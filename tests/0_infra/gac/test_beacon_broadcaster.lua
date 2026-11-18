-- tests/0_infra/gac/test_beacon_broadcaster.lua
local beacon_broadcaster = require("beacon_broadcaster")

describe("GAC aggregated beacon broadcaster", function()
    local cfg = {
        sectorId = "BASE_ALPHA_SECTOR_01",
        sectorName = "Alpha Base Central Vertiport",
        sectorType = "VERTIPORT",
        baseSecChannel = 50201,
        towerAtcChannel = 50001,
        beaconChannel = 50003,
        dispatchChannel = 50004
    }

    local mockInventory = {
        get_summary = function()
            return {
                totalLandingPads = 4,
                freeLandingPads = 3,
                totalRunways = 0,
                freeRunways = 0,
                maxSupportWeight = 40000.0,
                maxSupportRadius = 12.0
            }
        end
    }

    it("formats standard MSG_FACILITY_BEACON envelope and payload", function()
        local bc = beacon_broadcaster.create(cfg)
        local wind = { speed = 2.4, direction = 195.0 }
        local pkt = bc:build_sector_beacon(mockInventory, wind, "OPERATIONAL")
        
        assert_eq(pkt.ver, "1.9.5")
        assert_eq(pkt.type, "MSG_FACILITY_BEACON")
        assert_eq(pkt.payload.sectorId, "BASE_ALPHA_SECTOR_01")
        assert_eq(pkt.payload.gacChannel, 50201)
        assert_eq(pkt.payload.towerAtcChannel, 50001)
        assert_eq(pkt.payload.facilitiesSummary.totalLandingPads, 4)
        assert_eq(pkt.payload.facilitiesSummary.freeLandingPads, 3)
        assert_eq(pkt.payload.surfaceWind.speed, 2.4)
        assert_eq(pkt.payload.status, "OPERATIONAL")
    end)

    it("formats standard MSG_GAC_DISPATCH packet for directory announcement", function()
        local bc = beacon_broadcaster.create(cfg)
        local pkt = bc:build_dispatch_packet()
        assert_eq(pkt.ver, "1.9.5")
        assert_eq(pkt.type, "MSG_GAC_DISPATCH")
        assert_eq(pkt.payload.activeSectors[1].sectorId, "BASE_ALPHA_SECTOR_01")
        assert_eq(pkt.payload.activeSectors[1].gacChannel, 50201)
    end)

    it("rate-limits broadcast to strict 1Hz", function()
        local sentChannels = {}
        local mockModem = {
            transmit = function(ch, replyCh, payload)
                table.insert(sentChannels, ch)
            end
        }
        local bc = beacon_broadcaster.create(cfg)
        local wind = { speed = 2.0, direction = 180.0 }
        
        -- First call at t=10.0: should transmit
        local ok1 = bc:broadcast_1hz(mockModem, mockInventory, wind, "OPERATIONAL", 10.0)
        assert_true(ok1)
        assert_eq(#sentChannels, 2) -- 50003 and 50004
        
        -- Second call at t=10.5: should be rate-limited (skipped)
        local ok2 = bc:broadcast_1hz(mockModem, mockInventory, wind, "OPERATIONAL", 10.5)
        assert_false(ok2)
        assert_eq(#sentChannels, 2)
        
        -- Third call at t=11.1: should transmit
        local ok3 = bc:broadcast_1hz(mockModem, mockInventory, wind, "OPERATIONAL", 11.1)
        assert_true(ok3)
        assert_eq(#sentChannels, 4)
    end)

    it("includes facilities[] snapshot when inventory provides get_all_facilities", function()
        local facility_inventory = require("facility_inventory")
        local inv = facility_inventory.create({
            {
                facilityId = "PAD_PUB",
                type = "LANDING_PAD",
                status = "FREE",
                coordinates = { x = 100, y = 64, z = -200 },
                heading = 90.0,
                tacticalChannel = 50211,
            },
            {
                facilityId = "PAD_DED",
                type = "LANDING_PAD",
                status = "FREE",
                coordinates = { x = 150, y = 65, z = -250 },
                heading = 180.0,
                tacticalChannel = 50212,
                dedicatedCraftIds = { "AIRCRAFT_02" },
            },
            {
                facilityId = "RWY_01",
                type = "RUNWAY",
                status = "OCCUPIED",
                coordinates = { x = 300, y = 64, z = 0 },
                endPoint = { x = 600, y = 64, z = 0 },
                heading = 90.0,
                tacticalChannel = 50213,
            },
        })
        local bc = beacon_broadcaster.create(cfg)
        local pkt = bc:build_sector_beacon(inv, { speed = 1.0, direction = 0.0 }, "OPERATIONAL")
        assert_not_nil(pkt.payload.facilities)
        assert_eq(#pkt.payload.facilities, 3)

        local byId = {}
        for _, f in ipairs(pkt.payload.facilities) do
            byId[f.facilityId] = f
        end
        assert_eq(byId["PAD_PUB"].facilityType, "LANDING_PAD")
        assert_eq(byId["PAD_PUB"].status, "FREE")
        assert_eq(byId["PAD_PUB"].position.x, 100)
        assert_eq(byId["PAD_PUB"].tacticalChannel, 50211)
        assert_false(byId["PAD_PUB"].dedicated)
        assert_true(byId["PAD_DED"].dedicated)
        assert_eq(byId["RWY_01"].facilityType, "RUNWAY")
        assert_eq(byId["RWY_01"].endPoint.x, 600)
    end)

    it("includes explicit cfg.position or computes centroid fallback in MSG_FACILITY_BEACON", function()
        local facility_inventory = require("facility_inventory")
        local inv = facility_inventory.create({
            {
                facilityId = "PAD_A",
                type = "LANDING_PAD",
                status = "FREE",
                coordinates = { x = 100, y = 64, z = -200 },
                tacticalChannel = 50211,
            },
            {
                facilityId = "PAD_B",
                type = "LANDING_PAD",
                status = "FREE",
                coordinates = { x = 150, y = 65, z = -250 },
                tacticalChannel = 50212,
            },
        })

        local explicitCfg = {
            sectorId = "BASE_ALPHA_SECTOR_01",
            sectorName = "Alpha",
            sectorType = "VERTIPORT",
            baseSecChannel = 50201,
            towerAtcChannel = 50001,
            position = { x = 1275.0, y = 65.0, z = -810.0 },
        }
        local bcExplicit = beacon_broadcaster.create(explicitCfg)
        local pktExplicit = bcExplicit:build_sector_beacon(inv, { speed = 1.0, direction = 0.0 }, "OPERATIONAL")
        assert_not_nil(pktExplicit.payload.position)
        assert_eq(pktExplicit.payload.position.x, 1275.0)
        assert_eq(pktExplicit.payload.position.y, 65.0)
        assert_eq(pktExplicit.payload.position.z, -810.0)

        local bcCentroid = beacon_broadcaster.create(cfg)
        local pktCentroid = bcCentroid:build_sector_beacon(inv, { speed = 1.0, direction = 0.0 }, "OPERATIONAL")
        assert_not_nil(pktCentroid.payload.position)
        assert_eq(pktCentroid.payload.position.x, 125.0)
        assert_eq(pktCentroid.payload.position.y, 64.5)
        assert_eq(pktCentroid.payload.position.z, -225.0)
    end)
end)
