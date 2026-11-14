# Create_Aeroneutics 전수 검사 및 교정 완료 보고서 (TASK-013 Final Report)

> **수행 일시**: 2026-11-14  
> **수행 방식**: `/systematic-debugging` 전수 감사(43건 확정: Critical 10·High 14·Medium 15·Low 4, 오탐 4건 기각) + 2인 교차 검증 + 사용자 Grilling 확정(Q1~Q8 + Q3-1) + Wave 1(사양서) · Wave 2(코드/하네스/테스트) · Wave 3(독립 교차 검증 및 승격)  
> **최종 상태**: 교정·검증 **PASS** (`src/1_control/asa/**` 및 `tests/1_control/asa/**` `0 diff` 동결 유지, Wave 2 대상 8대 사양서 `Implemented` 승격 완료)

---

## 1. 기존 자동 검증 베이스라인 (전원 Exit 0 — 구조적 사각지대 확인)

기존 정적·동적 검증 파이프라인은 **전수 통과**하였으나, 로컬 단위 Mock 및 부분 E2E 시나리오 특성상 **계층 간 와이어 계약 불일치·미배선 런타임 경로·사양서 간 SSOT 분열**을 검출하지 못했습니다.

| 검증 명령 | 결과 요약 | 비고 |
| :--- | :--- | :--- |
| `python tools/verify_all_specs.py --check-readmes` | **Exit 0** (`15 active specs`, `0 Errors, 0 Warnings`, `8 READMEs`) | 링크·메타데이터·금지어 위주 검사 |
| `python tools/verify_spec_status.py` | **Exit 0** (`9 Implemented, 6 Approved`) | 일부 `Implemented` 사양서와 코드 괴리 발견 |
| `python tools/verify_manifest_sync.py` | **Exit 0** (`12 modules`, `112 paths`, `126 src`, `9 GDrive`, `0 Errors`) | `--strict-gdrive-packages` 실행 시 `104 Errors` |
| `python tools/validate_lua_syntax.py` | **Exit 0** (`123 target Lua files` Lua 5.2 OK) | — |
| `python tools/verify_context_docs.py` | **Exit 0** (`0 findings`, R1~R8) | — |
| `python -m unittest discover -s tests/harness -p "test_*.py"` | **Exit 0** (`82 tests in 6.948s`) | — |
| `python tools/run_unit_tests.py --require-tests --clean-orphans` | **Exit 0** (`12 targets`, `469/469 PASS`) | 4,204 assertions, 0 hollow tests |
| `python tools/run_e2e_tests.py --clean-orphans` | **Exit 0** (`8 suites`, `12/12 PASS`, `702.45ms`) | — |
| `python tools/run_mutation_tests.py` | **Exit 0** (`25/25 KILLED`, `100.0% >= 90.0%`) | 122개 중 20개 파일 편중 (`asa`/`amm` 코어 0건) |
| Lua 5.2/OS/Yield/Locals 정적 스캔 (198 `.lua` 파일) | **위반 0건** (최대 지역변수 30개, 루프 7건 모두 yield/`break` 보유) | 단, `static_guard.py` 자체 누락 7건 확인 |

---

## 2. 교차 검증 완료 결함 목록 (심각도순)

> **Grilling 여부**: 사양서 정본(SSOT) 선택, Mixed-Scope(사양서+코드 동시 수정), 와이어 스키마/채널/FSM 동작 변경, 또는 연기 과제(`TASK-105`/`103`/`104`/`401`)·GDrive 정책 판단이 필요한 항목은 `Grilling: Yes`로 표시했습니다.

### 🔴 CRITICAL (10건) — 시스템 불능 · 안전 위험 · 와이어 계약 파손

