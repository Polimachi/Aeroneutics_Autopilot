# Contraption Interlock (`TASK-136`), Pre-Flight PBIT (`TASK-131`) & GPS Health / DR Hold-over Guard (`TASK-128`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement contraption assembly state interlock & peripheral topology rebinding (`TASK-136`), 5-stage pre-flight PBIT & `< 5%` actuator wiggle sequencer (`TASK-131`), and GPS constellation quality diagnostics with `1.5s` Dead-Reckoning hold-over, chunk-border spike blending, and automatic `HOLD_LEVEL` transition (`TASK-128`) in strict dependency order (`TASK-136` → `TASK-131` → `TASK-128`).

**Architecture:** All three tasks share `VAS_PROGRAM_SPECIFICATION.md`, `src/1_control/vas/`, and `config/protocol_contracts.json`, so we execute a unified Spec-First revision (`Task 1`) updating all affected subsystem specifications, the Master ICD, Packet Diagram, and `config/protocol_contracts.json` first, followed by sequential TDD implementation inside existing registered modules (`Task 2`: `TASK-136`, `Task 3`: `TASK-131`, `Task 4`: `TASK-128`), preserving 135-file `manifest.lua` / `config/gdrive_mapping.json` 3-way parity, and concluding with multi-node E2E verification and `Implemented` spec promotion (`Task 5`).

**Tech Stack:** CC:Tweaked Lua 5.2 (Cobalt VM), `config/protocol_contracts.json` SSOT, CraftOS-PC headless Lua unit & multi-node virtual-bus E2E harness (`tools/run_unit_tests.py`, `tools/run_e2e_tests.py`, `tools/run_boot_smoke.py`), Python static contract/wiring/spec verifiers (`tools/verify_contracts.py`, `tools/verify_runtime_wiring.py`, `tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/verify_manifest_sync.py`, `tools/verify_context_docs.py`).

**Spec:**
- `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (`v2.8.0 Implemented` → `v2.9.0 Approved` → `Implemented`)
- `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (`v1.24.0 Implemented` → `v1.25.0 Approved` → `Implemented`)
- `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (`v1.13.0 Implemented` → `v1.14.0 Approved` → `Implemented`)
- `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v2.5.0 Implemented` → `v2.6.0 Approved` → `Implemented`)
- `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v2.3.3 Implemented` → `v2.4.0 Approved` → `Implemented`)
- `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (`v2.4.0 Implemented` → `v2.5.0 Approved` → `Implemented`)
- `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.37.0 Approved` → `v1.38.0 Approved`)
- `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.20.1 Approved` → `v2.21.0 Approved`)

## Global Constraints

- **CC:Tweaked Lua 5.2 Compliance**: No `//`, `&`, `|`, `~`, `<<`, `>>`, no `arg`, no `getfenv`/`setfenv`, no `os.execute`/`os.remove`/`os.rename`/`os.exit`/`io.popen` (`.agent/rules/cc-tweaked-runtime.md`).
- **Prohibited Mods & Zero-Fallback**: Zero Valkyrien Skies / `kontraption:` identifiers (`.agent/rules/domain-aeronautics.md`) and zero dual-key legacy fallbacks (`verify_contracts.py`).
- **Cross-Subsystem Isolation & 3-Way Manifest Parity**: No `require()` across `src/<layer>/<subsystem>/` boundaries (except `/lib/avionics_sensors.lua` and `/lib/ota_agent.lua`), and place all new logic inside existing registered modules so `manifest.lua` and `config/gdrive_mapping.json` stay synchronized (`135` GDrive entries).
- **40-Channel Spectrum Standard**: Maintain $Base = 10000 + (N - 1) \times 40$ ($N=1\sim 1000$) and wire envelope `ver = "1.9.5"`.
- **No-Overclaim**: Avoid banned overclaim terms (`AGENTS.md`) across all specs, code comments, and reports.

## Review Focus

1. **In-Flight vs Ground `DISASSEMBLED` Handling (`TASK-136`)**:
   - Detecting `CONTRAPTION_STATE == "DISASSEMBLED"` while airborne (`state.isAirborne == true` or active flight state) must latch `E_STOP` (`"CONTRAPTION_DISASSEMBLED_IN_FLIGHT"`), whereas ground disassembly transitions to `DISARMED` and rejects `arm = true` with `ERR_CONTRAPTION_DISASSEMBLED`.
2. **Dynamic Rebinding vs Thruster/Mass Drift (`TASK-136`)**:
   - Re-numbering wired peripheral IDs (`thruster_2` → `thruster_5`) with unchanged thruster count and mass within `<= 5%` must transparently rebind without blocking flight, whereas thruster count mismatch or `> 5%` mass change must latch `recalibrationRequired = true` and reject arming (`ERR_RECALIBRATION_REQUIRED`).
