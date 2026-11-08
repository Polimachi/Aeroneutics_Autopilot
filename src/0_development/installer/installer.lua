-- src/0_development/installer/installer.lua
-- Self-contained 3-Mode Root Bootstrapper for Create_Aeroneutics Unified Installer

local bootstrapper = {}

bootstrapper.VERSION = "1.0.0"
bootstrapper.DEFAULT_GITHUB_BASE = "https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/"
bootstrapper.DEFAULT_GDRIVE_BASE = "https://drive.usercontent.google.com/download?id="

bootstrapper.BOOTSTRAP_FILES = {
    { repoPath = "src/0_development/installer/installer_app.lua", cacheRelPath = "installer_app.lua", gdriveId = nil },
    { repoPath = "src/0_development/installer/modules/manifest.lua", cacheRelPath = "modules/manifest.lua", gdriveId = nil },
    { repoPath = "src/0_development/installer/modules/version_registry.lua", cacheRelPath = "modules/version_registry.lua", gdriveId = nil },
    { repoPath = "src/0_development/installer/modules/migration_engine.lua", cacheRelPath = "modules/migration_engine.lua", gdriveId = nil },
    { repoPath = "src/0_development/installer/modules/startup_generator.lua", cacheRelPath = "modules/startup_generator.lua", gdriveId = nil },
    { repoPath = "src/0_development/installer/modules/downloader.lua", cacheRelPath = "modules/downloader.lua", gdriveId = nil },
    { repoPath = "src/0_development/installer/modules/tui_view.lua", cacheRelPath = "modules/tui_view.lua", gdriveId = nil },
}

--- Detects the runtime execution context from program invocation path.
-- @param runningProgram string|nil Invocation path (e.g. from shell.getRunningProgram())
-- @param fsApi table|nil Filesystem API (defaults to _G.fs)
-- @return table { mode, runningPath, scriptDir, targetRoot, preserveSelf }
function bootstrapper.detectContext(runningProgram, fsApi)
    local fsObj = fsApi or _G.fs
    local prog = runningProgram
    if not prog or prog == "" then
        if shell and shell.getRunningProgram then
            prog = shell.getRunningProgram()
        else
            prog = "/installer.lua"
        end
    end
    prog = tostring(prog):gsub("\\", "/")

    local scriptDir = ""
    if fsObj and fsObj.getDir then
        scriptDir = fsObj.getDir(prog) or ""
    else
        scriptDir = prog:match("^(.-)/[^/]+$") or ""
    end

    local mode
    local targetRoot = "/"
    local preserveSelf = true

    if prog:find("wget") or prog:find("_tmp_wget") or prog == "/rom/programs/http/wget.lua" then
        mode = "remote_wget"
        targetRoot = "/"
        preserveSelf = false
    elseif prog:match("^/?disk") then
        mode = "disk"
        targetRoot = "/"
        preserveSelf = true
    else
        mode = "direct_root"
        targetRoot = "/"
        preserveSelf = true
    end

    return {
        mode = mode,
        runningPath = prog,
        scriptDir = scriptDir,
        targetRoot = targetRoot,
        preserveSelf = preserveSelf,
    }
end

--- Resolves local core directory containing installer_app.lua and modules if available on disk.
-- @param ctx table Context table from detectContext
-- @param fsApi table|nil Filesystem API (defaults to _G.fs)
-- @return string|nil Resolved local directory or nil
function bootstrapper.resolveLocalCoreDir(ctx, fsApi)
    local fsObj = fsApi or _G.fs
    if not fsObj then return nil end

    if ctx and ctx.mode == "remote_wget" then
        return nil
    end

    local candidates = {}
    local sDir = (ctx and ctx.scriptDir) or ""
    sDir = sDir:gsub("\\", "/")
    while #sDir > 1 and sDir:sub(-1) == "/" do
        sDir = sDir:sub(1, -2)
    end

    if sDir ~= "" and sDir ~= "/" then
        table.insert(candidates, sDir .. "/src/0_development/installer")
        table.insert(candidates, sDir)
    else
        table.insert(candidates, "src/0_development/installer")
        table.insert(candidates, "/src/0_development/installer")
        table.insert(candidates, "")
        table.insert(candidates, "/")
    end

    for _, dir in ipairs(candidates) do
        local appPath
        local manPath1
        local manPath2
        if dir == "" or dir == "/" then
            appPath = "installer_app.lua"
            manPath1 = "modules/manifest.lua"
            manPath2 = "manifest.lua"
        else
            appPath = dir .. "/installer_app.lua"
            manPath1 = dir .. "/modules/manifest.lua"
            manPath2 = dir .. "/manifest.lua"
        end

        if fsObj.exists(appPath) and (fsObj.exists(manPath1) or fsObj.exists(manPath2)) then
            return dir
        end
    end

    return nil
