# Create_Aeroneutics — Task Management & Roadmap (`TASK.md`)

> **문서 상태**: 활성 (Living Roadmap)  
> **최종 갱신일**: 2026-11-08  
> **현재 단계**: **Phase 1 & 2 (진행 중)** (TASK-107 GCS 지상 관제 콘솔 및 40채널 블록 관리자 구현 완료, 차기 과제: TASK-111 E2E 통합 시뮬레이션 / TASK-301 ACRO 수동 조종)

---

## 📌 에이전트 작업 지침 (Agent Protocol)

- **계획 수립 시**: 작업 계획(`/plan` 등)이 확정되면 본 파일의 당면 과제 또는 백로그에 신규 항목(`[ ]`)을 등록한다.
- **작업 착수 시**: 진행 중인 태스크를 `[-]` (진행 중)으로 전환한다.
- **작업 완료 시**: 완료 항목을 `[x]` (완료)로 변경해 `## 3. 완료된 작업 이력` 상단으로 이동·기록하고, 도출된 후속 과제를 즉시 본 파일에 등록한다.
- **완료 이력 보존 상한**: 완료된 작업 이력은 **최근 30개까지만 유지**하며, 30개를 초과하는 과거 완료 항목은 오래된 순서대로 정리(Prune)한다.
- **도메인 경로 매핑 기준**: `docs/specs/`, `src/`, `tests/` 간 1:1 도메인 계층 구조는 [README.md](README.md)의 디렉토리 레이아웃을 따른다.
- **유저 호출 예시**:
  - `TASK.md 확인하고 다음 남은 작업 진행해줘`
  - `TASK.md의 TASK-200 작업 진행해줘`
  - `TASK.md 상태 점검해줘`

---

## 🚀 1. 활성 당면 과제 (Active Immediate Tasks — Phase 1 & 2)

- [ ] **TASK-111: 멀티노드 종단간(E2E) 패킷 시퀀스 통합 시뮬레이션 테스트 구축**
  - 복수 노드(`GCS`↔`AMM`↔`FCP`↔`VAS`↔`TCA`/`ASA`, `FCP`↔`GPS` 10Hz 주기적 절대좌표 측위/융합, `Alignment` 교정 세션, GCS C2 오버라이드 및 E-STOP 차단 등) 간 다중 틱 교환 시나리오 통합 검증 확장

---

## 📋 2. 예정 백로그 (Planned Backlog — Phase 1 & 2)

### ⏸️ 연기·보류 과제 (Deferred / On-Hold)

- [ ] **[연기] TASK-103: Runway 활주로 제어기 구현** (`src/0_infra/runway/`)
  - 활주로 유도등, 가상 ILS 및 유도로 `GAC` 연동 관제 (일정 연기 — 사양서 `Approved` 유지)
- [ ] **[연기] TASK-104: Docking Arm 결합 암 제어기 구현** (`src/0_infra/docking_arm/`)
  - 2축 로봇 암 포획·인입 및 엄빌리컬 보급 시퀀스 (일정 연기 — 사양서 `Approved` 유지)
- [ ] **[연기] TASK-105: ASA (Aerodynamic Surface Adapter) 공력 조종면·플랩 분산 구동기 본 구현 완성** (`src/1_control/asa/`)
  - TASK-113의 기본 프레임워크(헤드리스/비동기 TUI, `Base+11` 수신 루프, 300ms Safe Glide Trim, 단위 테스트 15/15 PASS)를 기반으로 물리 액추에이터(Avionics API/RS) 각도 인가, `MSG_AERO_STATUS` 상태 피드백 송출 및 `MSG_SURFACE_DISCOVER_REQ/ACK` 핸드셰이크 완성 (일정 연기 — 사양서 `Approved` 유지)
- [ ] **[연기] TASK-108: Tower ATC (Sector 0, `CH 50001/50002`) 광역 항공교통 관제 노드 구현**
  - 광역 공역 진입/이탈 스케줄링 및 섹터 `GAC` 핸드오프 프로토콜 구현 (일정 연기)
- [ ] **[연기] TASK-202: 편대 미션 오케스트레이터 (`src/4_mission/`) 설계 및 구현**
  - Zone 4(`Base+30~39`) 기반 다중 기체 편대 비행 및 임무 분배 총괄 (일정 연기)

### 🛠️ Phase 3 예정 백로그 (Physical Hardware & Manual Control)

