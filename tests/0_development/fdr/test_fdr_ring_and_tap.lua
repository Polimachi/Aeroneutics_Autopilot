-- Unit tests for FDR ring_buffer and dynamic-binding packet_tap
local ring_buffer = require("ring_buffer")
local packet_tap = require("packet_tap")

local function make_base_cfg(overrides)
    local cfg = {
        aircraftIndexN = 1,
        bandwidth = 40,
        domainId = "*",
        modemSide = "top",
        tapOptions = {
            aero = true,
            trajectory = true,
            includeControlEvents = false,
        },
    }
    if overrides then
        for k, v in pairs(overrides) do cfg[k] = v end
    end
    return cfg
end

describe("fdr ring_buffer", function()
    it("retains newest items within capacity, counts drops, and resets cleanly", function()
        local buf = ring_buffer.init(3)
        assert_eq(ring_buffer.capacity(buf), 3)
        assert_eq(ring_buffer.len(buf), 0)
        assert_eq(ring_buffer.dropped(buf), 0)

        for i = 1, 5 do
            assert_true(ring_buffer.push(buf, { seq = i }))
        end
        assert_eq(ring_buffer.len(buf), 3)
        assert_eq(ring_buffer.dropped(buf), 2)

        local snap = ring_buffer.snapshot(buf)
        assert_eq(#snap, 3)
        assert_eq(snap[1].seq, 3)
        assert_eq(snap[2].seq, 4)
        assert_eq(snap[3].seq, 5)

        ring_buffer.clear(buf)
        assert_eq(ring_buffer.len(buf), 0)
        assert_eq(ring_buffer.dropped(buf), 0)
        assert_eq(#ring_buffer.snapshot(buf), 0)
    end)
end)

describe("fdr passive packet_tap", function()
    it("computes valid 40-channel aircraft bases and rejects out-of-range indices", function()
        assert_eq(packet_tap.compute_base(1), 10000)
        assert_eq(packet_tap.compute_base(3), 10080)
        assert_eq(packet_tap.compute_base(1000), 49960)
        local b0, err0 = packet_tap.compute_base(0)
        assert_nil(b0)
        assert_not_nil(err0)
        local bHigh, errHigh = packet_tap.compute_base(1001)
        assert_nil(bHigh)
        assert_not_nil(errHigh)
    end)

    it("opens passive channels only and never calls modem.transmit", function()
        local modem = mock.modem({ wireless = true })
        local tap = packet_tap.init(make_base_cfg(), modem)
        assert_true(packet_tap.open_channels(tap))

        assert_true(modem.isOpen(10001))
        assert_true(modem.isOpen(10002))
        assert_true(modem.isOpen(10010))
        assert_true(modem.isOpen(10011))
        assert_true(modem.isOpen(10004))
        assert_false(modem.isOpen(10006))
        assert_false(modem.isOpen(10007))
        assert_eq(#modem._transmitted, 0)
    end)

    it("dynamically rebinds [N] aircraft channels and auto-locks wildcard domainId", function()
        local modem = mock.modem({ wireless = true })
        local tap = packet_tap.init(make_base_cfg(), modem)
        assert_true(packet_tap.open_channels(tap))

        local ok, err = packet_tap.bind_aircraft(tap, 3, "*")
        assert_true(ok, err)
        assert_false(modem.isOpen(10001))
        assert_false(modem.isOpen(10002))
        assert_true(modem.isOpen(10081))
        assert_true(modem.isOpen(10082))
        assert_true(modem.isOpen(10090))
        assert_true(modem.isOpen(10091))
        assert_true(modem.isOpen(10084))
        assert_eq(tap.lockedDomainId, "*")

        local rec = packet_tap.classify_packet(tap, 10082, {
            ver = "1.9.5",
            domainId = "VIPER_03",
            seq = 12,
            type = "MSG_FLIGHT_TELEMETRY",
            time = 5000,
            payload = { controlState = "NORMAL", sensorOk = true },
        }, 5010)
        assert_not_nil(rec)
        assert_eq(tap.lockedDomainId, "VIPER_03")
        assert_eq(rec.offset, 2)

        local wrongCraft, why = packet_tap.classify_packet(tap, 10082, {
            ver = "1.9.5",
            domainId = "OTHER_CRAFT",
            seq = 13,
            type = "MSG_FLIGHT_TELEMETRY",
            time = 5050,
            payload = { controlState = "NORMAL" },
        }, 5060)
        assert_nil(wrongCraft)
        assert_eq(why, "ERR_DOMAIN_MISMATCH")
        assert_eq(#modem._transmitted, 0)
    end)

    it("enforces v1.9.5 envelope check and identifies E_STOP triggers", function()
        local modem = mock.modem({ wireless = true })
        local tap = packet_tap.init(make_base_cfg({ domainId = "AIRCRAFT_01" }), modem)
        assert_true(packet_tap.open_channels(tap))

        local badVer, badWhy = packet_tap.classify_packet(tap, 10002, {
            ver = "1.9.0",
            domainId = "AIRCRAFT_01",
            type = "MSG_FLIGHT_TELEMETRY",
            payload = {},
        }, 1000)
        assert_nil(badVer)
        assert_eq(badWhy, "ERR_UNSUPPORTED_VER")

        local rEstop = packet_tap.classify_packet(tap, 10002, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 20,
            type = "MSG_FLIGHT_TELEMETRY",
            time = 6000,
            payload = { controlState = "E_STOP" },
        }, 6005)
        assert_not_nil(rEstop)
        assert_true(packet_tap.is_estop_trigger(rEstop))

        local rOver = packet_tap.classify_packet(tap, 10001, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 21,
            type = "MSG_EMERGENCY_OVERRIDE",
            time = 6010,
            payload = { action = "E_STOP", source = "GCS" },
        }, 6012)
        assert_not_nil(rOver)
        assert_true(packet_tap.is_estop_trigger(rOver))

        local rNorm = packet_tap.classify_packet(tap, 10001, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 22,
            type = "MSG_ATTITUDE_CMD",
            time = 6020,
            payload = { commandType = "QUATERNION_RATE" },
        }, 6022)
        assert_not_nil(rNorm)
        assert_false(packet_tap.is_estop_trigger(rNorm))
    end)
end)
