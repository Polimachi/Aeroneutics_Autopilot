-- src/3_planning/amm/modules/channel_sentinel.lua
local channel_sentinel = {}

channel_sentinel.CRAFT_BASE_MIN = 10000
channel_sentinel.CRAFT_BASE_MAX = 49960
channel_sentinel.CRAFT_BANDWIDTH = 40
channel_sentinel.DEFAULT_BOOTSTRAP_CH = 50000
channel_sentinel.DEFAULT_LISTEN_MS = 200
channel_sentinel.DEFAULT_JITTER_MAX_MS = 100
channel_sentinel.DEFAULT_INTER_ROUND_JITTER_MAX_MS = 50
channel_sentinel.DEFAULT_PROBE_RETRIES = 2
channel_sentinel.DEFAULT_MAX_REASSIGN_ATTEMPTS = 3
channel_sentinel.DEFAULT_GCS_BOOTSTRAP_TIMEOUT_MS = 2000
channel_sentinel.INTRUSION_ESCALATE_MS = 30000
channel_sentinel.DEFAULT_LEASE_PATH = "config/channel_lease.json"

local CRAFT_BASE_MIN = channel_sentinel.CRAFT_BASE_MIN
local CRAFT_BASE_MAX = channel_sentinel.CRAFT_BASE_MAX
local CRAFT_BANDWIDTH = channel_sentinel.CRAFT_BANDWIDTH
local DEFAULT_BOOTSTRAP_CH = channel_sentinel.DEFAULT_BOOTSTRAP_CH
local DEFAULT_LISTEN_MS = channel_sentinel.DEFAULT_LISTEN_MS
local DEFAULT_JITTER_MAX_MS = channel_sentinel.DEFAULT_JITTER_MAX_MS
local DEFAULT_INTER_ROUND_JITTER_MAX_MS = channel_sentinel.DEFAULT_INTER_ROUND_JITTER_MAX_MS
local DEFAULT_PROBE_RETRIES = channel_sentinel.DEFAULT_PROBE_RETRIES
local DEFAULT_MAX_REASSIGN_ATTEMPTS = channel_sentinel.DEFAULT_MAX_REASSIGN_ATTEMPTS
local DEFAULT_GCS_BOOTSTRAP_TIMEOUT_MS = channel_sentinel.DEFAULT_GCS_BOOTSTRAP_TIMEOUT_MS
local INTRUSION_ESCALATE_MS = channel_sentinel.INTRUSION_ESCALATE_MS
local DEFAULT_LEASE_PATH = channel_sentinel.DEFAULT_LEASE_PATH

local function resolve_now_ms(now_ms)
    if type(now_ms) == "number" then
        return now_ms
    end
    return (os and os.epoch and os.epoch("utc")) or (os and os.time and math.floor(os.time() * 1000)) or 0
end

local function hash_uuid_seed(hw_uuid, now_ms)
    local h = 2166136261
    local s = tostring(hw_uuid or "AMM")
    for i = 1, #s do
        h = bit32.bxor(h, string.byte(s, i))
        h = (h * 16777619) % 2147483648
    end
    local t = math.floor(tonumber(now_ms) or 0) % 2147483648
    return bit32.bxor(h, t) % 2147483648
end

local function sample_jitter(state, rng, max_ms)
    local cap = math.floor(tonumber(max_ms) or 0)
    if cap <= 0 then return 0 end
    if type(rng) == "function" then
        local v = math.floor(tonumber(rng(0, cap)) or 0)
        if v < 0 then return 0 end
        if v > cap then return cap end
        return v
    end
    state.rngSeed = ((state.rngSeed or 1) * 1103515245 + 12345) % 2147483648
    return state.rngSeed % (cap + 1)
end

