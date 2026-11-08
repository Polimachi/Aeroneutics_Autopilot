-- src/0_development/installer/modules/tui_view.lua
-- 51x19 Terminal TUI Renderer for Create_Aeroneutics Unified Codebase Installer

local tui_view = {}

local SPACES = string.rep(" ", 80)
local SEPARATOR = string.rep("-", 80)

--- Toggles source between 'github' and 'gdrive'.
-- @param currentSource string|nil
-- @return string Next source ("github" or "gdrive")
function tui_view.toggleSource(currentSource)
    local s = tostring(currentSource or ""):lower()
    if s == "gdrive" then
        return "github"
    else
        return "gdrive"
    end
end

--- Resolves color palette based on terminal color capabilities.
-- @param termObj table Terminal object
-- @return table Palette table
local function getColors(termObj)
    local isCol = false
    if termObj and type(termObj.isColor) == "function" then
        isCol = termObj.isColor()
    elseif termObj and type(termObj.isColour) == "function" then
        isCol = termObj.isColour()
    end

    local c = _G.colors or {}
    local black = c.black or 32768
    local white = c.white or 1
    local yellow = c.yellow or 16
    local blue = c.blue or 2048
    local lightGray = c.lightGray or 256
    local gray = c.gray or 128
    local green = c.green or 8192
    local cyan = c.cyan or 512
    local red = c.red or 16384
    local orange = c.orange or 2

    if isCol then
        return {
            bg = black,
            fg = white,
            headerBg = blue,
            headerFg = yellow,
            subFg = lightGray,
            selectedBg = gray,
            selectedFg = yellow,
            badgeGh = green,
            badgeGd = cyan,
            footerFg = lightGray,
            sepFg = gray,
            okFg = green,
            errFg = red,
            warnFg = orange,
            infoFg = cyan,
        }
    else
        return {
            bg = black,
            fg = white,
            headerBg = black,
            headerFg = white,
            subFg = white,
            selectedBg = white,
            selectedFg = black,
            badgeGh = white,
            badgeGd = white,
            footerFg = white,
            sepFg = white,
            okFg = white,
            errFg = white,
            warnFg = white,
            infoFg = white,
        }
    end
end

--- Writes a single line padded or truncated to terminal width w, never exceeding h.
-- @param termObj table Terminal object
-- @param y number 1-based vertical position
-- @param text string Content to write
-- @param fg number Text color
-- @param bg number Background color
-- @param w number Terminal width
-- @param h number Terminal height
local function drawRow(termObj, y, text, fg, bg, w, h)
    if not termObj or y < 1 or y > h then
        return
    end

    termObj.setCursorPos(1, y)

    if fg and termObj.setTextColor then
        termObj.setTextColor(fg)
    end
    if bg and termObj.setBackgroundColor then
        termObj.setBackgroundColor(bg)
    end

    local s = tostring(text or "")
    local len = #s
    if len < w then
        s = s .. SPACES:sub(1, w - len)
    elseif len > w then
        s = s:sub(1, w)
    end

    termObj.write(s)
end

--- Renders application header lines (1-3) within 51x19 bounds.
-- @param termObj table Terminal object
-- @param title string|nil Main title
-- @param subtitle string|nil Subtitle
-- @param currentSource string|nil "github" or "gdrive"
-- @param contextLabel string|nil Optional context indicator
function tui_view.renderHeader(termObj, title, subtitle, currentSource, contextLabel)
    if not termObj then return end
    local w, h = termObj.getSize()
    w = tonumber(w) or 51
    h = tonumber(h) or 19
    local palette = getColors(termObj)

    local isGd = (tostring(currentSource):lower() == "gdrive")
    local srcBadge = isGd and "[GDrive]" or "[GitHub]"
    local ctx = contextLabel and (" [" .. tostring(contextLabel) .. "]") or ""
    local fullRight = srcBadge .. ctx

    local mainTitle = title or "Create: Aeronautics Installer"
    local space = w - #mainTitle - #fullRight
    local line1
    if space > 0 then
        line1 = mainTitle .. SPACES:sub(1, space) .. fullRight
    else
        line1 = (mainTitle .. " " .. fullRight):sub(1, w)
    end

    drawRow(termObj, 1, line1, palette.headerFg, palette.headerBg, w, h)

    local sub = subtitle or "Modular CC:Tweaked Autopilot Stack"
    drawRow(termObj, 2, " " .. sub, palette.subFg, palette.bg, w, h)
    drawRow(termObj, 3, SEPARATOR:sub(1, w), palette.sepFg, palette.bg, w, h)
end

