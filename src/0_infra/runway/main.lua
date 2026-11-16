-- src/0_infra/runway/main.lua
-- Runway Controller 20Hz non-blocking main daemon and console

local config_store = require("modules.config_store")
local offset_transform = require("modules.offset_transform")
local sensor_adapter = require("modules.sensor_adapter")
local lighting_controller = require("modules.lighting_controller")
local gps_client = require("modules.gps_client")
local tactical_streamer = require("modules.tactical_streamer")
local runway_fsm = require("modules.runway_fsm")
local setup_wizard = require("modules.setup_wizard")
local tui_view = require("modules.tui_view")

local CONFIG_FILE = "/runway/config.json"
local GPS_PING_CHANNEL = 60001
local TICK_INTERVAL = 0.05

local function transmit_pkt(modem, ch, pkt, replyCh)
    if modem and ch and pkt then modem.transmit(ch, replyCh or ch, pkt) end
end

local function step_20hz(app, nowClock)
    app.tickCount = app.tickCount + 1
    app.seq = app.seq + 1
    local kin = {
        velocity = { vx = 0, vy = 0, vz = 0 },
        acceleration = { ax = 0, ay = 0, az = 0 },
        attitude = { pitch = 0, roll = 0, yaw = app.cfg.approachHeading or 0.0 },
        angularRates = { pitchRate = 0, rollRate = 0, yawRate = 0 },
    }
    local deckStatus, landingPermitted = "STABLE", true
    if app.cfg.mobility == "DYNAMIC" then
        local kRead = app.sensorAdapter:read_kinematics()
        if kRead then
            kin = kRead
            deckStatus, landingPermitted = app.sensorAdapter:evaluate_deck_stability(kin.attitude.pitch, kin.attitude.roll, kin.velocity.vy)
            kin.velocity = offset_transform.calculate_point_velocity(kin.velocity, kin.attitude, kin.angularRates, app.cfg.mountingYawOffset, app.cfg.touchdownOffset)
        end
        app.gpsClient:update_dead_reckoning(TICK_INTERVAL, kin)
    end
    local tdPos, epPos = app.gpsClient:get_current_touchdown_pos(), app.gpsClient:get_current_end_pos()
    local curState = app.fsm:get_state()
    if curState == "APPROACH_DYNAMIC" then
        transmit_pkt(app.modem, app.cfg.channels.tacticalChannel,
            app.streamer:build_dynamic_guide(app.seq, app.fsm:get_current_craft(), tdPos, epPos, kin, deckStatus, landingPermitted, false))
    elseif curState == "APPROACH_STATIC" and (app.tickCount % 20 == 0) then
        transmit_pkt(app.modem, app.cfg.channels.tacticalChannel,
            app.streamer:build_static_guide(app.seq, app.fsm:get_current_craft(), tdPos, epPos, false))
    end
    if app.gpsClient:should_query_gps(curState, app.tickCount) then
        local cPos = app.gpsClient:get_current_comp_pos()
        local req = app.gpsClient:build_request_packet(cPos.y)
        transmit_pkt(app.modem, GPS_PING_CHANNEL, req, req.payload.replyChannel)
    end
    if app.tickCount % 20 == 0 then
        local upd = app.streamer:build_facility_update(app.seq, curState, app.fsm:get_current_craft(), app.fsm:get_fault_code(), tdPos)
        transmit_pkt(app.modem, app.cfg.channels.sectorFacilityChannel, upd)
        app.lastGacSyncSec = 0.0
        app.sensorAdapter:check_auto_reconnect(nowClock)
        app.gpsClient:check_gps_health(nowClock)
    else
        app.lastGacSyncSec = app.lastGacSyncSec + TICK_INTERVAL
    end
    for _, act in ipairs(app.fsm:tick(TICK_INTERVAL, nowClock, deckStatus, app.sensorAdapter:is_healthy())) do
        local dest = (act.type == "MSG_ABORT_APPROACH") and app.cfg.channels.tacticalChannel or app.cfg.channels.sectorFacilityChannel
        transmit_pkt(app.modem, dest, act)
    end
    local lState = app.testLightState or curState
    local lStat = app.lighting:apply_state(lState, { speed = 0, direction = app.cfg.approachHeading or 0 }, app.tickCount)
    app.tui:render_daemon({
        facilityId = app.cfg.facilityId, mobility = app.cfg.mobility, sectorId = app.cfg.sectorId,
        tacticalChannel = app.cfg.channels.tacticalChannel, state = curState, targetAircraft = app.fsm:get_current_craft(),
        touchdownPoint = tdPos, endPoint = epPos, glideSlopeAngle = app.cfg.glideSlopeAngle,
        touchdownZoneLength = app.cfg.touchdownZoneLength, approachHeading = app.cfg.approachHeading,
        deckStatus = deckStatus, landingPermitted = landingPermitted, lightStatus = lStat,
        lastGacSyncSec = app.lastGacSyncSec, slotRemainingSec = app.fsm:get_slot_remaining_sec(nowClock), lastLog = app.lastLog,
    })
