-- src/0_infra/landing_pad/modules/offset_transform.lua
-- 3D body-frame offset coordinate translation and platform yaw rotation

local offset_transform = {}

function offset_transform.calculate_pad_position(compPos, platformYaw, mountingYawOffset, bodyOffset)
    local cx = compPos and (compPos.x or 0.0) or 0.0
    local cy = compPos and (compPos.y or 0.0) or 0.0
    local cz = compPos and (compPos.z or 0.0) or 0.0

    local fwd = bodyOffset and (bodyOffset.forward or 0.0) or 0.0
    local right = bodyOffset and (bodyOffset.right or 0.0) or 0.0
    local up = bodyOffset and (bodyOffset.up or 0.0) or 0.0

    local pYaw = platformYaw or 0.0
    local mYaw = mountingYawOffset or 0.0
    local totalYawDeg = (pYaw + mYaw) % 360.0
    local totalYawRad = math.rad(totalYawDeg)

    local sinYaw = math.sin(totalYawRad)
    local cosYaw = math.cos(totalYawRad)

    -- In Minecraft coordinates:
    -- +X is East, +Z is South, +Y is Up.
    -- Yaw 0 is North (-Z), 90 is East (+X), 180 is South (+Z), 270 is West (-X)
    local padX = cx + (fwd * sinYaw) + (right * cosYaw)
    local padY = cy + up
    local padZ = cz - (fwd * cosYaw) + (right * sinYaw)

    return {
        x = padX,
        y = padY,
        z = padZ
    }
end

offset_transform.calculate_pad_coordinates = offset_transform.calculate_pad_position

return offset_transform
