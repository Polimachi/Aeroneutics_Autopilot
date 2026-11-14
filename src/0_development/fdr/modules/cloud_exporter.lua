-- External HTTP log/manifest exporter (GDRIVE_WEBHOOK / HTTP_POST). Zero modem calls.
local cloud_exporter = {}

local DEFAULT_MAX_CHUNK_BYTES = 90000

local function post_chunk(httpApi, url, bodyStr, headers)
    local res, err = httpApi.post(url, bodyStr, headers)
    if not res then
        return false, tostring(err or "ERR_HTTP_POST")
    end
    if res.close then res.close() end
    return true, nil
end

local function extract_basename(path)
    return string.match(tostring(path or "file.jsonl"), "([^/]+)$") or "file.jsonl"
end

local function upload_single_file(filePath, partIndex, manifest, exportCfg, httpApi, fsApi)
    if not fsApi.exists(filePath) then
        return false, 0, "ERR_FILE_MISSING"
    end
    local fh = fsApi.open(filePath, "r")
    if not fh then return false, 0, "ERR_FILE_OPEN" end
    local content = fh.readAll() or ""
    fh.close()

    local maxChunk = exportCfg.maxChunkBytes or DEFAULT_MAX_CHUNK_BYTES
    local len = math.max(1, #content)
    local totalChunks = math.max(1, math.ceil(len / maxChunk))
    local headers = { ["Content-Type"] = "application/json" }
    local fName = extract_basename(filePath)

    for c = 1, totalChunks do
        local sIdx = (c - 1) * maxChunk + 1
        local eIdx = math.min(#content, c * maxChunk)
        local slice = (#content == 0) and "" or string.sub(content, sIdx, eIdx)
        local payload = textutils.serialiseJSON({
            authToken = exportCfg.authToken or "",
            gdriveFolderId = exportCfg.gdriveFolderId or "1C3ZWMoXjsba1QE8ksgWG0LSfxzW_nMWI",
            gdriveFolderName = exportCfg.gdriveFolderName or "FDR_Reports",
            sessionId = manifest.sessionId or "UNKNOWN",
            partIndex = partIndex or 0,
            fileName = fName,
            chunkIndex = c,
            totalChunks = totalChunks,
            content = slice,
        })
        local ok, err = post_chunk(httpApi, exportCfg.webhookUrl, payload, headers)
        if not ok then
            return false, c - 1, err
        end
    end
    return true, totalChunks, nil
end

--- Upload every part and optional session manifest via http.post without altering local files.
function cloud_exporter.upload_session(sessionManifest, exportCfg, httpApi, fsApi)
    local cfg = exportCfg or {}
    local mode = cfg.mode or "GDRIVE_WEBHOOK"
    if mode == "NONE" then
        return false, { err = "ERR_EXPORT_DISABLED" }
    end
    if type(cfg.webhookUrl) ~= "string" or cfg.webhookUrl == "" then
        return false, { err = "ERR_MISSING_WEBHOOK_URL" }
    end
    local hApi = httpApi or _G.http
    local fApi = fsApi or _G.fs
    if not hApi or not hApi.post then
        return false, { err = "ERR_HTTP_UNAVAILABLE" }
    end

    local targets = {}
    for _, part in ipairs((sessionManifest and sessionManifest.parts) or {}) do
        table.insert(targets, { path = part.filePath, partIndex = part.partIndex })
    end
    if sessionManifest and sessionManifest.manifestPath and fApi.exists(sessionManifest.manifestPath) then
        table.insert(targets, { path = sessionManifest.manifestPath, partIndex = 0 })
    end

    local uploadedFiles, uploadedChunks = 0, 0
    for _, item in ipairs(targets) do
        local ok, chunks, err = upload_single_file(item.path, item.partIndex, sessionManifest, cfg, hApi, fApi)
        if not ok then
            return false, { err = err, uploadedFiles = uploadedFiles, uploadedChunks = uploadedChunks }
        end
        uploadedFiles = uploadedFiles + 1
        uploadedChunks = uploadedChunks + chunks
    end
    return true, { uploadedFiles = uploadedFiles, uploadedChunks = uploadedChunks }
end

return cloud_exporter
