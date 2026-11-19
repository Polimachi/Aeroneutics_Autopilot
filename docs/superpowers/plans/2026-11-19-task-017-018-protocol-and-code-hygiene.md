# TASK-017 & TASK-018 Protocol & Code Hygiene Implementation Plan

> **For agentic workers:** Execute this plan task-by-task using checkbox (`- [ ]`) tracking. Respect sequential task dependencies (`Task 1 -> Tasks 2-8 -> Task 9`); do not run tasks in parallel when they touch the same file.

**Goal:** Eliminate all wire-protocol contract drifts, legacy dead packet branches, unconsumed required payload fields (`ASA` excluded per active freeze), duplicated `installer.lua` bootstrap code, duplicated helper contracts, dead Lua functions, and unused config keys identified in `TASK-017` and `TASK-018`.

**Architecture:** Execute Spec-First contract and Master ICD synchronization in Task 1 (`Approved` state transitions where `src/` changes follow), then work sequentially through protocol expansion/consumer wiring (Tasks 2–5), single-source installer unification (Task 6), Lua helper/copy deduplication (Task 7), and dead-code/unused-config pruning (Task 8) under strict Red-Green TDD, finishing with full cross-gate verification, `Implemented` spec promotion, and context memory sync (Task 9). Keep subsystem isolation intact (`src/<layer>/<name>/` never cross-imports directly; only installer-injected `/lib/avionics_sensors.lua` and `/lib/ota_agent.lua` are shared).

**Tech Stack:** CC:Tweaked Lua 5.2 (CraftOS-PC headless runners via `tools/run_unit_tests.py`, `tools/run_e2e_tests.py`, `tools/run_boot_smoke.py`), Python 3 (`tools/verify_contracts.py`, `tools/verify_runtime_wiring.py`, `tools/verify_manifest_sync.py`, `tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/validate_lua_syntax.py`, `tools/sync_gdrive.py`, `tools/verify_context_docs.py`, `tools.audit`, `unittest`), JSON configs/contracts (`config/protocol_contracts.json`, `config/audit_baselines.json`, subsystem `config/*.json`).

**Spec & Audit Sources:**
- Backlog SSOT: `TASK.md` (`TASK-017-1`, `TASK-017-2`, `TASK-017-3`, `TASK-018-1`, `TASK-018-2`, `TASK-018-3`)
- Audit Report: `reports/underReview/Architecture_Efficiency_Audit_1_11182026.md` (`E-L2-01..04`, `E-L3-01..04`, P5 Gate decisions `A1..A5`)
- Master ICD: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (§3)
- Wire Contracts: `config/protocol_contracts.json`
- Installer Spec: `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md`

---

## Global Constraints

1. **Zero-Fallback & Single Canonical Path:** Never add dual-key receiver fallbacks when aligning packet fields or config keys; tag removed fields `[DEPRECATED]` in specifications only and keep specs at their permanent `docs/specs/<domain>/<subsystem>/` paths.
2. **ASA Subsystem Freeze (`0 diff`):** `src/1_control/asa/**` and `tests/1_control/asa/**` are frozen until `TASK-105` (`TASK.md` §1, `TASK-013` Q4 Option B). Keep `MSG_SURFACE_DISCOVER_REQ.targetPod` as the sole entry in `config/audit_baselines.json` (`unconsumed_required_keys_baseline`: reduce `9 -> 1`).
3. **Multi-Codebase Containment:** Do not introduce cross-subsystem `require()` calls or new `/lib/*.lua` runtime libraries; `/lib/` exceptions remain strictly `/lib/avionics_sensors.lua` and `/lib/ota_agent.lua`.
4. **Docking Arm Forward-Compatibility Preservation:** Keep `MSG_DOCK_CAPTURE_STAGE` (`L638`) and `MSG_UMBILICAL_STATUS` (`L639`) in `src/3_planning/amm/main.lua` (`BASE_PLUS_5_INFRA_RESPONSES`) and `MSG_DOCK_CAPTURE_STAGE` in `handle_base5_rx` (`L685`), as required by `tests/3_planning/amm/test_main_loop.lua:1079-1080` and the `Approved` `docking_arm` spec.
5. **Preserve Existing `fcp_config.json` Test Invariants:** `tests/2_guidance/fcp/test_flight_fsm_v2.lua:376-445` asserts `cfg.version == "2.1.0"` and `cfg.system.loopFrequencyHz == 20`. Wire and consume these fields in `fcp` runtime code rather than deleting them from `fcp_config.json`.
6. **GDrive Mapping Stability:** Removing `src/0_development/installer/installer.lua` must leave all 135 entries in `config/gdrive_mapping.json` intact (`python tools/verify_manifest_sync.py --strict-gdrive-packages` stays `0 Errors, 0 Warnings`).
7. **Spec-First Ordering:** Task 1 completes and passes `python tools/verify_contracts.py --specs-only` before any `src/` or `tests/` code modification starts in Tasks 2–8. Every active spec whose runtime code will change in Tasks 2–8 must be transitioned to `Approved` with a `Revision History` row in Task 1, then promoted back to `Implemented` only after Task 9 verification passes.
8. **Shell & Git Discipline:** Use Windows PowerShell 5.1 command chaining (`; if ($?) { ... }`, no `&&`), `& "C:\Program Files\Git\cmd\git.exe"` for git commands, and work inside an isolated worktree/branch for implementation; never run destructive git commands (`push --force`, `reset --hard`, `clean -fd`, `branch -D`).
9. **No Overclaims & Exact Verification Reporting:** Report only exact numeric outputs observed from tool runs after final edits (passing tests, packet counts, baseline counts, audit findings).
10. **Locked Pre-Execution Rulings (`R1–R5`):** Work strictly in `.worktrees/feat-task-017-018-hygiene` (`feat/task-017-018-hygiene`) without merging to `main` (`R1`); `AMM` PBIT blocks `FAIL` only (allows `WARN`), `VAS` clears `recalibrationRequired` + sends `ACCEPTED` only on `FULL_6DOF_PASS`/`AERO_ASSISTED_PASS` (`R2`); `TCA` validates `0 < safetyMaxTiltDeg <= 45` on non-`pbitWiggle` pulses, `VAS` keeps backup snapshot and rolls back on `saveProfile == false`, `AMM` stores `divertChannel` and switches channel on `status == "DIVERT"` (`R3`); remove `manifest.BOOTSTRAP_FILES` instead of `require("installer")` in `manifest.lua` (`R4`); preserve `vas` `[0,360)` / `fcp` `[-180,180]` yaw domains, `FCP` `version` soft-warn, `coreTelemetryTimeoutMs` integrator freeze+warn, and `emergencyMaxBankDeg` `75.0°` on `EMERGENCY_MANEUVER`/`EMERGENCY_LAND` with `AMM_TIMEOUT_HOLD` at `18.0°` (`R5`).

---

## Review Focus

Pin these five high-risk regression traps in automated tests during execution:

1. **Zone 3 Upper-Bound Inversion (`tests/3_planning/amm/test_network_manager.lua:212`):** Existing unit tests explicitly reject channel offsets `30` (`10030`) as invalid Zone 3 payload offsets. Task 2 must invert `30`/`10030` assertions to accepted and add explicit out-of-range rejection assertions for `19`/`10019` and `40`/`10040`.
2. **Legacy Allowlist Test Update (`tests/3_planning/amm/test_main_loop.lua:1066-1091`):** Existing test feeds 15 packet types (including removed legacy types in `BASE_PLUS_5_INFRA_RESPONSES`) expecting `intrusionCount == 0`. Task 4 must assert that all 14 deleted legacy types increment `intrusionCount` (or are rejected by `handle_facility_rx`/`handle_base5_rx`), while canonical infra types plus `MSG_DOCK_CAPTURE_STAGE` and `MSG_UMBILICAL_STATUS` continue to pass with `intrusionCount == 0`.
3. **ASA Baseline Boundary (`config/audit_baselines.json`):** Reducing `unconsumed_required_keys_baseline` from `9` to `1` in Task 5 must pass `python -m tools.audit guard` while verifying `git diff -- src/1_control/asa tests/1_control/asa` remains completely empty.
4. **Root Installer Single-Source Test & Staging Breakage (`harness/unit/engine.py`, `tools/run_boot_smoke.py`, `tools/verify_runtime_wiring.py`, `tests/harness/test_installer_integrity.py`):** Removing `src/0_development/installer/installer.lua` breaks unit/boot runners that previously copied only `target.source_dir`, breaks `verify_runtime_wiring.py` subsystem-scoped `require("installer")` lookup, and fails `test_installer_byte_parity_between_root_and_src`. Task 6 must wire root `installer.lua` injection into the harness/tools and rewrite parity tests around single-source root `installer.lua`.
5. **Euler Yaw Wrapping & `save_flight_state` Signature Parity (`vas` vs `fcp` & `amm`):** `src/1_control/vas/modules/quat.lua:108-129` wraps yaw to `[0, 360)` whereas `src/2_guidance/fcp/modules/outer_loop_controller.lua:66-72` returns `[-180, 180]`, and `src/1_control/vas/modules/state_machine.lua:44,165` uses a 4-arg `save_flight_state(path, armedState, extra, fsApi)` signature tested in `tests/1_control/vas/test_vas_core.lua:1353,1388`. Task 7 must preserve each subsystem's yaw domain and update both internal callers and `test_vas_core.lua` when standardizing on `save_flight_state(path, stateTbl, fsApi)`.

