# Create_Aeroneutics — Task Management & Implementation Roadmap

> **문서 상태**: 활성 (Living Roadmap)  
> **최종 갱신일**: 2026-11-12  
> **현재 단계**: **Phase 1 & 2** (직전 완료: TASK-201, TASK-202-1~4 / 진행 중: TASK-202-5 / 활성 대기: TASK-010, 011, 013, 117, 120, 122, 204, 206, 401)

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
  - [ ] **TASK-010-5**: 유도 및 임무 도메인 매뉴얼(`playbook/2_guidance/fcp.md`, `playbook/3_planning/amm.md`) 작성 (`TASK-201` `LOITER`/`POI_HOLD` 및 `TASK-202` AMM v1.2.0 3분할 미션 시퀀서·CLI/TUI·외부 에디터/파일 즉시 구동 규격 반영)
  - [ ] **TASK-010-6**: 프로젝트 규칙 반영, 컨텍스트 동기화 및 검증 (`test_tools_integrity.py` 도구 등록·`verify_context_docs.py` 통과 및 `TASK-009`·`113`·`114`·`115`·`116` 현행 반영 확인)

- [ ] **TASK-011: [인프라 매뉴얼] 지상 관제 및 정비 도메인 플레이북 2차 확장 (Alignment, GCS, GAC, Landing Pad)** (`playbook/0_development/alignment.md`, `playbook/0_infra/{gcs,gac,landing_pad}.md`)
  - **선행 의존성**: `TASK-010` 완료 필요 (표준 7대 섹션 템플릿 `playbook/README.md` 및 `tools/verify_playbooks.py` 검증 체계 활용)
  - **배경 및 필요성**: `TASK-010`은 핵심 5종(GPS, VAS, TCA, FCP, AMM)에 집중되어 있으나, 실제 인게임 운용 시 설정·조작이 가장 까다로운 격납고 동역학 캘리브레이션(Alignment)과 지상 관제소/패드 셋업(GCS, GAC, Landing Pad) 매뉴얼 보강 필요
  - **주요 작업**:
    - [ ] **TASK-011-1**: 격납고 동역학 캘리브레이션 매뉴얼(`playbook/0_development/alignment.md`) 작성
    - [ ] **TASK-011-2**: 중앙 지상 관제소 매뉴얼(`playbook/0_infra/gcs.md`) 작성
    - [ ] **TASK-011-3**: 섹터 관제·착륙패드 매뉴얼(`playbook/0_infra/gac.md`, `playbook/0_infra/landing_pad.md`) 작성
    - [ ] **TASK-011-4**: `tools/verify_playbooks.py` 7대 섹션·링크·인가 목록 정적 검증 통과

- [ ] **TASK-013: 사양서 전수 검사 — 사양서를 포함하는 모든 `.md` 파일에 대한 `md-management` 수행 예정** (`docs/system/*.md`, `docs/specs/**/*.md`)
  - **목적 및 범위**: 사양서를 포함하는 모든 `.md` 파일 전수 검사 및 문서 관리 수행 예정 (참고: `.agent/rules/skill-workflows.md` 기준 활성 사양서 전수 감사·동기화는 `specification-lifecycle-manager` 및 `tools/verify_all_specs.py`, 3계층 컨텍스트 문서(`AGENTS.md`, `GEMINI.md`, `.agent/memory/*.md`)는 `md-management` 관할)

