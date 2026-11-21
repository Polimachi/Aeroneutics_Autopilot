-- src/0_infra/pocket_pda/modules/pda_network.lua
-- Pocket PDA 40-channel aircraft + 10-channel hangar RF network router (ICD v1.9.5)

local pda_network = {}

pda_network.PROTO_VERSION = "1.9.5"
pda_network.CRAFT_BASE_MIN = 10000
pda_network.CRAFT_BASE_MAX = 49960
pda_network.CRAFT_BANDWIDTH = 40
pda_network.HANGAR_BASE_MIN = 101
pda_network.HANGAR_BANDWIDTH = 10
pda_network.MAX_HANGAR_BAYS = 10
pda_network.CH_GCS_BOOTSTRAP = 50000
pda_network.CH_MISSION_ACK = 50004
pda_network.AIRCRAFT_OFFSETS = { 0, 2, 3, 8, 9 }

local function is_finite_int(v)
    return type(v) == "number"
        and v == v
        and v ~= math.huge
        and v ~= -math.huge
        and math.floor(v) == v
end

local function get_time_ms(now_ms)
    if type(now_ms) == "number" then
        return now_ms
    end
    if os and os.epoch then
        return os.epoch("utc")
    end
    if os and os.time then
        return math.floor(os.time() * 1000)
    end
    return 0
end

local function modem_open(m, ch)
    if not m or type(m.open) ~= "function" then
        return false, "ERR_MODEM_NO_OPEN"
    end
    local ok, res, res_err = pcall(m.open, ch)
    if not ok then
        return false, tostring(res or "ERR_MODEM_OPEN")
    end
    if res == false then
        return false, tostring(res_err or "ERR_MODEM_OPEN")
    end
    return true, nil
end

local function modem_close(m, ch)
    if not m or type(m.close) ~= "function" then
        return false, "ERR_MODEM_NO_CLOSE"
    end
    local ok, res, res_err = pcall(m.close, ch)
    if not ok then
        return false, tostring(res or "ERR_MODEM_CLOSE")
    end
    if res == false then
        return false, tostring(res_err or "ERR_MODEM_CLOSE")
    end
    return true, nil
end

local function modem_transmit(m, ch, reply_ch, pkt)
    if not m or type(m.transmit) ~= "function" then return false end
    local ok = pcall(m.transmit, ch, reply_ch, pkt)
    if not ok then
        ok = pcall(m.transmit, m, ch, reply_ch, pkt)
    end
    return ok
end

local function is_wireless_modem(m)
    if type(m) ~= "table" then return false end
    if type(m.isWireless) ~= "function" then return true end
    local ok, wireless = pcall(m.isWireless, m)
    return ok and (wireless == true)
end

function pda_network.compute_craft_base(aircraft_index_n)
    if not is_finite_int(aircraft_index_n) or aircraft_index_n < 1 or aircraft_index_n > 1000 then
        return nil, "ERR_AIRCRAFT_INDEX_RANGE"
    end
    return pda_network.CRAFT_BASE_MIN + (aircraft_index_n - 1) * pda_network.CRAFT_BANDWIDTH, nil
end

function pda_network.compute_hangar_base(bay_id)
    if not is_finite_int(bay_id) or bay_id < 1 or bay_id > pda_network.MAX_HANGAR_BAYS then
        return nil, "ERR_HANGAR_BAY_RANGE"
    end
    return pda_network.HANGAR_BASE_MIN + (bay_id - 1) * pda_network.HANGAR_BANDWIDTH, nil
end

function pda_network.default_domain_for_index(aircraft_index_n)
    local n = tonumber(aircraft_index_n) or 1
    n = math.max(1, math.floor(n))
    return string.format("AIRCRAFT_%02d", n)
end

function pda_network.resolve_modem(modem_side, modem_override)
    if type(modem_override) == "table"
        and (type(modem_override.transmit) == "function" or type(modem_override.open) == "function") then
        return modem_override
    end
    if not peripheral then return nil end

    -- Boot-smoke environments attach monitor on "back"; verify type before wrapping.
    if type(modem_side) == "string" and modem_side ~= ""
        and peripheral.getType and peripheral.getType(modem_side) == "modem" then
        local m = peripheral.wrap and peripheral.wrap(modem_side)
        if is_wireless_modem(m) then
            return m
        end
    end

    if peripheral.find then
        local wireless = peripheral.find("modem", function(_, m)
            return m and (m.isWireless == nil or is_wireless_modem(m))
        end)
        if wireless then
            return wireless
        end
        return peripheral.find("modem")
    end
    return nil
end

