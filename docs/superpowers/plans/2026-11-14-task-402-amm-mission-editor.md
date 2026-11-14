# AMM WebUI Mission Editor (`TASK-402`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Isolated HTML Skills:** When implementing or reviewing `tools/amm_mission_editor.html`, apply `.agent/skills/frontend-design/SKILL.md` and `.agent/skills/web-design-guidelines/SKILL.md` (offline ruleset `.agent/skills/web-design-guidelines/references/command.md`).

**Goal:** Build `tools/amm_mission_editor.html` as a zero-install, offline `file://` single-file HTML5/CSS/Vanilla JS mission authoring tool matching `AMM v2.0.1` (`ACT_*`/`DEC_*`/`MAC_*`, 19 `preconditions`, 14 conditions, 4 hooks, 2D `(X, Z)` canvas + collapsible `120px` `#altProfilePane`), verified by automated Node/Python unit tests and CraftOS-PC `mission_engine` roundtrip tests.

**Architecture:** `tools/amm_mission_editor.html` structures a single `<script>` block into 9 non-polluting IIFE/namespace modules (`SchemaConstants`, `MacroExpander`, `DefaultResolver`, `Validator`, `Store`, `CanvasRenderer`, `InspectorUI`, `JsonIO`, `AppBootstrap`) driving a fixed `100vh` Flexbox Column shell (`.app-shell`), with a read-only/test API exposed on `window.__AMM_EDITOR__` for automated Node `vm` + CraftOS-PC roundtrip verification in `tests/3_planning/amm/test_amm_mission_editor.py`.

**Tech Stack:** Single-file HTML5 + CSS3 + Vanilla ES2020 JavaScript (`file://` offline), Python 3 `unittest` + Node.js (`vm` module for script extraction & Canvas/DOM shim tests) + CraftOS-PC headless Lua roundtrip against `src/3_planning/amm/modules/mission_engine.lua` and `action_registry.lua`.

**Spec:** `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.3.1 Draft`; promote to `Approved` in Task 1 before authoring `tools/amm_mission_editor.html`).

## Global Constraints

- Zero-install single-file `.html` (`tools/amm_mission_editor.html`, inline `<style>` + `<script>`); opens directly via `file://` with zero build step, zero npm runtime deps, zero local HTTP server.
- Zero external network calls: `0` occurrences of `http://`, `https://`, `<script src>`, `<link href>`, `fetch()`, `XMLHttpRequest`, or `WebSocket`.
- DOM XSS safety: render all untrusted mission JSON strings (`missionId`, `description`, `checkpointId`, `facilityId`, `command`, `message`, errors) strictly via `document.createElement` + `textContent` (or `.value`), never `innerHTML` / `insertAdjacentHTML`.
- No native browser dialogs (`window.alert`, `window.confirm`, `window.prompt` banned); use `#exportConfirmModal` (`role="dialog"`, `aria-modal="true"`) and `#toastContainer` (`aria-live="polite"`).
- Ecosystem hygiene: `0` occurrences of Valkyrien Skies (`vs_`, `valkyrien`), `kontraption:`, or legacy `[DEPRECATED - v2.0.0]` action symbols (`FLY_OVER`, `FLY_TO`, `ORBIT`, `PATROL`, `POI_HOLD`, `TAKEOFF_LAUNCHPAD`, `LAND_LAUNCHPAD`, `PAYLOAD_ACTION`, `REDSTONE_ACTION`, `TAKEOFF_RUNWAY`, `LAND_RUNWAY`, `DOCK_ARM`, `UNDOCK_ARM`, `convertLegacyItems`).
- Visual & Web Interface Guidelines: `color-scheme: dark`, `<meta name="theme-color" content="#0b0f17">`, explicit `<select>` dark colors, 4-step type scale (`11/12/13/14px`, `line-height: 1.4`), `2px/4px/6px` radii with `1px solid #2b394e` hairlines, zero `transition: all`, `@media (prefers-reduced-motion: reduce)`, `overscroll-behavior: contain` on drawers/modals, `pointer: fine` `overscroll-behavior: none` on `<html>`, `user-select: none` during active drags, never block `paste`, `:focus-visible` `2px solid #22d3ee`, `<button type="button">` for all actions.
- Exact `AMM v2.0.1` schema baseline: export always outputs `"version": "2.0.0"`, `defaults` (`cruiseSpeed: 18.0`, `targetAlt: 150.0`, `acceptanceRadius: 15.0`, `headingMode: "AUTO"`), `executionMode: "SINGLE"|"REPEAT"`, `fallbackPolicy: "RTH"|"HOVER_HOLD"|"LOITER"|"SKIP_NEXT"`.

## Review Focus

