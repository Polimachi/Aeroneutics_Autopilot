-- tests/0_infra/gcs/test_main_loop.lua
local main = require("main")

describe("GCS main application loop and event dispatcher", function()
    local function create_mock_modem()
        return {
            opened = {},
            transmissions = {},
            open = function(self, ch) self.opened[ch] = true end,
            close = function(self, ch) self.opened[ch] = nil end,
            isOpen = function(self, ch) return self.opened[ch] == true end,
            transmit = function(self, ch, rch, p)
                table.insert(self.transmissions, { channel = ch, replyChannel = rch, payload = p })
            end
        }
    end

    local test_cfg = {
        system = { id = "GCS_01", domainId = "GCS_01", modemSide = "top" },
        channels = { bootstrapChannel = 50000, bandwidth = 40, baseChannelMin = 10000, baseChannelMax = 49960, maxCraftBlocks = 1000 },
        ui = { screenWidth = 51, screenHeight = 19, telemetryTimeoutSec = 5.0 }
    }

    it("creates app context and opens bootstrap channel 50000", function()
        local modem = create_mock_modem()
        local app = main.create_app(test_cfg, modem, "config/test_main_registry.json")

        assert_not_nil(app)
        assert_true(modem:isOpen(50000), "CH 50000 must be open on startup")
        assert_eq(app.status_msg, "GCS READY")

        if fs.exists("config/test_main_registry.json") then fs.delete("config/test_main_registry.json") end
    end)

    it("handles MSG_BLOCK_REQUEST, allocates block, saves registry, and replies", function()
        local modem = create_mock_modem()
        local app = main.create_app(test_cfg, modem, "config/test_main_registry.json")

        local req = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 1,
            type = "MSG_BLOCK_REQUEST",
            time = 1000,
            payload = { domainId = "AIRCRAFT_01", hardwareUuid = "UUID-01", requestedBandwidth = 40 }
        }

        local handled = app:process_modem_message(50000, 50000, req)
        assert_true(handled)
        assert_eq(#modem.transmissions, 1)

        local reply = modem.transmissions[1]
        assert_eq(reply.channel, 50000)
        assert_eq(reply.payload.type, "MSG_BLOCK_ASSIGN")
        assert_eq(reply.payload.payload.blockId, 1)
        assert_eq(reply.payload.payload.baseChannel, 10000)

        -- Active craft should be AIRCRAFT_01 and telemetry channel 10003 opened
        assert_true(modem:isOpen(10003))

        if fs.exists("config/test_main_registry.json") then fs.delete("config/test_main_registry.json") end
    end)

    it("handles key commands for C2 override and E_STOP", function()
        local modem = create_mock_modem()
        local app = main.create_app(test_cfg, modem, "config/test_main_registry.json")

        -- Register craft
        app.channel_mgr.allocations["AIRCRAFT_01"] = { blockId = 1, baseChannel = 10000, domainId = "AIRCRAFT_01" }
        app.fleet_tracker.register_craft(app.fleet, "AIRCRAFT_01", 10000, 1)
        app.network_manager.set_active_craft(app.net_mgr, 10000)

        -- Press 'T' for Takeoff
        app:process_key(nil, "t")
        assert_eq(#modem.transmissions, 1)
        assert_eq(modem.transmissions[1].channel, 10000) -- Base+0
        assert_eq(modem.transmissions[1].payload.payload.command, "TAKEOFF")
        assert_eq(modem.transmissions[1].payload.payload.authority, "GCS_OVERRIDE")

        -- Press 'X' for Emergency E_STOP
        app:process_key(nil, "x")
        assert_eq(#modem.transmissions, 2)
        assert_eq(modem.transmissions[2].channel, 10001) -- Base+1 direct to VAS
        assert_eq(modem.transmissions[2].payload.payload.action, "E_STOP")
        assert_eq(modem.transmissions[2].payload.payload.source, "GCS")

        -- Press 'Q' to quit
        assert_true(app.running)
        app:process_key(nil, "q")
        assert_false(app.running)

        if fs.exists("config/test_main_registry.json") then fs.delete("config/test_main_registry.json") end
    end)
end)
