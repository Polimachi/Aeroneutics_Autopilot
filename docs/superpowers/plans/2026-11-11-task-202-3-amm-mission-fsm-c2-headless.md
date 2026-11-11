# AMM Polymorphic Mission Loader, Sequencer FSM, Remote C2 & Headless Mode (TASK-202-3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execute implementation in the active isolated git worktree (`.worktrees/task-202-2-amm-core` on branch `feat/task-202-2-amm-core`).

**Goal:** Extend `mission_engine.lua`, `c2_arbiter.lua`, and `main.lua` to implement the polymorphic `missions/*.json` loader (`v1.1.0 checkpoints` + legacy `v1.0.0 items`), the 5-state mission sequencer FSM (`IDLE`, `EN_ROUTE`, `SUSPENDED`, `COMPLETED`, `ABORTED`) with `SINGLE`/`REPEAT` loops and `PATROL` sub-waypoint cycling, `Base+0` `MSG_MISSION_CMD`/`MSG_MISSION_ACK` remote C2 arbitration, and `config.headless` UAV operation.

**Architecture:** `mission_engine.lua` builds stateful sequencer instances on top of Task 202-2's schema validators, `condition_evaluator`, and `hook_runner` to load/save JSON missions, dispatch FCP `MSG_OPERATOR_CMD` packets across all 9 active actions, cycle `PATROL` sub-waypoints (`LOOP`/`PING_PONG`), execute `onEnter`/`onExit`/`onAbort` hooks, and delegate `abortWhen` failsafes (`RTH`, `HOVER_HOLD`, `LOITER`, `SKIP_NEXT`). `c2_arbiter.lua` arbitrates `Base+0` `MSG_MISSION_CMD` requests (`RUN`, `STOP`, `PAUSE`, `RESUME`, `NEXT`) with `MSG_MISSION_ACK` responses (`ACCEPTED`, `BUSY_REJECTED`, `FILE_NOT_FOUND`, `DEFERRED_ACTION_UNSUPPORTED`, `INVALID_CMD`) while preserving `MUT-05` and legacy `waypoint_queue` compatibility. `main.lua` wires the 5Hz timer tick and Zone 3 `modem_message` (`Base+20~29`) into the engine while bypassing `ui_renderer` calls when `config.headless == true`.

**Tech Stack:** CC:Tweaked 1.109+ Lua 5.2 (Cobalt VM, `bit32`, `fs`, `textutils`), CraftOS-PC Headless Unit Test Runner (`tools/run_unit_tests.py`), Multi-Node E2E Simulation Harness (`tools/run_e2e_tests.py`), Mutation Test Runner (`tools/run_mutation_tests.py`), Python 3.10+ Manifest/Syntax/Context Verifiers (`tools/verify_manifest_sync.py`, `tools/validate_lua_syntax.py`, `tools/verify_context_docs.py`).

**Spec:**
- Primary Specification: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v1.1.0 Approved` — remains `Approved` after `TASK-202-3`; promoted to `Implemented` at `TASK-202-5`)
- Master ICD: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.26.0 Approved` — Interface I-6 `MSG_OPERATOR_CMD`, `MSG_MISSION_CMD`/`MSG_MISSION_ACK`, Interface I-11 Zone 3 `MSG_PAYLOAD_REQ`/`MSG_PAYLOAD_ACK`)
- Roadmap SSOT: `TASK.md` (`TASK-202-3`)

## Global Constraints

- **Lua 5.2 Cobalt Runtime (`.agent/rules/cc-tweaked-runtime.md`)**: No Lua 5.3+ operators (`//`, `&`, `|`, `~`, `<<`, `>>`); use `fs.*` for file I/O (`fs.open`, `fs.exists`) and never use `io.open`, `os.execute`, `io.popen`, `os.exit`, `os.remove`, or `os.rename`.
- **Non-Blocking Loop Contract (`AMM_PROGRAM_SPECIFICATION.md` §1.3, §6.4, §9)**: Zero calls to `sleep()`, `os.pullEvent()`, or `os.pullEventRaw()` inside `mission_engine.lua` or `c2_arbiter.lua` (`runner_lib.lua` aborts unit tests with `EVENT_SWALLOW_VIOLATION` if called).
- **Single-Function Complexity (`AMM_PROGRAM_SPECIFICATION.md` §9, §10)**: Keep every Lua function at `<= 50` lines via dispatch tables (`FCP_DISPATCHERS`, `FALLBACK_HANDLERS`, `MISSION_CMD_HANDLERS`).
- **Valkyrien Skies Mod Ban (`.agent/rules/domain-aeronautics.md`)**: Zero prohibited mod identifiers (`valkyrien`, `vs2`, `cc_vs`, `ship` peripheral, `kontraption:`).
- **Mutation Target Line & Legacy API Preservation (`tools/run_mutation_tests.py`, `tests/3_planning/amm/`)**: Preserve `MUT-04` in `src/3_planning/amm/modules/waypoint_queue.lua` (`if d2d <= rad then`) and `MUT-05` in `src/3_planning/amm/modules/c2_arbiter.lua` (`if self.queue and self.queue.state == "EN_ROUTE" then self.queue.state = "SUSPENDED" end`), and keep all existing tests in `test_c2_arbiter.lua`, `test_main_loop.lua`, and `test_amm_integration.lua` passing.
- **Zero-Fallback Protocol Standard (`AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` §1.3)**: Emit and parse only canonical ICD v1.9.5 / AMM v1.1.0 fields (`action`, `missionName`, `executionMode`, `forceRestart`, `status`, `missionId`, `missionState`, `activeIndex`, `totalCheckpoints`).

## Review Focus

