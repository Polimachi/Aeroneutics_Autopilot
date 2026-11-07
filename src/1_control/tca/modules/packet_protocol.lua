-- ICD v1.9.5 Common Message Envelope Engine for TCA
local packet_protocol = {}

packet_protocol.PROTO_VERSION = "1.9.5"

--- Encode a table into ICD v1.9.5 envelope
function packet_protocol.encode_envelope(domainId, pktType, seq, payload)
    return {
        ver = packet_protocol.PROTO_VERSION,
        domainId = tostring(domainId or "AIRCRAFT_01"),
        seq = tonumber(seq) or 0,
        type = tostring(pktType or "MSG_UNKNOWN"),
        time = (os.epoch and os.epoch("utc")) or 0,
        payload = payload or {}
    }
end

--- Decode an envelope returning payload and metadata
function packet_protocol.decode_envelope(pkt)
    if type(pkt) ~= "table" then
        return nil, "PACKET_NOT_TABLE"
    end
    return {
        ver = pkt.ver,
        domainId = pkt.domainId,
        seq = pkt.seq,
        type = pkt.type,
        time = pkt.time,
        payload = pkt.payload or {}
    }
end

--- Verify that an envelope complies with ICD v1.9.5 standards
function packet_protocol.verify_packet(pkt, expectedDomain)
    if type(pkt) ~= "table" then
        return false, "NOT_TABLE"
    end
    if pkt.ver ~= packet_protocol.PROTO_VERSION then
        return false, "UNSUPPORTED_VERSION"
    end
    if type(pkt.type) ~= "string" or #pkt.type == 0 then
        return false, "MISSING_TYPE"
    end
    if type(pkt.domainId) ~= "string" or #pkt.domainId == 0 then
        return false, "MISSING_DOMAIN"
    end
    if expectedDomain and pkt.domainId ~= expectedDomain then
        return false, "DOMAIN_MISMATCH"
    end
    if type(pkt.seq) ~= "number" then
        return false, "INVALID_SEQ"
    end
    if type(pkt.payload) ~= "table" then
        return false, "INVALID_PAYLOAD"
    end
    return true, nil
end

return packet_protocol