| ID | 대상 파일 (`File:Line`) | 근본 원인 요약 | Grilling |
| :--- | :--- | :--- | :---: |
| **FLT-CRIT-01** | `src/3_planning/amm/main.lua:499-504,630-656`<br>`src/3_planning/amm/modules/c2_arbiter.lua:274-302,391-407`<br>`src/1_control/vas/modules/telemetry_feeder.lua:56` | **AMM 순환 MFD 자가수신 & `Base+2` FCP 텔레메트리 미배선**: `Base+3`(`MSG_MFD_STATE`)을 자기 엔진 입력으로 연결하고 `Base+2` `handle_flight_telemetry`는 `latest_telem`만 캐싱(`fsmState`·`engine:step_telemetry` 미갱신). `step_5hz_downlink`가 `app.arbiter.fsmState`를 되돌려 송출하며 `[I-6]` 필수 필드 다수 누락 및 `heading`을 `yaw` 대신 전달. | **No** |
| **FLT-CRIT-02** | `src/3_planning/amm/modules/c2_arbiter.lua:14,450`<br>`src/3_planning/amm/main.lua:676,708-714` | **AMM 부팅 즉시 자동 시동(Auto-Arm)**: `authority` 초기값이 `"PILOT_PRIMARY"`이고 `get_effective_goal()`이 `arm = (self.authority ~= "DISARMED")`를 반환해 부팅 즉시 시동 명령 없이 `Base+4`로 `arm = true` 송출. | **No** |
| **FLT-CRIT-03** | `src/3_planning/amm/modules/network_manager.lua:43-52,68-76,186-189`<br>`src/3_planning/amm/main.lua:578-579`<br>`src/3_planning/amm/config/amm_config.json:14-15` | **AMM 듀얼 모뎀 `Base+5` GPS 수신 채널 분리 & 모뎀 사이드 하드코딩**: `bind_modems`는 `Base+5`를 `onboardModem`(`top`)에 개방하나 `send_gps_request`는 `infraModem`(`back`)으로 송신해 GPS 응답 수신 불가. `main.lua`는 `"top"`/`"back"` 하드코딩으로 `amm_config.json` 무시. `apply_rebind`는 `openPayloadChannels` 및 `nav`/`engine`/`sentinel` `baseChannel` 미갱신. | **No** |
| **FLT-CRIT-04** | `src/1_control/vas/modules/sensor_pipeline.lua:230-231,262-264` vs `VAS_PROGRAM_SPECIFICATION.md:170-199` | **VAS 3D 레버암 CoM 각속도 보정 수식 뒤섞임**: `pDeg = g.pitchRate`, `qDeg = g.rollRate`로 `p`/`q` 축 뒤바뀜 및 `vxCoM`/`vyCoM`/`vzCoM` 외적 항(`r*dz - p*dy` 등) 오기. | **No** |
| **FLT-CRIT-05** | `src/1_control/vas/modules/actuator_adapter_asa.lua:7-10,38-46,75,79,85,103,108-127`<br>`src/1_control/vas/modules/core_daemon.lua:207-209`<br>`src/1_control/asa/modules/tui_dashboard.lua:96` | **VAS → ASA (`Base+11` `[I-10]`) 스케일·스키마·설정 불일치**: 어댑터가 `0..15`/`-15..15` 정수를 송출해 ASA 대시보드(`d * 30.0`)에서 `450`도 산출, `dynamicPressureFactor` 누락, `VAS §9.5` 설정키(`surfaceGeometry`/`speedLimits`/`coefficients`, `vRef=20.0`) 대신 구 키(`surfaceMix`/`aeroEnvelope`, `vRef=15.0`) 참조, 피드백 키/상태값(`appliedDeg`/`API_TOTAL_LOSS` vs `appliedDeflection`/`NOMINAL`/`TOTAL_LOSS`) 불일치. | **Yes** |
| **FLT-CRIT-06** | Master ICD `1286,1297-1303,1523`, Diagram `299,603-633`, AMM `472`, VAS `1339-1362` vs FCP `744-767`, ASA `357,367-373,496`, TCA `456-458`<br>+ `amm/channel_sentinel.lua`, `fcp/network_manager.lua`, `vas/network_manager.lua`, `tca/channel_rebind_handler.lua` | **`[I-9]` 4계층 `MSG_CHANNEL_REBIND` 사양 분열 & 조기 ACK/롤백/영속화 결함**: Camp A(ICD/VAS/AMM/Diagram)는 `MSG_REBIND_ACK` + `phase`/`oldBase`/`newBase`/`switchTimeoutMs=1000`, Camp B(FCP/ASA/TCA 사양·4종 코드)는 `MSG_CHANNEL_REBIND_ACK` + `transactionId`/`action`/`oldBaseChannel`/`newBaseChannel`/`500ms`. 런타임에서도 VAS가 `PREPARE` 시 하위 노드 ACK 대기 없이 즉시 `READY` 반환·`COMMIT` 시 서브채널 초기화 및 디스크 저장 누락, FCP 500ms 롤백 시 상위 AMM NACK 미통보·`persist_config` 잘못된 JSON 키 기록, TCA 500ms 워치독 부재. | **Yes** |
| **FLT-CRIT-07** | `src/1_control/vas/modules/core_daemon.lua:232,249`<br>`src/1_control/vas/modules/state_machine.lua:188` | **VAS 패닉 FSM 전이 실패 & 종료 시 공중 추력 쿠션 상실**: `249`행이 `state.fsm` 대신 `state`를 전달해 패닉 시 비상 상태 전이 실패; `232`행이 `{}`를 넘겨 `isAirborne == true`여도 모든 추력기 `0` 출력. | **No** |
| **FLT-CRIT-08** | `ALIGNMENT` `116,607-679,746-801`, Master ICD `602-666,750-754,818-824`, VAS `985,1031-1177,1525`, TCA `403,448-449`, ASA `266,343-347,486`, Diagram `174`<br>+ `align_master.lua:153` | **`[I-4]` 격납고 캘리브레이션 와이어·채널 사양 충돌**: `MSG_CALIB_PULSE` 채널(`+0` vs TCA `+3` vs Diagram 미존재 패킷명), `INIT`/`INIT_ACK`/`BAY_BIND`/`CLOSE`/`DISCOVER_REQ`(`targetGroup` vs `targetGroupId`)/`PROFILE_SYNC.discoveredSurfaces`(맵 vs 객체맵 vs 배열, `"RUDD"` vs `"RUDDER"`), `align_master.lua:153` 응답 채널(`+1` vs 사양 `+3`) 전방위 불일치. | **Yes** |
| **FLT-CRIT-09**<br>*(+ **INF-HIGH-02**)* | `src/3_planning/amm/main.lua:518-529`<br>`src/3_planning/amm/modules/facility_client.lua:84-121,159,162`<br>`src/0_infra/landing_pad/modules/tactical_streamer.lua:55,70`<br>+ Master ICD / `LANDING_PAD` / `RUNWAY` / `DOCKING_ARM` | **`[I-5]` `MSG_FACILITY_DYNAMIC_GUIDE` 3방향 스키마 분열 & AMM 설비/센티넬 미배선**: AMM `main.lua`가 `on_atc_clearance`/`on_tactical_guide`/`on_docking_status`/`evaluate_guide_watchdog` 및 `channel_sentinel`을 전혀 호출하지 않고 `50001`/`50004`를 `update_beacons`로 오라우팅. 또한 `MSG_FACILITY_DYNAMIC_GUIDE` 필드가 `LANDING_PAD`(`touchdownPoint`/`attitude`), `Master ICD`·`RUNWAY`(`thresholdPoint`/`deckAttitude`), `DOCKING_ARM`(`portTargetPoint`/`portAttitude`)로 3분열되어 있음 (`facility_client`는 `LANDING_PAD`만 파싱). | **Yes** |
| **INF-CRIT-01** | `src/0_infra/landing_pad/main.lua:160-162`<br>`src/0_infra/gac/modules/gac_fsm.lua:163`<br>`src/0_infra/gac/modules/allocation_engine.lua:133`<br>`src/0_infra/gac/modules/facility_inventory.lua:155` | **Landing Pad ↔ GAC 상태 열거형 불일치 (`"IDLE"` vs `"FREE"`)**: 착륙패드가 1Hz `MSG_ATC_FACILITY_UPDATE`에 FSM 상태 `"IDLE"`을 전송하고 GAC가 이를 덮어쓰나, GAC 배정 엔진은 `"FREE"`만 가용 패드로 인식해 모든 유휴 패드가 할당 불가(`freeLandingPads = 0`) 상태가 됨. | **Yes** |

