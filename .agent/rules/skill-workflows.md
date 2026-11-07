---
trigger: always_on
description: 작업 단계별 스킬 발동·오발동 차단 게이트 및 파괴적 Git 명령 상시 금지 규칙
---

# Skill Workflow & Scope Gating Rules

본 규칙은 전역 플러그인(`superpowers` 등)의 포괄적 스킬 호출보다 우선 적용된다. 아래 작업 단계에 해당할 때만 지정된 스킬을 열람·발동하며, 제외 조건에 해당하면 스킬 `SKILL.md`를 읽지 않는다.

## 1. 상시 안전 및 전역 플러그인 차단 가드 (Global Guardrails)
- **Git 파괴 명령 금지**: 사용자의 명시적 지시 없이는 파괴적 Git 명령(`git push` 및 `--force`, `git reset --hard`, `git clean -f`/`-fd`, `git branch -D`, `git checkout .`, `git restore .`)을 실행하지 않는다.
- **전역 `superpowers` 기획·메타 스킬 자동 호출 금지**: 사용자가 스킬명을 직접 지목하지 않는 한 전역 플러그인의 `using-superpowers`, `brainstorming`, `writing-plans`, `executing-plans`는 열람·호출하지 않는다. 설계 인터뷰는 네이티브 `/grill-me`, 구현 계획은 네이티브 `/plan`, 활성 사양 관리는 로컬 `specification-lifecycle-manager`로 일원화한다.

## 2. 작업 유형별 스킬 발동 게이트 (Hard Gating)
- **단순 대화 / 개념·사양·API 질문 / 채팅 인라인 예시 코드**:
  - 코딩·TDD·검증·리뷰·VCS·`specification-lifecycle-manager`·`md-management` 스킬 **호출 금지** (`AGENTS.md`, `GEMINI.md` 및 필요한 대상 파일의 읽기 전용 열람만으로 즉시 응답).
- **아키텍처·기능 설계 (`/plan`, `/grill-me`)**:
  - `domain-aeronautics.md`(금지 모드 체크)만 참조. 구현 승인 전까지 `specification-lifecycle-manager`, `test-driven-development`, `lua`, `computercraft-lua`, `code-simplifier`, `pr-review-toolkit`, `verification-before-completion`, `md-management` **호출 금지** (`/plan`·`walkthrough` 아티팩트 작성 시에도 `specification-lifecycle-manager` 비발동).
- **문서 유형별 관할 스킬 분리 (Markdown & Config Dispatch)**:
  - **활성 사양서·ICD 편집 및 명시적 감사** (`docs/system/*.md`, `docs/specs/{approved,implemented}/**/*.md` — `README.md` 제외): `specification-lifecycle-manager` **단독 호출** (`md-management`, `writing-changelogs`, `test-driven-development`, `lua`, `computercraft-lua` 호출 금지; 사양서 내 실행 코드 작성 금지).
  - **초안·폐기 사양서, 분석 보고서 및 일반 설정·메타 문서 편집** (`docs/specs/{drafts,archived}/**`, `docs/specs/README.md`, `reports/**`, `.agent/**`, 루트/하위 `README.md`, `.json`, `.gitignore`): `specification-lifecycle-manager`, `md-management`, `test-driven-development`, `lua`, `computercraft-lua` **호출 금지**.
  - **프로젝트 컨텍스트·메모리 관리** (`AGENTS.md`, `GEMINI.md`, `.agent/memory/*.md`): 마일스톤 인계 또는 명시적 감사 요청 시 `md-management` **단독 관할**.
  - **배포 릴리스 노트** (`CHANGELOG.md`): 버전 릴리스 시 `writing-changelogs` **단독 관할**.
- **활성 사양서와 코드베이스 동시 수정 요청 인입 시 (Mixed-Scope)**:
  - `docs/system/*.md` 또는 `docs/specs/{approved,implemented}/**/*.md`의 스펙 변경과 `src/` 코드 수정을 한 작업에서 동시 요청받으면 `specification-lifecycle-manager`의 **Mixed-Scope Safety Interlock**을 즉시 발동하여 파일 수정 전 **중단(Hard Stop)**하고 진행 방향(Option 1: Spec-First, Option 2: Sequential, Option 3: Codebase-Only)을 질의한다.
- **버전 관리**:
  - `.git`이 존재하고 격리 브랜치/워크트리 작업에 착수할 때만 `using-git-worktrees` 호출.
