# AMM WebUI Mission Editor Specification (`Draft`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execute directly on the working branch or an isolated worktree without modifying active `Approved`/`Implemented` specifications or `src/` runtime files.

**Goal:** Author `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (`Status: Draft`, `Version: v0.1.0`) as a complete, Lua-parity engineering specification for the zero-install browser mission editor (`tools/amm_mission_editor.html`) before implementing `TASK-202-5`.

**Architecture:** The specification lives beside `AMM_PROGRAM_SPECIFICATION.md` (`v1.2.0 Approved`) inside `docs/specs/3_planning/amm/` so relative links to Tier 1/2 system specs (`../../../system/...`) remain identical and `tools/verify_context_docs.py` (`R4`) excludes `Draft` specs from active distribution counts. Its contract is derived directly from the Lua runtime SSOT (`mission_engine.lua`, `condition_evaluator.lua`, `hook_runner.lua`, `network_manager.lua`) and `TASK-202-4` preflight validation rules, pinning exact JSON schemas, 13-action/12-condition/4-hook form matrices, Minecraft `(X, Z)` tactical canvas math, DOM XSS constraints, and offline JSON round-trip verification gates.

**Tech Stack:** Markdown (GFM), Mermaid Diagrams, JSON Schema contracts, HTML5/CSS/Vanilla JS UI/Canvas specification, Python 3.10+ Spec & Context Verifiers (`tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/verify_context_docs.py`).

**Spec & SSOT Inputs:**
- Primary Parent Spec: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v1.2.0 Approved` — §3.2, §4.2–4.3, §6.1–6.6, §9, §10, §11)
- Master ICD: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.27.0 Approved` — Interface I-6, Interface I-11)
- System Diagram: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.12.1 Approved`)
- Lifecycle Standard: `docs/specs/README.md` (5-field metadata table, Permanent Unified Path, `Draft` rules)
- Lua Runtime SSOT:
  - `src/3_planning/amm/modules/mission_engine.lua` (13 actions, `ACTION_TAXONOMY`, `normalize_checkpoint`, `convert_legacy_items`, `validate_mission`, `save`)
  - `src/3_planning/amm/modules/condition_evaluator.lua` (12 conditions, `resolve_default_complete`, `evaluate_group`)
  - `src/3_planning/amm/modules/hook_runner.lua` (4 hooks, `VALID_SIDES`, `resolve_color_mask`)
  - `src/3_planning/amm/modules/network_manager.lua` (Zone 3 `Base + 20..29`)
  - `src/3_planning/amm/config/amm_config.json` (`baseChannel = 10000`, `defaultAlt = 150.0`, `defaultSpeed = 18.0`, `arrivalRadius = 15.0`)
  - `docs/superpowers/plans/2026-11-11-task-202-4-amm-tui-resolver-drop-cli.md` (`resolve_path`, `validate_mission_table`, `SCHEMA_INVALID`, `params.x`/`params.z` shorthand)
- Roadmap SSOT: `TASK.md` (`TASK-202-5`)

## Global Constraints

- **Metadata & Lifecycle Gate (`docs/specs/README.md`, `skill-workflows.md`)**: Set `문서 상태 (Status)` to `` `Draft` ``, `문서 버전 (Version)` to `` `v0.1.0` ``, `최종 수정일 (Date)` to `` `2026-11-11` ``, `구현 코드 (Source)` to `` `tools/amm_mission_editor.html` ``, and `주관 도메인 (Domain)` to `임무 계획 외부 웹 GUI 미션 에디터 (AMM Companion Tool / Host PC)`. Do NOT invoke `specification-lifecycle-manager` and do NOT modify `AMM_PROGRAM_SPECIFICATION.md`, `docs/system/*.md`, `tools/verify_spec_status.py`, or `src/` while creating a `Draft` spec.
- **Zero-Install Single-File Target (`AMM_PROGRAM_SPECIFICATION.md` §9.1)**: `tools/amm_mission_editor.html` must operate offline via `file://` in standard desktop browsers as one self-contained HTML5/CSS/Vanilla JS file with zero external CDN `<script>`/`<link>` imports, zero build tools, and zero network fetches.
- **Lua Runtime Parity Constants**:
  - RF Channel Standard: `Base = 10000 + (N - 1) * 40` ($N = 1 \dots 1000$), Zone 3 offset `20..29` (`Base + 20 .. Base + 29`).
  - Defaults (`amm_config.json` & `mission_engine.lua`): `cruiseSpeed = 18.0`, `targetAlt = 150.0`, `acceptanceRadius = 15.0` (`FLY_OVER` fallback `20.0`, `FLY_TO` precision default `5.0`), `headingMode = "AUTO"`, `ORBIT` `radius = 30.0` / `direction = "CW"`, `PATROL` `patrolMode = "LOOP"` / `cycles = 1`, `PAYLOAD_ACTION` `waitForAck = true` / `expectedStatus = "OK"`, `REDSTONE_PULSE` `durationMs = 500`, `REDSTONE_ACTION` `durationMs = 0` / `minLevel = 1`.
  - 6 Redstone Sides: `top`, `bottom`, `left`, `right`, `front`, `back`.
  - 16 CC:Tweaked Colors: `white`, `orange`, `magenta`, `lightBlue`, `yellow`, `lime`, `pink`, `gray`, `lightGray`, `cyan`, `purple`, `blue`, `brown`, `green`, `red`, `black`.
- **Static & Governance Hygiene (`tools/verify_all_specs.py`, `tools/verify_context_docs.py`, `.agent/rules/domain-aeronautics.md`)**:
  - Balanced double quotes (`"`) in every `mermaid` fenced block.
  - Zero broken relative markdown links and zero stale lifecycle paths (`drafts/`, `approved/`, `implemented/`, `archived/`).
  - Zero legacy prohibited terminology (`UAP`, `SAS`, `WAP`, `VAS-Core`, `VAS-Align`, `VAC-Align`, `VAC-Core`) and zero Valkyrien Skies / `kontraption:` identifiers.
  - Zero exaggerated or unverified performance/completeness claims per `AGENTS.md` Overclaim Ban (`verify_context_docs.py` R2).

