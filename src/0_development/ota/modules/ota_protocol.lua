-- src/0_development/ota/modules/ota_protocol.lua
-- Strict ICD 1.9.5 Wire Framing & Chunking Helper for Hangar Wireless OTA Server

local ota_agent = require("ota_agent")

local ota_protocol = {}

ota_protocol.ICD_VERSION = "1.9.5"
ota_protocol.DEFAULT_CHUNK_SIZE = 2048

--- Normalizes a relative or absolute VFS path and rejects directory traversal.
-- @param rawPath string Input path
-- @return string|nil Normalized "/..." path or nil when invalid
function ota_protocol.normalize_rel_path(rawPath)
    if type(rawPath) ~= "string" or rawPath == "" then
        return nil
    end
    local p = rawPath:gsub("\\", "/")
    if p:find("..", 1, true) then
        return nil
    end
    while p:sub(1, 1) == "/" do
        p = p:sub(2)
    end
    while #p > 0 and p:sub(-1) == "/" do
        p = p:sub(1, -2)
    end
    if p == "" then
        return nil
    end
    return "/" .. p
end

--- Builds a strict ICD 1.9.5 packet envelope without legacy keys.
-- @param domainId string Sender domain identifier
-- @param seq number Monotonic sequence counter
-- @param msgType string Canonical MSG_OTA_* packet type
-- @param payload table Packet payload table
-- @param nowMs number|nil UTC epoch milliseconds
-- @return table envelope
function ota_protocol.build_envelope(domainId, seq, msgType, payload, nowMs)
    assert(type(domainId) == "string" and domainId ~= "", "build_envelope requires non-empty domainId")
    assert(type(seq) == "number", "build_envelope requires numeric seq")
    assert(type(msgType) == "string" and msgType ~= "", "build_envelope requires non-empty msgType")
    assert(type(payload) == "table", "build_envelope requires table payload")

    local timestamp = nowMs
    if type(timestamp) ~= "number" then
        if os and os.epoch then
            timestamp = os.epoch("utc")
        elseif os and os.time then
            timestamp = os.time() * 1000
        else
            timestamp = 0
        end
    end

    return {
        ver = ota_protocol.ICD_VERSION,
        domainId = domainId,
        seq = seq,
        type = msgType,
        time = timestamp,
        payload = payload,
    }
end

--- Validates and parses an incoming ICD 1.9.5 packet envelope (Zero-Fallback).
-- @param raw any Raw decoded packet
-- @param expectedVer string|nil Expected ICD version (defaults to "1.9.5")
-- @return table|nil parsedEnvelope
-- @return string|nil errorCode
function ota_protocol.parse_envelope(raw, expectedVer)
    local targetVer = expectedVer or ota_protocol.ICD_VERSION
    if type(raw) ~= "table" then
        return nil, "INVALID_ENVELOPE"
    end
    if type(raw.ver) ~= "string" then
        return nil, "INVALID_ENVELOPE"
    end
    if raw.ver ~= targetVer then
        return nil, "VERSION_MISMATCH"
    end
    if type(raw.domainId) ~= "string" or raw.domainId == "" then
        return nil, "INVALID_ENVELOPE"
    end
    if type(raw.seq) ~= "number" then
        return nil, "INVALID_ENVELOPE"
    end
    if type(raw.type) ~= "string" or raw.type == "" then
        return nil, "INVALID_ENVELOPE"
    end
    if type(raw.time) ~= "number" then
        return nil, "INVALID_ENVELOPE"
    end
    if type(raw.payload) ~= "table" then
        return nil, "INVALID_ENVELOPE"
    end
    return raw, nil
end

--- Splits a file payload into fixed-size chunks with IEEE 802.3 CRC32 checksums.
-- @param relPath string Target file path on slave node
-- @param content string File byte content
-- @param chunkSize number|nil Maximum bytes per chunk (default 2048)
-- @return table fileManifest { path, size, crc32, chunkCount }
-- @return table chunks { { chunkIndex, chunkCrc32, data }, ... }
function ota_protocol.chunk_file(relPath, content, chunkSize)
    local normPath = ota_protocol.normalize_rel_path(relPath)
    if not normPath then
        error("Invalid file path for chunk_file: " .. tostring(relPath), 2)
    end
    if type(content) ~= "string" then
        error("chunk_file content must be a string", 2)
    end

    local maxBytes = math.floor(tonumber(chunkSize) or ota_protocol.DEFAULT_CHUNK_SIZE)
    if maxBytes < 1 then
        error("chunk_file chunkSize must be >= 1", 2)
    end

    local totalLen = #content
    local fileCrc = ota_agent.crc32(content)
    local chunks = {}

    if totalLen > 0 then
        local idx = 1
        local pos = 1
        while pos <= totalLen do
            local endPos = math.min(totalLen, pos + maxBytes - 1)
            local slice = string.sub(content, pos, endPos)
            chunks[idx] = {
                chunkIndex = idx,
                chunkCrc32 = ota_agent.crc32(slice),
                data = slice,
            }
            idx = idx + 1
            pos = endPos + 1
        end
    end

    local fileManifest = {
        path = normPath,
        size = totalLen,
        crc32 = fileCrc,
        chunkCount = #chunks,
    }
    return fileManifest, chunks
end

return ota_protocol
