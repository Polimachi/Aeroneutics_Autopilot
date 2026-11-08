-- tests/3_planning/amm/test_c2_arbiter.lua
local waypoint_queue = require("waypoint_queue")
local network_manager = require("network_manager")
local c2_arbiter = require("c2_arbiter")

describe("AMM C2 Arbiter, Authority Switching & Queue FSM", function()
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
end)