## Review Focus

1. **Field-Name & Default Asymmetry Between `mission_engine.lua` and `hook_runner.lua`**: `PAYLOAD_ACTION` checkpoint params use `params.commandPayload` (table) whereas the `ZONE3_PAYLOAD_CMD` hook uses `hook.payload` (table); `FLY_TO` defaults `acceptanceRadius` to `5.0` even when `defaults.acceptanceRadius` is `15.0`, whereas `FLY_OVER` inherits `defaults.acceptanceRadius`; and `ORBIT.radius` passes schema validation at `> 0` while FCP `LOITER` clamps at `>= 5.0m`. Pinned explicitly in Tasks 2 and 3.
2. **Minecraft `(X, Z)` Coordinate Handedness & Canvas Angles**: On Minecraft's top-down horizontal plane, `+X` points East (screen right) and `-Z` points North (screen top), so `+Z` points South (screen bottom). Heading `0°` (`North = -Z`) maps to canvas radian `-Math.PI / 2`, and `CW`/`CCW` orbit sweep arrows must follow screen clockwise (`+X -> +Z -> -X -> -Z`). Pinned explicitly in Task 4.
3. **Validation Severity Separation (`ERROR` vs `DEFERRED_WARNING`) & Empty Condition Group Trap**: `mission_engine.validate_mission_table` accepts the 4 deferred actions (`TAKEOFF_RUNWAY`, `LAND_RUNWAY`, `DOCK_ARM`, `UNDOCK_ARM`) structurally while runtime `enter_checkpoint` rejects them with `DEFERRED_ACTION_UNSUPPORTED`; meanwhile `condition_evaluator.evaluate_group` returns `false` on `conditions: []` rather than falling back to defaults. The spec must separate `ERROR` vs `DEFERRED_WARNING` and omit empty `completeWhen`/`abortWhen` objects on export. Pinned explicitly in Tasks 2 and 3.
4. **Legacy v1.0.0 Upgrade, Unknown-Field Preservation & DOM XSS Safety**: Importing `{ version: "1.0.0", items: [...] }` must convert each item to `FLY_OVER` and append `LAND_LAUNCHPAD` when the final item defines `facilityId`; importing `params.{x, z}` shorthand must normalize to `targetPos`; extra unrecognized keys on imported files must survive round-trip editing; and rendering untrusted JSON strings into the DOM must strictly use `textContent` / safe DOM construction (never `innerHTML` with raw strings). Pinned explicitly in Tasks 1, 2, and 4.
5. **Spec Lifecycle & Static Verifier Compliance**: Writing the spec as `Status: Draft` without modifying `AMM_PROGRAM_SPECIFICATION.md`, `verify_spec_status.py`, or `GEMINI.md` counts ensures `verify_context_docs.py` (`R4`, `R5`), `verify_all_specs.py`, and `verify_spec_status.py` all stay green while giving Gemini Argon / `TASK-202-5` an unambiguous blueprint. Pinned explicitly in Tasks 1 and 4.

---

## File Structure

- Create: `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` — Standalone `Draft` (`v0.1.0`) technical specification for `tools/amm_mission_editor.html` covering §1–§10 (System Integration, Layout & Design Tokens, State & Legacy Upgrade, 13-Action Matrix, 12-Condition & 4-Hook Builders, Lua-Parity Validator, 2D `(X, Z)` Tactical Canvas, JSON I/O & Shortcuts, JS Architecture & `TASK-202-5` Acceptance Criteria).
- Modify: `TASK.md:74-84` — Register `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (`현재 v0.1.0 Draft`) under `TASK-202-5` only after the spec file exists on disk (Task 4).

---

### Task 1: Specification Metadata, System Integration, Layout Shell & Design Tokens (`§1`–`§3`)

**Files:**
- Create: `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md`

**Interfaces:**
- Consumes: `docs/specs/README.md` (5-field metadata table & `Draft` conventions), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (§1, §3.2, §6.6, §9), `src/3_planning/amm/config/amm_config.json`.
- Produces: `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` header (`Status: Draft`, `Version: v0.1.0`), `### Revision History`, relative links, and `§1`–`§3` (Overview & Security Constraints, System Pipeline & Mermaid Diagram, Layout Shell & Industrial Avionics Design Tokens).

- [ ] **Step 1: Prepare the target directory verification check**

Confirm `docs/specs/3_planning/amm/` exists and verify `AMM_MISSION_EDITOR_SPECIFICATION.md` does not yet exist before authoring:
```powershell
python -c "from pathlib import Path; d=Path('docs/specs/3_planning/amm'); assert d.is_dir(); assert not (d/'AMM_MISSION_EDITOR_SPECIFICATION.md').exists(); print('READY')"
```
Expected: `READY`

- [ ] **Step 2: Author header metadata, Revision History, and `§1`–`§3` in `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md`**

Write the initial document containing:
1. **Title & Standard 5-Field Metadata Table**:
   - Title: `# AMM WebUI Mission Editor (호스트 PC 외부 비주얼 미션 에디터) 상세 규격서`
   - Subheader blockquotes identifying `tools/amm_mission_editor.html` as a companion tool for `AMM (Layer 3 Planning)` in `UAFS Ecosystem`.
   - Metadata table:
     - `문서 상태 (Status)`: `` `Draft` ``
     - `문서 버전 (Version)`: `` `v0.1.0` ``
     - `최종 수정일 (Date)`: `` `2026-11-11` ``
     - `구현 코드 (Source)`: `` `tools/amm_mission_editor.html` ``
     - `주관 도메인 (Domain)`: `임무 계획 외부 웹 GUI 미션 에디터 (AMM Companion Tool / Host PC)`
   - Relative links section pointing to:
     - `[AMM_PROGRAM_SPECIFICATION.md](AMM_PROGRAM_SPECIFICATION.md)` (`v1.2.0 Approved`)
     - `[AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md)` (`v1.27.0 Approved`)
     - `[SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md](../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md)` (`v2.12.1 Approved`)
     - `[GEMINI.md](../../../../GEMINI.md)`
   - `### Revision History` table (`v0.1.0 | 2026-11-11 | ...`).
