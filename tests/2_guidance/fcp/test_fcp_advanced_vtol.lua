-- Unit test suite for FCP ADVANCED_VTOL outer-loop driver and guidance integration
local guidance_controller = require("guidance_controller")
local flight_fsm = require("flight_fsm")
local aerodynamic_controller = require("aerodynamic_controller")
local ui_renderer = require("ui_renderer")

describe("fcp advanced_vtol airframe support and fsm recognition", function()
    it("recognizes ADVANCED_VTOL as a supported airframe in guidance_controller", function()
        local supported, reason = guidance_controller.is_airframe_supported("ADVANCED_VTOL")
        assert_true(supported, "ADVANCED_VTOL must be supported")
        assert_nil(reason, "Reason must be nil when supported")
    end)

    it("recognizes ADVANCED_VTOL as VTOL class in flight_fsm", function()
        assert_not_nil(flight_fsm.is_vtol, "flight_fsm.is_vtol must exist")
        assert_true(flight_fsm.is_vtol("ADVANCED_VTOL"), "ADVANCED_VTOL must be recognized as VTOL")
        assert_true(flight_fsm.is_vtol("VECTORED_VTOL"), "VECTORED_VTOL must be recognized as VTOL")
        assert_false(flight_fsm.is_vtol("FIXED_WING"), "FIXED_WING is not pure VTOL")
    end)

    it("initializes guidance_controller state with ADVANCED_VTOL airframe", function()
        local state = guidance_controller.init({ system = { airframeType = "ADVANCED_VTOL" } })
        assert_not_nil(state)
        assert_eq(state.airframeType, "ADVANCED_VTOL")
    end)
end)

describe("fcp advanced_vtol non-aero flapTarget 0.0 guarantee", function()
    it("ensures flapTarget is strictly 0.0 in all flight modes", function()
        local state = guidance_controller.init({ system = { airframeType = "ADVANCED_VTOL" } })
        local phases = { "TAKEOFF", "CRUISE", "LOITER", "APPROACH_LAND", "TOUCHDOWN", "EMERGENCY_LAND" }
        for _, phase in ipairs(phases) do
            local cmd = guidance_controller.pack_attitude_cmd(state, {
                surge = 0.5, sway = 0.2, heave = 0.1, throttle = 0.7,
                targetPitch = 0.0, targetRoll = 0.0, targetHeading = 90.0,
                targetClimbRate = 1.0, mode = "ADVANCED_VTOL"
            }, phase, true)
            assert_eq(cmd.flapTarget, 0.0, "flapTarget must be 0.0 for ADVANCED_VTOL in " .. phase)
            assert_eq(cmd.mode, "ADVANCED_VTOL")
        end
    end)

    it("disables aerodynamic_controller for ADVANCED_VTOL", function()
        assert_false(aerodynamic_controller.is_enabled_for_airframe("ADVANCED_VTOL"),
            "aerodynamic_controller must be disabled for ADVANCED_VTOL")
        local pkt = aerodynamic_controller.build_surface_packet({ airframeType = "ADVANCED_VTOL" }, { aileron = 1.0 })
        assert_nil(pkt, "build_surface_packet must be nil for ADVANCED_VTOL")
    end)
end)

