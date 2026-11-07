# 기체 40채널·4-Zone 런타임 코드 동기화 (TASK-001) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기체 및 지상 인프라 5대 핵심 런타임 코드베이스(`vas`, `tca`, `fcp`, `alignment`, `gps`)의 채널 연산식, 서브채널 Zone 매핑, 교정/재바인딩/측위 패킷 스키마를 마스터 ICD(`v1.21.0`)의 40채널 대역폭($BW=40$) 및 Zero-Fallback 규격과 일치시킨다.

**Architecture:** 기체 전용 주파수 대역(`10000 ~ 49999`)을 기체 번호 $N \in [1, 1000]$ 기준 $Base = 10000 + (N - 1) \times 40$의 40채널 블록으로 단일화하고, 내부 오프셋을 Zone 1(`+0~+9` 비행 코어), Zone 2(`+10~+19` 구동계), Zone 3(`+20~+29` 탑재체), Zone 4(`+30~+39` 편대/확장)로 직교 분리한다. 정적 `Base+4` 교정 채널 및 구 `Base+6`/`Base+7` 구동 채널, 구 `1000`/`30004`/`10045` 하드코딩과 이중 키 폴백(`or cfg.mode` 등)을 전면 제거하고, 격납고 동적 바인딩(`Base+0` $\to$ `Base_hangar + 0,1,3`), 2단계 채널 재바인딩(`MSG_CHANNEL_REBIND`), GPS 비동기 측위(`CH 60001` $\leftrightarrow$ `Base+5`) 계약을 5개 코드베이스 전반에서 단일 와이어 스키마로 정렬한다.

**Tech Stack:** Lua 5.2 (CC:Tweaked Cobalt VM), CraftOS-PC Headless 단위 테스트 러너(`python tools/run_unit_tests.py`), 정적 문법/도메인 검증기(`python scratch/validate_lua_syntax.py`, `python scratch/verify_all_specs.py`)

**Specifications (SSOT):**
- `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.21.0`, `Approved`)
- `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.8.0`, `Approved`)
- `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (`v1.13.0`, `Approved`)
- `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (`v1.9.0`, `Approved`)
- `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (`v1.11.0`, `Approved`)
- `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (`v2.5.0`, `Approved`)
- `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v2.1.0`, `Approved`)

---

## Global Constraints

1. **기체 40채널 블록 및 4-Zone 오프셋 불변식**:
   - 대역폭 상수: `CRAFT_BANDWIDTH = 40`, 유효 기체 인덱스 $N \in [1, 1000]$ (정수), `CRAFT_BASE_MIN = 10000`, `CRAFT_BASE_MAX = 49960` (`49960 + 39 = 49999`).
   - 기본 연산식: `Base = 10000 + (N - 1) * 40` (`N = 1`일 때 `10000`, `N = 2`일 때 `10040`).
   - 유효 Base 검증 조건: `type(base) == "number" and base >= 10000 and base <= 49960 and ((base - 10000) % 40 == 0)`.
   - **Zone 1 (`+0 ~ +9`, Flight Core)**: `+0` `c2` (`CH_OPERATOR_C2`), `+1` `guidance` (`CH_FLIGHT_GUIDANCE`), `+2` `telemetry` (`CH_TELEMETRY`), `+3` `mfd` (`CH_MFD_STATE`), `+4` `navSensor` (`CH_NAV_SENSOR`, 온보드 센서 전용 — 지상 교정 용도 폐지), `+5` `clientReply` (`CH_CLIENT_REPLY`, GPS/관제 P2P 회신), `+6 ~ +9` 예비(구 `+6` TCA, `+7` ASA 폐지).
   - **Zone 2 (`+10 ~ +19`, Actuation)**: `+10` `actuation` (`CH_THRUST_ACTUATION`, VAS $\leftrightarrow$ TCA), `+11` `aero` (`CH_SURFACE_ACTUATION`, VAS $\leftrightarrow$ ASA), `+12 ~ +19` 예비.
   - **Zone 3 (`+20 ~ +29`, Payload)**: `+20` `payloadBus` (`CH_PAYLOAD_BUS`), `+21` `weaponBus` (`CH_WEAPON_BUS`).
   - **Zone 4 (`+30 ~ +39`, Formation/Expansion)**: `+30` `formationLink` (`CH_FORMATION_LINK`).
2. **격납고 베이 및 글로벌 인프라 대역 상수**:
   - 격납고 교정 블록(`101 ~ 200`): `Base_hangar = 101 + (bayId - 1) * 10` (`bayId = 1 .. 10`). `+0` `calibrationCmd`, `+1` `calibrationTelem`, `+2` `facilityInterlock`, `+3` `tapDirect`.
   - 글로벌 인프라 대역(`50000 ~ 60020`): `50000` `CH_BOOTSTRAP`, `50001` `CH_ATC_COMM`, `50002` `CH_ATC_FACILITY`, `50003` `CH_FACILITY_BEACON`, `50004` `CH_GAC_DISPATCH`, `60001` `CH_GPS_PING`, `60002` `CH_GPS_SERVICE`, `60003` `CH_GPS_NODE_IN`, `60004` `CH_GPS_MGMT`.
3. **Zero-Fallback 및 단일 와이어 스키마 규칙**:
   - 수신단 및 설정 로더에서 구버전 필드 폴백(`cfg.interactionMode or cfg.mode`, `ch == 60001 or ch == 30004`, `t == "MSG_GPS_RESPONSE" or t == "MSG_GPS_FIX"`, `p.transactionId or p.rebindId`) 작성을 금지한다.
   - **교정 바인딩 계약 (`Alignment` $\leftrightarrow$ `VAS` $\leftrightarrow$ `TCA`)**:
     - `MSG_CALIBRATION_INIT` (`Align` $\to$ `VAS`, `Base + 0`): `{ stationId, bayId, baseHangarChannel, targetCraftDomain }`
     - `MSG_CALIB_BAY_BIND` (`VAS` $\to$ `TCA`/`ASA`, `Base + 10` / `Base + 11`): `{ action = "OPEN" | "CLOSE", stationId, bayId, baseHangarChannel, bayCalibrationTap = baseHangar + 3, bayCalibrationCmd = baseHangar + 0 }`
     - `MSG_CALIBRATION_INIT_ACK` (`VAS` $\to$ `Align`, `Base_hangar + 1`): `{ status = "READY", bayId, aircraftDomainId, baseChannel }`
     - `MSG_CALIB_START` (`Align` $\to$ `VAS`, `Base_hangar + 0`): `{ action = "ENTER_CALIBRATION" | "ABORT_CALIBRATION", stationId, targetThruster, timeoutSec }`
     - `MSG_CALIB_ACK` (`VAS` $\to$ `Align`, `Base_hangar + 1`): `{ profileId, status = "ACCEPTED" | "REJECTED" }`
     - `MSG_CALIBRATION_CLOSE` (`Align` $\to$ `VAS`, `Base_hangar + 0`): `{ stationId, bayId, action = "CLOSE_SESSION", reason }`
     - `MSG_CALIBRATION_CLOSE_ACK` (`VAS` $\to$ `Align`, `Base_hangar + 1`): `{ bayId, status = "CLOSED" }`
   - **동적 채널 재바인딩 계약 (`FCP` $\leftrightarrow$ `VAS` $\leftrightarrow$ `TCA`)**:
     - 요청/확정/롤백 단일 패킷 타입: `type = "MSG_CHANNEL_REBIND"`, `payload = { transactionId, action = "PREPARE" | "COMMIT" | "ROLLBACK", oldBaseChannel, newBaseChannel, bandwidth = 40 }` (별도 `MSG_CHANNEL_REBIND_COMMIT` 타입 폐기).
     - 응답 패킷 타입: `type = "MSG_CHANNEL_REBIND_ACK"`, `payload = { transactionId, nodeId, status = "READY", subNodesOk = true }`.
   - **GPS 비동기 측위 계약 (`FCP` $\leftrightarrow$ `GPS`)**:
     - 요청: `type = "MSG_GPS_REQUEST"` (`CH 60001`, reply `Base + 5`), `payload = { replyChannel = Base + 5, altitudeY, clientType = "AIRCRAFT", clientSeq }`.
     - 응답: `type = "MSG_GPS_RESPONSE"` (`domainId = "GPS_BASE_NET"`, `Base + 5`), `payload = { targetClient, clientSeq, status = "FIX_OK" | "FIX_DEGRADED" | ..., position = { x, z }, accuracy, hdop, nodeCount, selectedNodes }`.
4. **런타임 및 도메인 제약 (`.agent/rules/cc-tweaked-runtime.md`, `domain-aeronautics.md`, `AGENTS.md`)**:
   - Lua 5.3+ 연산자(`//`, `<<`, `>>`, `&`, `|`, 단항/이항 `~`) 및 호스트 OS API(`os.execute`, `os.remove`, `os.rename`, `os.exit`, `io.popen`, `getfenv`, `setfenv`) 사용 금지.
   - Valkyrien Skies 관련 식별자(`ship`, `vs2`, `kontraption:` 등) 사용 금지.
   - 코드, 주석, 커밋 메시지, 문서 내 미검증 과장 표현(`no-overclaim` 금지어 목록) 작성 금지; 기존 무관한 주석은 삭제·축약하지 않는다.
