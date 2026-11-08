-- tests/0_infra/gac/test_allocation_engine.lua
local allocation_engine = require("allocation_engine")

describe("GAC 2-stage multi-attribute pad allocation engine", function()
    local pads = {
        {
            facilityId = "PAD_SMALL",
            status = "FREE",
            maxSupportWeight = 10000.0,
            maxSupportRadius = 4.0,
            coordinates = { x = 100.0, y = 64.0, z = 0.0 },
            approachHeading = 180.0
        },
        {
            facilityId = "PAD_FAR_SIMILAR_WEIGHT",
            status = "FREE",
            maxSupportWeight = 11000.0,
            maxSupportRadius = 15.0,
            coordinates = { x = 200.0, y = 64.0, z = 0.0 },
            approachHeading = 180.0
        },
        {
            facilityId = "PAD_OCCUPIED",
            status = "OCCUPIED",
            maxSupportWeight = 50000.0,
            maxSupportRadius = 15.0,
            coordinates = { x = 50.0, y = 64.0, z = 0.0 },
            approachHeading = 180.0
        }
    }

    it("Stage 1: filters out occupied, overweight, or undersized pads", function()
        local valid = allocation_engine.filter_candidates(pads, 10500.0, 5.0)
        assert_eq(#valid, 1)
        assert_eq(valid[1].facilityId, "PAD_FAR_SIMILAR_WEIGHT")
    end)

    it("Short-circuits immediately if preferredFacilityId is valid and FREE", function()
        local craftReq = {
            aircraftId = "CRAFT_01",
            craftWeight = 8000.0,
            craftRadius = 3.0,
            currentPos = { x = 0.0, y = 100.0, z = 0.0 },
            preferredFacilityId = "PAD_SMALL"
        }
        local wind = { speed = 2.0, direction = 180.0 }
        local best, err = allocation_engine.select_best_pad(pads, craftReq, wind)
        assert_not_nil(best)
        assert_nil(err)
        assert_eq(best.facilityId, "PAD_SMALL")
    end)

    it("Stage 2: calculates score J(P_i) prioritizing headwind, distance, and weight margin", function()
        local craftReq = {
            aircraftId = "CRAFT_01",
            craftWeight = 8000.0,
            craftRadius = 3.0,
            currentPos = { x = 0.0, y = 64.0, z = 0.0 }
        }
        local wind = { speed = 3.0, direction = 180.0 }
        local best, err = allocation_engine.select_best_pad(pads, craftReq, wind)
        assert_not_nil(best)
        assert_nil(err)
        -- PAD_SMALL is at x=100 (score 0.3625), PAD_FAR_SIMILAR_WEIGHT is at x=200 (score 0.20625)
        assert_eq(best.facilityId, "PAD_SMALL")
    end)

    it("returns nil and SECTOR_ALL_OCCUPIED when no free pad exists", function()
        local occupiedOnly = {
            { facilityId = "P1", status = "OCCUPIED", maxSupportWeight = 50000, maxSupportRadius = 10, coordinates = {x=0,y=0,z=0} }
        }
        local craftReq = { aircraftId = "C1", craftWeight = 1000, craftRadius = 2, currentPos = {x=0,y=0,z=0} }
        local best, err = allocation_engine.select_best_pad(occupiedOnly, craftReq, { speed = 0, direction = 0 })
        assert_nil(best)
        assert_eq(err, "SECTOR_ALL_OCCUPIED")
    end)

    it("returns nil and OVERWEIGHT when all free pads exceed weight limit", function()
        local smallOnly = {
            { facilityId = "P1", status = "FREE", maxSupportWeight = 5000, maxSupportRadius = 10, coordinates = {x=0,y=0,z=0} }
        }
        local craftReq = { aircraftId = "C1", craftWeight = 20000, craftRadius = 2, currentPos = {x=0,y=0,z=0} }
        local best, err = allocation_engine.select_best_pad(smallOnly, craftReq, { speed = 0, direction = 0 })
        assert_nil(best)
        assert_eq(err, "OVERWEIGHT")
    end)
end)
