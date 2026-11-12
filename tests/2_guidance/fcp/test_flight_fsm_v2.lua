-- tests/2_guidance/fcp/test_flight_fsm_v2.lua
-- Unit test suite for FCP v2.0.0 6-state flight_fsm and fcp_config.json alignment

package.path = package.path .. ";/modules/?.lua;/?/init.lua"
local flight_fsm = require("flight_fsm")

describe("test_flight_fsm_v2: FCP v2.0.0 6-State FSM definition and transition validation", function()
    it("defines exactly the 6 valid v2.0.0 FSM states in flight_fsm.STATES", function()
        assert_not_nil(flight_fsm.STATES, "flight_fsm.STATES table must exist")
        local expected = {
            BOOT = true,
            IDLE_ARMED = true,
            ACTIVE_TRACKING = true,
            PASSIVE_TRACKING = true,
            AMM_TIMEOUT_HOLD = true,
            EMERGENCY_LAND = true,
        }
        local count = 0
        for k, v in pairs(flight_fsm.STATES) do
            assert_true(expected[k] == true, "Unexpected state in STATES: " .. tostring(k))
            assert_true(v == true, "State value must be boolean true")
            count = count + 1
        end
        assert_eq(count, 6, "Must define exactly 6 valid states")

        -- Explicitly verify deprecated legacy states are absent
        local legacy = { "BOOTSTRAP", "CRUISE", "TAKEOFF", "LOITER", "POI_HOLD", "APPROACH_LAND", "FAILSAFE_HOLD", "FAILSAFE_RTH" }
        for _, leg in ipairs(legacy) do
            assert_nil(flight_fsm.STATES[leg], "Legacy state must not exist in STATES: " .. leg)
        end
    end)

    it("verifies valid state transitions in is_transition_allowed", function()
        assert_not_nil(flight_fsm.is_transition_allowed, "is_transition_allowed must be exported")
        -- BOOT transitions
        assert_true(flight_fsm.is_transition_allowed("BOOT", "IDLE_ARMED"))

        -- IDLE_ARMED transitions
        assert_true(flight_fsm.is_transition_allowed("IDLE_ARMED", "ACTIVE_TRACKING"))

        -- ACTIVE_TRACKING transitions
        assert_true(flight_fsm.is_transition_allowed("ACTIVE_TRACKING", "IDLE_ARMED"))
        assert_true(flight_fsm.is_transition_allowed("ACTIVE_TRACKING", "PASSIVE_TRACKING"))
        assert_true(flight_fsm.is_transition_allowed("ACTIVE_TRACKING", "AMM_TIMEOUT_HOLD"))
        assert_true(flight_fsm.is_transition_allowed("ACTIVE_TRACKING", "EMERGENCY_LAND"))

        -- PASSIVE_TRACKING transitions
        assert_true(flight_fsm.is_transition_allowed("PASSIVE_TRACKING", "ACTIVE_TRACKING"))
        assert_true(flight_fsm.is_transition_allowed("PASSIVE_TRACKING", "IDLE_ARMED"))

        -- AMM_TIMEOUT_HOLD transitions
        assert_true(flight_fsm.is_transition_allowed("AMM_TIMEOUT_HOLD", "ACTIVE_TRACKING"))
        assert_true(flight_fsm.is_transition_allowed("AMM_TIMEOUT_HOLD", "EMERGENCY_LAND"))
        assert_true(flight_fsm.is_transition_allowed("AMM_TIMEOUT_HOLD", "IDLE_ARMED"))

        -- EMERGENCY_LAND transitions
        assert_true(flight_fsm.is_transition_allowed("EMERGENCY_LAND", "IDLE_ARMED"))
    end)

    it("rejects invalid state transitions in is_transition_allowed", function()
        -- Invalid transitions from BOOT
        assert_false(flight_fsm.is_transition_allowed("BOOT", "ACTIVE_TRACKING"))
        assert_false(flight_fsm.is_transition_allowed("BOOT", "EMERGENCY_LAND"))
        assert_false(flight_fsm.is_transition_allowed("BOOT", "PASSIVE_TRACKING"))
        assert_false(flight_fsm.is_transition_allowed("BOOT", "AMM_TIMEOUT_HOLD"))

        -- Invalid transitions from IDLE_ARMED
        assert_false(flight_fsm.is_transition_allowed("IDLE_ARMED", "PASSIVE_TRACKING"))
        assert_false(flight_fsm.is_transition_allowed("IDLE_ARMED", "AMM_TIMEOUT_HOLD"))
        assert_false(flight_fsm.is_transition_allowed("IDLE_ARMED", "EMERGENCY_LAND"))
        assert_false(flight_fsm.is_transition_allowed("IDLE_ARMED", "BOOT"))

        -- Invalid transitions from PASSIVE_TRACKING
        assert_false(flight_fsm.is_transition_allowed("PASSIVE_TRACKING", "AMM_TIMEOUT_HOLD"))
        assert_false(flight_fsm.is_transition_allowed("PASSIVE_TRACKING", "EMERGENCY_LAND"))
        assert_false(flight_fsm.is_transition_allowed("PASSIVE_TRACKING", "BOOT"))

        -- Invalid transitions from AMM_TIMEOUT_HOLD
        assert_false(flight_fsm.is_transition_allowed("AMM_TIMEOUT_HOLD", "PASSIVE_TRACKING"))
        assert_false(flight_fsm.is_transition_allowed("AMM_TIMEOUT_HOLD", "BOOT"))

        -- Invalid transitions from EMERGENCY_LAND
        assert_false(flight_fsm.is_transition_allowed("EMERGENCY_LAND", "ACTIVE_TRACKING"))
        assert_false(flight_fsm.is_transition_allowed("EMERGENCY_LAND", "PASSIVE_TRACKING"))
        assert_false(flight_fsm.is_transition_allowed("EMERGENCY_LAND", "AMM_TIMEOUT_HOLD"))
        assert_false(flight_fsm.is_transition_allowed("EMERGENCY_LAND", "BOOT"))

        -- Nil, self, and legacy checks
        assert_false(flight_fsm.is_transition_allowed(nil, "IDLE_ARMED"))
        assert_false(flight_fsm.is_transition_allowed("BOOT", nil))
        assert_false(flight_fsm.is_transition_allowed("BOOTSTRAP", "CRUISE"))
        assert_false(flight_fsm.is_transition_allowed("ACTIVE_TRACKING", "ACTIVE_TRACKING"))
    end)
end)

