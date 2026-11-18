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
    self.lastReceivedSeq = 0
    self.lastSolvedSeq = 0
    self.isManaged = false
    self.pendingResponses = {}
    self.latestStatus = nil
    self.pendingTtlMs = 5000
    self.consecutiveFailures = 0
    self.lastHdop = 1.0
    self.lastSatelliteCount = 4
    self.navQuality = "GOOD"
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
    self.lastReceivedSeq = 0
    self.lastSolvedSeq = 0
    self.consecutiveFailures = 0
    self.lastHdop = 1.0
    self.lastSatelliteCount = 4
    self.navQuality = "GOOD"
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
    if targetSeq < (self.lastReceivedSeq or 0) then
        self.lastReceivedSeq = 0
        self.lastSolvedSeq = 0
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
        if cSeq < (self.lastReceivedSeq or 0) or cSeq <= (self.lastSolvedSeq or 0) then
            return false
        end
        self.lastReceivedSeq = cSeq
        if pl.status == "FIX_OK" or pl.status == "FIX_DEGRADED" then
            self.lastSolvedSeq = cSeq
            self.consecutiveFailures = 0
            self.lastHdop = tonumber(pl.hdop) or self.lastHdop
            self.lastSatelliteCount = tonumber(pl.nodeCount) or self.lastSatelliteCount
            self.navQuality = pl.navQuality or protocol.classifyNavQuality(self.lastHdop, self.lastSatelliteCount, 0)
        else
            self.consecutiveFailures = (self.consecutiveFailures or 0) + 1
            self.navQuality = protocol.classifyNavQuality(pl.hdop or self.lastHdop, pl.nodeCount or self.lastSatelliteCount, self.consecutiveFailures)
        end
        pruneExpiredPending(self, nowMs)
        self.pendingResponses[cSeq] = { payload = pl, storedAt = tonumber(nowMs) or 0 }
        return true
    elseif message.type == protocol.MSG_NAV_QUALITY then
        if ch ~= self.replyChannel and ch ~= protocol.CH_GPS_SERVICE then return false end
        local pl = type(message.payload) == "table" and message.payload or nil
        if not pl or (pl.targetClient and pl.targetClient ~= self.domainId) then return false end
        self.navQuality = pl.navQuality or self.navQuality
        if pl.consecutiveFailures ~= nil then self.consecutiveFailures = tonumber(pl.consecutiveFailures) or self.consecutiveFailures end
        if pl.satelliteCount ~= nil then self.lastSatelliteCount = tonumber(pl.satelliteCount) or self.lastSatelliteCount end
        if pl.hdop ~= nil then self.lastHdop = tonumber(pl.hdop) or self.lastHdop end
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

function client_core:recordTimeout()
    self.consecutiveFailures = (self.consecutiveFailures or 0) + 1
    self.navQuality = protocol.classifyNavQuality(self.lastHdop, self.lastSatelliteCount, self.consecutiveFailures)
    return self.navQuality, self.consecutiveFailures
end

function client_core:getNavQuality()
    return self.navQuality or "GOOD", self.consecutiveFailures or 0
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
