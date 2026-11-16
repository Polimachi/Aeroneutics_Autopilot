-- src/0_infra/runway/modules/offset_transform.lua
-- 3D body-frame threshold & end offset rotation transform for Runway

local offset_transform = {}

local function to_hull_frame(bodyOffset, mountingYawOffset)
    local fwd = bodyOffset and (bodyOffset.forward or 0.0) or 0.0
    local right = bodyOffset and (bodyOffset.right or 0.0) or 0.0
    local up = bodyOffset and (bodyOffset.up or 0.0) or 0.0
    local mRad = math.rad(mountingYawOffset or 0.0)
    local sinM, cosM = math.sin(mRad), math.cos(mRad)
    return fwd * cosM - right * sinM, fwd * sinM + right * cosM, up
end

local function rotate_body_to_world(surge, sway, up, attitude)
    local pitch = math.rad(attitude.pitch or 0.0)
    local roll = math.rad(attitude.roll or 0.0)
    local yaw = math.rad(attitude.yaw or 0.0)
    local sT, cT = math.sin(pitch), math.cos(pitch)
    local sP, cP = math.sin(roll), math.cos(roll)
    local sY, cY = math.sin(yaw), math.cos(yaw)
    local dx = surge * (cT * sY) + sway * (cP * cY + sP * sT * sY) + up * (sP * cY - cP * sT * sY)
    local dy = surge * sT + sway * (-sP * cT) + up * (cP * cT)
    local dz = surge * (-cT * cY) + sway * (cP * sY - sP * sT * cY) + up * (sP * sY + cP * sT * cY)
    return dx, dy, dz
end

local function resolve_attitude(attOrYaw)
    if type(attOrYaw) == "table" then return attOrYaw end
    return { pitch = 0.0, roll = 0.0, yaw = attOrYaw or 0.0 }
end

function offset_transform.calculate_point_position(compPos, attitudeOrYaw, mountingYawOffset, bodyOffset)
    local cx = compPos and (compPos.x or 0.0) or 0.0
    local cy = compPos and (compPos.y or 0.0) or 0.0
    local cz = compPos and (compPos.z or 0.0) or 0.0
    local surge, sway, up = to_hull_frame(bodyOffset, mountingYawOffset)
    local dx, dy, dz = rotate_body_to_world(surge, sway, up, resolve_attitude(attitudeOrYaw))
    return { x = cx + dx, y = cy + dy, z = cz + dz }
end

function offset_transform.calculate_runway_points(compPos, attitudeOrYaw, mountingYawOffset, touchdownOffset, endOffset)
    local td = offset_transform.calculate_point_position(compPos, attitudeOrYaw, mountingYawOffset, touchdownOffset)
    local ep = offset_transform.calculate_point_position(compPos, attitudeOrYaw, mountingYawOffset, endOffset)
    return td, ep
end

function offset_transform.calculate_point_velocity(compVel, attitude, angularRates, mountingYawOffset, bodyOffset)
    local vx = compVel and (compVel.vx or 0.0) or 0.0
    local vy = compVel and (compVel.vy or 0.0) or 0.0
    local vz = compVel and (compVel.vz or 0.0) or 0.0
    local rates = angularRates or {}
    local p, q, r = math.rad(rates.rollRate or 0.0), math.rad(rates.pitchRate or 0.0), math.rad(rates.yawRate or 0.0)
    local surge, sway, up = to_hull_frame(bodyOffset, mountingYawOffset)
    local vSurge = -q * up - r * sway
    local vSway = r * surge + p * up
    local vUp = q * surge - p * sway
    local dvx, dvy, dvz = rotate_body_to_world(vSurge, vSway, vUp, attitude or {})
    return { vx = vx + dvx, vy = vy + dvy, vz = vz + dvz }
end

return offset_transform
