# Workspace Root Memory Archive

본 문서는 `Create_Aeroneutics` 루트 및 하네스 기반 구조의 주요 의사결정 이력을 최신순(ISO 날짜)으로 기록하는 온디맨드 아카이브입니다.

---

## 2026-11-14 — AMM WebUI Mission Editor(tools/amm_mission_editor.html) 구현, CraftOS-PC 라운드트립 및 AMM·에디터 사양 Implemented 승격 (TASK-402)

- **결정 배경**: `/grill-me`·`frontend-design`·`web-design-guidelines` 기반으로 `AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.3.1 Approved`)를 구체화하고, `mission_engine.lua` 런타임 SSOT와의 100% 패리티(`cp.onEnter`/`onExit`/`onAbort` 최상위 훅, `ACT_NAV_CORRIDOR` 양 끝점 필수, `{ logic: "ALL"|"ANY"|"NOT", conditions: [...] }` 조건 그룹, `TIMEOUT_SEC.timeout`)를 보장하는 오프라인 단일 파일 HTML 에디터(`tools/amm_mission_editor.html`)를 구현함 (`docs/superpowers/plans/2026-11-14-task-402-amm-mission-editor.md`).
- **반영 내역**:
  1. **`tools/amm_mission_editor.html` (9 IIFE 모듈)**: `SchemaConstants`·`DefaultResolver`·`MacroExpander`(36+22 `ACT_*`, 6+1 `DEC_*`, 3+2 `MAC_*`, 19종 `preconditions`, 14종 조건, 4종 훅, `_extra` 보존), `Validator`(Legacy `items[]`/13종 액션 Zero-Fallback 거부·3종 `DEFERRED_*` 경고·100-CP <50ms), `Store`(50단 Undo/Redo·드래그 트랜잭션 병합·`fieldPath` 탭 자동전환·`uafs_amm_editor_autosave_v1`), `JsonIO`(`version: "2.0.0"` 단일 출력·3종 프리셋), `CanvasRenderer`(8레이어 2D 전술 맵·`REPEAT` 루프백·`Selected-Node Priority` 히트테스트·접이식 120px `#altProfilePane`), `InspectorUI`·`AppBootstrap`(무 `innerHTML`/무 `window.alert`/무 외부 URL·다크 HUD·`:focus-visible`·`aria-label`·`1150px` 반응형).
  2. **사양 승격 & 검증 정합화**: `AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.3.1 Implemented`) 및 `AMM_PROGRAM_SPECIFICATION.md` (`v2.0.1 Implemented`) 승격, `tools/verify_spec_status.py` (`11 Implemented, 5 Approved`) 동기화, `TASK.md` 10개 상한 유지(`TASK-122` 이력 정리, 본 아카이브 기보존).
- **검증**: `test_amm_mission_editor.py` `17/17 PASS`(Node 단위/DOM-shim XSS+A11y+CraftOS-PC `mission_engine.validate_mission` 라운드트립), 단위 12타겟 `504/504 PASS`, E2E 8스위트 `13/13 PASS`, `test_terminology_guard.py` `7/7 PASS`, `verify_manifest_sync.py` `0 Errors, 0 Warnings`, HTML 정적 감사 `0 findings`.

---

## 2026-11-14 — 전사 사양서·코드베이스·하네스 전수 감사(43건 교정), 8종 사양서 `Implemented` 승격 및 컨텍스트 동기화 (TASK-013)

- **결정 배경**: 기존 정적/단위 파이프라인(Exit 0)에서 포착되지 않던 계층 간 와이어 계약 분열, `Implemented` 사양서 대비 미구현 기능, Zero-Fallback 위반, 미연동 가드 및 하네스 `static_guard.py` 누락을 전수 식별(`43`건 확정: Critical `10`·High `14`·Medium `15`·Low `4`, 오탐 `4`건 기각)하고 Q1~Q8+Q3-1 사용자 Grilling 확정안에 따라 Wave 1(사양서 동기화) → Wave 2(런타임/테스트/하네스 교정) → Wave 3(독립 교차 검증 및 `Implemented` 승격)를 완수함.
- **확정 결정 및 반영 내역**:
  1. **Wave 1 전역 사양 동기화 (16종 사양서 + `TASK-124` 설계서)**: `[I-9]` `MSG_CHANNEL_REBIND`/`MSG_CHANNEL_REBIND_ACK` Option A(`transactionId`, `action = "PREPARE"|"COMMIT"|"ROLLBACK"`, `oldBaseChannel`, `newBaseChannel`, `bandwidth = 40`, `500ms`) 단일화(Q1); `[I-4]` `MSG_CALIB_PULSE`(`Base_hangar+0`)·`MSG_ACTUATOR_DISCOVER_REQ/ACK`(`Base_hangar+3`, `replyChannel = 104`, `targetGroup = "ALL"`)·`MSG_CALIB_BAY_BIND`(`baseHangarChannel`)·`MSG_PROFILE_SYNC.discoveredSurfaces` 객체 맵+`"RUDD"`·`saveProfile`(Q2); `[I-5]` `Landing Pad -> GAC` `"IDLE"->"FREE"` 매핑, 3종 시설물 공통 가이드 스키마(`approachDirection`: `DOWNWARD`/`FRONT|BACK`/6축, `deckStatus`, 동적 `velocity`/`acceleration`/`angularRates`, 설비별 보조 필드) 및 `CH 50003` `GAC` 단일 송출·`120s` 타임아웃(Q3/Q3-1); `[I-10]` `interactionMode`/`appliedDeflection`/`"NOMINAL"|"DEGRADED"|"TOTAL_LOSS"`(Q4); `AMM` `CONDITION_TYPES` 14종(`SYS_ARMED`, `IMMEDIATE`) 정규화 및 `AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.3.1 Approved`) 내 `v1.3.0` 잔재 제거(Q5); `[I-1]`/`[I-2]` `actuatorHealth.allOk`·`MFD_ACRO` 침묵 즉시 복귀·`minStallThrottle` `[0.0, 1.0]`(`0.40`)(Q6); `DOCKING_ARM` 비태그 별칭 제거(Q7).
  2. **Wave 2 코드·테스트·하네스 교정 (`src/1_control/asa/**` `0 diff` 동결 준수)**: `alignment`/`installer` (`align_master.lua` 5개 FSM·`ABORT`·`cfg.safety`, `installer_app.lua` 3-리턴 언팩, `installer.lua` GDrive HTML interstitial 양쪽 바이트 패리티, `sync_gdrive.py` 동적 UTC 타임스탬프 및 `gdrive_mapping.json` 9종 해시 갱신), `gps`/`gac`/`gcs`/`landing_pad` (`GPS` 3코루틴·워치독·커미셔닝, `Landing Pad` 3D 오일러+$\omega \times r$·5단계 마법사·`FREE` 매핑, `GAC` 전용 패드/도킹암 비콘 집계·슬롯 타임아웃, `GCS` `main.lua` 인자/경로/저장 수정), `vas`/`tca`/`fcp` (`VAS` 3D 레버암 외적 부호·패닉 FSM/쿠션 추력·`[-1.0,+1.0]` ASA 어댑터 & `VAS §9.5` 키·`allOk`·Option A `PREPARE` 워치독·`PREPARE`/`COMMIT` 디스크 영속화, `TCA` 500ms 워치독·벡터 스케일/핫플러그, `FCP` `WINGED_VTOL` `vHigh==vLow`/보간·`SE(3)` 수식/`outerLoop` 키·`MFD_ACRO` 선점 차단 및 `ACTIVE_FLIGHT` 복귀), `amm` (`Base+0` 송출 제거, `Base+2` `FCP` 텔레메트리 배선 및 `Base+3` 격리·self-echo 차단·부팅 Auto-Arm 제거, 듀얼 모뎀/GDrive/재바인딩·`chattering_guard.lua` API 정렬 및 런타임 연동·미배선 7액션/2데코레이터/매크로 훅/궤적/비콘/ATC 재시도 수정), 고립 모듈 6종 삭제(`vas/{preflight_bit,dynamic_trim_compensator,node_fcp,node_asa}.lua`, `fcp/node_vas_sim.lua`, `amm/mission_controller.lua`), `harness/unit/static_guard.py` 7대 누락 보강 및 `run_mutation_tests.py` 타겟 현행화(`MUT-13`/`15`/`23`).
  3. **후속 이관 & 승격 (`Wave 3`)**: `@verifier-infra`·`@verifier-flight` 독립 교차 검증 완료 후 Wave 2 대상 8종 사양서(`ALIGNMENT v2.7.0`, `GPS v2.3.3`, `GAC v1.5.0`, `GCS v1.1.0`, `LANDING_PAD v2.5.0`, `VAS v1.20.0`, `TCA v1.12.0`, `FCP v2.1.0`)를 `Implemented`로 승격하고, Q4 방안 B에 따른 `ASA` 5대 골격 결함(`FLT-HIGH-12`)을 `[연기] TASK-105` 주석에 이관했으며 Q8 후속 전수 101패키지 GDrive 업로드를 `TASK-501`로 등록함. (`TASK.md` 10개 상한 유지를 위해 `TASK-201`은 완료 이력에서 정리—본 아카이브 기보존).
- **검증**: 단위 12타겟 `504/504 PASS`, E2E 8스위트 `13/13 PASS`, 돌연변이 `25/25 KILLED`(`100.0%`), 하네스 `88/88 PASS`, Lua 5.2 `117/117 PASS`, `verify_manifest_sync.py`(`12` 모듈/`109` 경로/`120` 소스/`9` GDrive)·`verify_all_specs.py --check-readmes`(15종) `0 Errors, 0 Warnings`, `verify_spec_status.py` `9 Implemented, 6 Approved PASS`, `verify_context_docs.py` `0 findings`.

---

## 2026-11-14 — GPS 고부하·위상 분산 수정 및 AMM v2.0.0 행동 체계·채터링 가드 통합 (TASK-123, TASK-204)

- **결정 배경**: `TASK-122` 후속 고부하 GPS 경합·버스트·채널 오염 결함(`TASK-123`)을 먼저 해소한 뒤, `TASK-124` 채터링 방지 규격과 `2026-11-12` 설계서를 기반으로 `AMM`의 구 13종 체크포인트를 Zero-Fallback 폐기하고 `AMM v2.0.0` `ACT_*`/`DEC_*`/`MAC_*`/진입조건/방안 A 채터링 방지 가드 체계(`TASK-204`)를 통합함 (`TASK.md`, `GEMINI.md` 동기화).
- **반영 내역**:
  1. **`TASK-123` — GPS 고부하 경합·위상 분산·채널 오염 수정 (`e9fdce4`)**: `src/0_infra/gps/modules/session_scheduler.lua`(`ingestReport` 선제 세션 대체 및 `flushExpired` Window-Solve HWM 역전 가드), `src/0_infra/gps/modules/client_core.lua`(`lastReceivedSeq` 단조 필터 및 `CH 60001` 미개방 가드), `src/0_infra/landing_pad/modules/gps_client.lua`·`src/3_planning/amm/modules/nav_engine.lua`(`os.getComputerID()` 기반 `should_query_gps` 위상 분산), `src/0_infra/landing_pad/main.lua`(`CH 60001` 수신 개방 제거), `GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v2.3.2 Implemented`), `LANDING_PAD_SPECIFICATION_AND_ICD.md` (`v2.4.4 Implemented`) 및 연관 사양서 배지·`test_e2e_gps_triangulation.lua` 검증을 반영함.
  2. **`TASK-204` Spec-First 개편 (`Stage 3A`)**: `AMM_PROGRAM_SPECIFICATION.md` (`v2.0.0 Approved`), `AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.2.0 Draft`), `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.29.0 Approved`), `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.14.0 Approved`) 및 연관 11종 사양서를 일괄 동기화함 (`AMM` 사양서는 `TASK-402` 완료 시 `Implemented` 승격 예정).
  3. **`TASK-204` AMM v2.0.0 & 채터링 가드 구현 (`Stage 3B`)**: `src/3_planning/amm/modules/chattering_guard.lua`(`PRIORITY`, `DEFAULT_CONFIG`, `init`, `reset`, `eval_hysteresis`, `eval_debounce`, `start_dwell`, `is_dwell_locked`, `update_fuel_latches`, `should_skip_on_repeat`), `src/3_planning/amm/modules/action_registry.lua`(활성 36종 `ACT_*`, 예약 22종, 구 13종 `SCHEMA_INVALID` 차단, 6+1종 `DEC_*`, 3+2종 `MAC_*` `deep_copy` 전개, 4대 정적/동적 진입조건), `src/3_planning/amm/config/amm_config.json`(`v2.0.0` + `safety.chattering` 20키), `condition_evaluator.lua`·`hook_runner.lua`·`ui_renderer.lua`·`input_handler.lua`(`guard`/`confirm`)·`c2_arbiter.lua`·`mission_engine.lua`·`main.lua`(`ACT_NAV_SPLINE_WP`/`ACT_TKL_LAND_PREC`, `DEC_EMCON` GPS 억제, `set_cruise_goal`/`set_land_goal` 2인자 수정) 및 `src/0_development/installer/modules/manifest.lua`(`v2.0.0` + 신규 2모듈)를 통합함.