- **Legacy `v1.0.0` `items[]` / 13 deprecated actions vs `params.{x, z}` shortcut**: importing `items[]` or any of the 13 legacy actions must fail with `ERROR` (`SCHEMA_INVALID` / `EMPTY_CHECKPOINTS` / `UNKNOWN_ACTION`) without auto-conversion, whereas `params.{x, z}` without `params.targetPos` on a `v2.0.0` checkpoint must promote to `params.targetPos = { x, z }` and strip `x`/`z`. (Pinned in Task 2 & Task 4 tests.)
- **Empty condition group omission trap (`conditions: []`)**: onboarding Lua `condition_evaluator.evaluate_group` returns `false` (not default) on explicit `conditions: []`; `exportJson()` must omit `completeWhen`/`abortWhen` when `conditions.length === 0`, while `validateMission()` must flag imported explicit `conditions: []` as `ERROR` (`EMPTY_CONDITION_GROUP`). (Pinned in Task 3 & Task 4 tests.)
- **DOM XSS injection via imported JSON strings**: importing `<img src=x onerror=window.__XSS=1>` inside `missionId`, `checkpointId`, `command`, `hooks.onEnter[0].message`, and Raw JSON drawer must render as literal text without invoking `innerHTML` or creating injected element nodes. (Pinned in Task 6 tests.)
- **Asymmetric runtime keys (`TIMEOUT_SEC.timeout`, `MAC_CARGO_SORTIE.payload/awaitAck`, `ZONE3_PAYLOAD_CMD.payload`, `targetAirframe`-dependent `MAC_SHIP_RECOVERY`)**: `TIMEOUT_SEC` must use `timeout` (not `timeoutSec`), `MAC_CARGO_SORTIE` must use `payload`/`awaitAck`, `ACT_PAY_BUS_CMD` uses `commandPayload`/`waitForAck`, `ZONE3_PAYLOAD_CMD` hook uses `hook.payload`, and `MAC_SHIP_RECOVERY` expansion inserts `ACT_TKL_TRANS_FW2MC` only when `ui.targetAirframe === "WINGED_VTOL"`. (Pinned in Task 2, Task 3, & Task 7 CraftOS-PC roundtrip tests.)
- **Single Undo snapshot on pointer drags & destructive replacements**: dragging a 2D canvas node (`CP`/`POI`/`CORRIDOR_END`) or `#altProfilePane` node across 20+ `mousemove` events must push exactly `1` Undo snapshot on `mousedown`, and `Presets`/`Import`/`Apply JSON`/`Expand Now` must push an Undo snapshot so `Ctrl+Z` restores the prior mission. (Pinned in Task 4 & Task 5 tests.)

---

## File Structure

- **Modify:** `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` — promote `Draft` → `Approved` in Task 1 (pre-implementation gate) and `Approved` → `Implemented` in Task 7.
- **Modify:** `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` — promote `Approved` → `Implemented` in Task 7 after `TASK-402` full pass.
- **Create:** `tools/amm_mission_editor.html` — self-contained offline single-file HTML5/CSS/Vanilla JS mission editor (9 IIFE modules + `window.__AMM_EDITOR__` hook).
- **Create:** `tests/3_planning/amm/test_amm_mission_editor.py` — automated Python `unittest` suite driving Node.js (`vm` extraction + Canvas/DOM shims), static security/CSS/guideline assertions, and CraftOS-PC headless Lua roundtrip validation via `harness/`.
- **Modify:** `TASK.md`, `.agent/memory/workspace-root.md` — mark `TASK-402` complete and record handover entry in Task 7.

---

### Task 1: Pre-Implementation Spec Promotion & Node/Python Test Harness Bootstrap

**Files:**
- Modify: `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md:8-15`
- Create: `tests/3_planning/amm/test_amm_mission_editor.py`
- Create: `tools/amm_mission_editor.html` (minimal valid HTML shell with CSS token skeleton + empty 9 IIFE module exports on `window.__AMM_EDITOR__`)

**Interfaces:**
- Produces: `window.__AMM_EDITOR__ = { version, SchemaConstants, MacroExpander, DefaultResolver, Validator, Store, CanvasRenderer, InspectorUI, JsonIO, AppBootstrap }` in `tools/amm_mission_editor.html`; Python helper `load_editor_context(dom_overrides=None)` in `tests/3_planning/amm/test_amm_mission_editor.py`.

- [ ] **Step 1: Promote `AMM_MISSION_EDITOR_SPECIFICATION.md` status from `Draft` to `Approved`**

Update `| **문서 상태 (Status)** | \`Draft\` |` to `\`Approved\`` in `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (and `TASK.md` `TASK-402` reference `v0.3.1 Draft` → `v0.3.1 Approved`), then verify `python tools/verify_all_specs.py --check-readmes` reports `0 Errors, 0 Warnings`.

- [ ] **Step 2: Write the failing bootstrap test in `tests/3_planning/amm/test_amm_mission_editor.py`**

```python
import re
import shutil
import subprocess
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parents[3]
EDITOR_HTML = WORKSPACE_ROOT / "tools" / "amm_mission_editor.html"


class TestEditorBootstrap(unittest.TestCase):
    def test_single_file_exists_offline_and_exposes_nine_modules(self) -> None:
        self.assertTrue(EDITOR_HTML.is_file(), "tools/amm_mission_editor.html must exist")
        html = EDITOR_HTML.read_text(encoding="utf-8")
        self.assertIn('<meta name="theme-color" content="#0b0f17">', html)
        self.assertIn("color-scheme: dark", html)
        self.assertIsNone(re.search(r'https?://|fetch\s*\(|XMLHttpRequest|WebSocket', html))
        self.assertIsNone(re.search(r'\bwindow\.(alert|confirm|prompt)\s*\(', html))
        self.assertNotIn("transition: all", html)

        node = shutil.which("node")
        self.assertIsNotNone(node, "node executable is required for JS module tests")
        script_match = re.search(r"<script>([\s\S]*)</script>", html)
        self.assertIsNotNone(script_match, "inline <script> block missing")
        js_probe = (
            "const window = { addEventListener(){}, devicePixelRatio: 1 };\n"
            "const document = { addEventListener(){}, getElementById(){ return null; }, querySelectorAll(){ return []; } };\n"
            "const localStorage = { getItem(){ return null; }, setItem(){} };\n"
            + script_match.group(1)
            + "\nconst keys = Object.keys(window.__AMM_EDITOR__ || {});\n"
            + "console.log(JSON.stringify(keys));\n"
        )
        res = subprocess.run([node, "-e", js_probe], capture_output=True, text=True, check=True)
        modules = ["SchemaConstants", "MacroExpander", "DefaultResolver", "Validator", "Store", "CanvasRenderer", "InspectorUI", "JsonIO", "AppBootstrap"]
        for mod in modules:
            self.assertIn(mod, res.stdout)
