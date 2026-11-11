# AMM 51x19 TUI Viewport, Multi-Path Resolver, Preflight Validator, File Drop & CLI Extensions (TASK-202-4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execute implementation in an isolated git worktree (`using-git-worktrees`) branched from `main`.

**Goal:** Complete AMM v1.2.0 onboarding and cockpit UX in `src/3_planning/amm/` by adding the multi-path file resolver (`resolve_path`), preflight schema validator (`validate_mission_table`), `c2_arbiter.lua` `SCHEMA_INVALID` ACK mapping, `ui_renderer.lua` 51x19 6-row scrolling viewport + 5-row condition progress panel, `input_handler.lua` / `main.lua` CLI commands (`run`/`load`/`files`/`stop`/`next`/`mission`), shell boot arguments, and `file_transfer` drag-and-drop hot injection.

**Architecture:** `mission_engine.lua` adds pure static helpers (`resolve_path`, `list_mission_files`, `validate_mission_table`) and integrates them into `load()`, allowing `c2_arbiter.lua` to resolve external/floppy mission paths on `Base+0` `MSG_MISSION_CMD (RUN)` and return `"SCHEMA_INVALID"` with checkpoint detail alongside `"FILE_NOT_FOUND"` and `"DEFERRED_ACTION_UNSUPPORTED"`. `ui_renderer.lua` adds `compute_viewport()` and polymorphic rendering supporting both `mission_engine` (6-row centered scroll viewport + 5-row state/action/condition/alt-speed/distance details) and legacy `waypoint_queue` while keeping every row strictly 51 characters wide. `input_handler.lua` and `main.lua` wire `run`/`load`/`files`/`stop`/`next`/`mission` CLI commands, `parse_boot_args()` for `main.lua <spec> [loop]`, and non-disruptive `handle_file_transfer()` drop handling (`IDLE` immediate load + optional `autoRunDroppedFile`, vs in-flight disk save only).

**Tech Stack:** CC:Tweaked 1.109+ Lua 5.2 (Cobalt VM, `fs`, `textutils`, `term.blit`), CraftOS-PC Headless Unit Test Runner (`tools/run_unit_tests.py`), Multi-Node E2E Simulation Harness (`tools/run_e2e_tests.py`), Mutation Test Runner (`tools/run_mutation_tests.py`), Python 3.10+ Verifiers (`tools/verify_manifest_sync.py`, `tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/validate_lua_syntax.py`, `tools/verify_context_docs.py`).

**Spec:**
- Primary Specification: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v1.2.0 Approved` — §5.1, §6.6, §7.3, §8.1, §8.2, §10, §11; remains `Approved` after `TASK-202-4` and transitions to `Implemented` at `TASK-202-5` after `tools/amm_mission_editor.html` and E2E verification)
- Master ICD: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.27.0 Approved` — Interface I-6 `MSG_MISSION_CMD` / `MSG_MISSION_ACK` with `SCHEMA_INVALID`)
- Roadmap SSOT: `TASK.md` (`TASK-202-4`)

## Global Constraints

- **Lua 5.2 Cobalt Runtime (`.agent/rules/cc-tweaked-runtime.md`)**: No Lua 5.3+ operators (`//`, `&`, `|`, `~`, `<<`, `>>`); use `fs.*` (`fs.exists`, `fs.isDir`, `fs.list`, `fs.open`, `fs.makeDir`, `fs.getName`) and never call `os.execute`, `os.exit`, `os.remove`, `os.rename`, `io.popen`, `getfenv`, or `setfenv`.
- **Non-Blocking Loop Contract (`AMM_PROGRAM_SPECIFICATION.md` §1.3, §6.4, §11)**: Zero calls to `sleep()`, `os.pullEvent()`, or `os.pullEventRaw()` inside `mission_engine.lua`, `c2_arbiter.lua`, `ui_renderer.lua`, `input_handler.lua`, or `main.lua` event handlers (`runner_lib.lua` aborts with `EVENT_SWALLOW_VIOLATION`).
- **Single-Function Complexity (`AMM_PROGRAM_SPECIFICATION.md` §10, §11)**: Keep every Lua function at `<= 50` lines using dispatch tables (`SCHEMA_PARAM_CHECKS`, `LOAD_ERR_TO_ACK`, `CLI_HANDLERS`, `MISSION_SUBCOMMANDS`).
- **Exact 51x19 Surface Integrity (`runner_lib.lua` Surface Auditor)**: Every `term.blit` call from `ui_renderer.flush_buffer` must pass `#text == #fg == #bg == 51` across all 19 rows with numeric `setCursorPos(1, y)` coordinates.
- **Valkyrien Skies Mod Ban (`.agent/rules/domain-aeronautics.md`)**: Zero prohibited mod identifiers (`valkyrien`, `vs2`, `cc_vs`, `ship` peripheral, `kontraption:`).
- **Mutation Target Line & Legacy API Preservation (`tools/run_mutation_tests.py`, `tests/3_planning/amm/`)**: Preserve `MUT-04` in `src/3_planning/amm/modules/waypoint_queue.lua` (`if d2d <= rad then`), `MUT-05` in `src/3_planning/amm/modules/c2_arbiter.lua` (`self.queue.state = "SUSPENDED"`), legacy `waypoint_queue` rendering assertions in `test_ui_renderer.lua` and `test_amm_integration.lua`, and `src/3_planning/amm/config/amm_config.json` unchanged (`test_harness_setup.lua`).
- **Zero-Fallback Protocol Standard (`AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` §1.3)**: Emit and parse only canonical v1.2.0 / ICD v1.9.5 ACK statuses (`ACCEPTED`, `BUSY_REJECTED`, `FILE_NOT_FOUND`, `SCHEMA_INVALID`, `DEFERRED_ACTION_UNSUPPORTED`, `INVALID_CMD`).

## Review Focus

1. **Path Traversal & Directory-as-File Collision in `resolve_path` and `handle_file_transfer` (`mission_engine.lua`, `main.lua`)**: Passing `"../config/amm_config.json"` or an existing directory name such as `"missions"` must never escape the sandbox or try to open a directory; `resolve_path` must reject `".."` with `nil, "INVALID_PATH"` and skip entries where `fs.isDir(p) == true`, and `handle_file_transfer` must sanitize filenames with `fs.getName` and reject `".."` (pinned by tests in Task 1 `test_external_loader.lua` and Task 3 `test_main_loop.lua`).
2. **In-Flight `file_transfer` Drop Corrupting Active Sortie or Invalid Drop Overwriting Disk (`main.lua`)**: Dropping a valid `.json` while `engine.state == "EN_ROUTE"` or `"SUSPENDED"` must save `missions/<name>` and display `"DROP SAVED: <name> (USE 'run <name>')"`, leaving `engine.checkpoints`, `engine.active_index`, and `engine.state` untouched; dropping malformed JSON or schema-invalid content must display `"DROP FAIL: <detail>"` without overwriting an existing valid file on disk (pinned by tests in Task 3 `test_main_loop.lua`).
3. **`SCHEMA_INVALID` vs `DEFERRED_ACTION_UNSUPPORTED` vs `FILE_NOT_FOUND` Separation on `Base+0` `MSG_MISSION_CMD (RUN)` (`c2_arbiter.lua`)**: An existing JSON file failing `validate_mission_table` (empty `checkpoints`, unknown `action`, missing `PAYLOAD_ACTION` `command`, invalid `completeWhen`/`onEnter` type, or malformed JSON) must answer `MSG_MISSION_ACK` with `status = "SCHEMA_INVALID"` and `reason` detail without stopping an active flight even when `forceRestart == true`, while valid schemas with deferred actions return `"DEFERRED_ACTION_UNSUPPORTED"` and missing paths return `"FILE_NOT_FOUND"` (pinned by test in Task 1 `test_c2_arbiter.lua`).
4. **51x19 TUI Viewport Scrolling Boundary, Reused-Buffer Ghost Text & 51-Char Width Invariant (`ui_renderer.lua`)**: Rendering a 10-checkpoint mission scrolled to index 6 and then re-rendering a 2-checkpoint or empty mission onto the same `screen_buf` must center `active_index` in rows `4..9`, overwrite all 25 right-pane columns (`27..51`) across rows `3..15` with zero leftover characters, and keep every row of `buf.text`, `buf.fg`, and `buf.bg` at exact length `51` even with long IDs (pinned by tests in Task 2 `test_ui_renderer.lua`).
5. **Boot-Arg Disambiguation (`main.lua <spec> [loop]`), Empty-Engine Queue Fallback on `run`, and CLI Pilot Takeover (`input_handler.lua`, `main.lua`)**: `parse_boot_args` must distinguish `"config/amm_config.json"` from mission specs such as `"/disk/sortie_01.json"` or `"sortie_01"` + `"loop"`; CLI `run` with no args when only `waypoint_queue` holds items must migrate and start those waypoints instead of failing; and executing CLI mission commands (`run`, `stop`, `next`, `mission ...`) under `GCS_OVERRIDE` must restore `authority = "PILOT_PRIMARY"` on both `arbiter` and `engine` (pinned by tests in Task 3 `test_input_handler.lua` and `test_main_loop.lua`).

