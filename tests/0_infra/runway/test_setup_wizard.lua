-- tests/0_infra/runway/test_setup_wizard.lua
local setup_wizard = require("modules.setup_wizard")
local offset_transform = require("modules.offset_transform")
local config_store = require("modules.config_store")

describe("Runway Setup Wizard & Config Persistence", function()
    it("derives sector channels and saves/reloads /runway/config.json atomically", function()
        local wiz = setup_wizard.create(offset_transform)
        local ch = setup_wizard.derive_channels(2, 3)
        assert_eq(ch.sectorChannel, 50401)
        assert_eq(ch.sectorFacilityChannel, 50402)
        assert_eq(ch.sectorGpsReplyChannel, 50406)
        assert_eq(ch.tacticalChannel, 50413)

        local okDyn, codeDyn = wiz:evaluate_sensors("DYNAMIC", { gimbal = false, altitude = true, velocity = true })
        assert_false(okDyn)
        assert_eq(codeDyn, "HALT_WITH_WARNING")

        local cfg = wiz:assemble_config({
            facilityId = "RWY_TEST_01",
            sectorId = 2,
            runwayIndex = 3,
            mobility = "STATIC",
            glideSlopeAngle = 3.0,
            touchdownZoneLength = 75.0,
        })
        local testPath = "/runway/test_cfg.json"
        local okSave, errSave = config_store.save_config(testPath, cfg)
        assert_true(okSave, tostring(errSave))

        local loaded, errLoad = config_store.load_config(testPath)
        assert_nil(errLoad)
        assert_eq(loaded.facilityId, "RWY_TEST_01")
        assert_eq(loaded.tacticalChannel, 50413)
        assert_eq(loaded.glideSlopeAngle, 3.0)
        assert_eq(loaded.touchdownZoneLength, 75.0)
    end)
end)
