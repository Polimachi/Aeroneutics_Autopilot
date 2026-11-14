-- tests/3_planning/amm/test_amm_integration.lua
-- AMM End-to-End Closed-Loop Integration Test
local waypoint_queue = require("waypoint_queue")
local network_manager = require("network_manager")
local c2_arbiter = require("c2_arbiter")
local input_handler = require("input_handler")
local ui_renderer = require("ui_renderer")

describe("AMM End-to-End Multi-Tick Simulation", function()
    it("completes full 8-step flight sequence from ground takeoff to landing", function()
        local cfg = { domainId = "AIRCRAFT_01", baseChannel = 10000, defaultAlt = 150, defaultSpeed = 18, arrivalRadius = 15 }
        local queue = waypoint_queue.new(cfg)
        local net = network_manager.new(cfg)
        local arbiter = c2_arbiter.new(queue, net, cfg)
        local input = input_handler.new()
        local screen_buf = ui_renderer.create_buffer(51, 19)

        local sent_packets = {}
        net.modem = {
            transmit = function(chan, reply_chan, payload)
                table.insert(sent_packets, { chan = chan, payload = payload })
            end,
            open = function(c) end,
        }

        -- Step 1: Add 3 waypoints
        queue:add(100, 100, 150, 18)
        queue:add(300, 300, 160, 20)
        queue:add(600, 600, 120, 15, "PAD_BRAVO_01")
        assert_eq(queue:count(), 3)
        assert_eq(queue.state, "EN_ROUTE")

        -- Step 2: Pilot presses [A] (ARM)
        local act_arm = input:handle_char("a")
        assert_eq(act_arm.action, "ARM")
        arbiter:handle_pilot_action(act_arm.action)
        assert_eq(#sent_packets, 0)
        local g_arm = arbiter:get_effective_goal()
        assert_eq(g_arm.flightMode, "IDLE_ARMED")
        assert_true(g_arm.arm)

        -- Step 3: Pilot presses [T] (TAKEOFF)
        local act_to = input:handle_char("t")
        assert_eq(act_to.action, "TAKEOFF")
        arbiter:handle_pilot_action(act_to.action, { targetAlt = 150 })
        assert_eq(#sent_packets, 0)
        assert_eq(arbiter:get_effective_goal().flightMode, "TAKEOFF")
        assert_true(arbiter.fcpTakeoffActive)

        -- Step 4: FCP takes off and enters CRUISE at clearance altitude -> WP1 in Base+4 goal
        arbiter:handle_flight_telemetry({
            payload = {
                fsmState = "CRUISE",
                navigation = { currentPos = { x = 0, z = 0 } }
            }
        })
        assert_eq(#sent_packets, 0)
        assert_eq(arbiter:get_effective_goal().targetPos.x, 100)

        -- Step 5: Craft reaches WP1 -> advances to WP2
        arbiter:handle_flight_telemetry({
            payload = {
                fsmState = "CRUISE",
                navigation = { currentPos = { x = 100, z = 100 } }
            }
        })
        assert_eq(#sent_packets, 0)
        assert_eq(arbiter:get_effective_goal().targetPos.x, 300)

        -- Step 6: GCS issues HOVER_HOLD on Base+0 -> AMM suspends without retransmission
        arbiter:handle_gcs_packet({
            ver = "1.9.5",
            type = "MSG_OPERATOR_CMD",
            payload = { authority = "GCS_OVERRIDE", command = "HOLD", emergencyAction = "HOVER_HOLD" }
        })
        assert_eq(arbiter.authority, "GCS_OVERRIDE")
        assert_eq(queue.state, "SUSPENDED")
        assert_eq(arbiter:get_effective_goal().flightMode, "HOVER_HOLD")
        assert_eq(#sent_packets, 0) -- Zero retransmissions!

        -- Step 7: Pilot types 'resume' via CLI -> queue reactivates
        input:set_mode("CLI")
        input.buffer = "resume"
        local cmd_res = input:handle_key(keys.enter or 28)
        assert_eq(cmd_res.name, "resume")
        arbiter:handle_pilot_action("RESUME")
        assert_eq(arbiter.authority, "PILOT_PRIMARY")
        assert_eq(queue.state, "EN_ROUTE")
        assert_eq(#sent_packets, 0)
        assert_eq(arbiter:get_effective_goal().targetPos.x, 300)

        -- Craft reaches WP2 -> advances to WP3
        arbiter:handle_flight_telemetry({
            payload = {
                fsmState = "CRUISE",
                navigation = { currentPos = { x = 300, z = 300 } }
            }
        })
        assert_eq(#sent_packets, 0)
        assert_eq(arbiter:get_effective_goal().targetPos.x, 600)

        -- Step 8: Craft reaches WP3 (final WP with facilityId PAD_BRAVO_01) -> LANDING goal active
        arbiter:handle_flight_telemetry({
            payload = {
                fsmState = "CRUISE",
                navigation = { currentPos = { x = 600, z = 600 } }
            }
        })
        assert_eq(queue.state, "COMPLETED")
        assert_eq(#sent_packets, 0)
        local fin = arbiter:get_effective_goal()
        assert_eq(fin.flightMode, "LANDING")
        assert_eq(fin.designatedFacilityId, "PAD_BRAVO_01")

        -- Step 9: Emergency E-STOP hotkey fires E_STOP to Base+1
        arbiter:handle_pilot_action("ESTOP")
        assert_eq(#sent_packets, 1)
        assert_eq(sent_packets[1].chan, 10001) -- Base+1
        assert_eq(sent_packets[1].payload.type, "MSG_EMERGENCY_OVERRIDE")
        assert_eq(sent_packets[1].payload.payload.action, "E_STOP")
        assert_eq(sent_packets[1].payload.payload.authKey, "ESTOP_CONFIRM_KEY")

        -- Verify TUI rendering executes cleanly
        local app_state = { domainId = "AIRCRAFT_01", authority = arbiter.authority, banner = arbiter.lastBanner, input_mode = "NAV" }
        ui_renderer.render_screen(screen_buf, { fsmState = "APPROACH_LAND" }, queue, app_state)
        assert_true(string.find(screen_buf.text[1], "AIRCRAFT_01") ~= nil)
    end)
end)
