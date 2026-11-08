# 구버전 명칭(UAP/SAS/WAP) 전면 척결 및 회귀 방지 테스트 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 비행 제어 및 공력 구동계 관련 구버전 잔존 명칭(`UAP`, `SAS`, `WAP`)을 전면 척결하고, 자동화 회귀 방지 테스트 슈트(`test_terminology_guard.py`, `verify_all_specs.py` Rule 8)를 구축하여 소급 전면 삭제(Zero-Tolerance Purge) 및 풀 마이그레이션(Full Migration)을 달성한다.

**Architecture:** 
1. **작업 환경 격리**: Git 워크트리 `.worktrees/task-legacy-terminology` 및 독립 브랜치 `task-legacy-terminology`에서 격리 수행.
2. **RED (회귀 테스트 및 정적 규칙 선행 구축)**:
   - `tests/harness/test_terminology_guard.py` 신설하여 `docs/`, `src/`, `tests/` 전역의 금지 명칭(`UAP`, `SAS`, `WAP`) 정규식 0건 단언 (소급 전면 삭제 기준).
   - `tools/verify_all_specs.py`에 규칙 8(용어 위생 검사: `Rule 8. Legacy Terminology Hygiene`)을 추가하여 14대 사양서 내 비표준 용어를 정적 검증.
3. **GREEN (런타임 코드 및 테스트 전면 개정 - Full Migration)**:
   - 파일명 개명: `actuator_adapter_wap.lua` $\to$ `actuator_adapter_asa.lua`, `node_wap.lua` $\to$ `node_asa.lua`, `node_wap_sim.lua` $\to$ `node_asa_sim.lua`.
   - 유선 패킷 스키마 `podId`: `"WAP_L"`, `"WAP_R"`, `"WAP_T"` $\to$ `"ASA_L"`, `"ASA_R"`, `"ASA_T"`.
   - 텔레메트리 헬스 키: `actuatorHealth.wap` $\to$ `actuatorHealth.asa`.
   - 변수 및 상수: `UAP_CMD_TIMEOUT_1500MS` $\to$ `FCP_CMD_TIMEOUT_1500MS`, `lastUapCmdMs` $\to$ `lastFcpCmdMs`, `wapTimeoutMs` $\to$ `asaTimeoutMs` 등 전면 치환.
4. **GREEN (사양서 13종 소급 전면 정비 - Zero-Tolerance Purge & SemVer 전이)**:
   - 과거 개정 이력표(`Revision History`) 및 폐기 안내문(`[DEPRECATED]`)에서도 단어 자체를 일체 배제하고 `구 명칭` 또는 `구 표준 명칭`으로 소급 치환.
   - 핵심 영향 4종(`ICD`, `VAS`, `FCP`, `ASA`)은 SemVer 마이너 승격 및 `Approved` 전이 후 구현 검증 통과 시 `Implemented` 환원. 단순 텍스트 정비 9종은 SemVer 패치 승격 및 기존 상태 유지.
5. **검증 및 병합 (Verification & Merge)**:
   - 단위 테스트(248/248), E2E 시뮬레이션(6/6), 돌연변이 살상률(100.0%, 20/20), 하네스 테스트(30/30), 사양서 정적 검사(100% CLEAN) 전수 검증 후 `main` 병합.

**Tech Stack:** Python 3.12 (`unittest`, `re`, `pathlib`), Lua 5.2 / CraftOS-PC Runner.

**Spec:**
- [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md)
- [SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md)
- [VAS_PROGRAM_SPECIFICATION.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md)
- [FCP_PROGRAM_SPECIFICATION.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md)
- [ASA_PROGRAM_SPECIFICATION.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md)
- [ALIGNMENT_PROGRAM_SPECIFICATION.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md)
- [GPS_PROGRAM_SPECIFICATION_AND_ICD.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md)
- [GAC_PROGRAM_SPECIFICATION_AND_ICD.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md)
- [DOCKING_ARM_SPECIFICATION_AND_ICD.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md)
- [LANDING_PAD_SPECIFICATION_AND_ICD.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md)
- [RUNWAY_SPECIFICATION_AND_ICD.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md)
- [GCS_PROGRAM_SPECIFICATION_AND_ICD.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md)
- [TCA_PROGRAM_SPECIFICATION.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md)
- [AMM_PROGRAM_SPECIFICATION.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md)

