-- src/3_planning/amm/modules/network_manager.lua
-- AMM Network Manager: ICD v1.9.5 Envelopes, Dual-Modem Binding & Multi-Channel Routing
local network_manager = {}
network_manager.__index = network_manager

local ZONE3_MIN_OFFSET = 20
local ZONE3_MAX_OFFSET = 39

local function is_finite_int(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and math.floor(v) == v
end

local function is_zone3_channel_for_base(ch, base)
    return ch >= base + ZONE3_MIN_OFFSET and ch <= base + ZONE3_MAX_OFFSET
end

local function open_ch_list(m, ch_list)
    if not m or type(m.open) ~= "function" then return end
    for _, ch in ipairs(ch_list) do
        pcall(function() m.open(ch) end)
    end
end

local function close_ch_list(m, ch_list)
    if not m or type(m.close) ~= "function" then return end
    for _, ch in ipairs(ch_list) do
        pcall(function() m.close(ch) end)
    end
end

function network_manager.new(config)
    local cfg = config or {}
    local chs = cfg.channels or {}
    local self = setmetatable({
        domainId = cfg.domainId or "AIRCRAFT_01",
        baseChannel = cfg.baseChannel or 10000,
        bootstrapChannel = chs.bootstrapChannel or 50000,
        facilityBeaconChannel = chs.facilityBeaconChannel or 50003,
        runwayDirectoryChannel = chs.runwayDirectoryChannel or 50004,
        atcCommChannel = chs.atcCommChannel or 50001,
        gpsPingChannel = chs.gpsPingChannel or 60001,
        gpsServiceChannel = chs.gpsServiceChannel or 60002,
        seq = 0,
        modem = nil,
        onboardModem = nil,
        infraModem = nil,
        modemFallbackActive = false,
        fullBlockBound = false,
        openPayloadChannels = {},
        openInfraChannels = {},
        otaAgent = nil,
        arbiter = cfg.arbiter or nil,
    }, network_manager)
    return self
end

function network_manager:set_arbiter(arbiter)
    self.arbiter = arbiter
end

local function build_block_channels(base)
    local list = {}
    for off = 0, 39 do
        list[off + 1] = base + off
    end
    return list
end

function network_manager:bind_modems(top_modem, back_modem, base_ch)
    if base_ch then self.baseChannel = base_ch end
    local base = self.baseChannel
    local on_chs = build_block_channels(base)
    local inf_chs = {
        base + 5,
        self.bootstrapChannel or 50000,
        self.atcCommChannel or 50001,
        self.facilityBeaconChannel or 50003,
        self.runwayDirectoryChannel or 50004,
        self.gpsServiceChannel or 60002,
    }

    if top_modem and back_modem and top_modem ~= back_modem then
        self.onboardModem = top_modem
        self.infraModem = back_modem
        self.modem = top_modem
        self.modemFallbackActive = false
        open_ch_list(top_modem, on_chs)
        open_ch_list(back_modem, inf_chs)
    else
        local m = top_modem or back_modem
        self.onboardModem = m
        self.infraModem = m
        self.modem = m
        self.modemFallbackActive = true
        open_ch_list(m, on_chs)
        open_ch_list(m, inf_chs)
    end
    if self.otaAgent then
        self:open_channels(self.otaAgent)
    end
    self.fullBlockBound = true
end

function network_manager:open_channels(ota_agent_inst)
    if not ota_agent_inst then return false end
    self.otaAgent = ota_agent_inst
    local m = self.infraModem or self.modem
    ota_agent_inst.modemApi = m
    if m then
        ota_agent_inst:open_channels()
        return true
    end
    return false
end

function network_manager:bind_modem(modem_obj)
    self:bind_modems(modem_obj, modem_obj, self.baseChannel)
end

function network_manager:apply_rebind(new_base)
    if not is_finite_int(new_base) then return false, "INVALID_BASE" end
    local old_base = self.baseChannel
    local on_m = self.onboardModem or self.modem
    local inf_m = self.infraModem or self.modem
    close_ch_list(on_m, build_block_channels(old_base))
    open_ch_list(on_m, build_block_channels(new_base))
    close_ch_list(inf_m, { old_base + 5 })
    open_ch_list(inf_m, { new_base + 5 })

    local offsets = {}
    for ch, open in pairs(self.openPayloadChannels) do
        if open and is_zone3_channel_for_base(ch, old_base) then
            offsets[#offsets + 1] = ch - old_base
        end
    end
    for _, off in ipairs(offsets) do
        self.openPayloadChannels[old_base + off] = nil
        self.openPayloadChannels[new_base + off] = true
    end

    self.baseChannel = new_base
    return true
end

function network_manager:encode_envelope(packet_type, payload)
    self.seq = self.seq + 1
    local now_ms = (os.epoch and os.epoch("utc")) or (os.time() * 1000)
    return {
        ver = "1.9.5",
        domainId = self.domainId,
        seq = self.seq,
        type = packet_type,
        time = now_ms,
        payload = payload or {},
    }
end

function network_manager:decode_envelope(raw_packet)
    if type(raw_packet) ~= "table" then
        return false, "NON_TABLE_PACKET"
    end
    if raw_packet.ver ~= "1.9.5" then
        return false, "VERSION_MISMATCH"
    end
    if type(raw_packet.type) ~= "string" then
        return false, "INVALID_TYPE"
    end
    if type(raw_packet.payload) ~= "table" then
        return false, "INVALID_PAYLOAD"
    end
    return true, raw_packet
end

function network_manager:send_trajectory_setpoint(payload)
    local pkt = self:encode_envelope("MSG_TRAJECTORY_SETPOINT", payload)
    local m = self.onboardModem or self.modem
    if not m then return false, "MODEM_UNBOUND" end
    local ok, err = pcall(function()
        m.transmit(self.baseChannel + 4, self.baseChannel + 4, pkt)
    end)
    return ok, err
end

function network_manager:send_rebind_command(action, txId, oldBase, newBase)
    local b_old = oldBase or self.baseChannel
    local payload = {
        transactionId = txId,
        action = action,
        oldBaseChannel = b_old,
        newBaseChannel = newBase,
        bandwidth = 40,
    }
    local pkt = self:encode_envelope("MSG_CHANNEL_REBIND", payload)
    local m = self.onboardModem or self.modem
    if not m then return false, "MODEM_UNBOUND" end
    local ok, err = pcall(function()
        m.transmit(b_old + 4, b_old + 4, pkt)
    end)
    return ok, err
end

function network_manager:send_mfd_state(payload, activeSource, now_ms)
    if activeSource == "MFD_ACRO" then
        return false, "YIELDED_TO_MFD_ACRO"
    end
    local arb = (type(activeSource) == "table" and activeSource) or self.arbiter
    if arb and type(arb.can_transmit_mfd) == "function" then
        local ok_tx, yield_reason = arb:can_transmit_mfd(now_ms)
        if not ok_tx then
            return false, yield_reason
        end
    end
    local pkt = self:encode_envelope("MSG_MFD_STATE", payload)
    local m = self.onboardModem or self.modem
    if not m then return false, "MODEM_UNBOUND" end
    local ok, err = pcall(function()
        m.transmit(self.baseChannel + 3, self.baseChannel + 3, pkt)
    end)
    return ok, err
end

local OFFSET_EMERGENCY = 9

function network_manager:send_emergency_override(action, reason, authKey, source)
    local now_ms = (os.epoch and os.epoch("utc")) or (os.time() * 1000)
    local payload = {
        action = action or "E_STOP",
        reason = reason or "PILOT_ESTOP_HOTKEY",
        authKey = authKey or "ESTOP_CONFIRM_KEY",
        source = source or "AMM",
        timestamp = now_ms,
    }
    local pkt = self:encode_envelope("MSG_EMERGENCY_OVERRIDE", payload)
    local m = self.onboardModem or self.modem
    if not m then return false, "MODEM_UNBOUND" end
    local ok, err = pcall(function()
        m.transmit(self.baseChannel + OFFSET_EMERGENCY, self.baseChannel + OFFSET_EMERGENCY, pkt)
    end)
    return ok, err
end

function network_manager:send_gps_request(pkt_or_payload)
    local pkt = (pkt_or_payload and pkt_or_payload.ver) and pkt_or_payload
        or self:encode_envelope("MSG_GPS_REQUEST", pkt_or_payload)
    local m = self.infraModem or self.modem
    if not m then return false, "MODEM_UNBOUND" end
    local ping_ch = self.gpsPingChannel or 60001
    local ok, err = pcall(function()
        m.transmit(ping_ch, self.baseChannel + 5, pkt)
    end)
    return ok, err
end

function network_manager:send_infra_packet(channel, pktType, payload)
    local pkt = self:encode_envelope(pktType, payload)
    local m = self.infraModem or self.modem
    if not m then return false, "MODEM_UNBOUND" end
    local ok, err = pcall(function()
        m.transmit(channel, channel, pkt)
    end)
    return ok, err
end

function network_manager:open_infra_channel(channel)
    if not is_finite_int(channel) then return false, "INVALID_CHANNEL" end
    local m = self.infraModem or self.modem
    if not m then return false, "MODEM_UNBOUND" end
    local ok, err = pcall(function() m.open(channel) end)
    if not ok then return false, err end
    self.openInfraChannels[channel] = true
    return true, channel
end

function network_manager:is_payload_channel(channel)
    if not is_finite_int(channel) then
        return false
    end
    return is_zone3_channel_for_base(channel, self.baseChannel)
end

function network_manager:resolve_payload_channel(channel_or_offset)
    if not is_finite_int(channel_or_offset) then
        return nil, "INVALID_ZONE3_CHANNEL"
    end
    if channel_or_offset >= ZONE3_MIN_OFFSET and channel_or_offset <= ZONE3_MAX_OFFSET then
        return self.baseChannel + channel_or_offset, nil
    end
    if self:is_payload_channel(channel_or_offset) then
        return channel_or_offset, nil
    end
    return nil, "INVALID_ZONE3_CHANNEL"
end

function network_manager:open_payload_channel(channel_or_offset)
    local ch, err = self:resolve_payload_channel(channel_or_offset)
    if not ch then return false, err end
    local m = self.onboardModem or self.modem
    if not m then return false, "MODEM_UNBOUND" end
    local ok, m_err = pcall(function()
        m.open(ch)
    end)
    if not ok then return false, m_err end
    self.openPayloadChannels[ch] = true
    return true, ch
end

function network_manager:close_payload_channel(channel_or_offset)
    local ch, err = self:resolve_payload_channel(channel_or_offset)
    if not ch then return false, err end
    local m = self.onboardModem or self.modem
    if not self.fullBlockBound and m and type(m.close) == "function" then
        pcall(function()
            m.close(ch)
        end)
    end
    self.openPayloadChannels[ch] = nil
    return true, ch
end

function network_manager:close_all_payload_channels()
    local channels = {}
    for ch, open in pairs(self.openPayloadChannels) do
        if open then
            channels[#channels + 1] = ch
        end
    end
    for _, ch in ipairs(channels) do
        self:close_payload_channel(ch)
    end
    return #channels
end

function network_manager:send_payload_req(channel_or_offset, checkpointId, command, params, opts)
    local ch, err = self:resolve_payload_channel(channel_or_offset)
    if not ch then return false, err end
    local m = self.onboardModem or self.modem
    if not m then return false, "MODEM_UNBOUND" end
    local options = opts or {}
    local was_open = (self.openPayloadChannels[ch] == true)
    if not was_open and options.keepOpen == true then
        local ok_open, open_err = self:open_payload_channel(ch)
        if not ok_open then return false, open_err end
    end
    local pkt = self:encode_envelope("MSG_PAYLOAD_REQ", {
        checkpointId = checkpointId,
        command = command,
        replyChannel = ch,
        params = params or {},
    })
    local ok, tx_err = pcall(function()
        m.transmit(ch, ch, pkt)
    end)
    if not was_open and not options.keepOpen then
        self:close_payload_channel(ch)
    end
    if not ok then return false, tx_err end
    return true, ch
end

function network_manager:send_mission_ack(ack_payload)
    if type(ack_payload) ~= "table" then
        return false, "INVALID_ACK_PAYLOAD"
    end
    local m = self.onboardModem or self.modem
    if not m then
        return false, "MODEM_UNBOUND"
    end
    local pkt = self:encode_envelope("MSG_MISSION_ACK", {
        action = ack_payload.action,
        status = ack_payload.status,
        missionId = ack_payload.missionId,
        missionState = ack_payload.missionState,
        activeIndex = ack_payload.activeIndex,
        totalCheckpoints = ack_payload.totalCheckpoints,
        reason = ack_payload.reason,
    })
    local ok, err = pcall(function()
        m.transmit(self.baseChannel + 0, self.baseChannel + 0, pkt)
    end)
    return ok, err
end

function network_manager:send_pbit_req(req_payload)
    local m = self.onboardModem or self.modem
    if not m then
        return false, "MODEM_UNBOUND"
    end
    local p = type(req_payload) == "table" and req_payload or {}
    local pkt = self:encode_envelope("MSG_PBIT_REQ", {
        requestId = tostring(p.requestId or ("PBIT-" .. tostring((os.epoch and os.epoch("utc")) or 0))),
        source = p.source or "AMM",
        runWiggle = (p.runWiggle ~= false),
        busRttMs = p.busRttMs,
        energyFuel = p.energyFuel,
        channelConflict = p.channelConflict,
        targetThrusterId = p.targetThrusterId,
    })
    local ch = self.baseChannel + 8
    local ok, err = pcall(function()
        m.transmit(ch, ch, pkt)
    end)
    return ok, err
end

return network_manager
