-- TCA Node for Multi-Computer Cluster Simulation (Node 1) - Raw Modem ICD v1.9.5 (v1.4.0)
package.path = package.path .. ";modules/?.lua;?.lua;src/1_control/tca/modules/?.lua;src/1_control/tca/?.lua"
local actuator_adapter = require("actuator_adapter")
local group_allocator = require("group_allocator")
local watchdog_sentinel = require("watchdog_sentinel")
local config_manager = require("config_manager")
local discovery_handler = require("discovery_handler")

local cfg = config_manager.load("config.json") or {
    groupId = "THR_MAIN_L",
    interactionMode = "REDSTONE",
    channels = { thrustActuation = 10010 },
    aircraftDomainId = "AIRCRAFT_01"
}

local modem = peripheral and peripheral.wrap and peripheral.wrap("top")
if not modem then error("Top modem not found on tca_node") end

modem.open(cfg.channels.thrustActuation)

local adapterState = actuator_adapter.init(cfg.interactionMode or "REDSTONE", nil, cfg.ports)
local sentinel = watchdog_sentinel.init(300, function()
    actuator_adapter.cut_thrust(adapterState)
end)

local timeoutTimer = os.startTimer(0.7)
while true do
    local ev, p1, p2, p3, p4 = os.pullEvent()
    if ev == "modem_message" then
        local channel, replyChannel, rawMsg = p2, p3, p4
        local pkt = rawMsg
        if type(pkt) == "string" and textutils and textutils.unserializeJSON then
            pkt = textutils.unserializeJSON(pkt) or pkt
        end
        if type(pkt) == "table" then
            if pkt.type == "MSG_ACTUATOR_DISCOVER_REQ" then
                discovery_handler.handle_request(modem, channel, replyChannel, pkt, cfg, adapterState)
            elseif pkt.type == "MSG_CALIB_PULSE" and pkt.payload then
                local tgt = pkt.payload.targetThrusterId
                if not tgt or tgt == cfg.groupId or tgt == "ALL" then
                    sentinel:handle_pulse(pkt.payload.pulseLevel, pkt.payload.pulseDurationMs, adapterState)
                end
            elseif pkt.type == "MSG_THRUST_CMD" and pkt.payload and pkt.payload.outputs then
                sentinel:feed()
                local raw = group_allocator.extract_group_output(pkt.payload.outputs, cfg.groupId, cfg.deadband)
                local _, finalSig = actuator_adapter.apply_thrust(adapterState, raw, 1, 1)
                if harness_set_state then
                    harness_set_state("applied_signal", finalSig)
                end
                print("TCA_CLUSTER_SYNC_OK")
                sleep(0.05)
                break
            end
        end
    elseif ev == "timer" then
        if p1 == timeoutTimer then
            break
        else
            sentinel:handle_timer(p1)
        end
    end
end