---

## File Structure

- Modify: `src/3_planning/amm/modules/mission_engine.lua` — Add `mission_engine.resolve_path(spec, fs_api)`, `mission_engine.list_mission_files(fs_api)`, `mission_engine.validate_mission_table(tbl, opts)`, `params.x`/`params.z` shorthand normalization, and integrate `resolve_path` + `validate_mission_table` into `mission_engine:load()`.
- Modify: `src/3_planning/amm/modules/c2_arbiter.lua` — Replace hardcoded `normalize_mission_path` with `eng:load(p.missionName)` (using `resolve_path`), validate before `forceRestart` stop, and map `"SCHEMA_INVALID"` / `"PARSE_ERROR"` to `MSG_MISSION_ACK.payload.status = "SCHEMA_INVALID"` with checkpoint detail.
- Modify: `src/3_planning/amm/modules/ui_renderer.lua` — Export `ui_renderer.compute_viewport(total, active_idx, window_size)` and upgrade `render_screen()` to render both `mission_engine` (6-row scroll viewport `4..9`, `O`/`*`/`!` markers, 5-row active/condition/alt-spd/dist panel `11..15`, col `27..51` width 25) and legacy `waypoint_queue` without stale buffer residue.
- Modify: `src/3_planning/amm/modules/input_handler.lua` — Add `input_handler.VALID_COMMANDS`, `mission` subcommand/subargs normalization in `parse_cli_command`, `input_handler:handle_paste(text)`, and `keys.backspace or keys.backSpace` compatibility.
- Modify: `src/3_planning/amm/main.lua` — Add `parse_boot_args()`, `handle_file_transfer()`, `CLI_HANDLERS` (`run`, `load`, `files`, `stop`, `next`, `mission`, updated `add`/`goto`/`save`/`alt`/`spd`/`rad`), `PILOT_PRIMARY` takeover in `execute_cli_command`, `resolve_path` integration in `try_auto_start_mission()`, and pass `engine` + `now_ms` to `ui_renderer.render_screen()`.
- Create: `tests/3_planning/amm/test_external_loader.lua` — Unit tests for `resolve_path` 5-priority search + directory/traversal guards, `list_mission_files`, and `validate_mission_table` schema rules across all 13 actions, 12 conditions, and 4 hooks.
- Modify: `tests/3_planning/amm/test_c2_arbiter.lua` — Unit tests for `Base+0` `MSG_MISSION_CMD (RUN)` returning `SCHEMA_INVALID`, resolving `/disk/...` paths, and preserving an active mission on failed `forceRestart`.
- Modify: `tests/3_planning/amm/test_ui_renderer.lua` — Unit tests for `compute_viewport`, 10-checkpoint scrolling with `O`/`*`/`!` markers, 5-row condition/distance details, buffer reuse ghost-text clearing, and 51-char `term.blit` invariance.
- Modify: `tests/3_planning/amm/test_input_handler.lua` — Unit tests for `run`/`load`/`files`/`stop`/`next`/`mission` CLI parsing, `VALID_COMMANDS`, and `handle_paste`.
- Modify: `tests/3_planning/amm/test_main_loop.lua` — Unit tests for `file_transfer` drop (valid IDLE load, `autoRunDroppedFile`, in-flight safe save, invalid JSON non-overwrite), `parse_boot_args` & `/disk/` `try_auto_start_mission`, CLI `run`/`load`/`files`/`stop`/`next`/`mission`, legacy queue fallback `run`, and `PILOT_PRIMARY` takeover.
- Modify: `TASK.md` & `.agent/memory/workspace-root.md` — Mark `TASK-202-4` `[x]` and record milestone history after full verification.

---

### Task 1: Multi-Path Resolver (`resolve_path`), Preflight Schema Validator (`validate_mission_table`), and `c2_arbiter` `SCHEMA_INVALID` Mapping

**Files:**
- Modify: `src/3_planning/amm/modules/mission_engine.lua:1-452`
- Modify: `src/3_planning/amm/modules/c2_arbiter.lua:56-128`
- Create: `tests/3_planning/amm/test_external_loader.lua`
- Modify: `tests/3_planning/amm/test_c2_arbiter.lua:230-245`

**Interfaces:**
- Consumes:
  - `condition_evaluator.CONDITION_TYPES` (12 valid condition strings)
  - `hook_runner.VALID_HOOK_TYPES` (4 valid hook strings)
  - `mission_engine.ACTION_TAXONOMY` (13 valid action strings)
- Produces:
  - `mission_engine.resolve_path(spec, fs_api) -> string|nil, string|nil` (`"INVALID_PATH"` | `"FS_UNAVAILABLE"` | `"FILE_NOT_FOUND"`)
  - `mission_engine.list_mission_files(fs_api) -> table`
  - `mission_engine.validate_mission_table(tbl, opts) -> boolean, string|nil, string|nil` (`"SCHEMA_INVALID"`, detail)
  - `mission_engine.preflight_file(spec, opts, fs_api) -> table|nil, string|nil, string|nil` (non-mutating resolve + JSON parse + schema + executable check)
  - `mission_engine:load(spec, fs_api) -> boolean, string|nil, string|nil`
  - `c2_arbiter:handle_mission_cmd` returning `MSG_MISSION_ACK` with `status = "SCHEMA_INVALID"` and `reason` on schema/parse errors

- [ ] **Step 1: Write the failing unit tests in `tests/3_planning/amm/test_external_loader.lua` and `tests/3_planning/amm/test_c2_arbiter.lua`**

