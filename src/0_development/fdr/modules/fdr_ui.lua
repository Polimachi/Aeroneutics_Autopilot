-- Exact 51x19 term.blit TUI renderer for FDR Ground In-Flight Aligner.
local fdr_ui = {}

local WIDTH = 51
local HEIGHT = 19

--- Pad or truncate a text string and expand uniform fg/bg hex chars to exact 51 chars.
function fdr_ui.format_row(text, fgChar, bgChar)
    local clean = tostring(text or ""):gsub("[\r\n]", " ")
    if #clean > WIDTH then
        clean = string.sub(clean, 1, WIDTH)
    elseif #clean < WIDTH then
        clean = clean .. string.rep(" ", WIDTH - #clean)
    end
    local fg = string.rep(string.sub(tostring(fgChar or "0"), 1, 1), WIDTH)
    local bg = string.rep(string.sub(tostring(bgChar or "f"), 1, 1), WIDTH)
    return clean, fg, bg
end

local function write_row(termObj, y, text, fgChar, bgChar)
    local t, f, b = fdr_ui.format_row(text, fgChar, bgChar)
    termObj.setCursorPos(1, y)
    termObj.blit(t, f, b)
end

local function state_colors(mode)
    if mode == "LOGGING" then return "f", "5" end
    if mode == "DISK_FULL" then return "0", "e" end
    if mode == "PAUSED" then return "f", "4" end
    return "0", "8"
end

local function build_rows(st)
    local cnt = st.countsByOffset or {}
    local rows = {}
    rows[1] = { " FDR GROUND IN-FLIGHT ALIGNER (RECEIVE-ONLY)     ", "0", "b" }
    rows[2] = { string.format(" STATE: %-10s  TARGET N:%-4d  BASE:%5d", tostring(st.mode or "STANDBY"), st.aircraftIndexN or 1, st.baseChannel or 10000), state_colors(st.mode) }
    rows[3] = { string.format(" DOMAIN: %-22s  PART: part%03d", tostring(st.domainId or "*"), st.partIndex or 1), "0", "f" }
    rows[4] = { string.rep("-", WIDTH), "8", "f" }
    rows[5] = { string.format(" VFS VOL: %-14s  FREE: %6d KB", tostring(st.activeMount or "NONE"), math.floor(st.activeFreeKB or 0)), "d", "f" }
    rows[6] = { string.format(" POOL FREE TOTAL: %7d KB  FRAMES: %7d", math.floor(st.poolFreeKB or 0), math.floor(st.framesWritten or 0)), "0", "f" }
    rows[7] = { string.format(" EXPORT: %-41s", tostring(st.exportStatus or "GDRIVE READY")), "3", "f" }
    rows[8] = { string.rep("-", WIDTH), "8", "f" }
    rows[9] = { " TAPPED RF CHANNELS (MODEM.TRANSMIT = 0)         ", "4", "f" }
    rows[10] = { string.format("  B+1 (GUIDANCE): %7d  B+2 (TELEM): %7d", cnt[1] or 0, cnt[2] or 0), "0", "f" }
    rows[11] = { string.format("  B+10 (TCA)    : %7d  B+11 (ASA) : %7d", cnt[10] or 0, cnt[11] or 0), "0", "f" }
    rows[12] = { string.format("  B+4 (TRAJ)    : %7d", cnt[4] or 0), "0", "f" }
    rows[13] = { string.rep("-", WIDTH), "8", "f" }
    rows[14] = { string.format(" LAST MSG: %-39s", tostring(st.lastEventMsg or "READY")), "1", "f" }
    rows[15] = { "", "0", "f" }
    rows[16] = { "", "0", "f" }
    rows[17] = { string.rep("-", WIDTH), "8", "f" }
    rows[18] = { " [N]Bind [D]Flush [S]Split [U]Upload [P]Pause    ", "4", "f" }
    rows[19] = { " [C]Clear/Reset  [Q]Safe Shutdown                ", "4", "f" }
    return rows
end

--- Render full 51x19 screen using term.blit with zero flicker.
function fdr_ui.render(termObj, state)
    if not termObj or not termObj.blit then return false end
    local rows = build_rows(state or {})
    for y = 1, HEIGHT do
        local r = rows[y]
        write_row(termObj, y, r[1], r[2], r[3])
    end
    return true
end

return fdr_ui
