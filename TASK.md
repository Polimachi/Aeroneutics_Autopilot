# Create_Aeroneutics — Task Management & Implementation Roadmap

> **문서 상태**: 활성 (Living Roadmap)  
> **최종 갱신일**: 2026-11-21  
> **현재 단계**: **Phase 1 & 2** (직전 완료: TASK-302, TASK-015, TASK-019, TASK-018, TASK-017, TASK-016, TASK-128, TASK-131, TASK-136, TASK-406 / 활성 대기: TASK-140, 020, 021, 135, 214, 105, 210, 132, 129)

---

## 📌 에이전트 작업 지침 (Agent Protocol)

- **계획 수립 시**: 작업 계획(`/plan` 등)이 확정되면 본 파일의 당면 과제 또는 백로그에 신규 항목(`[ ]`)을 등록한다.
- **작업 착수 시**: 진행 중인 태스크를 `[-]` (진행 중)으로 전환한다.
- **작업 완료 시**: 완료 항목을 `[x]` (완료)로 변경해 `## 3. 완료된 작업 이력` 상단으로 이동·기록하고, 도출된 후속 과제를 즉시 본 파일에 등록한다.
- **완료 이력 보존 상한**: 완료된 작업 이력은 **최근 10개까지만 유지**하며, 10개를 초과하는 과거 완료 항목은 오래된 순서대로 정리(Prune)한다.
- **도메인 경로 매핑 기준**: `docs/specs/`, `src/`, `tests/` 간 1:1 도메인 계층 구조는 [README.md](README.md)의 디렉토리 레이아웃을 따른다.
- **유저 호출 예시**:
  - `TASK.md 확인하고 다음 남은 작업 진행해줘`
  - `TASK.md의 TASK-302 작업 진행해줘`
  - `TASK.md 상태 점검해줘`

---

## 🚀 1. 활성 당면 과제 (Active Immediate Tasks — Phase 1 & 2)

> **권장 실행 우선순위**: **1순위** `TASK-140` (저고도 센서 융합 고도계 및 지면 효과 착륙 감쇠 보상) → **2순위** `TASK-020` (`46KB` 초과 Lua 3종 분할/추출) · `TASK-021` (지상 3종 20Hz TUI 분리·클로저 팩토리 분해) · `TASK-135` (AMM 임무 계층 샌드박스·Yield 워치독) · `TASK-214` (허브 공항 대기 스택·착륙 슬롯 스케줄러) · `TASK-105` ↔ `TASK-210` (ASA 본 구현 및 실노드 연동 연계) · `TASK-132` (추력 상실 비상 활공·오토로테이션 가드) · `TASK-129` (적응형 트림 보정) / **연기(§2)** `TASK-104`·`TASK-108`·`TASK-401`·`TASK-301`
- [ ] **TASK-140: [1순위 / 정밀 착륙 제어] 저고도 센서 융합 고도계, 양방향 지면 효과 착륙 보상 및 터치다운 프로토콜 개선** (`docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`, `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`, `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`, `src/1_control/vas/`, `src/2_guidance/fcp/`, `tests/1_control/vas/`)
  - **권장 착수 순위**: **1순위** (`TASK-403`의 `ACT_TKL_LAND_NORM` / `ACT_TKL_LAND_PREC` / `ACT_TKL_LAND_NEAREST` 착륙 정밀도 향상 연계)
  - **사양서 상태**: 미개정 (`VAS` · `FCP` · `AMM` 사양서 개정 필요)
  - **배경 및 필요성**: 20Hz GPS 위치 측정은 수직 방향 양자화 오차와 미세 지연을 포함하고 있어, 지상 `15m` 이하의 최종 착륙 접근(Final Flare) 구간에서 지면 표고 오판이나 로터·하향 추력기의 지면 효과(Ground Effect)로 인한 양력 변동(양의 양력 증가뿐 아니라 음의 방향 흡입·양력 감소 포함)으로 인해 접지 직전 기체가 튀어 오르는 바운싱(Porpoising) 또는 급침하가 발생함. 다중 센서 융합 대지 고도(AGL) 필터, 음/양 양방향 지면 효과 추력 보상, 지수 감쇠 플레어 프로파일 및 단계별 터치다운 프로토콜 개선으로 안정적이고 정밀한 소프트 터치다운을 구현해야 함.
  - **핵심 기술 규격**:
    - 상보 필터 기반 대지 고도계(`AGL_Estimator`): 지상 `15m` 이하 접근 시 GPS 수직 위치, VAS 수직 가속도/속도 적분값, 및 하향 거리 센서(또는 착륙패드 비콘 기준 표고 `padSurfaceY`)를 융합하여 지연 없는 정밀 AGL 고도와 침하율(`sinkRateMps`)을 산출함.
    - 양방향 지면 효과 추력 보상 곡선(`GROUND_EFFECT_COMP`): `AGL < 4.0m` 진입 시 지면 효과로 인한 양력 증가가 양/음 어느 방향으로든 발생할 수 있음을 전제로, 음/양 양방향 추력 보상 계수(감쇠 및 증강 모두 허용, 부호 있는 보상 바이어스)를 적용하고, 최종 접지 직전(`AGL < 1.5m`) 목표 침하율을 `0.35 m/s`로 고정하는 지수 플레어(Exponential Flare) 제어를 수행함.
    - 착륙 정밀도 향상을 위한 터치다운 프로토콜 과정 개선: 최종 접근 → 수평 위치/자세 정렬 안정화 게이트 → 플레어 하강 → 다중 조건 접지 판정(AGL·침하율·수직 가속도 변화량 조합) → 바운싱 억제 접지 래치(수직 오차 적분항 `Ki` 즉시 리셋 및 하향 홀드 바이어스 인가) → 추력 단계 감축 및 `AMM`/`Landing Pad` 착륙 완료 핸드셰이크로 이어지는 터치다운 시퀀스를 정밀화함.
  - **주요 작업**:
    - [ ] **TASK-140-1**: `VAS` · `FCP` · `AMM` 사양서 개정 — `AGL_Estimator` 센서 융합 가중치, 음/양 양방향 `GROUND_EFFECT_COMP` 보상 곡선, 최종 플레어 침하율 및 개선된 터치다운 프로토콜 단계별 전이 규격 정의
    - [ ] **TASK-140-2**: `VAS` 저고도 상보 고도 필터·양방향 지면 효과 추력 보상 모듈(`src/1_control/vas/modules/agl_flare_controller.lua`) 및 `FCP`/`AMM` 터치다운 프로토콜 시퀀스 개선 구현
    - [ ] **TASK-140-3**: 정밀 착륙 시나리오(음/양 지면 효과 외란 포함) 접지 위치·수직 속도 정밀도 및 바운싱 0회 검증 단위·E2E 테스트 통과 후 사양서 `Implemented` 승격

