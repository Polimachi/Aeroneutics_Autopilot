-- VAS 20Hz Realtime Flight Daemon & Orchestrator (VICD-Spec 3-Layer Sandwich v1.10.1)
local sensor_pipeline = require("sensor_pipeline")
local state_machine = require("state_machine")
local flight_dynamics_core = require("flight_dynamics_core")
local vehicle_policy = require("vehicle_policy")
local actuator_adapter_tca = require("actuator_adapter_tca")
local actuator_adapter_asa = require("actuator_adapter_asa")
local network_manager = require("network_manager")
local telemetry_feeder = require("telemetry_feeder")

local core_daemon = {}
local _json_cache = {}

local function load_json(path)
    if _json_cache[path] then return _json_cache[path] end
    if fs and fs.exists(path) then
        local f = fs.open(path, "r")
        if f then
            local txt = f.readAll()
            f.close()
            if textutils and textutils.unserialiseJSON then
                local res = textutils.unserialiseJSON(txt) or {}
                _json_cache[path] = res
                return res
            end
        end
    end
    return {}
end

local function save_json(path, data)
    _json_cache[path] = nil
    if fs and textutils then
        local ser = textutils.serializeJSON or textutils.serialiseJSON
        if ser then
            local f = fs.open(path, "w")
            if f then
                f.write(ser(data))
                f.close()
                return true
            end
        end
    end
    return false
end

local function load_configs(configDir)
    local dir = configDir or "config"
    return {
        sensors = load_json(dir .. "/sensors.json"),
        pid = load_json(dir .. "/pid.json"),
        thrusters = load_json(dir .. "/thrusters.json"),
        surfaces = load_json(dir .. "/surfaces.json"),
        system = load_json(dir .. "/system.json")
    }
end

pcall(load_configs, "config")

local function resolve_debug_flag(cfg)
    if cfg.system.debug == nil and cfg.debug ~= nil then cfg.system.debug = cfg.debug end
    if cfg.system.debug == nil and fs and fs.exists and fs.exists("config.json") then
        local rootCfg = load_json("config.json")
        if rootCfg and rootCfg.debug ~= nil then cfg.system.debug = (rootCfg.debug == true) end
    end
    if cfg.system.debug == nil then cfg.system.debug = true
    else cfg.system.debug = (cfg.system.debug == true) end
end

local function resolve_thruster_config(cfg)
    local thrusterCfg = cfg.thrusters or {}
    if (cfg.system and (cfg.system.vehicleType == "ADVANCED_VTOL" or cfg.system.airframeType == "ADVANCED_VTOL" or cfg.system.isVectorVtol)) then
        thrusterCfg.isVectorVtol = true
        thrusterCfg.airframeType = "ADVANCED_VTOL"
    end
    if cfg.system and cfg.system.pseudoInverseMatrix and not thrusterCfg.pseudoInverseMatrix then
        thrusterCfg.pseudoInverseMatrix = cfg.system.pseudoInverseMatrix
        thrusterCfg.controlEffectivenessMatrix = cfg.system.controlEffectivenessMatrix
    end
    return thrusterCfg
end

function core_daemon.init(configDirOrTable)
    local cfg
    local dir = "config"
    if type(configDirOrTable) == "table" then
        cfg = configDirOrTable
    else
        dir = configDirOrTable or "config"
        cfg = load_configs(dir)
    end
    cfg = cfg or {}
    cfg.system = cfg.system or {}
    resolve_debug_flag(cfg)

    local sensors = sensor_pipeline.init(cfg.sensors)
    local fsm = state_machine.init(cfg.system)
    local net = network_manager.init(cfg.system)
    local fdCore = flight_dynamics_core.init(cfg.pid)
    local policy = vehicle_policy.init(cfg.system)

    local thrusterCfg = resolve_thruster_config(cfg)
    local adapter = actuator_adapter_tca.init(thrusterCfg)
    local adapterAsa = actuator_adapter_asa.init(cfg.surfaces)
    local feeder = telemetry_feeder.init(cfg.system)
    local nowMs = (os.epoch and os.epoch("utc")) or 0

    net.adapterAsa = adapterAsa
    net.on_profile_sync = function(payload)
        save_json(dir .. "/thrusters.json", payload)
        if adapter and adapter.reload_coefficients then
            adapter.reload_coefficients(adapter, payload, false)
        end
    end
    if network_manager.broadcast_discovery then network_manager.broadcast_discovery(net) end

    return {
        cfg = cfg, sensors = sensors, fsm = fsm, net = net, fdCore = fdCore,
        policy = policy, adapter = adapter, adapterAsa = adapterAsa,
        controller = fdCore, mixer = adapter, feeder = feeder,
        running = true, tickCount = 0, lastTickMs = nowMs, timerId = nil
    }
