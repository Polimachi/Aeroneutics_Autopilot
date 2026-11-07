-- VAS Dual-Modem Network Router & ICD v1.19.0 Module
local network_manager = {}

network_manager.PROTO_VERSION = "1.9.5"

local function check_modem_side(side, expectWireless)
    if side and peripheral and peripheral.getType and peripheral.getType(side) == "modem" then
        local m = peripheral.wrap(side)
        if m and (m.isWireless == nil or m.isWireless() == expectWireless) then return m end
    end
    return nil
end

local function scan_typed_modem(expectWireless)
    if peripheral and peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "modem" then
                local m = peripheral.wrap(name)
                if m and (m.isWireless == nil or m.isWireless() == expectWireless) then return m end
            end
        end
    end
    if peripheral and peripheral.find then
        return peripheral.find("modem", function(_, dev)
            return dev and (dev.isWireless == nil or dev.isWireless() == expectWireless)
        end)
    end
    return nil
end

local function resolve_typed_modem(side, fallbackSide, expectWireless)
    return check_modem_side(side, expectWireless) or check_modem_side(fallbackSide, expectWireless)
        or scan_typed_modem(expectWireless)
        or (side and peripheral and peripheral.wrap and peripheral.wrap(side))
        or (peripheral and peripheral.find and peripheral.find("modem"))
end

function network_manager.init(systemConfig)
    local cfg = systemConfig or {}
    local ports, baseCh, sub = cfg.physicalPorts or {}, cfg.baseChannel or 10020, cfg.subchannels or {}
    local topM = resolve_typed_modem(ports.wirelessModemSide or "top", "top", true)
    local botM = resolve_typed_modem(ports.wiredSensorBusSide or "bottom", "bottom", false)

    local ch = {
        guidance = baseCh + (sub.guidance or 1), telemetry = baseCh + (sub.telemetry or 2),
        mfd = baseCh + (sub.mfd or 3), calibration = baseCh + (sub.calibration or 4),
        actuation = baseCh + (sub.actuation or 6), aero = baseCh + (sub.aero or 7)
    }

    if topM and topM.open then
        topM.open(ch.guidance)
        topM.open(ch.actuation)
        topM.open(ch.aero)
        topM.open(ch.calibration)
    end

    return {
        wirelessModem = topM, wiredModem = botM,
        aircraftDomainId = cfg.aircraftDomainId or "AIRCRAFT_01",
        baseChannel = baseCh, channels = ch, txSeq = 0, latestCommand = nil, adapterWap = nil
    }
end

function network_manager.verify_envelope(pkt, expectedDomain)
    if type(pkt) ~= "table" then return false, "ERR_NOT_TABLE" end
    if pkt.ver ~= "1.9.5" then return false, "ERR_VERSION_MISMATCH" end
    if expectedDomain and pkt.domainId ~= expectedDomain then return false, "ERR_DOMAIN_MISMATCH" end
    if not pkt.type or not pkt.seq or not pkt.payload then return false, "ERR_MALFORMED_ENVELOPE" end
    return true, "OK"
end

function network_manager.send_packet(state, channel, pktType, payload)
    if not state or not state.wirelessModem or not state.wirelessModem.transmit then return false end
    state.txSeq = ((state.txSeq or 0) + 1) % 65536
    local env = {
        ver = "1.9.5", domainId = state.aircraftDomainId, seq = state.txSeq,
        type = pktType, time = (os.epoch and os.epoch("utc")) or 0, payload = payload
    }
    pcall(state.wirelessModem.transmit, channel, channel, env)
    return true
end

function network_manager.broadcast_discovery(state)
    if not state or not state.channels or not state.channels.actuation then return false end
    return network_manager.send_packet(state, state.channels.actuation, "MSG_ACTUATOR_DISCOVER_REQ", {
        targetGroup = "ALL", targetThrusterId = "ALL", requestDomain = state.aircraftDomainId
    })
end

