-- src/0_infra/gac/modules/config_loader.lua
-- Configuration loader, schema validator, and atomic JSON persistence for GAC

local config_loader = {}

local DEFAULT_CONFIG_PATH = "/gac/config.json"

function config_loader.get_default_config()
    return {
        sectorId = "BASE_ALPHA_SECTOR_01",
        sectorName = "Alpha Base Central Vertiport",
        sectorType = "VERTIPORT",
        sectorIndex = 1,
        baseSecChannel = 50201,
        towerAtcChannel = 50001,
        beaconChannel = 50003,
        dispatchChannel = 50004,
        checkinTimeoutSec = 60,
        slotDurationSec = 120,
        surfaceWind = {
            speed = 2.4,
            direction = 195.0
        },
        facilities = {
            {
                facilityId = "PAD_01",
                type = "LANDING_PAD",
                tacticalChannel = 50211,
                maxSupportWeight = 40000.0,
                maxSupportRadius = 12.0,
                coordinates = { x = 1250.0, y = 65.0, z = -820.0 },
                status = "FREE",
                mobility = "STATIC"
            },
            {
                facilityId = "PAD_02",
                type = "LANDING_PAD",
                tacticalChannel = 50212,
                maxSupportWeight = 25000.0,
                maxSupportRadius = 8.0,
                coordinates = { x = 1300.0, y = 65.0, z = -800.0 },
                status = "FREE",
                mobility = "STATIC"
            }
        }
    }
end

function config_loader.validate_dedicated_field(val)
    if val == nil or type(val) == "string" then
        return true
    end
    if type(val) == "table" then
        local count = 0
        for k, v in pairs(val) do
            if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
                return false
            end
            if type(v) ~= "string" or v == "" then
                return false
            end
            count = count + 1
        end
        for i = 1, count do
            if type(val[i]) ~= "string" or val[i] == "" then
                return false
            end
        end
        return true
    end
    return false
end

function config_loader.validate_config(cfg)
    if type(cfg) ~= "table" then
        return false, "CONFIG_NOT_A_TABLE"
    end
    if type(cfg.sectorId) ~= "string" or cfg.sectorId == "" then
        return false, "MISSING_OR_INVALID_SECTOR_ID"
    end
    if type(cfg.sectorIndex) ~= "number" then
        return false, "MISSING_OR_INVALID_SECTOR_INDEX"
    end
    if type(cfg.baseSecChannel) ~= "number" then
        return false, "MISSING_OR_INVALID_BASE_SEC_CHANNEL"
    end
    if type(cfg.towerAtcChannel) ~= "number" then
        return false, "MISSING_OR_INVALID_TOWER_ATC_CHANNEL"
    end
    if type(cfg.facilities) ~= "table" then
        return false, "MISSING_OR_INVALID_FACILITIES"
    end
    for _, fac in ipairs(cfg.facilities) do
        if type(fac) ~= "table" then
            return false, "INVALID_FACILITY_ENTRY"
        end
        if not config_loader.validate_dedicated_field(fac.dedicatedCraftIds) then
            return false, "INVALID_DEDICATED_CRAFT_IDS"
        end
        if not config_loader.validate_dedicated_field(fac.dedicatedAirframeTypes) then
            return false, "INVALID_DEDICATED_AIRFRAME_TYPES"
        end
    end
    return true, nil
end

function config_loader.load_config(path)
    local targetPath = path or DEFAULT_CONFIG_PATH
    if not fs.exists(targetPath) then
        return config_loader.get_default_config(), nil
    end

    local file = fs.open(targetPath, "r")
    if not file then
        return nil, "CANNOT_OPEN_FILE"
    end

    local content = file.readAll()
    file.close()

    if not content or content == "" then
        return config_loader.get_default_config(), nil
    end

    local data = textutils.unserializeJSON(content)
    if type(data) ~= "table" then
        return nil, "JSON_PARSE_ERROR"
    end

    local ok, err = config_loader.validate_config(data)
    if not ok then
        return nil, "VALIDATION_FAILED: " .. tostring(err)
    end

    return data, nil
end

function config_loader.save_config(path, cfg)
    local targetPath = path or DEFAULT_CONFIG_PATH
    local ok, err = config_loader.validate_config(cfg)
    if not ok then
        return false, "INVALID_CONFIG: " .. tostring(err)
    end

    local jsonStr = textutils.serializeJSON(cfg)
    if not jsonStr then
        return false, "JSON_SERIALIZE_ERROR"
    end

    local parentDir = fs.getDir(targetPath)
    if parentDir and parentDir ~= "" and not fs.exists(parentDir) then
        fs.makeDir(parentDir)
    end

    local tmpPath = targetPath .. ".tmp"
    local file = fs.open(tmpPath, "w")
    if not file then
        return false, "CANNOT_WRITE_TEMP_FILE"
    end

    file.write(jsonStr)
    file.close()

    if fs.exists(targetPath) then
        fs.delete(targetPath)
    end
    fs.move(tmpPath, targetPath)

    return true, nil
end

return config_loader
