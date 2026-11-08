# TASK-003 사양서 상태 전이 (Approved → Implemented) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `TASK-001`을 통해 구현 및 단위 테스트(42/42 PASS)가 검증된 기체 5대 핵심 사양서(`VAS`, `TCA`, `FCP`, `Alignment`, `GPS`)의 인문서 메타데이터 표 상태를 `Approved`에서 `Implemented`로 인플레이스 전이하고, 워킹 트리 미커밋 사양서 4종을 정리하여 전역 사양서 무결성 및 프로젝트 로드맵을 완결한다.

**Architecture:** 사양서 영구 경로 불변 원칙(`docs/specs/<domain>/<subsystem>/`)을 엄수하여 파일 이동 없이 상단 5대 필수 항목 표의 `문서 상태`와 `최종 수정일`만 갱신한다. 워킹 트리의 미커밋 사양서 4종(마스터 ICD, 패킷 구조도, Alignment, TCA)을 선행 감사·커밋한 뒤, 5대 구현 사양서만 `Implemented`로 승격하고 미구현/Phase 1/연기 사양서 7종은 `Approved`를 불변 유지한다. 전용 상태 검증기(`scratch/verify_spec_status.py`)와 전수 무결성 스캐너(`scratch/verify_all_specs.py`)로 12종 사양서의 상태 직교성을 기계적으로 검증한다.

**Tech Stack:** Python 3.10+, Markdown, CraftOS-PC Lua 5.2 Unit Harness (`tools/run_unit_tests.py`), Git.

**Spec:**
- [docs/specs/README.md](../../specs/README.md)
- [TASK.md](../../../TASK.md)
- [GEMINI.md](../../../GEMINI.md)
- [docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md)
- [docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md](../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md)

## Global Constraints

- **영구 경로 불변 원칙 (Permanent Unified Path)**: 사양서는 생명주기 상태 전이 시 디렉토리를 이동하지 않으며 `docs/specs/<domain>/<subsystem>/` 경로를 영구 유지한다.
- **경량 자동 승격 프로토콜**: `verification-before-completion` 검증(단위 테스트 42/42 PASS, 문법 7/7 PASS) 완료 후 상단 메타데이터 표의 `문서 상태`를 `Implemented`로 갱신하고 `최종 수정일`을 동기화한다 (`specification-lifecycle-manager` 비호출, Mixed-Scope 면제).
- **5:7 직교 상태 분리**: 5대 핵심 구현 사양서(`VAS`, `TCA`, `FCP`, `Alignment`, `GPS`)만 `Implemented`로 승격하며, 시스템 마스터 2종(`AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD`, `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM`) 및 미구현/연기 5종(`GAC`, `DOCKING_ARM`, `LANDING_PAD`, `RUNWAY`, `ASA`)은 `Approved`를 엄격히 유지한다.
- **과장 표현 영구 금지 (Overclaim Ban)**: 커밋 메시지, 계획서, 코드, 문서 어디에도 측정·검증되지 않은 수식어를 작성하지 않는다.

## Review Focus

1. **워킹 트리 미커밋 사양서 4종 정합성**: 마스터 ICD, 패킷 구조도, Alignment, TCA의 개정 이력 중복 여부 및 $BW=40$, $N=1\sim 1000$ 수치 정합성 검증 (`verify_all_specs.py`).
2. **비대상 7종 사양서 오염 방지**: `ASA`, `GAC`, 지상설비 3종 및 시스템 마스터 2종의 상태가 실수로 `Implemented`로 전이되지 않는지 검증 (`verify_spec_status.py`).
3. **5대 사양서 메타데이터 표준 테이블 5대 필드 유지**: `문서 상태`, `문서 버전`, `최종 수정일`, `구현 코드`, `주관 도메인` 행이 누락 없이 보존되는지 검증.
4. **README 내 레거시 잔재 동기화**: `docs/specs/README.md` 내 잔존하는 구 명칭 `sas`가 `fcp`로 완전 동기화되는지 검증.
5. **로드맵 및 컨텍스트 정합성**: `TASK.md`의 `TASK-003` 항목과 `GEMINI.md` 스냅샷(<= 80줄)이 마일스톤 완료 상태로 정합하는지 검증.

---

### Task 1: 워킹 트리 미커밋 사양서 4종 정리·검증 및 사전 커밋 (`TASK-003-0`)

**Files:**
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`
- Modify: `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md`
- Scan: `src/`, `tests/` (20채널 잔재 스캔)

**Interfaces:**
- Consumes: 워킹 트리에 존재하는 4대 사양서의 수치 정합성 패치
- Produces: 4대 사양서 커밋 및 레거시 20채널 상수 0건 확인 증거

- [ ] **Step 1: 레거시 20채널 상수 잔존 0건 선행 정적 스캔**

Run:
```powershell
python -c "
import os, re
patterns = [(r'\b10020\b', '10020'), (r'\b10060\b', '10060'), (r'\b10006\b', '10006'), (r'\b10026\b', '10026'), (r'\b30004\b', '30004'), (r'\b10067\b', '10067')]
hits = []
for root, _, files in os.walk('src'):
    for f in files:
        if f.endswith('.lua') or f.endswith('.json'):
            p = os.path.join(root, f)
            with open(p, 'r', encoding='utf-8', errors='ignore') as fp:
                for idx, line in enumerate(fp, 1):
                    for pat, name in patterns:
                        if re.search(pat, line): hits.append(f'{p}:{idx} [{name}]')
