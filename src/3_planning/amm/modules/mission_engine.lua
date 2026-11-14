-- src/3_planning/amm/modules/mission_engine.lua
-- AMM v2.0.0 Mission Engine: 3-Tier Action Primitives, Macros, Decorators & Sequencer FSM

local action_registry = require("action_registry")
local chattering_guard = require("chattering_guard")
local condition_evaluator = require("condition_evaluator")
local hook_runner = require("hook_runner")

local mission_engine = {}
mission_engine.__index = mission_engine

mission_engine.DEFERRED_ERROR = "DEFERRED_ACTION_UNSUPPORTED"
mission_engine.ACTIVE_ACTIONS = action_registry.ACTIVE_LIFECYCLES
mission_engine.DEFERRED_ACTIONS = action_registry.DEFERRED_ACTIONS

local VALID_SIDES = { top = true, bottom = true, left = true, right = true, front = true, back = true }
local VALID_EXEC_MODES = { SINGLE = true, REPEAT = true, LOOP = true }
local VALID_FALLBACKS = { SKIP_NEXT = true, RTH = true, HOVER_HOLD = true, LOITER = true }

local function is_finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function is_finite_int(n)
    return is_finite(n) and math.floor(n) == n
end

local function is_pos_xz(pos)
    return type(pos) == "table" and is_finite(pos.x) and is_finite(pos.z)
end

local function get_time_ms(now_ms)
    return (type(now_ms) == "number" and now_ms) or ((os.epoch and os.epoch("utc")) or (os.time() * 1000)) or 0
end

local function extract_target_pos(p)
    if type(p) ~= "table" then return nil end
    if is_pos_xz(p.targetPos) then return p.targetPos end
    if is_finite(p.x) and is_finite(p.z) then
        p.targetPos = { x = p.x, z = p.z }
        return p.targetPos
    end
    return nil
end

local function inherit_flight_defaults(p, defaults, opts, default_radius)
    local def = defaults or {}
    local o = opts or {}
    if p.targetAlt == nil then p.targetAlt = def.targetAlt or o.defaultAlt end
    if p.cruiseSpeed == nil then p.cruiseSpeed = def.cruiseSpeed or o.defaultSpeed end
    if p.acceptanceRadius == nil then
        p.acceptanceRadius = default_radius or def.acceptanceRadius or o.arrivalRadius or 20.0
    end
    if p.headingMode == nil and def.headingMode ~= nil then
        p.headingMode = def.headingMode
    end
end

local function is_zone3_spec(p, base_channel)
    if p.channelOffset ~= nil then
        return is_finite_int(p.channelOffset) and p.channelOffset >= 20 and p.channelOffset <= 29
    end
    local ch = (p.targetChannel ~= nil) and p.targetChannel or p.channel
    if not is_finite_int(ch) then return false end
    if is_finite_int(base_channel) then
        return ch >= base_channel + 20 and ch <= base_channel + 29
    end
    return ch >= 10000 and (ch % 40) >= 20 and (ch % 40) <= 29
end

local function validate_fly_over(p, defaults, opts)
    if not extract_target_pos(p) then return false, "INVALID_TARGET_POS" end
    inherit_flight_defaults(p, defaults, opts)
    if p.acceptanceRadius ~= nil and (not is_finite(p.acceptanceRadius) or p.acceptanceRadius <= 0) then
        return false, "INVALID_ACCEPTANCE_RADIUS"
    end
    return true
end

local function validate_fly_to(p, defaults, opts)
    if not extract_target_pos(p) then return false, "INVALID_TARGET_POS" end
    inherit_flight_defaults(p, defaults, opts, p.acceptanceRadius or 5.0)
    if not is_finite(p.acceptanceRadius) or p.acceptanceRadius <= 0 then
        return false, "INVALID_ACCEPTANCE_RADIUS"
    end
    return true
end

local function validate_corridor(p, defaults, opts)
    if not is_pos_xz(p.startPos) or not is_pos_xz(p.endPos) then
        return false, "INVALID_CORRIDOR_BOUNDS"
    end
    if p.targetPos == nil then p.targetPos = p.endPos end
    inherit_flight_defaults(p, defaults, opts, p.acceptanceRadius or 5.0)
    return true
end

local function validate_orbit(p, defaults, opts)
    if not extract_target_pos(p) then return false, "INVALID_TARGET_POS" end
    inherit_flight_defaults(p, defaults, opts)
    p.radius = (p.radius ~= nil) and p.radius or 30.0
    if not is_finite(p.radius) or p.radius < 5.0 then
        return false, "INVALID_ORBIT_RADIUS"
    end
    p.direction = p.direction or "CW"
    if p.direction ~= "CW" and p.direction ~= "CCW" then
        return false, "INVALID_ORBIT_DIRECTION"
    end
    return true
end

local function validate_poi_hold(p, defaults, opts)
    if (p.targetPos ~= nil or p.x ~= nil or p.z ~= nil) and not extract_target_pos(p) then
        return false, "INVALID_TARGET_POS"
    end
    if p.poiPos == nil then return false, "MISSING_POI_POS" end
    if not is_pos_xz(p.poiPos) or (p.poiPos.y ~= nil and not is_finite(p.poiPos.y)) then
        return false, "INVALID_POI_POS"
    end
    local explicit_hdg = p.headingMode
    inherit_flight_defaults(p, defaults, opts)
    p.headingMode = explicit_hdg or "POI"
    return true
end

local function validate_takeoff(p, defaults, opts)
    if (p.targetPos ~= nil or p.x ~= nil or p.z ~= nil) and not extract_target_pos(p) then
        return false, "INVALID_TARGET_POS"
    end
    inherit_flight_defaults(p, defaults, opts)
    if p.targetAlt ~= nil and not is_finite(p.targetAlt) then return false, "INVALID_TARGET_ALT" end
    if p.facilityId ~= nil and (type(p.facilityId) ~= "string" or p.facilityId == "") then
        return false, "INVALID_FACILITY_ID"
    end
    return true
