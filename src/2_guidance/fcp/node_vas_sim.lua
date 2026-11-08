-- src/node_vas_sim.lua
local node_vas_sim = {}

function node_vas_sim.run()
    local top_modem = peripheral.wrap("top")
    if top_modem then
        top_modem.open(10001)
        local timer_id = os.startTimer(0.5)
        while true do
            local ev, p1, ch = os.pullEvent()
            if ev == "modem_message" and ch == 10001 then
                if harness_set_state then
                    harness_set_state("rx_vectored_cmd", true)
                end
                top_modem.transmit(10011, 10011, { ver = "1.9.5", type = "MSG_AERO_CMD", payload = { surfaceCmd = 0.0 } })
                top_modem.transmit(10002, 10002, {
                    ver = "1.9.5", type = "MSG_FLIGHT_TELEMETRY",
                    payload = {
                        attitude = { pitch = 0.0, roll = 0.0, yaw = 0.0 },
                        angularRates = { p = 0.0, q = 0.0, r = 0.0 },
                        dynamics = { altitudeY = 64.0, verticalSpeed = 0.0, velocity = { vx = 0.0, vy = 0.0, vz = 0.0 }, heading = 0.0 },
                        fuel = 1.0,
                        controlState = "NORMAL",
                        activeSource = "FCP",
                        actuatorHealth = { tca = true, asa = true, allOk = true },
                    }
                })
                break
            elseif ev == "timer" and p1 == timer_id then
                break
            end
        end
    end
    return true
end

local args = { ... }
if select("#", ...) == 0 or args[1] == "run" then
    node_vas_sim.run()
end

return node_vas_sim
