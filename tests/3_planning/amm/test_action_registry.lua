-- tests/3_planning/amm/test_action_registry.lua
local action_registry = require("action_registry")

describe("AMM v2.0.0 3-Tier Action Registry, Macros, Decorators, and Preconditions (TASK-204)", function()
    local ACTIVE_36 = {
        "ACT_SYS_LOAD", "ACT_SYS_PREFLIGHT", "ACT_SYS_SET_HOME", "ACT_SYS_ARM", "ACT_SYS_DISARM", "ACT_SYS_TERMINATE",
        "ACT_TKL_TAKEOFF_VERT", "ACT_TKL_TRANS_MC2FW", "ACT_TKL_TRANS_FW2MC", "ACT_TKL_LAND_NORM", "ACT_TKL_LAND_PREC", "ACT_TKL_ABORT_LAND",
        "ACT_NAV_GOTO_WP", "ACT_NAV_SPLINE_WP", "ACT_NAV_CORRIDOR", "ACT_NAV_CHANGE_ALT", "ACT_NAV_CHANGE_SPD", "ACT_NAV_CHANGE_YAW",
        "ACT_PAT_HOLD_POS", "ACT_PAT_POI_HOLD", "ACT_PAT_LOITER_TIME", "ACT_PAT_LOITER_TURNS", "ACT_PAT_LOITER_ALT",
        "ACT_PAY_BUS_CMD", "ACT_PAY_REDSTONE", "ACT_PAY_SET_ROI", "ACT_PAY_CLEAR_ROI",
        "ACT_COM_ATC_HOLD",
        "ACT_MOB_RV_TRACK", "ACT_MOB_DECK_SYNC", "ACT_MOB_MOVING_TKOFF",
        "ACT_FS_RTL_HOME", "ACT_FS_GOTO_RALLY", "ACT_FS_FENCE_BRAKE", "ACT_FS_HOVER_HOLD", "ACT_FS_EMERG_LAND",
    }

    local DEFERRED_22 = {
        "ACT_TKL_TAKEOFF_RWY", "ACT_TKL_LAND_RWY", "ACT_NAV_TERRAIN_FLW",
        "ACT_PAT_FIG_EIGHT", "ACT_PAT_GRID_SURVEY", "ACT_PAT_EXP_SPIRAL",
        "ACT_PER_LOCAL_AVOID", "ACT_PER_REPLAN_GLB", "ACT_PER_TRACK_TGT", "ACT_PER_SENTRY_HOLD",
        "ACT_COM_SWARM_FOLLOW", "ACT_COM_HANDOVER",
        "ACT_MOB_ARM_DOCK", "ACT_MOB_ARM_UNDOCK",
        "ACT_NRG_REFUEL_DOCK", "ACT_NRG_HIBERNATE",
        "ACT_MUMT_WINGMAN", "ACT_MUMT_UGV_SCOUT", "ACT_MUMT_CROSS_CUE",
        "ACT_PAY_CARGO_DROP", "ACT_PAY_FIRE_CTRL", "ACT_PAY_GEO_SCAN",
    }

    local LEGACY_13 = {
        "FLY_OVER", "FLY_TO", "ORBIT", "PATROL", "POI_HOLD",
        "TAKEOFF_LAUNCHPAD", "LAND_LAUNCHPAD", "PAYLOAD_ACTION", "REDSTONE_ACTION",
        "TAKEOFF_RUNWAY", "LAND_RUNWAY", "DOCK_ARM", "UNDOCK_ARM",
    }

    it("registers exactly 36 active ACT_*, 22 deferred ACT_* (19 roadmap + 3 TASK-401), and Zero-Fallback rejects 13 legacy names", function()
        assert_eq(#ACTIVE_36, 36)
        assert_eq(#DEFERRED_22, 22)
        for _, act in ipairs(ACTIVE_36) do
            assert_true(action_registry.is_action_supported(act), act .. " must be active")
            assert_false(action_registry.is_action_deferred(act), act .. " must not be deferred")
            assert_not_nil(action_registry.resolve_lifecycle(act), act .. " must resolve 5-stage lifecycle")
        end

        for _, act in ipairs(DEFERRED_22) do
            assert_false(action_registry.is_action_supported(act), act .. " must not be active")
            assert_true(action_registry.is_action_deferred(act), act .. " must be deferred")
            local ok, err = action_registry.validate_action_id(act)
            assert_false(ok)
            assert_eq(err, "DEFERRED_ACTION_UNSUPPORTED")
        end

        for _, old_act in ipairs(LEGACY_13) do
            assert_false(action_registry.is_action_supported(old_act))
            assert_false(action_registry.is_action_deferred(old_act))
            assert_true(action_registry.is_legacy_action(old_act))
            local ok, err = action_registry.validate_action_id(old_act)
            assert_false(ok)
            assert_eq(err, "SCHEMA_INVALID")
        end
    end)

    it("registers 6 active + 1 deferred decorators (DEC_*) and 3 active + 2 deferred macros (MAC_*)", function()
        local active_dec = { "DEC_EMCON", "DEC_ENERGY_ECO", "DEC_SMOOTH_TRAJ", "DEC_HUMAN_AUTH", "DEC_RETRY_N", "DEC_TIMEOUT_GUARD" }
        for _, dec in ipairs(active_dec) do
            assert_true(action_registry.is_decorator_supported(dec))
            local ok, err = action_registry.check_decorator({ decoratorId = dec })
            assert_true(ok, tostring(err))
        end

        assert_true(action_registry.is_decorator_deferred("DEC_TIME_CRIT"))
        local ok_def, err_def = action_registry.check_decorator({ decoratorId = "DEC_TIME_CRIT" })
        assert_false(ok_def)
        assert_eq(err_def, "DEFERRED_DECORATOR_UNSUPPORTED")

        -- 3 active MAC_* and 2 deferred MAC_*
        for _, mac in ipairs({ "MAC_RECON_ORBIT", "MAC_SHIP_RECOVERY", "MAC_CARGO_SORTIE" }) do
            assert_true(action_registry.is_macro_supported(mac))
        end
        for _, dmac in ipairs({ "MAC_PATROL_RADAR", "MAC_ARM_RESUPPLY" }) do
            assert_true(action_registry.is_macro_deferred(dmac))
            local expanded, merr = action_registry.expand_macros({
                { checkpointId = "CP_M", action = dmac, params = {} },
            }, "VECTORED_VTOL")
            assert_nil(expanded)
            assert_eq(merr, "DEFERRED_MACRO_UNSUPPORTED")
        end
    end)

    it("expands MAC_RECON_ORBIT, MAC_SHIP_RECOVERY (branching WINGED_VTOL), and MAC_CARGO_SORTIE cleanly", function()
        local recon, err1 = action_registry.expand_macros({
            {
                checkpointId = "CP_R",
                action = "MAC_RECON_ORBIT",
                params = {
                    targetPos = { x = 450, z = -1200 },
                    targetAlt = 140,
                    poiPos = { x = 450, y = 64, z = -1200 },
                    radius = 40,
                    durationSec = 180,
                    facilityId = "PAD_BRAVO_01",
                },
                onEnter = { { type = "NOTIFY_OPERATOR", message = "ENTER_RECON" } },
                onExit = { { type = "NOTIFY_OPERATOR", message = "EXIT_RECON" } },
                onAbort = { { type = "NOTIFY_OPERATOR", message = "ABORT_RECON" } },
            },
        }, "VECTORED_VTOL")
        assert_nil(err1)
        assert_eq(#recon, 6)
        assert_eq(recon[1].onEnter[1].message, "ENTER_RECON")
        assert_nil(recon[2].onEnter)
        assert_eq(recon[6].onExit[1].message, "EXIT_RECON")
        assert_nil(recon[1].onExit)
        assert_eq(recon[3].onAbort[1].message, "ABORT_RECON")
        assert_eq(recon[1].action, "ACT_NAV_GOTO_WP")
        assert_eq(recon[1].params.tangentEntryOffsetM, 40)
        assert_eq(recon[2].action, "ACT_PAY_SET_ROI")
        assert_eq(recon[3].action, "ACT_PAT_LOITER_TIME")
        assert_eq(recon[3].decorators[1].decoratorId, "DEC_SMOOTH_TRAJ")
        assert_eq(recon[4].action, "ACT_PAY_CLEAR_ROI")
        assert_eq(recon[5].action, "ACT_FS_RTL_HOME")
        assert_eq(recon[5].decorators[1].decoratorId, "DEC_ENERGY_ECO")
        assert_eq(recon[6].action, "ACT_TKL_LAND_PREC")

        -- WINGED_VTOL ship recovery inserts ACT_TKL_TRANS_FW2MC
        local ship_wvt, err2 = action_registry.expand_macros({
            { checkpointId = "CP_S", action = "MAC_SHIP_RECOVERY", params = { facilityId = "CARRIER_01", targetPos = { x = 100, z = 100 } } },
        }, "WINGED_VTOL")
        assert_nil(err2)
        assert_eq(#ship_wvt, 5)
        assert_eq(ship_wvt[1].action, "ACT_MOB_RV_TRACK")
        assert_eq(ship_wvt[2].action, "ACT_TKL_TRANS_FW2MC")
        assert_eq(ship_wvt[3].action, "ACT_MOB_DECK_SYNC")
        assert_eq(ship_wvt[4].action, "ACT_TKL_LAND_PREC")
        assert_eq(ship_wvt[4].decorators[1].decoratorId, "DEC_RETRY_N")
        assert_eq(ship_wvt[4].decorators[1].overrideParams.maxAttempts, 3)
        assert_eq(ship_wvt[5].action, "ACT_SYS_DISARM")

        -- Non-winged VTOL omits FW2MC transition
        local ship_quad, _ = action_registry.expand_macros({
            { checkpointId = "CP_S2", action = "MAC_SHIP_RECOVERY", params = { facilityId = "CARRIER_01", targetPos = { x = 100, z = 100 } } },
        }, "QUADROTOR")
        assert_eq(#ship_quad, 4)

        local cargo, err3 = action_registry.expand_macros({
            {
                checkpointId = "CP_C",
                action = "MAC_CARGO_SORTIE",
                params = {
                    targetPos = { x = 200, z = -300 },
                    facilityId = "PAD_01",
                    channelOffset = 20,
                    command = "RELEASE_BAY",
                },
            },
        }, "HEXAROTOR")
        assert_nil(err3)
        assert_eq(#cargo, 5)
        assert_eq(cargo[1].action, "ACT_TKL_TAKEOFF_VERT")
        assert_eq(cargo[2].action, "ACT_NAV_GOTO_WP")
        assert_eq(cargo[3].action, "ACT_PAY_BUS_CMD")
        assert_eq(cargo[3].decorators[1].decoratorId, "DEC_HUMAN_AUTH")
        assert_eq(cargo[4].action, "ACT_FS_RTL_HOME")
        assert_eq(cargo[5].action, "ACT_TKL_LAND_PREC")
    end)

    it("enforces static airframe/geofence constraints (SCHEMA_INVALID) and 4-category dynamic preconditions (PRECONDITION_FAILED)", function()
        -- Static airframe check
        local ok_st, code_st = action_registry.check_static_preconditions({
            action = "ACT_TKL_TAKEOFF_VERT",
            preconditions = { disallowedAirframes = { "FIXED_WING" } },
            params = { targetPos = { x = 0, z = 0 } },
        }, { system = { airframeType = "FIXED_WING" } })
        assert_false(ok_st)
        assert_eq(code_st, "SCHEMA_INVALID")

        -- Static allowedAirframes check
        local ok_al, code_al = action_registry.check_static_preconditions({
            action = "ACT_TKL_TRANS_MC2FW",
            preconditions = { allowedAirframes = { "WINGED_VTOL" } },
            params = { targetPos = { x = 10, z = 10 } },
        }, { system = { airframeType = "QUADROTOR" } })
        assert_false(ok_al)
        assert_eq(code_al, "SCHEMA_INVALID")

        -- Dynamic 4-category check: pass case
        local ctx_ok = {
            mfd = {
                controlState = "NORMAL",
                activeSource = "FCP",
                fsmState = "CRUISE",
                sensorOk = true,
                fuel = 0.85,
                dynamics = { altitudeY = 120.0, groundSpeed = 16.0 },
                actuatorHealth = { tap = true, asa = true },
                sensorHealth = { gimbal = true },
                navigation = { gpsTimedOut = false, navValid = true, hdop = 1.2 },
            },
            nav = { navValid = true, gpsStale = false, hdop = 1.2 },
            channelBound = true,
            atcCleared = true,
            zone3Available = true,
            geofenceMarginM = 50.0,
        }
        local ok_dyn, code_dyn, det_dyn = action_registry.check_dynamic_preconditions({
            action = "ACT_NAV_GOTO_WP",
            preconditions = {
                controlState = "NORMAL",
                activeSource = "FCP",
                sensorOk = true,
                gpsValid = true,
                maxHdop = 3.0,
                minFuel = 0.50,
                channelBound = true,
                geofenceMarginM = 10.0,
                minAlt = 50.0,
                maxAlt = 300.0,
                maxSpeed = 25.0,
            },
        }, ctx_ok)
        assert_true(ok_dyn, tostring(det_dyn))
        assert_nil(code_dyn)

        -- Dynamic failure returns PRECONDITION_FAILED
        ctx_ok.mfd.fuel = 0.30
        local ok_fail, code_fail, det_fail = action_registry.check_dynamic_preconditions({
            action = "ACT_NAV_GOTO_WP",
            preconditions = { minFuel = 0.50 },
        }, ctx_ok)
        assert_false(ok_fail)
        assert_eq(code_fail, "PRECONDITION_FAILED")
        assert_true(string.find(tostring(det_fail), "minFuel", 1, true) ~= nil)

        -- maxSpeed rejects missing or NaN speed telemetry (no silent pass on nil)
        local ok_nil_spd, code_nil_spd = action_registry.check_dynamic_preconditions({
            action = "ACT_NAV_GOTO_WP",
            preconditions = { maxSpeed = 25.0 },
        }, { mfd = { dynamics = {} } })
        assert_false(ok_nil_spd)
        assert_eq(code_nil_spd, "PRECONDITION_FAILED")
    end)
end)
