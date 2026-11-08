-- Configuration Manager for ASA (Aerodynamic Surface Actuator JSON Parser & Channel Binder v1.5.0)
local config_manager = {}

config_manager.CRAFT_BASE_MIN = 10000
config_manager.CRAFT_BASE_MAX = 49960
config_manager.CRAFT_BANDWIDTH = 40
config_manager.ACTUATION_OFFSET = 11

config_manager.default_cfg = {
    schemaVersion = "1.0.0",
    podId = "ASA_L",
    aircraftDomainId = "AIRCRAFT_01",
    aircraftIndexN = 1,
    baseChannel = 10000,
    channels = { surfaceActuation = 10011 },
    ports = {
        modemSide = "top",
        redstoneSide = "bottom"
    },
    watchdogTimeoutMs = 300,
    debug = true
}

--- Master ICD Base formula: Base = 10000 + (N - 1) * 40
function config_manager.compute_base(n)
    local idx = tonumber(n)
    if not idx or idx < 1 or idx > 1000 or math.floor(idx) ~= idx then
        return nil, "ERR_INDEX_OUT_OF_RANGE"
    end
    return 10000 + (idx - 1) * 40
end

--- Generate fresh copy of default configuration
function config_manager.default_config()
    return {
        schemaVersion = "1.0.0",
        podId = "ASA_L",
        aircraftDomainId = "AIRCRAFT_01",
        aircraftIndexN = 1,
        baseChannel = 10000,
        channels = { surfaceActuation = 10011 },
        ports = {
            modemSide = "top",
            redstoneSide = "bottom"
        },
        watchdogTimeoutMs = 300,
        debug = true
    }
end

--- Load and validate ASA configuration from JSON file
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
    cfg.podId = tostring(cfg.podId or "ASA_L")
    cfg.aircraftDomainId = tostring(cfg.aircraftDomainId or "AIRCRAFT_01")
    cfg.aircraftIndexN = tonumber(cfg.aircraftIndexN) or 1
    cfg.baseChannel = tonumber(cfg.baseChannel) or (config_manager.compute_base(cfg.aircraftIndexN) or 10000)
    cfg.channels = cfg.channels or {}
    cfg.channels.surfaceActuation = tonumber(cfg.channels.surfaceActuation) or (cfg.baseChannel + config_manager.ACTUATION_OFFSET)
    cfg.watchdogTimeoutMs = tonumber(cfg.watchdogTimeoutMs) or 300

    if not cfg.ports or type(cfg.ports) ~= "table" then
        cfg.ports = { modemSide = "top", redstoneSide = "bottom" }
    else
        cfg.ports.modemSide = cfg.ports.modemSide or "top"
        cfg.ports.redstoneSide = cfg.ports.redstoneSide or "bottom"
    end

    if cfg.debug == nil then
        cfg.debug = true
    else
        cfg.debug = (cfg.debug == true)
    end

    return cfg, "OK"
end

--- Save ASA configuration table to JSON file
function config_manager.save(path, cfg)
    path = path or "config.json"
    if not cfg or type(cfg) ~= "table" then return false, "INVALID_CONFIG_DATA" end
    if not fs or not textutils then return false, "ENVIRONMENT_UNSUPPORTED" end

    if cfg.debug == nil then
        cfg.debug = true
    else
        cfg.debug = (cfg.debug == true)
    end

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
