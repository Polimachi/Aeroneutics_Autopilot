-- src/1_control/vas/modules/sensor_pipeline.lua
-- VAS Sensor Pipeline & 3D Kinematics Module (v1.15.0 / VICD-Spec)

local quat = require("quat")

local sensor_pipeline = {}

local okSensors, sensors = pcall(require, "avionics_sensors")
if not okSensors then
    sensors = nil
end

local function find_peripheral_typed(role, roleCfg)
    local prefSide = type(roleCfg) == "table" and roleCfg.preferredSide or nil
    local pType = type(roleCfg) == "table" and roleCfg.peripheralType or tostring(roleCfg or "")

    if sensors and sensors[role] and sensors[role].find then
        local dev = sensors[role].find({ preferred_side = prefSide })
        if dev then return dev end
    end

    if prefSide and peripheral and peripheral.getType and peripheral.getType(prefSide) == pType then
        return peripheral.wrap(prefSide)
    end
    if peripheral and peripheral.find then
        local dev = peripheral.find(pType)
        if dev then return dev end
    end
    local c = string.find(pType, ":")
    local bare = c and string.sub(pType, c + 1) or ("avionics:" .. pType)
    if prefSide and peripheral and peripheral.getType and peripheral.getType(prefSide) == bare then
        return peripheral.wrap(prefSide)
    end
    return peripheral and peripheral.find and peripheral.find(bare) or nil
end

function sensor_pipeline.init(sensorsConfig)
    local cfg = sensorsConfig or {}
    local devices, roles, faults = {}, cfg.roles or {}, {}
    for role, roleCfg in pairs(roles) do
        faults[role] = 0
        devices[role] = find_peripheral_typed(role, roleCfg)
    end
    return {
        config = cfg,
        roles = roles,
        devices = devices,
        faultCounters = faults,
        lastRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
        lastCom = {
            attitude = { pitch = 0.0, roll = 0.0, yaw = 0.0, heading = 0.0 },
            rates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
            dynamics = { altitudeY = 0.0, verticalSpeed = 0.0, velocity = { vx = 0.0, vy = 0.0, vz = 0.0 } },
            fuel = 1.0
        }
    }
end

local function sample_gimbal(dev)
    local angles = sensors and sensors.gimbal and sensors.gimbal.get_angles(dev)
    if not angles then
        local a = dev.getAngles and dev.getAngles()
        angles = (type(a) == "table") and { pitch = a.pitch or a[1] or 0.0, roll = a.roll or a[2] or 0.0, yaw = a.yaw or a[3] or 0.0 } or { pitch = 0.0, roll = 0.0, yaw = 0.0 }
    end
    local rates = sensors and sensors.gimbal and sensors.gimbal.get_angular_rates(dev)
    if not rates then
        local rt = dev.getAngularRates and dev.getAngularRates()
        rates = (type(rt) == "table") and {
            pitch_rate = rt.pitchRate or rt.pitch_rate or rt.wx or rt[1] or 0.0,
            roll_rate = rt.rollRate or rt.roll_rate or rt.wz or rt[2] or 0.0,
            yaw_rate = rt.yawRate or rt.yaw_rate or rt.wy or rt[3] or 0.0,
        } or { pitch_rate = 0.0, roll_rate = 0.0, yaw_rate = 0.0 }
    end
    return {
        pitch = angles.pitch or 0.0,
        roll = angles.roll or 0.0,
        yaw = angles.yaw or 0.0,
        pitchRate = rates.pitch_rate or rates.wx or 0.0,
        rollRate = rates.roll_rate or rates.wz or 0.0,
        yawRate = rates.yaw_rate or rates.wy or 0.0,
    }
end

local function sample_altitude(dev)
    local alt = sensors and sensors.altitude and sensors.altitude.get_height(dev)
    if alt == nil then
        alt = (dev.getHeight and dev.getHeight()) or (dev.getAltitude and dev.getAltitude()) or 0.0
    end
    local vy = sensors and sensors.altitude and sensors.altitude.get_vertical_speed(dev)
    if vy == nil then
        vy = (dev.getVerticalSpeed and dev.getVerticalSpeed()) or 0.0
    end
    return { altitude = alt, verticalSpeed = vy }
end

