# AMM 13-Action Checkpoint Schema, Condition Evaluator, 0-Tick Hook Runner & Zone 3 Bus (TASK-202-2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execute implementation in an isolated git worktree (`using-git-worktrees`) branched from `main`.

**Goal:** Build the foundational AMM mission core components in `src/3_planning/amm/modules/` covering the 13-action checkpoint schema (9 active + 4 deferred), the 12-type `completeWhen`/`abortWhen` evaluator (`condition_evaluator.lua`), the 0-tick non-blocking lifecycle hook & device action runner (`hook_runner.lua`), and dynamic Zone 3 (`Base+20~29`) payload channel lifecycle + `MSG_MISSION_ACK` codec in `network_manager.lua`.

**Architecture:** `mission_engine.lua` (Task 1 schema layer) defines the 13-action taxonomy, `defaults` inheritance, parameter sanitization, and `"DEFERRED_ACTION_UNSUPPORTED"` validation guard; `network_manager.lua` adds bounded Zone 3 (`Base+20..29`) channel open/close/transmit tracking (`openPayloadChannels`) alongside `MSG_MISSION_ACK` encoding while keeping `bind_modem()` opening only `Base+0` and `Base+3`. `condition_evaluator.lua` implements pure stateless evaluators across all 12 condition types (`ALL`/`ANY`), empty-group safety, missing/boot telemetry guards, and per-action default `completeWhen` resolution with zero circular `require` dependency on `mission_engine`. `hook_runner.lua` orchestrates `onEnter`/`onExit`/`onAbort` hooks, a non-blocking `activePulses` deadline queue using Lua 5.2 `bit32`, `REDSTONE_ACTION` (`EMIT`/`WAIT_INPUT`), and `PAYLOAD_ACTION` dynamic Zone 3 open-send-ACK-close cycles, while registering all three new `.lua` files in `manifest.lua` so 3-way manifest sync stays clean at every commit.

**Tech Stack:** CC:Tweaked 1.109+ Lua 5.2 (Cobalt VM, `bit32`), CraftOS-PC Headless Unit Test Runner (`tools/run_unit_tests.py`), Multi-Node E2E Simulation Harness (`tools/run_e2e_tests.py`), Mutation Test Runner (`tools/run_mutation_tests.py`), Python 3.10+ Manifest/Syntax/Context Verifiers (`tools/verify_manifest_sync.py`, `tools/validate_lua_syntax.py`, `tools/verify_context_docs.py`, `tests/harness/`).

**Spec:**
- Primary Specification: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v1.1.0 Approved` — remains `Approved` after `TASK-202-2`; promoted to `Implemented` only at `TASK-202-5` after `TASK-202-3` & `TASK-202-4`)
- Master ICD: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.26.0 Approved` — Interface I-6 `MSG_MISSION_CMD`/`MSG_MISSION_ACK`, Interface I-11 Zone 3 `Base+20~29` `MSG_PAYLOAD_REQ`/`MSG_PAYLOAD_ACK`)
- Roadmap SSOT: `TASK.md` (`TASK-202-2`)

## Global Constraints

- **Lua 5.2 Cobalt Runtime (`.agent/rules/cc-tweaked-runtime.md`)**: Use `bit32` (`bit32.band`, `bit32.bor`, `bit32.bnot`) instead of Lua 5.3+ bitwise operators (`&`, `|`, `~`, `<<`, `>>`); never use `//`, `getfenv`, `setfenv`, `os.execute`, `io.popen`, `os.exit`, `os.remove`, or `os.rename`.
- **Non-Blocking Loop Contract (`AMM_PROGRAM_SPECIFICATION.md` §1.3, §6.4, §9)**: Zero calls to `sleep()`, `os.pullEvent()`, or `os.pullEventRaw()` inside any AMM schema, condition, hook, or network module (`runner_lib.lua` actively aborts unit tests with `EVENT_SWALLOW_VIOLATION` if called).
- **Single-Function Complexity (`AMM_PROGRAM_SPECIFICATION.md` §9, §10)**: Keep every Lua function at `<= 50` lines via dispatch tables (`ACTION_VALIDATORS`, `CONDITION_EVALUATORS`, `HOOK_HANDLERS`).
- **Valkyrien Skies Mod Ban (`.agent/rules/domain-aeronautics.md`)**: Zero prohibited mod identifiers (`valkyrien`, `vs2`, `cc_vs`, `ship` peripheral, `kontraption:`).
- **Mutation Target Line & Legacy API Preservation (`tools/run_mutation_tests.py`, `tests/3_planning/amm/`)**: Do not alter `src/3_planning/amm/modules/waypoint_queue.lua` (`MUT-04`: `if d2d <= rad then`), `src/3_planning/amm/modules/c2_arbiter.lua` (`MUT-05`: `self.queue.state = "SUSPENDED"`), or existing `network_manager.lua` methods (`bind_modem` opening only `+0`/`+3`, `encode_envelope`, `decode_envelope`, `send_operator_cmd`, `send_emergency_override`), and keep `src/3_planning/amm/config/amm_config.json` unchanged (`test_harness_setup.lua`).
- **Zero-Fallback Protocol Standard (`AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` §1.3)**: Parse only canonical v1.1.0 / ICD v1.9.5 keys (`cond.timeout`, `mfd.fsmState == "DISARMED"`, `payload.status`, `params.commandPayload`); never write dual-key fallbacks.
- **No Circular Lua `require`**: `TASK-202-3` will `require("condition_evaluator")` and `require("hook_runner")` from `mission_engine.lua`, so `condition_evaluator.lua` and `hook_runner.lua` must never `require("mission_engine")`.
- **Manifest 3-Way Parity (`tools/verify_manifest_sync.py`)**: Register each newly created `src/3_planning/amm/modules/*.lua` file in `src/0_development/installer/modules/manifest.lua` in the same task commit so `verify_manifest_sync.py` and `tests/harness` remain at `0 Errors, 0 Warnings`.

## Review Focus

