-- src/3_planning/amm/modules/facility_client.lua
-- AMM 3-Tier Facility Client, ATC/GAC Coordination & Dynamic Deck Extrapolation

local facility_client = {}

function facility_client.init(config)
    local cfg = config or {}
    local safe = cfg.safety or {}
    local traj = cfg.trajectory or {}
    local dockCfg = traj.docking or {}
    return {
        beacons = {},
        runways = {},
        activePadId = nil,
        padMobility = "STATIC",
        padChannel = nil,
        atcStatus = "NONE",
        retryCount = 0,
        approachRetryCount = 0,
        atcDeniedCount = 0,
        maxApproachRetries = safe.maxApproachRetries or 3,
        dynamicGuideTimeoutMs = safe.dynamicGuideTimeoutMs or 300,
        atcDeniedRetryIntervalSec = safe.atcDeniedRetryIntervalSec or 15,
        maxAtcDeniedRetries = safe.maxAtcDeniedRetries or 10,
        deniedHoldingClimbM = safe.deniedHoldingClimbM or 30.0,
        goAroundTargetAltM = safe.goAroundTargetAltM or 100.0,
        lastDynamicGuideMs = 0,
        lastStaticGuideMs = 0,
        lastAtcDeniedMs = 0,
        nextAtcRetryMs = 0,
        touchdownAborted = false,
        holdingTargetAlt = nil,
        dynamicGuide = nil,
        staticGuide = nil,
        dockingStage = "NONE",
        dockingStatus = nil,
        dockingAborted = false,
        abortTrajectoryBias = dockCfg.abortSurgeBias or -0.8,
        isHardLocked = false,
        flightActive = true,
        flightMode = "CRUISE",
    }
end

function facility_client.update_beacons(state, beacon_payload, now_ms)
    if not state or not beacon_payload then return end
    local id = beacon_payload.facilityId or "UNKNOWN"
    local now = now_ms or 0
    beacon_payload._receivedMs = now
    state.beacons[id] = beacon_payload

    local expire_thresh = now - 5000
    for fid, b in pairs(state.beacons) do
        if b._receivedMs and b._receivedMs < expire_thresh then
            state.beacons[fid] = nil
        end
    end
end

function facility_client.find_nearest_free_landing_facility(state, craft_pos)
    if not state or not craft_pos then return nil, 999999 end
    local best, best_dist = nil, 999999
    local cx, cz = craft_pos.x or 0, craft_pos.z or 0

    for _, b in pairs(state.beacons) do
        local is_landing = (b.facilityType == "LANDING_PAD" or b.facilityType == "RUNWAY")
        if is_landing and b.status == "FREE" and b.position then
            local dx = b.position.x - cx
            local dz = b.position.z - cz
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist < best_dist then
                best_dist = dist
                best = b
            end
        end
    end
    return best, best_dist
end

function facility_client.find_nearest_free_facility(state, craft_pos)
    return facility_client.find_nearest_free_landing_facility(state, craft_pos)
end

function facility_client.build_checkin_req(state, aircraftInfo, sectorId)
    local info = aircraftInfo or {}
    local craftId = info.aircraftId or (state and state.domainId) or "AIRCRAFT_01"
    local secId = sectorId or info.sectorId or (state and state.sectorId) or "SECTOR_01"
    return {
        ver = "1.9.5",
        type = "MSG_GAC_CHECKIN_REQ",
        payload = {
            sectorId = secId,
            aircraftId = craftId,
            craftWeight = info.craftWeight or 1000.0,
            craftRadius = info.craftRadius or 5.0,
            airframeType = info.airframeType or "VECTORED_VTOL",
            preferredFacilityId = info.preferredFacilityId or (state and state.activePadId),
            isEmergency = (info.isEmergency == true),
        }
    }
end

function facility_client.request_approach(state, pad_id, craft_cfg, fuel_pct, now_ms)
    if craft_cfg and craft_cfg.facilityType == "DOCKING_ARM" then
        return false, "DEFERRED_FACILITY_TYPE"
    end
    if state then
        state.activePadId = pad_id
        state.atcStatus = "REQUESTED"
    end
    return true, {
        ver = "1.9.5",
        type = "MSG_ATC_APPROACH_REQ",
        payload = {
            targetFacilityId = pad_id,
            facilityType = "LANDING_PAD",
            fuelPercent = fuel_pct or 1.0,
            timestamp = now_ms or 0,
        },
    }
