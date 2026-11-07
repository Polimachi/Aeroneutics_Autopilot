# Workspace Root Memory Archive

본 문서는 `Create_Aeroneutics` 루트 및 하네스 기반 구조의 주요 의사결정 이력을 최신순(ISO 날짜)으로 기록하는 온디맨드 아카이브입니다.

---

## 2026-11-07 — 기체 통신 40채널 전면 확장 및 12대 핵심 사양서 전수 리팩토링·검증 완료

- **결정 배경**: 과거 20채널 협소 대역폭($BW=20$) 및 구동계 채널(`Base+6`, `Base+7`) 밀집 한계를 극복하고, 구동계/탑재체/편대 데이터링크를 10채널 단위 4대 Zone으로 체계화하기 위해 기체 채널 대역폭을 $BW=40$으로 전면 확장함.
- **반영 내역**:
  1. **대역폭 및 4대 Zone 확립**: $Base = 10000 + (N-1) \times 40$ ($N=1\sim 1000$).
     - Zone 1 (0~9): 코어 C2/센서/유도/텔레메트리
     - Zone 2 (10~19): 구동계 전용 — TCA 추진기 `Base+10` (구 `Base+6` [DEPRECATED]), ASA 조종면 `Base+11` (구 `Base+7` [DEPRECATED])
     - Zone 3 (20~29): 탑재체 전용 버스
     - Zone 4 (30~39): 편대 데이터링크
  2. **12대 사양서 전수 리팩토링**:
     - Tier 1 마스터 ICD, Tier 2 관계도/패킷도, Tier 3 10종 사양서 전역에 40채널 수식 및 Zone 할당 동기화.
     - 런타임 코드 수정 대상 5대 사양서(VAS, TCA, SAS, Alignment, GPS)를 `implemented/`에서 `approved/`로 승격 이동.
     - 8대 주요 사양서에 SemVer 판올림 및 `Revision History` 테이블 신규 작성·누적.
     - Zero-Fallback & `Sender-Immediate-Patch` 원칙 적용: 사양서 내 구버전 명칭은 `[DEPRECATED]` 배지로 보존.
  3. **무결성 전수 검증 (`scratch/verify_all_specs.py`)**:
     - 12개 사양서 상대 링크(0 Broken), Stale `implemented/` 링크(0건), Revision History 존재성, 폐기 문자열 중첩 여부, 미폐기 Base+6/7 여부, 40채널 수식 정합성, Mermaid 구문 유효성을 자동 검사하여 **0 Errors, 0 Warnings** 전수 통과 확인.


## 2026-11-07 — 사양서·문서·완료 스킬군 적용 범위 분리 및 전역 기획 스킬 오발동 차단

- **결정 배경**: 12종 사양서 및 `specification-lifecycle-manager` 이식 직후, 일반 Q&A·`/plan` 아티팩트·`reports/` 보고서·`drafts/` 초안 편집 및 코드 검증 완료 후 `approved/`→`implemented/` 승격 시 스킬 오발동이나 Mixed-Scope Hard Stop 충돌이 발생할 수 있어 관할 경계를 재정립함.
- **반영 내역**:
  1. **`specification-lifecycle-manager` 경로 × 행위 이중 게이트**: `docs/system/*.md` 및 `docs/specs/{approved,implemented}/**/*.md`(`README.md`·`drafts/`·`archived/`·`reports/` 제외)의 생성·수정·폐기·명시적 감사 시에만 발동하며, 읽기 전용 참조·Q&A·`/grill-me`·`/plan` 아티팩트에서는 비발동으로 고정.
  2. **양방향 동기화 디렉토리 판정 및 메타데이터 규칙**: `src/` 런타임 코드 수정이 필요한 Tier 3 사양서만 `approved/`로 이동하고 단순 상대 링크·버전 배지만 갱신된 사양서는 `implemented/` 유지; 상단 SemVer 인용구를 기본 유지하되 실질 스펙 변경(`approved/` 이동 대상) 시에만 `Revision History` 테이블 신설·누적.
  3. **코드 완료 승격 경량 예외 (`verification-before-completion`)**: 검증 통과 직후 `approved/`→`implemented/` 파일 이동 및 `docs/` 내 상대 링크 치환은 Mixed-Scope 중단에서 면제하고 `specification-lifecycle-manager` 호출 없이 완료 게이트에서 직접 처리.
  4. **인접 로컬 스킬 분리 및 전역 플러그인 차단**: `md-management`(`AGENTS.md`·`GEMINI.md`·`.agent/memory/`), `writing-changelogs`(`CHANGELOG.md`)의 배타적 관할을 명시하고, `skill-workflows.md`에서 전역 `superpowers`의 `using-superpowers`·`brainstorming`·`writing-plans`·`executing-plans` 자동 호출을 차단함.

## 2026-11-07 — Git 형상 관리 시작 및 Worktree 격리 환경 구축