1. **Out-of-Range or Core-Hijacking Zone 3 Channel/Offset (`channelOffset` outside `20..29`, `targetChannel` in `Base+0..19` or `Base+30..39`, float/`NaN`/`Inf`)**: Any non-integer offset `< 20` or `> 29`, negative offset, `NaN`, or channel targeting Zone 1 (`Base+0..9`), Zone 2 (`Base+10..19`), or Zone 4 (`Base+30..39`) must be rejected with `"INVALID_ZONE3_CHANNEL"` across `network_manager`, `mission_engine.validate_checkpoint`, and `hook_runner` before touching `modem.open`/`modem.close`/`modem.transmit` (pinned by tests in Task 1 `test_network_manager.lua` and `test_checkpoint_schema.lua`).
2. **Orphan Redstone Outputs & Leaked Zone 3 Channels on Mid-Step Stop, Abort, or Modem Error**: Calling `hook_runner:cleanup()` or `clear_step_state()` while a `REDSTONE_PULSE` is still active (`nowMs < expireMs`) or while `PAYLOAD_ACTION` holds a Zone 3 channel open waiting for `MSG_PAYLOAD_ACK` must immediately deactivate all scheduled pulse outputs, close all tracked Zone 3 channels (never closing `Base+0`/`+3`), and clear pending ACK state (pinned by tests in Task 1 `test_network_manager.lua` and Task 3 `test_hook_runner.lua`).
3. **False Triggers on Empty Condition Lists, Missing Boot Telemetry, Stale Payload ACKs, or Pre-Approach `DISARMED` State**: `evaluate_group` must return `false` when `conditions == {}` under default `logic = "ALL"` (never vacuous truth), return `false` for `FUEL_LEVEL_BELOW` / `PROXIMITY_*` / `ALTITUDE_REACHED` when `mfd == nil` at boot, reject a `PAYLOAD_RESP_MATCH` ACK whose `checkpointId` does not match the active checkpoint, and hold `FACILITY_TOUCHDOWN == false` while `ctx.touchdownArmed == false` (pinned by tests in Task 2 `test_condition_evaluator.lua`).
4. **Deferred 4 Actions Bypassing Validation (`TAKEOFF_RUNWAY`, `LAND_RUNWAY`, `DOCK_ARM`, `UNDOCK_ARM`)**: Calling `mission_engine.validate_checkpoint`, `condition_evaluator.resolve_default_complete`, or `hook_runner:start_action` with any of the 4 deferred actions must return `false`/`nil`, `"DEFERRED_ACTION_UNSUPPORTED"` without emitting RF packets or modifying redstone outputs (pinned by tests in Task 1 `test_checkpoint_schema.lua`, Task 2 `test_condition_evaluator.lua`, and Task 3 `test_hook_runner.lua`).
5. **Dual-Mode Redstone & Bundled Bitmask / Overlapping Pulse Collisions**: Expiring a bundled `REDSTONE_PULSE` on `{ side = "top", color = colors.red }` must clear only the `red` bit via `bit32.band(cur, bit32.bnot(mask))` while preserving `colors.blue`, extending an already-active pulse on the same `(side, color)` must keep output high until the latest `expireMs`, analog `level` must not be overwritten by `setOutput(side, true)`, and `REDSTONE_INPUT_HIGH` must inspect both `getAnalogInput` and digital `getInput` (pinned by tests in Task 2 `test_condition_evaluator.lua` and Task 3 `test_hook_runner.lua`).

---

## File Structure

- Create: `src/3_planning/amm/modules/mission_engine.lua` — Task 1 schema layer (`ACTIVE_ACTIONS`, `DEFERRED_ACTIONS`, `ACTION_TAXONOMY`, `is_action_supported`, `is_action_deferred`, `normalize_checkpoint`, `validate_checkpoint`, `validate_mission`); left cleanly extensible for `TASK-202-3` file loader & FSM.
- Modify: `src/3_planning/amm/modules/network_manager.lua:6-92` — Add `openPayloadChannels` state, `is_payload_channel`, `resolve_payload_channel`, `open_payload_channel`, `close_payload_channel`, `close_all_payload_channels`, `send_payload_req`, and `send_mission_ack`.
- Create: `src/3_planning/amm/modules/condition_evaluator.lua` — 12 condition types, `ALL`/`ANY` group combinators, empty-list safety, default `completeWhen` auto-resolution, `should_arm_touchdown`, `evaluate_checkpoint`, `format_progress`.
- Create: `src/3_planning/amm/modules/hook_runner.lua` — 0-tick `execute_hooks` (`REDSTONE_SET`, `REDSTONE_PULSE`, `ZONE3_PAYLOAD_CMD`, `NOTIFY_OPERATOR`), non-blocking `tick(now_ms)` pulse deadline queue, `start_action` (`REDSTONE_ACTION`, `PAYLOAD_ACTION`), `on_payload_ack`, `clear_step_state`, `cleanup`.
- Modify: `src/0_development/installer/modules/manifest.lua:542-552` — Register `mission_engine.lua`, `condition_evaluator.lua`, and `hook_runner.lua` under `manifest.MODULES.amm.files`.
- Create: `tests/3_planning/amm/test_checkpoint_schema.lua` — Unit tests for 13-action schema validation, defaults inheritance, `NaN`/out-of-range guards, and deferred 4 action rejection.
- Modify: `tests/3_planning/amm/test_network_manager.lua:1-81` — Unit tests for Zone 3 (`Base+20~29`) channel validation, dynamic open/close/close-all isolation, `MSG_PAYLOAD_REQ`, and `MSG_MISSION_ACK`.
- Create: `tests/3_planning/amm/test_condition_evaluator.lua` — Unit tests for all 12 condition types, `ALL`/`ANY`, empty list, boot `nil`, stale ACK, touchdown arming, default resolution, and `format_progress`.
- Create: `tests/3_planning/amm/test_hook_runner.lua` — Unit tests for 0-tick hooks, non-blocking `REDSTONE_PULSE` deadline/overlap/bundled-preservation/cleanup, `REDSTONE_ACTION`, and `PAYLOAD_ACTION` Zone 3 open-ACK-close lifecycle.
- Create: `tests/3_planning/amm/test_mission_core_integration.lua` — Closed-loop cross-module integration tests connecting `mission_engine` schema -> `hook_runner` -> `network_manager` -> `condition_evaluator` across `ORBIT`, `PAYLOAD_ACTION`, and `REDSTONE_ACTION` lifecycles.

---

### Task 1: 13-Action Checkpoint Schema Layer (`mission_engine.lua`) & Zone 3 Bus (`network_manager.lua`)

**Files:**
- Create: `src/3_planning/amm/modules/mission_engine.lua`
- Modify: `src/3_planning/amm/modules/network_manager.lua:6-25,74-92`
- Modify: `src/0_development/installer/modules/manifest.lua:542-552`
- Create: `tests/3_planning/amm/test_checkpoint_schema.lua`
- Modify: `tests/3_planning/amm/test_network_manager.lua:80-81`

**Interfaces:**
- Consumes:
  - `amm_config` (`{ domainId, baseChannel, defaultAlt, defaultSpeed, arrivalRadius }`)
- Produces:
  - `mission_engine.DEFERRED_ERROR` (`"DEFERRED_ACTION_UNSUPPORTED"`)
  - `mission_engine.ACTIVE_ACTIONS` (9 keys), `mission_engine.DEFERRED_ACTIONS` (4 keys), `mission_engine.ACTION_TAXONOMY`
  - `mission_engine.is_action_supported(action) -> boolean`
  - `mission_engine.is_action_deferred(action) -> boolean`
  - `mission_engine.validate_checkpoint(cp, opts) -> boolean, string|nil`
  - `mission_engine.normalize_checkpoint(raw_cp, defaults, index, opts) -> table|nil, string|nil`
  - `mission_engine.validate_mission(mission_tbl, opts) -> boolean, table|string`
  - `network_manager:is_payload_channel(channel) -> boolean`
  - `network_manager:resolve_payload_channel(channel_or_offset) -> integer|nil, string|nil`
  - `network_manager:open_payload_channel(channel_or_offset) -> boolean, integer|string`
  - `network_manager:close_payload_channel(channel_or_offset) -> boolean, integer|string`
  - `network_manager:close_all_payload_channels() -> integer`
  - `network_manager:send_payload_req(channel_or_offset, checkpointId, command, params, opts) -> boolean, integer|string`
  - `network_manager:send_mission_ack(ack_payload) -> boolean, string|nil`

