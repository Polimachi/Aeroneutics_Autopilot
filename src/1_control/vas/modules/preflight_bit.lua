--[[
    ========================================================================
    PRE-FLIGHT BUILT-IN TEST (preflight_bit.lua)
    CC:Tweaked & Create: Aeronautics / Avionics 기체 하드웨어 부팅 자가점검
    
    [역할]
    - UAFS 분산 아키텍처 각 노드의 센서/출력부/조종면/통신 무결성 자동 점검
    - GREEN (정상 무장), AMBER (보조 결함 / 무장 허용), RED (치명적 결함 / 무장 차단) 3단계 판정
    - 100% CraftOS 순수 런타임 호환 보장
    ========================================================================
]]

local preflight_bit = {}

--- 점검 결과 종합 및 최종 비행 허가 상태(GREEN/AMBER/RED) 판정
---@param errors table 결함 목록
---@param warnings table 경고 목록
---@param passedCount number? 정상 통과 항목 수
---@param passedTags table? 정상 통과 태그 목록
---@return table { status, isArmed, errors, warnings, passedCount, passedTags }
function preflight_bit.evaluateStatus(errors, warnings, passedCount, passedTags)
    local errs = errors or {}
    local warns = warnings or {}
    local passed = passedCount or 0

    local status = "GREEN"
    local isArmed = true

    if #errs > 0 then
        status = "RED"
        isArmed = false
    elseif #warns > 0 then
        status = "AMBER"
        isArmed = true
    end

    return {
        status = status,
        isArmed = isArmed,
        errors = errs,
        warnings = warns,
        passedCount = passed,
        passedTags = passedTags or {},
    }
end

--- 무선 모뎀 인터페이스 유효성 점검
---@param target any 모뎀 객체 또는 nil
---@return boolean ok, any device
function preflight_bit.checkModem(target)
    local m = target
    if not m and peripheral and peripheral.find then
        m = peripheral.find("modem")
    end
    if m and type(m.open) == "function" and type(m.transmit) == "function" then
        return true, m
    end
    return false, nil
end

--- 고정익 조종면 4대 베어링 결속 상태 점검
---@param surfaces table?
---@param warnings table
---@param passed number
---@param passedTags table?
---@return number updatedPassed
function preflight_bit.checkCoreSurfaces(surfaces, warnings, passed, passedTags)
    local surfs = surfaces or {}
    local required = {
        { key = "elevator", name = "Elevator" },
        { key = "leftAileron", name = "LeftAileron" },
        { key = "rightAileron", name = "RightAileron" },
        { key = "rudder", name = "Rudder" },
    }
    for _, item in ipairs(required) do
        local b = surfs[item.key]
        if b ~= nil then
            passed = passed + 1
            if passedTags then table.insert(passedTags, "SURFACE_" .. string.upper(item.key) .. "_OK") end
        else
            table.insert(warnings, "ASA: " .. item.name .. " control surface bearing not bound (advisory)")
        end
    end
    return passed
end