end

function facility_client.on_atc_clearance(state, clrPayload, currentPos, now_ms)
    if not state or not clrPayload then return end
    local p = clrPayload.payload or clrPayload
    local status = p.status or "DENIED"
    state.atcStatus = status
    local now = now_ms or 0

    if status == "CLEARED" then
        state.activePadId = p.assignedFacilityId or state.activePadId
        state.padMobility = p.padMobility or "STATIC"
        state.padChannel = p.assignedTacticalChannel
        state.approachRetryCount = 0
        state.retryCount = 0
        state.atcDeniedCount = 0
        state.nextAtcRetryMs = 0
        state.holdingTargetAlt = nil
    elseif status == "DENIED" or status == "HOLD" then
        state.atcDeniedCount = (state.atcDeniedCount or 0) + 1
        state.lastAtcDeniedMs = now
        local intervalMs = (state.atcDeniedRetryIntervalSec or 15) * 1000
        state.nextAtcRetryMs = now + intervalMs
        local py = currentPos and currentPos.y or 64.0
        local climb = state.deniedHoldingClimbM or 30.0
        state.holdingTargetAlt = py + climb
    end
end

function facility_client.on_tactical_guide(state, pkt, now_ms)
    if not state or not pkt then return end
    local p = pkt.payload or pkt
    local msgType = pkt.type or p.type or ""
    local now = now_ms or 0

    if msgType == "MSG_FACILITY_DYNAMIC_GUIDE" then
        state.padMobility = "DYNAMIC"
        state.lastDynamicGuideMs = now
        local pos = p.touchdownPoint or { x = 0.0, y = 64.0, z = 0.0 }
        local vel = p.velocity or { vx = 0.0, vy = 0.0, vz = 0.0 }
        local acc = p.acceleration or { ax = 0.0, ay = 0.0, az = 0.0 }
        local att = p.attitude or { pitch = 0.0, roll = 0.0, yaw = 0.0 }
        state.dynamicGuide = {
            pos = { x = pos.x or 0.0, y = pos.y or 64.0, z = pos.z or 0.0 },
            vel = { vx = vel.vx or 0.0, vy = vel.vy or 0.0, vz = vel.vz or 0.0 },
            accel = { ax = acc.ax or 0.0, ay = acc.ay or 0.0, az = acc.az or 0.0 },
            attitude = { pitch = att.pitch or 0.0, roll = att.roll or 0.0, yaw = att.yaw or 0.0 },
            lastUpdateMs = now,
            approachHeading = att.yaw or 0.0,
            deckStatus = p.deckStatus or "STABLE",
            abortAlert = (p.abortAlert == true),
            landingPermitted = (p.landingPermitted ~= false),
        }
    elseif msgType == "MSG_FACILITY_STATIC_GUIDE" then
        state.padMobility = "STATIC"
        state.staticGuide = p
        state.lastStaticGuideMs = now
    end
    if p.abortAlert == true or msgType == "MSG_ABORT_APPROACH" then
        state.touchdownAborted = true
    end
end

function facility_client.extrapolate_dynamic_deck(state, now_ms)
    local g = (state and state.dynamicGuide) or state or {}
    local lastMs = g.lastUpdateMs or now_ms or 0
    local dt = 0.0
    if type(now_ms) == "number" then
        dt = math.max(0.0, math.min(0.5, (now_ms - lastMs) / 1000.0))
    end

    local p0 = g.pos or { x = 0.0, y = 64.0, z = 0.0 }
    local v0 = g.vel or { vx = 0.0, vy = 0.0, vz = 0.0 }
    local a0 = g.accel or { ax = 0.0, ay = 0.0, az = 0.0 }
    local att = g.attitude or {}
    local vx = v0.vx or 0.0
    local vy = v0.vy or 0.0
    local vz = v0.vz or 0.0
    local ax = a0.ax or 0.0
    local ay = a0.ay or 0.0
    local az = a0.az or 0.0
    local dt2 = 0.5 * dt * dt

    local pos = {
        x = (p0.x or 0.0) + vx * dt + ax * dt2,
        y = (p0.y or 64.0) + vy * dt + ay * dt2,
        z = (p0.z or 0.0) + vz * dt + az * dt2,
        vx = vx + ax * dt,
        vy = vy + ay * dt,
        vz = vz + az * dt,
        pitch = att.pitch or 0.0,
        roll = att.roll or 0.0,
        heading = g.approachHeading or 0.0,
    }
    local vel = {
        vx = vx + ax * dt,
        vy = vy + ay * dt,
        vz = vz + az * dt,
    }
    return pos, vel
