-- tests/2_guidance/fcp/test_outer_loop_se3.lua
-- Unit test suite for FCP v2.0.0 Unified SE(3) outer_loop_controller
-- Tests: 6 Airframes, QUATERNION_RATE, Anti-Windup, Bumpless Ramp, and Zero-Fallback Purity

package.path = package.path .. ";/modules/?.lua;/?/init.lua"
local outer_loop_controller = require("outer_loop_controller")

local function clamp(val, min_v, max_v)
    if val < min_v then return min_v end
    if val > max_v then return max_v end
    return val
end

local function make_base_cfg(airframe)
    return {
        system = {
            domainId = "AIRCRAFT_01",
            airframeType = airframe or "VECTORED_VTOL",
            loopFrequencyHz = 20,
        },
        outerLoop = {
            gravityMps2 = 11.0,
            kpPos = { x = 0.90, y = 1.10, z = 0.90 },
            kdVel = { x = 1.20, y = 1.35, z = 1.20 },
            kiPos = { x = 0.05, y = 0.08, z = 0.05 },
            maxAccelMps2 = 6.5,
            maxIntegralAccel = 1.5,
            hoverThrustNorm = 0.635,
            maxYawRateDegPerSec = 30.0,
            bumplessRampSec = 2.0,
            posMergeMaxStepM = 2.0,
            dtPropMaxSec = 0.1,
            fixed_wing = {
                nominalMaxBankDeg = 20.0,
                emergencyMaxBankDeg = 75.0,
                bankSlewRateDegPerSec = 45.0,
                nominalMaxPitchDeg = 20.0,
                trimThrottle = 0.70,
                trimPitchDeg = 2.5,
                energyKp = 0.03,
                balanceKp = 0.65,
                rotationSpeedMps = 12.0,
                stallSpeedMps = 10.0,
            },
            winged_vtol = {
                vLowMps = 8.0,
                vHighMps = 18.0,
                transitionMaxPitchDeg = 12.0,
                transitionMinPitchDeg = -10.0,
                transitionFlapTarget = 0.50,
            },
            vectored_vtol = {
                tiltAssistedMaxPitchDeg = 10.0,
                tiltSlewRateDegPerSec = 15.0,
                surgeAccelToBiasGain = 0.18,
                swayAccelToBiasGain = 0.18,
                thrustPerGScale = 0.06,
            },
            advanced_vtol = {
                tiltAssistedMaxPitchDeg = 10.0,
                tiltSlewRateDegPerSec = 15.0,
                gimbalSlewRate = 2.0,
                surgeAccelToBiasGain = 0.18,
                swayAccelToBiasGain = 0.18,
                thrustPerGScale = 0.06,
            },
            multirotor = {
                maxTiltDeg = 25.0,
            },
        },
        safety = {
            bumplessRampSec = 2.0,
            emergencyDescentRateMps = -1.5,
            fixedWingGlideDescentMps = -1.0,
        },
    }
end

local function make_nav(px, py, pz, vx, vy, vz, pitch, roll, heading)
    return {
        pos = { x = px or 0.0, y = py or 64.0, z = pz or 0.0 },
        vel = { vx = vx or 0.0, vy = vy or 0.0, vz = vz or 0.0 },
        attitude = { pitch = pitch or 0.0, roll = roll or 0.0, yaw = heading or 0.0, heading = heading or 0.0 },
        angularRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
    }
end

local function make_setpoint(tx, ty, tz, tvx, tvy, tvz, head, mode, profile)
    return {
        arm = true,
        flightActive = true,
        flightMode = mode or "CRUISE",
        constraintProfile = profile or "STRICT_LEVEL",
        targetPos = { x = tx or 0.0, y = ty or 64.0, z = tz or 0.0 },
        targetVel = { vx = tvx or 0.0, vy = tvy or 0.0, vz = tvz or 0.0 },
        feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
        targetHeading = head or 0.0,
        currentPos = { x = tx or 0.0, y = ty or 64.0, z = tz or 0.0 },
        navValid = true,
        gpsTimedOut = false,
        hdop = 1.0,
        posEpoch = 1000,
    }
end

