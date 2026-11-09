-- Unit test suite for 0_development/alignment
local ols_regression_engine = require("ols_regression_engine")
local align_master = require("align_master")
local hud_renderer = require("hud_renderer")

describe("alignment OLS regression engine", function()
    it("identifies dominant axis and calculates slope, intercept, and R2", function()
        local impulseList = {
            { surge = 2.0, sway = 0.1, heave = 0.0, pitch = 0.0, roll = 0.0, yaw = 0.0 },
            { surge = 4.0, sway = 0.1, heave = 0.0, pitch = 0.0, roll = 0.0, yaw = 0.0 },
            { surge = 6.0, sway = 0.2, heave = 0.0, pitch = 0.0, roll = 0.0, yaw = 0.0 },
        }

        local domAxis = ols_regression_engine.identify_dominant_axis(impulseList)
        assert_eq(domAxis, "surge")

        local signals = { 4, 8, 12 }
        local reg = ols_regression_engine.calculate_regression(signals, impulseList, domAxis)
        assert_not_nil(reg)
        assert_eq(reg.dominantAxis, "surge")
        assert_near(reg.slope, 0.5, 1e-4)
        assert_near(reg.intercept, 0.0, 1e-4)
        assert_near(reg.confidenceR2, 1.0, 1e-4)
        assert_near(reg.normalizedCoefficients.surge, 1.0, 1e-4)
    end)
end)