--- 기체 타입별 구동계 점검
---@param opts table?
---@param warnings table
---@param passed number
---@param passedTags table?
---@return number updatedPassed
function preflight_bit.checkActuatorsByVehicleType(opts, warnings, passed, passedTags)
    opts = opts or {}
    warnings = warnings or {}
    passed = passed or 0
    local rawType = opts.vehicleType or "airplane"
    local vType = string.lower(rawType)

    local thCount = opts.thrusterCount
    if not thCount then
        local allocator = opts.thrustAllocator
        if allocator and type(allocator.getThrusterCount) == "function" then
            thCount = allocator:getThrusterCount()
        elseif allocator and type(allocator.thrusters) == "table" then
            thCount = #allocator.thrusters
        elseif type(opts.thrusters) == "table" then
            thCount = #opts.thrusters
        else
            thCount = 0
        end
    end

    if vType == "drone" or vType == "multirotor_drone" then
        if thCount >= 4 then
            passed = passed + 1
            if passedTags then table.insert(passedTags, "DRONE_ROTORS_OK") end
        else
            table.insert(warnings, "WARN_DRONE_THRUSTERS_LOW")
        end
    elseif vType == "helicopter" or vType == "heli" then
        local hasTrans = (opts.transmission ~= nil) or (opts.throttleLever ~= nil)
        if hasTrans or thCount >= 2 then
            passed = passed + 1
            if passedTags then table.insert(passedTags, "HELI_ROTOR_SYSTEM_OK") end
        else
            table.insert(warnings, "WARN_HELI_ROTOR_MISSING")
        end
    elseif vType == "spacecraft" then
        if thCount >= 4 then
            passed = passed + 1
            if passedTags then table.insert(passedTags, "SPACECRAFT_RCS_OK") end
        else
            table.insert(warnings, "WARN_RCS_THRUSTERS_LOW")
        end
    else
        local hasThrottle = (opts.transmission and type(opts.transmission.setSignal) == "function") or
                            (opts.throttleLever and type(opts.throttleLever.setSignal) == "function")
        if hasThrottle then
            passed = passed + 1
            if passedTags then table.insert(passedTags, "THROTTLE_ACTUATOR_OK") end
        else
            table.insert(warnings, "VAS: Direct throttle transmission/lever not bound (advisory)")
        end
        passed = preflight_bit.checkCoreSurfaces(opts.surfaces, warnings, passed, passedTags)
    end
    return passed
end

--- Central Core (VAS / Node 01) 자가진단
---@param options table? { modem, transmission, throttleLever, surfaces, thrustAllocator, vehicleType, thrusterCount }
---@return table BIT 결과
function preflight_bit.checkCentralCore(options)
    local opts = options or {}
    local errors = {}
    local warnings = {}
    local passedTags = {}
    local passed = 0

    local hasModem = preflight_bit.checkModem(opts.modem)
    if hasModem then
        passed = passed + 1
        table.insert(passedTags, "MODEM_OK")
    else
        table.insert(errors, "VAS: Wireless modem missing or invalid (critical)")
    end

    local count = opts.thrusterCount or 0
    local allocator = opts.thrustAllocator
    if count == 0 and allocator then
        if type(allocator.getThrusterCount) == "function" then
            count = allocator:getThrusterCount()
        elseif type(allocator.thrusters) == "table" then
            count = #allocator.thrusters
        end
    elseif count == 0 and type(opts.thrusters) == "table" then
        count = #opts.thrusters
    end

    if count > 0 then
        passed = passed + 1
        table.insert(passedTags, "THRUSTERS_OK")
    else
        table.insert(warnings, "VAS: No thrusters registered in ThrustAllocator (advisory)")
    end

    passed = preflight_bit.checkActuatorsByVehicleType(opts, warnings, passed, passedTags)

    local result = preflight_bit.evaluateStatus(errors, warnings, passed, passedTags)
    result.node = "VAS_CORE"
    return result
end

--- 센서 장치군 점검 헬퍼
---@param devices table?
---@param errors table
---@param warnings table
---@param passed number
---@return number updatedPassed
local function checkSensorDevices(devices, errors, warnings, passed)
    local devs = devices or {}
    local alt = devs.altimeter or devs.altitude
    local altValid = false
    if alt and type(alt.getHeight) == "function" then
        local ok, val = pcall(function() return alt.getHeight() end)
        if ok and type(val) == "number" then
            altValid = true
        end
    end
    if altValid then
        passed = passed + 1
    else
        table.insert(errors, "SensorNode: Altimeter missing or invalid (critical)")
    end

    local gyro = devs.gyroscope or devs.gimbal
    local gyroValid = false
    if gyro and type(gyro.getAngles) == "function" then
        local ok, val = pcall(function() return gyro.getAngles() end)
        if ok and type(val) == "table" then
            gyroValid = true
        end
    end
    if gyroValid then
        passed = passed + 1
    else
        table.insert(errors, "SensorNode: Gyroscope / Gimbal sensor missing or invalid (critical)")
    end

    local vel = devs.velocitySensor or (devs.velocitySensors and (devs.velocitySensors.x or devs.velocitySensors[1]))
    if vel and type(vel.getVelocity) == "function" then
        passed = passed + 1
    else
        table.insert(warnings, "SensorNode: Velocity sensor missing or invalid (advisory)")
    end

    return passed