---

## File Structure

Sequential task ownership (no parallel execution across shared files):

- **Task 1 (Spec-First Sync):**
  - Modify: `config/protocol_contracts.json`
  - Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`
  - Modify: `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md`
  - Modify: active subsystem specs referenced by `config/protocol_contracts.json` (`docs/specs/0_infra/{gac,gps,gcs,runway,landing_pad}/`, `docs/specs/1_control/{vas,tca}/`, `docs/specs/2_guidance/fcp/`, `docs/specs/3_planning/amm/` — exact filenames resolved from `config/protocol_contracts.json` `specs` lists)
- **Task 2 (Zone 3 `20..39` Expansion):**
  - Modify: `src/3_planning/amm/modules/mission_engine.lua`, `src/3_planning/amm/modules/network_manager.lua`
  - Test/Modify: `tests/3_planning/amm/test_network_manager.lua`, `tests/3_planning/amm/test_checkpoint_schema.lua`
- **Task 3 (Canonical Facility/Runway Builders & Consumers):**
  - Modify: `src/3_planning/amm/modules/facility_client.lua`, `src/0_infra/runway/modules/runway_fsm.lua`, `src/0_infra/landing_pad/modules/pad_fsm.lua`, `src/0_infra/gac/modules/gac_fsm.lua`, `src/0_infra/gac/main.lua`
  - Inspect/Align if needed: `src/0_infra/landing_pad/modules/tactical_streamer.lua`, `src/0_infra/runway/modules/beacon_broadcaster.lua`, `src/0_infra/gps/modules/protocol.lua`
  - Test/Modify: `tests/e2e/test_e2e_facility_landing.lua`, plus facility/runway/landing_pad unit tests
- **Task 4 (AMM Dead Legacy Packet Removal):**
  - Modify: `src/3_planning/amm/main.lua` (`BASE_PLUS_5_INFRA_RESPONSES`, `handle_facility_rx`, `handle_base5_rx`)
  - Test/Modify: `tests/3_planning/amm/test_main_loop.lua`
- **Task 5 (Unconsumed `requiredKeys` & Field Wiring, ASA Excluded):**
  - Modify: `src/3_planning/amm/modules/mission_engine.lua`, `src/3_planning/amm/modules/facility_client.lua`, `src/3_planning/amm/modules/channel_sentinel.lua`, `src/1_control/tca/modules/tca_daemon.lua`, `src/1_control/tca/modules/channel_rebind_handler.lua`, `src/1_control/tca/modules/discovery_handler.lua`, `src/1_control/vas/modules/state_machine.lua`, `src/1_control/vas/modules/network_manager.lua`, `src/1_control/vas/modules/core_daemon.lua`, `config/audit_baselines.json`
  - Test/Modify: `tests/3_planning/amm/test_checkpoint_schema.lua` (or AMM sentinel/facility unit suite), TCA unit tests, VAS `tests/1_control/vas/test_vas_core.lua`, `tests/harness/test_audit_tools.py`
- **Task 6 (Single-Source `installer.lua`):**
  - Delete: `src/0_development/installer/installer.lua`
  - Modify: `installer.lua`, `src/0_development/installer/modules/manifest.lua` (remove unused `BOOTSTRAP_FILES` block `L72-80`), `harness/unit/engine.py`, `tools/run_boot_smoke.py`, `tools/verify_runtime_wiring.py`, `tools/verify_manifest_sync.py`, `tools/sync_gdrive.py`, `tools/audit/guard.py`, `config/audit_baselines.json`
  - Test/Modify: `tests/0_development/installer/test_manifest_and_registry.lua`, `tests/harness/test_installer_integrity.py`, `tests/harness/test_manifest_sync_verifier.py`, `tests/harness/test_gdrive_sync.py`, `tests/harness/test_audit_tools.py`
- **Task 7 (Lua Deduplication & Config Copy Safety):**
  - Modify: `src/1_control/vas/modules/state_machine.lua`, `src/1_control/vas/modules/quat.lua`, `src/2_guidance/fcp/modules/outer_loop_controller.lua`, `src/1_control/tca/modules/config_manager.lua`
  - Test/Modify: `tests/1_control/vas/test_vas_core.lua`, FCP outer loop unit tests, TCA config manager unit tests
- **Task 8 (17 Dead Functions & 19 Unused Config Keys):**
  - Modify (Lua): `src/1_control/tca/modules/tui_dashboard.lua`, `src/2_guidance/fcp/modules/network_manager.lua`, `src/2_guidance/fcp/modules/flight_fsm.lua`, `src/2_guidance/fcp/modules/outer_loop_controller.lua`, `src/2_guidance/fcp/modules/state_propagator.lua`, `src/2_guidance/fcp/main.lua`, `src/3_planning/amm/modules/facility_client.lua`, `src/3_planning/amm/modules/network_manager.lua`, `src/3_planning/amm/main.lua`, `src/0_infra/landing_pad/modules/tui_view.lua`, `src/1_control/vas/modules/flight_dynamics_core.lua`, `src/1_control/vas/modules/quat.lua`, `src/1_control/vas/modules/state_machine.lua`, `src/1_control/vas/modules/vehicle_policy.lua`
  - Modify (JSON): `src/3_planning/amm/config/amm_config.json`, `src/2_guidance/fcp/config/fcp_config.json`, `src/0_development/fdr/config/fdr_config.json`
  - Test/Verify: `tests/2_guidance/fcp/test_flight_fsm_v2.lua`, `tests/0_development/fdr/test_fdr_main.lua`, `tests/0_development/fdr/test_fdr_ring_and_tap.lua`, plus new/updated config wiring assertions for `amm_config.json` and `fcp_config.json`
- **Task 9 (Full Gates, Spec Promotion, Context Memory Sync):**
  - Modify: promoted subsystem specs (`Approved` -> `Implemented`), `TASK.md`, `.agent/memory/workspace-root.md`, `GEMINI.md` (only if invariants/commands changed)

---

### Task 1: Spec-First Synchronization (`config/protocol_contracts.json`, Master ICD §3, Active Specs)

**Files:**
- Modify: `config/protocol_contracts.json` (`L758`, `L778-1105`, `L871-879`, `L921-929`, `L990-993`, `L1016`, `L1107-1235`, `L1237+`)
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (§3 packet blocks)
- Modify: `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` (`L35`, `L174`, metadata/Revision History)
- Modify: affected subsystem specs listed in `config/protocol_contracts.json` whose runtime code changes in Tasks 2–8 (`AMM`, `GAC`, `GPS`, `GCS`, `RUNWAY`, `LANDING_PAD`, `VAS`, `TCA`, `FCP`)

**Interfaces:**
- Consumes: `TASK-017-1..3` and `TASK-018-1..3` requirements in `reports/underReview/Architecture_Efficiency_Audit_1_11182026.md` and current active emitters/consumers in `src/`
- Produces: Synchronized `config/protocol_contracts.json`, Master ICD §3, and `Approved` subsystem specifications passing `python tools/verify_contracts.py --specs-only` with `0 errors`

Steps:
- [ ] **Step 1: Inspect existing schema conventions in `config/protocol_contracts.json` and `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`**
  - Verify exact field structures (`diagramRequired`, `specs`, `requiredKeys`, `optionalKeys`, `enums`) of `I-5` (`L778-1105`) and `I-7` (`L1237+`) and check exact active spec filenames under `docs/specs/`.
  - Record baseline output of:
    `python tools/verify_contracts.py --specs-only`
    and check the 8 packets missing from Master ICD §3.

- [ ] **Step 2: Update `config/protocol_contracts.json` (14 additions, 5 ghost removals, 3 guide `optionalKeys` additions)**
  - In `I-5` (`L778-1105`), add the 10 uncontracted active packets matching exact runtime emitter/consumer fields:
    - `MSG_ATC_SLOT_ASSIGN`, `MSG_ATC_SLOT_ACK`, `MSG_ABORT_APPROACH`, `MSG_ATC_APPROACH_REQ`
    - `MSG_ATC_DEPARTURE_COMPLETE` (`"diagramRequired": false`)
    - `MSG_ATC_SECTOR_HANDOFF_REQ`, `MSG_ATC_SECTOR_HANDOFF_ACK`, `MSG_GAC_DEPARTURE_REQ`
    - `MSG_GAC_DISPATCH` (`"diagramRequired": false`, `specs` scoped to `AMM` spec)
    - `MSG_GAC_SECTOR_STATUS` (`"diagramRequired": false`, `specs` scoped to `GAC` spec)
  - In `I-7` (`L1237+`), add the 4 uncontracted active GPS packets:
    - `MSG_GPS_NODE_REPORT` (`specs` scoped to `GPS` spec)
    - `MSG_GPS_STATUS_REQ`, `MSG_GPS_STATUS_RESP` (`specs` scoped to `GPS` and `AMM` specs)
    - `MSG_GPS_NODE_HEARTBEAT` (`"diagramRequired": false`, `specs` scoped to `GPS` and `GCS` specs)
  - Remove the 5 ghost `optionalKeys` (plus unused enum if tied solely to it):
    - `MSG_CALIBRATION_CLOSE_ACK.currentFsmState` (`L758`)
    - `MSG_ATC_APPROACH_CLEARANCE.glideSlope` (`L990`) and `MSG_ATC_APPROACH_CLEARANCE.retryAfterSec` (`L993`)
    - `MSG_GAC_CHECKIN_REQ.estimatedArrivalTime` (`L1016`)
    - `MSG_OPERATOR_CMD.emergencyAction` (`L1135`, `L1142` enum entry)
  - Add `"dockingCorridor"`, `"captureLatchReady"`, `"armState"` to `optionalKeys` on both `MSG_FACILITY_STATIC_GUIDE` (`L871-879`) and `MSG_FACILITY_DYNAMIC_GUIDE` (`L921-929`) so `facility_client.lua:213-215` matches contract.

- [ ] **Step 3: Synchronize Master ICD §3 (`docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`) & Sequence Diagrams**
  - Add the 8 packet blocks currently absent from Master ICD §3: `MSG_ATC_SLOT_ACK`, `MSG_GPS_NODE_REPORT`, `MSG_GPS_STATUS_REQ`, `MSG_GPS_STATUS_RESP`, `MSG_ATC_SECTOR_HANDOFF_ACK`, `MSG_GAC_DISPATCH`, `MSG_GAC_SECTOR_STATUS`, `MSG_GPS_NODE_HEARTBEAT` (and verify the other 6 of the 14 are fully aligned).
  - Update Master ICD §3 / Zone 3 RF tables to state the canonical Zone 3 channel allocation (`Base + 20..39` vs previous `Base + 20..29` note where applicable).
  - Ensure every packet where `"diagramRequired": false` is NOT set appears in its subsystem diagram/ICD per `tools/verify_contracts.py` rules.

- [ ] **Step 4: Update `INSTALLER_PROGRAM_SPECIFICATION.md` and affected subsystem specs; flip changed specs to `Approved`**
  - In `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md`: update `L35` and `L174` (and `INSTALLER_BYTE_PARITY_MISMATCH` invariant) to establish root `/installer.lua` as the single source of truth (including `BOOTSTRAP_FILES`), removing duplicate `src/0_development/installer/installer.lua` and `manifest.BOOTSTRAP_FILES`.
  - In affected active specs (`AMM`, `GAC`, `GPS`, `RUNWAY`, `LANDING_PAD`, `VAS`, `TCA`, `FCP` — do NOT touch `ASA` spec): update packet tables, Zone 3 `20..39` bounds, required-field consumer rules (`R2`–`R3`), `FCP` config wiring (`version` soft check, `coreTelemetryTimeoutMs` integrator freeze + warning, `emergencyMaxBankDeg` on `EMERGENCY_MANEUVER`/`EMERGENCY_LAND`, keeping `AMM_TIMEOUT_HOLD` at `18.0°` per FCP §10.1), and remove dead config keys (`[DEPRECATED]` / Zero-Fallback); transition header metadata `문서 상태` to `Approved`, update `최종 수정일` to `2026-11-19`, and append a `Revision History` row to each spec whose `src/` code will be edited in Tasks 2–8.

- [ ] **Step 5: Verify spec & contract consistency before any runtime code change**
  - Run:
    `python tools/verify_contracts.py --specs-only ; if ($?) { python tools/verify_all_specs.py --check-readmes } ; if ($?) { python tools/verify_spec_status.py }`
  - Expected: `verify_contracts.py --specs-only` reports `0 errors`; `verify_all_specs.py --check-readmes` reports `0 Errors, 0 Warnings`; `verify_spec_status.py` PASSes with updated `Approved` statuses matching edited specs.

- [ ] **Step 6: Commit Task 1 (Spec-First checkpoint)**
  - Run `& "C:\Program Files\Git\cmd\git.exe" add config/protocol_contracts.json docs/` (exact modified spec files only) and commit `spec(contracts,icd): sync protocol contracts and approve TASK-017/018 spec revisions`.

---

### Task 2: Zone 3 RF Channel Alignment (`20..29` -> `20..39`) in AMM

**Files:**
- Modify: `src/3_planning/amm/modules/mission_engine.lua` (`L118-128`: `is_zone3_spec`, lines `120, 125, 127`)
- Modify: `src/3_planning/amm/modules/network_manager.lua` (`L111`: `apply_rebind`, `L266`: `is_payload_channel`, `L273`: `resolve_payload_channel`)
- Test: `tests/3_planning/amm/test_network_manager.lua` (`L212+`), `tests/3_planning/amm/test_checkpoint_schema.lua` (`L120-167`)

**Interfaces:**
- Consumes: Task 1 Master ICD / `AMM` spec defining Zone 3 payload offsets `20..39` (`Base + 20` through `Base + 39`)
- Produces: `is_zone3_spec(p, base_channel)`, `network_manager.is_payload_channel(ch)`, `network_manager.resolve_payload_channel(spec)`, and `apply_rebind` accepting offsets `20..39` (inclusive) and rejecting `<20` or `>39`

Steps:
- [ ] **Step 1: Write/update failing TDD tests for Zone 3 `20..39` boundary**
  - In `tests/3_planning/amm/test_network_manager.lua` around `L212`: update assertions that previously treated `30` and `base + 30` (`10030`) as invalid Zone 3 payload channels so they assert accepted `20..39` (`10020..10039`, including boundary `30` and `39`), and assert rejection for `19`, `40`, `10019`, and `10040`.
  - In `tests/3_planning/amm/test_checkpoint_schema.lua`: add case asserting `is_zone3_spec` accepts offset `39` and `base + 39`, and rejects offset `19`, `40`, `base + 19`, and `base + 40`.

- [ ] **Step 2: Run AMM unit tests to confirm Red failure**
  - Run: `python tools/run_unit_tests.py --target amm --clean-orphans`
  - Expected: FAIL on new/updated assertions for offset `30` / `39` (`expected true/valid, got false/nil`).

- [ ] **Step 3: Implement `20..39` Zone 3 bounds in `mission_engine.lua` and `network_manager.lua`**
  - Update `src/3_planning/amm/modules/mission_engine.lua` `is_zone3_spec(p, base_channel)` (`L118-128`, specifically `L120, 125, 127`) from upper bound `29` / `base + 29` to `39` / `base + 39`.
  - Update `src/3_planning/amm/modules/network_manager.lua` (`L111` `apply_rebind`, `L266` `is_payload_channel`, `L273` `resolve_payload_channel`) from `29` to `39` (extract a small local offset/bound helper or constant `ZONE3_MIN_OFFSET = 20`, `ZONE3_MAX_OFFSET = 39` if duplicated within `network_manager.lua`).

- [ ] **Step 4: Verify Green**
  - Run: `python tools/run_unit_tests.py --target amm --clean-orphans`
  - Expected: All AMM unit tests PASS (`0` failures).

- [ ] **Step 5: Commit Task 2**
  - Commit `src/3_planning/amm/modules/mission_engine.lua`, `src/3_planning/amm/modules/network_manager.lua`, and updated AMM test files with message `feat(amm): expand Zone 3 RF channel bounds from 20..29 to 20..39`.

---

### Task 3: Canonical Facility & Runway Builders and Consumers (`MSG_RUNWAY_TOUCHDOWN`, `MSG_RUNWAY_VACATED`, `MSG_TOUCHDOWN_COMPLETE`, `GAC`/`GPS` Alignment)

**Files:**
- Modify: `src/3_planning/amm/modules/facility_client.lua` (`L158-189` `on_atc_clearance`, `L388-407` `build_touchdown_complete`; add `build_runway_touchdown`, `build_runway_vacated`)
- Modify: `src/0_infra/landing_pad/modules/pad_fsm.lua` (`L173-182` `MSG_TOUCHDOWN_COMPLETE` consuming `payload.touchdownTime`)
- Modify (verify & align exact contract fields): `src/0_infra/runway/modules/runway_fsm.lua` (`L95-113`), `src/0_infra/gac/modules/gac_fsm.lua` (`L55-125, L170-210`), `src/0_infra/gac/main.lua` (`L115-175`), `src/0_infra/gps/modules/protocol.lua` (`L1-160`), `src/0_infra/runway/modules/beacon_broadcaster.lua` (`L90-155`), `src/0_infra/landing_pad/modules/tactical_streamer.lua` (`L95-135`)
- Test/Modify: `tests/e2e/test_e2e_facility_landing.lua` (`L676-697` replace manual raw packet tables with `facility_client.build_runway_touchdown` / `build_runway_vacated`), plus facility/pad/runway/gac/gps unit tests

**Interfaces:**
- Consumes: `I-5` contracts in `config/protocol_contracts.json` for `MSG_RUNWAY_TOUCHDOWN` (including required `touchdownSpeed`), `MSG_RUNWAY_VACATED`, `MSG_TOUCHDOWN_COMPLETE` (`touchdownTime`), `MSG_ATC_APPROACH_CLEARANCE` (`divertChannel`)
- Produces: Canonical builders `facility_client.build_runway_touchdown(...)` and `facility_client.build_runway_vacated(...)`; consumer handling for `divertChannel` in `on_atc_clearance` and `touchdownTime` in `pad_fsm.lua`; aligned E2E/unit verification

Steps:
- [ ] **Step 1: Add failing TDD unit tests for canonical runway builders, `divertChannel`, and `touchdownTime`**
  - In AMM facility tests (`tests/3_planning/amm/`): test `facility_client.build_runway_touchdown(...)` emits valid `MSG_RUNWAY_TOUCHDOWN` packet carrying canonical `craftId`, `runwayId`/`facilityId`, `touchdownSpeed`, and required header keys; test `build_runway_vacated(...)` emits valid `MSG_RUNWAY_VACATED`; test `on_atc_clearance` stores `state.divertChannel = p.divertChannel` and, when `status == "DIVERT"`, switches active approach/GAC target channel (`state.gacChannel` / approach target channel) to `p.divertChannel`.
  - In landing pad tests (`tests/0_infra/landing_pad/`): test `pad_fsm` stores/records `payload.touchdownTime` on `MSG_TOUCHDOWN_COMPLETE`.
  - Check `runway_fsm.lua` (`L95-113`), `gac_fsm.lua`, `gac/main.lua`, `gps/modules/protocol.lua`, `tactical_streamer.lua`, `beacon_broadcaster.lua` against Task 1 contracts to ensure zero field drift on `requiredKeys`/`optionalKeys` (especially `MSG_RUNWAY_TOUCHDOWN.touchdownSpeed` in `runway_fsm.lua`!).

- [ ] **Step 2: Run targeted unit tests to verify Red failures**
  - Run: `python tools/run_unit_tests.py --target amm --clean-orphans ; if ($?) { python tools/run_unit_tests.py --target landing_pad --clean-orphans } ; if ($?) { python tools/run_unit_tests.py --target runway --clean-orphans }`
  - Expected: FAIL (`attempt to call nil value (field 'build_runway_touchdown')` / unrecorded `divertChannel` & `touchdownTime`).

- [ ] **Step 3: Implement canonical builders and consumer logic; switch E2E away from raw tables**
  - In `src/3_planning/amm/modules/facility_client.lua`: implement `build_runway_touchdown` and `build_runway_vacated` reusing the shared packet/envelope helper alongside `build_touchdown_complete` (`L388-407`); in `on_atc_clearance` (`L158-189`), record `state.divertChannel = p.divertChannel` and when `status == "DIVERT"` switch `state.gacChannel` (active approach/GAC channel) to `p.divertChannel`.
  - In `src/0_infra/landing_pad/modules/pad_fsm.lua` (`L173-182`): read and record/propagate `payload.touchdownTime` on `MSG_TOUCHDOWN_COMPLETE`.
  - In `src/0_infra/runway/modules/runway_fsm.lua` (`L95-113`): consume/record `payload.touchdownSpeed` on `MSG_RUNWAY_TOUCHDOWN` (satisfying `requiredKeys` audit for `MSG_RUNWAY_TOUCHDOWN.touchdownSpeed`) and align any remaining `gac`/`gps`/`tactical_streamer`/`beacon_broadcaster` field mismatches revealed by `verify_contracts.py`.
  - In `tests/e2e/test_e2e_facility_landing.lua` (`L676-697`): replace hand-crafted raw `MSG_RUNWAY_TOUCHDOWN` / `MSG_RUNWAY_VACATED` tables with `facility_client.build_runway_touchdown` and `facility_client.build_runway_vacated`.

- [ ] **Step 4: Verify Green**
  - Run:
    `python tools/verify_contracts.py ; if ($?) { python tools/run_unit_tests.py --target amm --clean-orphans } ; if ($?) { python tools/run_unit_tests.py --target landing_pad --clean-orphans } ; if ($?) { python tools/run_unit_tests.py --target runway --clean-orphans } ; if ($?) { python tools/run_unit_tests.py --target gac --clean-orphans } ; if ($?) { python tools/run_unit_tests.py --target gps --clean-orphans } ; if ($?) { python tools/run_e2e_tests.py --filter facility_landing --clean-orphans }`
  - Expected: Targeted unit tests & `facility_landing` E2E PASS; `verify_contracts.py` shows `0` uncontracted active packet errors.

- [ ] **Step 5: Commit Task 3**
  - Commit modified `facility_client.lua`, `pad_fsm.lua`, `runway_fsm.lua` (plus any aligned `gac`/`gps` files), and tests with message `feat(facility,amm): add canonical runway builders and consume touchdown/divert fields`.

---

### Task 4: Remove Dead Legacy Packets from AMM Allowlist & Handlers

**Files:**
- Modify: `src/3_planning/amm/main.lua` (`L577-608` `handle_facility_rx`, `L610-642` `BASE_PLUS_5_INFRA_RESPONSES`, `L678-695` `handle_base5_rx`)
- Test/Modify: `tests/3_planning/amm/test_main_loop.lua` (`L1060-1115`, pinning `L1066-1091`)

**Interfaces:**
- Consumes: Canonical `config/protocol_contracts.json` packet allowlist + Task 1 `Approved` AMM spec + `Approved` `docking_arm` spec (`MSG_DOCK_CAPTURE_STAGE`, `MSG_UMBILICAL_STATUS`)
- Produces: Pruned `BASE_PLUS_5_INFRA_RESPONSES`, `handle_facility_rx`, and `handle_base5_rx` rejecting the 14 dead legacy packet types cleanly while continuing to accept canonical infra packets plus `MSG_DOCK_CAPTURE_STAGE` and `MSG_UMBILICAL_STATUS`

Steps:
- [ ] **Step 1: Update `tests/3_planning/amm/test_main_loop.lua` (`L1066-1091`) for canonical allowlist & legacy rejection**
  - Keep canonical infra responses + `MSG_DOCK_CAPTURE_STAGE` (`L1079`) + `MSG_UMBILICAL_STATUS` (`L1080`) asserting `intrusionCount == 0`.
  - Split the 14 removed legacy types (`MSG_FACILITY_LIST_ACK`, `MSG_ATC_HANDOFF_CLEARANCE`, `MSG_ATC_SECTOR_HANDOFF`, `MSG_ATC_DEPARTURE_CLEARANCE`, `MSG_PAD_RESERVE_ACK`, `MSG_PAD_TELEMETRY`, `MSG_PAD_STATUS`, `MSG_LANDING_STATUS`, `MSG_LANDING_ACK`, `MSG_RUNWAY_ACK`, `MSG_ILS_BEACON`, `MSG_DOCK_ACK`, `MSG_DOCK_STATUS`, `MSG_DOCKING_STATUS`) into a separate negative assertion block verifying they are NO longer accepted (`intrusionCount` increments by 1 per legacy packet, and `handle_facility_rx`/`handle_base5_rx` drops/flags them without state side effects).

- [ ] **Step 2: Run `amm` unit tests to confirm Red failure on legacy packet acceptance**
  - Run: `python tools/run_unit_tests.py --target amm --clean-orphans`
  - Expected: FAIL (`intrusionCount` did not increment for removed legacy types because they are still in `BASE_PLUS_5_INFRA_RESPONSES`).

- [ ] **Step 3: Prune 14 dead legacy entries and dead handler branches in `src/3_planning/amm/main.lua`**
  - In `BASE_PLUS_5_INFRA_RESPONSES` (`L610-642`): remove the 14 legacy entries (`L616-637`), preserving all canonical active entries plus `MSG_DOCK_CAPTURE_STAGE` (`L638`) and `MSG_UMBILICAL_STATUS` (`L639`).
  - In `handle_facility_rx` (`L577-608`): remove dead branches for `MSG_ATC_SECTOR_HANDOFF` (`L581`) and `MSG_DOCKING_STATUS` (`L600`).
  - In `handle_base5_rx` (`L678-695`): remove dead `MSG_DOCKING_STATUS`/`MSG_DOCK_STATUS` aliases at `L685` (keeping `MSG_DOCK_CAPTURE_STAGE`) and dead `MSG_ATC_SECTOR_HANDOFF` branch at `L689`.

- [ ] **Step 4: Verify Green**
  - Run: `python tools/run_unit_tests.py --target amm --clean-orphans`
  - Expected: `test_main_loop.lua` and full AMM suite PASS (`0` failures).

- [ ] **Step 5: Commit Task 4**
  - Commit `src/3_planning/amm/main.lua` and `tests/3_planning/amm/test_main_loop.lua` with message `refactor(amm): remove 14 dead legacy packet types from RX allowlist and handlers`.

---

### Task 5: Wire Remaining Unconsumed `requiredKeys` & Contract Fields (`ASA` Excluded; Baseline `9 -> 1`)

**Files:**
- Modify (AMM): `src/3_planning/amm/modules/mission_engine.lua` (`L1034-1042` `enter_checkpoint` PBIT guard: consume `rep.overallStatus` and `rep.checks`), `src/3_planning/amm/modules/facility_client.lua` (`L51-78` `update_beacons`: consume `beacon_payload.facilitiesSummary`), `src/3_planning/amm/modules/channel_sentinel.lua` (`L239-264` `on_block_assign`: consume `payload.reassignedFrom`; `L282-303` `on_probe_ack`: consume `payload.existingDomain` and `payload.responderStatus`)
- Modify (TCA): `src/1_control/tca/modules/tca_daemon.lua` (`L112-117` `handle_calib_pulse`: consume `safetyMaxTiltDeg`), `src/1_control/tca/modules/channel_rebind_handler.lua` (`L42-43`: consume `bayCalibrationTap`, `bayCalibrationCmd`), `src/1_control/tca/modules/discovery_handler.lua` (`L1-86`: validate/consume `requestDomain`)
- Modify (VAS): `src/1_control/vas/modules/state_machine.lua` (`L336-348` `evaluate_pbit` `overallStatus`/`checks`), `src/1_control/vas/modules/network_manager.lua` (`L160-275`: consume `targetCraftDomain`/`targetThruster` in `handle_calibration_init`, `targetThruster` in `MSG_CALIB_START`, `saveProfile` in `MSG_CALIBRATION_CLOSE`), `src/1_control/vas/modules/core_daemon.lua` (`L196-206` `net.on_profile_sync`: inspect `payload.controllabilityStatus`, `calibratedBy`, `discoveredSurfaces` before clearing `recalibrationRequired`)
- Modify (Baseline): `config/audit_baselines.json` (`unconsumed_required_keys_baseline`: reduce from 9 entries to 1 entry `["MSG_SURFACE_DISCOVER_REQ.targetPod"]`)
- **FORBIDDEN TO TOUCH:** `src/1_control/asa/**`, `tests/1_control/asa/**`
- Test/Modify: AMM, TCA, VAS unit suites + `tests/harness/test_audit_tools.py`

**Interfaces:**
- Consumes: Task 1 `config/protocol_contracts.json` `requiredKeys` & `optionalKeys` (`MSG_PBIT_REPORT.{overallStatus, checks}`, `MSG_CALIB_PULSE.safetyMaxTiltDeg`, `MSG_CALIB_START.targetThruster`, `MSG_PROFILE_SYNC.controllabilityStatus`, `MSG_FACILITY_BEACON.facilitiesSummary`, `MSG_CHANNEL_PROBE_ACK.existingDomain`, `MSG_SURFACE_DISCOVER_REQ.targetPod` frozen)
- Produces: Runtime validation/consumption for all 7 non-ASA unconsumed `requiredKeys` (+ Task 3's `MSG_RUNWAY_TOUCHDOWN.touchdownSpeed` = 8/8 non-ASA consumed) and auxiliary fields (`reassignedFrom`, `responderStatus`, `targetCraftDomain`, `saveProfile`, `calibratedBy`, `discoveredSurfaces`, `bayCalibrationTap`, `bayCalibrationCmd`, `requestDomain`), reducing `config/audit_baselines.json` `unconsumed_required_keys_baseline` from `9 -> 1`.

Steps:
- [ ] **Step 1: Write failing TDD unit tests for each unconsumed required & secondary protocol field (Locked Rulings R2 & R3)**
  - **AMM:**
    - `enter_checkpoint` blocks takeoff (`PBIT_TAKEOFF_INTERLOCK`) whenever `rep.overallStatus == "FAIL"` OR any entry in `rep.checks` has `status == "FAIL"`, even if `rep.takeoffPermitted == true`; allows `overallStatus == "WARN"` when `rep.takeoffPermitted == true` (recording warning metadata).
    - `facility_client.update_beacons` records/indexes `beacon_payload.facilitiesSummary`.
    - `channel_sentinel.on_block_assign` handles `payload.reassignedFrom` conflict/reassignment logging/state; `channel_sentinel.on_probe_ack` evaluates `payload.existingDomain` (detecting domain conflict) and `payload.responderStatus`.
  - **TCA:**
    - `tca_daemon.handle_calib_pulse`: for non-`pbitWiggle` calibration pulses, validates `type(p.safetyMaxTiltDeg) == "number" and p.safetyMaxTiltDeg > 0 and p.safetyMaxTiltDeg <= 45`, returning `false, "INVALID_SAFETY_MAX_TILT"` when missing/out-of-range and storing `inst.lastSafetyMaxTiltDeg` when valid.
    - `channel_rebind_handler` wires `bayCalibrationTap` and `bayCalibrationCmd` to internal calibration bindings (`state.hangarBayChannel`, `state.hangarPulseChannel`) instead of dropping them.
    - `discovery_handler` checks/records `requestDomain`.
  - **VAS:**
    - `network_manager`: `handle_calibration_init` checks `targetCraftDomain` mismatch and records/forwards `targetThruster`; `MSG_CALIB_START` records/applies `targetThruster`; `MSG_PROFILE_SYNC` saves a pre-sync backup snapshot (`thrusters.json`, `peripheralManifest`, `recalibrationRequired`, mixer coefficients) and clears `recalibrationRequired = false` + replies `MSG_CALIB_ACK(status="ACCEPTED")` **only** when `controllabilityStatus` is `"FULL_6DOF_PASS"` or `"AERO_ASSISTED_PASS"` (otherwise keeps `recalibrationRequired = true` and replies `MSG_CALIB_ACK(status="REJECTED")`); `MSG_CALIBRATION_CLOSE` with `saveProfile == false` rolls back disk & in-memory profile/manifest to the pre-sync snapshot and restores `recalibrationRequired = true`.

- [ ] **Step 2: Run AMM, TCA, VAS unit suites to confirm Red failures**
  - Run: `python tools/run_unit_tests.py --target amm --clean-orphans ; if ($?) { python tools/run_unit_tests.py --target tca --clean-orphans } ; if ($?) { python tools/run_unit_tests.py --target vas --clean-orphans }`
  - Expected: Newly added unit assertions FAIL on all unconsumed fields.

- [ ] **Step 3: Implement field consumers in AMM, TCA, VAS per R2/R3 and update `config/audit_baselines.json` (`9 -> 1`)**
  - Implement all AMM (`mission_engine.lua`, `facility_client.lua`, `channel_sentinel.lua`), TCA (`tca_daemon.lua`, `channel_rebind_handler.lua`, `discovery_handler.lua`), and VAS (`state_machine.lua`, `network_manager.lua`, `core_daemon.lua`) consumer handlers carefully without modifying `src/1_control/asa/**` or `tests/1_control/asa/**`.
  - Update `config/audit_baselines.json` `unconsumed_required_keys_baseline` to keep ONLY `"MSG_SURFACE_DISCOVER_REQ.targetPod"`.
  - Check if `tests/harness/test_audit_tools.py` asserts exact baseline counts or behavior and update any stale baseline count fixture if present.

- [ ] **Step 4: Verify Green and verify zero diff on `ASA` + audit baseline `1/1`**
  - Run:
    `python tools/run_unit_tests.py --target amm --clean-orphans ; if ($?) { python tools/run_unit_tests.py --target tca --clean-orphans } ; if ($?) { python tools/run_unit_tests.py --target vas --clean-orphans } ; if ($?) { python -m tools.audit guard } ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" diff -- src/1_control/asa tests/1_control/asa }`
  - Expected: AMM, TCA, VAS tests PASS; `python -m tools.audit guard` PASSes with `unconsumed_required_keys` count `1` (`MSG_SURFACE_DISCOVER_REQ.targetPod` only); `git diff` on `asa` is empty.

- [ ] **Step 5: Commit Task 5**
  - Commit Task 5 modified files + `config/audit_baselines.json` with message `feat(amm,tca,vas): wire 8 unconsumed requiredKeys and shrink audit baseline to ASA freeze only`.

---

### Task 6: Single-Source `installer.lua` Elimination (Delete Duplicate `src/0_development/installer/installer.lua` & Unify `BOOTSTRAP_FILES` per R4)

**Files:**
- Delete: `src/0_development/installer/installer.lua`
- Modify: `installer.lua` (canonical `L10-18` `BOOTSTRAP_FILES`), `src/0_development/installer/modules/manifest.lua` (remove unused `manifest.BOOTSTRAP_FILES` block `L72-80`; do NOT call `require("installer")` in `manifest.lua`)
- Modify Harness & Tools: `harness/unit/engine.py` (`L120-149`), `tools/run_boot_smoke.py` (`L184-212`), `tools/verify_runtime_wiring.py` (`L300-387`), `tools/verify_manifest_sync.py` (`parse_manifest` `L248-265`, `L365-430`, `L550-595`), `tools/sync_gdrive.py` (`L375-420`, specifically `L404-408` `embed_bootstrap_ids`), `tools/audit/guard.py`, `config/audit_baselines.json`
- Test/Modify: `tests/0_development/installer/test_manifest_and_registry.lua` (`L74`), `tests/harness/test_installer_integrity.py` (`L22-35` & related), `tests/harness/test_manifest_sync_verifier.py`, `tests/harness/test_gdrive_sync.py`, `tests/harness/test_audit_tools.py`
- **INVARIANT:** Leave `config/gdrive_mapping.json` (135 entries) completely untouched.

**Interfaces:**
- Consumes: Task 1 updated `INSTALLER_PROGRAM_SPECIFICATION.md` (`L35`, `L174` single-source root `/installer.lua`)
- Produces: Single `/installer.lua` at repo root injected automatically into installer unit/boot temp roots and resolved by `verify_runtime_wiring.py` / `verify_manifest_sync.py` / `sync_gdrive.py` / `tools.audit.guard`, plus single-source `BOOTSTRAP_FILES` (`7` entries in root `installer.lua` only; removed from `manifest.lua`)

Steps:
- [ ] **Step 1: Update `tests/harness/` & installer unit tests first (Red phase)**
  - In `tests/harness/test_installer_integrity.py` (`L22-35`): replace `test_installer_byte_parity_between_root_and_src` (which asserted `src_installer.exists()`) with tests asserting:
    1. `src/0_development/installer/installer.lua` does NOT exist (enforcing single-source root `installer.lua`),
    2. `harness/unit/engine.py` stages root `installer.lua` when preparing `0_development/installer` runs, and
    3. `src/0_development/installer/modules/manifest.lua` does NOT define `BOOTSTRAP_FILES` while root `installer.lua` holds all `7` `BOOTSTRAP_FILES` entries.
  - In `tests/0_development/installer/test_manifest_and_registry.lua:74`: remove/migrate `manifest.BOOTSTRAP_FILES` length assertion to test root `installer.BOOTSTRAP_FILES` (`require("installer").BOOTSTRAP_FILES` when staged) or manifest non-bootstrap metadata cleanly.
  - In `tests/harness/test_manifest_sync_verifier.py`, `tests/harness/test_gdrive_sync.py`, and `tests/harness/test_audit_tools.py`: update fixtures/assertions that expected `src/0_development/installer/installer.lua` or `manifest.BOOTSTRAP_FILES`, and test fail-on-duplicate rules in `tools/audit/guard.py` and `verify_manifest_sync.py`.

- [ ] **Step 2: Run harness & installer unit tests to verify Red failures**
  - Run:
    `python -m unittest tests/harness/test_installer_integrity.py tests/harness/test_manifest_sync_verifier.py tests/harness/test_gdrive_sync.py tests/harness/test_audit_tools.py ; if ($?) { python tools/run_unit_tests.py --target installer --clean-orphans }`
  - Expected: `test_installer_integrity.py` FAILs because `src/0_development/installer/installer.lua` and `manifest.BOOTSTRAP_FILES` still exist and staging/guard rules still check dual-copy parity.

- [ ] **Step 3: Remove `src/0_development/installer/installer.lua` and remove unused `manifest.BOOTSTRAP_FILES`**
  - Delete `src/0_development/installer/installer.lua` via `git rm`.
  - Keep root `installer.lua` (`L10-18`) as the sole canonical definition of the `7`-entry `BOOTSTRAP_FILES` table (`bootstrapper.BOOTSTRAP_FILES`, returned via `installer.lua` module return without requiring `modules.manifest`).
  - Remove the unused `manifest.BOOTSTRAP_FILES = { ... }` literal block (`L72-80`) from `src/0_development/installer/modules/manifest.lua` (do NOT add `require("installer")` inside `manifest.lua`, preserving safe `remote_wget` bootstrap isolation).

- [ ] **Step 4: Wire single-source root `installer.lua` into harness, runners, verifiers, and GDrive sync**
  - `harness/unit/engine.py` (`L120-149`): when `target.source_dir` is `src/0_development/installer`, copy repo-root `installer.lua` into the CraftOS staging root/work dir so `require("installer")` in `main.lua:5` and `installer.BOOTSTRAP_FILES` tests resolve identically to on-device `/installer.lua`.
  - `tools/run_boot_smoke.py` (`L184-212`): stage repo-root `installer.lua` alongside `src/0_development/installer/` during installer boot smoke test.
  - `tools/verify_runtime_wiring.py` (`L300-387`): teach module resolver (`L327`) that when checking `src/0_development/installer`, `require("installer")` resolves to repo-root `installer.lua` without marking it unresolved or dead.
  - `tools/verify_manifest_sync.py` (`L248-265`, `L365-430`, `L550-595`): parse `bootstrap_files` solely from root `installer.lua` (`bootstrap_files = parse_bootstrap_entries(root_installer_text)`), FAIL if `src/0_development/installer/installer.lua` exists or if `manifest.lua` defines `BOOTSTRAP_FILES`, and continue validating all 135 `config/gdrive_mapping.json` entries untouched.
  - `tools/sync_gdrive.py` (`L375-420`, specifically `embed_bootstrap_ids` `L404-408`): update ONLY root `installer.lua` (remove edits to deleted `src/0_development/installer/installer.lua` and removed `manifest.BOOTSTRAP_FILES`).
  - `tools/audit/guard.py` & `config/audit_baselines.json`: replace byte-parity mirror check with invariant asserting forbidden duplicates (`installer_forbidden_duplicates`: `["src/0_development/installer/installer.lua"]`) do NOT exist (`status = "FAIL"` if present) and update baseline schema/fixtures cleanly.

- [ ] **Step 5: Verify Green across harness tests, installer unit/boot tests, manifest sync, wiring, and audit guard**
  - Run:
    `python -m unittest discover -s tests/harness -p "test_*.py" ; if ($?) { python tools/run_unit_tests.py --target installer --clean-orphans } ; if ($?) { python tools/run_boot_smoke.py --clean-orphans } ; if ($?) { python tools/verify_runtime_wiring.py } ; if ($?) { python tools/verify_manifest_sync.py --strict-gdrive-packages } ; if ($?) { python -m tools.audit guard }`
  - Expected: All `tests/harness` unit tests PASS; `installer` unit tests PASS; 13/13 boot smoke PASS; `verify_runtime_wiring.py` `0 violations`; `verify_manifest_sync.py --strict-gdrive-packages` `0 Errors, 0 Warnings` (135 GDrive entries); `audit guard` PASS.

- [ ] **Step 6: Commit Task 6**
  - Commit deletion of `src/0_development/installer/installer.lua` and all modified files from Steps 3–4 with message `refactor(installer,tools): make root /installer.lua single source of truth`.

---

### Task 7: Code Deduplication & Copy-Safety Hardening (`vas`, `fcp`, `tca`)

**Files:**
- Modify: `src/1_control/vas/modules/state_machine.lua` (`L44`, `L165`: change `save_flight_state(path, armedState, extra, fsApi)` to `save_flight_state(path, stateTbl, fsApi)` matching AMM's `(path, state_tbl, fs_api)` signature and atomic write flow)
- Modify: `src/1_control/vas/modules/quat.lua` (`L108-129`: clean `to_euler` `[0,360)` yaw helper with explicit singularity/gimbal-lock clamping)
- Modify: `src/2_guidance/fcp/modules/outer_loop_controller.lua` (`L66-72`: align `quat_to_euler_deg` internal math/clamping pattern while preserving `[-180,180]` yaw return range)
- Modify: `src/1_control/tca/modules/config_manager.lua` (`L28-32`: replace shallow table copy with recursive `deep_copy`)
- Test/Modify: `tests/1_control/vas/test_vas_core.lua` (`L1353`, `L1388`), FCP outer loop unit tests (`tests/2_guidance/fcp/`), TCA config manager unit tests (`tests/1_control/tca/`)

**Interfaces:**
- Consumes: `src/3_planning/amm/modules/mission_engine.lua:58-90` (`save_flight_state(path, state_tbl, fs_api)`) canonical signature pattern (without cross-subsystem `require`)
- Produces: Canonical 3-arg `vas` `state_machine.save_flight_state(path, stateTbl, fsApi)`; pinned domain-preserving `vas` `[0,360)` and `fcp` `[-180,180]` Euler conversions; mutation-safe recursive `deep_copy` in `tca/modules/config_manager.lua`

Steps:
- [ ] **Step 1: Add/update failing TDD tests for `save_flight_state`, Euler yaw domains, and `tca` deep copy**
  - In `tests/1_control/vas/test_vas_core.lua` (`L1353, L1388`): update calls to `save_flight_state(path, { armedState = ..., ... }, fsApi)` asserting atomic persistence (`stateTbl` fields serialized cleanly); add gimbal-pitch +/-90 deg & yaw `[0, 360)` boundary assertions on `quat.to_euler`.
  - In `tests/2_guidance/fcp/`: pin `outer_loop_controller.quat_to_euler_deg` yaw domain `[-180, 180]` across all 4 quadrants and gimbal-pitch clamp (`[-90, 90]`).
  - In `tests/1_control/tca/`: add regression test showing mutating nested sub-tables on a returned config from `config_manager` does NOT mutate subsequent default config loads (currently fails due to shallow copy at `L28-32`).

- [ ] **Step 2: Run VAS, FCP, TCA tests to verify Red failures**
  - Run: `python tools/run_unit_tests.py --target vas --clean-orphans ; if ($?) { python tools/run_unit_tests.py --target fcp --clean-orphans } ; if ($?) { python tools/run_unit_tests.py --target tca --clean-orphans }`
  - Expected: New 3-arg `save_flight_state` and nested config isolation assertions FAIL.

- [ ] **Step 3: Implement canonical `save_flight_state`, aligned Euler math, and recursive `deep_copy`**
  - In `src/1_control/vas/modules/state_machine.lua` (`L44`, `L165`): refactor `save_flight_state` signature to `(path, stateTbl, fsApi)` (matching `amm/modules/mission_engine.lua:58-90` pattern with `.tmp` atomic write/move cleanup) and update the sole internal caller at `L165`. Verify via repo grep that no other callers of `vas` `save_flight_state` exist.
  - In `src/1_control/vas/modules/quat.lua` (`L108-129`) and `src/2_guidance/fcp/modules/outer_loop_controller.lua` (`L66-72`): clamp `asin` argument safely to `[-1, 1]` and standardize quaternion axis conventions while explicitly keeping `[0, 360)` wrap in `vas` and `[-180, 180]` wrap in `fcp`.
  - In `src/1_control/tca/modules/config_manager.lua` (`L28-32`): replace shallow loop copy with small local `deep_copy(v)` helper handling nested sub-tables.

- [ ] **Step 4: Verify Green**
  - Run: `python tools/run_unit_tests.py --target vas --clean-orphans ; if ($?) { python tools/run_unit_tests.py --target fcp --clean-orphans } ; if ($?) { python tools/run_unit_tests.py --target tca --clean-orphans }`
  - Expected: Full VAS, FCP, and TCA unit suites PASS.

- [ ] **Step 5: Commit Task 7**
  - Commit modified `vas`, `fcp`, `tca` files and updated unit tests with message `refactor(vas,fcp,tca): standardize save_flight_state signature, clamp Euler helpers, and deep-copy TCA defaults`.

---

### Task 8: Prune 17 Dead Functions & Reconcile 19 Unused Config Keys

**Files:**
- Modify (17 dead functions across 7 modules):
  1. `src/1_control/tca/modules/tui_dashboard.lua`: delete `render_status_line` (`L43`), `format_actuator_row` (`L57`), `get_diagnostic_lines` (`L76`)
  2. `src/2_guidance/fcp/modules/network_manager.lua`: delete `send_guidance_cmd` (`L367`), `send_channel_rebind` (`L375`), `rebind_aircraft_channels` (`L393`)
  3. `src/2_guidance/fcp/modules/flight_fsm.lua`: delete `is_flight_active` (`L281`), `is_armed` (`L287`), `is_vtol` (`L293`)
  4. `src/3_planning/amm/modules/facility_client.lua`: delete `find_nearest_free_facility` (`L103`), `evaluate_approach_safety` (`L350-366`)
  5. `src/3_planning/amm/modules/network_manager.lua`: delete `close_infra_channel` (`L252-260`)
  6. `src/0_infra/landing_pad/modules/tui_view.lua`: delete `render_halt_warning` (`L127`)
  7. `src/1_control/vas/modules/flight_dynamics_core.lua`: delete `compute_climb_wrench` (`L111`)
  8. `src/1_control/vas/modules/quat.lua`: delete `rotate_vector` (`L60`)
  9. `src/1_control/vas/modules/state_machine.lua`: delete `on_actuators_ready` (`L230`)
  10. `src/1_control/vas/modules/vehicle_policy.lua`: delete `transition_blend` (`L188`)
- Modify (19 unused config keys & their consumers):
  - `src/3_planning/amm/config/amm_config.json` (10 keys -> wire 7, remove 3):
    - Wire in `src/3_planning/amm/modules/network_manager.lua` (`L59` `bind_modems` reads `cfg.channels.{facilityBeaconChannel, runwayDirectoryChannel, atcCommChannel, gpsServiceChannel}` with protocol defaults) and `src/3_planning/amm/main.lua` (`cfg.channels.gpsPingChannel`, `cfg.system.loopFrequencyHz` replacing hardcoded `0.05` at `L1207-1225`, `cfg.system.uiFrequencyHz` replacing hardcoded `0.2` at `L1227-1244`).
    - Remove dead keys: `trajectory.docking.{maxHorizToleranceM, maxVertToleranceM, maxHeadingToleranceDeg}`.
  - `src/2_guidance/fcp/config/fcp_config.json` (6 keys -> wire 5, remove 1):
    - Wire in `src/2_guidance/fcp/main.lua` (`L34-58` `load_config` records soft warning/flag on `cfg.version` mismatch without aborting boot; `L327-341` `run_control_loop` computes interval from `cfg.system.loopFrequencyHz` instead of hardcoded `0.05`; telemetry watchdog checks `cfg.safety.coreTelemetryTimeoutMs` per `FCP_PROGRAM_SPECIFICATION.md` §10.1 `L944` to freeze outer-loop integrators `events.freezeIntegrators = true` and flag telemetry timeout warning without forcing `EMERGENCY_HOLD`), `src/2_guidance/fcp/modules/network_manager.lua` (`L342` `> 500` reads `rebindAckTimeoutMs`), `src/2_guidance/fcp/modules/outer_loop_controller.lua` (`L310-338` `project_fixed_wing` enforces `emergencyMaxBankDeg` `75.0` during `sp.constraintProfile == "EMERGENCY_MANEUVER"` OR `fsmCtx.currentState == "EMERGENCY_LAND"`, while keeping `AMM_TIMEOUT_HOLD` at `18.0°` per FCP §10.1 `L943`). Preserve `version == "2.1.0"` and `system.loopFrequencyHz == 20` per `tests/2_guidance/fcp/test_flight_fsm_v2.lua:376-445`.
    - Remove dead comment key: `system._airframeType_comment`.
  - `src/0_development/fdr/config/fdr_config.json` (3 keys -> remove 3):
    - Remove unused keys `bandwidth`, `export.timeoutSec`, `debug`.
- Test/Verify: `tests/2_guidance/fcp/test_flight_fsm_v2.lua` (`L375-445`), `tests/0_development/fdr/test_fdr_main.lua` (`L180-187`), `tests/0_development/fdr/test_fdr_ring_and_tap.lua` (`L5-12`), plus unit assertions for wired config parameters in AMM and FCP

**Interfaces:**
- Consumes: Task 1 updated AMM, FCP, TCA, VAS, LANDING_PAD, FDR configs/specs + P5 Gate audit list (`E-L3-01..04`)
- Produces: `0` dead functions among the 17 listed targets, `0` unused keys across `amm_config.json`, `fcp_config.json`, and `fdr_config.json`, `0` regressions on `test_flight_fsm_v2.lua`, `test_fdr_main.lua`, `test_fdr_ring_and_tap.lua`

Steps:
- [ ] **Step 1: Add failing TDD assertions for newly wired `amm_config.json` and `fcp_config.json` runtime parameters**
  - In AMM unit tests (`tests/3_planning/amm/`): assert custom `cfg.channels.{facilityBeaconChannel, runwayDirectoryChannel, atcCommChannel, gpsServiceChannel, gpsPingChannel}` override defaults when binding/sending, and `cfg.system.{loopFrequencyHz, uiFrequencyHz}` determine `make_coroutine_a`/`make_coroutine_b` tick period.
  - In FCP unit tests (`tests/2_guidance/fcp/`): assert custom `cfg.system.loopFrequencyHz`, `cfg.safety.rebindAckTimeoutMs`, `cfg.safety.coreTelemetryTimeoutMs` (freezing integrators & flagging VAS timeout warning without forcing `EMERGENCY_HOLD`), and `cfg.outerLoop.fixed_wing.emergencyMaxBankDeg` (`EMERGENCY_MANEUVER` / `EMERGENCY_LAND` -> `75.0°`, `AMM_TIMEOUT_HOLD` -> `18.0°`) behave per R5; verify `load_config` accepts `"2.1.0"` cleanly and records a soft warning on mismatch without failing boot.
  - Run `python tools/run_unit_tests.py --target amm --clean-orphans ; if ($?) { python tools/run_unit_tests.py --target fcp --clean-orphans }` -> Expected: new custom-config override assertions FAIL.

- [ ] **Step 2: PowerShell `Select-String`-verify zero callers and delete all 17 dead Lua functions**
  - Verify via PowerShell `Get-ChildItem -Recurse -Include *.lua src/,tests/ | Select-String -Pattern "<fn_name>"` (NOT `rg`, which is unavailable) that none of the 17 functions have callers; delete them cleanly across the 10 module files (`tca/tui_dashboard.lua`, `fcp/network_manager.lua`, `fcp/flight_fsm.lua`, `amm/facility_client.lua`, `amm/network_manager.lua`, `landing_pad/tui_view.lua`, `vas/flight_dynamics_core.lua`, `vas/quat.lua`, `vas/state_machine.lua`, `vas/vehicle_policy.lua`).

- [ ] **Step 3: Wire remaining config keys and prune the 7 dead JSON keys**
  - Wire the 7 `amm_config.json` keys (`channels.*`, `system.loopFrequencyHz`, `system.uiFrequencyHz`) in `amm/modules/network_manager.lua` and `amm/main.lua`; remove `trajectory.docking.{maxHorizToleranceM, maxVertToleranceM, maxHeadingToleranceDeg}` from `amm_config.json`.
  - Wire the 5 `fcp_config.json` keys (`version`, `system.loopFrequencyHz`, `safety.rebindAckTimeoutMs`, `safety.coreTelemetryTimeoutMs`, `outerLoop.fixed_wing.emergencyMaxBankDeg`) in `fcp/main.lua`, `fcp/modules/network_manager.lua`, `fcp/modules/state_propagator.lua`, and `fcp/modules/outer_loop_controller.lua`; remove `system._airframeType_comment` from `fcp_config.json`.
  - Remove `bandwidth`, `export.timeoutSec`, `debug` from `src/0_development/fdr/config/fdr_config.json` (confirm `tests/0_development/fdr/test_fdr_main.lua:183` and `test_fdr_ring_and_tap.lua:8` inline config mocks are unaffected).

- [ ] **Step 4: Verify Green across affected suites & static audit tools**
  - Run:
    `python tools/run_unit_tests.py --target amm --clean-orphans ; if ($?) { python tools/run_unit_tests.py --target fcp --clean-orphans } ; if ($?) { python tools/run_unit_tests.py --target tca --clean-orphans } ; if ($?) { python tools/run_unit_tests.py --target vas --clean-orphans } ; if ($?) { python tools/run_unit_tests.py --target landing_pad --clean-orphans } ; if ($?) { python tools/run_unit_tests.py --target fdr --clean-orphans } ; if ($?) { python tools/verify_runtime_wiring.py } ; if ($?) { python -m tools.audit static }`
  - Expected: All targeted unit tests PASS (including `test_flight_fsm_v2.lua`, `test_fdr_main.lua`, `test_fdr_ring_and_tap.lua`); `verify_runtime_wiring.py` reports `0 violations`; `tools.audit static` reports `0` dead functions and `0` unused config keys on cleaned configs.

- [ ] **Step 5: Commit Task 8**
  - Commit modified Lua and JSON files + tests with message `refactor(amm,fcp,vas,tca,pad,fdr): prune 17 dead functions and reconcile 19 unused config keys`.

---

### Task 9: Full Cross-Gate Verification, Spec `Implemented` Promotion & Context Sync

**Files:**
- Modify: All subsystem specs transitioned to `Approved` in Task 1 (`문서 상태`: `Implemented`, `최종 수정일`: completion date)
- Modify: `TASK.md` (mark `TASK-017`, `TASK-018` and sub-items `[x]`)
- Modify: `.agent/memory/workspace-root.md` (append `TASK-017` & `TASK-018` completion record via `md-management` skill)
- Check/Modify: `GEMINI.md` (update §1/§3 only if invariant/command counts changed, keeping `<= 80` lines)

**Interfaces:**
- Consumes: Completed implementation commits from Tasks 1–8
- Produces: Clean full verification pass across all project gates, `Implemented` spec statuses, synced `TASK.md` / memory / `GEMINI.md`, and `0 findings` from `verify_context_docs.py`

Steps:
- [ ] **Step 1: Run full protocol, wiring, syntax, manifest, and spec gates**
  - Run sequentially (PowerShell `; if ($?) { ... }`):
    1. `python tools/validate_lua_syntax.py`
    2. `python tools/verify_contracts.py`
    3. `python tools/verify_runtime_wiring.py`
    4. `python tools/verify_manifest_sync.py --strict-gdrive-packages`
    5. `python tools/verify_all_specs.py --check-readmes`
    6. `python -m tools.audit all`
  - Expected: `0` syntax errors, `0` contract errors, `0` runtime wiring violations, `0 Errors, 0 Warnings` on manifest/GDrive (`135` entries) & specs, `audit guard` & `audit static` clean.

- [ ] **Step 2: Run full CraftOS-PC unit, boot smoke, E2E simulation, mutation, and harness/WebUI tests**
  - Run sequentially:
    1. `python tools/run_boot_smoke.py --clean-orphans`
    2. `python tools/run_unit_tests.py --require-tests --clean-orphans`
    3. `python tools/run_e2e_tests.py --clean-orphans --check-baseline`
    4. `python tools/run_mutation_tests.py`
    5. `python -m unittest discover -s tests/harness -p "test_*.py"`
    6. `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py`
  - Verify `git diff -- src/1_control/asa tests/1_control/asa` is empty (`0 diff`).
  - Expected: `100%` PASS on boot smoke (13/13), unit tests (expanded count, 0 failures), E2E suites (23/23, 0 packet contract violations, tick budgets within baseline), mutation kill rate >= `90.0%`, harness tests PASS, WebUI tests PASS.

- [ ] **Step 3: Promote `Approved` specs to `Implemented` and update `TASK.md` + context docs**
  - Per `skill-workflows.md` lightweight completion transition (without calling `specification-lifecycle-manager`), update upper metadata table `문서 상태: Implemented` and `최종 수정일` in each spec touched by Task 1 that had `Approved` status.
  - Run `python tools/verify_spec_status.py` -> confirm PASS.
  - Update `TASK.md`: mark `TASK-017` (`TASK-017-1..3`) and `TASK-018` (`TASK-018-1..3`) `[x]` and sync completion status table.
  - Invoke `md-management` skill to append concise `TASK-017` & `TASK-018` entries to `.agent/memory/workspace-root.md` and update `GEMINI.md` §1 (`직전 완료`, `다음 액션`) cleanly within `<= 80` lines.

- [ ] **Step 4: Run final context verification & confirm clean repo status**
  - Run:
    `python tools/verify_context_docs.py ; if ($?) { python tools/verify_spec_status.py } ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" status -sb }`
  - Expected: `[PASS] context docs: 0 findings`, `verify_spec_status.py` PASS, only expected task commits present.

- [ ] **Step 5: Commit Task 9 documentation & context closure**
  - Commit promoted spec headers, `TASK.md`, `.agent/memory/workspace-root.md`, and `GEMINI.md` with message `docs(task-017,018): promote verified specs to Implemented and sync project context`.

---

## Plan Self-Review Summary

- **Spec coverage (`TASK-017-1..3` & `TASK-018-1..3`):** All 14 uncontracted active packets, 5 ghost `optionalKeys`, 3 missing guide `optionalKeys`, Master ICD §3 8 missing blocks, Zone 3 `20..39` expansion, canonical runway builders, 14 legacy RX removals (retaining `MSG_DOCK_CAPTURE_STAGE` & `MSG_UMBILICAL_STATUS`), 8 non-ASA unconsumed `requiredKeys` (keeping `ASA` frozen `9 -> 1`), root `installer.lua` single-source deduplication, `save_flight_state`/`Euler`/`deep_copy` hygiene, 17 dead function deletions, and 19 config key reconciliations map 1:1 to Tasks 1–8.
- **Step clarity:** Each step identifies exact file paths, function/key symbols, test assertions, and concrete CLI commands using Windows PowerShell 5.1 chaining.
- **Type & signature consistency:** Zone 3 `[20..39]` matches across `mission_engine.lua`, `network_manager.lua`, and Task 2 tests; `save_flight_state(path, stateTbl, fsApi)` matches across `amm`, `vas`, and `test_vas_core.lua`; yaw domain differences (`[0,360)` vs `[-180,180]`) and `fcp_config.json` preserved keys (`version`, `loopFrequencyHz`) remain invariant across Tasks 7–8.
- **Review Focus pinning:** Every one of the 5 pinned edge cases is guarded by an explicit Red-Green test step in Tasks 2, 4, 5, 6, and 7.
- **Proportion:** Scope is bounded strictly to `TASK-017` and `TASK-018` backlog items without touching frozen `ASA` or deferred `TASK-019..021` work.
