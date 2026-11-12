-- src/3_planning/amm/modules/network_manager.lua
-- AMM Network Manager: ICD v1.9.5 Envelopes, Dual-Modem Binding & Multi-Channel Routing
local network_manager = {}
network_manager.__index = network_manager

local function is_finite_int(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and math.floor(v) == v
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
    local self = setmetatable({
        domainId = cfg.domainId or "AIRCRAFT_01",
        baseChannel = cfg.baseChannel or 10000,
        seq = 0,
        modem = nil,
        onboardModem = nil,
        infraModem = nil,
        modemFallbackActive = false,
        openPayloadChannels = {},
        openInfraChannels = {},
    }, network_manager)
    return self
end

function network_manager:bind_modems(top_modem, back_modem, base_ch)
    if base_ch then self.baseChannel = base_ch end
    local base = self.baseChannel
    local on_chs = { base + 0, base + 2, base + 3, base + 4, base + 5 }
    local inf_chs = { 50000, 50001, 50003, 50004, 60002 }

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
end

function network_manager:bind_modem(modem_obj)
    self:bind_modems(modem_obj, modem_obj, self.baseChannel)
end

function network_manager:apply_rebind(new_base)
    if not new_base then return false, "INVALID_BASE" end
    local old_base = self.baseChannel
    local m = self.onboardModem or self.modem
    close_ch_list(m, { old_base + 0, old_base + 2, old_base + 3, old_base + 4, old_base + 5 })
    open_ch_list(m, { new_base + 0, new_base + 2, new_base + 3, new_base + 4, new_base + 5 })
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

function network_manager:send_mfd_state(payload, activeSource)
    if activeSource == "MFD_ACRO" then
        return false, "YIELDED_TO_MFD_ACRO"
    end
    local pkt = self:encode_envelope("MSG_MFD_STATE", payload)
    local m = self.onboardModem or self.modem
    if not m then return false, "MODEM_UNBOUND" end
    local ok, err = pcall(function()
        m.transmit(self.baseChannel + 3, self.baseChannel + 3, pkt)
    end)
    return ok, err
end

function network_manager:send_operator_cmd(command, flightMode, params, emergencyAction, authority)
    local payload = {
        authority = authority or "PILOT_PRIMARY",
        command = command or "CRUISE",
        flightMode = flightMode or "CRUISE",
        params = params or {},
        emergencyAction = emergencyAction or "NONE",
    }
    local pkt = self:encode_envelope("MSG_OPERATOR_CMD", payload)
    local m = self.onboardModem or self.modem
    if not m then return false, "MODEM_UNBOUND" end
    local ok, err = pcall(function()
        m.transmit(self.baseChannel + 0, self.baseChannel + 0, pkt)
    end)
    return ok, err
end

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
        m.transmit(self.baseChannel + 1, self.baseChannel + 1, pkt)
    end)
    return ok, err
end

function network_manager:send_gps_request(pkt_or_payload)
    local pkt = (pkt_or_payload and pkt_or_payload.ver) and pkt_or_payload
        or self:encode_envelope("MSG_GPS_REQUEST", pkt_or_payload)
    local m = self.infraModem or self.modem
    if not m then return false, "MODEM_UNBOUND" end
    local ok, err = pcall(function()
        m.transmit(60001, self.baseChannel + 5, pkt)
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

function network_manager:close_infra_channel(channel)
    if not is_finite_int(channel) then return false, "INVALID_CHANNEL" end
    local m = self.infraModem or self.modem
    if m and type(m.close) == "function" then
        pcall(function() m.close(channel) end)
    end
    self.openInfraChannels[channel] = nil
    return true, channel
end

function network_manager:is_payload_channel(channel)
    if not is_finite_int(channel) then
        return false
    end
    return channel >= self.baseChannel + 20 and channel <= self.baseChannel + 29
end

function network_manager:resolve_payload_channel(channel_or_offset)
    if not is_finite_int(channel_or_offset) then
        return nil, "INVALID_ZONE3_CHANNEL"
    end
    if channel_or_offset >= 20 and channel_or_offset <= 29 then
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
    if m and type(m.close) == "function" then
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
    if not was_open and not options.keepOpen and self.openPayloadChannels[ch] then
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

return network_manager