function pda_network.init(cfg, modem_override)
    local c = (type(cfg) == "table") and cfg or {}
    local sys = (type(c.system) == "table") and c.system or {}
    local defs = (type(c.defaults) == "table") and c.defaults or {}
    local chs = (type(c.channels) == "table") and c.channels or {}

    local modem_side = sys.modemSide or c.modemSide or "back"
    local modem = pda_network.resolve_modem(modem_side, modem_override)

    local craft_n = defs.aircraftIndexN or c.defaultAircraftIndexN or 1
    local base_ch = pda_network.compute_craft_base(craft_n)
    if not base_ch then
        craft_n = 1
        base_ch = pda_network.CRAFT_BASE_MIN
    end

    local bay_id = defs.hangarBayId or c.defaultHangarBayId or 1
    local hangar_base = pda_network.compute_hangar_base(bay_id)
    if not hangar_base then
        bay_id = 1
        hangar_base = pda_network.HANGAR_BASE_MIN
    end

    local raw_domain = defs.targetDomainId or c.defaultTargetDomainId
    local has_dom = (type(raw_domain) == "string" and raw_domain ~= "" and raw_domain ~= "*")
    local target_domain = has_dom and raw_domain or pda_network.default_domain_for_index(craft_n)
    local auto_domain
    if defs.autoDomain ~= nil then
        auto_domain = (defs.autoDomain == true)
    else
        auto_domain = not has_dom
    end

    return {
        cfg = c,
        modem = modem,
        pdaDomainId = sys.domainId or c.terminalId or "POCKET_PDA_01",
        aircraftIndexN = craft_n,
        baseChannel = base_ch,
        targetDomainId = target_domain,
        autoDomain = auto_domain,
        hangarBayId = bay_id,
        hangarBaseChannel = hangar_base,
        gcsBootstrapChannel = chs.gcsBootstrapChannel or pda_network.CH_GCS_BOOTSTRAP,
        missionAckChannel = chs.missionAckChannel or pda_network.CH_MISSION_ACK,
        openChannels = {},
        seq = 0,
    }
end

local function set_aircraft_channels(ctx, base_ch, should_open)
    for _, off in ipairs(pda_network.AIRCRAFT_OFFSETS) do
        local ch = base_ch + off
        if should_open then
            if ctx.modem then
                local ok, err = modem_open(ctx.modem, ch)
                if not ok then return false, err end
                ctx.openChannels[ch] = true
            end
        else
            if ctx.modem then
                local ok, err = modem_close(ctx.modem, ch)
                if not ok then return false, err end
            end
            ctx.openChannels[ch] = nil
        end
    end
    return true, nil
end

function pda_network.open_channels(ctx)
    if not ctx or not ctx.modem then
        return false, "ERR_NO_MODEM"
    end
    ctx.openChannels = ctx.openChannels or {}
    local ok_air, err_air = set_aircraft_channels(ctx, ctx.baseChannel, true)
    if not ok_air then return false, err_air end

    local static_channels = {
        ctx.hangarBaseChannel + 1,
        ctx.gcsBootstrapChannel or pda_network.CH_GCS_BOOTSTRAP,
        ctx.missionAckChannel or pda_network.CH_MISSION_ACK,
    }
    for _, ch in ipairs(static_channels) do
        local ok_s, err_s = modem_open(ctx.modem, ch)
        if not ok_s then return false, err_s end
        ctx.openChannels[ch] = true
    end
    return true, nil
end

