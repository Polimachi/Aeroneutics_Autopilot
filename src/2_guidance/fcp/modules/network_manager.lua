-- src/modules/network_manager.lua
local network_manager = {}
network_manager.PROTO_VERSION = "1.9.5"

network_manager.ZONE_OFFSETS = {
    c2 = 0,
    guidance = 1,
    telemetry = 2,
    mfd = 3,
    navSensor = 4,
    clientReply = 5,
    actuation = 10,
    aero = 11,
    payloadBus = 20,
    weaponBus = 21,
    formationLink = 30,
}

local function safe_unserialize(raw)
    if type(raw) == "table" then return raw end
    if type(raw) == "string" and textutils and textutils.unserializeJSON then
        return textutils.unserializeJSON(raw)
    end
    return nil
end

local function check_modem_side(side, expectWireless)
    if side and peripheral and peripheral.getType and peripheral.getType(side) == "modem" then
        local m = peripheral.wrap(side)
        if m and (expectWireless == nil or m.isWireless == nil or m.isWireless() == expectWireless) then
            return m
        end
    end
    return nil
end

local function scan_modem(expectWireless)
    if peripheral and peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "modem" then
                local m = peripheral.wrap(name)
                if m and (expectWireless == nil or m.isWireless == nil or m.isWireless() == expectWireless) then
                    return m
                end
            end
        end
    end
    if peripheral and peripheral.find then
        return peripheral.find("modem", function(_, dev)
            return dev and (expectWireless == nil or dev.isWireless == nil or dev.isWireless() == expectWireless)
        end)
    end
    return nil
end

local function resolve_modem(ctx, side_hint, expectWireless)
    if ctx and ctx.modem_lookup then
        local m = ctx.modem_lookup(side_hint)
        if m then return m end
    end
    local exp = (expectWireless ~= false)
    return check_modem_side(side_hint, exp)
        or scan_modem(exp)
        or check_modem_side(side_hint, nil)
        or scan_modem(nil)
        or (side_hint and peripheral and peripheral.wrap and peripheral.wrap(side_hint))
        or (peripheral and peripheral.find and peripheral.find("modem"))
end

function network_manager.init(config, modem_lookup_fn)
    local cfg = config or {}
    local sys = cfg.system or {}
    local chs = cfg.channels or {}
    local base_ch = chs.baseChannel or 10000
    return {
        domainId = sys.domainId or "AIRCRAFT_01",
        hardwareUuid = sys.hardwareUuid or "FCP-04",
        baseChannel = base_ch,
        bandwidth = chs.bandwidth or 40,
        bootstrapChannel = chs.bootstrapChannel or 50000,
        atcCommChannel = chs.atcCommChannel or 50001,
        gpsPingChannel = chs.gpsPingChannel or 60001,
        gpsServiceChannel = chs.gpsServiceChannel or 60002,
        facilityBeaconChannel = chs.facilityBeaconChannel or 50003,
        mfdInstrumentChannel = chs.mfdInstrumentChannel or (base_ch + 3),
        primarySide = sys.primaryModemSide or "top",
        infraSide = sys.infraModemSide or "back",
        modem_lookup = modem_lookup_fn,
        seq = 0,
        peer_seqs = {},
        active_guide_ch = nil,
        queues = {
            telemetry = nil, gps = nil, c2 = nil, facility = nil,
            calibration = nil, actuator = nil, probe = nil, rebindAck = nil,
        },
    }
end

function network_manager.encode_envelope(ctx, packetType, payload)
    ctx.seq = (ctx.seq or 0) + 1
    local now_epoch = os.epoch and os.epoch("utc") or 0
    return {
        ver = network_manager.PROTO_VERSION,
        domainId = ctx.domainId,
        senderId = ctx.hardwareUuid,
        type = packetType,
        seq = ctx.seq,
        time = now_epoch,
        payload = payload or {},
    }
end

function network_manager.decode_envelope(rawPacket)
    return safe_unserialize(rawPacket)
end

function network_manager.verify_packet(ctx, packet)
    local pkt = safe_unserialize(packet)
    if not pkt or type(pkt) ~= "table" then return false end
    if pkt.ver ~= network_manager.PROTO_VERSION then return false end
    local d = pkt.domainId
    local allowed_infra = {
        FACILITY_INFRA = true,
        GLOBAL = true,
        GCS = true,
        INFRA = true,
        GPS_BASE_NET = true,
    }
    if d ~= ctx.domainId and not allowed_infra[d] then
        return false
    end
    if pkt.type == "MSG_GPS_RESPONSE" then
        if type(pkt.payload) ~= "table" or not ctx.domainId or pkt.payload.targetClient ~= ctx.domainId then
            return false
        end
    end
    return true
end

function network_manager.bind_bootstrap_channels(ctx)
    local m = resolve_modem(ctx, ctx.infraSide) or resolve_modem(ctx, ctx.primarySide)
    if m and m.open then
        m.open(ctx.bootstrapChannel)
        m.open(ctx.atcCommChannel)
        m.open(ctx.gpsPingChannel or 60001)
        m.open(ctx.gpsServiceChannel or 60002)
        m.open(ctx.facilityBeaconChannel or 50003)
    end
end

function network_manager.bind_aircraft_channels(ctx, base_ch)
    local b = base_ch or ctx.baseChannel
    ctx.baseChannel = b
    ctx.mfdInstrumentChannel = b + 3
    local m = resolve_modem(ctx, ctx.primarySide)
    if m and m.open then
        for offset = 0, 5 do
            m.open(b + offset)
        end
    end
end