---

### 🟠 HIGH (14건) — 기능 결함 · 제어 법칙/가드 미동작 · Zero-Fallback 위반

| ID | 대상 파일 (`File:Line`) | 근본 원인 요약 | Grilling |
| :--- | :--- | :--- | :---: |
| **INF-HIGH-01** | `src/0_infra/gcs/main.lua:5-9,100,223-225`<br>`src/0_infra/gcs/modules/channel_manager.lua:57` | **GCS `main.lua` 3중 런타임 결함**: (a) `save_registry(self.registry_path, self.channel_mgr)` 인자 오전달로 `false` 반환, (b) `--daemon`/`-d` 인자를 `config_path`로 전달, (c) `require("channel_manager")` 등 `"modules."` 접두사/`package.path` 누락. | **No** |
| **DEV-HIGH-01** | `src/0_development/alignment/modules/align_master.lua:108-115,170,180-187,198-211`<br>`src/0_development/alignment/main.lua:66,69,78` | **Alignment FSM 미완성 & 안전 설정 유실**: `step_fsm`에 `INTEGRATING`/`SETTLING`/`REGRESSION`/`ANOMALY_PAUSE`/`AUTHORITY_CHECK` 핸들러가 없어 `DISCOVERY` 직후 영구 정지; `TUNING` 즉시 `HANDSHAKE` 덮어쓰기; `ABORT`가 활성 상태에서 무시됨; `totalDryMass=12000`/`FULL_6DOF_PASS` 하드코딩 및 로컬 백업 부재; `main.lua:66`이 `cfg` 대신 `cfg.station`을 넘겨 `cfg.safety`가 `nil`이 됨. (`Implemented` 사양서와 괴리) | **Yes** |
| **FLT-HIGH-01** | `src/2_guidance/fcp/modules/outer_loop_controller.lua:331-355` | **FCP `WINGED_VTOL` 천이 불연속 & 0 나눗셈**: `vHigh == vLow` 시 0 나눗셈(`NaN`), 호버↔고정익 간 `qH↔qF`/`rH↔rF` 보간 및 `[-10,+12]`도 피치 클램프 부재(`alpha >= 1.0`에서 점프), `alpha >= 1.0` 시 `sp.flapHint` 무시. | **No** |
| **FLT-HIGH-02** | `src/1_control/vas/modules/vehicle_policy.lua:13,16,67`<br>`src/1_control/vas/modules/state_machine.lua:25,100-103` | **VAS 실속 가드 스케일(1.0 vs 6.0) & FSM 결함**: `minStallThrottle`을 `[0, 1]`로 클램프해 사양서 `6.0`(0-15 스케일)이 `1.0`(100% 추력)으로 고정, `cfg.airframeType` 무시; `sensorLossDebounceTicks` 기본값 `1`(사양 `15`); `ARMING -> IDLE_ARMED` 전이 핸들러 부재. | **Yes** |
| **FLT-HIGH-03** | `src/3_planning/amm/main.lua:605,686-691`, `c2_arbiter.lua:397-406`, `mission_engine.lua:452,836`, `chattering_guard.lua:71-79,97-109` | **AMM 채터링 가드 런타임 미연동 & 설계서 API 괴리**: `main.lua`가 `app.guard.latches`를 계산만 하고 미사용, `c2_arbiter`는 비래치/비디바운스 `<0.20`/`0.10` 비교 실행, 5종 가드 메서드 사실상 미호출; `chattering_guard.lua` 모드명(`HIGH_ACTIVE` vs `HIGH_ENTER`)·상태 필드(`debounce`/`dwell`/`lowFuelLatched` vs `streaks`/`dwellUntilTick`/`rtl`)가 `2026-11-13` 설계서 §5.2와 상이. | **Yes** |
| **FLT-HIGH-04** | `src/3_planning/amm/modules/mission_engine.lua:641-684`<br>`src/3_planning/amm/modules/condition_evaluator.lua:255-269` | **AMM 활성 액션 7종 디스패처 누락·11종 리졸버 누락·`LOITER_TURNS` 버그**: `ACT_SYS_LOAD`/`PREFLIGHT`/`SET_HOME`, `ACT_TKL_TRANS_*`, `ACT_PAY_SET_ROI`/`CLEAR_ROI`가 `FCP_DISPATCHERS`에서 누락(No-op); 11종이 `DURATION_SEC(0)` 즉시 완료; `ACT_PAT_LOITER_TURNS`가 360도 회전 각도 대신 `durationSec`만 평가. | **No** |
| **FLT-HIGH-05** | `src/3_planning/amm/modules/mission_engine.lua:754-768,789`<br>`src/3_planning/amm/modules/action_registry.lua:131,342`<br>`c2_arbiter.lua:104-106`, `main.lua:101,160` | **AMM 데코레이터 미배선·매크로 훅 유실·사전조건 우회**: `DEC_RETRY_N`/`DEC_TIMEOUT_GUARD` 미구현, `DEC_ENERGY_ECO`/`SMOOTH_TRAJ` 파라미터 무시; 매크로 전개 시 `baseCp.onEnter`/`onExit`/`onAbort` 훅 유실; `pre_ctx`에 `channelBound=true`, `atcCleared=true` 등 하드코딩; `maxSpeed`가 `nil`을 통과시키고 `preflight` 호출이 `system` 생략. | **No** |
| **FLT-HIGH-06** | `AMM` (`c2_arbiter`, `mission_engine`, `channel_sentinel`), `FCP`, `VAS`, `TCA`, `ASA`, `DOCKING_ARM` Spec | **Zero-Fallback 원칙 전방위 위반**: AMM이 `[DEPRECATED]`인 `Base+0` `MSG_OPERATOR_CMD`를 계속 송출하고 `channel_sentinel`이 `candidateBaseChannel`/`hardwareUuid` 누락; FCP/VAS/TCA/ASA 다수 모듈에 구형 듀얼키 폴백(`or`) 잔존(`FCP-NODE-04-4402` 등); `DOCKING_ARM` 사양서가 `[DEPRECATED]` 태그 없이 `MSG_DOCKING_ARM_CMD` 별칭을 필수 요구. | **Yes** |
| **FLT-HIGH-07** | `src/3_planning/amm/modules/trajectory_generator.lua:88-90,112-114,198,498` | **AMM 궤적 생성기 고도·모드 결함**: `generate_takeoff`가 `goal.targetAlt` 무시; `generate_cruise`가 `ACT_NAV_CHANGE_ALT` 등 `targetPos == nil` 시 `nav.pos.y`로 `targetAlt` 덮어씀; `generate_loiter` `vy=0` 고정(`ACT_PAT_LOITER_ALT` 불능); `[I-12]` 11종 열거형에 없는 `"IDLE"` 송출. | **No** |
| **FLT-HIGH-08** | `src/2_guidance/fcp/modules/outer_loop_controller.lua`, `state_propagator.lua`, `fcp/main.lua`, `fcp_config.json` vs `FCP_PROGRAM_SPECIFICATION.md` | **FCP `SE(3)` 법칙·설정키·`state_propagator` 괴리**: `maxAccelMps2` 클램프·TECS(`0.70 + surge_a/20`)·VTOL 추력(`hoverThrust + K_Ty*ay`)·`0.18` 스웨이 바이어스 등 사양 수식과 차이; 미존재 `cfg.guidance.*`·`se3`(사양 `outerLoop`)·`navStaleEpochMs`(config `navStaleTimeoutMs`) 참조; 부팅 직후 `lastTelemMs==0`으로 `navStale=true` 판정 및 `saturated=false` 하드코딩. (`FCP v2.0.0 Implemented` 재검토 필요) | **Yes** |
| **FLT-HIGH-09** | `VAS` `telemetry_feeder.lua:24,36-40`, `state_machine.lua:79-85,114`, `network_manager.lua:341-345`<br>`FCP` `main.lua:191-202`, `state_propagator.lua:25,70-71`, `ui_renderer.lua:68` | **VAS↔FCP/AMM `[I-1]`/`[I-2]` 텔레메트리 스키마·`MFD_ACRO` 양보 결함**: `FCP`가 요구하는 `actuatorHealth.allOk`를 Master ICD/VAS/AMM이 생략; `build_mfd_payload` 필드 누락 및 `velocity` vs `groundSpeed`; 비행 중 FCP 패킷이 `MFD_ACRO`를 선점 덮어쓰고, MFD 해제 시 FCP가 `PASSIVE_TRACKING`으로 패킷을 억제해 VAS가 1.5s 타임아웃에 의존. | **Yes** |
| **FLT-HIGH-10** | `src/1_control/tca/modules/tca_daemon.lua:108`<br>`src/1_control/tca/modules/actuator_adapter.lua:149-158,225-232` | **TCA 핫플러그 짐벌 리셋 & 비`setPower` 벡터 추력기 스케일 오류**: 주변장치 변경 시 스칼라 `lastSignal`로 `apply_thrust`를 호출해 `gimbalX/Y = 0` 초기화; `setPower` 미지원 벡터 추력기에서 `0..15` `boosted`를 `0..1` 입력 기대 함수 `dispatch_val`에 전달. | **No** |
| **FLT-HIGH-11** | Master ICD, Diagram, `GCS`, `GAC`, `LANDING_PAD`, `RUNWAY`, `DOCKING_ARM`, `ASA` 사양서 다수 | **사양서 간 와이어·채널·타임아웃 상호 불일치**: `[I-10]` `mode` vs `interactionMode` & `NOMINAL` vs `API_NOMINAL`; `[I-2]` GCS `authKey` 누락; `[I-6]` GCS `MSG_OPERATOR_CMD` 상이; `[I-5]` `MSG_FACILITY_BEACON`(`50003`) 4분열 및 이륙 허가 패킷/채널 분열; 슬롯 타임아웃 `60s` vs `120s`; `Base_sec+2`/`60005~60020`/`attitude.heading` 테이블 누락. | **Yes** |
| **FLT-HIGH-12** | `src/1_control/asa/main.lua:81,84,94-95,106-110`<br>`src/1_control/asa/modules/config_manager.lua:10` | **ASA 골격(`TASK-105` 연기 경계 외) 자체 결함**: `SAFE_GLIDE` vs `SAFE_GLIDE_TRIM`, `elevator=0.1` 하드코딩, `ver=="1.9.5"`/`domainId` 검증 생략, `schemaVersion` vs `version`, `s.ELEV or s.elevator` 듀얼키 폴백. | **Yes** |