```

- [ ] **Step 3: Run test to verify it fails**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py`
Expected: FAIL (`AssertionError: tools/amm_mission_editor.html must exist`).

- [ ] **Step 4: Create minimal `tools/amm_mission_editor.html` shell and `load_editor_context` helper**

Create `tools/amm_mission_editor.html` with:
- `<meta charset="utf-8">`, `<meta name="viewport" content="width=device-width, initial-scale=1">`, `<meta name="theme-color" content="#0b0f17">`, `<title>AMM Mission Editor</title>`.
- `<style>` declaring `:root` Industrial Avionics Dark Cockpit CSS variables (`--bg-app: #0b0f17` through `--accent-violet: #a78bfa`), `html { color-scheme: dark; }`, and `.app-shell` Flexbox Column skeleton.
- `<div class="app-shell">` containing minimal skeleton containers (`#recoveryBanner`, `header.top-header`, `nav.responsive-tabs`, `main.workspace-main`, `#altProfilePane`, `#rawJsonDrawer`, `footer.bottom-validation-bar`, `#actionPickerPopover`, `#exportConfirmModal`, `#toastContainer`).
- `<script>` with `"use strict";` and the 9 IIFE namespace stubs assigned to `window.__AMM_EDITOR__`.
Also extract a reusable `run_editor_js(js_tail, dom_setup="")` helper in `tests/3_planning/amm/test_amm_mission_editor.py` for Tasks 2–6.

- [ ] **Step 5: Run test to verify it passes**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py`
Expected: PASS (`Ran 1 test ... OK`).

- [ ] **Step 6: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md TASK.md tools/amm_mission_editor.html tests/3_planning/amm/test_amm_mission_editor.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "chore(amm-editor): approve v0.3.1 spec and bootstrap TASK-402 shell"
```

---

### Task 2: `SchemaConstants`, `DefaultResolver`, & `MacroExpander`

**Files:**
- Modify: `tools/amm_mission_editor.html` (`SchemaConstants`, `DefaultResolver`, `MacroExpander` IIFEs)
- Modify: `tests/3_planning/amm/test_amm_mission_editor.py`

**Interfaces:**
- Produces `SchemaConstants`:
  - `ACTIVE_ACTIONS` (36 exact `ACT_*` entries across `SYS`(6), `TKL`(6), `NAV`(6), `PAT`(5), `PAY`(4), `COM`(1), `MOB`(3), `FS`(5) with `domain`, `summary`, `spatial`, `defaultComplete`),
  - `DEFERRED_ACTIONS` (19 roadmap + 3 `TASK-401`: `ACT_PAY_CARGO_DROP`, `ACT_PAY_FIRE_CTRL`, `ACT_PAY_GEO_SCAN`),
  - `LEGACY_ACTIONS` (13 `[DEPRECATED - v2.0.0]` names),
  - `ACTIVE_DECORATORS` (6 `DEC_*` + `overrideSchema`), `DEFERRED_DECORATORS` (`DEC_TIME_CRIT`),
  - `ACTIVE_MACROS` (3 `MAC_*`), `DEFERRED_MACROS` (2 `MAC_*`),
  - `PRECONDITION_CATEGORIES` (4 categories, 19 exact keys matching `action_registry.lua:82-89`),
  - `CONDITION_TYPES` (14 types incl. `SYS_ARMED`, `IMMEDIATE`, `TIMEOUT_SEC.timeout`), `DEFERRED_CONDITIONS` (`ARM_DOCKED`, `ARM_RELEASED`),
  - `HOOK_TYPES` (4 types), `REDSTONE_SIDES` (6), `BUNDLED_COLORS` (16 `{ key, hex }`), `DEFAULTS_BASELINE` (`cruiseSpeed: 18.0`, `targetAlt: 150.0`, `acceptanceRadius: 15.0`, `headingMode: "AUTO"`).
- Produces `DefaultResolver`:
  - `resolveCheckpointDefaults(cp, missionDefaults)` → `{ targetAlt, cruiseSpeed, acceptanceRadius, headingMode, settleTicks }` (`ACT_NAV_SPLINE_WP`: `acceptanceRadius` default `15.0`, `settleTicks: 0`; `ACT_NAV_GOTO_WP`: `acceptanceRadius` default `5.0`, `settleTicks: 4`).
  - `computeBaseChannel(blockNum)` → `10000 + (blockNum - 1) * 40`; `resolveZone3Channel(offsetOrCh, baseCh)`.
