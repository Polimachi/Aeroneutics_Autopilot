# Create_Aeroneutics — Task Management & Implementation Roadmap

> **문서 상태**: 활성 (Living Roadmap)  
> **최종 갱신일**: 2026-11-16  
> **현재 단계**: **Phase 1 & 2** (직전 완료: TASK-403, TASK-103, TASK-404, TASK-501 / 활성 대기: TASK-125, 302, 015, 128, 132, 129, 105, 210)

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

> **권장 실행 우선순위**: **1순위** `TASK-125` (40채널 블록 개편·경합·검증 결함 12종 해소) → **2순위** `TASK-302` (포켓 PDA 원격 관제·E_STOP 단말) · `TASK-015` (전 계층 모듈·신규 프로그램 통합 플레이북 체계) → **3순위** `TASK-128` (GPS 헬스 감시·DR 블렌딩 가드) · `TASK-132` (추력 상실 비상 활공·오토로테이션 가드) · `TASK-129` (적응형 트림 보정) · `TASK-105` ↔ `TASK-210` (ASA 본 구현 및 실노드 연동 연계) / **로드맵(연기)** `TASK-401`

- [ ] **TASK-125: [1순위 / 프로토콜·아키텍처] 비행체 40채널 블록 사용 채널 개편 및 프로토콜·경합·검증 결함 12종 해소** (`docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.34.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.18.0 Approved), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v2.3.0 Implemented), `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (현재 v1.22.0 Implemented), `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (현재 v2.2.0 Implemented), `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` (현재 v1.2.0 Implemented), `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (현재 v2.7.1 Implemented))
  - **권장 착수 순위**: **1순위** (`TASK-117` 완료 후 최우선; `TASK-302` Pocket PDA 비상 단말 및 `TASK-015` 통합 플레이북 작성 전 채널 체계 정립을 위해 선행 권장)
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
    - [ ] **TASK-125-13**: 전사 사양서·계약 SSOT 동기화 및 가드레일·하네스 검증 — 마스터 ICD, 전체 구조도, 연관 5대 사양서 및 `config/protocol_contracts.json` 개정 후 `verify_all_specs.py`, `verify_spec_status.py`, `verify_contracts.py`, `verify_runtime_wiring.py`, `run_boot_smoke.py`, 단위/E2E 테스트 검증 및 컨텍스트 동기화

- [ ] **TASK-302: [2순위 / 현장 운용 HMI] CC:Tweaked 포켓 컴퓨터(Pocket PDA) 휴대용 원격 관제·지상 콘솔 링크·비상 E_STOP 단말** (`src/0_infra/pocket_pda/`)
  - **권장 착수 순위**: **2순위** (선행 `TASK-120` 완료 — FDR 동적 바인딩·원격 덤프 트리거 연동 가능)
  - **배경 및 필요성**: 인게임 시험 비행·정비 중 기체 이상 진동이나 경로 이탈 시 고정형 GCS·Alignment·FDR 콘솔까지 이동할 시간적 여유가 없음. 플레이어가 인벤토리에서 꺼내 즉시 기체 비상 제어뿐 아니라 `Alignment`, `FDR` 등 지상/온보드 시스템과의 무선 링크(기체 바인딩·세션 제어)까지 수행할 수 있는 무선 휴대 단말(`src/0_infra/pocket_pda/`)이 필요함.
  - **주요 작업**:
    - [ ] **TASK-302-1**: Pocket Computer 전용 경량 TUI 구현 — 소형 화면(26×20)에 최적화된 기체 선택기, 고도·속도·자세·연료 HUD, 링크 품질(RSSI/거리) 및 연결 대상(`Alignment`/`FDR`/`GCS`/`AMM`) 상태 표시
    - [ ] **TASK-302-2**: 원격 비상 제어 및 FDR 연동 — 단일 키 입력으로 무선 `E_STOP` 송출 + `TASK-120` 블랙박스 로그 즉시 JSONL 덤프 트리거, `HOLD` / `RTB` / `LAND_NEAREST` 단축 명령 지원
    - [ ] **TASK-302-3**: `Alignment`·`FDR` 등 원격 링크 및 세션 제어 연동 — Pocket PDA에서 기체 인덱스 $N$을 지정해 `Alignment`(격납고 베이 바인딩·교정 세션 개시/중단/해제)·`FDR`(`STANDBY`↔`LOGGING` 동적 기체 $N$ 바인딩 전환·로그 반출 트리거) 등 주요 노드 간 원격 링크·해제 수행 지원
    - [ ] **TASK-302-4**: 사양서/계약 및 배포·가드레일 통합 — Pocket PDA 사양서(`Draft` → `Approved` → `Implemented`), `config/protocol_contracts.json`, `manifest.lua`, `config/gdrive_mapping.json`, `tools/run_boot_smoke.py` 등록 및 `verify_contracts.py`·`verify_runtime_wiring.py`·단위/E2E 검증 완료