## Global Constraints

- **소급 전면 삭제 (Zero-Tolerance Purge)**: `docs/`, `src/`, `tests/`, `tools/` 전역에서 `\bUAP\b`, `\bSAS\b`, `\bWAP\b` 단어를 일체 허용하지 않는다. 과거 이력표(`Revision History`) 및 `[DEPRECATED]` 안내문에서도 단어 자체를 `구 명칭` 또는 `구 표준 명칭`으로 소급 치환한다.
- **Zero-Fallback 유선 인터페이스**: `MSG_AERO_CMD` 및 `MSG_AERO_STATUS`의 `podId`는 `"ASA_L"`, `"ASA_R"`, `"ASA_T"`만 허용하며 구 식별자 폴백을 두지 않는다.
- **하위 호환 텔레메트리 일원화**: 텔레메트리 액추에이터 헬스 테이블 키는 `actuatorHealth.asa`로 완전 단일화한다.
- **FCP 40채널 수식 잔재 정비**: `FCP_PROGRAM_SPECIFICATION.md` 내 20채널 수식(`* 20`) 및 `bandwidth = 20` 잔재를 40채널 표준(`* 40`, `bandwidth = 40`)으로 일체화한다.
- **테스트 무결성 100% 보존**: 기존 12개 타겟 단위 테스트 248건, E2E 시뮬레이션 6건, 돌연변이 살상률 100.0%, Python 하네스 테스트 전수 통과를 보존한다.

## Review Focus

1. **상태머신 전이 사유 문자열 호환성**: `state_machine.lua`의 `UAP_CMD_TIMEOUT_1500MS` $\to$ `FCP_CMD_TIMEOUT_1500MS` 변경 시 외부 테스트나 상태 검증에서 하드코딩된 문자열 의존성이 없는지 확인.
2. **E2E 및 GCS 텔레메트리 렌더러 호환성**: `actuatorHealth.asa` 키 변경 시 `tests/e2e/test_e2e_bootstrap_and_telemetry.lua` 및 GCS `fleet_tracker.lua`, `ui_renderer.lua`가 에러 없이 정상 수신·렌더링하는지 확인.
3. **ASA 단위 테스트 설정 주입**: `tests/1_control/asa/test_asa_core.lua`의 8개 테스트 픽스처 내 `podId = "WAP_L"` $\to$ `"ASA_L"` 변경 후 15/15 PASS 유지 확인.
4. **인스톨러 매니페스트 동기화**: `src/0_development/installer/modules/manifest.lua` 내 `actuator_adapter_wap.lua` $\to$ `actuator_adapter_asa.lua` 갱신 및 인스톨러 28/28 PASS 확인.
5. **정규식 단어 경계 무결성**: 한글 조사 결합(`UAP는`, `SAS의`, `WAP과`) 및 소문자 식별자(`uap`, `wap`)를 누락 없이 포착하는 정규식 `(?i)(?<![A-Za-z0-9])(uap|wap)(?![A-Za-z0-9])` 및 `(?<![A-Za-z0-9])SAS(?![A-Za-z0-9])` 검증.

---

### Task 1: 워크트리 환경 생성 및 용어 회귀 테스트 슈트 신설 (RED)

**Files:**
- Create: `tests/harness/test_terminology_guard.py`
- Test: `tests/harness/test_terminology_guard.py`

**Interfaces:**
- Consumes: `docs/system/*.md`, `docs/specs/**/*.md`, `src/**/*.lua`, `tests/**/*.lua`
- Produces: `TestTerminologyGuard` (Python `unittest.TestCase`)

- [ ] **Step 1: 작업 격리 워크트리 및 브랜치 생성**

```bash
& "C:\Program Files\Git\cmd\git.exe" worktree add .worktrees/task-legacy-terminology -b task-legacy-terminology
```

- [ ] **Step 2: 실패하는 회귀 테스트 슈트 `tests/harness/test_terminology_guard.py` 작성**