local function sample_velocity(dev, roleCfg)
    local pref = roleCfg and (type(roleCfg) == "table" and roleCfg.preferredSide or nil)
    local v3 = sensors and sensors.velocity and sensors.velocity.read_vector3({ preferred_side = pref })
    if v3 then
        return { vx = v3.vx or 0.0, vy = v3.vy or 0.0, vz = v3.vz or 0.0 }
    end
    local v = (sensors and sensors.velocity and sensors.velocity.get_velocity(dev)) or (dev.getVelocity and dev.getVelocity())
    if type(v) == "table" then
        return { vx = v.x or v.vx or v[1] or 0.0, vy = v.y or v.vy or v[2] or 0.0, vz = v.z or v.vz or v[3] or 0.0 }
    elseif type(v) == "number" then
        local axis = (sensors and sensors.velocity and sensors.velocity.get_axis and sensors.velocity.get_axis(dev))
            or (dev.getAxis and dev.getAxis()) or "x"
        axis = string.lower(tostring(axis))
        return { vx = (axis == "x") and v or 0.0, vy = (axis == "y") and v or 0.0, vz = (axis == "z") and v or 0.0 }
    end
    return { vx = 0.0, vy = 0.0, vz = 0.0 }
end

local function sample_fuel(dev)
    if dev.tanks then
        local t = dev.tanks()
        local t0 = (type(t) == "table" and t[1]) or {}
        local amt, cap = t0.amount or 1000, t0.capacity or 1000
        return { amount = amt, capacity = cap, fuelRatio = (cap > 0) and (amt / cap) or 1.0 }
    elseif dev.getFluidAmount and dev.getCapacity then
        local amt, cap = dev.getFluidAmount() or 0, dev.getCapacity() or 1
        return { amount = amt, capacity = cap, fuelRatio = (cap > 0) and (amt / cap) or 1.0 }
    elseif dev.getEnergyStored and dev.getMaxEnergyStored then
        local amt, cap = dev.getEnergyStored() or 0, dev.getMaxEnergyStored() or 1
        return { amount = amt, capacity = cap, fuelRatio = (cap > 0) and (amt / cap) or 1.0 }
    end
    return { amount = 1000, capacity = 1000, fuelRatio = 1.0 }
end

local function sample_device_role(role, dev, roleCfg)
    if not dev then return nil end
    if role == "gimbal" then return sample_gimbal(dev)
    elseif role == "altitude" then return sample_altitude(dev)
    elseif role == "velocity" then return sample_velocity(dev, roleCfg)
    elseif role == "fuel" then return sample_fuel(dev)
    end
    return dev
end

function sensor_pipeline.sample_all(state)
    local raw = {}
    local roles = state.roles or {}
    local faults = state.faultCounters or {}

    for role, roleCfg in pairs(roles) do
        local dev = state.devices and state.devices[role]
        local ok, val = false, nil
        if dev then
            ok, val = pcall(sample_device_role, role, dev, roleCfg)
        end
        if ok and type(val) == "table" then
            raw[role] = val
            raw[role .. "Ok"] = true
            faults[role] = 0
        else
            if state.devices then state.devices[role] = nil end
            faults[role] = (faults[role] or 0) + 1
            raw[role .. "Ok"] = false
            local reDev = find_peripheral_typed(role, roleCfg)
            if reDev and state.devices then
                state.devices[role] = reDev
            end
        end
    end

    state.faultCounters = faults
    return raw
end

function sensor_pipeline.evaluate_health(raw, roles)
    local h = {
        gimbal = raw.gimbalOk == true,
        altitude = raw.altitudeOk == true,
        velocity = raw.velocityOk == true,
        fuel = raw.fuelOk == true,
        isAttitudeValid = raw.gimbalOk == true,
        isAltitudeValid = raw.altitudeOk == true,
        isVelocityValid = raw.velocityOk == true,
        isFuelValid = raw.fuelOk == true,
        isAirspeedValid = raw.velocityOk == true
    }

    local ok = true
    if roles then
        for role, roleCfg in pairs(roles) do
            if roleCfg.required ~= false and not h[role] then
                ok = false
                break
            end
        end
    else
        ok = h.gimbal and h.altitude and h.velocity and h.fuel
    end

    return h, ok
end

