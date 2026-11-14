-- tests/3_planning/amm/test_mission_core_integration.lua
local mission_engine = require("mission_engine")
local network_manager = require("network_manager")
local condition_evaluator = require("condition_evaluator")
local hook_runner = require("hook_runner")

describe("AMM Mission Core Cross-Module Integration", function()
    it("runs ACT_PAT_LOITER_TIME with onEnter pulse + duration completion + low-fuel abort hook sequence", function()
        local rs = mock.redstone()
        local notes = {}
        local runner = hook_runner.new({
            redstone = rs,
            colors = colors,
            on_notify = function(lvl, msg) table.insert(notes, lvl .. ":" .. msg) end,
        })

        local cp, err = mission_engine.normalize_checkpoint({
            checkpointId = "CP_ORBIT_01",
            action = "ACT_PAT_LOITER_TIME",
            params = { targetPos = { x = 600, z = -1500 }, radius = 40, direction = "CW", durationSec = 30 },
            onEnter = {
                { type = "NOTIFY_OPERATOR", level = "INFO", message = "ORBIT START" },
                { type = "REDSTONE_PULSE", side = "top", durationMs = 500 },
            },
            onAbort = {
                { type = "REDSTONE_SET", side = "right", state = true },
            },
            completeWhen = { logic = "ALL", conditions = { { type = "DURATION_SEC", durationSec = 30 } } },
            abortWhen = { logic = "ANY", conditions = { { type = "FUEL_LEVEL_BELOW", threshold = 0.25 } } },
        }, { targetAlt = 140, cruiseSpeed = 18 }, 1)
        assert_nil(err)

        runner:execute_hooks(cp.onEnter, cp, 1000)
        assert_true(rs.getOutput("top"))
        assert_eq(notes[1], "INFO:ORBIT START")

        runner:tick(1500)
        assert_false(rs.getOutput("top"))

        local eval_low_fuel = condition_evaluator.evaluate_checkpoint(cp, {
            mfd = { fuel = 0.20, dynamics = { altitudeY = 140 }, navigation = { currentPos = { x = 640, z = -1500 } } },
            enteredAtMs = 1000,
            nowMs = 31000, -- Both durationSec(30s) and fuel_below(0.25) satisfied -> abortWhen must take precedence
        })
        assert_true(eval_low_fuel.aborted)
        assert_false(eval_low_fuel.completed)

        runner:execute_hooks(cp.onAbort, cp, 10000)
        assert_true(rs.getOutput("right"))
    end)

    it("runs ACT_PAY_BUS_CMD dynamic Zone 3 lifecycle into PAYLOAD_RESP_MATCH completion and channel close", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local runner = hook_runner.new({ net = net })

        local cp, err = mission_engine.normalize_checkpoint({
            checkpointId = "CP_CARGO",
            action = "ACT_PAY_BUS_CMD",
            params = { channelOffset = 20, command = "RELEASE_BAY", commandPayload = { bayId = 1 }, expectedStatus = "DROPPED" },
            onExit = { { type = "ZONE3_PAYLOAD_CMD", channelOffset = 20, command = "LOCK_DOOR", payload = {} } },
        }, nil, 1, { baseChannel = 10000 })
        assert_nil(err)

        assert_true(runner:start_action(cp, 2000))
        assert_true(m.isOpen(10020))

        local pre = condition_evaluator.evaluate_checkpoint(cp, { checkpoint = cp, payloadAck = runner:get_last_payload_ack(), enteredAtMs = 2000, nowMs = 2100 })
        assert_false(pre.completed)

        assert_true(runner:on_payload_ack({
            ver = "1.9.5", type = "MSG_PAYLOAD_ACK",
            payload = { checkpointId = "CP_CARGO", command = "RELEASE_BAY", status = "DROPPED" },
        }, 10020))
        assert_false(m.isOpen(10020))

        local post = condition_evaluator.evaluate_checkpoint(cp, { checkpoint = cp, payloadAck = runner:get_last_payload_ack(), enteredAtMs = 2000, nowMs = 2250 })
        assert_true(post.completed)

        runner:execute_hooks(cp.onExit, cp, 2250)
        assert_false(m.isOpen(10020))
        assert_true(m.isOpen(10000))
        assert_true(m.isOpen(10003))
    end)

    it("runs ACT_PAY_REDSTONE WAIT_INPUT to completion and executes onExit cleanup cleanly", function()
        local rs = mock.redstone()
        local runner = hook_runner.new({ redstone = rs, colors = colors })

        local cp, err = mission_engine.normalize_checkpoint({
            checkpointId = "CP_RS_WAIT",
            action = "ACT_PAY_REDSTONE",
            params = { mode = "WAIT_INPUT", side = "back", minLevel = 8 },
            onExit = { { type = "REDSTONE_SET", side = "left", state = true } },
        }, nil, 1)
        assert_nil(err)

        assert_true(runner:start_action(cp, 3000))
        rs.setAnalogInput("back", 5)
        assert_false(condition_evaluator.evaluate_checkpoint(cp, { redstone = rs, colors = colors, enteredAtMs = 3000, nowMs = 3100 }).completed)

        rs.setAnalogInput("back", 10)
        assert_true(condition_evaluator.evaluate_checkpoint(cp, { redstone = rs, colors = colors, enteredAtMs = 3000, nowMs = 3200 }).completed)

        runner:execute_hooks(cp.onExit, cp, 3200)
        assert_true(rs.getOutput("left"))
    end)
end)
