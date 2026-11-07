-- VAS Sensor Pipeline & 3D Kinematics Module (v1.4.2 / VICD-Spec)
local quat = require("quat")
local sensor_pipeline = {}

local function find_peripheral_typed(pType, prefSide)
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
        devices[role] = find_peripheral_typed(roleCfg.peripheralType or roleCfg, roleCfg.preferredSide)
    end
    return {
        config = cfg, roles = roles, devices = devices, faultCounters = faults,
        lastRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
        lastCom = {
            attitude = { pitch = 0.0, roll = 0.0, yaw = 0.0, heading = 0.0 },
            rates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
            dynamics = { altitudeY = 0.0, verticalSpeed = 0.0, velocity = { vx = 0.0, vy = 0.0, vz = 0.0 } },
            fuel = 1.0
        }
    }
end

local function sample_device_role(role, dev)
    if not dev then return nil end
    if dev.getReading then return dev.getReading() end
    if role == "gimbal" then
        local a, rt = dev.getAngles and dev.getAngles(), dev.getAngularRates and dev.getAngularRates()
        local p = (a and (a.pitch or a[1])) or 0.0
        local r = (a and (a.roll or a[2])) or 0.0
        local dp = (rt and (rt.pitchRate or rt[1])) or 0.0
        local dr = (rt and (rt.rollRate or rt[2])) or 0.0
        local dy = (rt and (rt.yawRate or rt[3])) or 0.0
        return { pitch = p, roll = r, yaw = 0.0, pitchRate = dp, rollRate = dr, yawRate = dy }
    elseif role == "altitude" then
        local a = (dev.getAltitude and dev.getAltitude()) or 0.0
        local vy = (dev.getVerticalSpeed and dev.getVerticalSpeed()) or 0.0
        return { altitude = a, verticalSpeed = vy }
    elseif role == "velocity" then
        local v = (dev.getVelocity and dev.getVelocity()) or {}
        return { vx = v.x or v.vx or v[1] or 0.0, vy = v.y or v.vy or v[2] or 0.0, vz = v.z or v.vz or v[3] or 0.0 }
    elseif role == "fuel" and dev.tanks then
        local t = dev.tanks()
        local t0 = (type(t) == "table" and t[1]) or {}
        return { amount = t0.amount or 1000, capacity = t0.capacity or 1000 }
    end
    return dev
end

function sensor_pipeline.sample_all(state)
    local raw = {}
    local roles, faults = state.roles or {}, state.faultCounters or {}
    for role, roleCfg in pairs(roles) do
        local dev = state.devices and state.devices[role]
        local ok, val = false, nil
        if dev then ok, val = pcall(sample_device_role, role, dev) end
        if ok and type(val) == "table" then
            raw[role], raw[role .. "Ok"], faults[role] = val, true, 0
        else
            if state.devices then state.devices[role] = nil end
            faults[role] = (faults[role] or 0) + 1
            raw[role .. "Ok"] = false
            local reDev = find_peripheral_typed(roleCfg.peripheralType or roleCfg, roleCfg.preferredSide)
            if reDev and state.devices then state.devices[role] = reDev end
        end
    end
    state.faultCounters = faults
    return raw
end

function sensor_pipeline.evaluate_health(raw, roles)
    local h = {
        gimbal = raw.gimbalOk == true, altitude = raw.altitudeOk == true,
        velocity = raw.velocityOk == true, fuel = raw.fuelOk == true,
        isAttitudeValid = raw.gimbalOk == true, isAltitudeValid = raw.altitudeOk == true,
        isVelocityValid = raw.velocityOk == true, isFuelValid = raw.fuelOk == true,
        isAirspeedValid = raw.velocityOk == true
    }
    local ok = true
    if roles then
        for role, roleCfg in pairs(roles) do
            if roleCfg.required ~= false and not h[role] then ok = false break end
        end
    else
        ok = h.gimbal and h.altitude and h.velocity and h.fuel
    end
    return h, ok
end

