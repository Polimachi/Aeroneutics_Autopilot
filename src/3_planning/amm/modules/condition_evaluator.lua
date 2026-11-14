-- src/3_planning/amm/modules/condition_evaluator.lua
-- AMM 12-Type Complete/Abort Condition Evaluator & Default Completion Resolver

local action_registry = require("action_registry")

local condition_evaluator = {}

condition_evaluator.CONDITION_TYPES = {
    PROXIMITY_2D = true,
    PROXIMITY_3D = true,
    ALTITUDE_REACHED = true,
    DURATION_SEC = true,
    TIMEOUT_SEC = true,
    FUEL_LEVEL_BELOW = true,
    FACILITY_TOUCHDOWN = true,
    PAYLOAD_RESP_MATCH = true,
    REDSTONE_INPUT_HIGH = true,
    CROSS_TRACK_ERROR = true,
    ARM_DOCKED = true,
    ARM_RELEASED = true,
    SYS_ARMED = true,
    IMMEDIATE = true,
}

local ARM_TOUCHDOWN_STATES = {
    APPROACH_LAND = true,
    TAKEOFF = true,
    CRUISE = true,
    LOITER = true,
    POI_HOLD = true,
}

local function is_finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function resolve_target_xz(cond, ctx)
    if type(cond.targetPos) == "table" and is_finite(cond.targetPos.x) and is_finite(cond.targetPos.z) then
        return cond.targetPos.x, cond.targetPos.z
    end
    if type(ctx.target) == "table" and is_finite(ctx.target.x) and is_finite(ctx.target.z) then
        return ctx.target.x, ctx.target.z
    end
    local params = ctx.checkpoint and ctx.checkpoint.params
    local cp_pos = params and (params.targetPos or params.endPos)
    if type(cp_pos) == "table" and is_finite(cp_pos.x) and is_finite(cp_pos.z) then
        return cp_pos.x, cp_pos.z
    end
    return nil, nil
end

local function resolve_target_y(cond, ctx)
    if is_finite(cond.targetAlt) then return cond.targetAlt end
    if type(cond.targetPos) == "table" and is_finite(cond.targetPos.y) then return cond.targetPos.y end
    if type(ctx.target) == "table" and is_finite(ctx.target.y) then return ctx.target.y end
    local cp_alt = ctx.checkpoint and ctx.checkpoint.params and ctx.checkpoint.params.targetAlt
    if is_finite(cp_alt) then return cp_alt end
    return nil
end

local function resolve_current_pos(ctx)
    local pos = ctx.mfd and ctx.mfd.navigation and ctx.mfd.navigation.currentPos
    if type(pos) == "table" and is_finite(pos.x) and is_finite(pos.z) then
        return pos
    end
    return nil
end

local function eval_proximity_2d(cond, ctx, defaults)
    local cur = resolve_current_pos(ctx)
    local tx, tz = resolve_target_xz(cond, ctx)
    if not cur or not tx then return false end
    local cp_rad = ctx.checkpoint and ctx.checkpoint.params and ctx.checkpoint.params.acceptanceRadius
    local tol = cond.toleranceM or cp_rad or (defaults and defaults.acceptanceRadius) or 15.0
    if not is_finite(tol) or tol < 0 then return false end
    local dx, dz = tx - cur.x, tz - cur.z
    return math.sqrt(dx * dx + dz * dz) <= tol
end

local function eval_proximity_3d(cond, ctx)
    local cur = resolve_current_pos(ctx)
    local cy = ctx.mfd and ctx.mfd.dynamics and ctx.mfd.dynamics.altitudeY
    local tx, tz = resolve_target_xz(cond, ctx)
    local ty = resolve_target_y(cond, ctx)
    if not cur or not is_finite(cy) or not tx or not is_finite(ty) then return false end
    local cp_rad = ctx.checkpoint and ctx.checkpoint.params and ctx.checkpoint.params.acceptanceRadius
    local tol = cond.toleranceM or cp_rad or 5.0
    if not is_finite(tol) or tol < 0 then return false end
    local dx, dy, dz = tx - cur.x, ty - cy, tz - cur.z
    return math.sqrt(dx * dx + dy * dy + dz * dz) <= tol
