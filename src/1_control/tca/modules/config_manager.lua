-- Configuration Manager for TCA (JSON Parser & Channel Binder v1.4.0)
local config_manager = {}

config_manager.CRAFT_BASE_MIN = 10000
config_manager.CRAFT_BASE_MAX = 49960
config_manager.CRAFT_BANDWIDTH = 40
config_manager.ACTUATION_OFFSET = 10

--- Master ICD Base formula: Base = 10000 + (N - 1) * 40
function config_manager.compute_base(n)
    local idx = tonumber(n)
    if not idx or idx < 1 or idx > 1000 or math.floor(idx) ~= idx then
        return nil, "ERR_INDEX_OUT_OF_RANGE"
    end
    return 10000 + (idx - 1) * 40
end

--- Migrate configs saved with deprecated formulas or channels
function config_manager.migrate_legacy_base(cfg)
    if not cfg or type(cfg) ~= "table" then return false end
    local n = tonumber(cfg.aircraftIndexN)
    if not n then return false end
    local base = tonumber(cfg.baseChannel)
    local legacy1 = 10000 + (n - 1) * 20
    local legacy2 = 10000 + n * 20
    local channels = cfg.channels or {}
    local hasLegacyThrust = base and tonumber(channels.thrustActuation) == base + 6
    local hasCalibration = channels.calibration ~= nil
    local hasLegacyBase = base == legacy1 or base == legacy2

    if hasLegacyBase or hasLegacyThrust or hasCalibration then
        local newBase = config_manager.compute_base(n)
        if not newBase then return false end
        cfg.baseChannel = newBase
        cfg.channels = { thrustActuation = newBase + config_manager.ACTUATION_OFFSET }
        cfg.mode = nil
        return true
    end
    return false
end

--- Load and validate TCA configuration from JSON file
function config_manager.load(path)
    path = path or "config.json"
    if not fs or not fs.exists or not fs.exists(path) then
        return nil, "CONFIG_FILE_NOT_FOUND"
    end

    local f = fs.open(path, "r")
    if not f then return nil, "CONFIG_FILE_OPEN_FAILED" end
    local content = f.readAll()
    f.close()

    local cfg = textutils.unserializeJSON(content)
    if type(cfg) ~= "table" then return nil, "INVALID_JSON" end

    -- Defaults & Channel Binding
    cfg.aircraftIndexN = tonumber(cfg.aircraftIndexN) or 1
    cfg.baseChannel = tonumber(cfg.baseChannel) or (config_manager.compute_base(cfg.aircraftIndexN) or 10000)
    cfg.migratedLegacyBase = config_manager.migrate_legacy_base(cfg) or nil
    cfg.channels = cfg.channels or {}
    cfg.channels.thrustActuation = tonumber(cfg.channels.thrustActuation) or (cfg.baseChannel + config_manager.ACTUATION_OFFSET)
    cfg.channels.calibration = nil
    cfg.mode = nil
    cfg.watchdogTimeoutMs = tonumber(cfg.watchdogTimeoutMs) or 300
    cfg.nominalActuatorCount = tonumber(cfg.nominalActuatorCount) or 4
    cfg.deadband = tonumber(cfg.deadband) or 0
    cfg.aircraftDomainId = tostring(cfg.aircraftDomainId or "AIRCRAFT_01")
    cfg.groupId = tostring(cfg.groupId or "THR_MAIN_L")
    cfg.interactionMode = tostring(cfg.interactionMode or "REDSTONE")

    if not cfg.ports or type(cfg.ports) ~= "table" then
        cfg.ports = { modemSide = "top", redstoneSide = "bottom", apiSides = { "left", "right", "front", "back" } }
    else
        cfg.ports.modemSide = cfg.ports.modemSide or "top"
        cfg.ports.redstoneSide = cfg.ports.redstoneSide or "bottom"
        cfg.ports.apiSides = cfg.ports.apiSides or { "left", "right", "front", "back" }
    end

    return cfg, "OK"
end

--- Save TCA configuration table to JSON file
function config_manager.save(path, cfg)
    path = path or "config.json"
    if not cfg or type(cfg) ~= "table" then return false, "INVALID_CONFIG_DATA" end
    if not fs or not textutils then return false, "ENVIRONMENT_UNSUPPORTED" end
    local ser = textutils.serializeJSON or textutils.serialiseJSON
    if not ser then return false, "SERIALIZER_UNAVAILABLE" end
    local content = ser(cfg)
    local f = fs.open(path, "w")
    if not f then return false, "FILE_WRITE_FAILED" end
    f.write(content)
    f.close()
    return true, "OK"
end

return config_manager
