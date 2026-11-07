-- src/node_infra_sim.lua
local network_manager = require("network_manager")

local node_infra_sim = {}

function node_infra_sim.run()
    local back_modem = peripheral.wrap("back")
    if back_modem then
        back_modem.open(50000)
        back_modem.open(60001)
        back_modem.open(30004)
        local net = network_manager.init({
            system = { domainId = "FACILITY_INFRA", hardwareUuid = "INFRA-01" },
        })
        local timer_id = os.startTimer(0.5)
        while true do
            local ev, p1, ch, reply_ch = os.pullEvent()
            if ev == "modem_message" and (ch == 60001 or ch == 30004) and reply_ch then
                local fix = network_manager.encode_envelope(net, "MSG_GPS_FIX", {
                    pos = { x = 0.0, y = 64.0, z = 0.0 },
                    hdop = 0.9,
                    sats = 8,
                })
                back_modem.transmit(reply_ch, ch, fix)
            elseif ev == "timer" and p1 == timer_id then
                break
            end
        end
    end
    if harness_set_state then
        harness_set_state("infra_online", true)
    end
    return true
end

local args = { ... }
if select("#", ...) == 0 or args[1] == "run" then
    node_infra_sim.run()
end

return node_infra_sim
