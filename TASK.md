# Create_Aeroneutics — Task Management & Implementation Roadmap

> **문서 상태**: 활성 (Living Roadmap)  
> **최종 갱신일**: 2026-11-11  
> **현재 단계**: **Phase 1 & 2** (직전 완료: TASK-121, TASK-202-1 / 진행 중: TASK-202 / 활성 대기: TASK-010, 011, 117, 119, 120, 201)

---

## 📌 에이전트 작업 지침 (Agent Protocol)

- **계획 수립 시**: 작업 계획(`/plan` 등)이 확정되면 본 파일의 당면 과제 또는 백로그에 신규 항목(`[ ]`)을 등록한다.
- **작업 착수 시**: 진행 중인 태스크를 `[-]` (진행 중)으로 전환한다.
- **작업 완료 시**: 완료 항목을 `[x]` (완료)로 변경해 `## 3. 완료된 작업 이력` 상단으로 이동·기록하고, 도출된 후속 과제를 즉시 본 파일에 등록한다.
- **완료 이력 보존 상한**: 완료된 작업 이력은 **최근 10개까지만 유지**하며, 10개를 초과하는 과거 완료 항목은 오래된 순서대로 정리(Prune)한다.
- **도메인 경로 매핑 기준**: `docs/specs/`, `src/`, `tests/` 간 1:1 도메인 계층 구조는 [README.md](README.md)의 디렉토리 레이아웃을 따른다.
- **유저 호출 예시**:
  - `TASK.md 확인하고 다음 남은 작업 진행해줘`
  - `TASK.md의 TASK-201 작업 진행해줘`
  - `TASK.md 상태 점검해줘`

---

## 🚀 1. 활성 당면 과제 (Active Immediate Tasks — Phase 1 & 2)

