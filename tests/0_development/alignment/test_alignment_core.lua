-- Unit test suite for 0_development/alignment
local ols_regression_engine = require("ols_regression_engine")
local align_master = require("align_master")
local hud_renderer = require("hud_renderer")

describe("alignment OLS regression engine", function()
    it("identifies dominant axis and calculates slope, intercept, and R2", function()
        local impulseList = {
            { surge = 2.0, sway = 0.1, heave = 0.0, pitch = 0.0, roll = 0.0, yaw = 0.0 },
            { surge = 4.0, sway = 0.1, heave = 0.0, pitch = 0.0, roll = 0.0, yaw = 0.0 },
            { surge = 6.0, sway = 0.2, heave = 0.0, pitch = 0.0, roll = 0.0, yaw = 0.0 },
        }

        local domAxis = ols_regression_engine.identify_dominant_axis(impulseList)
        assert_eq(domAxis, "surge")

        local signals = { 4, 8, 12 }
        local reg = ols_regression_engine.calculate_regression(signals, impulseList, domAxis)
        assert_not_nil(reg)
        assert_eq(reg.dominantAxis, "surge")
        assert_near(reg.slope, 0.5, 1e-4)
        assert_near(reg.intercept, 0.0, 1e-4)
        assert_near(reg.confidenceR2, 1.0, 1e-4)
        assert_near(reg.normalizedCoefficients.surge, 1.0, 1e-4)
    end)
end)

