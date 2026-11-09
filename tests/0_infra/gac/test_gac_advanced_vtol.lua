-- tests/0_infra/gac/test_gac_advanced_vtol.lua
local allocation_engine = require("allocation_engine")

describe("GAC and Landing Pad compatibility for ADVANCED_VTOL", function()
    describe("Facility compatibility checks", function()
        it("identifies ADVANCED_VTOL as compatible with LANDING_PAD and DOCKING_ARM", function()
            assert_true(allocation_engine.is_facility_compatible("LANDING_PAD", "ADVANCED_VTOL"))
            assert_true(allocation_engine.is_facility_compatible("DOCKING_ARM", "ADVANCED_VTOL"))
            assert_false(allocation_engine.is_facility_compatible("RUNWAY", "ADVANCED_VTOL"))
        end)

        it("maintains compatibility matrix for other airframes", function()
            assert_true(allocation_engine.is_facility_compatible("LANDING_PAD", "VECTORED_VTOL"))
            assert_true(allocation_engine.is_facility_compatible("DOCKING_ARM", "VECTORED_VTOL"))
            assert_false(allocation_engine.is_facility_compatible("RUNWAY", "VECTORED_VTOL"))

            assert_false(allocation_engine.is_facility_compatible("LANDING_PAD", "FIXED_WING"))
            assert_false(allocation_engine.is_facility_compatible("DOCKING_ARM", "FIXED_WING"))
            assert_true(allocation_engine.is_facility_compatible("RUNWAY", "FIXED_WING"))
        end)
    end)

    describe("Dedicated facility matching with dedicatedAirframeTypes", function()
        local dedicatedPad = {
            facilityId = "PAD_DEDICATED_ADV",
            status = "FREE",
            maxSupportWeight = 20000.0,
            maxSupportRadius = 10.0,
            coordinates = { x = 100.0, y = 64.0, z = 0.0 },
            approachHeading = 180.0,
            facilityType = "LANDING_PAD",
            dedicatedAirframeTypes = { "ADVANCED_VTOL" },
        }

        local publicPad = {
            facilityId = "PAD_PUBLIC",
            status = "FREE",
            maxSupportWeight = 20000.0,
            maxSupportRadius = 10.0,
            coordinates = { x = 200.0, y = 64.0, z = 0.0 },
            approachHeading = 180.0,
            facilityType = "LANDING_PAD",
        }

        local dedicatedArm = {
            facilityId = "ARM_DEDICATED_ADV",
            status = "FREE",
            maxSupportWeight = 20000.0,
            maxSupportRadius = 10.0,
            coordinates = { x = 150.0, y = 80.0, z = 0.0 },
            facilityType = "DOCKING_ARM",
            dedicatedAirframeTypes = { "ADVANCED_VTOL" },
        }

        it("permits ADVANCED_VTOL for dedicated facility with dedicatedAirframeTypes table", function()
            local craftReq = {
                aircraftId = "ADV_CRAFT_01",
                airframeType = "ADVANCED_VTOL",
                craftWeight = 10000.0,
                craftRadius = 5.0,
            }
            assert_true(allocation_engine.isEligible(dedicatedPad, craftReq))
            assert_true(allocation_engine.isEligible(dedicatedArm, craftReq))
        end)

        it("rejects non-matching airframes for dedicated facility", function()
            local vecReq = {
                aircraftId = "VEC_CRAFT_01",
                airframeType = "VECTORED_VTOL",
                craftWeight = 10000.0,
                craftRadius = 5.0,
            }
            assert_false(allocation_engine.isEligible(dedicatedPad, vecReq))
            assert_false(allocation_engine.isEligible(dedicatedArm, vecReq))
        end)

        it("select_best_pad prioritizes dedicated facility for ADVANCED_VTOL", function()
            local facilities = {
                PAD_DEDICATED_ADV = dedicatedPad,
                PAD_PUBLIC = publicPad,
            }
            local craftReq = {
                aircraftId = "ADV_CRAFT_01",
                airframeType = "ADVANCED_VTOL",
                craftWeight = 10000.0,
                craftRadius = 5.0,
                currentPos = { x = 200.0, y = 64.0, z = 0.0 },
            }
            local wind = { speed = 0.0, direction = 180.0 }
            local best, err = allocation_engine.select_best_pad(facilities, craftReq, wind)
            assert_not_nil(best)
            assert_nil(err)
            assert_eq(best.facilityId, "PAD_DEDICATED_ADV")
        end)
    end)
end)
