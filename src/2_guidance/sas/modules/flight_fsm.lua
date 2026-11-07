-- src/modules/flight_fsm.lua
local flight_fsm = {}

function flight_fsm.init(config)
    local cfg = config or {}
    local sys = cfg.system or {}
    local safe = cfg.safety or {}
    return {
        current_state = "BOOT_INIT",
        airframeType = sys.airframeType or "VECTORED_VTOL",
        lowFuelRthThreshold = safe.lowFuelRthThreshold or 0.20,
        emergencyLandFuelThreshold = safe.emergencyLandFuelThreshold or 0.10,
        lockReason = nil,
        lastWarning = nil,
        inFlight = false,
    }
end

function flight_fsm.transition_to(state, next_state, reason)
    if not state then return end
    state.current_state = next_state
    if reason then state.lockReason = reason end
    local inflight_set = {
        TAKEOFF = true, CRUISE = true, LOITER = true,
        APPROACH_LAND = true, FAILSAFE_HOLD = true,
        FAILSAFE_RTH = true, EMERGENCY_LAND = true,
    }
    state.inFlight = inflight_set[next_state] == true
end

function flight_fsm.check_failsafes(state, ctx, now_ms)
    if not state or not state.inFlight then return nil end
    local c = ctx or {}
    if c.hasSwayLoss then
        flight_fsm.transition_to(state, "EMERGENCY_LAND", "SWAY_LOSS")
        return "EMERGENCY_LAND"
    end
    if c.fuel and c.fuel < state.emergencyLandFuelThreshold then
        flight_fsm.transition_to(state, "EMERGENCY_LAND", "CRITICAL_LOW_FUEL")
        return "EMERGENCY_LAND"
    end
    if c.coreAlive == false then
        flight_fsm.transition_to(state, "EMERGENCY_LAND", "CORE_TIMEOUT")
        return "EMERGENCY_LAND"
    end
    if c.fuel and c.fuel < state.lowFuelRthThreshold and state.current_state ~= "FAILSAFE_RTH" then
        flight_fsm.transition_to(state, "FAILSAFE_RTH", "LOW_FUEL_RTH")
        return "FAILSAFE_RTH"
    end
    if c.gpsTimedOut and state.current_state ~= "FAILSAFE_HOLD" and state.current_state ~= "EMERGENCY_LAND" then
        flight_fsm.transition_to(state, "FAILSAFE_HOLD", "GPS_TIMEOUT")
        return "FAILSAFE_HOLD"
    end
    return nil
end

local function handle_ground_transitions(state, ctx)
    local s = state.current_state
    if ctx.airframeSupported == false then
        flight_fsm.transition_to(state, "ARMING_LOCKED", "UNSUPPORTED_AIRFRAME_DEFERRED")
        return
    end
    if ctx.channelLocked then
        flight_fsm.transition_to(state, "ARMING_LOCKED", "RF_CHANNEL_CONFLICT")
        return
    end
    if s == "BOOT_INIT" or s == "BOOTSTRAP" or s == "PROBE_CHANNEL" then
        if ctx.channelAcquired then
            flight_fsm.transition_to(state, "DISARMED")
        end
    elseif s == "DISARMED" and ctx.cmd == "ARM" then
        flight_fsm.transition_to(state, "ARMING")
    elseif s == "ARMING" and ctx.coreArmed then
        flight_fsm.transition_to(state, "IDLE_ARMED")
    elseif s == "IDLE_ARMED" and ctx.cmd == "TAKEOFF" then
        local gate = ctx.takeoffGate or { allowed = true }
        if gate.allowed then
            if gate.warn_code then state.lastWarning = gate.warn_code end
            flight_fsm.transition_to(state, "TAKEOFF")
        end
    end
end

