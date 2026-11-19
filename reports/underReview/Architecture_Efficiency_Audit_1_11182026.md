# Create_Aeroneutics 제품 아키텍처 효율성·효용성 검사 보고서 (`TASK-016`)

| 항목 | 내용 |
|---|---|
| 문서 ID | `Architecture_Efficiency_Audit_1_11182026` |
| 검사 범위 | 제품 아키텍처 L1(토폴로지) · L2(RF/프로토콜) · L3(코드 구조) · L4(사양 체계) + 분할 트랙(S) + `docking_arm` `[SPEC-ONLY]` |
| 기준 커밋 | `d63d0db` (P0 기준선) / `eb339b5` (P1 계측·감사 도구 병합) |
| 작성일 | 2026-11-18 |
| 선행 감사 | [Audit_Report_1_11142026.md](../reviewCompleted/Audit_Report_1_11142026.md) (`TASK-013` 정합성 전수 감사) |
| 원자료 경로 | `reports/audit_data/2026-11-18/{registry,e2e_profile,static,dupes,specs,split}.json` |

---

## 1. 기준선 및 계측 오버헤드 (P0 · P2 실측)

### 1.1 P0 전 게이트 기준선 (커밋 `d63d0db`)

| 게이트 | 실행 명령 | 결과 | 소요 시간 (ms) |
|---|---|---|---:|
| 와이어 계약 검증 | `python tools/verify_contracts.py` | 18 활성 사양 · 145 코드/설정, 0 errors | 1,800 |
| 런타임 배선 검증 | `python tools/verify_runtime_wiring.py` | 13 서브시스템, 0 violations (4 알려진 예외) | 593 |
| 컨텍스트 문서 | `python tools/verify_context_docs.py` | 0 findings | 126 |
| 매니페스트 3-Way | `python tools/verify_manifest_sync.py --strict-gdrive-packages` | 15 모듈 · 134 경로 · 145 소스 · 135 GDrive, 0 Errors/Warnings | 133 |
| 사양·README 링크 | `python tools/verify_all_specs.py --check-readmes` | 17 사양, 0 Errors/Warnings | 244 |
| Lua 5.2 문법 | `python tools/validate_lua_syntax.py` | 140 Lua 파일 PASS | 171 |
| 사양 상태 | `python tools/verify_spec_status.py` | 18 사양 (14 Implemented, 4 Approved) PASS | 76 |
| 실부팅 스모크 | `python tools/run_boot_smoke.py --clean-orphans` | 13/13 PASS | 8,401 |
| Lua 단위 테스트 | `python tools/run_unit_tests.py --require-tests --clean-orphans` | 15 타겟, 629/629 PASS | 11,694 |
| Lua E2E 테스트 | `python tools/run_e2e_tests.py --clean-orphans` | 10 스위트, 23/23 PASS, 566 패킷 · 0 violations | 2,042 |
| 돌연변이 테스트 | `python tools/run_mutation_tests.py` | 25/25 KILLED (100.0%, 기준 90.0%) | 33,991 |
| 하네스 회귀 | `python -m unittest discover -s tests/harness -p "test_*.py"` | 141/141 OK (P1 후 `150/150` → P6 후 `152/152`) | 16,626 |
| WebUI 테스트 | `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py` | 30/30 OK | 9,390 |

### 1.2 E2E `--profile` 계측 무간섭 및 오버헤드 실측 (P2)

- `--profile` 미지정 vs 지정 비교(`reports/audit_data/2026-11-18/e2e_profile.json`):
  - **동작 동일성**: 두 모드 모두 `23/23 PASS`, `566 packets validated, 0 violations`로 동일.
  - **실행 시간**: 비계측 `2,080 ms` vs 계측 `2,041 ms` (프로세스 기동 편차 범위 내; 게스트 내부 총 `2,116,700` 바이트코드 명령어, `279 ms` 누적 CPU 기록).
- **계측 특성 주의**: `node_sandbox.lua`의 `cpu_ms`는 `os.epoch("utc")` 기반 1 ms 벽시계 차분이므로 CraftOS 호스트 `fs` 파일 I/O 대기 시간까지 포함한다. 핫스팟 비교는 `insns`(바이트코드 명령어)와 스위트 격리 실측을 함께 사용한다.

