# Create_Aeroneutics — Task Management & Implementation Roadmap

> **문서 상태**: 활성 (Living Roadmap)  
> **최종 갱신일**: 2026-11-08  
> **현재 단계**: **Phase 1 & 2** (TASK-007 구버전 명칭 전면 척결 완료, 활성: TASK-114 GAC 전용 시설물 런타임 구현 / TASK-010 플레이북 체계 구축 / TASK-115 ADVANCED_VTOL 아키텍처)

---

## 📌 에이전트 작업 지침 (Agent Protocol)

- **계획 수립 시**: 작업 계획(`/plan` 등)이 확정되면 본 파일의 당면 과제 또는 백로그에 신규 항목(`[ ]`)을 등록한다.
- **작업 착수 시**: 진행 중인 태스크를 `[-]` (진행 중)으로 전환한다.
- **작업 완료 시**: 완료 항목을 `[x]` (완료)로 변경해 `## 3. 완료된 작업 이력` 상단으로 이동·기록하고, 도출된 후속 과제를 즉시 본 파일에 등록한다.
- **완료 이력 보존 상한**: 완료된 작업 이력은 **최근 10개까지만 유지**하며, 10개를 초과하는 과거 완료 항목은 오래된 순서대로 정리(Prune)한다.
- **도메인 경로 매핑 기준**: `docs/specs/`, `src/`, `tests/` 간 1:1 도메인 계층 구조는 [README.md](README.md)의 디렉토리 레이아웃을 따른다.
- **유저 호출 예시**:
  - `TASK.md 확인하고 다음 남은 작업 진행해줘`
  - `TASK.md의 TASK-200 작업 진행해줘`
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
  - [ ] **TASK-010-5**: 유도 및 임무 도메인 매뉴얼(`playbook/2_guidance/fcp.md`, `playbook/3_planning/amm.md`) 작성
  - [ ] **TASK-010-6**: 프로젝트 규칙 반영, 컨텍스트 동기화 및 검증

- [ ] **TASK-114: GAC 전용 시설물(Dedicated Facility) 지원 및 2단계 다속성 분배 엔진/TUI 확장**
  - **사양서 상태**: `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md` (v1.4.1 Approved)
  - [x] **TASK-114-1**: 전용 시설물 사양서 개정 및 동기화 (GAC v1.4.1 Approved, 착륙패드 v2.4.2 Implemented, 도킹암 v1.11.1 Approved, 14 SPECS 100% CLEAN 검증 완료)
  - [ ] **TASK-114-2**: GAC 설정 스키마 및 인벤토리(`dedicatedCraftIds`, `dedicatedAirframeTypes`) 지원 (`src/0_infra/gac/modules/facility_inventory.lua`)
  - [ ] **TASK-114-3**: 2단계 다속성 분배 엔진 `isEligible` 및 전용 패드 최우선/폴백/비상 징발 알고리즘 구현 (`src/0_infra/gac/modules/allocation_engine.lua`)
  - [ ] **TASK-114-4**: 3-Tab TUI 콘솔 `DED` 표기 및 시설물 등록/관리 화면 확장 (`src/0_infra/gac/modules/tui_view.lua`, `main.lua`)
  - [ ] **TASK-114-5**: CraftOS-PC 단위 테스트 확장(전용 패드 격리/비상 징발 시나리오 검증, 사양서 `Implemented` 환원)