- [ ] **TASK-020: [3순위 / 대형 모듈 분할·추출] `46,080 B` 초과 Lua 3종(`amm/main.lua`·`amm/mission_engine.lua`·`installer/manifest.lua`) 분할 및 데이터 분리 (`TASK-016` 도출)** (`src/3_planning/amm/`, `src/0_development/installer/`, `config/audit_baselines.json`)
  - **근거**: [Architecture_Efficiency_Audit_1_11182026.md](reports/underReview/Architecture_Efficiency_Audit_1_11182026.md) §4.2 (`E-S-02`·`03`·`04`).
  - **주요 작업**:
    - [ ] **TASK-020-1**: `amm/main.lua` (`53,820 B`, 2026-11-20 실측) → `amm_cli.lua`·`cold_boot_recovery.lua`·`infra_rx_router.lua` 추출, `amm/modules/mission_engine.lua` (`53,334 B`) → `mission_validator.lua`·`mission_dispatchers.lua` 분할 (`manifest.lua`·`gdrive_mapping.json`·단위/E2E 동기화)
    - [ ] **TASK-020-2**: `installer/modules/manifest.lua` (`47,202 B`) → `manifest_catalog.lua` 데이터 카탈로그 분리 및 `ota_server.sync_remote` 동기화 후 `config/audit_baselines.json` `large_lua_exemptions` 제거

- [ ] **TASK-021: [3순위 / 지상 인프라 20Hz TUI 분리·구조 정제] `0_infra/{gac,landing_pad,runway}` 20Hz 루프 TUI 격리 및 200줄+ 클로저 팩토리 분해 (`TASK-016` 도출)** (`src/0_infra/gac/`, `src/0_infra/landing_pad/`, `src/0_infra/runway/`)
  - **근거**: [Architecture_Efficiency_Audit_1_11182026.md](reports/underReview/Architecture_Efficiency_Audit_1_11182026.md) §3 (`E-L1-04`, `E-L3-05`).
  - **주요 작업**:
    - [ ] **TASK-021-1**: `gac`/`landing_pad`/`runway` `0.05s` 루프 내 동기 `tui:render*`를 5Hz(`0.2s`) 코루틴·`headless` 옵션으로 분리 (`E-L1-04`)
    - [ ] **TASK-021-2**: `gac_fsm.create`(356 L)·`tui_view.create`(249 L)·`pad_fsm.create`(239 L) 내부 메서드 분해

