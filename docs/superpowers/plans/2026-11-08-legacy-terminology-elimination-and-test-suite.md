# 구버전 명칭(UAP/SAS/WAP) 전면 척결 및 회귀 방지 테스트 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 비행 제어 및 공력 구동계 관련 구버전 잔존 명칭(`UAP`, 미폐기 표기 `SAS`, `WAP`)을 전수 식별·차단하는 자동화 회귀 테스트 슈트(`test_terminology_guard.py`, `verify_all_specs.py`)를 선행 구축(RED)하고, 13개 사양서 문서 및 런타임 코드·목업을 `FCP`/`ASA` 표준 명칭으로 완전 동기화(GREEN)한다.

**Architecture:** 
1. `tests/harness/test_terminology_guard.py`를 신설하여 `docs/`, `src/`, `tests/` 전역의 금지 명칭(정규식 패턴 매칭)을 CI 및 테스트 단계에서 원천 차단.
2. `tools/verify_all_specs.py`에 규칙 8(용어 위생 검사: `Rule 8. Legacy Terminology Hygiene`)을 통합하여 사양서 내 비표준 용어(비인가 `UAP`, 비인가 `SAS`, 비인가 `WAP`)를 정적 검증.
3. 런타임 코드(`state_machine.lua`, `network_manager.lua`, `actuator_adapter_*.lua`, `node_*.lua`) 및 패킷/매니페스트의 구버전 식별자를 최신 표준(`FCP`, `ASA`)으로 일체화.

**Tech Stack:** Python 3.12 (`unittest`, `re`, `pathlib`), Lua 5.2 / CraftOS-PC Runner.

**Spec:**
- [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md) (v1.23.0)
- [FCP_PROGRAM_SPECIFICATION.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md) (v1.13.0)
- [VAS_PROGRAM_SPECIFICATION.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md) (v1.16.0)
- [ASA_PROGRAM_SPECIFICATION.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md) (v1.5.0)

## Global Constraints

- **UAP 절대 배제 원칙**: 사양서, 런타임 소스코드, 테스트 코드 어디에도 `UAP` 및 대소문자 변형 식별자를 허용하지 않는다. (FCP v1.11.0 명칭 표준화 SSOT).
- **SAS 명시적 폐기 표기 한정 허용**: `SAS`는 오직 `[DEPRECATED]` 태그나 Revision History/과거 변경 이력 표기 맥락에서만 예외적으로 허용하며, 활성 본문(`SAS -> Core`, `SAS 컴퓨터` 등)은 일체 불허한다.
- **WAP -> ASA 단일화**: 공력 조종면 구동계(Node 06)의 표준 명칭은 `ASA(Aerodynamic Surface Adapter)`이며, 구 명칭 `WAP` 잔재 모듈(`actuator_adapter_wap.lua`, `node_wap.lua`, `node_wap_sim.lua`)은 `actuator_adapter_asa.lua`, `node_asa.lua`, `node_asa_sim.lua`로 일원화한다.
- **테스트 무결성 유지**: 기존 단위 테스트 241건, E2E 시뮬레이션 6건, 하네스 테스트 24건 전수 PASS를 100% 보존해야 한다.

## Review Focus

1. **상태머신 전이 사유 문자열 호환성**: `state_machine.lua`의 `UAP_CMD_TIMEOUT_1500MS`를 `FCP_CMD_TIMEOUT_1500MS`로 변경 시, 외부 테스트(`test_vas_core.lua` 등)나 로그 검증에서 하드코딩된 사유 문자열 의존성이 존재하는지 확인.
2. **ASA 포드 ID (`WAP_L`, `WAP_R`, `WAP_T`)**: 패킷 스키마(`MSG_AERO_CMD`, `MSG_AERO_STATUS`) 상의 `podId`가 `ASA_L` 등으로 변경될 경우 네트워크 인터페이스 호환성에 미치는 영향 검토.
3. **인스톨러 매니페스트 동기화**: `src/0_development/installer/modules/manifest.lua` 내 파일 레지스트리에 등록된 `actuator_adapter_wap.lua` 경로가 `actuator_adapter_asa.lua`로 누락 없이 갱신되는지 확인.
4. **정규식 단어 경계 및 한글 조사 처리**: 한국어 문서 특성상 `UAP는`, `UAP의`, `UAP가` 등 조사가 결합된 경우 `\bUAP\b`로는 감지되지 않으므로, 유니코드 인식 또는 `(?i)(?<![A-Za-z0-9])uap(?![A-Za-z0-9])` 형태의 정밀 정규식 적용.
5. **합법적 과거 이력 보존**: Revision History 및 `[DEPRECATED]` 각주 내의 정당한 역사적 기록이 테스트에서 오탐(False Positive)으로 실패하지 않도록 허용 필터링 로직 구현.

