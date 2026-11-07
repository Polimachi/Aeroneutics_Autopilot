-- Atomic JSON persistence abstraction for CC:Tweaked filesystem
local storage_hal = {}

local function ensureDir(path)
    if not fs or not fs.getDir then return end
    local dir = fs.getDir(path)
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
end

function storage_hal.readJson(path)
    if not fs or not fs.exists or not fs.exists(path) then
        return nil, "FILE_NOT_FOUND"
    end
    local f = fs.open(path, "r")
    if not f then return nil, "CANNOT_OPEN" end
    local content = f.readAll()
    f.close()
    if not content or content == "" then return nil, "EMPTY_FILE" end
    local ser = textutils.unserializeJSON or textutils.unserialiseJSON
    if not ser then return nil, "JSON_API_UNAVAILABLE" end
    local data = ser(content)
    if not data then return nil, "JSON_PARSE_ERROR" end
    return data
end

function storage_hal.writeJsonAtomic(path, dataTable)
    if not fs or not textutils then return false, "FS_API_UNAVAILABLE" end
    ensureDir(path)
    local ser = textutils.serializeJSON or textutils.serialiseJSON
    local raw = ser(dataTable)
    if not raw then return false, "SERIALIZE_FAILED" end
    local tmp = path .. ".tmp"
    local f = fs.open(tmp, "w")
    if not f then return false, "CANNOT_WRITE_TMP" end
    f.write(raw)
    f.close()
    if fs.exists(path) then
        fs.delete(path)
    end
    local ok, err = pcall(fs.move, tmp, path)
    if not ok then return false, tostring(err) end
    return true
end

return storage_hal
