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
                    action = "ACT_PAY_BUS_CMD",
                    params = { channelOffset = 20, command = "SCAN", expectedStatus = "DONE" },
                    onEnter = { { type = "REDSTONE_PULSE", side = "top", durationMs = 400 } },
                },
                {
                    checkpointId = "CP_HOLD",
                    action = "ACT_PAT_LOITER_TIME",
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

        -- Zone 3 MSG_PAYLOAD_ACK arrives on Base+20 (10020) -> deactivates openPayloadChannels[10020] while preserving full-block open state
        app.now_ms = 1600
        main_mod.process_event(app, "modem_message", "back", 10020, 10020, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 2, type = "MSG_PAYLOAD_ACK", time = 1600,
            payload = { checkpointId = "CP_PAYLOAD", command = "SCAN", status = "DONE" },
        }, 1)
        assert_nil(net.openPayloadChannels[10020])
        assert_true(m.isOpen(10020))
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
            version = "2.0.0",
            missionId = "PATROL_REPEAT",
            executionMode = "REPEAT",
            checkpoints = {
                { checkpointId = "CP_01", action = "ACT_NAV_GOTO_WP", params = { targetPos = { x = 10, z = 20 } } },
                { checkpointId = "CP_02", action = "ACT_NAV_GOTO_WP", params = { targetPos = { x = 30, z = 40 } } },
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
            version = "2.0.0",
            missionId = "OVERRIDE_TEST",
            executionMode = "SINGLE",
            checkpoints = {
                { checkpointId = "CP_01", action = "ACT_NAV_GOTO_WP", params = { targetPos = { x = 50, z = 60 } } },
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
            version = "2.0.0",
            missionId = "SHUTDOWN_TEST",
            checkpoints = {
                {
                    checkpointId = "CP_01",
                    action = "ACT_PAY_BUS_CMD",
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
        assert_nil(net.openPayloadChannels[10020])
        assert_true(m.isOpen(10020))
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
            version = "2.0.0",
            missionId = "CLI_SORTIE",
            checkpoints = {
                { checkpointId = "CP_1", action = "ACT_NAV_SPLINE_WP", params = { x = 100, z = 200 } },
                { checkpointId = "CP_2", action = "ACT_PAT_LOITER_TIME", params = { x = 300, z = 400, radius = 35 } },
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
            version = "2.0.0",
            missionId = "DROPPED_01",
            checkpoints = { { checkpointId = "CP_1", action = "ACT_NAV_GOTO_WP", params = { x = 250, z = -350 } } },
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
            version = "2.0.0",
            missionId = "DROPPED_02",
            checkpoints = { { checkpointId = "CP_A", action = "ACT_NAV_SPLINE_WP", params = { x = 10, z = 20 } } },
        })
        main_mod.process_event(app, "file_transfer", make_transfer("dropped_02.json", valid2))
        assert_eq(eng.missionId, "DROPPED_02")
        assert_eq(eng.state, "EN_ROUTE")

        -- 4. Drop valid file while EN_ROUTE -> saves to disk only, active flight stays DROPPED_02!
        local valid3 = textutils.serializeJSON({
            version = "2.0.0",
            missionId = "DROPPED_03",
            checkpoints = { { checkpointId = "CP_B", action = "ACT_NAV_SPLINE_WP", params = { x = 99, z = 99 } } },
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
            version = "2.0.0",
            missionId = "BOOT_SORTIE",
            executionMode = "SINGLE",
            checkpoints = { { checkpointId = "CP_1", action = "ACT_NAV_SPLINE_WP", params = { x = 10, z = 20 } } },
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
        local mfd_after_acro = 0
        for _, tx in ipairs(top_m._transmitted) do
            if tx.tx == 10003 then mfd_after_acro = mfd_after_acro + 1 end
        end
        assert_eq(mfd_after_acro, 1) -- Still 1, suppressed!
    end)

    it("enforces 300ms ACRO_RECOVERY_HOLD in step_5hz_downlink and step_20hz_tick after MFD_ACRO/FAILSAFE_HOLD recovery", function()
        local main_mod = require("main")
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })
        local app = main_mod.create_app({
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            headless = true,
            safety = { acroRecoveryHoldMs = 300 },
        }, { top = top_m, back = back_m })

        local function count_mfd()
            local c = 0
            for _, tx in ipairs(top_m._transmitted) do
                if tx.tx == 10003 then c = c + 1 end
            end
            return c
        end

        -- 1. VAS sends MFD_ACRO at t=1000 via Base+3 -> yields immediately
        app.arbiter:handle_mfd_state({
            payload = { source = "CORE_ACRO_TAKEOVER", fsmState = "NORMAL", acroActive = true },
        }, 1000)
        -- 2. VAS returns to FCP via Base+2 at t=1050 -> still held until 1300
        app.arbiter:handle_flight_telemetry({
            payload = { controlState = "NORMAL", activeSource = "FCP" },
        }, 1050)

        app.tickCount = 3
        main_mod.step_20hz_tick(app, 0.05, 1250)
        assert_eq(count_mfd(), 0)

        local ok_dl, err_dl = main_mod.step_5hz_downlink(app, 1299)
        assert_false(ok_dl)
        assert_eq(err_dl, "ACRO_RECOVERY_HOLD")
        assert_eq(count_mfd(), 0)

        -- 3. At t=1300 (>= 300ms since lastVasPriorityMs=1000), step_5hz_downlink resumes Base+3
        local ok_res = main_mod.step_5hz_downlink(app, 1300)
        assert_true(ok_res)
        assert_eq(count_mfd(), 1)
    end)

    it("keeps simulated monotonic app.clock_ms consistent across handle_modem_message and step_5hz_downlink without wall-clock drift", function()
        local main_mod = require("main")
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })
        local app = main_mod.create_app({
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            headless = true,
            clock_ms = 1000,
            safety = { acroRecoveryHoldMs = 300 },
        }, { top = top_m, back = back_m })

        local function count_mfd()
            local c = 0
            for _, tx in ipairs(top_m._transmitted) do
                if tx.tx == 10003 then c = c + 1 end
            end
            return c
        end

        -- 1. Base+3 MFD_ACRO arrives via process_event/handle_modem_message at clock_ms=1000
        main_mod.process_event(app, "modem_message", "top", 10003, 10003, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1, type = "MSG_MFD_STATE", time = 1000,
            payload = { source = "CORE_ACRO_TAKEOVER", fsmState = "NORMAL", acroActive = true },
        }, 1)
        assert_eq(app.arbiter.lastVasPriorityMs, 1000)

        -- 2. Base+2 returns to FCP at clock_ms=1050 via handle_modem_message (no explicit now_ms arg)
        app.clock_ms = 1050
        main_mod.handle_modem_message(app, 10002, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 2, type = "MSG_FLIGHT_TELEMETRY", time = 1050,
            payload = { controlState = "NORMAL", activeSource = "FCP", fuel = 0.9 },
        })
        assert_eq(app.arbiter.activeSource, "FCP")

        -- 3. step_5hz_downlink(app) without explicit now_ms uses app.clock_ms=1299 -> ACRO_RECOVERY_HOLD
        app.clock_ms = 1299
        local ok_hold, err_hold = main_mod.step_5hz_downlink(app)
        assert_false(ok_hold)
        assert_eq(err_hold, "ACRO_RECOVERY_HOLD")
        assert_eq(count_mfd(), 0)

        -- 4. Direct net:send_mfd_state without explicit now_ms also consults arbiter.clockFn -> ACRO_RECOVERY_HOLD
        local ok_net_hold, err_net_hold = app.net:send_mfd_state({ fsmState = "NORMAL" }, "FCP")
        assert_false(ok_net_hold)
        assert_eq(err_net_hold, "ACRO_RECOVERY_HOLD")
        assert_eq(count_mfd(), 0)

        -- 5. Advance clock_ms=1350 (>= 300ms) -> step_5hz_downlink resumes Base+3
        app.clock_ms = 1350
        local ok_res = main_mod.step_5hz_downlink(app)
        assert_true(ok_res)
        assert_eq(count_mfd(), 1)
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

    it("integrates chattering_guard fuel latches in step_20hz_tick and confirm CLI command for DEC_HUMAN_AUTH", function()
        local main_mod = require("main")
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })
        local app = main_mod.create_app({
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            headless = true,
            safety = {
                lowFuelRthThreshold = 0.20,
                emergencyLandFuelThreshold = 0.10,
                chattering = { lowFuelDebounceTicks = 3, emergFuelDebounceTicks = 2, fuelLatchResetMargin = 0.05 },
            },
        }, { top = top_m, back = back_m })

        assert_not_nil(app.guard)
        assert_true(app.engine:load_table({
            version = "2.0.0",
            missionId = "CLI_CONFIRM",
            checkpoints = {
                {
                    checkpointId = "CP_AUTH",
                    action = "ACT_PAY_BUS_CMD",
                    decorators = { { decoratorId = "DEC_HUMAN_AUTH" } },
                    params = { channelOffset = 20, command = "DROP" },
                },
            },
        }))
        app.engine:start("SINGLE", 1000)
        assert_true(app.engine.waitingHumanAuth)

        main_mod.execute_cli_command(app, { type = "COMMAND", name = "confirm", args = {} }, 1100)
        assert_false(app.engine.waitingHumanAuth)

        app.lastMfd = { controlState = "NORMAL", fuel = 0.15 }
        main_mod.step_20hz_tick(app, 0.05, 1150)
        main_mod.step_20hz_tick(app, 0.05, 1200)
        assert_false(app.guard.latches.lowFuelLatched)
        main_mod.step_20hz_tick(app, 0.05, 1250)
        assert_true(app.guard.latches.lowFuelLatched)
        assert_eq(app.guard, app.arbiter.guard)
        assert_eq(app.guard, app.engine.guard)
    end)

    it("wires sentinel probe/rebind propagation, [I-5] ATC/GAC channels & watchdog, [I-6] MFD fields, Ctrl+X ESTOP, and CLI queue sync", function()
        local main_mod = require("main")
        local left_m = mock.modem({ wireless = true })
        local right_m = mock.modem({ wireless = true })
        local test_lease_wiring = "config/test_lease_main_wiring.json"
        if fs.exists(test_lease_wiring) then fs.delete(test_lease_wiring) end
        local app = main_mod.create_app({
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            headless = true,
            clock_ms = 1000,
            leasePath = test_lease_wiring,
            safety = { probeJitterMaxMs = 0, probeRetryCount = 2, channelProbeWaitMs = 200 },
            system = { primaryModemSide = "left", infraModemSide = "right" },
        }, { left = left_m, right = right_m })
        assert_eq(app.net.onboardModem, left_m)
        assert_eq(app.net.infraModem, right_m)

        -- 1. Sentinel INIT -> step_20hz_tick sends MSG_BLOCK_REQUEST on 50000 via infraModem
        main_mod.step_20hz_tick(app, 0.05, 1000)
        local saw_boot = false
        for _, tx in ipairs(right_m._transmitted) do
            if tx.tx == 50000 and tx.pkt and tx.pkt.type == "MSG_BLOCK_REQUEST" then
                saw_boot = true
            end
        end
        assert_true(saw_boot)

        -- Assign candidate 10040 -> 2 rounds of 200ms probing -> ACQUIRED
        app.clock_ms = 1050
        main_mod.process_event(app, "modem_message", "right", 50000, 50000, {
            ver = "1.9.5", type = "MSG_BLOCK_ASSIGN", payload = { baseChannel = 10040, status = "ASSIGNED" }
        }, 1050)
        main_mod.step_20hz_tick(app, 0.05, 1100)
        assert_eq(app.sentinel.status, "PROBING")
        main_mod.step_20hz_tick(app, 0.05, 1300)
        assert_eq(app.sentinel.status, "PROBING")
        main_mod.step_20hz_tick(app, 0.05, 1550)
        assert_eq(app.sentinel.status, "ACQUIRED")

        -- Commit rebind to 10080 -> config, nav, engine, net all update
        app.sentinel.baseChannel = 10000
        app.net:apply_rebind(10000)
        local channel_sentinel = require("channel_sentinel")
        channel_sentinel.initiate_rebind(app.sentinel, 10080, 1400)
        app.clock_ms = 1450
        main_mod.process_event(app, "modem_message", "left", 10004, 10004, {
            ver = "1.9.5", type = "MSG_CHANNEL_REBIND_ACK",
            payload = { transactionId = "REBIND-TX-10000-10080", status = "READY" },
        }, 1450)
        main_mod.step_20hz_tick(app, 0.05, 1500)
        assert_eq(app.config.baseChannel, 10080)
        assert_eq(app.net.baseChannel, 10080)
        assert_eq(app.nav.baseChannel, 10080)
        assert_eq(app.engine.baseChannel, 10080)

        -- 2. [I-6] MFD downlink fields (next 5Hz tick: tickCount % 4 == 0)
        for i = 1, 3 do
            main_mod.step_20hz_tick(app, 0.05, 1500 + i * 50)
        end
        local mfd_pkt = nil
        for _, tx in ipairs(left_m._transmitted) do
            if tx.tx == 10083 and tx.pkt and tx.pkt.type == "MSG_MFD_STATE" then
                mfd_pkt = tx.pkt
            end
        end
        assert_not_nil(mfd_pkt)
        assert_eq(mfd_pkt.payload.source, "AMM_INTEGRATED")
        assert_eq(mfd_pkt.payload.flightMode, "IDLE_ARMED")
        assert_not_nil(mfd_pkt.payload.actuatorHealth)
        assert_not_nil(mfd_pkt.payload.sensorHealth)
        assert_not_nil(mfd_pkt.payload.angularRates)

        -- 3. [I-5] ATC clearance opens GAC/Pad channels & watchdog FAILSAFE_RTH after 10 denials
        app.clock_ms = 1600
        main_mod.process_event(app, "modem_message", "right", 50001, 50001, {
            ver = "1.9.5", type = "MSG_ATC_APPROACH_CLEARANCE",
            payload = { status = "CLEARED", assignedFacilityId = "PAD_01", gacChannel = 51000, assignedGuidanceChannel = 51010, padMobility = "DYNAMIC" },
        }, 1600)
        assert_true(app.net.openInfraChannels[51000] == true)
        assert_true(app.net.openInfraChannels[51010] == true)
        app.clock_ms = 1650
        main_mod.process_event(app, "modem_message", "right", 51010, 51010, {
            ver = "1.9.5", type = "MSG_FACILITY_DYNAMIC_GUIDE",
            payload = { facilityId = "PAD_01", touchdownPoint = { x = 10, y = 64, z = 20 }, deckStatus = "STABLE" },
        }, 1650)
        assert_eq(app.fac.dynamicGuide.facilityId, "PAD_01")
        app.fac.touchdownAborted = true
        assert_true(app.fac.touchdownAborted)
        app.clock_ms = 1700
        main_mod.process_event(app, "modem_message", "right", 51000, 51000, {
            ver = "1.9.5", type = "MSG_GAC_ABORT_CLEAR",
            payload = { reason = "WAVEOFF" },
        }, 1700)
        assert_false(app.fac.touchdownAborted)

        -- 4. CLI add/alt sync + Ctrl+X ESTOP
        main_mod.execute_cli_command(app, { type = "COMMAND", name = "alt", args = { "210" } }, 1750)
        assert_eq(app.engine.defaults.targetAlt, 210)
        main_mod.execute_cli_command(app, { type = "COMMAND", name = "add", args = { "100", "200" } }, 1760)
        assert_eq(app.engine:count(), 1)
        assert_eq(app.engine.checkpoints[1].params.targetAlt, 210)

        app.clock_ms = 1770
        app.input:set_mode("CLI")
        main_mod.process_event(app, "key", keys.leftCtrl or 29)
        main_mod.process_event(app, "char", "x")
        main_mod.process_event(app, "key_up", keys.leftCtrl or 29)
        assert_false(app.ctrlHeld)
        local estop_tx = left_m._transmitted[#left_m._transmitted]
        assert_eq(estop_tx.tx, 10089)
        assert_eq(estop_tx.pkt.type, "MSG_EMERGENCY_OVERRIDE")

        -- 5. ATC denial triggers retry transmission MSG_ATC_APPROACH_REQ without crashing, and CH 50004 dispatch is ignored by update_beacons
        app.clock_ms = 1780
        main_mod.process_event(app, "modem_message", "right", 50004, 50004, {
            ver = "1.9.5", type = "MSG_GAC_DISPATCH",
            payload = { facilityId = "PAD_IGNORED", pos = { x = 999, y = 64, z = 999 } },
        }, 1780)
        assert_nil(app.fac.beacons["PAD_IGNORED"])

        app.fac.beacons["PAD_01"] = { facilityId = "PAD_01", facilityType = "LANDING_PAD", pos = { x = 10, y = 64, z = 20 } }
        app.fac.activePadId = "PAD_01"
        app.fac.gacChannel = 51000
        app.fac.atcStatus = "DENIED"
        app.fac.atcDeniedCount = 1
        app.fac.nextAtcRetryMs = 1800
        main_mod.step_20hz_tick(app, 0.05, 1850)
        local retry_pkt = nil
        for _, tx in ipairs(right_m._transmitted) do
            if tx.tx == 51000 and tx.pkt and tx.pkt.type == "MSG_ATC_APPROACH_REQ" then
                retry_pkt = tx.pkt
            end
        end
        assert_not_nil(retry_pkt)
        assert_eq(retry_pkt.payload.targetFacilityId, "PAD_01")
        if fs.exists(test_lease_wiring) then fs.delete(test_lease_wiring) end
    end)

    it("drives Base+0 boot probe responder, GCS reassign loop, and LOCKED_CONFLICT arming lockout in main loop", function()
        local main_mod = require("main")
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })
        local lease_path = "config/test_lease_main_sentinel.json"
        if fs.exists(lease_path) then fs.delete(lease_path) end

        local app = main_mod.create_app({
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            headless = true,
            clock_ms = 1000,
            leasePath = lease_path,
            system = { hardwareUuid = "AMM-MAIN-01", primaryModemSide = "top", infraModemSide = "back" },
            safety = { probeJitterMaxMs = 0, probeRetryCount = 2, channelProbeWaitMs = 200, maxReassignAttempts = 3 },
        }, { top = top_m, back = back_m })

        -- 1. Self-UUID probe on Base+0 must NOT emit CONFLICT_DETECTED ACK
        app.sentinel.status = "DISARMED"
        app.clock_ms = 1000
        main_mod.process_event(app, "modem_message", "top", 10000, 10000, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1, type = "MSG_CHANNEL_PROBE", time = 1000,
            payload = { hardwareUuid = "AMM-MAIN-01", candidateBase = 10000, bandwidth = 40 },
        }, 1000)
        assert_eq(#top_m._transmitted, 0)

        -- 2. Foreign probe on Base+0 during DISARMED immediately emits MSG_CHANNEL_PROBE_ACK
        app.clock_ms = 1010
        main_mod.process_event(app, "modem_message", "top", 10000, 10000, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 2, type = "MSG_CHANNEL_PROBE", time = 1010,
            payload = { hardwareUuid = "AMM-OTHER-02", candidateBase = 10000, bandwidth = 40 },
        }, 1010)
        assert_eq(#top_m._transmitted, 1)
        assert_eq(top_m._transmitted[1].tx, 10000)
        assert_eq(top_m._transmitted[1].pkt.type, "MSG_CHANNEL_PROBE_ACK")
        assert_eq(top_m._transmitted[1].pkt.payload.status, "CONFLICT_DETECTED")
        assert_eq(top_m._transmitted[1].pkt.payload.responderUuid, "AMM-MAIN-01")

        -- 3. Probe conflict during PROBING emits MSG_BLOCK_REQUEST(conflictBase=10040) via step_20hz_tick
        app.sentinel.status = "INIT"
        main_mod.step_20hz_tick(app, 0.05, 1100)
        app.clock_ms = 1120
        main_mod.process_event(app, "modem_message", "back", 50000, 50000, {
            ver = "1.9.5", domainId = "GCS_01", seq = 1, type = "MSG_BLOCK_ASSIGN", time = 1120,
            payload = { baseChannel = 10040, status = "ASSIGNED" },
        }, 1120)
        main_mod.step_20hz_tick(app, 0.05, 1150) -- emits Round 1 probe on 10040
        assert_eq(app.sentinel.status, "PROBING")
        app.clock_ms = 1170
        main_mod.process_event(app, "modem_message", "top", 10040, 10040, {
            ver = "1.9.5", domainId = "AIRCRAFT_99", seq = 9, type = "MSG_CHANNEL_PROBE_ACK", time = 1170,
            payload = { conflict = true, status = "CONFLICT_DETECTED", occupiedBase = 10040, existingDomain = "AIRCRAFT_99", responderUuid = "OTHER-99" },
        }, 1170)
        assert_eq(app.sentinel.status, "REASSIGN_REQUEST")
        main_mod.step_20hz_tick(app, 0.05, 1200)
        local reassign_req = nil
        for _, tx in ipairs(back_m._transmitted) do
            if tx.tx == 50000 and tx.pkt and tx.pkt.type == "MSG_BLOCK_REQUEST" and tx.pkt.payload.conflictBase == 10040 then
                reassign_req = tx.pkt
            end
        end
        assert_not_nil(reassign_req)
        assert_eq(app.sentinel.status, "GCS_WAIT")

        -- 4. When sentinel is locked (LOCKED_NO_GCS), step_20hz_tick forces arm=false, flightActive=false
        app.sentinel.status = "LOCKED_NO_GCS"
        app.sentinel.locked = true
        app.arbiter:handle_gcs_packet({
            payload = { authority = "GCS_OVERRIDE", flightMode = "HOVER_HOLD" },
        }, 1250)
        local sp_locked = main_mod.step_20hz_tick(app, 0.05, 1300)
        assert_false(sp_locked.arm)
        assert_false(sp_locked.flightActive)

        if fs.exists(lease_path) then fs.delete(lease_path) end
    end)

    it("passes own domainId in O(1), blocks foreign Base+0..39 intrusion packets, and escalates to HOVER_HOLD at 30000ms", function()
        local main_mod = require("main")
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })
        local lease_path = "config/test_lease_main_intrusion.json"
        if fs.exists(lease_path) then fs.delete(lease_path) end

        local app = main_mod.create_app({
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            headless = true,
            clock_ms = 1000,
            leasePath = lease_path,
            system = { hardwareUuid = "AMM-MAIN-INT", primaryModemSide = "top", infraModemSide = "back" },
            safety = { intrusionAlertWindowMs = 30000 },
        }, { top = top_m, back = back_m })
        app.sentinel.status = "ACQUIRED"

        -- 1. Own domainId on Base+2 and infra GPS response on Base+5 pass with 0 intrusions
        app.clock_ms = 1000
        main_mod.process_event(app, "modem_message", "top", 10002, 10002, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1, type = "MSG_FLIGHT_TELEMETRY", time = 1000,
            payload = { fuel = 0.9, controlState = "NORMAL", activeSource = "FCP", dynamics = { altitudeY = 100, velocity = { vx = 0, vy = 0, vz = 0 } } },
        }, 1000)
        app.nav.gpsReqSeq = 1
        main_mod.process_event(app, "modem_message", "back", 10005, 10005, {
            ver = "1.9.5", domainId = "GPS_BASE_NET", seq = 1, type = "MSG_GPS_RESPONSE", time = 1000,
            payload = { targetClient = "AIRCRAFT_01", status = "FIX_OK", clientSeq = 1, position = { x = 10, y = 100, z = 20 }, hdop = 1.0 },
        }, 1000)
        assert_eq(app.sentinel.intrusionCount, 0)

        -- 2. Foreign domainId across Base+8, Base+9, Base+10, Base+20, Base+30, Base+39 blocks dispatch & counts
        local rogue_channels = { 10008, 10009, 10010, 10020, 10030, 10039 }
        for idx, ch in ipairs(rogue_channels) do
            app.clock_ms = 1000 + idx * 1000
            main_mod.process_event(app, "modem_message", "top", ch, ch, {
                ver = "1.9.5", domainId = "ROGUE_CRAFT", seq = idx, type = "MSG_OPERATOR_CMD", time = app.clock_ms,
                payload = { authority = "GCS_OVERRIDE", command = "LAND" },
            })
        end
        assert_eq(app.sentinel.intrusionCount, 6)
        assert_eq(app.arbiter.authority, "PILOT_PRIMARY") -- Blocked, never reached arbiter

        -- 3. Periodic sustained foreign packets (every 3000ms across >= 30,000ms) trigger HOVER_HOLD failsafe
        for t = 10000, 34000, 3000 do
            app.clock_ms = t
            main_mod.process_event(app, "modem_message", "top", 10039, 10039, {
                ver = "1.9.5", domainId = "ROGUE_CRAFT", seq = t, type = "MSG_TRAJECTORY_SETPOINT", time = t,
                payload = {},
            })
        end
        assert_true(app.sentinel.intrusionFailsafeTriggered)
        assert_not_nil(app.arbiter.emergencyGoal)
        assert_eq(app.arbiter.emergencyGoal.flightMode, "HOVER_HOLD")
        local sp = main_mod.step_20hz_tick(app, 0.05, 34100)
        assert_eq(sp.flightMode, "HOVER_HOLD")

        if fs.exists(lease_path) then fs.delete(lease_path) end
    end)

    it("exempts Base+8 MSG_CALIBRATION_INIT from hangar domainId while blocking non-calibration Base+8 traffic and inactive Zone 3 late ACKs", function()
        local main_mod = require("main")
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })
        local lease_path = "config/test_lease_main_cal_z3.json"
        if fs.exists(lease_path) then fs.delete(lease_path) end

        local app = main_mod.create_app({
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            headless = true,
            clock_ms = 1000,
            leasePath = lease_path,
            system = { hardwareUuid = "AMM-CAL-Z3", primaryModemSide = "top", infraModemSide = "back" },
            safety = { intrusionAlertWindowMs = 30000 },
        }, { top = top_m, back = back_m })
        app.sentinel.status = "ACQUIRED"

        -- [I-3] Hangar station sending MSG_CALIBRATION_INIT on Base+8 across >30s must NOT trigger intrusion or HOVER_HOLD
        for t = 1000, 34000, 2500 do
            app.clock_ms = t
            main_mod.process_event(app, "modem_message", "top", 10008, 10008, {
                ver = "1.9.5", domainId = "HANGAR_ALIGN_01", seq = t, type = "MSG_CALIBRATION_INIT", time = t,
                payload = { craftDomainId = "AIRCRAFT_01", baseChannel = 10000 },
            })
        end
        assert_eq(app.sentinel.intrusionCount, 0)
        assert_false(app.sentinel.intrusionFailsafeTriggered)
        assert_nil(app.arbiter.emergencyGoal)

        -- Non-calibration packet on Base+8 from foreign domain MUST still be blocked & counted
        app.clock_ms = 35000
        main_mod.process_event(app, "modem_message", "top", 10008, 10008, {
            ver = "1.9.5", domainId = "ROGUE_CRAFT", seq = 999, type = "MSG_THRUST_CMD", time = 35000,
            payload = {},
        })
        assert_eq(app.sentinel.intrusionCount, 1)

        -- [C-1] Late own-domain MSG_PAYLOAD_ACK on Base+20 when openPayloadChannels[10020] is nil must be ignored cleanly
        assert_nil(app.net.openPayloadChannels[10020])
        assert_true(top_m.isOpen(10020))
        app.clock_ms = 35100
        main_mod.process_event(app, "modem_message", "top", 10020, 10020, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1000, type = "MSG_PAYLOAD_ACK", time = 35100,
            payload = { checkpointId = "CP_STALE", command = "DROP", status = "DROPPED" },
        })
        assert_nil(app.engine.hook_runner:get_last_payload_ack())

        if fs.exists(lease_path) then fs.delete(lease_path) end
    end)

    it("allows all valid Base+5 and Base+0 infra/C2 packets without false intrusion while blocking Base+0/Base+5 spoofing", function()
        local main_mod = require("main")
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })
        local lease_path = "config/test_lease_main_infra_allow.json"
        if fs.exists(lease_path) then fs.delete(lease_path) end

        local app = main_mod.create_app({
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            headless = true,
            clock_ms = 1000,
            leasePath = lease_path,
            system = { hardwareUuid = "AMM-INFRA-ALLOW", primaryModemSide = "top", infraModemSide = "back" },
            safety = { intrusionAlertWindowMs = 30000 },
        }, { top = top_m, back = back_m })
        app.sentinel.status = "ACQUIRED"

        -- 1. Valid Base+5 facility/pad/runway/dock/GPS responses from foreign domainIds must NOT trigger intrusion
        local base5_valid = {
            { domainId = "GPS_BASE_NET", type = "MSG_GPS_STATUS_RESP", payload = { activeNodes = 4 } },
            { domainId = "GAC_01", type = "MSG_FACILITY_LIST_ACK", payload = { facilities = {} } },
            { domainId = "PAD_01", type = "MSG_PAD_RESERVE_ACK", payload = { status = "RESERVED" } },
            { domainId = "PAD_01", type = "MSG_PAD_TELEMETRY", payload = { deckStatus = "STABLE" } },
            { domainId = "PAD_01", type = "MSG_LANDING_STATUS", payload = { status = "CLEARED" } },
            { domainId = "PAD_01", type = "MSG_LANDING_ACK", payload = { status = "OK" } },
            { domainId = "PAD_01", type = "MSG_PAD_STATUS", payload = { status = "FREE" } },
            { domainId = "RUNWAY_01", type = "MSG_RUNWAY_ACK", payload = { status = "CLEARED" } },
            { domainId = "RUNWAY_01", type = "MSG_ILS_BEACON", payload = { heading = 90 } },
            { domainId = "DOCK_01", type = "MSG_DOCK_ACK", payload = { status = "READY" } },
            { domainId = "DOCK_01", type = "MSG_DOCK_STATUS", payload = { stage = "ALIGNING" } },
            { domainId = "DOCK_01", type = "MSG_DOCKING_STATUS", payload = { stage = "ENGAGED" } },
            { domainId = "DOCK_01", type = "MSG_DOCK_CAPTURE_STAGE", payload = { stage = "CAPTURED" } },
            { domainId = "DOCK_01", type = "MSG_UMBILICAL_STATUS", payload = { connected = true } },
            { domainId = "PAD_01", type = "MSG_TOUCHDOWN_COMPLETE", payload = { facilityId = "PAD_01", craftState = "GROUND_IDLE" } },
        }
        for i, item in ipairs(base5_valid) do
            app.clock_ms = 1000 + i * 2500
            main_mod.process_event(app, "modem_message", "back", 10005, 10005, {
                ver = "1.9.5", domainId = item.domainId, seq = i, type = item.type, time = app.clock_ms,
                payload = item.payload,
            })
        end
        assert_eq(app.sentinel.intrusionCount, 0)
        assert_eq(app.fac.dockingStage, "CAPTURED")

        -- 2. Valid Base+0 packets: GCS_OVERRIDE from non-"GCS*" domainId ("TOWER_CMD"), GCS MSG_MISSION_CMD, MSG_BLOCK_ASSIGN, probes
        app.clock_ms = 40000
        main_mod.process_event(app, "modem_message", "top", 10000, 10000, {
            ver = "1.9.5", domainId = "TOWER_CMD", seq = 50, type = "MSG_OPERATOR_CMD", time = 40000,
            payload = { authority = "GCS_OVERRIDE", command = "HOLD", params = {} },
        })
        assert_eq(app.sentinel.intrusionCount, 0)
        assert_eq(app.arbiter.authority, "GCS_OVERRIDE")
        app.arbiter.authority = "PILOT_PRIMARY"

        main_mod.process_event(app, "modem_message", "top", 10000, 10000, {
            ver = "1.9.5", domainId = "GCS_01", seq = 51, type = "MSG_MISSION_CMD", time = 40100,
            payload = { action = "STOP" },
        })
        assert_eq(app.sentinel.intrusionCount, 0)

        main_mod.process_event(app, "modem_message", "top", 10000, 10000, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 52, type = "MSG_CHANNEL_PROBE", time = 40200,
            payload = { hardwareUuid = "OTHER-02", candidateBase = 10000, bandwidth = 40 },
        })
        assert_eq(app.sentinel.intrusionCount, 0)

        -- 3. Unauthorized spoofing on Base+0 and Base+5 MUST be blocked and counted as intrusion
        main_mod.process_event(app, "modem_message", "top", 10000, 10000, {
            ver = "1.9.5", domainId = "ROGUE_CRAFT", seq = 60, type = "MSG_OPERATOR_CMD", time = 41000,
            payload = { authority = "PILOT_PRIMARY", command = "LAND", params = {} },
        })
        main_mod.process_event(app, "modem_message", "top", 10000, 10000, {
            ver = "1.9.5", domainId = "ROGUE_CRAFT", seq = 61, type = "MSG_TRAJECTORY_SETPOINT", time = 41100,
            payload = {},
        })
        main_mod.process_event(app, "modem_message", "top", 10005, 10005, {
            ver = "1.9.5", domainId = "ROGUE_CRAFT", seq = 62, type = "MSG_THRUST_CMD", time = 41200,
            payload = {},
        })
        assert_eq(app.sentinel.intrusionCount, 3)

        -- 4. Authorized Base+9 MSG_EMERGENCY_OVERRIDE (GCS* / MFD / GCS_OVERRIDE) exempt from intrusion; rogue Base+9 E_STOP still counts
        local prev_count = app.sentinel.intrusionCount
        main_mod.process_event(app, "modem_message", "top", 10009, 10009, {
            ver = "1.9.5", domainId = "GCS_01", seq = 70, type = "MSG_EMERGENCY_OVERRIDE", time = 42000,
            payload = { action = "E_STOP", authKey = "ESTOP_CONFIRM_KEY", source = "GCS" },
        })
        main_mod.process_event(app, "modem_message", "top", 10009, 10009, {
            ver = "1.9.5", domainId = "COCKPIT_MFD", seq = 71, type = "MSG_EMERGENCY_OVERRIDE", time = 42100,
            payload = { action = "E_STOP", authKey = "ESTOP_CONFIRM_KEY", source = "MFD" },
        })
        main_mod.process_event(app, "modem_message", "top", 10009, 10009, {
            ver = "1.9.5", domainId = "TOWER_CMD", seq = 72, type = "MSG_EMERGENCY_OVERRIDE", time = 42200,
            payload = { action = "E_STOP", authKey = "ESTOP_CONFIRM_KEY", source = "PILOT", authority = "GCS_OVERRIDE" },
        })
        assert_eq(app.sentinel.intrusionCount, prev_count)

        main_mod.process_event(app, "modem_message", "top", 10009, 10009, {
            ver = "1.9.5", domainId = "ROGUE_CRAFT", seq = 73, type = "MSG_EMERGENCY_OVERRIDE", time = 42300,
            payload = { action = "E_STOP", authKey = "ESTOP_CONFIRM_KEY", source = "ROGUE" },
        })
        assert_eq(app.sentinel.intrusionCount, prev_count + 1)

        if fs.exists(lease_path) then fs.delete(lease_path) end
    end)

    it("ignores foreign CH 50000 MSG_BLOCK_ASSIGN while ACQUIRED and supports ACQUIRED_OFFLINE cached lease flow", function()
        local main_mod = require("main")
        local channel_sentinel = require("channel_sentinel")
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })
        local lease_path = "config/test_lease_main_offline.json"
        if fs.exists(lease_path) then fs.delete(lease_path) end

        -- Persist cached lease at Base=10040 for AMM-OFFLINE-01
        local seed = channel_sentinel.init({
            system = { domainId = "AIRCRAFT_01", hardwareUuid = "AMM-OFFLINE-01" },
            channels = { baseChannel = 10040 },
        }, 500, lease_path)
        seed.baseChannel = 10040
        seed.lastAcquiredMs = 500
        assert_true(channel_sentinel.save_lease_cache(seed, lease_path))

        local app = main_mod.create_app({
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            headless = true,
            clock_ms = 1000,
            leasePath = lease_path,
            system = { hardwareUuid = "AMM-OFFLINE-01", primaryModemSide = "top", infraModemSide = "back" },
            safety = { gcsBootstrapTimeoutMs = 2000, probeJitterMaxMs = 0, probeRetryCount = 2, channelProbeWaitMs = 200 },
        }, { top = top_m, back = back_m })

        assert_eq(app.sentinel.status, "BOOT_VERIFY")
        assert_eq(app.sentinel.baseChannel, 10040)
        assert_eq(app.net.baseChannel, 10040)
        assert_true(top_m.isOpen(10040))
        assert_true(top_m.isOpen(10079))

        -- Tick 1 emits MSG_BLOCK_REQUEST on 50000 -> GCS_WAIT
        main_mod.step_20hz_tick(app, 0.05, 1000)
        assert_eq(app.sentinel.status, "GCS_WAIT")

        -- GCS timeout at 3000 -> Round 1 probe, Round 2 probe at 3200 -> ACQUIRED_OFFLINE at 3400
        main_mod.step_20hz_tick(app, 0.05, 3000)
        assert_eq(app.sentinel.status, "PROBING")
        main_mod.step_20hz_tick(app, 0.05, 3200)
        assert_eq(app.sentinel.status, "PROBING")
        main_mod.step_20hz_tick(app, 0.05, 3400)
        assert_eq(app.sentinel.status, "ACQUIRED_OFFLINE")
        assert_eq(app.sentinel.offlineWarning, "NO_GCS_LEASE")
        assert_true(string.find(app.arbiter.lastBanner, "NO_GCS_LEASE", 1, true) ~= nil)

        -- Mission with channelBound=true starts cleanly while ACQUIRED_OFFLINE
        assert_true(app.engine:load_table({
            version = "2.0.0",
            missionId = "OFFLINE_SORTIE",
            checkpoints = {
                {
                    checkpointId = "CP_1",
                    action = "ACT_NAV_GOTO_WP",
                    params = { targetPos = { x = 200, z = 200 } },
                    preconditions = { channelBound = true },
                },
            },
        }))
        local ok_start, err_start = app.engine:start("SINGLE", 3450)
        assert_true(ok_start, tostring(err_start))
        local sp_off = main_mod.step_20hz_tick(app, 0.05, 3500)
        assert_true(sp_off.arm)
        assert_true(sp_off.flightActive)

        -- Foreign CH 50000 MSG_BLOCK_ASSIGN (ASSIGNED/DENIED) while ACQUIRED_OFFLINE or ACQUIRED must be ignored
        main_mod.process_event(app, "modem_message", "back", 50000, 50000, {
            ver = "1.9.5", domainId = "GCS_01", seq = 90, type = "MSG_BLOCK_ASSIGN", time = 3600,
            payload = { baseChannel = 10120, status = "ASSIGNED" },
        }, 3600)
        assert_eq(app.sentinel.status, "ACQUIRED_OFFLINE")
        assert_eq(app.sentinel.baseChannel, 10040)

        app.sentinel.status = "ACQUIRED"
        main_mod.process_event(app, "modem_message", "back", 50000, 50000, {
            ver = "1.9.5", domainId = "GCS_01", seq = 91, type = "MSG_BLOCK_ASSIGN", time = 3650,
            payload = { status = "DENIED", reason = "OTHER_CRAFT_DENIED" },
        }, 3650)
        assert_eq(app.sentinel.status, "ACQUIRED")
        assert_false(app.sentinel.locked)
        assert_eq(app.sentinel.baseChannel, 10040)

        if fs.exists(lease_path) then fs.delete(lease_path) end
    end)

    it("persists /.flight_state.json across takeoff/CP/homePad/stop and recovers via RESUME or RTB policy", function()
        local main_mod = require("main")
        local mission_engine = require("mission_engine")
        local snap_path = sdk.temp_path("amm_cold_boot_state.json")
        local mission_path = "missions/test_cold_boot_sortie.json"
        if fs.exists(snap_path) then fs.delete(snap_path) end
        if not fs.exists("missions") then fs.makeDir("missions") end

        local mission_tbl = {
            version = "2.0.0",
            missionId = "test_cold_boot_sortie",
            executionMode = "SINGLE",
            checkpoints = {
                { checkpointId = "CP_1_TKOFF", action = "ACT_TKL_TAKEOFF_VERT", params = { targetAlt = 140, facilityId = "PAD_ALPHA" } },
                { checkpointId = "CP_2_WP", action = "ACT_NAV_GOTO_WP", params = { targetPos = { x = 100, z = 50 }, targetAlt = 140 } },
                { checkpointId = "CP_3_WP", action = "ACT_NAV_GOTO_WP", params = { targetPos = { x = 250, z = 50 }, targetAlt = 140 } },
            },
        }
        local mh = fs.open(mission_path, "w")
        mh.write(textutils.serializeJSON(mission_tbl))
        mh.close()

        local net1 = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local eng1 = mission_engine.new({
            net = net1,
            config = {
                baseChannel = 10000,
                recovery = { enabled = true, persist = true, stateFilePath = snap_path, coldBootPolicy = "RESUME" },
            },
        })
        assert_true(eng1:load_table(mission_tbl))
        assert_true(eng1:start("SINGLE", 1000))
        eng1:set_home("PAD_HOME_01", { x = 10, y = 64, z = -15 }, 1100)
        assert_true(eng1:goto_index(2, 1200))

        local saved = mission_engine.load_flight_state(snap_path)
        assert_not_nil(saved)
        assert_eq(saved.schemaVersion, 1)
        assert_eq(saved.armedState, "AIRBORNE_ACTIVE")
        assert_eq(saved.missionId, "test_cold_boot_sortie")
        assert_eq(saved.currentCpIdx, 2)
        assert_eq(saved.homePadId, "PAD_HOME_01")
        assert_eq(saved.homePos.x, 10)
        assert_false(fs.exists(snap_path .. ".tmp"))

        -- Cold-boot app with RESUME policy restores missionId at currentCpIdx=2
        local m1 = mock.modem({ wireless = true })
        local lease1 = sdk.temp_path("amm_cb_lease1.json")
        local app_resume = main_mod.create_app({
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            headless = true,
            clock_ms = 2000,
            leasePath = lease1,
            recovery = { enabled = true, persist = true, stateFilePath = snap_path, coldBootPolicy = "RESUME" },
        }, m1)
        assert_eq(app_resume.engine.state, "EN_ROUTE")
        assert_eq(app_resume.engine.active_index, 2)
        assert_true(app_resume.arbiter.armed)

        -- Takeoff index 1 skips automatically to CP 2 when recovering airborne
        assert_true(mission_engine.save_flight_state(snap_path, {
            schemaVersion = 1,
            armedState = "AIRBORNE_ACTIVE",
            missionId = "test_cold_boot_sortie",
            currentCpIdx = 1,
            homePadId = "PAD_HOME_01",
            homePos = { x = 10, y = 64, z = -15 },
            savedAtEpoch = 2100,
        }))
        local m2 = mock.modem({ wireless = true })
        local lease2 = sdk.temp_path("amm_cb_lease2.json")
        local app_skip_tk = main_mod.create_app({
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            headless = true,
            clock_ms = 2200,
            leasePath = lease2,
            recovery = { enabled = true, persist = true, stateFilePath = snap_path, coldBootPolicy = "RESUME" },
        }, m2)
        assert_eq(app_skip_tk.engine.active_index, 2)

        -- Cold-boot app with RTB policy sets FAILSAFE_RTH to homePadId/homePos
        local m3 = mock.modem({ wireless = true })
        local lease3 = sdk.temp_path("amm_cb_lease3.json")
        local app_rtb = main_mod.create_app({
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            headless = true,
            clock_ms = 2500,
            leasePath = lease3,
            recovery = { enabled = true, persist = true, stateFilePath = snap_path, coldBootPolicy = "RTB" },
        }, m3)
        local rtb_goal = app_rtb.arbiter:get_effective_goal()
        assert_eq(rtb_goal.flightMode, "FAILSAFE_RTH")
        assert_true(rtb_goal.arm)
        assert_true(rtb_goal.flightActive)
        assert_eq(rtb_goal.designatedFacilityId, "PAD_HOME_01")
        assert_eq(rtb_goal.targetPos.x, 10)

        -- Yield Base+3 while VAS reports AIRBORNE_RECOVERY_HOLD
        app_rtb.arbiter:handle_flight_telemetry({
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1, time = 2600,
            type = "MSG_FLIGHT_TELEMETRY",
            payload = { controlState = "AIRBORNE_RECOVERY_HOLD", activeSource = "FCP", fuel = 0.8 },
        }, 2600)
        local can_tx, yield_reason = app_rtb.arbiter:can_transmit_mfd(2600)
        assert_false(can_tx)
        assert_eq(yield_reason, "ACRO_RECOVERY_HOLD")

        -- Stopping mission persists GROUND_SAFE
        eng1:stop(3000)
        local grounded = mission_engine.load_flight_state(snap_path)
        assert_eq(grounded.armedState, "GROUND_SAFE")

        if fs.exists(snap_path) then fs.delete(snap_path) end
        if fs.exists(mission_path) then fs.delete(mission_path) end
        if fs.exists(lease1) then fs.delete(lease1) end
        if fs.exists(lease2) then fs.delete(lease2) end
        if fs.exists(lease3) then fs.delete(lease3) end
    end)
end)
