-- VAS Dual-Modem Network Router & ICD v1.19.0 Module
local network_manager = {}

network_manager.PROTO_VERSION = "1.9.5"
network_manager.CRAFT_BASE_MIN = 10000
network_manager.CRAFT_BASE_MAX = 49960
network_manager.CRAFT_BANDWIDTH = 40
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
    formationLink = 30
}

function network_manager.compute_base(aircraftIndexN)
    if type(aircraftIndexN) ~= "number" or aircraftIndexN < 1 or aircraftIndexN > 1000 or math.floor(aircraftIndexN) ~= aircraftIndexN then
        return nil, "ERR_AIRCRAFT_INDEX_RANGE"
    end
    return 10000 + (aircraftIndexN - 1) * 40
end

function network_manager.is_valid_base(baseCh)
    return type(baseCh) == "number"
        and baseCh >= 10000
        and baseCh <= 49960
        and math.floor(baseCh) == baseCh
        and ((baseCh - 10000) % 40 == 0)
end

local function build_channel_map(baseCh, sub)
    local s = sub or {}
    local zo = network_manager.ZONE_OFFSETS
    return {
        c2 = baseCh + (s.c2 or zo.c2),
        guidance = baseCh + (s.guidance or zo.guidance),
        telemetry = baseCh + (s.telemetry or zo.telemetry),
        mfd = baseCh + (s.mfd or zo.mfd),
        navSensor = baseCh + (s.navSensor or zo.navSensor),
        clientReply = baseCh + (s.clientReply or zo.clientReply),
        actuation = baseCh + (s.actuation or zo.actuation),
        aero = baseCh + (s.aero or zo.aero),
        payloadBus = baseCh + (s.payloadBus or zo.payloadBus),
        weaponBus = baseCh + (s.weaponBus or zo.weaponBus),
        formationLink = baseCh + (s.formationLink or zo.formationLink)
    }
