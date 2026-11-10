-- src/0_development/installer/modules/tui_view.lua
-- 51x19 Terminal TUI Renderer for Create_Aeroneutics Unified Codebase Installer

local tui_view = {}

local SPACES = string.rep(" ", 128)
local SEPARATOR = string.rep("-", 128)
local EQUALS_24 = string.rep("=", 24)
local BLANK_51 = SPACES:sub(1, 51)
local SEP_51 = SEPARATOR:sub(1, 51)
local CAT_HINT_1 = (" [Up/Down] Select   [Enter] Open Folder" .. SPACES):sub(1, 51)
local CAT_HINT_2 = (" [S] Toggle Source  [Q] Quit" .. SPACES):sub(1, 51)
local MOD_HINT_1 = (" [Up/Down] Select   [Enter] Install   [U] Uninstall" .. SPACES):sub(1, 51)
local MOD_HINT_2_FOLDER = (" [Bksp/B] Folders   [S] Source        [Q] Quit" .. SPACES):sub(1, 51)
local MOD_HINT_2_FLAT = (" [S] Toggle Source  [Q] Quit" .. SPACES):sub(1, 51)

local function repeatChar(ch, count)
    if count <= 0 then
        return ""
    end
    local buf = (ch == " ") and SPACES or (ch == "-" and SEPARATOR or nil)
    if buf and count <= #buf then
        return buf:sub(1, count)
    end
    return string.rep(ch, count)
end

local function padExact(text, w)
    local s = tostring(text or "")
    local len = #s
    if len == w then
        return s
    elseif len < w then
        return s .. repeatChar(" ", w - len)
    else
        return s:sub(1, w)
    end
end

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

