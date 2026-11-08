# Create_Aeroneutics — Task Management & Roadmap (`TASK.md`)

> **문서 상태**: 활성 (Living Roadmap)  
> **최종 갱신일**: 2026-11-08  
> **현재 단계**: **Phase 0** (기체 5대 핵심 모듈 40채널 런타임 동기화 및 단위·하네스 테스트 검증 완료 → 사양서 정합성 마무리 및 `Implemented` 상태 전이 대기)

---

## 📌 에이전트 작업 지침 (Agent Protocol)

- **계획 수립 시**: 작업 계획(`/plan` 등)이 확정되면 본 파일의 당면 과제 또는 백로그에 신규 항목(`[ ]`)을 등록한다.
- **작업 착수 시**: 진행 중인 태스크를 `[-]` (진행 중)으로 전환한다.
- **작업 완료 시**: 완료 항목을 `[x]` (완료)로 변경해 `## 3. 완료된 작업 이력` 상단으로 이동·기록하고, 도출된 후속 과제를 즉시 본 파일에 등록한다.
- **완료 이력 보존 상한**: 완료된 작업 이력은 **최근 30개까지만 유지**하며, 30개를 초과하는 과거 완료 항목은 오래된 순서대로 정리(Prune)한다.
- **도메인 경로 매핑 기준**: `docs/specs/`, `src/`, `tests/` 간 1:1 도메인 계층 구조는 [README.md](README.md)의 디렉토리 레이아웃을 따른다.
- **유저 호출 예시**:
  - `TASK.md 확인하고 다음 남은 작업 진행해줘`
  - `TASK.md의 TASK-003 작업 계획 세워줘`
  - `TASK.md 상태 점검해줘`

---

## 🚀 1. 활성 당면 과제 (Active Immediate Tasks — Phase 0)

- [ ] **TASK-003: 런타임 코드 검증 및 사양서 상태 전이 (`Approved` → `Implemented`)**
  - **목표**: 런타임 동작 검증 증거를 최종 확인하고, 워킹 트리 내 미커밋 사양서 변경분을 정리한 뒤 Phase 0 구현 완료 5대 사양서(`VAS`, `TCA`, `FCP`, `Alignment`, `GPS`) 메타데이터 표의 상태를 `Implemented`로 인플레이스 전이 (영구 경로 불변 원칙 준수, 미구현/연기/전역 7종은 `Approved` 유지)
  - **계획서**: `docs/superpowers/plans/2026-11-08-task-003-spec-status-transition-to-implemented.md`
  - [ ] **TASK-003-0**: 워킹 트리 미커밋 사양서 4종(`AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`, `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`, `ALIGNMENT_PROGRAM_SPECIFICATION.md`, `TCA_PROGRAM_SPECIFICATION.md` — 중복 `Revision History` 행 정리 포함) 검토·반영 및 `src/`·`tests/` 레거시 20채널 상수 잔존 0건 선행 감사
  - [ ] **TASK-003-1**: 하네스 자체 회귀(`python -m unittest discover -s tests/harness -p "test_*.py"`) 및 멀티 타겟 단위 테스트(`python tools/run_unit_tests.py --require-tests --clean-orphans`) 전수 통과 확인
  - [ ] **TASK-003-2**: 구현 완료 5대 사양서 상단 메타데이터 `문서 상태`를 `Implemented`로 갱신 및 `최종 수정일` 동기화
  - [ ] **TASK-003-3**: `python scratch/verify_all_specs.py` 사후 무결성 스캔 통과(`0 Errors, 0 Warnings`) 및 컨텍스트 동기화

- [ ] **TASK-004: 원격 저장소(`origin main`) 푸시 및 인증 완료**
  - **목표**: 로컬 커밋 내역을 원격 GitHub 저장소에 푸시 (`git` 미인식 시 `"C:\Program Files\Git\cmd\git.exe"` 호출)
  - [ ] **TASK-004-1**: 사용자 인증(PAT/SSH) 상태 확인 및 명시적 푸시 승인 후 실행

