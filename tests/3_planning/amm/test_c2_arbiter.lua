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
            missionId = "PATROL_ALPHA",
            checkpoints = {
                { checkpointId = "CP_01", action = "FLY_OVER", params = { targetPos = { x = 100, z = 200 }, targetAlt = 150, cruiseSpeed = 18 } },
                { checkpointId = "CP_02", action = "ORBIT", params = { targetPos = { x = 300, z = 400 }, radius = 35, direction = "CW" } },
            },
        }))
        f_ok.close()

        local f_def = fs.open("missions/runway_sortie.json", "w")
        f_def.write(textutils.serializeJSON({
            missionId = "RUNWAY_SORTIE",
            checkpoints = {
                { checkpointId = "CP_RWY", action = "TAKEOFF_RUNWAY", params = {} },
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
            missionId = "BAD_SCHEMA",
            checkpoints = {
                { checkpointId = "CP_01", action = "FLY_OVER", params = { targetPos = { x = 10, z = 20 } } },
                { checkpointId = "CP_02", action = "PAYLOAD_ACTION", params = { channelOffset = 20 } }, -- missing command
            },
        }))
        f_bad.close()

        local f_disk = fs.open("/disk/disk_sortie.json", "w")
        f_disk.write(textutils.serializeJSON({
            missionId = "DISK_SORTIE",
            checkpoints = {
                { checkpointId = "CP_01", action = "FLY_OVER", params = { x = 400, z = -500 } },
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
end)
