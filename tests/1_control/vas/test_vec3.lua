-- Unit test suite for VAS 3D Vector Math (vec3.lua)
local vec3 = require("vec3")

describe("vas vec3 math primitives", function()
    it("constructs new and zero vectors", function()
        local z = vec3.zero()
        assert_near(z.x, 0.0, 1e-9)
        assert_near(z.y, 0.0, 1e-9)
        assert_near(z.z, 0.0, 1e-9)

        local v = vec3.new(1.5, -2.5, 3.0)
        assert_near(v.x, 1.5, 1e-9)
        assert_near(v.y, -2.5, 1e-9)
        assert_near(v.z, 3.0, 1e-9)
    end)

    it("computes add, sub, scale, and distance", function()
        local a = vec3.new(1.0, 2.0, 3.0)
        local b = vec3.new(4.0, -2.0, 3.0)

        local sum = vec3.add(a, b)
        assert_near(sum.x, 5.0, 1e-9)
        assert_near(sum.y, 0.0, 1e-9)
        assert_near(sum.z, 6.0, 1e-9)

        local diff = vec3.sub(b, a)
        assert_near(diff.x, 3.0, 1e-9)
        assert_near(diff.y, -4.0, 1e-9)
        assert_near(diff.z, 0.0, 1e-9)

        local scaled = vec3.scale(a, 2.0)
        assert_near(scaled.x, 2.0, 1e-9)
        assert_near(scaled.y, 4.0, 1e-9)
        assert_near(scaled.z, 6.0, 1e-9)

        assert_near(vec3.distance(a, b), 5.0, 1e-6)
    end)

    it("computes dot, cross, length, and safe normalize", function()
        local x = vec3.new(1.0, 0.0, 0.0)
        local y = vec3.new(0.0, 1.0, 0.0)
        assert_near(vec3.dot(x, y), 0.0, 1e-9)

        local z = vec3.cross(x, y)
        assert_near(z.x, 0.0, 1e-9)
        assert_near(z.y, 0.0, 1e-9)
        assert_near(z.z, 1.0, 1e-9)

        local v = vec3.new(0.0, 3.0, 4.0)
        assert_near(vec3.length_sq(v), 25.0, 1e-9)
        assert_near(vec3.length(v), 5.0, 1e-9)

        local n = vec3.normalize(v)
        assert_near(n.x, 0.0, 1e-6)
        assert_near(n.y, 0.6, 1e-6)
        assert_near(n.z, 0.8, 1e-6)

        local nz = vec3.normalize(vec3.zero())
        assert_near(nz.x, 0.0, 1e-9)
        assert_near(nz.y, 0.0, 1e-9)
        assert_near(nz.z, 0.0, 1e-9)
    end)
end)