end

local function validate_land(p, defaults, opts)
    local has_fac = type(p.facilityId) == "string" and p.facilityId ~= ""
    local has_pos = extract_target_pos(p) ~= nil
    if not has_fac and not has_pos then return false, "INVALID_LAND_PARAMS" end
    if p.targetPos ~= nil and not is_pos_xz(p.targetPos) then return false, "INVALID_TARGET_POS" end
    inherit_flight_defaults(p, defaults, opts)
    return true
end

local function validate_payload_action(p, _defaults, opts)
    if not is_zone3_spec(p, opts and opts.baseChannel) then return false, "INVALID_ZONE3_CHANNEL" end
    if type(p.command) ~= "string" or p.command == "" then return false, "MISSING_PAYLOAD_COMMAND" end
    if p.waitForAck == nil then p.waitForAck = (p.awaitAck ~= false) end
    if p.expectedStatus == nil then p.expectedStatus = "OK" end
    if p.commandPayload == nil then p.commandPayload = p.payload or {} end
    return true
end

local function validate_redstone_action(p)
    if p.mode ~= "EMIT" and p.mode ~= "WAIT_INPUT" then return false, "INVALID_REDSTONE_MODE" end
    if not VALID_SIDES[p.side] then return false, "INVALID_REDSTONE_SIDE" end
    p.durationMs = (p.durationMs ~= nil) and p.durationMs or 0
    if not is_finite(p.durationMs) or p.durationMs < 0 then return false, "INVALID_REDSTONE_DURATION" end
    if p.mode == "WAIT_INPUT" and p.minLevel == nil then p.minLevel = 1 end
    return true
end

local function validate_optional_pos(p, defaults, opts)
    if (p.targetPos ~= nil or p.x ~= nil or p.z ~= nil) and not extract_target_pos(p) then
        return false, "INVALID_TARGET_POS"
    end
    inherit_flight_defaults(p, defaults, opts)
    return true
end

local ACTION_VALIDATORS = {
    ACT_NAV_SPLINE_WP = validate_fly_over,
    ACT_NAV_GOTO_WP = validate_fly_to,
    ACT_NAV_CORRIDOR = validate_corridor,
    ACT_PAT_LOITER_TIME = validate_orbit,
    ACT_PAT_LOITER_TURNS = validate_orbit,
    ACT_PAT_LOITER_ALT = validate_orbit,
    ACT_PAT_POI_HOLD = validate_poi_hold,
    ACT_TKL_TAKEOFF_VERT = validate_takeoff,
    ACT_MOB_MOVING_TKOFF = validate_takeoff,
    ACT_TKL_LAND_PREC = validate_land,
    ACT_TKL_LAND_NORM = validate_land,
    ACT_PAY_BUS_CMD = validate_payload_action,
    ACT_PAY_REDSTONE = validate_redstone_action,
}

function mission_engine.is_action_supported(action)
    return action_registry.is_action_supported(action)
end

function mission_engine.is_action_deferred(action)
    return action_registry.is_action_deferred(action)
end

function mission_engine.normalize_checkpoint(raw_cp, defaults, index, opts)
    if type(raw_cp) ~= "table" or type(raw_cp.action) ~= "string" then
        return nil, "INVALID_CHECKPOINT"
    end
    if action_registry.is_action_deferred(raw_cp.action) then
        return nil, mission_engine.DEFERRED_ERROR
    end
    if action_registry.is_legacy_action(raw_cp.action) then
        return nil, "SCHEMA_INVALID"
    end
    if not action_registry.is_action_supported(raw_cp.action) then
        return nil, "UNKNOWN_ACTION"
    end
    local params = action_registry.shallow_copy(raw_cp.params)
    local validator = ACTION_VALIDATORS[raw_cp.action] or validate_optional_pos
    local ok, err = validator(params, defaults, opts)
    if not ok then return nil, err end
    local ok_pre, err_pre = action_registry.check_static_preconditions(raw_cp, opts)
    if not ok_pre then return nil, err_pre end
    return {
        checkpointId = raw_cp.checkpointId or string.format("CP_%02d", index or 1),
        action = raw_cp.action,
        params = params,
        preconditions = raw_cp.preconditions,
        decorators = raw_cp.decorators,
        onEnter = raw_cp.onEnter,
        onExit = raw_cp.onExit,
        onAbort = raw_cp.onAbort,
        completeWhen = raw_cp.completeWhen,
        abortWhen = raw_cp.abortWhen,
        fallbackPolicy = raw_cp.fallbackPolicy,
        settleState = {},
    }, nil
end

function mission_engine.validate_checkpoint(cp, opts)
    local norm, err = mission_engine.normalize_checkpoint(cp, nil, 1, opts)
    return norm ~= nil, err
end

function mission_engine.validate_mission(mission_tbl, opts)
    if type(mission_tbl) ~= "table" or mission_tbl.items ~= nil or type(mission_tbl.checkpoints) ~= "table" or #mission_tbl.checkpoints == 0 then
        local code = (type(mission_tbl) == "table" and mission_tbl.items ~= nil) and "SCHEMA_INVALID" or "INVALID_MISSION"
        return false, { index = 0, error = code }
    end
    local airframe = opts and opts.system and opts.system.airframeType
    local expanded, merr = action_registry.expand_macros(mission_tbl.checkpoints, airframe)
    if not expanded then
        local ecode = (merr == "DEFERRED_MACRO_UNSUPPORTED") and mission_engine.DEFERRED_ERROR or merr
        return false, { index = 1, error = ecode }
    end
    local normalized_cps = {}
    for i, raw_cp in ipairs(expanded) do
        local norm, err = mission_engine.normalize_checkpoint(raw_cp, mission_tbl.defaults, i, opts)
        if not norm then
            return false, { index = i, checkpointId = type(raw_cp) == "table" and raw_cp.checkpointId or nil, error = err }
        end
        normalized_cps[i] = norm
    end
    return true, {
        missionId = mission_tbl.missionId or "MISSION_01",
        version = mission_tbl.version or "2.0.0",
        description = mission_tbl.description,
        executionMode = mission_tbl.executionMode or "SINGLE",
        fallbackPolicy = mission_tbl.fallbackPolicy or "RTH",
        defaults = action_registry.shallow_copy(mission_tbl.defaults),
        checkpoints = normalized_cps,
    }
