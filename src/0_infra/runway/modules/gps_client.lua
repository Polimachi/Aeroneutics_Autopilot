-- src/0_infra/runway/modules/gps_client.lua
-- GPS client and 20Hz DR position updater computing runway threshold & end points

local gps_client = {}

local WIRE_VERSION = "1.9.5"
local GPS_TIMEOUT_SEC = 2.0
local VALID_RESPONSE_STATUS = {
    FIX_OK = true, FIX_DEGRADED = true, FAIL_INSUFFICIENT = true, FAIL_GEOMETRY = true,
}

local function is_finite_number(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

function gps_client.create(config, offsetTransform)
    if not config then error("config table required", 2) end
    if not offsetTransform then error("offset_transform module required", 2) end
    local sectorId = tonumber(config.sectorId) or 1
    local replyChannel = (config.channels and tonumber(config.channels.sectorGpsReplyChannel))
        or tonumber(config.sectorGpsReplyChannel) or (50001 + sectorId * 200 + 5)

    local state = {
        config = config,
        facilityId = config.facilityId or "RWY",
        mobility = config.mobility or "STATIC",
        replyChannel = replyChannel,
        computerId = math.max(0, math.floor(tonumber(config.computerId or (os and os.getComputerID and os.getComputerID()) or 0) or 0)),
        seq = 0,
        compPos = {
            x = config.position and tonumber(config.position.x) or 0.0,
            y = config.position and tonumber(config.position.y) or 64.0,
            z = config.position and tonumber(config.position.z) or 0.0,
        },
        touchdownPoint = { x = 0.0, y = 64.0, z = 0.0 },
        endPoint = { x = 200.0, y = 64.0, z = 0.0 },
        yaw = config.approachHeading or 0.0,
        lastGpsTime = 0.0,
        isDegraded = false,
        pendingSeq = nil,
        hasValidFix = false,
    }
    local client = {}

    local function recalculate_points()
        local td, ep = offsetTransform.calculate_runway_points(
            state.compPos,
            { pitch = 0.0, roll = 0.0, yaw = state.yaw },
            state.config.mountingYawOffset or 0.0,
            state.config.touchdownOffset,
            state.config.endOffset
        )
        state.touchdownPoint, state.endPoint = td, ep
    end
    recalculate_points()

    function client:build_request_packet(altitudeY, nowMs)
        state.seq = state.seq + 1
        state.pendingSeq = state.seq
        return {
            ver = WIRE_VERSION,
            domainId = state.facilityId,
            seq = state.seq,
            type = "MSG_GPS_REQUEST",
            time = nowMs or (os.epoch and os.epoch("utc") or 0),
            payload = {
                replyChannel = state.replyChannel,
                altitudeY = is_finite_number(altitudeY) and altitudeY or state.compPos.y,
                clientType = "FACILITY",
                clientSeq = state.seq,
            },
        }
    end

    function client:handle_response_packet(msg, nowSec)
        if type(msg) ~= "table" or msg.ver ~= WIRE_VERSION or msg.type ~= "MSG_GPS_RESPONSE" then return false end
        local p = msg.payload
        if type(p) ~= "table" or p.targetClient ~= state.facilityId or not VALID_RESPONSE_STATUS[p.status] then return false end
        local cSeq = tonumber(p.clientSeq)
        if state.pendingSeq == nil or cSeq ~= state.pendingSeq then return false end
        state.pendingSeq = nil
        if p.status ~= "FIX_OK" and p.status ~= "FIX_DEGRADED" then return false end
        if type(p.position) ~= "table" or not is_finite_number(p.position.x) or not is_finite_number(p.position.z) then return false end
        state.compPos.x, state.compPos.z = p.position.x, p.position.z
        state.hasValidFix = true
        state.lastGpsTime = is_finite_number(nowSec) and nowSec or (os.clock and os.clock() or 0)
        state.isDegraded = false
        recalculate_points()
        return true
    end

    function client:update_dead_reckoning(dt, kinematics)
        local delta = dt or 0.05
        if kinematics and state.mobility == "DYNAMIC" then
            local vel = kinematics.velocity or {}
            local acc = kinematics.acceleration or {}
            state.compPos.x = state.compPos.x + (vel.vx or 0) * delta + 0.5 * (acc.ax or 0) * delta * delta
            state.compPos.y = state.compPos.y + (vel.vy or 0) * delta + 0.5 * (acc.ay or 0) * delta * delta
            state.compPos.z = state.compPos.z + (vel.vz or 0) * delta + 0.5 * (acc.az or 0) * delta * delta
            if kinematics.attitude and kinematics.attitude.yaw then
                state.yaw = kinematics.attitude.yaw
            end
        end
        recalculate_points()
    end

    function client:check_gps_health(nowSec)
        if state.mobility == "STATIC" and state.hasValidFix then
            state.isDegraded = false
            return true
        end
        local t = nowSec or (os.clock and os.clock() or 0)
        state.isDegraded = (t - state.lastGpsTime) > GPS_TIMEOUT_SEC
        return not state.isDegraded
    end

    function client:should_query_gps(fsmState, tickCount)
        local tick = tonumber(tickCount) or 0
        if tick <= 0 then return false end
        if state.mobility == "STATIC" then
            return (not state.hasValidFix) and ((tick % 20) == (state.computerId % 20))
        end
        local interval = (fsmState == "RESERVED" or fsmState == "APPROACH_DYNAMIC") and 4 or 20
        return (tick % interval) == (state.computerId % interval)
    end

    function client:get_current_comp_pos() return { x = state.compPos.x, y = state.compPos.y, z = state.compPos.z } end
    function client:get_current_touchdown_pos() return { x = state.touchdownPoint.x, y = state.touchdownPoint.y, z = state.touchdownPoint.z } end
    function client:get_current_end_pos() return { x = state.endPoint.x, y = state.endPoint.y, z = state.endPoint.z } end
    return client
end

return gps_client
