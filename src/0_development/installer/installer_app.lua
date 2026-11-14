-- src/0_development/installer/installer_app.lua
-- Main Installer Application Controller with Staged Pipelines, Multi-Module Registry, and 51x19 TUI Loop

local installer_app = {}

--- Safely requires a module from root or modules/ subpackage without throwing errors.
-- @param name string Module name
-- @param subpath string|nil Alternative subpath
-- @return table|nil Loaded module
local function safeRequire(name, subpath)
    local ok, mod = pcall(require, name)
    if ok and type(mod) == "table" then
        return mod
    end
    if subpath then
        local ok2, mod2 = pcall(require, subpath)
        if ok2 and type(mod2) == "table" then
            return mod2
        end
    end
    return nil
end

--- Installs or upgrades a single module end-to-end.
-- Downloads batch atomically into staging, migrates configuration schemas preserving user values,
-- installs multi-boot startup hook, purges orphan files safely, and commits /.version.json.
-- Aborts completely before live system mutations if network or batch download fails.
-- @param moduleId string Module identifier (e.g. "tca", "fcp", "vas")
-- @param opts table|nil Options table { targetRoot, source, http, fs, onProgress, gdriveOverrides, metaPath }
-- @return boolean success
-- @return table|nil installedDestList
-- @return string|nil errorMessage
function installer_app.installModule(moduleId, opts)
    opts = opts or {}
    local manifestMod = opts.manifest or safeRequire("manifest", "modules.manifest")
    local versionReg = opts.versionRegistry or safeRequire("version_registry", "modules.version_registry")
    local migrationEng = opts.migrationEngine or safeRequire("migration_engine", "modules.migration_engine")
    local startupGen = opts.startupGenerator or safeRequire("startup_generator", "modules.startup_generator")
    local downloaderMod = opts.downloader or safeRequire("downloader", "modules.downloader")

    if not manifestMod then
        return false, nil, "MANIFEST_NOT_FOUND"
    end
    if not versionReg then
        return false, nil, "VERSION_REGISTRY_NOT_FOUND"
    end
    if not migrationEng then
        return false, nil, "MIGRATION_ENGINE_NOT_FOUND"
    end
    if not startupGen then
        return false, nil, "STARTUP_GENERATOR_NOT_FOUND"
    end
    if not downloaderMod then
        return false, nil, "DOWNLOADER_NOT_FOUND"
    end

    local mod = manifestMod.getModule(moduleId)
    if not mod then
        return false, nil, "MODULE_NOT_FOUND: " .. tostring(moduleId)
    end

    local fsObj = opts.fs or _G.fs
    if not fsObj then
        return false, nil, "FS_DISABLED"
    end

    local httpObj
    if opts.http ~= nil then
        httpObj = opts.http
    else
        httpObj = _G.http
    end

    local okHttp, httpErr = downloaderMod.checkHttpAvailable(httpObj)
    if not okHttp then
        return false, nil, httpErr
    end

    local targetRoot = opts.targetRoot or "/"
    local source = opts.source or (manifestMod.SOURCES and manifestMod.SOURCES.GITHUB) or "github"

    -- 1. Metadata resolution
    local metaPath = opts.metaPath or startupGen.resolveTargetPath(targetRoot, versionReg.DEFAULT_META_PATH)
    local meta = versionReg.load(metaPath, fsObj)

    -- 2. Staged batch download via atomic downloader
    local batchOpts = {
        targetRoot = targetRoot,
        manifest = manifestMod,
        gdriveOverrides = opts.gdriveOverrides,
        onProgress = opts.onProgress,
        http = httpObj,
        fs = fsObj,
    }
    local okDl, installedDestList, dlErr = downloaderMod.downloadBatch(source, mod.files, batchOpts)
    if not okDl then
        -- Abort immediately before modifying existing configs, startup hooks, orphans, or metadata
        return false, nil, dlErr
    end

    -- 3. JSON Configuration deep-merge migration
    if type(mod.defaultConfigs) == "table" then
        for cfgRelPath, defCfg in pairs(mod.defaultConfigs) do
            local fullCfgPath = startupGen.resolveTargetPath(targetRoot, cfgRelPath)
            local okMig, _, migErr = migrationEng.migrateFile(fullCfgPath, defCfg, fsObj)
            if not okMig then
                return false, nil, "CONFIG_MIGRATION_FAILED: " .. tostring(migErr)
            end
        end
    end

    -- 4. Multi-boot Startup Hook generation & installation
    if mod.startup and mod.startup.enabled then
        local hookSpec = {
            name = mod.startup.name or mod.name,
            path = mod.startup.path,
            target = mod.startup.target or "/main.lua",
            installDir = mod.installDir or "/",
            args = mod.startup.args or {},
            enabled = true,
        }
        local okHook, hookErr = startupGen.installHook(hookSpec, targetRoot, fsObj)
        if not okHook then
            return false, nil, "STARTUP_HOOK_FAILED: " .. tostring(hookErr)
        end
    end

    -- 5. Safe multi-module orphan purge
    local orphans = versionReg.getOrphanFiles(meta, moduleId, installedDestList)
    for _, orphanRel in ipairs(orphans) do
        local fullOrphan = startupGen.resolveTargetPath(targetRoot, orphanRel)
        if fsObj.exists(fullOrphan) then
            pcall(fsObj.delete, fullOrphan)
        end
    end

    -- 6. Atomic /.version.json registry commit
    versionReg.recordInstall(meta, moduleId, mod.version, installedDestList, source)
    local okSave, saveErr = versionReg.save(metaPath, meta, fsObj)
    if not okSave then
        return false, nil, "VERSION_REGISTRY_SAVE_FAILED: " .. tostring(saveErr)
    end

    return true, installedDestList, nil