describe("advanced_vtol_driver 3-axis decoupled translation and anti-windup", function()
    local advanced_vtol_driver = require("advanced_vtol_driver")
    local main = require("main")
    local cfg = main.load_config()

    it("computes surge, sway, and heave translation bias from position errors", function()
        local nav = {
            pos = { x = 0.0, y = 64.0, z = 0.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        -- Target is forward (-Z in Minecraft at heading 0) and right (+X at heading 0) and up (+Y)
        local target = { x = 5.0, y = 70.0, z = -10.0 }
        local driver_state = {}

        local out = advanced_vtol_driver.compute(cfg, nav, target, "CRUISE", 0.05, driver_state)
        assert_not_nil(out)
        assert_true(out.surge > 0.0, "Forward error must yield positive surge bias")
        assert_true(out.sway > 0.0, "Rightward error must yield positive sway bias")
        assert_true(out.heave > 0.0, "Climb error must yield positive heave bias")
        assert_not_nil(out.translationBias)
        assert_eq(out.translationBias.surge, out.surge)
        assert_eq(out.translationBias.sway, out.sway)
        assert_eq(out.translationBias.heave, out.heave)
        assert_eq(out.flapTarget, 0.0)
    end)

    it("accumulates error into driver_state integrals and clamps to maxI", function()
        local nav = {
            pos = { x = 0.0, y = 64.0, z = 0.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local target = { x = 10.0, y = 74.0, z = -10.0 }
        local driver_state = {}

        -- Large dt to saturate integral quickly
        advanced_vtol_driver.compute(cfg, nav, target, "CRUISE", 2.0, driver_state)
        assert_not_nil(driver_state.surge_i, "driver_state.surge_i must exist")
        assert_not_nil(driver_state.sway_i, "driver_state.sway_i must exist")
        assert_not_nil(driver_state.heave_i, "driver_state.heave_i must exist")
        assert_eq(driver_state.surge_i, 0.20, "surge_i clamped to maxI 0.20")
        assert_eq(driver_state.sway_i, 0.20, "sway_i clamped to maxI 0.20")
        assert_eq(driver_state.heave_i, 0.20, "heave_i clamped to maxI 0.20")

        -- Additional computation keeps it clamped
        advanced_vtol_driver.compute(cfg, nav, target, "CRUISE", 1.0, driver_state)
        assert_eq(driver_state.surge_i, 0.20, "surge_i remains clamped")

        -- Reset integrals clears all accumulator fields
        assert_not_nil(advanced_vtol_driver.reset_integrals, "reset_integrals must exist")
        advanced_vtol_driver.reset_integrals(driver_state)
        assert_eq(driver_state.surge_i, 0.0, "surge_i reset to 0.0")
        assert_eq(driver_state.sway_i, 0.0, "sway_i reset to 0.0")
        assert_eq(driver_state.heave_i, 0.0, "heave_i reset to 0.0")
    end)
end)

describe("advanced_vtol_driver gimbal slew rate limiter", function()
    local advanced_vtol_driver = require("advanced_vtol_driver")
    local main = require("main")
    local cfg = main.load_config()

    it("limits rate of change of translation bias to gimbalSlewRate", function()
        local nav = {
            pos = { x = 0.0, y = 64.0, z = 0.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        -- Huge target step error demanding surge = 1.0
        local target = { x = 0.0, y = 64.0, z = -100.0 }
        local driver_state = { prev_surge = 0.0, prev_sway = 0.0 }
        local dt = 0.05
        local slew_rate = 2.0 -- 2.0 / s -> max step = 0.10

        local out1 = advanced_vtol_driver.compute(cfg, nav, target, "CRUISE", dt, driver_state)
        assert_not_nil(out1)
        assert_true(out1.surge <= 0.1001 and out1.surge >= 0.0999,
            string.format("surge must be rate limited to ~0.10 per 50ms tick, got %.4f", out1.surge))

        local out2 = advanced_vtol_driver.compute(cfg, nav, target, "CRUISE", dt, driver_state)
        assert_true(out2.surge <= 0.2001 and out2.surge >= 0.1999,
            string.format("surge on 2nd tick must be ~0.20, got %.4f", out2.surge))
    end)
end)

describe("advanced_vtol_driver envelope attitude modes", function()
    local advanced_vtol_driver = require("advanced_vtol_driver")
    local main = require("main")

    it("enforces STRICT_LEVEL theta=0 phi=0 in STRICT_LEVEL mode even at high speed and max surge", function()
        local cfg = main.load_config()
        local g = cfg.guidance.advanced_vtol or cfg.guidance.vectored_vtol
        g.envelopeMode = "STRICT_LEVEL"

        local nav = {
            pos = { x = 0.0, y = 64.0, z = 0.0 },
            vel = { x = 0.0, y = 0.0, z = -25.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 25.0,
        }
        local target = { x = 0.0, y = 64.0, z = -200.0 }
        local driver_state = { prev_surge = 0.9, current_pitch = 0.0 }

        local out = advanced_vtol_driver.compute(cfg, nav, target, "CRUISE", 0.05, driver_state)
        assert_eq(out.targetPitch, 0.0, "STRICT_LEVEL must maintain pitch 0.0")
        assert_eq(out.targetRoll, 0.0, "STRICT_LEVEL must maintain roll 0.0")
    end)

    it("smoothly slews pitch in TILT_ASSISTED mode during CRUISE at high speed", function()
        local cfg = main.load_config()
        if not cfg.guidance.advanced_vtol then
            cfg.guidance.advanced_vtol = {}
        end
        cfg.guidance.advanced_vtol.envelopeMode = "TILT_ASSISTED"
        cfg.guidance.advanced_vtol.tiltSlewRateDegPerSec = 15.0
        cfg.guidance.advanced_vtol.tiltAssistedThresholdSpeedMps = 15.0
        cfg.guidance.advanced_vtol.tiltAssistedMaxPitchDeg = 10.0

        local nav = {
            pos = { x = 0.0, y = 64.0, z = 0.0 },
            vel = { x = 0.0, y = 0.0, z = -20.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 20.0,
        }
        local target = { x = 0.0, y = 64.0, z = -100.0 }
        local driver_state = { current_pitch = 0.0, prev_surge = 1.0 }

        local out = advanced_vtol_driver.compute(cfg, nav, target, "CRUISE", 0.05, driver_state)
        assert_not_nil(out)
        -- In 50ms at 15 deg/s max slew = 0.75 deg down (negative pitch for forward acceleration)
        assert_true(out.targetPitch >= -0.76 and out.targetPitch <= -0.74,
            string.format("targetPitch must slew by ~ -0.75 deg, got %.4f", out.targetPitch))
        assert_eq(out.targetRoll, 0.0, "Roll must remain 0.0 in TILT_ASSISTED")
    end)
end)

describe("advanced_vtol_driver FSM sequences: takeoff, approach, touchdown, emergency", function()
    local advanced_vtol_driver = require("advanced_vtol_driver")
    local main = require("main")
    local cfg = main.load_config()

    it("blocks horizontal translation and commands +2.5m/s climb during TAKEOFF until 15m clearance", function()
        local nav = {
            pos = { x = 0.0, y = 64.0, z = 0.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local target = { x = 20.0, y = 90.0, z = -20.0 }
        local driver_state = { takeoff_origin_y = 64.0 }

        -- Origin y = 64.0, current y = 70.0 (less than 64 + 15 = 79.0)
        nav.pos.y = 70.0
        local out = advanced_vtol_driver.compute(cfg, nav, target, "TAKEOFF", 0.05, driver_state)
        assert_eq(out.surge, 0.0, "Surge must be forced to 0.0 before takeoff clearance altitude")
        assert_eq(out.sway, 0.0, "Sway must be forced to 0.0 before takeoff clearance altitude")
        assert_eq(out.targetClimbRate, 2.5, "targetClimbRate must be +2.5 m/s during vertical takeoff climb")

        -- Past clearance altitude (y = 80.0 >= 79.0)
        nav.pos.y = 80.0
        local out2 = advanced_vtol_driver.compute(cfg, nav, target, "TAKEOFF", 0.05, driver_state)
        assert_true(out2.surge > 0.0 or out2.sway > 0.0, "Translation unblocks once clearance altitude is reached")
    end)

    it("executes 2-stage deceleration during APPROACH_LAND and TOUCHDOWN", function()
        local nav = {
            pos = { x = 0.0, y = 70.0, z = 0.0 },
            vel = { x = 0.0, y = -1.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local driver_state = {}

        -- Stage 1: horizontal distance > 0.5m -> approach descent -1.5 m/s
        local target_far = { x = 2.0, y = 64.0, z = 0.0 }
        local out_far = advanced_vtol_driver.compute(cfg, nav, target_far, "APPROACH_LAND", 0.05, driver_state)
        assert_eq(out_far.targetClimbRate, -1.5, "Stage 1 descent must be -1.5 m/s when d_2D > 0.5m")

        -- Stage 2: horizontal distance <= 0.5m -> touchdown descent -0.5 m/s
        local target_aligned = { x = 0.2, y = 64.0, z = 0.1 }
        local out_aligned = advanced_vtol_driver.compute(cfg, nav, target_aligned, "APPROACH_LAND", 0.05, driver_state)
        assert_eq(out_aligned.targetClimbRate, -0.5, "Stage 2 touchdown descent must be -0.5 m/s when d_2D <= 0.5m")

        -- Direct TOUCHDOWN state also commands -0.5 m/s soft landing
        local out_touchdown = advanced_vtol_driver.compute(cfg, nav, target_aligned, "TOUCHDOWN", 0.05, driver_state)
        assert_eq(out_touchdown.targetClimbRate, -0.5, "TOUCHDOWN state must command -0.5 m/s")
    end)

    it("handles EMERGENCY_LAND with -2.0m/s descent, level attitude, and velocity braking", function()
        local nav = {
            pos = { x = 0.0, y = 70.0, z = 0.0 },
            vel = { x = 3.0, y = -1.0, z = -4.0 },
            attitude = { pitch = 5.0, roll = 2.0, heading = 0.0 },
            groundSpeed = 5.0,
        }
        local driver_state = {}
        local target = { x = 0.0, y = 64.0, z = 0.0 }

        local out = advanced_vtol_driver.compute(cfg, nav, target, "EMERGENCY_LAND", 0.05, driver_state)
        assert_eq(out.targetClimbRate, -2.0, "EMERGENCY_LAND descent must be -2.0 m/s")
        assert_eq(out.targetPitch, 0.0, "EMERGENCY_LAND pitch must be level 0.0")
        assert_eq(out.targetRoll, 0.0, "EMERGENCY_LAND roll must be level 0.0")
        assert_true(out.surge < 0.0, "Surge must oppose forward velocity")
        assert_true(out.sway < 0.0, "Sway must oppose rightward velocity")
    end)
end)

describe("guidance_controller end-to-end integration with ADVANCED_VTOL", function()
    local main = require("main")
    local cfg = main.load_config()
    cfg.system.airframeType = "ADVANCED_VTOL"

    it("computes full guidance output packed attitude command for ADVANCED_VTOL", function()
        local state = guidance_controller.init(cfg)
        local nav = {
            pos = { x = 0.0, y = 64.0, z = 0.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local target = { x = 10.0, y = 80.0, z = -20.0 }
        local fsm_ctx = { state = "CRUISE", flightActive = true, now_ms = 5000 }

        local cmd, err = guidance_controller.compute(state, nav, target, fsm_ctx, 0.05)
        assert_nil(err, "guidance_controller.compute must not return error")
        assert_not_nil(cmd, "Packed attitude command must be returned")
        assert_eq(cmd.source, "FCP")
        assert_eq(cmd.mode, "ADVANCED_VTOL")
        assert_eq(cmd.commandType, "ATTITUDE_ANGLE")
        assert_eq(cmd.flapTarget, 0.0)
        assert_not_nil(cmd.translationBias)
        assert_true(cmd.translationBias.surge > 0.0, "Surge translationBias must be positive")
        assert_true(cmd.targetThrottle > 0.0, "targetThrottle must be positive")
    end)
end)

describe("ui_renderer ADVANCED_VTOL display", function()
    it("renders ADVANCED_VTOL in header row when configured", function()
        local rows = {}
        local mock_win = {}
        mock_win.setCursorPos = function(x, y) mock_win.cur_y = y end
        mock_win.blit = function(text, fg, bg)
            rows[mock_win.cur_y] = text
        end
        local state = {
            airframeType = "ADVANCED_VTOL",
            channel = { baseChannel = 10000, status = "ACTIVE" },
            fsm = { current_state = "CRUISE" },
            envelope = "STRICT_LEVEL",
            nav = {
                pos = { x = 100.0, y = 75.0, z = -50.0 },
                vel = { x = 0.0, y = 0.0, z = 0.0 },
                attitude = { pitch = 0.0, roll = 0.0, heading = 45.0 },
                groundSpeed = 12.5,
                hdop = 0.8,
                fuel = 0.95,
                coreAlive = true,
            },
            profile = {
                profile = { controllabilityStatus = "CALIBRATED" },
                swayTotalLoss = false,
            },
            operator = { authority = "AUTO", latestAlertBanner = "NOMINAL" },
            facility = { activePadId = "PAD-01", padMobility = "STATIC", atcStatus = "CLEARED" },
            tick = 120,
        }

        ui_renderer.render(mock_win, state)
        assert_not_nil(rows[1], "Header row 1 must be rendered")
        assert_true(string.find(rows[1], "ADVANCED_VTOL") ~= nil,
            "Header row must contain ADVANCED_VTOL, got: " .. tostring(rows[1]))
    end)
end)

describe("advanced_vtol_driver LOITER and POI_HOLD primitives with gimbal slew limiting", function()
    local advanced_vtol_driver = require("advanced_vtol_driver")
    local main = require("main")
    local cfg = main.load_config()

    it("executes CW and CCW LOITER with 2.0/s gimbal slew rate limiting and STRICT_LEVEL attitude", function()
        local prev_env = cfg.guidance.advanced_vtol.envelopeMode
        cfg.guidance.advanced_vtol.envelopeMode = "TILT_ASSISTED"
        local nav = {
            pos = { x = 0.0, y = 100.0, z = -30.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 20.0,
        }
        local target_cw = {
            x = 0.0, y = 100.0, z = 0.0,
            loiterRadius = 30.0,
            loiterDirection = "CW",
            targetSpeed = 10.0,
            poiTarget = { x = 0.0, y = 64.0, z = 0.0 },
            headingMode = "POI",
        }
        local ds = { prev_surge = 0.0, prev_sway = 0.0, prev_heading = 0.0 }
        local out = advanced_vtol_driver.compute(cfg, nav, target_cw, "LOITER", 0.05, ds)
        cfg.guidance.advanced_vtol.envelopeMode = prev_env
        assert_true(out.sway > 0.0 and out.sway <= 0.1001, "Gimbal slew limiter must cap sway step to <= 0.10 per tick")
        assert_eq(out.targetPitch, 0.0, "LOITER must enforce STRICT_LEVEL pitch 0.0")
        assert_eq(out.targetRoll, 0.0, "LOITER must enforce STRICT_LEVEL roll 0.0")
        assert_eq(out.flapTarget, 0.0, "flapTarget must remain 0.0")
    end)

    it("holds 3D hover and aims at poiTarget in POI_HOLD mode", function()
        local nav = {
            pos = { x = 0.0, y = 100.0, z = 0.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 90.0 },
            groundSpeed = 0.0,
        }
        -- Hold at (0, 100, 0), aim South (+Z -> 180 deg)
        local target = {
            x = 0.0, y = 100.0, z = 0.0,
            poiTarget = { x = 0.0, y = 64.0, z = 50.0 },
        }
        local ds = { prev_surge = 0.0, prev_sway = 0.0, prev_heading = 90.0 }
        local out = advanced_vtol_driver.compute(cfg, nav, target, "POI_HOLD", 0.05, ds)
        assert_eq(out.surge, 0.0)
        assert_eq(out.sway, 0.0)
        assert_eq(out.targetPitch, 0.0)
        assert_eq(out.targetRoll, 0.0)
        assert_eq(out.flapTarget, 0.0)
        assert_true(math.abs(out.targetHeading - 91.5) < 0.01, "Heading must slew from 90.0 toward 180.0 by +1.5 deg")
    end)

    it("preserves gimbal prev_surge/prev_sway continuity across FAILSAFE_HOLD exit for ADVANCED_VTOL", function()
        local guidance_controller = require("guidance_controller")
        local prev_af = cfg.system.airframeType
        cfg.system.airframeType = "ADVANCED_VTOL"
        local g_state = guidance_controller.init(cfg)
        cfg.system.airframeType = prev_af
        local nav = {
            pos = { x = 0.0, y = 100.0, z = 0.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local target = { x = 0.0, y = 100.0, z = -100.0 }

        -- Enter FAILSAFE_HOLD and establish active gimbal bias
        guidance_controller.compute(g_state, nav, target, { state = "FAILSAFE_HOLD", flightActive = true, now_ms = 1000 }, 0.05)
        g_state.driver_state.prev_surge = 0.60
        g_state.driver_state.prev_sway = -0.40

        -- Recover FAILSAFE_HOLD -> CRUISE: trigger_bumpless_transition must preserve prev_surge/prev_sway across reset
        guidance_controller.compute(g_state, nav, target, { state = "CRUISE", flightActive = true, now_ms = 1050 }, 0.05)
        -- With gimbalSlewRate = 2.0/s and dt = 0.05, max step is 0.10 -> prev_surge must be >= 0.50 (never reset to 0.0 -> <= 0.10)
        assert_true(g_state.driver_state.prev_surge >= 0.50,
            "FAILSAFE_HOLD exit must preserve prev_surge continuity, got " .. tostring(g_state.driver_state.prev_surge))
    end)
end)