local function buildPalettes()
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
    }, {
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

local COLOR_PALETTE, MONO_PALETTE = buildPalettes()

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
    return isCol and COLOR_PALETTE or MONO_PALETTE
end

--- Writes a single line padded or truncated to terminal width w, never exceeding h.
-- @param termObj table Terminal object
-- @param y number 1-based vertical position
-- @param text string Content to write
-- @param fg number Text color
-- @param bg number Background color
-- @param w number Terminal width
-- @param h number Terminal height
-- @param renderState table|nil Optional { fg = num, bg = num } cache to avoid redundant color calls
local function drawRow(termObj, y, text, fg, bg, w, h, renderState)
    if not termObj or y < 1 or y > h then
        return
    end

    termObj.setCursorPos(1, y)

    if fg and termObj.setTextColor then
        if not renderState or renderState.fg ~= fg then
            termObj.setTextColor(fg)
            if renderState then renderState.fg = fg end
        end
    end
    if bg and termObj.setBackgroundColor then
        if not renderState or renderState.bg ~= bg then
            termObj.setBackgroundColor(bg)
            if renderState then renderState.bg = bg end
        end
    end

    local s = tostring(text or "")
    local len = #s
    if len < w then
        s = s .. repeatChar(" ", w - len)
    elseif len > w then
        s = s:sub(1, w)
    end

    termObj.write(s)
end

local function drawHeaderLines(termObj, title, subtitle, currentSource, contextLabel, w, h, palette, renderState)
    local isGd = (tostring(currentSource):lower() == "gdrive")
    local srcBadge = isGd and "[GDrive]" or "[GitHub]"
    local ctx = contextLabel and (" [" .. tostring(contextLabel) .. "]") or ""
    local fullRight = srcBadge .. ctx

    local mainTitle = title or "Create: Aeronautics Installer"
    local space = w - #mainTitle - #fullRight
    local line1
    if space > 0 then
        line1 = mainTitle .. repeatChar(" ", space) .. fullRight
    else
        line1 = (mainTitle .. " " .. fullRight):sub(1, w)
    end

    drawRow(termObj, 1, line1, palette.headerFg, palette.headerBg, w, h, renderState)

    local sub = subtitle or "Modular CC:Tweaked Autopilot Stack"
    drawRow(termObj, 2, " " .. sub, palette.subFg, palette.bg, w, h, renderState)
    drawRow(termObj, 3, (w == 51) and SEP_51 or repeatChar("-", w), palette.sepFg, palette.bg, w, h, renderState)
end

local function buildSeparatorRow(w, total, firstIdx, lastIdx, maxRows)
    if total > maxRows and lastIdx >= firstIdx then
        local indicator = string.format(" [%d-%d of %d] ", firstIdx, lastIdx, total)
        if #indicator < w then
            local rem = w - #indicator
            local leftDashes = math.floor(rem / 2)
            local rightDashes = rem - leftDashes
            return repeatChar("-", leftDashes) .. indicator .. repeatChar("-", rightDashes)
        end
        return indicator:sub(1, w)
    end
    return (w == 51) and SEP_51 or repeatChar("-", w)
end

local function clearBlankRows(termObj, startRow, endRow, fg, bg, blankRow, renderState)
    if endRow < startRow then
        return
    end
    if fg and termObj.setTextColor and renderState.fg ~= fg then
        termObj.setTextColor(fg)
        renderState.fg = fg
    end
    if bg and termObj.setBackgroundColor and renderState.bg ~= bg then
        termObj.setBackgroundColor(bg)
        renderState.bg = bg
    end
    local setPos = termObj.setCursorPos
    local writeFn = termObj.write
    for y = startRow, endRow do
        setPos(1, y)
        writeFn(blankRow)
    end
end

local function countInstalledInCategory(cat, installedMap)
    local count = 0
    local mods = cat and cat.modules
    if type(mods) == "table" and type(installedMap) == "table" then
        for i = 1, #mods do
            local mod = mods[i]
            if mod and mod.id and installedMap[mod.id] then
                count = count + 1
            end
        end
    end
    return count
end

--- Computes an inclusive 1-based viewport slice and updated 0-based scroll offset.
-- @param totalItems number Total count of list items
-- @param selectedIndex number 1-based cursor index
-- @param maxVisibleRows number|nil Maximum viewport height (default 12)
-- @param currentScrollOffset number|nil Previous 0-based scroll offset
-- @return number firstIdx
-- @return number lastIdx
-- @return number nextScrollOffset
function tui_view.computeViewport(totalItems, selectedIndex, maxVisibleRows, currentScrollOffset)
    local total = math.floor(tonumber(totalItems) or 0)
    local maxRows = math.floor(tonumber(maxVisibleRows) or 12)
    if maxRows < 1 then
        maxRows = 1
    end

    if total <= 0 then
        return 1, 0, 0
    end

    local sel = math.floor(tonumber(selectedIndex) or 1)
    if sel < 1 then
        sel = 1
    elseif sel > total then
        sel = total
    end

    local scroll = math.floor(tonumber(currentScrollOffset) or 0)
    if scroll < 0 then
        scroll = 0
    end

    local maxScroll = math.max(0, total - maxRows)
    if scroll > maxScroll then
        scroll = maxScroll
    end

    if sel < scroll + 1 then
        scroll = sel - 1
    elseif sel > scroll + maxRows then
        scroll = sel - maxRows
    end

    local firstIdx = scroll + 1
    local lastIdx = math.min(total, scroll + maxRows)
    return firstIdx, lastIdx, scroll
end

local function formatCategoryRow(cat, isSel, installedMap)
    local prefix = isSel and "> " or "  "
    local catCode = tostring(cat.code or cat.id or "")
    local catShort = tostring(cat.shortName or cat.name or catCode)
    local totalCount = tonumber(cat.moduleCount) or (type(cat.modules) == "table" and #cat.modules or 0)
    local instCount = countInstalledInCategory(cat, installedMap)
    return string.format("%s[DIR] %-13s %-16s [%d/%d inst]", prefix, catCode, catShort, instCount, totalCount)
end

local function formatModuleRow(mod, isSel, installedMap)
    local prefix = isSel and "> " or "  "
    local modId = tostring(mod.id or "")
    local modName = tostring(mod.name or modId)
    local modVer = tostring(mod.version or "1.0.0")
    local statusStr
    if installedMap[modId] then
        statusStr = "[INSTALLED v" .. tostring(installedMap[modId].version or modVer) .. "]"
    else
        statusStr = "[Available v" .. modVer .. "]"
    end
    return string.format("%s%-14s %s", prefix, modName, statusStr)
end

--- Incrementally redraws only affected cursor rows and optional status bar when scroll stays unchanged.
-- @param termObj table Terminal object
-- @param items table List of categories or modules
-- @param prevIndex number Previous 1-based selection index
-- @param nextIndex number New 1-based selection index
-- @param scrollOffset number Current 0-based scroll offset
-- @param installedMap table|nil Map of installed modules
-- @param isCategory boolean True when rendering categories, false for modules
-- @param clearStatusRow boolean|nil True to blank row h when clearing a prior status message
-- @return boolean True if delta update succeeded; false if caller must do a full render
function tui_view.updateSelection(termObj, items, prevIndex, nextIndex, scrollOffset, installedMap, isCategory, clearStatusRow)
    if not termObj then return true end
    local w, h = termObj.getSize()
    w = tonumber(w) or 51
    h = tonumber(h) or 19

    local list = items or {}
    local startY = 4
    local maxEndY = h - 4
    local maxRows = math.max(1, maxEndY - startY + 1)
    local curScroll = math.floor(tonumber(scrollOffset) or 0)
    local firstIdx, lastIdx, nextScroll = tui_view.computeViewport(#list, nextIndex, maxRows, curScroll)

    if nextScroll ~= curScroll or prevIndex < firstIdx or prevIndex > lastIdx then
        return false
    end

    local palette = getColors(termObj)
    local renderState = {}
    local inst = installedMap or {}

    local function drawItemAt(idx, isSel)
        local item = list[idx]
        if not item then return end
        local y = startY + (idx - firstIdx)
        local rowText = isCategory and formatCategoryRow(item, isSel, inst) or formatModuleRow(item, isSel, inst)
        local fg = isSel and palette.selectedFg or palette.fg
        local bg = isSel and palette.selectedBg or palette.bg
        drawRow(termObj, y, rowText, fg, bg, w, h, renderState)
    end

    if prevIndex ~= nextIndex then
        drawItemAt(prevIndex, false)
        drawItemAt(nextIndex, true)
    end

    if clearStatusRow then
        local blankRow = (w == 51) and BLANK_51 or repeatChar(" ", w)
        drawRow(termObj, h, blankRow, palette.fg, palette.bg, w, h, renderState)
    end

    return true
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
    drawHeaderLines(termObj, title, subtitle, currentSource, contextLabel, w, h, palette, {})
end

local function renderListBodyAndFooter(termObj, items, sel, inst, isCategory, hint1Raw, hint2Raw, scrollOffset, w, h, palette, renderState)
    local list = items or {}
    local startY = 4
    local maxEndY = h - 4
    local maxRows = math.max(1, maxEndY - startY + 1)
    local firstIdx, lastIdx, nextScroll = tui_view.computeViewport(#list, sel, maxRows, scrollOffset)

    local drawnCount = 0
    local setPos = termObj.setCursorPos
    local writeFn = termObj.write
    local setFg = termObj.setTextColor
    local setBg = termObj.setBackgroundColor
    for i = firstIdx, lastIdx do
        local y = startY + drawnCount
        if y <= maxEndY then
            local item = list[i]
            local isSel = (i == sel)
            local rowText = isCategory and formatCategoryRow(item, isSel, inst) or formatModuleRow(item, isSel, inst)
            if #rowText < w then
                rowText = rowText .. ((w - #rowText <= 128) and SPACES:sub(1, w - #rowText) or string.rep(" ", w - #rowText))
            elseif #rowText > w then
                rowText = rowText:sub(1, w)
            end

            local fg = isSel and palette.selectedFg or palette.fg
            local bg = isSel and palette.selectedBg or palette.bg
            if setFg and renderState.fg ~= fg then
                setFg(fg)
                renderState.fg = fg
            end
            if setBg and renderState.bg ~= bg then
                setBg(bg)
                renderState.bg = bg
            end
            setPos(1, y)
            writeFn(rowText)
            drawnCount = drawnCount + 1
        end
    end

    local blankRow = (w == 51) and BLANK_51 or repeatChar(" ", w)
    clearBlankRows(termObj, startY + drawnCount, maxEndY, palette.fg, palette.bg, blankRow, renderState)

    local hint1 = (w == 51) and hint1Raw or padExact(hint1Raw, w)
    local hint2 = (w == 51) and hint2Raw or padExact(hint2Raw, w)
    drawRow(termObj, h - 3, buildSeparatorRow(w, #list, firstIdx, lastIdx, maxRows), palette.sepFg, palette.bg, w, h, renderState)
    drawRow(termObj, h - 2, hint1, palette.footerFg, palette.bg, w, h, renderState)
    drawRow(termObj, h - 1, hint2, palette.footerFg, palette.bg, w, h, renderState)
    drawRow(termObj, h, blankRow, palette.fg, palette.bg, w, h, renderState)

    return nextScroll
end

--- Renders root domain category folder menu within 51x19 bounds with viewport scrolling.
-- @param termObj table Terminal object
-- @param categories table List of category tables from manifest.listCategories()
-- @param selectedIndex number Currently selected category index (1..#categories)
-- @param currentSource string "github" or "gdrive"
-- @param installedMap table|nil Map of { [moduleId] = installInfo }
-- @param scrollOffset number|nil Previous 0-based scroll offset
-- @return number Updated 0-based scroll offset
function tui_view.renderCategoryMenu(termObj, categories, selectedIndex, currentSource, installedMap, scrollOffset)
    if not termObj then return tonumber(scrollOffset) or 0 end
    local w, h = termObj.getSize()
    w = tonumber(w) or 51
    h = tonumber(h) or 19
    local palette = getColors(termObj)
    local renderState = {}

    drawHeaderLines(termObj, "Create: Aeronautics", "Select domain folder to browse", currentSource, "Folders", w, h, palette, renderState)

    local sel = tonumber(selectedIndex) or 1
    local inst = installedMap or {}
    return renderListBodyAndFooter(termObj, categories, sel, inst, true, CAT_HINT_1, CAT_HINT_2, scrollOffset, w, h, palette, renderState)
end

--- Renders module menu screen within 51x19 bounds with viewport scrolling and optional category header.
-- @param termObj table Terminal object
-- @param modules table List of module tables
-- @param selectedIndex number Currently selected index (1..#modules)
-- @param currentSource string "github" or "gdrive"
-- @param installedMap table|nil Map of { [moduleId] = installInfo }
-- @param categoryInfo table|nil Optional parent category table ({ id, code, name })
-- @param scrollOffset number|nil Previous 0-based scroll offset
-- @return number Updated 0-based scroll offset
function tui_view.renderMenu(termObj, modules, selectedIndex, currentSource, installedMap, categoryInfo, scrollOffset)
    if not termObj then return tonumber(scrollOffset) or 0 end
    local w, h = termObj.getSize()
    w = tonumber(w) or 51
    h = tonumber(h) or 19
    local palette = getColors(termObj)
    local renderState = {}

    local catCode = nil
    local subtitle = "Select module to install/update"
    local hint2 = MOD_HINT_2_FLAT
    if categoryInfo then
        catCode = tostring(categoryInfo.code or categoryInfo.id or "")
        subtitle = "Folder: " .. catCode .. " - " .. tostring(categoryInfo.name or "")
        hint2 = MOD_HINT_2_FOLDER
    end

    drawHeaderLines(termObj, "Create: Aeronautics", subtitle, currentSource, catCode, w, h, palette, renderState)

    local sel = tonumber(selectedIndex) or 1
    local inst = installedMap or {}
    return renderListBodyAndFooter(termObj, modules, sel, inst, false, MOD_HINT_1, hint2, scrollOffset, w, h, palette, renderState)
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
    local renderState = {}

    local isGd = (tostring(currentSource):lower() == "gdrive")
    local srcBadge = isGd and "[GDrive]" or "[GitHub]"

    local c = tonumber(cur) or 0
    local tot = tonumber(total) or 1
    local ratio = (tot > 0) and (c / tot) or 0
    if ratio > 1 then ratio = 1 end
    if ratio < 0 then ratio = 0 end

    -- Compact progress render to preserve instruction budget
    local headerLine = " Create: Aeronautics            " .. srcBadge
    drawRow(termObj, 1, headerLine, palette.headerFg, palette.headerBg, w, h, renderState)

    local barWidth = 24
    local filled = math.floor(ratio * barWidth)
    local empty = barWidth - filled
    local pct = math.floor(ratio * 100)
    local barStr = string.format(" [%s%s] %3d%%  (%d/%d)", EQUALS_24:sub(1, filled), SPACES:sub(1, empty), pct, c, tot)
    drawRow(termObj, 3, barStr, palette.headerFg, palette.bg, w, h, renderState)

    local fileStr = " File: " .. tostring(currentPath or "")
    drawRow(termObj, 5, fileStr, palette.subFg, palette.bg, w, h, renderState)
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