```python
from __future__ import annotations

import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


class TestTerminologyGuard(unittest.TestCase):
    UAP_PATTERN = re.compile(r'(?<![A-Za-z0-9])uap(?![A-Za-z0-9])', re.IGNORECASE)
    SAS_PATTERN = re.compile(r'(?<![A-Za-z0-9])SAS(?![A-Za-z0-9])')
    WAP_PATTERN = re.compile(r'(?<![A-Za-z0-9])wap(?![A-Za-z0-9])', re.IGNORECASE)

    def _collect_violations(self, base_dir: Path, pattern: re.Pattern, extensions: list[str]) -> list[str]:
        violations = []
        for ext in extensions:
            for p in base_dir.rglob(f'*{ext}'):
                if 'superpowers' in p.parts or '.git' in p.parts:
                    continue
                content = p.read_text(encoding='utf-8', errors='replace')
                for idx, line in enumerate(content.splitlines(), 1):
                    if pattern.search(line):
                        violations.append(f"{p.relative_to(REPO_ROOT)}:L{idx}: {line.strip()[:80]}")
        return violations

    def test_no_uap_in_entire_repository(self):
        """docs/, src/, tests/ 전역에서 UAP 잔존을 검출한다."""
        violations = []
        for folder in ['docs', 'src', 'tests']:
            d = REPO_ROOT / folder
            if d.exists():
                violations.extend(self._collect_violations(d, self.UAP_PATTERN, ['.md', '.lua', '.json']))
        self.assertEqual(violations, [], f"Found {len(violations)} UAP occurrences:\n" + "\n".join(violations[:10]))

    def test_no_sas_in_entire_repository(self):
        """docs/, src/, tests/ 전역에서 SAS 잔존을 검출한다 (소급 전면 삭제)."""
        violations = []
        for folder in ['docs', 'src', 'tests']:
            d = REPO_ROOT / folder
            if d.exists():
                violations.extend(self._collect_violations(d, self.SAS_PATTERN, ['.md', '.lua', '.json']))
        self.assertEqual(violations, [], f"Found {len(violations)} SAS occurrences:\n" + "\n".join(violations[:10]))

    def test_no_wap_in_entire_repository(self):
        """docs/, src/, tests/ 전역에서 WAP 잔존을 검출한다."""
        violations = []
        for folder in ['docs', 'src', 'tests']:
            d = REPO_ROOT / folder
            if d.exists():
                violations.extend(self._collect_violations(d, self.WAP_PATTERN, ['.md', '.lua', '.json']))
        self.assertEqual(violations, [], f"Found {len(violations)} WAP occurrences:\n" + "\n".join(violations[:10]))

    def test_no_legacy_wap_files(self):
        """src/ 및 tests/ 내에 구버전 WAP 모듈명이 남아있지 않은지 검출한다."""
        banned_filenames = {'node_wap.lua', 'actuator_adapter_wap.lua', 'node_wap_sim.lua'}
        found = []
        for folder in ['src', 'tests']:
            d = REPO_ROOT / folder
            if d.exists():
                for p in d.rglob('*.lua'):
                    if p.name in banned_filenames:
                        found.append(str(p.relative_to(REPO_ROOT)))
        self.assertEqual(found, [], f"Legacy WAP files found: {found}")


if __name__ == '__main__':
    unittest.main()
```

- [ ] **Step 3: 테스트 실행 및 실패(RED) 확인**

Run: `python -m unittest tests/harness/test_terminology_guard.py -v`  
Expected: FAIL (4개 테스트 모두 현재 잔존 항목들을 적발하며 실패)

- [ ] **Step 4: 커밋**

```bash
git add tests/harness/test_terminology_guard.py
git commit -m "test(harness): add regression guard for legacy terminology purge (RED)"
```

---

### Task 2: 사양서 정적 검증기(`tools/verify_all_specs.py`)에 규칙 8 추가 (RED)

**Files:**
- Modify: `tools/verify_all_specs.py`
- Test: `python tools/verify_all_specs.py`

**Interfaces:**
- Consumes: 14개 활성 사양서
- Produces: `Rule 8. Legacy Terminology Hygiene` 정적 검사 (UAP/SAS/WAP 0건 강제)

- [ ] **Step 1: `tools/verify_all_specs.py`에 규칙 8 추가**

