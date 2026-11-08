-- src/3_planning/amm/main.lua
-- AMM: Aircraft Mission Manager & Cockpit MFD Terminal
local waypoint_queue = require("waypoint_queue")
local network_manager = require("network_manager")
local c2_arbiter = require("c2_arbiter")
local input_handler = require("input_handler")
local ui_renderer = require("ui_renderer")

local function load_config(path)
    local cfg_path = path or "config/amm_config.json"
    local defaults = {
        domainId = "AIRCRAFT_01",
        baseChannel = 10000,
        defaultAlt = 150.0,
        defaultSpeed = 18.0,
        arrivalRadius = 15.0,
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

local function execute_cli_command(app, cmd)
    if not cmd or cmd.type ~= "COMMAND" then return end
    local name = cmd.name
    local a = cmd.args
    if name == "add" then
        app.queue:add(a[1], a[2], a[3], a[4], a[5])
        app.arbiter.lastBanner = "WP ADDED"
    elseif name == "del" then
        app.queue:del(a[1])
        app.arbiter.lastBanner = "WP DELETED"
    elseif name == "clear" then
        app.queue:clear()
        app.arbiter.lastBanner = "QUEUE CLEARED"
    elseif name == "goto" then
        app.queue:set_active_index(a[1])
        local active_wp = app.queue:get_active()
        if active_wp then
            app.arbiter:handle_pilot_action("RESUME")
        end
    elseif name == "pause" then
        app.arbiter:handle_pilot_action("PAUSE")
    elseif name == "resume" then
        app.arbiter:handle_pilot_action("RESUME")
    elseif name == "save" and a[1] then
        app.queue:save("missions/" .. a[1] .. ".json")
        app.arbiter.lastBanner = "SAVED: " .. a[1]
    elseif name == "load" and a[1] then
        local ok, err = app.queue:load("missions/" .. a[1] .. ".json")
        app.arbiter.lastBanner = ok and ("LOADED: " .. a[1]) or ("LOAD FAIL: " .. tostring(err))
    elseif name == "alt" and a[1] then
        app.queue.defaultAlt = tonumber(a[1]) or app.queue.defaultAlt
        app.arbiter.lastBanner = "ALT SET: " .. tostring(app.queue.defaultAlt)
    elseif name == "spd" and a[1] then
        app.queue.defaultSpeed = tonumber(a[1]) or app.queue.defaultSpeed
        app.arbiter.lastBanner = "SPD SET: " .. tostring(app.queue.defaultSpeed)
    elseif name == "rad" and a[1] then
        app.queue.arrivalRadius = tonumber(a[1]) or app.queue.arrivalRadius
        app.arbiter.lastBanner = "RAD SET: " .. tostring(app.queue.arrivalRadius)
    end
end

local function process_event(app, ev, p1, p2, p3, p4, p5)
    if ev == "timer" and p1 == app.render_timer then
        app.render_timer = os.startTimer(0.2)
        local app_state = {
            domainId = app.config.domainId,
            authority = app.arbiter.authority,
            banner = app.arbiter.lastBanner,
            input_mode = app.input.mode,
            input_buffer = app.input.buffer,
        }
        ui_renderer.render_screen(app.screen_buf, app.arbiter.latest_mfd_payload, app.queue, app_state)
        ui_renderer.flush_buffer(app.screen_buf, term)
    elseif ev == "modem_message" then
        local chan, msg = p2, p4
        local ok, pkt = app.net:decode_envelope(msg)
        if ok and pkt then
            if chan == app.config.baseChannel + 3 then
                app.arbiter:handle_mfd_state(pkt)
            elseif chan == app.config.baseChannel + 0 then
                app.arbiter:handle_gcs_packet(pkt)
            end
        end
    elseif ev == "char" then
        local act = app.input:handle_char(p1)
        if act and act.action then
            app.arbiter:handle_pilot_action(act.action)
        end
    elseif ev == "key" then
        local cmd = app.input:handle_key(p1)
        if cmd then execute_cli_command(app, cmd) end
    end
end

local function main_loop(config_path)
    local cfg = load_config(config_path)
    local queue = waypoint_queue.new(cfg)
    local net = network_manager.new(cfg)
    local arbiter = c2_arbiter.new(queue, net, cfg)
    local input = input_handler.new()
    local screen_buf = ui_renderer.create_buffer(51, 19)

    local modem = peripheral.find("modem")
    if modem then net:bind_modem(modem) end

    local app = {
        config = cfg, queue = queue, net = net,
        arbiter = arbiter, input = input,
        screen_buf = screen_buf,
        render_timer = os.startTimer(0.2),
        running = true,
    }

    while app.running do
        local ev, p1, p2, p3, p4, p5 = os.pullEventRaw()
        if ev == "terminate" then
            app.running = false
        else
            process_event(app, ev, p1, p2, p3, p4, p5)
        end
    end
end

if not ... or type(...) == "string" then
    pcall(main_loop, ...)
end

return {
    load_config = load_config,
    execute_cli_command = execute_cli_command,
    process_event = process_event,
    main_loop = main_loop,
}