function flight_fsm.evaluate(state, ctx, now_ms)
    if not state then return "BOOT_INIT" end
    local c = ctx or {}

    if c.activeSource and c.activeSource ~= "SAS" then
        if state.current_state ~= "PASSIVE_TRACKING" then
            state.prePassiveState = state.current_state
            flight_fsm.transition_to(state, "PASSIVE_TRACKING", "ACRO_DIRECT_TAKEOVER")
        end
        return state.current_state
    elseif state.current_state == "PASSIVE_TRACKING" then
        if c.activeSource == "SAS" or c.activeSource == nil then
            state.recoveringBumpless = true
            local prev = state.prePassiveState or "CRUISE"
            state.prePassiveState = nil
            flight_fsm.transition_to(state, prev, "RESUME_UAP_CONTROL")
        else
            return "PASSIVE_TRACKING"
        end
    end

    if not state.inFlight then
        handle_ground_transitions(state, c)
        return state.current_state
    end
    local fs_act = flight_fsm.check_failsafes(state, c, now_ms)
    if fs_act then return state.current_state end

    local s = state.current_state
    if s == "TAKEOFF" and (c.climbAltitudeReached or c.cmd == "CRUISE") then
        flight_fsm.transition_to(state, "CRUISE")
    elseif s == "CRUISE" and c.cmd == "LOITER" then
        flight_fsm.transition_to(state, "LOITER")
    elseif s == "LOITER" and c.cmd == "CRUISE" then
        flight_fsm.transition_to(state, "CRUISE")
    elseif (s == "CRUISE" or s == "LOITER") and c.atcStatus == "CLEARED" then
        flight_fsm.transition_to(state, "APPROACH_LAND")
    elseif s == "APPROACH_LAND" and (c.approachAction == "GO_AROUND") then
        flight_fsm.transition_to(state, "LOITER")
    elseif s == "APPROACH_LAND" and (c.approachAction == "ABORT_DIVERT") then
        flight_fsm.transition_to(state, "FAILSAFE_RTH")
    elseif s == "FAILSAFE_HOLD" and c.gpsRecovered then
        flight_fsm.transition_to(state, "CRUISE")
    elseif (s == "APPROACH_LAND" or s == "EMERGENCY_LAND") and c.touchdownComplete then
        flight_fsm.transition_to(state, "DISARMED")
    end
    return state.current_state
end

function flight_fsm.evaluate_rth(state, fac_state, craft_pos, now_ms)
    if not state then return { action = "NONE" } end
    local facility_client_mod = require("facility_client")
    local best_fac, dist = nil, 999999
    if fac_state and facility_client_mod and facility_client_mod.find_nearest_free_landing_facility then
        best_fac, dist = facility_client_mod.find_nearest_free_landing_facility(fac_state, craft_pos)
    end

    if best_fac and dist then
        if dist <= 5.0 then
            flight_fsm.transition_to(state, "APPROACH_LAND", "RTH_FACILITY_REACHED")
            return {
                action = "APPROACH_LAND",
                targetFacilityId = best_fac.facilityId,
                position = best_fac.position,
                distance = dist,
            }
        else
            return {
                action = "NAV_TO_FACILITY",
                targetFacilityId = best_fac.facilityId,
                position = best_fac.position,
                distance = dist,
            }
        end
    else
        flight_fsm.transition_to(state, "LOITER", "NO_FREE_FACILITY")
        return {
            action = "LOITER_WAIT",
            holdingClimb = 30.0,
        }
    end
end

function flight_fsm.is_flight_active(state)
    local active_set = {
        TAKEOFF = true, CRUISE = true, LOITER = true,
        APPROACH_LAND = true, FAILSAFE_HOLD = true,
        FAILSAFE_RTH = true, EMERGENCY_LAND = true,
    }
    return state ~= nil and active_set[state.current_state] == true
end

function flight_fsm.is_armed(state)
    local armed_set = {
        ARMING = true, IDLE_ARMED = true, TAKEOFF = true,
        CRUISE = true, LOITER = true, APPROACH_LAND = true,
        FAILSAFE_HOLD = true, FAILSAFE_RTH = true, EMERGENCY_LAND = true,
        PASSIVE_TRACKING = true,
    }
    return state ~= nil and armed_set[state.current_state] == true
end

return flight_fsm
