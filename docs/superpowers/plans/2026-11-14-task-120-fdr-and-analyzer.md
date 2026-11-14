# Ground In-Flight Aligner & Offline Telemetry Profiler (FDR, `TASK-120`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execute implementation in an isolated git worktree (`using-git-worktrees`) after the Phase 1 `Draft` specification is approved (`Draft` → `Approved`).

**Goal:** Author the `Draft` specification for `TASK-120` (`docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md`), resolve the `Draft` → `Approved` review gate, build the ground-station In-Flight Aligner & Multi-Disk VFS Telemetry Recorder (`src/0_development/fdr/`), build the host Python offline telemetry analyzer & profile tuner CLI (`tools/analyze_flight_log.py`), and verify the full capture-to-profile pipeline via unit, E2E, and manifest/spec gates.

**Architecture:** `FDR` (`src/0_development/fdr/`) runs on a ground-station computer wired to a multi-disk drive array (or onboard standalone) as a receive-only wireless passive tap node (zero `modem.transmit` calls). Operating like `Alignment` (`STANDBY` ↔ `LOGGING`, `[N]` dynamic aircraft index $N \in [1, 1000]$ binding with `"*"` `domainId` auto-lock), it taps mandatory `Base+1`, `Base+2`, `Base+10` plus config-toggleable `Base+11` (`aero = true`) and `Base+4` (`trajectory = true`), spanning chunk-sharded JSONL part files (`<= 100 KB`) across wired/adjacent `/disk*` volumes via `storage_pool.lua` (rolling over seamlessly with `FOOTER` + `session_manifest.json`, `disk`/`disk_eject` hotplug, and `STREAMING` 1s/20-frame batch `flush()` default + `RING_BUFFER` optional), plus `cloud_exporter.lua` (`[U]` hotkey `http.post` export to `GDRIVE_WEBHOOK` Google Apps Script or `HTTP_POST` host ingest server). `VAS` (`src/1_control/vas/modules/telemetry_feeder.lua`) adds opt-in `telemetryDiag = true` (`diag` + `satFlags` on `Base+2`, default `false`). On the host PC, `tools/analyze_flight_log.py` merges single files, globs, or disk-pool directories, computes setpoint vs PV errors (`quat_to_euler_deg`), PID/actuator/ASA/outer-loop saturation, scalar/`ADVANCED_VTOL` thrust distribution, `--json`, `--csv`, and `--emit-profile <out_dir>` generating clamped `[0.70x, 1.35x]` `pid_tuned.json`, `system_patch.json`, `fcp_patch.json`, and `tuning_summary.json`.

**Tech Stack:** Markdown (GFM) & Mermaid specs (`docs/specs/0_development/fdr/`), CC:Tweaked 1.109+ Lua 5.2 (`parallel.waitForAny`, `os.epoch("utc")`, `disk`, `fs`, `http.post`, `textutils.serialiseJSON`, `term.blit`), CraftOS-PC Headless Runners (`tools/run_unit_tests.py`, `tools/run_e2e_tests.py`), Python 3.10+ stdlib CLI (`argparse`, `csv`, `json`, `math`, `statistics`), Static Verifiers (`tools/validate_lua_syntax.py`, `tools/verify_manifest_sync.py`, `tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/verify_context_docs.py`, `tests/harness/`).

**Spec:** Authored in **Phase 1 (Task 1)** as `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md` (`Status: Draft`, `Version: v0.2.0`), then reviewed and promoted to `Approved` in **Task 2** before any `src/` or `tools/` code is written.

---

## Global Constraints

- **Spec-First & Draft Gate (`.agent/rules/skill-workflows.md`, `docs/specs/README.md`)**: Do NOT touch `src/0_development/fdr/`, `src/1_control/vas/`, `manifest.lua`, or `tools/analyze_flight_log.py` while `FDR_PROGRAM_SPECIFICATION.md` is in `Draft`. Creating `Draft` does NOT invoke `specification-lifecycle-manager` and does NOT alter `tools/verify_spec_status.py` (`11 Implemented, 5 Approved`). Promoting `Draft` → `Approved` requires explicit user review of the `VAS` optional `telemetryDiag` diagnostic extension decision.
- **Multi-Codebase Isolation (`GEMINI.md`)**: `src/0_development/fdr/` must be 100% self-contained with zero cross-directory `require()` calls to `src/1_control/vas/` or other subsystems; all `manifest.lua` entries must bundle `{ repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil }` and use `category = "development"` (`tools/verify_manifest_sync.py`).
- **Passive Non-Interference Guarantee**: `packet_tap.lua` and `src/0_development/fdr/` must NEVER invoke `modem.transmit(...)`. Loss, stall, or crash of `FDR` must have zero effect on `FCP`, `VAS`, `TCA`, `ASA`, or `AMM`.
- **Protocol & Channel Standard (`AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` v1.30.0)**: `Base = 10000 + (N - 1) * 40` ($N = 1 \dots 1000$, `10000..49960`); envelope `ver == "1.9.5"` and `domainId` match enforced with Zero-Fallback (no legacy `ATTITUDE_ANGLE`, `angleTargets`, `rateTargets`, `targetThrottle`, `Base+6`, `Base+7`).
- **Quaternion Axis Convention (`src/1_control/vas/modules/quat.lua`)**: `sinp = 2*(w*y - z*x)`, `pitch = asin(clamp(sinp, -1, 1))`, `roll = atan2(2*(w*x + y*z), 1 - 2*(x*x + y*y))`, `yaw = (deg(atan2(2*(w*z + x*y), 1 - 2*(y*y + z*z))) % 360.0)`. Python `quat_to_euler_deg()` must match `quat.to_euler()` within `1e-6` deg.
- **Lua 5.2 Cobalt, Function Size & TUI Rules (`.agent/rules/cc-tweaked-runtime.md`)**: Zero Lua 5.3+ operators (`//`, `&`, `|`, `~`, `<<`, `>>`), zero banned OS calls (`os.execute`, `os.exit`, `os.remove`, `os.rename`, `io.popen`, `getfenv`, `setfenv`), every Lua function `<= 50` lines, exact `51`-character `text`/`fg`/`bg` rows on `term.blit`.
- **Mod Allowlist & Terminology Hygiene (`.agent/rules/domain-aeronautics.md`, `tools/verify_all_specs.py`, `AGENTS.md`)**: Zero Valkyrien Skies / `kontraption:` tokens, zero banned legacy tokens (`UAP`, `SAS`, `WAP`, `VAS-Core`, `VAS-Align`, `VAC-Align`, `VAC-Core`), zero overclaim terms (`AGENTS.md` Overclaim Ban).
- **Windows PowerShell & Git Guardrails**: Chain PowerShell commands with `; if ($?) { ... }` (never `&&`). Call Git via `& "C:\Program Files\Git\cmd\git.exe"`. Never run destructive git commands.

