-- ASA (Aerodynamic Surface Adapter) 51x19 TUI Diagnostic Dashboard
local tui_dashboard = {}

function tui_dashboard.clear_screen(surf)
    local t = surf or term
    if not t then return end
    if t.setBackgroundColor and colors and colors.black then pcall(t.setBackgroundColor, colors.black) end
    if t.setTextColor and colors and colors.white then pcall(t.setTextColor, colors.white) end
    if t.clear then pcall(t.clear) end
    if t.setCursorPos then pcall(t.setCursorPos, 1, 1) end
end

function tui_dashboard.restore_screen(surf)
    local t = surf or term
    if not t then return end
    if t.setBackgroundColor and colors and colors.black then pcall(t.setBackgroundColor, colors.black) end
    if t.setTextColor and colors and colors.white then pcall(t.setTextColor, colors.white) end
    if t.clear then pcall(t.clear) end
    if t.setCursorPos then pcall(t.setCursorPos, 1, 1) end
end

local function draw_line(surf, y, text, fg, bg)
    if not surf or not surf.setCursorPos then return end
    surf.setCursorPos(1, y)
    local width = 51
    local t = tostring(text or "")
    if #t > width then
        t = t:sub(1, width)
    elseif #t < width then
        t = t .. string.rep(" ", width - #t)
    end
    local fgStr = type(fg) == "string" and fg or string.rep("0", width)
    local bgStr = type(bg) == "string" and bg or string.rep("f", width)
    if #fgStr < width then fgStr = fgStr .. string.rep("0", width - #fgStr) end
    if #bgStr < width then bgStr = bgStr .. string.rep("f", width - #bgStr) end
    fgStr = fgStr:sub(1, width)
    bgStr = bgStr:sub(1, width)

    if surf.blit then
        surf.blit(t, fgStr, bgStr)
    elseif surf.write then
        surf.write(t)
    end
end

function tui_dashboard.render_dashboard(surf, state, cfg)
    local t = surf or term
    if not t or not t.setCursorPos then return end

    state = state or {}
    cfg = cfg or {}

    local domain = tostring(cfg.aircraftDomainId or "AIRCRAFT_01")
    local podId = tostring(cfg.podId or "WAP_L")
    local base = tonumber(cfg.baseChannel) or 10000
    local actChan = (cfg.channels and cfg.channels.surfaceActuation) or (base + 11)

    local fsm = tostring(state.fsm or "READY_DISARMED")
    local wdText = state.watchdogExpired and "TIMEOUT/FAILSAFE" or "300ms OK"
    local tick = tonumber(state.tickCount) or 0
    local statusMsg = tostring(state.status or (state.watchdogExpired and "SAFE GLIDE ACTIVE" or "NOMINAL"))

    local defs = state.deflections or {}
    local modes = state.modes or {}
    local sats = state.saturated or {}

    local surfaces = {
        { name = "ELEVATOR (Pitch) ", key = "elevator" },
        { name = "L.AILERON (Roll) ", key = "leftAileron" },
        { name = "R.AILERON (Roll) ", key = "rightAileron" },
        { name = "RUDDER (Yaw)     ", key = "rudder" },
        { name = "FLAPS (Lift)     ", key = "flaps" }
    }

    -- 19-line blit layout for 51x19 display
    -- Line 1: Header
    draw_line(t, 1, string.format(" ASA Surface Cluster | Node 06 | %-8s | B:%5d ", domain:sub(1, 8), base))
    -- Line 2: Border
    draw_line(t, 2, "+-------------------------------------------------+")
    -- Line 3: System overview
    draw_line(t, 3, string.format("| AIRFRAME: %-11s | POD: %-7s | B: %-5d |", domain:sub(1, 11), podId:sub(1, 7), base))
    -- Line 4: Table header divider
    draw_line(t, 4, "+---------------------+----------+--------+-------+")
    -- Line 5: Surface header
    draw_line(t, 5, "| SURFACE             | MODE     | DEFLEC | SAT   |")
    -- Line 6: Divider
    draw_line(t, 6, "+---------------------+----------+--------+-------+")

    -- Lines 7-11: 5 surfaces
    for i, s in ipairs(surfaces) do
        local m = tostring(modes[s.key] or "RS")
        local d = tonumber(defs[s.key]) or 0.0
        local isSat = sats[s.key] == true
        local satStr = isSat and "SAT" or "OK"
        local defStr = (m == "RS") and string.format("%2d RS", math.floor(math.abs(d) * 15 + 0.5))
                                   or string.format("%+5.1f*", d * 30.0)
        draw_line(t, 6 + i, string.format("| %-19s | %-8s | %-6s | %-5s |", s.name, m:sub(1, 8), defStr:sub(1, 6), satStr))
    end

    -- Line 12: Divider
    draw_line(t, 12, "+---------------------+----------+--------+-------+")
    -- Line 13: Subtitle
    draw_line(t, 13, "| [SYSTEM STATUS & WATCHDOG SENTINEL]             |")
    -- Line 14: FSM and Watchdog
    draw_line(t, 14, string.format("| FSM: %-14s | WATCHDOG: %-15s |", fsm:sub(1, 14), wdText:sub(1, 15)))
    -- Line 15: Bus info & Ticks
    draw_line(t, 15, string.format("| BUS: CH %-5d       | TICKS: %-8d | LINK: OK |", actChan, tick))
    -- Line 16: Divider
    draw_line(t, 16, "+-------------------------------------------------+")
    -- Line 17: Status line
    draw_line(t, 17, string.format("| STATUS: %-40s|", statusMsg:sub(1, 40)))
    -- Line 18: Divider
    draw_line(t, 18, "+-------------------------------------------------+")
    -- Line 19: Footer
    draw_line(t, 19, string.format(" [T/Q] Terminate       [R] Rescan     Tick: %05d ", tick))
end

return tui_dashboard
