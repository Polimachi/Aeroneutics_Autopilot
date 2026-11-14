-- Multi-Disk Spanned VFS manager across wired/adjacent CraftOS drive peripherals and local /logs.
local storage_pool = {}

local function normalize_apis(peripheralApi, diskApi, fsApi)
    return peripheralApi or _G.peripheral, diskApi or _G.disk, fsApi or _G.fs
end

local function make_part_dir(volume, cfg)
    local sub = (cfg and cfg.storage and cfg.storage.diskSubDir) or "fdr_logs"
    if volume.isLocal then
        return volume.mountPath
    end
    if volume.mountPath == "/" then
        return "/" .. sub
    end
    return volume.mountPath .. "/" .. sub
end

function storage_pool.ensure_dir(path, fsApi)
    if not fsApi or not path or path == "/" then return true end
    if fsApi.exists(path) then return fsApi.isDir(path) end
    if fsApi.makeDir then fsApi.makeDir(path) end
    return true
end

function storage_pool.part_dir(volume, cfg)
    return make_part_dir(volume, cfg)
end

--- Build deterministic part path for a volume.
function storage_pool.build_part_path(volume, cfg, domainId, sessionEpochMs, partIdx)
    local dir = make_part_dir(volume, cfg)
    local cleanDomain = tostring(domainId or "UNKNOWN"):gsub("[^%w_%-]", "_")
    local fileName = string.format("%s_%d_part%03d.jsonl", cleanDomain, math.floor(sessionEpochMs or 0), partIdx)
    return dir .. "/" .. fileName, dir
end

--- Scan attached data drives and optional local fallback directory.
function storage_pool.scan_volumes(cfg, peripheralApi, diskApi, fsApi)
    local pApi, dApi, fApi = normalize_apis(peripheralApi, diskApi, fsApi)
    local st = (cfg and cfg.storage) or {}
    local volumes = {}

    if pApi and dApi and pApi.getNames then
        for _, name in ipairs(pApi.getNames()) do
            if pApi.getType(name) == "drive" and dApi.isPresent(name) and dApi.hasData(name) then
                local mPath = dApi.getMountPath(name)
                if type(mPath) == "string" and mPath ~= "" then
                    local normMount = (string.sub(mPath, 1, 1) == "/") and mPath or ("/" .. mPath)
                    local free = (fApi and fApi.getFreeSpace and fApi.getFreeSpace(normMount)) or 0
                    table.insert(volumes, {
                        peripheralName = name,
                        mountPath = normMount,
                        freeBytes = free,
                        isLocal = false,
                    })
                end
            end
        end
    end

    if st.allowLocalFallback ~= false then
        local localDir = st.localDumpDir or "/logs"
        local localFree = (fApi and fApi.getFreeSpace and fApi.getFreeSpace(localDir)) or 0
        table.insert(volumes, {
            peripheralName = "local",
            mountPath = localDir,
            freeBytes = localFree,
            isLocal = true,
        })
    end
    return volumes
end

local function pick_max_free(volumes, wantLocal, minBytes)
    local best = nil
    for _, v in ipairs(volumes) do
        if (v.isLocal == wantLocal) and v.freeBytes >= minBytes then
            if not best or v.freeBytes > best.freeBytes then
                best = v
            end
        end
    end
    return best
end

--- Pick best writable volume respecting preferExternalDisk and minFreeSpaceBytes.
function storage_pool.select_best_volume(volumes, cfg, minOverride)
    local st = (cfg and cfg.storage) or {}
    local minBytes = minOverride or st.minFreeSpaceBytes or 16384
    if st.preferExternalDisk ~= false then
        local ext = pick_max_free(volumes, false, minBytes)
        if ext then return ext end
        return pick_max_free(volumes, true, minBytes)
    end
    local best = nil
    for _, v in ipairs(volumes) do
        if v.freeBytes >= minBytes and (not best or v.freeBytes > best.freeBytes) then
            best = v
        end
    end
    return best
end

function storage_pool.get_pool_free_bytes(volumes)
    local total = 0
    for _, v in ipairs(volumes or {}) do
        total = total + (v.freeBytes or 0)
    end
    return total
end

local function collect_session_files(volumes, cfg, activeSessionId, fsApi)
    local sessions, order = {}, {}
    for _, vol in ipairs(volumes) do
        local dir = make_part_dir(vol, cfg)
        if fsApi.exists(dir) and fsApi.isDir(dir) then
            for _, fname in ipairs(fsApi.list(dir) or {}) do
                local sid, epoch = string.match(fname, "^(.+_(%d+))_part%d+%.jsonl$")
                if sid and sid ~= activeSessionId then
                    if not sessions[sid] then
                        sessions[sid] = { sid = sid, epoch = tonumber(epoch) or 0, files = {} }
                        table.insert(order, sessions[sid])
                    end
                    table.insert(sessions[sid].files, dir .. "/" .. fname)
                end
            end
        end
    end
    table.sort(order, function(a, b) return a.epoch < b.epoch end)
    return order
end

--- Delete oldest inactive session parts when maxTotalSessions is exceeded.
function storage_pool.prune_oldest_sessions(volumes, cfg, activeSessionId, fsApi)
    local _, _, fApi = normalize_apis(nil, nil, fsApi)
    if not fApi then return 0 end
    local st = (cfg and cfg.storage) or {}
    local maxSessions = st.maxTotalSessions or 10
    local reserveSlot = activeSessionId and 1 or 0
    local allowedOld = math.max(0, maxSessions - reserveSlot)
    local groups = collect_session_files(volumes, cfg, activeSessionId, fApi)
    local deletedCount = 0

    while #groups > allowedOld do
        local oldest = table.remove(groups, 1)
        for _, path in ipairs(oldest.files) do
            fApi.delete(path)
            deletedCount = deletedCount + 1
        end
    end
    return deletedCount
end

--- Persist session manifest JSON listing parts across disks.
function storage_pool.write_session_manifest(manifestPath, sessionMeta, fsApi)
    local _, _, fApi = normalize_apis(nil, nil, fsApi)
    if not fApi then return false, "ERR_NO_FS" end
    local parent = string.match(manifestPath, "^(.*)/[^/]+$")
    if parent and parent ~= "" then
        storage_pool.ensure_dir(parent, fApi)
    end
    local fh = fApi.open(manifestPath, "w")
    if not fh then return false, "ERR_MANIFEST_OPEN" end
    local payload = textutils.serialiseJSON(sessionMeta)
    if fh.write then
        fh.write(payload)
    else
        fh.writeLine(payload)
    end
    fh.close()
    return true, nil
end

return storage_pool
