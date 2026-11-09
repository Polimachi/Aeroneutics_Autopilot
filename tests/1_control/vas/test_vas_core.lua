-- Unit test suite for 1_control/vas
local quat = require("quat")
local flight_dynamics_core = require("flight_dynamics_core")
local sensor_pipeline = require("sensor_pipeline")
local network_manager = require("network_manager")
local telemetry_feeder = require("telemetry_feeder")
local state_machine = require("state_machine")

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

    it("samples authentic CC:Avionics sensors via avionics_sensors library", function()
        local g_mock = mock.cc_gimbal_sensor({ pitch = 3.5, roll = -1.2, wx = 0.2, wy = 0.05, wz = -0.1 })
        local a_mock = mock.cc_altitude_sensor({ height = 250.0, verticalSpeed = -1.5 })
        local v_mock = mock.cc_velocity_sensor({ velocity = 12.5, axis = "x" })
        local f_mock = mock.fuel_tank(900, 1000)

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

        assert_near(raw.gimbal.pitch, 3.5, 1e-4)
        assert_near(raw.gimbal.roll, -1.2, 1e-4)
        assert_near(raw.gimbal.pitchRate, 0.2, 1e-4)
        assert_near(raw.gimbal.rollRate, -0.1, 1e-4)
        assert_near(raw.gimbal.yawRate, 0.05, 1e-4)

        assert_near(raw.altitude.altitude, 250.0, 1e-4)
        assert_near(raw.velocity.vx, 12.5, 1e-4)
        assert_near(raw.fuel.amount, 900, 1e-4)

        local comState, healthMap, allOk = sensor_pipeline.process_kinematics(sp, raw, 0.05)
        assert_true(allOk)
        assert_near(comState.dynamics.altitudeY, 250.0, 1e-4)
        assert_near(comState.attitude.pitch, 3.5, 1e-4)
        assert_near(comState.rates.pitchRate, 0.2, 1e-4)
    end)

    it("compensates 3D lever-arm offsets for altitude and velocity accurately", function()
        local g_mock = mock.cc_gimbal_sensor({ pitch = 10.0, roll = 0.0, wx = 0.5, wy = 0.0, wz = 0.0 })
        local a_mock = mock.cc_altitude_sensor({ height = 100.0, verticalSpeed = 2.0 })
        local v_mock = mock.cc_velocity_sensor({ velocity = 15.0, axis = "x" })
        local f_mock = mock.fuel_tank(500, 1000)

        mock.peripheral_registry({
            top = { type = "gimbal_sensor", dev = g_mock },
            bottom = { type = "altitude_sensor", dev = a_mock },
            left = { type = "velocity_sensor", dev = v_mock },
            right = { type = "fuel", dev = f_mock }
        })

        local sp = sensor_pipeline.init({
            roles = {
                gimbal = { peripheralType = "gimbal_sensor", preferredSide = "top" },
                altitude = {
                    peripheralType = "altitude_sensor",
                    preferredSide = "bottom",
                    leverArmOffset = { dx = 5.0, dy = 0.0, dz = 0.0 }
                },
                velocity = {
                    peripheralType = "velocity_sensor",
                    preferredSide = "left",
                    leverArmOffset = { dx = 0.0, dy = 2.0, dz = 0.0 }
                },
                fuel = { peripheralType = "fuel", preferredSide = "right" }
            }
        })

        local raw = sensor_pipeline.sample_all(sp)
        assert_true(raw.altitudeOk)
        assert_true(raw.velocityOk)

        -- Pitch 10 deg: sin(10 deg) ~ 0.173648. dh = 5.0 * sin(10 deg) ~ 0.86824.
        -- Expected altCoM = 100.0 - 0.86824 ~ 99.13175
        local comState, healthMap, allOk = sensor_pipeline.process_kinematics(sp, raw, 0.05)
        assert_true(allOk)
        assert_near(comState.dynamics.altitudeY, 99.1318, 1e-2)
        assert_near(comState.dynamics.verticalSpeed, 2.0, 1e-4)
    end)
end)

