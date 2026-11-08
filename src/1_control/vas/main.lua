-- VAS Main Executable Entrypoint (Node 01)
local core_daemon = require("core_daemon")
local ui_renderer = require("ui_renderer")

local function run_daemon(state)
    while state.running do
        local event, p1, p2, p3, p4 = os.pullEventRaw()
        core_daemon.handle_event(state, event, p1, p2, p3, p4)

        if _G.harness_set_state then
            _G.harness_set_state("fsm_state", state.fsm.currentState)
            _G.harness_set_state("active_ticks", state.tickCount)
            _G.harness_set_state("tca_connected", state.adapter and state.adapter.tcaConnected)
        end
        if _G.__HARNESS_HIL_MODE and state.tickCount >= 10 then
            core_daemon.shutdown(state, "HIL_COMPLETE")
        end
    end
end

local function run_tui(state)
    local ok, err = pcall(function()
        if term and term.clear then
            pcall(ui_renderer.clear_screen, term)
        end
        pcall(ui_renderer.render_dashboard, term, state)

        local uiTimer = os.startTimer(0.2) -- 5Hz 비동기 UI 주기
        while state.running do
            local event, p1, p2, p3 = os.pullEventRaw()
            if event == "timer" and p1 == uiTimer then
                pcall(ui_renderer.render_dashboard, term, state)
                uiTimer = os.startTimer(0.2)
            elseif event == "key" then
                if p1 == ((keys and keys.q) or 16) or p1 == ((keys and keys.t) or 20) then
                    state.running = false
                    break
                end
            elseif event == "terminate" then
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

local function main(configDirOrTable)
    local state = core_daemon.init(configDirOrTable or "config")
    state.fsm.currentState = "NORMAL"

    if _G.harness_set_state then
        state.sensors.devices.gimbal = state.sensors.devices.gimbal or {
            getReading = function() return { pitch = 0, roll = 0, yaw = 0, pitchRate = 0, rollRate = 0, yawRate = 0 } end
        }
        state.sensors.devices.altitude = state.sensors.devices.altitude or {
            getReading = function() return { altitude = 100, verticalSpeed = 0 } end
        }
        state.sensors.devices.velocity = state.sensors.devices.velocity or {
            getReading = function() return { vx = 0, vy = 0, vz = 0 } end
        }
        state.sensors.devices.fuel = state.sensors.devices.fuel or {
            getReading = function() return { amount = 1000, capacity = 1000 } end
        }
    end

    if os.startTimer then
        state.timerId = os.startTimer(0.05)
    end

    local isDebug = not (state.cfg and state.cfg.system and state.cfg.system.debug == false)

    if isDebug then
        if parallel and parallel.waitForAny then
            parallel.waitForAny(
                function() run_daemon(state) end,
                function() run_tui(state) end
            )
        else
            run_daemon(state)
        end
        if term and term.clear then
            ui_renderer.restore_screen(term)
        end
    else
        local baseChan = (state.cfg and state.cfg.system and state.cfg.system.baseChannel)
            or (state.net and state.net.baseChannel) or 10000
        print(string.format("[VAS] Core running in HEADLESS mode (Node 01, Base: %d)", baseChan))
        run_daemon(state)
    end

    print("[VAS] Daemon terminated. Returning to shell.")
    return state
end

if _G.describe == nil then
    main(...)
end

return {
    main = main,
    run_daemon = run_daemon,
    run_tui = run_tui
}