- [ ] **Step 1: Write the failing unit tests in `tests/3_planning/amm/test_checkpoint_schema.lua` and `tests/3_planning/amm/test_network_manager.lua`**

Create `tests/3_planning/amm/test_checkpoint_schema.lua`:
```lua
-- tests/3_planning/amm/test_checkpoint_schema.lua
local mission_engine = require("mission_engine")

describe("AMM 13-Action Checkpoint Schema and Validation", function()
    it("classifies 9 active actions and 4 deferred actions matching spec v1.1.0", function()
        local active = {
            "FLY_OVER", "FLY_TO", "ORBIT", "PATROL", "POI_HOLD",
            "TAKEOFF_LAUNCHPAD", "LAND_LAUNCHPAD", "PAYLOAD_ACTION", "REDSTONE_ACTION",
        }
        local deferred = { "TAKEOFF_RUNWAY", "LAND_RUNWAY", "DOCK_ARM", "UNDOCK_ARM" }

        for _, act in ipairs(active) do
            assert_true(mission_engine.is_action_supported(act), act .. " must be active")
            assert_false(mission_engine.is_action_deferred(act), act .. " must not be deferred")
        end
        for _, act in ipairs(deferred) do
            assert_false(mission_engine.is_action_supported(act), act .. " must not be active")
            assert_true(mission_engine.is_action_deferred(act), act .. " must be deferred")
            local cp, err = mission_engine.normalize_checkpoint({ checkpointId = "CP_DEF", action = act, params = {} })
            assert_nil(cp)
            assert_eq(err, "DEFERRED_ACTION_UNSUPPORTED")
        end

        local bad_cp, bad_err = mission_engine.normalize_checkpoint({ action = "TELEPORT_NOW", params = {} })
        assert_nil(bad_cp)
        assert_eq(bad_err, "UNKNOWN_ACTION")
    end)

    it("inherits mission defaults across active actions while preserving FLY_TO 5m default precision", function()
        local defaults = { cruiseSpeed = 20.0, targetAlt = 140.0, acceptanceRadius = 15.0, headingMode = "AUTO" }

        local cp_over, err1 = mission_engine.normalize_checkpoint({
            action = "FLY_OVER",
            params = { targetPos = { x = 450, z = -1200 } },
        }, defaults, 1)
        assert_nil(err1)
        assert_eq(cp_over.checkpointId, "CP_01")
        assert_eq(cp_over.params.targetAlt, 140.0)
        assert_eq(cp_over.params.cruiseSpeed, 20.0)
        assert_eq(cp_over.params.acceptanceRadius, 15.0)
        assert_eq(cp_over.params.headingMode, "AUTO")

        local cp_to, err2 = mission_engine.normalize_checkpoint({
            checkpointId = "CP_PRECISE",
            action = "FLY_TO",
            params = { targetPos = { x = 100, z = 200 } },
        }, defaults, 2)
        assert_nil(err2)
        assert_eq(cp_to.params.acceptanceRadius, 5.0)

        local cp_orb, err3 = mission_engine.normalize_checkpoint({
            action = "ORBIT",
            params = { targetPos = { x = 0, z = 0 } },
        }, defaults, 3)
        assert_nil(err3)
        assert_eq(cp_orb.params.radius, 30.0)
        assert_eq(cp_orb.params.direction, "CW")

        local cp_poi, err4 = mission_engine.normalize_checkpoint({
            action = "POI_HOLD",
            params = { targetPos = { x = 10, z = 10 }, poiPos = { x = 50, y = 64, z = 10 } },
        }, defaults, 4)
        assert_nil(err4)
        assert_eq(cp_poi.params.headingMode, "POI")
    end)

    it("rejects malformed ORBIT, PATROL, POI_HOLD, PAYLOAD_ACTION, and REDSTONE_ACTION inputs cleanly", function()
        local cases = {
            { cp = { action = "FLY_OVER", params = { targetPos = { x = 0/0, z = 0 } } }, err = "INVALID_TARGET_POS" },
            { cp = { action = "ORBIT", params = { targetPos = { x = 0, z = 0 }, radius = -5 } }, err = "INVALID_ORBIT_RADIUS" },
            { cp = { action = "ORBIT", params = { targetPos = { x = 0, z = 0 }, direction = "UP" } }, err = "INVALID_ORBIT_DIRECTION" },
            { cp = { action = "PATROL", params = { waypoints = {} } }, err = "INVALID_PATROL_WAYPOINTS" },
            { cp = { action = "POI_HOLD", params = { targetPos = { x = 0, z = 0 } } }, err = "MISSING_POI_POS" },
            { cp = { action = "PAYLOAD_ACTION", params = { channelOffset = 19, command = "DROP" } }, err = "INVALID_ZONE3_CHANNEL" },
            { cp = { action = "PAYLOAD_ACTION", params = { channelOffset = 30, command = "DROP" } }, err = "INVALID_ZONE3_CHANNEL" },
            { cp = { action = "PAYLOAD_ACTION", params = { targetChannel = 10000, command = "DROP" } }, err = "INVALID_ZONE3_CHANNEL" },
            { cp = { action = "REDSTONE_ACTION", params = { mode = "BLINK", side = "top" } }, err = "INVALID_REDSTONE_MODE" },
            { cp = { action = "REDSTONE_ACTION", params = { mode = "EMIT", side = "diagonal" } }, err = "INVALID_REDSTONE_SIDE" },
        }
        for _, tc in ipairs(cases) do
            local ok, res_or_err = mission_engine.normalize_checkpoint(tc.cp, nil, 1, { baseChannel = 10000 })
            assert_nil(ok, "Expected rejection for " .. tc.err)
            assert_eq(res_or_err, tc.err)
        end
    end)

    it("validates a full v1.1.0 mission definition and stops on first deferred checkpoint", function()
        local ok, res = mission_engine.validate_mission({
            missionId = "SORTIE_01",
            defaults = { targetAlt = 120.0, cruiseSpeed = 16.0 },
            checkpoints = {
                { action = "TAKEOFF_LAUNCHPAD", params = { facilityId = "PAD_01" } },
                { action = "TAKEOFF_RUNWAY", params = {} },
            },
        }, { baseChannel = 10000 })
        assert_false(ok)
        assert_eq(res.error, "DEFERRED_ACTION_UNSUPPORTED")
        assert_eq(res.index, 2)
    end)
end)
```

