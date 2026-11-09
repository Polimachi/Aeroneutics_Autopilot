-- 5-Axis / 6-DoF Controllability & Aerodynamic Surface Checker
local controllability_checker = {}

local AXES = { "surge", "sway", "heave", "pitch", "roll", "yaw" }

local DEFAULT_THRESHOLDS = {
    minSurge = 0.50,
    minHeave = 0.50,
    minPitch = 0.20,
    minRoll  = 0.05,
    minYaw   = 0.10
}

function controllability_checker.calculate_authorities(thrusterCoeffs)
    local auth = {}
    for _, a in ipairs(AXES) do auth[a] = { pos = 0, neg = 0 } end
    for _, coeff in pairs(thrusterCoeffs or {}) do
        -- Check if vector derivative format is present
        if coeff.dThrust or coeff.dGimbalX or coeff.dGimbalY then
            local dT = coeff.dThrust or {}
            local dX = coeff.dGimbalX or {}
            local dY = coeff.dGimbalY or {}
            for _, a in ipairs(AXES) do
                local tVal = dT[a] or 0
                local xSpan = math.abs(dX[a] or 0)
                local ySpan = math.abs(dY[a] or 0)
                local gSpan = xSpan + ySpan
                if tVal > 0 then
                    auth[a].pos = auth[a].pos + tVal + gSpan
                    auth[a].neg = auth[a].neg + gSpan
                elseif tVal < 0 then
                    auth[a].pos = auth[a].pos + gSpan
                    auth[a].neg = auth[a].neg + math.abs(tVal) + gSpan
                else
                    auth[a].pos = auth[a].pos + gSpan
                    auth[a].neg = auth[a].neg + gSpan
                end
            end
        else
            for _, a in ipairs(AXES) do
                local val = coeff[a] or 0
                if val > 0 then
                    auth[a].pos = auth[a].pos + val
                elseif val < 0 then
                    auth[a].neg = auth[a].neg + math.abs(val)
                end
            end
        end
    end
    return auth
end

local function has_valid_surfaces(surfaces)
    surfaces = surfaces or {}
    local hasAil = surfaces.AIL or (surfaces.AIL_L and surfaces.AIL_R)
    local hasElev = surfaces.ELEV ~= nil
    return (hasAil and hasElev)
end

local function check_axis_pass(auth, airframe, th)
    local isFixedWing = (airframe == "FIXED_WING")
    local surgePass = auth.surge.pos >= th.minSurge
    local heavePass = isFixedWing or (auth.heave.pos >= th.minHeave)
    local pitchPass = (auth.pitch.pos >= th.minPitch) and (auth.pitch.neg >= th.minPitch)
    local rollPass  = (auth.roll.pos  >= th.minRoll)  and (auth.roll.neg  >= th.minRoll)
    local yawPass   = (auth.yaw.pos   >= th.minYaw)   and (auth.yaw.neg   >= th.minYaw)
    return surgePass, heavePass, pitchPass, rollPass, yawPass
end

local function check_pseudo_inverse_controllability(bMatrix, pseudoInverse)
    if not bMatrix or not pseudoInverse then return false end
    local rowsB = #bMatrix
    local colsB = #bMatrix[1]
    local rowsP = #pseudoInverse
    local colsP = #pseudoInverse[1]
    if rowsB ~= 6 or colsB ~= rowsP or colsP ~= 6 then
        return false
    end
    for i = 1, 6 do
        for j = 1, 6 do
            local sum = 0.0
            for k = 1, colsB do
                sum = sum + bMatrix[i][k] * pseudoInverse[k][j]
            end
            local expected = (i == j) and 1.0 or 0.0
            if math.abs(sum - expected) > 0.05 then
                return false
            end
        end
    end
    return true
end

function controllability_checker.evaluate(thrusterCoeffs, airframeType, surfaces, customThresholds, pseudoInverse, bMatrix)
    local th = customThresholds or DEFAULT_THRESHOLDS
    local auth = controllability_checker.calculate_authorities(thrusterCoeffs)
    local sPass, hPass, pPass, rPass, yPass = check_axis_pass(auth, airframeType, th)

    local isVectorControllable = false
    if airframeType == "ADVANCED_VTOL" and bMatrix and pseudoInverse then
        isVectorControllable = check_pseudo_inverse_controllability(bMatrix, pseudoInverse)
    end
    
    local status = "FAIL_INSUFFICIENT_AUTHORITY"
    if (sPass and hPass and pPass and rPass and yPass) or isVectorControllable then
        status = "FULL_6DOF_PASS"
    elseif sPass and has_valid_surfaces(surfaces) and (airframeType == "FIXED_WING" or airframeType == "WINGED_VTOL") then
        status = "AERO_ASSISTED_PASS"
    elseif sPass then
        status = "PARTIAL_RESTRICTED"
    end
    
    return {
        status = status,
        authorities = auth,
        passed = (status == "FULL_6DOF_PASS" or status == "AERO_ASSISTED_PASS")
    }
end

return controllability_checker
