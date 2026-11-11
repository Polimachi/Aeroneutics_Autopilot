-- src/0_infra/landing_pad/modules/config_store.lua
-- Configuration store, schema validator, and atomic JSON persistence for Landing Pad

local config_store = {}

local DEFAULT_CONFIG_PATH = "/landing_pad/config.json"

function config_store.get_default_config()
    return {
        version = "2.4.0",
        ver = "2.4.0",
        facilityId = "PAD_BRAVO_01",
        padId = "PAD_BRAVO_01",
        sectorId = 1,
        sectorIndex = 1,
        padIndex = 1,
        mobility = "DYNAMIC",
        mode = "DYNAMIC",
        gacChannel = 50201,
        sectorFacilityChannel = 50202,
        sectorGpsReplyChannel = 50206,
        tacticalChannel = 50211,
        channels = {
            sectorChannel = 50201,
            sectorFacilityChannel = 50202,
            sectorGpsReplyChannel = 50206,
            tacticalChannel = 50211
        },
        mountingYawOffset = 0.0,
        bodyOffset = {
            forward = 0.0,
            right = 0.0,
            up = 0.0
        },
        staticPosition = nil,
        position = { x = 0.0, y = 64.0, z = 0.0 },
        approachHeading = 180.0,
        safeDescentRate = 1.0,
        clearanceZoneRadius = 5.0,
        maxSupportedWeight = 45000.0,
        wirelessModemSide = "top",
        slotDurationSec = 120
    }
end

config_store.create_default = config_store.get_default_config

function config_store.normalize_config(raw)
    local cfg = {}
    if type(raw) == "table" then
        for k, v in pairs(raw) do cfg[k] = v end
    end
    local def = config_store.get_default_config()
    local fid = tostring(cfg.facilityId or cfg.padId or def.facilityId)
    local secId = tonumber(cfg.sectorId or cfg.sectorIndex) or def.sectorId
    local pIdx = tonumber(cfg.padIndex) or def.padIndex
    local mob = tostring(cfg.mobility or cfg.mode or def.mobility)
    local baseSec = 50001 + secId * 200
    local inCh = type(cfg.channels) == "table" and cfg.channels or {}

    local gacCh = tonumber(inCh.sectorChannel or cfg.gacChannel) or baseSec
    local facCh = tonumber(inCh.sectorFacilityChannel or cfg.sectorFacilityChannel) or (baseSec + 1)
    local gpsCh = tonumber(inCh.sectorGpsReplyChannel or cfg.sectorGpsReplyChannel) or (baseSec + 5)
    local tacCh = tonumber(inCh.tacticalChannel or cfg.tacticalChannel) or (baseSec + 10 + (pIdx - 1))

    cfg.version = tostring(cfg.version or cfg.ver or def.version)
    cfg.ver = tostring(cfg.ver or cfg.version)
    cfg.facilityId = fid
    cfg.padId = fid
    cfg.sectorId = secId
    cfg.sectorIndex = secId
    cfg.padIndex = pIdx
    cfg.mobility = mob
    cfg.mode = mob
    cfg.gacChannel = gacCh
    cfg.sectorFacilityChannel = facCh
    cfg.sectorGpsReplyChannel = gpsCh
    cfg.tacticalChannel = tacCh
    cfg.channels = {
        sectorChannel = gacCh,
        sectorFacilityChannel = facCh,
        sectorGpsReplyChannel = gpsCh,
        tacticalChannel = tacCh,
    }
    cfg.mountingYawOffset = tonumber(cfg.mountingYawOffset) or def.mountingYawOffset
    cfg.bodyOffset = type(cfg.bodyOffset) == "table" and cfg.bodyOffset or { forward = 0.0, right = 0.0, up = 0.0 }
    cfg.position = type(cfg.position) == "table" and cfg.position or { x = 0.0, y = 64.0, z = 0.0 }
    cfg.approachHeading = tonumber(cfg.approachHeading) or def.approachHeading
    cfg.safeDescentRate = tonumber(cfg.safeDescentRate) or def.safeDescentRate
    cfg.clearanceZoneRadius = tonumber(cfg.clearanceZoneRadius) or def.clearanceZoneRadius
    cfg.maxSupportedWeight = tonumber(cfg.maxSupportedWeight) or def.maxSupportedWeight
    cfg.wirelessModemSide = tostring(cfg.wirelessModemSide or def.wirelessModemSide)
    cfg.slotDurationSec = tonumber(cfg.slotDurationSec) or def.slotDurationSec
    return cfg
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

    local normalized = config_store.normalize_config(data)
    local ok, err = config_store.validate_config(normalized)
    if not ok then
        return nil, "VALIDATION_FAILED: " .. tostring(err)
    end

    return normalized, nil
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
