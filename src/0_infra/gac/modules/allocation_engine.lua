-- src/0_infra/gac/modules/allocation_engine.lua
-- 2-stage multi-attribute pad allocation engine for GAC

local allocation_engine = {}

local DEFAULT_W1 = 0.50
local DEFAULT_W2 = 0.35
local DEFAULT_W3 = 0.15
local DEFAULT_D_NORM = 200.0

function allocation_engine.filter_candidates(facilities, craftWeight, craftRadius)
    local candidates = {}
    if type(facilities) ~= "table" then
        return candidates
    end

    local weight = craftWeight or 0
    local radius = craftRadius or 0

    for _, fac in pairs(facilities) do
        if fac.status == "FREE" then
            local maxW = fac.maxSupportWeight or 0
            local maxR = fac.maxSupportRadius or 0
            if maxW >= weight and maxR >= radius then
                table.insert(candidates, fac)
            end
        end
    end

    table.sort(candidates, function(a, b) return tostring(a.facilityId) < tostring(b.facilityId) end)
    return candidates
end

function allocation_engine.calculate_score(pad, craftPos, windDir, craftWeight, weights, dNorm)
    local w1 = weights and weights.w1 or DEFAULT_W1
    local w2 = weights and weights.w2 or DEFAULT_W2
    local w3 = weights and weights.w3 or DEFAULT_W3
    local normDist = dNorm or DEFAULT_D_NORM

    -- 1. Wind alignment score
    local appHeading = pad.approachHeading or 0.0
    local windHeading = windDir or 0.0
    local angleDiffRad = math.rad(windHeading - appHeading)
    local windScore = math.cos(angleDiffRad)

    -- 2. Distance score (Euclidean 3D)
    local dist = 0.0
    if craftPos and pad.coordinates then
        local dx = (craftPos.x or 0) - (pad.coordinates.x or 0)
        local dy = (craftPos.y or 0) - (pad.coordinates.y or 0)
        local dz = (craftPos.z or 0) - (pad.coordinates.z or 0)
        dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    local distScore = dist / normDist

    -- 3. Weight margin score
    local padMaxWeight = pad.maxSupportWeight or craftWeight or 1.0
    local cWeight = craftWeight and craftWeight > 0 and craftWeight or 1.0
    local weightScore = (padMaxWeight - cWeight) / cWeight

    local totalScore = (w1 * windScore) - (w2 * distScore) + (w3 * weightScore)
    return totalScore
end

function allocation_engine.select_best_pad(facilities, craftReq, surfaceWind, opts)
    if type(facilities) ~= "table" or type(craftReq) ~= "table" then
        return nil, "INVALID_ARGUMENTS"
    end

    local craftWeight = craftReq.craftWeight or 0
    local craftRadius = craftReq.craftRadius or 0
    local craftPos = craftReq.currentPos or { x = 0, y = 0, z = 0 }
    local windDir = surfaceWind and surfaceWind.direction or 0.0

    -- Preferred facility check
    if craftReq.preferredFacilityId then
        for _, fac in pairs(facilities) do
            if fac.facilityId == craftReq.preferredFacilityId then
                if fac.status == "FREE" and (fac.maxSupportWeight or 0) >= craftWeight and (fac.maxSupportRadius or 0) >= craftRadius then
                    return fac, nil
                end
            end
        end
    end

    -- Stage 1: Hard filter
    local validCandidates = allocation_engine.filter_candidates(facilities, craftWeight, craftRadius)
    if #validCandidates == 0 then
        -- Check if any free pad exists at all to distinguish error reasons
        local hasFreePad = false
        for _, fac in pairs(facilities) do
            if fac.status == "FREE" then
                hasFreePad = true
                break
            end
        end

        if hasFreePad then
            return nil, "OVERWEIGHT"
        else
            return nil, "SECTOR_ALL_OCCUPIED"
        end
    end

    -- Stage 2: Soft scoring
    local bestPad = nil
    local bestScore = -math.huge

    for _, pad in ipairs(validCandidates) do
        local score = allocation_engine.calculate_score(pad, craftPos, windDir, craftWeight, opts and opts.weights, opts and opts.dNorm)
        if score > bestScore then
            bestScore = score
            bestPad = pad
        end
    end

    return bestPad, nil
end

return allocation_engine
