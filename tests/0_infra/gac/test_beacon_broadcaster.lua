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
end)