---

### 🟡 MEDIUM (15건) — 엣지케이스 방어 누락 · 부분 스펙 미구현 · 가드/설정 결함

| ID | 대상 파일 (`File:Line`) | 근본 원인 요약 | Grilling |
| :--- | :--- | :--- | :---: |
| **DEV-MED-01** | `align_master.lua:153`, `tca/discovery_handler.lua:83`, `vas/network_manager.lua:201-203`, `ALIGNMENT_PROGRAM_SPECIFICATION.md:816-824` | `ALIGNMENT` 스펙(`Base_hangar+3`) vs 코드(`replyChannel=Base_hangar+1`); VAS `MSG_CALIBRATION_INIT_ACK` 내 `hardwareUuid`/`airframeType` 누락; 사양서 §11.1 모듈 파일명 오기. | **Yes** |
| **DEV-MED-02** | `src/0_development/installer/installer_app.lua:105-107` vs `migration_engine.lua:172` | `migrateFile` 3개 반환값 중 2개만 받아 실패 시 `err`가 항상 `nil` 로깅됨. | **No** |
| **DEV-MED-03** | `src/0_development/installer/installer.lua:127-220` vs `downloader.lua:155-200` | 루트 부트스트랩 다운로더에 Google Drive HTML interstitial 확인 및 `confirm=`/`uuid=` 재시도 누락. | **No** |
| **DEV-MED-04** | `config/gdrive_mapping.json:5,21-22`, `tools/sync_gdrive.py:294`, `manifest.lua` | `gdrive_mapping.json`에 패키지 파일 미등록(`--strict-gdrive-packages` 104 Errors), `manifest.lua` `sizeBytes` 구버전(`35098` vs `36561`), `lastSync` 날짜 하드코딩. | **Yes** |
| **INF-MED-01** | `src/0_infra/gps/server.lua`, `node.lua:34`, `hal/wizard_cli.lua:90` | `GPS v2.3.2 Implemented` 대비: `server.lua` 단일 루프(`parallel` 3코루틴·10s/35s 워치독·60s 상호보정·커미셔닝 핸들러·모니터 크기/컬러 검사·`CALIBRATE`/`CLEAR` 미구현), `listenChan=60001` 오표기, `node.lua` `compId` 미전달, `wizard_cli.lua` `top` vs `back`. | **Yes** |
| **INF-MED-02** | `src/0_infra/landing_pad/main.lua`, `offset_transform.lua`, `pad_fsm.lua:232-238` | `LANDING_PAD v2.4.4 Implemented` 대비: 3s 부팅/5단계 마법사 생략, 2D 요 회전만 구현(피치/롤 및 $\omega \times r$ 누락), `slotRemainingSec=120` 고정, `GO_AROUND -> IDLE` 10s 자동 복귀(GAC `FREE` 미대기). | **Yes** |
| **INF-MED-03** | `src/0_infra/gac/main.lua`, `gac_fsm.lua`, `facility_inventory.lua`, `tui_view.lua` | `GAC v1.4.2 Implemented` 대비: `traffic={}` 고정, 모니터 핫플러그/`[Enter]`/`[S]` 미구현, `maintenancePads=0` 고정 및 전용 `FREE` 패드를 `occupiedPads`로 오계산, `DOCKING_ARM` 집계 누락. | **Yes** |
| **INF-MED-04** | `src/0_infra/gcs/main.lua`, `channel_manager.lua`, `fleet_tracker.lua`, `ui_renderer.lua` | `[C]hannelReg` 키 핸들러 미구현, `updatedAt="2026-11-08"` 고정 및 비원자적 저장, `airframeType or airframe or mode` 폴백. | **No** |
| **TST-MED-01** | `harness/unit/static_guard.py:222-241,265,338-377,425-445` | 정적 가드 7대 누락: 금지 모드 토큰/접두사 누락(`valkyrien_pirates`, `vs_trackwork:` 등), 경계 정규식으로 `vs_trackwork` 미탐지, `peripheral.wrap("ship")` 미탐지, 구형 `arg` 미검사, 루트 `installer.lua`/`harness`/`tools` 스캔 제외, 루프 yield 가드 부재, 크로스 서브시스템 `require` 차단 부재. | **No** |
| **FLT-MED-01** | `src/3_planning/amm/modules/nav_engine.lua:62,120-143,156` | `gpsRequestRateHz==0` 0 나눗셈, DR `is_finite_number` 부재, `NaN`이 `hdop` 게이트 통과, `accuracy > 2.0` 시 `alpha <= 0.10` 미적용. | **No** |
| **FLT-MED-02** | `src/3_planning/amm/modules/facility_client.lua:237` | `>` vs `>=` off-by-one으로 ATC 거부를 10회가 아닌 11회 허용. | **No** |
| **FLT-MED-03** | `src/3_planning/amm/modules/c2_arbiter.lua:61-67,356,412-417` | `GCS_OVERRIDE` 6개 비행 모드 무시, `ESTOP` `self.net` nil 가드 부재, FCP 복귀 후 `emergencyGoal` 미해제. | **No** |
| **FLT-MED-04** | `src/3_planning/amm/main.lua`, `mission_engine.lua:857-889`, `condition_evaluator.lua:8-23` | `Ctrl+X` E_STOP 미배선, CLI(`add`/`alt`/`spd`/`rad`/`clear`) 큐-엔진 비동기화, 동일 50ms 틱 `settleTicks` 이중 증가, `CONDITION_TYPES` 14종(`SYS_ARMED`/`IMMEDIATE`) vs 사양 12종. | **Yes** |
| **FLT-MED-05** | `vas/actuator_adapter_tca.lua:216-220`, `core_daemon.lua:58`, 미사용 모듈·구형 노드 | 단일 TCA 비율로 `dynamicLoad` 덮어쓰기, `core_daemon` 모듈 로드 시점 config I/O 실행, 미사용 모듈(`dynamic_trim_compensator`, `preflight_bit`) 및 구형 시뮬레이터 노드(`ATTITUDE_ANGLE` 등). | **No** |
| **FLT-MED-06** | `AMM_PROGRAM_SPECIFICATION.md`, `AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.2.0 Draft`) vs `Task-204` 설계서 | `AMM v2.0.0` 내 파라미터·부등호 수치 오차(`toleranceM` `5.0` vs `1.5`/`2.0`, `arrivalRadius` `15.0` vs `5.0`, `<` vs `<=`); Draft 에디터 사양서에 삭제된 `v1.3.0` 액션/필드/오류명(`ORBIT`/`PATROL`/`PAYLOAD_ACTION`/`FLY_TO` 등) 잔존. | **Yes** |