- **검증**: 단위 12타겟 `469/469 PASS`(`3_planning/amm` `122/122`, `0_infra/gps` `29/29`, `0_infra/landing_pad` `46/46`), E2E 8스위트 `12/12 PASS`, 돌연변이 `25/25 KILLED`(`100.0%`), Lua 5.2 `123/123 PASS`, `verify_manifest_sync.py`(`12` 모듈/`112` 경로/`126` 소스/`9` GDrive)·`verify_all_specs.py --check-readmes`(15종) `0 Errors, 0 Warnings`, `verify_spec_status.py` `9 Implemented, 6 Approved PASS`, 하네스 `82/82 PASS`, `verify_context_docs.py` `0 findings`.

---

## 2026-11-13 — AMM 채터링 방지 가드 설계 명세(방안 A) 및 ACTION/연료 임계값 정합화 (TASK-124)

- **결정 배경**: `TASK-204` 착수 전 상태 전이 경계 진동(채터링) 방지 규칙을 마인크래프트 `CC:Tweaked (Lua 5.2)` 및 현행 UAFS 코드베이스(`nav_engine.lua`, `facility_client.lua`, `fcp_config.json`, `VAS Base+2`) 제약에 맞게 정합화함 (`f2e7b10`).
- **반영 내역**:
  1. **`docs/superpowers/specs/2026-11-13-task-204-chattering-prevention-design.md` 신설**: `[즉시]` 36종 본 규격과 `[로드맵]`(`LOCAL_AVOID`/`REPLAN_GLB`·서브컨트랩션 동결) 격리, `step_20hz_tick` 정수 틱 vs 통신 워치독 `now_ms` 이원화, `amm_config.json` 고정 파라미터 직접 지정(`R_bound`/`a_max`/`tau_mech` 런타임 연산 배제), `TCA` 레드스톤 0~15 양자화 Limit Cycle 방지용 `N_settle`·이탈 불감대, `nav_engine` `validStreak >= 3`·`fcp_config.json` `wingedVtolVLowMps(8.0)`/`VHighMps(18.0)` 정합 및 중앙 전이 가드 **방안 A**(`chattering_guard.lua` + `condition_evaluator` `settleTicks`) 확정.
  2. **`docs/superpowers/specs/2026-11-12-task-204-action-primitive-design.md` 동기화**: `Base+2` `fuel(0.0~1.0)` 단독 및 `0.20`/`0.10` 임계값 역통일, `ACT_NRG_HIBERNATE`의 `ACT_PER_SENTRY_HOLD` 통합 및 자가 충전 로직 반영, 상호 링크 연결.
- **검증**: `verify_context_docs.py` `0 findings`, `TASK-124` 완료 마감 및 `TASK-401` 로드맵 이관(`TASK.md`, `GEMINI.md`) 동기화.

---

## 2026-11-13 — AMM v1.3.0·FCP v2.0.0·VAS v1.19.0 4계층 SE(3) 연동 구현 및 사양서 승격 (TASK-207, TASK-208, TASK-209)

- **결정 배경**: `TASK-206` Spec-First 개편(`AMM v1.3.0`, `FCP v2.0.0`, `VAS v1.19.0`)에 따라 외부 게이트웨이·항법·20Hz 궤적 생성(`AMM`), 순수 온보드 3채널 `SE(3)` 외루프(`FCP`), `QUATERNION_RATE` 내루프 단일화 및 선점·페일세이프(`VAS`)를 3단계 순차 구현(`docs/superpowers/plans/2026-11-12-task-207-208-209-sequential-plan.md`, `feat/task-207-208-209` 워크트리)하고 4계층 폐루프 E2E 및 전계층 회귀 검증을 거쳐 `FCP`와 `VAS` 사양서를 `Implemented`로 승격함 (`AMM v1.3.0`은 `TASK-402` WebUI 에디터 구현 완료 시까지 `Approved` 유지).
- **반영 내역**:
  1. **`TASK-207` — AMM v1.3.0 (`src/3_planning/amm/`, `52dc141`..`bd1539c`)**: 듀얼 무선 모뎀(`top`+`back`, 단일 모뎀 폴백), `channel_sentinel.lua`(`CH 50000`, `200ms` 프로브, 4계층 재바인딩, `MUT-03`), `nav_engine.lua`(`TASK-122` GPS+DR $\alpha=0.35$, `degradedAlpha=0.10`, `5,000ms` DR 선회, `posEpoch`, `CH 60001` 송신 전용 미개방, 위상 분산), `facility_client.lua`(Tower ATC/GAC/Runway/Docking/Landing Pad 2차 테일러 외삽 $\le 0.5\text{s}$, `300ms` 워치독, `15s x 10` 재시도), `trajectory_generator.lua`(11종 비행 모드, `LOITER` `ffAccel`, `POI_HOLD` $\le 30^\circ/\text{s}$, `-0.8` 도킹 이탈, 가상 ILS, 2단계 터치다운, `-2.0` 비상 강하), `[I-12]` `Base+4` 20Hz 송수신, `Base+3` 5Hz MFD 다운링크(`MFD_ACRO` 양보), `E_STOP` `authKey` 및 Coroutine A(20Hz)/B(5Hz) 분리를 구현 (`tests/3_planning/amm/` `110/110 PASS`).
  2. **`TASK-208` — FCP v2.0.0 (`src/2_guidance/fcp/`, `26d8365`..`319d659`)**: 단일 `top` 모뎀 3채널(`Base+4`, `Base+2`, `Base+1`) 격리 및 `MSG_CHANNEL_REBIND` 중계(`network_manager.lua`), 로컬 속도 적분 전파(`state_propagator.lua`: `dt <= 0.1s`, `posMergeMaxStepM = 2.0`, `500ms` `navStale`), 6-State 외루프 FSM(`flight_fsm.lua`: `PASSIVE_TRACKING` 2.0s 범프리스 램핑, `AMM_TIMEOUT_HOLD` `500ms -> 10s -> EMERGENCY_LAND`, `MUT-14`), 통합 `SE(3)` 외루프(`outer_loop_controller.lua`: $g=11.0\text{ m/s}^2$, 조건부 안티와인드업, 6대 기체 `QUATERNION_RATE` 투영, `STRICT_LEVEL`/`TILT_ASSISTED` + 스웨이 결손 폴백, 멀티로터 $25^\circ$, 유익 VTOL `[8, 18] m/s`, 고정익 BTT+TECS, `MUT-15`/`MUT-23`) 구현 및 레거시 14개 파일 제거·매니페스트 동기화 (`tests/2_guidance/fcp/` `45/45 PASS`).
  3. **`TASK-209` & 4계층 E2E (`src/1_control/vas/`, `tests/e2e/`, `3c82f7f`, `83ff1f6`, `244c940`)**: `QUATERNION_RATE`/`RATE_COMMAND` Zero-Fallback 단일화, 일반 비행 `compute_climb_wrench` 제거(`FAILSAFE_HOLD` 한정 격리), `E_STOP (ESTOP_CONFIRM_KEY) > MFD_ACRO > FCP`, `Base+3` `CORE_ACRO_TAKEOVER` 20Hz HUD 직결 및 침묵 가드, `[I-10]` `MSG_AERO_*`/`MSG_SURFACE_DISCOVER_*`, `config/system.json`(`trajectory: 4`, `asaActuation: 11`, `fcpCommandTimeoutMs: 1500`, `flapVfeLimit: 15.0`), `satAsa`/`satTca`/`fcpCmd` 정합화 및 4노드 폐루프 E2E(`test_e2e_4tier_closed_loop.lua` Scenario 8 `4/4 PASS` — `TASK-210` 1차 재바인딩/UUID 호환 포함) 구현 (`tests/1_control/vas/` `45/45 PASS`).
  4. **사양서 승격 및 컨텍스트 동기화**: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (`v2.0.0 Implemented`) 및 `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (`v1.19.0 Implemented`) 승격(`2026-11-13`), `tools/verify_spec_status.py` (`9 Implemented, 6 Approved`), `TASK.md`(완료 아카이브 10개 상한 유지: `TASK-012`·`114`·`009` 정리, `TASK-210` 1차 검증 기록), `GEMINI.md`(47줄 유지) 동기화 완료.
  5. **최종 전체 브랜치 리뷰 결함 보완 (`fix(flight)`)**: `amm/main.lua` 20Hz 틱 내 `nav_engine.update_timeout` 호출(`gpsTimedOut` 전파) 및 `MSG_CHANNEL_REBIND_ACK` 단독 라우팅·`channel_sentinel.lua` `READY` 엄격 검증, `fcp/outer_loop_controller.lua`·`fcp/main.lua` `arm`/`flightActive` 불리언 `false` 강제 변환 버그 수정, `mission_engine.lua`·`c2_arbiter.lua` `stop()`/`pause()`/폴백(`RTH`→`FAILSAFE_RTH`, `HOVER_HOLD`, `LOITER`) `[I-12]` `fallbackGoal` 연동(`MUT-05` `self.queue.state = "SUSPENDED"` 보존), `vas/flight_dynamics_core.lua` `targetOrientation` 레거시 폴백 제거(Zero-Fallback) 적용.
- **검증 (`feat/task-207-208-209` 워크트리)**: 단위 12타겟 `455/455 PASS`(`3_planning/amm` `112/112`, `2_guidance/fcp` `46/46`, `1_control/vas` `46/46`), E2E 8스위트 `12/12 PASS`, 돌연변이 `25/25 KILLED`(`100.0%`), 하네스 `82/82 PASS`, `verify_all_specs.py --check-readmes` `0 Errors, 0 Warnings`(15종), `verify_spec_status.py` `9 Implemented, 6 Approved PASS`, `validate_lua_syntax.py` `121/121 PASS`, `verify_manifest_sync.py` `0 Errors, 0 Warnings`, `verify_context_docs.py` `0 findings`.

---

## 2026-11-12 — AMM WebUI 미션 에디터 사양서 초안(v0.1.0 Draft) 수립 (TASK-202-5)

- **결정 배경**: `TASK-202`의 최종 잔여 항목인 `TASK-202-5`(호스트 PC 외부 비주얼 미션 에디터 사양서 생성, HTML 구현은 `TASK-402`로 분리)를 `AMM v1.3.0` / `ICD v1.28.0` / `Diagram v2.13.0` 기준과 현행 Lua 미션 코어(`mission_engine.lua`, `condition_evaluator.lua`, `hook_runner.lua`)에 정합화하여 명세화함 (`docs/superpowers/plans/2026-11-12-task-202-5-amm-webui-editor-spec.md`).
- **반영 내역**:
  1. **`docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.1.0 Draft` 신설·보강)**: `AMM v1.3.0` 파이프라인(`file_transfer` Coroutine B 5Hz $\to$ `mission_engine` Coroutine A 20Hz $\to$ `trajectory_generator` $\to$ `Base+4 [I-12]` & `Zone 3 Base+20..29`), Chrome `file://` Flexbox Column `.app-shell` 레이아웃(`<= 1150px` 3탭 반응형, `footer.bottom-validation-bar` 최대 `165px`, 네이티브 대화상자 금지 및 `#exportConfirmModal`/`#toastContainer` DOM ID 계약), Industrial Avionics 다크 조종석 토큰(영문 UI 라벨 + 한/영 툴팁), 미션 JSON `"version": "1.3.0"` 출력 및 `v1.0.0` `items[]`/`v1.1.0`/`v1.2.0`/`params.{x,z}` 변환·`_extra` 미지 필드 보존, 13종 액션 폼·12종 조건·4종 훅(16색 번들)·빈 조건 그룹 생략 규칙·Lua 동등성 + `defaults.*`/`ARM_*` `DEFERRED_ACTION_UNSUPPORTED` 프리플라이트 검증기, 2D `(X, Z)` 전술 캔버스 8계층(`Coord Stack Offset`, `Selected-Node Priority`, `CP`/`POI`/`PATROL_WP`/`PATROL_ALL` 4종 `hitTestCanvas` 드래그, `Alt` `0.1m` 미세 조정, `mousedown` 단일 Undo), JSON 입출력 및 `TASK-402` 인수 기준을 명세화함.
  2. **`TASK.md` 동기화**: `TASK-202-5` 완료 표기 및 `TASK-202` 완료 아카이브 이관(10개 상한 유지, `TASK-008` 정리), `TASK-402`에 `AMM_MISSION_EDITOR_SPECIFICATION.md` (`현재 v0.1.0 Draft`) 연결.
