# TASK-014: 전수 감사 3대 사각지대 방지 가드레일 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Audit_Report_1_11142026.md`의 3대 사각지대(사양서 SSOT 분열, 계층 간 와이어 계약 불일치, 미배선 런타임 경로)를 `.py` 외부 검증기와 CraftOS-PC 실부팅/패킷 검증으로 차단하고 `.agent/` 작업 게이트를 동기화한다.

**Architecture:** `config/protocol_contracts.json`을 기계 판독형 프로토콜 계약 SSOT로 신설하고, `tools/verify_contracts.py`가 16개 활성 사양서·`src/` 정적 코드·E2E 버스 패킷 캡처를 단일 정본 기준으로 교차 검증한다. 별도로 `tools/verify_runtime_wiring.py`(정적 도달성·미사용 임포트)와 `tools/run_boot_smoke.py`(10개 활성 `main.lua` CraftOS-PC 실부팅 스모크)로 미배선 경로를 차단한다.

**Tech Stack:** Python 3.12 (`unittest`, `json`, `re`, `pathlib`), CraftOS-PC Console + Lua 5.2 (`virtual_bus.lua`, `node_sandbox.lua`).

**Spec:** [2026-11-14-audit-prevention-guardrails-design.md](../specs/2026-11-14-audit-prevention-guardrails-design.md)

## Global Constraints

- `src/<layer>/<name>/` 간 공용 `.lua` 모듈 직접 참조 금지 (유일한 예외는 `/lib/avionics_sensors.lua`).
- `src/1_control/asa/**` 및 `tests/1_control/asa/**`는 `TASK-105` 재개 전까지 `0 diff` 동결 유지 (`--include-deferred` 플래그 시에만 검사 대상 포함).
- `virtual_bus.lua` 기존 공개 API(`create_bus`, `create_modem`, `step`, `find_packets`, `clear_log`) 하위 호환 100% 유지.
- `Draft` 상태 사양서(`FDR_PROGRAM_SPECIFICATION.md` 등)는 SSOT 교차 검증 대상에서 제외하고, `verify_spec_status.py`에 등록된 16개 활성 사양서만 검사한다.
- `.agent/hooks/context_doc_guard.py`는 기존 R1~R8 경량 검사만 유지한다(CraftOS-PC 또는 무거운 AST 스캔 추가 금지).
- 과장 표현(`100% 보장`, `무결점`, `원천 차단` 등)을 코드, 주석, 문서, 출력 메시지에 작성하지 않는다.

## Review Focus

- **Revision History / `[DEPRECATED]` 오탐 함정**: 사양서의 `### Revision History` 테이블이나 `[DEPRECATED]` 배지가 명시된 라인/테이블 행에는 구형 패킷명(`MSG_REBIND_ACK`, `Base+6`, `1000ms` 등)이 정당하게 기록되므로, 이를 위반으로 오탐하지 않고 본문 비폐기 맥락에서만 엄격히 차단해야 한다.
- **Lua 주석·문자열 내 이중키 폴백 오탐**: `x or y` 일반 논리 연산이나 주석 속 예시 코드가 `payload.new or payload.old` Zero-Fallback 위반으로 잘못 검출되지 않도록, 문자열/주석 제거 및 테이블 필드/설정 키 패턴(`ident.keyA or ident.keyB`)에만 정밀 매칭해야 한다.
- **`virtual_bus` 다중 버스 및 `clear_log` 시 캡처 손실**: 단일 E2E 테스트 파일 안에서 `virtual_bus.create_bus()`를 여러 번 호출하거나 `bus:clear_log()`를 호출해도 `_G.__VIRTUAL_BUS_PACKET_LOG`는 전체 E2E 세션 패킷을 유실 없이 누적해야 한다.
- **Windows / CraftOS-PC 경로 구분자 및 모뎀/모니터 부팅 블로킹**: `installer`, `tca`, `landing_pad`, `gps` 등 일부 `main.lua`는 기본 `config.json` 부재 시 대화형 셋업 마법사나 `http` 다운로드로 진입해 스모크가 멈출 수 있으므로, 스모크 러너는 서브시스템별 격리 스테이징과 최소 비대화형 `config`/모의 주변기기를 주입해야 한다.
- **Windows PowerShell 5.1 셸 제약**: 검증 명령 예시와 테스트 실행은 `&&` 대신 `; if ($?) { ... }` 또는 개별 명령으로 실행 가능해야 한다.

