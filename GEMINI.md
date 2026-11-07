<!-- living-context: Snapshot managed by md-management skill. In-place replace only (strictly <= 80 lines). Append historical logs to .agent/memory/<dir>.md instead. -->
# Create_Aeroneutics — Living Project Context

## 1. Current Phase & Active Handover
- **현재 단계**: **Phase 0** — 기체 40채널 전면 확장, 지상 설비(`0_infra`) 통합 및 SAS → FCP 명칭 전면 개정 완료.
- **직전 완료**: SAS를 FCP(Flight Control Program)로 전면 개정(`docs/specs/2_guidance/fcp/`, `src/2_guidance/fcp/`, `tests/2_guidance/fcp/`), 런타임 식별자(`source`/`activeSource`=`FCP`) 동기화, 사양서 12종 및 마스터 ICD 개정 이력/링크 동기화, `scratch/verify_all_specs.py`(0 Errors, 0 Warnings) 및 단위 테스트(6/6 PASS).
- **다음 착수 후보**:
  1. 기체 5대 핵심 모듈(`src/` — VAS, TCA, FCP, Alignment, GPS) 통신 채널·Zone 런타임 코드 동기화 구현.
  2. 원격 푸시(`git push -u origin main`) 사용자 인증 완료 확인.
  3. CC:Tweaked 하네스 검증 파이프라인(정적 검사·단위 모킹·CraftOS-PC 헤드리스 연동) 설계.

## 2. Confirmed Architecture & Paths
- `TASK.md`: 유저-에이전트 장기 작업 추적 및 로드맵 SSOT (계획 수립·작업 완료 시 후속 태스크 필수 갱신).
- `AGENTS.md`: 불변 행동 헌장 (`attention-span` × `caveman` 하이브리드 + `no-overclaim`). **사전 diff 승인 없이 수정 금지**.
- `GEMINI.md`: 작업 간 동적 컨텍스트 스냅샷 (4개 고정 섹션 덮어쓰기, **80줄 상한**).
- `docs/system/`: 마스터 ICD 및 시스템 전역 구조도 보관 (`specification-lifecycle-manager` SSOT Tier 1 & 2, 위치 고정).
- `docs/specs/`: 기능 도메인 단일 계층(`docs/specs/<domain>/<subsystem>/`), 상단 메타데이터 표(`Draft`/`Approved`/`Implemented`/`Deprecated`) 기반 생명주기 관리.
- `harness/`: CC:Tweaked Peripheral & Rednet Mock 프레임워크 (`harness/unit/`).
- `tests/`: 코드베이스별 단위 테스트 슈트 (`tests/{0_development,0_infra,1_control,2_guidance,harness}/`).
- `tools/`: 단위 테스트 러너 CLI (`tools/run_unit_tests.py`).
- `reports/`: 버그·리팩토링 검토 보고서 (`underReview/`, `reviewCompleted/` — 사양서·메모리 스킬 비발동).
- `src/`: 독립 멀티 Lua 코드베이스 (`0_development/alignment`, `0_infra/{gps,gac,docking_arm,landing_pad,runway}`, `1_control/{vas,tca,asa}`, `2_guidance/fcp`, `3_planning/`, `4_mission/`).
- `.worktrees/`: Git Worktree 격리 작업 영역 (`.gitignore` 등록 완료).
- `.agent/memory/`: 디렉토리별 과거 의사결정·변경 이력 온디맨드 보관소 (`workspace-root.md` 등).
- `.agent/rules/`:
  - `skill-workflows.md` (`always_on`): 단계별 스킬 발동·오발동 차단 게이트 및 파괴적 Git 명령 금지.
  - `domain-aeronautics.md` (`model_decision`): Valkyrien Skies 차단 및 Create/Avionics/Radars/Propulsion/Advanced Peripherals 허용 명세.
  - `cc-tweaked-runtime.md` (`model_decision`): CC:Tweaked Lua 5.2 Cobalt 런타임 제약.
- `.agent/skills/`: 온디맨드 전문 스킬 13종 (`specification-lifecycle-manager` 신규 이식 포함).

## 3. Standard Commands
- **버전 관리**: Git (`git status`, `git branch`, `git worktree add .worktrees/<branch> -b <branch>`).
- **하네스/테스트 러너**: `python tools/run_unit_tests.py` (멀티 코드베이스 단위 테스트 러너, 16/16 PASS).
- **검증 도구**: `python scratch/verify_all_specs.py` (사양서 12종 전수 무결성 검증기), `python scratch/validate_lua_syntax.py` (문법 정적 분석).

## 4. Gotchas & Invariants
- **루트 문서 이중 로드 주의**: Antigravity는 `AGENTS.md`와 `GEMINI.md`를 매 턴 모두 로드하므로 두 파일 간 중복 문구를 두지 않는다.
- **기체 통신 채널 대역폭**: $BW=40$ ($Base = 10000 + (N-1) \times 40$). Zone 1(0~9), Zone 2(10~19 구동계), Zone 3(20~29 탑재체), Zone 4(30~39 편대링크).
- **Zero-Fallback 원칙**: 수신단에 듀얼키 폴백 금지. 송신단 즉각 패치, 구버전 명칭은 사양서 내 `[DEPRECATED]` 배지로 보존.
- **영구 단일 경로 불변 원칙**: 사양서는 상태 변화에 따라 디렉토리를 이동하지 않으며, 상단 메타데이터 표에서 생명주기를 관리하여 상대 링크 영구 안정성을 유지한다.
- **`ion_thruster` 충돌 조정**: `Create Propulsion: Simulated`의 `ion_thruster` 페리페럴은 허용하며, 금지 규칙은 `kontraption:` 네임스페이스만 차단한다.