## Review Focus

1. **Pure Passive Tap vs Optional `VAS` `telemetryDiag` Extension (`Task 1` & `Task 2`)**: `Base+2` `MSG_FLIGHT_TELEMETRY` currently omits internal PID `integrators` and `integralLimits`. The `Draft` spec (§4.3) defines both pure-passive saturation proxies (`MSG_ACTUATOR_STATUS.isSaturated`, `gimbalSaturated`, `dynamicLoad >= 0.95`) AND an opt-in `telemetryDiag = true` extension on `VAS` `config/system.json` (disabled by default so live 20Hz packets remain untouched unless confirmed during `Draft` → `Approved` review).
2. **Multi-Disk Spanned VFS, Hotplug & `E_STOP` Edge-Latch (`Task 3`, `Task 4`, `Task 5`)**: CC:Tweaked lacks native Lua `fs.mount()`, and default floppies are capped at `125000` bytes. `storage_pool.lua` scans wired/adjacent `drive` peripherals (`disk.isPresent`, `disk.hasData`, `disk.getMountPath`) + local fallback, selects the volume with the most free space, rolls over self-contained part files (`maxPartBytes = 100000`, `rollOverReserveBytes = 16384`) with `FOOTER` + `session_manifest.json`, handles `disk`/`disk_eject` hotplug, edge-latches `E_STOP` triggers (`estopFlushed`), and transitions gracefully to `DISK_FULL` without crashing or dropping aircraft control.
3. **Timestamp Alignment & `Base+1` / `Base+2` / `Base+10` Asynchronous Interleaving (`Task 6`)**: `FCP` (`Base+1`), `VAS` (`Base+2`), and `VAS->TCA` (`Base+10`) arrive with staggered epochs, multi-part disk splits, or `MFD_ACRO` `RATE_COMMAND` takeover (`targetQuaternion == nil`). `load_jsonl()`/`merge_parts()` deduplicates and sorts frames by `(rxMs, seqIdx)` across multiple parts/directories, `align_timeline()` pairs within `maxCmdAgeMs = 150`, and skips quaternion error metrics during `RATE_COMMAND`.
4. **Polymorphic `MSG_THRUST_CMD.outputs` Formats & Safety-Clamped Profile Generation (`Task 6` & `Task 7`)**: `MSG_THRUST_CMD.outputs[groupId]` is scalar `0..15` or `ADVANCED_VTOL` `{ thrust, gimbalX, gimbalY }`. `--emit-profile <out_dir>` generates `pid_tuned.json`, `system_patch.json`, `fcp_patch.json`, and `tuning_summary.json` strictly clamped to `[0.70x, 1.35x]` and guarded by `minSamples = 100` and `sensorOk` failure threshold (`20%`).
5. **External Export Without `modem.transmit`, Malformed JSONL & Tool Integrity (`Task 4`, `Task 6`, `Task 7`)**: `cloud_exporter.lua` uses `http.post()` only (`<= 100KB` chunked upload with `authToken` to `GDRIVE_WEBHOOK` Apps Script or LAN `HTTP_POST` server; zero `modem.transmit`). `load_jsonl()` tolerates trailing truncated lines unless `--strict` is passed, and `test_tools_integrity.py` verifies `tools/analyze_flight_log.py`.

---

## File Structure

- **Phase 1 (`Draft` Spec & Review Gate — No `src/` or `tools/` runtime edits)**:
  - Created (`v0.2.0 Draft`): `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md` (`Status: Draft`, `Version: v0.2.0`)
  - Modify (at `Draft` → `Approved` gate in Task 2): `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md` (`Approved`), `tools/verify_all_specs.py` (`SPEC_FILES`, `REVISION_HISTORY_SPECS`), `tools/verify_spec_status.py` (`TARGET_APPROVED`), `GEMINI.md` (active spec count `11 Implemented, 6 Approved`), `TASK.md`
  - Optional (only if user approves `VAS` `telemetryDiag` extension in Task 2): `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`, `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`, `src/1_control/vas/modules/telemetry_feeder.lua`