2. **`## 1. 프로그램 개요 및 불변 제약 (Overview, Constraints & Non-Goals)`**:
   - Goals: zero-install single HTML5 file (`file://` offline execution), full parity with AMM v1.2.0 (`13 actions`, `12 conditions`, `4 hooks`, `v1.0.0` legacy import), intuitive 2D `(X, Z)` tactical plotting, live preflight diagnostics before dropping `.json` into CC:Tweaked.
   - Hard Constraints: zero external CDN/JS/CSS dependencies, zero `fetch()`/WebSocket calls, DOM XSS safety (`document.createElement` + `textContent` strictly; forbid passing JSON strings into `innerHTML`).
   - Non-Goals: no live in-game telemetry/RF modem connection, no server process, no 3D WebGL terrain rendering, no Valkyrien Skies / `kontraption:` concepts.
3. **`## 2. 시스템 연동 및 외부 파일 파이프라인 (System Context & In-Game Workflow)`**:
   - Mermaid `flowchart LR` showing the end-to-end flow: Author/Import in `tools/amm_mission_editor.html` -> `validateMission()` -> Export `.json` -> Inject via (a) CC window drag-and-drop `file_transfer`, (b) `/disk/` or `/disk/missions/`, (c) `missions/` local folder -> `mission_engine.resolve_path` & `validate_mission_table` -> `mission_engine` FSM -> `FCP (Base+0)` & `Zone 3 (Base+20~29)`.
   - Reference `amm_config.json` baseline (`baseChannel = 10000`, `defaultAlt = 150.0`, `defaultSpeed = 18.0`, `arrivalRadius = 15.0`) and `Base = 10000 + (N - 1) * 40` preview calculator for `PAYLOAD_ACTION` / `ZONE3_PAYLOAD_CMD`.
4. **`## 3. UI 레이아웃, 디자인 시스템 및 반응형 규격 (Layout Shell & Design Tokens)`**:
   - Define the **Industrial Avionics Dark Cockpit** CSS custom properties (`--bg-app: #0b0f17`, `--bg-panel: #111827`, `--bg-elevated: #1b2434`, `--border-default: #2b394e`, `--text-primary: #e5edf7`, `--text-muted: #94a3b8`, `--accent-cyan: #22d3ee`, `--accent-amber: #f59e0b`, `--accent-green: #10b981`, `--accent-red: #ef4444`, `--accent-violet: #a78bfa`), monospace data font stack (`'JetBrains Mono', 'Cascadia Code', Consolas, monospace`), and high-contrast badge styles (color + text icon so status never relies on hue alone).
   - Define the 5-region workspace grid:
     1. Top Action & Mission Header Bar (`52px`): Mission ID, `SINGLE`/`REPEAT` toggle, `fallbackPolicy`, Aircraft `#N` (`Base`) preview input, Import / Presets / Raw JSON / Copy / Export `.json`, Undo/Redo.
     2. Left Checkpoint Sequence Rail (`300px`): `+ Add` dropdown/presets, vertical checkpoint cards (`index`, `checkpointId`, `action` badge, status border `[ERROR]`/`[DEFERRED]`/`[OK]`, up/down/duplicate/delete buttons, drag handle).
     3. Center Interactive 2D `(X, Z)` Tactical Canvas (`1fr`, min `420px`): Canvas toolbar (`activeTool`: `SELECT`, `ADD_FLY_OVER`, `PICK_TARGET`, `PICK_POI`, `ADD_PATROL_WP`; `Grid Snap: Off|1m|10m|50m`, `Fit All`, `Zoom +/-`), live cursor world `(X, Z)` & path summary HUD overlay.
     4. Right Inspector & JSON Drawer (`420px`): Tabbed or sectioned `Mission Defaults` + selected Checkpoint Inspector (`Action Params`, `completeWhen`, `abortWhen`, `Hooks [onEnter/onExit/onAbort]`) + collapsible Raw JSON Preview/Edit drawer.
     5. Bottom Preflight Validation Bar (`32px` collapsed / expandable drawer): live `ERROR` and `DEFERRED_WARNING` counts and clickable `CP#idx` issue chips.
   - Define responsive breakpoint behavior (`< 1150px` stacked or tabbed Canvas/Inspector) and `aria-label`/keyboard focus ring accessibility rules.

- [ ] **Step 3: Run structural & hygiene verification on `§1`–`§3`**

Run:
```powershell
python -c "from pathlib import Path; import re; p=Path('docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md'); txt=p.read_text(encoding='utf-8'); assert re.search(r'\*\*문서 상태 \(Status\)\*\*\s*\|\s*\x60Draft\x60', txt); assert re.search(r'\*\*문서 버전 \(Version\)\*\*\s*\|\s*\x60v0\.1\.0\x60', txt); assert '### Revision History' in txt; links=re.findall(r'\[[^\]]+\]\(([^)]+)\)', txt); bad=[l for l in links if not l.startswith(('http','#')) and not (p.parent/l.split('#')[0]).resolve().exists()]; assert not bad, bad; m=re.findall(r'\x60\x60\x60mermaid\n(.*?)\n\x60\x60\x60', txt, re.S); assert all(b.count('\"')%2==0 for b in m); print('TASK1_PASS', len(links), len(m))"
```
Expected: `TASK1_PASS <links> <mermaid_blocks>` with exit code `0`.

- [ ] **Step 4: Commit Task 1**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(amm): draft WebUI mission editor spec skeleton, context, and layout (TASK-202-5 prep)"
```

---

### Task 2: State Model, Legacy Migration & 13-Action Form Contract (`§4`–`§5`)

**Files:**
- Modify: `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (append `§4` and `§5`)

**Interfaces:**
- Consumes: `src/3_planning/amm/modules/mission_engine.lua` (`ACTIVE_ACTIONS`, `DEFERRED_ACTIONS`, `ACTION_TAXONOMY`, `validate_*`, `normalize_checkpoint`, `convert_legacy_items`, `save`), `TASK-202-4` plan (`params.x`/`params.z` shorthand).
- Produces: Complete editor state schema, deterministic `convertLegacyItems` algorithm, unknown-field preservation rules, undo/autosave behavior, and complete 13-action parameter/UI-control matrix (`§4`–`§5`).

