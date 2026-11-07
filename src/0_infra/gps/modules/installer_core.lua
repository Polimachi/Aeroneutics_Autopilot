-- installer_core.lua - Self-healing Config Migration and Startup Generator
local installer_core = {}

local function deepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = deepCopy(v)
    end
    return copy
end

function installer_core.migrateConfig(existingConfig, defaultConfig)
    local merged = deepCopy(defaultConfig or {})
    if not existingConfig or type(existingConfig) ~= "table" then
        return merged
    end

    for k, v in pairs(existingConfig) do
        if type(v) == "table" and type(merged[k]) == "table" then
            for subK, subV in pairs(v) do
                merged[k][subK] = deepCopy(subV)
            end
        else
            merged[k] = deepCopy(v)
        end
    end
    return merged
end

function installer_core.generateStartupHook(role, targetScriptPath)
    local r = tostring(role or "node"):upper()
    local path = tostring(targetScriptPath or "/gps/node.lua")
    local lines = {
        string.format("-- Auto-generated startup hook for CC-GPS (%s)", r),
        string.format("-- Target: %s", path),
        "if shell and fs and fs.exists(\"" .. path .. "\") then",
        "    print(\"[GPS] Launching GPS " .. (r == "SERVER" and "Central Server" or "Node") .. "...\")",
        "    shell.run(\"" .. path .. "\")",
        "end\n"
    }
    return table.concat(lines, "\n")
end

function installer_core.isValidRole(role)
    local r = string.lower(tostring(role or ""))
    return r == "server" or r == "node" or r == "client"
end

return installer_core
