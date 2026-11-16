-- Unit test suite for 0_infra/gcs channel manager and registry

describe("gcs config and registry files", function()
    it("reads configuration from staged config/gcs_config.json", function()
        assert_true(fs.exists("config/gcs_config.json"), "config/gcs_config.json must exist in staged root")
        local f = fs.open("config/gcs_config.json", "r")
        assert_not_nil(f)
        local raw = f.readAll()
        f.close()
        local data = textutils.unserializeJSON(raw)
        assert_not_nil(data)
        assert_not_nil(data.system)
        assert_eq(data.system.id, "GCS_01")
        assert_not_nil(data.channels)
        assert_eq(data.channels.bootstrapChannel, 50000, "bootstrapChannel must be 50000")
        assert_eq(data.channels.bandwidth, 40, "bandwidth must be 40")
        assert_eq(data.channels.baseChannelMin, 10000, "baseChannelMin must be 10000")
        assert_eq(data.channels.baseChannelMax, 49960, "baseChannelMax must be 49960")
    end)

    it("verifies empty initial registry in config/channel_registry.json", function()
        assert_true(fs.exists("config/channel_registry.json"), "config/channel_registry.json must exist")
        local f = fs.open("config/channel_registry.json", "r")
        assert_not_nil(f)
        local raw = f.readAll()
        f.close()
        local data = textutils.unserializeJSON(raw)
        assert_not_nil(data)
        assert_not_nil(data.allocations, "registry must contain allocations table")
    end)
end)

