-- 14-State FSM Align Master Orchestrator for Alignment
local discovery_client = require("discovery_client")
local multi_pulse_sequencer = require("multi_pulse_sequencer")
local impulse_integrator = require("impulse_integrator")
local settling_guard = require("settling_guard")
local ols_regression_engine = require("ols_regression_engine")
local controllability_checker = require("controllability_checker")
local safety_sentinel = require("safety_sentinel")
local profile_exporter = require("profile_exporter")

local align_master = {}
align_master.__index = align_master
local active_session = nil

local CRAFT_BASE_MIN = 10000
local CRAFT_BASE_MAX = 49960
local CRAFT_BANDWIDTH = 40
local HANGAR_BASE_MIN = 101
local HANGAR_BANDWIDTH = 10

align_master.CRAFT_BASE_MIN = CRAFT_BASE_MIN
align_master.CRAFT_BASE_MAX = CRAFT_BASE_MAX
align_master.CRAFT_BANDWIDTH = CRAFT_BANDWIDTH
align_master.HANGAR_BASE_MIN = HANGAR_BASE_MIN
align_master.HANGAR_BANDWIDTH = HANGAR_BANDWIDTH

function align_master.compute_craft_base(aircraft_number)
    local n = tonumber(aircraft_number)
    if n and math.floor(n) == n and n >= 1 and n <= 1000 then
        return CRAFT_BASE_MIN + (n - 1) * CRAFT_BANDWIDTH
    end
    return nil
end

function align_master.compute_hangar_base(bay_id)
    local b = tonumber(bay_id) or 1
    if b and math.floor(b) == b and b >= 1 and b <= 10 then
        return HANGAR_BASE_MIN + (b - 1) * HANGAR_BANDWIDTH
    end
    return nil
end

local function parse_domain_craft_base(domain_id)
    if type(domain_id) == "string" then
        local num_str = domain_id:match("AIRCRAFT_(%d+)")
        if num_str then
            return align_master.compute_craft_base(tonumber(num_str))
        end
    end
    return nil
end

local function modem_open(m, ch)
    if not m or not m.open then return end
    local ok = pcall(m.open, ch)
    if not ok then pcall(m.open, m, ch) end
end

local function modem_close(m, ch)
    if not m or not m.close then return end
    local ok = pcall(m.close, ch)
    if not ok then pcall(m.close, m, ch) end
end

local function modem_transmit(m, ch, reply_ch, msg)
    if not m or not m.transmit then return end
    local ok = pcall(m.transmit, ch, reply_ch, msg)
    if not ok then pcall(m.transmit, m, ch, reply_ch, msg) end
end

local function epoch_ms()
    return (os and os.epoch and os.epoch("utc")) or 0
end

local function send_pkt(self, ch, pkt_type, payload)
    self.seq = self.seq + 1
    local pkt = {
        ver = "1.9.5", domainId = self.domain_id,
        seq = self.seq, type = pkt_type,
        time = epoch_ms(),
        payload = payload or {}
    }
    modem_transmit(self.modem, ch, self.telem_ch, pkt)
    return pkt
end

local function get_station_cfg(cfg)
    return (cfg and cfg.station) or cfg or {}
end

local function reset_session_state(self, now_ms)
    self.seq = 0
    self.actuators = {}
    self.actuator_idx = 1
    self.thruster_results = {}
    self.vector_slopes = {}
    self.step_signals = {}
    self.step_impulses = {}
    self.last_telem = { pitch = 0, roll = 0 }
    self.last_regression = {}
    self.airframe_type = "VTOL"
    self.total_dry_mass = 0.0
    self.eval_result = nil
    self.pseudo_inverse = nil
    self.discovery = discovery_client.new(self.domain_id)
    self.sequencer = multi_pulse_sequencer.new(self.domain_id)
    self.integrator = impulse_integrator.new()
    self.settling = settling_guard.new()
    self.sentinel = safety_sentinel.new(self.cfg.safety)
    self.ols_engine = ols_regression_engine
    self.checker = controllability_checker
    self.state_entered_ms = now_ms or epoch_ms()
    self.pulse_start_ms = self.state_entered_ms