---

## 2. 렌즈별 요약 및 판정 분포

표준 6-판정 매트릭스(**Keep** U2~3/E2~3, **Optimize** U2~3/E0~1, **Watch** U1/E2~3, **Consolidate** U1/E0~1, **Investigate** U0/E2~3, **Retire** U0/E0~1)로 정규화한 분포는 다음과 같다.

| 렌즈 | 대상 수 | Keep | Optimize | Watch | Consolidate | Investigate | Retire | 핵심 소견 |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| **L1 토폴로지** | 16 (15 활성 + `[SPEC-ONLY]` 1) | 14 | 0 | 2 | 0 | 0 | 0 | 온보드 제어 루프가 전체 E2E 명령어의 `85.45%` 차지. `TCA` CPU 스파이크 원인은 `ota_agent` 파일 I/O(`V-A` 교정). 지상 3종 20Hz 동기 TUI, `FCP` Rebind 중계 홉 확인. |
| **L2 RF·프로토콜** | 18 (대역/엔벨로프/인터페이스/레거시/도킹암) | 4 | 8 | 1 | 4 | 0 | 1 | `AMM` Zone 3 `30..39` 차단 버그, `protocol_contracts.json` 5종 E2E + 9종 `src/` 패킷 누락, `AMM` 사문화 16핸들러, `requiredKeys` 9필드·`optionalKeys` 25엔트리 미소비. |
| **L3 코드 구조** | 18 (14 활성 + `/lib` 2 + `installer` + WebUI) | 12 | 3 | 1 | 1 | 0 | 1 | `installer.lua` 400줄 중복, 복사본 간 논리 분기 3건(shallow copy·Euler·시그니처), 사문화 함수 17종, 미사용 설정키 19종, `46,080 B` 초과 Lua 3종 + WebUI 1종. |
| **L4 사양 체계** | 18 활성 사양 | 12 | 4 | 2 | 0 | 0 | 0 | 커밋당 평균 `6.09` 문서 동시 수정, 인라인 피어 버전 배지 `111/210 (52.9%)` 부패, `Implemented` 사양 내 6메시지 드리프트, `verify_all_specs.py` WebUI 사양 1종 누락. |

*(주: L1 `TCA`/`OTA`는 `V-A` 교차 검증으로 호스트 NTFS I/O 귀속이 확인되어 L1 구조적 `Optimize`에서 `Keep`으로 재분류되었으며, 지상 20Hz TUI 분리 등은 후속 `TASK-021`로 관리한다. L2 `docking_arm`과 L3 `src/0_development/installer/installer.lua`는 각각 `Consolidate`, `Retire` 판정에 해당한다.)*

---

## 3. 상위 발견 항목 (교차 검증 완료, Confidence >= 80)

우선순위 지수 산식: **Priority = (예상 절감/개선 효과 1~10 × 신뢰도/100) ÷ 변경 위험도(1~5)**

