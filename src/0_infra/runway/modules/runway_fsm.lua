-- src/0_infra/runway/modules/runway_fsm.lua
-- Finite State Machine and GAC local backbone protocol mediator for Runway

local runway_fsm = {}

local UNSTABLE_ABORT_THRESHOLD_SEC = 3.0
local DEFAULT_COMPATIBLE_AIRFRAMES = {
    FIXED_WING = true,
    WINGED_VTOL = true,
}

local function is_airframe_compatible(config, af)
    if not af then return true end
    if config.supportedAirframeTypes then
        for _, sup in ipairs(config.supportedAirframeTypes) do
            if sup == af then return true end
        end
        return false
    end
    return DEFAULT_COMPATIBLE_AIRFRAMES[af] == true
end

function runway_fsm.create(config, streamer, initialSensorHealthy)
    if not config then error("config table required", 2) end
    if not streamer then error("streamer required", 2) end
    local isSensorHealthy = (initialSensorHealthy ~= false)
    local initialState = (config.mobility == "DYNAMIC" and not isSensorHealthy) and "MAINTENANCE" or "IDLE"

    local state = {
        currentState = initialState,
        currentCraft = nil,
        currentAirframe = nil,
        slotExpiresAt = 0.0,
        unstableStartSec = nil,
        seq = 20000,
        faultCode = (initialState == "MAINTENANCE") and "SENSOR_UNAVAILABLE" or nil,
    }
    local fsm = {}
    local function next_seq() state.seq = state.seq + 1; return state.seq end

    function fsm:get_state() return state.currentState end
    function fsm:get_current_craft() return state.currentCraft end
    function fsm:get_current_airframe() return state.currentAirframe end
    function fsm:get_fault_code() return state.faultCode end

    function fsm:get_slot_remaining_sec(nowSec)
        if not state.slotExpiresAt or state.slotExpiresAt <= 0 then return 0 end
        return math.max(0, state.slotExpiresAt - (nowSec or (os.clock and os.clock() or 0)))
    end

    function fsm:set_sensor_healthy(healthy)
        isSensorHealthy = healthy
        if not healthy and config.mobility == "DYNAMIC" then
            local out = {}
            if state.currentState == "APPROACH_DYNAMIC" and state.currentCraft then
                table.insert(out, streamer:build_abort_approach(next_seq(), state.currentCraft, "SENSOR_UNAVAILABLE", 100.0))
            end
            state.currentState, state.faultCode = "MAINTENANCE", "SENSOR_UNAVAILABLE"
            state.currentCraft, state.currentAirframe = nil, nil
            table.insert(out, streamer:build_facility_update(next_seq(), "MAINTENANCE", nil, state.faultCode))
            return out
        elseif healthy and state.currentState == "MAINTENANCE" then
            state.currentState, state.faultCode = "IDLE", nil
            return { streamer:build_facility_update(next_seq(), "FREE", nil, nil) }
        end
        return {}
    end

    function fsm:handle_backbone_message(msg, nowSec)
        if type(msg) ~= "table" then return {} end
        local t = nowSec or (os.clock and os.clock() or 0)
        local payload = msg.payload or {}
        if payload.facilityId ~= config.facilityId then return {} end

        if msg.type == "MSG_ATC_SLOT_ASSIGN" then
            if not is_airframe_compatible(config, payload.airframeType) then
                return { streamer:build_slot_ack(next_seq(), payload.aircraftId, "REJECTED", "INCOMPATIBLE_AIRFRAME") }
            end
            if state.currentState == "IDLE" then
                state.currentCraft = payload.aircraftId
                state.currentAirframe = payload.airframeType
                state.slotExpiresAt = t + (tonumber(payload.slotDurationSec) or 120)
                state.unstableStartSec = nil
                state.currentState = (config.mobility == "DYNAMIC") and "APPROACH_DYNAMIC" or "APPROACH_STATIC"
                return { streamer:build_slot_ack(next_seq(), state.currentCraft, "ACCEPTED", nil) }
            end
            local reason = (state.currentState == "MAINTENANCE") and "MAINTENANCE" or "OCCUPIED"
            return { streamer:build_slot_ack(next_seq(), payload.aircraftId, "REJECTED", reason) }
        elseif msg.type == "MSG_ATC_FACILITY_UPDATE" and payload.status == "FREE" then
            fsm:force_free()
        end
        return {}
    end

    function fsm:handle_tactical_message(msg, _nowSec)
        if type(msg) ~= "table" then return {} end
        local payload = msg.payload or {}
        if msg.type == "MSG_RUNWAY_TOUCHDOWN" and (payload.facilityId == config.facilityId or msg.domainId == state.currentCraft) then
            if state.currentState == "APPROACH_STATIC" or state.currentState == "APPROACH_DYNAMIC" then
                state.currentState = "ROLLOUT"
                state.unstableStartSec = nil
                return { streamer:build_facility_update(next_seq(), "ROLLOUT", state.currentCraft, nil) }
            end
        elseif msg.type == "MSG_RUNWAY_VACATED" and (payload.facilityId == config.facilityId or msg.domainId == state.currentCraft) then
            if payload.runwayCleared ~= false then
                return { fsm:force_free() }
            end
        elseif msg.type == "MSG_ABORT_APPROACH" and (payload.facilityId == config.facilityId or payload.aircraftId == state.currentCraft) then
            state.currentState = "WAVE_OFF"
            return { streamer:build_facility_update(next_seq(), "WAVE_OFF", state.currentCraft, "WAVE_OFF") }
        end
        return {}
    end

    function fsm:tick(_dt, nowSec, deckStatus, sensorHealthy)
        local t = nowSec or (os.clock and os.clock() or 0)
        local out = {}
        if sensorHealthy ~= nil and sensorHealthy ~= isSensorHealthy then
            for _, p in ipairs(fsm:set_sensor_healthy(sensorHealthy)) do table.insert(out, p) end
        end
        if state.currentState == "APPROACH_DYNAMIC" and deckStatus == "DANGEROUS" then
            if not state.unstableStartSec then
                state.unstableStartSec = t
            elseif (t - state.unstableStartSec) >= UNSTABLE_ABORT_THRESHOLD_SEC then
                state.currentState = "WAVE_OFF"
                table.insert(out, streamer:build_abort_approach(next_seq(), state.currentCraft, "DECK_UNSTABLE", 100.0))
                table.insert(out, streamer:build_facility_update(next_seq(), "FREE", nil, nil))
                state.unstableStartSec = nil
                return out
            end
        else
            state.unstableStartSec = nil
        end
        if (state.currentState == "APPROACH_DYNAMIC" or state.currentState == "APPROACH_STATIC") and t > state.slotExpiresAt then
            table.insert(out, streamer:build_abort_approach(next_seq(), state.currentCraft, "TIMEOUT", 100.0))
            table.insert(out, fsm:force_free())
        end
        return out
    end

    function fsm:force_free()
        state.currentState = isSensorHealthy and "IDLE" or "MAINTENANCE"
        state.currentCraft, state.currentAirframe, state.unstableStartSec, state.slotExpiresAt = nil, nil, nil, 0.0
        return streamer:build_facility_update(next_seq(), "FREE", nil, nil)
    end

    return fsm
end

return runway_fsm
