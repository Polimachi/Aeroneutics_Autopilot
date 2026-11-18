-- VAS 10-State FSM, 2-Stage Arming, Cold-Boot Recovery & C2 Preemption Module (v1.24.0)
local quat = require("quat")

local state_machine = {}

local AIRBORNE_PERSIST_STATES = {
    NORMAL = true,
    AIRBORNE_RECOVERY_HOLD = true,
    FAILSAFE_HOLD = true,
    EMERGENCY_LAND = true,
    AIRBORNE_EMERGENCY = true,
}

local GROUND_PERSIST_STATES = {
    DISARMED = true,
    IDLE_ARMED = true,
    E_STOP = true,
}

local function resolve_epoch_ms()
    return (os and os.epoch and os.epoch("utc")) or 0
end

function state_machine.load_flight_state(path, fsApi)
    local fsObj = fsApi or _G.fs
    local target = path or "/.flight_state.json"
    if not fsObj or not fsObj.exists or not fsObj.open or not fsObj.exists(target) then
        return nil
    end
    local f = fsObj.open(target, "r")
    if not f then return nil end
    local raw = f.readAll()
    f.close()
    local unjson = textutils and (textutils.unserializeJSON or textutils.unserialiseJSON)
    if type(raw) ~= "string" or raw == "" or not unjson then return nil end
    local ok, parsed = pcall(unjson, raw)
    if not ok or type(parsed) ~= "table" or parsed.schemaVersion ~= 1 then return nil end
    if parsed.armedState ~= "AIRBORNE_ACTIVE" and parsed.armedState ~= "GROUND_SAFE" then
        return nil
    end
    return parsed
end

function state_machine.save_flight_state(path, armedState, extra, fsApi)
    local fsObj = fsApi or _G.fs
    local target = path or "/.flight_state.json"
    local ser = textutils and (textutils.serializeJSON or textutils.serialiseJSON)
    if not fsObj or not fsObj.open or not ser then return false end
    if armedState ~= "AIRBORNE_ACTIVE" and armedState ~= "GROUND_SAFE" then return false end
    local dir = fsObj.getDir and fsObj.getDir(target) or ""
    if dir ~= "" and fsObj.exists and fsObj.makeDir and not fsObj.exists(dir) then
        fsObj.makeDir(dir)
    end
    local ex = type(extra) == "table" and extra or {}
    local snapshot = {
        schemaVersion = 1,
        armedState = armedState,
        missionId = ex.missionId or "",
        currentCpIdx = ex.currentCpIdx or 0,
        homePadId = ex.homePadId or "",
        homePos = ex.homePos or { x = 0.0, y = 0.0, z = 0.0 },
        savedAtEpoch = ex.savedAtEpoch or resolve_epoch_ms(),
    }
    local payload = ser(snapshot)
    if fsObj.move and fsObj.delete and fsObj.exists then
        local tmp = target .. ".tmp"
        local f = fsObj.open(tmp, "w")
        if not f then return false end
        f.write(payload)
        f.close()
        if fsObj.exists(target) then fsObj.delete(target) end
        fsObj.move(tmp, target)
        return true
    end
    local f = fsObj.open(target, "w")
    if not f then return false end
    f.write(payload)
    f.close()
    return true
end