| 순위 | EvID | 렌즈 | 제목 및 교차 검증 결과 | 신뢰도 | 효과/위험 | Priority | 후속 TASK |
|---:|---|---|---|---|---:|---:|---|
| 1 | **E-L2-01** | L2 | **`AMM` Zone 3 `30..39` 하드코딩 차단 버그** — `protocol_contracts.json`은 `20..39`를 허용하나 `amm/modules/{mission_engine.lua:120-127, network_manager.lua:111,266,273}`가 `20..29`로 제한(`INVALID_ZONE3_CHANNEL`). (`V-B CONFIRMED`) | 98 | 9 / 1 | **8.82** | `TASK-017` |
| 2 | **E-L4-04** | L4 | **`verify_all_specs.py` 18번째 사양 누락** — `verify_spec_status.py`·`verify_contracts.py`는 18종을 검사하나 `verify_all_specs.py:16-54`는 17종만 열거해 `AMM_MISSION_EDITOR_SPECIFICATION.md` 미검증. (`V-B CONFIRMED`) | 98 | 8 / 1 | **7.84** | `TASK-019` |
| 3 | **E-L3-01** | L3 | **`installer.lua` 400줄 byte-identical 이중 복제** — 루트 `installer.lua`와 `src/0_development/installer/installer.lua`가 SHA-256 동일(`17,676 B`, `453 L`; 전체 복제 `541`줄 중 `73.9%`). `BOOTSTRAP_FILES` 3중 복제. (`V-A CONFIRMED`) | 100 | 8 / 2 | **4.00** | `TASK-018` |
| 4 | **E-L3-02** | L3 | **독립 완결 복사본 간 논리 분기 3건 + 11쌍 유사 복제** — `tca/config_manager.lua:28` 얕은 복사(중첩 테이블 앨리어싱) vs `asa` 깊은 리터럴; `vas/quat.lua` `[0,360)` vs `fcp` `[-180,180]`; `vas/state_machine` vs `amm/mission_engine` `save_flight_state` 인자 순서 불일치; `landing_pad`↔`runway` 11쌍 유사+2쌍 완전 복제. (`V-A PARTIALLY_CONFIRMED`: `9`→`11`쌍 교정) | 96 | 8 / 2 | **3.84** | `TASK-018` |
| 5 | **E-L2-02** | L2 | **`protocol_contracts.json` 5종 E2E + 9종 `src/` 패킷 누락** — `MSG_ATC_SLOT_ASSIGN/ACK`, `MSG_GPS_NODE_REPORT`, `MSG_GPS_STATUS_REQ/RESP`가 E2E에서 실제 송신되나 계약에 미등록. 반대로 계약된 10종은 E2E 트래픽 `0`. (`V-B PARTIALLY_CONFIRMED`: 활성 `src/` 9종 + `amm` 화이트리스트 전용 2종 구분) | 96 | 8 / 2 | **3.84** | `TASK-017` |
| 6 | **E-L2-03** | L2 | **`amm/main.lua` 사문화 16핸들러 vs `RUNWAY` 송신 누락** — `BASE_PLUS_5_INFRA_RESPONSES` 내 16개 미계약 `MSG_*`는 `src/` 송신자 0. 반대로 `runway_fsm.lua`의 `MSG_RUNWAY_TOUCHDOWN`/`VACATED`는 `amm` 송신자 0. (`V-B PARTIALLY_CONFIRMED`: `14`→`16`개 교정) | 95 | 7 / 2 | **3.33** | `TASK-017` |
| 7 | **E-L4-01** | L4 | **사양 동기화 세금 `6.09`문서/커밋 & 52.9% 배지 부패** — 18 사양 인라인 피어 버전 배지 `210`개 중 `111개(52.9%)`가 구버전. (`V-B CONFIRMED`) | 96 | 9 / 3 | **2.88** | `TASK-019` |
| 8 | **E-L2-04** | L2 | **미소비 페이로드 필드 29종(`requiredKeys` 9 + `optionalKeys` 20)** — `MSG_PBIT_REPORT.{overallStatus, checks}`, `MSG_CALIB_PULSE.safetyMaxTiltDeg`, `MSG_FACILITY_BEACON.facilitiesSummary` 등 `requiredKeys` 9개가 `src/`·`tools/` 어디에서도 미참조. (`V-B CONFIRMED`) | 94 | 6 / 2 | **2.82** | `TASK-017` |
| 9 | **E-L4-03** | L4 | **`Implemented` 사양 내 6개 메시지 드리프트** — `Diagram:504` 폐기 `MSG_ATC_RUNWAY_CLEAR` 잔존, `LandingPad:529` `MSG_GAC_DEPARTURE_COMPLETE` 오기, `MSG_TAXI_CMD` 및 `GAC` 3종 미구현. (`V-B CONFIRMED`) | 95 | 6 / 2 | **2.85** | `TASK-019` |
| 10 | **E-L3-03** | L3 | **검증된 사문화 함수 17종 & 미사용 설정키 19종(`E-L3-04`)** — `tca/tui_dashboard`(3), `fcp/network_manager`(3), `fcp/flight_fsm`(3), `amm`(3), `vas`(4), `landing_pad`(1) 전원 단일 정의선만 존재; `amm_config.json` 10키·`fcp_config.json` 6키·`fdr_config.json` 3키 미사용. (`V-A CONFIRMED`) | 95 | 5 / 2 | **2.38** | `TASK-018` |
| 11 | **E-L1-04** | L1 | **지상 3종(`GAC`, `LANDING_PAD`, `RUNWAY`) 20Hz 루프 동기 TUI** — 매 `0.05s` 틱마다 터미널 렌더링 수행, `headless` 플래그 부재. (`V-A CONFIRMED`) | 95 | 7 / 3 | **2.22** | `TASK-021` |
| 12 | **E-L3-05** | L3 | **200줄+ 거대 함수 8종 & `amm` 대형 파일 2종 + `manifest.lua`** — `gac_fsm.create`(356 L) 등 클로저 팩토리 집중 및 `amm/main.lua`(53.2 KB)·`mission_engine.lua`(51.9 KB) 46KB 초과. (`V-A CONFIRMED`) | 95 | 8 / 4 | **1.90** | `TASK-020`, `TASK-021` |
| 13 | **E-L1-05** | L1 | **`FCP` `MSG_CHANNEL_REBIND` 동기 중계 홉 & 3중 DR 전파** — `AMM`↔`FCP`↔`VAS`↔`TCA/ASA` 2단 중계 및 3노드 독립 20Hz DR 루프 병행. (`V-A CONFIRMED`) | 90 | 5 / 4 | **1.13** | (관찰·장기 검토) |

