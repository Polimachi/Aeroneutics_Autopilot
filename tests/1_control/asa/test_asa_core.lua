-- Pilot Unit Tests for ASA (Aerodynamic Surface Actuator)
-- Tests 1_control/asa control surface classification and scanning

local mapper = require("control_surface_mapper")

describe("1_control/asa control_surface_mapper", function()
    it("classifies Tier 1 PascalCase names", function()
        local k1, t1 = mapper.classify("Elevator")
        assert_eq(k1, "elevator")
        assert_eq(t1, 1)

        local k2, t2 = mapper.classify("LeftAileron")
        assert_eq(k2, "leftAileron")
        assert_eq(t2, 1)

        local k3, t3 = mapper.classify("RightAileron")
        assert_eq(k3, "rightAileron")
        assert_eq(t3, 1)

        local k4, t4 = mapper.classify("Rudder")
        assert_eq(k4, "rudder")
        assert_eq(t4, 1)
    end)

    it("classifies Tier 2 and Tier 3 prefixed/snake_case names", function()
        local k1, t1 = mapper.classify("create:mechanical_bearing_Elevator")
        assert_eq(k1, "elevator")
        assert_eq(t1, 2)

        local k2, t3 = mapper.classify("bearing_left_aileron_0")
        assert_eq(k2, "leftAileron")
        assert_eq(t3, 3)

        local unk_k, unk_t = mapper.classify("random_mod_bearing")
        assert_nil(unk_k)
        assert_eq(unk_t, 99)
    end)

    it("scans and binds 4 control surfaces from peripheral registry", function()
        local fake_periph = {
            getNames = function()
                return { "bearing_elevator", "LeftAileron", "RightAileron", "rudder_bearing" }
            end,
            wrap = function(name)
                return { id = name, is_actuator = true }
            end,
        }
        local mapped = mapper.scan(fake_periph)
        assert_not_nil(mapped.elevator)
        assert_eq(mapped.elevator.id, "bearing_elevator")
        assert_not_nil(mapped.leftAileron)
        assert_eq(mapped.leftAileron.id, "LeftAileron")
        assert_not_nil(mapped.rightAileron)
        assert_eq(mapped.rightAileron.id, "RightAileron")
        assert_not_nil(mapped.rudder)
    end)
end)

describe("1_control/asa config_manager", function()
    local config_manager = require("config_manager")

    it("computes 40-channel base and validates index bounds", function()
        assert_eq(config_manager.compute_base(1), 10000)
        assert_eq(config_manager.compute_base(2), 10040)
        assert_eq(config_manager.compute_base(1000), 49960)

        local b0, err0 = config_manager.compute_base(0)
        assert_nil(b0)
        assert_eq(err0, "ERR_INDEX_OUT_OF_RANGE")

        local b1001, err1001 = config_manager.compute_base(1001)
        assert_nil(b1001)
        assert_eq(err1001, "ERR_INDEX_OUT_OF_RANGE")
    end)

    it("generates default_config with debug=true and standard channel assignments", function()
        local def = config_manager.default_config()
        assert_not_nil(def)
        assert_true(def.debug, "default_config must have debug = true")
        assert_eq(def.aircraftIndexN, 1)
        assert_eq(def.baseChannel, 10000)
        assert_not_nil(def.channels)
        assert_eq(def.channels.surfaceActuation, 10011)
        assert_eq(def.watchdogTimeoutMs, 300)
        assert_eq(def.aircraftDomainId, "AIRCRAFT_01")
        assert_not_nil(def.ports)
        assert_eq(def.ports.modemSide, "top")
        assert_eq(def.ports.redstoneSide, "bottom")
    end)

    it("loads and saves config JSON while guaranteeing debug=true default", function()
        local test_path = sdk.temp_path("test_asa_nodebug.json")
        local raw = {
            podId = "ASA_L",
            aircraftIndexN = 1,
            baseChannel = 10000
        }
        local okSave = config_manager.save(test_path, raw)
        assert_true(okSave)

        local loaded, err = config_manager.load(test_path)
        assert_not_nil(loaded)
        assert_eq(err, "OK")
        assert_true(loaded.debug, "loaded.debug must default to true when omitted")
        assert_eq(loaded.channels.surfaceActuation, 10011)
    end)

    it("preserves debug=false when explicitly configured", function()
        local test_path = sdk.temp_path("test_asa_debug_false.json")
        local raw = {
            podId = "ASA_L",
            aircraftIndexN = 1,
            baseChannel = 10000,
            debug = false
        }
        config_manager.save(test_path, raw)

        local loaded, err = config_manager.load(test_path)
        assert_not_nil(loaded)
        assert_eq(err, "OK")
        assert_false(loaded.debug, "loaded.debug must preserve explicit false")
    end)
end)

