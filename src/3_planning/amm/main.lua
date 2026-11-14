-- src/3_planning/amm/main.lua
-- AMM: Aircraft Mission Manager & Cockpit MFD Terminal
local waypoint_queue = require("waypoint_queue")
local network_manager = require("network_manager")
local c2_arbiter = require("c2_arbiter")
local input_handler = require("input_handler")
local ui_renderer = require("ui_renderer")
local mission_engine = require("mission_engine")
local channel_sentinel = require("channel_sentinel")
local nav_engine = require("nav_engine")
local facility_client = require("facility_client")
local trajectory_generator = require("trajectory_generator")
local chattering_guard = require("chattering_guard")

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
    local items = q.items or {}
    for i, it in ipairs(items) do
        local is_land = (it.facilityId ~= nil and it.facilityId ~= "" and i == #items)
        table.insert(cps, {
            checkpointId = string.format("WP_%02d", i),
            action = is_land and "ACT_TKL_LAND_PREC" or "ACT_NAV_SPLINE_WP",
            params = {
                targetPos = { x = it.x, z = it.z },
                targetAlt = it.alt,
                cruiseSpeed = it.speed,
                acceptanceRadius = q.arrivalRadius or 15.0,
                facilityId = it.facilityId,
            },
        })
    end
    return {
        missionId = "MANUAL_QUEUE",
        version = "2.0.0",
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
        local vok, verr, vdetail = mission_engine.validate_mission_table(auto_spec, cfg)
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
    local vok, verr, vdetail = mission_engine.validate_mission_table(parsed, app.config)
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
    confirm = function(app, _subargs, now_ms)
        if app.engine and app.engine.confirm then
            local ok, err = app.engine:confirm(now_ms)
            if app.arbiter then
                app.arbiter.lastBanner = ok and "HUMAN AUTH CONFIRMED" or ("CONFIRM FAIL: " .. tostring(err))
            end
        end
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

local function sync_queue_to_engine(app, now_ms, reload_cps)
    if not app.engine or not app.queue then return end
    app.engine.defaults.targetAlt = app.queue.defaultAlt
    app.engine.defaults.cruiseSpeed = app.queue.defaultSpeed
    app.engine.defaults.acceptanceRadius = app.queue.arrivalRadius
    if not reload_cps then return end
    if app.engine.missionId == "MANUAL_QUEUE" or app.engine:count() == 0 then
        local was_running = (app.engine.state == "EN_ROUTE")
        if app.queue:count() > 0 then
            app.engine:load_table(queue_to_mission_table(app.queue))
            if was_running then app.engine:start("SINGLE", now_ms) end
        else
            app.engine:stop(now_ms)
            app.engine.checkpoints = {}
            app.engine.state = "IDLE"
            app.engine.active_index = 1
        end
    end
end

local CLI_HANDLERS = {
    run = handle_cli_run,
    load = handle_cli_load,
    files = handle_cli_files,
    stop = handle_cli_stop,
    next = handle_cli_next,
    mission = handle_cli_mission,
    add = function(app, a, now_ms)
        app.queue:add(a[1], a[2], a[3], a[4], a[5])
        sync_queue_to_engine(app, now_ms, true)
        app.arbiter.lastBanner = "WP ADDED"
    end,
    del = function(app, a, now_ms)
        app.queue:del(a[1])
        sync_queue_to_engine(app, now_ms, true)
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
    confirm = function(app, _a, now_ms)
        if app.engine and app.engine.confirm then
            local ok, err = app.engine:confirm(now_ms)
            if app.arbiter then
                app.arbiter.lastBanner = ok and "HUMAN AUTH CONFIRMED" or ("CONFIRM FAIL: " .. tostring(err))
            end
        end
    end,
    save = handle_cli_save,
    alt = function(app, a, now_ms)
        if a[1] then
            app.queue.defaultAlt = tonumber(a[1]) or app.queue.defaultAlt
            sync_queue_to_engine(app, now_ms, false)
            app.arbiter.lastBanner = "ALT SET: " .. tostring(app.queue.defaultAlt)
        end
    end,
    spd = function(app, a, now_ms)
        if a[1] then
            app.queue.defaultSpeed = tonumber(a[1]) or app.queue.defaultSpeed
            sync_queue_to_engine(app, now_ms, false)
            app.arbiter.lastBanner = "SPD SET: " .. tostring(app.queue.defaultSpeed)
        end
    end,
    rad = function(app, a, now_ms)
        if a[1] then
            app.queue.arrivalRadius = tonumber(a[1]) or app.queue.arrivalRadius
            sync_queue_to_engine(app, now_ms, false)
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

local function render_ui_frame(app, now_ms)
    if not app or (app.config and app.config.headless == true) or not app.screen_buf then
        return
    end
    local t_ms = now_ms or get_now_ms(app)
    local nav = app.nav
    local arb = app.arbiter
    local fac = app.fac
    local mfd = arb and arb.latest_mfd_payload

    local app_state = {
        domainId = (app.config and app.config.domainId) or "AIRCRAFT_01",
        authority = (arb and arb.authority) or "PILOT_PRIMARY",
        banner = (arb and arb.lastBanner) or "SYSTEM READY",
        input_mode = (app.input and app.input.mode) or "NAV",
        input_buffer = (app.input and app.input.buffer) or "",
        now_ms = t_ms,
        gpsTimedOut = (nav and nav.gpsTimedOut) or false,
        navValid = (nav and nav.navValid) or (mfd and mfd.navigation and mfd.navigation.navValid) or false,
        fcpTimedOut = (arb and arb.fcpTimedOut) or false,
        trackingStatus = (arb and arb.fcpTrackingStatus)
            or (arb and arb.latest_outer_status and arb.latest_outer_status.trackingStatus) or "TRACKING",
        facilityId = (fac and fac.activePadId)
            or (arb and arb.activeGoal and arb.activeGoal.facilityId) or "NONE",
    }
    local src_data = (app.engine and app.engine:count() > 0) and app.engine or app.queue
    ui_renderer.render_screen(app.screen_buf, mfd, src_data, app_state)
    ui_renderer.flush_buffer(app.screen_buf, app.term_obj or term)
end

local function handle_timer_event(app, timer_id, now_ms)
    if timer_id ~= app.render_timer and app.render_timer ~= nil then return end
    if app.render_timer and os.startTimer then
        app.render_timer = os.startTimer(0.2)
    end
    if app.engine and not app.coroutineActive then
        app.engine:tick(now_ms)
    end
    render_ui_frame(app, now_ms)
end

local function open_fac_channels(app)
    if not app.fac or not app.net or not app.net.open_infra_channel then return end
    if app.fac.gacChannel then app.net:open_infra_channel(app.fac.gacChannel) end
    if app.fac.padChannel then app.net:open_infra_channel(app.fac.padChannel) end
end

local function handle_sentinel_rx(app, chan, pkt, base, now_ms)
    if not app.sentinel then return false end
    if chan == base + 0 and pkt.type == "MSG_CHANNEL_PROBE" then
        local ack = channel_sentinel.handle_incoming_probe(app.sentinel, pkt)
        local m = app.net and (app.net.onboardModem or app.net.modem)
        if ack and m then
            local env = app.net:encode_envelope(ack.type, ack.payload)
            pcall(function() m.transmit(base + 0, base + 0, env) end)
        end
        return true
    elseif pkt.type == "MSG_CHANNEL_PROBE_ACK" and (chan == base + 0 or chan == 50000 or chan == app.sentinel.candidateBase) then
        channel_sentinel.on_probe_ack(app.sentinel, pkt)
        return true
    elseif chan == 50000 and pkt.type == "MSG_BLOCK_ASSIGN" then
        channel_sentinel.on_block_assign(app.sentinel, pkt.payload, now_ms)
        return true
    end
    return false
end

local function handle_facility_rx(app, chan, pkt, now_ms)
    if not app.fac then return false end
    local pos = app.nav and app.nav.pos
    if chan == 50001 then
        if pkt.type == "MSG_ATC_APPROACH_CLEARANCE" or pkt.type == "MSG_ATC_SECTOR_HANDOFF" then
            facility_client.on_atc_clearance(app.fac, pkt, pos, now_ms)
            open_fac_channels(app)
        elseif pkt.type == "MSG_FACILITY_BEACON" then
            facility_client.update_beacons(app.fac, pkt.payload, now_ms)
        end
        return true
    elseif chan == 50003 and pkt.type == "MSG_FACILITY_BEACON" then
        facility_client.update_beacons(app.fac, pkt.payload, now_ms)
        return true
    elseif app.fac.gacChannel and chan == app.fac.gacChannel then
        if pkt.type == "MSG_GAC_APPROACH_CLEARANCE" then
            facility_client.on_atc_clearance(app.fac, pkt, pos, now_ms)
            open_fac_channels(app)
        elseif pkt.type == "MSG_GAC_ABORT_CLEAR" then
            facility_client.on_gac_abort_clear(app.fac, pkt, now_ms)
        end
        return true
    elseif app.fac.padChannel and chan == app.fac.padChannel then
        if pkt.type == "MSG_DOCKING_STATUS" then
            facility_client.on_docking_status(app.fac, pkt, now_ms)
        else
            facility_client.on_tactical_guide(app.fac, pkt, now_ms)
        end
        return true
    end
    return false
end

local function handle_modem_message(app, chan, raw_msg, now_ms)
    if not app.net or not app.net.decode_envelope then return end
    local ok, pkt = app.net:decode_envelope(raw_msg)
    if not ok or not pkt then return end
    local base = (app.config and app.config.baseChannel) or (app.net and app.net.baseChannel) or 10000
    if chan == base + 3 and app.arbiter and app.arbiter.handle_mfd_state then
        app.arbiter:handle_mfd_state(pkt, now_ms)
    elseif chan == base + 2 then
        if app.arbiter and app.arbiter.handle_flight_telemetry then
            app.arbiter:handle_flight_telemetry(pkt, now_ms)
        end
        if app.nav and nav_engine.integrate_dr then
            nav_engine.integrate_dr(app.nav, pkt.payload, 0.05, now_ms)
        end
    elseif chan == base + 4 then
        if pkt.type == "MSG_OUTER_LOOP_STATUS" and app.arbiter and app.arbiter.handle_outer_loop_status then
            app.arbiter:handle_outer_loop_status(pkt, now_ms)
        elseif pkt.type == "MSG_CHANNEL_REBIND_ACK" and app.sentinel then
            channel_sentinel.on_rebind_ack(app.sentinel, pkt, now_ms)
        end
    elseif chan == base + 5 and app.nav and pkt.type == "MSG_GPS_RESPONSE" then
        nav_engine.filter_gps(app.nav, pkt.payload, 0.05, now_ms)
    elseif handle_sentinel_rx(app, chan, pkt, base, now_ms) then
        return
    elseif chan == base + 0 and app.arbiter and app.arbiter.handle_gcs_packet then
        app.arbiter:handle_gcs_packet(pkt, now_ms)
    elseif handle_facility_rx(app, chan, pkt, now_ms) then
        return
    elseif app.net.is_payload_channel and app.net:is_payload_channel(chan) and app.engine then
        app.engine:on_payload_ack(pkt, chan, now_ms)
    end
end

local function is_ctrl_keycode(k)
    local lc = keys and keys.leftCtrl or 29
    local rc = keys and keys.rightCtrl or 157
    return k == lc or k == rc
end

local function handle_input_event(app, ev, p1, now_ms)
    if ev == "key_up" and is_ctrl_keycode(p1) then
        app.ctrlHeld = false
    elseif ev == "char" then
        if app.ctrlHeld and app.input and app.input.handle_ctrl_key then
            local act = app.input:handle_ctrl_key(p1)
            if act and act.action and app.arbiter then
                app.arbiter:handle_pilot_action(act.action, act.params or {}, now_ms)
                return
            end
        end
        local act = app.input:handle_char(p1)
        if act and act.action then
            app.arbiter:handle_pilot_action(act.action, act.params or {}, now_ms)
        end
    elseif ev == "key" then
        if is_ctrl_keycode(p1) then
            app.ctrlHeld = true
            return
        end
        if app.ctrlHeld and p1 == (keys and keys.x or 45) and app.input and app.input.handle_ctrl_key then
            local act = app.input:handle_ctrl_key("x")
            if act and act.action and app.arbiter then
                app.arbiter:handle_pilot_action(act.action, act.params or {}, now_ms)
                return
            end
        end
        local cmd = app.input:handle_key(p1)
        if cmd then execute_cli_command(app, cmd, now_ms) end
    elseif ev == "paste" and app.input and app.input.handle_paste then
        app.input:handle_paste(p1)
    elseif ev == "file_transfer" then
        handle_file_transfer(app, p1, now_ms)
    end
end

local function process_event(app, ev, p1, p2, p3, p4, _p5)
    local now_ms = get_now_ms(app)
    if ev == "timer" then
        handle_timer_event(app, p1, now_ms)
    elseif ev == "modem_message" then
        handle_modem_message(app, p2, p4, now_ms)
    else
        handle_input_event(app, ev, p1, now_ms)
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

local function bind_app_modems(net, modems, base_ch, cfg)
    local sys = type(cfg) == "table" and cfg.system or nil
    local pri_side = (sys and sys.primaryModemSide) or "top"
    local inf_side = (sys and sys.infraModemSide) or "back"
    if type(modems) == "table" then
        if modems[pri_side] or modems[inf_side] then
            net:bind_modems(modems[pri_side], modems[inf_side], base_ch)
        elseif modems.top or modems.back then
            net:bind_modems(modems.top, modems.back, base_ch)
        elseif modems[1] or modems[2] then
            net:bind_modems(modems[1], modems[2], base_ch)
        elseif modems.transmit then
            net:bind_modem(modems)
        end
    elseif peripheral and peripheral.find then
        local pri_m = peripheral.wrap and peripheral.wrap(pri_side)
        local inf_m = peripheral.wrap and peripheral.wrap(inf_side)
        local is_w = function(m) return m and type(m.isWireless) == "function" and m.isWireless() end
        if is_w(pri_m) and is_w(inf_m) then
            net:bind_modems(pri_m, inf_m, base_ch)
        else
            local m = peripheral.find("modem", function(_, o) return o.isWireless and o.isWireless() end)
            if m then net:bind_modem(m) end
        end
    end
end

local function create_app(config, modems)
    local cfg = (type(config) == "string") and load_config(config) or config or load_config()
    local queue = waypoint_queue.new(cfg)
    local net = network_manager.new(cfg)
    local sentinel = setmetatable(channel_sentinel.init(cfg), { __index = channel_sentinel })
    local nav = setmetatable(nav_engine.init(cfg), { __index = nav_engine })
    local fac = setmetatable(facility_client.init(cfg), { __index = facility_client })
    local traj = setmetatable(trajectory_generator.init(cfg), { __index = trajectory_generator })
    local guard = chattering_guard.init(cfg)
    local engine = mission_engine.new({
        net = net,
        config = cfg,
        guard = guard,
        sentinel = sentinel,
        fac = fac,
        redstone = redstone,
        colors = colors,
    })
    local arbiter = c2_arbiter.new(queue, net, cfg, engine, guard)
    local input = input_handler.new()
    local screen_buf = (not cfg.headless) and ui_renderer.create_buffer(51, 19) or nil

    bind_app_modems(net, modems, cfg.baseChannel, cfg)

    return {
        config = cfg,
        queue = queue,
        net = net,
        sentinel = sentinel,
        nav = nav,
        fac = fac,
        traj = traj,
        engine = engine,
        arbiter = arbiter,
        guard = guard,
        input = input,
        screen_buf = screen_buf,
        render_timer = os.startTimer(0.2),
        tickCount = 0,
        ctrlHeld = false,
        running = true,
    }
end

local function step_5hz_downlink(app, now_ms)
    local act_src = (app.arbiter and app.arbiter.activeSource) or "FCP"
    if act_src == "MFD_ACRO" then
        return false, "YIELDED_TO_MFD_ACRO"
    end
    local telem = (app.arbiter and app.arbiter.latest_telem) or {}
    local goal = (app.arbiter and app.arbiter.get_effective_goal and app.arbiter:get_effective_goal()) or {}
    local nav_pos = app.nav and app.nav.pos
    local att = (app.nav and app.nav.attitude) or telem.attitude or {}
    local dist_wp = nil
    if nav_pos and goal.targetPos then
        local dx = (goal.targetPos.x or 0) - (nav_pos.x or 0)
        local dz = (goal.targetPos.z or 0) - (nav_pos.z or 0)
        dist_wp = math.sqrt(dx * dx + dz * dz)
    end
    local mfd_payload = {
        source = "AMM_INTEGRATED",
        fsmState = (app.arbiter and app.arbiter.fsmState) or "DISARMED",
        controlState = telem.controlState or (app.arbiter and app.arbiter.fsmState) or "DISARMED",
        flightMode = goal.flightMode or "IDLE_ARMED",
        activeSource = act_src,
        authority = (app.arbiter and app.arbiter.authority) or "PILOT_PRIMARY",
        domainId = (app.config and app.config.domainId) or "AIRCRAFT_01",
        fuel = telem.fuel or (app.nav and app.nav.fuel) or 1.0,
        dynamicLoad = telem.dynamicLoad or 0.0,
        sensorOk = (telem.sensorOk ~= false),
        sensorHealth = telem.sensorHealth or { gimbal = true, altitude = true, velocity = true, fuel = true },
        actuatorHealth = telem.actuatorHealth or { tap = true, asa = true, allOk = true },
        angularRates = telem.angularRates or { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
        nav = {
            targetAlt = goal.targetAlt,
            targetSpeed = goal.targetSpeed,
            targetHeading = goal.fixedHeadingDeg,
            distToWp = dist_wp,
            currentWpIndex = (app.engine and app.engine.active_index) or (app.queue and app.queue.active_index) or 1,
        },
        navigation = {
            currentPos = nav_pos,
            navValid = app.nav and app.nav.navValid,
            gpsTimedOut = app.nav and app.nav.gpsStale,
            hdop = app.nav and app.nav.hdop,
        },
        dynamics = {
            altitudeY = nav_pos and nav_pos.y or (app.nav and app.nav.altitudeY),
            groundSpeed = app.nav and app.nav.groundSpeed,
            verticalSpeed = app.nav and app.nav.verticalSpeed,
        },
        attitude = {
            pitch = att.pitch or 0.0,
            roll = att.roll or 0.0,
            yaw = att.yaw or att.heading or 0.0,
            heading = att.heading or att.yaw or 0.0,
        },
    }
    if app.net and app.net.send_mfd_state then
        return app.net:send_mfd_state(mfd_payload, act_src)
    end
    return true
end

local function step_sentinel_20hz(app, now)
    if not app.sentinel or not app.net then return end
    local _, out_pkt = channel_sentinel.negotiate_and_probe(app.sentinel, now)
    if out_pkt then
        if out_pkt.type == "MSG_BLOCK_REQUEST" then
            app.net:send_infra_packet(50000, out_pkt.type, out_pkt.payload)
        elseif out_pkt.type == "MSG_CHANNEL_PROBE" then
            local probe_ch = (out_pkt.payload and out_pkt.payload.candidateBase)
                or app.sentinel.candidateBase or (app.config and app.config.baseChannel) or 10000
            local m = app.net.onboardModem or app.net.modem
            if m then
                pcall(function() m.open(probe_ch) end)
                local env = app.net:encode_envelope(out_pkt.type, out_pkt.payload)
                pcall(function() m.transmit(probe_ch, probe_ch, env) end)
            end
        end
    end
    if app.sentinel.rebindTx then
        local rebind_msg, status = channel_sentinel.step_rebind_transaction(app.sentinel, now)
        if rebind_msg then
            local p = rebind_msg.payload
            app.net:send_rebind_command(p.action, p.transactionId, p.oldBaseChannel, p.newBaseChannel)
            if status == "COMMITTED" then
                app.net:apply_rebind(p.newBaseChannel)
                if app.config then app.config.baseChannel = p.newBaseChannel end
                if app.nav then app.nav.baseChannel = p.newBaseChannel end
                if app.engine then app.engine.baseChannel = p.newBaseChannel end
            end
        end
    end
end

local function step_facility_watchdog_20hz(app, goal, now)
    if not app.fac then return end
    app.fac.flightMode = goal and goal.flightMode or app.fac.flightMode
    local wd = facility_client.evaluate_guide_watchdog(app.fac, now)
    if wd.action == "RTH" or wd.action == "FAILSAFE_RTH" then
        if app.arbiter then
            app.arbiter.emergencyGoal = { flightMode = "FAILSAFE_RTH", arm = true, flightActive = true }
            app.arbiter.lastBanner = "[FACILITY WATCHDOG: FAILSAFE RTH]"
        end
    elseif wd.triggerGoAround and app.arbiter then
        app.arbiter.emergencyGoal = { flightMode = "HOVER_HOLD", arm = true, flightActive = true, targetAlt = wd.targetAlt }
        app.arbiter.lastBanner = "[FACILITY WATCHDOG: GO-AROUND]"
    elseif wd.shouldRetryAtc and app.fac.activePadId and app.net then
        local pad_id = app.fac.activePadId
        local fac_info = (app.fac.beacons and app.fac.beacons[pad_id]) or {}
        local craft_cfg = {
            facilityType = fac_info.facilityType or "LANDING_PAD",
            domainId = (app.config and app.config.domainId) or "AIRCRAFT_01",
        }
        local fuel_pct = (app.arbiter and app.arbiter.latest_telem and app.arbiter.latest_telem.fuel) or 1.0
        local ok_req, req = facility_client.request_approach(app.fac, pad_id, craft_cfg, fuel_pct, now)
        if ok_req and type(req) == "table" then
            local tx_ch = app.fac.gacChannel or 50001
            app.net:send_infra_packet(tx_ch, req.type, req.payload)
        end
    end
end

local function step_20hz_tick(app, dt, now_ms)
    app.tickCount = (app.tickCount or 0) + 1
    local now = now_ms or get_now_ms(app)
    local step_dt = dt or 0.05

    if app.arbiter and app.arbiter.check_timeouts then
        app.arbiter:check_timeouts(now)
    end
    if app.nav and nav_engine.update_timeout then
        nav_engine.update_timeout(app.nav, now)
    end

    local pre_goal = (app.arbiter and app.arbiter.get_effective_goal and app.arbiter:get_effective_goal())
        or { flightMode = "IDLE_ARMED", arm = false, flightActive = false }
    local emcon_active = (pre_goal.emconActive == true) or (app.engine and app.engine.emconActive == true)
    if app.nav and app.net and not emcon_active then
        local should_gps, _, gps_pkt = nav_engine.build_gps_request(app.nav, now)
        if should_gps and gps_pkt then
            app.net:send_gps_request(gps_pkt)
        end
    end

    local mfd_live = app.lastMfd or (app.arbiter and app.arbiter.latest_mfd_payload)
    local fuel_live = (mfd_live and mfd_live.fuel) or (app.arbiter and app.arbiter.latest_telem and app.arbiter.latest_telem.fuel)
    local is_disarmed = mfd_live and (mfd_live.controlState == "DISARMED" or mfd_live.fsmState == "DISARMED")
    if app.guard and type(fuel_live) == "number" and (not app.arbiter or app.arbiter.lastTelemMs ~= now) then
        local latches = chattering_guard.update_fuel_latches(app.guard, fuel_live, app.config, is_disarmed)
        if app.arbiter and latches then
            if latches.emergFuelLatched then
                app.arbiter.emergencyGoal = { flightMode = "EMERGENCY_LAND", arm = true, flightActive = true, _fuelLatch = "EMERG" }
            elseif latches.lowFuelLatched and (not app.arbiter.emergencyGoal or app.arbiter.emergencyGoal.flightMode ~= "EMERGENCY_LAND") then
                app.arbiter.emergencyGoal = { flightMode = "FAILSAFE_RTH", arm = true, flightActive = true, _fuelLatch = "LOW" }
            end
        end
    end

    step_sentinel_20hz(app, now)
    if app.engine then app.engine:tick(now) end

    local goal = (app.arbiter and app.arbiter.get_effective_goal and app.arbiter:get_effective_goal())
        or { flightMode = "IDLE_ARMED", arm = false, flightActive = false }
    step_facility_watchdog_20hz(app, goal, now)
    goal = (app.arbiter and app.arbiter.get_effective_goal and app.arbiter:get_effective_goal()) or goal

    local setpoint = trajectory_generator.compute(app.traj, app.nav, app.fac, goal, step_dt, now)
    if app.net and app.net.send_trajectory_setpoint then
        app.net:send_trajectory_setpoint(setpoint)
    end
    if app.tickCount % 4 == 0 then
        step_5hz_downlink(app, now)
    end
    return setpoint
end

local function make_coroutine_a(app)
    return function()
        app.coroutineActive = true
        local timer20 = os.startTimer(0.05)
        while app.running do
            local ev, p1, p2, p3, p4 = os.pullEventRaw()
            local now_ms = get_now_ms(app)
            if ev == "terminate" then
                shutdown_app(app)
                break
            elseif ev == "timer" and p1 == timer20 then
                step_20hz_tick(app, 0.05, now_ms)
                timer20 = os.startTimer(0.05)
            elseif ev == "modem_message" then
                handle_modem_message(app, p2, p4, now_ms)
            end
        end
    end
end

local function make_coroutine_b(app)
    return function()
        app.render_timer = os.startTimer(0.2)
        while app.running do
            local ev, p1, p2, p3, p4 = os.pullEventRaw()
            local now_ms = get_now_ms(app)
            if ev == "terminate" then
                shutdown_app(app)
                break
            elseif ev == "timer" and p1 == app.render_timer then
                render_ui_frame(app, now_ms)
                app.render_timer = os.startTimer(0.2)
            else
                handle_input_event(app, ev, p1, now_ms)
            end
        end
    end
end

local function main_loop(...)
    local arg1, arg2, arg3 = ...
    local boot_cfg, boot_spec, boot_mode = parse_boot_args(arg1, arg2, arg3)
    local cfg = load_config(boot_cfg)
    local app = create_app(cfg)

    local now_ms = (os.epoch and os.epoch("utc")) or (os.time() * 1000)
    local start_spec = boot_spec or cfg.autoStartMission
    local start_mode = boot_mode or cfg.autoExecutionMode
    if start_spec then
        try_auto_start_mission(app.engine, start_spec, now_ms, cfg, app.arbiter, start_mode)
    end

    if cfg.headless then
        make_coroutine_a(app)()
    else
        parallel.waitForAny(make_coroutine_a(app), make_coroutine_b(app))
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
    create_app = create_app,
    step_20hz_tick = step_20hz_tick,
    step_5hz_downlink = step_5hz_downlink,
    render_ui_frame = render_ui_frame,
    handle_timer_event = handle_timer_event,
    make_coroutine_a = make_coroutine_a,
    make_coroutine_b = make_coroutine_b,
}
