-- Mock Node 04: FCP (Flight Control Program) ICD v1.24.0 / FCP v1.14.0
local modem = (peripheral and peripheral.wrap and peripheral.wrap("top")) or (peripheral and peripheral.find and peripheral.find("modem"))
if not modem then
    error("No modem peripheral found on mock FCP")
end

local CH_GUIDANCE, CH_TELEM = 10001, 10002
modem.open(CH_TELEM)

local nowMs = (os.epoch and os.epoch("utc")) or 0
local armCmd = {
    ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1,
    type = "MSG_ATTITUDE_CMD", time = nowMs,
    payload = {
        source = "FCP",
        flightMode = "TAKEOFF", commandType = "ATTITUDE_ANGLE",
        angleTargets = { targetPitch = 5.0, targetRoll = 0.0, targetHeading = 90.0, turnRateFF = 0.0 },
        targetThrottle = 8.5, targetClimbRate = 0.0, flapTarget = 0.0,
        translationBias = { surge = 0.0, sway = 0.0, heave = 0.0 },
        arm = true, flightActive = true
    }
}
modem.transmit(CH_GUIDANCE, CH_GUIDANCE, armCmd)

local timerId = os.startTimer(0.05)
while true do
    local ev, p1, p2, _, p4 = os.pullEvent()
    if ev == "modem_message" and p2 == CH_TELEM and type(p4) == "table" and p4.type == "MSG_FLIGHT_TELEMETRY" then
        if _G.harness_set_state then
            _G.harness_set_state("telemetry_received", true)
        end
        armCmd.seq = (armCmd.seq + 1) % 65536
        armCmd.time = (os.epoch and os.epoch("utc")) or 0
        modem.transmit(CH_GUIDANCE, CH_GUIDANCE, armCmd)
    elseif ev == "timer" and p1 == timerId then
        armCmd.seq = (armCmd.seq + 1) % 65536
        armCmd.time = (os.epoch and os.epoch("utc")) or 0
        modem.transmit(CH_GUIDANCE, CH_GUIDANCE, armCmd)
        timerId = os.startTimer(0.05)
    end
end