Append to `tests/3_planning/amm/test_network_manager.lua` (inside `describe(...)`):
```lua
    it("enforces Zone 3 (Base+20..29) bounds and manages dynamic channel open/close without closing Base+0/+3", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        assert_true(m.isOpen(10000))
        assert_true(m.isOpen(10003))
        assert_false(m.isOpen(10020))

        local invalid_inputs = { -1, 0, 3, 19, 30, 20.5, 0/0, 9999, 10000, 10010, 10030, "20" }
        for _, bad in ipairs(invalid_inputs) do
            local ch, err = net:resolve_payload_channel(bad)
            assert_nil(ch, "Should reject invalid Zone 3 selector: " .. tostring(bad))
            assert_eq(err, "INVALID_ZONE3_CHANNEL")
            local ok_open, err_open = net:open_payload_channel(bad)
            assert_false(ok_open)
            assert_eq(err_open, "INVALID_ZONE3_CHANNEL")
        end

        local ok_o, ch20 = net:open_payload_channel(20)
        assert_true(ok_o)
        assert_eq(ch20, 10020)
        assert_true(m.isOpen(10020))

        local ok_tx, tx_ch = net:send_payload_req(20, "CP_04", "RELEASE_BAY", { bayId = 1 }, { keepOpen = true })
        assert_true(ok_tx)
        assert_eq(tx_ch, 10020)
        assert_eq(#m._transmitted, 1)
        assert_eq(m._transmitted[1].tx, 10020)
        assert_eq(m._transmitted[1].pkt.type, "MSG_PAYLOAD_REQ")
        assert_eq(m._transmitted[1].pkt.payload.replyChannel, 10020)
        assert_eq(m._transmitted[1].pkt.payload.checkpointId, "CP_04")
        assert_true(m.isOpen(10020))

        net:open_payload_channel(10025)
        assert_true(m.isOpen(10025))
        local closed = net:close_all_payload_channels()
        assert_eq(closed, 2)
        assert_false(m.isOpen(10020))
        assert_false(m.isOpen(10025))
        assert_true(m.isOpen(10000))
        assert_true(m.isOpen(10003))
    end)

    it("encodes and transmits MSG_MISSION_ACK on Base+0", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10040 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local ok = net:send_mission_ack({
            action = "RUN",
            status = "ACCEPTED",
            missionId = "PATROL_ALPHA",
            missionState = "EN_ROUTE",
            activeIndex = 1,
            totalCheckpoints = 4,
        })
        assert_true(ok)
        assert_eq(m._transmitted[1].tx, 10040)
        assert_eq(m._transmitted[1].pkt.type, "MSG_MISSION_ACK")
        assert_eq(m._transmitted[1].pkt.payload.status, "ACCEPTED")
        assert_eq(m._transmitted[1].pkt.payload.missionId, "PATROL_ALPHA")
    end)
```

- [ ] **Step 2: Run the AMM unit tests to confirm they fail**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --clean-orphans
```
Expected: FAIL (`module 'mission_engine' not found` in `test_checkpoint_schema.lua`, missing Zone 3/`send_mission_ack` methods in `test_network_manager.lua`).

- [ ] **Step 3: Implement `mission_engine.lua` schema layer, `network_manager.lua` Zone 3 + `MSG_MISSION_ACK`, and register `mission_engine.lua` in `manifest.lua`**

1. **`src/3_planning/amm/modules/mission_engine.lua`**:
   - Define `mission_engine.DEFERRED_ERROR = "DEFERRED_ACTION_UNSUPPORTED"`, `ACTIVE_ACTIONS` (9 keys), `DEFERRED_ACTIONS` (4 keys), `ACTION_TAXONOMY` (13 actions mapped to `{ domain, status }`), and `VALID_SIDES` (`top`, `bottom`, `left`, `right`, `front`, `back`).
   - Implement `is_finite(n)` helper (`type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge`) and `is_zone3_spec(p, base_channel)` helper rejecting non-integer, out-of-range offsets (`< 20` or `> 29`), and channels outside `[base + 20, base + 29]` (or `(ch % 40) < 20 or (ch % 40) > 29` when `base_channel` is omitted and `ch >= 10000`).
   - Implement dispatch table `ACTION_VALIDATORS` with per-action functions (`<= 30` lines each) checking required fields and finite numbers (`FLY_OVER`, `FLY_TO`, `ORBIT`, `PATROL`, `POI_HOLD`, `TAKEOFF_LAUNCHPAD`, `LAND_LAUNCHPAD`, `PAYLOAD_ACTION`, `REDSTONE_ACTION`).
   - Implement `mission_engine.is_action_supported(action)`, `mission_engine.is_action_deferred(action)`, `mission_engine.validate_checkpoint(cp, opts)`, `mission_engine.normalize_checkpoint(raw_cp, defaults, index, opts)`, and `mission_engine.validate_mission(mission_tbl, opts)` (keeping `normalize_checkpoint` copying `defaults` shallowly into `params`: `targetAlt`, `cruiseSpeed`, `acceptanceRadius` — preserving `5.0` default for `FLY_TO`, `headingMode` — defaulting to `"POI"` for `POI_HOLD`, `radius = 30.0`/`direction = "CW"` for `ORBIT`, `patrolMode = "LOOP"`/`cycles = 1` for `PATROL`, `waitForAck = true`/`expectedStatus = "OK"`/`commandPayload = {}` for `PAYLOAD_ACTION`, `durationMs = 0`/`minLevel = 1` for `REDSTONE_ACTION`).

2. **`src/3_planning/amm/modules/network_manager.lua`**:
   - Add `openPayloadChannels = {}` in `network_manager.new(config)`.
   - Keep `bind_modem` opening only `baseChannel + 0` and `baseChannel + 3`.
   - Implement `is_payload_channel(channel)` (`type(ch) == "number" and ch == ch and ch ~= math.huge and ch ~= -math.huge and math.floor(ch) == ch and ch >= base + 20 and ch <= base + 29`).
   - Implement `resolve_payload_channel(channel_or_offset)`: if finite integer in `20..29` return `base + val`; if finite integer in `[base+20, base+29]` return `val`; else `nil, "INVALID_ZONE3_CHANNEL"`.
   - Implement `open_payload_channel(channel_or_offset)`, `close_payload_channel(channel_or_offset)`, `close_all_payload_channels()`, `send_payload_req(channel_or_offset, checkpointId, command, params, opts)` (recording `was_open = (self.openPayloadChannels[ch] == true)` before transmitting and closing `ch` afterward only when `not was_open and not opts.keepOpen`), and `send_mission_ack(ack_payload)`.

3. **`src/0_development/installer/modules/manifest.lua`**:
   - Add `{ repoPath = "src/3_planning/amm/modules/mission_engine.lua", dest = "/modules/mission_engine.lua", gdriveId = nil },` inside `manifest.MODULES.amm.files`.

- [ ] **Step 4: Run AMM unit tests, installer tests, Lua syntax check, and manifest 3-way verifier**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --clean-orphans; if ($?) { python tools/run_unit_tests.py --target 0_development/installer --clean-orphans }; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python tools/validate_lua_syntax.py }
```
Expected: All `3_planning/amm` & `0_development/installer` tests PASS, `verify_manifest_sync.py` reports `0 Errors, 0 Warnings`, `validate_lua_syntax.py` passes cleanly.

