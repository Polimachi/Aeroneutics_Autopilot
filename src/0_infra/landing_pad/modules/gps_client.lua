-- src/0_infra/landing_pad/modules/gps_client.lua
-- GPS client and 20Hz dead-reckoning coordinate integrator for Landing Pad

local gps_client = {}

local WIRE_VERSION = "1.9.5"
local GPS_TIMEOUT_SEC = 2.0

function gps_client.create(config, offsetTransform)
    if not config then error("config table required", 2) end
    if not offsetTransform then error("offset_transform module required", 2) end

    local state = {
        config = config,
        seq = 0,
        compPos = {
            x = config.position and config.position.x or 0.0,
            y = config.position and config.position.y or 64.0,
            z = config.position and config.position.z or 0.0
        },
        padPos = {
            x = config.position and config.position.x or 0.0,
            y = config.position and config.position.y or 64.0,
            z = config.position and config.position.z or 0.0
        },
        yaw = 0.0,
        lastGpsTime = 0.0,
        isDegraded = false,
        pendingSeq = nil
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
        local replyChannel = state.config.channels and state.config.channels.sectorGpsReplyChannel or 60001

        return {
            ver = WIRE_VERSION,
            domainId = state.config.padId or "PAD",
            seq = state.seq,
            type = "MSG_GPS_REQUEST",
            time = timeMs,
            payload = {
                replyChannel = replyChannel,
                altitudeY = altitudeY or state.compPos.y,
                clientType = "LANDING_PAD",
                clientSeq = state.seq
            }
        }
    end

    function client:handle_response_packet(msg, nowSec)
        if type(msg) ~= "table" then return false end
        if msg.type ~= "MSG_GPS_RESPONSE" then return false end
        local payload = msg.payload
        if type(payload) ~= "table" then return false end

        if payload.targetClient and payload.targetClient ~= state.config.padId then
            return false
        end

        if payload.status == "OK" or payload.status == "SUCCESS" then
            if payload.position then
                state.compPos.x = tonumber(payload.position.x) or state.compPos.x
                state.compPos.z = tonumber(payload.position.z) or state.compPos.z
            end
            local t = nowSec or (os.clock and os.clock() or 0)
            state.lastGpsTime = t
            state.isDegraded = false
            recalculate_pad_pos()
            return true
        end

        return false
    end

    function client:update_dead_reckoning(dt, kinematics)
        local delta = dt or 0.05
        if kinematics and state.config.mode == "DYNAMIC" then
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
        local t = nowSec or (os.clock and os.clock() or 0)
        if (t - state.lastGpsTime) > GPS_TIMEOUT_SEC then
            state.isDegraded = true
            return false
        end
        state.isDegraded = false
        return true
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
