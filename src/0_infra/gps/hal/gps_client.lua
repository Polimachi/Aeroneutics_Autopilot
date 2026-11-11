-- Hybrid Client API and Modem HAL Adapter for CC:Tweaked GPS
if package and package.path and not string.find(package.path, "/gps/modules/?.lua", 1, true) then
    package.path = package.path .. ";/gps/modules/?.lua"
end

local client_core = require("client_core")
local protocol = require("protocol")

local gps_client = {}
local instance = client_core.new()

function gps_client.init(domainId, clientType, replyChannel)
    instance:init(domainId, clientType, replyChannel)
    local modem = peripheral and peripheral.find and peripheral.find("modem")
    if modem and modem.open and not instance.isManaged then
        modem.open(instance.replyChannel)
    end
end

function gps_client.setManaged(managed)
    instance:setManaged(managed)
end

function gps_client.request(altitudeY)
    local modem = peripheral and peripheral.find and peripheral.find("modem")
    if not modem then error("No modem attached for GPS client", 2) end
    local nowMs = os.epoch and os.epoch("utc") or 0
    local seq, pkt = instance:nextRequestPacket(altitudeY, nowMs)
    modem.transmit(protocol.CH_GPS_PING, instance.replyChannel, pkt)
    return seq
end

function gps_client.poll(clientSeq)
    return instance:poll(clientSeq)
end

function gps_client.handleMessage(_side, channel, _replyChannel, message, _distance)
    local nowMs = os.epoch and os.epoch("utc") or 0
    return instance:handleMessage(channel, message, nowMs)
end

function gps_client.getStatus()
    return instance:getStatus()
end

local function standaloneLocate(altitudeY, timeoutSec)
    local modem = peripheral and peripheral.find and peripheral.find("modem")
    if not modem then return nil, nil, nil, { status = "NO_MODEM" } end
    modem.open(instance.replyChannel)
    local nowMs = os.epoch and os.epoch("utc") or 0
    local seq, pkt = instance:nextRequestPacket(altitudeY, nowMs)
    modem.transmit(protocol.CH_GPS_PING, instance.replyChannel, pkt)
    local totalTimeout = tonumber(timeoutSec) or 0.5
    local halfTimeout = totalTimeout / 2.0
    local tHalf = os.startTimer(halfTimeout)
    local tEnd = os.startTimer(totalTimeout)
    local retried = false
    while true do
        local eventData = { os.pullEvent() }
        local ev = eventData[1]
        if ev == "timer" then
            local timerId = eventData[2]
            if timerId == tHalf and not retried then
                retried = true
                local _, retryPkt = instance:nextRequestPacket(altitudeY, os.epoch and os.epoch("utc") or 0, seq)
                modem.transmit(protocol.CH_GPS_PING, instance.replyChannel, retryPkt)
            elseif timerId == tEnd then
                return nil, nil, nil, { status = "TIMEOUT" }
            end
        elseif ev == "modem_message" then
            local handled = instance:handleMessage(eventData[3], eventData[5], os.epoch and os.epoch("utc") or 0)
            if handled then
                local fix = instance:poll(seq)
                if fix then
                    if fix.position then
                        return fix.position.x, altitudeY, fix.position.z, fix
                    end
                    return nil, nil, nil, fix
                end
            end
        end
    end
end

function gps_client.locate(altitudeY, timeoutSec)
    if instance.isManaged then
        local modem = peripheral and peripheral.find and peripheral.find("modem")
        if not modem then return nil, nil, nil, { status = "NO_MODEM" } end
        local startMs = os.epoch and os.epoch("utc") or 0
        local seq, pkt = instance:nextRequestPacket(altitudeY, startMs)
        modem.transmit(protocol.CH_GPS_PING, instance.replyChannel, pkt)
        local totalMs = (tonumber(timeoutSec) or 0.5) * 1000
        local halfAtMs = startMs + totalMs * 0.5
        local deadline = startMs + totalMs
        local retried = false
        while true do
            local fix = instance:poll(seq)
            if fix then
                if fix.position then return fix.position.x, altitudeY, fix.position.z, fix end
                return nil, nil, nil, fix
            end
            local nowMs = os.epoch and os.epoch("utc") or 0
            if nowMs >= deadline then break end
            if not retried and nowMs >= halfAtMs then
                retried = true
                local _, retryPkt = instance:nextRequestPacket(altitudeY, nowMs, seq)
                modem.transmit(protocol.CH_GPS_PING, instance.replyChannel, retryPkt)
            end
            sleep(0.05)
        end
        return nil, nil, nil, { status = "TIMEOUT" }
    else
        return standaloneLocate(altitudeY, timeoutSec)
    end
end

function gps_client.requestStatus(queryType, replyChannel)
    local modem = peripheral and peripheral.find and peripheral.find("modem")
    if not modem then error("No modem attached for GPS client", 2) end
    local nowMs = os.epoch and os.epoch("utc") or 0
    local seq, pkt = instance:nextStatusRequestPacket(queryType, nowMs)
    modem.transmit(protocol.CH_GPS_SERVICE, tonumber(replyChannel) or protocol.CH_GPS_SERVICE, pkt)
    return seq
end

function gps_client.pollStatus()
    return instance:pollStatus()
end

function gps_client.queryStatus(timeoutSec, queryType)
    if instance.isManaged then
        gps_client.requestStatus(queryType, protocol.CH_GPS_SERVICE)
        local deadline = (os.epoch and os.epoch("utc") or 0) + (tonumber(timeoutSec) or 0.5) * 1000
        while (os.epoch and os.epoch("utc") or 0) < deadline do
            local st = instance:pollStatus()
            if st then return st, nil end
            sleep(0.05)
        end
        return nil, "TIMEOUT"
    end
    local modem = peripheral and peripheral.find and peripheral.find("modem")
    if not modem then return nil, "NO_MODEM" end
    modem.open(protocol.CH_GPS_SERVICE)
    local nowMs = os.epoch and os.epoch("utc") or 0
    local _, pkt = instance:nextStatusRequestPacket(queryType, nowMs)
    modem.transmit(protocol.CH_GPS_SERVICE, protocol.CH_GPS_SERVICE, pkt)
    local tEnd = os.startTimer(tonumber(timeoutSec) or 0.5)
    while true do
        local evData = { os.pullEvent() }
        if evData[1] == "timer" and evData[2] == tEnd then
            return nil, "TIMEOUT"
        elseif evData[1] == "modem_message" then
            if instance:handleMessage(evData[3], evData[5], os.epoch and os.epoch("utc") or 0) then
                local st = instance:pollStatus()
                if st then return st, nil end
            end
        end
    end
end

if package and package.preload then
    package.preload["gps.client"] = function(...) return gps_client end
end

return gps_client
