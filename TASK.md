# Create_Aeroneutics — Task Management & Implementation Roadmap

> **문서 상태**: 활성 (Living Roadmap)  
> **최종 갱신일**: 2026-11-14  
> **현재 단계**: **Phase 1 & 2** (직전 완료: TASK-207~209, TASK-124, TASK-123, TASK-204, TASK-013, TASK-402, TASK-120 / 활성 대기: TASK-117, 125, 403, 404, 302, 010, 011, 014, 501, 210)

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

> **권장 실행 우선순위**: **1순위** `TASK-117` (무선 OTA 배포·롤백) → **2순위** `TASK-125` (40채널 블록 개편·경합·검증 결함 12종 해소) · `TASK-403` (에디터 World Preset) · `TASK-404` (GCS WebSocket 브리지·실시간 전술 지도) · `TASK-302` (포켓 PDA 원격 관제·E_STOP 단말) · `TASK-010` → `TASK-011` (플레이북·에디터/FDR 문서) · `TASK-014` (3대 감사 가드레일) · **3순위** `TASK-501` (GDrive 전수 업로드·엄격 검증) / **대기** `TASK-210` (`[연기] TASK-105` 재개 연동) / **로드맵(연기)** `TASK-401`

- [ ] **TASK-117: [1순위] 무선 OTA 배포 서버 및 슬레이브 원자적 롤백 가드 구축 (구 TASK-117 + 119 통합)** (`src/0_development/ota/`, `src/0_development/installer/modules/startup_generator.lua`, `src/1_control/{vas,tca}/`, `src/2_guidance/fcp/`, `src/3_planning/amm/`)
  - **권장 착수 순위**: **1순위** (선행 과제 `TASK-202`·`TASK-204`·`TASK-207~209`·`TASK-013`·`TASK-402`·`TASK-120` 완료로 즉시 착수 가능)
  - **사양서 상태**: 통합 OTA 사양서 미작성(Draft → Approved 및 대상 경로 확정 필요) / 연관 개정 대상: `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` (현재 v1.1.1 Implemented), `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.31.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.15.1 Approved), `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (현재 v1.21.0 Implemented), `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (현재 v1.12.0 Implemented), `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (현재 v2.1.0 Implemented), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v2.0.1 Implemented)
  - **배경 및 통합 사유**: 다중 CC:Tweaked 컴퓨터 탑재 기체(VAS, 다수 TCA, 다수 ASA, FCP, AMM)의 수동 `installer.lua` 업데이트 비용을 해소하되, `Zero-Fallback` 원칙상 체크섬 검증·`/ota_staging/` 원자적 교체 응답·안전 게이트 거부(`NACK`) 사유 코드가 서버 프로토콜에 처음부터 일체화되어야 재설계를 방지할 수 있음. 또한 비행 중 OTA 재부팅 추락 및 패킷 유실로 인한 벽돌(Brick) 장애를 막기 위해 서버와 슬레이브 부트스트랩 가드를 단일 E2E 게이트로 통합 검증함
  - **주요 작업**:
    - [ ] **TASK-117-1**: 통합 OTA 사양 및 아키텍처 동시 개정 — 격납고 예약 대역(`101 ~ 200`, `Base_hangar+4~+9`) 무선 OTA 채널(`0 ~ 100` 유선/내부 IPC 대역 배제), `/.version.json` 기반 다중 노드 주소 지정(`VAS`·`TCA`·`FCP`·`AMM`), 체크섬·원자적 교체 ACK/NACK(`NOT_DISARMED` 등) 패킷 스키마를 통합 사양서(Draft → Approved), 마스터 ICD, 전체 구조도, 인스톨러·VAS·TCA·FCP·AMM 사양서에 동시 반영
    - [ ] **TASK-117-2**: 슬레이브 OTA 에이전트 및 2단계 부트 커밋 워치독 구현 — 수신 파일을 `/ota_staging/`에 기록 후 CRC/해시 일치 시에만 본 경로로 교체하고, `pending_ota` 마커와 초기 정상 틱 커밋·예외/미커밋 재부팅 시 `/ota_backup/` 자동 복구 래퍼를 `startup.lua` 생성기에 내장 (`src/0_development/installer/modules/startup_generator.lua`)
    - [ ] **TASK-117-3**: 온보드 안전 상태 게이트 및 노드 타게팅 연동 — 기체가 `DISARMED`·지상 `IDLE_ARMED`·지상 `E_STOP`(`not isAirborne`) 등 비비행 안전 상태일 때만 OTA 수신·적용을 허용하고 비행 중에는 `NACK` 거부하는 상태 게이트 구현 (`src/1_control/{vas,tca}/`·`FCP`·`AMM` 우선 적용, `src/1_control/asa/`는 `TASK-105` 연기 해제 시 연동)
    - [ ] **TASK-117-4**: 격납고 무선 OTA 배포 서버 구축 및 매니페스트 동기화 — 격납고 마스터 컴퓨터 단일 명령으로 기체 내 슬레이브 컴퓨터 로컬 파일(`src/` 하위 패키지) 일괄 배포 및 원격 `os.reboot()` 트리거 구현 (`src/0_development/ota/` 신설 시 `manifest.lua`, `config/gdrive_mapping.json`, `verify_manifest_sync.py` 정합성 동기화 필수)
    - [ ] **TASK-117-5**: 멀티노드 OTA E2E 시뮬레이션 검증 및 사양서 승격 — 정상 일괄 배포, 비행 상태 `NACK` 거부, 체크섬 불일치 중단, 부팅 크래시 자동 `/ota_backup/` 롤백 E2E 검증 완료 후 관련 사양서 `Implemented` 승격