*(E-L1-01·02·03·06·07 및 E-L2-05·06, E-L4-02·05는 아래 §4~§6 및 부록에 통합 수록)*

---

## 4. 분할 트랙(S) 결과

기준 임계값: Lua `>= 20,000 B` 또는 `>= 450 L` (21종), 서브시스템 `>= 90,000 B` (5종), 사양서 `>= 80,000 B` (7종), WebUI `>= 100,000 B` (1종), 에이전트 단일 읽기 상한 `46,080 B`.

### 4.1 서브시스템 (5종) 및 WebUI (1종)

| 대상 | 규모 | N 평균 / 수준 | F 평균 | 판정 | 제안 경계 및 예상 파급 |
|---|---|---:|---:|---|---|
| `3_planning/amm` | 299,795 B / 7,513 L / 15파일 (`require` 129.1k) | 2.8 (High) | 2.4 | **Split** | 서브시스템 단일 디렉토리 유지, 내부 비대 2파일(`main.lua`, `mission_engine.lua`) 분할 (매니페스트/GDrive +4~6). |
| `0_development/installer` | 148,145 B / 3,554 L / 9파일 | 1.6 (High) | 1.6 | **Extract** | `manifest.lua` 카탈로그 분리 + `installer.lua` 중복 1벌 정리. |
| `1_control/vas` | 151,703 B / 3,630 L / 15파일 (`require` 70.8k) | 1.6 (High) | 2.4 | **Keep** | 이미 15모듈로 균형 분할됨(최대 파일 24.0 KB). |
| `0_development/ota` | 97,293 B / 2,747 L / 5파일 | 1.2 (Low) | 1.2 | **Keep-Justified** | `/lib/ota_agent.lua` + 서버 2역할 합산 규모; 타겟당 `<= 58 KB`. |
| `0_infra/gps` | 96,082 B / 2,396 L / 15파일 | 0.8 (Low) | 2.6 | **Keep-Justified** | 3역할(`server`/`node`/`hal`) 15소모듈 분할 완료(최대 19.4 KB). |
| `tools/amm_mission_editor.html` | 260,802 B / 5,196 L (`5.66x`) | 1.8 (High) | 1.6 | **Keep-Justified** *(Gate 4: A4)* | 내부 11개 IIFE 모듈 분리 완료; `file://` 단일 HTML 제약 및 `test_amm_mission_editor.py` 정규식 추출 제약으로 분할 보류(A4). |

### 4.2 대형 Lua 파일 (21종)

