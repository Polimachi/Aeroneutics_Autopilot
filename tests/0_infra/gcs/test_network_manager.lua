-- tests/0_infra/gcs/test_network_manager.lua
local network_manager = require("network_manager")

describe("GCS network manager", function()
    local cfg = {
        system = {
            id = "GCS_01",
            domainId = "GCS_01"
        },
        channels = {
            bootstrapChannel = 50000,
            bandwidth = 40
        }
    }

    local function create_mock_modem()
        return {
            opened = {},
            transmissions = {},
            open = function(self, ch)
                self.opened[ch] = true
            end,
            close = function(self, ch)
                self.opened[ch] = nil
            end,
            isOpen = function(self, ch)
                return self.opened[ch] == true
            end,
            transmit = function(self, channel, replyChannel, payload)
                table.insert(self.transmissions, {
                    channel = channel,
                    replyChannel = replyChannel,
                    payload = payload
                })
            end
        }
    end

    it("initializes context and manages bootstrap channel", function()
        local modem = create_mock_modem()
        local ctx = network_manager.init(cfg, modem)

        assert_not_nil(ctx)
        assert_eq(ctx.domainId, "GCS_01")
        assert_eq(ctx.bootstrap_channel, 50000)

        network_manager.open_bootstrap_channel(ctx)
        assert_true(modem:isOpen(50000))

        network_manager.close_bootstrap_channel(ctx)
        assert_false(modem:isOpen(50000))
    end)

    it("dynamically manages telemetry channel on active craft switch", function()
        local modem = create_mock_modem()
        local ctx = network_manager.init(cfg, modem)

        -- Switch to craft with Base=10000: opens Base+3 (10003)
        network_manager.set_active_craft(ctx, 10000)
        assert_true(modem:isOpen(10003))
        assert_eq(ctx.active_base, 10000)

        -- Switch to craft with Base=10040: closes 10003, opens 10043
        network_manager.set_active_craft(ctx, 10040)
        assert_false(modem:isOpen(10003))
        assert_true(modem:isOpen(10043))
        assert_eq(ctx.active_base, 10040)

        -- Switch to nil: closes 10043
        network_manager.set_active_craft(ctx, nil)
        assert_false(modem:isOpen(10043))
        assert_nil(ctx.active_base)
    end)

    it("sends MSG_BLOCK_ASSIGN on requested reply channel", function()
        local modem = create_mock_modem()
        local ctx = network_manager.init(cfg, modem)

        local assign_payload = {
            blockId = 1,
            baseChannel = 10000,
            bandwidth = 40,
            status = "ASSIGNED",
            channelRange = { start = 10000, ["end"] = 10039 }
        }

        local ok = network_manager.send_block_assign(ctx, 50000, assign_payload)
        assert_true(ok)
        assert_eq(#modem.transmissions, 1)

        local tx = modem.transmissions[1]
        assert_eq(tx.channel, 50000)
        assert_eq(tx.replyChannel, 50000)
        assert_eq(tx.payload.ver, "1.9.5")
        assert_eq(tx.payload.type, "MSG_BLOCK_ASSIGN")
        assert_eq(tx.payload.domainId, "GCS_01")
        assert_eq(tx.payload.seq, 1)
        assert_not_nil(tx.payload.time)
        assert_eq(tx.payload.payload.blockId, 1)
        assert_eq(tx.payload.payload.baseChannel, 10000)
    end)

    it("sends MSG_OPERATOR_CMD on Base+0 and MSG_EMERGENCY_OVERRIDE on Base+1", function()
        local modem = create_mock_modem()
        local ctx = network_manager.init(cfg, modem)

        local c2_cmd = {
            targetCraft = "AIRCRAFT_01",
            authority = "GCS_OVERRIDE",
            command = "TAKEOFF",
            params = { altitude = 80.0 }
        }
        local ok_c2 = network_manager.send_c2_command(ctx, 10000, c2_cmd)
        assert_true(ok_c2)
        assert_eq(#modem.transmissions, 1)
        local tx_c2 = modem.transmissions[1]
        assert_eq(tx_c2.channel, 10000) -- Base + 0
        assert_eq(tx_c2.payload.type, "MSG_OPERATOR_CMD")
        assert_eq(tx_c2.payload.payload.command, "TAKEOFF")
        assert_eq(tx_c2.payload.payload.authority, "GCS_OVERRIDE")

        local estop_payload = {
            source = "GCS",
            action = "E_STOP",
            reason = "OPERATOR_HARD_STOP"
        }
        local ok_estop = network_manager.send_emergency_override(ctx, 10000, estop_payload)
        assert_true(ok_estop)
        assert_eq(#modem.transmissions, 2)
        local tx_estop = modem.transmissions[2]
        assert_eq(tx_estop.channel, 10001) -- Base + 1
        assert_eq(tx_estop.payload.type, "MSG_EMERGENCY_OVERRIDE")
        assert_eq(tx_estop.payload.payload.action, "E_STOP")
    end)

    it("parses and validates UAFS Envelope v1.9.5", function()
        local valid_envelope = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 42,
            type = "MSG_BLOCK_REQUEST",
            time = 1729845000000,
            payload = { domainId = "AIRCRAFT_01", hardwareUuid = "UUID-1", requestedBandwidth = 40 }
        }

        local parsed, err = network_manager.parse_envelope(valid_envelope)
        assert_not_nil(parsed)
        assert_nil(err)
        assert_eq(parsed.type, "MSG_BLOCK_REQUEST")

        -- Invalid version
        local bad_ver = { ver = "1.0.0", type = "X", payload = {}, domainId = "A", time = 1, seq = 1 }
        local p2, err2 = network_manager.parse_envelope(bad_ver)
        assert_nil(p2)
        assert_not_nil(err2)

        -- Missing payload
        local bad_payload = { ver = "1.9.5", type = "X", domainId = "A", time = 1, seq = 1 }
        local p3, err3 = network_manager.parse_envelope(bad_payload)
        assert_nil(p3)
        assert_not_nil(err3)

        -- Non-table input
        local p4, err4 = network_manager.parse_envelope("not a table")
        assert_nil(p4)
        assert_not_nil(err4)
    end)
end)