---

### Task 1: 용어 검증 테스트 슈트 신설 (`tests/harness/test_terminology_guard.py`)

**Files:**
- Create: `tests/harness/test_terminology_guard.py`
- Test: `tests/harness/test_terminology_guard.py`

**Interfaces:**
- Consumes: `docs/system/*.md`, `docs/specs/**/*.md`, `src/**/*.lua`, `tests/**/*.lua`
- Produces: `TestTerminologyGuard` (Python `unittest.TestCase`)

- [ ] **Step 1: 실패하는 용어 검증 테스트 슈트 작성**

```python
import os
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

class TestTerminologyGuard(unittest.TestCase):
    def test_no_uap_in_specifications(self):
        """docs/ 디렉토리 내 사양서에서 UAP/uap 잔존을 검출한다."""
        uap_pattern = re.compile(r'(?<![A-Za-z0-9])uap(?![A-Za-z0-9])', re.I)
        violations = []
        for p in (REPO_ROOT / 'docs').rglob('*.md'):
            if 'superpowers' in p.parts:
                continue
            content = p.read_text(encoding='utf-8')
            for idx, line in enumerate(content.splitlines(), 1):
                if uap_pattern.search(line):
                    violations.append(f"{p.relative_to(REPO_ROOT)}:L{idx}: {line.strip()[:80]}")
        self.assertEqual(violations, [], f"Found {len(violations)} UAP occurrences in specs:\n" + "\n".join(violations[:10]))

    def test_no_uap_in_code_and_tests(self):
        """src/ 및 tests/ 내 Lua 파일에서 uap/UAP 잔존을 검출한다."""
        uap_pattern = re.compile(r'(?<![A-Za-z0-9])uap(?![A-Za-z0-9])', re.I)
        violations = []
        for base in ['src', 'tests']:
            for p in (REPO_ROOT / base).rglob('*.lua'):
                content = p.read_text(encoding='utf-8')
                for idx, line in enumerate(content.splitlines(), 1):
                    if uap_pattern.search(line):
                        violations.append(f"{p.relative_to(REPO_ROOT)}:L{idx}: {line.strip()[:80]}")
        self.assertEqual(violations, [], f"Found {len(violations)} UAP occurrences in code/tests:\n" + "\n".join(violations[:10]))

    def test_no_undeprecated_sas_in_specs(self):
        """docs/ 사양서 본문에서 [DEPRECATED] 또는 이력 표기 없는 SAS 잔존을 검출한다."""
        sas_pattern = re.compile(r'\bSAS\b')
        violations = []
        for p in (REPO_ROOT / 'docs').rglob('*.md'):
            if 'superpowers' in p.parts:
                continue
            lines = p.read_text(encoding='utf-8').splitlines()
            in_rev_history = False
            for idx, line in enumerate(lines, 1):
                if '### Revision History' in line:
                    in_rev_history = True
                elif in_rev_history and line.startswith('---'):
                    in_rev_history = False
                if sas_pattern.search(line):
                    if in_rev_history or '[DEPRECATED]' in line or 'deprecated' in line or '구 SAS' in line or '기존 SAS' in line:
                        continue
                    violations.append(f"{p.relative_to(REPO_ROOT)}:L{idx}: {line.strip()[:80]}")
        self.assertEqual(violations, [], f"Found {len(violations)} un-deprecated SAS occurrences:\n" + "\n".join(violations[:10]))

    def test_no_legacy_wap_files(self):
        """src/ 내에 구버전 WAP 모듈명이 남아있지 않은지 검출한다."""
        banned_filenames = {'node_wap.lua', 'actuator_adapter_wap.lua', 'node_wap_sim.lua'}
        found = []
        for p in (REPO_ROOT / 'src').rglob('*.lua'):
            if p.name in banned_filenames:
                found.append(str(p.relative_to(REPO_ROOT)))
        self.assertEqual(found, [], f"Legacy WAP files found: {found}")
```

- [ ] **Step 2: 테스트 실행 및 실패(RED) 확인**

Run: `python -m unittest tests/harness/test_terminology_guard.py -v`  
Expected: FAIL (4개 테스트 모두 현재 위반 항목들을 적발하며 실패)

- [ ] **Step 3: 커밋**

```bash
git add tests/harness/test_terminology_guard.py
git commit -m "test(harness): add regression test suite for legacy terminology hygiene"
```

---

### Task 2: 사양서 무결성 검증기(`tools/verify_all_specs.py`)에 용어 규칙 확장

**Files:**
- Modify: `tools/verify_all_specs.py`
- Test: `python tools/verify_all_specs.py`