describe("test_flight_fsm_v2: FCP v2.0.0 flight_fsm.step lifecycle and state transitions", function()
    local function make_fsm()
        return flight_fsm.init({
            system = { airframeType = "VECTORED_VTOL" },
            safety = {
                ammSetpointTimeoutMs = 500,
                ammTimeoutHoldToEmgMs = 10000,
                bumplessRampSec = 2.0,
            },
        })
    end

    it("steps from BOOT to IDLE_ARMED when channels are ready", function()
        local state = make_fsm()
        assert_eq(state.currentState, "BOOT")

        local ctx = { channelsReady = true }
        local next_state, events = flight_fsm.step(state, ctx, 1000)
        assert_eq(next_state.currentState, "IDLE_ARMED")
        assert_true(events.resetIntegrators, "resetIntegrators must be true on BOOT -> IDLE_ARMED")
        assert_false(next_state.flightActive, "flightActive must be false in IDLE_ARMED")
    end)

    it("steps from IDLE_ARMED to ACTIVE_TRACKING on flightActive=true and arm=true", function()
        local state = make_fsm()
        state.currentState = "IDLE_ARMED"

        local ctx = {
            setpoint = {
                arm = true,
                flightActive = true,
                flightMode = "TAKEOFF",
                lastRxMs = 1000,
            },
            telemState = { activeSource = "FCP" },
        }
        local next_state, events = flight_fsm.step(state, ctx, 1000)
        assert_eq(next_state.currentState, "ACTIVE_TRACKING")
        assert_true(events.resetIntegrators, "resetIntegrators must be true on start tracking")
        assert_true(next_state.flightActive, "flightActive must be true in ACTIVE_TRACKING")
        assert_true(next_state.arm, "arm must be true")
    end)

    it("transitions to PASSIVE_TRACKING on MFD_ACRO preemption and recovers to ACTIVE_TRACKING with bumpless ramp", function()
        local state = make_fsm()
        state.currentState = "ACTIVE_TRACKING"
        state.flightActive = true
        state.arm = true
        state.prevFlightMode = "CRUISE"

        -- ACRO preemption
        local ctx_acro = {
            setpoint = { arm = true, flightActive = true, flightMode = "CRUISE", lastRxMs = 2000 },
            telemState = { activeSource = "MFD_ACRO" },
        }
        local s2, ev2 = flight_fsm.step(state, ctx_acro, 2000)
        assert_eq(s2.currentState, "PASSIVE_TRACKING")
        assert_true(ev2.freezeIntegrators, "Integrators should freeze on PASSIVE_TRACKING takeover")

        -- While in PASSIVE_TRACKING, stay passive
        local s3, ev3 = flight_fsm.step(s2, ctx_acro, 2100)
        assert_eq(s3.currentState, "PASSIVE_TRACKING")

        -- ACRO released back to FCP -> Bumpless ramp triggered
        local ctx_fcp = {
            setpoint = { arm = true, flightActive = true, flightMode = "CRUISE", lastRxMs = 2500 },
            telemState = { activeSource = "FCP" },
        }
        local s4, ev4 = flight_fsm.step(s3, ctx_fcp, 2500)
        assert_eq(s4.currentState, "ACTIVE_TRACKING")
        assert_true(ev4.triggerBumpless, "triggerBumpless must be true on recovery from PASSIVE_TRACKING")
        assert_true(ev4.resetIntegrators, "resetIntegrators must be true on recovery")
        assert_true(s4.bumplessTriggered, "state.bumplessTriggered must be true")
        assert_eq(s4.rampStartMs, 2500, "state.rampStartMs must record recovery timestamp")
    end)

    it("transitions to AMM_TIMEOUT_HOLD after 500ms setpoint silence, then recovers or escalates to EMERGENCY_LAND", function()
        local state = make_fsm()
        state.currentState = "ACTIVE_TRACKING"
        state.flightActive = true
        state.arm = true
        state.prevFlightMode = "CRUISE"

        -- Setpoint silence >= 500ms -> AMM_TIMEOUT_HOLD
        local ctx_silence = {
            setpoint = { arm = true, flightActive = true, flightMode = "CRUISE", lastRxMs = 1000 },
            telemState = { activeSource = "FCP" },
        }
        local s2, ev2 = flight_fsm.step(state, ctx_silence, 1500)
        assert_eq(s2.currentState, "AMM_TIMEOUT_HOLD")
        assert_true(ev2.resetIntegrators, "Integrators reset on entering AMM_TIMEOUT_HOLD")
        assert_eq(s2.timeoutHoldStartMs, 1500, "timeoutHoldStartMs must be set")

        -- Recovery branch: fresh setpoint received during hold
        local ctx_rec = {
            setpoint = { arm = true, flightActive = true, flightMode = "CRUISE", lastRxMs = 3000 },
            telemState = { activeSource = "FCP" },
        }
        local s_rec, ev_rec = flight_fsm.step(s2, ctx_rec, 3000)
        assert_eq(s_rec.currentState, "ACTIVE_TRACKING")
        assert_true(ev_rec.triggerBumpless, "Bumpless trigger on AMM recovery")
        assert_true(ev_rec.resetIntegrators, "Integrators reset on AMM recovery")
        assert_true(s_rec.bumplessTriggered)
        assert_eq(s_rec.rampStartMs, 3000)
        assert_nil(s_rec.timeoutHoldStartMs, "timeoutHoldStartMs must be cleared on recovery")

        -- Escalation branch: hold duration exceeds 10.0s (10000ms)
        local s_hold = make_fsm()
        s_hold.currentState = "AMM_TIMEOUT_HOLD"
        s_hold.flightActive = true
        s_hold.arm = true
        s_hold.timeoutHoldStartMs = 1500

        local ctx_escalate = {
            setpoint = { arm = true, flightActive = true, flightMode = "CRUISE", lastRxMs = 1000 },
            telemState = { activeSource = "FCP" },
        }
        local s_emg, ev_emg = flight_fsm.step(s_hold, ctx_escalate, 11501)
        assert_eq(s_emg.currentState, "EMERGENCY_LAND")
        assert_true(ev_emg.resetIntegrators, "resetIntegrators must be true on EMERGENCY_LAND entry")
    end)

    it("triggers bumpless ramp on discrete flightMode changes while in ACTIVE_TRACKING", function()
        local state = make_fsm()
        state.currentState = "ACTIVE_TRACKING"
        state.flightActive = true
        state.arm = true
        state.prevFlightMode = "CRUISE"

        -- Same mode -> no bumpless trigger
        local ctx_same = {
            setpoint = { arm = true, flightActive = true, flightMode = "CRUISE", lastRxMs = 5000 },
            telemState = { activeSource = "FCP" },
        }
        local s1, ev1 = flight_fsm.step(state, ctx_same, 5000)
        assert_eq(s1.currentState, "ACTIVE_TRACKING")
        assert_false(ev1.triggerBumpless, "No bumpless trigger for same flightMode")

        -- Discrete flightMode change: CRUISE -> APPROACH_LAND
        local ctx_change = {
            setpoint = { arm = true, flightActive = true, flightMode = "APPROACH_LAND", lastRxMs = 5050 },
            telemState = { activeSource = "FCP" },
        }
        local s2, ev2 = flight_fsm.step(s1, ctx_change, 5050)
        assert_eq(s2.currentState, "ACTIVE_TRACKING")
        assert_true(ev2.triggerBumpless, "Bumpless ramp triggered on discrete flightMode change")
        assert_true(ev2.resetIntegrators, "Integrators reset on discrete flightMode change")
        assert_true(s2.bumplessTriggered)
        assert_eq(s2.rampStartMs, 5050)
        assert_eq(s2.prevFlightMode, "APPROACH_LAND")
    end)

    it("transitions directly from ACTIVE_TRACKING to EMERGENCY_LAND on explicit setpoint", function()
        local state = make_fsm()
        state.currentState = "ACTIVE_TRACKING"
        state.flightActive = true
        state.arm = true

        local ctx = {
            setpoint = { arm = true, flightActive = true, flightMode = "EMERGENCY_LAND", lastRxMs = 6000 },
            telemState = { activeSource = "FCP" },
        }
        local s2, ev2 = flight_fsm.step(state, ctx, 6000)
        assert_eq(s2.currentState, "EMERGENCY_LAND")
        assert_true(ev2.resetIntegrators)
    end)

    it("handles Pre-Flight Ruling 3 E_STOP and MSG_EMERGENCY_ALERT cleanly into IDLE_ARMED", function()
        -- 1. activeSource == "EMERGENCY_DIRECT" from ACTIVE_TRACKING
        local s1 = make_fsm()
        s1.currentState = "ACTIVE_TRACKING"
        s1.flightActive = true
        s1.arm = true
        local ctx_estop1 = {
            setpoint = { arm = true, flightActive = true, flightMode = "CRUISE", lastRxMs = 7000 },
            telemState = { activeSource = "EMERGENCY_DIRECT", controlState = "E_STOP" },
        }
        local r1, ev1 = flight_fsm.step(s1, ctx_estop1, 7000)
        assert_eq(r1.currentState, "IDLE_ARMED")
        assert_true(ev1.resetIntegrators, "E-STOP must clear integrators")
        assert_false(ev1.triggerBumpless, "E-STOP must not trigger bumpless")
        assert_false(r1.flightActive, "flightActive must be false after E-STOP")

        -- 2. emergencyAlert == true from PASSIVE_TRACKING
        local s2 = make_fsm()
        s2.currentState = "PASSIVE_TRACKING"
        s2.flightActive = true
        s2.arm = true
        local ctx_estop2 = {
            emergencyAlert = true,
            telemState = { activeSource = "MFD_ACRO" },
        }
        local r2, ev2 = flight_fsm.step(s2, ctx_estop2, 7100)
        assert_eq(r2.currentState, "IDLE_ARMED")
        assert_true(ev2.resetIntegrators)
        assert_false(r2.flightActive)

        -- 3. controlState == "E_STOP" from AMM_TIMEOUT_HOLD
        local s3 = make_fsm()
        s3.currentState = "AMM_TIMEOUT_HOLD"
        s3.flightActive = true
        s3.arm = true
        local ctx_estop3 = {
            telemState = { controlState = "E_STOP" },
        }
        local r3, ev3 = flight_fsm.step(s3, ctx_estop3, 7200)
        assert_eq(r3.currentState, "IDLE_ARMED")
        assert_true(ev3.resetIntegrators)
        assert_false(r3.flightActive)

        -- 4. E_STOP from EMERGENCY_LAND
        local s4 = make_fsm()
        s4.currentState = "EMERGENCY_LAND"
        s4.flightActive = true
        s4.arm = true
        local ctx_estop4 = {
            emergencyAlert = true,
        }
        local r4, ev4 = flight_fsm.step(s4, ctx_estop4, 7300)
        assert_eq(r4.currentState, "IDLE_ARMED")
        assert_true(ev4.resetIntegrators)
        assert_false(r4.flightActive)
    end)

    it("transitions from EMERGENCY_LAND to IDLE_ARMED on touchdownComplete or disarm", function()
        local s1 = make_fsm()
        s1.currentState = "EMERGENCY_LAND"
        s1.flightActive = true
        s1.arm = true

        -- Touchdown complete
        local ctx_td = { touchdownComplete = true }
        local r1, ev1 = flight_fsm.step(s1, ctx_td, 8000)
        assert_eq(r1.currentState, "IDLE_ARMED")
        assert_true(ev1.resetIntegrators)
        assert_false(r1.flightActive)

        -- Disarm (arm = false)
        local s2 = make_fsm()
        s2.currentState = "EMERGENCY_LAND"
        s2.flightActive = true
        s2.arm = true

        local ctx_disarm = { setpoint = { arm = false, flightActive = false } }
        local r2, ev2 = flight_fsm.step(s2, ctx_disarm, 8100)
        assert_eq(r2.currentState, "IDLE_ARMED")
        assert_true(ev2.resetIntegrators)
        assert_false(r2.flightActive)
    end)
end)