end

local function handle_modem_rx(app, ch, msg, nowClock)
    if ch == app.cfg.channels.sectorFacilityChannel then
        for _, p in ipairs(app.fsm:handle_backbone_message(msg, nowClock)) do transmit_pkt(app.modem, ch, p) end
    elseif ch == app.cfg.channels.tacticalChannel then
        for _, p in ipairs(app.fsm:handle_tactical_message(msg, nowClock)) do transmit_pkt(app.modem, app.cfg.channels.sectorFacilityChannel, p) end
    elseif ch == app.cfg.channels.sectorGpsReplyChannel then
        if app.gpsClient:handle_response_packet(msg, nowClock) then app.lastLog = "[GPS] Runway fix updated" end
    end
end

local function run_wizard_apply(app)
    local nextCfg = app.wizard:assemble_config(app.cfg)
    config_store.save_config(CONFIG_FILE, nextCfg)
    app.cfg = nextCfg
    app.lastLog = "[WIZ] Config re-saved via Setup Wizard"
end

local function main()
    local cfg = config_store.load_config(CONFIG_FILE) or config_store.get_default_config()
    cfg = config_store.normalize_config(cfg)
    local modem = peripheral.find("modem", function(_, d) return d.isWireless and d.isWireless() end) or peripheral.find("modem")
    local sa = sensor_adapter.create(cfg.mobility, nil)
    sa:scan_peripherals()
    local chs = { cfg.channels.sectorFacilityChannel, cfg.channels.sectorGpsReplyChannel, cfg.channels.tacticalChannel }
    if modem then for _, ch in ipairs(chs) do if not modem.isOpen(ch) then modem.open(ch) end end end
    local streamer = tactical_streamer.create(cfg)
    local app = {
        cfg = cfg, modem = modem, sensorAdapter = sa, streamer = streamer,
        lighting = lighting_controller.create(sa:get_wired_devices()),
        gpsClient = gps_client.create(cfg, offset_transform),
        fsm = runway_fsm.create(cfg, streamer, sa:is_healthy()),
        wizard = setup_wizard.create(offset_transform),
        tui = tui_view.create(term),
        tickCount = 0, seq = 55000, lastGacSyncSec = 0.0, lastLog = "[INIT] Runway daemon online", testLightState = nil,
    }
    local timerId = os.startTimer(TICK_INTERVAL)
    while true do
        local ev = { os.pullEventRaw() }
        local nowClock = os.clock and os.clock() or 0
        if ev[1] == "timer" and ev[2] == timerId then
            timerId = os.startTimer(TICK_INTERVAL); step_20hz(app, nowClock)
        elseif ev[1] == "modem_message" then
            handle_modem_rx(app, ev[3], ev[5], nowClock)
        elseif ev[1] == "char" then
            local k = string.lower(tostring(ev[2] or ""))
            if k == "q" then break
            elseif k == "f" then transmit_pkt(modem, cfg.channels.sectorFacilityChannel, app.fsm:force_free()); app.lastLog = "[OP] Force FREE"
            elseif k == "l" then app.testLightState = (app.testLightState == nil) and "WAVE_OFF" or nil; app.lastLog = "[OP] Light test toggled"
            elseif k == "s" then run_wizard_apply(app) end
        elseif ev[1] == "terminate" then break end
    end
    if modem then for _, ch in ipairs(chs) do if modem.isOpen(ch) then modem.close(ch) end end end
end

if _G.describe == nil then main() end
return { run = main }