- [ ] **Step 5: Commit Task 1**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/modules/mission_engine.lua src/3_planning/amm/modules/network_manager.lua src/0_development/installer/modules/manifest.lua tests/3_planning/amm/test_checkpoint_schema.lua tests/3_planning/amm/test_network_manager.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): add 13-action checkpoint schema and Zone 3 dynamic bus (TASK-202-2)"
```

---

### Task 2: 12-Type Condition Evaluator & Default Completion Resolver (`condition_evaluator.lua`)

**Files:**
- Create: `src/3_planning/amm/modules/condition_evaluator.lua`
- Modify: `src/0_development/installer/modules/manifest.lua:542-554`
- Create: `tests/3_planning/amm/test_condition_evaluator.lua`

**Interfaces:**
- Consumes:
  - Normalized `cp` from `mission_engine.normalize_checkpoint` (passed as table; zero `require("mission_engine")`)
  - Evaluation context `ctx`: `{ mfd, target, checkpoint, enteredAtMs, nowMs, touchdownArmed, payloadAck, armState, redstone, colors, patrolCompleted }`
- Produces:
  - `condition_evaluator.CONDITION_TYPES` (12 keys)
  - `condition_evaluator.should_arm_touchdown(fsm_state) -> boolean`
  - `condition_evaluator.resolve_default_complete(cp, defaults) -> table|nil, string|nil`
  - `condition_evaluator.evaluate_condition(cond, ctx, defaults) -> boolean, table`
  - `condition_evaluator.evaluate_group(group, ctx, default_logic, defaults) -> boolean, table`
  - `condition_evaluator.evaluate_checkpoint(cp, ctx, defaults) -> { aborted, completed, abort_results, complete_results, summary, error }`
  - `condition_evaluator.format_progress(cp, ctx, defaults) -> string`

- [ ] **Step 1: Write the failing unit tests in `tests/3_planning/amm/test_condition_evaluator.lua`**

Create `tests/3_planning/amm/test_condition_evaluator.lua`:
```lua
-- tests/3_planning/amm/test_condition_evaluator.lua
local condition_evaluator = require("condition_evaluator")

