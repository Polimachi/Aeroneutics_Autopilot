-- src/0_infra/landing_pad/modules/offset_transform.lua
-- 3D body-frame offset coordinate translation and platform 3D Euler rotation

local offset_transform = {}

local function to_hull_frame(bodyOffset, mountingYawOffset)
    local fwd = bodyOffset and (bodyOffset.forward or 0.0) or 0.0
    local right = bodyOffset and (bodyOffset.right or 0.0) or 0.0
    local up = bodyOffset and (bodyOffset.up or 0.0) or 0.0

    local mRad = math.rad(mountingYawOffset or 0.0)
    local sinM = math.sin(mRad)
    local cosM = math.cos(mRad)

    local surge = fwd * cosM - right * sinM
    local sway = fwd * sinM + right * cosM
    return surge, sway, up
end

local function rotate_body_to_world(surge, sway, up, attitude)
    local pitch = math.rad(attitude.pitch or 0.0)
    local roll = math.rad(attitude.roll or 0.0)
    local yaw = math.rad(attitude.yaw or 0.0)

    local sT, cT = math.sin(pitch), math.cos(pitch)
    local sP, cP = math.sin(roll), math.cos(roll)
    local sY, cY = math.sin(yaw), math.cos(yaw)

    local dx = surge * (cT * sY)
             + sway * (cP * cY + sP * sT * sY)
             + up * (sP * cY - cP * sT * sY)
    local dy = surge * sT
             + sway * (-sP * cT)
             + up * (cP * cT)
    local dz = surge * (-cT * cY)
             + sway * (cP * sY - sP * sT * cY)
             + up * (sP * sY + cP * sT * cY)
    return dx, dy, dz
end

function offset_transform.calculate_pad_position(compPos, platformAttitudeOrYaw, mountingYawOffset, bodyOffset)
    local cx = compPos and (compPos.x or 0.0) or 0.0
    local cy = compPos and (compPos.y or 0.0) or 0.0
    local cz = compPos and (compPos.z or 0.0) or 0.0

    local attitude
    if type(platformAttitudeOrYaw) == "table" then
        attitude = platformAttitudeOrYaw
    else
        attitude = { pitch = 0.0, roll = 0.0, yaw = platformAttitudeOrYaw or 0.0 }
    end

    local surge, sway, up = to_hull_frame(bodyOffset, mountingYawOffset)
    local dx, dy, dz = rotate_body_to_world(surge, sway, up, attitude)

    return {
        x = cx + dx,
        y = cy + dy,
        z = cz + dz
    }
end

function offset_transform.calculate_pad_velocity(compVel, attitude, angularRates, mountingYawOffset, bodyOffset)
    local vx = compVel and (compVel.vx or 0.0) or 0.0
    local vy = compVel and (compVel.vy or 0.0) or 0.0
    local vz = compVel and (compVel.vz or 0.0) or 0.0

    local rates = angularRates or {}
    local p = math.rad(rates.rollRate or 0.0)
    local q = math.rad(rates.pitchRate or 0.0)
    local r = math.rad(rates.yawRate or 0.0)

    local surge, sway, up = to_hull_frame(bodyOffset, mountingYawOffset)
    -- omega x delta_s in hull frame (surge, sway, up)
    local vSurge = -q * up - r * sway
    local vSway = r * surge + p * up
    local vUp = q * surge - p * sway

    local dvx, dvy, dvz = rotate_body_to_world(vSurge, vSway, vUp, attitude or {})
    return {
        vx = vx + dvx,
        vy = vy + dvy,
        vz = vz + dvz
    }
end

offset_transform.calculate_pad_coordinates = offset_transform.calculate_pad_position

return offset_transform