end

local function validate_conditions_list(cond_block)
    if type(cond_block) ~= "table" then return false, "INVALID_COND_BLOCK" end
    if cond_block.logic ~= nil and cond_block.logic ~= "ANY" and cond_block.logic ~= "ALL" then
        return false, "INVALID_LOGIC"
    end
    if type(cond_block.conditions) ~= "table" then return false, "INVALID_CONDITIONS" end
    for _, cond in ipairs(cond_block.conditions) do
        if type(cond) ~= "table" or not condition_evaluator.CONDITION_TYPES[cond.type] then
            return false, "INVALID_CONDITION_TYPE " .. tostring(type(cond) == "table" and cond.type or cond)
        end
    end
    return true
end

local function validate_hooks_list(hooks)
    if type(hooks) ~= "table" then return false, "INVALID_HOOK_BLOCK" end
    for _, h in ipairs(hooks) do
        if type(h) ~= "table" or not hook_runner.VALID_HOOK_TYPES[h.type] then
            return false, "INVALID_HOOK_TYPE " .. tostring(type(h) == "table" and h.type or h)
        end
    end
    return true
end

local function validate_decorators_list(decs, i)
    if decs == nil then return true end
    if type(decs) ~= "table" then return false, string.format("CP#%d: INVALID_DECORATORS", i) end
    for _, d in ipairs(decs) do
        local ok, derr = action_registry.check_decorator(d)
        if not ok and derr ~= "DEFERRED_DECORATOR_UNSUPPORTED" then
            return false, string.format("CP#%d: %s", i, tostring(derr))
        end
    end
    return true
end

local function validate_cp_schema(cp, i, opts)
    if type(cp) ~= "table" or type(cp.action) ~= "string" then
        return false, string.format("CP#%d: INVALID_CHECKPOINT", i)
    end
    if action_registry.is_legacy_action(cp.action) then
        return false, string.format("CP#%d: DEPRECATED_ACTION '%s'", i, tostring(cp.action))
    end
    local known = action_registry.is_action_supported(cp.action) or action_registry.is_action_deferred(cp.action)
        or action_registry.is_macro_supported(cp.action) or action_registry.is_macro_deferred(cp.action)
    if not known then
        return false, string.format("CP#%d: UNKNOWN_ACTION '%s'", i, tostring(cp.action))
    end
    local ok_pre, err_pre = action_registry.check_static_preconditions(cp, opts)
    if not ok_pre then return false, string.format("CP#%d: PRECONDITION %s", i, tostring(err_pre)) end
    local ok_dec, err_dec = validate_decorators_list(cp.decorators, i)
    if not ok_dec then return false, err_dec end
    if action_registry.is_action_supported(cp.action) then
        local validator = ACTION_VALIDATORS[cp.action] or validate_optional_pos
        local ok_p, err_p = validator(action_registry.shallow_copy(cp.params), nil, opts)
        if not ok_p then return false, string.format("CP#%d: %s", i, tostring(err_p)) end
    end
    if cp.completeWhen ~= nil then
        local ok_c, err_c = validate_conditions_list(cp.completeWhen)
        if not ok_c then return false, string.format("CP#%d: completeWhen %s", i, err_c) end
    end
    if cp.abortWhen ~= nil then
        local ok_a, err_a = validate_conditions_list(cp.abortWhen)
        if not ok_a then return false, string.format("CP#%d: abortWhen %s", i, err_a) end
    end
    for _, hkey in ipairs({ "onEnter", "onExit", "onAbort" }) do
        if cp[hkey] ~= nil then
            local ok_h, err_h = validate_hooks_list(cp[hkey])
            if not ok_h then return false, string.format("CP#%d: %s %s", i, hkey, err_h) end
        end
    end
    return true
end

function mission_engine.validate_mission_table(tbl, opts)
    if type(tbl) ~= "table" then return false, "SCHEMA_INVALID", "INVALID_TABLE" end
    if tbl.items ~= nil then return false, "SCHEMA_INVALID", "LEGACY_ITEMS_UNSUPPORTED" end
    if type(tbl.checkpoints) ~= "table" or #tbl.checkpoints == 0 then
        return false, "SCHEMA_INVALID", "EMPTY_CHECKPOINTS"
    end
    if tbl.executionMode ~= nil and not VALID_EXEC_MODES[tbl.executionMode] then
        return false, "SCHEMA_INVALID", "INVALID_EXECUTION_MODE"
    end
    if tbl.fallbackPolicy ~= nil and not VALID_FALLBACKS[tbl.fallbackPolicy] then
        return false, "SCHEMA_INVALID", "INVALID_FALLBACK_POLICY"
    end
    for i, cp in ipairs(tbl.checkpoints) do
        local ok_cp, err_cp = validate_cp_schema(cp, i, opts)
        if not ok_cp then return false, "SCHEMA_INVALID", err_cp end
    end
    return true, nil, nil
end

