-- Unit test suite for 0_infra/gps
local storage_hal = require("storage_hal")
local trilateration = require("trilateration")

describe("gps storage HAL atomic writes and error handling", function()
    it("writes atomically and reads back JSON in ephemeral CraftOS filesystem", function()
        local test_file = sdk.temp_path("gps_nodes.json")
        local payload = {
            networkId = "GPS_NET_ALPHA",
            nodes = {
                { id = 1, x = 0, y = 64, z = 0 },
                { id = 2, x = 100, y = 64, z = 0 }
            }
        }

        local okWrite, errWrite = storage_hal.writeJsonAtomic(test_file, payload)
        assert_true(okWrite, errWrite)

        local data, errRead = storage_hal.readJson(test_file)
        assert_not_nil(data)
        assert_eq(errRead, nil)
        assert_eq(data.networkId, "GPS_NET_ALPHA")
        assert_eq(#data.nodes, 2)
        assert_eq(data.nodes[1].x, 0)
    end)

    it("returns FILE_NOT_FOUND error on non-existent path", function()
        local missing, err = storage_hal.readJson("/non_existent_path_xyz.json")
        assert_nil(missing)
        assert_eq(err, "FILE_NOT_FOUND")
    end)
end)

describe("gps trilateration numerical solver", function()
    it("projects horizontal distances and solves craft position accurately", function()
        -- True craft coordinates: (x = 30.0, y = 80.0, z = -20.0)
        local craftX, craftY, craftZ = 30.0, 80.0, -20.0

        local anchors = {
            { id = "N1", x = 0.0, y = 64.0, z = 0.0 },
            { id = "N2", x = 100.0, y = 64.0, z = 0.0 },
            { id = "N3", x = 0.0, y = 64.0, z = -100.0 },
            { id = "N4", x = 100.0, y = 64.0, z = -100.0 }
        }

        local nodes = {}
        for idx, anc in ipairs(anchors) do
            local dx = anc.x - craftX
            local dy = anc.y - craftY
            local dz = anc.z - craftZ
            local dist3d = math.sqrt(dx * dx + dy * dy + dz * dz)
            nodes[idx] = {
                id = anc.id,
                x = anc.x,
                y = anc.y,
                z = anc.z,
                distance = dist3d
            }
        end

        local projected = trilateration.projectHorizontal(nodes, craftY)
        assert_eq(#projected, 4)

        local optimal, errGeom = trilateration.selectOptimalNodes(projected, 4)
        assert_not_nil(optimal, errGeom)
        assert_true(#optimal >= 3)

        local solvedX, solvedZ, det = trilateration.solveLinearWLS(optimal)
        assert_not_nil(solvedX)
        assert_not_nil(solvedZ)
        assert_true(math.abs(det) > 1e-4)

        assert_near(solvedX, craftX, 0.05, "solved X should match true craft X")
        assert_near(solvedZ, craftZ, 0.05, "solved Z should match true craft Z")
    end)
end)