local function compute_lever_offsets(g, alt, vel, lastCom, cfg)
    local rollDeg = g.rollRate or (lastCom.rates and lastCom.rates.rollRate) or 0.0
    local pitchDeg = g.pitchRate or (lastCom.rates and lastCom.rates.pitchRate) or 0.0
    local yawDeg = g.yawRate or (lastCom.rates and lastCom.rates.yawRate) or 0.0
    local pRad, qRad, rRad = math.rad(rollDeg), math.rad(pitchDeg), math.rad(yawDeg)
    local thDeg = g.pitch or (lastCom.attitude and lastCom.attitude.pitch) or 0.0
    local phiDeg = g.roll or (lastCom.attitude and lastCom.attitude.roll) or 0.0
    local thRad, phiRad = math.rad(thDeg), math.rad(phiDeg)

    local altCfg = (cfg and cfg.roles and cfg.roles.altitude) or {}
    local rA = altCfg.leverArmOffset or {}
    local ra_dx = rA.dx or 0.0
    local ra_dy = rA.dy or 0.0
    local ra_dz = rA.dz or 0.0
    local dh = ra_dx * math.sin(thRad) - ra_dy * math.sin(phiRad) * math.cos(thRad)
             - ra_dz * (math.cos(thRad) * math.cos(phiRad) - 1.0)
    local rawAlt = alt.altitude or (lastCom.dynamics and lastCom.dynamics.altitudeY) or 0.0
    local altCoM = rawAlt - dh - (altCfg.zeroBias or 0.0)

    local velCfg = (cfg and cfg.roles and cfg.roles.velocity) or {}
    local rV = velCfg.leverArmOffset or {}
    local rv_dx = rV.dx or 0.0
    local rv_dy = rV.dy or 0.0
    local rv_dz = rV.dz or 0.0
    local dVel = lastCom.dynamics and lastCom.dynamics.velocity
    local rawVx = vel.vx or (dVel and dVel.vx) or 0.0
    local rawVy = vel.vy
    if (rawVy == nil or rawVy == 0.0) and (alt.verticalSpeed and alt.verticalSpeed ~= 0.0) then
        rawVy = alt.verticalSpeed
    elseif rawVy == nil then
        rawVy = (dVel and dVel.vy) or 0.0
    end
    local rawVz = vel.vz or (dVel and dVel.vz) or 0.0
    local vxCoM = rawVx - (qRad * rv_dz - rRad * rv_dy)
    local vyCoM = rawVy - (qRad * rv_dx - pRad * rv_dy)
    local vzCoM = rawVz - (rRad * rv_dx - pRad * rv_dz)

    return pitchDeg, rollDeg, yawDeg, altCoM, vyCoM, vxCoM, vzCoM
end

function sensor_pipeline.compensate_lever_arm(raw, lastCom, cfg, dt)
    local pDeg, qDeg, rDeg, altCoM, vyCoM, vxCoM, vzCoM = compute_lever_offsets(
        raw.gimbal or {},
        raw.altitude or {},
        raw.velocity or {},
        lastCom,
        cfg
    )

    local fuelRatio = 1.0
    if raw.fuelOk and raw.fuel then
        if raw.fuel.amount and raw.fuel.capacity and raw.fuel.capacity > 0 then
            fuelRatio = raw.fuel.amount / raw.fuel.capacity
        elseif raw.fuel.fuelRatio then
            fuelRatio = raw.fuel.fuelRatio
        end
    else
        fuelRatio = lastCom.fuel or 1.0
    end

    local thDeg = (raw.gimbal and raw.gimbal.pitch) or (lastCom.attitude and lastCom.attitude.pitch) or 0.0
    local phiDeg = (raw.gimbal and raw.gimbal.roll) or (lastCom.attitude and lastCom.attitude.roll) or 0.0
    local psiDeg = (raw.gimbal and raw.gimbal.yaw) or (lastCom.attitude and lastCom.attitude.yaw) or 0.0
    local qAtt = quat.from_euler(thDeg, phiDeg, psiDeg)
    local spd = math.sqrt(vxCoM * vxCoM + vyCoM * vyCoM + vzCoM * vzCoM)

    return {
        orientation = qAtt,
        attitude = { pitch = thDeg, roll = phiDeg, yaw = psiDeg, heading = psiDeg },
        rates = { pitchRate = pDeg, rollRate = qDeg, yawRate = rDeg },
        angularRate = { pitchRate = pDeg, rollRate = qDeg, yawRate = rDeg, x = pDeg, y = qDeg, z = rDeg },
        dynamics = { altitudeY = altCoM, verticalSpeed = vyCoM, velocity = { vx = vxCoM, vy = vyCoM, vz = vzCoM } },
        verticalSpeed = vyCoM,
        airspeed = spd,
        fuel = fuelRatio
    }
end

function sensor_pipeline.process_kinematics(state, rawSamples, dt)
    local cfg = state.config or state
    local healthMap, sensorOk = sensor_pipeline.evaluate_health(rawSamples, state.roles or cfg.roles)
    local lastCom = state.lastCom or {
        attitude = { pitch = 0, roll = 0, yaw = 0, heading = 0 },
        rates = { pitchRate = 0, rollRate = 0, yawRate = 0 },
        dynamics = { altitudeY = 0, verticalSpeed = 0, velocity = { vx = 0, vy = 0, vz = 0 } },
        fuel = 1.0
    }
    local comState = sensor_pipeline.compensate_lever_arm(rawSamples, lastCom, cfg, dt)
    if state.lastCom then state.lastCom = comState end
    return comState, healthMap, sensorOk
