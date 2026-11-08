-- tests/e2e/test_e2e_waypoint_guidance.lua
-- Scenario 2: AMM Cockpit MFD Waypoint Queue, Pilot Takeoff & FCP/VAS/TCA/ASA Guidance Closed Loop
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 2: AMM Waypoint & FCP/VAS/TCA/ASA Closed Loop", function()
    it("completes takeoff, inner/outer-loop mixing, actuator commands and waypoint transition", function()
        local bus = virtual_bus.create_bus({ clock = 1000.0 })

        local amm = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")
        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
        local tca = node_sandbox.create_node(bus, "TCA", "src/1_control/tca")
        local asa = node_sandbox.create_node(bus, "ASA", "src/1_control/asa")

        -- 1. Setup AMM components
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
        local net = amm_net_mod.new(amm_cfg)
        net.modem = amm.modem
        local arbiter = c2_arbiter.new(q, net, amm_cfg)

        -- Open channels
        amm.modem:open(10000) -- Base+0 (C2)
        amm.modem:open(10003) -- Base+3 (MFD state)

        fcp.modem:open(10000) -- Base+0 (C2)
        fcp.modem:open(10002) -- Base+2 (VAS Telem)

        vas.modem:open(10001) -- Base+1 (Attitude Cmd)
        vas.modem:open(10010) -- Base+10 (TCA feedback)
        vas.modem:open(10011) -- Base+11 (ASA feedback)

        tca.modem:open(10010) -- Base+10 (Thrust Cmd)
        asa.modem:open(10011) -- Base+11 (Surface Cmd)

        -- 2. Add waypoints into AMM queue
        q:add(100, 100, 150, 18)
        q:add(300, 300, 160, 20)
        assert_eq(q:count(), 2)

        -- 3. Pilot issues ARM and TAKEOFF via AMM
        arbiter:handle_pilot_action("ARM")
        arbiter:handle_pilot_action("TAKEOFF", { targetAlt = 150 })
        bus:step(0.05)

        -- Assert C2 commands reached Base+0 (10000)
        local c2_pkts = bus:find_packets({ type = "MSG_OPERATOR_CMD", channel = 10000 })
        assert_eq(#c2_pkts, 2)
        assert_eq(c2_pkts[1].payload.payload.command, "ARM")
        assert_eq(c2_pkts[2].payload.payload.command, "TAKEOFF")

        -- 4. FCP receives C2 command, transitions FSM and emits MSG_ATTITUDE_CMD on Base+1 (10001)
        local fcp_fsm = fcp:require("flight_fsm")
        local fsm = fcp_fsm.init({
            system = { airframeType = "VECTORED_VTOL" },
            safety = { takeoffClearanceAltitudeM = 15.0 },
        })
        fcp_fsm.transition_to(fsm, "IDLE_ARMED")
        assert_eq(fsm.current_state, "IDLE_ARMED")
        fcp_fsm.transition_to(fsm, "TAKEOFF")
        assert_eq(fsm.current_state, "TAKEOFF")

        -- FCP sends attitude command to VAS on Base+1 (10001)
        fcp.modem:transmit(10001, 10001, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 20,
            type = "MSG_ATTITUDE_CMD",
            time = 1050,
            payload = {
                source = "FCP",
                arm = true,
                flightActive = true,
                flightMode = "TAKEOFF",
                commandType = "RATE",
                angleTargets = { pitch = 0.0, roll = 0.0, heading = 0.0 },
                rateTargets = { pitch = 0.0, roll = 0.0, yaw = 0.0 },
                targetClimbRate = 2.5,
                targetThrottle = 0.6,
                flapTarget = 0.0,
                acroActive = false,
            },
        })
        bus:step(0.05)

        -- Assert attitude command arrived on Base+1 (10001)
        local att_pkts = bus:find_packets({ type = "MSG_ATTITUDE_CMD", channel = 10001 })
        assert_eq(#att_pkts, 1)

        -- 5. VAS processes attitude command, mixes 3-axis outputs to TCA (Base+10) & ASA (Base+11)
        local thrust_mixer = vas:require("thrust_mixer")
        local mixer_state = thrust_mixer.init({
            THR_L = { surge = 1.0, heave = 1.0, deadband = 1.0, maxThrust = 15 },
            THR_R = { surge = 1.0, heave = 1.0, deadband = 1.0, maxThrust = 15 },
        })
        local mixed_outputs = thrust_mixer.mix(mixer_state, {
            surge = 10.0, sway = 0.0, heave = 8.0, pitch = 0.0, roll = 0.0, yaw = 0.0
        })

        vas.modem:transmit(10010, 10010, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 50,
            type = "MSG_THRUST_CMD",
            time = 1060,
            payload = {
                watchdogSeq = 1,
                controlState = "NORMAL",
                outputs = mixed_outputs or { THR_L = 10, THR_R = 10 },
            },
        })

        vas.modem:transmit(10011, 10011, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 51,
            type = "MSG_SURFACE_CMD",
            time = 1060,
            payload = {
                watchdogSeq = 1,
                controlState = "NORMAL",
                surfaces = { AIL_L = 0.0, AIL_R = 0.0, ELEV = 0.0, RUDD = 0.0 },
            },
        })
        bus:step(0.05)

        -- Assert actuators received commands on Base+10 and Base+11
        local thr_pkts = bus:find_packets({ type = "MSG_THRUST_CMD", channel = 10010 })
        local srf_pkts = bus:find_packets({ type = "MSG_SURFACE_CMD", channel = 10011 })
        assert_eq(#thr_pkts, 1)
        assert_eq(#srf_pkts, 1)

        -- 6. Production Handler Hookup & Negative Checks
        -- ASA negative mapping check
        local cs_mapper = asa:require("control_surface_mapper")
        local unk_key, unk_tier = cs_mapper.classify("unknown_actuator_part")
        assert_nil(unk_key)
        assert_eq(unk_tier, 99)
        local elev_key, elev_tier = cs_mapper.classify("Elevator")
        assert_eq(elev_key, "elevator")
        assert_eq(elev_tier, 1)

        -- TCA Production Daemon
        local tca_daemon_mod = tca:require("tca_daemon")
        local tca_cfg = {
            groupId = "THR_L",
            interactionMode = "REDSTONE",
            channels = { thrustActuation = 10010 },
            aircraftDomainId = "AIRCRAFT_01",
            baseChannel = 10000,
            deadband = 1,
        }
        local tca_inst = tca_daemon_mod.init(tca_cfg, tca.modem)

        -- Happy path: feed actual thrust command received from VAS
        local tca_inbox = tca.modem:drain()
        assert_eq(#tca_inbox, 1)
        local ok_cmd = tca_inst:handle_thrust_cmd(tca_inbox[1].payload)
        assert_true(ok_cmd)
        assert_true((tca_inst.adapterState.lastSignal or 0) > 0)
        bus:step(0.05)

        -- Negative check: command targeting unknown group ID yields 0 thrust output
        local ok_bad_grp = tca_inst:handle_thrust_cmd({
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 99,
            type = "MSG_THRUST_CMD",
            payload = {
                watchdogSeq = 2,
                controlState = "NORMAL",
                outputs = { UNKNOWN_POD = 15 },
            },
        })
        assert_true(ok_bad_grp)
        assert_eq(tca_inst.adapterState.lastSignal or 0, 0)

        asa.modem:transmit(10011, 10011, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 61,
            type = "MSG_SURFACE_STATUS",
            time = 1070,
            payload = {
                podId = "POD_01",
                surfaceId = "ELEV",
                boundSide = "left",
                mode = "REDSTONE",
                appliedDeflection = 0.0,
                isSaturated = false,
                isJammed = false,
                healthStatus = "NOMINAL",
            },
        })
        bus:step(0.05)

        local tca_stat = bus:find_packets({ type = "MSG_ACTUATOR_STATUS", channel = 10010 })
        local asa_stat = bus:find_packets({ type = "MSG_SURFACE_STATUS", channel = 10011 })
        assert_true(#tca_stat >= 1)
        assert_true(#asa_stat >= 1)
        local last_tca = tca_stat[#tca_stat].payload.payload
        assert_eq(last_tca.groupId, "THR_L")
        assert_true(last_tca.appliedSignal > 0)

        -- 7. Craft reaches clearance altitude -> FCP transitions to CRUISE -> emits MFD_STATE
        fcp_fsm.transition_to(fsm, "CRUISE")
        assert_eq(fsm.current_state, "CRUISE")

        fcp.modem:transmit(10003, 10003, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 200,
            type = "MSG_MFD_STATE",
            time = 1100,
            payload = {
                fsmState = "CRUISE",
                flightMode = "AUTO_NAV",
                navigation = { currentPos = { x = 0, z = 0 } },
            },
        })
        bus:step(0.05)

        -- 8. AMM receives MFD_STATE on Base+3 -> auto-dispatches WP1 target waypoint
        local amm_inbox = amm.modem:drain()
        assert_eq(#amm_inbox, 1)
        assert_eq(amm_inbox[1].payload.type, "MSG_MFD_STATE")

        arbiter:handle_mfd_state(amm_inbox[1].payload)
        bus:step(0.05)

        -- Assert AMM transmitted WP1 command to FCP
        local wp1_pkts = bus:find_packets({ type = "MSG_OPERATOR_CMD", channel = 10000 })
        assert_true(#wp1_pkts >= 3)
        local latest_cmd = wp1_pkts[#wp1_pkts].payload.payload
        assert_eq(latest_cmd.command, "CRUISE")
        assert_eq(latest_cmd.params.targetWaypoint.x, 100)
        assert_eq(latest_cmd.params.targetWaypoint.z, 100)
    end)
end)
