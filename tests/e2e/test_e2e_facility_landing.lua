-- tests/e2e/test_e2e_facility_landing.lua
-- Scenario 6: GAC & Landing Pad 3-Tier Tactical Landing Sequence
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 6: 3-Tier Facility Tactical Landing", function()
    it("completes full beacon -> checkin -> slot assign -> tactical guide -> touchdown -> occupied update sequence", function()
        local bus = virtual_bus.create_bus({ clock = 1000.0 })

        -- 1. Initialize nodes
        local gac = node_sandbox.create_node(bus, "GAC", "src/0_infra/gac")
        local pad = node_sandbox.create_node(bus, "PAD_01", "src/0_infra/landing_pad")
        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")

        -- 2. Setup GAC context
        local config_loader = gac:require("config_loader")
        local facility_inventory = gac:require("facility_inventory")
        local allocation_engine = gac:require("allocation_engine")
        local beacon_broadcaster = gac:require("beacon_broadcaster")
        local gac_fsm = gac:require("gac_fsm")

        local gac_cfg = config_loader.get_default_config()
        gac_cfg.facilities = {
            {
                facilityId = "PAD_01",
                type = "LANDING_PAD",
                tacticalChannel = 50211,
                maxSupportWeight = 40000.0,
                maxSupportRadius = 12.0,
                coordinates = { x = 1250.0, y = 65.0, z = -820.0 },
                status = "FREE",
                mobility = "STATIC"
            }
        }
        local inv = facility_inventory.create(gac_cfg.facilities)
        local fsm = gac_fsm.create(gac_cfg, inv, allocation_engine)
        local bc = beacon_broadcaster.create(gac_cfg)

        gac.modem:open(50201) -- Base_sec+0: Aircraft Check-in & Clearance
        gac.modem:open(50202) -- Base_sec+1: Sector Facility Backbone

        -- 3. Setup Landing Pad context
        local tactical_streamer = pad:require("tactical_streamer")
        local pad_fsm = pad:require("pad_fsm")
        local pad_cfg = {
            padId = "PAD_01",
            facilityId = "PAD_01",
            mode = "DYNAMIC",
            approachHeading = 180.0,
            safeDescentRate = 1.0,
            clearanceZoneRadius = 5.0,
            channels = {
                sectorFacilityChannel = 50202,
                tacticalChannel = 50211
            }
        }
        local streamer = tactical_streamer.create(pad_cfg)
        local pad_fsm_inst = pad_fsm.create(pad_cfg, streamer, true)

        pad.modem:open(50202) -- Sector Facility Backbone
        pad.modem:open(50211) -- Tactical Guidance Channel

        -- 4. Setup FCP context
        local facility_client = fcp:require("facility_client")
        local fcp_fc = facility_client.init({ safety = { maxApproachRetries = 3 } })

        fcp.modem:open(50003) -- Global GAC Beacon
        fcp.modem:open(50201) -- Sector Base Checkin / Clearance
        fcp.modem:open(50211) -- Tactical Guidance Channel

        -- 5. Step 1: GAC broadcasts sector beacon on 50003
        local beacon_pkt = bc:build_sector_beacon(inv, gac_cfg.surfaceWind, "OPERATIONAL")
        assert_not_nil(beacon_pkt)
        assert_eq(beacon_pkt.type, "MSG_FACILITY_BEACON")
        assert_eq(beacon_pkt.payload.facilitiesSummary.freeLandingPads, 1)

        gac.modem:transmit(50003, 50003, beacon_pkt)
        bus:step(0.05)

        local beacon_pkts = bus:find_packets({ type = "MSG_FACILITY_BEACON", channel = 50003 })
        assert_eq(#beacon_pkts, 1)

        local fcp_beacon_inbox = fcp.modem:drain()
        assert_eq(#fcp_beacon_inbox, 1)
        facility_client.update_beacons(fcp_fc, fcp_beacon_inbox[1].payload.payload, 1000)

        -- 6. Step 2: FCP issues MSG_GAC_CHECKIN_REQ on Base_sec+0 (50201)
        local checkin_pkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 101,
            type = "MSG_GAC_CHECKIN_REQ",
            time = 1050,
            payload = {
                sectorId = gac_cfg.sectorId,
                aircraftId = "AIRCRAFT_01",
                craftWeight = 12500,
                craftRadius = 4.5,
                currentPos = { x = 1200, y = 80, z = -800 },
                airframeType = "VECTORED_VTOL",
            }
        }
        fcp.modem:transmit(50201, 50201, checkin_pkt)
        bus:step(0.05)

        local req_pkts = bus:find_packets({ type = "MSG_GAC_CHECKIN_REQ", channel = 50201 })
        assert_eq(#req_pkts, 1)

        -- 7. Step 3: GAC processes check-in, allocates Pad, and issues MSG_ATC_SLOT_ASSIGN on 50202
        local gac_checkin_inbox = gac.modem:drain()
        assert_eq(#gac_checkin_inbox, 1)
        local slot_assign, clearance_err = fsm:handle_aircraft_checkin(gac_checkin_inbox[1].payload, gac_cfg.surfaceWind)
        assert_nil(clearance_err)
        assert_not_nil(slot_assign)
        assert_eq(slot_assign.type, "MSG_ATC_SLOT_ASSIGN")
        assert_eq(slot_assign.payload.facilityId, "PAD_01")
        assert_eq(slot_assign.payload.aircraftId, "AIRCRAFT_01")
        assert_eq(slot_assign.payload.tacticalChannel, 50211)

        gac.modem:transmit(50202, 50202, slot_assign)
        bus:step(0.05)

        local assign_pkts = bus:find_packets({ type = "MSG_ATC_SLOT_ASSIGN", channel = 50202 })
        assert_eq(#assign_pkts, 1)

        -- 8. Step 4: Landing Pad receives assignment, transitions to APPROACH_DYNAMIC, and replies MSG_ATC_SLOT_ACK
        local pad_assign_inbox = pad.modem:drain()
        assert_eq(#pad_assign_inbox, 1)
        local pad_acks = pad_fsm_inst:handle_backbone_message(pad_assign_inbox[1].payload, 10.0)
        assert_eq(#pad_acks, 1)
        assert_eq(pad_acks[1].type, "MSG_ATC_SLOT_ACK")
        assert_eq(pad_acks[1].payload.status, "ACCEPTED")
        assert_eq(pad_acks[1].payload.facilityId, "PAD_01")
        assert_eq(pad_fsm_inst:get_state(), "APPROACH_DYNAMIC")

        pad.modem:transmit(50202, 50202, pad_acks[1])
        bus:step(0.05)

        local ack_pkts = bus:find_packets({ type = "MSG_ATC_SLOT_ACK", channel = 50202 })
        assert_eq(#ack_pkts, 1)

        -- 9. Step 5: GAC receives Pad ACK and grants MSG_GAC_APPROACH_CLEARANCE to FCP on 50201
        local gac_ack_inbox = gac.modem:drain()
        assert_eq(#gac_ack_inbox, 1)
        local clearance_pkt = fsm:handle_pad_slot_ack(gac_ack_inbox[1].payload)
        assert_not_nil(clearance_pkt)
        assert_eq(clearance_pkt.type, "MSG_GAC_APPROACH_CLEARANCE")
        assert_eq(clearance_pkt.payload.status, "CLEARED")
        assert_eq(clearance_pkt.payload.assignedFacilityId, "PAD_01")
        assert_eq(clearance_pkt.payload.assignedTacticalChannel, 50211)

        gac.modem:transmit(50201, 50201, clearance_pkt)
        bus:step(0.05)

        local clr_pkts = bus:find_packets({ type = "MSG_GAC_APPROACH_CLEARANCE", channel = 50201 })
        assert_eq(#clr_pkts, 1)

        local fcp_clr_inbox = fcp.modem:drain()
        assert_eq(#fcp_clr_inbox, 1)
        local clr_payload = fcp_clr_inbox[1].payload.payload
        facility_client.on_atc_clearance(fcp_fc, {
            status = clr_payload.status,
            padId = clr_payload.assignedFacilityId,
            padChannel = clr_payload.assignedTacticalChannel,
            padMobility = "DYNAMIC",
        }, { x = 1200, y = 80, z = -800 }, 1100)
        assert_eq(fcp_fc.atcStatus, "CLEARED")
        assert_eq(fcp_fc.activePadId, "PAD_01")
        assert_eq(fcp_fc.padChannel, 50211)

        -- 10. Step 6: Landing Pad streams tactical guidance on 50211
        local guide_pkt = streamer:build_static_guide(
            201,
            "AIRCRAFT_01",
            { x = 1250.0, y = 65.0, z = -820.0 },
            gac_cfg.surfaceWind,
            false,
            1150
        )
        pad.modem:transmit(50211, 50211, guide_pkt)
        bus:step(0.05)

        local guide_pkts = bus:find_packets({ type = "MSG_FACILITY_STATIC_GUIDE", channel = 50211 })
        assert_eq(#guide_pkts, 1)

        local fcp_guide_inbox = fcp.modem:drain()
        assert_eq(#fcp_guide_inbox, 1)
        assert_eq(fcp_guide_inbox[1].payload.payload.facilityId, "PAD_01")

        -- 11. Step 7: FCP guides to touchdown and transmits MSG_TOUCHDOWN_COMPLETE on 50211
        local td_pkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 301,
            type = "MSG_TOUCHDOWN_COMPLETE",
            time = 1200,
            payload = {
                facilityId = "PAD_01",
                craftState = "GROUND_IDLE",
            }
        }
        fcp.modem:transmit(50211, 50211, td_pkt)
        bus:step(0.05)

        local td_pkts = bus:find_packets({ type = "MSG_TOUCHDOWN_COMPLETE", channel = 50211 })
        assert_eq(#td_pkts, 1)

        -- 12. Step 8: Landing Pad processes touchdown, transitions to OCCUPIED, and reports MSG_ATC_FACILITY_UPDATE on 50202
        local pad_td_inbox = pad.modem:drain()
        assert_eq(#pad_td_inbox, 1)
        local pad_updates = pad_fsm_inst:handle_tactical_message(pad_td_inbox[1].payload, 25.0)
        assert_eq(#pad_updates, 1)
        assert_eq(pad_fsm_inst:get_state(), "OCCUPIED")
        assert_eq(pad_updates[1].type, "MSG_ATC_FACILITY_UPDATE")
        assert_eq(pad_updates[1].payload.status, "OCCUPIED")
        assert_eq(pad_updates[1].payload.currentCraft, "AIRCRAFT_01")

        pad.modem:transmit(50202, 50202, pad_updates[1])
        bus:step(0.05)

        local upd_pkts = bus:find_packets({ type = "MSG_ATC_FACILITY_UPDATE", channel = 50202 })
        assert_eq(#upd_pkts, 1)

        -- 13. Step 9: GAC receives facility update, sets PAD_01 to OCCUPIED, and broadcasts sector status
        local gac_upd_inbox = gac.modem:drain()
        assert_eq(#gac_upd_inbox, 1)
        local status_pkt = fsm:handle_facility_update(gac_upd_inbox[1].payload)
        assert_not_nil(status_pkt)
        assert_eq(status_pkt.type, "MSG_GAC_SECTOR_STATUS")
        assert_eq(status_pkt.payload.occupiedPads, 1)
        assert_eq(status_pkt.payload.freePads, 0)
        assert_eq(inv:get_facility("PAD_01").status, "OCCUPIED")
    end)
end)