end

local function eval_altitude_reached(cond, ctx)
    if not ctx.mfd then return false end
    if cond.allowFsmCruise == true and ctx.mfd.fsmState == "CRUISE" then
        return true
    end
    local cy = ctx.mfd.dynamics and ctx.mfd.dynamics.altitudeY
    local ty = resolve_target_y(cond, ctx)
    local tol = cond.toleranceM or 5.0
    if not is_finite(cy) or not is_finite(ty) or not is_finite(tol) or tol < 0 then
        return false
    end
    return math.abs(ty - cy) <= tol
end

local function eval_duration_sec(cond, ctx)
    if not is_finite(ctx.enteredAtMs) or not is_finite(ctx.nowMs) then return false end
    local dur = cond.durationSec or 0
    if not is_finite(dur) or dur < 0 then return false end
    return ((ctx.nowMs - ctx.enteredAtMs) / 1000.0) >= dur
end

local function eval_timeout_sec(cond, ctx)
    if not is_finite(ctx.enteredAtMs) or not is_finite(ctx.nowMs) then return false end
    local t_sec = cond.timeout
    if not is_finite(t_sec) or t_sec < 0 then return false end
    return ((ctx.nowMs - ctx.enteredAtMs) / 1000.0) >= t_sec
end

local function eval_fuel_below(cond, ctx)
    local fuel = ctx.mfd and ctx.mfd.fuel
    if not is_finite(fuel) or not is_finite(cond.threshold) then return false end
    return fuel <= cond.threshold
end

local function eval_facility_touchdown(_cond, ctx)
    if not ctx.mfd or ctx.mfd.fsmState ~= "DISARMED" then return false end
    return ctx.touchdownArmed ~= false
end

local function eval_payload_resp_match(cond, ctx)
    local ack = ctx.payloadAck
    if type(ack) ~= "table" then return false end
    local active_id = cond.checkpointId or (ctx.checkpoint and ctx.checkpoint.checkpointId)
    if active_id ~= nil and ack.checkpointId ~= active_id then
        return false
    end
    if cond.command ~= nil and ack.command ~= cond.command then
        return false
    end
    return ack.status == (cond.expectedStatus or "OK")
end

local function eval_redstone_high(cond, ctx)
    local rs = ctx.redstone or _G.redstone
    local colors_api = ctx.colors or _G.colors
    if type(rs) ~= "table" or type(cond.side) ~= "string" then return false end
    if cond.color ~= nil then
        local mask = (type(cond.color) == "number") and cond.color or (colors_api and colors_api[cond.color])
        if not is_finite(mask) then return false end
        if type(rs.testBundledInput) == "function" then
            return rs.testBundledInput(cond.side, mask) == true
        end
        if type(rs.getBundledInput) == "function" and bit32 then
            return bit32.band(rs.getBundledInput(cond.side) or 0, mask) ~= 0
        end
        return false
    end
    local analog = (type(rs.getAnalogInput) == "function" and rs.getAnalogInput(cond.side)) or 0
    local digital = (type(rs.getInput) == "function" and rs.getInput(cond.side)) and 15 or 0
    local min_lvl = is_finite(cond.minLevel) and cond.minLevel or 1
    return math.max(analog, digital) >= min_lvl
end

local function eval_cross_track_error(cond, ctx)
    local cte = ctx.mfd and ctx.mfd.navigation and ctx.mfd.navigation.crossTrackError
    if not is_finite(cte) or not is_finite(cond.maxDevM) or cond.maxDevM < 0 then
        return false
    end
    return math.abs(cte) >= cond.maxDevM
end