function state_machine.detect_airborne_at_boot(systemConfig, comState, healthMap, flightStateSnapshot)
    local sys = type(systemConfig) == "table" and systemConfig or {}
    local bootCfg = type(sys.bootRecovery) == "table" and sys.bootRecovery or {}
    if bootCfg.enabled == false then return false, "DISABLED" end
    if type(flightStateSnapshot) == "table" and flightStateSnapshot.schemaVersion == 1
        and flightStateSnapshot.armedState == "AIRBORNE_ACTIVE" then
        return true, "SNAPSHOT_AIRBORNE_ACTIVE"
    end
    local dyn = (type(comState) == "table" and type(comState.dynamics) == "table") and comState.dynamics or {}
    local vel = type(dyn.velocity) == "table" and dyn.velocity or {}
    local vx, vy, vz = tonumber(vel.vx) or 0.0, tonumber(vel.vy) or 0.0, tonumber(vel.vz) or 0.0
    local speedNorm = math.sqrt(vx * vx + vy * vy + vz * vz)
    local vSpeed = math.abs(tonumber(dyn.verticalSpeed) or 0.0)
    local speedThresh = tonumber(bootCfg.groundSafeSpeedThresholdMps) or 1.0
    local velValid = (not healthMap) or (healthMap.isVelocityValid ~= false)
    if velValid and (speedNorm > speedThresh or vSpeed > speedThresh) then
        return true, "BOOT_VELOCITY_EXCEEDED"
    end
    local altValid = (not healthMap) or (healthMap.isAltitudeValid ~= false)
    local altThresh = tonumber(bootCfg.groundSafeAltitudeThresholdM) or 2.5
    local snapGroundSafe = type(flightStateSnapshot) == "table"
        and flightStateSnapshot.schemaVersion == 1 and flightStateSnapshot.armedState == "GROUND_SAFE"
    if type(sys.bootRecovery) == "table" and altValid and not snapGroundSafe
        and (tonumber(dyn.altitudeY) or 0.0) > altThresh then
        return true, "BOOT_ALTITUDE_EXCEEDED"
    end
    return false, "GROUND_SAFE"
end

function state_machine.init(systemConfig, isCalibrated)
    local cfg = systemConfig or {}
    local timeouts = cfg.timeouts or {}
    local bootCfg = type(cfg.bootRecovery) == "table" and cfg.bootRecovery or {}
    local now = resolve_epoch_ms()
    local fsm = {
        currentState = isCalibrated and "IDLE_ARMED" or "DISARMED",
        previousState = nil,
        lastTransitionMs = now,
        transitionReason = "INIT",
        lastFcpCmdMs = now,
        lastFcpCmd = nil,
        lastAcroCmdMs = 0,
        lastAcroCmd = nil,
        calibStartMs = 0,
        hoverBaseThrottle = cfg.hoverBaseThrottle or 9.525,
        emergencyVyIntegrator = 0.0,
        emergencyKp = cfg.emergencyKp or (2.0 / 15.0),
        emergencyKi = cfg.emergencyKi or (0.1 / 15.0),
        isAirborne = false,
        contraptionState = "ASSEMBLED",
        recalibrationRequired = false,
        topologyStatus = "NOMINAL",
        navHoldLevel = false,
        activeSource = "FCP",
        sensorLossTicks = 0,
        sensorLossDebounceTicks = timeouts.sensorLossDebounceTicks or 15,
        fcpTimeoutMs = timeouts.fcpCommandTimeoutMs or 1500,
        acroTimeoutMs = timeouts.acroTimeoutMs or 250,
        calibTimeoutSec = timeouts.calibrationTimeoutSec or 120,
        lastPersistedArmedState = nil,
        bootRecovery = {
            enabled = (bootCfg.enabled ~= false),
            persistOnTransition = (type(cfg.bootRecovery) == "table" and bootCfg.enabled ~= false),
            stateFilePath = bootCfg.stateFilePath or "/.flight_state.json",
            bootTimeoutMs = tonumber(bootCfg.bootTimeoutMs) or 500,
            recoveryMaxHoldSec = tonumber(bootCfg.recoveryMaxHoldSec) or 10.0,
            groundSafeAltitudeThresholdM = tonumber(bootCfg.groundSafeAltitudeThresholdM) or 2.5,
            groundSafeSpeedThresholdMps = tonumber(bootCfg.groundSafeSpeedThresholdMps) or 1.0,
            fsApi = bootCfg.fsApi,
        },
    }
    fsm.transition_to = function(self, nextState, reason) return state_machine.transition_to(self, nextState, reason) end
    fsm.arbitrate_c2 = function(self, cmd) return state_machine.arbitrate_c2(self, cmd) end
    fsm.handle_arm_command = function(self, cmd) return state_machine.handle_arm_command(self, cmd) end
    return fsm