- **Phase 2 (`TASK-120-1`: Ground In-Flight Aligner & Multi-Disk VFS Logger)**:
  - Create: `src/0_development/fdr/config/fdr_config.json`
  - Create: `src/0_development/fdr/modules/ring_buffer.lua`
  - Create: `src/0_development/fdr/modules/packet_tap.lua`
  - Create: `src/0_development/fdr/modules/storage_pool.lua`
  - Create: `src/0_development/fdr/modules/jsonl_dumper.lua`
  - Create: `src/0_development/fdr/modules/cloud_exporter.lua`
  - Create: `src/0_development/fdr/modules/fdr_ui.lua`
  - Create: `src/0_development/fdr/main.lua`
  - Modify: `src/0_development/installer/modules/manifest.lua` (add `"fdr"` to `MODULE_ORDER` and `MODULES.fdr` with `/lib/avionics_sensors.lua` and `defaultConfigs["/config/fdr_config.json"]`)
  - Create: `tests/0_development/fdr/unit.json`
  - Create: `tests/0_development/fdr/test_fdr_ring_and_tap.lua`
  - Create: `tests/0_development/fdr/test_fdr_storage_pool.lua`
  - Create: `tests/0_development/fdr/test_fdr_dumper_and_ui.lua`
  - Create: `tests/0_development/fdr/test_fdr_exporter.lua`
- **Phase 3 (`TASK-120-2`: Python Offline Telemetry Analyzer & Profile Tuner CLI)**:
  - Create: `tools/analyze_flight_log.py`
  - Create: `tests/harness/test_analyze_flight_log.py`
  - Modify: `tests/harness/test_tools_integrity.py` (add `tools/analyze_flight_log.py` to `expected_tools`)
- **Phase 4 (Integration E2E, Full Verification & `Implemented` Promotion)**:
  - Create: `tests/e2e/test_e2e_fdr_blackbox.lua`
  - Modify: `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md` (`Approved` → `Implemented`), `tools/verify_spec_status.py` (`TARGET_IMPLEMENTED`), `GEMINI.md` (`12 Implemented, 5 Approved`), `TASK.md` (archive `TASK-120`), `.agent/memory/workspace-root.md` (append `TASK-120` entry)

---

### Task 1: Author `FDR_PROGRAM_SPECIFICATION.md` (`Status: Draft`, `Version: v0.2.0`)

**Files:**
- Create: `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md`
- Modify: `TASK.md` (link spec path and `TASK-120-0` child checkbox)

**Interfaces:**
- Consumes: `docs/specs/README.md`, `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.30.0`), `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (`v2.7.0`), `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (`v1.20.0`), `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (`v2.1.0`), `docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md`, `src/1_control/vas/modules/{quat,telemetry_feeder,flight_dynamics_core,vehicle_policy,thrust_mixer}.lua`.
- Produces: Complete standalone `v0.2.0 Draft` specification `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md` covering §1–§8.

- [x] **Step 1: Verify target spec directory and create `FDR_PROGRAM_SPECIFICATION.md` (`v0.2.0 Draft`)**
- [x] **Step 2: Author §1 (Ground In-Flight Aligner), §2 (`[N]` dynamic binding & 5 tapped channels), §3 (Multi-Disk Spanned VFS `storage_pool.lua`), §4 (JSONL schema `1.1.0` + `STREAMING`/`RING_BUFFER` + `VAS` Opt-in `telemetryDiag`), §5 (`analyze_flight_log.py` metrics + `--emit-profile`), §6 (External export 3 paths), §7 (`fdr_config.json` `1.1.0` + 51×19 TUI), §8 (Verification Gates)**
- [x] **Step 3: Validate `Draft` specification against `verify_all_specs.py --check-readmes`, `verify_spec_status.py`, `verify_context_docs.py`, and direct link/Mermaid/terminology script**

- [ ] **Step 4: Commit `Draft` specification (optional user checkpoint before Task 2)**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md docs/superpowers/plans/2026-11-14-task-120-fdr-and-analyzer.md TASK.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(spec): add TASK-120 FDR program specification (v0.2.0 Draft)"
```

---

### Task 2: Spec Review & `Draft` → `Approved` Promotion Gate (Hard Stop Before Code)

**Files:**
- Modify: `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md` (`Draft` → `Approved`)
- Modify: `tools/verify_all_specs.py` (register `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md` in `SPEC_FILES` and `REVISION_HISTORY_SPECS`)
- Modify: `tools/verify_spec_status.py` (add `FDR_PROGRAM_SPECIFICATION.md` to `TARGET_APPROVED`)
- Modify: `GEMINI.md` (update spec count `11 Implemented, 6 Approved`)
- Optional (if `VAS` `telemetryDiag` opt-in confirmed): `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`, `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`

**Interfaces:**
- Consumes: User review sign-off on `v0.2.0 Draft` (§3 Multi-Disk VFS, §4.3 `VAS` `telemetryDiag` opt-in, §5 `--emit-profile`, §6 External Export default path).
- Produces: Active `Approved` specification registered in `verify_all_specs.py` and `verify_spec_status.py`.

- [ ] **Step 1: Present `v0.2.0 Draft` spec & external export recommendation to the user and wait for explicit approval**
- [ ] **Step 2: Promote `FDR_PROGRAM_SPECIFICATION.md` to `Approved` and register in spec verifiers (`verify_all_specs.py`, `verify_spec_status.py`, `GEMINI.md`, `TASK.md`)**
- [ ] **Step 3: Verify all spec & context verifiers pass (`17` active specs)**

Run:
```powershell
python tools/verify_all_specs.py --check-readmes; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/verify_context_docs.py }
```
Expected: `ALL 16 SPECS 100% CLEAN (0 Errors, 0 Warnings)`, `All 17 specs have valid statuses (11 Implemented, 6 Approved)`, `[PASS] context docs: 0 findings`.

