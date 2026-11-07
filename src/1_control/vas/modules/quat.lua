-- VAS 3D Unit Quaternion Math Module (VICD-Spec v1.1.0)
local quat = {}

function quat.new(w, x, y, z)
    return {
        w = tonumber(w) or 1.0,
        x = tonumber(x) or 0.0,
        y = tonumber(y) or 0.0,
        z = tonumber(z) or 0.0
    }
end

function quat.identity()
    return { w = 1.0, x = 0.0, y = 0.0, z = 0.0 }
end

function quat.norm_sq(q)
    local w, x, y, z = q.w or 1.0, q.x or 0.0, q.y or 0.0, q.z or 0.0
    return w * w + x * x + y * y + z * z
end

function quat.norm(q)
    return math.sqrt(quat.norm_sq(q))
end

function quat.normalize(q)
    local n = quat.norm(q)
    if n > 1e-9 then
        local inv = 1.0 / n
        return {
            w = (q.w or 1.0) * inv,
            x = (q.x or 0.0) * inv,
            y = (q.y or 0.0) * inv,
            z = (q.z or 0.0) * inv
        }
    end
    return quat.identity()
end

function quat.conjugate(q)
    return {
        w = q.w or 1.0,
        x = -(q.x or 0.0),
        y = -(q.y or 0.0),
        z = -(q.z or 0.0)
    }
end

function quat.multiply(a, b)
    local aw, ax, ay, az = a.w or 1.0, a.x or 0.0, a.y or 0.0, a.z or 0.0
    local bw, bx, by, bz = b.w or 1.0, b.x or 0.0, b.y or 0.0, b.z or 0.0
    return {
        w = aw * bw - ax * bx - ay * by - az * bz,
        x = aw * bx + ax * bw + ay * bz - az * by,
        y = aw * by - ax * bz + ay * bw + az * bx,
        z = aw * bz + ax * by - ay * bx + az * bw
    }
end

function quat.rotate_vector(q, v)
    local qn = quat.normalize(q)
    local qx, qy, qz = qn.x, qn.y, qn.z
    local vx, vy, vz = v.x or 0.0, v.y or 0.0, v.z or 0.0

    local tx = 2.0 * (qy * vz - qz * vy)
    local ty = 2.0 * (qz * vx - qx * vz)
    local tz = 2.0 * (qx * vy - qy * vx)

    local cx = qy * tz - qz * ty
    local cy = qz * tx - qx * tz
    local cz = qx * ty - qy * tx

    return {
        x = vx + qn.w * tx + cx,
        y = vy + qn.w * ty + cy,
        z = vz + qn.w * tz + cz
    }
end

function quat.error_quaternion(targetQ, measQ)
    local t = quat.normalize(targetQ)
    local mInv = quat.conjugate(quat.normalize(measQ))
    local err = quat.multiply(t, mInv)
    if err.w < 0.0 then
        return { w = -err.w, x = -err.x, y = -err.y, z = -err.z }
    end
    return err
end

function quat.from_euler(pitchDeg, rollDeg, yawDeg)
    local p = math.rad(tonumber(pitchDeg) or 0.0) * 0.5
    local r = math.rad(tonumber(rollDeg) or 0.0) * 0.5
    local y = math.rad(tonumber(yawDeg) or 0.0) * 0.5

    local cp, sp = math.cos(p), math.sin(p)
    local cr, sr = math.cos(r), math.sin(r)
    local cy, sy = math.cos(y), math.sin(y)

    local q = {
        w = cr * cp * cy + sr * sp * sy,
        x = sr * cp * cy - cr * sp * sy,
        y = cr * sp * cy + sr * cp * sy,
        z = cr * cp * sy - sr * sp * cy
    }
    return quat.normalize(q)
end

function quat.to_euler(q)
    local qn = quat.normalize(q)
    local w, x, y, z = qn.w, qn.x, qn.y, qn.z

    local sinp = 2.0 * (w * y - z * x)
    local pitchRad
    if math.abs(sinp) >= 1.0 then
        pitchRad = (sinp > 0) and (math.pi * 0.5) or (-math.pi * 0.5)
    else
        pitchRad = math.asin(sinp)
    end

    local rollRad = math.atan2(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y))
    local yawRad = math.atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))

    local yawDeg = (math.deg(yawRad) + 360.0) % 360.0
    return {
        pitch = math.deg(pitchRad),
        roll = math.deg(rollRad),
        yaw = yawDeg
    }
end

return quat
