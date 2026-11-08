-- tests/0_development/sensors/test_avionics_sensors.lua
-- Unit test suite for standard CC:Avionics 4-sensor API library (avionics_sensors)

local sensors = require("avionics_sensors")

describe("avionics_sensors scope guard and peripheral discovery", function()
    it("exposes strictly the 4 supported CC:Avionics peripheral types and rejects others", function()
        assert_deep_eq(sensors.PERIPHERAL_TYPES, {
            VELOCITY = "velocity_sensor",
            ALTITUDE = "altitude_sensor",
            GIMBAL = "gimbal_sensor",
            PHYSICS_ASSEMBLER = "physics_assembler",
        })
        assert_true(sensors.is_supported_type("velocity_sensor"))
        assert_true(sensors.is_supported_type("avionics:altitude_sensor"))
        assert_true(sensors.is_supported_type("create_avionics:gimbal_sensor"))
        assert_true(sensors.is_supported_type("physics_assembler"))
        assert_false(sensors.is_supported_type("radar"))
        assert_false(sensors.is_supported_type("modem"))

        local dev, err = sensors.find("radar")
        assert_nil(dev)
        assert_not_nil(err)
        assert_true(string.find(err, "UNSUPPORTED_SENSOR_TYPE", 1, true) ~= nil)
    end)

    it("resolves preferredSide, namespace prefixes, and ship_ bridge peripherals deterministically", function()
        local g0 = mock.cc_gimbal_sensor({ pitch = 1.0, roll = 2.0 })
        local g1 = mock.cc_gimbal_sensor({ pitch = 9.0, roll = -4.0 })
        local a0 = mock.cc_altitude_sensor({ height = 120.0 })

        mock.peripheral_registry({
            ship_gimbal_sensor_0 = { type = "gimbal_sensor", dev = g0 },
            bottom = { type = "avionics:gimbal_sensor", dev = g1 },
            ship_altitude_sensor_0 = { type = "create_avionics:altitude_sensor", dev = a0 },
        })

        -- Preferred side takes priority
        local prefDev, prefName = sensors.gimbal.find({ preferred_side = "bottom" })
        assert_eq(prefName, "bottom")
        local angPref = sensors.gimbal.get_angles(prefDev)
        assert_near(angPref.pitch, 9.0, 1e-6)

        -- Fallback deterministic scan when preferred_side does not match type
        local altDev, altName = sensors.altitude.find({ preferred_side = "bottom" })
        assert_eq(altName, "ship_altitude_sensor_0")
        assert_near(sensors.altitude.get_height(altDev), 120.0, 1e-6)

        -- find_all returns sorted matches
        local allGimbals = sensors.gimbal.find_all()
        assert_eq(#allGimbals, 2)
        assert_eq(allGimbals[1].name, "bottom")
        assert_eq(allGimbals[2].name, "ship_gimbal_sensor_0")
    end)
end)

describe("velocity_sensor standard functions", function()
    it("reads single directional velocity_sensor scalar, axis, and ship bridge direction", function()
        local vs = mock.cc_velocity_sensor({ velocity = -14.25, axis = "Z" })
        local v, errV = sensors.velocity.get_velocity(vs)
        assert_nil(errV)
        assert_near(v, -14.25, 1e-6)

        local ax, errAx = sensors.velocity.get_axis(vs)
        assert_nil(errAx)
        assert_eq(ax, "z")

        local snap, errSnap = sensors.velocity.read(vs, "ship_velocity_sensor_forward_0")
        assert_nil(errSnap)
        assert_near(snap.velocity, -14.25, 1e-6)
        assert_eq(snap.axis, "z")
        assert_eq(snap.direction, "forward")
        assert_eq(snap.name, "ship_velocity_sensor_forward_0")
    end)

    it("reconstructs 3D body-frame velocity vector from orthogonal sensors and averages duplicates", function()
        mock.peripheral_registry({
            ship_velocity_sensor_lateral_0 = {
                type = "velocity_sensor",
                dev = mock.cc_velocity_sensor({ velocity = 3.0, axis = "x" }),
            },
            ship_velocity_sensor_vertical_0 = {
                type = "velocity_sensor",
                dev = mock.cc_velocity_sensor({ velocity = 4.0, axis = "y" }),
            },
            ship_velocity_sensor_forward_0 = {
                type = "velocity_sensor",
                dev = mock.cc_velocity_sensor({ velocity = 10.0, axis = "z" }),
            },
            ship_velocity_sensor_forward_1 = {
                type = "velocity_sensor",
                dev = mock.cc_velocity_sensor({ velocity = 14.0, axis = "z" }),
            },
        })

        local vec, err = sensors.velocity.read_vector3()
        assert_nil(err)
        assert_eq(vec.sensor_count, 4)
        assert_near(vec.x, 3.0, 1e-6)
        assert_near(vec.y, 4.0, 1e-6)
        assert_near(vec.z, 12.0, 1e-6) -- averaged (10 + 14) / 2
        assert_near(vec.vx, 3.0, 1e-6)
        assert_near(vec.vy, 4.0, 1e-6)
        assert_near(vec.vz, 12.0, 1e-6)
        assert_true(vec.axes_present.x and vec.axes_present.y and vec.axes_present.z)
        assert_near(vec.ship.lateral, 3.0, 1e-6)
        assert_near(vec.ship.vertical, 4.0, 1e-6)
        assert_near(vec.ship.forward, 12.0, 1e-6)
        assert_near(vec.speed, 13.0, 1e-6) -- sqrt(3^2 + 4^2 + 12^2) = 13
        assert_near(vec.horizontal_speed, math.sqrt(9.0 + 144.0), 1e-6)
    end)

    it("enforces Zero-False-Stability by returning nil when no valid velocity_sensor is present", function()
        mock.peripheral_registry({})
        local vec, err = sensors.velocity.read_vector3()
        assert_nil(vec)
        assert_not_nil(err)
    end)
end)

describe("altitude_sensor standard functions", function()
    it("reads height, air_pressure, vertical_speed and handles peripheral faults safely", function()
        local as = mock.cc_altitude_sensor({
            height = 142.5,
            airPressure = 0.815,
            verticalSpeed = 2.75,
        })
        assert_near(sensors.altitude.get_height(as), 142.5, 1e-6)
        assert_near(sensors.altitude.get_air_pressure(as), 0.815, 1e-6)
        assert_near(sensors.altitude.get_vertical_speed(as), 2.75, 1e-6)

        local snap, err = sensors.altitude.read(as)
        assert_nil(err)
        assert_near(snap.height, 142.5, 1e-6)
        assert_near(snap.altitude, 142.5, 1e-6)
        assert_near(snap.air_pressure, 0.815, 1e-6)
        assert_near(snap.vertical_speed, 2.75, 1e-6)

        -- Simulated hardware detach / exception
        local broken = {
            getHeight = function() error("Peripheral disconnected") end,
            getAirPressure = function() return 1.0 end,
            getVerticalSpeed = function() return 0.0 end,
        }
        local badSnap, badErr = sensors.altitude.read(broken)
        assert_nil(badSnap)
        assert_not_nil(badErr)
    end)
end)

describe("gimbal_sensor standard functions", function()
    it("maps body-frame angles, wy->yaw_rate / wz->roll_rate, gravity tilt, and inertial acceleration", function()
        local gs = mock.cc_gimbal_sensor({
            pitch = 12.0,
            roll = -6.5,
            wx = 1.5,   -- pitch rate (body-X)
            wy = -8.25, -- yaw rate (body-Y)
            wz = 3.75,  -- roll rate (body-Z)
            gravity = { 0.0, -11.0, 0.0 },
            linearAcceleration = { 2.0, 11.0, -0.5 }, -- stationary Y reads +11.0, +2.0 X thrust
        })

        local angDeg = sensors.gimbal.get_angles(gs)
        assert_near(angDeg.pitch, 12.0, 1e-6)
        assert_near(angDeg.roll, -6.5, 1e-6)

        local angRad = sensors.gimbal.get_angles_rad(gs)
        assert_near(angRad.pitch, math.rad(12.0), 1e-6)
        assert_near(angRad.roll, math.rad(-6.5), 1e-6)

        local ratesDeg = sensors.gimbal.get_angular_rates(gs)
        assert_near(ratesDeg.wx, 1.5, 1e-6)
        assert_near(ratesDeg.wy, -8.25, 1e-6)
        assert_near(ratesDeg.wz, 3.75, 1e-6)
        assert_near(ratesDeg.pitch_rate, 1.5, 1e-6)
        assert_near(ratesDeg.yaw_rate, -8.25, 1e-6)
        assert_near(ratesDeg.roll_rate, 3.75, 1e-6)

        local ratesRad = sensors.gimbal.get_angular_rates_rad(gs)
        assert_near(ratesRad.yaw_rate, math.rad(-8.25), 1e-6)
        assert_near(ratesRad.roll_rate, math.rad(3.75), 1e-6)

        local snap, err = sensors.gimbal.read(gs)
        assert_nil(err)
        assert_near(snap.tilt_deg, 0.0, 1e-6)
        assert_near(snap.inertial_acceleration.x, 2.0, 1e-6)
        assert_near(snap.inertial_acceleration.y, 0.0, 1e-6) -- 11.0 + (-11.0) = 0 inertial Y accel
        assert_near(snap.inertial_acceleration.z, -0.5, 1e-6)

        -- Singularity-free tilt edge cases
        assert_near(sensors.gimbal.compute_tilt_deg({ 11.0, 0.0, 0.0 }), 90.0, 1e-6)
        assert_near(sensors.gimbal.compute_tilt_deg({ 0.0, -7.0, 7.0 }), 45.0, 1e-6)
        assert_near(sensors.gimbal.compute_tilt_deg({ 0.0, 11.0, 0.0 }), 180.0, 1e-6)
        assert_nil(sensors.gimbal.compute_tilt_deg({ 0.0, 0.0, 0.0 }))
    end)
end)

describe("physics_assembler standard functions", function()
    it("reads mass, CoM, 3x3 inertia tensor, subLevel metadata and batches mainThread calls via parallel", function()
        local pa = mock.cc_physics_assembler({
            assembled = true,
            mass = 18500.5,
            com = { 0.25, 4.5, -1.75 },
            inertiaTensor = {
                1200.0, 15.0, -5.0,
                15.0, 3400.0, 8.0,
                -5.0, 8.0, 2900.0,
            },
            subLevelId = "550e8400-e29b-41d4-a716-446655440000",
            subLevelName = "AES Vanguard",
            yield = true,
        })

        -- 1) Verify real CraftOS _G.parallel.waitForAll execution path
        local paSync = mock.cc_physics_assembler({
            assembled = true,
            mass = 18500.5,
            com = { 0.25, 4.5, -1.75 },
            inertiaTensor = {
                1200.0, 15.0, -5.0,
                15.0, 3400.0, 8.0,
                -5.0, 8.0, 2900.0,
            },
            subLevelId = "550e8400-e29b-41d4-a716-446655440000",
            subLevelName = "AES Vanguard",
        })
        local syncSnap, syncErr = sensors.assembler.read(paSync)
        assert_nil(syncErr)
        assert_true(syncSnap.assembled)
        assert_near(syncSnap.mass, 18500.5, 1e-6)

        -- 2) Verify 6 mainThread-yielding calls settle in 1 single server tick (not 6 ticks)
        local simTicks = 0
        local branchCount = 0
        local customParallel = {
            waitForAll = function(...)
                local fns = { ... }
                branchCount = #fns
                local coros = {}
                for i = 1, #fns do
                    coros[i] = coroutine.create(fns[i])
                    local ok, res = coroutine.resume(coros[i])
                    assert_true(ok, tostring(res))
                end
                while true do
                    local anyAlive = false
                    for i = 1, #coros do
                        if coroutine.status(coros[i]) ~= "dead" then
                            anyAlive = true
                            break
                        end
                    end
                    if not anyAlive then break end
                    simTicks = simTicks + 1
                    for i = 1, #coros do
                        if coroutine.status(coros[i]) ~= "dead" then
                            local ok, res = coroutine.resume(coros[i], "task_complete")
                            assert_true(ok, tostring(res))
                        end
                    end
                end
            end,
        }

        local snap, err = sensors.assembler.read(pa, { parallel = customParallel })
        assert_nil(err)
        assert_eq(simTicks, 1) -- 6 mainThread getters batched into 1 server tick!
        assert_eq(branchCount, 6)
        assert_true(snap.assembled)
        assert_near(snap.mass, 18500.5, 1e-6)
        assert_near(snap.center_of_mass.x, 0.25, 1e-6)
        assert_near(snap.center_of_mass.y, 4.5, 1e-6)
        assert_near(snap.center_of_mass.z, -1.75, 1e-6)
        assert_near(snap.inertia_tensor.ixx, 1200.0, 1e-6)
        assert_near(snap.inertia_tensor.iyy, 3400.0, 1e-6)
        assert_near(snap.inertia_tensor.izz, 2900.0, 1e-6)
        assert_near(snap.inertia_tensor.ixy, 15.0, 1e-6)
        assert_eq(snap.sub_level_id, "550e8400-e29b-41d4-a716-446655440000")
        assert_eq(snap.sub_level_name, "AES Vanguard")
    end)

    it("handles stationary ground (disassembled, nil subLevelId/Name) and sequential fallback cleanly", function()
        local paGround = mock.cc_physics_assembler({
            assembled = false,
            subLevelId = nil,
            subLevelName = nil,
        })

        local idVal, idErr = sensors.assembler.get_sub_level_id(paGround)
        assert_nil(idVal)
        assert_nil(idErr) -- nil on ground is valid, NOT an error

        local nameVal, nameErr = sensors.assembler.get_sub_level_name(paGround)
        assert_nil(nameVal)
        assert_nil(nameErr)

        local snap, err = sensors.assembler.read(paGround, { parallel = false })
        assert_nil(err)
        assert_false(snap.assembled)
        assert_near(snap.mass, 0.0, 1e-6)
        assert_nil(snap.sub_level_id)
        assert_nil(snap.sub_level_name)
    end)
end)
