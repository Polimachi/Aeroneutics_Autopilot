-- src/0_infra/pocket_pda/main.lua
-- Pocket PDA 26x20 Remote C2, Telemetry HUD, Alignment & FDR Console Entrypoint (ICD v1.9.5)

if package and package.path and not string.find(package.path, "modules/%?%.lua", 1, true) then
    package.path = "modules/?.lua;/modules/?.lua;./modules/?.lua;" .. package.path
end

local pda_network = require("pda_network")
local telemetry_hud_state = require("telemetry_hud_state")
local emergency_c2_controller = require("emergency_c2_controller")
local remote_link_controller = require("remote_link_controller")
local pocket_tui = require("pocket_tui")

local main = {}

local TAB_BY_KEY = { ["1"] = "HUD", ["2"] = "ALIGN", ["3"] = "FDR" }
local GLOBAL_C2_KEYS = { h = "HOLD", r = "RTB", l = "LAND_NEAREST" }
local ALIGN_ACTION_KEYS = {
    b = "BIND_SESSION",
    g = "START_PULSE",
    p = "PAUSE_SESSION",
    t = "RETRY_STEP",
    y = "APPROVE_SYNC",
    a = "ABORT_SESSION",
    k = "RELEASE_SESSION",
}
local FDR_SIMPLE_KEYS = {
    d = "DUMP_NOW",
    u = "EXPORT_NOW",
    s = "ROLLOVER_NOW",
    c = "CLEAR_BUFFER",
}

local function get_time_ms(now_ms)
    if type(now_ms) == "number" then return now_ms end
    if os and os.epoch then return os.epoch("utc") end
    if os and os.time then return math.floor(os.time() * 1000) end
    return 0
end

local function default_config()
    return {
        schemaVersion = "1.0.0",
        system = {
            id = "PDA_01",
            domainId = "POCKET_PDA_01",
            modemSide = "back",
            loopFrequencyHz = 20,
            uiRefreshRateHz = 5,
        },
        defaults = {
            aircraftIndexN = 1,
            targetDomainId = "AIRCRAFT_01",
            hangarBayId = 1,
            fdrBoundIndexN = 1,
        },
        channels = {
            gcsBootstrapChannel = 50000,
            missionAckChannel = 50004,
            aircraftBaseMin = 10000,
            aircraftBandwidth = 40,
            maxAircraft = 1000,
            hangarBaseMin = 101,
            hangarBandwidth = 10,
            maxHangarBays = 10,
        },
        linkQuality = {
            telemetryTimeoutMs = 2000,
            nodeStaleMs = 3000,
            strongMaxDistM = 80.0,
            goodMaxDistM = 200.0,
        },
        ui = {
            screenWidth = 26,
            screenHeight = 20,
        },
    }
end

local function merge_tables(dst, src)
    if type(src) ~= "table" then return dst end
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            merge_tables(dst[k], v)
        else
            dst[k] = v
        end
    end
    return dst
end

local function read_json_file(path, fs_api)
    local f_api = fs_api or _G.fs
    if not f_api or type(f_api.exists) ~= "function" or type(f_api.open) ~= "function" then
        return nil
    end
    if not f_api.exists(path) then return nil end
    local fh = f_api.open(path, "r")
    if not fh then return nil end
    local raw = fh.readAll()
    fh.close()
    local dec = textutils and (textutils.unserializeJSON or textutils.unserialiseJSON)
    return dec and dec(raw) or nil
end

--- Load nested pda_config.json schema using defaults for omitted fields.
function main.load_config(path, fs_api)
    local cfg = default_config()
    if type(path) == "table" then
        return merge_tables(cfg, path)
    end
    local candidates = (type(path) == "string" and path ~= "")
        and { path }
        or { "/config/pda_config.json", "config/pda_config.json" }
    for _, cand in ipairs(candidates) do
        local parsed = read_json_file(cand, fs_api)
        if type(parsed) == "table" then
            return merge_tables(cfg, parsed)
        end
    end
    return cfg
