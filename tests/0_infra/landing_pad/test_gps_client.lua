-- tests/0_infra/landing_pad/test_gps_client.lua
local gps_client = require("gps_client")
local offset_transform = require("offset_transform")

describe("Landing pad GPS client and 20Hz dead reckoning", function()
    local dummyCfg = {
        padId = "PAD_ALPHA",
        mode = "DYNAMIC",
        channels = {
            sectorGpsReplyChannel = 50206
        },
        position = { x = 100.0, y = 64.0, z = 200.0 },
        mountingYawOffset = 0.0,
        bodyOffset = { forward = 5.0, right = 0.0, up = 1.0 }
    }

    it("builds standard MSG_GPS_REQUEST packet", function()
        local client = gps_client.create(dummyCfg, offset_transform)
        local pkt = client:build_request_packet(64.5, 12345678)
        assert_eq(pkt.ver, "1.9.5")
        assert_eq(pkt.type, "MSG_GPS_REQUEST")
        assert_eq(pkt.domainId, "PAD_ALPHA")
        assert_eq(pkt.payload.replyChannel, 50206)
        assert_eq(pkt.payload.altitudeY, 64.5)
        assert_eq(pkt.payload.clientType, "LANDING_PAD")
    end)

    it("handles MSG_GPS_RESPONSE and updates comp/pad coordinates", function()
        local client = gps_client.create(dummyCfg, offset_transform)
        local resp = {
            ver = "1.9.5",
            type = "MSG_GPS_RESPONSE",
            seq = 1,
            time = 1000,
            payload = {
                targetClient = "PAD_ALPHA",
                clientSeq = 1,
                status = "OK",
                position = { x = 840.0, z = 1120.0 }
            }
        }
        local handled = client:handle_response_packet(resp, 10.0)
        assert_true(handled)

        local compPos = client:get_current_comp_pos()
        assert_near(compPos.x, 840.0, 1e-4)
        assert_near(compPos.z, 1120.0, 1e-4)

        local padPos = client:get_current_pad_pos()
        -- With heading yaw 0 (North: -Z) and bodyOffset fwd = 5.0, pad should be at (840, 65, 1115)
        assert_near(padPos.x, 840.0, 1e-4)
        assert_near(padPos.y, 65.0, 1e-4)
        assert_near(padPos.z, 1115.0, 1e-4)
    end)

    it("integrates dead reckoning at 20Hz (dt = 0.05) using velocity", function()
        local client = gps_client.create(dummyCfg, offset_transform)
        client:set_comp_pos(100.0, 60.0, 200.0)

        local kin = {
            velocity = { vx = 10.0, vy = 2.0, vz = -5.0 },
            acceleration = { ax = 0.0, ay = 0.0, az = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, yaw = 90.0 } -- Heading East (+X)
        }
        client:update_dead_reckoning(0.05, kin)

        local compPos = client:get_current_comp_pos()
        assert_near(compPos.x, 100.5, 1e-4) -- 100 + 10 * 0.05
        assert_near(compPos.y, 60.1, 1e-4)  -- 60 + 2 * 0.05
        assert_near(compPos.z, 199.75, 1e-4) -- 200 - 5 * 0.05

        local padPos = client:get_current_pad_pos()
        -- yaw = 90 (East): fwd 5.0 moves in +X direction. x_pad = 100.5 + 5.0 = 105.5
        assert_near(padPos.x, 105.5, 1e-4)
        assert_near(padPos.y, 61.1, 1e-4)
        assert_near(padPos.z, 199.75, 1e-4)
    end)

    it("flags degraded health when GPS ping silent > 2.0s", function()
        local client = gps_client.create(dummyCfg, offset_transform)
        client:set_last_gps_time(10.0)

        assert_true(client:check_gps_health(11.5))
        assert_false(client:check_gps_health(12.5)) -- 2.5s > 2.0s
        assert_true(client:is_degraded())
    end)
end)
