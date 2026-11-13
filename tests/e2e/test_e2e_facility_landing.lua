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
        local amm = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")

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

        -- 4. Setup AMM context
        local facility_client = amm:require("facility_client")
        local amm_fc = facility_client.init({ safety = { maxApproachRetries = 3 } })

        amm.modem:open(50003) -- Global GAC Beacon
        amm.modem:open(50201) -- Sector Base Checkin / Clearance
        amm.modem:open(50211) -- Tactical Guidance Channel

        -- 5. Step 1: GAC broadcasts sector beacon on 50003
        local beacon_pkt = bc:build_sector_beacon(inv, gac_cfg.surfaceWind, "OPERATIONAL")
        assert_not_nil(beacon_pkt)
        assert_eq(beacon_pkt.type, "MSG_FACILITY_BEACON")
        assert_eq(beacon_pkt.payload.facilitiesSummary.freeLandingPads, 1)

        gac.modem:transmit(50003, 50003, beacon_pkt)
        bus:step(0.05)

        local beacon_pkts = bus:find_packets({ type = "MSG_FACILITY_BEACON", channel = 50003 })
        assert_eq(#beacon_pkts, 1)

        local amm_beacon_inbox = amm.modem:drain()
        assert_eq(#amm_beacon_inbox, 1)
        facility_client.update_beacons(amm_fc, amm_beacon_inbox[1].payload.payload, 1000)

        -- 6. Step 2: AMM issues MSG_GAC_CHECKIN_REQ on Base_sec+0 (50201)
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
        amm.modem:transmit(50201, 50201, checkin_pkt)
        bus:step(0.05)

        local req_pkts = bus:find_packets({ type = "MSG_GAC_CHECKIN_REQ", channel = 50201 })
        assert_eq(#req_pkts, 1)

        -- 7. Step 3: GAC processes check-in, allocates Pad, and issues MSG_ATC_SLOT_ASSIGN on 50202
        local gac_checkin_inbox = gac.modem:drain()
        assert_eq(#gac_checkin_inbox, 1)

        -- Negative Check: Overweight aircraft (50,000kg > 40,000kg maxSupportWeight) is rejected with DENIED / OVERWEIGHT
        local overweight_pkt = {
            ver = "1.9.5",
            domainId = "HEAVY_CARGO_01",
            seq = 1,
            type = "MSG_GAC_CHECKIN_REQ",
            time = 1040,
            payload = {
                sectorId = gac_cfg.sectorId,
                aircraftId = "HEAVY_CARGO_01",
                craftWeight = 50000,
                craftRadius = 4.5,
                currentPos = { x = 1200, y = 80, z = -800 },
                airframeType = "VECTORED_VTOL",
            }
        }
        local bad_assign, bad_clearance = fsm:handle_aircraft_checkin(overweight_pkt, gac_cfg.surfaceWind)
        assert_nil(bad_assign)
        assert_not_nil(bad_clearance)
        assert_eq(bad_clearance.type, "MSG_GAC_APPROACH_CLEARANCE")
        assert_eq(bad_clearance.payload.status, "DENIED")
        assert_eq(bad_clearance.payload.reason, "OVERWEIGHT")

        -- Happy Path: Aircraft check-in within structural limits is accepted and allocated
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

        local amm_clr_inbox = amm.modem:drain()
        assert_eq(#amm_clr_inbox, 1)
        local clr_payload = amm_clr_inbox[1].payload.payload
        facility_client.on_atc_clearance(amm_fc, {
            status = clr_payload.status,
            assignedFacilityId = clr_payload.assignedFacilityId,
            assignedTacticalChannel = clr_payload.assignedTacticalChannel,
            padMobility = "DYNAMIC",
        }, { x = 1200, y = 80, z = -800 }, 1100)
        assert_eq(amm_fc.atcStatus, "CLEARED")
        assert_eq(amm_fc.activePadId, "PAD_01")
        assert_eq(amm_fc.padChannel, 50211)

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

        local amm_guide_inbox = amm.modem:drain()
        assert_eq(#amm_guide_inbox, 1)
        assert_eq(amm_guide_inbox[1].payload.payload.facilityId, "PAD_01")

        -- 11. Step 7: AMM guides to touchdown and transmits MSG_TOUCHDOWN_COMPLETE on 50211
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
        amm.modem:transmit(50211, 50211, td_pkt)
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

    it("enforces dedicated pad beacon isolation, FACILITY_DEDICATED rejection, and last-resort EMERGENCY commandeering", function()
        local bus = virtual_bus.create_bus({ clock = 2000.0 })

        local gac = node_sandbox.create_node(bus, "GAC", "src/0_infra/gac")
        local pad_pub = node_sandbox.create_node(bus, "PAD_PUB_01", "src/0_infra/landing_pad")
        local pad_vip = node_sandbox.create_node(bus, "PAD_VIP_02", "src/0_infra/landing_pad")
        local amm = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")

        local config_loader = gac:require("config_loader")
        local facility_inventory = gac:require("facility_inventory")
        local allocation_engine = gac:require("allocation_engine")
        local beacon_broadcaster = gac:require("beacon_broadcaster")
        local gac_fsm = gac:require("gac_fsm")

        local gac_cfg = config_loader.get_default_config()
        gac_cfg.facilities = {
            {
                facilityId = "PAD_PUB_01",
                type = "LANDING_PAD",
                tacticalChannel = 50211,
                maxSupportWeight = 40000.0,
                maxSupportRadius = 12.0,
                coordinates = { x = 1400.0, y = 65.0, z = -820.0 },
                status = "FREE",
                mobility = "STATIC"
            },
            {
                facilityId = "PAD_VIP_02",
                type = "LANDING_PAD",
                tacticalChannel = 50212,
                maxSupportWeight = 40000.0,
                maxSupportRadius = 12.0,
                coordinates = { x = 1210.0, y = 65.0, z = -805.0 },
                status = "FREE",
                mobility = "STATIC",
                dedicatedCraftIds = { "VIP_VTOL_01" },
                dedicatedAirframeTypes = { "ADVANCED_VTOL" }
            }
        }
        assert_true(config_loader.validate_config(gac_cfg))

        local inv = facility_inventory.create(gac_cfg.facilities)
        local fsm = gac_fsm.create(gac_cfg, inv, allocation_engine)
        local bc = beacon_broadcaster.create(gac_cfg)

        gac.modem:open(50201)
        gac.modem:open(50202)

        -- Setup PAD_PUB_01 and PAD_VIP_02 nodes
        local pub_streamer = pad_pub:require("tactical_streamer").create({
            padId = "PAD_PUB_01", facilityId = "PAD_PUB_01", mode = "STATIC",
            approachHeading = 180.0, safeDescentRate = 1.0, clearanceZoneRadius = 5.0,
            channels = { sectorFacilityChannel = 50202, tacticalChannel = 50211 }
        })
        local pub_fsm = pad_pub:require("pad_fsm").create({
            padId = "PAD_PUB_01", facilityId = "PAD_PUB_01", mode = "STATIC",
            channels = { sectorFacilityChannel = 50202, tacticalChannel = 50211 }
        }, pub_streamer, true)
        pad_pub.modem:open(50202)
        pad_pub.modem:open(50211)

        local vip_streamer = pad_vip:require("tactical_streamer").create({
            padId = "PAD_VIP_02", facilityId = "PAD_VIP_02", mode = "STATIC",
            approachHeading = 180.0, safeDescentRate = 1.0, clearanceZoneRadius = 5.0,
            channels = { sectorFacilityChannel = 50202, tacticalChannel = 50212 }
        })
        local vip_fsm = pad_vip:require("pad_fsm").create({
            padId = "PAD_VIP_02", facilityId = "PAD_VIP_02", mode = "STATIC",
            channels = { sectorFacilityChannel = 50202, tacticalChannel = 50212 }
        }, vip_streamer, true)
        pad_vip.modem:open(50202)
        pad_vip.modem:open(50212)

        local facility_client = amm:require("facility_client")
        local amm_fc = facility_client.init({ safety = { maxApproachRetries = 3 } })
        amm.modem:open(50003)
        amm.modem:open(50201)
        amm.modem:open(50212)

        -- 1. Beacon public-only free pad advertisement check (total=2, free=1)
        local beacon_pkt = bc:build_sector_beacon(inv, gac_cfg.surfaceWind, "OPERATIONAL")
        assert_eq(beacon_pkt.payload.facilitiesSummary.totalLandingPads, 2)
        assert_eq(beacon_pkt.payload.facilitiesSummary.freeLandingPads, 1)

        -- 2. Review Focus Check: Emergency craft arriving while PAD_PUB_01 is FREE must select PAD_PUB_01 (not PAD_VIP_02)
        local early_emg_pad, early_emg_err = allocation_engine.select_best_pad(inv:get_all_facilities(), {
            aircraftId = "EMG_EARLY_01",
            airframeType = "VECTORED_VTOL",
            craftWeight = 12000,
            craftRadius = 4.5,
            currentPos = { x = 1200, y = 80, z = -800 },
            isEmergency = true
        }, gac_cfg.surfaceWind)
        assert_nil(early_emg_err)
        assert_not_nil(early_emg_pad)
        assert_eq(early_emg_pad.facilityId, "PAD_PUB_01")

        -- 3. Unprivileged craft requesting preferredFacilityId = "PAD_VIP_02" while PAD_PUB_01 is FREE is redirected to PAD_PUB_01
        local reg1_assign, reg1_err = fsm:handle_aircraft_checkin({
            ver = "1.9.5",
            domainId = "REGULAR_VTOL_01",
            seq = 1,
            type = "MSG_GAC_CHECKIN_REQ",
            time = 2010,
            payload = {
                sectorId = gac_cfg.sectorId,
                aircraftId = "REGULAR_VTOL_01",
                craftWeight = 12000,
                craftRadius = 4.5,
                currentPos = { x = 1200, y = 80, z = -800 },
                airframeType = "VECTORED_VTOL",
                preferredFacilityId = "PAD_VIP_02",
                isEmergency = false
            }
        }, gac_cfg.surfaceWind)
        assert_nil(reg1_err)
        assert_not_nil(reg1_assign)
        assert_eq(reg1_assign.payload.facilityId, "PAD_PUB_01")

        -- Mark PAD_PUB_01 as OCCUPIED after REGULAR_VTOL_01 lands
        fsm:handle_facility_update({
            ver = "1.9.5",
            domainId = "PAD_PUB_01",
            seq = 2,
            type = "MSG_ATC_FACILITY_UPDATE",
            time = 2050,
            payload = {
                facilityId = "PAD_PUB_01",
                status = "OCCUPIED",
                currentCraft = "REGULAR_VTOL_01"
            }
        })
        assert_eq(inv:get_summary().freeLandingPads, 0)
        assert_eq(inv:get_facility("PAD_VIP_02").status, "FREE")

        -- 4. Unprivileged craft REGULAR_VTOL_02 rejected with FACILITY_DEDICATED at both Tier-1 Handoff and Tier-2 Check-In
        local handoff_ack = fsm:handle_tower_handoff_req({
            ver = "1.9.5",
            domainId = "TOWER_SECTOR_00",
            seq = 10,
            type = "MSG_ATC_SECTOR_HANDOFF_REQ",
            time = 2060,
            payload = {
                sectorId = gac_cfg.sectorId,
                aircraftId = "REGULAR_VTOL_02",
                airframeType = "VECTORED_VTOL",
                craftWeight = 12000,
                craftRadius = 4.5,
                isEmergency = false
            }
        })
        assert_eq(handoff_ack.payload.status, "REJECTED")
        assert_eq(handoff_ack.payload.rejectReason, "FACILITY_DEDICATED")

        amm.modem:transmit(50201, 50201, {
            ver = "1.9.5",
            domainId = "REGULAR_VTOL_02",
            seq = 11,
            type = "MSG_GAC_CHECKIN_REQ",
            time = 2070,
            payload = {
                sectorId = gac_cfg.sectorId,
                aircraftId = "REGULAR_VTOL_02",
                craftWeight = 12000,
                craftRadius = 4.5,
                currentPos = { x = 1200, y = 80, z = -800 },
                airframeType = "VECTORED_VTOL",
                preferredFacilityId = "PAD_VIP_02",
                isEmergency = false
            }
        })
        bus:step(0.05)

        local gac_deny_in = gac.modem:drain()
        assert_eq(#gac_deny_in, 1)
        local deny_assign, deny_clr = fsm:handle_aircraft_checkin(gac_deny_in[1].payload, gac_cfg.surfaceWind)
        assert_nil(deny_assign)
        assert_not_nil(deny_clr)
        assert_eq(deny_clr.payload.status, "DENIED")
        assert_eq(deny_clr.payload.reason, "FACILITY_DEDICATED")

        gac.modem:transmit(50201, 50201, deny_clr)
        bus:step(0.05)

        local amm_deny_in = amm.modem:drain()
        assert_eq(#amm_deny_in, 1)
        facility_client.on_atc_clearance(amm_fc, {
            status = amm_deny_in[1].payload.payload.status,
            reason = amm_deny_in[1].payload.payload.reason
        }, { x = 1200, y = 80, z = -800 }, 2075)
        assert_eq(amm_fc.atcStatus, "DENIED")

        -- 5. Emergency aircraft MAYDAY_VTOL_99 commandeers dedicated PAD_VIP_02 when all public pads are OCCUPIED
        amm.modem:transmit(50201, 50201, {
            ver = "1.9.5",
            domainId = "MAYDAY_VTOL_99",
            seq = 20,
            type = "MSG_GAC_CHECKIN_REQ",
            time = 2100,
            payload = {
                sectorId = gac_cfg.sectorId,
                aircraftId = "MAYDAY_VTOL_99",
                craftWeight = 14000,
                craftRadius = 5.0,
                currentPos = { x = 1205, y = 78, z = -802 },
                airframeType = "VECTORED_VTOL",
                isEmergency = true
            }
        })
        bus:step(0.05)

        local gac_emg_in = gac.modem:drain()
        assert_eq(#gac_emg_in, 1)
        local emg_assign, emg_err = fsm:handle_aircraft_checkin(gac_emg_in[1].payload, gac_cfg.surfaceWind)
        assert_nil(emg_err)
        assert_not_nil(emg_assign)
        assert_eq(emg_assign.payload.facilityId, "PAD_VIP_02")
        assert_eq(emg_assign.payload.aircraftId, "MAYDAY_VTOL_99")
        assert_eq(emg_assign.payload.tacticalChannel, 50212)

        gac.modem:transmit(50202, 50202, emg_assign)
        bus:step(0.05)

        -- PAD_VIP_02 processes slot assignment and replies MSG_ATC_SLOT_ACK
        pad_pub.modem:drain()
        local vip_assign_in = pad_vip.modem:drain()
        assert_eq(#vip_assign_in, 1)
        local vip_acks = vip_fsm:handle_backbone_message(vip_assign_in[1].payload, 2105)
        assert_eq(#vip_acks, 1)
        assert_eq(vip_acks[1].type, "MSG_ATC_SLOT_ACK")
        assert_eq(vip_acks[1].payload.status, "ACCEPTED")
        assert_eq(vip_fsm:get_state(), "APPROACH_STATIC")

        pad_vip.modem:transmit(50202, 50202, vip_acks[1])
        bus:step(0.05)

        -- GAC grants approach clearance on 50201 for commandeered PAD_VIP_02
        local gac_vip_ack = gac.modem:drain()
        assert_eq(#gac_vip_ack, 1)
        local emg_clr = fsm:handle_pad_slot_ack(gac_vip_ack[1].payload)
        assert_not_nil(emg_clr)
        assert_eq(emg_clr.payload.status, "CLEARED")
        assert_eq(emg_clr.payload.assignedFacilityId, "PAD_VIP_02")
        assert_eq(emg_clr.payload.assignedTacticalChannel, 50212)

        gac.modem:transmit(50201, 50201, emg_clr)
        bus:step(0.05)

        local amm_emg_clr = amm.modem:drain()
        assert_eq(#amm_emg_clr, 1)
        local emg_p = amm_emg_clr[1].payload.payload
        facility_client.on_atc_clearance(amm_fc, {
            status = emg_p.status,
            assignedFacilityId = emg_p.assignedFacilityId,
            assignedTacticalChannel = emg_p.assignedTacticalChannel,
            padMobility = "STATIC",
        }, { x = 1205, y = 78, z = -802 }, 2110)
        assert_eq(amm_fc.atcStatus, "CLEARED")
        assert_eq(amm_fc.activePadId, "PAD_VIP_02")
        assert_eq(amm_fc.padChannel, 50212)

        -- Touchdown on PAD_VIP_02 transitions pad and GAC inventory to OCCUPIED
        amm.modem:transmit(50212, 50212, {
            ver = "1.9.5",
            domainId = "MAYDAY_VTOL_99",
            seq = 21,
            type = "MSG_TOUCHDOWN_COMPLETE",
            time = 2150,
            payload = { facilityId = "PAD_VIP_02", craftState = "GROUND_IDLE" }
        })
        bus:step(0.05)

        local vip_td_in = pad_vip.modem:drain()
        assert_eq(#vip_td_in, 1)
        local vip_upds = vip_fsm:handle_tactical_message(vip_td_in[1].payload, 2155)
        assert_eq(#vip_upds, 1)
        assert_eq(vip_fsm:get_state(), "OCCUPIED")

        pad_vip.modem:transmit(50202, 50202, vip_upds[1])
        bus:step(0.05)

        local gac_vip_upd = gac.modem:drain()
        assert_eq(#gac_vip_upd, 1)
        local sec_status = fsm:handle_facility_update(gac_vip_upd[1].payload)
        assert_not_nil(sec_status)
        assert_eq(inv:get_facility("PAD_VIP_02").status, "OCCUPIED")
        assert_eq(inv:get_facility("PAD_VIP_02").currentCraft, "MAYDAY_VTOL_99")
    end)
end)