end

local function step_kinematics(state, dt, nowMs)
    local raw = sensor_pipeline.sample_all(state.sensors)
    local comState, healthMap, sensorOk = sensor_pipeline.process_kinematics(state.sensors, raw, dt)
    local rTicks = (state.cfg and state.cfg.sensors and state.cfg.sensors.reconnectTicks) or 20
    if state.tickCount % rTicks == 0 then
        sensor_pipeline.reconnect_faulty(state.sensors, healthMap)
    end
    if not (state.adapter and state.adapter.tcaConnected) and (state.tickCount <= 5 or state.tickCount % rTicks == 0) and network_manager.broadcast_discovery then
        network_manager.broadcast_discovery(state.net)
    end
    state_machine.update_watchdogs(state.fsm, nowMs, comState, healthMap, sensorOk)
    return comState, healthMap, sensorOk
end

local function apply_gimbal_saturation(combSat, compWrench, adapter)
    if not (adapter and adapter.groupStatus) then return end
    local anyGimbalSaturated = false
    for _, gst in pairs(adapter.groupStatus) do
        if gst.gimbalSaturated == true then
            anyGimbalSaturated = true
            break
        end
    end
    if not anyGimbalSaturated then return end
    if (compWrench.surge or 0) > 0.05 then combSat.axisSaturatedPos.surge = true
    elseif (compWrench.surge or 0) < -0.05 then combSat.axisSaturatedNeg.surge = true end
    if (compWrench.sway or 0) > 0.05 then combSat.axisSaturatedPos.sway = true
    elseif (compWrench.sway or 0) < -0.05 then combSat.axisSaturatedNeg.sway = true end
    if (compWrench.pitchTorque or 0) > 0.05 then combSat.axisSaturatedPos.pitch = true
    elseif (compWrench.pitchTorque or 0) < -0.05 then combSat.axisSaturatedNeg.pitch = true end
    if (compWrench.rollTorque or 0) > 0.05 then combSat.axisSaturatedPos.roll = true
    elseif (compWrench.rollTorque or 0) < -0.05 then combSat.axisSaturatedNeg.roll = true end
    if (compWrench.yawTorque or 0) > 0.05 then combSat.axisSaturatedPos.yaw = true
    elseif (compWrench.yawTorque or 0) < -0.05 then combSat.axisSaturatedNeg.yaw = true end
end

local function step_actuation(state, comState, dt)
    state.policy.isDerated = (state.adapter and state.adapter.isStaticFallback == true)
    local fcpCmd = state_machine.get_effective_command(state.fsm, comState)
    local condCmd = vehicle_policy.pre_process_guidance(state.policy, comState, fcpCmd, state.fsm.currentState)
    local sat = state.fdCore.saturationStatus or state.adapter.saturationStatus
    local baseWrench = flight_dynamics_core.compute(state.fdCore, comState, condCmd, dt, sat)
    local compWrench = vehicle_policy.post_process_wrench(state.policy, baseWrench, comState, condCmd)

    local rawTap, satTca = actuator_adapter_tca.allocate(state.adapter, compWrench)
    local isAero = vehicle_policy.is_aerodynamic(state.policy)
    local rawAsa, satAsa = nil, nil
    if isAero then
        local vel = comState and comState.dynamics and comState.dynamics.velocity
        local airspeed = vel and math.sqrt((vel.vx or 0)^2 + (vel.vz or 0)^2) or 0.0
        rawAsa, satAsa = actuator_adapter_asa.allocate(state.adapterAsa, compWrench, airspeed, condCmd.flapTarget)
    end

    local combSat = isAero and vehicle_policy.combine_saturation(satTca, satAsa, condCmd.transitionAlpha) or satTca
    apply_gimbal_saturation(combSat, compWrench, state.adapter)
    state.fdCore.saturationStatus = combSat

    local safeTap = state_machine.apply_output_safety_rule(state.fsm, rawTap, false)
    local safeAsa = (isAero and rawAsa) and state_machine.apply_output_safety_rule(state.fsm, rawAsa, true) or nil
    local dynLoad = actuator_adapter_tca.compute_dynamic_load(state.adapter, safeTap)

    state.fdCore.lastDemands = { pitch = compWrench.pitchTorque, roll = compWrench.rollTorque, yaw = compWrench.yawTorque }
    state.fdCore.saturationFreeze = combSat.axisSaturatedPos.pitch or combSat.axisSaturatedNeg.pitch
        or combSat.axisSaturatedPos.roll or combSat.axisSaturatedNeg.roll
        or combSat.axisSaturatedPos.surge or combSat.axisSaturatedNeg.surge
    return safeTap, safeAsa, dynLoad