| 판정 | 대상 (규모) | 핵심 근거 및 제안 경계 |
|---|---|---|
| **Split** (2) | `src/3_planning/amm/main.lua` (`53,250 B / 1,289 L`), `src/3_planning/amm/modules/mission_engine.lua` (`51,861 B / 1,254 L`) | `46,080 B` 초과 + `N >= 2.4`. 각각 (`amm_cli`, `cold_boot_recovery`, `infra_rx_router`) 및 (`mission_validator`, `mission_dispatchers`)로 분할 (`TASK-020`). 파급: `manifest.lua`/`gdrive_mapping.json` 각 +2~3. |
| **Extract** (1) | `src/0_development/installer/modules/manifest.lua` (`48,420 B / 915 L`) | `46,080 B` 초과 + 670 L 데이터 카탈로그 혼재. `manifest_catalog.lua` 분리 (`TASK-020`), `ota_server.sync_remote` 동시 갱신. |
| **Retire** (1) | `src/0_development/installer/installer.lua` (`17,676 B / 453 L`) | 루트 `installer.lua`와 SHA-256 동일본 (`400` 중복 줄). 1벌 정리 (`TASK-018`). |
| **Keep-Justified** (3) | `installer.lua` (`17,676 B`), `ota_agent.lua` (`38,201 B`), `avionics_sensors.lua` (`37,994 B`) | `wget run` 단일 파일 요건 및 `/lib/` 2파일 불변식 준수. |
| **Keep** (14) | `ota_server.lua` (`35,698 B`), `c2_arbiter.lua` (`24,605 B`), `vas/network_manager.lua` (`24,015 B`), `trajectory_generator.lua` (`23,333 B`), `installer_app.lua` (`22,797 B`), `vas/state_machine.lua` (`22,614 B`), `channel_sentinel.lua` (`22,010 B`), `core_daemon.lua` (`21,688 B`), `gac/tui_view.lua` (`21,351 B`), `outer_loop_controller.lua` (`21,018 B`), `sensor_pipeline.lua` (`20,702 B`), `installer/tui_view.lua` (`20,479 B`), `gps/server.lua` (`19,435 B`), `condition_evaluator.lua` (`19,432 B`) | `0.42~0.77x` 단일 읽기 크기. 단 `installer_app.run`(281 L)과 `gac/tui_view.create`(249 L)는 동일 파일 내 함수 분해만 권고 (`TASK-021`). |

### 4.3 대형 사양서 (7종 >= 80,000 B)

| 사양서 | 규모 (`46,080 B` 배수) | N / F | 판정 | 제안 경계 (영구 경로 불변식 준수) |
|---|---|---:|---|---|
| `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` | 142,631 B / 1,704 L (`3.10x`) | N 높음 / F1=1, F4=1 | **Split-Prereq** | `§3` (`97,078 B`, 68.1%)이 비대하나 `verify_contracts.py:385` `is_master_icd`가 단일 파일 내 전 패킷 존재를 강제. A3 결정으로 물리 분할 보류, 현행 유지하되 배지/이력 정리 대상. |
| `VAS_PROGRAM_SPECIFICATION.md` | 143,328 B / 1,785 L (`3.11x`) | N 높음 / F(Extract)=3 | **Extract** | 제자리 압축: `§8` `28.3 KB` 패킷 Lua 덤프 → ICD 참조 치환 + `§5`/`§10` 코드 덤프(`~15 KB`) 및 `RevHist`(`10.9 KB`) 정리 (`TASK-019`). |
| `AMM_PROGRAM_SPECIFICATION.md` | 113,984 B / 1,017 L (`2.47x`) | N 높음 / F(Extract)=3 | **Extract** | 제자리 압축: `§4` `20.6 KB` ICD 복사본 및 `RevHist` `11.6 KB` 정리 (`TASK-019`). |
| `FCP_PROGRAM_SPECIFICATION.md` | 113,686 B / 1,302 L (`2.47x`) | N 높음 / F(Extract)=3 | **Extract** | 제자리 압축: `§11` `11.3 KB` 구현 의사코드 제거 + `§8` `23.2 KB` ICD 복사본(`867` 공유 shingle) 정리 (`TASK-019`). |
| `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` | 111,434 B / 1,010 L (`2.42x`) | N 보통 / F=1 | **Keep-Justified** | 본문 `33.2%`(`37,015 B`)가 Mermaid 다이어그램이며 `is_diagram` 계약 검증 대상. `RevHist`(`12.8 KB`)만 선택적 정리. |
| `GPS_PROGRAM_SPECIFICATION_AND_ICD.md` | 89,557 B / 1,199 L (`1.94x`) | N 낮음 / F=2 | **Keep** | 섹션 균형(`<= 17.7 KB`), 저변경(`6`커밋), 중복 `2%` 미만. |
| `AMM_MISSION_EDITOR_SPECIFICATION.md` | 83,896 B / 615 L (`1.82x`) | N 낮음 / F=3 | **Keep** | 단일 WebUI 1:1 사양. `verify_all_specs.py` 목록 편입 필요 (`TASK-019`). |

