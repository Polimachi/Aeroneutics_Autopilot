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

    it("handles nil/empty normalization, legacy aliases, missing-channel derivation, flat precedence, and mobility rules", function()
        local normNil = config_store.normalize_config(nil)
        local okNil, errNil = config_store.validate_config(normNil)
        assert_true(okNil, errNil)
        assert_eq(normNil.facilityId, "PAD_BRAVO_01")

        local normEmpty = config_store.normalize_config({})
        local okEmpty, errEmpty = config_store.validate_config(normEmpty)
        assert_true(okEmpty, errEmpty)

        local legacy = config_store.normalize_config({
            padId = "PAD_LEGACY",
            sectorIndex = 2,
            padIndex = 4,
            mode = "static",
            channels = {
                sectorChannel = 50401,
                sectorFacilityChannel = 50402,
                sectorGpsReplyChannel = 50406,
                tacticalChannel = 50414,
            }
        })
        local okLeg, errLeg = config_store.validate_config(legacy)
        assert_true(okLeg, errLeg)
        assert_eq(legacy.facilityId, "PAD_LEGACY")
        assert_eq(legacy.sectorId, 2)
        assert_eq(legacy.mobility, "STATIC")
        assert_eq(legacy.mode, "STATIC")
        assert_eq(legacy.gacChannel, 50401)
        assert_eq(legacy.tacticalChannel, 50414)

        local derived = config_store.normalize_config({
            facilityId = "",
            padId = "PAD_DERIVED",
            sectorId = 3,
            padIndex = 2,
            mobility = "",
            mode = "dynamic",
        })
        local okDer, errDer = config_store.validate_config(derived)
        assert_true(okDer, errDer)
        assert_eq(derived.facilityId, "PAD_DERIVED")
        assert_eq(derived.mobility, "DYNAMIC")
        assert_eq(derived.gacChannel, 50601)
        assert_eq(derived.sectorFacilityChannel, 50602)
        assert_eq(derived.sectorGpsReplyChannel, 50606)
        assert_eq(derived.tacticalChannel, 50612)

        local flatWins = config_store.normalize_config({
            facilityId = "PAD_FLAT_PREF",
            sectorId = 1,
            padIndex = 1,
            gacChannel = 50901,
            sectorFacilityChannel = 50902,
            sectorGpsReplyChannel = 50906,
            tacticalChannel = 50911,
            channels = {
                sectorChannel = 50201,
                sectorFacilityChannel = 50202,
                sectorGpsReplyChannel = 50206,
                tacticalChannel = 50211,
            }
        })
        assert_eq(flatWins.gacChannel, 50901)
        assert_eq(flatWins.channels.sectorChannel, 50901)
        assert_eq(flatWins.channels.sectorFacilityChannel, 50902)
        assert_eq(flatWins.channels.sectorGpsReplyChannel, 50906)
        assert_eq(flatWins.channels.tacticalChannel, 50911)

        local bogusNorm = config_store.normalize_config({
            facilityId = "PAD_BOGUS",
            sectorId = 1,
            padIndex = 1,
            mobility = "BOGUS",
        })
        assert_eq(bogusNorm.mobility, "BOGUS")
        local okBogus, errBogus = config_store.validate_config(bogusNorm)
        assert_false(okBogus)
        assert_eq(errBogus, "INVALID_MOBILITY")

        local badEmptyMob = config_store.get_default_config()
        badEmptyMob.mobility = ""
        local okEmpMob, errEmpMob = config_store.validate_config(badEmptyMob)
        assert_false(okEmpMob)
        assert_eq(errEmpMob, "INVALID_MOBILITY")

        local badLowerMob = config_store.get_default_config()
        badLowerMob.mobility = "static"
        local okLowMob, errLowMob = config_store.validate_config(badLowerMob)
        assert_false(okLowMob)
        assert_eq(errLowMob, "INVALID_MOBILITY")
    end)

    it("rejects incomplete JSON configs on load_config instead of hydrating defaults", function()
        local pEmpty = sdk.temp_path("pad_empty.json")
        local f1 = fs.open(pEmpty, "w")
        f1.write("{}")
        f1.close()
        local loaded1, err1 = config_store.load_config(pEmpty)
        assert_nil(loaded1)
        assert_true(string.find(tostring(err1), "VALIDATION_FAILED", 1, true) ~= nil)

        local pPartial = sdk.temp_path("pad_partial.json")
        local f2 = fs.open(pPartial, "w")
        f2.write(textutils.serializeJSON({ facilityId = "PAD_01" }))
        f2.close()
        local loaded2, err2 = config_store.load_config(pPartial)
        assert_nil(loaded2)
        assert_true(string.find(tostring(err2), "VALIDATION_FAILED", 1, true) ~= nil)
    end)
end)
