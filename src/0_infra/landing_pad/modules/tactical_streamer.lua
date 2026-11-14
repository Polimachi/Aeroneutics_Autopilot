-- src/0_infra/landing_pad/modules/tactical_streamer.lua
-- Tactical guidance packet streamer and local backbone protocol encoder for Landing Pad

local tactical_streamer = {}

local WIRE_VERSION = "1.9.5"

function tactical_streamer.create(config)
    if not config then error("config table required", 2) end

    local streamer = {}

    local function build_envelope(msgType, seq, payload, nowMs)
        return {
            ver = WIRE_VERSION,
            domainId = config.padId or "PAD",
            seq = seq or 0,
            type = msgType,
            time = nowMs or (os.epoch and os.epoch("utc") or 0),
            payload = payload or {}
        }
    end

    function streamer:build_static_guide(seq, targetAircraft, touchdownPoint, surfaceWind, abortAlert, nowMs)
        local isAbort = (abortAlert == true)
        local payload = {
            facilityId = config.padId,
            facilityType = "LANDING_PAD",
            targetAircraft = targetAircraft,
            touchdownPoint = {
                x = touchdownPoint and touchdownPoint.x or 0.0,
                y = touchdownPoint and touchdownPoint.y or 64.0,
                z = touchdownPoint and touchdownPoint.z or 0.0
            },
            attitude = {
                pitch = 0.0,
                roll = 0.0,
                yaw = config.approachHeading or 0.0
            },
            approachDirection = "DOWNWARD",
            deckStatus = "STABLE",
            landingPermitted = not isAbort,
            abortAlert = isAbort,
            clearanceRadius = config.clearanceRadius or 5.0,
            safeDescentRate = config.safeDescentRate or 1.0,
            tiltAngleDeg = 0.0,
            heaveRateMps = 0.0
        }
        return build_envelope("MSG_FACILITY_STATIC_GUIDE", seq, payload, nowMs)
    end

    function streamer:build_dynamic_guide(seq, targetAircraft, touchdownPoint, kinematics, deckStatus, landingPermitted, tiltAngleDeg, heaveRateMps, abortAlert, nowMs)
        local kin = kinematics or {}
        local vel = kin.velocity or {}
        local acc = kin.acceleration or {}
        local att = kin.attitude or {}
        local rates = kin.angularRates or {}

        local payload = {
            facilityId = config.padId,
            facilityType = "LANDING_PAD",
            targetAircraft = targetAircraft,
            touchdownPoint = {
                x = touchdownPoint and touchdownPoint.x or 0.0,
                y = touchdownPoint and touchdownPoint.y or 64.0,
                z = touchdownPoint and touchdownPoint.z or 0.0
            },
            attitude = {
                pitch = att.pitch or 0.0,
                roll = att.roll or 0.0,
                yaw = att.yaw or 0.0
            },
            approachDirection = "DOWNWARD",
            deckStatus = deckStatus or "STABLE",
            landingPermitted = (landingPermitted == true),
            abortAlert = (abortAlert == true),
            velocity = {
                vx = vel.vx or 0.0,
                vy = vel.vy or 0.0,
                vz = vel.vz or 0.0
            },
            acceleration = {
                ax = acc.ax or 0.0,
                ay = acc.ay or 0.0,
                az = acc.az or 0.0
            },
            angularRates = {
                pitchRate = rates.pitchRate or 0.0,
                rollRate = rates.rollRate or 0.0,
                yawRate = rates.yawRate or 0.0
            },
            clearanceRadius = config.clearanceRadius or 5.0,
            safeDescentRate = config.safeDescentRate or 1.0,
            tiltAngleDeg = tiltAngleDeg or 0.0,
            heaveRateMps = heaveRateMps or 0.0
        }
        return build_envelope("MSG_FACILITY_DYNAMIC_GUIDE", seq, payload, nowMs)
    end

    function streamer:build_abort_approach(seq, targetAircraft, reason, climbAlt, nowMs)
        local payload = {
            facilityId = config.padId,
            aircraftId = targetAircraft,
            reason = reason or "DECK_UNSTABLE",
            recommendedClimbAltitude = climbAlt or 100.0
        }
        return build_envelope("MSG_ABORT_APPROACH", seq, payload, nowMs)
    end

    function streamer:build_slot_ack(seq, targetAircraft, status, rejectReason, nowMs)
        local payload = {
            facilityId = config.padId,
            aircraftId = targetAircraft,
            status = status or "ACCEPTED",
            rejectReason = rejectReason,
            tacticalChannel = config.channels and config.channels.tacticalChannel or 0
        }
        return build_envelope("MSG_ATC_SLOT_ACK", seq, payload, nowMs)
    end

    local FACILITY_STATUS_MAP = {
        IDLE = "FREE",
        FREE = "FREE",
        RESERVED = "RESERVED",
        APPROACH_STATIC = "RESERVED",
        APPROACH_DYNAMIC = "RESERVED",
        OCCUPIED = "OCCUPIED",
        DEPARTURE_PENDING = "OCCUPIED",
        GO_AROUND = "MAINTENANCE",
        MAINTENANCE = "MAINTENANCE"
    }

    function streamer:build_facility_update(seq, status, currentCraft, faultCode, dynPos, heading, vel, nowMs)
        local payload = {
            facilityId = config.padId,
            status = FACILITY_STATUS_MAP[status] or "FREE",
            currentCraft = currentCraft,
            faultCode = faultCode
        }

        if dynPos then
            payload.touchdownPoint = {
                x = dynPos.x or 0.0,
                y = dynPos.y or 64.0,
                z = dynPos.z or 0.0
            }
        end

        if heading ~= nil then
            payload.heading = heading
        end

        if vel then
            payload.velocity = {
                vx = vel.vx or 0.0,
                vy = vel.vy or 0.0,
                vz = vel.vz or 0.0
            }
        end

        return build_envelope("MSG_ATC_FACILITY_UPDATE", seq, payload, nowMs)
    end

    return streamer
end

return tactical_streamer
