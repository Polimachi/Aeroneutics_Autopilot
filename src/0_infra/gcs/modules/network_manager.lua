-- src/0_infra/gcs/modules/network_manager.lua
-- Network manager for GCS CH 50000 bootstrap and target craft RF routing
-- UAFS Ecosystem standard envelope v1.9.5

local network_manager = {}

local ENVELOPE_VERSION = "1.9.5"
local OFFSET_C2 = 0         -- Base + 0: CH_OPERATOR_C2 (FCP)
local OFFSET_ESTOP = 1      -- Base + 1: CH_FLIGHT_GUIDANCE (VAS direct)
local OFFSET_TELEMETRY = 3  -- Base + 3: CH_MFD_INSTRUMENT (FCP)

local function get_time_ms()
    if os.epoch then
        return os.epoch("utc")
    end
    return math.floor(os.time() * 1000)
end

function network_manager.init(config, modem)
    local cfg_sys = (config and config.system) or {}
    local cfg_chan = (config and config.channels) or {}

    local ctx = {
        domainId = cfg_sys.domainId or cfg_sys.id or "GCS_01",
        bootstrap_channel = cfg_chan.bootstrapChannel or 50000,
        modem = modem,
        seq = 0,
        active_base = nil,
        open_channels = {}
    }
    return ctx
end

local function build_envelope(ctx, msg_type, payload)
    ctx.seq = ctx.seq + 1
    return {
        ver = ENVELOPE_VERSION,
        domainId = ctx.domainId,
        seq = ctx.seq,
        type = msg_type,
        time = get_time_ms(),
        payload = payload
    }
end

function network_manager.open_bootstrap_channel(ctx)
    if not ctx or not ctx.modem then return false end
    ctx.modem:open(ctx.bootstrap_channel)
    ctx.open_channels[ctx.bootstrap_channel] = true
    return true
end

function network_manager.close_bootstrap_channel(ctx)
    if not ctx or not ctx.modem then return false end
    ctx.modem:close(ctx.bootstrap_channel)
    ctx.open_channels[ctx.bootstrap_channel] = nil
    return true
end

function network_manager.set_active_craft(ctx, base_channel)
    if not ctx or not ctx.modem then return false end

    if ctx.active_base and ctx.active_base ~= base_channel then
        local old_telem_ch = ctx.active_base + OFFSET_TELEMETRY
        ctx.modem:close(old_telem_ch)
        ctx.open_channels[old_telem_ch] = nil
    end

    if base_channel then
        local new_telem_ch = base_channel + OFFSET_TELEMETRY
        ctx.modem:open(new_telem_ch)
        ctx.open_channels[new_telem_ch] = true
    end

    ctx.active_base = base_channel
    return true
end

function network_manager.send_block_assign(ctx, reply_ch, payload)
    if not ctx or not ctx.modem or not reply_ch or not payload then
        return false
    end
    local env = build_envelope(ctx, "MSG_BLOCK_ASSIGN", payload)
    ctx.modem:transmit(reply_ch, ctx.bootstrap_channel, env)
    return true
end

function network_manager.send_c2_command(ctx, target_base, cmd_payload)
    if not ctx or not ctx.modem or not target_base or not cmd_payload then
        return false
    end
    local env = build_envelope(ctx, "MSG_OPERATOR_CMD", cmd_payload)
    ctx.modem:transmit(target_base + OFFSET_C2, ctx.bootstrap_channel, env)
    return true
end

function network_manager.send_emergency_override(ctx, target_base, estop_payload)
    if not ctx or not ctx.modem or not target_base or not estop_payload then
        return false
    end
    local env = build_envelope(ctx, "MSG_EMERGENCY_OVERRIDE", estop_payload)
    ctx.modem:transmit(target_base + OFFSET_ESTOP, ctx.bootstrap_channel, env)
    return true
end

function network_manager.parse_envelope(raw_msg)
    if type(raw_msg) ~= "table" then
        return nil, "message is not a table"
    end
    if raw_msg.ver ~= ENVELOPE_VERSION then
        return nil, "unsupported envelope version: " .. tostring(raw_msg.ver)
    end
    if type(raw_msg.type) ~= "string" or raw_msg.type == "" then
        return nil, "invalid or missing message type"
    end
    if type(raw_msg.domainId) ~= "string" then
        return nil, "invalid or missing domainId"
    end
    if type(raw_msg.payload) ~= "table" then
        return nil, "payload must be a table"
    end
    return raw_msg, nil
end

return network_manager
