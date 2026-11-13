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
        local gcs = node_sandbox.create_node(bus, "GCS", "src/0_infra/gcs")

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
        amm.modem:open(10002) -- Base+2 (VAS Telem)
        amm.modem:open(10003) -- Base+3 (MFD state)
        amm.modem:open(10004) -- Base+4 (Trajectory Setpoint / Outer Loop Status)
        gcs.modem:open(10003) -- Base+3 (MFD state downlink)

        fcp.modem:open(10004) -- Base+4 (Trajectory Setpoint)
        fcp.modem:open(10002) -- Base+2 (VAS Telem)
        fcp.modem:open(10001) -- Base+1 (Attitude Cmd)

        vas.modem:open(10001) -- Base+1 (Attitude Cmd)
        vas.modem:open(10002) -- Base+2 (VAS Telem)
        vas.modem:open(10010) -- Base+10 (TCA feedback)
        vas.modem:open(10011) -- Base+11 (ASA feedback)

        tca.modem:open(10010) -- Base+10 (Thrust Cmd)
        asa.modem:open(10011) -- Base+11 (Aero Cmd)

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

        -- 4. AMM computes trajectory setpoint and sends to FCP on Base+4 (10004)
        local traj_gen = amm:require("trajectory_generator")
        local traj_state = traj_gen.init(amm_cfg)
        local setpoint = traj_gen.compute(traj_state, { pos = { x = 0, y = 64, z = 0 }, vel = { x = 0, y = 0, z = 0 } }, nil, {
            flightMode = "TAKEOFF", arm = true, flightActive = true, targetAlt = 150.0
        }, 0.05, 1000)
        net:send_trajectory_setpoint(setpoint)
        bus:step(0.05)

        local sp_pkts = bus:find_packets({ type = "MSG_TRAJECTORY_SETPOINT", channel = 10004 })
        assert_eq(#sp_pkts, 1)

        -- FCP outer_loop_controller computes MSG_ATTITUDE_CMD
        local outer_loop_controller = fcp:require("outer_loop_controller")
        local fcp_ctrl = outer_loop_controller.init({ system = { airframeType = "VECTORED_VTOL" } })
        local att_cmd = outer_loop_controller.compute(fcp_ctrl, { pos = { x = 0, y = 64, z = 0 }, vel = { x = 0, y = 0, z = 0 } }, sp_pkts[1].payload.payload, {
            currentState = "ACTIVE_TRACKING", flightActive = true, arm = true
        }, 0.05)

        -- FCP sends attitude command to VAS on Base+1 (10001)
        fcp.modem:transmit(10001, 10001, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 20,
            type = "MSG_ATTITUDE_CMD",
            time = 1050,
            payload = att_cmd,
        })
        bus:step(0.05)

        -- Assert attitude command arrived on Base+1 (10001)
        local att_pkts = bus:find_packets({ type = "MSG_ATTITUDE_CMD", channel = 10001 })
        assert_eq(#att_pkts, 1)
        assert_eq(att_pkts[1].payload.payload.commandType, "QUATERNION_RATE")
        assert_eq(att_pkts[1].payload.payload.source, "FCP")

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
            type = "MSG_AERO_CMD",
            time = 1060,
            payload = {
                watchdogSeq = 1,
                controlState = "NORMAL",
                surfaces = { elevator = 0.0, aileronLeft = 0.0, aileronRight = 0.0, rudder = 0.0, flaps = 0.0 },
            },
        })
        bus:step(0.05)

        -- Assert actuators received commands on Base+10 and Base+11
        local thr_pkts = bus:find_packets({ type = "MSG_THRUST_CMD", channel = 10010 })
        local srf_pkts = bus:find_packets({ type = "MSG_AERO_CMD", channel = 10011 })
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
            type = "MSG_AERO_STATUS",
            time = 1070,
            payload = {
                surfaceDeflections = { elevator = 0.0, aileronLeft = 0.0, aileronRight = 0.0, rudder = 0.0 },
                saturatedSurfaces = {},
                flapsPosition = 0.0,
                actuatorHealth = { allOk = true },
            },
        })
        bus:step(0.05)

        local tca_stat = bus:find_packets({ type = "MSG_ACTUATOR_STATUS", channel = 10010 })
        local asa_stat = bus:find_packets({ type = "MSG_AERO_STATUS", channel = 10011 })
        assert_true(#tca_stat >= 1)
        assert_true(#asa_stat >= 1)
        local last_tca = tca_stat[#tca_stat].payload.payload
        assert_eq(last_tca.groupId, "THR_L")
        assert_true(last_tca.appliedSignal > 0)

        -- 7. VAS reports clearance altitude telemetry on Base+2 -> FCP reports status on Base+4 -> AMM receives & dispatches WP1
        amm.modem:drain()
        vas.modem:transmit(10002, 10002, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 199,
            type = "MSG_FLIGHT_TELEMETRY",
            time = 1095,
            payload = {
                controlState = "NORMAL",
                activeSource = "FCP",
                dynamics = { altitudeY = 80.0, verticalSpeed = 0.0, groundSpeed = 0.0 },
                fuel = 0.95,
                sensorOk = true,
            },
        })
        fcp.modem:transmit(10004, 10004, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 200,
            type = "MSG_OUTER_LOOP_STATUS",
            time = 1100,
            payload = {
                fsmState = "ACTIVE_TRACKING",
                trackingStatus = "TRACKING",
                posError = 0.5,
                velError = 0.1,
                saturated = false,
            },
        })
        bus:step(0.05)

        -- 8. AMM ingests Base+2 & Base+4, transitions queue to WP1, and downlinks MSG_MFD_STATE on Base+3 to GCS
        local amm_inbox = amm.modem:drain()
        assert_eq(#amm_inbox, 2)
        for _, m in ipairs(amm_inbox) do
            if m.channel == 10002 and m.payload.type == "MSG_FLIGHT_TELEMETRY" then
                arbiter:handle_flight_telemetry(m.payload, 1095)
            elseif m.channel == 10004 and m.payload.type == "MSG_OUTER_LOOP_STATUS" then
                arbiter:handle_outer_loop_status(m.payload, 1100)
            end
        end
        assert_eq(arbiter.fcpTrackingStatus, "TRACKING")

        arbiter:handle_mfd_state({
            payload = {
                fsmState = "CRUISE",
                flightMode = "AUTO_NAV",
                navigation = { currentPos = { x = 0, z = 0 } },
            },
        }, 1100)
        net:send_mfd_state({
            fsmState = "CRUISE",
            flightMode = "AUTO_NAV",
            navigation = { currentPos = { x = 0, z = 0 } },
        }, "FCP")
        bus:step(0.05)

        local gcs_mfd_in = gcs.modem:drain()
        assert_eq(#gcs_mfd_in, 1)
        assert_eq(gcs_mfd_in[1].payload.type, "MSG_MFD_STATE")
        assert_eq(gcs_mfd_in[1].payload.payload.fsmState, "CRUISE")

        -- Assert AMM transmitted WP1 command to FCP
        local wp1_pkts = bus:find_packets({ type = "MSG_OPERATOR_CMD", channel = 10000 })
        assert_true(#wp1_pkts >= 3)
        local latest_cmd = wp1_pkts[#wp1_pkts].payload.payload
        assert_eq(latest_cmd.command, "CRUISE")
        assert_eq(latest_cmd.params.targetWaypoint.x, 100)
        assert_eq(latest_cmd.params.targetWaypoint.z, 100)

        -- 9. FCP full runtime closed-loop LOITER and POI_HOLD C2 -> Base+1 / Base+3 verification
        fcp.modem:drain()
        vas.modem:drain()
        amm.modem:drain()

        local fcp_main = fcp:require("main")
        local fcp_net_mod = fcp:require("network_manager")
        local fcp_cfg = fcp_main.load_config()
        local fcp_ctx = fcp_main.create_context(fcp_cfg, function() return fcp.modem end)
        fcp_ctx.fsm.currentState = "ACTIVE_TRACKING"
        fcp_ctx.fsm.flightActive = true
        fcp_ctx.fsm.arm = true
        fcp_ctx.nav.pos = { x = 100.0, y = 150.0, z = 60.0 }

        -- Dispatch LOITER trajectory setpoint from AMM on Base+4 (10004)
        amm.modem:transmit(10004, 10004, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "AMM-03",
            type = "MSG_TRAJECTORY_SETPOINT",
            seq = 301,
            time = 2000,
            payload = {
                flightMode = "LOITER",
                arm = true,
                flightActive = true,
                constraintProfile = "STRICT_LEVEL",
                targetPos = { x = 100.0, y = 150.0, z = 100.0 },
                targetVel = { vx = 0.0, vy = 0.0, vz = 10.0 },
                feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
                targetHeading = 90.0,
                flapHint = 0.0,
            },
        })
        bus:step(0.05)

        for _, m in ipairs(fcp.modem:drain()) do
            fcp_net_mod.ingest_modem_event(fcp_ctx.net, "top", m.channel, m.replyChannel, m.payload, 1, 2000)
        end
        fcp_main.step_tick(fcp_ctx, 0.05, 2050)
        bus:step(0.05)

        assert_eq(fcp_ctx.fsm.currentState, "ACTIVE_TRACKING")
        local vas_loiter_in = vas.modem:drain()
        local loiter_att = nil
        for _, m in ipairs(vas_loiter_in) do
            if m.channel == 10001 and type(m.payload) == "table" and m.payload.type == "MSG_ATTITUDE_CMD" then
                loiter_att = m.payload.payload
            end
        end
        assert_not_nil(loiter_att, "FCP must transmit LOITER MSG_ATTITUDE_CMD on Base+1 (10001)")
        assert_eq(loiter_att.commandType, "QUATERNION_RATE")
        assert_eq(loiter_att.flightMode, "LOITER")
        assert_not_nil(loiter_att.targetQuaternion)
        assert_nil(loiter_att.flapTarget)

        -- Dispatch POI_HOLD trajectory setpoint from AMM on Base+4 (10004)
        amm.modem:transmit(10004, 10004, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "AMM-03",
            type = "MSG_TRAJECTORY_SETPOINT",
            seq = 302,
            time = 2100,
            payload = {
                flightMode = "POI_HOLD",
                arm = true,
                flightActive = true,
                constraintProfile = "STRICT_LEVEL",
                targetPos = { x = 100.0, y = 150.0, z = 100.0 },
                targetVel = { vx = 0.0, vy = 0.0, vz = 0.0 },
                feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
                targetHeading = 45.0,
                flapHint = 0.0,
            },
        })
        bus:step(0.05)

        for _, m in ipairs(fcp.modem:drain()) do
            fcp_net_mod.ingest_modem_event(fcp_ctx.net, "top", m.channel, m.replyChannel, m.payload, 1, 2100)
        end
        fcp_main.step_tick(fcp_ctx, 0.05, 2150)
        bus:step(0.05)

        assert_eq(fcp_ctx.fsm.currentState, "ACTIVE_TRACKING")
        local vas_poi_in = vas.modem:drain()
        local poi_att = nil
        for _, m in ipairs(vas_poi_in) do
            if m.channel == 10001 and type(m.payload) == "table" and m.payload.type == "MSG_ATTITUDE_CMD" then
                poi_att = m.payload.payload
            end
        end
        assert_not_nil(poi_att, "FCP must transmit POI_HOLD MSG_ATTITUDE_CMD on Base+1 (10001)")
        assert_eq(poi_att.commandType, "QUATERNION_RATE")
        assert_eq(poi_att.flightMode, "POI_HOLD")
        assert_not_nil(poi_att.targetQuaternion)
        assert_nil(poi_att.flapTarget)

        -- AMM downlinks POI_HOLD MFD state on Base+3 (10003) to GCS
        net:send_mfd_state({
            fsmState = "POI_HOLD",
            flightMode = "POI_HOLD",
            navigation = { currentPos = { x = 100, y = 150, z = 60 }, distanceToWp = 40.0 },
        }, "FCP")
        bus:step(0.05)

        local gcs_poi_in = gcs.modem:drain()
        local poi_mfd = nil
        for _, m in ipairs(gcs_poi_in) do
            if m.channel == 10003 and type(m.payload) == "table" and m.payload.type == "MSG_MFD_STATE" then
                poi_mfd = m.payload.payload
            end
        end
        assert_not_nil(poi_mfd, "AMM must downlink POI_HOLD MSG_MFD_STATE on Base+3 (10003) to GCS")
        assert_eq(poi_mfd.fsmState, "POI_HOLD")
        assert_eq(poi_mfd.navigation.distanceToWp, 40.0)
    end)
end)
