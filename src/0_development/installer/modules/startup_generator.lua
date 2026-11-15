-- src/0_development/installer/modules/startup_generator.lua
--- Multi-boot startup hook generator supporting CraftOS cc.require package.path injection and daemon argument forwarding.

local startup_generator = {}

--- Resolves a relative or absolute path against a target root directory.
-- Ensures consistent forward slashes, prevents double prefixing, and handles root "/" cleanly.
-- @param targetRoot string|nil Target root directory (defaults to "/")
-- @param relOrAbsPath string|nil Path to resolve
-- @return string Resolved path
function startup_generator.resolveTargetPath(targetRoot, relOrAbsPath)
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

    -- If p already starts with root, avoid double prefixing
    if p == root then
        return p
    end
    if p:sub(1, #root + 1) == root .. "/" then
        return p
    end

    if p:sub(1, 1) ~= "/" then
        p = "/" .. p
    end

    return root .. p
end

--- Generates pure Lua 5.2 startup hook code for a module specification.
-- Emits cc.require environment scoping, package.path search path extension,
-- argument forwarding to loadfile, and a self-contained 2-stage OTA boot watchdog.
-- @param spec table Hook specification ({ name, target, installDir, args, otaRootPrefix })
-- @return string Generated Lua code
function startup_generator.generateHookContent(spec)
    spec = spec or {}
    local name = spec.name or "App"
    local target = spec.target or "/main.lua"
    local installDir = spec.installDir or "/"
    local args = spec.args or {}

    local otaRoot = spec.otaRootPrefix or ""
    otaRoot = otaRoot:gsub("\\", "/")
    while #otaRoot > 1 and otaRoot:sub(-1) == "/" do
        otaRoot = otaRoot:sub(1, -2)
    end
    if otaRoot == "/" then
        otaRoot = ""
    end

    local pendingPath = otaRoot .. "/.ota_pending.json"
    local rollbackPath = otaRoot .. "/.ota_rollback.json"
    local versionDest = otaRoot .. "/.version.json"

    local serializedArgs = {}
    for _, a in ipairs(args) do
        if type(a) == "string" then
            table.insert(serializedArgs, string.format("%q", a))
        elseif type(a) == "number" or type(a) == "boolean" then
            table.insert(serializedArgs, tostring(a))
        else
            table.insert(serializedArgs, string.format("%q", tostring(a)))
        end
    end
    local argsLiteral = "{" .. table.concat(serializedArgs, ", ") .. "}"

    local lines = {
        "-- Auto-generated Multi-Boot Hook: " .. name,
        "local target = " .. string.format("%q", target),
        "local installDir = " .. string.format("%q", installDir),
        "local hookArgs = " .. argsLiteral,
        "local otaPendingPath = " .. string.format("%q", pendingPath),
        "local otaRollbackPath = " .. string.format("%q", rollbackPath),
        "local otaVersionDest = " .. string.format("%q", versionDest),
        "",
        "local env = setmetatable({}, { __index = _ENV or _G })",
        "local ok_cc, cc_req = pcall(require, \"cc.require\")",
        "if not ok_cc or type(cc_req) ~= \"table\" or type(cc_req.make) ~= \"function\" then",
        "    if fs and fs.exists(\"/rom/modules/main/cc/require.lua\") then",
        "        local reqChunk = loadfile(\"/rom/modules/main/cc/require.lua\", nil, _ENV or _G)",
        "        if reqChunk then",
        "            local okChunk, resChunk = pcall(reqChunk)",
        "            if okChunk and type(resChunk) == \"table\" and type(resChunk.make) == \"function\" then",
        "                cc_req = resChunk",
        "                ok_cc = true",
        "            end",
        "        end",
        "    end",
        "end",
        "if ok_cc and type(cc_req) == \"table\" and type(cc_req.make) == \"function\" then",
        "    local req_fn, pkg_tbl = cc_req.make(env, installDir)",
        "    env.require = req_fn",
        "    env.package = pkg_tbl",
        "else",
        "    local pkg = package or (_ENV and _ENV.package) or _G.package",
        "    if pkg then",
        "        env.package = { path = pkg.path or \"\", loaded = pkg.loaded or {}, preload = pkg.preload or {} }",
        "    else",
        "        env.package = { path = \"\" }",
        "    end",
        "    env.require = require or (_ENV and _ENV.require) or _G.require",
        "end",
        "",
        "local baseDir = installDir:gsub(\"\\\\\", \"/\")",
        "while #baseDir > 1 and baseDir:sub(-1) == \"/\" do baseDir = baseDir:sub(1, -2) end",
        "if baseDir == \"\" then baseDir = \"/\" end",
        "local dirPrefix = (baseDir == \"/\") and \"\" or baseDir",
        "local searchPath = dirPrefix .. \"/?.lua;\" .. dirPrefix .. \"/?/init.lua;\" .. dirPrefix .. \"/modules/?.lua;\" .. dirPrefix .. \"/modules/drivers/?.lua;\" .. dirPrefix .. \"/hal/?.lua;\" .. dirPrefix .. \"/tools/?.lua;\" .. dirPrefix .. \"/lib/?.lua;/lib/?.lua;/apis/?.lua;\"",
        "",
        "if env.package then",
        "    env.package.path = searchPath .. (env.package.path or \"\")",
        "end",
        "if package and package.path then",
        "    package.path = searchPath .. package.path",
        "end",
        "",
        "-- Self-contained OTA Rollback Recovery Helper (zero require dependencies)",
        "local function rollbackOTA(pRecord, reasonStr, errStr)",
        "    pRecord = (type(pRecord) == \"table\") and pRecord or {}",
        "    if type(pRecord.restoredFiles) == \"table\" then",
        "        for _, item in ipairs(pRecord.restoredFiles) do",
        "            if type(item) == \"table\" then",
        "                if item.existed == true then",
        "                    if item.dest and item.src and fs and fs.exists and fs.exists(item.src) then",
        "                        local pDir = fs.getDir(item.dest)",
        "                        if pDir and pDir ~= \"\" and not fs.exists(pDir) then",
        "                            pcall(fs.makeDir, pDir)",
        "                        end",
        "                        if fs.exists(item.dest) then",
        "                            pcall(fs.delete, item.dest)",
        "                        end",
        "                        pcall(fs.copy, item.src, item.dest)",
        "                    end",
        "                elseif item.existed == false then",
        "                    if item.dest and fs and fs.exists and fs.exists(item.dest) then",
        "                        pcall(fs.delete, item.dest)",
        "                    end",
        "                end",
        "            end",
        "        end",
        "    end",
        "    if pRecord.versionBackupPath and fs and fs.exists and fs.exists(pRecord.versionBackupPath) then",
        "        if fs.exists(otaVersionDest) then",
        "            pcall(fs.delete, otaVersionDest)",
        "        end",
        "        local vDir = fs.getDir(otaVersionDest)",
        "        if vDir and vDir ~= \"\" and not fs.exists(vDir) then",
        "            pcall(fs.makeDir, vDir)",
        "        end",
        "        pcall(fs.copy, pRecord.versionBackupPath, otaVersionDest)",
        "    end",
        "    local rollbackRecord = {",
        "        txId = pRecord.txId,",
        "        moduleId = pRecord.moduleId,",
        "        targetVersion = pRecord.targetVersion,",
        "        reason = reasonStr,",
        "        timestamp = (os and os.epoch and os.epoch(\"utc\")) or 0,",
        "    }",
        "    if errStr ~= nil then",
        "        rollbackRecord.error = tostring(errStr)",
        "    end",
        "    if fs and textutils and textutils.serializeJSON then",
        "        local rwh = fs.open(otaRollbackPath, \"w\")",
        "        if rwh then",
        "            rwh.write(textutils.serializeJSON(rollbackRecord))",
        "            rwh.close()",
        "        end",
        "    end",
        "    if pRecord.backupDir and fs and fs.exists and fs.exists(pRecord.backupDir) then",
        "        pcall(fs.delete, pRecord.backupDir)",
        "    end",
        "    if fs and fs.exists and fs.exists(otaPendingPath) then",
        "        pcall(fs.delete, otaPendingPath)",
        "    end",
        "end",
        "",
        "-- 2-Stage OTA Boot Watchdog Pre-Check",
        "local pending = nil",
        "if fs and fs.exists and fs.exists(otaPendingPath) then",
        "    local rh = fs.open(otaPendingPath, \"r\")",
        "    if rh then",
        "        local raw = rh.readAll()",
        "        rh.close()",
        "        if raw and textutils and textutils.unserializeJSON then",
        "            local okParse, parsed = pcall(textutils.unserializeJSON, raw)",
        "            if okParse and type(parsed) == \"table\" then",
        "                pending = parsed",
        "            end",
        "        end",
        "    end",
        "end",
        "",
        "if pending then",
        "    local maxBootAttempts = tonumber(pending.maxBootAttempts) or 1",
        "    local bootAttempts = tonumber(pending.bootAttempts) or 0",
        "    if bootAttempts >= maxBootAttempts then",
        "        rollbackOTA(pending, \"BOOT_WATCHDOG_TIMEOUT\", nil)",
        "    else",
        "        pending.bootAttempts = bootAttempts + 1",
        "        if fs and textutils and textutils.serializeJSON then",
        "            local wh = fs.open(otaPendingPath, \"w\")",
        "            if wh then",
        "                wh.write(textutils.serializeJSON(pending))",
        "                wh.close()",
        "            end",
        "        end",
        "    end",
        "end",
        "",
        "local fn, loadErr = loadfile(target, nil, env)",
        "if not fn then",
        "    if fs and fs.exists and fs.exists(otaPendingPath) then",
        "        rollbackOTA(pending, \"BOOT_LOAD_ERROR\", loadErr)",
        "        if not _G.__OTA_DISABLE_REBOOT and os and os.reboot then",
        "            os.reboot()",
        "        end",
        "        return",
        "    end",
        "    print(\"[\" .. " .. string.format("%q", name) .. " .. \"] Failed to load: \" .. tostring(loadErr))",
        "    return",
        "end",
        "",
        "local unpackFn = table.unpack or unpack",
        "local okRun, runErr = pcall(fn, unpackFn(hookArgs))",
        "if not okRun then",
        "    if fs and fs.exists and fs.exists(otaPendingPath) then",
        "        rollbackOTA(pending, \"BOOT_RUNTIME_CRASH\", runErr)",
        "        if not _G.__OTA_DISABLE_REBOOT and os and os.reboot then",
        "            os.reboot()",
        "        end",
        "        return",
        "    end",
        "    print(\"[\" .. " .. string.format("%q", name) .. " .. \"] Runtime error: \" .. tostring(runErr))",
        "end",
    }

    return table.concat(lines, "\n") .. "\n"
end

--- Installs a multi-boot startup hook atomically into <targetRoot>/startup/<hookName>.
-- @param spec table Hook specification ({ path, name, target, installDir, args, otaRootPrefix })
-- @param targetRoot string|nil Target root directory (defaults to "/")
-- @param fsApi table|nil Optional injected fs API (defaults to _G.fs)
-- @return boolean success
-- @return string|nil errorMessage
function startup_generator.installHook(spec, targetRoot, fsApi)
    local fsObj = fsApi or fs
    if not fsObj then
        return false, "FS_API_UNAVAILABLE"
    end
    if type(spec) ~= "table" or type(spec.path) ~= "string" or spec.path == "" then
        return false, "INVALID_HOOK_SPEC"
    end

    local root = targetRoot or "/"
    local fullHookPath = startup_generator.resolveTargetPath(root, spec.path)

    local effectiveSpec = {
        name = spec.name or "App",
        path = spec.path,
        target = startup_generator.resolveTargetPath(root, spec.target or "/main.lua"),
        installDir = startup_generator.resolveTargetPath(root, spec.installDir or "/"),
        args = spec.args,
        enabled = spec.enabled,
        otaRootPrefix = spec.otaRootPrefix or (root ~= "/" and root or nil),
    }

    local content = startup_generator.generateHookContent(effectiveSpec)

    local parent = fsObj.getDir(fullHookPath)
    if parent and parent ~= "" and not fsObj.exists(parent) then
        local okMk, errMk = pcall(fsObj.makeDir, parent)
        if not okMk then
            return false, "FAILED_TO_CREATE_DIR: " .. tostring(errMk)
        end
    end

    local tmpPath = fullHookPath .. ".tmp"
    local wh = fsObj.open(tmpPath, "w")
    if not wh then
        return false, "FAILED_TO_OPEN_TMP: " .. tmpPath
    end
    wh.write(content)
    wh.close()

    if fsObj.exists(fullHookPath) then
        local okDel, errDel = pcall(fsObj.delete, fullHookPath)
        if not okDel then
            if fsObj.exists(tmpPath) then pcall(fsObj.delete, tmpPath) end
            return false, "FAILED_TO_REMOVE_EXISTING: " .. tostring(errDel)
        end
    end

    local okMove, errMove = pcall(fsObj.move, tmpPath, fullHookPath)
    if not okMove then
        if fsObj.exists(tmpPath) then pcall(fsObj.delete, tmpPath) end
        return false, "FAILED_TO_MOVE_HOOK: " .. tostring(errMove)
    end

    return true, nil
end

--- Removes a previously installed startup hook from <targetRoot>/startup/<hookName>.
-- @param hookPath string Relative or absolute hook path (e.g. "/startup/00_fcp.lua")
-- @param targetRoot string|nil Target root directory (defaults to "/")
-- @param fsApi table|nil Optional injected fs API (defaults to _G.fs)
-- @return boolean success
function startup_generator.removeHook(hookPath, targetRoot, fsApi)
    local fsObj = fsApi or fs
    if not fsObj then
        return false
    end
    if type(hookPath) ~= "string" or hookPath == "" then
        return false
    end

    local root = targetRoot or "/"
    local fullHookPath = startup_generator.resolveTargetPath(root, hookPath)

    if not fsObj.exists(fullHookPath) then
        return true
    end

    local ok, _ = pcall(fsObj.delete, fullHookPath)
    return ok and not fsObj.exists(fullHookPath)
end

return startup_generator