local function compute_lever_offsets(g, alt, vel, lastCom, cfg)
    local pDeg = g.pitchRate or (lastCom.rates and lastCom.rates.pitchRate) or 0.0
    local qDeg = g.rollRate or (lastCom.rates and lastCom.rates.rollRate) or 0.0
    local rDeg = g.yawRate or (lastCom.rates and lastCom.rates.yawRate) or 0.0
    local pRad, qRad, rRad = math.rad(pDeg), math.rad(qDeg), math.rad(rDeg)
    local thDeg = g.pitch or (lastCom.attitude and lastCom.attitude.pitch) or 0.0
    local phiDeg = g.roll or (lastCom.attitude and lastCom.attitude.roll) or 0.0
    local thRad, phiRad = math.rad(thDeg), math.rad(phiDeg)

    local altCfg = (cfg and cfg.roles and cfg.roles.altitude) or (cfg and cfg.altitude) or {}
    local rA = altCfg.leverArmOffset or { dx = 0.0, dy = 0.0, dz = 0.0 }
    local dh = rA.dx * math.sin(thRad) - rA.dy * math.sin(phiRad) * math.cos(thRad)
             - rA.dz * (math.cos(thRad) * math.cos(phiRad) - 1.0)
    local rawAlt = alt.altitude or (lastCom.dynamics and lastCom.dynamics.altitudeY) or 0.0
    local altCoM = rawAlt - dh - (altCfg.zeroBias or 0.0)

    local velCfg = (cfg and cfg.roles and cfg.roles.velocity) or (cfg and cfg.velocity) or {}
    local rV = velCfg.leverArmOffset or { dx = 0.0, dy = 0.0, dz = 0.0 }
    local dVel = lastCom.dynamics and lastCom.dynamics.velocity
    local rawVx = vel.vx or (dVel and dVel.vx) or 0.0
    local rawVy = vel.vy or alt.verticalSpeed or (lastCom.dynamics and lastCom.dynamics.verticalSpeed) or 0.0
    local rawVz = vel.vz or (dVel and dVel.vz) or 0.0
    local vxCoM = rawVx - (rRad * rV.dz - pRad * rV.dy)
    local vyCoM = rawVy - (pRad * rV.dx - qRad * rV.dz)
    local vzCoM = rawVz - (rRad * rV.dx - qRad * rV.dy)
    return pDeg, qDeg, rDeg, altCoM, vyCoM, vxCoM, vzCoM
end

function sensor_pipeline.compensate_lever_arm(raw, lastCom, cfg, dt)
    local pDeg, qDeg, rDeg, altCoM, vyCoM, vxCoM, vzCoM = compute_lever_offsets(raw.gimbal or {}, raw.altitude or {}, raw.velocity or {}, lastCom, cfg)
    local fuelRatio = 1.0
    if raw.fuelOk and raw.fuel then
        if raw.fuel.amount and raw.fuel.capacity and raw.fuel.capacity > 0 then
            fuelRatio = raw.fuel.amount / raw.fuel.capacity
        elseif raw.fuel.fuelRatio then fuelRatio = raw.fuel.fuelRatio end
    else
        fuelRatio = lastCom.fuel or 1.0
    end

    local thDeg = (raw.gimbal and raw.gimbal.pitch) or (lastCom.attitude and lastCom.attitude.pitch) or 0.0
    local phiDeg = (raw.gimbal and raw.gimbal.roll) or (lastCom.attitude and lastCom.attitude.roll) or 0.0
    local psiDeg = (raw.gimbal and raw.gimbal.yaw) or (lastCom.attitude and lastCom.attitude.yaw) or 0.0
    local qAtt = quat.from_euler(thDeg, phiDeg, psiDeg)
    local spd = math.sqrt(vxCoM * vxCoM + vyCoM * vyCoM + vzCoM * vzCoM)

    return {
        orientation = qAtt, attitude = { pitch = thDeg, roll = phiDeg, yaw = psiDeg, heading = psiDeg },
        rates = { pitchRate = pDeg, rollRate = qDeg, yawRate = rDeg },
        angularRate = { pitchRate = pDeg, rollRate = qDeg, yawRate = rDeg, x = pDeg, y = qDeg, z = rDeg },
        dynamics = { altitudeY = altCoM, verticalSpeed = vyCoM, velocity = { vx = vxCoM, vy = vyCoM, vz = vzCoM } },
        verticalSpeed = vyCoM, airspeed = spd, fuel = fuelRatio
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
    local count, roles = 0, state.roles or {}
    for role, roleCfg in pairs(roles) do
        if not healthMap[role] then
            local dev = find_peripheral_typed(roleCfg.peripheralType or roleCfg, roleCfg.preferredSide)
            if dev then
                if state.devices then state.devices[role] = dev end
                count = count + 1
            end
        end
    end
    return count
end

return sensor_pipeline
