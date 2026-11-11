-- src/3_planning/amm/main.lua
-- AMM: Aircraft Mission Manager & Cockpit MFD Terminal
local waypoint_queue = require("waypoint_queue")
local network_manager = require("network_manager")
local c2_arbiter = require("c2_arbiter")
local input_handler = require("input_handler")
local ui_renderer = require("ui_renderer")
local mission_engine = require("mission_engine")

local function load_config(path)
    local cfg_path = path or "config/amm_config.json"
    local defaults = {
        domainId = "AIRCRAFT_01",
        baseChannel = 10000,
        defaultAlt = 150.0,
        defaultSpeed = 18.0,
        arrivalRadius = 15.0,
        headless = false,
        autoStartMission = nil,
        autoExecutionMode = nil,
        autoRunDroppedFile = false,
    }
    if fs and fs.exists and fs.exists(cfg_path) then
        local f = fs.open(cfg_path, "r")
        if f then
            local raw = f.readAll()
            f.close()
            local parsed = textutils.unserializeJSON(raw)
            if type(parsed) == "table" then
                for k, v in pairs(parsed) do defaults[k] = v end
            end
        end
    end
    return defaults
end

local function get_now_ms(app)
    return (app and app.now_ms) or (os.epoch and os.epoch("utc")) or (os.time() * 1000)
end

local function is_config_path(str)
    if type(str) ~= "string" or str == "" then return false end
    if string.find(str, "amm_config%.json") then return true end
    if string.match(str, "^/?config/") then return true end
    return false
end

local function parse_boot_args(arg1, arg2, arg3)
    if is_config_path(arg1) then
        return arg1, arg2, arg3
    else
        return nil, arg1, arg2
    end
end

local function queue_to_mission_table(q)
    local cps = {}
    for i, it in ipairs(q.items or {}) do
        table.insert(cps, {
            checkpointId = string.format("WP_%02d", i),
            action = "FLY_TO",
            params = {
                targetPos = { x = it.x, z = it.z },
                targetAlt = it.alt,
                cruiseSpeed = it.speed,
                acceptanceRadius = q.arrivalRadius or 15.0,
            },
        })
    end
    return {
        missionId = "MANUAL_QUEUE",
        executionMode = "SINGLE",
        checkpoints = cps,
    }
end

local function normalize_execution_mode(mode_str)
    local m = string.upper(tostring(mode_str or "SINGLE"))
    if m == "LOOP" or m == "REPEAT" then
        return "REPEAT"
    end
    return "SINGLE"
end

local function try_auto_start_mission(engine, auto_spec, now_ms, cfg, arbiter, mode_arg)
    if not auto_spec or auto_spec == "" or not engine then
        return false, "NO_MISSION_SPEC"
    end
    local t_ms = now_ms or ((os.epoch and os.epoch("utc")) or (os.time() * 1000))
    local ok, err, detail
    if type(auto_spec) == "table" then
        local vok, verr, vdetail = mission_engine.validate_mission_table(auto_spec)
        if not vok then
            if arbiter then arbiter.lastBanner = "BOOT FAIL: " .. tostring(vdetail or verr) end
            return false, verr, vdetail
        end
        ok, err = engine:load_table(auto_spec)
        detail = err
    elseif type(auto_spec) == "string" then
        local resolved, res_err = mission_engine.resolve_path(auto_spec)
        if not resolved then
            if arbiter then arbiter.lastBanner = "BOOT FAIL: " .. tostring(res_err) end
            return false, res_err, nil
        end
        ok, err, detail = engine:load(resolved)
    end
    if not ok then
        if arbiter then arbiter.lastBanner = "BOOT FAIL: " .. tostring(detail or err) end
        return false, err, detail
    end
    local raw_mode = mode_arg or (cfg and cfg.autoExecutionMode) or engine.executionMode or "SINGLE"
    local mode = normalize_execution_mode(raw_mode)
    engine.executionMode = mode
    local sok, serr = engine:start(mode, t_ms)
    if not sok then
        if arbiter then arbiter.lastBanner = "BOOT FAIL: " .. tostring(serr) end
        return false, serr, nil
    end
    return true
end

