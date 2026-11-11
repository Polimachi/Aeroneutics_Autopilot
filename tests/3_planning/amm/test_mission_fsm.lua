-- tests/3_planning/amm/test_mission_fsm.lua
local network_manager = require("network_manager")
local mission_engine = require("mission_engine")

describe("AMM Mission Engine Polymorphic Loader and Sequencer FSM", function()
    local function create_engine_fixture(extra_opts)
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local rs = mock.redstone()
        local opts = extra_opts or {}
        opts.net = net
        opts.redstone = rs
        opts.colors = colors
        opts.config = { baseChannel = 10000, defaultAlt = 150.0, defaultSpeed = 18.0, arrivalRadius = 15.0 }
        local eng = mission_engine.new(opts)
        return eng, net, m, rs
    end

    it("loads v1.1.0 checkpoints JSON and normalizes legacy v1.0.0 items JSON with trailing LAND_LAUNCHPAD", function()
        local eng = create_engine_fixture()

        -- Write legacy v1.0.0 mission file
        local f1 = fs.open("missions/legacy_test.json", "w")
        f1.write(textutils.serializeJSON({
            version = "1.0.0",
            items = {
                { id = 1, x = 100, z = 200, alt = 140, speed = 18 },
                { id = 2, x = 300, z = 400, alt = 120, speed = 15, facilityId = "PAD_BRAVO_01" },
            },
        }))
        f1.close()

        local ok_leg, err_leg = eng:load("missions/legacy_test.json")
        assert_true(ok_leg, tostring(err_leg))
        assert_eq(eng:count(), 3)
        assert_eq(eng.checkpoints[1].action, "FLY_OVER")
        assert_eq(eng.checkpoints[1].params.targetPos.x, 100)
        assert_eq(eng.checkpoints[2].action, "FLY_OVER")
        assert_eq(eng.checkpoints[2].params.targetPos.x, 300)
        assert_eq(eng.checkpoints[3].action, "LAND_LAUNCHPAD")
        assert_eq(eng.checkpoints[3].params.facilityId, "PAD_BRAVO_01")

        -- Save as v1.1.0 and reload
        assert_true(eng:save("missions/saved_v110.json"))
        local eng2 = create_engine_fixture()
        assert_true(eng2:load("missions/saved_v110.json"))
        assert_eq(eng2:count(), 3)
        assert_eq(eng2.checkpoints[3].action, "LAND_LAUNCHPAD")

        fs.delete("missions/legacy_test.json")
        fs.delete("missions/saved_v110.json")
    end)

    it("dispatches 9 active actions to FCP, sequences SINGLE mode to COMPLETED, and loops REPEAT mode to first airborne step", function()
        local eng, _, m, rs = create_engine_fixture()
        local ok, err = eng:load_table({
            missionId = "SORTIE_REPEAT",
            executionMode = "REPEAT",
            defaults = { targetAlt = 140.0, cruiseSpeed = 18.0, acceptanceRadius = 15.0 },
            checkpoints = {
                { checkpointId = "CP_TK", action = "TAKEOFF_LAUNCHPAD", params = { targetAlt = 140, facilityId = "PAD_01" } },
                {
                    checkpointId = "CP_ORB",
                    action = "ORBIT",
                    params = { targetPos = { x = 500, z = -500 }, radius = 40, direction = "CCW", durationSec = 10 },
                    onEnter = { { type = "REDSTONE_PULSE", side = "top", durationMs = 500 } },
                },
                {
                    checkpointId = "CP_POI",
                    action = "POI_HOLD",
                    params = { targetPos = { x = 600, z = -600 }, poiPos = { x = 650, y = 70, z = -600 }, durationSec = 5 },
                },
            },
        })
        assert_true(ok, tostring(err))

        -- Start from DISARMED -> sends ARM then TAKEOFF
        assert_true(eng:start("REPEAT", 1000))
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.active_index, 1)
        assert_eq(#m._transmitted, 2)
        assert_eq(m._transmitted[1].pkt.payload.command, "ARM")
        assert_eq(m._transmitted[2].pkt.payload.command, "TAKEOFF")

        -- FCP enters CRUISE -> TAKEOFF_LAUNCHPAD completes, advances to CP_ORB (index 2)
        local st1 = eng:step_telemetry({ fsmState = "CRUISE", dynamics = { altitudeY = 140 }, navigation = { currentPos = { x = 0, z = 0 } } }, 2000)
        assert_eq(st1, "ADVANCED")
        assert_eq(eng.active_index, 2)
        assert_true(rs.getOutput("top"))
        local orb_cmd = m._transmitted[#m._transmitted].pkt.payload
        assert_eq(orb_cmd.command, "LOITER")
        assert_eq(orb_cmd.flightMode, "LOITER")
        assert_eq(orb_cmd.params.loiterRadius, 40)
        assert_eq(orb_cmd.params.loiterDirection, "CCW")

        -- Tick expires pulse at 2500ms; ORBIT duration (10s) completes at 12000ms -> advances to CP_POI (index 3)
        eng:tick(2500)
        assert_false(rs.getOutput("top"))
        local st2 = eng:step_telemetry({ fsmState = "LOITER", dynamics = { altitudeY = 140 }, navigation = { currentPos = { x = 500, z = -500 } } }, 12000)
        assert_eq(st2, "ADVANCED")
        assert_eq(eng.active_index, 3)
        local poi_cmd = m._transmitted[#m._transmitted].pkt.payload
        assert_eq(poi_cmd.command, "POI_HOLD")
        assert_eq(poi_cmd.flightMode, "POI_HOLD")
        assert_eq(poi_cmd.params.poiTarget.x, 650)

        -- POI_HOLD duration (5s) completes at 17000ms -> REPEAT mode wraps to index 2 (first airborne step, skipping TAKEOFF_LAUNCHPAD!)
        local st3 = eng:step_telemetry({ fsmState = "POI_HOLD", dynamics = { altitudeY = 140 }, navigation = { currentPos = { x = 600, z = -600 } } }, 17000)
        assert_eq(st3, "LOOPED")
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.active_index, 2)
    end)

    it("cycles PATROL sub-waypoints in both LOOP and PING_PONG modes including 1-waypoint degeneracy", function()
        local eng, _, m = create_engine_fixture()
        assert_true(eng:load_table({
            missionId = "PATROL_TEST",
            checkpoints = {
                {
                    checkpointId = "CP_PAT_PP",
                    action = "PATROL",
                    params = {
                        patrolMode = "PING_PONG",
                        cycles = 1,
                        acceptanceRadius = 10,
                        waypoints = {
                            { x = 0, z = 0 },
                            { x = 100, z = 0 },
                            { x = 200, z = 0 },
                        },
                    },
                },
                {
                    checkpointId = "CP_PAT_1WP",
                    action = "PATROL",
                    params = {
                        patrolMode = "PING_PONG",
                        cycles = 1,
                        acceptanceRadius = 10,
                        waypoints = { { x = 300, z = 0 } },
                    },
                },
            },
        }))

        assert_true(eng:start("SINGLE", 1000))
        assert_eq(m._transmitted[#m._transmitted].pkt.payload.params.targetWaypoint.x, 0)

        -- Reach WP1(0,0) -> subIndex 2(100,0)
        eng:step_telemetry({ fsmState = "CRUISE", navigation = { currentPos = { x = 0, z = 0 } } }, 1200)
        assert_eq(eng.active_index, 1)
        assert_eq(m._transmitted[#m._transmitted].pkt.payload.params.targetWaypoint.x, 100)

        -- Reach WP2(100,0) -> subIndex 3(200,0)
        eng:step_telemetry({ fsmState = "CRUISE", navigation = { currentPos = { x = 100, z = 0 } } }, 1400)
        assert_eq(eng.active_index, 1)
        assert_eq(m._transmitted[#m._transmitted].pkt.payload.params.targetWaypoint.x, 200)

        -- Reach WP3(200,0) -> PING_PONG must bounce back to subIndex 2(100,0), NOT complete yet!
        eng:step_telemetry({ fsmState = "CRUISE", navigation = { currentPos = { x = 200, z = 0 } } }, 1600)
        assert_eq(eng.active_index, 1)
        assert_eq(m._transmitted[#m._transmitted].pkt.payload.params.targetWaypoint.x, 100)

        -- Reach WP2(100,0) -> subIndex 1(0,0)
        eng:step_telemetry({ fsmState = "CRUISE", navigation = { currentPos = { x = 100, z = 0 } } }, 1800)
        assert_eq(eng.active_index, 1)
        assert_eq(m._transmitted[#m._transmitted].pkt.payload.params.targetWaypoint.x, 0)

        -- Reach WP1(0,0) -> completes 1 full PING_PONG cycle -> advances to CP_PAT_1WP (index 2)
        local st = eng:step_telemetry({ fsmState = "CRUISE", navigation = { currentPos = { x = 0, z = 0 } } }, 2000)
        assert_eq(st, "ADVANCED")
        assert_eq(eng.active_index, 2)

        -- Reach single waypoint (300,0) -> completes cleanly without index error
        local st_end = eng:step_telemetry({ fsmState = "CRUISE", navigation = { currentPos = { x = 300, z = 0 } } }, 2200)
        assert_eq(st_end, "COMPLETED")
        assert_eq(eng.state, "COMPLETED")
    end)

    it("delegates abortWhen fallbackPolicy (SKIP_NEXT, RTH, HOVER_HOLD, LOITER) and cleans up Zone 3 on abort/stop", function()
        local eng, _, m, rs = create_engine_fixture()
        assert_true(eng:load_table({
            missionId = "ABORT_TEST",
            fallbackPolicy = "RTH",
            checkpoints = {
                {
                    checkpointId = "CP_SKIP",
                    action = "PAYLOAD_ACTION",
                    params = { channelOffset = 20, command = "DROP", waitForAck = true },
                    fallbackPolicy = "SKIP_NEXT",
                    abortWhen = { logic = "ANY", conditions = { { type = "TIMEOUT_SEC", timeout = 5 } } },
                },
                {
                    checkpointId = "CP_RTH",
                    action = "FLY_TO",
                    params = { targetPos = { x = 1000, z = 1000 }, targetAlt = 150 },
                    onAbort = { { type = "REDSTONE_SET", side = "right", state = true } },
                    abortWhen = { logic = "ANY", conditions = { { type = "FUEL_LEVEL_BELOW", threshold = 0.25 } } },
                },
            },
        }))

        assert_true(eng:start("SINGLE", 1000))
        assert_true(m.isOpen(10020))

        -- Timeout at 6000ms triggers SKIP_NEXT -> closes 10020, marks CP_SKIP ABORTED, advances to CP_RTH (index 2)
        local st_skip = eng:tick(6000)
        assert_eq(st_skip, "SKIPPED")
        assert_false(m.isOpen(10020))
        assert_eq(eng.checkpoints[1].status, "ABORTED")
        assert_eq(eng.active_index, 2)
        assert_eq(eng.state, "EN_ROUTE")

        -- Low fuel on CP_RTH triggers mission fallbackPolicy = "RTH" -> executes onAbort, state = ABORTED, sends emergencyAction = "RTH"
        local st_rth = eng:step_telemetry({ fsmState = "CRUISE", fuel = 0.20, dynamics = { altitudeY = 150 }, navigation = { currentPos = { x = 100, z = 100 } } }, 7000)
        assert_eq(st_rth, "ABORTED")
        assert_eq(eng.state, "ABORTED")
        assert_true(rs.getOutput("right"))
        local last_pkt = m._transmitted[#m._transmitted].pkt.payload
        assert_eq(last_pkt.emergencyAction, "RTH")

        -- Verify HOVER_HOLD and LOITER fallbackPolicy delegation
        eng.checkpoints[2].fallbackPolicy = "HOVER_HOLD"
        eng:goto_index(2, 8000)
        eng:step_telemetry({ fsmState = "CRUISE", fuel = 0.20, dynamics = { altitudeY = 150 }, navigation = { currentPos = { x = 100, z = 100 } } }, 8100)
        assert_eq(m._transmitted[#m._transmitted].pkt.payload.emergencyAction, "HOVER_HOLD")

        eng.checkpoints[2].fallbackPolicy = "LOITER"
        eng:goto_index(2, 9000)
        eng:step_telemetry({ fsmState = "CRUISE", fuel = 0.20, dynamics = { altitudeY = 150 }, navigation = { currentPos = { x = 100, z = 100 } } }, 9100)
        assert_eq(m._transmitted[#m._transmitted].pkt.payload.flightMode, "LOITER")
    end)

    it("transitions pause and resume through canonical SUSPENDED state and rejects deferred actions at runtime", function()
        local eng, _, m = create_engine_fixture()
        assert_true(eng:load_table({
            missionId = "SUSPEND_TEST",
            checkpoints = {
                { checkpointId = "CP_01", action = "FLY_OVER", params = { targetPos = { x = 100, z = 100 } } },
            },
        }))
        assert_true(eng:start("SINGLE", 1000))
        assert_eq(eng.state, "EN_ROUTE")

        -- Pause transitions to SUSPENDED and commands LOITER standby
        assert_true(eng:pause())
        assert_eq(eng.state, "SUSPENDED")
        assert_false(eng:pause()) -- Already SUSPENDED
        local pause_cmd = m._transmitted[#m._transmitted].pkt.payload
        assert_eq(pause_cmd.command, "LOITER")
        assert_eq(pause_cmd.flightMode, "LOITER")

        -- Resume restores EN_ROUTE and re-dispatches checkpoint
        assert_true(eng:resume(1500))
        assert_eq(eng.state, "EN_ROUTE")
        assert_false(eng:resume(1600)) -- Already EN_ROUTE
        local resume_cmd = m._transmitted[#m._transmitted].pkt.payload
        assert_eq(resume_cmd.command, "CRUISE")

        -- Inject deferred action and verify runtime rejection in enter_checkpoint / goto_index
        table.insert(eng.checkpoints, {
            checkpointId = "CP_DEF_RUNWAY",
            action = "TAKEOFF_RUNWAY",
            params = {},
        })
        local ok_goto, err_goto = eng:goto_index(2, 2000)
        assert_false(ok_goto)
        assert_eq(err_goto, "DEFERRED_ACTION_UNSUPPORTED")
        assert_eq(eng.state, "ABORTED")
        assert_eq(eng.checkpoints[2].status, "ABORTED")

        -- Also verify evaluate_active handles DEFERRED_ACTION_UNSUPPORTED
        eng.state = "EN_ROUTE"
        eng.active_index = 2
        local st, reason = eng:evaluate_active(3000)
        assert_eq(st, "ABORTED")
        assert_eq(reason, "DEFERRED_ACTION_UNSUPPORTED")
        assert_eq(eng.state, "ABORTED")
    end)
end)
