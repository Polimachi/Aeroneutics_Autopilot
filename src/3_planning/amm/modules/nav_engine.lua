-- src/3_planning/amm/modules/nav_engine.lua
local nav_engine = {}

local function is_finite_number(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

function nav_engine.init(config)
    local cfg = config or {}
    local sys = cfg.system or {}
    local chs = cfg.channels or {}
    local nav = cfg.navigation or {}
    local safe = cfg.safety or {}
    local dId = sys.domainId or cfg.domainId or "AIRCRAFT_01"
    local bCh = chs.baseChannel or cfg.baseChannel or 10000
    local dAlpha = nav.drComplementaryAlpha or 0.35
    local degAlpha = nav.degradedAlpha or 0.10
    local rawCid = sys.computerId
    if rawCid == nil then rawCid = cfg.computerId end
    if rawCid == nil and os and os.getComputerID then rawCid = os.getComputerID() end
    local cid = math.max(0, math.floor(tonumber(rawCid) or 0))
    return {
        pos = { x = 0.0, y = 0.0, z = 0.0 },
        vel = { x = 0.0, y = 0.0, z = 0.0 },
        attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
        rates = { p = 0.0, q = 0.0, r = 0.0 },
        groundSpeed = 0.0,
        altitudeY = 0.0,
        verticalSpeed = 0.0,
        fuel = 1.0,
        coreArmed = false,
        hdop = 1.0,
        domainId = dId,
        computerId = cid,
        baseChannel = bCh,
        drComplementaryAlpha = dAlpha,
        degradedAlpha = degAlpha,
        alpha = dAlpha,
        maxAllowedHdop = nav.maxAllowedHdop or 3.0,
        kinematicGateLimitM = nav.kinematicGateLimitM or 8.0,
        kinematicLimitM = nav.kinematicGateLimitM or 8.0,
        gpsTimeoutMs = nav.gpsTimeoutMs or 5000,
        gpsRequestRateHz = nav.gpsRequestRateHz or 10,
        coreTimeoutMs = safe.fcpStatusTimeoutMs or 500,
        posEpoch = 0,
        navValid = false,
        gpsStale = false,
        lastCoreRxMs = 0,
        lastGpsFixMs = 0,
        lastGpsReqMs = 0,
        gpsPhaseAnchorMs = nil,
        gpsReqSeq = 0,
        lastGpsFixSeq = 0,
        lastGpsSeqSeen = 0,
        spikeStreak = 0,
        validStreak = 0,
    }
end

function nav_engine.should_query_gps(state, now_ms)
    local now = now_ms or 0
    local interval = math.floor(1000 / (state.gpsRequestRateHz or 10))
    if (state.lastGpsReqMs or 0) == 0 then
        local cid = state.computerId or 0
        local slots = math.max(1, math.floor(interval / 50))
        local offsetMs = (cid % slots) * 50
        if not state.gpsPhaseAnchorMs then
            state.gpsPhaseAnchorMs = now
        end
        if (now - state.gpsPhaseAnchorMs) < offsetMs then
            return false, nil
        end
        state.lastGpsReqMs = now
        state.gpsReqSeq = (state.gpsReqSeq or 0) + 1
        return true, state.gpsReqSeq
    end
    if (now - (state.lastGpsReqMs or 0)) >= interval then
        state.lastGpsReqMs = now
        state.gpsReqSeq = (state.gpsReqSeq or 0) + 1
        return true, state.gpsReqSeq
    end
    return false, nil
end

function nav_engine.build_gps_request(state, now_ms)
    local should, seq = nav_engine.should_query_gps(state, now_ms)
    if not should then
        return false, nil, nil
    end
    local now = now_ms or (os.epoch and os.epoch("utc")) or (os.time() * 1000)
    local repCh = (state.baseChannel or 10000) + 5
    local alt = (state.pos and state.pos.y) or 0.0
    local pkt = {
        ver = "1.9.5",
        domainId = state.domainId or "AIRCRAFT_01",
        seq = seq,
        type = "MSG_GPS_REQUEST",
        time = now,
        payload = {
            replyChannel = repCh,
            altitudeY = alt,
            clientType = "AIRCRAFT",
            clientSeq = seq,
        },
    }
    return true, seq, pkt
end

function nav_engine.update_timeout(state, now_ms)
    local now = now_ms or 0
    local is_stale = (now - (state.lastGpsFixMs or 0)) > (state.gpsTimeoutMs or 5000)
    state.gpsStale = is_stale
    return is_stale
end

function nav_engine.integrate_dr(state, telemetry, dt, now_ms)
    if not state or not telemetry then return end
    local step_dt = dt or 0.05
    local dyn = telemetry.dynamics or {}
    local v = dyn.velocity or telemetry.velocity or {}
    local vx = v.vx or v.x or 0.0
    local vy = v.vy or v.y or dyn.verticalSpeed or 0.0
    local vz = v.vz or v.z or 0.0
    state.vel = { x = vx, y = vy, z = vz }
    state.groundSpeed = math.sqrt(vx * vx + vz * vz)
    state.verticalSpeed = vy
    state.pos.x = state.pos.x + vx * step_dt
    local altY = dyn.altitudeY
    if not is_finite_number(altY) then altY = telemetry.altitudeY end
    if is_finite_number(altY) then
        state.pos.y = altY
        state.altitudeY = altY
    else
        state.pos.y = state.pos.y + vy * step_dt
        state.altitudeY = state.pos.y
    end
    state.pos.z = state.pos.z + vz * step_dt

    local att = telemetry.attitude or {}
    state.attitude.pitch = att.pitch or telemetry.pitch or state.attitude.pitch
    state.attitude.roll = att.roll or telemetry.roll or state.attitude.roll
    state.attitude.heading = dyn.heading or att.heading or att.yaw or telemetry.heading or state.attitude.heading
    state.fuel = telemetry.fuel or state.fuel
    state.lastCoreRxMs = now_ms or 0
    state.navValid = true
end

local function validate_gps_payload(state, fix_payload, expectedSeq)
    if not state or not fix_payload then return false end
    if fix_payload.targetClient and state.domainId and fix_payload.targetClient ~= state.domainId then
        return false
    end
    if fix_payload.status and fix_payload.status ~= "FIX_OK" and fix_payload.status ~= "FIX_DEGRADED" then
        return false
    end
    if fix_payload.hdop and state.maxAllowedHdop and fix_payload.hdop > state.maxAllowedHdop then
        return false
    end
    local cSeq = tonumber(fix_payload.clientSeq or expectedSeq)
    if cSeq ~= nil then
        local minSeq = state.lastGpsFixSeq or 0
        if not is_finite_number(cSeq) or cSeq <= minSeq or ((state.gpsReqSeq or 0) > 0 and cSeq > state.gpsReqSeq) then
            return false
        end
    end
    local pos = fix_payload.position or fix_payload
    local gx = (pos and pos.x) or fix_payload.x
    local gz = (pos and pos.z) or fix_payload.z
    if not is_finite_number(gx) or not is_finite_number(gz) then return false end
    return true, cSeq, gx, gz
end

local function check_kinematic_gate(state, gx, gz, acc, dt, now_ms)
    if (state.lastGpsFixMs or 0) == 0 then
        return true
    end
    local fallback_dt = dt or 0.05
    local delta_t = fallback_dt
    if is_finite_number(now_ms) and now_ms > state.lastGpsFixMs then
        local elapsed = (now_ms - state.lastGpsFixMs) / 1000.0
        local maxSpanSec = (state.gpsTimeoutMs or 5000) / 1000.0
        delta_t = math.max(fallback_dt, math.min(elapsed, maxSpanSec))
    end
    local max_allowed = math.max(state.kinematicGateLimitM or 8.0, (state.groundSpeed or 0.0) * delta_t * 1.5 + 3.0 * acc)
    local dx = gx - state.pos.x
    local dz = gz - state.pos.z
    local dist = math.sqrt(dx * dx + dz * dz)
    return dist <= max_allowed
end

local function apply_streak_snap(state, gx, gz, fix_payload, now_ms, cSeq)
    state.pos.x = gx
    state.pos.z = gz
    state.hdop = fix_payload.hdop or state.hdop
    state.lastGpsFixMs = now_ms or state.lastGpsFixMs
    if cSeq then state.lastGpsFixSeq = cSeq end
    state.posEpoch = (state.posEpoch or 0) + 1
    state.gpsStale = false
    state.navValid = true
    state.spikeStreak = 0
    state.validStreak = 1
end

local function apply_fix_fusion(state, gx, gz, fix_payload, now_ms, cSeq)
    local a
    if state.gpsStale or fix_payload.status == "FIX_DEGRADED" then
        a = state.degradedAlpha or 0.10
    else
        a = state.drComplementaryAlpha or 0.35
    end
    state.pos.x = (1.0 - a) * state.pos.x + a * gx
    state.pos.z = (1.0 - a) * state.pos.z + a * gz
    state.hdop = fix_payload.hdop or state.hdop
    state.lastGpsFixMs = now_ms or state.lastGpsFixMs
    if cSeq then state.lastGpsFixSeq = cSeq end
    state.posEpoch = (state.posEpoch or 0) + 1
    state.gpsStale = false
    state.navValid = true
    state.validStreak = (state.validStreak or 0) + 1
    state.spikeStreak = 0
end

function nav_engine.filter_gps(state, fix_payload, dt, now_ms, expectedSeq)
    local valid, cSeq, gx, gz = validate_gps_payload(state, fix_payload, expectedSeq)
    if not valid then return false end
    if now_ms ~= nil and not is_finite_number(now_ms) then return false end

    local acc = fix_payload.accuracy or 1.0
    if not check_kinematic_gate(state, gx, gz, acc, dt, now_ms) then
        state.spikeStreak = (state.spikeStreak or 0) + 1
        state.validStreak = 0
        if state.spikeStreak >= 3 then
            apply_streak_snap(state, gx, gz, fix_payload, now_ms, cSeq)
            return true
        end
        return false
    end

    apply_fix_fusion(state, gx, gz, fix_payload, now_ms, cSeq)
    return true
end

function nav_engine.update(state, dt, now_ms)
    local now = now_ms or 0
    local is_stale = nav_engine.update_timeout(state, now)
    local coreAlive = (now - (state.lastCoreRxMs or 0)) <= (state.coreTimeoutMs or 500)
    return {
        pos = { x = state.pos.x, y = state.pos.y, z = state.pos.z },
        vel = { x = state.vel.x, y = state.vel.y, z = state.vel.z },
        attitude = { pitch = state.attitude.pitch, roll = state.attitude.roll, heading = state.attitude.heading },
        groundSpeed = state.groundSpeed,
        altitudeY = state.altitudeY,
        verticalSpeed = state.verticalSpeed,
        fuel = state.fuel,
        coreArmed = state.coreArmed,
        coreAlive = coreAlive,
        gpsTimedOut = is_stale,
        gpsRecovered = (state.validStreak or 0) >= 3,
        hdop = state.hdop,
        navValid = state.navValid,
        posEpoch = state.posEpoch,
    }
end

return nav_engine
