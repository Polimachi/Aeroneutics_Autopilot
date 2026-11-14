# Create_Aeroneutics — Task Management & Implementation Roadmap

> **문서 상태**: 활성 (Living Roadmap)  
> **최종 갱신일**: 2026-11-14  
> **현재 단계**: **Phase 1 & 2** (직전 완료: TASK-206, TASK-207, TASK-208, TASK-209, TASK-124, TASK-123, TASK-204 / 활성 대기: TASK-010, 011, 013, 117, 120, 210, 402)

---

## 📌 에이전트 작업 지침 (Agent Protocol)

- **계획 수립 시**: 작업 계획(`/plan` 등)이 확정되면 본 파일의 당면 과제 또는 백로그에 신규 항목(`[ ]`)을 등록한다.
- **작업 착수 시**: 진행 중인 태스크를 `[-]` (진행 중)으로 전환한다.
- **작업 완료 시**: 완료 항목을 `[x]` (완료)로 변경해 `## 3. 완료된 작업 이력` 상단으로 이동·기록하고, 도출된 후속 과제를 즉시 본 파일에 등록한다.
- **완료 이력 보존 상한**: 완료된 작업 이력은 **최근 10개까지만 유지**하며, 10개를 초과하는 과거 완료 항목은 오래된 순서대로 정리(Prune)한다.
- **도메인 경로 매핑 기준**: `docs/specs/`, `src/`, `tests/` 간 1:1 도메인 계층 구조는 [README.md](README.md)의 디렉토리 레이아웃을 따른다.
- **유저 호출 예시**:
  - `TASK.md 확인하고 다음 남은 작업 진행해줘`
  - `TASK.md의 TASK-402 작업 진행해줘`
  - `TASK.md 상태 점검해줘`

---

## 🚀 1. 활성 당면 과제 (Active Immediate Tasks — Phase 1 & 2)

> **권장 실행 우선순위**: **1순위** `TASK-402` (`TASK-204` `v2.0.0` 행동 스키마 정합 WebUI 에디터 구현 및 `AMM` 승격) → **2순위** `TASK-010` → `TASK-011` (플레이북) · `TASK-120` (FDR) · `TASK-013` (사양서 전수 감사) → **3순위** `TASK-117` (무선 OTA) / **대기** `TASK-210` (`[연기] TASK-105` 재개 연동) / **로드맵(연기)** `TASK-401`

