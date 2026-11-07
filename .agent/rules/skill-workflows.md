---
trigger: always_on
description: 작업 단계별 스킬 발동·오발동 차단 게이트 및 파괴적 Git 명령 상시 금지 규칙
---

# Skill Workflow & Scope Gating Rules

본 규칙은 전역 플러그인(`using-superpowers` 등)의 포괄적 스킬 호출보다 우선 적용된다. 아래 작업 단계에 해당할 때만 지정된 스킬을 열람·발동하며, 제외 조건에 해당하면 스킬 `SKILL.md`를 읽지 않는다.

## 1. 상시 안전 가드 (Git Guardrails)
- 사용자의 명시적 지시 없이는 파괴적 Git 명령(`git push` 및 `--force`, `git reset --hard`, `git clean -f`/`-fd`, `git branch -D`, `git checkout .`, `git restore .`)을 실행하지 않는다.

## 2. 작업 유형별 스킬 발동 게이트 (Hard Gating)
- **단순 대화 / 개념·API 질문 / 채팅 인라인 예시 코드**:
  - 코딩·TDD·검증·리뷰·VCS·`md-management` 스킬 **호출 금지** (`AGENTS.md` 및 `GEMINI.md`만으로 즉시 응답).
- **아키텍처·기능 설계 (`/plan`, `/grill-me`)**:
  - `domain-aeronautics.md`(금지 모드 체크)만 참조. 구현 승인 전까지 `test-driven-development`, `lua`, `computercraft-lua`, `code-simplifier`, `pr-review-toolkit`, `verification-before-completion`, `md-management` **호출 금지**.
- **문서·규칙·설정 일반 편집 (설정 파일, 비사양서 `.md`, `.json`, `.gitignore`)**:
  - `test-driven-development`, `lua`, `computercraft-lua` **호출 금지**.
- **사양서·ICD·프로토콜 단독 편집 및 정합성 감사 (`docs/system/*.md`, `docs/specs/**/*.md`)**:
  - `specification-lifecycle-manager` **필수 호출**. SSOT 위계 준수, 6대 영역 동기화, Zero-Fallback 명세, Spec-to-Code Impact Report 생성.
  - 사양서 파일 내 실행 코드 작성 금지(의사코드·스키마만 허용). `test-driven-development`, `lua`, `computercraft-lua` **호출 금지**.
- **사양서와 코드베이스 동시 수정 요청 인입 시 (Mixed-Scope)**:
  - `specification-lifecycle-manager` **Mixed-Scope Safety Interlock** 즉시 발동. 파일 수정 전 **즉시 중단(Hard Stop)**하고 경고 및 유저에게 진행 방향(Option 1: Spec-First, Option 2: Sequential, Option 3: Codebase-Only) 질의.
- **버전 관리 및 릴리스**:
  - `.git`이 존재하고 격리 브랜치/워크트리 작업에 착수할 때만 `using-git-worktrees` 호출.
  - 버전 배포용 `CHANGELOG.md`·릴리스 노트 작성 요청 시에만 `writing-changelogs` 호출 (일상 컨텍스트 유지는 `md-management`가 담당).
- **프로덕션 코드 작성 및 수정 (Authoring — Red/Green)**:
  - 저장소 내 실제 프로덕션 코드 파일 수정 직전에만 `test-driven-development` + `ponytail` 호출 (단, Phase 0 테스트 러너 최초 부트스트랩 시 TDD Red-Green 대신 셀프 스모크 실행 적용).
  - 사양서 기반 구현 시 해당 사양서가 `docs/specs/approved/`에 위치하는지 선행 확인한다.
  - `.lua` 작업 시 역할 분담: CC:Tweaked API·페리페럴·이벤트 연동은 `computercraft-lua`(필요한 `references/` 파일만 선별 열람), 순수 Lua 구조·메타테이블·최적화는 `lua` 호출. Python(`.py`) 작업 시 두 Lua 스킬 호출 금지.
  - 초기 작성(Red/Green) 중에는 `code-simplifier`, `pr-review-toolkit` 동시 호출 금지.
- **리팩토링 및 코드 리뷰 (Refactor & Review)**:
  - 동작 통과(Green) 직후 구조 정제 또는 리팩토링 요청 시: `code-simplifier` + `ponytail`(가지치기).
  - 코드 리뷰 요청 또는 커밋/PR 전 `.lua` 감사 시: `pr-review-toolkit` (+ API 시그니처 대조 시 `computercraft-lua`, 언어 최적화 대조 시 `lua`).
- **작업 완료 보고 및 마일스톤 인계 (Completion & Context Sync)**:
  - 실제 코드·설정·테스트 변경 완료 주장 직전에만 `verification-before-completion` 호출.
  - 사양서 기반 작업인 경우 검증 통과 후 작업 완료 선언 직전에 사양서를 `docs/specs/approved/`에서 `docs/specs/implemented/`로 자동 이동한다.
  - 아키텍처·디렉토리·표준 명령어·Phase가 바뀐 마일스톤 완료 시에만 `md-management`를 호출해 `GEMINI.md` 스냅샷과 `.agent/memory/<dir>.md`를 갱신한다.

## 3. 사양서 생명주기 가드레일 (Spec Lifecycle Guardrails)
- **사양서 수정 발생 시 (Revision Protocol)**:
  - 이미 구현 완료(`implemented/`)된 사양서를 수정할 경우, `drafts/`를 거치지 않고 즉시 계층 경로를 유지한 채 `docs/specs/approved/`로 이동한다.
  - 사양서 상단에 '수정 이력(Revision History)' 테이블(버전, 일자, 변경 요약, 변경 사유)을 필수로 작성/갱신한다.
- **신규 사양서 작성 시 (Drafting Protocol)**:
  - 신규 기획안만 `docs/specs/drafts/`에서 시작하며, 요구사항 및 제약 검토 완료 시 `approved/`로 이동한다.
- **코드베이스 구현 착수 전 (Pre-implementation Check)**:
  - 코드베이스 구현 및 수정 작업은 대상 사양서가 `approved/` 디렉토리에 존재하는 상태에서만 착수한다.
- **코드베이스 반영 완료 시 (Completion Protocol)**:
  - 사양서의 변경 사항이 코드베이스에 완전히 적용되고 `verification-before-completion` 검증(문법/단위 테스트 증거 확보)을 통과하면, 완료 보고 직전에 사양서를 `approved/`에서 `implemented/`로 자동 이동시킨다.
- **경로 보존 원칙**:
  - 상태 디렉토리(`drafts/`, `approved/`, `implemented/`, `archived/`) 간 이동 시 계층 서브디렉토리 경로(예: `1_control/vas/`, `2_guidance/sas/`)를 동일하게 유지한다.