`tools/verify_all_specs.py` 내 검사 루프 하단(Rule 8 Mermaid 검사 다음)에 규칙 8 추가:
```python
        # 9. Rule 8: Legacy Terminology Hygiene (UAP / SAS / WAP Zero-Tolerance Purge)
        uap_pat = re.compile(r'(?<![A-Za-z0-9])uap(?![A-Za-z0-9])', re.IGNORECASE)
        sas_pat = re.compile(r'(?<![A-Za-z0-9])SAS(?![A-Za-z0-9])')
        wap_pat = re.compile(r'(?<![A-Za-z0-9])wap(?![A-Za-z0-9])', re.IGNORECASE)

        term_violations = []
        for i, line in enumerate(lines, 1):
            if uap_pat.search(line):
                term_violations.append((i, 'UAP', line.strip()))
            if sas_pat.search(line):
                term_violations.append((i, 'SAS', line.strip()))
            if wap_pat.search(line):
                term_violations.append((i, 'WAP', line.strip()))

        if term_violations:
            print(f"   [FAIL] Found {len(term_violations)} legacy terminology violation(s):")
            for lno, term, text in term_violations[:5]:
                print(f"      L{lno} [{term}]: {text[:80]}")
            if len(term_violations) > 5:
                print(f"      ... and {len(term_violations) - 5} more")
            total_errors += len(term_violations)
        else:
            print(f"   [PASS] Legacy terminology hygiene clean (zero UAP/SAS/WAP)")
```

- [ ] **Step 2: 스캐너 실행하여 14개 사양서의 위반 검출 확인 (RED)**

Run: `python tools/verify_all_specs.py`  
Expected: `[FAIL] Legacy terminology violations detected: ...` (총 390여 건 검출 및 실패)

- [ ] **Step 3: 커밋**

```bash
git add tools/verify_all_specs.py
git commit -m "feat(tools): add legacy terminology hygiene rule to verify_all_specs.py (RED)"
```

---

### Task 3: 런타임 코드 및 모듈 파일명 전면 개정 (Code Remediation - GREEN)

**Files:**
- Rename: `src/1_control/vas/modules/actuator_adapter_wap.lua` $\to$ `src/1_control/vas/modules/actuator_adapter_asa.lua`
- Rename: `src/1_control/vas/node_wap.lua` $\to$ `src/1_control/vas/node_asa.lua`
- Rename: `src/2_guidance/fcp/node_wap_sim.lua` $\to$ `src/2_guidance/fcp/node_asa_sim.lua`
- Modify: `src/1_control/vas/modules/state_machine.lua`
- Modify: `src/1_control/vas/modules/core_daemon.lua`
- Modify: `src/1_control/vas/modules/network_manager.lua`
- Modify: `src/1_control/vas/modules/telemetry_feeder.lua`
- Modify: `src/1_control/vas/modules/vehicle_policy.lua`
- Modify: `src/1_control/vas/node_fcp.lua`
- Modify: `src/1_control/asa/modules/config_manager.lua`
- Modify: `src/1_control/asa/modules/tui_dashboard.lua`
- Modify: `src/2_guidance/fcp/fcp_runtime.lua`
- Modify: `src/2_guidance/fcp/node_vas_sim.lua`
- Modify: `src/2_guidance/fcp/config/fcp_config.json`
- Modify: `src/2_guidance/fcp/modules/aerodynamic_controller.lua`
- Modify: `src/0_development/installer/modules/manifest.lua`
- Modify: `tests/1_control/asa/test_asa_core.lua`
- Modify: `tests/1_control/vas/test_vas_core.lua`
- Modify: `tests/0_infra/gcs/test_fleet_tracker.lua`
- Modify: `tests/0_infra/gcs/test_gcs_integration.lua`
- Modify: `tests/0_infra/gcs/test_ui_renderer.lua`
- Modify: `tests/e2e/test_e2e_bootstrap_and_telemetry.lua`
- Test: `python tools/run_unit_tests.py --require-tests --clean-orphans`

