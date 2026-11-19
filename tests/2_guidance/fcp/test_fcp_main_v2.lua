-- tests/2_guidance/fcp/test_fcp_main_v2.lua
-- Unit test suite for FCP v2.0.0 main.lua headless runtime and ui_renderer 51x19 HUD
-- CC:Tweaked Lua 5.2 / Cobalt VM compliant

package.path = package.path .. ";/modules/?.lua;/?/init.lua"
local fcp_main = require("main")
local ui_renderer = require("ui_renderer")

local function create_mock_modem()
    local modem = {
        openChannels = {},
        transmitted = {},
    }
    function modem.open(ch)
        modem.openChannels[ch] = true
    end
    function modem.close(ch)
        modem.openChannels[ch] = nil
    end
    function modem.isOpen(ch)
        return modem.openChannels[ch] == true
    end
    function modem.transmit(ch, replyCh, payload)
        table.insert(modem.transmitted, {
            channel = ch,
            replyChannel = replyCh,
            payload = payload,
        })
    end
    return modem
end

local function create_mock_term()
    local win = {
        cursorX = 1,
        cursorY = 1,
        rows = {},
        fg = {},
        bg = {},
        cleared = false,
    }
    function win.setCursorPos(x, y)
        win.cursorX = x
        win.cursorY = y
    end
    function win.blit(text, fg, bg)
        win.rows[win.cursorY] = text
        win.fg[win.cursorY] = fg
        win.bg[win.cursorY] = bg
    end
    function win.clear()
        win.cleared = true
    end
    return win
end

describe("test_fcp_main_v2: configuration loader and defaults", function()
    it("loads config/fcp_config.json with headless debug: false default", function()
        local cfg = fcp_main.load_config("config/fcp_config.json")
        assert_not_nil(cfg, "Config must load successfully")
        assert_not_nil(cfg.system, "System section must exist")
        assert_eq(cfg.system.debug, false, "Default debug must be false for headless runtime")
        assert_eq(cfg.system.airframeType, "VECTORED_VTOL", "Default airframeType must be VECTORED_VTOL")
        assert_not_nil(cfg.channels, "Channels section must exist")
        assert_eq(cfg.channels.baseChannel, 10000, "baseChannel must be 10000")
        assert_eq(cfg.channels.trajectoryOffset, 4, "trajectoryOffset must be 4")
        assert_eq(cfg.channels.telemetryOffset, 2, "telemetryOffset must be 2")
        assert_eq(cfg.channels.guidanceOffset, 1, "guidanceOffset must be 1")
        assert_eq(cfg.channels.emergencyOffset, 9, "emergencyOffset must be 9")
        assert_eq(cfg.version, "2.1.0", "Default config version must be 2.1.0")
        assert_nil(cfg._versionWarning, "Canonical version 2.1.0 must not emit _versionWarning")
    end)

    it("soft-validates cfg.version in load_config without aborting boot on mismatch", function()
        local tmpOk = sdk.temp_path("fcp_ver_ok.json")
        local tmpBad = sdk.temp_path("fcp_ver_bad.json")
        local tmpNil = sdk.temp_path("fcp_ver_nil.json")

        local function write_json(path, tbl)
            local h = fs.open(path, "w")
            h.write(textutils.serializeJSON(tbl))
            h.close()
        end

        write_json(tmpOk, { version = "2.1.0", system = { loopFrequencyHz = 20 } })
        write_json(tmpBad, { version = "1.9.0", system = { loopFrequencyHz = 10 } })
        write_json(tmpNil, { system = { debug = false } })

        local cOk = fcp_main.load_config(tmpOk)
        assert_eq(cOk.version, "2.1.0")
        assert_nil(cOk._versionWarning)

        local cBad = fcp_main.load_config(tmpBad)
        assert_not_nil(cBad._versionWarning, "Mismatched version must record soft _versionWarning")
        assert_true(string.find(cBad._versionWarning, "CONFIG_VERSION_MISMATCH", 1, true) ~= nil)
        assert_eq(cBad.system.loopFrequencyHz, 10)

        local cNil = fcp_main.load_config(tmpNil)
        assert_eq(cNil.version, "2.1.0")
        assert_nil(cNil._versionWarning)

        if fs.exists(tmpOk) then fs.delete(tmpOk) end
        if fs.exists(tmpBad) then fs.delete(tmpBad) end
        if fs.exists(tmpNil) then fs.delete(tmpNil) end
    end)
end)

