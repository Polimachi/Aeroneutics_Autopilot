-- VAS 51x19 Flight HUD Renderer (VICD-Spec / Gate 3 Optimized)
local quat = require("quat")

local ui_renderer = {}

function ui_renderer.clear_screen(surf)
    if not surf then return end
    if surf.setBackgroundColor then surf.setBackgroundColor(colors.black) end
    if surf.setTextColor then surf.setTextColor(colors.white) end
    if surf.clear then surf.clear() end
    if surf.setCursorPos then surf.setCursorPos(1, 1) end
end

function ui_renderer.restore_screen(surf)
    if not surf then return end
    if surf.setBackgroundColor then surf.setBackgroundColor(colors.black) end
    if surf.setTextColor then surf.setTextColor(colors.white) end
    if surf.clear then surf.clear() end
    if surf.setCursorPos then surf.setCursorPos(1, 1) end
end


function ui_renderer.make_gauge(val, minV, maxV, width)
    local clamped = math.max(minV, math.min(maxV, val or minV))
    local ratio = (maxV > minV) and ((clamped - minV) / (maxV - minV)) or 0
    local filled = math.floor(ratio * width + 0.5)
    return "[" .. string.rep("#", filled) .. string.rep(" ", width - filled) .. "]"
end

local function draw_line(surf, y, text, fg, bg)
    if not surf or not surf.setCursorPos then return end
    surf.setCursorPos(1, y)
    local tLen = string.len(text)
    local fgStr = type(fg) == "string" and fg or string.rep("0", tLen)
    local bgStr = type(bg) == "string" and bg or string.rep("f", tLen)
    if surf.blit then
        surf.blit(text, fgStr, bgStr)
    else
        surf.write(text)
    end
end

local function get_attitude_data(st)
    local com = (st.sensors and st.sensors.lastCom) or {}
    local att = com.attitude or (com.orientation and quat.to_euler(com.orientation)) or { pitch = 0, roll = 0, yaw = 0 }
    local dyn = com.dynamics or { altitudeY = 0, verticalSpeed = 0, velocity = {} }
    local vel = dyn.velocity or { vx = 0, vy = 0, vz = 0 }
    local horiz = math.sqrt((vel.vx or 0)^2 + (vel.vz or 0)^2)
    local fuelVal = math.floor((com.fuel or 1.0) * 1000)
    local fuelPct = math.floor((com.fuel or 1.0) * 100)
    return att, dyn, horiz, fuelVal, fuelPct
end

local function get_system_data(st)
    local fsm = st.fsm or {}
    local dev = (st.sensors and st.sensors.devices) or {}
    local roles = (st.sensors and (st.sensors.roles or (st.sensors.config and st.sensors.config.roles))) or {}
    local net = st.net or {}
    local mixer = st.mixer or {}
    local ctrl = st.controller or {}
    local gOk = dev.gimbal and "OK" or "NO"
    local aOk = dev.altitude and "OK" or "NO"
    local vReq = (roles.velocity and roles.velocity.required ~= false)
    local vOk = dev.velocity and "OK" or (vReq and "NO" or "--")
    local fReq = (roles.fuel and roles.fuel.required ~= false)
    local fOk = dev.fuel and "OK" or (fReq and "NO" or "--")
    local dLoad = math.floor(((mixer.dynamicLoad or 0) * 100) + 0.5)
    local pDemand = (ctrl.lastDemands and ctrl.lastDemands.pitch) or 0
    local tapStat = (mixer.tcaConnected == true) and "ONLINE" or "WAITING"
    return fsm, net, gOk, aOk, vOk, fOk, dLoad, ctrl, pDemand, tapStat
end

