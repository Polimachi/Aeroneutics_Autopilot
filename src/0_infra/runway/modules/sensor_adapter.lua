-- src/0_infra/runway/modules/sensor_adapter.lua
-- CC:Avionics sensor adapter & optional wired peripheral scanner for Runway

local sensor_adapter = {}

local okSensors, sensors = pcall(require, "avionics_sensors")
if not okSensors then sensors = nil end

local MAX_TILT_DEG = 10.0
local MAX_HEAVE_MPS = 2.5
local RECONNECT_INTERVAL_SEC = 1.0

local function scan_wired(state)
    local ri = peripheral.wrap and peripheral.wrap("redstone_integrator_0") or peripheral.find("redstone_integrator")
    local clutch = peripheral.wrap and peripheral.wrap("carrier_arresting_clutch")
    local disp = (peripheral.wrap and peripheral.wrap("wind_display_link")) or peripheral.find("display_link")
    state.wired.integrator = ri
    state.wired.clutch = clutch
    state.wired.windDisplay = disp
    return ri ~= nil, clutch ~= nil, disp ~= nil
end

local function scan_dynamic_avionics(state)
    if sensors then
        state.devices.gimbal = sensors.gimbal.find({ preferred_side = state.preferredSide })
        state.devices.altitude = sensors.altitude.find({ preferred_side = state.preferredSide })
        state.devices.velocity = sensors.velocity.find({ preferred_side = state.preferredSide })
    elseif peripheral and peripheral.find then
        state.devices.gimbal = peripheral.find("gimbal_sensor") or peripheral.find("avionics:gimbal_sensor")
        state.devices.altitude = peripheral.find("altitude_sensor") or peripheral.find("avionics:altitude_sensor")
        state.devices.velocity = peripheral.find("velocity_sensor") or peripheral.find("avionics:velocity_sensor")
    end
    return state.devices.gimbal ~= nil, state.devices.altitude ~= nil, state.devices.velocity ~= nil
end

function sensor_adapter.create(mode, preferredSide)
    local state = {
        mode = mode or "DYNAMIC",
        preferredSide = preferredSide,
        devices = { gimbal = nil, altitude = nil, velocity = nil },
        wired = { integrator = nil, clutch = nil, windDisplay = nil },
        lastReconnectAttempt = 0.0,
        isHealthy = false,
    }
    local adapter = {}

    function adapter:evaluate_deck_stability(pitch, roll, vy)
        local p, r, v = pitch or 0.0, roll or 0.0, vy or 0.0
        local tilt = math.sqrt(p * p + r * r)
        local isStable = (tilt <= MAX_TILT_DEG) and (math.abs(v) <= MAX_HEAVE_MPS)
        return isStable and "STABLE" or "DANGEROUS", isStable, tilt
    end

    function adapter:scan_peripherals()
        local gOk, aOk, vOk = scan_dynamic_avionics(state)
        local riOk, clOk, wdOk = false, false, false
        if peripheral then
            riOk, clOk, wdOk = scan_wired(state)
        end
        if state.mode == "DYNAMIC" then
            state.isHealthy = gOk and aOk and vOk
        else
            state.isHealthy = true
        end
        return state.isHealthy, {
            gimbal = gOk, altitude = aOk, velocity = vOk,
            redstoneIntegrator = riOk, carrierClutch = clOk, windDisplay = wdOk,
        }
    end

    function adapter:get_wired_devices()
        return state.wired
    end

    function adapter:read_kinematics()
        local kin = {
            velocity = { vx = 0.0, vy = 0.0, vz = 0.0 },
            acceleration = { ax = 0.0, ay = 0.0, az = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, yaw = 0.0 },
            angularRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
        }
        if not state.isHealthy and state.mode == "DYNAMIC" then
            return nil, "SENSORS_NOT_HEALTHY"
        end
        if state.devices.gimbal and sensors then
            local a = sensors.gimbal.get_angles(state.devices.gimbal)
            if a then kin.attitude.pitch, kin.attitude.roll, kin.attitude.yaw = a.pitch or 0, a.roll or 0, a.yaw or 0 end
            local r = sensors.gimbal.get_angular_rates(state.devices.gimbal)
            if r then kin.angularRates = { pitchRate = r.pitch_rate or 0, rollRate = r.roll_rate or 0, yawRate = r.yaw_rate or 0 } end
        end
        if state.devices.velocity and sensors then
            local v3 = sensors.velocity.read_vector3({ preferred_side = state.preferredSide })
            if v3 then kin.velocity = { vx = v3.vx or 0, vy = v3.vy or 0, vz = v3.vz or 0 } end
        end
        return kin, nil
    end

    function adapter:check_auto_reconnect(nowSec)
        local t = nowSec or (os.clock and os.clock() or 0)
        if not state.isHealthy and (t - state.lastReconnectAttempt) >= RECONNECT_INTERVAL_SEC then
            state.lastReconnectAttempt = t
            local ok = adapter:scan_peripherals()
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
