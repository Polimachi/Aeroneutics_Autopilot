-- Dynamic Hangar Bay Binding and 2-Phase Base Channel Rebinding for TCA (Master ICD v1.19.0 & TCA v1.7.0)
local packet_protocol = require("packet_protocol")
local config_manager = require("config_manager")

local channel_rebind_handler = {}
local ACTUATION_OFFSET = 10
channel_rebind_handler.ACTUATION_OFFSET = ACTUATION_OFFSET

--- Handle dynamic hangar bay binding from VAC-Core
function channel_rebind_handler.handle_bay_bind(modem, pkt, state)
    local p = pkt and pkt.payload
    if not p or not state then return false, "INVALID_PAYLOAD" end
    local base = tonumber(p.baseHangarChannel) or 101

    if p.action == "OPEN" then
        state.hangarBayChannel = base + 3
        state.hangarPulseChannel = base + 0
        if modem and modem.open then
            pcall(modem.open, state.hangarPulseChannel)
            pcall(modem.open, state.hangarBayChannel)
        end
        return true, "BAY_OPENED"
    elseif p.action == "CLOSE" then
        if modem and modem.close then
            if state.hangarPulseChannel then pcall(modem.close, state.hangarPulseChannel) end
            if state.hangarBayChannel then pcall(modem.close, state.hangarBayChannel) end
        end
        state.hangarPulseChannel = nil
        state.hangarBayChannel = nil
        return true, "BAY_CLOSED"
    end
    return false, "UNKNOWN_ACTION"
end

--- Rollback prepared channel rebinding
function channel_rebind_handler.handle_rollback(modem, pkt, state)
    local p = pkt and pkt.payload
    local newBase = (state and state.preparedRebind and state.preparedRebind.newBaseChannel) or (p and p.newBaseChannel)
    if newBase and modem and modem.close then
        pcall(modem.close, newBase + ACTUATION_OFFSET)
    end
    if state then state.preparedRebind = nil end
    return true, "ROLLED_BACK"
end

--- Handle Phase 2 COMMIT of channel rebinding
function channel_rebind_handler.handle_rebind_commit(modem, pkt, cfg, state, configPath)
    local p = pkt and pkt.payload
    if not p or not cfg or not state then return false, "INVALID_ARGS" end
    local newBase = tonumber(p.newBaseChannel) or (state.preparedRebind and state.preparedRebind.newBaseChannel)
    if not newBase then return false, "MISSING_NEW_BASE" end

    local oldActuation = cfg.channels and cfg.channels.thrustActuation
    if oldActuation and modem and modem.close then pcall(modem.close, oldActuation) end

    cfg.baseChannel = newBase
    if not cfg.channels then cfg.channels = {} end
    cfg.channels.thrustActuation = newBase + ACTUATION_OFFSET
    cfg.channels.calibration = nil
    cfg.mode = nil
    if modem and modem.open then pcall(modem.open, cfg.channels.thrustActuation) end
    if p.newAircraftIndexN then
        cfg.aircraftIndexN = tonumber(p.newAircraftIndexN)
    else
        cfg.aircraftIndexN = math.floor((newBase - 10000) / 40) + 1
    end

    local path = configPath or (cfg and cfg.configPath) or "config.json"
    pcall(config_manager.save, path, cfg)
    state.preparedRebind = nil
    return true, "COMMITTED"
end

--- Handle channel rebinding (PREPARE, COMMIT, ROLLBACK)
function channel_rebind_handler.handle_channel_rebind(modem, replyChannel, pkt, cfg, state, configPath)
    local p = pkt and pkt.payload
    if not p or not cfg or not state then return false, "INVALID_ARGS" end
    if p.action == "ROLLBACK" then
        return channel_rebind_handler.handle_rollback(modem, pkt, state)
    elseif p.action == "COMMIT" then
        return channel_rebind_handler.handle_rebind_commit(modem, pkt, cfg, state, configPath)
    elseif p.action ~= "PREPARE" and p.action ~= nil then
        return false, "INVALID_ACTION"
    end

    local newBase = tonumber(p.newBaseChannel)
    if not newBase then return false, "MISSING_NEW_BASE" end

    local prepChan = newBase + ACTUATION_OFFSET
    if modem and modem.open then pcall(modem.open, prepChan) end

    local txId = p.transactionId or p.rebindId
    state.preparedRebind = {
        transactionId = txId,
        newBaseChannel = newBase,
        newAircraftIndexN = p.newAircraftIndexN or cfg.aircraftIndexN
    }

    local ackPayload = {
        transactionId = txId,
        nodeId = cfg.groupId or "THR_MAIN_L",
        status = "READY",
        subNodesOk = true
    }
    if p.rebindId then
        ackPayload.rebindId = p.rebindId
    end

    local ackPkt = packet_protocol.encode_envelope(cfg.aircraftDomainId, "MSG_CHANNEL_REBIND_ACK", pkt.seq or 0, ackPayload)
    local tx = replyChannel or (cfg.channels and cfg.channels.thrustActuation)
    if modem and modem.transmit and tx then pcall(modem.transmit, tx, tx, ackPkt) end
    return true, "PREPARED"
end

return channel_rebind_handler
