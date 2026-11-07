-- Configuration Manager for TCA (JSON Parser & Channel Binder v1.4.0)
local config_manager = {}

--- Master ICD Base formula: Base = 10000 + (N - 1) * 20
function config_manager.compute_base(n)
    return 10000 + ((tonumber(n) or 1) - 1) * 20
end

--- Migrate configs saved with the deprecated formula (10000 + N * 20)
function config_manager.migrate_legacy_base(cfg)
    local legacyBase = 10000 + cfg.aircraftIndexN * 20
    if tonumber(cfg.baseChannel) ~= legacyBase then return false end
    local newBase = config_manager.compute_base(cfg.aircraftIndexN)
    cfg.baseChannel = newBase
    cfg.channels = cfg.channels or {}
    if tonumber(cfg.channels.thrustActuation) == legacyBase + 6 then cfg.channels.thrustActuation = newBase + 6 end
    if tonumber(cfg.channels.calibration) == legacyBase + 4 then cfg.channels.calibration = newBase + 4 end
    return true
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
    cfg.baseChannel = tonumber(cfg.baseChannel) or config_manager.compute_base(cfg.aircraftIndexN)
    cfg.migratedLegacyBase = config_manager.migrate_legacy_base(cfg) or nil
    cfg.channels = cfg.channels or {}
    cfg.channels.thrustActuation = tonumber(cfg.channels.thrustActuation) or (cfg.baseChannel + 6)
    cfg.channels.calibration = tonumber(cfg.channels.calibration) or (cfg.baseChannel + 4)
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