local function eval_arm_state(field, cond, ctx)
    if type(ctx.armState) ~= "table" or ctx.armState[field] ~= true then
        return false
    end
    if cond.facilityId ~= nil and ctx.armState.facilityId ~= cond.facilityId then
        return false
    end
    return true
end

local function eval_sys_armed(_cond, ctx)
    local mfd = ctx.mfd
    if type(mfd) ~= "table" then return false end
    return mfd.controlState == "IDLE_ARMED"
        or mfd.fsmState == "IDLE_ARMED"
        or mfd.fsmState == "TAKEOFF"
        or mfd.fsmState == "CRUISE"
end

local EVALUATORS = {
    PROXIMITY_2D = eval_proximity_2d,
    PROXIMITY_3D = eval_proximity_3d,
    ALTITUDE_REACHED = eval_altitude_reached,
    DURATION_SEC = eval_duration_sec,
    TIMEOUT_SEC = eval_timeout_sec,
    FUEL_LEVEL_BELOW = eval_fuel_below,
    FACILITY_TOUCHDOWN = eval_facility_touchdown,
    PAYLOAD_RESP_MATCH = eval_payload_resp_match,
    REDSTONE_INPUT_HIGH = eval_redstone_high,
    CROSS_TRACK_ERROR = eval_cross_track_error,
    ARM_DOCKED = function(cond, ctx) return eval_arm_state("docked", cond, ctx) end,
    ARM_RELEASED = function(cond, ctx) return eval_arm_state("released", cond, ctx) end,
    SYS_ARMED = eval_sys_armed,
    IMMEDIATE = function() return true end,
}

function condition_evaluator.should_arm_touchdown(fsm_state)
    return ARM_TOUCHDOWN_STATES[fsm_state] == true
end

local function make_prox2d(cp, p, def)
    return { logic = "ALL", conditions = { { type = "PROXIMITY_2D", toleranceM = p.acceptanceRadius or def.acceptanceRadius or 20.0, settleTicks = 0 } } }
end

local function make_prox3d(cp, p)
    return { logic = "ALL", conditions = { { type = "PROXIMITY_3D", toleranceM = p.acceptanceRadius or 5.0, settleTicks = 4 } } }
end

local function make_alt_reached(cp, p, def)
    local allow = (cp.action == "ACT_TKL_TAKEOFF_VERT" or cp.action == "ACT_MOB_MOVING_TKOFF")
    return { logic = "ANY", conditions = { { type = "ALTITUDE_REACHED", toleranceM = 5.0, targetAlt = p.targetAlt or def.targetAlt, allowFsmCruise = allow, settleTicks = 4 } } }
end

local function make_touchdown(_cp, p)
    return { logic = "ALL", conditions = { { type = "FACILITY_TOUCHDOWN", facilityId = p.facilityId } } }
end

local function make_hold_or_dur(_cp, p)
    if is_finite(p.durationSec) then
        return { logic = "ALL", conditions = { { type = "DURATION_SEC", durationSec = p.durationSec } } }
    end
    return { logic = "ALL", conditions = {} }
end

local function make_payload(cp, p)
    if p.waitForAck == false or p.awaitAck == false then
        return { logic = "ALL", conditions = { { type = "DURATION_SEC", durationSec = 0 } } }
    end
    return {
        logic = "ALL",
        conditions = { { type = "PAYLOAD_RESP_MATCH", expectedStatus = p.expectedStatus or "OK", command = p.command, checkpointId = cp.checkpointId } },
    }
end

local function make_redstone(_cp, p)
    if p.mode == "EMIT" then
        return { logic = "ALL", conditions = { { type = "DURATION_SEC", durationSec = (p.durationMs or 0) / 1000.0 } } }
    end
    return { logic = "ALL", conditions = { { type = "REDSTONE_INPUT_HIGH", side = p.side, color = p.color, minLevel = p.minLevel or 1 } } }
end

