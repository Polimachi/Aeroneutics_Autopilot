-- tests/3_planning/amm/test_main_loop.lua
local waypoint_queue = require("waypoint_queue")
local network_manager = require("network_manager")
local c2_arbiter = require("c2_arbiter")
local input_handler = require("input_handler")
local ui_renderer = require("ui_renderer")

describe("AMM Main Event Pump and Command Processing", function()
    local function create_app()
        local q = waypoint_queue.new({ defaultAlt = 150, defaultSpeed = 18, arrivalRadius = 15 })
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local arb = c2_arbiter.new(q, net)
        local inp = input_handler.new()
        local buf = ui_renderer.create_buffer(51, 19)
        local tx = {}
        net.modem = {
            transmit = function(c, r, p) table.insert(tx, { chan = c, payload = p }) end,
            open = function(c) end
        }
        return {
            q = q, net = net, arb = arb, inp = inp, buf = buf, tx = tx,
            handle_command = function(self, cmd)
                if not cmd or cmd.type ~= "COMMAND" then return end
                local name = cmd.name
                local a = cmd.args
                if name == "add" then
                    self.q:add(a[1], a[2], a[3], a[4], a[5])
                elseif name == "del" then
                    self.q:del(a[1])
                elseif name == "clear" then
                    self.q:clear()
                elseif name == "goto" then
                    self.q:set_active_index(a[1])
                elseif name == "pause" then
                    self.arb:handle_pilot_action("PAUSE")
                elseif name == "resume" then
                    self.arb:handle_pilot_action("RESUME")
                elseif name == "alt" then
                    self.q.defaultAlt = tonumber(a[1]) or self.q.defaultAlt
                elseif name == "spd" then
                    self.q.defaultSpeed = tonumber(a[1]) or self.q.defaultSpeed
                elseif name == "rad" then
                    self.q.arrivalRadius = tonumber(a[1]) or self.q.arrivalRadius
                end
            end
        }
    end

    it("executes CLI commands to modify waypoint queue and settings", function()
        local app = create_app()
        app:handle_command({ type = "COMMAND", name = "add", args = { "100", "200", "160", "20" } })
        assert_eq(app.q:count(), 1)
        assert_eq(app.q:get_active().x, 100)
        assert_eq(app.q:get_active().alt, 160)

        app:handle_command({ type = "COMMAND", name = "alt", args = { "180" } })
        assert_eq(app.q.defaultAlt, 180)

        app:handle_command({ type = "COMMAND", name = "spd", args = { "22" } })
        assert_eq(app.q.defaultSpeed, 22)

        app:handle_command({ type = "COMMAND", name = "rad", args = { "25" } })
        assert_eq(app.q.arrivalRadius, 25)

        app:handle_command({ type = "COMMAND", name = "clear", args = {} })
        assert_eq(app.q:count(), 0)
    end)

    it("routes incoming HUD telemetry and GCS commands accurately", function()
        local app = create_app()
        app.q:add(500, 500)

        -- Simulating incoming Base+0 GCS command
        local gcs_pkt = {
            ver = "1.9.5",
            type = "MSG_OPERATOR_CMD",
            payload = { authority = "GCS_OVERRIDE", command = "HOLD" }
        }
        app.arb:handle_gcs_packet(gcs_pkt)
        assert_eq(app.arb.authority, "GCS_OVERRIDE")
        assert_eq(app.q.state, "SUSPENDED")

        -- Simulating pilot resume CLI command
        app:handle_command({ type = "COMMAND", name = "resume", args = {} })
        assert_eq(app.arb.authority, "PILOT_PRIMARY")
        assert_eq(app.q.state, "EN_ROUTE")
    end)

    it("suppresses TUI rendering in headless mode while ticking hooks/conditions and routing Zone 3 ACKs", function()
        local main_mod = require("main")
        local mission_engine = require("mission_engine")
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local rs = mock.redstone()
        local q = waypoint_queue.new({ defaultAlt = 150, defaultSpeed = 18, arrivalRadius = 15 })
        local eng = mission_engine.new({ net = net, redstone = rs, colors = colors, config = { baseChannel = 10000 } })
        local arb = c2_arbiter.new(q, net, { baseChannel = 10000 }, eng)
        local inp = input_handler.new()

        local blit_calls = 0
        local spy_term = {
            setCursorPos = function() end,
            blit = function() blit_calls = blit_calls + 1 end,
        }

        assert_true(eng:load_table({
            missionId = "UAV_HEADLESS_SORTIE",
            checkpoints = {
                {
                    checkpointId = "CP_PAYLOAD",
                    action = "PAYLOAD_ACTION",
                    params = { channelOffset = 20, command = "SCAN", expectedStatus = "DONE" },
                    onEnter = { { type = "REDSTONE_PULSE", side = "top", durationMs = 400 } },
                },
                {
                    checkpointId = "CP_HOLD",
                    action = "ORBIT",
                    params = { targetPos = { x = 100, z = 100 }, durationSec = 5 },
                },
            },
        }))

        local app = {
            config = { domainId = "AIRCRAFT_01", baseChannel = 10000, headless = true },
            queue = q,
            net = net,
            engine = eng,
            arbiter = arb,
            input = inp,
            screen_buf = ui_renderer.create_buffer(51, 19),
            render_timer = 77,
            term_obj = spy_term,
            now_ms = 1000,
        }

        -- Remote RUN command arrives on Base+0 via modem_message
        main_mod.process_event(app, "modem_message", "back", 10000, 10000, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1, type = "MSG_MISSION_CMD", time = 1000,
            payload = { action = "RUN", executionMode = "SINGLE" },
        }, 10)
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.active_index, 1)
        assert_true(rs.getOutput("top"))
        assert_true(m.isOpen(10020))

        -- 5Hz timer fires at 1500ms -> expires pulse without calling term.blit in headless mode
        app.now_ms = 1500
        main_mod.process_event(app, "timer", 77)
        assert_eq(blit_calls, 0)
        assert_false(rs.getOutput("top"))

        -- Zone 3 MSG_PAYLOAD_ACK arrives on Base+20 (10020) -> closes 10020 and advances to CP_HOLD (index 2)
        app.now_ms = 1600
        main_mod.process_event(app, "modem_message", "back", 10020, 10020, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 2, type = "MSG_PAYLOAD_ACK", time = 1600,
            payload = { checkpointId = "CP_PAYLOAD", command = "SCAN", status = "DONE" },
        }, 1)
        assert_false(m.isOpen(10020))
        assert_eq(eng.active_index, 2)
    end)

    it("preserves mission executionMode = REPEAT when auto-starting missions from file or table", function()
        local main_mod = require("main")
        local mission_engine = require("mission_engine")
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local eng = mission_engine.new({ net = net, config = { baseChannel = 10000 } })

        -- 1. Test auto-start from mission file with executionMode = "REPEAT"
        local temp_path = "missions/test_auto_repeat.json"
        if not fs.exists("missions") then fs.makeDir("missions") end
        local f = fs.open(temp_path, "w")
        assert_true(f ~= nil)
        f.write(textutils.serializeJSON({
            version = "1.1.0",
            missionId = "PATROL_REPEAT",
            executionMode = "REPEAT",
            checkpoints = {
                { checkpointId = "CP_01", action = "FLY_TO", params = { targetPos = { x = 10, z = 20 } } },
                { checkpointId = "CP_02", action = "FLY_TO", params = { targetPos = { x = 30, z = 40 } } },
            },
        }))
        f.close()

        main_mod.try_auto_start_mission(eng, "test_auto_repeat", 1000)
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.executionMode, "REPEAT")
        assert_eq(eng.active_index, 1)

        -- Clean up temp file
        if fs.exists(temp_path) then fs.delete(temp_path) end

        -- 2. Test auto-start with config override cfg.autoExecutionMode
        local eng2 = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        main_mod.try_auto_start_mission(eng2, {
            missionId = "OVERRIDE_TEST",
            executionMode = "SINGLE",
            checkpoints = {
                { checkpointId = "CP_01", action = "FLY_TO", params = { targetPos = { x = 50, z = 60 } } },
            },
        }, 2000, { autoExecutionMode = "REPEAT" })
        assert_eq(eng2.state, "EN_ROUTE")
        assert_eq(eng2.executionMode, "REPEAT")
    end)

    it("cleanly stops active mission, turns off active redstone pulses, and closes Zone 3 channels on shutdown_app", function()
        local main_mod = require("main")
        local mission_engine = require("mission_engine")
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local rs = mock.redstone()
        local eng = mission_engine.new({ net = net, redstone = rs, colors = colors, config = { baseChannel = 10000 } })

        assert_true(eng:load_table({
            missionId = "SHUTDOWN_TEST",
            checkpoints = {
                {
                    checkpointId = "CP_01",
                    action = "PAYLOAD_ACTION",
                    params = { channelOffset = 20, command = "COLLECT" },
                    onEnter = { { type = "REDSTONE_PULSE", side = "bottom", durationMs = 5000 } },
                },
            },
        }))
        assert_true(eng:start("SINGLE", 1000))
        assert_eq(eng.state, "EN_ROUTE")
        assert_true(rs.getOutput("bottom"))
        assert_true(m.isOpen(10020))

        local app = {
            engine = eng,
            running = true,
            now_ms = 1100,
        }

        assert_true(type(main_mod.shutdown_app) == "function")
        main_mod.shutdown_app(app)

        assert_false(app.running)
        assert_eq(eng.state, "ABORTED")
        assert_false(rs.getOutput("bottom"))
        assert_false(m.isOpen(10020))
    end)
end)
