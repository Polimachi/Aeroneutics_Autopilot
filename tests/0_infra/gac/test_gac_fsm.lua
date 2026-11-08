-- tests/0_infra/gac/test_gac_fsm.lua
local gac_fsm = require("gac_fsm")
local facility_inventory = require("facility_inventory")
local allocation_engine = require("allocation_engine")

describe("GAC sector FSM and multi-tier handoff protocols", function()
    local cfg = {
        sectorId = "BASE_ALPHA_SECTOR_01",
        baseSecChannel = 50201,
        towerAtcChannel = 50001
    }
    local samplePads = {
        {
            facilityId = "PAD_01",
            type = "LANDING_PAD",
            tacticalChannel = 50211,
            maxSupportWeight = 40000.0,
            maxSupportRadius = 12.0,
            coordinates = { x = 1250.0, y = 65.0, z = -820.0 },
            status = "FREE"
        },
        {
            facilityId = "PAD_02",
            type = "LANDING_PAD",
            tacticalChannel = 50212,
            maxSupportWeight = 40000.0,
            maxSupportRadius = 12.0,
            coordinates = { x = 1300.0, y = 65.0, z = -800.0 },
            status = "FREE"
        }
    }

    it("Tower ATC handoff negotiation: accepts if free pads exist", function()
        local inv = facility_inventory.create(samplePads)
        local fsm = gac_fsm.create(cfg, inv, allocation_engine)
        
        local req = {
            type = "MSG_ATC_SECTOR_HANDOFF_REQ",
            payload = {
                sectorId = "BASE_ALPHA_SECTOR_01",
                aircraftId = "AIRCRAFT_01",
                airframeType = "VECTORED_VTOL",
                craftWeight = 18500.0,
                craftRadius = 5.2
            }
        }
        local ack = fsm:handle_tower_handoff_req(req)
        assert_eq(ack.type, "MSG_ATC_SECTOR_HANDOFF_ACK")
        assert_eq(ack.payload.status, "ACCEPTED")
        assert_eq(ack.payload.assignedGacChannel, 50201)
    end)

    it("Full approach flow: Checkin -> Slot Assign -> Slot Ack -> Clearance", function()
        local inv = facility_inventory.create(samplePads)
        local fsm = gac_fsm.create(cfg, inv, allocation_engine)
        
        local checkin = {
            type = "MSG_GAC_CHECKIN_REQ",
            payload = {
                sectorId = "BASE_ALPHA_SECTOR_01",
                aircraftId = "AIRCRAFT_01",
                airframeType = "VECTORED_VTOL",
                craftWeight = 18500.0,
                craftRadius = 5.2,
                currentPos = { x = 1200.0, y = 100.0, z = -750.0 }
            }
        }
        local slotAssign, immediateClearance = fsm:handle_aircraft_checkin(checkin)
        assert_not_nil(slotAssign)
        assert_eq(slotAssign.type, "MSG_ATC_SLOT_ASSIGN")
        assert_eq(slotAssign.payload.aircraftId, "AIRCRAFT_01")
        assert_eq(slotAssign.payload.facilityId, "PAD_01")
        assert_nil(immediateClearance) -- Clearance is sent after slot ACK
        
        local slotAck = {
            type = "MSG_ATC_SLOT_ACK",
            payload = {
                facilityId = "PAD_01",
                aircraftId = "AIRCRAFT_01",
                status = "ACCEPTED",
                tacticalChannel = 50211
            }
        }
        local clearance = fsm:handle_pad_slot_ack(slotAck)
        assert_not_nil(clearance)
        assert_eq(clearance.type, "MSG_GAC_APPROACH_CLEARANCE")
        assert_eq(clearance.payload.status, "CLEARED")
        assert_eq(clearance.payload.assignedFacilityId, "PAD_01")
        assert_eq(clearance.payload.assignedTacticalChannel, 50211)
    end)

    it("Go-Around flow: Isolates failed pad and redirects to secondary pad on abort clear", function()
        local inv = facility_inventory.create(samplePads)
        local fsm = gac_fsm.create(cfg, inv, allocation_engine)
        
        -- Reserve PAD_01 for AIRCRAFT_01
        inv:update_status("PAD_01", "RESERVED", "AIRCRAFT_01")
        fsm:record_slot_assignment("PAD_01", "AIRCRAFT_01", 100.0, 120)
        
        -- PAD_01 sends abort
        local abortMsg = {
            type = "MSG_ABORT_APPROACH",
            payload = {
                facilityId = "PAD_01",
                aircraftId = "AIRCRAFT_01",
                reason = "DECK_UNSTABLE"
            }
        }
        fsm:handle_abort_approach(abortMsg)
        assert_eq(inv:get_facility("PAD_01").status, "GO_AROUND")
        
        -- Aircraft reports safe altitude reached
        local abortClear = {
            type = "MSG_ATC_ABORT_CLEAR",
            payload = {
                sectorId = "BASE_ALPHA_SECTOR_01",
                facilityId = "PAD_01",
                aircraftId = "AIRCRAFT_01",
                currentAltitude = 100.0
            }
        }
        local newSlotAssign, divertClearance = fsm:handle_abort_clear(abortClear)
        assert_not_nil(newSlotAssign)
        assert_eq(newSlotAssign.payload.facilityId, "PAD_02") -- Redirected to PAD_02!
    end)

    it("Slot timeout triggers pad FREE reset after 120 seconds", function()
        local inv = facility_inventory.create(samplePads)
        local fsm = gac_fsm.create(cfg, inv, allocation_engine)
        inv:update_status("PAD_01", "RESERVED", "AIRCRAFT_01")
        fsm:record_slot_assignment("PAD_01", "AIRCRAFT_01", 100.0, 120)
        
        local actions1 = fsm:tick(150.0) -- 50s elapsed
        assert_eq(#actions1, 0)
        assert_eq(inv:get_facility("PAD_01").status, "RESERVED")
        
        local actions2 = fsm:tick(221.0) -- 121s elapsed (>120s)
        assert_eq(#actions2, 1)
        assert_eq(actions2[1].type, "SLOT_TIMEOUT")
        assert_eq(inv:get_facility("PAD_01").status, "FREE")
    end)
end)
