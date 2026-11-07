-- Actuator Discovery Dual-Binding Engine for TCA (Master ICD v1.15.0 & TCA v1.4.0)
local packet_protocol = require("packet_protocol")

local discovery_handler = {}

--- Check if the discovery request targets this node's group or wildcard ALL
function discovery_handler.is_target_matched(payload, myGroupId)
    if not payload or type(payload) ~= "table" then return true end
    local target = payload.targetThrusterId
    if not target or target == "ALL" or target == myGroupId then return true end
    return false
end

--- Resolve active count, total nominal count, and interaction mode
function discovery_handler.resolve_counts(cfg, adapterState, dispatchedCount)
    local mode = (adapterState and adapterState.interactionMode) or (cfg and (cfg.interactionMode or cfg.mode)) or "REDSTONE"
    if mode == "REDSTONE" then
        return 1, 1, "REDSTONE"
    end
    local devCount = dispatchedCount
    if not devCount and adapterState and adapterState.peripherals then
        devCount = #adapterState.peripherals
    end
    local act = tonumber(devCount) or 0
    local tot = (cfg and tonumber(cfg.nominalActuatorCount)) or math.max(1, act)
    return act, tot, "API"
end

--- Compute health status from interaction mode, active count, and timeout status
function discovery_handler.compute_health_status(interactionMode, activeCount, totalCount, isTimeout)
    local mode = interactionMode or "REDSTONE"
    local act = tonumber(activeCount) or 0
    local tot = tonumber(totalCount) or 1
    if mode == "REDSTONE" then
        if isTimeout then return "REDSTONE_TIMEOUT" end
        return "REDSTONE_NOMINAL"
    else
        if act <= 0 then return "API_TOTAL_LOSS" end
        if isTimeout then return "API_TIMEOUT" end
        if act < tot then return "API_DEGRADED" end
        return "API_NOMINAL"
    end
end

--- Create MSG_ACTUATOR_DISCOVER_ACK packet envelope
function discovery_handler.create_ack(reqPkt, cfg, adapterState)
    local act, tot, mode = discovery_handler.resolve_counts(cfg, adapterState)
    local hStat = discovery_handler.compute_health_status(mode, act, tot, false)
    local domainId = (cfg and cfg.aircraftDomainId) or "AIRCRAFT_01"
    local seq = (reqPkt and tonumber(reqPkt.seq)) or 0

    return packet_protocol.encode_envelope(domainId, "MSG_ACTUATOR_DISCOVER_ACK", seq, {
        groupId = (cfg and cfg.groupId) or "THR_MAIN_L",
        interactionMode = mode,
        activeCount = act,
        totalCount = tot,
        healthStatus = hStat
    })
end

--- Process discovery request and respond on caller channel for session isolation
function discovery_handler.handle_request(modem, recvChannel, replyChannel, pkt, cfg, adapterState)
    if not pkt or pkt.type ~= "MSG_ACTUATOR_DISCOVER_REQ" then return false end
    if not discovery_handler.is_target_matched(pkt.payload, cfg.groupId) then return false end

    local ackPkt = discovery_handler.create_ack(pkt, cfg, adapterState)
    local txChan = replyChannel or recvChannel or cfg.channels.thrustActuation
    if modem and modem.transmit then
        pcall(modem.transmit, txChan, txChan, ackPkt)
    end
    return true, ackPkt
end

return discovery_handler