- **프로덕션 코드 작성 및 수정 (Authoring — Red/Green)**:
  - 저장소 내 실제 프로덕션 코드 파일 수정 직전에만 `test-driven-development` + `ponytail` 호출 (단, Phase 0 테스트 러너 최초 부트스트랩 시 TDD Red-Green 대신 셀프 스모크 실행 적용).
  - 사양서 기반 구현 시 대상 사양서가 `docs/specs/approved/`에 위치하는지 선행 확인하며, 코드 작성을 위한 사양서 **읽기 전용 참조 시 `specification-lifecycle-manager`를 호출하지 않는다**.
  - `.lua` 작업 시 역할 분담: CC:Tweaked API·페리페럴·이벤트 연동은 `computercraft-lua`(필요한 `references/` 파일만 선별 열람), 순수 Lua 구조·메타테이블·최적화는 `lua` 호출. Python(`.py`) 작업 시 두 Lua 스킬 호출 금지.
  - 초기 작성(Red/Green) 중에는 `code-simplifier`, `pr-review-toolkit` 동시 호출 금지.
- **리팩토링 및 코드 리뷰 (Refactor & Review)**:
  - 동작 통과(Green) 직후 구조 정제 또는 리팩토링 요청 시: `code-simplifier` + `ponytail`(가지치기).
  - 코드 리뷰 요청 또는 커밋/PR 전 `.lua` 감사 시: `pr-review-toolkit` (+ API 시그니처 대조 시 `computercraft-lua`, 언어 최적화 대조 시 `lua`).
- **작업 완료 보고 및 마일스톤 인계 (Completion & Context Sync)**:
  - 실제 코드·설정·테스트 변경 완료 주장 직전에만 `verification-before-completion` 호출.
  - 사양서 기반 코드 구현이 검증을 통과하면 **Mixed-Scope 중단 예외(경량 완료 전이)**로서 `specification-lifecycle-manager`를 호출하지 않고, 사양서를 `docs/specs/approved/`에서 `docs/specs/implemented/`로 이동하며 `docs/system/` 및 `docs/specs/{approved,implemented}/` 내 깨진 상대 링크만 즉시 치환한다.
  - 아키텍처·디렉토리·표준 명령어·Phase가 바뀐 마일스톤 완료 시에만 `md-management`를 호출해 `GEMINI.md` 스냅샷과 `.agent/memory/<dir>.md`를 갱신한다.

## 3. 사양서 생명주기 가드레일 (Spec Lifecycle Guardrails)
- **사양서 수정 및 양방향 동기화 시 (Revision Protocol)**:
  - 활성 사양서 수정 시 `specification-lifecycle-manager` 규칙에 따라 `docs/system/` 및 `docs/specs/{approved,implemented}/` 간 양방향 동기화를 수행한다 (`drafts/`·`archived/`는 스캔 제외).
  - `implemented/` 사양서 중 요구사항·패킷 스키마·채널·파라미터 변경으로 **`src/` 런타임 코드 수정이 필요한 사양서만** `drafts/`를 거치지 않고 즉시 계층 경로를 유지한 채 `docs/specs/approved/`로 이동하며 상대 링크를 갱신한다. 단순 상대 링크나 참조 버전 배지만 갱신된 연관 사양서는 `implemented/`에 유지한다 (`docs/system/` 문서는 위치 고정).
  - 모든 활성 사양서는 상단 인용구(`> **문서 버전**: vX.Y.Z`, `> **최종 수정일**: YYYY-MM-DD`)를 기본 유지하되, **실질 스펙 변경(`approved/` 이동 대상)이 발생한 사양서에 한해** 상단 인용구 바로 아래에 `Revision History` 테이블(버전, 일자, 변경 요약, 변경 사유)을 신설·누적 기록한다.
- **신규 및 폐기 사양서 전이 시 (Drafting & Archiving Protocol)**:
  - 신규 기획안은 `docs/specs/drafts/`에서 자유롭게 작성하며(`specification-lifecycle-manager` 비발동), 검토 완료 후 `approved/`로 승격 배치할 때 `specification-lifecycle-manager`로 전역 동기화를 수행한다.
  - 사양서 폐기 시 `archived/`로 이동하고 `specification-lifecycle-manager`로 활성 문서 내 참조 정리 및 `[DEPRECATED]` 표기를 수행한 뒤, `archived/` 문서는 이후 동기화 스캔에서 영구 제외한다.
- **코드베이스 구현 및 완료 승격 시 (Pre-implementation & Completion Protocol)**:
  - 코드베이스 구현 및 수정은 대상 사양서가 `approved/`에 존재하는 상태에서 착수한다.
  - `verification-before-completion` 검증 통과 직후 완료 보고 전에 사양서를 `approved/` → `implemented/`로 자동 이동하고 `docs/` 내 상대 링크 경로(`approved` → `implemented`)를 치환한다 (`specification-lifecycle-manager` 비호출, Mixed-Scope 면제).
- **경로 보존 원칙**:
  - 상태 디렉토리(`drafts/`, `approved/`, `implemented/`, `archived/`) 간 이동 시 계층 서브디렉토리 경로(예: `1_control/vas/`, `2_guidance/sas/`)를 동일하게 유지한다.
