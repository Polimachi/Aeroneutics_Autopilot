<!-- living-context: Snapshot managed by md-management skill. In-place replace only (strictly <= 80 lines). Append historical logs to .agent/memory/<dir>.md instead. -->
# Create_Aeroneutics — Living Project Context

## 1. Current Phase & Active Handover
- **현재 단계**: **Phase 1 & 2** — Phase 0 전 과제 및 구버전 용어 척결 완료, 지상 인프라 및 온보드 유도/제어기 확장 진행 중.
- **직전 완료**: `TASK-007` 완료 (구버전 명칭 UAP/SAS/WAP 소급 전면 척결 및 회귀 방지 테스트 슈트 구축: test_terminology_guard.py, verify_all_specs.py Rule 8, 런타임/테스트 22개 파일 마이그레이션, 14대 사양서 전수 무결성 100% CLEAN, 8 Implemented, 6 Approved, 33/33 하네스 테스트 PASS, 248/248 유닛 타겟 PASS, 6/6 E2E 시나리오 PASS, 20/20 돌연변이 살상률 100.0%).
- **현재 활성**: `TASK-114` (GAC 전용 시설물 런타임 코드 `src/0_infra/gac/` 및 단위 테스트 구현 대기) / `TASK-010` (플레이북 체계 구축) / `TASK-115` (ADVANCED_VTOL 아키텍처).
- **다음 착수 후보**:
  1. `TASK-201`: AMP (Autopilot Mission Planner) 사양서 초안(Draft) 작성.
  2. `TASK-103`: Runway 활주로 제어기 구현 (`src/0_infra/runway/`, 사양서 v1.10.6 Approved).
  3. `TASK-301`: 물리 하드웨어 기반 ACRO 수동 급기동 조종 인터페이스 개발 (Phase 3).
  4. `TASK-105`: ASA (Aerodynamic Surface Adapter) 공력 조종면·플랩 분산 구동기 본 구현 완성.

## 2. Confirmed Architecture & Paths
- `TASK.md`: 장기 작업 추적 및 백로그 SSOT.
- `AGENTS.md`: 불변 행동 헌장 (`attention-span` × `caveman` 하이브리드 + `no-overclaim`). **사전 diff 승인 없이 수정 금지**.
- `GEMINI.md`: 작업 간 동적 컨텍스트 스냅샷 (4개 고정 섹션 덮어쓰기, **80줄 상한**).
- `docs/system/` & `docs/specs/`: 마스터 ICD·전역 구조도 및 기능 도메인 단일 계층 사양서 (`docs/specs/<domain>/<subsystem>/`).
- `installer.lua` & `src/`: 독립 완결형 멀티 Lua 코드베이스 (`0_development/{alignment,installer,sensors}`, `0_infra/{gps,gac,gcs,docking_arm,landing_pad,runway}`, `1_control/{vas,tca,asa}`, `2_guidance/fcp`, `3_planning/amm`, `4_mission/`).
- `harness/` & `tests/`: CraftOS-PC 헤드리스 기반 단위/통합 테스트 하네스(`harness/{unit,simulation}/`) 및 테스트 슈트(`tests/{0_development,0_infra,1_control,2_guidance,3_planning,e2e,harness}/`).
- `tools/`: 개발·검증 CLI (`tools/run_unit_tests.py`, `tools/run_e2e_tests.py`, `tools/run_mutation_tests.py`, `tools/validate_lua_syntax.py`, `tools/verify_all_specs.py`, `tools/verify_spec_status.py`).
- `reports/`: 분석·리팩토링 검토 보고서 (`underReview/`, `reviewCompleted/`).
- `.worktrees/` & `.runtime/`: Git Worktree 격리 영역 및 CraftOS 임시 세션 디렉토리 (`.gitignore` 등록).
- `.agent/`: 온디맨드 이력(`memory/workspace-root.md`), 규칙 3종(`rules/`), 전문 스킬 13종(`skills/`), 안전 훅(`hooks/`).

