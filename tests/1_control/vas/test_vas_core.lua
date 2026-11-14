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

    it("compensates 3D velocity lever-arm cross products with roll p, pitch q, yaw r rates", function()
        local lastCom = {
            attitude = { pitch = 0.0, roll = 0.0, yaw = 0.0 },
            rates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
            dynamics = { altitudeY = 0.0, verticalSpeed = 0.0, velocity = { vx = 0.0, vy = 0.0, vz = 0.0 } },
            fuel = 1.0
        }
        local cfg = {
            roles = {
                velocity = { leverArmOffset = { dx = 2.0, dy = 1.0, dz = 3.0 } }
            }
        }
        -- q = pitchRate = 90 deg/s, p = rollRate = 90 deg/s, r = yawRate = 0
        local qRad = math.rad(90.0)
        local pRad = math.rad(90.0)
        local raw = {
            gimbal = { pitch = 0.0, roll = 0.0, yaw = 0.0, pitchRate = 90.0, rollRate = 90.0, yawRate = 0.0 },
            altitude = { altitude = 10.0, verticalSpeed = 0.0 },
            velocity = { vx = 10.0, vy = 5.0, vz = 4.0 },
            fuelOk = false
        }
        local com = sensor_pipeline.compensate_lever_arm(raw, lastCom, cfg, 0.05)
        -- vxCoM = 10 - (q*dz - r*dy) = 10 - q*3
        -- vyCoM = 5 - (q*dx - p*dy) = 5 - (q*2 - p*1)
        -- vzCoM = 4 - (r*dx - p*dz) = 4 + p*3
        assert_near(com.dynamics.velocity.vx, 10.0 - qRad * 3.0, 1e-4)
        assert_near(com.dynamics.velocity.vy, 5.0 - (qRad * 2.0 - pRad * 1.0), 1e-4)
        assert_near(com.dynamics.velocity.vz, 4.0 + pRad * 3.0, 1e-4)
        assert_near(com.rates.pitchRate, 90.0, 1e-4)
        assert_near(com.rates.rollRate, 90.0, 1e-4)
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
        assert_eq(net.channels.trajectory, 10004)
        assert_eq(net.channels.clientReply, 10005)
        assert_eq(net.channels.actuation, 10010)
        assert_eq(net.channels.aero, 10011)
        assert_eq(net.channels.asaActuation, 10011)
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
        local lastAcroPkt = nil
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.tx == 10003 and tx.pkt.type == "MSG_MFD_STATE" then
                acro10003 = acro10003 + 1
                lastAcroPkt = tx.pkt
            end
        end
        assert_eq(acro10003, 3)
        assert_not_nil(lastAcroPkt)
        assert_eq(lastAcroPkt.payload.source, "CORE_ACRO_TAKEOVER")
        assert_eq(lastAcroPkt.payload.controlState, "NORMAL")
        assert_eq(lastAcroPkt.payload.flightMode, "ACRO")
        assert_true(lastAcroPkt.payload.acroActive)
        assert_true(lastAcroPkt.payload.sensorOk)
        assert_not_nil(lastAcroPkt.payload.attitude)
        assert_not_nil(lastAcroPkt.payload.angularRates)
        assert_not_nil(lastAcroPkt.payload.dynamics)
        assert_not_nil(lastAcroPkt.payload.dynamics.groundSpeed)
        assert_not_nil(lastAcroPkt.payload.actuatorHealth)
        assert_true(lastAcroPkt.payload.actuatorHealth.allOk)

        -- FAILSAFE_HOLD mode: transmits 1 every 4 ticks (5Hz)
        wirelessModem._transmitted = {}
        tf.tickCounter = 0
        local fsmFailsafe = { currentState = "FAILSAFE_HOLD", activeSource = "FCP" }
        for _ = 1, 4 do
            telemetry_feeder.tick(tf, net, comState, fsmFailsafe, mixerState, diagState)
        end
        local failsafe10003 = 0
        local lastFailsafePkt = nil
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.tx == 10003 and tx.pkt.type == "MSG_MFD_STATE" then
                failsafe10003 = failsafe10003 + 1
                lastFailsafePkt = tx.pkt
            end
        end
        assert_eq(failsafe10003, 1)
        assert_not_nil(lastFailsafePkt)
        assert_eq(lastFailsafePkt.payload.source, "CORE_FAILSAFE")
        assert_eq(lastFailsafePkt.payload.flightMode, "FAILSAFE_HOLD")
        assert_false(lastFailsafePkt.payload.acroActive)
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
                assert_not_nil(tx.pkt.payload.hardwareUuid)
                assert_not_nil(tx.pkt.payload.airframeType)
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
    it("awaits TCA and ASA ACKs on PREPARE, relays READY, and preserves subchannels on COMMIT", function()
        local nowMs = 5000
        sdk.patch(os, "epoch", function() return nowMs end)
        local wirelessModem = mock.modem({ wireless = true })
        mock.peripheral_registry({
            top = { type = "modem", dev = wirelessModem }
        })
        local net = network_manager.init({
            aircraftDomainId = "AIRCRAFT_01",
            vehicleType = "WINGED_VTOL",
            subchannels = { c2Command = 0, guidance = 1, actuation = 10, asaActuation = 11 }
        })
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

        -- PREPARE relayed on 10010 and 10011, and NO premature ACK before sub-nodes respond
        local prepRelay10, prepRelay11, prematureAck = false, false, false
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.tx == 10010 and tx.pkt.type == "MSG_CHANNEL_REBIND" and tx.pkt.payload.action == "PREPARE" then
                prepRelay10 = true
            end
            if tx.tx == 10011 and tx.pkt.type == "MSG_CHANNEL_REBIND" and tx.pkt.payload.action == "PREPARE" then
                prepRelay11 = true
            end
            if tx.tx == 10001 and tx.pkt.type == "MSG_CHANNEL_REBIND_ACK" then
                prematureAck = true
            end
        end
        assert_true(prepRelay10)
        assert_true(prepRelay11)
        assert_false(prematureAck)

        -- TCA ACKs READY on 10010, then ASA ACKs READY on 10011
        network_manager.dispatch(net, fsm, nil, mixer, 10010, 10010, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 11,
            type = "MSG_CHANNEL_REBIND_ACK", time = 5020,
            payload = { transactionId = "TX-1", nodeId = "02_tca", action = "PREPARE", status = "READY" }
        })
        network_manager.dispatch(net, fsm, nil, mixer, 10011, 10011, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 12,
            type = "MSG_CHANNEL_REBIND_ACK", time = 5030,
            payload = { transactionId = "TX-1", nodeId = "06_asa", action = "PREPARE", status = "READY" }
        })

        local ack10001 = false
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.tx == 10001 and tx.pkt.type == "MSG_CHANNEL_REBIND_ACK" then
                ack10001 = true
                assert_eq(tx.pkt.payload.transactionId, "TX-1")
                assert_eq(tx.pkt.payload.nodeId, "01_core")
                assert_eq(tx.pkt.payload.action, "PREPARE")
                assert_eq(tx.pkt.payload.status, "READY")
                assert_eq(tx.pkt.payload.oldBaseChannel, 10000)
                assert_eq(tx.pkt.payload.newBaseChannel, 10040)
                assert_true(tx.pkt.payload.subNodesReady.tap)
                assert_true(tx.pkt.payload.subNodesReady.asa)
            end
        end
        assert_true(ack10001)

        -- 2) Receive MSG_CHANNEL_REBIND (COMMIT) on Base+1 (10001)
        wirelessModem._transmitted = {}
        local commitPkt = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 13,
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

    it("times out after 500ms on PREPARE without sub-node ACKs and emits FAILED", function()
        local nowMs = 10000
        sdk.patch(os, "epoch", function() return nowMs end)
        local wirelessModem = mock.modem({ wireless = true })
        mock.peripheral_registry({
            top = { type = "modem", dev = wirelessModem }
        })
        local net = network_manager.init({ aircraftDomainId = "AIRCRAFT_01", vehicleType = "WINGED_VTOL" })
        local fsm = state_machine.init({}, true)

        network_manager.dispatch(net, fsm, nil, {}, 10001, 10001, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 20,
            type = "MSG_CHANNEL_REBIND", time = 10000,
            payload = { transactionId = "TX-TO", action = "PREPARE", oldBaseChannel = 10000, newBaseChannel = 10040, bandwidth = 40 }
        })
        assert_true(wirelessModem.isOpen(10040))

        nowMs = 10550
        local timedOut = network_manager.step_rebind_watchdog(net, nowMs)
        assert_true(timedOut)
        assert_nil(net.pendingRebind)
        assert_false(wirelessModem.isOpen(10040))

        local failedSent = false
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.tx == 10001 and tx.pkt.type == "MSG_CHANNEL_REBIND_ACK" and tx.pkt.payload.status == "FAILED" then
                failedSent = true
            end
        end
        assert_true(failedSent)
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
            surfaces = { surfaceGeometry = { AIL_L = { axis = "pitch", sign = 1.0 } } },
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
            payload = { action = "E_STOP", authKey = "ESTOP_CONFIRM_KEY", reason = "TEST_ESTOP" }
        })
        assert_true(ok)
        assert_eq(fsm.currentState, "E_STOP")
    end)
