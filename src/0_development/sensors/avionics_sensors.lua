--- @module avionics_sensors
--- Create_Aeroneutics 전역 표준 CC:Avionics (Create: Avionics) 4종 센서 API 라이브러리.
---
--- [지원 센서 4종 SSOT]
--- 1. velocity_sensor: 1축 선속도(m/s, 0.05m/s 데드밴드) 및 장착 축("x"|"y"|"z").
--- 2. altitude_sensor: 월드 고도(m), 기압비(0.0~1.5), 수직 승강 속도(m/s).
--- 3. gimbal_sensor: 동체 오일러 각도(pitch, roll), 3축 각속도(wx, wy, wz), 중력 벡터, 고유 가속도.
--- 4. physics_assembler: 조립 여부, 질량, 질량중심, 3x3 관성 텐서, 서브레벨 식별자.
---
--- [하드웨어 연결 토폴로지]
--- 1. 직접 인접 (Direct Adjacent):
---    - 컴퓨터 6개 면("top", "bottom", "left", "right", "front", "back")에 센서가 물리적으로 접촉한 구성.
---    - peripheral.wrap("top") 또는 sensors.find({ preferred_side = "top" })으로 즉시 바인딩.
--- 2. 유선 모뎀 네트워크 (Wired Modem Network):
---    - CC 유선 케이블(Networking Cable) 및 유선 모뎀(Wired Modem)으로 컴퓨터와 센서를 연결한 구성.
---    - [필수 주의] 각 센서에 부착된 유선 모뎀을 반드시 우클릭 활성화(빨간 테두리 점등)해야
---      네트워크에 고유 식별자(예: "velocity_sensor_0", "altitude_sensor_0")가 등록됩니다.
---    - 3축 속도계 구성 시, 3개의 1축 velocity_sensor를 유선 모뎀으로 연결하며, 라이브러리가
---      센서의 getAxis()("x", "y", "z") 또는 소프트웨어 명명 규칙(ship_velocity_sensor_forward_0 등)을
---      통해 전/상/측 3축을 자동 판정하여 합성 속도 벡터를 산출합니다.
---
--- [사용 패턴 (이중 패턴 지원)]
--- 패턴 A: CC 기본 peripheral.find() / peripheral.wrap()으로 얻은 핸들을 함수에 직접 주입
---   local sensors = require("avionics_sensors")
---   local dev = peripheral.find("altitude_sensor")
---   local alt, err = sensors.altitude.get_height(dev)
---
--- 패턴 B: 본 모듈의 내장 find() 메서드로 직접 인접 및 유선 모뎀을 통합 자동 탐색
---   local sensors = require("avionics_sensors")
---   local dev, name = sensors.altitude.find({ preferred_side = "bottom" })
---   local summary, err = sensors.altitude.read(dev)
---
--- @version 1.0.0

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

--- 지정된 이름(인접 면 또는 유선 모뎀 식별자)의 센서를 검증 및 래핑합니다.
---
--- @param sensor_type string 센서 타입 ("velocity_sensor" | "altitude_sensor" | "gimbal_sensor" | "physics_assembler")
--- @param name_or_dev string|table 주변기기 이름 ("top", "velocity_sensor_0" 등) 또는 이미 래핑된 테이블
--- @param opts table|nil 옵션 테이블 ({ preferred_side = "top", peripheral = custom_api })
--- @return table|nil dev 래핑된 주변기기 핸들 (실패 시 nil)
--- @return string|nil error_msg 오류 메시지 (성공 시 nil)
---
--- @example
--- -- 1) 직접 인접면("top") 바인딩
--- local dev, err = sensors.wrap("altitude_sensor", "top")
---
--- -- 2) 유선 모뎀 네트워크 이름("altitude_sensor_0") 바인딩
--- local dev, err = sensors.wrap("altitude_sensor", "altitude_sensor_0")
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