1. **Mid-Flight `REPEAT` Loop Re-Triggering Ground `TAKEOFF_LAUNCHPAD`**: When `executionMode == "REPEAT"` wraps around after the final checkpoint, resetting `active_index = 1` when `checkpoints[1].action == "TAKEOFF_LAUNCHPAD"` would issue ground `ARM`/`TAKEOFF` while already airborne; `REPEAT` wrap-around must target the first airborne checkpoint (`index 2` when `checkpoints[1].action == "TAKEOFF_LAUNCHPAD"` and `#checkpoints >= 2`, otherwise `1`) and clear per-checkpoint completion markers (pinned by test in Task 1 `test_mission_fsm.lua`).
2. **Remote `MSG_MISSION_CMD (RUN)` Overwriting an Active Mission or Accepting Missing/Deferred Mission Files**: Receiving `MSG_MISSION_CMD` with `action = "RUN"` while `engine.state == "EN_ROUTE"` and `forceRestart ~= true` must reply `MSG_MISSION_ACK` with `status = "BUSY_REJECTED"` without altering `active_index`; if `missionName` is missing on disk or contains a deferred action (`TAKEOFF_RUNWAY`, `DOCK_ARM`, etc.), `c2_arbiter` must reply `status = "FILE_NOT_FOUND"` or `status = "DEFERRED_ACTION_UNSUPPORTED"` without emitting FCP commands (pinned by tests in Task 2 `test_c2_arbiter.lua`).
3. **`PATROL` `PING_PONG` Multi-Waypoint Bounce & Single-Waypoint Degeneracy**: A `PATROL` checkpoint with `patrolMode = "PING_PONG"`, `cycles = 1`, and 3 waypoints (`1 -> 2 -> 3 -> 2 -> 1`) must not mark `patrolCompleted = true` upon reaching waypoint 3 before bouncing back to waypoint 1, and a 1-waypoint `PING_PONG` patrol must complete cleanly without index out-of-bounds or infinite loops (pinned by tests in Task 1 `test_mission_fsm.lua`).
4. **Headless Mode (`config.headless = true`) Leaking Terminal Calls or Starving Hook/Timer Deadlines**: When `config.headless == true` in `main.lua`, `process_event` on the 5Hz timer must execute zero `ui_renderer.render_screen` / `ui_renderer.flush_buffer` calls on `term` while still advancing `engine:tick(now_ms)` so `REDSTONE_PULSE` expirations and `TIMEOUT_SEC`/`DURATION_SEC` conditions fire even when no `MSG_MFD_STATE` packet arrives (pinned by test in Task 3 `test_main_loop.lua`).
5. **Legacy v1.0.0 `items` JSON Losing Final `facilityId` Landing Action on Polymorphic Load**: Loading a legacy v1.0.0 `{ version = "1.0.0", items = { { x = 100, z = 100 }, { x = 200, z = 200, facilityId = "PAD_BRAVO_01" } } }` file via `mission_engine:load()` must normalize every item into a `FLY_OVER` checkpoint and append a trailing `LAND_LAUNCHPAD` checkpoint (`facilityId = "PAD_BRAVO_01"`) for the final item so landing behavior is preserved (pinned by test in Task 1 `test_mission_fsm.lua`).

---

## File Structure

- Modify: `src/3_planning/amm/modules/mission_engine.lua` — Add `mission_engine.new(opts)`, polymorphic JSON `load`/`load_table`/`save`, 5-state FSM (`start`, `stop`, `pause`, `resume`, `skip_next`, `goto_index`), 9-action FCP command dispatcher, `PATROL` (`LOOP`/`PING_PONG`) sub-waypoint sequencer, `step_telemetry(mfd, now_ms)`, `tick(now_ms)`, `on_payload_ack(pkt, ch, now_ms)`, and `abortWhen` `fallbackPolicy` delegation (`RTH`, `HOVER_HOLD`, `LOITER`, `SKIP_NEXT`).
- Modify: `src/3_planning/amm/modules/c2_arbiter.lua` — Attach optional `mission_engine` instance, implement `handle_mission_cmd(packet, now_ms)` (`RUN`, `STOP`, `PAUSE`, `RESUME`, `NEXT`) with `MSG_MISSION_ACK` replies on `Base+0`, route `MSG_MISSION_CMD` inside `handle_gcs_packet`, synchronize `GCS_OVERRIDE` and pilot takeover (`HOLD`, `RTH`, `LAND`, `ESTOP`, `PAUSE`, `RESUME`) across `queue` and `engine`, and drive `engine:step_telemetry` from `handle_mfd_state`.
- Modify: `src/3_planning/amm/main.lua` — Initialize `mission_engine` and bind to `c2_arbiter`, add `headless = false` default in `load_config`, gate `ui_renderer` behind `not app.config.headless`, tick `app.engine:tick()` on the 5Hz timer, route Zone 3 (`Base+20~29`) `modem_message` packets to `app.engine:on_payload_ack`, and support `autoStartMission`.
- Create: `tests/3_planning/amm/test_mission_fsm.lua` — Unit tests for polymorphic `load`/`save` (`v1.1.0` & legacy `v1.0.0`), 9-action FCP dispatch, `PATROL` (`LOOP`/`PING_PONG`), `SINGLE`/`REPEAT` wrap-around, `abortWhen` 4-policy failsafes, and Zone 3 `PAYLOAD_ACTION` step auto-advance.
- Modify: `tests/3_planning/amm/test_c2_arbiter.lua` — Unit tests for `MSG_MISSION_CMD` (`RUN`, `BUSY_REJECTED`, `forceRestart`, `FILE_NOT_FOUND`, `DEFERRED_ACTION_UNSUPPORTED`, `STOP`, `PAUSE`, `RESUME`, `NEXT`) and `GCS_OVERRIDE`/pilot takeover with `mission_engine`.
- Modify: `tests/3_planning/amm/test_main_loop.lua` — Unit tests for `config.headless == true` (zero terminal writes + active 5Hz engine tick), Zone 3 `modem_message` routing, and `Base+0` `MSG_MISSION_CMD` event dispatch.
- Modify: `TASK.md:71` & `.agent/memory/workspace-root.md` — Mark `TASK-202-3` `[x]` and record milestone history.

---

### Task 1: Polymorphic Mission Loader, 9-Action FCP Dispatcher & Step Auto-Transition FSM (`mission_engine.lua`)

**Files:**
- Modify: `src/3_planning/amm/modules/mission_engine.lua:1-302`
- Create: `tests/3_planning/amm/test_mission_fsm.lua`

