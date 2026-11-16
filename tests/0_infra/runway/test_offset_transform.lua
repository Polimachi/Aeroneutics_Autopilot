-- tests/0_infra/runway/test_offset_transform.lua
local offset_transform = require("modules.offset_transform")

describe("Runway 3D Offset Transform", function()
    it("rotates threshold and end body offsets from computer pose by heading yaw", function()
        local comp = { x = 100.0, y = 64.0, z = 200.0 }
        -- Facing East (yaw = 90 deg): hull +surge goes +X (sin 90 = 1, cos 90 = 0)
        local td, endPt = offset_transform.calculate_runway_points(
            comp,
            { pitch = 0.0, roll = 0.0, yaw = 90.0 },
            0.0,
            { forward = 10.0, right = 0.0, up = 2.0 },
            { forward = 110.0, right = 0.0, up = 2.0 }
        )
        assert_near(td.x, 110.0, 0.01)
        assert_near(td.y, 66.0, 0.01)
        assert_near(td.z, 200.0, 0.01)

        assert_near(endPt.x, 210.0, 0.01)
        assert_near(endPt.y, 66.0, 0.01)
        assert_near(endPt.z, 200.0, 0.01)
    end)

    it("computes linear point velocity including carrier angular rotation", function()
        local v = offset_transform.calculate_point_velocity(
            { vx = 5.0, vy = 0.0, vz = 0.0 },
            { pitch = 0.0, roll = 0.0, yaw = 0.0 },
            { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
            0.0,
            { forward = 20.0, right = 0.0, up = 0.0 }
        )
        assert_near(v.vx, 5.0, 0.001)
        assert_near(v.vy, 0.0, 0.001)
        assert_near(v.vz, 0.0, 0.001)
    end)
end)