Create `tests/3_planning/amm/test_external_loader.lua`:
```lua
-- tests/3_planning/amm/test_external_loader.lua
local mission_engine = require("mission_engine")

describe("AMM Multi-Path Resolver and Preflight Schema Validator", function()
    local created_paths = {}

    local function write_raw(path, content)
        local dir = fs.getDir(path)
        if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
        local f = fs.open(path, "w")
        f.write(content)
        f.close()
        created_paths[#created_paths + 1] = path
    end

    after_each(function()
        for i = #created_paths, 1, -1 do
            local p = created_paths[i]
            if fs.exists(p) then pcall(fs.delete, p) end
            created_paths[i] = nil
        end
    end)

    it("resolves paths across 5 priority tiers while rejecting directory collisions and '..' traversal", function()
        if not fs.exists("missions") then fs.makeDir("missions") end
        if not fs.exists("/disk/missions") then fs.makeDir("/disk/missions") end

        write_raw("custom_root.json", "{}")
        write_raw("missions/alpha.json", "{}")
        write_raw("/disk/beta.json", "{}")
        write_raw("/disk/missions/gamma.json", "{}")
        write_raw("missions/shadow.json", "{}")
        write_raw("/disk/shadow.json", "{}")

        -- Priority 1 & 2: exact path and .json suffix
        assert_eq(mission_engine.resolve_path("custom_root.json"), "custom_root.json")
        assert_eq(mission_engine.resolve_path("custom_root"), "custom_root.json")
        assert_eq(mission_engine.resolve_path("/disk/beta"), "/disk/beta.json")

        -- Priority 3, 4, 5: missions/ beats /disk/, and /disk/missions/ resolves fallback
        assert_eq(mission_engine.resolve_path("alpha"), "missions/alpha.json")
        assert_eq(mission_engine.resolve_path("shadow"), "missions/shadow.json")
        assert_eq(mission_engine.resolve_path("beta"), "/disk/beta.json")
        assert_eq(mission_engine.resolve_path("gamma"), "/disk/missions/gamma.json")

        -- Directory collision: "missions" is a directory, must not match as file
        local dir_only_res, dir_only_err = mission_engine.resolve_path("missions")
        assert_nil(dir_only_res)
        assert_eq(dir_only_err, "FILE_NOT_FOUND")

        -- Path traversal and invalid inputs
        local bad_res, bad_err = mission_engine.resolve_path("../config/amm_config.json")
        assert_nil(bad_res)
        assert_eq(bad_err, "INVALID_PATH")
        local empty_res, empty_err = mission_engine.resolve_path("")
        assert_nil(empty_res)
        assert_eq(empty_err, "INVALID_PATH")
    end)

    it("lists mission files across missions/, /disk/, and /disk/missions/", function()
        write_raw("missions/patrol_alpha.json", "{}")
        write_raw("/disk/sortie_01.json", "{}")
        write_raw("/disk/readme.txt", "ignore")

        local files = mission_engine.list_mission_files()
        local found_alpha, found_disk, found_txt = false, false, false
        for _, entry in ipairs(files) do
            if entry == "patrol_alpha" then found_alpha = true end
            if entry == "/disk/sortie_01" then found_disk = true end
            if string.find(entry, "readme", 1, true) then found_txt = true end
        end
        assert_true(found_alpha)
        assert_true(found_disk)
        assert_false(found_txt)
    end)

    it("validates mission schema across 13 actions, shorthand coords, 12 conditions, and 4 hooks", function()
        local ok_valid, err_v, det_v = mission_engine.validate_mission_table({
            missionId = "EDITOR_EXPORT_01",
            executionMode = "REPEAT",
            fallbackPolicy = "LOITER",
            checkpoints = {
                { action = "FLY_OVER", params = { x = 100, z = -200 } },
                { action = "ORBIT", params = { targetPos = { x = 200, z = -300 }, radius = 35, direction = "CW" } },
                { action = "PATROL", params = { waypoints = { { x = 0, z = 0 }, { x = 50, z = 50 } } } },
                { action = "POI_HOLD", params = { targetPos = { x = 10, z = 10 }, poiPos = { x = 20, y = 65, z = 20 } } },
                { action = "LAND_LAUNCHPAD", params = { facilityId = "PAD_01" } },
                {
                    action = "PAYLOAD_ACTION",
                    params = { channelOffset = 20, command = "DROP" },
                    completeWhen = { logic = "ALL", conditions = { { type = "PAYLOAD_RESP_MATCH", expectedStatus = "OK" } } },
                    onEnter = { { type = "NOTIFY_OPERATOR", level = "INFO", message = "DROP" } },
                },
                { action = "REDSTONE_ACTION", params = { mode = "EMIT", side = "top", durationMs = 250 } },
                { action = "TAKEOFF_RUNWAY", params = {} },
            },
        })
        assert_true(ok_valid, tostring(det_v))
        assert_nil(err_v)

        local invalid_cases = {
            { tbl = { checkpoints = {} }, substr = "EMPTY_CHECKPOINTS" },
            { tbl = { executionMode = "FOREVER", checkpoints = { { action = "FLY_OVER", params = { x = 1, z = 2 } } } }, substr = "EXECUTION_MODE" },
            { tbl = { fallbackPolicy = "CRASH", checkpoints = { { action = "FLY_OVER", params = { x = 1, z = 2 } } } }, substr = "FALLBACK_POLICY" },
            { tbl = { checkpoints = { { action = "WARP", params = {} } } }, substr = "CP#1" },
            { tbl = { checkpoints = { { action = "ORBIT", params = { targetPos = { x = 0, z = 0 }, radius = 0 } } } }, substr = "CP#1" },
            { tbl = { checkpoints = { { action = "PATROL", params = { waypoints = {} } } } }, substr = "CP#1" },
            { tbl = { checkpoints = { { action = "POI_HOLD", params = {} } } }, substr = "CP#1" },
            { tbl = { checkpoints = { { action = "LAND_LAUNCHPAD", params = {} } } }, substr = "CP#1" },
            { tbl = { checkpoints = { { action = "PAYLOAD_ACTION", params = { channelOffset = 19, command = "X" } } } }, substr = "CP#1" },
            { tbl = { checkpoints = { { action = "REDSTONE_ACTION", params = { mode = "EMIT", side = "middle" } } } }, substr = "CP#1" },
            {
                tbl = {
                    checkpoints = {
                        {
                            action = "FLY_OVER",
                            params = { x = 10, z = 20 },
                            completeWhen = { logic = "ALL", conditions = { { type = "TELEPORTED" } } },
                        },
                    },
                },
                substr = "CP#1",
            },
            {
                tbl = {
                    checkpoints = {
                        {
                            action = "FLY_OVER",
                            params = { x = 10, z = 20 },
                            onEnter = { { type = "PLAY_SOUND" } },
                        },
                    },
                },
                substr = "CP#1",
            },
        }

        for _, tc in ipairs(invalid_cases) do
            local ok, code, detail = mission_engine.validate_mission_table(tc.tbl)
            assert_false(ok)
            assert_eq(code, "SCHEMA_INVALID")
            assert_true(string.find(tostring(detail), tc.substr, 1, true) ~= nil, "Missing " .. tc.substr .. " in " .. tostring(detail))
        end
    end)

    it("loads external mission JSON using shorthand params.x/params.z via resolve_path", function()
        write_raw("/disk/shorthand_sortie.json", textutils.serializeJSON({
            missionId = "DISK_SHORT",
            checkpoints = {
                { checkpointId = "CP_1", action = "FLY_OVER", params = { x = 120, z = -340 } },
            },
        }))
        local eng = mission_engine.new({ config = { baseChannel = 10000 } })
        local ok, err = eng:load("shorthand_sortie")
        assert_true(ok, tostring(err))
        assert_eq(eng.checkpoints[1].params.targetPos.x, 120)
        assert_eq(eng.checkpoints[1].params.targetPos.z, -340)
    end)
end)
```

