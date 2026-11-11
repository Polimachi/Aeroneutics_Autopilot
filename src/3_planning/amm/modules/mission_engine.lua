-- src/3_planning/amm/modules/mission_engine.lua
-- AMM Mission Engine: 13-Action Checkpoint Taxonomy, Polymorphic Loader & Sequencer FSM

local condition_evaluator = require("condition_evaluator")
local hook_runner = require("hook_runner")

local mission_engine = {}
mission_engine.__index = mission_engine

mission_engine.DEFERRED_ERROR = "DEFERRED_ACTION_UNSUPPORTED"

mission_engine.ACTIVE_ACTIONS = {
    FLY_OVER = true,
    FLY_TO = true,
    ORBIT = true,
    PATROL = true,
    POI_HOLD = true,
    TAKEOFF_LAUNCHPAD = true,
    LAND_LAUNCHPAD = true,
    PAYLOAD_ACTION = true,
    REDSTONE_ACTION = true,
}

mission_engine.DEFERRED_ACTIONS = {
    TAKEOFF_RUNWAY = true,
    LAND_RUNWAY = true,
    DOCK_ARM = true,
    UNDOCK_ARM = true,
}

mission_engine.ACTION_TAXONOMY = {
    FLY_OVER = { domain = "NAV", status = "ACTIVE" },
    FLY_TO = { domain = "NAV", status = "ACTIVE" },
    ORBIT = { domain = "NAV", status = "ACTIVE" },
    PATROL = { domain = "NAV", status = "ACTIVE" },
    POI_HOLD = { domain = "NAV", status = "ACTIVE" },
    TAKEOFF_LAUNCHPAD = { domain = "INFRA", status = "ACTIVE" },
    LAND_LAUNCHPAD = { domain = "INFRA", status = "ACTIVE" },
    TAKEOFF_RUNWAY = { domain = "INFRA", status = "DEFERRED" },
    LAND_RUNWAY = { domain = "INFRA", status = "DEFERRED" },
    DOCK_ARM = { domain = "INFRA", status = "DEFERRED" },
    UNDOCK_ARM = { domain = "INFRA", status = "DEFERRED" },
    PAYLOAD_ACTION = { domain = "SPECIAL", status = "ACTIVE" },
    REDSTONE_ACTION = { domain = "SPECIAL", status = "ACTIVE" },
}

local VALID_SIDES = {
    top = true, bottom = true, left = true,
    right = true, front = true, back = true,
}

local function is_finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function is_finite_int(n)
    return is_finite(n) and math.floor(n) == n
end

local function is_pos_xz(pos)
    return type(pos) == "table" and is_finite(pos.x) and is_finite(pos.z)
end

local function shallow_copy(src)
    local out = {}
    if type(src) ~= "table" then return out end
    for k, v in pairs(src) do
        out[k] = v
    end
    return out
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
    if ch < 10000 then return false end
    local rem = ch % 40
    return rem >= 20 and rem <= 29
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

local function validate_fly_over(p, defaults, opts)
    if not is_pos_xz(p.targetPos) then return false, "INVALID_TARGET_POS" end
    inherit_flight_defaults(p, defaults, opts)
    if p.acceptanceRadius ~= nil and (not is_finite(p.acceptanceRadius) or p.acceptanceRadius <= 0) then
        return false, "INVALID_ACCEPTANCE_RADIUS"
    end
    return true
end

local function validate_fly_to(p, defaults, opts)
    if not is_pos_xz(p.targetPos) then return false, "INVALID_TARGET_POS" end
    local explicit_rad = p.acceptanceRadius
    inherit_flight_defaults(p, defaults, opts, explicit_rad or 5.0)
    if not is_finite(p.acceptanceRadius) or p.acceptanceRadius <= 0 then
        return false, "INVALID_ACCEPTANCE_RADIUS"
    end
    return true
end

