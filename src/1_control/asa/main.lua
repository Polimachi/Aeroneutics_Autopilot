-- ASA (Aerodynamic Surface Adapter) Main Daemon Entrypoint
package.path = package.path .. ";modules/?.lua;?.lua;src/1_control/asa/modules/?.lua;src/1_control/asa/?.lua"

local config_manager = require("config_manager")
local control_surface_mapper = require("control_surface_mapper")
local tui_dashboard = require("tui_dashboard")

local function select_modem(ports)
    local preferredSide = ports and ports.modemSide
    if preferredSide and peripheral and peripheral.isPresent and peripheral.isPresent(preferredSide) then
        if peripheral.getType and peripheral.getType(preferredSide) == "modem" then
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

local function init_state(cfg)
    local surfaces = control_surface_mapper.scan(peripheral)
    local state = {
        running = true,
        fsm = "READY_DISARMED",
        surfaces = surfaces,
        modes = {
            elevator = (surfaces and surfaces.elevator) and "API" or "RS",
            leftAileron = (surfaces and surfaces.leftAileron) and "API" or "RS",
            rightAileron = (surfaces and surfaces.rightAileron) and "API" or "RS",
            rudder = (surfaces and surfaces.rudder) and "API" or "RS",
            flaps = (surfaces and surfaces.flaps) and "API" or "RS"
        },
        deflections = {
            elevator = 0.0,
            leftAileron = 0.0,
            rightAileron = 0.0,
            rudder = 0.0,
            flaps = 0.0
        },
        saturated = {
            elevator = false,
            leftAileron = false,
            rightAileron = false,
            rudder = false,
            flaps = false
        },
        watchdogExpired = false,
        tickCount = 0,
        status = "INIT"
    }
    return state
end

local function run_daemon(state, cfg)
    state.running = true
    state.modes = state.modes or {}
    state.deflections = state.deflections or {}
    state.saturated = state.saturated or {}
    state.surfaces = state.surfaces or {}

    local wdTimeout = ((cfg and cfg.watchdogTimeoutMs) or 300) / 1000.0
    if os.startTimer then
        state.watchdogTimerId = os.startTimer(wdTimeout)
    end

    local modem = select_modem(cfg and cfg.ports)
    local surfaceChan = (cfg and cfg.channels and cfg.channels.surfaceActuation) or (((cfg and cfg.baseChannel) or 10000) + 11)
    if modem and modem.open then
        pcall(modem.open, surfaceChan)
    end

    while state.running do
        local ev, p1, p2, p3, p4, p5 = os.pullEventRaw()
        if ev == "terminate" then
            state.running = false
            break
        elseif ev == "timer" and p1 == state.watchdogTimerId then
            state.fsm = "SAFE_GLIDE"
            state.watchdogExpired = true
            state.status = "SAFE_GLIDE_TRIM"
            state.deflections.elevator = 0.1
            state.deflections.leftAileron = 0.0
            state.deflections.rightAileron = 0.0
            state.deflections.rudder = 0.0
            state.deflections.flaps = 0.0
            if os.startTimer then
                state.watchdogTimerId = os.startTimer(wdTimeout)
            end
        elseif ev == "modem_message" then
            local channel, replyChannel, msg = p2, p3, p4
            if channel == surfaceChan and type(msg) == "table" then
                if msg.type == "MSG_AERO_CMD" and msg.payload and msg.payload.surfaces then
                    if state.watchdogTimerId and os.cancelTimer then
                        pcall(os.cancelTimer, state.watchdogTimerId)
                    end
                    if os.startTimer then
                        state.watchdogTimerId = os.startTimer(wdTimeout)
                    end
                    state.watchdogExpired = false
                    state.fsm = "ARMED_NORMAL"
                    state.status = "NOMINAL"
                    local s = msg.payload.surfaces
                    if s.ELEV ~= nil or s.elevator ~= nil then state.deflections.elevator = tonumber(s.ELEV or s.elevator) or 0 end
                    if s.AIL_L ~= nil or s.leftAileron ~= nil then state.deflections.leftAileron = tonumber(s.AIL_L or s.leftAileron) or 0 end
                    if s.AIL_R ~= nil or s.rightAileron ~= nil then state.deflections.rightAileron = tonumber(s.AIL_R or s.rightAileron) or 0 end
                    if s.RUDD ~= nil or s.rudder ~= nil then state.deflections.rudder = tonumber(s.RUDD or s.rudder) or 0 end
                    if s.FLAP_L ~= nil or s.flaps ~= nil then state.deflections.flaps = tonumber(s.FLAP_L or s.flaps) or 0 end
                    state.tickCount = (state.tickCount or 0) + 1
                end
            end
        elseif ev == "peripheral" or ev == "peripheral_detach" then
            state.surfaces = control_surface_mapper.scan(peripheral)
            for k, dev in pairs(state.surfaces) do
                state.modes[k] = dev and "API" or "RS"
            end
        end
    end
