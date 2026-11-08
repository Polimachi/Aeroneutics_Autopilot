-- src/3_planning/amm/modules/network_manager.lua
-- AMM Network Manager: ICD v1.9.5 Envelopes & Multi-Channel Routing
local network_manager = {}
network_manager.__index = network_manager

function network_manager.new(config)
    local cfg = config or {}
    local self = setmetatable({
        domainId = cfg.domainId or "AIRCRAFT_01",
        baseChannel = cfg.baseChannel or 10000,
        seq = 0,
        modem = nil,
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

return network_manager
