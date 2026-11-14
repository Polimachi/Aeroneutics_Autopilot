-- Simulator for VAS and Alignment (Node 0) - Raw Modem ICD v1.9.5 (v1.4.0)
local packet_protocol = require("packet_protocol")

local modem = peripheral and peripheral.wrap and peripheral.wrap("top")
if not modem then error("Top modem not found on core_sim") end

local CH_ACTUATION = 10010
modem.open(CH_ACTUATION)

sleep(0.15)

local discoverReq = packet_protocol.encode_envelope(
    "AIRCRAFT_01",
    "MSG_ACTUATOR_DISCOVER_REQ",
    1,
    { requestDomain = "AIRCRAFT_01", targetGroup = "ALL" }
)
modem.transmit(CH_ACTUATION, CH_ACTUATION, discoverReq)

local timerId = os.startTimer(0.6)
while true do
    local ev, p1, p2, _, p4 = os.pullEvent()
    if ev == "modem_message" and p2 == CH_ACTUATION then
        local pkt = p4
        if type(pkt) == "string" and textutils and textutils.unserializeJSON then
            pkt = textutils.unserializeJSON(pkt) or pkt
        end
        if type(pkt) == "table" and pkt.type == "MSG_ACTUATOR_DISCOVER_ACK" then
            if harness_set_state then
                harness_set_state("calib_ack", true)
            end
            local cmdPkt = packet_protocol.encode_envelope(
                "AIRCRAFT_01",
                "MSG_THRUST_CMD",
                2,
                { outputs = { THR_MAIN_L = 8 } }
            )
            modem.transmit(CH_ACTUATION, CH_ACTUATION, cmdPkt)
            sleep(0.1)
            break
        end
    elseif ev == "timer" and p1 == timerId then
        break
    end
end
