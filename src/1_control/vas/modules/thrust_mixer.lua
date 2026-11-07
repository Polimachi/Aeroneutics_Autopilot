--[[
    ========================================================================
    VAS 6-DOF THRUST MIXER MODULE (thrust_mixer.lua)
    UAFS VAS Layer 2: 6-DoF Wrench to Thruster Group Mixer
    
    [역할]
    - 6-DoF 요구치(surge, sway, heave, pitch, roll, yaw)로부터 추진기 그룹별 출력 배분
    - 데드밴드(deadband) 및 최대 추력 클램핑(0~15)
    - 다이내믹 로드(dynamicLoad) 산출 및 추진기 피드백 업데이트
    ========================================================================
]]

local thrust_mixer = {}

local function parse_profile(profileOrConfig)
    if type(profileOrConfig) == "table" then
        return profileOrConfig.coefficients or profileOrConfig.thrusterCoefficients or profileOrConfig
    end
    if type(profileOrConfig) == "string" and fs and fs.exists(profileOrConfig) then
        local f = fs.open(profileOrConfig, "r")
        if f then
            local text = f.readAll()
            f.close()
            local data = textutils and textutils.unserialiseJSON and textutils.unserialiseJSON(text)
            if data then
                return data.coefficients or data.thrusterCoefficients or data
            end
        end
    end
    return {}
end

--- 쓰러스트 믹서 상태 초기화
---@param profileOrConfig table|string?
---@return table mixerState
function thrust_mixer.init(profileOrConfig)
    local coeffs = parse_profile(profileOrConfig)
    return {
        coefficients = coeffs,
        groupStatus = {},
        dynamicLoad = 0.0
    }
end

--- 개별 추진기 그룹 출력 스케일링
---@param raw number
---@param coeff table
---@return number scaledOutput
local function scale_thrust_output(raw, coeff)
    if raw <= 0.05 then
        return 0
    end
    local db = coeff.deadband or 1.0
    local maxT = coeff.maxThrust or 15
    local clampedRaw = math.min(15.0, raw)
    local scaled = db + (15.0 - db) * (clampedRaw / 15.0)
    return math.max(math.ceil(db), math.min(maxT, math.floor(scaled + 0.5)))
end

--- 6-DoF Wrench 요구치로부터 추진기 그룹별 정수 출력(0~15) 산출
---@param state table
---@param demand table { surge, sway, heave, pitch, roll, yaw }
---@return table outputs { [groupId] = number }
function thrust_mixer.mix(state, demand)
    local outputs = {}
    local axes = { "surge", "sway", "heave", "pitch", "roll", "yaw" }
    for groupId, coeff in pairs(state.coefficients) do
        local raw = 0.0
        for _, ax in ipairs(axes) do
            raw = raw + (coeff[ax] or 0.0) * (demand[ax] or 0.0)
        end
        outputs[groupId] = scale_thrust_output(raw, coeff)
    end
    return outputs
end

--- 추진기 그룹들의 동적 부하율(0.0~1.0) 산출
---@param state table
---@param safeOutputs table
---@return number load
function thrust_mixer.compute_dynamic_load(state, safeOutputs)
    local totalSignal = 0
    local count = 0
    for groupId, _ in pairs(state.coefficients) do
        totalSignal = totalSignal + (safeOutputs[groupId] or 0)
        count = count + 1
    end
    if count == 0 then
        state.dynamicLoad = 0.0
        return 0.0
    end
    local load = math.min(1.0, totalSignal / (15.0 * count))
    state.dynamicLoad = load
    return load
end

--- TCA 액추에이터 상태 피드백 반영
---@param state table
---@param payload table { groupId, saturated, activeCount, healthStatus }
---@return boolean isTotalLoss
function thrust_mixer.update_actuator_feedback(state, payload)
    if not payload or not payload.groupId then
        return false
    end
    state.groupStatus[payload.groupId] = {
        saturated = payload.saturated == true,
        activeCount = payload.activeCount or 0,
        healthStatus = payload.healthStatus or "NOMINAL"
    }
    return payload.healthStatus == "TOTAL_LOSS"
end

return thrust_mixer