- **검증 (`feat/task-202-5` 워크트리)**: `verify_all_specs.py --check-readmes` `0 Errors, 0 Warnings`(15종), `verify_spec_status.py` `7 Implemented, 8 Approved PASS`, `verify_context_docs.py` `0 findings`, 하네스 `82/82 PASS`, 신설 `Draft` 사양서 구조·링크·Mermaid 감사 통과.

---

## 2026-11-12 — FCP 외루프 경량화 및 AMM 상위 계층 이관을 위한 15대 사양서 전면 개편 (TASK-206)

- **결정 배경**: 기존 `FCP (Node 04)`가 외부 RF 게이트웨이(`CH 50000~50004`, `CH 60001/60002`, `Base_sec+*`, `Base+5`), Tower ATC/GAC/시설물 핸드셰이크, GPS+DR 항법 융합, C2(`Base+0`) 중재와 온보드 외루프 제어를 겸임하여 계층 책임이 혼재되어 있었고, `FCP -> VAS` 인터페이스가 `ATTITUDE_ANGLE`/`targetClimbRate`/`targetThrottle` 등 다중 폴백 경로와 문서 결함을 포함하고 있었음. Spec-First 원칙에 따라 `src/` Lua 코드 수정 없이 14종 활성 사양서(`INSTALLER` v1.1.0 유지)를 일괄 개편함 (`docs/superpowers/plans/2026-11-11-fcp-amm-role-refactor-specs.md`).
- **반영 내역**:
  1. **마스터 ICD (`v1.28.0 Approved`) & 전체 구조도 (`v2.13.0 Approved`)**: `[I-5..I-9]` 외부 교신/C2/재바인딩을 `AMM (Node 03)`으로 이관, `Base+4` `[I-12]` `CH_TRAJECTORY_CMD`(`MSG_TRAJECTORY_SETPOINT` / `MSG_OUTER_LOOP_STATUS`, 구 `CH_NAV_SENSOR [DEPRECATED]`) 신설, `[I-2]` `Base+1`을 `QUATERNION_RATE`(`targetQuaternion`, `targetAngularRates`, `collectiveThrust`, 선택적 `flapTarget`/`translationBias {surge, sway}`) 단일 계약으로 정규화(`ATTITUDE_ANGLE` 등 `[DEPRECATED]`), `[I-10]` `Base+11`을 `MSG_AERO_CMD`/`MSG_AERO_STATUS`로 단일화하고 `MAX_CRAFT_LIMIT = 1000`, `BW=40`, `* 40`, `VAS-NODE-01-4402` 정정.
  2. **코어 3대 사양서 (`AMM v1.3.0 Approved`, `FCP v2.0.0 Approved`, `VAS v1.19.0 Approved`)**: `AMM`을 듀얼 무선 모뎀(`top`+`back`, 단일 모뎀 폴백)·`20Hz`/`5Hz` 듀얼 코루틴·`nav_engine`/`facility_client`/`channel_sentinel`/`trajectory_generator`·1계층 페일세이프·평시 5Hz `Base+3`(`MFD_ACRO` 시 양보) 전담으로 승격(`v1.2.0` 미션/에디터 규격 보존). `FCP`는 `Implemented -> Approved` 전이와 함께 단일 `top` 모뎀 3채널(`Base+4/+2/+1`) 온보드 `SE(3)` 외루프($g=11.0\text{ m/s}^2$, 6상태 FSM `PASSIVE_TRACKING`/`AMM_TIMEOUT_HOLD`)로 축소. `VAS`는 `Implemented -> Approved` 전이 및 정상 비행 승강 PI 제거(`FAILSAFE_HOLD` 한정), `E_STOP > MFD_ACRO > FCP`, `system.json`(`trajectory: 4`, `actuation: 10`, `asaActuation: 11`, `fcpCommandTimeoutMs: 1500`)·식별자(`SatAsa`/`satTca`/`fcpCmd`) 정비 완료.
  3. **제어·교정 및 지상 인프라 9종**: `ASA` (`v1.7.0 Approved`, `10011`/`bandwidth=40`/`oldBase+11`), `TCA` (`v1.11.1 Implemented`, `AMM->FCP->VAS` 재바인딩), `ALIGNMENT` (`v2.6.1 Implemented`, `VAS-NODE-01-4402`), `RUNWAY` (`v1.10.7 Approved`), `DOCKING_ARM` (`v1.11.2 Approved`), `GAC` (`v1.4.2 Implemented`), `LANDING_PAD` (`v2.4.3 Implemented`), `GCS` (`v1.0.2 Implemented`), `GPS` (`v2.3.1 Implemented`, `TASK-122` 규칙 보존 및 `10045`→`10005`) 정합화.
  4. **CI·로드맵·컨텍스트 동기화**: `tools/verify_spec_status.py`를 `7 Implemented, 8 Approved`로 갱신하고, `TASK.md`에 후속 구현 태스크(`TASK-207` AMM v1.3.0, `TASK-208` FCP v2.0.0, `TASK-209` VAS v1.19.0, `TASK-210` ASA/TCA/Alignment) 등록 및 `TASK-122`/`TASK-201` 아카이브 R5 인용·`GEMINI.md` 4개 섹션을 동기화함.
- **검증**: `verify_all_specs.py --check-readmes` `0 Errors, 0 Warnings`(15종), `verify_spec_status.py` `7 Implemented, 8 Approved PASS`, `verify_context_docs.py` `0 findings`, `verify_manifest_sync.py` `0 Errors, 0 Warnings`, 하네스 `82/82 PASS`, `validate_lua_syntax.py` `129/129 PASS`.

---

## 2026-11-12 — TASK-122 GPS ↔ 클라이언트 프로토콜 정합화 및 런타임 보완 완료

- **결정 배경**: 중앙 GPS 클러스터(`server.lua`, `session_scheduler.lua`, `node.lua`, `monitor_ui.lua`, `wizard_cli.lua`), GPS Client HAL(`client_core.lua`, `gps_client.lua`), 착륙패드(`src/0_infra/landing_pad/`) 및 FCP(`src/2_guidance/fcp/`) 간 패킷 스키마(`"FACILITY"`, `"FIX_OK"`/`"FIX_DEGRADED"`, `time` 헤더), 응답 채널(`replyChannel`/`50206`), 재시도·만료·TTL 처리가 서로 어긋나 있던 결함을 사양서 기준으로 단일화하고 실노드 폐루프 E2E로 검증함.
- **반영 내역**:
  1. **사양서 개정 및 배지·의사코드 동기화 (`TASK-122-1`, `1bf123a`, `83f8758` → `Implemented` 승격)**: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v2.2.2` → `v2.3.0 Approved` → `2026-11-12 Implemented`), 마스터 ICD(`v1.27.0`), 전체 구조도(`v2.12.1`), 착륙패드(`v2.4.2`), FCP(`v1.16.0`) 참조 배지 및 `isManaged` 재시도/`fix.position` 가드 정합화.
  2. **GPS 클러스터 서버·노드·UI·커미셔닝 (`TASK-122-2`, `195cf8f`, `53aa25f`)**: `EARLY_SOLVED` 원요청 `replyChannel` 반환, `FAIL_GEOMETRY` 150ms 단기 툼스톤(250ms 재시도 허용) 및 HWM 비갱신, 만료 세션 결정론적 정렬, 미등록 하트비트 게이트, `CH 60002` 클러스터 상태 응답, `payload.pos`, `monitor_ui.lua` `%-10s`, `wizard_cli.writeJsonAtomic` 적용.
  3. **GPS Client HAL (`TASK-122-3`, `bece209`, `aa7a52c`)**: `client_core.lua` `pendingResponses` 5000ms TTL 정리, `gps_client.lua` `isManaged` 50% 타임아웃 재시도 동등성, 채널 정리, `CH 60002` `queryStatus` API 및 비진행 epoch 루프 방어 구현.
  4. **착륙패드 & FCP 클라이언트 (`TASK-122-4` `bf1353f`·`133bc49`, `TASK-122-5` `b6db171`·`ead5a56`, 최종 리뷰 수정 `43874af`)**: 착륙패드 Zero-Fallback `config_store.normalize_config`·이중 주기(`1Hz`/`5Hz`/`STATIC`)·`Base_sec+5`(`50206`)·`"FACILITY"`/`"FIX_OK"`/`"FIX_DEGRADED"`·`is_finite_number` 좌표/고도 가드 정합화; FCP `time` 엔벨로프 표준화·`targetClient`/`clientSeq`(`lastGpsSeqSeen` 스파이크 재전송 차단)·빈 `domainId` 정규화/fail-closed 및 `now_ms` 방어·경과시간 `delta_t`·`altitudeY` 동기화.
  5. **실노드 폐루프 E2E (`TASK-122-6`, `tests/e2e/test_e2e_gps_triangulation.lua`)**: 가상 버스 상에서 4노드 `EARLY_SOLVED` + 스푸핑 차단 + `altitudeY` 동기화, 3노드 공선 `FAIL_GEOMETRY`(`bus.time = 2.080` >= `2070ms` 만료) + 250ms 재시도, `CH 60002` `SUMMARY` 상태 조회, 착륙패드 `FACILITY`(`50206`) + 재전송 차단을 폐루프로 검증. (참고: `virtual_bus:find_packets()`는 `bus:step()` 배달 이후 `packet_log`에 적재되며, `--headless` CraftOS-PC 4KB stdout 파이프 교착 방지를 위해 4노드 생성 전 `sdk.patch(_G, "print", function() end)` 적용.)
- **검증 (`feat/task-122` 및 `main` 병합 후)**: 단위 12타겟 `403/403 PASS`(`feat/task-122` 단독 `392/392`, `gps` `27/27`, `landing_pad` `44/44`, `fcp` `50/50`, `amm` `71/71`, `ui_violation_count=0`, `event_swallow_count=0`, `static_violations=[]`), E2E 7시나리오 `8/8 PASS`, 돌연변이 `25/25 KILLED`(`100.0%`), 하네스 `82/82 PASS`, Lua `129/129 PASS`, `verify_manifest_sync.py`·`verify_all_specs.py --check-readmes` `0 Errors, 0 Warnings`, `verify_spec_status.py` `9 Implemented, 6 Approved PASS`, `verify_context_docs.py` `0 findings`.

---

## 2026-11-12 — AMM 51x19 TUI 뷰포트·다중 경로 리졸버·프리플라이트 스키마 검증·파일 드롭/CLI 확장 구현 (TASK-202-4)

- **결정 배경**: `AMM_PROGRAM_SPECIFICATION.md` (`v1.2.0 Approved`) 기반 외부 파일 즉시 구동 파이프라인 및 조종석 `51x19` MFD UI 확장을 구현함 (단, `tools/amm_mission_editor.html` 제작·E2E 확장·사양서 `Implemented` 승격은 `TASK-202-5` 범위로 유지).
- **반영 내역**:
  1. **다중 경로 리졸버, 프리플라이트 스키마 검증 및 C2 ACK 매핑 (`mission_engine.lua`, `c2_arbiter.lua`, `fa91084`)**: `resolve_path`(5단계 탐색·디렉토리 충돌 및 `..` 탈출 차단), `list_mission_files`, `validate_mission_table`(13종 액션·12종 조건·4종 훅·`x`/`z` 단축 좌표 정규화·`CP#<idx>` 사유 반환), 비변이 `preflight_file` 및 `load` 연동을 구현함. `c2_arbiter.lua`는 `forceRestart` 중단 이전에 `preflight_file`을 선행 검증하여 잘못된 원격 `RUN` 지령이 비행 중 임무를 중단하지 않도록 보호하고 `SCHEMA_INVALID` ACK를 매핑함 (`MUT-04`/`MUT-05` 보존).
  2. **51x19 TUI 6행 스크롤 뷰포트 및 5행 조건 상세 패널 (`ui_renderer.lua`, `064a706`, `dfb3029`)**: `compute_viewport` 중앙 스크롤, `O`/`*`/`!` 마커, 5행 상세(`STATE`, `ACT`, `COND`, `ALT/V`, `DIST`), 레거시 `waypoint_queue` 다형성 지원, 정확히 25열 우측 패딩(`draw_right_pane`, `#text == #fg == #bg == 51`) 및 재사용 버퍼 잔상 제거(`render_mission_details` 분할 포함 전 함수 $\le 50$줄)를 구현함.
  3. **CLI 확장·셸 부팅 인자·`file_transfer` 핫인젝션 (`input_handler.lua`, `main.lua`, `d3b3b8b`)**: `VALID_COMMANDS` 16종·`mission` 서브커맨드 파싱·`handle_paste`·`parse_boot_args`(`main.lua <spec> [loop]`)·`handle_file_transfer`(파일명 정규화·검증 실패 시 비덮어쓰기·`IDLE` 적재/`autoRunDroppedFile` vs `EN_ROUTE`/`SUSPENDED` 디스크 저장)·`PILOT_PRIMARY` 탈환(`§8.2`) 및 빈 엔진 시 레거시 큐 마이그레이션 실행을 구현함 (`amm_config.json` 변경 없음).