--- 컴퓨터에 직접 인접하거나 유선 모뎀 네트워크에 연결된 해당 타입의 모든 센서를 탐색하여 반환합니다.
---
--- @param sensor_type string 센서 타입 식별자
--- @param opts table|nil 옵션 ({ filter = function(name, dev) return boolean end })
--- @return table list { { name = string, dev = table }, ... } (미발견 시 빈 배열)
--- @return string|nil error_msg 오류 메시지 (정상 시 nil)
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

--- 지정된 타입의 센서를 1개 탐색하여 래핑된 핸들과 이름을 반환합니다.
--- (preferred_side 지정 시 해당 면/이름을 최우선 검사하며, 미지정 시 유선모뎀/인접면 목록 중 첫 번째 장치 반환)
---
--- @param sensor_type string 센서 타입
--- @param opts table|string|nil 탐색 옵션 ({ preferred_side = "bottom" } 또는 면 이름 문자열)
--- @return table|nil dev 래핑된 센서 핸들 (미발견 시 nil)
--- @return string|nil name_or_err 성공 시 주변기기 이름("top", "velocity_sensor_0" 등), 실패 시 오류 문자열
---
--- @example
--- -- 1) 우선 순위 면 지정 바인딩 (인접 면 우선)
--- local dev, name = sensors.find("gimbal_sensor", { preferred_side = "bottom" })
---
--- -- 2) 유선 모뎀 네트워크 상의 임의 센서 1개 자동 탐색
--- local dev, name = sensors.find("velocity_sensor")
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

--- velocity_sensor의 장착 축 기준 단일 방향 선속도(m/s)를 조회합니다.
--- (CC:Avionics 내부 0.05 m/s 데드밴드가 적용되어 미세 진동 시 0.0을 반환합니다)
---
--- @param dev table peripheral.find("velocity_sensor") 또는 peripheral.wrap()으로 획득한 장치 핸들
--- @return number|nil velocity 선속도 (m/s, 실패 시 nil)
--- @return string|nil error_msg 오류 메시지 (성공 시 nil)
---
--- @example
--- -- 패턴 A: CC 기본 peripheral.find()로 장치 획득 후 전달 (직접 인접 또는 유선 모뎀)
--- local dev = peripheral.find("velocity_sensor")
--- local vel, err = sensors.velocity.get_velocity(dev)
---
--- -- 패턴 B: 모듈 내장 find()로 자동 탐색 후 전달
--- local dev = sensors.velocity.find({ preferred_side = "front" })
--- local vel, err = sensors.velocity.get_velocity(dev)
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

--- velocity_sensor가 장착된 선체 기준 축("x"|"y"|"z")을 조회합니다.
---
--- @param dev table peripheral.find() 또는 peripheral.wrap()으로 획득한 장치 핸들
--- @return string|nil axis 축 식별자 ("x" | "y" | "z", 실패 시 nil)
--- @return string|nil error_msg 오류 메시지 (성공 시 nil)
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

--- 단일 velocity_sensor의 속도와 축 정보, 방향을 일괄 조회합니다.
---
--- @param dev table 장치 핸들
--- @param periph_name string|nil 주변기기 식별자 이름 (옵션, 방향 추론용)
--- @return table|nil result { velocity = number, axis = "x"|"y"|"z", direction = "forward"|"vertical"|"lateral"|nil, name = string|nil }
--- @return string|nil error_msg 오류 메시지
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

