-- Profile exporter and synchronization module for Alignment
local profile_exporter = {}

local DEFAULT_AXES = { "surge", "sway", "heave", "pitch", "roll", "yaw" }

local function serialize_json_val(val)
    local t = type(val)
    if t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "table" then
        local is_arr = (#val > 0)
        local parts = {}
        if is_arr then
            for i = 1, #val do
                parts[#parts + 1] = serialize_json_val(val[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(val) do
                parts[#parts + 1] = string.format("%q:%s", tostring(k), serialize_json_val(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

function profile_exporter.serialize_profile(profile_data)
    if textutils and textutils.serializeJSON then
        return textutils.serializeJSON(profile_data)
    end
    return serialize_json_val(profile_data)
end

function profile_exporter.build_sync_packet(domain_id, seq, profile_data)
    return {
        ver = "1.9.5",
        domainId = domain_id,
        seq = seq or 1,
        type = "MSG_PROFILE_SYNC",
        time = (os and os.epoch and os.epoch("utc")) or 0,
        payload = profile_data or {}
    }
end

function profile_exporter.validate_ack(ack_pkt, expected_profile_id)
    if not ack_pkt or type(ack_pkt) ~= "table" then
        return false, "NIL_OR_NON_TABLE_PACKET"
    end
    if ack_pkt.type ~= "MSG_CALIB_ACK" then
        return false, "UNEXPECTED_PACKET_TYPE"
    end
    local p = ack_pkt.payload
    if not p or type(p) ~= "table" then
        return false, "MISSING_PAYLOAD"
    end
    if expected_profile_id and p.profileId ~= expected_profile_id then
        return false, "PROFILE_ID_MISMATCH"
    end
    if p.status ~= "ACCEPTED" then
        return false, p.status or "NOT_ACCEPTED"
    end
    return true, "ACCEPTED"
end

function profile_exporter.mat_transpose(A)
    local rows = #A
    local cols = #A[1]
    local AT = {}
    for j = 1, cols do
        AT[j] = {}
        for i = 1, rows do
            AT[j][i] = A[i][j]
        end
    end
    return AT
end

function profile_exporter.mat_mult(A, B)
    local rowsA = #A
    local colsA = #A[1]
    local rowsB = #B
    local colsB = #B[1]
    assert(colsA == rowsB, string.format("Matrix dim mismatch: colsA=%d, rowsB=%d", colsA, rowsB))
    local C = {}
    for i = 1, rowsA do
        C[i] = {}
        for j = 1, colsB do
            local sum = 0.0
            for k = 1, colsA do
                sum = sum + A[i][k] * B[k][j]
            end
            C[i][j] = sum
        end
    end
    return C
end

function profile_exporter.invert_matrix(M, eps)
    eps = eps or 1e-9
    local n = #M
    if n == 0 or #M[1] ~= n then
        return nil, "MATRIX_NOT_SQUARE"
    end

    -- Build augmented matrix [M | I]
    local A = {}
    for i = 1, n do
        A[i] = {}
        for j = 1, n do
            A[i][j] = tonumber(M[i][j]) or 0.0
        end
        for j = 1, n do
            A[i][n + j] = (i == j) and 1.0 or 0.0
        end
    end

    local totalCols = 2 * n

    for k = 1, n do
        -- Partial pivoting: find maximum pivot in column k, row >= k
        local maxVal = math.abs(A[k][k])
        local pivotRow = k
        for p = k + 1, n do
            local val = math.abs(A[p][k])
            if val > maxVal then
                maxVal = val
                pivotRow = p
            end
        end

        if maxVal < eps then
            return nil, "SINGULAR_MATRIX"
        end

        -- Swap pivotRow and k if needed
        if pivotRow ~= k then
            A[k], A[pivotRow] = A[pivotRow], A[k]
        end

        -- Normalize pivot row k
        local pivotVal = A[k][k]
        for j = 1, totalCols do
            A[k][j] = A[k][j] / pivotVal
        end

        -- Eliminate column k from all other rows
        for i = 1, n do
            if i ~= k then
                local factor = A[i][k]
                if math.abs(factor) > 1e-15 then
                    for j = 1, totalCols do
                        A[i][j] = A[i][j] - factor * A[k][j]
                    end
                end
            end
        end
    end

    -- Extract inverse from right half of A
    local inv = {}
    for i = 1, n do
        inv[i] = {}
        for j = 1, n do
            inv[i][j] = A[i][n + j]
        end
    end

    return inv
end

function profile_exporter.compute_pseudo_inverse(B, eps)
    if not B or type(B) ~= "table" or #B == 0 or not B[1] then
        return nil, "INVALID_MATRIX"
    end
    local rows = #B
    local cols = #B[1]
    if rows > cols then
        return nil, "OVERDETERMINED_NOT_SUPPORTED"
    end

    -- 1. BT = transpose(B) (cols x rows)
    local BT = profile_exporter.mat_transpose(B)

    -- 2. BBT = B * BT (rows x rows)
    local BBT = profile_exporter.mat_mult(B, BT)

    -- 3. Inv_BBT = invert_matrix(BBT)
    local inv_BBT, err = profile_exporter.invert_matrix(BBT, eps)
    if not inv_BBT then
        return nil, err or "SINGULAR_MATRIX"
    end

    -- 4. B_dagger = BT * inv_BBT (cols x rows)
    local B_dagger = profile_exporter.mat_mult(BT, inv_BBT)
    return B_dagger
end

function profile_exporter.assemble_control_matrix(vectorSlopesByGroup, groupOrder, axesOrder)
    local axes = axesOrder or DEFAULT_AXES
    local order = groupOrder
    if not order then
        order = {}
        for g, _ in pairs(vectorSlopesByGroup or {}) do
            table.insert(order, g)
        end
        table.sort(order)
    end

    local B = {}
    for r = 1, #axes do
        B[r] = {}
    end

    for _, gid in ipairs(order) do
        local slopes = vectorSlopesByGroup[gid] or {}
        local dT = slopes.dThrust or {}
        local dX = slopes.dGimbalX or {}
        local dY = slopes.dGimbalY or {}

        for r, axis in ipairs(axes) do
            table.insert(B[r], dT[axis] or 0.0)
            table.insert(B[r], dX[axis] or 0.0)
            table.insert(B[r], dY[axis] or 0.0)
        end
    end

    return B
end

return profile_exporter
