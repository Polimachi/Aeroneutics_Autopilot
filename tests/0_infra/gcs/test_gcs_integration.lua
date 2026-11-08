-- tests/0_infra/gcs/test_gcs_integration.lua
-- End-to-End integration test for GCS Channel Manager & Flight Command Console
local main = require("main")

describe("GCS E2E closed-loop simulation integration", function()
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

    it("executes full lifecycle: bootstrap assign -> telem downlink -> C2 override -> E-Stop cutoff", function()
        local modem = create_mock_modem()
        local app = main.create_app(test_cfg, modem, "config/test_e2e_registry.json")

        -- 1. FCP sends MSG_BLOCK_REQUEST on CH 50000
        local boot_req = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 1,
            type = "MSG_BLOCK_REQUEST",
            time = 1000,
            payload = {
                domainId = "AIRCRAFT_01",
                hardwareUuid = "HW-UUID-4401",
                requestedBandwidth = 40
            }
        }
        local ok1 = app:process_modem_message(50000, 50000, boot_req)
        assert_true(ok1)
        assert_eq(#modem.transmissions, 1)

        -- Verify assignment packet
        local assign_tx = modem.transmissions[1]
        assert_eq(assign_tx.channel, 50000)
        assert_eq(assign_tx.payload.type, "MSG_BLOCK_ASSIGN")
        assert_eq(assign_tx.payload.payload.blockId, 1)
        assert_eq(assign_tx.payload.payload.baseChannel, 10000)

        -- 2. Verify GCS opened telemetry downlink for AIRCRAFT_01 (Base + 3 = 10003)
        assert_true(modem:isOpen(10003))

        -- 3. FCP sends MSG_MFD_STATE telemetry on Base + 3
        local telem_pkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 101,
            type = "MSG_MFD_STATE",
            time = 1200,
            payload = {
                attitude = { pitch = 3.2, roll = 0.0, heading = 90.0 },
                dynamics = { altitudeY = 150.0, verticalSpeed = 0.0, groundSpeed = 18.5 },
                fuel = 0.75,
                fsmState = "CRUISE",
                actuatorHealth = { tap = true, wap = true, allOk = true }
            }
        }
        local ok2 = app:process_modem_message(10003, 10003, telem_pkt)
        assert_true(ok2)

        -- Verify telemetry cached in active craft
        local active = app.fleet_tracker.get_active_craft(app.fleet)
        assert_not_nil(active)
        assert_eq(active.domainId, "AIRCRAFT_01")
        assert_eq(active.telemetry.fsmState, "CRUISE")
        assert_eq(active.telemetry.dynamics.altitudeY, 150.0)

        -- 4. GCS operator issues C2 command: TAKEOFF ('T')
        app:process_key(nil, "t")
        assert_eq(#modem.transmissions, 2)
        local c2_tx = modem.transmissions[2]
        assert_eq(c2_tx.channel, 10000) -- Base + 0
        assert_eq(c2_tx.payload.type, "MSG_OPERATOR_CMD")
        assert_eq(c2_tx.payload.payload.command, "TAKEOFF")
        assert_eq(c2_tx.payload.payload.authority, "GCS_OVERRIDE")

        -- 5. GCS operator issues emergency cutoff: E_STOP ('X')
        app:process_key(nil, "x")
        assert_eq(#modem.transmissions, 3)
        local estop_tx = modem.transmissions[3]
        assert_eq(estop_tx.channel, 10001) -- Base + 1 (direct to VAS)
        assert_eq(estop_tx.payload.type, "MSG_EMERGENCY_OVERRIDE")
        assert_eq(estop_tx.payload.payload.action, "E_STOP")
        assert_eq(estop_tx.payload.payload.source, "GCS")

        -- 6. Second craft DRONE_02 boots up on CH 50000
        local drone_req = {
            ver = "1.9.5",
            domainId = "DRONE_02",
            seq = 1,
            type = "MSG_BLOCK_REQUEST",
            time = 1500,
            payload = { domainId = "DRONE_02", hardwareUuid = "HW-UUID-DRONE", requestedBandwidth = 40 }
        }
        app:process_modem_message(50000, 50000, drone_req)
        assert_eq(#modem.transmissions, 4)
        local drone_assign = modem.transmissions[4]
        assert_eq(drone_assign.payload.payload.blockId, 2)
        assert_eq(drone_assign.payload.payload.baseChannel, 10040)

        -- 7. Operator presses [TAB] to switch target craft
        app:process_key(keys and keys.tab or 15, "\t")
        local new_active = app.fleet_tracker.get_active_craft(app.fleet)
        assert_eq(new_active.domainId, "DRONE_02")
        assert_true(modem:isOpen(10043), "Must open Base+3 for DRONE_02 (10043)")
        assert_false(modem:isOpen(10003), "Must close Base+3 for AIRCRAFT_01 (10003)")

        if fs.exists("config/test_e2e_registry.json") then fs.delete("config/test_e2e_registry.json") end
    end)
end)