local function validate_orbit(p, defaults, opts)
    if not is_pos_xz(p.targetPos) then return false, "INVALID_TARGET_POS" end
    inherit_flight_defaults(p, defaults, opts)
    p.radius = (p.radius ~= nil) and p.radius or 30.0
    if not is_finite(p.radius) or p.radius <= 0 then
        return false, "INVALID_ORBIT_RADIUS"
    end
    p.direction = p.direction or "CW"
    if p.direction ~= "CW" and p.direction ~= "CCW" then
        return false, "INVALID_ORBIT_DIRECTION"
    end
    return true
end

local function validate_patrol(p, defaults, opts)
    if type(p.waypoints) ~= "table" or #p.waypoints < 1 then
        return false, "INVALID_PATROL_WAYPOINTS"
    end
    for _, wp in ipairs(p.waypoints) do
        if not is_pos_xz(wp) then return false, "INVALID_PATROL_WAYPOINTS" end
    end
    inherit_flight_defaults(p, defaults, opts)
    p.patrolMode = p.patrolMode or "LOOP"
    if p.patrolMode ~= "LOOP" and p.patrolMode ~= "PING_PONG" then
        return false, "INVALID_PATROL_MODE"
    end
    p.cycles = (p.cycles ~= nil) and p.cycles or 1
    if not is_finite_int(p.cycles) or p.cycles < 1 then
        return false, "INVALID_PATROL_CYCLES"
    end
    return true
end

local function validate_poi_hold(p, defaults, opts)
    if not is_pos_xz(p.targetPos) then return false, "INVALID_TARGET_POS" end
    if p.poiPos == nil then return false, "MISSING_POI_POS" end
    if not is_pos_xz(p.poiPos) or (p.poiPos.y ~= nil and not is_finite(p.poiPos.y)) then
        return false, "INVALID_POI_POS"
    end
    local explicit_hdg = p.headingMode
    inherit_flight_defaults(p, defaults, opts)
    p.headingMode = explicit_hdg or "POI"
    return true
end

local function validate_takeoff_launchpad(p, defaults, opts)
    if p.targetPos ~= nil and not is_pos_xz(p.targetPos) then
        return false, "INVALID_TARGET_POS"
    end
    inherit_flight_defaults(p, defaults, opts)
    if p.targetAlt ~= nil and not is_finite(p.targetAlt) then
        return false, "INVALID_TARGET_ALT"
    end
    if p.facilityId ~= nil and (type(p.facilityId) ~= "string" or p.facilityId == "") then
        return false, "INVALID_FACILITY_ID"
    end
    return true
end

local function validate_land_launchpad(p, defaults, opts)
    local has_fac = type(p.facilityId) == "string" and p.facilityId ~= ""
    local has_pos = is_pos_xz(p.targetPos)
    if not has_fac and not has_pos then
        return false, "INVALID_LAND_PARAMS"
    end
    if p.targetPos ~= nil and not has_pos then
        return false, "INVALID_TARGET_POS"
    end
    inherit_flight_defaults(p, defaults, opts)
    return true
end

local function validate_payload_action(p, _defaults, opts)
    local base_ch = opts and opts.baseChannel
    if not is_zone3_spec(p, base_ch) then
        return false, "INVALID_ZONE3_CHANNEL"
    end
    if type(p.command) ~= "string" or p.command == "" then
        return false, "MISSING_PAYLOAD_COMMAND"
    end
    if p.waitForAck == nil then p.waitForAck = true end
    if p.expectedStatus == nil then p.expectedStatus = "OK" end
    if p.commandPayload == nil then p.commandPayload = {} end
    return true
end

local function validate_redstone_action(p)
    if p.mode ~= "EMIT" and p.mode ~= "WAIT_INPUT" then
        return false, "INVALID_REDSTONE_MODE"
    end
    if not VALID_SIDES[p.side] then
        return false, "INVALID_REDSTONE_SIDE"
    end
    p.durationMs = (p.durationMs ~= nil) and p.durationMs or 0
    if not is_finite(p.durationMs) or p.durationMs < 0 then
        return false, "INVALID_REDSTONE_DURATION"
    end
    if p.mode == "WAIT_INPUT" and p.minLevel == nil then
        p.minLevel = 1
    end
    return true