## 3. Standard Commands
- **버전 관리 (PowerShell `PATH` 미등록 주의)**: `& "C:\Program Files\Git\cmd\git.exe" status -sb` (Worktree: `... worktree add .worktrees/<branch> -b <branch>`).
- **Lua 단위 테스트**: `python tools/run_unit_tests.py --require-tests --clean-orphans` (12개 타겟 248/248 PASS).
- **Lua E2E 시뮬레이션 테스트**: `python tools/run_e2e_tests.py --clean-orphans` (6개 시나리오 6/6 PASS).
- **돌연변이 살상 테스트**: `python tools/run_mutation_tests.py` (20/20 KILLED, 100.0% 살상률).
- **하네스 자체 회귀**: `python -m unittest discover -s tests/harness -p "test_*.py"` (33/33 PASS).
- **사양서·문법 정적 검사**: `python tools/verify_all_specs.py`, `python tools/validate_lua_syntax.py`, `python tools/verify_spec_status.py` (8 Implemented, 6 Approved).

## 4. Gotchas & Invariants
- **멀티 코드베이스 독립 완결성**: `src/<layer>/<name>/` 간 공용 모듈 직접 참조 금지 (개별 CC 컴퓨터 루트 마운트 단위 캡슐화, 기본 진입점 `main.lua`).
- **CC:Avionics 센서 공용 라이브러리**: `/lib/avionics_sensors.lua`로 자동 주입되며 `require("avionics_sensors")`로 로드 (`velocity_sensor`, `altitude_sensor`, `gimbal_sensor`, `physics_assembler` 4종 SSOT).
- **통합 인스톨러 배포 삼총사**: 화면 직접 업로드 `/installer.lua`, 플로피 `/disk/installer.lua`, 원격 `wget run <url>`. GitHub/GCS 이중 다운로드 지원.
- **CraftOS-PC 런타임 의존성**: `tools/run_unit_tests.py` 및 `tools/run_e2e_tests.py`는 `CraftOS-PC_console.exe` 설치 필요 (`CRAFTOS_PC_EXE` 환경변수 지정 가능).
- **전역 RF 스펙트럼 및 40채널 규격**: 기체 $Base = 10000 + (N-1) \times 40$ ($N=1\sim 1000$, `10000~49999`): Zone 1(`0~9` 코어 C2/유도/텔레메트리/`Base+5` GPS 응답), Zone 2(`10~19` 구동계: `Base+10` TCA, `Base+11` ASA), Zone 3(`20~29` 탑재체), Zone 4(`30~39` 편대링크). 격납고(`101~200`), GCS/관제(`50000~59999`), GPS(`60001~60020`).
- **Zero-Fallback & 영구 단일 경로**: 수신단 듀얼키 폴백 금지(구 필드는 사양서 `[DEPRECATED]` 표기); 사양서는 디렉토리 이동 없이 상단 메타데이터 표로만 상태를 전이한다.
- **`ion_thruster` 충돌 조정**: `Create Propulsion: Simulated`의 `ion_thruster` 페리페럴은 허용하며, 금지 규칙은 `kontraption:` 네임스페이스만 차단한다.
- **온보드 제어기 20Hz 헤드리스 원칙**: VAS/TCA/ASA는 터미널 UI 블로킹 방지를 위해 헤드리스가 기본이며, 디버그 TUI는 `config.json`의 `debug: true` 시 비동기(`parallel`)로만 격리 구동한다.
- **VECTORED_VTOL 외루프 가이던스**: 3축 Surge/Sway/Heave 완전 PID + Anti-windup, CRUISE 한정 TILT_ASSISTED 15°/s 피치 슬루율, 안전고도 미달 시 수평 차단 수직 이륙 및 패드 0.5m 정렬 2단계 감속 터치다운을 적용한다.
- **GCS 지상 비행 지휘 콘솔**: `CH 50000` 부트스트랩 스티키 영속화, `Base+0` 원격 C2 오버라이드, `Base+1` 하드 E_STOP 직결 셧다운, `Base+3` 텔레메트리 51x19 무깜빡임 콘솔 모니터링을 적용한다.
- **AMM 임무 관리 및 조종 중재**: GCS 원격 C2 무반향 감청, 웨이포인트 2D 수평 거리 15m 자동 전환 및 E-STOP/HOLD 하드웨어 선점 중재를 적용한다.
- **멀티노드 E2E 시뮬레이션 원칙**: 가상 버스/샌드박스 기반 멀티노드 테스트는 각 노드의 고유 `_ENV` 격리 및 채널 배타성을 준수하며, 테스트 종료 시 `os.shutdown()` 핸드셰이크를 보장한다.