end

local function persist_transition_state(state, nextState)
    local br = state.bootRecovery
    if not (br and br.persistOnTransition == true) then return end
    local armedState = AIRBORNE_PERSIST_STATES[nextState] and "AIRBORNE_ACTIVE"
        or (GROUND_PERSIST_STATES[nextState] and "GROUND_SAFE" or nil)
    if armedState and armedState ~= state.lastPersistedArmedState then
        state_machine.save_flight_state(br.stateFilePath, armedState, nil, br.fsApi)
        state.lastPersistedArmedState = armedState
    end
end

function state_machine.transition_to(state, nextState, reason)
    if state.currentState == nextState then return false end
    if state.currentState == "E_STOP" and nextState ~= "E_STOP" then
        return false -- Hard-latched emergency stop
    end
    state.previousState = state.currentState
    state.currentState = nextState
    state.lastTransitionMs = resolve_epoch_ms()
    state.transitionReason = reason or "NOMINAL"
    if nextState == "CALIBRATION" then state.calibStartMs = state.lastTransitionMs end
    persist_transition_state(state, nextState)
    return true
end

function state_machine.compute_emergency_collective(state, targetVy, measVy)
    local tVy = tonumber(targetVy) or 0.0
    local mVy = tonumber(measVy) or 0.0
    local eVy = tVy - mVy
    local baseNorm = (state.hoverBaseThrottle or 9.525) / 15.0
    local kp = state.emergencyKp or (2.0 / 15.0)
    local ki = state.emergencyKi or (0.1 / 15.0)
    local dt = 0.05
    local inVy = (state.emergencyVyIntegrator or 0.0) + eVy * dt * ki
    state.emergencyVyIntegrator = math.max(-0.2, math.min(0.2, inVy))
    local collective = baseNorm + kp * eVy + state.emergencyVyIntegrator
    return math.max(0.0, math.min(1.0, collective))
end

function state_machine.arbitrate_c2(state, cmd)
    if not cmd then return nil end
    if cmd.action == "E_STOP" then
        if cmd.authKey == "ESTOP_CONFIRM_KEY" then
            state.activeSource = "EMERGENCY_DIRECT"
            state_machine.transition_to(state, "E_STOP", "EMERGENCY_OVERRIDE_E_STOP")
            return cmd
        end
        return nil, "ERR_ESTOP_UNAUTHORIZED"
    end
    local isAcroSource = (cmd.source == "MFD_ACRO" or cmd.source == "MFD_DIRECT" or cmd.commandType == "RATE_COMMAND")
    if cmd.acroActive == true or (isAcroSource and cmd.acroActive ~= false) then
        state.activeSource = "MFD_ACRO"
        state.lastAcroCmdMs = resolve_epoch_ms()
        state.lastAcroCmd = cmd
        if state.currentState == "AIRBORNE_RECOVERY_HOLD" then
            state_machine.transition_to(state, "NORMAL", "MFD_ACRO_RECOVERY")
        end
        return cmd
    end
    if cmd.acroActive == false then
        state.activeSource = "FCP"
        state.lastAcroCmd = nil
        return cmd
    end
    if state.activeSource == "MFD_ACRO" then
        return nil, "ERR_PREEMPTED_BY_MFD_ACRO"
    end
    state.activeSource = "FCP"
    return cmd
end

function state_machine.on_actuators_ready(state)
    if state.currentState == "ARMING" then
        return state_machine.transition_to(state, "IDLE_ARMED", "ACTUATOR_READY")
    end
    return false
end

local AIRBORNE_DISASSEMBLY_STATES = {
    NORMAL = true, FAILSAFE_HOLD = true, EMERGENCY_LAND = true, AIRBORNE_RECOVERY_HOLD = true,
}