- [ ] **TASK-117: [4순위] 무선 OTA 배포 서버 및 슬레이브 원자적 롤백 가드 구축 (구 TASK-117 + 119 통합)** (`src/0_development/ota/`, `src/0_development/installer/modules/startup_generator.lua`, `src/1_control/{vas,tca}/`, `src/2_guidance/fcp/`, `src/3_planning/amm/`)
  - **권장 착수 순위**: **4순위** (선행 기능·문서·진단 과제인 `TASK-202`·`TASK-204`·`TASK-010`·`TASK-011`·`TASK-120` 완료 후 리소스 집중 착수)
  - **사양서 상태**: 통합 OTA 사양서 미작성(Draft → Approved 및 대상 경로 확정 필요) / 연관 개정 대상: `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` (현재 v1.1.0 Implemented), `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.27.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.12.1 Approved), `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (현재 v1.18.0 Implemented), `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (현재 v1.11.0 Implemented)
  - **배경 및 통합 사유**: 다중 CC:Tweaked 컴퓨터 탑재 기체(VAS, 다수 TCA, 다수 ASA, FCP, AMM)의 수동 `installer.lua` 업데이트 비용을 해소하되, `Zero-Fallback` 원칙상 체크섬 검증·`/ota_staging/` 원자적 교체 응답·안전 게이트 거부(`NACK`) 사유 코드가 서버 프로토콜에 처음부터 일체화되어야 재설계를 방지할 수 있음. 또한 비행 중 OTA 재부팅 추락 및 패킷 유실로 인한 벽돌(Brick) 장애를 막기 위해 서버와 슬레이브 부트스트랩 가드를 단일 E2E 게이트로 통합 검증함
  - **주요 작업**:
    - [ ] **TASK-117-1**: 통합 OTA 사양 및 아키텍처 동시 개정 — 격납고 예약 대역(`101 ~ 200`, `Base_hangar+4~+9`) 무선 OTA 채널(`0 ~ 100` 유선/내부 IPC 대역 배제), `/.version.json` 기반 다중 노드 주소 지정(`VAS`·`TCA`·`FCP`·`AMM`), 체크섬·원자적 교체 ACK/NACK(`NOT_DISARMED` 등) 패킷 스키마를 통합 사양서(Draft → Approved), 마스터 ICD, 전체 구조도, 인스톨러·VAS·TCA 사양서에 동시 반영
    - [ ] **TASK-117-2**: 슬레이브 OTA 에이전트 및 2단계 부트 커밋 워치독 구현 — 수신 파일을 `/ota_staging/`에 기록 후 CRC/해시 일치 시에만 본 경로로 교체하고, `pending_ota` 마커와 초기 정상 틱 커밋·예외/미커밋 재부팅 시 `/ota_backup/` 자동 복구 래퍼를 `startup.lua` 생성기에 내장 (`src/0_development/installer/modules/startup_generator.lua`)
    - [ ] **TASK-117-3**: 온보드 안전 상태 게이트 및 노드 타게팅 연동 — 기체가 `DISARMED`·지상 `IDLE_ARMED`·지상 `E_STOP`(`not isAirborne`) 등 비비행 안전 상태일 때만 OTA 수신·적용을 허용하고 비행 중에는 `NACK` 거부하는 상태 게이트 구현 (`src/1_control/{vas,tca}/`·`FCP`·`AMM` 우선 적용, `src/1_control/asa/`는 `TASK-105` 연기 해제 시 연동)
    - [ ] **TASK-117-4**: 격납고 무선 OTA 배포 서버 구축 및 매니페스트 동기화 — 격납고 마스터 컴퓨터 단일 명령으로 기체 내 슬레이브 컴퓨터 로컬 파일(`src/` 하위 패키지) 일괄 배포 및 원격 `os.reboot()` 트리거 구현 (`src/0_development/ota/` 신설 시 `manifest.lua`, `config/gdrive_mapping.json`, `verify_manifest_sync.py` 정합성 동기화 필수)
    - [ ] **TASK-117-5**: 멀티노드 OTA E2E 시뮬레이션 검증 및 사양서 승격 — 정상 일괄 배포, 비행 상태 `NACK` 거부, 체크섬 불일치 중단, 부팅 크래시 자동 `/ota_backup/` 롤백 E2E 검증 완료 후 관련 사양서 `Implemented` 승격

- [ ] **TASK-120: [개발 도구] 블랙박스 비행 기록기(FDR) 및 호스트 PC 오프라인 텔레메트리 분석기 구축** (`src/0_development/fdr/`, `tools/analyze_flight_log.py`)
  - **사양서 상태**: 미작성 (구현 착수 전 Draft → Approved 필요; `Base+1` `MSG_ATTITUDE_CMD`·`Base+2` `MSG_FLIGHT_TELEMETRY` 패시브 감청 기준, 필요 시 진단 필드 확장 검토)
  - **배경 및 필요성**: 온보드 제어기 헤드리스 전환(TASK-113)으로 실시간 20Hz 성능은 확보되었으나, 인게임 비행 중 발생하는 미세 자세 진동, 짐벌 포화(Saturation), 슬루율 제한 현상을 정밀 튜닝하기 위한 시계열 로그 수집 수단 부재
  - **주요 작업**:
    - [ ] **TASK-120-1**: 경량 블랙박스 로거(`src/0_development/fdr/`) 구현 — `Base+1`(유도 지령) 및 `Base+2`(20Hz VAS 텔레메트리) 패킷을 패시브 감청해 로컬 링 버퍼에 기록하고 `E_STOP` 또는 사용자 핫키 입력 시 JSONL 포맷으로 덤프 (`manifest.lua`·`verify_manifest_sync.py` 등록 포함)
    - [ ] **TASK-120-2**: 오프라인 텔레메트리 분석 CLI(`tools/analyze_flight_log.py`) 구현 — JSONL 덤프 파일을 읽어 목표치(Setpoint) 대비 실제 측정치(Process Variable), PID 적분항 포화도, 추력 분배율 분석·요약 출력 (`tests/harness/test_tools_integrity.py` 등록 포함)

- [ ] **TASK-122: GPS ↔ 클라이언트 프로토콜 정합화 및 런타임 보강** (`src/0_infra/gps/`, `src/0_infra/landing_pad/`, `src/2_guidance/fcp/`, `tests/e2e/test_e2e_gps_triangulation.lua`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-11-task-122-gps-client-protocol-sync.md`
  - **사양서 상태**: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (현재 v2.2.2 Implemented → 목표 v2.3.0 Approved → Implemented), `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.27.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.12.1 Approved), `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md` (현재 v2.4.2 Implemented), `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (현재 v1.16.0 Implemented)
  - **배경 및 목적**: 중앙 GPS 클러스터, GPS Client HAL, 착륙패드(`landing_pad`), FCP(`network_manager`/`nav_engine`) 간 와이어 프로토콜 불일치(`"FACILITY"`, `"FIX_OK"`/`"FIX_DEGRADED"`, `time` 헤더), `monitor_ui` 문자열 포맷 오류, `FAIL_GEOMETRY` 250ms 재시도 차단, `isManaged` 재시도 누락 및 채널 폴백(`60001`→`50206`)을 정합화하고 실노드 폐루프 E2E 시뮬레이션으로 검증
  - **주요 작업**:
    - [ ] **TASK-122-1**: GPS 사양서 개정(`v2.3.0 Approved`) 및 마스터 ICD·전체 구조도·FCP·착륙패드 사양서 GPS 참조 배지 동기화
    - [ ] **TASK-122-2**: GPS 서버·스케줄러·노드·모니터 UI·커미셔닝 수정 (`FAIL_GEOMETRY` 150ms 단기 툼스톤/HWM 비갱신, `EARLY_SOLVED` `replyChannel` 반환, `CH 60002` 상태 응답, `payload.pos`, `monitor_ui` `%-10s`, `wizard_cli.writeJsonAtomic`)
    - [ ] **TASK-122-3**: GPS Client HAL 보강 (`client_core.lua` `pendingResponses` 5000ms TTL 정리, `gps_client.lua` `isManaged` 50% 타임아웃 재시도 동등성 및 `CH 60002` 상태 조회 API)
    - [ ] **TASK-122-4**: 착륙패드 GPS 클라이언트 Zero-Fallback·설정 정규화 및 이중 주기(`1Hz`/`5Hz`/`STATIC`) 구현 (`config_store.normalize_config`, `setup_wizard`, `Base_sec+5` `50206`, `"FACILITY"`/`"FIX_OK"`/`"FIX_DEGRADED"`)
    - [ ] **TASK-122-5**: FCP GPS 엔벨로프 `time` 표준화, `targetClient`/`clientSeq` 방어, 경과시간 기반 동역학 게이트 `delta_t` 및 `altitudeY` 동기화 (`network_manager.lua`, `nav_engine.lua`)
    - [ ] **TASK-122-6**: Scenario 3 실노드 폐루프 E2E 검증(`test_e2e_gps_triangulation.lua`), GPS 사양서 `Implemented` 승격, 전계층 회귀 및 컨텍스트 문서 동기화

