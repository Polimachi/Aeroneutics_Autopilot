-- src/0_development/installer/modules/downloader.lua
-- Atomic HTTP Downloader with Dual-Source redirects, HTML interstitial rejection, and staged batch commit

local downloader = {}

downloader.MAX_REDIRECTS = 5

--- Resolves a relative or absolute path against a target root directory cleanly.
-- @param targetRoot string|nil Target root directory (defaults to "/")
-- @param relOrAbsPath string|nil Path to resolve
-- @return string Resolved path
local function resolveTargetPath(targetRoot, relOrAbsPath)
    local root = targetRoot or "/"
    root = root:gsub("\\", "/")
    local p = (relOrAbsPath or ""):gsub("\\", "/")

    while #root > 1 and root:sub(-1) == "/" do
        root = root:sub(1, -2)
    end
    if root == "" then
        root = "/"
    end

    if p == "" or p == "/" then
        return root
    end

    if root == "/" then
        if p:sub(1, 1) == "/" then
            return p
        else
            return "/" .. p
        end
    end

    if p == root then
        return p
    end
    if p:sub(1, #root + 1) == root .. "/" then
        return p
    end

    if p:sub(1, 1) == "/" then
        return root .. p
    else
        return root .. "/" .. p
    end
end

--- Checks if HTTP API is present and has required methods.
-- @param ... Injected HTTP table or none (defaults to _G.http when 0 arguments passed)
-- @return boolean isAvailable
-- @return string|nil errorMessage ("HTTP_DISABLED" if unavailable)
function downloader.checkHttpAvailable(...)
    local h
    if select("#", ...) == 0 then
        h = _G.http
    else
        h = select(1, ...)
    end
    if type(h) ~= "table" or type(h.get) ~= "function" then
        return false, "HTTP_DISABLED"
    end
    return true, nil
end

--- Fetches a remote URL as a string with redirect following and Google Drive interstitial handling.
-- @param url string Target URL
-- @param opts table|nil Options table { http, headers, binary, maxRedirects }
-- @return string|nil responseBody
-- @return string|nil errorMessage
function downloader.fetchString(url, opts)
    opts = opts or {}
    local httpObj
    if opts.http ~= nil then
        httpObj = opts.http
    else
        httpObj = _G.http
    end

    local okHttp, httpErr = downloader.checkHttpAvailable(httpObj)
    if not okHttp then
        return nil, httpErr
    end

    if type(url) ~= "string" or url == "" then
        return nil, "INVALID_URL"
    end

    local maxRedirects = tonumber(opts.maxRedirects) or downloader.MAX_REDIRECTS
    local currentUrl = url
    local hops = 0
    local retriedGDrive = false

    while true do
        local resp, getErr = httpObj.get(currentUrl, opts.headers, opts.binary)
        if not resp then
            return nil, getErr or "HTTP_REQUEST_FAILED"
        end

        local code = 200
        if type(resp.getResponseCode) == "function" then
            code = resp.getResponseCode() or 200
        end

        -- Check for 3xx redirect status codes
        if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
            hops = hops + 1
            if hops > maxRedirects then
                if type(resp.close) == "function" then
                    resp.close()
                end
                return nil, "TOO_MANY_REDIRECTS"
            end

            local headers = {}
            if type(resp.getResponseHeaders) == "function" then
                headers = resp.getResponseHeaders() or {}
            end

            local loc = headers["Location"] or headers["location"]
            if not loc then
                for k, v in pairs(headers) do
                    if string.lower(k) == "location" then
                        loc = v
                        break
                    end
                end
            end

            if type(resp.close) == "function" then
                resp.close()
            end

            if not loc or loc == "" then
                return nil, "REDIRECT_WITHOUT_LOCATION"
            end

            currentUrl = loc
        elseif code >= 400 then
            if type(resp.close) == "function" then
                resp.close()
            end
            return nil, "HTTP_ERROR_" .. tostring(code)
        else
            -- 2xx Success (or other non-redirect)
            local body = ""
            if type(resp.readAll) == "function" then
                body = resp.readAll() or ""
            end
            if type(resp.close) == "function" then
                resp.close()
            end

            -- Check for Google Drive HTML interstitial
            local isGDrive = (currentUrl:find("drive%.google%.com")
                or currentUrl:find("googleusercontent%.com")
                or currentUrl:find("drive%.")
                or currentUrl:find("googleusercontent"))

            if isGDrive then
                local trimmed = string.match(body, "^%s*(.-)%s*$") or ""
                local lowerTrimmed = string.lower(trimmed)
                if lowerTrimmed:sub(1, 14) == "<!doctype html" or lowerTrimmed:sub(1, 5) == "<html" then
                    -- Check if confirm / uuid can be extracted and retried once
                    if not retriedGDrive then
                        local confirmVal = body:match('name="confirm"%s+value="([^"]+)"')
                            or body:match('confirm=([%w_%-]+)')
                        local uuidVal = body:match('name="uuid"%s+value="([^"]+)"')
                            or body:match('uuid=([%w_%-]+)')

                        if confirmVal then
                            retriedGDrive = true
                            local retryUrl = currentUrl
                            if not retryUrl:find("confirm=") then
                                retryUrl = retryUrl .. "&confirm=" .. confirmVal
                            end
                            if uuidVal and not retryUrl:find("uuid=") then
                                retryUrl = retryUrl .. "&uuid=" .. uuidVal
                            end
                            currentUrl = retryUrl
                        else
                            return nil, "GDRIVE_HTML_INTERSTITIAL"
                        end
                    else
                        return nil, "GDRIVE_HTML_INTERSTITIAL"
                    end
                else
                    return body, nil
                end
            else
                return body, nil
            end
        end
    end
end

--- Downloads a single file atomically by writing to <destPath>.tmp and renaming upon completion.
-- @param url string Remote file URL
-- @param destPath string Destination file path
-- @param opts table|nil Options table { http, fs, headers, binary, maxRedirects }
-- @return boolean success
-- @return string|nil errorMessage
function downloader.downloadFileAtomic(url, destPath, opts)
    opts = opts or {}
    local fsObj = opts.fs or _G.fs
    if not fsObj then
        return false, "FS_DISABLED"
    end

    if type(destPath) ~= "string" or destPath == "" then
        return false, "INVALID_DEST_PATH"
    end

    local tmpPath = destPath .. ".tmp"

    -- Ensure parent directory exists
    local parent = fsObj.getDir(destPath)
    if parent and parent ~= "" and not fsObj.exists(parent) then
        local okMkdir, errMkdir = pcall(fsObj.makeDir, parent)
        if not okMkdir then
            return false, "FAILED_TO_CREATE_DIR: " .. tostring(errMkdir)
        end
    end

    -- Clean stale .tmp file if present
    if fsObj.exists(tmpPath) then
        pcall(fsObj.delete, tmpPath)
    end

    local content, fetchErr = downloader.fetchString(url, opts)
    if not content then
        if fsObj.exists(tmpPath) then
            pcall(fsObj.delete, tmpPath)
        end
        return false, fetchErr
    end

    local h = fsObj.open(tmpPath, "w")
    if not h then
        return false, "FAILED_TO_OPEN_TMP: " .. tmpPath
    end
    h.write(content)
    h.close()

    if fsObj.exists(destPath) then
        local okDel, errDel = pcall(fsObj.delete, destPath)
        if not okDel then
            if fsObj.exists(tmpPath) then
                pcall(fsObj.delete, tmpPath)
            end
            return false, "FAILED_TO_REMOVE_EXISTING: " .. tostring(errDel)
        end
    end

    local okMove, errMove = pcall(fsObj.move, tmpPath, destPath)
    if not okMove then
        if fsObj.exists(tmpPath) then
            pcall(fsObj.delete, tmpPath)
        end
        return false, "FAILED_TO_COMMIT: " .. tostring(errMove)
    end

    return true, nil
end

--- Downloads a batch of files into a staged directory and atomically commits them all.
-- Rolls back staging directory completely on any failure before touching live destinations.
-- @param sourceType string Source type ("github" or "gdrive")
-- @param fileEntries table List of file definitions { repoPath, dest, gdriveId }
-- @param opts table|nil Options table { targetRoot, manifest, gdriveOverrides, onProgress, http, fs }
-- @return boolean success
-- @return table|nil installedDestList List of installed dest paths
-- @return string|nil errorMessage
function downloader.downloadBatch(sourceType, fileEntries, opts)
    opts = opts or {}
    local fsObj = opts.fs or _G.fs
    if not fsObj then
        return false, nil, "FS_DISABLED"
    end

    if type(fileEntries) ~= "table" then
        return false, nil, "INVALID_FILE_ENTRIES"
    end

    local manifestModule = opts.manifest
    if not manifestModule then
        local okReq, mod = pcall(require, "manifest")
        if okReq then
            manifestModule = mod
        else
            return false, nil, "MANIFEST_NOT_FOUND"
        end
    end

    -- 1. Upfront URL resolution before touching disk or network
    local resolvedUrls = {}
    for i, entry in ipairs(fileEntries) do
        local url, err = manifestModule.resolveUrl(sourceType, entry, opts.gdriveOverrides)
        if not url then
            return false, nil, err or "URL_RESOLUTION_FAILED"
        end
        resolvedUrls[i] = url
    end

    local targetRoot = opts.targetRoot or "/"
    local stageRoot = resolveTargetPath(targetRoot, ".installer_stage")

    -- Clean any existing staging directory
    if fsObj.exists(stageRoot) then
        pcall(fsObj.delete, stageRoot)
    end

    -- 2. Staged downloads into stageRoot
    for idx, entry in ipairs(fileEntries) do
        if type(opts.onProgress) == "function" then
            opts.onProgress(idx, #fileEntries, entry.dest)
        end

        local stagedDest = resolveTargetPath(stageRoot, entry.dest)
        local okDl, dlErr = downloader.downloadFileAtomic(resolvedUrls[idx], stagedDest, opts)
        if not okDl then
            if fsObj.exists(stageRoot) then
                pcall(fsObj.delete, stageRoot)
            end
            return false, nil, dlErr
        end
    end

    -- 3. Atomically commit each file from stage to live target destination
    local installedDestList = {}
    for idx, entry in ipairs(fileEntries) do
        local stagedDest = resolveTargetPath(stageRoot, entry.dest)
        local finalDest = resolveTargetPath(targetRoot, entry.dest)

        local parent = fsObj.getDir(finalDest)
        if parent and parent ~= "" and not fsObj.exists(parent) then
            local okMkdir, errMkdir = pcall(fsObj.makeDir, parent)
            if not okMkdir then
                if fsObj.exists(stageRoot) then
                    pcall(fsObj.delete, stageRoot)
                end
                return false, nil, "FAILED_TO_CREATE_DIR: " .. tostring(errMkdir)
            end
        end

        if fsObj.exists(finalDest) then
            local okDel, errDel = pcall(fsObj.delete, finalDest)
            if not okDel then
                if fsObj.exists(stageRoot) then
                    pcall(fsObj.delete, stageRoot)
                end
                return false, nil, "FAILED_TO_REMOVE_EXISTING: " .. tostring(errDel)
            end
        end

        local okMove, errMove = pcall(fsObj.move, stagedDest, finalDest)
        if not okMove then
            if fsObj.exists(stageRoot) then
                pcall(fsObj.delete, stageRoot)
            end
            return false, nil, "FAILED_TO_COMMIT: " .. tostring(errMove)
        end

        table.insert(installedDestList, entry.dest)
    end

    -- 4. Clean up staging directory after commit
    if fsObj.exists(stageRoot) then
        pcall(fsObj.delete, stageRoot)
    end

    return true, installedDestList, nil
end

return downloader
