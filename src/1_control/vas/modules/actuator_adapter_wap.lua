-- VAS WAP Aerodynamic Surface Adapter & V^2 Scaling Module (Layer 3B)
local actuator_adapter_wap = {}

function actuator_adapter_wap.init(surfacesConfig)
    local cfg = surfacesConfig or {}
    return {
        surfaceMix = cfg.surfaceMix or {},
        aeroEnvelope = cfg.aeroEnvelope or {},
        speedLimits = cfg.speedLimits or {},
        coefficients = cfg.coefficients or {},
        saturationStatus = {
            axisSaturatedPos = { pitch = false, roll = false, yaw = false },
            axisSaturatedNeg = { pitch = false, roll = false, yaw = false }
        },
        surfacesFeedback = {},
        healthStatus = "API_NOMINAL"
    }
end

function actuator_adapter_wap.compute_q_scaling(state, airspeed)
    local v = tonumber(airspeed)
    if not v or v <= 0.0 then return 1.0 end
    local env = state.aeroEnvelope or {}
    local vRef = env.vRef or 15.0
    local vMin = env.vMin or 8.0
    local minQ = env.minDynScale or 0.35
    local maxQ = env.maxDynScale or 2.00

    local vEff = math.max(v, vMin)
    local ratio = vRef / vEff
    return math.max(minQ, math.min(maxQ, ratio * ratio))
end

local function check_axis_sat(sat, mix, isPosLimit)
    local axes = { pitch = mix.pitch or 0, roll = mix.roll or 0, yaw = mix.yaw or 0 }
    for ax, coeff in pairs(axes) do
        if coeff > 0.05 then
            if isPosLimit then sat.axisSaturatedPos[ax] = true
            else sat.axisSaturatedNeg[ax] = true end
        elseif coeff < -0.05 then
            if isPosLimit then sat.axisSaturatedNeg[ax] = true
            else sat.axisSaturatedPos[ax] = true end
        end
    end
end

function actuator_adapter_wap.allocate(state, wrench, airspeed, flapTarget)
    local qScale = actuator_adapter_wap.compute_q_scaling(state, airspeed)
    local sat = {
        axisSaturatedPos = { pitch = false, roll = false, yaw = false },
        axisSaturatedNeg = { pitch = false, roll = false, yaw = false }
    }
    local w = wrench or {}
    local tauP = tonumber(w.pitchTorque or w.pitch) or 0.0
    local tauR = tonumber(w.rollTorque or w.roll) or 0.0
    local tauY = tonumber(w.yawTorque or w.yaw) or 0.0
    local flap = math.max(0.0, math.min(1.0, tonumber(flapTarget) or 0.0))
    local outputs = {}

    for name, mix in pairs(state.surfaceMix or {}) do
        local mFlap = mix.flap or 0.0
        if mFlap > 0.0 then
            local fVal = math.max(0.0, math.min(1.0, flap * mFlap))
            outputs[name] = math.floor(fVal * 15.0 + 0.5)
        else
            local moment = (mix.pitch or 0) * tauP + (mix.roll or 0) * tauR + (mix.yaw or 0) * tauY
            local raw = (mix.trim or 0) + qScale * moment
            local rng = mix.range or { -1.0, 1.0 }
            local clamped = math.max(rng[1], math.min(rng[2], raw))
            local step = math.floor(clamped * 15.0 + 0.5)
            outputs[name] = step
            if step >= 15 then check_axis_sat(sat, mix, true)
            elseif step <= -15 then check_axis_sat(sat, mix, false) end
        end
    end
    state.saturationStatus = sat
    return outputs, sat
end

function actuator_adapter_wap.update_feedback(state, payload)
    if not payload or not payload.surfaceId then return end
    state.surfacesFeedback[payload.surfaceId] = {
        appliedDeg = payload.appliedDeg or 0.0,
        appliedRatio = payload.appliedRatio or 0.0,
        isSaturated = payload.isSaturated == true,
        healthStatus = payload.healthStatus or "API_NOMINAL"
    }
    local hasDegraded, hasLoss = false, false
    for _, fb in pairs(state.surfacesFeedback) do
        local h = fb.healthStatus
        if h == "API_TOTAL_LOSS" then hasLoss = true
        elseif h == "MECHANICAL_JAM" or h == "MOTOR_FAULT" or h == "API_DEGRADED" then
            hasDegraded = true
        end
    end
    if hasLoss then state.healthStatus = "API_TOTAL_LOSS"
    elseif hasDegraded then state.healthStatus = "API_DEGRADED"
    else state.healthStatus = "API_NOMINAL" end
end

return actuator_adapter_wap