- Produces `MacroExpander`:
  - `normalizeShortcutCoords(cp)` (promotes finite `params.x`/`params.z` to `params.targetPos` and deletes `x`/`z`),
  - `cleanActionSwitchParams(oldParams, nextAction)` (preserves valid shared `targetPos`, `targetAlt`, `cruiseSpeed` and drops stale action-specific keys),
  - `expandMacroCheckpoint(cp, targetAirframe)` (expands `MAC_RECON_ORBIT` 6 steps, `MAC_SHIP_RECOVERY` 4 or 5 steps adding `ACT_TKL_TRANS_FW2MC` iff `targetAirframe === "WINGED_VTOL"`, `MAC_CARGO_SORTIE` 5 steps carrying `payload`/`awaitAck`),
  - `extractExtras(raw, knownKeys)` / `mergeExtras(obj, extraMap)`.

- [ ] **Step 1: Write failing unit tests for `SchemaConstants`, `DefaultResolver`, and `MacroExpander`**

Add tests in `tests/3_planning/amm/test_amm_mission_editor.py`:
- `test_schema_counts_and_precondition_keys`: assert 36 active `ACT_*`, 22 deferred `ACT_*`, 13 legacy names, 6+1 `DEC_*`, 3+2 `MAC_*`, 19 precondition keys across 4 categories, 14 condition types (`TIMEOUT_SEC` uses `timeout`), 4 hook types, 16 bundled colors.
- `test_default_resolver_and_channel_math`: assert `ACT_NAV_SPLINE_WP` resolves `acceptanceRadius=15.0, settleTicks=0`; `ACT_NAV_GOTO_WP` resolves `acceptanceRadius=5.0, settleTicks=4`; `computeBaseChannel(1) === 10000`, `computeBaseChannel(3) === 10080`.
- `test_macro_expansion_airframe_and_cargo_keys`: assert `MAC_SHIP_RECOVERY` expands to 5 steps with `ACT_TKL_TRANS_FW2MC` for `"WINGED_VTOL"` and 4 steps without it for `"MULTICOPTER"`; `MAC_CARGO_SORTIE` preserves `payload` & `awaitAck`; `MAC_RECON_ORBIT` uses `DEC_SMOOTH_TRAJ` & `DEC_ENERGY_ECO`.
- `test_shortcut_coords_and_extras_preservation`: assert `params.{x:10, z:-20}` promotes to `params.targetPos = {x:10, z:-20}` and deletes `x`/`z`, while unknown `_customTag` survives `extractExtras` → `mergeExtras`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py`
Expected: FAIL (`TypeError` / `AssertionError` on stubbed modules).

- [ ] **Step 3: Implement `SchemaConstants`, `DefaultResolver`, and `MacroExpander` in `tools/amm_mission_editor.html`**

Populate all three IIFEs with exact tables and pure helper functions matching §5, §6, and `src/3_planning/amm/modules/action_registry.lua`. Keep `deepClone(val)` JSON-safe helper shared cleanly inside `<script>`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add tools/amm_mission_editor.html tests/3_planning/amm/test_amm_mission_editor.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm-editor): implement SchemaConstants, DefaultResolver, and MacroExpander"
```

---

### Task 3: `Validator` (Lua-Parity Preflight Schema Engine)

**Files:**
- Modify: `tools/amm_mission_editor.html` (`Validator` IIFE)
- Modify: `tests/3_planning/amm/test_amm_mission_editor.py`

**Interfaces:**
- Consumes: `SchemaConstants`, `DefaultResolver`.
- Produces `Validator.validateMission(mission, opts)` where `opts = { baseChannel?: number, targetAirframe?: string }` returning `{ valid: boolean, errors: ValidationIssue[], warnings: ValidationIssue[] }`.
- Every `ValidationIssue` has `{ severity, code, luaCode, cpIndex, checkpointId, fieldPath, message }` with fix-oriented `message` (e.g., `"POI position required — select PICK_POI tool or enter X/Z in Params."`).

- [ ] **Step 1: Write failing tests for all `Validator` error and warning codes**

Add tests in `tests/3_planning/amm/test_amm_mission_editor.py`:
- `test_validator_rejects_legacy_items_and_13_actions`: `raw.items = [...]` or `action: "FLY_OVER"` yields `valid === false` with `EMPTY_CHECKPOINTS` / `UNKNOWN_ACTION`.
- `test_validator_preconditions_static_and_19_keys`: valid 19 keys pass; `minAlt: 200, maxAlt: 100` or `disallowedAirframes: ["WINGED_VTOL"]` when `targetAirframe: "WINGED_VTOL"` triggers `ERROR` `PRECONDITION_STATIC_INVALID` (`fieldPath` points to `checkpoints[i].preconditions...`).
- `test_validator_splits_three_deferred_codes`: deferred `ACT_TKL_TAKEOFF_RWY` → `WARNING` `DEFERRED_ACTION_UNSUPPORTED`; `DEC_TIME_CRIT` → `WARNING` `DEFERRED_DECORATOR_UNSUPPORTED`; `MAC_PATROL_RADAR` → `WARNING` `DEFERRED_MACRO_UNSUPPORTED`; `ARM_DOCKED` condition → `WARNING` `DEFERRED_ACTION_UNSUPPORTED` (`valid === true`).
- `test_validator_action_condition_and_hook_edge_cases`: `ACT_PAT_POI_HOLD` missing `poiPos` (`MISSING_POI_POS`), `ACT_PAY_BUS_CMD` invalid `channelOffset` (`INVALID_ZONE3_CHANNEL`), `TIMEOUT_SEC` missing/negative `timeout` (`INVALID_CONDITION_PARAM`), explicit `completeWhen: { logic: "ALL", conditions: [] }` (`EMPTY_CONDITION_GROUP`), `ACT_PAT_LOITER_TIME` `radius: 3` (`WARNING` `ORBIT_RADIUS_BELOW_FCP_MIN`) + missing duration/completeWhen (`WARNING` `MISSING_DURATION_HOLD_MANUAL`), `ZONE3_PAYLOAD_CMD` missing `command` (`INVALID_HOOK_PARAM`), and latency `< 50ms` for 100-checkpoint mission.

