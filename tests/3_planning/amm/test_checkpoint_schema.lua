-- tests/3_planning/amm/test_checkpoint_schema.lua
local mission_engine = require("mission_engine")

describe("AMM v2.0.0 3-Tier Action Checkpoint Schema and Zero-Fallback Validation", function()
    it("classifies 36 active ACT_*, 22 deferred ACT_*, and rejects all 13 deprecated v1.x action names", function()
        local active = {
            "ACT_SYS_LOAD", "ACT_SYS_PREFLIGHT", "ACT_SYS_SET_HOME", "ACT_SYS_ARM", "ACT_SYS_DISARM", "ACT_SYS_TERMINATE",
            "ACT_TKL_TAKEOFF_VERT", "ACT_TKL_TRANS_MC2FW", "ACT_TKL_TRANS_FW2MC", "ACT_TKL_LAND_NORM", "ACT_TKL_LAND_PREC", "ACT_TKL_ABORT_LAND",
            "ACT_NAV_GOTO_WP", "ACT_NAV_SPLINE_WP", "ACT_NAV_CORRIDOR", "ACT_NAV_CHANGE_ALT", "ACT_NAV_CHANGE_SPD", "ACT_NAV_CHANGE_YAW",
            "ACT_PAT_HOLD_POS", "ACT_PAT_POI_HOLD", "ACT_PAT_LOITER_TIME", "ACT_PAT_LOITER_TURNS", "ACT_PAT_LOITER_ALT",
            "ACT_PAY_BUS_CMD", "ACT_PAY_REDSTONE", "ACT_PAY_SET_ROI", "ACT_PAY_CLEAR_ROI",
            "ACT_COM_ATC_HOLD",
            "ACT_MOB_RV_TRACK", "ACT_MOB_DECK_SYNC", "ACT_MOB_MOVING_TKOFF",
            "ACT_FS_RTL_HOME", "ACT_FS_GOTO_RALLY", "ACT_FS_FENCE_BRAKE", "ACT_FS_HOVER_HOLD", "ACT_FS_EMERG_LAND",
        }
        local deferred = {
            "ACT_TKL_TAKEOFF_RWY", "ACT_TKL_LAND_RWY", "ACT_NAV_TERRAIN_FLW",
            "ACT_PAT_FIG_EIGHT", "ACT_PAT_GRID_SURVEY", "ACT_PAT_EXP_SPIRAL",
            "ACT_PER_LOCAL_AVOID", "ACT_PER_REPLAN_GLB", "ACT_PER_TRACK_TGT", "ACT_PER_SENTRY_HOLD",
            "ACT_COM_SWARM_FOLLOW", "ACT_COM_HANDOVER", "ACT_MOB_ARM_DOCK", "ACT_MOB_ARM_UNDOCK",
            "ACT_NRG_REFUEL_DOCK", "ACT_NRG_HIBERNATE", "ACT_MUMT_WINGMAN", "ACT_MUMT_UGV_SCOUT", "ACT_MUMT_CROSS_CUE",
            "ACT_PAY_CARGO_DROP", "ACT_PAY_FIRE_CTRL", "ACT_PAY_GEO_SCAN",
        }
        local legacy = {
            "FLY_OVER", "FLY_TO", "ORBIT", "PATROL", "POI_HOLD",
            "TAKEOFF_LAUNCHPAD", "LAND_LAUNCHPAD", "PAYLOAD_ACTION", "REDSTONE_ACTION",
            "TAKEOFF_RUNWAY", "LAND_RUNWAY", "DOCK_ARM", "UNDOCK_ARM",
        }

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
        for _, old_act in ipairs(legacy) do
            local cp, err = mission_engine.normalize_checkpoint({ checkpointId = "CP_OLD", action = old_act, params = {} })
            assert_nil(cp)
            assert_eq(err, "SCHEMA_INVALID")
        end

        local bad_cp, bad_err = mission_engine.normalize_checkpoint({ action = "TELEPORT_NOW", params = {} })
        assert_nil(bad_cp)
        assert_eq(bad_err, "UNKNOWN_ACTION")
    end)

    it("inherits mission defaults across ACT_* actions while preserving ACT_NAV_GOTO_WP 5m precision default", function()
        local defaults = { cruiseSpeed = 20.0, targetAlt = 140.0, acceptanceRadius = 15.0, headingMode = "AUTO" }

        local cp_spl, err1 = mission_engine.normalize_checkpoint({
            action = "ACT_NAV_SPLINE_WP",
            params = { targetPos = { x = 450, z = -1200 } },
        }, defaults, 1)
        assert_nil(err1)
        assert_eq(cp_spl.checkpointId, "CP_01")
        assert_eq(cp_spl.params.targetAlt, 140.0)
        assert_eq(cp_spl.params.cruiseSpeed, 20.0)
        assert_eq(cp_spl.params.acceptanceRadius, 15.0)
        assert_eq(cp_spl.params.headingMode, "AUTO")

        local cp_to, err2 = mission_engine.normalize_checkpoint({
            checkpointId = "CP_PRECISE",
            action = "ACT_NAV_GOTO_WP",
            params = { targetPos = { x = 100, z = 200 } },
        }, defaults, 2)
        assert_nil(err2)
        assert_eq(cp_to.params.acceptanceRadius, 5.0)

        local cp_orb, err3 = mission_engine.normalize_checkpoint({
            action = "ACT_PAT_LOITER_TIME",
            params = { targetPos = { x = 0, z = 0 } },
        }, defaults, 3)
        assert_nil(err3)
        assert_eq(cp_orb.params.radius, 30.0)
        assert_eq(cp_orb.params.direction, "CW")

        local cp_poi, err4 = mission_engine.normalize_checkpoint({
            action = "ACT_PAT_POI_HOLD",
            params = { targetPos = { x = 10, z = 10 }, poiPos = { x = 50, y = 64, z = 10 } },
        }, defaults, 4)
        assert_nil(err4)
        assert_eq(cp_poi.params.headingMode, "POI")

        local cp_cor, err5 = mission_engine.normalize_checkpoint({
            action = "ACT_NAV_CORRIDOR",
            params = { startPos = { x = 0, z = 0 }, endPos = { x = 100, z = 0 } },
        }, defaults, 5)
        assert_nil(err5)
        assert_eq(cp_cor.params.endPos.x, 100)

        local cp_pld, err6 = mission_engine.normalize_checkpoint({
            action = "ACT_PAY_BUS_CMD",
            params = { channelOffset = 29, command = "SNAP" },
        }, defaults, 6, { baseChannel = 10000 })
        assert_nil(err6)
        assert_true(cp_pld.params.waitForAck)
        assert_eq(cp_pld.params.expectedStatus, "OK")
    end)

    it("rejects malformed ACT_* params cleanly", function()
        local cases = {
            { cp = { action = "ACT_NAV_SPLINE_WP", params = { targetPos = { x = 0 / 0, z = 0 } } }, err = "INVALID_TARGET_POS" },
            { cp = { action = "ACT_NAV_GOTO_WP", params = { targetPos = { x = 10, z = math.huge } } }, err = "INVALID_TARGET_POS" },
            { cp = { action = "ACT_PAT_LOITER_TIME", params = { targetPos = { x = 0, z = 0 }, radius = 4 } }, err = "INVALID_ORBIT_RADIUS" },
            { cp = { action = "ACT_PAT_LOITER_TIME", params = { targetPos = { x = 0, z = 0 }, direction = "UP" } }, err = "INVALID_ORBIT_DIRECTION" },
            { cp = { action = "ACT_NAV_CORRIDOR", params = {} }, err = "INVALID_CORRIDOR_BOUNDS" },
            { cp = { action = "ACT_PAT_POI_HOLD", params = { targetPos = { x = 0, z = 0 } } }, err = "MISSING_POI_POS" },
            { cp = { action = "ACT_PAY_BUS_CMD", params = { channelOffset = 19, command = "DROP" } }, err = "INVALID_ZONE3_CHANNEL" },
            { cp = { action = "ACT_PAY_BUS_CMD", params = { channelOffset = 30, command = "DROP" } }, err = "INVALID_ZONE3_CHANNEL" },
            { cp = { action = "ACT_PAY_BUS_CMD", params = { targetChannel = 10000, command = "DROP" } }, err = "INVALID_ZONE3_CHANNEL" },
            { cp = { action = "ACT_PAY_BUS_CMD", params = { channelOffset = 20.5, command = "DROP" } }, err = "INVALID_ZONE3_CHANNEL" },
            { cp = { action = "ACT_PAY_BUS_CMD", params = { channelOffset = 20, command = "" } }, err = "MISSING_PAYLOAD_COMMAND" },
            { cp = { action = "ACT_PAY_REDSTONE", params = { mode = "BLINK", side = "top" } }, err = "INVALID_REDSTONE_MODE" },
            { cp = { action = "ACT_PAY_REDSTONE", params = { mode = "EMIT", side = "diagonal" } }, err = "INVALID_REDSTONE_SIDE" },
        }
        for _, tc in ipairs(cases) do
            local ok, res_or_err = mission_engine.normalize_checkpoint(tc.cp, nil, 1, { baseChannel = 10000 })
            assert_nil(ok, "Expected rejection for " .. tc.err)
            assert_eq(res_or_err, tc.err)
        end
    end)

    it("validates a full v2.0.0 mission definition, rejects items[], and stops on first deferred checkpoint", function()
        local ok, res = mission_engine.validate_mission({
            missionId = "SORTIE_01",
            version = "2.0.0",
            defaults = { targetAlt = 120.0, cruiseSpeed = 16.0 },
            checkpoints = {
                { action = "ACT_TKL_TAKEOFF_VERT", params = { facilityId = "PAD_01" } },
                { action = "ACT_TKL_TAKEOFF_RWY", params = {} },
            },
        }, { baseChannel = 10000 })
        assert_false(ok)
        assert_eq(res.error, "DEFERRED_ACTION_UNSUPPORTED")
        assert_eq(res.index, 2)

        local ok2, norm = mission_engine.validate_mission({
            missionId = "SORTIE_OK",
            version = "2.0.0",
            defaults = { targetAlt = 120.0, cruiseSpeed = 16.0 },
            checkpoints = {
                { action = "ACT_TKL_TAKEOFF_VERT", params = { facilityId = "PAD_01" } },
                { action = "ACT_TKL_LAND_PREC", params = { facilityId = "PAD_01" } },
            },
        }, { baseChannel = 10000 })
        assert_true(ok2)
        assert_eq(#norm.checkpoints, 2)
        assert_eq(norm.checkpoints[1].params.targetAlt, 120.0)
    end)
end)
