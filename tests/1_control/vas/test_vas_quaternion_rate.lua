-- Unit test suite for VAS Zero-Fallback QUATERNION_RATE & Dynamics (TASK-209)
local quat = require("quat")
local vehicle_policy = require("vehicle_policy")
local flight_dynamics_core = require("flight_dynamics_core")
local state_machine = require("state_machine")

describe("vas vehicle_policy zero-fallback quaternion_rate parsing", function()
    it("parses targetQuaternion cleanly and rejects legacy orientation and throttle", function()
        local pol = vehicle_policy.init({ vehicleType = "WINGED_VTOL", stallGuard = { flapVfeLimit = 15.0 } })

        local cmd = {
            commandType = "QUATERNION_RATE",
            targetQuaternion = { w = 0.7071, x = 0.0, y = 0.7071, z = 0.0 },
            targetAngularRates = { pitchRate = 1.0, rollRate = -2.0, yawRate = 0.5 },
            collectiveThrust = 0.75,
            translationBias = { surge = 0.3, sway = -0.2, heave = 0.8 },
            -- Legacy deprecated fields that must be ignored
            targetOrientation = { pitch = 45.0, roll = 0.0, yaw = 0.0 },
            angleTargets = { targetPitch = 30.0, targetRoll = 0.0, targetHeading = 0.0 },
            targetThrottle = 0.9,
            targetClimbRate = 4.0
        }

        local targetQ = vehicle_policy.resolve_guidance_targets(cmd)
        assert_near(targetQ.w, 0.7071, 1e-4)
        assert_near(targetQ.y, 0.7071, 1e-4)
        assert_near(targetQ.x, 0.0, 1e-4)

        -- If targetQuaternion is omitted, legacy fields must NOT be used
        local legacyOnlyCmd = {
            targetOrientation = { pitch = 45.0, roll = 0.0, yaw = 0.0 },
            angleTargets = { targetPitch = 30.0, targetRoll = 0.0, targetHeading = 0.0 }
        }
        local defaultQ = vehicle_policy.resolve_guidance_targets(legacyOnlyCmd)
        assert_near(defaultQ.w, 1.0, 1e-6)
        assert_near(defaultQ.x, 0.0, 1e-6)
        assert_near(defaultQ.y, 0.0, 1e-6)
        assert_near(defaultQ.z, 0.0, 1e-6)
    end)

    it("pre-processes guidance command with zero-fallback output schema", function()
        local pol = vehicle_policy.init({ vehicleType = "WINGED_VTOL", stallGuard = { flapVfeLimit = 15.0 } })
        local telem = {
            airspeed = 12.0,
            sensorHealth = { isAttitudeValid = true, isVelocityValid = true, isAirspeedValid = true }
        }
        local rawCmd = {
            commandType = "QUATERNION_RATE",
            targetQuaternion = { w = 1.0, x = 0.0, y = 0.0, z = 0.0 },
            targetAngularRates = { pitchRate = 0.5, rollRate = 0.0, yawRate = -0.5 },
            collectiveThrust = 0.65,
            flapTarget = 0.8,
            translationBias = { surge = 0.1, sway = -0.1, heave = 0.9 },
            targetThrottle = 0.99,
            targetClimbRate = 3.5
        }

        local cond = vehicle_policy.pre_process_guidance(pol, telem, rawCmd, "NORMAL")
        assert_eq(cond.commandType, "QUATERNION_RATE")
        assert_near(cond.collectiveThrust, 0.65, 1e-4)
        assert_near(cond.targetAngularRates.pitchRate, 0.5, 1e-4)
        assert_near(cond.targetAngularRates.yawRate, -0.5, 1e-4)
        assert_near(cond.translationBias.surge, 0.1, 1e-4)
        assert_near(cond.translationBias.sway, -0.1, 1e-4)
        assert_nil(cond.translationBias.heave)
        assert_nil(cond.targetThrottle)
        assert_nil(cond.targetClimbRate)
        assert_nil(cond.targetOrientation)
    end)

    it("enforces vFe flap clamping at 15.0 m/s default", function()
        local pol = vehicle_policy.init({ vehicleType = "FIXED_WING" })
        assert_eq(pol.vFe, 15.0)

        local flapUnder = vehicle_policy.resolve_flap_target(pol, { flapTarget = 0.75 }, 14.0, { velocity = true })
        assert_near(flapUnder, 0.75, 1e-4)

        local flapOver = vehicle_policy.resolve_flap_target(pol, { flapTarget = 0.75 }, 16.0, { velocity = true })
        assert_eq(flapOver, 0.0)
    end)

    it("applies stall guard to collectiveThrust and nose-down targetQuaternion", function()
        local pol = vehicle_policy.init({ vehicleType = "FIXED_WING", stallGuard = { minStallThrottle = 0.40 } })
        assert_near(pol.minStallThrottle, 0.40, 1e-6)
        local telem = {
            airspeed = 8.0,
            sensorHealth = { velocity = true, isVelocityValid = true, isAirspeedValid = true }
        }
        local cond = {
            collectiveThrust = 0.20,
            targetQuaternion = quat.from_euler(10.0, 0.0, 0.0)
        }
        vehicle_policy.apply_stall_guard(pol, telem, cond)

        assert_true(cond.collectiveThrust >= 0.40)
        local eul = quat.to_euler(cond.targetQuaternion)
        assert_true(eul.pitch <= -5.0 + 1e-3)
    end)
end)

