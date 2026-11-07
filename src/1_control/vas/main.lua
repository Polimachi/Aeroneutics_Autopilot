-- VAS Main Executable Entrypoint (Node 01)
local core_daemon = require("core_daemon")
local ui_renderer = require("ui_renderer")

local state = core_daemon.init("config")
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

if term and term.clear then
    term.setBackgroundColor(colors.black)
    term.clear()
end
ui_renderer.render_dashboard(term, state)

local lastRenderTick = 0

while state.running do
    local event, p1, p2, p3, p4 = os.pullEventRaw()
    core_daemon.handle_event(state, event, p1, p2, p3, p4)

    if state.tickCount and state.tickCount >= lastRenderTick + 2 then
        lastRenderTick = state.tickCount
        ui_renderer.render_dashboard(term, state)
    end

    if _G.harness_set_state then
        _G.harness_set_state("fsm_state", state.fsm.currentState)
        _G.harness_set_state("active_ticks", state.tickCount)
        _G.harness_set_state("tca_connected", state.adapter.tcaConnected)
    end
    if _G.__HARNESS_HIL_MODE and state.tickCount >= 10 then
        core_daemon.shutdown(state, "HIL_COMPLETE")
    end
end

if term and term.clear then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end
print("[VAS] Daemon terminated. Returning to shell.")