3. **PBIT Wiggle Safety & Takeoff Interlock (`TASK-131`)**:
   - `TCA` wiggle check must clamp `pulseRatio` strictly `< 0.05` (`<= 0.04`), cut thrust back to `0` immediately, and fail-safe when `DISARMED`/`IDLE_ARMED` vs `NORMAL` flight; `AMM` must block all `ACT_TKL_*` takeoff actions when `takeoffPermitted == false` (or when `requirePbit == true` and no passing report exists).
4. **GPS 1.5s DR Hold-over & Chunk-Border Blending (`TASK-128`)**:
   - During transient GPS dropout (`<= 1500ms`), `VAS` and `FCP` must maintain velocity-integrated DR without snapping to raw stale coordinates (`drHoldoverActive = true`, `holdLevelActive = false`); only after `> 1500ms` blackout must `HOLD_LEVEL` engage, and GPS recovery after blackout or chunk-border jump must blend smoothly over 10 ticks rather than snapping instantaneously.
5. **Wire Contract & `verify_runtime_wiring.py` Cleanliness**:
   - Every transmitted `MSG_PBIT_REQ`, `MSG_PBIT_REPORT`, `MSG_NAV_QUALITY`, and updated `MSG_PROFILE_SYNC`/`MSG_GPS_RESPONSE` packet in E2E tests must pass `verify_contracts.py`, and all new helper functions must remain reachable from each subsystem's `main.lua` entrypoint with zero orphan/dead imports.

---

### Task 1: Unified Spec-First Revision (`TASK-136-1`, `TASK-131-1`, `TASK-128-1`)

**Files:**
- Modify: `config/protocol_contracts.json`
- Modify: `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`
- Modify: `tools/verify_spec_status.py`
- Modify: `TASK.md`

**Interfaces:**
- Produces: Synchronized `Approved` specs and `config/protocol_contracts.json` schemas for `peripheralManifest`, `MSG_PBIT_REQ`, `MSG_PBIT_REPORT`, `pbitWiggle`/`pulseRatio`, and `MSG_NAV_QUALITY`.

- [x] **Step 1: Update `config/protocol_contracts.json` for `I-4` (`peripheralManifest`, `MSG_PBIT_REQ`, `MSG_PBIT_REPORT`, `pbitWiggle`/`pulseRatio`) and `I-7` (`navQuality`, `consecutiveFailures`, `MSG_NAV_QUALITY`)**
- [x] **Step 2: Revise `ALIGNMENT` (`v2.9.0`), `VAS` (`v1.25.0`), `TCA` (`v1.14.0`), `AMM` (`v2.6.0`), `GPS` (`v2.4.0`), `FCP` (`v2.5.0`) to `Approved` (`2026-11-18`) and sync Master ICD (`v1.38.0`), Diagram (`v2.21.0`), `tools/verify_spec_status.py` (`8 Implemented, 10 Approved`), and `TASK.md`**
- [x] **Step 3: Run spec & contract verification gates**

Run:
```powershell
python tools/verify_all_specs.py --check-readmes; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/verify_contracts.py --specs-only }
```
Expected: `0 Errors, 0 Warnings` across all three commands.

---

### Task 2: `TASK-136` Implementation — Contraption Assembly Interlock & Peripheral Topology Rebinding

**Files:**
- Modify: `src/0_development/alignment/modules/profile_exporter.lua`
- Modify: `src/0_development/alignment/modules/align_master.lua`
- Modify: `src/1_control/vas/modules/sensor_pipeline.lua`
- Modify: `src/1_control/vas/modules/state_machine.lua`
- Modify: `src/1_control/vas/modules/core_daemon.lua`
- Modify: `src/1_control/tca/modules/actuator_adapter.lua`
- Test: `tests/0_development/alignment/test_alignment_core.lua`
- Test: `tests/1_control/vas/test_vas_core.lua`
- Test: `tests/1_control/tca/test_tca_core.lua`

**Interfaces:**
- Produces:
  - `profile_exporter.compute_topology_hash(manifest_tbl) -> string`
  - `profile_exporter.build_peripheral_manifest(domain_id, actuator_map, surfaces_map, sensor_roles, total_dry_mass) -> table`
  - `profile_exporter.save_peripheral_manifest(manifest_data, base_dir, fs_api) -> boolean, string`
  - `sensor_pipeline.detect_contraption_state(state, periphApi) -> string, number`
  - `sensor_pipeline.verify_and_rebind_topology(state, manifest, liveActuatorNodes, liveMass, periphApi) -> table`
  - `state_machine.update_contraption_interlock(state, contraptionState, recalibrationRequired, reason) -> boolean, string`
  - `actuator_adapter.scan_api_peripherals(state)` updating `state.logicalBindingMap`