- [ ] **Step 4: Commit `Approved` spec gate and create `.worktrees/feat-task-120-fdr` (`using-git-worktrees`)**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md tools/verify_all_specs.py tools/verify_spec_status.py GEMINI.md TASK.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(spec): approve FDR specification (v0.2.0 Approved) and register verifiers"
```

---

### Task 3: `TASK-120-1` Part A — `fdr_config.json`, `ring_buffer.lua`, and Dynamic-Binding `packet_tap.lua` (TDD)

**Files:**
- Create: `src/0_development/fdr/config/fdr_config.json` (`schemaVersion: "1.1.0"`, `domainId: "*"`, `STREAMING` default + `storage` + `export`)
- Create: `src/0_development/fdr/modules/ring_buffer.lua`
- Create: `src/0_development/fdr/modules/packet_tap.lua`
- Create: `tests/0_development/fdr/unit.json`
- Create: `tests/0_development/fdr/test_fdr_ring_and_tap.lua`

**Interfaces:**
- Produces `ring_buffer`: `init(capacity)`, `push(buf, entry)`, `len(buf)`, `capacity(buf)`, `dropped(buf)`, `snapshot(buf)`, `clear(buf)`.
- Produces `packet_tap`:
  - `packet_tap.compute_base(aircraftIndexN: number) -> number?, string?`
  - `packet_tap.build_channel_map(cfg: table) -> table`
  - `packet_tap.init(cfg: table, modemOverride?: table) -> table`
  - `packet_tap.open_channels(tap: table) -> boolean`
  - `packet_tap.close_channels(tap: table) -> boolean`
  - `packet_tap.bind_aircraft(tap: table, aircraftIndexN: number, domainIdOrWildcard?: string) -> boolean, string?`
  - `packet_tap.classify_packet(tap: table, channel: number, pkt: any, rxMs?: number) -> table?, string?`
  - `packet_tap.is_estop_trigger(record: table) -> boolean`

- [ ] **Step 1: Create `tests/0_development/fdr/unit.json` and write the failing tests in `tests/0_development/fdr/test_fdr_ring_and_tap.lua`**

Write tests asserting:
1. `ring_buffer.init(3)` pushes 5 items (`seq=1..5`), reports `len == 3`, `dropped == 2`, and `snapshot()` returns `{3, 4, 5}` in chronological order; `clear()` resets `len == 0` and `dropped == 0`.
2. `packet_tap.init(cfg, mockModem)` opens `Base+1`, `Base+2`, `Base+10` (plus `Base+11` when `tapOptions.aero == true` and `Base+4` when `tapOptions.trajectory == true`) and NEVER calls `mockModem.transmit`.
3. `packet_tap.bind_aircraft(tap, 3, "*")` closes old `N=1` channels (`10001..10011`), opens `N=3` (`10081..10091`), and locks `lockedDomainId` onto the first valid `ver == "1.9.5"` `MSG_FLIGHT_TELEMETRY` `domainId`.
4. `packet_tap.classify_packet(tap, channel, pkt, rxMs)` normalizes `FRAME` records (`offset`, `msgType`, `payload`) while rejecting `ver ~= "1.9.5"`, mismatched `lockedDomainId`, `Base+6`/`Base+7` `[DEPRECATED]`, or unknown channels, and `is_estop_trigger()` triggers on `MSG_EMERGENCY_OVERRIDE`, `MSG_EMERGENCY_ALERT`, and `controlState == "E_STOP"`.

- [ ] **Step 2: Run unit test to verify it fails**

Run:
```powershell
python tools/run_unit_tests.py --target 0_development/fdr --clean-orphans
```
Expected: FAIL (`module 'ring_buffer' not found`).

- [ ] **Step 3: Implement `src/0_development/fdr/config/fdr_config.json`, `ring_buffer.lua`, and `packet_tap.lua`**

Implement each function `<= 50` lines in Lua 5.2 (zero 5.3 operators, zero `transmit` calls anywhere in `packet_tap.lua`).

- [ ] **Step 4: Run unit tests to verify they pass**

Run:
```powershell
python tools/run_unit_tests.py --target 0_development/fdr --clean-orphans
```
Expected: PASS (`test_fdr_ring_and_tap` PASS).

- [ ] **Step 5: Commit `fdr_config.json`, `ring_buffer.lua`, and `packet_tap.lua`**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/fdr/config/fdr_config.json src/0_development/fdr/modules/ring_buffer.lua src/0_development/fdr/modules/packet_tap.lua tests/0_development/fdr/unit.json tests/0_development/fdr/test_fdr_ring_and_tap.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(fdr): add config, ring_buffer, and dynamic-binding packet_tap with unit tests"
```

---

### Task 4: `TASK-120-1` Part B — `storage_pool.lua` (Multi-Disk VFS), `jsonl_dumper.lua`, `cloud_exporter.lua`, and `fdr_ui.lua` (TDD)

**Files:**
- Create: `src/0_development/fdr/modules/storage_pool.lua`
- Create: `src/0_development/fdr/modules/jsonl_dumper.lua`
- Create: `src/0_development/fdr/modules/cloud_exporter.lua`
- Create: `src/0_development/fdr/modules/fdr_ui.lua`
- Create: `tests/0_development/fdr/test_fdr_storage_pool.lua`
- Create: `tests/0_development/fdr/test_fdr_dumper_and_ui.lua`
- Create: `tests/0_development/fdr/test_fdr_exporter.lua`

