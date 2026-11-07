# Workspace Root Memory Archive

본 문서는 `Create_Aeroneutics` 루트 및 하네스 기반 구조의 주요 의사결정 이력을 최신순(ISO 날짜)으로 기록하는 온디맨드 아카이브입니다.

---

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