describe("AMM 12-Type Condition Evaluator and Default Resolver", function()
    it("evaluates geometric, time, and fuel conditions while blocking missing boot telemetry", function()
        local boot_ctx = { mfd = nil, enteredAtMs = 1000, nowMs = 2000, target = { x = 0, y = 100, z = 0 } }
        assert_false(condition_evaluator.evaluate_condition({ type = "PROXIMITY_2D", toleranceM = 20 }, boot_ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "PROXIMITY_3D", toleranceM = 10 }, boot_ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "ALTITUDE_REACHED", toleranceM = 5 }, boot_ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "FUEL_LEVEL_BELOW", threshold = 0.25 }, boot_ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "CROSS_TRACK_ERROR", maxDevM = 10 }, boot_ctx))

        local ctx = {
            mfd = {
                fsmState = "CRUISE",
                fuel = 0.22,
                dynamics = { altitudeY = 138.0 },
                navigation = { currentPos = { x = 103.0, z = -4.0 }, crossTrackError = -12.5 },
            },
            target = { x = 100.0, y = 140.0, z = 0.0 },
            enteredAtMs = 10000,
            nowMs = 40000,
        }
        assert_true(condition_evaluator.evaluate_condition({ type = "PROXIMITY_2D", toleranceM = 5.0 }, ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "PROXIMITY_2D", toleranceM = 4.5 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "PROXIMITY_3D", toleranceM = 5.5 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "ALTITUDE_REACHED", toleranceM = 2.0 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "DURATION_SEC", durationSec = 30.0 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "TIMEOUT_SEC", timeout = 30.0 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "FUEL_LEVEL_BELOW", threshold = 0.25 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "CROSS_TRACK_ERROR", maxDevM = 12.0 }, ctx))
    end)

    it("guards FACILITY_TOUCHDOWN against pre-approach DISARMED and isolates stale PAYLOAD_RESP_MATCH ACKs", function()
        local ground_ctx = { mfd = { fsmState = "DISARMED" }, touchdownArmed = false }
        assert_false(condition_evaluator.evaluate_condition({ type = "FACILITY_TOUCHDOWN" }, ground_ctx))
        assert_true(condition_evaluator.should_arm_touchdown("APPROACH_LAND"))
        assert_false(condition_evaluator.should_arm_touchdown("DISARMED"))

        local landed_ctx = { mfd = { fsmState = "DISARMED" }, touchdownArmed = true }
        assert_true(condition_evaluator.evaluate_condition({ type = "FACILITY_TOUCHDOWN" }, landed_ctx))

        local stale_ack_ctx = {
            checkpoint = { checkpointId = "CP_04" },
            payloadAck = { checkpointId = "CP_02", command = "RELEASE_BAY", status = "DROPPED" },
        }
        assert_false(condition_evaluator.evaluate_condition({ type = "PAYLOAD_RESP_MATCH", expectedStatus = "DROPPED" }, stale_ack_ctx))

        local valid_ack_ctx = {
            checkpoint = { checkpointId = "CP_04" },
            payloadAck = { checkpointId = "CP_04", command = "RELEASE_BAY", status = "DROPPED" },
        }
        assert_true(condition_evaluator.evaluate_condition({ type = "PAYLOAD_RESP_MATCH", expectedStatus = "DROPPED" }, valid_ack_ctx))
    end)

    it("evaluates REDSTONE_INPUT_HIGH (analog, digital, bundled) and reserved ARM_DOCKED / ARM_RELEASED conditions", function()
        local rs = mock.redstone()
        rs._bundledIn = { top = colors.red }
        rs.getBundledInput = function(side) return rs._bundledIn[side] or 0 end
        rs.testBundledInput = function(side, mask) return bit32.band(rs._bundledIn[side] or 0, mask) ~= 0 end

        rs.setAnalogInput("left", 9)
        rs.setInput("back", true)

        local ctx = {
            redstone = rs,
            colors = colors,
            armState = { docked = true, released = false, facilityId = "ARM_01" },
        }
        assert_true(condition_evaluator.evaluate_condition({ type = "REDSTONE_INPUT_HIGH", side = "left", minLevel = 8 }, ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "REDSTONE_INPUT_HIGH", side = "left", minLevel = 10 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "REDSTONE_INPUT_HIGH", side = "back", minLevel = 1 }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "REDSTONE_INPUT_HIGH", side = "top", color = colors.red }, ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "REDSTONE_INPUT_HIGH", side = "top", color = colors.blue }, ctx))
        assert_true(condition_evaluator.evaluate_condition({ type = "ARM_DOCKED", facilityId = "ARM_01" }, ctx))
        assert_false(condition_evaluator.evaluate_condition({ type = "ARM_RELEASED", facilityId = "ARM_01" }, ctx))
    end)

    it("combines conditions via ALL/ANY and prevents vacuous truth on empty condition arrays", function()
        assert_false(condition_evaluator.evaluate_group({ logic = "ALL", conditions = {} }, {}))
        assert_false(condition_evaluator.evaluate_group({ logic = "ANY", conditions = {} }, {}))

        local ctx = { enteredAtMs = 0, nowMs = 5000, mfd = { fuel = 0.80 } }
        local grp_all = {
            logic = "ALL",
            conditions = {
                { type = "DURATION_SEC", durationSec = 5 },
                { type = "FUEL_LEVEL_BELOW", threshold = 0.20 },
            },
        }
        local grp_any = { logic = "ANY", conditions = grp_all.conditions }
        assert_false(condition_evaluator.evaluate_group(grp_all, ctx))
        assert_true(condition_evaluator.evaluate_group(grp_any, ctx))
    end)

    it("resolves default completeWhen across all 9 active actions, rejects 4 deferred actions, and formats compact progress", function()
        local over_def = condition_evaluator.resolve_default_complete({ action = "FLY_OVER", params = {} }, { acceptanceRadius = 15 })
        assert_eq(over_def.conditions[1].type, "PROXIMITY_2D")
        assert_eq(over_def.conditions[1].toleranceM, 15)

        local to_def = condition_evaluator.resolve_default_complete({ action = "FLY_TO", params = {} }, { acceptanceRadius = 15 })
        assert_eq(to_def.conditions[1].type, "PROXIMITY_3D")
        assert_eq(to_def.conditions[1].toleranceM, 5.0)

        local tk_cp = { action = "TAKEOFF_LAUNCHPAD", params = { targetAlt = 140 } }
        local tk_eval = condition_evaluator.evaluate_checkpoint(tk_cp, { mfd = { fsmState = "CRUISE", dynamics = { altitudeY = 80 } } })
        assert_true(tk_eval.completed)

        local land_def = condition_evaluator.resolve_default_complete({ action = "LAND_LAUNCHPAD", params = { facilityId = "PAD_01" } })
        assert_eq(land_def.conditions[1].type, "FACILITY_TOUCHDOWN")

        local poi_hold = condition_evaluator.resolve_default_complete({ action = "POI_HOLD", params = {} })
        assert_eq(#poi_hold.conditions, 0)

        local pat_eval = condition_evaluator.evaluate_checkpoint({ action = "PATROL", params = { waypoints = { { x = 0, z = 0 } } } }, { patrolCompleted = true })
        assert_true(pat_eval.completed)

        local orb_hold = condition_evaluator.resolve_default_complete({ action = "ORBIT", params = {} })
        assert_eq(#orb_hold.conditions, 0)
        local orb_dur = condition_evaluator.resolve_default_complete({ action = "ORBIT", params = { durationSec = 30 } })
        assert_eq(orb_dur.conditions[1].type, "DURATION_SEC")

        local pld_imm = condition_evaluator.resolve_default_complete({ action = "PAYLOAD_ACTION", params = { command = "PING", waitForAck = false } })
        assert_eq(pld_imm.conditions[1].type, "DURATION_SEC")
        assert_eq(pld_imm.conditions[1].durationSec, 0)

        local rs_emit = condition_evaluator.resolve_default_complete({ action = "REDSTONE_ACTION", params = { mode = "EMIT", side = "top", durationMs = 500 } })
        assert_eq(rs_emit.conditions[1].durationSec, 0.5)

        local rs_wait = condition_evaluator.resolve_default_complete({ action = "REDSTONE_ACTION", params = { mode = "WAIT_INPUT", side = "back" } })
        assert_eq(rs_wait.conditions[1].type, "REDSTONE_INPUT_HIGH")

        for _, def_act in ipairs({ "TAKEOFF_RUNWAY", "LAND_RUNWAY", "DOCK_ARM", "UNDOCK_ARM" }) do
            local d_res, d_err = condition_evaluator.resolve_default_complete({ action = def_act, params = {} })
            assert_nil(d_res)
            assert_eq(d_err, "DEFERRED_ACTION_UNSUPPORTED")
        end

        local str = condition_evaluator.format_progress(
            { action = "ORBIT", params = { durationSec = 30 } },
            { enteredAtMs = 0, nowMs = 12000 }
        )
        assert_true(#str > 0 and #str <= 25)
    end)
end)
```

- [ ] **Step 2: Run the unit test to verify it fails**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --filter condition_evaluator --clean-orphans
```
Expected: FAIL (`module 'condition_evaluator' not found`).

- [ ] **Step 3: Implement `condition_evaluator.lua` and register it in `manifest.lua`**

1. **`src/3_planning/amm/modules/condition_evaluator.lua`**:
   - Define `CONDITION_TYPES` (all 12 condition strings from §6.3) and `DEFERRED_ACTIONS` (`TAKEOFF_RUNWAY`, `LAND_RUNWAY`, `DOCK_ARM`, `UNDOCK_ARM`).
   - Implement `EVALUATORS` dispatch table with 12 concise evaluators (`<= 25` lines each):
     - `PROXIMITY_2D`, `PROXIMITY_3D`, `ALTITUDE_REACHED` (handling finite `ctx.mfd` guard and optional `cond.allowFsmCruise and mfd.fsmState == "CRUISE"` for `TAKEOFF_LAUNCHPAD` default).
     - `DURATION_SEC`, `TIMEOUT_SEC` (using canonical `cond.timeout`), `FUEL_LEVEL_BELOW` (`fuel <= threshold` with nil telemetry guard), `CROSS_TRACK_ERROR` (`math.abs(cte) >= maxDevM`).
     - `FACILITY_TOUCHDOWN` (`mfd.fsmState == "DISARMED"` and `ctx.touchdownArmed ~= false`), `PAYLOAD_RESP_MATCH` (matching `expectedStatus`, optional `command`, and `ctx.checkpoint.checkpointId` isolation against stale ACKs).
     - `REDSTONE_INPUT_HIGH` (supporting bundled `bit32.band`/`testBundledInput` plus analog `getAnalogInput` and digital `getInput` mapped to `15`).
     - `ARM_DOCKED`, `ARM_RELEASED` (reading reserved `ctx.armState`).
   - Implement `resolve_default_complete(cp, defaults)` matching §6.3 for all 9 active actions and returning `nil, "DEFERRED_ACTION_UNSUPPORTED"` for deferred actions.
   - Implement `evaluate_group(group, ctx, default_logic, defaults)` returning `false, {}` when `conditions` is empty, otherwise applying `"ALL"` (default) or `"ANY"`.
   - Implement `evaluate_checkpoint(cp, ctx, defaults)` (evaluating `abortWhen` before `completeWhen`, ensuring `ctx.checkpoint or cp` is bound for `PAYLOAD_RESP_MATCH`/`PROXIMITY_*`, and supporting `ctx.patrolCompleted` for `PATROL` without `durationSec`) and compact `format_progress(cp, ctx, defaults)` (`<= 25` chars).

2. **`src/0_development/installer/modules/manifest.lua`**:
   - Add `{ repoPath = "src/3_planning/amm/modules/condition_evaluator.lua", dest = "/modules/condition_evaluator.lua", gdriveId = nil },` inside `manifest.MODULES.amm.files`.

- [ ] **Step 4: Run unit tests, manifest verifier, and syntax checker**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --clean-orphans; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python tools/validate_lua_syntax.py }
```
Expected: PASS on all `3_planning/amm` tests, `0 Errors, 0 Warnings` on `verify_manifest_sync.py`, Lua 5.2 syntax valid.

- [ ] **Step 5: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/modules/condition_evaluator.lua src/0_development/installer/modules/manifest.lua tests/3_planning/amm/test_condition_evaluator.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): implement 12-type condition evaluator and default resolver (TASK-202-2)"
```

---

### Task 3: 0-Tick Lifecycle Hook Runner & Non-Blocking Device Driver (`hook_runner.lua`)

**Files:**
- Create: `src/3_planning/amm/modules/hook_runner.lua`
- Modify: `src/0_development/installer/modules/manifest.lua:542-555`
- Create: `tests/3_planning/amm/test_hook_runner.lua`

**Interfaces:**
- Consumes:
  - `network_manager` instance from Task 1 (`:open_payload_channel`, `:close_payload_channel`, `:close_all_payload_channels`, `:send_payload_req`, `:is_payload_channel`, `:decode_envelope`)
  - Normalized `checkpoint` from Task 1
- Produces:
  - `hook_runner.VALID_HOOK_TYPES` (`REDSTONE_SET`, `REDSTONE_PULSE`, `ZONE3_PAYLOAD_CMD`, `NOTIFY_OPERATOR`)
  - `hook_runner.new(opts) -> runner` (`opts = { net, redstone, colors, on_notify }`)
  - `hook_runner:execute_hooks(hooks, checkpoint, now_ms) -> integer, table`
  - `hook_runner:start_action(checkpoint, now_ms) -> boolean, string|nil`
  - `hook_runner:tick(now_ms) -> integer`
  - `hook_runner:on_payload_ack(packet, channel) -> boolean, table|string`
  - `hook_runner:get_last_payload_ack() -> table|nil`
  - `hook_runner:clear_step_state()`
  - `hook_runner:cleanup()`

- [ ] **Step 1: Write the failing unit tests in `tests/3_planning/amm/test_hook_runner.lua`**

Create `tests/3_planning/amm/test_hook_runner.lua`:
```lua
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
            action = "PAYLOAD_ACTION",
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

    it("manages PAYLOAD_ACTION dynamic Zone 3 open-ACK-close lifecycle, rejects wrong channel/checkpointId, and handles ZONE3_PAYLOAD_CMD", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local runner = hook_runner.new({ net = net })

        local ok, err = runner:start_action({
            checkpointId = "CP_04",
            action = "PAYLOAD_ACTION",
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

        -- Fire-and-forget ZONE3_PAYLOAD_CMD must transmit and leave channel closed
        runner:execute_hooks({
            { type = "ZONE3_PAYLOAD_CMD", channelOffset = 21, command = "TRIGGER_RADAR", payload = { scan = true } },
        }, { checkpointId = "CP_05" }, 3000)
        assert_false(m.isOpen(10021))
        assert_eq(m._transmitted[2].tx, 10021)
        assert_eq(m._transmitted[2].pkt.type, "MSG_PAYLOAD_REQ")

        -- Invalid Zone 3 channel or deferred action returns explicit error without transmitting
        local ok_def, err_def = runner:start_action({ checkpointId = "CP_DEF", action = "DOCK_ARM", params = {} }, 3100)
        assert_false(ok_def)
        assert_eq(err_def, "DEFERRED_ACTION_UNSUPPORTED")
    end)

    it("executes REDSTONE_ACTION EMIT pulses and ignores WAIT_INPUT without side effects", function()
        local rs = mock.redstone()
        local runner = hook_runner.new({ redstone = rs })

        local ok_e = runner:start_action({
            checkpointId = "CP_RS1",
            action = "REDSTONE_ACTION",
            params = { mode = "EMIT", side = "bottom", level = 12, durationMs = 250 },
        }, 5000)
        assert_true(ok_e)
        assert_eq(rs.getAnalogOutput("bottom"), 12)
        assert_eq(runner:tick(5249), 0)
        assert_eq(rs.getAnalogOutput("bottom"), 12)
        assert_eq(runner:tick(5250), 1)
        assert_eq(rs.getAnalogOutput("bottom"), 0)

        local ok_w = runner:start_action({
            checkpointId = "CP_RS2",
            action = "REDSTONE_ACTION",
            params = { mode = "WAIT_INPUT", side = "back", minLevel = 1 },
        }, 5300)
        assert_true(ok_w)
    end)
end)
```

- [ ] **Step 2: Run the unit test to verify it fails**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --filter hook_runner --clean-orphans
```
Expected: FAIL (`module 'hook_runner' not found`).

- [ ] **Step 3: Implement `hook_runner.lua` and register it in `manifest.lua`**

1. **`src/3_planning/amm/modules/hook_runner.lua`**:
   - Define `VALID_HOOK_TYPES`, `DEFERRED_ACTIONS`.
   - Maintain per-instance state: `net`, `redstone` (`opts.redstone or _G.redstone`), `colors` (`opts.colors or _G.colors`), `on_notify`, `activePulses` (keyed map `"<side>:<kind>:<mask>" -> { side, kind, colorMask, expireMs }`), `pendingPayload`, `lastPayloadAck`, `notifications`.
   - Helper `apply_redstone(rs, colors_api, spec, active)`:
     - Bundled (`spec.color ~= nil`): resolve mask (`number` or `colors_api[spec.color]`), combine via `bit32.bor` (active) or `bit32.band(cur, bit32.bnot(mask))` (inactive).
     - Analog (`spec.level ~= nil`): call `rs.setAnalogOutput(side, active and clamped_lvl or 0)`. (Never overwrite analog level with `setOutput(side, true)`.)
     - Digital: call `rs.setOutput(side, active)`.
   - `execute_hooks(hooks, checkpoint, now_ms)`: iterate sequentially via `HOOK_HANDLERS` (`REDSTONE_SET`, `REDSTONE_PULSE` updating `expireMs = math.max(prev, now_ms + dur)`, `ZONE3_PAYLOAD_CMD` fire-and-forget forwarding `hook.payload` to `net:send_payload_req(..., { keepOpen = false })`, `NOTIFY_OPERATOR`).
   - `start_action(checkpoint, now_ms)`: reject `DEFERRED_ACTIONS` with `"DEFERRED_ACTION_UNSUPPORTED"`; for `PAYLOAD_ACTION` validate channel (`channelOffset` first, else `targetChannel`/`channel`), open and send via `net:send_payload_req(..., { keepOpen = waitForAck })`, store `pendingPayload` when `waitForAck ~= false`; for `REDSTONE_ACTION` handle `EMIT` (with optional `durationMs > 0` deadline pulse) vs `WAIT_INPUT`.
   - `tick(now_ms)`: sweep `activePulses`, deactivate entries with `now_ms >= p.expireMs`, remove and return count.
   - `on_payload_ack(packet, channel)`: validate envelope via `net:decode_envelope` if present, verify `packet.type == "MSG_PAYLOAD_ACK"` and `net:is_payload_channel(channel)` when `channel ~= nil`, check `pendingPayload` channel & `checkpointId` match if pending, store `lastPayloadAck`, close Zone 3 channel (`net:close_payload_channel`), clear `pendingPayload`, return `true, ack`.
   - `clear_step_state()` and `cleanup()`: clear ACK/pending, close open Zone 3 channel(s), deactivate and clear all `activePulses`.

2. **`src/0_development/installer/modules/manifest.lua`**:
   - Add `{ repoPath = "src/3_planning/amm/modules/hook_runner.lua", dest = "/modules/hook_runner.lua", gdriveId = nil },` inside `manifest.MODULES.amm.files`.

- [ ] **Step 4: Run unit tests, manifest verifier, and syntax checker**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --clean-orphans; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python tools/validate_lua_syntax.py }
```
Expected: PASS on all `3_planning/amm` tests, `0 Errors, 0 Warnings` on `verify_manifest_sync.py`, Lua 5.2 syntax valid.

- [ ] **Step 5: Commit Task 3**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/modules/hook_runner.lua src/0_development/installer/modules/manifest.lua tests/3_planning/amm/test_hook_runner.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): implement 0-tick hook runner and non-blocking Zone 3 / redstone driver (TASK-202-2)"
```

---

### Task 4: Cross-Module Integration Verification, Code Quality & `TASK.md` Sync

**Files:**
- Create: `tests/3_planning/amm/test_mission_core_integration.lua`
- Modify: `TASK.md:69-70`
- Modify: `.agent/memory/workspace-root.md`

**Interfaces:**
- Consumes:
  - `mission_engine` (Task 1), `network_manager` (Task 1), `condition_evaluator` (Task 2), `hook_runner` (Task 3)
- Produces:
  - End-to-end component verification of normalized checkpoint -> `onEnter` hooks -> device action -> simulated telemetry / Zone 3 ACK / clock ticks -> `condition_evaluator` -> `onExit`/`onAbort` hooks -> `cleanup()`
  - Updated `TASK-202-2` (`[x]`) in `TASK.md` and appended milestone log in `.agent/memory/workspace-root.md` (`AMM_PROGRAM_SPECIFICATION.md` remains `v1.1.0 Approved` until `TASK-202-5`)

- [ ] **Step 1: Write cross-module integration tests in `tests/3_planning/amm/test_mission_core_integration.lua`**

Create `tests/3_planning/amm/test_mission_core_integration.lua`:
```lua
-- tests/3_planning/amm/test_mission_core_integration.lua
local mission_engine = require("mission_engine")
local network_manager = require("network_manager")
local condition_evaluator = require("condition_evaluator")
local hook_runner = require("hook_runner")

