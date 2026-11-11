<!-- living-context: Snapshot managed by md-management skill. In-place replace only (strictly <= 80 lines). Append historical logs to .agent/memory/<dir>.md instead. -->
# Create_Aeroneutics — Living Project Context

## 1. Current Phase & Active Handover
- **현재 단계**: **Phase 1 & 2** — 지상 인프라 및 온보드 유도/제어기 확장 진행 중 (활성·백로그 SSOT: `TASK.md`).
- **직전 완료**: `TASK-201`(FCP `v1.16.0 Implemented`), `TASK-202-2~3`(AMM 3분할 코어·FSM·C2·헤드리스), `TASK-202-1` 개정(AMM `v1.2.0`/ICD `v1.27.0`/구조도 `v2.12.1` `Approved` — 외부 에디터·외부 파일 즉시 구동 명세) (2026-11-11, 이력 `.agent/memory/workspace-root.md`).
- **다음 액션**:
  1. `TASK-202`: AMM TUI·CLI·다중 경로·스키마 검증·`file_transfer` 즉시 구동(`TASK-202-4`), `tools/amm_mission_editor.html`·E2E 검증·사양서 `Implemented` 환원(`TASK-202-5`).
  2. `TASK-010`: 플레이북 정적 검증기(`tools/verify_playbooks.py`) 및 핵심 5종 매뉴얼 작성.
  3. `TASK-103` / `TASK-117` / `TASK-204`: 활주로(`RUNWAY` v1.10.6 Approved) 제어기, OTA 서버 사양 또는 AMM 행동 진입조건 재정의 착수.

## 2. Confirmed Architecture & Paths
- `TASK.md`: 장기 작업 추적 및 백로그 SSOT.
- `AGENTS.md`: 불변 행동 헌장 (`attention-span` × `caveman` 하이브리드 + `no-overclaim`). **사전 diff 승인 없이 수정 금지**.
- `GEMINI.md`: 작업 간 동적 컨텍스트 스냅샷 (4개 고정 섹션 덮어쓰기, **80줄 상한**).
- `docs/system/` & `docs/specs/`: 마스터 ICD·전역 구조도 및 기능 도메인 단일 계층 사양서 (`docs/specs/<domain>/<subsystem>/`).
- `docs/superpowers/plans/`: 태스크별 실행 계획서 (`YYYY-MM-DD-task-<id>-*.md`).
- `installer.lua` & `src/`: 독립 완결형 멀티 Lua 코드베이스 (`0_development/{alignment,installer,sensors}`, `0_infra/{gps,gac,gcs,docking_arm,landing_pad,runway}`, `1_control/{vas,tca,asa}`, `2_guidance/fcp`, `3_planning/amm`, `4_mission/`).
- `harness/` & `tests/`: CraftOS-PC 헤드리스 기반 단위/통합 테스트 하네스(`harness/{unit,simulation}/`) 및 테스트 슈트(`tests/{0_development,0_infra,1_control,2_guidance,3_planning,e2e,harness}/`).
- `tools/`: 개발·검증 CLI (`tools/run_unit_tests.py`, `tools/run_e2e_tests.py`, `tools/run_mutation_tests.py`, `tools/validate_lua_syntax.py`, `tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/verify_manifest_sync.py`, `tools/verify_context_docs.py`).
- `config/gdrive_mapping.json` & `dist_gdrive/` & `tools/sync_gdrive.py`: GDrive 배포 매핑 SSOT, 격리 스테이징, 동기화 CLI (가이드 `docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md`).
- `reports/`: 분석·리팩토링 검토 보고서 (`underReview/`, `reviewCompleted/`).
- `.worktrees/` & `.runtime/`: Git Worktree 격리 영역 및 CraftOS 임시 세션 디렉토리 (`.gitignore` 등록).
- `.agent/`: 온디맨드 이력(`memory/workspace-root.md`), 규칙 3종(`rules/`), 전문 스킬 13종(`skills/`), 안전 훅(`hooks/`, `hooks.json`).