**Interfaces:**
- Consumes:
  - `condition_evaluator` (`should_arm_touchdown`, `evaluate_checkpoint`, `format_progress`)
  - `hook_runner` (`new`, `:execute_hooks`, `:start_action`, `:tick`, `:on_payload_ack`, `:get_last_payload_ack`, `:clear_step_state`, `:cleanup`)
  - `network_manager` (`:send_operator_cmd`, `:is_payload_channel`, `:close_all_payload_channels`)
- Produces:
  - `mission_engine.new(opts) -> engine` (`opts = { net, hook_runner, config, redstone, colors, on_notify }`)
  - `engine:load_table(data) -> boolean, string|nil`
  - `engine:load(filepath) -> boolean, string|nil`
  - `engine:save(filepath) -> boolean, string|nil`
  - `engine:start(execution_mode, now_ms) -> boolean, string|nil`
  - `engine:stop(now_ms) -> boolean`
  - `engine:pause() -> boolean`
  - `engine:resume(now_ms) -> boolean`
  - `engine:skip_next(now_ms) -> boolean, string|nil`
  - `engine:goto_index(index, now_ms) -> boolean, string|nil`
  - `engine:step_telemetry(mfd_payload, now_ms) -> string, any`
  - `engine:tick(now_ms) -> string, any`
  - `engine:on_payload_ack(packet, channel, now_ms) -> boolean, any`
  - `engine:get_active() -> table|nil`
  - `engine:count() -> integer`

- [ ] **Step 1: Write the failing unit tests in `tests/3_planning/amm/test_mission_fsm.lua`**