- [ ] **TASK-135: [3순위 / 온보드 런타임 격리] AMM 임무 계층(4_mission) 샌드박스 격리 및 무응답(Yield) 워치독 가드** (`docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`, `src/3_planning/amm/`, `tests/3_planning/amm/`)
  - **권장 착수 순위**: **3순위** (Phase 2 `4_mission` 임무 패키지 도입 전 필수 런타임 보호 게이트 — 2순위→3순위 조정)
  - **사양서 상태**: 미개정 (`AMM` 사양서 개정 필요)
  - **배경 및 필요성**: CC:Tweaked Lua 환경에서는 임무 스크립트(`4_mission`)나 사용자 정의 조건식(`DEC_*`) 내부에서 `os.pullEvent` 없이 루프가 지연(Too long without yielding)되거나 런타임 예외가 발생하면 호스트 컴퓨터 전체가 정지함. `AMM` 컴퓨터가 비행 중 멈추면 유도 명령 갱신이 중단되므로, 코어 비행 시퀀서와 상위 임무 애플리케이션을 엄격히 격리하는 런타임 가드가 필수적임.
  - **핵심 기술 규격**:
    - 격리된 임무 실행 샌드박스(Mission Sandbox): `4_mission` 패키지는 화이트리스트 API(`AMM` 네비게이션 요청, 허용된 주변장치 읽기, 상태 로깅)만 노출된 전용 환경 테이블에서 실행되며, 코어 채널·안전 인터록 변수의 직접 변조를 차단함.
    - 명령어 할당량(Instruction Quota) 및 Yield 워치독: `debug.sethook` 기반 스텝 카운터 가드를 적용하여 단일 틱 내 과도한 CPU 명령어를 소모하는 임무 스크립트를 강제 중단(`MISSION_SCRIPT_FAULT`)시킴.
    - 코어 생존 및 자동 폴백: 임무 스크립트 오류나 타임아웃 발생 시 `AMM` 코어 데몬은 예외를 포착해 해당 `4_mission` 태스크만 안전 언로드하고, 기체를 즉시 제자리 호버(`HOLD_POSITION`) 또는 홈 패드 귀환(`RTB`) 상태로 보호함.
  - **주요 작업**:
    - [ ] **TASK-135-1**: `AMM_PROGRAM_SPECIFICATION.md` 개정 — `4_mission` 샌드박스 화이트리스트 API, 명령어 할당량 임계치, 스크립트 크래시 시 `HOLD`/`RTB` 복구 규격 정의
    - [ ] **TASK-135-2**: `AMM` 코어 내 샌드박스 로더 및 `debug.sethook` 워치독 가드 구현 (`src/3_planning/amm/modules/mission_sandbox.lua`)
    - [ ] **TASK-135-3**: 무한 루프·메모리 초과·런타임 `nil` 참조 결함 스크립트 주입 테스트 통과 후 사양서 `Implemented` 승격