end

local ACTION_VALIDATORS = {
    FLY_OVER = validate_fly_over,
    FLY_TO = validate_fly_to,
    ORBIT = validate_orbit,
    PATROL = validate_patrol,
    POI_HOLD = validate_poi_hold,
    TAKEOFF_LAUNCHPAD = validate_takeoff_launchpad,
    LAND_LAUNCHPAD = validate_land_launchpad,
    PAYLOAD_ACTION = validate_payload_action,
    REDSTONE_ACTION = validate_redstone_action,
}

function mission_engine.is_action_supported(action)
    return mission_engine.ACTIVE_ACTIONS[action] == true
end

function mission_engine.is_action_deferred(action)
    return mission_engine.DEFERRED_ACTIONS[action] == true
end

function mission_engine.normalize_checkpoint(raw_cp, defaults, index, opts)
    if type(raw_cp) ~= "table" or type(raw_cp.action) ~= "string" then
        return nil, "INVALID_CHECKPOINT"
    end
    if mission_engine.DEFERRED_ACTIONS[raw_cp.action] then
        return nil, mission_engine.DEFERRED_ERROR
    end
    local validator = ACTION_VALIDATORS[raw_cp.action]
    if not validator then
        return nil, "UNKNOWN_ACTION"
    end
    local params = shallow_copy(raw_cp.params)
    local ok, err = validator(params, defaults, opts)
    if not ok then
        return nil, err
    end
    return {
        checkpointId = raw_cp.checkpointId or string.format("CP_%02d", index or 1),
        action = raw_cp.action,
        params = params,
        onEnter = raw_cp.onEnter,
        onExit = raw_cp.onExit,
        onAbort = raw_cp.onAbort,
        completeWhen = raw_cp.completeWhen,
        abortWhen = raw_cp.abortWhen,
        fallbackPolicy = raw_cp.fallbackPolicy,
    }, nil
end

function mission_engine.validate_checkpoint(cp, opts)
    local norm, err = mission_engine.normalize_checkpoint(cp, nil, 1, opts)
    if not norm then
        return false, err
    end
    return true, nil
end

function mission_engine.validate_mission(mission_tbl, opts)
    if type(mission_tbl) ~= "table" or type(mission_tbl.checkpoints) ~= "table" or #mission_tbl.checkpoints == 0 then
        return false, { index = 0, error = "INVALID_MISSION" }
    end
    local normalized_cps = {}
    for i, raw_cp in ipairs(mission_tbl.checkpoints) do
        local norm, err = mission_engine.normalize_checkpoint(raw_cp, mission_tbl.defaults, i, opts)
        if not norm then
            return false, {
                index = i,
                checkpointId = type(raw_cp) == "table" and raw_cp.checkpointId or nil,
                error = err,
            }
        end
        normalized_cps[i] = norm
    end
    return true, {
        missionId = mission_tbl.missionId or "MISSION_01",
        version = mission_tbl.version or "1.1.0",
        description = mission_tbl.description,
        executionMode = mission_tbl.executionMode or "SINGLE",
        fallbackPolicy = mission_tbl.fallbackPolicy or "RTH",
        defaults = shallow_copy(mission_tbl.defaults),
        checkpoints = normalized_cps,
    }
end

local function get_time_ms(now_ms)
    return (type(now_ms) == "number" and now_ms) or ((os.epoch and os.epoch("utc")) or (os.time() * 1000)) or 0
end

