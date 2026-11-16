-- src/0_infra/runway/modules/config_store.lua
-- Configuration store, schema validator, and atomic JSON persistence for Runway

local config_store = {}

local DEFAULT_CONFIG_PATH = "/runway/config.json"

local function non_empty_str(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function normalize_mobility(v, fallback)
    local raw = non_empty_str(v)
    if not raw then return fallback end
    local upper = string.upper(raw)
    if upper == "STATIC" or upper == "DYNAMIC" then return upper end
    return raw
end

function config_store.get_default_config()
    return {
        version = "1.12.0",
        facilityId = "RWY_ALPHA_09L",
        sectorId = 1,
        runwayIndex = 1,
        mobility = "DYNAMIC",
        gacChannel = 50201,
        sectorFacilityChannel = 50202,
        sectorGpsReplyChannel = 50206,
        tacticalChannel = 50211,
        channels = {
            sectorChannel = 50201,
            sectorFacilityChannel = 50202,
            sectorGpsReplyChannel = 50206,
            tacticalChannel = 50211,
        },
        mountingYawOffset = 0.0,
        position = { x = 0.0, y = 64.0, z = 0.0 },
        touchdownOffset = { forward = 0.0, right = 0.0, up = 0.0 },
        endOffset = { forward = 200.0, right = 0.0, up = 0.0 },
        approachHeading = 90.0,
        approachDirection = "FRONT",
        glideSlopeAngle = 3.0,
        touchdownZoneLength = 80.0,
        wirelessModemSide = "top",
        slotDurationSec = 120,
    }
end

config_store.create_default = config_store.get_default_config

function config_store.normalize_config(raw)
    local cfg = {}
    if type(raw) == "table" then
        for k, v in pairs(raw) do cfg[k] = v end
    end
    local def = config_store.get_default_config()
    local secId = tonumber(cfg.sectorId) or def.sectorId
    local rIdx = tonumber(cfg.runwayIndex) or def.runwayIndex
    local baseSec = 50001 + secId * 200
    local inCh = type(cfg.channels) == "table" and cfg.channels or {}

    cfg.version = non_empty_str(cfg.version) or def.version
    cfg.facilityId = non_empty_str(cfg.facilityId) or def.facilityId
    cfg.sectorId = secId
    cfg.runwayIndex = rIdx
    cfg.mobility = normalize_mobility(cfg.mobility, def.mobility)
    cfg.gacChannel = tonumber(cfg.gacChannel) or tonumber(inCh.sectorChannel) or baseSec
    cfg.sectorFacilityChannel = tonumber(cfg.sectorFacilityChannel) or tonumber(inCh.sectorFacilityChannel) or (baseSec + 1)
    cfg.sectorGpsReplyChannel = tonumber(cfg.sectorGpsReplyChannel) or tonumber(inCh.sectorGpsReplyChannel) or (baseSec + 5)
    cfg.tacticalChannel = tonumber(cfg.tacticalChannel) or tonumber(inCh.tacticalChannel) or (baseSec + 10 + (rIdx - 1))
    cfg.channels = {
        sectorChannel = cfg.gacChannel,
        sectorFacilityChannel = cfg.sectorFacilityChannel,
        sectorGpsReplyChannel = cfg.sectorGpsReplyChannel,
        tacticalChannel = cfg.tacticalChannel,
    }
    cfg.mountingYawOffset = tonumber(cfg.mountingYawOffset) or def.mountingYawOffset
    cfg.position = type(cfg.position) == "table" and cfg.position or def.position
    cfg.touchdownOffset = type(cfg.touchdownOffset) == "table" and cfg.touchdownOffset or def.touchdownOffset
    cfg.endOffset = type(cfg.endOffset) == "table" and cfg.endOffset or def.endOffset
    cfg.approachHeading = tonumber(cfg.approachHeading) or def.approachHeading
    cfg.approachDirection = non_empty_str(cfg.approachDirection) or def.approachDirection
    cfg.glideSlopeAngle = tonumber(cfg.glideSlopeAngle) or def.glideSlopeAngle
    cfg.touchdownZoneLength = tonumber(cfg.touchdownZoneLength) or def.touchdownZoneLength
    cfg.wirelessModemSide = non_empty_str(cfg.wirelessModemSide) or def.wirelessModemSide
    cfg.slotDurationSec = tonumber(cfg.slotDurationSec) or def.slotDurationSec
    return cfg
end

function config_store.validate_config(cfg)
    if type(cfg) ~= "table" then return false, "CONFIG_NOT_A_TABLE" end
    if type(cfg.facilityId) ~= "string" or cfg.facilityId == "" then
        return false, "MISSING_OR_INVALID_FACILITY_ID"
    end
    if type(cfg.sectorId) ~= "number" then return false, "MISSING_OR_INVALID_SECTOR_ID" end
    if type(cfg.runwayIndex) ~= "number" then return false, "MISSING_OR_INVALID_RUNWAY_INDEX" end
    if cfg.mobility ~= "STATIC" and cfg.mobility ~= "DYNAMIC" then
        return false, "INVALID_MOBILITY"
    end
    if type(cfg.tacticalChannel) ~= "number" then return false, "MISSING_OR_INVALID_TACTICAL_CHANNEL" end
    return true, nil
end

function config_store.load_config(path)
    local targetPath = path or DEFAULT_CONFIG_PATH
    if not fs.exists(targetPath) then return config_store.get_default_config(), nil end
    local file = fs.open(targetPath, "r")
    if not file then return nil, "CANNOT_OPEN_FILE" end
    local content = file.readAll()
    file.close()
    if not content or content == "" then return config_store.get_default_config(), nil end
    local data = textutils.unserializeJSON(content)
    if type(data) ~= "table" then return nil, "JSON_PARSE_ERROR" end
    local normalized = config_store.normalize_config(data)
    local ok, err = config_store.validate_config(normalized)
    if not ok then return nil, "VALIDATION_FAILED: " .. tostring(err) end
    return normalized, nil
end

function config_store.save_config(path, cfg)
    local targetPath = path or DEFAULT_CONFIG_PATH
    local ok, err = config_store.validate_config(cfg)
    if not ok then return false, "INVALID_CONFIG: " .. tostring(err) end
    local jsonStr = textutils.serializeJSON(cfg)
    if not jsonStr then return false, "JSON_SERIALIZE_ERROR" end
    local dir = fs.getDir(targetPath)
    if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local tmp = targetPath .. ".tmp"
    local file = fs.open(tmp, "w")
    if not file then return false, "CANNOT_WRITE_TEMP_FILE" end
    file.write(jsonStr)
    file.close()
    if fs.exists(targetPath) then fs.delete(targetPath) end
    fs.move(tmp, targetPath)
    return true, nil
end

return config_store
