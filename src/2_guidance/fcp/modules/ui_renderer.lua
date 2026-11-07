-- src/modules/ui_renderer.lua
local ui_renderer = {}

function ui_renderer.format_line(text, pad_len)
    local len = pad_len or 51
    local str = tostring(text or "")
    if #str > len then
        return string.sub(str, 1, len)
    end
    return str .. string.rep(" ", len - #str)
end

local function draw_row(win, row_idx, text, fg_char, bg_char)
    if not win or not win.setCursorPos or not win.blit then return end
    local line = ui_renderer.format_line(text, 51)
    local fg = string.rep(fg_char or "0", 51)
    local bg = string.rep(bg_char or "f", 51)
    win.setCursorPos(1, row_idx)
    win.blit(line, fg, bg)
end

local function render_section_1(win, state)
    local ch = state and state.channel and state.channel.baseChannel or 10060
    local ch_st = state and state.channel and state.channel.status or "INIT"
    local fsm_st = state and state.fsm and state.fsm.current_state or "BOOT_INIT"
    draw_row(win, 1, string.format("FCP NODE-04 | VECTORED_VTOL | CH:%d [%s]", ch, ch_st), "0", "7")
    draw_row(win, 2, "---------------------------------------------------", "8", "f")
    draw_row(win, 3, string.format("STATE: %s | ENV: %s", fsm_st, state and state.envelope or "STRICT_LEVEL"), "0", "f")
end

local function render_section_2(win, state)
    local nav = state and state.nav or {}
    local p = nav.pos or { x = 0, y = 64, z = 0 }
    local att = nav.attitude or { pitch = 0, roll = 0, heading = 0 }
    draw_row(win, 4, string.format("POS: X=%.1f Y=%.1f Z=%.1f", p.x, p.y, p.z), "0", "f")
    draw_row(win, 5, string.format("GS: %.1f m/s | HDOP: %.1f", nav.groundSpeed or 0, nav.hdop or 1.0), "0", "f")
    draw_row(win, 6, string.format("ATT: P=%.1f R=%.1f Y=%.1f", att.pitch, att.roll, att.heading), "0", "f")
    draw_row(win, 7, "---------------------------------------------------", "8", "f")
end

local function render_section_3(win, state)
    local prof = state and state.profile or {}
    local prof_str = prof.profile and prof.profile.controllabilityStatus or "UNCALIB"
    local sway_str = prof.swayTotalLoss and "TOTAL_LOSS" or "OK"
    local fuel_pct = math.floor((state and state.nav and state.nav.fuel or 1.0) * 100)
    local core_str = (state and state.nav and state.nav.coreAlive) and "ALIVE" or "TIMEOUT"
    draw_row(win, 8, string.format("6DOF PROFILE: %s", prof_str), "0", "f")
    draw_row(win, 9, string.format("SWAY: %s | CORE: %s", sway_str, core_str), "0", "f")
    draw_row(win, 10, string.format("FUEL: %d%% | AUTH: %s", fuel_pct, state and state.operator and state.operator.authority or "PILOT"), "0", "f")
    draw_row(win, 11, "---------------------------------------------------", "8", "f")
end

local function render_section_4(win, state)
    local fac = state and state.facility or {}
    local pad = fac.activePadId or "NONE"
    local atc = fac.atcStatus or "STANDBY"
    draw_row(win, 12, string.format("PAD: %s | MOB: %s | ATC: %s", pad, fac.padMobility or "STATIC", atc), "0", "f")
    draw_row(win, 13, "---------------------------------------------------", "8", "f")
    draw_row(win, 14, "ALERT BANNER:", "d", "f")
    draw_row(win, 15, state and state.operator and state.operator.latestAlertBanner or "ALL_SYSTEMS_NOMINAL", "e", "f")
    draw_row(win, 16, "---------------------------------------------------", "8", "f")
    draw_row(win, 17, string.format("TICK: %d | STATUS: ACTIVE", state and state.tick or 0), "0", "f")
    draw_row(win, 18, "CC:TWEAKED CLOSED-LOOP GUIDANCE", "7", "f")
    draw_row(win, 19, "PRESS ANY KEY FOR DIAGNOSTICS", "8", "f")
end

function ui_renderer.render(win, state)
    render_section_1(win, state)
    render_section_2(win, state)
    render_section_3(win, state)
    render_section_4(win, state)
    return true
end

return ui_renderer
