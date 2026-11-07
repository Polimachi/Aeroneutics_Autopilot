-- src/modules/channel_sentinel.lua
local channel_sentinel = {}

function channel_sentinel.init(config)
    local cfg = config or {}
    local chs = cfg.channels or {}
    local safe = cfg.safety or {}
    return {
        status = "INIT",
        baseChannel = chs.baseChannel or 10060,
        bootstrapChannel = chs.bootstrapChannel or 10000,
        candidateBase = chs.baseChannel or 10060,
        gcsBootstrapTimeoutMs = safe.gcsBootstrapTimeoutMs or 1000,
        channelProbeWaitMs = safe.channelProbeWaitMs or 200,
        bootstrapStartMs = 0,
        probeStartMs = 0,
        locked = false,
        conflictReason = nil,
    }
end

function channel_sentinel.start_bootstrap(state, now_ms)
    state.bootstrapStartMs = now_ms or 0
    state.status = "WAIT_BLOCK_ASSIGN"
    return {
        type = "MSG_BLOCK_REQUEST",
        candidateBaseChannel = state.baseChannel,
        preferredBandwidth = 20,
    }
end

function channel_sentinel.on_block_assign(state, payload, now_ms)
    if payload and payload.assignedBaseChannel then
        state.candidateBase = payload.assignedBaseChannel
    else
        state.candidateBase = state.baseChannel
    end
    state.status = "START_PROBE"
end

function channel_sentinel.probe_channel(state, candidate_base, now_ms)
    local c = candidate_base or state.candidateBase or state.baseChannel
    state.candidateBase = c
    state.probeStartMs = now_ms or 0
    state.status = "PROBING"
    return {
        type = "MSG_CHANNEL_PROBE",
        candidateBaseChannel = c,
    }
end

function channel_sentinel.on_probe_ack(state, packet)
    local payload = packet and packet.payload or {}
    if payload.conflict or packet.type == "MSG_CHANNEL_PROBE_ACK" then
        state.locked = true
        state.status = "ARMING_LOCKED"
        state.conflictReason = "RF_CHANNEL_CONFLICT"
    end
end

local function step_probing(state, now_ms, inbound)
    local p = inbound and inbound.probe
    if p and (p.type == "MSG_CHANNEL_PROBE_ACK" or (p.payload and p.payload.conflict)) then
        channel_sentinel.on_probe_ack(state, p)
        return state.status, nil
    end
    if (now_ms - state.probeStartMs) >= state.channelProbeWaitMs then
        state.baseChannel = state.candidateBase
        state.status = "ACQUIRED"
        state.locked = false
        return state.status, nil
    end
    return state.status, nil
end

function channel_sentinel.negotiate_and_probe(state, now_ms, inbound_packets)
    if not state then return "NO_STATE", nil end
    local now = now_ms or 0
    if state.status == "INIT" then
        local boot_payload = channel_sentinel.start_bootstrap(state, now)
        return state.status, boot_payload
    elseif state.status == "WAIT_BLOCK_ASSIGN" then
        if (now - state.bootstrapStartMs) >= state.gcsBootstrapTimeoutMs then
            local probe_payload = channel_sentinel.probe_channel(state, state.baseChannel, now)
            return state.status, probe_payload
        end
        return state.status, nil
    elseif state.status == "START_PROBE" then
        local probe_payload = channel_sentinel.probe_channel(state, state.candidateBase, now)
        return state.status, probe_payload
    elseif state.status == "PROBING" then
        return step_probing(state, now, inbound_packets)
    end
    return state.status, nil
end

function channel_sentinel.handle_incoming_probe(state, packet)
    if state.status == "ACQUIRED" and packet and packet.payload then
        local target = packet.payload.candidateBaseChannel
        if target == state.baseChannel then
            return {
                type = "MSG_CHANNEL_PROBE_ACK",
                payload = {
                    conflict = true,
                    baseChannel = state.baseChannel,
                    occupantId = "SAS",
                },
            }
        end
    end
    return nil
end

function channel_sentinel.is_locked(state)
    return state and (state.locked == true or state.status == "ARMING_LOCKED")
end

function channel_sentinel.is_acquired(state)
    return state and state.status == "ACQUIRED" and not state.locked
end

function channel_sentinel.initiate_rebind(state, new_base, now_ms)
    local tx_id = "REBIND-TX-" .. tostring(state.baseChannel) .. "-" .. tostring(new_base)
    state.rebindTx = {
        txId = tx_id,
        newBase = new_base,
        oldBase = state.baseChannel,
        startMs = now_ms or 0,
        status = "PREPARE",
    }
    return {
        type = "MSG_CHANNEL_REBIND",
        payload = {
            transactionId = tx_id,
            action = "PREPARE",
            oldBaseChannel = state.baseChannel,
            newBaseChannel = new_base,
            bandwidth = 20,
        },
    }
end

function channel_sentinel.on_rebind_ack(state, packet, now_ms)
    local payload = packet and packet.payload or {}
    if state and state.rebindTx and payload.transactionId == state.rebindTx.txId then
        state.rebindTx.status = "ACKED"
        return true
    end
    return false
end

function channel_sentinel.step_rebind_transaction(state, now_ms)
    if not state or not state.rebindTx then return nil, "NO_TRANSACTION" end
    local tx = state.rebindTx
    local now = now_ms or 0

    if tx.status == "ACKED" then
        tx.status = "COMMITTED"
        state.baseChannel = tx.newBase
        state.candidateBase = tx.newBase
        return {
            type = "MSG_CHANNEL_REBIND",
            payload = {
                transactionId = tx.txId,
                action = "COMMIT",
                oldBaseChannel = tx.oldBase,
                newBaseChannel = tx.newBase,
                bandwidth = 20,
            },
        }, "COMMITTED"
    end

    if (now - tx.startMs) > 500 then
        tx.status = "ROLLED_BACK"
        return {
            type = "MSG_CHANNEL_REBIND",
            payload = {
                transactionId = tx.txId,
                action = "ROLLBACK",
                oldBaseChannel = tx.oldBase,
                newBaseChannel = tx.newBase,
                bandwidth = 20,
            },
        }, "ROLLED_BACK"
    end

    return nil, tx.status
end

return channel_sentinel
