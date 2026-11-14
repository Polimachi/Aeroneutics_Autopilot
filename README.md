# Create_Aeroneutics

**Create_Aeroneutics**는 Minecraft의 **CC:Tweaked**(Lua 5.2 Cobalt) 환경을 기반으로 **Create: Aeronautics**, **Create: Avionics**, **Create: Radars**, **Create Propulsion: Simulated**, **Advanced Peripherals** 생태계에서 운용되는 비행선·항공기의 자율 비행, 항전(Avionics), 지상 시설 및 항공교통 관제를 구축하는 멀티 코드베이스 소프트웨어 및 전용 테스트 하네스 프로젝트입니다.

---

## 📌 현재 단계 및 로드맵 (Current Phase & Roadmap)

- **현재 단계**: **Phase 1 & 2 (진행 중)** — 전사 사양서·코드베이스·하네스 전수 감사 43건 교정 및 8대 사양서 `Implemented` 승격(`TASK-013`), `AMM v2.0.1` 표준 행동 체계(`ACT_*`/`DEC_*`/`MAC_*`)·채터링 방지 가드 통합(`TASK-124`, `TASK-204`), GPS 고부하·위상·채널 결함 수정(`TASK-123`), 4계층 `SE(3)` 아키텍처 연동(`TASK-207`~`209`: `AMM`·`FCP v2.1.0`·`VAS v1.20.0`), 사양서 역할 분리 개편(`TASK-206`) 및 미션 시퀀서·WebUI 에디터 사양(`TASK-202`, `v0.3.1 Approved`) 수립 완료 (`TASK-402` WebUI 구현 진행 중; 이전 기반 마일스톤 이력은 `.agent/memory/workspace-root.md`, 최신 검증 수치는 [GEMINI.md](GEMINI.md) §3 참조).
- **단계별 이정표 요약**:
  - **Phase 0 (기반 구축 및 코어 동기화)**: 40채널 마스터 ICD·12대 사양서 개편, 단위 테스트 하네스 구축, 코어 모듈(`VAS`, `TCA`, `FCP`, `Alignment`, `GPS`) 런타임 동기화, 사양서 상태 전이(`Approved` → `Implemented`) 및 통합 인스톨러 구축
  - **Phase 1 (지상 관제 및 온보드 확장)**: `GAC`, `Landing Pad`, `GCS`(`TASK-107`) 구현, `VAS` 센서 파이프라인 표준화(`TASK-112`), 온보드 제어기 헤드리스 개편(`TASK-113`), Cockpit MFD 통합 단말(`AMM`, `TASK-200`) 및 `FCP` VTOL 고도화(`TASK-110`) 구축 완료 (`Tower ATC`·`Runway`·`Docking Arm`·`ASA` 본 구현 일정 보류)
  - **Phase 2 (고등 항법 및 편대 임무)**: 3차원 경로 계획(`3_planning/`) 및 다중 기체 편대 미션 오케스트레이터(`4_mission/`) 구축
  - **Phase 3 (물리 하드웨어 및 수동 급기동)**: Create/Avionics 아날로그 스틱 및 물리 컨트롤러 연동, `Base+1` 20Hz 직접 3축 각속도(`RATE_COMMAND`) 직결 ACRO 수동 조종(`TASK-301`)
- **실시간 작업 진행 현황 및 상세 백로그 (SSOT)**: [TASK.md](TASK.md)

---

## ⚙️ 사전 요구사항 (Prerequisites)