--- 복수의 1축 velocity_sensor를 3축(x, y, z / forward, vertical, lateral) 합성 속도 벡터로 계산합니다.
---
--- [유선 모뎀 네트워크 3축 속도계 구성 및 매핑 원리]
--- - CC:Avionics의 velocity_sensor는 1축 전용이므로, 전방/수직/측방 3차원 속도를 산출하려면
---   3개의 센서를 설치하고 순정 CC:Tweaked 유선 모뎀(Wired Modem)과 케이블로 연결합니다.
---   (유선 모뎀을 우클릭하여 활성화(빨간 테두리 점등)해야 네트워크에 등록됩니다)
--- - 본 함수는 전달된 인자에 따라 다음 3가지 방식으로 3축 센서를 자동 분류 및 합성합니다:
---   1) getAxis() 자동 판정: 일반 모뎀 이름("velocity_sensor_0" 등)이어도 각 센서의 getAxis()("x", "y", "z")를
---      호출하여 축을 식별하고 평균 속도를 산출합니다.
---   2) 이름 규칙 매핑: 모뎀 이름이 "ship_velocity_sensor_forward_0", "_vertical_0", "_lateral_0"인 경우
---      정규식을 통해 전방/수직/측방 방향을 직접 매핑합니다.
---   3) 명시적 매핑 테이블 전달: 사용자가 { forward = dev_f, vertical = dev_v, lateral = dev_l } 또는
---      { x = dev_x, y = dev_y, z = dev_z } 형태로 직접 장치 핸들을 넘길 수 있습니다.
---
--- @param sensors_or_opts table|nil 센서 장치 배열, 방향 매핑 맵, 또는 find_all 옵션 (생략 시 유선 모뎀/인접면 자동 검색)
--- @return table|nil vector { x, y, z, vx, vy, vz, speed, horizontal_speed, ship = { forward, vertical, lateral }, axes_present, sensor_count }
--- @return string|nil error_msg 오류 메시지
---
--- @example
--- -- 예시 1: 유선 모뎀 상의 3축 센서 1줄 자동 탐색 및 합성 (가장 간편)
--- local vec, err = sensors.velocity.read_vector3()
--- if vec then
---     print("전진 속도(m/s):", vec.ship.forward, "합성 속력:", vec.speed)
--- end
---
--- -- 예시 2: peripheral.find/wrap으로 개별 획득한 장치를 테이블로 묶어 전달
--- local triad = {
---     forward = peripheral.wrap("velocity_sensor_0"),
---     vertical = peripheral.wrap("velocity_sensor_1"),
---     lateral = peripheral.wrap("velocity_sensor_2"),
--- }
--- local vec, err = sensors.velocity.read_vector3(triad)
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

--- altitude_sensor로부터 월드 절대 Y 고도(m)를 조회합니다.
---
--- @param dev table peripheral.find("altitude_sensor") 또는 peripheral.wrap() 장치 핸들
--- @return number|nil height 월드 고도 (m, 실패 시 nil)
--- @return string|nil error_msg 오류 메시지
---
--- @example
--- local dev = peripheral.find("altitude_sensor")
--- local y, err = sensors.altitude.get_height(dev)
function altitude.get_height(dev)
    local ok, val, err = safe_call_method(dev, "getHeight")
    if not ok then return nil, err end
    if not is_finite(val) then return nil, "NON_FINITE_HEIGHT" end
    return val, nil
end

--- altitude_sensor로부터 해수면 기준 대기압 비율(0.0 ~ 1.5)을 조회합니다.
---
--- @param dev table 장치 핸들
--- @return number|nil air_pressure 기압 비율 (실패 시 nil)
--- @return string|nil error_msg 오류 메시지
function altitude.get_air_pressure(dev)
    local ok, val, err = safe_call_method(dev, "getAirPressure")
    if not ok then return nil, err end
    if not is_finite(val) then return nil, "NON_FINITE_AIR_PRESSURE" end
    return val, nil
end

--- altitude_sensor로부터 수직 승강 속도(m/s, 상승 양수/하강 음수)를 조회합니다.
---
--- @param dev table 장치 핸들
--- @return number|nil vertical_speed 수직 속도 (m/s, 실패 시 nil)
--- @return string|nil error_msg 오류 메시지
function altitude.get_vertical_speed(dev)
    local ok, val, err = safe_call_method(dev, "getVerticalSpeed")
    if not ok then return nil, err end
    if not is_finite(val) then return nil, "NON_FINITE_VERTICAL_SPEED" end
    return val, nil