function pda_network.close_channels(ctx)
    if not ctx then return false, "ERR_NO_CONTEXT" end
    local to_close = {}
    for ch, is_open in pairs(ctx.openChannels or {}) do
        if is_open then
            to_close[#to_close + 1] = ch
        end
    end
    if not ctx.modem then
        for _, ch in ipairs(to_close) do
            ctx.openChannels[ch] = nil
        end
        return false, "ERR_NO_MODEM"
    end
    for _, ch in ipairs(to_close) do
        local ok, err = modem_close(ctx.modem, ch)
        if not ok then return false, err end
        ctx.openChannels[ch] = nil
    end
    return true, nil
end

function pda_network.rebind_aircraft(ctx, new_n, domain_override)
    if not ctx then return false, "ERR_NO_CONTEXT" end
    local new_base, err = pda_network.compute_craft_base(new_n)
    if not new_base then
        return false, err
    end

    ctx.openChannels = ctx.openChannels or {}
    local old_base = ctx.baseChannel
    if old_base and old_base ~= new_base then
        local ok_close, err_close = set_aircraft_channels(ctx, old_base, false)
        if not ok_close then return false, err_close end
    end

    if ctx.modem then
        local ok_open, err_open = set_aircraft_channels(ctx, new_base, true)
        if not ok_open then return false, err_open end
    end

    local has_dom = (type(domain_override) == "string" and domain_override ~= "" and domain_override ~= "*")
    ctx.aircraftIndexN = new_n
    ctx.baseChannel = new_base
    ctx.targetDomainId = has_dom and domain_override or pda_network.default_domain_for_index(new_n)
    ctx.autoDomain = not has_dom
    return true, nil
end

function pda_network.rebind_hangar_bay(ctx, new_bay_id)
    if not ctx then return false, "ERR_NO_CONTEXT" end
    local new_base, err = pda_network.compute_hangar_base(new_bay_id)
    if not new_base then
        return false, err
    end

    ctx.openChannels = ctx.openChannels or {}
    local old_telem = ctx.hangarBaseChannel and (ctx.hangarBaseChannel + 1) or nil
    local new_telem = new_base + 1

    if old_telem and old_telem ~= new_telem then
        if ctx.modem then
            local ok_close, err_close = modem_close(ctx.modem, old_telem)
            if not ok_close then return false, err_close end
        end
        ctx.openChannels[old_telem] = nil
    end

    if ctx.modem then
        local ok_open, err_open = modem_open(ctx.modem, new_telem)
        if not ok_open then return false, err_open end
        ctx.openChannels[new_telem] = true
    end

    ctx.hangarBayId = new_bay_id
    ctx.hangarBaseChannel = new_base
    return true, nil
end

local function resolve_reply_channel(base_ch, default_offset, reply_offset_or_ch)
    if type(reply_offset_or_ch) == "number" then
        if reply_offset_or_ch >= 40 then
            return reply_offset_or_ch
        end
        return base_ch + reply_offset_or_ch
    end
    return base_ch + default_offset
end

function pda_network.transmit_raw_channel(ctx, channel, reply_channel, pkt_type, payload, domain_override, now_ms)
    if not ctx or not ctx.modem or type(channel) ~= "number" or type(pkt_type) ~= "string" or pkt_type == "" then
        return false, nil
    end
    ctx.seq = (ctx.seq or 0) + 1
    local domain_id = domain_override
    if type(domain_id) ~= "string" or domain_id == "" or domain_id == "*" then
        if type(ctx.targetDomainId) == "string" and ctx.targetDomainId ~= "" and ctx.targetDomainId ~= "*" then
            domain_id = ctx.targetDomainId
        else
            domain_id = pda_network.default_domain_for_index(ctx.aircraftIndexN)
        end
    end

    local env = {
        ver = pda_network.PROTO_VERSION,
        domainId = domain_id,
        seq = ctx.seq,
        type = pkt_type,
        time = get_time_ms(now_ms),
        payload = (type(payload) == "table") and payload or {},
    }
    local ok = modem_transmit(ctx.modem, channel, reply_channel or channel, env)
    if not ok then
        return false, nil
    end
    return true, env
end

function pda_network.transmit_to_aircraft(ctx, offset, reply_offset_or_ch, pkt_type, payload, now_ms)
    if not ctx or type(ctx.baseChannel) ~= "number" or type(offset) ~= "number" then
        return false, nil
    end
    local channel = ctx.baseChannel + offset
    local reply_ch = resolve_reply_channel(ctx.baseChannel, offset, reply_offset_or_ch)
    return pda_network.transmit_raw_channel(ctx, channel, reply_ch, pkt_type, payload, nil, now_ms)
end

function pda_network.transmit_to_hangar(ctx, offset, reply_offset_or_ch, pkt_type, payload, now_ms)
    if not ctx or type(ctx.hangarBaseChannel) ~= "number" or type(offset) ~= "number" then
        return false, nil
    end
    local channel = ctx.hangarBaseChannel + offset
    local reply_ch = resolve_reply_channel(ctx.hangarBaseChannel, 1, reply_offset_or_ch)
    return pda_network.transmit_raw_channel(ctx, channel, reply_ch, pkt_type, payload, nil, now_ms)
end

function pda_network.parse_envelope(raw_msg)
    if type(raw_msg) ~= "table" then
        return nil, "ERR_NOT_TABLE"
    end
    if raw_msg.ver ~= pda_network.PROTO_VERSION then
        return nil, "ERR_VERSION_MISMATCH"
    end
    if type(raw_msg.type) ~= "string" or raw_msg.type == "" then
        return nil, "ERR_INVALID_TYPE"
    end
    if type(raw_msg.payload) ~= "table" then
        return nil, "ERR_INVALID_PAYLOAD"
    end
    return raw_msg, nil
end

return pda_network
