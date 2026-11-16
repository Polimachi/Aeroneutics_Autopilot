-- src/0_infra/gcs/modules/channel_manager.lua
local channel_manager = {}

local FIXED_BW = 40
channel_manager.FIXED_BW = FIXED_BW
channel_manager.DEFAULT_BASE_MIN = 10000
channel_manager.DEFAULT_BASE_MAX = 49960
channel_manager.DEFAULT_BANDWIDTH = FIXED_BW
channel_manager.DEFAULT_MAX_BLOCKS = 1000
channel_manager.MAX_CRAFT_CHAN = 49999

function channel_manager.compute_base(n)
    if not n or type(n) ~= "number" or n < 1 or n > channel_manager.DEFAULT_MAX_BLOCKS then
        return nil
    end
    local base = channel_manager.DEFAULT_BASE_MIN + (n - 1) * channel_manager.DEFAULT_BANDWIDTH
    if base > channel_manager.DEFAULT_BASE_MAX then
        return nil
    end
    return base
end

function channel_manager.is_valid_block_range(base_ch)
    if type(base_ch) ~= "number" then return false end
    if base_ch < channel_manager.DEFAULT_BASE_MIN
        or base_ch > channel_manager.DEFAULT_BASE_MAX
        or (base_ch + FIXED_BW - 1) > channel_manager.MAX_CRAFT_CHAN then
        return false
    end
    return ((base_ch - channel_manager.DEFAULT_BASE_MIN) % FIXED_BW) == 0
end

function channel_manager.is_valid_base(base_ch)
    return channel_manager.is_valid_block_range(base_ch)
end

function channel_manager.ranges_overlap(baseA, bwA, baseB, bwB)
    if type(baseA) ~= "number" or type(baseB) ~= "number" then
        return false
    end
    local a_bw = bwA or FIXED_BW
    local b_bw = bwB or FIXED_BW
    return not (baseA + a_bw - 1 < baseB or baseB + b_bw - 1 < baseA)
end

function channel_manager.init(config, registry_path)
    local cfg = config or {}
    local chs = cfg.channels or {}
    local path = registry_path or "config/channel_registry.json"
    local state = {
        baseChannelMin = chs.baseChannelMin or channel_manager.DEFAULT_BASE_MIN,
        baseChannelMax = chs.baseChannelMax or channel_manager.DEFAULT_BASE_MAX,
        bandwidth = FIXED_BW,
        maxCraftBlocks = chs.maxCraftBlocks or channel_manager.DEFAULT_MAX_BLOCKS,
        registryPath = path,
        allocations = {},
    }
    channel_manager.load_registry(state)
    return state
end

function channel_manager.load_registry(state)
    if not state or not state.registryPath then return end
    if not fs.exists(state.registryPath) then return end
    local f = fs.open(state.registryPath, "r")
    if not f then return end
    local raw = f.readAll()
    f.close()
    local data = textutils.unserializeJSON(raw)
    if data and type(data.allocations) == "table" then
        for d_id, alloc in pairs(data.allocations) do
            if type(alloc) == "table" then
                alloc.domainId = alloc.domainId or d_id
                alloc.bandwidth = alloc.bandwidth or FIXED_BW
                alloc.leaseState = "OFFLINE_RESERVED"
                state.allocations[d_id] = alloc
            end
        end
    end
end

function channel_manager.save_registry(state)
    if not state or not state.registryPath then return false end
    local updated_at = (os and os.date and os.date("!%Y-%m-%d")) or tostring(os and os.epoch and os.epoch("utc") or 0)
    local data = {
        version = "1.0.0",
        updatedAt = updated_at,
        allocations = state.allocations,
    }
    local tmp_path = state.registryPath .. ".tmp"
    local f = fs.open(tmp_path, "w")
    if not f then return false end
    f.write(textutils.serializeJSON(data))
    f.close()
    if fs.exists(state.registryPath) then
        fs.delete(state.registryPath)
    end
    fs.move(tmp_path, state.registryPath)
    return true
end

function channel_manager.get_allocation(state, domain_id)
    if not state or not domain_id then return nil end
    return state.allocations[domain_id]
end

local function has_collision(state, candidate_base, ignore_key)
    for key, alloc in pairs(state.allocations) do
        if key ~= ignore_key and alloc.baseChannel then
            if channel_manager.ranges_overlap(candidate_base, FIXED_BW, alloc.baseChannel, alloc.bandwidth or FIXED_BW) then
                return true
            end
        end
    end
    return false
end

local function find_lowest_free_block(state, conflict_base, ignore_key)
    local limit = math.min(state.maxCraftBlocks or channel_manager.DEFAULT_MAX_BLOCKS, channel_manager.DEFAULT_MAX_BLOCKS)
    for n = 1, limit do
        local base = channel_manager.compute_base(n)
        if base and base ~= conflict_base and channel_manager.is_valid_block_range(base) then
            if not has_collision(state, base, ignore_key) then
                return n, base
            end
        end
    end
    return nil, nil
end

local function build_assign_response(status, block_id, base, lease_state, reassigned_from, reason)
    local res = {
        status = status,
        blockId = block_id,
        baseChannel = base,
        bandwidth = FIXED_BW,
        leaseState = lease_state,
        reassignedFrom = reassigned_from,
        reason = reason,
    }
    if base then
        res.channelRange = { start = base, ["end"] = base + FIXED_BW - 1 }
    end
    return res
end

local function persist_allocation(state, alloc_key, domain_id, block_id, base, hardware_uuid, ts, assigned_at)
    state.allocations[alloc_key] = {
        domainId = domain_id,
        blockId = block_id,
        baseChannel = base,
        hardwareUuid = hardware_uuid or "UNKNOWN",
        bandwidth = FIXED_BW,
        leaseState = "ACTIVE_LEASE",
        lastSeenMs = ts,
        assignedAt = assigned_at or ts,
    }
    channel_manager.save_registry(state)
