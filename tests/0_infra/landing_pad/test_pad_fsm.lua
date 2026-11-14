-- tests/0_infra/landing_pad/test_pad_fsm.lua
local pad_fsm = require("pad_fsm")
local tactical_streamer = require("tactical_streamer")

describe("Landing pad finite state machine and local backbone protocol", function()
    local dummyCfg = {
        padId = "PAD_BRAVO_01",
        mode = "DYNAMIC",
        channels = {
            tacticalChannel = 50211,
            sectorFacilityChannel = 50202
        }
    }

    it("initializes to IDLE state when sensors are healthy", function()
        local streamer = tactical_streamer.create(dummyCfg)
        local fsm = pad_fsm.create(dummyCfg, streamer, true)
        assert_eq(fsm:get_state(), "IDLE")
        assert_nil(fsm:get_current_craft())
    end)

    it("initializes to MAINTENANCE state when sensors are unhealthy", function()
        local streamer = tactical_streamer.create(dummyCfg)
        local fsm = pad_fsm.create(dummyCfg, streamer, false)
        assert_eq(fsm:get_state(), "MAINTENANCE")
    end)

    it("transitions IDLE -> APPROACH_DYNAMIC upon MSG_ATC_SLOT_ASSIGN and returns ACK", function()
        local streamer = tactical_streamer.create(dummyCfg)
        local fsm = pad_fsm.create(dummyCfg, streamer, true)

        local assignMsg = {
            ver = "1.9.5",
            type = "MSG_ATC_SLOT_ASSIGN",
            domainId = "GAC_APRON_01",
            seq = 501,
            time = 1000,
            payload = {
                facilityId = "PAD_BRAVO_01",
                aircraftId = "AIRCRAFT_01",
                slotDurationSec = 120,
                tacticalChannel = 50211
            }
        }

        local packets = fsm:handle_backbone_message(assignMsg, 10.0)
        assert_eq(fsm:get_state(), "APPROACH_DYNAMIC")
        assert_eq(fsm:get_current_craft(), "AIRCRAFT_01")
        assert_not_nil(packets)
        assert_eq(#packets, 1)
        assert_eq(packets[1].type, "MSG_ATC_SLOT_ACK")
        assert_eq(packets[1].payload.status, "ACCEPTED")
    end)

    it("rejects MSG_ATC_SLOT_ASSIGN when pad is not IDLE", function()
        local streamer = tactical_streamer.create(dummyCfg)
        local fsm = pad_fsm.create(dummyCfg, streamer, false) -- MAINTENANCE
        assert_eq(fsm:get_state(), "MAINTENANCE")

        local assignMsg = {
            ver = "1.9.5",
            type = "MSG_ATC_SLOT_ASSIGN",
            domainId = "GAC_APRON_01",
            seq = 501,
            time = 1000,
            payload = {
                facilityId = "PAD_BRAVO_01",
                aircraftId = "AIRCRAFT_01",
                slotDurationSec = 120,
                tacticalChannel = 50211
            }
        }

        local packets = fsm:handle_backbone_message(assignMsg, 10.0)
        assert_eq(fsm:get_state(), "MAINTENANCE")
        assert_not_nil(packets)
        assert_eq(#packets, 1)
        assert_eq(packets[1].type, "MSG_ATC_SLOT_ACK")
        assert_eq(packets[1].payload.status, "REJECTED")
        assert_eq(packets[1].payload.rejectReason, "MAINTENANCE")
    end)

    it("transitions APPROACH_DYNAMIC -> OCCUPIED upon MSG_TOUCHDOWN_COMPLETE", function()
        local streamer = tactical_streamer.create(dummyCfg)
        local fsm = pad_fsm.create(dummyCfg, streamer, true)

        -- Assign slot
        fsm:handle_backbone_message({
            ver = "1.9.5",
            type = "MSG_ATC_SLOT_ASSIGN",
            domainId = "GAC_APRON_01",
            seq = 501,
            time = 1000,
            payload = {
                facilityId = "PAD_BRAVO_01",
                aircraftId = "AIRCRAFT_01",
                slotDurationSec = 120
            }
        }, 10.0)

        -- Touchdown
        local tdMsg = {
            ver = "1.9.5",
            type = "MSG_TOUCHDOWN_COMPLETE",
            domainId = "AIRCRAFT_01",
            seq = 102,
            time = 1050,
            payload = {
                facilityId = "PAD_BRAVO_01",
                craftState = "GROUND_IDLE"
            }
        }
        local packets = fsm:handle_tactical_message(tdMsg, 20.0)
        assert_eq(fsm:get_state(), "OCCUPIED")
        assert_not_nil(packets)
        assert_eq(#packets, 1)
        assert_eq(packets[1].type, "MSG_ATC_FACILITY_UPDATE")
        assert_eq(packets[1].payload.status, "OCCUPIED")
        assert_eq(packets[1].payload.currentCraft, "AIRCRAFT_01")
    end)

    it("triggers GO_AROUND and emits MSG_ABORT_APPROACH when deck is unstable >= 3.0s", function()
        local streamer = tactical_streamer.create(dummyCfg)
        local fsm = pad_fsm.create(dummyCfg, streamer, true)

        -- Assign slot
        fsm:handle_backbone_message({
            ver = "1.9.5",
            type = "MSG_ATC_SLOT_ASSIGN",
            domainId = "GAC_APRON_01",
            seq = 501,
            time = 1000,
            payload = {
                facilityId = "PAD_BRAVO_01",
                aircraftId = "AIRCRAFT_01",
                slotDurationSec = 120
            }
        }, 10.0)

        -- Tick 1: unstable for 1.0s
        local pkts1 = fsm:tick(0.05, 11.0, "DANGEROUS", true)
        assert_eq(fsm:get_state(), "APPROACH_DYNAMIC")
        assert_eq(#pkts1, 0)

        -- Tick 2: unstable for 3.1s total (11.0 to 14.1)
        local pkts2 = fsm:tick(0.05, 14.1, "DANGEROUS", true)
        assert_eq(fsm:get_state(), "GO_AROUND")
        assert_true(#pkts2 >= 1)
        local abortPkt = nil
        for _, p in ipairs(pkts2) do
            if p.type == "MSG_ABORT_APPROACH" then abortPkt = p end
        end
        assert_not_nil(abortPkt)
        assert_eq(abortPkt.payload.reason, "DECK_UNSTABLE")
        assert_eq(abortPkt.payload.aircraftId, "AIRCRAFT_01")
    end)

    it("expires slot and returns to IDLE after 120s timeout without touchdown", function()
        local streamer = tactical_streamer.create(dummyCfg)
        local fsm = pad_fsm.create(dummyCfg, streamer, true)

        -- Assign slot at t = 10.0, expires at t = 130.0
        fsm:handle_backbone_message({
            ver = "1.9.5",
            type = "MSG_ATC_SLOT_ASSIGN",
            domainId = "GAC_APRON_01",
            seq = 501,
            time = 1000,
            payload = {
                facilityId = "PAD_BRAVO_01",
                aircraftId = "AIRCRAFT_01",
                slotDurationSec = 120
            }
        }, 10.0)

        -- Tick at t = 131.0
        local pkts = fsm:tick(0.05, 131.0, "STABLE", true)
        assert_eq(fsm:get_state(), "IDLE")
        assert_nil(fsm:get_current_craft())

        local updatePkt = nil
        for _, p in ipairs(pkts) do
            if p.type == "MSG_ATC_FACILITY_UPDATE" then updatePkt = p end
        end
        assert_not_nil(updatePkt)
        assert_eq(updatePkt.payload.status, "FREE")
    end)

    it("accepts ADVANCED_VTOL in MSG_ATC_SLOT_ASSIGN", function()
        local streamer = tactical_streamer.create(dummyCfg)
        local fsm = pad_fsm.create(dummyCfg, streamer, true)

        local assignMsg = {
            ver = "1.9.5",
            type = "MSG_ATC_SLOT_ASSIGN",
            domainId = "GAC_APRON_01",
            seq = 502,
            time = 1000,
            payload = {
                facilityId = "PAD_BRAVO_01",
                aircraftId = "ADV_CRAFT_01",
                airframeType = "ADVANCED_VTOL",
                slotDurationSec = 120,
                tacticalChannel = 50211
            }
        }

        local packets = fsm:handle_backbone_message(assignMsg, 10.0)
        assert_eq(fsm:get_state(), "APPROACH_DYNAMIC")
        assert_eq(fsm:get_current_craft(), "ADV_CRAFT_01")
        assert_eq(fsm:get_current_airframe(), "ADVANCED_VTOL")
        assert_eq(#packets, 1)
        assert_eq(packets[1].payload.status, "ACCEPTED")
    end)

    it("rejects incompatible airframe FIXED_WING in MSG_ATC_SLOT_ASSIGN", function()
        local streamer = tactical_streamer.create(dummyCfg)
        local fsm = pad_fsm.create(dummyCfg, streamer, true)

        local assignMsg = {
            ver = "1.9.5",
            type = "MSG_ATC_SLOT_ASSIGN",
            domainId = "GAC_APRON_01",
            seq = 503,
            time = 1000,
            payload = {
                facilityId = "PAD_BRAVO_01",
                aircraftId = "PLANE_01",
                airframeType = "FIXED_WING",
                slotDurationSec = 120,
                tacticalChannel = 50211
            }
        }

        local packets = fsm:handle_backbone_message(assignMsg, 10.0)
        assert_eq(fsm:get_state(), "IDLE")
        assert_eq(#packets, 1)
        assert_eq(packets[1].payload.status, "REJECTED")
        assert_eq(packets[1].payload.rejectReason, "INCOMPATIBLE_AIRFRAME")
    end)

    it("keeps GO_AROUND isolated until GAC sends MSG_ATC_FACILITY_UPDATE FREE", function()
        local streamer = tactical_streamer.create(dummyCfg)
        local fsm = pad_fsm.create(dummyCfg, streamer, true)

        fsm:handle_backbone_message({
            ver = "1.9.5",
            type = "MSG_ATC_SLOT_ASSIGN",
            domainId = "GAC_APRON_01",
            seq = 504,
            time = 1000,
            payload = {
                facilityId = "PAD_BRAVO_01",
                aircraftId = "AIRCRAFT_01",
                slotDurationSec = 120,
                tacticalChannel = 50211
            }
        }, 10.0)
        assert_near(fsm:get_slot_remaining_sec(40.0), 90.0, 1e-4)

        fsm:tick(0.05, 11.0, "DANGEROUS", true)
        fsm:tick(0.05, 14.5, "DANGEROUS", true)
        assert_eq(fsm:get_state(), "GO_AROUND")

        -- Even after 20s, GO_AROUND must remain until GAC releases it
        fsm:tick(0.05, 35.0, "STABLE", true)
        assert_eq(fsm:get_state(), "GO_AROUND")

        fsm:handle_backbone_message({
            ver = "1.9.5",
            type = "MSG_ATC_FACILITY_UPDATE",
            domainId = "GAC_APRON_01",
            seq = 505,
            time = 2000,
            payload = {
                facilityId = "PAD_BRAVO_01",
                status = "FREE"
            }
        }, 36.0)
        assert_eq(fsm:get_state(), "IDLE")
        assert_nil(fsm:get_current_craft())
    end)
end)