5. **Git 스테이징 격리 규칙**:
   - 현재 워킹 트리에 선행 작업의 미커밋 변경분이 존재할 수 있으므로 `git add -A` 또는 `git add .` 사용을 금지하고, 각 태스크에서 수정한 파일 경로만 명시적으로 스테이징한다.
   - PowerShell에서 `git` 미인식 시 `& "C:\Program Files\Git\cmd\git.exe"` 절대 경로를 사용한다.

---

## Review Focus

단순 상수 치환만으로는 누락되기 쉬운 5가지 경계/연동 실패 모드를 정의하고, 각 소유 태스크에 검증 테스트를 고정한다.

1. **비정렬/범위 이탈 Base 채널 입력 (`10060`, `N=0`, `N=1001`, `Base=50000`)**:
   - 기존 `fcp_config.json`(`10060`)이나 구 20채널 오프셋(`10020`)이 그대로 유입되면 `(base - 10000) % 40 ~= 0`이 되어 인접 기체의 Zone 2(`+10~+19`) 및 Zone 3(`+20~+29`) 대역을 침범한다.
   - **고정 위치**: Task 1(`test_vas_core.lua`), Task 2(`test_tca_core.lua`), Task 3(`test_fcp_core.lua`)에서 `compute_base` / `is_valid_base` 경계값(`10000`, `10040`, `49960` 허용; `10020`, `10060`, `9960`, `50000` 거부 또는 정규화) 단언문으로 검증한다.
2. **2단계 채널 재바인딩(`MSG_CHANNEL_REBIND`) 계층 간 스키마·라우팅 불일치**:
   - FCP는 `MSG_CHANNEL_REBIND`(`transactionId`, `action = "PREPARE"|"COMMIT"|"ROLLBACK"`, `bandwidth = 40`)를 송출하나, 기존 TCA는 `rebindId`와 별도 `MSG_CHANNEL_REBIND_COMMIT` 타입 및 `newBase + 6`을 참조하고 VAS는 중계 핸들러가 없어 재바인딩 시 구동계 링크가 단절된다.
   - **고정 위치**: Task 1(`test_vas_core.lua`), Task 2(`test_tca_core.lua`), Task 3(`test_fcp_core.lua`)에서 동일 `transactionId` 기반 `PREPARE` $\to$ `MSG_CHANNEL_REBIND_ACK` $\to$ `COMMIT` / `ROLLBACK` 전 과정을 모의 모뎀으로 검증한다.
3. **평시 비행 중 VAS의 `Base + 3` (`CH_MFD_STATE`) 송출 침묵 위반**:
   - 기존 `vas/modules/telemetry_feeder.lua`가 `activeSource == "FCP"`인 정상 비행 중에도 4틱마다 `Base + 3`으로 패킷을 송출하여 FCP의 5Hz 통합 MFD 다운링크와 충돌한다.
   - **고정 위치**: Task 1(`test_vas_core.lua`)에서 `activeSource == "FCP"` + `NORMAL` 상태일 때 `Base + 3` 송출 0건, `activeSource == "MFD_ACRO"`일 때 매 틱(20Hz) 송출, FCP 타임아웃 페일세이프(`FAILSAFE_HOLD`/`EMERGENCY_LAND`)일 때 4틱(5Hz) 폴백 송출을 검증한다.
4. **격납고 교정 세션의 `Base+0` 직결 바인딩 및 종료 시 채널 미해제**:
   - 기존 Alignment가 구버전 `1000` 채널로 `MSG_CALIBRATION_INIT`를 송출하거나 종료 시 `MSG_CALIBRATION_CLOSE`를 생략하면 VAS와 TCA의 `Base_hangar + 0, +1, +3` 채널이 닫히지 않고 열린 채 잔류한다.
   - **고정 위치**: Task 1(`test_vas_core.lua`), Task 2(`test_tca_core.lua`), Task 4(`test_alignment_core.lua`)에서 `Base+0`(`10000`) 바인딩 개시 $\to$ `MSG_CALIB_BAY_BIND`(`Base+10`/`11`) 전파 $\to$ `Base_hangar+1` 텔레메트리/ACK $\to$ `MSG_CALIBRATION_CLOSE` 수신 후 모뎀 채널 완전 닫힘(`isOpen == false`)을 검증한다.
5. **FCP ↔ GPS `Base + 5` 측위 링크 단절 및 클라이언트 기본 채널 충돌**:
   - FCP `main.lua`의 구 `sas_runtime` 참조 오류, `network_manager`의 `"GPS_BASE_NET"` 도메인 차단 및 구 `MSG_GPS_FIX` 대기, `fcp_runtime`의 `{ requestId }` 불완전 페이로드, `nav_engine.filter_gps`의 `position.x/z` 미참조, GPS `client_core.new()`의 `10000 + (compId % 50000)` 임의 채널 할당이 맞물려 측위 패킷이 폐기되거나 기체 제어 채널과 충돌한다.
   - **고정 위치**: Task 3(`test_fcp_core.lua`) 및 Task 5(`test_gps_core.lua`)에서 `MSG_GPS_REQUEST`가 `GPS protocol.validatePacket`을 통과하고 `MSG_GPS_RESPONSE`(`domainId = "GPS_BASE_NET"`, `replyChannel = 10005`)가 `FCP network_manager` $\to$ `nav_engine.filter_gps`까지 수용되는지 검증한다.

---

## File Structure

- **Task 1 — VAS (`TASK-001-1`)**:
  - Modify: `src/1_control/vas/modules/network_manager.lua` — 40채널/4-Zone 오프셋 상수, `compute_base`/`is_valid_base`, 부팅 시 `Base + 0, 1, 10, 11` 개방(정적 `+4` 폐지), `MSG_CALIBRATION_INIT`/`CLOSE` 동적 베이 개폐 및 `MSG_CALIB_BAY_BIND` 전파, `MSG_CHANNEL_REBIND` 2단계 캐스케이드.
  - Modify: `src/1_control/vas/modules/telemetry_feeder.lua` — 정상 비행 시 `Base + 3` 침묵(`MFD_ACRO` 20Hz / 페일세이프 5Hz만 송출), 교정 세션 바인딩 중 `Base_hangar + 1` 동시 20Hz 스트리밍.
  - Modify: `src/1_control/vas/node_fcp.lua`, `src/1_control/vas/node_tca.lua`, `src/1_control/vas/node_wap.lua` — HIL 시뮬레이션 노드 채널을 01호기 40채널 기준(`10001`, `10002`, `10010`, `10011`) 및 `interactionMode = "REDSTONE"`으로 동기화.
  - Modify: `tests/1_control/vas/test_vas_core.lua` — 40채널/4-Zone 매핑, `Base+3` 침묵 가드, 격납고 동적 바인딩/해제, 채널 재바인딩 캐스케이드 단위 테스트 추가.
- **Task 2 — TCA (`TASK-001-2`)**:
  - Modify: `src/1_control/tca/modules/config_manager.lua` — `CRAFT_BANDWIDTH = 40`, `compute_base(n)` (`10000 + (n - 1) * 40`), 구 20채널(`10000 + (n - 1) * 20`, `10000 + n * 20`, `+6`) 설정의 40채널/`+10` 자동 마이그레이션, 정적 `channels.calibration` 제거.
  - Modify: `src/1_control/tca/modules/channel_rebind_handler.lua` — `newBase + 10` 개폐, 단일 `MSG_CHANNEL_REBIND`(`action = "PREPARE" | "COMMIT" | "ROLLBACK"`, `transactionId`) 처리.
  - Modify: `src/1_control/tca/modules/discovery_handler.lua`, `src/1_control/tca/modules/tca_daemon.lua`, `src/1_control/tca/modules/status_reporter.lua`, `src/1_control/tca/modules/tui_dashboard.lua` — `cfg.mode` 폴백 제거(Zero-Fallback), `targetGroup` 디스커버리 매칭 보강, `10010`(`Base + 10`) 기본값 및 단일 `MSG_CHANNEL_REBIND` 디스패치 동기화.
  - Modify: `src/1_control/tca/main.lua`, `src/1_control/tca/tools/tca_setup.lua`, `src/1_control/tca/node_tca.lua`, `src/1_control/tca/node_core_sim.lua` — 기본 채널 `10010` 동기화, 정적 `calibration = 10004` 및 `cfg.mode` 제거.
  - Modify: `tests/1_control/tca/test_tca_core.lua` — 기존 20채널/`+6` 단언문을 40채널/`+10`으로 갱신하고 마이그레이션, 격납고 동적 바인딩, `MSG_CHANNEL_REBIND` 2단계 트랜잭션 테스트 추가.