Append to `tests/3_planning/amm/test_c2_arbiter.lua` (inside `describe(...)`):
```lua
    it("maps SCHEMA_INVALID on bad mission JSON, resolves /disk paths, and preserves active flight on failed forceRestart", function()
        local mission_engine = require("mission_engine")
        local q, net, arb, tx = create_fixture()
        local eng = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        arb:set_engine(eng)

        if not fs.exists("/disk") then fs.makeDir("/disk") end
        local f_bad = fs.open("/disk/bad_schema.json", "w")
        f_bad.write(textutils.serializeJSON({
            missionId = "BAD_SCHEMA",
            checkpoints = {
                { checkpointId = "CP_01", action = "FLY_OVER", params = { targetPos = { x = 10, z = 20 } } },
                { checkpointId = "CP_02", action = "PAYLOAD_ACTION", params = { channelOffset = 20 } }, -- missing command
            },
        }))
        f_bad.close()

        local f_disk = fs.open("/disk/disk_sortie.json", "w")
        f_disk.write(textutils.serializeJSON({
            missionId = "DISK_SORTIE",
            checkpoints = {
                { checkpointId = "CP_01", action = "FLY_OVER", params = { x = 400, z = -500 } },
            },
        }))
        f_disk.close()

        -- 1. Schema error -> SCHEMA_INVALID with CP#2 detail
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "/disk/bad_schema", executionMode = "SINGLE" },
        }, 1000)
        local ack_bad = tx[#tx].payload.payload
        assert_eq(ack_bad.status, "SCHEMA_INVALID")
        assert_true(string.find(tostring(ack_bad.reason), "CP#2", 1, true) ~= nil)

        -- 2. Valid /disk path without .json suffix -> ACCEPTED
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "/disk/disk_sortie", executionMode = "SINGLE" },
        }, 1100)
        assert_eq(tx[#tx].payload.payload.status, "ACCEPTED")
        assert_eq(eng.state, "EN_ROUTE")

        -- 3. Failed forceRestart targeting bad_schema must NOT stop active DISK_SORTIE
        arb:handle_gcs_packet({
            ver = "1.9.5", type = "MSG_MISSION_CMD",
            payload = { action = "RUN", missionName = "/disk/bad_schema.json", forceRestart = true },
        }, 1200)
        assert_eq(tx[#tx].payload.payload.status, "SCHEMA_INVALID")
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.missionId, "DISK_SORTIE")

        fs.delete("/disk/bad_schema.json")
        fs.delete("/disk/disk_sortie.json")
    end)
```

- [ ] **Step 2: Run unit tests to verify they fail**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --filter external_loader --clean-orphans; if ($?) { python tools/run_unit_tests.py --target 3_planning/amm --filter c2_arbiter --clean-orphans }
```
Expected: FAIL (`attempt to call field 'resolve_path' (a nil value)` and `"FILE_NOT_FOUND"` instead of `"SCHEMA_INVALID"`).

- [ ] **Step 3: Implement `resolve_path`, `list_mission_files`, `validate_mission_table`, and `c2_arbiter` `SCHEMA_INVALID` ACK mapping**

1. **`src/3_planning/amm/modules/mission_engine.lua`**:
   - Add `extract_target_pos(p)`: returns `p.targetPos` if `is_pos_xz(p.targetPos)`, else if `is_finite(p.x) and is_finite(p.z)` normalizes and assigns `p.targetPos = { x = p.x, z = p.z }` inside `validate_fly_over`, `validate_fly_to`, and `validate_orbit`.
   - Implement `mission_engine.resolve_path(spec, fs_api)`:
     - Reject non-string, `""`, or `string.find(spec, "%.%.")` with `nil, "INVALID_PATH"`.
     - Build candidate paths in strict §6.6.1 priority: (1) `spec`, (2) `spec .. ".json"` (if not ending in `%.json$`), (3) `"missions/" .. spec` & `".json"`, (4) `"/disk/" .. spec` & `".json"`, (5) `"/disk/missions/" .. spec` & `".json"` (skipping prefixes when `spec` already starts with `"/"`).
     - Return first candidate where `fs_obj.exists(cand) and not (fs_obj.isDir and fs_obj.isDir(cand))`, else `nil, "FILE_NOT_FOUND"`.
   - Implement `mission_engine.list_mission_files(fs_api)`: scan `"missions"`, `"/disk"`, `"/disk/missions"` for non-directory `*.json` files, format `missions/<name>` as `<name>` and `/disk/...` without `.json`, deduplicate, and sort.
   - Implement `mission_engine.validate_mission_table(tbl, opts)` using modular helper functions (`<= 40` lines each):
     - Check `type(tbl) == "table"`, `executionMode` (`"SINGLE"`/`"REPEAT"`), `fallbackPolicy` (`"RTH"`/`"HOVER_HOLD"`/`"LOITER"`/`"SKIP_NEXT"`).
     - Validate non-empty `checkpoints` (or legacy `items` with finite `x`, `z`), returning `false, "SCHEMA_INVALID", "EMPTY_CHECKPOINTS"` if empty.
     - Validate every `CP#<idx>`: `action` in `mission_engine.ACTION_TAXONOMY`, `SCHEMA_PARAM_CHECKS[cp.action]` (allowing shorthand `x`/`z` on `FLY_OVER`/`FLY_TO`/`ORBIT`, requiring `poiPos` or `targetPos` on `POI_HOLD` — while ensuring `targetPos` / `poiPos` numeric validity when present — and checking `ORBIT` `radius > 0`, `PATROL` `waypoints` non-empty, `LAND_LAUNCHPAD` `facilityId` or `targetPos`, `PAYLOAD_ACTION` non-empty `command` + valid Zone 3 `20..29` / `Base+20..29`, `REDSTONE_ACTION` valid 6 `side`), `completeWhen` / `abortWhen` `logic` (`"ANY"`/`"ALL"`) + `condition_evaluator.CONDITION_TYPES`, and `onEnter` / `onExit` / `onAbort` + `hook_runner.VALID_HOOK_TYPES`.
   - Add `mission_engine.preflight_file(spec, opts, fs_api)`: resolve via `resolve_path`, open/parse JSON (`nil, "PARSE_ERROR"` if invalid JSON), run `validate_mission_table` (`nil, "SCHEMA_INVALID", detail` if invalid), and unless `opts and opts.allowDeferred` reject deferred actions (`nil, mission_engine.DEFERRED_ERROR`); returns `data, nil, nil` without mutating any engine instance.
   - Update `mission_engine:load(spec, fs_api)` to delegate to `mission_engine.preflight_file(spec, self_opts, fs_api)` and then `self:load_table(data)`.

2. **`src/3_planning/amm/modules/c2_arbiter.lua`**:
   - Require `mission_engine = require("mission_engine")` at module top (zero circular dependency since `mission_engine.lua` never requires `c2_arbiter`).
   - Remove hardcoded `normalize_mission_path` and map load errors via `LOAD_ERR_TO_ACK`:
     - `"INVALID_PATH"` -> `"INVALID_CMD"`
     - `"FILE_NOT_FOUND"` -> `"FILE_NOT_FOUND"`
     - `"SCHEMA_INVALID"`, `"PARSE_ERROR"` -> `"SCHEMA_INVALID"`
     - `"DEFERRED_ACTION_UNSUPPORTED"` -> `"DEFERRED_ACTION_UNSUPPORTED"`
   - In `handle_cmd_run`: check `BUSY_REJECTED` first; if `p.missionName` is present, call `mission_engine.preflight_file(p.missionName, { baseChannel = eng.baseChannel })` **before** `eng:stop(now_ms)` so a failed `forceRestart` never aborts an active mission or fires `onAbort` on bad target files. Only after preflight succeeds (or when `p.forceRestart` restarts an already-loaded mission with `p.missionName == nil`), call `eng:stop(now_ms)` if `p.forceRestart` and `eng.state == "EN_ROUTE"`/`"SUSPENDED"`, then `eng:load_table(data)` + `eng:start(p.executionMode, now_ms)`.

