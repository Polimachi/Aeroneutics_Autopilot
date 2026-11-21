-- tests/0_infra/pocket_pda/test_pda_c2_and_remote_links.lua
local pda_network = require("pda_network")
local telemetry_hud_state = require("telemetry_hud_state")
local emergency_c2_controller = require("emergency_c2_controller")
local remote_link_controller = require("remote_link_controller")

local function make_cfg()
    return {
        schemaVersion = "1.0.0",
        system = {
            id = "PDA_01",
            domainId = "POCKET_PDA_01",
            modemSide = "back",
            loopFrequencyHz = 20,
            uiRefreshRateHz = 5,
        },
        defaults = {
            aircraftIndexN = 1,
            targetDomainId = "AIRCRAFT_01",
            hangarBayId = 1,
            fdrBoundIndexN = 1,
        },
        channels = {
            gcsBootstrapChannel = 50000,
            missionAckChannel = 50004,
        },
        stationIdPrefix = "HANGAR_BAY_",
    }
end

describe("Pocket PDA emergency E_STOP+dump, tactical C2, and PBIT controller", function()
    it("emits MSG_EMERGENCY_OVERRIDE and MSG_FDR_REMOTE_CMD DUMP_NOW on Base+9 (single and dual-target)", function()
        local modem = mock.modem({ wireless = true })
        local cfg = make_cfg()
        local net_ctx = pda_network.init(cfg, modem)
        local hud = telemetry_hud_state.init(cfg)
        local link_state = remote_link_controller.init(cfg)

        local ok = emergency_c2_controller.trigger_estop_and_fdr_dump(net_ctx, hud, link_state, "RANGE_SAFETY", 2000)
        assert_true(ok)
        assert_eq(#modem._transmitted, 2)

        local tx1 = modem._transmitted[1]
        assert_eq(tx1.tx, 10009)
        assert_eq(tx1.pkt.ver, "1.9.5")
        assert_eq(tx1.pkt.domainId, "AIRCRAFT_01")
        assert_eq(tx1.pkt.type, "MSG_EMERGENCY_OVERRIDE")
        assert_eq(tx1.pkt.payload.action, "E_STOP")
        assert_eq(tx1.pkt.payload.authKey, "ESTOP_CONFIRM_KEY")
        assert_eq(tx1.pkt.payload.source, "POCKET_PDA")
        assert_eq(tx1.pkt.payload.reason, "RANGE_SAFETY")

        local tx2 = modem._transmitted[2]
        assert_eq(tx2.tx, 10009)
        assert_eq(tx2.pkt.type, "MSG_FDR_REMOTE_CMD")
        assert_eq(tx2.pkt.payload.action, "DUMP_NOW")
        assert_eq(tx2.pkt.payload.targetAircraftIndexN, 1)
        assert_eq(tx2.pkt.payload.source, "POCKET_PDA")
        assert_eq(tx2.pkt.payload.reason, "PDA_ESTOP_DUMP")

        -- Dual-target when FDR is bound to N=3 (10089) while PDA is on N=1 (10009)
        modem._transmitted = {}
        link_state.fdr.boundIndexN = 3
        link_state.fdr.boundBaseChannel = 10080
        local ok_dual = emergency_c2_controller.trigger_estop_and_fdr_dump(net_ctx, hud, link_state, nil, 2500)
        assert_true(ok_dual)
        assert_eq(#modem._transmitted, 3)
        assert_eq(modem._transmitted[1].tx, 10009)
        assert_eq(modem._transmitted[1].pkt.type, "MSG_EMERGENCY_OVERRIDE")
        assert_eq(modem._transmitted[2].tx, 10009)
        assert_eq(modem._transmitted[2].pkt.type, "MSG_FDR_REMOTE_CMD")
        assert_eq(modem._transmitted[3].tx, 10089)
        assert_eq(modem._transmitted[3].pkt.type, "MSG_FDR_REMOTE_CMD")
        assert_eq(modem._transmitted[3].pkt.payload.action, "DUMP_NOW")

        assert_false(emergency_c2_controller.trigger_estop_and_fdr_dump({ modem = nil }, hud, link_state, nil, 2600))
    end)

    it("sends tactical C2 commands on Base+0 and PBIT request on Base+8", function()
        local modem = mock.modem({ wireless = true })
        local cfg = make_cfg()
        local net_ctx = pda_network.init(cfg, modem)
        local hud = telemetry_hud_state.init(cfg)

        local cases = {
            { input = "HOLD", cmd = "HOLD", fm = "HOVER_HOLD" },
            { input = "RTB", cmd = "RTH", fm = "FAILSAFE_RTH" },
            { input = "LAND_NEAREST", cmd = "LAND_NEAREST", fm = "LANDING" },
            { input = "LAND", cmd = "LAND", fm = "EMERGENCY_LAND" },
            { input = "ARM", cmd = "ARM", fm = "IDLE_ARMED" },
            { input = "DISARM", cmd = "DISARM", fm = "IDLE_ARMED" },
            { input = "TAKEOFF", cmd = "TAKEOFF", fm = "TAKEOFF" },
        }

        for idx, c in ipairs(cases) do
            local ok, err = emergency_c2_controller.send_tactical_c2(net_ctx, hud, c.input, { targetAlt = 120 }, 3000 + idx)
            assert_true(ok, "failed tactical cmd: " .. c.input .. " err=" .. tostring(err))
            assert_nil(err)
            local rec = modem._transmitted[#modem._transmitted]
            assert_eq(rec.tx, 10000)
            assert_eq(rec.pkt.type, "MSG_OPERATOR_CMD")
            assert_eq(rec.pkt.payload.authority, "GCS_OVERRIDE")
            assert_eq(rec.pkt.payload.command, c.cmd)
            assert_eq(rec.pkt.payload.flightMode, c.fm)
            assert_eq(rec.pkt.payload.targetCraft, "AIRCRAFT_01")
            assert_eq(rec.pkt.payload.params.source, "POCKET_PDA")
        end

        local bad_ok, bad_err = emergency_c2_controller.send_tactical_c2(net_ctx, hud, "UNKNOWN_OP", nil, 3100)
        assert_false(bad_ok)
        assert_not_nil(bad_err)

        local ok_pbit = emergency_c2_controller.send_pbit_request(net_ctx, true, 3200)
        assert_true(ok_pbit)
        local pbit_rec = modem._transmitted[#modem._transmitted]
        assert_eq(pbit_rec.tx, 10008)
        assert_eq(pbit_rec.pkt.type, "MSG_PBIT_REQ")
        assert_true(string.find(pbit_rec.pkt.payload.requestId, "^PDA%-PBIT%-") ~= nil)
        assert_eq(pbit_rec.pkt.payload.source, "POCKET_PDA")
        assert_true(pbit_rec.pkt.payload.runWiggle)
    end)
end)

describe("Pocket PDA remote Alignment and FDR link controller", function()
    it("sends MSG_ALIGN_REMOTE_CMD for Bay 1/2 and ingests Alignment status and ACK packets", function()
        local modem = mock.modem({ wireless = true })
        local cfg = make_cfg()
        local net_ctx = pda_network.init(cfg, modem)
        local link_state = remote_link_controller.init(cfg)

        local ok1, err1 = remote_link_controller.send_align_cmd(net_ctx, link_state, "BIND_SESSION", {
            bayId = 1,
            aircraftIndexN = 2,
            targetCraftDomain = "AIRCRAFT_02",
        }, 4000)
        assert_true(ok1)
        assert_nil(err1)
        local t1 = modem._transmitted[#modem._transmitted]
        assert_eq(t1.tx, 101)
        assert_eq(t1.rx, 102)
        assert_eq(t1.pkt.type, "MSG_ALIGN_REMOTE_CMD")
        assert_eq(t1.pkt.payload.action, "BIND_SESSION")
        assert_eq(t1.pkt.payload.stationId, "HANGAR_BAY_01")
        assert_eq(t1.pkt.payload.bayId, 1)
        assert_eq(t1.pkt.payload.aircraftIndexN, 2)
        assert_eq(t1.pkt.payload.baseHangarChannel, 101)
        assert_eq(t1.pkt.payload.source, "POCKET_PDA")

        local ok2, err2 = remote_link_controller.send_align_cmd(net_ctx, link_state, "START_PULSE", {
            bayId = 2,
            aircraftIndexN = 2,
        }, 4100)
        assert_true(ok2)
        assert_nil(err2)
        local t2 = modem._transmitted[#modem._transmitted]
        assert_eq(t2.tx, 111)
        assert_eq(t2.rx, 112)
        assert_eq(t2.pkt.payload.stationId, "HANGAR_BAY_02")
        assert_eq(t2.pkt.payload.bayId, 2)
        assert_eq(t2.pkt.payload.baseHangarChannel, 111)

        local bad_act, bad_act_err = remote_link_controller.send_align_cmd(net_ctx, link_state, "BOGUS_ACTION", {}, 4150)
        assert_false(bad_act)
        assert_not_nil(bad_act_err)

        -- Ingest MSG_ALIGN_REMOTE_STATUS on 102
        assert_true(remote_link_controller.ingest_align_packet(link_state, 102, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_02",
            seq = 5,
            type = "MSG_ALIGN_REMOTE_STATUS",
            time = 4200,
            payload = {
                stationId = "HANGAR_BAY_01",
                bayId = 1,
                aircraftIndexN = 2,
                fsmState = "SYNC_APPROVAL",
                status = "SESSION_STARTED",
                targetCraftDomain = "AIRCRAFT_02",
                baseHangarChannel = 101,
                craftBaseChannel = 10040,
                activeThruster = "THR_MAIN_L",
                controllabilityStatus = "FULL_6DOF_PASS",
                confidenceR2 = 0.992,
                reason = "READY_FOR_SYNC",
            },
        }, 4200))
        assert_eq(link_state.alignment.fsmState, "SYNC_APPROVAL")
        assert_eq(link_state.alignment.status, "SESSION_STARTED")
        assert_eq(link_state.alignment.activeThruster, "THR_MAIN_L")
        assert_eq(link_state.alignment.controllabilityStatus, "FULL_6DOF_PASS")
        assert_near(link_state.alignment.confidenceR2, 0.992, 1e-6)
        assert_eq(link_state.alignment.reason, "READY_FOR_SYNC")

        -- Ingest ACKs on 102 and ignore non-hangar channel 10002
        assert_true(remote_link_controller.ingest_align_packet(link_state, 102, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 6, type = "MSG_CALIBRATION_INIT_ACK", time = 4210,
            payload = { aircraftDomainId = "AIRCRAFT_02", hardwareUuid = "HW-1", bayId = 1, status = "READY", airframeType = "VTOL", baseChannel = 10040 },
        }, 4210))
        assert_eq(link_state.alignment.initStatus, "READY")

        assert_true(remote_link_controller.ingest_align_packet(link_state, 102, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 7, type = "MSG_CALIB_ACK", time = 4220,
            payload = { profileId = "PROF-AIRCRAFT_02", status = "ACCEPTED" },
        }, 4220))
        assert_eq(link_state.alignment.calibAckStatus, "ACCEPTED")

        assert_true(remote_link_controller.ingest_align_packet(link_state, 102, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 8, type = "MSG_CALIBRATION_CLOSE_ACK", time = 4230,
            payload = { bayId = 1, status = "CLOSED" },
        }, 4230))
        assert_eq(link_state.alignment.fsmState, "STANDBY")
        assert_eq(link_state.alignment.status, "CLOSED")

        assert_false(remote_link_controller.ingest_align_packet(link_state, 10002, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 9, type = "MSG_ALIGN_REMOTE_STATUS", time = 4240,
            payload = { stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 2, fsmState = "TUNING", status = "SESSION_STARTED" },
        }, 4240))
    end)

    it("sends all 6 FDR remote commands and dual-targets old/new channels on BIND_AIRCRAFT", function()
        local modem = mock.modem({ wireless = true })
        local cfg = make_cfg()
        local net_ctx = pda_network.init(cfg, modem)
        local link_state = remote_link_controller.init(cfg)
        assert_eq(link_state.fdr.boundIndexN, 1)

        -- BIND_AIRCRAFT from N=1 (10009) to N=4 (10129) must transmit to BOTH 10009 and 10129
        local ok_bind, err_bind = remote_link_controller.send_fdr_cmd(net_ctx, link_state, "BIND_AIRCRAFT", {
            targetAircraftIndexN = 4,
            targetDomainId = "AIRCRAFT_04",
            autoStartLogging = true,
            reason = "SWITCH_SORTIE",
        }, 5000)
        assert_true(ok_bind)
        assert_nil(err_bind)
        assert_eq(#modem._transmitted, 2)
        assert_eq(modem._transmitted[1].tx, 10009)
        assert_eq(modem._transmitted[2].tx, 10129)
        assert_eq(modem._transmitted[1].pkt.type, "MSG_FDR_REMOTE_CMD")
        assert_eq(modem._transmitted[1].pkt.payload.action, "BIND_AIRCRAFT")
        assert_eq(modem._transmitted[1].pkt.payload.targetAircraftIndexN, 4)
        assert_eq(link_state.fdr.boundIndexN, 4)
        assert_eq(link_state.fdr.boundBaseChannel, 10120)
        assert_eq(link_state.fdr.mode, "LOGGING")

        -- SET_MODE to STANDBY sends to boundBase+9 (10129) and net_ctx.baseChannel+9 (10009)
        modem._transmitted = {}
        local ok_mode, err_mode = remote_link_controller.send_fdr_cmd(net_ctx, link_state, "SET_MODE", {
            recordMode = "STANDBY",
        }, 5100)
        assert_true(ok_mode)
        assert_nil(err_mode)
        assert_eq(link_state.fdr.mode, "STANDBY")
        assert_eq(modem._transmitted[1].tx, 10129)
        assert_eq(modem._transmitted[2].tx, 10009)

        -- DUMP_NOW, EXPORT_NOW, ROLLOVER_NOW, CLEAR_BUFFER
        for _, act in ipairs({ "DUMP_NOW", "EXPORT_NOW", "ROLLOVER_NOW", "CLEAR_BUFFER" }) do
            local ok_a = remote_link_controller.send_fdr_cmd(net_ctx, link_state, act, { reason = "OP_" .. act }, 5200)
            assert_true(ok_a, "failed FDR action: " .. act)
            assert_eq(link_state.fdr.lastCmd, act)
        end

        local bad_mode_ok = remote_link_controller.send_fdr_cmd(net_ctx, link_state, "SET_MODE", { recordMode = "BOGUS" }, 5300)
        assert_false(bad_mode_ok)
    end)
end)