--- Enforce contraption assembly & re-assembly recalibration safety interlocks.
function state_machine.update_contraption_interlock(state, contraptionState, recalibrationRequired, reason)
    if contraptionState ~= nil then
        state.contraptionState = contraptionState
    end
    if recalibrationRequired ~= nil then
        state.recalibrationRequired = (recalibrationRequired == true)
        state.topologyStatus = state.recalibrationRequired and "RECALIBRATION_REQUIRED" or "NOMINAL"
    end

    if state.contraptionState == "DISASSEMBLED" then
        if state.isAirborne == true or AIRBORNE_DISASSEMBLY_STATES[state.currentState] then
            state_machine.transition_to(state, "E_STOP", reason or "CONTRAPTION_DISASSEMBLED_IN_FLIGHT")
            return false, "CONTRAPTION_DISASSEMBLED_IN_FLIGHT"
        end
        if state.currentState ~= "DISARMED" and state.currentState ~= "E_STOP" then
            state_machine.transition_to(state, "DISARMED", reason or "ERR_CONTRAPTION_DISASSEMBLED")
        end
        return false, "ERR_CONTRAPTION_DISASSEMBLED"
    end

    if state.recalibrationRequired == true then
        if state.isAirborne ~= true and state.currentState ~= "DISARMED" and state.currentState ~= "CALIBRATION" and state.currentState ~= "E_STOP" then
            state_machine.transition_to(state, "DISARMED", reason or "ERR_RECALIBRATION_REQUIRED")
        end
        return false, "ERR_RECALIBRATION_REQUIRED"
    end

    return true, "OK"
end

--- Evaluate 5-stage Pre-Flight PBIT checks (busRtt, inertiaProfile, actuatorWiggle, energyFuel, channelConflict).
function state_machine.evaluate_pbit(state, pbitCtx)
    local ctx = type(pbitCtx) == "table" and pbitCtx or {}
    local checks = {}
    local hasFail = false
    local hasWarn = false
    local summaryReason = nil

    local function record_check(key, status, reason, value)
        checks[key] = { status = status, reason = reason, value = value }
        if status == "FAIL" then
            hasFail = true
            if not summaryReason then summaryReason = reason end
        elseif status == "WARN" then
            hasWarn = true
            if not summaryReason then summaryReason = reason end
        end
    end

    -- 1. Bus & Node RTT
    local rtt = tonumber(ctx.busRttMs)
    if rtt == nil then
        record_check("busRtt", "PASS", "LOCAL_BUS_OK", nil)
    elseif rtt > 200 then
        record_check("busRtt", "FAIL", "BUS_RTT_EXCEEDED", rtt)
    elseif rtt > 50 then
        record_check("busRtt", "WARN", "BUS_RTT_ELEVATED", rtt)
    else
        record_check("busRtt", "PASS", "NOMINAL", rtt)
    end

    -- 2. Inertia & Contraption Topology Profile
    if state.contraptionState == "DISASSEMBLED" then
        record_check("inertiaProfile", "FAIL", "CONTRAPTION_DISASSEMBLED", state.contraptionState)
    elseif state.recalibrationRequired == true then
        record_check("inertiaProfile", "FAIL", "RECALIBRATION_REQUIRED", state.topologyStatus)
    else
        record_check("inertiaProfile", "PASS", "NOMINAL", state.topologyStatus)
    end

    -- 3. Actuator Wiggle (<5% pulse)
    if ctx.actuatorWiggleOk == false then
        record_check("actuatorWiggle", "FAIL", "ACTUATOR_WIGGLE_FAILED", false)
    else
        record_check("actuatorWiggle", "PASS", "NOMINAL", true)
    end

    -- 4. Energy / Fuel Reserve
    local fuel = tonumber(ctx.energyFuel)
    if fuel ~= nil and fuel < 0.10 then
        record_check("energyFuel", "FAIL", "LOW_FUEL_CRITICAL", fuel)
    elseif fuel ~= nil and fuel <= 0.20 then
        record_check("energyFuel", "WARN", "LOW_FUEL_WARN", fuel)
    else
        record_check("energyFuel", "PASS", "NOMINAL", fuel)
    end

    -- 5. Channel Conflict Check
    if ctx.channelConflict == true then
        record_check("channelConflict", "FAIL", "CHANNEL_CONFLICT", true)
    else
        record_check("channelConflict", "PASS", "NOMINAL", false)
    end

    local overallStatus = hasFail and "FAIL" or (hasWarn and "WARN" or "PASS")
    local report = {
        requestId = tostring(ctx.requestId or ("PBIT-" .. tostring(resolve_epoch_ms()))),
        overallStatus = overallStatus,
        takeoffPermitted = (not hasFail),
        contraptionState = state.contraptionState,
        recalibrationRequired = (state.recalibrationRequired == true),
        summaryReason = summaryReason or "ALL_CHECKS_PASS",
        checks = checks,
        timestampMs = resolve_epoch_ms(),
    }
    state.lastPbitReport = report
    return report