end

--- Create Pocket PDA application state, open network channels, and build 26x20 TUI buffer.
function main.create_app(cfg, modem_override, fs_api)
    local resolved_cfg = main.load_config(cfg, fs_api)
    local net_ctx = pda_network.init(resolved_cfg, modem_override)
    if net_ctx.modem then
        pda_network.open_channels(net_ctx)
    end
    local app = {
        config = resolved_cfg,
        net = net_ctx,
        hud = telemetry_hud_state.init(resolved_cfg),
        link = remote_link_controller.init(resolved_cfg),
        buf = pocket_tui.create_buffer(resolved_cfg.ui.screenWidth, resolved_cfg.ui.screenHeight),
        activeTab = "HUD",
        statusMsg = "PDA READY",
        running = true,
    }
    return setmetatable(app, { __index = main })
end

local function reset_craft_hud(hud)
    if type(hud) ~= "table" then return end
    hud.fsmState = "UNKNOWN"
    hud.flightMode = "---"
    hud.activeSource = "---"
    hud.sensorOk = false
    hud.actuatorOk = false
    hud.lastTelemMs = nil
    hud.lastDistanceM = nil
    hud.linkQuality = { tier = "LOST", rssiPct = 0, distanceStr = "---" }
    hud.lastPbitReport = nil
    hud.lastAlert = nil
    if type(hud.nodes) == "table" then
        if hud.nodes.AMM then hud.nodes.AMM.online = false end
        if hud.nodes.VAS then hud.nodes.VAS.online = false end
    end
end

--- Switch target aircraft N (1..1000) and rebind modem channels cleanly.
function main:select_aircraft(new_n, domain_override)
    local old_n = self.net.aircraftIndexN
    if new_n == old_n and (domain_override == nil or domain_override == self.net.targetDomainId) then
        return true, nil
    end
    local ok, err = pda_network.rebind_aircraft(self.net, new_n, domain_override)
    if not ok then
        self.statusMsg = tostring(err)
        return false, err
    end
    if new_n ~= old_n then
        reset_craft_hud(self.hud)
    end
    self.statusMsg = string.format("TARGET N:%03d", self.net.aircraftIndexN)
    return true, nil
end

local function mark_node_seen(hud, name, ts)
    if type(hud) == "table" and type(hud.nodes) == "table" and type(hud.nodes[name]) == "table" then
        hud.nodes[name].online = true
        hud.nodes[name].lastSeenMs = ts
    end
end

--- Route an inbound modem packet to Alignment link tracker or Telemetry HUD state.
function main:process_modem_message(channel, _reply_channel, raw_msg, distance_m, now_ms)
    local pkt = pda_network.parse_envelope(raw_msg)
    if not pkt then return false end
    local ts = get_time_ms(now_ms)

    if remote_link_controller.ingest_align_packet(self.link, channel, pkt, ts) then
        mark_node_seen(self.hud, "ALN", ts)
        local p = pkt.payload
        self.statusMsg = (pkt.type == "MSG_ALIGN_REMOTE_STATUS")
            and ("ALN:" .. tostring(p.status or p.fsmState or "OK"))
            or pkt.type
        return true
    end

    if telemetry_hud_state.ingest_packet(self.hud, self.net, channel, pkt, distance_m, ts) then
        if pkt.type == "MSG_EMERGENCY_ALERT" then
            self.statusMsg = "ALERT:" .. tostring(pkt.payload.reason or "EMERGENCY")
        elseif pkt.type == "MSG_PBIT_REPORT" then
            self.statusMsg = "PBIT:" .. tostring(pkt.payload.overallStatus or "DONE")
        elseif pkt.type == "MSG_MISSION_ACK" then
            self.statusMsg = "ACK:" .. tostring(pkt.payload.status or "OK")
        end
        return true
    end
    return false
end

local function step_aircraft_index(app, delta)
    local max_n = (app.config and app.config.channels and app.config.channels.maxAircraft) or 1000
    local cur_n = app.net.aircraftIndexN or 1
    local target_n = math.max(1, math.min(max_n, cur_n + delta))
    local ok = app:select_aircraft(target_n)
    return ok == true
