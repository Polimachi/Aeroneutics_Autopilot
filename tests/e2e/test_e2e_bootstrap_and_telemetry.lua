-- tests/e2e/test_e2e_bootstrap_and_telemetry.lua
-- Scenario 1: GCS Channel Bootstrap & Realtime Telemetry Downlink Integration
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 1: GCS Bootstrap & Telemetry Downlink", function()
    it("completes full 40-channel bootstrap and fleet telemetry caching across GCS, FCP, and VAS", function()
        local bus = virtual_bus.create_bus({ clock = 1000.0 })

        local gcs = node_sandbox.create_node(bus, "GCS", "src/0_infra/gcs")
        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
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

        -- 2. FCP starts on bootstrap channel and requests channel block
        local channel_sentinel = fcp:require("channel_sentinel")
        local fcp_state = channel_sentinel.init({
            system = { domainId = "AIRCRAFT_01", hardwareUuid = "HW-UUID-4401" },
            channels = { bootstrapChannel = 50000, bandwidth = 40 },
        })
        fcp.modem:open(50000)

        local boot_req = channel_sentinel.start_bootstrap(fcp_state, 1000)
        assert_eq(boot_req.type, "MSG_BLOCK_REQUEST")
        assert_eq(boot_req.requestedBandwidth, 40)

        -- Transmit request from FCP to GCS on CH 50000
        fcp.modem:transmit(50000, 50000, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 1,
            type = boot_req.type,
            time = 1000,
            payload = {
                domainId = "AIRCRAFT_01",
                hardwareUuid = "HW-UUID-4401",
                requestedBandwidth = 40,
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

        -- 3. FCP receives assignment and commits Base=10000
        local fcp_inbox = fcp.modem:drain()
        assert_eq(#fcp_inbox, 1)
        channel_sentinel.on_block_assign(fcp_state, fcp_inbox[1].payload.payload)
        assert_eq(fcp_state.candidateBase, 10000)
        fcp_state.baseChannel = fcp_state.candidateBase

        -- FCP opens Base+0(10000), Base+1(10001), Base+2(10002), Base+3(10003), Base+5(10005)
        fcp.modem:close(50000)
        fcp.modem:open(10000)
        fcp.modem:open(10001)
        fcp.modem:open(10002)
        fcp.modem:open(10003)
        fcp.modem:open(10005)

        -- Confirm GCS automatically opened telemetry downlink Base+3 (10003) upon assigning Block 1
        assert_true(gcs.modem:isOpen(10003))

        -- 4. VAS operates on Base=10000: opens Base+1(10001) and transmits telemetry on Base+2 (10002)
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
                actuatorHealth = { tap = true, wap = true, allOk = true },
            },
        })
        bus:step(0.05)

        -- FCP receives telemetry on 10002
        local fcp_telem_inbox = fcp.modem:drain()
        assert_eq(#fcp_telem_inbox, 1)
        assert_eq(fcp_telem_inbox[1].payload.type, "MSG_FLIGHT_TELEMETRY")

        -- 5. FCP aggregates telemetry and downlinks MSG_MFD_STATE on Base+3 (10003)
        fcp.modem:transmit(10003, 10003, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 101,
            type = "MSG_MFD_STATE",
            time = 1060,
            payload = {
                fsmState = "CRUISE",
                flightMode = "AUTO_NAV",
                attitude = fcp_telem_inbox[1].payload.payload.attitude,
                dynamics = fcp_telem_inbox[1].payload.payload.dynamics,
                fuel = fcp_telem_inbox[1].payload.payload.fuel,
                actuatorHealth = fcp_telem_inbox[1].payload.payload.actuatorHealth,
            },
        })
        bus:step(0.05)

        -- 6. GCS receives MSG_MFD_STATE on Base+3 (10003) and updates fleet cache
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