end

--- altitude_sensor의 고도, 기압, 수직 속도를 일괄 조회하여 요약 테이블로 반환합니다.
---
--- @param dev table peripheral.find("altitude_sensor") 또는 peripheral.wrap() 장치 핸들
--- @return table|nil summary { height = number, altitude = number, air_pressure = number, vertical_speed = number }
--- @return string|nil error_msg 오류 메시지
---
--- @example
--- -- 1) 직접 인접면("top") 바인딩 후 일괄 조회
--- local dev = peripheral.wrap("top")
--- local alt_data, err = sensors.altitude.read(dev)
--- print("현재 고도:", alt_data.height, "승강 속도:", alt_data.vertical_speed)
---
--- -- 2) 모듈 내장 find로 유선 모뎀 상의 고도 센서 자동 탐색 후 조회
--- local dev = sensors.altitude.find()
--- local alt_data, err = sensors.altitude.read(dev)
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

--- gimbal_sensor로부터 도(degree) 단위 동체 오일러 각도(pitch, roll)를 조회합니다.
--- [주의] 짐벌 센서의 각도는 수직 특이점(Gimbal Lock)이 존재하므로, 기울기 계산 시에는
--- get_gravity() 기반의 compute_tilt_deg() 사용을 권장합니다.
---
--- @param dev table peripheral.find("gimbal_sensor") 또는 peripheral.wrap() 장치 핸들
--- @return table|nil angles { pitch = number, roll = number }
--- @return string|nil error_msg 오류 메시지
function gimbal.get_angles(dev)
    local ok, raw, err = safe_call_method(dev, "getAngles")
    if not ok then return nil, err end
    local pitch, roll = parse_vec2(raw, "getAngles")
    if pitch == nil then return nil, roll end
    return { pitch = pitch, roll = roll }, nil
end

--- gimbal_sensor로부터 라디안(radian) 단위 동체 오일러 각도(pitch, roll)를 조회합니다.
---
--- @param dev table 장치 핸들
--- @return table|nil angles_rad { pitch = number, roll = number } (라디안)
--- @return string|nil error_msg 오류 메시지
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

--- gimbal_sensor로부터 도 단위(deg/s) 3축 회전 각속도(wx=피치율, wy=요율, wz=롤율)를 조회합니다.
---
--- @param dev table 장치 핸들
--- @return table|nil rates { wx, wy, wz, pitch_rate, yaw_rate, roll_rate } (deg/s)
--- @return string|nil error_msg 오류 메시지
function gimbal.get_angular_rates(dev)
    local ok, raw, err = safe_call_method(dev, "getAngularRates")
    if not ok then return nil, err end
    return parse_angular_rates(raw, "getAngularRates")
end

--- gimbal_sensor로부터 라디안 단위(rad/s) 3축 회전 각속도를 조회합니다.
---
--- @param dev table 장치 핸들
--- @return table|nil rates_rad { wx, wy, wz, pitch_rate, yaw_rate, roll_rate } (rad/s)
--- @return string|nil error_msg 오류 메시지
function gimbal.get_angular_rates_rad(dev)
    local ok, raw, err = safe_call_method(dev, "getAngularRatesRad")
    if not ok then return nil, err end
    return parse_angular_rates(raw, "getAngularRatesRad")
end

--- gimbal_sensor로부터 동체 기준 중력 벡터 { x, y, z }를 조회합니다.
--- (수평 정지 시 월드 아래 방향이 동체 좌표계로 사영되며, 무특이점 기울기 연산의 기본 소스로 활용됩니다)
---
--- @param dev table 장치 핸들
--- @return table|nil gravity { x = number, y = number, z = number }
--- @return string|nil error_msg 오류 메시지
function gimbal.get_gravity(dev)
    local ok, raw, err = safe_call_method(dev, "getGravity")
    if not ok then return nil, err end
    local gx, gy, gz = parse_vec3(raw, "getGravity")
    if gx == nil then return nil, gy end
    return { x = gx, y = gy, z = gz }, nil
