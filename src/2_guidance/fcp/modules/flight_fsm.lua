-- src/2_guidance/fcp/modules/flight_fsm.lua
-- FCP v2.0.0 6-State Outer-Loop Flight Finite State Machine
-- CC:Tweaked Lua 5.2 / Cobalt VM compliant

local flight_fsm = {}

flight_fsm.STATES = {
    BOOT = true,
    IDLE_ARMED = true,
    ACTIVE_TRACKING = true,
    PASSIVE_TRACKING = true,
    AMM_TIMEOUT_HOLD = true,
    EMERGENCY_LAND = true,
}

local ALLOWED_TRANSITIONS = {
    BOOT = {
        IDLE_ARMED = true,
    },
    IDLE_ARMED = {
        ACTIVE_TRACKING = true,
    },
    ACTIVE_TRACKING = {
        IDLE_ARMED = true,
        PASSIVE_TRACKING = true,
        AMM_TIMEOUT_HOLD = true,
        EMERGENCY_LAND = true,
    },
    PASSIVE_TRACKING = {
        ACTIVE_TRACKING = true,
        IDLE_ARMED = true,
    },
    AMM_TIMEOUT_HOLD = {
        ACTIVE_TRACKING = true,
        EMERGENCY_LAND = true,
        IDLE_ARMED = true,
    },
    EMERGENCY_LAND = {
        IDLE_ARMED = true,
    },
}

function flight_fsm.is_transition_allowed(curr, nextState)
    if not curr or not nextState then return false end
    if curr == nextState then return false end
    local valid_next = ALLOWED_TRANSITIONS[curr]
    if not valid_next then return false end
    return valid_next[nextState] == true
end

local function do_transition(state, nextState)
    local curr = state.currentState
    if curr == nextState then
        return false
    end
    if flight_fsm.is_transition_allowed(curr, nextState) then
        state.currentState = nextState
        return true
    end
    return false
end

function flight_fsm.init(config, safetyConfig)
    local cfg = config or {}
    local sys = cfg.system or cfg
    local safe = safetyConfig or cfg.safety or {}
    return {
        currentState = "BOOT",
        airframeType = sys.airframeType or "VECTORED_VTOL",
        safety = {
            ammSetpointTimeoutMs = safe.ammSetpointTimeoutMs or 500,
            ammTimeoutHoldToEmgMs = safe.ammTimeoutHoldToEmgMs or 10000,
            bumplessRampSec = safe.bumplessRampSec or 2.0,
        },
        flightActive = false,
        arm = false,
        bumplessTriggered = false,
        rampStartMs = -10000,
        timeoutHoldStartMs = nil,
        prevFlightMode = nil,
    }
end

local function is_emergency_condition(ctx, telem)
    if ctx.emergencyAlert == true then return true end
    if telem.activeSource == "EMERGENCY_DIRECT" then return true end
    if telem.controlState == "E_STOP" then return true end
    return false
end

local function handle_emergency_stop(state, events)
    do_transition(state, "IDLE_ARMED")
    state.flightActive = false
    state.arm = false
    events.resetIntegrators = true
    events.triggerBumpless = false
end

local function step_boot(state, ctx, events)
    if ctx.channelsReady ~= false then
        if do_transition(state, "IDLE_ARMED") then
            state.flightActive = false
            events.resetIntegrators = true
        end
    end
end

local function step_idle_armed(state, sp, now_ms, events)
    if sp.arm == true and sp.flightActive == true then
        if do_transition(state, "ACTIVE_TRACKING") then
            state.flightActive = true
            state.arm = true
            state.prevFlightMode = sp.flightMode
            events.resetIntegrators = true
        end
    else
        state.flightActive = false
        if sp.arm ~= nil then state.arm = sp.arm end
    end
end

local function trigger_bumpless(state, now_ms, events, newMode)
    events.triggerBumpless = true
    events.resetIntegrators = true
    state.bumplessTriggered = true
    state.rampStartMs = now_ms
    if newMode then state.prevFlightMode = newMode end
end