- **검증 (워크트리 `.worktrees/task-202-4`, 브랜치 `feat/task-202-4`)**: 단위 12타겟 `372/372 PASS`(`3_planning/amm` `71/71 PASS`, `test_external_loader.lua` 신설), E2E 7시나리오 `8/8 PASS`, 돌연변이 `25/25 KILLED`(`100.0%`), 하네스 `82/82 PASS`, `verify_manifest_sync.py` `0 Errors, 0 Warnings`, `verify_all_specs.py --check-readmes` `0 Errors, 0 Warnings`, `verify_spec_status.py` `9 Implemented, 6 Approved PASS`, `validate_lua_syntax.py` `129/129 PASS`, `verify_context_docs.py` `0 findings`.

---

## 2026-11-11 — AMM v1.2.0 호스트 PC 외부 웹 GUI 미션 에디터 및 외부 파일 즉시 구동 사양 개정 (TASK-202-1)

- **결정 배경**: CC:Tweaked 인게임 `51x19` 터미널의 협소한 해상도 제약을 보완하여 13종 액션·12종 복합 조건·4종 훅을 직관적으로 설계할 수 있는 외부 에디터와, 저작한 `.json` 파일을 인게임 컴퓨터에 바로 집어넣어 구동하는 파이프라인을 명세화함.
- **반영 내역**:
  1. **`docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v1.1.0` → `v1.2.0 Approved`)**: §6.6 외부 파일 다중 경로 리졸버(`resolve_path`: 원문 경로 → `.json` → `missions/` → `/disk/` → `/disk/missions/`), 프리플라이트 스키마 검증기(`validate_mission_table`, `SCHEMA_INVALID` 반환), 3대 즉시 구동 채널(CLI `run`/`load`/`files`, 셸 부팅 인자 `main.lua <spec> [loop]`, CC 창 드래그 앤 드롭 `file_transfer` 수신 및 `IDLE` 적재/`autoRunDroppedFile` 출격/비행 중 안전 저장) 및 §9 호스트 PC 무설치 단일 파일 웹 GUI 에디터(`tools/amm_mission_editor.html` — 13종 액션 카드, 조건/훅 빌더, 2D $(X,Z)$ 경로 캔버스, 실시간 스키마 검증, JSON Import/Export) 규격 신설.
  2. **`docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.26.0` → `v1.27.0 Approved`) & `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.12.0` → `v2.12.1 Approved`)**: `MSG_MISSION_CMD.payload.missionName` 외부 경로 지원 및 `MSG_MISSION_ACK.payload.status` `SCHEMA_INVALID` 코드 추가, 참조 버전 배지 동기화.
  3. **`TASK.md` & `GEMINI.md`**: `TASK-202-1` 개정 완료 반영 및 `TASK-202-4~5` 구현 백로그 상세화.
- **검증**: `python tools/verify_all_specs.py --check-readmes` `0 Errors, 0 Warnings`, `python tools/verify_spec_status.py` `9 Implemented, 6 Approved PASS`, `python tools/verify_context_docs.py` `0 findings`, `python -m unittest discover -s tests/harness -p "test_*.py"` `82/82 PASS`.

---

## 2026-11-11 — AMM 미션 엔진 FSM·C2 중재·헤드리스 모드 및 5Hz 틱 연동 (TASK-202-3)

- **결정 배경**: `AMM_PROGRAM_SPECIFICATION.md` (`v1.1.0 Approved`) 기반 통합 미션 시퀀서 구축의 2단계 구현으로, 다형성 미션 파일 로더(`load`/`save`/`load_table`) 및 스텝 자동 전이 FSM(`mission_engine.lua`), `c2_arbiter.lua` `Base+0` `MSG_MISSION_CMD`/`MSG_MISSION_ACK` 중재, `main.lua` 헤드리스 모드(`config.headless`)·5Hz 타이머 틱·Zone 3(`Base+20~29`) 이벤트 라우팅을 구현함.
- **반영 내역**:
  1. **다형성 미션 로더 및 시퀀서 FSM (`mission_engine.lua`, `de91f47`, `e87a192`)**: `load_table`/`load`/`save` 구현(`items` 구형 포맷 자동 승격), 9종 FCP 디스패처(`TAKEOFF_LAUNCHPAD`, `FLY_OVER`, `FLY_TO`, `ORBIT`, `PATROL`, `POI_HOLD`, `LAND_LAUNCHPAD`, `PAYLOAD_ACTION`, `REDSTONE_ACTION`), `enter_checkpoint`·`advance`·`evaluate_active`·`step_telemetry`·`tick` 5단계 FSM 라이프사이클 및 4종 폴백 핸들러(`SKIP_NEXT`, `RTH`, `HOVER_HOLD`, `LOITER`), 일시정지 FSM 표준 전이(`SUSPENDED`) 및 런타임 예약 액션 거부(`DEFERRED_ACTION_UNSUPPORTED`) 적용.
  2. **C2 중재 및 원격 제어 (`c2_arbiter.lua`, `8442bbc`, `6113559`)**: `Base+0` `MSG_MISSION_CMD` 6종 액션(`RUN` `SINGLE`/`REPEAT`/`forceRestart`/`BUSY_REJECTED`, `STOP`, `PAUSE`, `RESUME`, `NEXT`, `ABORT`) 처리 및 `MSG_MISSION_ACK` 응답, `GCS_OVERRIDE` 권한 획득 시 큐/엔진 동시 일시정지, 조종사 CLI 액션(`PAUSE`/`RESUME`) 시 엔진 FSM 및 권한(`PILOT_PRIMARY`) 동기화.
  3. **헤드리스 모드·5Hz 엔진 틱·Zone 3 라우팅 (`main.lua`, `test_main_loop.lua`)**: `load_config` 기본값 `headless = false` 추가, 5Hz 타이머(`0.2s`) 시 `app.engine:tick(now_ms)` 구동 및 `config.headless == true` 시 TUI 렌더링/버퍼 플러시 생략, `modem_message` 시 `Base+3`(MFD), `Base+0`(GCS/C2), `Base+20~29`(Zone 3 `on_payload_ack`) 분기 라우팅, `execute_cli_command` 5종 명령어(`save`/`load`/`clear`/`pause`/`resume`) 엔진 동기화 및 `cfg.autoStartMission` 자동 시작 지원.
- **검증 (워크트리 `.worktrees/task-202-2-amm-core`)**: 단위 12타겟 `361/361 PASS`(`3_planning/amm` `60/60 PASS`), E2E 7시나리오 `8/8 PASS`, 돌연변이 `25/25 KILLED`(`100.0%`), 하네스 `82/82 PASS`, `verify_manifest_sync.py` `0 Errors, 0 Warnings`(`116` 매니페스트 경로/`132` 소스), `verify_all_specs.py --check-readmes` `0 Errors, 0 Warnings`, `verify_spec_status.py` `9 Implemented, 6 Approved PASS`, `validate_lua_syntax.py` `129/129 PASS`, `verify_context_docs.py` `0 findings`.

---

## 2026-11-11 — AMM 3분할 미션 코어 기반·조건 평가기·0-Tick 훅·Zone 3 버스 구현 (TASK-202-2)

- **결정 배경**: `AMM_PROGRAM_SPECIFICATION.md` (`v1.1.0 Approved`) 기반 통합 미션 시퀀서 구축의 1단계 코드 구현으로, 후속 `TASK-202-3`(JSON 로더 및 FSM)과 분리해 13종 체크포인트 스키마 검증·12종 조건 평가기·0-tick 비차단 훅/디바이스 드라이버·Zone 3(`Base+20~29`) 동적 버스를 순환 참조(`require("mission_engine")` 금지) 없이 독립 모듈화함.
- **반영 내역**:
  1. **13종 체크포인트 스키마 및 Zone 3 버스 (`mission_engine.lua`, `network_manager.lua`, `3a2290e`)**: `ACTIVE_ACTIONS` 9종 파라미터 검증(`FLY_TO` 5m 기본 정밀도 유지, `POI_HOLD` `headingMode="POI"`, `ORBIT` 30m/CW 기본값), `DEFERRED_ACTIONS` 4종(`TAKEOFF_RUNWAY`, `LAND_RUNWAY`, `DOCK_ARM`, `UNDOCK_ARM`) 즉시 거부(`"DEFERRED_ACTION_UNSUPPORTED"`), `defaults` 상속 및 `validate_mission` 구축. `network_manager.lua`는 `bind_modem`(`+0`/`+3`) 유지 상태에서 Zone 3(`Base+20~29`) 정수 범위 검증(`INVALID_ZONE3_CHANNEL`)·동적 개폐(`openPayloadChannels`)·`MSG_PAYLOAD_REQ`·`MSG_MISSION_ACK` 추가(`close_payload_channel` `pcall` 반환값 검사 포함).
  2. **12종 조건 평가기 (`condition_evaluator.lua`, `e089579`)**: 12종 조건(`PROXIMITY_2D/3D`, `ALTITUDE_REACHED`, `DURATION_SEC`, `TIMEOUT_SEC`, `FUEL_LEVEL_BELOW`, `FACILITY_TOUCHDOWN` 사전 접근 가드 `should_arm_touchdown`, `PAYLOAD_RESP_MATCH` `checkpointId` 격리, `REDSTONE_INPUT_HIGH` 번들/아날로그/디지털 병행, `CROSS_TRACK_ERROR`, 예약 `ARM_DOCKED/RELEASED`), `ALL`/`ANY` 조합기(빈 배열 허위 참 방지, `abortWhen` 우선 평가), 9종 기본 `completeWhen` 자동 보강 및 `format_progress`(`<= 25`자) 구현.
  3. **0-Tick 훅 러너 및 통합 검증 (`hook_runner.lua`, `433bcec`, `test_mission_core_integration.lua`)**: `sleep()`/`pullEvent` 없이 `REDSTONE_SET`·`bit32` 데드라인 큐 `REDSTONE_PULSE`(중첩 연장 및 번들 타 색상 보존, 아날로그 `setOutput` 덮어쓰기 방지)·단발 `ZONE3_PAYLOAD_CMD`·`NOTIFY_OPERATOR` 및 `REDSTONE_ACTION`/`PAYLOAD_ACTION`(`cleanup()` 고아 출력·채널 일괄 회수)을 구현하고 3개 신규 `.lua` 파일을 `manifest.lua`에 등록함 (`AMM_PROGRAM_SPECIFICATION.md`는 `TASK-202-5`까지 `v1.1.0 Approved` 유지).
- **검증 (워크트리 `.worktrees/task-202-2-amm-core`)**: 단위 12타겟 `349/349 PASS`(`3_planning/amm` `48/48`, `0_development/installer` `39/39`), E2E 7시나리오 `8/8 PASS`, 돌연변이 `25/25 KILLED`(`100.0%`, `MUT-04`/`MUT-05` 포함), 하네스 `82/82 PASS`, `verify_manifest_sync.py` `0 Errors, 0 Warnings`(`116` 매니페스트 경로/`132` 소스), `verify_all_specs.py --check-readmes` `0 Errors, 0 Warnings`, `verify_spec_status.py` `9 Implemented, 6 Approved PASS`, `validate_lua_syntax.py` `129/129 PASS`, `verify_context_docs.py` `0 findings`.

---

## 2026-11-11 — FCP 외루프 유도 프리미티브(LOITER/POI_HOLD) 확장 및 범프리스 C2 연동 (TASK-201)

