-- tests/3_planning/amm/test_mission_fsm.lua
local network_manager = require("network_manager")
local mission_engine = require("mission_engine")

describe("AMM v2.0.0 Mission Engine Loader, Decorators, Preconditions, and Sequencer FSM", function()
    local function create_engine_fixture(extra_opts)
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local rs = mock.redstone()
        local opts = extra_opts or {}
        opts.net = net
        opts.redstone = rs
        opts.colors = colors
        opts.config = {
            baseChannel = 10000,
            defaultAlt = 150.0,
            defaultSpeed = 18.0,
            arrivalRadius = 15.0,
            system = { airframeType = "VECTORED_VTOL" },
        }
        local eng = mission_engine.new(opts)
        return eng, net, m, rs
    end

    it("enforces Zero-Fallback rejection on v1.0.0 items[] and legacy 13 actions while loading v2.0.0 & macros", function()
        local eng = create_engine_fixture()

        -- Reject v1.0.0 items[] JSON
        local f1 = fs.open("missions/legacy_items.json", "w")
        f1.write(textutils.serializeJSON({
            version = "1.0.0",
            items = { { id = 1, x = 100, z = 200, alt = 140, speed = 18 } },
        }))
        f1.close()
        local ok_leg, err_leg = eng:load("missions/legacy_items.json")
        assert_false(ok_leg)
        assert_eq(err_leg, "SCHEMA_INVALID")

        -- Reject legacy v1.x action names (FLY_OVER)
        local ok_old, err_old = eng:load_table({
            version = "2.0.0",
            checkpoints = { { action = "FLY_OVER", params = { targetPos = { x = 100, z = 200 } } } },
        })
        assert_false(ok_old)
        assert_eq(err_old, "SCHEMA_INVALID")

        -- Load valid v2.0.0 macro + save and reload
        local ok_v2, err_v2 = eng:load_table({
            missionId = "RECON_MACRO_V2",
            version = "2.0.0",
            checkpoints = {
                {
                    checkpointId = "CP_MAC",
                    action = "MAC_RECON_ORBIT",
                    params = {
                        targetPos = { x = 300, z = -400 },
                        poiPos = { x = 300, y = 64, z = -400 },
                        radius = 40,
                        durationSec = 60,
                        facilityId = "PAD_BRAVO_01",
                    },
                },
            },
        })
        assert_true(ok_v2, tostring(err_v2))
        assert_eq(eng:count(), 6)
        assert_eq(eng.checkpoints[1].action, "ACT_NAV_GOTO_WP")
        assert_eq(eng.checkpoints[6].action, "ACT_TKL_LAND_PREC")

        assert_true(eng:save("missions/saved_v200.json"))
        local eng2 = create_engine_fixture()
        assert_true(eng2:load("missions/saved_v200.json"))
        assert_eq(eng2.version, "2.0.0")
        assert_eq(eng2:count(), 6)

        fs.delete("missions/legacy_items.json")
        fs.delete("missions/saved_v200.json")
    end)

    it("dispatches ACT_* actions, sequences SINGLE/REPEAT, and skips init/takeoff steps on REPEAT loop", function()
        local eng, _, m, rs = create_engine_fixture()
        local ok, err = eng:load_table({
            missionId = "SORTIE_REPEAT",
            version = "2.0.0",
            executionMode = "REPEAT",
            defaults = { targetAlt = 140.0, cruiseSpeed = 18.0, acceptanceRadius = 15.0 },
            checkpoints = {
                { checkpointId = "CP_ARM", action = "ACT_SYS_ARM", params = {} },
                { checkpointId = "CP_TK", action = "ACT_TKL_TAKEOFF_VERT", params = { targetAlt = 140, facilityId = "PAD_01" } },
                {
                    checkpointId = "CP_ORB",
                    action = "ACT_PAT_LOITER_TIME",
                    params = { targetPos = { x = 500, z = -500 }, radius = 40, direction = "CCW", durationSec = 10 },
                    onEnter = { { type = "REDSTONE_PULSE", side = "top", durationMs = 500 } },
                },
                {
                    checkpointId = "CP_POI",
                    action = "ACT_PAT_POI_HOLD",
                    params = { targetPos = { x = 600, z = -600 }, poiPos = { x = 650, y = 70, z = -600 }, durationSec = 5 },
                },
            },
        })
        assert_true(ok, tostring(err))

        -- Starts at CP_ARM (index 1)
        assert_true(eng:start("REPEAT", 1000))
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.active_index, 1)

        -- Telemetry controlState = IDLE_ARMED completes ACT_SYS_ARM -> advances to ACT_TKL_TAKEOFF_VERT (index 2)
        local st0 = eng:step_telemetry({ controlState = "IDLE_ARMED", fsmState = "IDLE_ARMED" }, 1200)
        assert_eq(st0, "ADVANCED")
        assert_eq(eng.active_index, 2)

        -- FCP enters CRUISE -> ACT_TKL_TAKEOFF_VERT completes, advances to CP_ORB (index 3)
        local st1 = eng:step_telemetry({ fsmState = "CRUISE", dynamics = { altitudeY = 140 }, navigation = { currentPos = { x = 0, z = 0 } } }, 2000)
        assert_eq(st1, "ADVANCED")
        assert_eq(eng.active_index, 3)
        assert_true(rs.getOutput("top"))
        assert_eq(#m._transmitted, 0) -- Zero-Fallback: Base+4 goal only, no Base+0 CMD
        local orb_goal = eng:get_trajectory_goal()
        assert_eq(orb_goal.flightMode, "LOITER")
        assert_eq(orb_goal.loiterRadius, 40)
        assert_eq(orb_goal.loiterDirection, "CCW")

        -- Tick expires pulse at 2500ms; ORBIT duration (10s) completes at 12000ms -> advances to CP_POI (index 4)
        eng:tick(2500)
        assert_false(rs.getOutput("top"))
        local st2 = eng:step_telemetry({ fsmState = "LOITER", dynamics = { altitudeY = 140 }, navigation = { currentPos = { x = 500, z = -500 } } }, 12000)
        assert_eq(st2, "ADVANCED")
        assert_eq(eng.active_index, 4)
        local poi_goal = eng:get_trajectory_goal()
        assert_eq(poi_goal.flightMode, "POI_HOLD")
        assert_eq(poi_goal.poiPos.x, 650)

        -- POI_HOLD completes at 17000ms -> REPEAT wraps to index 3 (skipping BOTH ACT_SYS_ARM and ACT_TKL_TAKEOFF_VERT!)
        local st3 = eng:step_telemetry({ fsmState = "POI_HOLD", dynamics = { altitudeY = 140 }, navigation = { currentPos = { x = 600, z = -600 } } }, 17000)
        assert_eq(st3, "LOOPED")
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.active_index, 3)
    end)

    it("enforces DEC_HUMAN_AUTH CONFIRM gate, DEC_EMCON flag, DEC_ENERGY_ECO speed, and dynamic PRECONDITION_FAILED", function()
        local eng = create_engine_fixture()
        assert_true(eng:load_table({
            missionId = "DEC_AND_PRECOND_TEST",
            version = "2.0.0",
            defaults = { cruiseSpeed = 20.0, targetAlt = 150.0 },
            checkpoints = {
                {
                    checkpointId = "CP_ECO",
                    action = "ACT_NAV_SPLINE_WP",
                    decorators = {
                        { decoratorId = "DEC_EMCON" },
                        { decoratorId = "DEC_ENERGY_ECO" },
                        { decoratorId = "DEC_SMOOTH_TRAJ" },
                    },
                    params = { targetPos = { x = 100, z = 0 }, acceptanceRadius = 10 },
                    preconditions = { minFuel = 0.40 },
                },
                {
                    checkpointId = "CP_AUTH",
                    action = "ACT_PAY_BUS_CMD",
                    decorators = { { decoratorId = "DEC_HUMAN_AUTH" } },
                    params = { channelOffset = 20, command = "RELEASE_BAY", waitForAck = true, expectedStatus = "DROPPED" },
                },
            },
        }))

        -- Precondition check passes at 0.80 fuel
        eng:step_telemetry({ fuel = 0.80, navigation = { currentPos = { x = 0, z = 0 } } }, 900)
        assert_true(eng:start("SINGLE", 1000))
        local goal1 = eng:get_trajectory_goal()
        assert_true(goal1.emconActive)
        assert_eq(goal1.constraintProfile, "STRICT_LEVEL")
        assert_true(goal1.targetSpeed < 20.0)

        -- Advance to CP_AUTH -> pauses in waitingHumanAuth until confirm()
        local st1 = eng:step_telemetry({ fsmState = "CRUISE", fuel = 0.80, navigation = { currentPos = { x = 100, z = 0 } } }, 1200)
        assert_eq(st1, "ADVANCED")
        assert_eq(eng.active_index, 2)
        assert_true(eng.waitingHumanAuth)

        -- Calling confirm() releases DEC_HUMAN_AUTH gate and dispatches ACT_PAY_BUS_CMD
        assert_true(eng:confirm(1300))
        assert_false(eng.waitingHumanAuth)

        -- Dynamic precondition failure returns PRECONDITION_FAILED and transitions to SUSPENDED/ABORTED
        local eng_fail = create_engine_fixture()
        assert_true(eng_fail:load_table({
            missionId = "PRECOND_FAIL",
            version = "2.0.0",
            fallbackPolicy = "HOVER_HOLD",
            checkpoints = {
                {
                    checkpointId = "CP_HIGH_FUEL",
                    action = "ACT_NAV_GOTO_WP",
                    params = { targetPos = { x = 50, z = 50 } },
                    preconditions = { minFuel = 0.90 },
                },
            },
        }))
        eng_fail:step_telemetry({ fuel = 0.50, navigation = { currentPos = { x = 0, z = 0 } } }, 900)
        local ok_s, err_s = eng_fail:start("SINGLE", 1000)
        assert_false(ok_s)
        assert_eq(err_s, "PRECONDITION_FAILED")
        assert_eq(eng_fail.state, "ABORTED")
        assert_eq(eng_fail:get_fallback_goal().flightMode, "HOVER_HOLD")
    end)

    it("delegates abortWhen fallbackPolicy (SKIP_NEXT, RTH, HOVER_HOLD, LOITER) and cleans up Zone 3 on abort/stop", function()
        local eng, net, m, rs = create_engine_fixture()
        assert_true(eng:load_table({
            missionId = "ABORT_TEST",
            version = "2.0.0",
            fallbackPolicy = "RTH",
            checkpoints = {
                {
                    checkpointId = "CP_SKIP",
                    action = "ACT_PAY_BUS_CMD",
                    params = { channelOffset = 20, command = "DROP", waitForAck = true },
                    fallbackPolicy = "SKIP_NEXT",
                    abortWhen = { logic = "ANY", conditions = { { type = "TIMEOUT_SEC", timeout = 5 } } },
                },
                {
                    checkpointId = "CP_RTH",
                    action = "ACT_NAV_GOTO_WP",
                    params = { targetPos = { x = 1000, z = 1000 }, targetAlt = 150 },
                    onAbort = { { type = "REDSTONE_SET", side = "right", state = true } },
                    abortWhen = { logic = "ANY", conditions = { { type = "FUEL_LEVEL_BELOW", threshold = 0.25 } } },
                },
            },
        }))

        assert_true(eng:start("SINGLE", 1000))
        assert_true(net.openPayloadChannels[10020])
        assert_true(m.isOpen(10020))

        local st_skip = eng:tick(6000)
        assert_eq(st_skip, "SKIPPED")
        assert_nil(net.openPayloadChannels[10020])
        assert_true(m.isOpen(10020))
        assert_eq(eng.checkpoints[1].status, "ABORTED")
        assert_eq(eng.active_index, 2)
        assert_eq(eng.state, "EN_ROUTE")

        local st_rth = eng:step_telemetry({ fsmState = "CRUISE", fuel = 0.20, dynamics = { altitudeY = 150 }, navigation = { currentPos = { x = 100, z = 100 } } }, 7000)
        assert_eq(st_rth, "ABORTED")
        assert_eq(eng.state, "ABORTED")
        assert_true(rs.getOutput("right"))
        assert_eq(eng:get_fallback_goal().flightMode, "FAILSAFE_RTH")

        eng.checkpoints[2].fallbackPolicy = "HOVER_HOLD"
        eng:goto_index(2, 8000)
        eng:step_telemetry({ fsmState = "CRUISE", fuel = 0.20, dynamics = { altitudeY = 150 }, navigation = { currentPos = { x = 100, z = 100 } } }, 8100)
        assert_eq(eng:get_fallback_goal().flightMode, "HOVER_HOLD")

        eng.checkpoints[2].fallbackPolicy = "LOITER"
        eng:goto_index(2, 9000)
        eng:step_telemetry({ fsmState = "CRUISE", fuel = 0.20, dynamics = { altitudeY = 150 }, navigation = { currentPos = { x = 100, z = 100 } } }, 9100)
        assert_eq(eng:get_fallback_goal().flightMode, "LOITER")
    end)

    it("transitions pause/resume through SUSPENDED, rejects deferred actions at runtime, and expires onAbort REDSTONE_PULSE", function()
        local eng, _, m, rs = create_engine_fixture()
        assert_true(eng:load_table({
            missionId = "SUSPEND_TEST",
            version = "2.0.0",
            checkpoints = {
                {
                    checkpointId = "CP_01",
                    action = "ACT_NAV_SPLINE_WP",
                    params = { targetPos = { x = 100, z = 100 } },
                    onAbort = { { type = "REDSTONE_PULSE", side = "left", durationMs = 600 } },
                },
            },
        }))
        assert_true(eng:start("SINGLE", 1000))
        assert_eq(eng.state, "EN_ROUTE")

        assert_true(eng:pause())
        assert_eq(eng.state, "SUSPENDED")
        assert_false(eng:pause())
        assert_eq(eng:get_fallback_goal().flightMode, "LOITER")

        assert_true(eng:resume(1500))
        assert_eq(eng.state, "EN_ROUTE")
        assert_false(eng:resume(1600))
        assert_eq(eng:get_trajectory_goal().flightMode, "CRUISE")

        table.insert(eng.checkpoints, { checkpointId = "CP_DEF_RUNWAY", action = "ACT_TKL_TAKEOFF_RWY", params = {} })
        local ok_goto, err_goto = eng:goto_index(2, 2000)
        assert_false(ok_goto)
        assert_eq(err_goto, "DEFERRED_ACTION_UNSUPPORTED")
        assert_eq(eng.state, "ABORTED")

        eng:start("SINGLE", 3000)
        eng:stop(3500)
        assert_true(rs.getOutput("left"))
        eng:tick(3800)
        assert_true(rs.getOutput("left"))
        eng:tick(4100)
        assert_false(rs.getOutput("left"))
    end)

    it("resets touchdownArmed in start() and handles malformed currentPos = {} cleanly", function()
        local eng = create_engine_fixture()
        assert_true(eng:load_table({
            missionId = "LAND_RESTART_TEST",
            version = "2.0.0",
            checkpoints = {
                { checkpointId = "CP_LAND", action = "ACT_TKL_LAND_PREC", params = { facilityId = "PAD_01" } },
            },
        }))
        assert_true(eng:start("SINGLE", 1000))
        eng:step_telemetry({ fsmState = "APPROACH_LAND" }, 1500)
        assert_true(eng.touchdownArmed)

        local st1 = eng:step_telemetry({ fsmState = "DISARMED" }, 2000)
        assert_eq(st1, "COMPLETED")
        assert_eq(eng.state, "COMPLETED")

        assert_true(eng:start("SINGLE", 3000))
        assert_false(eng.touchdownArmed)
        local st2 = eng:step_telemetry({ fsmState = "DISARMED" }, 3100)
        assert_eq(st2, "ACTIVE")
        assert_eq(eng.state, "EN_ROUTE")

        local eng_gps = create_engine_fixture()
        assert_true(eng_gps:load_table({
            missionId = "GPS_LOSS_TEST",
            version = "2.0.0",
            checkpoints = {
                { checkpointId = "CP_CORR", action = "ACT_NAV_CORRIDOR", params = { startPos = { x = 0, z = 0 }, endPos = { x = 100, z = 0 } } },
            },
        }))
        assert_true(eng_gps:start("SINGLE", 1000))
        local st_gps = eng_gps:step_telemetry({ fsmState = "CRUISE", navigation = { currentPos = {} } }, 1200)
        assert_eq(st_gps, "ACTIVE")
    end)

    it("executes DEC_TIMEOUT_GUARD, DEC_RETRY_N, eco/smooth overrides, and newly wired ACT_* handlers", function()
        local eng = create_engine_fixture()
        assert_true(eng:load_table({
            missionId = "DECORATOR_AND_ACT_TEST",
            version = "2.0.0",
            fallbackPolicy = "HOVER_HOLD",
            checkpoints = {
                {
                    checkpointId = "CP_HOME",
                    action = "ACT_SYS_SET_HOME",
                    params = { targetPos = { x = 10, z = 20 } },
                },
                {
                    checkpointId = "CP_ROI",
                    action = "ACT_PAY_SET_ROI",
                    params = { poiPos = { x = 400, y = 70, z = 400 } },
                },
                {
                    checkpointId = "CP_MC2FW",
                    action = "ACT_TKL_TRANS_MC2FW",
                    decorators = {
                        { decoratorId = "DEC_ENERGY_ECO", overrideParams = { ecoCruiseSpeed = 11.5 } },
                        { decoratorId = "DEC_SMOOTH_TRAJ", overrideParams = { maxYawRateDegS = 15.0 } },
                        { decoratorId = "DEC_TIMEOUT_GUARD", overrideParams = { maxDurationSec = 4 } },
                        { decoratorId = "DEC_RETRY_N", overrideParams = { maxAttempts = 2 } },
                    },
                    params = { targetAlt = 180 },
                },
            },
        }))
        assert_true(eng:start("SINGLE", 1000))
        -- ACT_SYS_SET_HOME immediate -> step_telemetry advances to ACT_PAY_SET_ROI then ACT_TKL_TRANS_MC2FW
        assert_eq(eng.homePos.x, 10)
        assert_eq(eng:step_telemetry({ fsmState = "IDLE_ARMED" }, 1100), "ADVANCED")
        assert_eq(eng.activeRoi.x, 400)
        assert_eq(eng:step_telemetry({ fsmState = "IDLE_ARMED" }, 1200), "ADVANCED")

        local g = eng:get_trajectory_goal()
        assert_eq(g.transitionMode, "MC2FW")
        assert_eq(g.targetSpeed, 11.5)
        assert_eq(g.maxYawRateDegPerSec, 15.0)

        -- First timeout triggers DEC_RETRY_N attempt 2
        local r1 = eng:tick(5200)
        assert_eq(r1, "RETRYING")
        assert_eq(eng.state, "EN_ROUTE")

        -- Second timeout exceeds maxAttempts=2 -> ABORTED
        local r2 = eng:tick(9200)
        assert_eq(r2, "ABORTED")
        assert_eq(eng.state, "ABORTED")
        assert_eq(eng:get_fallback_goal().flightMode, "HOVER_HOLD")
    end)

    it("resolves nearest free landing facility for ACT_TKL_LAND_NEAREST and handles missing facility with DEC_RETRY_N", function()
        local facility_client = require("facility_client")
        local facState = facility_client.init({ arrivalRadius = 15.0 })
        facility_client.update_beacons(facState, {
            sectorId = "SEC_1",
            gacChannel = 50201,
            facilities = {
                { facilityId = "PAD_DED", facilityType = "LANDING_PAD", status = "FREE", position = { x = 5, y = 64, z = 5 }, dedicated = true },
                { facilityId = "PAD_ALPHA", facilityType = "LANDING_PAD", status = "FREE", position = { x = 120, y = 65, z = -50 }, dedicated = false },
                { facilityId = "PAD_FAR", facilityType = "LANDING_PAD", status = "FREE", position = { x = 900, y = 70, z = 0 }, dedicated = false },
            },
        }, 1000)

        local eng = create_engine_fixture({ fac = facState })
        assert_true(eng:load_table({
            missionId = "LAND_NEAREST_OK",
            version = "2.0.0",
            checkpoints = {
                {
                    checkpointId = "CP_NEAREST",
                    action = "ACT_TKL_LAND_NEAREST",
                    params = { facilityTypeFilter = "LANDING_PAD", maxRangeM = 300 },
                },
            },
        }))
        eng.lastMfd = { fsmState = "CRUISE", navigation = { currentPos = { x = 100, z = -40 } } }
        assert_true(eng:start("SINGLE", 1200))
        local goal = eng:get_trajectory_goal()
        assert_not_nil(goal)
        assert_eq(goal.flightMode, "LANDING")
        assert_eq(goal.facilityId, "PAD_ALPHA")
        assert_eq(goal.targetPos.x, 120)
        assert_eq(goal.targetAlt, 65)

        eng:step_telemetry({ fsmState = "APPROACH_LAND" }, 1300)
        assert_eq(eng:step_telemetry({ fsmState = "DISARMED" }, 1500), "COMPLETED")

        -- No facility available with DEC_RETRY_N(2): retries cleanly on tick without stack overflow
        local emptyFac = facility_client.init({ arrivalRadius = 15.0 })
        local eng2 = create_engine_fixture({ fac = emptyFac })
        assert_true(eng2:load_table({
            missionId = "LAND_NEAREST_RETRY",
            version = "2.0.0",
            fallbackPolicy = "RTH",
            checkpoints = {
                {
                    checkpointId = "CP_RETRY",
                    action = "ACT_TKL_LAND_NEAREST",
                    decorators = { { decoratorId = "DEC_RETRY_N", overrideParams = { maxAttempts = 2 } } },
                    params = { facilityTypeFilter = "RUNWAY" },
                },
            },
        }))
        eng2.lastMfd = { fsmState = "CRUISE", navigation = { currentPos = { x = 0, z = 0 } } }
        local ok_s = eng2:start("SINGLE", 2000)
        assert_true(ok_s)
        local t1 = eng2:tick(2050)
        assert_eq(t1, "RETRYING")
        local t2 = eng2:tick(2100)
        assert_eq(t2, "ABORTED")
        assert_eq(eng2.state, "ABORTED")
        assert_eq(eng2:get_fallback_goal().flightMode, "FAILSAFE_RTH")
    end)

    it("passes preconditions.channelBound for ACQUIRED_OFFLINE while rejecting LOCKED_NO_GCS", function()
        local mission = {
            missionId = "OFFLINE_LEASE_PRECOND",
            version = "2.0.0",
            fallbackPolicy = "HOVER_HOLD",
            checkpoints = {
                {
                    checkpointId = "CP_OFFLINE",
                    action = "ACT_NAV_GOTO_WP",
                    params = { targetPos = { x = 100, z = 200 } },
                    preconditions = { channelBound = true },
                },
            },
        }

        local eng_ok = create_engine_fixture({
            sentinel = { status = "ACQUIRED_OFFLINE", locked = false, baseChannel = 10040 },
        })
        assert_true(eng_ok:load_table(mission))
        local ok_off, err_off = eng_ok:start("SINGLE", 1000)
        assert_true(ok_off, tostring(err_off))
        assert_eq(eng_ok.state, "EN_ROUTE")

        local eng_locked = create_engine_fixture({
            sentinel = { status = "LOCKED_NO_GCS", locked = true, baseChannel = 10000 },
        })
        assert_true(eng_locked:load_table(mission))
        local ok_lock, err_lock = eng_locked:start("SINGLE", 1000)
        assert_false(ok_lock)
        assert_eq(err_lock, "PRECONDITION_FAILED")
        assert_eq(eng_locked.state, "ABORTED")
    end)
end)
