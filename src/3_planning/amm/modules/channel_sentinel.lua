-- src/3_planning/amm/modules/channel_sentinel.lua
local channel_sentinel = {}

channel_sentinel.CRAFT_BASE_MIN = 10000
channel_sentinel.CRAFT_BASE_MAX = 49960
channel_sentinel.CRAFT_BANDWIDTH = 40
channel_sentinel.DEFAULT_BOOTSTRAP_CH = 50000

local CRAFT_BASE_MIN = channel_sentinel.CRAFT_BASE_MIN
local CRAFT_BASE_MAX = channel_sentinel.CRAFT_BASE_MAX
local CRAFT_BANDWIDTH = channel_sentinel.CRAFT_BANDWIDTH
local DEFAULT_BOOTSTRAP_CH = channel_sentinel.DEFAULT_BOOTSTRAP_CH

function channel_sentinel.compute_base(n)
    if not n or n < 1 then return nil end
    local base = CRAFT_BASE_MIN + (n - 1) * CRAFT_BANDWIDTH
    if base > CRAFT_BASE_MAX then return nil end
    return base
end

function channel_sentinel.is_valid_base(baseCh)
    if type(baseCh) ~= "number" then return false end
    if baseCh < CRAFT_BASE_MIN or baseCh > CRAFT_BASE_MAX then return false end
    if (baseCh - CRAFT_BASE_MIN) % CRAFT_BANDWIDTH ~= 0 then return false end
    return true
end

function channel_sentinel.init(config)
    local cfg = config or {}
    local chs = cfg.channels or {}
    local safe = cfg.safety or {}
    local sys = cfg.system or {}
    local rawBase = chs.baseChannel or cfg.baseChannel
    local validBase = channel_sentinel.is_valid_base(rawBase) and rawBase or CRAFT_BASE_MIN
    local bootCh = chs.bootstrapChannel or cfg.bootstrapChannel or DEFAULT_BOOTSTRAP_CH
    local dId = sys.domainId or cfg.domainId or "AIRCRAFT_01"
    return {
        status = "INIT",
        domainId = dId,
        baseChannel = validBase,
        bootstrapChannel = bootCh,
        candidateBase = validBase,
        bandwidth = CRAFT_BANDWIDTH,
        gcsBootstrapTimeoutMs = safe.gcsBootstrapTimeoutMs or cfg.gcsBootstrapTimeoutMs or 1000,
        channelProbeWaitMs = safe.channelProbeWaitMs or cfg.channelProbeWaitMs or 200,
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
        requestedBandwidth = CRAFT_BANDWIDTH,
    }
end

function channel_sentinel.on_block_assign(state, payload, now_ms)
    local candidate = payload and (payload.baseChannel or payload.assignedBaseChannel)
    if candidate and channel_sentinel.is_valid_base(candidate) then
        state.candidateBase = candidate
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
        bandwidth = CRAFT_BANDWIDTH,
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
                    status = "CONFLICT_DETECTED",
                    occupiedBase = state.baseChannel,
                    existingDomain = state.domainId or "AMM",
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
    if not channel_sentinel.is_valid_base(new_base) then
        return nil, "INVALID_BASE_CHANNEL"
    end
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
            bandwidth = CRAFT_BANDWIDTH,
        },
    }
end

function channel_sentinel.on_rebind_ack(state, packet, now_ms)
    local payload = packet and packet.payload or {}
    if state and state.rebindTx and payload.transactionId == state.rebindTx.txId then
        local st = payload.status
        if st == "READY" or st == "PREPARED" or st == "ACKED" or not st then
            state.rebindTx.status = "ACKED"
            return true
        end
    end
    return false
end

function channel_sentinel.step_rebind_transaction(state, now_ms)
    if not state or not state.rebindTx then return nil, "NO_TRANSACTION" end
    local tx = state.rebindTx
    local now = now_ms or 0

    if tx.status == "ACKED" then
        state.baseChannel = tx.newBase
        state.candidateBase = tx.newBase
        state.rebindTx = nil
        return {
            type = "MSG_CHANNEL_REBIND",
            payload = {
                transactionId = tx.txId,
                action = "COMMIT",
                oldBaseChannel = tx.oldBase,
                newBaseChannel = tx.newBase,
                bandwidth = CRAFT_BANDWIDTH,
            },
        }, "COMMITTED"
    end

    if tx.status == "PREPARE" and (now - tx.startMs) > 500 then
        state.rebindTx = nil
        return {
            type = "MSG_CHANNEL_REBIND",
            payload = {
                transactionId = tx.txId,
                action = "ROLLBACK",
                oldBaseChannel = tx.oldBase,
                newBaseChannel = tx.newBase,
                bandwidth = CRAFT_BANDWIDTH,
            },
        }, "ROLLED_BACK"
    end

    return nil, tx.status
end

return channel_sentinel