- **결정 배경**: `AMM` v1.1.0(`TASK-202-1`) 통합 미션 시퀀서의 `ORBIT`→`LOITER` 및 `POI_HOLD` 전술 기동 지령을 수행하기 위해 FCP(`src/2_guidance/fcp/`) 외루프 유도 프리미티브, 3종 기수 지향 모드, `Base+0` 파라미터 정규화 및 2.0s 범프리스 전환 인터록을 활성 VTOL 2종(`VECTORED_VTOL`, `ADVANCED_VTOL`)에 구현함 (`DEFERRED_AIRFRAMES` 4종 차단 및 `flapTarget == 0.0` 유지).
- **반영 내역**:
  1. **사양서 개정 및 배지 동기화 (`d3c5fef` → `Implemented` 승격)**: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (`v1.15.0 Implemented` → `v1.16.0 Approved` → `v1.16.0 Implemented`), 마스터 ICD(`v1.26.0`), 전체 구조도(`v2.12.0`), AMM 사양서(`v1.1.0`) FCP 참조 배지를 동기화함.
  2. **외루프 `LOITER`/`POI_HOLD` 제어 법칙 및 3종 요 제어 (`ddaf428`)**: `flight_fsm.lua` 16상태 확장(`POI_HOLD` 신설 및 `CRUISE`↔`LOITER`↔`POI_HOLD`↔`APPROACH_LAND` 전이, `MUT-14` 보존), `vectored_vtol_driver.lua`·`advanced_vtol_driver.lua`의 `resolve_horizontal_error` (반경 $R \ge 5.0\text{ m}$ 반경 오차 + CW/CCW 접선 벡터, 중심 $d_c \le 0.1\text{ m}$ 북향 `(0.0, -1.0)` 특이점 회피) 및 3종 `compute_heading` (`AUTO`/`FACE_PATH`, `FIXED`, `POI`/`TARGET_LOCK`/`ORBIT_POINT`, $<0.5\text{ m}$ 요 고정, $30.0^\circ/\text{s}$ 슬루율, `LOITER`/`POI_HOLD` 중 `TILT_ASSISTED` 억제 `STRICT_LEVEL` $0.0^\circ$), `fcp_config.json` 기본값(`loiterRadialKp`, `orbitRadiusM`, `orbitSpeedMps`)을 구현함.
  3. **C2 정규화, 2.0s 범프리스 램핑 및 런타임 배선 (`f218830`, `ecff4f4`, `fb08520`)**: `operator_handler.lua` `normalize_params`(`loiterRadius >= 5.0`, `loiterDirection` 기본 `"CW"`, `FIXED` $0\sim 360^\circ$ 래핑, `POI_HOLD` 기본 `"POI"`, `PILOT_PRIMARY` 비강제 GCS 거부 `PILOT_OVERRIDE_ACTIVE`), `guidance_controller.lua` `rampStartMs = -10000` 초기화 및 `trigger_bumpless_transition`(`prev_surge`/`prev_sway`/`prev_heading` 보존), `fcp_runtime.lua` C2→`mission_target`/`flight_fsm` 배선 및 `navigation.distanceToWp` 산출, 리뷰 후속 보완(`fb08520`: `NaN`/`Inf` 차단 `finite_num`, `FAILSAFE_HOLD` 이탈 시 `trigger_bumpless_transition` 통합, 지상 대기 C2 중심점 동결·램프 발동 방지, `POI_HOLD` 고도 자동 앵커링)을 적용하고 E2E 시나리오 2 Step 9(`test_e2e_waypoint_guidance.lua`)를 추가함.
- **검증**: 단위 12타겟 `330/330 PASS`(`2_guidance/fcp` `45/45`, 최대 `46,400 <= 50,000` insns), E2E 7시나리오 `8/8 PASS`, 돌연변이 `25/25 KILLED`(`100.0%`), 하네스 `82/82 PASS`, `verify_manifest_sync.py`·`verify_all_specs.py --check-readmes` `0 Errors, 0 Warnings`, `verify_spec_status.py` `9 Implemented, 6 Approved PASS`, `validate_lua_syntax.py` `126/126 PASS`, `verify_context_docs.py` `0 findings`.

---

## 2026-11-11 — AMM v1.1.0 통합 미션 시퀀서 사양서 및 마스터 ICD·구조도 개정 (TASK-202-1)

- **결정 배경**: 기존 Layer 3(AMM 단순 웨이포인트 큐)와 Layer 4(AMP 복합 미션 플래너 초안)로 이원화되어 있던 미션 시퀀서를 Node 03 단일 컴퓨터 내 3분할 코어(`mission_engine.lua`, `condition_evaluator.lua`, `hook_runner.lua`)로 통합하고, 별도 RF 채널 추가 없이 `Base+0` 원격 미션 제어와 Zone 3(`Base+20~29`) 동적 탑재체 버스를 규격화함.
- **반영 내역**:
  1. **`docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v1.0.1 Implemented` → `v1.1.0 Approved`)**: 13종 체크포인트 스키마(활성 9종 + 예약 4종 `DEFERRED_ACTION_UNSUPPORTED`), 12종 `completeWhen`/`abortWhen` 복합 조건 평가기, 0-tick 비차단 라이프사이클 훅(`onEnter`/`onExit`/`onAbort`), Zone 3(`Base+20~29`) 동적 탑재체 교신(`MSG_PAYLOAD_REQ`/`ACK`), `Base+0` 원격 미션 제어(`MSG_MISSION_CMD`/`ACK`), 무인기 헤드리스(`config.headless`) 겸용 토폴로지, `51x19` TUI 6행 스크롤 뷰포트 + 5행 조건 진행률 및 `run`/`stop`/`next`/`mission` CLI 규격 수립 (`waypoint_queue.lua` 하위 호환 유지).
  2. **`docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.25.0` → `v1.26.0 Approved`)**: Interface I-6(`Base+0`)에 `MSG_MISSION_CMD`/`MSG_MISSION_ACK` 및 `MSG_OPERATOR_CMD` 확장 파라미터(`POI_HOLD`, `loiterRadius`, `loiterDirection`, `poiTarget`, `headingMode`, `fixedHeading`) 반영, Interface I-11(`Base+20~29` Zone 3 탑재체 버스) 신설.
  3. **`docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.11.0` → `v2.12.0 Approved`) & `tools/verify_spec_status.py`**: 패킷 교환 매트릭스(I-6, I-11) 및 Node 03 채널 매핑 갱신, 사양서 상태 분포(`9 Implemented, 6 Approved`) 및 `GEMINI.md`·`TASK.md` 동기화.
- **검증**: `python tools/verify_all_specs.py --check-readmes` `0 Errors, 0 Warnings`, `python tools/verify_spec_status.py` `9 Implemented, 6 Approved` PASS, `python tools/verify_context_docs.py` `0 findings`.

---

## 2026-11-11 — 컨텍스트 문서 드리프트 가드 및 git.exe 차단 확장 (TASK-121)

- **결정 배경**: 앞선 Mode B 감사에서 드러난 테스트 수치 3중 수기 관리(R1), 과장 금지어 검사기 부재(R2), Mode A 조건 제한에 의한 Tier 3 메모리 누락(R8), 사양서 버전·마커 어긋남(R3~R7)이 작업 완료 시 재발하지 않도록, 에이전트가 턴 종료 전 스스로 검출·수정하게 만드는 자동 가드를 구축함.
- **반영 내역**:
  1. **정적 검사기 (`tools/verify_context_docs.py`, `edea694`·`a2cf19a`)**: 단일 문서(R1·R2·R3·R6·R7) 및 교차 참조(R4·R5·R8) 8개 규칙과 `--json` CLI 구현, `tests/harness/test_context_docs.py` 18건(실저장소 0건 회귀 포함) 및 `test_tools_integrity.py` 편입.
  2. **SessionStart/Stop 훅 (`.agent/hooks/context_doc_guard.py`, `97b2654`)**: 작업 트리 dirty 또는 세션 시작 `HEAD` 대비 커밋 이동 시에만 실행, 동일 위반 서명(SHA-1)당 `continue` 최대 2회 제한 및 내부 오류/비JSON 입력 시 fail-open(`allow`) 처리. 단위 테스트 10건(`test_context_doc_guard_hook.py`) 및 `stop` 실측 실행 시간 `204.15 ms` 확인.
  3. **훅 등록 및 `git.exe` 차단 보완 (`.agent/hooks.json`, `b12782a`·`f38356a`)**: `context-doc-guard`와 기존 `block_dangerous_git.py`(`PreToolUse`)를 함께 등록. 새 대화 스모크 1번(`a3ee0ef6`)에서 `Stop` 훅의 `[R1]` 차단 및 에이전트 자가 원복 확인; 2번 스모크(`4d9832e0`)에서 Windows 절대 경로 `& "C:\Program Files\Git\cmd\git.exe" push` 미매치 우회를 확인하여 `block_dangerous_git.py` 정규식에 `\b[Gg][Ii][Tt](?:\.[Ee][Xx][Ee])?["']?\s+` 적용 및 단위 테스트 4건(`test_git_guardrails_hook.py`) 추가.
  4. **워크플로우 연동**: `verification-before-completion` Step 5(`CONTEXT DOCS`), `md-management` Mode A(모든 `TASK-ID` 완료 시 메모리 기록), `skill-workflows.md`, `GEMINI.md`(47줄 유지), `TASK.md` 동기화.
- **검증**: `python tools/verify_context_docs.py` `0 findings`, `python -m unittest discover -s tests/harness -p "test_*.py"` `82/82 PASS`, `verify_all_specs.py` `0 Errors, 0 Warnings`, `verify_manifest_sync.py` `0 Errors, 0 Warnings`.

---

## 2026-11-10 — 통합 인스톨러(installer.lua) 도메인별 2계층 폴더 TUI 개편 (TASK-116)

- **결정 배경**: `manifest.lua` 등록 모듈이 12개에 도달하면서 `tui_view.lua`의 `51x19` 터미널 12행 뷰포트(`y = 4..15`)가 포화되어 후속 모듈(`runway`, `asa`, `docking_arm` 등) 추가 시 화면 이탈 위험이 발생했고, 통합 인스톨러 공식 규격서도 부재한 상태였음.
- **반영 내역**:
  1. `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` (`30023fb` Approved → v1.1.0 Implemented): 3종 실행 컨텍스트, 이중 원격 소스, 6대 도메인 계층 카테고리, `51x19` 2계층 상태 머신·12행 스크롤러·잔상 초기화 규칙을 정식 규격화하고 `verify_all_specs.py`·`verify_spec_status.py`·`README.md`에 편입함(15대 사양서).
  2. `src/0_development/installer/modules/manifest.lua`·`installer.lua` (`f23a27d`): `VERSION = "1.1.0"`으로 통일하고 `CATEGORY_ORDER`·`CATEGORIES`·`getCategory`·`listModulesByCategory`·`listCategories(includeEmpty)`(기본값 빈 `mission` 폴더 제외) 구현 및 루트/소스 `installer.lua` 바이트 패리티 유지.
  3. `src/0_development/installer/modules/tui_view.lua`·`installer_app.lua`·`tests/0_development/installer/` (`2e1b53a` + 리뷰 보완): `computeViewport` 12행 스크롤 윈도우 및 `[first-last of total]` 구분선 지표, `renderCategoryMenu`(`[DIR]`·`[inst/total inst]`), `renderMenu` 폴더 헤더/`[Bksp/B] Folders`/잔상·상태바(`y = h`) 공백 초기화, `updateSelection` 증분 커서 갱신 및 정상 팔레트 복원, 2계층 상태 머신(`CATEGORY_MENU` $\leftrightarrow$ `MODULE_MENU` $\leftrightarrow$ `CONFIRM_*`) 및 `[Q]` 종료 시 색상·커서(`1, h`) 복원 구현, 규격서 §5.1 `defaultConfigs` 마이그레이션 범위 정합화.
- **검증 (2026-11-10 실행)**: 단위 318/318 PASS(12개 타겟, `installer` 39/39, 최대 관측 인스트럭션 `46,800 <= 50,000`), E2E 8/8 PASS(7개 시나리오), 돌연변이 25/25 KILLED(100.0%, 기준 90.0%), 하네스 50/50 PASS, `verify_manifest_sync.py`·`verify_all_specs.py --check-readmes` `0 Errors, 0 Warnings`, `verify_spec_status.py` 15대 사양서(10 Implemented, 5 Approved) PASS, Lua 126/126 PASS.

---

## 2026-11-10 — ADVANCED_VTOL & GAC 전용 패드/비상 징발 E2E 및 돌연변이 확장 (TASK-118)

- **결정 배경**: `TASK-111` 구축 이후 구현된 `TASK-115`(`ADVANCED_VTOL` 2D 짐벌 벡터 추진)와 `TASK-114`(`GAC` 전용 패드 격리·비상 징발)에 대해 단위 테스트를 넘어선 다중 노드 패킷 시퀀스 E2E 시뮬레이션과 결정론적 돌연변이 타겟 확장이 필요했음.
- **반영 내역**:
  1. `tca_daemon.lua`·`watchdog_sentinel.lua`·`test_tca_vector_thruster.lua`·`tests/e2e/test_e2e_advanced_vtol_flight.lua`(`f4d0c1f`): `MSG_CALIB_PULSE`의 `gimbalX`/`gimbalY` 다형성 전달을 수정하고, Alignment 2D 짐벌 펄스 캘리브레이션·$B^\dagger$ 프로파일 동기화·FCP/VAS/TCA 6-DoF 폐루프 유도 비행(`flapTarget = 0.0`, `Base+11` 비송출)·포화 안티와인드업·`E_STOP` 노즐 `(0, 0)` 복귀를 검증하는 시나리오 7을 신설함.
  2. `tests/e2e/test_e2e_facility_landing.lua`(`704822f`): 전용 착륙패드(`dedicatedCraftIds`) 비콘 `freeLandingPads` 제외·공용 우선 배정·비인가 `FACILITY_DEDICATED` 거절·`isEmergency = true` 비상 징발 시퀀스를 시나리오 6에 추가함.
  3. `tools/run_mutation_tests.py`·`harness/simulation/node_sandbox.lua`·`tests/harness/test_simulation_core.py`(`b9211fa`): `MUT-21`~`MUT-25` 5종(11도메인 25타겟)을 확장하고, 전체 E2E 동시 실행 시 `fcp:require("main")`·`gcs:require("main")` 0인자 호출로 인한 CraftOS-PC `--headless` `term.clear()` 행을 유발하던 `node_sandbox.lua` `require` 시그니처를 Lua 5.2 표준 `(norm_name, found_path)` 2인자 전달로 수정(`test_node_sandbox_require_passes_modname_and_filepath` 회귀 추가).