- [ ] **Step 1: Append `## 4. 에디터 상태 모델, 하위 호환 변환 및 영속성 (§4)`**

Append §4 specifying exact data structures and algorithms:
1. **Canonical State Object (`EditorState`)**:
   - `mission`: `{ missionId, version: "1.2.0", description, executionMode, fallbackPolicy, defaults: { cruiseSpeed, targetAlt, acceptanceRadius, headingMode }, checkpoints: [...] }`, plus hidden per-object `_extra` bag (or preserved non-schema keys) so unrecognized fields from hand-edited JSON survive import -> edit -> export untouched.
   - `ui`: `{ selectedIndex, selectedPatrolIndex, activeInspectorTab, activeHookTab, rawJsonOpen, validationExpanded, activeTool, gridSnapM, baseChannel, dirty }` (`activeTool`: `"SELECT" | "ADD_FLY_OVER" | "PICK_TARGET" | "PICK_POI" | "ADD_PATROL_WP"`).
   - `canvas`: `{ camX, camZ, zoomPxPerM, draggingNode, isPanning }`.
   - `history`: `{ undoStack: [], redoStack: [], maxDepth: 50 }` storing immutable structured clones of `mission` + `selectedIndex`.
2. **Legacy v1.0.0 Import Upgrade (`convertLegacyItems`)**:
   - Detect when `Array.isArray(raw.items) && !Array.isArray(raw.checkpoints)`.
   - Transform each `item` at index `i` into `{ checkpointId: formatCpId(item.id ?? i+1), action: "FLY_OVER", params: { targetPos: { x: item.x, z: item.z }, ...(item.alt != null && { targetAlt: item.alt }), ...(item.speed != null && { cruiseSpeed: item.speed }) } }`.
   - If `last.facilityId` is a non-empty string, append `{ checkpointId: formatCpId(checkpoints.length + 1), action: "LAND_LAUNCHPAD", params: { facilityId: last.facilityId, targetPos: { x: last.x, z: last.z }, ...(last.alt != null && { targetAlt: last.alt }) } }`.
   - Emit explicit non-blocking toast notice (`"Legacy v1.0.0 queue upgraded to v1.2.0 checkpoints"`).
3. **Shorthand Coordinate Normalization on Import**:
   - If a checkpoint has numeric `params.x` and `params.z` without `params.targetPos` (per `TASK-202-4` `extract_target_pos`), promote to canonical `params.targetPos = { x: params.x, z: params.z }` and drop the temporary shorthand keys on export.
4. **Autosave Recovery (`localStorage`)**:
   - Debounced `500ms` write to key `uafs_amm_editor_autosave_v1` containing `{ savedAtIso, mission }`.
   - On page load, if `uafs_amm_editor_autosave_v1` differs from the default starter template, show a top non-blocking recovery banner (`[Restore Draft]` / `[Dismiss]`) rather than silently clobbering user actions.

- [ ] **Step 2: Append `## 5. 미션 헤더 및 13종 체크포인트 액션 폼 매트릭스 (§5)`**

Append §5 containing:
1. **Mission Header & Global `defaults` Form Contract**:
   - Table detailing `missionId` (string, non-empty suggested, default `"SORTIE_ALPHA"`), `version` (readonly/editable `"1.2.0"`), `description` (optional string), `executionMode` (`"SINGLE"` | `"REPEAT"`), `fallbackPolicy` (`"RTH"` | `"HOVER_HOLD"` | `"LOITER"` | `"SKIP_NEXT"`), and `defaults.{cruiseSpeed (18.0), targetAlt (150.0), acceptanceRadius (15.0), headingMode ("AUTO"|"FIXED"|"POI")}`.
2. **Checkpoint Envelope Controls & Card Reordering**:
   - Per-checkpoint header fields: `checkpointId` (string, auto `CP_01`), `action` (`<select>` grouped by `1. Navigation (Active 5)`, `2A. Infrastructure (Active 2)`, `3. Special Devices (Active 2)`, `2B. Infrastructure (Deferred 4)`), optional per-checkpoint `fallbackPolicy` override (`"(Inherit Mission)" | "RTH" | "HOVER_HOLD" | "LOITER" | "SKIP_NEXT"`).
   - Card lifecycle actions: Add, Duplicate, Delete, Move Up/Down, Drag-to-Reorder (updating array index and re-indexing validation `CP#idx` immediately).