end

function state_machine.handle_arm_command(state, cmd)
    if not cmd or cmd.arm == nil then return end
    local curr = state.currentState
    if cmd.arm == false then
        if curr ~= "DISARMED" and curr ~= "E_STOP" and curr ~= "CALIBRATION" and curr ~= "AIRBORNE_RECOVERY_HOLD" then
            state_machine.transition_to(state, "DISARMED", "PILOT_DISARM")
        end
    elseif cmd.arm == true then
        if state.contraptionState == "DISASSEMBLED" then
            return false, "ERR_CONTRAPTION_DISASSEMBLED"
        end
        if state.recalibrationRequired == true then
            return false, "ERR_RECALIBRATION_REQUIRED"
        end
        if cmd.flightActive == true then
            if curr == "DISARMED" or curr == "ARMING" or curr == "IDLE_ARMED"
                or curr == "FAILSAFE_HOLD" or curr == "AIRBORNE_RECOVERY_HOLD" then
                state_machine.transition_to(state, "NORMAL", "FLIGHT_ACTIVE")
            end
        else
            if curr == "DISARMED" then
                state_machine.transition_to(state, "ARMING", "PILOT_ARM_STAGE1")
            end
        end
    end
    return true, "OK"
end

function state_machine.update_watchdogs(state, nowMs, comState, _healthMap, sensorOk, actuatorsReady)
    local now = nowMs or resolve_epoch_ms()
    if comState and comState.dynamics and comState.dynamics.altitudeY then
        state.isAirborne = (comState.dynamics.altitudeY > 2.0)
    end
    if state.activeSource == "MFD_ACRO" and (now - (state.lastAcroCmdMs or 0)) > (state.acroTimeoutMs or 250) then
        state.activeSource = "FCP"
        state.lastAcroCmd = nil
    end
    local curr = state.currentState
    if curr == "ARMING" and actuatorsReady == true then
        state_machine.transition_to(state, "IDLE_ARMED", "ACTUATOR_READY")
    elseif curr == "AIRBORNE_RECOVERY_HOLD" then
        state.isAirborne = true
        local recMaxMs = ((state.bootRecovery and state.bootRecovery.recoveryMaxHoldSec) or 10.0) * 1000
        if (now - state.lastTransitionMs) > recMaxMs then
            state_machine.transition_to(state, "EMERGENCY_LAND", "RECOVERY_HOLD_TIMEOUT_10S")
        end
    elseif curr == "NORMAL" then
        if (now - state.lastFcpCmdMs) > state.fcpTimeoutMs then
            state_machine.transition_to(state, "FAILSAFE_HOLD", "FCP_CMD_TIMEOUT_1500MS")
        elseif not sensorOk then
            state.sensorLossTicks = (state.sensorLossTicks or 0) + 1
            if state.sensorLossTicks >= (state.sensorLossDebounceTicks or 15) then
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
    local curr = state.currentState

    if curr == "NORMAL" and state.navHoldLevel == true then
        local coll = state_machine.compute_emergency_collective(state, 0.0, vy)
        return {
            flightMode = "HOLD_LEVEL",
            commandType = "QUATERNION_RATE",
            targetQuaternion = quat.from_euler(0.0, 0.0, yaw),
            targetAngularRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
            collectiveThrust = coll,
            flapTarget = 0.0,
            translationBias = { surge = 0.0, sway = 0.0 }
        }
    elseif curr == "NORMAL" and state.activeSource == "MFD_ACRO" and state.lastAcroCmd then
        return state.lastAcroCmd
    elseif curr == "NORMAL" and state.lastFcpCmd then
        return state.lastFcpCmd
    elseif curr == "FAILSAFE_HOLD" or curr == "AIRBORNE_RECOVERY_HOLD" then
        local coll = state_machine.compute_emergency_collective(state, 0.0, vy)
        return {
            flightMode = (curr == "AIRBORNE_RECOVERY_HOLD") and "AIRBORNE_RECOVERY_HOLD" or "LOITER",
            commandType = "QUATERNION_RATE",
            targetQuaternion = quat.from_euler(0.0, 0.0, yaw),
            targetAngularRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
            collectiveThrust = coll,
            flapTarget = 0.0,
            translationBias = { surge = 0.0, sway = 0.0 }
        }
    elseif curr == "EMERGENCY_LAND" or curr == "AIRBORNE_EMERGENCY" then
        local descentRate = (curr == "EMERGENCY_LAND") and -1.5 or -1.0
        local coll = state_machine.compute_emergency_collective(state, descentRate, vy)
        local mode = (curr == "AIRBORNE_EMERGENCY") and "EMERGENCY" or "LANDING"
        return {
            flightMode = mode,
            commandType = "QUATERNION_RATE",
            targetQuaternion = quat.from_euler(0.0, 0.0, yaw),
            targetAngularRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
            collectiveThrust = coll,
            flapTarget = 1.0,
            translationBias = { surge = 0.0, sway = 0.0 }
        }
    end
    return {
        flightMode = "IDLE",
        commandType = "QUATERNION_RATE",
        targetQuaternion = quat.identity(),
        targetAngularRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
        collectiveThrust = 0.0,
        flapTarget = 0.0,
        translationBias = { surge = 0.0, sway = 0.0 }
    }