---

### 🟢 LOW (4건) — UI 자리표시자 · 테스트 사각지대 · 문서 오기

| ID | 대상 파일 (`File:Line`) | 요약 | Grilling |
| :--- | :--- | :--- | :---: |
| **TST-LOW-01** | `vas/{preflight_bit,dynamic_trim_compensator,vec3}.lua`, `amm/mission_controller.lua`, `tca/channel_rebind_handler.lua`, `alignment/{impulse_integrator,safety_sentinel,settling_guard}.lua` | 완전 미호출 모듈 4종(약 570줄), 단위 테스트 공백 모듈 4종, 돌연변이 테스트(`asa/` 및 `amm` 코어 미션·궤적·채터링 엔진 0건). | **No** |
| **FLT-LOW-01** | `amm/ui_renderer.lua:150`, `waypoint_queue.lua:115-119` | `ACTR : ALL_HEALTHY` 고정 출력 및 레거시 `"1.0.0"` `items[]` 큐 영속화. | **No** |
| **FLT-LOW-02** | `src/2_guidance/fcp/main.lua:273`, `ui_renderer.lua:76` | `debug: true` TUI 모드에서 임의 키 입력 시 `parallel.waitForAny` 데몬 종료. | **No** |
| **FLT-LOW-03** | `TCA:611`, `VAS:10,19,1490,1507`, `FCP:10,34`, `Master ICD:80,153,1404,1551-1552`, `Diagram:53,125,287-288,304`, `INSTALLER:15-16` | 사양서 오기(`N*20`, `Date` vs `RevTop`, `offsetTap`, `v2.4.0`, `MSG_MISSION_CMD_ACK`, `PAYLOAD_ACTION`, `FCP`/`VAS` `Approved` 잔존 표기, `INSTALLER` 구버전 배지). | **No** |

