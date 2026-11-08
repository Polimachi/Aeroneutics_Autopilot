-- src/0_infra/gcs/main.lua
-- Ground Control Station & RF Channel Manager (CH 50000 / Node 08)
-- UAFS Ecosystem GCS v1.0.0

local channel_manager = require("channel_manager")
local network_manager = require("network_manager")
local c2_commander = require("c2_commander")
local fleet_tracker = require("fleet_tracker")
local ui_renderer = require("ui_renderer")

local main = {}

local function load_config(path)
    local cfg_path = path or "config/gcs_config.json"
    local defaults = {
        system = {
            id = "GCS_01",
            name = "Ground Control Station",
            domainId = "GCS_01",
            loopFrequencyHz = 20,
            uiRefreshRateHz = 5,
            modemSide = "top"
        },
        channels = {
            bootstrapChannel = 50000,
            bandwidth = 40,
            baseChannelMin = 10000,
            baseChannelMax = 49960,
            maxCraftBlocks = 1000
        },
        ui = {
            screenWidth = 51,
            screenHeight = 19,
            telemetryTimeoutSec = 5.0
        }
    }
    if fs and fs.exists and fs.exists(cfg_path) then
        local f = fs.open(cfg_path, "r")
        if f then
            local raw = f.readAll()
            f.close()
            local parsed = textutils.unserializeJSON(raw)
            if type(parsed) == "table" then
                if parsed.system then defaults.system = parsed.system end
                if parsed.channels then defaults.channels = parsed.channels end
                if parsed.ui then defaults.ui = parsed.ui end
            end
        end
    end
    return defaults
end

local function get_time_ms()
    if os.epoch then return os.epoch("utc") end
    return math.floor(os.time() * 1000)
end

function main.create_app(cfg, modem, registry_path)
    local app = {
        config = cfg or load_config(),
        modem = modem,
        registry_path = registry_path or "config/channel_registry.json",
        channel_manager = channel_manager,
        network_manager = network_manager,
        c2_commander = c2_commander,
        fleet_tracker = fleet_tracker,
        ui_renderer = ui_renderer,
        status_msg = "GCS READY",
        running = true
    }

    app.channel_mgr = channel_manager.init(app.config, app.registry_path)
    app.net_mgr = network_manager.init(app.config, app.modem)
    network_manager.open_bootstrap_channel(app.net_mgr)
    app.fleet = fleet_tracker.init(app.config)

    -- Register existing allocations into fleet tracker
    local existing = channel_manager.list_allocations(app.channel_mgr)
    for _, alloc in ipairs(existing) do
        fleet_tracker.register_craft(app.fleet, alloc.domainId, alloc.baseChannel, alloc.blockId)
    end

    local active = fleet_tracker.get_active_craft(app.fleet)
    if active then
        network_manager.set_active_craft(app.net_mgr, active.baseChannel)
    end

    app.buf = ui_renderer.create_buffer(51, 19)
    return setmetatable(app, { __index = main })
end

function main:process_modem_message(channel, replyChannel, raw_msg)
    local msg, err = network_manager.parse_envelope(raw_msg)
    if not msg then return false, err end

    if channel == self.config.channels.bootstrapChannel then
        if msg.type == "MSG_BLOCK_REQUEST" then
            local p = msg.payload
            local res = channel_manager.allocate_block(self.channel_mgr, p.domainId, p.hardwareUuid, p.requestedBandwidth)
            channel_manager.save_registry(self.registry_path, self.channel_mgr)
            if res.status == "ASSIGNED" then
                fleet_tracker.register_craft(self.fleet, p.domainId, res.baseChannel, res.blockId)
                if not self.net_mgr.active_base then
                    network_manager.set_active_craft(self.net_mgr, res.baseChannel)
                end
                self.status_msg = string.format("ASSIGNED: %s -> CH %d", p.domainId, res.baseChannel)
            else
                self.status_msg = string.format("DENIED: %s (%s)", p.domainId, tostring(res.reason))
            end
            local reply_ch = replyChannel or self.config.channels.bootstrapChannel
            network_manager.send_block_assign(self.net_mgr, reply_ch, res)
            return true
        end
    end

    local cur_telem_ch = self.net_mgr.active_base and (self.net_mgr.active_base + 3)
    if cur_telem_ch and channel == cur_telem_ch and msg.type == "MSG_MFD_STATE" then
        fleet_tracker.update_telemetry(self.fleet, msg.domainId, msg.payload, get_time_ms())
        return true
    end

    return false