**Interfaces:**
- `lastUapCmdMs` $\to$ `lastFcpCmdMs`
- `lastUapCmd` $\to$ `lastFcpCmd`
- `uapTimeoutMs` $\to$ `fcpTimeoutMs`
- `UAP_CMD_TIMEOUT_1500MS` $\to$ `FCP_CMD_TIMEOUT_1500MS`
- `actuator_adapter_wap` $\to$ `actuator_adapter_asa`
- `node_wap` $\to$ `node_asa`
- `node_wap_sim` $\to$ `node_asa_sim`
- `podId`: `"WAP_L"`, `"WAP_R"`, `"WAP_T"` $\to$ `"ASA_L"`, `"ASA_R"`, `"ASA_T"`
- `actuatorHealth.wap` $\to$ `actuatorHealth.asa`
- `wapTimeoutMs` $\to$ `asaTimeoutMs`
- `WAP_DEGRADED_WARN` $\to$ `ASA_DEGRADED_WARN`, `WAP_TOTAL_LOSS_WARN` $\to$ `ASA_TOTAL_LOSS_WARN`

- [ ] **Step 1: 모듈 파일명 개명**

```bash
git mv src/1_control/vas/modules/actuator_adapter_wap.lua src/1_control/vas/modules/actuator_adapter_asa.lua
git mv src/1_control/vas/node_wap.lua src/1_control/vas/node_asa.lua
git mv src/2_guidance/fcp/node_wap_sim.lua src/2_guidance/fcp/node_asa_sim.lua
```

- [ ] **Step 2: VAS 코어 모듈 내 식별자 및 키 치환**
  - `state_machine.lua`: `UAP_CMD_TIMEOUT_1500MS` $\to$ `FCP_CMD_TIMEOUT_1500MS`, `apply_output_safety_rule`의 매개변수 `isWap` $\to$ `isAsa`.
  - `core_daemon.lua`: `actuator_adapter_wap` $\to$ `actuator_adapter_asa`, `adapterWap` $\to$ `adapterAsa`, `safeWap` $\to$ `safeAsa`, `satWap` $\to$ `satAsa`, `rawWap` $\to$ `rawAsa`, `actuatorHealth = { tap = tapOk, asa = asaOk }`.
  - `network_manager.lua`: `adapterWap` $\to$ `adapterAsa`, `latestCommand.uap` $\to$ `latestCommand.fcp`.
  - `telemetry_feeder.lua`: `actuatorHealth = diagState.actuatorHealth or { tap = true, asa = true }`.
  - `vehicle_policy.lua`: `satWap` $\to$ `satAsa`, `wapPos`/`wapNeg` $\to$ `asaPos`/`asaNeg`.
  - `node_fcp.lua`: 주석/에러 메시지 내 "mock UAP" $\to$ "mock FCP".
  - `node_asa.lua`: 주석/에러 메시지 내 "mock WAP" $\to$ "mock ASA".

- [ ] **Step 3: ASA 및 FCP 모듈, 설정, 목업 치환**
  - `src/1_control/asa/modules/config_manager.lua`: 기본 `podId = "ASA_L"`.
  - `src/1_control/asa/modules/tui_dashboard.lua`: 기본 `podId = "ASA_L"`.
  - `src/2_guidance/fcp/fcp_runtime.lua`: `actuatorHealth = { tca = true, asa = true, allOk = true }`.
  - `src/2_guidance/fcp/node_vas_sim.lua`: `actuatorHealth = { tca = true, asa = true, allOk = true }`.
  - `src/2_guidance/fcp/config/fcp_config.json`: `"wapTimeoutMs"` $\to$ `"asaTimeoutMs"`.
  - `src/2_guidance/fcp/modules/aerodynamic_controller.lua`: `WAP_DEGRADED_WARN` $\to$ `ASA_DEGRADED_WARN`, `WAP_TOTAL_LOSS_WARN` $\to$ `ASA_TOTAL_LOSS_WARN`, `[DEPRECATED]` 주석 정비.
  - `src/2_guidance/fcp/node_asa_sim.lua`: `wap_cmd_count` $\to$ `asa_cmd_count`.
  - `src/0_development/installer/modules/manifest.lua`: `actuator_adapter_wap.lua` $\to$ `actuator_adapter_asa.lua`.