end

--- gimbal_sensor로부터 동체 기준 고유 선형 가속도(m/s^2) { x, y, z }를 조회합니다.
---
--- @param dev table 장치 핸들
--- @return table|nil acceleration { x = number, y = number, z = number }
--- @return string|nil error_msg 오류 메시지
function gimbal.get_linear_acceleration(dev)
    local ok, raw, err = safe_call_method(dev, "getLinearAcceleration")
    if not ok then return nil, err end
    local ax, ay, az = parse_vec3(raw, "getLinearAcceleration")
    if ax == nil then return nil, ay end
    return { x = ax, y = ay, z = az }, nil
end

--- 중력 벡터로부터 동체 수직축의 기울기 각도(Tilt Angle, deg)를 계산합니다.
--- (오일러 각의 Gimbal Lock 특이점 없이 0.0~180.0도 전 영역에서 안전하게 기울기를 산출합니다)
---
--- @param gravity table { x = number, y = number, z = number } 중력 벡터
--- @return number|nil tilt_deg 경사각 (0=완전 수평, 90=수직 기립, 실패 시 nil)
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

--- gimbal_sensor의 각도, 각속도, 중력, 가속도, 무특이점 기울기 각도를 일괄 조회합니다.
---
--- @param dev table peripheral.find("gimbal_sensor") 또는 peripheral.wrap() 장치 핸들
--- @return table|nil summary { angles, angular_rates, gravity, linear_acceleration, inertial_acceleration, tilt_deg }
--- @return string|nil error_msg 오류 메시지
---
--- @example
--- -- 패턴 A: CC 기본 peripheral.find() 연동
--- local dev = peripheral.find("gimbal_sensor")
--- local gimb, err = sensors.gimbal.read(dev)
--- print("동체 기울기(deg):", gimb.tilt_deg, "피치 각속도:", gimb.angular_rates.pitch_rate)
---
--- -- 패턴 B: 모듈 내장 find() 연동 (인접 면 또는 유선 모뎀 자동 탐색)
--- local dev = sensors.gimbal.find({ preferred_side = "bottom" })
--- local gimb, err = sensors.gimbal.read(dev)
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

--- physics_assembler의 선체 조립(Assembly) 상태 여부를 조회합니다.
--- [주의] CC:Avionics 어셈블러 메서드는 내부 mainThread = true 설정으로 인해 1회의 틱 yield가 발생합니다.
---
--- @param dev table peripheral.find("physics_assembler") 또는 peripheral.wrap() 장치 핸들
--- @return boolean|nil is_assembled 조립 완료 시 true (미조립 시 false, 실패 시 nil)
--- @return string|nil error_msg 오류 메시지
function assembler.is_assembled(dev)
    local ok, val, err = safe_call_method(dev, "isAssembled")
    if not ok then return nil, err end
    if type(val) ~= "boolean" then return nil, "INVALID_ASSEMBLED_BOOLEAN" end
    return val, nil
end

--- 선체의 총 질량(Mass)을 조회합니다. (mainThread yield 발생)
---
--- @param dev table 장치 핸들
--- @return number|nil mass 총 질량 (실패 시 nil)
--- @return string|nil error_msg 오류 메시지
function assembler.get_mass(dev)
    local ok, val, err = safe_call_method(dev, "getMass")
    if not ok then return nil, err end
    if not is_finite(val) then return nil, "NON_FINITE_MASS" end
    return val, nil
end

