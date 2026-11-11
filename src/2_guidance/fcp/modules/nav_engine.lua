-- src/modules/nav_engine.lua
local nav_engine = {}

local function is_finite_number(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

function nav_engine.init(config)
    local cfg = config or {}
    local nav = cfg.navigation or {}
    local safe = cfg.safety or {}
    return {
        pos = { x = 0.0, y = 64.0, z = 0.0 },
        vel = { x = 0.0, y = 0.0, z = 0.0 },
        attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
        rates = { p = 0.0, q = 0.0, r = 0.0 },
        groundSpeed = 0.0,
        fuel = 1.0,
        coreArmed = false,
        hdop = 1.0,
        alpha = nav.drComplementaryAlpha or 0.35,
        maxHdop = nav.maxAllowedHdop or 3.0,
        kinematicLimitM = nav.kinematicGateLimitM or 8.0,
        coreTimeoutMs = safe.coreTelemetryTimeoutMs or 500,
        gpsTimeoutMs = nav.gpsTimeoutMs or 5000,
        lastCoreRxMs = 0,
        lastGpsFixMs = 0,
        lastGpsReqMs = 0,
        gpsReqSeq = 0,
        lastGpsFixSeq = 0,
        spikeStreak = 0,
        validStreak = 0,
    }
end

function nav_engine.should_query_gps(state, now_ms)
    local now = now_ms or 0
    if (now - state.lastGpsReqMs) >= 100 then
        state.lastGpsReqMs = now
        state.gpsReqSeq = state.gpsReqSeq + 1
        return true, state.gpsReqSeq
    end
    return false, nil
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
    state.pos.x = state.pos.x + vx * step_dt
    local altY = dyn.altitudeY
    if not is_finite_number(altY) then
        altY = telemetry.altitudeY
    end
    if is_finite_number(altY) then
        state.pos.y = altY
    else
        state.pos.y = state.pos.y + vy * step_dt
    end
    state.pos.z = state.pos.z + vz * step_dt

    local att = telemetry.attitude or {}
    state.attitude.pitch = att.pitch or telemetry.pitch or state.attitude.pitch
    state.attitude.roll = att.roll or telemetry.roll or state.attitude.roll
    state.attitude.heading = dyn.heading or att.yaw or telemetry.heading or state.attitude.heading

    state.fuel = telemetry.fuel or state.fuel
    local cs = telemetry.controlState
    if cs ~= nil then
        state.coreArmed = (cs ~= "DISARMED" and cs ~= "UNINITIALIZED")
    else
        state.coreArmed = (telemetry.armed == true)
    end
    state.lastCoreRxMs = now_ms or 0
end

local function maybe_update_fix_ms(state, now_ms)
    if is_finite_number(now_ms) and now_ms >= (state.lastGpsFixMs or 0) then
        state.lastGpsFixMs = now_ms
    end
end

local function apply_fix_fusion(state, fix, now_ms)
    local a = state.alpha
    if (fix.hdop and fix.hdop > state.maxHdop) or (fix.accuracy and fix.accuracy > 2.0) then
        a = 0.05
    end
    local pos = fix.position or fix
    local gx = (pos and pos.x) or fix.x or state.pos.x
    local gz = (pos and pos.z) or fix.z or state.pos.z
    state.pos.x = (1.0 - a) * state.pos.x + a * gx
    state.pos.z = (1.0 - a) * state.pos.z + a * gz
    state.hdop = fix.hdop or state.hdop
    maybe_update_fix_ms(state, now_ms)
    state.validStreak = state.validStreak + 1
    state.spikeStreak = 0
end

function nav_engine.filter_gps(state, fix_payload, dt, now_ms)
    if not state or not fix_payload then return false end
    if now_ms ~= nil and not is_finite_number(now_ms) then return false end
    if fix_payload.status and fix_payload.status ~= "FIX_OK" and fix_payload.status ~= "FIX_DEGRADED" then
        return false
    end

    local cSeq = nil
    if fix_payload.clientSeq ~= nil then
        cSeq = tonumber(fix_payload.clientSeq)
        if not is_finite_number(cSeq) or cSeq <= (state.lastGpsFixSeq or 0) or ((state.gpsReqSeq or 0) > 0 and cSeq > state.gpsReqSeq) then
            return false
        end
    end

    local pos = fix_payload.position or fix_payload
    local gx = (pos and pos.x) or fix_payload.x
    local gz = (pos and pos.z) or fix_payload.z
    if not is_finite_number(gx) or not is_finite_number(gz) then return false end

    local acc = fix_payload.accuracy or 1.0
    local fallback_dt = dt or 0.05
    local delta_t = fallback_dt
    if (state.lastGpsFixMs or 0) > 0 and is_finite_number(now_ms) and now_ms > state.lastGpsFixMs then
        local elapsed = (now_ms - state.lastGpsFixMs) / 1000.0
        local maxSpanSec = (state.gpsTimeoutMs or 5000) / 1000.0
        delta_t = math.max(fallback_dt, math.min(elapsed, maxSpanSec))
    end
    local max_allowed = math.max(state.kinematicLimitM, state.groundSpeed * delta_t * 1.5 + 3.0 * acc)
    local dx = gx - state.pos.x
    local dz = gz - state.pos.z
    local dist = math.sqrt(dx * dx + dz * dz)

    if dist > max_allowed then
        state.spikeStreak = state.spikeStreak + 1
        state.validStreak = 0
        if state.spikeStreak >= 3 then
            state.pos.x = gx
            state.pos.z = gz
            maybe_update_fix_ms(state, now_ms)
            state.hdop = fix_payload.hdop or state.hdop
            state.spikeStreak = 0
            state.validStreak = 1
            if cSeq then state.lastGpsFixSeq = cSeq end
            return true
        end
        return false
    end

    apply_fix_fusion(state, fix_payload, now_ms)
    if cSeq then state.lastGpsFixSeq = cSeq end
    return true
end

function nav_engine.update(state, dt, now_ms)
    local now = now_ms or 0
    local coreAlive = (now - state.lastCoreRxMs) <= state.coreTimeoutMs
    local gpsTimedOut = (now - state.lastGpsFixMs) > state.gpsTimeoutMs
    local gpsRecovered = state.validStreak >= 3
    return {
        pos = { x = state.pos.x, y = state.pos.y, z = state.pos.z },
        vel = { x = state.vel.x, y = state.vel.y, z = state.vel.z },
        attitude = { pitch = state.attitude.pitch, roll = state.attitude.roll, heading = state.attitude.heading },
        groundSpeed = state.groundSpeed,
        fuel = state.fuel,
        coreArmed = state.coreArmed,
        coreAlive = coreAlive,
        gpsTimedOut = gpsTimedOut,
        gpsRecovered = gpsRecovered,
        hdop = state.hdop,
    }
end

return nav_engine