Create `tests/3_planning/amm/test_mission_fsm.lua`:
```lua
-- tests/3_planning/amm/test_mission_fsm.lua
local network_manager = require("network_manager")
local mission_engine = require("mission_engine")

describe("AMM Mission Engine Polymorphic Loader and Sequencer FSM", function()
    local function create_engine_fixture(extra_opts)
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local rs = mock.redstone()
        local opts = extra_opts or {}
        opts.net = net
        opts.redstone = rs
        opts.colors = colors
        opts.config = { baseChannel = 10000, defaultAlt = 150.0, defaultSpeed = 18.0, arrivalRadius = 15.0 }
        local eng = mission_engine.new(opts)
        return eng, net, m, rs
    end

    it("loads v1.1.0 checkpoints JSON and normalizes legacy v1.0.0 items JSON with trailing LAND_LAUNCHPAD", function()
        local eng = create_engine_fixture()

        -- Write legacy v1.0.0 mission file
        local f1 = fs.open("missions/legacy_test.json", "w")
        f1.write(textutils.serializeJSON({
            version = "1.0.0",
            items = {
                { id = 1, x = 100, z = 200, alt = 140, speed = 18 },
                { id = 2, x = 300, z = 400, alt = 120, speed = 15, facilityId = "PAD_BRAVO_01" },
            },
        }))
        f1.close()

        local ok_leg, err_leg = eng:load("missions/legacy_test.json")
        assert_true(ok_leg, tostring(err_leg))
        assert_eq(eng:count(), 3)
        assert_eq(eng.checkpoints[1].action, "FLY_OVER")
        assert_eq(eng.checkpoints[1].params.targetPos.x, 100)
        assert_eq(eng.checkpoints[2].action, "FLY_OVER")
        assert_eq(eng.checkpoints[2].params.targetPos.x, 300)
        assert_eq(eng.checkpoints[3].action, "LAND_LAUNCHPAD")
        assert_eq(eng.checkpoints[3].params.facilityId, "PAD_BRAVO_01")

        -- Save as v1.1.0 and reload
        assert_true(eng:save("missions/saved_v110.json"))
        local eng2 = create_engine_fixture()
        assert_true(eng2:load("missions/saved_v110.json"))
        assert_eq(eng2:count(), 3)
        assert_eq(eng2.checkpoints[3].action, "LAND_LAUNCHPAD")

        fs.delete("missions/legacy_test.json")
        fs.delete("missions/saved_v110.json")
    end)

    it("dispatches 9 active actions to FCP, sequences SINGLE mode to COMPLETED, and loops REPEAT mode to first airborne step", function()
        local eng, _, m, rs = create_engine_fixture()
        local ok, err = eng:load_table({
            missionId = "SORTIE_REPEAT",
            executionMode = "REPEAT",
            defaults = { targetAlt = 140.0, cruiseSpeed = 18.0, acceptanceRadius = 15.0 },
            checkpoints = {
                { checkpointId = "CP_TK", action = "TAKEOFF_LAUNCHPAD", params = { targetAlt = 140, facilityId = "PAD_01" } },
                {
                    checkpointId = "CP_ORB",
                    action = "ORBIT",
                    params = { targetPos = { x = 500, z = -500 }, radius = 40, direction = "CCW", durationSec = 10 },
                    onEnter = { { type = "REDSTONE_PULSE", side = "top", durationMs = 500 } },
                },
                {
                    checkpointId = "CP_POI",
                    action = "POI_HOLD",
                    params = { targetPos = { x = 600, z = -600 }, poiPos = { x = 650, y = 70, z = -600 }, durationSec = 5 },
                },
            },
        })
        assert_true(ok, tostring(err))

        -- Start from DISARMED -> sends ARM then TAKEOFF
        assert_true(eng:start("REPEAT", 1000))
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.active_index, 1)
        assert_eq(#m._transmitted, 2)
        assert_eq(m._transmitted[1].pkt.payload.command, "ARM")
        assert_eq(m._transmitted[2].pkt.payload.command, "TAKEOFF")

        -- FCP enters CRUISE -> TAKEOFF_LAUNCHPAD completes, advances to CP_ORB (index 2)
        local st1 = eng:step_telemetry({ fsmState = "CRUISE", dynamics = { altitudeY = 140 }, navigation = { currentPos = { x = 0, z = 0 } } }, 2000)
        assert_eq(st1, "ADVANCED")
        assert_eq(eng.active_index, 2)
        assert_true(rs.getOutput("top"))
        local orb_cmd = m._transmitted[#m._transmitted].pkt.payload
        assert_eq(orb_cmd.command, "LOITER")
        assert_eq(orb_cmd.flightMode, "LOITER")
        assert_eq(orb_cmd.params.loiterRadius, 40)
        assert_eq(orb_cmd.params.loiterDirection, "CCW")

        -- Tick expires pulse at 2500ms; ORBIT duration (10s) completes at 12000ms -> advances to CP_POI (index 3)
        eng:tick(2500)
        assert_false(rs.getOutput("top"))
        local st2 = eng:step_telemetry({ fsmState = "LOITER", dynamics = { altitudeY = 140 }, navigation = { currentPos = { x = 500, z = -500 } } }, 12000)
        assert_eq(st2, "ADVANCED")
        assert_eq(eng.active_index, 3)
        local poi_cmd = m._transmitted[#m._transmitted].pkt.payload
        assert_eq(poi_cmd.command, "POI_HOLD")
        assert_eq(poi_cmd.flightMode, "POI_HOLD")
        assert_eq(poi_cmd.params.poiTarget.x, 650)

        -- POI_HOLD duration (5s) completes at 17000ms -> REPEAT mode wraps to index 2 (first airborne step, skipping TAKEOFF_LAUNCHPAD!)
        local st3 = eng:step_telemetry({ fsmState = "POI_HOLD", dynamics = { altitudeY = 140 }, navigation = { currentPos = { x = 600, z = -600 } } }, 17000)
        assert_eq(st3, "LOOPED")
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.active_index, 2)
    end)

    it("cycles PATROL sub-waypoints in both LOOP and PING_PONG modes including 1-waypoint degeneracy", function()
        local eng, _, m = create_engine_fixture()
        assert_true(eng:load_table({
            missionId = "PATROL_TEST",
            checkpoints = {
                {
                    checkpointId = "CP_PAT_PP",
                    action = "PATROL",
                    params = {
                        patrolMode = "PING_PONG",
                        cycles = 1,
                        acceptanceRadius = 10,
                        waypoints = {
                            { x = 0, z = 0 },
                            { x = 100, z = 0 },
                            { x = 200, z = 0 },
                        },
                    },
                },
                {
                    checkpointId = "CP_PAT_1WP",
                    action = "PATROL",
                    params = {
                        patrolMode = "PING_PONG",
                        cycles = 1,
                        acceptanceRadius = 10,
                        waypoints = { { x = 300, z = 0 } },
                    },
                },
            },
        }))

        assert_true(eng:start("SINGLE", 1000))
        assert_eq(m._transmitted[#m._transmitted].pkt.payload.params.targetWaypoint.x, 0)

        -- Reach WP1(0,0) -> subIndex 2(100,0)
        eng:step_telemetry({ fsmState = "CRUISE", navigation = { currentPos = { x = 0, z = 0 } } }, 1200)
        assert_eq(eng.active_index, 1)
        assert_eq(m._transmitted[#m._transmitted].pkt.payload.params.targetWaypoint.x, 100)

        -- Reach WP2(100,0) -> subIndex 3(200,0)
        eng:step_telemetry({ fsmState = "CRUISE", navigation = { currentPos = { x = 100, z = 0 } } }, 1400)
        assert_eq(eng.active_index, 1)
        assert_eq(m._transmitted[#m._transmitted].pkt.payload.params.targetWaypoint.x, 200)

        -- Reach WP3(200,0) -> PING_PONG must bounce back to subIndex 2(100,0), NOT complete yet!
        eng:step_telemetry({ fsmState = "CRUISE", navigation = { currentPos = { x = 200, z = 0 } } }, 1600)
        assert_eq(eng.active_index, 1)
        assert_eq(m._transmitted[#m._transmitted].pkt.payload.params.targetWaypoint.x, 100)

        -- Reach WP2(100,0) -> subIndex 1(0,0)
        eng:step_telemetry({ fsmState = "CRUISE", navigation = { currentPos = { x = 100, z = 0 } } }, 1800)
        assert_eq(eng.active_index, 1)
        assert_eq(m._transmitted[#m._transmitted].pkt.payload.params.targetWaypoint.x, 0)

        -- Reach WP1(0,0) -> completes 1 full PING_PONG cycle -> advances to CP_PAT_1WP (index 2)
        local st = eng:step_telemetry({ fsmState = "CRUISE", navigation = { currentPos = { x = 0, z = 0 } } }, 2000)
        assert_eq(st, "ADVANCED")
        assert_eq(eng.active_index, 2)

        -- Reach single waypoint (300,0) -> completes cleanly without index error
        local st_end = eng:step_telemetry({ fsmState = "CRUISE", navigation = { currentPos = { x = 300, z = 0 } } }, 2200)
        assert_eq(st_end, "COMPLETED")
        assert_eq(eng.state, "COMPLETED")
    end)

    it("delegates abortWhen fallbackPolicy (SKIP_NEXT, RTH, HOVER_HOLD, LOITER) and cleans up Zone 3 on abort/stop", function()
        local eng, _, m, rs = create_engine_fixture()
        assert_true(eng:load_table({
            missionId = "ABORT_TEST",
            fallbackPolicy = "RTH",
            checkpoints = {
                {
                    checkpointId = "CP_SKIP",
                    action = "PAYLOAD_ACTION",
                    params = { channelOffset = 20, command = "DROP", waitForAck = true },
                    fallbackPolicy = "SKIP_NEXT",
                    abortWhen = { logic = "ANY", conditions = { { type = "TIMEOUT_SEC", timeout = 5 } } },
                },
                {
                    checkpointId = "CP_RTH",
                    action = "FLY_TO",
                    params = { targetPos = { x = 1000, z = 1000 }, targetAlt = 150 },
                    onAbort = { { type = "REDSTONE_SET", side = "right", state = true } },
                    abortWhen = { logic = "ANY", conditions = { { type = "FUEL_LEVEL_BELOW", threshold = 0.25 } } },
                },
            },
        }))

        assert_true(eng:start("SINGLE", 1000))
        assert_true(m.isOpen(10020))

        -- Timeout at 6000ms triggers SKIP_NEXT -> closes 10020, marks CP_SKIP ABORTED, advances to CP_RTH (index 2)
        local st_skip = eng:tick(6000)
        assert_eq(st_skip, "SKIPPED")
        assert_false(m.isOpen(10020))
        assert_eq(eng.checkpoints[1].status, "ABORTED")
        assert_eq(eng.active_index, 2)
        assert_eq(eng.state, "EN_ROUTE")

        -- Low fuel on CP_RTH triggers mission fallbackPolicy = "RTH" -> executes onAbort, state = ABORTED, sends emergencyAction = "RTH"
        local st_rth = eng:step_telemetry({ fsmState = "CRUISE", fuel = 0.20, dynamics = { altitudeY = 150 }, navigation = { currentPos = { x = 100, z = 100 } } }, 7000)
        assert_eq(st_rth, "ABORTED")
        assert_eq(eng.state, "ABORTED")
        assert_true(rs.getOutput("right"))
        local last_pkt = m._transmitted[#m._transmitted].pkt.payload
        assert_eq(last_pkt.emergencyAction, "RTH")

        -- Verify HOVER_HOLD and LOITER fallbackPolicy delegation
        eng.checkpoints[2].fallbackPolicy = "HOVER_HOLD"
        eng:goto_index(2, 8000)
        eng:step_telemetry({ fsmState = "CRUISE", fuel = 0.20, dynamics = { altitudeY = 150 }, navigation = { currentPos = { x = 100, z = 100 } } }, 8100)
        assert_eq(m._transmitted[#m._transmitted].pkt.payload.emergencyAction, "HOVER_HOLD")

        eng.checkpoints[2].fallbackPolicy = "LOITER"
        eng:goto_index(2, 9000)
        eng:step_telemetry({ fsmState = "CRUISE", fuel = 0.20, dynamics = { altitudeY = 150 }, navigation = { currentPos = { x = 100, z = 100 } } }, 9100)
        assert_eq(m._transmitted[#m._transmitted].pkt.payload.flightMode, "LOITER")
    end)
end)
```