- [ ] **Step 2: Run tests to verify they fail**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py`
Expected: FAIL.

- [ ] **Step 3: Implement `Validator` in `tools/amm_mission_editor.html`**

Implement `validateMission(mission, opts)` covering every `ERROR` and `WARNING` row in §7.2 of `AMM_MISSION_EDITOR_SPECIFICATION.md`, generating exact `fieldPath` strings (`defaults.*`, `checkpoints[i].params.*`, `checkpoints[i].decorators`, `checkpoints[i].preconditions.*`, `checkpoints[i].completeWhen.*`, `checkpoints[i].abortWhen.*`, `checkpoints[i].hooks.<phase>[j].*`) so Task 6 can map any clicked chip directly to the right inspector mode/tab/input.

- [ ] **Step 4: Run tests to verify they pass**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add tools/amm_mission_editor.html tests/3_planning/amm/test_amm_mission_editor.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm-editor): implement Lua-parity Validator engine"
```

---

### Task 4: `Store` & `JsonIO` (State, Undo/Redo, Presets, `localStorage` Autosave, `importJson`/`exportJson`)

**Files:**
- Modify: `tools/amm_mission_editor.html` (`Store` and `JsonIO` IIFEs)
- Modify: `tests/3_planning/amm/test_amm_mission_editor.py`

**Interfaces:**
- Consumes: `SchemaConstants`, `MacroExpander`, `DefaultResolver`, `Validator`.
- Produces `Store`:
  - `getState()`, `subscribe(fn)`, `mutate(fn, { recordUndo = true, label })`, `beginUndoTransaction()` / `commitUndoTransaction()` (for drag-start single snapshot), `undo()`, `redo()`, `setUi(patch)`, `loadPreset(presetKey)`, `expandSelectedMacro()`, `checkAutosaveDraft()`, `restoreAutosaveDraft()`, `dismissAutosaveDraft()`.
- Produces `JsonIO`:
  - `STARTER_PRESETS` (`MSN_RECON_001`, `CORRIDOR_PATROL`, `MAC_SHIP_RECOVERY`, `EMPTY_DRAFT`),
  - `importJson(rawTextOrObj)` (records Undo snapshot before replacing `mission`, blocks `items[]`/legacy 13 actions with `SCHEMA_INVALID` error without destroying prior Undo entry, promotes `params.{x,z}`, preserves `_extra`),
  - `buildExportObject(mission)` (forces `"version": "2.0.0"`, omits empty `description`, empty `decorators`, empty `completeWhen`/`abortWhen`, empty hook arrays, and strips UI-only `targetAirframe`/`aircraftBlockNumber` while merging `_extra`),
  - `exportJson(mission)` (2-space `JSON.stringify`).

- [ ] **Step 1: Write failing tests for `Store` and `JsonIO`**

Add tests in `tests/3_planning/amm/test_amm_mission_editor.py`:
- `test_store_undo_redo_depth_50_and_preset_import_recovery`: verify 55 mutations cap `undoStack` at 50; `loadPreset("CORRIDOR_PATROL")` and `importJson(...)` are immediately reversible via `Store.undo()` (`Ctrl+Z`).
- `test_json_io_omits_empty_groups_and_preserves_extras`: verify `buildExportObject` always emits `version: "2.0.0"`, omits `completeWhen`/`abortWhen` when `conditions.length === 0`, omits empty `decorators`/`hooks`/`description`, drops UI-only fields, and preserves `_extra` metadata at mission/defaults/checkpoint/params/condition/hook levels.
- `test_json_io_rejects_legacy_zero_fallback_and_handles_autosave`: verify `importJson('{"version":"1.0.0","items":[{"action":"FLY_OVER"}]}')` returns `{ ok: false, code: "SCHEMA_INVALID" }`, while valid JSON written to `localStorage["uafs_amm_editor_autosave_v1"]` triggers `checkAutosaveDraft()` and `restoreAutosaveDraft()`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py`
Expected: FAIL.

- [ ] **Step 3: Implement `Store` and `JsonIO` in `tools/amm_mission_editor.html`**

Implement `Store` (50-deep undo/redo, 500ms debounced `localStorage` under `uafs_amm_editor_autosave_v1` wrapped in `try/catch` for restricted `file://` contexts, `expandSelectedMacro()`) and `JsonIO` (4 starter presets, Zero-Fallback `importJson`, clean 2-space `exportJson`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add tools/amm_mission_editor.html tests/3_planning/amm/test_amm_mission_editor.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm-editor): implement Store state/undo/autosave and JsonIO"
```

---

### Task 5: `CanvasRenderer` (2D `(X, Z)` Tactical Canvas + Collapsible `#altProfilePane`)

