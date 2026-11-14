-- FDR Ground In-Flight Aligner & Multi-Disk VFS Logger (Receive-Only)
if package and package.path then
    package.path = "/modules/?.lua;./modules/?.lua;" .. package.path
end

local ring_buffer = require("ring_buffer")
local packet_tap = require("packet_tap")
local storage_pool = require("storage_pool")
local jsonl_dumper = require("jsonl_dumper")
local cloud_exporter = require("cloud_exporter")
local fdr_ui = require("fdr_ui")

local main = {}

local function now_ms(apis)
    if apis and apis.epoch then return apis.epoch("utc") end
    if os and os.epoch then return os.epoch("utc") end
    return 0
end

local function read_json_file(path, fsApi)
    local fApi = fsApi or _G.fs
    if not fApi or not fApi.exists or not fApi.exists(path) then return nil end
    local fh = fApi.open(path, "r")
    if not fh then return nil end
    local raw = fh.readAll()
    fh.close()
    local dec = textutils and (textutils.unserialiseJSON or textutils.unserializeJSON)
    return dec and dec(raw) or nil
end

function main.load_config(cfgOrPath, fsApi)
    local cfg = type(cfgOrPath) == "table" and cfgOrPath
        or read_json_file(cfgOrPath or "/config/fdr_config.json", fsApi)
        or read_json_file("config/fdr_config.json", fsApi)
        or {}
    cfg.aircraftIndexN = cfg.aircraftIndexN or 1
    cfg.domainId = cfg.domainId or "*"
    cfg.recordMode = cfg.recordMode or "STREAMING"
    cfg.storage = cfg.storage or {}
    cfg.ringBuffer = cfg.ringBuffer or { capacity = 1500 }
    cfg.export = cfg.export or { mode = "GDRIVE_WEBHOOK" }
    return cfg
end

local function refresh_volumes(state)
    local a = state.apis or {}
    state.volumes = storage_pool.scan_volumes(state.cfg, a.peripheral, a.disk, a.fs)
end

local function open_active_stream(state)
    if state.cfg.recordMode ~= "STREAMING" then return true end
    local started = now_ms(state.apis)
    local dom = (state.tap.lockedDomainId ~= "*") and state.tap.lockedDomainId or ("CRAFT_N" .. tostring(state.tap.aircraftIndexN))
    local sid = string.format("%s_%d", tostring(dom), started)
    local stream, err = jsonl_dumper.open_stream(state.cfg, {
        sessionId = sid,
        domainId = dom,
        baseChannel = state.tap.baseChannel,
        startedAtMs = started,
        manifestPath = "/logs/sessions/" .. sid .. ".json",
    }, state.apis)
    if not stream then
        state.mode = "DISK_FULL"
        state.lastEventMsg = tostring(err or "ERR_DISK_FULL")
        return false
    end
    state.stream = stream
    return true
end

local function close_active_stream(state, reason)
    if not state.stream then return end
    local tMs = now_ms(state.apis)
    jsonl_dumper.close_stream(state.stream, reason or "SESSION_END", tMs, state.apis)
    state.lastSessionManifest = {
        sessionId = state.stream.sessionId,
        domainId = state.stream.domainId,
        baseChannel = state.stream.baseChannel,
        manifestPath = state.stream.manifestPath,
        totalFrames = state.stream.totalFrames,
        parts = state.stream.parts,
    }
    state.stream = nil
end

function main.init(cfgOrPath, apis)
    local a = apis or {}
    local cfg = main.load_config(cfgOrPath, a.fs)
    local tap = packet_tap.init(cfg, a.modem)
    packet_tap.open_channels(tap)
    local ring = ring_buffer.init((cfg.ringBuffer and cfg.ringBuffer.capacity) or 1500)
    local state = {
        cfg = cfg, apis = a, tap = tap, ring = ring, stream = nil,
        volumes = {}, mode = (cfg.autoStartOnBoot == false) and "STANDBY" or "LOGGING",
        estopFlushed = false, framesWritten = 0, running = true,
        lastSessionManifest = nil, lastExportResult = "GDRIVE READY",
        lastEventMsg = "OPENED BASE " .. tostring(tap.baseChannel), uiDirty = true,
    }
    refresh_volumes(state)
    if state.mode == "LOGGING" and cfg.recordMode == "STREAMING" then
        open_active_stream(state)
    end
    return state
