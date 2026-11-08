-- src/0_infra/gcs/modules/channel_manager.lua
local channel_manager = {}

channel_manager.DEFAULT_BASE_MIN = 10000
channel_manager.DEFAULT_BASE_MAX = 49960
channel_manager.DEFAULT_BANDWIDTH = 40
channel_manager.DEFAULT_MAX_BLOCKS = 1000

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

function channel_manager.is_valid_base(base_ch)
    if type(base_ch) ~= "number" then return false end
    if base_ch < channel_manager.DEFAULT_BASE_MIN or base_ch > channel_manager.DEFAULT_BASE_MAX then
        return false
    end
    return ((base_ch - channel_manager.DEFAULT_BASE_MIN) % channel_manager.DEFAULT_BANDWIDTH) == 0
end

function channel_manager.init(config, registry_path)
    local cfg = config or {}
    local chs = cfg.channels or {}
    local path = registry_path or "config/channel_registry.json"
    local state = {
        baseChannelMin = chs.baseChannelMin or channel_manager.DEFAULT_BASE_MIN,
        baseChannelMax = chs.baseChannelMax or channel_manager.DEFAULT_BASE_MAX,
        bandwidth = chs.bandwidth or channel_manager.DEFAULT_BANDWIDTH,
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
    if data and data.allocations then
        state.allocations = data.allocations
    end
end

function channel_manager.save_registry(state)
    if not state or not state.registryPath then return false end
    local data = {
        version = "1.0.0",
        updatedAt = "2026-11-08",
        allocations = state.allocations,
    }
    local f = fs.open(state.registryPath, "w")
    if not f then return false end
    f.write(textutils.serializeJSON(data))
    f.close()
    return true
end

function channel_manager.get_allocation(state, domain_id)
    if not state or not domain_id then return nil end
    return state.allocations[domain_id]
end

function channel_manager.allocate_block(state, domain_id, hardware_uuid, requested_bw)
    if not state or not domain_id then
        return { status = "DENIED", reason = "INVALID_ARGUMENTS" }
    end

    -- 1. Check existing allocation by domain_id
    if state.allocations[domain_id] then
        local alloc = state.allocations[domain_id]
        return {
            status = "ASSIGNED",
            blockId = alloc.blockId,
            baseChannel = alloc.baseChannel,
            bandwidth = state.bandwidth,
            channelRange = { start = alloc.baseChannel, ["end"] = alloc.baseChannel + state.bandwidth - 1 }
        }
    end

    -- 2. Check existing allocation by hardware_uuid if provided
    if hardware_uuid then
        for d_id, alloc in pairs(state.allocations) do
            if alloc.hardwareUuid == hardware_uuid then
                state.allocations[domain_id] = alloc
                if d_id ~= domain_id then
                    state.allocations[d_id] = nil
                end
                channel_manager.save_registry(state)
                return {
                    status = "ASSIGNED",
                    blockId = alloc.blockId,
                    baseChannel = alloc.baseChannel,
                    bandwidth = state.bandwidth,
                    channelRange = { start = alloc.baseChannel, ["end"] = alloc.baseChannel + state.bandwidth - 1 }
                }
            end
        end
    end

    -- 3. Find lowest unused blockId
    local used_blocks = {}
    for _, alloc in pairs(state.allocations) do
        if alloc.blockId then
            used_blocks[alloc.blockId] = true
        end
    end

    local target_block = nil
    for n = 1, state.maxCraftBlocks do
        if not used_blocks[n] then
            target_block = n
            break
        end
    end

    if not target_block then
        return { status = "DENIED", reason = "EXHAUSTED" }
    end

    local base = channel_manager.compute_base(target_block)
    if not base then
        return { status = "DENIED", reason = "EXHAUSTED" }
    end

    state.allocations[domain_id] = {
        blockId = target_block,
        baseChannel = base,
        hardwareUuid = hardware_uuid or "UNKNOWN",
        bandwidth = state.bandwidth,
        assignedAt = os.epoch and os.epoch("utc") or 0,
    }
    channel_manager.save_registry(state)

    return {
        status = "ASSIGNED",
        blockId = target_block,
        baseChannel = base,
        bandwidth = state.bandwidth,
        channelRange = { start = base, ["end"] = base + state.bandwidth - 1 }
    }
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
    for domain_id, alloc in pairs(state.allocations) do
        table.insert(list, {
            domainId = domain_id,
            blockId = alloc.blockId,
            baseChannel = alloc.baseChannel,
            hardwareUuid = alloc.hardwareUuid,
            assignedAt = alloc.assignedAt,
        })
    end
    table.sort(list, function(a, b) return a.blockId < b.blockId end)
    return list
end

return channel_manager