describe("vas flight_dynamics_core normal-flight vertical PI removal", function()
    it("produces identical heave regardless of vertical speed during normal flight", function()
        local fdc = flight_dynamics_core.init({})
        local guidance = {
            commandType = "QUATERNION_RATE",
            targetQuaternion = quat.identity(),
            targetAngularRates = { pitchRate = 0, rollRate = 0, yawRate = 0 },
            collectiveThrust = 0.635,
            transitionAlpha = 0.0
        }

        local telemHover = {
            orientation = quat.identity(),
            verticalSpeed = 0.0,
            angularRate = { pitchRate = 0, rollRate = 0, yawRate = 0 }
        }
        local wrenchHover = flight_dynamics_core.compute(fdc, telemHover, guidance, 0.05)

        local telemFalling = {
            orientation = quat.identity(),
            verticalSpeed = -5.0,
            angularRate = { pitchRate = 0, rollRate = 0, yawRate = 0 }
        }
        local wrenchFalling = flight_dynamics_core.compute(fdc, telemFalling, guidance, 0.05)

        local telemClimbing = {
            orientation = quat.identity(),
            verticalSpeed = 8.0,
            angularRate = { pitchRate = 0, rollRate = 0, yawRate = 0 }
        }
        local wrenchClimbing = flight_dynamics_core.compute(fdc, telemClimbing, guidance, 0.05)

        -- Heave must be open-loop from collectiveThrust * 15.0 = 9.525
        assert_near(wrenchHover.heave, 9.525, 1e-3)
        assert_near(wrenchFalling.heave, 9.525, 1e-3)
        assert_near(wrenchClimbing.heave, 9.525, 1e-3)
        assert_eq(wrenchHover.heave, wrenchFalling.heave)
        assert_eq(wrenchHover.heave, wrenchClimbing.heave)
        assert_near(fdc.integrators.climb, 0.0, 1e-6)
    end)

    it("blends surge and heave with transitionAlpha for winged airframes", function()
        local fdc = flight_dynamics_core.init({})
        local baseGuidance = {
            commandType = "QUATERNION_RATE",
            targetQuaternion = quat.identity(),
            collectiveThrust = 0.8,
            translationBias = { surge = 2.0, sway = 0.5 }
        }
        local telem = { orientation = quat.identity(), verticalSpeed = 0.0 }

        -- Alpha = 0.0 (Pure hover)
        baseGuidance.transitionAlpha = 0.0
        local wHover = flight_dynamics_core.compute(fdc, telem, baseGuidance, 0.05)
        assert_near(wHover.heave, 12.0, 1e-3)
        assert_near(wHover.surge, 2.0, 1e-3)
        assert_near(wHover.sway, 0.5, 1e-3)

        -- Alpha = 0.5 (Mid transition)
        baseGuidance.transitionAlpha = 0.5
        local wMid = flight_dynamics_core.compute(fdc, telem, baseGuidance, 0.05)
        assert_near(wMid.heave, 6.0, 1e-3)
        assert_near(wMid.surge, 7.0, 1e-3) -- 2.0 * 0.5 + 12.0 * 0.5

        -- Alpha = 1.0 (Full cruise)
        baseGuidance.transitionAlpha = 1.0
        local wCruise = flight_dynamics_core.compute(fdc, telem, baseGuidance, 0.05)
        assert_near(wCruise.heave, 0.0, 1e-3)
        assert_near(wCruise.surge, 12.0, 1e-3)
    end)

    it("tracks targetAngularRates feedforward in QUATERNION_RATE and direct in RATE_COMMAND", function()
        local fdc = flight_dynamics_core.init({})

        -- QUATERNION_RATE: rate error is 0 when measuring target rates
        local targetRates = { pitchRate = 5.0, rollRate = -3.0, yawRate = 1.0 }
        local measRates = { x = 5.0, y = -3.0, z = 1.0 }
        local wRateZero = flight_dynamics_core.compute_attitude_wrench(
            fdc, quat.identity(), quat.identity(), measRates, 0.05, nil, targetRates, "QUATERNION_RATE"
        )
        assert_near(wRateZero.pitchTorque, 0.0, 1e-4)
        assert_near(wRateZero.rollTorque, 0.0, 1e-4)
        assert_near(wRateZero.yawTorque, 0.0, 1e-4)

        -- RATE_COMMAND: outer quaternion error bypassed, pure rate error tracked
        local targetQOffset = quat.from_euler(45.0, 30.0, 20.0)
        local wAcro = flight_dynamics_core.compute_attitude_wrench(
            fdc, targetQOffset, quat.identity(), { x = 0, y = 0, z = 0 }, 0.05, nil, { pitchRate = 4.0, rollRate = 0, yawRate = 0 }, "RATE_COMMAND"
        )
        -- pitchTorque should only be Kd * 4.0 = 0.45 * 4.0 = 1.8
        assert_near(wAcro.pitchTorque, 1.8, 1e-3)
        assert_near(wAcro.rollTorque, 0.0, 1e-3)
        assert_near(wAcro.yawTorque, 0.0, 1e-3)
    end)

    it("ignores deprecated targetOrientation key in flight_dynamics_core.compute (Zero-Fallback)", function()
        local fdc = flight_dynamics_core.init({})
        local telem = {
            orientation = quat.identity(),
            angularRate = { x = 0, y = 0, z = 0 },
        }
        local legacyGuidance = {
            commandType = "QUATERNION_RATE",
            targetOrientation = quat.from_euler(35.0, -25.0, 45.0),
            collectiveThrust = 0.635,
        }
        local wrench = flight_dynamics_core.compute(fdc, telem, legacyGuidance, 0.05)
        assert_near(wrench.rollTorque, 0.0, 1e-6)
        assert_near(wrench.pitchTorque, 0.0, 1e-6)
        assert_near(wrench.yawTorque, 0.0, 1e-6)
    end)
end)