end

function sensor_pipeline.reconnect_faulty(state, healthMap)
    local count = 0
    local roles = state.roles or {}
    for role, roleCfg in pairs(roles) do
        if not healthMap[role] then
            local dev = find_peripheral_typed(role, roleCfg)
            if dev then
                if state.devices then state.devices[role] = dev end
                count = count + 1
            end
        end
    end
    return count
end

--- Inspect physics_assembler peripheral to determine ASSEMBLED vs DISASSEMBLED state and mass.
function sensor_pipeline.detect_contraption_state(state, periphApi)
    local papi = periphApi or peripheral
    local assembler = state and state.devices and state.devices.assembler or nil
    if not assembler and papi and type(papi.getNames) == "function" and type(papi.getType) == "function" then
        for _, name in ipairs(papi.getNames()) do
            if papi.getType(name) == "physics_assembler" then
                assembler = papi.wrap(name)
                if state and state.devices then state.devices.assembler = assembler end
                break
            end
        end
    end

    if not assembler then
        if state and state.requireAssembler == true then
            return "DISASSEMBLED", 0
        end
        return "ASSEMBLED", nil
    end

    local assembled = true
    local mass = nil
    if type(assembler.isAssembled) == "function" then
        local okA, resA = pcall(assembler.isAssembled)
        if okA and resA ~= nil then assembled = (resA == true) end
    elseif type(assembler.is_assembled) == "function" then
        local okA, resA = pcall(assembler.is_assembled)
        if okA and resA ~= nil then assembled = (resA == true) end
    end
    if type(assembler.getMass) == "function" then
        local okM, resM = pcall(assembler.getMass)
        if okM and tonumber(resM) then mass = tonumber(resM) end
    elseif type(assembler.get_mass) == "function" then
        local okM, resM = pcall(assembler.get_mass)
        if okM and tonumber(resM) then mass = tonumber(resM) end
    end

    return assembled and "ASSEMBLED" or "DISASSEMBLED", mass
end

--- Verify re-assembled thruster count and dry mass (<= 5%) against manifest, updating logical bindings.
function sensor_pipeline.verify_and_rebind_topology(state, manifest, liveActuatorNodes, liveMass, periphApi)
    if type(manifest) ~= "table" then
        return { ok = true, recalibrationRequired = false, topologyStatus = "NO_MANIFEST", reason = "NO_MANIFEST" }
    end

    local papi = periphApi or peripheral
    local nodeNames = {}
    if type(liveActuatorNodes) == "table" then
        if #liveActuatorNodes > 0 then
            for i, name in ipairs(liveActuatorNodes) do
                nodeNames[i] = tostring(name)
            end
        else
            for k, _ in pairs(liveActuatorNodes) do
                table.insert(nodeNames, tostring(k))
            end
            table.sort(nodeNames)
        end
    elseif papi and type(papi.getNames) == "function" and type(papi.getType) == "function" then
        for _, name in ipairs(papi.getNames()) do
            local pType = papi.getType(name)
            if pType == "thruster" or pType == "vector_thruster" or pType == "ion_thruster" then
                table.insert(nodeNames, name)
            end
        end
        table.sort(nodeNames)
    end

    local liveCount = #nodeNames
    local expectedCount = tonumber(manifest.thrusterCount) or 0
    if expectedCount > 0 and liveCount ~= expectedCount then
        if state then
            state.recalibrationRequired = true
            state.topologyStatus = "RECALIBRATION_REQUIRED"
        end
        return {
            ok = false,
            recalibrationRequired = true,
            topologyStatus = "RECALIBRATION_REQUIRED",
            reason = "THRUSTER_COUNT_MISMATCH",
            expectedCount = expectedCount,
            liveCount = liveCount,
        }
    end

    local expectedMass = tonumber(manifest.totalDryMass) or 0
    local measuredMass = tonumber(liveMass)
    if expectedMass > 0 and measuredMass and measuredMass > 0 then
        local deltaRatio = math.abs(measuredMass - expectedMass) / expectedMass
        if deltaRatio > 0.05 then
            if state then
                state.recalibrationRequired = true
                state.topologyStatus = "RECALIBRATION_REQUIRED"
            end
            return {
                ok = false,
                recalibrationRequired = true,
                topologyStatus = "RECALIBRATION_REQUIRED",
                reason = "MASS_DELTA_EXCEEDED",
                deltaRatio = deltaRatio,
            }
        end
    end

    local bindingMap = {}
    for i, name in ipairs(nodeNames) do
        bindingMap[i] = name
    end
    if state then
        state.logicalBindingMap = bindingMap
        state.recalibrationRequired = false
        state.topologyStatus = "REBOUND"
    end
    return {
        ok = true,
        recalibrationRequired = false,
        topologyStatus = "REBOUND",
        bindingMap = bindingMap,
        liveCount = liveCount,
    }
