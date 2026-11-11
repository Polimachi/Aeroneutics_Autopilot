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

    it("builds and sends MSG_OPERATOR_CMD onto Base+0", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local transmitted = {}
        local mock_modem = {
            transmit = function(chan, reply_chan, payload)
                table.insert(transmitted, { chan = chan, reply_chan = reply_chan, payload = payload })
            end
        }
        net.modem = mock_modem

        local ok = net:send_operator_cmd("CRUISE", "CRUISE", { targetWaypoint = { x = 100, z = 200 }, targetAlt = 150 }, "NONE", "PILOT_PRIMARY")
        assert_true(ok)
        assert_eq(#transmitted, 1)
        assert_eq(transmitted[1].chan, 10000) -- Base+0
        assert_eq(transmitted[1].payload.type, "MSG_OPERATOR_CMD")
        assert_eq(transmitted[1].payload.payload.command, "CRUISE")
        assert_eq(transmitted[1].payload.payload.params.targetAlt, 150)
        assert_eq(transmitted[1].payload.payload.authority, "PILOT_PRIMARY")
    end)

    it("builds and sends MSG_EMERGENCY_OVERRIDE onto Base+1", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local transmitted = {}
        local mock_modem = {
            transmit = function(chan, reply_chan, payload)
                table.insert(transmitted, { chan = chan, reply_chan = reply_chan, payload = payload })
            end
        }
        net.modem = mock_modem

        local ok = net:send_emergency_override("CUTOFF", "PILOT_ESTOP_HOTKEY")
        assert_true(ok)
        assert_eq(#transmitted, 1)
        assert_eq(transmitted[1].chan, 10001) -- Base+1
        assert_eq(transmitted[1].payload.type, "MSG_EMERGENCY_OVERRIDE")
        assert_eq(transmitted[1].payload.payload.action, "CUTOFF")
        assert_eq(transmitted[1].payload.payload.reason, "PILOT_ESTOP_HOTKEY")
        assert_eq(transmitted[1].payload.payload.source, "MFD")
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
