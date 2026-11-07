-- Unit test suite for 1_control/tca
local config_manager = require("config_manager")
local group_allocator = require("group_allocator")
local tca_daemon = require("tca_daemon")

describe("tca config and channel allocation", function()
    it("computes ICD base channels and saves configuration", function()
        local test_path = sdk.temp_path("test_tca_cfg.json")
        local base = config_manager.compute_base(2)
        assert_eq(base, 10020)

        local sample_cfg = {
            groupId = "THR_MAIN_L",
            aircraftIndexN = 2,
            baseChannel = base,
            interactionMode = "API",
            channels = { thrustActuation = base + 6, calibration = base + 4 },
            watchdogTimeoutMs = 300,
            nominalActuatorCount = 4,
            ports = { modemSide = "top", redstoneSide = "bottom", apiSides = { "left", "right" } }
        }

        local okSave = config_manager.save(test_path, sample_cfg)
        assert_true(okSave)

        local loaded, err = config_manager.load(test_path)
        assert_not_nil(loaded)
        assert_eq(err, "OK")
        assert_eq(loaded.groupId, "THR_MAIN_L")
        assert_eq(loaded.aircraftIndexN, 2)
        assert_eq(loaded.baseChannel, 10020)
        assert_eq(loaded.channels.thrustActuation, 10026)
    end)

    it("calculates API boosted signals with proportional compensation", function()
        local sig, ratio, isSat = group_allocator.calculate_api_boosted_signal(8, 3, 4)
        assert_eq(sig, 11)
        assert_near(ratio, 4.0 / 3.0, 0.01)
        assert_false(isSat)

        local sig0, ratio0 = group_allocator.calculate_api_boosted_signal(8, 0, 4)
        assert_eq(sig0, 0)
        assert_near(ratio0, 0.0, 1e-6)
    end)
end)

describe("tca daemon state machine and safing", function()
    it("safes outputs on DISARMED and maintains cushion in E_STOP", function()
        local mockModem = mock.modem()
        local cfg = {
            groupId = "THR_MAIN_L",
            aircraftDomainId = "AIRCRAFT_01",
            aircraftIndexN = 1,
            baseChannel = 10000,
            channels = { thrustActuation = 10006, calibration = 10004 },
            watchdogTimeoutMs = 300,
            nominalActuatorCount = 4,
            interactionMode = "REDSTONE",
            ports = { modemSide = "top", redstoneSide = "bottom", apiSides = {} }
        }

        local daemon = tca_daemon.init(cfg, mockModem)

        -- DISARMED command with non-zero output should be forced to 0
        local disarmPkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 1,
            type = "MSG_THRUST_CMD",
            payload = {
                watchdogSeq = 1,
                controlState = "DISARMED",
                outputs = { THR_MAIN_L = 10 }
            }
        }
        daemon:handle_thrust_cmd(disarmPkt)
        assert_eq(daemon.adapterState.lastSignal, 0)

        -- E_STOP with 5 signal holds cushion
        local estopPkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 2,
            type = "MSG_THRUST_CMD",
            payload = {
                watchdogSeq = 2,
                controlState = "E_STOP",
                outputs = { THR_MAIN_L = 5 }
            }
        }
        daemon:handle_thrust_cmd(estopPkt)
        assert_eq(daemon.adapterState.lastSignal, 5)
    end)
end)

describe("tca setup CLI tools", function()
    it("toggles interaction mode and renders UI without blit mismatch", function()
        _G.__TCA_SETUP_IMPORTED_ONLY = true
        local tca_setup = require("tca_setup")

        local cfg = {
            groupId = "THR_MAIN_L",
            aircraftDomainId = "AIRCRAFT_01",
            interactionMode = "REDSTONE",
            aircraftIndexN = 1,
            baseChannel = 10000,
            watchdogTimeoutMs = 300
        }

        -- Key 50 ('m') toggles REDSTONE -> API
        local cont1, m1 = tca_setup.handle_key(50, cfg, "REDSTONE", {})
        assert_true(cont1)
        assert_eq(m1, "API")

        -- Key 50 ('m') toggles API -> REDSTONE
        local cont2, m2 = tca_setup.handle_key(50, cfg, "API", {})
        assert_true(cont2)
        assert_eq(m2, "REDSTONE")

        -- Render to mock term
        local termMock = mock.term(51, 19)
        sdk.patch(_G, "term", termMock)
        tca_setup.render_ui(cfg, "REDSTONE", {})
        assert_true(termMock:_contains("TCA CONSOLE"))
        assert_true(termMock:_contains("THR_MAIN_L"))
    end)
end)
