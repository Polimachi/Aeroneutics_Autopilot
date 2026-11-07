-- Mock Node 06: WAP (Wing Actuator Pod) Cluster ICD v1.19.0 / WAP v1.2.0
local modem = (peripheral and peripheral.wrap and peripheral.wrap("top")) or (peripheral and peripheral.find and peripheral.find("modem"))
if not modem then
    error("No modem peripheral found on mock WAP")
end

local CH_AERO = 10027
modem.open(CH_AERO)

while true do
    local _, _, ch, _, msg = os.pullEvent("modem_message")
    if ch == CH_AERO and type(msg) == "table" and msg.type == "MSG_AERO_CMD" then
        if _G.harness_set_state then
            _G.harness_set_state("aero_cmd_received", true)
        end
        local statusPkt = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1,
            type = "MSG_AERO_STATUS", time = (os.epoch and os.epoch("utc")) or 0,
            payload = {
                surfaceId = "ELEV", appliedDeg = 3.0, appliedRatio = 0.20,
                isSaturated = false, healthStatus = "API_NOMINAL"
            }
        }
        modem.transmit(CH_AERO, CH_AERO, statusPkt)
    end
end
