-- src/0_infra/gcs/modules/ui_renderer.lua
-- 51x19 Dual-Pane TUI Console Buffer Renderer (0-Flicker term.blit)
-- UAFS Ecosystem GCS v1.0.0

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

local function render_header(buf, active_craft, fleet_summary)
    local count = fleet_summary and #fleet_summary or 0
    local target_id = active_craft and active_craft.domainId or "NONE"
    local head = string.format(" GCS CH50000 | CRAFTS: %d | TARGET: %s", count, target_id)
    draw_text(buf, 1, 1, pad(head, W), "0", "9")
    local div = string.rep("-", 25) .. "+" .. string.rep("-", 25)
    draw_text(buf, 2, 1, div, "7", "f")
end

local function render_left_hud(buf, active_craft)
    draw_text(buf, 3, 2, "[ACTIVE CRAFT HUD]", "d", "f")
    if not active_craft then
        draw_text(buf, 5, 2, "NO ACTIVE CRAFT SELECTED", "8", "f")
        return
    end

    local telem = active_craft.telemetry or {}
    local att = telem.attitude or {}
    local dyn = telem.dynamics or {}

    draw_text(buf, 4, 2, string.format("Domain: %-15s", active_craft.domainId), "0", "f")
    draw_text(buf, 5, 2, string.format("FSM   : %-15s", telem.fsmState or "NO_DATA"), "4", "f")
    draw_text(buf, 6, 2, string.format("Pitch : %+5.1f deg", att.pitch or 0.0), "0", "f")
    draw_text(buf, 7, 2, string.format("Roll  : %+5.1f deg", att.roll or 0.0), "0", "f")
    draw_text(buf, 8, 2, string.format("Yaw   : %5.1f deg", att.heading or 0.0), "0", "f")
    draw_text(buf, 9, 2, string.format("Alt Y : %6.1f m", dyn.altitudeY or 0.0), "0", "f")
    draw_text(buf, 10, 2, string.format("VSpd  : %+5.1f m/s", dyn.verticalSpeed or 0.0), "0", "f")
    draw_text(buf, 11, 2, string.format("GSpd  : %5.1f m/s", dyn.groundSpeed or 0.0), "0", "f")

    local fuel_pct = math.floor((telem.fuel or 0.0) * 100)
    local fuel_bars = math.min(10, math.max(0, math.floor(fuel_pct / 10)))
    local fuel_str = string.format("Fuel  : [%s%s] %2d%%", string.rep("|", fuel_bars), string.rep("-", 10 - fuel_bars), fuel_pct)
    local fuel_col = fuel_pct < 20 and "e" or (fuel_pct < 40 and "1" or "5")
    draw_text(buf, 12, 2, fuel_str, fuel_col, "f")

    local link_str = active_craft.isStale and "STALE" or "ONLINE"
    local link_col = active_craft.isStale and "e" or "5"
    draw_text(buf, 13, 2, string.format("Link  : %-8s", link_str), link_col, "f")

    local af = active_craft.airframeType or (telem and telem.airframeType)
    if af then
        local icon = (af == "ADVANCED_VTOL" and "^V^") or (af == "VECTORED_VTOL" and ">V<") or (af == "WINGED_VTOL" and "-V-") or "[A]"
        draw_text(buf, 14, 2, string.format("Type  : %s %-8s", icon, af), "b", "f")
    end
end

local function render_right_fleet(buf, active_craft, fleet_summary)
    draw_text(buf, 3, 27, "[REGISTERED FLEET]", "b", "f")
    local list = fleet_summary or {}
    for i = 1, 13 do
        local craft = list[i]
        local row_y = 3 + i
        if craft then
            local is_active = active_craft and (active_craft.domainId == craft.domainId)
            local marker = is_active and "*" or " "
            local status_ch = craft.isStale and "!" or " "
            local line = string.format("%s#%02d %-10s[%5d]%s", marker, craft.blockId or i, craft.domainId, craft.baseChannel or 0, status_ch)
            local col = is_active and "4" or (craft.isStale and "e" or "0")
            draw_text(buf, row_y, 27, pad(line, 24), col, "f")
        else
            draw_text(buf, row_y, 27, pad("", 24), "8", "f")
        end
    end
end

local function render_footer(buf, status_msg)
    local sep = string.rep("-", 25) .. "+" .. string.rep("-", 25)
    draw_text(buf, 16, 1, sep, "7", "f")
    local banner = pad("Status: " .. (status_msg or "ALL SYSTEMS NOMINAL"), W)
    draw_text(buf, 17, 1, banner, "0", "7")
    local c2_bar = "C2: [A]rm [T]akeoff [H]old [R]th [L]and [X]E-Stop"
    draw_text(buf, 18, 1, pad(c2_bar, W), "e", "f")
    local nav_bar = "Nav: [Tab]NextCraft [C]hannelReg [Q]uit"
    draw_text(buf, 19, 1, pad(nav_bar, W), "4", "f")
end

function ui_renderer.render_screen(buf, active_craft, fleet_summary, status_msg)
    for y = 3, 15 do
        draw_text(buf, y, 26, "|", "7", "f")
    end
    render_header(buf, active_craft, fleet_summary)
    render_left_hud(buf, active_craft)
    render_right_fleet(buf, active_craft, fleet_summary)
    render_footer(buf, status_msg)
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
