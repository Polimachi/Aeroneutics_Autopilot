-- tests/0_infra/gcs/test_fleet_tracker.lua
local fleet_tracker = require("fleet_tracker")

describe("GCS fleet tracker and multi-craft telemetry cache", function()
    local cfg = {
        ui = {
            telemetryTimeoutSec = 5.0
        }
    }

    it("registers crafts and maintains craft order and active craft", function()
        local state = fleet_tracker.init(cfg)
        assert_nil(fleet_tracker.get_active_craft(state))

        fleet_tracker.register_craft(state, "AIRCRAFT_01", 10000, 1)
        fleet_tracker.register_craft(state, "AIRCRAFT_02", 10040, 2)

        local active = fleet_tracker.get_active_craft(state)
        assert_not_nil(active)
        assert_eq(active.domainId, "AIRCRAFT_01")
        assert_eq(active.baseChannel, 10000)
        assert_eq(active.blockId, 1)

        local summary = fleet_tracker.get_fleet_summary(state)
        assert_eq(#summary, 2)
        assert_eq(summary[1].domainId, "AIRCRAFT_01")
        assert_eq(summary[2].domainId, "AIRCRAFT_02")
    end)

    it("cycles active craft with select_next and direct select_craft", function()
        local state = fleet_tracker.init(cfg)
        fleet_tracker.register_craft(state, "AIRCRAFT_01", 10000, 1)
        fleet_tracker.register_craft(state, "AIRCRAFT_02", 10040, 2)
        fleet_tracker.register_craft(state, "DRONE_01", 10080, 3)

        assert_eq(fleet_tracker.get_active_craft(state).domainId, "AIRCRAFT_01")

        -- Select next -> AIRCRAFT_02
        local next1 = fleet_tracker.select_next(state)
        assert_eq(next1.domainId, "AIRCRAFT_02")

        -- Select next -> DRONE_01
        local next2 = fleet_tracker.select_next(state)
        assert_eq(next2.domainId, "DRONE_01")

        -- Circular wrap -> AIRCRAFT_01
        local next3 = fleet_tracker.select_next(state)
        assert_eq(next3.domainId, "AIRCRAFT_01")

        -- Direct select
        assert_true(fleet_tracker.select_craft(state, "DRONE_01"))
        assert_eq(fleet_tracker.get_active_craft(state).domainId, "DRONE_01")

        -- Non-existent craft
        assert_false(fleet_tracker.select_craft(state, "NON_EXISTENT"))
    end)

    it("updates telemetry cache and marks freshness", function()
        local state = fleet_tracker.init(cfg)
        fleet_tracker.register_craft(state, "AIRCRAFT_01", 10000, 1)

        local telem_payload = {
            attitude = { pitch = 2.5, roll = -0.5, heading = 180.0 },
            dynamics = { altitudeY = 125.4, verticalSpeed = 0.5, groundSpeed = 16.2 },
            fuel = 0.82,
            fsmState = "CRUISE",
            actuatorHealth = { tap = true, asa = true, allOk = true }
        }

        local updated = fleet_tracker.update_telemetry(state, "AIRCRAFT_01", telem_payload, 10000)
        assert_true(updated)

        local active = fleet_tracker.get_active_craft(state)
        assert_not_nil(active.telemetry)
        assert_eq(active.telemetry.attitude.pitch, 2.5)
        assert_eq(active.telemetry.dynamics.altitudeY, 125.4)
        assert_eq(active.telemetry.fuel, 0.82)
        assert_eq(active.telemetry.fsmState, "CRUISE")
        assert_false(active.isStale)
    end)

    it("flags stale crafts when timeout threshold is exceeded", function()
        local state = fleet_tracker.init(cfg)
        fleet_tracker.register_craft(state, "AIRCRAFT_01", 10000, 1)
        fleet_tracker.register_craft(state, "AIRCRAFT_02", 10040, 2)

        fleet_tracker.update_telemetry(state, "AIRCRAFT_01", { fsmState = "CRUISE" }, 1000)
        fleet_tracker.update_telemetry(state, "AIRCRAFT_02", { fsmState = "HOVER" }, 5000)

        -- at t=6500 (threshold = 5000ms):
        -- AIRCRAFT_01 diff = 5500 > 5000 -> stale!
        -- AIRCRAFT_02 diff = 1500 <= 5000 -> fresh!
        fleet_tracker.prune_stale(state, 6500)

        local s1 = fleet_tracker.get_craft(state, "AIRCRAFT_01")
        local s2 = fleet_tracker.get_craft(state, "AIRCRAFT_02")
        assert_true(s1.isStale)
        assert_false(s2.isStale)
    end)

    it("unregisters crafts cleanly", function()
        local state = fleet_tracker.init(cfg)
        fleet_tracker.register_craft(state, "AIRCRAFT_01", 10000, 1)
        fleet_tracker.register_craft(state, "AIRCRAFT_02", 10040, 2)

        assert_true(fleet_tracker.unregister_craft(state, "AIRCRAFT_01"))
        assert_nil(fleet_tracker.get_craft(state, "AIRCRAFT_01"))
        assert_eq(fleet_tracker.get_active_craft(state).domainId, "AIRCRAFT_02")

        assert_true(fleet_tracker.unregister_craft(state, "AIRCRAFT_02"))
        assert_nil(fleet_tracker.get_active_craft(state))
    end)

    it("tracks ADVANCED_VTOL airframe with label and icon in telemetry and fleet summary", function()
        local state = fleet_tracker.init(cfg)
        fleet_tracker.register_craft(state, "ADV_01", 10000, 1, "ADVANCED_VTOL")

        assert_eq(fleet_tracker.get_airframe_label("ADVANCED_VTOL"), "ADV_VTOL")
        assert_eq(fleet_tracker.get_airframe_icon("ADVANCED_VTOL"), "^V^")

        fleet_tracker.update_telemetry(state, "ADV_01", {
            fsmState = "CRUISE",
            airframeType = "ADVANCED_VTOL",
        }, 1000)

        local craft = fleet_tracker.get_craft(state, "ADV_01")
        assert_eq(craft.airframeType, "ADVANCED_VTOL")

        local summary = fleet_tracker.get_fleet_summary(state)
        assert_eq(#summary, 1)
        assert_eq(summary[1].airframeType, "ADVANCED_VTOL")
        assert_eq(summary[1].airframeLabel, "ADV_VTOL")
        assert_eq(summary[1].airframeIcon, "^V^")
    end)
end)