3. **Complete 13-Action Parameter Specification Table & Sub-Specs**:
   - Explicitly list EVERY field for all 13 actions with: JSON key path, data type, UI widget, default/inheritance behavior, and validation constraints:
     - `FLY_OVER`: `targetPos.{x, z}` (required finite nums), `targetAlt` (optional num, inherits `defaults.targetAlt`), `cruiseSpeed` (optional num, inherits `defaults.cruiseSpeed`), `acceptanceRadius` (optional `> 0`, inherits `defaults.acceptanceRadius` else `20.0`), `headingMode` (optional `"AUTO"|"FIXED"|"POI"`), `fixedHeading` (`0..360`, shown/enabled when effective `headingMode == "FIXED"`).
     - `FLY_TO`: identical spatial/dynamics inputs except `acceptanceRadius` explicitly displays default `5.0 m` (does NOT inherit `defaults.acceptanceRadius = 15.0` unless explicitly set on the checkpoint, matching `mission_engine.lua:112`).
     - `ORBIT`: `targetPos.{x, z}` (required), `radius` (number `> 0`, default `30.0`; show advisory badge if `< 5.0` because FCP `LOITER` clamps `R >= 5.0`), `direction` (`"CW"` | `"CCW"`, default `"CW"`), `durationSec` (optional `>= 0`; blank = hold until `next`/`stop`), `targetAlt`, `cruiseSpeed`.
     - `PATROL`: dynamic ordered table `waypoints[]` (`min 1` row, each row `{ x, z, alt?, speed?, acceptanceRadius? }` with Add/Delete/Up/Down & canvas placement), `patrolMode` (`"LOOP"` | `"PING_PONG"`, default `"LOOP"`), `cycles` (integer `>= 1`, default `1`), `durationSec` (optional), `targetAlt`, `cruiseSpeed`, `acceptanceRadius`.
     - `POI_HOLD`: `targetPos.{x, z}` (required), `poiPos.{x, y?, z}` (`x, z` required, `y` optional finite number), `headingMode` (defaults to `"POI"`), `durationSec` (optional), `targetAlt`, `cruiseSpeed`.
     - `TAKEOFF_LAUNCHPAD`: `facilityId` (optional non-empty string if present), `targetAlt` (optional, inherits `defaults.targetAlt`), `targetPos.{x, z}` (optional pad marker for 2D canvas preview).
     - `LAND_LAUNCHPAD`: `facilityId` (non-empty string) and/or `targetPos.{x, z}` — **at least one required** (`INVALID_LAND_PARAMS`), `targetAlt` (optional).
     - `PAYLOAD_ACTION`: `channelOffset` (`20..29` integer, default `20`) OR advanced absolute `targetChannel` (`Base+20..29`) with live computed RF channel preview (`Base + offset`), `command` (required non-empty string), `commandPayload` (JSON object editor textarea, default `"{}"`, validated via `JSON.parse` + object check), `waitForAck` (checkbox, default `true`), `expectedStatus` (string, default `"OK"`, enabled when `waitForAck == true`).
     - `REDSTONE_ACTION`: `mode` (`"EMIT"` | `"WAIT_INPUT"`), `side` (6-side dropdown: `top`, `bottom`, `left`, `right`, `front`, `back`), `color` (optional 16 CC color selector or `"None (Digital/Analog)"`), `level` (optional `0..15` integer for `EMIT` when `color == nil`), `state` (bool toggle for digital `EMIT`, default `true`), `durationMs` (`>= 0`, default `0` for `EMIT`), `minLevel` (`1..15`, default `1` for `WAIT_INPUT`).
     - `TAKEOFF_RUNWAY`, `LAND_RUNWAY`, `DOCK_ARM`, `UNDOCK_ARM` (`DEFERRED`): render amber warning banner `[DEFERRED — TASK-103/104 미구현으로 런타임 실행 시 DEFERRED_ACTION_UNSUPPORTED 거부됨]` plus minimal editable `facilityId` / `targetPos.{x, z}` / `targetAlt` fields for future-ready mission authoring and canvas plotting.

- [ ] **Step 3: Verify 13-action & schema identifier coverage in `§4`–`§5`**

Run:
```powershell
python -c "from pathlib import Path; txt=Path('docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md').read_text(encoding='utf-8'); req=['FLY_OVER','FLY_TO','ORBIT','PATROL','POI_HOLD','TAKEOFF_LAUNCHPAD','LAND_LAUNCHPAD','PAYLOAD_ACTION','REDSTONE_ACTION','TAKEOFF_RUNWAY','LAND_RUNWAY','DOCK_ARM','UNDOCK_ARM','convertLegacyItems','commandPayload','waitForAck','expectedStatus','channelOffset','patrolMode','DEFERRED_ACTION_UNSUPPORTED','5.0']; miss=[k for k in req if k not in txt]; assert not miss, miss; print('TASK2_PASS')"
```
Expected: `TASK2_PASS`

- [ ] **Step 4: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(amm): specify WebUI state model, legacy conversion, and 13-action forms (TASK-202-5 prep)"
```

---

### Task 3: 12-Condition & 4-Hook Builders and Lua-Parity Preflight Validator (`§6`–`§7`)

**Files:**
- Modify: `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (append `§6` and `§7`)

**Interfaces:**
- Consumes: `src/3_planning/amm/modules/condition_evaluator.lua` (`CONDITION_TYPES`, `resolve_default_complete`, `evaluate_group`), `src/3_planning/amm/modules/hook_runner.lua` (`VALID_HOOK_TYPES`, `resolve_color_mask`), `TASK-202-4` plan (`validate_mission_table` error catalog).
- Produces: Complete `§6` (12-condition builder, empty-group omission rule, per-action default `completeWhen` table, 4-hook builder, 16-color CC table) and `§7` (real-time Lua-parity `validateMission()` specification and error catalog).

- [ ] **Step 1: Append `## 6. 12종 조건 빌더 및 4종 라이프사이클 훅 빌더 (§6)`**

Append §6 specifying:
1. **Condition Group Builders (`completeWhen` & `abortWhen`)**:
   - Logic selector: `"ALL"` (default for `completeWhen`) / `"ANY"` (default for `abortWhen`).
   - **Empty Group Rule**: When `conditions.length === 0`, the inspector shows `"Default completion active (no custom override)"` for `completeWhen` and omits `completeWhen` / `abortWhen` keys entirely from the exported JSON so `condition_evaluator.evaluate_group(..., {})` never traps the mission in `false`.
   - **Per-Action Default `completeWhen` Preview Table** matching `condition_evaluator.resolve_default_complete` across all 9 active actions (`FLY_OVER` -> `PROXIMITY_2D`, `FLY_TO` -> `PROXIMITY_3D <= 5m`, `TAKEOFF_LAUNCHPAD` -> `ALTITUDE_REACHED +/-5m OR FCP CRUISE`, `LAND_LAUNCHPAD` -> `FACILITY_TOUCHDOWN`, `ORBIT`/`POI_HOLD` -> `DURATION_SEC(durationSec)` or `HOLD/MANUAL`, `PATROL` -> `cycles` loop completion or `DURATION_SEC`, `PAYLOAD_ACTION` -> `PAYLOAD_RESP_MATCH` or `DURATION_SEC(0)` if `waitForAck == false`, `REDSTONE_ACTION` -> `DURATION_SEC(durationMs/1000)` or `REDSTONE_INPUT_HIGH`).