describe("vas 40-channel 4-zone layout and network manager initialization", function()
    it("computes base channel, validates base, and initializes 4-zone channels", function()
        assert_eq(network_manager.compute_base(1), 10000)
        assert_eq(network_manager.compute_base(2), 10040)
        assert_eq(network_manager.compute_base(1000), 49960)
        local outOfRange, err = network_manager.compute_base(0)
        assert_nil(outOfRange)
        assert_eq(err, "ERR_AIRCRAFT_INDEX_RANGE")
        assert_false(network_manager.is_valid_base(10060))
        assert_false(network_manager.is_valid_base(50000))
        assert_true(network_manager.is_valid_base(10000))
        assert_true(network_manager.is_valid_base(10040))

        local wirelessModem = mock.modem({ wireless = true })
        local wiredModem = mock.modem({ wireless = false })
        mock.peripheral_registry({
            top = { type = "modem", dev = wirelessModem },
            bottom = { type = "modem", dev = wiredModem }
        })

        local net = network_manager.init({ aircraftDomainId = "AIRCRAFT_01" })
        assert_eq(net.baseChannel, 10000)
        assert_eq(net.channels.c2, 10000)
        assert_eq(net.channels.guidance, 10001)
        assert_eq(net.channels.telemetry, 10002)
        assert_eq(net.channels.mfd, 10003)
        assert_eq(net.channels.navSensor, 10004)
        assert_eq(net.channels.clientReply, 10005)
        assert_eq(net.channels.actuation, 10010)
        assert_eq(net.channels.aero, 10011)
        assert_eq(net.channels.payloadBus, 10020)
        assert_eq(net.channels.weaponBus, 10021)
        assert_eq(net.channels.formationLink, 10030)

        assert_true(wirelessModem.isOpen(10000))
        assert_true(wirelessModem.isOpen(10001))
        assert_true(wirelessModem.isOpen(10010))
        assert_true(wirelessModem.isOpen(10011))
        assert_false(wirelessModem.isOpen(10004))
    end)
end)

describe("vas telemetry feeder MFD silence guard and failsafe rate limiting", function()
    it("keeps Base+3 silent during normal flight, streams at 20Hz in acro, downsamples in failsafe", function()
        local wirelessModem = mock.modem({ wireless = true })
        mock.peripheral_registry({
            top = { type = "modem", dev = wirelessModem }
        })
        local net = network_manager.init({ aircraftDomainId = "AIRCRAFT_01" })
        local tf = telemetry_feeder.init({})
        local comState = {
            attitude = { pitch = 0.0, roll = 0.0, yaw = 90.0 },
            rates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
            dynamics = { altitudeY = 150.0, verticalSpeed = 0.0 },
            fuel = { amount = 800, capacity = 1000 }
        }
        local diagState = { sensorOk = true, sensorHealth = {}, actuatorHealth = { tap = true, asa = true } }
        local mixerState = { dynamicLoad = 0.0 }
        local fsmNormal = { currentState = "NORMAL", activeSource = "FCP" }

        -- 8 consecutive ticks in normal FCP mode
        for _ = 1, 8 do
            telemetry_feeder.tick(tf, net, comState, fsmNormal, mixerState, diagState)
        end

        local count10002 = 0
        local count10003 = 0
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.tx == 10002 then count10002 = count10002 + 1 end
            if tx.tx == 10003 then count10003 = count10003 + 1 end
        end
        assert_eq(count10002, 8)
        assert_eq(count10003, 0) -- Base+3 must remain completely silent!

        -- MFD_ACRO mode: transmits every tick (20Hz)
        wirelessModem._transmitted = {}
        tf.tickCounter = 0
        local fsmAcro = { currentState = "NORMAL", activeSource = "MFD_ACRO" }
        for _ = 1, 3 do
            telemetry_feeder.tick(tf, net, comState, fsmAcro, mixerState, diagState)
        end
        local acro10003 = 0
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.tx == 10003 and tx.pkt.type == "MSG_MFD_STATE" then
                acro10003 = acro10003 + 1
            end
        end
        assert_eq(acro10003, 3)

        -- FAILSAFE_HOLD mode: transmits 1 every 4 ticks (5Hz)
        wirelessModem._transmitted = {}
        tf.tickCounter = 0
        local fsmFailsafe = { currentState = "FAILSAFE_HOLD", activeSource = "FCP" }
        for _ = 1, 4 do
            telemetry_feeder.tick(tf, net, comState, fsmFailsafe, mixerState, diagState)
        end
        local failsafe10003 = 0
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.tx == 10003 and tx.pkt.type == "MSG_MFD_STATE" then
                failsafe10003 = failsafe10003 + 1
            end
        end
        assert_eq(failsafe10003, 1)
    end)
end)