end

--- Downloads minimal bootstrap files into cache directory via HTTP.
-- @param cacheDir string Local cache destination directory
-- @param source string "github" or "gdrive"
-- @param opts table Options { fs, http, baseUrl, gdriveOverrides, maxRedirects }
-- @return boolean success
-- @return string|nil errorMessage
local function downloadBootstrapFiles(cacheDir, source, opts)
    local fsObj = opts.fs
    local httpObj = opts.http
    local baseUrl = opts.baseUrl or bootstrapper.DEFAULT_GITHUB_BASE
    local gdriveOverrides = opts.gdriveOverrides
    local maxRedirects = opts.maxRedirects or 5

    for _, file in ipairs(bootstrapper.BOOTSTRAP_FILES) do
        local url
        if source == "github" then
            url = baseUrl .. file.repoPath
        elseif source == "gdrive" then
            local fileId = (gdriveOverrides and gdriveOverrides[file.repoPath]) or file.gdriveId
            if not fileId or fileId == "" then
                return false, "GDRIVE_ID_UNCONFIGURED: " .. tostring(file.repoPath)
            end
            url = bootstrapper.DEFAULT_GDRIVE_BASE .. fileId .. "&export=download&confirm=t"
        else
            return false, "UNKNOWN_SOURCE: " .. tostring(source)
        end

        local curUrl = url
        local hops = 0
        local body = nil
        local fetchErr = nil

        while true do
            local resp, getErr = httpObj.get(curUrl)
            if not resp then
                fetchErr = getErr or ("HTTP_REQUEST_FAILED: " .. tostring(curUrl))
                break
            end

            local code = 200
            if type(resp.getResponseCode) == "function" then
                code = resp.getResponseCode() or 200
            end

            if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
                hops = hops + 1
                if hops > maxRedirects then
                    if type(resp.close) == "function" then resp.close() end
                    fetchErr = "TOO_MANY_REDIRECTS"
                    break
                end

                local headers = (type(resp.getResponseHeaders) == "function" and resp.getResponseHeaders()) or {}
                local loc = headers["Location"] or headers["location"]
                if not loc then
                    for k, v in pairs(headers) do
                        if string.lower(k) == "location" then loc = v; break end
                    end
                end

                if type(resp.close) == "function" then resp.close() end
                if not loc or loc == "" then
                    fetchErr = "REDIRECT_WITHOUT_LOCATION"
                    break
                end
                curUrl = loc
            elseif code >= 400 then
                if type(resp.close) == "function" then resp.close() end
                fetchErr = "HTTP_ERROR_" .. tostring(code)
                break
            else
                if type(resp.readAll) == "function" then
                    body = resp.readAll() or ""
                else
                    body = ""
                end
                if type(resp.close) == "function" then resp.close() end
                break
            end
        end

        if not body then
            return false, fetchErr or "HTTP_FETCH_FAILED"
        end

        local destPath = cacheDir .. "/" .. file.cacheRelPath
        local dir = fsObj.getDir(destPath)
        if dir and dir ~= "" and not fsObj.exists(dir) then
            fsObj.makeDir(dir)
        end
        local h = fsObj.open(destPath, "w")
        if not h then
            return false, "CANNOT_WRITE_CACHE_FILE: " .. tostring(destPath)
        end
        h.write(body)
        h.close()
    end

    return true, nil
end

