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

    it("normalizes flat manifest.lua schema into unified config table", function()
        local flat = {
            facilityId = "PAD_MANIFEST_02",
            sectorId = 2,
            padIndex = 3,
            mobility = "DYNAMIC",
            gacChannel = 50401,
            sectorFacilityChannel = 50402,
            sectorGpsReplyChannel = 50406,
            tacticalChannel = 50413,
        }
        local norm = config_store.normalize_config(flat)
        local ok, err = config_store.validate_config(norm)
        assert_true(ok, err)
        assert_eq(norm.padId, "PAD_MANIFEST_02")
        assert_eq(norm.mode, "DYNAMIC")
        assert_eq(norm.channels.sectorChannel, 50401)
        assert_eq(norm.channels.sectorGpsReplyChannel, 50406)
        assert_eq(norm.channels.tacticalChannel, 50413)
    end)

    it("normalizes flat manifest.lua JSON when loaded via load_config", function()
        local path = sdk.temp_path("flat_manifest_pad.json")
        local flatJson = textutils.serializeJSON({
            version = "2.4.0",
            facilityId = "PAD_BRAVO_01",
            sectorId = 1,
            padIndex = 1,
            mobility = "DYNAMIC",
            gacChannel = 50201,
            sectorFacilityChannel = 50202,
            sectorGpsReplyChannel = 50206,
            tacticalChannel = 50211,
        })
        local f = fs.open(path, "w")
        assert_not_nil(f)
        f.write(flatJson)
        f.close()

        local loaded, errLoad = config_store.load_config(path)
        assert_not_nil(loaded, errLoad)
        assert_nil(errLoad)
        assert_eq(loaded.padId, "PAD_BRAVO_01")
        assert_eq(loaded.mode, "DYNAMIC")
        assert_eq(loaded.sectorIndex, 1)
        assert_eq(loaded.channels.sectorChannel, 50201)
        assert_eq(loaded.channels.sectorFacilityChannel, 50202)
        assert_eq(loaded.channels.sectorGpsReplyChannel, 50206)
        assert_eq(loaded.channels.tacticalChannel, 50211)
    end)
end)