## 3. Standard Commands
- **버전 관리 (PowerShell `PATH` 미등록 주의)**: `& "C:\Program Files\Git\cmd\git.exe" status -sb` (Worktree: `... worktree add .worktrees/<branch> -b <branch>`).
- **Lua 단위 테스트**: `python tools/run_unit_tests.py --require-tests --clean-orphans` (12개 타겟 361/361 PASS).
- **Lua E2E 시뮬레이션 테스트**: `python tools/run_e2e_tests.py --clean-orphans` (7개 시나리오 8/8 PASS).
- **돌연변이 살상 테스트**: `python tools/run_mutation_tests.py` (25/25 KILLED, 100.0% 살상률, 기준 90.0%).
- **하네스 자체 회귀**: `python -m unittest discover -s tests/harness -p "test_*.py"` (82/82 PASS).
- **컨텍스트 문서 정합성**: `python tools/verify_context_docs.py` (0 findings, 규칙 R1~R8).
- **사양서·문법·매니페스트 정적 검사**: `python tools/verify_manifest_sync.py` (0 Errors, 0 Warnings), `python tools/verify_all_specs.py` (15대 사양서 0 Errors, 0 Warnings), `python tools/validate_lua_syntax.py` (129 파일), `python tools/verify_spec_status.py` (9 Implemented, 6 Approved).
- **GDrive 배포**: `python tools/sync_gdrive.py {stage|sync|status|verify}` (`sync --dry-run` 선행, `gdrive` CLI PATH 등록 필요).

## 4. Gotchas & Invariants
- **멀티 코드베이스 독립 완결성**: `src/<layer>/<name>/` 간 공용 모듈 직접 참조 금지 (개별 CC 컴퓨터 루트 마운트 단위 캡슐화, 기본 진입점 `main.lua`). 유일한 예외는 인스톨러가 주입하는 `/lib/avionics_sensors.lua`.
- **CC:Avionics 센서 공용 라이브러리**: `/lib/avionics_sensors.lua`로 자동 주입되며 `require("avionics_sensors")`로 로드 (`velocity_sensor`, `altitude_sensor`, `gimbal_sensor`, `physics_assembler` 4종 SSOT).
- **통합 인스톨러 배포 삼총사**: 화면 직접 업로드 `/installer.lua`, 플로피 `/disk/installer.lua`, 원격 `wget run <url>`. GitHub raw / Google Drive 이중 다운로드 지원.
- **CraftOS-PC 런타임 의존성**: `tools/run_unit_tests.py` 및 `tools/run_e2e_tests.py`는 `CraftOS-PC_console.exe` 설치 필요 (`CRAFTOS_PC_EXE` 환경변수 지정 가능).
- **PowerShell 5.1 체이닝**: 기본 셸은 Windows PowerShell 5.1이며 `&&` 미지원 → `; if ($?) { ... }` 사용.
- **전역 RF 스펙트럼 및 40채널 규격**: 기체 $Base = 10000 + (N-1) \times 40$ ($N=1\sim 1000$, `10000~49999`): Zone 1(`0~9` 코어 C2/유도/텔레메트리/`Base+5` GPS 응답), Zone 2(`10~19` 구동계: `Base+10` TCA, `Base+11` ASA), Zone 3(`20~29` 탑재체), Zone 4(`30~39` 편대링크). 격납고(`101~200`), GCS/관제(`50000~59999`), GPS(`60001~60020`).
- **Zero-Fallback & 영구 단일 경로**: 수신단 듀얼키 폴백 금지(구 필드는 사양서 `[DEPRECATED]` 표기); 사양서는 디렉토리 이동 없이 상단 메타데이터 표로만 상태를 전이한다.
- **`ion_thruster` 충돌 조정**: `Create Propulsion: Simulated`의 `ion_thruster` 페리페럴은 허용하며, 금지 규칙은 `kontraption:` 네임스페이스만 차단한다.
- **온보드 제어기 20Hz 헤드리스 원칙**: VAS/TCA/ASA는 터미널 UI 블로킹 방지를 위해 헤드리스가 기본이며, 디버그 TUI는 `config.json`의 `debug: true` 시 비동기(`parallel`)로만 격리 구동한다.
- **멀티노드 E2E 시뮬레이션 원칙**: 가상 버스/샌드박스 기반 멀티노드 테스트는 각 노드의 고유 `_ENV` 격리 및 채널 배타성을 준수하며, 테스트 종료 시 `os.shutdown()` 핸드셰이크를 수행한다.
- **컨텍스트 문서 Stop 훅**: `.agent/hooks.json`이 작업 종료 시 `verify_context_docs` 위반을 검사해 재개시킨다 (새 대화부터 적용, 동일 위반 2회 상한, 오류 시 종료 허용; `git-guardrails`가 `git.exe` 포함 위험 명령 차단).
