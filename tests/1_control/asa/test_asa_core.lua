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
            podId = "WAP_L",
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
            podId = "WAP_L",
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

