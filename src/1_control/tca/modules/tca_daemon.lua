-- Non-blocking TCA Daemon State Machine & Safety Supervisor (v1.7.0)
local packet_protocol = require("packet_protocol")
local actuator_adapter = require("actuator_adapter")
local watchdog_sentinel = require("watchdog_sentinel")
local status_reporter = require("status_reporter")
local group_allocator = require("group_allocator")
local discovery_handler = require("discovery_handler")
local channel_rebind_handler = require("channel_rebind_handler")

local tca_daemon = {}
tca_daemon.__index = tca_daemon

function tca_daemon.push_log(inst, msg)
    if not inst.logBuffer then inst.logBuffer = {} end
    table.insert(inst.logBuffer, tostring(msg))
    while #inst.logBuffer > 5 do table.remove(inst.logBuffer, 1) end
    inst.isDirty = true
end

function tca_daemon.init(cfg, modem, adapterState)
    local mode = cfg.interactionMode or "REDSTONE"
    local state = adapterState or actuator_adapter.init(mode, nil, cfg.ports)
    local actChan = cfg.channels and cfg.channels.thrustActuation or (cfg.baseChannel + 10)
    local rep = status_reporter.init(cfg.groupId, modem, actChan, cfg.aircraftDomainId)
    local inst = setmetatable({
        cfg = cfg, modem = modem, adapterState = state, reporter = rep,
        lastControlState = "DISARMED", linkStatus = "IDLE", isDirty = true,
        logBuffer = { "TCA Daemon initialized", "Awaiting VAC telemetry..." }
    }, tca_daemon)
    inst.sentinel = watchdog_sentinel.init(cfg.watchdogTimeoutMs or 300, function() inst:handle_watchdog_timeout() end)
    return inst
end

function tca_daemon.handle_watchdog_timeout(inst)
    actuator_adapter.cut_thrust(inst.adapterState)
    inst.linkStatus = "TIMEOUT"
    inst:push_log(string.format("[TIMEOUT] Watchdog %dms expired", inst.cfg.watchdogTimeoutMs or 300))
    local act, tot, mode = discovery_handler.resolve_counts(inst.cfg, inst.adapterState)
    local hStat = discovery_handler.compute_health_status(mode, act, tot, true)
    inst.reporter:check_and_send({
        groupId = inst.cfg.groupId, interactionMode = mode, appliedSignal = 0,
        appliedRatio = 0.0, activeCount = act, totalCount = tot, isSaturated = false, healthStatus = hStat
    })
end

local function is_flight_state(st)
    return st == "NORMAL" or st == "ARMING" or st == "FAILSAFE_HOLD" or st == "EMERGENCY_LAND"
end

function tca_daemon.handle_calib_pulse(inst, pkt)
    local p = pkt and pkt.payload
    if not p then return false end
    local tgt = p.targetThrusterId
    if tgt and tgt ~= inst.cfg.groupId and tgt ~= "ALL" then return false end
    if is_flight_state(inst.lastControlState) and inst.lastControlState ~= "CALIBRATION" then return false end
    return inst.sentinel:handle_pulse(p.pulseLevel, p.pulseDurationMs, inst.adapterState)
end

local function handle_safed_output(inst, mode, act, tot)
    actuator_adapter.cut_thrust(inst.adapterState)
    local hStat = discovery_handler.compute_health_status(mode, act, tot, false)
    inst.reporter:check_and_send({
        groupId = inst.cfg.groupId, interactionMode = mode, appliedSignal = 0,
        appliedRatio = 0.0, activeCount = act, totalCount = tot, isSaturated = false, healthStatus = hStat
    })
    return true
end

function tca_daemon.handle_thrust_cmd(inst, pkt)
    local p = pkt and pkt.payload
    if not p or not p.outputs then return false end
    inst.lastControlState = p.controlState or "NORMAL"
    inst.sentinel:feed(p.watchdogSeq)
    inst.linkStatus = "CONNECTED"
    local act, tot, mode = discovery_handler.resolve_counts(inst.cfg, inst.adapterState)
    if inst.lastControlState == "DISARMED" or inst.lastControlState == "IDLE_ARMED" then
        return handle_safed_output(inst, mode, act, tot)
    end
    if inst.lastControlState == "CALIBRATION" and inst.sentinel:is_pulse_active() then return true end
    local raw = group_allocator.extract_group_output(p.outputs, inst.cfg.groupId, inst.cfg.deadband)
    if inst.lastControlState == "E_STOP" and raw <= 0 then
        return handle_safed_output(inst, mode, act, tot)
    end
    local isSat = group_allocator.is_saturated(raw, mode, act, tot)
    actuator_adapter.apply_thrust(inst.adapterState, raw, act, tot)
    local hStat = discovery_handler.compute_health_status(mode, act, tot, false)
    inst.reporter:check_and_send({
        groupId = inst.cfg.groupId, interactionMode = mode,
        appliedSignal = inst.adapterState.lastSignal or 0, appliedRatio = inst.adapterState.lastRatio or 0.0,
        activeCount = act, totalCount = tot, isSaturated = isSat, healthStatus = hStat
    })
    inst:push_log(string.format("RX CMD seq=%d sig=%d", p.watchdogSeq or 0, raw))
    return true
end