- [ ] **TASK-010: 개별 코드베이스 사용 설명서(Playbook) 체계 구축 및 핵심 5종 매뉴얼 작성**
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-010-playbook-framework.md`
  - 계층형 단일 마크다운(`playbook/<도메인>/<서브시스템>.md`) 기반 인게임 운용 실전 매뉴얼 5종(GPS, VAS, TCA, FCP, AMM) 구축, 표준 7대 섹션 템플릿(`playbook/README.md`), CLI 정적 검증 도구(`tools/verify_playbooks.py`), 미인가 체계 작성 차단 가드레일 및 워크플로우 동기화
  - [ ] **TASK-010-1**: 플레이북 정적 검증 도구(`tools/verify_playbooks.py`) 구현 (7대 필수 섹션, 링크 유효성, 미인가 파일 생성 차단 검증)
  - [ ] **TASK-010-2**: 표준 템플릿 명세 및 인덱스(`playbook/README.md`) 작성
  - [ ] **TASK-010-3**: 인프라 도메인 매뉴얼(`playbook/0_infra/gps.md`) 작성
  - [ ] **TASK-010-4**: 온보드 제어 도메인 매뉴얼(`playbook/1_control/vas.md`, `playbook/1_control/tca.md`) 작성
  - [ ] **TASK-010-5**: 유도 및 임무 도메인 매뉴얼(`playbook/2_guidance/fcp.md`, `playbook/3_planning/amm.md`) 작성 (`TASK-201` `LOITER`/`POI_HOLD` 및 `TASK-202` AMM v1.1.0 3분할 미션 시퀀서·CLI/TUI 규격 반영)
  - [ ] **TASK-010-6**: 프로젝트 규칙 반영, 컨텍스트 동기화 및 검증 (`test_tools_integrity.py` 도구 등록·`verify_context_docs.py` 통과 및 `TASK-009`·`113`·`114`·`115`·`116` 현행 반영 확인)

- [ ] **TASK-011: [인프라 매뉴얼] 지상 관제 및 정비 도메인 플레이북 2차 확장 (Alignment, GCS, GAC, Landing Pad)** (`playbook/0_development/alignment.md`, `playbook/0_infra/{gcs,gac,landing_pad}.md`)
  - **선행 의존성**: `TASK-010` 완료 필요 (표준 7대 섹션 템플릿 `playbook/README.md` 및 `tools/verify_playbooks.py` 검증 체계 활용)
  - **배경 및 필요성**: `TASK-010`은 핵심 5종(GPS, VAS, TCA, FCP, AMM)에 집중되어 있으나, 실제 인게임 운용 시 설정·조작이 가장 까다로운 격납고 동역학 캘리브레이션(Alignment)과 지상 관제소/패드 셋업(GCS, GAC, Landing Pad) 매뉴얼 보강 필요
  - **주요 작업**:
    - [ ] **TASK-011-1**: 격납고 동역학 캘리브레이션 매뉴얼(`playbook/0_development/alignment.md`) 작성
    - [ ] **TASK-011-2**: 중앙 지상 관제소 매뉴얼(`playbook/0_infra/gcs.md`) 작성
    - [ ] **TASK-011-3**: 섹터 관제·착륙패드 매뉴얼(`playbook/0_infra/gac.md`, `playbook/0_infra/landing_pad.md`) 작성
    - [ ] **TASK-011-4**: `tools/verify_playbooks.py` 7대 섹션·링크·인가 목록 정적 검증 통과

- [ ] **TASK-117: 무선 원격 배포 및 OTA 업데이트 서버 (OTA Provisioner) 구축** (`src/0_development/ota/` 또는 installer 확장 모듈)
  - **사양서 상태**: 미작성 (구현 착수 전 Draft → Approved 및 대상 경로 확정 필요)
  - **배경 및 필요성**: 다중 CC:Tweaked 컴퓨터 탑재 기체(VAS, 다수 TCA, 다수 ASA, FCP, AMM 등)에서 소프트웨어 업데이트 시 인게임 개별 컴퓨터 수동 `installer.lua` 실행 비용 과다
  - **주요 기능**: 격납고 교정 채널(101 ~ 200) 등 무선 패킷 배포 프로토콜(주의: `0 ~ 100`은 구조도 v2.12.0 상 유선/내부 IPC 전용 예약 대역이므로 사양서 Draft 시 격납고 `+4~+9` 등 무선 채널 확정 필요), 격납고 마스터 컴퓨터 단일 명령으로 기체 내 모든 슬레이브 컴퓨터 로컬 파일(`src/` 하위 패키지) 무선 일괄 업데이트 및 원격 `os.reboot()` 트리거 (신규 `src/` 파일 추가 시 `manifest.lua` 및 `verify_manifest_sync.py` 정합성 동기화 필수)

- [ ] **TASK-119: [OTA 보안/안정성] 슬레이브 노드 부트스트랩 OTA 에이전트 및 원자적 롤백(Atomic Rollback) 가드 구현** (`src/0_development/installer/modules/startup_generator.lua`, `src/1_control/{tca,asa,vas}/`)
  - **선행 의존성**: `TASK-117` 완료 필요
  - **사양서 상태**: 미작성 / 연관 사양서 연동 필요 (TASK-117 OTA 프로토콜 Draft → Approved, `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` 현재 v1.1.0 Implemented 워치독 부트스트랩 개정 및 VAS·TCA·ASA 상태 게이트 반영 필요)
  - **배경 및 필요성**: TASK-117(OTA 업데이트 서버) 구현 시 비행 중이거나 추진기 가동 중인 기체가 OTA 패킷을 받아 재부팅하면 추락 위험이 있으며, 무선 패킷 유실로 손상된 파일 상태로 리부트되면 기체 내부 컴퓨터를 수동 복구해야 하는 벽돌(Brick) 장애 발생
  - **주요 작업**:
    - [ ] **TASK-119-1**: 착륙/안전 인터록 구현 — 기체가 `DISARMED` 또는 격납고 정지 상태일 때만 OTA 수신·적용을 허용하는 상태 게이트 구현 (`src/1_control/{vas,tca}/` 우선 적용; `src/1_control/asa/`는 `TASK-105` 연기 해제 시 연동)
    - [ ] **TASK-119-2**: 원자적 스테이징 및 CRC/해시 검증 구현 — 수신 파일을 `/ota_staging/`에 우선 기록하고 체크섬 일치 시에만 본 경로로 교체하며, 부팅 직후 런타임 에러 발생 시 이전 버전(`/ota_backup/`)으로 자동 복구하는 워치독 래퍼를 `startup.lua` 생성기에 내장 (`src/0_development/installer/modules/startup_generator.lua`)

- [ ] **TASK-120: [개발 도구] 블랙박스 비행 기록기(FDR) 및 호스트 PC 오프라인 텔레메트리 분석기 구축** (`src/0_development/fdr/`, `tools/analyze_flight_log.py`)
  - **사양서 상태**: 미작성 (구현 착수 전 Draft → Approved 필요; `Base+1` `MSG_ATTITUDE_CMD`·`Base+2` `MSG_FLIGHT_TELEMETRY` 패시브 감청 기준, 필요 시 진단 필드 확장 검토)
  - **배경 및 필요성**: 온보드 제어기 헤드리스 전환(TASK-113)으로 실시간 20Hz 성능은 확보되었으나, 인게임 비행 중 발생하는 미세 자세 진동, 짐벌 포화(Saturation), 슬루율 제한 현상을 정밀 튜닝하기 위한 시계열 로그 수집 수단 부재
  - **주요 작업**:
    - [ ] **TASK-120-1**: 경량 블랙박스 로거(`src/0_development/fdr/`) 구현 — `Base+1`(유도 지령) 및 `Base+2`(20Hz VAS 텔레메트리) 패킷을 패시브 감청해 로컬 링 버퍼에 기록하고 `E_STOP` 또는 사용자 핫키 입력 시 JSONL 포맷으로 덤프 (`manifest.lua`·`verify_manifest_sync.py` 등록 포함)
    - [ ] **TASK-120-2**: 오프라인 텔레메트리 분석 CLI(`tools/analyze_flight_log.py`) 구현 — JSONL 덤프 파일을 읽어 목표치(Setpoint) 대비 실제 측정치(Process Variable), PID 적분항 포화도, 추력 분배율 분석·요약 출력 (`tests/harness/test_tools_integrity.py` 등록 포함)

- [-] **TASK-201: FCP 외루프 유도 프리미티브(LOITER 선회 반경 제어 & POI_HOLD 관심점 지향) 확장**
  - **실행 계획서**: `docs/superpowers/plans/2026-11-11-task-201-fcp-loiter-poi-hold.md`
  - **사양서 상태**: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (현재 v1.15.0 Implemented → 목표 v1.16.0 Approved), `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.26.0 Approved — `MSG_OPERATOR_CMD` 확장 파라미터는 `TASK-202-1`에서 선반영 완료; FCP v1.16.0 참조 배지 동기화), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.12.0 Approved — FCP v1.16.0 참조 배지 및 유도 흐름 동기화)
  - **배경 및 목적**: 고수준 미션/편대/레이더 로직을 FCP 범위에서 제외(구 TASK-202 다이어트)하고, 상위 AMM의 전술 기동을 뒷받침할 2종 순수 유도 프리미티브(`LOITER` 반경/방향 선회 및 `POI_HOLD` 정밀 호버/조준)와 `MSG_OPERATOR_CMD`(`Base+0`) 수신 처리 확장
  - [x] **TASK-201-1**: FCP 사양서(→ v1.16.0 Approved) 유도 프리미티브·범프리스 전환 명세 반영 및 마스터 ICD(현재 v1.26.0)·구조도(현재 v2.12.0) 참조 버전 동기화 (`2026-11-11`)
  - [x] **TASK-201-2**: FCP `guidance_controller.lua` 및 활성 기종 드라이버(`vectored_vtol_driver.lua`, `advanced_vtol_driver.lua`; 현행 `DEFERRED_AIRFRAMES` 4종 제외)에 `LOITER`(선회 반경/방향 속도 제어) 및 `POI_HOLD`(관심 좌표 지속 지향) 제어 루프 구현 (`2026-11-11`)
  - [ ] **TASK-201-3**: `operator_handler.lua` `MSG_OPERATOR_CMD` 신규 모드(`POI_HOLD`, `loiterRadius`, `loiterDirection`, `poiTarget`, `headingMode`, `fixedHeading`) 수신 및 범프리스 전환 인터록 구현
  - [ ] **TASK-201-4**: FCP 단위 테스트 및 E2E 시뮬레이션 검증, 사양서 `Implemented` 환원 (`verify_spec_status.py` 기준 충족 및 신규 `src/` 파일 시 `manifest.lua` 동기화)

