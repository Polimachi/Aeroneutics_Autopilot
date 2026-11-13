# Create_Aeroneutics — Task Management & Implementation Roadmap

> **문서 상태**: 활성 (Living Roadmap)  
> **최종 갱신일**: 2026-11-13  
> **현재 단계**: **Phase 1 & 2** (직전 완료: TASK-206, TASK-207, TASK-208, TASK-209 / 활성 대기: TASK-010, 011, 013, 117, 120, 123, 124, 204, 210, 401, 402)

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

> **권장 실행 우선순위 (경로 A — 스키마 재작업 최소화)**: **1순위** `TASK-124` (`TASK-204` 선행 채터링 방지 규칙 정합 개정) · `TASK-123` (독립 GPS 고부하 결함 수정) → **2순위** `TASK-401` → `TASK-204` (Zone 3 탑재체 스키마 및 `ACT_*`/`DEC_*`/`MAC_*` 행동 체계 선확정) → **3순위** `TASK-402` (신규 행동 스키마 정합 WebUI 에디터 구현 및 `AMM` 승격) → **4순위** `TASK-010` → `TASK-011` (플레이북) · `TASK-120` (FDR) · `TASK-013` (사양서 전수 감사) → **5순위** `TASK-117` (무선 OTA) / **대기** `TASK-210` (`[연기] TASK-105` 재개 연동)

- [-] **TASK-124: [1순위] `TASK-204` 착수 전 채터링 방지 규칙 문서 인게임/코드베이스 정합 개정 및 설계서 동기화** (`docs/superpowers/specs/2026-11-13-task-204-chattering-prevention-design.md`, `docs/superpowers/specs/2026-11-12-task-204-action-primitive-design.md`)
  - **권장 착수 순위**: **1순위** (`TASK-204` 착수 전 선행 채터링 방지 설계 명세 확정 및 `2026-11-12` 설계서 연료 임계값 역통일)
  - **확정 개정 기준 (`/grill-me`, 2026-11-13)**: ① `[즉시]` 36종(`FENCE_BRAKE`, `RTL_HOME`, `EMERG_LAND`, `HOVER_HOLD`, `TRANS_*`, `LAND_PREC`/`ABORT_LAND`, 도달/선회) 본 규격 확정 + `[로드맵]`(`LOCAL_AVOID`/`REPLAN_GLB`·3D 복셀·`항목 E` 서브컨트랩션 동결) 별도 절 격리, ② $R_{\text{bound}}$·$a_{\text{max}}$·$\tau_{\text{mech}}$ 수식은 튜닝 참고치로만 보존하고 `amm_config.json` 고정 파라미터 직접 지정으로 단순화, ③ 물리·제어 디바운스/유지($N_{\text{debounce}}, N_{\text{dwell}}$)는 `step_20hz_tick` 정수 틱 / 통신 워치독(`GPS 5000ms`·`FCP 500ms`·`가이드 300ms`)은 `now_ms` 이원화, ④ `Base+2` `fuel(0.0~1.0)` 단독 + `amm_config.json`(`0.20`/`0.10`)으로 `2026-11-12` 설계서까지 역통일(동적 $P_{\text{consume}}$ 수식 제거), ⑤ `항목 D`(`TCA` 레드스톤 `0~15` 양자화 Limit Cycle 방지용 도착 안착 유지 `N_settle`·이탈 불감대) `[즉시]` 본문 반영(`항목 B` 제외), ⑥ `nav_engine.lua` `validStreak >= 3`·`fcp_config.json` `wingedVtolVLowMps(8.0)`/`VHighMps(18.0)` 정합화, ⑦ 구현 아키텍처 **방안 A**(`chattering_guard.lua` 중앙 전이 가드 + `condition_evaluator` `settleTicks` 통합) 채택
  - **주요 작업**:
    - [x] **TASK-124-1**: `TASK-204` 채터링 방지 가드 AMM 내부 아키텍처(**방안 A** 중앙 전이 가드 `chattering_guard.lua` + `settleTicks`) 확정 및 설계 문서(`docs/superpowers/specs/2026-11-13-task-204-chattering-prevention-design.md`) 작성
    - [x] **TASK-124-2**: `docs/superpowers/specs/2026-11-12-task-204-action-primitive-design.md` 연료 임계값(`0.30`/`0.15` → `0.20`/`0.10`) 동기화 및 상호 링크 반영 (`TASK-204-1` 착수 선행 조건)

