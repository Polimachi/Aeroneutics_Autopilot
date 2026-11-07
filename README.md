# Create_Aeroneutics

**Create_Aeroneutics**는 Minecraft의 **CC:Tweaked**(Lua 5.2 Cobalt) 환경을 기반으로 **Create: Aeronautics** 및 **Create: Propulsion** 비행선/항공기의 자율 비행, 항전(Avionics), 지상 시설 및 항공교통 관제를 구축하는 소프트웨어 및 전용 테스트 하네스 프로젝트입니다.

---

## 📌 현재 단계 및 로드맵 (Current Phase & Roadmap)

- **현재 단계**: **Phase 0** — 기체 통신 40채널 전면 확장, 사양서 영구 계층 개편, CC:Tweaked 단위 테스트 하네스 구축 완료
- **작업 관리 및 상세 로드맵**: [TASK.md](TASK.md)
  - `TASK-001`: 기체 5대 핵심 모듈(`src/` — VAS, TCA, SAS, Alignment, GPS) 40채널/Zone 런타임 코드 동기화 (진행 예정)
  - `TASK-002`: CC:Tweaked 하네스 및 단위 테스트 검증 파이프라인 구축 (완료)
  - `TASK-003`: 런타임 코드 검증 및 사양서 상태 전이 (`Approved` → `Implemented`)
  - `TASK-004`: 원격 저장소(`origin main`) 푸시 및 인증 완료

---

## 📁 디렉토리 구조 및 도메인 정합성 (Directory Layout)

프로젝트 내 모든 사양서(`docs/specs/`), 소스 코드(`src/`), 단위 테스트(`tests/`)는 도메인 계층 구조를 1:1로 일치시킵니다:

```
Create_Aeroneutics/
├── TASK.md                                # 에이전트-유저 작업 관리 및 종합 로드맵 (SSOT)
├── README.md                              # 프로젝트 개요 및 표준 개발 가이드
├── GEMINI.md                              # 작업 간 동적 컨텍스트 스냅샷
├── AGENTS.md                              # 에이전트 행동 헌장
│
├── docs/                                  # 시스템 사양서 및 아키텍처 문서
│   ├── system/                            # 마스터 ICD 및 시스템 전역 관계도
│   │   ├── AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md
│   │   └── SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md
│   └── specs/                             # 기능 도메인별 프로그램 사양서 (영구 단일 계층)
│       ├── 0_development/alignment/       # 격납고 동역학 프로파일러 및 식별 사양서
│       ├── 0_infra/                       # 기지 인프라 및 지상 설비 사양서 (docking_arm, gac, gps, landing_pad, runway)
│       ├── 1_control/                     # 온보드 제어 사양서 (asa, tca, vas)
│       ├── 2_guidance/fcp/                # 비행 제어 프로그램 및 외루프 유도 사양서
│       ├── 3_planning/                    # 3차원 경로 계획 사양서 (Phase 2)
│       └── 4_mission/                     # 편대 미션 오케스트레이터 사양서 (Phase 2)
│
├── src/                                   # CC:Tweaked Lua 독립 멀티 코드베이스
│   ├── 0_development/alignment/           # 지상 정렬 및 시스템 식별 프로그램
│   ├── 0_infra/                           # 기지 인프라 및 지상 관제 시설 (docking_arm, gac, gps, landing_pad, runway)
│   ├── 1_control/                         # 실시간 온보드 제어 (asa, tca, vas)
│   ├── 2_guidance/fcp/                    # 비행 제어 프로그램 및 외루프 유도 (FCP)
│   ├── 3_planning/                        # 경로 계획 모듈 (Phase 2)
│   └── 4_mission/                         # 미션 분배기 (Phase 2)
│
├── harness/                               # CC:Tweaked 전용 테스트 하네스
│   └── unit/                              # Mock Peripheral, Rednet 환경 및 게스트 러너
│
├── tests/                                 # 도메인별 단위 테스트 슈트
│   ├── 0_development/alignment/           # Alignment 단위 테스트
│   ├── 0_infra/gps/                       # GPS 단위 테스트
│   ├── 1_control/{tca, vas, asa}/         # 온보드 제어기 단위 테스트
│   ├── 2_guidance/fcp/                    # FCP 단위 테스트
│   └── harness/                           # 하네스 자체 검증 테스트
│
├── tools/                                 # 개발·빌드·검증 CLI 도구
│   └── run_unit_tests.py                  # 멀티 코드베이스 단위 테스트 러너
│
├── reports/                               # 정적 분석 및 리팩토링 검토 보고서
│   ├── underReview/                       # 검토 진행 중 보고서
│   └── reviewCompleted/                   # 검토 완료 보고서
│
└── scratch/                               # 검증 스크립트 및 임시 도구
    ├── verify_all_specs.py                # 12대 사양서 전수 무결성 검증기
    └── validate_lua_syntax.py             # Lua 5.2 문법/금지 모드 정적 검사기
```

