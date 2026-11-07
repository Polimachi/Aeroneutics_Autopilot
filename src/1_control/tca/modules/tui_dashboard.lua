-- Terminal TUI Status Dashboard for TCA
local tui_dashboard = {}

--- Render top header bar containing group ID and status
function tui_dashboard.render_header(groupId, busType, isCommOk, mode)
    local gId = tostring(groupId or "THR_MAIN_L")
    local bus = tostring(busType or "WIRED")
    local commStr = isCommOk and "OK" or "ERR"
    return string.format("TCA CONSOLE | %s | %s | WATCHDOG: %s", gId, bus, commStr)
end

--- Render a visual ASCII bar for a given signal value
function tui_dashboard.render_bar(signal, maxSignal, width)
    local sig = math.max(0, math.min(maxSignal or 15, tonumber(signal) or 0))
    local maxSig = math.max(1, tonumber(maxSignal) or 15)
    local w = math.max(5, tonumber(width) or 10)
    local filled = math.floor((sig / maxSig) * w + 0.5)
    local empty = w - filled
    local pct = math.floor((sig / maxSig) * 100)
    local bar = "[" .. string.rep("=", filled) .. string.rep(" ", empty) .. "]"
    return string.format("%s %2d/%d (%d%%)", bar, sig, maxSig, pct)
end

--- Render mode and signal status line
function tui_dashboard.render_status_line(mode, sig, boostedSig, devCount)
    local m = tostring(mode or "REDSTONE")
    local count = tonumber(devCount) or 0
    local raw = tonumber(sig) or 0
    local b = tonumber(boostedSig) or raw
    if m == "API" then
        local devTag = count == 0 and "NO DEV" or string.format("%d DEV", count)
        return string.format("MODE: API (%s) | SIG: %d -> %d (BOOSTED)", devTag, raw, b)
    else
        return string.format("MODE: REDSTONE | SIG: %d (DIRECT PASS-THROUGH)", raw)
    end
end

--- Format single actuator row
function tui_dashboard.format_actuator_row(idx, item, ratio)
    if not item then
        return string.format("#%-2d (None)       -         -", idx)
    end
    local name = tostring(item.name or "N/A"):sub(1, 10)
    local meth = tostring(item.method or "N/A"):sub(1, 9)
    local outStr
    local r = tonumber(ratio) or 0.0
    if meth == "setSpeed" or meth == "setTargetSpeed" then
        outStr = string.format("%5.1f RPM (%3.0f%%)", r * 256, r * 100)
    elseif meth == "setAnalogOutput" then
        outStr = string.format("%2d RS (15 max)", math.floor(r * 15 + 0.5))
    else
        outStr = string.format("%4.2f Ratio (%3.0f%%)", r, r * 100)
    end
    return string.format("#%-2d %-10s %-9s %s", idx, name, meth, outStr)
end

--- Render diagnostics summary lines
function tui_dashboard.get_diagnostic_lines(groupId, busChannel, isOk)
    local gId = tostring(groupId or "THR_MAIN_L")
    local chan = tostring(busChannel or "top")
    local stat = isOk and "OPERATIONAL" or "COMM_DEGRADED"
    local wd = isOk and "300ms OK" or "TIMEOUT/ERR"
    return {
        string.format("PROTOCOL : ICD v1.9.5 (Raw)   BUS CHANNEL: %-8s", chan),
        string.format("GROUP ID : %-16s  WATCHDOG   : %-10s", gId, wd),
        string.format("STATUS   : %-16s  FAILSAFE   : READY (0 CUT)", stat)
    }
end

--- Render full TUI dashboard with VAC link status and live log stream
function tui_dashboard.render_full_screen(cfg, daemon, w, h)
    if not term or not term.setCursorPos then return end
    local width = w or 51
    local gId = cfg and cfg.groupId or "THR_MAIN_L"
    local domain = cfg and cfg.aircraftDomainId or "AIRCRAFT_01"
    local airN = cfg and cfg.aircraftIndexN or 1
    local baseCh = cfg and cfg.baseChannel or 10000
    local mode = cfg and cfg.interactionMode or "REDSTONE"
    local actChan = cfg and cfg.channels and cfg.channels.thrustActuation or (baseCh + 10)
    local isOk = daemon and daemon.sentinel and not daemon.sentinel.isExpired
    local link = daemon and daemon.linkStatus or "IDLE"
    local sig = daemon and daemon.adapterState and daemon.adapterState.lastSignal or 0
    local act = daemon and daemon.adapterState and #(daemon.adapterState.peripherals or {}) or 0
    local tot = cfg and cfg.nominalActuatorCount or 4
    local border = "+" .. string.rep("-", width - 2) .. "+"

    local lines = {
        [1] = tui_dashboard.render_header(gId, link, isOk, mode),
        [2] = border,
        [3] = string.format("AIRFRAME : %-14s (AirN=%d, Base=%d)", domain, airN, baseCh),
        [4] = string.format("MODE: %-8s | DEV: %d/%d | ACT CH: %d", mode, act, tot, actChan),
        [5] = "THRUST   : " .. tui_dashboard.render_bar(sig, 15, 12),
        [6] = "+-- [CONTROLS] " .. string.rep("-", math.max(0, width - 17)) .. "+",
        [7] = "[S] Setup/Profile   [D] Ping VAC   [T] Terminate",
        [8] = "+-- [VAC LINK LOG STREAM (LAST 5)] " .. string.rep("-", math.max(0, width - 37)) .. "+"
    }
    local logInner = math.max(10, width - 4)
    for i = 1, 5 do
        local logItem = daemon and daemon.logBuffer and daemon.logBuffer[i] or ""
        lines[8 + i] = string.format("| %-" .. logInner .. "s |", logItem:sub(1, logInner))
    end
    lines[14] = border

    for y = 1, 14 do
        term.setCursorPos(1, y)
        local pad = width - #lines[y]
        term.write(lines[y] .. (pad > 0 and string.rep(" ", pad) or ""))
    end
end

return tui_dashboard
