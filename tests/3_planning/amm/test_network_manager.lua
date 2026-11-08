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
end)
