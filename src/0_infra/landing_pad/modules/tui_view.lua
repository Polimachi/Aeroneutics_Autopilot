-- src/0_infra/landing_pad/modules/tui_view.lua
-- 51x19 standard terminal UI view renderer for Landing Pad

local tui_view = {}

local WIDTH = 51
local HEIGHT = 19

local function pad_line(content, width, leftChar, rightChar)
    local w = width or WIDTH
    local left = leftChar or "|"
    local right = rightChar or "|"
    local innerWidth = w - #left - #right

    local text = tostring(content or "")
    if #text > innerWidth then
        text = string.sub(text, 1, innerWidth)
    end
    local padLen = innerWidth - #text
    return left .. text .. string.rep(" ", padLen) .. right
end

local function separator_line(width)
    local w = width or WIDTH
    return "+" .. string.rep("-", w - 2) .. "+"
end

function tui_view.create(termDevice)
    local t = termDevice or term
    local view = {}

    local function write_at(y, str)
        if t and t.setCursorPos and t.write then
            t.setCursorPos(1, y)
            t.write(str)
        end
    end

    function view:clear()
        if t and t.clear then t.clear() end
        if t and t.setCursorPos then t.setCursorPos(1, 1) end
    end

    function view:render_countdown(padId, mode, remainingSec, sectorBase, tacticalCh)
        local lines = {}
        lines[1] = separator_line()
        lines[2] = pad_line("   CREATE: AERONAUTICS LANDING PAD CONTROLLER")
        lines[3] = pad_line(string.format("   Facility ID: %-14s | Mode: %-9s", padId or "PAD_01", mode or "DYNAMIC"))
        lines[4] = separator_line()
        lines[5] = pad_line("")
        lines[6] = pad_line("   Existing configuration detected.")
        lines[7] = pad_line(string.format("   Starting autonomous daemon in: [ %s ]", tostring(remainingSec or 3)))
        lines[8] = pad_line("")
        lines[9] = pad_line("   Press [S] to enter Setup Wizard")
        lines[10] = pad_line("   Press [D] to start Daemon immediately")
        lines[11] = pad_line("")
        lines[12] = pad_line(string.format("   Sector Base: %-6s | Tactical Ch: %-6s", tostring(sectorBase or 50201), tostring(tacticalCh or 50211)))
        lines[13] = pad_line("")
        lines[14] = pad_line("")
        lines[15] = pad_line("")
        lines[16] = pad_line("")
        lines[17] = pad_line("")
        lines[18] = separator_line()
        lines[19] = pad_line(" Status: BOOT_COUNTDOWN             [CraftOS-PC]")

        for y = 1, HEIGHT do
            write_at(y, lines[y] or pad_line(""))
        end
    end

    function view:render_daemon(data)
        local d = data or {}
        local lines = {}
        lines[1] = separator_line()
        lines[2] = pad_line(string.format(" %s [%s] | SEC: %s | TACT: %s",
            tostring(d.padId or "PAD"),
            tostring(d.mode or "DYNAMIC"),
            tostring(d.sectorIndex or 1),
            tostring(d.tacticalChannel or 50211)))
        lines[3] = pad_line(string.format(" Status: %-16s | Target: %s",
            tostring(d.state or "IDLE"),
            tostring(d.targetAircraft or "NONE")))
        lines[4] = separator_line()

        if d.mode == "DYNAMIC" then
            lines[5] = pad_line(" [TACTICAL GUIDANCE STREAM - 20Hz]")
            local tp = d.touchdownPoint or {}
            lines[6] = pad_line(string.format(" Touchdown: X=%-7.2f Y=%-6.2f Z=%-7.2f",
                tp.x or 0.0, tp.y or 0.0, tp.z or 0.0))
            local vel = d.velocity or {}
            lines[7] = pad_line(string.format(" Velocity : Vx=%+5.2f Vy=%+5.2f Vz=%+5.2f (m/s)",
                vel.vx or 0.0, vel.vy or 0.0, vel.vz or 0.0))
            lines[8] = pad_line(string.format(" Deck Tilt: %-5.2f deg (Limit: 10.0 deg)",
                d.tiltAngleDeg or 0.0))
            lines[9] = pad_line(string.format(" Heave    : %+5.2f m/s (Limit: 2.50 m/s)",
                d.heaveRateMps or 0.0))
            lines[10] = pad_line(string.format(" Deck Cond: [ %-7s ]  Landing: [ %s ]",
                tostring(d.deckStatus or "STABLE"),
                d.landingPermitted and "PERMITTED" or "HOLD"))
        else
            lines[5] = pad_line(" [STATIC BEACON MODE - 1Hz]")
            local tp = d.touchdownPoint or {}
            lines[6] = pad_line(string.format(" Touchdown: X=%-7.2f Y=%-6.2f Z=%-7.2f",
                tp.x or 0.0, tp.y or 0.0, tp.z or 0.0))
            lines[7] = pad_line(" Velocity : STATIC 0.00 m/s")
            lines[8] = pad_line(" Deck Tilt: 0.00 deg (RIGID GROUND)")
            lines[9] = pad_line(" Heave    : 0.00 m/s (STABLE)")
            lines[10] = pad_line(" Deck Cond: [ FIXED  ]  Landing: [ PERMITTED ]")
        end

        lines[11] = pad_line("")
        lines[12] = pad_line(" [LOCAL BACKBONE TRAFFIC]")
        lines[13] = pad_line(string.format(" Last GAC Sync: %.1fs ago", d.lastGacSyncSec or 0.0))
        lines[14] = pad_line(string.format(" Active Slot  : %ss remaining / %ss",
            tostring(d.slotRemainingSec or 0), tostring(d.slotDurationSec or 120)))
        lines[15] = pad_line("")
        lines[16] = pad_line("")
        lines[17] = pad_line("")
        lines[18] = separator_line()
        lines[19] = pad_line(tostring(d.lastLog or "STANDBY"), WIDTH, "|", "|")

        for y = 1, HEIGHT do
            write_at(y, lines[y] or pad_line(""))
        end
    end

    function view:render_halt_warning(scanReport)
        local rep = scanReport or {}
        local lines = {}
        lines[1] = separator_line()
        lines[2] = pad_line("   LANDING PAD COMMISSIONING WIZARD (Step 3/5)")
        lines[3] = pad_line("   * CRITICAL HARDWARE ERROR: SENSOR MISSING *")
        lines[4] = separator_line()
        lines[5] = pad_line(" Dynamic pad mode requires 3 physical sensors.")
        lines[6] = pad_line(" Current peripheral scan results:")
        lines[7] = pad_line("")
        lines[8] = pad_line(string.format("   [%s] avionics:gimbal_sensor   : %s",
            rep.gimbal and " OK " or "FAIL", rep.gimbal and "CONNECTED" or "NOT FOUND"))
        lines[9] = pad_line(string.format("   [%s] avionics:altitude_sensor : %s",
            rep.altitude and " OK " or "FAIL", rep.altitude and "CONNECTED" or "NOT FOUND"))
        lines[10] = pad_line(string.format("   [%s] avionics:velocity_sensor : %s",
            rep.velocity and " OK " or "FAIL", rep.velocity and "CONNECTED" or "NOT FOUND"))
        lines[11] = pad_line("")
        lines[12] = pad_line(" * CANNOT PROCEED WITH CURRENT HARDWARE SETUP *")
        lines[13] = pad_line(" Configuration commit is locked to prevent crash.")
        lines[14] = pad_line(" Check wired modem cables and sensor power.")
        lines[15] = pad_line("")
        lines[16] = pad_line(" Press [R] to Rescan      Press [Q] to Abort")
        lines[17] = pad_line("")
        lines[18] = separator_line()
        lines[19] = pad_line(" Status: HALT_WITH_WARNING        [CANNOT SAVE]")

        for y = 1, HEIGHT do
            write_at(y, lines[y] or pad_line(""))
        end
    end

    return view
end

return tui_view