local function step_active_tracking(state, ctx, sp, telem, now_ms, events)
    if sp.arm == false or sp.flightActive == false then
        do_transition(state, "IDLE_ARMED")
        state.flightActive = false
        events.resetIntegrators = true
        return
    end
    if sp.flightMode == "EMERGENCY_LAND" then
        if do_transition(state, "EMERGENCY_LAND") then
            events.resetIntegrators = true
        end
        return
    end
    if telem.activeSource == "MFD_ACRO" then
        if do_transition(state, "PASSIVE_TRACKING") then
            events.freezeIntegrators = true
        end
        return
    end
    local lastRx = sp.lastRxMs or ctx.lastRxMs
    local timeoutMs = state.safety.ammSetpointTimeoutMs or 500
    if lastRx and (now_ms - lastRx >= timeoutMs) then
        if do_transition(state, "AMM_TIMEOUT_HOLD") then
            state.timeoutHoldStartMs = now_ms
            events.resetIntegrators = true
        end
        return
    end
    if sp.flightMode and state.prevFlightMode and sp.flightMode ~= state.prevFlightMode then
        trigger_bumpless(state, now_ms, events, sp.flightMode)
    elseif sp.flightMode then
        state.prevFlightMode = sp.flightMode
    end
end

local function step_passive_tracking(state, sp, telem, now_ms, events)
    if sp.arm == false or sp.flightActive == false then
        do_transition(state, "IDLE_ARMED")
        state.flightActive = false
        events.resetIntegrators = true
        return
    end
    if telem.activeSource == "FCP" or (telem.activeSource ~= "MFD_ACRO" and telem.activeSource ~= "EMERGENCY_DIRECT") then
        if do_transition(state, "ACTIVE_TRACKING") then
            trigger_bumpless(state, now_ms, events, sp.flightMode)
        end
    else
        events.freezeIntegrators = true
    end
end

local function step_amm_timeout_hold(state, ctx, sp, now_ms, events)
    if sp.arm == false or sp.flightActive == false then
        do_transition(state, "IDLE_ARMED")
        state.flightActive = false
        events.resetIntegrators = true
        return
    end
    local lastRx = sp.lastRxMs or ctx.lastRxMs
    local timeoutMs = state.safety.ammSetpointTimeoutMs or 500
    if lastRx and (now_ms - lastRx < timeoutMs) then
        if do_transition(state, "ACTIVE_TRACKING") then
            state.timeoutHoldStartMs = nil
            trigger_bumpless(state, now_ms, events, sp.flightMode)
        end
        return
    end
    local holdStart = state.timeoutHoldStartMs or now_ms
    local holdLimit = state.safety.ammTimeoutHoldToEmgMs or 10000
    if (now_ms - holdStart >= holdLimit) then
        if do_transition(state, "EMERGENCY_LAND") then
            state.timeoutHoldStartMs = nil
            events.resetIntegrators = true
        end
    end
end

local function step_emergency_land(state, ctx, sp, events)
    if ctx.touchdownComplete == true or ctx.touchdown == true or sp.arm == false or sp.flightActive == false then
        if do_transition(state, "IDLE_ARMED") then
            state.flightActive = false
            state.arm = false
            events.resetIntegrators = true
        end
    end
end

function flight_fsm.step(state, ctx, now_ms)
    local s = state or flight_fsm.init()
    local c = ctx or {}
    local now = tonumber(now_ms) or 0
    local telem = c.telemState or {}
    local sp = c.setpoint or {}

    local events = {
        triggerBumpless = false,
        resetIntegrators = false,
        freezeIntegrators = false,
    }

    if is_emergency_condition(c, telem) then
        handle_emergency_stop(s, events)
        return s, events
    end

    local curr = s.currentState or "BOOT"
    if curr == "BOOT" then
        step_boot(s, c, events)
    elseif curr == "IDLE_ARMED" then
        step_idle_armed(s, sp, now, events)
    elseif curr == "ACTIVE_TRACKING" then
        step_active_tracking(s, c, sp, telem, now, events)
    elseif curr == "PASSIVE_TRACKING" then
        step_passive_tracking(s, sp, telem, now, events)
    elseif curr == "AMM_TIMEOUT_HOLD" then
        step_amm_timeout_hold(s, c, sp, now, events)
    elseif curr == "EMERGENCY_LAND" then
        step_emergency_land(s, c, sp, events)
    end

    return s, events
end

function flight_fsm.is_flight_active(state)
    if not state then return false end
    local s = state.currentState
    return s == "ACTIVE_TRACKING" or s == "PASSIVE_TRACKING" or s == "AMM_TIMEOUT_HOLD" or s == "EMERGENCY_LAND"
end

function flight_fsm.is_armed(state)
    if not state then return false end
    local s = state.currentState
    return s ~= "BOOT"
end

function flight_fsm.is_vtol(airframe_type)
    local af = airframe_type or "VECTORED_VTOL"
    return (af == "VECTORED_VTOL" or af == "ADVANCED_VTOL" or af == "QUADROTOR" or af == "HEXAROTOR" or af == "WINGED_VTOL")
end

return flight_fsm
