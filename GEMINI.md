<!-- living-context: Snapshot managed by md-management skill. In-place replace only (strictly <= 80 lines). Append historical logs to .agent/memory/<dir>.md instead. -->
# Create_Aeroneutics — Living Project Context

## 1. Current Phase & Active Handover
- **현재 단계**: **Phase 0** — 기체 5대 핵심 모듈 40채널·Zone 런타임 코드 동기화 및 단위·하네스 테스트 검증 완료.
- **직전 완료**: `TASK-001`·`TASK-002` 종결 및 루트 4대 문서 정합화 (VAS, TCA, FCP, Alignment, GPS 40채널 동기화, 커밋 `16b8390`~`4c1db74`, 단위 테스트 42/42 PASS, 하네스 회귀 14/14 PASS).
- **다음 착수 후보**:
  1. `TASK-003`: 워킹 트리 미커밋 사양서 4종 정리·검증 후 구현 완료 5대 사양서 상태 전이 (`Approved` → `Implemented`).
  2. `TASK-004`: 원격 푸시 (`git push -u origin main`) 사용자 인증 완료 확인.
  3. `TASK-005`: 통합 코드베이스 설치 프로그램(Unified Installer) 구축.

## 2. Confirmed Architecture & Paths
- `TASK.md`: 장기 작업 추적 및 백로그 SSOT.
- `AGENTS.md`: 불변 행동 헌장 (`attention-span` × `caveman` 하이브리드 + `no-overclaim`). **사전 diff 승인 없이 수정 금지**.
- `GEMINI.md`: 작업 간 동적 컨텍스트 스냅샷 (4개 고정 섹션 덮어쓰기, **80줄 상한**).
- `docs/system/` & `docs/specs/`: 마스터 ICD·전역 구조도 및 기능 도메인 단일 계층 사양서 (`docs/specs/<domain>/<subsystem>/`).
- `src/`: 독립 완결형 멀티 Lua 코드베이스 (`0_development/alignment`, `0_infra/{gps,gac,docking_arm,landing_pad,runway}`, `1_control/{vas,tca,asa}`, `2_guidance/fcp`, `3_planning/`, `4_mission/`).
- `harness/` & `tests/`: CraftOS-PC 헤드리스 기반 단위 테스트 하네스(`harness/unit/`) 및 테스트 슈트(`tests/{0_development,0_infra,1_control,2_guidance,harness}/`).
- `tools/`: 단위 테스트 러너 CLI (`tools/run_unit_tests.py`).
- `reports/`: 분석·리팩토링 검토 보고서 (`underReview/`, `reviewCompleted/`).
- `.worktrees/` & `.runtime/`: Git Worktree 격리 영역 및 CraftOS 임시 세션 디렉토리 (`.gitignore` 등록).
- `.agent/`: 온디맨드 이력(`memory/workspace-root.md`), 규칙 3종(`rules/`), 전문 스킬 13종(`skills/`), 안전 훅(`hooks/`).

## 3. Standard Commands
- **버전 관리 (PowerShell `PATH` 미등록 주의)**: `& "C:\Program Files\Git\cmd\git.exe" status -sb` (Worktree: `... worktree add .worktrees/<branch> -b <branch>`).
- **Lua 단위 테스트**: `python tools/run_unit_tests.py --require-tests --clean-orphans` (6개 타겟 42/42 PASS).
- **하네스 자체 회귀**: `python -m unittest discover -s tests/harness -p "test_*.py"` (14/14 PASS).
- **사양서·문법 정적 검사**: `python scratch/verify_all_specs.py`, `python scratch/validate_lua_syntax.py`.

## 4. Gotchas & Invariants
- **멀티 코드베이스 독립 완결성**: `src/<layer>/<name>/` 간 공용 모듈 참조 금지 (개별 CC 컴퓨터 루트 마운트 단위 캡슐화, 기본 진입점 `main.lua`).
- **CraftOS-PC 런타임 의존성**: `tools/run_unit_tests.py`는 `CraftOS-PC_console.exe` 설치 필요 (비표준 경로 시 `CRAFTOS_PC_EXE` 환경변수 지정).
- **전역 RF 스펙트럼 및 40채널 규격**: 기체 $Base = 10000 + (N-1) \times 40$ ($N=1\sim 1000$, `10000~49999`): Zone 1(`0~9` 코어 C2/유도/텔레메트리/`Base+5` GPS 응답), Zone 2(`10~19` 구동계: `Base+10` TCA, `Base+11` ASA), Zone 3(`20~29` 탑재체), Zone 4(`30~39` 편대링크). 격납고(`101~200`), GCS/관제(`50000~59999`), GPS(`60001~60020`).
- **Zero-Fallback & 영구 단일 경로**: 수신단 듀얼키 폴백 금지(구 필드는 사양서 `[DEPRECATED]` 표기); 사양서는 디렉토리 이동 없이 상단 메타데이터 표로만 상태를 전이한다.
- **`ion_thruster` 충돌 조정**: `Create Propulsion: Simulated`의 `ion_thruster` 페리페럴은 허용하며, 금지 규칙은 `kontraption:` 네임스페이스만 차단한다.
