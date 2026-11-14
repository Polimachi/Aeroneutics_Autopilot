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
  - **활성 사양서·ICD 편집 및 명시적 감사** (`docs/system/*.md`, 활성 `docs/specs/**/*.md` — Status: `Draft` 및 `README.md` 제외): `specification-lifecycle-manager` **단독 호출** (`md-management`, `writing-changelogs`, `test-driven-development`, `lua`, `computercraft-lua` 호출 금지; 사양서 내 실행 코드 작성 금지).
  - **초안 사양서, 분석 보고서 및 일반 설정·메타 문서 편집** (Status: `Draft` 사양서, `docs/specs/README.md`, `reports/**`, `.agent/**` — `.agent/memory/*.md` 제외, 루트/하위 `README.md`, `.json`, `.gitignore`): `specification-lifecycle-manager`, `md-management`, `test-driven-development`, `lua`, `computercraft-lua` **호출 금지**.
  - **프로젝트 컨텍스트·메모리 관리** (`AGENTS.md`, `GEMINI.md`, `.agent/memory/*.md`): `TASK-ID` 완료, 마일스톤 인계 또는 명시적 감사 요청 시 `md-management` **단독 관할**.
  - **배포 릴리스 노트** (`CHANGELOG.md`): 버전 릴리스 시 `writing-changelogs` **단독 관할**.
- **활성 사양서와 코드베이스 동시 수정 요청 인입 시 (Mixed-Scope)**:
  - `docs/system/*.md` 또는 활성 `docs/specs/**/*.md`의 스펙 변경과 `src/` 코드 수정을 한 작업에서 동시 요청받으면 `specification-lifecycle-manager`의 **Mixed-Scope Safety Interlock**을 즉시 발동하여 파일 수정 전 **중단(Hard Stop)**하고 진행 방향(Option 1: Spec-First, Option 2: Sequential, Option 3: Codebase-Only)을 질의한다.
- **버전 관리**:
  - `.git`이 존재하고 격리 브랜치/워크트리 작업에 착수할 때만 `using-git-worktrees` 호출.
- **프로덕션 코드 작성 및 수정 (Authoring — Red/Green)**:
  - 저장소 내 실제 프로덕션 코드 파일 수정 직전에만 `test-driven-development` + `ponytail` 호출 (단, Phase 0 테스트 러너 최초 부트스트랩 시 TDD Red-Green 대신 셀프 스모크 실행 적용).
  - 사양서 기반 구현 시 대상 사양서의 상단 메타데이터 표 상태가 `Approved`인지 선행 확인하며, 코드 작성을 위한 사양서 **읽기 전용 참조 시 `specification-lifecycle-manager`를 호출하지 않는다**.
  - `.lua` 작업 시 역할 분담: CC:Tweaked API·페리페럴·이벤트 연동은 `computercraft-lua`(필요한 `references/` 파일만 선별 열람), 순수 Lua 구조·메타테이블·최적화는 `lua` 호출. Python(`.py`) 작업 시 두 Lua 스킬 호출 금지.
  - **WebUI 미션 에디터 HTML 작업 한정 (`tools/amm_mission_editor.html` / `AMM_MISSION_EDITOR_SPECIFICATION.md` 전용)**: `frontend-design`(레이아웃·시각 설계·CSS/Canvas 정제) 및 `web-design-guidelines`(접근성·포커스·폼·키보드 UI 감사)는 **오직 `tools/amm_mission_editor.html` 및 그 상세 규격서(`AMM_MISSION_EDITOR_SPECIFICATION.md`) 작업 시에만** 호출한다. 그 외 `.lua`, `.py`, 타 도메인 사양서 및 일반 문서 작업에서는 호출을 **영구 금지**한다.
  - 초기 작성(Red/Green) 중에는 `code-simplifier`, `pr-review-toolkit` 동시 호출 금지.
- **리팩토링 및 코드 리뷰 (Refactor & Review)**:
  - 동작 통과(Green) 직후 구조 정제 또는 리팩토링 요청 시: `code-simplifier` + `ponytail`(가지치기).
  - 코드 리뷰 요청 또는 커밋/PR 전 `.lua` 감사 시: `pr-review-toolkit` (+ API 시그니처 대조 시 `computercraft-lua`, 언어 최적화 대조 시 `lua`).