- [ ] **TASK-214: [3순위 / 다중 기체 관제] 허브 공항 터미널 접근 대기 스택(Holding Stack) 및 착륙 슬롯 스케줄러** (`docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md`, `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`, `src/0_infra/gac/`, `src/3_planning/amm/`, `tests/0_infra/gac/`)
  - **권장 착수 순위**: **3순위** (`TASK-403` 시설 점유 비콘 및 `TASK-125` 다중 기체 식별 체계와 연계, 다중 기체 임무 운용 단계에서 착수 — 2순위→3순위 조정)
  - **사양서 상태**: 미개정 (`GAC` · `AMM` 사양서 개정 필요)
  - **배경 및 필요성**: 복수의 화물기나 탐사기 등 다중 편대 기체(`4_mission`)가 임무를 마치고 동일한 중앙 격납고·허브 공항으로 동시 귀환할 때, 가용 착륙패드 수보다 귀환 기체가 많으면 패드 상공에서 동시 하강 충돌이나 교착 상태가 발생함. 섹터 관제기(`GAC`)가 공중 대기 선회 고도를 계층 배정하고 착륙 순서를 통제하는 터미널 슬롯 스케줄러가 필요함.
  - **핵심 기술 규격**:
    - 터미널 접근 요청 및 슬롯 배정(`MSG_APPROACH_REQ` / `MSG_HOLDING_ASSIGN` / `MSG_APPROACH_CLEARANCE`): 공항 관제 반경 진입 시 `AMM`이 착륙 슬롯을 요청하면, `GAC`가 가용 패드 유무를 확인해 즉시 착륙 허가 또는 고도 분리된 대기 스택 레벨(Level 1: `+40m`, Level 2: `+60m`, Level 3: `+80m` 등 `20m` 수직 간격)을 할당함.
    - 우선순위 기반 선입선출(Priority FIFO) 큐: 기본 도착순(FIFO)으로 착륙 순서를 관리하되, `TASK-125`의 `BINGO_FUEL` 또는 비상 상태 기체에는 최우선 착륙 슬롯(Preemptive Priority)을 부여함.
    - 순차 강하 및 패드 해제 연동: 선행 기체가 착륙 후 격납고 인입 또는 이륙으로 패드를 비우면(`PAD_RELEASED`), `GAC`가 다음 순번 기체에 최종 접근 허가를 발행하고 상위 대기 기체들의 고도 레벨을 한 단계씩 하강 재배치함.
  - **주요 작업**:
    - [ ] **TASK-214-1**: `GAC` · `AMM` 사양서 개정 — 터미널 관제 반경, 수직 대기 스택 고도 배분 규칙, 비상 우선순위 큐 및 메시지 스키마 정의
    - [ ] **TASK-214-2**: `GAC` 터미널 착륙 슬롯 스케줄러 및 대기 고도 관리 모듈 구현 (`src/0_infra/gac/modules/approach_scheduler.lua`)
    - [ ] **TASK-214-3**: `AMM` 터미널 접근 대기 선회(Holding Orbit) 및 허가 수신 강하 전이 로직 구현
    - [ ] **TASK-214-4**: 3기 동시 귀환 및 1기 `BINGO_FUEL` 긴급 추월 시나리오 E2E 테스트 통과 후 사양서 `Implemented` 승격