describe("vas dynamic hangar bay binding and calibration lifecycle", function()
    it("dynamically opens bay channels on MSG_CALIBRATION_INIT, replicates telemetry, and closes on MSG_CALIBRATION_CLOSE", function()
        local wirelessModem = mock.modem({ wireless = true })
        mock.peripheral_registry({
            top = { type = "modem", dev = wirelessModem }
        })
        local net = network_manager.init({ aircraftDomainId = "AIRCRAFT_01" })
        local fsm = state_machine.init({}, false)
        local tf = telemetry_feeder.init({})
        local comState = {
            attitude = { pitch = 0.0, roll = 0.0, yaw = 0.0 },
            rates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
            dynamics = { altitudeY = 0.0, verticalSpeed = 0.0 },
            fuel = { amount = 500, capacity = 1000 }
        }
        local diagState = { sensorOk = true, sensorHealth = {}, actuatorHealth = { tap = true, asa = true } }
        local mixer = {}

        -- 1) Receive MSG_CALIBRATION_INIT on Base+0 (10000)
        local initPkt = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1,
            type = "MSG_CALIBRATION_INIT", time = 1000,
            payload = {
                stationId = "STATION_BAY_02", bayId = 2,
                baseHangarChannel = 111, targetCraftDomain = "AIRCRAFT_01"
            }
        }
        network_manager.dispatch(net, fsm, nil, mixer, 10000, 10000, initPkt)

        -- Bay channels 111, 112, 114 dynamically opened
        assert_true(wirelessModem.isOpen(111))
        assert_true(wirelessModem.isOpen(112))
        assert_true(wirelessModem.isOpen(114))

        -- Check MSG_CALIB_BAY_BIND on 10010 and 10011
        local bind10, bind11, initAck112 = false, false, false
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.tx == 10010 and tx.pkt.type == "MSG_CALIB_BAY_BIND" and tx.pkt.payload.action == "OPEN" then
                bind10 = true
                assert_eq(tx.pkt.payload.bayCalibrationTap, 114)
                assert_eq(tx.pkt.payload.bayCalibrationCmd, 111)
            end
            if tx.tx == 10011 and tx.pkt.type == "MSG_CALIB_BAY_BIND" and tx.pkt.payload.action == "OPEN" then
                bind11 = true
            end
            if tx.tx == 112 and tx.pkt.type == "MSG_CALIBRATION_INIT_ACK" then
                initAck112 = true
                assert_eq(tx.pkt.payload.status, "READY")
                assert_eq(tx.pkt.payload.bayId, 2)
                assert_eq(tx.pkt.payload.baseChannel, 10000)
            end
        end
        assert_true(bind10)
        assert_true(bind11)
        assert_true(initAck112)
        assert_eq(fsm.currentState, "CALIBRATION")

        -- 2) Telemetry feeder replicates telemetry to Base_hangar+1 (112)
        wirelessModem._transmitted = {}
        telemetry_feeder.tick(tf, net, comState, fsm, nil, diagState)
        local telem10002, telem112 = false, false
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.tx == 10002 and tx.pkt.type == "MSG_FLIGHT_TELEMETRY" then telem10002 = true end
            if tx.tx == 112 and tx.pkt.type == "MSG_FLIGHT_TELEMETRY" then telem112 = true end
        end
        assert_true(telem10002)
        assert_true(telem112)

        -- 3) Receive MSG_CALIBRATION_CLOSE on Base_hangar+0 (111)
        wirelessModem._transmitted = {}
        local closePkt = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 2,
            type = "MSG_CALIBRATION_CLOSE", time = 2000,
            payload = { bayId = 2 }
        }
        network_manager.dispatch(net, fsm, nil, mixer, 111, 111, closePkt)

        local closeBind10, closeBind11, closeAck112 = false, false, false
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.tx == 10010 and tx.pkt.type == "MSG_CALIB_BAY_BIND" and tx.pkt.payload.action == "CLOSE" then
                closeBind10 = true
            end
            if tx.tx == 10011 and tx.pkt.type == "MSG_CALIB_BAY_BIND" and tx.pkt.payload.action == "CLOSE" then
                closeBind11 = true
            end
            if tx.tx == 112 and tx.pkt.type == "MSG_CALIBRATION_CLOSE_ACK" then
                closeAck112 = true
                assert_eq(tx.pkt.payload.status, "CLOSED")
            end
        end
        assert_true(closeBind10)
        assert_true(closeBind11)
        assert_true(closeAck112)

        -- Bay channels 111, 112, 114 closed
        assert_false(wirelessModem.isOpen(111))
        assert_false(wirelessModem.isOpen(112))
        assert_false(wirelessModem.isOpen(114))
        assert_nil(net.hangarChannels)
        assert_eq(fsm.currentState, "IDLE_ARMED")
    end)
