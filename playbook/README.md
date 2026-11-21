# Create_Aeroneutics — 통합 인게임 운용 플레이북 (Operations Playbook Index)

> **문서 성격**: 인게임 빌더·정비사·관제사·조종사를 위한 실전 설치·배선·채널·조작 매뉴얼 (Operations Guide)  
> **구조 원칙**: `src/`, `docs/specs/`, `tests/`와 동일한 1:1 도메인 계층 구조(`playbook/<domain>/<subsystem>.md`)를 유지합니다.  
> **정적 검증**: `python tools/verify_playbooks.py` (인가 목록·7대 고정 섹션·상대 링크·금지어·Rule 10 일괄 검사)

---

## 1. 표준 7대 섹션 규격 (Standard 7-Section Template)

모든 인가된 플레이북 문서는 아래 7개 섹션 헤딩을 **번호와 순서를 고정하여(`1` → `7`)** 빠짐없이 포함해야 합니다:

1. `## 1. 서브시스템 개요 및 역할 (Overview & Role)` — 역할, 생태계 내 위치, 핵심 기능 요약
2. `## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)` — 컴퓨터 등급, 모뎀, 센서, 유/무선 결선 요구사항
3. `## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)` — 인게임 블록 배치 방향, 축 규약, 주의사항
4. `## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)` — 글로벌/섹터/기체 40채널 공식 및 송수신 채널표
5. `## 5. 소프트웨어 설치 방법 (Installation)` — 통합 인스톨러(`installer.lua`), OTA, 또는 호스트 실행 방법
6. `## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)` — 주요 JSON 설정 경로, 기본값 및 핵심 튜닝 키
7. `## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)` — TUI 단축키, CLI 명령어, 자주 겪는 증상과 해결법

---

## 2. 인게임 전체 구축 및 운용 권장 순서 (5-Stage Commissioning Flow)

1. **1단계 — 지상 인프라 구축 (`0_infra`)**: [GPS](0_infra/gps.md) 위성군(중앙 서버 + 4기 이상 비공면 노드) → [GAC](0_infra/gac.md) 섹터 관제소 → [Landing Pad](0_infra/landing_pad.md) / [Runway](0_infra/runway.md) → [GCS](0_infra/gcs.md) 중앙 관제소 순으로 배치·가동합니다.
2. **2단계 — 기체 조립 및 소프트웨어 배포 (`0_development`, `1_control`, `2_guidance`, `3_planning`)**: 기체에 [Sensors](0_development/sensors.md) 규격에 맞게 CC:Avionics 센서와 추진기를 부착하고, [Installer](0_development/installer.md)로 온보드 컴퓨터([VAS](1_control/vas.md), [TCA](1_control/tca.md), [FCP](2_guidance/fcp.md), [AMM](3_planning/amm.md))를 설치합니다. 이후 격납고 업데이트는 [OTA](0_development/ota.md)를 사용합니다.
3. **3단계 — 격납고 동역학 교정 (`0_development/alignment`)**: [Alignment](0_development/alignment.md) 베이에서 기체 토폴로지와 6-DoF OLS 동역학을 식별하고 `MSG_PROFILE_SYNC`로 프로파일을 동기화합니다.
4. **4단계 — 임무 계획 및 비행 운용 (`3_planning`)**: 호스트 PC에서 [AMM Mission Editor](3_planning/amm_mission_editor.md)로 임무를 작성(또는 Live Push)하고, 조종석 [AMM](3_planning/amm.md)에서 `PBIT` 점검 후 이륙·자율 비행을 집행합니다.
5. **5단계 — 블랙박스 수집 및 튜닝 (`0_development/fdr`)**: 비행 중 [FDR](0_development/fdr.md)로 텔레메트리를 수신·기록하고, 호스트 오프라인 분석기(`tools/analyze_flight_log.py`)로 PID/추력 포화를 프로파일링합니다.

---

## 3. 도메인별 인가 플레이북 인덱스 (16종 Active Playbooks)

### 0_development — 개발 · 교정 · 배포 · 센서

| 서브시스템 | 플레이북 | 관련 사양서 / 문서 | 주요 진입점 / 대상 도구 |
| :--- | :--- | :--- | :--- |
| **Alignment** | [alignment.md](0_development/alignment.md) | [ALIGNMENT_PROGRAM_SPECIFICATION.md](../docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md) | `src/0_development/alignment/main.lua` |
| **FDR & Profiler** | [fdr.md](0_development/fdr.md) | [FDR_PROGRAM_SPECIFICATION.md](../docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md) | `src/0_development/fdr/main.lua`, `tools/analyze_flight_log.py` |
| **Unified Installer** | [installer.md](0_development/installer.md) | [INSTALLER_PROGRAM_SPECIFICATION.md](../docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md) | `installer.lua`, `tools/sync_gdrive.py` |
| **Wireless OTA** | [ota.md](0_development/ota.md) | [OTA_PROGRAM_SPECIFICATION.md](../docs/specs/0_development/ota/OTA_PROGRAM_SPECIFICATION.md) | `src/0_development/ota/main.lua`, `/lib/ota_agent.lua` |
| **Avionics Sensors** | [sensors.md](0_development/sensors.md) | [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md) | `src/0_development/sensors/avionics_sensors.lua` (`/lib/avionics_sensors.lua`) |