- [ ] **Step 4: 단위 및 E2E 테스트 픽스처 치환**
  - `tests/1_control/asa/test_asa_core.lua`: `podId = "WAP_L"` (8건) $\to$ `"ASA_L"`.
  - `tests/1_control/vas/test_vas_core.lua`: `actuatorHealth = { tap = true, asa = true }`.
  - `tests/0_infra/gcs/test_fleet_tracker.lua`: `actuatorHealth = { tap = true, asa = true, allOk = true }`.
  - `tests/0_infra/gcs/test_gcs_integration.lua`: `actuatorHealth = { tap = true, asa = true, allOk = true }`.
  - `tests/0_infra/gcs/test_ui_renderer.lua`: `actuatorHealth = { tap = true, asa = true, allOk = true }`.
  - `tests/e2e/test_e2e_bootstrap_and_telemetry.lua`: `actuatorHealth = { tap = true, asa = true, allOk = true }`.

- [ ] **Step 5: 코드 정적 가드 테스트 통과 확인 (GREEN)**

Run: `python -m unittest tests/harness/test_terminology_guard.py -k "test_no_uap_in_entire_repository or test_no_legacy_wap_files"`  
Expected: PASS for code targets

- [ ] **Step 6: 전체 단위 테스트 및 E2E 시뮬레이션 회귀 확인**

Run: `python tools/run_unit_tests.py --require-tests --clean-orphans`  
Expected: 12개 타겟 248/248 PASS  
Run: `python tools/run_e2e_tests.py --clean-orphans`  
Expected: 6개 시나리오 6/6 PASS

- [ ] **Step 7: 커밋**

```bash
git add src/ tests/
git commit -m "fix(control): migrate runtime identifiers and modules from UAP/WAP to FCP/ASA (GREEN)"
```

---

### Task 4: 핵심 4대 사양서 정비 및 SemVer 마이너 승격 (Approved 전이)

