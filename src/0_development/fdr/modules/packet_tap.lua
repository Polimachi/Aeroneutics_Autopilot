-- Passive receive-only RF packet tapper and dynamic aircraft [N] binder.
-- NEVER invokes modem.transmit under any execution path.
local packet_tap = {}

local ALLOWED_TYPES_BY_OFFSET = {
    [1] = {
        MSG_ATTITUDE_CMD = true,
        MSG_EMERGENCY_OVERRIDE = true,
        MSG_EMERGENCY_ALERT = true,
    },
    [2] = { MSG_FLIGHT_TELEMETRY = true },
    [4] = {
        MSG_TRAJECTORY_SETPOINT = true,
        MSG_OUTER_LOOP_STATUS = true,
    },
    [10] = {
        MSG_THRUST_CMD = true,
        MSG_ACTUATOR_STATUS = true,
    },
    [11] = {
        MSG_AERO_CMD = true,
        MSG_AERO_STATUS = true,
    },
}

local CONTROL_EVENT_TYPES = {
    MSG_CHANNEL_REBIND = true,
    MSG_CHANNEL_REBIND_ACK = true,
}

--- Compute 40-channel block base address for aircraft N in [1, 1000].
function packet_tap.compute_base(aircraftIndexN)
    local n = tonumber(aircraftIndexN)
    if not n or n ~= math.floor(n) or n < 1 or n > 1000 then
        return nil, "ERR_AIRCRAFT_INDEX_RANGE"
    end
    return 10000 + (n - 1) * 40, nil
end

--- Build tapped channel map from config and resolved baseChannel.
function packet_tap.build_channel_map(cfg, baseChannel)
    local tapOpts = (cfg and cfg.tapOptions) or {}
    local offsets = { 1, 2, 10 }
    if tapOpts.aero ~= false then
        table.insert(offsets, 11)
    end
    if tapOpts.trajectory ~= false then
        table.insert(offsets, 4)
    end
    local byChannel, ordered = {}, {}
    for _, off in ipairs(offsets) do
        local ch = baseChannel + off
        byChannel[ch] = off
        table.insert(ordered, ch)
    end
    return {
        byChannel = byChannel,
        channels = ordered,
    }
end

local function resolve_modem(cfg, modemOverride)
    if modemOverride then return modemOverride end
    if peripheral then
        local side = cfg and cfg.modemSide
        if side and peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
            return peripheral.wrap(side)
        end
        if peripheral.find then
            return peripheral.find("modem", function(_, m)
                return (not m.isWireless) or m.isWireless()
            end)
        end
    end
    return nil
end

--- Initialize passive tap state without transmitting.
function packet_tap.init(cfg, modemOverride)
    local n = (cfg and cfg.aircraftIndexN) or 1
    local base, err = packet_tap.compute_base(n)
    assert(base ~= nil, err or "Invalid aircraftIndexN")
    local cmap = packet_tap.build_channel_map(cfg, base)
    local domain = (cfg and cfg.domainId) or "*"
    return {
        cfg = cfg or {},
        modem = resolve_modem(cfg, modemOverride),
        aircraftIndexN = n,
        baseChannel = base,
        configuredDomainId = domain,
        lockedDomainId = domain,
        channelMap = cmap,
        seqIdx = 0,
        countsByOffset = { [1] = 0, [2] = 0, [4] = 0, [10] = 0, [11] = 0 },
    }
end

--- Open tapped channels on attached modem (read-only receive).
function packet_tap.open_channels(tap)
    if not tap or not tap.modem then return false, "ERR_NO_MODEM" end
    for _, ch in ipairs(tap.channelMap.channels) do
        tap.modem.open(ch)
    end
    return true
end

--- Close currently opened tap channels cleanly.
function packet_tap.close_channels(tap)
    if not tap or not tap.modem then return false end
    for _, ch in ipairs(tap.channelMap.channels) do
        tap.modem.close(ch)
    end
    return true
end

--- Rebind tapper dynamically to aircraft N (closes old channels, opens new ones).
function packet_tap.bind_aircraft(tap, aircraftIndexN, domainIdOrWildcard)
    if not tap then return false, "ERR_NO_TAP" end
    local newBase, err = packet_tap.compute_base(aircraftIndexN)
    if not newBase then return false, err end

    packet_tap.close_channels(tap)
    tap.aircraftIndexN = aircraftIndexN
    tap.baseChannel = newBase
    tap.lockedDomainId = domainIdOrWildcard or tap.cfg.domainId or "*"
    tap.channelMap = packet_tap.build_channel_map(tap.cfg, newBase)
    tap.countsByOffset = { [1] = 0, [2] = 0, [4] = 0, [10] = 0, [11] = 0 }
    local ok, openErr = packet_tap.open_channels(tap)
    if not ok then return false, openErr end
    return true, nil
end

local function is_allowed_type(tap, offset, msgType)
    local allowed = ALLOWED_TYPES_BY_OFFSET[offset]
    if allowed and allowed[msgType] then return true end
    local tapOpts = (tap.cfg and tap.cfg.tapOptions) or {}
    if tapOpts.includeControlEvents == true and CONTROL_EVENT_TYPES[msgType] then
        return true
    end
    return false
end

--- Validate packet envelope and normalize into a FRAME record.
function packet_tap.classify_packet(tap, channel, pkt, rxMs)
    if not tap or not tap.channelMap then return nil, "ERR_NO_TAP" end
    local offset = tap.channelMap.byChannel[channel]
    if not offset then return nil, "ERR_CHANNEL_NOT_TAPPED" end
    if type(pkt) ~= "table" then return nil, "ERR_INVALID_PACKET" end
    if pkt.ver ~= "1.9.5" then return nil, "ERR_UNSUPPORTED_VER" end
    if type(pkt.type) ~= "string" or type(pkt.payload) ~= "table" then
        return nil, "ERR_INVALID_ENVELOPE"
    end
    if tap.lockedDomainId == "*" then
        if type(pkt.domainId) == "string" and pkt.domainId ~= "" and pkt.type == "MSG_FLIGHT_TELEMETRY" then
            tap.lockedDomainId = pkt.domainId
        end
    elseif pkt.domainId ~= tap.lockedDomainId then
        return nil, "ERR_DOMAIN_MISMATCH"
    end
    if not is_allowed_type(tap, offset, pkt.type) then
        return nil, "ERR_FILTERED_MSG_TYPE"
    end

    tap.seqIdx = tap.seqIdx + 1
    tap.countsByOffset[offset] = (tap.countsByOffset[offset] or 0) + 1
    return {
        recordType = "FRAME",
        seqIdx = tap.seqIdx,
        rxMs = rxMs or 0,
        txMs = pkt.time or 0,
        pktSeq = pkt.seq,
        channel = channel,
        offset = offset,
        msgType = pkt.type,
        payload = pkt.payload,
    }, nil
end

--- Return true when a normalized FRAME signals emergency stop.
function packet_tap.is_estop_trigger(record)
    if type(record) ~= "table" or type(record.payload) ~= "table" then
        return false
    end
    if record.msgType == "MSG_EMERGENCY_OVERRIDE" then
        return record.payload.action == "E_STOP"
    end
    if record.msgType == "MSG_EMERGENCY_ALERT" then
        return true
    end
    if record.msgType == "MSG_FLIGHT_TELEMETRY" then
        return record.payload.controlState == "E_STOP"
    end
    return false
end

return packet_tap