end

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
    local ports, sub = cfg.physicalPorts or {}, cfg.subchannels or {}
    local topM = resolve_typed_modem(ports.wirelessModemSide or "top", "top", true)
    local botM = resolve_typed_modem(ports.wiredSensorBusSide or "bottom", "bottom", false)

    local baseCh = cfg.baseChannel
    if not network_manager.is_valid_base(baseCh) then
        local n = cfg.aircraftIndexN or 1
        local computed = network_manager.compute_base(n)
        baseCh = computed or 10000
    end

    local ch = build_channel_map(baseCh, sub)

    if topM and topM.open then
        topM.open(ch.c2)
        topM.open(ch.guidance)
        topM.open(ch.actuation)
        topM.open(ch.aero)
    end

    return {
        wirelessModem = topM, wiredModem = botM,
        aircraftDomainId = cfg.aircraftDomainId or "AIRCRAFT_01",
        baseChannel = baseCh, channels = ch, txSeq = 0, latestCommand = nil, adapterWap = nil,
        hangarChannels = nil, pendingRebind = nil
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
    local ch = (state and state.channels and state.channels.guidance) or 10001
    return network_manager.send_packet(state, ch, "MSG_EMERGENCY_ALERT", {
        reason = data.reason or "UNKNOWN", isAirborne = data.isAirborne == true,
        fsmState = data.fsmState or "UNKNOWN", altitude = data.altitude or 0.0
    })
end

local function handle_calibration_init(state, fsm, payload)
    if not payload then return false end
    local bayId = tonumber(payload.bayId) or 1
    local baseHangar = tonumber(payload.baseHangarChannel) or (101 + (bayId - 1) * 10)
    local cmdCh = baseHangar + 0
    local telemCh = baseHangar + 1
    local tapCh = baseHangar + 3

    if state.hangarChannels and state.wirelessModem and state.wirelessModem.close then
        state.wirelessModem.close(state.hangarChannels.cmd)
        state.wirelessModem.close(state.hangarChannels.telem)
        state.wirelessModem.close(state.hangarChannels.tap)
    end

    if state.wirelessModem and state.wirelessModem.open then
        state.wirelessModem.open(cmdCh)
        state.wirelessModem.open(telemCh)
        state.wirelessModem.open(tapCh)
    end

    state.hangarChannels = {
        bayId = bayId,
        stationId = payload.stationId or "HANGAR_BAY_01",
        base = baseHangar,
        cmd = cmdCh,
        telem = telemCh,
        tap = tapCh
    }

    if fsm and fsm.transition_to then
        fsm.transition_to(fsm, "CALIBRATION", "ALIGN_INIT")
    end

    local bindPayload = {
        action = "OPEN",
        stationId = state.hangarChannels.stationId,
        bayId = bayId,
        baseHangarChannel = baseHangar,
        bayCalibrationTap = tapCh,
        bayCalibrationCmd = cmdCh
    }
    if state.channels and state.channels.actuation then
        network_manager.send_packet(state, state.channels.actuation, "MSG_CALIB_BAY_BIND", bindPayload)
    end
    if state.channels and state.channels.aero then
        network_manager.send_packet(state, state.channels.aero, "MSG_CALIB_BAY_BIND", bindPayload)
    end

    network_manager.send_packet(state, telemCh, "MSG_CALIBRATION_INIT_ACK", {
        status = "READY",
        bayId = bayId,
        aircraftDomainId = state.aircraftDomainId,
        baseChannel = state.baseChannel
    })
    return true
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
        local replyCh = (state.hangarChannels and state.hangarChannels.telem) or (state.channels and state.channels.guidance) or 10001
        network_manager.send_packet(state, replyCh, "MSG_CALIB_ACK", { profileId = pid, status = "ACCEPTED" })
        return true
    elseif msgType == "MSG_CALIBRATION_CLOSE" then
        local bayId = (rawPacket.payload and rawPacket.payload.bayId) or (state.hangarChannels and state.hangarChannels.bayId) or 1
        local closePayload = {
            action = "CLOSE",
            bayId = bayId,
            stationId = (state.hangarChannels and state.hangarChannels.stationId) or "UNKNOWN"
        }
        if state.channels and state.channels.actuation then
            network_manager.send_packet(state, state.channels.actuation, "MSG_CALIB_BAY_BIND", closePayload)
        end
        if state.channels and state.channels.aero then
            network_manager.send_packet(state, state.channels.aero, "MSG_CALIB_BAY_BIND", closePayload)
        end
        local telemCh = state.hangarChannels and state.hangarChannels.telem
        if telemCh then
            network_manager.send_packet(state, telemCh, "MSG_CALIBRATION_CLOSE_ACK", {
                bayId = bayId,
                status = "CLOSED"
            })
        end
        if state.hangarChannels and state.wirelessModem and state.wirelessModem.close then
            state.wirelessModem.close(state.hangarChannels.cmd)
            state.wirelessModem.close(state.hangarChannels.telem)
            state.wirelessModem.close(state.hangarChannels.tap)
        end
        state.hangarChannels = nil
        if fsm and fsm.transition_to then
            fsm.transition_to(fsm, "IDLE_ARMED", "CALIB_CLOSE")
        end
        return true
    end
    return true
end

local function handle_channel_rebind(state, rawPacket)
    local p = rawPacket.payload
    if not p then return false end
    local act = p.action
    local newBase = tonumber(p.newBaseChannel)

    if act == "PREPARE" then
        if not network_manager.is_valid_base(newBase) then
            return false, "ERR_INVALID_NEW_BASE"
        end
        if state.wirelessModem and state.wirelessModem.open then
            state.wirelessModem.open(newBase + 0)
            state.wirelessModem.open(newBase + 1)
            state.wirelessModem.open(newBase + 10)
            state.wirelessModem.open(newBase + 11)
        end
        state.pendingRebind = {
            transactionId = p.transactionId,
            oldBase = state.baseChannel,
            newBase = newBase
        }
        if state.channels and state.channels.actuation then
            network_manager.send_packet(state, state.channels.actuation, "MSG_CHANNEL_REBIND", p)
        end
        if state.channels and state.channels.aero then
            network_manager.send_packet(state, state.channels.aero, "MSG_CHANNEL_REBIND", p)
        end
        local ackCh = (state.channels and state.channels.guidance) or (state.baseChannel + 1)
        network_manager.send_packet(state, ackCh, "MSG_CHANNEL_REBIND_ACK", {
            transactionId = p.transactionId,
            nodeId = "01_core",
            status = "READY",
            subNodesOk = true
        })
        return true
    elseif act == "COMMIT" then
        local oldBase = (state.pendingRebind and state.pendingRebind.oldBase) or tonumber(p.oldBaseChannel) or state.baseChannel
        local targetNewBase = (state.pendingRebind and state.pendingRebind.newBase) or newBase
        if not network_manager.is_valid_base(targetNewBase) then
            return false, "ERR_INVALID_NEW_BASE"
        end
        if state.channels and state.channels.actuation then
            network_manager.send_packet(state, state.channels.actuation, "MSG_CHANNEL_REBIND", p)
        end
        if state.channels and state.channels.aero then
            network_manager.send_packet(state, state.channels.aero, "MSG_CHANNEL_REBIND", p)
        end
        if state.wirelessModem and state.wirelessModem.close then
            state.wirelessModem.close(oldBase + 0)
            state.wirelessModem.close(oldBase + 1)
            state.wirelessModem.close(oldBase + 10)
            state.wirelessModem.close(oldBase + 11)
        end
        state.baseChannel = targetNewBase
        state.channels = build_channel_map(targetNewBase, {})
        state.pendingRebind = nil
        return true
    elseif act == "ROLLBACK" then
        local targetNewBase = (state.pendingRebind and state.pendingRebind.newBase) or newBase
        if state.channels and state.channels.actuation then
            network_manager.send_packet(state, state.channels.actuation, "MSG_CHANNEL_REBIND", p)
        end
        if state.channels and state.channels.aero then
            network_manager.send_packet(state, state.channels.aero, "MSG_CHANNEL_REBIND", p)
        end
        if targetNewBase and state.wirelessModem and state.wirelessModem.close then
            state.wirelessModem.close(targetNewBase + 0)
            state.wirelessModem.close(targetNewBase + 1)
            state.wirelessModem.close(targetNewBase + 10)
            state.wirelessModem.close(targetNewBase + 11)
        end
        state.pendingRebind = nil
        return true
    end
    return false
end

function network_manager.dispatch(state, fsm, controller, mixer, channel, replyChannel, rawPacket)
    local ok, _ = network_manager.verify_envelope(rawPacket, state.aircraftDomainId)
    if not ok then return false end
    local msgType = rawPacket.type

    if msgType == "MSG_EMERGENCY_OVERRIDE" then
        if fsm and fsm.arbitrate_c2 then fsm.arbitrate_c2(fsm, rawPacket.payload)
        elseif fsm and fsm.transition_to then fsm.transition_to(fsm, "AIRBORNE_EMERGENCY", "UAC_OVERRIDE") end
        return true
    elseif msgType == "MSG_CALIBRATION_INIT" and (channel == (state.channels and state.channels.c2) or channel == state.baseChannel) then
        return handle_calibration_init(state, fsm, rawPacket.payload)
    elseif msgType == "MSG_CHANNEL_REBIND" then
        return handle_channel_rebind(state, rawPacket)
    elseif msgType == "MSG_CHANNEL_REBIND_ACK" then
        if state.pendingRebind then
            state.pendingRebind.acks = state.pendingRebind.acks or {}
            table.insert(state.pendingRebind.acks, rawPacket.payload)
        end
        return true
    elseif channel == (state.channels and state.channels.guidance) or msgType == "MSG_ATTITUDE_CMD" then
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
    elseif channel == (state.channels and state.channels.actuation) or msgType == "MSG_ACTUATOR_STATUS" then
        if mixer and mixer.update_actuator_feedback then
            local isLoss = mixer.update_actuator_feedback(mixer, rawPacket.payload)
            if isLoss and fsm and fsm.transition_to then fsm.transition_to(fsm, "EMERGENCY_LAND", "TAP_TOTAL_LOSS") end
        end
        return true
    elseif channel == (state.channels and state.channels.aero) or msgType == "MSG_AERO_STATUS" then
        if state.adapterWap and state.adapterWap.update_feedback then state.adapterWap.update_feedback(state.adapterWap, rawPacket.payload) end
        return true
    elseif (state.hangarChannels and channel == state.hangarChannels.cmd) or msgType == "MSG_CALIB_START" or msgType == "MSG_PROFILE_SYNC" or msgType == "MSG_CALIBRATION_CLOSE" then
        return handle_calibration_packet(state, fsm, mixer, rawPacket)
    end
    return false
end

return network_manager
