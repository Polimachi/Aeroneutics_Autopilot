# TASK-015 실행 계획: 전 계층 코드베이스·신규 추가 모듈/프로그램 통합 플레이북 체계 구축

> **문서 상태**: Approved (수행 중)
> **생성일자**: 2026-11-20
> **대상 과제**: `TASK-015` (`TASK-010` + `TASK-011` 통합 확장)
> **목적**: 전 계층 코드베이스(`0_development`, `0_infra`, `1_control`, `2_guidance`, `3_planning`)와 신규 추가 모듈·프로그램(`installer`, `ota`, `sensors`, `runway`, `gcs_live_bridge`, `analyze_flight_log`, World Preset/Live Mode)을 망라한 15종 실전 운용 매뉴얼(`playbook/`)과 정적 무결성 검증 CLI(`tools/verify_playbooks.py`) 구축

---

## 1. 개요 및 설계 결정
- **작업 브랜치 및 범위**: 클린 `main` 워크스페이스에서 수행하며, 런타임 코드(`src/**`), 프로토콜 계약(`config/protocol_contracts.json`), GDrive 매핑(`config/gdrive_mapping.json`), 활성 사양서(`docs/system/**`, `docs/specs/**`)는 수정하지 않는다(`0 diff`).
- **표준 7대 필수 섹션 규격** (전 15종 플레이북에 번호·순서 1..7 고정 적용):
  1. `## 1. 서브시스템 개요 및 역할 (Overview & Role)`
  2. `## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)`
  3. `## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)`
  4. `## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)`
  5. `## 5. 소프트웨어 설치 방법 (Installation)`
  6. `## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)`
  7. `## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)`
- **수식·버전·금지어 가드레일**:
  - `AGENTS.md` Overclaim 금지어 사용 영구 금지.
  - `.agent/rules/domain-aeronautics.md` 금지 모드 식별자(`valkyrien`, `vs2`, `kontraption:`, `ship_api` 등) 사용 금지.
  - Rule 10 준수: 타 사양서/문서 마크다운 링크 옆에 인라인 버전 배지(`[SPEC.md](...) vX.Y.Z`)를 표기하지 않는다.

---

## 2. 단계별 세부 실행 절차

### Step 0: 작업 착수 상태 전환 및 계획서 아카이빙
1. `TASK.md`에서 `TASK-015` 상태를 `[ ]` → `[-]`로 전환한다.
2. 본 실행 계획서를 `docs/superpowers/plans/2026-11-20-task-015-unified-playbook-suite.md`에 저장한다.

### Step 1 (`TASK-015-1`): 플레이북 정적 검증기(`tools/verify_playbooks.py`), 단위 테스트(`tests/harness/test_verify_playbooks.py`) 및 프레임워크 인덱스(`playbook/README.md`) 구축
1. **TDD Red (`tests/harness/test_verify_playbooks.py`)**:
   - 임시 디렉토리 픽스처 기반으로 정상 통과(15종 + README), 필수 누락, 미인가 파일/예약 슬롯(`--allow-reserved` 미지정 시 차단), 7대 섹션 누락/순서 오류, 깨진 상대 링크, README 인덱스 누락, Overclaim/금지모드/Rule 10 인라인 버전 배지 검출을 검증한다.
2. **TDD Green (`tools/verify_playbooks.py`)**:
   - `REQUIRED_PLAYBOOKS` (15종): `0_development/{alignment,fdr,installer,ota,sensors}.md`, `0_infra/{gps,gcs,gac,landing_pad,runway}.md`, `1_control/{vas,tca}.md`, `2_guidance/fcp.md`, `3_planning/{amm,amm_mission_editor}.md`.
   - `RESERVED_EXPANSION_SLOTS` (4종): `0_infra/pocket_pda.md` (`TASK-302`), `1_control/asa.md` (`TASK-105`/`210`), `0_infra/docking_arm.md` (`TASK-104`), `0_infra/tower_atc.md` (`TASK-108`).
   - CLI 인자: `--root <path>`, `--allow-reserved`, `--json`.
   - 검증 통과 시 `SCAN RESULT: ALL 15 PLAYBOOKS & README CLEAN (0 Errors, 0 Warnings)` 출력 및 `0` 반환.
3. **`playbook/README.md` 작성**: 목적, 1:1 도메인 대칭 구조, 7대 섹션 규격, 5단계 전체 구축 순서, 15종 인덱스 테이블, 예약 슬롯, 검증 절차 기술.

### Step 2 (`TASK-015-2`): `0_development` 도메인 플레이북 5종 작성
- `playbook/0_development/{alignment,fdr,installer,ota,sensors}.md`

### Step 3 (`TASK-015-3`): `0_infra` 도메인 플레이북 5종 작성
- `playbook/0_infra/{gps,gcs,gac,landing_pad,runway}.md`

### Step 4 (`TASK-015-4`): `1_control` 및 `2_guidance` 도메인 플레이북 3종 작성
- `playbook/1_control/{vas,tca}.md`, `playbook/2_guidance/fcp.md`

### Step 5 (`TASK-015-5`): `3_planning` 도메인 플레이북 2종 작성
- `playbook/3_planning/{amm,amm_mission_editor}.md`

### Step 6 (`TASK-015-6`): 프로젝트 규칙·컨텍스트 동기화 및 전수 검증 게이트 실행
1. `tests/harness/test_tools_integrity.py`에 `verify_playbooks.py` 등록 및 실행 테스트 추가.
2. `README.md` 디렉토리 트리 및 검증 명령어 반영 (`verify_context_docs.py` R1/R9 준수).
3. `.agent/rules/skill-workflows.md`에 `playbook/**` 관할 규칙 반영.
4. `md-management`로 `TASK.md`, `GEMINI.md`, `.agent/memory/workspace-root.md` 갱신.
5. `verification-before-completion` 전수 검증 게이트 통과 및 커밋.
