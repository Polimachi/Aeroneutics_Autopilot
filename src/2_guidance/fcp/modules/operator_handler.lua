-- src/modules/operator_handler.lua
local operator_handler = {}

local VALID_HEADING_MODES = {
    AUTO = true,
    FIXED = true,
    POI = true,
    FACE_PATH = true,
    TARGET_LOCK = true,
    ORBIT_POINT = true,
}

function operator_handler.init(config)
    return {
        authority = "PILOT_PRIMARY",
        lastPilotOverrideMs = 0,
        lastFlightMode = nil,
        alertQueue = {},
        latestAlertBanner = "SYSTEM_READY",
    }
end

local function finite_num(v)
    local n = tonumber(v)
    if n and n == n and n ~= math.huge and n ~= -math.huge then
        return n
    end
    return nil
end

function operator_handler.normalize_params(raw_params, flight_mode)
    local p = (type(raw_params) == "table") and raw_params or {}
    local hmode = p.headingMode
    if not VALID_HEADING_MODES[hmode] then
        hmode = (flight_mode == "POI_HOLD") and "POI" or "AUTO"
    end

    local fixed_hdg = nil
    if p.fixedHeading ~= nil then
        local fh = finite_num(p.fixedHeading)
        if fh ~= nil then
            fixed_hdg = ((fh % 360.0) + 360.0) % 360.0
        end
    end

    local wp = nil
    if type(p.targetWaypoint) == "table" and p.targetWaypoint.x ~= nil and p.targetWaypoint.z ~= nil then
        local wx = finite_num(p.targetWaypoint.x)
        local wz = finite_num(p.targetWaypoint.z)
        if wx and wz then
            wp = { x = wx, z = wz }
        end
    end

    local poi = nil
    if type(p.poiTarget) == "table" and p.poiTarget.x ~= nil and p.poiTarget.z ~= nil then
        local px = finite_num(p.poiTarget.x)
        local py = finite_num(p.poiTarget.y) or 64.0
        local pz = finite_num(p.poiTarget.z)
        if px and pz then
            poi = { x = px, y = py, z = pz }
        end
    end

    return {
        targetWaypoint = wp,
        targetAlt = finite_num(p.targetAlt),
        targetSpeed = finite_num(p.targetSpeed),
        designatedFacilityId = p.designatedFacilityId,
        loiterRadius = math.max(5.0, finite_num(p.loiterRadius) or 30.0),
        loiterDirection = (p.loiterDirection == "CCW") and "CCW" or "CW",
        headingMode = hmode,
        fixedHeading = fixed_hdg,
        poiTarget = poi,
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

        local mode = payload.flightMode or payload.command
        local active_modes = {
            CRUISE = true, LOITER = true, POI_HOLD = true,
            APPROACH_LAND = true, LANDING = true,
        }
        local bumpless = (state.lastFlightMode ~= nil and mode ~= nil and state.lastFlightMode ~= mode and active_modes[mode] == true)
        if mode ~= nil and active_modes[mode] then
            state.lastFlightMode = mode
        end
        local norm_params = operator_handler.normalize_params(payload.params, mode)
        return {
            accepted = true,
            command = payload.command or mode,
            flightMode = mode,
            params = norm_params,
            bumplessTransition = bumpless,
        }
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
