<!-- living-context: Snapshot managed by md-management skill. In-place replace only (strictly <= 80 lines). Append historical logs to .agent/memory/<dir>.md instead. -->
# Create_Aeroneutics — Living Project Context

## 1. Current Phase & Active Handover
- **현재 단계**: **Phase 1 & 2** — 지상 인프라·WebUI LAN Live·GDrive 배포·40채널 정합·공중 콜드부트·안전 인터록/PBIT/GPS DR 가드·프로토콜 계약/코드 정리 완료 후 후속 확장 진행 중 (활성·백로그 SSOT: `TASK.md`).
- **직전 완료**: `TASK-017`·`018`(Zone 3 `30..39` 확장·계약/사문화 RX·필드 정합화·루트 `installer.lua` 단일 SSOT화·복제 분기 3건 및 미사용 함수 17/설정키 19 정리; 2026-11-19), `TASK-016`(제품 아키텍처 L1~L4 감사 및 `tools/audit/` 편입), `TASK-136`·`131`·`128`(컨트랩션 인터록·5단계 PBIT·GPS DR 가드), `TASK-405`·`406`(LAN Live·Inspection). 이전 이력: `TASK.md` §3, `.agent/memory/workspace-root.md`.
- **다음 액션**:
  1. `TASK-302` (1순위): Pocket PDA 원격 관제 단말.
  2. `TASK-019` / `TASK-140` / `TASK-015` (2순위): 사양 경량화·저고도 착륙 감쇠·플레이북.
  3. `TASK-020`·`021` / `TASK-135` / `TASK-214` / `TASK-105`↔`210` / `TASK-132` / `TASK-129` (3순위): 대형 분할·지상 TUI 분리·AMM 샌드박스·허브 대기 스택·ASA 본 구현·비상 활공·적응형 트림.

## 2. Confirmed Architecture & Paths
- `TASK.md`: 장기 작업 추적 및 백로그 SSOT.
- `AGENTS.md`: 불변 행동 헌장 (`attention-span` × `caveman` 하이브리드 + `no-overclaim`). **사전 diff 승인 없이 수정 금지**.
- `GEMINI.md`: 작업 간 동적 컨텍스트 스냅샷 (4개 고정 섹션 덮어쓰기, **80줄 상한**).
- `docs/system/` & `docs/specs/`: 마스터 ICD·전역 구조도 및 기능 도메인 단일 계층 사양서 (`docs/specs/<domain>/<subsystem>/`).
- `docs/superpowers/{plans,specs}/`: 태스크별 실행 계획서 및 설계 청사진.
- `installer.lua` & `src/`: 루트 `/installer.lua` 단일 부트스트랩 SSOT 및 독립 완결형 멀티 Lua 코드베이스 (`0_development/{alignment,fdr,installer,ota,sensors}`, `0_infra/{gps,gac,gcs,docking_arm,landing_pad,runway}`, `1_control/{vas,tca,asa}`, `2_guidance/fcp`, `3_planning/amm`, `4_mission/`).
- `config/protocol_contracts.json`: 활성 사양서·코드베이스·E2E 패킷 교차 검증용 기계 판독형 SSOT 와이어 프로토콜 계약 명세.
- `harness/` & `tests/`: CraftOS-PC 헤드리스 기반 단위/통합 테스트 하네스(`harness/{unit,simulation}/`) 및 테스트 슈트(`tests/{0_development,0_infra,1_control,2_guidance,3_planning,e2e,harness}/`).
- `tools/`: 개발·검증 CLI (`run_unit_tests.py`, `run_e2e_tests.py`, `run_boot_smoke.py`, `verify_contracts.py`, `verify_runtime_wiring.py`, `run_mutation_tests.py`, `analyze_flight_log.py`, `gcs_live_bridge.py`, `sync_gdrive.py`, `validate_lua_syntax.py`, `verify_all_specs.py`, `verify_spec_status.py`, `verify_manifest_sync.py`, `verify_context_docs.py`, `audit/`) 및 WebUI 에디터(`amm_mission_editor.html`, `v0.6.0 Implemented`).
- `config/gdrive_mapping.json` & `dist_gdrive/` & `tools/sync_gdrive.py`: GDrive 배포 매핑 SSOT(135파일 전수 매핑), 격리 스테이징, 동기화 CLI (가이드 `docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md`).
- `reports/`: 분석·리팩토링 검토 보고서 (`underReview/`, `reviewCompleted/`).
- `.worktrees/` & `.runtime/`: Git Worktree 격리 영역 및 CraftOS 임시 세션 디렉토리 (`.gitignore` 등록).
- `.agent/`: 온디맨드 이력(`memory/workspace-root.md`), 규칙 3종(`rules/`), 전문 스킬 15종(`skills/`), 안전 훅(`hooks/`, `hooks.json`).

