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
    local pType = type(roleCfg) == "table" and (roleCfg.peripheralType or roleCfg.type) or tostring(roleCfg or "")

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

local function sample_device_role(role, dev, roleCfg)
    if not dev then return nil end

    if role == "gimbal" then
        local angles = sensors and sensors.gimbal and sensors.gimbal.get_angles(dev)
        if not angles then
            local a = dev.getAngles and dev.getAngles()
            if type(a) == "table" then
                angles = {
                    pitch = a.pitch or a[1] or 0.0,
                    roll = a.roll or a[2] or 0.0,
                    yaw = a.yaw or a[3] or 0.0
                }
            else
                angles = { pitch = 0.0, roll = 0.0, yaw = 0.0 }
            end
        end

        local rates = sensors and sensors.gimbal and sensors.gimbal.get_angular_rates(dev)
        if not rates then
            local rt = dev.getAngularRates and dev.getAngularRates()
            if type(rt) == "table" then
                rates = {
                    pitch_rate = rt.pitchRate or rt.pitch_rate or rt.wx or rt[1] or 0.0,
                    roll_rate = rt.rollRate or rt.roll_rate or rt.wz or rt[2] or 0.0,
                    yaw_rate = rt.yawRate or rt.yaw_rate or rt.wy or rt[3] or 0.0
                }
            else
                rates = { pitch_rate = 0.0, roll_rate = 0.0, yaw_rate = 0.0 }
            end
        end

        return {
            pitch = angles.pitch or 0.0,
            roll = angles.roll or 0.0,
            yaw = angles.yaw or 0.0,
            pitchRate = rates.pitch_rate or rates.wx or 0.0,
            rollRate = rates.roll_rate or rates.wz or 0.0,
            yawRate = rates.yaw_rate or rates.wy or 0.0
        }

    elseif role == "altitude" then
        local alt = sensors and sensors.altitude and sensors.altitude.get_height(dev)
        if alt == nil then
            alt = (dev.getHeight and dev.getHeight()) or (dev.getAltitude and dev.getAltitude()) or (dev.getYCoordinate and dev.getYCoordinate()) or 0.0
        end

        local vy = sensors and sensors.altitude and sensors.altitude.get_vertical_speed(dev)
        if vy == nil then
            vy = (dev.getVerticalSpeed and dev.getVerticalSpeed()) or 0.0
        end

        return { altitude = alt, verticalSpeed = vy }

    elseif role == "velocity" then
        local pref = roleCfg and (type(roleCfg) == "table" and roleCfg.preferredSide or nil)
        local v3 = sensors and sensors.velocity and sensors.velocity.read_vector3({ preferred_side = pref })
        if v3 then
            return { vx = v3.vx or 0.0, vy = v3.vy or 0.0, vz = v3.vz or 0.0 }
        else
            local v = (sensors and sensors.velocity and sensors.velocity.get_velocity(dev))
            if v == nil and dev.getVelocity then
                v = dev.getVelocity()
            end

            if type(v) == "table" then
                return {
                    vx = v.x or v.vx or v[1] or 0.0,
                    vy = v.y or v.vy or v[2] or 0.0,
                    vz = v.z or v.vz or v[3] or 0.0
                }
            elseif type(v) == "number" then
                local axis = "x"
                if sensors and sensors.velocity and sensors.velocity.get_axis then
                    axis = sensors.velocity.get_axis(dev) or "x"
                elseif dev.getAxis then
                    axis = dev.getAxis() or "x"
                end
                axis = string.lower(tostring(axis))

                local vx, vy, vz = 0.0, 0.0, 0.0
                if axis == "x" then vx = v
                elseif axis == "y" then vy = v
                elseif axis == "z" then vz = v
                end
                return { vx = vx, vy = vy, vz = vz }
            end
            return { vx = 0.0, vy = 0.0, vz = 0.0 }
        end

    elseif role == "fuel" then
        if dev.tanks then
            local t = dev.tanks()
            local t0 = (type(t) == "table" and t[1]) or {}
            local amt = t0.amount or 1000
            local cap = t0.capacity or 1000
            return { amount = amt, capacity = cap, fuelRatio = (cap > 0) and (amt / cap) or 1.0 }
        elseif dev.getFluidAmount and dev.getCapacity then
            local amt = dev.getFluidAmount() or 0
            local cap = dev.getCapacity() or 1
            return { amount = amt, capacity = cap, fuelRatio = (cap > 0) and (amt / cap) or 1.0 }
        elseif dev.getEnergyStored and dev.getMaxEnergyStored then
            local amt = dev.getEnergyStored() or 0
            local cap = dev.getMaxEnergyStored() or 1
            return { amount = amt, capacity = cap, fuelRatio = (cap > 0) and (amt / cap) or 1.0 }
        end
        return { amount = 1000, capacity = 1000, fuelRatio = 1.0 }
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
    local pDeg = g.pitchRate or (lastCom.rates and lastCom.rates.pitchRate) or 0.0
    local qDeg = g.rollRate or (lastCom.rates and lastCom.rates.rollRate) or 0.0
    local rDeg = g.yawRate or (lastCom.rates and lastCom.rates.yawRate) or 0.0
    local pRad, qRad, rRad = math.rad(pDeg), math.rad(qDeg), math.rad(rDeg)
    local thDeg = g.pitch or (lastCom.attitude and lastCom.attitude.pitch) or 0.0
    local phiDeg = g.roll or (lastCom.attitude and lastCom.attitude.roll) or 0.0
    local thRad, phiRad = math.rad(thDeg), math.rad(phiDeg)

    local altCfg = (cfg and cfg.roles and cfg.roles.altitude) or (cfg and cfg.altitude) or {}
    local rA = altCfg.leverArmOffset or {}
    local ra_dx = rA.dx or 0.0
    local ra_dy = rA.dy or 0.0
    local ra_dz = rA.dz or 0.0
    local dh = ra_dx * math.sin(thRad) - ra_dy * math.sin(phiRad) * math.cos(thRad)
             - ra_dz * (math.cos(thRad) * math.cos(phiRad) - 1.0)
    local rawAlt = alt.altitude or (lastCom.dynamics and lastCom.dynamics.altitudeY) or 0.0
    local altCoM = rawAlt - dh - (altCfg.zeroBias or 0.0)

    local velCfg = (cfg and cfg.roles and cfg.roles.velocity) or (cfg and cfg.velocity) or {}
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
        rawVy = (dVel and dVel.verticalSpeed) or 0.0
    end
    local rawVz = vel.vz or (dVel and dVel.vz) or 0.0
    local vxCoM = rawVx - (rRad * rv_dz - pRad * rv_dy)
    local vyCoM = rawVy - (pRad * rv_dx - qRad * rv_dz)
    local vzCoM = rawVz - (rRad * rv_dx - qRad * rv_dy)

    return pDeg, qDeg, rDeg, altCoM, vyCoM, vxCoM, vzCoM
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

return sensor_pipeline
