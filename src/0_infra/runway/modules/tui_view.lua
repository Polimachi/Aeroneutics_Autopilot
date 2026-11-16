-- src/0_infra/runway/modules/tui_view.lua
-- 51x19 console view renderer for Runway Controller

local tui_view = {}

local WIDTH = 51
local HEIGHT = 19

local function pad_line(content)
    local inner = WIDTH - 2
    local text = tostring(content or "")
    if #text > inner then text = string.sub(text, 1, inner) end
    return "|" .. text .. string.rep(" ", inner - #text) .. "|"
end

local function separator_line()
    return "+" .. string.rep("-", WIDTH - 2) .. "+"
end

function tui_view.create(termDevice)
    local t = termDevice or term
    local view = {}

    local function write_lines(lines)
        for y = 1, HEIGHT do
            if t and t.setCursorPos and t.write then
                t.setCursorPos(1, y)
                t.write(lines[y] or pad_line(""))
            end
        end
    end

    function view:clear()
        if t and t.clear then t.clear() end
        if t and t.setCursorPos then t.setCursorPos(1, 1) end
    end

    function view:render_daemon(d)
        local data = d or {}
        local td = data.touchdownPoint or {}
        local ep = data.endPoint or {}
        local lightWarn = data.lightStatus and data.lightStatus.warning or "WIRED_OK"
        local lines = {}
        lines[1] = separator_line()
        lines[2] = pad_line(string.format(" %s [%s] | SEC:%s | TACT:%s",
            tostring(data.facilityId or "RWY"), tostring(data.mobility or "DYNAMIC"),
            tostring(data.sectorId or 1), tostring(data.tacticalChannel or 50211)))
        lines[3] = pad_line(string.format(" State: %-15s | Target: %s",
            tostring(data.state or "IDLE"), tostring(data.targetAircraft or "NONE")))
        lines[4] = separator_line()
        lines[5] = pad_line(string.format(" Threshold: X=%-7.1f Y=%-5.1f Z=%-7.1f", td.x or 0, td.y or 0, td.z or 0))
        lines[6] = pad_line(string.format(" EndPoint : X=%-7.1f Y=%-5.1f Z=%-7.1f", ep.x or 0, ep.y or 0, ep.z or 0))
        lines[7] = pad_line(string.format(" ILS GS   : %.1f deg | TDZ: %dm | HDG: %03d",
            data.glideSlopeAngle or 3.0, math.floor(data.touchdownZoneLength or 80), math.floor(data.approachHeading or 0)))
        lines[8] = pad_line(string.format(" Deck Cond: [%-7s] | Permit: %s",
            tostring(data.deckStatus or "STABLE"), data.landingPermitted and "YES" or "HOLD"))
        lines[9] = pad_line(string.format(" Wired HW : %s", tostring(lightWarn)))
        lines[10] = pad_line(string.format(" Slot Left: %ss | GAC Sync: %.1fs",
            tostring(data.slotRemainingSec or 0), data.lastGacSyncSec or 0))
        lines[11] = separator_line()
        lines[12] = pad_line(" [S] Wizard  [F] Force Free  [L] Light Test  [Q] Quit")
        lines[18] = separator_line()
        lines[19] = pad_line(tostring(data.lastLog or "STANDBY"))
        write_lines(lines)
    end

    return view
end

return tui_view