describe("vas state_machine failsafe vertical PI and C2 arbitration", function()
    it("computes emergency collective in FAILSAFE_HOLD and EMERGENCY_LAND", function()
        local fsm = state_machine.init({ hoverBaseThrottle = 9.525 }, true)
        fsm.currentState = "FAILSAFE_HOLD"

        local comZero = { dynamics = { verticalSpeed = 0.0 }, attitude = { yaw = 45.0 } }
        local cmdHold = state_machine.get_effective_command(fsm, comZero)
        assert_eq(cmdHold.commandType, "QUATERNION_RATE")
        assert_near(cmdHold.collectiveThrust, 0.635, 1e-3)
        assert_nil(cmdHold.targetThrottle)
        assert_nil(cmdHold.targetClimbRate)

        -- Falling in hold increases collective
        local comFalling = { dynamics = { verticalSpeed = -2.0 }, attitude = { yaw = 45.0 } }
        local cmdFall = state_machine.get_effective_command(fsm, comFalling)
        assert_true(cmdFall.collectiveThrust > cmdHold.collectiveThrust)

        -- EMERGENCY_LAND sets descent target -1.5 m/s
        fsm.currentState = "EMERGENCY_LAND"
        local cmdLand = state_machine.get_effective_command(fsm, comZero)
        assert_eq(cmdLand.commandType, "QUATERNION_RATE")
        assert_eq(cmdLand.flapTarget, 1.0)
        assert_true(cmdLand.collectiveThrust < cmdHold.collectiveThrust)
    end)

    it("arbitrates C2 requiring ESTOP_CONFIRM_KEY and preemption priority", function()
        local fsm = state_machine.init({}, true)
        fsm.currentState = "NORMAL"

        -- E_STOP without authKey is rejected
        local rejected = state_machine.arbitrate_c2(fsm, { action = "E_STOP" })
        assert_nil(rejected)
        assert_eq(fsm.currentState, "NORMAL")

        -- MFD_ACRO preempts FCP
        state_machine.arbitrate_c2(fsm, { source = "FCP", commandType = "QUATERNION_RATE" })
        assert_eq(fsm.activeSource, "FCP")

        state_machine.arbitrate_c2(fsm, { source = "MFD_DIRECT", commandType = "RATE_COMMAND", acroActive = true })
        assert_eq(fsm.activeSource, "MFD_ACRO")

        -- Clean return to FCP when acroActive is false
        state_machine.arbitrate_c2(fsm, { source = "FCP", commandType = "QUATERNION_RATE", acroActive = false })
        assert_eq(fsm.activeSource, "FCP")

        -- Valid E_STOP overrides everything
        local accepted = state_machine.arbitrate_c2(fsm, { action = "E_STOP", authKey = "ESTOP_CONFIRM_KEY" })
        assert_not_nil(accepted)
        assert_eq(fsm.currentState, "E_STOP")
        assert_eq(fsm.activeSource, "EMERGENCY_DIRECT")
    end)
end)