end

local function handle_c2_key(app, active, lower_char)
    if lower_char == "a" then
        local cmd = c2_commander.create_operator_cmd("ARM", active.domainId)
        network_manager.send_c2_command(app.net_mgr, active.baseChannel, cmd)
        app.status_msg = "CMD: ARM -> " .. active.domainId
    elseif lower_char == "t" then
        local cmd = c2_commander.create_operator_cmd("TAKEOFF", active.domainId, { altitude = 80.0 })
        network_manager.send_c2_command(app.net_mgr, active.baseChannel, cmd)
        app.status_msg = "CMD: TAKEOFF -> " .. active.domainId
    elseif lower_char == "h" then
        local cmd = c2_commander.create_operator_cmd("HOLD", active.domainId)
        network_manager.send_c2_command(app.net_mgr, active.baseChannel, cmd)
        app.status_msg = "CMD: HOLD -> " .. active.domainId
    elseif lower_char == "r" then
        local cmd = c2_commander.create_operator_cmd("RTH", active.domainId)
        network_manager.send_c2_command(app.net_mgr, active.baseChannel, cmd)
        app.status_msg = "CMD: RTH -> " .. active.domainId
    elseif lower_char == "l" then
        local cmd = c2_commander.create_operator_cmd("LAND", active.domainId)
        network_manager.send_c2_command(app.net_mgr, active.baseChannel, cmd)
        app.status_msg = "CMD: LAND -> " .. active.domainId
    elseif lower_char == "x" then
        local estop = c2_commander.create_emergency_estop(active.domainId, "OPERATOR_HARD_STOP")
        network_manager.send_emergency_override(app.net_mgr, active.baseChannel, estop)
        app.status_msg = "EMERGENCY E-STOP SENT -> " .. active.domainId
    end
end

function main:process_key(key_code, char_str)
    local lower_char = char_str and string.lower(char_str)
    if lower_char == "q" then
        self.running = false
        return
    end

    if (key_code and keys and key_code == keys.tab) or lower_char == " " or lower_char == "\t" then
        local next_c = fleet_tracker.select_next(self.fleet)
        if next_c then
            network_manager.set_active_craft(self.net_mgr, next_c.baseChannel)
            self.status_msg = "TARGET: " .. next_c.domainId
        end
        return
    end

    local active = fleet_tracker.get_active_craft(self.fleet)
    if active and lower_char then
        handle_c2_key(self, active, lower_char)
    end
end

function main:render(term_obj)
    local now_ms = get_time_ms()
    fleet_tracker.prune_stale(self.fleet, now_ms)
    local active = fleet_tracker.get_active_craft(self.fleet)
    local summary = fleet_tracker.get_fleet_summary(self.fleet)
    ui_renderer.render_screen(self.buf, active, summary, self.status_msg)
    ui_renderer.flush_buffer(self.buf, term_obj or term)
end

local function run_event_loop(app)
    while app.running do
        local ev, p1, p2, p3, p4, p5 = os.pullEventRaw()
        if ev == "terminate" then
            app.running = false
        elseif ev == "modem_message" then
            app:process_modem_message(p2, p3, p4)
        elseif ev == "key" then
            app:process_key(p1, nil)
        elseif ev == "char" then
            app:process_key(nil, p1)
        end
    end
end

local function run_ui_loop(app)
    local interval = 1.0 / (app.config.system.uiRefreshRateHz or 5)
    while app.running do
        app:render(term)
        sleep(interval)
    end
end

function main.main_loop(config_path)
    local cfg = load_config(config_path)
    local modem = (cfg.system and cfg.system.modemSide and peripheral.wrap(cfg.system.modemSide))
        or peripheral.find("modem")
    local app = main.create_app(cfg, modem)

    term.clear()
    parallel.waitForAny(
        function() run_event_loop(app) end,
        function() run_ui_loop(app) end
    )
    term.clear()
    term.setCursorPos(1, 1)
    print("GCS terminated.")
end

if not ... or ... == "--daemon" or ... == "-d" then
    pcall(main.main_loop, ...)
end

return main
