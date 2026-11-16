-- tests/e2e/test_e2e_bootstrap_and_telemetry.lua
-- Scenario 1: GCS Channel Bootstrap & Realtime Telemetry Downlink Integration
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 1: GCS Bootstrap & Telemetry Downlink", function()
    it("completes full 40-channel bootstrap and fleet telemetry caching across GCS, AMM, and VAS", function()
        local bus = virtual_bus.create_bus({ clock = 1000.0 })

        local gcs = node_sandbox.create_node(bus, "GCS", "src/0_infra/gcs")
        local amm = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")

        -- 1. Initialize GCS app
        local gcs_main = gcs:require("main")
        local gcs_cfg = {
            system = { id = "GCS_01", domainId = "GCS_01", modemSide = "top" },
            channels = {
                bootstrapChannel = 50000,
                bandwidth = 40,
                baseChannelMin = 10000,
                baseChannelMax = 49960,
                maxCraftBlocks = 1000,
            },
            ui = { screenWidth = 51, screenHeight = 19, telemetryTimeoutSec = 5.0 },
        }
        local gcs_app = gcs_main.create_app(gcs_cfg, gcs.modem, "config/test_e2e_registry.json")
        assert_not_nil(gcs_app)
        assert_true(gcs.modem:isOpen(50000))

        -- 2. Negative Path Verification: Incompatible version & non-table rejection on CH 50000
        local ok_bad, err_bad = gcs_app:process_modem_message(50000, 50000, {
            ver = "0.9.0",
            domainId = "ROGUE_CRAFT",
            seq = 1,
            type = "MSG_BLOCK_REQUEST",
            time = 1000,
            payload = { domainId = "ROGUE_CRAFT", requestedBandwidth = 40 }
        })
        assert_false(ok_bad)
        assert_not_nil(err_bad)

        local ok_nontable, err_nontable = gcs_app:process_modem_message(50000, 50000, "INVALID_STRING_PACKET")
        assert_false(ok_nontable)
        assert_eq(err_nontable, "message is not a table")

        -- 3. Happy Path: AMM starts on bootstrap channel and requests 40-channel block
        local channel_sentinel = amm:require("channel_sentinel")
        local amm_state = channel_sentinel.init({
            system = { domainId = "AIRCRAFT_01", hardwareUuid = "HW-UUID-4401" },
            channels = { bootstrapChannel = 50000, bandwidth = 40 },
        })
        amm.modem:open(50000)

        local boot_req = channel_sentinel.start_bootstrap(amm_state, 1000)
        assert_eq(boot_req.type, "MSG_BLOCK_REQUEST")
        assert_eq(boot_req.payload.requestedBandwidth, 40)

        -- Transmit request from AMM to GCS on CH 50000
        amm.modem:transmit(50000, 50000, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 1,
            type = boot_req.type,
            time = 1000,
            payload = {
                domainId = "AIRCRAFT_01",
                hardwareUuid = "HW-UUID-4401",
                requestedBandwidth = boot_req.payload.requestedBandwidth,
            },
        })
        bus:step(0.05)

        -- Process inbound packet on GCS
        local gcs_inbox = gcs.modem:drain()
        assert_eq(#gcs_inbox, 1)
        local ok_proc = gcs_app:process_modem_message(gcs_inbox[1].channel, gcs_inbox[1].replyChannel, gcs_inbox[1].payload)
        assert_true(ok_proc)

        -- GCS should have transmitted MSG_BLOCK_ASSIGN on CH 50000
        bus:step(0.05)
        local assign_pkts = bus:find_packets({ type = "MSG_BLOCK_ASSIGN", channel = 50000 })
        assert_eq(#assign_pkts, 1)
        local assign_payload = assign_pkts[1].payload.payload
        assert_eq(assign_payload.blockId, 1)
        assert_eq(assign_payload.baseChannel, 10000)
        assert_eq(assign_payload.bandwidth, 40)

        -- 4. AMM receives assignment and commits Base=10000
        local amm_inbox = amm.modem:drain()
        assert_eq(#amm_inbox, 1)
        channel_sentinel.on_block_assign(amm_state, amm_inbox[1].payload.payload)
        assert_eq(amm_state.candidateBase, 10000)
        amm_state.baseChannel = amm_state.candidateBase

        -- AMM opens Base+0(10000), Base+1(10001), Base+2(10002), Base+3(10003), Base+4(10004), Base+5(10005)
        amm.modem:close(50000)
        amm.modem:open(10000)
        amm.modem:open(10001)
        amm.modem:open(10002)
        amm.modem:open(10003)
        amm.modem:open(10004)
        amm.modem:open(10005)

        -- Confirm GCS automatically opened telemetry downlink Base+3 (10003) upon assigning Block 1
        assert_true(gcs.modem:isOpen(10003))

        -- 5. VAS operates on Base=10000: opens Base+1(10001) and transmits telemetry on Base+2 (10002)
        vas.modem:open(10001)
        vas.modem:transmit(10002, 10002, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 10,
            type = "MSG_FLIGHT_TELEMETRY",
            time = 1050,
            payload = {
                attitude = { pitch = 2.5, roll = -1.0, heading = 180.0 },
                angularRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
                dynamics = { altitudeY = 125.0, verticalSpeed = 0.0, groundSpeed = 16.5 },
                fuel = 0.85,
                dynamicLoad = 0.0,
                controlState = "NORMAL",
                activeSource = "FCP",
                sensorOk = true,
                sensorHealth = { imu = true },
                actuatorHealth = { tap = true, asa = true, allOk = true },
            },
        })
        bus:step(0.05)

        -- AMM receives telemetry on 10002
        local amm_telem_inbox = amm.modem:drain()
        assert_eq(#amm_telem_inbox, 1)
        assert_eq(amm_telem_inbox[1].payload.type, "MSG_FLIGHT_TELEMETRY")

        -- 6. AMM aggregates telemetry and downlinks MSG_MFD_STATE on Base+3 (10003)
        amm.modem:transmit(10003, 10003, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 101,
            type = "MSG_MFD_STATE",
            time = 1060,
            payload = {
                fsmState = "CRUISE",
                flightMode = "AUTO_NAV",
                attitude = amm_telem_inbox[1].payload.payload.attitude,
                dynamics = amm_telem_inbox[1].payload.payload.dynamics,
                fuel = amm_telem_inbox[1].payload.payload.fuel,
                actuatorHealth = amm_telem_inbox[1].payload.payload.actuatorHealth,
            },
        })
        bus:step(0.05)

        -- 7. GCS receives MSG_MFD_STATE on Base+3 (10003) and updates fleet cache
        local gcs_telem_inbox = gcs.modem:drain()
        assert_eq(#gcs_telem_inbox, 1)
        local ok_tlm = gcs_app:process_modem_message(10003, 10003, gcs_telem_inbox[1].payload)
        assert_true(ok_tlm)

        local active_craft = gcs_app.fleet_tracker.get_active_craft(gcs_app.fleet)
        assert_not_nil(active_craft)
        assert_eq(active_craft.domainId, "AIRCRAFT_01")
        assert_eq(active_craft.baseChannel, 10000)
        assert_eq(active_craft.telemetry.fsmState, "CRUISE")
        assert_eq(active_craft.telemetry.dynamics.altitudeY, 125.0)
    end)

    it("handles sleeping occupant preferredBase, GCS REASSIGNED, 2-round probe CONFLICT_DETECTED renegotiation, and DENIED bandwidth", function()
        local bus = virtual_bus.create_bus({ clock = 2000.0 })

        local gcs = node_sandbox.create_node(bus, "GCS", "src/0_infra/gcs")
        local amm2 = node_sandbox.create_node(bus, "AMM_02", "src/3_planning/amm")
        local amm3 = node_sandbox.create_node(bus, "OCCUPANT_03", "src/3_planning/amm")

        -- In-memory VFS overlay on gcs.env.fs so persistent registry round-trips cleanly across GCS reboot
        local mem_files = {}
        local orig_gcs_fs = gcs.env.fs
        gcs.env.fs = {
            exists = function(p)
                if mem_files[p] ~= nil then return true end
                return orig_gcs_fs and orig_gcs_fs.exists and orig_gcs_fs.exists(p) or false
            end,
            isDir = function(p)
                return orig_gcs_fs and orig_gcs_fs.isDir and orig_gcs_fs.isDir(p) or false
            end,
            makeDir = function() return true end,
            getDir = function(p) return tostring(p):match("^(.*)/[^/]+$") or "" end,
            delete = function(p) mem_files[p] = nil end,
            move = function(src, dst)
                mem_files[dst] = mem_files[src]
                mem_files[src] = nil
            end,
            open = function(p, mode)
                if mode == "w" then
                    local buf = ""
                    return {
                        write = function(s) buf = buf .. tostring(s) end,
                        writeLine = function(s) buf = buf .. tostring(s) .. "\n" end,
                        flush = function() mem_files[p] = buf end,
                        close = function() mem_files[p] = buf end,
                    }
                elseif mem_files[p] ~= nil then
                    local data = mem_files[p]
                    return { readAll = function() return data end, close = function() end }
                elseif orig_gcs_fs and orig_gcs_fs.open then
                    return orig_gcs_fs.open(p, mode)
                end
                return nil
            end,
        }

        local gcs_main = gcs:require("main")
        local reg_path = "config/test_e2e_multi_registry.json"

        local gcs_cfg = {
            system = { id = "GCS_01", domainId = "GCS_01", modemSide = "top" },
            channels = {
                bootstrapChannel = 50000,
                bandwidth = 40,
                baseChannelMin = 10000,
                baseChannelMax = 49960,
                maxCraftBlocks = 1000,
            },
            ui = { screenWidth = 51, screenHeight = 19, telemetryTimeoutSec = 5.0 },
        }

        -- 1. Pre-register AIRCRAFT_01 (10000) then reboot GCS so AIRCRAFT_01 becomes a sleeping OFFLINE_RESERVED occupant
        local gcs_boot1 = gcs_main.create_app(gcs_cfg, gcs.modem, reg_path)
        local seed_res = gcs_boot1.channel_manager.allocate_block(
            gcs_boot1.channel_mgr, "AIRCRAFT_01", "HW-UUID-01", 40, nil, nil, 1500
        )
        assert_eq(seed_res.status, "ASSIGNED")
        assert_eq(seed_res.baseChannel, 10000)

        local gcs_app = gcs_main.create_app(gcs_cfg, gcs.modem, reg_path)
        local reserved_01 = gcs_app.channel_manager.get_allocation(gcs_app.channel_mgr, "AIRCRAFT_01")
        assert_not_nil(reserved_01)
        assert_eq(reserved_01.leaseState, "OFFLINE_RESERVED")
        assert_eq(reserved_01.baseChannel, 10000)

        -- 2. AIRCRAFT_02 boots with stale preferredBase=10000 -> GCS returns REASSIGNED to 10040
        local cs2 = amm2:require("channel_sentinel")
        local amm2_state = cs2.init({
            system = { domainId = "AIRCRAFT_02", hardwareUuid = "HW-UUID-02" },
            channels = { bootstrapChannel = 50000, bandwidth = 40 },
            safety = {
                probeJitterMaxMs = 20,
                probeInterRoundJitterMaxMs = 10,
                channelProbeWaitMs = 200,
                probeRetryCount = 2,
                maxReassignAttempts = 3,
            },
            leasePath = "config/test_e2e_amm2_lease.json",
        }, 2000)
        amm2_state.cachedBase = 10000
        amm2.modem:open(50000)

        local _, req1 = cs2.negotiate_and_probe(amm2_state, 2000)
        assert_eq(req1.type, "MSG_BLOCK_REQUEST")
        assert_eq(req1.payload.preferredBase, 10000)
        assert_eq(req1.payload.requestedBandwidth, 40)

        amm2.modem:transmit(50000, 50000, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_02",
            seq = 1,
            type = req1.type,
            time = 2000,
            payload = req1.payload,
        })
        bus:step(0.05)

        local gcs_in1 = gcs.modem:drain()
        assert_eq(#gcs_in1, 1)
        assert_true(gcs_app:process_modem_message(gcs_in1[1].channel, gcs_in1[1].replyChannel, gcs_in1[1].payload))
        bus:step(0.05)

        local amm2_in1 = amm2.modem:drain()
        assert_eq(#amm2_in1, 1)
        local assign1 = amm2_in1[1].payload.payload
        assert_eq(assign1.status, "REASSIGNED")
        assert_eq(assign1.baseChannel, 10040)
        assert_eq(assign1.reassignedFrom, 10000)

        local fixed_rng = function() return 10 end
        cs2.on_block_assign(amm2_state, assign1, 2010, fixed_rng)
        assert_eq(amm2_state.status, "JITTER_WAIT")
        assert_eq(amm2_state.candidateBase, 10040)

        -- Jitter gate: before 10ms elapses, no probe emitted
        local st_pre, pkt_pre = cs2.negotiate_and_probe(amm2_state, 2015, nil, fixed_rng)
        assert_eq(st_pre, "JITTER_WAIT")
        assert_nil(pkt_pre)

        -- After jitter, Round 1 probe emitted on 10040
        local st_p1, pkt_p1 = cs2.negotiate_and_probe(amm2_state, 2020, nil, fixed_rng)
        assert_eq(st_p1, "PROBING")
        assert_eq(amm2_state.probeRound, 1)
        assert_eq(pkt_p1.type, "MSG_CHANNEL_PROBE")
        assert_eq(pkt_p1.payload.candidateBase, 10040)

        -- 3. Active occupant on 10040 responds with CONFLICT_DETECTED -> AMM2 renegotiates with conflictBase=10040
        local cs3 = amm3:require("channel_sentinel")
        local occ_state = cs3.init({
            system = { domainId = "OCCUPANT_03", hardwareUuid = "HW-UUID-03" },
            channels = { baseChannel = 10040 },
            leasePath = "config/test_e2e_occ3_lease.json",
        }, 2000)
        occ_state.status = "ACQUIRED"
        occ_state.baseChannel = 10040

        amm2.modem:open(10040)
        amm3.modem:open(10040)
        amm2.modem:transmit(10040, 10040, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_02",
            seq = 2,
            type = pkt_p1.type,
            time = 2020,
            payload = pkt_p1.payload,
        })
        bus:step(0.05)

        local occ_in = amm3.modem:drain()
        assert_eq(#occ_in, 1)
        local ack_pkt = cs3.handle_incoming_probe(occ_state, occ_in[1].payload)
        assert_not_nil(ack_pkt)
        assert_eq(ack_pkt.type, "MSG_CHANNEL_PROBE_ACK")
        assert_eq(ack_pkt.payload.status, "CONFLICT_DETECTED")
        assert_eq(ack_pkt.payload.occupiedBase, 10040)

        amm3.modem:transmit(10040, 10040, {
            ver = "1.9.5",
            domainId = "OCCUPANT_03",
            seq = 1,
            type = ack_pkt.type,
            time = 2025,
            payload = ack_pkt.payload,
        })
        bus:step(0.05)

        local amm2_probe_in = amm2.modem:drain()
        assert_true(#amm2_probe_in >= 1)
        local ack_msg = amm2_probe_in[#amm2_probe_in].payload
        assert_true(cs2.on_probe_ack(amm2_state, ack_msg))
        assert_eq(amm2_state.status, "REASSIGN_REQUEST")
        assert_eq(amm2_state.conflictBase, 10040)
        assert_eq(amm2_state.reassignAttempts, 1)
        amm2.modem:close(10040)

        -- AMM2 requests reassignment with conflictBase=10040 -> GCS assigns 10080
        local _, req2 = cs2.negotiate_and_probe(amm2_state, 2030)
        assert_eq(req2.type, "MSG_BLOCK_REQUEST")
        assert_eq(req2.payload.conflictBase, 10040)

        amm2.modem:transmit(50000, 50000, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_02",
            seq = 3,
            type = req2.type,
            time = 2030,
            payload = req2.payload,
        })
        bus:step(0.05)

        local gcs_in2 = gcs.modem:drain()
        assert_eq(#gcs_in2, 1)
        assert_true(gcs_app:process_modem_message(gcs_in2[1].channel, gcs_in2[1].replyChannel, gcs_in2[1].payload))
        bus:step(0.05)

        local amm2_in2 = amm2.modem:drain()
        assert_eq(#amm2_in2, 1)
        local assign2 = amm2_in2[1].payload.payload
        assert_eq(assign2.status, "REASSIGNED")
        assert_eq(assign2.baseChannel, 10080)
        assert_eq(assign2.reassignedFrom, 10040)

        cs2.on_block_assign(amm2_state, assign2, 2040, fixed_rng)
        -- Complete initial jitter + 2 probe rounds with inter-round jitter -> ACQUIRED at 10080
        local _, pr1 = cs2.negotiate_and_probe(amm2_state, 2050, nil, fixed_rng)
        assert_eq(pr1.type, "MSG_CHANNEL_PROBE")
        assert_eq(pr1.payload.candidateBase, 10080)
        assert_eq(amm2_state.probeRound, 1)

        amm2.modem:open(10080)
        amm2.modem:transmit(10080, 10080, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 4, type = pr1.type, time = 2050, payload = pr1.payload,
        })
        bus:step(0.05)
        amm2.modem:drain()

        -- Round 1 silence elapses -> enters inter-round JITTER_WAIT
        local st_inter, _ = cs2.negotiate_and_probe(amm2_state, 2250, nil, fixed_rng)
        assert_eq(st_inter, "JITTER_WAIT")

        -- After inter-round jitter -> Round 2 probe emitted
        local _, pr2 = cs2.negotiate_and_probe(amm2_state, 2260, nil, fixed_rng)
        assert_eq(pr2.type, "MSG_CHANNEL_PROBE")
        assert_eq(amm2_state.probeRound, 2)
        amm2.modem:transmit(10080, 10080, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 5, type = pr2.type, time = 2260, payload = pr2.payload,
        })
        bus:step(0.05)
        amm2.modem:drain()

        -- Round 2 silence elapses -> ACQUIRED
        local st_acq, _ = cs2.negotiate_and_probe(amm2_state, 2460, nil, fixed_rng)
        assert_eq(st_acq, "ACQUIRED")
        assert_eq(amm2_state.baseChannel, 10080)
        assert_true(cs2.is_acquired(amm2_state))

        -- 4. Sleeping AIRCRAFT_01 wakes up with preferredBase=10000 and reclaims ASSIGNED 10000
        amm2.modem:transmit(50000, 50000, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 1,
            type = "MSG_BLOCK_REQUEST",
            time = 2500,
            payload = {
                domainId = "AIRCRAFT_01",
                hardwareUuid = "HW-UUID-01",
                requestedBandwidth = 40,
                preferredBase = 10000,
            },
        })
        bus:step(0.05)
        local gcs_in_wake = gcs.modem:drain()
        assert_eq(#gcs_in_wake, 1)
        assert_true(gcs_app:process_modem_message(gcs_in_wake[1].channel, gcs_in_wake[1].replyChannel, gcs_in_wake[1].payload))
        bus:step(0.05)
        local wake_assign = amm2.modem:drain()
        assert_eq(#wake_assign, 1)
        assert_eq(wake_assign[1].payload.payload.status, "ASSIGNED")
        assert_eq(wake_assign[1].payload.payload.baseChannel, 10000)

        -- 5. Invalid bandwidth (requestedBandwidth = 20) -> GCS emits DENIED and AMM locks
        assert_true(gcs_app:process_modem_message(50000, 50000, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_BAD",
            seq = 1,
            type = "MSG_BLOCK_REQUEST",
            time = 2600,
            payload = {
                domainId = "AIRCRAFT_BAD",
                hardwareUuid = "HW-UUID-BAD",
                requestedBandwidth = 20,
            },
        }))
        bus:step(0.05)
        local deny_inbox = amm2.modem:drain()
        assert_eq(#deny_inbox, 1)
        local deny_payload = deny_inbox[1].payload.payload
        assert_eq(deny_payload.status, "DENIED")
        assert_eq(deny_payload.reason, "INVALID_BANDWIDTH")

        local bad_state = cs2.init({ system = { domainId = "AIRCRAFT_BAD", hardwareUuid = "HW-UUID-BAD" } }, 2600)
        cs2.on_block_assign(bad_state, deny_payload, 2600)
        assert_eq(bad_state.status, "LOCKED_CONFLICT")
        assert_true(bad_state.locked)
        assert_eq(bad_state.conflictReason, "INVALID_BANDWIDTH")

        -- Clean up temporary registry/lease files inside sandbox
        for _, p in ipairs({ reg_path, "config/test_e2e_amm2_lease.json", "config/test_e2e_occ3_lease.json" }) do
            if gcs.env.fs and gcs.env.fs.exists and gcs.env.fs.exists(p) and gcs.env.fs.delete then
                gcs.env.fs.delete(p)
            end
        end
    end)
end)
