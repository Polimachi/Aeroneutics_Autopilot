-- JSONL streaming/rollover and ring-buffer dumper layered over storage_pool VFS.
local storage_pool = require("storage_pool")
local ring_buffer = require("ring_buffer")

local jsonl_dumper = {}

local function serialize_line(tbl)
    local raw = textutils.serialiseJSON(tbl)
    return tostring(raw):gsub("[\r\n]", " ")
end

local function resolve_apis(apis)
    local a = apis or {}
    return a.peripheral or _G.peripheral, a.disk or _G.disk, a.fs or _G.fs
end

local function resolve_volume(cfg, activeSessionId, apis, minOverride)
    local pApi, dApi, fApi = resolve_apis(apis)
    local vols = storage_pool.scan_volumes(cfg, pApi, dApi, fApi)
    local best = storage_pool.select_best_volume(vols, cfg, minOverride)
    if not best and cfg.storage and cfg.storage.autoPruneOldest ~= false then
        storage_pool.prune_oldest_sessions(vols, cfg, activeSessionId, fApi)
        vols = storage_pool.scan_volumes(cfg, pApi, dApi, fApi)
        best = storage_pool.select_best_volume(vols, cfg, minOverride)
    end
    return best, vols
end

local function write_line_counted(stream, tbl)
    local line = serialize_line(tbl)
    stream.handle.writeLine(line)
    local delta = #line + 1
    stream.partBytes = stream.partBytes + delta
    local partInfo = stream.parts[#stream.parts]
    if partInfo then
        partInfo.bytes = partInfo.bytes + delta
    end
    return delta
end

local function open_next_part(stream, reason, apis)
    local _, _, fApi = resolve_apis(apis)
    local st = stream.cfg.storage or {}
    local minReq = (reason == "OPEN") and (st.minFreeSpaceBytes or 16384) or ((st.rollOverReserveBytes or 16384) + 1)
    local best, vols = resolve_volume(stream.cfg, stream.sessionId, apis, minReq)
    if not best then
        best, vols = resolve_volume(stream.cfg, stream.sessionId, apis, st.minFreeSpaceBytes or 16384)
    end
    if not best then
        return false, "ERR_DISK_FULL", vols
    end

    local pPath, pDir = storage_pool.build_part_path(
        best, stream.cfg, stream.domainId, stream.startedAtMs, stream.partIndex
    )
    storage_pool.ensure_dir(pDir, fApi)
    local fh = fApi.open(pPath, "w")
    if not fh then return false, "ERR_FILE_OPEN", vols end

    stream.handle = fh
    stream.activeVolume = best
    stream.volumes = vols
    stream.partBytes = 0
    stream.partFrames = 0
    table.insert(stream.parts, {
        partIndex = stream.partIndex,
        peripheralName = best.peripheralName,
        mountPath = best.mountPath,
        filePath = pPath,
        frames = 0,
        bytes = 0,
    })

    write_line_counted(stream, {
        recordType = "META",
        schemaVersion = "1.1.0",
        sessionId = stream.sessionId,
        partIndex = stream.partIndex,
        domainId = stream.domainId,
        baseChannel = stream.baseChannel,
        recordMode = stream.cfg.recordMode or "STREAMING",
        startedAtMs = stream.startedAtMs,
        trigger = reason,
        tapOptions = stream.cfg.tapOptions,
        volumeMount = best.mountPath,
    })
    fh.flush()
    return true, nil, vols
end

--- Open a new JSONL streaming session on the best VFS volume.
function jsonl_dumper.open_stream(cfg, sessionMeta, apis)
    local m = sessionMeta or {}
    local stream = {
        cfg = cfg or {},
        sessionId = m.sessionId or (tostring(m.domainId or "AIRCRAFT") .. "_" .. tostring(m.startedAtMs or 0)),
        domainId = m.domainId or "UNKNOWN",
        baseChannel = m.baseChannel or 10000,
        startedAtMs = m.startedAtMs or 0,
        manifestPath = m.manifestPath or ("/logs/sessions/" .. tostring(m.sessionId or "session") .. ".json"),
        partIndex = 1,
        parts = {},
        pendingSinceFlush = 0,
        lastFlushMs = m.startedAtMs or 0,
        totalFrames = 0,
        closed = false,
    }
    local ok, err = open_next_part(stream, "OPEN", apis)
    if not ok then return nil, err end
    return stream, nil
end

local function close_active_part(stream, reason, nextPart, nowMs)
    if not stream.handle then return end
    local partInfo = stream.parts[#stream.parts]
    write_line_counted(stream, {
        recordType = "FOOTER",
        endedAtMs = nowMs or 0,
        trigger = reason,
        frameCount = stream.partFrames,
        bytesWritten = stream.partBytes,
        rolloverReason = nextPart and reason or nil,
        nextPart = nextPart,
    })
    stream.handle.flush()
    stream.handle.close()
    stream.handle = nil
    if partInfo then
        partInfo.frames = stream.partFrames
    end
end

local function should_rollover(stream, fApi)
    local st = stream.cfg.storage or {}
    local maxPart = st.maxPartBytes or 100000
    local reserve = st.rollOverReserveBytes or 16384
    if stream.partBytes >= maxPart then
        return "PART_LIMIT"
    end
    if fApi and fApi.getFreeSpace and fApi.getFreeSpace(stream.activeVolume.mountPath) <= reserve then
        return "DISK_LOW_SPACE"
    end
    return nil
end

--- Flush pending writes and rollover to next part/volume when needed.
function jsonl_dumper.flush_stream(stream, nowMs, apis)
    if not stream or not stream.handle then return false, "ERR_STREAM_CLOSED" end
    stream.handle.flush()
    stream.pendingSinceFlush = 0
    stream.lastFlushMs = nowMs or stream.lastFlushMs
    local _, _, fApi = resolve_apis(apis)
    local rollReason = should_rollover(stream, fApi)
    if rollReason then
        return jsonl_dumper.rollover_stream(stream, rollReason, nowMs, apis)
    end
    return true, nil
end

function jsonl_dumper.rollover_stream(stream, reason, nowMs, apis)
    if not stream or stream.closed then return false, "ERR_STREAM_CLOSED" end
    local nextIdx = stream.partIndex + 1
    close_active_part(stream, reason or "MANUAL_SPLIT", nextIdx, nowMs)
    stream.partIndex = nextIdx
    local ok, err = open_next_part(stream, reason or "ROLLOVER", apis)
    if not ok then
        stream.closed = true
        return false, err
    end
    return true, nil
end

--- Append one FRAME record, auto-flushing and rolling over per policy.
function jsonl_dumper.append_frame(stream, record, nowMs, apis)
    if not stream or stream.closed or not stream.handle then
        return false, "ERR_STREAM_CLOSED"
    end
    write_line_counted(stream, record)
    stream.partFrames = stream.partFrames + 1
    stream.totalFrames = stream.totalFrames + 1
    stream.pendingSinceFlush = stream.pendingSinceFlush + 1

    local _, _, fApi = resolve_apis(apis)
    local rollReason = should_rollover(stream, fApi)
    if rollReason then
        return jsonl_dumper.rollover_stream(stream, rollReason, nowMs, apis)
    end
    local sc = stream.cfg.streaming or {}
    local maxPend = sc.flushIntervalFrames or 20
    local maxAgeMs = (sc.flushIntervalSec or 1.0) * 1000
    if stream.pendingSinceFlush >= maxPend or ((nowMs or 0) - stream.lastFlushMs >= maxAgeMs) then
        stream.handle.flush()
        stream.pendingSinceFlush = 0
        stream.lastFlushMs = nowMs or stream.lastFlushMs
    end
    return true, nil
end

--- Close active stream cleanly and persist session_manifest.json.
function jsonl_dumper.close_stream(stream, reason, nowMs, apis)
    if not stream then return false end
    if stream.handle then
        close_active_part(stream, reason or "SESSION_END", nil, nowMs)
    end
    stream.closed = true
    local _, _, fApi = resolve_apis(apis)
    storage_pool.write_session_manifest(stream.manifestPath, {
        sessionId = stream.sessionId,
        domainId = stream.domainId,
        baseChannel = stream.baseChannel,
        manifestPath = stream.manifestPath,
        startedAtMs = stream.startedAtMs,
        endedAtMs = nowMs or 0,
        totalFrames = stream.totalFrames,
        parts = stream.parts,
    }, fApi)
    return true
end

--- Dump an entire RING_BUFFER snapshot across VFS parts safely.
function jsonl_dumper.dump_ring_buffer(buf, cfg, meta, apis)
    local snap = ring_buffer.snapshot(buf)
    local stream, err = jsonl_dumper.open_stream(cfg, {
        sessionId = meta and meta.sessionId,
        domainId = meta and meta.domainId,
        baseChannel = meta and meta.baseChannel,
        startedAtMs = (meta and meta.nowMs) or 0,
        manifestPath = meta and meta.manifestPath,
    }, apis)
    if not stream then return false, nil, err end
    for _, rec in ipairs(snap) do
        local ok, wErr = jsonl_dumper.append_frame(stream, rec, (meta and meta.nowMs) or rec.rxMs, apis)
        if not ok then
            jsonl_dumper.close_stream(stream, wErr or "DISK_FULL", meta and meta.nowMs, apis)
            return false, nil, wErr
        end
    end
    jsonl_dumper.close_stream(stream, (meta and meta.trigger) or "RING_DUMP", meta and meta.nowMs, apis)
    return true, {
        sessionId = stream.sessionId,
        manifestPath = stream.manifestPath,
        parts = stream.parts,
        frameCount = #snap,
    }, nil
end

return jsonl_dumper