--- 선체의 무게중심(Center of Mass) 상대 좌표 { x, y, z }를 조회합니다. (mainThread yield 발생)
---
--- @param dev table 장치 핸들
--- @return table|nil center_of_mass { x = number, y = number, z = number }
--- @return string|nil error_msg 오류 메시지
function assembler.get_center_of_mass(dev)
    local ok, raw, err = safe_call_method(dev, "getCenterOfMass")
    if not ok then return nil, err end
    local cx, cy, cz = parse_vec3(raw, "getCenterOfMass")
    if cx == nil then return nil, cy end
    return { x = cx, y = cy, z = cz }, nil
end

--- 선체의 3x3 관성 모멘트 텐서(Inertia Tensor)를 조회합니다. (mainThread yield 발생)
---
--- @param dev table 장치 핸들
--- @return table|nil inertia_tensor { raw = {1..9}, ixx, ixy, ixz, iyx, iyy, iyz, izx, izy, izz }
--- @return string|nil error_msg 오류 메시지
function assembler.get_inertia_tensor(dev)
    local ok, raw, err = safe_call_method(dev, "getInertiaTensor")
    if not ok then return nil, err end
    return parse_inertia_tensor(raw)
end

--- 선체가 속한 서브레벨 식별자(SubLevel ID)를 조회합니다. (mainThread yield 발생)
---
--- @param dev table 장치 핸들
--- @return string|nil sub_level_id 서브레벨 식별 문자열 (없을 시 nil)
--- @return string|nil error_msg 오류 메시지
function assembler.get_sub_level_id(dev)
    local ok, val, err = safe_call_method(dev, "getSubLevelId")
    if not ok then return nil, err end
    if val ~= nil and type(val) ~= "string" then
        return nil, "INVALID_SUB_LEVEL_ID"
    end
    return val, nil
end

--- 선체가 속한 서브레벨 이름(SubLevel Name)을 조회합니다. (mainThread yield 발생)
---
--- @param dev table 장치 핸들
--- @return string|nil sub_level_name 서브레벨 명칭 문자열 (없을 시 nil)
--- @return string|nil error_msg 오류 메시지
function assembler.get_sub_level_name(dev)
    local ok, val, err = safe_call_method(dev, "getSubLevelName")
    if not ok then return nil, err end
    if val ~= nil and type(val) ~= "string" then
        return nil, "INVALID_SUB_LEVEL_NAME"
    end
    return val, nil
end

--- physics_assembler의 6대 핵심 물리 지표를 단 1틱 안에 병렬 일괄 조회합니다.
---
--- [1틱 일괄 조회 및 지연 누적 방지 원리]
--- 어셈블러의 개별 메서드(isAssembled, getMass 등)는 모두 mainThread yield를 수반하므로,
--- 직렬로 순차 호출할 경우 최소 6틱(0.3초) 이상의 블로킹 지연이 누적됩니다.
--- 본 함수는 parallel.waitForAll 코루틴을 통해 6대 쿼리를 단 1틱에 동시 스케줄링하여 조회합니다.
---
--- @param dev table peripheral.find("physics_assembler") 또는 peripheral.wrap() 장치 핸들
--- @param opts table|nil 옵션 ({ parallel = false 시 직렬 강제 })
--- @return table|nil summary { assembled, mass, center_of_mass, inertia_tensor, sub_level_id, sub_level_name }
--- @return string|nil error_msg 오류 메시지
---
--- @example
--- -- 패턴 A: CC 기본 peripheral.find() 연동
--- local dev = peripheral.find("physics_assembler")
--- local phys, err = sensors.assembler.read(dev)
--- if phys and phys.assembled then
---     print("선체 질량(kg):", phys.mass, "무게중심 Y:", phys.center_of_mass.y)
--- end
---
--- -- 패턴 B: 모듈 내장 find() 연동 (유선 모뎀 상의 어셈블러 자동 바인딩)
--- local dev = sensors.assembler.find()
--- local phys, err = sensors.assembler.read(dev)
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
