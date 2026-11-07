-- Protocol constants and packet validation for CC:Tweaked GPS system
local protocol = {
    WIRE_VERSION = "1.9.5", COMPAT_PREFIX = "^1%.9",
    CH_GPS_PING = 60001, CH_GPS_SERVICE = 60002, CH_GPS_NODE_IN = 60003, CH_GPS_MGMT = 60004,
    MSG_REQUEST = "MSG_GPS_REQUEST", MSG_NODE_REPORT = "MSG_GPS_NODE_REPORT",
    MSG_RESPONSE = "MSG_GPS_RESPONSE", MSG_NODE_HEARTBEAT = "MSG_GPS_NODE_HEARTBEAT",
    MSG_STATUS_REQ = "MSG_GPS_STATUS_REQ", MSG_STATUS_RESP = "MSG_GPS_STATUS_RESP",
    MSG_DIAG_TRIGGER = "MSG_GPS_DIAG_TRIGGER", MSG_DIAG_PING = "MSG_GPS_DIAG_PING",
    MSG_DIAG_REPORT = "MSG_GPS_DIAG_REPORT", MSG_NODE_HELLO = "MSG_GPS_NODE_HELLO",
    MSG_NODE_OFFER = "MSG_GPS_NODE_OFFER", MSG_NODE_VERIFY_REQ = "MSG_GPS_NODE_VERIFY_REQ",
    MSG_NODE_VERIFY_RESP = "MSG_GPS_NODE_VERIFY_RESP", MSG_NODE_REG_COMMIT = "MSG_GPS_NODE_REG_COMMIT",
    MSG_NODE_REG_ACK = "MSG_GPS_NODE_REG_ACK"
}

function protocol.buildEnvelope(domainId, seq, msgType, payload, nowMs)
    return {
        ver = protocol.WIRE_VERSION, domainId = tostring(domainId or "UNKNOWN"),
        seq = tonumber(seq) or 0, type = tostring(msgType or "UNKNOWN"),
        time = tonumber(nowMs) or (os.epoch and os.epoch("utc") or 0), payload = payload or {}
    }
end

function protocol.buildRequest(domainId, seq, reqFields, nowMs)
    if type(reqFields) ~= "table" then error("reqFields must be a table", 2) end
    if type(reqFields.altitudeY) ~= "number" then error("altitudeY required", 2) end
    if type(reqFields.replyChannel) ~= "number" then error("replyChannel required", 2) end
    local payload = {
        replyChannel = reqFields.replyChannel, altitudeY = reqFields.altitudeY,
        clientType = tostring(reqFields.clientType or "AIRCRAFT"), clientSeq = tonumber(reqFields.clientSeq) or seq
    }
    return protocol.buildEnvelope(domainId, seq, protocol.MSG_REQUEST, payload, nowMs)
end

function protocol.buildNodeReport(nodeId, seq, repFields, nowMs)
    if type(repFields) ~= "table" then error("repFields must be a table", 2) end
    if type(repFields.nodePos) ~= "table" then error("nodePos table required", 2) end
    if type(repFields.measuredDistance) ~= "number" then error("measuredDistance required", 2) end
    local payload = {
        targetClient = tostring(repFields.targetClient or ""), clientSeq = tonumber(repFields.clientSeq) or 0,
        nodeId = tostring(repFields.nodeId or nodeId),
        nodePos = { x = tonumber(repFields.nodePos.x) or 0, y = tonumber(repFields.nodePos.y) or 0, z = tonumber(repFields.nodePos.z) or 0 },
        measuredDistance = repFields.measuredDistance, clientAltitudeY = tonumber(repFields.clientAltitudeY) or 0,
        replyChannel = tonumber(repFields.replyChannel) or 0
    }
    return protocol.buildEnvelope(nodeId, seq, protocol.MSG_NODE_REPORT, payload, nowMs)
end