---

## 5. `docking_arm` `[SPEC-ONLY]` 검토 결과

근거 문서: [DOCKING_ARM_SPECIFICATION_AND_ICD.md](../../docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md) (`Approved v1.12.0`, `34,038 B`, `471 L`, `src/0_infra/docking_arm/` 코드 0개).

- **L1 토폴로지 (`Watch`)**: 6종 유선 기계·접촉·엄빌리컬 장치(`dock_bearing_controller` 등)를 구동하므로 `landing_pad`·`runway`와 물리 역할 중복이 없으며 독립 노드 분리가 타당하다. 단, `§4.2`(`L394-443`)는 `Tower ATC(CH 50002)`가 `GAC(Base_sec+1)`를 우회해 암에 직접 명령하도록 그려져 있어 `§2.1`(`L119`)과 충돌하며, `Base+5` 기체별 동적 바인딩을 요구해 다른 시설물(`Base_sec+10+Idx` 단일 전술 채널)과 비대칭이다.
- **L2 프로토콜 (`Consolidate`)**: 활성 패킷 `10`종(`MSG_DOCK_CAPTURE_STAGE`, `MSG_UMBILICAL_STATUS`, `MSG_UNDOCK_CLEARANCE` 등)이 `protocol_contracts.json`에 미등록이며, `amm/facility_client.lua:213-215`가 이미 읽는 `dockingCorridor`·`captureLatchReady`·`armState` 3필드가 `I-5` 가이드 스키마에 누락되었다. 또한 `§3.4` 예제 3종 모두 필수 엔벨로프 `seq`가 빠졌고 `stage` 열거에 `"ABORTED"`가 누락되었다.
- **L4 사양 (`Watch`)**: `RUNWAY`와의 중복률(`containment=0.1135`) 중 `66.2%`가 헤더 보일러플레이트이며 `8/9` 배지가 구버전이다. `TASK-104` 구현 착수 시 `landing_pad`/`runway`와 유사한 9~10모듈(`~50-65 KB`) 규모가 예상되며, 착수 전 위 사양 모순 정합화가 선행되어야 한다.

---

## 6. 아키텍처 불변식 비용 정량화

| 불변식 | 정량 비용 (실측) | 유지/재검토 권고 (P5 결정) |
|---|---|---|
| **멀티 코드베이스 독립 완결** | ① E2E `require_insns` 비중 `14.92%`(`315,800 / 2,116,700`); ② 서브시스템 간 동일·유사 복제 `14`클러스터 `541`추가줄 + `24`유사쌍(단 `400`줄은 `installer.lua` 단일 미러); ③ 복사본 간 논리 분기 3건(`tca` shallow copy, `vas/fcp` Euler, `vas/amm` `save_flight_state`). | **불변식 유지** (A2). 미러 1벌 정리 + 논리 분기 3건만 정합화. |
| **40채널 블록 (`Base+0..39`)** | `AMM`이 `40`개 채널을 모두 개방하나 `src/`·E2E 실사용 오프셋은 `10/40 (25.0%)`(Zone 1: 8개, Zone 2: 2개). Zone 3(`20..39`, 50%)은 E2E 0패킷이며 `AMM` 버그로 `30..39` 차단 상태. | **불변식 유지**. Zone 3 `30..39` 차단 버그만 수정(`TASK-017`). |
| **Zero-Fallback & `ver="1.9.5"`** | 엔벨로프 6필드 JSON 오버헤드 `~100-106 B/pkt`(`220,520 B` 중 `~59.4 KB`, `26.9%`). 잔존 이중키 2곳(`asa/main.lua:106-110`, `amm/nav_engine.lua:136-156`). | **불변식 유지**. |
| **온보드 20Hz 헤드리스** | 온보드 5노드는 5Hz TUI 코루틴/헤드리스 격리 준수. 반면 지상 3종(`GAC`, `LANDING_PAD`, `RUNWAY`)이 20Hz 루프에서 동기 TUI 수행. | **불변식 유지**, 지상 3종을 기준에 맞춰 분리(`TASK-021`). |
| **사양서 영구 경로 & SSOT** | 커밋당 평균 `6.09` 문서 수정, 인라인 버전 배지 `52.9%` 부패, `ICD §3`↔`FCP §8` 간 `805` shingle 중복. | **영구 경로 유지**, 인라인 배지 폐지 + 제자리 `Extract`로 동기화 비용 절감(`TASK-019`). |

