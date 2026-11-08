-- src/0_development/sensors/avionics_sensors.lua
-- Standard CC:Avionics (Create: Avionics) 4-sensor API library for Create_Aeroneutics.
-- Scope: velocity_sensor, altitude_sensor, gimbal_sensor, physics_assembler only.

local M = {}

local pcall = pcall
local type = type
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local sort = table.sort
local sqrt = math.sqrt
local acos = math.acos
local deg = math.deg

M.VERSION = "1.0.0"

M.PERIPHERAL_TYPES = {
    VELOCITY = "velocity_sensor",
    ALTITUDE = "altitude_sensor",
    GIMBAL = "gimbal_sensor",
    PHYSICS_ASSEMBLER = "physics_assembler",
}

local SUPPORTED_SET = {
    velocity_sensor = true,
    altitude_sensor = true,
    gimbal_sensor = true,
    physics_assembler = true,
}

local function is_finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function canonicalize_type(sensor_type)
    if type(sensor_type) ~= "string" or sensor_type == "" then
        return nil, "UNSUPPORTED_SENSOR_TYPE: " .. tostring(sensor_type)
    end
    local bare = sensor_type
    local prefix, tail = sensor_type:match("^([%w_]+):([%w_]+)$")
    if prefix and (prefix == "avionics" or prefix == "create_avionics") then
        bare = tail
    end
    if SUPPORTED_SET[bare] then
        return bare, nil
    end
    return nil, "UNSUPPORTED_SENSOR_TYPE: " .. tostring(sensor_type)
end

function M.is_supported_type(sensor_type)
    local canon = canonicalize_type(sensor_type)
    return canon ~= nil
end

local function normalize_opts(opts)
    if type(opts) == "string" then
        return { preferred_side = opts }
    elseif type(opts) == "table" then
        return opts
    end
    return {}
end

local function matches_peripheral_type(actual_type, canonical_type)
    if type(actual_type) ~= "string" then
        return false
    end
    if actual_type == canonical_type then
        return true
    end
    return actual_type == ("avionics:" .. canonical_type)
        or actual_type == ("create_avionics:" .. canonical_type)
end

local function safe_call_method(dev, method_name)
    if type(dev) ~= "table" then
        return false, nil, "INVALID_PERIPHERAL_HANDLE"
    end
    local fn = dev[method_name]
    if type(fn) ~= "function" then
        return false, nil, "MISSING_METHOD: " .. tostring(method_name)
    end
    local ok, res = pcall(fn)
    if not ok then
        return false, nil, "PERIPHERAL_CALL_ERROR(" .. tostring(method_name) .. "): " .. tostring(res)
    end
    return true, res, nil
end

local function parse_vec2(raw, label)
    if type(raw) ~= "table" then
        return nil, "INVALID_VEC2_RETURN: " .. label
    end
    local a = raw[1]
    local b = raw[2]
    if not is_finite(a) or not is_finite(b) then
        return nil, "NON_FINITE_VEC2: " .. label
    end
    return a, b
end

local function parse_vec3(raw, label)
    if type(raw) ~= "table" then
        return nil, "INVALID_VEC3_RETURN: " .. label
    end
    local x = raw[1] ~= nil and raw[1] or raw.x
    local y = raw[2] ~= nil and raw[2] or raw.y
    local z = raw[3] ~= nil and raw[3] or raw.z
    if not is_finite(x) or not is_finite(y) or not is_finite(z) then
        return nil, "NON_FINITE_VEC3: " .. label
    end
    return x, y, z
end

-- =========================================================================
-- Common Discovery & Wrapping (4 Supported Peripherals Only)
-- =========================================================================

function M.wrap(sensor_type, name_or_dev, opts)
    local canon, type_err = canonicalize_type(sensor_type)
    if not canon then
        return nil, type_err
    end
    if type(name_or_dev) == "table" then
        return name_or_dev, nil
    end
    if type(name_or_dev) ~= "string" or name_or_dev == "" then
        return nil, "INVALID_PERIPHERAL_TARGET"
    end
    local cfg = normalize_opts(opts)
    local periph = cfg.peripheral or _G.peripheral
    if type(periph) ~= "table" or type(periph.wrap) ~= "function" then
        return nil, "PERIPHERAL_API_UNAVAILABLE"
    end
    if type(periph.getType) == "function" then
        local ok_t, actual_t = pcall(periph.getType, name_or_dev)
        if not ok_t or not matches_peripheral_type(actual_t, canon) then
            return nil, "PERIPHERAL_TYPE_MISMATCH: expected " .. canon .. ", got " .. tostring(actual_t)
        end
    end
    local ok_w, wrapped = pcall(periph.wrap, name_or_dev)
    if not ok_w or type(wrapped) ~= "table" then
        return nil, "PERIPHERAL_WRAP_FAILED: " .. tostring(name_or_dev)
    end
    return wrapped, nil