function tca_daemon.handle_hardware_change(inst)
    actuator_adapter.scan_api_peripherals(inst.adapterState)
    local act, tot, mode = discovery_handler.resolve_counts(inst.cfg, inst.adapterState)
    if not inst.sentinel.isExpired and (inst.adapterState.lastSignal or 0) > 0 then
        actuator_adapter.apply_thrust(inst.adapterState, inst.adapterState.lastSignal, act, tot)
    end
    local hStat = discovery_handler.compute_health_status(mode, act, tot, inst.sentinel.isExpired)
    inst.reporter:check_and_send({
        groupId = inst.cfg.groupId, interactionMode = mode,
        appliedSignal = inst.adapterState.lastSignal or 0, appliedRatio = inst.adapterState.lastRatio or 0.0,
        activeCount = act, totalCount = tot, isSaturated = false, healthStatus = hStat
    })
end

local function now_ms()
    return (os and os.epoch and os.epoch("utc")) or 0
end

function tca_daemon.send_manual_ping(inst)
    if not inst.modem then
        inst:push_log("[PING] FAIL: no modem attached")
        return false
    end
    local act, tot, mode = discovery_handler.resolve_counts(inst.cfg, inst.adapterState)
    local hStat = discovery_handler.compute_health_status(mode, act, tot, inst.sentinel.isExpired)
    inst.reporter:check_and_send({
        groupId = inst.cfg.groupId, interactionMode = mode,
        appliedSignal = inst.adapterState.lastSignal or 0, appliedRatio = inst.adapterState.lastRatio or 0.0,
        activeCount = act, totalCount = tot, isSaturated = false, healthStatus = hStat
    }, true)
    local rx = inst.lastRxMs and string.format("%dms ago", now_ms() - inst.lastRxMs) or "never"
    inst:push_log(string.format("TX PING ch%d | last RX %s", inst.reporter.channel or 0, rx))
    return true
end

function tca_daemon.pause(inst)
    actuator_adapter.cut_thrust(inst.adapterState)
    inst:push_log("[PAUSE] Daemon paused for setup")
end

function tca_daemon.resume(inst, newCfg)
    if newCfg then
        inst.cfg = newCfg
        local actChan = newCfg.channels and newCfg.channels.thrustActuation or (newCfg.baseChannel + 10)
        inst.reporter = status_reporter.init(newCfg.groupId, inst.modem, actChan, newCfg.aircraftDomainId)
    end
    inst.sentinel:start_timer((inst.cfg.watchdogTimeoutMs or 300) / 1000.0)
    inst:push_log("[RESUME] Config reloaded")
end

local function log_drop(inst, pkt, reason)
    local detail = (type(pkt) == "table") and tostring(reason == "UNSUPPORTED_VERSION" and pkt.ver or pkt.domainId) or type(pkt)
    local key = tostring(reason) .. "|" .. detail
    if inst.lastDropKey == key then return end
    inst.lastDropKey = key
    inst:push_log(string.format("[DROP] %s %s", tostring(reason), detail):sub(1, 47))
end

function tca_daemon.dispatch_modem_message(inst, channel, replyChannel, rawMsg)
    local pkt = (type(rawMsg) == "string" and textutils and textutils.unserializeJSON) and textutils.unserializeJSON(rawMsg) or rawMsg
    local okPkt, reason = packet_protocol.verify_packet(pkt, inst.cfg.aircraftDomainId)
    if not okPkt then
        log_drop(inst, pkt, reason)
        return false
    end
    inst.lastRxMs = now_ms()
    local t = pkt.type
    if t == "MSG_THRUST_CMD" then return inst:handle_thrust_cmd(pkt)
    elseif t == "MSG_CALIB_PULSE" then return inst:handle_calib_pulse(pkt)
    elseif t == "MSG_ACTUATOR_DISCOVER_REQ" then
        return discovery_handler.handle_request(inst.modem, channel, replyChannel, pkt, inst.cfg, inst.adapterState)
    elseif t == "MSG_CALIB_BAY_BIND" then
        return channel_rebind_handler.handle_bay_bind(inst.modem, pkt, inst.adapterState)
    elseif t == "MSG_CHANNEL_REBIND" then
        local cfgPath = inst.configPath or (inst.cfg and inst.cfg.configPath) or "config.json"
        local ok = channel_rebind_handler.handle_channel_rebind(inst.modem, replyChannel, pkt, inst.cfg, inst.adapterState, cfgPath)
        if ok and inst.reporter and inst.cfg and inst.cfg.channels and inst.cfg.channels.thrustActuation then
            inst.reporter.channel = inst.cfg.channels.thrustActuation
        end
        return ok
    end
    return false
end

function tca_daemon.step_event(inst, ev, p1, p2, p3, p4)
    if ev == "modem_message" then
        local bay, pulse = inst.adapterState and inst.adapterState.hangarBayChannel, inst.adapterState and inst.adapterState.hangarPulseChannel
        local act = inst.cfg and inst.cfg.channels and inst.cfg.channels.thrustActuation
        if p2 == act or p2 == bay or p2 == pulse then
            inst:dispatch_modem_message(p2, p3, p4)
        end
    elseif ev == "timer" then inst.sentinel:handle_timer(p1)
    elseif ev == "peripheral" or ev == "peripheral_detach" then inst:handle_hardware_change()
    elseif ev == "terminate" then
        actuator_adapter.cut_thrust(inst.adapterState)
        return false
    end
    return true
end

function tca_daemon.hil_smoke_tick(inst, dt, cmdPayload)
    if not inst then return false, "NO_INSTANCE" end
    if cmdPayload then
        local pkt = packet_protocol.encode_envelope(inst.cfg.aircraftDomainId, "MSG_THRUST_CMD", 1, cmdPayload)
        inst:handle_thrust_cmd(pkt)
    end
    return true, inst.adapterState.lastSignal or 0
end

return tca_daemon
