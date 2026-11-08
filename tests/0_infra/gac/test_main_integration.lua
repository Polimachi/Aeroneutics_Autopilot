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
end)