---

## 🌐 통신 아키텍처 및 네트워크 규격 (Network Architecture)

모든 비행체 및 지상 시스템은 **Dynamic 40-Channel Bandwidth ($BW=40$)** 규격을 따릅니다:

$$\text{Base} = 10000 + (N - 1) \times 40 \quad (N: \text{기체 번호, } 1 \le N \le 99)$$

### 4대 기능 Zone 분할
- **Zone 1 (`Base + 0 ~ 9`)**: 비행 제어 & 코어 항전 (VAS, FCP 텔레메트리, 정렬, 안전 정지)
- **Zone 2 (`Base + 10 ~ 19`)**: 구동계 & 추진 제어 (TCA, RCS, 스러스터 제어 링크)
- **Zone 3 (`Base + 20 ~ 29`)**: 탑재체 & 센서 링크 (ASA 레이더, 페이로드)
- **Zone 4 (`Base + 30 ~ 39`)**: 편대 비행 & 지상 링크 (GAC, 착륙 패드, 편대 링크)

---

## 🛠️ 개발 및 검증 명령어 (Standard Commands)

### 1. 단위 테스트 실행 (Unit Test Runner)
모든 코드베이스의 CC:Tweaked 모킹 기반 단위 테스트를 실행합니다:
```bash
python tools/run_unit_tests.py
```
- 특정 모듈 단독 실행:
  ```bash
  python tools/run_unit_tests.py --target 1_control/vas
  python tools/run_unit_tests.py -t tca
  ```

### 2. 사양서 전수 무결성 검증 (Specification Integrity Scanner)
12대 활성 사양서의 상대 링크, 메타데이터 표, Mermaid 블록, 폐기 배지 및 대역폭 수식을 전수 검사합니다:
```bash
python scratch/verify_all_specs.py
```

### 3. Lua 5.2 문법 및 제약 정적 검사 (Lua Syntax & Guard Check)
Cobalt 런타임 문법 및 허용/금지 모드 API 사용 여부를 정적 검사합니다:
```bash
python scratch/validate_lua_syntax.py
```

---

## 📐 핵심 설계 원칙 (Engineering Principles)

1. **영구 단일 경로 불변 원칙 (Permanent Single Path)**:
   - 사양서 파일은 상태 변화(`Draft` / `Approved` / `Implemented` / `Deprecated`)에 따라 디렉토리를 이동하지 않고 `docs/specs/<domain>/` 하위 위치를 영구 유지합니다.
   - 생명주기는 각 문서 최상단 메타데이터 요약 표 및 `Revision History` 테이블로 추적합니다.
2. **Zero-Fallback 원칙 (Clean Contracts)**:
   - 통신 프로토콜 개정 시 수신단에 구버전/신버전 듀얼키 폴백 코드를 두지 않습니다.
   - 송신단과 수신단의 계약을 동시에 패치하며, 구버전 필드는 사양서 내 `[DEPRECATED]` 배지로 명시합니다.
3. **런타임 호환성 (CC:Tweaked Lua 5.2 Cobalt)**:
   - Lua 5.2 표준 준수 (1-based index, `bit32` 연산, 전역 변수 오염 금지).
   - Create: Aeronautics, Avionics, Radars, Propulsion 모드 허용 및 Valkyrien Skies (VS2) 네임스페이스 엄격 차단.
