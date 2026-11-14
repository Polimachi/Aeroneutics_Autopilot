-- tests/2_guidance/fcp/test_fcp_network_and_rebind.lua
local network_manager = require("network_manager")

describe("test_fcp_network_and_rebind|test_state_propagator: FCP 3-Channel Network Manager and Modem Binding", function()
    it("binds single top modem and opens ONLY Base+4, Base+2, Base+1", function()
        local mock_modem = mock.modem({ wireless = true })
        local cfg = {
            system = { domainId = "AIRCRAFT_01", hardwareUuid = "FCP-04", primaryModemSide = "top" },
            channels = { baseChannel = 10000 },
        }
        local net = network_manager.init(cfg, function(side)
            if side == "top" then return mock_modem end
            return nil
        end)

        assert_not_nil(net, "network_manager.init must return net context")
        assert_eq(net.baseChannel, 10000)

        -- ONLY 3 channels opened: 10004 (trajectory), 10002 (telemetry), 10001 (guidance)
        assert_true(mock_modem.isOpen(10004), "10004 (Base+4 trajectory) must be open")
        assert_true(mock_modem.isOpen(10002), "10002 (Base+2 telemetry) must be open")
        assert_true(mock_modem.isOpen(10001), "10001 (Base+1 guidance) must be open")

        -- All other channels MUST NOT be open
        assert_false(mock_modem.isOpen(50000), "50000 (bootstrap) must NOT be opened by FCP")
        assert_false(mock_modem.isOpen(60001), "60001 (GPS req) must NOT be opened by FCP")
        assert_false(mock_modem.isOpen(60002), "60002 (GPS resp) must NOT be opened by FCP")
        assert_false(mock_modem.isOpen(10000), "10000 (Base+0 C2) must NOT be opened by FCP")
        assert_false(mock_modem.isOpen(10003), "10003 (Base+3 MFD) must NOT be opened by FCP")
        assert_false(mock_modem.isOpen(10005), "10005 (Base+5 reply) must NOT be opened by FCP")
    end)

    it("encodes valid ICD v1.9.5 envelopes and validates domainId", function()
        local mock_modem = mock.modem({ wireless = true })
        local net = network_manager.init({
            system = { domainId = "AIRCRAFT_01", hardwareUuid = "FCP-04" },
            channels = { baseChannel = 10000 },
        }, function() return mock_modem end)

        local env = network_manager.encode_envelope(net, "MSG_ATTITUDE_CMD", { test = 123 })
        assert_eq(env.ver, "1.9.5")
        assert_eq(env.domainId, "AIRCRAFT_01")
        assert_eq(env.senderId, "FCP-04")
        assert_eq(env.type, "MSG_ATTITUDE_CMD")
        assert_eq(env.payload.test, 123)

        assert_true(network_manager.verify_packet(net, env))

        -- Reject mismatched domain
        local bad_domain = { ver = "1.9.5", domainId = "OTHER_CRAFT", type = "TEST", payload = {} }
        assert_false(network_manager.verify_packet(net, bad_domain))

        -- Reject invalid version
        local bad_ver = { ver = "1.9.4", domainId = "AIRCRAFT_01", type = "TEST", payload = {} }
        assert_false(network_manager.verify_packet(net, bad_ver))

        -- Reject non-table
        assert_false(network_manager.verify_packet(net, "not a table"))
    end)

    it("sends MSG_ATTITUDE_CMD onto Base+1", function()
        local mock_modem = mock.modem({ wireless = true })
        local net = network_manager.init({
            system = { domainId = "AIRCRAFT_01" },
            channels = { baseChannel = 10000 },
        }, function() return mock_modem end)

        local cmd = {
            source = "FCP",
            arm = true,
            flightActive = true,
            flightMode = "CRUISE",
            commandType = "QUATERNION_RATE",
            targetQuaternion = { w = 1.0, x = 0.0, y = 0.0, z = 0.0 },
            targetAngularRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
            collectiveThrust = 0.75,
            acroActive = false,
        }
        local ok = network_manager.send_attitude_cmd(net, cmd)
        assert_true(ok)
        assert_eq(#mock_modem._transmitted, 1)
        assert_eq(mock_modem._transmitted[1].tx, 10001)
        assert_eq(mock_modem._transmitted[1].rx, 10001)
        assert_eq(mock_modem._transmitted[1].pkt.type, "MSG_ATTITUDE_CMD")
        assert_eq(mock_modem._transmitted[1].pkt.payload.commandType, "QUATERNION_RATE")
        assert_eq(mock_modem._transmitted[1].pkt.payload.collectiveThrust, 0.75)
    end)

    it("sends MSG_OUTER_LOOP_STATUS onto Base+4 with ICD I-12 fields", function()
        local mock_modem = mock.modem({ wireless = true })
        local net = network_manager.init({
            system = { domainId = "AIRCRAFT_01" },
            channels = { baseChannel = 10000 },
        }, function() return mock_modem end)

        local status_payload = {
            fsmState = "ACTIVE_TRACKING",
            posError = 1.25,
            velError = 0.35,
            saturated = false,
            navStale = false,
            activeConstraintProfile = "STANDARD",
            commandedCollectiveThrust = 0.65,
        }
        local ok = network_manager.send_outer_loop_status(net, status_payload)
        assert_true(ok)
        assert_eq(#mock_modem._transmitted, 1)
        assert_eq(mock_modem._transmitted[1].tx, 10004)
        assert_eq(mock_modem._transmitted[1].rx, 10004)
        assert_eq(mock_modem._transmitted[1].pkt.type, "MSG_OUTER_LOOP_STATUS")
        assert_eq(mock_modem._transmitted[1].pkt.payload.fsmState, "ACTIVE_TRACKING")
        assert_eq(mock_modem._transmitted[1].pkt.payload.commandedCollectiveThrust, 0.65)
    end)

    it("ingests inbound packets on Base+4, Base+2, Base+1 and filters others", function()
        local mock_modem = mock.modem({ wireless = true })
        local net = network_manager.init({
            system = { domainId = "AIRCRAFT_01" },
            channels = { baseChannel = 10000 },
        }, function() return mock_modem end)

        -- Ingest setpoint on Base+4
        local sp_pkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            type = "MSG_TRAJECTORY_SETPOINT",
            payload = { flightMode = "CRUISE", targetHeading = 90.0, currentPos = { x = 10, y = 20, z = 30 } },
        }
        local ok_sp = network_manager.ingest_modem_event(net, "top", 10004, 10004, sp_pkt, 0, 1000)
        assert_true(ok_sp)

        -- Ingest telemetry on Base+2
        local telem_pkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            type = "MSG_FLIGHT_TELEMETRY",
            payload = { attitude = { yaw = 89.0 }, dynamics = { altitudeY = 100.0 } },
        }
        local ok_telem = network_manager.ingest_modem_event(net, "top", 10002, 10002, telem_pkt, 0, 1000)
        assert_true(ok_telem)

        local polled = network_manager.poll_inbound(net)
        assert_not_nil(polled.trajectory)
        assert_eq(polled.trajectory.payload.flightMode, "CRUISE")
        assert_not_nil(polled.telemetry)
        assert_eq(polled.telemetry.payload.dynamics.altitudeY, 100.0)

        -- Polled queues are cleared
        local polled_again = network_manager.poll_inbound(net)
        assert_nil(polled_again.trajectory)
        assert_nil(polled_again.telemetry)
    end)
end)