- [ ] **TASK-301: 물리 하드웨어 기반 ACRO 수동 급기동 조종 인터페이스 개발 (Phase 3)**
  - Create/Avionics 아날로그 스틱 및 물리 컨트롤러 하드웨어 연동
  - `Base+1` 20Hz 직접 3축 각속도(`RATE_COMMAND`) 직결 스트림 및 비행 제어 코어(VAS) 선점 제어 연동

---

## ✅ 3. 완료된 작업 이력 (Completed Tasks Archive — 최근 30개 유지)

- [x] **TASK-107: GCS 채널 관리자(`CH 50000`) 및 지상 비행 지휘 콘솔 구현** (완료일: 2026-11-08, 커밋 `e9febe6` ~ `e8c25b3`) (`docs/specs/0_infra/gcs/`, `src/0_infra/gcs/`, `tests/0_infra/gcs/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-107-gcs-channel-manager-console.md`
  - **목적 및 성과**: UAFS 항공 생태계 중앙 지상 관제 인프라로서 40채널 블록($N = 1 \sim 1000$, $Base = 10000 + (N-1)\times 40$) 스티키 영속화 관리자(`CH 50000`), 원격 비행 C2 오버라이드(`Base+0`, `GCS_OVERRIDE`), 직결 하드 `E_STOP` 비상차단기(`Base+1`), 실시간 텔레메트리(`Base+3`) 캐시, 51x19 무깜빡임(`term.blit`) 분할 TUI 콘솔 및 메인 데몬 루프 구현 완료. 단위 및 E2E 폐루프 통합 테스트 25/25 PASS (전체 12개 타겟 241/241 PASS), 통합 인스톨러(`manifest.lua`) `gcs` 패키지 등록, 사양서(`GCS_PROGRAM_SPECIFICATION_AND_ICD.md` v1.0.0) `Implemented` 승격 및 정적 무결성(14 SPECS 100% CLEAN, 9 Implemented, 5 Approved) 달성.
  - **구현 내용**:
    - [x] **TASK-107-1**: GCS 규격서(`GCS_PROGRAM_SPECIFICATION_AND_ICD.md` v1.0.0) 제정, 설정/레지스트리 스캐폴딩(`gcs_config.json`, `channel_registry.json`) 구성 및 정적 검사기 등록
    - [x] **TASK-107-2**: 40채널 블록 스티키 영속화 관리자(`channel_manager.lua`, 4/4 PASS) 구현 (`compute_base`, `is_valid_base`, `allocate_block`, `release_block`)
    - [x] **TASK-107-3**: 무선 통신 관리자(`network_manager.lua`, 5/5 PASS) 구현 (UAFS Envelope v1.9.5, CH 50000, `Base+0/1/3` 동적 개폐 라우팅)
    - [x] **TASK-107-4**: 원격 비행 C2 명령 생성기(`c2_commander.lua`, 4/4 PASS) 및 하드 비상차단(`E_STOP`) 패킷 생성기 구현
    - [x] **TASK-107-5**: 다중 기체 텔레메트리 캐시 및 활성 기체 추적기(`fleet_tracker.lua`, 5/5 PASS) 구현 (원형 순환 선택, 5초 타임아웃 플래그)
    - [x] **TASK-107-6**: 51x19 분할 TUI 콘솔 화면 렌더러(`ui_renderer.lua`, 3/3 PASS) 구현 (`term.blit` 무깜빡임 가상 버퍼)
    - [x] **TASK-107-7**: 메인 데몬 루프(`main.lua`, 3/3 PASS) 및 통합 인스톨러(`manifest.lua`, 28/28 PASS) `gcs` 패키지 등록
    - [x] **TASK-107-8**: 종단간(E2E) 시뮬레이션 통합 테스트(`test_gcs_integration.lua`, 1/1 PASS), 사양서 `Implemented` 승격 및 마일스톤 완료 동기화

- [x] **TASK-110: FCP VTOL 제어 고도화** (완료일: 2026-11-08, 커밋 `21f4e76` ~ `e6b22c8`) (`docs/specs/2_guidance/fcp/`, `src/2_guidance/fcp/`, `tests/2_guidance/fcp/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-110-fcp-vtol-refinement.md`
  - **목적 및 성과**: VECTORED_VTOL 기종의 외루프 유도 제어기를 3축(Surge/Sway/Heave) 완전 PID + Anti-windup, CRUISE 모드 한정 15m/s TILT_ASSISTED 피치 슬루율(최대 15°/s) 완화, 수평 고정 수직 이륙 및 착륙 패드 정렬 2단계 감속 수직 착륙 시퀀스로 전면 고도화. 단위 테스트 슈트 보강(FCP 17/17 PASS, 전체 11개 타겟 216/216 PASS), 사양서(`FCP_PROGRAM_SPECIFICATION.md` v1.13.0) `Implemented` 환원 및 정적 무결성(13 SPECS 100% CLEAN) 달성.
  - **구현 내용**:
    - [x] **TASK-110-1**: FCP 사양서(`FCP_PROGRAM_SPECIFICATION.md` v1.13.0) VTOL 외루프 3축 PID/슬루율/이착륙 규격 개정 및 `fcp_config.json` 스키마 확장
    - [x] **TASK-110-2**: `vectored_vtol_driver.lua` 3축 Surge/Sway/Heave PID 및 Anti-windup 클램프(`maxI = 0.20`), `reset_integrals` 구현
    - [x] **TASK-110-3**: TILT_ASSISTED 모드 천이 피치 슬루율(15°/s) 완화 및 CRUISE 외 전 상태 STRICT_LEVEL($0.0^\circ$) 강제 인터록 구현
    - [x] **TASK-110-4**: 수평 이동 차단 수직 이륙 및 착륙 패드 정렬 2단계 감속 수직 착륙 시퀀스 구현 및 회귀 검증 통과

- [x] **TASK-113: 온보드 제어기(VAS, TCA, ASA) 헤드리스 기본 구동 및 `parallel` 비동기 디버그 TUI 분리** (완료일: 2026-11-08, 커밋 `b5ee552` ~ `b2c5d5a`) (`docs/specs/1_control/`, `src/1_control/`, `tests/1_control/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-113-headless-parallel-debug-tui.md`
  - **목적 및 성과**: 터미널 렌더링 부하를 제거하여 실시간 20Hz 제어 루프를 보장하고, `debug: true` 설정 시에만 ComputerCraft `parallel` API 기반 비동기 디버그 TUI를 안전하게 구동하는 구조 개편 완료. 단위 테스트 슈트 보강(VAS 23/23, TCA 19/19, ASA 15/15 PASS), 사양서(`VAS_PROGRAM_SPECIFICATION.md` v1.16.0, `TCA_PROGRAM_SPECIFICATION.md` v1.10.0) `Implemented` 환원 및 정적 무결성(13 SPECS 100% CLEAN) 달성.
  - **구현 내용**:
    - [x] **TASK-113-1**: VAS/TCA/ASA 사양서(`VAS_PROGRAM_SPECIFICATION.md`, `TCA_...`, `ASA_...`) 헤드리스/디버그 TUI 동작 규격 개정 (`Approved` 전이)
    - [x] **TASK-113-2**: `config.json` 로더에 `debug` 플래그 스키마 추가 및 기본값(`debug: true` 개발 기본값) 설정
    - [x] **TASK-113-3**: VAS(`src/1_control/vas/`) 메인 루프 헤드리스 전환 및 `parallel` 기반 비동기 `ui_renderer` 분리
    - [x] **TASK-113-4**: TCA(`src/1_control/tca/`) 및 ASA(`src/1_control/asa/`) 메인 루프 헤드리스 전환 및 비동기 디버그 뷰 분리
    - [x] **TASK-113-5**: 단위 테스트 슈트 보강(헤드리스/디버그 TUI 격리 동작 검증) 및 사양서 `Implemented` 환원

- [x] **TASK-200: AMM (Aircraft Mission Manager & Cockpit MFD 통합 단말) 구현** (완료일: 2026-11-08, 커밋 `3b2907a`) (`docs/specs/3_planning/amm/`, `src/3_planning/amm/`, `tests/3_planning/amm/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-amm-mission-manager.md`
  - TASK-106(Cockpit MFD)을 완전 병합하여 51x19 분할 TUI(5Hz 계기판 HUD + 미션 큐 및 C2 관리), 단방향 순차 웨이포인트 큐, JSON 영속화, GCS C2 무반향 감청, 원터치 핫키 및 CLI 대화형 인터페이스 일체화 단말 구현 완료. 사양서 v1.0.0 `Implemented` 승격, 단위/통합 테스트(29/29 PASS) 및 통합 인스톨러(`manifest.lua`) 등록 완료.
  - **구현 내용**:
    - [x] **TASK-200-1**: AMM 상세 규격서(`AMM_PROGRAM_SPECIFICATION.md`) 작성 및 Revision History 반영 (`Implemented` 승격)
    - [x] **TASK-200-2**: AMM 상세 구현 계획서(`2026-11-08-amm-mission-manager.md`) 수립 (8대 Task)
    - [x] **TASK-200-3**: 사양서 `Approved` 승격, 스캐폴딩 및 설정 모듈(`amm_config.json`, `test_harness_setup.lua`, 1/1 PASS) 구축
    - [x] **TASK-200-4**: 웨이포인트 FIFO 큐, 2D 도달 거리 판정($d_{2D} \le 15\text{m}$) 및 JSON 영속화 모듈(`waypoint_queue.lua`, `test_waypoint_queue.lua`, 7/7 PASS) 구현
    - [x] **TASK-200-5**: ICD v1.9.5 엔벨로프 통신 관리자(`network_manager.lua`, `test_network_manager.lua`, 4/4 PASS) 구현 (`Base+0` C2, `Base+1` E-STOP, `Base+3` HUD)
    - [x] **TASK-200-6**: C2 조종 권한 중재자 및 4대 큐 FSM(`c2_arbiter.lua`, `test_c2_arbiter.lua`, 5/5 PASS) 구현 (GCS 무반향 감청, 이륙-순항 핸드오버, 완주 후 LANDING/LOITER 분기)
    - [x] **TASK-200-7**: 모달(NAV/CLI) 입력 처리기(`input_handler.lua`, `test_input_handler.lua`, 6/6 PASS) 구현 (`[X]` E-STOP, `[H]` HOLD, `[R]` RTH 등 핫키 및 CLI 커맨드라인)
    - [x] **TASK-200-8**: 51x19 분할 TUI 렌더러(`ui_renderer.lua`, `test_ui_renderer.lua`, 3/3 PASS) 구현 (`term.blit` 0-깜빡임 버퍼 출력)
    - [x] **TASK-200-9**: 메인 데몬 루프(`main.lua`) 및 비동기 타이머 연동(`test_main_loop.lua`, 2/2 PASS) 구현
    - [x] **TASK-200-10**: E2E 폐루프 통합 시뮬레이션(`test_amm_integration.lua`, 1/1 PASS), 통합 인스톨러(`manifest.lua`) 등록 및 전체 회귀 검증 통과

- [x] **TASK-112: VAS 센서 파이프라인의 CC:Avionics 표준 API(`avionics_sensors`) 동기화 및 3축 속도/고도 정합화** (완료일: 2026-11-08, 커밋 `1ee16b2` ~ `95f68f5`) (`docs/specs/1_control/vas/`, `src/1_control/vas/modules/sensor_pipeline.lua`, `tests/1_control/vas/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-112-vas-sensor-pipeline-avionics.md`
  - VAS 내루프 실시간 동역학 제어용 센서 파이프라인을 전역 표준 라이브러리(`/lib/avionics_sensors.lua`)와 동기화하고, CC:Avionics 공식 API(`getHeight()`, 1축 스칼라 `getVelocity()` 3축 합성, 짐벌 오일러/각속도/중력/가속도) 정합성 확보
  - **구현 내용**:
    - [x] **TASK-112-1**: VAS 규격서(`docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` v1.15.0) Section 2·3에 `/lib/avionics_sensors.lua` 연동 표준 명세 반영 및 Revision History 갱신
    - [x] **TASK-112-2**: `src/1_control/vas/modules/sensor_pipeline.lua` 내 레거시 페리페럴 탐색/폴링 로직을 `require("avionics_sensors")` 기반 4종 센서(`gimbal`, `altitude`, `velocity`, `fuel`) 고속 획득 파이프라인으로 리팩토링
    - [x] **TASK-112-3**: `velocity_sensor` 3축 분산 배치(전/상/측) 자동 합성 및 `altitude_sensor`의 `getHeight()` 공식 메서드 적용, 3D 레버암 기하 동역학 보정과 결합 검증
    - [x] **TASK-112-4**: `tests/1_control/vas/test_vas_core.lua`의 센서 모킹 및 단위 테스트를 `test_sdk.lua` 최신 CC:Avionics 4종 Mock으로 전면 정합화 및 12/12 PASS 검증

- [x] **TASK-102: Landing Pad 지상 착륙 패드 제어기 구현** (완료일: 2026-11-08, 커밋 `47b98bb` ~ `c064823`) (`docs/specs/0_infra/landing_pad/`, `src/0_infra/landing_pad/`, `tests/0_infra/landing_pad/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-102-landing-pad-controller.md`
  - Landing Pad 사양서 v2.4.0 Implemented 승격, 설정 영속화(`config_store.lua`), 마인크래프트 좌표계 3D 바디 오프셋 변환(`offset_transform.lua`), CC:Avionics 센서 어댑터 및 갑판 요동 판정(`sensor_adapter.lua`), GPS 클라이언트 및 20Hz 추측항법 적분기(`gps_client.lua`), 전술 유도 스트리머(`tactical_streamer.lua`), 패드 FSM 및 로컬 백본 중재(`pad_fsm.lua`), 5단계 셋업 마법사(`setup_wizard.lua`), 51x19 TUI 뷰(`tui_view.lua`), 20Hz 메인 데몬 루프(`main.lua`), 단위 테스트(32/32 PASS) 및 통합 인스톨러(`manifest.lua`) 등록 완료
  - **구현 내용**:
    - [x] **TASK-102-1**: 5단계 대화형 TUI 셋업 마법사(`setup_wizard.lua`), 3초 부팅 카운트다운 FSM, 컴퓨터 바디 기준 오프셋(`bodyOffset`) 및 선체 장착 방위(`mountingYawOffset`) 3D 변환(`offset_transform.lua`), 자체 GPS(`CH 60001`/`Base_sec+5`) 연동, 원자적 설정 직렬화(`/landing_pad/config.json`) 구현
    - [x] **TASK-102-2**: 동적 패드 필수 3종 센서(`gimbal_sensor`, `altitude_sensor`, `velocity_sensor`) 바인딩, TUI 결손 차단(`HALT_WITH_WARNING`), 런타임 결손 격리(`MAINTENANCE`), 1초(1Hz) 백그라운드 자동 재연결(`Auto-Reconnect`) 및 FSM 상태 머신 구현
    - [x] **TASK-102-3**: GAC 로컬 백본망(`Base_sec+1`) 패킷 수수(`MSG_ATC_SLOT_ASSIGN/ACK`), 평시 1Hz 위치/상태 동기화(`MSG_ATC_FACILITY_UPDATE`), 복행 및 슬롯 예약/점유 해제 프로토콜 연동
    - [x] **TASK-102-4**: 전술 유도 채널(`Base_sec+10+Idx`) 스트리밍 (정적 1Hz 하트비트 / 동적 5Hz 비동기 GPS + 20Hz 속도 적분 융합 20Hz 전술 유도 `MSG_FACILITY_DYNAMIC_GUIDE` 및 갑판 요동 `deckStatus` 판정 알고리즘) 구현
    - [x] **TASK-102-5**: 컴팩트 1줄 순환 로깅 데몬 모드, 독립 완결형 메인 루프(`main.lua`) 및 센서 결손 복행(`reason: SENSOR_FAULT`) / 300ms 패킷 두절 / 120초 슬롯 타임아웃 / `DANGEROUS` 지속 시 `GO_AROUND` 안전 인터록 구현
    - [x] **TASK-102-6**: CraftOS-PC 단위 테스트 슈트(`tests/0_infra/landing_pad/`, 32/32 PASS) 구축 및 통합 인스톨러(`src/0_development/installer/modules/manifest.lua`) 등록

- [x] **TASK-101: GAC (Ground Area Controller) 지상 구역 관제사 사양서 개편 및 제어기/TUI 구현** (완료일: 2026-11-08, 커밋 `0787649` ~ `e5aa176`) (`docs/specs/0_infra/gac/`, `src/0_infra/gac/`, `tests/0_infra/gac/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-101-gac-ground-apron-controller.md`
  - GAC 사양서 v1.3.0 Implemented 승격, 설정 영속화(`config_loader.lua`), 관할 패드 인벤토리(`facility_inventory.lua`), 2단계 다속성 최적 분배(`allocation_engine.lua`), 1Hz 섹터 대표 비콘/디스패치(`beacon_broadcaster.lua`), 섹터 FSM 및 핸드오프/국지 복행 중재(`gac_fsm.lua`), 듀얼 디스플레이 3-Tab TUI 콘솔(`tui_view.lua`), 20Hz 비차단 메인 루프(`main.lua`), 단위 테스트(27/27 PASS) 및 통합 인스톨러(`manifest.lua`) 등록 완료
  - **구현 내용**:
    - [x] **TASK-101-1**: GAC 사양서(`GAC_PROGRAM_SPECIFICATION_AND_ICD.md` v1.3.0) 세부 내용 개편 (FCP 치환, 패킷 스키마 동기화, Section 6 TUI 콘솔 및 수동 조작 규격 신설, 사양서 Implemented 승격)
    - [x] **TASK-101-2**: GAC 제어기 설정 로더 및 원자적 영속화 엔진(`config_loader.lua`) 구현 (4/4 PASS)
    - [x] **TASK-101-3**: 관할 패드 인벤토리 및 공간 색인(`facility_inventory.lua`), 동적 원격 계측 수신 및 비상 동결 FSM 구현 (5/5 PASS)
    - [x] **TASK-101-4**: 1Hz 섹터 대표 집약 비콘(`CH 50003` / `Base_sec+2`) 및 관제 디스패치(`CH 50004`) 송출기(`beacon_broadcaster.lua`) 구현 (3/3 PASS)
    - [x] **TASK-101-5**: 2단계 다속성(하드 제약 + 맞바람/거리/하중 가중치) 최적 패드 분배 엔진(`allocation_engine.lua`) 구현 (5/5 PASS)
    - [x] **TASK-101-6**: 섹터 체크인/진입(`Base_sec+0`), 국지 복행(Go-Around) 격리/대체 패드 재배정, 이륙 인가 및 Tower ATC(`CH 50002`) 핸드오프(`gac_fsm.lua`) 구현 (4/4 PASS)
    - [x] **TASK-101-7**: 듀얼 디스플레이(51x19 터미널 + 외장 모니터) 3-Tab TUI 관제 콘솔(`tui_view.lua`) 및 수동 조작(`[M]`, `[F]`, `[W]`, `[E]`, `[A]`, `[D]`) 인터페이스 구현 (4/4 PASS)
    - [x] **TASK-101-8**: 20Hz 비차단 메인 루프(`main.lua`), CraftOS-PC 단위 테스트 슈트(`tests/0_infra/gac/`, 27/27 PASS), 통합 인스톨러(`manifest.lua`) 등록 및 전체 회귀(112/112 PASS, 24/24 PASS) 통과

- [x] **TASK-109: ASA 관할 범위 축소 (VECTORED_VTOL, 드론 기체 배제 및 FCP/VAS 비활성화)** (완료일: 2026-11-08) (`docs/specs/`, `src/1_control/vas/`, `src/2_guidance/fcp/`, `tests/`)
  - VECTORED_VTOL 및 드론(QUADROTOR, HEXAROTOR) 기체에서 ASA 동작 배제, FCP 외루프 flapTarget 지령 차단(0.0 고정), VAS 내루프 ASA 타면 할당 및 Base+11 MSG_AERO_CMD 송출 비활성화, 텔레메트리 WAP 바이패스 구현
  - **구현 내용**:
    - [x] **TASK-109-1**: 활성 사양서 5종(`ASA_PROGRAM_SPECIFICATION.md` v1.4.0, `VAS_PROGRAM_SPECIFICATION.md` v1.14.0, `FCP_PROGRAM_SPECIFICATION.md` v1.12.0, `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` v1.23.0, `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` v2.10.0) 개정 및 기체 적용 범위/제외 원칙 동기화
    - [x] **TASK-109-2**: `src/2_guidance/fcp/modules/guidance_controller.lua`에서 비공력 기체 대상 `flapTarget = 0.0` 고정 및 단위 테스트(`tests/2_guidance/fcp/`, 11/11 PASS) 검증
    - [x] **TASK-109-3**: `src/1_control/vas/modules/vehicle_policy.lua` 및 `core_daemon.lua`에서 비공력 기체 대상 조종면 할당 생략, `MSG_AERO_CMD` 미송출, TCA 단독 포화 평가 및 텔레메트리 헬스 바이패스 구현 및 단위 테스트(`tests/1_control/vas/`, 10/10 PASS) 검증
    - [x] **TASK-109-4**: 전체 사양서 무결성(`verify_all_specs.py`, `verify_spec_status.py`), Lua 5.2 문법(`validate_lua_syntax.py`, 91/91 PASS), 하네스 회귀(24/24 PASS) 전수 통과 확인

- [x] **TASK-100: CC:Avionics 4종 센서 API 표준 라이브러리(`avionics_sensors`) 구축 및 공용 배포·하네스 연동** (완료일: 2026-11-08, 커밋 `6164848`, `93e959b`) (`src/0_development/sensors/`, `tests/0_development/sensors/`)
  - `velocity_sensor`, `altitude_sensor`, `gimbal_sensor`, `physics_assembler` 4종 전용 표준 함수 모음 단일 원본(SSOT) 구축 및 통합 인스톨러(`manifest.lua`)·단위 테스트 하네스(`engine.py`) `/lib/` 자동 스테이징 연동
  - **구현 내용**:
    - [x] **TASK-100-1**: 단위 테스트 하네스(`harness/unit/engine.py`) 공용 `/lib/` 자동 스테이징 및 `test_sdk.lua` 정밀 CC:Avionics 4종 Mock 추가
    - [x] **TASK-100-2**: `src/0_development/sensors/avionics_sensors.lua` 4종 센서 표준 탐색·단건/3축/병렬(`mainThread`) 계측 함수 및 단위 테스트 슈트(`tests/0_development/sensors/`, 9/9 PASS) 구현
    - [x] **TASK-100-3**: 통합 인스톨러(`manifest.lua`, `startup_generator.lua`) `/lib/avionics_sensors.lua` 번들 배포·경로 주입 및 전체 회귀 검증(85/85 PASS)

- [x] **TASK-006: 검증 스크립트 정식 도구화(`scratch/` → `tools/`) 및 하위 문서 구 경로 정리** (완료일: 2026-11-08, 커밋 `8ab621e`, `44ef922`, `c4c4a6e`, `1d3b658`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-006-tooling-and-spec-links-cleanup.md`
  - **구현 내용**:
    - [x] **TASK-006-1**: `verify_all_specs.py`·`validate_lua_syntax.py`·`verify_spec_status.py`의 `tools/` 이관, 동적 DLL 탐색 및 90개 Lua 전수 검사 지원, 일회성 `scratch/` 스크립트 정리 및 전용 `scratch/README.md` 구축
    - [x] **TASK-006-2**: `src/1_control/asa/README.md` 및 `src/0_infra/gac/README.md` 내 폐기된 `docs/specs/approved/...` 링크 제거, 영구 단일 경로 동기화 및 `tools/verify_all_specs.py --check-readmes` 0 error 통과
    - [x] **TASK-006-1B**: 도구 무결성 자동화 테스트(`tests/harness/test_tools_integrity.py`, 5/5 PASS) 작성, 전체 하네스 회귀(23/23 PASS) 및 루트 문서(`README.md`, `GEMINI.md`, `TASK.md`) 동기화

- [x] **TASK-005: 통합 코드베이스 설치 프로그램(Unified Installer) 구축 및 구버전 통폐합** (완료일: 2026-11-08, 커밋 `adfc561` ~ `01d938d`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-005-unified-codebase-installer.md`
  - **구현 내용**:
    - [x] **TASK-005-0**: GPS 사양서(`GPS_PROGRAM_SPECIFICATION_AND_ICD.md`) 개정(`v2.2.0`, `Implemented` → `Approved`, 구 인스톨러 `[DEPRECATED]` 명시)
    - [x] **TASK-005-1**: 선언적 매니페스트(`manifest.lua`, 듀얼 원천) 및 버전 레지스트리(`version_registry.lua`) 구축
    - [x] **TASK-005-2**: 설정 보존 마이그레이션(`migration_engine.lua`) 및 본체 루트 멀티부트 후크(`startup_generator.lua`) 구축
    - [x] **TASK-005-3**: HTTP 원자적 다운로더(`downloader.lua`, GitHub & Google Drive 302 리다이렉트 지원) 구축
    - [x] **TASK-005-4**: 터미널 TUI(`tui_view.lua`, 소스 전환 `[S]`) 및 메인 앱(`installer_app.lua`) 구축
    - [x] **TASK-005-5**: 3대 배포(화면 직접 업로드·플로피 `/disk/`·원격 `wget run`) 지원 루트 부트스트래퍼(`installer.lua`) 및 byte-parity 검증
    - [x] **TASK-005-6**: 구버전 개별 인스톨러(`gps/installer.lua`, `installer_core.lua`) Zero-Fallback 삭제
    - [x] **TASK-005-7**: 단위 테스트 하네스 전수 실행(`tools/run_unit_tests.py` 7개 타겟 71/71 PASS, 하네스 자체 회귀 18/18 PASS, Lua 5.2 문법 7/7 PASS)
    - [x] **TASK-005-8**: GPS 사양서 메타데이터 `문서 상태`를 `Implemented`로 환원 및 전역 검증(`verify_all_specs.py`, `verify_spec_status.py` 5 Implemented, 7 Approved)

- [x] **TASK-004: 원격 저장소(`origin main`) 푸시 및 인증 완료** (완료일: 2026-11-08)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-004-remote-repository-push.md`
  - GitHub `Aeroneutics_Autopilot` 저장소 확인, Fine-grained PAT Contents Write 권한 갱신 및 원격 초기 커밋 조정(`1ca730b` merge) 후 `git push -u origin main` 완료, 로컬 HEAD와 원격 ref 일치 검증 통과 (커밋 `197172f`)
- [x] **TASK-003: 런타임 코드 검증 및 사양서 상태 전이 (`Approved` → `Implemented`)** (완료일: 2026-11-08)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-003-spec-status-transition-to-implemented.md`
  - 5대 핵심 사양서(`VAS`, `TCA`, `FCP`, `Alignment`, `GPS`) `Implemented` 전이 완료 및 `verify_spec_status.py` 12종 전수 검증 통과 (5종 `Implemented`, 7종 `Approved`), 단위 테스트 `42/42 PASS`, 하네스 회귀 `14/14 PASS` (커밋 `dd096e1`, `6daa12d`, `dea477e`)
- [x] **TASK-002: 코드베이스 40채널·Zone 단위 테스트 및 하네스 루프 통합 검증** (완료일: 2026-11-08)
  - 6개 활성 타겟(`alignment` 7, `gps` 9, `asa` 3, `tca` 7, `vas` 7, `fcp` 9) 전수 `42/42 PASS` 및 하네스 Python 회귀 테스트 `14/14 PASS`로 통합 종결 (멀티노드 E2E 시나리오는 `TASK-111`로 분리)
- [x] **TASK-001: 기체 5대 핵심 모듈(`src/`) 통신 채널·Zone 런타임 코드 동기화** (완료일: 2026-11-08)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-07-task-001-runtime-40ch-sync.md`
  - $BW=40$ ($Base = 10000 + (N-1) \times 40$) 및 4대 Zone 규격을 `VAS`(`16b8390`, `1db52ed`), `TCA`(`e6be320`, `0f29c5b`), `FCP`(`9da4301`, `34fc867`, `4c1db74`), `Alignment`(`f52cb11`, `c5e8b5a`), `GPS`(`8da2d09`)에 반영 완료 (단위 테스트 `42/42 PASS`, 문법 정적 분석 `7/7 PASS`)
- [x] **TASK-P0-06: SAS → FCP(Flight Control Program) 전면 명칭 개정 및 디렉토리·식별자 일체화** (완료일: 2026-11-07)
  - 디렉토리/파일명(`docs/specs/2_guidance/fcp/`, `src/2_guidance/fcp/`, `tests/2_guidance/fcp/`) 및 런타임 식별자(`source`/`activeSource`='FCP', `hardwareUuid`='FCP-04'), 사양서 12종 및 마스터 ICD 동기화, 단위 테스트 6/6 PASS
- [x] **TASK-P0-05: CC:Tweaked 하네스 및 단위 테스트 검증 파이프라인 구축** (완료일: 2026-11-07)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-07-universal-unit-test-framework.md`
  - Lua 5.2 문법/금지 모드 정적 분석기(`scratch/validate_lua_syntax.py`), CraftOS-PC 헤드리스 세션·Mock 프레임워크(`harness/unit/`), 멀티 타겟 테스트 러너 CLI(`tools/run_unit_tests.py`) 및 6대 코드베이스 초기 테스트 슈트 구축
- [x] **TASK-P0-04: 사양서 생명주기 관리 체계 문서 내부화 및 영구 단일 계층 개편** (완료일: 2026-11-07)
  - `docs/specs/{approved,drafts,implemented,archived}/` 디렉토리 분리 제거 및 도메인 직하 단일 계층 평탄화, 12대 규격서 상단 5대 필수 항목 메타데이터 표 도입, `specification-lifecycle-manager`·`skill-workflows.md`·`verify_all_specs.py` 동기화
- [x] **TASK-P0-03: 사양서 정합성 무결성 검증기 통과** (완료일: 2026-11-07)
  - `scratch/verify_all_specs.py` 전수 검증 (0 Errors, 0 Warnings)
- [x] **TASK-P0-02: 12대 핵심 사양서 전수 리팩토링 및 10종 승격** (완료일: 2026-11-07)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-07-system-specifications-refactoring.md`
  - 40채널 대역폭, Zero-Fallback 원칙, `ion_thruster` 호환성, 상대 링크 정합성 반영
- [x] **TASK-P0-01: 기체 통신 40채널($BW=40$) ICD 전면 개편** (완료일: 2026-11-07)
  - `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` 및 `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` 4대 Zone 규격 반영
