-- tests/0_infra/landing_pad/test_sensor_adapter.lua
local sensor_adapter = require("sensor_adapter")

describe("Landing pad sensor adapter and deck stability evaluator", function()
    it("evaluates deck stability: STABLE when tilt <= 10 deg and |vy| <= 2.5 m/s", function()
        local adapter = sensor_adapter.create("DYNAMIC")
        local status, permitted, tilt = adapter:evaluate_deck_stability(1.2, -2.5, -0.15)
        assert_eq(status, "STABLE")
        assert_true(permitted)
        assert_near(tilt, 2.773, 1e-2)
    end)

    it("evaluates deck stability: DANGEROUS when tilt > 10 deg or |vy| > 2.5 m/s", function()
        local adapter = sensor_adapter.create("DYNAMIC")
        local status1, permitted1 = adapter:evaluate_deck_stability(8.0, 7.0, 0.5) -- tilt = sqrt(64+49) = 10.63 > 10.0
        assert_eq(status1, "DANGEROUS")
        assert_false(permitted1)

        local status2, permitted2 = adapter:evaluate_deck_stability(2.0, 2.0, 3.0) -- vy = 3.0 > 2.5
        assert_eq(status2, "DANGEROUS")
        assert_false(permitted2)
    end)

    it("scans peripherals and enforces 3 required sensors in DYNAMIC mode", function()
        local adapter = sensor_adapter.create("DYNAMIC")
        mock.peripheral_registry({
            top = { type = "modem", dev = mock.modem({ is_wireless = true }) }
        })
        local ok, scanReport = adapter:scan_peripherals()
        assert_false(ok)
        assert_false(scanReport.gimbal)
        assert_false(scanReport.altitude)
        assert_false(scanReport.velocity)
    end)

    it("passes peripheral scan in DYNAMIC mode when all 3 sensors are present", function()
        local adapter = sensor_adapter.create("DYNAMIC")
        mock.peripheral_registry({
            gimbal_0 = { type = "gimbal_sensor", dev = mock.cc_gimbal_sensor({ pitch = 0, roll = 0, yaw = 0 }) },
            altitude_0 = { type = "altitude_sensor", dev = mock.cc_altitude_sensor({ height = 64 }) },
            velocity_0 = { type = "velocity_sensor", dev = mock.cc_velocity_sensor({ velocity = 0, axis = "Y" }) }
        })
        local ok, scanReport = adapter:scan_peripherals()
        assert_true(ok)
        assert_true(scanReport.gimbal)
        assert_true(scanReport.altitude)
        assert_true(scanReport.velocity)

        local kin, err = adapter:read_kinematics()
        assert_nil(err)
        assert_not_nil(kin)
        assert_eq(kin.attitude.pitch, 0)
        assert_eq(kin.altitude, 64)
    end)
end)
