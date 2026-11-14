-- src/3_planning/amm/modules/ui_renderer.lua
-- AMM 51x19 Dual-Pane TUI Buffer Renderer (0-Flicker term.blit)
local condition_evaluator = require("condition_evaluator")

local ui_renderer = {}

local W, H = 51, 19

local ACTION_SHORT = {
    ACT_SYS_LOAD = "LOAD",
    ACT_SYS_PREFLIGHT = "PREFLT",
    ACT_SYS_SET_HOME = "SETHM",
    ACT_SYS_ARM = "ARM",
    ACT_SYS_DISARM = "DISARM",
    ACT_SYS_TERMINATE = "TERM",
    ACT_TKL_TAKEOFF_VERT = "TKOFF",
    ACT_TKL_TRANS_MC2FW = "MC2FW",
    ACT_TKL_TRANS_FW2MC = "FW2MC",
    ACT_TKL_LAND_NORM = "LAND",
    ACT_TKL_LAND_PREC = "LAND",
    ACT_TKL_ABORT_LAND = "ABTLND",
    ACT_NAV_GOTO_WP = "GOTO",
    ACT_NAV_SPLINE_WP = "SPLINE",
    ACT_NAV_CORRIDOR = "CORR",
    ACT_NAV_CHANGE_ALT = "CHGALT",
    ACT_NAV_CHANGE_SPD = "CHGSPD",
    ACT_NAV_CHANGE_YAW = "CHGYAW",
    ACT_PAT_HOLD_POS = "HOLD",
    ACT_PAT_POI_HOLD = "POIHLD",
    ACT_PAT_LOITER_TIME = "ORBIT",
    ACT_PAT_LOITER_TURNS = "ORBIT",
    ACT_PAT_LOITER_ALT = "ORBIT",
    ACT_PAY_BUS_CMD = "PAYLD",
    ACT_PAY_REDSTONE = "RDSTN",
    ACT_PAY_SET_ROI = "SETROI",
    ACT_PAY_CLEAR_ROI = "CLRROI",
    ACT_COM_ATC_HOLD = "ATCHLD",
    ACT_MOB_RV_TRACK = "RVTRK",
    ACT_MOB_DECK_SYNC = "DCKSYN",
    ACT_MOB_MOVING_TKOFF = "MVTKOF",
    ACT_FS_RTL_HOME = "RTH",
    ACT_FS_GOTO_RALLY = "RALLY",
    ACT_FS_FENCE_BRAKE = "BRAKE",
    ACT_FS_HOVER_HOLD = "HOVER",
    ACT_FS_EMERG_LAND = "EMLND",
    ACT_TKL_TAKEOFF_RWY = "TKORW",
    ACT_TKL_LAND_RWY = "LNDRW",
    ACT_MOB_ARM_DOCK = "DCKARM",
    ACT_MOB_ARM_UNDOCK = "UNDCK",
}

