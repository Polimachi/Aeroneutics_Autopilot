-- Unit test suite for 2_guidance/fcp
local flight_fsm = require("flight_fsm")

describe("fcp config file staging and access", function()
    it("reads configuration from staged config/fcp_config.json", function()
        assert_true(fs.exists("config/fcp_config.json"), "config/fcp_config.json must exist in staged root")
        local f = fs.open("config/fcp_config.json", "r")
        assert_not_nil(f)
        local raw = f.readAll()
        f.close()
        local data = textutils.unserializeJSON(raw)
        assert_not_nil(data)
        assert_not_nil(data.system)
        assert_not_nil(data.channels)
        assert_not_nil(data.safety)
    end)

    it("validates vectored_vtol PID, slew-rate and sequence config fields", function()
        local f = fs.open("config/fcp_config.json", "r")
        local raw = f.readAll()
        f.close()
        local data = textutils.unserializeJSON(raw)
        assert_not_nil(data.guidance)
        local vv = data.guidance.vectored_vtol
        assert_not_nil(vv)
        assert_eq(vv.surgeKi, 0.02, "surgeKi default 0.02")
        assert_eq(vv.surgeMaxI, 0.20, "surgeMaxI default 0.20")
        assert_eq(vv.swayKi, 0.02, "swayKi default 0.02")
        assert_eq(vv.swayMaxI, 0.20, "swayMaxI default 0.20")
        assert_eq(vv.heaveKi, 0.02, "heaveKi default 0.02")
        assert_eq(vv.heaveMaxI, 0.20, "heaveMaxI default 0.20")
        assert_eq(vv.tiltSlewRateDegPerSec, 15.0, "tiltSlewRateDegPerSec default 15.0")
        assert_eq(vv.takeoffClearanceAltitudeM, 15.0, "takeoffClearanceAltitudeM default 15.0")
        assert_eq(vv.takeoffClimbRateMps, 2.5, "takeoffClimbRateMps default 2.5")
        assert_eq(vv.approachDescentRateMps, -1.5, "approachDescentRateMps default -1.5")
        assert_eq(vv.touchdownDescentRateMps, -0.5, "touchdownDescentRateMps default -0.5")
        assert_eq(vv.landingAlignDistanceM, 0.5, "landingAlignDistanceM default 0.5")
    end)
end)

describe("fcp config and main loader 40-channel baseline", function()
    it("validates 40-channel config fields in config/fcp_config.json", function()
        assert_true(fs.exists("config/fcp_config.json"), "config/fcp_config.json must exist in staged root")
        local f = fs.open("config/fcp_config.json", "r")
        assert_not_nil(f)
        local raw = f.readAll()
        f.close()
        local data = textutils.unserializeJSON(raw)
        assert_not_nil(data)
        assert_not_nil(data.channels)
        assert_eq(data.channels.baseChannel, 10000, "baseChannel must be 10000")
        assert_eq(data.channels.bandwidth, 40, "bandwidth must be 40")
        assert_eq(data.channels.mfdInstrumentChannel, 10003, "mfdInstrumentChannel must be 10003")
        assert_eq(data.channels.bootstrapChannel, 50000, "bootstrapChannel must be 50000")
        assert_eq(data.channels.gpsPingChannel, 60001, "gpsPingChannel must be 60001")
    end)

    it("loads config via fcp_main.load_config without sas_runtime error", function()
        local fcp_main = require("main")
        assert_not_nil(fcp_main, "require('main') must succeed")
        local loaded_cfg = fcp_main.load_config()
        assert_not_nil(loaded_cfg.channels, "fcp_main.load_config must return channels")
        assert_eq(loaded_cfg.channels.baseChannel, 10000, "fcp_main.load_config must return baseChannel 10000")
    end)
end)

