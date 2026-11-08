-- src/0_infra/landing_pad/main.lua
-- Landing Pad Controller 20Hz non-blocking main daemon and console

local config_store = require("modules.config_store")
local offset_transform = require("modules.offset_transform")
local sensor_adapter = require("modules.sensor_adapter")
local gps_client = require("modules.gps_client")
local tactical_streamer = require("modules.tactical_streamer")
local pad_fsm = require("modules.pad_fsm")
local setup_wizard = require("modules.setup_wizard")
local tui_view = require("modules.tui_view")

local CONFIG_FILE = "/landing_pad/config.json"
local GPS_PING_CHANNEL = 60001
local TICK_INTERVAL = 0.05 -- 20Hz

local function main()
    local tui = tui_view.create(term)

    -- 1. Configuration Loading / Countdown
    local cfg = config_store.load_config(CONFIG_FILE)
    if not cfg then
        cfg = config_store.create_default()
        config_store.save_config(CONFIG_FILE, cfg)
    end

    -- 2. Hardware Peripheral Discovery
    local modem = peripheral.find("modem", function(name, dev)
        return dev.isWireless and dev.isWireless()
    end) or peripheral.find("modem")

    local sensorAdapter = sensor_adapter.create(cfg.mode, nil)
    local sensorsOk, scanReport = sensorAdapter:scan_peripherals()

    -- 3. Channel Initialization
    local channelsToOpen = {
        cfg.channels and cfg.channels.sectorFacilityChannel or 50202,
        cfg.channels and cfg.channels.sectorGpsReplyChannel or 50206,
        cfg.channels and cfg.channels.tacticalChannel or 50211,
        GPS_PING_CHANNEL
    }

    if modem then
        for _, ch in ipairs(channelsToOpen) do
            if not modem.isOpen(ch) then
                modem.open(ch)
            end
        end
    end

    -- 4. Subsystem Instantiation
    local gpsClient = gps_client.create(cfg, offset_transform)
    local streamer = tactical_streamer.create(cfg)
    local fsm = pad_fsm.create(cfg, streamer, sensorAdapter:is_healthy())

    local running = true
    local timerId = os.startTimer(TICK_INTERVAL)
    local tickCount = 0
    local seq = 45000
    local lastGacSyncSec = 0.0
    local lastLog = "[INIT] Landing Pad daemon online: " .. tostring(cfg.padId)

    local function cleanup()
        if modem then
            for _, ch in ipairs(channelsToOpen) do
                if modem.isOpen(ch) then
                    modem.close(ch)
                end
            end
        end
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(1, 1)
    end

    local function send_packet(channel, pkt)
        if modem and channel and pkt then
            modem.transmit(channel, channel, pkt)
        end
    end

    -- 5. Main Event Loop
    while running do
        local eventData = { os.pullEventRaw() }
        local event = eventData[1]
        local nowClock = os.clock and os.clock() or 0

        if event == "timer" and eventData[2] == timerId then
            timerId = os.startTimer(TICK_INTERVAL)
            tickCount = tickCount + 1
            seq = seq + 1

            local kin = {
                velocity = { vx = 0, vy = 0, vz = 0 },
                acceleration = { ax = 0, ay = 0, az = 0 },
                attitude = { pitch = 0, roll = 0, yaw = 0 },
                angularRates = { pitchRate = 0, rollRate = 0, yawRate = 0 }
            }
            local deckStatus = "STABLE"
            local landingPermitted = true
            local tiltAngle = 0.0

            if cfg.mode == "DYNAMIC" then
                local kRead, kErr = sensorAdapter:read_kinematics()
                if kRead then
                    kin = kRead
                    local status, permitted, tilt = sensorAdapter:evaluate_deck_stability(
                        kin.attitude.pitch, kin.attitude.roll, kin.velocity.vy
                    )
                    deckStatus = status
                    landingPermitted = permitted
                    tiltAngle = tilt
                end
                gpsClient:update_dead_reckoning(TICK_INTERVAL, kin)
            end

            local padPos = gpsClient:get_current_pad_pos()
            local currentState = fsm:get_state()

            -- 20Hz Guidance Stream
            if currentState == "APPROACH_DYNAMIC" then
                local guidePkt = streamer:build_dynamic_guide(
                    seq,
                    fsm:get_current_craft(),
                    padPos,
                    kin,
                    deckStatus,
                    landingPermitted,
                    tiltAngle,
                    kin.velocity.vy,
                    false
                )
                send_packet(cfg.channels.tacticalChannel, guidePkt)
                lastLog = string.format("[TX] DYN_GUIDE seq=%d -> %s", seq, tostring(fsm:get_current_craft()))
            elseif currentState == "APPROACH_STATIC" and (tickCount % 20 == 0) then
                local staticPkt = streamer:build_static_guide(
                    seq,
                    fsm:get_current_craft(),
                    padPos,
                    { speed = 0, direction = 0 },
                    false
                )
                send_packet(cfg.channels.tacticalChannel, staticPkt)
                lastLog = string.format("[TX] STATIC_GUIDE seq=%d -> %s", seq, tostring(fsm:get_current_craft()))
            end

            -- 1Hz periodic tasks (every 20 ticks)
            if tickCount % 20 == 0 then
                -- GPS request
                local reqPkt = gpsClient:build_request_packet(padPos.y)
                send_packet(GPS_PING_CHANNEL, reqPkt)

                -- Local backbone facility status update
                local velForUpd = (cfg.mode == "DYNAMIC") and kin.velocity or nil
                local headingForUpd = (cfg.mode == "DYNAMIC") and kin.attitude.yaw or nil
                local updPkt = streamer:build_facility_update(
                    seq,
                    currentState,
                    fsm:get_current_craft(),
                    fsm:get_fault_code(),
                    padPos,
                    headingForUpd,
                    velForUpd
                )
                send_packet(cfg.channels.sectorFacilityChannel, updPkt)
                lastGacSyncSec = 0.0

                -- Sensor auto-reconnect check
                sensorAdapter:check_auto_reconnect(nowClock)
                gpsClient:check_gps_health(nowClock)
            else
                lastGacSyncSec = lastGacSyncSec + TICK_INTERVAL
            end

            -- FSM tick
            local fsmActions = fsm:tick(TICK_INTERVAL, nowClock, deckStatus, sensorAdapter:is_healthy())
            for _, act in ipairs(fsmActions) do
                if act.type == "MSG_ABORT_APPROACH" then
                    send_packet(cfg.channels.tacticalChannel, act)
                    send_packet(cfg.channels.sectorFacilityChannel, act)
                    lastLog = string.format("[ALERT] %s issued: %s", act.type, tostring(act.payload.reason))
                else
                    send_packet(cfg.channels.sectorFacilityChannel, act)
                end
            end

            -- Render TUI
            tui:render_daemon({
                padId = cfg.padId,
                mode = cfg.mode,
                sectorIndex = cfg.sectorIndex,
                tacticalChannel = cfg.channels.tacticalChannel,
                state = currentState,
                targetAircraft = fsm:get_current_craft(),
                touchdownPoint = padPos,
                velocity = kin.velocity,
                tiltAngleDeg = tiltAngle,
                heaveRateMps = kin.velocity.vy,
                deckStatus = deckStatus,
                landingPermitted = landingPermitted,
                lastGacSyncSec = lastGacSyncSec,
                slotRemainingSec = 120,
                slotDurationSec = 120,
                lastLog = lastLog
            })

        elseif event == "modem_message" then
            local side = eventData[2]
            local senderCh = eventData[3]
            local replyCh = eventData[4]
            local msg = eventData[5]

            if senderCh == cfg.channels.sectorFacilityChannel then
                local outPkts = fsm:handle_backbone_message(msg, nowClock)
                for _, pkt in ipairs(outPkts) do
                    send_packet(cfg.channels.sectorFacilityChannel, pkt)
                    lastLog = string.format("[BACKBONE] %s -> %s", pkt.type, tostring(pkt.payload.status or "OK"))
                end
            elseif senderCh == cfg.channels.tacticalChannel then
                local outPkts = fsm:handle_tactical_message(msg, nowClock)
                for _, pkt in ipairs(outPkts) do
                    send_packet(cfg.channels.sectorFacilityChannel, pkt)
                    lastLog = string.format("[TACTICAL] %s -> %s", pkt.type, tostring(pkt.payload.status or "OK"))
                end
            elseif senderCh == cfg.channels.sectorGpsReplyChannel then
                local handled = gpsClient:handle_response_packet(msg, nowClock)
                if handled then
                    lastLog = string.format("[GPS] Fix updated: X=%.1f Z=%.1f", gpsClient:get_current_comp_pos().x, gpsClient:get_current_comp_pos().z)
                end
            end

        elseif event == "char" then
            local ch = string.lower(tostring(eventData[2] or ""))
            if ch == "q" then
                running = false
            elseif ch == "f" then
                local upd = fsm:force_free()
                send_packet(cfg.channels.sectorFacilityChannel, upd)
                lastLog = "[OP] Force free command executed"
            end

        elseif event == "terminate" then
            running = false
        end
    end

    cleanup()
end

if _G.describe == nil then
    main()
end

return { run = main }