describe("test_fcp_main_v2: context creation and channel binding", function()
    it("initializes runtime context and opens 4 core channels on primary modem", function()
        local mock_modem = create_mock_modem()
        local cfg = fcp_main.load_config("config/fcp_config.json")
        local ctx = fcp_main.create_context(cfg, function() return mock_modem end)

        assert_not_nil(ctx, "Context must be created")
        assert_not_nil(ctx.net, "Network manager must be initialized")
        assert_not_nil(ctx.fsm, "Flight FSM must be initialized")
        assert_not_nil(ctx.ctrl, "SE(3) controller must be initialized")
        assert_not_nil(ctx.nav, "State propagator must be initialized")
        assert_true(ctx.running, "Context running flag must be true")
        assert_eq(ctx.tick, 0, "Initial tick must be 0")

        -- Verify 4 channels opened: 10004, 10002, 10001, 10009
        assert_true(mock_modem.isOpen(10004), "Trajectory channel 10004 must be open")
        assert_true(mock_modem.isOpen(10002), "Telemetry channel 10002 must be open")
        assert_true(mock_modem.isOpen(10001), "Guidance channel 10001 must be open")
        assert_true(mock_modem.isOpen(10009), "Emergency channel 10009 must be open")
    end)
end)

describe("test_fcp_main_v2: step_tick control loop and packet dispatch", function()
    it("executes ACTIVE_TRACKING: transmits QUATERNION_RATE attitude command on Base+1 and status on Base+4", function()
        local mock_modem = create_mock_modem()
        local cfg = fcp_main.load_config("config/fcp_config.json")
        local ctx = fcp_main.create_context(cfg, function() return mock_modem end)
        ctx.fsm.currentState = "IDLE_ARMED"

        -- Ingest VAS telemetry on Base+2 (10002)
        local telem_pkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "VAS-01",
            seq = 100,
            type = "MSG_FLIGHT_TELEMETRY",
            payload = {
                dynamics = { velocity = { vx = 5.0, vy = 0.0, vz = 0.0 } },
                attitude = { pitch = 0, roll = 0, yaw = 0 },
                angularRates = { pitchRate = 0, rollRate = 0, yawRate = 0 },
                activeSource = "FCP",
                controlState = "NORMAL",
                actuatorHealth = { tca = true, asa = true, tap = true, allOk = true },
                sensorOk = true,
            },
        }
        ctx.net.inbound.telemetry = telem_pkt

        -- Ingest AMM setpoint on Base+4 (10004)
        local sp_pkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "AMM-03",
            seq = 200,
            type = "MSG_TRAJECTORY_SETPOINT",
            payload = {
                arm = true,
                flightActive = true,
                flightMode = "CRUISE",
                targetPos = { x = 100, y = 64, z = 0 },
                targetVel = { vx = 15.0, vy = 0.0, vz = 0.0 },
                feedforwardAccel = { ax = 0, ay = 0, az = 0 },
                targetHeading = 0.0,
                constraintProfile = "STRICT_LEVEL",
                currentPos = { x = 0, y = 64, z = 0 },
                navValid = true,
                posEpoch = 1000,
                lastRxMs = 1000,
            },
        }
        ctx.net.inbound.trajectory = sp_pkt

        -- Step tick
        fcp_main.step_tick(ctx, 0.05, 1000)

        assert_eq(ctx.fsm.currentState, "ACTIVE_TRACKING", "FSM should transition to ACTIVE_TRACKING")
        assert_eq(ctx.tick, 1, "Tick counter should increment to 1")

        -- Check transmitted packets
        local att_pkt = nil
        local status_pkt = nil
        for _, tx in ipairs(mock_modem.transmitted) do
            if tx.channel == 10001 and tx.payload.type == "MSG_ATTITUDE_CMD" then
                att_pkt = tx.payload
            elseif tx.channel == 10004 and tx.payload.type == "MSG_OUTER_LOOP_STATUS" then
                status_pkt = tx.payload
            end
        end

        assert_not_nil(att_pkt, "Must transmit MSG_ATTITUDE_CMD on Base+1 (10001)")
        assert_eq(att_pkt.payload.source, "FCP")
        assert_true(att_pkt.payload.arm)
        assert_true(att_pkt.payload.flightActive)
        assert_eq(att_pkt.payload.commandType, "QUATERNION_RATE")
        assert_not_nil(att_pkt.payload.targetQuaternion)
        assert_not_nil(att_pkt.payload.targetAngularRates)
        assert_false(att_pkt.payload.acroActive)

        assert_not_nil(status_pkt, "Must transmit MSG_OUTER_LOOP_STATUS on Base+4 (10004)")
        assert_eq(status_pkt.payload.fsmState, "ACTIVE_TRACKING")
        assert_true(status_pkt.payload.saturated, "Large pos error must wire live saturated == true")
        assert_not_nil(status_pkt.payload.posError)
        assert_not_nil(status_pkt.payload.velError)
        assert_not_nil(status_pkt.payload.commandedCollectiveThrust)
    end)

    it("silences Base+1 during PASSIVE_TRACKING (MFD_ACRO) while still transmitting status on Base+4", function()
        local mock_modem = create_mock_modem()
        local cfg = fcp_main.load_config("config/fcp_config.json")
        local ctx = fcp_main.create_context(cfg, function() return mock_modem end)

        -- Put into ACTIVE_TRACKING first
        ctx.fsm.currentState = "ACTIVE_TRACKING"
        ctx.fsm.flightActive = true
        ctx.fsm.arm = true

        -- Feed MFD_ACRO telemetry
        ctx.net.inbound.telemetry = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "VAS-01",
            seq = 101,
            type = "MSG_FLIGHT_TELEMETRY",
            payload = {
                dynamics = { velocity = { vx = 0, vy = 0, vz = 0 } },
                attitude = { pitch = 0, roll = 0, yaw = 0 },
                angularRates = { pitchRate = 0, rollRate = 0, yawRate = 0 },
                activeSource = "MFD_ACRO",
                controlState = "ACRO",
                actuatorHealth = { tca = true, asa = true, tap = true, allOk = true },
            },
        }
        ctx.net.inbound.trajectory = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "AMM-03",
            seq = 201,
            type = "MSG_TRAJECTORY_SETPOINT",
            payload = { arm = true, flightActive = true, flightMode = "CRUISE", lastRxMs = 2000 },
        }

        mock_modem.transmitted = {}
        fcp_main.step_tick(ctx, 0.05, 2000)

        assert_eq(ctx.fsm.currentState, "PASSIVE_TRACKING", "FSM should transition to PASSIVE_TRACKING")

        -- Base+1 MUST BE SILENT!
        local att_count = 0
        local status_pkt = nil
        for _, tx in ipairs(mock_modem.transmitted) do
            if tx.channel == 10001 then
                att_count = att_count + 1
            elseif tx.channel == 10004 and tx.payload.type == "MSG_OUTER_LOOP_STATUS" then
                status_pkt = tx.payload
            end
        end

        assert_eq(att_count, 0, "Base+1 must be completely silent during PASSIVE_TRACKING")
        assert_not_nil(status_pkt, "Must still transmit MSG_OUTER_LOOP_STATUS on Base+4")
        assert_eq(status_pkt.payload.fsmState, "PASSIVE_TRACKING")
    end)

    it("verifies bumpless transition linear rampAlpha ramping from 0.0 to 1.0 over bumplessRampSec", function()
        local mock_modem = create_mock_modem()
        local cfg = fcp_main.load_config("config/fcp_config.json")
        local ctx = fcp_main.create_context(cfg, function() return mock_modem end)
        ctx.fsm.currentState = "ACTIVE_TRACKING"
        ctx.fsm.flightActive = true
        ctx.fsm.arm = true
        ctx.fsm.prevFlightMode = "CRUISE"

        -- Ingest setpoint with mode change -> triggers bumpless
        ctx.net.inbound.telemetry = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", senderId = "VAS-01", seq = 10, type = "MSG_FLIGHT_TELEMETRY",
            payload = { dynamics = { velocity = { vx = 0, vy = 0, vz = 0 } }, attitude = { pitch = 0, roll = 0, yaw = 0 }, activeSource = "FCP" },
        }
        ctx.net.inbound.trajectory = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", senderId = "AMM-03", seq = 20, type = "MSG_TRAJECTORY_SETPOINT",
            payload = { arm = true, flightActive = true, flightMode = "APPROACH_LAND", lastRxMs = 5000, currentPos = { x = 0, y = 64, z = 0 }, posEpoch = 5000 },
        }

        fcp_main.step_tick(ctx, 0.05, 5000)
        assert_not_nil(ctx.rampStartMs, "rampStartMs must be set when bumpless is triggered")
        assert_eq(ctx.rampAlpha, 0.0, "rampAlpha must start at 0.0 at trigger time")

        -- Advance 1.0s (50% of 2.0s ramp)
        fcp_main.step_tick(ctx, 0.05, 6000)
        assert_true(math.abs(ctx.rampAlpha - 0.5) < 0.05, "rampAlpha should be ~0.5 at halfway mark, got: " .. tostring(ctx.rampAlpha))

        -- Advance 2.0s (100% of ramp)
        fcp_main.step_tick(ctx, 0.05, 7000)
        assert_eq(ctx.rampAlpha, 1.0, "rampAlpha should reach 1.0 after bumplessRampSec")
    end)

    it("transitions to EMERGENCY_HOLD on Base+9 MSG_EMERGENCY_ALERT and ignores Base+1 MSG_EMERGENCY_ALERT", function()
        local network_manager = require("network_manager")
        local mock_modem = create_mock_modem()
        local cfg = fcp_main.load_config("config/fcp_config.json")
        local ctx = fcp_main.create_context(cfg, function() return mock_modem end)
        ctx.fsm.currentState = "ACTIVE_TRACKING"
        ctx.fsm.flightActive = true
        ctx.fsm.arm = true

        local alert_pkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "VAS-01",
            seq = 10,
            type = "MSG_EMERGENCY_ALERT",
            payload = { reason = "SENSOR_TIMEOUT_15TICKS", isAirborne = true, fsmState = "FAILSAFE_HOLD", altitude = 80.0 },
        }

        -- Base+1 alert must be ignored
        assert_false(network_manager.ingest_modem_event(ctx.net, "top", 10001, 10001, alert_pkt, 0, 1000))
        mock_modem.transmitted = {}
        fcp_main.step_tick(ctx, 0.05, 1000)
        assert_eq(ctx.fsm.currentState, "ACTIVE_TRACKING")

        -- Base+9 alert triggers EMERGENCY_HOLD, silences Base+1, and reports status on Base+4
        assert_true(network_manager.ingest_modem_event(ctx.net, "top", 10009, 10009, alert_pkt, 0, 1050))
        mock_modem.transmitted = {}
        fcp_main.step_tick(ctx, 0.05, 1050)
        assert_eq(ctx.fsm.currentState, "EMERGENCY_HOLD")
        assert_false(ctx.fsm.flightActive)

        local att_count = 0
        local status_pkt = nil
        for _, tx in ipairs(mock_modem.transmitted) do
            if tx.channel == 10001 then att_count = att_count + 1 end
            if tx.channel == 10004 and tx.payload.type == "MSG_OUTER_LOOP_STATUS" then
                status_pkt = tx.payload
            end
        end
        assert_eq(att_count, 0, "Base+1 must be silent in EMERGENCY_HOLD")
        assert_not_nil(status_pkt, "Base+4 MSG_OUTER_LOOP_STATUS must be emitted in EMERGENCY_HOLD")
        assert_eq(status_pkt.payload.fsmState, "EMERGENCY_HOLD")
    end)

    it("silences Base+1 during IDLE_ARMED when VAS is in AIRBORNE_RECOVERY_HOLD, blocks OTA, and triggers bumpless ramp on AMM recovery", function()
        local network_manager = require("network_manager")
        local mock_modem = create_mock_modem()
        local rootDir = sdk.temp_path("fcp_cold_boot_ota")
        if fs.exists(rootDir) then fs.delete(rootDir) end
        fs.makeDir(rootDir)

        local cfg = fcp_main.load_config("config/fcp_config.json")
        cfg.ota = { bayId = 1, rootDir = rootDir, onRebootFn = function() end }
        local ctx = fcp_main.create_context(cfg, function() return mock_modem end)
        ctx.fsm.currentState = "IDLE_ARMED"

        ctx.net.inbound.telemetry = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "VAS-01",
            seq = 1,
            type = "MSG_FLIGHT_TELEMETRY",
            payload = {
                dynamics = { velocity = { vx = 0, vy = -2.0, vz = 0 } },
                attitude = { pitch = 0, roll = 0, yaw = 0 },
                angularRates = { pitchRate = 0, rollRate = 0, yawRate = 0 },
                activeSource = "FCP",
                controlState = "AIRBORNE_RECOVERY_HOLD",
                actuatorHealth = { tap = true, asa = true, allOk = true },
                sensorOk = true,
            },
        }
        ctx.net.inbound.trajectory = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "AMM-03",
            seq = 1,
            type = "MSG_TRAJECTORY_SETPOINT",
            payload = { arm = false, flightActive = false, flightMode = "IDLE_ARMED", lastRxMs = 1000 },
        }

        mock_modem.transmitted = {}
        fcp_main.step_tick(ctx, 0.05, 1000)

        assert_eq(ctx.fsm.currentState, "IDLE_ARMED")
        local attCount = 0
        for _, tx in ipairs(mock_modem.transmitted) do
            if tx.channel == 10001 and tx.payload.type == "MSG_ATTITUDE_CMD" then
                attCount = attCount + 1
            end
        end
        assert_eq(attCount, 0, "FCP must silence Base+1 arm=false emission while VAS is in AIRBORNE_RECOVERY_HOLD")

        -- OTA must reject with NOT_DISARMED while VAS reports AIRBORNE_RECOVERY_HOLD
        local ota_agent = require("ota_agent")
        local crc = ota_agent.crc32("return true")
        network_manager.ingest_modem_event(ctx.net, "top", 105, 106, {
            ver = "1.9.5",
            domainId = "HANGAR",
            seq = 10,
            time = 1000,
            type = "MSG_OTA_BEGIN",
            payload = {
                txId = "tx-cb",
                targetModuleId = "fcp",
                targetDomainId = "AIRCRAFT_01",
                targetVersion = "2.4.0",
                totalBytes = 11,
                totalCrc32 = crc,
                files = { { path = "/main.lua", size = 11, crc32 = crc, chunkCount = 1 } },
            },
        }, 1, 1000)
        local nackReason = nil
        for _, tx in ipairs(mock_modem.transmitted) do
            if tx.channel == 106 and tx.payload.type == "MSG_OTA_NACK" then
                nackReason = tx.payload.payload.reason
            end
        end
        assert_eq(nackReason, "NOT_DISARMED")

        -- AMM completes cold-boot sync and sends arm=true, flightActive=true -> bumpless ACTIVE_TRACKING
        ctx.net.inbound.trajectory = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "AMM-03",
            seq = 2,
            type = "MSG_TRAJECTORY_SETPOINT",
            payload = {
                arm = true,
                flightActive = true,
                flightMode = "CRUISE",
                targetPos = { x = 50, y = 120, z = 0 },
                targetVel = { vx = 10, vy = 0, vz = 0 },
                currentPos = { x = 0, y = 120, z = 0 },
                navValid = true,
                posEpoch = 1100,
                lastRxMs = 1100,
            },
        }
        mock_modem.transmitted = {}
        fcp_main.step_tick(ctx, 0.05, 1100)
        assert_eq(ctx.fsm.currentState, "ACTIVE_TRACKING")
        assert_not_nil(ctx.rampStartMs, "Transitioning out of AIRBORNE_RECOVERY_HOLD must trigger bumpless ramp")
        assert_eq(ctx.rampAlpha, 0.0)
        if fs.exists(rootDir) then fs.delete(rootDir) end
    end)
