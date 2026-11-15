-- src/0_development/ota/modules/ota_ui.lua
-- Exact 51x19 term.blit TUI Renderer for Hangar Wireless OTA Deployment Server

local ota_ui = {}

local WIDTH = 51
local HEIGHT = 19
local MAX_NODE_ROWS = 8
local BAR_WIDTH = 24

local function pad_exact(text, width)
    local clean = tostring(text or ""):gsub("[\r\n]", " ")
    if #clean > width then
        return string.sub(clean, 1, width)
    elseif #clean < width then
        return clean .. string.rep(" ", width - #clean)
    end
    return clean
end

--- Formats a single row to exact 51-character text, foreground, and background blit strings.
-- @param text string Display text
-- @param fgChar string|nil Single hex color char (default "0")
-- @param bgChar string|nil Single hex color char (default "f")
-- @return string text51, string fg51, string bg51
function ota_ui.format_row(text, fgChar, bgChar)
    local t = pad_exact(text, WIDTH)
    local fCh = string.sub(tostring(fgChar or "0"), 1, 1)
    local bCh = string.sub(tostring(bgChar or "f"), 1, 1)
    return t, string.rep(fCh, WIDTH), string.rep(bCh, WIDTH)
end

local function write_row(termObj, y, text, fgChar, bgChar)
    local t, f, b = ota_ui.format_row(text, fgChar, bgChar)
    termObj.setCursorPos(1, y)
    if type(termObj.blit) == "function" then
        termObj.blit(t, f, b)
    elseif type(termObj.write) == "function" then
        termObj.write(t)
    end
end

local function format_node_row(node, isSelected)
    local prefix = isSelected and ">" or " "
    local dom = pad_exact(node.domainId or "?", 11)
    local mod = pad_exact(node.moduleId or "?", 5)
    local ver = pad_exact(node.version or "0.0.0", 9)
    local badge = node.safeForOta and "[SAFE]" or "[LOCK]"
    local ctrl = pad_exact(node.controlState or "UNKNOWN", 12)
    local line = string.format("%s%s %s %s %-6s %s", prefix, dom, mod, ver, badge, ctrl)
    local fg = node.safeForOta and "5" or "e"
    if isSelected then
        return line, "4", "7"
    end
    return line, fg, "f"
end

local function build_progress_line(progress)
    if type(progress) ~= "table" or not progress.active then
        local emptyBar = string.rep(".", BAR_WIDTH)
        return string.format(" PROG: [%s]   0%% (0/0)", emptyBar), "8", "f"
    end
    local total = math.max(1, math.floor(tonumber(progress.totalChunks) or 1))
    local sent = math.max(0, math.min(total, math.floor(tonumber(progress.sentChunks) or 0)))
    local pct = math.floor((sent * 100) / total)
    local filled = math.floor((sent * BAR_WIDTH) / total)
    local bar = string.rep("#", filled) .. string.rep(".", BAR_WIDTH - filled)
    local line = string.format(" PROG: [%s] %3d%% (%d/%d)", bar, pct, sent, total)
    local fg = (sent >= total) and "5" or "3"
    return line, fg, "f"
end

--- Renders the 51x19 OTA Server dashboard onto a terminal or monitor surface.
-- @param termObj table CC terminal or monitor object
-- @param state table UI state snapshot
-- @return boolean rendered
function ota_ui.render(termObj, state)
    if not termObj or type(termObj.setCursorPos) ~= "function" then
        return false
    end
    local st = state or {}
    local bayId = math.floor(tonumber(st.bayId) or 1)
    local cmdCh = math.floor(tonumber(st.cmdCh) or 105)
    local ackCh = math.floor(tonumber(st.ackCh) or 106)
    local domainId = tostring(st.domainId or "HANGAR-OTA-01")
    local modemLabel = st.modemPresent and "ONLINE" or "NO MODEM"
    local modemBg = st.modemPresent and "d" or "e"
    local nodes = type(st.nodes) == "table" and st.nodes or {}
    local selectedIdx = math.floor(tonumber(st.selectedIdx) or 1)
    if #nodes > 0 then
        selectedIdx = math.max(1, math.min(#nodes, selectedIdx))
    else
        selectedIdx = 0
    end

    local rows = {}
    rows[1] = { string.format(" HANGAR WIRELESS OTA SERVER  BAY:%02d (CH:%d/%d)", bayId, cmdCh, ackCh), "0", "b" }
    rows[2] = { string.format(" DOMAIN: %-22s MODEM: %-10s", domainId, modemLabel), "0", modemBg }
    rows[3] = { string.rep("-", WIDTH), "8", "f" }
    rows[4] = { "  DOMAIN      MOD   VERSION   GATE   CTRL_STATE", "4", "f" }

    local scrollOffset = 0
    if selectedIdx > MAX_NODE_ROWS then
        scrollOffset = selectedIdx - MAX_NODE_ROWS
    end
    for i = 1, MAX_NODE_ROWS do
        local nodeIdx = scrollOffset + i
        local node = nodes[nodeIdx]
        if node then
            local text, fg, bg = format_node_row(node, nodeIdx == selectedIdx)
            rows[4 + i] = { text, fg, bg }
        elseif i == 1 and #nodes == 0 then
            rows[4 + i] = { "  (No nodes found - press [D]iscover)", "8", "f" }
        else
            rows[4 + i] = { "", "0", "f" }
        end
    end

    rows[13] = { string.rep("-", WIDTH), "8", "f" }
    local selNode = (selectedIdx > 0) and nodes[selectedIdx] or nil
    local targetLabel = selNode
        and (tostring(selNode.domainId) .. "/" .. tostring(selNode.moduleId) .. " v" .. tostring(selNode.version))
        or "NONE"
    rows[14] = { string.format(" TARGET: %-41s", targetLabel), "0", "f" }

    local progText, progFg, progBg = build_progress_line(st.progress)
    rows[15] = { progText, progFg, progBg }
    rows[16] = { string.format(" STATUS: %-41s", tostring(st.statusMsg or "READY")), "1", "f" }
    rows[17] = { string.rep("-", WIDTH), "8", "f" }
    rows[18] = { " [D]iscover [S]ync [U]pdate [B]ay [Up/Dn]Select", "4", "f" }
    rows[19] = {
        string.format(
            " [O]verwriteCfg:%-3s [R]eboot:%-3s [Q]uit",
            st.overwriteConfig and "ON" or "OFF",
            st.autoReboot and "ON" or "OFF"
        ),
        "4",
        "f",
    }

    for y = 1, HEIGHT do
        local r = rows[y]
        write_row(termObj, y, r[1], r[2], r[3])
    end
    return true
end

return ota_ui
