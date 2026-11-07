-- src/modules/facility_client.lua
local facility_client = {}

function facility_client.init(config)
    local cfg = config or {}
    local safe = cfg.safety or {}
    return {
        beacons = {},
        activePadId = nil,
        padMobility = "STATIC",
        padChannel = nil,
        atcStatus = "NONE",
        retryCount = 0,
        atcDeniedCount = 0,
        maxApproachRetries = safe.maxApproachRetries or 3,
        dynamicGuideTimeoutMs = safe.dynamicGuideTimeoutMs or 300,
        deniedHoldingClimbM = safe.deniedHoldingClimbM or 30.0,
        lastDynamicGuideMs = 0,
        touchdownAborted = false,
        holdingAlt = nil,
    }
end

function facility_client.update_beacons(state, beacon_payload, now_ms)
    if not state or not beacon_payload then return end
    local id = beacon_payload.facilityId or "UNKNOWN"
    beacon_payload._receivedMs = now_ms or 0
    state.beacons[id] = beacon_payload

    local expire_thresh = (now_ms or 0) - 5000
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

function facility_client.request_approach(state, pad_id, craft_cfg, fuel_pct, now_ms)
    if craft_cfg and craft_cfg.facilityType == "DOCKING_ARM" then
        return false, "DEFERRED_FACILITY_TYPE"
    end
    state.activePadId = pad_id
    state.atcStatus = "REQUESTED"
    return true, {
        type = "MSG_ATC_APPROACH_REQ",
        payload = {
            targetFacilityId = pad_id,
            facilityType = "LANDING_PAD",
            fuelPercent = fuel_pct or 1.0,
            timestamp = now_ms or 0,
        },
    }
end

function facility_client.on_atc_clearance(state, payload, craft_pos, now_ms)
    if not state or not payload then return end
    local status = payload.status or "DENIED"
    state.atcStatus = status
    if status == "CLEARED" then
        state.activePadId = payload.padId or state.activePadId
        state.padMobility = payload.padMobility or "STATIC"
        state.padChannel = payload.padChannel
        state.retryCount = 0
        state.atcDeniedCount = 0
    elseif status == "DENIED" then
        state.atcDeniedCount = state.atcDeniedCount + 1
        local py = craft_pos and craft_pos.y or 64.0
        state.holdingAlt = py + state.deniedHoldingClimbM
    end
end

function facility_client.extrapolate_dynamic_deck(guide, dt)
    local p = guide.position or { x = 0, y = 64, z = 0 }
    local v = guide.velocity or { x = 0, y = 0, z = 0 }
    local a = guide.acceleration or { x = 0, y = 0, z = 0 }
    local dt2 = 0.5 * dt * dt
    return {
        x = p.x + v.x * dt + a.x * dt2,
        y = p.y + v.y * dt + a.y * dt2,
        z = p.z + v.z * dt + a.z * dt2,
        vx = v.x + a.x * dt,
        vy = v.y + a.y * dt,
        vz = v.z + a.z * dt,
        pitch = guide.pitch or 0.0,
        roll = guide.roll or 0.0,
        heading = guide.heading or 0.0,
    }
end

function facility_client.evaluate_approach_safety(state, craft_pos, now_ms)
    if not state then return "SAFE" end
    if state.padMobility == "STATIC" then return "SAFE" end
    local elapsed = (now_ms or 0) - state.lastDynamicGuideMs
    local timed_out = elapsed > state.dynamicGuideTimeoutMs

    if timed_out then
        state.retryCount = state.retryCount + 1
        if state.retryCount > state.maxApproachRetries then
            state.touchdownAborted = true
            return "ABORT_DIVERT"
        end
        return "GO_AROUND"
    end
    return "SAFE"
end

function facility_client.build_touchdown_complete(state, pad_id)
    return {
        type = "MSG_TOUCHDOWN_COMPLETE",
        payload = {
            padId = pad_id or state.activePadId,
            touchdownTime = os.epoch and os.epoch("utc") or 0,
        },
    }
end

return facility_client