- [x] **Step 1: Write failing unit tests in `tests/0_development/alignment/test_alignment_core.lua`, `tests/1_control/vas/test_vas_core.lua`, and `tests/1_control/tca/test_tca_core.lua` covering `peripheral_manifest` hash/save, `DISASSEMBLED` arming/in-flight interlock, thruster count / `> 5%` mass recalibration latch, and dynamic peripheral name rebinding**
- [x] **Step 2: Run targeted unit tests to verify they fail**

Run:
```powershell
python tools/run_unit_tests.py --target 0_development/alignment --target 1_control/vas --target 1_control/tca --clean-orphans
```
Expected: FAIL on newly added `TASK-136` assertions.

- [x] **Step 3: Implement `TASK-136` across `Alignment`, `VAS`, and `TCA`**
- [x] **Step 4: Run targeted unit tests to verify they pass**

Run:
```powershell
python tools/run_unit_tests.py --target 0_development/alignment --target 1_control/vas --target 1_control/tca --clean-orphans
```
Expected: PASS.

---

### Task 3: `TASK-131` Implementation — Pre-Flight PBIT & Actuator Wiggle Sequencer

**Files:**
- Modify: `src/1_control/vas/modules/state_machine.lua`
- Modify: `src/1_control/vas/modules/network_manager.lua`
- Modify: `src/1_control/vas/modules/core_daemon.lua`
- Modify: `src/1_control/tca/modules/tca_daemon.lua`
- Modify: `src/3_planning/amm/modules/mission_engine.lua`
- Modify: `src/3_planning/amm/modules/network_manager.lua`
- Modify: `src/3_planning/amm/main.lua`
- Test: `tests/1_control/vas/test_vas_core.lua`
- Test: `tests/1_control/tca/test_tca_core.lua`
- Test: `tests/3_planning/amm/test_mission_fsm.lua`

**Interfaces:**
- Consumes: `TASK-136` `fsm.contraptionState`, `fsm.recalibrationRequired`.
- Produces:
  - `state_machine.evaluate_pbit(fsm, pbitCtx) -> table` (5 checks: `busRtt`, `inertiaProfile`, `actuatorWiggle`, `energyFuel`, `channelConflict`)
  - `core_daemon.run_pbit(state, reqPayload) -> table`
  - `tca_daemon.handle_calib_pulse(inst, pkt)` supporting `pbitWiggle == true` with `pulseRatio <= 0.04`
  - `amm/network_manager:send_pbit_req(payload)`
  - `mission_engine:set_pbit_report(report)` & `PBIT_TAKEOFF_INTERLOCK` on `ACT_TKL_*` takeoff primitives

- [x] **Step 1: Write failing unit tests in `tests/1_control/vas/test_vas_core.lua`, `tests/1_control/tca/test_tca_core.lua`, and `tests/3_planning/amm/test_mission_fsm.lua` covering 5-stage PBIT PASS/WARN/FAIL evaluation, `< 5%` TCA wiggle + cut-off, and AMM takeoff interlock**
- [x] **Step 2: Run targeted unit tests to verify they fail**

Run:
```powershell
python tools/run_unit_tests.py --target 1_control/vas --target 1_control/tca --target 3_planning/amm --clean-orphans
```
Expected: FAIL on newly added `TASK-131` assertions.

- [x] **Step 3: Implement `TASK-131` across `VAS`, `TCA`, and `AMM`**
- [x] **Step 4: Run targeted unit tests to verify they pass**

Run:
```powershell
python tools/run_unit_tests.py --target 1_control/vas --target 1_control/tca --target 3_planning/amm --clean-orphans
```
Expected: PASS.

---

### Task 4: `TASK-128` Implementation — GPS Constellation Health & Chunk Border DR Hold-over Guard

**Files:**
- Modify: `src/0_infra/gps/modules/protocol.lua`
- Modify: `src/0_infra/gps/modules/trilateration.lua`
- Modify: `src/0_infra/gps/modules/client_core.lua`
- Modify: `src/1_control/vas/modules/sensor_pipeline.lua`
- Modify: `src/1_control/vas/modules/state_machine.lua`
- Modify: `src/2_guidance/fcp/modules/state_propagator.lua`
- Modify: `src/2_guidance/fcp/modules/outer_loop_controller.lua`
- Modify: `src/2_guidance/fcp/main.lua`
- Modify: `src/3_planning/amm/modules/nav_engine.lua`
- Test: `tests/0_infra/gps/test_gps_core.lua`
- Test: `tests/1_control/vas/test_vas_core.lua`
- Test: `tests/2_guidance/fcp/test_state_propagator.lua`
- Test: `tests/3_planning/amm/test_nav_engine.lua`