end)

describe("vas [I-10] surface discovery and attitude command type validation", function()
    local actuator_adapter_asa = require("actuator_adapter_asa")

    it("broadcasts both MSG_ACTUATOR_DISCOVER_REQ on Base+10 and MSG_SURFACE_DISCOVER_REQ on Base+11", function()
        local wirelessModem = mock.modem({ wireless = true })
        mock.peripheral_registry({
            top = { type = "modem", dev = wirelessModem }
        })
        local net = network_manager.init({ aircraftDomainId = "AIRCRAFT_01", baseChannel = 10000 })
        wirelessModem._transmitted = {}

        local ok = network_manager.broadcast_discovery(net)
        assert_true(ok)

        local sentActuator = false
        local sentSurface = false
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.tx == 10010 and tx.pkt.type == "MSG_ACTUATOR_DISCOVER_REQ" then
                sentActuator = true
                assert_eq(tx.pkt.payload.targetGroup, "ALL")
            end
            if tx.tx == 10011 and tx.pkt.type == "MSG_SURFACE_DISCOVER_REQ" then
                sentSurface = true
                assert_eq(tx.pkt.payload.targetPod, "ALL")
            end
        end
        assert_true(sentActuator, "Must send MSG_ACTUATOR_DISCOVER_REQ on Base+10")
        assert_true(sentSurface, "Must send MSG_SURFACE_DISCOVER_REQ on Base+11")
    end)

    it("dispatches MSG_SURFACE_DISCOVER_ACK and MSG_AERO_STATUS to adapterAsa", function()
        local net = network_manager.init({ aircraftDomainId = "AIRCRAFT_01", baseChannel = 10000 })
        local adapterAsa = actuator_adapter_asa.init({})
        net.adapterAsa = adapterAsa

        local ackPacket = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1,
            type = "MSG_SURFACE_DISCOVER_ACK",
            payload = {
                podId = "ASA_L",
                managedSurfaces = { "AIL_L", "FLAP_L" },
                boundPorts = { ["AIL_L"] = { side = "left", mode = "API" } },
                healthStatus = "NOMINAL"
            }
        }
        local okAck = network_manager.dispatch(net, nil, nil, nil, 10011, 10011, ackPacket)
        assert_true(okAck)
        assert_not_nil(adapterAsa.discoveredPods)
        assert_not_nil(adapterAsa.discoveredPods["ASA_L"])
        assert_eq(adapterAsa.discoveredPods["ASA_L"].podId, "ASA_L")

        local statusPacket = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 2,
            type = "MSG_AERO_STATUS",
            payload = {
                podId = "ASA_L",
                surfaceId = "AIL_L",
                boundSide = "left",
                interactionMode = "API",
                appliedDeflection = -0.5,
                isSaturated = false,
                isJammed = false,
                healthStatus = "NOMINAL"
            }
        }
        local okStatus = network_manager.dispatch(net, nil, nil, nil, 10011, 10011, statusPacket)
        assert_true(okStatus)
        assert_not_nil(adapterAsa.surfacesFeedback["AIL_L"])
        assert_near(adapterAsa.surfacesFeedback["AIL_L"].appliedDeflection, -0.5, 1e-6)
        assert_eq(adapterAsa.surfacesFeedback["AIL_L"].interactionMode, "API")
        assert_eq(adapterAsa.healthStatus, "NOMINAL")

        local lossPacket = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 3,
            type = "MSG_AERO_STATUS",
            payload = { surfaceId = "RUDD", interactionMode = "REDSTONE", appliedDeflection = 0.0, healthStatus = "TOTAL_LOSS" }
        }
        network_manager.dispatch(net, nil, nil, nil, 10011, 10011, lossPacket)
        assert_eq(adapterAsa.healthStatus, "TOTAL_LOSS")
    end)

    it("allocates normalized [-1,+1]/[0,1] surfaces and q-scaling with RUDD under VAS §9.5", function()
        local asa = actuator_adapter_asa.init({
            surfaceGeometry = {
                AIL_L = { axis = "roll", sign = 1.0 },
                RUDD = { axis = "yaw", sign = 1.0 },
                FLAP_L = { axis = "lift", sign = 1.0 }
            },
            coefficients = { qScalingRefSpeed = 20.0, minQScale = 0.25, maxQScale = 2.50 }
        })
        assert_near(asa:compute_q_scaling(20.0), 1.0, 1e-4)
        assert_near(asa:compute_q_scaling(5.0), 2.50, 1e-4)
        assert_near(asa:compute_q_scaling(100.0), 0.25, 1e-4)

        local outs, sat, qScale = asa:allocate({ rollTorque = 0.4, yawTorque = -0.2 }, 20.0, 0.5)
        assert_near(qScale, 1.0, 1e-4)
        assert_near(outs.AIL_L, 0.4, 1e-4)
        assert_near(outs.RUDD, -0.2, 1e-4)
        assert_near(outs.FLAP_L, 0.5, 1e-4)
        assert_false(sat.axisSaturatedPos.roll)
    end)

    it("rejects MSG_ATTITUDE_CMD unless commandType is QUATERNION_RATE or RATE_COMMAND", function()
        local net = network_manager.init({ aircraftDomainId = "AIRCRAFT_01", baseChannel = 10000 })
        local fsm = state_machine.init({}, true)
        fsm.currentState = "NORMAL"

        -- Stale ATTITUDE_ANGLE: must be rejected!
        local stalePacket = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 10,
            type = "MSG_ATTITUDE_CMD",
            payload = {
                commandType = "ATTITUDE_ANGLE",
                targetQuaternion = { w = 1.0, x = 0.0, y = 0.0, z = 0.0 }
            }
        }
        local okStale = network_manager.dispatch(net, fsm, nil, nil, 10001, 10001, stalePacket)
        assert_false(okStale, "Stale ATTITUDE_ANGLE must be rejected")

        -- Missing commandType: must be rejected!
        local untypedPacket = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 11,
            type = "MSG_ATTITUDE_CMD",
            payload = {
                targetQuaternion = { w = 1.0, x = 0.0, y = 0.0, z = 0.0 }
            }
        }
        local okUntyped = network_manager.dispatch(net, fsm, nil, nil, 10001, 10001, untypedPacket)
        assert_false(okUntyped, "Untyped MSG_ATTITUDE_CMD must be rejected")

        -- QUATERNION_RATE: accepted
        local quatPacket = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 12,
            type = "MSG_ATTITUDE_CMD",
            payload = {
                commandType = "QUATERNION_RATE",
                targetQuaternion = { w = 1.0, x = 0.0, y = 0.0, z = 0.0 },
                targetRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 }
            }
        }
        local okQuat = network_manager.dispatch(net, fsm, nil, nil, 10001, 10001, quatPacket)
        assert_true(okQuat, "QUATERNION_RATE must be accepted")
        assert_eq(net.latestCommand.commandType, "QUATERNION_RATE")

        -- RATE_COMMAND: accepted
        local ratePacket = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 13,
            type = "MSG_ATTITUDE_CMD",
            payload = {
                commandType = "RATE_COMMAND",
                targetRates = { pitchRate = 5.0, rollRate = -2.0, yawRate = 0.0 }
            }
        }
        local okRate = network_manager.dispatch(net, fsm, nil, nil, 10001, 10001, ratePacket)
        assert_true(okRate, "RATE_COMMAND must be accepted")
        assert_eq(net.latestCommand.commandType, "RATE_COMMAND")
    end)