- [ ] **TASK-125: [2순위 / 프로토콜·아키텍처] 비행체 40채널 블록 사용 채널 개편 및 프로토콜·경합·검증 결함 12종 해소** (`docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.31.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.15.1 Approved), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v2.0.1 Implemented), `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (현재 v1.21.0 Implemented), `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (현재 v2.1.0 Implemented), `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` (현재 v1.1.0 Implemented), `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (현재 v2.7.0 Implemented))
  - **권장 착수 순위**: **2순위** (`TASK-117` 다음, `TASK-302` Pocket PDA 비상 단말 및 `TASK-010` 플레이북 작성 전 채널 체계 정립을 위해 선행 권장)
  - **사양서 상태**: 마스터 ICD 및 전체 구조도, 연관 5대 서브시스템 사양서 개정 필요 (Spec-First: Approved 승격 후 코드베이스 반영)
  - **배경 및 필요성**: 현행 40채널 블록($BW=40$) 구조에서 고속 비행 유도(`Base+1`)와 비상 정지(`E_STOP`)의 패킷 혼재, 지상 교정(`Base+0`)과 비행 C2 패킷의 VAS 유입, ARP 유사 채널 충돌 프로브의 동시 부팅/오프라인 점유자 미탐지 결함, `Base+3` 이중 송신자 경합, `Base+30` 대역의 Payload 재편 및 편대 TBD, `reqBW` 가변 대역폭 vs `stride 40` 고정 불일치, GCS `REASSIGNED` 상태값 불일치, 비행 중 침범 감시 범위 누락(`Base+20~39`), Rule 3 수학적 중복, 그리고 다이어그램 의사코드 인자 불일치 버그를 해소함
  - **주요 작업**:
    - [ ] **TASK-125-1**: E_STOP 및 EMERGENCY_ALERT 전용 채널(`Base+9`) 격리 — `Base+1`(`CH_FLIGHT_GUIDANCE`)에서 혼재되던 `E_STOP` 및 `MSG_EMERGENCY_ALERT`를 Zone 1 예비 대역인 `Base+9`(`CH_EMERGENCY_CORE`) 전용 채널로 이동하여 20Hz 비행 유도 패킷과의 충돌 분리
    - [ ] **TASK-125-2**: 동시 부팅 경합 방지 및 충돌 프로브 강화 — 단일 200ms 청취의 한계를 극복하기 위해 랜덤 백오프(Jitter 0~100ms) 및 다회 재프로브 시퀀스 도입, 충돌 응답(`CONFLICT_DETECTED`) 수신 시 회피 절차 정립
    - [ ] **TASK-125-3**: 꺼진 점유자(Sleeping Occupant) 충돌 방지 체계 수립 — 기존 기체의 AMM 전원이 꺼져 있을 때 침묵을 빈 채널로 오판하는 결함을 방지하기 위해 GCS 레지스트리 영속 리스/클레임 검증, 디스크 캐시 점유 마커 및 부팅 시 재검증 핸드셰이크 규격 명세
    - [ ] **TASK-125-4**: 프로브 응답자 리스닝 조건 명시 — 기체 AMM이 부팅 직후(Disarmed/대기 상태 포함) `Base+0`을 상시 개방하여 외부 충돌 프로브를 감청하고 즉시 응답하는 필수 수신 조건을 사양서에 명문화
    - [ ] **TASK-125-5**: Base+3 이중 송신자 핸드오버 경합 해소 — `Base+3`(`CH_MFD_STATE`)의 평시 `AMM` 5Hz 송출과 `MFD_ACRO` 진입 시 `VAS` 20Hz 송출 간 소스 우선순위를 `VAS` 20Hz 우선으로 확정하고, AMM 송출 억제 및 복귀 시퀀스/히스테리시스 규칙 정의
    - [ ] **TASK-125-6**: 지상 교정 중 패킷 혼재 해소 — `Base+0`에 C2 비행명령, 충돌 프로브, 격납고 교정 바인딩(`MSG_CALIBRATION_INIT`, VAS 수신)이 혼재되어 교정 중 C2 패킷이 VAS로 유입되는 문제를 전용 채널 분리(예: `Base+8` 등) 또는 엄격한 패킷 필터링으로 차단
    - [ ] **TASK-125-7**: Base+30 채널대 Payload 용도 개편 및 편대 비행 채널 TBD 재정의 — `Base+30 ~ 39` 대역을 Zone 3 확장(Payload/특수 임무 버스)으로 통합 재편하고, 편대 비행(Formation Flight) 채널 개념은 차후 독립 광역 데이터링크로 재정의하기 위해 사양서상 `TBD`로 할당
    - [ ] **TASK-125-8**: 전체 구조도 의사코드 인자 불일치 버그 수정 — `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` L798의 `checkCollision(existingCraft.baseChannel, reqBW, craftUuid)` (3개 인자) 호출부를 L827 정의(`baseA, bwA, baseB, bwB`, 4개 인자)에 부합하도록 정합화
    - [ ] **TASK-125-9**: reqBW 가변 대역폭 vs stride 40 고정 불일치 해소 — $N$ 인덱스 간격이 $stride = 40$으로 고정된 상태에서 $reqBW > 40$ 시 인접 블록 침범 및 모순이 발생하므로, 대역폭을 $BW=40$ 고정 계약으로 단일화하고 가변 필드 유효성 검증 정합화
    - [ ] **TASK-125-10**: GCS 재할당 상태값 불일치 정합화 (`REASSIGNED` vs `ASSIGNED`) — §6.3 안전 매트릭스에서 정의된 자동 재할당 회신 상태 `REASSIGNED`를 의사코드(L799, L820) 및 시퀀스 5 다이어그램과 일치하도록 상태값 체계 동기화
    - [ ] **TASK-125-11**: 비행 중 채널 침범 감시 범위 전수 확대 (`Base+20~39` Payload 버스 포함) — §6.3 비행 중 침범 감지 대상이 `Base+0~5, +10~11`로 제한되어 누락된 `Base+20/21/30` 및 Zone 3 Payload 확장 버스(`Base+20~39`)를 비행 중 감시 대상에 전수 포함
    - [ ] **TASK-125-12**: 채널 검증 규칙 Rule 3 수학적 중복 제거 및 경계 검증 단순화 — Rule 2($Base + BW - 1 \le 49999$) 만족 시 인프라 대역($[50000, 60020]$) 침범이 수학적으로 불가능하므로, Rule 3의 논리적 중복을 해소하고 검증 의사코드 단순화
    - [ ] **TASK-125-13**: 전사 사양서 동기화, 정적 검증 및 하네스 회귀 테스트 — 마스터 ICD, 전체 구조도 및 연관 5대 사양서 개정, `verify_all_specs.py`, `verify_spec_status.py`, 단위/E2E 테스트 검증 및 컨텍스트 동기화

