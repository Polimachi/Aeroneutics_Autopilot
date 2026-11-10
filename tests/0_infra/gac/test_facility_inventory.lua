-- tests/0_infra/gac/test_facility_inventory.lua
local facility_inventory = require("facility_inventory")

describe("GAC facility swarm inventory manager", function()
    local samplePads = {
        {
            facilityId = "PAD_01",
            type = "LANDING_PAD",
            tacticalChannel = 50211,
            maxSupportWeight = 40000.0,
            maxSupportRadius = 12.0,
            coordinates = { x = 1250.0, y = 65.0, z = -820.0 },
            status = "FREE",
            mobility = "STATIC"
        },
        {
            facilityId = "PAD_02",
            type = "LANDING_PAD",
            tacticalChannel = 50212,
            maxSupportWeight = 20000.0,
            maxSupportRadius = 6.0,
            coordinates = { x = 1300.0, y = 65.0, z = -800.0 },
            status = "FREE",
            mobility = "STATIC"
        }
    }

    it("initializes inventory and queries free pads and summary", function()
        local inv = facility_inventory.create(samplePads)
        assert_eq(#inv:get_all_facilities(), 2)
        local freePads = inv:get_free_pads()
        assert_eq(#freePads, 2)
        
        local summary = inv:get_summary()
        assert_eq(summary.totalLandingPads, 2)
        assert_eq(summary.freeLandingPads, 2)
        assert_eq(summary.maxSupportWeight, 40000.0)
        assert_eq(summary.maxSupportRadius, 12.0)
    end)

    it("updates status and reflects in free pads list", function()
        local inv = facility_inventory.create(samplePads)
        local ok, err = inv:update_status("PAD_01", "OCCUPIED", "CRAFT_01")
        assert_true(ok)
        assert_nil(err)
        
        local fac = inv:get_facility("PAD_01")
        assert_eq(fac.status, "OCCUPIED")
        assert_eq(fac.currentCraft, "CRAFT_01")
        
        local freePads = inv:get_free_pads()
        assert_eq(#freePads, 1)
        assert_eq(freePads[1].facilityId, "PAD_02")
    end)

    it("toggles emergency lockdown and overrides availability", function()
        local inv = facility_inventory.create(samplePads)
        assert_false(inv:is_emergency_lockdown())
        
        inv:set_emergency_lockdown(true)
        assert_true(inv:is_emergency_lockdown())
        assert_eq(#inv:get_free_pads(), 0)
        
        inv:set_emergency_lockdown(false)
        assert_false(inv:is_emergency_lockdown())
        assert_eq(#inv:get_free_pads(), 2)
    end)

    it("adds and removes facilities dynamically", function()
        local inv = facility_inventory.create(samplePads)
        local newFac = {
            facilityId = "PAD_03",
            type = "LANDING_PAD",
            tacticalChannel = 50213,
            maxSupportWeight = 15000.0,
            maxSupportRadius = 5.0,
            coordinates = { x = 1400.0, y = 65.0, z = -800.0 },
            status = "FREE"
        }
        local okAdd = inv:add_facility(newFac)
        assert_true(okAdd)
        assert_eq(#inv:get_all_facilities(), 3)
        
        local okRem = inv:remove_facility("PAD_03")
        assert_true(okRem)
        assert_eq(#inv:get_all_facilities(), 2)
    end)

    it("updates dynamic facility telemetry coordinates and velocity", function()
        local inv = facility_inventory.create(samplePads)
        local ok = inv:update_dynamic_telemetry("PAD_01", { x = 1260.0, y = 66.0, z = -815.0 }, 90.0, { vx = 1.0, vy = 0.0, vz = 0.0 })
        assert_true(ok)
        local fac = inv:get_facility("PAD_01")
        assert_eq(fac.coordinates.x, 1260.0)
        assert_eq(fac.heading, 90.0)
        assert_eq(fac.velocity.vx, 1.0)
    end)

    it("excludes dedicated pads and runways from freeLandingPads and freeRunways in summary", function()
        local mixedFacilities = {
            {
                facilityId = "PAD_PUB_01",
                type = "LANDING_PAD",
                status = "FREE",
                maxSupportWeight = 30000.0,
                maxSupportRadius = 10.0
            },
            {
                facilityId = "PAD_DED_VIP",
                type = "LANDING_PAD",
                status = "FREE",
                maxSupportWeight = 50000.0,
                maxSupportRadius = 15.0,
                dedicatedCraftIds = { "VIP_CRAFT_01" }
            },
            {
                facilityId = "RWY_DED_01",
                type = "RUNWAY",
                status = "FREE",
                dedicatedAirframeTypes = "FIXED_WING"
            }
        }
        local inv = facility_inventory.create(mixedFacilities)
        assert_false(inv:is_dedicated("PAD_PUB_01"))
        assert_true(inv:is_dedicated("PAD_DED_VIP"))
        assert_true(inv:is_dedicated("RWY_DED_01"))

        local summary = inv:get_summary()
        assert_eq(summary.totalLandingPads, 2)
        assert_eq(summary.freeLandingPads, 1)
        assert_eq(summary.totalRunways, 1)
        assert_eq(summary.freeRunways, 0)
        assert_eq(summary.maxSupportWeight, 50000.0)
        assert_eq(summary.maxSupportRadius, 15.0)
    end)

    it("updates dedicated attributes dynamically on an existing facility", function()
        local inv = facility_inventory.create(samplePads)
        assert_false(inv:is_dedicated("PAD_02"))

        local ok, err = inv:update_dedicated("PAD_02", { "DRONE_01" }, "QUADROTOR")
        assert_true(ok)
        assert_nil(err)
        assert_true(inv:is_dedicated("PAD_02"))
        assert_eq(inv:get_summary().freeLandingPads, 1)

        local okClear = inv:update_dedicated("PAD_02", nil, nil)
        assert_true(okClear)
        assert_false(inv:is_dedicated("PAD_02"))
        assert_eq(inv:get_summary().freeLandingPads, 2)
    end)
end)