**Files:**
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (v1.13.0 Implemented $\to$ v1.14.0 Approved)
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (v1.16.0 Implemented $\to$ v1.17.0 Approved)
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (v1.23.0 Approved $\to$ v1.24.0 Approved)
- Modify: `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (v1.5.0 Approved $\to$ v1.6.0 Approved)
- Test: `python tools/verify_all_specs.py`

**Interfaces:**
- 4대 사양서 내 모든 UAP/SAS/WAP 단어 소급 치환
- FCP: 40채널 공식 `$Base = 10000 + (N - 1) \times 40$`, `bandwidth = 40` 정비
- ASA: `podId = "ASA_L" | "ASA_R" | "ASA_T"` 단일화
- VAS: `actuator_adapter_asa`, `actuatorHealth.asa`, `FCP_CMD_TIMEOUT_1500MS` 동기화
- ICD: `MSG_AERO_CMD`, `MSG_AERO_STATUS`, MFD 및 텔레메트리 스키마 일체화

- [ ] **Step 1: `FCP_PROGRAM_SPECIFICATION.md` 개정**
  - 메타데이터: 버전을 `v1.14.0`, 날짜 당일 갱신, 문서 상태 `Approved`.
  - `Revision History`에 `v1.14.0` 행 추가: "구 명칭(UAP/SAS) 소급 전면 척결, 40채널 대역폭 및 채널 할당 공식 정비". 과거 이력표 내 `SAS` 단어도 `구 명칭`으로 치환.
  - 본문 및 다이어그램: `UAP_NODE`, `UAP_MAIN`, `PC["SAS 컴퓨터"]` $\to$ `FCP_NODE`, `FCP_MAIN`, `PC["FCP 컴퓨터"]`.
  - 패킷 송수신: `SAS -> Core`, `SAS -> ATC`, `SAS -> GPS` $\to$ `FCP -> Core`, `FCP -> ATC`, `FCP -> GPS`.
  - Line 81: `$Base = 10000 + (N - 1) \times 20$` $\to$ `$Base = 10000 + (N - 1) \times 40$`.
  - Line 1378: `bandwidth = 20` $\to$ `bandwidth = 40`.
  - `actuatorHealth.wap` $\to$ `actuatorHealth.asa`.

- [ ] **Step 2: `VAS_PROGRAM_SPECIFICATION.md` 개정**
  - 메타데이터: 버전을 `v1.17.0`, 날짜 당일 갱신, 문서 상태 `Approved`.
  - `Revision History`에 `v1.17.0` 행 추가: "WAP 어댑터를 ASA 어댑터로 정식 일원화, FCP 타임아웃 사유 및 텔레메트리 헬스 키 동기화, 구 명칭 전면 척결".
  - `actuator_adapter_wap` $\to$ `actuator_adapter_asa`, `node_wap` $\to$ `node_asa`.
  - `UAP_CMD_TIMEOUT_1500MS` $\to$ `FCP_CMD_TIMEOUT_1500MS`.
  - `actuatorHealth = { tap, asa }`, `podId` 예시 `"ASA_L"`.
  - 다이어그램 및 본문 내 `UAP`, `SAS`, `WAP` 일체 제거.

- [ ] **Step 3: `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` 개정**
  - 메타데이터: 버전을 `v1.24.0`, 날짜 당일 갱신, 문서 상태 `Approved`.
  - `Revision History`에 `v1.24.0` 행 추가: "유선 패킷 podId를 ASA_L/R/T로 완전 단일화, 텔레메트리 헬스 키 asa 반영, 구 명칭(UAP/SAS/WAP) 전면 소급 척결".
  - MFD 텔레메트리, 외루프 조종면, `MSG_AERO_CMD`, `MSG_AERO_STATUS` 테이블 내 `podId = "ASA_L", "ASA_R", "ASA_T"`.
  - 전역 다이어그램 및 패킷 주체 `UAP` $\to$ `FCP`.

- [ ] **Step 4: `ASA_PROGRAM_SPECIFICATION.md` 개정**
  - 메타데이터: 버전을 `v1.6.0`, 날짜 당일 갱신, 문서 상태 `Approved`.
  - `Revision History`에 `v1.6.0` 행 추가: "포드 ID(podId) ASA_L/R/T 완전 단일화, 구 WAP 명칭 잔재 소급 척결".
  - 본문, 설정 스키마, 다이어그램, 예제 코드 내 `podId = "ASA_L"` 등 일체화.
  - `ADAPT_WAP`, `WAP_CLUSTER`, `WAP_L/R/T` 다이어그램 노드명을 `ADAPT_ASA`, `ASA_CLUSTER`, `ASA_L/R/T`로 정비.

- [ ] **Step 5: 커밋**

```bash
git add docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md
git commit -m "docs(specs): harmonize 4 core specifications with ASA/FCP standards and bump minor versions"
```

---

### Task 5: 연관 10대 사양서 및 시스템 문서 소급 정비 (SemVer 패치 승격)

**Files:**
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (v2.10.1 Approved)
- Modify: `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (v2.5.2 Implemented)
- Modify: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (v2.2.2 Implemented)
- Modify: `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md` (v1.4.1 Approved)
- Modify: `docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md` (v1.11.1 Approved)
- Modify: `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md` (v2.4.2 Implemented)
- Modify: `docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md` (v1.10.6 Approved)
- Modify: `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` (v1.0.1 Implemented)
- Modify: `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (v1.10.1 Implemented)
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (v1.0.1 Implemented)
- Test: `python tools/verify_all_specs.py`, `python -m unittest tests/harness/test_terminology_guard.py`

**Interfaces:**
- 10대 사양서 및 마스터 다이어그램 문서 내 UAP, SAS, WAP 단어 소급 완전 제거
- `hardwareUuid = "SAS-NODE-04-4402"` $\to$ `"FCP-NODE-04-4402"`
- 패치 버전 승격 및 `Revision History` 갱신

- [ ] **Step 1: `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` 정비**
  - 버전 `v2.10.1 Approved`, 날짜 갱신.
  - `UAP_NODE` $\to$ `FCP_NODE`, `SAS` 다이어그램 노드명 $\to$ `FCP`.
  - `Revision History` 갱신.

- [ ] **Step 2: 인프라 사양서 5종 정비 (`docking_arm`, `landing_pad`, `runway`, `gps`, `gac`, `gcs`)**
  - 헤더 `컴포넌트` 표기: `(SAS ➔ VAS ...)` $\to$ `(FCP ➔ VAS ...)`.
  - 다이어그램 노드명: `SAS["기체 항법 FCP..."]` $\to$ `FCP["기체 항법 FCP..."]`.
  - 본문 텍스트 내 `UAP`, `SAS` 단어를 `FCP` 또는 `구 표준 명칭`으로 치환.
  - 버전 패치 승격 및 `Revision History` 기록.

- [ ] **Step 3: 제어 및 개발 사양서 3종 정비 (`alignment`, `tca`, `amm`)**
  - `alignment`: `hardwareUuid = "SAS-NODE-04-4402"` $\to$ `"FCP-NODE-04-4402"`, 본문 `SAS` $\to$ `FCP`.
  - `tca`: `SAS -> VAS-Core` $\to$ `FCP -> VAS-Core`.
  - `amm`: 잔존 `UAP`, `SAS`, `WAP` 전수 정비.
  - 버전 패치 승격 및 `Revision History` 기록.

- [ ] **Step 4: 용어 가드 회귀 테스트 전체 통과 확인 (GREEN)**

Run: `python -m unittest discover -s tests/harness -p "test_*.py"`  
Expected: 30개 테스트 전수 PASS (`TestTerminologyGuard` 4개 테스트 100% PASS)

- [ ] **Step 5: 사양서 스캐너 14개 전수 100% 클린 확인**

Run: `python tools/verify_all_specs.py`  
Expected: `SCAN RESULT: ALL 14 SPECS 100% CLEAN (0 Errors, 0 Warnings)`

- [ ] **Step 6: 커밋**

```bash
git add docs/
git commit -m "docs(specs): purge legacy terminology across remaining 10 specifications (GREEN)"
```

---

### Task 6: 전체 통합 검증, 사양서 상태 환원 및 브랜치 병합 (Handover)

**Files:**
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (Approved $\to$ Implemented)
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (Approved $\to$ Implemented)
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (Approved $\to$ Implemented)
- Modify: `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (Approved $\to$ Implemented)
- Modify: `TASK.md` (TASK-007 완료 처리)
- Modify: `GEMINI.md` (컨텍스트 동기화)
- Test: 전역 테스트 러너 및 정적 분석 CLI 일체