**Interfaces:**
- Consumes: 14개 활성 사양서
- Produces: 용어 위생 검사(UAP 원천 차단, 비인가 SAS 차단, 비인가 WAP 차단)

- [ ] **Step 1: 실패 검증 - `verify_all_specs.py`에 용어 위생 규칙 8 추가**

`tools/verify_all_specs.py`에 다음 검사 블록을 추가:
- `UAP` 검출 시 ERROR 카운트 증가.
- `[DEPRECATED]` 또는 Revision History 외 영역에서 `SAS` 단독 사용 시 ERROR 카운트 증가.
- 미승인 `WAP` 본문 사용 시 WARN/ERROR 보고.

- [ ] **Step 2: 스캐너 실행하여 14개 사양서의 위반 검출 확인 (RED)**

Run: `python tools/verify_all_specs.py`  
Expected: `[FAIL] Legacy terminology violations detected: ...` (총 수십 건 검출 및 0 Errors 상태 탈락 확인)

- [ ] **Step 3: 커밋**

```bash
git add tools/verify_all_specs.py
git commit -m "feat(tools): add legacy terminology hygiene rule to verify_all_specs.py"
```

---

### Task 3: 런타임 소스코드 및 목업 노드의 구버전 명칭 치환 (Code Remediation)

**Files:**
- Modify: `src/1_control/vas/modules/state_machine.lua`
- Modify: `src/1_control/vas/modules/network_manager.lua`
- Modify: `src/1_control/vas/node_fcp.lua`
- Rename & Modify: `src/1_control/vas/node_wap.lua` $\to$ `src/1_control/vas/node_asa.lua`
- Rename & Modify: `src/1_control/vas/modules/actuator_adapter_wap.lua` $\to$ `src/1_control/vas/modules/actuator_adapter_asa.lua`
- Rename & Modify: `src/2_guidance/fcp/node_wap_sim.lua` $\to$ `src/2_guidance/fcp/node_asa_sim.lua`
- Modify: `src/1_control/vas/modules/core_daemon.lua`
- Modify: `src/0_development/installer/modules/manifest.lua`
- Modify: `src/2_guidance/fcp/modules/aerodynamic_controller.lua`
- Test: `python tools/run_unit_tests.py --clean-orphans`

**Interfaces:**
- `lastUapCmdMs` $\to$ `lastFcpCmdMs`
- `lastUapCmd` $\to$ `lastFcpCmd`
- `uapTimeoutMs` $\to$ `fcpTimeoutMs`
- `UAP_CMD_TIMEOUT_1500MS` $\to$ `FCP_CMD_TIMEOUT_1500MS`
- `actuator_adapter_wap` $\to$ `actuator_adapter_asa`
- `node_wap` $\to$ `node_asa`

- [ ] **Step 1: `state_machine.lua` 및 `network_manager.lua` 변수명/사유 일체화**
  `lastUapCmdMs`, `lastUapCmd`, `uapTimeoutMs`, `UAP_CMD_TIMEOUT_1500MS`를 각각 `lastFcpCmdMs`, `lastFcpCmd`, `fcpTimeoutMs`, `FCP_CMD_TIMEOUT_1500MS`로 변경.
  `node_fcp.lua` 주석 및 에러 메시지 내 "mock UAP" $\to$ "mock FCP".

- [ ] **Step 2: WAP 모듈 및 목업 파일명/참조를 ASA로 개명**
  `node_wap.lua` $\to$ `node_asa.lua`
  `actuator_adapter_wap.lua` $\to$ `actuator_adapter_asa.lua`
  `node_wap_sim.lua` $\to$ `node_asa_sim.lua`
  `core_daemon.lua`, `manifest.lua`, `aerodynamic_controller.lua` 내부 `require` 및 테이블 키 동기화.

- [ ] **Step 3: 코드 테스트 확인 (GREEN)**
  Run: `python -m unittest tests/harness/test_terminology_guard.py -k "test_no_uap_in_code_and_tests or test_no_legacy_wap_files"`  
  Expected: PASS

- [ ] **Step 4: 단위 테스트 전체 회귀 검증**
  Run: `python tools/run_unit_tests.py --require-tests --clean-orphans`  
  Expected: 12개 타겟 241/241 PASS

- [ ] **Step 5: 커밋**

```bash
git add src/ tests/
git commit -m "fix(control): migrate runtime identifiers and modules from UAP/WAP to FCP/ASA"
```

---

### Task 4: `FCP_PROGRAM_SPECIFICATION.md` 잔존 명칭 일괄 정비

