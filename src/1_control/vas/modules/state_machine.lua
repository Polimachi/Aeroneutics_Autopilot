-- VAS 9-State FSM, 2-Stage Arming & C2 Preemption Module (v1.10.0)
local state_machine = {}

function state_machine.init(systemConfig, isCalibrated)
    local cfg = systemConfig or {}
    local timeouts = cfg.timeouts or {}
    local now = (os.epoch and os.epoch("utc")) or 0
    local fsm = {
        currentState = isCalibrated and "IDLE_ARMED" or "DISARMED",
        previousState = nil,
        lastTransitionMs = now,
        transitionReason = "INIT",
        lastFcpCmdMs = now,
        lastFcpCmd = nil,
        calibStartMs = 0,
        hoverBaseThrottle = 7.5,
        isAirborne = false,
        activeSource = "FCP",
        sensorLossTicks = 0,
        sensorLossDebounceTicks = timeouts.sensorLossDebounceTicks or 1,
        fcpTimeoutMs = timeouts.fcpCommandTimeoutMs or 1500,
        calibTimeoutSec = timeouts.calibrationTimeoutSec or 120
    }
    fsm.transition_to = function(self, nextState, reason)
        return state_machine.transition_to(self, nextState, reason)
    end
    fsm.arbitrate_c2 = function(self, cmd)
        return state_machine.arbitrate_c2(self, cmd)
    end
    fsm.handle_arm_command = function(self, cmd)
        return state_machine.handle_arm_command(self, cmd)
    end
    return fsm
end

function state_machine.transition_to(state, nextState, reason)
    if state.currentState == nextState then return false end
    if state.currentState == "E_STOP" and nextState ~= "E_STOP" then
        return false -- Hard-latched emergency stop
    end
    state.previousState = state.currentState
    state.currentState = nextState
    state.lastTransitionMs = (os.epoch and os.epoch("utc")) or 0
    state.transitionReason = reason or "NOMINAL"
    if nextState == "CALIBRATION" then state.calibStartMs = state.lastTransitionMs end
    return true
end

function state_machine.arbitrate_c2(state, cmd)
    if not cmd then return nil end
    local action = cmd.emergencyAction or (cmd.eStop and "E_STOP") or (cmd.action == "E_STOP" and "E_STOP")
    if action == "E_STOP" then
        state.activeSource = "EMERGENCY_DIRECT"
        state_machine.transition_to(state, "E_STOP", "EMERGENCY_OVERRIDE_E_STOP")
        return cmd
    end
    if cmd.acroActive == true or cmd.source == "PILOT_MFD" or cmd.source == "MFD_ACRO" then
        state.activeSource = "MFD_ACRO"
        return cmd
    end
    state.activeSource = "FCP"
    return cmd
end

function state_machine.handle_arm_command(state, cmd)
    if not cmd or cmd.arm == nil then return end
    local curr = state.currentState
    if cmd.arm == false then
        if curr ~= "DISARMED" and curr ~= "E_STOP" and curr ~= "CALIBRATION" then
            state_machine.transition_to(state, "DISARMED", "PILOT_DISARM")
        end
    elseif cmd.arm == true then
        if cmd.flightActive == true then
            if curr == "DISARMED" or curr == "ARMING" or curr == "IDLE_ARMED" or curr == "FAILSAFE_HOLD" then
                state_machine.transition_to(state, "NORMAL", "FLIGHT_ACTIVE")
            end
        else
            if curr == "DISARMED" then
                state_machine.transition_to(state, "ARMING", "PILOT_ARM_STAGE1")
            end
        end
    end
end