- [ ] **Step 2: Run the unit test to verify it fails**

Run:
```powershell
Set-Location c:\Users\sjmik\Desktop\Create_Aeroneutics\.worktrees\task-202-2-amm-core; python tools/run_unit_tests.py --target 3_planning/amm --filter mission_fsm --clean-orphans
```
Expected: FAIL (`attempt to call field 'new' (a nil value)` on `mission_engine`).

- [ ] **Step 3: Implement the mission loader, FCP dispatcher, `PATROL` sequencer, and FSM in `src/3_planning/amm/modules/mission_engine.lua`**

1. Require `condition_evaluator` and `hook_runner` at top of `src/3_planning/amm/modules/mission_engine.lua` (`local condition_evaluator = require("condition_evaluator")`, `local hook_runner = require("hook_runner")`).
2. Add `mission_engine.__index = mission_engine` and `mission_engine.new(opts)`:
   - Store `net`, `config`, `baseChannel`, `authority = "PILOT_PRIMARY"`, `hook_runner` (using `opts.hook_runner or hook_runner.new({ net = opts.net, redstone = opts.redstone, colors = opts.colors, on_notify = opts.on_notify })`), `defaults` (`{ cruiseSpeed = cfg.defaultSpeed or 18.0, targetAlt = cfg.defaultAlt or 150.0, acceptanceRadius = cfg.arrivalRadius or 15.0, headingMode = "AUTO" }`), `missionId = "SORTIE"`, `executionMode = "SINGLE"`, `fallbackPolicy = "RTH"`, `checkpoints = {}`, `active_index = 1`, `state = "IDLE"`, `enteredAtMs = 0`, `lastFsmState = "DISARMED"`, `lastMfd = nil`, `touchdownArmed = false`, `patrolState = nil`, `lastConditionSummary = "NONE"`.
3. Implement polymorphic `load_table(data)` and `load(filepath)` / `save(filepath)`:
   - Convert legacy `data.items` (`v1.0.0`) into `FLY_OVER` checkpoints plus a trailing `LAND_LAUNCHPAD` checkpoint when the final item has a non-empty `facilityId`, then pass through `mission_engine.validate_mission(...)`.
   - When loading from disk (`load(filepath)`), return `false, "FILE_NOT_FOUND"` if missing, `false, "FS_OPEN_ERROR"` if unreadable, `false, "PARSE_ERROR"` if JSON invalid, or `false, res.error` if validation fails (preserving `"DEFERRED_ACTION_UNSUPPORTED"`).
4. Implement FCP command dispatch table (`FCP_DISPATCHERS`) and step entry (`enter_checkpoint(self, index, now_ms)`):
   - Dispatch `CRUISE` (`FLY_OVER`, `FLY_TO`, `PATROL`), `LOITER` (`ORBIT`), `POI_HOLD` (`POI_HOLD`), `ARM`+`TAKEOFF` (`TAKEOFF_LAUNCHPAD`), `LANDING` (`LAND_LAUNCHPAD`), and `hook_runner:start_action` (`PAYLOAD_ACTION`, `REDSTONE_ACTION`).
5. Implement `PATROL` sub-waypoint stepping (`update_patrol(self, mfd_payload)`):
   - Handle `LOOP` (`1 .. N -> 1`, incrementing `completedCycles` after visiting all $N$ waypoints) and `PING_PONG` (`1 .. N .. 1` bounce, handling $N = 1$ without division/index error).
6. Implement `step_telemetry(mfd_payload, now_ms)`, `tick(now_ms)`, `on_payload_ack(packet, channel, now_ms)`, `advance(now_ms)`, `apply_abort(cp, now_ms)`, `start`, `stop`, `pause`, `resume`, `skip_next`, `goto_index` keeping every function `<= 50` lines.

- [ ] **Step 4: Run AMM unit tests and Lua syntax check**

Run:
```powershell
Set-Location c:\Users\sjmik\Desktop\Create_Aeroneutics\.worktrees\task-202-2-amm-core; python tools/run_unit_tests.py --target 3_planning/amm --clean-orphans; if ($?) { python tools/validate_lua_syntax.py }
```
Expected: PASS on all `3_planning/amm` suites (`49/49 passed`), Lua 5.2 syntax valid.

