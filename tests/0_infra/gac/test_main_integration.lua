-- tests/0_infra/gac/test_main_integration.lua
local config_loader = require("config_loader")
local facility_inventory = require("facility_inventory")
local allocation_engine = require("allocation_engine")
local beacon_broadcaster = require("beacon_broadcaster")
local gac_fsm = require("gac_fsm")

describe("GAC main application module integration smoke test", function()
    it("wires all modules and processes one complete event cycle synchronously", function()
        local cfg = config_loader.get_default_config()
        local inv = facility_inventory.create(cfg.facilities)
        local fsm = gac_fsm.create(cfg, inv, allocation_engine)
        local bc = beacon_broadcaster.create(cfg)
        
        -- Simulate checkin packet reception
        local checkinPkt = {
            ver = "1.9.5",
            type = "MSG_GAC_CHECKIN_REQ",
            time = 1000,
            payload = {
                sectorId = cfg.sectorId,
                aircraftId = "TEST_CRAFT",
                craftWeight = 10000,
                craftRadius = 4,
                currentPos = { x = 1200, y = 65, z = -800 }
            }
        }
        local slotAssign = fsm:handle_aircraft_checkin(checkinPkt)
        assert_not_nil(slotAssign)
        assert_eq(slotAssign.type, "MSG_ATC_SLOT_ASSIGN")
        
        -- Beacon generation
        local bPkt = bc:build_sector_beacon(inv, { speed = 2, direction = 180 }, "OPERATIONAL")
        assert_eq(bPkt.type, "MSG_FACILITY_BEACON")
        assert_eq(bPkt.payload.facilitiesSummary.freeLandingPads, 1) -- 1 free out of 2
    end)

    it("verifies config.lua exports valid default configuration", function()
        local configModule = require("config")
        assert_eq(type(configModule), "table")
        assert_not_nil(configModule.sectorId)
        assert_not_nil(configModule.baseSecChannel)
        assert_true(#configModule.facilities >= 1)
    end)

    it("executes operator facility add, dedicated attribute update, and delete with config persistence", function()
        local tui_view = require("tui_view")
        local path = sdk.temp_path("gac_op_test.json")
        local cfg = config_loader.get_default_config()
        local inv = facility_inventory.create(cfg.facilities)
        local tui = tui_view.create()

        local ctx = {
            inventory = inv,
            config = cfg,
            configPath = path,
            configLoader = config_loader,
            tui = tui
        }

        -- 1. Add facility with dedicatedAirframeTypes
        local okAdd = tui_view.apply_operator_action("ADD_FACILITY", {
            facilityId = "PAD_DED_03",
            type = "LANDING_PAD",
            tacticalChannel = 50213,
            maxSupportWeight = 30000.0,
            maxSupportRadius = 10.0,
            coordinates = { x = 1350.0, y = 65.0, z = -810.0 },
            status = "FREE",
            dedicatedAirframeTypes = { "ADVANCED_VTOL" }
        }, ctx)
        assert_true(okAdd)
        assert_true(inv:is_dedicated("PAD_DED_03"))

        -- 2. Edit dedicated attributes on index 1 (PAD_01)
        local okEdit = tui_view.apply_operator_action("EDIT_DEDICATED", 1, ctx, {
            dedicatedCraftIds = { "VIP_CRAFT_99" },
            dedicatedAirframeTypes = nil
        })
        assert_true(okEdit)
        assert_true(inv:is_dedicated("PAD_01"))

        -- 3. Delete facility at index 3 (PAD_DED_03)
        local okDel = tui_view.apply_operator_action("DELETE_FACILITY", 3, ctx)
        assert_true(okDel)
        assert_nil(inv:get_facility("PAD_DED_03"))

        -- Verify persisted config reflects changes
        local reloaded = config_loader.load_config(path)
        assert_eq(#reloaded.facilities, 2)
        assert_eq(reloaded.facilities[1].dedicatedCraftIds[1], "VIP_CRAFT_99")
    end)
end)