- [ ] **TASK-123: [1순위] GPS 고부하 경합·위상 버스트·모뎀 채널 오염 결함 수정** (`src/0_infra/gps/`, `src/0_infra/landing_pad/`, `src/3_planning/amm/modules/nav_engine.lua`, `tests/`)
  - **권장 착수 순위**: **1순위** (선행 `TASK-122`·`207`·`208` 완료, 타 태스크와 스키마 충돌 없는 독립 결함 수정)
  - **선행 참고**: `TASK-122` 후속 고부하 시나리오 검증 보고서(2026-11-12) 기반 결함 보완 (`TASK-207` `AMM`·`TASK-208` `FCP` 완료로 온보드 `CH 60001` 미개방은 해소됨; 잔여 대상인 `AMM nav_engine` + `landing_pad` 위상 분산 및 `landing_pad` `CH 60001` 미개방 적용)
  - **사양서 상태**: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (현재 v2.3.1 Implemented), `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md` (현재 v2.4.3 Implemented), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v1.3.0 Approved) — 선제 세션 대체·위상 분산·채널 인터록 규격 명문화 필요 시 착수 전 사양서 `Approved` 개정 검토
  - **배경 및 목적**: `20Hz × 3기+` 및 `5Hz × 15기+` 고부하 검증에서 식별된 3대 구조적 위험(1-A/1-B: `50ms` Window-Solve와 `20Hz` 요청 경합에 의한 응답 순서 역전 및 구형 미결 세션 `FAIL_*` 패킷 낭비, 2-A: `5Hz` 동시 기동 In-cast 버스트로 인한 CC 256-이벤트 큐 포화, 2-B: 클라이언트 측 `CH 60001` 개방에 따른 타 기체 핑·진단 핑 역유입)을 수정하여 고밀도 다기체 운용 안정성을 확보함
  - **주요 작업**:
    - [ ] **TASK-123-1**: `session_scheduler.lua` 구형 미결 세션 선제 폐기 및 Window-Solve HWM 역전 가드 구현 — `ingestReport` 내 동일 `targetClient`의 더 낮은 `clientSeq` 미결 세션(`client_pending_key`) 즉시 회수(Preemptive Supersede) 및 `flushExpired` 풀이 직전 `clientSeq > client_last_solved[targetClient]` 재검증으로 `20Hz` 환경 50ms 만료 세션의 과거 해 역전 송출·불필요 `FAIL_*` 패킷 발송 방지 (`src/0_infra/gps/modules/session_scheduler.lua`, `tests/0_infra/gps/`)
    - [ ] **TASK-123-2**: GPS 클라이언트 `client_core.lua` 단조 증가 시퀀스 수신 필터 및 `CH 60001` 미개방 인터록 보강 — `client_core:handleMessage` 내 `lastReceivedSeq` 추적으로 구형/역전 `MSG_GPS_RESPONSE` 무시(재부팅·`overrideSeq` 경계 고려) 및 `gps_client.lua` 내 `CH_GPS_PING`(`60001`) 수신 미개방 검증 (`src/0_infra/gps/modules/client_core.lua`, `src/0_infra/gps/hal/gps_client.lua`, `tests/0_infra/gps/`)
    - [ ] **TASK-123-3**: 클라이언트 결정론적 틱 위상 분산(Deterministic Tick Phase Staggering) 적용 — `os.getComputerID() % interval` 기반 틱/시간 오프셋으로 동시 기동 시 In-cast 버스트 평탄화 (`src/0_infra/landing_pad/modules/gps_client.lua` `should_query_gps(interval = 4 / 20)` 및 `src/3_planning/amm/modules/nav_engine.lua` `should_query_gps` 동시 적용; `tests/0_infra/landing_pad/`, `tests/3_planning/amm/`)
    - [ ] **TASK-123-4**: 착륙패드 `landing_pad/main.lua` `channelsToOpen`의 `GPS_PING_CHANNEL`(`60001`) 모뎀 개방 결함 제거 — `CH 60001` 송신 전용화(`FCP` `TASK-208`·`AMM` `TASK-207`은 미개방 정합화 완료)로 타 기체 핑 및 `MSG_GPS_DIAG_PING`의 지상 패드 이벤트 큐 유입 차단 (`src/0_infra/landing_pad/main.lua`, `tests/0_infra/landing_pad/`)
    - [ ] **TASK-123-5**: 고부하 경합·위상 분산·채널 미개방 단위 및 E2E 회귀 검증 — `20Hz` Early-Solve vs Window-Solve 경합 역전 차단, 다기체 위상 분산 분포, `CH 60001` 미개방 시나리오 검증(`tests/e2e/test_e2e_gps_triangulation.lua`) 및 전계층 회귀·사양서 상태 동기화