- **검증 (2026-11-10 실행)**: 단위 309/309 PASS(12개 타겟, TCA 32/32), E2E 7개 시나리오 8/8 PASS, 돌연변이 25/25 KILLED(100.0%, 기준 90.0%), 하네스 50/50 PASS, `verify_manifest_sync.py`·`verify_all_specs.py` 0 Errors/0 Warnings(9 Implemented, 5 Approved), Lua 126 파일 문법 PASS.

---

## 2026-11-10 — 인스톨러 매니페스트·GDrive·소스 트리 3자 정합성 검증기 구축 (TASK-012)

- **결정 배경**: `TASK-009`(GDrive 매핑) 및 향후 `TASK-116`(인스톨러 카테고리 개편)과 연계하여 `src/`에 신규 Lua/JSON 파일이 추가·개명될 때 `manifest.lua` 또는 `config/gdrive_mapping.json` 갱신 누락으로 인한 배포 불일치를 사전에 차단할 정적 가드가 필요함.
- **반영 내역**:
  1. `tools/verify_manifest_sync.py`: 외부 Lua 런타임 없이 `manifest.lua`·`installer.lua`·`src/`·`config/gdrive_mapping.json`을 구조 파싱하여 바이트/부트스트랩 패리티, `MODULE_ORDER`↔`MODULES` 대칭성, 모듈/GDrive 카테고리 정합성, 공용 센서(`/lib/avionics_sensors.lua`) 번들링, 양방향 누락·고아(`ORPHAN_SRC_FILE`/`ORPHAN_SRC_CONFIG_FILE`/`MISSING_DISK_FILE`/`ORPHAN_GDRIVE_MAPPING`), 연기 서브시스템(`src/1_control/asa`) 면제 만료(`STALE_DEFERRED_EXEMPTION`)를 전수 검사함.
  2. `tests/harness/test_manifest_sync_verifier.py`·`tests/harness/test_tools_integrity.py`·`README.md`·`GEMINI.md`·`TASK.md`: 결함 주입 테스트 7건 및 통합 실행 테스트 1건을 하네스 회귀 슈트에 편입하고 표준 One-Liner 검증 파이프라인을 동기화함.
- **검증 (2026-11-10 실행)**: `verify_manifest_sync.py` `0 Errors, 0 Warnings`(12 모듈·113 매니페스트 경로·129 소스 파일·9 GDrive 엔트리), 하네스 49/49 PASS, 사양서 9 Implemented / 5 Approved(0 Errors/0 Warnings), Lua 126 파일 문법 PASS.

---

## 2026-11-10 — GAC 전용 시설물(Dedicated Facility) 런타임 및 TUI 확장 (TASK-114)

- **결정 배경**: `GAC_PROGRAM_SPECIFICATION_AND_ICD.md` v1.4.1(전속 착륙패드/도킹암 보호, 비콘 공용 패드 분리, `FACILITY_DEDICATED` 거절, TUI `[DED: ...]`/`PUBLIC` 관리)에 맞춰 `src/0_infra/gac/` 런타임을 완결하고 사양서를 `Implemented`로 승격함.
- **반영 내역**:
  1. `config_loader.lua`·`facility_inventory.lua`: `dedicatedCraftIds`/`dedicatedAirframeTypes` 스키마 검증(`validate_dedicated_field`), 전용 시설 판별(`is_facility_dedicated`/`is_dedicated`/`update_dedicated`), `get_summary()` 공용 가용 패드·활주로(`freeLandingPads`/`freeRunways`) 분리 (`37c45a4`).
  2. `allocation_engine.lua`·`gac_fsm.lua`: 비인가 `preferredFacilityId` 및 공용 패드 부재 시 `FACILITY_DEDICATED` 거절 분기, `isEligible` 비상 override 시 공용 패드 호환·크기·중량 검증, `handle_tower_handoff_req` `craftReq` 필터 전달 (`f46d0ce` + 후속 수정).
  3. `tui_view.lua`·`main.lua`: `format_dedicated_badge` Tab 2 Cyan 하이라이트, 비동기 인라인 프롬프트(`[A]`/`[P]`), `apply_operator_action` 설정 저장 실패 로그/전파 및 로컬 백본 `MSG_ATC_FACILITY_UPDATE` 동기화 (`ac98618`, `3825f7e` + 후속 수정).
- **검증 (2026-11-10 실행)**: 단위 308/308(GAC 46/46), E2E 6/6, 돌연변이 20/20 KILLED(100.0%), 하네스 41/41, 사양서 9 Implemented / 5 Approved(0 Errors/0 Warnings).

---

## 2026-11-10 — 루트 4대 마크다운 Mode B 감사 및 Tier 3 메모리 백필

- **결정 배경**: 감사 결과 `README.md` 수치 낡음(단위 293 → 실측 294, 하네스 33 → 실측 41), Windows PowerShell 5.1에서 `&&` One-Liner ParserError, `TASK.md` 과장 표현 3건 및 ICD 버전 낡음(v1.24.0 → 실제 v1.25.0), `GEMINI.md` Section 1 규격 초과(약 11줄·후보 7개), 본 아카이브의 TASK-113 이후 9개 마일스톤 누락을 확인함. 점수: AGENTS 88 / GEMINI 76 / TASK 70 / README 69.
- **반영 내역**:
  1. 본 아카이브에 2026-11-08 ~ 2026-11-09 마일스톤 9개 소급 기록.
  2. `GEMINI.md` Section 1을 다음 액션 3개로 압축, GDrive 배포 경로·명령 추가, PowerShell 5.1 체이닝 및 `/lib/avionics_sensors.lua` 예외 Gotcha 추가, 사양서 중복 Gotcha 3줄(VECTORED_VTOL·GCS·AMM) 제거, 인스톨러 이중 다운로드 표기 `GitHub/GCS` → `GitHub raw / Google Drive` 정정 — 해당 내용은 FCP/GCS/AMM 사양서와 아래 TASK-110/107/200 항목에 보존.
  3. `AGENTS.md` 과장 금지 절에 도구 출력 인용 규칙 1줄 추가 (사용자 승인 후 반영).
  4. `TASK.md` TASK-114 `[-]` 전환, TASK-201/202 사양서 현재/목표 버전 분리, TASK-116/117 사양서 선행 조건 명시, TASK-301 Phase 3 섹션 분리, 과장 표현 4건 교체 및 `100% CLEAN` 5건을 `0 Errors/0 Warnings`로 통일.
  5. `README.md` 수치를 GEMINI §3 참조로 대체, PowerShell 5.1 호환 One-Liner, `config/`·`dist_gdrive/`·`docs/guides/`·`docs/superpowers/plans/`·`tools/sync_gdrive.py` 구조도 보강, GDrive 배포 절 추가.
- **검증 기준선 (2026-11-10 실행)**: 단위 294/294, E2E 6/6, 하네스 41/41, 사양서 8 Implemented / 6 Approved, Lua 126 파일 문법 PASS. 돌연변이 테스트는 재실행하지 않음.

---

## 2026-11-09 — GDrive 배포 디렉토리 재지정 및 파일 관리 체계 구축 (TASK-009)

- **결정 배경**: `installer.lua`의 Google Drive 다운로드 경로를 지원하기 위해 업로드 대상을 저장소 구조와 분리된 격리 스테이징으로 관리하고, 파일 ID 매핑을 단일 원천으로 고정할 필요가 있었음.
- **반영 내역**: `dist_gdrive/` 스테이징 레이아웃(커밋 `8bf2aa9`), 인스톨러 구조화 `gdrive_mapping.json` 파싱(`8431cab`), `tools/sync_gdrive.py` `stage`/`sync`/`status`/`verify` CLI(`66834c6`, 외부 `gdrive` CLI 필요), 공식 폴더 `1NgbGjm9YY7lpIlo4sLs32cNE2NwjVVy9`로 부트스트랩 7종·인스톨러·센서 라이브러리 동기화 및 ID 임베딩(`decb69a`), 운영 가이드 `docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md`(`90bcc0a`).
- **검증**: 단위 294/294, 하네스 41/41, E2E 6/6, 돌연변이 20/20 KILLED.

---

## 2026-11-09 — 구버전 명칭(VAS-Core, VAS-Align, VAC-Align) 전면 치환 (TASK-008)

- **결정 배경**: TASK-007 이후에도 `VAS-Core`/`VAS-Align`/`VAC-Align`/`VAC-Core` 및 TCA 내 `VAC` 링크 스트림 명칭이 잔존하여 단일 표준(`VAS`, `Alignment`)으로 정리함.
- **반영 내역**: `tests/harness/test_terminology_guard.py` 금지 패턴 추가(`b471ba2`), 런타임 모듈 치환(`4991488`), TCA 테스트 단언 갱신(`3c83f2a`), 사양서 7종 치환(`aca89bb`), `verify_all_specs.py` Rule 8 확장.
- **검증**: 단위 293/293, E2E 6/6, 돌연변이 20/20, 하네스 36/36.

---

## 2026-11-09 — ADVANCED_VTOL 짐벌 벡터 추진 기종 전계층 연동 (TASK-115)

- **결정 배경**: 2D 짐벌 벡터 추진기(`vector_thruster` 계열)를 탑재한 고기동 기종을 기존 VECTORED_VTOL과 분리된 기종 정책으로 수용하기 위함.
- **반영 내역**: 사양서 6종 개정(ICD v1.25.0, 구조도 v2.11.0, TCA v1.11.0, VAS v1.18.0, FCP v1.15.0, Alignment v2.6.0, `7ee5d40`), TCA `setVector` 및 페일세이프 노즐 `(0, 0)` 복귀(`0eefd93`), Alignment 짐벌 펄스 및 $B^\dagger$ 산출(`ed68d37`), VAS 6-DoF 의사역행렬 믹서·안티와인드업(`61ae050`), FCP `advanced_vtol_driver.lua`(`95ba854`), GAC/Landing Pad/GCS/Installer 호환(`109c8aa`), 병합 `8c48468`.
- **검증**: 단위 293/293, E2E 6/6, 돌연변이 20/20, 하네스 33/33.

---

## 2026-11-08 — 구버전 명칭(UAP/SAS/WAP) 척결 및 용어 회귀 가드 구축 (TASK-007)

- **결정 배경**: 공력 구동계/비행 제어 명칭이 `UAP`/`SAS`/`WAP`와 `ASA`/`FCP`로 혼재하여 패킷 `podId`, 헬스 키, 모듈 파일명을 단일화함 (Zero-Fallback, 듀얼키 미보존).
- **반영 내역**: 회귀 가드 `test_terminology_guard.py`(`a51493e`), `verify_all_specs.py` Rule 8(`26bf042`), 런타임 식별자·모듈 개명 22개 파일(`a6c6311`), 사양서 14종 용어 정비 및 SemVer 승격(`4a8e26b`, `e3224bd`), 병합 `f7eb99b`.
- **검증**: 단위 248/248, E2E 6/6, 돌연변이 20/20, 하네스 33/33.

---

## 2026-11-08 — 멀티노드 E2E 시뮬레이션 및 돌연변이 테스트 체계 구축 (TASK-111)

- **결정 배경**: 단위 테스트만으로는 노드 간 패킷 시퀀스 결함을 검출할 수 없어 다중 노드 통합 검증 계층이 필요했음.
- **반영 내역**: `harness/simulation/virtual_bus.lua`, `_ENV` 격리 `node_sandbox.lua`, `tools/run_e2e_tests.py`(6개 시나리오), `tools/run_mutation_tests.py`(20개 결정론적 결함, 기준 90.0%, `7315403`), 원본 바이트·개행 보존 복원(`58d6c58`). 커밋 `646d831` ~ `81e584b`, 병합 `0ca7148`.
- **운용 원칙**: 노드별 `_ENV` 격리, 채널 배타성, 종료 시 `os.shutdown()` 핸드셰이크.