---

### ❌ 기각된 오탐 및 보정 사항 (False Positives Rejected)
1. **`src/0_infra/gps/client_entry.lua` 미사용 스텁 오탐 기각**: `src/0_infra/gps/main.lua:12`에서 `shell.run("client_entry.lua", ...)`로 직접 실행됨 (단, 테스트 공백은 사실).
2. **`src/1_control/tca/modules/discovery_handler.lua:83` `replyChannel` 오탐 기각**: `TCA` 사양서 `L402`는 `replyChannel` 응답을 명시하며, 실제 불일치는 `ALIGNMENT` 사양서 `L661`(`Base_hangar+3`) vs `align_master.lua:153`(`Base_hangar+1`).
3. **`FCP` 사양서 Rebind 스키마 불일치 부분 기각**: `FCP_PROGRAM_SPECIFICATION.md:760-767` 자체는 코드(`transactionId`/`action`/`oldBaseChannel`/`newBaseChannel`/`500ms`)와 일치하며, 진성 분열은 **Camp A(`Master ICD`·`VAS`·`AMM`·`Diagram`) vs Camp B(`FCP`·`ASA`·`TCA`)** 간 문서 충돌임.
4. **`AMM` `facility_client.lua:159,162` 가이드 스키마 보정**: `LANDING_PAD` 사양·코드와는 호환되나 `Master ICD`·`RUNWAY`·`DOCKING_ARM`과 불일치함.

---

## 3. 수정 착수 전 Grilling 필요 중대 결정사항 (Decision Gates)

아래 **8개 핵심 결정 축**은 코드와 사양서가 충돌하거나(SSOT 부재), Mixed-Scope 동시 개정이 필요하거나, 연기 과제 및 배포 정책이 걸려 있어 **개별 수정 TASK 생성·착수 전 유저 확정**이 필요합니다.

1. **`[I-9]` 4계층 `MSG_CHANNEL_REBIND` 정본 통일 (`FLT-CRIT-06`)**:
   - Camp A (`Master ICD`/`VAS`/`AMM`/`Diagram`: `MSG_REBIND_ACK`, `phase`, `oldBase`, `newBase`, `1000ms`) vs Camp B (`FCP`/`ASA`/`TCA` 사양 및 **모든 런타임 Lua 코드**: `MSG_CHANNEL_REBIND_ACK`, `transactionId`, `action`, `oldBaseChannel`, `newBaseChannel`, `500ms`) 중 어느 쪽을 단일 정본(SSOT)으로 채택할지?
2. **`[I-4]` 격납고 캘리브레이션 와이어 및 `Alignment`/`GPS`/`Landing Pad`/`GAC`/`FCP` `Implemented` 사양서 대코드 불일치 처리 방향 (`FLT-CRIT-08`, `FLT-HIGH-08`, `DEV-HIGH-01`, `DEV-MED-01`, `INF-MED-01~03`)**:
   - 현재 `Implemented`로 표기된 사양서(`Alignment`, `GPS`, `Landing Pad`, `GAC`, `FCP`)에 미구현 기능(예: `Alignment` 5개 FSM 상태, `GPS` 3코루틴·상호보정·커미셔닝, `Landing Pad` 3D 오일러·5단계 마법사, `FCP` TECS·`outerLoop` 키)이 다수 존재함 → **(A) 코드에 맞춰 사양서 범위 현실화**, **(B) 사양서 기준으로 코드 대대적 구현 + 사양서 일시 `Approved` 강등**, **(C) 핵심 버그만 우선 수정 후 기능 갭은 별도 백로그 TASK 분리** 중 선택.
3. **`[I-5]` `MSG_FACILITY_DYNAMIC_GUIDE` & `MSG_FACILITY_BEACON` 스키마 통일 + `IDLE` vs `FREE` (`INF-CRIT-01`, `FLT-CRIT-09`, `FLT-HIGH-11`)**:
   - `Landing Pad`의 `MSG_ATC_FACILITY_UPDATE.status`를 `"FREE"`/`"OCCUPIED"` 매핑으로 고칠지, GAC가 수락할지; 그리고 `MSG_FACILITY_DYNAMIC_GUIDE`를 `touchdownPoint`/`attitude` vs `thresholdPoint`/`deckAttitude` vs 설비별 분리 중 어떻게 통일할지(특히 연기 사양서 `RUNWAY`·`DOCKING_ARM` 포함 여부).
4. **`[I-10]` `VAS -> ASA` 스케일(`[-1,1]` vs `0..15`), `mode` vs `interactionMode`, `ASA` 골격 범위 (`FLT-CRIT-05`, `FLT-HIGH-11`, `FLT-HIGH-12`)**:
   - `VAS`가 `[-1.0, +1.0]` 정규화 값을 보내고 `VAS §9.5` 키(`surfaceGeometry` 등)로 통일하는 동시에 `TASK-105/210` 연기 중인 `src/1_control/asa/` 골격의 명확한 결함(`SAFE_GLIDE_TRIM`, 폴백 제거)까지 이번에 함께 고칠지?