---

### Task 1: `config/protocol_contracts.json` SSOT 스키마 구축 및 로더 검증

**Files:**
- Create: `config/protocol_contracts.json`
- Create: `tools/verify_contracts.py` (스키마 로드 및 기본 CLI 뼈대)
- Test: `tests/harness/test_verify_contracts.py`

**Interfaces:**
- Consumes: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`, `tools/verify_spec_status.py` (`TARGET_IMPLEMENTED`, `TARGET_APPROVED`)
- Produces:
  - `config/protocol_contracts.json` (`envelope`, `channels`, `interfaces[I-1..I-12]`, `missionSchema`, `deferredSubsystems`)
  - `tools/verify_contracts.py`: `load_contracts(contracts_path: Path) -> dict[str, Any]`

- [ ] **Step 1: Write the failing test**

Create `tests/harness/test_verify_contracts.py` with schema loader and structural validation tests:

```python
import json
import unittest
from pathlib import Path
from tools.verify_contracts import load_contracts

WORKSPACE_ROOT = Path(__file__).resolve().parents[2]

class TestProtocolContractsSchema(unittest.TestCase):
    def test_load_contracts_contains_all_12_interfaces_and_envelope(self) -> None:
        contracts = load_contracts(WORKSPACE_ROOT / "config" / "protocol_contracts.json")
        self.assertEqual(contracts["envelope"]["ver"], "1.9.5")
        self.assertEqual(
            contracts["envelope"]["requiredKeys"],
            ["ver", "domainId", "seq", "type", "time", "payload"],
        )
        ids = {iface["id"] for iface in contracts["interfaces"]}
        self.assertEqual(ids, {f"I-{i}" for i in range(1, 13)})
        self.assertIn("src/1_control/asa", contracts["deferredSubsystems"])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m unittest tests.harness.test_verify_contracts.TestProtocolContractsSchema -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'tools.verify_contracts'`

- [ ] **Step 3: Author `config/protocol_contracts.json` and `load_contracts` in `tools/verify_contracts.py`**

1. Extract exact canonical contracts from `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.30.0`), `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.15.0`), and active subsystem specs (`I-1`..`I-12`):
   - `I-1` (`Base+2`): `MSG_FLIGHT_TELEMETRY` (`requiredKeys`: `attitude`, `angularRates`, `dynamics`, `fuel`, `dynamicLoad`, `controlState`, `activeSource`, `sensorOk`, `sensorHealth`, `actuatorHealth`; `numericBounds`: `fuel: [0.0, 1.0]`, `dynamicLoad: [0.0, 1.0]`).
   - `I-2` (`Base+1`): `MSG_ATTITUDE_CMD` (`QUATERNION_RATE`, `RATE_COMMAND`; `deprecatedModes`: `["ATTITUDE_ANGLE"]`), `MSG_EMERGENCY_OVERRIDE`, `MSG_EMERGENCY_ALERT`.
   - `I-3` (`Base+10`): `MSG_THRUST_CMD`, `MSG_ACTUATOR_STATUS`, `MSG_ACTUATOR_DISCOVER_REQ`, `MSG_ACTUATOR_DISCOVER_ACK` (`deprecatedOffsets`: `[6]`).
   - `I-4` (`Base+0`, `Base_hangar+0/+1/+3`): `MSG_CALIBRATION_INIT`, `MSG_CALIBRATION_INIT_ACK` (`hardwareUuid`, `airframeType`), `MSG_CALIB_BAY_BIND` (`baseHangarChannel`), `MSG_CALIB_START`, `MSG_CALIB_PULSE`, `MSG_PROFILE_SYNC` (`discoveredSurfaces`, `saveProfile`), `MSG_CALIB_ACK`, `MSG_CALIBRATION_CLOSE`, `MSG_CALIBRATION_CLOSE_ACK`.
   - `I-5` (`50001..50004`, `Base_sec+0/+1/+2/+5/+10+Idx`): `MSG_FACILITY_BEACON` (`totalDockingArms`, `freeDockingArms`), `MSG_ATC_FACILITY_UPDATE` (`enums.status`: `["FREE", "RESERVED", "OCCUPIED", "MAINTENANCE"]`), `MSG_FACILITY_STATIC_GUIDE`, `MSG_FACILITY_DYNAMIC_GUIDE` (`approachDirection`, `deckStatus`, `landingPermitted`, `abortAlert`), `MSG_GAC_DEPARTURE_CLEARANCE`, `MSG_GAC_ABORT_CLEAR`, `timeoutsMs`: `{"slotTimeoutMs": 120000}`.
   - `I-6` (`Base+0`, `Base+3`): `MSG_OPERATOR_CMD`, `MSG_MISSION_CMD`, `MSG_MISSION_ACK`, `MSG_MFD_STATE` (`controlState`, `sensorOk`, `allOk`).
   - `I-7` (`60001/60002`, `Base+5`, `Base_sec+5`): `MSG_GPS_REQUEST`, `MSG_GPS_RESPONSE`.
   - `I-8` (`50000`): `MSG_BLOCK_REQUEST`, `MSG_BLOCK_ASSIGN`.
   - `I-9` (`Base+0`, `Base+4`, `Base+1`, `Base+10`, `Base+11`): `MSG_CHANNEL_PROBE`, `MSG_CHANNEL_PROBE_ACK`, `MSG_CHANNEL_REBIND` (`transactionId`, `action`, `oldBaseChannel`, `newBaseChannel`, `bandwidth`), `MSG_CHANNEL_REBIND_ACK` (`transactionId`, `status` in `["READY", "COMMITTED", "ROLLED_BACK", "FAILED"]`, `deprecatedPacketTypes`: `["MSG_REBIND_ACK"]`, `deprecatedPayloadKeys`: `["phase", "oldBase", "newBase"]`, `timeoutsMs`: `{"rebindWatchdogMs": 500}`).
   - `I-10` (`Base+11`): `MSG_AERO_CMD` (`numericBounds` normalized `[-1.0, 1.0]` / `[0.0, 1.0]`, `dynamicPressureFactor`), `MSG_AERO_STATUS` (`interactionMode`, `appliedDeflection`, `enums.status`: `["NOMINAL", "DEGRADED", "TOTAL_LOSS"]`, `deprecatedPacketTypes`: `["MSG_SURFACE_CMD", "MSG_SURFACE_STATUS"]`, `deprecatedPayloadKeys`: `["mode", "appliedDeg", "API_NOMINAL", "API_TOTAL_LOSS"]`, `deprecatedOffsets`: `[7]`).
   - `I-11` (`Base+20..29`): `MSG_PAYLOAD_REQ`, `MSG_PAYLOAD_ACK`.
   - `I-12` (`Base+4`): `MSG_TRAJECTORY_SETPOINT`, `MSG_OUTER_LOOP_STATUS`.
   - `missionSchema`: `version = "2.0.0"`, 36 `ACT_*`, 6 `DEC_*`, 3 `MAC_*`, 14 `CONDITION_TYPES`, `deprecatedActions` (`["ORBIT", "PATROL", "PAYLOAD_ACTION", "FLY_TO"]`).
2. Implement `load_contracts(contracts_path: Path) -> dict[str, Any]` in `tools/verify_contracts.py` validating required top-level keys (`schemaVersion`, `envelope`, `channels`, `interfaces`, `missionSchema`, `deferredSubsystems`).

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m unittest tests.harness.test_verify_contracts.TestProtocolContractsSchema -v`
Expected: PASS (`Ran 1 test ... OK`)

