-- src/3_planning/amm/modules/action_registry.lua
-- AMM v2.0.0 3-Tier Action Primitive Registry, Macro Expander,
-- Decorator Classifier, and 4-Category Precondition Evaluator.

local action_registry = {}

local ACTIVE_LIFECYCLES = {
    -- System Lifecycle (6)
    ACT_SYS_LOAD = { group = "SYS", complete = "MANUAL", abort = "ABORT_HOLD" },
    ACT_SYS_PREFLIGHT = { group = "SYS", complete = "MANUAL", abort = "DISARM_HOLD" },
    ACT_SYS_SET_HOME = { group = "SYS", complete = "IMMEDIATE", abort = "NONE" },
    ACT_SYS_ARM = { group = "SYS", complete = "IMMEDIATE", abort = "ACT_SYS_DISARM" },
    ACT_SYS_DISARM = { group = "SYS", complete = "IMMEDIATE", abort = "NONE" },
    ACT_SYS_TERMINATE = { group = "SYS", complete = "IMMEDIATE", abort = "E_STOP" },
    -- Takeoff / Transition / Landing (6)
    ACT_TKL_TAKEOFF_VERT = { group = "TKL", complete = "ALTITUDE_REACHED", abort = "ACT_TKL_LAND_PREC" },
    ACT_TKL_TRANS_MC2FW = { group = "TKL", complete = "AIRSPEED_REACHED", abort = "ACT_TKL_TRANS_FW2MC" },
    ACT_TKL_TRANS_FW2MC = { group = "TKL", complete = "AIRSPEED_BELOW", abort = "ACT_FS_HOVER_HOLD" },
    ACT_TKL_LAND_NORM = { group = "TKL", complete = "TOUCHDOWN", abort = "ACT_TKL_ABORT_LAND" },
    ACT_TKL_LAND_PREC = { group = "TKL", complete = "TOUCHDOWN", abort = "ACT_TKL_ABORT_LAND" },
    ACT_TKL_ABORT_LAND = { group = "TKL", complete = "ALTITUDE_REACHED", abort = "ACT_FS_HOVER_HOLD" },
    -- Navigation & Envelope (6)
    ACT_NAV_GOTO_WP = { group = "NAV", complete = "PROXIMITY_3D", abort = "ACT_FS_HOVER_HOLD" },
    ACT_NAV_SPLINE_WP = { group = "NAV", complete = "PROXIMITY_2D", abort = "ACT_FS_HOVER_HOLD" },
    ACT_NAV_CORRIDOR = { group = "NAV", complete = "PROXIMITY_3D", abort = "ACT_FS_HOVER_HOLD" },
    ACT_NAV_CHANGE_ALT = { group = "NAV", complete = "ALTITUDE_REACHED", abort = "ACT_FS_HOVER_HOLD" },
    ACT_NAV_CHANGE_SPD = { group = "NAV", complete = "IMMEDIATE", abort = "ACT_FS_HOVER_HOLD" },
    ACT_NAV_CHANGE_YAW = { group = "NAV", complete = "HEADING_REACHED", abort = "ACT_FS_HOVER_HOLD" },
    -- Hover / Loiter / Orbit (5)
    ACT_PAT_HOLD_POS = { group = "PAT", complete = "TIME_ELAPSED", abort = "ACT_FS_HOVER_HOLD" },
    ACT_PAT_POI_HOLD = { group = "PAT", complete = "TIME_ELAPSED", abort = "ACT_FS_HOVER_HOLD" },
    ACT_PAT_LOITER_TIME = { group = "PAT", complete = "TIME_ELAPSED", abort = "ACT_FS_HOVER_HOLD" },
    ACT_PAT_LOITER_TURNS = { group = "PAT", complete = "ORBIT_TURNS", abort = "ACT_FS_HOVER_HOLD" },
    ACT_PAT_LOITER_ALT = { group = "PAT", complete = "ALTITUDE_REACHED", abort = "ACT_FS_HOVER_HOLD" },
    -- Payload & I/O (4)
    ACT_PAY_BUS_CMD = { group = "PAY", complete = "ACK_OR_IMMEDIATE", abort = "ACT_FS_HOVER_HOLD" },
    ACT_PAY_REDSTONE = { group = "PAY", complete = "TIME_ELAPSED", abort = "ACT_FS_HOVER_HOLD" },
    ACT_PAY_SET_ROI = { group = "PAY", complete = "IMMEDIATE", abort = "NONE" },
    ACT_PAY_CLEAR_ROI = { group = "PAY", complete = "IMMEDIATE", abort = "NONE" },
    -- Communications / ATC (1)
    ACT_COM_ATC_HOLD = { group = "COM", complete = "TIME_ELAPSED", abort = "ACT_FS_RTL_HOME" },
    -- Mobile Carrier & Rendezvous (3)
    ACT_MOB_RV_TRACK = { group = "MOB", complete = "PROXIMITY_3D", abort = "ACT_FS_HOVER_HOLD" },
    ACT_MOB_DECK_SYNC = { group = "MOB", complete = "DECK_SYNCED", abort = "ACT_TKL_ABORT_LAND" },
    ACT_MOB_MOVING_TKOFF = { group = "MOB", complete = "ALTITUDE_REACHED", abort = "ACT_FS_HOVER_HOLD" },
    -- Failsafe Primitives (5)
    ACT_FS_RTL_HOME = { group = "FS", complete = "PROXIMITY_2D", abort = "ACT_FS_EMERG_LAND" },
    ACT_FS_GOTO_RALLY = { group = "FS", complete = "PROXIMITY_2D", abort = "ACT_FS_EMERG_LAND" },
    ACT_FS_FENCE_BRAKE = { group = "FS", complete = "IMMEDIATE", abort = "ACT_FS_HOVER_HOLD" },
    ACT_FS_HOVER_HOLD = { group = "FS", complete = "MANUAL", abort = "ACT_FS_EMERG_LAND" },
    ACT_FS_EMERG_LAND = { group = "FS", complete = "TOUCHDOWN", abort = "ACT_SYS_DISARM" },
}

