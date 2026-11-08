-- tests/0_infra/landing_pad/test_config_store.lua
local config_store = require("config_store")

describe("Landing pad configuration store and persistence", function()
    it("returns default config matching v2.4.0 schema", function()
        local def = config_store.get_default_config()
        assert_eq(type(def), "table")
        assert_eq(def.version, "2.4.0")
        assert_eq(def.facilityId, "PAD_BRAVO_01")
        assert_eq(def.sectorId, 1)
        assert_eq(def.padIndex, 1)
        assert_eq(def.tacticalChannel, 50211)
        assert_eq(def.gacChannel, 50201)
        assert_eq(def.sectorFacilityChannel, 50202)
        assert_eq(def.sectorGpsReplyChannel, 50206)
        
        local ok, err = config_store.validate_config(def)
        assert_true(ok)
        assert_nil(err)
    end)

    it("rejects incomplete configuration", function()
        local bad = { facilityId = "PAD_01" }
        local ok, err = config_store.validate_config(bad)
        assert_false(ok)
        assert_not_nil(err)
    end)

    it("saves and loads configuration atomically", function()
        local path = sdk.temp_path("pad_config.json")
        local cfg = config_store.get_default_config()
        cfg.facilityId = "PAD_CUSTOM_99"
        
        local okSave, errSave = config_store.save_config(path, cfg)
        assert_true(okSave, errSave)
        
        local loaded, errLoad = config_store.load_config(path)
        assert_not_nil(loaded)
        assert_nil(errLoad)
        assert_eq(loaded.facilityId, "PAD_CUSTOM_99")
    end)
end)
