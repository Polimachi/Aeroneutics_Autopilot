-- src/node_infra_sim.lua
local network_manager = require("network_manager")

local node_infra_sim = {}

function node_infra_sim.run()
    local back_modem = peripheral.wrap("back")
    if back_modem then
        back_modem.open(50000)
        back_modem.open(60001)
        local net = network_manager.init({
            system = { domainId = "GPS_BASE_NET", hardwareUuid = "INFRA-01" },
        })
        local timer_id = os.startTimer(0.5)
        while true do
            local ev, p1, ch, reply_ch, msg = os.pullEvent()
            if ev == "modem_message" and ch == 60001 and reply_ch then
                local req = network_manager.decode_envelope(msg)
                local client_seq = (req and req.payload and req.payload.clientSeq) or 1
                local fix = network_manager.encode_envelope(net, "MSG_GPS_RESPONSE", {
                    targetClient = "AIRCRAFT_01",
                    clientSeq = client_seq,
                    status = "FIX_OK",
                    position = { x = 10.0, z = -20.0 },
                    accuracy = 0.5,
                    hdop = 1.0,
                    nodeCount = 4,
                    selectedNodes = { "NODE_01", "NODE_02", "NODE_03", "NODE_04" },
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
