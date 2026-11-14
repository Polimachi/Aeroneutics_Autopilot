-- Dynamic Hangar Bay Binding and 2-Phase Base Channel Rebinding for TCA (Master ICD v1.30.0 & TCA v1.12.0)
local packet_protocol = require("packet_protocol")
local config_manager = require("config_manager")

local channel_rebind_handler = {}
local ACTUATION_OFFSET = 10
local REBIND_TIMEOUT_MS = 500
channel_rebind_handler.ACTUATION_OFFSET = ACTUATION_OFFSET
channel_rebind_handler.REBIND_TIMEOUT_MS = REBIND_TIMEOUT_MS

local function now_ms()
    return (os and os.epoch and os.epoch("utc")) or 0
end

local function cancel_rebind_timer(prep)
    if prep and prep.rebindTimerId and os and os.cancelTimer then
        pcall(os.cancelTimer, prep.rebindTimerId)
    end
end

local function send_rebind_ack(modem, txChan, cfg, seq, txId, action, status, oldBase, newBase)
    if not modem or not modem.transmit or not txChan then return end
    local payload = {
        transactionId = txId,
        nodeId = (cfg and cfg.groupId) or "THR_MAIN_L",
        action = action,
        status = status,
        oldBaseChannel = oldBase,
        newBaseChannel = newBase
    }
    local ackPkt = packet_protocol.encode_envelope(cfg and cfg.aircraftDomainId, "MSG_CHANNEL_REBIND_ACK", seq or 0, payload)
    pcall(modem.transmit, txChan, txChan, ackPkt)
end

--- Handle dynamic hangar bay binding from VAS
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
function channel_rebind_handler.handle_rollback(modem, pkt, state, cfg, replyChannel)
    local p = pkt and pkt.payload
    local prep = state and state.preparedRebind
    cancel_rebind_timer(prep)
    local newBase = (prep and prep.newBaseChannel) or (p and tonumber(p.newBaseChannel))
    local oldBase = (prep and prep.oldBaseChannel) or (p and tonumber(p.oldBaseChannel)) or (cfg and cfg.baseChannel)
    local txId = (prep and prep.transactionId) or (p and p.transactionId)
    if newBase and modem and modem.close then
        pcall(modem.close, newBase + ACTUATION_OFFSET)
    end
    if state then state.preparedRebind = nil end
    local tx = replyChannel or (prep and prep.replyChannel) or (cfg and cfg.channels and cfg.channels.thrustActuation)
    if cfg and txId then
        send_rebind_ack(modem, tx, cfg, pkt and pkt.seq, txId, "ROLLBACK", "ROLLED_BACK", oldBase, newBase)
    end
    return true, "ROLLED_BACK"
end

--- Handle Phase 2 COMMIT of channel rebinding
function channel_rebind_handler.handle_rebind_commit(modem, pkt, cfg, state, configPath, replyChannel)
    local p = pkt and pkt.payload
    if not p or not cfg or not state then return false, "INVALID_ARGS" end
    local prep = state.preparedRebind
    cancel_rebind_timer(prep)
    local newBase = tonumber(p.newBaseChannel) or (prep and prep.newBaseChannel)
    if not newBase then return false, "MISSING_NEW_BASE" end
    local oldBase = (prep and prep.oldBaseChannel) or tonumber(p.oldBaseChannel) or cfg.baseChannel
    local oldActuation = cfg.channels and cfg.channels.thrustActuation
    if oldActuation and modem and modem.close then pcall(modem.close, oldActuation) end

    cfg.baseChannel = newBase
    if not cfg.channels then cfg.channels = {} end
    cfg.channels.thrustActuation = newBase + ACTUATION_OFFSET
    if modem and modem.open then pcall(modem.open, cfg.channels.thrustActuation) end
    cfg.aircraftIndexN = tonumber(p.newAircraftIndexN) or (math.floor((newBase - 10000) / 40) + 1)

    local path = configPath or cfg.configPath or "config.json"
    pcall(config_manager.save, path, cfg)
    state.preparedRebind = nil
    local tx = replyChannel or (prep and prep.replyChannel) or oldActuation
    send_rebind_ack(modem, tx, cfg, pkt.seq, (prep and prep.transactionId) or p.transactionId, "COMMIT", "COMMITTED", oldBase, newBase)
    return true, "COMMITTED"
end

--- Handle channel rebinding (PREPARE, COMMIT, ROLLBACK)
function channel_rebind_handler.handle_channel_rebind(modem, replyChannel, pkt, cfg, state, configPath)
    local p = pkt and pkt.payload
    if not p or not cfg or not state then return false, "INVALID_ARGS" end
    if p.action == "ROLLBACK" then
        return channel_rebind_handler.handle_rollback(modem, pkt, state, cfg, replyChannel)
    elseif p.action == "COMMIT" then
        return channel_rebind_handler.handle_rebind_commit(modem, pkt, cfg, state, configPath, replyChannel)
    elseif p.action ~= "PREPARE" then
        return false, "INVALID_ACTION"
    end

    local newBase = tonumber(p.newBaseChannel)
    if not newBase then return false, "MISSING_NEW_BASE" end
    cancel_rebind_timer(state.preparedRebind)
    if modem and modem.open then pcall(modem.open, newBase + ACTUATION_OFFSET) end

    local oldBase = tonumber(p.oldBaseChannel) or cfg.baseChannel
    local tx = replyChannel or (cfg.channels and cfg.channels.thrustActuation)
    local timerId = (os and os.startTimer and os.startTimer(REBIND_TIMEOUT_MS / 1000.0)) or nil
    state.preparedRebind = {
        transactionId = p.transactionId,
        oldBaseChannel = oldBase,
        newBaseChannel = newBase,
        newAircraftIndexN = p.newAircraftIndexN or cfg.aircraftIndexN,
        startMs = now_ms(),
        rebindTimerId = timerId,
        replyChannel = tx
    }
    send_rebind_ack(modem, tx, cfg, pkt.seq, p.transactionId, "PREPARE", "READY", oldBase, newBase)
    return true, "PREPARED"
end

--- Check if prepared rebind exceeded 500ms timeout and auto-rollback
function channel_rebind_handler.check_timeout(modem, cfg, state, currentMs)
    local prep = state and state.preparedRebind
    if not prep then return false end
    local cur = tonumber(currentMs) or now_ms()
    if (cur - (prep.startMs or cur)) >= REBIND_TIMEOUT_MS then
        channel_rebind_handler.handle_rollback(modem, nil, state, cfg, prep.replyChannel)
        return true
    end
    return false
end

--- Handle timer event for 500ms PREPARE timeout watchdog
function channel_rebind_handler.handle_timer(modem, cfg, state, timerId, currentMs)
    local prep = state and state.preparedRebind
    if not prep or not timerId or prep.rebindTimerId ~= timerId then return false end
    return channel_rebind_handler.handle_rollback(modem, nil, state, cfg, prep.replyChannel)
end

return channel_rebind_handler