- [ ] **TASK-401: [2순위] PAYLOAD 계층(Zone 3) 통신 스키마 정의** (`docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.28.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.13.0 Approved), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v1.3.0 Approved), `docs/specs/4_mission/`)
  - **권장 착수 순위**: **2순위** (`TASK-204` `ACT_PAY_*` `TBD` 해소를 위한 선행/병행 스키마 확정)
  - **사양서 상태**: PAYLOAD 계층 전용 사양서 미작성 (Draft → Approved 수립 및 마스터 ICD Interface I-11·전체 구조도·AMM 사양서 동기화 필요)
  - **배경 및 목적**: 현행 마스터 ICD Interface I-11(`Base+20~29`, Zone 3 탑재체 버스)에는 `MSG_PAYLOAD_REQ`/`MSG_PAYLOAD_ACK` 기본 예시 패킷만 정의되어 있으며, 전체 구조도의 세부 채널 구분(`Base+20` `CH_PAYLOAD_BUS`, `Base+21` `CH_WEAPON_BUS`, `Base+22~29` 예비) 및 다양한 탑재체 노드(화물 투하, 마그넷 래치, 엄빌리컬 급유/충전, `CC:Radars`/터렛 무장 제어 등) 간 표준 통신 계약이 미비함. 탐색/기능 등록(Discovery & Capability), 상태/헬스 텔레메트리, 명령·응답(`ACK`/`NACK`)·오류 코드, 안전 인터록 및 채널 오프셋 배분 규칙을 포함한 PAYLOAD 계층 표준 통신 스키마를 정의함
  - [ ] **TASK-401-1**: 세부 탑재체 표준 행동군(`ACT_PAY_*` 하위 `TBD` 항목: 화물 투하 `CARGO_DROP`, `CC:Radars` 무장 사격 `FIRE_CTRL`, `geoScanner` 주기 스캔 등) 및 Zone 3 채널(`Base+20~29`)·안전 인터록 스키마 확정 (`docs/superpowers/specs/2026-11-12-task-204-action-primitive-design.md` §3.6 연계)

- [ ] **TASK-204: [2순위] AMM의 미션 관리 시스템용 표준 행동 리스트 재정의: 진입조건 및 계층별 분류** (`docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v1.3.0 Approved), `src/3_planning/amm/modules/`)
  - **권장 착수 순위**: **2순위** (`TASK-124`·`TASK-401` 연계 확정 후 착수 / 후속 `TASK-402`·`TASK-010-5`·`TASK-117` 선행 조건)
  - **설계 기준 문서**: `docs/superpowers/specs/2026-11-12-task-204-action-primitive-design.md` (Minecraft/UAFS 정합 Action Primitive 설계 청사진 — 기본 8도메인 45종 `ACT_*` + 확장 3도메인 10종 `ACT_*` + 데코레이터 7종 `DEC_*` + 매크로 5종 `MAC_*`) 및 `docs/superpowers/specs/2026-11-13-task-204-chattering-prevention-design.md` (`TASK-124` 채터링 방지 가드 설계서)
  - **확정 구현 경계 (`/grill-me`, 2026-11-13)**: ① `src/3_planning/amm/` 단독 범위(`VAS`/`FCP` ICD 미확장), ② `[즉시]` 항목(액션 36종·데코레이터 6종·매크로 3종)만 본 구현하고 `[로드맵]` 19종·`DEC_TIME_CRIT`·`MAC_PATROL_RADAR`/`MAC_ARM_RESUPPLY`·`TASK-401` 항목은 메타데이터 예약(`DEFERRED_ACTION_UNSUPPORTED`) 처리, ③ 로드 타임 `MAC_*` 선형 전개 + `mission_engine` FSM + 20Hz `ACT_FS_*` 반응형 안전 감독기 구조, ④ 정적 제약(기종·지오펜스·스키마)은 로드 시 `SCHEMA_INVALID` 차단 / 동적 조건 실패는 `PRECONDITION_FAILED`(`HOVER_HOLD`/`failsafePolicy` 분기) 처리
  - **배경 및 목적**: 현행 AMM의 3도메인(항법/인프라/특수) 13종 평면적 체크포인트 체계를 완전 폐기(Zero-Fallback)하고, 각 표준 행동(`ACT_*`)의 **진입조건(Entry Preconditions / State Guards)**, **데코레이터(`DEC_*`)**, **복합 매크로(`MAC_*`)** 및 **계층별 분류(Hierarchical Taxonomy)**로 전면 재편해 사양서 및 미션 엔진 검증/실행 모델에 반영
  - **주요 작업**:
    - [ ] **TASK-204-1**: `AMM` 사양서(`v2.0.0 Approved`)·상위 문서 스키마 정합화(Spec-First) — `AMM_PROGRAM_SPECIFICATION.md` 내 구 13종 체크포인트 체계 Zero-Fallback 폐기 및 `v2.0.0` `ACT_*`/`DEC_*`/`MAC_*`/`preconditions`/`failsafePolicy` 스키마 개정(`Approved`), `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`·`SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`·`AMM_MISSION_EDITOR_SPECIFICATION.md` 참조/스키마 동기화
    - [ ] **TASK-204-2**: 3계층 코어 프레임워크 & 레지스트리 엔진 구현 — `action_registry.lua`(`[즉시]` 액션 36종 본 등록 + `[로드맵]` 19종·`TASK-401` 예약 차단), 5단계 생명주기(`checkPrecondition`/`onEnter`/`onTick`/`onExit`/`onAbort`), 4대 진입조건 평가기(정적 `SCHEMA_INVALID` vs 동적 `PRECONDITION_FAILED`), `[즉시]` 데코레이터 6종(`DEC_EMCON`, `DEC_ENERGY_ECO`, `DEC_SMOOTH_TRAJ`, `DEC_HUMAN_AUTH`, `DEC_RETRY_N`, `DEC_TIMEOUT_GUARD`) 래퍼, 로드 타임 매크로 3종(`MAC_RECON_ORBIT`, `MAC_SHIP_RECOVERY`, `MAC_CARGO_SORTIE`) 전개기 및 단위 테스트
    - [ ] **TASK-204-3**: 핵심 비행 도메인 액션 23종 구현 (`ACT_SYS_*` 6종, `ACT_TKL_*` 6종, `ACT_NAV_*` 6종, `ACT_PAT_*` 5종) — 각 행동 생명주기 핸들러 및 `trajectory_generator.lua` 연계(접선 진입 `tangentEntryOffsetM`, `ACT_NAV_CORRIDOR` `CROSS_TRACK_ERROR` 감시, `ACT_PAT_LOITER_TURNS` 누적 각도, `ACT_PAT_LOITER_ALT` 나선 승강, `ACT_TKL_TRANS_*` 천이 프로파일, `ACT_NAV_CHANGE_ALT`/`SPD`/`YAW`) 및 단위 테스트
    - [ ] **TASK-204-4**: 특수·이동갑판·반응형 안전 감독기 13종 구현 (`ACT_PAY_*` 4종, `ACT_COM_ATC_HOLD` 1종, `ACT_MOB_*` 3종, `ACT_FS_*` 5종) — `PAY` 4종(`BUS_CMD`, `REDSTONE`, `SET_ROI`, `CLEAR_ROI`), `ACT_COM_ATC_HOLD`(`GAC` 슬롯 대기), `ACT_MOB_*` 3종(`RV_TRACK`, `DECK_SYNC`, `MOVING_TKOFF`), Coroutine A 20Hz `ACT_FS_*` 5종 반응형 안전 감독기(`RTL_HOME`, `GOTO_RALLY`, `FENCE_BRAKE`, `HOVER_HOLD`, `EMERG_LAND`), `nav_engine.lua` `DEC_EMCON`(`CH 60001` 억제·DR 단독·비필수 RF 침묵) 연동 및 단위 테스트
    - [ ] **TASK-204-5**: 구 13종 Zero-Fallback 제거 및 `mission_engine`·`c2_arbiter`·`ui_renderer`·`manifest.lua` 통합 — `mission_engine.lua` 레거시 13종 검증/실행 분기 완전 제거, `c2_arbiter.lua` `PRECONDITION_FAILED`/`DEFERRED_ACTION_UNSUPPORTED`/`DEC_HUMAN_AUTH` `CONFIRM` ACK·상태 전이, `ui_renderer.lua` 액션/데코레이터/진입조건 배너 표시, `manifest.lua`·`config/gdrive_mapping.json`·`verify_manifest_sync.py` 동기화
    - [ ] **TASK-204-6**: `v2.0.0` E2E 시뮬레이션 마이그레이션 및 전계층 회귀 검증 — `tests/e2e/`(`Scenario 8` 포함) 미션 JSON `v2.0.0` `ACT_*` 전면 마이그레이션, `MSN_RECON_001`·`PRECONDITION_FAILED`·`DEC_RETRY_N` 복행·`ACT_FS_*` 인터럽트 E2E 검증, 전계층 단위·E2E·돌연변이·하네스·Lua 5.2·정적 검증 통과 (`AMM` 사양서는 경로 A에 따라 `TASK-402` 완료 시까지 `Approved` 유지)