---

### Task 2: `tools/verify_contracts.py` — 사양서 SSOT 대조 및 정적 Zero-Fallback 린터 구현

**Files:**
- Modify: `tools/verify_contracts.py`
- Modify: `tests/harness/test_verify_contracts.py`

**Interfaces:**
- Consumes: `load_contracts` (`tools/verify_contracts.py`), `SPEC_FILES` (`tools/verify_all_specs.py`), `strip_lua_comments_and_strings` (`harness/unit/static_guard.py`)
- Produces:
  - `verify_specs_against_contracts(repo_root: Path, contracts: dict[str, Any]) -> list[str]`
  - `verify_code_against_contracts(repo_root: Path, contracts: dict[str, Any], include_deferred: bool = False) -> list[str]`
  - CLI `python tools/verify_contracts.py [--specs-only | --code-only] [--include-deferred]` returning Exit 0 on 0 errors.

- [ ] **Step 1: Write failing tests for spec SSOT drift & Lua dual-key fallback detection**

Append to `tests/harness/test_verify_contracts.py`:
- `test_revision_history_and_deprecated_lines_do_not_trigger_false_positives`: synthetic spec fixture containing `MSG_REBIND_ACK` inside `### Revision History` and on a `[DEPRECATED]` line passes; unannotated `MSG_REBIND_ACK` in body fails.
- `test_missing_canonical_packet_in_spec_fails`: synthetic spec fixture omitting `MSG_CHANNEL_REBIND_ACK` fails.
- `test_static_code_detects_dual_key_fallback_and_deprecated_packet_literal`: synthetic Lua fixture with `p.oldBase or p.newBaseChannel` and `"MSG_REBIND_ACK"` fails; clean single-key `p.newBaseChannel` passes; deferred `src/1_control/asa/` skipped unless `include_deferred=True`.
- `test_live_repo_specs_and_code_pass`: runs `verify_specs_against_contracts` and `verify_code_against_contracts` against `WORKSPACE_ROOT` and asserts 0 errors.