- **Task 3 — FCP (`TASK-001-3`)**:
  - Modify: `src/2_guidance/fcp/config/fcp_config.json` — `baseChannel = 10000`, `bandwidth = 40`, `mfdInstrumentChannel = 10003`, `bootstrapChannel = 50000`, `gpsPingChannel = 60001`, `gpsServiceChannel = 60002` 동기화.
  - Modify: `src/2_guidance/fcp/main.lua` — 구 `sas_runtime` / `config/sas_config.json` 참조를 `fcp_runtime` / `config/fcp_config.json`으로 복구 및 `fcp_main` 식별자 정리.
  - Modify: `src/2_guidance/fcp/modules/channel_sentinel.lua` — `BANDWIDTH = 40`, 기본 `baseChannel = 10000`, `bootstrapChannel = 50000`, 40채널 정렬 검증(`is_valid_base`), `MSG_BLOCK_REQUEST`/`ASSIGN` 및 `MSG_CHANNEL_REBIND`(`bandwidth = 40`) 동기화.
  - Modify: `src/2_guidance/fcp/modules/network_manager.lua`, `src/2_guidance/fcp/modules/nav_engine.lua`, `src/2_guidance/fcp/fcp_runtime.lua`, `src/2_guidance/fcp/modules/ui_renderer.lua` — 4-Zone 오프셋 상수, 재바인딩 시 소켓 절체(`rebind_aircraft_channels`), `"GPS_BASE_NET"` 허용 도메인 추가, `MSG_GPS_REQUEST` 표준 4필드 송출 및 `MSG_GPS_RESPONSE`(`position.x/z`, `FIX_OK`/`FIX_DEGRADED`) 수신 융합, UI 기본 채널 `10000` 동기화.
  - Modify: `src/2_guidance/fcp/node_fcp.lua`, `src/2_guidance/fcp/node_vas_sim.lua`, `src/2_guidance/fcp/node_wap_sim.lua`, `src/2_guidance/fcp/node_infra_sim.lua` — `10001~10003`, `10011`(`Base+11`), `60001`(`30004` 제거) 및 `MSG_GPS_RESPONSE` 회신으로 동기화.
  - Modify: `tests/2_guidance/fcp/test_fcp_core.lua` — `fcp_config.json` 40채널 검증, `main.lua` 로더, `channel_sentinel` 부트스트랩/재바인딩, `MSG_GPS_REQUEST`/`RESPONSE` 왕복 융합 테스트 추가.
- **Task 4 — Alignment (`TASK-001-4`)**:
  - Modify: `src/0_development/alignment/modules/align_master.lua`, `src/0_development/alignment/main.lua` — `CRAFT_BANDWIDTH = 40`, `compute_craft_base(aircraft_number)` (`10000 + (N - 1) * 40`), 구 `1000` 기본값 제거(`10000` 적용), `tapDirect = 104` 키 정규화, `HANDSHAKE` 완료 시 `MSG_CALIB_START` 송출 및 `release_channels` 시 `MSG_CALIBRATION_CLOSE` 송출 후 베이 채널 해제.
  - Modify: `tests/0_development/alignment/test_alignment_core.lua` — 기체 번호별 40채널 Base 산출(`N=1 -> 10000`, `N=2 -> 10040`, 범위 이탈 거부), `MSG_CALIBRATION_INIT` `Base+0` 송출, `MSG_CALIB_START` 및 `MSG_CALIBRATION_CLOSE` 세션 해제 테스트 추가.
- **Task 5 — GPS (`TASK-001-5`)**:
  - Modify: `src/0_infra/gps/modules/protocol.lua`, `src/0_infra/gps/modules/client_core.lua`, `src/0_infra/gps/client_entry.lua`, `src/0_infra/gps/installer.lua` — 기체 40채널 회신 상수(`CRAFT_BASE_MIN = 10000`, `CRAFT_BANDWIDTH = 40`, `CRAFT_REPLY_OFFSET = 5`, `DEFAULT_REPLY_CHANNEL = 10005`, `computeCraftReplyChannel(n)`), `client_core` 기본/도메인별 회신 채널을 `Base + 5`(`10005`, `AIRCRAFT_02 -> 10045`)로 정규화하여 제어 채널 충돌 제거, `client_entry.lua` 구 `10045` 기본값을 `10005`로 수정, `installer.lua` 노드 설정에 4채널(`60001~60004`) 구조 반영.
  - Modify: `tests/0_infra/gps/test_gps_core.lua` — `computeCraftReplyChannel`, `client_core` 도메인별 `Base+5` 자동 매핑 및 `MSG_GPS_REQUEST`/`MSG_GPS_RESPONSE` 채널 정합성 테스트 추가.
- **Task 6 — 통합 검증 및 `TASK.md` 완료 상태 동기화**:
  - Run: 구버전 채널/폴백 잔존 정적 스캔, 전체 단위 테스트 러너(`python tools/run_unit_tests.py --require-tests --clean-orphans`) 및 정적 문법 검사기(`python scratch/validate_lua_syntax.py`) 실행.
  - Modify: `TASK.md`의 `TASK-001` 및 하위 항목(`TASK-001-1 ~ TASK-001-5`)을 `[x]`로 완료 갱신(5대 사양서의 `Approved` $\to$ `Implemented` 전이는 후속 `TASK-002` 완료 후 `TASK-003`에서 일괄 수행).

---

### Task 1: VAS (`TASK-001-1`) 40채널·4-Zone 매핑, `Base+3` 침묵 가드 및 동적 바인딩/재바인딩 구현

**Files:**
- Modify: `src/1_control/vas/modules/network_manager.lua`
- Modify: `src/1_control/vas/modules/telemetry_feeder.lua`
- Modify: `src/1_control/vas/node_fcp.lua`
- Modify: `src/1_control/vas/node_tca.lua`
- Modify: `src/1_control/vas/node_wap.lua`
- Test: `tests/1_control/vas/test_vas_core.lua`

**Interfaces:**
- Consumes:
  - `MSG_CALIBRATION_INIT` on `Base + 0` (`{ stationId, bayId, baseHangarChannel, targetCraftDomain }`)
  - `MSG_CALIB_START`, `MSG_PROFILE_SYNC`, `MSG_CALIBRATION_CLOSE` on `Base_hangar + 0`
  - `MSG_CHANNEL_REBIND` on `Base + 1` (`{ transactionId, action = "PREPARE"|"COMMIT"|"ROLLBACK", oldBaseChannel, newBaseChannel, bandwidth = 40 }`)
  - `MSG_CHANNEL_REBIND_ACK` on `Base + 10` / `Base + 11` (`{ transactionId, nodeId, status = "READY", subNodesOk }`)
- Produces:
  - `MSG_CALIB_BAY_BIND` on `Base + 10`, `Base + 11` (`{ action = "OPEN"|"CLOSE", stationId, bayId, baseHangarChannel, bayCalibrationTap, bayCalibrationCmd }`)
  - `MSG_CALIBRATION_INIT_ACK`, `MSG_CALIB_ACK`, `MSG_CALIBRATION_CLOSE_ACK`, `MSG_FLIGHT_TELEMETRY` on `Base_hangar + 1`
  - `MSG_CHANNEL_REBIND` cascade on `Base + 10`, `Base + 11`; `MSG_CHANNEL_REBIND_ACK` (`nodeId = "01_core"`) on `Base + 1`

- [ ] **Step 1: `tests/1_control/vas/test_vas_core.lua`에 실패하는 단위 테스트 추가**

`tests/1_control/vas/test_vas_core.lua` 상단에 `network_manager`, `telemetry_feeder`, `state_machine` 모듈 `require`를 추가하고, 파일 하단에 아래 4개 검증 케이스를 추가한다:
1) `network_manager.compute_base(1) == 10000`, `compute_base(2) == 10040`, `compute_base(1000) == 49960`, `is_valid_base(10060) == false`, `is_valid_base(50000) == false` 및 `network_manager.init({ aircraftDomainId = "AIRCRAFT_01" })` 호출 시 기본 `baseChannel == 10000`, Zone 1~4 채널(`c2 = 10000`, `guidance = 10001`, `telemetry = 10002`, `mfd = 10003`, `navSensor = 10004`, `clientReply = 10005`, `actuation = 10010`, `aero = 10011`, `payloadBus = 10020`, `weaponBus = 10021`, `formationLink = 10030`)이 설정되고 무선 모뎀에 `10000`, `10001`, `10010`, `10011`만 개방되며 정적 `10004`는 개방되지 않음(`assert_false(wirelessModem.isOpen(10004))`) 검증.
2) `telemetry_feeder`가 `activeSource == "FCP"` 및 `currentState == "NORMAL"`일 때 8틱 연속 실행해도 `Base + 2`(`10002`)만 송출하고 `Base + 3`(`10003`)은 송출하지 않으며, `activeSource == "MFD_ACRO"`일 때는 매 틱 `10003`으로 `MSG_MFD_STATE`를 송출하고, `FAILSAFE_HOLD`일 때는 4틱마다 `10003`으로 폴백 송출하는지 검증.
3) `Base + 0`(`10000`)으로 `MSG_CALIBRATION_INIT`(`bayId = 2`, `baseHangarChannel = 111`) 수신 시 베이 채널 `111`, `112`, `114`가 동적 개방되고 `10010`/`10011`로 `MSG_CALIB_BAY_BIND`(`action = "OPEN"`)가 전파되며 `112`로 `MSG_CALIBRATION_INIT_ACK`가 회신되고, 이후 `telemetry_feeder`가 `112`에도 텔레메트리를 복제 송출하며, `111`로 `MSG_CALIBRATION_CLOSE` 수신 시 `MSG_CALIB_BAY_BIND`(`action = "CLOSE"`) 전파 및 `112`로 `MSG_CALIBRATION_CLOSE_ACK` 송출 후 `111`, `112`, `114`가 모두 닫히는지(`isOpen == false`) 검증.
4) `Base + 1`(`10001`)으로 `MSG_CHANNEL_REBIND`(`transactionId = "TX-1"`, `action = "PREPARE"`, `oldBaseChannel = 10000`, `newBaseChannel = 10040`, `bandwidth = 40`) 수신 시 `10040`, `10041`, `10050`, `10051`이 사전 개방되고 `10010`/`10011`로 `PREPARE`가 중계되며 `10001`로 `MSG_CHANNEL_REBIND_ACK`가 회신되고, `action = "COMMIT"` 수신 시 구 채널(`10000`, `10001`, `10010`, `10011`)이 닫히고 `state.baseChannel == 10040`, `state.channels.actuation == 10050`으로 전환되는지 검증.