describe("channel_sentinel 40-channel validation, bootstrap and rebind", function()
    local channel_sentinel = require("channel_sentinel")

    it("verifies baseChannel validation and normalization", function()
        assert_eq(channel_sentinel.is_valid_base(10000), true, "10000 is valid base")
        assert_eq(channel_sentinel.is_valid_base(10040), true, "10040 is valid base")
        assert_eq(channel_sentinel.is_valid_base(10060), false, "10060 is non-aligned legacy base")
        assert_eq(channel_sentinel.is_valid_base(9960), false, "below CRAFT_BASE_MIN")
        assert_eq(channel_sentinel.is_valid_base(50000), false, "above CRAFT_BASE_MAX")

        local default_state = channel_sentinel.init({})
        assert_eq(default_state.baseChannel, 10000, "default baseChannel must be 10000")
        assert_eq(default_state.bootstrapChannel, 50000, "default bootstrapChannel must be 50000")
        assert_eq(default_state.bandwidth, 40, "bandwidth must be 40")

        local bad_state = channel_sentinel.init({ channels = { baseChannel = 10060 } })
        assert_eq(bad_state.baseChannel, 10000, "non-aligned base 10060 must be normalized to 10000")
    end)

    it("generates 40-channel bootstrap and rebind packets", function()
        local state = channel_sentinel.init({ channels = { baseChannel = 10000 } })
        local boot_msg = channel_sentinel.start_bootstrap(state, 100)
        assert_eq(boot_msg.type, "MSG_BLOCK_REQUEST")
        assert_eq(boot_msg.requestedBandwidth, 40, "start_bootstrap requestedBandwidth must be 40")

        local rebind_msg = channel_sentinel.initiate_rebind(state, 10080, 200)
        assert_not_nil(rebind_msg, "initiate_rebind must succeed for valid base 10080")
        assert_eq(rebind_msg.type, "MSG_CHANNEL_REBIND")
        assert_eq(rebind_msg.payload.action, "PREPARE")
        assert_eq(rebind_msg.payload.newBaseChannel, 10080)
        assert_eq(rebind_msg.payload.bandwidth, 40, "rebind PREPARE bandwidth must be 40")

        local ack_handled = channel_sentinel.on_rebind_ack(state, {
            type = "MSG_CHANNEL_REBIND_ACK",
            payload = { transactionId = rebind_msg.payload.transactionId, status = "PREPARED" }
        }, 250)
        assert_true(ack_handled, "on_rebind_ack must return true for matching transactionId")

        local commit_msg, commit_st = channel_sentinel.step_rebind_transaction(state, 300)
        assert_eq(commit_st, "COMMITTED")
        assert_not_nil(commit_msg)
        assert_eq(commit_msg.payload.action, "COMMIT")
        assert_eq(commit_msg.payload.newBaseChannel, 10080)
        assert_eq(commit_msg.payload.bandwidth, 40, "rebind COMMIT bandwidth must be 40")
        assert_eq(state.baseChannel, 10080, "state.baseChannel must be updated to 10080")
        assert_nil(state.rebindTx, "rebindTx must be cleared upon COMMIT")

        -- Calling step_rebind_transaction again after timeout (>500ms) should NOT trigger spurious ROLLBACK
        local sp_msg, sp_st = channel_sentinel.step_rebind_transaction(state, 1000)
        assert_nil(sp_msg)
        assert_eq(sp_st, "NO_TRANSACTION")

        -- Test timeout on unacked PREPARE
        local rebind_msg2 = channel_sentinel.initiate_rebind(state, 10120, 2000)
        assert_not_nil(rebind_msg2)
        local rb_msg, rb_st = channel_sentinel.step_rebind_transaction(state, 2600)
        assert_eq(rb_st, "ROLLED_BACK")
        assert_not_nil(rb_msg)
        assert_eq(rb_msg.payload.action, "ROLLBACK")
        assert_nil(state.rebindTx, "rebindTx must be cleared upon ROLLBACK")
    end)
end)