local DEFERRED_ACTIONS = {
    ACT_TKL_TAKEOFF_RWY = true, ACT_TKL_LAND_RWY = true, ACT_NAV_TERRAIN_FLW = true,
    ACT_PAT_FIG_EIGHT = true, ACT_PAT_GRID_SURVEY = true, ACT_PAT_EXP_SPIRAL = true,
    ACT_PER_LOCAL_AVOID = true, ACT_PER_REPLAN_GLB = true, ACT_PER_TRACK_TGT = true,
    ACT_PER_SENTRY_HOLD = true, ACT_COM_SWARM_FOLLOW = true, ACT_COM_HANDOVER = true,
    ACT_MOB_ARM_DOCK = true, ACT_MOB_ARM_UNDOCK = true,
    ACT_NRG_REFUEL_DOCK = true, ACT_NRG_HIBERNATE = true,
    ACT_MUMT_WINGMAN = true, ACT_MUMT_UGV_SCOUT = true, ACT_MUMT_CROSS_CUE = true,
    -- TASK-401 TBD
    ACT_PAY_CARGO_DROP = true, ACT_PAY_FIRE_CTRL = true, ACT_PAY_GEO_SCAN = true,
}

local LEGACY_ACTIONS = {
    FLY_OVER = true, FLY_TO = true, ORBIT = true, PATROL = true, POI_HOLD = true,
    TAKEOFF_LAUNCHPAD = true, LAND_LAUNCHPAD = true,
    PAYLOAD_ACTION = true, REDSTONE_ACTION = true,
    TAKEOFF_RUNWAY = true, LAND_RUNWAY = true, DOCK_ARM = true, UNDOCK_ARM = true,
}

local ACTIVE_DECORATORS = {
    DEC_EMCON = true, DEC_ENERGY_ECO = true, DEC_SMOOTH_TRAJ = true,
    DEC_HUMAN_AUTH = true, DEC_RETRY_N = true, DEC_TIMEOUT_GUARD = true,
}
local DEFERRED_DECORATORS = { DEC_TIME_CRIT = true }

local ACTIVE_MACROS = { MAC_RECON_ORBIT = true, MAC_SHIP_RECOVERY = true, MAC_CARGO_SORTIE = true }
local DEFERRED_MACROS = { MAC_PATROL_RADAR = true, MAC_ARM_RESUPPLY = true }

local KNOWN_PRECONDITIONS = {
    controlState = "string", activeSource = "string", fsmState = "string_or_list",
    allowedAirframes = "list", disallowedAirframes = "list",
    sensorOk = "boolean", gpsValid = "boolean", maxHdop = "number",
    requireTap = "boolean", requireAsa = "boolean", requireGimbal = "boolean",
    minFuel = "number", channelBound = "boolean", atcCleared = "boolean", zone3Available = "boolean",
    geofenceMarginM = "number", minAlt = "number", maxAlt = "number", maxSpeed = "number",
}

local function shallow_copy(src)
    local out = {}
    if type(src) == "table" then
        for k, v in pairs(src) do out[k] = v end
    end
    return out
