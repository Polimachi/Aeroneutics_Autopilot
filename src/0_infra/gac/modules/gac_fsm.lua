-- src/0_infra/gac/modules/gac_fsm.lua
-- Sector finite state machine and multi-tier handoff protocols for GAC

local gac_fsm = {}

local PROTOCOL_VER = "1.9.5"

function gac_fsm.create(config, inventory, allocator)
    local cfg = config or {}
    local inv = inventory
    local alloc = allocator

    local state = {
        seq = 3000,
        activeSlots = {}, -- facilityId -> { aircraftId, assignedAtSec, durationSec, craftReq }
        pendingAircraft = {}, -- aircraftId -> craftReq
        goAroundQueue = {} -- aircraftId -> info
    }

    local function get_time_ms()
        if os.epoch then
            return os.epoch("utc")
        end
        return os.time() * 1000
    end

    local function next_seq()
        state.seq = state.seq + 1
        return state.seq
    end

    local fsm = {}

    function fsm:record_slot_assignment(facilityId, craftId, assignedAtSec, durationSec, craftReq)
        state.activeSlots[facilityId] = {
            aircraftId = craftId,
            assignedAtSec = assignedAtSec or (os.clock and os.clock() or 0),
            durationSec = durationSec or cfg.slotDurationSec or 120,
            craftReq = craftReq
        }
    end

    function fsm:handle_tower_handoff_req(packet)
        local payload = packet and packet.payload or {}
        local accepted = false
        local rejectReason = nil

        if inv:is_emergency_lockdown() then
            rejectReason = "DECK_DANGEROUS"
        else
            local bestPad, errReason = alloc.select_best_pad(inv:get_all_facilities(), payload, cfg.surfaceWind)
            if bestPad then
                accepted = true
            else
                rejectReason = errReason or "SECTOR_ALL_OCCUPIED"
            end
        end

        return {
            ver = PROTOCOL_VER,
            domainId = cfg.sectorId or "GAC_NODE",
            seq = next_seq(),
            type = "MSG_ATC_SECTOR_HANDOFF_ACK",
            time = get_time_ms(),
            payload = {
                sectorId = cfg.sectorId,
                aircraftId = payload.aircraftId,
                status = accepted and "ACCEPTED" or "REJECTED",
                rejectReason = rejectReason,
                assignedGacChannel = accepted and (cfg.baseSecChannel or 50201) or nil
            }
        }
    end

    function fsm:handle_aircraft_checkin(packet, surfaceWind)
        local payload = packet and packet.payload or {}
        local craftId = payload.aircraftId or "UNKNOWN_CRAFT"
        state.pendingAircraft[craftId] = payload

        local bestPad, err = alloc.select_best_pad(inv:get_all_facilities(), payload, surfaceWind)
        if not bestPad then
            local clearance = {
                ver = PROTOCOL_VER,
                domainId = cfg.sectorId or "GAC_NODE",
                seq = next_seq(),
                type = "MSG_GAC_APPROACH_CLEARANCE",
                time = get_time_ms(),
                payload = {
                    sectorId = cfg.sectorId,
                    aircraftId = craftId,
                    status = (err == "SECTOR_ALL_OCCUPIED") and "HOLD" or "DENIED",
                    assignedFacilityId = nil,
                    assignedTacticalChannel = nil,
                    reason = err
                }
            }
            return nil, clearance
        end

        -- Reserve pad
        inv:update_status(bestPad.facilityId, "RESERVED", craftId)
        local nowSec = os.clock and os.clock() or 0
        fsm:record_slot_assignment(bestPad.facilityId, craftId, nowSec, cfg.slotDurationSec or 120, payload)

        local slotAssign = {
            ver = PROTOCOL_VER,
            domainId = cfg.sectorId or "GAC_NODE",
            seq = next_seq(),
            type = "MSG_ATC_SLOT_ASSIGN",
            time = get_time_ms(),
            payload = {
                facilityId = bestPad.facilityId,
                aircraftId = craftId,
                airframeType = payload.airframeType or "UNKNOWN",
                slotDurationSec = cfg.slotDurationSec or 120,
                tacticalChannel = bestPad.tacticalChannel
            }
        }

        return slotAssign, nil
    end

    function fsm:handle_pad_slot_ack(packet)
        local payload = packet and packet.payload or {}
        local facilityId = payload.facilityId
        local craftId = payload.aircraftId
        local status = payload.status

        if status == "ACCEPTED" then
            local pad = inv:get_facility(facilityId)
            local coords = pad and pad.coordinates or { x = 0, y = 0, z = 0 }
            local radius = pad and pad.maxSupportRadius or 5.0

            return {
                ver = PROTOCOL_VER,
                domainId = cfg.sectorId or "GAC_NODE",
                seq = next_seq(),
                type = "MSG_GAC_APPROACH_CLEARANCE",
                time = get_time_ms(),
                payload = {
                    sectorId = cfg.sectorId,
                    aircraftId = craftId,
                    status = "CLEARED",
                    assignedFacilityId = facilityId,
                    assignedTacticalChannel = payload.tacticalChannel,
                    touchdownPoint = coords,
                    safeDescentRate = 1.0,
                    clearanceZoneRadius = radius
                }
            }
        end
        return nil
    end

    function fsm:handle_facility_update(packet)
        local payload = packet and packet.payload or {}
        local facilityId = payload.facilityId
        local status = payload.status
        local craftId = payload.currentCraft
        local faultCode = payload.faultCode

        if facilityId then
            inv:update_status(facilityId, status, craftId, faultCode)
            if payload.touchdownPoint or payload.heading or payload.velocity then
                inv:update_dynamic_telemetry(facilityId, payload.touchdownPoint, payload.heading, payload.velocity)
            end
            if status == "OCCUPIED" or status == "FREE" then
                state.activeSlots[facilityId] = nil
            end
        end

        local summary = inv:get_summary()
        return {
            ver = PROTOCOL_VER,
            domainId = cfg.sectorId or "GAC_NODE",
            seq = next_seq(),
            type = "MSG_GAC_SECTOR_STATUS",
            time = get_time_ms(),
            payload = {
                sectorId = cfg.sectorId,
                totalPads = summary.totalLandingPads,
                freePads = summary.freeLandingPads,
                occupiedPads = summary.totalLandingPads - summary.freeLandingPads,
                maintenancePads = 0,
                sectorStatus = inv:is_emergency_lockdown() and "DECK_DANGEROUS" or "OPERATIONAL"
            }
        }
    end

    function fsm:handle_abort_approach(packet)
        local payload = packet and packet.payload or {}
        local facilityId = payload.facilityId
        local craftId = payload.aircraftId

        if facilityId then
            inv:update_status(facilityId, "GO_AROUND", craftId, payload.reason)
        end
        if craftId then
            local craftReq = state.pendingAircraft[craftId] or (state.activeSlots[facilityId] and state.activeSlots[facilityId].craftReq)
            state.goAroundQueue[craftId] = {
                aircraftId = craftId,
                failedFacilityId = facilityId,
                reason = payload.reason,
                craftReq = craftReq
            }
        end
        return nil
    end

    function fsm:handle_abort_clear(packet, surfaceWind)
        local payload = packet and packet.payload or {}
        local craftId = payload.aircraftId
        local failedPadId = payload.facilityId

        local info = state.goAroundQueue[craftId] or {}
        local craftReq = info.craftReq or state.pendingAircraft[craftId] or {
            aircraftId = craftId,
            craftWeight = 10000,
            craftRadius = 5,
            currentPos = { x = 0, y = payload.currentAltitude or 100, z = 0 }
        }

        -- Exclude the failed pad from candidate selection during diversion
        local allFacilities = inv:get_all_facilities()
        local divertCandidates = {}
        for _, fac in ipairs(allFacilities) do
            if fac.facilityId ~= failedPadId then
                table.insert(divertCandidates, fac)
            end
        end

        local newPad, err = alloc.select_best_pad(divertCandidates, craftReq, surfaceWind)
        
        -- Reset failed pad after diverting search
        if failedPadId then
            inv:update_status(failedPadId, "FREE", nil)
            state.activeSlots[failedPadId] = nil
        end

        if newPad then
            inv:update_status(newPad.facilityId, "RESERVED", craftId)
            local nowSec = os.clock and os.clock() or 0
            fsm:record_slot_assignment(newPad.facilityId, craftId, nowSec, cfg.slotDurationSec or 120, craftReq)
            state.goAroundQueue[craftId] = nil

            local slotAssign = {
                ver = PROTOCOL_VER,
                domainId = cfg.sectorId or "GAC_NODE",
                seq = next_seq(),
                type = "MSG_ATC_SLOT_ASSIGN",
                time = get_time_ms(),
                payload = {
                    facilityId = newPad.facilityId,
                    aircraftId = craftId,
                    airframeType = craftReq.airframeType or "UNKNOWN",
                    slotDurationSec = cfg.slotDurationSec or 120,
                    tacticalChannel = newPad.tacticalChannel
                }
            }
            return slotAssign, nil
        else
            -- Divert to Tower ATC
            local divertClearance = {
                ver = PROTOCOL_VER,
                domainId = cfg.sectorId or "GAC_NODE",
                seq = next_seq(),
                type = "MSG_GAC_APPROACH_CLEARANCE",
                time = get_time_ms(),
                payload = {
                    sectorId = cfg.sectorId,
                    aircraftId = craftId,
                    status = "DENIED",
                    reason = "NO_ALTERNATIVE_PAD",
                    divertChannel = cfg.towerAtcChannel or 50001
                }
            }
            return nil, divertClearance
        end
    end

    function fsm:handle_departure_req(packet)
        local payload = packet and packet.payload or {}
        local facilityId = payload.facilityId
        local craftId = payload.aircraftId

        return {
            ver = PROTOCOL_VER,
            domainId = cfg.sectorId or "GAC_NODE",
            seq = next_seq(),
            type = "MSG_GAC_DEPARTURE_CLEARANCE",
            time = get_time_ms(),
            payload = {
                sectorId = cfg.sectorId,
                facilityId = facilityId,
                aircraftId = craftId,
                status = "CLEARED",
                initialClimbAltitude = 100.0,
                towerAtcChannel = cfg.towerAtcChannel or 50001
            }
        }
    end

    function fsm:handle_departure_complete(packet)
        local payload = packet and packet.payload or {}
        local facilityId = payload.facilityId
        if facilityId then
            inv:update_status(facilityId, "FREE", nil)
            state.activeSlots[facilityId] = nil
        end
        return fsm:handle_facility_update({ payload = { facilityId = facilityId, status = "FREE" } })
    end

    function fsm:tick(nowSec)
        local now = nowSec or (os.clock and os.clock() or 0)
        local actions = {}

        for facilityId, slot in pairs(state.activeSlots) do
            if (now - slot.assignedAtSec) > slot.durationSec then
                inv:update_status(facilityId, "FREE", nil)
                table.insert(actions, {
                    type = "SLOT_TIMEOUT",
                    facilityId = facilityId,
                    aircraftId = slot.aircraftId
                })
                state.activeSlots[facilityId] = nil
            end
        end

        return actions
    end

    return fsm
end

return gac_fsm