end)

describe("vas two-phase channel rebind cascade", function()
    it("handles PREPARE and COMMIT rebind cascade to actuation/aero and closes old channels", function()
        local wirelessModem = mock.modem({ wireless = true })
        mock.peripheral_registry({
            top = { type = "modem", dev = wirelessModem }
        })
        local net = network_manager.init({ aircraftDomainId = "AIRCRAFT_01" })
        local fsm = state_machine.init({}, true)
        local mixer = {}

        -- 1) Receive MSG_CHANNEL_REBIND (PREPARE) on Base+1 (10001)
        local preparePkt = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 10,
            type = "MSG_CHANNEL_REBIND", time = 5000,
            payload = {
                transactionId = "TX-1", action = "PREPARE",
                oldBaseChannel = 10000, newBaseChannel = 10040, bandwidth = 40
            }
        }
        network_manager.dispatch(net, fsm, nil, mixer, 10001, 10001, preparePkt)

        -- New channels 10040, 10041, 10050, 10051 pre-opened
        assert_true(wirelessModem.isOpen(10040))
        assert_true(wirelessModem.isOpen(10041))
        assert_true(wirelessModem.isOpen(10050))
        assert_true(wirelessModem.isOpen(10051))

        -- PREPARE relayed on 10010 and 10011, and ACK sent on 10001
        local prepRelay10, prepRelay11, ack10001 = false, false, false
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.tx == 10010 and tx.pkt.type == "MSG_CHANNEL_REBIND" and tx.pkt.payload.action == "PREPARE" then
                prepRelay10 = true
            end
            if tx.tx == 10011 and tx.pkt.type == "MSG_CHANNEL_REBIND" and tx.pkt.payload.action == "PREPARE" then
                prepRelay11 = true
            end
            if tx.tx == 10001 and tx.pkt.type == "MSG_CHANNEL_REBIND_ACK" then
                ack10001 = true
                assert_eq(tx.pkt.payload.transactionId, "TX-1")
                assert_eq(tx.pkt.payload.nodeId, "01_core")
                assert_eq(tx.pkt.payload.status, "READY")
                assert_true(tx.pkt.payload.subNodesOk)
            end
        end
        assert_true(prepRelay10)
        assert_true(prepRelay11)
        assert_true(ack10001)

        -- 2) Receive MSG_CHANNEL_REBIND (COMMIT) on Base+1 (10001)
        wirelessModem._transmitted = {}
        local commitPkt = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 11,
            type = "MSG_CHANNEL_REBIND", time = 6000,
            payload = {
                transactionId = "TX-1", action = "COMMIT",
                oldBaseChannel = 10000, newBaseChannel = 10040, bandwidth = 40
            }
        }
        network_manager.dispatch(net, fsm, nil, mixer, 10001, 10001, commitPkt)

        local commitRelay10, commitRelay11 = false, false
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.tx == 10010 and tx.pkt.type == "MSG_CHANNEL_REBIND" and tx.pkt.payload.action == "COMMIT" then
                commitRelay10 = true
            end
            if tx.tx == 10011 and tx.pkt.type == "MSG_CHANNEL_REBIND" and tx.pkt.payload.action == "COMMIT" then
                commitRelay11 = true
            end
        end
        assert_true(commitRelay10)
        assert_true(commitRelay11)

        -- Old channels 10000, 10001, 10010, 10011 must be closed
        assert_false(wirelessModem.isOpen(10000))
        assert_false(wirelessModem.isOpen(10001))
        assert_false(wirelessModem.isOpen(10010))
        assert_false(wirelessModem.isOpen(10011))

        -- State baseChannel and channels updated
        assert_eq(net.baseChannel, 10040)
        assert_eq(net.channels.c2, 10040)
        assert_eq(net.channels.guidance, 10041)
        assert_eq(net.channels.actuation, 10050)
        assert_eq(net.channels.aero, 10051)
        assert_nil(net.pendingRebind)
    end)
