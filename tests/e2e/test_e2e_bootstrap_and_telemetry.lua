-- tests/e2e/test_e2e_bootstrap_and_telemetry.lua
-- Scenario 1: GCS Channel Bootstrap & Realtime Telemetry Downlink Integration
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 1: GCS Bootstrap & Telemetry Downlink", function()
    it("completes full 40-channel bootstrap and fleet telemetry caching across GCS, AMM, and VAS", function()
        local bus = virtual_bus.create_bus({ clock = 1000.0 })

        local gcs = node_sandbox.create_node(bus, "GCS", "src/0_infra/gcs")
        local amm = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")

        -- 1. Initialize GCS app
        local gcs_main = gcs:require("main")
        local gcs_cfg = {
            system = { id = "GCS_01", domainId = "GCS_01", modemSide = "top" },
            channels = {
                bootstrapChannel = 50000,
                bandwidth = 40,
                baseChannelMin = 10000,
                baseChannelMax = 49960,
                maxCraftBlocks = 1000,
            },
            ui = { screenWidth = 51, screenHeight = 19, telemetryTimeoutSec = 5.0 },
        }
        local gcs_app = gcs_main.create_app(gcs_cfg, gcs.modem, "config/test_e2e_registry.json")
        assert_not_nil(gcs_app)
        assert_true(gcs.modem:isOpen(50000))

        -- 2. Negative Path Verification: Incompatible version & non-table rejection on CH 50000
        local ok_bad, err_bad = gcs_app:process_modem_message(50000, 50000, {
            ver = "0.9.0",
            domainId = "ROGUE_CRAFT",
            seq = 1,
            type = "MSG_BLOCK_REQUEST",
            time = 1000,
            payload = { domainId = "ROGUE_CRAFT", requestedBandwidth = 40 }
        })
        assert_false(ok_bad)
        assert_not_nil(err_bad)

        local ok_nontable, err_nontable = gcs_app:process_modem_message(50000, 50000, "INVALID_STRING_PACKET")
        assert_false(ok_nontable)
        assert_eq(err_nontable, "message is not a table")

        -- 3. Happy Path: AMM starts on bootstrap channel and requests 40-channel block
        local channel_sentinel = amm:require("channel_sentinel")
        local amm_state = channel_sentinel.init({
            system = { domainId = "AIRCRAFT_01", hardwareUuid = "HW-UUID-4401" },
            channels = { bootstrapChannel = 50000, bandwidth = 40 },
        })
        amm.modem:open(50000)

        local boot_req = channel_sentinel.start_bootstrap(amm_state, 1000)
        assert_eq(boot_req.type, "MSG_BLOCK_REQUEST")
        assert_eq(boot_req.requestedBandwidth, 40)

        -- Transmit request from AMM to GCS on CH 50000
        amm.modem:transmit(50000, 50000, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 1,
            type = boot_req.type,
            time = 1000,
            payload = {
                domainId = "AIRCRAFT_01",
                hardwareUuid = "HW-UUID-4401",
                requestedBandwidth = boot_req.requestedBandwidth,
            },
        })
        bus:step(0.05)

        -- Process inbound packet on GCS
        local gcs_inbox = gcs.modem:drain()
        assert_eq(#gcs_inbox, 1)
        local ok_proc = gcs_app:process_modem_message(gcs_inbox[1].channel, gcs_inbox[1].replyChannel, gcs_inbox[1].payload)
        assert_true(ok_proc)

        -- GCS should have transmitted MSG_BLOCK_ASSIGN on CH 50000
        bus:step(0.05)
        local assign_pkts = bus:find_packets({ type = "MSG_BLOCK_ASSIGN", channel = 50000 })
        assert_eq(#assign_pkts, 1)
        local assign_payload = assign_pkts[1].payload.payload
        assert_eq(assign_payload.blockId, 1)
        assert_eq(assign_payload.baseChannel, 10000)
        assert_eq(assign_payload.bandwidth, 40)

        -- 4. AMM receives assignment and commits Base=10000
        local amm_inbox = amm.modem:drain()
        assert_eq(#amm_inbox, 1)
        channel_sentinel.on_block_assign(amm_state, amm_inbox[1].payload.payload)
        assert_eq(amm_state.candidateBase, 10000)
        amm_state.baseChannel = amm_state.candidateBase

        -- AMM opens Base+0(10000), Base+1(10001), Base+2(10002), Base+3(10003), Base+4(10004), Base+5(10005)
        amm.modem:close(50000)
        amm.modem:open(10000)
        amm.modem:open(10001)
        amm.modem:open(10002)
        amm.modem:open(10003)
        amm.modem:open(10004)
        amm.modem:open(10005)

        -- Confirm GCS automatically opened telemetry downlink Base+3 (10003) upon assigning Block 1
        assert_true(gcs.modem:isOpen(10003))

        -- 5. VAS operates on Base=10000: opens Base+1(10001) and transmits telemetry on Base+2 (10002)
        vas.modem:open(10001)
        vas.modem:transmit(10002, 10002, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 10,
            type = "MSG_FLIGHT_TELEMETRY",
            time = 1050,
            payload = {
                attitude = { pitch = 2.5, roll = -1.0, heading = 180.0 },
                angularRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
                dynamics = { altitudeY = 125.0, verticalSpeed = 0.0, groundSpeed = 16.5 },
                fuel = 0.85,
                controlState = "NORMAL",
                activeSource = "FCP",
                sensorOk = true,
                actuatorHealth = { tap = true, asa = true, allOk = true },
            },
        })
        bus:step(0.05)

        -- AMM receives telemetry on 10002
        local amm_telem_inbox = amm.modem:drain()
        assert_eq(#amm_telem_inbox, 1)
        assert_eq(amm_telem_inbox[1].payload.type, "MSG_FLIGHT_TELEMETRY")

        -- 6. AMM aggregates telemetry and downlinks MSG_MFD_STATE on Base+3 (10003)
        amm.modem:transmit(10003, 10003, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 101,
            type = "MSG_MFD_STATE",
            time = 1060,
            payload = {
                fsmState = "CRUISE",
                flightMode = "AUTO_NAV",
                attitude = amm_telem_inbox[1].payload.payload.attitude,
                dynamics = amm_telem_inbox[1].payload.payload.dynamics,
                fuel = amm_telem_inbox[1].payload.payload.fuel,
                actuatorHealth = amm_telem_inbox[1].payload.payload.actuatorHealth,
            },
        })
        bus:step(0.05)

        -- 7. GCS receives MSG_MFD_STATE on Base+3 (10003) and updates fleet cache
        local gcs_telem_inbox = gcs.modem:drain()
        assert_eq(#gcs_telem_inbox, 1)
        local ok_tlm = gcs_app:process_modem_message(10003, 10003, gcs_telem_inbox[1].payload)
        assert_true(ok_tlm)

        local active_craft = gcs_app.fleet_tracker.get_active_craft(gcs_app.fleet)
        assert_not_nil(active_craft)
        assert_eq(active_craft.domainId, "AIRCRAFT_01")
        assert_eq(active_craft.baseChannel, 10000)
        assert_eq(active_craft.telemetry.fsmState, "CRUISE")
        assert_eq(active_craft.telemetry.dynamics.altitudeY, 125.0)
    end)
end)