end

local function init_session_into(self, cfg, domain_id, craft_base_ch, modem, now_ms)
    if self.modem and self.cmd_ch then modem_close(self.modem, self.cmd_ch) end
    if self.modem and self.telem_ch then modem_close(self.modem, self.telem_ch) end
    if self.modem and self.tap_ch then modem_close(self.modem, self.tap_ch) end

    self.cfg = cfg or {}
    local station = get_station_cfg(self.cfg)
    self.station = station
    self.domain_id = domain_id or "AIRCRAFT_01"
    self.craft_base_ch = craft_base_ch or parse_domain_craft_base(self.domain_id) or CRAFT_BASE_MIN
    self.modem = modem
    local base = station.baseHangarChannel or (station.bayId and align_master.compute_hangar_base(station.bayId)) or HANGAR_BASE_MIN
    self.cmd_ch, self.telem_ch, self.tap_ch = base + 0, base + 1, base + 3
    reset_session_state(self, now_ms)

    modem_open(self.modem, self.cmd_ch)
    modem_open(self.modem, self.telem_ch)
    modem_open(self.modem, self.tap_ch)
    self.state = "TUNING"
    send_pkt(self, self.craft_base_ch + 8, "MSG_CALIBRATION_INIT", {
        stationId = station.stationId or "HANGAR_BAY_01",
        bayId = station.bayId or 1,
        baseHangarChannel = base,
        targetCraftDomain = self.domain_id,
        timeoutSec = 120,
        targetThruster = "ALL"
    })
    active_session = self
    return self
end

function align_master.init_bay_session(cfg, domain_id, craft_base_ch, modem, now_ms)
    local self = setmetatable({}, align_master)
    return init_session_into(self, cfg, domain_id, craft_base_ch, modem, now_ms)
end

function align_master.get_state(self)
    local inst = (type(self) == "table" and self.state) and self or active_session
    return inst and inst.state or "STANDBY"
end

local VALID_CLOSE_REASONS = {
    COMPLETE = true,
    MANUAL = true,
    CALIBRATION_FINISHED = true,
}

local function normalize_close_reason(reason_str, fallback_reason)
    if VALID_CLOSE_REASONS[reason_str] then
        return reason_str
    end
    return fallback_reason or "MANUAL"
end

local function send_zero_pulse(inst)
    send_pkt(inst, inst.cmd_ch, "MSG_CALIB_PULSE", {
        targetThrusterId = (inst.actuators and inst.actuators[inst.actuator_idx]) or "ALL",
        stepIndex = 1,
        pulseLevel = 0,
        pulseDurationMs = 0,
        safetyMaxTiltDeg = 12.0,
    })
end

function align_master.release_channels(self, reason)
    local inst = (type(self) == "table" and self.state) and self or active_session
    if not inst then return end
    local raw_reason = (type(self) == "string" and self) or reason
    local close_reason = normalize_close_reason(raw_reason, "COMPLETE")
    local station = inst.station or get_station_cfg(inst.cfg)
    send_pkt(inst, inst.cmd_ch, "MSG_CALIBRATION_CLOSE", {
        stationId = station.stationId or "HANGAR_BAY_01",
        bayId = station.bayId or 1,
        action = "CLOSE_SESSION",
        reason = close_reason,
        saveProfile = true
    })
    modem_close(inst.modem, inst.cmd_ch)
    modem_close(inst.modem, inst.telem_ch)
    modem_close(inst.modem, inst.tap_ch)
    inst.state = "STANDBY"
end