- [ ] **Step 5: Commit Task 1**

```powershell
Set-Location c:\Users\sjmik\Desktop\Create_Aeroneutics\.worktrees\task-202-2-amm-core
& "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/modules/mission_engine.lua tests/3_planning/amm/test_mission_fsm.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): add polymorphic mission loader, 9-action FCP dispatcher, and sequencer FSM (TASK-202-3)"
```

---

### Task 2: `Base+0` `MSG_MISSION_CMD` / `MSG_MISSION_ACK` Arbitration & Engine Synchronization (`c2_arbiter.lua`)

**Files:**
- Modify: `src/3_planning/amm/modules/c2_arbiter.lua:1-126`
- Modify: `tests/3_planning/amm/test_c2_arbiter.lua:90-121`

**Interfaces:**
- Consumes:
  - `mission_engine` instance from Task 1 (`:load`, `:start`, `:stop`, `:pause`, `:resume`, `:skip_next`, `:step_telemetry`, `:count`)
  - `network_manager` (`:send_mission_ack`, `:send_operator_cmd`, `:send_emergency_override`)
  - `waypoint_queue` (existing FIFO queue; `MUT-05` line preserved)
- Produces:
  - `c2_arbiter.new(queue, net, config, engine) -> arbiter`
  - `c2_arbiter:set_engine(engine)`
  - `c2_arbiter:handle_mission_cmd(packet, now_ms) -> boolean, string`
  - `c2_arbiter:handle_gcs_packet(packet, now_ms)` (routes both `MSG_OPERATOR_CMD` and `MSG_MISSION_CMD`)
  - `c2_arbiter:handle_mfd_state(packet, now_ms)` (drives `engine:step_telemetry` when engine has checkpoints, alongside legacy queue)
  - `c2_arbiter:handle_pilot_action(action, params, now_ms)` (synchronizes `authority`, `queue`, and `engine`)

- [ ] **Step 1: Write the failing unit tests in `tests/3_planning/amm/test_c2_arbiter.lua`**

Append to `tests/3_planning/amm/test_c2_arbiter.lua` (inside `describe(...)`):
```lua
    it("arbitrates Base+0 MSG_MISSION_CMD (RUN, BUSY_REJECTED, forceRestart, FILE_NOT_FOUND, DEFERRED, STOP/PAUSE/RESUME/NEXT) and sends MSG_MISSION_ACK", function()
        local mission_engine = require("mission_engine")
        local q, net, arb, tx = create_fixture()
        local eng = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        arb:set_engine(eng)

        -- Write valid and deferred mission files
        local f_ok = fs.open("missions/patrol_alpha.json", "w")
        f_ok.write(textutils.serializeJSON({
            missionId = "PATROL_ALPHA",
            checkpoints = {
                { checkpointId = "CP_01", action = "FLY_OVER", params = { targetPos = { x = 100, z = 200 }, targetAlt = 150, cruiseSpeed = 18 } },
                { checkpointId = "CP_02", action = "ORBIT", params = { targetPos = { x = 300, z = 400 }, radius = 35, direction = "CW" } },
            },
        }))
        f_ok.close()

        local f_def = fs.open("missions/runway_sortie.json", "w")
        f_def.write(textutils.serializeJSON({
            missionId = "RUNWAY_SORTIE",
            checkpoints = {
                { checkpointId = "CP_RWY", action = "TAKEOFF_RUNWAY", params = {} },
            },
        }))
        f_def.close()

        -- 1. Missing file -> FILE_NOT_FOUND
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "nonexistent_mission", executionMode = "SINGLE" },
        }, 1000)
        assert_eq(tx[#tx].payload.type, "MSG_MISSION_ACK")
        assert_eq(tx[#tx].payload.payload.status, "FILE_NOT_FOUND")

        -- 2. Deferred action -> DEFERRED_ACTION_UNSUPPORTED
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "runway_sortie", executionMode = "SINGLE" },
        }, 1100)
        assert_eq(tx[#tx].payload.type, "MSG_MISSION_ACK")
        assert_eq(tx[#tx].payload.payload.status, "DEFERRED_ACTION_UNSUPPORTED")

        -- 3. Valid RUN -> ACCEPTED, engine EN_ROUTE at index 1
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "patrol_alpha", executionMode = "SINGLE", forceRestart = false },
        }, 1200)
        local ack_run = tx[#tx].payload.payload
        assert_eq(ack_run.status, "ACCEPTED")
        assert_eq(ack_run.missionId, "PATROL_ALPHA")
        assert_eq(ack_run.missionState, "EN_ROUTE")
        assert_eq(ack_run.activeIndex, 1)
        assert_eq(ack_run.totalCheckpoints, 2)

        -- 4. Duplicate RUN while EN_ROUTE with forceRestart = false -> BUSY_REJECTED
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "patrol_alpha", forceRestart = false },
        }, 1300)
        assert_eq(tx[#tx].payload.payload.status, "BUSY_REJECTED")

        -- 5. NEXT -> advances to index 2 and replies ACCEPTED
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "NEXT" },
        }, 1400)
        assert_eq(tx[#tx].payload.payload.status, "ACCEPTED")
        assert_eq(tx[#tx].payload.payload.activeIndex, 2)

        -- 5b. RUN while EN_ROUTE with forceRestart = true -> resets to index 1 and replies ACCEPTED
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "patrol_alpha", forceRestart = true },
        }, 1450)
        assert_eq(tx[#tx].payload.payload.status, "ACCEPTED")
        assert_eq(tx[#tx].payload.payload.activeIndex, 1)

        -- 6. PAUSE / RESUME / STOP
        arb:handle_gcs_packet({ ver = "1.9.5", type = "MSG_MISSION_CMD", payload = { action = "PAUSE" } }, 1500)
        assert_eq(eng.state, "SUSPENDED")
        arb:handle_gcs_packet({ ver = "1.9.5", type = "MSG_MISSION_CMD", payload = { action = "RESUME" } }, 1600)
        assert_eq(eng.state, "EN_ROUTE")
        arb:handle_gcs_packet({ ver = "1.9.5", type = "MSG_MISSION_CMD", payload = { action = "STOP" } }, 1700)
        assert_eq(eng.state, "ABORTED")
        assert_eq(tx[#tx].payload.payload.missionState, "ABORTED")

        fs.delete("missions/patrol_alpha.json")
        fs.delete("missions/runway_sortie.json")
    end)
```

