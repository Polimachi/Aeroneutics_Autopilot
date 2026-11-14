-- VAS Telemetry Feeder & MFD Downsampler Module (v1.10.0)
local network_manager = require("network_manager")

local telemetry_feeder = {}

function telemetry_feeder.init(systemConfig)
    return {
        tickCounter = 0,
        telemetryDiag = (systemConfig and systemConfig.telemetryDiag == true) or false,
    }
end

local function normalize_actuator_health(diagState)
    local ah = diagState and diagState.actuatorHealth
    if not ah then return { tap = true, asa = true, allOk = true } end
    local tap = (ah.tap ~= false)
    local asa = (ah.asa ~= false)
    local allOk = (ah.allOk ~= nil) and (ah.allOk == true) or (tap and asa)
    return { tap = tap, asa = asa, allOk = allOk }
end

local function build_mfd_dynamics(comState)
    local d = (comState and comState.dynamics) or {}
    local v = d.velocity or {}
    local gs = d.groundSpeed or math.sqrt((v.vx or 0.0)^2 + (v.vz or 0.0)^2)
    return {
        altitudeY = d.altitudeY or 0.0,
        verticalSpeed = d.verticalSpeed or 0.0,
        groundSpeed = gs,
        velocity = d.velocity
    }
end

local function build_telem_payload(state, comState, fsmState, mixerState, diagState)
    local d = diagState or {}
    local payload = {
        attitude = comState.attitude,
        angularRates = comState.rates,
        dynamics = comState.dynamics,
        fuel = comState.fuel,
        dynamicLoad = (mixerState and mixerState.dynamicLoad) or 0.0,
        controlState = fsmState.currentState,
        activeSource = fsmState.activeSource or "FCP",
        sensorOk = d.sensorOk == true,
        sensorHealth = d.sensorHealth,
        actuatorHealth = normalize_actuator_health(d)
    }
    if state and state.telemetryDiag == true then
        if d.satFlags ~= nil then payload.satFlags = d.satFlags end
        if d.diag ~= nil then payload.diag = d.diag end
    end
    return payload
end

local function build_mfd_payload(comState, fsmState, mixerState, diagState, isAcro)
    return {
        source = isAcro and "CORE_ACRO_TAKEOVER" or "CORE_FAILSAFE",
        fsmState = fsmState.currentState,
        controlState = fsmState.currentState,
        flightMode = isAcro and "ACRO" or fsmState.currentState,
        acroActive = isAcro == true,
        attitude = comState.attitude,
        angularRates = comState.rates,
        dynamics = build_mfd_dynamics(comState),
        fuel = comState.fuel,
        dynamicLoad = (mixerState and mixerState.dynamicLoad) or 0.0,
        sensorOk = diagState.sensorOk == true,
        sensorHealth = diagState.sensorHealth,
        actuatorHealth = normalize_actuator_health(diagState)
    }
end

function telemetry_feeder.tick(state, netState, comState, fsmState, mixerState, diagState)
    state.tickCounter = state.tickCounter + 1

    local telemPayload = build_telem_payload(state, comState, fsmState, mixerState, diagState)
    network_manager.send_packet(netState, netState.channels.telemetry, "MSG_FLIGHT_TELEMETRY", telemPayload)
    if netState and netState.hangarChannels and netState.hangarChannels.telem then
        network_manager.send_packet(netState, netState.hangarChannels.telem, "MSG_FLIGHT_TELEMETRY", telemPayload)
    end

    local isAcro = (fsmState and fsmState.activeSource == "MFD_ACRO")
    local isFailsafe = (fsmState and (fsmState.currentState == "FAILSAFE_HOLD" or fsmState.currentState == "EMERGENCY_LAND"))

    if isAcro or (isFailsafe and (state.tickCounter % 4 == 0)) then
        local mfdPayload = build_mfd_payload(comState, fsmState, mixerState, diagState, isAcro)
        network_manager.send_packet(netState, netState.channels.mfd, "MSG_MFD_STATE", mfdPayload)
    end
end

return telemetry_feeder
