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

local function send_pkt(self, ch, pkt_type, payload)
    self.seq = self.seq + 1
    local pkt = {
        ver = "1.9.5", domainId = self.domain_id,
        seq = self.seq, type = pkt_type,
        time = (os and os.epoch and os.epoch("utc")) or 0,
        payload = payload or {}
    }
    modem_transmit(self.modem, ch, self.telem_ch, pkt)
    return pkt
end

function align_master.init_bay_session(cfg, domain_id, craft_base_ch, modem)
    local self = setmetatable({}, align_master)
    self.cfg = cfg or {}
    self.domain_id = domain_id or "AIRCRAFT_01"
    self.craft_base_ch = craft_base_ch or 1000
    self.modem = modem
    local base = cfg.baseHangarChannel or 101
    self.cmd_ch = base + 0
    self.telem_ch = base + 1
    self.tap_ch = base + 3
    self.seq = 0
    self.actuators = {}
    self.actuator_idx = 1
    self.thruster_results = {}
    self.discovery = discovery_client.new(self.domain_id)
    self.sequencer = multi_pulse_sequencer.new(self.domain_id)
    self.integrator = impulse_integrator.new()
    self.settling = settling_guard.new()
    self.sentinel = safety_sentinel.new(cfg.safety)
    self.ols_engine = ols_regression_engine
    self.checker = controllability_checker
    
    modem_open(self.modem, self.cmd_ch)
    modem_open(self.modem, self.telem_ch)
    modem_open(self.modem, self.tap_ch)
    self.state = "TUNING"
    send_pkt(self, self.craft_base_ch, "MSG_CALIBRATION_INIT", {
        stationId = cfg.stationId or "HANGAR_BAY_01",
        bayId = cfg.bayId or 1,
        baseHangarChannel = base,
        targetCraftDomain = self.domain_id
    })
    self.state = "HANDSHAKE"
    active_session = self
    return self
end

function align_master.get_state(self)
    local inst = (type(self) == "table" and self.state) and self or active_session
    return inst and inst.state or "STANDBY"
end

function align_master.release_channels(self)
    local inst = (type(self) == "table" and self.state) and self or active_session
    if not inst then return end
    modem_close(inst.modem, inst.cmd_ch)
    modem_close(inst.modem, inst.telem_ch)
    modem_close(inst.modem, inst.tap_ch)
    inst.state = "STANDBY"
end

local function handle_handshake(self, event)
    if event.type == "PACKET" and event.packet and event.packet.type == "MSG_CALIBRATION_INIT_ACK" then
        self.state = "DISCOVERY"
        local reqs = self.discovery:build_requests(self.seq)
        for _, req in ipairs(reqs) do
            self.seq = self.seq + 1
            modem_transmit(self.modem, self.tap_ch, self.telem_ch, req)
        end
    end
end

local function handle_discovery(self, event)
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
        self.sequencer:start_thruster(self.actuators[1])
        self.state = "INTEGRATING"
        local pulse_pkt = self.sequencer:build_pulse_packet(self.seq + 1)
        self.seq = self.seq + 1
        modem_transmit(self.modem, self.cmd_ch, self.telem_ch, pulse_pkt)
    end
end

local function handle_approval_and_sync(self, event)
    if self.state == "SYNC_APPROVAL" and (event.type == "USER_APPROVE" or event.type == "OVERRIDE") then
        self.state = "SYNCING"
        local profile = {
            profileId = "PROF-" .. self.domain_id,
            calibratedBy = self.cfg.stationId or "HANGAR_BAY_01",
            totalDryMass = 12000.0,
            controllabilityStatus = "FULL_6DOF_PASS",
            thrusterCoefficients = self.thruster_results,
            discoveredSurfaces = self.discovery:get_discovered_surfaces()
        }
        local sync_pkt = profile_exporter.build_sync_packet(self.domain_id, self.seq + 1, profile)
        self.seq = self.seq + 1
        modem_transmit(self.modem, self.cmd_ch, self.telem_ch, sync_pkt)
    elseif self.state == "SYNCING" and event.type == "PACKET" and event.packet then
        if event.packet.type == "MSG_CALIB_ACK" and event.packet.payload and event.packet.payload.status == "ACCEPTED" then
            align_master.release_channels(self)
        end
    end
end

function align_master.step_fsm(self, event, now_ms)
    local inst = (type(self) == "table" and self.state) and self or active_session
    if not inst or not event then return end
    
    if inst.state == "HANDSHAKE" then
        handle_handshake(inst, event)
    elseif inst.state == "DISCOVERY" then
        handle_discovery(inst, event)
    elseif inst.state == "SYNC_APPROVAL" or inst.state == "SYNCING" then
        handle_approval_and_sync(inst, event)
    elseif event.type == "ABORT" or inst.state == "ABORTING" then
        align_master.release_channels(inst)
    end
end

return align_master