5. **`AMM` Zero-Fallback(`Base+0` `MSG_OPERATOR_CMD`) · 채터링 가드 API 방향 (`FLT-HIGH-03`, `FLT-HIGH-06`, `FLT-MED-04`, `FLT-MED-06`)**:
   - `AMM`의 구형 `Base+0` `MSG_OPERATOR_CMD` 송출을 즉시 전면 제거(Zero-Fallback)할지, `chattering_guard.lua`(`HIGH_ACTIVE`/`lowFuelLatched`)와 `2026-11-13` 설계서(`HIGH_ENTER`/`rtl`) 중 어느 쪽 API를 정본으로 맞출지, `AMM_MISSION_EDITOR_SPECIFICATION.md` Draft 동기화를 `TASK-402`로 넘길지 이번 감사에서 선행 정리할지?
6. **`[I-1]`/`[I-2]` `VAS ↔ FCP/AMM` `actuatorHealth.allOk`, `MFD_ACRO` 해제 신호, `Vehicle Policy` 실속 추력 단위 (`FLT-HIGH-02`, `FLT-HIGH-09`)**:
   - `actuatorHealth.allOk`를 Master ICD/VAS에 추가할지 FCP에서 계산/제거할지, `MFD_ACRO` 해제 시 즉시 `Base+3` 복귀 패킷을 도입할지(와이어/FSM 변경), `minStallThrottle`을 `[0..1]` 정규화로 통일할지 `0..15`로 바꿀지?
7. **Zero-Fallback 폴백 제거 범위 및 `DOCKING_ARM` 별칭 정책 (`FLT-HIGH-06`, `FLT-MED-05`, `TST-LOW-01`)**:
   - `VAS`/`FCP`/`TCA`/`GCS` 코드 내 구형 키 폴백(`or`)과 `preflight_bit.lua`/`dynamic_trim_compensator.lua`/`vec3.lua`/`mission_controller.lua` 고립 모듈을 즉시 삭제(Zero-Fallback)할지 단계별 제거할지?
8. **Google Drive 패키지 배포 정책 (`DEV-MED-04`)**:
   - `config/gdrive_mapping.json`에 12개 서브시스템 패키지 파일(104개)을 등록해 `--strict-gdrive-packages`까지 통과시킬지, 현행 9개 부트스트랩/공용 파일 한정 매핑 정책을 유지하고 stale `sizeBytes`/`lastSync`만 수정할지?

---

## 4. Grilling 확정 결정(Q1~Q8 + Q3-1) 및 Wave 1~3 교정·검증 결과

### 4.1 사용자 확정 결정 요약
- **Q1 (`[I-9]` `MSG_CHANNEL_REBIND`) — 방안 A**: `MSG_CHANNEL_REBIND` / `MSG_CHANNEL_REBIND_ACK` + `{ transactionId, action = "PREPARE"|"COMMIT"|"ROLLBACK", oldBaseChannel, newBaseChannel, bandwidth = 40 }` + `500ms` 타임아웃(`"READY"|"COMMITTED"|"ROLLED_BACK"|"FAILED"`)으로 통일. `VAS`는 `TCA`/`ASA` ACK 대기 후 `system.json` 영속화, `FCP`는 `ROLLBACK` 전 상위 `oldBase+4`로 `FAILED` NACK 송출 및 `fcp_config.json` 영속화, `TCA`는 `500ms` `PREPARE` 워치독 구현, `AMM`은 `channel_sentinel` 및 `apply_rebind` 배선.
- **Q2 (`Implemented` 5대 사양서 & `[I-4]` 격납고 캘리브레이션) — 방안 A**: `Alignment`, `GPS`, `Landing Pad`, `GAC`, `FCP`의 미구현 사양 기능 보완 및 `[I-4]` 와이어 계약(`MSG_CALIB_PULSE` `Base_hangar+0`, `MSG_ACTUATOR_DISCOVER_REQ/ACK` `Base_hangar+3`·`replyChannel = 104`·`targetGroup = "ALL"`, `MSG_CALIB_BAY_BIND.baseHangarChannel`, `MSG_CALIBRATION_INIT_ACK` `hardwareUuid`/`airframeType`, `MSG_PROFILE_SYNC.discoveredSurfaces` 객체 맵 + `"RUDD"`, `saveProfile = true`) 단일화.
- **Q3 & Q3-1 (`[I-5]` 시설물 가이드, 진입 방향, 보조 필드, 비콘, 상태) — 방안 A + 확장 스키마**: `Landing Pad` FSM 상태의 `MSG_ATC_FACILITY_UPDATE` 매핑(`IDLE -> "FREE"`, `APPROACH_* -> "RESERVED"`, `DEPARTURE_PENDING -> "OCCUPIED"`, `GO_AROUND -> "MAINTENANCE"`); `MSG_FACILITY_STATIC_GUIDE`·`MSG_FACILITY_DYNAMIC_GUIDE` 공통 필드(`approachDirection`: 패드 `"DOWNWARD"`, 활주로 `"FRONT"|"BACK"`, 도킹암 6축, `deckStatus`, `landingPermitted`, `abortAlert`, 동적 `velocity`/`acceleration`/`angularRates`, 설비별 대칭 보조 필드); `CH 50003` `MSG_FACILITY_BEACON` `GAC` 일원화(`totalDockingArms`/`freeDockingArms`), 슬롯 타임아웃 `120s`, `MSG_GAC_ABORT_CLEAR` `Base_sec+0`.
- **Q4 (`[I-10]` `VAS <-> ASA` & `ASA` 골격) — 방안 B (부분 동결)**: `VAS`(`actuator_adapter_asa.lua`, `core_daemon.lua`)는 정규화 `[-1.0, +1.0]`/`[0.0, 1.0]` + `dynamicPressureFactor` + `VAS §9.5` 키로 선행 정렬하되, `src/1_control/asa/**` 및 `tests/1_control/asa/**`는 `TASK-105` 재개 시까지 `0 diff` 동결 유지 및 `FLT-HIGH-12` 5대 결함을 `TASK.md` `TASK-105` 주석으로 이관.
- **Q5 (`AMM` `Base+0`, 채터링 가드, 14종 조건, 에디터 Draft) — 방안 A**: `AMM`의 `Base+0` `MSG_OPERATOR_CMD` 송출 제거(`Base+4` `[I-12]` 단일 경로), `chattering_guard.lua`(`HIGH_ENTER`/`rtl`)·`2026-11-13` 설계서·`main.lua`/`c2_arbiter.lua`/`mission_engine.lua` 통합, `AMM v2.0.1` 14종 조건(`SYS_ARMED`, `IMMEDIATE`) 반영 및 `AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.3.1 Approved`) 내 `v1.3.0` 잔재 제거.
- **Q6 (`[I-1]`/`[I-2]` `allOk`, `MFD_ACRO`, 실속 단위) — 방안 A**: `VAS`·사양서에 `actuatorHealth.allOk = (tap and asa)` 추가, `FCP`의 `MFD_ACRO` 중 `activeSource` 덮어쓰기 차단 및 `MFD_ACRO` 침묵 만료 시 `ACTIVE_FLIGHT` 즉시 복귀, `minStallThrottle` `[0.0, 1.0]` (`0.40`) 정규화.
- **Q7 (Zero-Fallback, 고립 모듈, 정적 가드) — 방안 A**: 듀얼키 `or` 폴백 및 구형 식별자(`FCP-NODE-04-4402`), `DOCKING_ARM` 비태그 별칭 `MSG_DOCKING_ARM_CMD`, 고립 모듈 6종(`vas/{preflight_bit,dynamic_trim_compensator,node_fcp,node_asa}.lua`, `fcp/node_vas_sim.lua`, `amm/mission_controller.lua`) 제거(`vec3.lua` 유지), `harness/unit/static_guard.py` 7대 누락 보완.
- **Q8 (GDrive & `TASK-501`) — 방안 A + 후속 과제 분리**: `installer_app.lua` 3-리턴 언팩, 루트/소스 `installer.lua` GDrive HTML interstitial 바이트 동일 반영, `tools/sync_gdrive.py` 동적 UTC 타임스탬프, `config/gdrive_mapping.json` 9종 부트스트랩/공용 해시 갱신, 전수 104패키지 업로드 및 `--strict-gdrive-packages` 활성화는 `TASK.md` `TASK-501`로 등록.