local function load_lease_cache(lease_path, hw_uuid)
    if not lease_path or not fs or not fs.exists or not fs.open then return nil end
    if not fs.exists(lease_path) then return nil end
    local f = fs.open(lease_path, "r")
    if not f then return nil end
    local raw = f.readAll()
    f.close()
    if type(raw) ~= "string" or raw == "" or not textutils or not textutils.unserializeJSON then
        return nil
    end
    local parsed = textutils.unserializeJSON(raw)
    if type(parsed) ~= "table" then return nil end
    if parsed.hardwareUuid ~= nil and hw_uuid ~= nil and parsed.hardwareUuid ~= hw_uuid then
        return nil
    end
    local base = parsed.baseChannel or parsed.cachedBase
    if channel_sentinel.is_valid_base(base) then
        return base
    end
    return nil
end

function channel_sentinel.save_lease_cache(state, lease_path)
    if not state then return false end
    local path = lease_path or state.leasePath or DEFAULT_LEASE_PATH
    if not fs or not fs.open or not textutils or not textutils.serializeJSON then
        return false
    end
    if fs.getDir and fs.makeDir and fs.exists then
        local dir = fs.getDir(path)
        if dir and dir ~= "" and not fs.exists(dir) then
            fs.makeDir(dir)
        end
    end
    local payload = textutils.serializeJSON({
        hardwareUuid = state.hardwareUuid,
        domainId = state.domainId,
        baseChannel = state.baseChannel,
        cachedBase = state.baseChannel,
        updatedAtMs = state.lastAcquiredMs or 0,
    })
    if fs.move and fs.delete and fs.exists then
        local tmp = path .. ".tmp"
        local f = fs.open(tmp, "w")
        if not f then return false end
        f.write(payload)
        f.close()
        if fs.exists(path) then fs.delete(path) end
        fs.move(tmp, path)
        return true
    end
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(payload)
    f.close()
    return true
end

function channel_sentinel.compute_base(n)
    if not n or n < 1 then return nil end
    local base = CRAFT_BASE_MIN + (n - 1) * CRAFT_BANDWIDTH
    if base > CRAFT_BASE_MAX then return nil end
    return base
end

function channel_sentinel.is_valid_base(baseCh)
    if type(baseCh) ~= "number" or baseCh ~= baseCh or baseCh == math.huge or baseCh == -math.huge then
        return false
    end
    if math.floor(baseCh) ~= baseCh then return false end
    if baseCh < CRAFT_BASE_MIN or baseCh > CRAFT_BASE_MAX then return false end
    if (baseCh - CRAFT_BASE_MIN) % CRAFT_BANDWIDTH ~= 0 then return false end
    return true
end

function channel_sentinel.is_in_own_block(state, channel)
    if not state or type(channel) ~= "number" or type(state.baseChannel) ~= "number" then
        return false
    end
    return channel >= state.baseChannel and channel <= (state.baseChannel + CRAFT_BANDWIDTH - 1)
end