- [ ] **TASK-005: 통합 코드베이스 설치 프로그램(Unified Installer) 구축 및 구버전 통폐합**
  - **목표**: 3대 배포(화면 직접 업로드 `/installer.lua`, 플로피 디스크 `/disk/`, HTTP `wget run`) 지원, GitHub/Google Drive 듀얼 다운로드 원천, `/.version.json` 메타데이터 및 설정 보존 마이그레이션 연동, 구버전 개별 인스톨러(`gps/installer.lua` 등) Zero-Fallback 폐기
  - **참조 계획서**: `docs/superpowers/plans/2026-11-07-unified-codebase-installer.md`
  - [ ] **TASK-005-1**: 선언적 매니페스트(`manifest.lua`, 듀얼 원천) 및 버전 레지스트리(`version_registry.lua`) 구축
  - [ ] **TASK-005-2**: 설정 보존 마이그레이션(`migration_engine.lua`) 및 본체 루트 멀티부트 후크(`startup_generator.lua`) 구축
  - [ ] **TASK-005-3**: HTTP 원자적 다운로더(`downloader.lua`, GitHub & Google Drive 302 리다이렉트 지원) 구축
  - [ ] **TASK-005-4**: 터미널 TUI(`tui_view.lua`, 소스 전환 `[S]`) 및 메인 앱(`installer_app.lua`) 구축
  - [ ] **TASK-005-5**: 3대 배포(화면 직접 업로드·플로피·원격) 지원 루트 부트스트래퍼(`installer.lua`) 구축
  - [ ] **TASK-005-6**: 구버전 개별 인스톨러(`gps/installer.lua` 등) Zero-Fallback 삭제 및 사양서 개정
  - [ ] **TASK-005-7**: 단위 테스트 하네스 전수 실행(`tools/run_unit_tests.py`) 및 회귀 검증

- [ ] **TASK-006: 검증 스크립트 정식 도구화(`scratch/` → `tools/`) 및 하위 문서 구 경로 정리**
  - **목표**: 상시 사용하는 검증 스크립트를 `tools/`로 정식 이관해 일회성 마이그레이션 스크립트와 분리하고, 하위 모듈 문서의 폐기 경로 잔재를 제거
  - [ ] **TASK-006-1**: `verify_all_specs.py`·`validate_lua_syntax.py`의 `tools/` 이관, 일회성 `scratch/` 스크립트 정리 및 루트 문서 표준 명령 경로 동기화
  - [ ] **TASK-006-2**: `src/1_control/asa/README.md` 내 폐기된 `docs/specs/approved/...` 링크를 영구 단일 경로(`docs/specs/1_control/asa/...`)로 수정 및 전수 상대 링크 점검

---

## 📋 2. 예정 백로그 (Planned Backlog — Phase 1 & 2)

- [ ] **TASK-101: GAC (Ground Area Controller) 지상 구역 관제사 구현** (`src/0_infra/gac/`)
  - 섹터 대표 비콘(`CH 50003`), 로컬 백본(`Base_sec+1`) 및 다속성 패드 슬롯 배정·복행 중재 구현
- [ ] **TASK-102: Landing Pad 지상 착륙 패드 제어기 구현** (`src/0_infra/landing_pad/`)
  - 가상 좌표 비콘, 동역학 요동 인터록 및 전술 유도 채널(`Base_sec+10+Idx`) 스트리밍 구현
- [ ] **TASK-105: ASA (Aerodynamic Surface Adapter) 공력 조종면·플랩 분산 구동기 본 구현 완성** (`src/1_control/asa/`)
  - 기초 모듈 및 단위 테스트(`3/3 PASS`)를 기반으로 `Base+11` 20Hz 구동 루프, `peripheral.find` 동적 바인딩 및 300ms Safe Glide Trim 본체 엔트리 완성
- [ ] **TASK-106: Cockpit MFD (Node 03) 조종석 다기능 계기판 및 ACRO 입력 단말 구현**
  - 평시 5Hz(`FCP`) / ACRO 20Hz(`VAS`) `Base+3` HUD 렌더링 및 `Base+0`·`Base+1` C2/비상 선점 송출 구현
- [ ] **TASK-107: GCS 채널 관리자(`CH 50000`) 및 지상 비행 지휘 콘솔 구현**
  - 기체 40채널 블록(`10000~49999`, $N=1\sim 1000$) 스티키 배정·충돌 중재 및 원격 C2 콘솔 구현
- [ ] **TASK-108: Tower ATC (Sector 0, `CH 50001/50002`) 광역 항공교통 관제 노드 구현**
  - 광역 공역 진입/이탈 스케줄링 및 섹터 `GAC` 핸드오프 프로토콜 구현
- [ ] **TASK-109: 멀티노드 종단간(E2E) 패킷 시퀀스 통합 시뮬레이션 테스트 구축**
  - 복수 노드(`FCP`↔`VAS`↔`TCA`/`ASA`, `Alignment` 교정 세션 등) 간 다중 틱 교환 시나리오 검증 확장