**Files:**
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`
- Test: `python tools/verify_all_specs.py`

**Interfaces:**
- 63개 `UAP` 및 33개 비인가 `SAS` 구문을 `FCP`로 전면 개정
- 20채널 수식 잔재(`\times 20`)를 40채널(`\times 40`) 표준으로 수정

- [ ] **Step 1: FCP 사양서 텍스트 및 다이어그램 개정**
  - 개요, 본문, 다이어그램 노드명(`UAP_NODE`, `UAP_MAIN`, `PC["SAS 컴퓨터"]`) 치환.
  - 패킷 송수신 주체(`SAS -> Core`, `SAS -> ATC`, `SAS -> GPS`) $\to$ (`FCP -> Core`, `FCP -> ATC`, `FCP -> GPS`).
  - 과거 배포 이력(Google Drive 등) 언급 시 `uap_bundle.lua`를 `fcp_bundle.lua` 또는 공식 번들명으로 정비하거나 명시적 `[DEPRECATED]` 처리.
  - Line 81: `$Base = 10000 + (N - 1) \times 20$` $\to$ `$Base = 10000 + (N - 1) \times 40$`.

- [ ] **Step 2: FCP 사양서 검증 (GREEN)**
  Run: `python tools/verify_all_specs.py` (FCP 섹션 에러 0건 확인)

- [ ] **Step 3: 커밋**

```bash
git add docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md
git commit -m "docs(fcp): purge legacy UAP and un-deprecated SAS terminology from FCP specification"
```

---

### Task 5: 마스터 ICD 및 타 도메인 사양서 잔존 용어 정비

**Files:**
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (19 UAP, un-deprecated SAS)
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (4 UAP, un-deprecated SAS)
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (15 UAP, WAP references)
- Modify: `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md` (7 UAP)
- Modify: `docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md` (5 UAP)
- Modify: `docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md` (4 UAP)
- Modify: `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (5 UAP, WAP references)
- Modify: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (2 UAP)
- Modify: `TASK.md` (작업 추적 내역 동기화)
- Test: `python tools/verify_all_specs.py`, `python -m unittest tests/harness/test_terminology_guard.py`

- [ ] **Step 1: 마스터 ICD 및 다이어그램 문서 내 UAP/SAS 치환**
  - `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`: MFD 스트림, 텔레메트리, 외루프 조종면 분담 본문 내 `UAP` $\to$ `FCP`.
  - `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`: 노드 다이어그램 및 시퀀스 차트 내 `UAP_NODE` $\to$ `FCP_NODE`.

- [ ] **Step 2: 제어 및 인프라 사양서 6종 내 UAP/WAP 치환**
  - `VAS_PROGRAM_SPECIFICATION.md`: `actuator_adapter_wap` $\to$ `actuator_adapter_asa`, `UAP` $\to$ `FCP`.
  - `ASA_PROGRAM_SPECIFICATION.md`: `UAP` $\to$ `FCP`, 어댑터 명칭 정합성 확보.
  - `landing_pad`, `docking_arm`, `runway`, `gps`: 전술 유도 및 접근 체크인 주체 명칭 `UAP` $\to$ `FCP`.

- [ ] **Step 3: 용어 가드 테스트 전체 통과 확인 (GREEN)**
  Run: `python -m unittest discover -s tests/harness -p "test_*.py"`  
  Expected: 25개 테스트 전수 PASS (TestTerminologyGuard 4개 테스트 100% PASS)

- [ ] **Step 4: 사양서 스캐너 14개 전수 100% 클린 확인**
  Run: `python tools/verify_all_specs.py`  
  Expected: `SCAN RESULT: ALL 14 SPECS 100% CLEAN (0 Errors, 0 Warnings)`

- [ ] **Step 5: 커밋**

```bash
git add docs/ TASK.md
git commit -m "docs(specs): harmonize legacy terminology across master ICD and domain specifications"
```

---

### Task 6: 전체 회귀 및 무결성 최종 검증 (Verification & Handover)

**Files:**
- Test: 전역 테스트 러너 및 정적 분석 CLI

- [ ] **Step 1: 단위 테스트 전체 실행**
  Run: `python tools/run_unit_tests.py --require-tests --clean-orphans`  
  Expected: 12개 타겟 241/241 PASS

- [ ] **Step 2: E2E 시뮬레이션 전체 실행**
  Run: `python tools/run_e2e_tests.py --clean-orphans`  
  Expected: 6개 시나리오 6/6 PASS

- [ ] **Step 3: 하네스 회귀 테스트 실행**
  Run: `python -m unittest discover -s tests/harness -p "test_*.py"`  
  Expected: All PASS

- [ ] **Step 4: 사양서 상태 및 정적 검사 실행**
  Run: `python tools/verify_all_specs.py`  
  Run: `python tools/verify_spec_status.py`  
  Run: `python tools/validate_lua_syntax.py`  
  Expected: 0 Errors, 0 Warnings