end

--- Uninstalls a module cleanly, protecting files still owned by other installed modules.
-- @param moduleId string Module identifier
-- @param opts table|nil Options table { targetRoot, fs, metaPath }
-- @return boolean success
-- @return string|nil errorMessage
function installer_app.uninstallModule(moduleId, opts)
    opts = opts or {}
    local manifestMod = opts.manifest or safeRequire("manifest", "modules.manifest")
    local versionReg = opts.versionRegistry or safeRequire("version_registry", "modules.version_registry")
    local startupGen = opts.startupGenerator or safeRequire("startup_generator", "modules.startup_generator")

    if not versionReg then
        return false, "VERSION_REGISTRY_NOT_FOUND"
    end
    if not startupGen then
        return false, "STARTUP_GENERATOR_NOT_FOUND"
    end

    local fsObj = opts.fs or _G.fs
    if not fsObj then
        return false, "FS_DISABLED"
    end

    local targetRoot = opts.targetRoot or "/"
    local metaPath = opts.metaPath or startupGen.resolveTargetPath(targetRoot, versionReg.DEFAULT_META_PATH)
    local meta = versionReg.load(metaPath, fsObj)

    if not meta.modules or not meta.modules[moduleId] then
        return false, "MODULE_NOT_INSTALLED: " .. tostring(moduleId)
    end

    -- 1. Remove module from registry and get orphan files safe to remove
    local removable = versionReg.removeModule(meta, moduleId)
    for _, fileRel in ipairs(removable) do
        local fullPath = startupGen.resolveTargetPath(targetRoot, fileRel)
        if fsObj.exists(fullPath) then
            pcall(fsObj.delete, fullPath)
        end
    end

    -- 2. Remove startup hook if registered
    local mod = manifestMod and manifestMod.getModule(moduleId)
    local hookPath = mod and mod.startup and mod.startup.path
    if not hookPath then
        hookPath = "/startup/00_" .. tostring(moduleId) .. ".lua"
    end
    startupGen.removeHook(hookPath, targetRoot, fsObj)

    -- 3. Save updated metadata
    local okSave, saveErr = versionReg.save(metaPath, meta, fsObj)
    if not okSave then
        return false, "VERSION_REGISTRY_SAVE_FAILED: " .. tostring(saveErr)
    end

    return true, nil
end

local function renderActiveMessage(tuiView, termObj, state, activeModules, moduleIndex, statusMsg, statusLevel)
    if state == "CONFIRM_INSTALL" then
        local selectedMod = activeModules[moduleIndex]
        tuiView.renderMessage(termObj, "warn", "Install " .. tostring(selectedMod and selectedMod.name or "") .. "? (y/n)")
    elseif state == "CONFIRM_UNINSTALL" then
        local selectedMod = activeModules[moduleIndex]
        tuiView.renderMessage(termObj, "warn", "Uninstall " .. tostring(selectedMod and selectedMod.name or "") .. "? (y/n)")
    elseif statusMsg then
        tuiView.renderMessage(termObj, statusLevel, statusMsg)
    end