- [-] **TASK-202: UAFS 통합 미션 시퀀서 엔진 및 AMM 조종석 단말 구현 (구 TASK-201 + 203 통합)**
  - **선행 의존성**: `TASK-202-2~4`(AMM 온보드 3분할 코어·TUI·단위 테스트)는 `TASK-202-1` 사양 확정으로 즉시 독립 진행 가능; `TASK-202-5` 멀티노드 E2E 통합 시뮬레이션(`ORBIT`→FCP `LOITER` / `POI_HOLD` 실기동 연동)은 `TASK-201` 완료 필요
  - **참조 초안 계획서**: `docs/superpowers/plans/2026-11-08-amp-mission-planner.md` (Layer 4 AMP 설계를 AMM 3분할 코어 `mission_engine.lua`·`condition_evaluator.lua`·`hook_runner.lua`로 통합 승계)
  - **사양서 상태**: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v1.1.0 Approved), `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.26.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.12.0 Approved)
  - **배경 및 목적**: Layer 3(AMM)과 Layer 4(AMP)로 분열되었던 미션 시퀀서 및 체크포인트 평가 로직을 3분할 미션 코어(`src/3_planning/amm/modules/{mission_engine,condition_evaluator,hook_runner}.lua`)로 일원화. 온보드 AMM 51x19 MFD TUI와 결합 구동하고 동일 코어를 무인기 헤드리스(`config.headless`) 및 원격 트리거(`Base+0` `MSG_MISSION_CMD`)로 겸용 구동하도록 모듈화
  - [x] **TASK-202-1**: AMM 사양서(v1.1.0 Approved), 마스터 ICD(v1.26.0 Approved), 전체 구조도(v2.12.0 Approved) 통합 미션 스키마 및 Zone 3 인터페이스 반영 완료 (2026-11-11)
  - [ ] **TASK-202-2**: 13종 체크포인트 스키마(활성 9종 + 예약 4종), 12종 `completeWhen`/`abortWhen` 조건 평가기(`condition_evaluator.lua`) 및 0-tick 비차단 훅/디바이스 실행기(`hook_runner.lua`), `network_manager.lua` Zone 3(`Base+20~29`) 동적 채널 연동 구현
  - [ ] **TASK-202-3**: `missions/*.json` 다형성 시퀀스 파일 로더 및 스텝 자동 전이 FSM(`mission_engine.lua`), `c2_arbiter.lua` `Base+0` `MSG_MISSION_CMD`/`ACK` 중재 및 `config.headless` 분기 구현
  - [ ] **TASK-202-4**: AMM 51x19 TUI 6행 스크롤 뷰포트 + 5행 조건 진행률 시각화(`ui_renderer.lua`) 및 CLI 명령어(`run/stop/next/mission`, `input_handler.lua`) 확장
  - [ ] **TASK-202-5**: AMM 단위 테스트 및 E2E 시뮬레이션 검증, `manifest.lua`·`verify_manifest_sync.py`·`verify_spec_status.py` 동기화 및 사양서 `Implemented` 환원

---

## 📋 2. 예정 백로그 (Planned Backlog — Phase 1 & 2)

- [ ] **TASK-103: Runway 활주로 제어기 구현** (`src/0_infra/runway/`)
  - **사양서 상태**: `docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md` (v1.10.6 Approved)
  - 활주로 유도등, 가상 ILS 및 유도로 `GAC` 연동 관제, 3축 ILS 글라이드슬로프/로컬라이저 비콘 송출 및 착륙 접근 프로토콜 (`TASK-116` 완료로 `0_infra` 폴더 스크롤 수용 가능, 구현 시 `manifest.lua` 등록 및 `verify_spec_status.py` 갱신 필요)

### ⏸️ 연기·보류 과제 (Deferred / On-Hold)

- [ ] **[연기] TASK-104: Docking Arm 결합 암 제어기 구현** (`src/0_infra/docking_arm/`)
  - **사양서 상태**: `docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md` (v1.11.1 Approved)
  - 2축 로봇 암 포획·인입 및 엄빌리컬 보급 시퀀스 (일정 연기 — 사양서 `Approved` 유지, 구현 시 `manifest.lua` 등록 및 `verify_spec_status.py` 갱신 필요)
- [ ] **[연기] TASK-105: ASA (Aerodynamic Surface Adapter) 공력 조종면·플랩 분산 구동기 본 구현 완성** (`src/1_control/asa/`)
  - **사양서 상태**: `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (v1.6.0 Approved)
  - TASK-113의 기본 프레임워크(헤드리스/비동기 TUI, `Base+11` 수신 루프, 300ms Safe Glide Trim, 단위 테스트 15/15 PASS)를 기반으로 물리 액추에이터(Avionics API/RS) 각도 인가, `MSG_AERO_STATUS` 상태 피드백 송출 및 `MSG_SURFACE_DISCOVER_REQ/ACK` 핸드셰이크 완성 (일정 연기 — 사양서 `Approved` 유지; 재개 시 `manifest.lua`·`verify_spec_status.py` 갱신 및 `tools/verify_manifest_sync.py` `DEFERRED_SUBSYSTEM_DIRS` 면제 해제 필요)
- [ ] **[연기] TASK-108: Tower ATC (Sector 0, `CH 50001/50002`) 광역 항공교통 관제 노드 구현**
  - **사양서 상태**: 별도 사양서 미작성 (마스터 ICD `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` v1.26.0 Interface I-5 기반; 착수 전 사양서 Draft → Approved 또는 ICD 연계 필요)
  - 광역 공역 진입/이탈 스케줄링 및 섹터 `GAC` 핸드오프 프로토콜 구현 (일정 연기)

### 🔭 Phase 3 백로그 (Phase 3 Backlog)

- [ ] **[연기] TASK-301: 물리 하드웨어 기반 ACRO 수동 급기동 조종 인터페이스 개발**
  - Create/Avionics 아날로그 스틱 및 물리 컨트롤러 하드웨어 연동 (일정 연기)
  - `Base+1` 20Hz 직접 3축 각속도(`RATE_COMMAND`) 직결 스트림 및 비행 제어 코어(VAS) 선점 제어 연동

---

## ✅ 3. 완료된 작업 이력 (Completed Tasks Archive — 최근 10개 유지)

- [x] **TASK-121: [하네스/거버넌스] 컨텍스트 문서 드리프트 정적 검사기(`verify_context_docs.py`) 및 Antigravity `Stop` 훅 자동 가드 구축** (완료일: 2026-11-11, 커밋 `edea694` ~ `7832914`) (`tools/verify_context_docs.py`, `.agent/hooks/`, `.agent/hooks.json`, `tests/harness/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-11-task-121-context-doc-drift-guard.md`
  - **목적 및 성과**: 루트 컨텍스트 문서(`README.md`, `GEMINI.md`, `TASK.md`, `.agent/memory/*.md`)의 8개 드리프트 규칙(R1~R8)을 정적 판정하는 `tools/verify_context_docs.py`와 작업 종료 시 미수정 위반이 있으면 `continue`로 되돌리는 `.agent/hooks/context_doc_guard.py`(`SessionStart`/`Stop`, 동일 위반 2회 상한, fail-open, `stop` 실측 `204.15 ms`)를 구축하고 `.agent/hooks.json`에 등록함. 새 대화 실환경 스모크에서 `Stop` 훅의 `[R1]` 차단 및 자가 원복을 확인했고, Windows `git.exe"` 호출 우회를 수정(`f38356a`)한 뒤 하네스 전체 82/82 PASS 및 `verify_context_docs.py` `0 findings` 달성.
  - **구현 내용**:
    - [x] **TASK-121-1**: 단일 문서 규칙(R1, R2, R3, R6, R7) 및 단위 테스트 11건 구현 (`edea694`)
    - [x] **TASK-121-2**: 교차 참조 규칙(R4, R5, R8), `--json` CLI, 실저장소 회귀 7건 구현 및 `test_tools_integrity.py` 편입 (`a2cf19a`)
    - [x] **TASK-121-3**: `SessionStart`/`Stop` 훅(`.agent/hooks/context_doc_guard.py`) 및 단위 테스트 10건 구현 (`97b2654`)
    - [x] **TASK-121-4**: `.agent/hooks.json` 등록(`b12782a`), 실환경 `Stop` 훅 차단 확인(`a3ee0ef6`), `block_dangerous_git.py` `git.exe` 경로 차단 확장·테스트 4건 추가(`f38356a`)
    - [x] **TASK-121-5**: 완료 워크플로우(`verification-before-completion`, `md-management`, `skill-workflows.md`) 연동 및 컨텍스트 동기화 (`7832914`)

- [x] **TASK-116: 통합 인스톨러(`installer.lua`) 역할/도메인별 TUI 폴더 탐색 구조 개편** (완료일: 2026-11-10, 커밋 `30023fb` ~ `14f5a45`) (`installer.lua`, `src/0_development/installer/`, `tests/0_development/installer/`, `docs/specs/0_development/installer/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-10-task-116-installer-category-folder-tui.md`
  - **목적 및 성과**: `51x19` 터미널 12행(`y = 4..15`) 포화를 해소하고 패키지 탐색 복잡도를 낮추기 위해, `INSTALLER_PROGRAM_SPECIFICATION.md` v1.1.0 제정과 `manifest.lua` v1.1.0 6대 도메인 카테고리 그룹화 API(`CATEGORY_ORDER`, `CATEGORIES`, `getCategory`, `listModulesByCategory`, `listCategories`), `tui_view.lua` 12행 뷰포트 스크롤러(`computeViewport`)·카테고리 폴더 렌더러(`renderCategoryMenu`)·증분 커서 갱신(`updateSelection`, 정상 색상 복원)·잔상 초기화, `installer_app.lua` 2계층 상태 머신(`CATEGORY_MENU` $\leftrightarrow$ `MODULE_MENU` $\leftrightarrow$ `CONFIRM_*`, `Q` 종료 시 색상/커서 복원)을 구현하고 사양서를 `Implemented`로 승격함 (단일 컴퓨터 복합 프리셋 제외, CLI 모드 호환 유지). 단위 318/318 PASS(12개 타겟, `installer` 39/39), E2E 8/8 PASS(7개 시나리오), 돌연변이 25/25 KILLED(100.0%, 기준 90.0%), 하네스 50/50 PASS, `verify_manifest_sync.py`·`verify_all_specs.py --check-readmes` `0 Errors, 0 Warnings`, `verify_spec_status.py` 15대 사양서(10 Implemented, 5 Approved) PASS, Lua 126/126 PASS.
  - **구현 내용**:
    - [x] **TASK-116-1**: `INSTALLER_PROGRAM_SPECIFICATION.md` v1.1.0 `Approved` 작성 및 `verify_all_specs.py`·`verify_spec_status.py`·`README.md` 등록 (`30023fb`)
    - [x] **TASK-116-2**: `manifest.lua` v1.1.0 도메인 카테고리 레지스트리 및 조회 API 구현, `installer.lua` 바이트 패리티·버전 동기화 (`f23a27d`)
    - [x] **TASK-116-3**: `tui_view.lua` 뷰포트 스크롤/폴더 뷰/증분 선택 및 `installer_app.lua` 2계층 TUI FSM 구현 (`2e1b53a`)
    - [x] **TASK-116-4**: 전계층 회귀 검증, 사양서 `Implemented` 승격(`10 Implemented, 5 Approved`), 리뷰 보완(`updateSelection`/종료 색상 복원·경계 통합 테스트 4종 추가·§5.1 정합화) 및 컨텍스트 동기화 (`c320d12`, `14f5a45`)

- [x] **TASK-118: [검증 확장] `ADVANCED_VTOL` 및 GAC 전용 패드/비상 징발 E2E 시뮬레이션 & 돌연변이 테스트 확장** (완료일: 2026-11-10, 커밋 `f4d0c1f` ~ `b9211fa`) (`src/1_control/tca/`, `tests/1_control/tca/`, `tests/e2e/`, `tools/run_mutation_tests.py`, `harness/simulation/node_sandbox.lua`, `tests/harness/test_simulation_core.py`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-10-task-118-advanced-vtol-gac-e2e-mutation.md`
  - **목적 및 성과**: `TASK-115`(`ADVANCED_VTOL` 6-DoF 짐벌 벡터 추진) 및 `TASK-114`(`GAC` 전용 패드 격리·비상 징발) 대상 멀티노드 E2E 시나리오 및 결정론적 돌연변이 테스트 확장, 통합 E2E 동시 실행 중 노출된 게스트 샌드박스 `require` 인자 누락 버그(`node_sandbox.lua:226` `(norm_name, found_path)` 2인자 전달) 수정 완료. 단위 테스트 309/309 PASS(12개 타겟, TCA 32/32), E2E 7개 시나리오 8/8 PASS, 돌연변이 25/25 KILLED(100.0%, 기준 90.0%), 하네스 회귀 50/50 PASS, `verify_manifest_sync.py`·`verify_all_specs.py` 0 Errors/0 Warnings 달성.
  - **구현 내용**:
    - [x] **TASK-118-1**: `tca_daemon.lua`·`watchdog_sentinel.lua` `MSG_CALIB_PULSE` 2D 짐벌(`gimbalX`/`gimbalY`) 전달 수정, TCA 단위 테스트 추가(`32/32`) 및 `tests/e2e/test_e2e_advanced_vtol_flight.lua`(시나리오 7) 신설 (`f4d0c1f`)
    - [x] **TASK-118-2**: `tests/e2e/test_e2e_facility_landing.lua` 확장 — 전용 패드 비콘 분리, `FACILITY_DEDICATED` 거절 및 `isEmergency = true` 강제 징발 시퀀스 검증 (`704822f`)
    - [x] **TASK-118-3**: `tools/run_mutation_tests.py` `MUT-21`~`MUT-25` 추가(25/25 KILLED) 및 `node_sandbox.lua` `require` 표준 인자 패리티 수정·하네스 회귀(`test_simulation_core.py`) 추가 (`b9211fa`)

- [x] **TASK-012: [CI/CD 정적 가드] 인스톨러 매니페스트(`manifest.lua`) · GDrive 맵 · 실제 소스 트리 간 3자 정합성 검증기 구현** (완료일: 2026-11-10) (`tools/verify_manifest_sync.py`, `tests/harness/test_manifest_sync_verifier.py`, `tests/harness/test_tools_integrity.py`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-10-task-012-manifest-sync-verifier.md`
  - **목적 및 성과**: 외부 Lua 런타임 없이 `manifest.lua`·`installer.lua`·`src/`·`config/gdrive_mapping.json` 3자 정합성(모듈 순서·카테고리 정합성, 공용 센서 번들링, 양방향 누락·고아 파일, 연기 서브시스템 면제 만료, 부트스트랩 바이트/ID 패리티)을 정적 검사하는 CLI 구축 및 표준 검증 파이프라인(`test_tools_integrity.py`) 편입 완료. 전체 하네스 회귀 49/49 PASS(신규 7건+통합 1건), `verify_manifest_sync.py` `0 Errors, 0 Warnings`(12 모듈·113 매니페스트 경로·129 소스 파일·9 GDrive 엔트리) 달성.
  - **구현 내용**:
    - [x] **TASK-012-1**: `tools/verify_manifest_sync.py` 구현 및 결함 주입 단위 테스트(`tests/harness/test_manifest_sync_verifier.py` 7/7 PASS) 구축
    - [x] **TASK-012-2**: `tests/harness/test_tools_integrity.py` 편입, `README.md`/`GEMINI.md` 표준 One-Liner 갱신 및 전체 정적 파이프라인 검증 완료

- [x] **TASK-114: GAC 전용 시설물(Dedicated Facility) 지원 및 2단계 다속성 분배 엔진/TUI 확장** (완료일: 2026-11-10) (`src/0_infra/gac/`, `tests/0_infra/gac/`, `docs/specs/0_infra/gac/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-10-task-114-gac-dedicated-facility.md`
  - **목적 및 성과**: 특정 VTOL/DRONE 전속 대기용 전용 착륙패드/도킹암/활주로(`dedicatedCraftIds`, `dedicatedAirframeTypes`) 런타임 검증, 비콘 공용 가용 패드 분리, `FACILITY_DEDICATED` 거절 분기 및 3-Tab TUI `[DED: ...]`/`PUBLIC` 콘솔 관리 구현 완료. 전체 12개 타겟 단위 테스트 308/308 PASS(GAC 46/46 PASS), E2E 6/6 PASS, 돌연변이 20/20 KILLED(100.0%), 하네스 41/41 PASS, GAC 사양서 v1.4.1 `Implemented` 승격(9 Implemented, 5 Approved, 0 Errors/0 Warnings) 달성.
  - **구현 내용**:
    - [x] **TASK-114-1**: 전용 시설물 사양서 개정 및 동기화 (GAC v1.4.1, 착륙패드 v2.4.2, 도킹암 v1.11.1)
    - [x] **TASK-114-2**: `config_loader.lua` 전용 필드 스키마 검증 및 `facility_inventory.lua` 비콘 공용 가용 패드(`freeLandingPads`/`freeRunways`) 분리·동적 전용 속성 갱신 구현
    - [x] **TASK-114-3**: `allocation_engine.lua` `FACILITY_DEDICATED` 거절 분기(비인가 `preferredFacilityId`·공용 패드 부재) 및 `gac_fsm.lua` `handle_tower_handoff_req` `craftReq` 필터 연동
    - [x] **TASK-114-4**: `tui_view.lua` Tab 2 `[DED: ...]`/`PUBLIC` Cyan 하이라이트, 비동기 인라인 프롬프트(`[A]`/`[P]`), `apply_operator_action` 및 `main.lua` 로컬 백본 동기화 연동
    - [x] **TASK-114-5**: CraftOS-PC 단위 테스트 46/46·전계층 회귀 검증 및 GAC 사양서 `Implemented` 승격

- [x] **TASK-009: GDrive 업로드용 디렉토리 재지정 및 파일 관리 방식 개선** (완료일: 2026-11-09) (`dist_gdrive/`, `config/gdrive_mapping.json`, `tools/sync_gdrive.py`, `docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-09-task-009-gdrive-deployment-framework.md`
  - **목적 및 성과**: 인게임 CC:Tweaked 및 원격 배포(`installer.lua` Google Drive 다운로드 연동)에 필요한 격리 스테이징 구조(`dist_gdrive/`), 단일 진실 공급원 매핑 파일(`config/gdrive_mapping.json`), 자동화 CLI 도구(`tools/sync_gdrive.py`) 및 운영 가이드라인 구축 완료. Google Drive 공식 폴더(`1NgbGjm9YY7lpIlo4sLs32cNE2NwjVVy9`, `Antigravity_Playground`)로의 부트스트랩 7종, 인스톨러, 센서 공유 라이브러리 실시간 업로드 및 파일 ID 매핑 연동. 인스톨러 `--bootstrap-gdrive-map` 구조적 JSON 파싱 확장, 단위 테스트 294/294 PASS, 하네스 41/41 PASS, E2E 6/6 PASS, 돌연변이 20/20 KILLED(100.0%), 14대 사양서 0 Errors/0 Warnings 달성.
  - **구현 내용**:
    - [x] **TASK-009-1**: GDrive 업로드/동기화 대상 디렉토리 구조(`dist_gdrive/`) 재정의 및 4대 파일 분류 기준 수립
    - [x] **TASK-009-2**: 배포 아티팩트 및 GDrive 매핑 파일(`config/gdrive_mapping.json`, `--bootstrap-gdrive-map` 구조화 지원) 관리 체계 개선
    - [x] **TASK-009-3**: 동기화/업로드 CLI 도구(`tools/sync_gdrive.py`) 개발, 하네스 무결성 테스트 구축 및 운영 가이드라인(`docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md`) 문서화
    - [x] **TASK-009-4**: Google Drive 공식 폴더 동기화 및 부트스트랩 파일 ID 프리셋 내장
    - [x] **TASK-009-5**: 전계층 회귀 검증 및 마일스톤 동기화

- [x] **TASK-008: 구버전 잔존 명칭(VAS-Core, VAS-Align, VAC-Align) 전면 검수·치환 및 회귀 방지 정비** (완료일: 2026-11-09) (`tests/harness/test_terminology_guard.py`, `tools/verify_all_specs.py`, `src/`, `tests/`, `docs/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-09-task-008-legacy-terminology-purge.md`
  - **목적 및 성과**: 비행 제어 및 교정 지상 콘솔 관련 구버전 잔존 명칭(`VAS-Core` $\to$ `VAS`, `VAS-Align` $\to$ `Alignment`, `VAC-Align` $\to$ `Alignment`, `VAC-Core` $\to$ `VAS`, TCA 내 잔존 `VAC` 링크 스트림 명칭) 전면 소급 척결 및 단일 표준화 완료. 회귀 방지 테스트(`test_terminology_guard.py` 7/7 PASS) 및 사양서 무결성 검증기(`verify_all_specs.py` Rule 8) 확장으로 재유입 시 자동 검출되도록 구성. 런타임 모듈(`preflight_bit.lua`, `channel_rebind_handler.lua`, `tca_daemon.lua`, `tui_dashboard.lua`, `node_core_sim.lua`) 및 7대 사양서 전수 치환 완료. 12개 타겟 단위 테스트 293/293 PASS, E2E 시뮬레이션 6/6 PASS, 돌연변이 살상률 100.0%(20/20 KILLED), 하네스 36/36 PASS, 14대 사양서 0 Errors/0 Warnings 달성.
  - **구현 내용**:
    - [x] **TASK-008-1**: 회귀 방지 테스트(`tests/harness/test_terminology_guard.py`)에 `VAS-Core`, `VAS-Align`, `VAC-Align`, `VAC-Core` 금지 패턴 등록 및 Red 검증
    - [x] **TASK-008-2**: 사양서 무결성 검증 도구(`tools/verify_all_specs.py` Rule 8) 용어 위생 검사 규칙 확장
    - [x] **TASK-008-3**: 전체 사양서(`ALIGNMENT`, `ASA`, `TCA`, `VAS`, `FCP`, `SYSTEM_ARCHITECTURE`, `SYSTEM_PACKET`) 내 잔존 식별자 전수 치환
    - [x] **TASK-008-4**: 런타임 소스(`src/1_control/`) 및 테스트 코드(`tests/1_control/tca/`) 내 주석·식별자 치환
    - [x] **TASK-008-5**: 단위 테스트(293/293), E2E(6/6), 돌연변이(20/20) 및 사양서 무결성 검증기 일괄 통과 검증

- [x] **TASK-115: ADVANCED_VTOL 짐벌 벡터 추진기 기체 아키텍처 및 전계층 연동 구현** (완료일: 2026-11-09) (`src/`, `docs/`, `tests/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-09-task-115-advanced-vtol-architecture-and-implementation.md`
  - **목적 및 성과**: 2D 짐벌 벡터 추진기(`vector_thruster`, `liquid_vector_thruster`, `creative_vector_thruster`)를 탑재한 신규 고기동 기종 `ADVANCED_VTOL` 설계 및 전계층 구현 완료. TCA 노즐 편향(`setVector`) 및 워치독/E_STOP 페일세이프 노즐 중립 `(0, 0)` 복귀, Alignment 3단계 펄스 시퀀스(Throttle, Gimbal X/Y) 및 가우스-조던 소거법 기반 Moore-Penrose 의사역행렬($B^\dagger$) 산출 프로파일 내보내기, VAS 6-DoF 렌치 할당기 및 짐벌 포화 방향성 안티 와인드업/비공력 정책(`flapTarget = 0.0`, ASA 바이패스), FCP `advanced_vtol_driver.lua` 3축 비결합 수평/수직 가이던스(2.0/s 짐벌 슬루율, `STRICT_LEVEL`/`TILT_ASSISTED`, 15m 안전고도 수직 이륙 및 2단계 연착륙), GAC v1.4.1 전용 슬롯 매칭 및 Landing Pad/GCS/Installer 통합. 전체 단위 테스트 293/293 PASS(12개 타겟), E2E 시뮬레이션 6/6 PASS, 돌연변이 살상률 100.0%(20/20 KILLED), 하네스 회귀 33/33 PASS, 14대 사양서 0 Errors/0 Warnings (8 Implemented, 6 Approved).
  - **구현 내용**:
    - [x] **TASK-115-0**: 워크트리 Rebase 및 `main` 베이스라인 정렬
    - [x] **TASK-115-1**: 사양서 6종 개정 (ICD v1.25.0, 구조도 v2.11.0, TCA v1.11.0, VAS v1.18.0, FCP v1.15.0, Alignment v2.6.0)
    - [x] **TASK-115-2**: TCA `vector_thruster` 래퍼 및 다형성 추력/짐벌 출력 구동 (`src/1_control/tca/`)
    - [x] **TASK-115-3**: Alignment 짐벌 X/Y 펄스 시퀀서 및 $B^\dagger$ 추출기 (`src/0_development/alignment/`)
    - [x] **TASK-115-4**: VAS ADVANCED_VTOL 정책, 6-DoF 의사역행렬 믹서 및 안티와인드업 (`src/1_control/vas/`)
    - [x] **TASK-115-5**: FCP 외루프 `advanced_vtol_driver.lua` 및 가이던스 연동 (`src/2_guidance/fcp/`)
    - [x] **TASK-115-6**: 지상 인프라 및 미션 시스템 호환 (GAC, Landing Pad, GCS, Installer)
    - [x] **TASK-115-7**: 전계층 검증(293/293 unit, 6/6 E2E, 20/20 mutation, 33/33 harness), 사양서 4종 `Implemented` 승격

- [x] **TASK-007: 구버전 명칭(UAP/SAS/WAP) 전면 척결 및 회귀 방지 테스트 슈트 구축** (완료일: 2026-11-08) (`tests/harness/test_terminology_guard.py`, `tools/verify_all_specs.py`, `src/`, `tests/`, `docs/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-legacy-terminology-elimination-and-test-suite.md`
  - **목적 및 성과**: 비행 제어 및 공력 구동계 관련 구버전 잔존 명칭(`UAP`, `SAS`, `WAP`) 소급 전면 삭제(Zero-Tolerance Purge) 및 풀 마이그레이션(Full Migration) 완료. 유선 패킷 `podId`(`"ASA_L"`, `"ASA_R"`, `"ASA_T"`), 텔레메트리 헬스 키(`actuatorHealth.asa`), 모듈 파일명(`actuator_adapter_asa.lua`, `node_asa.lua`, `node_asa_sim.lua`) 일체 통일. 회귀 방지 테스트(`test_terminology_guard.py`) 및 정적 분석기(`verify_all_specs.py` Rule 8) 구축하여 14대 사양서 및 런타임/테스트 코드 0건 검출 확인(2026-11-08 실행 기준). 전체 12개 타겟 단위 테스트 248/248 PASS, E2E 시뮬레이션 6/6 PASS, 돌연변이 살상률 100.0%(20/20 KILLED), 하네스 테스트 33/33 PASS, 14대 사양서 0 Errors/0 Warnings(8 Implemented, 6 Approved) 달성.
  - **구현 내용**:
    - [x] **TASK-007-1**: 워크트리(`.worktrees/task-legacy-terminology`) 격리 및 회귀 테스트(`tests/harness/test_terminology_guard.py`, 4/4 PASS) 신설
    - [x] **TASK-007-2**: 사양서 무결성 검증기(`tools/verify_all_specs.py`) Rule 8 용어 위생 검사 통합
    - [x] **TASK-007-3**: 런타임 모듈 파일 개명 및 소스/테스트 코드 내 식별자 치환 (`actuator_adapter_asa.lua`, `node_asa.lua`, `node_asa_sim.lua`, `state_machine.lua`, `core_daemon.lua`, `network_manager.lua` 등 22개 파일)
    - [x] **TASK-007-4**: 핵심 4대 사양서(`ICD` v1.24.0, `VAS` v1.17.0, `FCP` v1.14.0, `ASA` v1.6.0) 용어 소급 척결 및 SemVer 마이너 승격
    - [x] **TASK-007-5**: 연관 10대 사양서(`SYSTEM_DIAGRAM` v2.10.1, `ALIGNMENT` v2.5.2, `GPS` v2.2.2, `GAC` v1.4.1, `DOCKING_ARM` v1.11.1, `LANDING_PAD` v2.4.2, `RUNWAY` v1.10.6, `GCS` v1.0.1, `TCA` v1.10.1, `AMM` v1.0.1) 용어 정비 및 SemVer 패치 승격
    - [x] **TASK-007-6**: 전체 파이프라인 일괄 검증 및 사양서 상태(`VAS`, `FCP` $\to$ `Implemented`) 환원

- [x] **TASK-111: 멀티노드 종단간(E2E) 패킷 시퀀스 통합 시뮬레이션 테스트 구축** (완료일: 2026-11-08, 커밋 `646d831` ~ `81e584b`) (`harness/simulation/`, `tools/run_e2e_tests.py`, `tests/e2e/`, `tests/harness/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-111-e2e-simulation.md`
  - **목적 및 성과**: 다중 노드 격리 가상 버스(`virtual_bus.lua`), Cobalt Lua 5.2 `_ENV` 기반 게스트 샌드박스(`node_sandbox.lua`), 자동화 E2E 테스트 러너(`tools/run_e2e_tests.py`), 자동화 돌연변이 테스터(`tools/run_mutation_tests.py`) 구축 및 6대 핵심 통합 시나리오 검증 완료.