- [ ] **Step 2: Run the unit test to verify it fails**

Run:
```powershell
Set-Location c:\Users\sjmik\Desktop\Create_Aeroneutics\.worktrees\task-202-2-amm-core; python tools/run_unit_tests.py --target 3_planning/amm --filter c2_arbiter --clean-orphans
```
Expected: FAIL (`attempt to call method 'set_engine' (a nil value)`).

- [ ] **Step 3: Implement `MSG_MISSION_CMD` arbitration and `mission_engine` synchronization in `src/3_planning/amm/modules/c2_arbiter.lua`**

1. Update `c2_arbiter.new(queue, net, config, engine)` to store `self.engine = engine or (cfg and cfg.engine)` and add `c2_arbiter:set_engine(engine)`.
2. Preserve the exact `MUT-05` lines in `c2_arbiter:handle_gcs_packet(packet, now_ms)`:
   - When `packet.type == "MSG_MISSION_CMD"`, return `self:handle_mission_cmd(packet, now_ms)`.
   - When `p.authority == "GCS_OVERRIDE"`, keep `if self.queue and self.queue.state == "EN_ROUTE" then self.queue.state = "SUSPENDED" end`, and also pause `self.engine` if `self.engine and self.engine.state == "EN_ROUTE"`.
3. Implement `c2_arbiter:handle_mission_cmd(packet, now_ms)`:
   - Build and send `MSG_MISSION_ACK` via `self.net:send_mission_ack(...)` for `RUN` (checking `BUSY_REJECTED`, optional `missionName` load errors `"FILE_NOT_FOUND"`, `"DEFERRED_ACTION_UNSUPPORTED"`, `"INVALID_CMD"`, and `engine:start`), `STOP`, `PAUSE`, `RESUME`, `NEXT`, and unknown actions (`"INVALID_CMD"`).
4. In `handle_mfd_state(packet, now_ms)` and `handle_pilot_action(action, params, now_ms)`:
   - When `self.engine` has checkpoints (`self.engine:count() > 0`), drive `self.engine:step_telemetry(p, now_ms)` and synchronize `HOLD`/`RTH`/`LAND`/`ESTOP`/`PAUSE`/`RESUME` with `self.engine`.

- [ ] **Step 4: Run AMM unit tests and mutation test check (`MUT-04`, `MUT-05`)**

Run:
```powershell
Set-Location c:\Users\sjmik\Desktop\Create_Aeroneutics\.worktrees\task-202-2-amm-core; python tools/run_unit_tests.py --target 3_planning/amm --clean-orphans; if ($?) { python tools/validate_lua_syntax.py }
```
Expected: PASS on all `3_planning/amm` tests (`50/50 passed`), Lua 5.2 syntax valid.

- [ ] **Step 5: Commit Task 2**

```powershell
Set-Location c:\Users\sjmik\Desktop\Create_Aeroneutics\.worktrees\task-202-2-amm-core
& "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/modules/c2_arbiter.lua tests/3_planning/amm/test_c2_arbiter.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): add Base+0 MSG_MISSION_CMD arbitration and engine C2 sync (TASK-202-3)"
```

---

### Task 3: Headless Mode (`config.headless`), 5Hz Timer Tick & Zone 3 Event Dispatch (`main.lua`)

**Files:**
- Modify: `src/3_planning/amm/main.lua:1-144`
- Modify: `tests/3_planning/amm/test_main_loop.lua:1-88`
- Modify: `TASK.md:71`
- Modify: `.agent/memory/workspace-root.md`

**Interfaces:**
- Consumes:
  - `mission_engine` (Task 1), `c2_arbiter` (Task 2), `network_manager` (Task 202-2)
- Produces:
  - `main.load_config(path)` (includes `headless = false`)
  - `main.process_event(app, ev, p1, p2, p3, p4, p5)` (ticks `app.engine:tick()` on 5Hz timer, skips `ui_renderer` when `app.config.headless == true`, routes `Base+20~29` `modem_message` to `app.engine:on_payload_ack`)
  - Updated `TASK-202-3` (`[x]`) in `TASK.md` and appended milestone entry in `.agent/memory/workspace-root.md`

- [ ] **Step 1: Write the failing unit tests in `tests/3_planning/amm/test_main_loop.lua`**