end)

describe("vas core daemon identifier normalization and flap limit", function()
    local core_daemon = require("core_daemon")

    it("loads flapVfeLimit from stallGuard config into policy", function()
        local daemonState = core_daemon.init({
            system = {
                vehicleType = "WINGED_VTOL",
                aircraftDomainId = "AIRCRAFT_01",
                stallGuard = { flapVfeLimit = 15.0 }
            },
            thrusters = {},
            surfaces = {},
            sensors = {},
            pid = {}
        })
        assert_not_nil(daemonState.policy)
        assert_eq(daemonState.policy.vFe, 15.0)
    end)
end)

describe("vas main boot state without harness override", function()
    local vas_main = require("main")

    it("does not force fsm currentState to NORMAL on boot when _G.harness_set_state is absent", function()
        sdk.patch(parallel, "waitForAny", function(...) end)
        sdk.patch(_G, "term", mock.term(51, 19))
        sdk.patch(_G, "print", function() end)

        local prevHarness = _G.harness_set_state
        _G.harness_set_state = nil

        local cfg = {
            system = { vehicleType = "WINGED_VTOL", aircraftDomainId = "AIRCRAFT_01", debug = true },
            thrusters = {},
            surfaces = {},
            sensors = {},
            pid = {}
        }
        local state = vas_main.main(cfg)
        _G.harness_set_state = prevHarness

        assert_not_nil(state)
        assert_not_nil(state.fsm)
        assert_eq(state.fsm.currentState, "DISARMED", "Boot FSM state must be DISARMED when uncalibrated and without harness override")
    end)
end)

