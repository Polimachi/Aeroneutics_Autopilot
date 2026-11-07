-- 2D Trilateration and LOO numerical engine for CC:Tweaked
local trilateration = {}

function trilateration.projectHorizontal(nodes, craftAlt)
    local proj = {}
    for i, node in ipairs(nodes) do
        local dy = math.abs(node.y - craftAlt)
        local r2 = math.max(0, node.distance^2 - dy^2)
        proj[i] = {
            id = tostring(node.id or ("N" .. i)),
            x = tonumber(node.x) or 0,
            y = tonumber(node.y) or 0,
            z = tonumber(node.z) or 0,
            r = math.sqrt(r2),
        }
    end
    table.sort(proj, function(a, b)
        if math.abs(a.r - b.r) > 1e-4 then return a.r < b.r end
        return a.id < b.id
    end)
    return proj
end

function trilateration.checkGeometry(n1, n2, n3)
    local ux, uz = n2.x - n1.x, n2.z - n1.z
    local vx, vz = n3.x - n1.x, n3.z - n1.z
    local cross = math.abs(ux * vz - vx * uz)
    local lenU = math.sqrt(ux * ux + uz * uz)
    local lenV = math.sqrt(vx * vx + vz * vz)
    if lenU < 0.5 or lenV < 0.5 then return false, "BASELINES_TOO_SHORT" end
    local sinTheta = cross / (lenU * lenV)
    if cross <= 1.0 or sinTheta < 0.05 then return false, "COLLINEAR_GEOMETRY" end
    return true
end

