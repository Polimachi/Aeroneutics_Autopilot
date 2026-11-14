-- src/2_guidance/fcp/modules/state_propagator.lua
-- VAS Base+2 velocity integration, AMM posEpoch bounded merge, and navStale monitoring (ICD v1.28.0)
local state_propagator = {}

local function clamp_dt(dt, max_dt)
    local lim = tonumber(max_dt) or 0.1
    if dt < 0.0 then return 0.0 end
    if dt > lim then return lim end
    return dt
end

function state_propagator.init(cfg)
    local c = cfg or {}
    local ol = c.outerLoop or c
    local safe = c.safety or c
    local initPos = c.initialPos or {}
    return {
        pos = {
            x = tonumber(initPos.x) or 0.0,
            y = tonumber(initPos.y) or 0.0,
            z = tonumber(initPos.z) or 0.0,
        },
        vel = { vx = 0.0, vy = 0.0, vz = 0.0 },
        attitude = { pitch = 0.0, roll = 0.0, heading = 0.0, yaw = 0.0 },
        angularRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
        groundSpeed = 0.0,
        airspeed = 0.0,
        actuatorHealth = { tap = true, asa = true, allOk = true },
        activeSource = "FCP",
        sensorOk = true,
        posEpoch = 0,
        lastSyncedEpoch = 0,
        lastTelemMs = 0,
        lastPropagateMs = 0,
        lastSetpointMs = 0,
        navValid = true,
        gpsTimedOut = false,
        hdop = 1.0,
        navStale = false,
        dtPropMaxSec = tonumber(ol.dtPropMaxSec) or 0.1,
        posMergeMaxStepM = tonumber(ol.posMergeMaxStepM) or 2.0,
        navStaleTimeoutMs = tonumber(safe.navStaleTimeoutMs) or 500,
    }
end

local function apply_velocity(state, dyn)
    if not dyn or not dyn.velocity then return end
    local v = dyn.velocity
    state.vel.vx = tonumber(v.vx) or 0.0
    state.vel.vy = tonumber(v.vy) or 0.0
    state.vel.vz = tonumber(v.vz) or 0.0
    state.groundSpeed = math.sqrt(state.vel.vx * state.vel.vx + state.vel.vz * state.vel.vz)
    state.airspeed = tonumber(dyn.airspeed) or state.groundSpeed
end

local function apply_orientation(state, att, ar)
    if att then
        state.attitude.pitch = tonumber(att.pitch) or 0.0
        state.attitude.roll = tonumber(att.roll) or 0.0
        local yaw = tonumber(att.yaw) or 0.0
        state.attitude.yaw = yaw
        state.attitude.heading = yaw
    end
    if ar then
        state.angularRates.pitchRate = tonumber(ar.pitchRate) or 0.0
        state.angularRates.rollRate = tonumber(ar.rollRate) or 0.0
        state.angularRates.yawRate = tonumber(ar.yawRate) or 0.0
    end
end

function state_propagator.on_telemetry(state, telemPayload, now_ms)
    if not state or type(telemPayload) ~= "table" then return end
    apply_velocity(state, telemPayload.dynamics)
    apply_orientation(state, telemPayload.attitude, telemPayload.angularRates)
    if type(telemPayload.actuatorHealth) == "table" then
        local ah = telemPayload.actuatorHealth
        local tap = (ah.tap ~= false)
        local asa = (ah.asa ~= false)
        local allOk = (ah.allOk ~= nil) and (ah.allOk == true) or (tap and asa)
        state.actuatorHealth = {
            tca = ah.tca,
            tap = tap,
            asa = asa,
            allOk = allOk,
        }
    end
    if telemPayload.activeSource then
        state.activeSource = telemPayload.activeSource
    end
    if telemPayload.sensorOk ~= nil then
        state.sensorOk = telemPayload.sensorOk
    end
    state.lastTelemMs = now_ms or (os.epoch and os.epoch("utc") or 0)
    if state.lastPropagateMs == 0 then
        state.lastPropagateMs = state.lastTelemMs
    end
end

local function merge_current_pos(state, curPos, maxStep)
    local cx = tonumber(curPos.x) or state.pos.x
    local cy = tonumber(curPos.y) or state.pos.y
    local cz = tonumber(curPos.z) or state.pos.z
    local dx = cx - state.pos.x
    local dy = cy - state.pos.y
    local dz = cz - state.pos.z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist <= maxStep then
        state.pos.x = cx
        state.pos.y = cy
        state.pos.z = cz
    else
        local s = maxStep / dist
        state.pos.x = state.pos.x + dx * s
        state.pos.y = state.pos.y + dy * s
        state.pos.z = state.pos.z + dz * s
    end
end

function state_propagator.on_setpoint_epoch(state, setpointPayload, now_ms)
    if not state or type(setpointPayload) ~= "table" then return end
    if setpointPayload.navValid ~= nil then state.navValid = setpointPayload.navValid end
    if setpointPayload.gpsTimedOut ~= nil then state.gpsTimedOut = setpointPayload.gpsTimedOut end
    if setpointPayload.hdop ~= nil then state.hdop = setpointPayload.hdop end

    local epoch = tonumber(setpointPayload.posEpoch)
    local curPos = setpointPayload.currentPos
    if epoch and epoch > state.lastSyncedEpoch then
        if type(curPos) == "table" then
            local maxStep = state.posMergeMaxStepM or 2.0
            merge_current_pos(state, curPos, maxStep)
        end
        state.posEpoch = epoch
        state.lastSyncedEpoch = epoch
        state.lastSetpointMs = now_ms or (os.epoch and os.epoch("utc") or 0)
    end
end

function state_propagator.propagate(state, now_ms)
    local now = now_ms or (os.epoch and os.epoch("utc") or 0)
    local last = (state.lastPropagateMs and state.lastPropagateMs > 0) and state.lastPropagateMs or now
    local dt = clamp_dt((now - last) / 1000.0, state.dtPropMaxSec)
    state.lastPropagateMs = now

    state.pos.x = state.pos.x + state.vel.vx * dt
    state.pos.y = state.pos.y + state.vel.vy * dt
    state.pos.z = state.pos.z + state.vel.vz * dt

    local timeoutMs = state.navStaleTimeoutMs or 500
    local telemStale = (state.lastTelemMs > 0) and ((now - state.lastTelemMs) > timeoutMs)
    local epochStale = (state.lastSetpointMs > 0) and ((now - state.lastSetpointMs) > timeoutMs)
    state.navStale = telemStale or epochStale or (state.navValid == false)

    return {
        pos = state.pos,
        vel = state.vel,
        attitude = state.attitude,
        angularRates = state.angularRates,
        groundSpeed = state.groundSpeed,
        airspeed = state.airspeed,
        posEpoch = state.posEpoch,
        lastTelemMs = state.lastTelemMs,
        navStale = state.navStale,
        actuatorHealth = state.actuatorHealth,
        activeSource = state.activeSource,
    }
end

return state_propagator