local function save_dropped_file(safe_name, content)
    if not fs.exists("missions") then fs.makeDir("missions") end
    local dest = "missions/" .. safe_name
    local h = fs.open(dest, "w")
    if not h then return false end
    h.write(content)
    h.close()
    return true, dest
end

local function handle_file_transfer(app, transferred, now_ms)
    if not transferred or not transferred.getFiles then return false, "NO_FILES" end
    local files = transferred:getFiles()
    if not files or #files == 0 then return false, "EMPTY_TRANSFER" end
    local file_obj = files[1]
    local raw_name = file_obj.getName and file_obj:getName()
    local safe_name = fs.getName(raw_name or "")
    if not safe_name or safe_name == "" or string.find(safe_name, "%.%.") or not string.match(safe_name, "%.json$") then
        if file_obj.close then file_obj:close() end
        if app.arbiter then app.arbiter.lastBanner = "DROP FAIL: INVALID_FILENAME" end
        return false, "INVALID_FILENAME"
    end
    local body = file_obj.readAll and file_obj:readAll()
    if file_obj.close then file_obj:close() end
    local parsed = textutils.unserializeJSON(body)
    if type(parsed) ~= "table" then
        if app.arbiter then app.arbiter.lastBanner = "DROP FAIL: MALFORMED_JSON" end
        return false, "MALFORMED_JSON"
    end
    local vok, verr, vdetail = mission_engine.validate_mission_table(parsed)
    if not vok then
        local d = vdetail or verr
        if app.arbiter then app.arbiter.lastBanner = "DROP FAIL: " .. tostring(d) end
        return false, verr, vdetail
    end
    local saved, dest = save_dropped_file(safe_name, body)
    if not saved then
        if app.arbiter then app.arbiter.lastBanner = "DROP FAIL: WRITE_ERROR" end
        return false, "WRITE_ERROR"
    end
    if app.engine and (app.engine.state == "EN_ROUTE" or app.engine.state == "SUSPENDED") then
        local stem = string.gsub(safe_name, "%.json$", "")
        if app.arbiter then app.arbiter.lastBanner = "DROP SAVED: " .. safe_name .. " (USE 'run " .. stem .. "')" end
        return true
    end
    local lok, lerr, ldetail = app.engine:load(dest)
    if not lok then
        local d = ldetail or lerr
        if app.arbiter then app.arbiter.lastBanner = "DROP FAIL: " .. tostring(d) end
        return false, lerr, ldetail
    end
    if app.config and app.config.autoRunDroppedFile == true then
        local mode = normalize_execution_mode((app.config and app.config.autoExecutionMode) or app.engine.executionMode)
        app.engine:start(mode, now_ms)
        if app.arbiter then app.arbiter.lastBanner = "DROP RUNNING: " .. safe_name end
    else
        if app.arbiter then app.arbiter.lastBanner = "DROP LOADED: " .. safe_name end
    end
    return true
end

local function handle_cli_run(app, a, now_ms)
    local spec, mode_raw
    if a[1] == "loop" or a[1] == "repeat" or a[1] == "single" then
        mode_raw = a[1]
    else
        spec = a[1]
        mode_raw = a[2]
    end
    if spec then
        local resolved, res_err = mission_engine.resolve_path(spec)
        if not resolved then
            app.arbiter.lastBanner = "RUN FAIL: " .. tostring(res_err)
            return
        end
        local ok, err, detail = app.engine:load(resolved)
        if not ok then
            app.arbiter.lastBanner = "RUN FAIL: " .. tostring(detail or err)
            return
        end
    elseif app.engine:count() == 0 and app.queue and app.queue:count() > 0 then
        local tbl = queue_to_mission_table(app.queue)
        local ok, err = app.engine:load_table(tbl)
        if not ok then
            app.arbiter.lastBanner = "RUN FAIL: " .. tostring(err)
            return
        end
    end
    if app.engine:count() == 0 then
        app.arbiter.lastBanner = "RUN FAIL: EMPTY"
        return
    end
    local mode = normalize_execution_mode(mode_raw or app.engine.executionMode)
    local sok, serr = app.engine:start(mode, now_ms)
    if not sok then
        app.arbiter.lastBanner = "RUN FAIL: " .. tostring(serr)
        return
    end
    app.arbiter.lastBanner = "RUNNING: " .. tostring(app.engine.missionId or "MANUAL")
