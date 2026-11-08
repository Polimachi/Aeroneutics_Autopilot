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
end)