function protocol.buildResponse(serverDomainId, seq, respFields, nowMs)
    if type(respFields) ~= "table" then error("respFields must be a table", 2) end
    local payload = {
        targetClient = tostring(respFields.targetClient or ""), clientSeq = tonumber(respFields.clientSeq) or 0,
        status = tostring(respFields.status or "FAIL_INSUFFICIENT"),
        nodeCount = tonumber(respFields.nodeCount) or 0, selectedNodes = respFields.selectedNodes or {}
    }
    if respFields.position then
        payload.position = { x = tonumber(respFields.position.x) or 0, z = tonumber(respFields.position.z) or 0 }
        payload.accuracy = tonumber(respFields.accuracy) or 0
        payload.hdop = tonumber(respFields.hdop) or 99.9
    end
    return protocol.buildEnvelope(serverDomainId, seq, protocol.MSG_RESPONSE, payload, nowMs)
end

function protocol.buildHeartbeat(nodeId, seq, fields, nowMs)
    if type(fields) ~= "table" then error("fields must be a table", 2) end
    local pos = type(fields.pos) == "table" and fields.pos or {}
    local payload = {
        nodeId = tostring(fields.nodeId or nodeId), computerId = tonumber(fields.computerId) or -1,
        pos = { x = tonumber(pos.x) or 0, y = tonumber(pos.y) or 0, z = tonumber(pos.z) or 0 },
        status = tostring(fields.status or "ONLINE"), uptime = tonumber(fields.uptime) or 0,
        reportsSent = tonumber(fields.reportsSent) or 0
    }
    return protocol.buildEnvelope(nodeId, seq, protocol.MSG_NODE_HEARTBEAT, payload, nowMs)
end

function protocol.buildStatusReq(senderId, seq, fields, nowMs)
    local f = type(fields) == "table" and fields or {}
    local payload = { queryType = tostring(f.queryType or "SUMMARY") }
    return protocol.buildEnvelope(senderId, seq, protocol.MSG_STATUS_REQ, payload, nowMs)
end

function protocol.buildStatusResp(serverId, seq, fields, nowMs)
    if type(fields) ~= "table" then error("fields must be a table", 2) end
    local payload = {
        activeNodes = tonumber(fields.activeNodes) or 0, uptime = tonumber(fields.uptime) or 0,
        totalSolved = tonumber(fields.totalSolved) or 0, version = tostring(fields.version or protocol.WIRE_VERSION)
    }
    return protocol.buildEnvelope(serverId, seq, protocol.MSG_STATUS_RESP, payload, nowMs)
end

function protocol.buildDiagTrigger(serverId, seq, fields, nowMs)
    if type(fields) ~= "table" then error("fields must be a table", 2) end
    local payload = { diagId = tostring(fields.diagId or "DIAG-0"), targetNode = tostring(fields.targetNode or "") }
    return protocol.buildEnvelope(serverId, seq, protocol.MSG_DIAG_TRIGGER, payload, nowMs)
end

function protocol.buildDiagPing(originNode, seq, fields, nowMs)
    if type(fields) ~= "table" then error("fields must be a table", 2) end
    local pos = type(fields.originPos) == "table" and fields.originPos or {}
    local payload = {
        diagId = tostring(fields.diagId or "DIAG-0"), originNode = tostring(fields.originNode or originNode),
        originPos = { x = tonumber(pos.x) or 0, y = tonumber(pos.y) or 0, z = tonumber(pos.z) or 0 }
    }
    return protocol.buildEnvelope(originNode, seq, protocol.MSG_DIAG_PING, payload, nowMs)
end

function protocol.buildDiagReport(senderNode, seq, fields, nowMs)
    if type(fields) ~= "table" then error("fields must be a table", 2) end
    local payload = {
        diagId = tostring(fields.diagId or "DIAG-0"), senderNode = tostring(fields.senderNode or senderNode),
        targetNode = tostring(fields.targetNode or ""), measuredDistance = tonumber(fields.measuredDistance) or 0
    }
    return protocol.buildEnvelope(senderNode, seq, protocol.MSG_DIAG_REPORT, payload, nowMs)
end

local function validateRequestPayload(pl)
    if type(pl.replyChannel) ~= "number" or pl.replyChannel < 1 or pl.replyChannel > 65535 then return false, "Invalid replyChannel" end
    if type(pl.altitudeY) ~= "number" then return false, "Missing or invalid altitudeY" end
    if type(pl.clientType) ~= "string" then return false, "Missing clientType" end
    if type(pl.clientSeq) ~= "number" then return false, "Missing clientSeq" end
    return true
