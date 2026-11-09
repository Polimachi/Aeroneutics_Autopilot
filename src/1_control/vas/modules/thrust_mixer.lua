--[[
    ========================================================================
    VAS 6-DOF THRUST MIXER MODULE (thrust_mixer.lua)
    VAS Layer 2: 6-DoF Wrench to Thruster Group Mixer & Vector Allocation
    
    [역할]
    - 6-DoF 요구치(surge, sway, heave, pitch, roll, yaw)로부터 추진기 그룹별 출력 배분
    - ADVANCED_VTOL 2D 짐벌 벡터 추진기 의사역행렬(B†) 기반 제어 입력 할당
    - 데드밴드(deadband) 및 최대 추력 클램핑(0~15), 짐벌 편향 클램핑(-1.0~1.0)
    - 방향성 안티 와인드업(saturationStatus) 및 다이내믹 로드(dynamicLoad) 산출
    ========================================================================
]]

local thrust_mixer = {}

local DEFAULT_AXES = { "surge", "sway", "heave", "pitch", "roll", "yaw" }

local function parse_profile(profileOrConfig)
    local p = profileOrConfig
    if type(p) == "string" and fs and fs.exists and fs.exists(p) then
        local f = fs.open(p, "r")
        if f then
            local text = f.readAll()
            f.close()
            p = textutils and textutils.unserialiseJSON and textutils.unserialiseJSON(text) or {}
        end
    end
    return type(p) == "table" and p or {}
end

local function extract_coefficients(p)
    if p.coefficients then return p.coefficients end
    if p.thrusterCoefficients then return p.thrusterCoefficients end
    if p.pseudoInverseMatrix or p.airframeType or p.isVectorVtol then
        return {}
    end
    return p
end

--- 쓰러스트 믹서 상태 초기화
---@param profileOrConfig table|string?
---@return table mixerState
function thrust_mixer.init(profileOrConfig)
    local p = parse_profile(profileOrConfig)
    local coeffs = extract_coefficients(p)

    local isVector = (p.isVectorVtol == true) or (p.airframeType == "ADVANCED_VTOL") or (p.vehicleType == "ADVANCED_VTOL")
    local pseudoInv = p.pseudoInverseMatrix
    local ctrlEff = p.controlEffectivenessMatrix
    local vecGroupOrder = p.vectorGroupOrder or p.groupOrder or p.vectorGroups
    local axesOrder = p.axesOrder or DEFAULT_AXES

    return {
        coefficients = coeffs,
        groupStatus = {},
        dynamicLoad = 0.0,
        isVectorVtol = isVector,
        pseudoInverseMatrix = pseudoInv,
        controlEffectivenessMatrix = ctrlEff,
        vectorGroupOrder = vecGroupOrder,
        axesOrder = axesOrder,
        saturationStatus = {
            axisSaturatedPos = { surge = false, sway = false, heave = false, roll = false, pitch = false, yaw = false },
            axisSaturatedNeg = { surge = false, sway = false, heave = false, roll = false, pitch = false, yaw = false }
        }
    }
end

--- 개별 추진기 그룹 출력 스케일링 (스칼라 믹서용)
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

--- 방향성 안티 와인드업 축 포화 태깅
local function tag_axis_saturation(state, inputIdx, isHigh, satPos, satNeg, axes)
    local B_dag = state.pseudoInverseMatrix
    local B = state.controlEffectivenessMatrix
    for k, ax in ipairs(axes) do
        local coeff = (B_dag and B_dag[inputIdx] and B_dag[inputIdx][k])
        if not coeff and B and B[k] then
            coeff = B[k][inputIdx]
        end
        if coeff then
            local mapAxis = ax
            if ax == "pitchTorque" then mapAxis = "pitch"
            elseif ax == "rollTorque" then mapAxis = "roll"
            elseif ax == "yawTorque" then mapAxis = "yaw" end

            if isHigh then
                if coeff > 0.001 then satPos[mapAxis] = true
                elseif coeff < -0.001 then satNeg[mapAxis] = true end
            else
                if coeff > 0.001 then satNeg[mapAxis] = true
                elseif coeff < -0.001 then satPos[mapAxis] = true end
            end
        end
    end
end

