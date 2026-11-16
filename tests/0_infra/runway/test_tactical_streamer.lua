-- tests/0_infra/runway/test_tactical_streamer.lua
local tactical_streamer = require("modules.tactical_streamer")

describe("Runway Tactical Guide & GAC Backbone Encoder", function()
    local cfg = {
        facilityId = "RWY_ALPHA_09L",
        sectorId = 1,
        runwayIndex = 1,
        mobility = "DYNAMIC",
        glideSlopeAngle = 3.5,
        touchdownZoneLength = 80.0,
        approachHeading = 90.0,
        approachDirection = "FRONT",
        channels = { tacticalChannel = 50211, sectorFacilityChannel = 50202 },
    }

    it("encodes symmetric MSG_FACILITY_STATIC_GUIDE and DYNAMIC_GUIDE with endPoint and ILS metadata", function()
        local st = tactical_streamer.create(cfg)
        local td = { x = 100.0, y = 64.0, z = 200.0 }
        local ep = { x = 400.0, y = 64.0, z = 200.0 }

        local stat = st:build_static_guide(10, "AIRCRAFT_01", td, ep, false, 5000)
        assert_eq(stat.ver, "1.9.5")
        assert_eq(stat.type, "MSG_FACILITY_STATIC_GUIDE")
        assert_eq(stat.payload.facilityId, "RWY_ALPHA_09L")
        assert_eq(stat.payload.facilityType, "RUNWAY")
        assert_eq(stat.payload.touchdownPoint.x, 100.0)
        assert_eq(stat.payload.endPoint.x, 400.0)
        assert_eq(stat.payload.glideSlopeAngle, 3.5)
        assert_eq(stat.payload.touchdownZoneLength, 80.0)
        assert_true(stat.payload.landingPermitted)
        assert_false(stat.payload.abortAlert)

        local dyn = st:build_dynamic_guide(11, "AIRCRAFT_01", td, ep, {
            velocity = { vx = 10, vy = 0.1, vz = 0 },
            acceleration = { ax = 0, ay = 0, az = 0 },
            attitude = { pitch = 0.5, roll = -0.2, yaw = 90.0 },
            angularRates = { pitchRate = 0, rollRate = 0, yawRate = 0 },
        }, "STABLE", true, false, 5050)
        assert_eq(dyn.type, "MSG_FACILITY_DYNAMIC_GUIDE")
        assert_eq(dyn.payload.endPoint.x, 400.0)
        assert_eq(dyn.payload.velocity.vx, 10)
        assert_eq(dyn.payload.approachDirection, "FRONT")
    end)

    it("encodes MSG_ATC_SLOT_ACK, MSG_ATC_FACILITY_UPDATE, and MSG_ABORT_APPROACH", function()
        local st = tactical_streamer.create(cfg)
        local ack = st:build_slot_ack(1, "AIRCRAFT_01", "ACCEPTED", nil)
        assert_eq(ack.type, "MSG_ATC_SLOT_ACK")
        assert_eq(ack.payload.status, "ACCEPTED")
        assert_eq(ack.payload.tacticalChannel, 50211)

        local upd = st:build_facility_update(2, "ROLLOUT", "AIRCRAFT_01", nil, { x = 1, y = 64, z = 2 }, 90.0, { vx = 5, vy = 0, vz = 0 })
        assert_eq(upd.type, "MSG_ATC_FACILITY_UPDATE")
        assert_eq(upd.payload.status, "OCCUPIED")

        local abt = st:build_abort_approach(3, "AIRCRAFT_01", "DECK_UNSTABLE", 120.0)
        assert_eq(abt.type, "MSG_ABORT_APPROACH")
        assert_eq(abt.payload.recommendedClimbAltitude, 120.0)
    end)
end)