**Files:**
- Modify: `tools/amm_mission_editor.html` (`CanvasRenderer` IIFE)
- Modify: `tests/3_planning/amm/test_amm_mission_editor.py`

**Interfaces:**
- Consumes: `SchemaConstants`, `DefaultResolver`, `Store`, `Validator`.
- Produces `CanvasRenderer`:
  - `worldToScreen(wx, wz, rect, canvasState)`, `screenToWorld(sx, sy, rect, canvasState)`, `snapCoord(val, gridSnapM, altKey)`,
  - `computeRepeatLoopTarget(checkpoints)` (skips `ACT_SYS_*`, `ACT_TKL_TAKEOFF_*`, `ACT_MOB_MOVING_TKOFF` matching `mission_engine.lua`),
  - `computeLabelStackOffsets(checkpoints, rect, canvasState)` (`15px` vertical step for coinciding `(X, Z)` coords),
  - `hitTestCanvas(sx, sy, state, rect)` (returns `{ kind: "CP" | "POI" | "CORRIDOR_END", index, field } | null` with `Selected-Node Priority` and `16px`/`15px`/`14px` radii + label box hit),
  - `renderCanvas(canvasEl, hudEls, state, validation)` (HiDPI `dpr` transform, 8 layers, empty-state vector hint),
  - `fitAll(state, rect)`, `bindCanvasEvents(canvasEl)`,
  - `renderAltProfile(altCanvasEl, state)` & `bindAltProfileEvents(altCanvasEl)` (`120px` collapsible `#altProfilePane`, `Seq #1..#N` X-axis, `5m` snap / `Alt` `1m` fine vertical drag for `params.targetAlt`, single Undo snapshot on `mousedown`).

- [ ] **Step 1: Write failing tests for `CanvasRenderer` geometry, hit-testing, `REPEAT` loop, and `#altProfilePane` drag**

Add tests in `tests/3_planning/amm/test_amm_mission_editor.py`:
- `test_canvas_affine_snap_and_label_stacking`: assert `worldToScreen` ↔ `screenToWorld` roundtrip within `1e-6`; `snapCoord(14.2, 10, false) === 10` and `snapCoord(14.2, 10, true) === 14.2`; two CPs at `(0, 0)` receive `0px` and `15px` label Y-offsets.
- `test_canvas_repeat_leg_and_hit_test_priority`: assert `computeRepeatLoopTarget` skips `ACT_SYS_ARM` and `ACT_TKL_TAKEOFF_VERT` and targets the first cruise/nav CP; when two nodes overlap, `hitTestCanvas` prioritizes `ui.selectedIndex`.
- `test_canvas_and_alt_profile_drag_push_single_undo`: simulate `mousedown` → 10 `mousemove`s → `mouseup` on a mock `<canvas>` context; assert `params.targetPos` and `params.targetAlt` (`5m` snap vs `Alt` `1m`) update cleanly while `undoStack.length` increases by exactly `1`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py`
Expected: FAIL.

- [ ] **Step 3: Implement `CanvasRenderer` (2D Tactical Canvas + `#altProfilePane`) in `tools/amm_mission_editor.html`**

Implement all 8 rendering layers, pointer state machine (`SELECT`, `ADD_SPLINE_WP`, `PICK_TARGET`, `PICK_POI`, wheel cursor-centered zoom `0.05..10.0 px/m`, middle/right/`Space+left` pan, `user-select: none` while dragging), `fitAll`, and the collapsible `120px` `#altProfilePane` renderer & vertical drag handler.

- [ ] **Step 4: Run tests to verify they pass**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add tools/amm_mission_editor.html tests/3_planning/amm/test_amm_mission_editor.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm-editor): implement 2D CanvasRenderer and collapsible Alt Profile pane"
```

---

### Task 6: CSS Design System, `InspectorUI`, & `AppBootstrap` (All 5 Zones, Drawers, Popover, Accessibility)

**Files:**
- Modify: `tools/amm_mission_editor.html` (`<style>`, HTML structure, `InspectorUI` & `AppBootstrap` IIFEs)
- Modify: `tests/3_planning/amm/test_amm_mission_editor.py`

**Interfaces:**
- Consumes: all 6 core modules (`SchemaConstants`..`CanvasRenderer`).
- Produces `InspectorUI`:
  - `renderAll(state, validation)`, `renderCheckpoints(state, validation)`, `renderInspector(state, validation)`, `renderValidationBar(state, validation)`, `renderRawJsonDrawer(state)`,
  - `openActionPicker(mode: "ADD" | "MACRO", triggerEl)` / `closeActionPicker()`,
  - `navigateToIssue(issue)` (selects `CP#idx`, centers 2D canvas, maps `issue.fieldPath` to `[Mission Settings]` or `[Checkpoint]` → `Params` | `Guards` | `Conditions` | `Hooks` and focuses the matching `[data-field-path]` element),
  - `showToast(message, kind)` (`aria-live="polite"`, active-voice copy), `openExportConfirmModal(errorCount, onConfirm)` (`role="dialog"`, `aria-modal="true"`, focus restore).