function trilateration.selectOptimalNodes(projNodes, maxCount)
    if #projNodes < 3 then return nil, "FAIL_INSUFFICIENT" end
    local n1 = projNodes[1]
    local n2 = nil
    for i = 2, #projNodes do
        local d = math.sqrt((projNodes[i].x - n1.x)^2 + (projNodes[i].z - n1.z)^2)
        if d >= 0.5 then n2 = projNodes[i] break end
    end
    if not n2 then return nil, "FAIL_GEOMETRY" end
    local n3 = nil
    local n3Idx = nil
    for i = 2, #projNodes do
        if projNodes[i] ~= n2 and trilateration.checkGeometry(n1, n2, projNodes[i]) then
            n3 = projNodes[i]
            n3Idx = i
            break
        end
    end
    if not n3 then return nil, "FAIL_GEOMETRY" end
    local selected = { n1, n2, n3 }
    local limit = math.min(maxCount or 6, #projNodes)
    for i = 2, #projNodes do
        if #selected >= limit then break end
        if projNodes[i] ~= n2 and i ~= n3Idx then
            table.insert(selected, projNodes[i])
        end
    end
    return selected
end

function trilateration.solveLinearWLS(projNodes)
    local n1 = projNodes[1]
    local m11, m12, m22, y1, y2 = 0, 0, 0, 0, 0
    local rawW = {}
    local maxW = 1e-6
    for i = 2, #projNodes do
        local w = 1.0 / math.max(projNodes[i].r, 1.0)
        rawW[i] = w
        if w > maxW then maxW = w end
    end
    for i = 2, #projNodes do
        local node = projNodes[i]
        local a1 = 2 * (node.x - n1.x)
        local a2 = 2 * (node.z - n1.z)
        local b = (n1.r^2 - node.r^2) + (node.x^2 - n1.x^2) + (node.z^2 - n1.z^2)
        local nw = rawW[i] / maxW
        m11 = m11 + nw * a1 * a1
        m12 = m12 + nw * a1 * a2
        m22 = m22 + nw * a2 * a2
        y1 = y1 + nw * a1 * b
        y2 = y2 + nw * a2 * b
    end
    local det = m11 * m22 - m12 * m12
    if math.abs(det) < 1e-4 then return nil, nil, det end
    return (m22 * y1 - m12 * y2) / det, (-m12 * y1 + m11 * y2) / det, det
end

function trilateration.gaussNewtonStep(projNodes, x, z, lambda, alpha)
    local jtj11, jtj12, jtj22 = lambda, 0, lambda
    local jtr1, jtr2, sumSqRes = 0, 0, 0
    for _, n in ipairs(projNodes) do
        local dx = x - n.x
        local dz = z - n.z
        local rho = math.sqrt(dx * dx + dz * dz)
        local denom = math.max(rho, 1e-6)
        local j1, j2 = dx / denom, dz / denom
        local res = n.r - rho
        sumSqRes = sumSqRes + res * res
        jtj11 = jtj11 + j1 * j1
        jtj12 = jtj12 + j1 * j2
        jtj22 = jtj22 + j2 * j2
        jtr1 = jtr1 + j1 * res
        jtr2 = jtr2 + j2 * res
    end
    local det = jtj11 * jtj22 - jtj12 * jtj12
    if det <= 1e-8 then return nil, "SINGULAR_NORMAL_MATRIX" end
    local dxStep = (jtj22 * jtr1 - jtj12 * jtr2) / det
    local dzStep = (-jtj12 * jtr1 + jtj11 * jtr2) / det
    return {
        x = x + alpha * dxStep,
        z = z + alpha * dzStep,
        stepNorm = math.sqrt(dxStep * dxStep + dzStep * dzStep),
        rms = math.sqrt(sumSqRes / #projNodes),
    }
end

function trilateration.computeHDOP(projNodes, x, z)
    local h11, h12, h22 = 0, 0, 0
    for _, n in ipairs(projNodes) do
        local dx = x - n.x
        local dz = z - n.z
        local rho = math.sqrt(dx * dx + dz * dz)
        local denom = math.max(rho, 1e-6)
        local g1 = dx / denom
        local g2 = dz / denom
        h11 = h11 + g1 * g1
        h12 = h12 + g1 * g2
        h22 = h22 + g2 * g2
    end
    local det = h11 * h22 - h12 * h12
    if det <= 1e-6 then return 99.9 end
    return math.sqrt((h11 + h22) / det)
end

local function solveSubset(subset, swarmBBox)
    local x0, z0, detM = trilateration.solveLinearWLS(subset)
    if not x0 or math.abs(detM) < 1e-4 then return nil, "FAIL_GEOMETRY" end
    if swarmBBox then
        local pad = 500
        if x0 < swarmBBox.minX - pad or x0 > swarmBBox.maxX + pad
           or z0 < swarmBBox.minZ - pad or z0 > swarmBBox.maxZ + pad then
            return nil, "FAIL_GEOMETRY"
        end
    end
    local curX, curZ = x0, z0
    for _ = 1, 8 do
        local step = trilateration.gaussNewtonStep(subset, curX, curZ, 0.01, 0.8)
        if not step then break end
        curX, curZ = step.x, step.z
        if step.stepNorm < 0.01 then break end
    end
    local maxRes = 0
    local maxIdx = 1
    local sumSq = 0
    for i, n in ipairs(subset) do
        local rModel = math.sqrt((curX - n.x)^2 + (curZ - n.z)^2)
        local res = math.abs(n.r - rModel)
        sumSq = sumSq + res * res
        if res > maxRes then maxRes = res maxIdx = i end
    end
    local finalRMS = math.sqrt(sumSq / #subset)
    local hdop = trilateration.computeHDOP(subset, curX, curZ)
    return {
        x = curX, z = curZ,
        hdop = hdop, accuracy = finalRMS,
        maxRes = maxRes, maxIdx = maxIdx,
    }
end

function trilateration.solve(nodes, craftAlt, swarmBBox)
    if #nodes < 3 then return nil, "FAIL_INSUFFICIENT" end
    local proj = trilateration.projectHorizontal(nodes, craftAlt)
    local selected, selErr = trilateration.selectOptimalNodes(proj, 6)
    if not selected then return nil, selErr end
    local sol, solErr = solveSubset(selected, swarmBBox)
    if not sol then return nil, solErr end
    local looApplied = false
    if #selected >= 4 and sol.maxRes > 1.5 then
        local candidate = {}
        for idx, n in ipairs(selected) do
            if idx ~= sol.maxIdx then table.insert(candidate, n) end
        end
        if #candidate >= 3 then
            local looSol = solveSubset(candidate, swarmBBox)
            if looSol and looSol.accuracy < sol.accuracy then
                sol = looSol
                selected = candidate
                looApplied = true
            end
        end
    end
    local status = "FIX_OK"
    if sol.hdop > 5.0 or sol.accuracy > 1.5 then status = "FIX_DEGRADED" end
    local ids = {}
    for i, n in ipairs(selected) do ids[i] = n.id end
    return {
        x = sol.x, z = sol.z, status = status,
        hdop = sol.hdop, accuracy = sol.accuracy,
        nodeCount = #selected, selectedNodes = ids,
        looApplied = looApplied,
    }
end

return trilateration
