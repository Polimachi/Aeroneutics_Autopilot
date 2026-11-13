-- tests/3_planning/amm/test_nav_engine.lua
local nav_engine = require("nav_engine")

describe("AMM nav_engine GPS+DR complementary filter, monotonic seq and epoch sync", function()
    it("synchronizes pos.y to onboard baro altitudeY and falls back to vy*dt when missing", function()
        local st = nav_engine.init({ navigation = { drComplementaryAlpha = 0.35, gpsTimeoutMs = 5000 } })
        nav_engine.integrate_dr(st, {
            dynamics = { altitudeY = 142.5, velocity = { vx = 10.0, vy = 0.0, vz = -5.0 } },
            attitude = { pitch = 1.0, roll = 0.0, heading = 90.0 },
        }, 0.05, 1000)
        assert_near(st.pos.y, 142.5, 1e-4)
        assert_near(st.pos.x, 0.5, 1e-4)
        assert_near(st.pos.z, -0.25, 1e-4)
        assert_true(st.navValid)

        nav_engine.integrate_dr(st, { velocity = { vx = 0.0, vy = 10.0, vz = 0.0 } }, 0.1, 1100)
        assert_near(st.pos.y, 143.5, 1e-4)
    end)

    it("builds TASK-122 compliant GPS request, enforces monotonic seq and increments posEpoch on FIX_OK", function()
        local st = nav_engine.init({
            system = { domainId = "AIRCRAFT_01" },
            channels = { baseChannel = 10000 },
            navigation = { drComplementaryAlpha = 0.35, kinematicGateLimitM = 8.0, gpsTimeoutMs = 5000 },
        })
        st.pos = { x = 10.0, y = 100.0, z = 20.0 }

        local ok, seq1, reqPkt = nav_engine.build_gps_request(st, 1000)
        assert_true(ok)
        assert_eq(seq1, 1)
        assert_eq(reqPkt.type, "MSG_GPS_REQUEST")
        assert_not_nil(reqPkt.time)
        assert_nil(reqPkt.timestamp)
        assert_eq(reqPkt.payload.replyChannel, 10005)
        assert_eq(reqPkt.payload.altitudeY, 100.0)
        assert_eq(reqPkt.payload.clientType, "AIRCRAFT")
        assert_eq(reqPkt.payload.clientSeq, 1)

        local epochBefore = st.posEpoch
        assert_true(nav_engine.filter_gps(st, {
            targetClient = "AIRCRAFT_01",
            clientSeq = 1,
            status = "FIX_OK",
            position = { x = 20.0, z = 30.0 },
            accuracy = 0.2,
            hdop = 1.0,
        }, 0.05, 1050))
        assert_eq(st.posEpoch, epochBefore + 1)
        assert_near(st.pos.x, 13.5, 1e-4) -- 0.65*10 + 0.35*20
        assert_near(st.pos.z, 23.5, 1e-4) -- 0.65*20 + 0.35*30
        assert_eq(st.pos.y, 100.0) -- Baro altitude preserved

        -- Replayed or future clientSeq rejected
        assert_false(nav_engine.filter_gps(st, {
            targetClient = "AIRCRAFT_01", clientSeq = 1, status = "FIX_OK", position = { x = 21, z = 31 }, hdop = 1.0,
        }, 0.05, 1100))
        assert_false(nav_engine.filter_gps(st, {
            targetClient = "AIRCRAFT_01", clientSeq = 99, status = "FIX_OK", position = { x = 21, z = 31 }, hdop = 1.0,
        }, 0.05, 1100))
    end)

    it("marks gpsStale after 5000ms and degrades alpha to 0.10, and accepts 3-streak snap", function()
        local st = nav_engine.init({
            system = { domainId = "AIRCRAFT_01" },
            navigation = { drComplementaryAlpha = 0.35, degradedAlpha = 0.10, gpsTimeoutMs = 5000, kinematicGateLimitM = 8.0 },
        })
        st.lastGpsFixMs = 1000
        assert_false(nav_engine.update_timeout(st, 5500))
        assert_true(nav_engine.update_timeout(st, 6100))
        assert_true(st.gpsStale)

        -- 3-streak outlier snap
        local _, s1 = nav_engine.should_query_gps(st, 6200)
        assert_false(nav_engine.filter_gps(st, { targetClient = "AIRCRAFT_01", clientSeq = s1, status = "FIX_OK", position = { x = 400, z = 0 }, hdop = 1.0 }, 0.05, 6200))
        local _, s2 = nav_engine.should_query_gps(st, 6300)
        assert_false(nav_engine.filter_gps(st, { targetClient = "AIRCRAFT_01", clientSeq = s2, status = "FIX_OK", position = { x = 401, z = 0 }, hdop = 1.0 }, 0.05, 6300))
        local _, s3 = nav_engine.should_query_gps(st, 6400)
        assert_true(nav_engine.filter_gps(st, { targetClient = "AIRCRAFT_01", clientSeq = s3, status = "FIX_OK", position = { x = 402, z = 0 }, hdop = 1.0 }, 0.05, 6400))
        assert_eq(st.lastGpsFixSeq, s3)
        assert_false(st.gpsStale)
    end)

    it("staggers initial GPS queries across 50ms slots based on computerId (cid=0 remains immediate)", function()
        local st0 = nav_engine.init({ system = { domainId = "AIRCRAFT_01", computerId = 0 }, navigation = { gpsRequestRateHz = 5 } })
        local st1 = nav_engine.init({ system = { domainId = "AIRCRAFT_02", computerId = 1 }, navigation = { gpsRequestRateHz = 5 } })
        local st2 = nav_engine.init({ system = { domainId = "AIRCRAFT_03", computerId = 2 }, navigation = { gpsRequestRateHz = 5 } })
        local st3 = nav_engine.init({ system = { domainId = "AIRCRAFT_04", computerId = 3 }, navigation = { gpsRequestRateHz = 5 } })

        -- At t=1000: only cid=0 fires immediately (offset 0ms)
        local q0, _ = nav_engine.should_query_gps(st0, 1000)
        local q1, _ = nav_engine.should_query_gps(st1, 1000)
        local q2, _ = nav_engine.should_query_gps(st2, 1000)
        local q3, _ = nav_engine.should_query_gps(st3, 1000)
        assert_true(q0)
        assert_false(q1)
        assert_false(q2)
        assert_false(q3)

        -- At t=1050: cid=1 fires (offset 50ms)
        assert_false(nav_engine.should_query_gps(st0, 1050))
        assert_true(nav_engine.should_query_gps(st1, 1050))
        assert_false(nav_engine.should_query_gps(st2, 1050))
        assert_false(nav_engine.should_query_gps(st3, 1050))

        -- At t=1100: cid=2 fires (offset 100ms)
        assert_true(nav_engine.should_query_gps(st2, 1100))
        assert_false(nav_engine.should_query_gps(st3, 1100))

        -- At t=1150: cid=3 fires (offset 150ms)
        assert_true(nav_engine.should_query_gps(st3, 1150))

        -- Steady state interval (200ms at 5Hz): st1 next fires at 1250
        assert_false(nav_engine.should_query_gps(st1, 1200))
        assert_true(nav_engine.should_query_gps(st1, 1250))
    end)
end)