- [ ] **Step 4: Run AMM unit tests and Lua 5.2 syntax verification**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --clean-orphans; if ($?) { python tools/validate_lua_syntax.py }
```
Expected: All `3_planning/amm` tests PASS, `validate_lua_syntax.py` reports 0 errors.

- [ ] **Step 5: Commit Task 1**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/modules/mission_engine.lua src/3_planning/amm/modules/c2_arbiter.lua tests/3_planning/amm/test_external_loader.lua tests/3_planning/amm/test_c2_arbiter.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): add multi-path resolver, preflight schema validator, and SCHEMA_INVALID ACK mapping (TASK-202-4)"
```

---

### Task 2: 51x19 TUI 6-Row Scroll Viewport + 5-Row Condition Progress Visualization (`ui_renderer.lua`)

**Files:**
- Modify: `src/3_planning/amm/modules/ui_renderer.lua:1-141`
- Modify: `tests/3_planning/amm/test_ui_renderer.lua:1-80`

**Interfaces:**
- Consumes:
  - `condition_evaluator.format_progress(cp, ctx, defaults) -> string`
  - Either `mission_engine` (`checkpoints`, `missionId`, `executionMode`, `state`, `active_index`, `enteredAtMs`, `defaults`, `patrolState`, `lastConditionSummary`) OR legacy `waypoint_queue` (`items`, `state`, `active_index`, `arrivalRadius`, `defaultAlt`, `defaultSpeed`)
  - `app_state` (`{ domainId, authority, banner, input_mode, input_buffer, now_ms }`)
- Produces:
  - `ui_renderer.compute_viewport(total, active_idx, window_size) -> integer, integer`
  - `ui_renderer.render_screen(buf, mfd_state, source_data, app_state)` (rendering rows `3..15` cols `27..51` per §5.1 with zero leftover characters and exact 51-char rows)

- [ ] **Step 1: Write the failing unit tests in `tests/3_planning/amm/test_ui_renderer.lua`**

Append to `tests/3_planning/amm/test_ui_renderer.lua` (inside `describe(...)`):
```lua
    it("computes centered 6-row viewport windows across boundary indices", function()
        local s0, e0 = ui_renderer.compute_viewport(0, 1, 6)
        assert_eq(s0, 1)
        assert_eq(e0, 0)

        local s1, e1 = ui_renderer.compute_viewport(4, 3, 6)
        assert_eq(s1, 1)
        assert_eq(e1, 4)

        local s_mid, e_mid = ui_renderer.compute_viewport(10, 6, 6)
        assert_eq(e_mid - s_mid + 1, 6)
        assert_true(s_mid <= 6 and 6 <= e_mid)

        local s_end, e_end = ui_renderer.compute_viewport(10, 10, 6)
        assert_eq(s_end, 5)
        assert_eq(e_end, 10)
    end)

    it("renders mission_engine 6-row scroll viewport, O/*/! markers, 5-row condition progress, and clears stale reused buffer cells", function()
        local mission_engine = require("mission_engine")
        local buf = ui_renderer.create_buffer(51, 19)
        local eng = mission_engine.new({ config = { baseChannel = 10000 } })

        local cps = {}
        for i = 1, 10 do
            if i == 1 then
                cps[i] = { checkpointId = "CP_01", action = "TAKEOFF_LAUNCHPAD", params = { facilityId = "PAD_BRAVO", targetAlt = 150 } }
            elseif i == 5 then
                cps[i] = { checkpointId = "CP_05", action = "PAYLOAD_ACTION", params = { channelOffset = 20, command = "DROP" } }
            elseif i == 6 then
                cps[i] = {
                    checkpointId = "CP_06",
                    action = "ORBIT",
                    params = { targetPos = { x = 450, z = -1200 }, targetAlt = 150, cruiseSpeed = 18, radius = 40, direction = "CW", durationSec = 30 },
                }
            else
                cps[i] = { checkpointId = "CP_" .. i, action = "FLY_OVER", params = { targetPos = { x = i * 100, z = -100 }, acceptanceRadius = 20 } }
            end
        end
        assert_true(eng:load_table({ missionId = "SORTIE_LONG_NAME_99", executionMode = "REPEAT", checkpoints = cps }))
        eng.state = "EN_ROUTE"
        eng.active_index = 6
        eng.enteredAtMs = 1000
        eng.checkpoints[1].status = "COMPLETED"
        eng.checkpoints[5].status = "ABORTED"
        eng.checkpoints[6].status = "ACTIVE"

        local mfd = {
            fsmState = "LOITER",
            dynamics = { altitudeY = 148.5, verticalSpeed = 0.1, groundSpeed = 18.0 },
            navigation = { currentPos = { x = 350, z = -1100 } },
            attitude = { pitch = 1.0, roll = 0.0, heading = 90.0 },
            fuel = 0.82,
        }
        ui_renderer.render_screen(buf, mfd, eng, { domainId = "AIRCRAFT_01", authority = "PILOT_PRIMARY", banner = "OK", input_mode = "NAV", now_ms = 13000 })

        -- Every row must strictly have 51 characters across text, fg, and bg
        for y = 1, 19 do
            assert_eq(string.len(buf.text[y]), 51, "text width mismatch at row " .. y)
            assert_eq(string.len(buf.fg[y]), 51, "fg width mismatch at row " .. y)
            assert_eq(string.len(buf.bg[y]), 51, "bg width mismatch at row " .. y)
        end

        assert_true(string.find(buf.text[3], "(6/10)", 1, true) ~= nil)
        -- Scroll viewport shows CP 5 ('!' aborted) and CP 6 ('*' active) inside rows 4..9
        local found_abort, found_active = false, false
        for r = 4, 9 do
            local right_slice = string.sub(buf.text[r], 27, 51)
            if string.find(right_slice, "! 5:PAYLD", 1, true) or string.find(right_slice, "!5:PAYLD", 1, true) then
                found_abort = true
            end
            if string.find(right_slice, "* 6:ORBIT", 1, true) or string.find(right_slice, "*6:ORBIT", 1, true) then
                found_active = true
            end
        end
        assert_true(found_abort, "Expected aborted marker ! on CP 5")
        assert_true(found_active, "Expected active marker * on CP 6")

        -- 5-row active checkpoint detail panel (rows 11..15)
        assert_true(string.find(buf.text[11], "EN_ROUTE", 1, true) ~= nil)
        assert_true(string.find(buf.text[11], "REPEAT", 1, true) ~= nil)
        assert_true(string.find(buf.text[12], "ORBIT", 1, true) ~= nil)
        assert_true(string.find(buf.text[13], "DUR 12/30s", 1, true) ~= nil)
        assert_true(string.find(buf.text[14], "150", 1, true) ~= nil)
        assert_true(string.find(buf.text[15], "141.4", 1, true) ~= nil)

        -- Re-render a 1-checkpoint mission on the SAME buffer -> rows 5..9 must be cleared (no ghost rows from 10-cp mission)
        local eng_short = mission_engine.new({ config = { baseChannel = 10000 } })
        assert_true(eng_short:load_table({
            missionId = "SHORT",
            checkpoints = { { action = "FLY_TO", params = { x = 10, z = 20 } } },
        }))
        ui_renderer.render_screen(buf, mfd, eng_short, { domainId = "AIRCRAFT_01", authority = "PILOT_PRIMARY", banner = "SHORT", input_mode = "NAV", now_ms = 1000 })
        for r = 5, 9 do
            assert_eq(string.sub(buf.text[r], 27, 51), string.rep(" ", 25), "Ghost text leaked at row " .. r)
        end
    end)
```