2. **Complete 12-Condition Field Matrix**:
   - `PROXIMITY_2D`: `toleranceM` (`>= 0`, optional default `acceptanceRadius`), optional `targetPos.{x, z}` override.
   - `PROXIMITY_3D`: `toleranceM` (`>= 0`, default `5.0`), optional `targetPos.{x, z}`, optional `targetAlt`.
   - `ALTITUDE_REACHED`: `toleranceM` (`>= 0`, default `5.0`), optional `targetAlt`, optional `allowFsmCruise` (bool).
   - `DURATION_SEC`: `durationSec` (`>= 0`, required).
   - `TIMEOUT_SEC`: `timeout` (`>= 0`, required — note key is `timeout`, NOT `timeoutSec`!).
   - `FUEL_LEVEL_BELOW`: `threshold` (`0.0 .. 1.0`, step `0.05`).
   - `FACILITY_TOUCHDOWN`: optional `facilityId`.
   - `PAYLOAD_RESP_MATCH`: `expectedStatus` (string, default `"OK"`), optional `command`, optional `checkpointId`.
   - `REDSTONE_INPUT_HIGH`: `side` (`top..back`, required), optional `color` (16 CC colors), optional `minLevel` (`1..15`, default `1`).
   - `CROSS_TRACK_ERROR`: `maxDevM` (`>= 0`, required).
   - `ARM_DOCKED` / `ARM_RELEASED`: `[DEFERRED / TASK-104]` badge + optional `facilityId`.
3. **3-Tab Lifecycle Hook Builder (`onEnter`, `onExit`, `onAbort`)**:
   - 4-Hook Field Table:
     - `REDSTONE_SET`: `side` (required), `state` (bool, default `true`), optional `color`, optional `level` (`0..15`).
     - `REDSTONE_PULSE`: `side` (required), `durationMs` (`>= 0`, default `500`), optional `color`, optional `level` (`0..15`).
     - `ZONE3_PAYLOAD_CMD`: `channelOffset` (`20..29`) or `targetChannel` (`Base+20..29`), `command` (non-empty string), `payload` (JSON object editor, default `{}` — explicitly note that hooks use `hook.payload` whereas `PAYLOAD_ACTION` uses `params.commandPayload`).
     - `NOTIFY_OPERATOR`: `level` (`"INFO"` | `"WARN"` | `"CRITICAL"`), `message` (string).
   - **16 CC:Tweaked Color Reference Table**: `white`, `orange`, `magenta`, `lightBlue`, `yellow`, `lime`, `pink`, `gray`, `lightGray`, `cyan`, `purple`, `blue`, `brown`, `green`, `red`, `black` with their canonical hex swatches (`#F0F0F0` .. `#111111`) and string emission rule (`hook_runner.lua:38` `colors[color]`).

- [ ] **Step 2: Append `## 7. 실시간 프리플라이트 스키마 검증 엔진 (§7)`**

Append §7 specifying `validateMission(mission, opts)`:
1. **Validation Output Model**:
   - Returns `{ valid: boolean, errors: ValidationIssue[], warnings: ValidationIssue[] }`, where `ValidationIssue = { severity: "ERROR" | "WARNING", code: string, cpIndex: number|null, checkpointId: string|null, fieldPath: string, message: string }`.
   - `valid === true` iff `errors.length === 0`. Deferred actions emit `WARNING` (`DEFERRED_ACTION_UNSUPPORTED`) matching `TASK-202-4` `validate_mission_table` structural pass while informing the user that AMM runtime execution will safely abort at that step.
2. **Exact Error & Warning Catalog Table** (1:1 parity with `mission_engine.validate_mission_table` & `normalize_checkpoint`):
   - Mission-level: `EMPTY_CHECKPOINTS`, `INVALID_EXECUTION_MODE`, `INVALID_FALLBACK_POLICY`.
   - Checkpoint-level (`CP#k`): `UNKNOWN_ACTION`, `INVALID_TARGET_POS`, `INVALID_ACCEPTANCE_RADIUS`, `INVALID_TARGET_ALT`, `INVALID_FACILITY_ID`, `INVALID_ORBIT_RADIUS`, `INVALID_ORBIT_DIRECTION`, `INVALID_PATROL_WAYPOINTS`, `INVALID_PATROL_MODE`, `INVALID_PATROL_CYCLES`, `MISSING_POI_POS`, `INVALID_POI_POS`, `INVALID_LAND_PARAMS`, `INVALID_ZONE3_CHANNEL`, `MISSING_PAYLOAD_COMMAND`, `INVALID_JSON_PAYLOAD`, `INVALID_REDSTONE_MODE`, `INVALID_REDSTONE_SIDE`, `INVALID_REDSTONE_DURATION`, `INVALID_CONDITION_LOGIC`, `UNKNOWN_CONDITION_TYPE`, `EMPTY_CONDITION_GROUP`, `INVALID_CONDITION_PARAM`, `UNKNOWN_HOOK_TYPE`, `INVALID_HOOK_PARAM`.
   - Warnings: `DEFERRED_ACTION_UNSUPPORTED`, `ORBIT_RADIUS_BELOW_FCP_MIN` (`radius < 5.0`), `MISSING_DURATION_HOLD_MANUAL` (`ORBIT`/`POI_HOLD` without `durationSec` or `completeWhen`), `PATROL_SINGLE_WP_DEGENERACY` (`waypoints.length === 1`).
3. **Interactive Diagnostic UX**:
   - Live validation runs synchronously on every state edit (`< 5ms`).
   - Export button stays clickable with an explicit confirmation prompt if `errors.length > 0` (or exports cleanly when `valid === true`), and clicking any `CP#k` issue focuses checkpoint `k` and centers the canvas on its coordinates.

- [ ] **Step 3: Verify 12-condition, 4-hook, 16-color, and error catalog coverage in `§6`–`§7`**