- [ ] **TASK-403: [2순위 / 에디터·AMM 확장] AMM WebUI 미션 에디터 World Preset, 시설 기반 이착륙 지정 및 `ACT_TKL_LAND_NEAREST` 추가** (`docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (현재 v0.3.1 Implemented), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v2.0.1 Implemented), `tools/amm_mission_editor.html`, `src/3_planning/amm/`, `tests/3_planning/amm/`)
  - **권장 착수 순위**: **2순위** (`TASK-120`·`TASK-117` 다음, `TASK-011-4` 에디터 매뉴얼 작성 전 착수; Spec-First 절차 준수)
  - **확정 설계 결정 (`/grill-me` 2026-11-14)**:
    - **구조 범위**: **멀티 월드 프로필 구조** — 월드/서버별 이름(`Survival_Main`, `Test_Lab` 등)을 생성·전환하며 각 월드마다 시설물 목록 독립 보관
    - **시설 스키마**: `facilityId`, `label`, `type`(`LANDING_PAD` | `RUNWAY` | `DOCKING_ARM` | `RALLY` | `POI` | `CUSTOM`), `x`/`z`(필수), `y`(선택), `headingDeg`(선택), `notes`(선택)
    - **이중 영속성**: `localStorage` 자동 저장 + World Preset `.json` 파일 Export/Import(백업·공유·병합) 병행
    - **UI/등록 동선**: 상단 헤더 `World` 선택·드로어(`#worldPresetDrawer`) + 체크포인트 `Params` `'Save as Facility'` 및 캔버스 좌표 픽커(`PICK_FACILITY`) 빠른 등록
    - **편집 연동 및 바인딩**: 2D 캔버스 배경 시설물 핀 레이어(토글·클릭 할당/센터링) + 인스펙터 `Params` `'From World…'` 퀵픽 + `'+ From Facility'` 병행; **순수 값 복사**(미션 JSON `v2.0.0` 순수성 유지) 및 **스마트 Y 매핑**(`facility.y`는 `poiPos.y`에 기본 반영하고 `targetAlt`는 비행 고도 보호를 위해 명시적 선택 시에만 적용)
    - **이착륙 시설 지정 규약**: 도킹암(`ACT_MOB_ARM_DOCK`/`UNDOCK`)·랜딩패드(`ACT_TKL_TAKEOFF_VERT`, `ACT_TKL_LAND_NORM`/`PREC`)·활주로(`ACT_TKL_TAKEOFF_RWY`/`LAND_RWY`) 및 시설 기반 매크로(`MAC_*`)는 **활성 월드 프로필 내 호환 타입 시설 드롭다운 선택**으로 전환(좌표·`facilityId` 자동 채움; 외부 JSON 미등록 `facilityId` 임포트 시 `WARNING` + `'현재 월드에 등록'` 1클릭 버튼 제공)
    - **신규 행동 `ACT_TKL_LAND_NEAREST` (가장 가까운 착륙 가능 시설에 착륙)**: `AMM` 런타임(`facility_client.find_nearest_free_landing_facility` 연동)과 에디터 동시 확장; `facilityTypeFilter`(`"ANY"` | `"LANDING_PAD"` | `"RUNWAY"`)·`maxRangeM`(선택) 지원, 비콘 기반 최근접 `FREE` 착륙 시설 동적 탐색 후 착륙(`FACILITY_TOUCHDOWN` 완료), 가용 시설 부재 시 체크포인트 `abort`/`fallbackPolicy` 전이
    - **2D XZ 캔버스 4변 좌표 눈금 표시**: 메인 `(X, Z)` 평면 상단/하단(X축) 및 좌측/우측(Z축) 가장자리 격자선에 월드 좌표 라벨(`tabular-nums` 고정폭, 주 격자선 정렬, 툴바·HUD 영역 회피) 실시간 렌더링
  - **주요 작업**:
    - [ ] **TASK-403-1**: Spec-First 양대 사양서 개정 — `AMM_PROGRAM_SPECIFICATION.md` (`v2.0.1 Implemented` → `v2.1.0 Approved`, `ACT_TKL_LAND_NEAREST` 규격) 및 `AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.3.1 Implemented` → `v0.4.0 Approved`, World Preset·호환 시설 드롭다운·`ACT_TKL_LAND_NEAREST`·2D 캔버스 4변 격자 좌표 눈금 규격) 동시 반영
    - [ ] **TASK-403-2**: 온보드 `AMM` `ACT_TKL_LAND_NEAREST` 구현 (`src/3_planning/amm/`, `tests/3_planning/amm/`) — `action_registry.lua`(활성 37종 확장), `mission_engine.lua`·`main.lua`·`facility_client.find_nearest_free_landing_facility` 동적 탐색/가용 시설 부재 전이 연동, `condition_evaluator.lua`·`ui_renderer.lua` 및 Lua 단위 테스트 추가
    - [ ] **TASK-403-3**: 에디터 월드 프리셋 스토어 & 이중 영속성 구현 (`tools/amm_mission_editor.html`) — `WorldStore` 모듈(멀티 월드 생성/전환/수정/삭제, 시설 CRUD, `localStorage` 영속화, `.json` Import/Export 병합, DOM XSS 안전 렌더링) 구현
    - [ ] **TASK-403-4**: 에디터 `#worldPresetDrawer`·2D 캔버스·시설 지정·`ACT_TKL_LAND_NEAREST` UI 구현 (`tools/amm_mission_editor.html`) — 상단 `World` 컨트롤, 2D 4변(상하 `X`·좌우 `Z`) 격자 좌표 눈금 & 배경 핀 레이어/토글, `PICK_FACILITY`, 이착륙/도킹 호환 시설 드롭다운·미등록 경고/1클릭 등록, `'From World…'` 퀵픽·`'Save as Facility'` 등록, `ACT_TKL_LAND_NEAREST` 폼/검증, `Undo` 보호
    - [ ] **TASK-403-5**: 전수 회귀 테스트(CraftOS-PC 라운드트립 포함) 및 사양서 승격 — `test_amm_mission_editor.py`·`run_unit_tests.py`·`run_e2e_tests.py` 통과 후 `AMM_PROGRAM_SPECIFICATION.md` (`v2.1.0`) 및 `AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.4.0`) `Implemented` 승격

- [ ] **TASK-404: [2순위 / 에디터·GCS 실시간 연동] GCS WebSocket 브리지 및 실시간 전술 지도·원클릭 미션 무선 푸시** (`tools/gcs_live_bridge.py`, `tools/amm_mission_editor.html`)
  - **권장 착수 순위**: **2순위** (`TASK-403` 완료 이후 착수)
  - **선행 의존성**: `TASK-403` (`tools/amm_mission_editor.html`의 `WorldStore` 및 2D 캔버스 완료 이후)
  - **배경 및 필요성**: 브라우저 에디터에서 작성한 미션 JSON을 매번 월드 세이브 폴더로 복사하는 수작업을 제거하고, `TASK-403`의 월드 시설물 지도 위에 실제 비행 중인 기체의 실시간 궤적을 오버레이함
  - **주요 작업**:
    - [ ] **TASK-404-1**: 로컬 Python WebSocket 브리지(`tools/gcs_live_bridge.py`) 구축 — 인게임 `GCS` 컴퓨터(`http.websocket`)와 외부 브라우저 WebUI 간 양방향 JSON 중계 서버 구현
    - [ ] **TASK-404-2**: `amm_mission_editor.html` Live Mode 확장 — `WorldStore` 2D 캔버스 위에 다중 기체 실시간 위치·기수각·계획 경로 대비 실제 궤적(`Trail`) 렌더링 및 상단 헤더 `'Push to Aircraft'` 원클릭 무선 미션 전송·즉시 로드 기능 구현