**Interfaces:**
- Produces `storage_pool`: `scan_volumes(cfg, peripheralApi?, diskApi?, fsApi?)`, `select_best_volume(volumes, cfg)`, `get_pool_free_bytes(volumes)`, `build_part_path(mountRoot, cfg, domainId, sessionEpochMs, partIdx)`, `prune_oldest_sessions(volumes, cfg, activeSessionId, fsApi?)`, `write_session_manifest(manifestPath, sessionMeta, fsApi?)`.
- Produces `jsonl_dumper`: `open_stream(poolState, cfg, sessionMeta)`, `write_stream_batch(stream, frames)`, `flush_stream(stream)`, `rollover_stream(stream, poolState, reason)`, `close_stream(stream, reason)`, `dump_ring_buffer(ringBuf, poolState, cfg, sessionMeta)` (writes `META`/`FRAME`/`FOOTER` JSONL lines `1.1.0` without internal newlines).
- Produces `cloud_exporter`: `upload_session(sessionManifest, exportCfg, httpApi?, fsApi?) -> boolean, table` (`<= 100KB` chunked `http.post` with `authToken`, zero `modem.transmit`).
- Produces `fdr_ui`: `format_row(text, fgChar?, bgChar?)`, `render(termObj, state)` (`51` chars per `term.blit` row showing `N`/`Base`/`lockedDomainId`, `STANDBY`/`LOGGING`/`PAUSED`/`DISK_FULL`, active VFS volume + pool KB, `partNNN`, channel counters).

- [ ] **Step 1: Write failing tests in `test_fdr_storage_pool.lua`, `test_fdr_dumper_and_ui.lua`, and `test_fdr_exporter.lua`**

Write tests asserting:
1. `storage_pool.scan_volumes()` collects wired/adjacent `drive` mounts (`/disk`, `/disk2`), ignores audio disks (`disk.hasData == false`), selects the volume with largest `fs.getFreeSpace()`, falls back to local `"/logs"` only when external drives are exhausted, prunes oldest non-active sessions when `autoPruneOldest == true`, and signals `DISK_FULL` cleanly when pool free bytes are exhausted.
2. `jsonl_dumper` `STREAMING` opens `part001`, batches `flush()` on `20` frames or `1.0s`, rolls over automatically at `maxPartBytes = 100000` or `rollOverReserveBytes = 16384` by writing `FOOTER` (`nextPart = 2`) and opening `part002` on the next disk in `storage_pool`, and `dump_ring_buffer` writes `META` + `FRAME` + `FOOTER` without partial writes.
3. `cloud_exporter.upload_session()` reads each part listed in `session_manifest.json`, posts JSON chunks (`<= 100KB`) with `authToken` via `http.post`, preserves all local/disk part files on network error, and invokes `modem.transmit` `0` times.
4. `fdr_ui.render(mockTerm, state)` invokes `term.blit` with exact `51`-character `text`, `fg`, and `bg` strings on every row.

- [ ] **Step 2: Run unit tests to verify they fail**

Run:
```powershell
python tools/run_unit_tests.py --target 0_development/fdr --clean-orphans
```
Expected: FAIL (`module 'storage_pool' not found`).

- [ ] **Step 3: Implement `storage_pool.lua`, `jsonl_dumper.lua`, `cloud_exporter.lua`, and `fdr_ui.lua`**

Use CraftOS `fs.delete` / `fs.move` (never `os.remove`/`os.rename`), sanitize serialized JSON lines against `\r`/`\n`, keep all Lua functions `<= 50` lines in Lua 5.2.

- [ ] **Step 4: Run unit tests to verify they pass**

Run:
```powershell
python tools/run_unit_tests.py --target 0_development/fdr --clean-orphans
```
Expected: PASS (`test_fdr_ring_and_tap`, `test_fdr_storage_pool`, `test_fdr_dumper_and_ui`, `test_fdr_exporter` PASS).