- [ ] **Step 2: Run the UI renderer unit test to verify it fails**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --filter ui_renderer --clean-orphans
```
Expected: FAIL (`attempt to call field 'compute_viewport' (a nil value)`).

- [ ] **Step 3: Implement `compute_viewport`, polymorphic mission pane, and 5-row detail panel in `src/3_planning/amm/modules/ui_renderer.lua`**

1. Require `condition_evaluator` at top of `src/3_planning/amm/modules/ui_renderer.lua`.
2. Add `ui_renderer.compute_viewport(total, active_idx, window_size)` (`window_size` default `6`):
   - If `total <= 0` return `1, 0`.
   - If `total <= window_size` return `1, total`.
   - Center `active_idx` (`start_i = math.max(1, act - math.floor((window_size - 1) / 2))`), clamp `if start_i + window_size - 1 > total then start_i = math.max(1, total - window_size + 1) end`, return `start_i, math.min(total, start_i + window_size - 1)`.
3. Implement `ACTION_SHORT` label table (`TAKEOFF_LAUNCHPAD = "TKOFF"`, `LAND_LAUNCHPAD = "LAND"`, `FLY_OVER = "FLYOV"`, `FLY_TO = "FLYTO"`, `ORBIT = "ORBIT"`, `PATROL = "PATROL"`, `POI_HOLD = "POIHLD"`, `PAYLOAD_ACTION = "PAYLD"`, `REDSTONE_ACTION = "RDSTN"`, plus deferred labels) and compact target formatter `format_cp_target(cp)`.
4. Implement polymorphic `render_mission_pane(buf, mfd, source, app)` using helper functions (`<= 40` lines each):
   - Detect `is_engine = type(source) == "table" and type(source.checkpoints) == "table"`.
   - Row 3 (col `27..51`, padded to `25`): `"[MISSION: " .. id .. "] (" .. disp .. "/" .. total .. ")"` (using `"[MSN:"` fallback if title exceeds 25 chars) for engine, or `"[MISSION QUEUE] (" .. disp .. "/" .. total .. ")"` for legacy queue.
   - Rows `4..9` (col `27..51`, padded to `25`): use `compute_viewport(total, active_idx, 6)`; draw `"*"` (`"4"` yellow), `"O"` (`"8"` lightGray), `"!"` (`"e"` red), or `" "` (`"0"` white); blank unused rows with `pad("", 25)`.
   - Row 10: col 26 `"|"`, col `27..51` `string.rep("-", 25)`.
   - Rows `11..15` (col `27..51`, padded to `25`):
     - Row 11: `STATE: <state> (<mode>)`
     - Row 12: `ACT  : <action detail>` (e.g. `ORBIT CW R:40m`, `PATROL (2/3) LOOP`, `PAYLD CH+20`, `RDSTN top EMIT`, or `NONE`)
     - Row 13: `COND : <progress>` via `condition_evaluator.format_progress(cp, { mfd = mfd, enteredAtMs = source.enteredAtMs, nowMs = app and app.now_ms }, source.defaults)` (or `RAD: <r>m` in legacy queue mode)
     - Row 14: `ALT/V: <alt>m / <spd>m/s`
     - Row 15: `DIST : <dist>m (RAD:<rad>m)` (computing 2D Euclidean distance from `mfd.navigation.currentPos` to active target or `PATROL` sub-waypoint, falling back to `mfd.navigation.distanceToWp` or `"---.-"`).
   - Clear left pane rows `12..15` (`draw_text(buf, y, 2, pad("", 24), "0", "f")`) in `render_hud_pane`.

- [ ] **Step 4: Run AMM unit tests and Lua 5.2 syntax verification**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --clean-orphans; if ($?) { python tools/validate_lua_syntax.py }
```
Expected: All `3_planning/amm` tests PASS (including existing `test_ui_renderer.lua` & `test_amm_integration.lua` and `0` `BLIT_LENGTH_MISMATCH` violations).

- [ ] **Step 5: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/modules/ui_renderer.lua tests/3_planning/amm/test_ui_renderer.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): add 6-row scroll viewport and 5-row condition progress TUI in ui_renderer (TASK-202-4)"
```

---

### Task 3: CLI Commands (`run`/`load`/`files`/`stop`/`next`/`mission`), Shell Boot Args & `file_transfer` Drag-and-Drop (`input_handler.lua`, `main.lua`)

**Files:**
- Modify: `src/3_planning/amm/modules/input_handler.lua:1-102`
- Modify: `src/3_planning/amm/main.lua:1-268`
- Modify: `tests/3_planning/amm/test_input_handler.lua:80-94`
- Modify: `tests/3_planning/amm/test_main_loop.lua:205-245`
- Modify: `TASK.md:72`
- Modify: `.agent/memory/workspace-root.md`

**Interfaces:**
- Consumes:
  - `mission_engine.resolve_path`, `mission_engine.list_mission_files`, `mission_engine.validate_mission_table` (Task 1)
  - `ui_renderer.render_screen` receiving `app.engine` (when `count() > 0`) and `app_state.now_ms` (Task 2)
- Produces:
  - `input_handler.VALID_COMMANDS` (16 canonical command keys)
  - `input_handler:handle_paste(text)` and `cmd.subcommand` / `cmd.subargs` / `cmd.known` on `parse_cli_command`
  - `main.parse_boot_args(arg1, arg2, arg3) -> string|nil, string|nil, string|nil`
  - `main.handle_file_transfer(app, transferred, now_ms) -> boolean, string|nil, string|nil`
  - `main.try_auto_start_mission(engine, auto_spec, now_ms, cfg, arbiter, mode_arg) -> boolean, string|nil, string|nil`
  - Updated `CLI_HANDLERS` (`run`, `load`, `files`, `stop`, `next`, `mission`, `add`, `goto`, `save`, `alt`, `spd`, `rad`) and `process_event` (`file_transfer`, `paste`)

- [ ] **Step 1: Write the failing unit tests in `tests/3_planning/amm/test_input_handler.lua` and `tests/3_planning/amm/test_main_loop.lua`**

Append to `tests/3_planning/amm/test_input_handler.lua` (inside `describe(...)`):
```lua
    it("parses v1.2.0 CLI commands (run, load, files, stop, next, mission subcommands) and handles paste in CLI mode", function()
        local h = input_handler.new()
        assert_true(input_handler.VALID_COMMANDS.run == true)
        assert_true(input_handler.VALID_COMMANDS.mission == true)
        assert_true(input_handler.VALID_COMMANDS.files == true)

        h:set_mode("CLI")
        h:handle_paste("mission run /disk/sortie_01 loop")
        local cmd_msn = h:handle_key(keys.enter or 28)
        assert_not_nil(cmd_msn)
        assert_eq(cmd_msn.name, "mission")
        assert_true(cmd_msn.known)
        assert_eq(cmd_msn.subcommand, "run")
        assert_eq(cmd_msn.subargs[1], "/disk/sortie_01")
        assert_eq(cmd_msn.subargs[2], "loop")

        h:set_mode("CLI")
        h.buffer = "files"
        local cmd_files = h:handle_key(keys.enter or 28)
        assert_eq(cmd_files.name, "files")
        assert_true(cmd_files.known)

        h:set_mode("CLI")
        h.buffer = "boguscmd"
        local cmd_unk = h:handle_key(keys.enter or 28)
        assert_eq(cmd_unk.name, "boguscmd")
        assert_false(cmd_unk.known)
    end)
