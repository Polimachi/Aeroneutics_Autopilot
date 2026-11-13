-- tests/e2e/test_e2e_gps_triangulation.lua
-- Scenario 3: Closed-Loop Multi-Node GPS Triangulation, Fail-Geometry Retry, Status Query & Facility Client
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 3: GPS Closed-Loop Swarm Triangulation, Service Status & Multi-Client Integration", function()
    it("exercises FCP 4-node EARLY_SOLVED, collinear FAIL_GEOMETRY + 250ms retry, CH 60002 status, and Landing Pad FACILITY", function()
        local bus = virtual_bus.create_bus({ clock = 1.0 })
        sdk.patch(os, "epoch", function()
            return math.floor(bus.time * 1000 + 0.5)
        end)
        sdk.patch(_G, "print", function() end)

        local handlerErrors = {}
        local function safeCall(tag, fn)
            local ok, err = pcall(fn)
            if not ok then
                table.insert(handlerErrors, tag .. ": " .. tostring(err))
            end
        end

        local amm = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")
        local gps_srv = node_sandbox.create_node(bus, "GPS_SRV", "src/0_infra/gps")
        local gps_cli = node_sandbox.create_node(bus, "GPS_CLI", "src/0_infra/gps")
        local pad_node = node_sandbox.create_node(bus, "PAD_01", "src/0_infra/landing_pad")

        local anchorDefs = {
            { sb = node_sandbox.create_node(bus, "GPS_N1", "src/0_infra/gps"), cfg = { nodeId = "NODE_01", computerId = 1, position = { x = 0.0, y = 80.0, z = 0.0 } } },
            { sb = node_sandbox.create_node(bus, "GPS_N2", "src/0_infra/gps"), cfg = { nodeId = "NODE_02", computerId = 2, position = { x = 250.0, y = 80.0, z = 0.0 } } },
            { sb = node_sandbox.create_node(bus, "GPS_N3", "src/0_infra/gps"), cfg = { nodeId = "NODE_03", computerId = 3, position = { x = 500.0, y = 80.0, z = 0.0 } } },
            { sb = node_sandbox.create_node(bus, "GPS_N4", "src/0_infra/gps"), cfg = { nodeId = "NODE_04", computerId = 4, position = { x = 250.0, y = 80.0, z = 500.0 } } },
        }

        local truthByClient = {
            AIRCRAFT_01 = { x = 200.0, y = 100.0, z = 300.0 },
            AIRCRAFT_02 = { x = 200.0, y = 100.0, z = 300.0 },
            PAD_BRAVO_01 = { x = 340.0, y = 64.0, z = 420.0 },
        }

        local registry = { nodes = {} }
        local nodeEnabled = { true, true, true, true }
        local nodeMods, nodeStates = {}, {}
        for i, n in ipairs(anchorDefs) do
            registry.nodes[n.cfg.nodeId] = {
                nodeId = n.cfg.nodeId, computerId = n.cfg.computerId,
                position = n.cfg.position, status = "ONLINE"
            }
            nodeMods[i] = n.sb:require("node")
            nodeStates[i] = { reportsSent = 0, reportSeq = 0 }
            n.sb.modem:open(60001)
            n.sb.modem.on_message = function(ev)
                if not nodeEnabled[i] then return end
                local targetId = type(ev.payload) == "table" and ev.payload.domainId or nil
                local truth = truthByClient[targetId]
                if not truth then return end
                local dx = truth.x - n.cfg.position.x
                local dy = truth.y - n.cfg.position.y
                local dz = truth.z - n.cfg.position.z
                local dist3d = math.sqrt(dx * dx + dy * dy + dz * dz)
                safeCall(n.cfg.nodeId, function()
                    nodeMods[i].handlePingMessage(n.sb.modem, n.cfg, ev.channel, ev.payload, dist3d, nodeStates[i])
                end)
            end
        end

        local srv_mod = gps_srv:require("server")
        local sched_mod = gps_srv:require("session_scheduler")
        local sched = sched_mod.new({ windowMs = 50, tombstoneTtlMs = 1000 })
        local srv_state = {
            ticks = 400, solvedCount = 0, totalSolves = 0, seq = 1,
            activeNodes = 4, clientCount = 0,
            nodes = {
                { id = "NODE_01", x = 0, y = 80, z = 0, status = "ONLINE", ping = 0 },
                { id = "NODE_02", x = 250, y = 80, z = 0, status = "ONLINE", ping = 0 },
                { id = "NODE_03", x = 500, y = 80, z = 0, status = "ONLINE", ping = 0 },
                { id = "NODE_04", x = 250, y = 80, z = 500, status = "ONLINE", ping = 0 },
            },
            clients = {}
        }
        gps_srv.modem:open(60002)
        gps_srv.modem:open(60003)
        gps_srv.modem:open(60004)
        gps_srv.modem.on_message = function(ev)
            safeCall("GPS_SRV", function()
                srv_mod.handleModemMsg(sched, registry, gps_srv.modem, srv_state, {
                    "modem_message", ev.side, ev.channel, ev.replyChannel, ev.payload, ev.distance
                })
            end)
        end

        -- 1. AMM 4-node EARLY_SOLVED + foreign spoof filter + altitudeY sync
        local nav_engine = amm:require("nav_engine")
        local amm_net_mod = amm:require("network_manager")
        local amm_net = amm_net_mod.new({
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            bandwidth = 40,
        })
        amm_net.modem = amm.modem
        local nav_state = nav_engine.init({
            system = { domainId = "AIRCRAFT_01" },
            channels = { baseChannel = 10000, bandwidth = 40 },
            navigation = { drComplementaryAlpha = 0.5, gpsTimeoutMs = 5000 },
        })
        nav_state.pos = { x = 195.0, y = 64.0, z = 295.0 }
        amm.modem:open(10005)

        -- Base+2 altitudeY injection via MSG_FLIGHT_TELEMETRY
        local telem_pkt = {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1, type = "MSG_FLIGHT_TELEMETRY", time = 1000,
            payload = { dynamics = { altitudeY = 100.0, velocity = { vx = 0, vy = 0, vz = 0 } }, controlState = "IDLE_ARMED" }
        }
        nav_engine.integrate_dr(nav_state, telem_pkt.payload, 0.05, 1000)
        assert_eq(nav_state.pos.y, 100.0)

        -- AMM sends MSG_GPS_REQUEST to CH 60001
        local should_gps, gps_seq, gps_req = nav_engine.build_gps_request(nav_state, 1000)
        assert_true(should_gps)
        amm_net:send_gps_request(gps_req)
        bus:step(0.01)

        -- Inject foreign AIRCRAFT_02 spoof onto 10005 before delivering real GPS response
        gps_srv.modem:transmit(10005, 60002, {
            ver = "1.9.5", domainId = "GPS_BASE_NET", seq = 999, type = "MSG_GPS_RESPONSE", time = 1005,
            payload = { targetClient = "AIRCRAFT_02", clientSeq = 1, status = "FIX_OK", position = { x = -9999, z = -9999 }, nodeCount = 4, selectedNodes = {} }
        })
        bus:step(0.01) -- pings -> node reports (and foreign spoof delivered to 10005)

        -- Verify foreign spoof is rejected by nav_engine
        local amm_inbox = amm.modem:drain()
        for _, m in ipairs(amm_inbox) do
            if m.channel == 10005 and type(m.payload) == "table" and m.payload.type == "MSG_GPS_RESPONSE" then
                local filtered = nav_engine.filter_gps(nav_state, m.payload.payload, 0.05, 1005, 1)
                assert_false(filtered, "Foreign spoof must be rejected by nav_engine")
            end
        end

        local reqPkts = bus:find_packets({ type = "MSG_GPS_REQUEST", channel = 60001 })
        assert_eq(#reqPkts, 1)
        assert_not_nil(reqPkts[1].payload.time)
        assert_nil(reqPkts[1].payload.timestamp)

        bus:step(0.01) -- reports -> server EARLY_SOLVED response
        bus:step(0.03) -- response delivered to AMM

        local amm_gps_inbox = amm.modem:drain()
        local real_resp = nil
        for _, m in ipairs(amm_gps_inbox) do
            if m.channel == 10005 and type(m.payload) == "table" and m.payload.type == "MSG_GPS_RESPONSE" then
                if m.payload.payload and m.payload.payload.targetClient == "AIRCRAFT_01" then
                    real_resp = m.payload.payload
                end
            end
        end
        assert_not_nil(real_resp)
        local ok_filter = nav_engine.filter_gps(nav_state, real_resp, 0.05, 1050, 1)
        assert_true(ok_filter)
        assert_near(nav_state.pos.x, 197.5, 0.5)
        assert_near(nav_state.pos.z, 297.5, 0.5)
        assert_eq(nav_state.pos.y, 100.0)
        assert_eq(nav_state.lastGpsFixSeq, 1)
        assert_eq(nav_state.posEpoch, 1)

        -- 2. Collinear 3-node FAIL_GEOMETRY + 250ms retry after 150ms tombstone
        nodeEnabled[4] = false
        bus.time = 2.000
        local cli_hal = gps_cli:require("gps_client")
        cli_hal.init("AIRCRAFT_02", "AIRCRAFT", 10045)
        cli_hal.setManaged(true)
        gps_cli.modem:open(10045)
        gps_cli.modem:open(60002)
        gps_cli.modem.on_message = function(ev)
            safeCall("GPS_CLI", function()
                cli_hal.handleMessage(ev.side, ev.channel, ev.replyChannel, ev.payload, ev.distance)
            end)
        end

        local retrySeq = cli_hal.request(100.0)
        bus:step(0.01) -- ping -> 3 collinear nodes
        bus:step(0.01) -- 3 reports buffered
        bus.time = 2.080
        srv_mod.flushTimerExpired(sched, registry, gps_srv.modem, srv_state)
        bus:step(0.01)
        local geomResp = cli_hal.poll(retrySeq)
        assert_not_nil(geomResp, "3 collinear nodes on expiration must return FAIL_GEOMETRY instead of hanging")
        assert_eq(geomResp.status, "FAIL_GEOMETRY")

        -- Re-enable 4th non-collinear node and retry at 250ms (> 150ms tombstone) with same clientSeq
        nodeEnabled[4] = true
        bus.time = 2.250
        gps_cli.modem:transmit(60001, 10045, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = retrySeq, type = "MSG_GPS_REQUEST", time = 2250,
            payload = { replyChannel = 10045, altitudeY = 100.0, clientType = "AIRCRAFT", clientSeq = retrySeq }
        })
        bus:step(0.01)
        bus:step(0.01)
        bus:step(0.01)
        local retryFix = cli_hal.poll(retrySeq)
        assert_not_nil(retryFix)
        assert_eq(retryFix.status, "FIX_OK")
        assert_near(retryFix.position.x, 200.0, 0.5)
        assert_near(retryFix.position.z, 300.0, 0.5)

        -- 3. CH 60002 server status query
        cli_hal.requestStatus("SUMMARY", 60002)
        bus:step(0.01)
        bus:step(0.01)
        local srvStatus = cli_hal.pollStatus()
        assert_not_nil(srvStatus)
        assert_eq(srvStatus.activeNodes, 4)
        assert_eq(srvStatus.totalSolved, 2)
        assert_eq(srvStatus.version, "1.9.5")

        -- 4. Landing Pad FACILITY (50206) closed loop & replay guard
        local pad_cfg_store = pad_node:require("config_store")
        local pad_offset = pad_node:require("offset_transform")
        local pad_gps_mod = pad_node:require("gps_client")
        local padCfg = pad_cfg_store.normalize_config({
            facilityId = "PAD_BRAVO_01", sectorId = 1, padIndex = 1, mobility = "DYNAMIC",
            gacChannel = 50201, sectorFacilityChannel = 50202, sectorGpsReplyChannel = 50206, tacticalChannel = 50211
        })
        local padGps = pad_gps_mod.create(padCfg, pad_offset)
        local lastPadEnvelope = nil
        local padReplayOk = nil
        pad_node.modem:open(50206)
        pad_node.modem.on_message = function(ev)
            lastPadEnvelope = ev.payload
            safeCall("PAD", function()
                local pad_gps_ok = padGps:handle_response_packet(ev.payload, bus.time)
                assert_true(pad_gps_ok)
            end)
        end
        assert_true(padGps:should_query_gps("RESERVED", 4))
        local padReq = padGps:build_request_packet(64.0, 2300)
        assert_eq(padReq.payload.clientType, "FACILITY")
        assert_eq(padReq.payload.replyChannel, 50206)
        pad_node.modem:transmit(60001, padReq.payload.replyChannel, padReq)
        bus:step(0.01)
        bus:step(0.01)
        bus:step(0.01)

        assert_true(padGps:has_valid_fix())
        assert_near(padGps:get_current_comp_pos().x, 340.0, 0.5)
        assert_near(padGps:get_current_comp_pos().z, 420.0, 0.5)
        assert_not_nil(lastPadEnvelope)
        padReplayOk = padGps:handle_response_packet(lastPadEnvelope, bus.time)
        assert_false(padReplayOk, "Landing Pad client must reject replayed clientSeq")

        -- 5. TASK-123 High-load active session eviction, monotonic client guard & computerId staggering
        nodeEnabled[3] = false
        nodeEnabled[4] = false
        local seqStale = cli_hal.request(100.0)
        bus:step(0.01)
        bus:step(0.01)
        assert_not_nil(sched.active_sessions["AIRCRAFT_02:" .. seqStale])

        nodeEnabled[3] = true
        nodeEnabled[4] = true
        local seqFresh = cli_hal.request(100.0)
        bus:step(0.01)
        bus:step(0.01)
        bus:step(0.01)
        assert_nil(sched.active_sessions["AIRCRAFT_02:" .. seqStale], "Incomplete older session must be evicted by newer seq")
        local freshFix = cli_hal.poll(seqFresh)
        assert_not_nil(freshFix)
        assert_eq(freshFix.status, "FIX_OK")
        assert_eq(sched.client_last_solved["AIRCRAFT_02"], seqFresh)

        -- Stale & duplicate responses rejected by client_core monotonic guard
        local proto_mod = gps_cli:require("protocol")
        local staleRespPkt = proto_mod.buildResponse("GPS_BASE_NET", 10, {
            targetClient = "AIRCRAFT_02", clientSeq = seqStale, status = "FIX_OK",
            nodeCount = 4, position = { x = 0, z = 0 }, accuracy = 0.1, hdop = 1.0
        }, 3000)
        assert_false(cli_hal.handleMessage("top", 10045, 60001, staleRespPkt, 10))
        assert_nil(cli_hal.poll(seqStale))

        -- Phase staggering on AMM nav_engine & Landing Pad gps_client
        local ammStagger = nav_engine.init({ system = { domainId = "AIRCRAFT_03", computerId = 1 }, navigation = { gpsRequestRateHz = 5 } })
        assert_false(nav_engine.should_query_gps(ammStagger, 1000))
        assert_true(nav_engine.should_query_gps(ammStagger, 1050))

        local padStagger = pad_gps_mod.create({ facilityId = "PAD_BRAVO_02", mobility = "DYNAMIC", sectorIndex = 1, computerId = 2 }, pad_offset)
        assert_false(padStagger:should_query_gps("RESERVED", 4))
        assert_true(padStagger:should_query_gps("RESERVED", 2))

        assert_eq(#handlerErrors, 0, table.concat(handlerErrors, "; "))
    end)
end)