end)


describe("vas asa exclusion for vectored_vtol and drone", function()
    local vehicle_policy = require("vehicle_policy")
    local core_daemon = require("core_daemon")

    it("clamps flapTarget to 0.0 in vehicle_policy for non-aero airframes", function()
        local non_aero = { "VECTORED_VTOL", "ADVANCED_VTOL", "QUADROTOR", "HEXAROTOR", "VTOL" }
        for _, vType in ipairs(non_aero) do
            local pol = vehicle_policy.init({ vehicleType = vType })
            local flap = vehicle_policy.resolve_flap_target(pol, { flapTarget = 0.8 }, 15.0, {})
            assert_eq(flap, 0.0, "flapTarget must be 0.0 for " .. vType)
        end

        local pol_fw = vehicle_policy.init({ vehicleType = "FIXED_WING" })
        assert_eq(vehicle_policy.resolve_flap_target(pol_fw, { flapTarget = 0.8 }, 15.0, {}), 0.8)

        local pol_wv = vehicle_policy.init({ vehicleType = "WINGED_VTOL" })
        assert_eq(vehicle_policy.resolve_flap_target(pol_wv, { flapTarget = 0.8 }, 15.0, {}), 0.8)
    end)

    it("suppresses MSG_AERO_CMD broadcast in core_daemon for VECTORED_VTOL", function()
        local wirelessModem = mock.modem({ wireless = true })
        mock.peripheral_registry({
            top = { type = "modem", dev = wirelessModem },
            bottom = { type = "altitude_sensor", dev = mock.avionics_altitude({ altitude = 100.0, verticalSpeed = 0.0 }) },
            left = { type = "velocity_sensor", dev = mock.avionics_velocity({ vx = 5.0, vy = 0.0, vz = 0.0 }) },
            right = { type = "fuel", dev = mock.fuel_tank(500, 1000) }
        })
        local daemonState = core_daemon.init({
            system = { vehicleType = "VECTORED_VTOL", aircraftDomainId = "AIRCRAFT_01", baseChannel = 10000 },
            thrusters = {},
            surfaces = {},
            sensors = { roles = { altitude = { preferredSide = "bottom", peripheralType = "altitude_sensor" } } },
            pid = {}
        })

        wirelessModem._transmitted = {}
        core_daemon.tick(daemonState)

        local sentThrust = false
        local sentAero = false
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.pkt.type == "MSG_THRUST_CMD" then sentThrust = true end
            if tx.pkt.type == "MSG_AERO_CMD" then sentAero = true end
        end

        assert_true(sentThrust, "MSG_THRUST_CMD must be transmitted")
        assert_false(sentAero, "MSG_AERO_CMD must NOT be transmitted for VECTORED_VTOL")
    end)

    it("transmits MSG_AERO_CMD broadcast in core_daemon for WINGED_VTOL", function()
        local wirelessModem = mock.modem({ wireless = true })
        mock.peripheral_registry({
            top = { type = "modem", dev = wirelessModem },
            bottom = { type = "altitude_sensor", dev = mock.avionics_altitude({ altitude = 100.0, verticalSpeed = 0.0 }) },
            left = { type = "velocity_sensor", dev = mock.avionics_velocity({ vx = 5.0, vy = 0.0, vz = 0.0 }) },
            right = { type = "fuel", dev = mock.fuel_tank(500, 1000) }
        })
        local daemonState = core_daemon.init({
            system = { vehicleType = "WINGED_VTOL", aircraftDomainId = "AIRCRAFT_01", baseChannel = 10000 },
            thrusters = {},
            surfaces = { surfaceMix = { AIL_L = { pitch = 1.0 } } },
            sensors = { roles = { altitude = { preferredSide = "bottom", peripheralType = "altitude_sensor" } } },
            pid = {}
        })

        wirelessModem._transmitted = {}
        core_daemon.tick(daemonState)

        local sentThrust = false
        local sentAero = false
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.pkt.type == "MSG_THRUST_CMD" then sentThrust = true end
            if tx.pkt.type == "MSG_AERO_CMD" then sentAero = true end
        end

        assert_true(sentThrust, "MSG_THRUST_CMD must be transmitted")
        assert_true(sentAero, "MSG_AERO_CMD must be transmitted for WINGED_VTOL")
    end)
end)