Append to `tests/3_planning/amm/test_main_loop.lua` (inside `describe(...)`):
```lua
    it("suppresses TUI rendering in headless mode while ticking hooks/conditions and routing Zone 3 ACKs", function()
        local main_mod = require("main")
        local mission_engine = require("mission_engine")
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local rs = mock.redstone()
        local q = waypoint_queue.new({ defaultAlt = 150, defaultSpeed = 18, arrivalRadius = 15 })
        local eng = mission_engine.new({ net = net, redstone = rs, colors = colors, config = { baseChannel = 10000 } })
        local arb = c2_arbiter.new(q, net, { baseChannel = 10000 }, eng)
        local inp = input_handler.new()

        local blit_calls = 0
        local spy_term = {
            setCursorPos = function() end,
            blit = function() blit_calls = blit_calls + 1 end,
        }

        assert_true(eng:load_table({
            missionId = "UAV_HEADLESS_SORTIE",
            checkpoints = {
                {
                    checkpointId = "CP_PAYLOAD",
                    action = "PAYLOAD_ACTION",
                    params = { channelOffset = 20, command = "SCAN", expectedStatus = "DONE" },
                    onEnter = { { type = "REDSTONE_PULSE", side = "top", durationMs = 400 } },
                },
                {
                    checkpointId = "CP_HOLD",
                    action = "ORBIT",
                    params = { targetPos = { x = 100, z = 100 }, durationSec = 5 },
                },
            },
        }))

        local app = {
            config = { domainId = "AIRCRAFT_01", baseChannel = 10000, headless = true },
            queue = q,
            net = net,
            engine = eng,
            arbiter = arb,
            input = inp,
            screen_buf = ui_renderer.create_buffer(51, 19),
            render_timer = 77,
            term_obj = spy_term,
            now_ms = 1000,
        }

        -- Remote RUN command arrives on Base+0 via modem_message
        main_mod.process_event(app, "modem_message", "back", 10000, 10000, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1, type = "MSG_MISSION_CMD", time = 1000,
            payload = { action = "RUN", executionMode = "SINGLE" },
        }, 10)
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.active_index, 1)
        assert_true(rs.getOutput("top"))
        assert_true(m.isOpen(10020))

        -- 5Hz timer fires at 1500ms -> expires pulse without calling term.blit in headless mode
        app.now_ms = 1500
        main_mod.process_event(app, "timer", 77)
        assert_eq(blit_calls, 0)
        assert_false(rs.getOutput("top"))

        -- Zone 3 MSG_PAYLOAD_ACK arrives on Base+20 (10020) -> closes 10020 and advances to CP_HOLD (index 2)
        app.now_ms = 1600
        main_mod.process_event(app, "modem_message", "back", 10020, 10020, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 2, type = "MSG_PAYLOAD_ACK", time = 1600,
            payload = { checkpointId = "CP_PAYLOAD", command = "SCAN", status = "DONE" },
        }, 1)
        assert_false(m.isOpen(10020))
        assert_eq(eng.active_index, 2)
    end)
```

- [ ] **Step 2: Run the unit test to verify it fails**

Run:
```powershell
Set-Location c:\Users\sjmik\Desktop\Create_Aeroneutics\.worktrees\task-202-2-amm-core; python tools/run_unit_tests.py --target 3_planning/amm --filter main_loop --clean-orphans
```
Expected: FAIL (`eng.state` remains `"IDLE"` and `blit_calls > 0` because `main.lua` does not yet wire `engine`, `headless`, or Zone 3 `modem_message`).

- [ ] **Step 3: Implement headless mode, 5Hz engine tick, and Zone 3 event dispatch in `src/3_planning/amm/main.lua`**

1. Require `mission_engine` in `src/3_planning/amm/main.lua` and add `headless = false` to `load_config` defaults.
2. In `process_event(app, ev, p1, p2, p3, p4, p5)`:
   - Compute `now_ms = app.now_ms or (os.epoch and os.epoch("utc")) or (os.time() * 1000)`.
   - On `ev == "timer" and p1 == app.render_timer`:
     - Re-arm `app.render_timer = os.startTimer(0.2)`.
     - If `app.engine` then call `app.engine:tick(now_ms)`.
     - Only call `ui_renderer.render_screen(...)` and `ui_renderer.flush_buffer(app.screen_buf, app.term_obj or term)` when `not (app.config and app.config.headless == true)`.
   - On `ev == "modem_message"`:
     - `chan == base + 3`: `app.arbiter:handle_mfd_state(pkt, now_ms)`
     - `chan == base + 0`: `app.arbiter:handle_gcs_packet(pkt, now_ms)`
     - `app.net:is_payload_channel(chan)` and `app.engine`: `app.engine:on_payload_ack(pkt, chan, now_ms)`
3. In `execute_cli_command(app, cmd)` and `main_loop(config_path)`:
   - Instantiate `engine = mission_engine.new({ net = net, config = cfg })` and pass to `c2_arbiter.new(queue, net, cfg, engine)`.
   - Sync `save`/`load`/`clear`/`pause`/`resume` with `app.engine` when present, and auto-start `cfg.autoStartMission` if configured.

- [ ] **Step 4: Run the full verification suite across unit, E2E, mutation, harness, manifest, specs, and Lua syntax**

Run:
```powershell
Set-Location c:\Users\sjmik\Desktop\Create_Aeroneutics\.worktrees\task-202-2-amm-core; python tools/run_unit_tests.py --require-tests --clean-orphans; if ($?) { python tools/run_e2e_tests.py --clean-orphans }; if ($?) { python tools/run_mutation_tests.py }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python tools/verify_all_specs.py --check-readmes }; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/validate_lua_syntax.py }
```
Expected:
- `run_unit_tests.py`: 12 targets PASS (`355/355 PASS`, `3_planning/amm` `54/54 passed`)
- `run_e2e_tests.py`: 7 scenarios `8/8 PASS`
- `run_mutation_tests.py`: `25/25 KILLED (100.0%)` (including `MUT-04`, `MUT-05`)
- `tests/harness`: `82 tests OK`
- `verify_manifest_sync.py`: `0 Errors, 0 Warnings`
- `verify_all_specs.py --check-readmes`: `0 Errors, 0 Warnings`
- `verify_spec_status.py`: PASS (`9 Implemented, 6 Approved`)
- `validate_lua_syntax.py`: `129/129 PASS`

- [ ] **Step 5: Sync `TASK.md` (`TASK-202-3` -> `[x]`) and `.agent/memory/workspace-root.md`, verify context docs, and commit Task 3**

1. Update `TASK.md:71` to `- [x] **TASK-202-3**` with completion date and test summary.
2. Prepend a `## 2026-11-11 — ... (TASK-202-3)` entry in `.agent/memory/workspace-root.md`.
3. Run:
   ```powershell
   Set-Location c:\Users\sjmik\Desktop\Create_Aeroneutics\.worktrees\task-202-2-amm-core; python tools/verify_context_docs.py
   ```
   Expected: `[PASS] context docs: 0 findings`
4. Commit:
   ```powershell
   Set-Location c:\Users\sjmik\Desktop\Create_Aeroneutics\.worktrees\task-202-2-amm-core
   & "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/main.lua tests/3_planning/amm/test_main_loop.lua TASK.md .agent/memory/workspace-root.md
   & "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): wire headless mode, 5Hz engine tick, and Zone 3 event routing in main (TASK-202-3)"
   ```