- [-] **TASK-115: ADVANCED_VTOL 짐벌 벡터 추진기 기체 아키텍처 및 전계층 연동 구현** (진행 중)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-115-advanced-vtol-architecture-and-implementation.md`
  - **격리 워크트리**: `.worktrees/task-advanced-vtol` (브랜치: `task-advanced-vtol`)
  - **진행 상황**:
    - [x] **환경 격리 및 브랜치 생성**: `.worktrees/task-advanced-vtol` 워크트리 생성 및 기본 테스트 환경 검증 완료
    - [x] **설계 인터뷰 및 아키텍처 확정 (/grill-me, /brainstorming)**: 2~4기 짐벌 벡터 통합 구동, `Base+10` 다형성 테이블 스키마, 의사역행렬($B^\dagger$) 기반 6-DoF 믹서, Alignment 짐벌 펄스 캘리브레이션 및 FCP 전용 드라이버 설계 합의
    - [x] **구현 계획서 작성 (/writing-plans)**: 7단계 세부 구현 태스크 수립 및 계획서 아티팩트(`plan-advanced-vtol.md`) 생성 완료
    - [ ] **TASK-115-1**: 사양서 6종 개정 (ICD v1.24.0, System Diagram v2.11.0, TCA v1.11.0, VAS v1.17.0, FCP v1.14.0, Alignment v2.6.0) 및 100% CLEAN 동기화
    - [ ] **TASK-115-2**: TCA `vector_thruster` 페리페럴 래핑 및 다형성 추력/짐벌 출력 구동 (`src/1_control/tca/`)
    - [ ] **TASK-115-3**: Alignment 짐벌 X/Y 펄스 시퀀서 및 제어 효과 의사역행렬 추출기 (`src/0_development/alignment/`)
    - [ ] **TASK-115-4**: VAS ADVANCED_VTOL 정책, 의사역행렬 6-DoF 렌치 믹서 및 짐벌 포화 안티와인드업 (`src/1_control/vas/`)
    - [ ] **TASK-115-5**: FCP 외루프 `advanced_vtol_driver.lua` 및 가이던스 컨트롤러 연동 (`src/2_guidance/fcp/`)
    - [ ] **TASK-115-6**: 지상 인프라 및 미션 시스템 기종 호환성 확장 (GAC, Landing Pad, GCS, Installer)
    - [ ] **TASK-115-7**: 전계층 CraftOS-PC 단위 테스트, Lua 5.2 문법 및 하네스 회귀 검증 100% PASS

- [ ] **TASK-201: AMP (Autopilot Mission Planner) 사양서 초안(Draft) 작성**
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-amp-mission-planner.md`
  - Layer 4 (`src/4_mission/amp/`) 온보드/지상 겸용 미션 플래너, 인프라 기동 6종 체계(런치패드, 활주로, 도킹 암) 및 3대 도메인 13개 체크포인트 행동 규격 제정 (`docs/specs/4_mission/amp/AMP_PROGRAM_SPECIFICATION.md`) (구 TASK-202 편대 미션 오케스트레이터 및 지상 관제 디스패처 기능 통합 대체)

- [ ] **TASK-301: 물리 하드웨어 기반 ACRO 수동 급기동 조종 인터페이스 개발 (Phase 3)**
  - Create/Avionics 아날로그 스틱 및 물리 컨트롤러 하드웨어 연동
  - `Base+1` 20Hz 직접 3축 각속도(`RATE_COMMAND`) 직결 스트림 및 비행 제어 코어(VAS) 선점 제어 연동

- [ ] **TASK-116: 통합 인스톨러(installer.lua) 기체/시설 역할별 원클릭 프로파일 배포 확장** (`installer.lua`, `src/0_development/installer/`)
  - **배경 및 필요성**: 온보드/지상 모듈(VAS, TCA, FCP, AMM, GCS, GAC, Landing Pad 등) 확장에 따른 개별 패키지·설정 조합 복잡도 해소
  - **주요 기능**: 인스톨러 대화형 UI에서 단일 컴퓨터 대상 역할 프리셋(예: `[1] Onboard Flight Core (VAS+FCP)`, `[2] Cockpit Terminal (AMM)`, `[3] Thruster Node (TCA)`, `[4] Ground Control (GCS+GAC)`) 선택 시 패키지 의존성 자동 추출, 맞춤형 설정 스캐폴딩 및 `startup.lua` 원스톱 자동 구성

- [ ] **TASK-117: 무선 원격 배포 및 OTA 업데이트 서버 (OTA Provisioner) 구축** (`src/0_development/ota/` 또는 installer 확장 모듈)
  - **배경 및 필요성**: 다중 CC:Tweaked 컴퓨터 탑재 기체(VAS, 다수 TCA, 다수 ASA, FCP, AMM 등)에서 소프트웨어 업데이트 시 인게임 개별 컴퓨터 수동 `installer.lua` 실행 비용 과다
  - **주요 기능**: 격납고 교정 채널(101 ~ 200) 또는 시스템 예약 대역(0 ~ 100)을 활용한 무선 패킷 배포 프로토콜, 격납고 마스터 컴퓨터 단일 명령으로 기체 내 모든 슬레이브 컴퓨터 로컬 파일(`src/` 하위 패키지) 무선 일괄 업데이트 및 원격 `os.reboot()` 트리거

---

## 📋 2. 예정 백로그 (Planned Backlog — Phase 1 & 2)

- [ ] **TASK-103: Runway 활주로 제어기 구현** (`src/0_infra/runway/`)
  - **사양서 상태**: `docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md` (v1.10.6 Approved)
  - 활주로 유도등, 가상 ILS 및 유도로 `GAC` 연동 관제, 3축 ILS 글라이드슬로프/로컬라이저 비콘 송출 및 착륙 접근 프로토콜