function network_manager.rebind_aircraft_channels(ctx, new_base)
    local old_b = ctx.baseChannel
    local m = resolve_modem(ctx, ctx.primarySide)
    if m and m.close then
        for offset = 0, 5 do
            m.close(old_b + offset)
        end
    end
    ctx.baseChannel = new_base
    ctx.mfdInstrumentChannel = new_base + 3
    if m and m.open then
        for offset = 0, 5 do
            m.open(new_base + offset)
        end
    end
end

function network_manager.bind_dynamic_guide_channel(ctx, pad_ch)
    if not pad_ch then return end
    local m = resolve_modem(ctx, ctx.infraSide) or resolve_modem(ctx, ctx.primarySide)
    if m and m.open then
        if ctx.active_guide_ch and ctx.active_guide_ch ~= pad_ch then
            m.close(ctx.active_guide_ch)
        end
        m.open(pad_ch)
        ctx.active_guide_ch = pad_ch
    end
end

local function categorize_packet(ctx, pkt)
    local t = pkt.type
    if t == "MSG_FLIGHT_TELEMETRY" then ctx.queues.telemetry = pkt
    elseif t == "MSG_GPS_RESPONSE" then ctx.queues.gps = pkt
    elseif t == "MSG_OPERATOR_CMD" or t == "MSG_EMERGENCY_CMD" then ctx.queues.c2 = pkt
    elseif t == "MSG_FACILITY_BEACON" or t == "MSG_ATC_CLEARANCE" then ctx.queues.facility = pkt
    elseif t == "MSG_PROFILE_SYNC" then ctx.queues.calibration = pkt
    elseif t == "MSG_ACTUATOR_STATUS" then ctx.queues.actuator = pkt
    elseif t == "MSG_CHANNEL_PROBE" or t == "MSG_CHANNEL_PROBE_ACK" then ctx.queues.probe = pkt
    elseif t == "MSG_CHANNEL_REBIND_ACK" then ctx.queues.rebindAck = pkt
    end
end

function network_manager.ingest_modem_event(ctx, side, ch, reply_ch, msg, dist, now_ms)
    local pkt = safe_unserialize(msg)
    if pkt and network_manager.verify_packet(ctx, pkt) then
        categorize_packet(ctx, pkt)
        return true
    end
    return false
end

function network_manager.poll_all(ctx)
    local res = {
        telemetry = ctx.queues.telemetry,
        gps = ctx.queues.gps,
        c2 = ctx.queues.c2,
        facility = ctx.queues.facility,
        calibration = ctx.queues.calibration,
        actuator = ctx.queues.actuator,
        probe = ctx.queues.probe,
        rebindAck = ctx.queues.rebindAck,
    }
    ctx.queues.telemetry = nil
    ctx.queues.gps = nil
    ctx.queues.c2 = nil
    ctx.queues.facility = nil
    ctx.queues.calibration = nil
    ctx.queues.actuator = nil
    ctx.queues.probe = nil
    ctx.queues.rebindAck = nil
    return res
end

local function transmit_packet(ctx, side, ch, reply_ch, msg_type, payload)
    local m = resolve_modem(ctx, side)
    if not m or not m.transmit then return false end
    local env = network_manager.encode_envelope(ctx, msg_type, payload)
    m.transmit(ch, reply_ch, env)
    return true
end

function network_manager.send_guidance_cmd(ctx, cmd_payload)
    return transmit_packet(ctx, ctx.primarySide, ctx.baseChannel + 1, ctx.baseChannel + 1, "MSG_ATTITUDE_CMD", cmd_payload)
end

function network_manager.send_emergency_override(ctx, em_payload)
    return transmit_packet(ctx, ctx.primarySide, ctx.baseChannel + 1, ctx.baseChannel + 1, "MSG_EMERGENCY_OVERRIDE", em_payload)
end

function network_manager.send_channel_rebind(ctx, rebind_payload)
    return transmit_packet(ctx, ctx.primarySide, ctx.baseChannel + 1, ctx.baseChannel + 1, "MSG_CHANNEL_REBIND", rebind_payload)
end

function network_manager.send_mfd_state(ctx, mfd_payload)
    return transmit_packet(ctx, ctx.primarySide, ctx.baseChannel + 3, ctx.baseChannel + 3, "MSG_MFD_STATE", mfd_payload)
end

function network_manager.send_gps_request(ctx, req_payload)
    return transmit_packet(ctx, ctx.infraSide, ctx.gpsPingChannel or 60001, ctx.baseChannel + 5, "MSG_GPS_REQUEST", req_payload)
end

function network_manager.send_atc_req(ctx, atc_payload)
    return transmit_packet(ctx, ctx.infraSide, ctx.atcCommChannel, ctx.atcCommChannel, "MSG_ATC_APPROACH_REQ", atc_payload)
end

function network_manager.send_touchdown_msg(ctx, td_payload)
    return transmit_packet(ctx, ctx.infraSide, ctx.atcCommChannel, ctx.atcCommChannel, "MSG_TOUCHDOWN_COMPLETE", td_payload)
end

function network_manager.send_mfd_alert(ctx, alert_payload)
    return transmit_packet(ctx, ctx.primarySide, ctx.baseChannel + 3, ctx.baseChannel + 3, "MSG_MFD_ALERT", alert_payload)
end

function network_manager.send_bootstrap_msg(ctx, boot_payload)
    local m_side = ctx.infraSide or ctx.primarySide
    return transmit_packet(ctx, m_side, ctx.bootstrapChannel, ctx.bootstrapChannel, "MSG_BLOCK_REQUEST", boot_payload)
end

return network_manager
