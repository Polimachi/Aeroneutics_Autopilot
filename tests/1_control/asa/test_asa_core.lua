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