end

local function find_matching_allocation(state, domain_id, hardware_uuid)
    local by_domain = state.allocations[domain_id]
    if by_domain and (not hardware_uuid or by_domain.hardwareUuid == hardware_uuid) then
        return domain_id, by_domain
    end
    if hardware_uuid then
        for key, alloc in pairs(state.allocations) do
            if alloc.hardwareUuid == hardware_uuid then
                if not by_domain then
                    state.allocations[key] = nil
                    state.allocations[domain_id] = alloc
                    return domain_id, alloc
                end
                return key, alloc
            end
        end
    end
    return nil, nil
end

function channel_manager.allocate_block(state, domain_id, hardware_uuid, requested_bw, preferred_base, conflict_base, now_ms)
    if not state or not domain_id then
        return { status = "DENIED", reason = "INVALID_ARGUMENTS", bandwidth = FIXED_BW }
    end
    if requested_bw ~= FIXED_BW then
        return { status = "DENIED", reason = "INVALID_BANDWIDTH", bandwidth = FIXED_BW }
    end

    local ts = now_ms or (os and os.epoch and os.epoch("utc")) or (os and os.time and math.floor(os.time() * 1000)) or 0
    local existing_key, existing_alloc = find_matching_allocation(state, domain_id, hardware_uuid)

    if existing_alloc then
        local can_keep = conflict_base == nil
            and (preferred_base == nil or preferred_base == existing_alloc.baseChannel)
            and not has_collision(state, existing_alloc.baseChannel, existing_key)
        if can_keep then
            persist_allocation(
                state, existing_key, domain_id,
                existing_alloc.blockId, existing_alloc.baseChannel,
                existing_alloc.hardwareUuid, ts, existing_alloc.assignedAt
            )
            return build_assign_response("ASSIGNED", existing_alloc.blockId, existing_alloc.baseChannel, "ACTIVE_LEASE")
        end

        if conflict_base == nil and preferred_base ~= nil and channel_manager.is_valid_block_range(preferred_base)
            and not has_collision(state, preferred_base, existing_key) then
            local pref_n = math.floor((preferred_base - channel_manager.DEFAULT_BASE_MIN) / FIXED_BW) + 1
            persist_allocation(state, existing_key, domain_id, pref_n, preferred_base, existing_alloc.hardwareUuid, ts, existing_alloc.assignedAt)
            return build_assign_response("ASSIGNED", pref_n, preferred_base, "ACTIVE_LEASE")
        end

        local avoid_base = conflict_base or preferred_base or existing_alloc.baseChannel
        local n, base = find_lowest_free_block(state, avoid_base, existing_key)
        if not n then
            return { status = "FAILED", reason = "NO_FREE_BLOCK", bandwidth = FIXED_BW }
        end
        persist_allocation(state, existing_key, domain_id, n, base, existing_alloc.hardwareUuid, ts, existing_alloc.assignedAt)
        return build_assign_response("REASSIGNED", n, base, "ACTIVE_LEASE", avoid_base)
    end

    local alloc_key = state.allocations[domain_id] == nil and domain_id or (domain_id .. ":" .. tostring(hardware_uuid or "UNKNOWN"))

    if preferred_base ~= nil then
        if conflict_base ~= preferred_base and channel_manager.is_valid_block_range(preferred_base)
            and not has_collision(state, preferred_base, nil) then
            local pref_n = math.floor((preferred_base - channel_manager.DEFAULT_BASE_MIN) / FIXED_BW) + 1
            persist_allocation(state, alloc_key, domain_id, pref_n, preferred_base, hardware_uuid, ts, ts)
            return build_assign_response("ASSIGNED", pref_n, preferred_base, "ACTIVE_LEASE")
        end

        local avoid_base = conflict_base or preferred_base
        local n, base = find_lowest_free_block(state, avoid_base, nil)
        if not n then
            return { status = "FAILED", reason = "NO_FREE_BLOCK", bandwidth = FIXED_BW }
        end
        persist_allocation(state, alloc_key, domain_id, n, base, hardware_uuid, ts, ts)
        return build_assign_response("REASSIGNED", n, base, "ACTIVE_LEASE", avoid_base)
    end

    local n, base = find_lowest_free_block(state, conflict_base, nil)
    if not n then
        return { status = "FAILED", reason = "NO_FREE_BLOCK", bandwidth = FIXED_BW }
    end
    persist_allocation(state, alloc_key, domain_id, n, base, hardware_uuid, ts, ts)
    if conflict_base ~= nil then
        return build_assign_response("REASSIGNED", n, base, "ACTIVE_LEASE", conflict_base)
    end
    return build_assign_response("ASSIGNED", n, base, "ACTIVE_LEASE")
end

function channel_manager.release_block(state, domain_id)
    if not state or not domain_id or not state.allocations[domain_id] then
        return false
    end
    state.allocations[domain_id] = nil
    channel_manager.save_registry(state)
    return true
end

function channel_manager.list_allocations(state)
    local list = {}
    if not state or not state.allocations then return list end
    for key, alloc in pairs(state.allocations) do
        table.insert(list, {
            domainId = alloc.domainId or key,
            blockId = alloc.blockId,
            baseChannel = alloc.baseChannel,
            hardwareUuid = alloc.hardwareUuid,
            bandwidth = alloc.bandwidth or FIXED_BW,
            leaseState = alloc.leaseState,
            lastSeenMs = alloc.lastSeenMs,
            assignedAt = alloc.assignedAt,
        })
    end
    table.sort(list, function(a, b) return a.blockId < b.blockId end)
    return list
end

return channel_manager
