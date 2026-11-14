-- tests/3_planning/amm/test_chattering_guard.lua
local chattering_guard = require("chattering_guard")

describe("AMM Chattering Prevention Guard (TASK-124)", function()
    local cfg = {
        safety = {
            lowFuelRthThreshold = 0.20,
            emergencyLandFuelThreshold = 0.10,
            chattering = {
                fenceBrakeMarginM = 5.0,
                fenceReleaseMarginM = 15.0,
                fenceDebounceTicks = 2,
                fenceDwellTicks = 40,
                lowFuelDebounceTicks = 60,
                emergFuelDebounceTicks = 30,
                fuelLatchResetMargin = 0.05,
                vtolCruiseEnterMps = 18.0,
                vtolHoverReturnMps = 8.0,
                vtolTransDebounceTicks = 10,
                vtolTransDwellTicks = 100,
                deckAbortTiltDeg = 10.0,
                deckSafeTiltDeg = 7.0,
                deckAbortHeaveMps = 2.5,
                deckSafeHeaveMps = 1.8,
                deckAbortDebounceTicks = 2,
                deckSyncDebounceTicks = 10,
                goAroundDwellTicks = 60,
                arrivalSettleTicks = 4,
                arrivalReengageMarginM = 2.0,
            },
        },
    }

    it("applies HIGH_ACTIVE and LOW_ACTIVE hysteresis deadbands without boundary toggling", function()
        -- HIGH_ACTIVE: VTOL cruise enter 18.0 m/s, hover return 8.0 m/s
        assert_false(chattering_guard.eval_hysteresis(false, 17.9, 18.0, 8.0, "HIGH_ACTIVE"))
        assert_true(chattering_guard.eval_hysteresis(false, 18.0, 18.0, 8.0, "HIGH_ACTIVE"))
        assert_true(chattering_guard.eval_hysteresis(true, 10.0, 18.0, 8.0, "HIGH_ACTIVE"))
        assert_true(chattering_guard.eval_hysteresis(true, 8.1, 18.0, 8.0, "HIGH_ACTIVE"))
        assert_false(chattering_guard.eval_hysteresis(true, 8.0, 18.0, 8.0, "HIGH_ACTIVE"))

        -- LOW_ACTIVE: Geofence inner margin 5.0m brake, 15.0m release
        assert_false(chattering_guard.eval_hysteresis(false, 5.1, 5.0, 15.0, "LOW_ACTIVE"))
        assert_true(chattering_guard.eval_hysteresis(false, 5.0, 5.0, 15.0, "LOW_ACTIVE"))
        assert_true(chattering_guard.eval_hysteresis(true, 14.9, 5.0, 15.0, "LOW_ACTIVE"))
        assert_false(chattering_guard.eval_hysteresis(true, 15.0, 5.0, 15.0, "LOW_ACTIVE"))
    end)

    it("requires N consecutive debounce ticks and resets immediately on single-tick drop", function()
        local state = chattering_guard.init(cfg)
        assert_false(chattering_guard.eval_debounce(state, "deck_abort", true, 2))
        -- Drop on tick 2 resets counter
        assert_false(chattering_guard.eval_debounce(state, "deck_abort", false, 2))
        assert_false(chattering_guard.eval_debounce(state, "deck_abort", true, 2))
        -- Consecutive tick 2 fires
        assert_true(chattering_guard.eval_debounce(state, "deck_abort", true, 2))
    end)

    it("latches lowFuel/emergFuel on debounce and blocks mid-flight unlatch until DISARMED recovery", function()
        local state = chattering_guard.init(cfg)
        -- 59 ticks at 0.20 -> not yet latched
        for _ = 1, 59 do
            chattering_guard.update_fuel_latches(state, 0.20, cfg, false)
            assert_false(state.latches.lowFuelLatched)
        end
        -- 60th consecutive tick latches RTL
        chattering_guard.update_fuel_latches(state, 0.20, cfg, false)
        assert_true(state.latches.lowFuelLatched)

        -- Mid-flight bounce up to 0.30 (isDisarmed = false) must NOT release latch
        chattering_guard.update_fuel_latches(state, 0.30, cfg, false)
        assert_true(state.latches.lowFuelLatched)

        -- Landed DISARMED below margin (0.24 < 0.25) keeps latch
        chattering_guard.update_fuel_latches(state, 0.24, cfg, true)
        assert_true(state.latches.lowFuelLatched)

        -- Landed DISARMED >= 0.25 resets latch
        chattering_guard.update_fuel_latches(state, 0.25, cfg, true)
        assert_false(state.latches.lowFuelLatched)

        -- Emergency fuel latch at 0.10 after 30 ticks
        for _ = 1, 29 do
            chattering_guard.update_fuel_latches(state, 0.10, cfg, false)
            assert_false(state.latches.emergFuelLatched)
        end
        chattering_guard.update_fuel_latches(state, 0.10, cfg, false)
        assert_true(state.latches.emergFuelLatched)

        chattering_guard.reset(state)
        assert_false(state.latches.emergFuelLatched)
        assert_false(state.latches.lowFuelLatched)
    end)

    it("enforces minimum dwell lock while allowing immediate upward priority preemption", function()
        local state = chattering_guard.init(cfg)
        local P = chattering_guard.PRIORITY
        assert_eq(P.E_STOP, 1)
        assert_true(P.E_STOP < P.EMERG_LAND)
        assert_true(P.EMERG_LAND < P.FENCE_BRAKE)
        assert_true(P.FENCE_BRAKE < P.RTH_LOITER)
        assert_true(P.RTH_LOITER < P.ABORT_LAND)
        assert_true(P.ABORT_LAND < P.NORMAL)

        -- Lock ABORT_LAND go-around dwell for 60 ticks starting at tick 100
        chattering_guard.start_dwell(state, "go_around", 100, 60)

        -- Normal priority or equal priority is locked at tick 120 (< 160)
        assert_true(chattering_guard.is_dwell_locked(state, "go_around", 120, P.ABORT_LAND, P.NORMAL))
        assert_true(chattering_guard.is_dwell_locked(state, "go_around", 159, P.ABORT_LAND, P.ABORT_LAND))

        -- Upward preemption (E_STOP, EMERG_LAND, FENCE_BRAKE, RTH_LOITER < ABORT_LAND) bypasses dwell lock immediately
        assert_false(chattering_guard.is_dwell_locked(state, "go_around", 120, P.ABORT_LAND, P.RTH_LOITER))
        assert_false(chattering_guard.is_dwell_locked(state, "go_around", 120, P.ABORT_LAND, P.FENCE_BRAKE))
        assert_false(chattering_guard.is_dwell_locked(state, "go_around", 120, P.ABORT_LAND, P.EMERG_LAND))
        assert_false(chattering_guard.is_dwell_locked(state, "go_around", 120, P.ABORT_LAND, P.E_STOP))

        -- Normal expiry at tick 160 unlocks
        assert_false(chattering_guard.is_dwell_locked(state, "go_around", 160, P.ABORT_LAND, P.NORMAL))
    end)

    it("blocks ground-init and takeoff actions on REPEAT wrap via should_skip_on_repeat", function()
        assert_true(chattering_guard.should_skip_on_repeat("ACT_SYS_LOAD"))
        assert_true(chattering_guard.should_skip_on_repeat("ACT_SYS_PREFLIGHT"))
        assert_true(chattering_guard.should_skip_on_repeat("ACT_SYS_SET_HOME"))
        assert_true(chattering_guard.should_skip_on_repeat("ACT_SYS_ARM"))
        assert_true(chattering_guard.should_skip_on_repeat("ACT_SYS_DISARM"))
        assert_true(chattering_guard.should_skip_on_repeat("ACT_TKL_TAKEOFF_VERT"))
        assert_true(chattering_guard.should_skip_on_repeat("ACT_MOB_MOVING_TKOFF"))
        assert_false(chattering_guard.should_skip_on_repeat("ACT_NAV_GOTO_WP"))
        assert_false(chattering_guard.should_skip_on_repeat("ACT_PAT_LOITER_TIME"))
    end)

    it("ignores NaN and Inf inputs in eval_hysteresis and update_fuel_latches", function()
        local state = chattering_guard.init(cfg)
        local nan = 0 / 0
        assert_false(chattering_guard.eval_hysteresis(false, nan, 5.0, 15.0, "LOW_ACTIVE"))
        assert_true(chattering_guard.eval_hysteresis(true, math.huge, 5.0, 15.0, "HIGH_ACTIVE"))
        chattering_guard.update_fuel_latches(state, nan, cfg, false)
        assert_false(state.latches.lowFuelLatched)
        assert_false(state.latches.emergFuelLatched)
    end)
end)