end)

describe("test_fcp_main_v2: ui_renderer 51x19 character HUD matrix", function()
    it("renders exactly 19 rows with exact width 51 characters in all lines", function()
        local win = create_mock_term()
        local cfg = fcp_main.load_config("config/fcp_config.json")
        local mock_modem = create_mock_modem()
        local ctx = fcp_main.create_context(cfg, function() return mock_modem end)
        ctx.fsm.currentState = "ACTIVE_TRACKING"
        ctx.tick = 42

        local res = ui_renderer.render(win, ctx)
        assert_true(res, "ui_renderer.render must return true")

        -- Verify all 19 rows
        local rowCount = 0
        for i = 1, 19 do
            local line = win.rows[i]
            local fg = win.fg[i]
            local bg = win.bg[i]
            assert_not_nil(line, "Row " .. tostring(i) .. " must be rendered")
            assert_eq(#line, 51, "Row " .. tostring(i) .. " text length must be exactly 51 chars, got: " .. tostring(#line))
            assert_eq(#fg, 51, "Row " .. tostring(i) .. " fg length must be exactly 51 chars, got: " .. tostring(#fg))
            assert_eq(#bg, 51, "Row " .. tostring(i) .. " bg length must be exactly 51 chars, got: " .. tostring(#bg))
            rowCount = rowCount + 1
        end
        assert_eq(rowCount, 19, "Must render exactly 19 rows for 51x19 terminal")
    end)
end)

describe("test_fcp_main_v2: R5 config wiring (loopFrequencyHz and coreTelemetryTimeoutMs)", function()
    it("computes loopIntervalSec from system.loopFrequencyHz in create_context and run_control_loop", function()
        local mock_modem = create_mock_modem()
        local cfg = fcp_main.load_config("config/fcp_config.json")
        cfg.system.loopFrequencyHz = 10
        local ctx = fcp_main.create_context(cfg, function() return mock_modem end)
        assert_near(ctx.loopIntervalSec, 0.1, 1e-6)

        local timerDurations = {}
        local nextId = 50
        sdk.patch(os, "startTimer", function(sec)
            nextId = nextId + 1
            table.insert(timerDurations, sec)
            return nextId
        end)
        local pulls = 0
        sdk.patch(os, "pullEventRaw", function()
            pulls = pulls + 1
            if pulls == 1 then return "timer", nextId end
            return "terminate"
        end)

        assert_eq(type(fcp_main._run_control_loop), "function")
        fcp_main._run_control_loop(ctx)
        assert_true(#timerDurations >= 2)
        assert_near(timerDurations[1], 0.1, 1e-6)
        assert_near(timerDurations[2], 0.1, 1e-6)
    end)

    it("wires safety.coreTelemetryTimeoutMs to freeze integrators and flag status without forcing EMERGENCY_HOLD", function()
        local mock_modem = create_mock_modem()
        local cfg = fcp_main.load_config("config/fcp_config.json")
        cfg.safety = cfg.safety or {}
        cfg.safety.coreTelemetryTimeoutMs = 250
        cfg.safety.navStaleTimeoutMs = 1000
        cfg.safety.ammSetpointTimeoutMs = 2000

        local ctx = fcp_main.create_context(cfg, function() return mock_modem end)
        assert_eq(ctx.nav.coreTelemetryTimeoutMs, 250)
        ctx.fsm.currentState = "ACTIVE_TRACKING"
        ctx.fsm.flightActive = true
        ctx.fsm.arm = true

        local function make_sp(nowMs)
            return {
                ver = "1.9.5",
                domainId = "AIRCRAFT_01",
                senderId = "AMM-03",
                seq = nowMs,
                type = "MSG_TRAJECTORY_SETPOINT",
                payload = {
                    arm = true,
                    flightActive = true,
                    flightMode = "CRUISE",
                    targetPos = { x = 50, y = 64, z = 0 },
                    targetVel = { vx = 5.0, vy = 0.0, vz = 0.0 },
                    currentPos = { x = 0, y = 64, z = 0 },
                    navValid = true,
                    posEpoch = nowMs,
                    lastRxMs = nowMs,
                },
            }
        end
        local function make_telem(seq)
            return {
                ver = "1.9.5",
                domainId = "AIRCRAFT_01",
                senderId = "VAS-01",
                seq = seq,
                type = "MSG_FLIGHT_TELEMETRY",
                payload = {
                    dynamics = { velocity = { vx = 0.0, vy = 0.0, vz = 0.0 } },
                    attitude = { pitch = 0, roll = 0, yaw = 0 },
                    angularRates = { pitchRate = 0, rollRate = 0, yawRate = 0 },
                    activeSource = "FCP",
                    controlState = "NORMAL",
                    actuatorHealth = { tca = true, asa = true, tap = true, allOk = true },
                    sensorOk = true,
                },
            }
        end

        -- Tick 1 at t=1000 with fresh telemetry: accumulates integrator
        ctx.net.inbound.telemetry = make_telem(1)
        ctx.net.inbound.trajectory = make_sp(1000)
        fcp_main.step_tick(ctx, 0.05, 1000)
        assert_false(ctx.nav.coreTelemetryTimedOut == true)
        assert_false(ctx.freezeIntegrators == true)
        assert_false(ctx.latestOuterLoopStatus.coreTelemetryTimedOut == true)
        local intAfterFresh = ctx.ctrl.integrators.x
        assert_true(intAfterFresh > 0, "Integrator X must grow on fresh telemetry")

        -- Tick 2 at t=1250 (250ms elapsed >= coreTelemetryTimeoutMs=250, < navStaleTimeoutMs=1000): freezes integrators & flags status
        ctx.net.inbound.telemetry = nil
        ctx.net.inbound.trajectory = make_sp(1250)
        mock_modem.transmitted = {}
        fcp_main.step_tick(ctx, 0.05, 1250)
        assert_eq(ctx.fsm.currentState, "ACTIVE_TRACKING", "Must NOT force EMERGENCY_HOLD on coreTelemetryTimeoutMs")
        assert_true(ctx.nav.coreTelemetryTimedOut, "ctx.nav.coreTelemetryTimedOut must become true")
        assert_true(ctx.freezeIntegrators, "ctx.freezeIntegrators must become true")
        assert_near(ctx.ctrl.integrators.x, intAfterFresh, 1e-9, "Integrator X must remain frozen during core telemetry timeout")
        assert_true(ctx.latestOuterLoopStatus.coreTelemetryTimedOut, "Status telemetry must expose coreTelemetryTimedOut=true")

        -- Tick 3 at t=1300 with fresh telemetry: clears timeout and resumes integration
        ctx.net.inbound.telemetry = make_telem(2)
        ctx.net.inbound.trajectory = make_sp(1300)
        fcp_main.step_tick(ctx, 0.05, 1300)
        assert_false(ctx.nav.coreTelemetryTimedOut, "coreTelemetryTimedOut must clear on fresh telemetry")
        assert_false(ctx.freezeIntegrators, "freezeIntegrators must clear on fresh telemetry")
        assert_false(ctx.latestOuterLoopStatus.coreTelemetryTimedOut)
        assert_true(ctx.ctrl.integrators.x > intAfterFresh, "Integrator X must resume after fresh telemetry")
    end)
end)