---

## 2026-11-08 — GCS 채널 관리자(CH 50000) 및 지상 비행 지휘 콘솔 (TASK-107)

- **결정 배경**: 40채널 블록 할당과 원격 C2를 담당할 중앙 지상 관제 노드가 필요했음.
- **반영 내역**: `CH 50000` 부트스트랩 블록 스티키 영속화, `Base+0` 원격 C2 오버라이드, `Base+1` 하드 `E_STOP` 직결 셧다운, `Base+3` 텔레메트리 캐시 및 51x19 무깜빡임 분할 TUI (`src/0_infra/gcs/`, 커밋 `e9febe6` ~ `e8c25b3`).

---

## 2026-11-08 — FCP VECTORED_VTOL 외루프 유도 고도화 (TASK-110)

- **결정 배경**: VECTORED_VTOL 외루프의 축 결합 및 이착륙 시퀀스 정밀도 개선.
- **반영 내역**: Surge/Sway/Heave 3축 완전 PID + Anti-windup, CRUISE 한정 TILT_ASSISTED 피치 슬루율 15°/s, 안전고도 미달 시 수평 차단 수직 이륙, 패드 0.5m 정렬 2단계 감속 터치다운 (`src/2_guidance/fcp/`, 커밋 `21f4e76` ~ `e6b22c8`).

---

## 2026-11-08 — 온보드 제어기 헤드리스 기본화 및 parallel 디버그 TUI 분리 (TASK-113)

- **결정 배경**: 터미널 렌더링 부하가 VAS/TCA/ASA 20Hz 제어 루프를 블로킹하는 문제 제거.
- **반영 내역**: 헤드리스 기본 구동, `config.json`의 `debug: true` 시에만 `parallel` 기반 비동기 디버그 TUI 구동, ASA 기본 프레임워크(`Base+11` 수신 루프, 300ms Safe Glide Trim) 구축 (`src/1_control/`, 커밋 `b5ee552` ~ `b2c5d5a`).

---

## 2026-11-08 — AMM 임무 관리자 및 Cockpit MFD 통합 단말 (TASK-200)

- **결정 배경**: TASK-106(Cockpit MFD)을 AMM에 병합해 조종석 단말을 단일화함.
- **반영 내역**: 51x19 분할 TUI(5Hz HUD + 미션 큐/C2), 순차 웨이포인트 큐(2D 수평 15m 자동 전환), JSON 영속화, GCS C2 무반향 감청, E-STOP/HOLD 선점 중재, 핫키 및 CLI (`src/3_planning/amm/`, 커밋 `3b2907a`).

---

## 2026-11-08 — VAS 센서 파이프라인의 CC:Avionics 표준 API 동기화 및 3축 속도/고도 정합화 (TASK-112)

- **결정 배경**: VAS의 내루프 실시간 동역학 제어용 `sensor_pipeline.lua`를 전역 표준 라이브러리(`/lib/avionics_sensors.lua`)와 정합화하고, 공식 CC:Avionics 센서 메서드(`getHeight()`, 1축 스칼라 `getVelocity()`의 3축 합성, 짐벌 오일러/각속도 벡터) 및 3D 기하 레버암 오프셋 보정을 통합 검증함.
- **반영 내역**:
  1. **사양서 갱신 (`VAS_PROGRAM_SPECIFICATION.md` v1.15.0)**: Section 2·3에 `/lib/avionics_sensors.lua` 연동 표준 명세 반영, Revision History 기록 (커밋 `1ee16b2`).
  2. **센서 파이프라인 리팩토링 (`src/1_control/vas/modules/sensor_pipeline.lua`)**: `require("avionics_sensors")` 연동, `getHeight()` 우선 호출 및 레거시 딕셔너리 폴백, 3D 레버암 기하 동역학 보정 적용 (커밋 `3c6b3e6`).
  3. **단위 테스트 확장 (`tests/1_control/vas/test_vas_core.lua`)**: 정밀 CC:Avionics 센서 모킹 샘플링 테스트 및 3D 레버암 오프셋 보정 정밀 테스트 추가 (12/12 PASS, 전체 146/146 PASS).
  4. **인스톨러 동기화 (`manifest.lua`)**: VAS 버전 1.15.0 갱신 및 `/lib/avionics_sensors.lua` 번들링 검증.

---

## 2026-11-08 — 루트 4대 마크다운(GEMINI·README·TASK·AGENTS) 감사 및 Phase 1 기준선 최신화

- **결정 배경**: Phase 1 착수 및 `TASK-101`(GAC), `TASK-102`(Landing Pad) 구현 완료 이후 루트 마크다운 문서 중 특히 `README.md`에 남아 있던 과거 Phase 0 잔재 수치(`71/71 PASS, 7개 타겟`, `5 Implemented, 7 Approved`)와 디렉토리 트리 결손(`sensors`, `gac`, `landing_pad`)을 해소하고, `GEMINI.md`와 `TASK.md`의 핸드오버 및 계획서 링크를 최신화하기 위해 `md-management` Mode B 감사를 수행함.
- **반영 내역**:
  1. **`AGENTS.md` 현행 유지**: 41줄 불변 헌장으로서 과장 금지 및 소통 원칙이 완결되어 있어 diff 없이 보존.
  2. **`GEMINI.md` 스냅샷 압축 및 사양서 상태 분포 동기화 (36줄)**: `TASK-102` 완료 상세 모듈 나열을 압축하고 `TASK-112` 착수 준비 상태와 사양서 7 Implemented, 5 Approved 최신 분포를 반영.
  3. **`README.md` 전면 최신화**: Phase 1 진행 중 상태 표기, 단위 테스트 `144/144 PASS`(10개 타겟), 하네스 `24/24 PASS`, 사양서 상태 분포 `7 Implemented, 5 Approved`로 동기화하고, `src/0_development/sensors/` 및 `tests/` 산하 `sensors`, `gac`, `landing_pad` 디렉토리 트리를 누락 없이 보강.
  4. **`TASK.md` 계획서 경로 및 형상 추적성 보강**: `TASK-112`에 사전 수립된 실행 계획서 경로를 명시하고, 최근 완료 작업(`TASK-100`~`TASK-102`)의 커밋 해시 범위를 보완.

---

## 2026-11-08 — CC:Avionics 4종 센서 API 표준 라이브러리(TASK-100) 구축 및 공용 /lib/ 주입 확립

- **결정 배경**: 전체 코드베이스에서 CC:Avionics 센서 4종(`velocity_sensor`, `altitude_sensor`, `gimbal_sensor`, `physics_assembler`)을 직접 분산 접근하며 발생하는 중복 로직, `mainThread = true` 틱 yield 분산 지연, 3축 분산 속도 센서 매핑 파편화를 해소하기 위해 단일 원본(SSOT) 표준 라이브러리(`avionics_sensors`)를 구축하고 인스톨러 및 하네스에 자동 주입 파이프라인을 확립함.
- **반영 내역**:
  1. **표준 센서 라이브러리 구현 (`src/0_development/sensors/avionics_sensors.lua`)**: 4종 센서 전용 peripheral 탐색, 속도 단건/3축 합성(`get_triaxial_velocity`), 고도 요약(`get_altitude_summary`), 짐벌 자세/각속도/가속도/중력(`get_gimbal_summary`), 어셈블러 `parallel.waitForAll` 1틱 일괄 쿼리(`get_physics_summary`) 구현.
  2. **하네스 공용 `/lib/` 자동 주입 및 정밀 Mocking (`harness/unit/engine.py`, `test_sdk.lua`)**: 단위 테스트 세션 격리 시 `src/0_development/sensors/*.lua`를 게스트 컴퓨터 루트 `/lib/`로 자동 스테이징하고, `mock.cc_*` 4종 Mock 구축 (`tests/harness/test_guest_sdk.py` 2/2 PASS).
  3. **통합 인스톨러 배포 연동 (`manifest.lua`, `startup_generator.lua`)**: 8번째 모듈 `sensors` 등록 및 모든 타겟 설치 번들에 `/lib/avionics_sensors.lua` 포함, 부팅 훅의 `package.path`에 `/lib/?.lua` 자동 주입.
  4. **전역 회귀 검증 통과**: 8개 타겟 단위 테스트 `85/85 PASS`, 하네스 자체 회귀 `24/24 PASS`, 91개 Lua 문법 전수 PASS, 12개 사양서 무결성 `0 Errors 0 Warnings` 확인.

---

## 2026-11-08 — 검증 스크립트 정식 도구화(TASK-006) 및 Phase 0 종결

- **결정 배경**: 임시 작업 공간(`scratch/`)에 혼재되어 있던 핵심 사양서·문법 검증 스크립트를 정식 도구 디렉토리(`tools/`)로 격리 이관하고, 도메인 하위 README 내 폐기된 구 사양서 경로(`docs/specs/approved/...`) 잔재를 전수 정리함.
- **반영 내역**:
  1. **검증 도구 정식화 (`tools/`)**: `verify_all_specs.py`, `validate_lua_syntax.py`, `verify_spec_status.py`를 `tools/`로 이관하고, Windows 동적 DLL 탐색 보강 및 90개 Lua 전수 문법 검사 지원.
  2. **임시 스크립트 정리 및 가이드 확립**: 일회성 `scratch/` 스크립트를 제거하고 `scratch/README.md`를 신설하여 임시 스크립트 격리 원칙 확립.
  3. **서브시스템 README 영구 단일 경로 정합화**: `src/1_control/asa/README.md` 및 `src/0_infra/gac/README.md` 내 폐기된 구 경로 링크를 제거하고 `verify_all_specs.py --check-readmes` 0 error 달성.
  4. **도구 무결성 자동화 테스트 및 Phase 0 전 과제 종결**: `tests/harness/test_tools_integrity.py`(5/5 PASS) 추가로 하네스 자체 회귀 `23/23 PASS` 달성, Phase 0 전 과제 완료 및 Phase 1 인계 준비 완료.

## 2026-11-08 — 통합 코드베이스 설치 프로그램(TASK-005) 구축 및 GPS 사양서 v2.2.0 Implemented 승격

- **결정 배경**: 분산된 개별 모듈 인스톨러(`gps/installer.lua` 등)를 폐기하고, 단일 진입점 기반으로 7개 전 모듈을 일괄 설치·갱신·마이그레이션할 수 있는 전역 통합 인스톨러와 단위 테스트 하네스를 구축함.
- **반영 내역**:
  1. **통합 인스톨러 아키텍처 확립 (`installer.lua`, `src/0_development/installer/`)**: 화면 직접 업로드, 플로피 디스크(`/disk/`), 원격 HTTP(`wget run`) 3대 배포 방식 및 GitHub/Google Drive 듀얼 다운로드 소스 지원.
  2. **선언적 매니페스트 및 자동 마이그레이션**: `manifest.lua`, `version_registry.lua`, `migration_engine.lua`, `startup_generator.lua`를 구축하여 `/.version.json` 메타데이터 및 기존 설정 파일 보존 지원.
  3. **Zero-Fallback 구버전 정리 및 GPS v2.2.0 승격**: `src/0_infra/gps/installer.lua` 및 `installer_core.lua` 완전 제거, `GPS_PROGRAM_SPECIFICATION_AND_ICD.md` 상태를 `Implemented`로 전이.
  4. **전역 검증 통과**: 7개 타겟 단위 테스트 `71/71 PASS`, 하네스 회귀 `18/18 PASS`, 12대 사양서 무결성 `0 Errors 0 Warnings` (5 Implemented, 7 Approved).

## 2026-11-08 — 루트 4대 마크다운 문서(AGENTS·GEMINI·README·TASK) 감사 및 아키텍처 정합화