- [ ] **Step 5: Commit `storage_pool.lua`, `jsonl_dumper.lua`, `cloud_exporter.lua`, and `fdr_ui.lua`**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/fdr/modules/storage_pool.lua src/0_development/fdr/modules/jsonl_dumper.lua src/0_development/fdr/modules/cloud_exporter.lua src/0_development/fdr/modules/fdr_ui.lua tests/0_development/fdr/test_fdr_storage_pool.lua tests/0_development/fdr/test_fdr_dumper_and_ui.lua tests/0_development/fdr/test_fdr_exporter.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(fdr): add Multi-Disk VFS storage_pool, jsonl_dumper, cloud_exporter, and fdr_ui"
```

---

### Task 5: `TASK-120-1` Part C — `src/0_development/fdr/main.lua`, `manifest.lua` Sync & Optional `VAS` `telemetryDiag` (TDD)

**Files:**
- Create: `src/0_development/fdr/main.lua`
- Modify: `src/0_development/installer/modules/manifest.lua` (add `"fdr"` to `MODULE_ORDER` and `MODULES.fdr`)
- Modify: `tests/0_development/fdr/test_fdr_dumper_and_ui.lua` (add `main.lua` event-dispatch, `STANDBY` ↔ `LOGGING` `[N]` binding, `disk`/`disk_eject` hotplug, `E_STOP` edge-latch, and `[D]`/`[S]`/`[U]`/`[C]`/`[P]`/`[Q]` hotkey tests)
- Optional (only if Task 2 approved opt-in `telemetryDiag`): Modify `src/1_control/vas/modules/telemetry_feeder.lua` (`telemetryDiag` opt-in attachment) and `tests/1_control/vas/test_telemetry_feeder.lua`

**Interfaces:**
- Consumes: `ring_buffer`, `packet_tap`, `storage_pool`, `jsonl_dumper`, `cloud_exporter`, `fdr_ui`.
- Produces `main`:
  - `main.init(configPathOrTable?: string|table, modemOverride?: table) -> table`
  - `main.handle_event(state: table, ev: string, p1: any, p2: any, p3: any, p4: any) -> boolean`
  - `main.switch_aircraft(state: table, nextN: number) -> boolean, string?`
  - `main.trigger_flush_or_dump(state: table, reason: string) -> boolean, string?`
  - `main.run(configPathOrTable?: string|table) -> table` (guarded by `if _G.describe == nil then main.run(...) end`)

- [ ] **Step 1: Add failing `main.lua` tests to `tests/0_development/fdr/test_fdr_dumper_and_ui.lua`**

Assert:
1. Two consecutive `E_STOP` telemetry packets trigger **exactly 1** immediate flush/dump (`state.estopFlushed == true`), reset on `[C]` or manual rebind.
2. `[N]` rebinds channels dynamically (`oldBase` closed, `newBase` opened, active stream closes cleanly with `FOOTER` before starting new session).
3. `disk` / `disk_eject` events refresh `storage_pool` and automatically recover from `DISK_FULL` when a new volume is inserted.
4. `[P]` toggles `STANDBY`/`LOGGING` ↔ `PAUSED`; `[D]` triggers immediate flush/dump; `[S]` splits part (`partNNN+1`); `[U]` triggers `cloud_exporter.upload_session`; `[Q]`/`terminate` writes `FOOTER` + `session_manifest.json` cleanly.

- [ ] **Step 2: Run unit test to verify it fails**

Run:
```powershell
python tools/run_unit_tests.py --target 0_development/fdr --clean-orphans
```
Expected: FAIL (`module 'main' not found`).

- [ ] **Step 3: Implement `src/0_development/fdr/main.lua` and register `fdr` in `src/0_development/installer/modules/manifest.lua`**

In `manifest.lua`:
- Append `"fdr"` to `MODULE_ORDER` (under `development`).
- Add `MODULES.fdr` with `category = "development"`, `installDir = "/"`, `startup = { enabled = false }`, `defaultConfigs = { ["/config/fdr_config.json"] = { ... } }`, and `files` listing `main.lua`, `modules/{ring_buffer,packet_tap,storage_pool,jsonl_dumper,cloud_exporter,fdr_ui}.lua`, plus `{ repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil }`.

- [ ] **Step 4: Run Lua syntax, manifest sync, and unit test suite**

Run:
```powershell
python tools/validate_lua_syntax.py; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python tools/run_unit_tests.py --require-tests --clean-orphans }
```
Expected: `validate_lua_syntax.py` PASS, `verify_manifest_sync.py` `0 Errors, 0 Warnings`, `run_unit_tests.py` 13 targets ALL PASS.

- [ ] **Step 5: Commit `main.lua` and `manifest.lua`**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/fdr/main.lua src/0_development/installer/modules/manifest.lua tests/0_development/fdr/test_fdr_dumper_and_ui.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(fdr): add ground main daemon, dynamic [N] bind, disk hotplug, and manifest entry"
```

---

### Task 6: `TASK-120-2` Part A — `tools/analyze_flight_log.py` Core Parser, Multi-Part Merge, Metrics & Profile Generator (TDD)

**Files:**
- Create: `tools/analyze_flight_log.py`
- Create: `tests/harness/test_analyze_flight_log.py`

**Interfaces:**
- Produces in `tools/analyze_flight_log.py`:
  - `resolve_inputs(inputs: list[str]) -> list[Path]` (files, globs, disk-pool directories with `*part*.jsonl` / `session_manifest.json`)
  - `load_and_merge_jsonl(paths: list[Path], window: tuple[int, int] | None = None) -> tuple[list[dict], list[dict], list[str]]` (sorted/deduped by `(rxMs, seqIdx)`)
  - `quat_to_euler_deg(q: dict[str, float]) -> tuple[float, float, float]` (`pitch, roll, yaw`, exact `src/1_control/vas/modules/quat.lua` convention)
  - `wrap_angle_err_deg(target_deg: float, meas_deg: float) -> float` (`[-180, 180)`)
  - `align_timeline(records: list[dict], max_cmd_age_ms: int = 150) -> list[dict]`
  - `compute_tracking_metrics(aligned: list[dict]) -> dict`
  - `compute_saturation_metrics(aligned: list[dict], records: list[dict]) -> dict`
  - `compute_thrust_distribution(records: list[dict]) -> dict`
  - `generate_tuning_profile(report: dict, aligned: list[dict], baseline_pid: dict | None = None, baseline_system: dict | None = None, baseline_fcp: dict | None = None, force: bool = False) -> dict`
  - `analyze_logs(paths: list[Path], window: tuple[int, int] | None = None) -> dict`

- [ ] **Step 1: Write failing unit tests in `tests/harness/test_analyze_flight_log.py`**