end

local function handle_global_key(app, key_code, ch, now_ms)
    local tab = ch and TAB_BY_KEY[ch]
    if tab then
        app.activeTab = tab
        app.statusMsg = "TAB:" .. tab
        return true, true
    elseif ch == "q" then
        app.running = false
        pda_network.close_channels(app.net)
        app.statusMsg = "SHUTDOWN"
        return true, true
    elseif ch == "x" then
        local ok = emergency_c2_controller.trigger_estop_and_fdr_dump(app.net, app.hud, app.link, "PDA_OPERATOR_ESTOP", now_ms)
        if ok then mark_node_seen(app.hud, "FDR", get_time_ms(now_ms)) end
        app.statusMsg = ok and "E_STOP+DUMP SENT" or "ERR:ESTOP_TX"
        return true, ok == true
    elseif ch and GLOBAL_C2_KEYS[ch] then
        local ok, err = emergency_c2_controller.send_tactical_c2(app.net, app.hud, GLOBAL_C2_KEYS[ch], nil, now_ms)
        app.statusMsg = ok and ("C2:" .. GLOBAL_C2_KEYS[ch]) or tostring(err)
        return true, ok == true
    end

    local left_code = (keys and keys.left) or 203
    local right_code = (keys and keys.right) or 205
    local tab_code = (keys and keys.tab) or 15
    if ch == "[" or ch == "," or (key_code ~= nil and key_code == left_code) then
        return true, step_aircraft_index(app, -1)
    elseif ch == "]" or ch == "." or (key_code ~= nil and key_code == right_code) then
        return true, step_aircraft_index(app, 1)
    elseif ch == "\t" or (key_code ~= nil and key_code == tab_code) then
        local next_n, next_dom = telemetry_hud_state.select_next_discovered(app.hud, app.net.aircraftIndexN)
        if not next_n then
            app.statusMsg = "NO FLEET"
            return true, false
        end
        local ok = app:select_aircraft(next_n, next_dom)
        return true, ok == true
    end
    return false, false
end

local function handle_hud_key(app, ch, now_ms)
    if ch == "a" or ch == "t" then
        local cmd = (ch == "a") and "ARM" or "TAKEOFF"
        local ok, err = emergency_c2_controller.send_tactical_c2(app.net, app.hud, cmd, nil, now_ms)
        app.statusMsg = ok and ("C2:" .. cmd) or tostring(err)
        return ok == true
    elseif ch == "p" then
        local ok = emergency_c2_controller.send_pbit_request(app.net, false, now_ms)
        app.statusMsg = ok and "PBIT REQ SENT" or "ERR:PBIT_TX"
        return ok == true
    end
    return false
end

local function step_hangar_bay(app, delta)
    local max_b = (app.config and app.config.channels and app.config.channels.maxHangarBays) or 10
    local cur_b = app.net.hangarBayId or 1
    local new_bay = math.max(1, math.min(max_b, cur_b + delta))
    local ok, err = pda_network.rebind_hangar_bay(app.net, new_bay)
    if not ok then
        app.statusMsg = tostring(err)
        return false
    end
    local aln = app.link and app.link.alignment
    if aln then
        aln.bayId = new_bay
        aln.baseHangarChannel = app.net.hangarBaseChannel
        aln.stationId = string.format("%s%02d", app.link.stationIdPrefix or "HANGAR_BAY_", new_bay)
    end
    app.statusMsg = string.format("BAY:%02d", new_bay)
    return true
end

local function handle_align_key(app, ch, now_ms)
    if ch == "-" then
        return step_hangar_bay(app, -1)
    elseif ch == "=" or ch == "+" then
        return step_hangar_bay(app, 1)
    end
    local act = ch and ALIGN_ACTION_KEYS[ch]
    if not act then return false end
    local opts = (act == "ABORT_SESSION") and { reason = "PDA_REMOTE_ABORT" } or {}
    local ok, err = remote_link_controller.send_align_cmd(app.net, app.link, act, opts, now_ms)
    app.statusMsg = ok and ("ALN:" .. act) or tostring(err)
    return ok == true