Run:
```powershell
python -c "from pathlib import Path; txt=Path('docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md').read_text(encoding='utf-8'); conds=['PROXIMITY_2D','PROXIMITY_3D','ALTITUDE_REACHED','DURATION_SEC','TIMEOUT_SEC','FUEL_LEVEL_BELOW','FACILITY_TOUCHDOWN','PAYLOAD_RESP_MATCH','REDSTONE_INPUT_HIGH','CROSS_TRACK_ERROR','ARM_DOCKED','ARM_RELEASED']; hooks=['REDSTONE_SET','REDSTONE_PULSE','ZONE3_PAYLOAD_CMD','NOTIFY_OPERATOR']; cols=['white','orange','magenta','lightBlue','yellow','lime','pink','gray','lightGray','cyan','purple','blue','brown','green','red','black']; errs=['EMPTY_CHECKPOINTS','UNKNOWN_ACTION','INVALID_ZONE3_CHANNEL','MISSING_PAYLOAD_COMMAND','INVALID_LAND_PARAMS','INVALID_REDSTONE_SIDE','UNKNOWN_CONDITION_TYPE','UNKNOWN_HOOK_TYPE']; miss=[x for x in conds+hooks+cols+errs if x not in txt]; assert not miss, miss; print('TASK3_PASS')"
```
Expected: `TASK3_PASS`

- [ ] **Step 4: Commit Task 3**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(amm): specify 12-condition/4-hook builders and Lua-parity preflight validator (TASK-202-5 prep)"
```

---

### Task 4: 2D `(X, Z)` Tactical Canvas, JSON I/O, JS Architecture & `TASK-202-5` Acceptance Criteria (`§8`–`§10`)

**Files:**
- Modify: `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (append `§8`, `§9`, `§10`)
- Modify: `TASK.md:74-84` (register `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` `(현재 v0.1.0 Draft)` under `TASK-202-5`)

**Interfaces:**
- Consumes: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (§6.2 sample mission, §9.2 items 4–5, §10, §11), `tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/verify_context_docs.py`.
- Produces: Complete `§8`–`§10` of `AMM_MISSION_EDITOR_SPECIFICATION.md` and synchronized `TASK.md` reference passing all repository verifiers.

- [ ] **Step 1: Append `## 8. 2D (X, Z) 전술 경로 프리뷰 캔버스 규격 (§8)`**

Append §8 specifying:
1. **Minecraft `(X, Z)` Affine Transform**:
   - World-to-Screen: `sx = width / 2 + (wx - camX) * zoom`, `sy = height / 2 + (wz - camZ) * zoom` (`+X` East right, `-Z` North up, `+Z` South down).
   - Screen-to-World: `wx = camX + (sx - width / 2) / zoom`, `wz = camZ + (sy - height / 2) / zoom`, with optional grid snap (`snap(v) = Math.round(v / gridSnapM) * gridSnapM` for `1m`, `10m`, `50m`).
   - Compass Heading Mapping: `0°` = North (`-Z`), `90°` = East (`+X`); `canvasRad = (headingDeg - 90) * Math.PI / 180`.
   - HiDPI Scaling: `canvas.width = rect.width * devicePixelRatio`, `ctx.setTransform(dpr, 0, 0, dpr, 0, 0)` on resize.
2. **8 Ordered Rendering Layers**:
   1. Background & adaptive metric grid (`10m` / `50m` / `100m` / `500m` step scaled dynamically so grid lines stay `40..120px` apart), world origin `(0, 0)` crosshairs, and corner `N(-Z)/E(+X)/S(+Z)/W(-X)` compass indicator.
   2. Primary leg trajectory lines connecting spatial checkpoints (`FLY_OVER`, `FLY_TO`, `ORBIT`, `POI_HOLD`, `PATROL` entry->exit, `TAKEOFF_LAUNCHPAD`/`LAND_LAUNCHPAD` with `targetPos`) + midpoint directional arrowheads; if `executionMode === "REPEAT"`, render dashed return leg from final spatial checkpoint back to wrap-around target (`index 1` if `checkpoints[0].action === "TAKEOFF_LAUNCHPAD"` and `checkpoints.length >= 2`, else `index 0`, matching `mission_engine.lua:748-751`).
   3. Acceptance radius dashed rings (`FLY_OVER` / `FLY_TO` using resolved radius) and `ORBIT` dashed circle (`params.radius`) with `CW`/`CCW` tangent directional arrowheads along the circumference.
   4. `PATROL` sub-waypoint numbered polyline (`P1`, `P2`, ...), closing edge (`P_n -> P_1` when `LOOP`) or bidirectional chevron (`PING_PONG`).
   5. `POI_HOLD` dashed amber sightline from `targetPos` to `poiPos` crosshair marker (`+POI`).
   6. Checkpoint markers (`1..N`), distinct node glyphs (`TAKEOFF` upward triangle, `LAND` downward square/pad, `ORBIT` ring, `POI_HOLD` diamond, `PATROL` polygon node, non-spatial `PAYLOAD_ACTION`/`REDSTONE_ACTION` attached as side satellite badges near the previous spatial anchor), selected cyan halo, and error/deferred outline.
   7. `headingMode == "FIXED"` short nose-heading vector glyph when defined.
   8. Top-left canvas HUD overlay (`Cursor (X, Z)`, `Zoom`, `Leg Count`, `Total 2D Path Distance (m)`, `Estimated Transit Time (s)`).
3. **Mouse & Touch Pointer State Machine**:
   - Wheel zoom anchored at cursor world coordinates (`0.05 .. 10.0 px/m`).
   - Pan via Middle-drag, Right-drag, or `Space + Left-drag` (`cursor: grab`).
   - Tool modes (`ui.activeTool`): `SELECT` (click node to select, drag handle to move `targetPos`, `poiPos`, or `PATROL` sub-waypoint), `ADD_FLY_OVER` (click canvas appends `FLY_OVER` at snapped `(X, Z)`), `PICK_TARGET` (click updates selected checkpoint `targetPos`), `PICK_POI` (click updates selected `POI_HOLD` `poiPos`), `ADD_PATROL_WP` (click appends to selected `PATROL.waypoints`).
   - `Fit All` computes bounding box across all spatial coordinates + `ORBIT` radii + `poiPos` with `15%` padding (defaulting to `(-200..200)` around `(0, 0)` when empty).

- [ ] **Step 2: Append `## 9. JSON 입출력, 스타터 프리셋 및 단축키 규격 (§9)`**

Append §9 specifying:
1. **Starter Templates**:
   - `Sortie Alpha (Full Example)` (exact 5-checkpoint sortie from `AMM_PROGRAM_SPECIFICATION.md` §6.2), `Patrol Perimeter`, `Payload Delivery`, `Empty Draft`.
