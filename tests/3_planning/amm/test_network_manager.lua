-- tests/3_planning/amm/test_network_manager.lua
local network_manager = require("network_manager")

describe("AMM Network Manager and Packet Protocol", function()
    it("encodes valid ICD v1.9.5 envelopes", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local pkt = net:encode_envelope("MSG_OPERATOR_CMD", { command = "ARM" })
        assert_not_nil(pkt)
        assert_eq(pkt.ver, "1.9.5")
        assert_eq(pkt.domainId, "AIRCRAFT_01")
        assert_eq(pkt.type, "MSG_OPERATOR_CMD")
        assert_eq(pkt.payload.command, "ARM")
        assert_true(pkt.seq >= 1)
        assert_true(pkt.time > 0)
    end)

    it("decodes valid packets and rejects corrupted packets", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local valid = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 10,
            type = "MSG_MFD_STATE",
            time = 1729845000000,
            payload = { fsmState = "CRUISE" }
        }
        local ok, decoded = net:decode_envelope(valid)
        assert_true(ok)
        assert_eq(decoded.type, "MSG_MFD_STATE")

        local invalid_ver = { ver = "0.9.0", type = "TEST", payload = {} }
        local ok2, err2 = net:decode_envelope(invalid_ver)
        assert_false(ok2)
        assert_eq(err2, "VERSION_MISMATCH")

        local not_table = "corrupted string"
        local ok3, err3 = net:decode_envelope(not_table)
        assert_false(ok3)
        assert_eq(err3, "NON_TABLE_PACKET")
    end)

    it("enforces Zero-Fallback by removing outbound Base+0 send_operator_cmd", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        assert_nil(net.send_operator_cmd)
    end)

    it("builds and sends MSG_EMERGENCY_OVERRIDE onto Base+1 with E_STOP and ESTOP_CONFIRM_KEY", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local transmitted = {}
        local mock_modem = {
            transmit = function(chan, reply_chan, payload)
                table.insert(transmitted, { chan = chan, reply_chan = reply_chan, payload = payload })
            end
        }
        net.modem = mock_modem

        local ok = net:send_emergency_override()
        assert_true(ok)
        assert_eq(#transmitted, 1)
        assert_eq(transmitted[1].chan, 10001) -- Base+1
        assert_eq(transmitted[1].payload.type, "MSG_EMERGENCY_OVERRIDE")
        assert_eq(transmitted[1].payload.payload.action, "E_STOP")
        assert_eq(transmitted[1].payload.payload.reason, "PILOT_ESTOP_HOTKEY")
        assert_eq(transmitted[1].payload.payload.authKey, "ESTOP_CONFIRM_KEY")
        assert_eq(transmitted[1].payload.payload.source, "AMM")
    end)

    it("binds dual modems opening onboard Base+0,1,2,3,4 and infra Base+5,50000,50001,50003,50004,60002", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })

        net:bind_modems(top_m, back_m, 10000)
        assert_false(net.modemFallbackActive)
        assert_true(top_m.isOpen(10000))
        assert_true(top_m.isOpen(10001))
        assert_true(top_m.isOpen(10002))
        assert_true(top_m.isOpen(10003))
        assert_true(top_m.isOpen(10004))
        assert_false(top_m.isOpen(10005))
        assert_false(top_m.isOpen(50000))

        assert_true(back_m.isOpen(10005))
        assert_true(back_m.isOpen(50000))
        assert_true(back_m.isOpen(50001))
        assert_true(back_m.isOpen(50003))
        assert_true(back_m.isOpen(50004))
        assert_true(back_m.isOpen(60002))
        assert_false(back_m.isOpen(10000))
    end)

    it("falls back to single modem binding when only one modem is provided", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local single_m = mock.modem({ wireless = true })

        net:bind_modems(single_m, nil, 10000)
        assert_true(net.modemFallbackActive)
        assert_true(single_m.isOpen(10000))
        assert_true(single_m.isOpen(10001))
        assert_true(single_m.isOpen(10004))
        assert_true(single_m.isOpen(10005))
        assert_true(single_m.isOpen(50000))
        assert_true(single_m.isOpen(60002))
    end)

    it("transmits MSG_TRAJECTORY_SETPOINT on Base+4 via onboard modem", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })
        net:bind_modems(top_m, back_m, 10000)

        local ok = net:send_trajectory_setpoint({ flightMode = "CRUISE", targetHeading = 180.0 })
        assert_true(ok)
        assert_eq(#top_m._transmitted, 1)
        assert_eq(top_m._transmitted[1].tx, 10004)
        assert_eq(top_m._transmitted[1].pkt.type, "MSG_TRAJECTORY_SETPOINT")
        assert_eq(top_m._transmitted[1].pkt.payload.flightMode, "CRUISE")
        assert_eq(#back_m._transmitted, 0)
    end)

    it("transmits MSG_CHANNEL_REBIND on Base+4 and applies channel rebind cleanly", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local top_m = mock.modem({ wireless = true })
        local back_m = mock.modem({ wireless = true })
        net:bind_modems(top_m, back_m, 10000)
        net:open_payload_channel(20)
        assert_true(top_m.isOpen(10020))

        local ok = net:send_rebind_command("PREPARE", "TX-01", 10000, 10040)
        assert_true(ok)
        assert_eq(#top_m._transmitted, 1)
        assert_eq(top_m._transmitted[1].tx, 10004)
        assert_eq(top_m._transmitted[1].pkt.payload.action, "PREPARE")

        local reb_ok = net:apply_rebind(10040)
        assert_true(reb_ok)
        assert_eq(net.baseChannel, 10040)
        assert_false(top_m.isOpen(10000))
        assert_false(top_m.isOpen(10004))
        assert_false(back_m.isOpen(10005))
        assert_true(top_m.isOpen(10040))
        assert_true(top_m.isOpen(10044))
        assert_true(back_m.isOpen(10045))
        assert_false(top_m.isOpen(10020)) -- Old Zone 3 channel closed
        assert_true(top_m.isOpen(10060)) -- Zone 3 offset 20 migrated to new base 10040+20
    end)

    it("suppresses MSG_MFD_STATE transmission when activeSource is MFD_ACRO", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local top_m = mock.modem({ wireless = true })
        net:bind_modems(top_m, top_m, 10000)

        local ok_normal = net:send_mfd_state({ fsmState = "CRUISE" }, "FCP")
        assert_true(ok_normal)
        assert_eq(#top_m._transmitted, 1)
        assert_eq(top_m._transmitted[1].tx, 10003)

        local ok_yield, reason = net:send_mfd_state({ fsmState = "CRUISE" }, "MFD_ACRO")
        assert_false(ok_yield)
        assert_eq(reason, "YIELDED_TO_MFD_ACRO")
        assert_eq(#top_m._transmitted, 1) -- No new transmission!
    end)

    it("enforces Zone 3 (Base+20..29) bounds and manages dynamic channel open/close without closing Base+0/+3", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        assert_true(m.isOpen(10000))
        assert_true(m.isOpen(10003))
        assert_false(m.isOpen(10020))

        local invalid_inputs = { -1, 0, 3, 19, 30, 20.5, 0 / 0, math.huge, 9999, 10000, 10010, 10030, "20" }
        for _, bad in ipairs(invalid_inputs) do
            local ch, err = net:resolve_payload_channel(bad)
            assert_nil(ch, "Should reject invalid Zone 3 selector: " .. tostring(bad))
            assert_eq(err, "INVALID_ZONE3_CHANNEL")
            local ok_open, err_open = net:open_payload_channel(bad)
            assert_false(ok_open)
            assert_eq(err_open, "INVALID_ZONE3_CHANNEL")
        end

        local ok_o, ch20 = net:open_payload_channel(20)
        assert_true(ok_o)
        assert_eq(ch20, 10020)
        assert_true(m.isOpen(10020))

        local ok_tx, tx_ch = net:send_payload_req(20, "CP_04", "RELEASE_BAY", { bayId = 1 }, { keepOpen = true })
        assert_true(ok_tx)
        assert_eq(tx_ch, 10020)
        assert_eq(#m._transmitted, 1)
        assert_eq(m._transmitted[1].tx, 10020)
        assert_eq(m._transmitted[1].pkt.type, "MSG_PAYLOAD_REQ")
        assert_eq(m._transmitted[1].pkt.payload.replyChannel, 10020)
        assert_eq(m._transmitted[1].pkt.payload.checkpointId, "CP_04")
        assert_true(m.isOpen(10020))

        -- Calling send_payload_req without opts preserves already-open channel state
        assert_true(net:send_payload_req(20, "CP_04", "STATUS_PING", {}))
        assert_true(m.isOpen(10020))

        -- Fire-and-forget send on unopened Zone 3 channel opens for reply metadata and closes immediately
        local ok_ff, ch21 = net:send_payload_req(21, "CP_05", "PING", {}, { keepOpen = false })
        assert_true(ok_ff)
        assert_eq(ch21, 10021)
        assert_false(m.isOpen(10021))

        net:open_payload_channel(10025)
        assert_true(m.isOpen(10025))
        local closed = net:close_all_payload_channels()
        assert_eq(closed, 2)
        assert_false(m.isOpen(10020))
        assert_false(m.isOpen(10025))
        assert_true(m.isOpen(10000))
        assert_true(m.isOpen(10003))
    end)

    it("encodes and transmits MSG_MISSION_ACK on Base+0", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10040 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local ok = net:send_mission_ack({
            action = "RUN",
            status = "ACCEPTED",
            missionId = "PATROL_ALPHA",
            missionState = "EN_ROUTE",
            activeIndex = 1,
            totalCheckpoints = 4,
        })
        assert_true(ok)
        assert_eq(m._transmitted[1].tx, 10040)
        assert_eq(m._transmitted[1].pkt.type, "MSG_MISSION_ACK")
        assert_eq(m._transmitted[1].pkt.payload.status, "ACCEPTED")
        assert_eq(m._transmitted[1].pkt.payload.missionId, "PATROL_ALPHA")
    end)
end)
