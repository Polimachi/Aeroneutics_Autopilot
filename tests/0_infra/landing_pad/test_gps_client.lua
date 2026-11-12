-- tests/0_infra/landing_pad/test_gps_client.lua
local gps_client = require("gps_client")
local offset_transform = require("offset_transform")

describe("Landing pad GPS client and 20Hz dead reckoning", function()
    local dummyCfg = {
        facilityId = "PAD_ALPHA",
        sectorId = 1,
        mobility = "DYNAMIC",
        channels = {
            sectorGpsReplyChannel = 50206
        },
        position = { x = 100.0, y = 64.0, z = 200.0 },
        mountingYawOffset = 0.0,
        bodyOffset = { forward = 5.0, right = 0.0, up = 1.0 }
    }

    it("builds standard MSG_GPS_REQUEST packet with FACILITY type and derives 50206 default", function()
        local client = gps_client.create(dummyCfg, offset_transform)
        local pkt = client:build_request_packet(64.5, 12345678)
        assert_eq(pkt.ver, "1.9.5")
        assert_eq(pkt.type, "MSG_GPS_REQUEST")
        assert_eq(pkt.domainId, "PAD_ALPHA")
        assert_eq(pkt.payload.replyChannel, 50206)
        assert_eq(pkt.payload.altitudeY, 64.5)
        assert_eq(pkt.payload.clientType, "FACILITY")
        assert_eq(pkt.payload.clientSeq, 1)

        local flatDerived = gps_client.create({
            facilityId = "PAD_NO_CH",
            sectorId = 2,
            mobility = "STATIC",
            position = { x = 0, y = 64, z = 0 },
        }, offset_transform)
        local pkt2 = flatDerived:build_request_packet(64.0, 2000)
        assert_eq(pkt2.payload.replyChannel, 50406)
    end)

    it("handles FIX_OK and FIX_DEGRADED MSG_GPS_RESPONSE and rejects legacy/replayed/foreign packets", function()
        local client = gps_client.create(dummyCfg, offset_transform)
        assert_false(client:has_valid_fix())

        -- Unrequested response (pendingSeq == nil) must be rejected
        local unsolicited = {
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 1, time = 900,
            payload = { targetClient = "PAD_ALPHA", clientSeq = 1, status = "FIX_OK", position = { x = 10, z = 20 } }
        }
        assert_false(client:handle_response_packet(unsolicited, 9.0))

        local req = client:build_request_packet(64.0, 1000)
        local seq1 = req.payload.clientSeq

        -- Legacy OK / SUCCESS and non-1.9.5 / foreign target must be rejected
        assert_false(client:handle_response_packet({
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 2, time = 1010,
            payload = { targetClient = "PAD_ALPHA", clientSeq = seq1, status = "OK", position = { x = 10, z = 20 } }
        }, 10.0))
        assert_false(client:handle_response_packet({
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 3, time = 1010,
            payload = { targetClient = "PAD_ALPHA", clientSeq = seq1, status = "SUCCESS", position = { x = 10, z = 20 } }
        }, 10.0))
        assert_false(client:handle_response_packet({
            ver = "1.8.0", type = "MSG_GPS_RESPONSE", seq = 4, time = 1010,
            payload = { targetClient = "PAD_ALPHA", clientSeq = seq1, status = "FIX_OK", position = { x = 10, z = 20 } }
        }, 10.0))
        assert_false(client:handle_response_packet({
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 5, time = 1010,
            payload = { targetClient = "PAD_BETA", clientSeq = seq1, status = "FIX_OK", position = { x = 10, z = 20 } }
        }, 10.0))
        assert_false(client:handle_response_packet({
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 6, time = 1010,
            payload = { targetClient = "PAD_ALPHA", clientSeq = 999, status = "FIX_OK", position = { x = 10, z = 20 } }
        }, 10.0))

        local validResp = {
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 7, time = 1020,
            payload = {
                targetClient = "PAD_ALPHA",
                clientSeq = seq1,
                status = "FIX_OK",
                position = { x = 840.0, z = 1120.0 },
                accuracy = 0.2,
                hdop = 1.1
            }
        }
        assert_true(client:handle_response_packet(validResp, 10.0))
        assert_true(client:has_valid_fix())
        -- Replaying the already consumed clientSeq must be rejected
        assert_false(client:handle_response_packet(validResp, 10.1))

        local compPos = client:get_current_comp_pos()
        assert_near(compPos.x, 840.0, 1e-4)
        assert_near(compPos.z, 1120.0, 1e-4)
        local padPos = client:get_current_pad_pos()
        assert_near(padPos.x, 840.0, 1e-4)
        assert_near(padPos.y, 65.0, 1e-4)
        assert_near(padPos.z, 1115.0, 1e-4)

        -- FAIL_GEOMETRY consumes pendingSeq cleanly and rejects coordinate update
        local req2 = client:build_request_packet(64.0, 1100)
        assert_false(client:handle_response_packet({
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 8, time = 1120,
            payload = { targetClient = "PAD_ALPHA", clientSeq = req2.payload.clientSeq, status = "FAIL_GEOMETRY" }
        }, 11.2))
        assert_false(client:handle_response_packet({
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 9, time = 1130,
            payload = { targetClient = "PAD_ALPHA", clientSeq = req2.payload.clientSeq, status = "FIX_OK", position = { x = 0, z = 0 } }
        }, 11.3))

        -- FIX_DEGRADED is accepted for new request
        local req3 = client:build_request_packet(64.0, 1200)
        assert_true(client:handle_response_packet({
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 10, time = 1220,
            payload = { targetClient = "PAD_ALPHA", clientSeq = req3.payload.clientSeq, status = "FIX_DEGRADED", position = { x = 842.0, z = 1121.0 }, hdop = 6.2 }
        }, 12.2))
        assert_near(client:get_current_comp_pos().x, 842.0, 1e-4)
    end)

    it("enforces dual-rate (1Hz / 5Hz / STATIC-once) GPS query scheduling and STATIC health", function()
        local dynClient = gps_client.create(dummyCfg, offset_transform)
        assert_false(dynClient:should_query_gps("IDLE", 4))
        assert_true(dynClient:should_query_gps("IDLE", 20))
        assert_true(dynClient:should_query_gps("RESERVED", 4))
        assert_true(dynClient:should_query_gps("APPROACH_DYNAMIC", 8))
        assert_false(dynClient:should_query_gps("APPROACH_DYNAMIC", 9))

        local statClient = gps_client.create({
            facilityId = "PAD_STATIC_01",
            sectorId = 1,
            mobility = "STATIC",
            position = { x = 0, y = 64, z = 0 },
        }, offset_transform)
        assert_true(statClient:should_query_gps("IDLE", 20))
        local sReq = statClient:build_request_packet(64.0, 1000)
        assert_true(statClient:handle_response_packet({
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 1, time = 1020,
            payload = { targetClient = "PAD_STATIC_01", clientSeq = sReq.payload.clientSeq, status = "FIX_OK", position = { x = 50.0, z = 60.0 } }
        }, 10.0))
        assert_false(statClient:should_query_gps("IDLE", 40))
        assert_true(statClient:check_gps_health(999.0))
        assert_false(statClient:is_degraded())
    end)

    it("integrates dead reckoning at 20Hz (dt = 0.05) using velocity", function()
        local client = gps_client.create(dummyCfg, offset_transform)
        client:set_comp_pos(100.0, 60.0, 200.0)
        client:update_dead_reckoning(0.05, {
            velocity = { vx = 10.0, vy = 2.0, vz = -5.0 },
            acceleration = { ax = 0.0, ay = 0.0, az = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, yaw = 90.0 }
        })
        assert_near(client:get_current_comp_pos().x, 100.5, 1e-4)
        assert_near(client:get_current_comp_pos().y, 60.1, 1e-4)
        assert_near(client:get_current_comp_pos().z, 199.75, 1e-4)
    end)

    it("flags degraded health when DYNAMIC GPS ping silent > 2.0s", function()
        local client = gps_client.create(dummyCfg, offset_transform)
        client:set_last_gps_time(10.0)
        assert_true(client:check_gps_health(11.5))
        assert_false(client:check_gps_health(12.5))
        assert_true(client:is_degraded())
    end)

    it("rejects FAIL_INSUFFICIENT and malformed FIX_OK, and skips dead reckoning in STATIC mode", function()
        local client = gps_client.create(dummyCfg, offset_transform)
        local req1 = client:build_request_packet(64.0, 1000)
        assert_false(client:handle_response_packet({
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 1, time = 1010,
            payload = { targetClient = "PAD_ALPHA", clientSeq = req1.payload.clientSeq, status = "FAIL_INSUFFICIENT" }
        }, 10.0))
        assert_false(client:has_valid_fix())
        assert_false(client:handle_response_packet({
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 2, time = 1020,
            payload = { targetClient = "PAD_ALPHA", clientSeq = req1.payload.clientSeq, status = "FIX_OK", position = { x = 1, z = 2 } }
        }, 10.1))

        local req2 = client:build_request_packet(64.0, 1100)
        assert_false(client:handle_response_packet({
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 3, time = 1110,
            payload = { targetClient = "PAD_ALPHA", clientSeq = req2.payload.clientSeq, status = "FIX_OK", position = { x = 50.0 } }
        }, 11.1))
        assert_false(client:has_valid_fix())
        assert_near(client:get_current_comp_pos().x, 100.0, 1e-4)

        assert_false(client:should_query_gps("RESERVED", 0))
        assert_false(client:should_query_gps("OCCUPIED", 4))
        assert_true(client:should_query_gps("OCCUPIED", 20))
        assert_true(client:should_query_gps("GO_AROUND", 40))

        local statClient = gps_client.create({
            facilityId = "PAD_STATIC_DR",
            sectorId = 1,
            mobility = "STATIC",
            position = { x = 10.0, y = 64.0, z = 20.0 }
        }, offset_transform)
        statClient:update_dead_reckoning(0.05, {
            velocity = { vx = 50.0, vy = 5.0, vz = -25.0 },
            acceleration = { ax = 1.0, ay = 0.0, az = 1.0 }
        })
        assert_near(statClient:get_current_comp_pos().x, 10.0, 1e-4)
        assert_near(statClient:get_current_comp_pos().y, 64.0, 1e-4)
        assert_near(statClient:get_current_comp_pos().z, 20.0, 1e-4)
    end)

    it("retries STATIC pre-fix after FAIL_GEOMETRY and enforces canonical mobility and flat replyChannel precedence", function()
        local statRetry = gps_client.create({
            facilityId = "PAD_STATIC_RETRY",
            sectorId = 1,
            mobility = "static",
            position = { x = 0, y = 64, z = 0 }
        }, offset_transform)
        assert_true(statRetry:should_query_gps("IDLE", 20))
        local req = statRetry:build_request_packet(64.0, 1000)
        assert_false(statRetry:handle_response_packet({
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 1, time = 1010,
            payload = { targetClient = "PAD_STATIC_RETRY", clientSeq = req.payload.clientSeq, status = "FAIL_GEOMETRY" }
        }, 1.0))
        assert_false(statRetry:has_valid_fix())
        assert_true(statRetry:should_query_gps("IDLE", 40))
        assert_false(statRetry:check_gps_health(2.5))
        assert_true(statRetry:is_degraded())

        local fallbackClient = gps_client.create({
            facilityId = "",
            padId = "PAD_FALLBACK",
            sectorId = 1,
            mobility = "",
            mode = "dynamic",
            sectorGpsReplyChannel = 50806,
            channels = { sectorGpsReplyChannel = 50206 },
            position = { x = 0, y = 64, z = 0 }
        }, offset_transform)
        local fPkt = fallbackClient:build_request_packet(64.0, 2000)
        assert_eq(fPkt.domainId, "PAD_FALLBACK")
        assert_eq(fPkt.payload.replyChannel, 50806)
        fallbackClient:update_dead_reckoning(0.05, {
            velocity = { vx = 20.0, vy = 0.0, vz = 0.0 }
        })
        assert_near(fallbackClient:get_current_comp_pos().x, 1.0, 1e-4)

        local okBad = pcall(gps_client.create, {
            facilityId = "PAD_BAD_MOB",
            mobility = "BOGUS"
        }, offset_transform)
        assert_false(okBad)
    end)

    it("rejects non-finite (NaN, +Inf, -Inf) coordinates in MSG_GPS_RESPONSE without poisoning fix state", function()
        local client = gps_client.create(dummyCfg, offset_transform)
        local badCoords = {
            { x = 0 / 0, z = 200.0 },
            { x = 100.0, z = 0 / 0 },
            { x = math.huge, z = 200.0 },
            { x = 100.0, z = -math.huge },
        }
        for i, pos in ipairs(badCoords) do
            local req = client:build_request_packet(64.0, 1000 + i * 100)
            assert_false(client:handle_response_packet({
                ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = i, time = 1010 + i * 100,
                payload = {
                    targetClient = "PAD_ALPHA",
                    clientSeq = req.payload.clientSeq,
                    status = "FIX_OK",
                    position = pos,
                    accuracy = 0.2,
                    hdop = 1.0,
                }
            }, 10.0 + i))
            assert_false(client:has_valid_fix())
            assert_near(client:get_current_comp_pos().x, 100.0, 1e-4)
            assert_near(client:get_current_comp_pos().z, 200.0, 1e-4)
        end

        -- Establish a valid fix first, then confirm non-finite response does not overwrite it
        local goodReq = client:build_request_packet(64.0, 2000)
        assert_true(client:handle_response_packet({
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 10, time = 2010,
            payload = {
                targetClient = "PAD_ALPHA",
                clientSeq = goodReq.payload.clientSeq,
                status = "FIX_OK",
                position = { x = 300.0, z = 400.0 },
                accuracy = 0.2,
                hdop = 1.0,
            }
        }, 20.0))
        assert_true(client:has_valid_fix())

        local poisonReq = client:build_request_packet(64.0, 2100)
        assert_false(client:handle_response_packet({
            ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 11, time = 2110,
            payload = {
                targetClient = "PAD_ALPHA",
                clientSeq = poisonReq.payload.clientSeq,
                status = "FIX_OK",
                position = { x = 0 / 0, z = math.huge },
                accuracy = 0.2,
                hdop = 1.0,
            }
        }, 21.0))
        assert_true(client:has_valid_fix())
        assert_near(client:get_current_comp_pos().x, 300.0, 1e-4)
        assert_near(client:get_current_comp_pos().z, 400.0, 1e-4)
    end)
end)
