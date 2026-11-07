-- VAS Layer 3: Platform Actuator Adapter for TAP Cluster (VICD-Spec v1.1.1)
local actuator_adapter_tca = {}

local function parse_coefficients(profileOrConfig)
    if type(profileOrConfig) == "table" then
        return profileOrConfig.thrusterCoefficients or {}
    end
    return {}
end

function actuator_adapter_tca.init(profileOrConfig)
    local coeffs = parse_coefficients(profileOrConfig)
    local isFallback = true
    if type(profileOrConfig) == "table" and profileOrConfig.isStaticFallback ~= nil then
        isFallback = profileOrConfig.isStaticFallback == true
    end
    local adapter = {
        coefficients = coeffs, groupStatus = {}, registeredNodes = {},
        tcaConnected = false, lastFeedbackMs = 0, healthStatus = "API_NOMINAL",
        dynamicLoad = 0.0, isStaticFallback = isFallback,
        saturationStatus = {
            axisSaturatedPos = { surge = false, sway = false, heave = false, roll = false, pitch = false, yaw = false },
            axisSaturatedNeg = { surge = false, sway = false, heave = false, roll = false, pitch = false, yaw = false }
        }
    }
    adapter.register_actuator_node = function(self, payload)
        return actuator_adapter_tca.register_actuator_node(self, payload)
    end
    adapter.update_actuator_feedback = function(self, payload)
        return actuator_adapter_tca.update_actuator_feedback(self, payload)
    end
    adapter.reload_coefficients = function(self, p, isFb)
        return actuator_adapter_tca.reload_coefficients(self, p, isFb)
    end
    return adapter
end

function actuator_adapter_tca.reload_coefficients(state, profileOrCoeffs, isFallback)
    local coeffs = parse_coefficients(profileOrCoeffs)
    state.coefficients = coeffs
    state.isStaticFallback = (isFallback == true)
    return true
end

local function scale_thrust_signal(rawDemand, coeff)
    if rawDemand <= 0.05 then return 0, false, false end
    local db = coeff.deadband or 1.0
    local maxT = coeff.maxThrust or 15
    local clamped = math.min(15.0, rawDemand)
    local scaled = db + (15.0 - db) * (clamped / 15.0)
    local outSignal = math.max(math.ceil(db), math.min(maxT, math.floor(scaled + 0.5)))
    local isMax = (outSignal >= maxT) or (rawDemand >= 15.0)
    return outSignal, isMax, false
end

local AXIS_MAP = {
    surge = "surge", sway = "sway", heave = "heave",
    rollTorque = "roll", pitchTorque = "pitch", yawTorque = "yaw"
}

function actuator_adapter_tca.allocate(state, wrench)
    local outputs = {}
    local satPos = { surge = false, sway = false, heave = false, roll = false, pitch = false, yaw = false }
    local satNeg = { surge = false, sway = false, heave = false, roll = false, pitch = false, yaw = false }

    for groupId, coeff in pairs(state.coefficients or {}) do
        local raw = 0.0
        for wrenchKey, axisName in pairs(AXIS_MAP) do
            local cVal = coeff[axisName] or 0.0
            raw = raw + cVal * (wrench[wrenchKey] or 0.0)
        end
        local sig, isMax, isMin = scale_thrust_signal(raw, coeff)
        outputs[groupId] = sig

        if isMax then
            for _, axisName in pairs(AXIS_MAP) do
                local cVal = coeff[axisName] or 0.0
                if cVal > 0.01 then satPos[axisName] = true
                elseif cVal < -0.01 then satNeg[axisName] = true end
            end
        end
        if isMin then
            for _, axisName in pairs(AXIS_MAP) do
                local cVal = coeff[axisName] or 0.0
                if cVal > 0.01 then satNeg[axisName] = true
                elseif cVal < -0.01 then satPos[axisName] = true end
            end
        end
    end

    state.saturationStatus = { axisSaturatedPos = satPos, axisSaturatedNeg = satNeg }
    return outputs, state.saturationStatus
end

function actuator_adapter_tca.compute_dynamic_load(state, outputs)
    local total, count = 0, 0
    for groupId, _ in pairs(state.coefficients or {}) do
        total = total + (outputs[groupId] or 0)
        count = count + 1
    end
    if count == 0 then
        state.dynamicLoad = 0.0
        return 0.0
    end
    local load = math.min(1.0, total / (15.0 * count))
    state.dynamicLoad = load
    return load
end

function actuator_adapter_tca.register_actuator_node(state, payload)
    if not payload or not payload.groupId then return false end
    state.registeredNodes = state.registeredNodes or {}
    state.registeredNodes[payload.groupId] = payload
    state.tcaConnected = true
    state.lastFeedbackMs = (os.epoch and os.epoch("utc")) or 0
    state.healthStatus = payload.healthStatus or "API_NOMINAL"
    return true
end

function actuator_adapter_tca.update_actuator_feedback(state, payload)
    if not payload or not payload.groupId then return false end
    local sig = payload.appliedSignal
    state.groupStatus[payload.groupId] = {
        interactionMode = payload.interactionMode or "API",
        isSaturated = (payload.isSaturated == true),
        appliedSignal = sig,
        appliedRatio = payload.appliedRatio or (sig and (sig / 15.0)),
        activeCount = payload.activeCount or 0,
        totalCount = payload.totalCount or 0,
        healthStatus = payload.healthStatus or "API_NOMINAL"
    }
    state.tcaConnected = true
    state.lastFeedbackMs = (os.epoch and os.epoch("utc")) or 0
    state.healthStatus = payload.healthStatus or "API_NOMINAL"
    if payload.appliedRatio then
        state.dynamicLoad = payload.appliedRatio
    elseif sig then
        state.dynamicLoad = math.min(1.0, sig / 15.0)
    end
    return payload.healthStatus == "API_TOTAL_LOSS"
end

return actuator_adapter_tca
