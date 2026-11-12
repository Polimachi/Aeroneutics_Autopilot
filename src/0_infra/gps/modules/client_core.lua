-- Client state machine and message dispatcher for CC:Tweaked GPS
local protocol = require("protocol")

local client_core = {}
client_core.__index = client_core

local function pruneExpiredPending(self, nowMs)
    local now = tonumber(nowMs)
    if not now then return end
    local ttl = self.pendingTtlMs or 5000
    for k, entry in pairs(self.pendingResponses) do
        if now - (entry.storedAt or 0) > ttl then
            self.pendingResponses[k] = nil
        end
    end
end

function client_core.new()
    local self = setmetatable({}, client_core)
    self.domainId = "CLIENT_" .. tostring(os.getComputerID and os.getComputerID() or 0)
    self.clientType = "AIRCRAFT"
    self.replyChannel = protocol.DEFAULT_REPLY_CHANNEL
    self.seq = 0
    self.isManaged = false
    self.pendingResponses = {}
    self.latestStatus = nil
    self.pendingTtlMs = 5000
    return self
end

function client_core:init(domainId, clientType, replyChannel)
    if domainId then self.domainId = tostring(domainId) end
    if clientType then self.clientType = tostring(clientType) end
    if replyChannel ~= nil then
        self.replyChannel = tonumber(replyChannel) or self.replyChannel
    else
        self.replyChannel = protocol.resolveDomainReplyChannel(self.domainId) or protocol.DEFAULT_REPLY_CHANNEL
    end
end

function client_core:setManaged(managed)
    self.isManaged = managed == true
end

function client_core:nextRequestPacket(altitudeY, nowMs, overrideSeq)
    pruneExpiredPending(self, nowMs)
    local targetSeq
    if overrideSeq then
        targetSeq = tonumber(overrideSeq) or self.seq
    else
        self.seq = self.seq + 1
        targetSeq = self.seq
    end
    local pkt = protocol.buildRequest(self.domainId, targetSeq, {
        replyChannel = self.replyChannel,
        altitudeY = tonumber(altitudeY) or 0,
        clientType = self.clientType,
        clientSeq = targetSeq,
    }, nowMs)
    return targetSeq, pkt
end

function client_core:nextStatusRequestPacket(queryType, nowMs)
    self.seq = self.seq + 1
    local pkt = protocol.buildStatusReq(self.domainId, self.seq, {
        queryType = tostring(queryType or "SUMMARY"),
    }, nowMs)
    return self.seq, pkt
end

function client_core:handleMessage(channel, message, nowMs)
    if type(message) ~= "table" then return false end
    local ch = tonumber(channel)
    if message.type == protocol.MSG_RESPONSE then
        if ch ~= self.replyChannel then return false end
        local ok = protocol.validatePacket(message, protocol.MSG_RESPONSE)
        if not ok then return false end
        local pl = message.payload
        if pl.targetClient ~= self.domainId then return false end
        local cSeq = tonumber(pl.clientSeq)
        if not cSeq then return false end
        pruneExpiredPending(self, nowMs)
        self.pendingResponses[cSeq] = { payload = pl, storedAt = tonumber(nowMs) or 0 }
        return true
    elseif message.type == protocol.MSG_STATUS_RESP then
        if ch ~= self.replyChannel and ch ~= protocol.CH_GPS_SERVICE then return false end
        local ok = protocol.validatePacket(message, protocol.MSG_STATUS_RESP)
        if not ok then return false end
        self.latestStatus = message.payload
        return true
    end
    return false
end

function client_core:poll(clientSeq)
    local cSeq = tonumber(clientSeq)
    if not cSeq then return nil end
    local entry = self.pendingResponses[cSeq]
    if entry then
        self.pendingResponses[cSeq] = nil
        return entry.payload
    end
    return nil
end

function client_core:pollStatus()
    local st = self.latestStatus
    self.latestStatus = nil
    return st
end

function client_core:getStatus()
    return {
        domainId = self.domainId,
        clientType = self.clientType,
        replyChannel = self.replyChannel,
        seq = self.seq,
        isManaged = self.isManaged,
    }
end

return client_core
