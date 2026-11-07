-- TCA Setup & Diagnostic CLI Wizard (v1.4.0)
package.path = package.path .. ";modules/?.lua;?.lua;src/1_control/tca/modules/?.lua;src/1_control/tca/?.lua"
local config_manager = require("config_manager")

local function load_active_config()
    local loaded = config_manager.load("config.json")
    if loaded then return loaded end
    return {
        schemaVersion = "1.2.0", groupId = "THR_MAIN_L", interactionMode = "REDSTONE",
        baseChannel = 10000, aircraftIndexN = 1, watchdogTimeoutMs = 300,
        aircraftDomainId = "AIRCRAFT_01", nominalActuatorCount = 4,
        channels = { thrustActuation = 10010 },
        ports = { modemSide = "top", redstoneSide = "bottom", apiSides = { "left", "right", "front", "back" } },
        deadband = 0
    }
end

local function scan_hardware()
    local devices = {}
    if peripheral and peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            if name ~= "modem" and peripheral.isPresent(name) then
                local pType = peripheral.getType(name)
                if pType and pType ~= "modem" then
                    table.insert(devices, { name = name, type = pType })
                end
            end
        end
    end
    return devices
end

local function render_ui(cfg, mode, devs)
    term.clear()
    local border = "+" .. string.rep("-", 49) .. "+"
    local lines = {
        [1] = "TCA CONSOLE | SETUP & DIAGNOSTICS (v1.4.0)",
        [2] = border,
        [3] = "AIRFRAME : " .. tostring(cfg.aircraftDomainId or "AIRCRAFT_01"),
        [4] = "GROUP ID : " .. tostring(cfg.groupId),
        [5] = "MODE: " .. tostring(mode) .. " | WATCHDOG: " .. tostring(cfg.watchdogTimeoutMs) .. "ms OK",
        [6] = "BASE CH  : " .. tostring(cfg.baseChannel) .. " (Aircraft N=" .. tostring(cfg.aircraftIndexN) .. ")",
        [7] = "+-- [ATTACHED PERIPHERALS] " .. string.rep("-", 23) .. "+",
        [8] = "DEV  NAME        TYPE",
        [9] = devs[1] and string.format("#1   %-11s %-30s", devs[1].name, devs[1].type) or "#1   (None)",
        [10] = devs[2] and string.format("#2   %-11s %-30s", devs[2].name, devs[2].type) or "#2   (None)",
        [11] = devs[3] and string.format("#3   %-11s %-30s", devs[3].name, devs[3].type) or "#3   (None)",
        [12] = devs[4] and string.format("#4   %-11s %-30s", devs[4].name, devs[4].type) or "#4   (None)",
        [13] = "+-- [CONTROLS] " .. string.rep("-", 35) .. "+",
        [14] = "[A] AirDomain [G] Group [M] Mode [N] AirN [ENT] Save",
        [15] = border
    }
    for y = 1, 15 do
        term.setCursorPos(1, y)
        term.write(lines[y])
    end
end

local function flush_char_events()
    if not os or not os.startTimer or not os.pullEvent then return end
    local id = os.startTimer(0)
    while true do
        local ev, p1 = os.pullEvent()
        if ev == "timer" and p1 == id then break end
    end
end

local function prompt_input(label, current)
    flush_char_events()
    term.setCursorPos(1, 16)
    term.clearLine()
    term.write(label .. " [" .. tostring(current) .. "]: ")
    local input = read and read() or current
    if input and input ~= "" then
        return input:gsub("^%s+", ""):gsub("%s+$", "")
    end
    return current
end

local function handle_key(key, cfg, currentMode, devs)
    if key == ((keys and keys.enter) or 28) then
        return false, currentMode
    elseif key == ((keys and keys.a) or 30) then
        cfg.aircraftDomainId = prompt_input("AirDomain", cfg.aircraftDomainId or "AIRCRAFT_01")
    elseif key == ((keys and keys.g) or 34) then
        cfg.groupId = prompt_input("Enter Group ID", cfg.groupId)
    elseif key == ((keys and keys.m) or 50) then
        currentMode = (currentMode == "REDSTONE") and "API" or "REDSTONE"
    elseif key == ((keys and keys.n) or 49) then
        local val = tonumber(prompt_input("Aircraft Index N", cfg.aircraftIndexN))
        if val and val >= 1 and val <= 1000 and math.floor(val) == val then
            cfg.aircraftIndexN = val
            cfg.baseChannel = config_manager.compute_base(val)
            if not cfg.channels then cfg.channels = {} end
            cfg.channels.thrustActuation = cfg.baseChannel + 10
            cfg.channels.calibration = nil
        end
    elseif key == ((keys and keys.c) or 46) then
        local cnt = tonumber(prompt_input("Nominal Count", cfg.nominalActuatorCount or 4))
        if cnt and cnt >= 1 then cfg.nominalActuatorCount = cnt end
    end
    return true, currentMode
end

local function run_setup()
    local cfg = load_active_config()
    local currentMode = cfg.interactionMode or "REDSTONE"
    local devs = scan_hardware()
    if #devs > 0 and not cfg.nominalActuatorCount then cfg.nominalActuatorCount = #devs end
    render_ui(cfg, currentMode, devs)

    while true do
        local ev, key = os.pullEvent()
        if ev == "key" then
            local cont, newMode = handle_key(key, cfg, currentMode, devs)
            currentMode = newMode
            if not cont then
                cfg.interactionMode = currentMode
                config_manager.save("config.json", cfg)
                break
            end
            render_ui(cfg, currentMode, devs)
        end
    end
    term.setCursorPos(1, 17)
    print("[TCA] Setup completed and saved to config.json.")
end

local M = {
    load_active_config = load_active_config,
    scan_hardware = scan_hardware,
    render_ui = render_ui,
    handle_key = handle_key,
    run = run_setup
}

if not _G.__TCA_SETUP_IMPORTED_ONLY then
    run_setup()
end

return M
