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
end)
