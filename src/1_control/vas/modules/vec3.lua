-- VAS 3D Vector Math Module (VICD-Spec v1.1.0)
local vec3 = {}

function vec3.new(x, y, z)
    return {
        x = tonumber(x) or 0.0,
        y = tonumber(y) or 0.0,
        z = tonumber(z) or 0.0
    }
end

function vec3.zero()
    return { x = 0.0, y = 0.0, z = 0.0 }
end

function vec3.add(a, b)
    return {
        x = (a.x or 0.0) + (b.x or 0.0),
        y = (a.y or 0.0) + (b.y or 0.0),
        z = (a.z or 0.0) + (b.z or 0.0)
    }
end

function vec3.sub(a, b)
    return {
        x = (a.x or 0.0) - (b.x or 0.0),
        y = (a.y or 0.0) - (b.y or 0.0),
        z = (a.z or 0.0) - (b.z or 0.0)
    }
end

function vec3.scale(v, s)
    local k = tonumber(s) or 0.0
    return {
        x = (v.x or 0.0) * k,
        y = (v.y or 0.0) * k,
        z = (v.z or 0.0) * k
    }
end

function vec3.dot(a, b)
    return (a.x or 0.0) * (b.x or 0.0) +
           (a.y or 0.0) * (b.y or 0.0) +
           (a.z or 0.0) * (b.z or 0.0)
end

function vec3.cross(a, b)
    local ax, ay, az = a.x or 0.0, a.y or 0.0, a.z or 0.0
    local bx, by, bz = b.x or 0.0, b.y or 0.0, b.z or 0.0
    return {
        x = ay * bz - az * by,
        y = az * bx - ax * bz,
        z = ax * by - ay * bx
    }
end

function vec3.length_sq(v)
    local x, y, z = v.x or 0.0, v.y or 0.0, v.z or 0.0
    return x * x + y * y + z * z
end

function vec3.length(v)
    return math.sqrt(vec3.length_sq(v))
end

function vec3.normalize(v)
    local len = vec3.length(v)
    if len > 1e-9 then
        local inv = 1.0 / len
        return {
            x = (v.x or 0.0) * inv,
            y = (v.y or 0.0) * inv,
            z = (v.z or 0.0) * inv
        }
    end
    return { x = 0.0, y = 0.0, z = 0.0 }
end

function vec3.distance(a, b)
    return vec3.length(vec3.sub(a, b))
end

return vec3