end

local function handle_cli_load(app, a, _now_ms)
    if not a[1] then
        app.arbiter.lastBanner = "LOAD FAIL: NO SPEC"
        return
    end
    local resolved, res_err = mission_engine.resolve_path(a[1])
    if not resolved then
        app.arbiter.lastBanner = "LOAD FAIL: " .. tostring(res_err)
        return
    end
    local ok, err, detail
    if app.engine then
        ok, err, detail = app.engine:load(resolved)
    elseif app.queue then
        ok, err = app.queue:load(resolved)
    end
    if ok then
        app.arbiter.lastBanner = "LOADED: " .. tostring(a[1])
    else
        app.arbiter.lastBanner = "LOAD FAIL: " .. tostring(detail or err)
    end
end

local function handle_cli_files(app, _a, _now_ms)
    local file_list = mission_engine.list_mission_files()
    if #file_list == 0 then
        app.arbiter.lastBanner = "NO MISSION FILES"
    else
        app.arbiter.lastBanner = "FILES: " .. table.concat(file_list, " ")
    end
end

local function handle_cli_stop(app, _a, now_ms)
    if app.engine then app.engine:stop(now_ms) end
    if app.queue then app.queue.state = "SUSPENDED" end
    app.arbiter.lastBanner = "MISSION STOPPED"
end

local function handle_cli_next(app, _a, now_ms)
    if app.engine and app.engine:count() > 0 then
        local ok, status = app.engine:skip_next(now_ms)
        if ok then
            if status == "COMPLETED" then
                app.arbiter.lastBanner = "MISSION COMPLETE"
            else
                local cp = app.engine:get_active()
                local cpid = (cp and cp.checkpointId) or tostring(app.engine.active_index)
                app.arbiter.lastBanner = "NEXT CP: " .. cpid
            end
        else
            app.arbiter.lastBanner = "NEXT FAIL: " .. tostring(status)
        end
    elseif app.queue and app.queue:count() > 0 then
        local next_idx = app.queue.active_index + 1
        if next_idx <= app.queue:count() then
            app.queue:set_active_index(next_idx)
            app.arbiter.lastBanner = "NEXT WP: " .. tostring(next_idx)
        else
            app.arbiter.lastBanner = "QUEUE END"
        end
    else
        app.arbiter.lastBanner = "NEXT FAIL: EMPTY"
    end
end

local MISSION_SUBCOMMANDS = {
    run = function(app, subargs, now_ms)
        handle_cli_run(app, subargs, now_ms)
    end,
    load = function(app, subargs, now_ms)
        handle_cli_load(app, subargs, now_ms)
    end,
    list = function(app, subargs, now_ms)
        handle_cli_files(app, subargs, now_ms)
    end,
    files = function(app, subargs, now_ms)
        handle_cli_files(app, subargs, now_ms)
    end,
    stop = function(app, subargs, now_ms)
        handle_cli_stop(app, subargs, now_ms)
    end,
    next = function(app, subargs, now_ms)
        handle_cli_next(app, subargs, now_ms)
    end,
    status = function(app, _subargs, _now_ms)
        local st = (app.engine and app.engine.state) or (app.queue and app.queue.state) or "IDLE"
        local mid = (app.engine and app.engine.missionId) or "NONE"
        local idx = (app.engine and app.engine.active_index) or (app.queue and app.queue.active_index) or 1
        local tot = (app.engine and app.engine:count()) or (app.queue and app.queue:count()) or 0
        app.arbiter.lastBanner = string.format("MSN: %s [%s] %d/%d", mid, st, idx, tot)
    end,
}

local function handle_cli_mission(app, a, now_ms)
    local subcmd = string.lower(a[1] or "status")
    local subargs = {}
    for i = 2, #a do
        table.insert(subargs, a[i])
    end
    local fn = MISSION_SUBCOMMANDS[subcmd]
    if fn then
        fn(app, subargs, now_ms)
    else
        app.arbiter.lastBanner = "UNKNOWN SUBCOMMAND: " .. tostring(subcmd)
    end
end