- [ ] **TASK-201: 경로 계획 모듈 (`src/3_planning/`) 설계 및 구현**
  - 3차원 장애물 회피 및 비행 웨이포인트 스케줄링
- [ ] **TASK-202: 편대 미션 오케스트레이터 (`src/4_mission/`) 설계 및 구현**
  - Zone 4(`Base+30~39`) 기반 다중 기체 편대 비행 및 임무 분배 총괄

### ⏸️ 연기·보류 과제 (Deferred / On-Hold)

- [ ] **[연기] TASK-103: Runway 활주로 제어기 구현** (`src/0_infra/runway/`)
  - 활주로 유도등, 가상 ILS 및 유도로 `GAC` 연동 관제 (일정 연기 — 사양서 `Approved` 유지)
- [ ] **[연기] TASK-104: Docking Arm 결합 암 제어기 구현** (`src/0_infra/docking_arm/`)
  - 2축 로봇 암 포획·인입 및 엄빌리컬 보급 시퀀스 (일정 연기 — 사양서 `Approved` 유지)

---

## ✅ 3. 완료된 작업 이력 (Completed Tasks Archive — 최근 30개 유지)

- [x] **TASK-002: 코드베이스 40채널·Zone 단위 테스트 및 하네스 루프 통합 검증** (완료일: 2026-11-08)
  - 6개 활성 타겟(`alignment` 7, `gps` 9, `asa` 3, `tca` 7, `vas` 7, `fcp` 9) 전수 `42/42 PASS` 및 하네스 Python 회귀 테스트 `14/14 PASS`로 통합 종결 (멀티노드 E2E 시나리오는 `TASK-109`로 분리)
- [x] **TASK-001: 기체 5대 핵심 모듈(`src/`) 통신 채널·Zone 런타임 코드 동기화** (완료일: 2026-11-08)
  - $BW=40$ ($Base = 10000 + (N-1) \times 40$) 및 4대 Zone 규격을 `VAS`(`16b8390`, `1db52ed`), `TCA`(`e6be320`, `0f29c5b`), `FCP`(`9da4301`, `34fc867`, `4c1db74`), `Alignment`(`f52cb11`, `c5e8b5a`), `GPS`(`8da2d09`)에 반영 완료 (단위 테스트 `42/42 PASS`, 문법 정적 분석 `7/7 PASS`)
- [x] **TASK-P0-06: SAS → FCP(Flight Control Program) 전면 명칭 개정 및 디렉토리·식별자 일체화** (완료일: 2026-11-07)
  - 디렉토리/파일명(`docs/specs/2_guidance/fcp/`, `src/2_guidance/fcp/`, `tests/2_guidance/fcp/`) 및 런타임 식별자(`source`/`activeSource`='FCP', `hardwareUuid`='FCP-04'), 사양서 12종 및 마스터 ICD 동기화, 단위 테스트 6/6 PASS
- [x] **TASK-P0-05: CC:Tweaked 하네스 및 단위 테스트 검증 파이프라인 구축** (완료일: 2026-11-07)
  - Lua 5.2 문법/금지 모드 정적 분석기(`scratch/validate_lua_syntax.py`), CraftOS-PC 헤드리스 세션·Mock 프레임워크(`harness/unit/`), 멀티 타겟 테스트 러너 CLI(`tools/run_unit_tests.py`) 및 6대 코드베이스 초기 테스트 슈트 구축
- [x] **TASK-P0-04: 사양서 생명주기 관리 체계 문서 내부화 및 영구 단일 계층 개편** (완료일: 2026-11-07)
  - `docs/specs/{approved,drafts,implemented,archived}/` 디렉토리 분리 제거 및 도메인 직하 단일 계층 평탄화, 12대 규격서 상단 5대 필수 항목 메타데이터 표 도입, `specification-lifecycle-manager`·`skill-workflows.md`·`verify_all_specs.py` 동기화
- [x] **TASK-P0-03: 사양서 정합성 무결성 검증기 통과** (완료일: 2026-11-07)
  - `scratch/verify_all_specs.py` 전수 검증 (0 Errors, 0 Warnings)
- [x] **TASK-P0-02: 12대 핵심 사양서 전수 리팩토링 및 10종 승격** (완료일: 2026-11-07)
  - 40채널 대역폭, Zero-Fallback 원칙, `ion_thruster` 호환성, 상대 링크 정합성 반영
- [x] **TASK-P0-01: 기체 통신 40채널($BW=40$) ICD 전면 개편** (완료일: 2026-11-07)
  - `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` 및 `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` 4대 Zone 규격 반영