local function convert_legacy_items(data)
    local checkpoints = {}
    for i, item in ipairs(data.items) do
        checkpoints[#checkpoints + 1] = {
            checkpointId = string.format("CP_%02d", item.id or i),
            action = "FLY_OVER",
            params = {
                targetPos = { x = item.x, z = item.z },
                targetAlt = item.alt,
                cruiseSpeed = item.speed,
            },
        }
    end
    local last = data.items[#data.items]
    if last and type(last.facilityId) == "string" and last.facilityId ~= "" then
        checkpoints[#checkpoints + 1] = {
            checkpointId = string.format("CP_%02d", #checkpoints + 1),
            action = "LAND_LAUNCHPAD",
            params = {
                facilityId = last.facilityId,
                targetPos = { x = last.x, z = last.z },
                targetAlt = last.alt,
            },
        }
    end
    return {
        version = "1.1.0",
        missionId = data.missionId or "LEGACY_MISSION",
        executionMode = data.executionMode or "SINGLE",
        fallbackPolicy = data.fallbackPolicy or "RTH",
        defaults = data.defaults or {},
        checkpoints = checkpoints,
    }
end

function mission_engine.new(opts)
    local o = opts or {}
    local cfg = o.config or {}
    local base_ch = cfg.baseChannel or (o.net and o.net.baseChannel) or 10000
    local runner = o.hook_runner or hook_runner.new({
        net = o.net,
        redstone = o.redstone,
        colors = o.colors,
        on_notify = o.on_notify,
    })
    return setmetatable({
        net = o.net,
        hook_runner = runner,
        config = cfg,
        baseChannel = base_ch,
        redstone = o.redstone,
        colors = o.colors,
        on_notify = o.on_notify,
        authority = "PILOT_PRIMARY",
        defaults = {
            cruiseSpeed = cfg.defaultSpeed or 18.0,
            targetAlt = cfg.defaultAlt or 150.0,
            acceptanceRadius = cfg.arrivalRadius or 15.0,
            headingMode = "AUTO",
        },
        missionId = "SORTIE",
        version = "1.1.0",
        executionMode = "SINGLE",
        fallbackPolicy = "RTH",
        checkpoints = {},
        active_index = 1,
        state = "IDLE",
        enteredAtMs = 0,
        lastFsmState = "DISARMED",
        lastMfd = nil,
        touchdownArmed = false,
        patrolState = nil,
        lastConditionSummary = "NONE",
    }, mission_engine)
end

function mission_engine:load_table(data)
    if type(data) ~= "table" then return false, "INVALID_MISSION" end
    local raw = data
    if type(data.items) == "table" and type(data.checkpoints) ~= "table" then
        raw = convert_legacy_items(data)
    end
    local opts = {
        baseChannel = self.baseChannel,
        defaultAlt = self.defaults and self.defaults.targetAlt,
        defaultSpeed = self.defaults and self.defaults.cruiseSpeed,
        arrivalRadius = self.defaults and self.defaults.acceptanceRadius,
    }
    local ok, validated = mission_engine.validate_mission(raw, opts)
    if not ok then
        return false, (type(validated) == "table" and validated.error) or "INVALID_MISSION"
    end
    self.missionId = validated.missionId
    self.version = validated.version
    self.executionMode = validated.executionMode
    self.fallbackPolicy = validated.fallbackPolicy
    local defs = shallow_copy(self.defaults)
    if validated.defaults then
        for k, v in pairs(validated.defaults) do defs[k] = v end
    end
    self.defaults = defs
    self.checkpoints = validated.checkpoints
    self.active_index = 1
    self.state = "IDLE"
    self.enteredAtMs = 0
    self.patrolState = nil
    self.touchdownArmed = false
    self.lastConditionSummary = "NONE"
    return true, nil
end

function mission_engine:load(filepath)
    if not fs.exists(filepath) then return false, "FILE_NOT_FOUND" end
    local h = fs.open(filepath, "r")
    if not h then return false, "FS_OPEN_ERROR" end
    local raw = h.readAll()
    h.close()
    local data = textutils.unserializeJSON(raw)
    if type(data) ~= "table" then return false, "PARSE_ERROR" end
    return self:load_table(data)
end

function mission_engine:save(filepath)
    if type(filepath) ~= "string" or filepath == "" then return false, "INVALID_FILEPATH" end
    local dir = fs.getDir(filepath)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local h = fs.open(filepath, "w")
    if not h then return false, "FS_OPEN_ERROR" end
    local payload = {
        version = "1.1.0",
        missionId = self.missionId or "MISSION_01",
        executionMode = self.executionMode or "SINGLE",
        fallbackPolicy = self.fallbackPolicy or "RTH",
        defaults = self.defaults or {},
        checkpoints = self.checkpoints or {},
    }
    h.write(textutils.serializeJSON(payload))
    h.close()
    return true, nil
end

function mission_engine:get_active()
    return self.checkpoints[self.active_index]
end

function mission_engine:count()
    return #self.checkpoints
end

local FCP_DISPATCHERS = {
    TAKEOFF_LAUNCHPAD = function(self, cp, _now_ms)
        local p = cp.params or {}
        local fsm = (self.lastMfd and self.lastMfd.fsmState) or "DISARMED"
        if fsm == "DISARMED" and self.net then
            self.net:send_operator_cmd("ARM", "CRUISE", {}, "NONE", self.authority)
        end
        if self.net then
            self.net:send_operator_cmd("TAKEOFF", "TAKEOFF", {
                targetAlt = p.targetAlt or self.defaults.targetAlt,
                designatedFacilityId = p.facilityId or p.designatedFacilityId,
            }, "NONE", self.authority)
        end
        return true
    end,
    FLY_OVER = function(self, cp, _now_ms)
        if not self.net then return false end
        local p = cp.params or {}
        return self.net:send_operator_cmd("CRUISE", "CRUISE", {
            targetWaypoint = p.targetPos,
            targetAlt = p.targetAlt or self.defaults.targetAlt,
            cruiseSpeed = p.cruiseSpeed or self.defaults.cruiseSpeed,
        }, "NONE", self.authority)
    end,
    FLY_TO = function(self, cp, _now_ms)
        if not self.net then return false end
        local p = cp.params or {}
        return self.net:send_operator_cmd("CRUISE", "CRUISE", {
            targetWaypoint = p.targetPos,
            targetAlt = p.targetAlt or self.defaults.targetAlt,
            cruiseSpeed = p.cruiseSpeed or self.defaults.cruiseSpeed,
        }, "NONE", self.authority)
    end,
    ORBIT = function(self, cp, _now_ms)
        if not self.net then return false end
        local p = cp.params or {}
        return self.net:send_operator_cmd("LOITER", "LOITER", {
            targetWaypoint = p.targetPos,
            targetAlt = p.targetAlt or self.defaults.targetAlt,
            cruiseSpeed = p.cruiseSpeed or self.defaults.cruiseSpeed,
            loiterRadius = p.radius,
            loiterDirection = p.direction,
        }, "NONE", self.authority)
    end,
    POI_HOLD = function(self, cp, _now_ms)
        if not self.net then return false end
        local p = cp.params or {}
        return self.net:send_operator_cmd("POI_HOLD", "POI_HOLD", {
            targetWaypoint = p.targetPos,
            poiTarget = p.poiPos,
            targetAlt = p.targetAlt or self.defaults.targetAlt,
            cruiseSpeed = p.cruiseSpeed or self.defaults.cruiseSpeed,
        }, "NONE", self.authority)
    end,
    PATROL = function(self, cp, _now_ms)
        local p = cp.params or {}
        if not self.patrolState then
            self.patrolState = { subIndex = 1, dir = 1, completedCycles = 0, completed = false }
        end
        local wp = p.waypoints and p.waypoints[self.patrolState.subIndex]
        if not wp or not self.net then return false end
        return self.net:send_operator_cmd("CRUISE", "CRUISE", {
            targetWaypoint = wp,
            targetAlt = wp.alt or p.targetAlt or self.defaults.targetAlt,
            cruiseSpeed = wp.speed or p.cruiseSpeed or self.defaults.cruiseSpeed,
        }, "NONE", self.authority)
    end,
    LAND_LAUNCHPAD = function(self, cp, _now_ms)
        if not self.net then return false end
        local p = cp.params or {}
        return self.net:send_operator_cmd("LANDING", "LANDING", {
            designatedFacilityId = p.facilityId or p.designatedFacilityId,
            targetWaypoint = p.targetPos,
            targetAlt = p.targetAlt,
        }, "NONE", self.authority)
    end,
    PAYLOAD_ACTION = function(self, cp, now_ms)
        return self.hook_runner:start_action(cp, now_ms)
    end,
    REDSTONE_ACTION = function(self, cp, now_ms)
        return self.hook_runner:start_action(cp, now_ms)
    end,
}

local function step_ping_pong(state, n_wp, cycles)
    if state.dir == 1 then
        if state.subIndex >= n_wp then
            state.dir = -1
            state.subIndex = n_wp - 1
        else
            state.subIndex = state.subIndex + 1
        end
    else
        if state.subIndex <= 1 then
            state.completedCycles = state.completedCycles + 1
            if state.completedCycles >= cycles then
                state.completed = true
            else
                state.dir = 1
                state.subIndex = 2
            end
        else
            state.subIndex = state.subIndex - 1
        end
    end
end

local function step_loop(state, n_wp, cycles)
    if state.subIndex >= n_wp then
        state.completedCycles = state.completedCycles + 1
        if state.completedCycles >= cycles then
            state.completed = true
        else
            state.subIndex = 1
        end
    else
        state.subIndex = state.subIndex + 1
    end
end

local function advance_patrol_state(self, cp)
    local p = cp.params or {}
    local waypoints = p.waypoints or {}
    local n_wp = #waypoints
    local state = self.patrolState
    local cycles = p.cycles or 1

    if n_wp <= 1 then
        state.completedCycles = state.completedCycles + 1
        if state.completedCycles >= cycles then state.completed = true end
        return
    end

    if p.patrolMode == "PING_PONG" then
        step_ping_pong(state, n_wp, cycles)
    else
        step_loop(state, n_wp, cycles)
    end

    if not state.completed and self.net then
        local next_wp = waypoints[state.subIndex]
        local alt = next_wp.alt or p.targetAlt or self.defaults.targetAlt
        local spd = next_wp.speed or p.cruiseSpeed or self.defaults.cruiseSpeed
        self.net:send_operator_cmd("CRUISE", "CRUISE", {
            targetWaypoint = next_wp,
            targetAlt = alt,
            cruiseSpeed = spd,
        }, "NONE", self.authority)
    end
end

function mission_engine:update_patrol(cp, mfd_payload, t_ms)
    local nav = mfd_payload and mfd_payload.navigation
    local cur = nav and nav.currentPos
    if not cur or not self.patrolState or self.patrolState.completed then
        return nil
    end
    local p = cp.params or {}
    local waypoints = p.waypoints or {}
    local cur_wp = waypoints[self.patrolState.subIndex]
    if not cur_wp then return nil end

    local tol = cur_wp.acceptanceRadius or p.acceptanceRadius or (self.defaults and self.defaults.acceptanceRadius) or 15.0
    local dx = cur_wp.x - cur.x
    local dz = cur_wp.z - cur.z
    if (dx * dx + dz * dz) > (tol * tol) then
        return nil
    end

    local ctx = {
        mfd = mfd_payload,
        enteredAtMs = self.enteredAtMs,
        nowMs = t_ms,
        redstone = self.redstone,
        colors = self.colors,
        checkpoint = cp,
    }
    local aborted = condition_evaluator.evaluate_group(cp.abortWhen, ctx, "ANY", self.defaults)
    if aborted then
        return self:apply_abort(cp, t_ms)
    end

    advance_patrol_state(self, cp)
    return nil
end

local FALLBACK_HANDLERS = {
    SKIP_NEXT = function(self, cp, now_ms)
        cp.status = "ABORTED"
        local next_idx = self.active_index + 1
        if next_idx <= #self.checkpoints then
            self:enter_checkpoint(next_idx, now_ms)
            return "SKIPPED"
        end
        self.state = "ABORTED"
        return "ABORTED"
    end,
    RTH = function(self, cp, _now_ms)
        cp.status = "ABORTED"
        self.state = "ABORTED"
        if self.net then
            self.net:send_operator_cmd("CRUISE", "CRUISE", {}, "RTH", self.authority)
        end
        return "ABORTED"
    end,
    HOVER_HOLD = function(self, cp, _now_ms)
        cp.status = "ABORTED"
        self.state = "ABORTED"
        if self.net then
            self.net:send_operator_cmd("HOVER_HOLD", "HOVER_HOLD", {}, "HOVER_HOLD", self.authority)
        end
        return "ABORTED"
    end,
    LOITER = function(self, cp, _now_ms)
        cp.status = "ABORTED"
        self.state = "ABORTED"
        if self.net then
            self.net:send_operator_cmd("LOITER", "LOITER", {}, "NONE", self.authority)
        end
        return "ABORTED"
    end,
}

function mission_engine:apply_abort(cp, now_ms)
    local policy = cp.fallbackPolicy or self.fallbackPolicy or "RTH"
    if cp.onAbort then
        self.hook_runner:execute_hooks(cp.onAbort, cp, now_ms)
    end
    self.hook_runner:cleanup()
    local handler = FALLBACK_HANDLERS[policy]
    if handler then
        return handler(self, cp, now_ms)
    end
    cp.status = "ABORTED"
    self.state = "ABORTED"
    if self.net then
        self.net:send_operator_cmd("CRUISE", "CRUISE", {}, policy, self.authority)
    end
    return "ABORTED"
end

function mission_engine:enter_checkpoint(index, now_ms)
    local cp = self.checkpoints[index]
    if not cp then return false, "INVALID_INDEX" end
    if mission_engine.is_action_deferred(cp.action) then
        self.hook_runner:cleanup()
        cp.status = "ABORTED"
        self.state = "ABORTED"
        return false, mission_engine.DEFERRED_ERROR
    end
    self.active_index = index
    self.enteredAtMs = get_time_ms(now_ms)
    cp.status = "ACTIVE"
    if cp.action == "PATROL" then
        self.patrolState = { subIndex = 1, dir = 1, completedCycles = 0, completed = false }
    else
        self.patrolState = nil
    end
    if cp.onEnter then
        self.hook_runner:execute_hooks(cp.onEnter, cp, self.enteredAtMs)
    end
    local dispatcher = FCP_DISPATCHERS[cp.action]
    if dispatcher then
        dispatcher(self, cp, self.enteredAtMs)
    end
    return true
end

function mission_engine:advance(now_ms)
    local cp = self:get_active()
    if cp then
        cp.status = "COMPLETED"
        if cp.onExit then
            self.hook_runner:execute_hooks(cp.onExit, cp, now_ms)
        end
    end
    self.hook_runner:clear_step_state()
    local next_idx = self.active_index + 1
    if next_idx <= #self.checkpoints then
        local ok, err = self:enter_checkpoint(next_idx, now_ms)
        if not ok then
            return "ABORTED", err
        end
        return "ADVANCED"
    end
    if self.executionMode == "REPEAT" then
        for _, c in ipairs(self.checkpoints) do c.status = nil end
        local wrap_idx = 1
        if self.checkpoints[1] and self.checkpoints[1].action == "TAKEOFF_LAUNCHPAD" and #self.checkpoints >= 2 then
            wrap_idx = 2
        end
        local ok, err = self:enter_checkpoint(wrap_idx, now_ms)
        if not ok then
            return "ABORTED", err
        end
        return "LOOPED"
    end
    self.state = "COMPLETED"
    return "COMPLETED"
end

function mission_engine:evaluate_active(now_ms)
    if self.state ~= "EN_ROUTE" then
        return self.state
    end
    local cp = self:get_active()
    if not cp then return "IDLE" end
    local ctx = {
        mfd = self.lastMfd,
        enteredAtMs = self.enteredAtMs,
        nowMs = now_ms,
        touchdownArmed = self.touchdownArmed,
        payloadAck = self.hook_runner:get_last_payload_ack(),
        redstone = self.redstone,
        colors = self.colors,
        patrolCompleted = self.patrolState and self.patrolState.completed,
        checkpoint = cp,
    }
    local res = condition_evaluator.evaluate_checkpoint(cp, ctx, self.defaults)
    if res.error == mission_engine.DEFERRED_ERROR then
        self.hook_runner:cleanup()
        cp.status = "ABORTED"
        self.state = "ABORTED"
        return "ABORTED", mission_engine.DEFERRED_ERROR
    end
    self.lastConditionSummary = res.summary or "NONE"
    if res.aborted then
        return self:apply_abort(cp, now_ms)
    end
    if res.completed then
        return self:advance(now_ms)
    end
    return "ACTIVE", self.lastConditionSummary
end

function mission_engine:step_telemetry(mfd_payload, now_ms)
    local t_ms = get_time_ms(now_ms)
    self.lastMfd = mfd_payload
    if mfd_payload and condition_evaluator.should_arm_touchdown(mfd_payload.fsmState) then
        self.touchdownArmed = true
    end
    if self.state ~= "EN_ROUTE" then
        return self.state
    end
    local cp = self:get_active()
    if not cp then return "IDLE" end
    if cp.action == "PATROL" then
        local pat_st = self:update_patrol(cp, mfd_payload, t_ms)
        if pat_st then return pat_st end
    end
    return self:evaluate_active(t_ms)
end

function mission_engine:tick(now_ms)
    local t_ms = get_time_ms(now_ms)
    self.hook_runner:tick(t_ms)
    if self.state ~= "EN_ROUTE" then
        return self.state
    end
    return self:evaluate_active(t_ms)
end

function mission_engine:on_payload_ack(packet, channel, now_ms)
    local t_ms = get_time_ms(now_ms)
    local ok, res = self.hook_runner:on_payload_ack(packet, channel)
    if not ok then
        return false, res
    end
    if self.state == "EN_ROUTE" then
        local st = self:evaluate_active(t_ms)
        return true, st
    end
    return true, res
end

function mission_engine:start(execution_mode, now_ms)
    if #self.checkpoints == 0 then return false, "NO_CHECKPOINTS" end
    if execution_mode then self.executionMode = execution_mode end
    for _, cp in ipairs(self.checkpoints) do cp.status = nil end
    self.state = "EN_ROUTE"
    local ok, err = self:enter_checkpoint(1, now_ms)
    if not ok then
        return false, err
    end
    return true, nil
end

function mission_engine:stop(now_ms)
    local cp = self:get_active()
    if cp and cp.onAbort then
        self.hook_runner:execute_hooks(cp.onAbort, cp, now_ms)
    end
    self.hook_runner:cleanup()
    self.state = "ABORTED"
    if self.net then
        self.net:send_operator_cmd("LOITER", "LOITER", {}, "NONE", self.authority)
    end
    return true
end

function mission_engine:pause()
    if self.state ~= "EN_ROUTE" then return false end
    self.hook_runner:cleanup()
    self.state = "SUSPENDED"
    if self.net then
        self.net:send_operator_cmd("LOITER", "LOITER", {}, "NONE", self.authority)
    end
    return true
end

function mission_engine:resume(now_ms)
    if self.state ~= "SUSPENDED" then return false end
    self.state = "EN_ROUTE"
    self:enter_checkpoint(self.active_index, now_ms)
    return true
end

function mission_engine:skip_next(now_ms)
    local cp = self:get_active()
    if cp then
        cp.status = "SKIPPED"
        if cp.onExit then
            self.hook_runner:execute_hooks(cp.onExit, cp, now_ms)
        end
    end
    self.hook_runner:cleanup()
    local next_idx = self.active_index + 1
    if next_idx <= #self.checkpoints then
        local ok, err = self:enter_checkpoint(next_idx, now_ms)
        if not ok then
            return false, err
        end
        return true, "ADVANCED"
    end
    self.state = "COMPLETED"
    return true, "COMPLETED"
end

function mission_engine:goto_index(index, now_ms)
    if type(index) ~= "number" or index < 1 or index > #self.checkpoints then
        return false, "INVALID_INDEX"
    end
    self.hook_runner:cleanup()
    self.state = "EN_ROUTE"
    local ok, err = self:enter_checkpoint(index, now_ms)
    if not ok then
        return false, err
    end
    return true
end

return mission_engine
