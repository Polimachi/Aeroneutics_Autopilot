-- VAS Telemetry Feeder & MFD Downsampler Module (v1.10.0)
local network_manager = require("network_manager")

local telemetry_feeder = {}

function telemetry_feeder.init(systemConfig)
    local _ = systemConfig
    return {
        tickCounter = 0
    }
end

local function build_telem_payload(comState, fsmState, mixerState, diagState)
    return {
        attitude = comState.attitude,
        angularRates = comState.rates,
        dynamics = comState.dynamics,
        fuel = comState.fuel,
        dynamicLoad = (mixerState and mixerState.dynamicLoad) or 0.0,
        controlState = fsmState.currentState,
        activeSource = fsmState.activeSource or "FCP",
        sensorOk = diagState.sensorOk == true,
        sensorHealth = diagState.sensorHealth,
        actuatorHealth = diagState.actuatorHealth or { tap = true, wap = true }
    }
end

local function build_mfd_payload(comState, fsmState, mixerState, diagState)
    return {
        fsmState = fsmState.currentState,
        pitch = comState.attitude.pitch,
        roll = comState.attitude.roll,
        yaw = comState.attitude.yaw,
        altitude = comState.dynamics.altitudeY,
        vy = comState.dynamics.verticalSpeed,
        fuel = comState.fuel,
        dynamicLoad = (mixerState and mixerState.dynamicLoad) or 0.0,
        sensorHealth = diagState.sensorHealth
    }
end

function telemetry_feeder.tick(state, netState, comState, fsmState, mixerState, diagState)
    state.tickCounter = state.tickCounter + 1

    local telemPayload = build_telem_payload(comState, fsmState, mixerState, diagState)
    network_manager.send_packet(netState, netState.channels.telemetry, "MSG_FLIGHT_TELEMETRY", telemPayload)
    if netState and netState.hangarChannels and netState.hangarChannels.telem then
        network_manager.send_packet(netState, netState.hangarChannels.telem, "MSG_FLIGHT_TELEMETRY", telemPayload)
    end

    local isAcro = (fsmState and fsmState.activeSource == "MFD_ACRO")
    local isFailsafe = (fsmState and (fsmState.currentState == "FAILSAFE_HOLD" or fsmState.currentState == "EMERGENCY_LAND"))

    if isAcro or (isFailsafe and (state.tickCounter % 4 == 0)) then
        local mfdPayload = build_mfd_payload(comState, fsmState, mixerState, diagState)
        network_manager.send_packet(netState, netState.channels.mfd, "MSG_MFD_STATE", mfdPayload)
    end
end

return telemetry_feeder
