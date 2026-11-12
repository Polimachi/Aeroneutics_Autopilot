# AMM WebUI Mission Editor Specification (`Draft` v0.1.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Commit the pending roadmap/context docs on `main`, sync `feat/task-202-5` with `main`, and author `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (`Status: Draft`, `Version: v0.1.0`, `Date: 2026-11-12`) aligned with `AMM v1.3.0` / `ICD v1.28.0` / `Diagram v2.13.0` so `TASK-402` can implement `tools/amm_mission_editor.html` without ambiguity.

**Architecture:** The specification lives beside `AMM_PROGRAM_SPECIFICATION.md` (`v1.3.0 Approved`) inside `docs/specs/3_planning/amm/` so relative links to Tier 1/2 system specs (`../../../system/...`) remain identical and `Status: Draft` keeps `tools/verify_spec_status.py` at `15` active specs (`7 Implemented, 8 Approved`) until review. It supersedes the stale `v1.2.0` draft plan (`docs/superpowers/plans/2026-11-11-amm-webui-editor-spec-draft.md`) by aligning the pipeline diagram (`trajectory_generator` -> `Base+4 [I-12]`, Coroutine B 5Hz `file_transfer`), `AMM v1.3.0` §10.2 config keys, and exported mission JSON `"version": "1.3.0"` while maintaining parity with the 13-action, 12-condition, and 4-hook Lua runtime (`mission_engine.lua`, `condition_evaluator.lua`, `hook_runner.lua`).

**Tech Stack:** Git Worktree, Markdown (GFM), Mermaid Diagrams, JSON Schema contracts, HTML5/CSS/Vanilla JS UI/Canvas specification, Python 3.10+ Verifiers (`tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/verify_context_docs.py`).