---

## 7. Decision Gate(P5) 확정 결과 및 편입된 회귀 가드

| Gate | 확정 결정 | 편입된 회귀 가드 / 반영 내역 |
|---|---|---|
| **A1 (게이트 강도)** | **Warn 우선 편입** (`installer.lua` 미러 불일치만 **Fail**) | `config/audit_baselines.json` + `tools/audit/guard.py` (`python -m tools.audit guard`: 미러 drift Fail, 신규 `>46,080 B` Lua 및 신규 미소비 `requiredKeys` Warn) + `tools/run_e2e_tests.py --check-baseline` (`+25%/+5,000` insns 및 미수신 증가 시 Warn). |
| **A2 (독립 완결 비용)** | 불변식 유지 + `installer.lua` 중복 1벌 및 논리 분기 3건 정합화 | `TASK-018` 등록. |
| **A3 (사양서 체계)** | 인라인 버전 배지 폐지 + `VAS`/`AMM`/`FCP` 제자리 `Extract` + `verify_all_specs` 18종 보완 (ICD §3 물리 분할 보류) | `TASK-019` 등록. |
| **A4 (대형 모듈 분할)** | `46,080 B` 초과 Lua 3종(`amm/main.lua`, `amm/mission_engine.lua`, `installer/manifest.lua`)만 분할/추출 (`amm_mission_editor.html` 보류) | `TASK-020` 등록. |
| **A5 (결함·사문화 정리)** | Zone 3 `30..39` · 누락 계약 · `docking_arm §4.2` · 지상 20Hz TUI · 사문화 핸들러/함수/설정 전수 정리 | `TASK-017`, `TASK-018`, `TASK-019`, `TASK-021`, `TASK-104` 사전 조건 등록. |

---

## 8. 후속 TASK 목록

1. **`TASK-017` [2순위 / 프로토콜·계약 정합화]**: `AMM` Zone 3 `30..39` 차단 해제, `protocol_contracts.json` 5종 E2E + 9종 `src/` 패킷·3 가이드 필드 편입, `amm/main.lua` 사문화 `BASE_PLUS_5` 16핸들러 정리 및 `MSG_RUNWAY_TOUCHDOWN`/`VACATED` 송신 정합화, 미소비 29필드(`requiredKeys` 9 + `optionalKeys` 20) 정리.
2. **`TASK-018` [2순위 / 코드 복제·분기·사문화 정리]**: `src/0_development/installer/installer.lua` 이중 복제본 정리(400줄 제거) 및 `BOOTSTRAP_FILES` 3중 복제 통합, 논리 분기 3건(`tca/config_manager.lua` 얕은 복사, `vas`/`fcp` 오일러 yaw, `vas`/`amm` `save_flight_state` 시그니처) 정합화, 사문화 함수 17종·미사용 설정키 19종 제거.
3. **`TASK-019` [2순위 / 사양 경량화·동기화 비용 절감]**: 18 사양 인라인 피어 버전 배지(`111/210` 부패) 폐지(문서 헤더 + ICD §5.1 SSOT 일원화), `VAS`·`AMM`·`FCP` 제자리 `Extract`(ICD 복사본/의사코드/오래된 이력 정리), `verify_all_specs.py` 18종 편입, `Implemented` 사양 드리프트 6메시지 해소.
4. **`TASK-020` [3순위 / 대형 모듈 분할·추출]**: `46,080 B` 초과 Lua 3종 분할·추출(`amm/main.lua` → `amm_cli`/`cold_boot_recovery`/`infra_rx_router`; `amm/modules/mission_engine.lua` → `mission_validator`/`mission_dispatchers`; `installer/modules/manifest.lua` → `manifest_catalog.lua`).
5. **`TASK-021` [3순위 / 지상 인프라 20Hz TUI 분리·구조 정제]**: `0_infra/{gac,landing_pad,runway}` 20Hz 루프 동기 TUI를 5Hz 코루틴·`headless` 옵션으로 분리하고 `gac`/`landing_pad` 200줄+ 클로저 팩토리(`gac_fsm.create`, `tui_view.create`, `pad_fsm.create`) 내부 분해.
6. **`TASK-104` 선행 정비 (`docking_arm` `[SPEC-ONLY]`)**: `§4.2` `CH 50002` ATC 직접 제어 제거(`GAC` `Base_sec+1` 경유 통일), `Base+5` 기체별 바인딩을 `Base_sec+10+Idx`로 일원화, `§3.4` `seq` 누락·`"ABORTED"` stage 누락 보완.