- Produces `AppBootstrap`:
  - `init()`, keyboard shortcut dispatcher (`Ctrl+Z`, `Ctrl+Y`/`Ctrl+Shift+Z`, `F`, `Delete`, `1/2/3`, `Escape`), window file `dragover`/`drop` handler, `MSN_RECON_001` initial load + `#recoveryBanner` check.

- [ ] **Step 1: Write failing DOM-shim integration & static CSS/accessibility tests**

Add tests in `tests/3_planning/amm/test_amm_mission_editor.py`:
- `test_html_css_guidelines_compliance`: verify `@media (max-width: 1150px)`, `@media (prefers-reduced-motion: reduce)`, `@media (pointer: fine)` `overscroll-behavior: none`, `overscroll-behavior: contain` on `.drawer`/`.modal`/`.popover`, `user-select: none`, `:focus-visible`, `min-width: 0`, explicit `<select>` dark styling, zero `transition: all`, zero `<div onclick=`/`<span onclick=` patterns.
- `test_dom_xss_safety_and_field_path_jump`: using a lightweight JS DOM shim in Node that records `innerHTML` setters (throwing if invoked!) and tracks `textContent`/`createElement`/`focus`, import a mission containing `<img src=x onerror=window.__XSS=1>` in `missionId`, `checkpointId`, `command`, and `hooks.onEnter[0].message`; assert zero `innerHTML` writes, literal `<img...` stored in `.textContent`/`.value`, and clicking a validation issue with `fieldPath: "checkpoints[0].hooks.onEnter[0].command"` switches `ui.activeRightMode = "CHECKPOINT"`, `ui.activeInspectorTab = "HOOKS"`, `ui.activeHookTab = "onEnter"`.
- `test_action_picker_and_empty_state_cta`: verify `#actionPickerPopover` filters by domain tab & query, inserting `MAC_SHIP_RECOVERY` keeps `action === "MAC_SHIP_RECOVERY"`, clicking `Expand Now` expands according to `ui.targetAirframe`, and `EMPTY_DRAFT` renders empty-state CTA buttons.

- [ ] **Step 2: Run tests to verify they fail**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py`
Expected: FAIL.

- [ ] **Step 3: Implement complete `<style>`, semantic HTML skeleton, `InspectorUI`, and `AppBootstrap` in `tools/amm_mission_editor.html`**

Build the complete Industrial Avionics Dark Cockpit stylesheet and DOM-safe UI:
- **Header (`52px`)**: Title, `Mission ID` (`translate="no"`, `spellcheck="false"`), `SINGLE`/`REPEAT` toggle, `Undo`/`Redo`, `Presets`, `Import .json`, `Raw JSON` toggle, `Copy JSON`, `Export .json`.
- **Left Rail (`300px`)**: `CHECKPOINTS (N)`, `+ Add`, `+ Macro`, empty-state CTA, drag-reorderable cards with `#k`, `checkpointId` (ellipsis truncation), domain/status badge, 1-line summary, `DEC`/`PRE`/`COND`/`HOOK` chips, `▲`/`▼`/Dup/Del `<button type="button">` controls.
- **`#actionPickerPopover`**: `role="dialog"`, `aria-modal="true"`, domain filter tabs (`ALL|SYS|TKL|NAV|PAT|PAY|COM|MOB|FS|MAC|DEFERRED`), search input (`placeholder="Search actions…"`), `[즉시]`/`[예약]` badges, Escape focus restoration.
- **Center Column**: Floating toolbar (`SELECT`, `ADD_SPLINE_WP`, `PICK_TARGET`, `PICK_POI`, `Grid Snap`, `Alt Profile`, `Fit All`, `Zoom +/-`), HUD overlay, 2D `<canvas>`, `#altProfilePane` (`120px`).
- **Right Inspector (`420px`)**: `[Checkpoint | Mission Settings]` switch; `Checkpoint` header (`checkpointId`, `action`, `fallbackPolicy`, `Expand Now` for `MAC_*`) + 4 tabs (`Params`, `Guards` [7 `DEC_*` w/ inline `overrideParams` + 4 collapsible `Preconditions` accordions covering all 19 keys], `Conditions` [`completeWhen` + default preview + `abortWhen`], `Hooks` [`onEnter`/`onExit`/`onAbort` + 16-color swatch picker]); `Mission Settings` (`version`, `description`, `fallbackPolicy`, `defaults.*`, `Target Airframe`, `Aircraft #N` → `Base`/Zone 3 preview).
- **`#rawJsonDrawer` (`460px` slide-over)**, **`footer.bottom-validation-bar`** (`[All | Errors | Warnings]` + `fieldPath` jump), **`#exportConfirmModal`**, **`#toastContainer`**.

- [ ] **Step 4: Run tests to verify they pass**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add tools/amm_mission_editor.html tests/3_planning/amm/test_amm_mission_editor.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm-editor): implement complete UI, InspectorUI, drawers, and AppBootstrap"
```

---

### Task 7: CraftOS-PC Lua Roundtrip, Full Regression Verification & Spec/Context Promotion

**Files:**
- Modify: `tests/3_planning/amm/test_amm_mission_editor.py` (add CraftOS-PC `mission_engine` roundtrip test)
- Modify: `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (`Approved` → `Implemented`)
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`Approved` → `Implemented`)
- Modify: `TASK.md`, `.agent/memory/workspace-root.md`