local DEFAULT_RESOLVERS = {
    ACT_NAV_SPLINE_WP = make_prox2d, ACT_FS_RTL_HOME = make_prox2d, ACT_FS_GOTO_RALLY = make_prox2d,
    ACT_NAV_GOTO_WP = make_prox3d, ACT_NAV_CORRIDOR = make_prox3d, ACT_MOB_RV_TRACK = make_prox3d,
    ACT_TKL_TAKEOFF_VERT = make_alt_reached, ACT_MOB_MOVING_TKOFF = make_alt_reached,
    ACT_TKL_ABORT_LAND = make_alt_reached, ACT_NAV_CHANGE_ALT = make_alt_reached, ACT_PAT_LOITER_ALT = make_alt_reached,
    ACT_TKL_LAND_PREC = make_touchdown, ACT_TKL_LAND_NORM = make_touchdown, ACT_FS_EMERG_LAND = make_touchdown,
    ACT_PAT_LOITER_TIME = make_hold_or_dur, ACT_PAT_POI_HOLD = make_hold_or_dur,
    ACT_PAT_HOLD_POS = make_hold_or_dur, ACT_COM_ATC_HOLD = make_hold_or_dur,
    ACT_PAT_LOITER_TURNS = function(_cp, p) return { logic = "ALL", conditions = { { type = "DURATION_SEC", durationSec = p.durationSec or 30 } } } end,
    ACT_PAY_BUS_CMD = make_payload, ACT_PAY_REDSTONE = make_redstone,
    ACT_SYS_ARM = function() return { logic = "ANY", conditions = { { type = "SYS_ARMED" } } } end,
    ACT_SYS_LOAD = function() return { logic = "ALL", conditions = {} } end,
    ACT_SYS_PREFLIGHT = function() return { logic = "ALL", conditions = {} } end,
    ACT_FS_HOVER_HOLD = function() return { logic = "ALL", conditions = {} } end,
}

function condition_evaluator.resolve_default_complete(cp, defaults)
    if type(cp) ~= "table" or type(cp.action) ~= "string" then
        return nil, "INVALID_CHECKPOINT"
    end
    if action_registry.is_action_deferred(cp.action) then
        return nil, "DEFERRED_ACTION_UNSUPPORTED"
    end
    if action_registry.is_legacy_action(cp.action) then
        return nil, "SCHEMA_INVALID"
    end
    if not action_registry.is_action_supported(cp.action) then
        return nil, "UNKNOWN_ACTION"
    end
    local fn = DEFAULT_RESOLVERS[cp.action]
    if fn then
        return fn(cp, cp.params or {}, defaults or {}), nil
    end
    local dur = (cp.params and cp.params.durationSec) or 0
    return { logic = "ALL", conditions = { { type = "DURATION_SEC", durationSec = dur } } }, nil
end

function condition_evaluator.evaluate_condition(cond, ctx, defaults)
    if type(cond) ~= "table" or type(cond.type) ~= "string" then
        return false, { error = "INVALID_CONDITION" }
    end
    local fn = EVALUATORS[cond.type]
    if not fn then
        return false, { type = cond.type, error = "UNKNOWN_CONDITION_TYPE" }
    end
    local eval_ctx = ctx or {}
    if cond.allowFsmCruise == true and eval_ctx.mfd and eval_ctx.mfd.fsmState == "CRUISE" then
        return true, { type = cond.type, met = true }
    end
    local met = fn(cond, eval_ctx, defaults) == true
    if is_finite(cond.settleTicks) and cond.settleTicks > 1 and type(eval_ctx.checkpoint) == "table" and type(eval_ctx.checkpoint.settleState) == "table" then
        local st = eval_ctx.checkpoint.settleState
        st[cond.type] = met and ((st[cond.type] or 0) + 1) or 0
        met = met and (st[cond.type] >= cond.settleTicks)
    end
    return met, { type = cond.type, met = met }
end

