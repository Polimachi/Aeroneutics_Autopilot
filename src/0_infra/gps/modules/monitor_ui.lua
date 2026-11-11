-- monitor_ui.lua - Advanced Monitor 4-Tab Visual GCS Dashboard
local radar_math = require("radar_math")

local monitor_ui = {}
local UI = {}
UI.__index = UI

local function padLine(text, fgChar, bgChar, width)
    local len = #text
    if len < width then
        local pad = string.rep(" ", width - len)
        return text .. pad, string.rep(fgChar, width), string.rep(bgChar, width)
    elseif len > width then
        return string.sub(text, 1, width), string.rep(fgChar, width), string.rep(bgChar, width)
    end
    return text, string.rep(fgChar, width), string.rep(bgChar, width)
end

function monitor_ui.new(opts)
    local self = setmetatable({}, UI)
    self.width = (opts and opts.width) or 79
    self.height = (opts and opts.height) or 36
    self.currentTab = 1
    return self
end

function UI:getTab()
    return self.currentTab
end

function UI:setTab(tabIdx)
    if tabIdx and tabIdx >= 1 and tabIdx <= 4 then
        self.currentTab = tabIdx
    end
end

function UI:handleTouch(x, y)
    if y == 1 or y == 2 then
        if x >= 1 and x <= 18 then self:setTab(1); return "TAB_SWITCH"
        elseif x >= 19 and x <= 36 then self:setTab(2); return "TAB_SWITCH"
        elseif x >= 37 and x <= 56 then self:setTab(3); return "TAB_SWITCH"
        elseif x >= 57 and x <= 76 then self:setTab(4); return "TAB_SWITCH"
        end
    elseif y >= 34 and y <= 36 then
        if x >= 3 and x <= 14 then return "ACTION_REFRESH"
        elseif x >= 17 and x <= 30 then return "ACTION_CALIBRATE"
        elseif x >= 33 and x <= 42 then return "ACTION_CLEAR"
        elseif x >= 45 and x <= 54 then return "ACTION_REFIT"
        end
    end
    return nil
end