end

function facility_client.evaluate_guide_watchdog(state, now_ms)
    local res = {
        triggerGoAround = false,
        retriesExhausted = false,
        holdAltClimbM = 0.0,
        shouldRetryAtc = false,
        activeTarget = state and state.activePadId,
        targetAlt = nil,
        action = nil,
    }
    if not state then return res end
    local now = now_ms or 0

    if state.atcStatus == "DENIED" or state.atcStatus == "HOLD" then
        if state.atcDeniedCount > state.maxAtcDeniedRetries then
            res.retriesExhausted = true
            res.action = "RTH"
            return res
        end
        if now >= (state.nextAtcRetryMs or 0) then
            res.shouldRetryAtc = true
            res.holdAltClimbM = state.deniedHoldingClimbM or 30.0
            res.targetAlt = state.holdingTargetAlt
        end
    end

    local isDyn = (state.padMobility == "DYNAMIC")
    local isLanding = (state.flightMode == "APPROACH_LAND" or state.flightMode == "LANDING" or state.flightMode == "DOCKING" or state.activePadId ~= nil)
    if isDyn and isLanding then
        local elapsed = now - (state.lastDynamicGuideMs or 0)
        local timedOut = elapsed > (state.dynamicGuideTimeoutMs or 300)
        if timedOut or state.touchdownAborted then
            local nextRetry = (state.approachRetryCount or 0) + 1
            if nextRetry <= (state.maxApproachRetries or 3) then
                state.approachRetryCount = nextRetry
                state.retryCount = nextRetry
                state.lastDynamicGuideMs = now
                res.triggerGoAround = true
                res.targetAlt = state.goAroundTargetAltM or 100.0
                res.action = "GO_AROUND"
            else
                res.retriesExhausted = true
                state.touchdownAborted = true
                res.action = "FAILSAFE_RTH"
            end
        end
    end
    return res
end

function facility_client.evaluate_approach_safety(state, craft_pos, now_ms)
    if not state then return "SAFE" end
    if state.padMobility == "STATIC" then return "SAFE" end
    local elapsed = (now_ms or 0) - (state.lastDynamicGuideMs or 0)
    local timed_out = elapsed > (state.dynamicGuideTimeoutMs or 300)

    if timed_out then
        state.approachRetryCount = (state.approachRetryCount or 0) + 1
        state.retryCount = state.approachRetryCount
        if state.approachRetryCount > (state.maxApproachRetries or 3) then
            state.touchdownAborted = true
            return "ABORT_DIVERT"
        end
        return "GO_AROUND"
    end
    return "SAFE"
end

function facility_client.on_docking_status(state, payload, now_ms)
    if not state or not payload then return end
    local p = payload.payload or payload
    local stage = p.stage or "UNKNOWN"
    state.dockingStage = stage
    state.dockingStatus = p
    state.lastDockingStatusMs = now_ms or 0

    if stage == "HARD_LOCKED" then
        state.isHardLocked = true
        state.flightActive = false
        state.dockingAborted = false
    elseif stage == "ABORTED" then
        state.dockingAborted = true
        state.touchdownAborted = true
        state.abortTrajectoryBias = -0.8
    end
    return stage, state.isHardLocked, state.dockingAborted
end

function facility_client.build_touchdown_complete(state, craftState)
    local targetId = state and state.activePadId
    local cState = "GROUND_IDLE"
    if type(craftState) == "table" then
        cState = craftState.craftState or "GROUND_IDLE"
        targetId = craftState.facilityId or targetId
    elseif type(craftState) == "string" and craftState ~= "" then
        cState = craftState
    end
    local nowTime = (os.epoch and os.epoch("utc")) or (os.clock and math.floor(os.clock() * 1000)) or 0
    return {
        ver = "1.9.5",
        type = "MSG_TOUCHDOWN_COMPLETE",
        payload = {
            facilityId = targetId,
            touchdownTime = nowTime,
            craftState = cState,
        }
    }
end

return facility_client