```

Append to `tests/3_planning/amm/test_main_loop.lua` (inside `describe(...)`):
```lua
    it("executes run, load, files, stop, next, and mission CLI commands with PILOT_PRIMARY takeover and queue fallback", function()
        local main_mod = require("main")
        local mission_engine = require("mission_engine")
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local q = waypoint_queue.new({ defaultAlt = 150, defaultSpeed = 18, arrivalRadius = 15 })
        local eng = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        local arb = c2_arbiter.new(q, net, { baseChannel = 10000 }, eng)
        local inp = input_handler.new()
        local app = { config = { domainId = "AIRCRAFT_01", baseChannel = 10000 }, queue = q, net = net, engine = eng, arbiter = arb, input = inp, now_ms = 1000 }

        if not fs.exists("/disk") then fs.makeDir("/disk") end
        local f = fs.open("/disk/cli_sortie.json", "w")
        f.write(textutils.serializeJSON({
            missionId = "CLI_SORTIE",
            checkpoints = {
                { checkpointId = "CP_1", action = "FLY_OVER", params = { x = 100, z = 200 } },
                { checkpointId = "CP_2", action = "ORBIT", params = { x = 300, z = 400, radius = 35 } },
            },
        }))
        f.close()

        -- 1. files lists /disk/cli_sortie
        main_mod.execute_cli_command(app, { type = "COMMAND", name = "files", args = {} }, 1000)
        assert_true(string.find(arb.lastBanner, "/disk/cli_sortie", 1, true) ~= nil)

        -- 2. load resolves /disk/cli_sortie without .json and leaves engine IDLE
        main_mod.execute_cli_command(app, { type = "COMMAND", name = "load", args = { "/disk/cli_sortie" } }, 1050)
        assert_eq(eng.state, "IDLE")
        assert_eq(eng.missionId, "CLI_SORTIE")

        -- 3. GCS_OVERRIDE followed by mission run loop -> PILOT_PRIMARY takeover + REPEAT execution
        arb.authority = "GCS_OVERRIDE"
        eng.authority = "GCS_OVERRIDE"
        main_mod.execute_cli_command(app, { type = "COMMAND", name = "mission", args = { "run", "/disk/cli_sortie", "loop" } }, 1100)
        assert_eq(arb.authority, "PILOT_PRIMARY")
        assert_eq(eng.authority, "PILOT_PRIMARY")
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.executionMode, "REPEAT")
        assert_eq(eng.active_index, 1)

        -- 4. next advances to CP 2; stop aborts cleanly
        main_mod.execute_cli_command(app, { type = "COMMAND", name = "next", args = {} }, 1200)
        assert_eq(eng.active_index, 2)
        main_mod.execute_cli_command(app, { type = "COMMAND", name = "stop", args = {} }, 1300)
        assert_eq(eng.state, "ABORTED")

        -- 5. run with no args when only legacy queue has items -> migrates and starts engine
        local eng_q = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        local q2 = waypoint_queue.new({ defaultAlt = 150, defaultSpeed = 18, arrivalRadius = 15 })
        q2:add(50, 60)
        local arb2 = c2_arbiter.new(q2, net, { baseChannel = 10000 }, eng_q)
        local app2 = { config = { baseChannel = 10000 }, queue = q2, net = net, engine = eng_q, arbiter = arb2, input = inp, now_ms = 2000 }
        main_mod.execute_cli_command(app2, { type = "COMMAND", name = "run", args = {} }, 2000)
        assert_eq(eng_q.state, "EN_ROUTE")
        assert_eq(eng_q:count(), 1)

        fs.delete("/disk/cli_sortie.json")
    end)

    it("handles file_transfer drops safely across IDLE, autoRunDroppedFile, EN_ROUTE, and invalid payloads", function()
        local main_mod = require("main")
        local mission_engine = require("mission_engine")
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local m = mock.modem({ wireless = true })
        net:bind_modem(m)
        local q = waypoint_queue.new({ defaultAlt = 150, defaultSpeed = 18, arrivalRadius = 15 })
        local eng = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        local arb = c2_arbiter.new(q, net, { baseChannel = 10000 }, eng)
        local inp = input_handler.new()

        local function make_transfer(name, body)
            local closed = false
            return {
                getFiles = function()
                    return {
                        {
                            getName = function() return name end,
                            readAll = function() return body end,
                            close = function() closed = true end,
                        },
                    }
                end,
                isClosed = function() return closed end,
            }
        end

        local valid_json = textutils.serializeJSON({
            missionId = "DROPPED_01",
            checkpoints = { { checkpointId = "CP_1", action = "FLY_TO", params = { x = 250, z = -350 } } },
        })
        local app = {
            config = { domainId = "AIRCRAFT_01", baseChannel = 10000, autoRunDroppedFile = false },
            queue = q, net = net, engine = eng, arbiter = arb, input = inp, now_ms = 1000,
        }

        -- 1. Drop valid file while IDLE (autoRunDroppedFile = false) -> saves and loads IDLE
        main_mod.process_event(app, "file_transfer", make_transfer("dropped_01.json", valid_json))
        assert_true(fs.exists("missions/dropped_01.json"))
        assert_eq(eng.missionId, "DROPPED_01")
        assert_eq(eng.state, "IDLE")
        assert_true(string.find(arb.lastBanner, "DROP LOADED", 1, true) ~= nil)

        -- 2. Drop invalid JSON with same name -> DROP FAIL without overwriting existing valid file!
        main_mod.process_event(app, "file_transfer", make_transfer("dropped_01.json", "{invalid-json"))
        assert_true(string.find(arb.lastBanner, "DROP FAIL", 1, true) ~= nil)
        local check_f = fs.open("missions/dropped_01.json", "r")
        local preserved = check_f.readAll()
        check_f.close()
        assert_true(string.find(preserved, "DROPPED_01", 1, true) ~= nil)

        -- 3. Drop with autoRunDroppedFile = true while IDLE -> auto starts EN_ROUTE
        app.config.autoRunDroppedFile = true
        local valid2 = textutils.serializeJSON({
            missionId = "DROPPED_02",
            checkpoints = { { checkpointId = "CP_A", action = "FLY_OVER", params = { x = 10, z = 20 } } },
        })
        main_mod.process_event(app, "file_transfer", make_transfer("dropped_02.json", valid2))
        assert_eq(eng.missionId, "DROPPED_02")
        assert_eq(eng.state, "EN_ROUTE")

        -- 4. Drop valid file while EN_ROUTE -> saves to disk only, active flight stays DROPPED_02!
        local valid3 = textutils.serializeJSON({
            missionId = "DROPPED_03",
            checkpoints = { { checkpointId = "CP_B", action = "FLY_OVER", params = { x = 99, z = 99 } } },
        })
        main_mod.process_event(app, "file_transfer", make_transfer("../escape/dropped_03.json", valid3))
        assert_true(fs.exists("missions/dropped_03.json"))
        assert_eq(eng.missionId, "DROPPED_02")
        assert_eq(eng.state, "EN_ROUTE")
        assert_true(string.find(arb.lastBanner, "DROP SAVED", 1, true) ~= nil)

        fs.delete("missions/dropped_01.json")
        fs.delete("missions/dropped_02.json")
        fs.delete("missions/dropped_03.json")
    end)

    it("disambiguates shell boot arguments from config paths and auto-starts /disk missions in REPEAT mode", function()
        local main_mod = require("main")
        local mission_engine = require("mission_engine")
        local cfg_p, msn_p, mode_p = main_mod.parse_boot_args("config/amm_config.json", "/disk/sortie_01", "loop")
        assert_eq(cfg_p, "config/amm_config.json")
        assert_eq(msn_p, "/disk/sortie_01")
        assert_eq(mode_p, "loop")

        local cfg_d, msn_d, mode_d = main_mod.parse_boot_args("/disk/boot_sortie.json", "loop")
        assert_nil(cfg_d)
        assert_eq(msn_d, "/disk/boot_sortie.json")
        assert_eq(mode_d, "loop")

        if not fs.exists("/disk") then fs.makeDir("/disk") end
        local f = fs.open("/disk/boot_sortie.json", "w")
        f.write(textutils.serializeJSON({
            missionId = "BOOT_SORTIE",
            executionMode = "SINGLE",
            checkpoints = { { checkpointId = "CP_1", action = "FLY_OVER", params = { x = 10, z = 20 } } },
        }))
        f.close()

        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local eng = mission_engine.new({ net = net, config = { baseChannel = 10000 } })
        local ok = main_mod.try_auto_start_mission(eng, msn_d, 1000, {}, nil, mode_d)
        assert_true(ok)
        assert_eq(eng.missionId, "BOOT_SORTIE")
        assert_eq(eng.state, "EN_ROUTE")
        assert_eq(eng.executionMode, "REPEAT")

        fs.delete("/disk/boot_sortie.json")
    end)