- [ ] **Step 2: 테스트 실패 확인 (Red)**

Run: `python tools/run_unit_tests.py --target 1_control/vas`
Expected: `network_manager.compute_base` 미정의, 기본 `baseChannel = 10020`, 정적 `10004` 개방 및 `Base + 3` 평시 송출로 인해 FAIL.

- [ ] **Step 3: VAS 런타임 모듈 및 시뮬레이션 노드 구현 (Green)**

1) `src/1_control/vas/modules/network_manager.lua` 수정:
   - 상수 정의: `CRAFT_BASE_MIN = 10000`, `CRAFT_BASE_MAX = 49960`, `CRAFT_BANDWIDTH = 40`, `ZONE_OFFSETS = { c2 = 0, guidance = 1, telemetry = 2, mfd = 3, navSensor = 4, clientReply = 5, actuation = 10, aero = 11, payloadBus = 20, weaponBus = 21, formationLink = 30 }`.
   - `network_manager.compute_base(aircraftIndexN)`: `n`이 `[1, 1000]` 정수 범위 밖이면 `nil, "ERR_AIRCRAFT_INDEX_RANGE"` 반환, 유효 시 `10000 + (n - 1) * 40` 반환.
   - `network_manager.is_valid_base(baseCh)`: `type(baseCh) == "number" and baseCh >= 10000 and baseCh <= 49960 and ((baseCh - 10000) % 40 == 0)`.
   - `build_channel_map(baseCh, sub)`: 위 11개 Zone 오프셋으로 `channels` 테이블 생성(레거시 `calibration = +4` 키 제거).
   - `network_manager.init(systemConfig)`: `cfg.baseChannel`이 주어지면 `is_valid_base`로 검증(무효 시 `compute_base(cfg.aircraftIndexN or 1)` 사용, 기본값 `10000`), 무선 모뎀에 `ch.c2`(`+0`), `ch.guidance`(`+1`), `ch.actuation`(`+10`), `ch.aero`(`+11`) 개방. `state.hangarChannels = nil`, `state.pendingRebind = nil` 초기화.
   - `network_manager.send_emergency_alert(state, alertData)`: 기본 채널 폴백을 `(state and state.channels and state.channels.guidance) or 10001`로 변경.
   - 격납고 동적 바인딩 함수 추가:
     - `handle_calibration_init(state, fsm, payload)`: `bayId = tonumber(payload.bayId) or 1`, `baseHangar = tonumber(payload.baseHangarChannel) or (101 + (bayId - 1) * 10)`. 무선 모뎀에 `baseHangar + 0`, `baseHangar + 1`, `baseHangar + 3` 개방 후 `state.hangarChannels = { bayId = bayId, stationId = payload.stationId or "HANGAR_BAY_01", base = baseHangar, cmd = baseHangar + 0, telem = baseHangar + 1, tap = baseHangar + 3 }` 저장. `fsm.transition_to(fsm, "CALIBRATION", "ALIGN_INIT")` 호출. `state.channels.actuation`(`+10`)과 `state.channels.aero`(`+11`)에 `MSG_CALIB_BAY_BIND`(`action = "OPEN"`, `stationId`, `bayId`, `baseHangarChannel = baseHangar`, `bayCalibrationTap = baseHangar + 3`, `bayCalibrationCmd = baseHangar + 0`) 송출 후 `baseHangar + 1`로 `MSG_CALIBRATION_INIT_ACK`(`status = "READY"`, `bayId`, `aircraftDomainId = state.aircraftDomainId`, `baseChannel = state.baseChannel`) 회신.
     - `handle_calibration_packet`: `MSG_PROFILE_SYNC` 처리 후 `state.hangarChannels and state.hangarChannels.telem`으로 `MSG_CALIB_ACK` 송출. `MSG_CALIBRATION_CLOSE` 수신 시 `+10`/`+11`로 `MSG_CALIB_BAY_BIND`(`action = "CLOSE"`) 송출, `hangarChannels.telem`으로 `MSG_CALIBRATION_CLOSE_ACK`(`bayId`, `status = "CLOSED"`) 송출 후 `cmd`, `telem`, `tap` 모뎀 채널을 `close`하고 `state.hangarChannels = nil` 및 `fsm.transition_to(fsm, "IDLE_ARMED", "CALIB_CLOSE")` 수행.
   - 재바인딩 캐스케이드 함수 추가:
     - `handle_channel_rebind(state, rawPacket)`: `p = rawPacket.payload`, `newBase = tonumber(p.newBaseChannel)`. `p.action == "PREPARE"`이면 `is_valid_base(newBase)` 확인 후 새 채널(`newBase + 0, +1, +10, +11`) 사전 개방, `state.pendingRebind = { transactionId = p.transactionId, oldBase = state.baseChannel, newBase = newBase }` 저장, 현재 `+10`/`+11`로 동일 `MSG_CHANNEL_REBIND` 중계 후 현재 `+1`로 `MSG_CHANNEL_REBIND_ACK`(`transactionId = p.transactionId`, `nodeId = "01_core"`, `status = "READY"`, `subNodesOk = true`) 송출. `p.action == "COMMIT"`이면 현재 `+10`/`+11`로 `COMMIT` 중계 후 기존 `oldBase + 0, +1, +10, +11`을 `close`하고 `state.baseChannel = newBase`, `state.channels = build_channel_map(newBase, {})`, `state.pendingRebind = nil` 갱신. `p.action == "ROLLBACK"`이면 현재 `+10`/`+11`로 `ROLLBACK` 중계 후 사전 개방한 `newBase + 0, +1, +10, +11`을 `close`하고 `state.pendingRebind = nil` 초기화.
   - `network_manager.dispatch`: `msgType == "MSG_CALIBRATION_INIT"` (`channel == state.channels.c2`), `msgType == "MSG_CHANNEL_REBIND"`, `msgType == "MSG_CHANNEL_REBIND_ACK"`, 그리고 `state.hangarChannels and channel == state.hangarChannels.cmd`(`MSG_CALIB_START`, `MSG_PROFILE_SYNC`, `MSG_CALIBRATION_CLOSE`) 분기를 연결한다.
2) `src/1_control/vas/modules/telemetry_feeder.lua` 수정:
   - `MSG_FLIGHT_TELEMETRY`를 `netState.channels.telemetry`(`Base + 2`)로 송출하고, `netState.hangarChannels and netState.hangarChannels.telem`이 존재하면 해당 격납고 텔레메트리 채널(`Base_hangar + 1`)로도 동일 페이로드를 송출한다.
   - `Base + 3` (`netState.channels.mfd`) 송출 조건 수정: `isAcro = (fsmState and fsmState.activeSource == "MFD_ACRO")`, `isFcpTimeoutFailsafe = (fsmState and (fsmState.currentState == "FAILSAFE_HOLD" or fsmState.currentState == "EMERGENCY_LAND") and fsmState.activeSource ~= "FCP")`(또는 `fsmState.fcpTimedOut == true` / `fsmState.currentState == "FAILSAFE_HOLD"`). 평시(`activeSource == "FCP"`이고 정상 상태)에는 `Base + 3` 송출을 수행하지 않으며, `isAcro`일 때 매 틱(20Hz), 페일세이프 단독 운전(`currentState == "FAILSAFE_HOLD" or currentState == "EMERGENCY_LAND"`)일 때 `state.tickCounter % 4 == 0`(5Hz)으로만 `MSG_MFD_STATE`를 송출한다.
3) HIL 시뮬레이션 노드 3종 수정:
   - `src/1_control/vas/node_fcp.lua`: `CH_GUIDANCE, CH_TELEM = 10001, 10002`로 변경.
   - `src/1_control/vas/node_tca.lua`: `CH_ACTUATION = 10010`으로 변경하고 line 18의 `mode = "REDSTONE"`을 `interactionMode = "REDSTONE"`으로 교체.
   - `src/1_control/vas/node_wap.lua`: `CH_AERO = 10011`로 변경.

- [ ] **Step 4: 테스트 통과 및 정적 분석 확인**

Run: `python tools/run_unit_tests.py --target 1_control/vas && python scratch/validate_lua_syntax.py`
Expected: `1_control/vas` 전 테스트 PASS, Lua 문법 오류 0건.