- [ ] **TASK-015: [2순위 / 운용 매뉴얼] 전 계층 코드베이스·신규 추가 모듈/프로그램 통합 플레이북 체계 구축 (`TASK-010` + `TASK-011` 통합 확장)** (`playbook/README.md`, `tools/verify_playbooks.py`, `playbook/0_development/{alignment,fdr,installer,ota,sensors}.md`, `playbook/0_infra/{gps,gcs,gac,landing_pad}.md`, `playbook/1_control/{vas,tca}.md`, `playbook/2_guidance/fcp.md`, `playbook/3_planning/{amm,amm_mission_editor}.md`)
  - **권장 착수 순위**: **2순위** (선행 `TASK-125` 40채널 블록 개편·`TASK-403` World Preset·`TASK-404` GCS Live Bridge 완료 후 현행 스펙 일괄 반영 권장)
  - **기존 계획서 참조**: `docs/superpowers/plans/2026-11-08-task-010-playbook-framework.md` (기존 `TASK-010`·`TASK-011`을 단일 과제 `TASK-015`로 통합하고, 이후 추가된 `installer`·`ota`·`sensors`·`gcs_live_bridge` 등 신규 모듈·프로그램까지 포함하도록 확장)
  - **배경 및 목적**: 기존 `TASK-010`(핵심 5종: `GPS`, `VAS`, `TCA`, `FCP`, `AMM`)과 `TASK-011`(2차 확장 6종: `Alignment`, `GCS`, `GAC`, `Landing Pad`, `Mission Editor`, `FDR`/분석기)으로 이원화되어 있던 플레이북 과제를 단일 체계로 통합하고, 이후 구현 완료·추가된 신규 모듈 및 프로그램(`installer`, `ota` 무선 배포·2단계 부트 워치독, `sensors` 공용 센서 라이브러리, `TASK-403`/`404` 에디터 World Preset·`tools/gcs_live_bridge.py` 등)까지 누락 없이 인게임 실전 운용 매뉴얼로 구축함.
  - **주요 작업**:
    - [ ] **TASK-015-1**: 플레이북 프레임워크 및 정적 검증 도구 구축 (`tools/verify_playbooks.py`, `playbook/README.md`) — 표준 7대 섹션 템플릿, 전체 인가 파일 목록(활성 12 서브시스템 + 공용 센서 + 에디터/브리지/분석기 + 추후 `TASK-302` Pocket PDA 등 확장 슬롯), 미인가 파일 생성 차단 및 링크/섹션 정적 검증기 구현
    - [ ] **TASK-015-2**: 개발·배포·진단 도메인 플레이북 작성 (`playbook/0_development/{alignment,fdr,installer,ota,sensors}.md`) — 격납고 동역학 캘리브레이션(`Alignment`), 지상 블랙박스 `FDR`·다중 디스크 VFS·`tools/analyze_flight_log.py` 오프라인 프로파일러(`TASK-120`), 통합 인스톨러(`installer.lua`·`manifest.lua`·GitHub/GDrive 이중 배포), 무선 OTA 서버·`/lib/ota_agent.lua`·2단계 부트 워치독 롤백(`TASK-117`), `avionics_sensors` 공용 센서 부착·배선 가이드 작성
    - [ ] **TASK-015-3**: 인프라 도메인 플레이북 작성 (`playbook/0_infra/{gps,gcs,gac,landing_pad}.md`) — GPS 위성군 구축(`GPS`), 중앙 지상 관제소 및 Live Bridge 연동(`GCS` + `TASK-404` `tools/gcs_live_bridge.py` GAC/시설물 자동 수집), 섹터 관제·전용 패드/징발(`GAC`), 착륙패드(`Landing Pad`) 운용 매뉴얼 작성 (`TASK-302` `pocket_pda` 구현 시 `pocket_pda.md` 연동 확장)
    - [ ] **TASK-015-4**: 온보드 제어·유도 도메인 플레이북 작성 (`playbook/1_control/{vas,tca}.md`, `playbook/2_guidance/fcp.md`) — `VAS`(`QUATERNION_RATE`·`Base+3` `MFD_ACRO`·`system.json`·`telemetryDiag`·`TASK-125` 채널 개편(비상·교정 채널 분리)), `TCA`(짐벌/벡터 추력기·진단), `FCP`(3채널 순수 `SE(3)` 외루프) 실전 세팅·튜닝 매뉴얼 작성
    - [ ] **TASK-015-5**: 임무 계획·WebUI 에디터 플레이북 작성 (`playbook/3_planning/{amm,amm_mission_editor}.md`) — `AMM`(듀얼 모뎀·`nav_engine`·`trajectory_generator`·`ACT_*`/`DEC_*`/`MAC_*` 3계층 시퀀서·`chattering_guard`·`ACT_TKL_LAND_NEAREST`) 및 오프라인 WebUI 에디터(`tools/amm_mission_editor.html`, `TASK-403` World Preset·`TASK-404` Live Mode/원클릭 무선 푸시 포함) 양방향 워크플로우 작성
    - [ ] **TASK-015-6**: 프로젝트 규칙·컨텍스트 동기화 및 전수 검증 — `playbook/README.md` 인덱스·`tools/verify_playbooks.py` 전수 PASS, `tests/harness/test_tools_integrity.py` 도구 등록 및 `verify_context_docs.py` 통과 확인