describe("network_manager and fcp_runtime 40-channel binding and Base+5 GPS link", function()
    local network_manager = require("network_manager")
    local fcp_runtime = require("fcp_runtime")

    it("verifies bind_aircraft_channels and rebind_aircraft_channels", function()
        local opened = {}
        local closed = {}
        local mock_modem = {
            open = function(ch) opened[ch] = true; closed[ch] = nil end,
            close = function(ch) closed[ch] = true; opened[ch] = nil end,
            isOpen = function(ch) return opened[ch] == true end,
            transmit = function() end,
            isWireless = function() return true end,
        }
        local net = network_manager.init({ channels = { baseChannel = 10000, bandwidth = 40 } }, function() return mock_modem end)
        network_manager.bind_aircraft_channels(net, 10000)

        for off = 0, 5 do
            assert_true(opened[10000 + off], "channel " .. tostring(10000 + off) .. " must be opened")
        end

        network_manager.rebind_aircraft_channels(net, 10040)
        for off = 0, 5 do
            assert_true(closed[10000 + off], "old channel " .. tostring(10000 + off) .. " must be closed")
            assert_true(opened[10040 + off], "new channel " .. tostring(10040 + off) .. " must be opened")
        end
        assert_eq(net.baseChannel, 10040)
        assert_eq(net.mfdInstrumentChannel, 10043)
    end)

    it("verifies GPS request format and nav_engine MSG_GPS_RESPONSE 2D fusion", function()
        local transmitted = {}
        local mock_modem = {
            open = function() end,
            close = function() end,
            isOpen = function() return true end,
            transmit = function(ch, reply_ch, payload)
                table.insert(transmitted, { channel = ch, replyChannel = reply_ch, payload = payload })
            end,
            isWireless = function() return true end,
        }
        local ctx = fcp_runtime.create_context({
            channels = { baseChannel = 10000, bandwidth = 40, gpsPingChannel = 60001 },
            navigation = { drComplementaryAlpha = 0.5 }
        }, function() return mock_modem end)

        ctx.nav.pos = { x = 0.0, y = 80.0, z = 0.0 }
        fcp_runtime.step_tick(ctx, 0.05, 1000)

        local gps_tx = nil
        for _, tx in ipairs(transmitted) do
            if tx.channel == 60001 then
                gps_tx = tx
                break
            end
        end
        assert_not_nil(gps_tx, "MSG_GPS_REQUEST must be sent to CH 60001")
        assert_eq(gps_tx.replyChannel, 10005, "replyChannel must be Base+5 (10005)")
        local req_payload = gps_tx.payload.payload
        assert_not_nil(req_payload)
        assert_eq(req_payload.replyChannel, 10005)
        assert_eq(req_payload.altitudeY, 80.0)
        assert_eq(req_payload.clientType, "AIRCRAFT")
        assert_not_nil(req_payload.clientSeq)

        local gps_resp = {
            ver = "1.9.5",
            domainId = "GPS_BASE_NET",
            senderId = "INFRA-01",
            type = "MSG_GPS_RESPONSE",
            seq = 1,
            timestamp = 1050,
            payload = {
                targetClient = "AIRCRAFT_01",
                clientSeq = req_payload.clientSeq,
                status = "FIX_OK",
                position = { x = 4.0, z = -3.0 },
                accuracy = 0.2,
                hdop = 1.1,
                nodeCount = 4,
                selectedNodes = { "NODE_01", "NODE_02", "NODE_03", "NODE_04" }
            }
        }
        local accepted = network_manager.ingest_modem_event(ctx.net, "back", 10005, 60001, gps_resp, 10, 1100)
        assert_true(accepted, "network_manager must accept MSG_GPS_RESPONSE from GPS_BASE_NET on 10005")

        fcp_runtime.step_tick(ctx, 0.05, 1200)

        assert_eq(ctx.nav.pos.y, 80.0, "onboard altitude must be preserved (not overwritten by 2D GPS)")
        assert_true(ctx.nav.pos.x > 0.0, "nav_engine horizontal X must be updated via complementary filter")
        assert_true(ctx.nav.pos.z < 0.0, "nav_engine horizontal Z must be updated via complementary filter")
    end)
end)