## 3. Standard Commands
- **버전 관리 (PowerShell `PATH` 미등록 주의)**: `& "C:\Program Files\Git\cmd\git.exe" status -sb` (Worktree: `... worktree add .worktrees/<branch> -b <branch>`).
- **와이어 프로토콜 계약 검증**: `python tools/verify_contracts.py` (18 활성 사양서·144 코드/설정 린트, 0 errors).
- **정적 배선 및 도달성 검증**: `python tools/verify_runtime_wiring.py` (13 활성 서브시스템 0 violations, 4 예외).
- **실부팅 스모크 테스트**: `python tools/run_boot_smoke.py --clean-orphans` (13개 활성 `main.lua` 13/13 PASS).
- **Lua 단위 테스트**: `python tools/run_unit_tests.py --require-tests --clean-orphans` (15개 타겟 655/655 PASS).
- **Lua E2E 시뮬레이션 테스트**: `python tools/run_e2e_tests.py --clean-orphans [--profile <out.json> --check-baseline]` (10개 스위트 23/23 PASS, 566패킷 계약 0 violations).
- **아키텍처 감사·가드**: `python -m tools.audit {registry|static|dupes|specs|split|guard|all}` (`guard`: 루트 `installer.lua` 단일 SSOT·복제본 차단 Fail, 신규 `>46KB`·미소비 필드 Warn; `config/audit_baselines.json`).
- **돌연변이 살상 테스트**: `python tools/run_mutation_tests.py` (25/25 KILLED, 100.0% 살상률, 기준 90.0%).
- **하네스 자체 회귀**: `python -m unittest discover -s tests/harness -p "test_*.py"` (157/157 PASS).
- **컨텍스트 문서 정합성**: `python tools/verify_context_docs.py` (0 findings, 규칙 R1~R9).
- **사양서·문법·매니페스트 정적 검사**: `python tools/verify_manifest_sync.py --strict-gdrive-packages` (0 Errors, 0 Warnings; 135 GDrive 엔트리), `python tools/verify_all_specs.py --check-readmes` (17대 사양서 0 Errors, 0 Warnings), `python tools/validate_lua_syntax.py` (139 파일), `python tools/verify_spec_status.py` (18종 14 Implemented, 4 Approved PASS), `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py` (30/30 PASS).
- **GDrive 배포 & Live Bridge**: `python tools/sync_gdrive.py {stage|sync|status|verify}` (`sync --dry-run` 선행), `python tools/gcs_live_bridge.py --port 8765 [--lan]`.

## 4. Gotchas & Invariants
- **멀티 코드베이스 독립 완결성**: `src/<layer>/<name>/` 간 공용 모듈 직접 참조 금지 (개별 CC 컴퓨터 루트 마운트 단위 캡슐화, 기본 진입점 `main.lua`). 예외는 인스톨러가 `/lib/`에 주입하는 `/lib/avionics_sensors.lua`와 `/lib/ota_agent.lua` 2종.
- **CC:Avionics 센서 공용 라이브러리**: `/lib/avionics_sensors.lua`로 자동 주입되며 `require("avionics_sensors")`로 로드 (`velocity_sensor`, `altitude_sensor`, `gimbal_sensor`, `physics_assembler` 4종 SSOT).
- **통합 인스톨러 배포 삼총사**: 화면 직접 업로드 `/installer.lua`, 플로피 `/disk/installer.lua`, 원격 `wget run <url>`. GitHub raw / Google Drive 이중 다운로드 지원.
- **CraftOS-PC 런타임 의존성**: `tools/run_unit_tests.py` 및 `tools/run_e2e_tests.py`는 `CraftOS-PC_console.exe` 설치 필요 (`CRAFTOS_PC_EXE` 환경변수 지정 가능).
- **PowerShell 5.1 체이닝**: 기본 셸은 Windows PowerShell 5.1이며 `&&` 미지원 → `; if ($?) { ... }` 사용.
- **전역 RF 스펙트럼 및 40채널 규격**: 기체 $Base = 10000 + (N-1) \times 40$ ($N=1\sim 1000$, `10000~49999`): Zone 1(`0` C2/프로브, `1` `QUATERNION_RATE`, `2` 텔레메트리, `3` MFD/ACRO 우선권, `4` `AMM<->FCP` `CH_TRAJECTORY_CMD`, `5` `GPS` 응답, `8` `CH_CALIBRATION_INIT`, `9` `CH_EMERGENCY_CORE` `E_STOP`), Zone 2(`10` TCA, `11` ASA `MSG_AERO_*`), Zone 3(`20~39` 탑재체·특수 임무 확장; 편대 `TBD` 광역 데이터링크 이관). `AMM`은 외부 RF(`CH 50000~50004`, `CH 60001/60002`, `Base_sec+*`) 전담, `FCP`는 `Base+4/+2/+1` 3채널 + `Base+9` E_STOP만 사용; 격납고(`101~200`), GCS/관제(`50000~59999`), GPS(`60001~60020`).
- **Zero-Fallback & 영구 단일 경로**: 수신단 듀얼키 폴백 금지(구 필드는 사양서 `[DEPRECATED]` 표기); 사양서는 디렉토리 이동 없이 상단 메타데이터 표로만 상태를 전이한다.
- **`ion_thruster` 충돌 조정**: `Create Propulsion: Simulated`의 `ion_thruster` 페리페럴은 허용하며, 금지 규칙은 `kontraption:` 네임스페이스만 차단한다.
- **온보드 제어기 20Hz 헤드리스 원칙**: VAS/TCA/ASA는 터미널 UI 블로킹 방지를 위해 헤드리스가 기본이며, 디버그 TUI는 `config.json`의 `debug: true` 시 비동기(`parallel`)로만 격리 구동한다.
- **멀티노드 E2E 시뮬레이션 원칙**: 가상 버스/샌드박스 기반 멀티노드 테스트는 각 노드의 고유 `_ENV` 격리 및 채널 배타성을 준수하며, 테스트 종료 시 `os.shutdown()` 핸드셰이크를 수행한다.
- **컨텍스트 문서 Stop 훅**: `.agent/hooks.json`이 작업 종료 시 `verify_context_docs` 위반을 검사해 재개시킨다 (동일 위반 2회 상한, 오류 시 종료 허용; `git-guardrails`가 `git.exe` 포함 위험 명령 차단).