describe("AMM Mission Core Cross-Module Integration", function()
    it("runs ORBIT with onEnter pulse + duration completion + low-fuel abort hook sequence", function()
        local rs = mock.redstone()
        local notes = {}
        local runner = hook_runner.new({
            redstone = rs,
            colors = colors,
            on_notify = function(lvl, msg) table.insert(notes, lvl .. ":" .. msg) end,
        })

        local cp, err = mission_engine.normalize_checkpoint({
            checkpointId = "CP_ORBIT_01",
            action = "ORBIT",
            params = { targetPos = { x = 600, z = -1500 }, radius = 40, direction = "CW" },
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
            nowMs = 10000,
        })
        assert_true(eval_low_fuel.aborted)
        assert_false(eval_low_fuel.completed)

        runner:execute_hooks(cp.onAbort, cp, 10000)
        assert_true(rs.getOutput("right"))
    end)

    it("runs PAYLOAD_ACTION dynamic Zone 3 lifecycle into PAYLOAD_RESP_MATCH completion and channel close", function()
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local runner = hook_runner.new({ net = net })

        local cp, err = mission_engine.normalize_checkpoint({
            checkpointId = "CP_CARGO",
            action = "PAYLOAD_ACTION",
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
end)
```

- [ ] **Step 2: Run the full verification suite across unit, E2E, mutation, harness, manifest, specs, and Lua syntax**

Run:
```powershell
python tools/run_unit_tests.py --require-tests --clean-orphans; if ($?) { python tools/run_e2e_tests.py --clean-orphans }; if ($?) { python tools/run_mutation_tests.py }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python tools/verify_all_specs.py --check-readmes }; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/validate_lua_syntax.py }
```
Expected:
- `run_unit_tests.py`: 12 targets PASS (`0 failed`)
- `run_e2e_tests.py`: 7 scenarios `8/8 PASS`
- `run_mutation_tests.py`: `25/25 KILLED (100.0%)` (including `MUT-04`, `MUT-05`)
- `tests/harness`: PASS (`0 failed`)
- `verify_manifest_sync.py`: `0 Errors, 0 Warnings`
- `verify_all_specs.py --check-readmes`: `0 Errors, 0 Warnings`
- `verify_spec_status.py`: PASS (`AMM_PROGRAM_SPECIFICATION.md` remains `v1.1.0 Approved` until `TASK-202-5`)
- `validate_lua_syntax.py`: PASS

- [ ] **Step 3: Sync `TASK.md` (`TASK-202-2` -> `[x]`) and `.agent/memory/workspace-root.md`, then verify context docs**

1. Update `TASK.md:70` to `- [x] **TASK-202-2**` with completion date & artifacts (`mission_engine.lua`, `condition_evaluator.lua`, `hook_runner.lua`, `network_manager.lua`, unit counts). Keep `TASK-202` top-level `[-]` until `TASK-202-5`.
2. Append a `2026-11-11 — TASK-202-2` record to `.agent/memory/workspace-root.md` (mentioning `TASK-202-2` per `verify_context_docs.py` R8).
3. Run:
   ```powershell
   python tools/verify_context_docs.py
   ```
   Expected: `[PASS] Context document verification passed (0 findings across R1-R8).`

- [ ] **Step 4: Commit Task 4**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tests/3_planning/amm/test_mission_core_integration.lua TASK.md .agent/memory/workspace-root.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "test(amm): add mission core integration tests and sync TASK-202-2 status"
```