**Interfaces:**
- Consumes: `tools/amm_mission_editor.html` (`JsonIO.exportJson`, `MacroExpander.expandMacroCheckpoint`), `src/3_planning/amm/modules/mission_engine.lua`, `src/3_planning/amm/modules/action_registry.lua`, `harness/` CraftOS-PC runner.

- [ ] **Step 1: Add CraftOS-PC Lua roundtrip tests in `tests/3_planning/amm/test_amm_mission_editor.py`**

Write `test_craftos_mission_engine_roundtrip`:
- Use Node to export JSON files via `JsonIO.exportJson()` for: (a) `MSN_RECON_001` preset, (b) mission containing all 36 active `ACT_*`, 6 active `DEC_*` (`overrideParams`), 19 `preconditions`, `settleTicks`, and 4 hooks, (c) native `MAC_SHIP_RECOVERY` + `MAC_CARGO_SORTIE`, (d) deferred mission (`ACT_TKL_TAKEOFF_RWY`, `DEC_TIME_CRIT`, `MAC_PATROL_RADAR`), and (e) invalid legacy `v1.0.0` `items[]`.
- Execute CraftOS-PC headless Lua loading `src/3_planning/amm/modules/mission_engine.lua` (`validate_mission_table` / `load` / `expand_macros`): assert (a), (b), (c) pass with `ok == true`, (d) yields `DEFERRED_*_UNSUPPORTED`, and (e) fails with `SCHEMA_INVALID` / `EMPTY_CHECKPOINTS`.

- [ ] **Step 2: Run full test & audit suite**

Run in sequence:
1. `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py` (expect all PASS, including CraftOS-PC roundtrip)
2. Web Interface Guidelines manual line-by-line review of `tools/amm_mission_editor.html` against `.agent/skills/web-design-guidelines/references/command.md` (`file:line` checklist clean)
3. `python tools/run_unit_tests.py --require-tests --clean-orphans`
4. `python tools/run_e2e_tests.py --clean-orphans`
5. `python -m unittest tests/harness/test_terminology_guard.py`
6. `python tools/verify_manifest_sync.py`
7. `python tools/verify_all_specs.py --check-readmes`

- [ ] **Step 3: Perform manual `file://` desktop browser smoke check**

Open `tools/amm_mission_editor.html` directly via `file:///` (Chrome/Edge) and verify: `>= 1280px` 1-row header + bottom validation bar placement, `<= 1150px` 3-tab responsive switch, `#actionPickerPopover` search/add, 2D canvas drag + `Alt` fine tune, `#altProfilePane` toggle + vertical drag, `#rawJsonDrawer` edit/apply, `#exportConfirmModal`, `#toastContainer`.

- [ ] **Step 4: Promote specs (`Approved` → `Implemented`) and sync `TASK.md` + `.agent/memory/workspace-root.md`**

- Update `문서 상태 (Status)` to `Implemented` (`최종 수정일`: completion date) in `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` and `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`.
- Mark `TASK-402` `[x]` in `TASK.md` and append `TASK-402` entry to `.agent/memory/workspace-root.md` (`md-management` skill).
- Run `python tools/verify_all_specs.py --check-readmes`, `python tools/verify_spec_status.py`, `python tools/verify_context_docs.py`.

- [ ] **Step 5: Final commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add tools/amm_mission_editor.html tests/3_planning/amm/test_amm_mission_editor.py docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md TASK.md .agent/memory/workspace-root.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): implement AMM WebUI Mission Editor (TASK-402) and promote AMM specs"
```

---

## Self-Review

- **Spec coverage check**:
  - §1.2–§1.3 Constraints/Non-Goals → Global Constraints + Task 1 static checks.
  - §3.1–§3.4 Design Tokens, Typography, Copy, 5-Zone + `#altProfilePane` + `#rawJsonDrawer` + `#actionPickerPopover` + Web Interface Guidelines → Task 6 + Task 7 audit.
  - §4 State, `_extra`, Zero-Fallback `v2.0.0`, `params.{x,z}`, `localStorage` → Task 2 + Task 4.
  - §5–§6 `ACT_*` (36+19+3), `DEC_*` (7 + `overrideParams`), `MAC_*` (5 + `Expand Now`), 19 `preconditions`, 14 conditions, 4 hooks, 16 colors → Task 2 + Task 6.
  - §7 `Validator` & `fieldPath` jump → Task 3 + Task 6.
  - §8 2D `(X, Z)` Canvas + `#altProfilePane` → Task 5.
  - §9–§10 Presets, `JsonIO`, shortcuts, 9 IIFE modules, 4 Acceptance Gates → Tasks 1–7.
- **Placeholder scan**: Zero `TBD`/`TODO` lines; every task pins exact files, interfaces, test assertions, and commands.
- **Type & symbol consistency**: `window.__AMM_EDITOR__` 9 module names, `ValidationIssue` shape (`severity`, `code`, `luaCode`, `cpIndex`, `checkpointId`, `fieldPath`, `message`), `ui.activeRightMode` (`"CHECKPOINT"|"MISSION"`), `ui.activeInspectorTab` (`"PARAMS"|"GUARDS"|"CONDITIONS"|"HOOKS"`), `ui.targetAirframe`, `ui.altProfileOpen` match verbatim across Tasks 1–7 and `AMM_MISSION_EDITOR_SPECIFICATION.md` `v0.3.1`.