function mission_engine.resolve_path(spec, fs_api)
    if type(spec) ~= "string" or spec == "" or string.find(spec, "%.%.") then
        return nil, "INVALID_PATH"
    end
    local fs_obj = fs_api or fs
    if not fs_obj then return nil, "FS_UNAVAILABLE" end
    local candidates = {}
    local function add_cand(c)
        candidates[#candidates + 1] = c
        if not string.match(c, "%.json$") then candidates[#candidates + 1] = c .. ".json" end
    end
    add_cand(spec)
    if not string.match(spec, "^/") then
        add_cand("missions/" .. spec)
        add_cand("/disk/" .. spec)
        add_cand("/disk/missions/" .. spec)
    end
    for _, cand in ipairs(candidates) do
        if fs_obj.exists(cand) and not (fs_obj.isDir and fs_obj.isDir(cand)) then return cand, nil end
    end
    return nil, "FILE_NOT_FOUND"
end

function mission_engine.list_mission_files(fs_api)
    local fs_obj = fs_api or fs
    local results, seen = {}, {}
    if not fs_obj then return results end
    local dirs = {
        { path = "missions", prefix = "" },
        { path = "/disk", prefix = "/disk/" },
        { path = "/disk/missions", prefix = "/disk/missions/" },
    }
    for _, d in ipairs(dirs) do
        if fs_obj.exists(d.path) and (not fs_obj.isDir or fs_obj.isDir(d.path)) then
            for _, item in ipairs(fs_obj.list(d.path) or {}) do
                local full = d.path .. "/" .. item
                if string.match(item, "%.json$") and not (fs_obj.isDir and fs_obj.isDir(full)) then
                    local entry = d.prefix .. string.sub(item, 1, -6)
                    if not seen[entry] then seen[entry] = true; results[#results + 1] = entry end
                end
            end
        end
    end
    table.sort(results)
    return results
end

local function find_deferred_in_table(data)
    for i, cp in ipairs(data.checkpoints or {}) do
        if type(cp) == "table" then
            if action_registry.is_action_deferred(cp.action) or action_registry.is_macro_deferred(cp.action) then
                return string.format("CP#%d: %s", i, tostring(cp.action))
            end
            for _, d in ipairs(cp.decorators or {}) do
                if type(d) == "table" and action_registry.is_decorator_deferred(d.decoratorId) then
                    return string.format("CP#%d: %s", i, tostring(d.decoratorId))
                end
            end
        end
    end
    return nil
end

function mission_engine.preflight_file(spec, opts, fs_api)
    local resolved, err_path = mission_engine.resolve_path(spec, fs_api)
    if not resolved then return nil, err_path, nil end
    local fs_obj = fs_api or fs
    local h = fs_obj.open(resolved, "r")
    if not h then return nil, "FS_OPEN_ERROR", nil end
    local raw = h.readAll()
    h.close()
    local data = textutils.unserializeJSON(raw)
    if type(data) ~= "table" then return nil, "PARSE_ERROR", "INVALID_JSON" end
    local ok_v, err_v, det_v = mission_engine.validate_mission_table(data, opts)
    if not ok_v then return nil, err_v, det_v end
    if not (opts and opts.allowDeferred) then
        local def_det = find_deferred_in_table(data)
        if def_det then return nil, mission_engine.DEFERRED_ERROR, def_det end
    end
    return data, nil, nil
end

function mission_engine.new(opts)
    local o = opts or {}
    local cfg = o.config or {}
    local base_ch = cfg.baseChannel or (o.net and o.net.baseChannel) or 10000
    local runner = o.hook_runner or hook_runner.new({
        net = o.net, redstone = o.redstone, colors = o.colors, on_notify = o.on_notify,
    })
    return setmetatable({
        net = o.net, hook_runner = runner, config = cfg, baseChannel = base_ch,
        redstone = o.redstone, colors = o.colors, on_notify = o.on_notify,
        guard = o.guard or chattering_guard.init(cfg),
        sentinel = o.sentinel,
        fac = o.fac,
        precondCtx = o.precondCtx,
        geofenceMarginM = o.geofenceMarginM,
        authority = "PILOT_PRIMARY",
        defaults = {
            cruiseSpeed = cfg.defaultSpeed or 18.0,
            targetAlt = cfg.defaultAlt or 150.0,
            acceptanceRadius = cfg.arrivalRadius or 15.0,
            headingMode = "AUTO",
        },
        missionId = "SORTIE",
        version = "2.0.0",
        executionMode = "SINGLE",
        fallbackPolicy = "RTH",
        checkpoints = {},
        active_index = 1,
        state = "IDLE",
        enteredAtMs = 0,
        lastFsmState = "DISARMED",
        lastMfd = nil,
        touchdownArmed = false,
        waitingHumanAuth = false,
        emconActive = false,
        activeRoi = nil,
        currentGoal = nil,
        fallbackGoal = nil,
    }, mission_engine)
end

function mission_engine:load_table(tbl)
    local ok_t, err_t, det_t = mission_engine.validate_mission_table(tbl, self.config)
    if not ok_t then return false, err_t, det_t end
    local ok_m, res = mission_engine.validate_mission(tbl, {
        baseChannel = self.baseChannel,
        defaultAlt = self.defaults.targetAlt,
        defaultSpeed = self.defaults.cruiseSpeed,
        arrivalRadius = self.defaults.acceptanceRadius,
        system = self.config and self.config.system,
        safety = self.config and self.config.safety,
    })
    if not ok_m then
        local code = (res and res.error) or "SCHEMA_INVALID"
        if code ~= mission_engine.DEFERRED_ERROR then code = "SCHEMA_INVALID" end
        return false, code, res
    end
    self.hook_runner:cleanup()
    self.missionId = res.missionId
    self.version = "2.0.0"
    self.executionMode = (res.executionMode == "LOOP") and "REPEAT" or res.executionMode
    self.fallbackPolicy = res.fallbackPolicy
    if type(res.defaults) == "table" then
        for k, v in pairs(res.defaults) do self.defaults[k] = v end
    end
    self.checkpoints = res.checkpoints
    self.active_index = 1
    self.state = "IDLE"
    self.waitingHumanAuth = false
    self.emconActive = false
    self.activeRoi = nil
    self.currentGoal = nil
    self.fallbackGoal = nil
    return true, nil
end

function mission_engine:load(filepath)
    local resolved, err_path = mission_engine.resolve_path(filepath)
    if not resolved then return false, err_path end
    local h = fs.open(resolved, "r")
    if not h then return false, "FS_OPEN_ERROR" end
    local raw = h.readAll()
    h.close()
    local data = textutils.unserializeJSON(raw)
    if type(data) ~= "table" then return false, "SCHEMA_INVALID", "INVALID_JSON" end
    return self:load_table(data)
end

function mission_engine:save(filepath)
    if type(filepath) ~= "string" or filepath == "" then return false, "INVALID_FILEPATH" end
    local dir = fs.getDir(filepath)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = fs.open(filepath, "w")
    if not h then return false, "FS_OPEN_ERROR" end
    h.write(textutils.serializeJSON({
        version = "2.0.0",
        missionId = self.missionId or "MISSION_01",
        executionMode = self.executionMode or "SINGLE",
        fallbackPolicy = self.fallbackPolicy or "RTH",
        defaults = self.defaults or {},
        checkpoints = self.checkpoints or {},
    }))
    h.close()
    return true, nil
end

function mission_engine:get_active() return self.checkpoints[self.active_index] end
function mission_engine:count() return #self.checkpoints end

local function set_cruise_goal(self, cp)
    local p = cp.params or {}
    local tgt = p.targetPos or p.endPos
    local spd = p.cruiseSpeed or self.defaults.cruiseSpeed
    local alt = p.targetAlt or self.defaults.targetAlt
    self.currentGoal = {
        flightMode = "CRUISE",
        arm = true,
        flightActive = true,
        targetPos = tgt,
        targetAlt = alt,
        targetSpeed = spd,
        poiPos = self.activeRoi,
        headingMode = p.headingMode or "AUTO",
        fixedHeadingDeg = p.targetHeading or p.headingDeg,
        acceptanceRadius = p.acceptanceRadius,
    }
    return true
end

local function set_takeoff_goal(self, cp)
    local p = cp.params or {}
    local alt = p.targetAlt or self.defaults.targetAlt
    local fac = p.facilityId or p.designatedFacilityId
    self.currentGoal = { flightMode = "TAKEOFF", arm = true, flightActive = true, targetAlt = alt, facilityId = fac }
    return true
end

local function set_loiter_goal(self, cp)
    local p = cp.params or {}
    local alt = p.targetAlt or self.defaults.targetAlt
    local spd = p.cruiseSpeed or self.defaults.cruiseSpeed
    self.currentGoal = {
        flightMode = "LOITER", arm = true, flightActive = true,
        targetPos = p.targetPos, targetAlt = alt, targetSpeed = spd,
        poiPos = self.activeRoi,
        loiterRadius = p.radius, loiterDirection = p.direction,
    }
    return true
end

local function set_poi_goal(self, cp)
    local p = cp.params or {}
    local alt = p.targetAlt or self.defaults.targetAlt
    local spd = p.cruiseSpeed or self.defaults.cruiseSpeed
    self.currentGoal = {
        flightMode = "POI_HOLD", arm = true, flightActive = true,
        targetPos = p.targetPos, poiPos = p.poiPos or self.activeRoi, targetAlt = alt, targetSpeed = spd,
    }
    return true
end

local function set_land_goal(self, cp)
    local p = cp.params or {}
    local fac = p.facilityId or p.designatedFacilityId
    self.currentGoal = {
        flightMode = "LANDING", arm = true, flightActive = true,
        facilityId = fac, targetPos = p.targetPos, targetAlt = p.targetAlt,
    }
    return true
end

local function dispatch_failsafe_cmd(self, mode)
    self.currentGoal = { flightMode = mode, arm = true, flightActive = true }
    return true
end

local FCP_DISPATCHERS = {
    ACT_SYS_LOAD = function(self)
        self.currentGoal = { flightMode = "IDLE_ARMED", arm = false, flightActive = false }
        return true
    end,
    ACT_SYS_PREFLIGHT = function(self)
        self.currentGoal = { flightMode = "IDLE_ARMED", arm = false, flightActive = false }
        return true
    end,
    ACT_SYS_SET_HOME = function(self, cp)
        local p = cp.params or {}
        local nav_pos = self.lastMfd and self.lastMfd.navigation and self.lastMfd.navigation.currentPos
        self.homePos = p.targetPos or nav_pos
        return true
    end,
    ACT_SYS_ARM = function(self)
        self.currentGoal = { flightMode = "IDLE_ARMED", arm = true, flightActive = false }
        return true
    end,
    ACT_SYS_DISARM = function(self)
        self.currentGoal = { flightMode = "IDLE_ARMED", arm = false, flightActive = false }
        return true
    end,
    ACT_SYS_TERMINATE = function(self)
        self.currentGoal = { flightMode = "IDLE_ARMED", arm = false, flightActive = false }
        if self.net and self.net.send_emergency_override then
            self.net:send_emergency_override("E_STOP", "MISSION_TERMINATE", "ESTOP_CONFIRM_KEY", "AMM")
        end
        return true
    end,
    ACT_TKL_TAKEOFF_VERT = set_takeoff_goal,
    ACT_MOB_MOVING_TKOFF = set_takeoff_goal,
    ACT_TKL_ABORT_LAND = set_takeoff_goal,
    ACT_TKL_TRANS_MC2FW = function(self, cp)
        local p = cp.params or {}
        self.currentGoal = {
            flightMode = "CRUISE", arm = true, flightActive = true, transitionMode = "MC2FW",
            targetAlt = p.targetAlt or self.defaults.targetAlt,
            targetSpeed = p.targetSpeed or p.cruiseSpeed or self.defaults.cruiseSpeed,
        }
        return true
    end,
    ACT_TKL_TRANS_FW2MC = function(self, cp)
        local p = cp.params or {}
        self.currentGoal = {
            flightMode = "HOVER_HOLD", arm = true, flightActive = true, transitionMode = "FW2MC",
            targetAlt = p.targetAlt or self.defaults.targetAlt,
        }
        return true
    end,
    ACT_NAV_SPLINE_WP = set_cruise_goal,
    ACT_NAV_GOTO_WP = set_cruise_goal,
    ACT_NAV_CORRIDOR = set_cruise_goal,
    ACT_NAV_CHANGE_ALT = set_cruise_goal,
    ACT_NAV_CHANGE_SPD = set_cruise_goal,
    ACT_NAV_CHANGE_YAW = set_cruise_goal,
    ACT_MOB_RV_TRACK = set_cruise_goal,
    ACT_PAT_LOITER_TIME = set_loiter_goal,
    ACT_PAT_LOITER_TURNS = set_loiter_goal,
    ACT_PAT_LOITER_ALT = set_loiter_goal,
    ACT_PAT_HOLD_POS = set_loiter_goal,
    ACT_COM_ATC_HOLD = set_loiter_goal,
    ACT_PAT_POI_HOLD = set_poi_goal,
    ACT_TKL_LAND_PREC = set_land_goal,
    ACT_TKL_LAND_NORM = set_land_goal,
    ACT_MOB_DECK_SYNC = set_land_goal,
    ACT_PAY_BUS_CMD = function(self, cp, now_ms) return self.hook_runner:start_action(cp, now_ms) end,
    ACT_PAY_REDSTONE = function(self, cp, now_ms) return self.hook_runner:start_action(cp, now_ms) end,
    ACT_PAY_SET_ROI = function(self, cp, now_ms)
        local p = cp.params or {}
        self.activeRoi = p.poiPos or p.targetPos
        if self.currentGoal then self.currentGoal.poiPos = self.activeRoi end
        return self.hook_runner:start_action(cp, now_ms)
    end,
    ACT_PAY_CLEAR_ROI = function(self, cp, now_ms)
        self.activeRoi = nil
        if self.currentGoal then self.currentGoal.poiPos = nil end
        return self.hook_runner:start_action(cp, now_ms)
    end,
    ACT_FS_RTL_HOME = function(self) return dispatch_failsafe_cmd(self, "FAILSAFE_RTH") end,
    ACT_FS_GOTO_RALLY = function(self) return dispatch_failsafe_cmd(self, "FAILSAFE_RTH") end,
    ACT_FS_HOVER_HOLD = function(self) return dispatch_failsafe_cmd(self, "HOVER_HOLD") end,
    ACT_FS_FENCE_BRAKE = function(self) return dispatch_failsafe_cmd(self, "HOVER_HOLD") end,
    ACT_FS_EMERG_LAND = function(self) return dispatch_failsafe_cmd(self, "EMERGENCY_LAND") end,
}

local function build_loiter_fallback(self, cp)
    local p = cp and cp.params or {}
    local nav_pos = self.lastMfd and self.lastMfd.navigation and self.lastMfd.navigation.currentPos
    return {
        flightMode = "LOITER", arm = true, flightActive = true,
        targetPos = nav_pos or p.targetPos,
        targetAlt = p.targetAlt or (self.defaults and self.defaults.targetAlt),
    }
end

local FALLBACK_HANDLERS = {
    SKIP_NEXT = function(self, cp, now_ms)
        cp.status = "ABORTED"
        if self.active_index + 1 <= #self.checkpoints then
            self:enter_checkpoint(self.active_index + 1, now_ms)
            return "SKIPPED"
        end
        self.state = "ABORTED"
        self.fallbackGoal = { flightMode = "HOVER_HOLD", arm = true, flightActive = true }
        return "ABORTED"
    end,
    RTH = function(self, cp)
        cp.status = "ABORTED"
        self.state = "ABORTED"
        self.fallbackGoal = { flightMode = "FAILSAFE_RTH", arm = true, flightActive = true }
        return "ABORTED"
    end,
    HOVER_HOLD = function(self, cp)
        cp.status = "ABORTED"
        self.state = "ABORTED"
        self.fallbackGoal = { flightMode = "HOVER_HOLD", arm = true, flightActive = true }
        return "ABORTED"
    end,
    LOITER = function(self, cp)
        cp.status = "ABORTED"
        self.state = "ABORTED"
        self.fallbackGoal = build_loiter_fallback(self, cp)
        return "ABORTED"
    end,
}

local function find_decorator(cp, decorator_id)
    for _, d in ipairs((cp and cp.decorators) or {}) do
        if d.decoratorId == decorator_id then return d end
    end
    return nil
end

function mission_engine:apply_abort(cp, now_ms)
    local retry_dec = find_decorator(cp, "DEC_RETRY_N")
    if retry_dec then
        local ov = type(retry_dec.overrideParams) == "table" and retry_dec.overrideParams or {}
        local max_att = math.max(1, math.floor(tonumber(ov.maxAttempts) or 3))
        if (cp._attempt or 1) < max_att then
            cp._attempt = (cp._attempt or 1) + 1
            self.hook_runner:cleanup()
            self.waitingHumanAuth = false
            local ok_r = self:enter_checkpoint(self.active_index, now_ms, true)
            if ok_r then return "RETRYING" end
        end
    end
    local policy = cp.fallbackPolicy or self.fallbackPolicy or "RTH"
    self.hook_runner:cleanup()
    self.waitingHumanAuth = false
    if cp.onAbort then self.hook_runner:execute_hooks(cp.onAbort, cp, now_ms) end
    local handler = FALLBACK_HANDLERS[policy]
    if handler then return handler(self, cp, now_ms) end
    cp.status = "ABORTED"
    self.state = "ABORTED"
    self.fallbackGoal = { flightMode = "FAILSAFE_RTH", arm = true, flightActive = true }
    return "ABORTED"
end

local function inspect_decorators(cp)
    local has_human = false
    for _, d in ipairs(cp.decorators or {}) do
        local ok, derr = action_registry.check_decorator(d)
        if not ok then return false, (derr == "DEFERRED_DECORATOR_UNSUPPORTED" and mission_engine.DEFERRED_ERROR or derr), false end
        if d.decoratorId == "DEC_HUMAN_AUTH" then has_human = true end
    end
    return true, nil, has_human
end

local function apply_runtime_decorators(self, cp)
    self.emconActive = false
    if type(self.currentGoal) ~= "table" then return end
    for _, d in ipairs(cp.decorators or {}) do
        local ov = type(d.overrideParams) == "table" and d.overrideParams or {}
        if d.decoratorId == "DEC_EMCON" then
            self.currentGoal.emconActive = true
            self.emconActive = true
        elseif d.decoratorId == "DEC_ENERGY_ECO" then
            local spd = self.currentGoal.targetSpeed or self.defaults.cruiseSpeed or 18.0
            self.currentGoal.targetSpeed = (type(ov.ecoCruiseSpeed) == "number" and ov.ecoCruiseSpeed > 0) and ov.ecoCruiseSpeed or (spd * 0.75)
        elseif d.decoratorId == "DEC_SMOOTH_TRAJ" then
            self.currentGoal.constraintProfile = "STRICT_LEVEL"
            if type(ov.maxYawRateDegS) == "number" and ov.maxYawRateDegS > 0 then
                self.currentGoal.maxYawRateDegPerSec = ov.maxYawRateDegS
            end
        end
    end
end

local function build_precond_ctx(self)
    local pctx = type(self.precondCtx) == "table" and self.precondCtx or {}
    local ch_bound = pctx.channelBound
    if ch_bound == nil then
        ch_bound = (self.sentinel == nil) or (self.sentinel.status == "ACQUIRED" and not self.sentinel.locked)
    end
    local atc_ok = pctx.atcCleared
    if atc_ok == nil then
        atc_ok = (self.fac == nil) or (self.fac.atcStatus == "CLEARED")
    end
    local z3_ok = pctx.zone3Available
    if z3_ok == nil then z3_ok = true end
    local gf = pctx.geofenceMarginM
    if gf == nil then
        gf = (type(self.geofenceMarginM) == "number") and self.geofenceMarginM or 100.0
    end
    return {
        mfd = self.lastMfd,
        channelBound = ch_bound,
        atcCleared = atc_ok,
        zone3Available = z3_ok,
        geofenceMarginM = gf,
    }
end

local function dispatch_checkpoint(self, cp, t_ms)
    if cp.onEnter then self.hook_runner:execute_hooks(cp.onEnter, cp, t_ms) end
    local dispatcher = FCP_DISPATCHERS[cp.action]
    if dispatcher then dispatcher(self, cp, t_ms) end
    apply_runtime_decorators(self, cp)
end

function mission_engine:enter_checkpoint(index, now_ms, is_retry)
    local cp = self.checkpoints[index]
    if not cp then return false, "INVALID_INDEX" end
    if action_registry.is_action_deferred(cp.action) then
        self.hook_runner:cleanup(); cp.status = "ABORTED"; self.state = "ABORTED"
        return false, mission_engine.DEFERRED_ERROR
    end
    local ok_dec, err_dec, has_human = inspect_decorators(cp)
    if not ok_dec then
        self.hook_runner:cleanup(); cp.status = "ABORTED"; self.state = "ABORTED"
        return false, err_dec
    end
    local pre_ctx = build_precond_ctx(self)
    local ok_dyn, err_dyn = action_registry.check_dynamic_preconditions(cp, pre_ctx)
    if not ok_dyn then
        self:apply_abort(cp, get_time_ms(now_ms))
        return false, err_dyn
    end
    self.fallbackGoal = nil
    self.active_index = index
    self.enteredAtMs = get_time_ms(now_ms)
    cp.status = "ACTIVE"
    cp.settleState = {}
    cp._orbitState = nil
    if not is_retry then cp._attempt = 1 end
    if has_human then
        self.waitingHumanAuth = true
        self.currentGoal = build_loiter_fallback(self, cp)
        return true
    end
    self.waitingHumanAuth = false
    dispatch_checkpoint(self, cp, self.enteredAtMs)
    return true
end

function mission_engine:confirm(now_ms)
    if not self.waitingHumanAuth then return false, "NOT_WAITING_AUTH" end
    local cp = self:get_active()
    if not cp then return false, "INVALID_INDEX" end
    self.waitingHumanAuth = false
    self.enteredAtMs = get_time_ms(now_ms)
    dispatch_checkpoint(self, cp, self.enteredAtMs)
    return true, nil
end

function mission_engine:advance(now_ms)
    local cp = self:get_active()
    if cp then
        cp.status = "COMPLETED"
        if cp.onExit then self.hook_runner:execute_hooks(cp.onExit, cp, now_ms) end
    end
    self.hook_runner:clear_step_state()
    local next_idx = self.active_index + 1
    if next_idx <= #self.checkpoints then
        local ok, err = self:enter_checkpoint(next_idx, now_ms)
        if not ok then return "ABORTED", err end
        return "ADVANCED"
    end
    if self.executionMode == "REPEAT" then
        for _, c in ipairs(self.checkpoints) do
            c.status = nil
            c._attempt = nil
            c._orbitState = nil
        end
        local wrap_idx = 1
        while wrap_idx < #self.checkpoints and chattering_guard.should_skip_on_repeat(self.checkpoints[wrap_idx].action) do
            wrap_idx = wrap_idx + 1
        end
        local ok, err = self:enter_checkpoint(wrap_idx, now_ms)
        if not ok then return "ABORTED", err end
        return "LOOPED"
    end
    self.state = "COMPLETED"
    return "COMPLETED"
end

function mission_engine:evaluate_active(now_ms)
    if self.state ~= "EN_ROUTE" then return self.state end
    if self.waitingHumanAuth then return "WAITING_AUTH" end
    local cp = self:get_active()
    if not cp then return "IDLE" end
    local t_dec = find_decorator(cp, "DEC_TIMEOUT_GUARD")
    if t_dec and type(now_ms) == "number" then
        local ov = type(t_dec.overrideParams) == "table" and t_dec.overrideParams or {}
        local lim = ov.maxDurationSec or ov.timeoutSec or ov.timeout
        if type(lim) == "number" and lim > 0 and (now_ms - self.enteredAtMs) >= (lim * 1000) then
            return self:apply_abort(cp, now_ms)
        end
    end
    local ctx = {
        mfd = self.lastMfd, enteredAtMs = self.enteredAtMs, nowMs = now_ms,
        touchdownArmed = self.touchdownArmed, payloadAck = self.hook_runner:get_last_payload_ack(),
        redstone = self.redstone, colors = self.colors, checkpoint = cp,
    }
    local res = condition_evaluator.evaluate_checkpoint(cp, ctx, self.defaults)
    if res.error == mission_engine.DEFERRED_ERROR then
        self.hook_runner:cleanup(); cp.status = "ABORTED"; self.state = "ABORTED"
        return "ABORTED", mission_engine.DEFERRED_ERROR
    end
    self.lastConditionSummary = res.summary or "NONE"
    if res.aborted then return self:apply_abort(cp, now_ms) end
    if res.completed then return self:advance(now_ms) end
    return "ACTIVE", self.lastConditionSummary
end

function mission_engine:step_telemetry(mfd_payload, now_ms)
    local t_ms = get_time_ms(now_ms)
    self.lastMfd = mfd_payload
    if mfd_payload and condition_evaluator.should_arm_touchdown(mfd_payload.fsmState) then
        self.touchdownArmed = true
    end
    if self.state ~= "EN_ROUTE" then return self.state end
    return self:evaluate_active(t_ms)
end

function mission_engine:tick(now_ms)
    local t_ms = get_time_ms(now_ms)
    self.hook_runner:tick(t_ms)
    if self.state ~= "EN_ROUTE" then return self.state end
    return self:evaluate_active(t_ms)
end

function mission_engine:on_payload_ack(packet, channel, now_ms)
    local t_ms = get_time_ms(now_ms)
    local ok, res = self.hook_runner:on_payload_ack(packet, channel)
    if not ok then return false, res end
    if self.state == "EN_ROUTE" then return true, self:evaluate_active(t_ms) end
    return true, res
end

function mission_engine:start(execution_mode, now_ms)
    if #self.checkpoints == 0 then return false, "NO_CHECKPOINTS" end
    if execution_mode then
        self.executionMode = (execution_mode == "LOOP") and "REPEAT" or execution_mode
    end
    for _, cp in ipairs(self.checkpoints) do
        cp.status = nil
        cp._attempt = nil
        cp._orbitState = nil
    end
    self.touchdownArmed = false
    self.waitingHumanAuth = false
    self.activeRoi = nil
    self.currentGoal = nil
    self.fallbackGoal = nil
    self.state = "EN_ROUTE"
    local ok, err = self:enter_checkpoint(1, now_ms)
    if not ok then return false, err end
    return true, nil
end

function mission_engine:stop(now_ms)
    local prev_state, cp = self.state, self:get_active()
    self.hook_runner:cleanup()
    self.waitingHumanAuth = false
    if cp and cp.onAbort then self.hook_runner:execute_hooks(cp.onAbort, cp, now_ms) end
    self.state = "ABORTED"
    local is_disarmed = self.lastMfd and self.lastMfd.fsmState == "DISARMED"
    if (prev_state == "EN_ROUTE" or prev_state == "SUSPENDED") and not is_disarmed then
        self.fallbackGoal = build_loiter_fallback(self, cp)
    else
        self.fallbackGoal = { flightMode = "IDLE_ARMED", arm = false, flightActive = false }
    end
    return true
end

function mission_engine:pause()
    if self.state ~= "EN_ROUTE" then return false end
    self.hook_runner:cleanup()
    self.state = "SUSPENDED"
    self.fallbackGoal = build_loiter_fallback(self, self:get_active())
    return true
end

function mission_engine:resume(now_ms)
    if self.state ~= "SUSPENDED" then return false end
    self.fallbackGoal = nil
    self.state = "EN_ROUTE"
    self:enter_checkpoint(self.active_index, now_ms)
    return true
end

function mission_engine:skip_next(now_ms)
    local cp = self:get_active()
    if cp then
        cp.status = "SKIPPED"
        if cp.onExit then self.hook_runner:execute_hooks(cp.onExit, cp, now_ms) end
    end
    self.hook_runner:cleanup()
    self.waitingHumanAuth = false
    local next_idx = self.active_index + 1
    if next_idx <= #self.checkpoints then
        local ok, err = self:enter_checkpoint(next_idx, now_ms)
        if not ok then return false, err end
        return true, "ADVANCED"
    end
    self.state = "COMPLETED"
    return true, "COMPLETED"
end

function mission_engine:goto_index(index, now_ms)
    if type(index) ~= "number" or index < 1 or index > #self.checkpoints then return false, "INVALID_INDEX" end
    self.hook_runner:cleanup()
    self.waitingHumanAuth = false
    self.state = "EN_ROUTE"
    local ok, err = self:enter_checkpoint(index, now_ms)
    if not ok then return false, err end
    return true
end

function mission_engine:get_trajectory_goal() return self.currentGoal end
function mission_engine:get_fallback_goal() return self.fallbackGoal end

return mission_engine