- **결정 배경**: `Phase 0` 런타임 동기화 완료 직후 루트 문서 간 이중 로드 토큰 중복, 진부화된 태스크 상태(`SAS`, `TASK-001 진행 예정`, `TASK-002` 중복), 마스터 ICD와의 수치/도메인 불일치(`N <= 99`, `ASA 레이더` 오기재 등), Windows `git.exe`·CraftOS-PC 의존성 누락을 일괄 해소하기 위해 `md-management` Mode B 감사를 수행함.
- **반영 내역**:
  1. **`AGENTS.md` 미세 보정 (사전 승인 완료)**: 에세이형 수사 문구 및 시스템 `<guidelines>` 중복 문장을 압축(45줄 → 40줄)하고, `Plain-prose exceptions` 5번 항목에 `TASK.md`, `docs/**`, `reports/**`, `CHANGELOG.md`를 명시하여 영속 문서 작성 시 문체 압축 오적용을 방지함.
  2. **`GEMINI.md` 토큰 중복 제거 및 비자명 Gotcha 보강 (40줄)**: 매 턴 자동 주입되는 `.agent/rules/`·`<skills>` 설명 중복을 덜어내고, PowerShell `git.exe` 절대 경로, `CraftOS-PC_console.exe`(`CRAFTOS_PC_EXE`) 의존성, 멀티 코드베이스 `Self-Contained` 원칙, 전역 RF 스펙트럼(`101~200`, `10000~49999` $N\le 1000$, `50000~60020`) 및 최신 커밋(`4c1db74`) 기준을 반영함.
  3. **`README.md` 사실관계 교정 및 온보딩 보강**: 개별 태스크 복제본을 제거해 `TASK.md`로 단일 위임하고, 사전 요구사항(`Python 3.10+`, `CraftOS-PC`, 모드 허용/차단 목록), 전역 스펙트럼 할당표, ICD 기준 4대 Zone(`Base+10` TCA, `Base+11` ASA 등), 하네스 회귀 명령을 정비함.
  4. **`TASK.md` 중복 표 제거 및 Option A 종결**: 21줄 정적 디렉토리 표를 제거하고, `42/42 PASS`·하네스 `14/14 PASS` 달성 기준에 따라 `TASK-001`·`TASK-002`를 완료 아카이브로 이관했으며, `TASK-105` 명칭을 `ASA (Aerodynamic Surface Adapter)`로 교정하고 누락 백로그(`TASK-006` 검증기 `tools/` 이관, `MFD`, `GCS`, `Tower ATC`, 멀티노드 E2E)를 등록함.


## 2026-11-08 — 사양서 영구 단일 경로 전환, 단위 테스트 하네스 구축, SAS→FCP 개명 및 40채널 런타임 동기화

- **결정 배경**: 상태 전이마다 사양서 디렉토리를 이동(`approved/` ↔ `implemented/`)하던 구 방식의 상대 링크 파손 문제를 해결하고, 40채널($BW=40$) 규격을 실제 Lua 코드베이스와 자동화 테스트로 검증하기 위해 아키텍처 및 런타임 동기화를 수행함.
- **반영 내역**:
  1. **영구 단일 계층(`docs/specs/<domain>/<subsystem>/`) 확립**: 상태별 하위 디렉토리를 폐지하고 문서 상단 5대 항목 메타데이터 표(`Status`, `Version`, `Date`, `Source`, `Domain`)로 생명주기를 인플레이스 관리하도록 전환함 (구 `2026-11-07` 디렉토리 이동 규칙 대체).
  2. **CraftOS-PC 단위 테스트 하네스 구축 (`harness/unit/`, `tools/run_unit_tests.py`)**: 격리 세션, Peripheral/Rednet 모킹, 게스트 SDK, 정적 가드를 구축하고 하네스 자체 Python 회귀 테스트(`14/14 PASS`)를 확보함.
  3. **`SAS` → `FCP` 전면 개명 및 `0_ground` → `0_infra` 통합 (커밋 `7d37d40`)**: 유도 계층 명칭·경로·런타임 식별자(`FCP`, `FCP-04`)를 일원화하고 지상 시설 도메인을 `0_infra/`로 단일화함.
  4. **5대 코어 모듈 40채널 런타임 동기화 완료 (`TASK-001`, 커밋 `16b8390`~`4c1db74`)**: `VAS`, `TCA`, `FCP`, `Alignment`, `GPS`의 채널 수식·Zone·동적 리바인딩 트랜잭션을 동기화하고 6대 타겟 단위 테스트 `42/42 PASS`를 확인함.


## 2026-11-07 — 기체 통신 40채널 전면 확장 및 12대 핵심 사양서 전수 리팩토링·검증 완료

- **결정 배경**: 과거 20채널 협소 대역폭($BW=20$) 및 구동계 채널(`Base+6`, `Base+7`) 밀집 한계를 극복하고, 구동계/탑재체/편대 데이터링크를 10채널 단위 4대 Zone으로 체계화하기 위해 기체 채널 대역폭을 $BW=40$으로 전면 확장함.
- **반영 내역**:
  1. **대역폭 및 4대 Zone 확립**: $Base = 10000 + (N-1) \times 40$ ($N=1\sim 1000$).
     - Zone 1 (0~9): 코어 C2/센서/유도/텔레메트리
     - Zone 2 (10~19): 구동계 전용 — TCA 추진기 `Base+10` (구 `Base+6` [DEPRECATED]), ASA 조종면 `Base+11` (구 `Base+7` [DEPRECATED])
     - Zone 3 (20~29): 탑재체 전용 버스
     - Zone 4 (30~39): 편대 데이터링크
  2. **12대 사양서 전수 리팩토링**:
     - Tier 1 마스터 ICD, Tier 2 관계도/패킷도, Tier 3 10종 사양서 전역에 40채널 수식 및 Zone 할당 동기화.
     - 런타임 코드 수정 대상 5대 사양서(VAS, TCA, SAS, Alignment, GPS)를 `implemented/`에서 `approved/`로 승격 이동.
     - 8대 주요 사양서에 SemVer 판올림 및 `Revision History` 테이블 신규 작성·누적.
     - Zero-Fallback & `Sender-Immediate-Patch` 원칙 적용: 사양서 내 구버전 명칭은 `[DEPRECATED]` 배지로 보존.
  3. **무결성 전수 검증 (`scratch/verify_all_specs.py`)**:
     - 12개 사양서 상대 링크(0 Broken), Stale `implemented/` 링크(0건), Revision History 존재성, 폐기 문자열 중첩 여부, 미폐기 Base+6/7 여부, 40채널 수식 정합성, Mermaid 구문 유효성을 자동 검사하여 **0 Errors, 0 Warnings** 전수 통과 확인.


## 2026-11-07 — 사양서·문서·완료 스킬군 적용 범위 분리 및 전역 기획 스킬 오발동 차단

- **결정 배경**: 12종 사양서 및 `specification-lifecycle-manager` 이식 직후, 일반 Q&A·`/plan` 아티팩트·`reports/` 보고서·`drafts/` 초안 편집 및 코드 검증 완료 후 `approved/`→`implemented/` 승격 시 스킬 오발동이나 Mixed-Scope Hard Stop 충돌이 발생할 수 있어 관할 경계를 재정립함.
- **반영 내역**:
  1. **`specification-lifecycle-manager` 경로 × 행위 이중 게이트**: `docs/system/*.md` 및 `docs/specs/{approved,implemented}/**/*.md`(`README.md`·`drafts/`·`archived/`·`reports/` 제외)의 생성·수정·폐기·명시적 감사 시에만 발동하며, 읽기 전용 참조·Q&A·`/grill-me`·`/plan` 아티팩트에서는 비발동으로 고정.
  2. **양방향 동기화 디렉토리 판정 및 메타데이터 규칙**: `src/` 런타임 코드 수정이 필요한 Tier 3 사양서만 `approved/`로 이동하고 단순 상대 링크·버전 배지만 갱신된 사양서는 `implemented/` 유지; 상단 SemVer 인용구를 기본 유지하되 실질 스펙 변경(`approved/` 이동 대상) 시에만 `Revision History` 테이블 신설·누적.
  3. **코드 완료 승격 경량 예외 (`verification-before-completion`)**: 검증 통과 직후 `approved/`→`implemented/` 파일 이동 및 `docs/` 내 상대 링크 치환은 Mixed-Scope 중단에서 면제하고 `specification-lifecycle-manager` 호출 없이 완료 게이트에서 직접 처리.
  4. **인접 로컬 스킬 분리 및 전역 플러그인 차단**: `md-management`(`AGENTS.md`·`GEMINI.md`·`.agent/memory/`), `writing-changelogs`(`CHANGELOG.md`)의 배타적 관할을 명시하고, `skill-workflows.md`에서 전역 `superpowers`의 `using-superpowers`·`brainstorming`·`writing-plans`·`executing-plans` 자동 호출을 차단함.

## 2026-11-07 — Git 형상 관리 시작 및 Worktree 격리 환경 구축

- **결정 배경**: 프로젝트의 지속적인 변경 추적, 다중 브랜치 병렬 작업(Worktree), 안전한 원격 협업을 위해 Git 버전 관리 체계를 정식 도입함.
- **반영 내역**:
  1. **Git 저장소 초기화**: `main` 기본 브랜치로 초기화(`git init -b main`)하고 작성자(`Polimachi` / `abovepolaris110@gmail.com`) 및 `credential.helper manager` 등록.
  2. **Worktree 격리 경로 확보**: `using-git-worktrees` 표준에 맞춰 `.worktrees/` 및 `worktrees/`를 `.gitignore`에 추가하여 격리 브랜치 작업물이 메인 트리에 오인 커밋되지 않도록 보장.
  3. **원격 저장소 연동**: GitHub 원격 저장소(`https://github.com/Polimachi/Aeroneutics_Autopilot.git`)를 `origin`으로 등록.
  4. **Phase 0 기준선 커밋**: 사양서 12종, GPS 및 제어 소스, 에이전트 규칙/스킬 등 131개 파일(20,342 LOC)을 포함하는 초기 기준선 커밋 생성.


## 2026-11-07 — 사양서 생명주기 하네스 규칙 개정 (수정 시 approved 직행 / 검증 완료 시 implemented 이동)

- **결정 배경**: 사양서가 수정되었을 때 구현 전 단계(`approved/`)로 즉시 이동시키고, 코드베이스에 반영 및 검증이 완료되었을 때 구현 완료 단계(`implemented/`)로 자동 전환하는 규칙을 하네스 시스템에 강제하고자 함.
- **반영 내역**:
  1. **가이드 문서 개정 (`docs/specs/README.md`)**:
     - 4단계 상태 전이 흐름도 추가 (`drafts` 신규 기획 → `approved` 구현 대기·수정 직행 → `implemented` 구현 완료 → `archived` 폐기/대체).
     - 수정 발생 시 `drafts/`를 거치지 않고 `approved/`로 직행 이동 및 계층 디렉토리 경로 보존 원칙 명시.
     - 사양서 상단에 `Revision History`(버전, 일자, 변경 요약, 변경 사유) 필수 작성 표준 확립.
  2. **에이전트 규칙 반영 (`.agent/rules/skill-workflows.md`)**:
     - `사양서 생명주기 가드레일` 신설: 프로덕션 코드 작성 전 `approved/` 확인, 작업 완료 전 `verification-before-completion` 통과 후 `implemented/` 자동 이동 강제.
  3. **컨텍스트 스냅샷 동기화**: `GEMINI.md`에 사양서 생명주기 상태 갱신.

## 2026-11-07 — 15종 역할별 스킬·규칙 설치 및 3계층 메모리 체계 확립

- **결정 배경**: 전역 `using-superpowers` 환경에서 단순 대화 중 `TDD`·`검증` 스킬이 오발동하거나 대용량 스킬 열람으로 컨텍스트가 낭비되는 문제를 막고, 세션 간 프로젝트 맥락을 유지할 체계가 필요했음.
- **반영 내역**:
  1. **3계층 컨텍스트 분리**: `AGENTS.md`(불변 행동 원칙, 사전 승인 필수) / `GEMINI.md`(80줄 상한 현재 상태 스냅샷, 마일스톤 비대칭 즉시 갱신) / `.agent/memory/<dir>.md`(온디맨드 누적 이력, 코드 마운트 오염 방지).
  2. **Rule 3종 + Scoped Skill 12종 정비**: `skill-workflows.md`(`always_on`)로 단순 대화·설계 중 구현 스킬 호출을 차단하고, 전역 동명 스킬 3종(`TDD`, `verification-before-completion`, `using-git-worktrees`)을 로컬 음성 가드로 Override함.
  3. **`computercraft-lua` 분할 및 도메인 정합화**: 839줄 원본을 `SKILL.md` + `references/` 4종으로 분할하고, `Create Propulsion: Simulated`의 `ion_thruster`와 `Lua-Harness` 금지 목록 간 충돌을 해소(`kontraption:` 네임스페이스만 차단)함.

## 2026-11-07 — 하네스 밑바닥 재구축을 위한 Phase 0 클린 캔버스 초기화

- **결정 배경**: 초기 스캐폴딩에서 임의로 생성된 임시 코드·테스트·러너(`src/`, `tests/`, `tools/` 등)가 하네스 아키텍처 설계에 선입견과 제약을 줄 수 있어 초기화를 결정함.
- **반영 내역**: 비규칙 폴더 전체 및 구 `harness-verification.md`를 제거하고 도메인·런타임 불변 규칙만 보존한 Phase 0 상태로 리셋함.

## 2026-11-06 — Create_Aeroneutics 독립 워크스페이스 출범

- **결정 배경**: 기존 `Antigravity_Workspace`(`Lua_Harness`, `TAP`, `GPS`, `UAP` 등)의 컨텍스트 영향 없이 CC:Tweaked 기반 Create: Aeronautics 코드를 클린 룸에서 개발하기 위해 별도 루트를 생성함.
