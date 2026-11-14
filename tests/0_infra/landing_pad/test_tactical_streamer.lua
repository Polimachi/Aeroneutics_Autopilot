-- tests/0_infra/landing_pad/test_tactical_streamer.lua
local tactical_streamer = require("tactical_streamer")

describe("Landing pad tactical guidance packet streamer", function()
    local dummyCfg = {
        padId = "PAD_BRAVO_01",
        mode = "DYNAMIC",
        approachHeading = 180.0,
        safeDescentRate = 1.0,
        clearanceRadius = 5.0,
        channels = {
            tacticalChannel = 50211,
            sectorFacilityChannel = 50202
        }
    }

    it("builds MSG_FACILITY_STATIC_GUIDE packet according to ICD 3.2", function()
        local streamer = tactical_streamer.create(dummyCfg)
        local pos = { x = 1250.0, y = 65.0, z = -820.0 }
        local wind = { speed = 2.4, direction = 195.0 }
        local pkt = streamer:build_static_guide(10450, "AIRCRAFT_01", pos, wind, false, 1729850010000)

        assert_eq(pkt.ver, "1.9.5")
        assert_eq(pkt.domainId, "PAD_BRAVO_01")
        assert_eq(pkt.type, "MSG_FACILITY_STATIC_GUIDE")
        assert_eq(pkt.seq, 10450)
        assert_eq(pkt.time, 1729850010000)

        local p = pkt.payload
        assert_eq(p.facilityId, "PAD_BRAVO_01")
        assert_eq(p.facilityType, "LANDING_PAD")
        assert_eq(p.targetAircraft, "AIRCRAFT_01")
        assert_eq(p.touchdownPoint.x, 1250.0)
        assert_eq(p.touchdownPoint.y, 65.0)
        assert_eq(p.touchdownPoint.z, -820.0)
        assert_eq(p.attitude.pitch, 0.0)
        assert_eq(p.attitude.roll, 0.0)
        assert_eq(p.attitude.yaw, 180.0)
        assert_eq(p.approachDirection, "DOWNWARD")
        assert_eq(p.deckStatus, "STABLE")
        assert_true(p.landingPermitted)
        assert_eq(p.safeDescentRate, 1.0)
        assert_eq(p.clearanceRadius, 5.0)
        assert_eq(p.tiltAngleDeg, 0.0)
        assert_eq(p.heaveRateMps, 0.0)
        assert_nil(p.approachHeading)
        assert_nil(p.clearanceZoneRadius)
        assert_nil(p.surfaceWind)
        assert_false(p.abortAlert)
    end)

    it("builds MSG_FACILITY_DYNAMIC_GUIDE packet with deck stability flags (ICD 3.3)", function()
        local streamer = tactical_streamer.create(dummyCfg)
        local pos = { x = 840.25, y = 62.10, z = 1120.80 }
        local kin = {
            velocity = { vx = 6.20, vy = -0.15, vz = 1.10 },
            acceleration = { ax = 0.05, ay = 0.85, az = -0.02 },
            attitude = { pitch = 1.2, roll = -2.5, yaw = 85.0 },
            angularRates = { pitchRate = 0.4, rollRate = -0.8, yawRate = 0.05 }
        }
        local pkt = streamer:build_dynamic_guide(45100, "AIRCRAFT_01", pos, kin, "STABLE", true, 2.77, -0.15, false, 1729850020050)

        assert_eq(pkt.ver, "1.9.5")
        assert_eq(pkt.type, "MSG_FACILITY_DYNAMIC_GUIDE")
        local p = pkt.payload
        assert_eq(p.facilityId, "PAD_BRAVO_01")
        assert_eq(p.facilityType, "LANDING_PAD")
        assert_eq(p.targetAircraft, "AIRCRAFT_01")
        assert_eq(p.approachDirection, "DOWNWARD")
        assert_eq(p.velocity.vx, 6.20)
        assert_eq(p.velocity.vy, -0.15)
        assert_eq(p.attitude.pitch, 1.2)
        assert_eq(p.deckStatus, "STABLE")
        assert_true(p.landingPermitted)
        assert_eq(p.clearanceRadius, 5.0)
        assert_eq(p.safeDescentRate, 1.0)
        assert_near(p.tiltAngleDeg, 2.77, 1e-2)
        assert_near(p.heaveRateMps, -0.15, 1e-2)
        assert_false(p.abortAlert)
    end)

    it("builds MSG_ABORT_APPROACH packet (ICD 3.5.4)", function()
        local streamer = tactical_streamer.create(dummyCfg)
        local pkt = streamer:build_abort_approach(10455, "AIRCRAFT_01", "DECK_UNSTABLE", 100.0, 1729850022000)

        assert_eq(pkt.ver, "1.9.5")
        assert_eq(pkt.type, "MSG_ABORT_APPROACH")
        assert_eq(pkt.payload.facilityId, "PAD_BRAVO_01")
        assert_eq(pkt.payload.aircraftId, "AIRCRAFT_01")
        assert_eq(pkt.payload.reason, "DECK_UNSTABLE")
        assert_eq(pkt.payload.recommendedClimbAltitude, 100.0)
    end)

    it("builds MSG_ATC_SLOT_ACK and MSG_ATC_FACILITY_UPDATE packets (ICD 3.5.2 & 3.5.3)", function()
        local streamer = tactical_streamer.create(dummyCfg)
        local ack = streamer:build_slot_ack(10451, "AIRCRAFT_01", "ACCEPTED", nil, 1729850005100)
        assert_eq(ack.type, "MSG_ATC_SLOT_ACK")
        assert_eq(ack.payload.status, "ACCEPTED")
        assert_eq(ack.payload.tacticalChannel, 50211)

        local pos = { x = 840.25, y = 62.10, z = 1120.80 }
        local vel = { vx = 6.20, vy = -0.15, vz = 1.10 }
        local upd = streamer:build_facility_update(10452, "OCCUPIED", "AIRCRAFT_01", nil, pos, 85.0, vel, 1729850025100)
        assert_eq(upd.type, "MSG_ATC_FACILITY_UPDATE")
        assert_eq(upd.payload.status, "OCCUPIED")
        assert_eq(upd.payload.currentCraft, "AIRCRAFT_01")
        assert_eq(upd.payload.touchdownPoint.x, 840.25)
        assert_eq(upd.payload.heading, 85.0)
        assert_eq(upd.payload.velocity.vx, 6.20)

        local idleUpd = streamer:build_facility_update(10453, "IDLE", nil, nil)
        assert_eq(idleUpd.payload.status, "FREE")
        local appUpd = streamer:build_facility_update(10454, "APPROACH_DYNAMIC", "AIRCRAFT_01", nil)
        assert_eq(appUpd.payload.status, "RESERVED")
    end)
end)