function channel_sentinel.init(config, now_ms, lease_path)
    local cfg = config or {}
    local chs = cfg.channels or {}
    local safe = cfg.safety or {}
    local sys = cfg.system or {}
    local rawBase = chs.baseChannel or cfg.baseChannel
    local validBase = channel_sentinel.is_valid_base(rawBase) and rawBase or CRAFT_BASE_MIN
    local bootCh = chs.bootstrapChannel or cfg.bootstrapChannel or DEFAULT_BOOTSTRAP_CH
    local dId = sys.domainId or cfg.domainId or "AIRCRAFT_01"
    local hwUuid = sys.hardwareUuid or cfg.hardwareUuid or ("AMM-NODE-" .. tostring(dId))
    local lPath = lease_path or cfg.leasePath or DEFAULT_LEASE_PATH
    local cached = load_lease_cache(lPath, hwUuid)
    if cached then
        validBase = cached
    end
    local jitterMax = safe.probeJitterMaxMs or cfg.probeJitterMaxMs or DEFAULT_JITTER_MAX_MS
    local interJitterMax = safe.probeInterRoundJitterMaxMs or cfg.probeInterRoundJitterMaxMs
        or (jitterMax == 0 and 0 or DEFAULT_INTER_ROUND_JITTER_MAX_MS)
    return {
        status = cached and "BOOT_VERIFY" or "INIT",
        domainId = dId,
        hardwareUuid = hwUuid,
        baseChannel = validBase,
        cachedBase = cached,
        leasePath = lPath,
        bootstrapChannel = bootCh,
        candidateBase = validBase,
        bandwidth = CRAFT_BANDWIDTH,
        gcsBootstrapTimeoutMs = safe.gcsBootstrapTimeoutMs or cfg.gcsBootstrapTimeoutMs or DEFAULT_GCS_BOOTSTRAP_TIMEOUT_MS,
        channelProbeWaitMs = safe.channelProbeWaitMs or cfg.channelProbeWaitMs or DEFAULT_LISTEN_MS,
        probeJitterMaxMs = jitterMax,
        probeInterRoundJitterMaxMs = interJitterMax,
        probeMaxRounds = safe.probeRetryCount or cfg.probeRetryCount or DEFAULT_PROBE_RETRIES,
        maxReassignAttempts = safe.maxReassignAttempts or cfg.maxReassignAttempts or DEFAULT_MAX_REASSIGN_ATTEMPTS,
        intrusionAlertWindowMs = safe.intrusionAlertWindowMs or cfg.intrusionAlertWindowMs or INTRUSION_ESCALATE_MS,
        rngSeed = hash_uuid_seed(hwUuid, resolve_now_ms(now_ms)),
        bootstrapStartMs = 0,
        gcsWaitStartedAtMs = 0,
        jitterStartMs = 0,
        jitterDelayMs = 0,
        probeStartMs = 0,
        probeRound = 0,
        reassignAttempts = 0,
        conflictBase = nil,
        offlinePending = false,
        offlineWarning = nil,
        locked = false,
        conflictReason = nil,
        intrusionCount = 0,
        intrusionFirstMs = nil,
        intrusionLastMs = nil,
        intrusionFailsafeTriggered = false,
        lastIntruderDomainId = nil,
        lastIntruderChannel = nil,
        lastAcquiredMs = nil,
    }
end

function channel_sentinel.start_bootstrap(state, now_ms)
    local t_now = resolve_now_ms(now_ms)
    state.bootstrapStartMs = t_now
    state.gcsWaitStartedAtMs = t_now
    state.status = "GCS_WAIT"
    state.offlinePending = false
    state.offlineWarning = nil
    return {
        type = "MSG_BLOCK_REQUEST",
        payload = {
            domainId = state.domainId,
            hardwareUuid = state.hardwareUuid,
            requestedBandwidth = CRAFT_BANDWIDTH,
            preferredBase = state.cachedBase,
            conflictBase = state.conflictBase,
        },
    }
end

function channel_sentinel.on_block_assign(state, payload, now_ms, rng)
    if type(payload) == "table" and (payload.status == "DENIED" or payload.status == "FAILED") then
        state.locked = true
        state.status = "LOCKED_CONFLICT"
        state.conflictReason = payload.reason or "GCS_BLOCK_DENIED"
        return
    end
    local candidate = payload and payload.baseChannel
    if candidate and channel_sentinel.is_valid_base(candidate) then
        state.candidateBase = candidate
    else
        state.candidateBase = state.baseChannel
    end
    state.jitterDelayMs = sample_jitter(state, rng, state.probeJitterMaxMs)
    state.jitterStartMs = resolve_now_ms(now_ms)
    state.probeRound = 0
    state.offlinePending = false
    state.locked = false
    state.conflictReason = nil
    state.conflictBase = nil
    state.status = "JITTER_WAIT"
end