- **Python 3.10+**: 단위 테스트 러너(`tools/run_unit_tests.py`) 및 사양서·문법 정적 검사기 실행
- **CraftOS-PC (`CraftOS-PC_console.exe`)**: 헤드리스 CC:Tweaked 게스트 세션 실행 필수 의존성
  - 기본 설치 경로(`C:\Program Files\CraftOS-PC\` 등)를 자동 탐색하며, 비표준 경로 설치 시 `CRAFTOS_PC_EXE` 환경변수로 실행 파일 경로를 지정합니다.
- **Git**: 버전 관리 및 `.worktrees/` 격리 브랜치 운용 (Windows PowerShell `PATH` 미등록 환경에서는 `"C:\Program Files\Git\cmd\git.exe"` 호출)
- **gdrive CLI** *(선택, §10 배포 시)*: Google Drive 공식 폴더 동기화(`tools/sync_gdrive.py`) 실행 시 `PATH` 등록 필요
- **인게임 대상 모드 스택**:
  - **지원 모드**: `CC:Tweaked` (Lua 5.2 Cobalt), `Create`, `Create: Aeronautics`, `Create: Avionics`, `Create: Radars`, `Create Propulsion: Simulated` (`ion_thruster` 포함), `Advanced Peripherals`
  - **비호환·차단 모드**: `Valkyrien Skies (VS2)` 계열 및 `kontraption:` 네임스페이스 페리페럴

---

## 📁 디렉토리 구조 및 도메인 정합성 (Directory Layout)

프로젝트 내 모든 사양서(`docs/specs/`), 구현 코드(`src/`), 단위 테스트(`tests/`)는 도메인 계층 구조를 1:1로 일치시킵니다:

```text
Create_Aeroneutics/
├── TASK.md                                # 장기 작업 관리 및 종합 로드맵 (SSOT)
├── README.md                              # 프로젝트 개요 및 표준 개발 가이드
├── GEMINI.md                              # 작업 간 동적 컨텍스트 스냅샷 (<= 80줄)
├── AGENTS.md                              # 에이전트 불변 행동 헌장
├── installer.lua                          # 통합 코드베이스 설치 프로그램 (화면 직접 업로드/플로피/wget)
├── config/gdrive_mapping.json             # GDrive 배포 파일 ID 매핑 (SSOT)
├── dist_gdrive/                           # GDrive 업로드 격리 스테이징 (sync_gdrive.py 생성)
│
├── docs/                                  # 시스템 사양서 및 아키텍처 문서
│   ├── guides/                            # 운영 가이드 (GDRIVE_DEPLOYMENT_GUIDE.md)
│   ├── superpowers/plans/                 # 태스크별 실행 계획서
│   ├── superpowers/specs/                 # 태스크별 설계 청사진 (Action Primitive 등)
│   ├── system/                            # 마스터 ICD 및 시스템 전역 관계도
│   │   ├── AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md
│   │   └── SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md
│   └── specs/                             # 기능 도메인별 프로그램 사양서 (영구 단일 계층)
│       ├── 0_development/                 # 개발·교정·배포 사양서 (alignment, installer)
│       ├── 0_infra/                       # 기지 인프라 및 지상 설비 사양서 (docking_arm, gac, gcs, gps, landing_pad, runway)
│       ├── 1_control/                     # 온보드 제어 사양서 (asa, tca, vas)
│       ├── 2_guidance/fcp/                # 비행 제어 프로그램 및 외루프 유도 사양서 (FCP)
│       ├── 3_planning/amm/                # 항공기 임무 관리자(AMM) 및 WebUI 미션 에디터 사양서
│       └── 4_mission/                     # 편대 미션 오케스트레이터 사양서 (Phase 2 예정 / 현재 빈 폴더)
│
├── src/                                   # CC:Tweaked Lua 독립 완결형 멀티 코드베이스
│   ├── 0_development/alignment/           # 지상 정렬 및 시스템 식별 프로그램
│   ├── 0_development/installer/           # 통합 인스톨러 코어 및 선언적 매니페스트
│   ├── 0_development/sensors/             # CC:Avionics 4종 센서 공용 표준 라이브러리 (SSOT)
│   ├── 0_infra/                           # 기지 인프라 및 지상 관제 시설 (docking_arm, gac, gcs, gps, landing_pad, runway)
│   ├── 1_control/                         # 실시간 온보드 제어 (asa, tca, vas)
│   ├── 2_guidance/fcp/                    # 비행 제어 프로그램 및 외루프 유도 (FCP)
│   ├── 3_planning/amm/                    # 항공기 임무 관리자 및 Cockpit MFD 통합 단말 (AMM)
│   └── 4_mission/                         # 미션 분배기 (Phase 2 예정 / `.gitkeep` 플레이스홀더)
│
├── harness/                               # CraftOS-PC 헤드리스 기반 전용 테스트 하네스
│   ├── simulation/                        # 다중 노드 격리 가상 버스 및 게스트 샌드박스 (E2E)
│   └── unit/                              # 세션 관리, 정적 가드, Mock Peripheral/Rednet 및 게스트 SDK
│
├── tests/                                 # 도메인별 단위 테스트 및 하네스 회귀 테스트 슈트
│   ├── 0_development/alignment/           # Alignment 단위 테스트
│   ├── 0_development/installer/           # 통합 인스톨러 단위 테스트
│   ├── 0_development/sensors/             # 센서 표준 라이브러리 단위 테스트
│   ├── 0_infra/{gac, gcs, gps, landing_pad}/ # 기지 인프라 단위 테스트 (GAC, GCS, GPS, Landing Pad)
│   ├── 1_control/{asa, tca, vas}/         # 온보드 제어기 단위 테스트
│   ├── 2_guidance/fcp/                    # FCP 단위 테스트
│   ├── 3_planning/amm/                    # AMM 및 WebUI 에디터(`test_amm_mission_editor.py`) 단위 테스트
│   ├── e2e/                               # 멀티노드 종단간(E2E) 패킷 시뮬레이션 시나리오 슈트
│   └── harness/                           # 하네스 엔진·러너 Python 단위 테스트
│
├── tools/                                 # 개발·검증 CLI 도구
│   ├── amm_mission_editor.html            # 호스트 PC 오프라인 WebUI 미션 에디터 (`TASK-402` 구현 중)
│   ├── run_e2e_tests.py                   # 멀티노드 E2E 패킷 시뮬레이션 러너
│   ├── run_mutation_tests.py              # 테스트 실효성 검증용 돌연변이 테스터 (살상률 측정)
│   ├── run_unit_tests.py                  # 멀티 코드베이스 단위 테스트 러너
│   ├── sync_gdrive.py                     # GDrive 스테이징·동기화·검증 CLI
│   ├── validate_lua_syntax.py             # Lua 5.2 문법/금지 모드 정적 검사기
│   ├── verify_all_specs.py                # 15대 사양서 전수 무결성 검증기
│   ├── verify_context_docs.py             # 루트 컨텍스트 문서 드리프트 정적 검사기 (R1~R8)
│   ├── verify_manifest_sync.py            # manifest.lua·GDrive 맵·src/ 3자 정합성 검증기
│   └── verify_spec_status.py              # 사양서 상태 분포 검증기
│
├── reports/                               # 정적 분석 및 리팩토링 검토 보고서
│   ├── underReview/                       # 검토 진행 중 보고서
│   └── reviewCompleted/                   # 검토 완료 보고서
│
├── scratch/                               # 개발자 임시 작업 공간 (Scratchpad)
│   └── README.md                          # 임시 스크립트 격리 정책 안내
│
└── .agent/                                # 에이전트 규칙(rules/), 스킬(skills/), 이력(memory/), 안전 훅(hooks/, hooks.json)
```

---

## 🌐 통신 아키텍처 및 네트워크 규격 (Network Architecture)

### 전역 RF 스펙트럼 할당표

| 채널 구간 | 할당 도메인 | 비고 |
| :--- | :--- | :--- |
| `0 ~ 100` | 시스템 예약 대역 | 일반 무선 할당 제외 |
| `101 ~ 200` | 격납고 교정 시설 (`Alignment`) | $Base_{\text{hangar}} = 101 + (\text{BayID} - 1) \times 10$ (`Bay 1 ~ 10`) |
| `10000 ~ 49999` | 비행체 전용 40채널 블록 ($BW=40$) | 최대 1,000대 연속 수납 ($1 \le N \le 1000$) |
| `50000` | GCS 채널 부트스트랩 | 기체 채널 블록 동적 할당 및 충돌 중재 |
| `50001 ~ 59999` | 광역 ATC · 섹터 GAC · 스마트 시설물 | Sector 0(`50001~50200`), Sector $S$($Base_{\text{sec}} = 50001 + S \times 200$) |
| `60001 ~ 60020` | 고정밀 GPS 측위 인프라 | 측위 핑(`60001`), 서비스(`60002`), 스웜 노드 보고(`60003`) |

### 비행체 전용 40채널 수식 및 4대 기능 Zone

$$\text{Base} = 10000 + (N - 1) \times 40 \quad (N: \text{기체 블록 번호, } 1 \le N \le 1000)$$

- **Zone 1 (`Base + 0 ~ 9`)**: 코어 C2 · 궤적/외루프 유도 · 텔레메트리 (`Base+0` 오퍼레이터/교정 바인딩 C2, `Base+1` FCP `QUATERNION_RATE` 외루프 지령 및 ACRO/비상 선점, `Base+2` VAS 20Hz 텔레메트리, `Base+3` MFD 다운링크 및 ACRO 양보, `Base+4` AMM↔FCP 20Hz 궤적 지령 `CH_TRAJECTORY_CMD`, `Base+5` GPS 측위 응답 수신)
- **Zone 2 (`Base + 10 ~ 19`)**: 구동계 전용 버스 (`Base+10` `TCA` 추진기 분산 클러스터, `Base+11` `ASA` 공력 조종면·플랩 분산 클러스터, `Base+12~19` 구동계 예비)
- **Zone 3 (`Base + 20 ~ 29`)**: 탑재체 전용 버스 (임무 장비 및 확장 페이로드 링크)
- **Zone 4 (`Base + 30 ~ 39`)**: 편대 비행 데이터링크 (다중 기체 간 편대 동기화 및 협동 링크)

---

## 🛠️ 개발 및 검증 명령어 (Standard Commands)

### 0. 전체 파이프라인 통합 일괄 검증 (One-Liner)
Windows PowerShell 5.1 (`&&` 미지원):
```powershell
python tools/run_unit_tests.py --require-tests --clean-orphans; if ($?) { python tools/run_e2e_tests.py --clean-orphans }; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python tools/verify_all_specs.py }; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/verify_context_docs.py }; if ($?) { python tools/validate_lua_syntax.py }
```
bash / PowerShell 7+:
```bash
python tools/run_unit_tests.py --require-tests --clean-orphans && python tools/run_e2e_tests.py --clean-orphans && python tools/verify_manifest_sync.py && python tools/verify_all_specs.py && python tools/verify_spec_status.py && python tools/verify_context_docs.py && python tools/validate_lua_syntax.py
```

### 1. Lua 멀티 코드베이스 단위 테스트 실행
CraftOS-PC 격리 세션에서 전체 코드베이스의 단위 테스트를 실행합니다:
```bash
python tools/run_unit_tests.py --require-tests --clean-orphans
```
- 특정 모듈 단독 또는 필터 실행:
  ```bash
  python tools/run_unit_tests.py --target 1_control/vas
  python tools/run_unit_tests.py -t tca --filter rebind
  ```

### 2. 멀티노드 종단간(E2E) 시뮬레이션 테스트 실행
다중 노드 격리 가상 버스 및 게스트 샌드박스 환경에서 8개 통합 시뮬레이션 스위트(13개 케이스)를 실행합니다:
```bash
python tools/run_e2e_tests.py --clean-orphans
```

### 3. 테스트 실효성 검증 (돌연변이 살상 테스트)
25개 결정론적 결함을 자동 주입하여 테스트 슈트의 결함 포착 능력(살상률 90% 이상 기준)을 검증합니다:
```bash
python tools/run_mutation_tests.py
```

### 4. 테스트 하네스 자체 회귀 검증 (Python)
하네스 엔진, 격리 세션, 게스트 SDK, 정적 가드의 단위 테스트를 실행합니다:
```bash
python -m unittest discover -s tests/harness -p "test_*.py"
```

### 5. 사양서 전수 무결성 검증
15대 활성 사양서의 상대 링크, 메타데이터 표, Mermaid 구문, 폐기 배지 및 40채널 수식을 검사합니다:
```bash
python tools/verify_all_specs.py
```
- README 상대 링크 정밀 검사 옵션:
  ```bash
  python tools/verify_all_specs.py --check-readmes
  ```

### 6. 사양서 상태 분포 검증
코어 15대 활성 사양서의 상태 분포(`Implemented` / `Approved`)를 검사합니다 (에디터 사양서 포함 전체 16종 분포는 [GEMINI.md](GEMINI.md) §3 참조):
```bash
python tools/verify_spec_status.py
```

### 7. Lua 5.2 문법 및 금지 API 정적 검사
전체 Lua 소스의 Cobalt 런타임 문법 및 허용/차단 모드 네임스페이스 규칙 준수 여부를 검사합니다:
```bash
python tools/validate_lua_syntax.py
```

### 8. 인스톨러 매니페스트 · GDrive · 소스 트리 3자 정합성 검증
`src/` 실제 런타임 파일, `manifest.lua` 등록 목록, `config/gdrive_mapping.json` 간의 누락·고아 파일·카테고리 불일치를 정적 검사합니다:
```bash
python tools/verify_manifest_sync.py
```

### 9. 컨텍스트 문서 정합성 검증
`README.md`, `GEMINI.md`, `TASK.md`, `.agent/memory/*.md` 간 8개 드리프트 규칙(R1~R8) 준수 여부를 정적 검사합니다:
```bash
python tools/verify_context_docs.py
```

### 10. 인게임 배포 (GDrive)
배포 파일을 `dist_gdrive/`에 스테이징하고 Google Drive 공식 폴더와 동기화합니다 (`gdrive` CLI PATH 등록 필요). 상세 절차: [docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md](docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md)
```powershell
python tools/sync_gdrive.py stage
python tools/sync_gdrive.py sync --dry-run
```

---

## 📐 핵심 설계 원칙 (Engineering Principles)

1. **독립 멀티 코드베이스 원칙 (Self-Contained Multi-Codebase)**:
   - 각 하위 코드베이스(`src/<layer>/<subsystem>/`)는 개별 CC:Tweaked 컴퓨터 루트에 독립 마운트되어 동작하므로 코드베이스 간 직접 참조를 두지 않고 내부에서 자체 완결합니다 (기본 진입점 `main.lua`, 유일한 예외는 인스톨러가 `/lib/avionics_sensors.lua`로 자동 주입하는 공용 센서 라이브러리).
2. **영구 단일 경로 불변 원칙 (Permanent Single Path)**:
   - 사양서 파일은 상태 변화(`Draft` / `Approved` / `Implemented` / `Deprecated`)에 따라 디렉토리를 이동하지 않고 `docs/specs/<domain>/<subsystem>/` 위치를 영구 유지합니다.
   - 생명주기는 각 문서 상단 메타데이터 요약 표 및 `Revision History` 테이블로 관리합니다.
3. **Zero-Fallback 원칙 (Clean Contracts)**:
   - 통신 프로토콜 개정 시 수신단에 구버전/신버전 듀얼키 폴백 코드를 두지 않습니다.
   - 송신단과 수신단의 계약을 함께 갱신하며, 구버전 필드는 사양서 내 `[DEPRECATED]` 배지로 이력을 보존합니다.
4. **런타임 및 도메인 호환성 (CC:Tweaked Lua 5.2 Cobalt)**:
   - Lua 5.2 표준(1-based index, `bit32` 연산, 전역 변수 오염 금지) 및 허용/차단 모드 페리페럴 경계를 준수합니다.
