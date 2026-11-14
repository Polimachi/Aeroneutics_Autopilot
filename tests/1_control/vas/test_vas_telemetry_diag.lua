-- Unit tests for VAS Opt-in telemetryDiag (TASK-120 / v1.21.0)
local telemetry_feeder = require("telemetry_feeder")
local core_daemon = require("core_daemon")

local function make_spy_net()
    local sent = {}
    local spyModem = {
        isOpen = function() return true end,
        open = function() end,
        close = function() end,
        transmit = function(ch, replyCh, pkt)
            table.insert(sent, { channel = ch, replyChannel = replyCh, packet = pkt })
        end,
    }
    return {
        channels = { telemetry = 10002, actuation = 10010, c2 = 10000 },
        wirelessModem = spyModem,
        wiredModem = spyModem,
        domainId = "VAS_DIAG_TEST",
        aircraftDomainId = "VAS_DIAG_TEST",
        seq = 0,
    }, sent
end

local function make_dummy_com()
    return {
        attitude = { w = 1, x = 0, y = 0, z = 0 },
        rates = { p = 0, q = 0, r = 0 },
        dynamics = { vx = 0, vy = 0, vz = 0, speed = 0, altitudeY = 50, verticalSpeed = 0 },
        fuel = { amount = 100, capacity = 100, ratio = 1.0 },
    }
end

describe("VAS opt-in telemetryDiag", function()
    it("omits satFlags and diag when telemetryDiag is disabled or unset", function()
        local feederDefault = telemetry_feeder.init({})
        local feederOff = telemetry_feeder.init({ telemetryDiag = false })
        local net, sent = make_spy_net()
        local com = make_dummy_com()
        local fsm = { currentState = "NORMAL" }
        local diag = {
            sensorOk = true,
            satFlags = { axisSaturatedPos = { pitch = true }, axisSaturatedNeg = {} },
            diag = { saturationFreeze = true, integrators = { pitch = 0.5 } },
        }

        telemetry_feeder.tick(feederDefault, net, com, fsm, nil, diag)
        telemetry_feeder.tick(feederOff, net, com, fsm, nil, diag)

        assert_eq(#sent, 2)
        for i = 1, 2 do
            local p = sent[i].packet.payload
            assert_eq(sent[i].packet.type, "MSG_FLIGHT_TELEMETRY")
            assert_eq(p.sensorOk, true)
            assert_nil(p.satFlags)
            assert_nil(p.diag)
        end
    end)

    it("includes satFlags and diag when telemetryDiag is true", function()
        local feederOn = telemetry_feeder.init({ telemetryDiag = true })
        local net, sent = make_spy_net()
        local com = make_dummy_com()
        local fsm = { currentState = "NORMAL" }
        local diag = {
            sensorOk = true,
            satFlags = { axisSaturatedPos = { pitch = true }, axisSaturatedNeg = {} },
            diag = {
                saturationFreeze = true,
                integrators = { pitch = 0.25, roll = 0, yaw = 0, climb = 0 },
                integralLimits = { pitch = 1.0, roll = 1.0, yaw = 1.0, climb = 1.0 },
                lastDemands = { pitch = 12.0, roll = 0.0, yaw = 0.0 },
            },
        }

        telemetry_feeder.tick(feederOn, net, com, fsm, nil, diag)

        assert_eq(#sent, 1)
        local p = sent[1].packet.payload
        assert_not_nil(p.satFlags)
        assert_true(p.satFlags.axisSaturatedPos.pitch)
        assert_not_nil(p.diag)
        assert_true(p.diag.saturationFreeze)
        assert_near(p.diag.integrators.pitch, 0.25, 1e-6)
        assert_near(p.diag.lastDemands.pitch, 12.0, 1e-6)
    end)

    it("propagates core_daemon saturation and integrators only when system.telemetryDiag is true", function()
        local function run_one_tick(diagEnabled)
            local cfg = {
                system = {
                    domainId = "VAS_DIAG_TEST",
                    airframeType = "VECTORED_VTOL",
                    baseChannel = 10000,
                    telemetryDiag = diagEnabled,
                    debug = false,
                },
                pid = {
                    attitude = {
                        pitch = { kp = 5.0, ki = 1.0, kd = 0.0, integralLimit = 0.5 },
                        roll = { kp = 3.0, ki = 0.1, kd = 0.4, integralLimit = 1.0 },
                        yaw = { kp = 2.0, ki = 0.1, kd = 0.2, integralLimit = 1.0 },
                    },
                    altitude = { kp = 1.5, ki = 0.2, kd = 0.3, integralLimit = 2.0 },
                },
                thrusters = {
                    airframeType = "VECTORED_VTOL",
                    thrusters = {
                        { id = "t1", channel = "pitch_up", maxThrust = 1000, direction = { x = 0, y = 1, z = 0 }, position = { x = 0, y = 0, z = 2 } },
                    },
                },
            }
            local st = core_daemon.init(cfg)
            local net, sent = make_spy_net()
            st.net.wirelessModem = net.wirelessModem
            st.net.wiredModem = net.wiredModem
            st.fsm.currentState = "NORMAL"
            st.adapter.tcaConnected = true
            st.sensors.devices.gimbal = {
                getReading = function() return { pitch = 0.8, roll = 0, yaw = 0, pitchRate = 0, rollRate = 0, yawRate = 0 } end,
            }
            st.sensors.devices.altitude = {
                getReading = function() return { altitude = 50, verticalSpeed = 0 } end,
            }
            st.sensors.devices.velocity = {
                getReading = function() return { vx = 0, vy = 0, vz = 0 } end,
            }
            st.sensors.devices.fuel = {
                getReading = function() return { amount = 100, capacity = 100 } end,
            }
            core_daemon.tick(st, 0.05, 10000)
            for _, item in ipairs(sent) do
                if item.packet and item.packet.type == "MSG_FLIGHT_TELEMETRY" then
                    return item.packet.payload
                end
            end
            return nil
        end

        local payloadOff = run_one_tick(false)
        assert_not_nil(payloadOff)
        assert_nil(payloadOff.satFlags)
        assert_nil(payloadOff.diag)

        local payloadOn = run_one_tick(true)
        assert_not_nil(payloadOn)
        assert_not_nil(payloadOn.satFlags)
        assert_not_nil(payloadOn.satFlags.axisSaturatedPos)
        assert_not_nil(payloadOn.satFlags.axisSaturatedNeg)
        assert_not_nil(payloadOn.diag)
        assert_not_nil(payloadOn.diag.integrators)
        assert_not_nil(payloadOn.diag.integralLimits)
        assert_not_nil(payloadOn.diag.lastDemands)
        assert_eq(type(payloadOn.diag.saturationFreeze), "boolean")
    end)
end)