describe("channel_manager 40-channel block sticky allocator", function()
    local channel_manager = require("channel_manager")

    it("verifies compute_base and is_valid_base", function()
        assert_eq(channel_manager.compute_base(1), 10000)
        assert_eq(channel_manager.compute_base(2), 10040)
        assert_eq(channel_manager.compute_base(1000), 49960)
        assert_nil(channel_manager.compute_base(1001))
        assert_nil(channel_manager.compute_base(0))

        assert_true(channel_manager.is_valid_base(10000))
        assert_true(channel_manager.is_valid_base(10040))
        assert_true(channel_manager.is_valid_base(49960))
        assert_false(channel_manager.is_valid_base(10060))
        assert_false(channel_manager.is_valid_base(9960))
        assert_false(channel_manager.is_valid_base(50000))
    end)

    it("allocates sticky blocks and enforces reuse", function()
        local state = channel_manager.init({
            channels = { baseChannelMin = 10000, baseChannelMax = 49960, bandwidth = 40, maxCraftBlocks = 1000 }
        }, "config/test_registry.json")

        local res1 = channel_manager.allocate_block(state, "AIRCRAFT_01", "UUID-1", 40)
        assert_eq(res1.status, "ASSIGNED")
        assert_eq(res1.blockId, 1)
        assert_eq(res1.baseChannel, 10000)
        assert_eq(res1.bandwidth, 40)
        assert_eq(res1.channelRange.start, 10000)
        assert_eq(res1.channelRange["end"], 10039)

        -- Re-allocating same craft must return same sticky assignment
        local res1_repeat = channel_manager.allocate_block(state, "AIRCRAFT_01", "UUID-1", 40)
        assert_eq(res1_repeat.status, "ASSIGNED")
        assert_eq(res1_repeat.blockId, 1)
        assert_eq(res1_repeat.baseChannel, 10000)

        -- New craft gets next block
        local res2 = channel_manager.allocate_block(state, "AIRCRAFT_02", "UUID-2", 40)
        assert_eq(res2.status, "ASSIGNED")
        assert_eq(res2.blockId, 2)
        assert_eq(res2.baseChannel, 10040)

        -- Release AIRCRAFT_01 and reallocate
        assert_true(channel_manager.release_block(state, "AIRCRAFT_01"))
        assert_nil(channel_manager.get_allocation(state, "AIRCRAFT_01"))

        -- Now block 1 is lowest free, next new craft gets block 1
        local res3 = channel_manager.allocate_block(state, "AIRCRAFT_03", "UUID-3", 40)
        assert_eq(res3.blockId, 1)
        assert_eq(res3.baseChannel, 10000)

        -- Cleanup test file if created
        if fs.exists("config/test_registry.json") then fs.delete("config/test_registry.json") end
    end)

    it("rejects variable requestedBandwidth ~= 40 with DENIED and does not persist", function()
        local reg_path = "config/test_bw_deny_registry.json"
        if fs.exists(reg_path) then fs.delete(reg_path) end

        local state = channel_manager.init({
            channels = { baseChannelMin = 10000, baseChannelMax = 49960, bandwidth = 40, maxCraftBlocks = 1000 }
        }, reg_path)

        local res20 = channel_manager.allocate_block(state, "AIRCRAFT_04", "UUID-4", 20)
        assert_eq(res20.status, "DENIED")
        assert_eq(res20.reason, "INVALID_BANDWIDTH")
        assert_eq(res20.bandwidth, 40)
        assert_nil(channel_manager.get_allocation(state, "AIRCRAFT_04"))

        local res80 = channel_manager.allocate_block(state, "AIRCRAFT_04", "UUID-4", 80)
        assert_eq(res80.status, "DENIED")
        assert_eq(res80.reason, "INVALID_BANDWIDTH")
        assert_nil(channel_manager.get_allocation(state, "AIRCRAFT_04"))
        assert_false(fs.exists(reg_path), "denied allocation must not create/record registry")

        if fs.exists(reg_path) then fs.delete(reg_path) end
    end)

    it("validates Rule 2 single boundary via is_valid_block_range and 4-arg ranges_overlap", function()
        assert_true(channel_manager.is_valid_block_range(10000))
        assert_true(channel_manager.is_valid_block_range(10040))
        assert_true(channel_manager.is_valid_block_range(49960))
        assert_false(channel_manager.is_valid_block_range(50000))
        assert_false(channel_manager.is_valid_block_range(49980))
        assert_false(channel_manager.is_valid_block_range(9960))
        assert_false(channel_manager.is_valid_block_range(10020))

        assert_true(channel_manager.ranges_overlap(10000, 40, 10020, 40))
        assert_true(channel_manager.ranges_overlap(10000, 40, 10039, 40))
        assert_false(channel_manager.ranges_overlap(10000, 40, 10040, 40))
        assert_false(channel_manager.ranges_overlap(10040, 40, 10000, 40))
    end)

    it("returns REASSIGNED on preferredBase or conflictBase collision and FAILED when exhausted", function()
        local reg_path = "config/test_reassign_registry.json"
        if fs.exists(reg_path) then fs.delete(reg_path) end

        local state = channel_manager.init({
            channels = { baseChannelMin = 10000, baseChannelMax = 49960, bandwidth = 40, maxCraftBlocks = 1000 }
        }, reg_path)

        local r1 = channel_manager.allocate_block(state, "AIRCRAFT_01", "UUID-1", 40, nil, nil, 1000)
        assert_eq(r1.status, "ASSIGNED")
        assert_eq(r1.baseChannel, 10000)

        -- Another craft requests preferredBase = 10000 -> REASSIGNED to Block 2 (10040)
        local r2 = channel_manager.allocate_block(state, "AIRCRAFT_02", "UUID-2", 40, 10000, nil, 2000)
        assert_eq(r2.status, "REASSIGNED")
        assert_eq(r2.reassignedFrom, 10000)
        assert_eq(r2.baseChannel, 10040)
        assert_eq(r2.blockId, 2)

        -- Craft 3 reports conflictBase = 10080 -> skips 10080 and gets Block 4 (10120)
        local r3 = channel_manager.allocate_block(state, "AIRCRAFT_03", "UUID-3", 40, nil, 10080, 3000)
        assert_eq(r3.status, "REASSIGNED")
        assert_eq(r3.reassignedFrom, 10080)
        assert_eq(r3.baseChannel, 10120)
        assert_eq(r3.blockId, 4)

        -- Exhaustion check
        local small_state = channel_manager.init({
            channels = { baseChannelMin = 10000, baseChannelMax = 49960, bandwidth = 40, maxCraftBlocks = 1 }
        }, "config/test_exhaust_registry.json")
        local ok1 = channel_manager.allocate_block(small_state, "C1", "U1", 40)
        assert_eq(ok1.status, "ASSIGNED")
        local fail2 = channel_manager.allocate_block(small_state, "C2", "U2", 40)
        assert_eq(fail2.status, "FAILED")
        assert_eq(fail2.reason, "NO_FREE_BLOCK")

        if fs.exists(reg_path) then fs.delete(reg_path) end
        if fs.exists("config/test_exhaust_registry.json") then fs.delete("config/test_exhaust_registry.json") end
    end)

    it("protects sleeping occupant persistent lease across GCS restarts and validates UUID on preferredBase", function()
        local reg_path = "config/test_persist_lease.json"
        if fs.exists(reg_path) then fs.delete(reg_path) end

        local cfg = {
            channels = { baseChannelMin = 10000, baseChannelMax = 49960, bandwidth = 40, maxCraftBlocks = 1000 }
        }
        local state1 = channel_manager.init(cfg, reg_path)
        local r1 = channel_manager.allocate_block(state1, "AIRCRAFT_01", "UUID-1", 40, nil, nil, 5000)
        assert_eq(r1.status, "ASSIGNED")
        assert_eq(r1.baseChannel, 10000)
        assert_eq(r1.leaseState, "ACTIVE_LEASE")

        -- Simulate GCS restart: reload registry into fresh state2
        local state2 = channel_manager.init(cfg, reg_path)
        local persisted = channel_manager.get_allocation(state2, "AIRCRAFT_01")
        assert_not_nil(persisted)
        assert_true(persisted.leaseState == "OFFLINE_RESERVED" or persisted.leaseState == "ACTIVE_LEASE")
        assert_eq(persisted.lastSeenMs, 5000)

        -- New craft AIRCRAFT_05 must NOT hijack Block 1
        local r5 = channel_manager.allocate_block(state2, "AIRCRAFT_05", "UUID-5", 40, nil, nil, 6000)
        assert_eq(r5.status, "ASSIGNED")
        assert_eq(r5.blockId, 2)
        assert_eq(r5.baseChannel, 10040)

        -- Different hardwareUuid requesting preferredBase = 10000 gets REASSIGNED to Block 3 (10080)
        local r_mismatch = channel_manager.allocate_block(state2, "AIRCRAFT_06", "UUID-NEW", 40, 10000, nil, 7000)
        assert_eq(r_mismatch.status, "REASSIGNED")
        assert_eq(r_mismatch.reassignedFrom, 10000)
        assert_eq(r_mismatch.blockId, 3)
        assert_eq(r_mismatch.baseChannel, 10080)

        -- Same domainId + different hardwareUuid requesting preferredBase = 10000 also cannot steal Block 1
        local r_hijack = channel_manager.allocate_block(state2, "AIRCRAFT_01", "UUID-HIJACK", 40, 10000, nil, 7500)
        assert_eq(r_hijack.status, "REASSIGNED")
        assert_eq(r_hijack.reassignedFrom, 10000)
        assert_eq(r_hijack.baseChannel, 10120)

        -- Original craft AIRCRAFT_01 reboots with preferredBase = 10000 and matching UUID-1 -> ASSIGNED Block 1
        local r1_reconfirm = channel_manager.allocate_block(state2, "AIRCRAFT_01", "UUID-1", 40, 10000, nil, 8000)
        assert_eq(r1_reconfirm.status, "ASSIGNED")
        assert_eq(r1_reconfirm.blockId, 1)
        assert_eq(r1_reconfirm.baseChannel, 10000)
        assert_eq(r1_reconfirm.leaseState, "ACTIVE_LEASE")

        -- Explicit release frees Block 1 for subsequent craft
        assert_true(channel_manager.release_block(state2, "AIRCRAFT_01"))
        local r7 = channel_manager.allocate_block(state2, "AIRCRAFT_07", "UUID-7", 40, nil, nil, 9000)
        assert_eq(r7.blockId, 1)
        assert_eq(r7.baseChannel, 10000)

        if fs.exists(reg_path) then fs.delete(reg_path) end
    end)
end)
