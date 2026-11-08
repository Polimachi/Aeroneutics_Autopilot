-- src/0_infra/landing_pad/modules/config_store.lua
-- Configuration store, schema validator, and atomic JSON persistence for Landing Pad

local config_store = {}

local DEFAULT_CONFIG_PATH = "/landing_pad/config.json"

function config_store.get_default_config()
    return {
        version = "2.4.0",
        facilityId = "PAD_BRAVO_01",
        sectorId = 1,
        padIndex = 1,
        mobility = "DYNAMIC",
        gacChannel = 50201,
        sectorFacilityChannel = 50202,
        sectorGpsReplyChannel = 50206,
        tacticalChannel = 50211,
        mountingYawOffset = 0.0,
        bodyOffset = {
            forward = 0.0,
            right = 0.0,
            up = 0.0
        },
        staticPosition = nil,
        approachHeading = 180.0,
        safeDescentRate = 1.0,
        clearanceZoneRadius = 5.0,
        maxSupportedWeight = 45000.0,
        wirelessModemSide = "top",
        slotDurationSec = 120
    }
end

function config_store.validate_config(cfg)
    if type(cfg) ~= "table" then
        return false, "CONFIG_NOT_A_TABLE"
    end
    if type(cfg.facilityId) ~= "string" or cfg.facilityId == "" then
        return false, "MISSING_OR_INVALID_FACILITY_ID"
    end
    if type(cfg.sectorId) ~= "number" then
        return false, "MISSING_OR_INVALID_SECTOR_ID"
    end
    if type(cfg.padIndex) ~= "number" then
        return false, "MISSING_OR_INVALID_PAD_INDEX"
    end
    if type(cfg.tacticalChannel) ~= "number" then
        return false, "MISSING_OR_INVALID_TACTICAL_CHANNEL"
    end
    if type(cfg.gacChannel) ~= "number" then
        return false, "MISSING_OR_INVALID_GAC_CHANNEL"
    end
    if type(cfg.sectorFacilityChannel) ~= "number" then
        return false, "MISSING_OR_INVALID_SECTOR_FACILITY_CHANNEL"
    end
    return true, nil
end

function config_store.load_config(path)
    local targetPath = path or DEFAULT_CONFIG_PATH
    if not fs.exists(targetPath) then
        return config_store.get_default_config(), nil
    end

    local file = fs.open(targetPath, "r")
    if not file then
        return nil, "CANNOT_OPEN_FILE"
    end

    local content = file.readAll()
    file.close()

    if not content or content == "" then
        return config_store.get_default_config(), nil
    end

    local data = textutils.unserializeJSON(content)
    if type(data) ~= "table" then
        return nil, "JSON_PARSE_ERROR"
    end

    local ok, err = config_store.validate_config(data)
    if not ok then
        return nil, "VALIDATION_FAILED: " .. tostring(err)
    end

    return data, nil
end

function config_store.save_config(path, cfg)
    local targetPath = path or DEFAULT_CONFIG_PATH
    local ok, err = config_store.validate_config(cfg)
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

return config_store