describe("fcp flight FSM state transitions and failsafes", function()
    it("transitions through ground sequence BOOT_INIT -> TAKEOFF", function()
        local fsm = flight_fsm.init({
            system = { airframeType = "VECTORED_VTOL" },
            safety = { emergencyLandFuelThreshold = 0.10, lowFuelRthThreshold = 0.20 }
        })
        assert_eq(fsm.current_state, "BOOT_INIT")
        assert_false(fsm.inFlight)

        flight_fsm.evaluate(fsm, { channelAcquired = true })
        assert_eq(fsm.current_state, "DISARMED")

        flight_fsm.evaluate(fsm, { cmd = "ARM" })
        assert_eq(fsm.current_state, "ARMING")

        flight_fsm.evaluate(fsm, { coreArmed = true })
        assert_eq(fsm.current_state, "IDLE_ARMED")

        flight_fsm.evaluate(fsm, { cmd = "TAKEOFF", takeoffGate = { allowed = true } })
        assert_eq(fsm.current_state, "TAKEOFF")
        assert_true(fsm.inFlight)
    end)

    it("triggers EMERGENCY_LAND on critical fuel drop during flight", function()
        local fsm = flight_fsm.init({
            safety = { emergencyLandFuelThreshold = 0.10, lowFuelRthThreshold = 0.20 }
        })
        flight_fsm.transition_to(fsm, "CRUISE")
        assert_true(fsm.inFlight)

        local action = flight_fsm.check_failsafes(fsm, { fuel = 0.05 })
        assert_eq(action, "EMERGENCY_LAND")
        assert_eq(fsm.current_state, "EMERGENCY_LAND")
        assert_eq(fsm.lockReason, "CRITICAL_LOW_FUEL")
    end)
end)


describe("fcp asa exclusion for vectored_vtol and drone", function()
    local guidance_controller = require("guidance_controller")
    local aerodynamic_controller = require("aerodynamic_controller")

    it("ensures flapTarget is strictly 0.0 for VECTORED_VTOL, QUADROTOR, and HEXAROTOR", function()
        local non_aero_types = { "VECTORED_VTOL", "QUADROTOR", "HEXAROTOR" }
        for _, af in ipairs(non_aero_types) do
            local state = guidance_controller.init({ system = { airframeType = af } })
            local cmd_takeoff = guidance_controller.pack_attitude_cmd(state, {}, "TAKEOFF", true)
            assert_eq(cmd_takeoff.flapTarget, 0.0, "flapTarget must be 0.0 for " .. af .. " in TAKEOFF")

            local cmd_land = guidance_controller.pack_attitude_cmd(state, {}, "APPROACH_LAND", true)
            assert_eq(cmd_land.flapTarget, 0.0, "flapTarget must be 0.0 for " .. af .. " in APPROACH_LAND")

            assert_false(aerodynamic_controller.is_enabled_for_airframe(af), "aerodynamic_controller must be disabled for " .. af)
            local pkt = aerodynamic_controller.build_surface_packet({ airframeType = af }, { aileron = 1.0 })
            assert_nil(pkt, "build_surface_packet must be nil for " .. af)
        end
    end)

    it("allows flapTarget scheduling for FIXED_WING and WINGED_VTOL", function()
        local aero_types = { "FIXED_WING", "WINGED_VTOL" }
        for _, af in ipairs(aero_types) do
            local state = guidance_controller.init({ system = { airframeType = af } })
            local cmd_takeoff = guidance_controller.pack_attitude_cmd(state, {}, "TAKEOFF", true)
            assert_eq(cmd_takeoff.flapTarget, 0.35, "flapTarget must be 0.35 for " .. af .. " in TAKEOFF")

            local cmd_land = guidance_controller.pack_attitude_cmd(state, {}, "APPROACH_LAND", true)
            assert_eq(cmd_land.flapTarget, 1.0, "flapTarget must be 1.0 for " .. af .. " in APPROACH_LAND")

            assert_true(aerodynamic_controller.is_enabled_for_airframe(af), "aerodynamic_controller must be enabled for " .. af)
        end
    end)
end)