local function handle_cli_save(app, a, _now_ms)
    if not a[1] then return end
    local path = a[1]
    if not string.find(path, "/") then
        path = "missions/" .. path
    end
    if not string.match(path, "%.json$") then
        path = path .. ".json"
    end
    local ok, err
    if app.engine and app.engine:count() > 0 then
        ok, err = app.engine:save(path)
    elseif app.queue then
        ok, err = app.queue:save(path)
    end
    app.arbiter.lastBanner = ok and ("SAVED: " .. a[1]) or ("SAVE FAIL: " .. tostring(err))
end

local CLI_HANDLERS = {
    run = handle_cli_run,
    load = handle_cli_load,
    files = handle_cli_files,
    stop = handle_cli_stop,
    next = handle_cli_next,
    mission = handle_cli_mission,
    add = function(app, a, _now_ms)
        app.queue:add(a[1], a[2], a[3], a[4], a[5])
        app.arbiter.lastBanner = "WP ADDED"
    end,
    del = function(app, a, _now_ms)
        app.queue:del(a[1])
        app.arbiter.lastBanner = "WP DELETED"
    end,
    clear = function(app, _a, now_ms)
        if app.queue then app.queue:clear() end
        if app.engine then
            app.engine:stop(now_ms)
            app.engine.checkpoints = {}
            app.engine.state = "IDLE"
            app.engine.active_index = 1
        end
        app.arbiter.lastBanner = "QUEUE CLEARED"
    end,
    ["goto"] = function(app, a, now_ms)
        app.queue:set_active_index(a[1])
        local idx = tonumber(a[1])
        if app.engine and idx then app.engine:goto_index(idx, now_ms) end
        local active_wp = app.queue:get_active()
        if active_wp then
            app.arbiter:handle_pilot_action("RESUME", {}, now_ms)
        end
    end,
    pause = function(app, _a, now_ms)
        app.arbiter:handle_pilot_action("PAUSE", {}, now_ms)
    end,
    resume = function(app, _a, now_ms)
        app.arbiter:handle_pilot_action("RESUME", {}, now_ms)
    end,
    save = handle_cli_save,
    alt = function(app, a, _now_ms)
        if a[1] then
            app.queue.defaultAlt = tonumber(a[1]) or app.queue.defaultAlt
            app.arbiter.lastBanner = "ALT SET: " .. tostring(app.queue.defaultAlt)
        end
    end,
    spd = function(app, a, _now_ms)
        if a[1] then
            app.queue.defaultSpeed = tonumber(a[1]) or app.queue.defaultSpeed
            app.arbiter.lastBanner = "SPD SET: " .. tostring(app.queue.defaultSpeed)
        end
    end,
    rad = function(app, a, _now_ms)
        if a[1] then
            app.queue.arrivalRadius = tonumber(a[1]) or app.queue.arrivalRadius
            app.arbiter.lastBanner = "RAD SET: " .. tostring(app.queue.arrivalRadius)
        end
    end,
}

local function execute_cli_command(app, cmd, now_ms)
    if not cmd or cmd.type ~= "COMMAND" then return end
    local t_ms = now_ms or get_now_ms(app)
    if app.arbiter then
        app.arbiter.authority = "PILOT_PRIMARY"
    end
    if app.engine then
        app.engine.authority = "PILOT_PRIMARY"
    end
    local handler = CLI_HANDLERS[cmd.name]
    if handler then
        handler(app, cmd.args or {}, t_ms)
    else
        if app.arbiter then
            app.arbiter.lastBanner = "UNKNOWN CMD: " .. tostring(cmd.name)
        end
    end
end

local function handle_timer_event(app, timer_id, now_ms)
    if timer_id ~= app.render_timer then return end
    app.render_timer = os.startTimer(0.2)
    if app.engine then
        app.engine:tick(now_ms)
    end
    if not (app.config and app.config.headless == true) and app.screen_buf then
        local app_state = {
            domainId = app.config.domainId,
            authority = app.arbiter.authority,
            banner = app.arbiter.lastBanner,
            input_mode = app.input.mode,
            input_buffer = app.input.buffer,
            now_ms = now_ms,
        }
        local src_data = (app.engine and app.engine:count() > 0) and app.engine or app.queue
        ui_renderer.render_screen(app.screen_buf, app.arbiter.latest_mfd_payload, src_data, app_state)
        ui_renderer.flush_buffer(app.screen_buf, app.term_obj or term)
    end