describe("vas wave 2 safety & actuator regression guards", function()
    local state_machine = require("state_machine")
    local actuator_adapter_tca = require("actuator_adapter_tca")
    local core_daemon = require("core_daemon")

    it("enforces sensorLossDebounceTicks=15, ARMING->IDLE_ARMED transition, and MFD_ACRO lock", function()
        local nowMs = 1000
        sdk.patch(os, "epoch", function() return nowMs end)
        local fsm = state_machine.init({}, false)
        assert_eq(fsm.sensorLossDebounceTicks, 15)

        state_machine.handle_arm_command(fsm, { arm = true, flightActive = false })
        assert_eq(fsm.currentState, "ARMING")
        state_machine.update_watchdogs(fsm, nowMs, nil, nil, true, true)
        assert_eq(fsm.currentState, "IDLE_ARMED")

        -- Enter NORMAL and test MFD_ACRO blocking FCP until 250ms timeout
        state_machine.handle_arm_command(fsm, { arm = true, flightActive = true })
        assert_eq(fsm.currentState, "NORMAL")
        local fcpCmd = { source = "FCP", commandType = "QUATERNION_RATE", targetQuaternion = { w = 1, x = 0, y = 0, z = 0 } }
        state_machine.arbitrate_c2(fsm, fcpCmd)
        assert_eq(fsm.activeSource, "FCP")

        local acroCmd = { source = "MFD_ACRO", commandType = "RATE_COMMAND", acroActive = true, targetAngularRates = { pitchRate = 10 } }
        assert_not_nil(state_machine.arbitrate_c2(fsm, acroCmd))
        assert_eq(fsm.activeSource, "MFD_ACRO")

        -- FCP packet without acroActive=false must be blocked while MFD_ACRO is active
        assert_nil(state_machine.arbitrate_c2(fsm, fcpCmd))
        assert_eq(fsm.activeSource, "MFD_ACRO")

        -- After 250ms silence, MFD_ACRO reverts immediately to FCP
        nowMs = 1300
        state_machine.update_watchdogs(fsm, nowMs, nil, nil, true, true)
        assert_eq(fsm.activeSource, "FCP")

        -- 14 ticks of sensor loss must NOT trip FAILSAFE_HOLD; 15th tick does
        for _ = 1, 14 do
            state_machine.update_watchdogs(fsm, nowMs, nil, nil, false, true)
            assert_eq(fsm.currentState, "NORMAL")
        end
        state_machine.update_watchdogs(fsm, nowMs, nil, nil, false, true)
        assert_eq(fsm.currentState, "FAILSAFE_HOLD")
    end)

    it("aggregates dynamicLoad across all TCA actuator groups instead of overwriting", function()
        local tca = actuator_adapter_tca.init({})
        tca:update_actuator_feedback({ groupId = "G1", appliedRatio = 0.8, healthStatus = "API_NOMINAL" })
        tca:update_actuator_feedback({ groupId = "G2", appliedRatio = 0.2, healthStatus = "API_NOMINAL" })
        assert_near(tca.dynamicLoad, 0.5, 1e-4)
    end)

    it("emits non-empty airborne E_STOP cushion thrust on core_daemon.shutdown", function()
        local wirelessModem = mock.modem({ wireless = true })
        mock.peripheral_registry({ top = { type = "modem", dev = wirelessModem } })
        local daemonState = core_daemon.init({
            system = { vehicleType = "VTOL", aircraftDomainId = "AIRCRAFT_01", baseChannel = 10000 },
            thrusters = { THR_1 = { heave = 1.0, deadband = 1.0, maxThrust = 15 } },
            surfaces = {}, sensors = {}, pid = {}
        })
        daemonState.fsm.currentState = "E_STOP"
        daemonState.fsm.isAirborne = true
        wirelessModem._transmitted = {}
        core_daemon.shutdown(daemonState, "UNIT_TEST")

        local foundCushion = false
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.pkt.type == "MSG_THRUST_CMD" and tx.pkt.payload.outputs.THR_1 then
                foundCushion = (tx.pkt.payload.outputs.THR_1 > 0)
            end
        end
        assert_true(foundCushion, "Airborne E_STOP shutdown must output cushion thrust to thruster groups")
    end)
end)
