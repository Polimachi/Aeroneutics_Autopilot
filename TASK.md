# Create_Aeroneutics — Task Management & Roadmap (`TASK.md`)

> **문서 상태**: 활성 (Living Roadmap)  
> **최종 갱신일**: 2026-11-07  
> **현재 단계**: **Phase 0** (기체 통신 40채널 개편 & 단위 하네스 파이프라인 구축 완료 → 기체 런타임 코드 동기화 대기)

---

## 📌 에이전트 작업 지침 (Agent Protocol)

- **계획 수립 시**: 작업 계획(/plan 등)이 확정되면 본 파일의 당면 과제 또는 백로그에 신규 항목(`[ ]`)을 등록한다.
- **작업 착수 시**: 진행 중인 태스크를 `[-]` (진행 중)으로 전환한다.
- **작업 완료 시**: 완료 항목을 `[x]` (완료)로 변경하고 완료 일자를 기록하며, 완료 후 제시된 추가 작업(후속 과제)을 즉시 본 파일에 등록한다.
- **완료 이력 보존 상한**: 완료된 작업 이력은 **최근 30개까지만 유지**하며, 30개를 초과하는 과거 완료 항목은 오래된 순서대로 정리(Prune)한다.
- **유저 호출 방법**:
  - `TASK.md 확인하고 다음 남은 작업 진행해줘`
  - `TASK.md의 TASK-001 작업 계획 세워줘`
  - `TASK.md 상태 점검해줘`

---

## 📁 0. 디렉토리 구조 일치 현황 (Directory Alignment SSOT)

프로젝트 내 모든 사양서(`docs/specs/`), 구현 코드(`src/`), 단위 테스트(`tests/`)는 도메인 계층 구조를 1:1로 일치시킵니다:

| 계층 (Layer) | 도메인 디렉토리 | 사양서 위치 (`docs/specs/`) | 구현 코드 위치 (`src/`) | 단위 테스트 위치 (`tests/`) |
| :--- | :--- | :--- | :--- | :--- |
| **0_development** | `alignment` | `docs/specs/0_development/alignment/` | `src/0_development/alignment/` | `tests/0_development/alignment/` |
| **0_infra** | `docking_arm` | `docs/specs/0_infra/docking_arm/` | `src/0_infra/docking_arm/` | *(연기 / 보류)* |
| | `gac` | `docs/specs/0_infra/gac/` | `src/0_infra/gac/` | *(Phase 1 구축 예정)* |
| | `gps` | `docs/specs/0_infra/gps/` | `src/0_infra/gps/` | `tests/0_infra/gps/` |
| | `landing_pad` | `docs/specs/0_infra/landing_pad/` | `src/0_infra/landing_pad/` | *(Phase 1 구축 예정)* |
| | `runway` | `docs/specs/0_infra/runway/` | `src/0_infra/runway/` | *(연기 / 보류)* |
| **1_control** | `asa` | `docs/specs/1_control/asa/` | `src/1_control/asa/` | `tests/1_control/asa/` |
| | `tca` | `docs/specs/1_control/tca/` | `src/1_control/tca/` | `tests/1_control/tca/` |
| | `vas` | `docs/specs/1_control/vas/` | `src/1_control/vas/` | `tests/1_control/vas/` |
| **2_guidance** | `fcp` | `docs/specs/2_guidance/fcp/` | `src/2_guidance/fcp/` | `tests/2_guidance/fcp/` |
| **3_planning** | *(경로 계획)* | `docs/specs/3_planning/` | `src/3_planning/` | *(Phase 2 구축 예정)* |
| **4_mission** | *(편대 미션)* | `docs/specs/4_mission/` | `src/4_mission/` | *(Phase 2 구축 예정)* |
| **시스템 전역** | 마스터 ICD / 아키텍처 | `docs/system/` | — | — |
| **하네스/도구** | 단위 테스트 러너/모킹 | — | `harness/unit/` | `tests/harness/`, `tools/run_unit_tests.py` |

---

## 🚀 1. 활성 당면 과제 (Active Immediate Tasks — Phase 0)

현재 기체 통신 40채널($BW=40$) 사양서 개편 및 유닛 테스트 하네스 구축이 완료되었으며, 실제 Lua 코드베이스 런타임 동기화가 필요합니다.

