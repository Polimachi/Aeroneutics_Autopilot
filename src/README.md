# Source Programs (멀티 Lua 코드베이스)

Create: Aeronautics 및 CC:Tweaked 환경에서 구동되는 비행선 제어·운항 소프트웨어 코드베이스 관리 디렉토리입니다.

## 아키텍처 및 관리 원칙

1. **독립 자체 완결성 (Self-contained)**
   - 각 하위 프로젝트(`src/<계층>/<프로젝트명>/`)는 외부에 직접 의존하지 않고 독립적으로 동작하는 완결형 프로그램입니다.
   - 프로젝트 공용 라이브러리를 두지 않으며, 필요한 기능은 코드베이스 내부에서 캡슐화합니다.

2. **표준 진입점 (Entry Point)**
   - 각 코드베이스의 기본 실행 진입점은 `main.lua`입니다.
   - 내부 모듈은 해당 프로젝트 디렉토리 하위(예: `modules/`, `hal/` 등)에서 관리합니다.

---

## 계층 구조 (Architectural Layers)

- **`0_development/`**: 개발 계층 (Development Layer)
  - `alignment/`: **Alignment** - 지상 기지 추진기 캘리브레이션 및 횡측 정렬 엔진
  - `installer/`: **Installer** - 통합 코드베이스 설치 프로그램 코어 및 매니페스트 (루트 `installer.lua`와 연계)
  - `sensors/`: **Sensors API** - CC:Avionics 4종 표준 센서 API 라이브러리 (`/lib/avionics_sensors.lua`)
- **`0_infra/`**: 인프라 및 지상 시설물 계층 (Infrastructure & Ground Facility Layer)
  - `gps/`: **GPS** - 중앙 연산형 고정밀 GPS 측위 서버 및 노드 클러스터
  - `gac/`: **GAC** - 지상 구역 관제사 (Ground Area Controller)
  - `docking_arm/`: **DOCKING_ARM** - 기체 정밀 도킹 2축 로봇 암 스테이션
  - `landing_pad/`: **LANDING_PAD** - VTOL 착륙패드 및 버티포트 스테이션
  - `runway/`: **RUNWAY** - 활주로 및 항공모함 비행갑판 관제 스테이션
- **`1_control/`**: 제어 계층 (Flight Control Layer)
  - `vas/`: **VAS** (Vessel Attitude Sustainer) - 기체 자세 유지 및 비행 제어 코어
  - `tca/`: **TCA** (Thruster Control Adapter) - 추진기 제어 어댑터
  - `asa/`: **ASA** (Aerodynamic Surface Adapter) - 공력익/조종면 제어 어댑터
- **`2_guidance/`**: 유도 계층 (Guidance Layer)
  - `fcp/`: **FCP** (Flight Control Program) - 비행 제어 프로그램 및 외루프 유도 컴퓨터
- **`3_planning/`**: 경로 계획 계층 (Path/Trajectory Planning Layer)
  - 항로 및 궤적 계획 시스템
- **`4_mission/`**: 임무 관리 계층 (Mission Management Layer)
  - 비행 미션 상태 머신 및 임무 수행 통제기