```

- [ ] **Step 2: Run the input handler and main loop tests to verify they fail**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --filter input_handler --clean-orphans; if ($?) { python tools/run_unit_tests.py --target 3_planning/amm --filter main_loop --clean-orphans }
```
Expected: FAIL (`VALID_COMMANDS` nil, `parse_boot_args` nil, `file_transfer` ignored, `files`/`run`/`stop`/`next`/`mission` missing).

- [ ] **Step 3: Implement CLI parsing extensions in `input_handler.lua` and CLI/boot/file-drop pipelines in `main.lua`**

1. **`src/3_planning/amm/modules/input_handler.lua`**:
   - Define `input_handler.VALID_COMMANDS` with all 16 commands (`run`, `stop`, `next`, `files`, `mission`, `add`, `del`, `clear`, `goto`, `pause`, `resume`, `save`, `load`, `alt`, `spd`, `rad`).
   - In `parse_cli_command(line)`: set `known = (input_handler.VALID_COMMANDS[cmd_name] == true)` and when `cmd_name == "mission"`, set `subcommand = string.lower(parts[1] or "status")` and `subargs` (array slice from index 2).
   - Add `input_handler:handle_paste(text)` appending `tostring(text or "")` when `self.mode == "CLI"`.
   - Update `handle_key` backspace lookup to `(keys and (keys.backspace or keys.backSpace)) or 14`.

2. **`src/3_planning/amm/main.lua`**:
   - Add `autoStartMission = nil`, `autoExecutionMode = nil`, `autoRunDroppedFile = false` to `load_config` defaults.
   - Implement `parse_boot_args(arg1, arg2, arg3)` distinguishing `"*amm_config.json"` / `"^config/"` from direct mission specs (`"/disk/sortie_01.json"`, `"sortie_01"`).
   - Update `try_auto_start_mission(engine, auto_spec, now_ms, cfg, arbiter, mode_arg)`: resolve string paths via `mission_engine.resolve_path`, validate tables via `mission_engine.validate_mission_table`, map `"loop"`/`"repeat"` -> `"REPEAT"` and `"single"` -> `"SINGLE"`, report `"BOOT FAIL: ..."` on error, and start engine on success.
   - Implement `handle_file_transfer(app, transferred, now_ms)`: iterate `transferred.getFiles()`, reject non-`.json` / invalid JSON / `validate_mission_table` errors without writing to disk (`DROP FAIL: <detail>`), sanitize basename with `fs.getName` + `".."` rejection, write valid JSON to `"missions/" .. safe_name`, save-only if `EN_ROUTE`/`SUSPENDED` (`DROP SAVED: <name> (USE 'run <name>')`), or load (`DROP LOADED: <name>`) and start if `app.config.autoRunDroppedFile == true` (`DROP RUNNING: <name>`).
   - Update `CLI_HANDLERS` (`<= 30` lines per handler):
     - `run`: support `run`, `run loop`, `run <spec>`, `run <spec> loop` (using `resolve_path` + `eng:load` + `eng:start`, or converting `app.queue.items` if `eng:count() == 0 and queue:count() > 0`).
     - `load`: use `resolve_path` + `eng:load`, banner `"LOADED: ..."` or `"LOAD FAIL: <detail>"`.
     - `files`: call `mission_engine.list_mission_files()`, banner `"FILES: ..."`.
     - `stop`: call `app.engine:stop(now_ms)` (and pause/suspend `app.queue` if present), banner `"MISSION STOPPED"`.
     - `next`: call `app.engine:skip_next(now_ms)`, banner `"NEXT CP: ..."` / `"MISSION COMPLETE"` / `"NEXT FAIL: ..."`.
     - `mission`: dispatch `MISSION_SUBCOMMANDS` (`run`, `load`, `list`, `stop`, `next`, `status`).
     - `add`, `goto`, `save`, `alt`, `spd`, `rad`: keep `app.queue` working and keep `app.engine` synced (`save` avoids prefixing `"missions/"` when path already contains `"/"`).
   - In `execute_cli_command(app, cmd, now_ms)`: restore `PILOT_PRIMARY` authority on `app.arbiter` and `app.engine` before dispatch (§8.2 Pilot Takeover), and display `"UNKNOWN CMD: " .. tostring(cmd.name)` if unknown.
   - In `handle_timer_event`: pass `(app.engine and app.engine:count() > 0) and app.engine or app.queue` plus `now_ms = now_ms` to `ui_renderer.render_screen`.
   - In `process_event`: route `ev == "file_transfer"` to `handle_file_transfer(app, p1, now_ms)` and `ev == "paste"` to `app.input:handle_paste(p1)`.
   - Update `main_loop(...)` to accept variadic shell args via `parse_boot_args(...)`, pass `boot_spec or cfg.autoStartMission` and `boot_mode or cfg.autoExecutionMode` to `try_auto_start_mission(...)`, and preserve the bottom-of-file auto-run guard (`pcall(main_loop, ...)`).
   - Export `handle_file_transfer` and `parse_boot_args` in `main.lua` return table.

- [ ] **Step 4: Run full verification suite across unit, E2E, mutation, harness, manifest, specs, and Lua syntax**

Run:
```powershell
python tools/run_unit_tests.py --require-tests --clean-orphans; if ($?) { python tools/run_e2e_tests.py --clean-orphans }; if ($?) { python tools/run_mutation_tests.py }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python tools/verify_all_specs.py --check-readmes }; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/validate_lua_syntax.py }
```
Expected:
- `run_unit_tests.py`: 12 targets PASS (all existing + new `3_planning/amm` tests passing, 0 `BLIT_LENGTH_MISMATCH` / `EVENT_SWALLOW_VIOLATION`)
- `run_e2e_tests.py`: 7 scenarios `8/8 PASS`
- `run_mutation_tests.py`: `25/25 KILLED (100.0%)` (including `MUT-04`, `MUT-05`)
- `tests/harness`: `82 tests OK`
- `verify_manifest_sync.py`: `0 Errors, 0 Warnings`
- `verify_all_specs.py --check-readmes`: `0 Errors, 0 Warnings`
- `verify_spec_status.py`: PASS (`9 Implemented, 6 Approved` — `AMM_PROGRAM_SPECIFICATION.md` stays `Approved` until `TASK-202-5`)
- `validate_lua_syntax.py`: all Lua files PASS

- [ ] **Step 5: Sync `TASK.md` (`TASK-202-4` -> `[x]`) and `.agent/memory/workspace-root.md`, verify context docs, and commit Task 3**

1. Update `TASK.md` `TASK-202-4` to `[x]` with completion date and measured test counts.
2. Prepend a `## 2026-11-11 — ... (TASK-202-4)` entry in `.agent/memory/workspace-root.md`.
3. Run:
   ```powershell
   python tools/verify_context_docs.py
   ```
   Expected: `[PASS] context docs: 0 findings`
4. Commit:
   ```powershell
   & "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/modules/input_handler.lua src/3_planning/amm/main.lua tests/3_planning/amm/test_input_handler.lua tests/3_planning/amm/test_main_loop.lua TASK.md .agent/memory/workspace-root.md
   & "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): wire CLI commands, boot args, and file_transfer hot-injection (TASK-202-4)"
   ```
