-- src/0_infra/landing_pad/modules/gps_client.lua
-- GPS client and 20Hz dead-reckoning coordinate integrator for Landing Pad

local gps_client = {}

local WIRE_VERSION = "1.9.5"
local GPS_TIMEOUT_SEC = 2.0
local VALID_RESPONSE_STATUS = {
    FIX_OK = true,
    FIX_DEGRADED = true,
    FAIL_INSUFFICIENT = true,
    FAIL_GEOMETRY = true,
}

local function non_empty_str(v)
    if type(v) == "string" and v ~= "" then
        return v
    end
    return nil
end

local function resolve_mobility(config)
    local raw = non_empty_str(config.mobility) or non_empty_str(config.mode) or "STATIC"
    local upper = string.upper(raw)
    if upper ~= "STATIC" and upper ~= "DYNAMIC" then
        error("INVALID_MOBILITY: " .. tostring(raw), 2)
    end
    return upper
end

function gps_client.create(config, offsetTransform)
    if not config then error("config table required", 2) end
    if not offsetTransform then error("offset_transform module required", 2) end

    local facilityId = non_empty_str(config.facilityId) or non_empty_str(config.padId) or "PAD"
    local mobility = resolve_mobility(config)
    local sectorId = tonumber(config.sectorId or config.sectorIndex) or 1
    local replyChannel = tonumber(config.sectorGpsReplyChannel)
        or (config.channels and tonumber(config.channels.sectorGpsReplyChannel))
        or (50001 + sectorId * 200 + 5)

    local state = {
        config = config,
        facilityId = facilityId,
        mobility = mobility,
        replyChannel = replyChannel,
        seq = 0,
        compPos = {
            x = config.position and tonumber(config.position.x) or 0.0,
            y = config.position and tonumber(config.position.y) or 64.0,
            z = config.position and tonumber(config.position.z) or 0.0
        },
        padPos = {
            x = config.position and tonumber(config.position.x) or 0.0,
            y = config.position and tonumber(config.position.y) or 64.0,
            z = config.position and tonumber(config.position.z) or 0.0
        },
        yaw = 0.0,
        lastGpsTime = 0.0,
        isDegraded = false,
        pendingSeq = nil,
        hasValidFix = false,
        lastStatus = nil,
        lastAccuracy = nil,
        lastHdop = nil
    }

    local client = {}

    local function recalculate_pad_pos()
        local padCoords = offsetTransform.calculate_pad_coordinates(
            state.compPos,
            state.yaw,
            state.config.mountingYawOffset or 0.0,
            state.config.bodyOffset
        )
        state.padPos.x = padCoords.x
        state.padPos.y = padCoords.y
        state.padPos.z = padCoords.z
    end

    -- Initial position calculation
    recalculate_pad_pos()

    function client:build_request_packet(altitudeY, nowMs)
        state.seq = state.seq + 1
        state.pendingSeq = state.seq

        local timeMs = nowMs or (os.epoch and os.epoch("utc") or 0)

        return {
            ver = WIRE_VERSION,
            domainId = state.facilityId,
            seq = state.seq,
            type = "MSG_GPS_REQUEST",
            time = timeMs,
            payload = {
                replyChannel = state.replyChannel,
                altitudeY = altitudeY or state.compPos.y,
                clientType = "FACILITY",
                clientSeq = state.seq
            }
        }
    end

    function client:handle_response_packet(msg, nowSec)
        if type(msg) ~= "table" then return false end
        if msg.ver ~= WIRE_VERSION or msg.type ~= "MSG_GPS_RESPONSE" then return false end
        local payload = msg.payload
        if type(payload) ~= "table" then return false end
        if payload.targetClient ~= state.facilityId then return false end
        if not VALID_RESPONSE_STATUS[payload.status] then return false end
        local cSeq = tonumber(payload.clientSeq)
        if state.pendingSeq == nil or not cSeq or cSeq ~= state.pendingSeq then return false end
        state.pendingSeq = nil
        state.lastStatus = payload.status

        if payload.status ~= "FIX_OK" and payload.status ~= "FIX_DEGRADED" then
            return false
        end
        if type(payload.position) ~= "table" or type(payload.position.x) ~= "number" or type(payload.position.z) ~= "number" then
            return false
        end

        state.compPos.x = payload.position.x
        state.compPos.z = payload.position.z
        state.lastAccuracy = tonumber(payload.accuracy)
        state.lastHdop = tonumber(payload.hdop)
        state.hasValidFix = true
        state.lastGpsTime = nowSec or (os.clock and os.clock() or 0)
        state.isDegraded = false
        recalculate_pad_pos()
        return true
    end

    function client:update_dead_reckoning(dt, kinematics)
        local delta = dt or 0.05
        if kinematics and state.mobility == "DYNAMIC" then
            local vel = kinematics.velocity or {}
            local acc = kinematics.acceleration or {}

            local vx = vel.vx or 0.0
            local vy = vel.vy or 0.0
            local vz = vel.vz or 0.0

            local ax = acc.ax or 0.0
            local ay = acc.ay or 0.0
            local az = acc.az or 0.0

            state.compPos.x = state.compPos.x + vx * delta + 0.5 * ax * delta * delta
            state.compPos.y = state.compPos.y + vy * delta + 0.5 * ay * delta * delta
            state.compPos.z = state.compPos.z + vz * delta + 0.5 * az * delta * delta

            if kinematics.attitude and kinematics.attitude.yaw then
                state.yaw = kinematics.attitude.yaw
            end
        end

        recalculate_pad_pos()
    end

    function client:check_gps_health(nowSec)
        if state.mobility == "STATIC" and state.hasValidFix then
            state.isDegraded = false
            return true
        end
        local t = nowSec or (os.clock and os.clock() or 0)
        if (t - state.lastGpsTime) > GPS_TIMEOUT_SEC then
            state.isDegraded = true
            return false
        end
        state.isDegraded = false
        return true
    end

    function client:has_valid_fix()
        return state.hasValidFix == true
    end

    function client:should_query_gps(fsmState, tickCount)
        local tick = tonumber(tickCount) or 0
        if tick <= 0 then return false end
        if state.mobility == "STATIC" then
            return (not state.hasValidFix) and (tick % 20 == 0)
        end
        local interval = (fsmState == "RESERVED" or fsmState == "APPROACH_DYNAMIC") and 4 or 20
        return (tick % interval) == 0
    end

    function client:is_degraded()
        return state.isDegraded
    end

    function client:get_current_comp_pos()
        return { x = state.compPos.x, y = state.compPos.y, z = state.compPos.z }
    end

    function client:get_current_pad_pos()
        return { x = state.padPos.x, y = state.padPos.y, z = state.padPos.z }
    end

    function client:set_comp_pos(x, y, z)
        state.compPos.x = x or state.compPos.x
        state.compPos.y = y or state.compPos.y
        state.compPos.z = z or state.compPos.z
        recalculate_pad_pos()
    end

    function client:set_last_gps_time(t)
        state.lastGpsTime = t or 0.0
    end

    return client
end

return gps_client