describe("test_flight_fsm_v2: FCP v2.0.0 config/fcp_config.json schema validation", function()
    it("validates that config/fcp_config.json adheres strictly to v2.0.0 specification", function()
        assert_true(fs.exists("config/fcp_config.json"), "config/fcp_config.json must exist")
        local f = fs.open("config/fcp_config.json", "r")
        assert_not_nil(f)
        local raw = f.readAll()
        f.close()
        local cfg = textutils.unserializeJSON(raw)
        assert_not_nil(cfg, "config must parse as valid JSON")

        -- Top-level version
        assert_eq(cfg.version, "2.0.0", "Config version must be 2.0.0")

        -- System section
        assert_not_nil(cfg.system, "system section required")
        assert_eq(cfg.system.domainId, "AIRCRAFT_01")
        assert_eq(cfg.system.hardwareUuid, "FCP-NODE-04-4402")
        assert_eq(cfg.system.airframeType, "VECTORED_VTOL")
        assert_eq(cfg.system.loopFrequencyHz, 20)
        assert_eq(cfg.system.primaryModemSide, "top")
        assert_eq(cfg.system.debug, false, "system.debug must be false by default")

        -- Deprecated channel keys must be absent
        assert_not_nil(cfg.channels, "channels section required")
        assert_nil(cfg.channels.bootstrapChannel, "bootstrapChannel is deprecated")
        assert_nil(cfg.channels.mfdInstrumentChannel, "mfdInstrumentChannel is deprecated")
        assert_nil(cfg.channels.facilityBeaconChannel, "facilityBeaconChannel is deprecated")
        assert_nil(cfg.channels.atcCommChannel, "atcCommChannel is deprecated")
        assert_nil(cfg.channels.gpsPingChannel, "gpsPingChannel is deprecated")
        assert_nil(cfg.channels.gpsServiceChannel, "gpsServiceChannel is deprecated")
        assert_nil(cfg.system.infraModemSide, "infraModemSide is deprecated")

        -- Channels v2.0.0 schema
        assert_eq(cfg.channels.baseChannel, 10000)
        assert_eq(cfg.channels.bandwidth, 40)
        assert_eq(cfg.channels.trajectoryOffset, 4)
        assert_eq(cfg.channels.telemetryOffset, 2)
        assert_eq(cfg.channels.guidanceOffset, 1)

        -- Propagation section
        assert_not_nil(cfg.propagation, "propagation section required")
        assert_eq(cfg.propagation.maxDtSec, 0.1)
        assert_eq(cfg.propagation.posMergeMaxStepM, 2.0)
        assert_eq(cfg.propagation.navStaleTimeoutMs, 500)

        -- SE(3) section
        assert_not_nil(cfg.se3, "se3 section required")
        assert_eq(cfg.se3.gravityMps2, 11.0)
        assert_eq(cfg.se3.kp.x, 1.6)
        assert_eq(cfg.se3.kp.y, 2.2)
        assert_eq(cfg.se3.kp.z, 1.6)
        assert_eq(cfg.se3.kd.x, 1.4)
        assert_eq(cfg.se3.kd.y, 1.8)
        assert_eq(cfg.se3.kd.z, 1.4)
        assert_eq(cfg.se3.ki.x, 0.08)
        assert_eq(cfg.se3.ki.y, 0.12)
        assert_eq(cfg.se3.ki.z, 0.08)
        assert_eq(cfg.se3.hoverThrustRatio, 0.635)
        assert_eq(cfg.se3.tiltAssistedMaxPitchDeg, 10.0)
        assert_eq(cfg.se3.tiltAssistedThresholdSpeedMps, 15.0)
        assert_eq(cfg.se3.tiltSlewRateDegPerSec, 15.0)
        assert_eq(cfg.se3.gimbalSlewRate, 2.0)
        assert_eq(cfg.se3.multirotorMaxTiltDeg, 25.0)

        -- Deprecated sections must be absent
        assert_nil(cfg.navigation, "navigation section is deprecated (migrated to AMM)")
        assert_nil(cfg.docking, "docking section is deprecated (migrated to AMM)")
        assert_nil(cfg.guidance, "guidance section is deprecated (migrated to AMM/SE(3))")

        -- Safety section
        assert_not_nil(cfg.safety, "safety section required")
        assert_eq(cfg.safety.ammSetpointTimeoutMs, 500)
        assert_eq(cfg.safety.ammTimeoutHoldToEmgMs, 10000)
        assert_eq(cfg.safety.rebindAckTimeoutMs, 500)
        assert_eq(cfg.safety.bumplessRampSec, 2.0)
        assert_eq(cfg.safety.emergencyDescentRateMps, -2.0)
    end)
end)
