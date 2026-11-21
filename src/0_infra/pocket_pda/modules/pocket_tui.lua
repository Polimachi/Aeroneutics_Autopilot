-- src/0_infra/pocket_pda/modules/pocket_tui.lua
-- 26x20 3-Tab Pocket Computer TUI Buffer Renderer (0-Flicker term.blit)

local pocket_tui = {}

pocket_tui.SCREEN_W = 26
pocket_tui.SCREEN_H = 20

local NODE_NAMES = { "AMM", "VAS", "GCS", "ALN", "FDR" }

local LINK_COLORS = {
    STRONG = "5",
    GOOD = "4",
    WEAK = "1",
    LOST = "e",
}

local function clamp_width(buf)
    return (type(buf) == "table" and buf.width) or pocket_tui.SCREEN_W
end

local function clamp_height(buf)
    return (type(buf) == "table" and buf.height) or pocket_tui.SCREEN_H
end

--- Create a blank 26x20 (or w x h) TUI blit buffer.
function pocket_tui.create_buffer(w, h)
    local width = w or pocket_tui.SCREEN_W
    local height = h or pocket_tui.SCREEN_H
    local buf = { width = width, height = height, text = {}, fg = {}, bg = {} }
    local blank_t = string.rep(" ", width)
    local blank_f = string.rep("0", width)
    local blank_b = string.rep("f", width)
    for y = 1, height do
        buf.text[y] = blank_t
        buf.fg[y] = blank_f
        buf.bg[y] = blank_b
    end
    return buf
end

