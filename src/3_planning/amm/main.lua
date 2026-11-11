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

local CLI_HANDLERS = {
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
    save = function(app, a, _now_ms)
        if not a[1] then return end
        local path = "missions/" .. a[1] .. ".json"
        local ok, err
        if app.engine and app.engine:count() > 0 then
            ok, err = app.engine:save(path)
        elseif app.queue then
            ok, err = app.queue:save(path)
        end
        app.arbiter.lastBanner = ok and ("SAVED: " .. a[1]) or ("SAVE FAIL: " .. tostring(err))
    end,
    load = function(app, a, _now_ms)
        if not a[1] then return end
        local path = "missions/" .. a[1] .. ".json"
        local ok, err
        if app.engine then
            ok, err = app.engine:load(path)
        elseif app.queue then
            ok, err = app.queue:load(path)
        end
        app.arbiter.lastBanner = ok and ("LOADED: " .. a[1]) or ("LOAD FAIL: " .. tostring(err))
    end,
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
    local handler = CLI_HANDLERS[cmd.name]
    if handler then
        local t_ms = now_ms or get_now_ms(app)
        handler(app, cmd.args or {}, t_ms)
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
        }
        ui_renderer.render_screen(app.screen_buf, app.arbiter.latest_mfd_payload, app.queue, app_state)
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
    end
end

local function try_auto_start_mission(engine, auto_spec, now_ms, cfg)
    if not auto_spec or auto_spec == "" or not engine then return end
    local ok = false
    if type(auto_spec) == "table" then
        ok = engine:load_table(auto_spec)
    elseif type(auto_spec) == "string" then
        if fs and fs.exists and fs.exists(auto_spec) then
            ok = engine:load(auto_spec)
        else
            local p = auto_spec
            if not string.match(p, "^missions/") and not string.match(p, "^/missions/") then
                p = "missions/" .. p
            end
            if not string.match(p, "%.json$") then
                p = p .. ".json"
            end
            ok = engine:load(p)
        end
    end
    if ok then
        local mode = (cfg and cfg.autoExecutionMode) or engine.executionMode or "SINGLE"
        engine:start(mode, now_ms)
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

local function main_loop(config_path)
    local cfg = load_config(config_path)
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
    try_auto_start_mission(engine, cfg.autoStartMission, now_ms, cfg)

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
}