end

function state_machine.apply_output_safety_rule(state, rawOutputs, isAsa)
    local safe = {}
    local curr = state.currentState
    if curr == "E_STOP" then
        if state.isAirborne and not isAsa then
            local cushionT = math.floor((state.hoverBaseThrottle or 9.525) * 0.6 + 0.5)
            for k, v in pairs(rawOutputs or {}) do
                if type(v) == "table" then
                    safe[k] = { thrust = cushionT, gimbalX = 0.0, gimbalY = 0.0 }
                else
                    safe[k] = cushionT
                end
            end
            return safe
        end
        for k, v in pairs(rawOutputs or {}) do
            if type(v) == "table" then
                safe[k] = { thrust = 0, gimbalX = 0.0, gimbalY = 0.0 }
            else
                safe[k] = 0
            end
        end
        return safe
    end
    local isFlight = (curr == "NORMAL" or curr == "AIRBORNE_RECOVERY_HOLD"
        or curr == "FAILSAFE_HOLD" or curr == "EMERGENCY_LAND" or curr == "AIRBORNE_EMERGENCY")
    for k, v in pairs(rawOutputs or {}) do
        if type(v) == "table" then
            safe[k] = {
                thrust = isFlight and (tonumber(v.thrust) or 0) or 0,
                gimbalX = isFlight and (tonumber(v.gimbalX) or 0.0) or 0.0,
                gimbalY = isFlight and (tonumber(v.gimbalY) or 0.0) or 0.0
            }
        else
            safe[k] = isFlight and (tonumber(v) or 0) or 0
        end
    end
    return safe
end

return state_machine
