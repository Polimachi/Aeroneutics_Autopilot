-- src/3_planning/amm/modules/network_manager.lua
-- AMM Network Manager: ICD v1.9.5 Envelopes & Multi-Channel Routing
local network_manager = {}
network_manager.__index = network_manager

local function is_finite_int(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and math.floor(v) == v
end

function network_manager.new(config)
    local cfg = config or {}
    local self = setmetatable({
        domainId = cfg.domainId or "AIRCRAFT_01",
        baseChannel = cfg.baseChannel or 10000,
        seq = 0,
        modem = nil,
        openPayloadChannels = {},
    }, network_manager)
    return self
end

function network_manager:bind_modem(modem_obj)
    self.modem = modem_obj
    if self.modem then
        pcall(function()
            self.modem.open(self.baseChannel + 0)
            self.modem.open(self.baseChannel + 3)
        end)
    end
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

function network_manager:send_operator_cmd(command, flightMode, params, emergencyAction, authority)
    local payload = {
        authority = authority or "PILOT_PRIMARY",
        command = command or "CRUISE",
        flightMode = flightMode or "CRUISE",
        params = params or {},
        emergencyAction = emergencyAction or "NONE",
    }
    local pkt = self:encode_envelope("MSG_OPERATOR_CMD", payload)
    if not self.modem then
        return false, "MODEM_UNBOUND"
    end
    local ok, err = pcall(function()
        self.modem.transmit(self.baseChannel + 0, self.baseChannel + 0, pkt)
    end)
    return ok, err
end

function network_manager:send_emergency_override(action, reason)
    local now_ms = (os.epoch and os.epoch("utc")) or (os.time() * 1000)
    local payload = {
        action = action or "CUTOFF",
        reason = reason or "PILOT_ESTOP_HOTKEY",
        source = "MFD",
        timestamp = now_ms,
    }
    local pkt = self:encode_envelope("MSG_EMERGENCY_OVERRIDE", payload)
    if not self.modem then
        return false, "MODEM_UNBOUND"
    end
    local ok, err = pcall(function()
        self.modem.transmit(self.baseChannel + 1, self.baseChannel + 1, pkt)
    end)
    return ok, err
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
    if not self.modem then return false, "MODEM_UNBOUND" end
    local ok, m_err = pcall(function()
        self.modem.open(ch)
    end)
    if not ok then return false, m_err end
    self.openPayloadChannels[ch] = true
    return true, ch
end

function network_manager:close_payload_channel(channel_or_offset)
    local ch, err = self:resolve_payload_channel(channel_or_offset)
    if not ch then return false, err end
    if self.modem and type(self.modem.close) == "function" then
        local ok, m_err = pcall(function()
            self.modem.close(ch)
        end)
        if not ok then
            return false, m_err
        end
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
    if not self.modem then return false, "MODEM_UNBOUND" end
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
        self.modem.transmit(ch, ch, pkt)
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
    if not self.modem then
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
        self.modem.transmit(self.baseChannel + 0, self.baseChannel + 0, pkt)
    end)
    return ok, err
end

return network_manager