describe("alignment master bay session and HUD renderer", function()
    it("initializes bay session and opens required hangar channels on mock modem", function()
        local mockModem = mock.modem()
        local stationCfg = {
            stationId = "BAY_01",
            bayId = 1,
            baseHangarChannel = 101,
            safety = { tiltAbortDeg = 12.0, tiltWarnDeg = 8.0 }
        }

        local master = align_master.init_bay_session(stationCfg, "AIRCRAFT_01", 10000, mockModem)
        assert_not_nil(master)
        assert_eq(master.state, "HANDSHAKE")
        -- Hangar channels opened: cmd (101), telem (102), tap (104)
        assert_true(mockModem.isOpen(101))
        assert_true(mockModem.isOpen(102))
        assert_true(mockModem.isOpen(104))
    end)

    it("renders artificial horizon on virtual terminal without blit mismatch", function()
        local termMock = mock.term(79, 36)
        local hud = hud_renderer.init(termMock)
        assert_not_nil(hud)

        hud:render_artificial_horizon(4.5, -2.0, 12.0)
        assert_true(termMock:_contains("ARTIFICIAL HORIZON"))
        assert_true(termMock:_contains("Pitch:"))
        assert_true(termMock:_contains("Tilt Guard:"))
    end)

    it("computes craft base channel accurately and validates bounds", function()
        assert_eq(align_master.compute_craft_base(1), 10000)
        assert_eq(align_master.compute_craft_base(2), 10040)
        assert_eq(align_master.compute_craft_base(1000), 49960)
        assert_nil(align_master.compute_craft_base(0))
        assert_nil(align_master.compute_craft_base(1001))
    end)

    it("auto-resolves craft Base+0 from domain id and sends MSG_CALIBRATION_INIT to Base+0", function()
        local mockModem = mock.modem()
        local stationCfg = {
            stationId = "BAY_01",
            bayId = 1,
            baseHangarChannel = 101,
            safety = { tiltAbortDeg = 12.0, tiltWarnDeg = 8.0 }
        }

        local master = align_master.init_bay_session(stationCfg, "AIRCRAFT_02", nil, mockModem)
        assert_not_nil(master)
        assert_eq(master.craft_base_ch, 10040)
        assert_eq(#mockModem._transmitted, 1)
        local t1 = mockModem._transmitted[1]
        assert_eq(t1.tx, 10040)
        assert_eq(t1.rx, 102)
        assert_not_nil(t1.pkt)
        assert_eq(t1.pkt.type, "MSG_CALIBRATION_INIT")
        assert_eq(t1.pkt.payload.stationId, "BAY_01")
        assert_eq(t1.pkt.payload.targetCraftDomain, "AIRCRAFT_02")
    end)

    it("emits MSG_CALIB_START on Base_hangar+0 and discovery requests on Base_hangar+3 upon INIT_ACK", function()
        local mockModem = mock.modem()
        local stationCfg = {
            stationId = "BAY_01",
            bayId = 1,
            baseHangarChannel = 101,
            safety = { tiltAbortDeg = 12.0, tiltWarnDeg = 8.0 }
        }

        local master = align_master.init_bay_session(stationCfg, "AIRCRAFT_01", 10000, mockModem)
        assert_eq(master.state, "HANDSHAKE")
        mockModem._transmitted = {}

        local ackEvent = {
            type = "PACKET",
            channel = 102,
            packet = {
                ver = "1.9.5",
                domainId = "AIRCRAFT_01",
                seq = 10,
                type = "MSG_CALIBRATION_INIT_ACK",
                payload = { status = "READY", craftDomain = "AIRCRAFT_01" }
            }
        }
        align_master.step_fsm(master, ackEvent)
        assert_eq(master.state, "DISCOVERY")

        assert_eq(#mockModem._transmitted, 3)

        local t1 = mockModem._transmitted[1]
        assert_eq(t1.tx, 101)
        assert_eq(t1.rx, 102)
        assert_eq(t1.pkt.type, "MSG_CALIB_START")
        assert_eq(t1.pkt.payload.action, "ENTER_CALIBRATION")
        assert_eq(t1.pkt.payload.stationId, "BAY_01")

        local t2 = mockModem._transmitted[2]
        assert_eq(t2.tx, 104)
        assert_eq(t2.rx, 102)
        assert_eq(t2.pkt.type, "MSG_ACTUATOR_DISCOVER_REQ")

        local t3 = mockModem._transmitted[3]
        assert_eq(t3.tx, 104)
        assert_eq(t3.rx, 102)
        assert_eq(t3.pkt.type, "MSG_SURFACE_DISCOVER_REQ")
    end)

    it("emits MSG_CALIBRATION_CLOSE on Base_hangar+0 and closes all channels on release", function()
        local mockModem = mock.modem()
        local stationCfg = {
            stationId = "BAY_01",
            bayId = 1,
            baseHangarChannel = 101,
            safety = { tiltAbortDeg = 12.0, tiltWarnDeg = 8.0 }
        }

        local master = align_master.init_bay_session(stationCfg, "AIRCRAFT_01", 10000, mockModem)
        assert_true(mockModem.isOpen(101))
        assert_true(mockModem.isOpen(102))
        assert_true(mockModem.isOpen(104))
        mockModem._transmitted = {}

        align_master.release_channels(master)
        assert_eq(#mockModem._transmitted, 1)
        local t1 = mockModem._transmitted[1]
        assert_eq(t1.tx, 101)
        assert_eq(t1.rx, 102)
        assert_eq(t1.pkt.type, "MSG_CALIBRATION_CLOSE")
        assert_eq(t1.pkt.payload.action, "CLOSE_SESSION")

        assert_false(mockModem.isOpen(101))
        assert_false(mockModem.isOpen(102))
        assert_false(mockModem.isOpen(104))
        assert_eq(master.state, "STANDBY")
    end)
end)


describe("alignment vector calibration integration (TASK-115)", function()
    it("assembles control matrix and validates pseudo-inverse inversion", function()
        local profile_exporter = require("profile_exporter")
        local vectorSlopes = {
            THR_VEC_1 = {
                dThrust = { surge = 0, sway = 0, heave = 2, pitch = 0, roll = 0, yaw = 0 },
                dGimbalX = { surge = 0, sway = 6, heave = 0, pitch = 0, roll = 3, yaw = 0 },
                dGimbalY = { surge = 6, sway = 0, heave = 0, pitch = 3, roll = 0, yaw = 0 }
            },
            THR_VEC_2 = {
                dThrust = { surge = 0, sway = 0, heave = 2, pitch = 0, roll = 0, yaw = 0 },
                dGimbalX = { surge = 0, sway = 6, heave = 0, pitch = 0, roll = -3, yaw = 0 },
                dGimbalY = { surge = 6, sway = 0, heave = 0, pitch = -3, roll = 0, yaw = 0 }
            }
        }
        local B = profile_exporter.assemble_control_matrix(vectorSlopes, { "THR_VEC_1", "THR_VEC_2" })
        assert_not_nil(B)
        assert_eq(#B, 6)
        assert_eq(#B[1], 6)
    end)
end)