- [ ] **Step 5: Task 1 변경분 격리 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/1_control/vas/modules/network_manager.lua src/1_control/vas/modules/telemetry_feeder.lua src/1_control/vas/node_fcp.lua src/1_control/vas/node_tca.lua src/1_control/vas/node_wap.lua tests/1_control/vas/test_vas_core.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(vas): sync 40-channel 4-zone layout, MFD silence guard, and dynamic bay/rebind links"
```

---

### Task 2: TCA (`TASK-001-2`) 40채널 연산식, `Base+10` 구동 링크 및 Zero-Fallback 동기화

**Files:**
- Modify: `src/1_control/tca/modules/config_manager.lua`
- Modify: `src/1_control/tca/modules/channel_rebind_handler.lua`
- Modify: `src/1_control/tca/modules/discovery_handler.lua`
- Modify: `src/1_control/tca/modules/tca_daemon.lua`
- Modify: `src/1_control/tca/modules/status_reporter.lua`
- Modify: `src/1_control/tca/modules/tui_dashboard.lua`
- Modify: `src/1_control/tca/main.lua`
- Modify: `src/1_control/tca/tools/tca_setup.lua`
- Modify: `src/1_control/tca/node_tca.lua`
- Modify: `src/1_control/tca/node_core_sim.lua`
- Test: `tests/1_control/tca/test_tca_core.lua`

**Interfaces:**
- Consumes:
  - `MSG_THRUST_CMD`, `MSG_ACTUATOR_DISCOVER_REQ`, `MSG_CALIB_BAY_BIND`, `MSG_CHANNEL_REBIND` on `Base + 10` (`CH_THRUST_ACTUATION`)
  - `MSG_ACTUATOR_DISCOVER_REQ` on `Base_hangar + 3`, `MSG_CALIB_PULSE` on `Base_hangar + 0` (격납고 동적 바인딩 개방 중)
- Produces:
  - `MSG_ACTUATOR_STATUS`, `MSG_ACTUATOR_DISCOVER_ACK`, `MSG_CHANNEL_REBIND_ACK` on `Base + 10` (또는 디스커버리 시 `Base_hangar + 3`)

- [ ] **Step 1: `tests/1_control/tca/test_tca_core.lua`를 40채널/`Base+10` 규격으로 갱신하고 신규 실패 테스트 추가**

`tests/1_control/tca/test_tca_core.lua`에서:
1) 기존 `compute_base(2)` 단언문을 `10040`, `channels.thrustActuation`을 `10050`(`base + 10`)으로 수정하고 정적 `calibration` 필드를 제거한다(데몬 테스트 설정도 `thrustActuation = 10010` 단일 채널로 수정).
2) 신규 테스트 케이스 추가:
   - `compute_base(1) == 10000`, `compute_base(1000) == 49960`, 범위 이탈(`0`, `1001`) 거부(`nil`) 및 구형 20채널 설정(`aircraftIndexN = 2, baseChannel = 10020, channels = { thrustActuation = 10026, calibration = 10024 }`) 로드 시 `baseChannel == 10040`, `channels.thrustActuation == 10050`, `channels.calibration == nil`로 자동 마이그레이션 검증.
   - `MSG_CALIB_BAY_BIND`(`action = "OPEN"`, `baseHangarChannel = 101`) 수신 시 모뎀에 `101`(`+0`), `104`(`+3`)가 개방되고, `targetGroup = "ALL"`만 담긴 `MSG_ACTUATOR_DISCOVER_REQ`에 `MSG_ACTUATOR_DISCOVER_ACK`(`interactionMode = "REDSTONE"`, `mode` 필드 없음)로 응답하며, `action = "CLOSE"` 수신 시 `101`, `104`가 닫히는지 검증.
   - `MSG_CHANNEL_REBIND` 단일 타입으로 `action = "PREPARE"`(`transactionId = "REBIND-TX-10000-10080"`, `newBaseChannel = 10080`) 수신 시 `10090`(`newBase + 10`)이 사전 개방되고 `MSG_CHANNEL_REBIND_ACK`(`transactionId == "REBIND-TX-10000-10080"`)가 송출되며, 이어 동일 `MSG_CHANNEL_REBIND` 타입의 `action = "COMMIT"` 수신 시 구 `10010`이 닫히고 `cfg.baseChannel == 10080`, `cfg.channels.thrustActuation == 10090`, `cfg.aircraftIndexN == 3`으로 영구 반영되는지(및 `ROLLBACK` 시 `10090` 닫힘) 검증.

- [ ] **Step 2: 테스트 실패 확인 (Red)**

Run: `python tools/run_unit_tests.py --target 1_control/tca`
Expected: `compute_base(2)`가 `10020`을 반환하고 `channel_rebind_handler`가 `+6` 및 구 `rebindId`를 사용하여 FAIL.

- [ ] **Step 3: TCA 모듈·엔트리·도구 10개 파일 동기화 구현 (Green)**

1) `src/1_control/tca/modules/config_manager.lua`:
   - `CRAFT_BASE_MIN = 10000`, `CRAFT_BASE_MAX = 49960`, `CRAFT_BANDWIDTH = 40`, `ACTUATION_OFFSET = 10`.
   - `compute_base(n)`: `idx = tonumber(n)`, `if not idx or idx < 1 or idx > 1000 or math.floor(idx) ~= idx then return nil, "ERR_INDEX_OUT_OF_RANGE" end`, 반환 `10000 + (idx - 1) * 40`.
   - `migrate_legacy_base(cfg)`: `n = tonumber(cfg.aircraftIndexN)`일 때 기존 `baseChannel`이 구 20채널 공식(`10000 + (n - 1) * 20` 또는 `10000 + n * 20`)이거나 `channels.thrustActuation == cfg.baseChannel + 6` 또는 `channels.calibration ~= nil`이면 `newBase = compute_base(n)`으로 갱신하고 `cfg.channels = { thrustActuation = newBase + 10 }`(`calibration` 제거), `cfg.mode = nil` 정리 후 `true` 반환.
   - `load(path)`: `cfg.channels.thrustActuation = tonumber(cfg.channels.thrustActuation) or (cfg.baseChannel + 10)`, `cfg.channels.calibration = nil`, `cfg.mode = nil`.
2) `src/1_control/tca/modules/channel_rebind_handler.lua`:
   - `ACTUATION_OFFSET = 10` 상수화(`newBase + 6` 전수 제거 -> `newBase + 10`).
   - `handle_channel_rebind(modem, replyChannel, pkt, cfg, state, configPath)`:
     - `p.action == "ROLLBACK"` -> `handle_rollback(modem, pkt, state)`(`newBase + 10` 닫기).
     - `p.action == "COMMIT"` -> `handle_rebind_commit(modem, pkt, cfg, state, configPath)`(`oldActuation` 닫기, `cfg.baseChannel = newBase`, `cfg.channels.thrustActuation = newBase + 10`, `cfg.aircraftIndexN = p.newAircraftIndexN or (math.floor((newBase - 10000) / 40) + 1)`, 설정 저장).
     - `p.action == "PREPARE"` -> `newBase + 10` 사전 개방, `state.preparedRebind = { transactionId = p.transactionId, newBaseChannel = newBase }`, `MSG_CHANNEL_REBIND_ACK` 페이로드에 `transactionId = p.transactionId`, `nodeId = cfg.groupId or "THR_MAIN_L"`, `status = "READY"`, `subNodesOk = true` 수록 후 회신.
3) Zero-Fallback 및 채널 기본값 정리:
   - `src/1_control/tca/modules/discovery_handler.lua`: `cfg.mode` 폴백 제거(`cfg.interactionMode`만 참조); `is_target_matched`에서 `payload.targetGroup`과 `payload.targetThrusterId` 모두 `"ALL"` 또는 `groupId` 매칭 지원(Master ICD §I-3 및 Alignment §10.3 `targetGroup = "ALL"` 호환).
   - `src/1_control/tca/modules/tca_daemon.lua`: `cfg.mode` 제거(`cfg.interactionMode or "REDSTONE"`), `dispatch_modem_message`에서 구 `MSG_CHANNEL_REBIND_COMMIT` 분기를 제거하고 `MSG_CHANNEL_REBIND` 단일 분기로 `configPath`까지 전달.
   - `src/1_control/tca/modules/status_reporter.lua`: 기본 채널 폴백 `10006` -> `10010`.
   - `src/1_control/tca/modules/tui_dashboard.lua`: `cfg.mode` 제거, 기본 구동 채널 `baseCh + 10`.
   - `src/1_control/tca/main.lua`: `DEFAULT_CONFIG.channels = { thrustActuation = 10010 }`, 부팅 시 `thrustActuation`만 개방(정적 `calibration` 개방 제거).
   - `src/1_control/tca/tools/tca_setup.lua`: 기본 `channels = { thrustActuation = 10010 }`, 기체 번호 변경 시 `cfg.channels.thrustActuation = cfg.baseChannel + 10`(`calibration` 제거), `cfg.mode` 참조 제거, 기체 번호 유효 범위를 `1 ~ 1000`으로 조정.
   - `src/1_control/tca/node_tca.lua`, `src/1_control/tca/node_core_sim.lua`: `10006` -> `10010`, 정적 `10004` 제거(`node_core_sim.lua`는 격납고 베이 `101`/`104` 또는 `10010` 사용).

- [ ] **Step 4: 테스트 통과 및 정적 분석 확인**

Run: `python tools/run_unit_tests.py --target 1_control/tca && python scratch/validate_lua_syntax.py`
Expected: `1_control/tca` 전 테스트 PASS, Lua 문법 오류 0건.

- [ ] **Step 5: Task 2 변경분 격리 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/1_control/tca/modules/config_manager.lua src/1_control/tca/modules/channel_rebind_handler.lua src/1_control/tca/modules/discovery_handler.lua src/1_control/tca/modules/tca_daemon.lua src/1_control/tca/modules/status_reporter.lua src/1_control/tca/modules/tui_dashboard.lua src/1_control/tca/main.lua src/1_control/tca/tools/tca_setup.lua src/1_control/tca/node_tca.lua src/1_control/tca/node_core_sim.lua tests/1_control/tca/test_tca_core.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(tca): migrate actuation bus to Base+10 with 40-channel formula and zero-fallback"
```