- [-] **TASK-202: UAFS 통합 미션 시퀀서 엔진 및 AMM 조종석 단말 구현 (구 TASK-201[AMP 초안] + 203 통합)**
  - **선행 의존성**: `TASK-202-1~4` 및 `TASK-201` 완료로 `TASK-202-5`(호스트 PC 외부 비주얼 에디터 `tools/amm_mission_editor.html`, 멀티노드 E2E 시뮬레이션·사양서 승격) 즉시 진행 가능
  - **실행 계획서**: `docs/superpowers/plans/2026-11-11-task-202-2-amm-mission-core-hooks-zone3.md`, `docs/superpowers/plans/2026-11-11-task-202-3-amm-mission-fsm-c2-headless.md`, `docs/superpowers/plans/2026-11-11-task-202-4-amm-tui-resolver-drop-cli.md`, `docs/superpowers/plans/2026-11-11-amm-webui-editor-spec-draft.md` (초안: `docs/superpowers/plans/2026-11-08-amp-mission-planner.md`)
  - **사양서 상태**: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v1.2.0 Approved), `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.27.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.12.1 Approved)
  - **배경 및 목적**: Layer 3(AMM)과 Layer 4(AMP)로 분열되었던 미션 시퀀서 및 체크포인트 평가 로직을 3분할 미션 코어(`src/3_planning/amm/modules/{mission_engine,condition_evaluator,hook_runner}.lua`)로 일원화. 온보드 AMM 51x19 MFD TUI와 결합 구동하고 동일 코어를 무인기 헤드리스(`config.headless`) 및 원격 트리거(`Base+0` `MSG_MISSION_CMD`)로 겸용 구동하며, 호스트 PC 외부 비주얼 에디터(`tools/amm_mission_editor.html`) 저작 및 외부 파일 즉시 구동 파이프라인을 통합 지원하도록 모듈화
  - [x] **TASK-202-1**: AMM 사양서(v1.2.0 Approved), 마스터 ICD(v1.27.0 Approved), 전체 구조도(v2.12.1 Approved) 통합 미션 스키마·Zone 3 인터페이스·호스트 PC 외부 비주얼 에디터(`tools/amm_mission_editor.html`) 및 외부 파일 즉시 구동(`resolve_path`, `validate_mission_table`, `file_transfer`, 부팅 인자) 규격 반영 완료 (2026-11-11)
  - [x] **TASK-202-2**: 13종 체크포인트 스키마(활성 9종 + 예약 4종), 12종 `completeWhen`/`abortWhen` 조건 평가기(`condition_evaluator.lua`) 및 0-tick 비차단 훅/디바이스 실행기(`hook_runner.lua`), `network_manager.lua` Zone 3(`Base+20~29`) 동적 채널 연동 구현 완료 (2026-11-11, `3_planning/amm` 48/48 PASS)
  - [x] **TASK-202-3**: `missions/*.json` 다형성 시퀀스 파일 로더 및 스텝 자동 전이 FSM(`mission_engine.lua`), `c2_arbiter.lua` `Base+0` `MSG_MISSION_CMD`/`ACK` 중재 및 `config.headless` 분기 구현 완료 (2026-11-11, 단위 12타겟 361/361 PASS, `3_planning/amm` 60/60 PASS)
  - [x] **TASK-202-4**: AMM 51x19 TUI 6행 스크롤 뷰포트 + 5행 조건 진행률 시각화(`ui_renderer.lua`), 다중 경로 리졸버(`resolve_path`)·프리플라이트 스키마 검증기(`validate_mission_table`), `c2_arbiter.lua` `SCHEMA_INVALID` ACK 매핑, `file_transfer` 드롭/부팅 인자 즉시 실행(`main.lua`) 및 CLI 명령어(`run/load/files/stop/next/mission`, `input_handler.lua`) 확장 구현 완료 (2026-11-12, 커밋 `fa91084`, `064a706`, `dfb3029`, `d3b3b8b`, 단위 12타겟 372/372 PASS·`3_planning/amm` 71/71 PASS, E2E 8/8 PASS, 돌연변이 25/25 KILLED)
  - [ ] **TASK-202-5**: 호스트 PC 브라우저 기반 단일 파일 비주얼 미션 에디터(`tools/amm_mission_editor.html`) 구현, AMM 단위 테스트·E2E 시뮬레이션 검증, `manifest.lua`·`verify_manifest_sync.py`·`verify_spec_status.py` 동기화 및 사양서 `Implemented` 환원 (선행 단계: WebUI 에디터 `Draft` 사양서 작성 — `docs/superpowers/plans/2026-11-11-amm-webui-editor-spec-draft.md`)

- [ ] **TASK-204: AMM의 미션 관리 시스템용 표준 행동 리스트 재정의: 진입조건 및 계층별 분류** (`docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v1.2.0 Approved), `src/3_planning/amm/modules/`)
  - **배경 및 목적**: 현행 AMM의 3도메인(항법/인프라/특수) 13종 평면적 체크포인트 분류 및 사후 조건(`completeWhen`/`abortWhen`) 중심 스키마를 재검토하여, 각 표준 행동(Action)의 **진입조건(Entry Preconditions / State Guards)**과 **계층별 분류(Hierarchical Taxonomy)**를 체계적으로 재정의하고 사양서 및 미션 엔진 검증/실행 모델에 반영

- [ ] **TASK-206: FCP 외루프 경량화 및 AMM 상위 계층 이관을 위한 15대 사양서 전면 개편** (`docs/system/*.md`, `docs/specs/**/*.md`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-11-fcp-amm-role-refactor-specs.md`
  - **사양서 상태 (변경 대상 14종 / `INSTALLER` v1.1.0 유지 → 완료 시 목표 분포 `7 Implemented, 8 Approved`)**:
    - 코어 개정(목표 `Approved`): `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.27.0 Approved → 목표 v1.28.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.12.1 Approved → 목표 v2.13.0 Approved), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v1.2.0 Approved → 목표 v1.3.0 Approved), `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (현재 v1.16.0 Implemented → 목표 v2.0.0 Approved), `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (현재 v1.18.0 Implemented → 목표 v1.19.0 Approved), `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (현재 v1.6.0 Approved → 목표 v1.7.0 Approved)
    - 연관 배지·용어·결함 정합화: `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (현재 v1.11.0 Implemented → 목표 v1.11.1 Implemented), `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (현재 v2.6.0 Implemented → 목표 v2.6.1 Implemented), `docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md` (현재 v1.10.6 Approved → 목표 v1.10.7 Approved), `docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md` (현재 v1.11.1 Approved → 목표 v1.11.2 Approved), `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md` (현재 v1.4.1 Implemented → 목표 v1.4.2 Implemented), `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md` (현재 v2.4.2 Implemented → 목표 v2.4.3 Implemented), `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` (현재 v1.0.1 Implemented → 목표 v1.0.2 Implemented), `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (현재 v2.2.2 Implemented → 목표 v2.2.3 Implemented)
  - **배경 및 결정 아키텍처 (`/grill-me` Q1~Q6 확정, Spec-First — `src/` 코드 무수정)**:
    - **계층 분리**: `AMM (Node 03)`이 미션 시퀀서·조종석/GCS C2(`Base+0`/`+3`)·외부 인프라 게이트웨이(`CH 50000~50004`, `Base_sec+*`, Tower ATC/GAC/Runway/Docking Arm/Landing Pad)·GPS/DR 항법 융합(`CH 60001~60002`, `Base+5`)·20Hz 궤적 생성(`20Hz`/`5Hz` 코루틴 분리, 이중 무선 모뎀 `top`+`back` 및 단일 모뎀 폴백)을 전담하고, `FCP (Node 04)`는 단일 `top` 모뎀 3채널(`Base+4/+2/+1`)만 사용하는 온보드 `SE(3)` 외루프 제어기($g = 11.0\text{ m/s}^2$, 6상태 FSM)로 축소함.
    - **3대 와이어 계약**: `AMM -> FCP`(`Base+4`, `[I-12]`, `MSG_TRAJECTORY_SETPOINT` `[targetPos, targetVel, feedforwardAccel, targetHeading]` + 항법/라이프사이클·제약 프로파일 / `MSG_OUTER_LOOP_STATUS`), `FCP -> VAS`(`Base+1`, `[I-2]`, `QUATERNION_RATE` `[targetQuaternion, targetAngularRates, collectiveThrust, flapTarget?, translationBias?]`), `VAS -> TCA/ASA`(`Base+10/+11`, `[I-3]/[I-10]` `MSG_THRUST_CMD` & `MSG_AERO_CMD`/`STATUS` 단일화).
    - **3계층 페일세이프 격리 및 Zero-Fallback**: `AMM`(GPS `5,000ms`·동적 착륙패드 `300ms`·ATC/연료) / `FCP`(`AMM_TIMEOUT` `500ms` → 10초 `AMM_TIMEOUT_HOLD` → `EMERGENCY_LAND`, `PASSIVE_TRACKING` + 2.0초 범프리스 복귀) / `VAS`(`FCP_TIMEOUT` `1,500ms` → 10초 `FAILSAFE_HOLD` → `EMERGENCY_LAND`, `MFD_ACRO` `Base+3` 인계 시 `AMM` 침묵) 분리. 구 필드(`ATTITUDE_ANGLE`, `targetClimbRate`, `targetThrottle`, `translationBias.heave`, `CH_NAV_SENSOR`, `MSG_SURFACE_CMD/STATUS`, `MSG_AERO_DISCOVER_*`, `AMM->FCP MSG_OPERATOR_CMD`) `[DEPRECATED]` 표기 및 기존 문서 채널·식별자 결함(`Base+6/7`, `10007`, `10045`, `BW=20`, `2000`, `system.json` `reserved04`, 구버전 유도·액추에이터 식별자, `FCP-NODE-04-4402`) 일괄 정정. 완료 시 후속 Lua 구현 태스크(`TASK-207` AMM v1.3.0, `TASK-208` FCP v2.0.0, `TASK-209` VAS v1.19.0, `TASK-210` ASA/TCA/Alignment) 등록.
  - **주요 작업**:
    - [ ] **TASK-206-1**: 마스터 ICD(`v1.28.0 Approved`) 개정 — `[I-1..I-11]` 책임 재할당, `Base+4` `[I-12]` 신설, `[I-2]` `QUATERNION_RATE` 정규화, `[I-10]` `MSG_AERO_*` 통일 및 기존 결함 정정
    - [ ] **TASK-206-2**: 전체 구조도(`v2.13.0 Approved`) 개정 — 4계층 Mermaid 구조도·6기종 흐름도·패킷 교환 매트릭스·6대 시퀀스·채널 매트릭스 갱신 및 `BW=20`/`2000`/`Base+6/7` 오류 정정
    - [ ] **TASK-206-3**: AMM 사양서(`v1.3.0 Approved`) 개정 — 이중 무선 모뎀·`20Hz`/`5Hz` 코루틴 분리·`nav_engine`/`facility_client`/`channel_sentinel`/`trajectory_generator`·`Base+4` `[I-12]` 및 1계층 페일세이프 추가 (`v1.2.0` 미션/에디터 규격 보존)
    - [ ] **TASK-206-4**: FCP 사양서(`v2.0.0 Approved`, `Implemented -> Approved`) 개정 — 단일 `top` 모뎀 3채널·`SE(3)` 외루프 수학 법칙($g=11.0\text{ m/s}^2$)·6기종 투영·6상태 FSM(`PASSIVE_TRACKING`/`AMM_TIMEOUT_HOLD`) 축소 및 외부 RF·`/etc/vac/` `[DEPRECATED]`/제거
    - [ ] **TASK-206-5**: VAS 사양서(`v1.19.0 Approved`, `Implemented -> Approved`) 개정 — `QUATERNION_RATE` 단일화·정상 비행 승강 PI 제거(`FAILSAFE_HOLD` 한정 유지)·`AMM` `[I-1]`/`Base+3` ACRO 양보·`system.json` 및 구버전 액추에이터·유도 타임아웃 잔존 결함 정정
    - [ ] **TASK-206-6**: 제어·교정 연관 사양서 개정 — ASA(`v1.7.0 Approved`, `10007`/`+7`/`bw=20` 정정), TCA(`v1.11.1 Implemented`, `AMM->FCP->VAS` 재바인딩 및 `+6` 정정), Alignment(`v2.6.1 Implemented`, `VAS-NODE-01-4402` 정정)
    - [ ] **TASK-206-7**: 지상·공역 인프라 6대 사양서 정합화 — `RUNWAY` (`v1.10.7`), `DOCKING_ARM` (`v1.11.2`), `GAC` (`v1.4.2`), `LANDING_PAD` (`v2.4.3`), `GCS` (`v1.0.2`), `GPS` (`v2.2.3`, `10045`->`10005`)의 기체 측 교신 주체를 `AMM (Node 03)`으로 일원화 (와이어 프로토콜 하위 호환 유지)
    - [ ] **TASK-206-8**: `tools/verify_spec_status.py` (`7 Implemented, 8 Approved`) 갱신, `TASK-206` 완료 아카이브·후속 구현 과제(`TASK-207~210`) 등록·`TASK-201` `R5` 인용 정비, `GEMINI.md`/`.agent/memory/workspace-root.md` 동기화 및 전수 정적·하네스 검증 통과

- [ ] **TASK-401: PAYLOAD 계층(Zone 3) 통신 스키마 정의** (`docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.27.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.12.1 Approved), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v1.2.0 Approved), `docs/specs/4_mission/`)
  - **사양서 상태**: PAYLOAD 계층 전용 사양서 미작성 (Draft → Approved 수립 및 마스터 ICD Interface I-11·전체 구조도·AMM 사양서 동기화 필요)
  - **배경 및 목적**: 현행 마스터 ICD Interface I-11(`Base+20~29`, Zone 3 탑재체 버스)에는 `MSG_PAYLOAD_REQ`/`MSG_PAYLOAD_ACK` 기본 예시 패킷만 정의되어 있으며, 전체 구조도의 세부 채널 구분(`Base+20` `CH_PAYLOAD_BUS`, `Base+21` `CH_WEAPON_BUS`, `Base+22~29` 예비) 및 다양한 탑재체 노드(화물 투하, 마그넷 래치, 엄빌리컬 급유/충전, `CC:Radars`/터렛 무장 제어 등) 간 표준 통신 계약이 미비함. 탐색/기능 등록(Discovery & Capability), 상태/헬스 텔레메트리, 명령·응답(`ACK`/`NACK`)·오류 코드, 안전 인터록 및 채널 오프셋 배분 규칙을 포함한 PAYLOAD 계층 표준 통신 스키마를 정의함

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
  - **사양서 상태**: 별도 사양서 미작성 (마스터 ICD `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` v1.27.0 Interface I-5 기반; 착수 전 사양서 Draft → Approved 또는 ICD 연계 필요)
  - 광역 공역 진입/이탈 스케줄링 및 섹터 `GAC` 핸드오프 프로토콜 구현 (일정 연기)

