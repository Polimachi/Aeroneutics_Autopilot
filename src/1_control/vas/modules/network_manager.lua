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
    trajectory = 4,
    clientReply = 5,
    actuation = 10,
    aero = 11,
    asaActuation = 11,
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
    local aeroOff = s.asaActuation or zo.asaActuation
    return {
        c2 = baseCh + (s.c2Command or zo.c2),
        guidance = baseCh + (s.guidance or zo.guidance),
        telemetry = baseCh + (s.telemetry or zo.telemetry),
        mfd = baseCh + (s.mfd or zo.mfd),
        trajectory = baseCh + (s.trajectory or zo.trajectory),
        clientReply = baseCh + (s.clientReply or zo.clientReply),
        actuation = baseCh + (s.actuation or zo.actuation),
        aero = baseCh + aeroOff,
        asaActuation = baseCh + aeroOff,
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

    local vType = cfg.vehicleType or "WINGED_VTOL"
    local isAero = (vType == "FIXED_WING" or vType == "WINGED_VTOL")
    local hwUuid = cfg.hardwareUuid or (os and os.getComputerLabel and os.getComputerLabel()) or "cc-core-01-uuid"

    return {
        wirelessModem = topM, wiredModem = botM,
        aircraftDomainId = cfg.aircraftDomainId or "AIRCRAFT_01",
        airframeType = vType, isAero = isAero, hardwareUuid = hwUuid,
        subchannels = sub, configPath = cfg.configPath or "config/system.json",
        baseChannel = baseCh, channels = ch, txSeq = 0, latestCommand = nil, adapterAsa = nil,
        hangarChannels = nil, pendingRebind = nil, rebindTimerId = nil
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
    if not state or not state.channels then return false end
    if state.channels.actuation then
        network_manager.send_packet(state, state.channels.actuation, "MSG_ACTUATOR_DISCOVER_REQ", {
            targetGroup = "ALL", requestDomain = state.aircraftDomainId
        })
    end
    local aeroCh = state.channels.asaActuation
    if aeroCh then
        network_manager.send_packet(state, aeroCh, "MSG_SURFACE_DISCOVER_REQ", {
            targetPod = "ALL", requestDomain = state.aircraftDomainId
        })
    end
    return true
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
    local cmdCh, telemCh, tapCh = baseHangar + 0, baseHangar + 1, baseHangar + 3

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
        bayId = bayId, stationId = payload.stationId or "HANGAR_BAY_01",
        base = baseHangar, cmd = cmdCh, telem = telemCh, tap = tapCh
    }

    if fsm and fsm.transition_to then fsm.transition_to(fsm, "CALIBRATION", "ALIGN_INIT") end

    local bindPayload = {
        action = "OPEN", stationId = state.hangarChannels.stationId, bayId = bayId,
        baseHangarChannel = baseHangar, bayCalibrationTap = tapCh, bayCalibrationCmd = cmdCh,
        timeoutSec = tonumber(payload.timeoutSec) or 120
    }
    if state.channels and state.channels.actuation then
        network_manager.send_packet(state, state.channels.actuation, "MSG_CALIB_BAY_BIND", bindPayload)
    end
    local aeroCh = state.channels and state.channels.asaActuation
    if aeroCh then
        network_manager.send_packet(state, aeroCh, "MSG_CALIB_BAY_BIND", bindPayload)
    end

    network_manager.send_packet(state, telemCh, "MSG_CALIBRATION_INIT_ACK", {
        aircraftDomainId = state.aircraftDomainId, hardwareUuid = state.hardwareUuid,
        bayId = bayId, status = "READY", airframeType = state.airframeType, baseChannel = state.baseChannel
    })
    return true
end

local function handle_calib_close(state, fsm, rawPacket)
    local bayId = (rawPacket.payload and rawPacket.payload.bayId) or (state.hangarChannels and state.hangarChannels.bayId) or 1
    local closePayload = {
        action = "CLOSE", bayId = bayId,
        stationId = (state.hangarChannels and state.hangarChannels.stationId) or "UNKNOWN",
        baseHangarChannel = state.hangarChannels and state.hangarChannels.base
    }
    if state.channels and state.channels.actuation then
        network_manager.send_packet(state, state.channels.actuation, "MSG_CALIB_BAY_BIND", closePayload)
    end
    local aeroCh = state.channels and state.channels.asaActuation
    if aeroCh then
        network_manager.send_packet(state, aeroCh, "MSG_CALIB_BAY_BIND", closePayload)
    end
    local telemCh = state.hangarChannels and state.hangarChannels.telem
    if telemCh then
        network_manager.send_packet(state, telemCh, "MSG_CALIBRATION_CLOSE_ACK", { bayId = bayId, status = "CLOSED" })
    end
    if state.hangarChannels and state.wirelessModem and state.wirelessModem.close then
        state.wirelessModem.close(state.hangarChannels.cmd)
        state.wirelessModem.close(state.hangarChannels.telem)
        state.wirelessModem.close(state.hangarChannels.tap)
    end
    state.hangarChannels = nil
    if fsm and fsm.transition_to then fsm.transition_to(fsm, "IDLE_ARMED", "CALIB_CLOSE") end
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
        if mixer and mixer.reload_coefficients then mixer.reload_coefficients(mixer, rawPacket.payload, false) end
        if fsm and fsm.transition_to then fsm.transition_to(fsm, "IDLE_ARMED", "CALIB_COMPLETE") end
        if state.on_profile_sync then state.on_profile_sync(rawPacket.payload) end
        local pid = (rawPacket.payload and rawPacket.payload.profileId) or "UNKNOWN"
        local replyCh = (state.hangarChannels and state.hangarChannels.telem) or (state.channels and state.channels.guidance) or 10001
        network_manager.send_packet(state, replyCh, "MSG_CALIB_ACK", { profileId = pid, status = "ACCEPTED" })
        return true
    elseif msgType == "MSG_CALIBRATION_CLOSE" then
        return handle_calib_close(state, fsm, rawPacket)
    end
    return true
end

local REBIND_TIMEOUT_MS = 500

local function relay_rebind(state, rebindPayload)
    if state.channels and state.channels.actuation then
        network_manager.send_packet(state, state.channels.actuation, "MSG_CHANNEL_REBIND", rebindPayload)
    end
    local aeroCh = state.channels and state.channels.asaActuation
    if aeroCh then
        network_manager.send_packet(state, aeroCh, "MSG_CHANNEL_REBIND", rebindPayload)
    end
end

local function set_rebind_channels(state, baseCh, isOpen)
    if not state.wirelessModem or not baseCh then return end
    local chMap = build_channel_map(baseCh, state.subchannels)
    local fn = isOpen and state.wirelessModem.open or state.wirelessModem.close
    if not fn then return end
    fn(chMap.c2)
    fn(chMap.guidance)
    fn(chMap.actuation)
    fn(chMap.asaActuation)
end

local function persist_system_base(state, newBase)
    if state.on_rebind_commit then state.on_rebind_commit(newBase) end
    local path = state.configPath
    if not (path and fs and fs.exists and fs.exists(path) and textutils) then return end
    local rf = fs.open(path, "r")
    if not rf then return end
    local decoded = textutils.unserialiseJSON and textutils.unserialiseJSON(rf.readAll()) or {}
    rf.close()
    decoded.baseChannel = newBase
    local ser = textutils.serializeJSON or textutils.serialiseJSON
    local wf = ser and fs.open(path, "w")
    if wf then
        wf.write(ser(decoded))
        wf.close()
    end
end

local function emit_rebind_ack(state, txId, action, status, oldBase, newBase, subNodes)
    local oldCh = build_channel_map(oldBase, state.subchannels)
    network_manager.send_packet(state, oldCh.guidance, "MSG_CHANNEL_REBIND_ACK", {
        transactionId = txId, nodeId = "01_core", action = action, status = status,
        oldBaseChannel = oldBase, newBaseChannel = newBase, subNodesReady = subNodes
    })
end

local function handle_rebind_prepare(state, p, newBase)
    if not network_manager.is_valid_base(newBase) then return false, "ERR_INVALID_NEW_BASE" end
    local nowMs = (os.epoch and os.epoch("utc")) or 0
    set_rebind_channels(state, newBase, true)
    state.pendingRebind = {
        transactionId = p.transactionId, oldBase = state.baseChannel, newBase = newBase,
        startMs = nowMs, subNodesReady = { tap = false, asa = (not state.isAero) }, ackSent = false
    }
    relay_rebind(state, {
        transactionId = p.transactionId, action = "PREPARE",
        oldBaseChannel = state.baseChannel, newBaseChannel = newBase, bandwidth = 40
    })
    if os and os.startTimer then state.rebindTimerId = os.startTimer(0.55) end
    return true
end

local function handle_rebind_ack(state, channel, p)
    local pr = state.pendingRebind
    if not pr or not p or p.transactionId ~= pr.transactionId then return false end
    local actCh = state.channels and state.channels.actuation
    local asaCh = state.channels and state.channels.asaActuation
    if channel == actCh or p.nodeId == "02_tca" or p.nodeId == "TCA" then
        pr.subNodesReady.tap = (p.status == "READY")
    elseif channel == asaCh or p.nodeId == "06_asa" or p.nodeId == "ASA" then
        pr.subNodesReady.asa = (p.status == "READY")
    end
    if p.status == "FAILED" and not pr.ackSent then
        pr.ackSent = true
        emit_rebind_ack(state, pr.transactionId, "PREPARE", "FAILED", pr.oldBase, pr.newBase, pr.subNodesReady)
        set_rebind_channels(state, pr.newBase, false)
        state.pendingRebind = nil
    elseif pr.subNodesReady.tap and pr.subNodesReady.asa and not pr.ackSent then
        pr.ackSent = true
        emit_rebind_ack(state, pr.transactionId, "PREPARE", "READY", pr.oldBase, pr.newBase, pr.subNodesReady)
    end
    return true
end

function network_manager.step_rebind_watchdog(state, nowMs)
    local pr = state and state.pendingRebind
    if not pr or pr.ackSent then return false end
    local now = nowMs or ((os.epoch and os.epoch("utc")) or 0)
    if (now - (pr.startMs or 0)) < REBIND_TIMEOUT_MS then return false end
    pr.ackSent = true
    emit_rebind_ack(state, pr.transactionId, "PREPARE", "FAILED", pr.oldBase, pr.newBase, pr.subNodesReady)
    set_rebind_channels(state, pr.newBase, false)
    state.pendingRebind = nil
    return true
end

local function handle_rebind_commit(state, p, newBase)
    local oldBase = (state.pendingRebind and state.pendingRebind.oldBase) or tonumber(p.oldBaseChannel) or state.baseChannel
    local targetNewBase = (state.pendingRebind and state.pendingRebind.newBase) or newBase
    if not network_manager.is_valid_base(targetNewBase) then return false, "ERR_INVALID_NEW_BASE" end
    relay_rebind(state, {
        transactionId = p.transactionId, action = "COMMIT",
        oldBaseChannel = oldBase, newBaseChannel = targetNewBase, bandwidth = 40
    })
    set_rebind_channels(state, oldBase, false)
    state.baseChannel = targetNewBase
    state.channels = build_channel_map(targetNewBase, state.subchannels)
    persist_system_base(state, targetNewBase)
    state.pendingRebind = nil
    return true
end

local function handle_rebind_rollback(state, p, newBase)
    local targetNewBase = (state.pendingRebind and state.pendingRebind.newBase) or newBase
    relay_rebind(state, {
        transactionId = p.transactionId, action = "ROLLBACK",
        oldBaseChannel = state.baseChannel, newBaseChannel = targetNewBase, bandwidth = 40
    })
    set_rebind_channels(state, targetNewBase, false)
    state.pendingRebind = nil
    return true
end

local function handle_channel_rebind(state, rawPacket)
    local p = rawPacket.payload
    if not p then return false end
    local act = p.action
    local newBase = tonumber(p.newBaseChannel)
    if act == "PREPARE" then return handle_rebind_prepare(state, p, newBase)
    elseif act == "COMMIT" then return handle_rebind_commit(state, p, newBase)
    elseif act == "ROLLBACK" then return handle_rebind_rollback(state, p, newBase) end
    return false
end

local function handle_guidance_cmd(state, fsm, msgType, rawPacket)
    local p = rawPacket.payload
    if msgType == "MSG_ATTITUDE_CMD" then
        local cmdType = p and p.commandType
        if cmdType ~= "QUATERNION_RATE" and cmdType ~= "RATE_COMMAND" then
            return false
        end
    end
    local now = (os.epoch and os.epoch("utc")) or 0
    local accepted = true
    if fsm and fsm.arbitrate_c2 then
        accepted = fsm.arbitrate_c2(fsm, p) ~= nil
    end
    if not accepted then
        fsm.lastFcpCmdMs = now
        return true
    end
    state.latestCommand = p
    if fsm then
        fsm.lastFcpCmdMs = now
        fsm.lastFcpCmd = p
        if fsm.handle_arm_command then fsm.handle_arm_command(fsm, p)
        elseif (fsm.currentState == "IDLE_ARMED" or fsm.currentState == "DISARMED") and p.arm == true then
            fsm.currentState = "NORMAL"
        end
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
    elseif msgType == "MSG_CALIBRATION_INIT" and (channel == (state.channels and state.channels.c2) or channel == state.baseChannel) then
        return handle_calibration_init(state, fsm, rawPacket.payload)
    elseif msgType == "MSG_CHANNEL_REBIND" then
        return handle_channel_rebind(state, rawPacket)
    elseif msgType == "MSG_CHANNEL_REBIND_ACK" then
        return handle_rebind_ack(state, channel, rawPacket.payload)
    elseif channel == (state.channels and state.channels.guidance) or msgType == "MSG_ATTITUDE_CMD" then
        return handle_guidance_cmd(state, fsm, msgType, rawPacket)
    elseif msgType == "MSG_ACTUATOR_DISCOVER_ACK" then
        if mixer and mixer.register_actuator_node then mixer.register_actuator_node(mixer, rawPacket.payload) end
        return true
    elseif msgType == "MSG_SURFACE_DISCOVER_ACK" then
        if state.adapterAsa and state.adapterAsa.register_surface_node then
            state.adapterAsa:register_surface_node(rawPacket.payload)
        end
        return true
    elseif channel == (state.channels and state.channels.actuation) or msgType == "MSG_ACTUATOR_STATUS" then
        if mixer and mixer.update_actuator_feedback then
            local isLoss = mixer.update_actuator_feedback(mixer, rawPacket.payload)
            if isLoss and fsm and fsm.transition_to then fsm.transition_to(fsm, "EMERGENCY_LAND", "TAP_TOTAL_LOSS") end
        end
        return true
    elseif channel == (state.channels and state.channels.asaActuation) or msgType == "MSG_AERO_STATUS" then
        if state.adapterAsa and state.adapterAsa.update_feedback then
            state.adapterAsa:update_feedback(rawPacket.payload)
        end
        return true
    elseif (state.hangarChannels and channel == state.hangarChannels.cmd) or msgType == "MSG_CALIB_START" or msgType == "MSG_PROFILE_SYNC" or msgType == "MSG_CALIBRATION_CLOSE" then
        return handle_calibration_packet(state, fsm, mixer, rawPacket)
    end
    return false
end

return network_manager
