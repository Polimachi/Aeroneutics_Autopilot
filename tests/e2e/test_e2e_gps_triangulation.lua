-- tests/e2e/test_e2e_gps_triangulation.lua
-- Scenario 3: High-Precision GPS 10Hz Swarm Triangulation & Navigation Fusion Integration
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 3: GPS 10Hz Swarm Triangulation & Navigation Fusion", function()
    it("completes full ping -> swarm report -> 2D trilateration solve -> FCP fusion cycle", function()
        local bus = virtual_bus.create_bus({ clock = 1000.0 })

        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
        local gps_srv = node_sandbox.create_node(bus, "GPS_SRV", "src/0_infra/gps")
        local n1 = node_sandbox.create_node(bus, "GPS_N1", "src/0_infra/gps")
        local n2 = node_sandbox.create_node(bus, "GPS_N2", "src/0_infra/gps")
        local n3 = node_sandbox.create_node(bus, "GPS_N3", "src/0_infra/gps")
        local n4 = node_sandbox.create_node(bus, "GPS_N4", "src/0_infra/gps")

        -- 1. Setup channel bindings
        fcp.modem:open(10005) -- Base+5 (GPS response)
        n1.modem:open(60001)  -- CH_GPS_PING
        n2.modem:open(60001)
        n3.modem:open(60001)
        n4.modem:open(60001)
        gps_srv.modem:open(60003) -- CH_GPS_NODE_IN

        -- 2. Swarm node positions around craft at true position (x=200, y=100, z=300)
        local craft_true = { x = 200.0, y = 100.0, z = 300.0 }
        local nodes = {
            { id = "NODE_01", x = 0.0,   y = 80.0, z = 0.0,   modem = n1.modem },
            { id = "NODE_02", x = 500.0, y = 80.0, z = 0.0,   modem = n2.modem },
            { id = "NODE_03", x = 0.0,   y = 80.0, z = 500.0, modem = n3.modem },
            { id = "NODE_04", x = 500.0, y = 80.0, z = 500.0, modem = n4.modem },
        }

        -- 3. FCP Navigation Engine checks whether to query GPS
        local nav_engine = fcp:require("nav_engine")
        local nav_state = nav_engine.init({
            navigation = { drComplementaryAlpha = 0.5 },
        })
        nav_state.pos.x = 195.0 -- prior dead-reckoning position
        nav_state.pos.y = 100.0
        nav_state.pos.z = 295.0

        local should_query, seq = nav_engine.should_query_gps(nav_state, 1000)
        assert_true(should_query)
        assert_eq(seq, 1)

        -- FCP transmits MSG_GPS_REQUEST on CH 60001
        fcp.modem:transmit(60001, 10005, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = seq,
            type = "MSG_GPS_REQUEST",
            time = 1000,
            payload = {
                replyChannel = 10005,
                altitudeY = nav_state.pos.y,
                clientType = "AIRCRAFT",
                clientSeq = seq,
            },
        })
        bus:step(0.05)

        -- 4. Each swarm node receives ping and measures 3D distance
        local pings = bus:find_packets({ type = "MSG_GPS_REQUEST", channel = 60001 })
        assert_eq(#pings, 1)

        for _, n in ipairs(nodes) do
            local dx = craft_true.x - n.x
            local dy = craft_true.y - n.y
            local dz = craft_true.z - n.z
            local dist3d = math.sqrt(dx * dx + dy * dy + dz * dz)

            -- Node transmits distance report to GPS Server on 60003
            n.modem:transmit(60003, 60003, {
                ver = "1.9.5",
                domainId = n.id,
                seq = 1,
                type = "MSG_GPS_NODE_REPORT",
                time = 1010,
                payload = {
                    targetClient = "AIRCRAFT_01",
                    clientSeq = seq,
                    nodeId = n.id,
                    nodePos = { x = n.x, y = n.y, z = n.z },
                    measuredDistance = dist3d,
                    clientAltitudeY = nav_state.pos.y,
                    replyChannel = 10005,
                },
            })
        end
        bus:step(0.05)

        -- Assert reports arrived on 60003
        local reports = bus:find_packets({ type = "MSG_GPS_NODE_REPORT", channel = 60003 })
        assert_eq(#reports, 4)

        -- 5. GPS Server collects reports and runs 2D WLS trilateration
        local trilateration = gps_srv:require("trilateration")
        local solver_nodes = {}
        for _, rep in ipairs(reports) do
            local p = rep.payload.payload
            table.insert(solver_nodes, {
                id = p.nodeId,
                x = p.nodePos.x,
                y = p.nodePos.y,
                z = p.nodePos.z,
                distance = p.measuredDistance,
            })
        end

        local sol, err = trilateration.solve(solver_nodes, nav_state.pos.y, { minX = 0, maxX = 500, minZ = 0, maxZ = 500 })
        assert_nil(err)
        assert_not_nil(sol)
        assert_eq(sol.status, "FIX_OK")
        assert_near(sol.x, 200.0, 0.5)
        assert_near(sol.z, 300.0, 0.5)

        -- GPS Server transmits MSG_GPS_RESPONSE to craft replyChannel Base+5 (10005)
        gps_srv.modem:transmit(10005, 10005, {
            ver = "1.9.5",
            domainId = "GPS_SERVER",
            seq = 500,
            type = "MSG_GPS_RESPONSE",
            time = 1020,
            payload = {
                targetClient = "AIRCRAFT_01",
                clientSeq = seq,
                status = sol.status,
                position = { x = sol.x, z = sol.z },
                accuracy = sol.accuracy,
                hdop = sol.hdop,
                nodeCount = sol.nodeCount,
                selectedNodes = sol.selectedNodes,
            },
        })
        bus:step(0.05)

        -- 6. FCP receives fix on Base+5 (10005) and fuses with Dead Reckoning
        local fcp_gps_inbox = fcp.modem:drain()
        assert_eq(#fcp_gps_inbox, 1)
        local resp = fcp_gps_inbox[1].payload
        assert_eq(resp.type, "MSG_GPS_RESPONSE")

        local fused_ok = nav_engine.filter_gps(nav_state, resp.payload, 0.05, 1020)
        assert_true(fused_ok)

        -- Position should be smoothly pulled towards true fix (200.0, 300.0) from prior (195.0, 295.0)
        assert_near(nav_state.pos.x, 197.5, 0.5)
        assert_near(nav_state.pos.z, 297.5, 0.5)
        assert_eq(nav_state.lastGpsFixMs, 1020)
    end)
end)
