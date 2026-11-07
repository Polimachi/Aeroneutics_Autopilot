-- src/modules/operator_handler.lua
local operator_handler = {}

function operator_handler.init(config)
    return {
        authority = "PILOT_PRIMARY",
        lastPilotOverrideMs = 0,
        alertQueue = {},
        latestAlertBanner = "SYSTEM_READY",
    }
end

function operator_handler.check_pilot_override(state, pilot_input, now_ms)
    if not state or not pilot_input then return false end
    local deadband = 0.05
    local s = math.abs(pilot_input.surge or 0.0)
    local w = math.abs(pilot_input.sway or 0.0)
    local h = math.abs(pilot_input.heave or 0.0)
    local y = math.abs(pilot_input.yaw or 0.0)

    if s > deadband or w > deadband or h > deadband or y > deadband or pilot_input.modeBtn then
        state.authority = "PILOT_PRIMARY"
        state.lastPilotOverrideMs = now_ms or 0
        return true
    end
    return false
end

function operator_handler.process_c2(state, packet, now_ms)
    if not state or not packet then return { accepted = false, reason = "NIL_INPUT" } end
    local t = packet.type
    local payload = packet.payload or {}

    if t == "MSG_EMERGENCY_CMD" then
        return { accepted = true, action = payload.action or "HOVER_HOLD", sender = packet.senderId }
    end

    if t == "MSG_OPERATOR_CMD" then
        if payload.authority == "PILOT_PRIMARY" then
            state.authority = "PILOT_PRIMARY"
        elseif payload.authority == "GCS_OVERRIDE" or payload.forceOverride then
            state.authority = "GCS_OVERRIDE"
        elseif state.authority == "PILOT_PRIMARY" and not payload.forceOverride then
            return { accepted = false, reason = "PILOT_OVERRIDE_ACTIVE" }
        end

        local em_action = payload.emergencyAction
        if em_action and em_action ~= "NONE" then
            return { accepted = true, action = em_action, emergencyAction = em_action }
        end

        return { accepted = true, command = payload.command, flightMode = payload.flightMode, params = payload.params }
    end

    return { accepted = false, reason = "UNKNOWN_CMD_TYPE" }
end

function operator_handler.build_emergency_override(state, action, reason)
    local act = action
    if act ~= "CUTOFF" and act ~= "CUSHION_STOP" then
        act = "CUTOFF"
    end
    return {
        type = "MSG_EMERGENCY_OVERRIDE",
        payload = {
            action = act,
            reason = reason or "KILLSWITCH",
            source = state and state.authority or "FCP",
            timestamp = os.epoch and os.epoch("utc") or 0,
        },
    }
end

function operator_handler.send_mfd_alert(state, code, severity, text, now_ms)
    local alert = {
        code = code or "INFO",
        severity = severity or "INFO",
        message = text or "",
        timestamp = now_ms or 0,
    }
    if state then
        table.insert(state.alertQueue, alert)
        state.latestAlertBanner = text or state.latestAlertBanner
    end
    return alert
end

return operator_handler