**Interfaces:**
- Produces:
  - `protocol.MSG_NAV_QUALITY`, `protocol.classifyNavQuality(hdop, satelliteCount, consecutiveFailures)`, `protocol.buildNavQuality(domainId, seq, fields, nowMs)`
  - `client_core:recordTimeout()`, `client_core:getNavQuality()`
  - `sensor_pipeline.step_gps_dr(state, gpsSample, comState, dt, nowMs)` (`1500ms` DR hold-over, chunk-border spike blending, `HOLD_LEVEL`)
  - `state_propagator` `drHoldoverActive`, `holdLevelActive`, `chunkBlendTicks`, and `outer_loop_controller` `HOLD_LEVEL` handling + `2.0s` bumpless recovery

- [x] **Step 1: Write failing unit tests in `tests/0_infra/gps/test_gps_core.lua`, `tests/1_control/vas/test_vas_core.lua`, `tests/2_guidance/fcp/test_state_propagator.lua`, and `tests/3_planning/amm/test_nav_engine.lua` covering `MSG_NAV_QUALITY` classification/validation, `<= 1.5s` DR hold-over, `> 1.5s` `HOLD_LEVEL`, and chunk-border recovery blending**
- [x] **Step 2: Run targeted unit tests to verify they fail**

Run:
```powershell
python tools/run_unit_tests.py --target 0_infra/gps --target 1_control/vas --target 2_guidance/fcp --target 3_planning/amm --clean-orphans
```
Expected: FAIL on newly added `TASK-128` assertions.

- [x] **Step 3: Implement `TASK-128` across `GPS`, `VAS`, `FCP`, and `AMM`**
- [x] **Step 4: Run targeted unit tests to verify they pass**

Run:
```powershell
python tools/run_unit_tests.py --target 0_infra/gps --target 1_control/vas --target 2_guidance/fcp --target 3_planning/amm --clean-orphans
```
Expected: PASS.

---

### Task 5: Multi-Node E2E Verification, Spec Promotion (`Implemented`), & Context Sync

**Files:**
- Modify: `tests/e2e/test_e2e_hangar_alignment.lua`
- Modify: `tests/e2e/test_e2e_3node_se3_closed_loop.lua`
- Modify: `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`
- Modify: `tools/verify_spec_status.py`
- Modify: `TASK.md`
- Modify: `GEMINI.md`
- Modify: `.agent/memory/workspace-root.md`

- [x] **Step 1: Add E2E scenarios in `tests/e2e/test_e2e_hangar_alignment.lua` and `tests/e2e/test_e2e_3node_se3_closed_loop.lua` exercising `TASK-136` (`peripheralManifest`), `TASK-131` (`MSG_PBIT_REQ`/`MSG_PBIT_REPORT` + takeoff interlock), and `TASK-128` (`<= 1.5s` DR hold-over, `> 1.5s` `HOLD_LEVEL`, and chunk-border recovery)**
- [x] **Step 2: Promote all 6 modified specifications (`ALIGNMENT v2.9.0`, `VAS v1.25.0`, `TCA v1.14.0`, `AMM v2.6.0`, `GPS v2.4.0`, `FCP v2.5.0`) to `Implemented` (`2026-11-18`) and restore `tools/verify_spec_status.py` (`14 Implemented, 4 Approved`)**
- [x] **Step 3: Sync `TASK.md` (archive `TASK-136`, `TASK-131`, `TASK-128`, cap at 10), `GEMINI.md` (`<= 80` lines), and `.agent/memory/workspace-root.md`**
- [x] **Step 4: Run full verification suite and commit**

Run:
```powershell
python tools/validate_lua_syntax.py; if ($?) { python tools/verify_contracts.py }; if ($?) { python tools/verify_runtime_wiring.py }; if ($?) { python tools/verify_manifest_sync.py --strict-gdrive-packages }; if ($?) { python tools/verify_all_specs.py --check-readmes }; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/run_boot_smoke.py --clean-orphans }; if ($?) { python tools/run_unit_tests.py --require-tests --clean-orphans }; if ($?) { python tools/run_e2e_tests.py --clean-orphans }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }; if ($?) { python tools/verify_context_docs.py }
```
Expected: All commands exit `0` with `0` errors / `0` violations / `0` findings.
