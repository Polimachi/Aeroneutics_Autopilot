-- Base_hangar+3 Actuator and Surface Discovery Client
local discovery_client = {}
local Client = {}
Client.__index = Client

function discovery_client.new(craftDomainId)
    local obj = {
        domainId = craftDomainId or "AIRCRAFT_01",
        actuatorQueue = {},
        actuatorMap = {},
        surfaces = {}
    }
    return setmetatable(obj, Client)
end

function Client:build_requests(startSeq)
    local seq = startSeq or 1
    local now = (os.epoch and os.epoch("utc")) or (os.time() * 1000)
    local reqAct = {
        ver = "1.9.5",
        domainId = self.domainId,
        seq = seq,
        type = "MSG_ACTUATOR_DISCOVER_REQ",
        time = now,
        payload = { targetGroup = "ALL" }
    }
    local reqSurf = {
        ver = "1.9.5",
        domainId = self.domainId,
        seq = seq + 1,
        type = "MSG_SURFACE_DISCOVER_REQ",
        time = now,
        payload = { targetGroup = "ALL" }
    }
    return { reqAct, reqSurf }
end

local function handle_actuator_ack(self, payload)
    local gid = payload.groupId
    if not gid or self.actuatorMap[gid] then return false end
    self.actuatorMap[gid] = payload
    table.insert(self.actuatorQueue, gid)
    return true
end

local function handle_surface_ack(self, payload)
    local sid = payload.surfaceId
    if not sid or self.surfaces[sid] then return false end
    self.surfaces[sid] = payload
    return true
end

function Client:process_ack(packet)
    if not packet or type(packet) ~= "table" then return false end
    local pType = packet.type
    local p = packet.payload or {}
    if pType == "MSG_ACTUATOR_DISCOVER_ACK" then
        return handle_actuator_ack(self, p)
    elseif pType == "MSG_SURFACE_DISCOVER_ACK" then
        return handle_surface_ack(self, p)
    end
    return false
end

function Client:get_actuator_queue()
    local res = {}
    for _, gid in ipairs(self.actuatorQueue) do table.insert(res, gid) end
    return res
end

function Client:get_discovered_surfaces()
    local res = {}
    for k, v in pairs(self.surfaces) do res[k] = v end
    return res
end

return discovery_client
