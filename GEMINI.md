<!-- living-context: Snapshot managed by md-management skill. In-place replace only (strictly <= 80 lines). Append historical logs to .agent/memory/<dir>.md instead. -->
# Create_Aeroneutics — Living Project Context

## 1. Current Phase & Active Handover
- **현재 단계**: **Phase 1** — Phase 0(기반 구축·도구화) 전 과제 완료, 지상 인프라 및 온보드 제어기 확장 착수.
- **직전 완료**: `TASK-101` 완료 (GAC 사양서 v1.3.0 Implemented 승격, 지상 구역 관제사 7개 모듈 및 3-Tab TUI 콘솔 구현, 인스톨러 등록, 단위 테스트 112/112 PASS, 하네스 24/24 PASS).
- **다음 착수 후보**:
  1. `TASK-102`: Landing Pad 지상 착륙 패드 제어기 구현 (`docs/specs/0_infra/landing_pad/`, `src/0_infra/landing_pad/`).
  2. `TASK-112`: VAS/FCP 센서 표준 라이브러리(`avionics_sensors`) 연동 및 잔재 정리.

## 2. Confirmed Architecture & Paths
- `TASK.md`: 장기 작업 추적 및 백로그 SSOT.
- `AGENTS.md`: 불변 행동 헌장 (`attention-span` × `caveman` 하이브리드 + `no-overclaim`). **사전 diff 승인 없이 수정 금지**.
- `GEMINI.md`: 작업 간 동적 컨텍스트 스냅샷 (4개 고정 섹션 덮어쓰기, **80줄 상한**).
- `docs/system/` & `docs/specs/`: 마스터 ICD·전역 구조도 및 기능 도메인 단일 계층 사양서 (`docs/specs/<domain>/<subsystem>/`).
- `installer.lua` & `src/`: 독립 완결형 멀티 Lua 코드베이스 (`0_development/{alignment,installer,sensors}`, `0_infra/{gps,gac,docking_arm,landing_pad,runway}`, `1_control/{vas,tca,asa}`, `2_guidance/fcp`, `3_planning/`, `4_mission/`).
- `harness/` & `tests/`: CraftOS-PC 헤드리스 기반 단위 테스트 하네스(`harness/unit/`) 및 테스트 슈트(`tests/{0_development,0_infra,1_control,2_guidance,harness}/`).
- `tools/`: 개발·검증 CLI (`tools/run_unit_tests.py`, `tools/validate_lua_syntax.py`, `tools/verify_all_specs.py`, `tools/verify_spec_status.py`).
- `reports/`: 분석·리팩토링 검토 보고서 (`underReview/`, `reviewCompleted/`).
- `.worktrees/` & `.runtime/`: Git Worktree 격리 영역 및 CraftOS 임시 세션 디렉토리 (`.gitignore` 등록).
- `.agent/`: 온디맨드 이력(`memory/workspace-root.md`), 규칙 3종(`rules/`), 전문 스킬 13종(`skills/`), 안전 훅(`hooks/`).

## 3. Standard Commands
- **버전 관리 (PowerShell `PATH` 미등록 주의)**: `& "C:\Program Files\Git\cmd\git.exe" status -sb` (Worktree: `... worktree add .worktrees/<branch> -b <branch>`).
- **Lua 단위 테스트**: `python tools/run_unit_tests.py --require-tests --clean-orphans` (9개 타겟 112/112 PASS).
- **하네스 자체 회귀**: `python -m unittest discover -s tests/harness -p "test_*.py"` (24/24 PASS).
- **사양서·문법 정적 검사**: `python tools/verify_all_specs.py`, `python tools/validate_lua_syntax.py`, `python tools/verify_spec_status.py`.

## 4. Gotchas & Invariants
- **멀티 코드베이스 독립 완결성**: `src/<layer>/<name>/` 간 공용 모듈 직접 참조 금지 (개별 CC 컴퓨터 루트 마운트 단위 캡슐화, 기본 진입점 `main.lua`).
- **CC:Avionics 센서 공용 라이브러리**: `/lib/avionics_sensors.lua`로 자동 주입되며 `require("avionics_sensors")`로 로드 (`velocity_sensor`, `altitude_sensor`, `gimbal_sensor`, `physics_assembler` 4종 SSOT).
- **통합 인스톨러 배포 삼총사**: 화면 직접 업로드 `/installer.lua`, 플로피 `/disk/installer.lua`, 원격 `wget run <url>`. GitHub/GCS 이중 다운로드 지원.
- **CraftOS-PC 런타임 의존성**: `tools/run_unit_tests.py`는 `CraftOS-PC_console.exe` 설치 필요 (비표준 경로 시 `CRAFTOS_PC_EXE` 환경변수 지정).
- **전역 RF 스펙트럼 및 40채널 규격**: 기체 $Base = 10000 + (N-1) \times 40$ ($N=1\sim 1000$, `10000~49999`): Zone 1(`0~9` 코어 C2/유도/텔레메트리/`Base+5` GPS 응답), Zone 2(`10~19` 구동계: `Base+10` TCA, `Base+11` ASA), Zone 3(`20~29` 탑재체), Zone 4(`30~39` 편대링크). 격납고(`101~200`), GCS/관제(`50000~59999`), GPS(`60001~60020`).
- **Zero-Fallback & 영구 단일 경로**: 수신단 듀얼키 폴백 금지(구 필드는 사양서 `[DEPRECATED]` 표기); 사양서는 디렉토리 이동 없이 상단 메타데이터 표로만 상태를 전이한다.
- **`ion_thruster` 충돌 조정**: `Create Propulsion: Simulated`의 `ion_thruster` 페리페럴은 허용하며, 금지 규칙은 `kontraption:` 네임스페이스만 차단한다.