---

### Task 3: FCP (`TASK-001-3`) 40채널·부트스트랩·재바인딩 및 GPS(`Base+5`) 측위 링크 동기화

**Files:**
- Modify: `src/2_guidance/fcp/config/fcp_config.json`
- Modify: `src/2_guidance/fcp/main.lua`
- Modify: `src/2_guidance/fcp/modules/channel_sentinel.lua`
- Modify: `src/2_guidance/fcp/modules/network_manager.lua`
- Modify: `src/2_guidance/fcp/modules/nav_engine.lua`
- Modify: `src/2_guidance/fcp/fcp_runtime.lua`
- Modify: `src/2_guidance/fcp/modules/ui_renderer.lua`
- Modify: `src/2_guidance/fcp/node_fcp.lua`
- Modify: `src/2_guidance/fcp/node_vas_sim.lua`
- Modify: `src/2_guidance/fcp/node_wap_sim.lua`
- Modify: `src/2_guidance/fcp/node_infra_sim.lua`
- Test: `tests/2_guidance/fcp/test_fcp_core.lua`

**Interfaces:**
- Consumes:
  - `MSG_FLIGHT_TELEMETRY` on `Base + 2`, `MSG_EMERGENCY_ALERT` / `MSG_CHANNEL_REBIND_ACK` on `Base + 1`
  - `MSG_GPS_RESPONSE` (`domainId = "GPS_BASE_NET"`) on `Base + 5` (`{ targetClient, clientSeq, status, position = { x, z }, accuracy, hdop, nodeCount, selectedNodes }`)
  - `MSG_BLOCK_ASSIGN` on `CH 50000`, `MSG_CHANNEL_PROBE` / `MSG_CHANNEL_PROBE_ACK` on `Base + 0`
- Produces:
  - `MSG_ATTITUDE_CMD`, `MSG_EMERGENCY_OVERRIDE`, `MSG_CHANNEL_REBIND` (`bandwidth = 40`) on `Base + 1`
  - `MSG_MFD_STATE` (5Hz), `MSG_MFD_ALERT` on `Base + 3`
  - `MSG_GPS_REQUEST` on `CH 60001` (`{ replyChannel = Base + 5, altitudeY, clientType = "AIRCRAFT", clientSeq }`)
  - `MSG_BLOCK_REQUEST` (`requestedBandwidth = 40`) on `CH 50000`, `MSG_CHANNEL_PROBE` (`bandwidth = 40`) on `Base + 0`

- [ ] **Step 1: `tests/2_guidance/fcp/test_fcp_core.lua`에 실패하는 단위 테스트 추가**

`tests/2_guidance/fcp/test_fcp_core.lua`에 다음 검증을 추가한다:
1) `config/fcp_config.json`의 `channels.baseChannel == 10000`, `channels.bandwidth == 40`, `channels.mfdInstrumentChannel == 10003`, `channels.bootstrapChannel == 50000`, `channels.gpsPingChannel == 60001` 확인 및 `require("main")` 로드 시 구 `sas_runtime` 오류 없이 `fcp_main.load_config()`가 `baseChannel == 10000`을 반환하는지 검증.
2) `channel_sentinel`: 기본 초기화 시 `baseChannel == 10000`, `bootstrapChannel == 50000`, `bandwidth == 40` 설정; 비정렬 `baseChannel = 10060` 유입 시 `10000`으로 정규화(`channel_sentinel.is_valid_base(10060) == false`, `is_valid_base(10040) == true`); `start_bootstrap`이 `requestedBandwidth == 40`을 생성하고 `initiate_rebind(state, 10080, 100)` $\to$ `on_rebind_ack` $\to$ `step_rebind_transaction`이 `bandwidth == 40`인 `PREPARE`/`COMMIT` 패킷을 생성하는지 검증.
3) `network_manager` & `fcp_runtime` & `nav_engine`: `bind_aircraft_channels` 호출 시 Zone 1 코어 채널 `10000 ~ 10005` 개방 및 `rebind_aircraft_channels(net, 10040)` 호출 시 `10000 ~ 10005` 닫힘 + `10040 ~ 10045` 개방(`mfdInstrumentChannel == 10043`); `fcp_runtime.step_tick` 실행 시 `CH 60001`로 송출되는 `MSG_GPS_REQUEST`가 `replyChannel == 10005`, `altitudeY`, `clientType == "AIRCRAFT"`, `clientSeq` 4필드를 모두 포함하며, `domainId = "GPS_BASE_NET"`의 `MSG_GPS_RESPONSE`(`status = "FIX_OK"`, `position = { x = 4.0, z = -3.0 }`, `accuracy = 0.2`, `hdop = 1.1`)를 `ingest_modem_event`로 수신했을 때 `nav_engine` 수평 위치(`pos.x`, `pos.z`)가 갱신되고 고도(`pos.y`)는 온보드 값이 유지되는지 검증.

- [ ] **Step 2: 테스트 실패 확인 (Red)**

Run: `python tools/run_unit_tests.py --target 2_guidance/fcp`
Expected: `fcp_config.json`의 `baseChannel == 10060`, `main.lua`의 `require("sas_runtime")` 실패, `MSG_GPS_RESPONSE` 미수신으로 인해 FAIL.

- [ ] **Step 3: FCP 설정·런타임·모듈·시뮬레이션 노드 11개 파일 구현 (Green)**

1) `src/2_guidance/fcp/config/fcp_config.json`:
   - `"baseChannel": 10000`, `"bandwidth": 40`, `"mfdInstrumentChannel": 10003`, `"bootstrapChannel": 50000`, `"facilityBeaconChannel": 50003`, `"atcCommChannel": 50001`, `"gpsPingChannel": 60001`, `"gpsServiceChannel": 60002`로 갱신.
2) `src/2_guidance/fcp/main.lua`:
   - `require("sas_runtime")` -> `require("fcp_runtime")`, 모듈 테이블 `fcp_main`, 기본 설정 경로 `"config/fcp_config.json"` (대체 경로 `"src/2_guidance/fcp/config/fcp_config.json"`)으로 교체.
3) `src/2_guidance/fcp/modules/channel_sentinel.lua`:
   - `CRAFT_BASE_MIN = 10000`, `CRAFT_BASE_MAX = 49960`, `CRAFT_BANDWIDTH = 40`, `DEFAULT_BOOTSTRAP_CH = 50000`.
   - `channel_sentinel.compute_base(n)` 및 `channel_sentinel.is_valid_base(baseCh)` 추가.
   - `init`: `rawBase = chs.baseChannel`, `validBase = channel_sentinel.is_valid_base(rawBase) and rawBase or 10000`, `bootstrapChannel = chs.bootstrapChannel or 50000`, `bandwidth = 40`.
   - `start_bootstrap`: `requestedBandwidth = 40`, `candidateBaseChannel = state.baseChannel`.
   - `on_block_assign`: `payload.baseChannel` 또는 `payload.assignedBaseChannel` 중 표준 `payload.baseChannel` 우선 수용(단 `is_valid_base` 검증 통과 시에만 반영).
   - `probe_channel` / `handle_incoming_probe`: `candidateBase = c`, `bandwidth = 40`, 충돌 응답 `{ existingDomain, occupiedBase = state.baseChannel, status = "CONFLICT_DETECTED", conflict = true }`.
   - `initiate_rebind` / `step_rebind_transaction`: `is_valid_base(new_base)` 검증 및 모든 `MSG_CHANNEL_REBIND` 페이로드의 `bandwidth = 40` 고정.
