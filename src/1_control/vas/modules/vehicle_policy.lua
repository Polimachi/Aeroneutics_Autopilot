-- VAS Layer 2: Vehicle-Specific Control Policy Factory (VICD-Spec v1.1.0)
local quat = require("quat")

local vehicle_policy = {}

function vehicle_policy.init(policyConfig)
    local cfg = policyConfig or {}
    local env = cfg.envelope or {}
    local trim = cfg.trim or {}
    local stall = cfg.stallGuard or {}

    return {
        vehicleType = cfg.vehicleType or "WINGED_VTOL",
        maxTiltDeg = env.maxTiltDeg or 35.0,
        stallSpeed = stall.stallSpeed or 10.0,
        minStallThrottle = stall.minThrottle or 1.0,
        stallNoseDownPitchDeg = stall.stallNoseDownPitchDeg or -5.0,
        vFe = cfg.vFe or 22.0,
        antiTorqueCoeff = trim.antiTorqueCoeff or 0.0,
        pitchTrim = trim.pitchTrim or 0.0,
        transitionAlpha = 0.0
    }
end

function vehicle_policy.is_aerodynamic(policyOrType)
    local vType = (type(policyOrType) == "table" and policyOrType.vehicleType) or policyOrType
    return vType == "FIXED_WING" or vType == "WINGED_VTOL"
end

function vehicle_policy.resolve_guidance_targets(cmd)
    local targetQ = cmd.targetOrientation
    if type(targetQ) == "table" then
        if targetQ.w ~= nil then
            return quat.normalize(targetQ)
        elseif targetQ.pitch ~= nil or targetQ.roll ~= nil or targetQ.heading ~= nil or targetQ.yaw ~= nil then
            local p = tonumber(targetQ.pitch) or 0.0
            local r = tonumber(targetQ.roll) or 0.0
            local y = tonumber(targetQ.heading or targetQ.yaw) or 0.0
            return quat.from_euler(p, r, y)
        end
    end
    if cmd.angleTargets then
        local p = tonumber(cmd.angleTargets.targetPitch) or 0.0
        local r = tonumber(cmd.angleTargets.targetRoll) or 0.0
        local y = tonumber(cmd.angleTargets.targetHeading) or 0.0
        return quat.from_euler(p, r, y)
    end
    return quat.identity()
end

function vehicle_policy.compute_transition_weights(policy, airspeed)
    local vType = policy.vehicleType
    if vType == "FIXED_WING" then return 1.0 end
    if vType == "QUADROTOR" or vType == "HEXAROTOR" or vType == "VTOL" or vType == "VECTORED_VTOL" or vType == "ADVANCED_VTOL" then return 0.0 end
    local v = tonumber(airspeed) or 0.0
    if v < 8.0 then return 0.0
    elseif v > 18.0 then return 1.0
    else return (v - 8.0) / 10.0 end
end

function vehicle_policy.resolve_flap_target(policy, rawCmd, airspeed, health)
    local isAero = vehicle_policy.is_aerodynamic(policy)
    if not isAero then
        return 0.0
    end
    local flap = tonumber(rawCmd and rawCmd.flapTarget) or 0.0
    local v = tonumber(airspeed) or 0.0
    local isVValid = (health and health.velocity ~= false) and (health and health.isVelocityValid ~= false)
    if isVValid and v > (policy.vFe or 22.0) then
        return 0.0
    end
    return math.max(0.0, math.min(1.0, flap))
end

function vehicle_policy.apply_stall_guard(policy, telem, conditionedCmd)
    local health = telem.sensorHealth or {}
    local airspeed = telem.airspeed or 0.0
    local isVValid = (health.velocity ~= false) and (health.isVelocityValid ~= false) and (health.isAirspeedValid ~= false)
    local isAero = vehicle_policy.is_aerodynamic(policy)
    if isVValid and isAero and airspeed < policy.stallSpeed then
        conditionedCmd.targetThrottle = math.max(conditionedCmd.targetThrottle or 0.0, policy.minStallThrottle)
        local eul = quat.to_euler(conditionedCmd.targetOrientation)
        local noseDown = policy.stallNoseDownPitchDeg or -5.0
        if eul.pitch > noseDown then
            conditionedCmd.targetOrientation = quat.from_euler(noseDown, eul.roll, eul.yaw)
        end
    end
end

function vehicle_policy.clamp_tilt_limits(policy, targetQ, isDerated)
    local eul = quat.to_euler(targetQ)
    local maxT = isDerated and math.min(20.0, policy.maxTiltDeg) or policy.maxTiltDeg
    local clampedP = math.max(-maxT, math.min(maxT, eul.pitch))
    local clampedR = math.max(-maxT, math.min(maxT, eul.roll))
    if clampedP ~= eul.pitch or clampedR ~= eul.roll then
        return quat.from_euler(clampedP, clampedR, eul.yaw)
    end
    return targetQ
end