- [ ] **TASK-128: [3순위 / 항법 무결성] GPS 위성군 헬스 감시 및 청크 경계(Chunk Border) 추측 항법(DR) 블렌딩 가드** (`src/0_infra/gps/`, `src/1_control/vas/`, `src/2_guidance/fcp/`, `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`, `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`, `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`, `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`, `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`)
  - **권장 착수 순위**: **3순위** (항법 안전성 핵심 과제, 착수 시 Spec-First 사양 개정 선행)
  - **사양서 상태**: 개정 대기 (`GPS v2.3.3`, `VAS v1.22.0`, `FCP v2.2.0` Implemented → Approved 전이 필요)
  - **배경 및 필요성**: 마인크래프트 멀티플레이어 및 고속 비행 환경에서는 청크 로딩 지연이나 지형 차폐로 `gps.locate()`가 순간적으로 `nil`을 반환하거나 삼각측량 오차가 급등함. 이때 위치 값이 튀면 FCP 외루프가 급격한 속도·자세 명령을 생성하여 기체가 추락함.
  - **주요 작업**:
    - [ ] **TASK-128-1**: GPS 노드 수신 품질 진단 지표(HDOP 근사치, 응답 위성 수, 연속 실패 카운터) 산출 및 `MSG_NAV_QUALITY` 상태 플래그 정의 (`src/0_infra/gps/`, 연관 사양서 및 `config/protocol_contracts.json`)
    - [ ] **TASK-128-2**: VAS/FCP 단기 관성·속도 적분 기반 추측 항법(Dead-Reckoning) 홀드오버(Hold-over, 최대 1.5초) 및 임계 시간 초과 시 자동 `HOLD_LEVEL` 안전 전환 구현 (`src/1_control/vas/`, `src/2_guidance/fcp/` 및 연관 사양서)
    - [ ] **TASK-128-3**: 전사 사양서 동기화, 모의 청크 차폐/지연 E2E 및 `verify_contracts.py`·`verify_runtime_wiring.py`·`run_boot_smoke.py` 검증 완료 후 사양서 `Implemented` 승격

