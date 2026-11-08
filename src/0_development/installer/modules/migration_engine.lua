-- src/0_development/installer/modules/migration_engine.lua
--- JSON configuration deep-merge migration engine with array-replacement protection and atomic file updates.

local migration_engine = {}

--- Returns true when t is a non-empty sequential array (integer keys 1..#t).
-- @param t any
-- @return boolean
function migration_engine.isArray(t)
    if type(t) ~= "table" then
        return false
    end
    local n = #t
    if n == 0 then
        return false
    end
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    if count ~= n then
        return false
    end
    for i = 1, n do
        if t[i] == nil then
            return false
        end
    end
    return true
end

--- Recursively deep copies a value or table.
-- @param v any
-- @return any
function migration_engine.deepCopy(v)
    if type(v) ~= "table" then
        return v
    end
    local copy = {}
    for k, val in pairs(v) do
        copy[migration_engine.deepCopy(k)] = migration_engine.deepCopy(val)
    end
    return copy
end

--- Recursively merges existing configuration overrides with default schema.
-- Preserves user overrides at arbitrary depth while backfilling missing default keys.
-- When a value is an array (or empty table override for an array), the user table
-- replaces the default array rather than merging element-by-element.
-- @param existingConfig table|nil
-- @param defaultConfig table|nil
-- @return table Merged configuration table (neither input is mutated)
function migration_engine.deepMerge(existingConfig, defaultConfig)
    if type(existingConfig) ~= "table" and type(defaultConfig) ~= "table" then
        return {}
    end
    if type(existingConfig) ~= "table" then
        return migration_engine.deepCopy(defaultConfig)
    end
    if type(defaultConfig) ~= "table" then
        return migration_engine.deepCopy(existingConfig)
    end

    local result = {}

    -- Merge or backfill all default keys
    for k, defVal in pairs(defaultConfig) do
        local exVal = existingConfig[k]
        if exVal == nil then
            result[k] = migration_engine.deepCopy(defVal)
        else
            if type(exVal) == "table" and type(defVal) == "table" then
                if migration_engine.isArray(exVal) or migration_engine.isArray(defVal) then
                    -- Array override: user array replaces default array completely
                    result[k] = migration_engine.deepCopy(exVal)
                else
                    result[k] = migration_engine.deepMerge(exVal, defVal)
                end
            else
                result[k] = migration_engine.deepCopy(exVal)
            end
        end
    end

    -- Preserve extra user keys not present in defaults
    for k, exVal in pairs(existingConfig) do
        if defaultConfig[k] == nil then
            result[k] = migration_engine.deepCopy(exVal)
        end
    end

    return result
end

--- Atomically loads or creates a JSON configuration file, merging existing user
-- overrides with the provided default configuration schema.
-- @param filePath string Path to configuration file
-- @param defaultConfig table Default configuration values
-- @param fsApi table|nil Optional injected fs API (defaults to _G.fs)
-- @return boolean success
-- @return table|nil mergedConfig
-- @return string|nil errorMessage
function migration_engine.migrateFile(filePath, defaultConfig, fsApi)
    local fsObj = fsApi or fs
    if not fsObj then
        return false, nil, "FS_API_UNAVAILABLE"
    end
    if type(filePath) ~= "string" or filePath == "" then
        return false, nil, "INVALID_FILE_PATH"
    end

    local existingConfig = nil
    if fsObj.exists(filePath) then
        local rh = fsObj.open(filePath, "r")
        if not rh then
            return false, nil, "FAILED_TO_OPEN_EXISTING: " .. filePath
        end
        local raw = rh.readAll()
        rh.close()

        if raw and raw ~= "" then
            local ser = textutils and (textutils.unserializeJSON or textutils.unserialiseJSON)
            if not ser then
                return false, nil, "TEXTUTILS_JSON_UNAVAILABLE"
            end
            local parsed = ser(raw)
            if type(parsed) == "table" then
                existingConfig = parsed
            end
        end
    end

    local mergedConfig = migration_engine.deepMerge(existingConfig or {}, defaultConfig or {})

    -- Atomic persistence via temporary file
    local parent = fsObj.getDir(filePath)
    if parent and parent ~= "" and not fsObj.exists(parent) then
        local okMk, errMk = pcall(fsObj.makeDir, parent)
        if not okMk then
            return false, nil, "FAILED_TO_CREATE_DIR: " .. tostring(errMk)
        end
    end

    local tmpPath = filePath .. ".tmp"
    local serWrite = textutils and (textutils.serializeJSON or textutils.serialiseJSON)
    if not serWrite then
        return false, nil, "TEXTUTILS_JSON_UNAVAILABLE"
    end
    local jsonStr = serWrite(mergedConfig)

    local wh = fsObj.open(tmpPath, "w")
    if not wh then
        return false, nil, "FAILED_TO_OPEN_TMP: " .. tmpPath
    end
    wh.write(jsonStr)
    wh.close()

    if fsObj.exists(filePath) then
        local okDel, errDel = pcall(fsObj.delete, filePath)
        if not okDel then
            if fsObj.exists(tmpPath) then pcall(fsObj.delete, tmpPath) end
            return false, nil, "FAILED_TO_REMOVE_EXISTING: " .. tostring(errDel)
        end
    end

    local okMove, errMove = pcall(fsObj.move, tmpPath, filePath)
    if not okMove then
        if fsObj.exists(tmpPath) then pcall(fsObj.delete, tmpPath) end
        return false, nil, "FAILED_TO_MOVE_CONFIG: " .. tostring(errMove)
    end

    return true, mergedConfig, nil
end

return migration_engine