4) `src/2_guidance/fcp/modules/network_manager.lua`, `nav_engine.lua`, `fcp_runtime.lua`, `ui_renderer.lua`:
   - `network_manager.lua`: `ZONE_OFFSETS`(`c2 = 0, guidance = 1, telemetry = 2, mfd = 3, navSensor = 4, clientReply = 5, actuation = 10, aero = 11, payloadBus = 20, weaponBus = 21, formationLink = 30`), 기본 `baseChannel = 10000`, `bandwidth = 40`, `mfdInstrumentChannel = baseChannel + 3`, `gpsPingChannel = chs.gpsPingChannel or 60001`, `gpsServiceChannel = chs.gpsServiceChannel or 60002`. `verify_packet`의 `allowed_infra`에 `GPS_BASE_NET = true` 추가. `categorize_packet`에서 구 `"MSG_GPS_FIX"`를 표준 `"MSG_GPS_RESPONSE"`로 교체하고 `"MSG_CHANNEL_REBIND_ACK"` 큐(`rebindAck`) 추가. `rebind_aircraft_channels(ctx, new_base)` 함수 추가(기존 `oldBase + 0..5` `close` 후 `new_base + 0..5` `open`, `ctx.baseChannel = new_base`, `ctx.mfdInstrumentChannel = new_base + 3`). `send_gps_request`는 `ctx.gpsPingChannel`(`60001`)로 송출하고 `reply_ch = ctx.baseChannel + 5` 지정.
   - `nav_engine.lua`: `filter_gps(state, fix_payload, dt, now_ms)`가 표준 `MSG_GPS_RESPONSE` 페이로드(`fix_payload.status == "FIX_OK" or fix_payload.status == "FIX_DEGRADED"`, `fix_payload.position.x`, `fix_payload.position.z`)를 파싱하여 2D 수평 상보 필터를 수행하고 고도 `state.pos.y`는 온보드 기압/고도계 적분값을 유지하도록 수정.
   - `fcp_runtime.lua`: `step_tick`에서 `network_manager.send_gps_request(ctx.net, { replyChannel = ctx.net.baseChannel + 5, altitudeY = ctx.nav.pos.y, clientType = "AIRCRAFT", clientSeq = req_id })` 송출; `polled.rebindAck` 수신 시 `channel_sentinel.on_rebind_ack` 및 `step_rebind_transaction` 연동.
   - `ui_renderer.lua`: 기본 표시 채널 폴백 `10060` -> `10000`.
5) 시뮬레이션 노드 4종 수정:
   - `node_fcp.lua`: `10061, 10062, 10063` -> `10001, 10002, 10003`.
   - `node_vas_sim.lua`: `10061` -> `10001`, `10062` -> `10002`, 구 `10067`(`Base+7`) -> `10011`(`Base+11`).
   - `node_wap_sim.lua`: 구 `10067`(`Base+7`) -> `10011`(`Base+11`).
   - `node_infra_sim.lua`: 구 `30004` 개방 및 조건문 제거(`60001` 단일 수신), 응답을 `domainId = "GPS_BASE_NET"`, `type = "MSG_GPS_RESPONSE"`, `payload = { targetClient = "AIRCRAFT_01", clientSeq = ..., status = "FIX_OK", position = { x = 10.0, z = -20.0 }, accuracy = 0.5, hdop = 1.0, nodeCount = 4, selectedNodes = { "NODE_01", "NODE_02", "NODE_03", "NODE_04" } }`로 수정.

- [ ] **Step 4: 테스트 통과 및 정적 분석 확인**

Run: `python tools/run_unit_tests.py --target 2_guidance/fcp && python scratch/validate_lua_syntax.py`
Expected: `2_guidance/fcp` 전 테스트 PASS, Lua 문법 오류 0건.

- [ ] **Step 5: Task 3 변경분 격리 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/2_guidance/fcp/config/fcp_config.json src/2_guidance/fcp/main.lua src/2_guidance/fcp/modules/channel_sentinel.lua src/2_guidance/fcp/modules/network_manager.lua src/2_guidance/fcp/modules/nav_engine.lua src/2_guidance/fcp/fcp_runtime.lua src/2_guidance/fcp/modules/ui_renderer.lua src/2_guidance/fcp/node_fcp.lua src/2_guidance/fcp/node_vas_sim.lua src/2_guidance/fcp/node_wap_sim.lua src/2_guidance/fcp/node_infra_sim.lua tests/2_guidance/fcp/test_fcp_core.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(fcp): sync 40-channel baseline, bootstrap/rebind protocol, and Base+5 GPS link"
```

---

### Task 4: Alignment (`TASK-001-4`) 기체 `Base+0` 40채널 바인딩 및 교정 세션 개폐 동기화

**Files:**
- Modify: `src/0_development/alignment/modules/align_master.lua`
- Modify: `src/0_development/alignment/main.lua`
- Test: `tests/0_development/alignment/test_alignment_core.lua`

**Interfaces:**
- Consumes:
  - `MSG_CALIBRATION_INIT_ACK`, `MSG_FLIGHT_TELEMETRY`, `MSG_CALIB_ACK`, `MSG_CALIBRATION_CLOSE_ACK` on `Base_hangar + 1`
  - `MSG_ACTUATOR_DISCOVER_ACK`, `MSG_SURFACE_DISCOVER_ACK` on `Base_hangar + 3`
- Produces:
  - `MSG_CALIBRATION_INIT` on aircraft `Base + 0` (`10000 + (N - 1) * 40`)
  - `MSG_CALIB_START`, `MSG_CALIB_PULSE`, `MSG_PROFILE_SYNC`, `MSG_CALIBRATION_CLOSE` on `Base_hangar + 0`
  - `MSG_ACTUATOR_DISCOVER_REQ`, `MSG_SURFACE_DISCOVER_REQ` on `Base_hangar + 3`

- [ ] **Step 1: `tests/0_development/alignment/test_alignment_core.lua`에 실패하는 단위 테스트 추가**

`tests/0_development/alignment/test_alignment_core.lua`에 다음 검증을 추가한다:
1) `align_master.compute_craft_base(1) == 10000`, `compute_craft_base(2) == 10040`, `compute_craft_base(1000) == 49960`, 범위 이탈(`0`, `1001`) 시 `nil` 반환 검증.
2) `craft_base_ch` 생략 상태로 `align_master.init_bay_session(stationCfg, "AIRCRAFT_02", nil, mockModem)` 호출 시 도메인 번호(`2`)로부터 `craft_base_ch == 10040`을 자동 산출하여 `tx == 10040`(`Base + 0`, 구 `1000` 아님), `rx == 102`(`Base_hangar + 1`)로 `MSG_CALIBRATION_INIT`를 전송하는지 검증.
3) `HANDSHAKE` 상태에서 `MSG_CALIBRATION_INIT_ACK` 패킷 주입 시 `Base_hangar + 0`(`101`)으로 `MSG_CALIB_START`(`action = "ENTER_CALIBRATION"`)가 송출되고 `Base_hangar + 3`(`104`)으로 `MSG_ACTUATOR_DISCOVER_REQ` 및 `MSG_SURFACE_DISCOVER_REQ`가 송출되는지 검증.
4) `align_master.release_channels(master)` 호출 시 `Base_hangar + 0`(`101`)으로 `MSG_CALIBRATION_CLOSE`(`action = "CLOSE_SESSION"`)가 먼저 송출된 뒤 `101`, `102`, `104` 모뎀 채널이 모두 닫히고(`isOpen == false`) `master.state == "STANDBY"`로 복귀하는지 검증.

- [ ] **Step 2: 테스트 실패 확인 (Red)**

Run: `python tools/run_unit_tests.py --target 0_development/alignment`
Expected: `compute_craft_base` 미정의, 기본 채널 `1000` 송출 및 `MSG_CALIB_START`/`MSG_CALIBRATION_CLOSE` 미송출로 인해 FAIL.

- [ ] **Step 3: Alignment 마스터 오케스트레이터 및 엔트리포인트 수정 (Green)**

1) `src/0_development/alignment/modules/align_master.lua`:
   - 상수 정의: `CRAFT_BASE_MIN = 10000`, `CRAFT_BASE_MAX = 49960`, `CRAFT_BANDWIDTH = 40`, `HANGAR_BASE_MIN = 101`, `HANGAR_BANDWIDTH = 10`.
   - `align_master.compute_craft_base(aircraft_number)`: `n = tonumber(aircraft_number)`, `1 <= n <= 1000` 정수일 때 `10000 + (n - 1) * 40` 반환, 그 외 `nil`.
   - `align_master.compute_hangar_base(bay_id)`: `b = tonumber(bay_id) or 1`, `1 <= b <= 10`일 때 `101 + (b - 1) * 10` 반환.
   - 도메인 파서 헬퍼: `domain_id`가 `"AIRCRAFT_(%d+)"` 패턴이면 기체 번호 `N`을 추출하여 `craft_base_ch` 미지정 시 `compute_craft_base(N)` 적용(폴백 기본값 `10000`, 구 `1000` 완전 제거).
   - `handle_handshake`: `MSG_CALIBRATION_INIT_ACK` 수신 시 `self.cmd_ch`(`Base_hangar + 0`)로 `MSG_CALIB_START`(`{ action = "ENTER_CALIBRATION", stationId = self.cfg.stationId or "HANGAR_BAY_01", targetThruster = "ALL", timeoutSec = 120 }`) 송출 후 `self.tap_ch`(`Base_hangar + 3`)로 디스커버리 요청 2종 송출.
   - `release_channels(self, reason)`: 채널 닫기 직전에 `self.cmd_ch`(`Base_hangar + 0`)로 `MSG_CALIBRATION_CLOSE`(`{ stationId = inst.cfg.stationId or "HANGAR_BAY_01", bayId = inst.cfg.bayId or 1, action = "CLOSE_SESSION", reason = reason or "COMPLETE" }`)를 송출한 뒤 `cmd_ch`, `telem_ch`, `tap_ch`를 `modem_close`하고 `inst.state = "STANDBY"`로 전환.
2) `src/0_development/alignment/main.lua`:
   - `default_cfg.station.channels.tcaDirect = 104`를 사양서 표준 키 `tapDirect = 104`로 교체.
   - line 66의 `align_master.init_bay_session(cfg.station, "AIRCRAFT_01", 1000, modem)`을 `align_master.init_bay_session(cfg.station, "AIRCRAFT_01", align_master.compute_craft_base(1), modem)`(`10000`)으로 교체.

- [ ] **Step 4: 테스트 통과 및 정적 분석 확인**

Run: `python tools/run_unit_tests.py --target 0_development/alignment && python scratch/validate_lua_syntax.py`
Expected: `0_development/alignment` 전 테스트 PASS, Lua 문법 오류 0건.

- [ ] **Step 5: Task 4 변경분 격리 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/alignment/modules/align_master.lua src/0_development/alignment/main.lua tests/0_development/alignment/test_alignment_core.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(alignment): bind aircraft C2 on 40-channel Base+0 and emit session start/close packets"
```

