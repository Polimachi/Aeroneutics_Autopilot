-- src/0_infra/runway/modules/tactical_streamer.lua
-- Tactical ILS guide packet streamer and GAC backbone encoder for Runway

local tactical_streamer = {}

local WIRE_VERSION = "1.9.5"

local FACILITY_STATUS_MAP = {
    IDLE = "FREE",
    FREE = "FREE",
    RESERVED = "RESERVED",
    APPROACH_STATIC = "RESERVED",
    APPROACH_DYNAMIC = "RESERVED",
    ROLLOUT = "OCCUPIED",
    VACATING = "OCCUPIED",
    OCCUPIED = "OCCUPIED",
    LINE_UP_WAIT = "OCCUPIED",
    TAKEOFF_ROLL = "OCCUPIED",
    WAVE_OFF = "MAINTENANCE",
    MAINTENANCE = "MAINTENANCE",
}

local function copy_xyz(pt, defaultY)
    return {
        x = pt and pt.x or 0.0,
        y = pt and pt.y or (defaultY or 64.0),
        z = pt and pt.z or 0.0,
    }
end

function tactical_streamer.create(config)
    if not config then error("config table required", 2) end
    local streamer = {}

    local function build_envelope(msgType, seq, payload, nowMs)
        return {
            ver = WIRE_VERSION,
            domainId = config.facilityId or "RWY",
            seq = seq or 0,
            type = msgType,
            time = nowMs or (os.epoch and os.epoch("utc") or 0),
            payload = payload or {},
        }
    end

    function streamer:build_static_guide(seq, targetAircraft, touchdownPoint, endPoint, abortAlert, nowMs)
        local isAbort = (abortAlert == true)
        return build_envelope("MSG_FACILITY_STATIC_GUIDE", seq, {
            facilityId = config.facilityId,
            facilityType = "RUNWAY",
            targetAircraft = targetAircraft,
            touchdownPoint = copy_xyz(touchdownPoint, 64.0),
            attitude = { pitch = 0.0, roll = 0.0, yaw = config.approachHeading or 0.0 },
            approachDirection = config.approachDirection or "FRONT",
            deckStatus = "STABLE",
            landingPermitted = not isAbort,
            abortAlert = isAbort,
            endPoint = copy_xyz(endPoint, 64.0),
            glideSlopeAngle = config.glideSlopeAngle or 3.0,
            touchdownZoneLength = config.touchdownZoneLength or 80.0,
        }, nowMs)
    end

    function streamer:build_dynamic_guide(seq, targetAircraft, touchdownPoint, endPoint, kinematics, deckStatus, landingPermitted, abortAlert, nowMs)
        local kin = kinematics or {}
        local vel, acc, att, rates = kin.velocity or {}, kin.acceleration or {}, kin.attitude or {}, kin.angularRates or {}
        return build_envelope("MSG_FACILITY_DYNAMIC_GUIDE", seq, {
            facilityId = config.facilityId,
            facilityType = "RUNWAY",
            targetAircraft = targetAircraft,
            touchdownPoint = copy_xyz(touchdownPoint, 64.0),
            attitude = { pitch = att.pitch or 0.0, roll = att.roll or 0.0, yaw = att.yaw or 0.0 },
            approachDirection = config.approachDirection or "FRONT",
            deckStatus = deckStatus or "STABLE",
            landingPermitted = (landingPermitted == true),
            abortAlert = (abortAlert == true),
            velocity = { vx = vel.vx or 0.0, vy = vel.vy or 0.0, vz = vel.vz or 0.0 },
            acceleration = { ax = acc.ax or 0.0, ay = acc.ay or 0.0, az = acc.az or 0.0 },
            angularRates = { pitchRate = rates.pitchRate or 0.0, rollRate = rates.rollRate or 0.0, yawRate = rates.yawRate or 0.0 },
            endPoint = copy_xyz(endPoint, 64.0),
            glideSlopeAngle = config.glideSlopeAngle or 3.0,
            touchdownZoneLength = config.touchdownZoneLength or 80.0,
        }, nowMs)
    end

    function streamer:build_abort_approach(seq, targetAircraft, reason, climbAlt, nowMs)
        return build_envelope("MSG_ABORT_APPROACH", seq, {
            facilityId = config.facilityId,
            aircraftId = targetAircraft,
            reason = reason or "DECK_UNSTABLE",
            recommendedClimbAltitude = climbAlt or 100.0,
        }, nowMs)
    end

    function streamer:build_slot_ack(seq, targetAircraft, status, rejectReason, nowMs)
        return build_envelope("MSG_ATC_SLOT_ACK", seq, {
            facilityId = config.facilityId,
            aircraftId = targetAircraft,
            status = status or "ACCEPTED",
            rejectReason = rejectReason,
            tacticalChannel = config.channels and config.channels.tacticalChannel or 0,
        }, nowMs)
    end

    function streamer:build_facility_update(seq, status, currentCraft, faultCode, dynPos, heading, vel, nowMs)
        local payload = {
            facilityId = config.facilityId,
            status = FACILITY_STATUS_MAP[status] or "FREE",
            currentCraft = currentCraft,
            faultCode = faultCode,
        }
        if dynPos then payload.touchdownPoint = copy_xyz(dynPos, 64.0) end
        if heading ~= nil then payload.heading = heading end
        if vel then payload.velocity = { vx = vel.vx or 0.0, vy = vel.vy or 0.0, vz = vel.vz or 0.0 } end
        return build_envelope("MSG_ATC_FACILITY_UPDATE", seq, payload, nowMs)
    end

    return streamer
end

return tactical_streamer
