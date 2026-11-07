-- Headless / TUI Non-blocking TCA Daemon Entrypoint
package.path = package.path .. ";modules/?.lua;tools/?.lua;?.lua;src/1_control/tca/modules/?.lua;src/1_control/tca/?.lua"
local config_manager = require("config_manager")
local tca_daemon = require("tca_daemon")
local tui_dashboard = require("tui_dashboard")
_G.__TCA_SETUP_IMPORTED_ONLY = true
local function load_setup_tool()
    local ok, mod = pcall(require, "tca_setup")
    if ok and type(mod) == "table" and mod.run then return mod end
    if fs and fs.exists and fs.exists("setup.lua") then
        local ok_do, res_do = pcall(dofile, "setup.lua")
        if ok_do and type(res_do) == "table" and res_do.run then return res_do end
    end
    return { run = function() print("[TCA] setup tool not found.") end }
end
local tca_setup = load_setup_tool()

local default_cfg = {
    schemaVersion = "1.2.0",
    groupId = "THR_MAIN_L",
    interactionMode = "REDSTONE",
    aircraftIndexN = 1,
    baseChannel = 10000,
    channels = { thrustActuation = 10006, calibration = 10004 },
    watchdogTimeoutMs = 300,
    nominalActuatorCount = 4,
    aircraftDomainId = "AIRCRAFT_01",
    ports = {
        modemSide = "top",
        redstoneSide = "bottom",
        apiSides = { "left", "right", "front", "back" }
    },
    deadband = 0
}

local function select_modem(ports)
    local preferredSide = ports and ports.modemSide
    if preferredSide and peripheral and peripheral.isPresent(preferredSide) then
        if peripheral.getType(preferredSide) == "modem" then
            return peripheral.wrap(preferredSide)
        end
    end
    if peripheral and peripheral.find then
        local wireless = peripheral.find("modem", function(_, dev) return dev.isWireless and dev.isWireless() end)
        if wireless then return wireless end
        return peripheral.find("modem")
    end
    return nil
end

local function handle_key_event(daemon, key, activeCfg, modemDev)
    if key == ((keys and keys.s) or 31) then
        daemon:pause()
        tca_setup.run()
        local newCfg = config_manager.load("config.json")
        if newCfg then
            activeCfg = newCfg
            if modemDev then
                pcall(modemDev.open, newCfg.channels.thrustActuation)
                pcall(modemDev.open, newCfg.channels.calibration)
            end
            daemon:resume(newCfg)
        end
        if term and term.clear then term.clear() end
        daemon.isDirty = true
    elseif key == ((keys and keys.d) or 32) then
        daemon:send_manual_ping()
    elseif key == ((keys and keys.t) or 20) then
        daemon:pause()
        if term and term.clear then term.clear() end
        print("[TCA] Daemon safely terminated by operator.")
        return false, activeCfg
    end
    return true, activeCfg
end

local cfg = config_manager.load("config.json")
if not cfg then
    cfg = default_cfg
    pcall(config_manager.save, "config.json", cfg)
end
local migrated = cfg.migratedLegacyBase
cfg.migratedLegacyBase = nil
if migrated then pcall(config_manager.save, "config.json", cfg) end

local modem = select_modem(cfg.ports)
if modem then
    pcall(modem.open, cfg.channels.thrustActuation)
    pcall(modem.open, cfg.channels.calibration)
end

local daemon = tca_daemon.init(cfg, modem)
daemon.sentinel:start_timer(cfg.watchdogTimeoutMs / 1000.0)
if migrated then daemon:push_log(string.format("[MIGRATE] Base -> %d (ICD N-1)", cfg.baseChannel)) end
tui_dashboard.render_full_screen(cfg, daemon)

while true do
    local ev, p1, p2, p3, p4 = os.pullEvent()
    if ev == "key" then
        local cont, nextCfg = handle_key_event(daemon, p1, cfg, modem)
        cfg = nextCfg
        if not cont then break end
    else
        local ok, keepGoing = pcall(daemon.step_event, daemon, ev, p1, p2, p3, p4)
        if not ok then
            daemon:push_log("[ERR] " .. tostring(keepGoing):sub(1, 35))
        elseif keepGoing == false then
            print("[TCA] Daemon terminated safely.")
            break
        end
    end
    if daemon.isDirty then
        tui_dashboard.render_full_screen(cfg, daemon)
        daemon.isDirty = false
    end
end