end

--- Sensor Node 자가진단
---@param options table? { modem, devices }
---@return table BIT 결과
function preflight_bit.checkSensorNode(options)
    local opts = options or {}
    local errors = {}
    local warnings = {}
    local passed = 0

    local hasModem = preflight_bit.checkModem(opts.modem)
    if hasModem then
        passed = passed + 1
    else
        table.insert(errors, "SensorNode: Wireless modem missing or invalid (critical)")
    end

    passed = checkSensorDevices(opts.devices, errors, warnings, passed)

    local result = preflight_bit.evaluateStatus(errors, warnings, passed)
    result.node = "SENSOR_NODE"
    return result
end

--- TCA Thruster Node 자가진단
---@param options table? { modem, engine, transmission, thrusters }
---@return table BIT 결과
function preflight_bit.checkThrusterNode(options)
    local opts = options or {}
    local errors = {}
    local warnings = {}
    local passed = 0

    local hasModem = preflight_bit.checkModem(opts.modem)
    if hasModem then
        passed = passed + 1
    else
        table.insert(errors, "TCA: Wireless modem missing or invalid (critical)")
    end

    local thCount = 0
    if opts.thrusters and type(opts.thrusters) == "table" then
        thCount = #opts.thrusters
    end

    local hasActuator = (opts.transmission and type(opts.transmission.setSignal) == "function") or
                        (opts.engine and (type(opts.engine.getBurnTime) == "function" or type(opts.engine.getGeneratedSpeed) == "function")) or
                        (thCount > 0)

    if hasActuator then
        passed = passed + 1
    else
        table.insert(warnings, "TCA: No propulsion actuator or engine bound (advisory)")
    end

    local result = preflight_bit.evaluateStatus(errors, warnings, passed)
    result.node = "TCA_NODE"
    return result
end

--- MFD Display Node 자가진단
---@param options table? { modem, monitor }
---@return table BIT 결과
function preflight_bit.checkMfdNode(options)
    local opts = options or {}
    local errors = {}
    local warnings = {}
    local passed = 0

    local hasModem = preflight_bit.checkModem(opts.modem)
    if hasModem then
        passed = passed + 1
    else
        table.insert(errors, "MFD: Wireless modem missing or invalid (critical)")
    end

    local mon = opts.monitor
    if not mon and peripheral and peripheral.find then
        mon = peripheral.find("monitor")
    end

    if mon and type(mon.write) == "function" and type(mon.setCursorPos) == "function" then
        passed = passed + 1
    else
        table.insert(errors, "MFD: Primary monitor display missing or invalid (critical)")
    end

    local result = preflight_bit.evaluateStatus(errors, warnings, passed)
    result.node = "MFD_NODE"
    return result
end

--- 역할 문자열 또는 노드 ID에 따른 범용 BIT 실행 편의 함수
---@param role string|number
---@param options table?
---@return table BIT 결과
function preflight_bit.run(role, options)
    if role == "01_vas" or role == "vas" or role == "central_core" or role == 1 then
        return preflight_bit.checkCentralCore(options)
    elseif role == "02_sensor" or role == "sensor" or role == "sensor_manager" or role == 2 then
        return preflight_bit.checkSensorNode(options)
    elseif role == "03_tca" or role == "tca" or role == "thruster_node" or role == 3 then
        return preflight_bit.checkThrusterNode(options)
    elseif role == "04_mfd" or role == "mfd" or role == "mfd_cockpit" or role == 4 then
        return preflight_bit.checkMfdNode(options)
    end
    return preflight_bit.evaluateStatus({ "Unknown node role: " .. tostring(role) }, {}, 0)
end

return preflight_bit
