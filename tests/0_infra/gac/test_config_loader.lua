-- tests/0_infra/gac/test_config_loader.lua
local config_loader = require("config_loader")

describe("GAC config loader and atomic persistence", function()
    it("returns valid default configuration with sector settings and facilities", function()
        local def = config_loader.get_default_config()
        assert_eq(type(def), "table")
        assert_eq(def.sectorId, "BASE_ALPHA_SECTOR_01")
        assert_eq(def.sectorIndex, 1)
        assert_eq(def.baseSecChannel, 50201)
        assert_eq(def.towerAtcChannel, 50001)
        assert_true(#def.facilities >= 1)
        
        local ok, err = config_loader.validate_config(def)
        assert_true(ok)
        assert_nil(err)
    end)

    it("rejects configuration missing mandatory sector fields", function()
        local bad = { sectorId = "TEST" }
        local ok, err = config_loader.validate_config(bad)
        assert_false(ok)
        assert_not_nil(err)
    end)

    it("performs atomic save and load round-trip", function()
        local path = sdk.temp_path("gac_config.json")
        local cfg = config_loader.get_default_config()
        cfg.sectorName = "Custom Test Sector"
        
        local okSave, errSave = config_loader.save_config(path, cfg)
        assert_true(okSave, errSave)
        
        local loaded, errLoad = config_loader.load_config(path)
        assert_not_nil(loaded)
        assert_nil(errLoad)
        assert_eq(loaded.sectorName, "Custom Test Sector")
        assert_eq(loaded.baseSecChannel, 50201)
    end)

    it("falls back to default config if file does not exist", function()
        local loaded, err = config_loader.load_config("/non_existent_gac_cfg.json")
        assert_not_nil(loaded)
        assert_nil(err)
        assert_eq(loaded.sectorId, "BASE_ALPHA_SECTOR_01")
    end)

    it("accepts valid string or string-array dedicatedCraftIds and dedicatedAirframeTypes", function()
        local cfg = config_loader.get_default_config()
        cfg.facilities[1].dedicatedCraftIds = "VTOL_VIP_01"
        cfg.facilities[2].dedicatedCraftIds = { "VTOL_VIP_01", "DRONE_SCOUT_02" }
        cfg.facilities[2].dedicatedAirframeTypes = { "ADVANCED_VTOL", "VECTORED_VTOL" }

        local ok, err = config_loader.validate_config(cfg)
        assert_true(ok)
        assert_nil(err)
    end)

    it("rejects malformed dedicatedCraftIds or dedicatedAirframeTypes in facility config", function()
        local cfg1 = config_loader.get_default_config()
        cfg1.facilities[1].dedicatedCraftIds = 12345
        local ok1, err1 = config_loader.validate_config(cfg1)
        assert_false(ok1)
        assert_eq(err1, "INVALID_DEDICATED_CRAFT_IDS")

        local cfg2 = config_loader.get_default_config()
        cfg2.facilities[1].dedicatedAirframeTypes = { "VECTORED_VTOL", 99 }
        local ok2, err2 = config_loader.validate_config(cfg2)
        assert_false(ok2)
        assert_eq(err2, "INVALID_DEDICATED_AIRFRAME_TYPES")

        local cfg3 = config_loader.get_default_config()
        cfg3.facilities[1].dedicatedCraftIds = { "" }
        local ok3, err3 = config_loader.validate_config(cfg3)
        assert_false(ok3)
        assert_eq(err3, "INVALID_DEDICATED_CRAFT_IDS")

        local cfg4 = config_loader.get_default_config()
        cfg4.facilities[1].dedicatedAirframeTypes = { key = "VECTORED_VTOL" }
        local ok4, err4 = config_loader.validate_config(cfg4)
        assert_false(ok4)
        assert_eq(err4, "INVALID_DEDICATED_AIRFRAME_TYPES")
    end)
end)