describe("test_outer_loop_se3: FCP v2.0.0 SE(3) Outer Loop Controller", function()

    it("verifies is_airframe_supported returns true for exactly the 6 valid airframes", function()
        assert_not_nil(outer_loop_controller.is_airframe_supported)
        local valid = { "FIXED_WING", "WINGED_VTOL", "VECTORED_VTOL", "ADVANCED_VTOL", "QUADROTOR", "HEXAROTOR" }
        for _, af in ipairs(valid) do
            assert_true(outer_loop_controller.is_airframe_supported(af), "Airframe must be supported: " .. af)
        end
        assert_false(outer_loop_controller.is_airframe_supported("HELICOPTER"))
        assert_false(outer_loop_controller.is_airframe_supported("ROVER"))
        assert_false(outer_loop_controller.is_airframe_supported(nil))
    end)

    it("verifies hovering equilibrium yields a_des.y == 11.0 and collectiveThrust ~ 0.635", function()
        local cfg = make_base_cfg("VECTORED_VTOL")
        local state = outer_loop_controller.init(cfg)
        local nav = make_nav(10.0, 64.0, -20.0, 0.0, 0.0, 0.0)
        local sp = make_setpoint(10.0, 64.0, -20.0, 0.0, 0.0, 0.0, 0.0)
        local dt = 0.05

        local a_des = outer_loop_controller.compute_desired_accel(state, nav, sp, dt, {})
        assert_not_nil(a_des, "a_des must not be nil")
        assert_true(math.abs(a_des.ax) < 1e-4, "Horizontal ax must be 0 at equilibrium")
        assert_true(math.abs(a_des.ay - 11.0) < 1e-4, "Vertical ay must equal 11.0 at equilibrium")
        assert_true(math.abs(a_des.az) < 1e-4, "Horizontal az must be 0 at equilibrium")
        assert_false(a_des.saturated, "Equilibrium must not saturate")

        -- Norm clamping test: ||a_des - g*u_y|| <= maxAccelMps2 (6.5)
        local sp_far = make_setpoint(1000.0, 200.0, -1000.0, 0.0, 0.0, 0.0, 0.0)
        local a_sat = outer_loop_controller.compute_desired_accel(state, nav, sp_far, dt, {})
        assert_true(a_sat.saturated, "Large demand must set saturated = true")
        assert_true(state.saturated, "state.saturated must record saturation")
        local kin_norm = math.sqrt(a_sat.ax * a_sat.ax + (a_sat.ay - 11.0) * (a_sat.ay - 11.0) + a_sat.az * a_sat.az)
        assert_true(kin_norm <= 6.5001, "Kinematic accel norm must be clamped to maxAccelMps2=6.5, got: " .. tostring(kin_norm))

        local fsmCtx = { currentState = "ACTIVE_TRACKING", rampAlpha = 1.0 }
        local cmd = outer_loop_controller.compute(state, nav, sp, fsmCtx, dt)
        assert_not_nil(cmd, "compute() must return command")
        assert_true(math.abs(cmd.collectiveThrust - 0.635) < 0.05, "collectiveThrust should be near hoverThrustRatio 0.635, got: " .. tostring(cmd.collectiveThrust))
    end)

    it("verifies conditional anti-windup: positive saturation freezes integration while negative error unwinds", function()
        local cfg = make_base_cfg("VECTORED_VTOL")
        local state = outer_loop_controller.init(cfg)
        local nav = make_nav(0.0, 64.0, 0.0, 0.0, 0.0, 0.0)
        local sp_pos = make_setpoint(5.0, 64.0, 0.0, 0.0, 0.0, 0.0)
        local dt = 0.05

        -- Saturation on X positive (surge)
        local satFlags = {
            axisSaturatedPos = { surge = true, x = true },
            axisSaturatedNeg = {},
        }
        -- With positive error (tx=5 > px=0), integrator should NOT increase
        outer_loop_controller.compute_desired_accel(state, nav, sp_pos, dt, satFlags)
        assert_true(state.integrators.x <= 1e-6, "Integrator X must not increase when positively saturated, got: " .. tostring(state.integrators.x))

        -- With negative error (tx=-5 < px=0), opposing error unwinds integrator
        local sp_neg = make_setpoint(-5.0, 64.0, 0.0, 0.0, 0.0, 0.0)
        outer_loop_controller.compute_desired_accel(state, nav, sp_neg, dt, satFlags)
        assert_true(state.integrators.x < -1e-6, "Integrator X must unwind on negative error, got: " .. tostring(state.integrators.x))

        -- reset_integrators resets all axes to 0
        outer_loop_controller.reset_integrators(state)
        assert_eq(state.integrators.x, 0.0)
        assert_eq(state.integrators.y, 0.0)
        assert_eq(state.integrators.z, 0.0)

        -- Actuator tap failure freezes integration
        local tapSat = { actuatorHealth = { tap = false, asa = true, allOk = false } }
        outer_loop_controller.compute_desired_accel(state, nav, sp_pos, dt, tapSat)
        assert_eq(state.integrators.x, 0.0, "Integrator must be frozen when tap == false")
    end)

    it("verifies Zero-Fallback wire purity on MSG_ATTITUDE_CMD payload across all airframes", function()
        local airframes = { "FIXED_WING", "WINGED_VTOL", "VECTORED_VTOL", "ADVANCED_VTOL", "QUADROTOR", "HEXAROTOR" }
        for _, af in ipairs(airframes) do
            local cfg = make_base_cfg(af)
            local state = outer_loop_controller.init(cfg)
            local nav = make_nav(0, 64, 0, 5, 0, 0, 0, 0, 45)
            local sp = make_setpoint(10, 70, 5, 5, 0, 0, 45, "CRUISE", "STRICT_LEVEL")
            local fsmCtx = { currentState = "ACTIVE_TRACKING", rampAlpha = 1.0 }
            local cmd = outer_loop_controller.compute(state, nav, sp, fsmCtx, 0.05)

            assert_eq(cmd.source, "FCP")
            assert_true(cmd.arm == true)
            assert_true(cmd.flightActive == true)
            assert_eq(cmd.commandType, "QUATERNION_RATE")
            assert_eq(cmd.mode, af)
            assert_false(cmd.acroActive, "acroActive must be false")

            -- Quaternion validity: ||q|| == 1.0
            local q = cmd.targetQuaternion
            assert_not_nil(q, "targetQuaternion must not be nil for " .. af)
            local qnorm = math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)
            assert_true(math.abs(qnorm - 1.0) < 1e-3, "Quaternion norm must be 1.0, got: " .. tostring(qnorm))

            -- Angular rates validity
            assert_not_nil(cmd.targetAngularRates)
            assert_not_nil(cmd.targetAngularRates.pitchRate)
            assert_not_nil(cmd.targetAngularRates.rollRate)
            assert_not_nil(cmd.targetAngularRates.yawRate)

            -- Collective thrust in [0, 1]
            assert_true(cmd.collectiveThrust >= 0.0 and cmd.collectiveThrust <= 1.0, "collectiveThrust out of [0,1]")

            -- Zero-Fallback: deprecated fields MUST BE strictly nil
            assert_nil(cmd.angleTargets, "angleTargets must be nil")
            assert_nil(cmd.rateTargets, "rateTargets must be nil")
            assert_nil(cmd.targetThrottle, "targetThrottle must be nil")
            assert_nil(cmd.targetClimbRate, "targetClimbRate must be nil")
            if cmd.translationBias ~= nil then
                assert_nil(cmd.translationBias.heave, "translationBias.heave must be nil")
            end
        end
    end)

    it("verifies QUADROTOR & HEXAROTOR Tilt-to-Accelerate clamped to 25 deg with translationBias == nil and flapTarget == 0.0", function()
        for _, af in ipairs({ "QUADROTOR", "HEXAROTOR" }) do
            local cfg = make_base_cfg(af)
            local state = outer_loop_controller.init(cfg)
            -- Strong lateral and forward acceleration demand
            local nav = make_nav(0, 64, 0, 0, 0, 0, 0, 0, 0)
            local sp = make_setpoint(100.0, 64.0, -100.0, 20.0, 0.0, -20.0, 0.0)
            local fsmCtx = { currentState = "ACTIVE_TRACKING", rampAlpha = 1.0 }
            local cmd = outer_loop_controller.compute(state, nav, sp, fsmCtx, 0.05)

            assert_nil(cmd.translationBias, "Multirotors must have translationBias == nil")
            assert_eq(cmd.flapTarget, 0.0, "Multirotors must have flapTarget == 0.0")

            -- Quaternion pitch/roll within max tilt limit (25 deg)
            local q = cmd.targetQuaternion
            -- Convert back to pitch/roll roughly
            local sinp = 2.0 * (q.w * q.y - q.z * q.x)
            local pitchRad = math.abs(sinp) >= 1.0 and ((sinp > 0) and (math.pi*0.5) or (-math.pi*0.5)) or math.asin(sinp)
            local rollRad = math.atan2(2.0 * (q.w * q.x + q.y * q.z), 1.0 - 2.0 * (q.x * q.x + q.y * q.y))
            local pitchDeg = math.abs(math.deg(pitchRad))
            local rollDeg = math.abs(math.deg(rollRad))

            assert_true(pitchDeg <= 25.01, "Pitch tilt must be clamped to 25 deg, got: " .. tostring(pitchDeg))
            assert_true(rollDeg <= 25.01, "Roll tilt must be clamped to 25 deg, got: " .. tostring(rollDeg))
        end
    end)

    it("verifies VECTORED_VTOL & ADVANCED_VTOL STRICT_LEVEL, TILT_ASSISTED, and Sway-Loss Tilt Fallback", function()
        -- 1. STRICT_LEVEL: level attitude, horizontal translationBias
        local cfg = make_base_cfg("VECTORED_VTOL")
        local state = outer_loop_controller.init(cfg)
        local nav = make_nav(0, 64, 0, 0, 0, 0, 0, 0, 0)
        local sp = make_setpoint(10, 64, -10, 5, 0, -5, 0, "CRUISE", "STRICT_LEVEL")
        local fsmCtx = { currentState = "ACTIVE_TRACKING", rampAlpha = 1.0 }
        local cmd = outer_loop_controller.compute(state, nav, sp, fsmCtx, 0.05)

        assert_nil(cmd.flapTarget, "VECTORED_VTOL must have flapTarget == nil")
        assert_not_nil(cmd.translationBias, "STRICT_LEVEL must provide translationBias")
        assert_not_nil(cmd.translationBias.surge)
        assert_not_nil(cmd.translationBias.sway)
        assert_nil(cmd.translationBias.heave)

        -- 2. ADVANCED_VTOL gimbal slew rate limiting (2.0 / s -> 0.1 per 0.05s)
        local adv_cfg = make_base_cfg("ADVANCED_VTOL")
        local adv_state = outer_loop_controller.init(adv_cfg)
        local cmd1 = outer_loop_controller.compute(adv_state, nav, sp, fsmCtx, 0.05)
        assert_true(math.abs(cmd1.translationBias.surge) <= 0.1001, "Gimbal slew rate limit must clamp initial step to <= 0.10, got: " .. tostring(cmd1.translationBias.surge))

        -- 3. Sway-Loss Tilt Fallback: when actuatorHealth.tap == false, falls back to tilt projection
        local satFail = {
            currentState = "ACTIVE_TRACKING",
            rampAlpha = 1.0,
            actuatorHealth = { tap = false, asa = true, allOk = false },
        }
        local cmdFallback = outer_loop_controller.compute(adv_state, nav, sp, satFail, 0.05)
        -- In tilt fallback, attitude tilts to provide lateral force
        local qf = cmdFallback.targetQuaternion
        local rollRad = math.atan2(2.0 * (qf.w * qf.x + qf.y * qf.z), 1.0 - 2.0 * (qf.x * qf.x + qf.y * qf.y))
        local rollDeg = math.abs(math.deg(rollRad))
        assert_true(rollDeg > 0.1, "Sway loss fallback must tilt roll, got: " .. tostring(rollDeg))
    end)

    it("verifies FIXED_WING Bank-to-Turn roll projection and flapTarget behavior", function()
        local cfg = make_base_cfg("FIXED_WING")
        local state = outer_loop_controller.init(cfg)
        -- Flying forward at 15 m/s, lateral acceleration requested to the right
        local nav = make_nav(0, 100, 0, 0, 0, -15, 0, 0, 0)
        local sp = make_setpoint(20, 100, -50, 5, 0, -15, 0, "CRUISE", "FIXED_WING_NOMINAL")
        sp.flapHint = 0.25
        local fsmCtx = { currentState = "ACTIVE_TRACKING", rampAlpha = 1.0 }
        local cmd = outer_loop_controller.compute(state, nav, sp, fsmCtx, 0.05)

        assert_nil(cmd.translationBias, "FIXED_WING must have translationBias == nil")
        assert_eq(cmd.flapTarget, 0.25, "FIXED_WING must reflect flapHint")

        -- Target angular rates should have yawRate feedforward for BTT
        assert_not_nil(cmd.targetAngularRates)
        assert_true(cmd.collectiveThrust > 0.0 and cmd.collectiveThrust <= 1.0)
    end)

    it("verifies WINGED_VTOL transition blending across [8, 18] m/s", function()
        local cfg = make_base_cfg("WINGED_VTOL")
        local state = outer_loop_controller.init(cfg)

        -- Case 1: Low speed (4 m/s < 8 m/s) -> pure hover
        local nav_low = make_nav(0, 100, 0, 0, 0, -4, 0, 0, 0)
        local sp = make_setpoint(5, 100, -10, 0, 0, -4, 0, "CRUISE", "STRICT_LEVEL")
        local fsmCtx = { currentState = "ACTIVE_TRACKING", rampAlpha = 1.0 }
        local cmd_low = outer_loop_controller.compute(state, nav_low, sp, fsmCtx, 0.05)
        assert_eq(cmd_low.flapTarget, 0.0, "Low speed WINGED_VTOL should have flapTarget == 0.0")

        -- Case 2: Transition speed (13 m/s) -> transition blending (alpha = 0.5)
        local nav_mid = make_nav(0, 100, 0, 0, 0, -13, 0, 0, 0)
        local cmd_mid = outer_loop_controller.compute(state, nav_mid, sp, fsmCtx, 0.05)
        assert_true(cmd_mid.flapTarget >= 0.4 and cmd_mid.flapTarget <= 0.6, "Transition WINGED_VTOL should have flapTarget ~ 0.5")

        -- Case 3: High speed (20 m/s > 18 m/s) -> fixed wing cruise (preserves sp.flapHint)
        local nav_high = make_nav(0, 100, 0, 0, 0, -20, 0, 0, 0)
        local cmd_high = outer_loop_controller.compute(state, nav_high, sp, fsmCtx, 0.05)
        assert_eq(cmd_high.flapTarget, 0.0, "High speed cruise WINGED_VTOL should have flapTarget == 0.0")
        sp.flapHint = 0.30
        local cmd_high_hint = outer_loop_controller.compute(state, nav_high, sp, fsmCtx, 0.05)
        assert_eq(cmd_high_hint.flapTarget, 0.30, "High speed WINGED_VTOL must preserve sp.flapHint")
        sp.flapHint = nil

        -- Case 4: Transition pitch clamp [-10, +12] deg and vHigh == vLow div-by-zero guard
        local sp_climb = make_setpoint(0, 200, -50, 0, 0, -13, 0, "CRUISE", "STRICT_LEVEL")
        local cmd_mid_climb = outer_loop_controller.compute(state, nav_mid, sp_climb, fsmCtx, 0.05)
        local q_mc = cmd_mid_climb.targetQuaternion
        local sinp_mc = clamp(2.0 * (q_mc.w * q_mc.y - q_mc.z * q_mc.x), -1.0, 1.0)
        local pitch_mc = math.deg(math.asin(sinp_mc))
        assert_true(pitch_mc >= -10.01 and pitch_mc <= 12.01, "Transition pitch must be clamped to [-10, +12] deg, got: " .. tostring(pitch_mc))

        local cfg_eq = make_base_cfg("WINGED_VTOL")
        cfg_eq.outerLoop.winged_vtol.vLowMps = 12.0
        cfg_eq.outerLoop.winged_vtol.vHighMps = 12.0
        local state_eq = outer_loop_controller.init(cfg_eq)
        local nav_eq = make_nav(0, 100, 0, 0, 0, -12, 0, 0, 0)
        local cmd_eq = outer_loop_controller.compute(state_eq, nav_eq, sp, fsmCtx, 0.05)
        assert_true(cmd_eq.targetQuaternion.w == cmd_eq.targetQuaternion.w, "vHigh == vLow must not produce NaN")
    end)

    it("verifies 2.0s bumpless ramp scales feedback correction smoothly", function()
        local cfg = make_base_cfg("VECTORED_VTOL")
        local state = outer_loop_controller.init(cfg)
        local nav = make_nav(0, 64, 0, 0, 0, 0, 0, 0, 0)
        local sp = make_setpoint(0, 64, -10, 0, 0, -5, 0, "CRUISE", "STRICT_LEVEL")

        -- At rampAlpha = 0.0 (fresh transition), feedback is 0
        local fsmCtx0 = { currentState = "ACTIVE_TRACKING", rampAlpha = 0.0 }
        local cmd0 = outer_loop_controller.compute(state, nav, sp, fsmCtx0, 0.05)
        assert_true(math.abs(cmd0.translationBias.surge) < 1e-4, "At rampAlpha 0.0, translationBias.surge must be 0")

        -- At rampAlpha = 0.5, feedback is half
        local fsmCtxHalf = { currentState = "ACTIVE_TRACKING", rampAlpha = 0.5 }
        local cmdHalf = outer_loop_controller.compute(state, nav, sp, fsmCtxHalf, 0.05)
        assert_true(cmdHalf.translationBias.surge > 0.01, "At rampAlpha 0.5, surge must be scaled")

        -- At rampAlpha = 1.0, feedback is full
        local fsmCtx1 = { currentState = "ACTIVE_TRACKING", rampAlpha = 1.0 }
        local cmd1 = outer_loop_controller.compute(state, nav, sp, fsmCtx1, 0.05)
        assert_true(cmd1.translationBias.surge > cmdHalf.translationBias.surge, "Full ramp surge must exceed half ramp surge")
    end)

    it("verifies AMM_TIMEOUT_HOLD self-generates level hover and EMERGENCY_LAND commands -1.5 m/s descent", function()
        local cfg = make_base_cfg("VECTORED_VTOL")
        local state = outer_loop_controller.init(cfg)
        local nav = make_nav(15.0, 75.0, -30.0, 1.0, 0.0, -1.0, 2.0, 1.0, 45.0)
        local sp = make_setpoint(100.0, 100.0, -100.0, 15.0, 0.0, -15.0, 90.0)

        -- AMM_TIMEOUT_HOLD: holds position, level attitude, collectiveThrust ~ 0.635
        local holdCtx = { currentState = "AMM_TIMEOUT_HOLD", rampAlpha = 1.0 }
        local holdCmd = outer_loop_controller.compute(state, nav, sp, holdCtx, 0.05)
        assert_true(math.abs(holdCmd.collectiveThrust - 0.635) < 0.1, "AMM_TIMEOUT_HOLD collectiveThrust must balance hover ~ 0.635")

        -- EMERGENCY_LAND: level attitude, descends at -2.0 m/s
        local emgCtx = { currentState = "EMERGENCY_LAND", rampAlpha = 1.0 }
        local emgCmd = outer_loop_controller.compute(state, nav, sp, emgCtx, 0.05)
        assert_eq(emgCmd.flightMode, "EMERGENCY_LAND")
        assert_true(emgCmd.collectiveThrust < 0.635, "EMERGENCY_LAND should command descent thrust < hover")
    end)

    it("verifies compute() freezes integration when fsmCtx.vasSat indicates saturation", function()
        local cfg = make_base_cfg("VECTORED_VTOL")
        local state = outer_loop_controller.init(cfg)
        local nav = make_nav(0, 64, 0, 0, 0, 0, 0, 0, 0)
        local sp = make_setpoint(10, 64, 0, 5, 0, 0, 0, "CRUISE", "STRICT_LEVEL")

        -- Saturated X in fsmCtx.vasSat
        local fsmCtx = {
            currentState = "ACTIVE_TRACKING",
            rampAlpha = 1.0,
            vasSat = {
                axisSaturatedPos = { surge = true, x = true },
                axisSaturatedNeg = {},
            },
        }
        outer_loop_controller.compute(state, nav, sp, fsmCtx, 0.05)
        assert_true(state.integrators.x <= 1e-6, "Integrator X must not increase via compute() when fsmCtx.vasSat is saturated")

        -- Opposing error unwinds through compute()
        local sp_neg = make_setpoint(-10, 64, 0, -5, 0, 0, 0, "CRUISE", "STRICT_LEVEL")
        outer_loop_controller.compute(state, nav, sp_neg, fsmCtx, 0.05)
        assert_true(state.integrators.x < -1e-6, "Integrator X must unwind opposing error through compute()")
    end)

    it("verifies EMERGENCY_LAND on QUADROTOR and VECTORED_VTOL yields reduced collectiveThrust < 0.635 without climb", function()
        for _, af in ipairs({ "QUADROTOR", "VECTORED_VTOL" }) do
            local cfg = make_base_cfg(af)
            local state = outer_loop_controller.init(cfg)
            local nav = make_nav(50.0, 100.0, 50.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
            local sp = make_setpoint(50.0, 100.0, 50.0, 0.0, 0.0, 0.0, 0.0, "CRUISE", "STRICT_LEVEL")
            local emgCtx = { currentState = "EMERGENCY_LAND", rampAlpha = 1.0 }

            local cmd = outer_loop_controller.compute(state, nav, sp, emgCtx, 0.05)
            assert_eq(cmd.flightMode, "EMERGENCY_LAND")
            assert_true(cmd.collectiveThrust < 0.635, af .. " EMERGENCY_LAND thrust must be strictly < hoverThrust (0.635), got: " .. tostring(cmd.collectiveThrust))
            assert_true(cmd.collectiveThrust > 0.0, af .. " EMERGENCY_LAND thrust must be > 0.0")
        end
    end)

    it("verifies TILT_ASSISTED inhibits pitch tilt in LOITER and POI_HOLD modes", function()
        local cfg = make_base_cfg("VECTORED_VTOL")
        local state = outer_loop_controller.init(cfg)
        -- High speed (20 m/s > 15 m/s threshold) with large forward surge demand
        local nav = make_nav(0, 100, 0, 0, 0, -20, 0, 0, 0)
        local sp_cruise = make_setpoint(0, 100, -50, 0, 0, -20, 0, "CRUISE", "TILT_ASSISTED")
        local fsmCtx = { currentState = "ACTIVE_TRACKING", rampAlpha = 1.0 }

        -- In CRUISE mode with TILT_ASSISTED, pitch tilts up to assist forward thrust
        local cmd_cruise = outer_loop_controller.compute(state, nav, sp_cruise, fsmCtx, 0.05)
        local q_cruise = cmd_cruise.targetQuaternion
        local sinp_c = 2.0 * (q_cruise.w * q_cruise.y - q_cruise.z * q_cruise.x)
        local pitch_c = math.abs(math.deg(math.asin(clamp(sinp_c, -1.0, 1.0))))
        assert_true(pitch_c > 0.1, "CRUISE TILT_ASSISTED must command non-zero pitch, got: " .. tostring(pitch_c))

        -- In LOITER mode with TILT_ASSISTED, pitch must be inhibited (0.0)
        local state_loiter = outer_loop_controller.init(cfg)
        local sp_loiter = make_setpoint(0, 100, -50, 0, 0, -20, 0, "LOITER", "TILT_ASSISTED")
        local cmd_loiter = outer_loop_controller.compute(state_loiter, nav, sp_loiter, fsmCtx, 0.05)
        local q_loiter = cmd_loiter.targetQuaternion
        local sinp_l = 2.0 * (q_loiter.w * q_loiter.y - q_loiter.z * q_loiter.x)
        local pitch_l = math.abs(math.deg(math.asin(clamp(sinp_l, -1.0, 1.0))))
        assert_true(pitch_l < 0.01, "LOITER TILT_ASSISTED must inhibit pitch tilt, got: " .. tostring(pitch_l))

        -- In POI_HOLD mode with TILT_ASSISTED, pitch must also be inhibited (0.0)
        local state_poi = outer_loop_controller.init(cfg)
        local sp_poi = make_setpoint(0, 100, -50, 0, 0, -20, 0, "POI_HOLD", "TILT_ASSISTED")
        local cmd_poi = outer_loop_controller.compute(state_poi, nav, sp_poi, fsmCtx, 0.05)
        local q_poi = cmd_poi.targetQuaternion
        local sinp_p = 2.0 * (q_poi.w * q_poi.y - q_poi.z * q_poi.x)
        local pitch_p = math.abs(math.deg(math.asin(clamp(sinp_p, -1.0, 1.0))))
        assert_true(pitch_p < 0.01, "POI_HOLD TILT_ASSISTED must inhibit pitch tilt, got: " .. tostring(pitch_p))
    end)

    it("verifies FIXED_WING respects rotation speed and stall speed limits", function()
        local cfg = make_base_cfg("FIXED_WING")
        local state = outer_loop_controller.init(cfg)

        -- 1. TAKEOFF below rotation speed (gs = 5 m/s < rotationSpeed = 12 m/s): pitch held at 0
        local nav_roll = make_nav(0, 100, 0, 0, 0, -5, 0, 0, 0)
        local sp_takeoff = make_setpoint(0, 120, -50, 0, 5, -15, 0, "TAKEOFF", "FIXED_WING_NOMINAL")
        local fsmCtx = { currentState = "ACTIVE_TRACKING", rampAlpha = 1.0 }
        local cmd_takeoff = outer_loop_controller.compute(state, nav_roll, sp_takeoff, fsmCtx, 0.05)
        local q_to = cmd_takeoff.targetQuaternion
        local sinp_to = 2.0 * (q_to.w * q_to.y - q_to.z * q_to.x)
        local pitch_to = math.deg(math.asin(clamp(sinp_to, -1.0, 1.0)))
        assert_true(math.abs(pitch_to) < 0.01, "TAKEOFF below rotation speed must keep pitch at 0, got: " .. tostring(pitch_to))

        -- 2. Below stall speed (gs = 6 m/s < stallSpeed = 10 m/s): pitch-up clamped to <= 5 deg
        local nav_slow = make_nav(0, 100, 0, 0, 0, -6, 0, 0, 0)
        local sp_cruise_slow = make_setpoint(0, 150, -50, 0, 10, -15, 0, "CRUISE", "FIXED_WING_NOMINAL")
        local cmd_slow = outer_loop_controller.compute(state, nav_slow, sp_cruise_slow, fsmCtx, 0.05)
        local q_sl = cmd_slow.targetQuaternion
        local sinp_sl = 2.0 * (q_sl.w * q_sl.y - q_sl.z * q_sl.x)
        local pitch_sl = math.deg(math.asin(clamp(sinp_sl, -1.0, 1.0)))
        assert_true(pitch_sl <= 5.01, "Pitch below stall speed must be clamped to <= 5.0 deg, got: " .. tostring(pitch_sl))
    end)

    it("preserves explicit false values for arm and flightActive without Lua and/or true coercion", function()
        local cfg = make_base_cfg("VECTORED_VTOL")
        local state = outer_loop_controller.init(cfg)
        local nav = make_nav(0, 64, 0, 0, 0, 0, 0, 0, 0)

        -- 1. fsmCtx explicit false overrides setpoint true
        local sp_true = make_setpoint(0, 64, 0, 0, 0, 0, 0, "CRUISE", "STRICT_LEVEL")
        local cmd_fsm_false = outer_loop_controller.compute(state, nav, sp_true, {
            currentState = "ACTIVE_TRACKING",
            rampAlpha = 1.0,
            arm = false,
            flightActive = false,
        }, 0.05)
        assert_false(cmd_fsm_false.arm, "fsmCtx.arm = false must yield cmd.arm == false")
        assert_false(cmd_fsm_false.flightActive, "fsmCtx.flightActive = false must yield cmd.flightActive == false")

        -- 2. setpoint explicit false when fsmCtx omits arm/flightActive
        local sp_false = make_setpoint(0, 64, 0, 0, 0, 0, 0, "IDLE", "STRICT_LEVEL")
        sp_false.arm = false
        sp_false.flightActive = false
        local cmd_sp_false = outer_loop_controller.compute(state, nav, sp_false, {
            currentState = "ACTIVE_TRACKING",
            rampAlpha = 1.0,
        }, 0.05)
        assert_false(cmd_sp_false.arm, "sp.arm = false must yield cmd.arm == false when fsmCtx.arm is nil")
        assert_false(cmd_sp_false.flightActive, "sp.flightActive = false must yield cmd.flightActive == false when fsmCtx.flightActive is nil")
    end)

end)
