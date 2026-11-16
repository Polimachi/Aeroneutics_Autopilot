-- src/0_infra/gcs/modules/live_bridge_client.lua
-- Optional localhost WebSocket client bridging GCS <-> Host WebUI (TASK-404)
-- UAFS Ecosystem GCS v1.2.0

local live_bridge_client = {}

function live_bridge_client.init(config, http_api)
    local lb = (config and config.liveBridge) or {}
    return {
        enabled = (lb.enabled == true),
        url = lb.url or "ws://127.0.0.1:8765",
        http_api = http_api,
        ws = nil,
        connected = false,
    }
end

function live_bridge_client.connect(state)
    if not state or not state.enabled then
        return false, "DISABLED"
    end
    local h = state.http_api
    if type(h) ~= "table" or type(h.websocket) ~= "function" then
        return false, "HTTP_WS_UNAVAILABLE"
    end
    local ok, handle_or_err = pcall(h.websocket, state.url)
    if not ok or type(handle_or_err) ~= "table" then
        state.ws = nil
        state.connected = false
        return false, tostring(handle_or_err or "CONNECT_FAILED")
    end
    state.ws = handle_or_err
    state.connected = true
    return true, nil
end

function live_bridge_client.close(state)
    if not state then return end
    if state.ws and type(state.ws.close) == "function" then
        pcall(state.ws.close, state.ws)
    end
    state.ws = nil
    state.connected = false
end

local function send_json(state, tbl)
    if not state or not state.connected or not state.ws or type(state.ws.send) ~= "function" then
        return false
    end
    local raw = textutils.serializeJSON(tbl)
    local ok = pcall(function() state.ws:send(raw) end)
    if not ok then
        ok = pcall(state.ws.send, raw)
    end
    if not ok then
        state.connected = false
        return false
    end
    return true
end

function live_bridge_client.send_world_preset(state, beacon_payload)
    if type(beacon_payload) ~= "table" then return false end
    return send_json(state, {
        type = "WORLD_PRESET_SYNC",
        sectorId = beacon_payload.sectorId,
        sectorName = beacon_payload.sectorName,
        surfaceWind = beacon_payload.surfaceWind,
        facilities = beacon_payload.facilities or {},
    })
end

function live_bridge_client.send_fleet_telemetry(state, fleet_state)
    if not state or not state.connected or type(fleet_state) ~= "table" then return false end
    local crafts = {}
    for _, dom_id in ipairs(fleet_state.craft_order or {}) do
        local c = fleet_state.crafts and fleet_state.crafts[dom_id]
        if c then
            local t = c.telemetry or {}
            local nav = t.navigation or t.nav or {}
            local dyn = t.dynamics or {}
            local att = t.attitude or {}
            local pos = nav.currentPos or t.position or { x = 0, y = dyn.altitudeY or 0, z = 0 }
            table.insert(crafts, {
                domainId = c.domainId,
                baseChannel = c.baseChannel,
                isStale = (c.isStale == true),
                fsmState = t.fsmState or "UNKNOWN",
                fuel = t.fuel or 0.0,
                groundSpeed = dyn.groundSpeed or 0.0,
                attitude = {
                    pitch = att.pitch or 0.0,
                    roll = att.roll or 0.0,
                    yaw = att.yaw or att.heading or 0.0,
                },
                position = {
                    x = pos.x or 0.0,
                    y = pos.y or dyn.altitudeY or 0.0,
                    z = pos.z or 0.0,
                },
            })
        end
    end
    return send_json(state, { type = "FLEET_TELEMETRY_SYNC", crafts = crafts })
end

function live_bridge_client.send_mission_ack(state, req_id, target_craft, ack_payload)
    if type(ack_payload) ~= "table" then return false end
    return send_json(state, {
        type = "MISSION_PUSH_ACK",
        requestId = req_id,
        targetCraft = target_craft,
        action = ack_payload.action,
        status = ack_payload.status,
        missionId = ack_payload.missionId,
        missionState = ack_payload.missionState,
        reason = ack_payload.reason,
    })
end

function live_bridge_client.parse_incoming(raw_json)
    if type(raw_json) ~= "string" or raw_json == "" then
        return nil, "EMPTY_MESSAGE"
    end
    local ok, decoded = pcall(textutils.unserializeJSON, raw_json)
    if not ok or type(decoded) ~= "table" or type(decoded.type) ~= "string" then
        return nil, "INVALID_JSON"
    end
    return decoded, nil
end

return live_bridge_client
