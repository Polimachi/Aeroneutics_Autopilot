-- VAS Layer 3B: ASA Aerodynamic Surface Adapter & V^2 Scaling Module (VAS v1.20.0)
local actuator_adapter_asa = {}

function actuator_adapter_asa.init(surfacesConfig)
    local cfg = surfacesConfig or {}
    local adapter = {
        surfaceGeometry = cfg.surfaceGeometry or {},
        speedLimits = cfg.speedLimits or {},
        coefficients = cfg.coefficients or {},
        saturationStatus = {
            axisSaturatedPos = { pitch = false, roll = false, yaw = false },
            axisSaturatedNeg = { pitch = false, roll = false, yaw = false }
        },
        surfacesFeedback = {},
        discoveredPods = {},
        healthStatus = "NOMINAL",
        lastQScale = 1.0
    }

    adapter.register_surface_node = function(self, payload)
        return actuator_adapter_asa.register_surface_node(self, payload)
    end
    adapter.update_feedback = function(self, payload)
        return actuator_adapter_asa.update_feedback(self, payload)
    end
    adapter.compute_q_scaling = function(self, airspeed)
        return actuator_adapter_asa.compute_q_scaling(self, airspeed)
    end
    adapter.allocate = function(self, wrench, airspeed, flapTarget)
        return actuator_adapter_asa.allocate(self, wrench, airspeed, flapTarget)
    end
    return adapter
end

function actuator_adapter_asa.compute_q_scaling(state, airspeed)
    local v = tonumber(airspeed)
    if not v or v <= 0.0 then return 1.0 end
    local coeff = state.coefficients or {}
    local lim = state.speedLimits or {}
    local vRef = coeff.qScalingRefSpeed or lim.vRef or 20.0
    local vMin = lim.vMin or 5.0
    local minQ = coeff.minQScale or 0.25
    local maxQ = coeff.maxQScale or 2.50

    local vEff = math.max(v, vMin)
    local ratio = vRef / vEff
    return math.max(minQ, math.min(maxQ, ratio * ratio))
end

local function check_axis_sat(sat, axis, sign, isPosLimit)
    if axis ~= "pitch" and axis ~= "roll" and axis ~= "yaw" then return end
    if sign > 0.05 then
        if isPosLimit then sat.axisSaturatedPos[axis] = true
        else sat.axisSaturatedNeg[axis] = true end
    elseif sign < -0.05 then
        if isPosLimit then sat.axisSaturatedNeg[axis] = true
        else sat.axisSaturatedPos[axis] = true end
    end
end

function actuator_adapter_asa.allocate(state, wrench, airspeed, flapTarget)
    local qScale = actuator_adapter_asa.compute_q_scaling(state, airspeed)
    state.lastQScale = qScale
    local satAsa = {
        axisSaturatedPos = { pitch = false, roll = false, yaw = false },
        axisSaturatedNeg = { pitch = false, roll = false, yaw = false }
    }
    local w = wrench or {}
    local torques = {
        pitch = tonumber(w.pitchTorque) or 0.0,
        roll = tonumber(w.rollTorque) or 0.0,
        yaw = tonumber(w.yawTorque) or 0.0
    }
    local flap = math.max(0.0, math.min(1.0, tonumber(flapTarget) or 0.0))
    local outputs = {}

    for name, geom in pairs(state.surfaceGeometry or {}) do
        local axis = geom.axis
        local sign = tonumber(geom.sign) or 1.0
        if axis == "lift" then
            outputs[name] = math.max(0.0, math.min(1.0, flap * sign))
        else
            local moment = sign * (torques[axis] or 0.0)
            local raw = (geom.trim or 0.0) + qScale * moment
            local clamped = math.max(-1.0, math.min(1.0, raw))
            outputs[name] = clamped
            if clamped >= 1.0 then check_axis_sat(satAsa, axis, sign, true)
            elseif clamped <= -1.0 then check_axis_sat(satAsa, axis, sign, false) end
        end
    end
    state.saturationStatus = satAsa
    return outputs, satAsa, qScale
end

function actuator_adapter_asa.register_surface_node(state, payload)
    if not state or not payload then return false end
    state.discoveredPods = state.discoveredPods or {}
    local podId = payload.podId or ("POD_" .. tostring(#state.discoveredPods + 1))
    state.discoveredPods[podId] = {
        podId = podId,
        managedSurfaces = payload.managedSurfaces or {},
        boundPorts = payload.boundPorts or {},
        healthStatus = payload.healthStatus or "NOMINAL"
    }
    return true
end

function actuator_adapter_asa.update_feedback(state, payload)
    if not payload or not payload.surfaceId then return end
    state.surfacesFeedback[payload.surfaceId] = {
        podId = payload.podId,
        boundSide = payload.boundSide,
        interactionMode = payload.interactionMode or "API",
        appliedDeflection = tonumber(payload.appliedDeflection) or 0.0,
        isSaturated = payload.isSaturated == true,
        isJammed = payload.isJammed == true,
        healthStatus = payload.healthStatus or "NOMINAL"
    }
    local hasDegraded, hasLoss = false, false
    for _, fb in pairs(state.surfacesFeedback) do
        if fb.healthStatus == "TOTAL_LOSS" then hasLoss = true
        elseif fb.healthStatus == "DEGRADED" or fb.isJammed then hasDegraded = true end
    end
    if hasLoss then state.healthStatus = "TOTAL_LOSS"
    elseif hasDegraded then state.healthStatus = "DEGRADED"
    else state.healthStatus = "NOMINAL" end
end

return actuator_adapter_asa
