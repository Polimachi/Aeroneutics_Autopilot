-- src/0_infra/landing_pad/modules/pad_fsm.lua
-- Finite State Machine and local backbone protocol mediator for Landing Pad

local pad_fsm = {}

local UNSTABLE_ABORT_THRESHOLD_SEC = 3.0
local GO_AROUND_TIMEOUT_SEC = 10.0

local DEFAULT_COMPATIBLE_AIRFRAMES = {
    ADVANCED_VTOL = true,
    VECTORED_VTOL = true,
    WINGED_VTOL   = true,
    QUADROTOR     = true,
    HEXAROTOR     = true,
}

function pad_fsm.create(config, streamer, initialSensorHealthy)
    if not config then error("config table required", 2) end
    if not streamer then error("streamer required", 2) end

    local isSensorHealthy = (initialSensorHealthy ~= false)
    local initialState = "IDLE"
    if config.mode == "DYNAMIC" and not isSensorHealthy then
        initialState = "MAINTENANCE"
    end

    local state = {
        currentState = initialState,
        currentCraft = nil,
        currentAirframe = nil,
        slotExpiresAt = 0.0,
        unstableStartSec = nil,
        goAroundStartSec = nil,
        seq = 10000,
        faultCode = (initialState == "MAINTENANCE") and "SENSOR_UNAVAILABLE" or nil
    }

    local fsm = {}

    local function next_seq()
        state.seq = state.seq + 1
        return state.seq
    end

    function fsm:get_state()
        return state.currentState
    end

    function fsm:get_current_craft()
        return state.currentCraft
    end

    function fsm:get_current_airframe()
        return state.currentAirframe
    end

    function fsm:get_fault_code()
        return state.faultCode
    end

    function fsm:set_sensor_healthy(healthy)
        isSensorHealthy = healthy
        if not healthy and config.mode == "DYNAMIC" then
            if state.currentState == "APPROACH_DYNAMIC" or state.currentState == "RESERVED" then
                -- Abort active approach
                local out = {}
                if state.currentCraft then
                    table.insert(out, streamer:build_abort_approach(next_seq(), state.currentCraft, "SENSOR_UNAVAILABLE", 100.0))
                end
                state.currentState = "MAINTENANCE"
                state.faultCode = "SENSOR_UNAVAILABLE"
                state.currentCraft = nil
                state.currentAirframe = nil
                table.insert(out, streamer:build_facility_update(next_seq(), "MAINTENANCE", nil, state.faultCode))
                return out
            elseif state.currentState == "IDLE" then
                state.currentState = "MAINTENANCE"
                state.faultCode = "SENSOR_UNAVAILABLE"
                return { streamer:build_facility_update(next_seq(), "MAINTENANCE", nil, state.faultCode) }
            end
        elseif healthy and state.currentState == "MAINTENANCE" then
            state.currentState = "IDLE"
            state.faultCode = nil
            return { streamer:build_facility_update(next_seq(), "FREE", nil, nil) }
        end
        return {}
    end

    function fsm:handle_backbone_message(msg, nowSec)
        if type(msg) ~= "table" then return {} end
        local t = nowSec or (os.clock and os.clock() or 0)
        local out = {}

        if msg.type == "MSG_ATC_SLOT_ASSIGN" then
            local payload = msg.payload or {}
            if payload.facilityId ~= config.padId then
                return {}
            end

            -- Validate airframe compatibility
            local af = payload.airframeType
            local isAirframeCompatible = true
            if af then
                if config.supportedAirframeTypes then
                    local found = false
                    for _, supported in ipairs(config.supportedAirframeTypes) do
                        if supported == af then found = true; break end
                    end
                    isAirframeCompatible = found
                elseif DEFAULT_COMPATIBLE_AIRFRAMES[af] == nil then
                    isAirframeCompatible = false
                end
            end

            if not isAirframeCompatible then
                local ack = streamer:build_slot_ack(next_seq(), payload.aircraftId, "REJECTED", "INCOMPATIBLE_AIRFRAME")
                table.insert(out, ack)
                return out
            end

            if state.currentState == "IDLE" then
                state.currentCraft = payload.aircraftId
                state.currentAirframe = payload.airframeType
                local duration = tonumber(payload.slotDurationSec) or 120
                state.slotExpiresAt = t + duration
                state.unstableStartSec = nil

                if config.mode == "DYNAMIC" then
                    state.currentState = "APPROACH_DYNAMIC"
                else
                    state.currentState = "APPROACH_STATIC"
                end

                local ack = streamer:build_slot_ack(next_seq(), state.currentCraft, "ACCEPTED", nil)
                table.insert(out, ack)
            else
                local reason = "OCCUPIED"
                if state.currentState == "MAINTENANCE" then
                    reason = "MAINTENANCE"
                end
                local ack = streamer:build_slot_ack(next_seq(), payload.aircraftId, "REJECTED", reason)
                table.insert(out, ack)
            end
        elseif msg.type == "MSG_ATC_FACILITY_UPDATE" then
            local payload = msg.payload or {}
            if payload.facilityId == config.padId then
                if payload.status == "FREE" then
                    state.currentState = isSensorHealthy and "IDLE" or "MAINTENANCE"
                    state.currentCraft = nil
                    state.currentAirframe = nil
                    state.unstableStartSec = nil
                    state.goAroundStartSec = nil
                end
            end
        end

        return out
    end

    function fsm:handle_tactical_message(msg, nowSec)
        if type(msg) ~= "table" then return {} end
        local t = nowSec or (os.clock and os.clock() or 0)
        local out = {}

        if msg.type == "MSG_TOUCHDOWN_COMPLETE" then
            local payload = msg.payload or {}
            if payload.facilityId == config.padId or msg.domainId == state.currentCraft then
                if state.currentState == "APPROACH_STATIC" or state.currentState == "APPROACH_DYNAMIC" or state.currentState == "RESERVED" then
                    state.currentState = "OCCUPIED"
                    state.unstableStartSec = nil
                    local upd = streamer:build_facility_update(next_seq(), "OCCUPIED", state.currentCraft, nil)
                    table.insert(out, upd)
                end
            end
        elseif msg.type == "MSG_ABORT_APPROACH" then
            local payload = msg.payload or {}
            if payload.facilityId == config.padId or payload.aircraftId == state.currentCraft then
                state.currentState = "GO_AROUND"
                state.goAroundStartSec = t
                local upd = streamer:build_facility_update(next_seq(), "FREE", nil, nil)
                table.insert(out, upd)
            end
        end

        return out
    end

    function fsm:tick(dt, nowSec, deckStatus, sensorHealthy)
        local t = nowSec or (os.clock and os.clock() or 0)
        local out = {}

        if sensorHealthy ~= nil and sensorHealthy ~= isSensorHealthy then
            local sensorPkts = fsm:set_sensor_healthy(sensorHealthy)
            for _, p in ipairs(sensorPkts) do table.insert(out, p) end
        end

        if state.currentState == "APPROACH_DYNAMIC" then
            -- 1. Check deck stability timeout (3.0s continuously dangerous)
            if deckStatus == "DANGEROUS" then
                if not state.unstableStartSec then
                    state.unstableStartSec = t
                elseif (t - state.unstableStartSec) >= UNSTABLE_ABORT_THRESHOLD_SEC then
                    state.currentState = "GO_AROUND"
                    state.goAroundStartSec = t
                    table.insert(out, streamer:build_abort_approach(next_seq(), state.currentCraft, "DECK_UNSTABLE", 100.0))
                    table.insert(out, streamer:build_facility_update(next_seq(), "FREE", nil, nil))
                    state.unstableStartSec = nil
                    return out
                end
            else
                state.unstableStartSec = nil
            end

            -- 2. Check slot timeout
            if t > state.slotExpiresAt then
                state.currentState = "IDLE"
                table.insert(out, streamer:build_abort_approach(next_seq(), state.currentCraft, "TIMEOUT", 100.0))
                state.currentCraft = nil
                state.currentAirframe = nil
                table.insert(out, streamer:build_facility_update(next_seq(), "FREE", nil, nil))
                return out
            end
        elseif state.currentState == "APPROACH_STATIC" or state.currentState == "RESERVED" then
            if t > state.slotExpiresAt then
                state.currentState = "IDLE"
                table.insert(out, streamer:build_abort_approach(next_seq(), state.currentCraft, "TIMEOUT", 100.0))
                state.currentCraft = nil
                state.currentAirframe = nil
                table.insert(out, streamer:build_facility_update(next_seq(), "FREE", nil, nil))
                return out
            end
        elseif state.currentState == "GO_AROUND" then
            if state.goAroundStartSec and (t - state.goAroundStartSec) >= GO_AROUND_TIMEOUT_SEC then
                state.currentState = isSensorHealthy and "IDLE" or "MAINTENANCE"
                state.currentCraft = nil
                state.currentAirframe = nil
                state.goAroundStartSec = nil
            end
        end

        return out
    end

    function fsm:force_free()
        state.currentState = isSensorHealthy and "IDLE" or "MAINTENANCE"
        state.currentCraft = nil
        state.currentAirframe = nil
        state.unstableStartSec = nil
        state.goAroundStartSec = nil
        return streamer:build_facility_update(next_seq(), "FREE", nil, nil)
    end

    return fsm
end

return pad_fsm