- [ ] **TASK-001: 기체 5대 핵심 모듈(`src/`) 통신 채널·Zone 런타임 코드 동기화**
  - **목표**: $BW=40$ ($Base = 10000 + (N-1) \times 40$) 및 4대 Zone(1: 비행, 2: 구동계, 3: 탑재체, 4: 편대)을 `src/` 코드에 반영
  - **계획서**: `docs/superpowers/plans/2026-11-07-task-001-runtime-40ch-sync.md`
  - [ ] **TASK-001-1**: VAS (`src/1_control/vas/`) 채널 상수, 패킷 구조, Zone 동기화
  - [ ] **TASK-001-2**: TCA (`src/1_control/tca/`) 채널 상수, 구동계 제어 링크 동기화
  - [ ] **TASK-001-3**: FCP (`src/2_guidance/fcp/`) 채널 상수, 텔레메트리/유도 링크 동기화
  - [ ] **TASK-001-4**: Alignment (`src/0_development/alignment/`) 채널 및 보정 데이터 링크 동기화
  - [ ] **TASK-001-5**: GPS (`src/0_infra/gps/`) 인프라 채널 동기화

- [ ] **TASK-002: 코드베이스 검증용 테스트 구축 및 하네스 루프 연동 조정**
  - **목표**: 40채널 통신 및 Zone 패킷 규격이 반영된 코드베이스 동작을 검증하는 단위 테스트를 구축하고 하네스 실행 루프에 통합 조정
  - [ ] **TASK-002-1**: 코드베이스 검증용 테스트 구축 (5대 핵심 모듈 40채널·Zone 통신 검증 테스트 케이스 작성)
  - [ ] **TASK-002-2**: 코드베이스 검증용 테스트를 하네스 루프에 포함시켜 조정 (테스트 러너 루프 연동 및 타임아웃/명령 계측 튜닝)

- [ ] **TASK-003: 런타임 코드 검증 및 사양서 상태 전이 (`Approved` → `Implemented`)**
  - **목표**: `TASK-001`·`TASK-002` 완료 후 런타임 코드 동작 검증(`python tools/run_unit_tests.py`) 통과 증거를 확보하고, Phase 0 구현 완료 5대 사양서(`VAS`, `TCA`, `FCP`, `Alignment`, `GPS`) 메타데이터 표의 상태를 `Implemented`로 인플레이스 전이 (영구 경로 불변 원칙 준수, 미구현/연기/전역 7종은 `Approved` 유지)
  - [ ] **TASK-003-0**: `TASK-001`·`TASK-002` 완료 여부 및 `src/`·`tests/` 레거시 20채널 상수 잔존 0건 선행 감사
  - [ ] **TASK-003-1**: 하네스 자체 회귀(`unittest tests/harness`) 및 멀티 타겟 단위 테스트(`python tools/run_unit_tests.py --require-tests --clean-orphans`) 전수 통과 확인
  - [ ] **TASK-003-2**: 구현 완료 5대 사양서 상단 메타데이터 `문서 상태`를 `Implemented`로 갱신 및 `최종 수정일` 동기화
  - [ ] **TASK-003-3**: `python scratch/verify_all_specs.py` 사후 무결성 스캔 통과(`0 Errors, 0 Warnings`) 및 컨텍스트 동기화

- [ ] **TASK-004: 원격 저장소(`origin main`) 푸시 및 인증 완료**
  - **목표**: 로컬 커밋 내역을 원격 GitHub 저장소에 안전하게 푸시 (`git` 미인식 시 `"C:\Program Files\Git\cmd\git.exe"` 호출)
  - [ ] **TASK-004-1**: 사용자 인증(PAT/SSH) 상태 확인 및 푸시 승인 후 실행

- [ ] **TASK-005: 통합 코드베이스 설치 프로그램(Unified Installer) 구축 및 구버전 통폐합**
  - **목표**: 전 도메인 코드베이스 TUI 원격 다운로더 구축, `/.version.json` 메타데이터 및 설정 보존 마이그레이션 연동, 구버전 개별 인스톨러(`gps/installer.lua` 등) Zero-Fallback 폐기
  - **계획서**: `docs/superpowers/plans/2026-11-07-unified-codebase-installer.md`
  - [ ] **TASK-005-1**: 선언적 매니페스트(`manifest.lua`) 및 버전 레지스트리(`version_registry.lua`) 구축
  - [ ] **TASK-005-2**: 설정 보존 마이그레이션(`migration_engine.lua`) 및 멀티부트 후크(`startup_generator.lua`) 구축
  - [ ] **TASK-005-3**: HTTP 원자적 다운로더(`downloader.lua`) 구축 및 네트워크 장애 격리
  - [ ] **TASK-005-4**: 터미널 TUI(`tui_view.lua`) 및 메인 앱(`installer_app.lua`) 구축
  - [ ] **TASK-005-5**: 루트 경량 부트스트래퍼(`installer.lua`) 구축
  - [ ] **TASK-005-6**: 구버전 개별 인스톨러(`gps/installer.lua` 등) Zero-Fallback 삭제 및 사양서 개정
  - [ ] **TASK-005-7**: 단위 테스트 하네스 전수 실행(`tools/run_unit_tests.py`) 및 회귀 검증

