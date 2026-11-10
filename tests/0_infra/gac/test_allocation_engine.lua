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

    it("allocates dedicatedCraftIds pad with first priority and falls back to public pad when occupied", function()
        local mixedPads = {
            {
                facilityId = "PAD_PUBLIC_NEAR",
                status = "FREE",
                maxSupportWeight = 30000.0,
                maxSupportRadius = 10.0,
                coordinates = { x = 10.0, y = 64.0, z = 0.0 },
                approachHeading = 180.0
            },
            {
                facilityId = "PAD_VIP_FAR",
                status = "FREE",
                maxSupportWeight = 30000.0,
                maxSupportRadius = 10.0,
                coordinates = { x = 180.0, y = 64.0, z = 0.0 },
                approachHeading = 180.0,
                dedicatedCraftIds = { "VIP_01", "VIP_02" }
            }
        }
        local vipReq = {
            aircraftId = "VIP_02",
            airframeType = "VECTORED_VTOL",
            craftWeight = 12000.0,
            craftRadius = 5.0,
            currentPos = { x = 0.0, y = 64.0, z = 0.0 }
        }
        local best1, err1 = allocation_engine.select_best_pad(mixedPads, vipReq, { speed = 2.0, direction = 180.0 })
        assert_not_nil(best1)
        assert_nil(err1)
        assert_eq(best1.facilityId, "PAD_VIP_FAR")

        -- When dedicated pad is OCCUPIED, VIP craft falls back to public pad
        mixedPads[2].status = "OCCUPIED"
        local best2, err2 = allocation_engine.select_best_pad(mixedPads, vipReq, { speed = 2.0, direction = 180.0 })
        assert_not_nil(best2)
        assert_nil(err2)
        assert_eq(best2.facilityId, "PAD_PUBLIC_NEAR")
    end)

    it("handles unauthorized preferredFacilityId: redirects to public pad if available, else returns FACILITY_DEDICATED", function()
        local padsWithPublic = {
            {
                facilityId = "PAD_DED_ONLY",
                status = "FREE",
                maxSupportWeight = 30000.0,
                maxSupportRadius = 10.0,
                coordinates = { x = 20.0, y = 64.0, z = 0.0 },
                dedicatedCraftIds = "VIP_01"
            },
            {
                facilityId = "PAD_PUB_01",
                status = "FREE",
                maxSupportWeight = 30000.0,
                maxSupportRadius = 10.0,
                coordinates = { x = 100.0, y = 64.0, z = 0.0 }
            }
        }
        local unauthReq = {
            aircraftId = "NORMAL_CRAFT",
            airframeType = "VECTORED_VTOL",
            craftWeight = 10000.0,
            craftRadius = 4.0,
            currentPos = { x = 0.0, y = 64.0, z = 0.0 },
            preferredFacilityId = "PAD_DED_ONLY"
        }
        local fallbackPad, errFallback = allocation_engine.select_best_pad(padsWithPublic, unauthReq, { speed = 0, direction = 0 })
        assert_not_nil(fallbackPad)
        assert_nil(errFallback)
        assert_eq(fallbackPad.facilityId, "PAD_PUB_01")

        -- When public pad is occupied, unauthorized preferredFacilityId must be rejected with FACILITY_DEDICATED
        padsWithPublic[2].status = "OCCUPIED"
        local deniedPad, errDenied = allocation_engine.select_best_pad(padsWithPublic, unauthReq, { speed = 0, direction = 0 })
        assert_nil(deniedPad)
        assert_eq(errDenied, "FACILITY_DEDICATED")
    end)

    it("enforces emergency commandeering only when no public pad is FREE", function()
        local sectorPads = {
            {
                facilityId = "PAD_DED_CLOSER",
                status = "FREE",
                maxSupportWeight = 30000.0,
                maxSupportRadius = 10.0,
                coordinates = { x = 10.0, y = 64.0, z = 0.0 },
                dedicatedCraftIds = "VIP_01"
            },
            {
                facilityId = "PAD_PUB_FARTHER",
                status = "FREE",
                maxSupportWeight = 30000.0,
                maxSupportRadius = 10.0,
                coordinates = { x = 150.0, y = 64.0, z = 0.0 }
            }
        }
        local emgReq = {
            aircraftId = "EMG_CRAFT",
            airframeType = "VECTORED_VTOL",
            craftWeight = 10000.0,
            craftRadius = 4.0,
            currentPos = { x = 0.0, y = 64.0, z = 0.0 },
            isEmergency = true
        }
        -- Public pad is FREE -> must NOT commandeer dedicated pad even though dedicated pad is closer
        local bestPub, errPub = allocation_engine.select_best_pad(sectorPads, emgReq, { speed = 0, direction = 0 })
        assert_not_nil(bestPub)
        assert_nil(errPub)
        assert_eq(bestPub.facilityId, "PAD_PUB_FARTHER")

        -- Public pad becomes OCCUPIED -> emergency craft commandeers dedicated pad as last resort
        sectorPads[2].status = "OCCUPIED"
        local bestDed, errDed = allocation_engine.select_best_pad(sectorPads, emgReq, { speed = 0, direction = 0 })
        assert_not_nil(bestDed)
        assert_nil(errDed)
        assert_eq(bestDed.facilityId, "PAD_DED_CLOSER")
    end)

    it("allows emergency commandeering of dedicated pad when only undersized or incompatible public pads are FREE", function()
        local mixedScalePads = {
            {
                facilityId = "PAD_PUB_TINY_DRONE",
                facilityType = "LANDING_PAD",
                status = "FREE",
                maxSupportWeight = 2000.0,
                maxSupportRadius = 3.0,
                coordinates = { x = 10.0, y = 64.0, z = 0.0 }
            },
            {
                facilityId = "PAD_DED_HEAVY",
                facilityType = "LANDING_PAD",
                status = "FREE",
                maxSupportWeight = 50000.0,
                maxSupportRadius = 15.0,
                coordinates = { x = 100.0, y = 64.0, z = 0.0 },
                dedicatedCraftIds = "VIP_HEAVY_01"
            }
        }
        local heavyEmgReq = {
            aircraftId = "EMG_HEAVY",
            airframeType = "VECTORED_VTOL",
            craftWeight = 35000.0,
            craftRadius = 8.0,
            currentPos = { x = 0.0, y = 64.0, z = 0.0 },
            isEmergency = true
        }
        local best, err = allocation_engine.select_best_pad(mixedScalePads, heavyEmgReq, { speed = 0, direction = 0 })
        assert_not_nil(best)
        assert_nil(err)
        assert_eq(best.facilityId, "PAD_DED_HEAVY")
    end)
end)
