-- Ground Station Master Entrypoint for Alignment
local align_master = require("align_master")
local hud_renderer = require("hud_renderer")

local main = {}

local function load_config()
    local default_cfg = {
        station = {
            stationId = "HANGAR_BAY_01",
            bayId = 1,
            baseHangarChannel = 101,
            channels = {
                calibrationCmd = 101,
                calibrationTelem = 102,
                facilityInterlock = 103,
                tapDirect = 104
            }
        },
        safety = {
            tiltAbortDeg = 12.0,
            tiltWarnDeg = 8.0,
            watchdogTimeoutMs = 300,
            maxDeadband = 6.0,
            minR2Warning = 0.85
        }
    }
    if fs and fs.exists("config.json") then
        local f = fs.open("config.json", "r")
        if f then
            local content = f.readAll()
            f.close()
            if textutils and textutils.unserializeJSON then
                local parsed = textutils.unserializeJSON(content)
                if parsed and parsed.station then return parsed end
            end
        end
    end
    return default_cfg
end

local function handle_key_action(master, key_char)
    if not master then return true end
    if key_char == "q" or key_char == "Q" then
        align_master.step_fsm(master, { type = "ABORT" })
        return false
    elseif key_char == " " then
        align_master.step_fsm(master, { type = "PAUSE" })
    elseif key_char == "r" or key_char == "R" then
        align_master.step_fsm(master, { type = "RETRY" })
    elseif key_char == "y" or key_char == "Y" then
        align_master.step_fsm(master, { type = "USER_APPROVE" })
    end
    return true
end

function main.run()
    local cfg = load_config()
    local modem = (peripheral and peripheral.find and peripheral.find("modem")) or nil
    local mon = (peripheral and peripheral.find and peripheral.find("monitor")) or nil
    local display = mon or term
    local hud = hud_renderer.init(display)
    
    local master = nil
    if modem then
        master = align_master.init_bay_session(cfg, "AIRCRAFT_01", align_master.compute_craft_base(1), modem, (os.epoch and os.epoch("utc")) or 0)
    end
    
    hud:render_dashboard("STANDBY", { pitch = 0, roll = 0 }, "THR_MAIN_L", {})
    
    local running = true
    local ui_timer = os.startTimer(0.1)
    
    while running do
        local ev, p1, _, _, p4 = os.pullEventRaw()
        local now_ms = (os.epoch and os.epoch("utc")) or 0
        if ev == "timer" and p1 == ui_timer then
            if master then align_master.step_fsm(master, { type = "TICK" }, now_ms) end
            local st = master and align_master.get_state(master) or "STANDBY"
            local telem = (master and master.last_telem) or { pitch = 0, roll = 0 }
            local thr = (master and master.actuators and master.actuators[master.actuator_idx]) or "THR_MAIN_L"
            local reg = (master and master.last_regression) or {}
            hud:render_dashboard(st, telem, thr, reg)
            ui_timer = os.startTimer(0.1)
        elseif ev == "modem_message" and master then
            align_master.step_fsm(master, { type = "PACKET", channel = p1, packet = p4 }, now_ms)
        elseif ev == "char" then
            running = handle_key_action(master, p1)
        elseif ev == "terminate" then
            if master then align_master.release_channels(master) end
            running = false
        end
    end
end

if not _G.__HARNESS_HIL_MODE then
    main.run()
end

return main