end

local function validateNodeReportPayload(pl)
    if type(pl.targetClient) ~= "string" or pl.targetClient == "" then return false, "Missing targetClient" end
    if type(pl.nodePos) ~= "table" or type(pl.nodePos.x) ~= "number" then return false, "Missing nodePos.x" end
    if type(pl.measuredDistance) ~= "number" then return false, "Missing measuredDistance" end
    if type(pl.replyChannel) ~= "number" or pl.replyChannel < 1 or pl.replyChannel > 65535 then return false, "Invalid replyChannel" end
    return true
end

local function validateResponsePayload(pl)
    if type(pl.targetClient) ~= "string" or pl.targetClient == "" then return false, "Missing targetClient" end
    if type(pl.status) ~= "string" then return false, "Missing status" end
    if pl.status == "FIX_OK" or pl.status == "FIX_DEGRADED" then
        if type(pl.position) ~= "table" or type(pl.position.x) ~= "number" then return false, "Missing position for fix" end
    end
    return true
end

local function validateHeartbeatPayload(pl)
    if type(pl.nodeId) ~= "string" or pl.nodeId == "" then return false, "Missing nodeId" end
    if type(pl.pos) ~= "table" or type(pl.pos.x) ~= "number" then return false, "Missing pos.x" end
    return true
end

local function validateStatusPayload(pl, isReq)
    if isReq then
        if type(pl.queryType) ~= "string" then return false, "Missing queryType" end
    else
        if type(pl.activeNodes) ~= "number" then return false, "Missing activeNodes" end
    end
    return true
end

local function validateDiagPayload(pl, pType)
    if type(pl.diagId) ~= "string" or pl.diagId == "" then return false, "Missing diagId" end
    if pType == protocol.MSG_DIAG_PING and (type(pl.originPos) ~= "table" or type(pl.originPos.x) ~= "number") then
        return false, "Missing originPos"
    elseif pType == protocol.MSG_DIAG_REPORT and type(pl.measuredDistance) ~= "number" then
        return false, "Missing measuredDistance"
    end
    return true
end

local function validateTypedPayload(pl, pType)
    if pType == protocol.MSG_REQUEST then return validateRequestPayload(pl)
    elseif pType == protocol.MSG_NODE_REPORT then return validateNodeReportPayload(pl)
    elseif pType == protocol.MSG_RESPONSE then return validateResponsePayload(pl)
    elseif pType == protocol.MSG_NODE_HEARTBEAT then return validateHeartbeatPayload(pl)
    elseif pType == protocol.MSG_STATUS_REQ then return validateStatusPayload(pl, true)
    elseif pType == protocol.MSG_STATUS_RESP then return validateStatusPayload(pl, false)
    elseif pType == protocol.MSG_DIAG_TRIGGER or pType == protocol.MSG_DIAG_PING or pType == protocol.MSG_DIAG_REPORT then
        return validateDiagPayload(pl, pType)
    end
    return true, nil
end

function protocol.validatePacket(pkt, expectedType)
    if type(pkt) ~= "table" then return false, "Packet must be a table" end
    if type(pkt.ver) ~= "string" then return false, "Missing ver field" end
    if expectedType and pkt.type ~= expectedType then
        return false, string.format("Type mismatch: expected %s, got %s", expectedType, tostring(pkt.type))
    end
    local versionWarning = false
    if pkt.ver ~= protocol.WIRE_VERSION then
        if string.find(pkt.ver, protocol.COMPAT_PREFIX) then
            versionWarning = true
        else
            return false, "VERSION_MISMATCH: expected 1.9.x, got " .. pkt.ver
        end
    end
    local pl = pkt.payload
    if type(pl) ~= "table" then return false, "Missing payload table" end
    local valid, err = validateTypedPayload(pl, pkt.type)
    if not valid then return false, err end
    return true, { versionWarning = versionWarning, patchVer = pkt.ver }
end

return protocol