print(f'Legacy hits count: {len(hits)}')
assert len(hits) == 0, f'Found legacy hits: {hits}'
"
```
Expected: `Legacy hits count: 0`.

- [ ] **Step 2: 미커밋 사양서 4종 무결성 검증**

Run: `python scratch/verify_all_specs.py`  
Expected: `SCAN RESULT: ALL 12 SPECS 100% CLEAN (0 Errors, 0 Warnings)`.

- [ ] **Step 3: 미커밋 사양서 4종 및 루트 변경분 격리 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md README.md AGENTS.md GEMINI.md TASK.md .agent/memory/workspace-root.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(system): finalize 40-channel bandwidth specifications and align root documents"
```

---

### Task 2: 회귀 검증 및 상태 전이 검증 스크립트 작성 (`TASK-003-1`)

**Files:**
- Create: `scratch/verify_spec_status.py`
- Verify: `tests/harness/`, `tools/run_unit_tests.py`

**Interfaces:**
- Consumes: `docs/specs/**` 메타데이터 표
- Produces: `scratch/verify_spec_status.py` (5개 `Implemented`, 7개 `Approved` 상태를 단언 검증하는 CLI 도구)

- [ ] **Step 1: 실패하는 정적 검증 스크립트 `scratch/verify_spec_status.py` 작성**