---

### Task 5: GPS (`TASK-001-5`) 인프라 채널(`60001~60004`) 및 비행체 `Base+5` 회신 채널 동기화

**Files:**
- Modify: `src/0_infra/gps/modules/protocol.lua`
- Modify: `src/0_infra/gps/modules/client_core.lua`
- Modify: `src/0_infra/gps/client_entry.lua`
- Modify: `src/0_infra/gps/installer.lua`
- Test: `tests/0_infra/gps/test_gps_core.lua`

**Interfaces:**
- Consumes:
  - `MSG_GPS_REQUEST` on `CH_GPS_PING = 60001` (`replyChannel = Base + 5`)
  - `MSG_GPS_NODE_REPORT`, `MSG_GPS_NODE_HEARTBEAT` on `CH_GPS_NODE_IN = 60003`
- Produces:
  - `MSG_GPS_RESPONSE` (`domainId = "GPS_BASE_NET"`) on `replyChannel` (`10005` for `AIRCRAFT_01`, `10000 + (N - 1) * 40 + 5` for `AIRCRAFT_N`)

- [ ] **Step 1: `tests/0_infra/gps/test_gps_core.lua`에 실패하는 단위 테스트 추가**

`tests/0_infra/gps/test_gps_core.lua`에 `protocol`, `client_core`, `installer` 검증을 추가한다:
1) `protocol.CH_GPS_PING == 60001`, `CH_GPS_SERVICE == 60002`, `CH_GPS_NODE_IN == 60003`, `CH_GPS_MGMT == 60004`, `DEFAULT_REPLY_CHANNEL == 10005` 상수 및 `protocol.computeCraftReplyChannel(1) == 10005`, `computeCraftReplyChannel(2) == 10045`, `computeCraftReplyChannel(1000) == 49965`, 범위 이탈(`0`, `1001`) 시 `nil` 반환 검증.
2) `client_core.new()`의 초기 `replyChannel == 10005`(구 `10000 + compId % 50000`으로 인해 `compId = 0`일 때 `10000` `CH_OPERATOR_C2`와 충돌하던 문제 해소) 및 `c:init("AIRCRAFT_02", "AIRCRAFT")`처럼 `replyChannel` 생략 시 도메인 번호로부터 `10045`(`Base + 5`)가 자동 설정되고, `c:nextRequestPacket(120.5, 1000)`이 생성한 패킷이 `protocol.validatePacket(pkt, protocol.MSG_REQUEST)`를 통과하며, `protocol.buildResponse("GPS_BASE_NET", 1, ...)` 응답을 `c:handleMessage(10045, respPkt, 1020)` -> `c:poll(seq)`로 정상 수령하는지 검증.
3) `installer.lua`(`_G.harness_is_testing = true`)의 노드 기본 설정이 구 단일 `channel = 60002` 대신 4채널 테이블 `channels = { ping = 60001, service = 60002, nodeIn = 60003, mgmt = 60004 }`를 기록하는지 검증.

- [ ] **Step 2: 테스트 실패 확인 (Red)**

Run: `python tools/run_unit_tests.py --target 0_infra/gps`
Expected: `protocol.computeCraftReplyChannel` 미정의, `client_core.new().replyChannel == 10000`, `installer.lua`의 `channels` 누락으로 인해 FAIL.

- [ ] **Step 3: GPS 프로토콜·클라이언트·인스톨러 수정 (Green)**

1) `src/0_infra/gps/modules/protocol.lua`:
   - 상수 추가: `CRAFT_BASE_MIN = 10000`, `CRAFT_BASE_MAX = 49960`, `CRAFT_BANDWIDTH = 40`, `CRAFT_MAX_INDEX = 1000`, `CH_REPLY_OFFSET = 5`, `DEFAULT_REPLY_CHANNEL = 10005`.
   - `protocol.computeCraftReplyChannel(aircraftIndexN)`: `n = tonumber(aircraftIndexN)`, `if not n or n < 1 or n > 1000 or math.floor(n) ~= n then return nil end`, 반환 `10000 + (n - 1) * 40 + 5`.
   - `protocol.resolveDomainReplyChannel(domainId)`: `tostring(domainId or "")`에서 `"^AIRCRAFT_(%d+)$"` 매칭 시 `computeCraftReplyChannel(tonumber(idx))` 반환, 미매칭 시 `nil`.
2) `src/0_infra/gps/modules/client_core.lua`:
   - `client_core.new()`: `self.replyChannel = protocol.DEFAULT_REPLY_CHANNEL` (`10005`).
   - `client_core:init(domainId, clientType, replyChannel)`: `replyChannel`이 명시되면 해당 번호를 사용하고, 생략(`nil`)된 경우 `protocol.resolveDomainReplyChannel(self.domainId) or protocol.DEFAULT_REPLY_CHANNEL`로 설정.
3) `src/0_infra/gps/client_entry.lua`:
   - line 7의 구버전 `10045` 하드코딩을 제거하고 `local replyChannel = tonumber(args[3]) or protocol.resolveDomainReplyChannel(domainId) or protocol.DEFAULT_REPLY_CHANNEL` (`AIRCRAFT_01` 기본값 `10005`)로 교체.
4) `src/0_infra/gps/installer.lua`:
   - `installNode()`의 `defaultCfg`에서 구 `channel = 60002`를 제거하고 `channels = { ping = 60001, service = 60002, nodeIn = 60003, mgmt = 60004 }`로 교체.
   - (참고: `src/0_infra/gps/server.lua` line 118의 `protocol.MSG_HEARTBEAT` 오타도 `protocol.MSG_NODE_HEARTBEAT`로 함께 정정하여 `CH 60003` 하트비트 수신 누락을 막는다.)

- [ ] **Step 4: 테스트 통과 및 정적 분석 확인**

Run: `python tools/run_unit_tests.py --target 0_infra/gps && python scratch/validate_lua_syntax.py`
Expected: `0_infra/gps` 전 테스트 PASS, Lua 문법 오류 0건.

- [ ] **Step 5: Task 5 변경분 격리 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/gps/modules/protocol.lua src/0_infra/gps/modules/client_core.lua src/0_infra/gps/client_entry.lua src/0_infra/gps/installer.lua src/0_infra/gps/server.lua tests/0_infra/gps/test_gps_core.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(gps): align aircraft client reply channel to 40-channel Base+5 and normalize node channels"
```

---

### Task 6: 전 코드베이스 통합 검증 및 `TASK.md` 동기화

**Files:**
- Modify: `TASK.md`

- [ ] **Step 1: 구버전 채널/폴백 잔존 여부 전수 정적 스캔**

Run:
```powershell
python -c "import pathlib, re; bad = re.compile(r'(sas_runtime|sas_config|MSG_GPS_FIX|MSG_CHANNEL_REBIND_COMMIT|cfg\.mode\b|10060|10061|10062|10063|10067|30004)'); hits = [f'{p}:{i}:{l.strip()}' for r in ['src/1_control/vas','src/1_control/tca','src/2_guidance/fcp','src/0_development/alignment','src/0_infra/gps'] for p in sorted(pathlib.Path(r).rglob('*')) if p.is_file() for i, l in enumerate(p.read_text(encoding='utf-8').splitlines(), 1) if not l.lstrip().startswith('--') and bad.search(l)]; print('\n'.join(hits)); raise SystemExit(1 if hits else 0)"
```
Expected: 출력 0줄, 종료 코드 `0`.

- [ ] **Step 2: 전체 단위 테스트 스위트, 하네스 회귀 및 Lua 문법 검증 실행**

Run:
```powershell
python -m unittest discover -s tests/harness -v
python tools/run_unit_tests.py --require-tests --clean-orphans
python scratch/validate_lua_syntax.py
```
Expected: 하네스 회귀 및 전 코드베이스 단위 테스트 스위트 전원 PASS(종료 코드 `0`), 문법 오류 `0`건.

- [ ] **Step 3: `TASK.md` 진행 상태 갱신 (`TASK-003` 경계 준수)**

`TASK.md`의 로드맵 순서(`TASK-001` $\to$ `TASK-002` $\to$ `TASK-003`)를 준수하여:
1) `TASK.md`의 `TASK-001` 및 `TASK-001-1 ~ TASK-001-5` 체크박스를 `[x]`로 갱신하고 완료 일자를 기록한다.
2) 5대 사양서(`VAS`, `TCA`, `FCP`, `Alignment`, `GPS`)의 `Approved` $\to$ `Implemented` 메타데이터 전이는 `TASK-002` 완료 후 `TASK-003`에서 수행하도록 현행 `Approved` 상태를 유지한다.

- [ ] **Step 4: Task 6 완료 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add TASK.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "chore(task): mark TASK-001 runtime 40-channel sync complete"
```
