-- Unit test suite for 1_control/tca (40-Channel Layout & Zero-Fallback)
local config_manager = require("config_manager")
local group_allocator = require("group_allocator")
local tca_daemon = require("tca_daemon")

describe("tca config and channel allocation", function()
    it("computes ICD base channels and saves configuration", function()
        local test_path = sdk.temp_path("test_tca_cfg.json")
        local base = config_manager.compute_base(2)
        assert_eq(base, 10040)

        local sample_cfg = {
            groupId = "THR_MAIN_L",
            aircraftIndexN = 2,
            baseChannel = base,
            interactionMode = "API",
            channels = { thrustActuation = base + 10 },
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
        assert_eq(loaded.baseChannel, 10040)
        assert_eq(loaded.channels.thrustActuation, 10050)
        assert_nil(loaded.channels.calibration)
    end)

    it("defaults debug flag to true when omitted in config JSON", function()
        local test_path = sdk.temp_path("test_tca_nodebug.json")
        local raw_cfg = {
            groupId = "THR_MAIN_L",
            aircraftIndexN = 1,
            baseChannel = 10000
        }
        config_manager.save(test_path, raw_cfg)
        local loaded, err = config_manager.load(test_path)
        assert_not_nil(loaded)
        assert_eq(err, "OK")
        assert_true(loaded.debug, "loaded.debug must default to true")
    end)

    it("preserves debug flag when explicitly set to false in config JSON", function()
        local test_path = sdk.temp_path("test_tca_debug_false.json")
        local raw_cfg = {
            groupId = "THR_MAIN_L",
            aircraftIndexN = 1,
            baseChannel = 10000,
            debug = false
        }
        config_manager.save(test_path, raw_cfg)
        local loaded, err = config_manager.load(test_path)
        assert_not_nil(loaded)
        assert_eq(err, "OK")
        assert_false(loaded.debug, "loaded.debug must preserve explicit false")
    end)

    it("provides default config with debug enabled", function()
        assert_not_nil(config_manager.default_cfg)
        assert_true(config_manager.default_cfg.debug)
    end)


    it("validates compute_base bounds and migrates legacy 20-channel configs", function()
        assert_eq(config_manager.compute_base(1), 10000)
        assert_eq(config_manager.compute_base(1000), 49960)

        local b0, err0 = config_manager.compute_base(0)
        assert_nil(b0)
        assert_eq(err0, "ERR_INDEX_OUT_OF_RANGE")

        local b1001, err1001 = config_manager.compute_base(1001)
        assert_nil(b1001)
        assert_eq(err1001, "ERR_INDEX_OUT_OF_RANGE")

        -- Legacy 20-channel configuration migration
        local legacyPath = sdk.temp_path("test_legacy_20ch.json")
        local legacyCfg = {
            groupId = "THR_MAIN_L",
            aircraftIndexN = 2,
            baseChannel = 10020,
            channels = { thrustActuation = 10026, calibration = 10024 },
            mode = "REDSTONE"
        }
        config_manager.save(legacyPath, legacyCfg)

        local migrated, errLoad = config_manager.load(legacyPath)
        assert_not_nil(migrated)
        assert_eq(errLoad, "OK")
        assert_eq(migrated.baseChannel, 10040)
        assert_eq(migrated.channels.thrustActuation, 10050)
        assert_nil(migrated.channels.calibration)
        assert_nil(migrated.mode)
        assert_eq(migrated.interactionMode, "REDSTONE")
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
            channels = { thrustActuation = 10010 },
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

    it("handles dynamic hangar bay binding and discovery wildcard ALL", function()
        local mockModem = mock.modem()
        local cfg = {
            groupId = "THR_MAIN_L",
            aircraftDomainId = "AIRCRAFT_01",
            aircraftIndexN = 1,
            baseChannel = 10000,
            channels = { thrustActuation = 10010 },
            watchdogTimeoutMs = 300,
            nominalActuatorCount = 4,
            interactionMode = "REDSTONE",
            ports = { modemSide = "top", redstoneSide = "bottom", apiSides = {} }
        }

        local daemon = tca_daemon.init(cfg, mockModem)

        -- Dynamic Hangar Bay Bind OPEN
        local bindPkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 1,
            type = "MSG_CALIB_BAY_BIND",
            payload = { action = "OPEN", baseHangarChannel = 101 }
        }
        daemon:dispatch_modem_message(10010, 10010, bindPkt)
        assert_true(mockModem:isOpen(101))
        assert_true(mockModem:isOpen(104))

        -- Actuator Discovery with targetGroup = "ALL"
        local discReq = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 2,
            type = "MSG_ACTUATOR_DISCOVER_REQ",
            payload = { targetGroup = "ALL" }
        }
        daemon:dispatch_modem_message(104, 104, discReq)
        local ackRecord = mockModem._transmitted[#mockModem._transmitted]
        assert_not_nil(ackRecord)
        assert_eq(ackRecord.tx, 104)
        assert_eq(ackRecord.pkt.type, "MSG_ACTUATOR_DISCOVER_ACK")
        assert_eq(ackRecord.pkt.payload.interactionMode, "REDSTONE")
        assert_nil(ackRecord.pkt.payload.mode)

        -- Dynamic Hangar Bay Bind CLOSE
        local closePkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 3,
            type = "MSG_CALIB_BAY_BIND",
            payload = { action = "CLOSE", baseHangarChannel = 101 }
        }
        daemon:dispatch_modem_message(10010, 10010, closePkt)
        assert_false(mockModem:isOpen(101))
        assert_false(mockModem:isOpen(104))
    end)

    it("executes single-packet MSG_CHANNEL_REBIND 2-phase lifecycle and rollback", function()
        local mockModem = mock.modem()
        local tempCfgPath = sdk.temp_path("rebind_test_cfg.json")
        local cfg = {
            groupId = "THR_MAIN_L",
            aircraftDomainId = "AIRCRAFT_01",
            aircraftIndexN = 1,
            baseChannel = 10000,
            channels = { thrustActuation = 10010 },
            watchdogTimeoutMs = 300,
            nominalActuatorCount = 4,
            interactionMode = "REDSTONE",
            ports = { modemSide = "top", redstoneSide = "bottom", apiSides = {} },
            configPath = tempCfgPath
        }
        config_manager.save(tempCfgPath, cfg)
        mockModem:open(10010)

        local daemon = tca_daemon.init(cfg, mockModem)

        -- Phase 1: PREPARE
        local prepPkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 10,
            type = "MSG_CHANNEL_REBIND",
            payload = {
                action = "PREPARE",
                transactionId = "REBIND-TX-10000-10080",
                newBaseChannel = 10080
            }
        }
        daemon:dispatch_modem_message(10010, 10010, prepPkt)
        assert_true(mockModem:isOpen(10090))

        local ackRecord = mockModem._transmitted[#mockModem._transmitted]
        assert_not_nil(ackRecord)
        assert_eq(ackRecord.pkt.type, "MSG_CHANNEL_REBIND_ACK")
        assert_eq(ackRecord.pkt.payload.transactionId, "REBIND-TX-10000-10080")
        assert_eq(ackRecord.pkt.payload.status, "READY")

        -- ROLLBACK test
        local rollPkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 11,
            type = "MSG_CHANNEL_REBIND",
            payload = {
                action = "ROLLBACK",
                transactionId = "REBIND-TX-10000-10080",
                newBaseChannel = 10080
            }
        }
        daemon:dispatch_modem_message(10010, 10010, rollPkt)
        assert_false(mockModem:isOpen(10090))

        -- Prepare again for commit
        daemon:dispatch_modem_message(10010, 10010, prepPkt)
        assert_true(mockModem:isOpen(10090))

        -- Phase 2: COMMIT
        local commitPkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 12,
            type = "MSG_CHANNEL_REBIND",
            payload = {
                action = "COMMIT",
                transactionId = "REBIND-TX-10000-10080",
                newBaseChannel = 10080
            }
        }
        daemon:dispatch_modem_message(10010, 10010, commitPkt)
        assert_false(mockModem:isOpen(10010))
        assert_eq(daemon.cfg.baseChannel, 10080)
        assert_eq(daemon.cfg.channels.thrustActuation, 10090)
        assert_eq(daemon.cfg.aircraftIndexN, 3)

        local reloaded = config_manager.load(tempCfgPath)
        assert_not_nil(reloaded)
        assert_eq(reloaded.baseChannel, 10080)
        assert_eq(reloaded.channels.thrustActuation, 10090)
        assert_eq(reloaded.aircraftIndexN, 3)
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