local function render_body_rows(surf, st)
    local att, dyn, horiz, fuelVal, fuelPct = get_attitude_data(st)
    local fsm, net, gOk, aOk, vOk, fOk, dLoad, ctrl, pDem, tapStat = get_system_data(st)

    local pGauge = ui_renderer.make_gauge(att.pitch or 0, -30, 30, 4)
    local rGauge = ui_renderer.make_gauge(att.roll or 0, -30, 30, 4)
    local yGauge = ui_renderer.make_gauge(att.yaw or 0, 0, 360, 4)
    local aGauge = ui_renderer.make_gauge(dyn.altitudeY or 0, 0, 250, 4)
    local vGauge = ui_renderer.make_gauge(dyn.verticalSpeed or 0, -10, 10, 4)
    local hGauge = ui_renderer.make_gauge(horiz, 0, 50, 4)
    local fGauge = ui_renderer.make_gauge(fuelVal, 0, 1000, 4)
    local dGauge = ui_renderer.make_gauge(dLoad, 0, 100, 4)

    local satText = ctrl.saturationFreeze and "FROZEN" or "NORMAL"
    local wStat = net.wirelessModem and "ONLINE" or "OFFLINE"
    local bStat = net.wiredModem and "ONLINE" or "OFFLINE"

    draw_line(surf, 4, string.format("| PITCH: %+5.1f* %s  | FSM STATE: %-13s|", att.pitch or 0, pGauge, fsm.currentState or "NORMAL"))
    draw_line(surf, 5, string.format("| ROLL : %+5.1f* %s  | DOMAIN   : %-13s|", att.roll or 0, rGauge, net.aircraftDomainId or "AIRCRAFT_01"))
    draw_line(surf, 6, string.format("| YAW  :  %4.1f* %s  | SENSORS  : G  A  V  F   |", att.yaw or 0, yGauge))
    draw_line(surf, 7, string.format("|                       | STATUS   : %-2s %-2s %-2s %-2s  |", gOk, aOk, vOk, fOk))
    draw_line(surf, 8, "|-----------------------+-------------------------|")
    draw_line(surf, 9, string.format("| ALT  : %5.1fm %s  | W.MODEM  : %-13s|", dyn.altitudeY or 0, aGauge, wStat))
    draw_line(surf, 10, string.format("| V.SPD:   %+4.1f %s  | B.MODEM  : %-13s|", dyn.verticalSpeed or 0, vGauge, bStat))
    draw_line(surf, 11, string.format("| HORIZ:   %4.1f %s  | TAP COMM : %-13s|", horiz, hGauge, tapStat))
    draw_line(surf, 12, "|-----------------------| [ACTUATOR & COMMS]      |")
    draw_line(surf, 13, string.format("| [RESOURCES]           | DYN.LOAD : %3d%% %s  |", dLoad, dGauge))
    draw_line(surf, 14, string.format("| FUEL :  %4dL %s  | SAT.CTRL : %-13s|", fuelVal, fGauge, satText))
    draw_line(surf, 15, string.format("| LEVEL:   %3d%% %s  | DEMAND P : %+5.2f        |", fuelPct, fGauge, pDem))
end

function ui_renderer.render_dashboard(surf, st)
    if not surf or not surf.setCursorPos then return end
    st = st or {}
    local fsmState = (st.fsm and st.fsm.currentState) or "STANDBY"
    local domain = (st.net and st.net.aircraftDomainId) or "AIRCRAFT_01"
    local tick = st.tickCount or 0
    local statText = (st.fsm and st.fsm.transitionReason) or "INIT"

    draw_line(surf, 1, string.format(" [VAS v1.10.0]       FLIGHT HUD      %-8s ", fsmState))
    draw_line(surf, 2, "+-----------------------+-------------------------+")
    draw_line(surf, 3, "| [ATTITUDE & DYNAMICS] | [SYSTEM & SENSORS]      |")

    render_body_rows(surf, st)

    draw_line(surf, 16, "+-----------------------+-------------------------+")
    local statSuffix = (st.mixer and st.mixer.isStaticFallback) and " [UNCALIB DERATED]" or ""
    local fullStat = statText .. statSuffix
    draw_line(surf, 17, string.format("| STATUS: %-40s|", string.sub(fullStat, 1, 40)))
    draw_line(surf, 18, "+-------------------------------------------------+")
    draw_line(surf, 19, string.format(" [Ctrl+T] Shutdown     Domain: %-11s T:%05d ", domain, tick))
end

return ui_renderer