- [ ] **Step 2: Run tests to verify they fail**

Run: `python -m unittest tests.harness.test_verify_contracts -v`
Expected: FAIL (`ImportError: cannot import name 'verify_specs_against_contracts'`)

- [ ] **Step 3: Implement `verify_specs_against_contracts`, `verify_code_against_contracts`, and CLI `main()` in `tools/verify_contracts.py`**

Key behaviors:
- `strip_revision_history(markdown: str) -> str`: strips lines strictly inside `### Revision History` table before checking body regression/deprecated tokens.
- For each line outside `Revision History`, if a `deprecatedPacketTypes` or `deprecatedPayloadKeys` token (from `specContracts` / `interfaces` participating in that spec) appears as a standalone identifier/backticked token and the line does NOT contain `DEPRECATED` or `구 ` / `deprecated`, record an error with `file:line`.
- For each active spec, check all `interfaces` whose `specs` list includes that file (and `Master ICD` / `Diagram` cover all `I-1`..`I-12`): every canonical packet type and `specRequiredTokens` (key field/enum/timeout tokens configured per interface) must appear in the spec.
- For `verify_code_against_contracts`:
  - Walk active `src/<layer>/<name>/` `.lua` files (`deferredSubsystems` excluded unless `include_deferred=True`) and `src/**/config/*.json`.
  - Detect deprecated packet string literals (`MSG_REBIND_ACK`, `MSG_SURFACE_CMD`, `MSG_SURFACE_STATUS`, etc.), dual-key `or` fallback regex (`\b([a-zA-Z_][a-zA-Z0-9_]*)\s*\.\s*([a-zA-Z_][a-zA-Z0-9_]*)\s+or\s+\1\s*\.\s*([a-zA-Z_][a-zA-Z0-9_]*)` where one key matches a known payload/config/deprecated key or differing alias), and invalid/legacy config JSON keys (`surfaceMix`, `aeroEnvelope`, `navStaleEpochMs`).