end

local function ensure_dr_state(state)
    state.drState = state.drState or {
        pos = { x = 0.0, z = 0.0 },
        lastValidGpsMs = nil,
        gpsBlackoutMs = 0,
        navQuality = "GOOD",
        drHoldoverActive = false,
        holdLevelActive = false,
        blendTicksRemaining = 0,
        blendStart = nil,
        blendTarget = nil,
        blendTotalTicks = 10,
    }
    return state.drState
end

--- Advance 1.5s Dead-Reckoning GPS hold-over, chunk-border spike blending, and HOLD_LEVEL guard.
function sensor_pipeline.step_gps_dr(state, gpsSample, comState, dt, nowMs)
    local dr = ensure_dr_state(state)
    local dtSec = math.max(0.0, math.min(0.5, tonumber(dt) or 0.05))
    local now = tonumber(nowMs) or ((os.epoch and os.epoch("utc")) or 0)
    local vel = (comState and comState.dynamics and comState.dynamics.velocity) or {}
    local vx = tonumber(vel.vx) or 0.0
    local vz = tonumber(vel.vz) or 0.0

    local fixPos = type(gpsSample) == "table" and (gpsSample.position or gpsSample.pos) or nil
    local hasFix = type(fixPos) == "table"
        and tonumber(fixPos.x) ~= nil and tonumber(fixPos.z) ~= nil
        and gpsSample.navQuality ~= "LOST"
        and gpsSample.status ~= "NO_FIX"
        and gpsSample.status ~= "FAIL_GEOMETRY"

    if hasFix then
        local fx = tonumber(fixPos.x)
        local fz = tonumber(fixPos.z)
        local dx = fx - dr.pos.x
        local dz = fz - dr.pos.z
        local dist = math.sqrt(dx * dx + dz * dz)
        if dr.lastValidGpsMs ~= nil and (dr.holdLevelActive or dr.drHoldoverActive or dist > 4.0) then
            local totalTicks = dr.blendTotalTicks or 10
            dr.blendStart = { x = dr.pos.x, z = dr.pos.z }
            dr.blendTarget = { x = fx, z = fz }
            dr.blendTicksRemaining = totalTicks
        end
        if dr.blendTicksRemaining > 0 and dr.blendTarget and dr.blendStart then
            local total = dr.blendTotalTicks or 10
            local done = (total - dr.blendTicksRemaining + 1)
            local ratio = math.min(1.0, done / math.max(1, total))
            dr.pos.x = dr.blendStart.x + (dr.blendTarget.x - dr.blendStart.x) * ratio
            dr.pos.z = dr.blendStart.z + (dr.blendTarget.z - dr.blendStart.z) * ratio
            dr.blendTicksRemaining = dr.blendTicksRemaining - 1
            if dr.blendTicksRemaining <= 0 then
                dr.pos.x = dr.blendTarget.x
                dr.pos.z = dr.blendTarget.z
            end
        else
            dr.pos.x = fx
            dr.pos.z = fz
        end
        dr.lastValidGpsMs = now
        dr.gpsBlackoutMs = 0
        dr.drHoldoverActive = false
        dr.holdLevelActive = false
        dr.navQuality = gpsSample.navQuality or "GOOD"
    else
        dr.pos.x = dr.pos.x + vx * dtSec
        dr.pos.z = dr.pos.z + vz * dtSec
        local blackout = (dr.lastValidGpsMs and (now - dr.lastValidGpsMs)) or ((dr.gpsBlackoutMs or 0) + math.floor(dtSec * 1000))
        if blackout < 0 then blackout = 0 end
        dr.gpsBlackoutMs = blackout
        dr.navQuality = (type(gpsSample) == "table" and gpsSample.navQuality) or "LOST"
        if blackout > 1500 then
            dr.drHoldoverActive = false
            dr.holdLevelActive = true
        else
            dr.drHoldoverActive = true
            dr.holdLevelActive = false
        end
    end

    return {
        pos = { x = dr.pos.x, z = dr.pos.z },
        navQuality = dr.navQuality,
        drHoldoverActive = dr.drHoldoverActive,
        holdLevelActive = dr.holdLevelActive,
        blackoutMs = dr.gpsBlackoutMs,
    }
end

return sensor_pipeline
