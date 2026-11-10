# Workspace Root Memory Archive

본 문서는 `Create_Aeroneutics` 루트 및 하네스 기반 구조의 주요 의사결정 이력을 최신순(ISO 날짜)으로 기록하는 온디맨드 아카이브입니다.

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