Test exact mathematical invariants:
1. `resolve_inputs` + `load_and_merge_jsonl` merges multi-part `part001.jsonl` + `part002.jsonl` across disk directories, deduplicates overlapping `(rxMs, seqIdx)`, and tolerates trailing truncated JSON line (`malformed_count == 1`).
2. `quat_to_euler_deg` roundtrips known `quat.from_euler(pitch=12.5, roll=-8.0, yaw=270.0)` values matching `VAS` `quat.lua` within `1e-4` deg.
3. `align_timeline` pairs `Base+2` frames with the latest `Base+1` command within `150ms`, skips quaternion error when `commandType == "RATE_COMMAND"`, and computes exact pitch/roll/yaw & rate `rmse`, `mae`, `maxAbsErr`, and oscillation zero-crossing Hz.
4. `compute_saturation_metrics` reports exact integrator saturation % (`|I| / integralLimit >= 0.99`) when `payload.diag` is present, and falls back cleanly to `MSG_ACTUATOR_STATUS.isSaturated`, `gimbalSaturated`, and `dynamicLoad >= 0.95` ratios when `diag` is absent.
5. `compute_thrust_distribution` handles both scalar `0..15` (`{ "THR_MAIN_L": 10, "THR_MAIN_R": 5 }`) and `ADVANCED_VTOL` table `{ thrust = 12, gimbalX = 0.85, gimbalY = -0.2 }` outputs.
6. `generate_tuning_profile` emits `pid_tuned.json`, `system_patch.json`, `fcp_patch.json`, and `tuning_summary.json` clamped strictly to `[0.70x, 1.35x]`, refuses generation (`force=False`) when `sampleCount < 100` or `sensorOk == false` exceeds `20%`, and skips `ki` increases (`AUTHORITY_LIMITED`) when `isSaturated >= 15%`.

- [ ] **Step 2: Run test to verify it fails**

Run:
```powershell
python -m unittest tests/harness/test_analyze_flight_log.py -v
```
Expected: FAIL (`ModuleNotFoundError: No module named 'tools.analyze_flight_log'`).

- [ ] **Step 3: Implement core parser, metrics, and profile generator in `tools/analyze_flight_log.py`**

Pure Python 3 stdlib (`argparse`, `csv`, `glob`, `json`, `math`, `statistics`, `pathlib`, `sys`). Ensure `quat_to_euler_deg` clamps `sinp` to `[-1.0, 1.0]` before `math.asin`.

- [ ] **Step 4: Run tests to verify they pass**

Run:
```powershell
python -m unittest tests/harness/test_analyze_flight_log.py -v
```
Expected: PASS.

- [ ] **Step 5: Commit core analyzer & profile generator**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tools/analyze_flight_log.py tests/harness/test_analyze_flight_log.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(tools): add multi-part telemetry analyzer core metrics and profile tuner"
```

---

### Task 7: `TASK-120-2` Part B — CLI Formatter, `--json`/`--csv`/`--emit-profile`/`--strict` Flags & `test_tools_integrity.py` Registration (TDD)

**Files:**
- Modify: `tools/analyze_flight_log.py` (add `format_text_report(report, top_n=10)`, `export_csv(aligned, out_path)`, `write_profile_bundle(profile, out_dir)`, `build_arg_parser()`, `main(argv=None)`)
- Modify: `tests/harness/test_analyze_flight_log.py` (add subprocess CLI tests for text output, `--json`, `--csv`, `--emit-profile`, `--baseline-*`, `--window`, and `--strict`)
- Modify: `tests/harness/test_tools_integrity.py` (register `WORKSPACE_ROOT / "tools" / "analyze_flight_log.py"` in `expected_tools`)

**Interfaces:**
- Produces CLI entrypoint `python tools/analyze_flight_log.py <logfile_or_dir>... [--json] [--csv <out.csv>] [--window START:END] [--top N] [--strict] [--emit-profile <out_dir>] [--baseline-pid <pid.json>] [--baseline-system <system.json>] [--baseline-fcp <fcp_config.json>] [--force-profile]`.

- [ ] **Step 1: Write failing CLI subprocess tests in `tests/harness/test_analyze_flight_log.py`**

Assert:
1. Running `python tools/analyze_flight_log.py <sample.jsonl>` exits `0` and prints sections `[SUMMARY]`, `[TRACKING]`, `[SATURATION]`, and `[THRUST DISTRIBUTION]`.
2. Running with `--json` outputs valid JSON containing `meta`, `tracking`, `saturation`, `thrustDistribution`, and `warnings`.
3. Running with `--csv <out.csv>` writes header + aligned time-series rows.
4. Running with `--emit-profile <out_dir>` writes `pid_tuned.json`, `system_patch.json`, `fcp_patch.json`, and `tuning_summary.json` (respecting `minSamples = 100` guard unless `--force-profile`).
5. Running with `--strict` on a truncated/malformed JSONL exits `1`.

- [ ] **Step 2: Run test to verify it fails**

Run:
```powershell
python -m unittest tests/harness/test_analyze_flight_log.py -v
```
Expected: FAIL (`main()` / CLI not implemented).

- [ ] **Step 3: Implement CLI formatters & `--csv`/`--emit-profile` writers in `tools/analyze_flight_log.py` and register in `tests/harness/test_tools_integrity.py`**

- [ ] **Step 4: Run all harness tests**

Run:
```powershell
python -m unittest discover -s tests/harness -p "test_*.py" -v
```
Expected: ALL PASS (`88+` tests passing, 0 failures).

- [ ] **Step 5: Commit CLI & integrity registration**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tools/analyze_flight_log.py tests/harness/test_analyze_flight_log.py tests/harness/test_tools_integrity.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(tools): add analyze_flight_log CLI (--csv, --emit-profile) and integrity check"
```

---

### Task 8: Multi-Node E2E Passive Tap → Multi-Disk VFS → Analyzer/Profile Roundtrip & `Implemented` Promotion