---

## 📋 2. 예정 백로그 (Planned Backlog — Phase 1 & 2)

- [ ] **TASK-101: GAC (Ground Air Traffic Controller) 구현** (`src/0_infra/gac/`)
  - 지상 항공교통 관제탑 및 슬롯 배정 알고리즘 구현
- [ ] **TASK-102: Landing Pad 지상 착륙 패드 제어기 구현** (`src/0_infra/landing_pad/`)
  - 착륙 패드 유도 신호 송출 및 비행체 접안 제어
- [ ] **TASK-105: ASA (Automated Spatial Alignment) 센서 어레이 구현** (`src/1_control/asa/`)
  - 공간 정렬 센서 융합 및 상대 좌표 계산
- [ ] **TASK-201: 경로 계획 모듈 (`src/3_planning/`) 설계 및 구현**
  - 3차원 장애물 회피 및 비행 웨이포인트 스케줄링
- [ ] **TASK-202: 편대 미션 오케스트레이터 (`src/4_mission/`) 설계 및 구현**
  - 다중 기체 편대 비행 및 임무 분배 총괄

### ⏸️ 연기·보류 과제 (Deferred / On-Hold)

- [ ] **[연기] TASK-103: Runway 활주로 제어기 구현** (`src/0_infra/runway/`)
  - 활주로 유도등, 진입 정렬 비콘 및 이착륙 통제 (일정 연기 — 사양서 `Approved` 유지)
- [ ] **[연기] TASK-104: Docking Arm 결합 암 제어기 구현** (`src/0_infra/docking_arm/`)
  - 기체 도킹 고정 및 연료/자원 보급 시퀀스 (일정 연기 — 사양서 `Approved` 유지)

---

## ✅ 3. 완료된 작업 이력 (Completed Tasks Archive — 최근 30개 유지)

- [x] **TASK-P0-01: 기체 통신 40채널($BW=40$) ICD 전면 개편** (완료일: 2026-11-07)
  - `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` 및 `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` 4대 Zone 규격 반영
- [x] **TASK-P0-02: 12대 핵심 사양서 전수 리팩토링 및 10종 승격** (완료일: 2026-11-07)
  - 40채널 대역폭, Zero-Fallback 원칙, `ion_thruster` 호환성, 상대 링크 정합성 반영
- [x] **TASK-P0-03: 사양서 정합성 무결성 검증기 통과** (완료일: 2026-11-07)
  - `scratch/verify_all_specs.py` 전수 검증 (0 Errors, 0 Warnings)
- [x] **TASK-P0-04: 사양서 생명주기 관리 체계 문서 내부화 및 영구 단일 계층 개편** (완료일: 2026-11-07)
  - `docs/specs/{approved,drafts,implemented,archived}/` 디렉토리 분리 제거 및 도메인 직하 단일 계층 평탄화
  - 12대 규격서 상단 5대 필수 항목 표준 메타데이터 요약 표 삽입 (`Status`, `Version`, `Date`, `Source`, `Domain`)
  - `specification-lifecycle-manager` 스킬, `skill-workflows.md`, `docs/specs/README.md`, `scratch/verify_all_specs.py` 전수 동기화 및 무결성 검증 통과 (0 Errors, 0 Warnings)
- [x] **TASK-P0-05: CC:Tweaked 하네스 및 단위 테스트 검증 파이프라인 구축** (완료일: 2026-11-07)
  - Lua 5.2 문법/금지 모드 정적 분석기(`scratch/validate_lua_syntax.py`) 작성
  - CC:Tweaked Peripheral & Rednet Mock 프레임워크 구축 (`harness/unit/`)
  - 로컬/게스트 테스트 러너 CLI 구축 (`tools/run_unit_tests.py`)
  - 6대 활성 코드베이스(`alignment`, `gps`, `asa`, `tca`, `vas`, `sas`) 파일럿 단위 테스트 슈트 구축 및 전수 통과 (19/19 tests PASS)
- [x] **TASK-P0-06: SAS → FCP(Flight Control Program) 전면 명칭 개정 및 디렉토리·식별자 일체화** (완료일: 2026-11-07)
  - 디렉토리/파일명(`docs/specs/2_guidance/fcp/`, `src/2_guidance/fcp/`, `tests/2_guidance/fcp/`) 및 런타임 식별자(`source`/`activeSource`='FCP', `hardwareUuid`='FCP-04'), 사양서 12종 및 마스터 ICD 동기화, 단위 테스트 6/6 PASS
