-- src/0_infra/gac/main.lua
-- Ground Apron Controller (GAC) 20Hz non-blocking main daemon and console

local config_loader = require("modules.config_loader")
local facility_inventory = require("modules.facility_inventory")
local allocation_engine = require("modules.allocation_engine")
local beacon_broadcaster = require("modules.beacon_broadcaster")
local gac_fsm = require("modules.gac_fsm")
local tui_view = require("modules.tui_view")

local CONFIG_FILE = "/gac/config.json"

local function main()
    -- 1. Load Configuration
    local cfg, loadErr = config_loader.load_config(CONFIG_FILE)
    if not cfg then
        cfg = config_loader.get_default_config()
    end

    -- 2. Hardware Peripheral Discovery
    local modem = peripheral.find("modem", function(name, dev)
        return dev.isWireless and dev.isWireless()
    end) or peripheral.find("modem")

    local monitor = peripheral.find("monitor")

    -- 3. Channel Initialization
    local channelsToOpen = {
        cfg.towerAtcChannel or 50001,
        50002, -- Wide-area backbone
        50004, -- Dispatch
        cfg.baseSecChannel or 50201, -- Sector Comm (Base_sec + 0)
        (cfg.baseSecChannel or 50201) + 1 -- Local Backbone (Base_sec + 1)
    }

    if modem then
        for _, ch in ipairs(channelsToOpen) do
            if not modem.isOpen(ch) then
                modem.open(ch)
            end
        end
    end

    -- 4. Subsystem Instantiation
    local inventory = facility_inventory.create(cfg.facilities)
    local fsm = gac_fsm.create(cfg, inventory, allocation_engine)
    local broadcaster = beacon_broadcaster.create(cfg)
    local tui = tui_view.create(term, monitor)

    tui:add_log("[INIT] GAC online for sector: " .. tostring(cfg.sectorId))

    -- 5. Main Loop Variables
    local running = true
    local TICK_INTERVAL = 0.05 -- 20Hz
    local timerId = os.startTimer(TICK_INTERVAL)
    local nowClock = os.clock and os.clock() or 0

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

    local function save_current_config()
        cfg.facilities = inventory:get_all_facilities()
        config_loader.save_config(CONFIG_FILE, cfg)
    end

    -- 6. Event Loop
    while running do
        local eventData = { os.pullEventRaw() }
        local event = eventData[1]
        nowClock = os.clock and os.clock() or 0

        if event == "timer" and eventData[2] == timerId then
            -- 20Hz Tick
            timerId = os.startTimer(TICK_INTERVAL)

            -- 1Hz Beacon & Dispatch Broadcast
            local sectorStatus = inventory:is_emergency_lockdown() and "DECK_DANGEROUS" or "OPERATIONAL"
            if modem then
                broadcaster:broadcast_1hz(modem, inventory, cfg.surfaceWind, sectorStatus, nowClock)
            end

            -- FSM Slot Expiry Tick
            local timeoutActions = fsm:tick(nowClock)
            for _, act in ipairs(timeoutActions) do
                tui:add_log(string.format("[TIMEOUT] Slot expired on %s for %s", act.facilityId, act.aircraftId or "?"))
                -- Notify local backbone of free pad
                if modem then
                    local updateMsg = {
                        ver = "1.9.5",
                        domainId = cfg.sectorId,
                        seq = os.time(),
                        type = "MSG_ATC_FACILITY_UPDATE",
                        time = os.epoch and os.epoch("utc") or (os.time() * 1000),
                        payload = { facilityId = act.facilityId, status = "FREE", currentCraft = nil }
                    }
                    modem.transmit((cfg.baseSecChannel or 50201) + 1, cfg.baseSecChannel, updateMsg)
                end
            end

            -- Render TUI
            tui:render({
                config = cfg,
                surfaceWind = cfg.surfaceWind,
                sectorStatus = sectorStatus,
                summary = inventory:get_summary(),
                facilities = inventory:get_all_facilities(),
                traffic = {}
            })

        elseif event == "modem_message" then
            local side, senderChannel, replyChannel, message, distance = eventData[2], eventData[3], eventData[4], eventData[5], eventData[6]
            if type(message) == "table" and message.type then
                local mType = message.type
                tui:add_log(string.format("[RF RX] %s on CH %d", mType, senderChannel))

                if mType == "MSG_ATC_SECTOR_HANDOFF_REQ" then
                    local ack = fsm:handle_tower_handoff_req(message)
                    if modem and replyChannel then
                        modem.transmit(replyChannel, cfg.baseSecChannel, ack)
                    end
                elseif mType == "MSG_GAC_CHECKIN_REQ" then
                    local slotAssign, clearance = fsm:handle_aircraft_checkin(message, cfg.surfaceWind)
                    if slotAssign and modem then
                        -- Send slot assign to pad on local backbone
                        modem.transmit((cfg.baseSecChannel or 50201) + 1, cfg.baseSecChannel, slotAssign)
                    elseif clearance and modem and replyChannel then
                        modem.transmit(replyChannel, cfg.baseSecChannel, clearance)
                    end
                elseif mType == "MSG_ATC_SLOT_ACK" then
                    local clearance = fsm:handle_pad_slot_ack(message)
                    if clearance and modem then
                        -- Broadcast clearance on GAC Comm channel to aircraft
                        modem.transmit(cfg.baseSecChannel or 50201, cfg.baseSecChannel, clearance)
                    end
                elseif mType == "MSG_ATC_FACILITY_UPDATE" then
                    local statusMsg = fsm:handle_facility_update(message)
                    if statusMsg and modem then
                        modem.transmit(50002, cfg.baseSecChannel, statusMsg)
                    end
                elseif mType == "MSG_ABORT_APPROACH" then
                    fsm:handle_abort_approach(message)
                    tui:add_log(string.format("[ALERT] Abort on %s: %s", message.payload.facilityId or "?", message.payload.reason or "?"))
                elseif mType == "MSG_ATC_ABORT_CLEAR" then
                    local slotAssign, divert = fsm:handle_abort_clear(message, cfg.surfaceWind)
                    if slotAssign and modem then
                        modem.transmit((cfg.baseSecChannel or 50201) + 1, cfg.baseSecChannel, slotAssign)
                    elseif divert and modem and replyChannel then
                        modem.transmit(replyChannel, cfg.baseSecChannel, divert)
                    end
                elseif mType == "MSG_GAC_DEPARTURE_REQ" then
                    local depClearance = fsm:handle_departure_req(message)
                    if modem and replyChannel then
                        modem.transmit(replyChannel, cfg.baseSecChannel, depClearance)
                    end
                elseif mType == "MSG_ATC_DEPARTURE_COMPLETE" then
                    local statusMsg = fsm:handle_departure_complete(message)
                    if statusMsg and modem then
                        modem.transmit(50002, cfg.baseSecChannel, statusMsg)
                    end
                end
            end

        elseif event == "key" or event == "char" then
            local action, data
            if event == "key" then
                action, data = tui:handle_key(eventData[2], nil, { facilities = inventory:get_all_facilities() })
            else
                action, data = tui:handle_key(nil, eventData[2], { facilities = inventory:get_all_facilities() })
            end

            if action == "QUIT" then
                running = false
            elseif action == "TOGGLE_EMERGENCY" then
                local isEmg = not inventory:is_emergency_lockdown()
                inventory:set_emergency_lockdown(isEmg)
                tui:add_log(isEmg and "[OP] EMERGENCY LOCKDOWN ENGAGED!" or "[OP] Emergency lockdown disengaged.")
                -- Broadcast wave-off on all tactical channels
                if isEmg and modem then
                    for _, fac in ipairs(inventory:get_all_facilities()) do
                        if fac.tacticalChannel then
                            local waveOff = {
                                ver = "1.9.5",
                                domainId = cfg.sectorId,
                                seq = os.time(),
                                type = "MSG_ABORT_APPROACH",
                                time = os.epoch and os.epoch("utc") or (os.time() * 1000),
                                payload = { facilityId = fac.facilityId, reason = "GAC_ORDER", recommendedClimbAltitude = 100.0 }
                            }
                            modem.transmit(fac.tacticalChannel, cfg.baseSecChannel, waveOff)
                        end
                    end
                end
            elseif action == "TOGGLE_MAINTENANCE" and data then
                local allFacs = inventory:get_all_facilities()
                local targetFac = allFacs[data]
                if targetFac then
                    local nextStatus = (targetFac.status == "MAINTENANCE") and "FREE" or "MAINTENANCE"
                    inventory:update_status(targetFac.facilityId, nextStatus, nil)
                    tui:add_log(string.format("[OP] %s status -> %s", targetFac.facilityId, nextStatus))
                    save_current_config()
                end
            elseif action == "FORCE_FREE" and data then
                local allFacs = inventory:get_all_facilities()
                local targetFac = allFacs[data]
                if targetFac then
                    inventory:update_status(targetFac.facilityId, "FREE", nil)
                    tui:add_log(string.format("[OP] %s FORCE FREE reset", targetFac.facilityId))
                    save_current_config()
                end
            elseif action == "WAVE_OFF" and data then
                local allFacs = inventory:get_all_facilities()
                local targetFac = allFacs[data]
                if targetFac and targetFac.tacticalChannel and modem then
                    local waveOff = {
                        ver = "1.9.5",
                        domainId = cfg.sectorId,
                        seq = os.time(),
                        type = "MSG_ABORT_APPROACH",
                        time = os.epoch and os.epoch("utc") or (os.time() * 1000),
                        payload = { facilityId = targetFac.facilityId, reason = "GAC_ORDER", recommendedClimbAltitude = 100.0 }
                    }
                    modem.transmit(targetFac.tacticalChannel, cfg.baseSecChannel, waveOff)
                    inventory:update_status(targetFac.facilityId, "GO_AROUND", nil)
                    tui:add_log(string.format("[OP] Wave-off issued for %s", targetFac.facilityId))
                end
            end

        elseif event == "monitor_touch" then
            local side, x, y = eventData[2], eventData[3], eventData[4]
            tui:handle_touch(x, y, { facilities = inventory:get_all_facilities() })

        elseif event == "terminate" then
            running = false
        end
    end

    cleanup()
end

main()
