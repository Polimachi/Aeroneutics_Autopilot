-- src/3_planning/amm/modules/mission_engine.lua
-- AMM Mission Engine Schema Layer: 13-Action Checkpoint Taxonomy, Defaults Inheritance & Validation

local mission_engine = {}

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

return mission_engine