- [ ] **Step 4: Run tests and live CLI to verify they pass**

Run: `python -m unittest tests.harness.test_verify_contracts -v`
Expected: PASS
Run: `python tools/verify_contracts.py`
Expected: Exit 0 (`0 Errors`)

---

### Task 3: E2E 실전 패킷 캡처 계약 검증 연동 (`virtual_bus.lua` + `run_e2e_tests.py`)

**Files:**
- Modify: `harness/simulation/virtual_bus.lua`
- Modify: `tools/run_e2e_tests.py`
- Modify: `tools/verify_contracts.py` (`validate_captured_packets`)
- Create: `tests/harness/test_e2e_contract_validation.py`

**Interfaces:**
- Consumes: `load_contracts` (`tools/verify_contracts.py`), `virtual_bus.lua` `bus:deliver()`
- Produces:
  - `tools/verify_contracts.py`: `validate_captured_packets(packets: list[dict[str, Any]], contracts: dict[str, Any]) -> list[str]`
  - `harness/simulation/virtual_bus.lua`: appends `{ suite = _G.__ACTIVE_E2E_SUITE, channel, replyChannel, from, time, payload }` to `_G.__VIRTUAL_BUS_PACKET_LOG` when initialized as a table.
  - `tools/run_e2e_tests.py`: exports `captured_packets` from guest `result.json`, runs `validate_captured_packets` unless `--skip-contract-check`, adds `contract_errors` to `report_payload`, returns Exit 1 if `len(contract_errors) > 0`.

- [ ] **Step 1: Write failing tests for packet batch validation**