end

local function handle_modem_message(app, chan, raw_msg, now_ms)
    if not app.net or not app.net.decode_envelope then return end
    local ok, pkt = app.net:decode_envelope(raw_msg)
    if not ok or not pkt then return end
    local base = (app.config and app.config.baseChannel) or (app.net and app.net.baseChannel) or 10000
    if chan == base + 3 then
        if app.arbiter and app.arbiter.handle_mfd_state then
            app.arbiter:handle_mfd_state(pkt, now_ms)
        end
    elseif chan == base + 0 then
        if app.arbiter and app.arbiter.handle_gcs_packet then
            app.arbiter:handle_gcs_packet(pkt, now_ms)
        end
    elseif app.net.is_payload_channel and app.net:is_payload_channel(chan) and app.engine then
        app.engine:on_payload_ack(pkt, chan, now_ms)
    end
end

local function process_event(app, ev, p1, p2, p3, p4, p5)
    local now_ms = get_now_ms(app)
    if ev == "timer" then
        handle_timer_event(app, p1, now_ms)
    elseif ev == "modem_message" then
        handle_modem_message(app, p2, p4, now_ms)
    elseif ev == "char" then
        local act = app.input:handle_char(p1)
        if act and act.action then
            app.arbiter:handle_pilot_action(act.action, act.params or {}, now_ms)
        end
    elseif ev == "key" then
        local cmd = app.input:handle_key(p1)
        if cmd then
            execute_cli_command(app, cmd, now_ms)
        end
    elseif ev == "paste" then
        if app.input and app.input.handle_paste then
            app.input:handle_paste(p1)
        end
    elseif ev == "file_transfer" then
        handle_file_transfer(app, p1, now_ms)
    end
end

local function shutdown_app(app)
    if not app then return end
    if app.engine then
        local now_ms = get_now_ms(app)
        app.engine:stop(now_ms)
        if app.engine.hook_runner then
            app.engine.hook_runner:cleanup()
        end
    end
    app.running = false
end

local function main_loop(...)
    local arg1, arg2, arg3 = ...
    local boot_cfg, boot_spec, boot_mode = parse_boot_args(arg1, arg2, arg3)
    local cfg = load_config(boot_cfg)
    local queue = waypoint_queue.new(cfg)
    local net = network_manager.new(cfg)
    local engine = mission_engine.new({
        net = net,
        config = cfg,
        redstone = redstone,
        colors = colors,
    })
    local arbiter = c2_arbiter.new(queue, net, cfg, engine)
    local input = input_handler.new()
    local screen_buf = (not cfg.headless) and ui_renderer.create_buffer(51, 19) or nil

    local modem = peripheral and peripheral.find and peripheral.find("modem")
    if modem then net:bind_modem(modem) end

    local now_ms = (os.epoch and os.epoch("utc")) or (os.time() * 1000)
    local start_spec = boot_spec or cfg.autoStartMission
    local start_mode = boot_mode or cfg.autoExecutionMode
    if start_spec then
        try_auto_start_mission(engine, start_spec, now_ms, cfg, arbiter, start_mode)
    end

    local app = {
        config = cfg,
        queue = queue,
        net = net,
        engine = engine,
        arbiter = arbiter,
        input = input,
        screen_buf = screen_buf,
        render_timer = os.startTimer(0.2),
        running = true,
    }

    while app.running do
        local ev, p1, p2, p3, p4, p5 = os.pullEventRaw()
        if ev == "terminate" then
            shutdown_app(app)
        else
            process_event(app, ev, p1, p2, p3, p4, p5)
        end
    end
    shutdown_app(app)
end

if _G.describe == nil and (...) ~= "main" and (not ... or type(...) == "string") then
    pcall(main_loop, ...)
end

return {
    load_config = load_config,
    execute_cli_command = execute_cli_command,
    process_event = process_event,
    main_loop = main_loop,
    try_auto_start_mission = try_auto_start_mission,
    shutdown_app = shutdown_app,
    handle_file_transfer = handle_file_transfer,
    parse_boot_args = parse_boot_args,
}
