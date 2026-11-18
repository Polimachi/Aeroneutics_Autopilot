-- tests/e2e/test_e2e_hangar_alignment.lua
-- Scenario 4: Hangar Alignment Calibration Session, Direct Binding & OLS Profile Sync
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 4: Hangar Alignment Calibration Session", function()
    it("completes full 5-stage calibration session: binding, discover, pulse, OLS sync, and clean close", function()
        local bus = virtual_bus.create_bus({ clock = 1000.0 })

        local align = node_sandbox.create_node(bus, "ALIGN", "src/0_development/alignment")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
        local tca = node_sandbox.create_node(bus, "TCA", "src/1_control/tca")
        local asa = node_sandbox.create_node(bus, "ASA", "src/1_control/asa")

        -- 1. Setup VAS network state and channels
        local vas_net = vas:require("network_manager")
        local vas_state = vas_net.init({
            aircraftDomainId = "AIRCRAFT_01",
            baseChannel = 10000,
        })
        vas_state.baseChannel = 10000
        vas_state.aircraftDomainId = "AIRCRAFT_01"
        vas_state.channels.calibration = 10008
        vas_state.channels.emergency = 10009

        local state_machine = vas:require("state_machine")
        local vas_fsm = state_machine.init({}, true)
        vas_state.wirelessModem = vas.modem

        -- Alignment console is located in Bay 1 (Base_hangar = 101)
        -- Alignment listens on 101(CMD), 102(TELEM), 104(TAP)
        align.modem:open(101)
        align.modem:open(102)
        align.modem:open(104)

        -- VAS listens on Base+8 (10008) for calibration binding (Base+0 is NOT opened on VAS)
        vas.modem:open(10008)
        tca.modem:open(10010)
        asa.modem:open(10011)

        -- Negative Check 0a: C2 packet on Base+0 (10000) is NOT received by VAS
        align.modem:transmit(10000, 10000, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 0,
            type = "MSG_OPERATOR_CMD",
            time = 999,
            payload = { authority = "PILOT_PRIMARY", command = "HOLD", params = {} },
        })
        bus:step(0.05)
        assert_false(vas.modem:isOpen(10000))
        assert_eq(#vas.modem:drain(), 0)

        -- 2. Stage 1: Alignment sends MSG_CALIBRATION_INIT to craft Base+8 (10008)
        align.modem:transmit(10008, 102, {
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
            },
        })
        bus:step(0.05)

        -- VAS processes inbound message on 10008
        local vas_inbox = vas.modem:drain()
        assert_eq(#vas_inbox, 1)
        assert_eq(vas_inbox[1].channel, 10008)

        -- Negative Check 0b (Zero-Fallback): MSG_CALIBRATION_INIT delivered on legacy Base+0 (10000) is rejected
        local ok_legacy_calib, err_legacy_calib = vas_net.dispatch(vas_state, vas_fsm, nil, nil, 10000, 102, vas_inbox[1].payload)
        assert_false(ok_legacy_calib)
        assert_eq(err_legacy_calib, "WRONG_CHANNEL")
        assert_eq(vas_fsm.currentState, "IDLE_ARMED")

        -- Negative Check 1: Rogue domain spoofing (ROGUE_CRAFT) is rejected by envelope verification
        local rogue_init_pkt = {
            ver = "1.9.5",
            domainId = "ROGUE_CRAFT",
            seq = 1,
            type = "MSG_CALIBRATION_INIT",
            time = 1000,
            payload = {
                bayId = 1,
                stationId = "ALIGN_BAY_01",
                baseHangarChannel = 101,
                targetCraftDomain = "AIRCRAFT_01",
            },
        }
        local ok_rogue = vas_net.dispatch(vas_state, vas_fsm, nil, nil, 10008, 102, rogue_init_pkt)
        assert_false(ok_rogue)
        assert_eq(vas_fsm.currentState, "IDLE_ARMED")

        -- Negative Check 2: Hard E-STOP lock prevents entering CALIBRATION state
        local estop_fsm = state_machine.init({}, true)
        estop_fsm.currentState = "E_STOP"
        assert_false(estop_fsm:transition_to("CALIBRATION", "ILLEGAL_CALIBRATION_ATTEMPT"))
        assert_eq(estop_fsm.currentState, "E_STOP")

        -- Happy Path: Valid calibration init on Base+8 (10008)
        local ok_init = vas_net.dispatch(vas_state, vas_fsm, nil, nil, 10008, vas_inbox[1].replyChannel, vas_inbox[1].payload)
        assert_true(ok_init)
        assert_eq(vas_fsm.currentState, "CALIBRATION")

        -- VAS opens Bay channels: 101(CMD), 102(TELEM), 104(TAP)
        assert_true(vas.modem:isOpen(101))
        assert_true(vas.modem:isOpen(102))
        assert_true(vas.modem:isOpen(104))

        bus:step(0.05)

        -- Verify VAS sent MSG_CALIB_BAY_BIND to TCA (10010) and ASA (10011)
        local bind_pkts_tca = bus:find_packets({ type = "MSG_CALIB_BAY_BIND", channel = 10010 })
        local bind_pkts_asa = bus:find_packets({ type = "MSG_CALIB_BAY_BIND", channel = 10011 })
        assert_eq(#bind_pkts_tca, 1)
        assert_eq(#bind_pkts_asa, 1)
        assert_eq(bind_pkts_tca[1].payload.payload.action, "OPEN")
        assert_eq(bind_pkts_tca[1].payload.payload.bayCalibrationTap, 104)

        -- TCA and ASA open Bay channels (101, 104)
        tca.modem:open(101)
        tca.modem:open(104)
        asa.modem:open(101)
        asa.modem:open(104)

        -- Verify Alignment received MSG_CALIBRATION_INIT_ACK on 102
        local align_inbox = align.modem:drain()
        local ack_init = nil
        for _, m in ipairs(align_inbox) do
            if m.payload and m.payload.type == "MSG_CALIBRATION_INIT_ACK" then
                ack_init = m.payload
            end
        end
        assert_not_nil(ack_init)
        assert_eq(ack_init.payload.status, "READY")
        assert_eq(ack_init.payload.bayId, 1)

        -- 3. Stage 2: Actuator Discovery on 104 (CH_CALIBRATION_TAP)
        align.modem:transmit(104, 104, {
            ver = "1.9.5",
            domainId = "ALIGN_CONSOLE_01",
            seq = 2,
            type = "MSG_ACTUATOR_DISCOVER_REQ",
            time = 1010,
            payload = { targetGroup = "ALL" },
        })
        bus:step(0.05)

        local disc_reqs = bus:find_packets({ type = "MSG_ACTUATOR_DISCOVER_REQ", channel = 104 })
        assert_eq(#disc_reqs, 1)

        -- TCA replies on 104
        tca.modem:transmit(104, 104, {
            ver = "1.9.5",
            domainId = "TCA_NODE_01",
            seq = 10,
            type = "MSG_ACTUATOR_DISCOVER_ACK",
            time = 1015,
            payload = {
                groupId = "THR_MAIN_L",
                interactionMode = "REDSTONE",
                activeCount = 2,
                totalCount = 2,
                healthStatus = "REDSTONE_NOMINAL",
                isVectorCapable = false,
            },
        })
        bus:step(0.05)

        local disc_acks = bus:find_packets({ type = "MSG_ACTUATOR_DISCOVER_ACK", channel = 104 })
        assert_eq(#disc_acks, 1)

        -- 4. Stage 3: Pulse Testing on 101 (CH_CALIBRATION_CMD) & 20Hz Telemetry on 102
        align.modem:transmit(101, 102, {
            ver = "1.9.5",
            domainId = "ALIGN_CONSOLE_01",
            seq = 3,
            type = "MSG_CALIB_PULSE",
            time = 1020,
            payload = {
                targetThrusterId = "THR_MAIN_L",
                stepIndex = 1,
                pulseLevel = 8,
                pulseDurationMs = 300,
                safetyMaxTiltDeg = 12.0,
            },
        })
        bus:step(0.05)

        -- TCA applies pulse and VAS streams telemetry on 102
        vas.modem:drain() -- clear intermediate discovery / tap echoes
        vas.modem:transmit(102, 102, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 100,
            type = "MSG_FLIGHT_TELEMETRY",
            time = 1030,
            payload = {
                attitude = { pitch = 0.5, roll = 0.0, heading = 0.0 },
                angularRates = { pitchRate = 0.12, rollRate = 0.0, yawRate = 0.0 },
                dynamics = { altitudeY = 64.0, velocity = { vx = 0.0, vy = 0.0, vz = 0.8 } },
                fuel = 1.0,
                dynamicLoad = 0.0,
                controlState = "NORMAL",
                activeSource = "FCP",
                sensorOk = true,
                sensorHealth = { imu = true },
                actuatorHealth = { tap = true, asa = true, allOk = true },
            },
        })
        bus:step(0.05)

        local telem_pkts = bus:find_packets({ type = "MSG_FLIGHT_TELEMETRY", channel = 102 })
        assert_eq(#telem_pkts, 1)

        -- 5. Stage 4: OLS Regression & MSG_PROFILE_SYNC on 101
        local ols_engine = align:require("ols_regression_engine")
        local signals = { 4, 8, 12 }
        local impulses = {
            { surge = 4.2, sway = 0.0, heave = 0.0, pitch = 0.1, roll = 0.0, yaw = 0.0 },
            { surge = 8.5, sway = 0.0, heave = 0.0, pitch = 0.2, roll = 0.0, yaw = 0.0 },
            { surge = 12.8, sway = 0.0, heave = 0.0, pitch = 0.3, roll = 0.0, yaw = 0.0 },
        }
        local reg = ols_engine.calculate_regression(signals, impulses, "surge")
        assert_eq(reg.dominantAxis, "surge")
        assert_true(reg.slope > 1.0)
        assert_true(reg.confidenceR2 > 0.99)

        -- Alignment sends MSG_PROFILE_SYNC on 101
        vas.modem:drain()
        local synced_coeffs = {
            THR_MAIN_L = { surge = 1.0, sway = 0.0, heave = 0.0, deadband = reg.deadband, maxThrust = 15 }
        }
        align.modem:transmit(101, 102, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 4,
            type = "MSG_PROFILE_SYNC",
            time = 1050,
            payload = {
                profileId = "PROF_E2E_01",
                controllabilityStatus = "FULL_6DOF_PASS",
                thrusterCoefficients = synced_coeffs,
            },
        })
        bus:step(0.05)

        -- VAS processes MSG_PROFILE_SYNC
        local vas_sync_inbox = vas.modem:drain()
        assert_eq(#vas_sync_inbox, 1)
        local ok_sync = vas_net.dispatch(vas_state, vas_fsm, nil, nil, 101, vas_sync_inbox[1].replyChannel, vas_sync_inbox[1].payload)
        assert_true(ok_sync)
        assert_eq(vas_fsm.currentState, "IDLE_ARMED")

        bus:step(0.05)

        -- Verify VAS returned MSG_CALIB_ACK on 102
        local calib_acks = bus:find_packets({ type = "MSG_CALIB_ACK", channel = 102 })
        assert_eq(#calib_acks, 1)
        assert_eq(calib_acks[1].payload.payload.profileId, "PROF_E2E_01")
        assert_eq(calib_acks[1].payload.payload.status, "ACCEPTED")

        -- 6. Stage 5: Session Close on 101
        align.modem:transmit(101, 102, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 5,
            type = "MSG_CALIBRATION_CLOSE",
            time = 1060,
            payload = {
                bayId = 1,
                action = "CLOSE_SESSION",
                reason = "CALIBRATION_FINISHED",
            },
        })
        bus:step(0.05)

        local vas_close_inbox = vas.modem:drain()
        assert_eq(#vas_close_inbox, 1)
        local ok_close = vas_net.dispatch(vas_state, vas_fsm, nil, nil, 101, vas_close_inbox[1].replyChannel, vas_close_inbox[1].payload)
        assert_true(ok_close)

        -- Confirm VAS closed Bay channels 101, 104
        assert_false(vas.modem:isOpen(101))
        assert_false(vas.modem:isOpen(104))
    end)

    it("syncs peripheralManifest in MSG_PROFILE_SYNC across Alignment->VAS and detects >5% mass shift on re-assembly (TASK-136)", function()
        local bus = virtual_bus.create_bus({ clock = 2.0 })
        sdk.patch(os, "epoch", function() return math.floor(bus.time * 1000 + 0.5) end)
        local align = node_sandbox.create_node(bus, "ALIGN", "src/0_development/alignment")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
        local align_master = align:require("align_master")
        local vas_net = vas:require("network_manager")
        local vas_sp = vas:require("sensor_pipeline")
        local vas_fsm_mod = vas:require("state_machine")

        vas.modem:open(101)
        vas.modem:open(10008)
        local vas_fsm = vas_fsm_mod.init({}, true)
        local vas_state = vas_net.init({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        vas_state.wirelessModem = vas.modem
        local capturedManifest = nil
        vas_state.on_profile_sync = function(p)
            capturedManifest = p.peripheralManifest
            vas_fsm_mod.update_contraption_interlock(vas_fsm, "ASSEMBLED", false, "PROFILE_SYNC")
        end

        local master = align_master.init_bay_session({
            station = { stationId = "BAY_01", bayId = 1, baseHangarChannel = 101 },
            safety = { tiltAbortDeg = 12.0, tiltWarnDeg = 8.0, watchdogTimeoutMs = 5000 },
        }, "AIRCRAFT_01", 10000, align.modem, 2000)
        master.total_dry_mass = 12000.0
        local payload = align_master.build_profile_payload(master, { status = "FULL_6DOF_PASS" }, {})
        assert_not_nil(payload.peripheralManifest)

        align.modem:transmit(101, 102, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 1,
            type = "MSG_PROFILE_SYNC",
            time = 2010,
            payload = payload,
        })
        bus:step(0.05)

        for _, m in ipairs(vas.modem:drain()) do
            if m.channel == 101 then
                vas_net.dispatch(vas_state, vas_fsm, nil, nil, 101, m.replyChannel, m.payload)
            end
        end
        assert_not_nil(capturedManifest)
        assert_eq(capturedManifest.totalDryMass, 12000.0)

        local recheck = vas_sp.verify_and_rebind_topology({}, capturedManifest, {}, 13000.0)
        assert_true(recheck.recalibrationRequired)
    end)
end)
