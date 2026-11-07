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
end)