2. **Import Pipelines**:
   - `<input type="file" accept=".json">` loader, whole-window `dragover`/`drop` JSON loader, and Raw JSON drawer `Apply JSON` parser — all running `JSON.parse` -> `convertLegacyItems` (if v1.0.0) -> shorthand `(x, z)` normalization -> `validateMission`.
3. **Export & Raw Preview**:
   - `Export .json`: formats canonical `2`-space JSON omitting empty `completeWhen`/`abortWhen` objects and undefined optional keys, triggers browser download (`${missionId.toLowerCase()}.json`).
   - `Copy JSON`: copies formatted JSON via `navigator.clipboard.writeText` with hidden `<textarea>` fallback and toast confirmation.
   - `Raw JSON Drawer`: read/write preview with DOM-safe syntax highlighting (`<span>` text nodes only) and sync status indicator.
4. **Keyboard Shortcuts**:
   - `Ctrl+Z` (Undo), `Ctrl+Y` / `Ctrl+Shift+Z` (Redo), `F` (Fit All on canvas when focus is not in text input), `Delete` (delete selected checkpoint when focus is not in text input), `1`/`2`/`3` (switch tool mode when focus is not in text input).

- [ ] **Step 3: Append `## 10. 내부 모듈 아키텍처 및 TASK-202-5 인수 기준 (§10)`**

Append §10 specifying:
1. **Single-File Internal IIFE Module Layout (`tools/amm_mission_editor.html`)**:
   - HTML shell + `<style>` CSS design tokens + `<script>` divided into clean IIFE sections: `SchemaConstants`, `LegacyMigrator`, `DefaultResolver`, `Validator`, `Store`, `CanvasRenderer`, `InspectorUI`, `JsonIO`, `AppBootstrap`.
   - Map `AMM_PROGRAM_SPECIFICATION.md` §10 canonical entrypoints explicitly to these modules: `validateMission()` (`Validator`), `renderCheckpoints()` (`InspectorUI`), `renderCanvas()` (`CanvasRenderer`), `exportJson()` & `importJson()` (`JsonIO`).
   - Zero global namespace pollution (except optional `window.__AMM_EDITOR__` read-only/test hook if needed for automated verification, cleanly guarded).
2. **`TASK-202-5` Implementation & Verification Criteria**:
   - **Static & Security Gate**: zero external `http://`/`https://` assets, zero `innerHTML` usage with user/JSON strings, zero VS/`kontraption:` identifiers.
   - **Schema & Lua-Parity Gate**: verify exported JSON files across all 9 active actions + 12 conditions + 4 hooks + upgraded v1.0.0 legacy missions load and validate with `ok == true` inside CraftOS-PC `mission_engine:load()` and `validate_mission_table()` (`tools/run_unit_tests.py` + `tools/run_e2e_tests.py`), and confirm `DEFERRED` 4-action exports pass `validate_mission_table` while returning `DEFERRED_ACTION_UNSUPPORTED` in `enter_checkpoint`.
   - **Interactive Browser Verification**: manual `file://` verification across desktop (`>= 1280px`) and narrow (`~1024px`) viewports covering canvas pan/zoom/click/drag, undo/redo, JSON import/export, and CraftOS-PC `file_transfer` drop execution.
   - **Lifecycle Promotion Rule**: Upon `TASK-202-5` implementation & verification pass, promote this spec (`Draft` -> `Implemented` via `Approved` review) alongside `AMM_PROGRAM_SPECIFICATION.md` (`v1.2.0 Approved` -> `Implemented`) and register in `tools/verify_all_specs.py` / `tools/verify_spec_status.py`.

- [ ] **Step 4: Register the `Draft` spec in `TASK.md` and run all repository & spec verification gates**

1. Update `TASK.md:74-84` to reference `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (`현재 v0.1.0 Draft`) and this plan under `TASK-202` / `TASK-202-5`.
2. Run all verification gates:
```powershell
python tools/verify_all_specs.py --check-readmes; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/verify_context_docs.py }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }
```
And run the standalone completeness audit on the new `Draft` spec:
```powershell
python -c "from pathlib import Path; import re; p=Path('docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md'); txt=p.read_text(encoding='utf-8'); secs=[f'## {i}.' for i in range(1,11)]+['validateMission','renderCheckpoints','renderCanvas','exportJson','importJson','textContent']; miss_s=[s for s in secs if s not in txt]; assert not miss_s, miss_s; m=re.findall(r'\x60\x60\x60mermaid\n(.*?)\n\x60\x60\x60', txt, re.S); assert len(m)>=1 and all(b.count('\"')%2==0 for b in m); links=re.findall(r'\[[^\]]+\]\(([^)]+)\)', txt); bad=[l for l in links if not l.startswith(('http','#')) and not (p.parent/l.split('#')[0]).resolve().exists()]; assert not bad, bad; banned=['UAP','SAS','WAP','VAS-Core','VAS-Align','VAC-Align','VAC-Core','valkyrien','vs2','cc_vs','kontraption:','world-class','best-in-class','flawless','zero-defect','bulletproof','guarantee']; hits=[b for b in banned if re.search(r'(?<![A-Za-z0-9])'+re.escape(b)+r'(?![A-Za-z0-9])', txt, re.I)]; assert not hits, hits; print('SPEC_AUDIT_PASS', len(txt.splitlines()))"
```
Expected:
- `verify_all_specs.py --check-readmes`: `0 Errors, 0 Warnings`
- `verify_spec_status.py`: `[PASS] All 15 specs have valid statuses (9 Implemented, 6 Approved)!`
- `verify_context_docs.py`: `[PASS] context docs: 0 findings`
- `tests/harness`: `82 tests OK` (or current baseline passing)
- `SPEC_AUDIT_PASS <line_count>` with zero missing sections, zero broken links, and zero banned terms.

- [ ] **Step 5: Commit Task 4**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md TASK.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(amm): complete WebUI mission editor Draft specification (v0.1.0) and sync TASK.md"
```