end

local function run_tui(state, cfg)
    local ok, err = pcall(function()
        if term and term.clear then
            pcall(tui_dashboard.clear_screen, term)
        end
        pcall(tui_dashboard.render_dashboard, term, state, cfg)

        local uiTimer = os.startTimer and os.startTimer(0.2)
        while state.running do
            local ev, p1, p2, p3 = os.pullEventRaw()
            if ev == "key" then
                if p1 == ((keys and keys.q) or 16) or p1 == ((keys and keys.t) or 20) then
                    state.running = false
                    break
                elseif p1 == ((keys and keys.r) or 19) then
                    state.surfaces = control_surface_mapper.scan(peripheral)
                    for k, dev in pairs(state.surfaces) do
                        state.modes[k] = dev and "API" or "RS"
                    end
                    pcall(tui_dashboard.render_dashboard, term, state, cfg)
                end
            elseif ev == "timer" and p1 == uiTimer then
                pcall(tui_dashboard.render_dashboard, term, state, cfg)
                if os.startTimer then
                    uiTimer = os.startTimer(0.2)
                end
            elseif ev == "terminate" then
                state.running = false
                break
            end
        end
    end)

    if not ok then
        -- Fault isolation: if an unhandled fatal error occurred in run_tui,
        -- do NOT exit immediately (which causes parallel.waitForAny to kill run_daemon).
        -- Idle silently until state.running becomes false so run_daemon finishes safely.
        while state.running do
            os.pullEventRaw()
        end
    end
end

local function main(cfgPathOrTable)
    local cfg
    if type(cfgPathOrTable) == "table" then
        cfg = cfgPathOrTable
    else
        local path = cfgPathOrTable or "config.json"
        cfg = config_manager.load(path)
        if not cfg then
            cfg = config_manager.default_config()
            pcall(config_manager.save, path, cfg)
        end
    end

    local state = init_state(cfg)
    local isDebug = not (cfg.debug == false)

    if isDebug then
        if parallel and parallel.waitForAny then
            parallel.waitForAny(
                function() run_daemon(state, cfg) end,
                function() run_tui(state, cfg) end
            )
        else
            run_daemon(state, cfg)
        end
        if term and term.clear then
            pcall(tui_dashboard.restore_screen, term)
        end
    else
        local baseChan = cfg.baseChannel or 10000
        local dominantMode = cfg.interactionMode or (state.modes and state.modes.elevator) or "REDSTONE"
        print(string.format("[ASA] Surface daemon running in HEADLESS mode (Base: %d, Mode: %s)", baseChan, dominantMode))
        run_daemon(state, cfg)
    end

    print("[ASA] Surface daemon terminated.")
    return state
end

if _G.describe == nil then
    main(...)
end

return {
    run = main,
    main = main,
    run_daemon = run_daemon,
    run_tui = run_tui,
    init_state = init_state,
    select_modem = select_modem
}
