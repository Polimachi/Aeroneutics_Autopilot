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