### ⏸️ 연기·보류 과제 (Deferred / On-Hold)

- [ ] **[연기] TASK-104: Docking Arm 결합 암 제어기 구현** (`src/0_infra/docking_arm/`)
  - 2축 로봇 암 포획·인입 및 엄빌리컬 보급 시퀀스 (일정 연기 — 사양서 `Approved` 유지)
- [ ] **[연기] TASK-105: ASA (Aerodynamic Surface Adapter) 공력 조종면·플랩 분산 구동기 본 구현 완성** (`src/1_control/asa/`)
  - TASK-113의 기본 프레임워크(헤드리스/비동기 TUI, `Base+11` 수신 루프, 300ms Safe Glide Trim, 단위 테스트 15/15 PASS)를 기반으로 물리 액추에이터(Avionics API/RS) 각도 인가, `MSG_AERO_STATUS` 상태 피드백 송출 및 `MSG_SURFACE_DISCOVER_REQ/ACK` 핸드셰이크 완성 (일정 연기 — 사양서 `Approved` 유지)
- [ ] **[연기] TASK-108: Tower ATC (Sector 0, `CH 50001/50002`) 광역 항공교통 관제 노드 구현**
  - 광역 공역 진입/이탈 스케줄링 및 섹터 `GAC` 핸드오프 프로토콜 구현 (일정 연기)

---

## ✅ 3. 완료된 작업 이력 (Completed Tasks Archive — 최근 10개 유지)