- [ ] **TASK-132: [3순위 / 비상 비행 제어] 추력 상실·대파(Battle Damage) 시 비상 활공(Best-Glide) 및 오토로테이션 가드** (`src/1_control/vas/`, `src/2_guidance/fcp/`, `src/3_planning/amm/`)
  - **권장 착수 순위**: **3순위** (비상 비행 제어 핵심 과제, 착수 시 Spec-First 사양 개정 선행)
  - **사양서 상태**: 개정 대기 (`VAS v1.22.0`, `FCP v2.2.0`, `AMM v2.1.0` Implemented → Approved 전이 필요)
  - **대상 사양서**: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (현재 v1.22.0 Implemented), `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (현재 v2.2.0 Implemented), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v2.3.0 Implemented)
  - **배경 및 필요성**: Create: Aeronautics / Create: Big Cannons 운용 환경에서 엔진 피격, 회전력(SU) 과부하, 또는 다수 추진기 TOTAL_LOSS로 총 가용 추력이 기체 중량을 지탱하지 못할 때(availableThrust < weight), 기존 호버/고도 유지 루프는 기수를 과도하게 들어 올려 실속(Stall)·스핀 추락을 유발함.
  - **주요 작업**:
    - [ ] **TASK-132-1**: VAS 실시간 추력 여유도 감시기 구현 — TCA 상태 피드백 합산 추력이 임계치 미만으로 하락 시 `POWER_LOSS_EMERGENCY` 상태 전이
    - [ ] **TASK-132-2**: 고정익·하이브리드 기체용 최적 활공각(Best-Glide Pitch) 및 최소 침하율 속도 유지 제어 법칙(`MAC_EMERGENCY_GLIDE`)과 AMM의 전방 개활지/최인접 패드 비상 활공 경로 생성 연동
    - [ ] **TASK-132-3**: 전사 사양서·`config/protocol_contracts.json` 동기화, 추력 상실 E2E 및 3대 가드레일(`verify_contracts.py`·`verify_runtime_wiring.py`·`run_boot_smoke.py`) 검증 후 사양서 `Implemented` 승격

- [ ] **TASK-129: [3순위 / 적응형 비행 제어] 비행 중 질량·무게중심(CoG) 변화 및 구동기 열화 대응 실시간 트림 보정기** (`src/1_control/vas/`, `src/1_control/tca/`, `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`, `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md`)
  - **권장 착수 순위**: **3순위** (Spec-First 절차상 `VAS`·`TCA` 사양서 `Approved` 개정 선행)
  - **사양서 상태**: 추후 착수 시점 개정 예정 (현재 `VAS v1.22.0 Implemented`, `TCA v1.13.0 Implemented` → 착수 시점 Spec-First `Approved` 개정 및 연동)
  - **배경 및 필요성**: Alignment(v2.7.1)는 격납고 정지 상태의 관성 텐서만 측정하므로, 비행 중 화물 투하(TASK-401), 연료 소모, 또는 특정 추진기/조종면의 DEGRADED 판정 시 피치·롤 정적 불균형과 적분항 와인드업(Wind-up)이 발생함.
  - **주요 작업**:
    - [ ] **TASK-129-1**: VAS 수평 정속 비행 구간 감지 및 지속 편향 PID 적분항을 정적 트림 오프셋으로 이관하는 적응형 트림 학습기(Adaptive Trim Estimator) 구현 (비정상 급기동 시 학습 동결 가드 포함)
    - [ ] **TASK-129-2**: TCA 구동기 상태(DEGRADED / TOTAL_LOSS) 피드백 수신 시 잔여 정상 추진기의 추력 배분 행렬(Control Allocation Matrix) 실시간 재가중치 계산

- [ ] **TASK-105: [3순위 / 공력 구동기] ASA (Aerodynamic Surface Adapter) 공력 조종면·플랩 분산 구동기 본 구현 완성** (`docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (현재 v1.8.0 Approved), `src/1_control/asa/`, `tests/1_control/asa/`)
  - **권장 착수 순위**: **3순위** (`TASK-210` 연계 동시 배치·병행 수행)
  - **사양서 상태**: `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (현재 v1.8.0 Approved)
  - TASK-113의 기본 프레임워크(헤드리스/비동기 TUI, `Base+11` 수신 루프, 300ms Safe Glide Trim, 단위 테스트 15/15 PASS)를 기반으로 물리 액추에이터(Avionics API/RS) 각도 인가, `MSG_AERO_STATUS` 상태 피드백 송출 및 `MSG_ACTUATOR_DISCOVER_REQ/ACK` 핸드셰이크 완성 (`TASK-210` 연계; 3순위 편입 — 착수 시 `manifest.lua`·`verify_spec_status.py` 갱신 및 `tools/verify_manifest_sync.py` `DEFERRED_SUBSYSTEM_DIRS`·`config/protocol_contracts.json` `deferredSubsystems`·`tools/run_boot_smoke.py` `deferred` 면제 해제 필요)
  - **[동결 결정 주석 — `TASK-013` Q4 방안 B (2026-11-14)]**: `src/1_control/asa/**` 및 `tests/1_control/asa/**`는 `TASK-105` 본 구현 착수 시점까지 현행 골격(`0 diff`)으로 동결 유지 후, 착수 시 아래 **5대 골격 결함 (`FLT-HIGH-12`)**을 필수로 함께 수정해야 함:
    1. `[I-10]` 정규화 입력(`[-1.0, +1.0]` / `[0.0, 1.0]`) 매핑 및 `dynamicPressureFactor` 승산 적용 (구 `0..15`/`-15..15` 직접 각도 스케일링 제거).
    2. `MSG_AERO_STATUS` 표준 필드·상태 열거형 정렬: `interactionMode`(`mode` 제거), `appliedDeflection`(`appliedDeg` 제거), `"NOMINAL" | "DEGRADED" | "TOTAL_LOSS"`(`"API_NOMINAL"`/`"API_TOTAL_LOSS"` 제거) 및 페일세이프 문자열 `"SAFE_GLIDE_TRIM"` 정렬(`"SAFE_GLIDE"`·`elevator=0.1` 하드코딩 제거).
    3. `[I-4]` 격납고 프로파일링 핸드셰이크 정렬: `MSG_CALIB_BAY_BIND`(`baseHangarChannel`), `MSG_ACTUATOR_DISCOVER_REQ/ACK`(`Base_hangar+3`, `targetGroup`), `MSG_PROFILE_SYNC.discoveredSurfaces` 객체 맵 및 표준 조종면 코드 `"RUDD"`(`"RUDDER"` 제거).
    4. `[I-9]` 4계층 재바인딩 Option A 정렬: `MSG_CHANNEL_REBIND` / `MSG_CHANNEL_REBIND_ACK`(`transactionId`, `action`, `oldBaseChannel`, `newBaseChannel`, `500ms` 워치독, `"READY"`/`"COMMITTED"`/`"ROLLED_BACK"`/`"FAILED"`).
    5. `ASA §3.2` 설정 스키마 정합화: `schemaVersion` vs `version` 단일화, `ver == "1.9.5"` 및 `domainId` 검증 복원, `s.ELEV or s.elevator` 등 듀얼키 폴백(Zero-Fallback) 제거.

- [ ] **TASK-210: [3순위 / 연계 · ASA 실노드 연동] ASA v1.8.0 구현 정합화 및 VAS·Alignment 실노드 연동 검증 (`MSG_AERO_*` · `MSG_SURFACE_DISCOVER_*` · 4계층 재바인딩 반영)** (`docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (현재 v1.8.0 Approved), `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (현재 v1.13.0 Implemented), `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (현재 v2.7.1 Implemented), `src/1_control/asa/`)
  - **권장 착수 순위**: **3순위** (`TASK-105` 연계 TASK — 3순위 섹션 동시 배치·병행 수행)
  - **선행·연계 의존성**:
    - **기완료 기반 (`TASK-206`·`TASK-207`·`TASK-208`·`TASK-209`·`TASK-013` 완료)**: `VAS v1.20.0` (당시 기준, 현행 `v1.22.0 Implemented`; `actuator_adapter_asa.lua`·`Base+11` 송신단), `TCA v1.12.0` (당시 기준, 현행 `v1.13.0 Implemented`; `Option A` 재바인딩·`Base_hangar+3` 탐색), `ALIGNMENT v2.7.0` (당시 기준, 현행 `v2.7.1 Implemented`; `discovery_client.lua` `MSG_SURFACE_DISCOVER_REQ/ACK`·`profile_exporter.lua`) 정합화 및 1차 E2E(`244c940`) 완료.
    - **연계 TASK (`TASK-105`)**: **`TASK-105` (ASA 본 구현 및 `FLT-HIGH-12` 5대 골격 결함 해소)** — `TASK-013` Q4 방안 B에 따라 `src/1_control/asa/**`·`tests/1_control/asa/**`가 동결(`0 diff`)되어 있으므로, 3순위 `TASK-105` 착수 시 본 과제를 연계·병행 수행함.
  - **배경 및 목적**: ① **[기반 완료]** `TCA`·`Alignment`·`VAS`(`actuator_adapter_asa.lua` 송신단·`Base+11`) 1차 E2E(`244c940`) 및 `TASK-013` 정합화 완료. ② **[잔여 범위 — `TASK-105` 연계 수행]** 동결 중인 `ASA` 본 구현과 함께 `TASK-105`의 `FLT-HIGH-12` 5대 결함을 해소하고, 다중 노드 E2E(`AMM ↔ FCP ↔ VAS ↔ ASA ↔ Alignment`) 검증 후 `ASA` 사양서를 `Implemented`로 승격함.

---

## 📋 2. 예정 백로그 (Planned Backlog — Phase 1 & 2)

### ⏸️ 연기·보류 과제 (Deferred / On-Hold)

- [ ] **[연기] TASK-104: Docking Arm 결합 암 제어기 구현** (`src/0_infra/docking_arm/`)
  - **사양서 상태**: `docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md` (v1.12.0 Approved)
  - 2축 로봇 암 포획·인입 및 엄빌리컬 보급 시퀀스 (`AMM (Node 03)` 주도 4단계 랑데부 연동; 일정 연기 — 사양서 `Approved` 유지, 구현 시 `manifest.lua`·`verify_spec_status.py`·`config/protocol_contracts.json`·`tools/run_boot_smoke.py` 등록 및 `verify_contracts.py`·`verify_runtime_wiring.py` 검증 필요)
- [ ] **[연기] TASK-108: Tower ATC (Sector 0, `CH 50001/50002`) 광역 항공교통 관제 노드 구현**
  - **사양서 상태**: 별도 사양서 미작성 (마스터 ICD `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.34.0 Approved) Interface I-5 기반 `AMM (Node 03)` 교신 규격; 착수 전 사양서 Draft → Approved 또는 ICD 연계 필요)
  - 광역 공역 진입/이탈 스케줄링 및 섹터 `GAC` 핸드오프 프로토콜 구현 (일정 연기)
- [ ] **[연기] TASK-401: PAYLOAD 계층(Zone 3) 통신 스키마 정의** (`docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.34.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.18.0 Approved), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v2.3.0 Implemented), `docs/specs/4_mission/`)
  - **상태 및 이관 사유**: 선행 우선순위 취소 및 로드맵 백로그 이관 (`TASK-204`는 `AMM v2.0.0` 기본 `ACT_PAY_BUS_CMD`/`ACT_PAY_REDSTONE`/`ACT_PAY_SET_ROI` 계약으로 독립 구현 완료; 세부 탑재체 행동은 `[로드맵: TASK-401]` `TBD`로 이관)
  - **사양서 상태**: PAYLOAD 계층 전용 사양서 미작성 (Draft → Approved 수립 및 마스터 ICD Interface I-11·전체 구조도·AMM 사양서 동기화 필요)
  - **배경 및 목적**: 현행 마스터 ICD Interface I-11(`Base+20~29`, Zone 3 탑재체 버스)에는 `MSG_PAYLOAD_REQ`/`MSG_PAYLOAD_ACK` 기본 예시 패킷만 정의되어 있으며, 전체 구조도의 세부 채널 구분(`Base+20` `CH_PAYLOAD_BUS`, `Base+21` `CH_WEAPON_BUS`, `Base+22~29` 예비) 및 다양한 탑재체 노드(화물 투하, 마그넷 래치, 엄빌리컬 급유/충전, `CC:Radars`/터렛 무장 제어 등) 간 표준 통신 계약이 미비함. 탐색/기능 등록(Discovery & Capability), 상태/헬스 텔레메트리, 명령·응답(`ACK`/`NACK`)·오류 코드, 안전 인터록 및 채널 오프셋 배분 규칙을 포함한 PAYLOAD 계층 표준 통신 스키마를 정의함
  - **주요 작업**:
    - [ ] **TASK-401-1**: 세부 탑재체 표준 행동군(`ACT_PAY_*` 하위 `[로드맵: TASK-401]` `TBD` 항목: 화물 투하 `CARGO_DROP`, `CC:Radars` 무장 사격 `FIRE_CTRL`, `geoScanner` 주기 스캔 등) 및 Zone 3 채널(`Base+20~29`)·안전 인터록 스키마 확정 (`docs/superpowers/specs/2026-11-12-task-204-action-primitive-design.md` §3.6 연계)

### 🔭 Phase 3 백로그 (Phase 3 Backlog)

- [ ] **[연기] TASK-301: 물리 하드웨어 기반 ACRO 수동 급기동 조종 인터페이스 개발**
  - Create/Avionics 아날로그 스틱 및 물리 컨트롤러 하드웨어 연동 (일정 연기)
  - `Base+1` 20Hz 직접 3축 각속도(`RATE_COMMAND`) 직결 스트림 및 비행 제어 코어(VAS) 선점 제어 연동

### 🧩 애드온 확장 백로그 (Addon Integration Backlog)

- [ ] **TASK-901: 신규 애드온 통합 물리 센서 구현 및 온보드 항전(`avionics_sensors`·`VAS`) 연동** (`src/0_development/sensors/`, `src/1_control/vas/modules/sensor_pipeline.lua`)
  - **배경 및 제약**: 기존 CC:Avionics 다중 센서(`gimbal`·`altitude`·`velocity`·`physics_assembler`)의 `yaw` 부재·6틱 yield·레버암 수동 설정 한계를 해소하기 위해 별도 애드온으로 단일 물리 센서를 구현하고 온보드에 통합함. 월드 절대 `X/Z` 좌표는 GPS(`CH 60001`/`Base+5`) 및 추측항법(DR) 아키텍처 유지를 위해 센서 출력에서 영구 제외함.
  - **확정·반영 사항 (2026-11-15 세션 설계)**:
    - 동적 일괄 스냅샷(`getKinematicsInfo()`)에 `dtSec`·`serverTps`, `quaternion`(`VAS` `quat.lua` 축 규약 `x=Roll, y=Pitch, z=Yaw`), `attitude`(`yaw`/`heading` 포함), `angularRates`, `dynamics`(`altitudeY`, `speed`, `groundSpeed`, `airPressure`, `velocity.world/body`, `acceleration.world/body`)를 중첩 계층까지 1:1 일치시켜 반영. 가속도는 중력·무중력 상태 감안 없이 현 기체의 최종 3축 가속도로 정의하며 `getBodyLinearAcceleration()` / `getWorldLinearAcceleration()`으로 분리.
    - **`verticalSpeed` 폴백 메모**: 본 애드온 센서 사용 시 별도 `verticalSpeed` 필드를 요구하지 않으며, 온보드 어댑터(`avionics_sensors.lua` / `sensor_pipeline.lua`)에서 자동으로 `dynamics.velocity.world.vy`로 폴백 처리함.
    - 정적 일괄 스냅샷(`getContraptionInfo()`)에 `assembled`, `mass`(`> 0.0 kg`, 미조립 시 `0.0` 하한 고정), `centerOfMass`, `inertiaTensor`, `boundsCenterOfMass`·`boundsLocalOrigin`, `sensorOffset`(`CoM -> Sensor` 벡터를 센서 `facing`=`front` 좌표계로 투영, `frame = "SENSOR_FACING"`), `subLevelId`, `subLevelName` 반영.
    - **동체 기준 공통 규약**: `attitude`, `quaternion`, `angularRates`, `dynamics.velocity.body`, `dynamics.acceleration.body`, `sensorOffset` 전부 센서 블록 `facing`=`front` 좌표계를 공통 사용하며, `dynamics.acceleration` 서브키는 `velocity`와 대칭(`world: { ax, ay, az }`, `body: { forward, vertical, lateral }`)으로 확정.
  - **주요 작업**:
    - [ ] **TASK-901-1**: 센서 API 구현 전 최종 규약 확인 — `sensorOffset` (`dx, dy, dz`) 3축 매핑과 `sensor_pipeline.lua` `compute_lever_offsets` 간 부호·축 일치 검증 및 `speed`/`groundSpeed` 파생 규칙 문서화
    - [ ] **TASK-901-2**: 마인크래프트 애드온 Java 페리페럴 구현 및 인게임 동작 검증 — 원자적 스냅샷(`getKinematicsInfo`, `getContraptionInfo`) 및 개별 fallback getter 구현
    - [ ] **TASK-901-3**: 온보드 Lua 어댑터(`src/0_development/sensors/avionics_sensors.lua`, `src/1_control/vas/modules/sensor_pipeline.lua`) 통합 및 `VAS`/`FCP`/`AMM`/`Alignment` 단위·E2E·가드레일(`verify_contracts.py`·`verify_runtime_wiring.py`·`run_boot_smoke.py`) 검증 완료

---

## ✅ 3. 완료된 작업 이력 (Completed Tasks Archive — 최근 10개 요약; 상세 결정·검증 원문은 `.agent/memory/workspace-root.md`)

- [x] **TASK-501: Google Drive 전수 패키지(135파일) 업로드·매핑 동기화 및 `--strict-gdrive-packages` 기본 게이트 활성화** (완료일: 2026-11-16)
  - **핵심 성과**: `tools/sync_gdrive.py` 패키지 원격 파일명 `<modId>__<dest_underscored>` 충돌 제거, `--max 0` 전체 목록 조회, `BOOTSTRAP_FILES`/`SHARED_LIBS`/전 15모듈 `MODULES.*.files` 전수 `--embed` 및 변경된 `manifest.lua` 재업로드, `tools/verify_manifest_sync.py` `strict_gdrive_packages=True` 기본 활성화 (`TASK-501-1~3`).
  - **검증**: `sync_gdrive.py verify --category all` (`135 mapped files PASS`), `verify_manifest_sync.py --strict-gdrive-packages` (`15 modules, 134 manifest paths, 145 source files, 135 GDrive entries, 0 Errors, 0 Warnings`), `test_gdrive_sync.py`·`test_manifest_sync_verifier.py` `15/15 PASS`.

- [x] **TASK-404: GCS WebSocket Live Bridge, GAC·시설물 기반 월드 프리셋 자동 생성 및 실시간 전술 지도·원클릭 미션 무선 푸시** (완료일: 2026-11-16)
  - **핵심 성과**: stdlib `asyncio` 로컬 RFC 6455 서버(`tools/gcs_live_bridge.py`, `ws://127.0.0.1:8765`), `GCS v1.2.0` (`live_bridge_client.lua`·`CH 50003`/`50004`·전 기체 `Base+3`/`+0` 동시 구독), `AMM v2.3.0` `MSG_MISSION_CMD` `"LOAD"` 인라인 `/missions/<id>.json` 저장·적재, `tools/amm_mission_editor.html v0.5.0` Live Mode (`WORLD_PRESET_SYNC`→`WorldStore` 병합·다중 기체 마커/궤적·`'Push to Aircraft'` 모달) 구현 (`TASK-404-1~3`).
  - **승격·검증**: `GCS v1.2.0`·`AMM v2.3.0`·`AMM_MISSION_EDITOR v0.5.0` `Implemented` 승격(`14 Implemented, 4 Approved`), `0_infra/gcs` `30/30 PASS`, `3_planning/amm` `138/138 PASS`, `test_amm_mission_editor.py` `24/24 PASS`, `test_gcs_live_bridge.py` 통과.

- [x] **TASK-103: Runway 활주로 제어기 사양 전면 검토·개정 및 10모듈 구현 (`RUNWAY v1.12.0 Implemented`)** (완료일: 2026-11-16)
  - **핵심 성과**: `RUNWAY_SPECIFICATION_AND_ICD.md`(`v1.12.0 Implemented`) 및 `config/protocol_contracts.json`(`MSG_FACILITY_STATIC_GUIDE` 선택 키, `MSG_RUNWAY_TOUCHDOWN`/`VACATED`) 동기화, `src/0_infra/runway/` 10모듈(유선 등화·클러치 우아한 성능 저하 포함) 구현, `manifest.lua` 15번 모듈 등록, `tools/run_boot_smoke.py` `getMethods` 재귀 수정 (`TASK-103-1~3`).
  - **승격·검증**: `0_infra/runway` 단위 `12/12 PASS`, E2E Scenario 6 활주로 접근·접지·롤아웃·이탈 통과(`19/19 PASS`), `0_development/installer` `44/44 PASS`, 부트 스모크 `13/13 PASS`.

- [x] **TASK-403: AMM WebUI 미션 에디터 World Preset, 시설 기반 이착륙 지정 및 `ACT_TKL_LAND_NEAREST` 추가** (완료일: 2026-11-16)
  - **설계서**: `docs/superpowers/specs/2026-11-14-task-403-world-preset-design.md`
  - **핵심 성과**: `GAC v1.6.0` `MSG_FACILITY_BEACON.facilities[]` 스냅샷 송출, `AMM v2.2.0` `ACT_TKL_LAND_NEAREST` (`37`종 활성 `ACT_*`) 및 `facility_client` 일괄 수집·최근접 무료 시설 탐색/Abort 가드, `amm_mission_editor.html v0.4.0` `WorldStore`·`#worldPresetDrawer`·4변 `(X, Z)` 눈금·핀 레이어·1클릭 시설 등록 구현 (`TASK-403-1~5`).
  - **승격·검증**: `GAC v1.6.0`·`AMM v2.2.0`·`AMM_MISSION_EDITOR v0.4.0` `Implemented` 승격, `test_amm_mission_editor.py` `23/23 PASS`, 단위 `14/14 PASS`, E2E `18/18 PASS`.

- [x] **TASK-117: 무선 OTA 배포 서버·슬레이브 에이전트(`/lib/ota_agent.lua`)·2단계 부트 워치독 구현 및 다중 노드 E2E/사양 승격 (구 TASK-117 + 119 통합)** (완료일: 2026-11-15)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-15-task-117-wireless-ota-rollback.md`
  - **핵심 성과**: `[I-13]`(`CH 105`/`106`, `ver "1.9.5"`, `0x1010`) 계약·`OTA_PROGRAM_SPECIFICATION.md`(`v0.1.0`)·6대 사양서·`config/protocol_contracts.json` 동기화, `startup_generator.lua` 2단계 부트 워치독(`/.ota_boot_pending`, `/ota_backup/` 롤백, `/.ota_rolled_back`), `src/0_development/ota/ota_agent.lua`(CRC32·`/ota_staging/<txId>/` 다중 파일 원자 교체·안전 게이트·20틱 커밋), 온보드 4계층(`VAS`/`TCA`/`FCP`/`AMM`, `asa/` `0 diff`) 연동, 격납고 OTA 서버(`src/0_development/ota/`), `manifest.lua` 14모듈 등록 및 E2E Scenario 10(`tests/e2e/test_e2e_ota_deploy_rollback.lua`) 4케이스 구현.
  - **승격·검증**: `OTA v0.1.0`, `INSTALLER v1.2.0`, `VAS v1.22.0`, `TCA v1.13.0`, `FCP v2.2.0`, `AMM v2.1.0` `Implemented` 승격(`13 Implemented, 5 Approved`); 단위 14타겟 `566/566 PASS`, E2E 10스위트 `18/18 PASS`(`517`패킷 `0` violations), 부트 스모크 `12/12 PASS`, `verify_contracts.py` `0 errors`, `verify_runtime_wiring.py` `0 violations`, `verify_all_specs.py`·`verify_manifest_sync.py` `0 Errors, 0 Warnings`, Lua 5.2 `129/129 PASS`, 돌연변이 `25/25 KILLED`, 하네스 `132/132 PASS`, 에디터 `20/20 PASS`.

- [x] **TASK-014: 전수 감사 3대 사각지대 방지 가드레일 구축 (SSOT 계약·E2E 패킷 검증·런타임 배선/실부팅 스모크)** (완료일: 2026-11-15)
  - **설계서 및 실행 계획서**: `docs/superpowers/specs/2026-11-14-audit-prevention-guardrails-design.md`, `docs/superpowers/plans/2026-11-14-task-014-audit-prevention-guardrails.md`
  - **핵심 성과**: `config/protocol_contracts.json` SSOT(`MSG_FLIGHT_TELEMETRY` 선택 진단키 포함), `tools/verify_contracts.py`, `virtual_bus.lua` + `tools/run_e2e_tests.py` 실전 패킷 검증(`test_e2e_fdr_blackbox.lua` 계약 정합 교정 포함), `tools/verify_runtime_wiring.py`(11 서브시스템·4 예외 승인), `tools/run_boot_smoke.py`(11개 활성 `main.lua` 실부팅 및 `0_development/fdr` 64비트 타임스탬프 `%d` 오버플로우 교정), `README.md`(`R9`) 및 `.agent/` 게이트 동기화 완료 (`TASK-014-1~6`). `src/1_control/asa/**`(`TASK-105`)는 `0 diff` 동결 유지.
  - **검증**: `verify_contracts.py` 17 사양서·128 코드/설정 `0 errors`, `verify_runtime_wiring.py` `0 violations`, 부트 스모크 `11/11 PASS`, 단위 `13`타겟 `524/524 PASS`, E2E `9`스위트 `14/14 PASS` (`474`패킷 `0` violations), 하네스 `130/130 PASS`, 컨텍스트 `0 findings`, Lua 5.2 `124/124 PASS`, 매니페스트·사양서 `0 Errors, 0 Warnings`.

- [x] **TASK-120: 지상 실환경 비행 식별기(FDR)·멀티 디스크 VFS 로거 및 오프라인 프로파일러 구축 (`FDR v0.3.0`·`VAS v1.21.0 Implemented`)** (완료일: 2026-11-14)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-14-task-120-fdr-and-analyzer.md`
  - **핵심 성과**: 수신 전용(`modem.transmit` 0회) 지상 상주형 FDR (`src/0_development/fdr/` 6모듈+`main.lua`+`fdr_config.json`: `[N]` 동적 기체 바인딩·`domainId` 자동 잠금·다중 `/disk*` Spanned VFS 롤오버·`STREAMING`/`RING_BUFFER`·`E_STOP` 에지 래치·`GDRIVE_WEBHOOK` `FDR_Reports` 반출·51x19 TUI·`manifest.lua` 13모듈 등록), `VAS` Opt-in `telemetryDiag` (`telemetry_feeder.lua`/`core_daemon.lua`), 호스트 오프라인 분석/튜닝 CLI(`tools/analyze_flight_log.py`: 다중 JSONL 병합·`quat.lua` 오일러 변환·포화/추력 분배·`[0.70x, 1.35x]` 가드 `--emit-profile`) 구현 (`TASK-120-0~2`).
  - **승격·검증**: `FDR_PROGRAM_SPECIFICATION.md` (`v0.3.0 Implemented`), `VAS_PROGRAM_SPECIFICATION.md` (`v1.21.0 Implemented`) 승격(`12 Implemented, 5 Approved`), 단위 `13`타겟 `523/523 PASS` (`0_development/fdr` `16/16`, `1_control/vas` `58/58`, `0_development/installer` `40/40`), E2E `9`스위트 `14/14 PASS`, 돌연변이 `25/25 KILLED`, 하네스 `93/93 PASS`, Lua 5.2 `124/124 PASS`, 매니페스트·사양서 `0 Errors, 0 Warnings`.

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