**Spec & SSOT Inputs:**
- Primary Parent Spec: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v1.3.0 Approved` — §1.1, §4.6, §6.1–6.6, §9, §10, §11.2)
- Master ICD: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.28.0 Approved` — Interface I-6, I-11, I-12)
- System Diagram: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.13.0 Approved`)
- Lifecycle Standard: `docs/specs/README.md` (5-field metadata table, Permanent Unified Path, `Draft` rules)
- Lua Runtime SSOT:
  - `src/3_planning/amm/modules/mission_engine.lua` (`ACTIVE_ACTIONS`, `DEFERRED_ACTIONS`, `ACTION_TAXONOMY`, `validate_*`, `extract_target_pos`, `convert_legacy_items`, `save`)
  - `src/3_planning/amm/modules/condition_evaluator.lua` (`CONDITION_TYPES`, `resolve_default_complete`, `evaluate_group`)
  - `src/3_planning/amm/modules/hook_runner.lua` (`VALID_HOOK_TYPES`, `VALID_SIDES`, `resolve_color_mask`)
  - `src/3_planning/amm/modules/network_manager.lua` (Zone 3 `Base + 20..29`)
  - `src/3_planning/amm/config/amm_config.json` (current v1.0.0 runtime keys vs `AMM v1.3.0` §10.2 target config schema)
- Prior Baseline Plan (superseded by this plan): `docs/superpowers/plans/2026-11-11-amm-webui-editor-spec-draft.md`
- Roadmap SSOT: `TASK.md` (`TASK-202-5`, `TASK-402`)

## Global Constraints

- **Scope Isolation (`TASK-202-5` vs `TASK-402`)**: `TASK-202-5` delivers only the specification (`docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md`) and roadmap/context sync (`TASK.md`, `.agent/memory/workspace-root.md`). Do NOT create `tools/amm_mission_editor.html` or modify `src/` runtime Lua files (`TASK-402` scope).
- **Metadata & Lifecycle Gate (`docs/specs/README.md`, `.agent/rules/skill-workflows.md`)**: Set `문서 상태 (Status)` to `` `Draft` ``, `문서 버전 (Version)` to `` `v0.1.0` ``, `최종 수정일 (Date)` to `` `2026-11-12` ``, `구현 코드 (Source)` to `` `tools/amm_mission_editor.html` ``, and `주관 도메인 (Domain)` to `임무 계획 외부 웹 GUI 미션 에디터 (AMM Companion Tool / Host PC)`. Do NOT invoke `specification-lifecycle-manager` and do NOT modify `AMM_PROGRAM_SPECIFICATION.md`, `docs/system/*.md`, `tools/verify_all_specs.py`, or `tools/verify_spec_status.py` while authoring a `Draft` spec.
- **Zero-Install Single-File Target (`AMM_PROGRAM_SPECIFICATION.md` §9.1)**: `tools/amm_mission_editor.html` must operate offline via `file://` in standard desktop browsers as one self-contained HTML5/CSS/Vanilla JS file with zero external CDN `<script>`/`<link>` imports, zero build tools, and zero `fetch()`/WebSocket network calls.
- **`AMM v1.3.0` Alignment Constants**:
  - Exported mission JSON `"version"` defaults to `"1.3.0"`; importer accepts `"1.1.0"` / `"1.2.0"` / `"1.3.0"` cleanly and upgrades `"1.0.0"` `items[]` queues.
  - RF Channel Standard: `Base = 10000 + (N - 1) * 40` ($N = 1 \dots 1000$), Zone 3 offset `20..29` (`Base + 20 .. Base + 29`), trajectory bus `Base+4` (`[I-12]`).
  - Defaults (`AMM v1.3.0` §10.2 `channels.baseChannel = 10000`, `trajectory.{defaultAlt = 150.0, defaultSpeed = 18.0, arrivalRadius = 15.0}` and `mission_engine.lua`): `FLY_OVER` fallback `20.0`, `FLY_TO` precision default `5.0`, `headingMode = "AUTO"`, `ORBIT` `radius = 30.0` / `direction = "CW"`, `PATROL` `patrolMode = "LOOP"` / `cycles = 1`, `PAYLOAD_ACTION` `waitForAck = true` / `expectedStatus = "OK"`, `REDSTONE_PULSE` `durationMs = 500`, `REDSTONE_ACTION` `durationMs = 0` / `minLevel = 1`.
  - 6 Redstone Sides: `top`, `bottom`, `left`, `right`, `front`, `back`.
  - 16 CC:Tweaked Colors: `white`, `orange`, `magenta`, `lightBlue`, `yellow`, `lime`, `pink`, `gray`, `lightGray`, `cyan`, `purple`, `blue`, `brown`, `green`, `red`, `black`.
- **UI Language & Security Policy**: English cockpit/avionics UI labels with bilingual (Korean/English) helper tooltips; strict DOM XSS safety (`document.createElement` + `textContent`, zero `innerHTML` with JSON or user strings).
- **Static & Governance Hygiene (`tools/verify_all_specs.py`, `tools/verify_context_docs.py`, `.agent/rules/domain-aeronautics.md`)**:
  - Balanced double quotes (`"`) in every `mermaid` fenced block.
  - Zero broken relative markdown links and zero stale lifecycle paths (`drafts/`, `approved/`, `implemented/`, `archived/`).
  - Zero legacy prohibited terminology (`UAP`, `SAS`, `WAP`, `VAS-Core`, `VAS-Align`, `VAC-Align`, `VAC-Core`), zero Valkyrien Skies / `kontraption:` identifiers, and zero unverified overclaim terms (`AGENTS.md` Overclaim Ban).

## Review Focus

1. **`AMM v1.3.0` vs Current `mission_engine.lua` Version/Config Transition**: Exported JSON uses `"version": "1.3.0"` and §2/§10 reference `AMM v1.3.0` §10.2 (`channels.baseChannel`, `trajectory.*`) and `trajectory_generator -> Base+4 [I-12]`, while explicitly noting that current on-disk `mission_engine.lua` defaults `"1.1.0"` and `amm_config.json` `v1.0.0` uses flat keys until `TASK-207` and `TASK-402` align both sides. Pinned in Tasks 1, 2, and 4.
2. **Field-Name & Default Asymmetry (`mission_engine.lua` vs `hook_runner.lua`)**: `PAYLOAD_ACTION` uses `params.commandPayload` whereas `ZONE3_PAYLOAD_CMD` hook uses `hook.payload`; `FLY_TO` defaults `acceptanceRadius` to `5.0` rather than `defaults.acceptanceRadius` (`15.0`); `ORBIT.radius` passes schema validation at `> 0` while `FCP` / `LOITER` clamps at `>= 5.0m`; `TIMEOUT_SEC` uses key `timeout` (not `timeoutSec`). Pinned in Tasks 2 and 3.
3. **Minecraft `(X, Z)` Coordinate Handedness & Canvas Angles**: `+X` points East (right), `-Z` points North (top), `+Z` points South (bottom). Heading `0°` (`North = -Z`) maps to canvas radian `-Math.PI / 2`, and `CW`/`CCW` orbit sweep follows screen clockwise (`+X -> +Z -> -X -> -Z`). Pinned in Task 4.
4. **Validation Severity Separation (`ERROR` vs `WARNING`) & Empty Condition Group Trap**: `validate_mission_table` accepts the 4 deferred actions (`TAKEOFF_RUNWAY`, `LAND_RUNWAY`, `DOCK_ARM`, `UNDOCK_ARM`) structurally while runtime `enter_checkpoint` rejects them with `DEFERRED_ACTION_UNSUPPORTED`; `condition_evaluator.evaluate_group` returns `false` on `conditions: []` instead of falling back to defaults, so the spec must omit empty `completeWhen`/`abortWhen` objects on export. Pinned in Tasks 2 and 3.
5. **Legacy v1.0.0 Upgrade, Unknown-Field Preservation & `TASK-402` Acceptance Gate**: Importing `{ version: "1.0.0", items: [...] }` converts items to `FLY_OVER` + trailing `LAND_LAUNCHPAD` when the final item defines `facilityId`; `params.{x, z}` shorthand normalizes to `params.targetPos`; unrecognized keys survive round-trip; and §10 pins the `TASK-402` static/security gate, CraftOS-PC JSON round-trip test, and `file://` viewport verification. Pinned in Tasks 2 and 4.

---

## File Structure

- Commit on `main` (pre-sync): `TASK.md`, `GEMINI.md`, `README.md`, `docs/superpowers/plans/2026-11-12-task-207-208-209-sequential-plan.md` — already modified/untracked on root `main`; commit cleanly and merge into `feat/task-202-5`.
- Create (in `.worktrees/feat-task-202-5`): `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` — Standalone `Draft` (`v0.1.0`) technical specification for `tools/amm_mission_editor.html` covering §1–§10.
- Modify (in `.worktrees/feat-task-202-5`): `TASK.md` — Mark `TASK-202-5` `[x]` with completed summary (`AMM_MISSION_EDITOR_SPECIFICATION.md` `v0.1.0 Draft`), close parent `TASK-202` `[x]` into `## ✅ 3. 완료된 작업 이력` (respecting the 10-entry archive cap), and link `v0.1.0 Draft` under `TASK-402`.
- Modify (in `.worktrees/feat-task-202-5`): `.agent/memory/workspace-root.md` — Append `TASK-202-5` completion entry per `verify_context_docs.py` R8.

---

### Task 0: Commit Pending `main` Docs & Sync `feat/task-202-5`

**Files:**
- Commit on `main`: `TASK.md`, `GEMINI.md`, `README.md`, `docs/superpowers/plans/2026-11-12-task-207-208-209-sequential-plan.md`
- Sync into worktree `.worktrees/feat-task-202-5`: branch `feat/task-202-5`

**Interfaces:**
- Consumes: uncommitted doc edits currently on root `main` working tree.
- Produces: clean `main` commit and updated `feat/task-202-5` base containing the `TASK-202-5` / `TASK-402` split in `TASK.md`.

- [ ] **Step 1: Verify `main` working tree contains only the 4 expected doc files**

Run in repo root:
```powershell
& "C:\Program Files\Git\cmd\git.exe" status -sb
```
Expected: `## main...origin/main` with `M GEMINI.md`, `M README.md`, `M TASK.md`, `?? docs/superpowers/plans/2026-11-12-task-207-208-209-sequential-plan.md`.

- [ ] **Step 2: Run context/spec verifiers on `main` before committing**

Run in repo root:
```powershell
python tools/verify_context_docs.py; if ($?) { python tools/verify_all_specs.py }; if ($?) { python tools/verify_spec_status.py }
```
Expected: `0 findings`, `0 Errors, 0 Warnings`, `7 Implemented, 8 Approved`.

- [ ] **Step 3: Commit the 4 docs on `main`**

Run in repo root:
```powershell
& "C:\Program Files\Git\cmd\git.exe" add TASK.md GEMINI.md README.md docs/superpowers/plans/2026-11-12-task-207-208-209-sequential-plan.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(roadmap): sync TASK-206/122 context docs, split TASK-402, and add 207-209 plan"
```
Expected: clean working tree on `main`.

- [ ] **Step 4: Merge `main` into `feat/task-202-5` inside `.worktrees/feat-task-202-5`**

Run inside `.worktrees/feat-task-202-5`:
```powershell
Push-Location .worktrees/feat-task-202-5; & "C:\Program Files\Git\cmd\git.exe" merge --no-ff main -m "chore(worktree): sync feat/task-202-5 with main roadmap split"; & "C:\Program Files\Git\cmd\git.exe" status -sb; Pop-Location
```
Expected: fast-forward or clean merge commit, `TASK.md` in `.worktrees/feat-task-202-5` now contains `TASK-202-5` (spec-only) and `TASK-402`.

---

### Task 1: Specification Metadata, `AMM v1.3.0` Pipeline & Design Tokens (`§1`–`§3`)

**Files:**
- Create: `.worktrees/feat-task-202-5/docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md`

**Interfaces:**
- Consumes: `docs/specs/README.md` (5-field metadata table & `Draft` conventions), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v1.3.0` §1.1, §4.6, §6.6, §9, §10.2).
- Produces: `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` header (`Status: Draft`, `Version: v0.1.0`, `Date: 2026-11-12`), `### Revision History`, relative links (`v1.3.0`, `v1.28.0`, `v2.13.0`), and `§1`–`§3`.

- [ ] **Step 1: Confirm target spec file does not exist yet in `.worktrees/feat-task-202-5`**

Run:
```powershell
Push-Location .worktrees/feat-task-202-5; python -c "from pathlib import Path; d=Path('docs/specs/3_planning/amm'); assert d.is_dir(); assert not (d/'AMM_MISSION_EDITOR_SPECIFICATION.md').exists(); print('READY')"; Pop-Location
```
Expected: `READY`

- [ ] **Step 2: Create `AMM_MISSION_EDITOR_SPECIFICATION.md` with header metadata, Revision History, and `§1`–`§3`**

Include exact metadata and sections:
1. **Title & Standard 5-Field Metadata Table**:
   - Title: `# AMM WebUI Mission Editor (호스트 PC 외부 비주얼 미션 에디터) 상세 규격서`
   - Metadata table:
     - `문서 상태 (Status)`: `` `Draft` ``
     - `문서 버전 (Version)`: `` `v0.1.0` ``
     - `최종 수정일 (Date)`: `` `2026-11-12` ``
     - `구현 코드 (Source)`: `` `tools/amm_mission_editor.html` ``
     - `주관 도메인 (Domain)`: `임무 계획 외부 웹 GUI 미션 에디터 (AMM Companion Tool / Host PC)`
   - Relative links (`../../../system/...` and `./AMM_PROGRAM_SPECIFICATION.md`):
     - `[AMM_PROGRAM_SPECIFICATION.md](AMM_PROGRAM_SPECIFICATION.md)` (`v1.3.0 Approved`)
     - `[AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md)` (`v1.28.0 Approved`)
     - `[SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md](../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md)` (`v2.13.0 Approved`)
     - `[GEMINI.md](../../../../GEMINI.md)`
   - `### Revision History` (`v0.1.0 | 2026-11-12 | ...`).
2. **`## 1. 프로그램 개요 및 불변 제약 (Overview, Constraints & Non-Goals)`**:
   - Single offline HTML5/CSS/Vanilla JS file (`file://`), full parity with AMM (`13 actions`, `12 conditions`, `4 hooks`, `v1.0.0` legacy import, `"version": "1.3.0"` export), 2D `(X, Z)` tactical canvas, live preflight diagnostics.
   - Hard constraints: zero external CDN/CSS/JS, zero `fetch()`/WebSocket calls, DOM XSS safety (`document.createElement` + `textContent` strictly; forbid `innerHTML` with untrusted/JSON strings).
   - Non-goals: no live in-game telemetry/RF modem connection, no server process, no 3D WebGL terrain, no Valkyrien Skies / `kontraption:` concepts.
3. **`## 2. 시스템 연동 및 외부 파일 파이프라인 (System Context & In-Game Workflow)`**:
   - Mermaid `flowchart LR` aligned to `AMM v1.3.0`: `tools/amm_mission_editor.html` -> `validateMission()` -> Export `.json` -> Inject via (a) CC `file_transfer` (Coroutine B 5Hz), (b) `/disk/` or `/disk/missions/`, (c) `missions/` -> `mission_engine.resolve_path` & `validate_mission_table` -> `mission_engine` (Coroutine A 20Hz) -> `trajectory_generator` -> `FCP (Base+4 [I-12])` & `Zone 3 (Base+20~29)`.
   - Reference `AMM v1.3.0` §10.2 baseline (`channels.baseChannel = 10000`, `trajectory.defaultAlt = 150.0`, `trajectory.defaultSpeed = 18.0`, `trajectory.arrivalRadius = 15.0`) + note current `amm_config.json` v1.0.0 flat keys (`TASK-202-4`) and `Base = 10000 + (N - 1) * 40` preview calculator for `PAYLOAD_ACTION` / `ZONE3_PAYLOAD_CMD`.
4. **`## 3. UI 레이아웃, 디자인 시스템 및 반응형 규격 (Layout Shell & Design Tokens)`**:
   - Industrial Avionics Dark Cockpit CSS tokens (`--bg-app: #0b0f17`, `--bg-panel: #111827`, `--bg-elevated: #1b2434`, `--border-default: #2b394e`, `--text-primary: #e5edf7`, `--text-muted: #94a3b8`, `--accent-cyan: #22d3ee`, `--accent-amber: #f59e0b`, `--accent-green: #10b981`, `--accent-red: #ef4444`, `--accent-violet: #a78bfa`), monospace data font stack (`'JetBrains Mono', 'Cascadia Code', Consolas, monospace`).
   - UI copy policy: English cockpit/avionics labels on controls/headers + bilingual (Korean/English) helper tooltips and status explanations.
   - 5-region workspace grid (Top Action Bar `52px`, Left Sequence Rail `300px`, Center 2D `(X, Z)` Canvas `1fr` min `420px`, Right Inspector & JSON Drawer `420px`, Bottom Preflight Bar `32px` expandable), `< 1150px` responsive stack/tabs, and `aria-label` keyboard focus accessibility.

- [ ] **Step 3: Run structural & link verification on `§1`–`§3`**

Run:
```powershell
Push-Location .worktrees/feat-task-202-5; python -c "from pathlib import Path; import re; p=Path('docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md'); txt=p.read_text(encoding='utf-8'); assert re.search(r'\*\*문서 상태 \(Status\)\*\*\s*\|\s*\x60Draft\x60', txt); assert re.search(r'\*\*문서 버전 \(Version\)\*\*\s*\|\s*\x60v0\.1\.0\x60', txt); assert 'v1.3.0' in txt and 'v1.28.0' in txt and 'v2.13.0' in txt; assert 'Base+4' in txt; links=re.findall(r'\[[^\]]+\]\(([^)]+)\)', txt); bad=[l for l in links if not l.startswith(('http','#')) and not (p.parent/l.split('#')[0]).resolve().exists()]; assert not bad, bad; m=re.findall(r'\x60\x60\x60mermaid\n(.*?)\n\x60\x60\x60', txt, re.S); assert len(m)>=1 and all(b.count('\"')%2==0 for b in m); print('TASK1_PASS', len(links), len(m))"; Pop-Location
```
Expected: `TASK1_PASS <links> <mermaid_blocks>` with exit code `0`.

- [ ] **Step 4: Commit Task 1**

```powershell
Push-Location .worktrees/feat-task-202-5; & "C:\Program Files\Git\cmd\git.exe" add docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md; & "C:\Program Files\Git\cmd\git.exe" commit -m "docs(amm): draft WebUI mission editor spec skeleton, v1.3.0 context, and layout (TASK-202-5)"; Pop-Location
```

---

### Task 2: State Model, Legacy Migration & 13-Action Form Contract (`§4`–`§5`)

**Files:**
- Modify: `.worktrees/feat-task-202-5/docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (append `§4` and `§5`)

**Interfaces:**
- Consumes: `src/3_planning/amm/modules/mission_engine.lua` (`ACTIVE_ACTIONS`, `DEFERRED_ACTIONS`, `ACTION_TAXONOMY`, `validate_*`, `extract_target_pos`, `convert_legacy_items`, `save`).
- Produces: `§4` (`EditorState` with `"version": "1.3.0"`, `convertLegacyItems`, `v1.1.0`/`v1.2.0` import compatibility, shorthand `(x, z)` promotion, `_extra` unknown-field preservation, `localStorage` autosave) and `§5` (Mission Header + 13-Action Parameter/Control Matrix).

- [ ] **Step 1: Append `## 4. 에디터 상태 모델, 하위 호환 변환 및 영속성 (§4)`**

Specify exact structures and rules:
1. **`EditorState`**:
   - `mission`: `{ missionId, version: "1.3.0", description, executionMode, fallbackPolicy, defaults: { cruiseSpeed, targetAlt, acceptanceRadius, headingMode }, checkpoints: [...] }`, plus hidden `_extra` bag for unrecognized top-level, checkpoint, `params`, condition, or hook keys so round-trip editing preserves hand-authored extensions.
   - `ui`: `{ selectedIndex, selectedPatrolIndex, activeInspectorTab, activeHookTab, rawJsonOpen, validationExpanded, activeTool, gridSnapM, baseChannel, dirty }`.
   - `canvas`: `{ camX, camZ, zoomPxPerM, draggingNode, isPanning }`.
   - `history`: `{ undoStack: [], redoStack: [], maxDepth: 50 }` storing structured clones of `mission` + `selectedIndex`.
2. **Version Import & Legacy Upgrade (`convertLegacyItems`)**:
   - Accept `"1.1.0"`, `"1.2.0"`, and `"1.3.0"` checkpoint-based files seamlessly (recording `importedFromVersion` badge when `< "1.3.0"` and normalizing `"version"` to `"1.3.0"` on canonical export, noting `mission_engine.lua` compatibility).
   - Detect legacy `"1.0.0"` queue (`Array.isArray(raw.items) && !Array.isArray(raw.checkpoints)`): convert each `item` to `FLY_OVER` (`targetPos: { x, z }`, optional `targetAlt`, `cruiseSpeed`) and append `LAND_LAUNCHPAD` if `last.facilityId` is a non-empty string; display non-blocking toast `"Legacy v1.0.0 queue upgraded to v1.3.0 checkpoints"`.
3. **Shorthand Coordinate Normalization**: Promote numeric `params.x` / `params.z` without `params.targetPos` to `params.targetPos = { x, z }` and omit temporary shorthand keys on export.
4. **Autosave Recovery (`localStorage`)**: `500ms` debounced write to `uafs_amm_editor_autosave_v1` (`{ savedAtIso, mission }`), prompting `[Restore Draft]` / `[Dismiss]` banner on load when differing from default template.

- [ ] **Step 2: Append `## 5. 미션 헤더 및 13종 체크포인트 액션 폼 매트릭스 (§5)`**

Specify:
1. **Mission Header & Global `defaults`**: `missionId` (`"SORTIE_ALPHA"`), `version` (`"1.3.0"`), `description`, `executionMode` (`"SINGLE"` | `"REPEAT"`), `fallbackPolicy` (`"RTH"` | `"HOVER_HOLD"` | `"LOITER"` | `"SKIP_NEXT"`), and `defaults.{cruiseSpeed (18.0), targetAlt (150.0), acceptanceRadius (15.0), headingMode ("AUTO"|"FIXED"|"POI")}`.
2. **Checkpoint Envelope Controls**: `checkpointId`, `action` grouped into `1. Navigation (Active 5)`, `2A. Infrastructure (Active 2)`, `3. Special Devices (Active 2)`, `2B. Infrastructure (Deferred 4)`, optional `fallbackPolicy` override, plus Add / Duplicate / Delete / Move Up/Down / Drag Reorder.
3. **Complete 13-Action Field Matrix**:
   - `FLY_OVER`: `targetPos.{x, z}`, `targetAlt`, `cruiseSpeed`, `acceptanceRadius` (inherits `defaults.acceptanceRadius`, fallback `20.0`), `headingMode`, conditional `fixedHeading` (`0..360`).
   - `FLY_TO`: identical spatial/dynamics fields except `acceptanceRadius` defaults explicitly to `5.0 m` (never inheriting `defaults.acceptanceRadius = 15.0`).
   - `ORBIT`: `targetPos.{x, z}`, `radius` (`> 0`, default `30.0`, advisory badge if `< 5.0`), `direction` (`"CW"` | `"CCW"`, default `"CW"`), `durationSec` (optional `>= 0`), `targetAlt`, `cruiseSpeed`.
   - `PATROL`: `waypoints[]` (`min 1` row `{ x, z, alt?, speed?, acceptanceRadius? }`), `patrolMode` (`"LOOP"` | `"PING_PONG"`, default `"LOOP"`), `cycles` (`>= 1`, default `1`), `durationSec`, `targetAlt`, `cruiseSpeed`, `acceptanceRadius`.
   - `POI_HOLD`: `targetPos.{x, z}`, `poiPos.{x, y?, z}` (`x, z` required, `y` optional), `headingMode` (default `"POI"`), `durationSec`, `targetAlt`, `cruiseSpeed`.
   - `TAKEOFF_LAUNCHPAD`: optional `facilityId`, `targetAlt`, optional `targetPos.{x, z}` canvas marker.
   - `LAND_LAUNCHPAD`: `facilityId` and/or `targetPos.{x, z}` (**at least one required** — `INVALID_LAND_PARAMS`), `targetAlt`.
   - `PAYLOAD_ACTION`: `channelOffset` (`20..29`, default `20`) or `targetChannel` (`Base+20..29`) with live `Base + offset` preview, `command` (required non-empty), `commandPayload` (JSON object textarea, default `"{}"`), `waitForAck` (`true`), `expectedStatus` (`"OK"`).
   - `REDSTONE_ACTION`: `mode` (`"EMIT"` | `"WAIT_INPUT"`), `side` (6 sides), optional `color` (16 CC colors), `level` (`0..15`), `state` (bool), `durationMs` (`>= 0`, default `0`), `minLevel` (`1..15`, default `1`).
   - `TAKEOFF_RUNWAY`, `LAND_RUNWAY`, `DOCK_ARM`, `UNDOCK_ARM` (`DEFERRED`): amber warning banner (`DEFERRED_ACTION_UNSUPPORTED`) + optional `facilityId` / `targetPos.{x, z}` / `targetAlt` fields.

- [ ] **Step 3: Verify 13-action & v1.3.0 schema coverage in `§4`–`§5`**

Run:
```powershell
Push-Location .worktrees/feat-task-202-5; python -c "from pathlib import Path; txt=Path('docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md').read_text(encoding='utf-8'); req=['1.3.0','FLY_OVER','FLY_TO','ORBIT','PATROL','POI_HOLD','TAKEOFF_LAUNCHPAD','LAND_LAUNCHPAD','PAYLOAD_ACTION','REDSTONE_ACTION','TAKEOFF_RUNWAY','LAND_RUNWAY','DOCK_ARM','UNDOCK_ARM','convertLegacyItems','commandPayload','waitForAck','expectedStatus','channelOffset','patrolMode','DEFERRED_ACTION_UNSUPPORTED','5.0']; miss=[k for k in req if k not in txt]; assert not miss, miss; print('TASK2_PASS')"; Pop-Location
```
Expected: `TASK2_PASS`

- [ ] **Step 4: Commit Task 2**

```powershell
Push-Location .worktrees/feat-task-202-5; & "C:\Program Files\Git\cmd\git.exe" add docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md; & "C:\Program Files\Git\cmd\git.exe" commit -m "docs(amm): specify WebUI state model, v1.3.0 migration, and 13-action forms (TASK-202-5)"; Pop-Location
```

---

### Task 3: 12-Condition & 4-Hook Builders and Lua-Parity Preflight Validator (`§6`–`§7`)

**Files:**
- Modify: `.worktrees/feat-task-202-5/docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (append `§6` and `§7`)

**Interfaces:**
- Consumes: `src/3_planning/amm/modules/condition_evaluator.lua`, `src/3_planning/amm/modules/hook_runner.lua`, `src/3_planning/amm/modules/mission_engine.lua`, `AMM_PROGRAM_SPECIFICATION.md` (`v1.3.0` §6.3–§6.4).
- Produces: `§6` (12-condition builder, empty-group omission rule, `AMM v1.3.0` default `completeWhen` table, 4-hook builder, 16-color CC table) and `§7` (`validateMission()` real-time Lua-parity engine & error/warning catalog).

- [ ] **Step 1: Append `## 6. 12종 조건 빌더 및 4종 라이프사이클 훅 빌더 (§6)`**

Specify:
1. **Condition Group Builders (`completeWhen` & `abortWhen`)**:
   - Logic selector: `"ALL"` (default `completeWhen`) / `"ANY"` (default `abortWhen`).
   - Empty Group Omission Rule: omit `completeWhen` / `abortWhen` completely when `conditions.length === 0` so `condition_evaluator.evaluate_group(..., {})` never returns `false` forever.
   - **Per-Action Default `completeWhen` Preview Table** (`AMM v1.3.0` §6.3): note `TAKEOFF_LAUNCHPAD` completes on `ALTITUDE_REACHED` (`±5m`) OR `flightMode == "CRUISE"`.
2. **Complete 12-Condition Field Matrix**: `PROXIMITY_2D`, `PROXIMITY_3D`, `ALTITUDE_REACHED`, `DURATION_SEC`, `TIMEOUT_SEC` (key `timeout`, NOT `timeoutSec`), `FUEL_LEVEL_BELOW`, `FACILITY_TOUCHDOWN`, `PAYLOAD_RESP_MATCH`, `REDSTONE_INPUT_HIGH`, `CROSS_TRACK_ERROR`, `ARM_DOCKED`, `ARM_RELEASED`.
3. **3-Tab Lifecycle Hook Builder (`onEnter`, `onExit`, `onAbort`)**: `REDSTONE_SET`, `REDSTONE_PULSE` (`durationMs = 500`), `ZONE3_PAYLOAD_CMD` (uses `hook.payload`, distinct from `params.commandPayload`), `NOTIFY_OPERATOR`, plus the 16 CC:Tweaked color reference table (`white`..`black`).

- [ ] **Step 2: Append `## 7. 실시간 프리플라이트 스키마 검증 엔진 (§7)`**

Specify `validateMission(mission, opts)`:
1. **Output Model**: `{ valid: boolean, errors: ValidationIssue[], warnings: ValidationIssue[] }`, `valid === (errors.length === 0)`.
2. **Error & Warning Catalog** (1:1 parity with `mission_engine.validate_mission_table`):
   - Errors: `EMPTY_CHECKPOINTS`, `INVALID_EXECUTION_MODE`, `INVALID_FALLBACK_POLICY`, `UNKNOWN_ACTION`, `INVALID_TARGET_POS`, `INVALID_ACCEPTANCE_RADIUS`, `INVALID_TARGET_ALT`, `INVALID_FACILITY_ID`, `INVALID_ORBIT_RADIUS`, `INVALID_ORBIT_DIRECTION`, `INVALID_PATROL_WAYPOINTS`, `INVALID_PATROL_MODE`, `INVALID_PATROL_CYCLES`, `MISSING_POI_POS`, `INVALID_POI_POS`, `INVALID_LAND_PARAMS`, `INVALID_ZONE3_CHANNEL`, `MISSING_PAYLOAD_COMMAND`, `INVALID_JSON_PAYLOAD`, `INVALID_REDSTONE_MODE`, `INVALID_REDSTONE_SIDE`, `INVALID_REDSTONE_DURATION`, `INVALID_CONDITION_LOGIC`, `UNKNOWN_CONDITION_TYPE`, `EMPTY_CONDITION_GROUP`, `INVALID_CONDITION_PARAM`, `UNKNOWN_HOOK_TYPE`, `INVALID_HOOK_PARAM`.
   - Warnings: `DEFERRED_ACTION_UNSUPPORTED`, `ORBIT_RADIUS_BELOW_FCP_MIN`, `MISSING_DURATION_HOLD_MANUAL`, `PATROL_SINGLE_WP_DEGENERACY`.
3. **Interactive Diagnostic UX**: live synchronous execution (`< 5ms`), export confirmation prompt when `errors.length > 0`, clickable `CP#k` chips focusing checkpoint & canvas coordinates.

- [ ] **Step 3: Verify 12-condition, 4-hook, 16-color, and error catalog coverage in `§6`–`§7`**

Run:
```powershell
Push-Location .worktrees/feat-task-202-5; python -c "from pathlib import Path; txt=Path('docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md').read_text(encoding='utf-8'); conds=['PROXIMITY_2D','PROXIMITY_3D','ALTITUDE_REACHED','DURATION_SEC','TIMEOUT_SEC','FUEL_LEVEL_BELOW','FACILITY_TOUCHDOWN','PAYLOAD_RESP_MATCH','REDSTONE_INPUT_HIGH','CROSS_TRACK_ERROR','ARM_DOCKED','ARM_RELEASED']; hooks=['REDSTONE_SET','REDSTONE_PULSE','ZONE3_PAYLOAD_CMD','NOTIFY_OPERATOR']; cols=['white','orange','magenta','lightBlue','yellow','lime','pink','gray','lightGray','cyan','purple','blue','brown','green','red','black']; errs=['EMPTY_CHECKPOINTS','UNKNOWN_ACTION','INVALID_ZONE3_CHANNEL','MISSING_PAYLOAD_COMMAND','INVALID_LAND_PARAMS','INVALID_REDSTONE_SIDE','UNKNOWN_CONDITION_TYPE','UNKNOWN_HOOK_TYPE']; miss=[x for x in conds+hooks+cols+errs if x not in txt]; assert not miss, miss; print('TASK3_PASS')"; Pop-Location
```
Expected: `TASK3_PASS`

- [ ] **Step 4: Commit Task 3**

```powershell
Push-Location .worktrees/feat-task-202-5; & "C:\Program Files\Git\cmd\git.exe" add docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md; & "C:\Program Files\Git\cmd\git.exe" commit -m "docs(amm): specify 12-condition/4-hook builders and Lua-parity preflight validator (TASK-202-5)"; Pop-Location
```

---

### Task 4: 2D `(X, Z)` Canvas, JSON I/O, `TASK-402` Acceptance Criteria & Roadmap/Memory Sync (`§8`–`§10`)

**Files:**
- Modify: `.worktrees/feat-task-202-5/docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (append `§8`, `§9`, `§10`)
- Modify: `.worktrees/feat-task-202-5/TASK.md` (mark `TASK-202-5` `[x]`, move closed `TASK-202` to `## ✅ 3. 완료된 작업 이력` keeping <= 10 items, link `AMM_MISSION_EDITOR_SPECIFICATION.md` `v0.1.0 Draft` under `TASK-402`)
- Modify: `.worktrees/feat-task-202-5/.agent/memory/workspace-root.md` (append `TASK-202-5` completion summary per `verify_context_docs.py` R8)

**Interfaces:**
- Consumes: `AMM_PROGRAM_SPECIFICATION.md` (`v1.3.0` §6.2, §9, §10, §11.2), `tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/verify_context_docs.py`.
- Produces: Complete `§8`–`§10` of `AMM_MISSION_EDITOR_SPECIFICATION.md` and synchronized `TASK.md` + `.agent/memory/workspace-root.md`.

- [ ] **Step 1: Append `## 8. 2D (X, Z) 전술 경로 프리뷰 캔버스 규격 (§8)`**

Specify:
1. Minecraft `(X, Z)` affine transform (`+X` East right, `-Z` North up, `+Z` South down), `canvasRad = (headingDeg - 90) * Math.PI / 180`, grid snap (`Off|1m|10m|50m`), HiDPI scaling (`devicePixelRatio`).
2. 8 ordered rendering layers (adaptive metric grid & compass, primary trajectory + `REPEAT` wrap-around leg, `acceptanceRadius` & `ORBIT` `CW`/`CCW` rings, `PATROL` `LOOP`/`PING_PONG` polyline, `POI_HOLD` dashed amber sightline, distinct node glyphs & non-spatial satellite badges, `FIXED` nose heading vector, top-left canvas HUD overlay).
3. Pointer state machine (`wheel` zoom `0.05..10.0 px/m`, Middle/Right/`Space+Left` pan, `SELECT`/`ADD_FLY_OVER`/`PICK_TARGET`/`PICK_POI`/`ADD_PATROL_WP` modes, `Fit All` with `15%` padding).

- [ ] **Step 2: Append `## 9. JSON 입출력, 스타터 프리셋 및 단축키 규격 (§9)`**

Specify:
1. Starter templates (`Sortie Alpha (Full Example)` with `"version": "1.3.0"`, `Patrol Perimeter`, `Payload Delivery`, `Empty Draft`).
2. Import (`<input type="file" accept=".json">`, window drag-and-drop, Raw JSON drawer `Apply JSON`), Export (`2`-space JSON omitting empty `completeWhen`/`abortWhen`, downloading `${missionId.toLowerCase()}.json`), `Copy JSON` (clipboard + textarea fallback), DOM-safe Raw JSON highlighting (`<span>` text nodes only).
3. Keyboard shortcuts (`Ctrl+Z`, `Ctrl+Y`/`Ctrl+Shift+Z`, `F`, `Delete`, `1`/`2`/`3` outside text inputs).

- [ ] **Step 3: Append `## 10. 내부 모듈 아키텍처 및 TASK-402 인수 기준 (§10)`**

Specify:
1. Single-file IIFE layout (`SchemaConstants`, `LegacyMigrator`, `DefaultResolver`, `Validator`, `Store`, `CanvasRenderer`, `InspectorUI`, `JsonIO`, `AppBootstrap`) mapping `AMM_PROGRAM_SPECIFICATION.md` §10 canonical symbols (`validateMission()`, `renderCheckpoints()`, `renderCanvas()`, `exportJson()`, `importJson()`).
2. **`TASK-402` Implementation & Verification Criteria** (per Q5 decision):
   - **Static & Security Gate**: zero external `http://`/`https://` assets, zero `innerHTML` with user/JSON strings, zero VS/`kontraption:` identifiers.
   - **Schema & Lua-Parity Gate**: verify exported `"1.3.0"` JSON files across 9 active actions + 12 conditions + 4 hooks + upgraded `v1.0.0` legacy missions load cleanly via CraftOS-PC `mission_engine:load()` and `validate_mission_table()` (`tools/run_unit_tests.py`, `tools/run_e2e_tests.py`), and confirm 4 `DEFERRED` actions pass structural validation while rejecting at `enter_checkpoint` with `DEFERRED_ACTION_UNSUPPORTED`.
   - **Interactive Browser Verification**: manual `file://` verification across desktop (`>= 1280px`) and narrow (`~1024px`) viewports covering canvas pan/zoom/click/drag, undo/redo, JSON import/export, and CraftOS-PC `file_transfer` drop execution.
   - **Lifecycle Promotion Rule**: Upon `TASK-402` completion, promote `AMM_MISSION_EDITOR_SPECIFICATION.md` (`Draft` -> `Approved` -> `Implemented`) and register in `tools/verify_all_specs.py` / `tools/verify_spec_status.py` (while `AMM_PROGRAM_SPECIFICATION.md` v1.3.0 awaits both `TASK-402` and `TASK-207`).

- [ ] **Step 4: Sync `TASK.md` and `.agent/memory/workspace-root.md`**

1. In `.worktrees/feat-task-202-5/TASK.md`:
   - Mark `TASK-202-5` `[x]` with summary and date `2026-11-12`.
   - Since `TASK-202-1..5` are all `[x]`, move `TASK-202` to `## ✅ 3. 완료된 작업 이력` (`[x]`) and prune the oldest entry if the archive exceeds 10 items.
   - Under `TASK-402`, link `[docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md](docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md) (현재 v0.1.0 Draft)` and update top `현재 단계` summary line.
2. In `.worktrees/feat-task-202-5/.agent/memory/workspace-root.md`:
   - Invoke `md-management` skill (during execution) and append a `TASK-202-5` entry detailing the new `Draft` spec and verification outputs.

- [ ] **Step 5: Run all repository, context, and spec completeness verification gates**

Run inside `.worktrees/feat-task-202-5`:
```powershell
Push-Location .worktrees/feat-task-202-5
python tools/verify_all_specs.py --check-readmes; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/verify_context_docs.py }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }
Pop-Location
```
And run the standalone completeness audit on `AMM_MISSION_EDITOR_SPECIFICATION.md`:
```powershell
Push-Location .worktrees/feat-task-202-5
python -c "from pathlib import Path; import re; p=Path('docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md'); txt=p.read_text(encoding='utf-8'); secs=[f'## {i}.' for i in range(1,11)]+['validateMission','renderCheckpoints','renderCanvas','exportJson','importJson','textContent','1.3.0']; miss=[s for s in secs if s not in txt]; assert not miss, miss; m=re.findall(r'\x60\x60\x60mermaid\n(.*?)\n\x60\x60\x60', txt, re.S); assert len(m)>=1 and all(b.count('\"')%2==0 for b in m); links=re.findall(r'\[[^\]]+\]\(([^)]+)\)', txt); bad=[l for l in links if not l.startswith(('http','#')) and not (p.parent/l.split('#')[0]).resolve().exists()]; assert not bad, bad; print('SPEC_AUDIT_PASS', len(txt.splitlines()))"
Pop-Location
```
Expected:
- `verify_all_specs.py --check-readmes`: `0 Errors, 0 Warnings`
- `verify_spec_status.py`: `7 Implemented, 8 Approved`
- `verify_context_docs.py`: `0 findings`
- `tests/harness`: `82/82 PASS`
- `SPEC_AUDIT_PASS <line_count>` with zero missing sections and zero broken links.

- [ ] **Step 6: Commit Task 4**

```powershell
Push-Location .worktrees/feat-task-202-5
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md TASK.md .agent/memory/workspace-root.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(amm): complete WebUI mission editor Draft spec (v0.1.0) and close TASK-202-5"
Pop-Location
```
