-- src/3_planning/amm/modules/ui_renderer.lua
-- AMM 51x19 Dual-Pane TUI Buffer Renderer (0-Flicker term.blit)
local ui_renderer = {}

local W, H = 51, 19

local function pad(str, len, align_right)
    local s = tostring(str or "")
    if #s > len then return string.sub(s, 1, len) end
    local spaces = string.rep(" ", len - #s)
    if align_right then return spaces .. s end
    return s .. spaces
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

local function render_hud_pane(buf, mfd)
    draw_text(buf, 3, 2, "[HUD INSTRUMENTS]", "d", "f")
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
end

local function render_queue_pane(buf, q)
    local items = q and q.items or {}
    local active_idx = q and q.active_index or 1
    local q_title = string.format("[MISSION QUEUE] (%d/%d)", math.min(active_idx, #items), #items)
    draw_text(buf, 3, 27, q_title, "b", "f")

    for i = 1, 6 do
        local wp = items[i]
        local row_y = 3 + i
        if wp then
            local marker = (i == active_idx) and "*" or (wp.completed and "O" or " ")
            local fac = wp.facilityId and (" " .. wp.facilityId) or ""
            local wp_line = string.format("%s WP%d:[%4d,%4d]%s", marker, wp.id, math.floor(wp.x), math.floor(wp.z), fac)
            local col = (i == active_idx) and "4" or (wp.completed and "8" or "0")
            draw_text(buf, row_y, 27, pad(wp_line, 24), col, "f")
        else
            draw_text(buf, row_y, 27, pad("", 24), "8", "f")
        end
    end
    draw_text(buf, 10, 26, string.rep("-", 25), "7", "f")
    draw_text(buf, 11, 27, string.format("STATE  : %s", pad(q and q.state or "IDLE", 12)), "4", "f")
    draw_text(buf, 12, 27, string.format("RAD    : %3.1f m", q and q.arrivalRadius or 15.0), "8", "f")
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

function ui_renderer.render_screen(buf, mfd_state, queue_data, app_state)
    for y = 3, 15 do
        draw_text(buf, y, 26, "|", "7", "f")
    end
    render_header(buf, mfd_state, app_state)
    render_hud_pane(buf, mfd_state)
    render_queue_pane(buf, queue_data)
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