describe("1_control/asa tui_dashboard and async/headless execution", function()
    local tui_dashboard = require("tui_dashboard")
    local asa_main = require("main")

    it("renders 51x19 dashboard with airframe info, control surfaces and watchdog status", function()
        local termMock = mock.term(51, 19)
        local state = {
            fsm = "ARMED_NORMAL",
            surfaces = { elevator = {}, leftAileron = {}, rightAileron = {}, rudder = {}, flaps = {} },
            modes = { elevator = "API", leftAileron = "API", rightAileron = "API", rudder = "API", flaps = "API" },
            deflections = { elevator = 0.2, leftAileron = -0.3, rightAileron = 0.3, rudder = 0.0, flaps = 0.5 },
            saturated = { elevator = false, leftAileron = true, rightAileron = false, rudder = false, flaps = false },
            watchdogExpired = false,
            tickCount = 128,
            status = "NOMINAL"
        }
        local cfg = {
            aircraftDomainId = "AIRCRAFT_01",
            podId = "ASA_L",
            baseChannel = 10000,
            channels = { surfaceActuation = 10011 }
        }

        tui_dashboard.render_dashboard(termMock, state, cfg)
        assert_true(termMock:_contains("ASA Surface Cluster"))
        assert_true(termMock:_contains("Node 06"))
        assert_true(termMock:_contains("AIRCRAFT_01"))
        assert_true(termMock:_contains("ELEVATOR"))
        assert_true(termMock:_contains("L.AILERON"))
        assert_true(termMock:_contains("R.AILERON"))
        assert_true(termMock:_contains("RUDDER"))
        assert_true(termMock:_contains("FLAPS"))
        assert_true(termMock:_contains("ARMED_NORMAL"))

        for y = 1, 19 do
            assert_true(#(termMock._lines[y]) <= 51, "line length must not exceed 51 columns at line " .. tostring(y))
        end
    end)

    it("provides clear_screen and restore_screen helpers resetting cursor and colors", function()
        local termMock = mock.term(51, 19)
        assert_eq(type(tui_dashboard.clear_screen), "function")
        assert_eq(type(tui_dashboard.restore_screen), "function")

        tui_dashboard.clear_screen(termMock)
        local cx, cy = termMock.getCursorPos()
        assert_eq(cx, 1)
        assert_eq(cy, 1)

        tui_dashboard.restore_screen(termMock)
        local rx, ry = termMock.getCursorPos()
        assert_eq(rx, 1)
        assert_eq(ry, 1)
    end)

    it("exports main, run, run_daemon, run_tui in asa main module", function()
        assert_not_nil(asa_main)
        assert_eq(type(asa_main.main), "function")
        assert_eq(type(asa_main.run), "function")
        assert_eq(type(asa_main.run_daemon), "function")
        assert_eq(type(asa_main.run_tui), "function")
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
            aircraftDomainId = "AIRCRAFT_01",
            podId = "ASA_L",
            baseChannel = 10000,
            channels = { surfaceActuation = 10011 },
            debug = true
        }

        asa_main.main(cfg)
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
        local termWriteCalled = false
        local termMock = {
            clear = function() termClearCalled = true end,
            blit = function() termBlitCalled = true end,
            write = function() termWriteCalled = true end,
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
            aircraftDomainId = "AIRCRAFT_01",
            podId = "ASA_L",
            baseChannel = 10040,
            channels = { surfaceActuation = 10051 },
            interactionMode = "API",
            debug = false
        }

        asa_main.main(cfg)
        assert_false(waitForAnyCalled, "parallel.waitForAny must NOT be called in headless mode")
        assert_false(termClearCalled, "term.clear must NOT be called in headless mode")
        assert_false(termBlitCalled, "term.blit must NOT be called in headless mode")
        assert_false(termWriteCalled, "term.write must NOT be called in headless mode")

        local headlessBannerFound = false
        for _, msg in ipairs(printed) do
            if string.find(msg, "%[ASA%] Surface daemon running in HEADLESS mode %(Base: 10040, Mode: API%)") then
                headlessBannerFound = true
                break
            end
        end
        assert_true(headlessBannerFound, "Expected headless banner with Base 10040 and Mode API printed")
    end)

    it("runs ui update on timer in run_tui and terminates on key q or t", function()
        local termMock = mock.term(51, 19)
        sdk.patch(_G, "term", termMock)

        local timerSeq = 400
        sdk.patch(os, "startTimer", function(duration)
            timerSeq = timerSeq + 1
            return timerSeq
        end)

        local state = {
            running = true,
            fsm = "READY_DISARMED",
            surfaces = {},
            modes = {},
            deflections = {},
            saturated = {},
            tickCount = 5
        }
        local cfg = {
            aircraftDomainId = "AIRCRAFT_01",
            podId = "ASA_L",
            baseChannel = 10000,
            channels = { surfaceActuation = 10011 }
        }

        local pullCount = 0
        local pullFn = function()
            pullCount = pullCount + 1
            if pullCount == 1 then
                return "timer", timerSeq
            else
                return "key", 20 -- keys.t
            end
        end
        sdk.patch(os, "pullEvent", pullFn)
        sdk.patch(os, "pullEventRaw", pullFn)

        asa_main.run_tui(state, cfg)
        assert_false(state.running, "state.running must be set to false on terminate key event")
        assert_true(pullCount >= 2, "must have handled timer and key events")
    end)

    it("isolates render errors in run_tui using pcall without crashing or stopping state.running prematurely", function()
        local termMock = mock.term(51, 19)
        sdk.patch(_G, "term", termMock)

        local renderAttemptCount = 0
        sdk.patch(tui_dashboard, "render_dashboard", function()
            renderAttemptCount = renderAttemptCount + 1
            error("Simulated catastrophic ASA TUI render error")
        end)

        local timerSeq = 500
        sdk.patch(os, "startTimer", function(duration)
            timerSeq = timerSeq + 1
            return timerSeq
        end)

        local state = {
            running = true,
            fsm = "READY_DISARMED",
            surfaces = {},
            modes = {},
            deflections = {},
            saturated = {},
            tickCount = 5
        }
        local cfg = {
            aircraftDomainId = "AIRCRAFT_01",
            podId = "ASA_L",
            baseChannel = 10000,
            channels = { surfaceActuation = 10011 }
        }

        local pullCount = 0
        local pullFn = function()
            pullCount = pullCount + 1
            if pullCount == 1 then
                return "timer", timerSeq
            else
                assert_true(state.running, "state.running must remain true despite render errors")
                return "key", 20 -- keys.t
            end
        end
        sdk.patch(os, "pullEvent", pullFn)
        sdk.patch(os, "pullEventRaw", pullFn)

        local ok, err = pcall(asa_main.run_tui, state, cfg)
        assert_true(ok, "run_tui must not propagate render exceptions")
        assert_false(state.running, "state.running must be false after operator terminates")
        assert_true(renderAttemptCount >= 1, "render_dashboard must have been attempted")
    end)

    it("handles terminate event gracefully in run_daemon and sets state.running to false", function()
        local state = {
            running = true,
            fsm = "READY_DISARMED",
            surfaces = {},
            modes = {},
            deflections = {},
            saturated = {},
            tickCount = 5
        }
        local cfg = {
            aircraftDomainId = "AIRCRAFT_01",
            podId = "ASA_L",
            baseChannel = 10000,
            channels = { surfaceActuation = 10011 }
        }

        local pullFn = function()
            return "terminate"
        end
        sdk.patch(os, "pullEventRaw", pullFn)

        asa_main.run_daemon(state, cfg)
        assert_false(state.running, "state.running must be false on terminate")
    end)
end)

