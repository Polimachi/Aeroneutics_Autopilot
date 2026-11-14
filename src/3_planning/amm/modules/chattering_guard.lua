-- src/3_planning/amm/modules/chattering_guard.lua
-- Anti-chattering state guard: hysteresis deadbands, N-tick debounce,
-- unilateral fuel latches, and dwell locks with upward priority preemption.

local chattering_guard = {}

chattering_guard.PRIORITY = {
    E_STOP = 1,
    EMERG_LAND = 2,
    FENCE_BRAKE = 3,
    RTH_LOITER = 4,
    ABORT_LAND = 5,
    NORMAL = 6,
}

chattering_guard.DEFAULT_CONFIG = {
    fenceBrakeMarginM = 5.0,
    fenceReleaseMarginM = 15.0,
    fenceDebounceTicks = 2,
    fenceDwellTicks = 40,
    lowFuelDebounceTicks = 60,
    emergFuelDebounceTicks = 30,
    fuelLatchResetMargin = 0.05,
    vtolCruiseEnterMps = 18.0,
    vtolHoverReturnMps = 8.0,
    vtolTransDebounceTicks = 10,
    vtolTransDwellTicks = 100,
    deckAbortTiltDeg = 10.0,
    deckSafeTiltDeg = 7.0,
    deckAbortHeaveMps = 2.5,
    deckSafeHeaveMps = 1.8,
    deckAbortDebounceTicks = 2,
    deckSyncDebounceTicks = 10,
    goAroundDwellTicks = 60,
    arrivalSettleTicks = 4,
    arrivalReengageMarginM = 2.0,
}

local REPEAT_SKIP_ACTIONS = {
    ACT_SYS_LOAD = true,
    ACT_SYS_PREFLIGHT = true,
    ACT_SYS_SET_HOME = true,
    ACT_SYS_ARM = true,
    ACT_SYS_DISARM = true,
    ACT_TKL_TAKEOFF_VERT = true,
    ACT_MOB_MOVING_TKOFF = true,
}

local function merge_chattering_cfg(config)
    local out = {}
    for k, v in pairs(chattering_guard.DEFAULT_CONFIG) do
        out[k] = v
    end
    local safety = type(config) == "table" and config.safety or nil
    local src = type(safety) == "table" and safety.chattering or nil
    if type(src) == "table" then
        for k, v in pairs(src) do
            if out[k] ~= nil then out[k] = v end
        end
    end
    return out, (type(safety) == "table" and safety or {})
end

--- Create an anti-chattering state container initialized from amm_config.
function chattering_guard.init(config)
    local chatCfg, safety = merge_chattering_cfg(config)
    return {
        cfg = chatCfg,
        lowFuelRthThreshold = tonumber(safety.lowFuelRthThreshold) or 0.20,
        emergencyLandFuelThreshold = tonumber(safety.emergencyLandFuelThreshold) or 0.10,
        debounce = {},
        dwell = {},
        latches = {
            lowFuelLatched = false,
            emergFuelLatched = false,
            fenceBrakeActive = false,
            vtolCruiseActive = false,
            deckAbortActive = false,
        },
    }
end

--- Reset transient counters, dwell timers, and recovery latches.
function chattering_guard.reset(state)
    if type(state) ~= "table" then return end
    state.debounce = {}
    state.dwell = {}
    if type(state.latches) ~= "table" then state.latches = {} end
    state.latches.lowFuelLatched = false
    state.latches.emergFuelLatched = false
    state.latches.fenceBrakeActive = false
    state.latches.vtolCruiseActive = false
    state.latches.deckAbortActive = false
end

--- Evaluate asymmetric threshold hysteresis in HIGH_ACTIVE or LOW_ACTIVE mode.
function chattering_guard.eval_hysteresis(prevActive, value, enterTh, exitTh, mode)
    local active = (prevActive == true)
    if type(value) ~= "number" or type(enterTh) ~= "number" or type(exitTh) ~= "number" then
        return active
    end
    if mode == "HIGH_ACTIVE" then
        if active then return value > exitTh end
        return value >= enterTh
    elseif mode == "LOW_ACTIVE" then
        if active then return value < exitTh end
        return value <= enterTh
    end
    return active
end

--- Evaluate consecutive-tick debounce; resets counter immediately on false tick.
function chattering_guard.eval_debounce(state, key, condition, requiredTicks)
    if type(state) ~= "table" or not key then return false end
    state.debounce = state.debounce or {}
    local req = math.max(1, math.floor(tonumber(requiredTicks) or 1))
    if condition then
        local count = (state.debounce[key] or 0) + 1
        state.debounce[key] = count
        return count >= req
    end
    state.debounce[key] = 0
    return false
end

--- Record a minimum dwell lock window until nowTick + dwellTicks.
function chattering_guard.start_dwell(state, key, nowTick, dwellTicks)
    if type(state) ~= "table" or not key then return end
    state.dwell = state.dwell or {}
    local ticks = math.max(0, math.floor(tonumber(dwellTicks) or 0))
    state.dwell[key] = (tonumber(nowTick) or 0) + ticks
end

--- Check whether key is dwell-locked unless candidatePrio has strictly higher urgency (lower number).
function chattering_guard.is_dwell_locked(state, key, nowTick, currentPrio, candidatePrio)
    if type(state) ~= "table" or type(state.dwell) ~= "table" then return false end
    local untilTick = state.dwell[key]
    if not untilTick or (tonumber(nowTick) or 0) >= untilTick then
        return false
    end
    if type(candidatePrio) == "number" and type(currentPrio) == "number" and candidatePrio < currentPrio then
        return false
    end
    return true
end

--- Update unilateral fuel latches; unlatch is only permitted while DISARMED above hysteresis margin.
function chattering_guard.update_fuel_latches(state, fuel, cfg, isDisarmed)
    if type(state) ~= "table" then return nil end
    state.latches = state.latches or {}
    if type(fuel) ~= "number" then return state.latches end

    local chCfg, safety = merge_chattering_cfg(cfg)
    local ch = (type(cfg) == "table" and type(cfg.safety) == "table" and chCfg) or state.cfg or chattering_guard.DEFAULT_CONFIG
    local lowTh = tonumber(safety.lowFuelRthThreshold) or state.lowFuelRthThreshold or 0.20
    local emergTh = tonumber(safety.emergencyLandFuelThreshold) or state.emergencyLandFuelThreshold or 0.10
    local margin = tonumber(ch.fuelLatchResetMargin) or 0.05

    if isDisarmed then
        if state.latches.lowFuelLatched and fuel >= (lowTh + margin) then
            state.latches.lowFuelLatched = false
            chattering_guard.eval_debounce(state, "fuel_low", false, 1)
        end
        if state.latches.emergFuelLatched and fuel >= (emergTh + margin) then
            state.latches.emergFuelLatched = false
            chattering_guard.eval_debounce(state, "fuel_emerg", false, 1)
        end
    end

    if chattering_guard.eval_debounce(state, "fuel_low", fuel <= lowTh, ch.lowFuelDebounceTicks) then
        state.latches.lowFuelLatched = true
    end
    if chattering_guard.eval_debounce(state, "fuel_emerg", fuel <= emergTh, ch.emergFuelDebounceTicks) then
        state.latches.emergFuelLatched = true
    end
    return state.latches
end

--- Return true when action represents ground-init/takeoff that REPEAT wrap must skip.
function chattering_guard.should_skip_on_repeat(action)
    return REPEAT_SKIP_ACTIONS[action] == true
end

return chattering_guard
