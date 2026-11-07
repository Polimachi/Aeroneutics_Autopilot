-- Configuration normalizer and node registry resolver for CC:Tweaked GPS
local config_store = {}

local DEFAULT_CHANNELS = {
    ping = 60001,
    service = 60002,
    nodeIn = 60003,
    mgmt = 60004,
}

function config_store.normalizeNodeConfig(rawTable, fallbackCompId)
    local raw = type(rawTable) == "table" and rawTable or {}
    local pos = type(raw.position) == "table" and raw.position or {}
    local ch = type(raw.channels) == "table" and raw.channels or {}
    local isComplete = (raw.nodeId ~= nil and raw.position ~= nil
        and type(pos.x) == "number" and type(pos.y) == "number" and type(pos.z) == "number")
    local cfg = {
        version = tostring(raw.version or "1.9.5"),
        nodeId = raw.nodeId and tostring(raw.nodeId) or nil,
        computerId = tonumber(raw.computerId) or fallbackCompId or -1,
        position = {
            x = tonumber(pos.x) or 0,
            y = tonumber(pos.y) or 0,
            z = tonumber(pos.z) or 0,
        },
        channels = {
            ping = tonumber(ch.ping) or DEFAULT_CHANNELS.ping,
            service = tonumber(ch.service) or DEFAULT_CHANNELS.service,
            nodeIn = tonumber(ch.nodeIn) or DEFAULT_CHANNELS.nodeIn,
            mgmt = tonumber(ch.mgmt) or DEFAULT_CHANNELS.mgmt,
        },
        modemSide = tostring(raw.modemSide or "top"),
    }
    return cfg, isComplete
end

function config_store.parseNodeCliArgs(args, compId)
    if type(args) ~= "table" or #args < 4 then return nil, "INVALID_ARGS" end
    local x = tonumber(args[2])
    local y = tonumber(args[3])
    local z = tonumber(args[4])
    if not x or not y or not z then return nil, "INVALID_COORDINATES" end
    return {
        version = "1.9.5",
        nodeId = tostring(args[1]),
        computerId = tonumber(compId) or -1,
        position = { x = x, y = y, z = z },
        channels = {
            ping = DEFAULT_CHANNELS.ping,
            service = DEFAULT_CHANNELS.service,
            nodeIn = DEFAULT_CHANNELS.nodeIn,
            mgmt = DEFAULT_CHANNELS.mgmt,
        },
        modemSide = "top",
    }
end

function config_store.normalizeServerRegistry(rawTable)
    local raw = type(rawTable) == "table" and rawTable or {}
    local out = {
        version = tostring(raw.version or "1.9.5"),
        updatedAt = tonumber(raw.updatedAt) or (os.epoch and os.epoch("utc") or 0),
        nodes = {},
    }
    if type(raw.nodes) == "table" then
        for k, v in pairs(raw.nodes) do
            if type(v) == "table" and v.nodeId then
                out.nodes[tostring(k)] = v
            end
        end
    end
    return out
end

function config_store.resolveNodeReport(registry, reportPayload)
    if type(reportPayload) ~= "table" then return false, nil, "INVALID_REPORT" end
    local nodeId = tostring(reportPayload.nodeId or "")
    local nodes = registry and registry.nodes or {}
    local count = 0
    for _ in pairs(nodes) do count = count + 1 end

    if count == 0 then
        local p = reportPayload.nodePos or {}
        return true, {
            id = nodeId,
            x = tonumber(p.x) or 0,
            y = tonumber(p.y) or 0,
            z = tonumber(p.z) or 0,
            distance = tonumber(reportPayload.measuredDistance) or 0,
        }
    end

    local regNode = nodes[nodeId]
    if not regNode then return false, nil, "NODE_UNREGISTERED" end
    if regNode.status ~= "ONLINE" then return false, nil, "NODE_OFFLINE" end
    local pos = regNode.position or {}
    return true, {
        id = nodeId,
        x = tonumber(pos.x) or 0,
        y = tonumber(pos.y) or 0,
        z = tonumber(pos.z) or 0,
        distance = tonumber(reportPayload.measuredDistance) or 0,
    }
end

function config_store.computeSwarmBBox(registry, fallbackReports)
    local minX, maxX, minZ, maxZ = nil, nil, nil, nil
    local function expand(x, z)
        if type(x) == "number" and type(z) == "number" then
            if not minX or x < minX then minX = x end
            if not maxX or x > maxX then maxX = x end
            if not minZ or z < minZ then minZ = z end
            if not maxZ or z > maxZ then maxZ = z end
        end
    end

    if registry and type(registry.nodes) == "table" then
        for _, n in pairs(registry.nodes) do
            if n.status == "ONLINE" and n.position then
                expand(n.position.x, n.position.z)
            end
        end
    end

    if not minX and fallbackReports then
        for _, r in ipairs(fallbackReports) do
            expand(r.x, r.z)
        end
    end

    if not minX then
        return { minX = -1000, maxX = 1000, minZ = -1000, maxZ = 1000 }
    end
    return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

return config_store
