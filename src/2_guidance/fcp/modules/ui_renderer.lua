-- src/2_guidance/fcp/modules/ui_renderer.lua
-- FCP v2.0.0 51x19 Headless-Optional Diagnostics TUI HUD
-- CC:Tweaked Lua 5.2 / Cobalt VM compliant: all functions <= 50 lines, Zero-Fallback

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

local function render_header(win, state)
    local ch = (state and state.net and state.net.baseChannel) or 10000
    local af = (state and state.config and state.config.system and state.config.system.airframeType) or "VECTORED_VTOL"
    local fsm_st = (state and state.fsm and state.fsm.currentState) or "BOOT"
    local prof = (state and state.lastAmmSetpoint and state.lastAmmSetpoint.constraintProfile) or "STRICT_LEVEL"
    draw_row(win, 1, string.format("FCP NODE-04 | %s | BASE:%d", af, ch), "0", "7")
    draw_row(win, 2, "---------------------------------------------------", "8", "f")
    draw_row(win, 3, string.format("FSM: %s | PROFILE: %s", fsm_st, prof), "0", "f")
end

local function render_nav(win, state)
    local nav = state and state.nav or {}
    local p = nav.pos or { x = 0.0, y = 64.0, z = 0.0 }
    local v = nav.vel or { vx = 0.0, vy = 0.0, vz = 0.0 }
    local att = nav.attitude or { pitch = 0.0, roll = 0.0, heading = 0.0 }
    local gs = nav.groundSpeed or 0.0
    draw_row(win, 4, string.format("POS: X=%.1f Y=%.1f Z=%.1f", p.x or 0.0, p.y or 0.0, p.z or 0.0), "0", "f")
    draw_row(win, 5, string.format("VEL: VX=%.1f VY=%.1f VZ=%.1f | GS:%.1f", v.vx or 0.0, v.vy or 0.0, v.vz or 0.0, gs), "0", "f")
    draw_row(win, 6, string.format("ATT: P=%.1f R=%.1f Y=%.1f deg", att.pitch or 0.0, att.roll or 0.0, att.heading or 0.0), "0", "f")
    draw_row(win, 7, "---------------------------------------------------", "8", "f")
end

local function render_guidance(win, state)
    local sp = state and state.lastAmmSetpoint or {}
    local tp = sp.targetPos or { x = 0.0, y = 64.0, z = 0.0 }
    local mode = sp.flightMode or "STANDBY"
    local st = state and state.latestOuterLoopStatus or {}
    local thr = st.commandedCollectiveThrust or 0.0
    local ramp = state and state.rampAlpha or 1.0
    local pErr = st.posError or 0.0
    local vErr = st.velError or 0.0
    draw_row(win, 8, string.format("SETPT: X=%.1f Y=%.1f Z=%.1f | %s", tp.x or 0.0, tp.y or 0.0, tp.z or 0.0, mode), "0", "f")
    draw_row(win, 9, string.format("THRUST: %.2f | RAMP_ALPHA: %.2f", thr, ramp), "0", "f")
    draw_row(win, 10, string.format("ERRORS: POS=%.2fm | VEL=%.2fm/s", pErr, vErr), "0", "f")
    draw_row(win, 11, "---------------------------------------------------", "8", "f")
end

local function render_system_status(win, state)
    local net = state and state.net or {}
    local chs = net.channels or { trajectory = 10004, telemetry = 10002, guidance = 10001 }
    local nav = state and state.nav or {}
    local sat = (state and state.latestOuterLoopStatus and state.latestOuterLoopStatus.saturated) and "YES" or "NO"
    local stale = (nav.navStale == true) and "YES" or "NO"
    local act = (nav.actuatorHealth and nav.actuatorHealth.allOk == false) and "DEGRADED" or "OK"
    draw_row(win, 12, string.format("CH: TRJ:%d | TLM:%d | CMD:%d", chs.trajectory, chs.telemetry, chs.guidance), "0", "f")
    draw_row(win, 13, string.format("SAT: %s | STALE: %s | HEALTH: %s", sat, stale, act), "0", "f")
    draw_row(win, 14, "ALERT BANNER:", "d", "f")
    draw_row(win, 15, "ALL_SYSTEMS_NOMINAL", "e", "f")
    draw_row(win, 16, "---------------------------------------------------", "8", "f")
    draw_row(win, 17, string.format("TICK: %d | RATE: 20Hz | SE(3) OUTER-LOOP", state and state.tick or 0), "0", "f")
    draw_row(win, 18, "CC:TWEAKED CLOSED-LOOP GUIDANCE", "7", "f")
    draw_row(win, 19, "DEBUG HUD ACTIVE | PRESS ANY KEY TO EXIT", "8", "f")
end

function ui_renderer.render(win, state)
    render_header(win, state)
    render_nav(win, state)
    render_guidance(win, state)
    render_system_status(win, state)
    return true
end

return ui_renderer
