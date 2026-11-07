-- 5-Axis Controllability & Aerodynamic Surface Checker
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
    for _, coeff in pairs(thrusterCoeffs) do
        for _, a in ipairs(AXES) do
            local val = coeff[a] or 0
            if val > 0 then
                auth[a].pos = auth[a].pos + val
            elseif val < 0 then
                auth[a].neg = auth[a].neg + math.abs(val)
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

function controllability_checker.evaluate(thrusterCoeffs, airframeType, surfaces, customThresholds)
    local th = customThresholds or DEFAULT_THRESHOLDS
    local auth = controllability_checker.calculate_authorities(thrusterCoeffs)
    local sPass, hPass, pPass, rPass, yPass = check_axis_pass(auth, airframeType, th)
    
    local status = "FAIL_INSUFFICIENT_AUTHORITY"
    if sPass and hPass and pPass and rPass and yPass then
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
