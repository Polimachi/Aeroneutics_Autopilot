-- tests/e2e/test_e2e_advanced_vtol_flight.lua
-- Scenario 7: Hangar 2D Gimbal Pulse Calibration -> FCP/VAS/TCA ADVANCED_VTOL 6-DoF Closed-Loop Flight
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

local B_6x12 = {
    -- T1, gx1, gy1,  T2, gx2, gy2,  T3, gx3, gy3,  T4, gx4, gy4
    { 0,   0,   8,    0,   0,   8,    0,   0,   8,    0,   0,   8 }, -- surge
    { 0,   8,   0,    0,   8,   0,    0,   8,   0,    0,   8,   0 }, -- sway
    { 1,   0,   0,    1,   0,   0,    1,   0,   0,    1,   0,   0 }, -- heave
    {-1,   0,   0,   -1,   0,   0,    1,   0,   0,    1,   0,   0 }, -- pitch
    { 1,   0,   0,   -1,   0,   0,    1,   0,   0,   -1,   0,   0 }, -- roll
    { 0,   2,  -2,    0,   2,   2,    0,  -2,  -2,    0,  -2,   2 }  -- yaw
}

describe("Scenario 7: ADVANCED_VTOL Gimbal Calibration & 6-DoF Closed-Loop Flight", function()
    it("completes gimbal X/Y pulse calibration, B_dagger profile sync, 6-DoF vector flight, saturation anti-windup, and E_STOP nozzle neutralization", function()
        local bus = virtual_bus.create_bus({ clock = 1000.0 })

        local align = node_sandbox.create_node(bus, "ALIGN", "src/0_development/alignment")
        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
        local tca = node_sandbox.create_node(bus, "TCA_VEC_1", "src/1_control/tca")

        -- 1. Attach mock vector_thruster peripheral to TCA_VEC_1 sandbox
        local vec_hw = {
            _power = 0,
            _vectorX = 0.5, -- non-zero pre-boot state to verify cold-boot centering
            _vectorY = -0.5,
        }
        function vec_hw.setPower(p) vec_hw._power = tonumber(p) or 0 end
        function vec_hw.setVector(x, y)
            vec_hw._vectorX = tonumber(x) or 0.0
            vec_hw._vectorY = tonumber(y) or 0.0
        end
        function vec_hw.getVectorX() return vec_hw._vectorX end
        function vec_hw.getVectorY() return vec_hw._vectorY end
        function vec_hw.getPower() return vec_hw._power end

        local orig_periph = tca.env.peripheral
        tca.env.peripheral = {
            getNames = function() return { "top", "left" } end,
            isPresent = function(s) return s == "top" or s == "left" end,
            getType = function(s)
                if s == "left" then return "vector_thruster" end
                return orig_periph.getType(s)
            end,
            wrap = function(s)
                if s == "left" then return vec_hw end
                return orig_periph.wrap(s)
            end,
            find = orig_periph.find,
            call = orig_periph.call,
        }

        local tca_daemon_mod = tca:require("tca_daemon")
        local tca_cfg = {
            groupId = "THR_VEC_1",
            aircraftDomainId = "AIRCRAFT_01",
            aircraftIndexN = 1,
            baseChannel = 10000,
            channels = { thrustActuation = 10010 },
            watchdogTimeoutMs = 300,
            nominalActuatorCount = 1,
            interactionMode = "API",
            ports = { modemSide = "top", redstoneSide = "bottom", apiSides = { "left" } }
        }
        local tca_inst = tca_daemon_mod.init(tca_cfg, tca.modem)
        tca.modem:open(10010)

        -- Cold-boot neutral centering check
        assert_true(tca_inst.adapterState.isVectorCapable)
        assert_near(vec_hw._vectorX, 0.0, 1e-6)
        assert_near(vec_hw._vectorY, 0.0, 1e-6)

        -- 2. Initialize VAS with network_manager, state_machine, vehicle_policy, and actuator_adapter_tca
        local vas_net = vas:require("network_manager")
        local vas_fsm_mod = vas:require("state_machine")
        local vas_policy_mod = vas:require("vehicle_policy")
        local vas_tca_mod = vas:require("actuator_adapter_tca")

        local vas_state = vas_net.init({
            aircraftDomainId = "AIRCRAFT_01",
            baseChannel = 10000,
        })
        vas_state.wirelessModem = vas.modem
        local vas_fsm = vas_fsm_mod.init({}, true)
        local vas_policy = vas_policy_mod.init({ vehicleType = "ADVANCED_VTOL" })
        local vas_tca = vas_tca_mod.init({
            airframeType = "ADVANCED_VTOL",
            isVectorVtol = true,
            vectorGroupOrder = { "THR_VEC_1", "THR_VEC_2", "THR_VEC_3", "THR_VEC_4" }
        })

        vas.modem:open(10000)
        vas.modem:open(10001)
        vas.modem:open(10010)
        align.modem:open(101)
        align.modem:open(102)
        align.modem:open(104)

        -- 3. Stage 1: Hangar Calibration Init & Bay Bind (Bay 1: 101/102/104)
        align.modem:transmit(10000, 102, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 1,
            type = "MSG_CALIBRATION_INIT",
            time = 1000,
            payload = {
                bayId = 1,
                stationId = "ALIGN_BAY_01",
                baseHangarChannel = 101,
                targetCraftDomain = "AIRCRAFT_01",
            }
        })
        bus:step(0.05)

        local vas_init_in = vas.modem:drain()
        assert_eq(#vas_init_in, 1)
        assert_true(vas_net.dispatch(vas_state, vas_fsm, nil, vas_tca, 10000, vas_init_in[1].replyChannel, vas_init_in[1].payload))
        assert_eq(vas_fsm.currentState, "CALIBRATION")
        bus:step(0.05)

        -- TCA processes MSG_CALIB_BAY_BIND (OPEN) on 10010
        local tca_bind_in = tca.modem:drain()
        assert_eq(#tca_bind_in, 1)
        assert_eq(tca_bind_in[1].payload.type, "MSG_CALIB_BAY_BIND")
        assert_true(tca_inst:dispatch_modem_message(10010, 10010, tca_bind_in[1].payload))
        assert_true(tca.modem:isOpen(101))
        assert_true(tca.modem:isOpen(104))

        -- 4. Stage 2: Vector Actuator Discovery on 104
        local discovery_client = align:require("discovery_client")
        local disc_client = discovery_client.new("AIRCRAFT_01")

        align.modem:drain() -- clear init ack
        align.modem:transmit(104, 104, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 2,
            type = "MSG_ACTUATOR_DISCOVER_REQ",
            time = 1010,
            payload = { targetGroup = "ALL" }
        })
        bus:step(0.05)

        local tca_disc_in = tca.modem:drain()
        assert_eq(#tca_disc_in, 1)
        assert_true(tca_inst:dispatch_modem_message(104, 104, tca_disc_in[1].payload))
        bus:step(0.05)

        local align_disc_in = align.modem:drain()
        assert_eq(#align_disc_in, 1)
        assert_eq(align_disc_in[1].payload.type, "MSG_ACTUATOR_DISCOVER_ACK")
        assert_true(disc_client:process_ack(align_disc_in[1].payload))
        assert_true(disc_client:is_vector_capable("THR_VEC_1"))

        -- 5. Stage 3: Multi-Pulse Gimbal Calibration (THROTTLE, GIMBAL_X, GIMBAL_Y) on 101
        local multi_pulse_sequencer = align:require("multi_pulse_sequencer")
        local ols_engine = align:require("ols_regression_engine")
        local profile_exporter = align:require("profile_exporter")
        local controllability_checker = align:require("controllability_checker")

        local seq = multi_pulse_sequencer.new("AIRCRAFT_01")
        seq:start_vector_thruster("THR_VEC_1")

        -- Step 1: THROTTLE (level 5, gx=0, gy=0)
        local p_thr = seq:build_pulse_packet(10)
        align.modem:transmit(101, 102, p_thr)
        bus:step(0.05)
        local tca_p1 = tca.modem:drain()
        assert_eq(#tca_p1, 1)
        assert_true(tca_inst:dispatch_modem_message(101, 102, tca_p1[1].payload))
        assert_eq(vec_hw._power, 5)
        assert_near(vec_hw._vectorX, 0.0, 1e-6)
        assert_near(vec_hw._vectorY, 0.0, 1e-6)

        -- Advance to Step 4: GIMBAL_X (level 8, gx=-0.5, gy=0)
        for _ = 1, 3 do seq:next_step() end
        local p_gx = seq:build_pulse_packet(11)
        assert_eq(p_gx.payload.phase, "GIMBAL_X")
        align.modem:transmit(101, 102, p_gx)
        bus:step(0.05)
        local tca_p4 = tca.modem:drain()
        assert_eq(#tca_p4, 1)
        assert_true(tca_inst:dispatch_modem_message(101, 102, tca_p4[1].payload))
        assert_eq(vec_hw._power, 8)
        assert_near(vec_hw._vectorX, -0.5, 1e-6)
        assert_near(vec_hw._vectorY, 0.0, 1e-6)

        -- Advance to Step 7: GIMBAL_Y (level 8, gx=0, gy=-0.5)
        for _ = 1, 3 do seq:next_step() end
        local p_gy = seq:build_pulse_packet(12)
        assert_eq(p_gy.payload.phase, "GIMBAL_Y")
        align.modem:transmit(101, 102, p_gy)
        bus:step(0.05)
        local tca_p7 = tca.modem:drain()
        assert_eq(#tca_p7, 1)
        assert_true(tca_inst:dispatch_modem_message(101, 102, tca_p7[1].payload))
        assert_eq(vec_hw._power, 8)
        assert_near(vec_hw._vectorX, 0.0, 1e-6)
        assert_near(vec_hw._vectorY, -0.5, 1e-6)

        -- 6. Stage 4: Compute OLS Vector Slopes, Moore-Penrose B_dagger & Sync Profile
        local slopes = ols_engine.compute_vector_slopes({
            throttle = {
                signals = { 5, 10, 15 },
                impulses = {
                    { surge = 0, sway = 0, heave = 5, pitch = -5, roll = 5, yaw = 0 },
                    { surge = 0, sway = 0, heave = 10, pitch = -10, roll = 10, yaw = 0 },
                    { surge = 0, sway = 0, heave = 15, pitch = -15, roll = 15, yaw = 0 },
                }
            },
            gimbalX = {
                signals = { -0.5, 0.5, 1.0 },
                impulses = {
                    { surge = 0, sway = -4, heave = 8, pitch = 0, roll = 0, yaw = -1 },
                    { surge = 0, sway = 4, heave = 8, pitch = 0, roll = 0, yaw = 1 },
                    { surge = 0, sway = 8, heave = 8, pitch = 0, roll = 0, yaw = 2 },
                }
            },
            gimbalY = {
                signals = { -0.5, 0.5, 1.0 },
                impulses = {
                    { surge = -4, sway = 0, heave = 8, pitch = 0, roll = 0, yaw = 1 },
                    { surge = 4, sway = 0, heave = 8, pitch = 0, roll = 0, yaw = -1 },
                    { surge = 8, sway = 0, heave = 8, pitch = 0, roll = 0, yaw = -2 },
                }
            }
        })
        assert_near(slopes.dThrust.heave, 1.0, 1e-4)
        assert_near(slopes.dGimbalX.sway, 8.0, 1e-4)
        assert_near(slopes.dGimbalY.surge, 8.0, 1e-4)

        local B_dagger = profile_exporter.compute_pseudo_inverse(B_6x12)
        assert_not_nil(B_dagger)
        local eval = controllability_checker.evaluate({}, "ADVANCED_VTOL", {}, nil, B_dagger, B_6x12)
        assert_eq(eval.status, "FULL_6DOF_PASS")

        local sync_pkt = profile_exporter.build_sync_packet("AIRCRAFT_01", 20, {
            profileId = "PROF_ADV_VTOL_01",
            airframeType = "ADVANCED_VTOL",
            isVectorVtol = true,
            controllabilityStatus = eval.status,
            controlEffectivenessMatrix = B_6x12,
            pseudoInverseMatrix = B_dagger,
            vectorGroupOrder = { "THR_VEC_1", "THR_VEC_2", "THR_VEC_3", "THR_VEC_4" },
        })

        vas.modem:drain() -- clear intermediate pulse packets on 101
        align.modem:transmit(101, 102, sync_pkt)
        bus:step(0.05)

        local vas_sync_in = vas.modem:drain()
        assert_eq(#vas_sync_in, 1)
        assert_true(vas_net.dispatch(vas_state, vas_fsm, nil, vas_tca, 101, vas_sync_in[1].replyChannel, vas_sync_in[1].payload))
        assert_eq(vas_fsm.currentState, "IDLE_ARMED")
        assert_not_nil(vas_tca.pseudoInverseMatrix)
        bus:step(0.05)

        local calib_acks = bus:find_packets({ type = "MSG_CALIB_ACK", channel = 102 })
        assert_eq(#calib_acks, 1)
        assert_eq(calib_acks[1].payload.payload.profileId, "PROF_ADV_VTOL_01")

        -- Close calibration session
        align.modem:transmit(101, 102, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 21,
            type = "MSG_CALIBRATION_CLOSE",
            time = 1060,
            payload = { bayId = 1, action = "CLOSE_SESSION", reason = "COMPLETE" }
        })
        bus:step(0.05)
        local vas_close_in = vas.modem:drain()
        assert_eq(#vas_close_in, 1)
        assert_true(vas_net.dispatch(vas_state, vas_fsm, nil, vas_tca, 101, vas_close_in[1].replyChannel, vas_close_in[1].payload))
        assert_false(vas.modem:isOpen(101))
        bus:step(0.05)

        local tca_close_in = tca.modem:drain()
        local bay_close_count = 0
        for _, m in ipairs(tca_close_in) do
            if m.channel == 10010 and type(m.payload) == "table" and m.payload.type == "MSG_CALIB_BAY_BIND" then
                bay_close_count = bay_close_count + 1
                assert_true(tca_inst:dispatch_modem_message(m.channel, m.replyChannel, m.payload))
            else
                assert_false(tca_inst:dispatch_modem_message(m.channel, m.replyChannel, m.payload))
            end
        end
        assert_eq(bay_close_count, 1)
        assert_false(tca.modem:isOpen(101))
        assert_false(tca.modem:isOpen(104))

        -- 7. Stage 5: FCP -> VAS -> TCA Closed-Loop Flight (TAKEOFF -> CRUISE)
        local fcp_main = fcp:require("main")
        local fcp_cfg = fcp_main.load_config()
        fcp_cfg.system.airframeType = "ADVANCED_VTOL"
        fcp_cfg.system.domainId = "AIRCRAFT_01"

        local outer_loop_controller = fcp:require("outer_loop_controller")
        local fcp_guid = outer_loop_controller.init(fcp_cfg)

        -- 7a. TAKEOFF purely vertical setpoint has zero horizontal surge/sway
        local nav_takeoff = {
            pos = { x = 0.0, y = 70.0, z = 0.0 },
            vel = { x = 0.0, y = 1.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local tk_sp = {
            flightMode = "TAKEOFF",
            targetPos = { x = 0.0, y = 85.0, z = 0.0 },
            targetVel = { x = 0.0, y = 2.5, z = 0.0 },
            constraintProfile = "STRICT_LEVEL",
            translationBiasHint = { surge = 0.0, sway = 0.0 },
            arm = true,
            flightActive = true,
        }
        local tk_cmd = outer_loop_controller.compute(fcp_guid, nav_takeoff, tk_sp, {
            currentState = "ACTIVE_TRACKING", flightActive = true, arm = true
        }, 0.05)
        assert_not_nil(tk_cmd)
        assert_eq(tk_cmd.commandType, "QUATERNION_RATE")
        assert_eq(tk_cmd.translationBias.surge, 0.0)
        assert_eq(tk_cmd.translationBias.sway, 0.0)
        assert_true(tk_cmd.collectiveThrust > 0.0)

        -- 7b. CRUISE with offset waypoint computes 3-axis translationBias with STRICT_LEVEL attitude
        local nav_cruise = {
            pos = { x = 0.0, y = 80.0, z = 0.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local cr_sp = {
            flightMode = "CRUISE",
            targetPos = { x = 10.0, y = 85.0, z = -25.0 },
            targetVel = { x = 0.0, y = 0.0, z = 0.0 },
            constraintProfile = "STRICT_LEVEL",
            arm = true,
            flightActive = true,
        }
        local cr_cmd = outer_loop_controller.compute(fcp_guid, nav_cruise, cr_sp, {
            currentState = "ACTIVE_TRACKING", flightActive = true, arm = true
        }, 0.05)
        assert_not_nil(cr_cmd)
        assert_eq(cr_cmd.commandType, "QUATERNION_RATE")
        assert_true(cr_cmd.targetQuaternion.w > 0.99)
        assert_near(cr_cmd.targetQuaternion.x, 0.0, 1e-4)
        assert_near(cr_cmd.targetQuaternion.z, 0.0, 1e-4)
        assert_true(cr_cmd.translationBias.surge > 0.0)
        assert_true(cr_cmd.translationBias.sway > 0.0)

        -- FCP transmits MSG_ATTITUDE_CMD on Base+1 (10001)
        fcp.modem:transmit(10001, 10001, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 101,
            type = "MSG_ATTITUDE_CMD",
            time = 1150,
            payload = cr_cmd
        })
        bus:step(0.05)

        -- VAS receives MSG_ATTITUDE_CMD, verifies non-aero policy, and allocates 6-DoF vector thrust
        local vas_att_in = vas.modem:drain()
        assert_eq(#vas_att_in, 1)
        assert_true(vas_net.dispatch(vas_state, vas_fsm, nil, vas_tca, 10001, 10001, vas_att_in[1].payload))
        assert_eq(vas_fsm.currentState, "NORMAL")
        assert_eq(vas_policy_mod.resolve_flap_target(vas_policy, vas_state.latestCommand, 15.0, {}), 0.0)

        local wrench = {
            surge = 16.0,
            sway = 8.0,
            heave = 20.0,
            pitchTorque = 0.0,
            rollTorque = 0.0,
            yawTorque = 0.0
        }
        local vec_outputs, sat_status = vas_tca_mod.allocate(vas_tca, wrench)
        assert_not_nil(vec_outputs.THR_VEC_1)
        assert_eq(type(vec_outputs.THR_VEC_1), "table")
        assert_eq(vec_outputs.THR_VEC_1.thrust, 5)
        assert_near(vec_outputs.THR_VEC_1.gimbalX, 0.25, 1e-4)
        assert_near(vec_outputs.THR_VEC_1.gimbalY, 0.5, 1e-4)
        assert_false(sat_status.axisSaturatedPos.surge)

        -- VAS transmits MSG_THRUST_CMD on Base+10 (10010) and suppresses Base+11 (10011)
        vas_net.send_packet(vas_state, 10010, "MSG_THRUST_CMD", {
            watchdogSeq = 1,
            controlState = "NORMAL",
            outputs = vec_outputs
        })
        bus:step(0.05)

        -- Only the earlier calibration bay bind packets (OPEN/CLOSE) may exist on 10011; zero MSG_SURFACE_CMD or MSG_AERO_CMD
        assert_eq(#bus:find_packets({ type = "MSG_SURFACE_CMD", channel = 10011 }), 0)
        assert_eq(#bus:find_packets({ type = "MSG_AERO_CMD", channel = 10011 }), 0)

        -- TCA processes MSG_THRUST_CMD and reports MSG_ACTUATOR_STATUS
        local tca_cmd_in = tca.modem:drain()
        assert_eq(#tca_cmd_in, 1)
        assert_true(tca_inst:dispatch_modem_message(10010, 10010, tca_cmd_in[1].payload))
        assert_eq(vec_hw._power, 5)
        assert_near(vec_hw._vectorX, 0.25, 1e-6)
        assert_near(vec_hw._vectorY, 0.5, 1e-6)
        bus:step(0.05)

        local vas_stat_in = vas.modem:drain()
        assert_eq(#vas_stat_in, 1)
        assert_eq(vas_stat_in[1].payload.type, "MSG_ACTUATOR_STATUS")
        assert_near(vas_stat_in[1].payload.payload.appliedGimbal.x, 0.25, 1e-6)
        assert_near(vas_stat_in[1].payload.payload.appliedGimbal.y, 0.5, 1e-6)
        assert_false(vas_stat_in[1].payload.payload.gimbalSaturated)
        assert_true(vas_net.dispatch(vas_state, vas_fsm, nil, vas_tca, 10010, 10010, vas_stat_in[1].payload))
        assert_false(vas_tca.hasGimbalSaturation)

        -- 8. Stage 6: Gimbal Saturation Anti-Windup & E_STOP Nozzle Neutralization
        local sat_outputs, sat_flags = vas_tca_mod.allocate(vas_tca, {
            surge = 40.0, sway = 0.0, heave = 20.0, pitchTorque = 0.0, rollTorque = 0.0, yawTorque = 0.0
        })
        assert_eq(sat_outputs.THR_VEC_1.gimbalY, 1.0)
        assert_true(sat_flags.axisSaturatedPos.surge)

        -- Force an out-of-range gimbal command into TCA to verify TCA clamping + gimbalSaturated feedback to VAS
        sat_outputs.THR_VEC_1.gimbalY = 1.4
        vas_net.send_packet(vas_state, 10010, "MSG_THRUST_CMD", {
            watchdogSeq = 2,
            controlState = "NORMAL",
            outputs = sat_outputs
        })
        bus:step(0.05)

        local tca_sat_in = tca.modem:drain()
        assert_eq(#tca_sat_in, 1)
        assert_true(tca_inst:dispatch_modem_message(10010, 10010, tca_sat_in[1].payload))
        assert_near(vec_hw._vectorY, 1.0, 1e-6)
        assert_true(tca_inst.adapterState.isGimbalSaturated)
        bus:step(0.05)

        local vas_sat_in = vas.modem:drain()
        assert_eq(#vas_sat_in, 1)
        assert_true(vas_sat_in[1].payload.payload.gimbalSaturated)
        assert_true(vas_net.dispatch(vas_state, vas_fsm, nil, vas_tca, 10010, 10010, vas_sat_in[1].payload))
        assert_true(vas_tca.hasGimbalSaturation)

        -- Hard E_STOP command cuts power to 0 and resets nozzle gimbals to (0.0, 0.0)
        vas_net.send_packet(vas_state, 10010, "MSG_THRUST_CMD", {
            watchdogSeq = 3,
            controlState = "E_STOP",
            outputs = { THR_VEC_1 = { thrust = 0, gimbalX = 0.8, gimbalY = -0.8 } }
        })
        bus:step(0.05)

        local tca_estop_in = tca.modem:drain()
        assert_eq(#tca_estop_in, 1)
        assert_true(tca_inst:dispatch_modem_message(10010, 10010, tca_estop_in[1].payload))
        assert_eq(vec_hw._power, 0)
        assert_near(vec_hw._vectorX, 0.0, 1e-6)
        assert_near(vec_hw._vectorY, 0.0, 1e-6)
    end)
end)