---

## 9. 부록

### 9.1 원자료 및 검증 도구
- 원자료: `reports/audit_data/2026-11-18/{registry,e2e_profile,static,dupes,specs,split}.json`
- 도구: `python -m tools.audit {registry|static|dupes|specs|split|guard|all}`, `python tools/run_e2e_tests.py --profile <out> [--check-baseline]`

### 9.2 관찰 사항 (Confidence < 80)
- **O-L1-08** (`0_infra/gps/main.lua:1-16`, Conf 75): `shell.run` 16줄 디스패처(`0 ms` CPU) — 런타임 비용 미미.
- **O-L1-09** (`e2e_profile.json`, Conf 70): E2E 내 `require_insns` `14.92%`는 다중 샌드박스 콜드부트 누적이므로 실기체 정상상태 루프 비용과 구분 필요.
- **O-L1-10** (`0_development/fdr`, Conf 75): `4,690.91` insns/call — 수신 전용 격리로 비행 루프 영향 없으나 저사양 서버 대량 JSONL flush 별도 미측정.
- **O-L2-08** (Conf 78): Hangar `+2(facilityInterlock)`, `50001/50002/50004`, `60004`는 E2E 트래픽 0건으로 통합 시나리오 미검증 상태.
- **O-L3-01** (`avionics_sensors.lua:24,29`, Conf 78): docstring 내 `require("avionics_sensors")` 예시가 정적 regex 스캐너에 자기참조로 잡힘.
- **O-L4-06** (`DOCKING_ARM_SPECIFICATION_AND_ICD.md:8`, Conf 75): `Approved` 상태가 `TASK-104` 연기 규칙에 부합하나 `AMM`/`GAC`에 일부 후크가 선반영됨.

### 9.3 P4 교차 검증 교정·기각 로그
1. **E-L1-01 원인 재귀속 (`V-A`)**: 초기 L1 보고서는 `TCA` E2E `114 ms`(`40.86%`) 원인을 20Hz `actuator_adapter` 6면 루프/`push_log`로 지목했으나, `V-A` 스위트 격리 재현 결과 `test_e2e_3node_se3_closed_loop.lua`(200회 호출)에서 `TCA`는 `0 ms`(`86,000` insns)였고 `test_e2e_ota_deploy_rollback.lua`(64회 호출)에서 `112 ms`가 집중 발생해 `ota_agent`의 호스트 NTFS 파일 I/O가 `os.epoch("utc")`에 잡힌 것으로 교정됨.
2. **E-L3-02 개수 교정 (`V-A`)**: `landing_pad`↔`runway` 유사 복제 쌍 수를 `9`쌍에서 `11`쌍(`0.816..0.974`)으로 교정.
3. **E-L2-02/03 분류 정정 (`V-B`)**: `amm/main.lua` `BASE_PLUS_5_INFRA_RESPONSES` 내 송신자 0인 미계약 사문화 키를 `14`개에서 `16`개(`12` 화이트리스트 전용 + `4` 핸들러 포함)로 교정하고, `MSG_DOCK_CAPTURE_STAGE`/`MSG_UMBILICAL_STATUS`는 활성 송신자가 아닌 `amm/main.lua` 수신 대기 키임을 확정.
4. **동적 디스패치 오탐 기각 (`V-A`·`R-L3`)**: `static.json` 미참조 함수 후보 중 `amm/main.lua:463` `pbit` (`CLI_HANDLERS`), `amm/c2_arbiter.lua:505` `ESTOP` (`PILOT_ACTION_HANDLERS`), `test_refs >= 1` 공개 API 34건은 오탐으로 기각.
