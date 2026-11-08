-- src/0_infra/landing_pad/modules/sensor_adapter.lua
-- CC:Avionics standard sensor adapter and deck stability evaluator for Landing Pad

local sensor_adapter = {}

local okSensors, sensors = pcall(require, "avionics_sensors")
if not okSensors then
    sensors = nil
end

local MAX_TILT_DEG = 10.0
local MAX_HEAVE_MPS = 2.5
local RECONNECT_INTERVAL_SEC = 1.0

function sensor_adapter.create(mode, preferredSide)
    local state = {
        mode = mode or "DYNAMIC",
        preferredSide = preferredSide,
        devices = {
            gimbal = nil,
            altitude = nil,
            velocity = nil
        },
        deviceNames = {
            gimbal = nil,
            altitude = nil,
            velocity = nil
        },
        lastReconnectAttempt = 0.0,
        isHealthy = false
    }

    local adapter = {}

    function adapter:evaluate_deck_stability(pitch, roll, vy)
        local p = pitch or 0.0
        local r = roll or 0.0
        local v = vy or 0.0

        local tilt = math.sqrt(p * p + r * r)
        local isStable = (tilt <= MAX_TILT_DEG) and (math.abs(v) <= MAX_HEAVE_MPS)
        local status = isStable and "STABLE" or "DANGEROUS"
        local permitted = isStable

        return status, permitted, tilt
    end

    function adapter:scan_peripherals()
        local report = {
            gimbal = false,
            altitude = false,
            velocity = false
        }

        if sensors then
            local gDev, gName = sensors.gimbal.find({ preferred_side = state.preferredSide })
            if gDev then
                state.devices.gimbal = gDev
                state.deviceNames.gimbal = gName
                report.gimbal = true
            else
                state.devices.gimbal = nil
                state.deviceNames.gimbal = nil
            end

            local aDev, aName = sensors.altitude.find({ preferred_side = state.preferredSide })
            if aDev then
                state.devices.altitude = aDev
                state.deviceNames.altitude = aName
                report.altitude = true
            else
                state.devices.altitude = nil
                state.deviceNames.altitude = nil
            end

            local vDev, vName = sensors.velocity.find({ preferred_side = state.preferredSide })
            if vDev then
                state.devices.velocity = vDev
                state.deviceNames.velocity = vName
                report.velocity = true
            else
                state.devices.velocity = nil
                state.deviceNames.velocity = nil
            end
        else
            -- Direct peripheral scan fallback if library not in path
            local gDev = peripheral.find("gimbal_sensor") or peripheral.find("avionics:gimbal_sensor")
            if gDev then state.devices.gimbal = gDev; report.gimbal = true end

            local aDev = peripheral.find("altitude_sensor") or peripheral.find("avionics:altitude_sensor")
            if aDev then state.devices.altitude = aDev; report.altitude = true end

            local vDev = peripheral.find("velocity_sensor") or peripheral.find("avionics:velocity_sensor")
            if vDev then state.devices.velocity = vDev; report.velocity = true end
        end

        if state.mode == "DYNAMIC" then
            state.isHealthy = (report.gimbal and report.altitude and report.velocity)
        else
            state.isHealthy = true
        end

        return state.isHealthy, report
    end

    function adapter:read_kinematics()
        local kin = {
            velocity = { vx = 0.0, vy = 0.0, vz = 0.0 },
            acceleration = { ax = 0.0, ay = 0.0, az = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, yaw = 0.0 },
            angularRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 }
        }

        if not state.isHealthy and state.mode == "DYNAMIC" then
            return nil, "SENSORS_NOT_HEALTHY"
        end

        if state.devices.gimbal and sensors then
            local angles, errA = sensors.gimbal.get_angles(state.devices.gimbal)
            if angles then
                kin.attitude.pitch = angles.pitch or 0.0
                kin.attitude.roll = angles.roll or 0.0
                kin.attitude.yaw = angles.yaw or 0.0
            end
            local rates, errR = sensors.gimbal.get_angular_rates(state.devices.gimbal)
            if rates then
                kin.angularRates.pitchRate = rates.pitch_rate or rates.wx or 0.0
                kin.angularRates.rollRate = rates.roll_rate or rates.wz or 0.0
                kin.angularRates.yawRate = rates.yaw_rate or rates.wy or 0.0
            end
        end

        if state.devices.velocity and sensors then
            local v3, errV = sensors.velocity.read_vector3({ preferred_side = state.preferredSide })
            if v3 then
                kin.velocity.vx = v3.vx or 0.0
                kin.velocity.vy = v3.vy or 0.0
                kin.velocity.vz = v3.vz or 0.0
            else
                local vScalar = sensors.velocity.get_velocity(state.devices.velocity)
                if vScalar then
                    kin.velocity.vy = vScalar
                end
            end
        end

        if state.devices.altitude and sensors then
            local alt = sensors.altitude.get_height(state.devices.altitude)
            kin.altitude = alt or 64.0
        end

        return kin, nil
    end

    function adapter:check_auto_reconnect(nowSec)
        local now = nowSec or (os.clock and os.clock() or 0)
        if (now - state.lastReconnectAttempt) >= RECONNECT_INTERVAL_SEC then
            state.lastReconnectAttempt = now
            local ok, report = adapter:scan_peripherals()
            return ok
        end
        return state.isHealthy
    end

    function adapter:is_healthy()
        return state.isHealthy
    end

    return adapter
end

return sensor_adapter