local function pad(str, len, align_right)
    local s = tostring(str or "")
    if #s > len then return string.sub(s, 1, len) end
    local spaces = string.rep(" ", len - #s)
    if align_right then return spaces .. s end
    return s .. spaces
end

local function draw_text(buf, y, x, text, fg_char, bg_char)
    if y < 1 or y > H or x < 1 or x > W then return end
    local str = tostring(text or "")
    local len = #str
    if x + len - 1 > W then
        str = string.sub(str, 1, W - x + 1)
        len = #str
    end
    local fc = string.rep(fg_char or "0", len)
    local bc = string.rep(bg_char or "f", len)

    local left_t = string.sub(buf.text[y], 1, x - 1)
    local right_t = string.sub(buf.text[y], x + len)
    buf.text[y] = left_t .. str .. right_t

    local left_f = string.sub(buf.fg[y], 1, x - 1)
    local right_f = string.sub(buf.fg[y], x + len)
    buf.fg[y] = left_f .. fc .. right_f

    local left_b = string.sub(buf.bg[y], 1, x - 1)
    local right_b = string.sub(buf.bg[y], x + len)
    buf.bg[y] = left_b .. bc .. right_b
end

local function draw_right_pane(buf, y, text, fg_char, bg_char)
    local s = pad(text or "", 25)
    draw_text(buf, y, 27, s, fg_char or "0", bg_char or "f")
end

function ui_renderer.create_buffer(width, height)
    local w = width or W
    local h = height or H
    local buf = { text = {}, fg = {}, bg = {} }
    for y = 1, h do
        buf.text[y] = string.rep(" ", w)
        buf.fg[y] = string.rep("0", w)
        buf.bg[y] = string.rep("f", w)
    end
    return buf
end

function ui_renderer.compute_viewport(total, active_idx, window_size)
    local win = window_size or 6
    if not total or total <= 0 then
        return 1, 0
    end
    if total <= win then
        return 1, total
    end
    local act = math.max(1, active_idx or 1)
    local half = math.floor((win - 1) / 2)
    local start_i = math.max(1, act - half)
    if start_i + win - 1 > total then
        start_i = math.max(1, total - win + 1)
    end
    local end_i = math.min(total, start_i + win - 1)
    return start_i, end_i
end

local function render_header(buf, mfd, app)
    local dom = app and app.domainId or "AIRCRAFT_01"
    local fsm = mfd and mfd.fsmState or "DISARMED"
    local alt = mfd and mfd.dynamics and mfd.dynamics.altitudeY or 0
    local spd = mfd and mfd.dynamics and mfd.dynamics.groundSpeed or 0
    local auth = app and app.authority or "PILOT_PRIMARY"
    local head = string.format(" %s [%s] ALT:%dm SPD:%dm/s AUTH:%s", dom, fsm, math.floor(alt), math.floor(spd), auth)
    draw_text(buf, 1, 1, pad(head, W), "0", "9")
    local div = string.rep("-", 25) .. "+" .. string.rep("-", 25)
    draw_text(buf, 2, 1, div, "7", "f")
end

local function render_hud_pane(buf, mfd, app)
    draw_text(buf, 3, 2, pad("[HUD INSTRUMENTS]", 24), "d", "f")
    local att = mfd and mfd.attitude or {}
    local dyn = mfd and mfd.dynamics or {}
    local p = att.pitch or 0.0
    local r = att.roll or 0.0
    local hdg = att.heading or 0.0
    draw_text(buf, 4, 2, string.format("PITCH: %+05.1f ROLL:%+05.1f", p, r), "0", "f")
    draw_text(buf, 5, 2, string.format("HDG  : %05.1f DEG", hdg), "0", "f")
    draw_text(buf, 6, 2, string.format("Y-ALT: %6.1f m", dyn.altitudeY or 0.0), "0", "f")
    draw_text(buf, 7, 2, string.format("V-SPD: %+5.2f m/s", dyn.verticalSpeed or 0.0), "0", "f")
    draw_text(buf, 8, 2, string.format("G-SPD:  %5.1f m/s", dyn.groundSpeed or 0.0), "0", "f")

    local fuel_pct = math.floor((mfd and mfd.fuel or 1.0) * 100)
    local fuel_bars = math.floor(fuel_pct / 10)
    local fuel_str = string.format("FUEL : [%s%s] %3d%%", string.rep("|", fuel_bars), string.rep(".", 10 - fuel_bars), fuel_pct)
    local fuel_col = fuel_pct < 20 and "e" or (fuel_pct < 40 and "1" or "5")
    draw_text(buf, 9, 2, fuel_str, fuel_col, "f")
    draw_text(buf, 10, 2, string.format("SRC  : %s", pad(mfd and mfd.activeSource or "FCP", 12)), "8", "f")
    draw_text(buf, 11, 2, "ACTR : ALL_HEALTHY", "5", "f")

    local nav = mfd and mfd.navigation
    local is_stale = (app and app.gpsTimedOut == true) or (nav and nav.gpsTimedOut == true)
    local is_valid = (app and app.navValid) or (nav and nav.navValid) or false
    local nav_status = is_stale and "DR_STALE" or (is_valid and "GPS_OK" or "NO_FIX")
    local nav_col = is_stale and "e" or (is_valid and "5" or "8")
    draw_text(buf, 12, 2, pad("NAV  : " .. nav_status, 24), nav_col, "f")

    local fcp_to = (app and app.fcpTimedOut == true)
    local fcp_trk = (app and app.trackingStatus) or (mfd and mfd.trackingStatus) or "TRACKING"
    local fcp_status = fcp_to and "TIMEOUT" or fcp_trk
    local fcp_col = fcp_to and "e" or "5"
    draw_text(buf, 13, 2, pad("FCP  : " .. fcp_status, 24), fcp_col, "f")

    local fac_id = (app and app.facilityId) or (mfd and mfd.facilityId) or "NONE"
    draw_text(buf, 14, 2, pad("FAC  : " .. tostring(fac_id), 24), "8", "f")
    draw_text(buf, 15, 2, pad("", 24), "0", "f")
end

local function format_mission_header(source, is_engine)
    if not is_engine then
        local items = source and source.items or {}
        local act = source and source.active_index or 1
        local total = #items
        local disp = (total == 0) and 0 or math.min(math.max(1, act), total)
        return pad(string.format("[MISSION QUEUE] (%d/%d)", disp, total), 25)
    end

    local cps = source and source.checkpoints or {}
    local total = #cps
    local act = source and source.active_index or 1
    local disp = (total == 0) and 0 or math.min(math.max(1, act), total)
    local suffix = string.format(" (%d/%d)", disp, total)
    local id = tostring(source and source.missionId or "UNNAMED")

    local full = string.format("[MISSION: %s]%s", id, suffix)
    if #full <= 25 then return pad(full, 25) end

    local msn = string.format("[MSN: %s]%s", id, suffix)
    if #msn <= 25 then return pad(msn, 25) end

    local avail = math.max(1, 25 - #suffix - 6)
    return pad(string.format("[MSN:%s]%s", string.sub(id, 1, avail), suffix), 25)
end

local function format_cp_target(item)
    local p = item and item.params or {}
    local pos = p.targetPos or (p.x and p.z and { x = p.x, z = p.z })
    if p.facilityId then
        return " " .. tostring(p.facilityId)
    elseif pos and pos.x and pos.z then
        return string.format(" [%d,%d]", math.floor(pos.x), math.floor(pos.z))
    elseif p.channelOffset then
        return string.format(" CH+%d", p.channelOffset)
    end
    return ""
end

local function format_checkpoint_row(item, idx, active_idx, is_engine)
    if not item then return "", "0" end
    if not is_engine then
        local marker = (idx == active_idx) and "*" or (item.completed and "O" or " ")
        local col = (idx == active_idx) and "4" or (item.completed and "8" or "0")
        local fac = item.facilityId and (" " .. item.facilityId) or ""
        local x = item.x or (item.params and item.params.x) or 0
        local z = item.z or (item.params and item.params.z) or 0
        local line = string.format("%s WP%d:[%4d,%4d]%s", marker, item.id or idx, math.floor(x), math.floor(z), fac)
        return line, col
    end

    local marker = " "
    local col = "0"
    if item.status == "ABORTED" then
        marker = "!"
        col = "e"
    elseif idx == active_idx or item.status == "ACTIVE" then
        marker = "*"
        col = "4"
    elseif item.status == "COMPLETED" or item.completed then
        marker = "O"
        col = "8"
    end

    local act_code = ACTION_SHORT[item.action] or item.action or "WP"
    local tgt = format_cp_target(item)
    local line = string.format("%s %d:%s%s", marker, idx, act_code, tgt)
    return line, col
end

local function format_action_detail(cp, source, is_engine)
    if not is_engine then
        local items = source and source.items or {}
        local act = source and source.active_index or 1
        local wp = items[act]
        if wp then return string.format("WP %d", wp.id or act) end
        return "NONE"
    end
    if not cp then return "NONE" end
    local act = cp.action or "NONE"
    local p = cp.params or {}
    if act == "ACT_PAT_LOITER_TIME" or act == "ACT_PAT_LOITER_TURNS" or act == "ACT_PAT_LOITER_ALT" then
        return string.format("ORBIT %s R:%dm", p.direction or "CW", math.floor(p.radius or 50))
    elseif act == "ACT_PAY_BUS_CMD" then
        local ch = p.channelOffset and string.format("CH+%d", p.channelOffset) or (p.command or "")
        return "PAYLD " .. ch
    elseif act == "ACT_PAY_REDSTONE" then
        return string.format("RDSTN %s %s", p.side or "top", p.mode or "EMIT")
    elseif act == "ACT_TKL_TAKEOFF_VERT" or act == "ACT_MOB_MOVING_TKOFF" then
        return "TKOFF " .. tostring(p.facilityId or "")
    elseif act == "ACT_TKL_LAND_PREC" or act == "ACT_TKL_LAND_NORM" then
        return "LAND " .. tostring(p.facilityId or "")
    end
    return ACTION_SHORT[act] or act
end

local function resolve_active_target_pos(cp, source, is_engine)
    if not is_engine then
        local items = source and source.items or {}
        local act = source and source.active_index or 1
        local wp = items[act]
        if wp and wp.x and wp.z then return wp.x, wp.z end
        return nil, nil
    end
    if not cp then return nil, nil end
    local p = cp.params or {}
    local pos = p.targetPos or p.endPos or (p.x and p.z and { x = p.x, z = p.z })
    if pos and pos.x and pos.z then return pos.x, pos.z end
    return nil, nil
end

local function format_distance_detail(cp, source, mfd, is_engine)
    local tx, tz = resolve_active_target_pos(cp, source, is_engine)
    local cur = mfd and mfd.navigation and mfd.navigation.currentPos
    local dist_str
    if tx and tz and cur and cur.x and cur.z then
        local dx = tx - cur.x
        local dz = tz - cur.z
        local dist_m = math.sqrt(dx * dx + dz * dz)
        dist_str = string.format("%.1fm", dist_m)
    elseif mfd and mfd.navigation and mfd.navigation.distanceToWp then
        dist_str = string.format("%.1fm", mfd.navigation.distanceToWp)
    else
        dist_str = "---.-m"
    end

    local p = cp and cp.params or {}
    local rad = p.acceptanceRadius or (source and source.defaults and source.defaults.acceptanceRadius)
        or (source and source.arrivalRadius) or 15
    return string.format("DIST : %s (RAD:%dm)", dist_str, math.floor(rad))
end

local function format_alt_spd_detail(cp, source, mfd, is_engine)
    local p = cp and cp.params or {}
    local def = source and source.defaults or {}
    local dyn = mfd and mfd.dynamics or {}
    local alt = p.targetAlt or def.targetAlt or (source and source.defaultAlt) or dyn.altitudeY or 0
    local spd = p.cruiseSpeed or def.cruiseSpeed or (source and source.defaultSpeed) or dyn.groundSpeed or 0
    return string.format("ALT/V: %dm / %dm/s", math.floor(alt), math.floor(spd))
end

local function render_mission_details(buf, mfd, source, app, active_idx, is_engine)
    local active_cp = is_engine and source and source.checkpoints and source.checkpoints[active_idx] or nil
    local st = source and source.state or "IDLE"
    local mode = is_engine and source and source.executionMode or nil
    local r11 = mode and string.format("STATE: %s (%s)", st, mode) or string.format("STATE: %s", st)
    draw_right_pane(buf, 11, r11, "4", "f")

    local r12 = "ACT  : " .. format_action_detail(active_cp, source, is_engine)
    draw_right_pane(buf, 12, r12, "0", "f")

    local r13
    if is_engine then
        local ctx = { mfd = mfd, enteredAtMs = source and source.enteredAtMs, nowMs = app and app.now_ms }
        r13 = "COND : " .. condition_evaluator.format_progress(active_cp, ctx, source and source.defaults)
    else
        r13 = string.format("RAD  : %3.1f m", source and source.arrivalRadius or 15.0)
    end
    draw_right_pane(buf, 13, r13, "8", "f")

    draw_right_pane(buf, 14, format_alt_spd_detail(active_cp, source, mfd, is_engine), "8", "f")
    draw_right_pane(buf, 15, format_distance_detail(active_cp, source, mfd, is_engine), "8", "f")
end

local function render_mission_pane(buf, mfd, source, app)
    local is_engine = type(source) == "table" and type(source.checkpoints) == "table"
    local total = 0
    local active_idx = 1
    if is_engine then
        total = #source.checkpoints
        active_idx = source.active_index or 1
    elseif type(source) == "table" and type(source.items) == "table" then
        total = #source.items
        active_idx = source.active_index or 1
    end

    draw_right_pane(buf, 3, format_mission_header(source, is_engine), "b", "f")

    local s_idx, e_idx = ui_renderer.compute_viewport(total, active_idx, 6)
    for slot = 1, 6 do
        local row_y = 3 + slot
        local item_idx = s_idx + slot - 1
        if item_idx >= s_idx and item_idx <= e_idx and item_idx <= total then
            local item = is_engine and source.checkpoints[item_idx] or source.items[item_idx]
            local line, col = format_checkpoint_row(item, item_idx, active_idx, is_engine)
            draw_right_pane(buf, row_y, line, col, "f")
        else
            draw_right_pane(buf, row_y, "", "8", "f")
        end
    end

    draw_text(buf, 10, 26, "|", "7", "f")
    draw_right_pane(buf, 10, string.rep("-", 25), "7", "f")

    render_mission_details(buf, mfd, source, app, active_idx, is_engine)
end

local function render_footer(buf, app)
    local sep = string.rep("-", 25) .. "+" .. string.rep("-", 25)
    draw_text(buf, 16, 1, sep, "7", "f")
    local banner = pad("MSG: " .. (app and app.banner or "SYSTEM READY"), W)
    draw_text(buf, 17, 1, banner, "0", "7")
    local hotkeys = "[X]STOP [H]HOLD [R]RTH [L]LAND [A]ARM [T]TAKEOFF"
    draw_text(buf, 18, 1, pad(hotkeys, W), "4", "f")

    local mode = app and app.input_mode or "NAV"
    local prompt = (mode == "NAV") and "CMD> [HOTKEY MODE - Press / or Enter to type]" or ("CMD> " .. (app and app.input_buffer or ""))
    draw_text(buf, 19, 1, pad(prompt, W), (mode == "CLI") and "e" or "8", "f")
end

function ui_renderer.render_screen(buf, mfd_state, source_data, app_state)
    for y = 3, 15 do
        draw_text(buf, y, 26, "|", "7", "f")
    end
    render_header(buf, mfd_state, app_state)
    render_hud_pane(buf, mfd_state, app_state)
    render_mission_pane(buf, mfd_state, source_data, app_state)
    render_footer(buf, app_state)
end

function ui_renderer.flush_buffer(buf, term_obj)
    local t = term_obj or term
    if not t or not t.blit then return end
    for y = 1, H do
        t.setCursorPos(1, y)
        t.blit(buf.text[y], buf.fg[y], buf.bg[y])
    end
end

return ui_renderer