- **결정 배경**: 프로젝트의 지속적인 변경 추적, 다중 브랜치 병렬 작업(Worktree), 안전한 원격 협업을 위해 Git 버전 관리 체계를 정식 도입함.
- **반영 내역**:
  1. **Git 저장소 초기화**: `main` 기본 브랜치로 초기화(`git init -b main`)하고 작성자(`Polimachi` / `abovepolaris110@gmail.com`) 및 `credential.helper manager` 등록.
  2. **Worktree 격리 경로 확보**: `using-git-worktrees` 표준에 맞춰 `.worktrees/` 및 `worktrees/`를 `.gitignore`에 추가하여 격리 브랜치 작업물이 메인 트리에 오인 커밋되지 않도록 보장.
  3. **원격 저장소 연동**: GitHub 원격 저장소(`https://github.com/Polimachi/Aeroneutics_Autopilot.git`)를 `origin`으로 등록.
  4. **Phase 0 기준선 커밋**: 사양서 12종, GPS 및 제어 소스, 에이전트 규칙/스킬 등 131개 파일(20,342 LOC)을 포함하는 초기 기준선 커밋 생성.


## 2026-11-07 — 사양서 생명주기 하네스 규칙 개정 (수정 시 approved 직행 / 검증 완료 시 implemented 이동)

- **결정 배경**: 사양서가 수정되었을 때 구현 전 단계(`approved/`)로 즉시 이동시키고, 코드베이스에 반영 및 검증이 완료되었을 때 구현 완료 단계(`implemented/`)로 자동 전환하는 규칙을 하네스 시스템에 강제하고자 함.
- **반영 내역**:
  1. **가이드 문서 개정 (`docs/specs/README.md`)**:
     - 4단계 상태 전이 흐름도 추가 (`drafts` 신규 기획 → `approved` 구현 대기·수정 직행 → `implemented` 구현 완료 → `archived` 폐기/대체).
     - 수정 발생 시 `drafts/`를 거치지 않고 `approved/`로 직행 이동 및 계층 디렉토리 경로 보존 원칙 명시.
     - 사양서 상단에 `Revision History`(버전, 일자, 변경 요약, 변경 사유) 필수 작성 표준 확립.
  2. **에이전트 규칙 반영 (`.agent/rules/skill-workflows.md`)**:
     - `사양서 생명주기 가드레일` 신설: 프로덕션 코드 작성 전 `approved/` 확인, 작업 완료 전 `verification-before-completion` 통과 후 `implemented/` 자동 이동 강제.
  3. **컨텍스트 스냅샷 동기화**: `GEMINI.md`에 사양서 생명주기 상태 갱신.

## 2026-11-07 — 15종 역할별 스킬·규칙 설치 및 3계층 메모리 체계 확립

- **결정 배경**: 전역 `using-superpowers` 환경에서 단순 대화 중 `TDD`·`검증` 스킬이 오발동하거나 대용량 스킬 열람으로 컨텍스트가 낭비되는 문제를 막고, 세션 간 프로젝트 맥락을 유지할 체계가 필요했음.
- **반영 내역**:
  1. **3계층 컨텍스트 분리**: `AGENTS.md`(불변 행동 원칙, 사전 승인 필수) / `GEMINI.md`(80줄 상한 현재 상태 스냅샷, 마일스톤 비대칭 즉시 갱신) / `.agent/memory/<dir>.md`(온디맨드 누적 이력, 코드 마운트 오염 방지).
  2. **Rule 3종 + Scoped Skill 12종 정비**: `skill-workflows.md`(`always_on`)로 단순 대화·설계 중 구현 스킬 호출을 차단하고, 전역 동명 스킬 3종(`TDD`, `verification-before-completion`, `using-git-worktrees`)을 로컬 음성 가드로 Override함.
  3. **`computercraft-lua` 분할 및 도메인 정합화**: 839줄 원본을 `SKILL.md` + `references/` 4종으로 분할하고, `Create Propulsion: Simulated`의 `ion_thruster`와 `Lua-Harness` 금지 목록 간 충돌을 해소(`kontraption:` 네임스페이스만 차단)함.

## 2026-11-07 — 하네스 밑바닥 재구축을 위한 Phase 0 클린 캔버스 초기화

- **결정 배경**: 초기 스캐폴딩에서 임의로 생성된 임시 코드·테스트·러너(`src/`, `tests/`, `tools/` 등)가 하네스 아키텍처 설계에 선입견과 제약을 줄 수 있어 초기화를 결정함.
- **반영 내역**: 비규칙 폴더 전체 및 구 `harness-verification.md`를 제거하고 도메인·런타임 불변 규칙만 보존한 Phase 0 상태로 리셋함.

## 2026-11-06 — Create_Aeroneutics 독립 워크스페이스 출범

- **결정 배경**: 기존 `Antigravity_Workspace`(`Lua_Harness`, `TAP`, `GPS`, `UAP` 등)의 컨텍스트 영향 없이 CC:Tweaked 기반 Create: Aeronautics 코드를 클린 룸에서 개발하기 위해 별도 루트를 생성함.
