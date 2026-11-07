-- Profile exporter and synchronization module for Alignment
local profile_exporter = {}

local function serialize_json_val(val)
    local t = type(val)
    if t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "table" then
        local is_arr = (#val > 0)
        local parts = {}
        if is_arr then
            for i = 1, #val do
                parts[#parts + 1] = serialize_json_val(val[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(val) do
                parts[#parts + 1] = string.format("%q:%s", tostring(k), serialize_json_val(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

function profile_exporter.serialize_profile(profile_data)
    if textutils and textutils.serializeJSON then
        return textutils.serializeJSON(profile_data)
    end
    return serialize_json_val(profile_data)
end

function profile_exporter.build_sync_packet(domain_id, seq, profile_data)
    return {
        ver = "1.9.5",
        domainId = domain_id,
        seq = seq or 1,
        type = "MSG_PROFILE_SYNC",
        time = (os and os.epoch and os.epoch("utc")) or 0,
        payload = profile_data or {}
    }
end

function profile_exporter.validate_ack(ack_pkt, expected_profile_id)
    if not ack_pkt or type(ack_pkt) ~= "table" then
        return false, "NIL_OR_NON_TABLE_PACKET"
    end
    if ack_pkt.type ~= "MSG_CALIB_ACK" then
        return false, "UNEXPECTED_PACKET_TYPE"
    end
    local p = ack_pkt.payload
    if not p or type(p) ~= "table" then
        return false, "MISSING_PAYLOAD"
    end
    if expected_profile_id and p.profileId ~= expected_profile_id then
        return false, "PROFILE_ID_MISMATCH"
    end
    if p.status ~= "ACCEPTED" then
        return false, p.status or "NOT_ACCEPTED"
    end
    return true, "ACCEPTED"
end

return profile_exporter