end

function main.switch_aircraft(state, newN, domainOverride)
    local base, err = packet_tap.compute_base(newN)
    if not base then
        state.lastEventMsg = tostring(err)
        return false, err
    end
    close_active_stream(state, "AIRCRAFT_REBIND")
    ring_buffer.clear(state.ring)
    local ok, bErr = packet_tap.bind_aircraft(state.tap, newN, domainOverride or "*")
    if not ok then
        state.lastEventMsg = tostring(bErr)
        return false, bErr
    end
    state.estopFlushed = false
    state.framesWritten = 0
    if state.mode == "LOGGING" and state.cfg.recordMode == "STREAMING" then
        open_active_stream(state)
    end
    state.lastEventMsg = "BOUND N=" .. tostring(newN) .. " BASE=" .. tostring(base)
    state.uiDirty = true
    return true
end

local function flush_on_estop(state, tMs)
    state.estopFlushed = true
    state.lastEventMsg = "ESTOP_AUTO_FLUSH"
    if state.cfg.recordMode == "STREAMING" and state.stream then
        jsonl_dumper.flush_stream(state.stream, tMs, state.apis)
        return
    end
    local ok, manifest = jsonl_dumper.dump_ring_buffer(state.ring, state.cfg, {
        domainId = state.tap.lockedDomainId,
        baseChannel = state.tap.baseChannel,
        nowMs = tMs,
        trigger = "E_STOP",
    }, state.apis)
    if ok and manifest then state.lastSessionManifest = manifest end
end

local function handle_modem_frame(state, channel, pkt)
    if state.mode ~= "LOGGING" then return false end
    local tMs = now_ms(state.apis)
    local rec, _ = packet_tap.classify_packet(state.tap, channel, pkt, tMs)
    if not rec then return false end
    ring_buffer.push(state.ring, rec)
    if state.cfg.recordMode == "STREAMING" and state.stream then
        local ok, wErr = jsonl_dumper.append_frame(state.stream, rec, tMs, state.apis)
        if not ok then
            close_active_stream(state, wErr or "DISK_FULL")
            state.mode = "DISK_FULL"
            state.lastEventMsg = tostring(wErr or "ERR_DISK_FULL")
            return true
        end
    end
    state.framesWritten = state.framesWritten + 1
    if packet_tap.is_estop_trigger(rec) then
        if not state.estopFlushed and state.cfg.storage.autoFlushOnEstop ~= false then
            flush_on_estop(state, tMs)
        end
    elseif rec.msgType == "MSG_FLIGHT_TELEMETRY" then
        state.estopFlushed = false
    end
    state.uiDirty = true
    return true
end

local function trigger_manual_dump(state)
    local tMs = now_ms(state.apis)
    if state.cfg.recordMode == "STREAMING" and state.stream then
        local ok, err = jsonl_dumper.flush_stream(state.stream, tMs, state.apis)
        state.lastEventMsg = ok and "FLUSHED STREAM" or tostring(err)
        return
    end
    local ok, manifest, err = jsonl_dumper.dump_ring_buffer(state.ring, state.cfg, {
        domainId = state.tap.lockedDomainId, baseChannel = state.tap.baseChannel,
        nowMs = tMs, trigger = "MANUAL_DUMP",
    }, state.apis)
    if ok then
        state.lastSessionManifest = manifest
        state.lastEventMsg = "DUMPED " .. tostring(manifest.frameCount) .. "F"
    else
        state.lastEventMsg = tostring(err or "DUMP_FAIL")
    end
end

local function trigger_export(state)
    local target = state.lastSessionManifest
    if not target and state.stream then
        close_active_stream(state, "EXPORT_SNAPSHOT")
        target = state.lastSessionManifest
        if state.mode == "LOGGING" then open_active_stream(state) end
    end
    if not target then
        state.lastExportResult = "NO_SESSION_TO_EXPORT"
        return false
    end
    local a = state.apis or {}
    local ok, res = cloud_exporter.upload_session(target, state.cfg.export, a.http, a.fs)
    if ok then
        state.lastExportResult = string.format("OK %dF/%dC", res.uploadedFiles or 0, res.uploadedChunks or 0)
    else
        state.lastExportResult = "ERR: " .. tostring(res and res.err or "FAIL")
    end
    return ok
