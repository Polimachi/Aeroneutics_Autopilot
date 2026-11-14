-- tests/3_planning/amm/test_hook_runner.lua
local network_manager = require("network_manager")
local hook_runner = require("hook_runner")

describe("AMM 0-Tick Hook Runner and Zone 3 / Redstone Driver", function()
    local function create_bundled_redstone()
        local rs = mock.redstone()
        rs._bundledOut = {}
        rs.getBundledOutput = function(side) return rs._bundledOut[side] or 0 end
        rs.setBundledOutput = function(side, mask) rs._bundledOut[side] = mask end
        return rs
    end

    it("executes REDSTONE_SET (digital, analog, bundled) and NOTIFY_OPERATOR in 0 ticks", function()
        local rs = create_bundled_redstone()
        local notes = {}
        local runner = hook_runner.new({
            redstone = rs,
            colors = colors,
            on_notify = function(lvl, msg) table.insert(notes, { level = lvl, message = msg }) end,
        })

        local count, emitted = runner:execute_hooks({
            { type = "REDSTONE_SET", side = "right", state = true },
            { type = "REDSTONE_SET", side = "left", level = 11 },
            { type = "REDSTONE_SET", side = "top", color = colors.blue, state = true },
            { type = "NOTIFY_OPERATOR", level = "INFO", message = "ORBIT SURVEILLANCE START" },
        }, { checkpointId = "CP_03" }, 1000)

        assert_eq(count, 4)
        assert_true(rs.getOutput("right"))
        assert_eq(rs.getAnalogOutput("left"), 11)
        assert_eq(bit32.band(rs.getBundledOutput("top"), colors.blue), colors.blue)
        assert_eq(#notes, 1)
        assert_eq(emitted[1].message, "ORBIT SURVEILLANCE START")
    end)

    it("schedules REDSTONE_PULSE without sleep(), extends overlapping pulses, and preserves unrelated bundled colors", function()
        local rs = create_bundled_redstone()
        rs.setBundledOutput("top", colors.blue)
        local runner = hook_runner.new({ redstone = rs, colors = colors })

        runner:execute_hooks({
            { type = "REDSTONE_PULSE", side = "top", color = colors.red, durationMs = 500 },
        }, { checkpointId = "CP_01" }, 1000)

        assert_eq(bit32.band(rs.getBundledOutput("top"), colors.red), colors.red)
        assert_eq(bit32.band(rs.getBundledOutput("top"), colors.blue), colors.blue)

        -- Overlap another red pulse at 1200ms -> extends deadline to 1700ms
        runner:execute_hooks({
            { type = "REDSTONE_PULSE", side = "top", color = colors.red, durationMs = 500 },
        }, { checkpointId = "CP_02" }, 1200)

        assert_eq(runner:tick(1500), 0)
        assert_eq(bit32.band(rs.getBundledOutput("top"), colors.red), colors.red)

        assert_eq(runner:tick(1700), 1)
        assert_eq(bit32.band(rs.getBundledOutput("top"), colors.red), 0)
        assert_eq(bit32.band(rs.getBundledOutput("top"), colors.blue), colors.blue)
    end)

    it("deactivates active orphan pulses and closes leaked Zone 3 channels on cleanup()", function()
        local rs = create_bundled_redstone()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)

        local runner = hook_runner.new({ net = net, redstone = rs, colors = colors })
        runner:execute_hooks({
            { type = "REDSTONE_PULSE", side = "front", durationMs = 2000 },
        }, { checkpointId = "CP_01" }, 1000)
        assert_true(rs.getOutput("front"))

        local ok = runner:start_action({
            checkpointId = "CP_04",
            action = "ACT_PAY_BUS_CMD",
            params = { channelOffset = 20, command = "RELEASE_BAY", commandPayload = { bayId = 1 }, waitForAck = true },
        }, 1000)
        assert_true(ok)
        assert_true(m.isOpen(10020))

        runner:cleanup()
        assert_false(rs.getOutput("front"))
        assert_false(m.isOpen(10020))
        assert_true(m.isOpen(10000))
        assert_true(m.isOpen(10003))
        assert_nil(runner:get_last_payload_ack())
    end)

    it("manages ACT_PAY_BUS_CMD dynamic Zone 3 open-ACK-close lifecycle, rejects wrong channel/checkpointId, and handles ZONE3_PAYLOAD_CMD", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local runner = hook_runner.new({ net = net })

        local ok, err = runner:start_action({
            checkpointId = "CP_04",
            action = "ACT_PAY_BUS_CMD",
            params = { channelOffset = 20, command = "RELEASE_BAY", commandPayload = { bayId = 1 }, waitForAck = true },
        }, 2000)
        assert_nil(err)
        assert_true(ok)
        assert_true(m.isOpen(10020))

        -- Stale checkpointId ACK or non-Zone3 channel must not close channel or overwrite ACK
        local m1 = runner:on_payload_ack({
            ver = "1.9.5", type = "MSG_PAYLOAD_ACK",
            payload = { checkpointId = "CP_OLD", command = "RELEASE_BAY", status = "DROPPED" },
        }, 10020)
        assert_false(m1)
        assert_true(m.isOpen(10020))

        local m2 = runner:on_payload_ack({
            ver = "1.9.5", type = "MSG_PAYLOAD_ACK",
            payload = { checkpointId = "CP_04", command = "RELEASE_BAY", status = "DROPPED" },
        }, 10000)
        assert_false(m2)
        assert_true(m.isOpen(10020))

        local m3, ack = runner:on_payload_ack({
            ver = "1.9.5", type = "MSG_PAYLOAD_ACK",
            payload = { checkpointId = "CP_04", command = "RELEASE_BAY", status = "DROPPED", detail = { empty = true } },
        }, 10020)
        assert_true(m3)
        assert_eq(ack.status, "DROPPED")
        assert_false(m.isOpen(10020))
        assert_eq(runner:get_last_payload_ack().status, "DROPPED")

        -- Fire-and-forget ZONE3_PAYLOAD_CMD must transmit payload and leave channel closed
        runner:execute_hooks({
            { type = "ZONE3_PAYLOAD_CMD", channelOffset = 21, command = "TRIGGER_RADAR", payload = { scan = true } },
        }, { checkpointId = "CP_05" }, 3000)
        assert_false(m.isOpen(10021))
        assert_eq(m._transmitted[2].tx, 10021)
        assert_eq(m._transmitted[2].pkt.type, "MSG_PAYLOAD_REQ")
        assert_true(m._transmitted[2].pkt.payload.params.scan)

        -- Invalid Zone 3 channel or deferred action returns explicit error without transmitting
        local ok_bad_ch, err_bad_ch = runner:start_action({
            checkpointId = "CP_BAD_CH",
            action = "ACT_PAY_BUS_CMD",
            params = { channelOffset = 10, command = "HIJACK_TCA" },
        }, 3050)
        assert_false(ok_bad_ch)
        assert_eq(err_bad_ch, "INVALID_ZONE3_CHANNEL")

        local ok_def, err_def = runner:start_action({ checkpointId = "CP_DEF", action = "ACT_MOB_ARM_DOCK", params = {} }, 3100)
        assert_false(ok_def)
        assert_eq(err_def, "DEFERRED_ACTION_UNSUPPORTED")
    end)

    it("executes ACT_PAY_REDSTONE EMIT pulses and ignores WAIT_INPUT without side effects", function()
        local rs = mock.redstone()
        local runner = hook_runner.new({ redstone = rs })

        local ok_e = runner:start_action({
            checkpointId = "CP_RS1",
            action = "ACT_PAY_REDSTONE",
            params = { mode = "EMIT", side = "bottom", level = 12, durationMs = 250 },
        }, 5000)
        assert_true(ok_e)
        assert_eq(rs.getAnalogOutput("bottom"), 12)
        assert_false(rs.getOutput("bottom"))
        assert_eq(runner:tick(5249), 0)
        assert_eq(rs.getAnalogOutput("bottom"), 12)
        assert_eq(runner:tick(5250), 1)
        assert_eq(rs.getAnalogOutput("bottom"), 0)

        local ok_w = runner:start_action({
            checkpointId = "CP_RS2",
            action = "ACT_PAY_REDSTONE",
            params = { mode = "WAIT_INPUT", side = "back", minLevel = 1 },
        }, 5300)
        assert_true(ok_w)
    end)
end)