local function renderHeader(mon, currentTab, w)
    local tabs = { " [1: OVERVIEW] ", " [2: CLIENTS] ", " [3: NODES] ", " [4: RADAR] " }
    local tStr, fStr, bStr = "", "", ""
    for i, title in ipairs(tabs) do
        tStr = tStr .. title
        local isAct = (i == currentTab)
        fStr = fStr .. string.rep(isAct and "0" or "7", #title)
        bStr = bStr .. string.rep(isAct and "4" or "f", #title)
    end
    local text = padLine(tStr, "7", "f", w)
    mon:setCursorPos(1, 1)
    mon:blit(text, string.sub(fStr .. string.rep("7", w), 1, w), string.sub(bStr .. string.rep("f", w), 1, w))
    local sepText, sepFg, sepBg = padLine(string.rep("-", w), "8", "f", w)
    mon:setCursorPos(1, 2)
    mon:blit(sepText, sepFg, sepBg)
end

local function renderFooter(mon, w, h)
    local actions = "  [ REFRESH ]    [ CALIBRATE ]    [ CLEAR ]    [ REFIT ]"
    local t, f, b = padLine(actions, "0", "8", w)
    mon:setCursorPos(1, h - 1)
    mon:blit(t, f, b)
    local stat, sf, sb = padLine("  STATUS: ACTIVE | AUTO-REFIT 5HZ | TOUCH TO NAVIGATE", "5", "f", w)
    mon:setCursorPos(1, h)
    mon:blit(stat, sf, sb)
end

local function renderOverviewTab(mon, state, w)
    local lines = {
        "  GPS ADVANCED CENTRAL GCS - SYSTEM OVERVIEW",
        "  ------------------------------------------------------------",
        string.format("  Total Solved Requests : %d", state.totalSolves or 0),
        string.format("  Active Swarm Nodes   : %d online", state.activeNodes or 0),
        string.format("  Tracked Clients      : %d active", state.clientCount or 0),
        string.format("  Channel Freq         : %d (Listen) / %d (Data)", state.listenChan or 60001, state.dataChan or 60002),
        string.format("  System Health        : %s", (state.activeNodes or 0) >= 3 and "OPTIMAL" or "DEGRADED"),
        "  ------------------------------------------------------------",
        "  Swarm Constellation  : 3D Spherical Trilateration Active",
        "  Watchdog Status      : 35s Auto-Purge Running"
    }
    for idx, line in ipairs(lines) do
        local t, f, b = padLine(line, "0", "f", w)
        mon:setCursorPos(1, 3 + idx)
        mon:blit(t, f, b)
    end
end

local function renderClientsTab(mon, state, w)
    local header, hf, hb = padLine("  ID         CLIENT POSITION (X, Y, Z)     LAST SEEN (s)", "d", "f", w)
    mon:setCursorPos(1, 4)
    mon:blit(header, hf, hb)
    local clients = state.clients or {}
    for i = 1, math.min(#clients, 25) do
        local c = clients[i]
        local idStr = string.sub(tostring(c.id or "?"), 1, 16)
        local row = string.format("  %-10s (%7.1f, %5.1f, %7.1f)  %5.1fs ago",
            idStr, tonumber(c.x) or 0, tonumber(c.y) or 0, tonumber(c.z) or 0, tonumber(c.lastSeen) or 0)
        local t, f, b = padLine(row, "0", "f", w)
        mon:setCursorPos(1, 4 + i)
        mon:blit(t, f, b)
    end
end

local function renderNodesTab(mon, state, w)
    local header, hf, hb = padLine("  ID         NODE POSITION (X, Y, Z)       STATUS       PING", "b", "f", w)
    mon:setCursorPos(1, 4)
    mon:blit(header, hf, hb)
    local nodes = state.nodes or {}
    for i = 1, math.min(#nodes, 25) do
        local n = nodes[i]
        local idStr = string.sub(tostring(n.id or "?"), 1, 16)
        local row = string.format("  %-10s (%7.1f, %5.1f, %7.1f)  %-10s %dms",
            idStr, tonumber(n.x) or 0, tonumber(n.y) or 0, tonumber(n.z) or 0, tostring(n.status or "OK"), tonumber(n.ping) or 0)
        local t, f, b = padLine(row, (n.status == "ONLINE" and "5" or "e"), "f", w)
        mon:setCursorPos(1, 4 + i)
        mon:blit(t, f, b)
    end
end

local function renderRadarTab(mon, state, w, h)
    local allPoints = {}
    for _, n in ipairs(state.nodes or {}) do table.insert(allPoints, { x = n.x, z = n.z, type = "NODE" }) end
    for _, c in ipairs(state.clients or {}) do table.insert(allPoints, { x = c.x, z = c.z, type = "CLIENT" }) end
    local bounds = radar_math.computeCentroidSpan(allPoints, 1.2)
    local info = string.format("  RADAR VIEW: Centroid=(%.1f, %.1f) Span=(%.1f x %.1f)",
        bounds.centerX, bounds.centerZ, bounds.spanX, bounds.spanZ)
    local it, ifg, ibg = padLine(info, "4", "f", w)
    mon:setCursorPos(1, 3); mon:blit(it, ifg, ibg)

    for y = 4, h - 3 do
        local gridLine = (y == math.floor(h / 2)) and string.rep("-", w) or ("|" .. string.rep(" ", w - 2) .. "|")
        local gt, gf, gb = padLine(gridLine, "8", "f", w)
        mon:setCursorPos(1, y); mon:blit(gt, gf, gb)
    end

    for _, pt in ipairs(allPoints) do
        local sx, sz = radar_math.projectToGrid(pt.x, pt.z, bounds, w, h - 6)
        local sy = sz + 3
        if radar_math.isInBounds(sx, sy, w, h - 3) and sy >= 4 then
            mon:setCursorPos(sx, sy)
            local char = (pt.type == "NODE") and "N" or "^"
            local color = (pt.type == "NODE") and "5" or "4"
            mon:blit(char, color, "f")
        end
    end
end

function UI:render(mon, state)
    local w = self.width
    local h = self.height
    renderHeader(mon, self.currentTab, w)
    local blankT, blankFg, blankBg = padLine("", "0", "f", w)
    for row = 3, h - 2 do
        mon:setCursorPos(1, row)
        mon:blit(blankT, blankFg, blankBg)
    end
    if self.currentTab == 1 then renderOverviewTab(mon, state, w)
    elseif self.currentTab == 2 then renderClientsTab(mon, state, w)
    elseif self.currentTab == 3 then renderNodesTab(mon, state, w)
    elseif self.currentTab == 4 then renderRadarTab(mon, state, w, h)
    end
    renderFooter(mon, w, h)
end

return monitor_ui
