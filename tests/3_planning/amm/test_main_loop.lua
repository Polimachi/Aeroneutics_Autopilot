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

    it("executes run, load, files, stop, next, and mission CLI commands with PILOT_PRIMARY takeover and queue fallback", function()
        local main_mod = require("main")
        local mission_engine = require("mission_engine")
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local q = waypoint_queue.new({ defaultAlt = 150, defaultSpeed = 18, arrivalRadius = 15 })
        local eng = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        local arb = c2_arbiter.new(q, net, { baseChannel = 10000 }, eng)
        local inp = input_handler.new()
        local app = { config = { domainId = "AIRCRAFT_01", baseChannel = 10000 }, queue = q, net = net, engine = eng, arbiter = arb, input = inp, now_ms = 1000 }

        if not fs.exists("/disk") then fs.makeDir("/disk") end
        local f = fs.open("/disk/cli_sortie.json", "w")
        f.write(textutils.serializeJSON({
            missionId = "CLI_SORTIE",
            checkpoints = {
                { checkpointId = "CP_1", action = "FLY_OVER", params = { x = 100, z = 200 } },
                { checkpointId = "CP_2", action = "ORBIT", params = { x = 300, z = 400, radius = 35 } },
            },
        }))
        f.close()

        -- 1. files lists /disk/cli_sortie
        main_mod.execute_cli_command(app, { type = "COMMAND", name = "files", args = {} }, 1000)
        assert_true(string.find(arb.lastBanner, "/disk/cli_sortie", 1, true) ~= nil)

        -- 2. load resolves /disk/cli_sortie without .json and leaves engine IDLE
        main_mod.execute_cli_command(app, { type = "COMMAND", name = "load", args = { "/disk/cli_sortie" } }, 1050)
        assert_eq(eng.state, "IDLE")
        assert_eq(eng.missionId, "CLI_SORTIE")

        -- 3. GCS_OVERRIDE followed by mission run loop -> PILOT_PRIMARY takeover + REPEAT execution
        arb.authority = "GCS_OVERRIDE"
        eng.authority = "GCS_OVERRIDE"
        main_mod.execute_cli_command(app, { type = "COMMAND", name = "mission", args = { "run", "/disk/cli_sortie", "loop" } }, 1100)
        assert_eq(arb.authority, "PILOT_PRIMARY")
        assert_eq(eng.authority, "PILOT_PRIMARY")
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.executionMode, "REPEAT")
        assert_eq(eng.active_index, 1)

        -- 4. next advances to CP 2; stop aborts cleanly
        main_mod.execute_cli_command(app, { type = "COMMAND", name = "next", args = {} }, 1200)
        assert_eq(eng.active_index, 2)
        main_mod.execute_cli_command(app, { type = "COMMAND", name = "stop", args = {} }, 1300)
        assert_eq(eng.state, "ABORTED")

        -- 5. run with no args when only legacy queue has items -> migrates and starts engine
        local eng_q = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        local q2 = waypoint_queue.new({ defaultAlt = 150, defaultSpeed = 18, arrivalRadius = 15 })
        q2:add(50, 60)
        local arb2 = c2_arbiter.new(q2, net, { baseChannel = 10000 }, eng_q)
        local app2 = { config = { baseChannel = 10000 }, queue = q2, net = net, engine = eng_q, arbiter = arb2, input = inp, now_ms = 2000 }
        main_mod.execute_cli_command(app2, { type = "COMMAND", name = "run", args = {} }, 2000)
        assert_eq(eng_q.state, "EN_ROUTE")
        assert_eq(eng_q:count(), 1)

        if fs.exists("/disk/cli_sortie.json") then fs.delete("/disk/cli_sortie.json") end
    end)

    it("handles file_transfer drops safely across IDLE, autoRunDroppedFile, EN_ROUTE, and invalid payloads", function()
        local main_mod = require("main")
        local mission_engine = require("mission_engine")
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local q = waypoint_queue.new({ defaultAlt = 150, defaultSpeed = 18, arrivalRadius = 15 })
        local eng = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        local arb = c2_arbiter.new(q, net, { baseChannel = 10000 }, eng)
        local inp = input_handler.new()

        local function make_transfer(name, body)
            local closed = false
            return {
                getFiles = function()
                    return {
                        {
                            getName = function() return name end,
                            readAll = function() return body end,
                            close = function() closed = true end,
                        },
                    }
                end,
                isClosed = function() return closed end,
            }
        end

        local valid_json = textutils.serializeJSON({
            missionId = "DROPPED_01",
            checkpoints = { { checkpointId = "CP_1", action = "FLY_TO", params = { x = 250, z = -350 } } },
        })
        local app = {
            config = { domainId = "AIRCRAFT_01", baseChannel = 10000, autoRunDroppedFile = false },
            queue = q, net = net, engine = eng, arbiter = arb, input = inp, now_ms = 1000,
        }

        -- 1. Drop valid file while IDLE (autoRunDroppedFile = false) -> saves and loads IDLE
        main_mod.process_event(app, "file_transfer", make_transfer("dropped_01.json", valid_json))
        assert_true(fs.exists("missions/dropped_01.json"))
        assert_eq(eng.missionId, "DROPPED_01")
        assert_eq(eng.state, "IDLE")
        assert_true(string.find(arb.lastBanner, "DROP LOADED", 1, true) ~= nil)

        -- 2. Drop invalid JSON with same name -> DROP FAIL without overwriting existing valid file!
        main_mod.process_event(app, "file_transfer", make_transfer("dropped_01.json", "{invalid-json"))
        assert_true(string.find(arb.lastBanner, "DROP FAIL", 1, true) ~= nil)
        local check_f = fs.open("missions/dropped_01.json", "r")
        local preserved = check_f.readAll()
        check_f.close()
        assert_true(string.find(preserved, "DROPPED_01", 1, true) ~= nil)

        -- 3. Drop with autoRunDroppedFile = true while IDLE -> auto starts EN_ROUTE
        app.config.autoRunDroppedFile = true
        local valid2 = textutils.serializeJSON({
            missionId = "DROPPED_02",
            checkpoints = { { checkpointId = "CP_A", action = "FLY_OVER", params = { x = 10, z = 20 } } },
        })
        main_mod.process_event(app, "file_transfer", make_transfer("dropped_02.json", valid2))
        assert_eq(eng.missionId, "DROPPED_02")
        assert_eq(eng.state, "EN_ROUTE")

        -- 4. Drop valid file while EN_ROUTE -> saves to disk only, active flight stays DROPPED_02!
        local valid3 = textutils.serializeJSON({
            missionId = "DROPPED_03",
            checkpoints = { { checkpointId = "CP_B", action = "FLY_OVER", params = { x = 99, z = 99 } } },
        })
        main_mod.process_event(app, "file_transfer", make_transfer("../escape/dropped_03.json", valid3))
        assert_true(fs.exists("missions/dropped_03.json"))
        assert_eq(eng.missionId, "DROPPED_02")
        assert_eq(eng.state, "EN_ROUTE")
        assert_true(string.find(arb.lastBanner, "DROP SAVED", 1, true) ~= nil)

        if fs.exists("missions/dropped_01.json") then fs.delete("missions/dropped_01.json") end
        if fs.exists("missions/dropped_02.json") then fs.delete("missions/dropped_02.json") end
        if fs.exists("missions/dropped_03.json") then fs.delete("missions/dropped_03.json") end
    end)

    it("disambiguates shell boot arguments from config paths and auto-starts /disk missions in REPEAT mode", function()
        local main_mod = require("main")
        local mission_engine = require("mission_engine")
        local cfg_p, msn_p, mode_p = main_mod.parse_boot_args("config/amm_config.json", "/disk/sortie_01", "loop")
        assert_eq(cfg_p, "config/amm_config.json")
        assert_eq(msn_p, "/disk/sortie_01")
        assert_eq(mode_p, "loop")

        local cfg_d, msn_d, mode_d = main_mod.parse_boot_args("/disk/boot_sortie.json", "loop")
        assert_nil(cfg_d)
        assert_eq(msn_d, "/disk/boot_sortie.json")
        assert_eq(mode_d, "loop")

        if not fs.exists("/disk") then fs.makeDir("/disk") end
        local f = fs.open("/disk/boot_sortie.json", "w")
        f.write(textutils.serializeJSON({
            missionId = "BOOT_SORTIE",
            executionMode = "SINGLE",
            checkpoints = { { checkpointId = "CP_1", action = "FLY_OVER", params = { x = 10, z = 20 } } },
        }))
        f.close()

        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local eng = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        local ok = main_mod.try_auto_start_mission(eng, msn_d, 1000, {}, nil, mode_d)
        assert_true(ok)
        assert_eq(eng.missionId, "BOOT_SORTIE")
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.executionMode, "REPEAT")

        if fs.exists("/disk/boot_sortie.json") then fs.delete("/disk/boot_sortie.json") end
    end)

    it("runs closed-loop 20Hz tick step transmitting canonical setpoint on Base+4 and 5Hz MFD state on Base+3", function()
        local main_mod = require("main")
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })
        local app = main_mod.create_app({ domainId = "AIRCRAFT_01", baseChannel = 10000, headless = true }, { top = top_m, back = back_m })

        assert_not_nil(app.nav)
        assert_not_nil(app.sentinel)
        assert_not_nil(app.fac)
        assert_not_nil(app.traj)

        -- Ingest flight telemetry on Base+2 (simulated incoming)
        app.nav:integrate_dr({
            dynamics = { velocity = { vx = 10.0, vy = 1.0, vz = 0.0 }, altitudeY = 120.0, groundSpeed = 10.0, verticalSpeed = 1.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 90.0 },
            fuel = 0.95,
        }, 0.05, 1000)

        -- Execute 4 ticks to trigger 20Hz trajectory and 5Hz MFD state downlink
        local sp1 = main_mod.step_20hz_tick(app, 0.05, 1050)
        assert_not_nil(sp1)
        assert_not_nil(sp1.feedforwardAccel)
        assert_not_nil(sp1.targetHeading)
        assert_not_nil(sp1.currentPos)

        main_mod.step_20hz_tick(app, 0.05, 1100)
        main_mod.step_20hz_tick(app, 0.05, 1150)
        local sp4 = main_mod.step_20hz_tick(app, 0.05, 1200)
        assert_eq(app.tickCount, 4)

        -- Verify Base+4 setpoint packets transmitted
        local setpoint_tx = {}
        local mfd_tx = {}
        for _, tx in ipairs(top_m._transmitted) do
            if tx.tx == 10004 then
                table.insert(setpoint_tx, tx)
            elseif tx.tx == 10003 then
                table.insert(mfd_tx, tx)
            end
        end
        assert_eq(#setpoint_tx, 4)
        assert_eq(#mfd_tx, 1)
        assert_eq(setpoint_tx[4].pkt.type, "MSG_TRAJECTORY_SETPOINT")
        assert_eq(mfd_tx[1].pkt.type, "MSG_MFD_STATE")

        -- Verify MFD state suppression when activeSource is MFD_ACRO
        app.arbiter.activeSource = "MFD_ACRO"
        for _ = 1, 4 do
            main_mod.step_20hz_tick(app, 0.05, 1250)
        end
        assert_eq(#mfd_tx, 1) -- Still 1, suppressed!
    end)

    it("routes Base+5 MSG_GPS_RESPONSE through filter_gps updating app.nav.pos and posEpoch without crashing", function()
        local main_mod = require("main")
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })
        local app = main_mod.create_app({ domainId = "AIRCRAFT_01", baseChannel = 10000, headless = true }, { top = top_m, back = back_m })

        assert_eq(app.nav.posEpoch, 0)
        local gps_pkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 1,
            type = "MSG_GPS_RESPONSE",
            time = 1000,
            payload = {
                targetClient = "AIRCRAFT_01",
                status = "FIX_OK",
                clientSeq = 1,
                position = { x = 123.4, y = 70.0, z = -567.8 },
                hdop = 1.2,
                accuracy = 0.5,
            }
        }
        app.nav.gpsReqSeq = 1
        main_mod.process_event(app, "modem_message", "top", 10005, 10005, gps_pkt, 10)

        assert_true(app.nav.posEpoch > 0)
        assert_true(math.abs(app.nav.pos.x - 43.19) < 0.001)
        assert_true(math.abs(app.nav.pos.z - (-198.73)) < 0.001)
        assert_true(app.nav.navValid)
    end)

    it("executes non-headless Coroutine B timer rendering without double-ticking app.engine:tick", function()
        local main_mod = require("main")
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })
        local app = main_mod.create_app({ domainId = "AIRCRAFT_01", baseChannel = 10000, headless = false }, { top = top_m, back = back_m })

        local blit_count = 0
        app.term_obj = {
            setCursorPos = function() end,
            blit = function() blit_count = blit_count + 1 end,
        }

        local tick_count = 0
        app.engine.tick = function(self, now_ms)
            tick_count = tick_count + 1
        end

        -- 1. Direct render_ui_frame execution renders 19 rows with 0 engine ticks
        main_mod.render_ui_frame(app, 1000)
        assert_eq(blit_count, 19)
        assert_eq(tick_count, 0)

        -- 2. handle_timer_event with coroutineActive = true renders without double-ticking
        app.coroutineActive = true
        main_mod.handle_timer_event(app, app.render_timer, 1200)
        assert_eq(blit_count, 38)
        assert_eq(tick_count, 0)
    end)

    it("detects live GPS timeout in step_20hz_tick and propagates gpsTimedOut to Base+4 setpoint and Base+3 MFD telemetry", function()
        local main_mod = require("main")
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })
        local app = main_mod.create_app({
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            headless = true,
            navigation = { gpsTimeoutMs = 5000 },
        }, { top = top_m, back = back_m })

        app.nav.lastGpsFixMs = 1000
        app.nav.gpsStale = false

        -- Within timeout (now = 5000, elapsed = 4000 <= 5000): gpsTimedOut remains false
        local sp_ok = main_mod.step_20hz_tick(app, 0.05, 5000)
        assert_false(app.nav.gpsStale)
        assert_false(sp_ok.gpsTimedOut)

        -- Stalled beyond timeout (now = 6500, elapsed = 5500 > 5000): gpsTimedOut flips true on setpoint and Base+3 MFD
        app.tickCount = 3 -- next step_20hz_tick hits tickCount % 4 == 0 to emit Base+3 MFD telemetry
        local sp_stale = main_mod.step_20hz_tick(app, 0.05, 6500)
        assert_true(app.nav.gpsStale)
        assert_true(sp_stale.gpsTimedOut)

        local mfd_pkt = nil
        for _, tx in ipairs(top_m._transmitted) do
            if tx.tx == 10003 and tx.pkt and tx.pkt.type == "MSG_MFD_STATE" then
                mfd_pkt = tx.pkt
            end
        end
        assert_not_nil(mfd_pkt)
        assert_true(mfd_pkt.payload.navigation.gpsTimedOut)
    end)
end)