- [ ] **TASK-105: [3순위 / 공력 구동기] ASA (Aerodynamic Surface Adapter) 공력 조종면·플랩 분산 구동기 본 구현 완성** (`docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md`, `src/1_control/asa/`, `tests/1_control/asa/`)
  - **권장 착수 순위**: **3순위** (`TASK-210` 연계 동시 배치·병행 수행)
  - **사양서 상태**: `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (`Approved`)
  - TASK-113의 기본 프레임워크(헤드리스/비동기 TUI, `Base+11` 수신 루프, 300ms Safe Glide Trim, 단위 테스트 15/15 PASS)를 기반으로 물리 액추에이터(Avionics API/RS) 각도 인가, `MSG_AERO_STATUS` 상태 피드백 송출 및 `MSG_ACTUATOR_DISCOVER_REQ/ACK` 핸드셰이크 완성 (`TASK-210` 연계; 3순위 편입 — 착수 시 `manifest.lua`·`verify_spec_status.py` 갱신 및 `tools/verify_manifest_sync.py` `DEFERRED_SUBSYSTEM_DIRS`·`config/protocol_contracts.json` `deferredSubsystems`·`tools/run_boot_smoke.py` `deferred` 면제 해제 필요)
  - **[동결 결정 주석 — `TASK-013` Q4 방안 B (2026-11-14)]**: `src/1_control/asa/**` 및 `tests/1_control/asa/**`는 `TASK-105` 본 구현 착수 시점까지 현행 골격(`0 diff`)으로 동결 유지 후, 착수 시 아래 **5대 골격 결함 (`FLT-HIGH-12`)**을 필수로 함께 수정해야 함:
    1. `[I-10]` 정규화 입력(`[-1.0, +1.0]` / `[0.0, 1.0]`) 매핑 및 `dynamicPressureFactor` 승산 적용 (구 `0..15`/`-15..15` 직접 각도 스케일링 제거).
    2. `MSG_AERO_STATUS` 표준 필드·상태 열거형 정렬: `interactionMode`(`mode` 제거), `appliedDeflection`(`appliedDeg` 제거), `"NOMINAL" | "DEGRADED" | "TOTAL_LOSS"`(`"API_NOMINAL"`/`"API_TOTAL_LOSS"` 제거) 및 페일세이프 문자열 `"SAFE_GLIDE_TRIM"` 정렬(`"SAFE_GLIDE"`·`elevator=0.1` 하드코딩 제거).
    3. `[I-4]` 격납고 프로파일링 핸드셰이크 정렬: `MSG_CALIB_BAY_BIND`(`baseHangarChannel`), `MSG_ACTUATOR_DISCOVER_REQ/ACK`(`Base_hangar+3`, `targetGroup`), `MSG_PROFILE_SYNC.discoveredSurfaces` 객체 맵 및 표준 조종면 코드 `"RUDD"`(`"RUDDER"` 제거).
    4. `[I-9]` 4계층 재바인딩 Option A 정렬: `MSG_CHANNEL_REBIND` / `MSG_CHANNEL_REBIND_ACK`(`transactionId`, `action`, `oldBaseChannel`, `newBaseChannel`, `500ms` 워치독, `"READY"`/`"COMMITTED"`/`"ROLLED_BACK"`/`"FAILED"`).
    5. `ASA §3.2` 설정 스키마 정합화: `schemaVersion` vs `version` 단일화, `ver == "1.9.5"` 및 `domainId` 검증 복원, `s.ELEV or s.elevator` 등 듀얼키 폴백(Zero-Fallback) 제거.

- [ ] **TASK-210: [3순위 / 연계 · ASA 실노드 연동] ASA 구현 정합화 및 VAS·Alignment 실노드 연동 검증 (`MSG_AERO_*` · `MSG_SURFACE_DISCOVER_*` · 4계층 재바인딩 반영)** (`docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md`, `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md`, `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md`, `src/1_control/asa/`)
  - **권장 착수 순위**: **3순위** (`TASK-105` 연계 TASK — 3순위 섹션 동시 배치·병행 수행)
  - **선행·연계 의존성**:
    - **기완료 기반 (`TASK-206`·`TASK-207`·`TASK-208`·`TASK-209`·`TASK-013` 완료)**: `VAS v1.20.0` (당시 기준; `actuator_adapter_asa.lua`·`Base+11` 송신단), `TCA v1.12.0` (당시 기준; `Option A` 재바인딩·`Base_hangar+3` 탐색), `ALIGNMENT v2.7.0` (당시 기준; `discovery_client.lua` `MSG_SURFACE_DISCOVER_REQ/ACK`·`profile_exporter.lua`) 정합화 및 1차 E2E(`244c940`) 완료.
    - **연계 TASK (`TASK-105`)**: **`TASK-105` (ASA 본 구현 및 `FLT-HIGH-12` 5대 골격 결함 해소)** — `TASK-013` Q4 방안 B에 따라 `src/1_control/asa/**`·`tests/1_control/asa/**`가 동결(`0 diff`)되어 있으므로, 3순위 `TASK-105` 착수 시 본 과제를 연계·병행 수행함.
  - **배경 및 목적**: ① **[기반 완료]** `TCA`·`Alignment`·`VAS`(`actuator_adapter_asa.lua` 송신단·`Base+11`) 1차 E2E(`244c940`) 및 `TASK-013` 정합화 완료. ② **[잔여 범위 — `TASK-105` 연계 수행]** 동결 중인 `ASA` 본 구현과 함께 `TASK-105`의 `FLT-HIGH-12` 5대 결함을 해소하고, 다중 노드 E2E(`AMM ↔ FCP ↔ VAS ↔ ASA ↔ Alignment`) 검증 후 `ASA` 사양서를 `Implemented`로 승격함.

- [ ] **TASK-132: [3순위 / 비상 비행 제어] 추력 상실·대파(Battle Damage) 시 비상 활공(Best-Glide) 및 오토로테이션 가드** (`src/1_control/vas/`, `src/2_guidance/fcp/`, `src/3_planning/amm/`)
  - **권장 착수 순위**: **3순위** (고정익·하이브리드 기체용 공력 조종면 `TASK-105`/`210` `ASA` 체계와 연계 — 2순위→3순위 조정, 착수 시 Spec-First 사양 개정 선행)
  - **사양서 상태**: 개정 대기 (`VAS`·`FCP`·`AMM` `Implemented` 기반 추가 반영 필요)
  - **대상 사양서**: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`, `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`, `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`
  - **배경 및 필요성**: Create: Aeronautics / Create: Big Cannons 운용 환경에서 엔진 피격, 회전력(SU) 과부하, 또는 다수 추진기 TOTAL_LOSS로 총 가용 추력이 기체 중량을 지탱하지 못할 때(availableThrust < weight), 기존 호버/고도 유지 루프는 기수를 과도하게 들어 올려 실속(Stall)·스핀 추락을 유발함.
  - **주요 작업**:
    - [ ] **TASK-132-1**: VAS 실시간 추력 여유도 감시기 구현 — TCA 상태 피드백 합산 추력이 임계치 미만으로 하락 시 `POWER_LOSS_EMERGENCY` 상태 전이
    - [ ] **TASK-132-2**: 고정익·하이브리드 기체용 최적 활공각(Best-Glide Pitch) 및 최소 침하율 속도 유지 제어 법칙(`MAC_EMERGENCY_GLIDE`)과 AMM의 전방 개활지/최인접 패드 비상 활공 경로 생성 연동
    - [ ] **TASK-132-3**: 전사 사양서·`config/protocol_contracts.json` 동기화, 추력 상실 E2E 및 3대 가드레일(`verify_contracts.py`·`verify_runtime_wiring.py`·`run_boot_smoke.py`) 검증 후 사양서 `Implemented` 승격

- [ ] **TASK-129: [3순위 / 적응형 비행 제어] 비행 중 질량·무게중심(CoG) 변화 및 구동기 열화 대응 실시간 트림 보정기** (`src/1_control/vas/`, `src/1_control/tca/`, `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`, `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md`)
  - **권장 착수 순위**: **3순위** (Spec-First 절차상 `VAS`·`TCA` 사양서 `Approved` 개정 선행)
  - **사양서 상태**: 추후 착수 시점 개정 예정 (현재 `VAS`·`TCA` `Implemented` → 착수 시점 Spec-First `Approved` 개정 및 연동)
  - **배경 및 필요성**: Alignment는 격납고 정지 상태의 관성 텐서만 측정하므로, 비행 중 화물 투하(TASK-401), 연료 소모, 또는 특정 추진기/조종면의 DEGRADED 판정 시 피치·롤 정적 불균형과 적분항 와인드업(Wind-up)이 발생함.
  - **주요 작업**:
    - [ ] **TASK-129-1**: VAS 수평 정속 비행 구간 감지 및 지속 편향 PID 적분항을 정적 트림 오프셋으로 이관하는 적응형 트림 학습기(Adaptive Trim Estimator) 구현 (비정상 급기동 시 학습 동결 가드 포함)
    - [ ] **TASK-129-2**: TCA 구동기 상태(DEGRADED / TOTAL_LOSS) 피드백 수신 시 잔여 정상 추진기의 추력 배분 행렬(Control Allocation Matrix) 실시간 재가중치 계산

---

## 📋 2. 예정 백로그 (Planned Backlog — Phase 1 & 2)

### ⏸️ 연기·보류 과제 (Deferred / On-Hold)

- [ ] **[연기] TASK-104: Docking Arm 결합 암 제어기 구현** (`src/0_infra/docking_arm/`)
  - **사양서 상태**: `docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md` (`Approved`)
  - 2축 로봇 암 포획·인입 및 엄빌리컬 보급 시퀀스 (`AMM (Node 03)` 주도 4단계 랑데부 연동; 일정 연기 — **착수 전 `TASK-016` 도출 선행 조건**: `§4.2` `CH 50002` ATC 직접 제어 제거 및 `GAC Base_sec+1` 경유 통일, `Base+5` 기체별 바인딩을 `Base_sec+10+Idx`로 일원화, `§3.4` `seq`·`"ABORTED"` stage 보완; 구현 시 `manifest.lua`·`verify_spec_status.py`(`Implemented` 전이)·`config/protocol_contracts.json`·`tools/run_boot_smoke.py` 등록 필요)
- [ ] **[연기] TASK-108: Tower ATC (Sector 0, `CH 50001/50002`) 광역 항공교통 관제 노드 구현**
  - **사양서 상태**: 별도 사양서 미작성 (마스터 ICD `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` Interface I-5 기반 `AMM (Node 03)` 교신 규격; 착수 전 사양서 Draft → Approved 또는 ICD 연계 필요)
  - 광역 공역 진입/이탈 스케줄링 및 섹터 `GAC` 핸드오프 프로토콜 구현 (일정 연기)
- [ ] **[연기] TASK-401: PAYLOAD 계층(Zone 3) 통신 스키마 정의** (`docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`, `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`, `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`, `docs/specs/4_mission/`)
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

- [x] **TASK-302: CC:Tweaked 포켓 컴퓨터(Pocket PDA) 휴대용 원격 관제·지상 콘솔 링크·비상 E_STOP 단말 구축 (`TASK-302-1..4`)** (완료일: 2026-11-21)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-21-task-302-pocket-pda.md`
  - **결과**: `src/0_infra/pocket_pda/` (`26×20` 3-탭 TUI·RSSI 분류·듀얼 기체 선택·단일키 `[X]` `E_STOP`+`DUMP_NOW`·`[L]` `LAND_NEAREST`·`Alignment`/`FDR` 원격 제어) 및 `AMM`/`FDR`(`0 tx`)/`Alignment` 연동 구현, `POCKET_PDA v1.0.0`·`ALIGNMENT v2.10.0`·`FDR v0.6.0`·`AMM v2.8.0`·`GCS v1.5.0` `Implemented` 승격(`19종: 15 Implemented, 4 Approved`), `manifest.lua`(`16`모듈)·`gdrive_mapping.json`(`142`파일)·`playbook/0_infra/pocket_pda.md`(`16`종)·`test_e2e_pocket_pda_remote.lua`(`11`스위트 `25`케이스) 통합.

- [x] **TASK-015: 전 계층 코드베이스·신규 추가 모듈/프로그램 통합 플레이북 체계 구축 (`TASK-015-1..6`)** (완료일: 2026-11-20)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-20-task-015-unified-playbook-suite.md`
  - **결과**: `playbook/README.md` 및 15종 인게임 운용 매뉴얼(`0_development/{alignment,fdr,installer,ota,sensors}`, `0_infra/{gps,gcs,gac,landing_pad,runway}`, `1_control/{vas,tca}`, `2_guidance/fcp`, `3_planning/{amm,amm_mission_editor}`) 구축, `tools/verify_playbooks.py` + `tests/harness/test_verify_playbooks.py` (`8/8 PASS`) 및 `test_tools_integrity.py` 등록, `README.md`·`GEMINI.md`·`skill-workflows.md` 동기화; `src/**`·`docs/specs/**`·`config/*.json` `0 diff` 유지.

- [x] **TASK-019: 사양 경량화·인라인 피어 버전 배지 폐지·18종 검증 보완 (`TASK-019-1..2`)** (완료일: 2026-11-20)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-20-task-019-spec-lightweighting-and-sync-cost.md`
  - **결과**: 18종 사양서 인라인 피어 버전 배지 `178 → 0`(버전 SSOT = 사양서 헤더 + 마스터 ICD `§5.1`), `verify_all_specs.py` 18종 확장·`Rule 10` 가드, `VAS`·`AMM`·`FCP` 제자리 `Extract`(5종 합계 `-110,317 B`), `Implemented` 사양 6메시지 드리프트 해소; 전 18종 `+0.0.1`(`14 Implemented, 4 Approved`), 단위 `656/656`·E2E `23/23`·부트 `13/13`·하네스 `169/169` PASS.

- [x] **TASK-018: 코드 복제·분기·사문화 정리 (`installer.lua` 단일 SSOT화, 복제 분기 3건 정합화, 사문화 함수 17·설정키 19 제거) (`TASK-018-1..3`)** (완료일: 2026-11-19)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-19-task-017-018-protocol-and-code-hygiene.md` (Locked Rulings `R4`·`R5`)
  - **결과**: 루트 `/installer.lua` 단일 SSOT, `save_flight_state`·`quat.to_euler`·`tca/config_manager` 분기 정합화, 사문화 함수 17종·미사용 설정키 19종 제거; `FDR v0.5.0`·`INSTALLER v1.3.0`·`LANDING_PAD v2.6.0`·`VAS v1.26.0`·`TCA v1.15.0`·`FCP v2.6.0`·`AMM v2.7.0` 승격, 단위 `656/656`·E2E `23/23` PASS, 돌연변이 `25/25 KILLED`.

- [x] **TASK-017: 프로토콜·계약 정합화 (Zone 3 `30..39` 확장, 누락 계약 14종 편입, 사문화 RX·미소비 필드 정리) (`TASK-017-1..3`)** (완료일: 2026-11-19)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-19-task-017-018-protocol-and-code-hygiene.md` (Locked Rulings `R1`·`R2`·`R3`)
  - **결과**: `protocol_contracts.json` +14패킷·마스터 ICD `v1.39.0`·구조도 `v2.22.0`, `AMM` Zone 3 `20..39`, `MSG_RUNWAY_TOUCHDOWN`/`VACATED` 빌더, `BASE_PLUS_5_INFRA_RESPONSES` 구형 14종 제거, `R2` PBIT 게이트·`R3` 경계 구현; `verify_contracts.py` `0 errors`, E2E `23/23` PASS, 동결 `asa/**` `0 diff`.

- [x] **TASK-016: 제품 아키텍처(L1~L4) 효율성·효용성 감사 및 계측·회귀 가드 구축** (완료일: 2026-11-18)
  - **설계서·보고서**: `docs/superpowers/specs/2026-11-18-task-016-architecture-efficiency-audit-design.md`, `reports/underReview/Architecture_Efficiency_Audit_1_11182026.md`
  - **결과**: E2E 노드/버스 프로파일러(`--profile --check-baseline`), `tools/audit/` 6종 및 `config/audit_baselines.json` 편입, Decision Gate A1~A5 기반 후속 `TASK-017..021`·`TASK-104` 선행 조건 도출; 하네스 `152/152`·E2E `23/23` PASS, `audit guard` `0 errors, 0 warnings`.

- [x] **TASK-128: GPS 위성군 헬스 감시 및 청크 경계(Chunk Border) 추측 항법(DR) 블렌딩 가드 (`TASK-128-1..3`)** (완료일: 2026-11-18)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-18-task-136-131-128-safety-and-nav-integrity.md`
  - **결과**: `GPS` `MSG_NAV_QUALITY`, `VAS`·`FCP` `1,500ms` DR 홀드오버·10틱 청크 경계 보간·`HOLD_LEVEL`, `AMM` `on_nav_quality`; `GPS v2.4.0`·`VAS v1.25.0`·`FCP v2.5.0`·`AMM v2.6.0` 승격, E2E Scenario 8 통과.

- [x] **TASK-131: 비행 전 자동 자가진단(PBIT) 및 구동기 응답 검증 시퀀서 (`TASK-131-1..4`)** (완료일: 2026-11-18)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-18-task-136-131-128-safety-and-nav-integrity.md`
  - **결과**: `VAS` 5단계 `evaluate_pbit`·`MSG_PBIT_REQ`/`REPORT`, `TCA` 지상 한정 `< 5%` `pbitWiggle`, `AMM` `PBIT_TAKEOFF_INTERLOCK`; `VAS v1.25.0`·`TCA v1.14.0`·`AMM v2.6.0` 승격, 다중 노드 PBIT E2E 통과.

- [x] **TASK-136: 기체 블록화(Disassembly)·재조립 상태 인터록 및 주변장치 재바인딩 검증기 (`TASK-136-1..4`)** (완료일: 2026-11-18)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-18-task-136-131-128-safety-and-nav-integrity.md`
  - **결과**: `Alignment` `peripheralManifest`·토폴로지 해시, `VAS` 재조립 검증·`> 5%` 질량 편차 `recalibrationRequired` 래치·공중 해제 시 `E_STOP`, `TCA` `logicalBindingMap` 리바인딩; `ALIGNMENT v2.9.0`·`VAS v1.25.0`·`TCA v1.14.0` 승격, Scenario 4 & 8 E2E 통과.

- [x] **TASK-406: AMM Mission Editor 광역 줌·실시간 노드 자동등록/1분 TTL·대상 필터·Inspection 모드 (`TASK-406-1..5`)** (완료일: 2026-11-18)
  - **실행 계획서**: `docs/superpowers/plans/2026-11-18-task-405-406-amm-editor-live-lan-and-inspection.md`
  - **결과**: `GAC` `position`·Centroid 폴백, `GCS` `60003` `MSG_GPS_NODE_HEARTBEAT`·`60s` TTL, WebUI 광역 줌(`0.01..4.0`)·노드 자동 등록·필터·`Inspection` 모드; `AMM_MISSION_EDITOR v0.6.0`·`GCS v1.4.0`·`GAC v1.7.0` 승격, 에디터 `30/30`·브리지 `4/4` PASS.
