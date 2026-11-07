-- Dominant Axis Auto-Selection and OLS Linear Regression Engine
local ols_engine = {}

local AXES = { "surge", "sway", "heave", "pitch", "roll", "yaw" }

function ols_engine.identify_dominant_axis(impulseList)
    local sums = { surge = 0, sway = 0, heave = 0, pitch = 0, roll = 0, yaw = 0 }
    for _, imp in ipairs(impulseList) do
        for _, axis in ipairs(AXES) do
            sums[axis] = sums[axis] + math.abs(imp[axis] or 0)
        end
    end
    local bestAxis, maxVal = "surge", -1
    for _, axis in ipairs(AXES) do
        if sums[axis] > maxVal then
            maxVal = sums[axis]
            bestAxis = axis
        end
    end
    return bestAxis
end

local function compute_mean(list)
    local sum = 0
    for _, v in ipairs(list) do sum = sum + v end
    return #list > 0 and (sum / #list) or 0
end

local function solve_ols(signals, values)
    local sMean = compute_mean(signals)
    local vMean = compute_mean(values)
    local num, den = 0, 0
    for i = 1, #signals do
        local ds = signals[i] - sMean
        num = num + ds * (values[i] - vMean)
        den = den + ds * ds
    end
    local k = den > 1e-12 and (num / den) or 0
    local b = vMean - k * sMean
    return k, b, sMean, vMean
end

local function compute_r2(signals, values, k, b, vMean)
    local ssTot, ssRes = 0, 0
    for i = 1, #signals do
        local dv = values[i] - vMean
        local res = values[i] - (k * signals[i] + b)
        ssTot = ssTot + dv * dv
        ssRes = ssRes + res * res
    end
    if ssTot < 1e-12 then return 1.0 end
    local r2 = 1.0 - (ssRes / ssTot)
    if r2 < 0 then r2 = 0 elseif r2 > 1.0 then r2 = 1.0 end
    return r2
end

function ols_engine.clamp_and_normalize(slopes, domSlope)
    local absDom = math.abs(domSlope or 0)
    local threshold = 0.05 * absDom
    local invDom = absDom > 1e-12 and (1.0 / absDom) or 0
    local result = {}
    for _, axis in ipairs(AXES) do
        local val = slopes[axis] or 0
        if math.abs(val) < threshold then
            result[axis] = 0.0
        else
            result[axis] = val * invDom
        end
    end
    return result
end

function ols_engine.calculate_regression(signals, impulseList, dominantAxis)
    local domValues = {}
    for _, imp in ipairs(impulseList) do
        table.insert(domValues, imp[dominantAxis] or 0)
    end
    local k, b, _, vMean = solve_ols(signals, domValues)
    local deadband = (k > 1e-12 and b < 0) and math.max(0, -b / k) or 0.0
    local r2 = compute_r2(signals, domValues, k, b, vMean)
    
    local allSlopes = {}
    for _, axis in ipairs(AXES) do
        local axisVals = {}
        for _, imp in ipairs(impulseList) do table.insert(axisVals, imp[axis] or 0) end
        allSlopes[axis] = solve_ols(signals, axisVals)
    end
    
    return {
        dominantAxis = dominantAxis,
        slope = k,
        intercept = b,
        deadband = deadband,
        confidenceR2 = r2,
        normalizedCoefficients = ols_engine.clamp_and_normalize(allSlopes, k)
    }
end

return ols_engine
