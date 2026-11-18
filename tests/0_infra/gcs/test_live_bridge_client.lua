-- tests/0_infra/gcs/test_live_bridge_client.lua
local live_bridge_client = require("live_bridge_client")

describe("GCS live_bridge_client WebSocket module", function()
    local function create_mock_ws()
        return {
            sent = {},
            inbox = {},
            closed = false,
            send = function(self, raw) table.insert(self.sent, raw) end,
            receive = function(self) return table.remove(self.inbox, 1) end,
            close = function(self) self.closed = true end,
        }
    end

    it("degrades gracefully when disabled or http API unavailable", function()
        local s1 = live_bridge_client.init({ liveBridge = { enabled = false, url = "ws://127.0.0.1:8765" } }, nil)
        local ok1, err1 = live_bridge_client.connect(s1)
        assert_false(ok1)
        assert_eq(err1, "DISABLED")

        local s2 = live_bridge_client.init({ liveBridge = { enabled = true, url = "ws://127.0.0.1:8765" } }, {})
        local ok2, err2 = live_bridge_client.connect(s2)
        assert_false(ok2)
        assert_eq(err2, "HTTP_WS_UNAVAILABLE")
    end)

    it("connects, sends WORLD_PRESET_SYNC, FLEET_TELEMETRY_SYNC, MISSION_PUSH_ACK, and decodes MISSION_PUSH_CMD", function()
        local ws = create_mock_ws()
        local mock_http = {
            websocket = function(url)
                assert_eq(url, "ws://127.0.0.1:8765")
                return ws
            end,
        }
        local st = live_bridge_client.init({ liveBridge = { enabled = true, url = "ws://127.0.0.1:8765" } }, mock_http)
        assert_true(live_bridge_client.connect(st))
        assert_true(st.connected)

        assert_true(live_bridge_client.send_world_preset(st, {
            sectorId = 2,
            sectorName = "Sector Bravo",
            facilities = { { facilityId = "PAD_B1", facilityType = "LANDING_PAD", status = "FREE", position = { x = 10, y = 65, z = -20 } } },
        }))
        local w_msg = textutils.unserializeJSON(ws.sent[1])
        assert_eq(w_msg.type, "WORLD_PRESET_SYNC")
        assert_eq(w_msg.sectorId, 2)
        assert_eq(w_msg.facilities[1].facilityId, "PAD_B1")

        local fleet = {
            craft_order = { "AIRCRAFT_01" },
            crafts = {
                AIRCRAFT_01 = {
                    domainId = "AIRCRAFT_01",
                    baseChannel = 10000,
                    isStale = false,
                    telemetry = {
                        fsmState = "CRUISE",
                        fuel = 0.77,
                        attitude = { pitch = 1.5, roll = -0.5, yaw = 90.0 },
                        dynamics = { altitudeY = 120.0, groundSpeed = 14.5 },
                        navigation = { currentPos = { x = 220, y = 120, z = -140 } },
                    },
                },
            },
        }
        assert_true(live_bridge_client.send_fleet_telemetry(st, fleet))
        local f_msg = textutils.unserializeJSON(ws.sent[2])
        assert_eq(f_msg.type, "FLEET_TELEMETRY_SYNC")
        assert_eq(f_msg.crafts[1].domainId, "AIRCRAFT_01")
        assert_eq(f_msg.crafts[1].position.x, 220)
        assert_eq(f_msg.crafts[1].attitude.yaw, 90.0)

        assert_true(live_bridge_client.send_mission_ack(st, "req-9", "AIRCRAFT_01", {
            action = "LOAD", status = "ACCEPTED", missionId = "M1", missionState = "IDLE",
        }))
        local a_msg = textutils.unserializeJSON(ws.sent[3])
        assert_eq(a_msg.type, "MISSION_PUSH_ACK")
        assert_eq(a_msg.requestId, "req-9")
        assert_eq(a_msg.status, "ACCEPTED")

        local cmd, cmd_err = live_bridge_client.parse_incoming(textutils.serializeJSON({
            type = "MISSION_PUSH_CMD",
            requestId = "req-10",
            targetCraft = "AIRCRAFT_01",
            action = "RUN",
        }))
        assert_nil(cmd_err)
        assert_eq(cmd.type, "MISSION_PUSH_CMD")
        assert_eq(cmd.requestId, "req-10")

        live_bridge_client.close(st)
        assert_true(ws.closed)
        assert_false(st.connected)
    end)

    it("attaches gacNode (explicit position or facility centroid) to WORLD_PRESET_SYNC and sends GPS_NODES_SYNC", function()
        local sent = {}
        local mock_ws = {
            send = function(_, txt) table.insert(sent, txt) end,
            close = function() end,
        }
        local st = live_bridge_client.init({
            liveBridge = { enabled = true, url = "ws://127.0.0.1:8765" },
        }, {
            websocket = function() return mock_ws end,
        })
        assert_true(live_bridge_client.connect(st))

        -- 1. Explicit GAC position
        assert_true(live_bridge_client.send_world_preset(st, {
            sectorId = "ALPHA_01",
            sectorName = "Alpha Apron",
            gacChannel = 50201,
            status = "OPERATIONAL",
            position = { x = 500, y = 70, z = -600 },
            facilities = {
                { facilityId = "PAD_01", facilityType = "LANDING_PAD", position = { x = 100, y = 64, z = -200 } },
            },
        }))
        local msg_exp = textutils.unserializeJSON(sent[1])
        assert_eq(msg_exp.type, "WORLD_PRESET_SYNC")
        assert_not_nil(msg_exp.gacNode)
        assert_eq(msg_exp.gacNode.facilityId, "GAC_ALPHA_01")
        assert_eq(msg_exp.gacNode.facilityType, "GAC")
        assert_eq(msg_exp.gacNode.position.x, 500)
        assert_eq(msg_exp.gacNode.position.z, -600)

        -- 2. Legacy centroid fallback when position omitted
        assert_true(live_bridge_client.send_world_preset(st, {
            sectorId = "BETA_02",
            sectorName = "Beta Outpost",
            facilities = {
                { facilityId = "PAD_1", facilityType = "LANDING_PAD", position = { x = 100, y = 60, z = 200 } },
                { facilityId = "PAD_2", facilityType = "LANDING_PAD", position = { x = 200, y = 80, z = 400 } },
            },
        }))
        local msg_cen = textutils.unserializeJSON(sent[2])
        assert_not_nil(msg_cen.gacNode)
        assert_eq(msg_cen.gacNode.facilityId, "GAC_BETA_02")
        assert_eq(msg_cen.gacNode.position.x, 150)
        assert_eq(msg_cen.gacNode.position.y, 70)
        assert_eq(msg_cen.gacNode.position.z, 300)

        -- 3. GPS_NODES_SYNC sorted list
        assert_true(live_bridge_client.send_gps_nodes(st, {
            GPS_02 = {
                facilityId = "GPS_02", facilityType = "GPS", status = "ONLINE", isStale = false,
                position = { x = 20, y = 240, z = 30 }, computerId = 2, uptime = 10, reportsSent = 5, lastSeen = 1000,
            },
            GPS_01 = {
                facilityId = "GPS_01", facilityType = "GPS", status = "OFFLINE", isStale = true,
                position = { x = 10, y = 240, z = 15 }, computerId = 1, uptime = 90, reportsSent = 50, lastSeen = 500,
            },
        }))
        local msg_gps = textutils.unserializeJSON(sent[3])
        assert_eq(msg_gps.type, "GPS_NODES_SYNC")
        assert_eq(#msg_gps.nodes, 2)
        assert_eq(msg_gps.nodes[1].facilityId, "GPS_01")
        assert_eq(msg_gps.nodes[1].status, "OFFLINE")
        assert_true(msg_gps.nodes[1].isStale)
        assert_eq(msg_gps.nodes[2].facilityId, "GPS_02")
    end)
end)
