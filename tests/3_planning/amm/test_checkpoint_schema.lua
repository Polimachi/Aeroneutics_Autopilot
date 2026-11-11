-- tests/3_planning/amm/test_checkpoint_schema.lua
local mission_engine = require("mission_engine")

describe("AMM 13-Action Checkpoint Schema and Validation", function()
    it("classifies 9 active actions and 4 deferred actions matching spec v1.1.0", function()
        local active = {
            "FLY_OVER", "FLY_TO", "ORBIT", "PATROL", "POI_HOLD",
            "TAKEOFF_LAUNCHPAD", "LAND_LAUNCHPAD", "PAYLOAD_ACTION", "REDSTONE_ACTION",
        }
        local deferred = { "TAKEOFF_RUNWAY", "LAND_RUNWAY", "DOCK_ARM", "UNDOCK_ARM" }

        for _, act in ipairs(active) do
            assert_true(mission_engine.is_action_supported(act), act .. " must be active")
            assert_false(mission_engine.is_action_deferred(act), act .. " must not be deferred")
        end
        for _, act in ipairs(deferred) do
            assert_false(mission_engine.is_action_supported(act), act .. " must not be active")
            assert_true(mission_engine.is_action_deferred(act), act .. " must be deferred")
            local cp, err = mission_engine.normalize_checkpoint({ checkpointId = "CP_DEF", action = act, params = {} })
            assert_nil(cp)
            assert_eq(err, "DEFERRED_ACTION_UNSUPPORTED")
            local ok_v, err_v = mission_engine.validate_checkpoint({ checkpointId = "CP_DEF", action = act, params = {} })
            assert_false(ok_v)
            assert_eq(err_v, "DEFERRED_ACTION_UNSUPPORTED")
        end

        local bad_cp, bad_err = mission_engine.normalize_checkpoint({ action = "TELEPORT_NOW", params = {} })
        assert_nil(bad_cp)
        assert_eq(bad_err, "UNKNOWN_ACTION")
    end)

    it("inherits mission defaults across active actions while preserving FLY_TO 5m default precision", function()
        local defaults = { cruiseSpeed = 20.0, targetAlt = 140.0, acceptanceRadius = 15.0, headingMode = "AUTO" }

        local cp_over, err1 = mission_engine.normalize_checkpoint({
            action = "FLY_OVER",
            params = { targetPos = { x = 450, z = -1200 } },
        }, defaults, 1)
        assert_nil(err1)
        assert_eq(cp_over.checkpointId, "CP_01")
        assert_eq(cp_over.params.targetAlt, 140.0)
        assert_eq(cp_over.params.cruiseSpeed, 20.0)
        assert_eq(cp_over.params.acceptanceRadius, 15.0)
        assert_eq(cp_over.params.headingMode, "AUTO")

        local cp_to, err2 = mission_engine.normalize_checkpoint({
            checkpointId = "CP_PRECISE",
            action = "FLY_TO",
            params = { targetPos = { x = 100, z = 200 } },
        }, defaults, 2)
        assert_nil(err2)
        assert_eq(cp_to.params.acceptanceRadius, 5.0)

        local cp_orb, err3 = mission_engine.normalize_checkpoint({
            action = "ORBIT",
            params = { targetPos = { x = 0, z = 0 } },
        }, defaults, 3)
        assert_nil(err3)
        assert_eq(cp_orb.params.radius, 30.0)
        assert_eq(cp_orb.params.direction, "CW")

        local cp_poi, err4 = mission_engine.normalize_checkpoint({
            action = "POI_HOLD",
            params = { targetPos = { x = 10, z = 10 }, poiPos = { x = 50, y = 64, z = 10 } },
        }, defaults, 4)
        assert_nil(err4)
        assert_eq(cp_poi.params.headingMode, "POI")

        local cp_pat, err5 = mission_engine.normalize_checkpoint({
            action = "PATROL",
            params = { waypoints = { { x = 0, z = 0 }, { x = 100, z = 0 } } },
        }, defaults, 5)
        assert_nil(err5)
        assert_eq(cp_pat.params.patrolMode, "LOOP")
        assert_eq(cp_pat.params.cycles, 1)

        local cp_pld, err6 = mission_engine.normalize_checkpoint({
            action = "PAYLOAD_ACTION",
            params = { channelOffset = 29, command = "SNAP" },
        }, defaults, 6, { baseChannel = 10000 })
        assert_nil(err6)
        assert_true(cp_pld.params.waitForAck)
        assert_eq(cp_pld.params.expectedStatus, "OK")
    end)

    it("rejects malformed ORBIT, PATROL, POI_HOLD, PAYLOAD_ACTION, and REDSTONE_ACTION inputs cleanly", function()
        local cases = {
            { cp = { action = "FLY_OVER", params = { targetPos = { x = 0 / 0, z = 0 } } }, err = "INVALID_TARGET_POS" },
            { cp = { action = "FLY_TO", params = { targetPos = { x = 10, z = math.huge } } }, err = "INVALID_TARGET_POS" },
            { cp = { action = "ORBIT", params = { targetPos = { x = 0, z = 0 }, radius = -5 } }, err = "INVALID_ORBIT_RADIUS" },
            { cp = { action = "ORBIT", params = { targetPos = { x = 0, z = 0 }, direction = "UP" } }, err = "INVALID_ORBIT_DIRECTION" },
            { cp = { action = "PATROL", params = { waypoints = {} } }, err = "INVALID_PATROL_WAYPOINTS" },
            { cp = { action = "POI_HOLD", params = { targetPos = { x = 0, z = 0 } } }, err = "MISSING_POI_POS" },
            { cp = { action = "PAYLOAD_ACTION", params = { channelOffset = 19, command = "DROP" } }, err = "INVALID_ZONE3_CHANNEL" },
            { cp = { action = "PAYLOAD_ACTION", params = { channelOffset = 30, command = "DROP" } }, err = "INVALID_ZONE3_CHANNEL" },
            { cp = { action = "PAYLOAD_ACTION", params = { targetChannel = 10000, command = "DROP" } }, err = "INVALID_ZONE3_CHANNEL" },
            { cp = { action = "PAYLOAD_ACTION", params = { channelOffset = 20.5, command = "DROP" } }, err = "INVALID_ZONE3_CHANNEL" },
            { cp = { action = "PAYLOAD_ACTION", params = { channelOffset = 20, command = "" } }, err = "MISSING_PAYLOAD_COMMAND" },
            { cp = { action = "REDSTONE_ACTION", params = { mode = "BLINK", side = "top" } }, err = "INVALID_REDSTONE_MODE" },
            { cp = { action = "REDSTONE_ACTION", params = { mode = "EMIT", side = "diagonal" } }, err = "INVALID_REDSTONE_SIDE" },
        }
        for _, tc in ipairs(cases) do
            local ok, res_or_err = mission_engine.normalize_checkpoint(tc.cp, nil, 1, { baseChannel = 10000 })
            assert_nil(ok, "Expected rejection for " .. tc.err)
            assert_eq(res_or_err, tc.err)
        end
    end)

    it("validates a full v1.1.0 mission definition and stops on first deferred checkpoint", function()
        local ok, res = mission_engine.validate_mission({
            missionId = "SORTIE_01",
            defaults = { targetAlt = 120.0, cruiseSpeed = 16.0 },
            checkpoints = {
                { action = "TAKEOFF_LAUNCHPAD", params = { facilityId = "PAD_01" } },
                { action = "TAKEOFF_RUNWAY", params = {} },
            },
        }, { baseChannel = 10000 })
        assert_false(ok)
        assert_eq(res.error, "DEFERRED_ACTION_UNSUPPORTED")
        assert_eq(res.index, 2)

        local ok2, norm = mission_engine.validate_mission({
            missionId = "SORTIE_OK",
            defaults = { targetAlt = 120.0, cruiseSpeed = 16.0 },
            checkpoints = {
                { action = "TAKEOFF_LAUNCHPAD", params = { facilityId = "PAD_01" } },
                { action = "LAND_LAUNCHPAD", params = { facilityId = "PAD_01" } },
            },
        }, { baseChannel = 10000 })
        assert_true(ok2)
        assert_eq(#norm.checkpoints, 2)
        assert_eq(norm.checkpoints[1].params.targetAlt, 120.0)
    end)
end)