local function start_current_thruster(self, now_ms)
    local gid = self.actuators[self.actuator_idx]
    self.step_signals = {}
    self.step_impulses = {}
    if self.discovery:is_vector_capable(gid) then
        self.sequencer:start_vector_thruster(gid)
    else
        self.sequencer:start_thruster(gid)
    end
    self.integrator:reset()
    self.sentinel:reset_watchdog(now_ms or epoch_ms())
    self.pulse_start_ms = now_ms or epoch_ms()
    self.state = "INTEGRATING"
    local pulse_pkt = self.sequencer:build_pulse_packet(self.seq + 1)
    self.seq = self.seq + 1
    modem_transmit(self.modem, self.cmd_ch, self.telem_ch, pulse_pkt)
end

local function build_profile_payload(self, eval_result, regressions)
    local station = self.station or get_station_cfg(self.cfg)
    local surfaces = self.discovery and self.discovery:get_discovered_surfaces() or {}
    local isVec = self.discovery and self.discovery.get_vector_actuators and (#self.discovery:get_vector_actuators() > 0) or false
    local actuatorMap = (self.discovery and self.discovery.get_actuator_map and self.discovery:get_actuator_map()) or {}
    local evalRes = eval_result or self.eval_result
    local dryMass = self.total_dry_mass or self.totalDryMass or 0.0
    local manifest = profile_exporter.build_peripheral_manifest(
        self.domain_id or "AIRCRAFT_01",
        actuatorMap,
        surfaces,
        { "gimbal", "altitude", "velocity", "assembler" },
        dryMass
    )
    self.peripheralManifest = manifest
    return {
        profileId = "PROF-" .. (self.domain_id or "AIRCRAFT_01"),
        domainId = self.domain_id or "AIRCRAFT_01",
        airframeType = self.airframe_type or "VTOL",
        isVectorVtol = isVec,
        calibratedBy = station.stationId or "HANGAR_BAY_01",
        totalDryMass = dryMass,
        controllabilityStatus = (evalRes and evalRes.status) or "FAIL_INSUFFICIENT_AUTHORITY",
        pseudoInverseMatrix = self.pseudo_inverse,
        thrusterCoefficients = regressions or self.thruster_results,
        discoveredSurfaces = surfaces,
        peripheralManifest = manifest,
    }
end

local function finalize_authority_check(self)
    self.state = "AUTHORITY_CHECK"
    local surfaces = self.discovery:get_discovered_surfaces()
    local bMat = nil
    if next(self.vector_slopes) ~= nil then
        bMat = profile_exporter.assemble_control_matrix(self.vector_slopes)
        local pInv = profile_exporter.compute_pseudo_inverse(bMat)
        self.pseudo_inverse = pInv
    end
    self.eval_result = self.checker.evaluate(
        self.thruster_results,
        self.airframe_type,
        surfaces,
        self.cfg.authorityThresholds,
        self.pseudo_inverse,
        bMat
    )
    self.state = "SYNC_APPROVAL"
    local payload = build_profile_payload(self)
    profile_exporter.save_local(payload)
    if type(payload.peripheralManifest) == "table" then
        profile_exporter.save_peripheral_manifest(payload.peripheralManifest, (self.cfg and self.cfg.manifestDir) or "/alignment")
    end
end

local function accept_and_advance_thruster(self, reg, now_ms)
    local gid = self.actuators[self.actuator_idx]
    local entry = {}
    for k, v in pairs(reg.normalizedCoefficients or {}) do
        entry[k] = v
    end
    entry.deadband = reg.deadband
    entry.confidenceR2 = reg.confidenceR2
    entry.maxThrust = 15
    self.thruster_results[gid] = entry
    self.last_regression = reg

    if self.actuator_idx < #self.actuators then
        self.actuator_idx = self.actuator_idx + 1
        start_current_thruster(self, now_ms)
    else
        finalize_authority_check(self)
    end
end

local function run_regression(self, now_ms)
    self.state = "REGRESSION"
    local domAxis = self.ols_engine.identify_dominant_axis(self.step_impulses)
    local reg = self.ols_engine.calculate_regression(self.step_signals, self.step_impulses, domAxis)
    self.last_regression = reg
    local chk = self.sentinel:check_regression_anomaly(reg)
    if chk.status == "PAUSE" then
        self.state = "ANOMALY_PAUSE"
        return
    end
    accept_and_advance_thruster(self, reg, now_ms)
end

local function handle_tuning_or_handshake(self, event, now_ms)
    if event.type == "PACKET" and event.packet and event.packet.type == "MSG_CALIBRATION_INIT_ACK" then
        local p = event.packet.payload or {}
        if p.airframeType then self.airframe_type = p.airframeType end
        if p.totalDryMass then self.total_dry_mass = p.totalDryMass end
        self.state = "HANDSHAKE"
        local station = self.station or get_station_cfg(self.cfg)
        send_pkt(self, self.cmd_ch, "MSG_CALIB_START", {
            action = "ENTER_CALIBRATION",
            stationId = station.stationId or "HANGAR_BAY_01",
            targetThruster = "ALL",
            timeoutSec = 120
        })
        self.state = "DISCOVERY"
        local reqs = self.discovery:build_requests(self.seq + 1, self.tap_ch)
        for _, req in ipairs(reqs) do
            self.seq = req.seq or (self.seq + 1)
            modem_transmit(self.modem, self.tap_ch, self.tap_ch, req)
        end
    elseif (event.type == "TICK" or event.type == "TIMEOUT") and now_ms and (now_ms - self.state_entered_ms >= 3000) then
        align_master.release_channels(self, "TIMEOUT")
    end
end

local function handle_discovery(self, event, now_ms)
    if event.type == "PACKET" and event.packet then
        local pt = event.packet.type
        if pt == "MSG_ACTUATOR_DISCOVER_ACK" or pt == "MSG_SURFACE_DISCOVER_ACK" then
            self.discovery:process_ack(event.packet)
        end
    end
    if event.type == "START_PULSE_SEQUENCE" or event.type == "DISCOVERY_DONE" then
        self.actuators = self.discovery:get_actuator_queue()
        if #self.actuators == 0 then table.insert(self.actuators, "THR_MAIN_L") end
        self.actuator_idx = 1
        start_current_thruster(self, now_ms)
    end
end

local function handle_integrating(self, event, now_ms)
    if event.type == "PACKET" and event.packet and event.packet.type == "MSG_FLIGHT_TELEMETRY" then
        local p = event.packet.payload or {}
        self.last_telem = p
        local chk = self.sentinel:check_telemetry(p, now_ms)
        if chk.status == "ABORT" then
            align_master.step_fsm(self, { type = "ABORT", reason = chk.reason }, now_ms)
            return
        elseif chk.status == "PAUSE" then
            self.state = "ANOMALY_PAUSE"
            return
        end
        self.integrator:integrate_step(p, 0.05)
    elseif event.type == "PULSE_DONE" or (event.type == "TICK" and now_ms and (now_ms - self.pulse_start_ms >= self.sequencer.durationMs)) then
        if event.type == "TICK" and now_ms then
            local wChk = self.sentinel:check_watchdog(now_ms)
            if wChk.status == "ABORT" then
                align_master.step_fsm(self, { type = "ABORT", reason = wChk.reason }, now_ms)
                return
            end
        end
        local _, lvl = self.sequencer:get_current_step()
        table.insert(self.step_signals, lvl)
        table.insert(self.step_impulses, self.integrator:get_total_impulse())
        self.settling:reset()
        self.state = "SETTLING"
    end
end

local function handle_settling(self, event, now_ms)
    local done = (event.type == "SETTLING_DONE")
    if event.type == "PACKET" and event.packet and event.packet.type == "MSG_FLIGHT_TELEMETRY" then
        local p = event.packet.payload or {}
        self.last_telem = p
        local chk = self.sentinel:check_telemetry(p, now_ms)
        if chk.status == "ABORT" then
            align_master.step_fsm(self, { type = "ABORT", reason = chk.reason }, now_ms)
            return
        end
        local settled, timedOut = self.settling:check_sample(p, 0.05)
        done = settled or timedOut
    end
    if done then
        if self.sequencer:next_step() then
            self.integrator:reset()
            self.pulse_start_ms = now_ms or epoch_ms()
            self.state = "INTEGRATING"
            local pulse_pkt = self.sequencer:build_pulse_packet(self.seq + 1)
            self.seq = self.seq + 1
            modem_transmit(self.modem, self.cmd_ch, self.telem_ch, pulse_pkt)
        else
            run_regression(self, now_ms)
        end
    end
end

local function handle_anomaly_pause(self, event, now_ms)
    if event.type == "RETRY" then
        start_current_thruster(self, now_ms)
    elseif event.type == "FORCE_ACCEPT" then
        accept_and_advance_thruster(self, self.last_regression or {}, now_ms)
    end
end

local function handle_approval_and_sync(self, event)
    if self.state == "SYNC_APPROVAL" then
        local passed = self.eval_result and self.eval_result.passed
        if (event.type == "USER_APPROVE" and passed) or event.type == "OVERRIDE" then
            self.state = "SYNCING"
            local profile = build_profile_payload(self)
            profile_exporter.save_local(profile)
            local sync_pkt = profile_exporter.build_sync_packet(self.domain_id, self.seq + 1, profile)
            self.seq = self.seq + 1
            modem_transmit(self.modem, self.cmd_ch, self.telem_ch, sync_pkt)
        elseif event.type == "REJECT" then
            align_master.release_channels(self, "USER_REJECTED")
        end
    elseif self.state == "SYNCING" and event.type == "PACKET" and event.packet then
        if event.packet.type == "MSG_CALIB_ACK" and event.packet.payload and event.packet.payload.status == "ACCEPTED" then
            align_master.release_channels(self, "COMPLETE")
        end
    end
end

function align_master.step_fsm(self, event, now_ms)
    local inst = (type(self) == "table" and self.state) and self or active_session
    if not inst or not event then return end

    if event.type == "ABORT" or inst.state == "ABORTING" then
        inst.state = "ABORTING"
        send_zero_pulse(inst)
        local station = inst.station or get_station_cfg(inst.cfg)
        send_pkt(inst, inst.cmd_ch, "MSG_CALIB_START", {
            action = "ABORT_CALIBRATION",
            stationId = station.stationId or "HANGAR_BAY_01",
            targetThruster = "ALL",
            timeoutSec = 0
        })
        align_master.release_channels(inst, normalize_close_reason(event.reason, "MANUAL"))
        return
    end

    if inst.state == "TUNING" or inst.state == "HANDSHAKE" then
        handle_tuning_or_handshake(inst, event, now_ms)
    elseif inst.state == "DISCOVERY" then
        handle_discovery(inst, event, now_ms)
    elseif inst.state == "INTEGRATING" then
        handle_integrating(inst, event, now_ms)
    elseif inst.state == "SETTLING" then
        handle_settling(inst, event, now_ms)
    elseif inst.state == "ANOMALY_PAUSE" then
        handle_anomaly_pause(inst, event, now_ms)
    elseif inst.state == "SYNC_APPROVAL" or inst.state == "SYNCING" then
        handle_approval_and_sync(inst, event)
    end
end

local function build_remote_status_pkt(inst, meta, status_str, reason_str, t_ms)
    local seq_num = 1
    if inst then
        inst.seq = (inst.seq or 0) + 1
        seq_num = inst.seq
    end
    local idx = inst and inst.actuator_idx or 1
    local thr = inst and inst.actuators and inst.actuators[idx] or nil
    local eval_res = inst and inst.eval_result or nil
    local reg = inst and inst.last_regression or nil
    local payload = {
        stationId = meta.stationId,
        bayId = meta.bayId,
        aircraftIndexN = meta.aircraftIndexN,
        fsmState = (inst and inst.state) or "STANDBY",
        status = status_str,
        targetCraftDomain = meta.targetCraftDomain,
        baseHangarChannel = meta.baseHangarChannel,
        craftBaseChannel = meta.craftBaseChannel,
    }
    if type(thr) == "string" then payload.activeThruster = thr end
    if eval_res and type(eval_res.status) == "string" then payload.controllabilityStatus = eval_res.status end
    if reg and type(reg.confidenceR2) == "number" then payload.confidenceR2 = reg.confidenceR2 end
    if reason_str ~= nil then payload.reason = reason_str end
    return {
        ver = "1.9.5",
        domainId = meta.targetCraftDomain or "AIRCRAFT_01",
        seq = seq_num,
        type = "MSG_ALIGN_REMOTE_STATUS",
        time = t_ms,
        payload = payload,
    }
end

local function emit_remote_status(inst, m_obj, telem_ch, meta, status_str, reason_str, t_ms)
    local out = build_remote_status_pkt(inst, meta, status_str, reason_str, t_ms)
    modem_transmit(m_obj, telem_ch, telem_ch, out)
    return out
end

local function make_session_cfg(eff_cfg, req, hangar_base)
    local merged = {}
    for k, v in pairs(eff_cfg or {}) do
        merged[k] = v
    end
    local st = {}
    for k, v in pairs(get_station_cfg(eff_cfg)) do
        st[k] = v
    end
    st.stationId = req.stationId
    st.bayId = req.bayId
    st.baseHangarChannel = hangar_base
    merged.station = st
    return merged
end

local REMOTE_ALIGN_HANDLERS = {
    START_PULSE = function(inst, _req, t_ms)
        if inst.state ~= "DISCOVERY" then return "REJECTED", "INVALID_STATE_" .. tostring(inst.state) end
        align_master.step_fsm(inst, { type = "START_PULSE_SEQUENCE" }, t_ms)
        return "PULSE_STARTED", nil
    end,
    PAUSE_SESSION = function(inst, req, _t_ms)
        if inst.state == "INTEGRATING" then
            send_zero_pulse(inst)
        end
        inst.state = "ANOMALY_PAUSE"
        return "PAUSED", req.reason
    end,
    RETRY_STEP = function(inst, _req, t_ms)
        if inst.state ~= "ANOMALY_PAUSE" and inst.state ~= "INTEGRATING" and inst.state ~= "SETTLING" then
            return "REJECTED", "INVALID_STATE_" .. tostring(inst.state)
        end
        if not inst.actuators or #inst.actuators == 0 then
            inst.actuators = { "THR_MAIN_L" }
            inst.actuator_idx = 1
        end
        inst.state = "ANOMALY_PAUSE"
        align_master.step_fsm(inst, { type = "RETRY" }, t_ms)
        return "RETRYING", nil
    end,
    APPROVE_SYNC = function(inst, req, t_ms)
        if inst.state ~= "SYNC_APPROVAL" then return "REJECTED", "INVALID_STATE_" .. tostring(inst.state) end
        if not (inst.eval_result and inst.eval_result.passed) then return "REJECTED", "AUTHORITY_NOT_PASSED" end
        align_master.step_fsm(inst, { type = "USER_APPROVE", saveProfile = req.saveProfile }, t_ms)
        return "SYNCING", nil
    end,
    ABORT_SESSION = function(inst, req, t_ms)
        align_master.step_fsm(inst, { type = "ABORT", reason = normalize_close_reason(req.reason, "MANUAL") }, t_ms)
        return "ABORTED", req.reason
    end,
}

local function extract_remote_req(pkt, eff_cfg)
    local p = pkt.payload
    local station = get_station_cfg(eff_cfg)
    local bay_id = p.bayId
    local aircraft_n = p.aircraftIndexN
    local hangar_base = align_master.compute_hangar_base(bay_id) or p.baseHangarChannel or station.baseHangarChannel or HANGAR_BASE_MIN
    local craft_base = align_master.compute_craft_base(aircraft_n)
    local raw_dom = p.targetCraftDomain
    local dom = (type(raw_dom) == "string" and raw_dom ~= "" and raw_dom ~= "*") and raw_dom
        or (aircraft_n and string.format("AIRCRAFT_%02d", math.floor(tonumber(aircraft_n) or 1)))
        or "AIRCRAFT_01"
    local station_id = (type(p.stationId) == "string" and p.stationId ~= "") and p.stationId
        or station.stationId or string.format("HANGAR_BAY_%02d", tonumber(bay_id) or 1)
    return {
        action = p.action,
        stationId = station_id,
        bayId = bay_id,
        aircraftIndexN = aircraft_n,
        targetCraftDomain = dom,
        baseHangarChannel = hangar_base,
        craftBaseChannel = craft_base,
        reason = p.reason,
        saveProfile = p.saveProfile,
        source = p.source,
    }
end

--- Handle incoming MSG_ALIGN_REMOTE_CMD on Base_hangar+0 and transmit MSG_ALIGN_REMOTE_STATUS on Base_hangar+1.
function align_master.handle_remote_cmd(self, pkt, cfg, modem, now_ms)
    if type(pkt) ~= "table" or pkt.ver ~= "1.9.5" or pkt.type ~= "MSG_ALIGN_REMOTE_CMD" or type(pkt.payload) ~= "table" then
        return self, nil
    end
    local inst = (type(self) == "table" and self.state) and self or nil
    local eff_cfg = cfg or (inst and inst.cfg) or {}
    local eff_modem = modem or (inst and inst.modem)
    local t_ms = now_ms or epoch_ms()
    local req = extract_remote_req(pkt, eff_cfg)
    local telem_ch = (req.baseHangarChannel or HANGAR_BASE_MIN) + 1

    local valid_bay = type(req.bayId) == "number" and math.floor(req.bayId) == req.bayId and req.bayId >= 1 and req.bayId <= 10
    if not valid_bay or not req.craftBaseChannel then
        return inst, emit_remote_status(inst, eff_modem, telem_ch, req, "REJECTED", "INVALID_REMOTE_PARAMS", t_ms)
    end
    if req.source ~= nil and type(req.source) ~= "string" then
        return inst, emit_remote_status(inst, eff_modem, telem_ch, req, "REJECTED", "INVALID_SOURCE", t_ms)
    end

    if req.action == "BIND_SESSION" then
        local mcfg = make_session_cfg(eff_cfg, req, req.baseHangarChannel)
        inst = init_session_into(inst or setmetatable({}, align_master), mcfg, req.targetCraftDomain, req.craftBaseChannel, eff_modem, t_ms)
        return inst, emit_remote_status(inst, eff_modem, inst.telem_ch, req, "SESSION_STARTED", req.reason, t_ms)
    end
    if not inst or inst.state == "STANDBY" then
        return inst, emit_remote_status(inst, eff_modem, telem_ch, req, "REJECTED", "NO_ACTIVE_SESSION", t_ms)
    end
    if req.action == "RELEASE_SESSION" then
        local close_reason = normalize_close_reason(req.reason, req.saveProfile == false and "MANUAL" or "COMPLETE")
        local out = emit_remote_status(inst, eff_modem, inst.telem_ch, req, "RELEASED", req.reason, t_ms)
        align_master.release_channels(inst, close_reason)
        return inst, out
    end
    local handler = REMOTE_ALIGN_HANDLERS[req.action]
    if not handler then
        return inst, emit_remote_status(inst, eff_modem, inst.telem_ch, req, "REJECTED", "UNKNOWN_ACTION", t_ms)
    end
    local status_str, reason_str = handler(inst, req, t_ms)
    return inst, emit_remote_status(inst, eff_modem, inst.telem_ch, req, status_str, reason_str, t_ms)
end

align_master.build_profile_payload = build_profile_payload

return align_master
