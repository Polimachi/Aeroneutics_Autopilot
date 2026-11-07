-- radar_math.lua - BBox Centroid and 2D Grid Projection for GPS Radar
local radar_math = {}

function radar_math.computeCentroidSpan(points, marginFactor)
    local margin = marginFactor or 1.2
    if not points or #points == 0 then
        return { centerX = 0, centerZ = 0, spanX = 20, spanZ = 20 }
    end

    local minX, maxX = points[1].x or 0, points[1].x or 0
    local minZ, maxZ = points[1].z or 0, points[1].z or 0

    for i = 2, #points do
        local px, pz = points[i].x or 0, points[i].z or 0
        if px < minX then minX = px end
        if px > maxX then maxX = px end
        if pz < minZ then minZ = pz end
        if pz > maxZ then maxZ = pz end
    end

    local diffX = maxX - minX
    local diffZ = maxZ - minZ
    local spanX = math.max(20, diffX * margin)
    local spanZ = math.max(20, diffZ * margin)

    return {
        centerX = (minX + maxX) / 2,
        centerZ = (minZ + maxZ) / 2,
        spanX = spanX,
        spanZ = spanZ,
        minX = minX,
        maxX = maxX,
        minZ = minZ,
        maxZ = maxZ
    }
end

function radar_math.projectToGrid(x, z, bounds, screenW, screenH)
    local w = screenW or 79
    local h = screenH or 36
    local b = bounds or { centerX = 0, centerZ = 0, spanX = 20, spanZ = 20 }

    local scaleX = b.spanX / w
    local scaleZ = b.spanZ / h
    local scale = math.max(scaleX, scaleZ)
    if scale <= 0 then scale = 1 end

    local dx = (x or 0) - b.centerX
    local dz = (z or 0) - b.centerZ

    local sx = math.floor((w / 2) + (dx / scale) + 0.5)
    local sz = math.floor((h / 2) + (dz / scale) + 0.5)
    return sx, sz
end

function radar_math.isInBounds(sx, sz, screenW, screenH)
    local w = screenW or 79
    local h = screenH or 36
    return sx >= 1 and sx <= w and sz >= 1 and sz <= h
end

return radar_math
