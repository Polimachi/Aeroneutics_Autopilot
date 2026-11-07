-- Unit test suite for 1_control/vas
local quat = require("quat")
local flight_dynamics_core = require("flight_dynamics_core")
local sensor_pipeline = require("sensor_pipeline")

describe("vas quaternion math invariants", function()
    it("normalizes and calculates error quaternion", function()
        local q1 = quat.new(1.0, 0.0, 0.0, 0.0)
        assert_near(quat.norm(q1), 1.0, 1e-6)

        local q_unnorm = quat.new(2.0, 2.0, 2.0, 2.0)
        local q_norm = quat.normalize(q_unnorm)
        assert_near(quat.norm(q_norm), 1.0, 1e-6)

        -- Multiplying identity by q yields q
        local q_prod = quat.multiply(quat.identity(), q_norm)
        assert_near(q_prod.w, q_norm.w, 1e-6)
        assert_near(q_prod.x, q_norm.x, 1e-6)
        assert_near(q_prod.y, q_norm.y, 1e-6)
        assert_near(q_prod.z, q_norm.z, 1e-6)

        -- Error quaternion between identical poses has w near 1.0 and xyz near 0
        local err = quat.error_quaternion(q_norm, q_norm)
        assert_near(err.w, 1.0, 1e-6)
        assert_near(err.x, 0.0, 1e-6)
        assert_near(err.y, 0.0, 1e-6)
        assert_near(err.z, 0.0, 1e-6)
    end)
end)

describe("vas flight dynamics core and integrators", function()
    it("initializes gains and resets integrators", function()
        local fdc = flight_dynamics_core.init({
            attitude = {
                pitch = { kp = 3.0, ki = 0.1, kd = 0.4 },
                roll = { kp = 3.0, ki = 0.1, kd = 0.4 },
                yaw = { kp = 2.5, ki = 0.05, kd = 0.3 }
            }
        })
        assert_not_nil(fdc.gains.pitch)
        assert_near(fdc.gains.pitch.kp, 3.0, 1e-6)

        fdc.integrators.pitch = 2.5
        fdc.integrators.roll = -1.2
        flight_dynamics_core.reset_integrators(fdc)
        assert_near(fdc.integrators.pitch, 0.0, 1e-6)
        assert_near(fdc.integrators.roll, 0.0, 1e-6)
    end)
end)

describe("vas sensor pipeline sampling with peripheral registry", function()
    it("samples avionics gimbal, altitude, velocity and fuel sensors", function()
        local g_mock = mock.avionics_gimbal({ pitch = 5.0, roll = -2.0, yaw = 0.0, pitchRate = 0.1 })
        local a_mock = mock.avionics_altitude({ altitude = 150.0, verticalSpeed = 0.5 })
        local v_mock = mock.avionics_velocity({ vx = 10.0, vy = 0.5, vz = -3.0 })
        local f_mock = mock.fuel_tank(800, 1000)

        mock.peripheral_registry({
            top = { type = "gimbal_sensor", dev = g_mock },
            bottom = { type = "altitude_sensor", dev = a_mock },
            left = { type = "velocity_sensor", dev = v_mock },
            right = { type = "fuel", dev = f_mock }
        })

        local sp = sensor_pipeline.init({
            roles = {
                gimbal = { peripheralType = "gimbal_sensor", preferredSide = "top" },
                altitude = { peripheralType = "altitude_sensor", preferredSide = "bottom" },
                velocity = { peripheralType = "velocity_sensor", preferredSide = "left" },
                fuel = { peripheralType = "fuel", preferredSide = "right" }
            }
        })

        local raw = sensor_pipeline.sample_all(sp)
        assert_true(raw.gimbalOk)
        assert_true(raw.altitudeOk)
        assert_true(raw.velocityOk)
        assert_true(raw.fuelOk)
        assert_near(raw.gimbal.pitch, 5.0, 1e-6)
        assert_near(raw.altitude.altitude, 150.0, 1e-6)
        assert_near(raw.velocity.vx, 10.0, 1e-6)
        assert_near(raw.fuel.amount, 800, 1e-6)

        local health, allOk = sensor_pipeline.evaluate_health(raw, sp.roles)
        assert_true(allOk)
        assert_true(health.gimbal)
        assert_true(health.altitude)
    end)
end)