- [ ] **TASK-402: [1순위] 호스트 PC 브라우저 기반 단일 파일 비주얼 미션 에디터(`tools/amm_mission_editor.html`) HTML 구현 및 검증** (`tools/amm_mission_editor.html`, `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (현재 v0.2.0 Draft), `tests/3_planning/amm/`)
  - **권장 착수 순위**: **1순위** (`TASK-204` 신규 행동 스키마 확정·구현 완료에 따른 에디터 사양 `v0.2.0` 정합 구현)
  - **선행 의존성**: `TASK-202-5`·`TASK-207`·`TASK-204` 완료 (`AMM_MISSION_EDITOR_SPECIFICATION.md` `v0.2.0 Draft`를 `Approved`로 승격한 뒤 구현 착수)
  - **배경 및 목적**: `TASK-202-5`에서 수립하고 `TASK-204`에서 `v0.2.0 Draft`로 정합 개정한 `AMM_MISSION_EDITOR_SPECIFICATION.md`를 기반으로 오프라인 `file://` 호환 단일 파일 HTML5/CSS/Vanilla JS 비주얼 미션 에디터(`tools/amm_mission_editor.html`)를 직접 생성하고, AMM 단위 테스트·E2E 시뮬레이션 검증, `manifest.lua`·`verify_manifest_sync.py`·`verify_spec_status.py` 동기화 및 WebUI 에디터 사양서와 `AMM` 사양서 `Implemented` 승격을 수행함 (`TASK-207`·`TASK-204` 코드 구현 완료, `TASK-402` 완료 시까지 `AMM` 사양서 `Approved` 유지)

- [ ] **TASK-010: [2순위] 개별 코드베이스 사용 설명서(Playbook) 체계 구축 및 핵심 5종 매뉴얼 작성**
  - **권장 착수 순위**: **2순위** (`GPS`·`VAS`·`TCA`·`FCP` 4종은 즉시 착수 가능, `TASK-010-5` `AMM` 절은 `TASK-204` 반영 완료 및 `TASK-402` 완료 후 마감 권장)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-010-playbook-framework.md`
  - 계층형 단일 마크다운(`playbook/<도메인>/<서브시스템>.md`) 기반 인게임 운용 실전 매뉴얼 5종(GPS, VAS, TCA, FCP, AMM) 구축, 표준 7대 섹션 템플릿(`playbook/README.md`), CLI 정적 검증 도구(`tools/verify_playbooks.py`), 미인가 체계 작성 차단 가드레일 및 워크플로우 동기화
  - [ ] **TASK-010-1**: 플레이북 정적 검증 도구(`tools/verify_playbooks.py`) 구현 (7대 필수 섹션, 링크 유효성, 미인가 파일 생성 차단 검증)
  - [ ] **TASK-010-2**: 표준 템플릿 명세 및 인덱스(`playbook/README.md`) 작성
  - [ ] **TASK-010-3**: 인프라 도메인 매뉴얼(`playbook/0_infra/gps.md`) 작성
  - [ ] **TASK-010-4**: 온보드 제어 도메인 매뉴얼(`playbook/1_control/vas.md`, `playbook/1_control/tca.md`) 작성 (`VAS v1.19.0` `QUATERNION_RATE`·`Base+3` `MFD_ACRO`·`system.json` 및 `TCA v1.11.1` 반영)
  - [ ] **TASK-010-5**: 유도 및 임무 도메인 매뉴얼(`playbook/2_guidance/fcp.md`, `playbook/3_planning/amm.md`) 작성 (`TASK-207~209` 완료 기준 현행 `FCP v2.0.0` `Base+4/+2/+1` 3채널 순수 `SE(3)` 외루프 및 `AMM v1.3.0` 듀얼 모뎀 외부 게이트웨이·`nav_engine`·`trajectory_generator`·`TASK-201`/`TASK-202` 3분할 미션 시퀀서·CLI/TUI·외부 파일 즉시 구동 규격 반영; 후속 `TASK-204`·`TASK-402` 완료 시 해당 절 동기화)
  - [ ] **TASK-010-6**: 프로젝트 규칙 반영, 컨텍스트 동기화 및 검증 (`test_tools_integrity.py` 도구 등록·`verify_context_docs.py` 통과 및 `TASK-009`·`113`·`114`·`115`·`116`·`122`·`202`·`207~209` 현행 반영 확인)

- [ ] **TASK-011: [2순위 / 인프라 매뉴얼] 지상 관제 및 정비 도메인 플레이북 2차 확장 (Alignment, GCS, GAC, Landing Pad)** (`playbook/0_development/alignment.md`, `playbook/0_infra/{gcs,gac,landing_pad}.md`)
  - **선행 의존성**: `TASK-010` 완료 필요 (표준 7대 섹션 템플릿 `playbook/README.md` 및 `tools/verify_playbooks.py` 검증 체계 활용)
  - **배경 및 필요성**: `TASK-010`은 핵심 5종(GPS, VAS, TCA, FCP, AMM)에 집중되어 있으나, 실제 인게임 운용 시 설정·조작이 가장 까다로운 격납고 동역학 캘리브레이션(Alignment)과 지상 관제소/패드 셋업(GCS, GAC, Landing Pad) 매뉴얼 보강 필요
  - **주요 작업**:
    - [ ] **TASK-011-1**: 격납고 동역학 캘리브레이션 매뉴얼(`playbook/0_development/alignment.md`) 작성
    - [ ] **TASK-011-2**: 중앙 지상 관제소 매뉴얼(`playbook/0_infra/gcs.md`) 작성
    - [ ] **TASK-011-3**: 섹터 관제·착륙패드 매뉴얼(`playbook/0_infra/gac.md`, `playbook/0_infra/landing_pad.md`) 작성
    - [ ] **TASK-011-4**: `tools/verify_playbooks.py` 7대 섹션·링크·인가 목록 정적 검증 통과

- [ ] **TASK-120: [2순위 / 개발 도구] 블랙박스 비행 기록기(FDR) 및 호스트 PC 오프라인 텔레메트리 분석기 구축** (`src/0_development/fdr/`, `tools/analyze_flight_log.py`)
  - **권장 착수 순위**: **2순위** (독립 도구로서 병렬 착수 가능, `TASK-117` 선행 조건)
  - **사양서 상태**: 미작성 (구현 착수 전 Draft → Approved 필요; `Base+1` `MSG_ATTITUDE_CMD`·`Base+2` `MSG_FLIGHT_TELEMETRY` 패시브 감청 기준, 필요 시 진단 필드 확장 검토)
  - **배경 및 필요성**: 온보드 제어기 헤드리스 전환(TASK-113)으로 실시간 20Hz 성능은 확보되었으나, 인게임 비행 중 발생하는 미세 자세 진동, 짐벌 포화(Saturation), 슬루율 제한 현상을 정밀 튜닝하기 위한 시계열 로그 수집 수단 부재
  - **주요 작업**:
    - [ ] **TASK-120-1**: 경량 블랙박스 로거(`src/0_development/fdr/`) 구현 — `Base+1`(유도 지령) 및 `Base+2`(20Hz VAS 텔레메트리) 패킷을 패시브 감청해 로컬 링 버퍼에 기록하고 `E_STOP` 또는 사용자 핫키 입력 시 JSONL 포맷으로 덤프 (`manifest.lua`·`verify_manifest_sync.py` 등록 포함)
    - [ ] **TASK-120-2**: 오프라인 텔레메트리 분석 CLI(`tools/analyze_flight_log.py`) 구현 — JSONL 덤프 파일을 읽어 목표치(Setpoint) 대비 실제 측정치(Process Variable), PID 적분항 포화도, 추력 분배율 분석·요약 출력 (`tests/harness/test_tools_integrity.py` 등록 포함)

- [ ] **TASK-013: [2순위] 사양서 전수 검사 — 사양서를 포함하는 모든 `.md` 파일에 대한 정합성 감사(`specification-lifecycle-manager`) 수행 예정** (`docs/system/*.md`, `docs/specs/**/*.md`)
  - **권장 착수 순위**: **2순위** (`TASK-204` 완료, `TASK-402` 스펙 변경 수렴 직후 1회 일괄 감사 권장; `TASK-401`은 로드맵 이관)
  - **목적 및 범위**: 사양서를 포함하는 모든 `.md` 파일 전수 검사 및 문서 관리 수행 예정 (참고: `.agent/rules/skill-workflows.md` 기준 활성 사양서 전수 감사·동기화는 `specification-lifecycle-manager` 및 `tools/verify_all_specs.py`, 3계층 컨텍스트 문서(`AGENTS.md`, `GEMINI.md`, `.agent/memory/*.md`)는 `md-management` 관할)

- [ ] **TASK-117: [3순위] 무선 OTA 배포 서버 및 슬레이브 원자적 롤백 가드 구축 (구 TASK-117 + 119 통합)** (`src/0_development/ota/`, `src/0_development/installer/modules/startup_generator.lua`, `src/1_control/{vas,tca}/`, `src/2_guidance/fcp/`, `src/3_planning/amm/`)
  - **권장 착수 순위**: **3순위** (선행 과제 중 `TASK-202`·`TASK-204`·`TASK-207~209` 완료; 잔여 선행 `TASK-010`·`TASK-011`·`TASK-120` 완료 후 리소스 집중 착수)
  - **사양서 상태**: 통합 OTA 사양서 미작성(Draft → Approved 및 대상 경로 확정 필요) / 연관 개정 대상: `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` (현재 v1.1.0 Implemented), `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.29.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.14.0 Approved), `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (현재 v1.19.0 Implemented), `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (현재 v1.11.1 Implemented), `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (현재 v2.0.0 Implemented), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v2.0.0 Approved)
  - **배경 및 통합 사유**: 다중 CC:Tweaked 컴퓨터 탑재 기체(VAS, 다수 TCA, 다수 ASA, FCP, AMM)의 수동 `installer.lua` 업데이트 비용을 해소하되, `Zero-Fallback` 원칙상 체크섬 검증·`/ota_staging/` 원자적 교체 응답·안전 게이트 거부(`NACK`) 사유 코드가 서버 프로토콜에 처음부터 일체화되어야 재설계를 방지할 수 있음. 또한 비행 중 OTA 재부팅 추락 및 패킷 유실로 인한 벽돌(Brick) 장애를 막기 위해 서버와 슬레이브 부트스트랩 가드를 단일 E2E 게이트로 통합 검증함
  - **주요 작업**:
    - [ ] **TASK-117-1**: 통합 OTA 사양 및 아키텍처 동시 개정 — 격납고 예약 대역(`101 ~ 200`, `Base_hangar+4~+9`) 무선 OTA 채널(`0 ~ 100` 유선/내부 IPC 대역 배제), `/.version.json` 기반 다중 노드 주소 지정(`VAS`·`TCA`·`FCP`·`AMM`), 체크섬·원자적 교체 ACK/NACK(`NOT_DISARMED` 등) 패킷 스키마를 통합 사양서(Draft → Approved), 마스터 ICD, 전체 구조도, 인스톨러·VAS·TCA·FCP·AMM 사양서에 동시 반영
    - [ ] **TASK-117-2**: 슬레이브 OTA 에이전트 및 2단계 부트 커밋 워치독 구현 — 수신 파일을 `/ota_staging/`에 기록 후 CRC/해시 일치 시에만 본 경로로 교체하고, `pending_ota` 마커와 초기 정상 틱 커밋·예외/미커밋 재부팅 시 `/ota_backup/` 자동 복구 래퍼를 `startup.lua` 생성기에 내장 (`src/0_development/installer/modules/startup_generator.lua`)
    - [ ] **TASK-117-3**: 온보드 안전 상태 게이트 및 노드 타게팅 연동 — 기체가 `DISARMED`·지상 `IDLE_ARMED`·지상 `E_STOP`(`not isAirborne`) 등 비비행 안전 상태일 때만 OTA 수신·적용을 허용하고 비행 중에는 `NACK` 거부하는 상태 게이트 구현 (`src/1_control/{vas,tca}/`·`FCP`·`AMM` 우선 적용, `src/1_control/asa/`는 `TASK-105` 연기 해제 시 연동)
    - [ ] **TASK-117-4**: 격납고 무선 OTA 배포 서버 구축 및 매니페스트 동기화 — 격납고 마스터 컴퓨터 단일 명령으로 기체 내 슬레이브 컴퓨터 로컬 파일(`src/` 하위 패키지) 일괄 배포 및 원격 `os.reboot()` 트리거 구현 (`src/0_development/ota/` 신설 시 `manifest.lua`, `config/gdrive_mapping.json`, `verify_manifest_sync.py` 정합성 동기화 필수)
    - [ ] **TASK-117-5**: 멀티노드 OTA E2E 시뮬레이션 검증 및 사양서 승격 — 정상 일괄 배포, 비행 상태 `NACK` 거부, 체크섬 불일치 중단, 부팅 크래시 자동 `/ota_backup/` 롤백 E2E 검증 완료 후 관련 사양서 `Implemented` 승격

- [ ] **TASK-210: [대기] ASA v1.7.0 / TCA / Alignment 구현 정합화 (`MSG_AERO_*` · 채널 · 핸드셰이크 반영)** (`docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (현재 v1.7.0 Approved), `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (현재 v1.11.1 Implemented), `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (현재 v2.6.1 Implemented), `src/1_control/asa/`)
  - **선행 의존성**: `TASK-206`·`TASK-209`(`VAS v1.19.0`) 완료 및 연동; `ASA` 본 구현은 `[연기] TASK-105` 재개 시 연동
  - **배경 및 목적**: ① **[1차 검증 완료 — `TASK-207/208/209` E2E, `244c940`]** `TCA`/`Alignment` 간 채널·`AMM -> FCP -> VAS -> TCA` 4계층 재바인딩(`10000 -> 10080`) 및 UUID(`VAS-NODE-01-4402`) E2E 호환 검증 완료(Scenario 8 `4/4 PASS`, Scenario 4 `1/1 PASS`), ② `TASK-105`로 연기 중인 `ASA` 본 구현 재개 시 `Base+11` (`10011`), `bandwidth = 40`, `[I-10]` `MSG_AERO_CMD`/`MSG_AERO_STATUS` 및 `MSG_SURFACE_DISCOVER_REQ/ACK` 단일 스키마(Zero-Fallback), `AMM -> FCP -> VAS -> ASA` 4계층 재바인딩 ACK(`oldBase + 11` / `newBaseChannel + 11`)를 준수하도록 구현·검증한 뒤 `ASA` 사양서를 `Implemented`로 승격함

---

## 📋 2. 예정 백로그 (Planned Backlog — Phase 1 & 2)

### ⏸️ 연기·보류 과제 (Deferred / On-Hold)

- [ ] **[연기] TASK-103: Runway 활주로 제어기 사양서 상세화 및 활주로 제어기 코드베이스 작성** (`docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md`, `src/0_infra/runway/`)
  - **사양서 상태**: `docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md` (v1.10.7 Approved)
  - 활주로 제어기 사양서 상세화 및 코드베이스 구현: 활주로 유도등, 가상 ILS 및 유도로 `GAC` 연동 관제, 3축 ILS 글라이드슬로프/로컬라이저 비콘 송출 및 착륙 접근 프로토콜 (`TASK-116` 완료로 `0_infra` 폴더 스크롤 수용 가능; 일정 연기 — 사양서 `Approved` 유지, 구현 시 `manifest.lua` 등록 및 `verify_spec_status.py` 갱신 필요)
- [ ] **[연기] TASK-104: Docking Arm 결합 암 제어기 구현** (`src/0_infra/docking_arm/`)
  - **사양서 상태**: `docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md` (v1.11.2 Approved)
  - 2축 로봇 암 포획·인입 및 엄빌리컬 보급 시퀀스 (`AMM (Node 03)` 주도 4단계 랑데부 연동; 일정 연기 — 사양서 `Approved` 유지, 구현 시 `manifest.lua` 등록 및 `verify_spec_status.py` 갱신 필요)
- [ ] **[연기] TASK-105: ASA (Aerodynamic Surface Adapter) 공력 조종면·플랩 분산 구동기 본 구현 완성** (`src/1_control/asa/`)
  - **사양서 상태**: `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (v1.7.0 Approved)
  - TASK-113의 기본 프레임워크(헤드리스/비동기 TUI, `Base+11` 수신 루프, 300ms Safe Glide Trim, 단위 테스트 15/15 PASS)를 기반으로 물리 액추에이터(Avionics API/RS) 각도 인가, `MSG_AERO_STATUS` 상태 피드백 송출 및 `MSG_SURFACE_DISCOVER_REQ/ACK` 핸드셰이크 완성 (`TASK-210` 연동; 일정 연기 — 사양서 `Approved` 유지; 재개 시 `manifest.lua`·`verify_spec_status.py` 갱신 및 `tools/verify_manifest_sync.py` `DEFERRED_SUBSYSTEM_DIRS` 면제 해제 필요)
- [ ] **[연기] TASK-108: Tower ATC (Sector 0, `CH 50001/50002`) 광역 항공교통 관제 노드 구현**
  - **사양서 상태**: 별도 사양서 미작성 (마스터 ICD `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.29.0 Approved) Interface I-5 기반 `AMM (Node 03)` 교신 규격; 착수 전 사양서 Draft → Approved 또는 ICD 연계 필요)
  - 광역 공역 진입/이탈 스케줄링 및 섹터 `GAC` 핸드오프 프로토콜 구현 (일정 연기)
- [ ] **[연기] TASK-401: PAYLOAD 계층(Zone 3) 통신 스키마 정의** (`docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.29.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.14.0 Approved), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v2.0.0 Approved), `docs/specs/4_mission/`)
  - **상태 및 이관 사유**: 선행 우선순위 취소 및 로드맵 백로그 이관 (`TASK-204`는 현행 `AMM v1.3.0` 기본 `PAYLOAD_ACTION`/`REDSTONE_ACTION`/`POI` 계약으로 독립 착수)
  - **사양서 상태**: PAYLOAD 계층 전용 사양서 미작성 (Draft → Approved 수립 및 마스터 ICD Interface I-11·전체 구조도·AMM 사양서 동기화 필요)
  - **배경 및 목적**: 현행 마스터 ICD Interface I-11(`Base+20~29`, Zone 3 탑재체 버스)에는 `MSG_PAYLOAD_REQ`/`MSG_PAYLOAD_ACK` 기본 예시 패킷만 정의되어 있으며, 전체 구조도의 세부 채널 구분(`Base+20` `CH_PAYLOAD_BUS`, `Base+21` `CH_WEAPON_BUS`, `Base+22~29` 예비) 및 다양한 탑재체 노드(화물 투하, 마그넷 래치, 엄빌리컬 급유/충전, `CC:Radars`/터렛 무장 제어 등) 간 표준 통신 계약이 미비함. 탐색/기능 등록(Discovery & Capability), 상태/헬스 텔레메트리, 명령·응답(`ACK`/`NACK`)·오류 코드, 안전 인터록 및 채널 오프셋 배분 규칙을 포함한 PAYLOAD 계층 표준 통신 스키마를 정의함
  - **주요 작업**:
    - [ ] **TASK-401-1**: 세부 탑재체 표준 행동군(`ACT_PAY_*` 하위 `[로드맵: TASK-401]` `TBD` 항목: 화물 투하 `CARGO_DROP`, `CC:Radars` 무장 사격 `FIRE_CTRL`, `geoScanner` 주기 스캔 등) 및 Zone 3 채널(`Base+20~29`)·안전 인터록 스키마 확정 (`docs/superpowers/specs/2026-11-12-task-204-action-primitive-design.md` §3.6 연계)

### 🔭 Phase 3 백로그 (Phase 3 Backlog)

- [ ] **[연기] TASK-301: 물리 하드웨어 기반 ACRO 수동 급기동 조종 인터페이스 개발**
  - Create/Avionics 아날로그 스틱 및 물리 컨트롤러 하드웨어 연동 (일정 연기)
  - `Base+1` 20Hz 직접 3축 각속도(`RATE_COMMAND`) 직결 스트림 및 비행 제어 코어(VAS) 선점 제어 연동

---

## ✅ 3. 완료된 작업 이력 (Completed Tasks Archive — 최근 10개 유지)

- [x] **TASK-204: AMM v2.0.0 표준 행동 리스트(`ACT_*`/`DEC_*`/`MAC_*`) 재정의, 진입조건 및 채터링 방지 가드 통합** (완료일: 2026-11-14) (`docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v2.0.0 Approved), `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (현재 v0.2.0 Draft), `src/3_planning/amm/`, `src/0_development/installer/modules/manifest.lua`, `tests/3_planning/amm/`)
  - **설계 기준 문서**: `docs/superpowers/specs/2026-11-12-task-204-action-primitive-design.md`, `docs/superpowers/specs/2026-11-13-task-204-chattering-prevention-design.md`
  - **목적 및 성과**: 구 13종 평면적 체크포인트 체계를 Zero-Fallback 폐기하고 `AMM v2.0.0`(`ACT_*`/`DEC_*`/`MAC_*`/진입조건/방안 A 채터링 방지 가드) 체계로 사양서 15종(마스터 ICD `v1.29.0 Approved`, 전체 구조도 `v2.14.0 Approved`, `AMM` `v2.0.0 Approved`, 에디터 `v0.2.0 Draft` + 연관 11종 배지) 및 런타임·테스트를 전면 개편함 (`AMM` 사양서는 `TASK-402` WebUI 에디터 구현 완료 시 `Implemented` 승격 예정). 단위 12타겟 `469/469 PASS`(`3_planning/amm` `122/122 PASS`), E2E 8스위트 `12/12 PASS`, 돌연변이 `25/25 KILLED`(`100.0%`), Lua 5.2 `123/123 PASS`, 매니페스트 3자 정합성(`112` 경로/`126` 소스)·사양서 15종 `0 Errors, 0 Warnings` 달성.
  - **구현 내용**:
    - [x] **TASK-204-1**: `AMM_PROGRAM_SPECIFICATION.md` (`v2.0.0 Approved`)·`AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.2.0 Draft`)·마스터 ICD (`v1.29.0 Approved`)·전체 구조도 (`v2.14.0 Approved`) 및 연관 11종 사양서 동기화
    - [x] **TASK-204-2**: `action_registry.lua` 구현 — 활성 36종 `ACT_*`·예약 22종·레거시 13종 `SCHEMA_INVALID` 차단·6+1종 `DEC_*`·3+2종 `MAC_*` (`deep_copy` 전개)·4대 정적/동적 진입조건 및 단위 테스트
    - [x] **TASK-204-3**: `chattering_guard.lua` 구현 — 방안 A(`PRIORITY`, `DEFAULT_CONFIG`, `init`, `reset`, `eval_hysteresis`, `eval_debounce`, `start_dwell`, `is_dwell_locked`, `update_fuel_latches`, `should_skip_on_repeat`) 및 `amm_config.json` `v2.0.0`(`safety.chattering` 20키) 정합화
    - [x] **TASK-204-4**: `condition_evaluator.lua`·`hook_runner.lua`·`ui_renderer.lua`·`input_handler.lua`(`guard`/`confirm`)·`c2_arbiter.lua`·`mission_engine.lua`·`main.lua`(`ACT_NAV_SPLINE_WP`/`ACT_TKL_LAND_PREC`, `DEC_EMCON` GPS 억제, `set_cruise_goal`/`set_land_goal` 2인자 수정) 통합
    - [x] **TASK-204-5**: `manifest.lua`(`v2.0.0` + `action_registry.lua`/`chattering_guard.lua`) 동기화 및 `tests/3_planning/amm/`(`122/122 PASS`)·전체 회귀 검증(`469/469 PASS`, E2E `12/12 PASS`, 돌연변이 `25/25 KILLED`)

- [x] **TASK-123: GPS 고부하 경합·위상 버스트·모뎀 채널 오염 결함 수정** (완료일: 2026-11-14, 커밋 `e9fdce4`) (`src/0_infra/gps/`, `src/0_infra/landing_pad/`, `src/3_planning/amm/modules/nav_engine.lua`, `tests/`)
  - **목적 및 성과**: 고부하 다기체 GPS 환경의 응답 순서 역전, 동시 기동 In-cast 버스트, 지상 패드 `CH 60001` 모뎀 오염 결함을 수정하고 `GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v2.3.2 Implemented`), `LANDING_PAD_SPECIFICATION_AND_ICD.md` (`v2.4.4 Implemented`) 및 연관 사양서 배지를 동기화함.
  - **구현 내용**:
    - [x] **TASK-123-1**: `src/0_infra/gps/modules/session_scheduler.lua` 선제 세션 대체 및 Window-Solve HWM 역전 가드 구현
    - [x] **TASK-123-2**: `src/0_infra/gps/modules/client_core.lua` 단조 증가 시퀀스 수신 필터 및 `CH 60001` 미개방 보강
    - [x] **TASK-123-3**: `src/0_infra/landing_pad/modules/gps_client.lua`·`src/3_planning/amm/modules/nav_engine.lua` 결정론적 틱 위상 분산 적용
    - [x] **TASK-123-4**: `src/0_infra/landing_pad/main.lua` `GPS_PING_CHANNEL`(`60001`) 모뎀 수신 개방 제거(송신 전용화)
    - [x] **TASK-123-5**: GPS·착륙패드·AMM 단위 테스트 및 `tests/e2e/test_e2e_gps_triangulation.lua` 고부하/위상/채널 회귀 검증 완료

- [x] **TASK-124: `TASK-204` 착수 전 채터링 방지 규칙 문서 인게임/코드베이스 정합 개정 및 설계서 동기화** (완료일: 2026-11-13, 커밋 `f2e7b10`, `b85677c`) (`docs/superpowers/specs/2026-11-13-task-204-chattering-prevention-design.md`, `docs/superpowers/specs/2026-11-12-task-204-action-primitive-design.md`)
  - **목적 및 성과**: `TASK-204` 착수 전 상태 전이 경계 채터링 방지 규격을 마인크래프트 `CC:Tweaked (Lua 5.2)` 및 현행 UAFS 코드베이스 제약에 맞춰 확정함. `[즉시]` 36종 본 규격과 `[로드맵]`(`LOCAL_AVOID`/`REPLAN_GLB`·서브컨트랩션 동결) 격리, `step_20hz_tick` 정수 틱 vs 통신 워치독 `now_ms` 이원화, `amm_config.json` 고정 파라미터 직접 지정(참고 수식은 부록 A 격리), `TCA` 레드스톤 0~15 양자화 Limit Cycle 방지용 `N_settle`·이탈 불감대, `nav_engine.lua` `validStreak >= 3`·`fcp_config.json` `wingedVtolVLowMps(8.0)`/`VHighMps(18.0)` 정합화, **방안 A**(`chattering_guard.lua` 중앙 전이 가드 + `condition_evaluator` `settleTicks`) 아키텍처 채택 및 `2026-11-12` 설계서 연료 임계값(`0.20`/`0.10`, `Base+2` `fuel(0.0~1.0)` 단독) 역통일을 완료함.
  - **구현 내용**:
    - [x] **TASK-124-1**: `TASK-204` 채터링 방지 가드 AMM 내부 아키텍처(**방안 A** 중앙 전이 가드 `chattering_guard.lua` + `settleTicks`) 확정 및 설계 문서(`docs/superpowers/specs/2026-11-13-task-204-chattering-prevention-design.md`) 작성
    - [x] **TASK-124-2**: `docs/superpowers/specs/2026-11-12-task-204-action-primitive-design.md` 연료 임계값(`0.30`/`0.15` → `0.20`/`0.10`) 동기화 및 상호 링크 반영

- [x] **TASK-209: VAS v1.19.0 `QUATERNION_RATE` 내루프 정규화 및 ACRO/페일세이프 정합화** (완료일: 2026-11-13, 커밋 `3c82f7f`, `83ff1f6`, `244c940`, `7b19207`) (`docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (현재 v1.19.0 Implemented), `src/1_control/vas/`, `tests/1_control/vas/`, `tests/e2e/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-12-task-207-208-209-sequential-plan.md`
  - **목적 및 성과**: `Base+1` `[I-2]` 수신 스키마를 `QUATERNION_RATE`/`RATE_COMMAND`(`targetQuaternion`, `targetAngularRates`, `collectiveThrust`, 선택적 `flapTarget`/`translationBias {surge, sway}`) 단일 경로(Zero-Fallback, `ATTITUDE_ANGLE` 제거)로 정규화하고, 정상 비행 `compute_climb_wrench`를 제거해 `FAILSAFE_HOLD`(`FCP_TIMEOUT` 1,500ms $\to$ 10s $\to$ `EMERGENCY_LAND`) 한정 격리함. `E_STOP (ESTOP_CONFIRM_KEY) > MFD_ACRO > FCP` 선점 중재, `Base+3` `CORE_ACRO_TAKEOVER` 20Hz HUD 직결 및 침묵 가드, `[I-10]` `MSG_AERO_*`/`MSG_SURFACE_DISCOVER_*`, `config/system.json`(`trajectory: 4`, `asaActuation: 11`, `fcpCommandTimeoutMs: 1500`, `flapVfeLimit: 15.0`) 및 `satAsa`/`satTca`/`fcpCmd` 정합화를 완료하고 `VAS v1.19.0` 사양서를 `Implemented`로 승격함. 4노드 폐루프 E2E(`test_e2e_4tier_closed_loop.lua` Scenario 8 `4/4 PASS`), 전계층 단위 12타겟 `455/455 PASS`(`1_control/vas` `46/46`), E2E 8스위트 `12/12 PASS`, 돌연변이 `25/25 KILLED`(`100.0%`), 하네스 `82/82 PASS`, Lua 5.2 `121/121 PASS`, 매니페스트 3자 정합성 `0 Errors, 0 Warnings`, 사양서 15종(`9 Implemented, 6 Approved`) `0 Errors, 0 Warnings` 달성.

- [x] **TASK-208: FCP v2.0.0 SE(3) 외루프 제어기 경량화 전면 개편** (완료일: 2026-11-13, 커밋 `26d8365`, `ea66b21`, `3fd3c46`, `9c8af01`, `319d659`, `244c940`, `7b19207`) (`docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (현재 v2.0.0 Implemented), `src/2_guidance/fcp/`, `tests/2_guidance/fcp/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-12-task-207-208-209-sequential-plan.md`
  - **목적 및 성과**: `FCP (Node 04)`를 단일 `top` 모뎀 3채널(`Base+4`, `Base+2`, `Base+1`) 전용 순수 온보드 `SE(3)` 외루프 제어기로 축소 개편함. `network_manager.lua` 3채널 격리 및 `MSG_CHANNEL_REBIND` 중계, `state_propagator.lua` 로컬 속도 적분(`dt <= 0.1s`, `posMergeMaxStepM = 2.0`, `500ms` `navStale`), `flight_fsm.lua` 6상태 FSM(`BOOT`, `IDLE_ARMED`, `ACTIVE_TRACKING`, `PASSIVE_TRACKING` 2.0s 범프리스 램핑, `AMM_TIMEOUT_HOLD` 500ms $\to$ 10s $\to$ `EMERGENCY_LAND`), `outer_loop_controller.lua` 통합 `SE(3)` 법칙($g = 11.0\text{ m/s}^2$, 조건부 안티와인드업, 6대 기체 `QUATERNION_RATE` 투영, `STRICT_LEVEL`/`TILT_ASSISTED` + 스웨이 결손 폴백, 멀티로터 $25^\circ$, 유익 VTOL `[8, 18] m/s`, 고정익 BTT+TECS)을 구현하고 레거시 14개 파일·외부 RF·`/etc/vac/` 경로를 제거해 `manifest.lua`·`gdrive_mapping.json`·돌연변이 테스트(`MUT-14`/`15`/`23`)를 동기화하고 `FCP v2.0.0` 사양서를 `Implemented`로 승격함. 단위 `2_guidance/fcp` `46/46 PASS`(전계층 `455/455`), Scenario 8 `4/4 PASS`, 돌연변이 `25/25 KILLED` 달성.

- [x] **TASK-207: AMM v1.3.0 외부 게이트웨이·항법 융합·20Hz 궤적 생성기 구현** (완료일: 2026-11-13, 커밋 `52dc141`, `829d6a4`, `86a2701`, `28aceaf`, `8673e38`, `bd1539c`, `244c940`, `7b19207`) (`docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (당시 v1.3.0 Approved), `src/3_planning/amm/`, `tests/3_planning/amm/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-12-task-207-208-209-sequential-plan.md`
  - **목적 및 성과**: `AMM (Node 03)`에 듀얼 모뎀(`top`+`back`, 단일 모뎀 폴백), `channel_sentinel.lua`(`CH 50000`, `200ms` 프로브, 4계층 재바인딩, `MUT-03`), `nav_engine.lua`(`TASK-122` GPS+DR $\alpha=0.35$, `degradedAlpha=0.10`, `5,000ms` DR 선회, `posEpoch`, `CH 60001` 송신 전용 미개방; 위상 분산은 `TASK-123` 연계), `facility_client.lua`(Tower ATC/GAC/Runway/Docking/Landing Pad 2차 테일러 외삽 $\le 0.5\text{s}$, `300ms` 워치독, `15s x 10` 재시도), `trajectory_generator.lua`(11종 비행 모드, `LOITER` `ffAccel`, `POI_HOLD` $\le 30^\circ/\text{s}$, `-0.8` 도킹 이탈, 가상 ILS, 2단계 터치다운, `-2.0` 비상 강하), `Base+4` `[I-12]` 20Hz 송수신, `Base+3` 5Hz MFD 다운링크(`MFD_ACRO` 양보), `E_STOP` `authKey` 및 Coroutine A(20Hz)/B(5Hz) 분리를 구현함. 단위 `3_planning/amm` `112/112 PASS`(전계층 `455/455`), Scenario 8 `4/4 PASS`, 돌연변이 `25/25 KILLED` 달성 (`AMM` 사양서는 `TASK-402` WebUI 에디터 구현 완료 시 `Implemented` 승격 예정).

- [x] **TASK-202: UAFS 통합 미션 시퀀서 엔진, AMM 조종석 단말 및 WebUI 에디터 사양 수립 (구 TASK-201[AMP 초안] + 203 통합)** (완료일: 2026-11-12) (`src/3_planning/amm/`, `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (당시 v0.1.0 Draft))
  - **실행 계획서**: `docs/superpowers/plans/2026-11-11-task-202-2-amm-mission-core-hooks-zone3.md`, `docs/superpowers/plans/2026-11-11-task-202-3-amm-mission-fsm-c2-headless.md`, `docs/superpowers/plans/2026-11-11-task-202-4-amm-tui-resolver-drop-cli.md`, `docs/superpowers/plans/2026-11-12-task-202-5-amm-webui-editor-spec.md` (초안: `docs/superpowers/plans/2026-11-08-amp-mission-planner.md`, `docs/superpowers/plans/2026-11-11-amm-webui-editor-spec-draft.md`)
  - **목적 및 성과**: Layer 3(AMM)과 구 Layer 4(AMP) 미션 시퀀서를 3분할 코어(`mission_engine.lua`, `condition_evaluator.lua`, `hook_runner.lua`)로 통합하고 51x19 6행 스크롤 뷰포트·다중 경로 리졸버·프리플라이트 검증기·`file_transfer` 핫인젝션·헤드리스 C2(`Base+0`)를 구현했으며(`TASK-202-1~4`), 호스트 PC 외부 비주얼 에디터(`tools/amm_mission_editor.html`)의 `AMM v1.3.0` 정합 상세 규격서(`AMM_MISSION_EDITOR_SPECIFICATION.md` `v0.1.0 Draft`)를 수립해 후속 HTML 구현(`TASK-402`)으로 인계함 (`docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` 당시 v1.3.0 Approved, `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` 당시 v1.28.0 Approved, `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` 당시 v2.13.0 Approved).
  - **구현 내용**:
    - [x] **TASK-202-1**: AMM 사양서(당시 v1.2.0 Approved), 마스터 ICD(당시 v1.27.0 Approved), 전체 구조도(당시 v2.12.1 Approved) 통합 미션 스키마·Zone 3·외부 파일 즉시 구동 규격 반영 완료 (2026-11-11)
    - [x] **TASK-202-2**: 13종 체크포인트 스키마, 12종 조건 평가기(`condition_evaluator.lua`), 0-tick 훅(`hook_runner.lua`), Zone 3(`Base+20~29`) 연동 구현 완료 (2026-11-11, `3_planning/amm` 48/48 PASS)
    - [x] **TASK-202-3**: 다형성 로더·자동 전이 FSM(`mission_engine.lua`), `c2_arbiter.lua` `MSG_MISSION_CMD`/`ACK` 중재 및 `config.headless` 분기 구현 완료 (2026-11-11, 단위 361/361 PASS, `3_planning/amm` 60/60 PASS)
    - [x] **TASK-202-4**: 51x19 TUI 6행 뷰포트·5행 조건 진행률(`ui_renderer.lua`), `resolve_path`·`validate_mission_table`, `SCHEMA_INVALID` ACK, `file_transfer` 드롭/부팅 인자·CLI 확장 완료 (2026-11-12, `fa91084`..`d3b3b8b`, 단위 372/372 PASS·`3_planning/amm` 71/71 PASS, E2E 8/8 PASS, 돌연변이 25/25 KILLED)
    - [x] **TASK-202-5**: 호스트 PC 외부 비주얼 미션 에디터 사양서 `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.1.0 Draft`) 작성 완료 (`AMM v1.3.0` / `ICD v1.28.0` / `Diagram v2.13.0` 정합화, `version: "1.3.0"` 출력 및 `v1.0.0`~`v1.2.0` 호환, 13종 액션·12종 조건·4종 훅·`validateMission()` 카탈로그·2D `(X,Z)` 캔버스·`TASK-402` 인수 기준 명세; HTML 구현은 `TASK-402` 분리) (2026-11-12)

- [x] **TASK-206: FCP 외루프 경량화 및 AMM 상위 계층 이관을 위한 15대 사양서 전면 개편** (완료일: 2026-11-12) (`docs/system/*.md`, `docs/specs/**/*.md`, `tools/verify_spec_status.py`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-11-fcp-amm-role-refactor-specs.md`
  - **목적 및 성과**: `FCP (Node 04)`를 단일 `top` 모뎀 3채널(`Base+4/+2/+1`) 온보드 `SE(3)` 외루프 제어기($g = 11.0\text{ m/s}^2$, 6상태 FSM)로 경량화하고, 외부 게이트웨이(`CH 50000~50004`, `CH 60001/60002`, `Base_sec+*`, `Base+5`), C2/MFD(`Base+0`/`+3`), GPS+DR 항법 융합 및 20Hz 궤적 생성 책임을 `AMM (Node 03)`으로 이관하는 Spec-First 개편 완료 (`src/` 무수정; `7 Implemented, 8 Approved` 전이). 3대 와이어 계약(`AMM->FCP` `Base+4` `[I-12]` `MSG_TRAJECTORY_SETPOINT`/`MSG_OUTER_LOOP_STATUS`, `FCP->VAS` `Base+1` `QUATERNION_RATE`, `VAS->ASA` `Base+11` `MSG_AERO_CMD`/`STATUS` 단일화) 및 3계층 페일세이프 격리(`AMM`/`FCP 500ms`/`VAS 1500ms`)를 정립하고, 레거시 필드(`[DEPRECATED]`) 및 14종 사양서의 잔존 결함(`10007`, `10045`, `BW=20`, `MAX_CRAFT_LIMIT = 2000`, `system.json`, `FCP-NODE-04-4402` 등)을 일괄 정정함. `verify_all_specs.py --check-readmes` `0 Errors, 0 Warnings`, `verify_spec_status.py` `7 Implemented, 8 Approved PASS`, `verify_context_docs.py` `0 findings`, 하네스 `82/82 PASS`, `validate_lua_syntax.py` `129/129 PASS` 달성 및 후속 구현 태스크(`TASK-207~210`) 등록.
  - **개정 내용**:
    - [x] **TASK-206-1**: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.28.0 Approved`) — `[I-1..I-11]` 이관, `Base+4` `[I-12]` 신설, `[I-2]` `QUATERNION_RATE` 정규화, `[I-10]` `MSG_AERO_*` 통일, 섹션 4~5 워치독·상태표 갱신 및 기존 결함 정정
    - [x] **TASK-206-2**: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.13.0 Approved`) — 4계층 Mermaid 구조도·6기종 흐름도·패킷 교환 매트릭스·6대 시퀀스·채널 매트릭스 갱신 및 `BW=20`/`2000`/`Base+6/7` 정정
    - [x] **TASK-206-3**: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v1.3.0 Approved`) — 듀얼 모뎀·`20Hz`/`5Hz` 코루틴 분리·`nav_engine`/`facility_client`/`channel_sentinel`/`trajectory_generator`·`Base+4` `[I-12]`·1계층 페일세이프 신설 (`v1.2.0` 미션/에디터 규격 보존)
    - [x] **TASK-206-4**: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (`v2.0.0 Approved`) — 3채널 `SE(3)` 외루프 수학 법칙($g=11.0\text{ m/s}^2$)·6기종 투영·6상태 FSM(`PASSIVE_TRACKING`/`AMM_TIMEOUT_HOLD`) 축소 및 외부 RF·`/etc/vac/` `[DEPRECATED]`/제거
    - [x] **TASK-206-5**: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (`v1.19.0 Approved`) — `QUATERNION_RATE` 단일화·정상 비행 승강 PI 제거(`FAILSAFE_HOLD` 한정)·`AMM` `[I-1]`/`Base+3` ACRO 양보·`system.json` 및 잔존 식별자 결함 정정
    - [x] **TASK-206-6**: 제어·교정 사양서 3종 — `ASA` (`v1.7.0 Approved`, `10007`/`+7`/`bw=20` 정정), `TCA` (`v1.11.1 Implemented`, `AMM->FCP->VAS` 재바인딩 및 `+6` 정정), `ALIGNMENT` (`v2.6.1 Implemented`, `VAS-NODE-01-4402` 정정)
    - [x] **TASK-206-7**: 지상 인프라 6종 — `RUNWAY` (`v1.10.7 Approved`), `DOCKING_ARM` (`v1.11.2 Approved`), `GAC` (`v1.4.2 Implemented`), `LANDING_PAD` (`v2.4.3 Implemented`), `GCS` (`v1.0.2 Implemented`), `GPS` (`v2.3.1 Implemented`, `10045`→`10005`) 기체 측 교신 주체를 `AMM (Node 03)`으로 일원화
    - [x] **TASK-206-8**: `tools/verify_spec_status.py` (`7 Implemented, 8 Approved`)·`TASK.md`·`GEMINI.md`·`.agent/memory/workspace-root.md` 동기화 및 전수 정적·하네스 검증 통과

- [x] **TASK-122: GPS ↔ 클라이언트 프로토콜 정합화 및 런타임 보강** (완료일: 2026-11-12, 커밋 `1bf123a`, `83f8758`, `195cf8f`, `53aa25f`, `bece209`, `aa7a52c`, `bf1353f`, `133bc49`, `b6db171`, `ead5a56`, `b0b371e`, `43874af`) (`docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`, 당시 `v2.3.0 Implemented`, `src/0_infra/gps/`, `src/0_infra/landing_pad/`, `src/2_guidance/fcp/`, `tests/e2e/test_e2e_gps_triangulation.lua`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-11-task-122-gps-client-protocol-sync.md`
  - **목적 및 성과**: 중앙 GPS 클러스터(`server.lua`, `session_scheduler.lua`, `node.lua`, `monitor_ui.lua`, `wizard_cli.lua`), GPS Client HAL(`client_core.lua`, `gps_client.lua`), 착륙패드(`docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md`, 당시 `v2.4.2 Implemented`), FCP(`docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`, 당시 `v1.16.0 Implemented`) 간 와이어 프로토콜 및 런타임 불일치를 정합화하고, Scenario 3 실노드 폐루프 E2E 검증으로 통합 동작을 확인함 (`docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` 당시 `v1.27.0 Approved`, `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` 당시 `v2.12.1 Approved`). 브랜치 단위 392/392 PASS(`main` 병합 기준 403/403 PASS — `gps` 27/27, `landing_pad` 44/44, `fcp` 50/50, `amm` 71/71), E2E 8/8 PASS(7시나리오), 돌연변이 25/25 KILLED(100.0%), 하네스 82/82 PASS, Lua 129/129 PASS, 정적·사양서 15종(당시 `9 Implemented, 6 Approved`) `0 Errors, 0 Warnings` 달성.
  - **구현 내용**:
    - [x] **TASK-122-1**: GPS 사양서(당시 v2.3.0 Approved → Implemented) 개정 및 마스터 ICD(`v1.27.0`)·전체 구조도(`v2.12.1`)·FCP·착륙패드 사양서 GPS 참조 배지·재시도 의사코드 동기화 (`1bf123a`, `83f8758`)
    - [x] **TASK-122-2**: GPS 서버·스케줄러·노드·모니터 UI·커미셔닝 수정 (`EARLY_SOLVED` `replyChannel` 반환, `FAIL_GEOMETRY` 150ms 단기 툼스톤 및 HWM 비갱신, 만료 세션 결정론적 정렬, 미등록 하트비트 게이트, `CH 60002` 상태 응답, `payload.pos`, `monitor_ui` `%-10s`, `wizard_cli.writeJsonAtomic`) (`195cf8f`, `53aa25f`)
    - [x] **TASK-122-3**: GPS Client HAL 보강 (`client_core.lua` `pendingResponses` 5000ms TTL 정리, `gps_client.lua` `isManaged` 50% 타임아웃 재시도 동등성, 채널 정리 및 `CH 60002` `queryStatus` API) (`bece209`, `aa7a52c`)
    - [x] **TASK-122-4**: 착륙패드 GPS 클라이언트 Zero-Fallback·설정 정규화 및 이중 주기(`1Hz`/`5Hz`/`STATIC`) 구현 (`config_store.normalize_config`, `setup_wizard`, `Base_sec+5` `50206`, `"FACILITY"`/`"FIX_OK"`/`"FIX_DEGRADED"`, 이동성 정규화 및 플랫 채널 우선순위) (`bf1353f`, `133bc49`)
    - [x] **TASK-122-5**: FCP GPS 엔벨로프 `time` 표준화, `targetClient`/`clientSeq` 및 `now_ms` 방어, 경과시간 기반 동역학 게이트 `delta_t` 및 `altitudeY` 동기화 (`network_manager.lua`, `nav_engine.lua`) (`b6db171`, `ead5a56`)
    - [x] **TASK-122-6**: Scenario 3 실노드 폐루프 E2E 검증(`test_e2e_gps_triangulation.lua`: FCP 4노드 `EARLY_SOLVED`/스푸핑 차단/`altitudeY`, 3노드 공선 `FAIL_GEOMETRY` 및 250ms 재시도, `CH 60002` 상태 조회, 착륙패드 `FACILITY` `50206`/재전송 거부), GPS 사양서 `Implemented` 승격, 전계층 회귀 및 컨텍스트 동기화