function vehicle_policy.combine_saturation(satTap, satAsa, alpha)
    local a = math.max(0.0, math.min(1.0, tonumber(alpha) or 0.0))
    local tapPos = (satTap and satTap.axisSaturatedPos) or {}
    local tapNeg = (satTap and satTap.axisSaturatedNeg) or {}
    local asaPos = (satAsa and satAsa.axisSaturatedPos) or {}
    local asaNeg = (satAsa and satAsa.axisSaturatedNeg) or {}

    local function merge_axis(tapVal, asaVal)
        if a <= 0.0 then return tapVal == true
        elseif a >= 1.0 then return asaVal == true
        else return (tapVal == true) and (asaVal == true) end
    end

    return {
        axisSaturatedPos = {
            surge = tapPos.surge == true,
            sway = tapPos.sway == true,
            pitch = merge_axis(tapPos.pitch, asaPos.pitch),
            roll = merge_axis(tapPos.roll, asaPos.roll),
            yaw = merge_axis(tapPos.yaw, asaPos.yaw),
            heave = tapPos.heave == true
        },
        axisSaturatedNeg = {
            surge = tapNeg.surge == true,
            sway = tapNeg.sway == true,
            pitch = merge_axis(tapNeg.pitch, asaNeg.pitch),
            roll = merge_axis(tapNeg.roll, asaNeg.roll),
            yaw = merge_axis(tapNeg.yaw, asaNeg.yaw),
            heave = tapNeg.heave == true
        }
    }
end

function vehicle_policy.pre_process_guidance(policy, telem, rawCmd, fsmState)
    local health = telem.sensorHealth or {}
    local airspeed = telem.airspeed or (telem.dynamics and telem.dynamics.velocity and math.sqrt(telem.dynamics.velocity.vx^2 + telem.dynamics.velocity.vz^2)) or 0.0
    local conditioned = {
        targetOrientation = vehicle_policy.resolve_guidance_targets(rawCmd),
        targetClimbRate = tonumber(rawCmd.targetClimbRate) or 0.0,
        targetThrottle = tonumber(rawCmd.targetThrottle) or 0.0,
        flapTarget = vehicle_policy.resolve_flap_target(policy, rawCmd, airspeed, health),
        transitionAlpha = vehicle_policy.compute_transition_weights(policy, airspeed),
        translationBias = rawCmd.translationBias or { surge = 0, sway = 0, heave = 0 }
    }

    if fsmState == "FAILSAFE_HOLD" or fsmState == "EMERGENCY_LAND" then
        conditioned.targetOrientation = quat.identity()
        conditioned.translationBias = { surge = 0, sway = 0, heave = 0 }
        conditioned.targetClimbRate = (fsmState == "EMERGENCY_LAND") and -1.5 or 0.0
        return conditioned
    end

    local isDerated = (rawCmd and rawCmd.isStaticFallback == true)
        or (telem and telem.isCalibrated == false)
        or (policy and policy.isDerated == true)

    if health.isAttitudeValid == false then
        conditioned.targetOrientation = quat.identity()
    else
        conditioned.targetOrientation = vehicle_policy.clamp_tilt_limits(policy, conditioned.targetOrientation, isDerated)
    end

    if health.isVelocityValid == false then
        conditioned.translationBias = { surge = 0, sway = 0, heave = 0 }
    end

    vehicle_policy.apply_stall_guard(policy, telem, conditioned)
    return conditioned
end

function vehicle_policy.post_process_wrench(policy, baseWrench, _telem, _conditionedCmd)
    local wrench = {
        surge = baseWrench.surge or 0.0,
        sway = baseWrench.sway or 0.0,
        heave = baseWrench.heave or 0.0,
        rollTorque = baseWrench.rollTorque or 0.0,
        pitchTorque = (baseWrench.pitchTorque or 0.0) + (policy.pitchTrim or 0.0),
        yawTorque = baseWrench.yawTorque or 0.0
    }
    if policy.antiTorqueCoeff ~= 0.0 then
        wrench.yawTorque = wrench.yawTorque + (wrench.heave * policy.antiTorqueCoeff)
    end
    return wrench
end

function vehicle_policy.transition_blend(hoverWrench, cruiseWrench, alpha)
    local a = math.max(0.0, math.min(1.0, tonumber(alpha) or 0.0))
    local invA = 1.0 - a
    return {
        surge = invA * (hoverWrench.surge or 0) + a * (cruiseWrench.surge or 0),
        sway = invA * (hoverWrench.sway or 0) + a * (cruiseWrench.sway or 0),
        heave = invA * (hoverWrench.heave or 0) + a * (cruiseWrench.heave or 0),
        rollTorque = invA * (hoverWrench.rollTorque or 0) + a * (cruiseWrench.rollTorque or 0),
        pitchTorque = invA * (hoverWrench.pitchTorque or 0) + a * (cruiseWrench.pitchTorque or 0),
        yawTorque = invA * (hoverWrench.yawTorque or 0) + a * (cruiseWrench.yawTorque or 0)
    }
end

return vehicle_policy
