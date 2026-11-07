-- On-Change Actuator Status Reporter for TCA v1.4.0
local packet_protocol = require("packet_protocol")

local status_reporter = {}
status_reporter.__index = status_reporter

--- Initialize status reporter instance
function status_reporter.init(groupId, modem, channel, domainId)
    local inst = {
        groupId = tostring(groupId or "THR_MAIN_L"),
        modem = modem,
        channel = tonumber(channel) or 10006,
        domainId = tostring(domainId or "AIRCRAFT_01"),
        seq = 0,
        lastReport = {}
    }
    return setmetatable(inst, status_reporter)
end

--- Check if status changed and transmit MSG_ACTUATOR_STATUS if needed (force = manual ping)
function status_reporter.check_and_send(reporter, currentStatus, force)
    if not reporter or type(currentStatus) ~= "table" then
        return false
    end

    local last = reporter.lastReport or {}
    local changed = (last.activeCount ~= currentStatus.activeCount) or
                    (last.interactionMode ~= currentStatus.interactionMode) or
                    (last.isSaturated ~= currentStatus.isSaturated) or
                    (last.healthStatus ~= currentStatus.healthStatus)

    if not changed and not force then
        return false
    end

    reporter.seq = (reporter.seq + 1) % 65536
    local payload = {
        groupId = currentStatus.groupId or reporter.groupId,
        interactionMode = currentStatus.interactionMode or "REDSTONE",
        appliedSignal = tonumber(currentStatus.appliedSignal) or 0,
        appliedRatio = tonumber(currentStatus.appliedRatio) or 0.0,
        isSaturated = currentStatus.isSaturated == true,
        activeCount = tonumber(currentStatus.activeCount) or 0,
        totalCount = tonumber(currentStatus.totalCount) or 0,
        healthStatus = tostring(currentStatus.healthStatus or "REDSTONE_NOMINAL")
    }

    local pkt = packet_protocol.encode_envelope(
        reporter.domainId,
        "MSG_ACTUATOR_STATUS",
        reporter.seq,
        payload
    )

    if reporter.modem and reporter.channel and reporter.modem.transmit then
        pcall(reporter.modem.transmit, reporter.channel, reporter.channel, pkt)
    end

    reporter.lastReport = {
        activeCount = payload.activeCount,
        interactionMode = payload.interactionMode,
        isSaturated = payload.isSaturated,
        healthStatus = payload.healthStatus
    }
    return true
end

return status_reporter
