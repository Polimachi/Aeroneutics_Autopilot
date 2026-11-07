-- Client state machine and message dispatcher for CC:Tweaked GPS
local protocol = require("protocol")

local client_core = {}
client_core.__index = client_core

function client_core.new()
    local self = setmetatable({}, client_core)
    self.domainId = "CLIENT_" .. tostring(os.getComputerID and os.getComputerID() or 0)
    self.clientType = "AIRCRAFT"
    self.replyChannel = protocol.DEFAULT_REPLY_CHANNEL
    self.seq = 0
    self.isManaged = false
    self.pendingResponses = {}
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

function client_core:handleMessage(channel, message, nowMs)
    if tonumber(channel) ~= self.replyChannel then return false end
    if type(message) ~= "table" then return false end
    local ok = protocol.validatePacket(message, protocol.MSG_RESPONSE)
    if not ok then return false end
    local pl = message.payload
    if pl.targetClient ~= self.domainId then return false end
    local cSeq = tonumber(pl.clientSeq)
    if not cSeq then return false end
    self.pendingResponses[cSeq] = pl
    return true
end

function client_core:poll(clientSeq)
    local cSeq = tonumber(clientSeq)
    if not cSeq then return nil end
    local res = self.pendingResponses[cSeq]
    if res then
        self.pendingResponses[cSeq] = nil
        return res
    end
    return nil
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