--- ADVANCED_VTOL 의사역행렬 제어 할당 (6-DoF Wrench -> 다형성 벡터 지령)
---@param state table
---@param demand table { surge, sway, heave, pitch, roll, yaw }
---@return table outputs { [groupId] = { thrust, gimbalX, gimbalY } }
---@return table saturationStatus
function thrust_mixer.allocate_vector_vtol(state, demand)
    local B_dagger = state.pseudoInverseMatrix
    if not B_dagger or #B_dagger == 0 then
        if state.isVectorVtol then
            print("[WARN] [thrust_mixer] pseudoInverseMatrix missing for vector VTOL, falling back to scalar mixer")
        end
        local scalarOut = thrust_mixer.mix(state, demand)
        return scalarOut, state.saturationStatus
    end

    local axes = state.axesOrder or DEFAULT_AXES
    local w = {}
    for i, ax in ipairs(axes) do
        if ax == "surge" then w[i] = tonumber(demand.surge) or 0.0
        elseif ax == "sway" then w[i] = tonumber(demand.sway) or 0.0
        elseif ax == "heave" then w[i] = tonumber(demand.heave) or 0.0
        elseif ax == "pitch" or ax == "pitchTorque" then w[i] = tonumber(demand.pitchTorque or demand.pitch) or 0.0
        elseif ax == "roll" or ax == "rollTorque" then w[i] = tonumber(demand.rollTorque or demand.roll) or 0.0
        elseif ax == "yaw" or ax == "yawTorque" then w[i] = tonumber(demand.yawTorque or demand.yaw) or 0.0
        else w[i] = tonumber(demand[ax]) or 0.0 end
    end

    local numInputs = #B_dagger
    local u = {}
    for r = 1, numInputs do
        local sum = 0.0
        local row = B_dagger[r] or {}
        for c = 1, #axes do
            sum = sum + (row[c] or 0.0) * (w[c] or 0.0)
        end
        u[r] = sum
    end

    local numGroups = math.floor(numInputs / 3)
    local groupOrder = state.vectorGroupOrder
    if not groupOrder or #groupOrder < numGroups then
        groupOrder = {}
        if state.coefficients then
            for gid, _ in pairs(state.coefficients) do
                table.insert(groupOrder, gid)
            end
            table.sort(groupOrder)
        end
        if #groupOrder < numGroups then
            for i = #groupOrder + 1, numGroups do
                table.insert(groupOrder, "THR_VEC_" .. i)
            end
        end
    end

    local outputs = {}
    local satPos = { surge = false, sway = false, heave = false, roll = false, pitch = false, yaw = false }
    local satNeg = { surge = false, sway = false, heave = false, roll = false, pitch = false, yaw = false }

    for i = 1, numGroups do
        local gid = groupOrder[i]
        local rawT = u[3 * i - 2] or 0.0
        local rawGx = u[3 * i - 1] or 0.0
        local rawGy = u[3 * i] or 0.0

        -- Clamp thrust 0..15
        local T = math.max(0, math.min(15, math.floor(rawT + 0.5)))
        -- Clamp gimbals -1.0..1.0
        local gx = math.max(-1.0, math.min(1.0, rawGx))
        local gy = math.max(-1.0, math.min(1.0, rawGy))

        outputs[gid] = {
            thrust = T,
            gimbalX = gx,
            gimbalY = gy
        }

        -- Check saturation for thrust
        if rawT >= 15.0 or T >= 15 then
            tag_axis_saturation(state, 3 * i - 2, true, satPos, satNeg, axes)
        elseif rawT <= 0.0 or T <= 0 then
            tag_axis_saturation(state, 3 * i - 2, false, satPos, satNeg, axes)
        end

        -- Check saturation for gimbalX
        if rawGx >= 1.0 or gx >= 1.0 then
            tag_axis_saturation(state, 3 * i - 1, true, satPos, satNeg, axes)
        elseif rawGx <= -1.0 or gx <= -1.0 then
            tag_axis_saturation(state, 3 * i - 1, false, satPos, satNeg, axes)
        end

        -- Check saturation for gimbalY
        if rawGy >= 1.0 or gy >= 1.0 then
            tag_axis_saturation(state, 3 * i, true, satPos, satNeg, axes)
        elseif rawGy <= -1.0 or gy <= -1.0 then
            tag_axis_saturation(state, 3 * i, false, satPos, satNeg, axes)
        end
    end

    state.saturationStatus = { axisSaturatedPos = satPos, axisSaturatedNeg = satNeg }
    return outputs, state.saturationStatus
end

--- 6-DoF Wrench 요구치로부터 추진기 그룹별 출력 산출
---@param state table
---@param demand table { surge, sway, heave, pitch, roll, yaw }
---@return table outputs { [groupId] = number | { thrust, gimbalX, gimbalY } }
function thrust_mixer.mix(state, demand)
    if state.isVectorVtol and state.pseudoInverseMatrix and #state.pseudoInverseMatrix > 0 then
        local outputs, _ = thrust_mixer.allocate_vector_vtol(state, demand)
        return outputs
    end

    if state.isVectorVtol and (not state.pseudoInverseMatrix or #state.pseudoInverseMatrix == 0) then
        print("[WARN] [thrust_mixer] pseudoInverseMatrix missing for vector VTOL, falling back to scalar mixer")
    end

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
    local coeffs = state.coefficients or {}
    local hasCoeffs = false
    for groupId, _ in pairs(coeffs) do
        hasCoeffs = true
        local out = safeOutputs and safeOutputs[groupId]
        local sig = (type(out) == "table" and out.thrust) or tonumber(out) or 0
        totalSignal = totalSignal + sig
        count = count + 1
    end
    if not hasCoeffs and safeOutputs then
        for _, out in pairs(safeOutputs) do
            local sig = (type(out) == "table" and out.thrust) or tonumber(out) or 0
            totalSignal = totalSignal + sig
            count = count + 1
        end
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
---@param payload table { groupId, saturated, activeCount, healthStatus, gimbalSaturated, appliedGimbal }
---@return boolean isTotalLoss
function thrust_mixer.update_actuator_feedback(state, payload)
    if not payload or not payload.groupId then
        return false
    end
    state.groupStatus[payload.groupId] = {
        saturated = payload.saturated == true or payload.isSaturated == true,
        gimbalSaturated = payload.gimbalSaturated == true,
        appliedGimbal = payload.appliedGimbal,
        activeCount = payload.activeCount or 0,
        healthStatus = payload.healthStatus or "NOMINAL"
    }
    return payload.healthStatus == "TOTAL_LOSS" or payload.healthStatus == "API_TOTAL_LOSS"
end

return thrust_mixer
