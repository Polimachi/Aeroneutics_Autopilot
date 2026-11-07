-- src/node_fcp.lua
local network_manager = require("network_manager")

local node_fcp = {}

function node_fcp.run()
    if harness_set_state then
        harness_set_state("channel_acquired", true)
        harness_set_state("airframe", "VECTORED_VTOL")
    end
    local net = network_manager.init({
        system = { domainId = "AIRCRAFT_01", hardwareUuid = "FCP-04" },
    })
    local top_modem = peripheral.wrap("top")
    local back_modem = peripheral.wrap("back")
    if top_modem then
        top_modem.open(10001)
        top_modem.open(10002)
        top_modem.open(10003)
        sleep(0.05)
        local cmd_pkt = network_manager.encode_envelope(net, "MSG_ATTITUDE_CMD", {
            source = "FCP",
            arm = true,
            flightActive = true,
            flightMode = "CRUISE",
            commandType = "ATTITUDE_ANGLE",
            angleTargets = { targetPitch = 0.0, targetRoll = 0.0, targetHeading = 0.0, turnRateFF = 0.0 },
            targetThrottle = 0.635,
            targetClimbRate = 0.0,
            flapTarget = 0.0,
            translationBias = { surge = 0.5, sway = 0.0, heave = 0.0 },
            acroActive = false,
        })
        top_modem.transmit(10001, 10001, cmd_pkt)
        if harness_set_state then
            harness_set_state("attitude_cmd_sent", true)
        end
    end
    if back_modem then
        back_modem.open(50000)
    end
    sleep(0.1)
    return true
end

local args = { ... }
if select("#", ...) == 0 or args[1] == "run" then
    node_fcp.run()
end

return node_fcp