end

local function deep_copy(val)
    if type(val) ~= "table" then return val end
    local out = {}
    for k, v in pairs(val) do
        out[k] = deep_copy(v)
    end
    return out
end

local function list_contains(list, val)
    if type(list) ~= "table" or val == nil then return false end
    for _, item in ipairs(list) do
        if item == val then return true end
    end
    return false
end

local function merge_decorators(baseList, extraList)
    local merged = {}
    for _, d in ipairs(baseList or {}) do table.insert(merged, deep_copy(d)) end
    for _, d in ipairs(extraList or {}) do table.insert(merged, deep_copy(d)) end
    return #merged > 0 and merged or nil
end

local function make_step(baseCp, idx, action, params, defaultDecorators, carryPreconditions)
    local idPrefix = tostring(baseCp.checkpointId or "CP")
    return {
        checkpointId = idPrefix .. "_" .. tostring(idx),
        action = action,
        params = deep_copy(params or {}),
        preconditions = carryPreconditions and deep_copy(baseCp.preconditions) or nil,
        decorators = merge_decorators(defaultDecorators, baseCp.decorators),
        hooks = idx == 1 and deep_copy(baseCp.hooks) or nil,
        complete = nil,
    }
end

function action_registry.is_action_supported(id)
    return ACTIVE_LIFECYCLES[id] ~= nil
end

function action_registry.is_action_deferred(id)
    return DEFERRED_ACTIONS[id] == true
end

function action_registry.is_legacy_action(id)
    return LEGACY_ACTIONS[id] == true
end

function action_registry.is_decorator_supported(id)
    return ACTIVE_DECORATORS[id] == true
end

function action_registry.is_decorator_deferred(id)
    return DEFERRED_DECORATORS[id] == true
end

function action_registry.is_macro_supported(id)
    return ACTIVE_MACROS[id] == true
end

function action_registry.is_macro_deferred(id)
    return DEFERRED_MACROS[id] == true
end

--- Return canonical 5-stage lifecycle descriptor for an active ACT_* ID, or nil.
function action_registry.resolve_lifecycle(id)
    local spec = ACTIVE_LIFECYCLES[id]
    if not spec then return nil end
    return {
        actionId = id,
        group = spec.group,
        preconditions = true,
        entry = true,
        execution = true,
        complete = spec.complete,
        abort = spec.abort,
    }
end

--- Validate an action ID using Zero-Fallback: active passes, deferred returns DEFERRED_ACTION_UNSUPPORTED, legacy/unknown returns SCHEMA_INVALID.
function action_registry.validate_action_id(id)
    if type(id) ~= "string" or id == "" then
        return false, "SCHEMA_INVALID"
    end
    if ACTIVE_LIFECYCLES[id] then return true, nil end
    if DEFERRED_ACTIONS[id] then return false, "DEFERRED_ACTION_UNSUPPORTED" end
    return false, "SCHEMA_INVALID"
end

--- Validate one decorator descriptor table against active/deferred registries.
function action_registry.check_decorator(dec)
    if type(dec) ~= "table" or type(dec.decoratorId) ~= "string" then
        return false, "SCHEMA_INVALID"
    end
    if ACTIVE_DECORATORS[dec.decoratorId] then return true, nil end
    if DEFERRED_DECORATORS[dec.decoratorId] then return false, "DEFERRED_DECORATOR_UNSUPPORTED" end
    return false, "SCHEMA_INVALID"
end

local function expand_recon_orbit(cp)
    local p = type(cp.params) == "table" and cp.params or {}
    local radius = tonumber(p.radius) or 40
    local poiPos = p.poiPos or p.targetPos
    return {
        make_step(cp, 1, "ACT_NAV_GOTO_WP", { targetPos = p.targetPos, targetAlt = p.targetAlt, tangentEntryOffsetM = radius }, nil, true),
        make_step(cp, 2, "ACT_PAY_SET_ROI", { poiPos = poiPos }, nil, false),
        make_step(cp, 3, "ACT_PAT_LOITER_TIME", { targetPos = p.targetPos, targetAlt = p.targetAlt, radius = radius, durationSec = p.durationSec or 60 }, { { decoratorId = "DEC_SMOOTH_TRAJ" } }, false),
        make_step(cp, 4, "ACT_PAY_CLEAR_ROI", {}, nil, false),
        make_step(cp, 5, "ACT_FS_RTL_HOME", { targetAlt = p.targetAlt }, { { decoratorId = "DEC_ENERGY_ECO" } }, false),
        make_step(cp, 6, "ACT_TKL_LAND_PREC", { facilityId = p.facilityId, targetPos = p.targetPos }, nil, false),
    }