describe("test_fcp_network_and_rebind|test_state_propagator: FCP 4-Layer MSG_CHANNEL_REBIND Relay and Watchdog", function()
    it("handles PREPARE by opening newBase 3 channels and forwarding to VAS on Base+1", function()
        local mock_modem = mock.modem({ wireless = true })
        local net = network_manager.init({
            system = { domainId = "AIRCRAFT_01" },
            channels = { baseChannel = 10000 },
            configPath = "config/fcp_test_rebind.json",
        }, function() return mock_modem end)

        local rebind_prepare = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            type = "MSG_CHANNEL_REBIND",
            payload = {
                transactionId = "TX-REBIND-10040",
                action = "PREPARE",
                oldBaseChannel = 10000,
                newBaseChannel = 10040,
                bandwidth = 40,
            },
        }

        local ok = network_manager.ingest_modem_event(net, "top", 10004, 10004, rebind_prepare, 0, 1000)
        assert_true(ok)

        -- Opens newBase 3 channels: 10044, 10042, 10041
        assert_true(mock_modem.isOpen(10044), "newBase+4 must be open")
        assert_true(mock_modem.isOpen(10042), "newBase+2 must be open")
        assert_true(mock_modem.isOpen(10041), "newBase+1 must be open")

        -- Forwards PREPARE to VAS on oldBase+1 (10001)
        assert_eq(#mock_modem._transmitted, 1)
        assert_eq(mock_modem._transmitted[1].tx, 10001)
        assert_eq(mock_modem._transmitted[1].pkt.type, "MSG_CHANNEL_REBIND")
        assert_eq(mock_modem._transmitted[1].pkt.payload.action, "PREPARE")
        assert_eq(mock_modem._transmitted[1].pkt.payload.transactionId, "TX-REBIND-10040")

        -- Receiving MSG_CHANNEL_REBIND_ACK from VAS relays READY to AMM on oldBase+4 (10004)
        local vas_ack = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            type = "MSG_CHANNEL_REBIND_ACK",
            payload = {
                transactionId = "TX-REBIND-10040",
                nodeId = "VAS",
                action = "PREPARE",
                status = "READY",
                subNodesReady = { tca = true, asa = true },
            },
        }
        local ok_ack = network_manager.ingest_modem_event(net, "top", 10001, 10001, vas_ack, 0, 1050)
        assert_true(ok_ack)

        assert_eq(#mock_modem._transmitted, 2)
        assert_eq(mock_modem._transmitted[2].tx, 10004)
        assert_eq(mock_modem._transmitted[2].pkt.type, "MSG_CHANNEL_REBIND_ACK")
        assert_eq(mock_modem._transmitted[2].pkt.payload.nodeId, "FCP")
        assert_eq(mock_modem._transmitted[2].pkt.payload.status, "READY")
        assert_eq(mock_modem._transmitted[2].pkt.payload.transactionId, "TX-REBIND-10040")
        assert_nil(mock_modem._transmitted[2].pkt.payload.subNodesOk)

        -- Now AMM sends COMMIT on 10004
        local commit_pkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            type = "MSG_CHANNEL_REBIND",
            payload = {
                transactionId = "TX-REBIND-10040",
                action = "COMMIT",
                oldBaseChannel = 10000,
                newBaseChannel = 10040,
                bandwidth = 40,
            },
        }
        local ok_commit = network_manager.ingest_modem_event(net, "top", 10004, 10004, commit_pkt, 0, 1100)
        assert_true(ok_commit)

        -- Relays COMMIT to VAS on oldBase+1
        assert_eq(#mock_modem._transmitted, 3)
        assert_eq(mock_modem._transmitted[3].tx, 10001)
        assert_eq(mock_modem._transmitted[3].pkt.payload.action, "COMMIT")

        -- Old channels closed
        assert_false(mock_modem.isOpen(10004), "oldBase+4 must be closed after COMMIT")
        assert_false(mock_modem.isOpen(10002), "oldBase+2 must be closed after COMMIT")
        assert_false(mock_modem.isOpen(10001), "oldBase+1 must be closed after COMMIT")

        -- Base channel switched
        assert_eq(net.baseChannel, 10040)
        assert_eq(net.channels.trajectory, 10044)
        assert_eq(net.channels.telemetry, 10042)
        assert_eq(net.channels.guidance, 10041)
    end)

    it("triggers ROLLBACK on 500ms watchdog timeout and closes newBase channels", function()
        local mock_modem = mock.modem({ wireless = true })
        local net = network_manager.init({
            system = { domainId = "AIRCRAFT_01" },
            channels = { baseChannel = 10000 },
        }, function() return mock_modem end)

        local rebind_prepare = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            type = "MSG_CHANNEL_REBIND",
            payload = {
                transactionId = "TX-TIMEOUT",
                action = "PREPARE",
                oldBaseChannel = 10000,
                newBaseChannel = 10040,
                bandwidth = 40,
            },
        }
        network_manager.ingest_modem_event(net, "top", 10004, 10004, rebind_prepare, 0, 1000)
        assert_true(mock_modem.isOpen(10044))

        -- Advance time by 300ms (not yet timed out)
        local status_300 = network_manager.step_rebind_watchdog(net, 1300)
        assert_eq(status_300, "PREPARE")
        assert_true(mock_modem.isOpen(10044))

        -- Advance time past 500ms threshold (t = 1501ms, delta = 501ms)
        local status_501 = network_manager.step_rebind_watchdog(net, 1501)
        assert_eq(status_501, "ROLLED_BACK")

        -- Emits upward MSG_CHANNEL_REBIND_ACK (status = "FAILED") to AMM on oldBase+4 (10004)
        local fail_ack_tx = mock_modem._transmitted[#mock_modem._transmitted - 1]
        assert_eq(fail_ack_tx.tx, 10004)
        assert_eq(fail_ack_tx.pkt.type, "MSG_CHANNEL_REBIND_ACK")
        assert_eq(fail_ack_tx.pkt.payload.status, "FAILED")
        assert_eq(fail_ack_tx.pkt.payload.nodeId, "FCP")

        -- Relays ROLLBACK to VAS on oldBase+1 (10001)
        local last_tx = mock_modem._transmitted[#mock_modem._transmitted]
        assert_eq(last_tx.tx, 10001)
        assert_eq(last_tx.pkt.type, "MSG_CHANNEL_REBIND")
        assert_eq(last_tx.pkt.payload.action, "ROLLBACK")

        -- Pending newBase channels closed
        assert_false(mock_modem.isOpen(10044))
        assert_false(mock_modem.isOpen(10042))
        assert_false(mock_modem.isOpen(10041))

        -- Old baseChannel untouched
        assert_eq(net.baseChannel, 10000)
        assert_true(mock_modem.isOpen(10004))
    end)
end)