**Files:**
- Create: `tests/e2e/test_e2e_fdr_blackbox.lua`
- Modify: `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md` (`Approved` → `Implemented`, update `Date`)
- Modify: `tools/verify_spec_status.py` (move `FDR_PROGRAM_SPECIFICATION.md` from `TARGET_APPROVED` to `TARGET_IMPLEMENTED`)
- Modify: `GEMINI.md` (update spec counts `12 Implemented, 5 Approved` and handover summary)
- Modify: `TASK.md` (mark `TASK-120-0`, `TASK-120-1`, `TASK-120-2` `[x]`, move `TASK-120` to `## ✅ 3. 완료된 작업 이력` respecting 10-entry cap, update `TASK-011-5` note that `TASK-120` is complete)
- Modify: `.agent/memory/workspace-root.md` (append `2026-11-14 — TASK-120` completion record per `verify_context_docs.py` R8)

**Interfaces:**
- Consumes: `src/0_development/fdr/main.lua`, `tools/analyze_flight_log.py`, `harness/simulation/` virtual bus.
- Produces: Verified end-to-end passive recording -> Multi-Disk VFS rollover -> `--emit-profile` Python CLI proof and synchronized `Implemented` documentation.

- [ ] **Step 1: Write `tests/e2e/test_e2e_fdr_blackbox.lua` and run E2E + roundtrip tests**

Simulate multi-node flight traffic (`FCP` `Base+1` + `VAS` `Base+2` + `Base+10` + `TCA`) alongside ground `FDR` node (`src/0_development/fdr/main.lua`) mounted with multiple mock `drive` volumes:
1. Assert `FDR` emits zero modem packets (`txCount == 0`).
2. Trigger `[N]` aircraft binding, `maxPartBytes` VFS rollover (`/disk` -> `/disk2`), and `E_STOP` flush; assert `part001.jsonl` + `part002.jsonl` + `FOOTER` + `session_manifest.json` are valid.
3. Add a roundtrip test in `tests/harness/test_analyze_flight_log.py` feeding multi-part CraftOS-PC JSONL dumps into `tools/analyze_flight_log.py --json --csv --emit-profile --strict` and verifying `pid_tuned.json` / `system_patch.json` / `fcp_patch.json` / `tuning_summary.json`.

Run:
```powershell
python tools/run_e2e_tests.py --filter fdr --clean-orphans; if ($?) { python -m unittest tests/harness/test_analyze_flight_log.py -v }
```
Expected: `test_e2e_fdr_blackbox` PASS and Python roundtrip PASS.

- [ ] **Step 2: Run the complete project verification suite (`verification-before-completion`)**

Run:
```powershell
python tools/validate_lua_syntax.py; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python tools/run_unit_tests.py --require-tests --clean-orphans }; if ($?) { python tools/run_e2e_tests.py --clean-orphans }; if ($?) { python tools/run_mutation_tests.py }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }
```
Expected: All Lua syntax, manifest 3-way sync, all unit test targets, all E2E suites, `25/25 KILLED` mutation tests, and all Python harness tests PASS with 0 errors.

- [ ] **Step 3: Promote `FDR_PROGRAM_SPECIFICATION.md` (`v0.2.0`) to `Implemented` and synchronize `verify_spec_status.py`, `GEMINI.md`, `TASK.md`, and `.agent/memory/workspace-root.md`**

Run final doc verifiers:
```powershell
python tools/verify_all_specs.py --check-readmes; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/verify_context_docs.py }
```
Expected: `0 Errors, 0 Warnings`, `All 17 specs have valid statuses (12 Implemented, 5 Approved)`, `[PASS] context docs: 0 findings`.

- [ ] **Step 4: Commit final E2E, promotion, and context handover**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tests/e2e/test_e2e_fdr_blackbox.lua tests/harness/test_analyze_flight_log.py docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md tools/verify_spec_status.py GEMINI.md TASK.md .agent/memory/workspace-root.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "chore(fdr): complete TASK-120 E2E verification and promote FDR spec to Implemented"
```

---

## Self-Review

- **Spec & Roadmap Coverage**: Matches `FDR_PROGRAM_SPECIFICATION.md` (`v0.2.0 Draft`) across §1–§8 (`Alignment`-style `STANDBY` ↔ `LOGGING` dynamic `[N]` binding, `Base+1/2/10` + optional `Base+11/4`, `storage_pool.lua` Multi-Disk VFS `/disk*` chunk-sharded rollover & hotplug, `STREAMING` default + `RING_BUFFER` optional, `VAS` opt-in `telemetryDiag`, `cloud_exporter.lua` `GDRIVE_WEBHOOK`/`HTTP_POST` export, and `tools/analyze_flight_log.py` `--json`/`--csv`/`--emit-profile`).
- **Step Scan**: Every task lists exact files, exact module function signatures, exact CraftOS/Python verification commands, and concrete expected outputs with zero `"TBD"` gaps.
- **Type & Convention Consistency**: `Base = 10000 + (N - 1) * 40`, `ver == "1.9.5"`, `quat_to_euler_deg` matched to `src/1_control/vas/modules/quat.lua`, `51`-char `term.blit`, and `manifest.lua` `/lib/avionics_sensors.lua` bundle invariant are consistent across Tasks 1–8.
- **Review Focus Pinned**: Pure passive vs `telemetryDiag` opt-in (Tasks 1–2), Multi-Disk VFS + hotplug + `E_STOP` edge-latch (Tasks 3–5), async multi-part merge & `RATE_COMMAND` skip (Task 6), polymorphic `outputs` + `[0.70x, 1.35x]`-clamped `--emit-profile` (Tasks 6–7), and `http.post` export + `--strict` + `test_tools_integrity.py` (Tasks 4, 6, 7).
