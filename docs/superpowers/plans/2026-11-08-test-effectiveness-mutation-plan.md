# 구현된 테스트의 실효성 및 결함 검출력 검증 계획서 (Test Effectiveness & Mutation Plan)

> **문서 상태**: 확정 및 실행 착수 (Aligned via `/grill-me` Session)  
> **기준 규칙**: `systematic-debugging` 4단계 철칙 (원인 조사 → 패턴 분석 → 가설 수립 및 최소 검증 → 근본 구현)  
> **실행 브랜치**: `task-111-e2e-simulation` (`.worktrees/task-111-e2e-simulation`)  
> **통과 기준**: 주입된 20대 핵심 결함 중 **$\ge 90\%$ (18/20 이상 KILL)** 달성 및 전 유닛/E2E 테스트 통과  

---

## 1. 확정된 설계 방향 (Resolved Decisions via `/grill-me`)

1. **뮤테이션 결함 주입 범위 및 통과 기준**:
   - 20대 핵심 프로덕션 결함 매트릭스(네트워크, FSM, 유도/제어 수학, 안전 차단, 착륙/지상 관제) 구축.
   - 자동 결함 주입 테스터(`tools/run_mutation_tests.py`)를 개발하여 **결함 검출률(Kill Rate) $\ge 90\%$ (18/20 이상 KILL)** 달성.
2. **E2E 시나리오 리팩토링 방식**:
   - 기존 6개 E2E 시나리오 파일(`tests/e2e/test_e2e_*.lua`)을 직접 리팩토링.
   - 인형극식 수동 패킷 주입(`modem:transmit` 바이패스)을 전면 제거하고, 실제 노드의 프로덕션 핸들러(`tca_daemon`, `vas_net`, `gac_fsm`, `state_machine` 등) 직결 폐루프로 전환.
3. **부정/예외 경로(Negative Pathway) 검증 구성**:
   - 별도 신규 파일 분리 대신, **기존 6개 E2E 테스트 파일마다 대응하는 부정/예외 `it()` 블록을 1~2개씩 분산 추가**.
4. **작업 및 커밋 원칙**:
   - `.worktrees/task-111-e2e-simulation` 브랜치에서 단계별 TDD 단위 커밋으로 안전하게 수행.

---

## 2. 세부 실행 계획 및 작업 분할 (Execution Tasks)

### Step 1: 자동 결함 주입 뮤테이션 테스터 개발 (`tools/run_mutation_tests.py`)
- **대상 파일**: `tools/run_mutation_tests.py`, `tests/harness/test_mutation_runner.py`
- Python 기반 20대 결정론적 코드 변이 주입기 (`try ... finally` 원자적 복원 보장).
- 각 변이에 대해 관련 유닛/E2E 테스트 실행 (`--target` 또는 `--filter`).
- 테스트 `FAIL` 시 `KILLED` (정상 검출), `PASS` 시 `SURVIVED` (검출 실패/실효성 부족) 판정.
- 종합 검출률(Kill Rate %) 계산 및 요약 리포트 CLI 출력.

### Step 2: E2E 시나리오 1~6 프로덕션 디스패처 직결 리팩토링 및 부정 검증 추가
각 시나리오 파일에 대해: (1) 수동 패킷 조립 제거 및 실제 프로덕션 핸들러 연동, (2) 대응 부정 `it()` 블록 추가.
1. **Scenario 1 (`test_e2e_bootstrap_and_telemetry.lua`)**: Happy path 실제 텔레메트리 디스패처 직결 + Negative path 잘못된 도메인/UUID 부트스트랩 거절.
2. **Scenario 2 (`test_e2e_waypoint_guidance.lua`)**: Happy path FCP-VAS-TCA-ASA 실시간 연동 + Negative path 미등록 액추에이터 그룹 ID 무시.
3. **Scenario 3 (`test_e2e_gps_triangulation.lua`)**: Happy path GPS 스웜/서버 프로토콜 파이프라인 연동 + Negative path 쿼럼 미달 시 WLS 삼각측위 거절.
4. **Scenario 4 (`test_e2e_hangar_alignment.lua`)**: Happy path 실제 펄스/OLS 세션 핸드셰이크 + Negative path 비행 중(`NORMAL`) 캘리브레이션 진입 차단.
5. **Scenario 5 (`test_e2e_c2_and_estop.lua`)**: Happy path VAS 실제 `state_machine.lua` 연동 + Negative path GCS Override 중 조종사 수동 해제 차단.
6. **Scenario 6 (`test_e2e_facility_landing.lua`)**: Happy path GAC-Pad-FCP 전술 착륙 + Negative path 기체 과적 시 GAC의 `DENIED` 처리 및 착륙 불허.

### Step 3: 뮤테이션 테스터 실행 및 결함 검출률 $\ge 90\%$ 달성 검증
- `python tools/run_mutation_tests.py` 실행.
- 20개 변이 중 최소 18개 이상(18/20, $\ge 90\%$) KILLED 달성 확인.

### Step 4: 전체 회귀 및 정적 무결성 점검
- 12개 유닛 테스트 타겟 241/241 PASS 확인.
- 6개 E2E 시나리오 전원 PASS 확인.
- Python 하네스 테스트 전원 PASS 확인.
- 14개 사양서 100% CLEAN 확인.
