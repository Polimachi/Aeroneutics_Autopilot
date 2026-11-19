-- src/3_planning/amm/modules/facility_client.lua
-- AMM 3-Tier Facility Client, ATC/GAC Coordination & Dynamic Deck Extrapolation

local facility_client = {}

function facility_client.init(config)
    local cfg = config or {}
    local sys = cfg.system or {}
    local safe = cfg.safety or {}
    local traj = cfg.trajectory or {}
    local dockCfg = traj.docking or {}
    return {
        domainId = sys.domainId or cfg.domainId or "AIRCRAFT_01",
        sectorId = cfg.sectorId or "SECTOR_01",
        airframeType = sys.airframeType or cfg.airframeType or "VECTORED_VTOL",
        reqSeq = 0,
        beacons = {},
        runways = {},
        activePadId = nil,
        gacChannel = nil,
        divertChannel = nil,
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
    local now = now_ms or 0

    if type(beacon_payload.facilities) == "table" then
        for _, fac in ipairs(beacon_payload.facilities) do
            if type(fac) == "table" and type(fac.facilityId) == "string" and fac.facilityId ~= "" then
                fac._receivedMs = now
                if fac.sectorId == nil then fac.sectorId = beacon_payload.sectorId end
                if fac.gacChannel == nil then fac.gacChannel = beacon_payload.gacChannel end
                state.beacons[fac.facilityId] = fac
            end
        end
    end

    if beacon_payload.facilityId or type(beacon_payload.facilities) ~= "table" then
        local id = beacon_payload.facilityId or "UNKNOWN"
        beacon_payload._receivedMs = now
        state.beacons[id] = beacon_payload
    end

    local expire_thresh = now - 5000
    for fid, b in pairs(state.beacons) do
        if b._receivedMs and b._receivedMs < expire_thresh then
            state.beacons[fid] = nil
        end
    end
end

function facility_client.find_nearest_free_landing_facility(state, craft_pos, type_filter, max_range_m)
    if not state or not craft_pos then return nil, 999999 end
    local filter = type_filter or "ANY"
    local best, best_dist = nil, 999999
    local cx, cz = craft_pos.x or 0, craft_pos.z or 0
    local has_range = (type(max_range_m) == "number" and max_range_m > 0)

    for _, b in pairs(state.beacons) do
        local is_landing = (filter == "ANY" and (b.facilityType == "LANDING_PAD" or b.facilityType == "RUNWAY"))
            or (b.facilityType == filter)
        if is_landing and b.status == "FREE" and b.dedicated ~= true and b.position then
            local dx = (b.position.x or 0) - cx
            local dz = (b.position.z or 0) - cz
            local dist = math.sqrt(dx * dx + dz * dz)
            if (not has_range or dist <= max_range_m) and dist < best_dist then
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

local function next_envelope(state, pktType, now_ms, payload)
    local seq = 1
    if state then
        state.reqSeq = (state.reqSeq or 0) + 1
        seq = state.reqSeq
    end
    local now = now_ms or (os and os.epoch and os.epoch("utc")) or (os and os.clock and math.floor(os.clock() * 1000)) or 0
    return {
        ver = "1.9.5",
        domainId = (state and state.domainId) or "AIRCRAFT_01",
        seq = seq,
        time = now,
        type = pktType,
        payload = payload,
    }
end

function facility_client.build_checkin_req(state, aircraftInfo, sectorId, now_ms)
    local info = aircraftInfo or {}
    local craftId = info.aircraftId or (state and state.domainId) or "AIRCRAFT_01"
    local secId = sectorId or info.sectorId or (state and state.sectorId) or "SECTOR_01"
    return next_envelope(state, "MSG_GAC_CHECKIN_REQ", now_ms, {
        sectorId = secId,
        aircraftId = craftId,
        grossWeight = info.grossWeight or 1000.0,
        clearanceRadius = info.clearanceRadius or 5.0,
        airframeType = info.airframeType or (state and state.airframeType) or "VECTORED_VTOL",
        preferredFacilityId = info.preferredFacilityId or (state and state.activePadId),
        isEmergency = (info.isEmergency == true),
    })
end

function facility_client.request_approach(state, pad_id, craft_cfg, fuel_pct, now_ms)
    local cfg = craft_cfg or {}
    local fType = cfg.facilityType or "LANDING_PAD"
    if fType ~= "LANDING_PAD" and fType ~= "RUNWAY" and fType ~= "DOCKING_ARM" then
        return false, "INVALID_FACILITY_TYPE"
    end
    if state then
        state.activePadId = pad_id
        state.atcStatus = "REQUESTED"
    end
    return true, next_envelope(state, "MSG_ATC_APPROACH_REQ", now_ms, {
        aircraftId = (state and state.domainId) or cfg.domainId or "AIRCRAFT_01",
        targetFacilityId = pad_id,
        facilityType = fType,
        fuelPercent = fuel_pct or 1.0,
        timestamp = now_ms or 0,
    })
end

local function reset_approach_retries(state)
    state.approachRetryCount = 0
    state.retryCount = 0
    state.atcDeniedCount = 0
    state.nextAtcRetryMs = 0
    state.holdingTargetAlt = nil
end

function facility_client.on_atc_clearance(state, clrPayload, currentPos, now_ms)
    if not state or not clrPayload then return end
    local p = clrPayload.payload or clrPayload
    local status = p.status or "DENIED"
    state.atcStatus = status
    local now = now_ms or 0
    if p.gacChannel then state.gacChannel = p.gacChannel end
    if p.sectorId then state.sectorId = p.sectorId end
    if p.divertChannel ~= nil then state.divertChannel = p.divertChannel end

    if status == "CLEARED" then
        state.activePadId = p.assignedFacilityId or p.targetFacilityId or state.activePadId
        state.padMobility = p.padMobility or state.padMobility or "STATIC"
        if clrPayload.type == "MSG_ATC_APPROACH_CLEARANCE" then
            state.padChannel = p.assignedGuidanceChannel or state.padChannel
        else
            state.padChannel = p.assignedTacticalChannel or state.padChannel
        end
        reset_approach_retries(state)
    elseif status == "DIVERT" then
        if type(p.divertChannel) == "number" and p.divertChannel > 0 then
            state.gacChannel = p.divertChannel
        end
        reset_approach_retries(state)
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

local function extract_common_guide(p, now)
    local pos = p.touchdownPoint or { x = 0.0, y = 64.0, z = 0.0 }
    local att = p.attitude or { pitch = 0.0, roll = 0.0, yaw = 0.0 }
    return {
        facilityId = p.facilityId,
        facilityType = p.facilityType or "LANDING_PAD",
        targetAircraft = p.targetAircraft,
        pos = { x = pos.x or 0.0, y = pos.y or 64.0, z = pos.z or 0.0 },
        attitude = { pitch = att.pitch or 0.0, roll = att.roll or 0.0, yaw = att.yaw or 0.0 },
        approachDirection = p.approachDirection,
        deckStatus = p.deckStatus or "STABLE",
        landingPermitted = (p.landingPermitted ~= false),
        abortAlert = (p.abortAlert == true),
        lastUpdateMs = now,
        approachHeading = att.yaw or 0.0,
        clearanceRadius = p.clearanceRadius,
        safeDescentRate = p.safeDescentRate,
        tiltAngleDeg = p.tiltAngleDeg,
        heaveRateMps = p.heaveRateMps,
        endPoint = p.endPoint,
        glideSlopeAngle = p.glideSlopeAngle,
        touchdownZoneLength = p.touchdownZoneLength,
        dockingCorridor = p.dockingCorridor,
        captureLatchReady = p.captureLatchReady,
        armState = p.armState,
    }
end

function facility_client.on_tactical_guide(state, pkt, now_ms)
    if not state or not pkt then return end
    local p = pkt.payload or pkt
    local msgType = pkt.type or p.type or ""
    local now = now_ms or 0

    if msgType == "MSG_FACILITY_DYNAMIC_GUIDE" then
        state.padMobility = "DYNAMIC"
        state.lastDynamicGuideMs = now
        local vel = p.velocity or { vx = 0.0, vy = 0.0, vz = 0.0 }
        local acc = p.acceleration or { ax = 0.0, ay = 0.0, az = 0.0 }
        local guide = extract_common_guide(p, now)
        guide.vel = { vx = vel.vx or 0.0, vy = vel.vy or 0.0, vz = vel.vz or 0.0 }
        guide.accel = { ax = acc.ax or 0.0, ay = acc.ay or 0.0, az = acc.az or 0.0 }
        guide.angularRates = p.angularRates
        state.dynamicGuide = guide
    elseif msgType == "MSG_FACILITY_STATIC_GUIDE" then
        state.padMobility = "STATIC"
        state.staticGuide = extract_common_guide(p, now)
        state.lastStaticGuideMs = now
    end
    if p.abortAlert == true or msgType == "MSG_ABORT_APPROACH" or p.deckStatus == "DANGEROUS" or p.landingPermitted == false then
        state.touchdownAborted = true
    end
end

function facility_client.on_gac_abort_clear(state, pkt, now_ms)
    if not state or not pkt then return end
    local p = pkt.payload or pkt
    state.touchdownAborted = false
    state.dockingAborted = false
    state.approachRetryCount = 0
    state.retryCount = 0
    if p.reassignedFacilityId or p.assignedFacilityId then
        state.activePadId = p.reassignedFacilityId or p.assignedFacilityId
    end
    if p.assignedTacticalChannel then
        state.padChannel = p.assignedTacticalChannel
    end
    state.lastAtcDeniedMs = now_ms or state.lastAtcDeniedMs
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
        if (state.atcDeniedCount or 0) >= (state.maxAtcDeniedRetries or 10) then
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

local function resolve_builder_opts(state, arg, opts, now_ms)
    local o = type(arg) == "table" and arg or (type(opts) == "table" and opts or {})
    local scalar = (type(arg) ~= "table") and arg or nil
    local facilityId = o.facilityId or (state and state.activePadId)
    local t = now_ms or o.nowMs or o.now_ms or o.time
    return o, scalar, facilityId, t
end

function facility_client.build_touchdown_complete(state, craftState, now_ms)
    local o, scalar, facilityId, t = resolve_builder_opts(state, craftState, nil, now_ms)
    local cState = o.craftState or ((type(scalar) == "string" and scalar ~= "") and scalar) or "GROUND_IDLE"
    local env = next_envelope(state, "MSG_TOUCHDOWN_COMPLETE", t, {
        facilityId = facilityId,
        craftState = cState,
    })
    env.payload.touchdownTime = o.touchdownTime or env.time
    return env
end

function facility_client.build_runway_touchdown(state, touchdownSpeed, opts)
    local o, scalar, facilityId, t = resolve_builder_opts(state, touchdownSpeed, opts)
    local rawSpeed = scalar ~= nil and scalar or o.touchdownSpeed
    local speed = (type(rawSpeed) == "number") and rawSpeed or (tonumber(rawSpeed) or 0.0)
    local payload = {
        facilityId = facilityId,
        touchdownSpeed = speed,
    }
    if o.arrestedWire ~= nil then payload.arrestedWire = o.arrestedWire end
    if o.craftState ~= nil then payload.craftState = o.craftState end
    return next_envelope(state, "MSG_RUNWAY_TOUCHDOWN", t, payload)
end

function facility_client.build_runway_vacated(state, exitTaxiway, opts)
    local o, scalar, facilityId, t = resolve_builder_opts(state, exitTaxiway, opts)
    local taxiway = scalar ~= nil and scalar or o.exitTaxiway
    local payload = {
        facilityId = facilityId,
        runwayCleared = (o.runwayCleared ~= false),
    }
    if type(taxiway) == "string" and taxiway ~= "" then
        payload.exitTaxiway = taxiway
    end
    return next_envelope(state, "MSG_RUNWAY_VACATED", t, payload)
end

return facility_client