--- Bootstraps dependencies if needed and runs the installer application.
-- @param opts table|nil Execution options
-- @return boolean success
-- @return string|nil errorMessage
function bootstrapper.bootstrapAndRun(opts)
    opts = opts or {}
    local fsObj = opts.fs or _G.fs
    if not fsObj then
        return false, "FS_DISABLED"
    end

    -- 1. Detect runtime execution context
    local prog = opts.runningProgram
    if not prog or prog == "" then
        local shellObj = opts.shell or _G.shell
        if shellObj and shellObj.getRunningProgram then
            prog = shellObj.getRunningProgram()
        else
            prog = "/installer.lua"
        end
    end
    local ctx = bootstrapper.detectContext(prog, fsObj)

    local targetRoot = opts.targetRoot or ctx.targetRoot or "/"

    -- Parse CLI flags
    local source = opts.source or "github"
    local gdriveMapPath = opts.bootstrapGdriveMap
    local gdriveOverrides = opts.gdriveOverrides

    if opts.cliArgs then
        for i = 1, #opts.cliArgs do
            local arg = opts.cliArgs[i]
            if arg == "--source" or arg == "-s" then
                if opts.cliArgs[i + 1] then
                    source = tostring(opts.cliArgs[i + 1]):lower()
                end
            elseif arg == "--bootstrap-gdrive-map" then
                if opts.cliArgs[i + 1] then
                    gdriveMapPath = opts.cliArgs[i + 1]
                end
            end
        end
    end

    if gdriveMapPath and fsObj.exists(gdriveMapPath) then
        local h = fsObj.open(gdriveMapPath, "r")
        if h then
            local raw = h.readAll()
            h.close()
            if raw and textutils and textutils.unserializeJSON then
                local map = textutils.unserializeJSON(raw)
                if type(map) == "table" then
                    gdriveOverrides = gdriveOverrides or {}
                    for k, v in pairs(map) do
                        gdriveOverrides[k] = v
                    end
                end
            end
        end
    end

    -- 2. Resolve local core directory or determine if HTTP bootstrap needed
    local localCoreDir
    if opts.localCoreDir == false then
        localCoreDir = nil
    elseif opts.localCoreDir ~= nil then
        localCoreDir = opts.localCoreDir
    else
        localCoreDir = bootstrapper.resolveLocalCoreDir(ctx, fsObj)
    end

    local cacheDir = nil

    if not localCoreDir then
        -- HTTP Bootstrap required
        local httpObj = opts.http or _G.http
        if type(httpObj) ~= "table" or type(httpObj.get) ~= "function" then
            return false, "HTTP_DISABLED"
        end

        if targetRoot == "/" then
            cacheDir = "/.installer_cache"
        elseif targetRoot:sub(-1) == "/" then
            cacheDir = targetRoot .. ".installer_cache"
        else
            cacheDir = targetRoot .. "/.installer_cache"
        end

        if not fsObj.exists(cacheDir) then
            fsObj.makeDir(cacheDir)
        end

        local baseUrl = opts.baseUrl or bootstrapper.DEFAULT_GITHUB_BASE
        local okDl, dlErr = downloadBootstrapFiles(cacheDir, source, {
            http = httpObj,
            fs = fsObj,
            baseUrl = baseUrl,
            gdriveOverrides = gdriveOverrides,
            maxRedirects = opts.maxRedirects,
        })

        if not okDl then
            if fsObj.exists(cacheDir) then
                pcall(fsObj.delete, cacheDir)
            end
            return false, dlErr
        end
    end

    -- 3. Setup package.path for loading installer_app and modules
    local oldPath = package.path or ""
    local coreBase = localCoreDir or cacheDir
    local addPath = ""
    if coreBase == "" or coreBase == "/" then
        addPath = "?.lua;modules/?.lua;/?.lua;/modules/?.lua;"
    else
        addPath = coreBase .. "/?.lua;" .. coreBase .. "/modules/?.lua;"
    end
    package.path = addPath .. oldPath

    -- 4. Execute application
    local appOpts = {
        targetRoot = targetRoot,
        cliArgs = opts.cliArgs,
        source = source,
        gdriveOverrides = gdriveOverrides,
        http = opts.http or _G.http,
        fs = fsObj,
        term = opts.term or _G.term,
        pullEvent = opts.pullEvent or (os and os.pullEvent),
    }

    local ok, appOk, appErr
    if type(opts.appRunner) == "function" then
        ok, appOk, appErr = pcall(opts.appRunner, appOpts)
    else
        local okReq, appMod = pcall(require, "installer_app")
        if not okReq or type(appMod) ~= "table" or type(appMod.run) ~= "function" then
            ok = false
            appErr = "CANNOT_LOAD_INSTALLER_APP: " .. tostring(appMod)
        else
            ok, appOk, appErr = pcall(appMod.run, appOpts)
        end
    end

    -- 5. Cleanup
    package.path = oldPath

    if cacheDir and fsObj.exists(cacheDir) then
        pcall(fsObj.delete, cacheDir)
    end

    if not ctx.preserveSelf and ctx.runningPath and ctx.runningPath ~= "" then
        if fsObj.exists(ctx.runningPath) and not (fsObj.isReadOnly and fsObj.isReadOnly(ctx.runningPath)) then
            pcall(fsObj.delete, ctx.runningPath)
        end
    end

    if not ok then
        return false, appErr or appOk or "UNKNOWN_ERROR"
    end

    return appOk, appErr
end

-- Top-level auto-execution guard
local _boot_args = { ... }
local _first = tostring(_boot_args[1] or "")
local _is_module_require = (_first == "installer" or _first:match("[%.%/]installer$") ~= nil) and select("#", ...) >= 1
if not _G.__INSTALLER_LIB_MODE and not _is_module_require then
    local ok, err = bootstrapper.bootstrapAndRun({ cliArgs = _boot_args })
    if not ok and err then
        print("Error: " .. tostring(err))
    end
end

return bootstrapper
