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

    it("validates on_block_assign candidate base assignment (MUT-03)", function()
        local state = channel_sentinel.init({ channels = { baseChannel = 10000 } })
        channel_sentinel.on_block_assign(state, { baseChannel = 10040 })
        assert_eq(state.candidateBase, 10040, "candidateBase must be assigned to 10040")
        assert_eq(state.status, "START_PROBE")
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
        local non_aero_types = { "VECTORED_VTOL", "ADVANCED_VTOL", "QUADROTOR", "HEXAROTOR" }
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

describe("vectored_vtol 3-axis PID and anti-windup integration", function()
    local vectored_vtol_driver = require("vectored_vtol_driver")
    local main = require("main")
    local cfg = main.load_config()

    it("accumulates error into driver_state integrals and clamps to maxI", function()
        local nav = {
            pos = { x = 0.0, y = 64.0, z = 0.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local target = { x = 0.0, y = 74.0, z = -10.0 }
        local driver_state = {}

        local out1 = vectored_vtol_driver.compute(cfg, nav, target, "CRUISE", 1.0, driver_state)
        assert_not_nil(out1)
        assert_not_nil(driver_state.surge_i, "driver_state.surge_i must exist")
        assert_eq(driver_state.surge_i, 0.20, "surge_i reached maxI 0.20")
        assert_eq(driver_state.heave_i, 0.20, "heave_i reached maxI 0.20")

        vectored_vtol_driver.compute(cfg, nav, target, "CRUISE", 1.0, driver_state)
        assert_eq(driver_state.surge_i, 0.20, "surge_i clamped to maxI 0.20")
        assert_eq(driver_state.heave_i, 0.20, "heave_i clamped to maxI 0.20")

        assert_not_nil(vectored_vtol_driver.reset_integrals, "reset_integrals function must exist")
        vectored_vtol_driver.reset_integrals(driver_state)
        assert_eq(driver_state.surge_i, 0.0, "surge_i reset to 0.0")
        assert_eq(driver_state.sway_i, 0.0, "sway_i reset to 0.0")
        assert_eq(driver_state.heave_i, 0.0, "heave_i reset to 0.0")
    end)
end)

describe("vectored_vtol tilt slew-rate limiter and strict level interlock", function()
    local vectored_vtol_driver = require("vectored_vtol_driver")
    local main = require("main")
    local cfg = main.load_config()
    cfg.guidance.vectored_vtol.envelopeMode = "TILT_ASSISTED"

    it("smoothly slews pitch in CRUISE at high speed without step jump", function()
        local nav = {
            pos = { x = 0.0, y = 64.0, z = 0.0 },
            vel = { x = 20.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 20.0,
        }
        local target = { x = 0.0, y = 64.0, z = -100.0 }
        local driver_state = { current_pitch = 0.0 }

        local out1 = vectored_vtol_driver.compute(cfg, nav, target, "CRUISE", 0.05, driver_state)
        assert_not_nil(out1)
        assert_true(out1.targetPitch >= -0.76 and out1.targetPitch <= -0.74, "targetPitch slewed by 0.75 deg")
        assert_eq(driver_state.current_pitch, out1.targetPitch)
    end)

    it("enforces STRICT_LEVEL pitch 0.0 in non-CRUISE modes even at high speed", function()
        local nav = {
            pos = { x = 0.0, y = 64.0, z = 0.0 },
            vel = { x = 20.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 20.0,
        }
        local target = { x = 0.0, y = 64.0, z = -100.0 }
        local driver_state = { current_pitch = -5.0 }

        local out_to = vectored_vtol_driver.compute(cfg, nav, target, "TAKEOFF", 1.0, driver_state)
        assert_eq(out_to.targetPitch, 0.0, "TAKEOFF must enforce strict level 0.0 pitch")

        local out_land = vectored_vtol_driver.compute(cfg, nav, target, "APPROACH_LAND", 1.0, driver_state)
        assert_eq(out_land.targetPitch, 0.0, "APPROACH_LAND must enforce strict level 0.0 pitch")
    end)
end)

describe("vectored_vtol takeoff horizontal lock and approach 2-stage descent", function()
    local vectored_vtol_driver = require("vectored_vtol_driver")
    local main = require("main")
    local cfg = main.load_config()

    it("locks horizontal surge and sway to 0.0 during TAKEOFF until safe altitude", function()
        local nav = {
            pos = { x = 0.0, y = 64.0, z = 0.0 },
            vel = { x = 0.0, y = 1.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local target = { x = 50.0, y = 100.0, z = -50.0 }
        local driver_state = {}

        local out_to = vectored_vtol_driver.compute(cfg, nav, target, "TAKEOFF", 0.05, driver_state)
        assert_eq(out_to.surge, 0.0, "surge must be locked to 0.0 in TAKEOFF below clearance")
        assert_eq(out_to.sway, 0.0, "sway must be locked to 0.0 in TAKEOFF below clearance")
        assert_eq(out_to.targetPitch, 0.0, "targetPitch must be 0.0 in TAKEOFF")
        assert_eq(out_to.targetRoll, 0.0, "targetRoll must be 0.0 in TAKEOFF")
        assert_eq(out_to.targetClimbRate, 2.5, "targetClimbRate must be takeoffClimbRateMps (2.5)")

        nav.pos.y = 80.0
        local out_to_cleared = vectored_vtol_driver.compute(cfg, nav, target, "TAKEOFF", 0.05, driver_state)
        assert_true(out_to_cleared.surge > 0.0, "surge released once clearance altitude reached")
    end)

    it("stages descent rate in APPROACH_LAND based on landingAlignDistanceM (0.5m)", function()
        local nav = {
            pos = { x = 0.0, y = 70.0, z = 0.0 },
            vel = { x = 0.0, y = -1.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local driver_state = {}
        local target_far = { x = 3.0, y = 64.0, z = 4.0 }
        local out_align = vectored_vtol_driver.compute(cfg, nav, target_far, "APPROACH_LAND", 0.05, driver_state)
        assert_eq(out_align.targetClimbRate, -1.5, "approachDescentRateMps (-1.5) when unaligned")
        assert_eq(out_align.targetPitch, 0.0)

        local target_near = { x = 0.1, y = 64.0, z = 0.1 }
        local out_touchdown = vectored_vtol_driver.compute(cfg, nav, target_near, "APPROACH_LAND", 0.05, driver_state)
        assert_eq(out_touchdown.targetClimbRate, -0.5, "touchdownDescentRateMps (-0.5) when aligned")
        assert_eq(out_touchdown.targetPitch, 0.0)
    end)
end)

describe("flight_fsm POI_HOLD and LOITER mode transitions", function()
    it("transitions cleanly among CRUISE, LOITER, POI_HOLD, and APPROACH_LAND while keeping inFlight active", function()
        local fsm = flight_fsm.init({ system = { airframeType = "VECTORED_VTOL" } })
        flight_fsm.transition_to(fsm, "CRUISE")
        assert_true(flight_fsm.is_flight_active(fsm))
        assert_true(flight_fsm.is_armed(fsm))

        flight_fsm.evaluate(fsm, { cmd = "POI_HOLD" }, 1000)
        assert_eq(fsm.current_state, "POI_HOLD")
        assert_true(fsm.inFlight)
        assert_true(flight_fsm.is_flight_active(fsm))
        assert_true(flight_fsm.is_armed(fsm))

        flight_fsm.evaluate(fsm, { cmd = "LOITER" }, 1050)
        assert_eq(fsm.current_state, "LOITER")

        flight_fsm.evaluate(fsm, { cmd = "POI_HOLD" }, 1100)
        assert_eq(fsm.current_state, "POI_HOLD")

        flight_fsm.evaluate(fsm, { cmd = "CRUISE" }, 1150)
        assert_eq(fsm.current_state, "CRUISE")

        flight_fsm.transition_to(fsm, "POI_HOLD")
        flight_fsm.evaluate(fsm, { atcStatus = "CLEARED" }, 1200)
        assert_eq(fsm.current_state, "APPROACH_LAND")
    end)
end)

describe("vectored_vtol_driver LOITER CW/CCW orbit and POI_HOLD aiming primitives", function()
    local vectored_vtol_driver = require("vectored_vtol_driver")
    local main = require("main")
    local cfg = main.load_config()

    it("drives tangential East (+X) velocity in CW LOITER and West (-X) velocity in CCW LOITER when North of center", function()
        local prev_env = cfg.guidance.vectored_vtol.envelopeMode
        cfg.guidance.vectored_vtol.envelopeMode = "TILT_ASSISTED"
        -- Craft is at (0, 100, -30), which is exactly 30m North of center (0, 100, 0), facing North (heading = 0)
        local nav = {
            pos = { x = 0.0, y = 100.0, z = -30.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 18.0,
        }
        local target_cw = {
            x = 0.0, y = 100.0, z = 0.0,
            loiterRadius = 30.0,
            loiterDirection = "CW",
            targetSpeed = 8.0,
            headingMode = "AUTO",
        }
        local ds_cw = { prev_heading = 0.0, current_pitch = 0.0 }
        local out_cw = vectored_vtol_driver.compute(cfg, nav, target_cw, "LOITER", 0.05, ds_cw)
        -- Facing North (0 deg), Eastward (+X) tangent demand projects to positive sway (+right)
        assert_true(out_cw.sway > 0.0, "CW loiter at North of center must command positive sway (East), got " .. tostring(out_cw.sway))
        assert_eq(out_cw.targetPitch, 0.0, "LOITER must enforce STRICT_LEVEL pitch 0.0 even when TILT_ASSISTED is configured")
        assert_eq(out_cw.targetRoll, 0.0, "LOITER must enforce STRICT_LEVEL roll 0.0")
        assert_true(out_cw.targetHeading > 0.0 and out_cw.targetHeading <= 1.51, "Heading must slew toward 90 deg East tangent")

        local target_ccw = {
            x = 0.0, y = 100.0, z = 0.0,
            loiterRadius = 30.0,
            loiterDirection = "CCW",
            targetSpeed = 8.0,
            headingMode = "AUTO",
        }
        local ds_ccw = { prev_heading = 0.0, current_pitch = 0.0 }
        local out_ccw = vectored_vtol_driver.compute(cfg, nav, target_ccw, "LOITER", 0.05, ds_ccw)
        cfg.guidance.vectored_vtol.envelopeMode = prev_env
        -- Facing North (0 deg), Westward (-X) tangent demand projects to negative sway (-left)
        assert_true(out_ccw.sway < 0.0, "CCW loiter at North of center must command negative sway (West), got " .. tostring(out_ccw.sway))
        assert_true(out_ccw.targetHeading >= 358.49 and out_ccw.targetHeading < 360.0, "Heading must slew toward 270 deg West tangent")
    end)

    it("pulls craft inward when outside loiterRadius and handles zero-distance center singularity", function()
        -- Craft is 50m North of center (0, 100, -50), facing North (0 deg); loiterRadius = 30m -> r_err = -20m (Southward / backward)
        local nav = {
            pos = { x = 0.0, y = 100.0, z = -50.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local target = { x = 0.0, y = 100.0, z = 0.0, loiterRadius = 30.0, loiterDirection = "CW", targetSpeed = 8.0 }
        local out = vectored_vtol_driver.compute(cfg, nav, target, "LOITER", 0.05, {})
        assert_true(out.surge < 0.0, "Outside orbit radius while facing North (away from center) must command negative surge toward center")
        assert_true(out.sway > 0.0, "CW LOITER while pulling inward must simultaneously command positive sway")

        -- Singularity check: craft exactly at center (0, 100, 0)
        nav.pos = { x = 0.0, y = 100.0, z = 0.0 }
        local out_center = vectored_vtol_driver.compute(cfg, nav, target, "LOITER", 0.05, { prev_heading = 45.0 })
        assert_true(out_center.surge == out_center.surge and out_center.sway == out_center.sway, "Must not produce NaN at d_center == 0")
        assert_true(out_center.targetHeading == out_center.targetHeading, "targetHeading must not be NaN at d_center == 0")
        assert_true(out_center.surge > 0.0, "At center d_center == 0, default North fallback must command outward surge toward orbit radius")
    end)

    it("holds position and slews heading toward poiTarget in POI_HOLD and FIXED heading modes", function()
        local nav = {
            pos = { x = 10.0, y = 100.0, z = 10.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        -- Hold at (10, 100, 10), aim at POI (110, 64, 10) which is due East (+X -> 90 deg)
        local poi_target = {
            x = 10.0, y = 100.0, z = 10.0,
            poiTarget = { x = 110.0, y = 64.0, z = 10.0 },
        }
        local ds = { prev_heading = 0.0 }
        local out_poi = vectored_vtol_driver.compute(cfg, nav, poi_target, "POI_HOLD", 0.05, ds)
        assert_eq(out_poi.surge, 0.0, "Zero position error in POI_HOLD must yield 0.0 surge")
        assert_eq(out_poi.sway, 0.0, "Zero position error in POI_HOLD must yield 0.0 sway")
        assert_eq(out_poi.targetPitch, 0.0, "POI_HOLD must maintain 0.0 pitch")
        assert_eq(out_poi.targetRoll, 0.0, "POI_HOLD must maintain 0.0 roll")
        -- 30 deg/s * 0.05s = 1.5 deg step toward 90 deg
        assert_true(math.abs(out_poi.targetHeading - 1.5) < 0.01, "Heading must slew by +1.5 deg toward East POI")

        -- FIXED heading mode in CRUISE aiming at 270 deg
        local fixed_target = {
            x = 10.0, y = 100.0, z = -50.0,
            headingMode = "FIXED",
            fixedHeading = 270.0,
        }
        local out_fixed = vectored_vtol_driver.compute(cfg, nav, fixed_target, "CRUISE", 0.05, { prev_heading = 0.0 })
        assert_true(math.abs(out_fixed.targetHeading - 358.5) < 0.01, "FIXED 270 deg from 0 deg must slew -1.5 deg to 358.5 deg")
    end)
end)

describe("operator_handler MSG_OPERATOR_CMD normalization, authority guard, and bumpless transition", function()
    local operator_handler = require("operator_handler")
    local guidance_controller = require("guidance_controller")
    local fcp_runtime = require("fcp_runtime")
    local main = require("main")
    local cfg = main.load_config()

    it("normalizes LOITER and POI_HOLD parameters and sanitizes out-of-range inputs", function()
        local op = operator_handler.init({})
        local pkt_loiter = {
            type = "MSG_OPERATOR_CMD",
            payload = {
                authority = "PILOT_PRIMARY",
                command = "LOITER",
                flightMode = "LOITER",
                params = {
                    targetWaypoint = { x = 200.0, z = -300.0 },
                    targetAlt = 140.0,
                    targetSpeed = 12.0,
                    loiterRadius = -15.0,       -- invalid negative -> clamp to >= 5.0
                    loiterDirection = "INVALID", -- invalid -> default "CW"
                    headingMode = "FIXED",
                    fixedHeading = -45.0,       -- normalize to 315.0
                },
                emergencyAction = "NONE",
            },
        }
        local res = operator_handler.process_c2(op, pkt_loiter, 1000)
        assert_true(res.accepted)
        assert_eq(res.flightMode, "LOITER")
        assert_eq(res.params.loiterRadius, 5.0, "Negative loiterRadius must be clamped to minimum 5.0m")
        assert_eq(res.params.loiterDirection, "CW", "Invalid loiterDirection must default to CW")
        assert_eq(res.params.headingMode, "FIXED")
        assert_eq(res.params.fixedHeading, 315.0, "-45 deg fixedHeading must normalize to 315.0 deg")

        -- Transition from LOITER to POI_HOLD triggers bumplessTransition
        local pkt_poi = {
            type = "MSG_OPERATOR_CMD",
            payload = {
                authority = "PILOT_PRIMARY",
                command = "POI_HOLD",
                flightMode = "POI_HOLD",
                params = {
                    targetWaypoint = { x = 210.0, z = -310.0 },
                    targetAlt = 135.0,
                    poiTarget = { x = 250.0, y = 64.0, z = -350.0 },
                },
            },
        }
        local res_poi = operator_handler.process_c2(op, pkt_poi, 2000)
        assert_true(res_poi.accepted)
        assert_eq(res_poi.flightMode, "POI_HOLD")
        assert_eq(res_poi.params.headingMode, "POI", "POI_HOLD must default headingMode to POI")
        assert_not_nil(res_poi.params.poiTarget)
        assert_eq(res_poi.params.poiTarget.x, 250.0)
        assert_true(res_poi.bumplessTransition, "Switching LOITER -> POI_HOLD must flag bumplessTransition")

        -- Unforced GCS packet while PILOT_PRIMARY is active must be rejected
        local pkt_unforced_gcs = {
            type = "MSG_OPERATOR_CMD",
            payload = {
                authority = "GCS",
                command = "CRUISE",
                flightMode = "CRUISE",
                params = { targetWaypoint = { x = 0.0, z = 0.0 } },
            },
        }
        local res_rej = operator_handler.process_c2(op, pkt_unforced_gcs, 2500)
        assert_false(res_rej.accepted)
        assert_eq(res_rej.reason, "PILOT_OVERRIDE_ACTIVE")

        -- NaN / Infinity sanitization in normalize_params (Issue 2)
        local nan_val = 0 / 0
        local norm_nan = operator_handler.normalize_params({
            fixedHeading = nan_val,
            loiterRadius = nan_val,
            targetAlt = math.huge,
            targetSpeed = -math.huge,
        }, "LOITER")
        assert_nil(norm_nan.fixedHeading, "NaN fixedHeading must be rejected as nil")
        assert_eq(norm_nan.loiterRadius, 30.0, "NaN loiterRadius must fall back to default 30.0")
        assert_nil(norm_nan.targetAlt, "Inf targetAlt must be rejected as nil")
        assert_nil(norm_nan.targetSpeed, "-Inf targetSpeed must be rejected as nil")

        local norm_inf = operator_handler.normalize_params({ fixedHeading = math.huge }, "CRUISE")
        assert_nil(norm_inf.fixedHeading, "Inf fixedHeading must be rejected as nil")
    end)

    it("applies 2.0s bumpless linear ramp on mode transition without zeroing initial boot output", function()
        local g_state = guidance_controller.init(cfg)
        local nav = {
            pos = { x = 0.0, y = 100.0, z = -30.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local target = { x = 0.0, y = 100.0, z = 0.0, loiterRadius = 30.0, loiterDirection = "CW", targetSpeed = 8.0 }

        -- At now_ms = 500 on fresh boot (no prior mode switch), output must NOT be attenuated by ramp
        local cmd_boot, _ = guidance_controller.compute(g_state, nav, target, { state = "CRUISE", flightActive = true, now_ms = 500 }, 0.05)
        assert_true(math.abs(cmd_boot.surge) > 0.1, "Fresh boot at now_ms=500 must not be attenuated by un-triggered ramp")
        assert_eq(cmd_boot.surge, -1.0, "Fresh boot at now_ms=500 must output full un-ramped -1.0 surge")

        -- Switching CRUISE -> LOITER at now_ms = 1000 triggers bumpless ramp (elapsed = 500ms at now_ms = 1500 -> lambda = 0.25)
        guidance_controller.trigger_bumpless_transition(g_state, 1000)
        local cmd_mid, _ = guidance_controller.compute(g_state, nav, target, { state = "LOITER", flightActive = true, now_ms = 1500 }, 0.05)
        local cmd_full, _ = guidance_controller.compute(g_state, nav, target, { state = "LOITER", flightActive = true, now_ms = 3500 }, 0.05)
        assert_true(math.abs(cmd_mid.sway) > 0.0 and math.abs(cmd_mid.sway) < math.abs(cmd_full.sway), "Bumpless ramp at 500ms elapsed must partially attenuate sway compared to full 2.5s elapsed")
        assert_eq(cmd_mid.translationBias.sway, cmd_mid.sway, "translationBias.sway must match ramped sway")
    end)

    it("wires Base+0 MSG_OPERATOR_CMD through fcp_runtime.step_tick into FSM, mission_target, and Base+1/Base+3", function()
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
        local ctx = fcp_runtime.create_context(cfg, function() return mock_modem end)
        flight_fsm.transition_to(ctx.fsm, "CRUISE")
        ctx.nav.pos = { x = 0.0, y = 100.0, z = -40.0 }
        ctx.nav.lastCoreRxMs = 2000
        ctx.nav.lastGpsFixMs = 2000

        local network_manager = require("network_manager")
        network_manager.ingest_modem_event(ctx.net, "top", 10000, 10000, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "AMM-03",
            type = "MSG_OPERATOR_CMD",
            seq = 10,
            timestamp = 2000,
            payload = {
                authority = "PILOT_PRIMARY",
                command = "LOITER",
                flightMode = "LOITER",
                params = {
                    targetWaypoint = { x = 0.0, z = 0.0 },
                    targetAlt = 120.0,
                    targetSpeed = 10.0,
                    loiterRadius = 40.0,
                    loiterDirection = "CCW",
                },
                emergencyAction = "NONE",
            },
        }, 1, 2000)

        -- Advance 4 ticks so both Base+1 MSG_ATTITUDE_CMD and Base+3 MSG_MFD_STATE are emitted
        for i = 1, 4 do
            fcp_runtime.step_tick(ctx, 0.05, 2000 + i * 50)
        end

        assert_eq(ctx.fsm.current_state, "LOITER")
        assert_eq(ctx.mission_target.y, 120.0)
        assert_eq(ctx.mission_target.loiterRadius, 40.0)
        assert_eq(ctx.mission_target.loiterDirection, "CCW")

        local att_tx, mfd_tx = nil, nil
        for _, tx in ipairs(transmitted) do
            if tx.channel == 10001 and tx.payload.type == "MSG_ATTITUDE_CMD" then att_tx = tx end
            if tx.channel == 10003 and tx.payload.type == "MSG_MFD_STATE" then mfd_tx = tx end
        end
        assert_not_nil(att_tx, "MSG_ATTITUDE_CMD must be transmitted on Base+1")
        assert_eq(att_tx.payload.payload.flightMode, "LOITER")
        assert_not_nil(mfd_tx, "MSG_MFD_STATE must be transmitted on Base+3")
        assert_eq(mfd_tx.payload.payload.fsmState, "LOITER")
        assert_eq(mfd_tx.payload.payload.navigation.distanceToWp, 40.0)
    end)

    it("freezes hold center to current nav.pos on LOITER/POI_HOLD entry when targetWaypoint is omitted", function()
        local mock_modem = {
            open = function() end,
            close = function() end,
            isOpen = function() return true end,
            transmit = function() end,
            isWireless = function() return true end,
        }
        local ctx = fcp_runtime.create_context(cfg, function() return mock_modem end)
        flight_fsm.transition_to(ctx.fsm, "CRUISE")
        ctx.mission_target = { x = 500.0, y = 100.0, z = -500.0 }
        ctx.nav.pos = { x = 42.0, y = 120.0, z = -88.0 }
        ctx.nav.lastCoreRxMs = 3000
        ctx.nav.lastGpsFixMs = 3000

        local network_manager = require("network_manager")
        network_manager.ingest_modem_event(ctx.net, "top", 10000, 10000, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "AMM-03",
            type = "MSG_OPERATOR_CMD",
            seq = 11,
            timestamp = 3000,
            payload = {
                authority = "PILOT_PRIMARY",
                command = "POI_HOLD",
                flightMode = "POI_HOLD",
                params = {
                    poiTarget = { x = 142.0, y = 64.0, z = -88.0 },
                },
                emergencyAction = "NONE",
            },
        }, 1, 3000)

        fcp_runtime.step_tick(ctx, 0.05, 3050)
        assert_eq(ctx.fsm.current_state, "POI_HOLD")
        assert_eq(ctx.mission_target.x, 42.0, "Omitted targetWaypoint on POI_HOLD entry must freeze to current pos.x")
        assert_eq(ctx.mission_target.y, 120.0, "Omitted targetAlt on POI_HOLD entry must freeze to current pos.y")
        assert_eq(ctx.mission_target.z, -88.0, "Omitted targetWaypoint on POI_HOLD entry must freeze to current pos.z")
        assert_eq(ctx.mission_target.headingMode, "POI")

        -- Subsequent POI_HOLD parameter update while already in POI_HOLD without targetWaypoint keeps existing anchor
        ctx.nav.pos = { x = 44.0, y = 120.0, z = -90.0 }
        network_manager.ingest_modem_event(ctx.net, "top", 10000, 10000, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "AMM-03",
            type = "MSG_OPERATOR_CMD",
            seq = 12,
            timestamp = 3100,
            payload = {
                authority = "PILOT_PRIMARY",
                command = "POI_HOLD",
                flightMode = "POI_HOLD",
                params = {
                    poiTarget = { x = 200.0, y = 64.0, z = -100.0 },
                },
                emergencyAction = "NONE",
            },
        }, 1, 3100)
        fcp_runtime.step_tick(ctx, 0.05, 3150)
        assert_eq(ctx.mission_target.x, 42.0, "Updating POI while already in POI_HOLD must preserve existing hold anchor x")
        assert_eq(ctx.mission_target.z, -88.0, "Updating POI while already in POI_HOLD must preserve existing hold anchor z")
        assert_eq(ctx.mission_target.poiTarget.x, 200.0)
    end)

    it("does not freeze ground coordinates or arm bumpless ramp on ground C2 commands", function()
        local mock_modem = {
            open = function() end,
            close = function() end,
            isOpen = function() return true end,
            transmit = function() end,
            isWireless = function() return true end,
        }
        local ctx = fcp_runtime.create_context(cfg, function() return mock_modem end)
        flight_fsm.transition_to(ctx.fsm, "DISARMED")
        ctx.mission_target = { x = 500.0, y = 100.0, z = -500.0 }
        ctx.nav.pos = { x = 5.0, y = 64.0, z = 5.0 }
        ctx.nav.lastCoreRxMs = 2000
        ctx.nav.lastGpsFixMs = 2000
        -- Seed operator lastFlightMode so C2 would otherwise emit bumplessTransition = true
        ctx.operator.lastFlightMode = "CRUISE"

        local network_manager = require("network_manager")
        network_manager.ingest_modem_event(ctx.net, "top", 10000, 10000, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "AMM-03",
            type = "MSG_OPERATOR_CMD",
            seq = 13,
            timestamp = 2000,
            payload = {
                authority = "PILOT_PRIMARY",
                command = "LOITER",
                flightMode = "LOITER",
                params = {},
                emergencyAction = "NONE",
            },
        }, 1, 2000)

        fcp_runtime.step_tick(ctx, 0.05, 2050)
        assert_eq(ctx.fsm.current_state, "DISARMED")
        assert_eq(ctx.mission_target.x, 500.0, "Ground C2 must not overwrite mission_target.x with ground coordinates")
        assert_eq(ctx.mission_target.z, -500.0, "Ground C2 must not overwrite mission_target.z with ground coordinates")
        assert_eq(ctx.guidance.rampStartMs, -10000, "Ground C2 must not arm bumpless rampStartMs")
    end)
end)
