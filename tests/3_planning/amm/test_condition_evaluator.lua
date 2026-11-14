-- tests/3_planning/amm/test_condition_evaluator.lua
local condition_evaluator = require("condition_evaluator")

describe("AMM 12-Type Condition Evaluator and Default Resolver", function()
    it("evaluates geometric, time, and fuel conditions while blocking missing boot telemetry", function()
        local boot_ctx = { mfd = nil, enteredAtMs = 1000, nowMs = 2000, target = { x = 0, y = 100, z = 0 } }
        assert_false(condition_evaluator.evaluate_condition({ type = "PROXIMITY_2D", toleranceM = 20 }, boot_ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "PROXIMITY_3D", toleranceM = 10 }, boot_ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "ALTITUDE_REACHED", toleranceM = 5 }, boot_ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "FUEL_LEVEL_BELOW", threshold = 0.25 }, boot_ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "CROSS_TRACK_ERROR", maxDevM = 10 }, boot_ctx))

        local ctx = {
            mfd = {
                fsmState = "CRUISE",
                fuel = 0.22,
                dynamics = { altitudeY = 138.0 },
                navigation = { currentPos = { x = 103.0, z = -4.0 }, crossTrackError = -12.5 },
            },
            target = { x = 100.0, y = 140.0, z = 0.0 },
            enteredAtMs = 10000,
            nowMs = 40000,
        }
        assert_true(condition_evaluator.evaluate_condition({ type = "PROXIMITY_2D", toleranceM = 5.0 }, ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "PROXIMITY_2D", toleranceM = 4.5 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "PROXIMITY_3D", toleranceM = 5.5 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "ALTITUDE_REACHED", toleranceM = 2.0 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "DURATION_SEC", durationSec = 30.0 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "TIMEOUT_SEC", timeout = 30.0 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "FUEL_LEVEL_BELOW", threshold = 0.25 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "CROSS_TRACK_ERROR", maxDevM = 12.0 }, ctx))
    end)

    it("guards FACILITY_TOUCHDOWN against pre-approach DISARMED and isolates stale PAYLOAD_RESP_MATCH ACKs", function()
        local ground_ctx = { mfd = { fsmState = "DISARMED" }, touchdownArmed = false }
        assert_false(condition_evaluator.evaluate_condition({ type = "FACILITY_TOUCHDOWN" }, ground_ctx))
        assert_true(condition_evaluator.should_arm_touchdown("APPROACH_LAND"))
        assert_false(condition_evaluator.should_arm_touchdown("DISARMED"))

        local landed_ctx = { mfd = { fsmState = "DISARMED" }, touchdownArmed = true }
        assert_true(condition_evaluator.evaluate_condition({ type = "FACILITY_TOUCHDOWN" }, landed_ctx))

        local stale_ack_ctx = {
            checkpoint = { checkpointId = "CP_04" },
            payloadAck = { checkpointId = "CP_02", command = "RELEASE_BAY", status = "DROPPED" },
        }
        assert_false(condition_evaluator.evaluate_condition({ type = "PAYLOAD_RESP_MATCH", expectedStatus = "DROPPED" }, stale_ack_ctx))

        local valid_ack_ctx = {
            checkpoint = { checkpointId = "CP_04" },
            payloadAck = { checkpointId = "CP_04", command = "RELEASE_BAY", status = "DROPPED" },
        }
        assert_true(condition_evaluator.evaluate_condition({ type = "PAYLOAD_RESP_MATCH", expectedStatus = "DROPPED" }, valid_ack_ctx))
    end)

    it("evaluates REDSTONE_INPUT_HIGH (analog, digital, bundled) and reserved ARM_DOCKED / ARM_RELEASED conditions", function()
        local rs = mock.redstone()
        rs._bundledIn = { top = colors.red }
        rs.getBundledInput = function(side) return rs._bundledIn[side] or 0 end
        rs.testBundledInput = function(side, mask) return bit32.band(rs._bundledIn[side] or 0, mask) ~= 0 end

        rs.setAnalogInput("left", 9)
        rs.setInput("back", true)

        local ctx = {
            redstone = rs,
            colors = colors,
            armState = { docked = true, released = false, facilityId = "ARM_01" },
        }
        assert_true(condition_evaluator.evaluate_condition({ type = "REDSTONE_INPUT_HIGH", side = "left", minLevel = 8 }, ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "REDSTONE_INPUT_HIGH", side = "left", minLevel = 10 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "REDSTONE_INPUT_HIGH", side = "back", minLevel = 1 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "REDSTONE_INPUT_HIGH", side = "top", color = colors.red }, ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "REDSTONE_INPUT_HIGH", side = "top", color = colors.blue }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "ARM_DOCKED", facilityId = "ARM_01" }, ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "ARM_RELEASED", facilityId = "ARM_01" }, ctx))
    end)

    it("combines conditions via ALL/ANY and prevents vacuous truth on empty condition arrays", function()
        assert_false(condition_evaluator.evaluate_group({ logic = "ALL", conditions = {} }, {}))
        assert_false(condition_evaluator.evaluate_group({ logic = "ANY", conditions = {} }, {}))

        local ctx = { enteredAtMs = 0, nowMs = 5000, mfd = { fuel = 0.80 } }
        local grp_all = {
            logic = "ALL",
            conditions = {
                { type = "DURATION_SEC", durationSec = 5 },
                { type = "FUEL_LEVEL_BELOW", threshold = 0.20 },
            },
        }
        local grp_any = { logic = "ANY", conditions = grp_all.conditions }
        assert_false(condition_evaluator.evaluate_group(grp_all, ctx))
        assert_true(condition_evaluator.evaluate_group(grp_any, ctx))
    end)

    it("resolves default completeWhen across v2.0.0 ACT_* actions, rejects deferred/legacy actions, and enforces settleTicks", function()
        local spl_def = condition_evaluator.resolve_default_complete({ action = "ACT_NAV_SPLINE_WP", params = {} }, { acceptanceRadius = 15 })
        assert_eq(spl_def.conditions[1].type, "PROXIMITY_2D")
        assert_eq(spl_def.conditions[1].toleranceM, 15)
        assert_eq(spl_def.conditions[1].settleTicks, 0)

        local to_def = condition_evaluator.resolve_default_complete({ action = "ACT_NAV_GOTO_WP", params = {} }, { acceptanceRadius = 15 })
        assert_eq(to_def.conditions[1].type, "PROXIMITY_3D")
        assert_eq(to_def.conditions[1].toleranceM, 5.0)
        assert_eq(to_def.conditions[1].settleTicks, 4)

        local tk_cp = { action = "ACT_TKL_TAKEOFF_VERT", params = { targetAlt = 140 } }
        local tk_def = condition_evaluator.resolve_default_complete(tk_cp)
        assert_eq(tk_def.conditions[1].type, "ALTITUDE_REACHED")
        assert_eq(tk_def.conditions[1].settleTicks, 4)
        local tk_eval = condition_evaluator.evaluate_checkpoint(tk_cp, { mfd = { fsmState = "CRUISE", dynamics = { altitudeY = 80 } } })
        assert_true(tk_eval.completed)

        local land_def = condition_evaluator.resolve_default_complete({ action = "ACT_TKL_LAND_PREC", params = { facilityId = "PAD_01" } })
        assert_eq(land_def.conditions[1].type, "FACILITY_TOUCHDOWN")

        local poi_hold = condition_evaluator.resolve_default_complete({ action = "ACT_PAT_POI_HOLD", params = {} })
        assert_eq(#poi_hold.conditions, 0)

        local orb_hold = condition_evaluator.resolve_default_complete({ action = "ACT_PAT_LOITER_TIME", params = {} })
        assert_eq(#orb_hold.conditions, 0)
        local orb_dur = condition_evaluator.resolve_default_complete({ action = "ACT_PAT_LOITER_TIME", params = { durationSec = 30 } })
        assert_eq(orb_dur.conditions[1].type, "DURATION_SEC")

        local pld_imm = condition_evaluator.resolve_default_complete({ action = "ACT_PAY_BUS_CMD", params = { command = "PING", waitForAck = false } })
        assert_eq(pld_imm.conditions[1].type, "DURATION_SEC")
        assert_eq(pld_imm.conditions[1].durationSec, 0)

        local rs_emit = condition_evaluator.resolve_default_complete({ action = "ACT_PAY_REDSTONE", params = { mode = "EMIT", side = "top", durationMs = 500 } })
        assert_eq(rs_emit.conditions[1].durationSec, 0.5)

        local rs_wait = condition_evaluator.resolve_default_complete({ action = "ACT_PAY_REDSTONE", params = { mode = "WAIT_INPUT", side = "back" } })
        assert_eq(rs_wait.conditions[1].type, "REDSTONE_INPUT_HIGH")

        for _, def_act in ipairs({ "ACT_TKL_TAKEOFF_RWY", "ACT_TKL_LAND_RWY", "ACT_MOB_ARM_DOCK", "ACT_MOB_ARM_UNDOCK", "ACT_PAY_CARGO_DROP" }) do
            local d_res, d_err = condition_evaluator.resolve_default_complete({ action = def_act, params = {} })
            assert_nil(d_res)
            assert_eq(d_err, "DEFERRED_ACTION_UNSUPPORTED")
        end

        -- Zero-Fallback rejection of legacy v1.x action names
        local leg_res, leg_err = condition_evaluator.resolve_default_complete({ action = "FLY_OVER", params = {} })
        assert_nil(leg_res)
        assert_eq(leg_err, "SCHEMA_INVALID")

        -- settleTicks = 4 anti-chattering dwell verification for PROXIMITY_3D
        local settle_cp = {
            checkpointId = "CP_SETTLE",
            action = "ACT_NAV_GOTO_WP",
            params = { targetPos = { x = 100, z = 0 }, targetAlt = 140, acceptanceRadius = 5.0 },
            settleState = {},
        }
        local in_ctx = {
            checkpoint = settle_cp,
            mfd = { fsmState = "CRUISE", dynamics = { altitudeY = 140 }, navigation = { currentPos = { x = 98, z = 0 } } },
        }
        local out_ctx = {
            checkpoint = settle_cp,
            mfd = { fsmState = "CRUISE", dynamics = { altitudeY = 140 }, navigation = { currentPos = { x = 90, z = 0 } } },
        }
        assert_false(condition_evaluator.evaluate_checkpoint(settle_cp, in_ctx).completed) -- tick 1
        assert_false(condition_evaluator.evaluate_checkpoint(settle_cp, in_ctx).completed) -- tick 2
        assert_false(condition_evaluator.evaluate_checkpoint(settle_cp, out_ctx).completed) -- reset!
        assert_false(condition_evaluator.evaluate_checkpoint(settle_cp, in_ctx).completed) -- tick 1
        assert_false(condition_evaluator.evaluate_checkpoint(settle_cp, in_ctx).completed) -- tick 2
        assert_false(condition_evaluator.evaluate_checkpoint(settle_cp, in_ctx).completed) -- tick 3
        assert_true(condition_evaluator.evaluate_checkpoint(settle_cp, in_ctx).completed)  -- tick 4 -> complete!

        local str = condition_evaluator.format_progress(
            { action = "ACT_PAT_LOITER_TIME", params = { durationSec = 30 } },
            { enteredAtMs = 0, nowMs = 12000 }
        )
        assert_true(#str > 0 and #str <= 25)
    end)

    it("resolves all 36 active ACT_* defaults, evaluates SYS_ARMED/IMMEDIATE, and tracks 360*turns for ACT_PAT_LOITER_TURNS", function()
        local action_registry = require("action_registry")
        for act_id in pairs(action_registry.ACTIVE_LIFECYCLES) do
            local grp, err = condition_evaluator.resolve_default_complete({ action = act_id, params = {} }, { acceptanceRadius = 15 })
            assert_nil(err, act_id .. " should resolve cleanly")
            assert_not_nil(grp, act_id .. " should return default group")
        end

        assert_true(condition_evaluator.evaluate_condition({ type = "IMMEDIATE" }, {}))
        assert_false(condition_evaluator.evaluate_condition({ type = "SYS_ARMED" }, { mfd = { controlState = "DISARMED", fsmState = "DISARMED" } }))
        assert_true(condition_evaluator.evaluate_condition({ type = "SYS_ARMED" }, { mfd = { controlState = "IDLE_ARMED" } }))

        local set_home = condition_evaluator.resolve_default_complete({ action = "ACT_SYS_SET_HOME", params = {} })
        assert_eq(set_home.conditions[1].type, "IMMEDIATE")

        local trans = condition_evaluator.resolve_default_complete({ action = "ACT_TKL_TRANS_MC2FW", params = {} })
        assert_eq(trans.conditions[1].type, "DURATION_SEC")
        assert_eq(trans.conditions[1].durationSec, 0.5)

        local roi_imm = condition_evaluator.resolve_default_complete({ action = "ACT_PAY_SET_ROI", params = { poiPos = { x = 1, y = 2, z = 3 } } })
        assert_eq(roi_imm.conditions[1].type, "IMMEDIATE")

        -- ACT_PAT_LOITER_TURNS: 1 full turn = 360 deg around center (0, 0)
        local orb_cp = {
            checkpointId = "CP_ORB",
            action = "ACT_PAT_LOITER_TURNS",
            params = { targetPos = { x = 0, z = 0 }, turns = 1 },
        }
        local angles = { 0, 90, 180, 270, 360 }
        for i, deg in ipairs(angles) do
            local rad = math.rad(deg)
            local ev = condition_evaluator.evaluate_checkpoint(orb_cp, {
                mfd = { navigation = { currentPos = { x = 20 * math.cos(rad), z = 20 * math.sin(rad) } } },
            })
            if i < #angles then
                assert_false(ev.completed)
            else
                assert_true(ev.completed)
            end
        end
    end)
end)