end

local function handle_fdr_key(app, ch, now_ms)
    local act, opts = nil, {}
    if ch == "b" then
        act = "BIND_AIRCRAFT"
        opts = { targetAircraftIndexN = app.net.aircraftIndexN, autoStartLogging = true }
    elseif ch == "m" then
        act = "SET_MODE"
        local is_log = app.link and app.link.fdr and app.link.fdr.mode == "LOGGING"
        opts = { recordMode = is_log and "STANDBY" or "LOGGING", autoStartLogging = (not is_log) }
    else
        act = ch and FDR_SIMPLE_KEYS[ch] or nil
    end
    if not act then return false end
    local ok, err = remote_link_controller.send_fdr_cmd(app.net, app.link, act, opts, now_ms)
    if ok then mark_node_seen(app.hud, "FDR", get_time_ms(now_ms)) end
    app.statusMsg = ok and ("FDR:" .. act) or tostring(err)
    return ok == true
end

--- Process a key code or character input against global and active-tab hotkey maps.
function main:process_key(key_code, char_str, now_ms)
    local ch = (type(char_str) == "string" and char_str ~= "") and string.lower(char_str) or nil
    local handled, ok = handle_global_key(self, key_code, ch, now_ms)
    if handled then
        return ok
    end
    if not ch then return false end
    if self.activeTab == "ALIGN" then
        return handle_align_key(self, ch, now_ms)
    elseif self.activeTab == "FDR" then
        return handle_fdr_key(self, ch, now_ms)
    end
    return handle_hud_key(self, ch, now_ms)
end

--- Refresh link/node timeouts and flush 26x20 TUI buffer to terminal.
function main:render(term_obj, now_ms)
    local ts = get_time_ms(now_ms)
    telemetry_hud_state.update_link_timeouts(self.hud, ts)
    if not self.buf then
        self.buf = pocket_tui.create_buffer()
    end
    pocket_tui.render_screen(self.buf, {
        activeTab = self.activeTab,
        statusMsg = self.statusMsg,
        nowMs = ts,
        net = self.net,
        hud = self.hud,
        link = self.link,
    })
    return pocket_tui.flush_buffer(self.buf, term_obj or term)
end

local function cleanup_display(app)
    pda_network.close_channels(app.net)
    if term and term.clear and term.setCursorPos then
        if term.setBackgroundColor and colors and colors.black then term.setBackgroundColor(colors.black) end
        if term.setTextColor and colors and colors.white then term.setTextColor(colors.white) end
        term.clear()
        term.setCursorPos(1, 1)
    end
end

--- Run live CraftOS non-blocking Pocket PDA event and 5Hz UI refresh loop.
function main.main_loop(config_path)
    local app = main.create_app(config_path)
    local hz = (app.config.system and app.config.system.uiRefreshRateHz) or 5
    local refresh_sec = 1.0 / math.max(1, hz)
    local ui_timer = os.startTimer(refresh_sec)
    app:render(term, get_time_ms())

    while app.running do
        local ev, p1, p2, p3, p4, p5 = os.pullEventRaw()
        local now_ms = get_time_ms()
        if ev == "terminate" then
            app.running = false
        elseif ev == "timer" and p1 == ui_timer then
            app:render(term, now_ms)
            ui_timer = os.startTimer(refresh_sec)
        elseif ev == "modem_message" then
            app:process_modem_message(p2, p3, p4, p5, now_ms)
        elseif ev == "key" then
            app:process_key(p1, nil, now_ms)
        elseif ev == "char" then
            app:process_key(nil, p1, now_ms)
        end
    end
    cleanup_display(app)
    return app
end

if _G.describe == nil and not _G.__HARNESS_HIL_MODE then
    main.main_loop()
end

return main