function network_manager.send_emergency_alert(state, alertData)
    local data = alertData or {}
    local ch = (state and state.channels and state.channels.guidance) or 10021
    return network_manager.send_packet(state, ch, "MSG_EMERGENCY_ALERT", {
        reason = data.reason or "UNKNOWN", isAirborne = data.isAirborne == true,
        fsmState = data.fsmState or "UNKNOWN", altitude = data.altitude or 0.0
    })
end

local function handle_calibration_packet(state, fsm, mixer, rawPacket)
    local msgType = rawPacket.type
    if msgType == "MSG_CALIB_START" then
        if rawPacket.payload and rawPacket.payload.stationId then state.calibStationId = rawPacket.payload.stationId end
        if fsm and fsm.transition_to then
            local act = rawPacket.payload and rawPacket.payload.action
            local isAbort = (act == "ABORT_CALIBRATION")
            fsm.transition_to(fsm, isAbort and "IDLE_ARMED" or "CALIBRATION", isAbort and "CALIB_ABORT" or "ALIGN_START")
        end
        return true
    elseif msgType == "MSG_PROFILE_SYNC" then
        if mixer and mixer.reload_coefficients then
            mixer.reload_coefficients(mixer, rawPacket.payload and rawPacket.payload.thrusterCoefficients, false)
        end
        if fsm and fsm.transition_to then fsm.transition_to(fsm, "IDLE_ARMED", "CALIB_COMPLETE") end
        if state.on_profile_sync then state.on_profile_sync(rawPacket.payload) end
        local pid = (rawPacket.payload and rawPacket.payload.profileId) or "UNKNOWN"
        network_manager.send_packet(state, state.channels.calibration, "MSG_CALIB_ACK", { profileId = pid, status = "ACCEPTED" })
        return true
    end
    return true
end

function network_manager.dispatch(state, fsm, controller, mixer, channel, replyChannel, rawPacket)
    local ok, _ = network_manager.verify_envelope(rawPacket, state.aircraftDomainId)
    if not ok then return false end
    local msgType = rawPacket.type
    if msgType == "MSG_EMERGENCY_OVERRIDE" then
        if fsm and fsm.arbitrate_c2 then fsm.arbitrate_c2(fsm, rawPacket.payload)
        elseif fsm and fsm.transition_to then fsm.transition_to(fsm, "AIRBORNE_EMERGENCY", "UAC_OVERRIDE") end
        return true
    elseif channel == state.channels.guidance or msgType == "MSG_ATTITUDE_CMD" then
        state.latestCommand = rawPacket.payload
        if fsm then
            fsm.lastUapCmdMs = (os.epoch and os.epoch("utc")) or 0
            fsm.lastUapCmd = rawPacket.payload
            if fsm.arbitrate_c2 then fsm.arbitrate_c2(fsm, rawPacket.payload) end
            if fsm.handle_arm_command then fsm.handle_arm_command(fsm, rawPacket.payload)
            elseif (fsm.currentState == "IDLE_ARMED" or fsm.currentState == "DISARMED") and rawPacket.payload.arm == true then
                fsm.currentState = "NORMAL"
            end
        end
        return true
    elseif msgType == "MSG_ACTUATOR_DISCOVER_ACK" then
        if mixer and mixer.register_actuator_node then mixer.register_actuator_node(mixer, rawPacket.payload) end
        return true
    elseif channel == state.channels.actuation or msgType == "MSG_ACTUATOR_STATUS" then
        if mixer and mixer.update_actuator_feedback then
            local isLoss = mixer.update_actuator_feedback(mixer, rawPacket.payload)
            if isLoss and fsm and fsm.transition_to then fsm.transition_to(fsm, "EMERGENCY_LAND", "TAP_TOTAL_LOSS") end
        end
        return true
    elseif channel == state.channels.aero or msgType == "MSG_AERO_STATUS" then
        if state.adapterWap and state.adapterWap.update_feedback then state.adapterWap.update_feedback(state.adapterWap, rawPacket.payload) end
        return true
    elseif channel == state.channels.calibration or msgType == "MSG_CALIB_START" or msgType == "MSG_PROFILE_SYNC" then
        return handle_calibration_packet(state, fsm, mixer, rawPacket)
    end
    return false
end

return network_manager
