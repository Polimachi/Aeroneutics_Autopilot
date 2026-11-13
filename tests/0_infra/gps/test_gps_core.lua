-- Unit test suite for 0_infra/gps
local storage_hal = require("storage_hal")
local trilateration = require("trilateration")
local protocol = require("protocol")
local client_core = require("client_core")
local config_store = require("config_store")

describe("gps storage HAL atomic writes and error handling", function()
    it("writes atomically and reads back JSON in ephemeral CraftOS filesystem", function()
        local test_file = sdk.temp_path("gps_nodes.json")
        local payload = {
            networkId = "GPS_NET_ALPHA",
            nodes = {
                { id = 1, x = 0, y = 64, z = 0 },
                { id = 2, x = 100, y = 64, z = 0 }
            }
        }

        local okWrite, errWrite = storage_hal.writeJsonAtomic(test_file, payload)
        assert_true(okWrite, errWrite)

        local data, errRead = storage_hal.readJson(test_file)
        assert_not_nil(data)
        assert_eq(errRead, nil)
        assert_eq(data.networkId, "GPS_NET_ALPHA")
        assert_eq(#data.nodes, 2)
        assert_eq(data.nodes[1].x, 0)
    end)

    it("returns FILE_NOT_FOUND error on non-existent path", function()
        local missing, err = storage_hal.readJson("/non_existent_path_xyz.json")
        assert_nil(missing)
        assert_eq(err, "FILE_NOT_FOUND")
    end)
end)

describe("gps trilateration numerical solver", function()
    it("projects horizontal distances and solves craft position accurately", function()
        -- True craft coordinates: (x = 30.0, y = 80.0, z = -20.0)
        local craftX, craftY, craftZ = 30.0, 80.0, -20.0

        local anchors = {
            { id = "N1", x = 0.0, y = 64.0, z = 0.0 },
            { id = "N2", x = 100.0, y = 64.0, z = 0.0 },
            { id = "N3", x = 0.0, y = 64.0, z = -100.0 },
            { id = "N4", x = 100.0, y = 64.0, z = -100.0 }
        }

        local nodes = {}
        for idx, anc in ipairs(anchors) do
            local dx = anc.x - craftX
            local dy = anc.y - craftY
            local dz = anc.z - craftZ
            local dist3d = math.sqrt(dx * dx + dy * dy + dz * dz)
            nodes[idx] = {
                id = anc.id,
                x = anc.x,
                y = anc.y,
                z = anc.z,
                distance = dist3d
            }
        end

        local projected = trilateration.projectHorizontal(nodes, craftY)
        assert_eq(#projected, 4)

        local optimal, errGeom = trilateration.selectOptimalNodes(projected, 4)
        assert_not_nil(optimal, errGeom)
        assert_true(#optimal >= 3)

        local solvedX, solvedZ, det = trilateration.solveLinearWLS(optimal)
        assert_not_nil(solvedX)
        assert_not_nil(solvedZ)
        assert_true(math.abs(det) > 1e-4)

        assert_near(solvedX, craftX, 0.05, "solved X should match true craft X")
        assert_near(solvedZ, craftZ, 0.05, "solved Z should match true craft Z")

        -- Full solve status validation (MUT-09)
        local fullSol, solErr = trilateration.solve(nodes, craftY, { minX = -100, maxX = 100, minZ = -100, maxZ = 100 })
        assert_nil(solErr)
        assert_not_nil(fullSol)
        assert_eq(fullSol.status, "FIX_OK")
        assert_near(fullSol.x, craftX, 0.1)
        assert_near(fullSol.z, craftZ, 0.1)
    end)
end)

describe("gps protocol 40-channel layout and craft reply channels", function()
    it("defines standard infrastructure channels and reply channel constants", function()
        assert_eq(protocol.CH_GPS_PING, 60001)
        assert_eq(protocol.CH_GPS_SERVICE, 60002)
        assert_eq(protocol.CH_GPS_NODE_IN, 60003)
        assert_eq(protocol.CH_GPS_MGMT, 60004)
        assert_eq(protocol.DEFAULT_REPLY_CHANNEL, 10005)
        assert_eq(protocol.CRAFT_BASE_MIN, 10000)
        assert_eq(protocol.CRAFT_BASE_MAX, 49960)
        assert_eq(protocol.CRAFT_BANDWIDTH, 40)
        assert_eq(protocol.CRAFT_MAX_INDEX, 1000)
        assert_eq(protocol.CH_REPLY_OFFSET, 5)
    end)

    it("computes craft reply channel accurately and guards boundary conditions", function()
        assert_eq(protocol.computeCraftReplyChannel(1), 10005)
        assert_eq(protocol.computeCraftReplyChannel(2), 10045)
        assert_eq(protocol.computeCraftReplyChannel(1000), 49965)

        assert_nil(protocol.computeCraftReplyChannel(0))
        assert_nil(protocol.computeCraftReplyChannel(1001))
        assert_nil(protocol.computeCraftReplyChannel(-1))
        assert_nil(protocol.computeCraftReplyChannel(1.5))
        assert_nil(protocol.computeCraftReplyChannel("invalid"))
        assert_nil(protocol.computeCraftReplyChannel(nil))
    end)

    it("resolves domain reply channel from domainId string", function()
        assert_eq(protocol.resolveDomainReplyChannel("AIRCRAFT_01"), 10005)
        assert_eq(protocol.resolveDomainReplyChannel("AIRCRAFT_02"), 10045)
        assert_eq(protocol.resolveDomainReplyChannel("AIRCRAFT_1000"), 49965)
        assert_nil(protocol.resolveDomainReplyChannel("AIRCRAFT_0"))
        assert_nil(protocol.resolveDomainReplyChannel("AIRCRAFT_1001"))
        assert_nil(protocol.resolveDomainReplyChannel("GROUND_STATION"))
        assert_nil(protocol.resolveDomainReplyChannel(""))
        assert_nil(protocol.resolveDomainReplyChannel(nil))
    end)
end)

describe("gps client_core 40-channel auto-resolution and message handling", function()
    it("initializes with default replyChannel 10005 and auto-resolves Base+5 from domainId", function()
        local c1 = client_core.new()
        assert_eq(c1.replyChannel, 10005)

        local c2 = client_core.new()
        c2:init("AIRCRAFT_02", "AIRCRAFT")
        assert_eq(c2.domainId, "AIRCRAFT_02")
        assert_eq(c2.replyChannel, 10045)

        local c3 = client_core.new()
        c3:init("AIRCRAFT_02", "AIRCRAFT", 25000)
        assert_eq(c3.replyChannel, 25000)

        local c4 = client_core.new()
        c4:init("GROUND_ROVER", "GROUND")
        assert_eq(c4.replyChannel, 10005)
    end)

    it("generates valid request packet and successfully dispatches and polls response", function()
        local c = client_core.new()
        c:init("AIRCRAFT_02", "AIRCRAFT")
        assert_eq(c.replyChannel, 10045)

        local seq, pkt = c:nextRequestPacket(120.5, 1000)
        assert_eq(seq, 1)
        assert_eq(pkt.payload.replyChannel, 10045)
        assert_eq(pkt.payload.altitudeY, 120.5)

        local okPkt, errPkt = protocol.validatePacket(pkt, protocol.MSG_REQUEST)
        assert_true(okPkt, errPkt)

        local respFields = {
            targetClient = "AIRCRAFT_02",
            clientSeq = seq,
            status = "FIX_OK",
            nodeCount = 4,
            position = { x = 150.0, z = -200.0 },
            accuracy = 0.05,
            hdop = 1.1
        }
        local respPkt = protocol.buildResponse("GPS_BASE_NET", 1, respFields, 1020)

        local handledWrong = c:handleMessage(99999, respPkt, 1020)
        assert_false(handledWrong)
        assert_nil(c:poll(seq))

        local handledOk = c:handleMessage(10045, respPkt, 1020)
        assert_true(handledOk)

        local res = c:poll(seq)
        assert_not_nil(res)
        assert_eq(res.targetClient, "AIRCRAFT_02")
        assert_eq(res.status, "FIX_OK")
        assert_eq(res.position.x, 150.0)
        assert_eq(res.position.z, -200.0)

        assert_nil(c:poll(seq))
    end)

    it("enforces monotonic lastReceivedSeq guard while allowing FAIL_GEOMETRY same-seq retry and reset", function()
        local c = client_core.new()
        c:init("AIRCRAFT_02", "AIRCRAFT")
        local s1, _ = c:nextRequestPacket(100.0, 1000)
        local s2, _ = c:nextRequestPacket(100.0, 1100)
        assert_eq(s1, 1)
        assert_eq(s2, 2)

        local resp2 = protocol.buildResponse("GPS_BASE_NET", 1, {
            targetClient = "AIRCRAFT_02",
            clientSeq = s2,
            status = "FIX_OK",
            nodeCount = 4,
            position = { x = 10, z = 20 },
            accuracy = 0.05,
            hdop = 1.0
        }, 1110)
        assert_true(c:handleMessage(10045, resp2, 1110))
        assert_not_nil(c:poll(s2))

        -- Duplicate FIX_OK on s2 must be rejected
        assert_false(c:handleMessage(10045, resp2, 1120))
        assert_nil(c:poll(s2))

        -- Delayed older FIX_OK and FAIL_GEOMETRY on s1 must be rejected
        local staleResp1 = protocol.buildResponse("GPS_BASE_NET", 2, {
            targetClient = "AIRCRAFT_02",
            clientSeq = s1,
            status = "FIX_OK",
            nodeCount = 4,
            position = { x = 5, z = 5 },
            accuracy = 0.05,
            hdop = 1.0
        }, 1130)
        assert_false(c:handleMessage(10045, staleResp1, 1130))
        assert_nil(c:poll(s1))

        local staleFail1 = protocol.buildResponse("GPS_BASE_NET", 3, {
            targetClient = "AIRCRAFT_02",
            clientSeq = s1,
            status = "FAIL_GEOMETRY",
            nodeCount = 3,
            hdop = 9.9
        }, 1135)
        assert_false(c:handleMessage(10045, staleFail1, 1135))

        -- Advance to s3: FAIL_GEOMETRY followed by same-seq retry FIX_OK must both work
        local s3, _ = c:nextRequestPacket(100.0, 1200)
        assert_eq(s3, 3)
        local fail3 = protocol.buildResponse("GPS_BASE_NET", 4, {
            targetClient = "AIRCRAFT_02",
            clientSeq = s3,
            status = "FAIL_GEOMETRY",
            nodeCount = 3,
            hdop = 9.9
        }, 1210)
        assert_true(c:handleMessage(10045, fail3, 1210))
        local pollFail3 = c:poll(s3)
        assert_not_nil(pollFail3)
        assert_eq(pollFail3.status, "FAIL_GEOMETRY")

        local retryOk3 = protocol.buildResponse("GPS_BASE_NET", 5, {
            targetClient = "AIRCRAFT_02",
            clientSeq = s3,
            status = "FIX_OK",
            nodeCount = 4,
            position = { x = 12, z = 24 },
            accuracy = 0.05,
            hdop = 1.0
        }, 1460)
        assert_true(c:handleMessage(10045, retryOk3, 1460))
        local pollOk3 = c:poll(s3)
        assert_not_nil(pollOk3)
        assert_eq(pollOk3.status, "FIX_OK")
        assert_false(c:handleMessage(10045, retryOk3, 1470))

        -- overrideSeq < lastReceivedSeq resets monotonic guard (seq wraparound)
        local ovSeq, _ = c:nextRequestPacket(100.0, 1500, 1)
        assert_eq(ovSeq, 1)
        assert_true(c:handleMessage(10045, staleResp1, 1510))
        assert_not_nil(c:poll(1))
    end)
end)

describe("gps config_store 4-channel node configuration and standalone gps_client load", function()
    it("normalizes default 4-channel node configuration without legacy channel field", function()
        local cfg, isComplete = config_store.normalizeNodeConfig({}, 7)
        assert_not_nil(cfg)
        assert_nil(cfg.channel)
        assert_not_nil(cfg.channels)
        assert_eq(cfg.channels.ping, 60001)
        assert_eq(cfg.channels.service, 60002)
        assert_eq(cfg.channels.nodeIn, 60003)
        assert_eq(cfg.channels.mgmt, 60004)
        assert_eq(cfg.computerId, 7)
        assert_false(isComplete)
    end)

    it("verifies legacy installer removal and cleanly loads standalone gps_client", function()
        local okInstaller, errInstaller = pcall(require, "installer")
        assert_false(okInstaller, "legacy gps/installer.lua must not be resolvable")

        local okClient, gpsClient = pcall(require, "gps_client")
        assert_true(okClient, tostring(gpsClient))
        assert_eq(type(gpsClient), "table")
        assert_eq(type(gpsClient.locate), "function")
        assert_eq(type(gpsClient.request), "function")
    end)
end)


describe("radar_math centroid and bounding box calculations", function()
    local radar_math = require("radar_math")

    it("computes centroid and span from points accurately (MUT-10)", function()
        local pts = {
            { x = 10, z = 20 },
            { x = 30, z = 40 },
        }
        local bounds = radar_math.computeCentroidSpan(pts, 1.0)
        assert_not_nil(bounds)
        assert_eq(bounds.centerX, 20)
        assert_eq(bounds.centerZ, 30)
        assert_eq(bounds.minX, 10)
        assert_eq(bounds.maxX, 30)
    end)
end)

describe("gps session_scheduler early solve and FAIL_GEOMETRY retry window", function()
    local session_scheduler = require("session_scheduler")

    it("returns replyChannel as 3rd return on EARLY_SOLVED", function()
        local sched = session_scheduler.new({ windowMs = 50, tombstoneTtlMs = 1000 })
        local registry = { nodes = {} }
        local nodes = {
            { id = "N1", x = 0, y = 80, z = 0 },
            { id = "N2", x = 500, y = 80, z = 0 },
            { id = "N3", x = 0, y = 80, z = 500 },
            { id = "N4", x = 500, y = 80, z = 500 },
        }
        local cx, cy, cz = 200, 100, 300
        local act, pl, replyCh
        for _, n in ipairs(nodes) do
            local d = math.sqrt((cx - n.x)^2 + (cy - n.y)^2 + (cz - n.z)^2)
            act, pl, replyCh = sched:ingestReport({
                targetClient = "AIRCRAFT_01",
                clientSeq = 7,
                nodeId = n.id,
                nodePos = { x = n.x, y = n.y, z = n.z },
                measuredDistance = d,
                clientAltitudeY = cy,
                replyChannel = 10005,
            }, registry, 1000)
        end
        assert_eq(act, "EARLY_SOLVED")
        assert_not_nil(pl)
        assert_eq(pl.status, "FIX_OK")
        assert_eq(replyCh, 10005)
    end)

    it("emits FAIL_GEOMETRY with 150ms tombstone on flushExpired without raising HWM", function()
        local sched = session_scheduler.new({ windowMs = 50, tombstoneTtlMs = 1000 })
        local registry = { nodes = {} }
        -- 3 strictly collinear nodes along Z=0
        local collinear = {
            { id = "C1", x = 0, y = 80, z = 0, d = 120 },
            { id = "C2", x = 100, y = 80, z = 0, d = 100 },
            { id = "C3", x = 200, y = 80, z = 0, d = 120 },
        }
        for _, n in ipairs(collinear) do
            local act = sched:ingestReport({
                targetClient = "AIRCRAFT_01",
                clientSeq = 1,
                nodeId = n.id,
                nodePos = { x = n.x, y = n.y, z = n.z },
                measuredDistance = n.d,
                clientAltitudeY = 80,
                replyChannel = 10005,
            }, registry, 1000)
            assert_eq(act, "BUFFERED")
        end

        local responses = sched:flushExpired(registry, 1060)
        assert_eq(#responses, 1)
        assert_eq(responses[1].replyChannel, 10005)
        assert_eq(responses[1].payload.status, "FAIL_GEOMETRY")
        assert_eq(responses[1].payload.targetClient, "AIRCRAFT_01")
        assert_eq(responses[1].payload.clientSeq, 1)
        assert_nil(sched.client_last_solved["AIRCRAFT_01"], "FAIL_GEOMETRY must not raise HWM")

        -- Late report inside 150ms tombstone window (1060 + 150 = 1210) must be dropped
        local lateAct, _, lateReason = sched:ingestReport({
            targetClient = "AIRCRAFT_01",
            clientSeq = 1,
            nodeId = "C4",
            nodePos = { x = 100, y = 80, z = 200 },
            measuredDistance = 200,
            clientAltitudeY = 80,
            replyChannel = 10005,
        }, registry, 1150)
        assert_eq(lateAct, "DROPPED")
        assert_eq(lateReason, "TOMBSTONE")

        -- Client 250ms retry (t=1250 > 1210) with same clientSeq must succeed when non-collinear node joins
        local retryNodes = {
            { id = "C1", x = 0, y = 80, z = 0 },
            { id = "C2", x = 500, y = 80, z = 0 },
            { id = "C3", x = 0, y = 80, z = 500 },
            { id = "C4", x = 500, y = 80, z = 500 },
        }
        local rAct, rPl, rCh
        for _, n in ipairs(retryNodes) do
            local d = math.sqrt((200 - n.x)^2 + (300 - n.z)^2)
            rAct, rPl, rCh = sched:ingestReport({
                targetClient = "AIRCRAFT_01",
                clientSeq = 1,
                nodeId = n.id,
                nodePos = { x = n.x, y = n.y, z = n.z },
                measuredDistance = d,
                clientAltitudeY = 80,
                replyChannel = 10005,
            }, registry, 1250)
        end
        assert_eq(rAct, "EARLY_SOLVED")
        assert_eq(rPl.status, "FIX_OK")
        assert_eq(rCh, 10005)
    end)

    it("flushes multiple expired sessions in deterministic sorted order", function()
        local sched = session_scheduler.new({ windowMs = 50, tombstoneTtlMs = 1000 })
        local registry = { nodes = {} }
        local clients = {
            { id = "AIRCRAFT_06", ch = 10205 },
            { id = "AIRCRAFT_05", ch = 10165 },
            { id = "AIRCRAFT_04", ch = 10125 },
            { id = "AIRCRAFT_03", ch = 10085 },
            { id = "AIRCRAFT_02", ch = 10045 },
            { id = "AIRCRAFT_01", ch = 10005 },
        }
        for _, c in ipairs(clients) do
            sched:ingestReport({
                targetClient = c.id,
                clientSeq = 1,
                nodeId = "N1",
                nodePos = { x = 0, y = 80, z = 0 },
                measuredDistance = 100,
                clientAltitudeY = 80,
                replyChannel = c.ch,
            }, registry, 1000)
        end
        local responses = sched:flushExpired(registry, 1060)
        assert_eq(#responses, 6)
        assert_eq(responses[1].payload.targetClient, "AIRCRAFT_01")
        assert_eq(responses[2].payload.targetClient, "AIRCRAFT_02")
        assert_eq(responses[3].payload.targetClient, "AIRCRAFT_03")
        assert_eq(responses[4].payload.targetClient, "AIRCRAFT_04")
        assert_eq(responses[5].payload.targetClient, "AIRCRAFT_05")
        assert_eq(responses[6].payload.targetClient, "AIRCRAFT_06")
    end)

    it("evicts older incomplete active sessions on newer seq ingest and skips <= HWM sessions in flushExpired", function()
        local sched = session_scheduler.new({ windowMs = 50, tombstoneTtlMs = 1000 })
        local registry = { nodes = {} }
        local rNodes = {
            { id = "N1", x = 0, y = 80, z = 0 },
            { id = "N2", x = 500, y = 80, z = 0 },
            { id = "N3", x = 0, y = 80, z = 500 },
            { id = "N4", x = 500, y = 80, z = 500 },
        }
        -- Ingest only 2 reports for seq=1 (buffered)
        for i = 1, 2 do
            local n = rNodes[i]
            local act = sched:ingestReport({
                targetClient = "AIRCRAFT_01",
                clientSeq = 1,
                nodeId = n.id,
                nodePos = { x = n.x, y = n.y, z = n.z },
                measuredDistance = 200,
                clientAltitudeY = 80,
                replyChannel = 10005,
            }, registry, 1000)
            assert_eq(act, "BUFFERED")
        end
        assert_not_nil(sched.active_sessions["AIRCRAFT_01:1"])

        -- Newer seq=2 arrives before seq=1 finishes: seq=1 must be evicted and tombstoned
        local act2 = sched:ingestReport({
            targetClient = "AIRCRAFT_01",
            clientSeq = 2,
            nodeId = rNodes[1].id,
            nodePos = { x = rNodes[1].x, y = rNodes[1].y, z = rNodes[1].z },
            measuredDistance = 200,
            clientAltitudeY = 80,
            replyChannel = 10005,
        }, registry, 1010)
        assert_eq(act2, "BUFFERED")
        assert_nil(sched.active_sessions["AIRCRAFT_01:1"])

        local lateAct, _, lateReason = sched:ingestReport({
            targetClient = "AIRCRAFT_01",
            clientSeq = 1,
            nodeId = rNodes[3].id,
            nodePos = { x = rNodes[3].x, y = rNodes[3].y, z = rNodes[3].z },
            measuredDistance = 200,
            clientAltitudeY = 80,
            replyChannel = 10005,
        }, registry, 1020)
        assert_eq(lateAct, "DROPPED")
        assert_eq(lateReason, "TOMBSTONE")

        -- Verify HWM pre-check in flushExpired blocks stale active sessions <= client_last_solved
        sched.client_last_solved["AIRCRAFT_01"] = 5
        sched.active_sessions["AIRCRAFT_01:4"] = {
            targetClient = "AIRCRAFT_01",
            clientSeq = 4,
            clientAltitudeY = 80,
            replyChannel = 10005,
            reports = { N1 = rNodes[1], N2 = rNodes[2], N3 = rNodes[3], N4 = rNodes[4] },
            reportsList = { rNodes[1], rNodes[2], rNodes[3], rNodes[4] },
            expireMs = 1050,
        }
        -- Also clear seq=2 so flushExpired only evaluates seq=4 (stale) and seq=2 (also <= 5)
        local responses = sched:flushExpired(registry, 2000)
        assert_eq(#responses, 0)
        assert_nil(sched.active_sessions["AIRCRAFT_01:4"])
    end)
end)

describe("gps server handlers, CH 60002 status, nodes.json schema, and monitor_ui", function()
    local server = require("server")
    local monitor_ui = require("monitor_ui")
    local session_scheduler = require("session_scheduler")
    local node = require("node")
    local wizard_cli = require("wizard_cli")

    it("initializes registry from /gps_data/nodes.json nodeId/position schema", function()
        local nodesPath = "/gps_data/nodes.json"
        local hadNodes = fs.exists(nodesPath)
        local origRaw = nil
        if hadNodes then
            local f = fs.open(nodesPath, "r")
            origRaw = f and f.readAll()
            if f then f.close() end
        end
        storage_hal.writeJsonAtomic(nodesPath, {
            version = "1.9.5",
            nodes = {
                NODE_01 = { nodeId = "NODE_01", computerId = 1, position = { x = 10, y = 80, z = -20 }, status = "ONLINE" },
                NODE_02 = { nodeId = "NODE_02", computerId = 2, position = { x = 110, y = 80, z = -20 }, status = "OFFLINE" },
            }
        })
        local m = mock.modem({ wireless = true })
        sdk.patch(peripheral, "find", function(ptype)
            if ptype == "modem" then return m end
            return nil
        end)
        local okInit, _, _, _, state = pcall(server.initServer)
        if origRaw then
            local f = fs.open(nodesPath, "w")
            if f then f.write(origRaw); f.close() end
        elseif fs.exists(nodesPath) then
            fs.delete(nodesPath)
        end
        assert_true(okInit, tostring(state))
        assert_eq(#state.nodes, 2)
        assert_eq(state.nodes[1].id, "NODE_01")
        assert_eq(state.nodes[1].x, 10)
        assert_eq(state.nodes[1].z, -20)
        assert_eq(state.activeNodes, 1)
        assert_eq(state.listenChan, 60001)
        assert_eq(state.dataChan, 60002)
    end)

    it("handles EARLY_SOLVED TX, heartbeat payload.pos, and CH 60002 status requests", function()
        local m = mock.modem({ wireless = true })
        local sched = session_scheduler.new({ windowMs = 50, tombstoneTtlMs = 1000 })
        local registry = { nodes = {} }
        local state = {
            ticks = 400, solvedCount = 0, totalSolves = 0, seq = 1,
            activeNodes = 0, clientCount = 0, nodes = {}, clients = {}
        }

        -- Heartbeat with Zero-Fallback payload.pos
        local hbPkt = protocol.buildHeartbeat("NODE_09", 1, {
            nodeId = "NODE_09",
            computerId = 9,
            pos = { x = 123, y = 90, z = -456 },
            status = "ONLINE",
        }, 1000)
        server.handleModemMsg(sched, registry, m, state, { "modem_message", "top", protocol.CH_GPS_NODE_IN, protocol.CH_GPS_PING, hbPkt, 0 })
        assert_eq(#state.nodes, 1)
        assert_eq(state.nodes[1].id, "NODE_09")
        assert_eq(state.nodes[1].x, 123)
        assert_eq(state.nodes[1].z, -456)
        assert_eq(state.activeNodes, 1)

        -- 4-node EARLY_SOLVED must transmit on replyChannel 10005 without error and update clients
        local anchors = {
            { id = "N1", x = 0, y = 80, z = 0 },
            { id = "N2", x = 500, y = 80, z = 0 },
            { id = "N3", x = 0, y = 80, z = 500 },
            { id = "N4", x = 500, y = 80, z = 500 },
        }
        for idx, n in ipairs(anchors) do
            local d = math.sqrt((200 - n.x)^2 + (20 - 0)^2 + (300 - n.z)^2)
            local rep = protocol.buildNodeReport(n.id, idx, {
                targetClient = "AIRCRAFT_01",
                clientSeq = 12,
                nodeId = n.id,
                nodePos = { x = n.x, y = n.y, z = n.z },
                measuredDistance = d,
                clientAltitudeY = 100,
                replyChannel = 10005,
            }, 1010)
            server.handleModemMsg(sched, registry, m, state, { "modem_message", "top", protocol.CH_GPS_NODE_IN, protocol.CH_GPS_PING, rep, 0 })
        end
        assert_eq(state.solvedCount, 1)
        assert_eq(state.clientCount, 1)
        assert_eq(state.clients[1].id, "AIRCRAFT_01")
        assert_eq(m._transmitted[1].tx, 10005)
        assert_eq(m._transmitted[1].rx, protocol.CH_GPS_SERVICE)
        assert_eq(m._transmitted[1].pkt.type, protocol.MSG_RESPONSE)

        -- CH 60002 MSG_GPS_STATUS_REQ
        local stReq = protocol.buildStatusReq("GCS_01", 3, { queryType = "SUMMARY" }, 1020)
        server.handleModemMsg(sched, registry, m, state, { "modem_message", "top", protocol.CH_GPS_SERVICE, 50010, stReq, 0 })
        assert_eq(#m._transmitted, 2)
        assert_eq(m._transmitted[2].tx, 50010)
        assert_eq(m._transmitted[2].pkt.type, protocol.MSG_STATUS_RESP)
        assert_eq(m._transmitted[2].pkt.payload.activeNodes, 1)
        assert_eq(m._transmitted[2].pkt.payload.totalSolved, 1)
        assert_eq(m._transmitted[2].pkt.payload.uptime, 20)
    end)

    it("renders monitor_ui string IDs and 60001/60002 channels without format crash", function()
        local mon = mock.term(79, 36)
        local ui = monitor_ui.new({ width = 79, height = 36 })
        local st = {
            totalSolves = 5,
            activeNodes = 2,
            clientCount = 1,
            listenChan = 60001,
            dataChan = 60002,
            clients = { { id = "AIRCRAFT_01", x = 100.5, y = 80.0, z = -200.5, lastSeen = 0.2 } },
            nodes = { { id = "NODE_01", x = 0, y = 80, z = 0, status = "ONLINE", ping = 12 } },
        }
        ui:setTab(1); ui:render(mon, st)
        assert_true(mon:_contains("60001 (Listen) / 60002 (Data)"))
        ui:setTab(2); ui:render(mon, st)
        assert_true(mon:_contains("AIRCRAFT_01"), "Clients tab must render string IDs")
        assert_false(mon:_contains("Total Solved"), "Tab switch must clear previous tab rows")
        ui:setTab(3); ui:render(mon, st)
        assert_true(mon:_contains("NODE_01"), "Nodes tab must render string IDs")
    end)

    it("increments node report seq monotonically and wizard_cli saves atomically", function()
        sdk.patch(_G, "print", function() end)
        sdk.patch(term, "clear", function() end)
        local m = mock.modem({ wireless = true })
        local nCfg = { nodeId = "NODE_01", computerId = 5, position = { x = 0, y = 80, z = 0 } }
        local st = { reportsSent = 0, reportSeq = 0 }
        local req1 = protocol.buildRequest("AIRCRAFT_01", 1, { replyChannel = 10005, altitudeY = 80, clientType = "AIRCRAFT", clientSeq = 1 }, 1000)
        local req2 = protocol.buildRequest("AIRCRAFT_01", 2, { replyChannel = 10005, altitudeY = 80, clientType = "AIRCRAFT", clientSeq = 2 }, 1100)
        node.handlePingMessage(m, nCfg, protocol.CH_GPS_PING, req1, 50, st)
        node.handlePingMessage(m, nCfg, protocol.CH_GPS_PING, req2, 55, st)
        assert_eq(#m._transmitted, 2)
        assert_eq(m._transmitted[1].pkt.seq, 1)
        assert_eq(m._transmitted[2].pkt.seq, 2)

        local savePath = sdk.temp_path("wiz_node.json")
        sdk.patch(_G, "write", function() end)
        sdk.patch(_G, "read", function() return "100 80 -200" end)
        local evIdx = 0
        local events = {
            { "modem_message", "top", protocol.CH_GPS_MGMT, protocol.CH_GPS_NODE_IN, { ver = "1.9.5", type = protocol.MSG_NODE_OFFER, payload = { suggestedNodeId = "NODE_07" } }, 0 },
            { "modem_message", "top", protocol.CH_GPS_MGMT, protocol.CH_GPS_NODE_IN, { ver = "1.9.5", type = protocol.MSG_NODE_VERIFY_RESP, payload = { passed = true, maxResidual = 0.1 } }, 0 },
            { "modem_message", "top", protocol.CH_GPS_MGMT, protocol.CH_GPS_NODE_IN, { ver = "1.9.5", type = protocol.MSG_NODE_REG_ACK, payload = { status = "COMMITTED" } }, 0 },
        }
        sdk.with_events_allowed(function()
            sdk.patch(os, "pullEvent", function()
                evIdx = evIdx + 1
                return table.unpack(events[evIdx])
            end)
            sdk.patch(os, "startTimer", function() return 1 end)
            sdk.patch(os, "epoch", function() return 1000 end)
            local commissioning = require("commissioning")
            local fsm = commissioning.newFSM({ hasConfig = false, computerId = 7 })
            local cfg = wizard_cli.runWizard(m, fsm, savePath)
            assert_eq(cfg.nodeId, "NODE_07")
            local saved = storage_hal.readJson(savePath)
            assert_not_nil(saved)
            assert_eq(saved.position.x, 100)
        end)
    end)

    it("ignores unregistered node heartbeats when registry is non-empty", function()
        local registry = {
            nodes = {
                NODE_01 = { nodeId = "NODE_01", computerId = 1, position = { x = 0, y = 80, z = 0 }, status = "OFFLINE" },
            }
        }
        local state = {
            ticks = 0, solvedCount = 0, totalSolves = 0, seq = 1,
            activeNodes = 0, clientCount = 0,
            nodes = { { id = "NODE_01", x = 0, y = 80, z = 0, status = "OFFLINE", ping = 0 } },
            clients = {}
        }

        local rogueHb = protocol.buildHeartbeat("ROGUE_99", 1, {
            nodeId = "ROGUE_99",
            computerId = 99,
            pos = { x = 50, y = 80, z = 50 },
            status = "ONLINE",
        }, 1000)
        server.handleHeartbeat(state, rogueHb, registry)
        assert_eq(#state.nodes, 1)
        assert_eq(state.activeNodes, 0)
        assert_nil(registry.nodes["ROGUE_99"])

        local validHb = protocol.buildHeartbeat("NODE_01", 2, {
            nodeId = "NODE_01",
            computerId = 1,
            pos = { x = 10, y = 85, z = -20 },
            status = "ONLINE",
        }, 1010)
        server.handleHeartbeat(state, validHb, registry)
        assert_eq(#state.nodes, 1)
        assert_eq(state.activeNodes, 1)
        assert_eq(state.nodes[1].status, "ONLINE")
        assert_eq(state.nodes[1].x, 10)
        assert_eq(registry.nodes["NODE_01"].status, "ONLINE")
    end)

    it("flushTimerExpired sends FAIL_GEOMETRY without counting solve and commits 3-node fix", function()
        local m = mock.modem({ wireless = true })
        local sched = session_scheduler.new({ windowMs = 50, tombstoneTtlMs = 1000 })
        local registry = { nodes = {} }
        local state = {
            ticks = 0, solvedCount = 0, totalSolves = 0, seq = 1,
            activeNodes = 0, clientCount = 0, nodes = {}, clients = {}
        }
        local nowMs = 1000
        sdk.patch(os, "epoch", function() return nowMs end)

        -- 1. Collinear 3-node batch expires as FAIL_GEOMETRY: TX on replyChannel, zero solve/client count
        local collinear = {
            { id = "C1", x = 0, y = 80, z = 0, d = 120 },
            { id = "C2", x = 100, y = 80, z = 0, d = 100 },
            { id = "C3", x = 200, y = 80, z = 0, d = 120 },
        }
        for idx, n in ipairs(collinear) do
            local rep = protocol.buildNodeReport(n.id, idx, {
                targetClient = "AIRCRAFT_01",
                clientSeq = 1,
                nodeId = n.id,
                nodePos = { x = n.x, y = n.y, z = n.z },
                measuredDistance = n.d,
                clientAltitudeY = 80,
                replyChannel = 10005,
            }, nowMs)
            server.handleModemMsg(sched, registry, m, state, { "modem_message", "top", protocol.CH_GPS_NODE_IN, protocol.CH_GPS_PING, rep, 0 })
        end
        nowMs = 1060
        server.flushTimerExpired(sched, registry, m, state)
        assert_eq(state.solvedCount, 0)
        assert_eq(state.totalSolves, 0)
        assert_eq(state.clientCount, 0)
        assert_eq(#state.clients, 0)
        assert_eq(state.lastSolvedStatus, "FAIL_GEOMETRY")
        assert_eq(#m._transmitted, 1)
        assert_eq(m._transmitted[1].tx, 10005)
        assert_eq(m._transmitted[1].rx, protocol.CH_GPS_SERVICE)
        assert_eq(m._transmitted[1].pkt.type, protocol.MSG_RESPONSE)
        assert_eq(m._transmitted[1].pkt.payload.status, "FAIL_GEOMETRY")

        -- 2. After 150ms tombstone expires, 3 non-collinear nodes wait for timer flush and count 1 fix
        nowMs = 1250
        local triNodes = {
            { id = "N1", x = 0, y = 80, z = 0 },
            { id = "N2", x = 500, y = 80, z = 0 },
            { id = "N3", x = 0, y = 80, z = 500 },
        }
        for idx, n in ipairs(triNodes) do
            local d = math.sqrt((200 - n.x)^2 + (100 - n.y)^2 + (300 - n.z)^2)
            local rep = protocol.buildNodeReport(n.id, idx + 10, {
                targetClient = "AIRCRAFT_01",
                clientSeq = 1,
                nodeId = n.id,
                nodePos = { x = n.x, y = n.y, z = n.z },
                measuredDistance = d,
                clientAltitudeY = 100,
                replyChannel = 10005,
            }, nowMs)
            server.handleModemMsg(sched, registry, m, state, { "modem_message", "top", protocol.CH_GPS_NODE_IN, protocol.CH_GPS_PING, rep, 0 })
        end
        assert_eq(state.solvedCount, 0, "3-node batch must wait for flushTimerExpired")

        nowMs = 1310
        server.flushTimerExpired(sched, registry, m, state)
        assert_eq(state.solvedCount, 1)
        assert_eq(state.totalSolves, 1)
        assert_eq(state.clientCount, 1)
        assert_eq(state.clients[1].id, "AIRCRAFT_01")
        assert_near(state.clients[1].x, 200, 0.5)
        assert_near(state.clients[1].z, 300, 0.5)
        assert_eq(state.clients[1].y, 100)
        assert_eq(#m._transmitted, 2)
        assert_eq(m._transmitted[2].tx, 10005)
        assert_eq(m._transmitted[2].pkt.type, protocol.MSG_RESPONSE)
        assert_true(m._transmitted[2].pkt.payload.status == "FIX_OK" or m._transmitted[2].pkt.payload.status == "FIX_DEGRADED")
    end)
end)

describe("gps client_core TTL pruning and CH 60002 status dispatch", function()
    it("prunes pendingResponses older than 5000ms while preserving active entries", function()
        local c = client_core.new()
        c:init("AIRCRAFT_01", "AIRCRAFT")
        local r1 = protocol.buildResponse("GPS_BASE_NET", 1, {
            targetClient = "AIRCRAFT_01", clientSeq = 1, status = "FIX_OK",
            position = { x = 10, z = 20 }, accuracy = 0.1, hdop = 1.0, nodeCount = 4
        }, 1000)
        local r2 = protocol.buildResponse("GPS_BASE_NET", 2, {
            targetClient = "AIRCRAFT_01", clientSeq = 2, status = "FIX_OK",
            position = { x = 30, z = 40 }, accuracy = 0.1, hdop = 1.0, nodeCount = 4
        }, 5500)
        assert_true(c:handleMessage(10005, r1, 1000))
        assert_true(c:handleMessage(10005, r2, 5500))
        -- Advance beyond 1000 + 5000 = 6000 on next request or message
        local _, _ = c:nextRequestPacket(80, 6200)
        assert_nil(c:poll(1), "Expired unpolled entry (>5000ms) must be pruned")
        local live = c:poll(2)
        assert_not_nil(live)
        assert_eq(live.position.x, 30)
    end)

    it("builds MSG_GPS_STATUS_REQ and consumes MSG_GPS_STATUS_RESP on CH 60002 and replyChannel", function()
        local c = client_core.new()
        c:init("AIRCRAFT_01", "AIRCRAFT")
        local seq, reqPkt = c:nextStatusRequestPacket("SUMMARY", 1000)
        assert_eq(seq, 1)
        assert_true(protocol.validatePacket(reqPkt, protocol.MSG_STATUS_REQ))

        local stResp = protocol.buildStatusResp("GPS_BASE_NET", 5, {
            activeNodes = 4, uptime = 120, totalSolved = 42, version = "1.9.5"
        }, 1020)
        assert_false(c:handleMessage(99999, stResp, 1020))
        assert_true(c:handleMessage(protocol.CH_GPS_SERVICE, stResp, 1020))

        local polled = c:pollStatus()
        assert_not_nil(polled)
        assert_eq(polled.activeNodes, 4)
        assert_eq(polled.totalSolved, 42)
        assert_nil(c:pollStatus())

        -- Verify handleMessage also accepts MSG_GPS_STATUS_RESP on self.replyChannel (10005)
        local stResp2 = protocol.buildStatusResp("GPS_BASE_NET", 6, {
            activeNodes = 3, uptime = 140, totalSolved = 43, version = "1.9.5"
        }, 1030)
        assert_true(c:handleMessage(10005, stResp2, 1030))
        local polled2 = c:pollStatus()
        assert_not_nil(polled2)
        assert_eq(polled2.activeNodes, 3)
        assert_nil(c:pollStatus())
    end)
end)

describe("gps_client HAL managed retry parity and status query", function()
    local gps_client = require("gps_client")

    it("retries once at half-timeout with identical clientSeq when isManaged is true", function()
        local m = mock.modem({ wireless = true })
        sdk.patch(peripheral, "find", function(ptype)
            if ptype == "modem" then return m end
            return nil
        end)
        gps_client.init("AIRCRAFT_01", "AIRCRAFT", 10005)
        gps_client.setManaged(true)

        local nowMs = 1000
        local sleepCalls = 0
        sdk.with_events_allowed(function()
            sdk.patch(os, "epoch", function() return nowMs end)
            sdk.patch(_G, "sleep", function(sec)
                sleepCalls = sleepCalls + 1
                nowMs = nowMs + math.floor((tonumber(sec) or 0.05) * 1000)
                if sleepCalls == 6 and #m._transmitted >= 2 then
                    local secondSeq = m._transmitted[2].pkt.payload.clientSeq
                    local resp = protocol.buildResponse("GPS_BASE_NET", 1, {
                        targetClient = "AIRCRAFT_01",
                        clientSeq = secondSeq,
                        status = "FIX_OK",
                        position = { x = 250.0, z = -125.0 },
                        accuracy = 0.2,
                        hdop = 1.1,
                        nodeCount = 4,
                    }, nowMs)
                    gps_client.handleMessage("top", 10005, 60002, resp, 10)
                end
            end)
            local x, y, z, meta = gps_client.locate(120.0, 0.5)
            assert_near(x, 250.0, 1e-4)
            assert_eq(y, 120.0)
            assert_near(z, -125.0, 1e-4)
            assert_eq(meta.status, "FIX_OK")
        end)
        gps_client.setManaged(false)
        assert_eq(#m._transmitted, 2, "isManaged locate must emit initial + 1 half-timeout retry")
        assert_eq(m._transmitted[1].pkt.payload.clientSeq, m._transmitted[2].pkt.payload.clientSeq)
    end)

    it("exposes requestStatus and pollStatus over CH 60002", function()
        local m = mock.modem({ wireless = true })
        sdk.patch(peripheral, "find", function(ptype)
            if ptype == "modem" then return m end
            return nil
        end)
        gps_client.init("AIRCRAFT_01", "AIRCRAFT", 10005)
        local seq = gps_client.requestStatus("SUMMARY", protocol.CH_GPS_SERVICE)
        assert_true(seq >= 1)
        assert_eq(m._transmitted[1].tx, protocol.CH_GPS_SERVICE)
        assert_eq(m._transmitted[1].rx, protocol.CH_GPS_SERVICE)
        assert_eq(m._transmitted[1].pkt.type, protocol.MSG_STATUS_REQ)

        local resp = protocol.buildStatusResp("GPS_BASE_NET", 2, {
            activeNodes = 5, uptime = 60, totalSolved = 9, version = "1.9.5"
        }, 2000)
        assert_true(gps_client.handleMessage("top", protocol.CH_GPS_SERVICE, protocol.CH_GPS_SERVICE, resp, 0))
        local polled = gps_client.pollStatus()
        assert_not_nil(polled)
        assert_eq(polled.activeNodes, 5)
    end)

    it("handles isManaged locate failure paths: NO_MODEM, FAIL_GEOMETRY, and TIMEOUT with nil/frozen os.epoch", function()
        -- 1. NO_MODEM
        sdk.patch(peripheral, "find", function() return nil end)
        gps_client.init("AIRCRAFT_01", "AIRCRAFT", 10005)
        gps_client.setManaged(true)
        local x1, y1, z1, meta1 = gps_client.locate(120.0, 0.5)
        gps_client.setManaged(false)
        assert_nil(x1)
        assert_nil(y1)
        assert_nil(z1)
        assert_not_nil(meta1)
        assert_eq(meta1.status, "NO_MODEM")

        -- 2. FAIL_GEOMETRY returning nil, nil, nil, fix
        local m = mock.modem({ wireless = true })
        sdk.patch(peripheral, "find", function(ptype)
            if ptype == "modem" then return m end
            return nil
        end)
        gps_client.init("AIRCRAFT_01", "AIRCRAFT", 10005)
        gps_client.setManaged(true)
        sdk.with_events_allowed(function()
            sdk.patch(os, "epoch", function() return 1000 end)
            sdk.patch(_G, "sleep", function(sec)
                local failPkt = protocol.buildResponse("GPS_BASE_NET", 1, {
                    targetClient = "AIRCRAFT_01",
                    clientSeq = m._transmitted[1].pkt.payload.clientSeq,
                    status = "FAIL_GEOMETRY",
                    nodeCount = 3,
                }, 1010)
                gps_client.handleMessage("top", 10005, 60002, failPkt, 10)
            end)
            local x2, y2, z2, meta2 = gps_client.locate(120.0, 0.5)
            assert_nil(x2)
            assert_nil(y2)
            assert_nil(z2)
            assert_not_nil(meta2)
            assert_eq(meta2.status, "FAIL_GEOMETRY")
        end)
        gps_client.setManaged(false)

        -- 3. TIMEOUT with frozen os.epoch
        m._transmitted = {}
        gps_client.setManaged(true)
        local sleepCount = 0
        sdk.with_events_allowed(function()
            sdk.patch(os, "epoch", function() return 5000 end) -- non-advancing epoch
            sdk.patch(_G, "sleep", function(sec) sleepCount = sleepCount + 1 end)
            local x3, y3, z3, meta3 = gps_client.locate(120.0, 0.1)
            assert_nil(x3)
            assert_eq(meta3.status, "TIMEOUT")
            assert_true(sleepCount >= 2, "fallback counter must advance despite frozen os.epoch")
        end)
        gps_client.setManaged(false)

        -- 4. TIMEOUT with nil os.epoch
        m._transmitted = {}
        gps_client.setManaged(true)
        local sleepCountNil = 0
        sdk.with_events_allowed(function()
            sdk.patch(os, "epoch", nil) -- os.epoch is nil
            sdk.patch(_G, "sleep", function(sec) sleepCountNil = sleepCountNil + 1 end)
            local x4, y4, z4, meta4 = gps_client.locate(120.0, 0.1)
            assert_nil(x4)
            assert_eq(meta4.status, "TIMEOUT")
            assert_true(sleepCountNil >= 2, "fallback counter must advance despite nil os.epoch")
        end)
        gps_client.setManaged(false)
    end)

    it("executes isManaged queryStatus: NO_MODEM, stale flushing, replyChannel routing, and TIMEOUT", function()
        -- 1. NO_MODEM returns nil, "NO_MODEM"
        sdk.patch(peripheral, "find", function() return nil end)
        gps_client.setManaged(true)
        local st1, err1 = gps_client.queryStatus(0.5, "SUMMARY")
        gps_client.setManaged(false)
        assert_nil(st1)
        assert_eq(err1, "NO_MODEM")

        -- 2. Stale status flushed, sends replyChannel = instance.replyChannel (10005), and succeeds
        local m = mock.modem({ wireless = true })
        sdk.patch(peripheral, "find", function(ptype)
            if ptype == "modem" then return m end
            return nil
        end)
        gps_client.init("AIRCRAFT_01", "AIRCRAFT", 10005)
        gps_client.setManaged(true)
        -- Inject stale status:
        local staleResp = protocol.buildStatusResp("GPS_BASE_NET", 1, { activeNodes = 99 }, 500)
        gps_client.handleMessage("top", 10005, 60002, staleResp, 0)
        assert_not_nil(gps_client.pollStatus(), "stale status injected")
        -- Re-inject so instance:pollStatus() in queryStatus must flush it
        gps_client.handleMessage("top", 10005, 60002, staleResp, 0)

        local sleepCalls = 0
        sdk.with_events_allowed(function()
            sdk.patch(os, "epoch", function() return 1000 + sleepCalls * 50 end)
            sdk.patch(_G, "sleep", function(sec)
                sleepCalls = sleepCalls + 1
                if sleepCalls == 1 then
                    -- Verify transmitted request packet: TX to CH_GPS_SERVICE (60002), RX set to instance.replyChannel (10005)
                    assert_eq(#m._transmitted, 1)
                    assert_eq(m._transmitted[1].tx, protocol.CH_GPS_SERVICE)
                    assert_eq(m._transmitted[1].rx, 10005)
                    local freshResp = protocol.buildStatusResp("GPS_BASE_NET", 2, {
                        activeNodes = 4, uptime = 40, totalSolved = 15, version = "1.9.5"
                    }, 1050)
                    gps_client.handleMessage("top", 10005, 60002, freshResp, 0)
                end
            end)
            local st2, err2 = gps_client.queryStatus(0.5, "SUMMARY")
            assert_nil(err2)
            assert_not_nil(st2)
            assert_eq(st2.activeNodes, 4)
            assert_eq(st2.totalSolved, 15)
        end)
        gps_client.setManaged(false)

        -- 3. TIMEOUT with nil os.epoch
        m._transmitted = {}
        gps_client.setManaged(true)
        sdk.with_events_allowed(function()
            sdk.patch(os, "epoch", nil)
            sdk.patch(_G, "sleep", function(sec) end)
            local st3, err3 = gps_client.queryStatus(0.1, "SUMMARY")
            assert_nil(st3)
            assert_eq(err3, "TIMEOUT")
        end)
        gps_client.setManaged(false)
    end)

    it("executes standalone queryStatus: success, channel lifecycle, default 1.0s timeout, and NO_MODEM", function()
        -- 1. NO_MODEM
        sdk.patch(peripheral, "find", function() return nil end)
        gps_client.setManaged(false)
        local st1, err1 = gps_client.queryStatus(0.5, "SUMMARY")
        assert_nil(st1)
        assert_eq(err1, "NO_MODEM")

        -- 2. Success, verifies default 1.0s timeout and CH_GPS_SERVICE closed after completion
        local m = mock.modem({ wireless = true })
        sdk.patch(peripheral, "find", function(ptype)
            if ptype == "modem" then return m end
            return nil
        end)
        gps_client.init("AIRCRAFT_01", "AIRCRAFT", 10005)
        gps_client.setManaged(false)
        assert_false(m.isOpen(protocol.CH_GPS_SERVICE))

        local timerSec = nil
        local resp = protocol.buildStatusResp("GPS_BASE_NET", 3, {
            activeNodes = 6, uptime = 100, totalSolved = 25, version = "1.9.5"
        }, 2000)

        sdk.with_events_allowed(function()
            sdk.patch(os, "startTimer", function(sec)
                timerSec = sec
                return 77
            end)
            sdk.patch(os, "pullEvent", function()
                assert_true(m.isOpen(protocol.CH_GPS_SERVICE), "channel must be open while listening")
                return "modem_message", "top", protocol.CH_GPS_SERVICE, protocol.CH_GPS_SERVICE, resp, 0
            end)
            local st2, err2 = gps_client.queryStatus(nil, "SUMMARY") -- nil timeoutSec tests 1.0s default
            assert_nil(err2)
            assert_not_nil(st2)
            assert_eq(st2.activeNodes, 6)
            assert_eq(timerSec, 1.0, "queryStatus default timeout must be 1.0s")
            assert_false(m.isOpen(protocol.CH_GPS_SERVICE), "channel must be closed after response if previously unopened")
        end)

        -- 3. TIMEOUT when channel was already open: remains open afterwards
        m.open(protocol.CH_GPS_SERVICE)
        assert_true(m.isOpen(protocol.CH_GPS_SERVICE))
        sdk.with_events_allowed(function()
            sdk.patch(os, "startTimer", function(sec) return 88 end)
            sdk.patch(os, "pullEvent", function() return "timer", 88 end)
            local st3, err3 = gps_client.queryStatus(0.5, "SUMMARY")
            assert_nil(st3)
            assert_eq(err3, "TIMEOUT")
            assert_true(m.isOpen(protocol.CH_GPS_SERVICE), "channel must remain open if opened before query")
        end)
        m.close(protocol.CH_GPS_SERVICE)
    end)
end)