### 🔭 Phase 3 백로그 (Phase 3 Backlog)

- [ ] **[연기] TASK-301: 물리 하드웨어 기반 ACRO 수동 급기동 조종 인터페이스 개발**
  - Create/Avionics 아날로그 스틱 및 물리 컨트롤러 하드웨어 연동 (일정 연기)
  - `Base+1` 20Hz 직접 3축 각속도(`RATE_COMMAND`) 직결 스트림 및 비행 제어 코어(VAS) 선점 제어 연동

---

## ✅ 3. 완료된 작업 이력 (Completed Tasks Archive — 최근 10개 유지)

- [x] **TASK-201: FCP 외루프 유도 프리미티브(`LOITER` 선회 반경 제어 & `POI_HOLD` 관심점 지향) 확장** (완료일: 2026-11-11, 커밋 `d3c5fef`, `ddaf428`, `f218830`, `ecff4f4`, `fb08520`) (`docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (v1.16.0 Implemented), `src/2_guidance/fcp/`, `tests/2_guidance/fcp/`, `tests/e2e/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-11-task-201-fcp-loiter-poi-hold.md`
  - **목적 및 성과**: 상위 `AMM`(`docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (v1.2.0 Approved))의 전술 기동을 지원하기 위해 `VECTORED_VTOL` 및 `ADVANCED_VTOL` 외루프 드라이버에 `LOITER`(반경 $R \ge 5.0\text{ m}$·CW/CCW 접선 벡터, 중심 특이점 회피) 및 `POI_HOLD`(관심점 조준 3D 호버)와 3종 기수 지향 모드(`AUTO`/`FACE_PATH`, `FIXED`, `POI`/`TARGET_LOCK`/`ORBIT_POINT`, $<0.5\text{ m}$ 요 고정, $30.0^\circ/\text{s}$ 슬루, `LOITER`/`POI_HOLD` 중 `STRICT_LEVEL` $0.0^\circ$ 피치 강제)를 구현함 (`DEFERRED_AIRFRAMES` 4종 차단 및 `flapTarget == 0.0` 유지). 또한 `operator_handler.lua` `Base+0` 파라미터 정규화(`NaN`/`Inf` 차단 포함)·`PILOT_OVERRIDE_ACTIVE` 보호, `guidance_controller.lua` 2.0초 범프리스 램핑(`rampStartMs = -10000`, `FAILSAFE_HOLD` 복귀 시 짐벌 연속성 유지), `fcp_runtime.lua` 지상 대기 C2 중심점 동결·램프 방지 및 `distanceToWp` 다운링크를 통합함. 단위 330/330 PASS(12타겟, `fcp` 45/45), E2E 8/8 PASS(7시나리오), 돌연변이 25/25 KILLED(100.0%), 하네스 82/82 PASS, 정적 3종·사양서 15종(`9 Implemented, 6 Approved`)·Lua 126/126 PASS 달성.
  - **구현 내용**:
    - [x] **TASK-201-1**: FCP 사양서(v1.16.0 Approved → Implemented) 개정 및 마스터 ICD(`docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (v1.27.0 Approved))·전체 구조도(`docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (v2.12.1 Approved))·AMM 사양서 FCP 참조 배지 동기화 (`d3c5fef`)
    - [x] **TASK-201-2**: `flight_fsm.lua` `POI_HOLD` 16상태 확장(`MUT-14` 보존), `vectored_vtol_driver.lua`·`advanced_vtol_driver.lua` `resolve_horizontal_error`/`compute_heading` 및 `fcp_config.json` 기본값 구현 (`ddaf428`)
    - [x] **TASK-201-3**: `operator_handler.lua` `MSG_OPERATOR_CMD` 정규화·권한 보호, `guidance_controller.lua` `trigger_bumpless_transition`, `fcp_runtime.lua` C2 배선 및 `distanceToWp` 구현 (`f218830`)
    - [x] **TASK-201-4**: E2E 시나리오 2(`test_e2e_waypoint_guidance.lua` Step 9) 검증(`ecff4f4`), 리뷰 보완 패치(`NaN`/`Inf` 방어·`FAILSAFE_HOLD` 연속성·지상 C2 가드·고도 앵커링, `fb08520`), FCP 사양서 `Implemented` 승격 및 컨텍스트 동기화

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
