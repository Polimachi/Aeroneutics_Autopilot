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
    end)
end)

describe("test_fcp_main_v2: context creation and channel binding", function()
    it("initializes runtime context and opens 3 core channels on primary modem", function()
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

        -- Verify 3 channels opened: 10004, 10002, 10001
        assert_true(mock_modem.isOpen(10004), "Trajectory channel 10004 must be open")
        assert_true(mock_modem.isOpen(10002), "Telemetry channel 10002 must be open")
        assert_true(mock_modem.isOpen(10001), "Guidance channel 10001 must be open")
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
