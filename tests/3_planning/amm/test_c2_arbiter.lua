-- tests/3_planning/amm/test_c2_arbiter.lua
local waypoint_queue = require("waypoint_queue")
local network_manager = require("network_manager")
local c2_arbiter = require("c2_arbiter")

describe("AMM C2 Arbiter (c2_arbiter), Authority Switching & Queue FSM", function()
    local function create_fixture()
        local q = waypoint_queue.new({ defaultAlt = 150, defaultSpeed = 18, arrivalRadius = 15 })
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local transmitted = {}
        net.modem = {
            transmit = function(chan, reply_chan, payload)
                table.insert(transmitted, { chan = chan, payload = payload })
            end
        }
        local arb = c2_arbiter.new(q, net)
        return q, net, arb, transmitted
    end

    it("initializes with PILOT_PRIMARY authority and idle state", function()
        local q, net, arb = create_fixture()
        assert_eq(arb.authority, "PILOT_PRIMARY")
        assert_eq(q.state, "IDLE")
    end)

    it("suspends queue and adopts GCS_OVERRIDE without retransmitting on Base+0", function()
        local q, net, arb, tx = create_fixture()
        q:add(100, 200)
        assert_eq(q.state, "EN_ROUTE")

        local gcs_packet = {
            ver = "1.9.5",
            type = "MSG_OPERATOR_CMD",
            payload = {
                authority = "GCS_OVERRIDE",
                command = "LOITER",
                flightMode = "LOITER",
                emergencyAction = "NONE"
            }
        }
        arb:handle_gcs_packet(gcs_packet)
        assert_eq(arb.authority, "GCS_OVERRIDE")
        assert_eq(q.state, "SUSPENDED")
        -- Non-loopback check: tx must remain empty!
        assert_eq(#tx, 0)
    end)

    it("restores PILOT_PRIMARY and dispatches command upon pilot action", function()
        local q, net, arb, tx = create_fixture()
        arb.authority = "GCS_OVERRIDE"

        arb:handle_pilot_action("HOLD")
        assert_eq(arb.authority, "PILOT_PRIMARY")
        assert_eq(q.state, "SUSPENDED")
        assert_eq(#tx, 1)
        assert_eq(tx[1].payload.payload.emergencyAction, "HOVER_HOLD")
        assert_eq(tx[1].payload.payload.authority, "PILOT_PRIMARY")
    end)

    it("coordinates ground-to-air handover waiting for FCP CRUISE state", function()
        local q, net, arb, tx = create_fixture()
        q:add(500, 500, 150, 20)

        -- Pilot commands TAKEOFF
        arb:handle_pilot_action("TAKEOFF", { targetAlt = 150 })
        assert_eq(#tx, 1)
        assert_eq(tx[1].payload.payload.command, "TAKEOFF")
        assert_true(arb.fcpTakeoffActive)

        -- FCP still taking off
        arb:handle_mfd_state({
            payload = {
                fsmState = "TAKEOFF",
                navigation = { currentPos = { x = 0, z = 0 } }
            }
        })
        assert_eq(#tx, 1) -- WP1 not dispatched yet

        -- FCP reaches clearance altitude and transitions to CRUISE
        arb:handle_mfd_state({
            payload = {
                fsmState = "CRUISE",
                navigation = { currentPos = { x = 0, z = 0 } }
            }
        })
        assert_false(arb.fcpTakeoffActive)
        assert_eq(#tx, 2)
        assert_eq(tx[2].payload.payload.command, "CRUISE")
        assert_eq(tx[2].payload.payload.params.targetWaypoint.x, 500)
    end)

    it("handles waypoint arrival and final landing/loiter transitions", function()
        local q, net, arb, tx = create_fixture()
        q:add(100, 100)
        q:add(200, 200, 120, 15, "PAD_BRAVO_01")

        -- Craft arrives at WP1
        arb:handle_mfd_state({
            payload = {
                fsmState = "CRUISE",
                navigation = { currentPos = { x = 100, z = 100 } }
            }
        })
        -- Should advance and transmit WP2
        assert_true(#tx >= 1)
        local last_tx = tx[#tx].payload.payload
        assert_eq(last_tx.params.targetWaypoint.x, 200)

        -- Craft arrives at WP2 (final waypoint with facilityId)
        arb:handle_mfd_state({
            payload = {
                fsmState = "CRUISE",
                navigation = { currentPos = { x = 200, z = 200 } }
            }
        })
        assert_eq(q.state, "COMPLETED")
        local final_tx = tx[#tx].payload.payload
        assert_eq(final_tx.flightMode, "LANDING")
        assert_eq(final_tx.params.designatedFacilityId, "PAD_BRAVO_01")
    end)

    it("arbitrates Base+0 MSG_MISSION_CMD (RUN, BUSY_REJECTED, forceRestart, FILE_NOT_FOUND, DEFERRED, STOP/PAUSE/RESUME/NEXT) and sends MSG_MISSION_ACK", function()
        local mission_engine = require("mission_engine")
        local q, net, arb, tx = create_fixture()
        local eng = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        arb:set_engine(eng)

        -- Write valid and deferred mission files
        local f_ok = fs.open("missions/patrol_alpha.json", "w")
        f_ok.write(textutils.serializeJSON({
            version = "2.0.0",
            missionId = "PATROL_ALPHA",
            checkpoints = {
                { checkpointId = "CP_01", action = "ACT_NAV_SPLINE_WP", params = { targetPos = { x = 100, z = 200 }, targetAlt = 150, cruiseSpeed = 18 } },
                { checkpointId = "CP_02", action = "ACT_PAT_LOITER_TIME", params = { targetPos = { x = 300, z = 400 }, radius = 35, direction = "CW" } },
            },
        }))
        f_ok.close()

        local f_def = fs.open("missions/runway_sortie.json", "w")
        f_def.write(textutils.serializeJSON({
            version = "2.0.0",
            missionId = "RUNWAY_SORTIE",
            checkpoints = {
                { checkpointId = "CP_RWY", action = "ACT_TKL_TAKEOFF_RWY", params = {} },
            },
        }))
        f_def.close()

        -- 0. PAUSE / RESUME while IDLE -> INVALID_CMD (INVALID_STATE_TRANSITION)
        arb:handle_gcs_packet({ ver = "1.9.5", type = "MSG_MISSION_CMD", payload = { action = "PAUSE" } }, 950)
        assert_eq(tx[#tx].payload.payload.status, "INVALID_CMD")
        assert_eq(tx[#tx].payload.payload.reason, "INVALID_STATE_TRANSITION")

        arb:handle_gcs_packet({ ver = "1.9.5", type = "MSG_MISSION_CMD", payload = { action = "RESUME" } }, 960)
        assert_eq(tx[#tx].payload.payload.status, "INVALID_CMD")
        assert_eq(tx[#tx].payload.payload.reason, "INVALID_STATE_TRANSITION")

        -- 1. Missing file -> FILE_NOT_FOUND
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "nonexistent_mission", executionMode = "SINGLE" },
        }, 1000)
        assert_eq(tx[#tx].payload.type, "MSG_MISSION_ACK")
        assert_eq(tx[#tx].payload.payload.status, "FILE_NOT_FOUND")

        -- 2. Deferred action -> DEFERRED_ACTION_UNSUPPORTED
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "runway_sortie", executionMode = "SINGLE" },
        }, 1100)
        assert_eq(tx[#tx].payload.type, "MSG_MISSION_ACK")
        assert_eq(tx[#tx].payload.payload.status, "DEFERRED_ACTION_UNSUPPORTED")

        -- 3. Valid RUN -> ACCEPTED, engine EN_ROUTE at index 1
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "patrol_alpha", executionMode = "SINGLE", forceRestart = false },
        }, 1200)
        local ack_run = tx[#tx].payload.payload
        assert_eq(ack_run.status, "ACCEPTED")
        assert_eq(ack_run.missionId, "PATROL_ALPHA")
        assert_eq(ack_run.missionState, "EN_ROUTE")
        assert_eq(ack_run.activeIndex, 1)
        assert_eq(ack_run.totalCheckpoints, 2)

        -- 3b. RESUME while already EN_ROUTE -> INVALID_CMD (INVALID_STATE_TRANSITION)
        arb:handle_gcs_packet({ ver = "1.9.5", type = "MSG_MISSION_CMD", payload = { action = "RESUME" } }, 1250)
        assert_eq(tx[#tx].payload.payload.status, "INVALID_CMD")
        assert_eq(tx[#tx].payload.payload.reason, "INVALID_STATE_TRANSITION")

        -- 3c. GCS_OVERRIDE suspends active engine and syncs eng.authority
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_OPERATOR_CMD",
            payload = {
                authority = "GCS_OVERRIDE",
                command = "LOITER",
                flightMode = "LOITER",
                emergencyAction = "NONE",
            },
        }, 1260)
        assert_eq(arb.authority, "GCS_OVERRIDE")
        assert_eq(eng.authority, "GCS_OVERRIDE")
        assert_eq(eng.state, "SUSPENDED")

        -- Pilot resumes mission control
        arb:handle_pilot_action("RESUME")
        assert_eq(arb.authority, "PILOT_PRIMARY")
        assert_eq(eng.authority, "PILOT_PRIMARY")
        assert_eq(eng.state, "EN_ROUTE")

        -- 4. Duplicate RUN while EN_ROUTE with forceRestart = false -> BUSY_REJECTED
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "patrol_alpha", forceRestart = false },
        }, 1300)
        assert_eq(tx[#tx].payload.payload.status, "BUSY_REJECTED")

        -- 5. NEXT -> advances to index 2 and replies ACCEPTED
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "NEXT" },
        }, 1400)
        assert_eq(tx[#tx].payload.payload.status, "ACCEPTED")
        assert_eq(tx[#tx].payload.payload.activeIndex, 2)

        -- 5b. RUN while EN_ROUTE with forceRestart = true -> resets to index 1 and replies ACCEPTED
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "patrol_alpha", forceRestart = true },
        }, 1450)
        assert_eq(tx[#tx].payload.payload.status, "ACCEPTED")
        assert_eq(tx[#tx].payload.payload.activeIndex, 1)

        -- 6. PAUSE / RESUME / STOP
        arb:handle_gcs_packet({ ver = "1.9.5", type = "MSG_MISSION_CMD", payload = { action = "PAUSE" } }, 1500)
        assert_eq(eng.state, "SUSPENDED")
        arb:handle_gcs_packet({ ver = "1.9.5", type = "MSG_MISSION_CMD", payload = { action = "RESUME" } }, 1600)
        assert_eq(eng.state, "EN_ROUTE")
        arb:handle_gcs_packet({ ver = "1.9.5", type = "MSG_MISSION_CMD", payload = { action = "STOP" } }, 1700)
        assert_eq(eng.state, "ABORTED")
        assert_eq(tx[#tx].payload.payload.missionState, "ABORTED")

        fs.delete("missions/patrol_alpha.json")
        fs.delete("missions/runway_sortie.json")
    end)

    it("maps SCHEMA_INVALID on bad mission JSON, resolves /disk paths, and preserves active flight on failed forceRestart", function()
        local mission_engine = require("mission_engine")
        local q, net, arb, tx = create_fixture()
        local eng = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        arb:set_engine(eng)

        if not fs.exists("/disk") then fs.makeDir("/disk") end
        local f_bad = fs.open("/disk/bad_schema.json", "w")
        f_bad.write(textutils.serializeJSON({
            version = "2.0.0",
            missionId = "BAD_SCHEMA",
            checkpoints = {
                { checkpointId = "CP_01", action = "ACT_NAV_SPLINE_WP", params = { targetPos = { x = 10, z = 20 } } },
                { checkpointId = "CP_02", action = "ACT_PAY_BUS_CMD", params = { channelOffset = 20 } }, -- missing command
            },
        }))
        f_bad.close()

        local f_disk = fs.open("/disk/disk_sortie.json", "w")
        f_disk.write(textutils.serializeJSON({
            version = "2.0.0",
            missionId = "DISK_SORTIE",
            checkpoints = {
                { checkpointId = "CP_01", action = "ACT_NAV_SPLINE_WP", params = { x = 400, z = -500 } },
            },
        }))
        f_disk.close()

        -- 1. Schema error -> SCHEMA_INVALID with CP#2 detail
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "/disk/bad_schema", executionMode = "SINGLE" },
        }, 1000)
        local ack_bad = tx[#tx].payload.payload
        assert_eq(ack_bad.status, "SCHEMA_INVALID")
        assert_true(string.find(tostring(ack_bad.reason), "CP#2", 1, true) ~= nil)

        -- 2. Valid /disk path without .json suffix -> ACCEPTED
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "/disk/disk_sortie", executionMode = "SINGLE" },
        }, 1100)
        assert_eq(tx[#tx].payload.payload.status, "ACCEPTED")
        assert_eq(eng.state, "EN_ROUTE")

        -- 3. Failed forceRestart targeting bad_schema must NOT stop active DISK_SORTIE
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "/disk/bad_schema.json", forceRestart = true },
        }, 1200)
        assert_eq(tx[#tx].payload.payload.status, "SCHEMA_INVALID")
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.missionId, "DISK_SORTIE")

        fs.delete("/disk/bad_schema.json")
        fs.delete("/disk/disk_sortie.json")
    end)

    it("emits E_STOP with ESTOP_CONFIRM_KEY and source AMM on ESTOP pilot action", function()
        local q, net, arb, tx = create_fixture()
        arb:handle_pilot_action("ESTOP", {}, 1000)
        assert_eq(#tx, 1)
        assert_eq(tx[1].payload.type, "MSG_EMERGENCY_OVERRIDE")
        assert_eq(tx[1].payload.payload.action, "E_STOP")
        assert_eq(tx[1].payload.payload.authKey, "ESTOP_CONFIRM_KEY")
        assert_eq(tx[1].payload.payload.source, "AMM")
        local goal = arb:get_effective_goal()
        assert_eq(goal.flightMode, "IDLE")
        assert_false(goal.arm)
    end)

    it("triggers FCP 500ms timeout raising alert banner and HOVER_HOLD fallback", function()
        local q, net, arb, tx = create_fixture()
        arb:handle_outer_loop_status({
            type = "MSG_OUTER_LOOP_STATUS",
            payload = { trackingStatus = "TRACKING", flightMode = "CRUISE" }
        }, 1000)
        assert_false(arb.fcpTimedOut)

        arb:check_timeouts(1400)
        assert_false(arb.fcpTimedOut)

        arb:check_timeouts(1600)
        assert_true(arb.fcpTimedOut)
        assert_true(string.find(arb.lastBanner, "FCP TIMEOUT") ~= nil)
        local goal = arb:get_effective_goal()
        assert_eq(goal.flightMode, "HOVER_HOLD")
    end)

    it("enforces fuel failsafe thresholds with FAILSAFE_RTH and EMERGENCY_LAND", function()
        local q, net, arb, tx = create_fixture()
        arb:handle_flight_telemetry({
            type = "MSG_FLIGHT_TELEMETRY",
            payload = { fuel = 0.25, activeSource = "FCP" }
        }, 1000)
        assert_nil(arb.emergencyGoal)

        -- Fuel drops below 0.20 -> FAILSAFE_RTH
        arb:handle_flight_telemetry({
            type = "MSG_FLIGHT_TELEMETRY",
            payload = { fuel = 0.18, activeSource = "FCP" }
        }, 1100)
        assert_not_nil(arb.emergencyGoal)
        assert_eq(arb.emergencyGoal.flightMode, "FAILSAFE_RTH")
        assert_true(string.find(arb.lastBanner, "LOW FUEL") ~= nil)

        -- Fuel drops below 0.10 -> EMERGENCY_LAND
        arb:handle_flight_telemetry({
            type = "MSG_FLIGHT_TELEMETRY",
            payload = { fuel = 0.08, activeSource = "FCP" }
        }, 1200)
        assert_eq(arb.emergencyGoal.flightMode, "EMERGENCY_LAND")
        assert_true(string.find(arb.lastBanner, "CRITICAL FUEL") ~= nil)
    end)

    it("propagates mission pause and abort fallbackPolicy goals through c2_arbiter:get_effective_goal for [I-12]", function()
        local mission_engine = require("mission_engine")
        local q, net, arb = create_fixture()
        local eng = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        arb:set_engine(eng)

        assert_true(eng:load_table({
            missionId = "FALLBACK_I12",
            version = "2.0.0",
            fallbackPolicy = "RTH",
            checkpoints = {
                {
                    checkpointId = "CP_1",
                    action = "ACT_NAV_GOTO_WP",
                    params = { targetPos = { x = 500, z = 500 }, targetAlt = 150 },
                    fallbackPolicy = "RTH",
                    abortWhen = { logic = "ANY", conditions = { { type = "TIMEOUT_SEC", timeout = 5 } } },
                },
                {
                    checkpointId = "CP_2",
                    action = "ACT_NAV_GOTO_WP",
                    params = { targetPos = { x = 800, z = 800 }, targetAlt = 150 },
                    fallbackPolicy = "HOVER_HOLD",
                    abortWhen = { logic = "ANY", conditions = { { type = "TIMEOUT_SEC", timeout = 5 } } },
                },
                {
                    checkpointId = "CP_3",
                    action = "ACT_NAV_GOTO_WP",
                    params = { targetPos = { x = 900, z = 900 }, targetAlt = 150 },
                    fallbackPolicy = "LOITER",
                    abortWhen = { logic = "ANY", conditions = { { type = "TIMEOUT_SEC", timeout = 5 } } },
                },
            },
        }))

        -- 1. Pause while EN_ROUTE -> LOITER standby goal with arm=true, flightActive=true
        assert_true(eng:start("SINGLE", 1000))
        eng:step_telemetry({ fsmState = "ACTIVE_TRACKING", navigation = { currentPos = { x = 10, y = 150, z = 10 } } }, 1050)
        assert_true(eng:pause())
        local g_pause = arb:get_effective_goal()
        assert_eq(g_pause.flightMode, "LOITER")
        assert_true(g_pause.arm)
        assert_true(g_pause.flightActive)

        -- 2. Resume restores EN_ROUTE CRUISE goal, then abort with RTH -> FAILSAFE_RTH
        assert_true(eng:resume(2000))
        assert_eq(arb:get_effective_goal().flightMode, "CRUISE")
        eng:tick(8000)
        assert_eq(eng.state, "ABORTED")
        local g_rth = arb:get_effective_goal()
        assert_eq(g_rth.flightMode, "FAILSAFE_RTH")
        assert_true(g_rth.arm)
        assert_true(g_rth.flightActive)

        -- 3. Abort with HOVER_HOLD -> HOVER_HOLD
        assert_true(eng:goto_index(2, 9000))
        assert_eq(arb:get_effective_goal().flightMode, "CRUISE")
        eng:tick(15000)
        assert_eq(eng.state, "ABORTED")
        local g_hover = arb:get_effective_goal()
        assert_eq(g_hover.flightMode, "HOVER_HOLD")
        assert_true(g_hover.arm)
        assert_true(g_hover.flightActive)

        -- 4. Abort with LOITER -> LOITER
        assert_true(eng:goto_index(3, 16000))
        eng:tick(22000)
        assert_eq(eng.state, "ABORTED")
        local g_loiter = arb:get_effective_goal()
        assert_eq(g_loiter.flightMode, "LOITER")
        assert_true(g_loiter.arm)
        assert_true(g_loiter.flightActive)

        -- 5. Deliberate stop while DISARMED on ground -> IDLE with arm=false, flightActive=false
        assert_true(eng:start("SINGLE", 23000))
        eng:step_telemetry({ fsmState = "DISARMED", navigation = { currentPos = { x = 0, y = 64, z = 0 } } }, 23050)
        assert_true(eng:stop(23100))
        local g_stop = arb:get_effective_goal()
        assert_eq(g_stop.flightMode, "IDLE")
        assert_false(g_stop.arm)
        assert_false(g_stop.flightActive)
    end)

    it("arbitrates CONFIRM for DEC_HUMAN_AUTH and emits PRECONDITION_FAILED on dynamic precondition check failure", function()
        local mission_engine = require("mission_engine")
        local q, net, arb, tx = create_fixture()
        local eng = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        arb:set_engine(eng)

        local f_auth = fs.open("missions/auth_sortie.json", "w")
        f_auth.write(textutils.serializeJSON({
            version = "2.0.0",
            missionId = "AUTH_SORTIE",
            checkpoints = {
                {
                    checkpointId = "CP_AUTH",
                    action = "ACT_PAY_BUS_CMD",
                    decorators = { { decoratorId = "DEC_HUMAN_AUTH" } },
                    params = { channelOffset = 20, command = "DROP" },
                },
            },
        }))
        f_auth.close()

        -- CONFIRM while not waitingHumanAuth -> INVALID_CMD
        arb:handle_gcs_packet({ ver = "1.9.5", type = "MSG_MISSION_CMD", payload = { action = "CONFIRM" } }, 900)
        assert_eq(tx[#tx].payload.payload.status, "INVALID_CMD")

        -- RUN mission -> ACCEPTED while paused at waitingHumanAuth
        arb:handle_gcs_packet({ ver = "1.9.5", type = "MSG_MISSION_CMD", payload = { action = "RUN", missionName = "auth_sortie" } }, 1000)
        assert_eq(tx[#tx].payload.payload.status, "ACCEPTED")
        assert_true(eng.waitingHumanAuth)

        -- CONFIRM releases gate -> ACCEPTED
        arb:handle_gcs_packet({ ver = "1.9.5", type = "MSG_MISSION_CMD", payload = { action = "CONFIRM" } }, 1100)
        assert_eq(tx[#tx].payload.payload.status, "ACCEPTED")
        assert_false(eng.waitingHumanAuth)

        -- RUN with failing runtime precondition -> PRECONDITION_FAILED
        eng:stop(1200)
        local f_pre = fs.open("missions/precond_fail.json", "w")
        f_pre.write(textutils.serializeJSON({
            version = "2.0.0",
            missionId = "PRECOND_FAIL",
            checkpoints = {
                {
                    checkpointId = "CP_P",
                    action = "ACT_NAV_GOTO_WP",
                    params = { targetPos = { x = 10, z = 10 } },
                    preconditions = { minFuel = 0.95 },
                },
            },
        }))
        f_pre.close()
        eng:step_telemetry({ fuel = 0.50 }, 1250)
        arb:handle_gcs_packet({ ver = "1.9.5", type = "MSG_MISSION_CMD", payload = { action = "RUN", missionName = "precond_fail" } }, 1300)
        assert_eq(tx[#tx].payload.payload.status, "PRECONDITION_FAILED")

        fs.delete("missions/auth_sortie.json")
        fs.delete("missions/precond_fail.json")
    end)
end)