- [ ] **TASK-302: [2순위 / 현장 운용 HMI] CC:Tweaked 포켓 컴퓨터(Pocket PDA) 휴대용 원격 관제·지상 콘솔 링크·비상 E_STOP 단말** (`src/0_infra/pocket_pda/`)
  - **권장 착수 순위**: **2순위** (`TASK-120` 완료 후 FDR 동적 바인딩·원격 덤프 트리거 연동 시 시너지 극대화)
  - **선행 의존성**: `TASK-120` (FDR 원격 바인딩·덤프 트리거 연동 시 시너지 극대화)
  - **배경 및 필요성**: 인게임 시험 비행·정비 중 기체 이상 진동이나 경로 이탈 시 고정형 GCS·Alignment·FDR 콘솔까지 이동할 시간적 여유가 없음. 플레이어가 인벤토리에서 꺼내 즉시 기체 비상 제어뿐 아니라 `Alignment`, `FDR` 등 지상/온보드 시스템과의 무선 링크(기체 바인딩·세션 제어)까지 수행할 수 있는 무선 휴대 단말(`src/0_infra/pocket_pda/`)이 필요함.
  - **주요 작업**:
    - [ ] **TASK-302-1**: Pocket Computer 전용 경량 TUI 구현 — 소형 화면(26×20)에 최적화된 기체 선택기, 고도·속도·자세·연료 HUD, 링크 품질(RSSI/거리) 및 연결 대상(`Alignment`/`FDR`/`GCS`/`AMM`) 상태 표시
    - [ ] **TASK-302-2**: 원격 비상 제어 및 FDR 연동 — 단일 키 입력으로 무선 `E_STOP` 송출 + `TASK-120` 블랙박스 로그 즉시 JSONL 덤프 트리거, `HOLD` / `RTB` / `LAND_NEAREST` 단축 명령 지원
    - [ ] **TASK-302-3**: `Alignment`·`FDR` 등 원격 링크 및 세션 제어 연동 — Pocket PDA에서 기체 인덱스 $N$을 지정해 `Alignment`(격납고 베이 바인딩·교정 세션 개시/중단/해제)·`FDR`(`STANDBY`↔`LOGGING` 동적 기체 $N$ 바인딩 전환·로그 반출 트리거) 등 주요 노드 간 원격 링크·해제 수행 지원

- [ ] **TASK-010: [2순위] 개별 코드베이스 사용 설명서(Playbook) 체계 구축 및 핵심 5종 매뉴얼 작성**
  - **권장 착수 순위**: **2순위** (`GPS`·`VAS`·`TCA`·`FCP`·`AMM`·`tools/amm_mission_editor.html` 모두 `Implemented` 승격 완료; 1순위 `TASK-120`·`TASK-117` 이후 또는 병렬 착수 가능, `TASK-011`의 선행 기반)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-010-playbook-framework.md`
  - 계층형 단일 마크다운(`playbook/<도메인>/<서브시스템>.md`) 기반 인게임 운용 실전 매뉴얼 5종(GPS, VAS, TCA, FCP, AMM) 구축, 표준 7대 섹션 템플릿(`playbook/README.md`), CLI 정적 검증 도구(`tools/verify_playbooks.py`), 미인가 체계 작성 차단 가드레일 및 워크플로우 동기화
  - [ ] **TASK-010-1**: 플레이북 정적 검증 도구(`tools/verify_playbooks.py`) 구현 (7대 필수 섹션, 링크 유효성, 미인가 파일 생성 차단 검증)
  - [ ] **TASK-010-2**: 표준 템플릿 명세 및 인덱스(`playbook/README.md`) 작성
  - [ ] **TASK-010-3**: 인프라 도메인 매뉴얼(`playbook/0_infra/gps.md`) 작성 (`GPS v2.3.3 Implemented` 반영)
  - [ ] **TASK-010-4**: 온보드 제어 도메인 매뉴얼(`playbook/1_control/vas.md`, `playbook/1_control/tca.md`) 작성 (`VAS v1.20.0` `QUATERNION_RATE`·`Base+3` `MFD_ACRO`·`system.json` 및 `TCA v1.12.0` 반영)
  - [ ] **TASK-010-5**: 유도 및 임무 도메인 매뉴얼(`playbook/2_guidance/fcp.md`, `playbook/3_planning/amm.md`) 작성 (현행 `FCP v2.1.0` `Base+4/+2/+1` 3채널 순수 `SE(3)` 외루프 및 `TASK-204`·`TASK-013`·`TASK-402` 반영 완료 기준 `AMM v2.0.1` 듀얼 모뎀 외부 게이트웨이·`nav_engine`·`trajectory_generator`·`ACT_*`/`DEC_*`/`MAC_*` 3계층 미션 시퀀서·`chattering_guard`·CLI/TUI·외부 파일 즉시 구동 규격 및 `amm_mission_editor.md` 연동 안내 반영)
  - [ ] **TASK-010-6**: 프로젝트 규칙 반영, 컨텍스트 동기화 및 검증 (`test_tools_integrity.py` 도구 등록·`verify_context_docs.py` 통과 및 `TASK-009`·`013`·`113`·`114`·`115`·`116`·`122`·`202`·`207~209`·`402` 현행 반영 확인)

- [ ] **TASK-011: [2순위 / 확장 매뉴얼] 지상 관제·정비·미션 에디터·FDR 및 텔레메트리 분석기 플레이북 2차 확장** (`playbook/0_development/{alignment,fdr}.md`, `playbook/0_infra/{gcs,gac,landing_pad}.md`, `playbook/3_planning/amm_mission_editor.md`)
  - **선행 의존성**:
    - **공통 선행**: `TASK-010` 완료 필요 (표준 7대 섹션 템플릿 `playbook/README.md` 및 `tools/verify_playbooks.py` 검증·인가 목록 체계 활용)
    - **완료 연동**: `TASK-011-5` (`playbook/0_development/fdr.md`)는 `TASK-120` 완료(`FDR v0.3.0 Implemented`, `tools/analyze_flight_log.py`) 기준 반영 가능 (`Alignment`, `GCS`, `GAC`, `Landing Pad`, `Mission Editor`, `FDR` 모두 `TASK-010` 완료 즉시 착수 가능)
  - **배경 및 필요성**: `TASK-10`은 핵심 5종(GPS, VAS, TCA, FCP, AMM)에 집중되어 있으므로, ① 실제 인게임 운용 시 설정·조작이 까다로운 격납고 동역학 캘리브레이션(`Alignment`)과 지상 관제소/패드(`GCS`, `GAC`, `Landing Pad`), ② `TASK-402`로 구현 완료된 오프라인 WebUI 미션 에디터(`tools/amm_mission_editor.html`, `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (현재 v0.3.1 Implemented))의 작성·검증·AMM 투입 워크플로우, ③ `TASK-120`으로 구축 완료된 지상 In-Flight Aligner FDR(`src/0_development/fdr/`) 및 오프라인 텔레메트리 분석기(`tools/analyze_flight_log.py`) 운용·진단 매뉴얼을 통합 확장함
  - **주요 작업**:
    - [ ] **TASK-011-1**: 격납고 동역학 캘리브레이션 매뉴얼(`playbook/0_development/alignment.md`) 작성
    - [ ] **TASK-011-2**: 중앙 지상 관제소 매뉴얼(`playbook/0_infra/gcs.md`) 작성
    - [ ] **TASK-011-3**: 섹터 관제·착륙패드 매뉴얼(`playbook/0_infra/gac.md`, `playbook/0_infra/landing_pad.md`) 작성
    - [ ] **TASK-011-4**: AMM WebUI 미션 에디터 운용 매뉴얼(`playbook/3_planning/amm_mission_editor.md`) 작성 (`tools/amm_mission_editor.html` 기준 2D 캔버스/인스펙터·조건/훅 빌더·프리플라이트 검증·JSON Export → `AMM` 다중 경로/드래그앤드롭 투입 연동 및 `amm.md` 상호 참조; `TASK-403` 완료 시 World Preset 기능 포함)
    - [ ] **TASK-011-5**: 지상 In-Flight Aligner FDR 및 오프라인 텔레메트리 분석기 매뉴얼(`playbook/0_development/fdr.md`) 작성 (`TASK-120` 완료 연동 — `src/0_development/fdr/` 감청·VFS 디스크 풀·`GDRIVE_WEBHOOK` 반출 절차 및 `tools/analyze_flight_log.py` CLI 튜닝·진단 해석 가이드)
    - [ ] **TASK-011-6**: `playbook/README.md` 인덱스·`tools/verify_playbooks.py` 인가 목록 동기화 및 7대 섹션·링크 정적 검증 통과

