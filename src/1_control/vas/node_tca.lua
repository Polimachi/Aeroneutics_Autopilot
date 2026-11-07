-- Mock Node 02: TAP (Thrust Actuator Package) Cluster ICD v1.19.0 / TAP v1.7.0
local modem = (peripheral and peripheral.wrap and peripheral.wrap("top")) or (peripheral and peripheral.find and peripheral.find("modem"))
if not modem then
    error("No modem peripheral found on mock TAP")
end

local CH_ACTUATION = 10026
modem.open(CH_ACTUATION)

while true do
    local _, _, ch, _, msg = os.pullEvent("modem_message")
    if ch == CH_ACTUATION and type(msg) == "table" then
        if msg.type == "MSG_ACTUATOR_DISCOVER_REQ" then
            local ackPkt = {
                ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1,
                type = "MSG_ACTUATOR_DISCOVER_ACK", time = (os.epoch and os.epoch("utc")) or 0,
                payload = {
                    groupId = "THR_MAIN_L", mode = "REDSTONE", activeCount = 4, totalCount = 4,
                    healthStatus = "REDSTONE_NOMINAL"
                }
            }
            modem.transmit(CH_ACTUATION, CH_ACTUATION, ackPkt)
        elseif msg.type == "MSG_THRUST_CMD" then
            if _G.harness_set_state then
                _G.harness_set_state("thrust_cmd_received", true)
            end
            local statusPkt = {
                ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1,
                type = "MSG_ACTUATOR_STATUS", time = (os.epoch and os.epoch("utc")) or 0,
                payload = {
                    groupId = "THR_VTOL_F", interactionMode = "API", appliedSignal = 10,
                    appliedRatio = 10 / 15.0, isSaturated = false, activeCount = 6, totalCount = 6,
                    healthStatus = "API_NOMINAL"
                }
            }
            modem.transmit(CH_ACTUATION, CH_ACTUATION, statusPkt)
        end
    end
end