### 0_infra — 지상 관제 및 비행장 인프라

| 서브시스템 | 플레이북 | 관련 사양서 / 문서 | 주요 진입점 / 대상 도구 |
| :--- | :--- | :--- | :--- |
| **GPS Cluster** | [gps.md](0_infra/gps.md) | [GPS_PROGRAM_SPECIFICATION_AND_ICD.md](../docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md) | `src/0_infra/gps/{server,node,client_entry}.lua` |
| **GCS & Live Bridge** | [gcs.md](0_infra/gcs.md) | [GCS_PROGRAM_SPECIFICATION_AND_ICD.md](../docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md) | `src/0_infra/gcs/main.lua`, `tools/gcs_live_bridge.py` |
| **GAC (Sector ATC)** | [gac.md](0_infra/gac.md) | [GAC_PROGRAM_SPECIFICATION_AND_ICD.md](../docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md) | `src/0_infra/gac/main.lua` |
| **Landing Pad** | [landing_pad.md](0_infra/landing_pad.md) | [LANDING_PAD_SPECIFICATION_AND_ICD.md](../docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md) | `src/0_infra/landing_pad/main.lua` |
| **Pocket PDA** | [pocket_pda.md](0_infra/pocket_pda.md) | [POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md](../docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md) | `src/0_infra/pocket_pda/main.lua` |
| **Runway** | [runway.md](0_infra/runway.md) | [RUNWAY_SPECIFICATION_AND_ICD.md](../docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md) | `src/0_infra/runway/main.lua` |

### 1_control & 2_guidance — 온보드 비행 제어 및 외루프 유도

| 서브시스템 | 플레이북 | 관련 사양서 / 문서 | 주요 진입점 / 대상 도구 |
| :--- | :--- | :--- | :--- |
| **VAS (Inner Loop)** | [vas.md](1_control/vas.md) | [VAS_PROGRAM_SPECIFICATION.md](../docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md) | `src/1_control/vas/main.lua` |
| **TCA (Thrusters)** | [tca.md](1_control/tca.md) | [TCA_PROGRAM_SPECIFICATION.md](../docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md) | `src/1_control/tca/main.lua`, `tca_setup.lua` |
| **FCP (Outer Loop)** | [fcp.md](2_guidance/fcp.md) | [FCP_PROGRAM_SPECIFICATION.md](../docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md) | `src/2_guidance/fcp/main.lua` |

### 3_planning — 임무 관리 및 미션 에디터

| 서브시스템 | 플레이북 | 관련 사양서 / 문서 | 주요 진입점 / 대상 도구 |
| :--- | :--- | :--- | :--- |
| **AMM (MFD Terminal)** | [amm.md](3_planning/amm.md) | [AMM_PROGRAM_SPECIFICATION.md](../docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md) | `src/3_planning/amm/main.lua` |
| **AMM Mission Editor** | [amm_mission_editor.md](3_planning/amm_mission_editor.md) | [AMM_MISSION_EDITOR_SPECIFICATION.md](../docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md) | `tools/amm_mission_editor.html`, `tools/gcs_live_bridge.py` |

---

## 4. 확장 예약 슬롯 및 미인가 파일 차단 정책

`tools/verify_playbooks.py`는 아래 예약 슬롯에 대한 구현이 완료되어 인가 목록(`REQUIRED_PLAYBOOKS`)에 정식 편입되기 전까지 미등록 `.md` 파일 생성을 실패로 차단합니다:

- `playbook/1_control/asa.md` — `TASK-105` / `TASK-210` (ASA 공력 조종면 구동기 본 구현) 완료 후 편입 예정
- `playbook/0_infra/docking_arm.md` — `TASK-104` (Docking Arm, 일정 연기) 구현 완료 후 편입 예정
- `playbook/0_infra/tower_atc.md` — `TASK-108` (Tower ATC, 일정 연기) 구현 완료 후 편입 예정

### 검증 실행

```bash
python tools/verify_playbooks.py
```

- 신규 서브시스템 추가 시 `tools/verify_playbooks.py`의 `REQUIRED_PLAYBOOKS`와 본 `playbook/README.md` 인덱스 테이블을 함께 갱신한 뒤 위 명령으로 `0 Errors, 0 Warnings`를 확인합니다.