- [ ] **TASK-014: [2순위 / 검증 인프라] 전수 감사 3대 사각지대 방지 가드레일 구축 (SSOT 계약·E2E 패킷 검증·런타임 배선/실부팅 스모크)** (`config/protocol_contracts.json`, `tools/verify_contracts.py`, `tools/verify_runtime_wiring.py`, `tools/run_boot_smoke.py`, `harness/simulation/virtual_bus.lua`, `tools/run_e2e_tests.py`, `.agent/`)
  - **설계서 및 실행 계획서**: [2026-11-14-audit-prevention-guardrails-design.md](docs/superpowers/specs/2026-11-14-audit-prevention-guardrails-design.md), [2026-11-14-task-014-audit-prevention-guardrails.md](docs/superpowers/plans/2026-11-14-task-014-audit-prevention-guardrails.md)
  - **확정 설계 결정 (`/brainstorming` · `/grill-me` 2026-11-14)**:
    - **SSOT 원천**: `config/protocol_contracts.json`을 기계 판독형 계약 정본으로 신설하고, `tools/verify_contracts.py`가 16개 활성 사양서·활성 `src/` Lua/JSON·E2E 패킷을 교차 검증 (`Revision History`·`[DEPRECATED]` 배지 맥락 오탐 배제).
    - **와이어 계약 검증**: `virtual_bus.lua` + `tools/run_e2e_tests.py`가 E2E 중 오가는 모든 패킷을 `result.json`으로 캡처해 엔벨로프·필수키·열거형·수치범위·Zero-Fallback을 자동 검증하며, 정적 `src/` 이중키 폴백 린트 병행.
    - **미배선 런타임 경로 차단**: `tools/verify_runtime_wiring.py`로 `main.lua` 도달성·고아 모듈·깨진 `require`·미사용 임포트를 검출하고, `tools/run_boot_smoke.py`로 10개 활성 `main.lua`를 CraftOS-PC에서 실제 설치 레이아웃으로 약 7틱 부팅 스모크 검증.
    - **유예 및 컨텍스트 게이트**: `src/1_control/asa`(`TASK-105`) 런타임 검사는 `--include-deferred` 전까지 기본 유예(사양서 16종 SSOT는 전수 검사); `.agent/hooks/`는 R1~R8 경량 유지하고 `skill-workflows.md`·스킬 지침으로 완료 게이트 통합.
  - **주요 작업**:
    - [ ] **TASK-014-1**: `config/protocol_contracts.json` SSOT 스키마 구축 및 로더 검증 (`tests/harness/test_verify_contracts.py`)
    - [ ] **TASK-014-2**: `tools/verify_contracts.py` 사양서 SSOT 대조 및 정적 Zero-Fallback/폐기키 린터 구현
    - [ ] **TASK-014-3**: `virtual_bus.lua` + `tools/run_e2e_tests.py` E2E 실전 패킷 캡처 계약 검증 연동 (`tests/harness/test_e2e_contract_validation.py`)
    - [ ] **TASK-014-4**: `tools/verify_runtime_wiring.py` 정적 도달성·고아 모듈·미사용 임포트 검증기 구현 (`tests/harness/test_verify_runtime_wiring.py`)
    - [ ] **TASK-014-5**: `tools/run_boot_smoke.py` 10개 활성 `main.lua` CraftOS-PC 실부팅 스모크 러너 구현 및 `test_tools_integrity.py` 등록
    - [ ] **TASK-014-6**: `.agent/` 규칙·스킬 게이트 및 컨텍스트 문서 동기화

- [ ] **TASK-501: [3순위 / 배포 인프라] Google Drive 전수 패키지(101종) 업로드·매핑 동기화 및 `--strict-gdrive-packages` 게이트 활성화** (`config/gdrive_mapping.json`, `tools/sync_gdrive.py`, `tools/verify_manifest_sync.py`, `dist_gdrive/`)
  - **등록 배경**: `TASK-013` Q8 결정(방안 A 우선 적용 + 방안 B 후속 과제 분리)에 따라 현행 9종 부트스트랩/공용 파일 해시 갱신만 우선 완료하고, 12개 서브시스템 전수 패키지 파일(`101`건; `manifest.lua` `109`경로 + 루트 `installer.lua` - 기매핑 `9`건)의 Google Drive 실업로드·매핑 등록 및 엄격 정합성 게이트 활성화를 별도 과제로 추적함.
  - **주요 작업**:
    - [ ] **TASK-501-1**: `python tools/sync_gdrive.py stage` 실행으로 `dist_gdrive/` 내 12개 서브시스템 전수 패키지 스테이징 생성 및 무결성 확인
    - [ ] **TASK-501-2**: `gdrive` CLI 환경에서 `python tools/sync_gdrive.py sync --dry-run` 검증 후 본 동기화(`sync`) 실행 및 `config/gdrive_mapping.json` 내 전수 패키지(`101`건)의 `fileId`, `sha256`, `sizeBytes` 갱신
    - [ ] **TASK-501-3**: `python tools/verify_manifest_sync.py --strict-gdrive-packages` `0 Errors, 0 Warnings` 검증 통과 및 CI/표준 검증 파이프라인 반영

