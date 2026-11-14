-- tests/0_infra/landing_pad/test_offset_transform.lua
local offset_transform = require("offset_transform")

describe("Landing pad 3D body offset coordinate transform", function()
    it("transforms body offset (fwd, right, up) correctly when facing North (yaw=0)", function()
        local compPos = { x = 100.0, y = 64.0, z = 200.0 }
        local bodyOffset = { forward = 10.0, right = 5.0, up = 1.5 }
        -- Facing North (yaw 0): forward is -Z, right is +X, up is +Y
        local padPos = offset_transform.calculate_pad_position(compPos, 0.0, 0.0, bodyOffset)
        assert_near(padPos.x, 105.0, 1e-4)
        assert_near(padPos.y, 65.5, 1e-4)
        assert_near(padPos.z, 190.0, 1e-4)
    end)

    it("transforms body offset correctly with platform yaw 90 (East) and mounting yaw 0", function()
        local compPos = { x = 100.0, y = 64.0, z = 200.0 }
        local bodyOffset = { forward = 10.0, right = 0.0, up = 0.0 }
        -- Facing East (yaw 90): forward is +X, right is +Z
        local padPos = offset_transform.calculate_pad_position(compPos, 90.0, 0.0, bodyOffset)
        assert_near(padPos.x, 110.0, 1e-4)
        assert_near(padPos.y, 64.0, 1e-4)
        assert_near(padPos.z, 200.0, 1e-4)
    end)

    it("incorporates mountingYawOffset (+90 deg starboard mounting)", function()
        local compPos = { x = 0.0, y = 64.0, z = 0.0 }
        local bodyOffset = { forward = 10.0, right = 0.0, up = 0.0 }
        -- Platform yaw 0 (North), Computer mounted at +90 (facing East). Total yaw = 90
        local padPos = offset_transform.calculate_pad_position(compPos, 0.0, 90.0, bodyOffset)
        assert_near(padPos.x, 10.0, 1e-4)
        assert_near(padPos.z, 0.0, 1e-4)
    end)

    it("applies 3D Euler pitch/roll/yaw rotation and omega x r velocity compensation", function()
        local compPos = { x = 0.0, y = 64.0, z = 0.0 }
        local bodyOffset = { forward = 10.0, right = 0.0, up = 0.0 }
        local attitude = { pitch = 90.0, roll = 0.0, yaw = 0.0 }
        local padPos = offset_transform.calculate_pad_position(compPos, attitude, 0.0, bodyOffset)
        assert_near(padPos.x, 0.0, 1e-4)
        assert_near(padPos.y, 74.0, 1e-4)
        assert_near(padPos.z, 0.0, 1e-4)

        local vel = offset_transform.calculate_pad_velocity(
            { vx = 1.0, vy = 0.0, vz = 0.0 },
            { pitch = 0.0, roll = 0.0, yaw = 0.0 },
            { pitchRate = 0.0, rollRate = 0.0, yawRate = math.deg(1.0) },
            0.0,
            bodyOffset
        )
        assert_near(vel.vx, 1.0 + 10.0, 1e-4)
        assert_near(vel.vy, 0.0, 1e-4)
        assert_near(vel.vz, 0.0, 1e-4)
    end)
end)
