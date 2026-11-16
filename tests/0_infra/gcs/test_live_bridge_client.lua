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
end)