- [ ] **TASK-210: [대기] ASA v1.8.0 구현 정합화 및 VAS·Alignment 실노드 연동 검증 (`MSG_AERO_*` · `MSG_SURFACE_DISCOVER_*` · 4계층 재바인딩 반영)** (`docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (현재 v1.8.0 Approved), `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (현재 v1.12.0 Implemented), `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (현재 v2.7.0 Implemented), `src/1_control/asa/`)
  - **선행 의존성**:
    - **기완료 기반 (`TASK-206`·`TASK-207`·`TASK-208`·`TASK-209`·`TASK-013` 완료)**: `VAS v1.20.0` (`Implemented`, `actuator_adapter_asa.lua`·`Base+11` 송신단), `TCA v1.12.0` (`Implemented`, `Option A` 재바인딩·`Base_hangar+3` 탐색), `ALIGNMENT v2.7.0` (`Implemented`, `discovery_client.lua` `MSG_SURFACE_DISCOVER_REQ/ACK`·`profile_exporter.lua`) 정합화 및 1차 E2E(`244c940`) 완료.
    - **잔여 차단 의존성**: **`[연기] TASK-105` (ASA 본 구현 재개 및 `FLT-HIGH-12` 5대 골격 결함 해소)** — `TASK-013` Q4 방안 B에 따라 `src/1_control/asa/**`·`tests/1_control/asa/**`가 동결(`0 diff`)되어 있으므로, `TASK-105` 재개 시 본 과제를 일괄 병행 수행함.
  - **배경 및 목적**: ① **[기반 완료 — `TASK-207/208/209` E2E (`244c940`) + `TASK-013` 전수 교정]** `TCA`/`Alignment`/`VAS` 간 채널·`AMM -> FCP -> VAS -> TCA` 4계층 재바인딩(`[I-9]` `MSG_CHANNEL_REBIND_ACK` Option A), `[I-4]` 격납고 캘리브레이션 와이어·`UUID`(`VAS-NODE-01-4402`), `VAS` `actuator_adapter_asa.lua` 송신단(`[-1.0, +1.0]`/`[0.0, 1.0]`, `VAS §9.5`) 및 `Alignment` `discovery_client.lua`(`MSG_SURFACE_DISCOVER_REQ/ACK`) 정합 구현·`Implemented` 승격 완료, ② **[잔여 범위 — `TASK-105` 재개 시]** 동결 중인 `ASA` 본 구현 재개와 함께 `FLT-HIGH-12` 결함을 해소하여 `Base+11` (`10011`), `bandwidth = 40`, `[I-10]` `MSG_AERO_CMD`/`MSG_AERO_STATUS`(`[-1.0, +1.0]`/`[0.0, 1.0]`, `dynamicPressureFactor`, `interactionMode`, `appliedDeflection`, `"NOMINAL"|"DEGRADED"|"TOTAL_LOSS"`, `"SAFE_GLIDE_TRIM"`), `MSG_SURFACE_DISCOVER_REQ/ACK`(`Base+11`·`Base_hangar+3`), `MSG_CALIB_BAY_BIND`(`baseHangarChannel`)·`MSG_PROFILE_SYNC` `"RUDD"`, `AMM -> FCP -> VAS -> ASA` 4계층 재바인딩(`oldBase + 11` / `newBaseChannel + 11`, `500ms`)을 구현·다중 노드 E2E(`AMM ↔ FCP ↔ VAS ↔ ASA ↔ Alignment`)로 검증한 뒤 `ASA` 사양서를 `Implemented`로 승격함

---

## 📋 2. 예정 백로그 (Planned Backlog — Phase 1 & 2)

### ⏸️ 연기·보류 과제 (Deferred / On-Hold)

- [ ] **[연기] TASK-103: Runway 활주로 제어기 사양서 상세화 및 활주로 제어기 코드베이스 작성** (`docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md`, `src/0_infra/runway/`)
  - **사양서 상태**: `docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md` (v1.11.0 Approved)
  - 활주로 제어기 사양서 상세화 및 코드베이스 구현: 활주로 유도등, 가상 ILS 및 유도로 `GAC` 연동 관제, 3축 ILS 글라이드슬로프/로컬라이저 비콘 송출 및 착륙 접근 프로토콜 (`TASK-116` 완료로 `0_infra` 폴더 스크롤 수용 가능; 일정 연기 — 사양서 `Approved` 유지, 구현 시 `manifest.lua` 등록 및 `verify_spec_status.py` 갱신 필요)
- [ ] **[연기] TASK-104: Docking Arm 결합 암 제어기 구현** (`src/0_infra/docking_arm/`)
  - **사양서 상태**: `docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md` (v1.12.0 Approved)
  - 2축 로봇 암 포획·인입 및 엄빌리컬 보급 시퀀스 (`AMM (Node 03)` 주도 4단계 랑데부 연동; 일정 연기 — 사양서 `Approved` 유지, 구현 시 `manifest.lua` 등록 및 `verify_spec_status.py` 갱신 필요)
- [ ] **[연기] TASK-105: ASA (Aerodynamic Surface Adapter) 공력 조종면·플랩 분산 구동기 본 구현 완성** (`src/1_control/asa/`)
  - **사양서 상태**: `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (v1.8.0 Approved)
  - TASK-113의 기본 프레임워크(헤드리스/비동기 TUI, `Base+11` 수신 루프, 300ms Safe Glide Trim, 단위 테스트 15/15 PASS)를 기반으로 물리 액추에이터(Avionics API/RS) 각도 인가, `MSG_AERO_STATUS` 상태 피드백 송출 및 `MSG_ACTUATOR_DISCOVER_REQ/ACK` 핸드셰이크 완성 (`TASK-210` 연동; 일정 연기 — 사양서 `Approved` 유지; 재개 시 `manifest.lua`·`verify_spec_status.py` 갱신 및 `tools/verify_manifest_sync.py` `DEFERRED_SUBSYSTEM_DIRS` 면제 해제 필요)
  - **[동결 결정 주석 — `TASK-013` Q4 방안 B (2026-11-14)]**: `src/1_control/asa/**` 및 `tests/1_control/asa/**`는 `TASK-105` 본 구현 재개 시까지 현행 골격(`0 diff`)으로 동결 유지함 (송신 측 `VAS` `actuator_adapter_asa.lua`·`core_daemon.lua`는 `[-1.0, +1.0]` / `[0.0, 1.0]` 정규화·`dynamicPressureFactor`·`VAS §9.5` 키로 선행 정렬 완료). `TASK-105` 재개 시 아래 **5대 골격 결함 (`FLT-HIGH-12`)**을 필수로 함께 수정해야 함:
    1. `[I-10]` 정규화 입력(`[-1.0, +1.0]` / `[0.0, 1.0]`) 매핑 및 `dynamicPressureFactor` 승산 적용 (구 `0..15`/`-15..15` 직접 각도 스케일링 제거).
    2. `MSG_AERO_STATUS` 표준 필드·상태 열거형 정렬: `interactionMode`(`mode` 제거), `appliedDeflection`(`appliedDeg` 제거), `"NOMINAL" | "DEGRADED" | "TOTAL_LOSS"`(`"API_NOMINAL"`/`"API_TOTAL_LOSS"` 제거) 및 페일세이프 문자열 `"SAFE_GLIDE_TRIM"` 정렬(`"SAFE_GLIDE"`·`elevator=0.1` 하드코딩 제거).
    3. `[I-4]` 격납고 프로파일링 핸드셰이크 정렬: `MSG_CALIB_BAY_BIND`(`baseHangarChannel`), `MSG_ACTUATOR_DISCOVER_REQ/ACK`(`Base_hangar+3`, `targetGroup`), `MSG_PROFILE_SYNC.discoveredSurfaces` 객체 맵 및 표준 조종면 코드 `"RUDD"`(`"RUDDER"` 제거).
    4. `[I-9]` 4계층 재바인딩 Option A 정렬: `MSG_CHANNEL_REBIND` / `MSG_CHANNEL_REBIND_ACK`(`transactionId`, `action`, `oldBaseChannel`, `newBaseChannel`, `500ms` 워치독, `"READY"`/`"COMMITTED"`/`"ROLLED_BACK"`/`"FAILED"`).
    5. `ASA §3.2` 설정 스키마 정합화: `schemaVersion` vs `version` 단일화, `ver == "1.9.5"` 및 `domainId` 검증 복원, `s.ELEV or s.elevator` 등 듀얼키 폴백(Zero-Fallback) 제거.
- [ ] **[연기] TASK-108: Tower ATC (Sector 0, `CH 50001/50002`) 광역 항공교통 관제 노드 구현**
  - **사양서 상태**: 별도 사양서 미작성 (마스터 ICD `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.31.0 Approved) Interface I-5 기반 `AMM (Node 03)` 교신 규격; 착수 전 사양서 Draft → Approved 또는 ICD 연계 필요)
  - 광역 공역 진입/이탈 스케줄링 및 섹터 `GAC` 핸드오프 프로토콜 구현 (일정 연기)
- [ ] **[연기] TASK-401: PAYLOAD 계층(Zone 3) 통신 스키마 정의** (`docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.31.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.15.1 Approved), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v2.0.1 Implemented), `docs/specs/4_mission/`)
  - **상태 및 이관 사유**: 선행 우선순위 취소 및 로드맵 백로그 이관 (`TASK-204`는 `AMM v2.0.0` 기본 `ACT_PAY_BUS_CMD`/`ACT_PAY_REDSTONE`/`ACT_PAY_SET_ROI` 계약으로 독립 구현 완료; 세부 탑재체 행동은 `[로드맵: TASK-401]` `TBD`로 이관)
  - **사양서 상태**: PAYLOAD 계층 전용 사양서 미작성 (Draft → Approved 수립 및 마스터 ICD Interface I-11·전체 구조도·AMM 사양서 동기화 필요)
  - **배경 및 목적**: 현행 마스터 ICD Interface I-11(`Base+20~29`, Zone 3 탑재체 버스)에는 `MSG_PAYLOAD_REQ`/`MSG_PAYLOAD_ACK` 기본 예시 패킷만 정의되어 있으며, 전체 구조도의 세부 채널 구분(`Base+20` `CH_PAYLOAD_BUS`, `Base+21` `CH_WEAPON_BUS`, `Base+22~29` 예비) 및 다양한 탑재체 노드(화물 투하, 마그넷 래치, 엄빌리컬 급유/충전, `CC:Radars`/터렛 무장 제어 등) 간 표준 통신 계약이 미비함. 탐색/기능 등록(Discovery & Capability), 상태/헬스 텔레메트리, 명령·응답(`ACK`/`NACK`)·오류 코드, 안전 인터록 및 채널 오프셋 배분 규칙을 포함한 PAYLOAD 계층 표준 통신 스키마를 정의함
  - **주요 작업**:
    - [ ] **TASK-401-1**: 세부 탑재체 표준 행동군(`ACT_PAY_*` 하위 `[로드맵: TASK-401]` `TBD` 항목: 화물 투하 `CARGO_DROP`, `CC:Radars` 무장 사격 `FIRE_CTRL`, `geoScanner` 주기 스캔 등) 및 Zone 3 채널(`Base+20~29`)·안전 인터록 스키마 확정 (`docs/superpowers/specs/2026-11-12-task-204-action-primitive-design.md` §3.6 연계)

### 🔭 Phase 3 백로그 (Phase 3 Backlog)

- [ ] **[연기] TASK-301: 물리 하드웨어 기반 ACRO 수동 급기동 조종 인터페이스 개발**
  - Create/Avionics 아날로그 스틱 및 물리 컨트롤러 하드웨어 연동 (일정 연기)
  - `Base+1` 20Hz 직접 3축 각속도(`RATE_COMMAND`) 직결 스트림 및 비행 제어 코어(VAS) 선점 제어 연동

---

## ✅ 3. 완료된 작업 이력 (Completed Tasks Archive — 최근 10개 요약; 상세 결정·검증 원문은 `.agent/memory/workspace-root.md`)

- [x] **TASK-402: AMM WebUI 단일 파일 미션 에디터(`tools/amm_mission_editor.html`) 구현, CraftOS-PC 라운드트립 검증 및 `AMM`/`에디터` 사양 `Implemented` 승격** (완료일: 2026-11-14)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-14-task-402-amm-mission-editor.md`
  - **핵심 성과**: `AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.3.1 Implemented`) 기준 오프라인 단일 HTML5/CSS/JS 에디터(9 IIFE 모듈, 36+22 `ACT_*`·6+1 `DEC_*`·3+2 `MAC_*`·19종 `preconditions`·14종 조건·4종 훅·2D 전술 캔버스·`#altProfilePane`·50단 Undo/Redo·Raw JSON 드로어·`localStorage` 자동저장) 구현 및 Web Interface Guidelines 준수 정적/DOM-shim 감사 완료.
  - **승격·검증**: `AMM_PROGRAM_SPECIFICATION.md` (`v2.0.1 Implemented`)·`AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.3.1 Implemented`) 승격(`11 Implemented, 5 Approved`), `test_amm_mission_editor.py` `17/17 PASS`(CraftOS-PC `mission_engine.validate_mission` 라운드트립 포함), 단위 `504/504 PASS`, E2E `13/13 PASS`.

- [x] **TASK-013: 전사 사양서·코드베이스·하네스 전수 감사(43건 교정), Wave 1~3 통합 정렬 및 8종 사양서 `Implemented` 승격** (완료일: 2026-11-14)
  - **핵심 성과**: Q1~Q8+Q3-1 확정안에 따라 Wave 1(16종 사양서+`TASK-124` 설계서 동기화), Wave 2(`alignment`·`installer`·`gps`·`gac`·`gcs`·`landing_pad`·`vas`·`tca`·`fcp`·`amm`·`static_guard.py`·`sync_gdrive.py` 교정, 고립 모듈 6종 삭제, `asa/` `0 diff` 동결), Wave 3(독립 교차 검증 및 8종 사양서 `Implemented` 승격, `TASK-105` `FLT-HIGH-12`·`TASK-501` 이관) 완수 (`TASK-013-1~4`).
  - **승격·검증**: `ALIGNMENT v2.7.0`, `GPS v2.3.3`, `GAC v1.5.0`, `GCS v1.1.0`, `LANDING_PAD v2.5.0`, `VAS v1.20.0`, `TCA v1.12.0`, `FCP v2.1.0` `Implemented` (`INSTALLER v1.1.1 Implemented`, 코어 15종 + 에디터 `v0.3.1 Approved`); 단위 `504/504 PASS`, E2E `13/13 PASS`, 돌연변이 `25/25 KILLED`, 하네스 `88/88 PASS`, Lua 5.2 `117/117 PASS`, 매니페스트·사양서 `0 Errors, 0 Warnings`.

- [x] **TASK-204: AMM v2.0.0 표준 행동 리스트(`ACT_*`/`DEC_*`/`MAC_*`) 재정의, 진입조건 및 채터링 방지 가드 통합** (완료일: 2026-11-14, 커밋 `c331c4b`)
  - **설계 기준**: `docs/superpowers/specs/2026-11-12-task-204-action-primitive-design.md`, `docs/superpowers/specs/2026-11-13-task-204-chattering-prevention-design.md`
  - **핵심 성과**: 구 13종 체크포인트/`items[]` Zero-Fallback 폐기, `action_registry.lua`(36+22종 `ACT_*`·6+1종 `DEC_*`·3+2종 `MAC_*`·4대 진입조건)·`chattering_guard.lua`(방안 A)·`amm_config.json` `safety.chattering` 통합 및 `AMM` (`v2.0.0 Approved`) 사양 동기화 (`TASK-204-1~5`; 당시 단위 `469/469 PASS`, E2E `12/12 PASS`, 돌연변이 `25/25 KILLED`).

- [x] **TASK-123: GPS 고부하 경합·위상 버스트·모뎀 채널 오염 결함 수정** (완료일: 2026-11-14, 커밋 `e9fdce4`)
  - **핵심 성과**: `session_scheduler.lua` 선제 세션 대체/HWM 역전 가드, `client_core.lua` 단조 시퀀스 필터, `landing_pad`/`amm` 틱 위상 분산, `landing_pad/main.lua` `CH 60001` 수신 개방 제거 및 `GPS` (`v2.3.2`)·`LANDING_PAD` (`v2.4.4`) 동기화 (`TASK-123-1~5`).

- [x] **TASK-124: `TASK-204` 착수 전 채터링 방지 규칙 문서 인게임/코드베이스 정합 개정 및 설계서 동기화** (완료일: 2026-11-13, 커밋 `f2e7b10`, `b85677c`)
  - **핵심 성과**: `docs/superpowers/specs/2026-11-13-task-204-chattering-prevention-design.md` 신설(방안 A 중앙 가드·`step_20hz_tick`/`now_ms` 이원화·`N_settle`) 및 `2026-11-12` 설계서 연료 임계값(`0.20`/`0.10`) 역통일 (`TASK-124-1~2`).

- [x] **TASK-209: VAS v1.19.0 `QUATERNION_RATE` 내루프 정규화 및 ACRO/페일세이프 정합화** (완료일: 2026-11-13, 커밋 `3c82f7f`, `83ff1f6`, `244c940`, `7b19207`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-12-task-207-208-209-sequential-plan.md`
  - **핵심 성과**: `Base+1` `QUATERNION_RATE` Zero-Fallback 단일화, 정상 비행 `compute_climb_wrench` 제거(`FAILSAFE_HOLD` 격리), `E_STOP > MFD_ACRO > FCP` 선점 중재 및 `VAS` (`v1.19.0 Implemented`) 승격 (당시 Scenario 8 `4/4 PASS`, 단위 `455/455 PASS`).

- [x] **TASK-208: FCP v2.0.0 SE(3) 외루프 제어기 경량화 전면 개편** (완료일: 2026-11-13, 커밋 `26d8365`..`319d659`, `244c940`, `7b19207`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-12-task-207-208-209-sequential-plan.md`
  - **핵심 성과**: 단일 `top` 모뎀 3채널(`Base+4/+2/+1`) 온보드 `SE(3)` 외루프(6상태 FSM, 6기종 투영) 경량화, 레거시 14개 파일 제거 및 `FCP` (`v2.0.0 Implemented`) 승격.

- [x] **TASK-207: AMM v1.3.0 외부 게이트웨이·항법 융합·20Hz 궤적 생성기 구현** (완료일: 2026-11-13, 커밋 `52dc141`..`bd1539c`, `244c940`, `7b19207`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-12-task-207-208-209-sequential-plan.md`
  - **핵심 성과**: 듀얼 모뎀·`channel_sentinel.lua`·`nav_engine.lua`(GPS+DR $\alpha=0.35$)·`facility_client.lua`·`trajectory_generator.lua`(11모드)·`Base+4` `[I-12]` 및 20Hz/5Hz 코루틴 분리 구현.

- [x] **TASK-202: UAFS 통합 미션 시퀀서 엔진, AMM 조종석 단말 및 WebUI 에디터 사양 수립 (구 TASK-201[AMP 초안] + 203 통합)** (완료일: 2026-11-12)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-11-task-202-{2,3,4}-*.md`, `docs/superpowers/plans/2026-11-12-task-202-5-amm-webui-editor-spec.md`
  - **핵심 성과**: 3분할 미션 코어(`mission_engine`, `condition_evaluator`, `hook_runner`), Zone 3 버스, 51x19 뷰포트, `resolve_path`·`file_transfer`·CLI 및 WebUI 에디터 초안(`AMM_MISSION_EDITOR_SPECIFICATION.md` 당시 `v0.1.0 Draft`) 수립 (`TASK-202-1~5`).

- [x] **TASK-206: FCP 외루프 경량화 및 AMM 상위 계층 이관을 위한 15대 사양서 전면 개편** (완료일: 2026-11-12)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-11-fcp-amm-role-refactor-specs.md`
  - **핵심 성과**: Spec-First 4계층 책임 분리(`AMM` 외부 게이트웨이·항법·궤적 / `FCP` `SE(3)` / `VAS` `SO(3)`), `Base+4` `[I-12]` 신설, `[I-2]`/`[I-10]` 단일화 및 잔존 결함 일괄 정정 (`TASK-206-1~8`).