function state_machine.update_watchdogs(state, nowMs, comState, _healthMap, sensorOk)
    local now = nowMs or ((os.epoch and os.epoch("utc")) or 0)
    if comState and comState.dynamics and comState.dynamics.altitudeY then
        state.isAirborne = (comState.dynamics.altitudeY > 2.0)
    end
    local curr = state.currentState
    if curr == "NORMAL" then
        if (now - state.lastFcpCmdMs) > state.fcpTimeoutMs then
            state_machine.transition_to(state, "FAILSAFE_HOLD", "FCP_CMD_TIMEOUT_1500MS")
        elseif not sensorOk then
            state.sensorLossTicks = (state.sensorLossTicks or 0) + 1
            if state.sensorLossTicks >= (state.sensorLossDebounceTicks or 1) then
                state_machine.transition_to(state, "FAILSAFE_HOLD", "SENSOR_HEALTH_DROPPED")
            end
        else
            state.sensorLossTicks = 0
        end
    elseif curr == "CALIBRATION" then
        if (now - state.calibStartMs) > (state.calibTimeoutSec * 1000) then
            state_machine.transition_to(state, "IDLE_ARMED", "CALIB_TIMEOUT_120S_EXPIRED")
        end
    elseif curr == "FAILSAFE_HOLD" then
        if (now - state.lastTransitionMs) > 10000 then
            state_machine.transition_to(state, "EMERGENCY_LAND", "FAILSAFE_HOLD_TIMEOUT_10S")
        end
    elseif curr == "AIRBORNE_EMERGENCY" or curr == "EMERGENCY_LAND" then
        if not state.isAirborne and (now - state.lastTransitionMs) > 2000 then
            state_machine.transition_to(state, "E_STOP", "TOUCHDOWN_HALT")
        end
    end
end

function state_machine.get_effective_command(state, comState)
    local vy = (comState and comState.dynamics and comState.dynamics.verticalSpeed) or 0.0
    local yaw = (comState and comState.attitude and comState.attitude.yaw) or 0.0
    local baseT = state.hoverBaseThrottle or 7.5
    local curr = state.currentState

    if curr == "NORMAL" and state.lastFcpCmd then
        return state.lastFcpCmd
    elseif curr == "FAILSAFE_HOLD" then
        local trim = baseT + 2.0 * (0.0 - vy)
        return {
            flightMode = "LOITER", commandType = "ATTITUDE_ANGLE",
            angleTargets = { targetPitch = 0.0, targetRoll = 0.0, targetHeading = yaw, turnRateFF = 0.0 },
            targetThrottle = math.max(0.0, math.min(15.0, trim)), targetClimbRate = 0.0, flapTarget = 0.0,
            translationBias = { surge = 0.0, sway = 0.0, heave = 0.0 }
        }
    elseif curr == "EMERGENCY_LAND" or curr == "AIRBORNE_EMERGENCY" then
        local descentRate = (curr == "EMERGENCY_LAND") and -1.5 or -1.0
        local descentT = baseT + 2.0 * (descentRate - vy)
        local mode = (curr == "AIRBORNE_EMERGENCY") and "EMERGENCY" or "LANDING"
        return {
            flightMode = mode, commandType = "ATTITUDE_ANGLE",
            angleTargets = { targetPitch = 0.0, targetRoll = 0.0, targetHeading = yaw, turnRateFF = 0.0 },
            targetThrottle = math.max(0.0, math.min(15.0, descentT)), targetClimbRate = descentRate, flapTarget = 1.0,
            translationBias = { surge = 0.0, sway = 0.0, heave = 0.0 }
        }
    end
    return { flightMode = "IDLE", commandType = "ATTITUDE_ANGLE", targetThrottle = 0.0, targetClimbRate = 0.0, flapTarget = 0.0, translationBias = {} }
end

function state_machine.apply_output_safety_rule(state, rawOutputs, isAsa)
    local safe = {}
    local curr = state.currentState
    if curr == "E_STOP" then
        if state.isAirborne and not isAsa then
            local cushionT = math.floor((state.hoverBaseThrottle or 7.5) * 0.6 + 0.5)
            for k, _ in pairs(rawOutputs or {}) do safe[k] = cushionT end
            return safe
        end
        for k, _ in pairs(rawOutputs or {}) do safe[k] = 0 end
        return safe
    end
    local isFlight = (curr == "NORMAL" or curr == "FAILSAFE_HOLD" or curr == "EMERGENCY_LAND" or curr == "AIRBORNE_EMERGENCY")
    for k, v in pairs(rawOutputs or {}) do
        safe[k] = isFlight and (tonumber(v) or 0) or 0
    end
    return safe
end

return state_machine
