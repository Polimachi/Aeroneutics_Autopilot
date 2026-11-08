-- src/0_development/installer/modules/version_registry.lua
-- Atomic metadata registry reader/writer and multi-module orphan calculator

local version_registry = {}

version_registry.DEFAULT_META_PATH = "/.version.json"

function version_registry.load(metaPath, fsApi)
    local fsObj = fsApi or fs
    local path = metaPath or version_registry.DEFAULT_META_PATH

    local defaultMeta = {
        modules = {},
        installerVersion = "1.0.0",
    }

    if not fsObj or not fsObj.exists(path) then
        return defaultMeta
    end

    local h = fsObj.open(path, "r")
    if not h then
        return defaultMeta
    end

    local raw = h.readAll()
    h.close()

    if not raw or raw == "" then
        return defaultMeta
    end

    local data = textutils.unserializeJSON(raw)
    if type(data) ~= "table" then
        return defaultMeta
    end

    if type(data.modules) ~= "table" then
        data.modules = {}
    end

    return data
end

function version_registry.save(metaPath, meta, fsApi)
    local fsObj = fsApi or fs
    local path = metaPath or version_registry.DEFAULT_META_PATH
    local tmpPath = path .. ".tmp"

    local parent = fsObj.getDir(path)
    if parent and parent ~= "" and not fsObj.exists(parent) then
        local okMkdir, errMkdir = pcall(fsObj.makeDir, parent)
        if not okMkdir then
            return false, "FAILED_TO_CREATE_DIR: " .. tostring(errMkdir)
        end
    end

    local jsonStr = textutils.serializeJSON(meta or { modules = {} })
    local h = fsObj.open(tmpPath, "w")
    if not h then
        return false, "FAILED_TO_OPEN_TMP: " .. tmpPath
    end

    h.write(jsonStr)
    h.close()

    if fsObj.exists(path) then
        local okDel, errDel = pcall(fsObj.delete, path)
        if not okDel then
            if fsObj.exists(tmpPath) then pcall(fsObj.delete, tmpPath) end
            return false, "FAILED_TO_REMOVE_EXISTING: " .. tostring(errDel)
        end
    end

    local okMove, errMove = pcall(fsObj.move, tmpPath, path)
    if not okMove then
        if fsObj.exists(tmpPath) then pcall(fsObj.delete, tmpPath) end
        return false, "FAILED_TO_COMMIT: " .. tostring(errMove)
    end

    return true, nil
end

function version_registry.recordInstall(meta, moduleId, version, destList, sourceUsed, timestampMs)
    if type(meta) ~= "table" then
        meta = { modules = {} }
    end
    if type(meta.modules) ~= "table" then
        meta.modules = {}
    end

    local destCopy = {}
    if type(destList) == "table" then
        for i, path in ipairs(destList) do
            destCopy[i] = path
        end
    end

    local defaultTime = 0
    if os and os.epoch then
        defaultTime = os.epoch("utc")
    elseif os and os.time then
        defaultTime = os.time() * 1000
    end

    meta.modules[moduleId] = {
        id = moduleId,
        version = tostring(version or "1.0.0"),
        files = destCopy,
        source = sourceUsed or "github",
        installedAt = timestampMs or defaultTime,
    }

    return meta
end

function version_registry.getOrphanFiles(meta, moduleId, newDestList)
    if not meta or type(meta.modules) ~= "table" or not meta.modules[moduleId] then
        return {}
    end

    local currentModule = meta.modules[moduleId]
    local prevFiles = currentModule.files or {}

    local newSet = {}
    if type(newDestList) == "table" then
        for _, f in ipairs(newDestList) do
            newSet[f] = true
        end
    end

    local otherModulesSet = {}
    for mId, mInfo in pairs(meta.modules) do
        if mId ~= moduleId and type(mInfo) == "table" and type(mInfo.files) == "table" then
            for _, f in ipairs(mInfo.files) do
                otherModulesSet[f] = true
            end
        end
    end

    local orphans = {}
    for _, f in ipairs(prevFiles) do
        if not newSet[f] and not otherModulesSet[f] then
            orphans[#orphans + 1] = f
        end
    end

    table.sort(orphans)
    return orphans
end

function version_registry.removeModule(meta, moduleId)
    if not meta or type(meta.modules) ~= "table" or not meta.modules[moduleId] then
        return {}
    end

    local currentModule = meta.modules[moduleId]
    local modFiles = currentModule.files or {}

    local otherModulesSet = {}
    for mId, mInfo in pairs(meta.modules) do
        if mId ~= moduleId and type(mInfo) == "table" and type(mInfo.files) == "table" then
            for _, f in ipairs(mInfo.files) do
                otherModulesSet[f] = true
            end
        end
    end

    local removable = {}
    for _, f in ipairs(modFiles) do
        if not otherModulesSet[f] then
            removable[#removable + 1] = f
        end
    end

    meta.modules[moduleId] = nil
    table.sort(removable)
    return removable
end

return version_registry