end

function core_daemon.tick(state)
    local nowMs = (os.epoch and os.epoch("utc")) or 0
    local dt = math.max(0.005, math.min(0.25, (nowMs - state.lastTickMs) / 1000.0))
    state.lastTickMs = nowMs
    state.tickCount = state.tickCount + 1

    local comState, healthMap, sensorOk = step_kinematics(state, dt, nowMs)
    local safeTap, safeAsa, _ = step_actuation(state, comState, dt)

    network_manager.send_packet(state.net, state.net.channels.actuation, "MSG_THRUST_CMD", {
        watchdogSeq = state.tickCount, controlState = state.fsm.currentState, outputs = safeTap
    })
    local isAero = vehicle_policy.is_aerodynamic(state.policy)
    if isAero and safeAsa then
        network_manager.send_packet(state.net, state.net.channels.aero, "MSG_AERO_CMD", {
            watchdogSeq = state.tickCount, controlState = state.fsm.currentState, surfaces = safeAsa
        })
    end

    local tapOk = (state.adapter.healthStatus ~= "API_TOTAL_LOSS")
    local asaOk = isAero and (state.adapterAsa.healthStatus ~= "API_TOTAL_LOSS") or true
    telemetry_feeder.tick(state.feeder, state.net, comState, state.fsm, state.mixer, {
        sensorOk = sensorOk, sensorHealth = healthMap,
        actuatorHealth = { tap = tapOk, asa = asaOk }
    })
    return true
end

function core_daemon.shutdown(state, reason)
    state.running = false
    local r = reason or "SHUTDOWN"
    local fsm = state.fsm or { currentState = "E_STOP" }
    if fsm.isAirborne == true and state.net and network_manager.send_emergency_alert then
        local altY = (state.sensors and state.sensors.lastCom and state.sensors.lastCom.dynamics and state.sensors.lastCom.dynamics.altitudeY) or 0.0
        network_manager.send_emergency_alert(state.net, {
            reason = r, isAirborne = true, fsmState = fsm.currentState, altitude = altY
        })
    end
    local isAero = vehicle_policy.is_aerodynamic(state.policy)
    local safeTap = state_machine.apply_output_safety_rule(fsm, {}, false)
    local safeAsa = isAero and state_machine.apply_output_safety_rule(fsm, {}, true) or nil
    network_manager.send_packet(state.net, state.net.channels.actuation, "MSG_THRUST_CMD", {
        watchdogSeq = 0, controlState = "E_STOP", outputs = safeTap
    })
    if isAero and safeAsa then
        network_manager.send_packet(state.net, state.net.channels.aero, "MSG_AERO_CMD", {
            watchdogSeq = 0, controlState = "E_STOP", surfaces = safeAsa
        })
    end
end

function core_daemon.handle_event(state, event, p1, p2, p3, p4)
    if event == "timer" and p1 == state.timerId then
        local ok, err = pcall(core_daemon.tick, state)
        if not ok then
            local nextSt = (state.fsm and state.fsm.isAirborne) and "AIRBORNE_EMERGENCY" or "E_STOP"
            state_machine.transition_to(state, nextSt, "PANIC: " .. tostring(err))
        end
        if state.running and os.startTimer then state.timerId = os.startTimer(0.05) end
        return true
    elseif event == "modem_message" then
        return network_manager.dispatch(state.net, state.fsm, state.controller, state.mixer, p2, p3, p4)
    elseif event == "terminate" then
        core_daemon.shutdown(state, "TERMINATE")
        return true
    end
    return false
end

function core_daemon.run(configDir)
    local state = core_daemon.init(configDir)
    if os.startTimer then state.timerId = os.startTimer(0.05) end
    return state
end

return core_daemon