- [ ] **TASK-402: [3순위] 호스트 PC 브라우저 기반 단일 파일 비주얼 미션 에디터(`tools/amm_mission_editor.html`) HTML 구현 및 검증** (`tools/amm_mission_editor.html`, `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (현재 v0.1.0 Draft), `tests/3_planning/amm/`)
  - **권장 착수 순위**: **3순위** (경로 A: `TASK-204` 신규 행동 스키마 확정 후 에디터 사양을 정합 개정하여 1회 구현)
  - **선행 의존성**: `TASK-202-5` 및 `TASK-207` 완료 / **`TASK-204` 완료 필요** (`AMM_MISSION_EDITOR_SPECIFICATION.md` `v0.1.0 Draft`를 `TASK-204` `ACT_*`/`DEC_*`/`MAC_*` 스키마 기준으로 개정 → `Approved` 승격 후 구현)
  - **배경 및 목적**: `TASK-202-5`에서 수립한 `AMM_MISSION_EDITOR_SPECIFICATION.md`를 `TASK-204` 신규 행동 체계에 맞춰 개정한 뒤, 오프라인 `file://` 호환 단일 파일 HTML5/CSS/Vanilla JS 비주얼 미션 에디터(`tools/amm_mission_editor.html`)를 직접 생성하고, AMM 단위 테스트·E2E 시뮬레이션 검증, `manifest.lua`·`verify_manifest_sync.py`·`verify_spec_status.py` 동기화 및 WebUI 에디터 사양서와 `AMM` 사양서 `Implemented` 승격을 수행함 (`TASK-207` 코드 구현 완료, `TASK-204`·`TASK-402` 완료 시까지 `AMM` 사양서 `Approved` 유지)

- [ ] **TASK-010: [4순위] 개별 코드베이스 사용 설명서(Playbook) 체계 구축 및 핵심 5종 매뉴얼 작성**
  - **권장 착수 순위**: **4순위** (`GPS`·`VAS`·`TCA`·`FCP` 4종은 즉시 착수 가능, `TASK-010-5` `AMM` 절은 `TASK-204`·`402` 정합 후 마감 권장)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-08-task-010-playbook-framework.md`
  - 계층형 단일 마크다운(`playbook/<도메인>/<서브시스템>.md`) 기반 인게임 운용 실전 매뉴얼 5종(GPS, VAS, TCA, FCP, AMM) 구축, 표준 7대 섹션 템플릿(`playbook/README.md`), CLI 정적 검증 도구(`tools/verify_playbooks.py`), 미인가 체계 작성 차단 가드레일 및 워크플로우 동기화
  - [ ] **TASK-010-1**: 플레이북 정적 검증 도구(`tools/verify_playbooks.py`) 구현 (7대 필수 섹션, 링크 유효성, 미인가 파일 생성 차단 검증)
  - [ ] **TASK-010-2**: 표준 템플릿 명세 및 인덱스(`playbook/README.md`) 작성
  - [ ] **TASK-010-3**: 인프라 도메인 매뉴얼(`playbook/0_infra/gps.md`) 작성
  - [ ] **TASK-010-4**: 온보드 제어 도메인 매뉴얼(`playbook/1_control/vas.md`, `playbook/1_control/tca.md`) 작성 (`VAS v1.19.0` `QUATERNION_RATE`·`Base+3` `MFD_ACRO`·`system.json` 및 `TCA v1.11.1` 반영)
  - [ ] **TASK-010-5**: 유도 및 임무 도메인 매뉴얼(`playbook/2_guidance/fcp.md`, `playbook/3_planning/amm.md`) 작성 (`TASK-207~209` 완료 기준 현행 `FCP v2.0.0` `Base+4/+2/+1` 3채널 순수 `SE(3)` 외루프 및 `AMM v1.3.0` 듀얼 모뎀 외부 게이트웨이·`nav_engine`·`trajectory_generator`·`TASK-201`/`TASK-202` 3분할 미션 시퀀서·CLI/TUI·외부 파일 즉시 구동 규격 반영; 후속 `TASK-204`·`TASK-402` 완료 시 해당 절 동기화)
  - [ ] **TASK-010-6**: 프로젝트 규칙 반영, 컨텍스트 동기화 및 검증 (`test_tools_integrity.py` 도구 등록·`verify_context_docs.py` 통과 및 `TASK-009`·`113`·`114`·`115`·`116`·`122`·`202`·`207~209` 현행 반영 확인)

- [ ] **TASK-011: [4순위 / 인프라 매뉴얼] 지상 관제 및 정비 도메인 플레이북 2차 확장 (Alignment, GCS, GAC, Landing Pad)** (`playbook/0_development/alignment.md`, `playbook/0_infra/{gcs,gac,landing_pad}.md`)
  - **선행 의존성**: `TASK-010` 완료 필요 (표준 7대 섹션 템플릿 `playbook/README.md` 및 `tools/verify_playbooks.py` 검증 체계 활용)
  - **배경 및 필요성**: `TASK-010`은 핵심 5종(GPS, VAS, TCA, FCP, AMM)에 집중되어 있으나, 실제 인게임 운용 시 설정·조작이 가장 까다로운 격납고 동역학 캘리브레이션(Alignment)과 지상 관제소/패드 셋업(GCS, GAC, Landing Pad) 매뉴얼 보강 필요
  - **주요 작업**:
    - [ ] **TASK-011-1**: 격납고 동역학 캘리브레이션 매뉴얼(`playbook/0_development/alignment.md`) 작성
    - [ ] **TASK-011-2**: 중앙 지상 관제소 매뉴얼(`playbook/0_infra/gcs.md`) 작성
    - [ ] **TASK-011-3**: 섹터 관제·착륙패드 매뉴얼(`playbook/0_infra/gac.md`, `playbook/0_infra/landing_pad.md`) 작성
    - [ ] **TASK-011-4**: `tools/verify_playbooks.py` 7대 섹션·링크·인가 목록 정적 검증 통과

- [ ] **TASK-120: [4순위 / 개발 도구] 블랙박스 비행 기록기(FDR) 및 호스트 PC 오프라인 텔레메트리 분석기 구축** (`src/0_development/fdr/`, `tools/analyze_flight_log.py`)
  - **권장 착수 순위**: **4순위** (독립 도구로서 병렬 착수 가능, `TASK-117` 선행 조건)
  - **사양서 상태**: 미작성 (구현 착수 전 Draft → Approved 필요; `Base+1` `MSG_ATTITUDE_CMD`·`Base+2` `MSG_FLIGHT_TELEMETRY` 패시브 감청 기준, 필요 시 진단 필드 확장 검토)
  - **배경 및 필요성**: 온보드 제어기 헤드리스 전환(TASK-113)으로 실시간 20Hz 성능은 확보되었으나, 인게임 비행 중 발생하는 미세 자세 진동, 짐벌 포화(Saturation), 슬루율 제한 현상을 정밀 튜닝하기 위한 시계열 로그 수집 수단 부재
  - **주요 작업**:
    - [ ] **TASK-120-1**: 경량 블랙박스 로거(`src/0_development/fdr/`) 구현 — `Base+1`(유도 지령) 및 `Base+2`(20Hz VAS 텔레메트리) 패킷을 패시브 감청해 로컬 링 버퍼에 기록하고 `E_STOP` 또는 사용자 핫키 입력 시 JSONL 포맷으로 덤프 (`manifest.lua`·`verify_manifest_sync.py` 등록 포함)
    - [ ] **TASK-120-2**: 오프라인 텔레메트리 분석 CLI(`tools/analyze_flight_log.py`) 구현 — JSONL 덤프 파일을 읽어 목표치(Setpoint) 대비 실제 측정치(Process Variable), PID 적분항 포화도, 추력 분배율 분석·요약 출력 (`tests/harness/test_tools_integrity.py` 등록 포함)

- [ ] **TASK-013: [4순위] 사양서 전수 검사 — 사양서를 포함하는 모든 `.md` 파일에 대한 정합성 감사(`specification-lifecycle-manager`) 수행 예정** (`docs/system/*.md`, `docs/specs/**/*.md`)
  - **권장 착수 순위**: **4순위** (`TASK-401`·`204`·`402` 스펙 변경 수렴 직후 1회 일괄 감사 권장)
  - **목적 및 범위**: 사양서를 포함하는 모든 `.md` 파일 전수 검사 및 문서 관리 수행 예정 (참고: `.agent/rules/skill-workflows.md` 기준 활성 사양서 전수 감사·동기화는 `specification-lifecycle-manager` 및 `tools/verify_all_specs.py`, 3계층 컨텍스트 문서(`AGENTS.md`, `GEMINI.md`, `.agent/memory/*.md`)는 `md-management` 관할)

- [ ] **TASK-117: [5순위] 무선 OTA 배포 서버 및 슬레이브 원자적 롤백 가드 구축 (구 TASK-117 + 119 통합)** (`src/0_development/ota/`, `src/0_development/installer/modules/startup_generator.lua`, `src/1_control/{vas,tca}/`, `src/2_guidance/fcp/`, `src/3_planning/amm/`)
  - **권장 착수 순위**: **5순위** (선행 과제 중 `TASK-202`·`TASK-207~209` 완료; 잔여 선행 `TASK-204`·`TASK-010`·`TASK-011`·`TASK-120` 완료 후 리소스 집중 착수)
  - **사양서 상태**: 통합 OTA 사양서 미작성(Draft → Approved 및 대상 경로 확정 필요) / 연관 개정 대상: `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` (현재 v1.1.0 Implemented), `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (현재 v1.28.0 Approved), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (현재 v2.13.0 Approved), `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (현재 v1.19.0 Implemented), `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (현재 v1.11.1 Implemented), `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (현재 v2.0.0 Implemented), `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v1.3.0 Approved)
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
  - **사양서 상태**: 별도 사양서 미작성 (마스터 ICD `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` v1.28.0 Interface I-5 기반 `AMM (Node 03)` 교신 규격; 착수 전 사양서 Draft → Approved 또는 ICD 연계 필요)
  - 광역 공역 진입/이탈 스케줄링 및 섹터 `GAC` 핸드오프 프로토콜 구현 (일정 연기)

### 🔭 Phase 3 백로그 (Phase 3 Backlog)

- [ ] **[연기] TASK-301: 물리 하드웨어 기반 ACRO 수동 급기동 조종 인터페이스 개발**
  - Create/Avionics 아날로그 스틱 및 물리 컨트롤러 하드웨어 연동 (일정 연기)
  - `Base+1` 20Hz 직접 3축 각속도(`RATE_COMMAND`) 직결 스트림 및 비행 제어 코어(VAS) 선점 제어 연동

---

## ✅ 3. 완료된 작업 이력 (Completed Tasks Archive — 최근 10개 유지)

- [x] **TASK-209: VAS v1.19.0 `QUATERNION_RATE` 내루프 정규화 및 ACRO/페일세이프 정합화** (완료일: 2026-11-13, 커밋 `3c82f7f`, `83ff1f6`, `244c940`, `7b19207`) (`docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (현재 v1.19.0 Implemented), `src/1_control/vas/`, `tests/1_control/vas/`, `tests/e2e/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-12-task-207-208-209-sequential-plan.md`
  - **목적 및 성과**: `Base+1` `[I-2]` 수신 스키마를 `QUATERNION_RATE`/`RATE_COMMAND`(`targetQuaternion`, `targetAngularRates`, `collectiveThrust`, 선택적 `flapTarget`/`translationBias {surge, sway}`) 단일 경로(Zero-Fallback, `ATTITUDE_ANGLE` 제거)로 정규화하고, 정상 비행 `compute_climb_wrench`를 제거해 `FAILSAFE_HOLD`(`FCP_TIMEOUT` 1,500ms $\to$ 10s $\to$ `EMERGENCY_LAND`) 한정 격리함. `E_STOP (ESTOP_CONFIRM_KEY) > MFD_ACRO > FCP` 선점 중재, `Base+3` `CORE_ACRO_TAKEOVER` 20Hz HUD 직결 및 침묵 가드, `[I-10]` `MSG_AERO_*`/`MSG_SURFACE_DISCOVER_*`, `config/system.json`(`trajectory: 4`, `asaActuation: 11`, `fcpCommandTimeoutMs: 1500`, `flapVfeLimit: 15.0`) 및 `satAsa`/`satTca`/`fcpCmd` 정합화를 완료하고 `VAS v1.19.0` 사양서를 `Implemented`로 승격함. 4노드 폐루프 E2E(`test_e2e_4tier_closed_loop.lua` Scenario 8 `4/4 PASS`), 전계층 단위 12타겟 `455/455 PASS`(`1_control/vas` `46/46`), E2E 8스위트 `12/12 PASS`, 돌연변이 `25/25 KILLED`(`100.0%`), 하네스 `82/82 PASS`, Lua 5.2 `121/121 PASS`, 매니페스트 3자 정합성 `0 Errors, 0 Warnings`, 사양서 15종(`9 Implemented, 6 Approved`) `0 Errors, 0 Warnings` 달성.

- [x] **TASK-208: FCP v2.0.0 SE(3) 외루프 제어기 경량화 전면 개편** (완료일: 2026-11-13, 커밋 `26d8365`, `ea66b21`, `3fd3c46`, `9c8af01`, `319d659`, `244c940`, `7b19207`) (`docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (현재 v2.0.0 Implemented), `src/2_guidance/fcp/`, `tests/2_guidance/fcp/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-12-task-207-208-209-sequential-plan.md`
  - **목적 및 성과**: `FCP (Node 04)`를 단일 `top` 모뎀 3채널(`Base+4`, `Base+2`, `Base+1`) 전용 순수 온보드 `SE(3)` 외루프 제어기로 축소 개편함. `network_manager.lua` 3채널 격리 및 `MSG_CHANNEL_REBIND` 중계, `state_propagator.lua` 로컬 속도 적분(`dt <= 0.1s`, `posMergeMaxStepM = 2.0`, `500ms` `navStale`), `flight_fsm.lua` 6상태 FSM(`BOOT`, `IDLE_ARMED`, `ACTIVE_TRACKING`, `PASSIVE_TRACKING` 2.0s 범프리스 램핑, `AMM_TIMEOUT_HOLD` 500ms $\to$ 10s $\to$ `EMERGENCY_LAND`), `outer_loop_controller.lua` 통합 `SE(3)` 법칙($g = 11.0\text{ m/s}^2$, 조건부 안티와인드업, 6대 기체 `QUATERNION_RATE` 투영, `STRICT_LEVEL`/`TILT_ASSISTED` + 스웨이 결손 폴백, 멀티로터 $25^\circ$, 유익 VTOL `[8, 18] m/s`, 고정익 BTT+TECS)을 구현하고 레거시 14개 파일·외부 RF·`/etc/vac/` 경로를 제거해 `manifest.lua`·`gdrive_mapping.json`·돌연변이 테스트(`MUT-14`/`15`/`23`)를 동기화하고 `FCP v2.0.0` 사양서를 `Implemented`로 승격함. 단위 `2_guidance/fcp` `46/46 PASS`(전계층 `455/455`), Scenario 8 `4/4 PASS`, 돌연변이 `25/25 KILLED` 달성.

- [x] **TASK-207: AMM v1.3.0 외부 게이트웨이·항법 융합·20Hz 궤적 생성기 구현** (완료일: 2026-11-13, 커밋 `52dc141`, `829d6a4`, `86a2701`, `28aceaf`, `8673e38`, `bd1539c`, `244c940`, `7b19207`) (`docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (현재 v1.3.0 Approved), `src/3_planning/amm/`, `tests/3_planning/amm/`)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-12-task-207-208-209-sequential-plan.md`
  - **목적 및 성과**: `AMM (Node 03)`에 듀얼 모뎀(`top`+`back`, 단일 모뎀 폴백), `channel_sentinel.lua`(`CH 50000`, `200ms` 프로브, 4계층 재바인딩, `MUT-03`), `nav_engine.lua`(`TASK-122` GPS+DR $\alpha=0.35$, `degradedAlpha=0.10`, `5,000ms` DR 선회, `posEpoch`, `CH 60001` 송신 전용 미개방; 위상 분산은 `TASK-123` 연계), `facility_client.lua`(Tower ATC/GAC/Runway/Docking/Landing Pad 2차 테일러 외삽 $\le 0.5\text{s}$, `300ms` 워치독, `15s x 10` 재시도), `trajectory_generator.lua`(11종 비행 모드, `LOITER` `ffAccel`, `POI_HOLD` $\le 30^\circ/\text{s}$, `-0.8` 도킹 이탈, 가상 ILS, 2단계 터치다운, `-2.0` 비상 강하), `Base+4` `[I-12]` 20Hz 송수신, `Base+3` 5Hz MFD 다운링크(`MFD_ACRO` 양보), `E_STOP` `authKey` 및 Coroutine A(20Hz)/B(5Hz) 분리를 구현함. 단위 `3_planning/amm` `112/112 PASS`(전계층 `455/455`), Scenario 8 `4/4 PASS`, 돌연변이 `25/25 KILLED` 달성 (`AMM v1.3.0` 사양서는 `TASK-402` WebUI 에디터 구현 완료 시 `Implemented` 승격 예정).

- [x] **TASK-202: UAFS 통합 미션 시퀀서 엔진, AMM 조종석 단말 및 WebUI 에디터 사양 수립 (구 TASK-201[AMP 초안] + 203 통합)** (완료일: 2026-11-12) (`src/3_planning/amm/`, `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (현재 v0.1.0 Draft))
  - **실행 계획서**: `docs/superpowers/plans/2026-11-11-task-202-2-amm-mission-core-hooks-zone3.md`, `docs/superpowers/plans/2026-11-11-task-202-3-amm-mission-fsm-c2-headless.md`, `docs/superpowers/plans/2026-11-11-task-202-4-amm-tui-resolver-drop-cli.md`, `docs/superpowers/plans/2026-11-12-task-202-5-amm-webui-editor-spec.md` (초안: `docs/superpowers/plans/2026-11-08-amp-mission-planner.md`, `docs/superpowers/plans/2026-11-11-amm-webui-editor-spec-draft.md`)
  - **목적 및 성과**: Layer 3(AMM)과 구 Layer 4(AMP) 미션 시퀀서를 3분할 코어(`mission_engine.lua`, `condition_evaluator.lua`, `hook_runner.lua`)로 통합하고 51x19 6행 스크롤 뷰포트·다중 경로 리졸버·프리플라이트 검증기·`file_transfer` 핫인젝션·헤드리스 C2(`Base+0`)를 구현했으며(`TASK-202-1~4`), 호스트 PC 외부 비주얼 에디터(`tools/amm_mission_editor.html`)의 `AMM v1.3.0` 정합 상세 규격서(`AMM_MISSION_EDITOR_SPECIFICATION.md` `v0.1.0 Draft`)를 수립해 후속 HTML 구현(`TASK-402`)으로 인계함 (`docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` 현재 v1.3.0 Approved, `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` 현재 v1.28.0 Approved, `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` 현재 v2.13.0 Approved).
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