end

function M.find_all(sensor_type, opts)
    local canon, type_err = canonicalize_type(sensor_type)
    if not canon then
        return nil, type_err
    end
    local cfg = normalize_opts(opts)
    local periph = cfg.peripheral or _G.peripheral
    if type(periph) ~= "table" or type(periph.getNames) ~= "function" or type(periph.wrap) ~= "function" then
        return {}, "PERIPHERAL_API_UNAVAILABLE"
    end

    local ok_n, names = pcall(periph.getNames)
    if not ok_n or type(names) ~= "table" then
        return {}, "PERIPHERAL_ENUM_FAILED"
    end

    local sorted = {}
    for i = 1, #names do
        sorted[i] = names[i]
    end
    sort(sorted)

    local filter_fn = type(cfg.filter) == "function" and cfg.filter or nil
    local out = {}
    for _, name in ipairs(sorted) do
        local ok_t, ptype = pcall(periph.getType, name)
        if ok_t and matches_peripheral_type(ptype, canon) then
            local ok_w, dev = pcall(periph.wrap, name)
            if ok_w and type(dev) == "table" then
                if not filter_fn or filter_fn(name, dev) then
                    out[#out + 1] = { name = name, dev = dev }
                end
            end
        end
    end
    return out, nil
end

function M.find(sensor_type, opts)
    local canon, type_err = canonicalize_type(sensor_type)
    if not canon then
        return nil, type_err
    end
    local cfg = normalize_opts(opts)
    local pref = cfg.preferred_side or cfg.preferredSide or cfg.name
    local filter_fn = type(cfg.filter) == "function" and cfg.filter or nil

    if type(pref) == "string" and pref ~= "" then
        local dev = M.wrap(canon, pref, cfg)
        if dev and (not filter_fn or filter_fn(pref, dev)) then
            return dev, pref
        end
    end

    local all, err = M.find_all(canon, cfg)
    if not all or #all == 0 then
        return nil, err or ("PERIPHERAL_NOT_FOUND: " .. canon)
    end
    return all[1].dev, all[1].name
end

local function make_scoped_finder(canon_type)
    return {
        find = function(opts)
            return M.find(canon_type, opts)
        end,
        find_all = function(opts)
            return M.find_all(canon_type, opts)
        end,
        wrap = function(name_or_dev, opts)
            return M.wrap(canon_type, name_or_dev, opts)
        end,
    }
end

-- =========================================================================
-- 1. velocity_sensor (CC:Avionics)
-- =========================================================================

local velocity = make_scoped_finder(M.PERIPHERAL_TYPES.VELOCITY)

local VALID_AXES = { x = true, y = true, z = true }
local VALID_DIRECTIONS = { forward = true, vertical = true, lateral = true }

local function parse_ship_velocity_direction(periph_name)
    if type(periph_name) ~= "string" then
        return nil
    end
    local dir = periph_name:match("^ship_velocity_sensor_(%a+)_%d+$")
    if dir then
        dir = dir:lower()
        if VALID_DIRECTIONS[dir] then
            return dir
        end
    end
    return nil
end

function velocity.get_velocity(dev)
    local ok, val, err = safe_call_method(dev, "getVelocity")
    if not ok then
        return nil, err
    end
    if not is_finite(val) then
        return nil, "NON_FINITE_VELOCITY"
    end
    return val, nil
end

function velocity.get_axis(dev)
    local ok, val, err = safe_call_method(dev, "getAxis")
    if not ok then
        return nil, err
    end
    if type(val) ~= "string" then
        return nil, "INVALID_VELOCITY_AXIS"
    end
    local axis = val:lower()
    if not VALID_AXES[axis] then
        return nil, "UNKNOWN_VELOCITY_AXIS: " .. tostring(val)
    end
    return axis, nil
end

function velocity.read(dev, periph_name)
    local v, err_v = velocity.get_velocity(dev)
    if v == nil then
        return nil, err_v
    end
    local axis, err_a = velocity.get_axis(dev)
    if not axis then
        return nil, err_a
    end
    return {
        velocity = v,
        axis = axis,
        direction = parse_ship_velocity_direction(periph_name),
        name = periph_name,
    }, nil
end

local function collect_velocity_entries(sensors_or_opts)
    if sensors_or_opts == nil then
        return velocity.find_all()
    end
    if type(sensors_or_opts) ~= "table" then
        return nil, "INVALID_VELOCITY_SOURCE"
    end
    -- Check if array of entries or wrapped devices
    if #sensors_or_opts > 0 then
        local list = {}
        for i = 1, #sensors_or_opts do
            local item = sensors_or_opts[i]
            if type(item) == "table" and type(item.dev) == "table" then
                list[#list + 1] = { name = item.name, dev = item.dev, direction = item.direction }
            elseif type(item) == "table" and type(item.getVelocity) == "function" then
                list[#list + 1] = { name = nil, dev = item }
            end
        end
        return list, nil
    end
    -- Check if keyed map { x=dev, y=dev, z=dev } or { forward=dev, ... }
    local keyed = {}
    for k, v in pairs(sensors_or_opts) do
        if type(v) == "table" and type(v.getVelocity) == "function" then
            local key_str = tostring(k):lower()
            keyed[#keyed + 1] = {
                name = VALID_DIRECTIONS[key_str] and ("ship_velocity_sensor_" .. key_str .. "_0") or key_str,
                dev = v,
                axis_hint = VALID_AXES[key_str] and key_str or nil,
                direction = VALID_DIRECTIONS[key_str] and key_str or nil,
            }
        end
    end
    if #keyed > 0 then
        return keyed, nil
    end
    -- Treat as discovery options table
    return velocity.find_all(sensors_or_opts)
end

function velocity.read_vector3(sensors_or_opts)
    local entries, err = collect_velocity_entries(sensors_or_opts)
    if not entries or #entries == 0 then
        return nil, err or "NO_VELOCITY_SENSORS_FOUND"
    end

    local sums = { x = 0.0, y = 0.0, z = 0.0 }
    local counts = { x = 0, y = 0, z = 0 }
    local dir_sums = {}
    local dir_counts = {}
    local valid_total = 0

    for _, ent in ipairs(entries) do
        local v = velocity.get_velocity(ent.dev)
        local ax = velocity.get_axis(ent.dev) or ent.axis_hint
        if v ~= nil and ax and VALID_AXES[ax] then
            sums[ax] = sums[ax] + v
            counts[ax] = counts[ax] + 1
            valid_total = valid_total + 1

            local dir = ent.direction or parse_ship_velocity_direction(ent.name)
            if dir and VALID_DIRECTIONS[dir] then
                dir_sums[dir] = (dir_sums[dir] or 0.0) + v
                dir_counts[dir] = (dir_counts[dir] or 0) + 1
            end
        end
    end

    if valid_total == 0 then
        return nil, "NO_VALID_VELOCITY_READING"
    end

    local vx = counts.x > 0 and (sums.x / counts.x) or 0.0
    local vy = counts.y > 0 and (sums.y / counts.y) or 0.0
    local vz = counts.z > 0 and (sums.z / counts.z) or 0.0

    local ship_dirs = {
        forward = dir_counts.forward and (dir_sums.forward / dir_counts.forward) or nil,
        vertical = dir_counts.vertical and (dir_sums.vertical / dir_counts.vertical) or nil,
        lateral = dir_counts.lateral and (dir_sums.lateral / dir_counts.lateral) or nil,
    }

    return {
        x = vx,
        y = vy,
        z = vz,
        vx = vx,
        vy = vy,
        vz = vz,
        axes_present = {
            x = counts.x > 0,
            y = counts.y > 0,
            z = counts.z > 0,
        },
        ship = ship_dirs,
        speed = sqrt(vx * vx + vy * vy + vz * vz),
        horizontal_speed = sqrt(vx * vx + vz * vz),
        sensor_count = valid_total,
    }, nil
end

M.velocity = velocity

-- =========================================================================
-- 2. altitude_sensor (CC:Avionics)
-- =========================================================================

local altitude = make_scoped_finder(M.PERIPHERAL_TYPES.ALTITUDE)

function altitude.get_height(dev)
    local ok, val, err = safe_call_method(dev, "getHeight")
    if not ok then return nil, err end
    if not is_finite(val) then return nil, "NON_FINITE_HEIGHT" end
    return val, nil
end

function altitude.get_air_pressure(dev)
    local ok, val, err = safe_call_method(dev, "getAirPressure")
    if not ok then return nil, err end
    if not is_finite(val) then return nil, "NON_FINITE_AIR_PRESSURE" end
    return val, nil
end

function altitude.get_vertical_speed(dev)
    local ok, val, err = safe_call_method(dev, "getVerticalSpeed")
    if not ok then return nil, err end
    if not is_finite(val) then return nil, "NON_FINITE_VERTICAL_SPEED" end
    return val, nil
end

function altitude.read(dev)
    local h, err_h = altitude.get_height(dev)
    if h == nil then return nil, err_h end

    local p, err_p = altitude.get_air_pressure(dev)
    if p == nil then return nil, err_p end

    local vs, err_vs = altitude.get_vertical_speed(dev)
    if vs == nil then return nil, err_vs end

    return {
        height = h,
        altitude = h,
        air_pressure = p,
        vertical_speed = vs,
    }, nil
end

M.altitude = altitude

-- =========================================================================
-- 3. gimbal_sensor (CC:Avionics)
-- =========================================================================

local gimbal = make_scoped_finder(M.PERIPHERAL_TYPES.GIMBAL)

function gimbal.get_angles(dev)
    local ok, raw, err = safe_call_method(dev, "getAngles")
    if not ok then return nil, err end
    local pitch, roll = parse_vec2(raw, "getAngles")
    if pitch == nil then return nil, roll end
    return { pitch = pitch, roll = roll }, nil
end

function gimbal.get_angles_rad(dev)
    local ok, raw, err = safe_call_method(dev, "getAnglesRad")
    if not ok then return nil, err end
    local pitch, roll = parse_vec2(raw, "getAnglesRad")
    if pitch == nil then return nil, roll end
    return { pitch = pitch, roll = roll }, nil
end

local function parse_angular_rates(raw, label)
    local wx, wy, wz = parse_vec3(raw, label)
    if wx == nil then
        return nil, wy
    end
    -- Sable / CC:Avionics body frame:
    -- wx = rotation about body-X (pitch rate)
    -- wy = rotation about body-Y (yaw rate)
    -- wz = rotation about body-Z (roll rate)
    return {
        wx = wx,
        wy = wy,
        wz = wz,
        pitch_rate = wx,
        yaw_rate = wy,
        roll_rate = wz,
    }, nil
end

function gimbal.get_angular_rates(dev)
    local ok, raw, err = safe_call_method(dev, "getAngularRates")
    if not ok then return nil, err end
    return parse_angular_rates(raw, "getAngularRates")
end

function gimbal.get_angular_rates_rad(dev)
    local ok, raw, err = safe_call_method(dev, "getAngularRatesRad")
    if not ok then return nil, err end
    return parse_angular_rates(raw, "getAngularRatesRad")
end

function gimbal.get_gravity(dev)
    local ok, raw, err = safe_call_method(dev, "getGravity")
    if not ok then return nil, err end
    local gx, gy, gz = parse_vec3(raw, "getGravity")
    if gx == nil then return nil, gy end
    return { x = gx, y = gy, z = gz }, nil
end

function gimbal.get_linear_acceleration(dev)
    local ok, raw, err = safe_call_method(dev, "getLinearAcceleration")
    if not ok then return nil, err end
    local ax, ay, az = parse_vec3(raw, "getLinearAcceleration")
    if ax == nil then return nil, ay end
    return { x = ax, y = ay, z = az }, nil
end

function gimbal.compute_tilt_deg(gravity)
    local gx, gy, gz = parse_vec3(gravity, "gravity")
    if gx == nil then
        return nil
    end
    local mag = sqrt(gx * gx + gy * gy + gz * gz)
    if mag < 1e-9 then
        return nil
    end
    -- At level attitude, world-down in body frame is (0, -|g|, 0), so -gy / |g| = 1 -> 0 deg.
    local cos_theta = (-gy) / mag
    if cos_theta > 1.0 then
        cos_theta = 1.0
    elseif cos_theta < -1.0 then
        cos_theta = -1.0
    end
    return deg(acos(cos_theta))
end

function gimbal.read(dev)
    local angles, err_ang = gimbal.get_angles(dev)
    if not angles then return nil, err_ang end

    local rates, err_rt = gimbal.get_angular_rates(dev)
    if not rates then return nil, err_rt end

    local grav, err_g = gimbal.get_gravity(dev)
    if not grav then return nil, err_g end

    local lin_acc, err_a = gimbal.get_linear_acceleration(dev)
    if not lin_acc then return nil, err_a end

    return {
        angles = angles,
        angular_rates = rates,
        gravity = grav,
        linear_acceleration = lin_acc,
        inertial_acceleration = {
            x = lin_acc.x + grav.x,
            y = lin_acc.y + grav.y,
            z = lin_acc.z + grav.z,
        },
        tilt_deg = gimbal.compute_tilt_deg(grav),
    }, nil
end

M.gimbal = gimbal

-- =========================================================================
-- 4. physics_assembler (CC:Avionics — all methods yield on mainThread)
-- =========================================================================

local assembler = make_scoped_finder(M.PERIPHERAL_TYPES.PHYSICS_ASSEMBLER)

local function parse_inertia_tensor(raw)
    if type(raw) ~= "table" then
        return nil, "INVALID_INERTIA_TENSOR"
    end
    local clean = {}
    for i = 1, 9 do
        local v = raw[i]
        if not is_finite(v) then
            return nil, "NON_FINITE_INERTIA_TENSOR"
        end
        clean[i] = v
    end
    return {
        raw = clean,
        ixx = clean[1], ixy = clean[2], ixz = clean[3],
        iyx = clean[4], iyy = clean[5], iyz = clean[6],
        izx = clean[7], izy = clean[8], izz = clean[9],
    }, nil
end

function assembler.is_assembled(dev)
    local ok, val, err = safe_call_method(dev, "isAssembled")
    if not ok then return nil, err end
    if type(val) ~= "boolean" then return nil, "INVALID_ASSEMBLED_BOOLEAN" end
    return val, nil
end

function assembler.get_mass(dev)
    local ok, val, err = safe_call_method(dev, "getMass")
    if not ok then return nil, err end
    if not is_finite(val) then return nil, "NON_FINITE_MASS" end
    return val, nil
end

function assembler.get_center_of_mass(dev)
    local ok, raw, err = safe_call_method(dev, "getCenterOfMass")
    if not ok then return nil, err end
    local cx, cy, cz = parse_vec3(raw, "getCenterOfMass")
    if cx == nil then return nil, cy end
    return { x = cx, y = cy, z = cz }, nil
end

function assembler.get_inertia_tensor(dev)
    local ok, raw, err = safe_call_method(dev, "getInertiaTensor")
    if not ok then return nil, err end
    return parse_inertia_tensor(raw)
end

function assembler.get_sub_level_id(dev)
    local ok, val, err = safe_call_method(dev, "getSubLevelId")
    if not ok then return nil, err end
    if val ~= nil and type(val) ~= "string" then
        return nil, "INVALID_SUB_LEVEL_ID"
    end
    return val, nil
end

function assembler.get_sub_level_name(dev)
    local ok, val, err = safe_call_method(dev, "getSubLevelName")
    if not ok then return nil, err end
    if val ~= nil and type(val) ~= "string" then
        return nil, "INVALID_SUB_LEVEL_NAME"
    end
    return val, nil
end

function assembler.read(dev, opts)
    if type(dev) ~= "table" then
        return nil, "INVALID_PERIPHERAL_HANDLE"
    end
    local cfg = normalize_opts(opts)
    local par_api
    if cfg.parallel == false then
        par_api = nil
    elseif type(cfg.parallel) == "table" then
        par_api = cfg.parallel
    else
        par_api = _G.parallel
    end

    local assembled, err_asm
    local mass, err_mass
    local com, err_com
    local tensor, err_ten
    local sub_id, err_id
    local sub_name, err_name

    if par_api and type(par_api.waitForAll) == "function" then
        local ok_par, par_err = pcall(
            par_api.waitForAll,
            function() assembled, err_asm = assembler.is_assembled(dev) end,
            function() mass, err_mass = assembler.get_mass(dev) end,
            function() com, err_com = assembler.get_center_of_mass(dev) end,
            function() tensor, err_ten = assembler.get_inertia_tensor(dev) end,
            function() sub_id, err_id = assembler.get_sub_level_id(dev) end,
            function() sub_name, err_name = assembler.get_sub_level_name(dev) end
        )
        if not ok_par then
            return nil, "PARALLEL_BATCH_ERROR: " .. tostring(par_err)
        end
    else
        assembled, err_asm = assembler.is_assembled(dev)
        mass, err_mass = assembler.get_mass(dev)
        com, err_com = assembler.get_center_of_mass(dev)
        tensor, err_ten = assembler.get_inertia_tensor(dev)
        sub_id, err_id = assembler.get_sub_level_id(dev)
        sub_name, err_name = assembler.get_sub_level_name(dev)
    end

    local first_err = err_asm or err_mass or err_com or err_ten or err_id or err_name
    if first_err then
        return nil, first_err
    end

    return {
        assembled = assembled,
        mass = mass,
        center_of_mass = com,
        inertia_tensor = tensor,
        sub_level_id = sub_id,
        sub_level_name = sub_name,
    }, nil
end

M.assembler = assembler
M.physics_assembler = assembler

return M