- [x] **TASK-007: 구버전 명칭(UAP/SAS/WAP) 전면 척결 및 회귀 방지 테스트 슈트 구축** (완료일: 2026-11-08) (`tests/harness/test_terminology_guard.py`, `tools/verify_all_specs.py`, `src/`, `tests/`, `docs/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-legacy-terminology-elimination-and-test-suite.md`
  - **목적 및 성과**: 비행 제어 및 공력 구동계 관련 구버전 잔존 명칭(`UAP`, `SAS`, `WAP`) 소급 전면 삭제(Zero-Tolerance Purge) 및 풀 마이그레이션(Full Migration) 완료. 유선 패킷 `podId`(`"ASA_L"`, `"ASA_R"`, `"ASA_T"`), 텔레메트리 헬스 키(`actuatorHealth.asa`), 모듈 파일명(`actuator_adapter_asa.lua`, `node_asa.lua`, `node_asa_sim.lua`) 일체 통일. 회귀 방지 테스트(`test_terminology_guard.py`) 및 정적 분석기(`verify_all_specs.py` Rule 8) 구축하여 14대 사양서 및 런타임/테스트 코드 0건 검출 보장. 전체 12개 타겟 단위 테스트 248/248 PASS, E2E 시뮬레이션 6/6 PASS, 돌연변이 살상률 100.0%(20/20 KILLED), 하네스 테스트 33/33 PASS, 14대 사양서 100% CLEAN(8 Implemented, 6 Approved) 달성.
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

- [x] **TASK-107: GCS 채널 관리자(`CH 50000`) 및 지상 비행 지휘 콘솔 구현** (완료일: 2026-11-08, 커밋 `e9febe6` ~ `e8c25b3`) (`docs/specs/0_infra/gcs/`, `src/0_infra/gcs/`, `tests/0_infra/gcs/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-107-gcs-channel-manager-console.md`
  - **목적 및 성과**: UAFS 항공 생태계 중앙 지상 관제 인프라로서 40채널 블록($N = 1 \sim 1000$, $Base = 10000 + (N-1)\times 40$) 스티키 영속화 관리자(`CH 50000`), 원격 비행 C2 오버라이드(`Base+0`), 직결 하드 `E_STOP` 비상차단기(`Base+1`), 실시간 텔레메트리(`Base+3`) 캐시, 51x19 무깜빡임 분할 TUI 콘솔 및 메인 데몬 루프 구현 완료.

- [x] **TASK-110: FCP VTOL 제어 고도화** (완료일: 2026-11-08, 커밋 `21f4e76` ~ `e6b22c8`) (`docs/specs/2_guidance/fcp/`, `src/2_guidance/fcp/`, `tests/2_guidance/fcp/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-110-fcp-vtol-refinement.md`
  - **목적 및 성과**: VECTORED_VTOL 기종의 외루프 유도 제어기를 3축(Surge/Sway/Heave) 완전 PID + Anti-windup, CRUISE 모드 한정 15m/s TILT_ASSISTED 피치 슬루율(최대 15°/s) 완화, 수평 고정 수직 이륙 및 착륙 패드 정렬 2단계 감속 수직 착륙 시퀀스로 전면 고도화.

- [x] **TASK-113: 온보드 제어기(VAS, TCA, ASA) 헤드리스 기본 구동 및 `parallel` 비동기 디버그 TUI 분리** (완료일: 2026-11-08, 커밋 `b5ee552` ~ `b2c5d5a`) (`docs/specs/1_control/`, `src/1_control/`, `tests/1_control/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-113-headless-parallel-debug-tui.md`
  - **목적 및 성과**: 터미널 렌더링 부하를 제거하여 실시간 20Hz 제어 루프를 보장하고, `debug: true` 설정 시에만 ComputerCraft `parallel` API 기반 비동기 디버그 TUI를 안전하게 구동하는 구조 개편 완료.

- [x] **TASK-200: AMM (Aircraft Mission Manager & Cockpit MFD 통합 단말) 구현** (완료일: 2026-11-08, 커밋 `3b2907a`) (`docs/specs/3_planning/amm/`, `src/3_planning/amm/`, `tests/3_planning/amm/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-amm-mission-manager.md`
  - TASK-106(Cockpit MFD)을 완전 병합하여 51x19 분할 TUI(5Hz 계기판 HUD + 미션 큐 및 C2 관리), 단방향 순차 웨이포인트 큐, JSON 영속화, GCS C2 무반향 감청, 원터치 핫키 및 CLI 대화형 인터페이스 일체화 단말 구현 완료.

- [x] **TASK-112: VAS 센서 파이프라인의 CC:Avionics 표준 API(`avionics_sensors`) 동기화 및 3축 속도/고도 정합화** (완료일: 2026-11-08, 커밋 `1ee16b2` ~ `95f68f5`) (`docs/specs/1_control/vas/`, `src/1_control/vas/modules/sensor_pipeline.lua`, `tests/1_control/vas/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-112-vas-sensor-pipeline-avionics.md`
  - VAS 내루프 실시간 동역학 제어용 센서 파이프라인을 전역 표준 라이브러리(`/lib/avionics_sensors.lua`)와 동기화하고, CC:Avionics 공식 API(`getHeight()`, 1축 스칼라 `getVelocity()` 3축 합성, 짐벌 오일러/각속도/중력/가속도) 정합성 확보.

- [x] **TASK-102: Landing Pad 지상 착륙 패드 제어기 구현** (완료일: 2026-11-08, 커밋 `47b98bb` ~ `c064823`) (`docs/specs/0_infra/landing_pad/`, `src/0_infra/landing_pad/`, `tests/0_infra/landing_pad/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-102-landing-pad-controller.md`
  - Landing Pad 사양서 v2.4.2 Implemented 승격, 설정 영속화, 3D 바디 오프셋 변환, 갑판 요동 판정, GPS 클라이언트, 전술 유도 스트리머, 패드 FSM, 5단계 셋업 마법사, 51x19 TUI 뷰, 20Hz 메인 데몬 루프 구현 완료.

- [x] **TASK-101: GAC (Ground Area Controller) 지상 구역 관제사 사양서 개편 및 제어기/TUI 구현** (완료일: 2026-11-08, 커밋 `0787649` ~ `e5aa176`) (`docs/specs/0_infra/gac/`, `src/0_infra/gac/`, `tests/0_infra/gac/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-101-gac-ground-apron-controller.md`
  - GAC 사양서 v1.4.1 Approved, 설정 영속화, 관할 패드 인벤토리, 2단계 다속성 최적 분배, 1Hz 섹터 대표 비콘/디스패치, 섹터 FSM 및 핸드오프/국지 복행 중재, 듀얼 디스플레이 3-Tab TUI 관제 콘솔 구현 완료.

- [x] **TASK-109: ASA 관할 범위 축소 (VECTORED_VTOL, 드론 기체 배제 및 FCP/VAS 비활성화)** (완료일: 2026-11-08) (`docs/specs/`, `src/1_control/vas/`, `src/2_guidance/fcp/`, `tests/`)
  - VECTORED_VTOL 및 드론(QUADROTOR, HEXAROTOR) 기체에서 ASA 동작 배제, FCP 외루프 flapTarget 지령 차단, VAS 내루프 ASA 타면 할당 및 Base+11 MSG_AERO_CMD 송출 비활성화 구현 완료.