--- Renders 7-module interactive menu screen within 51x19 bounds.
-- @param termObj table Terminal object
-- @param modules table List of module tables from manifest.listModules()
-- @param selectedIndex number Currently selected index (1..#modules)
-- @param currentSource string "github" or "gdrive"
-- @param installedMap table|nil Map of { [moduleId] = installInfo }
function tui_view.renderMenu(termObj, modules, selectedIndex, currentSource, installedMap)
    if not termObj then return end
    local w, h = termObj.getSize()
    w = tonumber(w) or 51
    h = tonumber(h) or 19
    local palette = getColors(termObj)

    tui_view.renderHeader(termObj, "Create: Aeronautics", "Select module to install/update", currentSource, nil)

    local mods = modules or {}
    local sel = tonumber(selectedIndex) or 1
    local inst = installedMap or {}

    local startY = 4
    for i = 1, #mods do
        local y = startY + i - 1
        if y <= h - 4 then
            local mod = mods[i]
            local isSel = (i == sel)
            local prefix = isSel and "> " or "  "
            local modId = tostring(mod.id or "")
            local modName = tostring(mod.name or modId)
            local modVer = tostring(mod.version or "1.0.0")

            local statusStr
            if inst[modId] then
                statusStr = "[INSTALLED v" .. tostring(inst[modId].version or modVer) .. "]"
            else
                statusStr = "[Available v" .. modVer .. "]"
            end

            local rowText = string.format("%s%-14s %s", prefix, modName, statusStr)
            local fg = isSel and palette.selectedFg or palette.fg
            local bg = isSel and palette.selectedBg or palette.bg
            drawRow(termObj, y, rowText, fg, bg, w, h)
        end
    end

    -- Separator and navigation hints
    drawRow(termObj, h - 3, SEPARATOR:sub(1, w), palette.sepFg, palette.bg, w, h)
    drawRow(termObj, h - 2, " [Up/Down] Select   [Enter] Install   [U] Uninstall", palette.footerFg, palette.bg, w, h)
    drawRow(termObj, h - 1, " [S] Toggle Source  [Q] Quit", palette.footerFg, palette.bg, w, h)
end

--- Renders progress bar screen during batch download.
-- @param termObj table Terminal object
-- @param cur number Current file index
-- @param total number Total files count
-- @param currentPath string Current downloading path
-- @param currentSource string "github" or "gdrive"
function tui_view.renderProgress(termObj, cur, total, currentPath, currentSource)
    if not termObj then return end
    local w, h = termObj.getSize()
    w = tonumber(w) or 51
    h = tonumber(h) or 19
    local palette = getColors(termObj)

    local isGd = (tostring(currentSource):lower() == "gdrive")
    local srcBadge = isGd and "[GDrive]" or "[GitHub]"

    local c = tonumber(cur) or 0
    local tot = tonumber(total) or 1
    local ratio = (tot > 0) and (c / tot) or 0
    if ratio > 1 then ratio = 1 end
    if ratio < 0 then ratio = 0 end

    -- Compact progress render to preserve instruction budget
    local headerLine = " Create: Aeronautics            " .. srcBadge
    drawRow(termObj, 1, headerLine, palette.headerFg, palette.headerBg, w, h)

    local barWidth = 24
    local filled = math.floor(ratio * barWidth)
    local empty = barWidth - filled
    local pct = math.floor(ratio * 100)
    local barStr = string.format(" [%s%s] %3d%%  (%d/%d)", string.rep("=", filled), string.rep(" ", empty), pct, c, tot)
    drawRow(termObj, 3, barStr, palette.headerFg, palette.bg, w, h)

    local fileStr = " File: " .. tostring(currentPath or "")
    drawRow(termObj, 5, fileStr, palette.subFg, palette.bg, w, h)
end

--- Renders a status or confirmation message at bottom row (h).
-- @param termObj table Terminal object
-- @param level string "info", "warn", "error", "success"
-- @param message string Message text
function tui_view.renderMessage(termObj, level, message)
    if not termObj then return end
    local w, h = termObj.getSize()
    w = tonumber(w) or 51
    h = tonumber(h) or 19
    local palette = getColors(termObj)

    local lvl = tostring(level or "info"):lower()
    local prefix = "[INFO] "
    local fg = palette.infoFg

    if lvl == "warn" or lvl == "warning" then
        prefix = "[WARN] "
        fg = palette.warnFg
    elseif lvl == "error" or lvl == "fail" then
        prefix = "[ERROR] "
        fg = palette.errFg
    elseif lvl == "success" or lvl == "ok" then
        prefix = "[OK] "
        fg = palette.okFg
    end

    local text = " " .. prefix .. tostring(message or "")
    drawRow(termObj, h, text, fg, palette.bg, w, h)
end

return tui_view