end

function main.shutdown(state, reason)
    if not state.running then return end
    close_active_stream(state, reason or "SHUTDOWN")
    packet_tap.close_channels(state.tap)
    state.running = false
    state.lastEventMsg = reason or "SHUTDOWN"
end

local function key_code(name, fallback)
    return (keys and keys[name]) or fallback
end

local function handle_key(state, code)
    state.uiDirty = true
    if code == key_code("q", 16) then main.shutdown(state, "USER_QUIT")
    elseif code == key_code("p", 25) then
        state.mode = (state.mode == "LOGGING") and "PAUSED" or "LOGGING"
        if state.mode == "LOGGING" and not state.stream then open_active_stream(state) end
    elseif code == key_code("d", 32) then trigger_manual_dump(state)
    elseif code == key_code("s", 31) and state.stream then
        jsonl_dumper.rollover_stream(state.stream, "MANUAL_SPLIT", now_ms(state.apis), state.apis)
    elseif code == key_code("u", 22) then trigger_export(state)
    elseif code == key_code("c", 46) then
        ring_buffer.clear(state.ring)
        state.tap.countsByOffset = { [1] = 0, [2] = 0, [4] = 0, [10] = 0, [11] = 0 }
        state.estopFlushed = false
        state.lastEventMsg = "CLEARED"
    elseif code == key_code("n", 49) and state.apis and state.apis.promptAircraftN then
        local nVal = tonumber(state.apis.promptAircraftN())
        if nVal then main.switch_aircraft(state, nVal, "*") end
    end
end

function main.handle_event(state, ev, p1, p2, p3, p4)
    if ev == "modem_message" then
        return handle_modem_frame(state, p2, p4)
    elseif ev == "disk" or ev == "disk_eject" then
        refresh_volumes(state)
        if state.mode == "DISK_FULL" and storage_pool.select_best_volume(state.volumes, state.cfg) then
            state.mode = "LOGGING"
            open_active_stream(state)
        end
        state.uiDirty = true
        return true
    elseif ev == "key" then
        handle_key(state, p1)
        return true
    elseif ev == "terminate" then
        main.shutdown(state, "TERMINATE")
        return true
    end
    return false
end

function main.render_ui(state, termObj)
    local t = termObj or (state.apis and state.apis.term) or _G.term
    if not t then return false end
    local a = state.apis or {}
    local activeVol = state.stream and state.stream.activeVolume or state.volumes[1]
    local uiState = {
        mode = state.mode,
        aircraftIndexN = state.tap.aircraftIndexN,
        baseChannel = state.tap.baseChannel,
        domainId = state.tap.lockedDomainId,
        partIndex = state.stream and state.stream.partIndex or 1,
        activeMount = activeVol and activeVol.mountPath or "NONE",
        activeFreeKB = (activeVol and activeVol.freeBytes or 0) / 1024,
        poolFreeKB = storage_pool.get_pool_free_bytes(state.volumes) / 1024,
        framesWritten = state.framesWritten,
        exportStatus = state.lastExportResult,
        countsByOffset = state.tap.countsByOffset,
        lastEventMsg = state.lastEventMsg,
    }
    state.uiDirty = false
    return fdr_ui.render(t, uiState)
end

function main.run(cfgOrPath, apis)
    local a = apis or {}
    if not a.promptAircraftN and _G.read and _G.term then
        a.promptAircraftN = function()
            term.setCursorPos(1, 15)
            term.write("NEW N (1-1000): ")
            return read()
        end
    end
    local state = main.init(cfgOrPath, a)
    main.render_ui(state, a.term)
    local uiTimer = os.startTimer and os.startTimer(0.5) or nil
    while state.running do
        local ev, p1, p2, p3, p4 = os.pullEventRaw()
        if ev == "timer" and p1 == uiTimer then
            main.render_ui(state, a.term)
            uiTimer = os.startTimer(0.5)
        else
            main.handle_event(state, ev, p1, p2, p3, p4)
            if state.uiDirty then main.render_ui(state, a.term) end
        end
    end
    return state
end

if _G.describe == nil and not _G.__HARNESS_HIL_MODE then
    main.run()
end

return main