```python
import os, re, sys

TARGET_IMPLEMENTED = [
    'docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md',
    'docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md',
    'docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md',
    'docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md',
    'docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md',
]

TARGET_APPROVED = [
    'docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md',
    'docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md',
    'docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md',
    'docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md',
]

def check_status():
    errors = []
    status_pat = re.compile(r'\|\s*\*\*문서 상태 \(Status\)\*\*\s*\|\s*`([^`]+)`\s*\|')

    for path in TARGET_IMPLEMENTED:
        if not os.path.exists(path):
            errors.append(f"Missing file: {path}")
            continue
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        m = status_pat.search(content)
        if not m:
            errors.append(f"Missing status table in {path}")
        elif m.group(1).strip() != 'Implemented':
            errors.append(f"{path}: expected 'Implemented', got '{m.group(1).strip()}'")

    for path in TARGET_APPROVED:
        if not os.path.exists(path):
            errors.append(f"Missing file: {path}")
            continue
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        m = status_pat.search(content)
        if not m:
            errors.append(f"Missing status table in {path}")
        elif m.group(1).strip() != 'Approved':
            errors.append(f"{path}: expected 'Approved', got '{m.group(1).strip()}'")

    if errors:
        print(f"[FAIL] {len(errors)} spec status violation(s):")
        for e in errors:
            print("  - " + e)
        sys.exit(1)
    print(f"[PASS] All 12 specs have valid statuses (5 Implemented, 7 Approved)!")

if __name__ == '__main__':
    check_status()
```

- [ ] **Step 2: 스크립트 실행하여 기대 실패(Red) 확인**

Run: `python scratch/verify_spec_status.py`  
Expected: FAIL with 5 errors (VAS, TCA, FCP, Alignment, GPS: expected 'Implemented', got 'Approved').

- [ ] **Step 3: 사전 회귀 테스트 전수 실행**

Run:
```powershell
python -m unittest discover -s tests/harness -v
python tools/run_unit_tests.py --require-tests --clean-orphans
python scratch/validate_lua_syntax.py
```
Expected:
- Harness: 14/14 tests OK.
- Unit runner: 6 targets, 42/42 tests PASS.
- Syntax validator: 7/7 files PASS.

- [ ] **Step 4: 스크립트 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add scratch/verify_spec_status.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "test(specs): add verification script for Phase 0 spec status transition"
```

---

### Task 3: 5대 핵심 사양서 메타데이터 인플레이스 상태 전이 (`Approved` → `Implemented`) (`TASK-003-2`)

**Files:**
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md:8-10`
- Modify: `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md:8-10`
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md:8-10`
- Modify: `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md:8-10`
- Modify: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md:8-10`
- Modify: `docs/specs/README.md:16`

**Interfaces:**
- Consumes: Task 2 검증 스크립트
- Produces: 5개 사양서의 `Status: Implemented`, `Date: 2026-11-08` 갱신

- [ ] **Step 1: 5대 핵심 사양서 상단 메타데이터 표 갱신**

1) `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`:
   - `| **문서 상태 (Status)** | `Approved` |` → `| **문서 상태 (Status)** | `Implemented` |`
   - `| **최종 수정일 (Date)** | `2026-11-07` |` → `| **최종 수정일 (Date)** | `2026-11-08` |`
2) `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md`:
   - `| **문서 상태 (Status)** | `Approved` |` → `| **문서 상태 (Status)** | `Implemented` |`
   - `| **최종 수정일 (Date)** | `2026-11-08` |` (유지)
3) `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`:
   - `| **문서 상태 (Status)** | `Approved` |` → `| **문서 상태 (Status)** | `Implemented` |`
   - `| **최종 수정일 (Date)** | `2026-11-07` |` → `| **최종 수정일 (Date)** | `2026-11-08` |`
4) `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md`:
   - `| **문서 상태 (Status)** | `Approved` |` → `| **문서 상태 (Status)** | `Implemented` |`
   - `| **최종 수정일 (Date)** | `2026-11-08` |` (유지)
5) `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`:
   - `| **문서 상태 (Status)** | `Approved` |` → `| **문서 상태 (Status)** | `Implemented` |`
   - `| **최종 수정일 (Date)** | `2026-11-07` |` → `| **최종 수정일 (Date)** | `2026-11-08` |`
6) `docs/specs/README.md`:
   - Line 16: `- 2_guidance/: 자율 항법 및 오토파일럿 사양서 (sas 등)` → `- 2_guidance/: 자율 항법 및 외루프 유도 컴퓨터 사양서 (fcp 등)`

- [ ] **Step 2: 상태 전이 정합성 스크립트 실행 (Green 확인)**

Run: `python scratch/verify_spec_status.py`  
Expected: `[PASS] All 12 specs have valid statuses (5 Implemented, 7 Approved)!`

- [ ] **Step 3: 사양서 전수 무결성 스캐너 실행**

Run: `python scratch/verify_all_specs.py`  
Expected: `SCAN RESULT: ALL 12 SPECS 100% CLEAN (0 Errors, 0 Warnings)`.

- [ ] **Step 4: 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md docs/specs/README.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(specs): transition 5 core phase 0 specs to Implemented status"
```

---

### Task 4: 전역 무결성 스캔 및 전 코드베이스 회귀 방어 (`TASK-003-3`)

**Files:**
- Verify: `scratch/verify_all_specs.py`, `scratch/verify_spec_status.py`, `tools/run_unit_tests.py`, `tests/harness/`

**Interfaces:**
- Consumes: Task 3 커밋
- Produces: 12종 사양서 및 6대 코드베이스의 전수 무결성 통과 증거

- [ ] **Step 1: 사양서 12종 전수 무결성 검증**

Run: `python scratch/verify_all_specs.py`  
Expected: `SCAN RESULT: ALL 12 SPECS 100% CLEAN (0 Errors, 0 Warnings)`.

- [ ] **Step 2: 상태 전이 정합성 재검증**

Run: `python scratch/verify_spec_status.py`  
Expected: `[PASS] All 12 specs have valid statuses (5 Implemented, 7 Approved)!`.

- [ ] **Step 3: 전 코드베이스 단위 테스트 및 하네스 재실행**

Run:
```powershell
python -m unittest discover -s tests/harness -v
python tools/run_unit_tests.py --require-tests --clean-orphans
python scratch/validate_lua_syntax.py
```
Expected:
- 14/14 harness tests OK.
- 42/42 unit tests PASS across 6 targets.
- 7/7 Lua 5.2 files syntax PASS.

---

### Task 5: 로드맵(`TASK.md`) 및 컨텍스트(`GEMINI.md`) 동기화

**Files:**
- Modify: `TASK.md`
- Modify: `GEMINI.md`

**Interfaces:**
- Consumes: Task 3 및 Task 4 검증 결과
- Produces: `TASK.md` `TASK-003` 완료 체크마크(`[x]`), `GEMINI.md` Phase 0 인계 상태 동기화

- [ ] **Step 1: `TASK.md` 갱신**

- `TASK.md`의 `TASK-003`을 `[x]`(완료)로 전이하고 하위 항목(`TASK-003-0` ~ `TASK-003-3`)을 모두 `[x]`로 체크.
- 완료 일자 `2026-11-08` 및 커밋 해시 기록.
- 현재 단계 상태 갱신: `현재 단계: Phase 0 (기체 5대 핵심 사양서 Implemented 전이 완료 → 원격 푸시 및 통합 인스톨러 대기)`.

- [ ] **Step 2: `GEMINI.md` 동기화 및 80줄 상한 점검**

- Section 1 (Current Phase & Active Handover) 갱신:
  - 현재 단계: `Phase 0 — 기체 5대 핵심 모듈 40채널 코드 동기화 및 사양서 Implemented 승격 완료`.
  - 직전 완료: `TASK-003` 완료 (5대 핵심 사양서 Implemented 전이, `verify_spec_status.py` 12종 전수 검증).
  - 다음 착수 후보:
    1. `TASK-004`: 원격 푸시(`git push -u origin main`) 사용자 인증 완료 확인.
    2. `TASK-005`: 통합 코드베이스 설치 프로그램(Unified Installer) 구축.
- 줄 수 점검: `(Get-Content GEMINI.md).Count`가 80줄 이하인지 확인.

- [ ] **Step 3: 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add TASK.md GEMINI.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(task): mark TASK-003 spec status transition complete and sync context"
```