describe("vas core daemon debug config defaults", function()
    local core_daemon = require("core_daemon")

    it("defaults system.debug to true when omitted", function()
        local daemonState = core_daemon.init({
            system = { vehicleType = "FIXED_WING", aircraftDomainId = "AIRCRAFT_01" },
            thrusters = {},
            surfaces = {},
            sensors = {},
            pid = {}
        })
        assert_not_nil(daemonState.cfg)
        assert_not_nil(daemonState.cfg.system)
        assert_true(daemonState.cfg.system.debug, "system.debug must default to true when omitted")
    end)

    it("defaults system.debug to true when system table is empty or missing", function()
        local daemonState = core_daemon.init({
            thrusters = {},
            surfaces = {},
            sensors = {},
            pid = {}
        })
        assert_not_nil(daemonState.cfg)
        assert_not_nil(daemonState.cfg.system)
        assert_true(daemonState.cfg.system.debug, "system.debug must default to true when system table missing")
    end)

    it("preserves system.debug when explicitly set to false", function()
        local daemonState = core_daemon.init({
            system = { vehicleType = "FIXED_WING", debug = false },
            thrusters = {},
            surfaces = {},
            sensors = {},
            pid = {}
        })
        assert_not_nil(daemonState.cfg)
        assert_not_nil(daemonState.cfg.system)
        assert_false(daemonState.cfg.system.debug, "system.debug must remain false when explicitly set")
    end)
end)