function channel_sentinel.probe_channel(state, candidate_base, now_ms)
    local c = candidate_base or state.candidateBase or state.baseChannel
    state.candidateBase = c
    state.probeStartMs = now_ms or 0
    state.probeRound = (state.probeRound or 0) + 1
    state.status = "PROBING"
    return {
        type = "MSG_CHANNEL_PROBE",
        payload = {
            hardwareUuid = state.hardwareUuid,
            candidateBase = c,
            bandwidth = CRAFT_BANDWIDTH,
        },
    }
end

function channel_sentinel.on_probe_ack(state, packet)
    local payload = packet and packet.payload
    if type(payload) ~= "table" then return end
    if payload.responderUuid ~= nil and payload.responderUuid == state.hardwareUuid then
        return
    end
    if payload.conflict == true or payload.status == "CONFLICT_DETECTED" then
        state.reassignAttempts = (state.reassignAttempts or 0) + 1
        state.conflictBase = payload.occupiedBase or state.candidateBase
        state.conflictReason = "RF_CHANNEL_CONFLICT"
        if state.reassignAttempts >= (state.maxReassignAttempts or DEFAULT_MAX_REASSIGN_ATTEMPTS) then
            state.locked = true
            state.status = "LOCKED_CONFLICT"
        else
            state.locked = false
            state.status = "REASSIGN_REQUEST"
        end
    end
end

local function finalize_acquired(state, now_ms)
    state.baseChannel = state.candidateBase
    state.cachedBase = state.candidateBase
    state.lastAcquiredMs = now_ms
    state.locked = false
    state.reassignAttempts = 0
    state.conflictBase = nil
    if state.offlinePending then
        state.status = "ACQUIRED_OFFLINE"
        state.offlineWarning = "NO_GCS_LEASE"
    else
        state.status = "ACQUIRED"
        state.offlineWarning = nil
    end
    state.offlinePending = false
    channel_sentinel.save_lease_cache(state)
    return state.status, nil
end

local function step_probing(state, now_ms, inbound, rng)
    local p = inbound and inbound.probe
    if p and p.payload and (p.payload.conflict == true or p.payload.status == "CONFLICT_DETECTED") then
        channel_sentinel.on_probe_ack(state, p)
        return state.status, nil
    end
    if (now_ms - state.probeStartMs) >= state.channelProbeWaitMs then
        if (state.probeRound or 1) < (state.probeMaxRounds or DEFAULT_PROBE_RETRIES) then
            local inter_jitter = sample_jitter(state, rng, state.probeInterRoundJitterMaxMs)
            if inter_jitter > 0 then
                state.jitterDelayMs = inter_jitter
                state.jitterStartMs = now_ms
                state.status = "JITTER_WAIT"
                return state.status, nil
            end
            local next_probe = channel_sentinel.probe_channel(state, state.candidateBase, now_ms)
            return state.status, next_probe
        end
        return finalize_acquired(state, now_ms)
    end
    return state.status, nil
end

function channel_sentinel.negotiate_and_probe(state, now_ms, inbound_packets, rng)
    if not state then return "NO_STATE", nil end
    local now = resolve_now_ms(now_ms)
    if state.status == "INIT" or state.status == "BOOT_VERIFY" or state.status == "REASSIGN_REQUEST" then
        local boot_payload = channel_sentinel.start_bootstrap(state, now)
        return state.status, boot_payload
    elseif state.status == "GCS_WAIT" then
        local wait_start = state.gcsWaitStartedAtMs or state.bootstrapStartMs or 0
        if (now - wait_start) >= state.gcsBootstrapTimeoutMs then
            if state.cachedBase and channel_sentinel.is_valid_base(state.cachedBase) then
                state.candidateBase = state.cachedBase
                state.offlinePending = true
                state.probeRound = 0
                state.jitterDelayMs = sample_jitter(state, rng, state.probeJitterMaxMs)
                state.jitterStartMs = now
                state.status = "JITTER_WAIT"
                if state.jitterDelayMs <= 0 then
                    local probe_payload = channel_sentinel.probe_channel(state, state.candidateBase, now)
                    return state.status, probe_payload
                end
                return state.status, nil
            end
            state.locked = true
            state.status = "LOCKED_NO_GCS"
            state.conflictReason = "NO_GCS_LEASE"
            return state.status, nil
        end
        return state.status, nil
    elseif state.status == "JITTER_WAIT" then
        if (now - (state.jitterStartMs or 0)) >= (state.jitterDelayMs or 0) then
            local probe_payload = channel_sentinel.probe_channel(state, state.candidateBase, now)
            return state.status, probe_payload
        end
        return state.status, nil
    elseif state.status == "PROBING" then
        return step_probing(state, now, inbound_packets, rng)
    end
    return state.status, nil