function condition_evaluator.evaluate_group(group, ctx, default_logic, defaults)
    if type(group) ~= "table" or type(group.conditions) ~= "table" or #group.conditions == 0 then
        return false, {}
    end
    local logic = group.logic or default_logic or "ALL"
    local results = {}
    local any_met, all_met = false, true
    for i, cond in ipairs(group.conditions) do
        local met, detail = condition_evaluator.evaluate_condition(cond, ctx, defaults)
        results[i] = detail
        if met then any_met = true else all_met = false end
    end
    if logic == "ANY" then
        return any_met, results
    end
    return all_met, results
end

function condition_evaluator.format_progress(cp, ctx, defaults)
    if type(cp) ~= "table" then return "NONE" end
    if action_registry.is_action_deferred(cp.action) then return "DEFERRED" end
    local grp = cp.completeWhen
    if not grp then grp = condition_evaluator.resolve_default_complete(cp, defaults) end
    local conds = grp and grp.conditions
    if type(conds) ~= "table" or #conds == 0 then
        return "HOLD/MANUAL"
    end
    local c = conds[1]
    local logic = grp.logic or "ALL"
    local s = c.type
    if c.type == "DURATION_SEC" then
        local elapsed = math.max(0, math.floor((((ctx and ctx.nowMs) or 0) - ((ctx and ctx.enteredAtMs) or 0)) / 1000))
        s = string.format("DUR %d/%ds (%s)", elapsed, math.floor(c.durationSec or 0), logic)
    elseif c.type == "PROXIMITY_2D" then
        s = string.format("PROX2D <=%dm", math.floor(c.toleranceM or 15))
    elseif c.type == "PROXIMITY_3D" then
        s = string.format("PROX3D <=%dm", math.floor(c.toleranceM or 5))
    elseif c.type == "ALTITUDE_REACHED" then
        s = string.format("ALT +/-%dm", math.floor(c.toleranceM or 5))
    elseif c.type == "FACILITY_TOUCHDOWN" then
        s = "TOUCHDOWN"
    elseif c.type == "PAYLOAD_RESP_MATCH" then
        s = "WAIT_ACK"
    elseif c.type == "REDSTONE_INPUT_HIGH" then
        s = "WAIT_RS_IN"
    elseif c.type == "TIMEOUT_SEC" then
        s = string.format("TIMEOUT %ds", math.floor(c.timeout or 0))
    end
    return string.sub(s, 1, 25)
end

function condition_evaluator.evaluate_checkpoint(cp, ctx, defaults)
    if type(cp) ~= "table" then
        return { aborted = false, completed = false, error = "INVALID_CHECKPOINT" }
    end
    if action_registry.is_action_deferred(cp.action) then
        return { aborted = false, completed = false, error = "DEFERRED_ACTION_UNSUPPORTED" }
    end
    local eval_ctx = {}
    if type(ctx) == "table" then
        for k, v in pairs(ctx) do eval_ctx[k] = v end
    end
    if eval_ctx.checkpoint == nil then eval_ctx.checkpoint = cp end

    local aborted, abort_res = condition_evaluator.evaluate_group(cp.abortWhen, eval_ctx, "ANY", defaults)
    if aborted then
        return { aborted = true, completed = false, abort_results = abort_res, complete_results = {} }
    end

    local completed, comp_res = false, {}
    if cp.completeWhen ~= nil then
        completed, comp_res = condition_evaluator.evaluate_group(cp.completeWhen, eval_ctx, "ALL", defaults)
    else
        local def_grp, err = condition_evaluator.resolve_default_complete(cp, defaults)
        if not def_grp then
            return { aborted = false, completed = false, error = err }
        end
        completed, comp_res = condition_evaluator.evaluate_group(def_grp, eval_ctx, "ALL", defaults)
    end
    return {
        aborted = false,
        completed = completed,
        abort_results = abort_res,
        complete_results = comp_res,
        summary = condition_evaluator.format_progress(cp, eval_ctx, defaults),
    }
end

return condition_evaluator
