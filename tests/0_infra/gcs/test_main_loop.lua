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
        assert_true(fs.exists("config/test_main_registry.json"), "registry must be persisted after allocation")

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

        -- Press 'C' for ChannelReg status/save
        app:process_key(nil, "c")
        assert_true(string.find(app.status_msg, "REG:", 1, true) ~= nil)

        -- Press 'Q' to quit
        assert_true(app.running)
        app:process_key(nil, "q")
        assert_false(app.running)

        if fs.exists("config/test_main_registry.json") then fs.delete("config/test_main_registry.json") end
    end)

    it("receives multi-craft telemetry, forwards CH 50003 beacon, and relays websocket MISSION_PUSH_CMD / MSG_MISSION_ACK", function()
        local modem = create_mock_modem()
        local sent_ws = {}
        local mock_ws = {
            send = function(_, raw) table.insert(sent_ws, textutils.unserializeJSON(raw)) end,
            close = function() end,
        }
        local cfg_ws = {
            system = { id = "GCS_01", domainId = "GCS_01", modemSide = "top" },
            channels = {
                bootstrapChannel = 50000, facilityBeaconChannel = 50003, missionAckChannel = 50004,
                bandwidth = 40, baseChannelMin = 10000, baseChannelMax = 49960, maxCraftBlocks = 1000,
            },
            liveBridge = { enabled = true, url = "ws://127.0.0.1:8765", telemetrySyncHz = 5 },
            ui = { screenWidth = 51, screenHeight = 19, telemetryTimeoutSec = 5.0 },
        }
        local app = main.create_app(cfg_ws, modem, "config/test_ws_registry.json", {
            websocket = function() return mock_ws end,
        })

        assert_true(modem:isOpen(50003))
        assert_true(modem:isOpen(50004))

        -- Bootstrap two aircraft and verify both Base+3 and Base+0 stay open
        for idx, dom in ipairs({ "AIRCRAFT_01", "AIRCRAFT_02" }) do
            app:process_modem_message(50000, 50000, {
                ver = "1.9.5", domainId = dom, seq = idx, type = "MSG_BLOCK_REQUEST", time = 1000 + idx,
                payload = { domainId = dom, hardwareUuid = "UUID-" .. idx, requestedBandwidth = 40 },
            })
        end
        assert_true(modem:isOpen(10003))
        assert_true(modem:isOpen(10043))
        assert_true(modem:isOpen(10040))

        -- Non-active craft (#2 at 10043) sends MSG_MFD_STATE -> must update fleet_tracker
        assert_true(app:process_modem_message(10043, 10043, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 5, type = "MSG_MFD_STATE", time = 1500,
            payload = {
                fsmState = "CRUISE", flightMode = "CRUISE",
                attitude = { pitch = 0, roll = 0, yaw = 45 },
                dynamics = { altitudeY = 130, verticalSpeed = 0, groundSpeed = 12 },
                navigation = { currentPos = { x = 400, y = 130, z = -300 } },
                fuel = 0.9, actuatorHealth = { allOk = true },
            },
        }))
        local c2 = app.fleet_tracker.get_craft(app.fleet, "AIRCRAFT_02")
        assert_eq(c2.telemetry.fsmState, "CRUISE")
        assert_false(c2.isStale)

        -- CH 50003 MSG_FACILITY_BEACON forwards WORLD_PRESET_SYNC over WebSocket
        assert_true(app:process_modem_message(50003, 50003, {
            ver = "1.9.5", domainId = "GAC_01", seq = 1, type = "MSG_FACILITY_BEACON", time = 1600,
            payload = {
                sectorId = 1, sectorName = "Main Airfield",
                facilitiesSummary = { total = 1, free = 1 },
                facilities = { { facilityId = "RWY_01", facilityType = "RUNWAY", status = "FREE", position = { x = 0, y = 64, z = 0 } } },
            },
        }))
        assert_eq(sent_ws[#sent_ws].type, "WORLD_PRESET_SYNC")
        assert_eq(sent_ws[#sent_ws].sectorName, "Main Airfield")

        -- WebSocket MISSION_PUSH_CMD dispatches Base+0 MSG_MISSION_CMD to AIRCRAFT_02 (10040)
        assert_true(app:process_websocket_message("ws://127.0.0.1:8765", textutils.serializeJSON({
            type = "MISSION_PUSH_CMD",
            requestId = "req-42",
            targetCraft = "AIRCRAFT_02",
            action = "LOAD",
            saveToDisk = true,
            missionData = { version = "2.0.0", missionId = "SORTIE_B", checkpoints = { { checkpointId = "CP1", action = "ACT_NAV_SPLINE_WP", params = { targetPos = { x = 10, z = 20 } } } } },
        })))
        local last_tx = modem.transmissions[#modem.transmissions]
        assert_eq(last_tx.channel, 10040)
        assert_eq(last_tx.payload.type, "MSG_MISSION_CMD")
        assert_eq(last_tx.payload.payload.action, "LOAD")

        -- MSG_MISSION_ACK on CH 50004 (or Base+0) relays MISSION_PUSH_ACK with requestId req-42
        assert_true(app:process_modem_message(50004, 10040, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = 9, type = "MSG_MISSION_ACK", time = 1700,
            payload = { action = "LOAD", status = "ACCEPTED", missionId = "SORTIE_B", missionState = "IDLE" },
        }))
        assert_eq(sent_ws[#sent_ws].type, "MISSION_PUSH_ACK")
        assert_eq(sent_ws[#sent_ws].requestId, "req-42")
        assert_eq(sent_ws[#sent_ws].targetCraft, "AIRCRAFT_02")
        assert_eq(sent_ws[#sent_ws].status, "ACCEPTED")

        if fs.exists("config/test_ws_registry.json") then fs.delete("config/test_ws_registry.json") end
    end)
end)