### 4.2 Wave별 이행 내역 및 승격
1. **Wave 1 (Spec-First 전역 동기화)**: `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.30.0 Approved`), `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.15.0 Approved`), `AMM_PROGRAM_SPECIFICATION.md` (`v2.0.1 Approved`), `AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.3.1 Approved`), `RUNWAY_SPECIFICATION_AND_ICD.md` (`v1.11.0 Approved`), `DOCKING_ARM_SPECIFICATION_AND_ICD.md` (`v1.12.0 Approved`), `ASA_PROGRAM_SPECIFICATION.md` (`v1.8.0 Approved`), `INSTALLER_PROGRAM_SPECIFICATION.md` (`v1.1.1 Implemented`), `2026-11-13-task-204-chattering-prevention-design.md` 및 Wave 2 코드 반영 대상 8종 사양서 동기화.
2. **Wave 2 (런타임·하네스·테스트 교정)**: `src/0_development/{alignment,installer}/`, `src/0_infra/{gps,gac,gcs,landing_pad}/`, `src/1_control/{vas,tca}/`, `src/2_guidance/fcp/`, `src/3_planning/amm/`, `harness/unit/static_guard.py`, `tools/sync_gdrive.py`, `tools/run_mutation_tests.py`, `config/gdrive_mapping.json` 및 대응 테스트 슈트 일괄 교정 (`src/1_control/asa/**`·`tests/1_control/asa/**` `0 diff` 동결).
3. **Wave 3 (독립 교차 검증, 8종 `Implemented` 승격 & 컨텍스트 동기화)**: `verifier-infra` 및 `verifier-flight` 최종 `PASS` 판정 후 `ALIGNMENT (v2.7.0)`, `GPS (v2.3.3)`, `GAC (v1.5.0)`, `GCS (v1.1.0)`, `LANDING_PAD (v2.5.0)`, `VAS (v1.20.0)`, `TCA (v1.12.0)`, `FCP (v2.1.0)` 8종 사양서를 `Implemented`로 승격하고 `TASK.md`(`TASK-013` 완료 이관, `TASK-105` 주석, `TASK-501` 등록), `.agent/memory/workspace-root.md`, `GEMINI.md`를 동기화함.

### 4.3 최종 순차 검증 증거 (Step 5B 실측)
| 검증 명령 | 실측 결과 |
| :--- | :--- |
| `python tools/verify_context_docs.py` | **Exit 0** (`[PASS] context docs: 0 findings`) |
| `python tools/verify_all_specs.py --check-readmes` | **Exit 0** (`ALL 15 SPECS 100% CLEAN (0 Errors, 0 Warnings)`, `8 READMEs 0 error(s)`) |
| `python tools/verify_spec_status.py` | **Exit 0** (`All 15 specs have valid statuses (9 Implemented, 6 Approved)`, 에디터 `v0.3.1 Approved` 포함 16종 정합) |
| `python tools/verify_manifest_sync.py` | **Exit 0** (`12 modules`, `109 manifest paths`, `120 source files`, `9 GDrive entries`, `0 Errors, 0 Warnings`) |
| `python tools/validate_lua_syntax.py` | **Exit 0** (`117/117` Lua 5.2 OK) |
| `python -m unittest discover -s tests/harness -p "test_*.py"` | **Exit 0** (`88/88 OK`, `7.492s`) |
| `python tools/run_unit_tests.py --require-tests --clean-orphans` | **Exit 0** (`12/12 targets`, `504/504 PASS`) |
| `python tools/run_e2e_tests.py --clean-orphans` | **Exit 0** (`8/8 suites`, `13/13 PASS`, `754.47ms`) |
| `python tools/run_mutation_tests.py` | **Exit 0** (`25/25 KILLED`, `0 Survived`, `100.0% >= 90.0%`, `27.16s`) |
| `& "C:\Program Files\Git\cmd\git.exe" status -s -- src/1_control/asa/ tests/1_control/asa/` | **Exit 0** (빈 출력 — 동결 범위 `0` 변경) |
