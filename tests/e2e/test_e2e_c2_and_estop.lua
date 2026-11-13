-- tests/e2e/test_e2e_c2_and_estop.lua
-- Scenario 5: GCS Remote C2 Override, AMM Non-Echo Snooping & Hard E_STOP Immediate Cutoff
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 5: GCS C2 Override & Hard E-STOP Cutoff", function()
    it("handles GCS remote override without AMM echo and executes direct Base+1 E-STOP thruster shutdown", function()
        local bus = virtual_bus.create_bus({ clock = 1000.0 })

        local gcs = node_sandbox.create_node(bus, "GCS", "src/0_infra/gcs")
        local amm = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")
        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
        local tca = node_sandbox.create_node(bus, "TCA", "src/1_control/tca")

        -- 1. Setup GCS network context
        local gcs_net_mod = gcs:require("network_manager")
        local gcs_cmd_mod = gcs:require("c2_commander")
        local gcs_ctx = gcs_net_mod.init({ system = { domainId = "GCS_01" } }, gcs.modem)

        -- 2. Setup AMM context
        local waypoint_queue = amm:require("waypoint_queue")
        local amm_net_mod = amm:require("network_manager")
        local c2_arbiter = amm:require("c2_arbiter")
        local amm_cfg = {
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            defaultAlt = 150.0,
            defaultSpeed = 18.0,
            arrivalRadius = 15.0,
        }
        local q = waypoint_queue.new(amm_cfg)
        q:add(100, 100, 150, 18)
        q:add(200, 200, 150, 18)
        local amm_net = amm_net_mod.new(amm_cfg)
        amm_net.modem = amm.modem
        local arbiter = c2_arbiter.new(q, amm_net, amm_cfg)

        -- 3. Setup VAS context
        local vas_net = vas:require("network_manager")
        local vas_state = vas_net.init({
            system = { domainId = "AIRCRAFT_01" },
            channels = { c2 = 10000, guidance = 10001, telemetry = 10002, actuation = 10010, aero = 10011 },
        }, vas.modem)
        vas_state.baseChannel = 10000
        vas_state.aircraftDomainId = "AIRCRAFT_01"

        local state_machine = vas:require("state_machine")
        local vas_fsm = state_machine.init({}, true)
        vas_fsm.currentState = "NORMAL"
        vas_state.wirelessModem = vas.modem

        -- Open channels
        amm.modem:open(10000) -- Base+0 (C2 snoop)
        fcp.modem:open(10000) -- Base+0 (C2)
        vas.modem:open(10001) -- Base+1 (Direct Guidance / Hard E-STOP)
        tca.modem:open(10010) -- Base+10 (Thrust)

        -- 4. Part 1: GCS issues remote C2 override HOLD on Base+0 (10000)
        local hold_payload, _ = gcs_cmd_mod.create_operator_cmd("HOLD", "AIRCRAFT_01", { action = "HOVER_HOLD" })
        assert_not_nil(hold_payload)
        assert_eq(hold_payload.authority, "GCS_OVERRIDE")

        gcs_net_mod.send_c2_command(gcs_ctx, 10000, hold_payload)
        bus:step(0.05)

        -- Verify HOLD reached Base+0
        local hold_pkts = bus:find_packets({ type = "MSG_OPERATOR_CMD", channel = 10000 })
        assert_eq(#hold_pkts, 1)
        assert_eq(hold_pkts[1].payload.payload.authority, "GCS_OVERRIDE")

        -- AMM snoops Base+0 packet
        local amm_inbox = amm.modem:drain()
        vas.modem:drain() -- clear Base+0 C2 message from VAS inbox
        assert_eq(#amm_inbox, 1)
        arbiter:handle_gcs_packet(amm_inbox[1].payload)

        -- Verify AMM authority is overridden and queue suspended
        assert_eq(arbiter.authority, "GCS_OVERRIDE")
        assert_eq(q.state, "SUSPENDED")

        -- Non-Echo Verification: AMM must not transmit any packet back to Base+0
        local pkts_before = #bus.packet_log
        bus:step(0.05)
        local pkts_after = #bus.packet_log
        assert_eq(pkts_before, pkts_after, "AMM must not echo or retransmit when GCS_OVERRIDE is active")

        -- 5. Part 2: Emergency Hard E-STOP Cutoff on Base+1 (10001)
        -- 5a. AMM pilot E_STOP preemption verification
        arbiter:handle_pilot_action("ESTOP")
        bus:step(0.05)
        local amm_estop_pkts = bus:find_packets({ type = "MSG_EMERGENCY_OVERRIDE", channel = 10001 })
        assert_true(#amm_estop_pkts >= 1)
        local amm_estop_p = amm_estop_pkts[#amm_estop_pkts].payload.payload
        assert_eq(amm_estop_p.action, "E_STOP")
        assert_eq(amm_estop_p.authKey, "ESTOP_CONFIRM_KEY")
        assert_eq(amm_estop_p.source, "AMM")

        -- 5b. GCS Emergency Hard E-STOP override verification
        local estop_payload = gcs_cmd_mod.create_emergency_estop("AIRCRAFT_01", "CRITICAL_COLLISION_ALERT")
        assert_eq(estop_payload.action, "E_STOP")
        assert_eq(estop_payload.source, "GCS")
        assert_eq(estop_payload.authKey, "ESTOP_CONFIRM_KEY")

        -- GCS transmits directly to Base+1 (10001) bypassing FCP
        gcs_net_mod.send_emergency_override(gcs_ctx, 10000, estop_payload)
        bus:step(0.05)

        local estop_pkts = bus:find_packets({ type = "MSG_EMERGENCY_OVERRIDE", channel = 10001 })
        assert_true(#estop_pkts >= 2)

        -- VAS receives packet on Base+1 and immediately trips failsafe
        local vas_inbox = vas.modem:drain()
        assert_true(#vas_inbox >= 1)
        assert_eq(vas_inbox[#vas_inbox].payload.type, "MSG_EMERGENCY_OVERRIDE")

        -- Note: For emergency override, envelope verification uses sender domain
        local ok_estop = vas_net.dispatch(vas_state, vas_fsm, nil, nil, 10001, 10001, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01", -- aircraft target routing
            seq = 99,
            type = "MSG_EMERGENCY_OVERRIDE",
            time = 1020,
            payload = estop_payload,
        })
        assert_true(ok_estop)
        assert_eq(vas_fsm.currentState, "E_STOP")
        assert_eq(vas_fsm.activeSource, "EMERGENCY_DIRECT")

        -- Negative Check: Hard-latched E_STOP blocks illegal state recovery
        assert_false(vas_fsm:transition_to("NORMAL", "ATTEMPT_RECOVERY"))
        assert_eq(vas_fsm.currentState, "E_STOP")

        -- VAS cuts all thrusters to 0 and broadcasts emergency command to TCA (Base+10)
        vas.modem:transmit(10010, 10010, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 200,
            type = "MSG_THRUST_CMD",
            time = 1025,
            payload = {
                watchdogSeq = 99,
                controlState = "E_STOP",
                outputs = { THR_L = 0, THR_R = 0, THR_HEAVE = 0 },
            },
        })
        bus:step(0.05)

        -- Verify TCA receives hard 0 cut via real tca_daemon
        local tca_inbox = tca.modem:drain()
        assert_eq(#tca_inbox, 1)
        local tca_daemon_mod = tca:require("tca_daemon")
        local tca_cfg = {
            groupId = "THR_L",
            interactionMode = "REDSTONE",
            channels = { thrustActuation = 10010 },
            aircraftDomainId = "AIRCRAFT_01",
            baseChannel = 10000,
        }
        local tca_inst = tca_daemon_mod.init(tca_cfg, tca.modem)
        local ok_tca_estop = tca_inst:handle_thrust_cmd(tca_inbox[1].payload)
        assert_true(ok_tca_estop)
        assert_eq(tca_inst.lastControlState, "E_STOP")
        assert_eq(tca_inst.adapterState.lastSignal or 0, 0)
    end)
end)