end

local function stepSelection(tuiView, termObj, items, currentIndex, scrollOffset, isUp, installedMap, isCategory, statusMsg)
    if #items == 0 then
        return currentIndex, statusMsg, false
    end
    local prev = currentIndex
    local nextIdx = isUp and math.max(1, currentIndex - 1) or math.min(#items, currentIndex + 1)
    local hadStatus = (statusMsg ~= nil)
    if nextIdx == prev and not hadStatus then
        return nextIdx, statusMsg, false
    end

    if type(tuiView.updateSelection) == "function" then
        if tuiView.updateSelection(termObj, items, prev, nextIdx, scrollOffset, installedMap, isCategory, hadStatus) then
            return nextIdx, nil, false
        end
    end
    return nextIdx, nil, true
end

local function resetTerminalOnExit(termObj)
    if not termObj then return end
    local c = _G.colors or {}
    if termObj.setTextColor then
        termObj.setTextColor(c.white or 1)
    end
    if termObj.setBackgroundColor then
        termObj.setBackgroundColor(c.black or 32768)
    end
    if termObj.setCursorPos and termObj.getSize then
        local _, h = termObj.getSize()
        termObj.setCursorPos(1, tonumber(h) or 19)
    end
end

--- Runs the installer in either non-interactive CLI mode or interactive 51x19 TUI mode.
-- @param opts table|nil Configuration options
-- @return boolean success
-- @return string|nil errorMessage
function installer_app.run(opts)
    opts = opts or {}
    local manifestMod = opts.manifest or safeRequire("manifest", "modules.manifest")
    local versionReg = opts.versionRegistry or safeRequire("version_registry", "modules.version_registry")
    local startupGen = opts.startupGenerator or safeRequire("startup_generator", "modules.startup_generator")
    local tuiView = opts.tuiView or safeRequire("tui_view", "modules.tui_view")

    -- 1. Non-interactive CLI Mode
    if opts.cliArgs and #opts.cliArgs > 0 then
        local cmd = tostring(opts.cliArgs[1] or ""):lower()
        local modId = opts.cliArgs[2]

        if cmd == "install" or cmd == "update" then
            if not modId or modId == "" then
                return false, "MISSING_MODULE_ID"
            end
            local src = opts.source or "github"
            for i = 3, #opts.cliArgs do
                if opts.cliArgs[i] == "--source" or opts.cliArgs[i] == "-s" then
                    if opts.cliArgs[i + 1] then
                        src = tostring(opts.cliArgs[i + 1]):lower()
                    end
                end
            end
            local callOpts = {}
            for k, v in pairs(opts) do callOpts[k] = v end
            callOpts.source = src
            local okInst, _, errInst = installer_app.installModule(modId, callOpts)
            return okInst, errInst
        elseif cmd == "uninstall" or cmd == "remove" then
            if not modId or modId == "" then
                return false, "MISSING_MODULE_ID"
            end
            local callOpts = {}
            for k, v in pairs(opts) do callOpts[k] = v end
            local okUn, errUn = installer_app.uninstallModule(modId, callOpts)
            return okUn, errUn
        else
            return false, "UNKNOWN_CLI_COMMAND: " .. tostring(cmd)
        end
    end

    -- 2. Interactive TUI Mode
    local termObj = opts.term or _G.term
    local pullEvent = opts.pullEvent or os.pullEvent
    local fsObj = opts.fs or _G.fs
    local targetRoot = opts.targetRoot or "/"
    local currentSource = opts.source or "github"
    local metaPath = opts.metaPath or (startupGen and startupGen.resolveTargetPath(targetRoot, versionReg.DEFAULT_META_PATH))

    if not manifestMod or not tuiView or not versionReg then
        return false, "REQUIRED_MODULES_MISSING"
    end

    local categories
    if type(manifestMod.listCategories) == "function" then
        categories = manifestMod.listCategories(false) or {}
    else
        local fallbackMods = manifestMod.listModules and manifestMod.listModules() or {}
        categories = {
            {
                id = "all",
                code = "all",
                name = "All Modules",
                shortName = "All Modules",
                modules = fallbackMods,
                moduleCount = #fallbackMods,
            },
        }
    end

    local categoryIndex = 1
    local categoryScroll = 0
    local moduleIndex = 1
    local moduleScroll = 0
    local state = "CATEGORY_MENU" -- "CATEGORY_MENU", "MODULE_MENU", "CONFIRM_INSTALL", "CONFIRM_UNINSTALL"
    local statusMsg = nil
    local statusLevel = "info"
    local needsFullRender = true
    local needsMessageOnly = false

    local meta = versionReg.load(metaPath, fsObj)
    local installedMap = (meta and meta.modules) or {}

    while true do
        local activeCategory = categories[categoryIndex]
        local activeModules = (activeCategory and activeCategory.modules) or {}

        if needsFullRender then
            needsFullRender = false
            needsMessageOnly = false
            if state == "CATEGORY_MENU" then
                if type(tuiView.renderCategoryMenu) == "function" then
                    categoryScroll = tuiView.renderCategoryMenu(termObj, categories, categoryIndex, currentSource, installedMap, categoryScroll) or categoryScroll
                else
                    local flatMods = (type(manifestMod.listModules) == "function" and manifestMod.listModules()) or activeModules
                    tuiView.renderMenu(termObj, flatMods, moduleIndex, currentSource, installedMap)
                end
                if statusMsg then
                    tuiView.renderMessage(termObj, statusLevel, statusMsg)
                end
            else
                moduleScroll = tuiView.renderMenu(termObj, activeModules, moduleIndex, currentSource, installedMap, activeCategory, moduleScroll) or moduleScroll
                renderActiveMessage(tuiView, termObj, state, activeModules, moduleIndex, statusMsg, statusLevel)
            end
        elseif needsMessageOnly then
            needsMessageOnly = false
            renderActiveMessage(tuiView, termObj, state, activeModules, moduleIndex, statusMsg, statusLevel)
        end

        local ev, p1 = pullEvent()
        if not ev then
            return true, nil
        end

        if ev == "term_resize" then
            needsFullRender = true
        elseif ev == "char" then
            local ch = tostring(p1 or ""):lower()
            if state == "CATEGORY_MENU" then
                if ch == "q" then
                    resetTerminalOnExit(termObj)
                    return true, nil
                elseif ch == "s" then
                    currentSource = tuiView.toggleSource(currentSource)
                    statusMsg = "Switched source to " .. (currentSource == "gdrive" and "Google Drive" or "GitHub")
                    statusLevel = "info"
                    needsFullRender = true
                end
            elseif state == "MODULE_MENU" then
                if ch == "q" then
                    resetTerminalOnExit(termObj)
                    return true, nil
                elseif ch == "b" then
                    state = "CATEGORY_MENU"
                    statusMsg = nil
                    needsFullRender = true
                elseif ch == "s" then
                    currentSource = tuiView.toggleSource(currentSource)
                    statusMsg = "Switched source to " .. (currentSource == "gdrive" and "Google Drive" or "GitHub")
                    statusLevel = "info"
                    needsFullRender = true
                elseif ch == "u" then
                    local selectedMod = activeModules[moduleIndex]
                    if selectedMod and installedMap[selectedMod.id] then
                        state = "CONFIRM_UNINSTALL"
                        statusMsg = nil
                        needsMessageOnly = true
                    else
                        statusMsg = "Module is not installed"
                        statusLevel = "warn"
                        needsMessageOnly = true
                    end
                end
            elseif state == "CONFIRM_INSTALL" then
                if ch == "y" then
                    state = "MODULE_MENU"
                    local selectedMod = activeModules[moduleIndex]
                    if selectedMod then
                        local onProg = function(cur, total, path)
                            tuiView.renderProgress(termObj, cur, total, path, currentSource)
                        end
                        local instOpts = {}
                        for k, v in pairs(opts) do instOpts[k] = v end
                        instOpts.source = currentSource
                        instOpts.targetRoot = targetRoot
                        instOpts.onProgress = onProg

                        local okInst, _, instErr = installer_app.installModule(selectedMod.id, instOpts)
                        if okInst then
                            statusMsg = tostring(selectedMod.name) .. " installed successfully"
                            statusLevel = "success"
                            installedMap[selectedMod.id] = { id = selectedMod.id, version = selectedMod.version }
                        else
                            statusMsg = "Install failed: " .. tostring(instErr)
                            statusLevel = "error"
                        end
                    end
                    needsFullRender = true
                elseif ch == "n" or ch == "q" then
                    state = "MODULE_MENU"
                    statusMsg = "Installation cancelled"
                    statusLevel = "info"
                    needsMessageOnly = true
                end
            elseif state == "CONFIRM_UNINSTALL" then
                if ch == "y" then
                    state = "MODULE_MENU"
                    local selectedMod = activeModules[moduleIndex]
                    if selectedMod then
                        local uninstOpts = {}
                        for k, v in pairs(opts) do uninstOpts[k] = v end
                        uninstOpts.targetRoot = targetRoot

                        local okUn, unErr = installer_app.uninstallModule(selectedMod.id, uninstOpts)
                        if okUn then
                            statusMsg = tostring(selectedMod.name) .. " uninstalled successfully"
                            statusLevel = "success"
                            installedMap[selectedMod.id] = nil
                        else
                            statusMsg = "Uninstall failed: " .. tostring(unErr)
                            statusLevel = "error"
                        end
                    end
                    needsFullRender = true
                elseif ch == "n" or ch == "q" then
                    state = "MODULE_MENU"
                    statusMsg = "Uninstallation cancelled"
                    statusLevel = "info"
                    needsMessageOnly = true
                end
            end
        elseif ev == "key" then
            local key = p1
            local keysObj = _G.keys or {}
            local isUp = (key == 200) or (keysObj.up ~= nil and key == keysObj.up)
            local isDown = (key == 208) or (keysObj.down ~= nil and key == keysObj.down)
            local isLeft = (key == 203) or (keysObj.left ~= nil and key == keysObj.left)
            local isRight = (key == 205) or (keysObj.right ~= nil and key == keysObj.right)
            local isEnter = (key == 28) or (key == 156) or (keysObj.enter ~= nil and key == keysObj.enter) or (keysObj.numPadEnter ~= nil and key == keysObj.numPadEnter)
            local isBackspace = (key == 14) or (keysObj.backspace ~= nil and key == keysObj.backspace)
            local isQ = (key == 16) or (keysObj.q ~= nil and key == keysObj.q)

            if state == "CATEGORY_MENU" then
                if isUp or isDown then
                    local needFull
                    categoryIndex, statusMsg, needFull = stepSelection(tuiView, termObj, categories, categoryIndex, categoryScroll, isUp, installedMap, true, statusMsg)
                    if needFull then needsFullRender = true end
                elseif isEnter or isRight then
                    if activeCategory and #activeModules > 0 then
                        state = "MODULE_MENU"
                        moduleIndex = 1
                        moduleScroll = 0
                        statusMsg = nil
                        needsFullRender = true
                    elseif activeCategory then
                        statusMsg = "Folder is empty"
                        statusLevel = "warn"
                        needsMessageOnly = true
                    end
                elseif isQ then
                    resetTerminalOnExit(termObj)
                    return true, nil
                end
            elseif state == "MODULE_MENU" then
                if isUp or isDown then
                    local needFull
                    moduleIndex, statusMsg, needFull = stepSelection(tuiView, termObj, activeModules, moduleIndex, moduleScroll, isUp, installedMap, false, statusMsg)
                    if needFull then needsFullRender = true end
                elseif isEnter then
                    if activeModules[moduleIndex] then
                        state = "CONFIRM_INSTALL"
                        statusMsg = nil
                        needsMessageOnly = true
                    end
                elseif isBackspace or isLeft then
                    state = "CATEGORY_MENU"
                    statusMsg = nil
                    needsFullRender = true
                elseif isQ then
                    resetTerminalOnExit(termObj)
                    return true, nil
                end
            elseif state == "CONFIRM_INSTALL" then
                if isBackspace then
                    state = "MODULE_MENU"
                    statusMsg = "Installation cancelled"
                    statusLevel = "info"
                    needsMessageOnly = true
                end
            elseif state == "CONFIRM_UNINSTALL" then
                if isBackspace then
                    state = "MODULE_MENU"
                    statusMsg = "Uninstallation cancelled"
                    statusLevel = "info"
                    needsMessageOnly = true
                end
            end
        end
    end
end

return installer_app