describe("vas ui_renderer and async/headless execution", function()
    local ui_renderer = require("ui_renderer")
    local vas_main = require("main")

    it("renders dashboard to mock terminal within 51x19 dimensions without blit error", function()
        local termMock = mock.term(51, 19)
        local state = {
            fsm = { currentState = "NORMAL", transitionReason = "CRUISE" },
            net = { aircraftDomainId = "AIRCRAFT_01", baseChannel = 10000, wirelessModem = {}, wiredModem = {} },
            sensors = {
                devices = { gimbal = {}, altitude = {}, velocity = {}, fuel = {} },
                roles = { velocity = { required = true }, fuel = { required = true } },
                lastCom = {
                    attitude = { pitch = 5.0, roll = -2.0, yaw = 120.0 },
                    dynamics = { altitudeY = 150.0, verticalSpeed = 1.2, velocity = { vx = 10.0, vy = 1.2, vz = -5.0 } },
                    fuel = 0.85
                }
            },
            mixer = { dynamicLoad = 0.45, tcaConnected = true, isStaticFallback = false },
            controller = { saturationFreeze = false, lastDemands = { pitch = 0.15 } },
            tickCount = 42
        }

        ui_renderer.render_dashboard(termMock, state)
        assert_true(termMock:_contains("VAS"))
        assert_true(termMock:_contains("FLIGHT HUD"))
        assert_true(termMock:_contains("NORMAL"))
        assert_true(termMock:_contains("AIRCRAFT_01"))

        for y = 1, 19 do
            assert_true(#(termMock._lines[y]) <= 51, "line length must not exceed terminal width")
        end
    end)

    it("provides clear_screen and restore_screen helpers that reset cursor and colors", function()
        local termMock = mock.term(51, 19)
        assert_eq(type(ui_renderer.clear_screen), "function")
        assert_eq(type(ui_renderer.restore_screen), "function")

        ui_renderer.clear_screen(termMock)
        local cx, cy = termMock.getCursorPos()
        assert_eq(cx, 1)
        assert_eq(cy, 1)

        ui_renderer.restore_screen(termMock)
        local rx, ry = termMock.getCursorPos()
        assert_eq(rx, 1)
        assert_eq(ry, 1)
    end)

    it("exports main, run_daemon, run_tui in vas main module without stalling in test environment", function()
        assert_not_nil(vas_main)
        assert_eq(type(vas_main.main), "function")
        assert_eq(type(vas_main.run_daemon), "function")
        assert_eq(type(vas_main.run_tui), "function")
    end)

    it("launches parallel waitForAny in debug mode when debug flag is true", function()
        local waitForAnyCalled = false
        local coroutineCount = 0
        sdk.patch(parallel, "waitForAny", function(...)
            waitForAnyCalled = true
            coroutineCount = select("#", ...)
        end)

        local termMock = mock.term(51, 19)
        sdk.patch(_G, "term", termMock)

        local cfg = {
            system = { vehicleType = "FIXED_WING", aircraftDomainId = "AIRCRAFT_01", debug = true, baseChannel = 10000 },
            thrusters = {},
            surfaces = {},
            sensors = {},
            pid = {}
        }

        vas_main.main(cfg)
        assert_true(waitForAnyCalled, "parallel.waitForAny must be called in debug mode")
        assert_eq(coroutineCount, 2, "parallel.waitForAny must receive exactly 2 coroutines (run_daemon and run_tui)")
    end)

    it("bypasses terminal rendering and runs daemon directly in headless mode when debug is false", function()
        local waitForAnyCalled = false
        sdk.patch(parallel, "waitForAny", function(...)
            waitForAnyCalled = true
        end)

        local termClearCalled = false
        local termBlitCalled = false
        local termMock = {
            clear = function() termClearCalled = true end,
            blit = function() termBlitCalled = true end,
            setCursorPos = function() end,
            setBackgroundColor = function() end,
            setTextColor = function() end
        }
        sdk.patch(_G, "term", termMock)

        local printed = {}
        sdk.patch(_G, "print", function(msg)
            table.insert(printed, tostring(msg))
        end)

        sdk.patch(os, "pullEventRaw", function()
            return "terminate"
        end)

        local cfg = {
            system = { vehicleType = "FIXED_WING", aircraftDomainId = "AIRCRAFT_01", debug = false, baseChannel = 10040 },
            thrusters = {},
            surfaces = {},
            sensors = {},
            pid = {}
        }

        vas_main.main(cfg)
        assert_false(waitForAnyCalled, "parallel.waitForAny must NOT be called in headless mode")
        assert_false(termClearCalled, "term.clear must NOT be called in headless mode")
        assert_false(termBlitCalled, "term.blit must NOT be called in headless mode")

        local headlessBannerFound = false
        for _, msg in ipairs(printed) do
            if string.find(msg, "%[VAS%] Core running in HEADLESS mode %(Node 01, Base: 10040%)") then
                headlessBannerFound = true
                break
            end
        end
        assert_true(headlessBannerFound, "Expected headless banner with Base 10040 printed")
    end)

    it("runs ui update on timer in run_tui and terminates on key q or t", function()
        local termMock = mock.term(51, 19)
        sdk.patch(_G, "term", termMock)

        local timerSeq = 200
        sdk.patch(os, "startTimer", function(duration)
            timerSeq = timerSeq + 1
            return timerSeq
        end)

        local state = {
            running = true,
            fsm = { currentState = "NORMAL" },
            tickCount = 10,
            cfg = { system = { debug = true } }
        }

        local pullCount = 0
        local pullFn = function()
            pullCount = pullCount + 1
            if pullCount == 1 then
                return "timer", timerSeq
            else
                return "key", 16 -- keys.q
            end
        end
        sdk.patch(os, "pullEvent", pullFn)
        sdk.patch(os, "pullEventRaw", pullFn)

        vas_main.run_tui(state)
        assert_false(state.running, "state.running must be set to false on key event")
        assert_true(pullCount >= 2, "must have handled timer and key events")
    end)

    it("isolates render errors in run_tui using pcall without crashing or stopping state.running", function()
        local termMock = mock.term(51, 19)
        sdk.patch(_G, "term", termMock)

        local renderAttemptCount = 0
        sdk.patch(ui_renderer, "render_dashboard", function()
            renderAttemptCount = renderAttemptCount + 1
            error("Simulated renderer catastrophic error")
        end)

        local timerSeq = 300
        sdk.patch(os, "startTimer", function(duration)
            timerSeq = timerSeq + 1
            return timerSeq
        end)

        local state = {
            running = true,
            fsm = { currentState = "NORMAL" },
            tickCount = 10,
            cfg = { system = { debug = true } }
        }

        local pullCount = 0
        local pullFn = function()
            pullCount = pullCount + 1
            if pullCount == 1 then
                return "timer", timerSeq
            else
                assert_true(state.running, "state.running must remain true despite render_dashboard errors")
                return "key", 16
            end
        end
        sdk.patch(os, "pullEvent", pullFn)
        sdk.patch(os, "pullEventRaw", pullFn)

        local ok, err = pcall(vas_main.run_tui, state)
        assert_true(ok, "run_tui must not propagate render exceptions")
        assert_false(state.running, "state.running must be false after key terminate")
        assert_true(renderAttemptCount >= 2, "render_dashboard must have been attempted at least twice")
    end)

    it("handles terminate event in run_tui and isolates fatal error while keeping idle until state stopped", function()
        local termMock = mock.term(51, 19)
        sdk.patch(_G, "term", termMock)

        sdk.patch(os, "startTimer", function()
            return 999
        end)

        local state = {
            running = true,
            fsm = { currentState = "NORMAL" },
            tickCount = 10,
            cfg = { system = { debug = true } }
        }

        local pullCount = 0
        local pullFn = function()
            pullCount = pullCount + 1
            if pullCount == 1 then
                return "terminate"
            end
            state.running = false
            return "dummy"
        end
        sdk.patch(os, "pullEvent", pullFn)
        sdk.patch(os, "pullEventRaw", pullFn)

        vas_main.run_tui(state)
        assert_false(state.running, "state.running must become false on terminate event")
    end)
end)

describe("vas mutation hardening invariants", function()
    it("verifies envelope rejects domain mismatch (MUT-01)", function()
        local ok, err = network_manager.verify_envelope({
            ver = "1.9.5", domainId = "ROGUE_DOMAIN", seq = 1, type = "MSG_OPERATOR_CMD", payload = {}
        }, "AIRCRAFT_01")
        assert_false(ok)
        assert_eq(err, "ERR_DOMAIN_MISMATCH")
    end)

    it("verifies thrust_mixer calculates positive surge/heave thrust demand (MUT-06)", function()
        local thrust_mixer = require("thrust_mixer")
        local mixer_state = thrust_mixer.init({
            THR_MAIN = { surge = 1.0, heave = 0.5, deadband = 0.0, maxThrust = 15 }
        })
        local out = thrust_mixer.mix(mixer_state, {
            surge = 10.0, sway = 0.0, heave = 4.0, pitch = 0.0, roll = 0.0, yaw = 0.0
        })
        assert_not_nil(out)
        assert_eq(out.THR_MAIN, 12)
    end)

    it("verifies network_manager dispatches MSG_EMERGENCY_OVERRIDE to transition to E_STOP (MUT-07)", function()
        local net = network_manager.init({ aircraftDomainId = "AIRCRAFT_01" })
        local fsm = state_machine.init({}, true)
        fsm.currentState = "NORMAL"
        local ok = network_manager.dispatch(net, fsm, nil, nil, 10000, 10000, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 99,
            type = "MSG_EMERGENCY_OVERRIDE",
            payload = { action = "E_STOP", reason = "TEST_ESTOP" }
        })
        assert_true(ok)
        assert_eq(fsm.currentState, "E_STOP")
    end)
end)