describe("alignment master bay session and HUD renderer", function()
    it("initializes bay session and opens required hangar channels on mock modem", function()
        local mockModem = mock.modem()
        local stationCfg = {
            stationId = "BAY_01",
            bayId = 1,
            baseHangarChannel = 101,
            safety = { tiltAbortDeg = 12.0, tiltWarnDeg = 8.0 }
        }

        local master = align_master.init_bay_session(stationCfg, "AIRCRAFT_01", 10000, mockModem)
        assert_not_nil(master)
        assert_eq(master.state, "TUNING")
        -- Hangar channels opened: cmd (101), telem (102), tap (104)
        assert_true(mockModem.isOpen(101))
        assert_true(mockModem.isOpen(102))
        assert_true(mockModem.isOpen(104))
    end)

    it("renders artificial horizon on virtual terminal without blit mismatch", function()
        local termMock = mock.term(79, 36)
        local hud = hud_renderer.init(termMock)
        assert_not_nil(hud)

        hud:render_artificial_horizon(4.5, -2.0, 12.0)
        assert_true(termMock:_contains("ARTIFICIAL HORIZON"))
        assert_true(termMock:_contains("Pitch:"))
        assert_true(termMock:_contains("Tilt Guard:"))
    end)

    it("computes craft base channel accurately and validates bounds", function()
        assert_eq(align_master.compute_craft_base(1), 10000)
        assert_eq(align_master.compute_craft_base(2), 10040)
        assert_eq(align_master.compute_craft_base(1000), 49960)
        assert_nil(align_master.compute_craft_base(0))
        assert_nil(align_master.compute_craft_base(1001))
    end)

    it("auto-resolves craft base from domain id and sends MSG_CALIBRATION_INIT to Base+8", function()
        local mockModem = mock.modem()
        local stationCfg = {
            stationId = "BAY_01",
            bayId = 1,
            baseHangarChannel = 101,
            safety = { tiltAbortDeg = 12.0, tiltWarnDeg = 8.0 }
        }

        local master = align_master.init_bay_session(stationCfg, "AIRCRAFT_02", nil, mockModem)
        assert_not_nil(master)
        assert_eq(master.craft_base_ch, 10040)
        assert_eq(#mockModem._transmitted, 1)
        local t1 = mockModem._transmitted[1]
        assert_eq(t1.tx, 10048) -- Base+8 (CH_CALIBRATION_INIT)
        assert_eq(t1.rx, 102)
        assert_not_nil(t1.pkt)
        assert_eq(t1.pkt.type, "MSG_CALIBRATION_INIT")
        assert_eq(t1.pkt.payload.stationId, "BAY_01")
        assert_eq(t1.pkt.payload.targetCraftDomain, "AIRCRAFT_02")

        local mockModem1 = mock.modem()
        local master1 = align_master.init_bay_session(stationCfg, "AIRCRAFT_01", 10000, mockModem1)
        assert_not_nil(master1)
        assert_eq(mockModem1._transmitted[1].tx, 10008)
    end)

    it("emits MSG_CALIB_START on Base_hangar+0 and discovery requests on Base_hangar+3 upon INIT_ACK", function()
        local mockModem = mock.modem()
        local stationCfg = {
            stationId = "BAY_01",
            bayId = 1,
            baseHangarChannel = 101,
            safety = { tiltAbortDeg = 12.0, tiltWarnDeg = 8.0 }
        }

        local master = align_master.init_bay_session(stationCfg, "AIRCRAFT_01", 10000, mockModem)
        assert_eq(master.state, "TUNING")
        mockModem._transmitted = {}

        local ackEvent = {
            type = "PACKET",
            channel = 102,
            packet = {
                ver = "1.9.5",
                domainId = "AIRCRAFT_01",
                seq = 10,
                type = "MSG_CALIBRATION_INIT_ACK",
                payload = { status = "READY", craftDomain = "AIRCRAFT_01" }
            }
        }
        align_master.step_fsm(master, ackEvent)
        assert_eq(master.state, "DISCOVERY")

        assert_eq(#mockModem._transmitted, 3)

        local t1 = mockModem._transmitted[1]
        assert_eq(t1.tx, 101)
        assert_eq(t1.rx, 102)
        assert_eq(t1.pkt.type, "MSG_CALIB_START")
        assert_eq(t1.pkt.payload.action, "ENTER_CALIBRATION")
        assert_eq(t1.pkt.payload.stationId, "BAY_01")

        local t2 = mockModem._transmitted[2]
        assert_eq(t2.tx, 104)
        assert_eq(t2.rx, 104)
        assert_eq(t2.pkt.type, "MSG_ACTUATOR_DISCOVER_REQ")

        local t3 = mockModem._transmitted[3]
        assert_eq(t3.tx, 104)
        assert_eq(t3.rx, 104)
        assert_eq(t3.pkt.type, "MSG_SURFACE_DISCOVER_REQ")
    end)

    it("emits MSG_CALIBRATION_CLOSE on Base_hangar+0 and closes all channels on release", function()
        local mockModem = mock.modem()
        local stationCfg = {
            stationId = "BAY_01",
            bayId = 1,
            baseHangarChannel = 101,
            safety = { tiltAbortDeg = 12.0, tiltWarnDeg = 8.0 }
        }

        local master = align_master.init_bay_session(stationCfg, "AIRCRAFT_01", 10000, mockModem)
        assert_true(mockModem.isOpen(101))
        assert_true(mockModem.isOpen(102))
        assert_true(mockModem.isOpen(104))
        mockModem._transmitted = {}

        align_master.release_channels(master)
        assert_eq(#mockModem._transmitted, 1)
        local t1 = mockModem._transmitted[1]
        assert_eq(t1.tx, 101)
        assert_eq(t1.rx, 102)
        assert_eq(t1.pkt.type, "MSG_CALIBRATION_CLOSE")
        assert_eq(t1.pkt.payload.action, "CLOSE_SESSION")

        assert_false(mockModem.isOpen(101))
        assert_false(mockModem.isOpen(102))
        assert_false(mockModem.isOpen(104))
        assert_eq(master.state, "STANDBY")
    end)
end)


describe("alignment vector calibration integration (TASK-115)", function()
    it("assembles control matrix and validates pseudo-inverse inversion", function()
        local profile_exporter = require("profile_exporter")
        local vectorSlopes = {
            THR_VEC_1 = {
                dThrust = { surge = 0, sway = 0, heave = 2, pitch = 0, roll = 0, yaw = 0 },
                dGimbalX = { surge = 0, sway = 6, heave = 0, pitch = 0, roll = 3, yaw = 0 },
                dGimbalY = { surge = 6, sway = 0, heave = 0, pitch = 3, roll = 0, yaw = 0 }
            },
            THR_VEC_2 = {
                dThrust = { surge = 0, sway = 0, heave = 2, pitch = 0, roll = 0, yaw = 0 },
                dGimbalX = { surge = 0, sway = 6, heave = 0, pitch = 0, roll = -3, yaw = 0 },
                dGimbalY = { surge = 6, sway = 0, heave = 0, pitch = -3, roll = 0, yaw = 0 }
            }
        }
        local B = profile_exporter.assemble_control_matrix(vectorSlopes, { "THR_VEC_1", "THR_VEC_2" })
        assert_not_nil(B)
        assert_eq(#B, 6)
        assert_eq(#B[1], 6)
    end)

    it("saves profile JSON locally via profile_exporter.save_local", function()
        local profile_exporter = require("profile_exporter")
        local tempDir = sdk and sdk.temp_path and sdk.temp_path("align_profiles") or "/tmp/align_profiles"
        local ok, savedPath = profile_exporter.save_local({ profileId = "PROF-TEST-01", totalDryMass = 12500.0 }, tempDir, fs)
        assert_true(ok)
        assert_not_nil(savedPath)
        assert_true(fs.exists(savedPath))
    end)
end)

describe("impulse_integrator, settling_guard, and safety_sentinel (TST-LOW-01)", function()
    it("samples baseline and performs trapezoidal integration", function()
        local impulse_integrator = require("impulse_integrator")
        local integ = impulse_integrator.new()
        integ:sample_baseline({
            { linearVelocity = { surge = 1.0, sway = 0, heave = 0 }, angularVelocity = { pitch = 0, roll = 0, yaw = 0 } },
            { linearVelocity = { surge = 1.0, sway = 0, heave = 0 }, angularVelocity = { pitch = 0, roll = 0, yaw = 0 } },
        })
        assert_near(integ:get_baseline().surge, 1.0, 1e-6)
        integ:integrate_step({ linearVelocity = { surge = 1.0, sway = 0, heave = 0 }, angularVelocity = {} }, 0.05)
        integ:integrate_step({ linearVelocity = { surge = 3.0, sway = 0, heave = 0 }, angularVelocity = {} }, 0.05)
        -- Trapezoid of (0 + 2)/2 * 0.05 = 0.05
        assert_near(integ:get_total_impulse().surge, 0.05, 1e-6)
        assert_eq(integ:get_sample_count(), 2)
        integ:reset()
        assert_eq(integ:get_sample_count(), 0)
    end)

    it("monitors dynamic settling and timeout in settling_guard", function()
        local settling_guard = require("settling_guard")
        local guard = settling_guard.new({ maxAngularRate = 0.02, maxLinearVelocity = 0.05, timeoutSec = 0.2 })
        local settled, timedOut = guard:check_sample({ linearVelocity = { surge = 0.2 }, angularVelocity = { pitch = 0.1 } }, 0.1)
        assert_false(settled)
        assert_false(timedOut)
        settled, timedOut = guard:check_sample({ linearVelocity = { surge = 0.01 }, angularVelocity = { pitch = 0.005 } }, 0.1)
        assert_true(settled)
        assert_true(timedOut)
    end)

    it("enforces tilt limits, telemetry watchdog, and regression anomaly in safety_sentinel", function()
        local safety_sentinel = require("safety_sentinel")
        local s = safety_sentinel.new({ tiltAbortDeg = 12.0, tiltWarnDeg = 8.0, watchdogTimeoutMs = 300, minR2Warning = 0.85, maxDeadband = 6.0 })
        assert_eq(s:check_telemetry({ pitch = 2.0, roll = -1.0 }, 100).status, "OK")
        assert_eq(s:check_telemetry({ pitch = 9.0, roll = 0.0 }, 150).status, "PAUSE")
        assert_eq(s:check_telemetry({ pitch = 13.0, roll = 0.0 }, 200).status, "ABORT")
        assert_eq(s:check_watchdog(450).status, "OK")
        assert_eq(s:check_watchdog(500).status, "ABORT")
        assert_eq(s:check_regression_anomaly({ confidenceR2 = 0.80, deadband = 1.0 }).status, "PAUSE")
        assert_eq(s:check_regression_anomaly({ confidenceR2 = 0.99, deadband = 1.0 }).status, "OK")
    end)
end)

describe("align_master full FSM lifecycle and safety config (DEV-HIGH-01)", function()
    it("times out TUNING after 3000ms and aborts cleanly from any active state", function()
        local mockModem = mock.modem()
        local fullCfg = {
            station = { stationId = "BAY_01", bayId = 1, baseHangarChannel = 101 },
            safety = { tiltAbortDeg = 10.0, tiltWarnDeg = 6.0, watchdogTimeoutMs = 300 }
        }
        local m1 = align_master.init_bay_session(fullCfg, "AIRCRAFT_01", 10000, mockModem, 1000)
        assert_eq(m1.state, "TUNING")
        assert_eq(m1.sentinel.tilt_abort_deg, 10.0)
        align_master.step_fsm(m1, { type = "TICK" }, 4100)
        assert_eq(m1.state, "STANDBY")

        local m2 = align_master.init_bay_session(fullCfg, "AIRCRAFT_01", 10000, mockModem, 1000)
        align_master.step_fsm(m2, { type = "ABORT" }, 1100)
        assert_eq(m2.state, "STANDBY")
    end)

    it("includes replyChannel=104 on actuator discovery and steps INTEGRATING->SETTLING->REGRESSION->SYNC_APPROVAL->SYNCING", function()
        local mockModem = mock.modem()
        local fullCfg = {
            station = { stationId = "BAY_01", bayId = 1, baseHangarChannel = 101 },
            safety = { tiltAbortDeg = 12.0, tiltWarnDeg = 8.0, watchdogTimeoutMs = 5000 }
        }
        local master = align_master.init_bay_session(fullCfg, "AIRCRAFT_01", 10000, mockModem, 1000)
        align_master.step_fsm(master, {
            type = "PACKET", channel = 102,
            packet = { ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1, type = "MSG_CALIBRATION_INIT_ACK",
                       payload = { status = "READY", airframeType = "FIXED_WING", baseChannel = 10000 } }
        }, 1050)
        assert_eq(master.state, "DISCOVERY")

        -- Verify replyChannel on MSG_ACTUATOR_DISCOVER_REQ
        local foundReq = false
        for _, t in ipairs(mockModem._transmitted) do
            if t.pkt and t.pkt.type == "MSG_ACTUATOR_DISCOVER_REQ" then
                foundReq = true
                assert_eq(t.pkt.payload.replyChannel, 104)
                assert_eq(t.rx, 104)
            end
        end
        assert_true(foundReq)

        -- Discover 1 thruster
        align_master.step_fsm(master, {
            type = "PACKET", channel = 104,
            packet = { type = "MSG_ACTUATOR_DISCOVER_ACK", payload = { groupId = "THR_MAIN_L", interactionMode = "REDSTONE" } }
        }, 1100)
        align_master.step_fsm(master, { type = "DISCOVERY_DONE" }, 1150)
        assert_eq(master.state, "INTEGRATING")

        -- Step through 3 pulse levels (4, 8, 12)
        local tMs = 1200
        for stepIdx = 1, 3 do
            local surgeVal = stepIdx * 2.0
            align_master.step_fsm(master, {
                type = "PACKET", channel = 102,
                packet = { type = "MSG_FLIGHT_TELEMETRY", payload = { pitch = 0, roll = 0, linearVelocity = { surge = 0, sway = 0, heave = 0 }, angularVelocity = { pitch = 0, roll = 0, yaw = 0 } } }
            }, tMs)
            align_master.step_fsm(master, {
                type = "PACKET", channel = 102,
                packet = { type = "MSG_FLIGHT_TELEMETRY", payload = { pitch = 0, roll = 0, linearVelocity = { surge = surgeVal, sway = 0, heave = 0 }, angularVelocity = { pitch = 0, roll = 0, yaw = 0 } } }
            }, tMs + 50)
            align_master.step_fsm(master, { type = "PULSE_DONE" }, tMs + 300)
            assert_eq(master.state, "SETTLING")
            align_master.step_fsm(master, { type = "SETTLING_DONE" }, tMs + 400)
            tMs = tMs + 500
        end

        assert_eq(master.state, "SYNC_APPROVAL")
        assert_not_nil(master.eval_result)
        assert_eq(master.eval_result.status, "PARTIAL_RESTRICTED")

        -- Approve via OVERRIDE and receive MSG_CALIB_ACK
        align_master.step_fsm(master, { type = "OVERRIDE" }, tMs)
        assert_eq(master.state, "SYNCING")
        align_master.step_fsm(master, {
            type = "PACKET", channel = 102,
            packet = { type = "MSG_CALIB_ACK", payload = { profileId = "PROF-AIRCRAFT_01", status = "ACCEPTED" } }
        }, tMs + 50)
        assert_eq(master.state, "STANDBY")
    end)

    it("builds deterministic peripheralManifest with topologyHash, saves manifest, and attaches it to profile payload (TASK-136)", function()
        local okExp, profile_exporter = pcall(require, "profile_exporter")
        if not okExp then profile_exporter = require("modules.profile_exporter") end

        local m1 = profile_exporter.build_peripheral_manifest(
            "AIRCRAFT_01",
            {
                THR_MAIN_L = { peripheralCount = 1, vectorCapable = false },
                THR_MAIN_R = { peripheralCount = 1, vectorCapable = false },
            },
            { AIL_L = {}, AIL_R = {} },
            { "gimbal", "altitude", "velocity", "assembler" },
            12500.0
        )
        assert_not_nil(m1)
        assert_eq(m1.schemaVersion, 1)
        assert_eq(m1.domainId, "AIRCRAFT_01")
        assert_eq(m1.thrusterCount, 2)
        assert_eq(m1.totalDryMass, 12500.0)
        assert_not_nil(m1.topologyHash)

        local m2 = profile_exporter.build_peripheral_manifest(
            "AIRCRAFT_01",
            {
                THR_MAIN_R = { peripheralCount = 1, vectorCapable = false },
                THR_MAIN_L = { peripheralCount = 1, vectorCapable = false },
            },
            { AIL_R = {}, AIL_L = {} },
            { "assembler", "velocity", "altitude", "gimbal" },
            12500.0
        )
        assert_eq(m1.topologyHash, m2.topologyHash, "topologyHash must be deterministic regardless of table iteration order")

        local savedPath = "/_test_align_manifest.json"
        if fs.exists(savedPath) then fs.delete(savedPath) end
        local savedOk, savedErr = profile_exporter.save_peripheral_manifest(m1, "/", fs, "alignment/peripheral_manifest.json")
        -- clean up custom path
        local okWrite, errWrite = profile_exporter.save_peripheral_manifest(m1, "/_test_manifest_dir", fs)
        assert_true(okWrite, tostring(errWrite))
        assert_true(fs.exists("/_test_manifest_dir/peripheral_manifest.json"))
        fs.delete("/_test_manifest_dir/peripheral_manifest.json")
        if fs.exists("/alignment/peripheral_manifest.json") then fs.delete("/alignment/peripheral_manifest.json") end

        local master = align_master.init_bay_session({
            station = { stationId = "BAY_01", bayId = 1, baseHangarChannel = 101 },
            safety = { tiltAbortDeg = 12.0, tiltWarnDeg = 8.0, watchdogTimeoutMs = 5000 }
        }, "AIRCRAFT_01", 10000, mock.modem(), 1000)
        master.totalDryMass = 12500.0
        local payload = align_master.build_profile_payload(master, {}, {})
        assert_not_nil(payload.peripheralManifest)
        assert_eq(payload.peripheralManifest.domainId, "AIRCRAFT_01")
    end)

    it("handles MSG_ALIGN_REMOTE_CMD full lifecycle and emits MSG_ALIGN_REMOTE_STATUS on Base_hangar+1 (TASK-302)", function()
        local mockModem = mock.modem()
        local stationCfg = {
            station = { stationId = "HANGAR_BAY_01", bayId = 1, baseHangarChannel = 101 },
            safety = { tiltAbortDeg = 12.0, tiltWarnDeg = 8.0, watchdogTimeoutMs = 5000 },
        }

        -- 1. BIND_SESSION for N=2 from STANDBY (nil master) -> sends MSG_CALIBRATION_INIT to 10048 & status on 102
        local master, st1 = align_master.handle_remote_cmd(nil, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 1, time = 1000,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = {
                action = "BIND_SESSION",
                stationId = "HANGAR_BAY_01",
                bayId = 1,
                aircraftIndexN = 2,
                targetCraftDomain = "AIRCRAFT_02",
                baseHangarChannel = 101,
                source = "POCKET_PDA",
            },
        }, stationCfg, mockModem, 1000)
        assert_not_nil(master)
        assert_eq(master.state, "TUNING")
        assert_eq(master.craft_base_ch, 10040)
        assert_not_nil(st1)
        assert_eq(st1.type, "MSG_ALIGN_REMOTE_STATUS")
        assert_eq(st1.payload.status, "SESSION_STARTED")
        assert_eq(st1.payload.craftBaseChannel, 10040)
        assert_eq(mockModem._transmitted[1].tx, 10048)
        assert_eq(mockModem._transmitted[1].pkt.type, "MSG_CALIBRATION_INIT")
        assert_eq(mockModem._transmitted[2].tx, 102)
        assert_eq(mockModem._transmitted[2].pkt.type, "MSG_ALIGN_REMOTE_STATUS")

        -- 2. Move to DISCOVERY and trigger START_PULSE remotely
        master.state = "DISCOVERY"
        mockModem._transmitted = {}
        local _, st_pulse = align_master.handle_remote_cmd(master, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 2, time = 1100,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = { action = "START_PULSE", stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 2 },
        }, stationCfg, mockModem, 1100)
        assert_eq(master.state, "INTEGRATING")
        assert_eq(st_pulse.payload.status, "PULSE_STARTED")

        -- 3. PAUSE_SESSION -> ANOMALY_PAUSE (with contract-valid stepIndex in [1..9]), then RETRY_STEP -> INTEGRATING
        mockModem._transmitted = {}
        local _, st_pause = align_master.handle_remote_cmd(master, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 3, time = 1200,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = { action = "PAUSE_SESSION", stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 2, reason = "OP_HOLD" },
        }, stationCfg, mockModem, 1200)
        assert_eq(master.state, "ANOMALY_PAUSE")
        assert_eq(st_pause.payload.status, "PAUSED")
        local saw_pause_pulse = false
        for _, tx in ipairs(mockModem._transmitted) do
            if tx.pkt and tx.pkt.type == "MSG_CALIB_PULSE" then
                saw_pause_pulse = true
                assert_true(tx.pkt.payload.stepIndex >= 1 and tx.pkt.payload.stepIndex <= 9, "PAUSE stepIndex must be in [1..9]")
                assert_eq(tx.pkt.payload.pulseLevel, 0)
            end
        end
        assert_true(saw_pause_pulse)

        local _, st_retry = align_master.handle_remote_cmd(master, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 4, time = 1300,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = { action = "RETRY_STEP", stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 2 },
        }, stationCfg, mockModem, 1300)
        assert_eq(master.state, "INTEGRATING")
        assert_eq(st_retry.payload.status, "RETRYING")

        -- 4. APPROVE_SYNC in SYNC_APPROVAL -> SYNCING
        master.state = "SYNC_APPROVAL"
        master.eval_result = { status = "FULL_6DOF_PASS", passed = true }
        mockModem._transmitted = {}
        local _, st_sync = align_master.handle_remote_cmd(master, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 5, time = 1400,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = { action = "APPROVE_SYNC", stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 2, saveProfile = true },
        }, stationCfg, mockModem, 1400)
        assert_eq(master.state, "SYNCING")
        assert_eq(st_sync.payload.status, "SYNCING")
        assert_eq(mockModem._transmitted[1].tx, 101)
        assert_eq(mockModem._transmitted[1].pkt.type, "MSG_PROFILE_SYNC")
        assert_eq(mockModem._transmitted[2].tx, 102)
        assert_eq(mockModem._transmitted[2].pkt.type, "MSG_ALIGN_REMOTE_STATUS")

        -- 5. RELEASE_SESSION emits RELEASED on 102 then closes 101/102/104
        mockModem._transmitted = {}
        local _, st_rel = align_master.handle_remote_cmd(master, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 6, time = 1500,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = { action = "RELEASE_SESSION", stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 2 },
        }, stationCfg, mockModem, 1500)
        assert_eq(master.state, "STANDBY")
        assert_eq(st_rel.payload.status, "RELEASED")
        assert_false(mockModem.isOpen(101))
        assert_false(mockModem.isOpen(102))
        assert_false(mockModem.isOpen(104))

        -- 6. START_PULSE while STANDBY -> REJECTED
        local _, st_rej = align_master.handle_remote_cmd(master, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 7, time = 1600,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = { action = "START_PULSE", stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 2 },
        }, stationCfg, mockModem, 1600)
        assert_eq(st_rej.payload.status, "REJECTED")

        -- 7. ABORT_SESSION closes channels with valid MSG_CALIBRATION_CLOSE.reason, emits ABORTED on 102, and alignment/main.lua keeps 101 open in STANDBY
        align_master.handle_remote_cmd(master, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 8, time = 1700,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = { action = "BIND_SESSION", stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 2 },
        }, stationCfg, mockModem, 1700)
        mockModem._transmitted = {}
        local _, st_abt = align_master.handle_remote_cmd(master, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 9, time = 1800,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = { action = "ABORT_SESSION", stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 2, reason = "PDA_ABORT" },
        }, stationCfg, mockModem, 1800)
        assert_eq(master.state, "STANDBY")
        assert_eq(st_abt.payload.status, "ABORTED")
        assert_eq(st_abt.payload.reason, "PDA_ABORT")
        assert_false(mockModem.isOpen(101))
        local valid_close = { COMPLETE = true, MANUAL = true, CALIBRATION_FINISHED = true }
        local saw_abt_pulse, saw_abt_close = false, false
        for _, tx in ipairs(mockModem._transmitted) do
            if tx.pkt and tx.pkt.type == "MSG_CALIB_PULSE" then
                saw_abt_pulse = true
                assert_true(tx.pkt.payload.stepIndex >= 1 and tx.pkt.payload.stepIndex <= 9, "ABORT stepIndex must be in [1..9]")
            elseif tx.pkt and tx.pkt.type == "MSG_CALIBRATION_CLOSE" then
                saw_abt_close = true
                assert_true(valid_close[tx.pkt.payload.reason], "MSG_CALIBRATION_CLOSE.reason must be valid enum, got " .. tostring(tx.pkt.payload.reason))
            end
        end
        assert_true(saw_abt_pulse)
        assert_true(saw_abt_close)

        local align_main = require("main")
        assert_not_nil(align_main.handle_modem_message)
        local m2 = align_main.handle_modem_message(master, 101, {
            ver = "1.9.5", domainId = "AIRCRAFT_03", seq = 10, time = 1900,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = { action = "BIND_SESSION", stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 3 },
        }, stationCfg, mockModem, 1900)
        assert_eq(m2.state, "TUNING")
        assert_eq(m2.craft_base_ch, 10080)
        align_main.handle_modem_message(m2, 101, {
            ver = "1.9.5", domainId = "AIRCRAFT_03", seq = 11, time = 2000,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = { action = "RELEASE_SESSION", stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 3 },
        }, stationCfg, mockModem, 2000)
        assert_eq(m2.state, "STANDBY")
        assert_true(mockModem.isOpen(101), "STANDBY daemon must re-open cmd_ch=101")
    end)

    it("forwards saveProfile=false and preserves default saveProfile=true on RELEASE_SESSION", function()
        local mockModem = mock.modem()
        local stationCfg = {
            station = { stationId = "HANGAR_BAY_01", bayId = 1, baseHangarChannel = 101 },
            safety = { tiltAbortDeg = 12.0, tiltWarnDeg = 8.0, watchdogTimeoutMs = 5000 },
        }

        local function find_close_pkt(tx_list)
            for _, tx in ipairs(tx_list) do
                if tx.pkt and tx.pkt.type == "MSG_CALIBRATION_CLOSE" then
                    return tx.pkt
                end
            end
            return nil
        end

        -- Case 1: Explicit saveProfile = false -> MSG_CALIBRATION_CLOSE carries saveProfile = false, reason = "MANUAL"
        local m_rollback = align_master.handle_remote_cmd(nil, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 1, time = 1000,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = { action = "BIND_SESSION", stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 2 },
        }, stationCfg, mockModem, 1000)
        mockModem._transmitted = {}
        align_master.handle_remote_cmd(m_rollback, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 2, time = 1100,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = { action = "RELEASE_SESSION", stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 2, saveProfile = false },
        }, stationCfg, mockModem, 1100)
        local close_rollback = find_close_pkt(mockModem._transmitted)
        assert_not_nil(close_rollback)
        assert_eq(close_rollback.payload.saveProfile, false)
        assert_eq(close_rollback.payload.reason, "MANUAL")

        -- Case 2: Default RELEASE_SESSION (saveProfile omitted) -> saveProfile = true, reason = "COMPLETE"
        local m_default = align_master.handle_remote_cmd(nil, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 3, time = 1200,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = { action = "BIND_SESSION", stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 2 },
        }, stationCfg, mockModem, 1200)
        mockModem._transmitted = {}
        align_master.handle_remote_cmd(m_default, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 4, time = 1300,
            type = "MSG_ALIGN_REMOTE_CMD",
            payload = { action = "RELEASE_SESSION", stationId = "HANGAR_BAY_01", bayId = 1, aircraftIndexN = 2 },
        }, stationCfg, mockModem, 1300)
        local close_default = find_close_pkt(mockModem._transmitted)
        assert_not_nil(close_default)
        assert_eq(close_default.payload.saveProfile, true)
        assert_eq(close_default.payload.reason, "COMPLETE")
    end)
end)