end

function channel_sentinel.handle_incoming_probe(state, packet)
    if not state or not packet or type(packet.payload) ~= "table" then
        return nil
    end
    if packet.payload.hardwareUuid ~= nil and packet.payload.hardwareUuid == state.hardwareUuid then
        return nil
    end
    local target = packet.payload.candidateBase
    if type(target) ~= "number" then return nil end
    local is_active = (state.status == "ACQUIRED" or state.status == "ACQUIRED_OFFLINE")
    local is_boot_bound = (state.status == "BOOT_VERIFY" or state.status == "DISARMED"
        or state.status == "PROBING" or state.status == "JITTER_WAIT")
    local matches = (is_active and target == state.baseChannel)
        or (is_boot_bound and (target == state.baseChannel or target == state.candidateBase))
    if matches then
        return {
            type = "MSG_CHANNEL_PROBE_ACK",
            payload = {
                conflict = true,
                status = "CONFLICT_DETECTED",
                occupiedBase = target,
                existingDomain = state.domainId or "AMM",
                responderUuid = state.hardwareUuid,
                responderStatus = state.status,
            },
        }
    end
    return nil
end

function channel_sentinel.record_intrusion_sample(state, channel, domain_id, now_ms)
    if not channel_sentinel.is_in_own_block(state, channel) then
        return false, nil
    end
    if type(domain_id) ~= "string" or domain_id == "" or domain_id == state.domainId then
        return false, nil
    end
    local now = now_ms or 0
    state.intrusionCount = (state.intrusionCount or 0) + 1
    if not state.intrusionFirstMs then
        state.intrusionFirstMs = now
    end
    state.intrusionLastMs = now
    state.lastIntruderDomainId = domain_id
    state.lastIntruderChannel = channel
    if (now - state.intrusionFirstMs) >= (state.intrusionAlertWindowMs or INTRUSION_ESCALATE_MS) then
        state.intrusionFailsafeTriggered = true
        return true, "FAILSAFE_ESCALATE"
    end
    return true, "INTRUSION_DETECTED"
end

function channel_sentinel.step_intrusion_watchdog(state, now_ms)
    if not state or not state.intrusionFirstMs or (state.intrusionCount or 0) == 0 then
        return "CLEAR"
    end
    local now = now_ms or 0
    if state.intrusionFailsafeTriggered
        or (now - state.intrusionFirstMs) >= (state.intrusionAlertWindowMs or INTRUSION_ESCALATE_MS) then
        state.intrusionFailsafeTriggered = true
        return "FAILSAFE_ESCALATE"
    end
    return "INTRUSION_DETECTED"
end

function channel_sentinel.is_locked(state)
    return state ~= nil and (
        state.locked == true
        or state.status == "LOCKED_CONFLICT"
        or state.status == "LOCKED_NO_GCS"
        or state.status == "ARMING_LOCKED"
    )
end

function channel_sentinel.is_acquired(state)
    return state ~= nil
        and (state.status == "ACQUIRED" or state.status == "ACQUIRED_OFFLINE")
        and not channel_sentinel.is_locked(state)
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
        if st == "READY" then
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
        state.cachedBase = tx.newBase
        state.lastAcquiredMs = now
        state.rebindTx = nil
        channel_sentinel.save_lease_cache(state)
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