Create `tests/harness/test_e2e_contract_validation.py`:
- `test_valid_telemetry_and_rebind_packets_pass`
- `test_missing_envelope_field_or_wrong_version_fails`
- `test_deprecated_packet_type_or_payload_key_fails` (`MSG_REBIND_ACK`, `oldBase`, `appliedDeg`, `API_NOMINAL`)
- `test_out_of_bounds_numeric_or_invalid_enum_fails` (`fuel = 1.5`, `status = "UNKNOWN_STATE"` on `MSG_CHANNEL_REBIND_ACK`)
- `test_virtual_bus_lua_preserves_existing_api_and_populates_global_capture` (can also be verified by existing `test_simulation_core.py` + `run_e2e_tests.py`).

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m unittest tests.harness.test_e2e_contract_validation -v`
Expected: FAIL (`ImportError: cannot import name 'validate_captured_packets'`)

- [ ] **Step 3: Implement `validate_captured_packets` in `tools/verify_contracts.py`, capture hook in `harness/simulation/virtual_bus.lua`, and contract gate in `tools/run_e2e_tests.py`**

1. In `tools/verify_contracts.py`, implement `validate_captured_packets(packets, contracts) -> list[str]`:
   - Skip raw non-table test noise only if explicitly marked non-UAFS; for all dict payloads with `type` or matching a known channel offset (`baseMin..baseMax` modulo `40`, or global channels `50000..50004`, `60001..60004`, `101..200`), validate envelope (`ver == "1.9.5"`, `domainId` non-empty str, `seq` int/float, `type` str, `time` int/float, `payload` dict).
   - Match packet `type` (or deprecated type) against `interfaces`: fail on `deprecatedPacketTypes`, `deprecatedPayloadKeys`, missing `requiredKeys`, invalid `enums`, and out-of-range `numericBounds`.
2. In `harness/simulation/virtual_bus.lua`:
   - Inside `bus:deliver()`, when `type(_G.__VIRTUAL_BUS_PACKET_LOG) == "table"`, append `{ suite = _G.__ACTIVE_E2E_SUITE, channel = msg.channel, replyChannel = msg.replyChannel, from = msg.from, time = msg.time, payload = msg.payload }`.
3. In `tools/run_e2e_tests.py`:
   - Add `--skip-contract-check` flag (default `False`).
   - Initialize `_G.__VIRTUAL_BUS_PACKET_LOG = {}` in `startup_script`, set `_G.__ACTIVE_E2E_SUITE = tf` before executing each E2E file, and pass `captured_packets = _G.__VIRTUAL_BUS_PACKET_LOG` into `R.write_result(...)`.
   - On host, call `validate_captured_packets(captured_packets, load_contracts(...))`; print `[FAIL] Wire contract violations` and fail `run_e2e_tests.py` (`exit_code = 1`) if any violations are found.

- [ ] **Step 4: Run unit tests and full E2E suite to verify live compatibility**

Run: `python -m unittest tests.harness.test_e2e_contract_validation tests.harness.test_simulation_core tests.harness.test_e2e_runner -v`
Expected: PASS
Run: `python tools/run_e2e_tests.py --clean-orphans`
Expected: Exit 0 (`13/13 PASS` + contract check `0 violations` — fix any synthetic test packet in `tests/e2e/` only if an actual test fixture emitted an intentionally malformed test packet, in which case tag only negative-test fixtures or verify exact E2E output!).

---

### Task 4: `tools/verify_runtime_wiring.py` — 정적 도달성, 고아 모듈, 깨진 `require` 및 미사용 임포트 검출

**Files:**
- Create: `tools/verify_runtime_wiring.py`
- Create: `tests/harness/test_verify_runtime_wiring.py`

**Interfaces:**
- Consumes: `src/<layer>/<name>/main.lua` trees, `src/0_development/installer/modules/startup_generator.lua`
- Produces:
  - `analyze_subsystem_wiring(subsystem_dir: Path, repo_root: Path) -> list[WiringViolation]`
  - `verify_all_wiring(repo_root: Path, include_deferred: bool = False) -> list[WiringViolation]`
  - CLI `python tools/verify_runtime_wiring.py [--include-deferred] [--json]` returning Exit 0 on 0 errors.

- [ ] **Step 1: Write failing tests for broken require, orphan module, and dead import detection**

Create `tests/harness/test_verify_runtime_wiring.py`:
- `test_detects_broken_require_and_missing_modules_prefix`: temp subsystem where `main.lua` calls `require("nonexistent_mod")` fails with `BROKEN_REQUIRE`.
- `test_detects_orphan_module_not_reachable_from_main`: temp subsystem with `modules/dead_helper.lua` never required by `main.lua` or transitive deps fails with `ORPHAN_MODULE`; `modules/node_sim.lua` (`node_*.lua`) is ignored.
- `test_detects_unused_require_binding_in_main`: temp `main.lua` with `local sentinel = require("modules.sentinel")` where `sentinel` is never referenced again fails with `DEAD_IMPORT`.
- `test_live_repo_runtime_wiring_passes`: runs `verify_all_wiring(WORKSPACE_ROOT)` and asserts 0 violations across the 10 active subsystems.

- [ ] **Step 2: Run tests to verify they fail**

Run: `python -m unittest tests.harness.test_verify_runtime_wiring -v`
Expected: FAIL (`ModuleNotFoundError: No module named 'tools.verify_runtime_wiring'`)

- [ ] **Step 3: Implement `tools/verify_runtime_wiring.py`**

Key logic:
- Discover all `src/<layer>/<name>/main.lua` (exclude `deferredSubsystems` `src/1_control/asa` unless `include_deferred=True`).
- Strip Lua comments before scanning (`strip_lua_comments_and_strings`).
- BFS/DFS from `main.lua`:
  - Extract `require("mod")` / `require 'mod'`, `dofile("file")`, `loadfile("file")`, `shell.run("file", ...)` (and `pcall(require, "mod")`).
  - Resolve target relative to subsystem root, `modules/`, `hal/`, `tools/` (skip `/lib/avionics_sensors` / `avionics_sensors` which comes from `/lib/`).
  - If `main.lua` or transitive file cannot resolve target to an existing `.lua` file inside the subsystem, emit `BROKEN_REQUIRE`.
  - Check `package.path` safety: if `main.lua` uses bare `require("foo")` for a file in `modules/foo.lua` without either `main.lua` modifying `package.path` OR `startup_generator.lua` injecting `modules/?.lua` (note: flag warning/error only if neither `main.lua` nor `startup_generator.lua` covers it).
  - Any `.lua` file in subsystem (not `node_*.lua` and not `tests/`) unreachable from `main.lua` emits `ORPHAN_MODULE`.
  - In `main.lua`, for each `local <var> = require(...)`, count occurrences of `\b<var>\b` outside that declaration line; if `0`, emit `DEAD_IMPORT` (except `_`).

- [ ] **Step 4: Run tests and live CLI to verify they pass**

Run: `python -m unittest tests.harness.test_verify_runtime_wiring -v`
Expected: PASS
Run: `python tools/verify_runtime_wiring.py`
Expected: Exit 0 (`0 violations` across 10 active subsystems — if any real dead import/orphan exists in `src/`, report it cleanly in task output or confirm against `Audit_Report_1` cleanup!).

---

### Task 5: `tools/run_boot_smoke.py` — 10개 활성 `main.lua` CraftOS-PC 실부팅 스모크 러너

**Files:**
- Create: `tools/run_boot_smoke.py`
- Create: `tests/harness/test_boot_smoke_runner.py`
- Modify: `tests/harness/test_tools_integrity.py`

**Interfaces:**
- Consumes: `harness/unit/config.py` (`resolve_craftos_paths`), `harness/unit/session.py` (`EphemeralCraftOSSession`), `src/0_development/sensors/*.lua`
- Produces:
  - `tools/run_boot_smoke.py`: `run_boot_smoke_cli(argv: list[str] | None = None, workspace_root: Path | None = None) -> tuple[int, dict[str, Any]]`
  - Expected channels & boot fixtures for 10 active entrypoints (`alignment`, `installer`, `gps`, `gac`, `gcs`, `landing_pad`, `tca`, `vas`, `fcp`, `amm`).

- [ ] **Step 1: Write failing tests for boot smoke runner CLI & config staging**

Create `tests/harness/test_boot_smoke_runner.py`:
- `test_build_smoke_targets_covers_10_active_subsystems_and_skips_deferred_asa`
- `test_build_smoke_targets_includes_asa_when_include_deferred`
- `test_smoke_runner_reports_failure_on_lua_boot_error` (mocked `EphemeralCraftOSSession` returning failed guest payload).

- [ ] **Step 2: Run tests to verify they fail**

Run: `python -m unittest tests.harness.test_boot_smoke_runner -v`
Expected: FAIL (`ModuleNotFoundError: No module named 'tools.run_boot_smoke'`)

- [ ] **Step 3: Implement `tools/run_boot_smoke.py` and register tools in `tests/harness/test_tools_integrity.py`**

Key design in `tools/run_boot_smoke.py`:
- Stage each target subsystem cleanly in its own CraftOS-PC computer directory (or sequential isolated sessions / computers inside `EphemeralCraftOSSession`) mirroring deployed layout:
  - Copy subsystem files (`main.lua`, `modules/`, `hal/`, `config/`, `*.lua`) to `/`.
  - Copy `src/0_development/sensors/*.lua` (except `main.lua`) to `/lib/`.
  - Pre-stage minimal non-interactive `config.json` / `/gac/config.json` / `/landing_pad/config.json` when missing so daemons do not enter blocking interactive wizards (`tca_setup`, etc.), plus mock peripherals (`modem` tracking `opened` channels, `monitor`, `redstone`, `velocity_sensor`, `altitude_sensor`, `gimbal_sensor`, `ion_thruster` / `thruster`) and mock `http` (for `installer` safe non-network exit).
  - Run `main.lua` under `parallel.waitForAny` with a `0.35s` watchdog timer + `os.queueEvent("terminate")` so real `os.pullEventRaw()` loops execute ~7 ticks and shut down cleanly.
  - Assert zero boot errors and verify opened modem channels against expected `expectedChannels` per subsystem (`gac`: `[50001, 50002, 50004, 50201, 50202]`, `landing_pad`: `[50202, 50206, 50211]`, `gcs`: `[50000]`, `tca`: `[10010]`, `fcp`: `[10004, 10002, 10001]`, `vas`: `[10001, 10010, 10011]`, `amm`: `[10000, 10002, 10003, 10004, 10005]`, `gps`: `[60001]`, `alignment`: `[101, 102, 103, 104, 10000]`).
- Register `verify_contracts.py`, `verify_runtime_wiring.py`, `run_boot_smoke.py` in `tests/harness/test_tools_integrity.py`.

- [ ] **Step 4: Run harness tests and live CraftOS-PC boot smoke**

Run: `python -m unittest discover -s tests/harness -p "test_*.py"`
Expected: PASS (all harness tests including new integrity & unit tests)
Run: `python tools/run_boot_smoke.py --clean-orphans`
Expected: Exit 0 (`10/10 PASS`)

---

### Task 6: `.agent/` 작업 컨텍스트 게이트 및 `TASK.md` / `GEMINI.md` / 메모리 동기화

**Files:**
- Modify: `.agent/rules/skill-workflows.md`
- Modify: `.agent/skills/specification-lifecycle-manager/SKILL.md`
- Modify: `.agent/skills/verification-before-completion/SKILL.md`
- Modify: `TASK.md`
- Modify: `.agent/memory/workspace-root.md`
- Modify: `GEMINI.md`

**Interfaces:**
- Consumes: CLI commands from Tasks 2–5 (`tools/verify_contracts.py`, `tools/verify_runtime_wiring.py`, `tools/run_boot_smoke.py`, `tools/run_e2e_tests.py`)
- Produces: Updated agent workflow rules/skills and context docs passing `tools/verify_context_docs.py`.

- [ ] **Step 1: Update `.agent/` workflow rules & skills**

1. In `.agent/rules/skill-workflows.md`:
   - Under `문서 유형별 관할 스킬 분리` & `사양서 생명주기 가드레일`: require synchronizing `config/protocol_contracts.json` and running `python tools/verify_contracts.py --specs-only` whenever active protocol/packet/channel/enum specs change.
   - Under `작업 완료 보고 및 마일스톤 인계`: add `python tools/verify_contracts.py`, `python tools/verify_runtime_wiring.py`, and `python tools/run_boot_smoke.py --clean-orphans` to mandatory verification commands alongside `run_unit_tests.py` and `run_e2e_tests.py`.
2. In `.agent/skills/specification-lifecycle-manager/SKILL.md`: add `config/protocol_contracts.json` update & `python tools/verify_contracts.py --specs-only` check to Case B / Option 2 Phase 1 workflow.
3. In `.agent/skills/verification-before-completion/SKILL.md`: add the 3 new verification commands to the pre-completion evidence gate.

- [ ] **Step 2: Synchronize `TASK.md`, `.agent/memory/workspace-root.md`, and `GEMINI.md` (`<= 80 lines`)**

Mark `TASK-014` `[x]` in `TASK.md`, append `TASK-014` entry to `.agent/memory/workspace-root.md`, and update `GEMINI.md` Section 1 & Section 3 (`Standard Commands`) while keeping `GEMINI.md <= 80` lines.

- [ ] **Step 3: Final sequential verification suite**

Run sequentially:
```powershell
python tools/verify_context_docs.py
if ($?) { python tools/verify_all_specs.py --check-readmes }
if ($?) { python tools/verify_spec_status.py }
if ($?) { python tools/verify_manifest_sync.py }
if ($?) { python tools/verify_contracts.py }
if ($?) { python tools/verify_runtime_wiring.py }
if ($?) { python tools/validate_lua_syntax.py }
if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }
if ($?) { python tools/run_unit_tests.py --require-tests --clean-orphans }
if ($?) { python tools/run_e2e_tests.py --clean-orphans }
if ($?) { python tools/run_boot_smoke.py --clean-orphans }
```
Expected: All commands Exit 0 with zero errors/warnings.