- **작업 완료 보고 및 마일스톤 인계 (Completion & Context Sync)**:
  - 실제 코드·설정·테스트 변경 완료 주장 직전에만 `verification-before-completion` 호출.
  - 사양서 기반 코드 구현이 검증을 통과하면 **Mixed-Scope 중단 예외(경량 완료 전이)**로서 `specification-lifecycle-manager`를 호출하지 않고, 대상 사양서 상단 메타데이터 표의 `문서 상태`를 `Implemented`로 갱신하고 `최종 수정일`을 당일 날짜로 동기화한다.
  - `TASK-ID` 완료 시 `md-management`를 호출해 `.agent/memory/<dir>.md`에 `TASK-ID`를 포함한 이력 항목을 추가한다(`verify_context_docs.py` R8). `GEMINI.md` 스냅샷은 Phase·디렉토리·표준 명령어·핵심 아키텍처 불변식이 바뀐 마일스톤 완료 시에만 갱신한다.
  - 작업 계획 생성 시 및 작업 완료 후 후속 과제 도출 시 `TASK.md`에 신규/후속 태스크를 즉시 등록하고 진행 상태(`[ ]`, `[-]`, `[x]`)를 동기화한다.
  - 작업 완료 직전 `python tools/verify_context_docs.py`로 컨텍스트 문서 정합성을 확인한다. `.agent/hooks.json`의 `Stop` 훅이 위반 시 턴 종료를 보류한다 (동일 위반당 최대 2회).

## 3. 사양서 생명주기 가드레일 (Spec Lifecycle Guardrails)
- **사양서 수정 및 양방향 동기화 시 (Revision Protocol)**:
  - 활성 사양서 수정 시 `specification-lifecycle-manager` 규칙에 따라 `docs/system/*.md` 및 활성 `docs/specs/**/*.md`(Status != `Draft`) 간 양방향 동기화를 수행한다.
  - `Implemented` 사양서 중 요구사항·패킷 스키마·채널·파라미터 변경으로 **`src/` 런타임 코드 수정이 필요한 사양서만** 상단 메타데이터 표의 `문서 상태`를 `Approved`로 전이하고 `최종 수정일` 갱신 및 `Revision History` 테이블(버전, 일자, 변경 요약, 변경 사유)에 행을 추가한다. 단순 상대 링크나 참조 버전 배지만 갱신된 연관 사양서는 `Implemented` 상태를 유지한다.
- **신규 및 폐기 사양서 전이 시 (Drafting & Deprecation Protocol)**:
  - 신규 기획안은 대상 도메인 디렉토리에 직접 `문서 상태`: `Draft`로 작성하며(`specification-lifecycle-manager` 비발동), 검토 완료 후 `Approved`로 상태를 승격할 때 `specification-lifecycle-manager`로 전역 동기화를 수행한다.
  - 사양서 폐기 시 상단 메타데이터 표의 `문서 상태`를 `Deprecated`로 변경하고, `specification-lifecycle-manager`로 활성 문서 내 참조 정리 및 대체 규격 명시를 수행한 뒤 Zero-Fallback 원칙을 엄수한다.
- **코드베이스 구현 및 완료 승격 시 (Pre-implementation & Completion Protocol)**:
  - 코드베이스 구현 및 수정은 대상 사양서의 `문서 상태`가 `Approved`인 상태에서 착수한다.
  - `verification-before-completion` 검증 통과 직후 완료 보고 전에 사양서 상단 메타데이터 표의 `문서 상태`를 `Implemented`로 자동 갱신하고 `최종 수정일`을 동기화한다 (`specification-lifecycle-manager` 비호출, Mixed-Scope 면제).
- **영구 경로 불변 원칙 (Permanent Unified Path)**:
  - 사양서는 생명주기 전이에 따라 디렉토리를 이동하지 않으며, `docs/specs/<domain>/<subsystem>/` 경로를 영구 유지하여 문서 간 상대 마크다운 링크 깨짐을 방지한다.