- [ ] **Step 1: 사양서 4종 상태 환원 (`Approved` $\to$ `Implemented`)**
  - `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`: `Implemented`
  - `FCP_PROGRAM_SPECIFICATION.md`: `Implemented`
  - `VAS_PROGRAM_SPECIFICATION.md`: `Implemented`
  - `ASA_PROGRAM_SPECIFICATION.md`: `Implemented`
  - 날짜 당일 동기화.

- [ ] **Step 2: 전체 파이프라인 일괄 검증 실행**
  - Run: `python tools/run_unit_tests.py --require-tests --clean-orphans` (12개 타겟 248/248 PASS)
  - Run: `python tools/run_e2e_tests.py --clean-orphans` (6개 시나리오 6/6 PASS)
  - Run: `python tools/run_mutation_tests.py` (20/20 KILLED, 100.0%)
  - Run: `python -m unittest discover -s tests/harness -p "test_*.py"` (30/30 PASS)
  - Run: `python tools/verify_all_specs.py` (ALL 14 SPECS 100% CLEAN)
  - Run: `python tools/verify_spec_status.py` (12 Implemented, 2 Approved 확인)
  - Run: `python tools/validate_lua_syntax.py` (0 Syntax Errors)

- [ ] **Step 3: `TASK.md` 및 `GEMINI.md` 갱신**
  - `TASK-007` 항목을 `[x]` 완료로 전환하고 완료 이력 아카이브에 기록.
  - `GEMINI.md` 80줄 이내 스냅샷 갱신.

- [ ] **Step 4: 워크트리 변경사항 커밋 및 메인 브랜치 병합**

```bash
git add docs/ TASK.md GEMINI.md
git commit -m "chore(release): complete TASK-007 legacy terminology purge and spec lifecycle restoration"
```
메인 워크트리로 복귀 후 브랜치 병합:
```bash
cd C:/Users/sjmik/Desktop/Create_Aeroneutics
& "C:\Program Files\Git\cmd\git.exe" merge task-legacy-terminology
& "C:\Program Files\Git\cmd\git.exe" worktree remove .worktrees/task-legacy-terminology
& "C:\Program Files\Git\cmd\git.exe" branch -d task-legacy-terminology
```