- [x] **TASK-201: FCP 외루프 유도 프리미티브(`LOITER` 선회 반경 제어 & `POI_HOLD` 관심점 지향) 확장** (완료일: 2026-11-11, 커밋 `d3c5fef`, `ddaf428`, `f218830`, `ecff4f4`, `fb08520`) (`docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`, 당시 `v1.16.0 Implemented`, `src/2_guidance/fcp/`, `tests/2_guidance/fcp/`, `tests/e2e/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-11-task-201-fcp-loiter-poi-hold.md`
  - **목적 및 성과**: 상위 `AMM`(`docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`, 당시 `v1.2.0 Approved`)의 전술 기동을 지원하기 위해 `VECTORED_VTOL` 및 `ADVANCED_VTOL` 외루프 드라이버에 `LOITER`(반경 $R \ge 5.0\text{ m}$·CW/CCW 접선 벡터, 중심 특이점 회피) 및 `POI_HOLD`(관심점 조준 3D 호버)와 3종 기수 지향 모드(`AUTO`/`FACE_PATH`, `FIXED`, `POI`/`TARGET_LOCK`/`ORBIT_POINT`, $<0.5\text{ m}$ 요 고정, $30.0^\circ/\text{s}$ 슬루, `LOITER`/`POI_HOLD` 중 `STRICT_LEVEL` $0.0^\circ$ 피치 강제)를 구현함 (`DEFERRED_AIRFRAMES` 4종 차단 및 `flapTarget == 0.0` 유지). 또한 `operator_handler.lua` `Base+0` 파라미터 정규화(`NaN`/`Inf` 차단 포함)·`PILOT_OVERRIDE_ACTIVE` 보호, `guidance_controller.lua` 2.0초 범프리스 램핑(`rampStartMs = -10000`, `FAILSAFE_HOLD` 복귀 시 짐벌 연속성 유지), `fcp_runtime.lua` 지상 대기 C2 중심점 동결·램프 방지 및 `distanceToWp` 다운링크를 통합함. 단위 330/330 PASS(12타겟, `fcp` 45/45), E2E 8/8 PASS(7시나리오), 돌연변이 25/25 KILLED(100.0%), 하네스 82/82 PASS, 정적 3종·사양서 15종(당시 `9 Implemented, 6 Approved`)·Lua 126/126 PASS 달성.
  - **구현 내용**:
    - [x] **TASK-201-1**: FCP 사양서(당시 v1.16.0 Approved → Implemented) 개정 및 마스터 ICD(`docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`, 당시 `v1.27.0 Approved`)·전체 구조도(`docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`, 당시 `v2.12.1 Approved`)·AMM 사양서 FCP 참조 배지 동기화 (`d3c5fef`)
    - [x] **TASK-201-2**: `flight_fsm.lua` `POI_HOLD` 16상태 확장(`MUT-14` 보존), `vectored_vtol_driver.lua`·`advanced_vtol_driver.lua` `resolve_horizontal_error`/`compute_heading` 및 `fcp_config.json` 기본값 구현 (`ddaf428`)
    - [x] **TASK-201-3**: `operator_handler.lua` `MSG_OPERATOR_CMD` 정규화·권한 보호, `guidance_controller.lua` `trigger_bumpless_transition`, `fcp_runtime.lua` C2 배선 및 `distanceToWp` 구현 (`f218830`)
    - [x] **TASK-201-4**: E2E 시나리오 2(`test_e2e_waypoint_guidance.lua` Step 9) 검증(`ecff4f4`), 리뷰 보완 패치(`NaN`/`Inf` 방어·`FAILSAFE_HOLD` 연속성·지상 C2 가드·고도 앵커링, `fb08520`), FCP 사양서 `Implemented` 승격 및 컨텍스트 동기화