--- Clamp or right-pad text to exact character width.
function pocket_tui.format_line(text, width)
    local w = width or pocket_tui.SCREEN_W
    local s = string.gsub(tostring(text or ""), "[\r\n\t]", " ")
    if #s > w then
        return string.sub(s, 1, w)
    end
    if #s < w then
        return s .. string.rep(" ", w - #s)
    end
    return s
end

local function set_row(buf, y, text, fg_char, bg_char)
    local h = clamp_height(buf)
    if y < 1 or y > h then return end
    local w = clamp_width(buf)
    buf.text[y] = pocket_tui.format_line(text, w)
    buf.fg[y] = string.rep(fg_char or "0", w)
    buf.bg[y] = string.rep(bg_char or "f", w)
end

local function write_span(buf, y, x, text, fg_char, bg_char)
    local w, h = clamp_width(buf), clamp_height(buf)
    if y < 1 or y > h or x < 1 or x > w then return end
    local s = string.gsub(tostring(text or ""), "[\r\n\t]", " ")
    if #s == 0 then return end
    if x + #s - 1 > w then
        s = string.sub(s, 1, w - x + 1)
    end
    local len = #s
    local fc = string.rep(fg_char or "0", len)
    local bc = string.rep(bg_char or "f", len)
    buf.text[y] = string.sub(buf.text[y], 1, x - 1) .. s .. string.sub(buf.text[y], x + len)
    buf.fg[y] = string.sub(buf.fg[y], 1, x - 1) .. fc .. string.sub(buf.fg[y], x + len)
    buf.bg[y] = string.sub(buf.bg[y], 1, x - 1) .. bc .. string.sub(buf.bg[y], x + len)
end

local function fuel_bar_str(fuel)
    local f = math.max(0.0, math.min(1.0, tonumber(fuel) or 0.0))
    local filled = math.floor(f * 5 + 0.5)
    return string.rep("|", filled) .. string.rep(".", 5 - filled), f
end

local function render_header(buf, net, hud, active_tab)
    local w = clamp_width(buf)
    local n = tonumber(net.aircraftIndexN) or 1
    local base_ch = tonumber(net.baseChannel) or (10000 + (math.max(1, n) - 1) * 40)
    local dom = tostring(net.targetDomainId or "AIRCRAFT_01")
    set_row(buf, 1, string.format("N:%03d CH%d %s", n, base_ch, dom), "0", "b")

    local lq = (type(hud.linkQuality) == "table") and hud.linkQuality or {}
    local tier = tostring(lq.tier or "LOST")
    local dist = tostring(lq.distanceStr or "---")
    local lnk_str = tier .. " " .. dist
    local fsm = tostring(hud.fsmState or "UNKNOWN")
    local left_w = math.max(1, w - #lnk_str - 1)
    set_row(buf, 2, pocket_tui.format_line("FSM:" .. fsm, left_w) .. " " .. lnk_str, "0", "f")
    write_span(buf, 2, w - #lnk_str + 1, lnk_str, LINK_COLORS[tier] or "e", "f")

    set_row(buf, 3, "TAB:[1]HUD  [2]ALN [3]FDR", "8", "f")
    if active_tab == "ALIGN" then
        write_span(buf, 3, 13, "[2]ALN", "f", "9")
    elseif active_tab == "FDR" then
        write_span(buf, 3, 20, "[3]FDR", "f", "9")
    else
        write_span(buf, 3, 5, "[1]HUD", "f", "9")
    end
end

local function render_hud_nodes(buf, y, hud)
    set_row(buf, y, "", "8", "f")
    local nodes = (type(hud.nodes) == "table") and hud.nodes or {}
    local col = 1
    for _, name in ipairs(NODE_NAMES) do
        local online = type(nodes[name]) == "table" and nodes[name].online == true
        local badge = name .. (online and "*" or ".")
        write_span(buf, y, col, badge, online and "5" or "8", "f")
        col = col + 5
    end
end

local function render_hud_body(buf, net, hud, link, status_msg)
    local alt = tonumber(hud.altitudeY) or 0.0
    local vspd = tonumber(hud.verticalSpeed) or 0.0
    local spd = tonumber(hud.groundSpeed) or 0.0
    set_row(buf, 5, string.format("ALT:%6.1fm VSPD:%+5.1fm/s", alt, vspd), "0", "f")

    local bar, f_ratio = fuel_bar_str(hud.fuel)
    set_row(buf, 6, string.format("SPD:%5.1fm/s FUEL:[%s]", spd, bar), "0", "f")
    local f_col = (f_ratio < 0.2) and "e" or ((f_ratio < 0.4) and "1" or "5")
    write_span(buf, 6, 20, bar, f_col, "f")

    local pitch = tonumber(hud.pitch) or 0.0
    local roll = tonumber(hud.roll) or 0.0
    local yaw = tonumber(hud.yaw) or 0.0
    set_row(buf, 7, string.format("P:%+5.1f R:%+5.1f Y:%05.1f", pitch, roll, yaw), "0", "f")

    local mode = string.sub(tostring(hud.flightMode or "---"), 1, 9)
    local src = string.sub(tostring(hud.activeSource or "---"), 1, 7)
    set_row(buf, 8, string.format("MOD:%-9s SRC:%-7s", mode, src), "0", "f")

    local act_s = hud.actuatorOk and "OK" or "BAD"
    local sen_s = hud.sensorOk and "OK" or "BAD"
    local pbit = (type(hud.lastPbitReport) == "table" and hud.lastPbitReport.overallStatus) or "---"
    set_row(buf, 9, string.format("ACT:%-3s SEN:%-3s PBIT:%-4s", act_s, sen_s, string.sub(tostring(pbit), 1, 4)), "0", "f")

    local count = (type(hud.discoveredOrder) == "table") and #hud.discoveredOrder or 0
    set_row(buf, 10, string.format("FLEET:%02d DISCOVERED", count), "3", "f")
    render_hud_nodes(buf, 11, hud)

    local fdr = (type(link.fdr) == "table") and link.fdr or {}
    local aln = (type(link.alignment) == "table") and link.alignment or {}
    set_row(buf, 12, string.format("FDR:%-8s N:%03d", tostring(fdr.mode or "LOGGING"), tonumber(fdr.boundIndexN) or 1), "0", "f")
    set_row(buf, 13, string.format("ALN:BAY%02d %-15s", tonumber(aln.bayId or net.hangarBayId) or 1, tostring(aln.fsmState or "STANDBY")), "0", "f")

    local alert_reason = (type(hud.lastAlert) == "table" and hud.lastAlert.reason) and ("ALT:" .. tostring(hud.lastAlert.reason)) or nil
    set_row(buf, 14, "STS:" .. tostring(alert_reason or status_msg or "NOMINAL"), alert_reason and "e" or "8", "f")
    local ack_sts = (type(hud.lastMissionAck) == "table" and hud.lastMissionAck.status) or "---"
    set_row(buf, 15, "ACK:" .. tostring(ack_sts), "8", "f")
    set_row(buf, 16, "CMD:" .. tostring(hud.lastCommand or "---"), "8", "f")
    set_row(buf, 17, "HUD:[A]RM [T]KOF [P]BIT", "3", "f")
end

local function render_align_body(buf, net, link, status_msg)
    local aln = (type(link.alignment) == "table") and link.alignment or {}
    local bay_id = tonumber(aln.bayId or net.hangarBayId) or 1
    local h_ch = tonumber(aln.baseHangarChannel or net.hangarBaseChannel) or (101 + (bay_id - 1) * 10)
    local craft_n = tonumber(aln.aircraftIndexN or net.aircraftIndexN) or 1
    local craft_dom = tostring(aln.targetCraftDomain or net.targetDomainId or "AIRCRAFT_01")
    local r2 = tonumber(aln.confidenceR2)
    local r2_str = r2 and string.format("%.3f", r2) or "---"

    set_row(buf, 5, string.format("BAY:%02d CH:%3d", bay_id, h_ch), "4", "f")
    set_row(buf, 6, string.format("CRAFT:N:%03d %s", craft_n, craft_dom), "0", "f")
    set_row(buf, 7, "FSM:" .. tostring(aln.fsmState or "STANDBY"), "0", "f")
    set_row(buf, 8, "STS:" .. tostring(aln.status or "IDLE"), "3", "f")
    set_row(buf, 9, "THR:" .. tostring(aln.activeThruster or "---"), "0", "f")
    set_row(buf, 10, "R2 :" .. r2_str, "5", "f")
    set_row(buf, 11, "CTL:" .. tostring(aln.controllabilityStatus or "---"), "5", "f")
    set_row(buf, 12, "CMD:" .. tostring(aln.lastCmd or "---"), "8", "f")
    set_row(buf, 13, "RSN:" .. tostring(aln.reason or "---"), "8", "f")
    set_row(buf, 14, "MSG:" .. tostring(status_msg or "---"), "8", "f")
    set_row(buf, 15, "", "0", "f")
    set_row(buf, 16, "[-]Bay [+] [B]ind [G]o", "3", "f")
    set_row(buf, 17, "[P]au [T]Rty [Y]Syn [A][K]", "3", "f")
end

local function render_fdr_body(buf, net, link, status_msg)
    local fdr = (type(link.fdr) == "table") and link.fdr or {}
    local pda_n = tonumber(net.aircraftIndexN) or 1
    local pda_base = tonumber(net.baseChannel) or (10000 + (math.max(1, pda_n) - 1) * 40)
    local fdr_n = tonumber(fdr.boundIndexN) or pda_n
    local fdr_base = tonumber(fdr.boundBaseChannel) or (10000 + (math.max(1, fdr_n) - 1) * 40)

    set_row(buf, 5, string.format("PDA N:%03d  CH:%5d", pda_n, pda_base + 9), "0", "f")
    set_row(buf, 6, string.format("FDR N:%03d  CH:%5d", fdr_n, fdr_base + 9), "4", "f")
    set_row(buf, 7, "MODE:" .. tostring(fdr.mode or "LOGGING"), "0", "f")
    set_row(buf, 8, "REC :" .. tostring(fdr.recordMode or "STREAMING"), "0", "f")
    set_row(buf, 9, "DOM :" .. tostring(fdr.boundDomainId or net.targetDomainId or "*"), "0", "f")
    set_row(buf, 10, "CMD :" .. tostring(fdr.lastCmd or "---"), "8", "f")
    set_row(buf, 11, "LINK: PASSIVE 0 tx", "5", "f")
    set_row(buf, 12, "STS :" .. tostring(status_msg or "---"), "8", "f")
    set_row(buf, 13, "[X] -> E_STOP + DUMP_NOW", "e", "f")
    set_row(buf, 14, "", "0", "f")
    set_row(buf, 15, "", "0", "f")
    set_row(buf, 16, "FDR:[B]ind [M]ode [D]ump", "3", "f")
    set_row(buf, 17, "[U]Exp [S]Roll [C]lear", "3", "f")
end

local function render_footer(buf)
    local div = string.rep("-", clamp_width(buf))
    set_row(buf, 4, div, "7", "f")
    set_row(buf, 18, div, "7", "f")
    set_row(buf, 19, "[X]ESTP+DMP [H]LD [R]RTB", "4", "f")
    write_span(buf, 19, 1, "[X]ESTP+DMP", "0", "e")
    set_row(buf, 20, "[L]LND [< >]N [Tab]F [Q]X", "3", "f")
    write_span(buf, 20, 22, "[Q]X", "1", "f")
end

--- Populate 26x20 blit buffer for active tab ("HUD" | "ALIGN" | "FDR").
function pocket_tui.render_screen(buf, view_model)
    local target = (type(buf) == "table" and buf.text and buf.fg and buf.bg) and buf or pocket_tui.create_buffer()
    local vm = (type(view_model) == "table") and view_model or {}
    local net = (type(vm.net) == "table") and vm.net or vm
    local hud = (type(vm.hud) == "table") and vm.hud or vm
    local link = (type(vm.link) == "table") and vm.link or vm
    local tab = tostring(vm.activeTab or "HUD")

    render_header(target, net, hud, tab)
    render_footer(target)
    if tab == "ALIGN" then
        render_align_body(target, net, link, vm.statusMsg)
    elseif tab == "FDR" then
        render_fdr_body(target, net, link, vm.statusMsg)
    else
        render_hud_body(target, net, hud, link, vm.statusMsg)
    end
    return target
end

--- Flush 26x20 buffer to CC:Tweaked terminal using term.setCursorPos and term.blit.
function pocket_tui.flush_buffer(buf, term_obj)
    local t = term_obj or term
    if type(buf) ~= "table" or not buf.text or not buf.fg or not buf.bg then
        return false
    end
    if type(t) ~= "table" or type(t.blit) ~= "function" or type(t.setCursorPos) ~= "function" then
        return false
    end
    local h = clamp_height(buf)
    for y = 1, h do
        t.setCursorPos(1, y)
        t.blit(buf.text[y], buf.fg[y], buf.bg[y])
    end
    return true
end

return pocket_tui
