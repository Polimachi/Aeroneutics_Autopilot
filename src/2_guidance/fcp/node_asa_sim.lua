-- src/node_asa_sim.lua
local node_asa_sim = {}

function node_asa_sim.run()
    local top_modem = peripheral.wrap("top")
    local cmd_count = 0
    if top_modem then
        top_modem.open(10011)
        local timer_id = os.startTimer(0.6)
        while true do
            local ev, p1, ch = os.pullEvent()
            if ev == "modem_message" and ch == 10011 then
                cmd_count = cmd_count + 1
            elseif ev == "timer" and p1 == timer_id then
                break
            end
        end
    end
    if harness_set_state then
        harness_set_state("asa_cmd_count", cmd_count)
    end
    return true
end

local args = { ... }
if select("#", ...) == 0 or args[1] == "run" then
    node_asa_sim.run()
end

return node_asa_sim