end

local function expand_ship_recovery(cp, airframeType)
    local p = type(cp.params) == "table" and cp.params or {}
    local retryDec = { { decoratorId = "DEC_RETRY_N", overrideParams = { maxAttempts = 3 } } }
    local steps = {
        make_step(cp, 1, "ACT_MOB_RV_TRACK", { facilityId = p.facilityId, targetPos = p.targetPos }, nil, true),
    }
    if airframeType == "WINGED_VTOL" then
        table.insert(steps, make_step(cp, #steps + 1, "ACT_TKL_TRANS_FW2MC", {}, nil, false))
    end
    table.insert(steps, make_step(cp, #steps + 1, "ACT_MOB_DECK_SYNC", { facilityId = p.facilityId, targetPos = p.targetPos }, nil, false))
    table.insert(steps, make_step(cp, #steps + 1, "ACT_TKL_LAND_PREC", { facilityId = p.facilityId, targetPos = p.targetPos }, retryDec, false))
    table.insert(steps, make_step(cp, #steps + 1, "ACT_SYS_DISARM", {}, nil, false))
    return steps
end

local function expand_cargo_sortie(cp)
    local p = type(cp.params) == "table" and cp.params or {}
    return {
        make_step(cp, 1, "ACT_TKL_TAKEOFF_VERT", { facilityId = p.facilityId, targetAlt = p.targetAlt }, nil, true),
        make_step(cp, 2, "ACT_NAV_GOTO_WP", { targetPos = p.targetPos, targetAlt = p.targetAlt }, nil, false),
        make_step(cp, 3, "ACT_PAY_BUS_CMD", { channelOffset = p.channelOffset, command = p.command, payload = p.payload, awaitAck = p.awaitAck }, { { decoratorId = "DEC_HUMAN_AUTH" } }, false),
        make_step(cp, 4, "ACT_FS_RTL_HOME", { targetAlt = p.targetAlt }, nil, false),
        make_step(cp, 5, "ACT_TKL_LAND_PREC", { facilityId = p.facilityId, targetPos = p.targetPos }, nil, false),
    }
end

local MACRO_EXPANDERS = {
    MAC_RECON_ORBIT = expand_recon_orbit,
    MAC_SHIP_RECOVERY = expand_ship_recovery,
    MAC_CARGO_SORTIE = expand_cargo_sortie,
}

--- Expand active MAC_* macro checkpoints into ordered ACT_* primitives; reject deferred MAC_* cleanly.
function action_registry.expand_macros(checkpoints, airframeType)
    if type(checkpoints) ~= "table" then return nil, "SCHEMA_INVALID" end
    local out = {}
    for _, cp in ipairs(checkpoints) do
        local act = type(cp) == "table" and cp.action or nil
        if DEFERRED_MACROS[act] then
            return nil, "DEFERRED_MACRO_UNSUPPORTED"
        end
        local fn = MACRO_EXPANDERS[act]
        if fn then
            for _, step in ipairs(fn(cp, airframeType)) do
                table.insert(out, step)
            end
        else
            table.insert(out, cp)
        end
    end
    return out, nil
end

local function validate_precondition_schema(pre)
    for k, v in pairs(pre) do
        local kind = KNOWN_PRECONDITIONS[k]
        if not kind then return false, "SCHEMA_INVALID" end
        if kind == "number" and type(v) ~= "number" then return false, "SCHEMA_INVALID" end
        if kind == "boolean" and type(v) ~= "boolean" then return false, "SCHEMA_INVALID" end
        if kind == "string" and type(v) ~= "string" then return false, "SCHEMA_INVALID" end
        if kind == "list" and type(v) ~= "table" then return false, "SCHEMA_INVALID" end
        if kind == "string_or_list" and type(v) ~= "string" and type(v) ~= "table" then
            return false, "SCHEMA_INVALID"
        end
    end
    if type(pre.minAlt) == "number" and type(pre.maxAlt) == "number" and pre.minAlt > pre.maxAlt then
        return false, "SCHEMA_INVALID"
    end
    return true, nil
end

--- Check compile-time static preconditions (schema keys and airframe compatibility).
function action_registry.check_static_preconditions(cp, cfg)
    local pre = type(cp) == "table" and cp.preconditions or nil
    if pre == nil then return true, nil end
    if type(pre) ~= "table" then return false, "SCHEMA_INVALID" end
    local ok, err = validate_precondition_schema(pre)
    if not ok then return false, err end

    local airframe = type(cfg) == "table" and type(cfg.system) == "table" and cfg.system.airframeType or nil
    if pre.disallowedAirframes and airframe and list_contains(pre.disallowedAirframes, airframe) then
        return false, "SCHEMA_INVALID"
    end
    if pre.allowedAirframes and airframe and not list_contains(pre.allowedAirframes, airframe) then
        return false, "SCHEMA_INVALID"
    end
    return true, nil
end

local function check_gps_ok(mfd, nav)
    local navValid = (type(nav) == "table" and nav.navValid == true)
        or (type(mfd.navigation) == "table" and mfd.navigation.navValid == true)
    local stale = (type(nav) == "table" and nav.gpsStale == true)
        or (type(mfd.navigation) == "table" and mfd.navigation.gpsTimedOut == true)
    return navValid and not stale
end

local function eval_single_precondition(k, expected, ctx)
    local mfd = type(ctx.mfd) == "table" and ctx.mfd or {}
    local nav = type(ctx.nav) == "table" and ctx.nav or {}
    local dyn = type(mfd.dynamics) == "table" and mfd.dynamics or {}
    local actH = type(mfd.actuatorHealth) == "table" and mfd.actuatorHealth or {}
    local senH = type(mfd.sensorHealth) == "table" and mfd.sensorHealth or {}
    local hdop = nav.hdop or (type(mfd.navigation) == "table" and mfd.navigation.hdop)
    local alt = dyn.altitudeY or ctx.altitudeY
    local spd = dyn.groundSpeed or ctx.groundSpeed
    local fuel = mfd.fuel or ctx.fuel

    local checks = {
        controlState = function() return mfd.controlState == expected end,
        activeSource = function() return mfd.activeSource == expected end,
        fsmState = function()
            return type(expected) == "table" and list_contains(expected, mfd.fsmState) or (mfd.fsmState == expected)
        end,
        allowedAirframes = function() return true end,
        disallowedAirframes = function() return true end,
        sensorOk = function() return (not expected) or (mfd.sensorOk == true) end,
        gpsValid = function() return (not expected) or check_gps_ok(mfd, nav) end,
        maxHdop = function() return type(hdop) == "number" and hdop <= expected end,
        requireTap = function() return (not expected) or (actH.tap == true) end,
        requireAsa = function() return (not expected) or (actH.asa == true) end,
        requireGimbal = function() return (not expected) or (senH.gimbal == true) end,
        minFuel = function() return type(fuel) == "number" and fuel >= expected end,
        channelBound = function() return (not expected) or (ctx.channelBound == true) end,
        atcCleared = function() return (not expected) or (ctx.atcCleared == true) end,
        zone3Available = function() return (not expected) or (ctx.zone3Available == true) end,
        geofenceMarginM = function() return type(ctx.geofenceMarginM) == "number" and ctx.geofenceMarginM >= expected end,
        minAlt = function() return type(alt) == "number" and alt >= expected end,
        maxAlt = function() return type(alt) == "number" and alt <= expected end,
        maxSpeed = function() return (type(spd) ~= "number") or spd <= expected end,
    }
    local fn = checks[k]
    return fn and fn() or false
end

--- Evaluate dynamic 4-category preconditions against live runtime telemetry/context.
function action_registry.check_dynamic_preconditions(cp, ctx)
    local pre = type(cp) == "table" and cp.preconditions or nil
    if pre == nil then return true, nil, nil end
    if type(pre) ~= "table" then return false, "SCHEMA_INVALID", "preconditions must be table" end
    local okSchema, errSchema = validate_precondition_schema(pre)
    if not okSchema then return false, errSchema, "invalid precondition schema" end

    local runtimeCtx = type(ctx) == "table" and ctx or {}
    for k, v in pairs(pre) do
        if not eval_single_precondition(k, v, runtimeCtx) then
            return false, "PRECONDITION_FAILED", k .. " precondition failed"
        end
    end
    return true, nil, nil
end

action_registry.ACTIVE_LIFECYCLES = ACTIVE_LIFECYCLES
action_registry.DEFERRED_ACTIONS = DEFERRED_ACTIONS
action_registry.LEGACY_ACTIONS = LEGACY_ACTIONS
action_registry.ACTIVE_DECORATORS = ACTIVE_DECORATORS
action_registry.DEFERRED_DECORATORS = DEFERRED_DECORATORS
action_registry.ACTIVE_MACROS = ACTIVE_MACROS
action_registry.DEFERRED_MACROS = DEFERRED_MACROS
action_registry.shallow_copy = shallow_copy

return action_registry
