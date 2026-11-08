# TASK-010: 개별 코드베이스 사용 설명서(Playbook) 체계 구축 및 핵심 5종 매뉴얼 작성 계획

> **문서 상태**: Approved (수행 대기)  
> **생성일자**: 2026-11-08  
> **관련 사양서**: N/A (운용 매뉴얼 및 개발 하네스 가이드)  
> **목적**: 개별 완성형 코드베이스의 인게임 설치, 설정, 페리페럴 결선, 채널 구성 및 조작법을 직관적으로 안내하는 플레이북 체계(`playbook/`) 신설 및 회귀 검증 도구 구축

---

## 1. 확정된 설계 결정 사항 (/grill-me 결과)

- **디렉토리 구조**: 계층형 단일 마크다운 (`playbook/<도메인>/<서브시스템>.md`)으로 `src/` 및 `docs/specs/`와 1:1 대칭 구조 유지.
- **표준 7대 섹션 템플릿**:
  1. 서브시스템 개요 및 역할 (Overview & Role)
  2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)
  3. 물리 설치 및 블록 배치 지침 (Physical Placement)
  4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)
  5. 소프트웨어 설치 방법 (Installation via installer/wget/floppy)
  6. 설정 파일 가이드 (`config.lua` Parameters & Defaults)
  7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)
- **작성 대상 범위**:
  - 표준 템플릿 명세 및 인덱스: `playbook/README.md`
  - 초기 5종 핵심 체계: `gps.md`, `vas.md`, `tca.md`, `fcp.md`, `amm.md`
  - **엄격한 가드레일**: 타 체계(alignment, gac, docking_arm, landing_pad, runway, asa 등)는 유저의 명시적 추가 요청 전까지 개설 금지.
- **유지보수 및 검증 체계**:
  - `tools/verify_playbooks.py` CLI 도구 신설 (7대 고정 섹션 유무 및 마크다운 링크/경로 정적 검사).
  - `skill-workflows.md`, `GEMINI.md`, `TASK.md`에 플레이북 갱신 워크플로우 반영 (코드 기능 변경 또는 유저 요청 시 갱신).
- **톤앤매너**: 인게임 빌더 및 조종사를 위한 실전 운용 매뉴얼 (블록 명칭, 배치 방향, 실제 화면 조작, 자주 발생하는 오류 해결 중심).

---

## 2. 세부 파일 구성

```text
playbook/
├── README.md                      # 플레이북 표준 템플릿 명세, 작성 규칙 및 인덱스
├── 0_infra/
│   └── gps.md                     # 지상 인프라: 위성/지상 GPS 비컨 송신기 매뉴얼
├── 1_control/
│   ├── vas.md                     # 온보드 제어: 3축 벡터 추력기 자세 안정화(VAS) 매뉴얼
│   └── tca.md                     # 온보드 제어: 추력 중심 자동 정렬(TCA) 매뉴얼
├── 2_guidance/
│   └── fcp.md                     # 유도/항법: 비행 제어 및 경로 유도 컴퓨터(FCP) 매뉴얼
└── 3_planning/
    └── amm.md                     # 임무/조작: 임무 관리자 및 Cockpit MFD 단말(AMM) 매뉴얼

tools/
└── verify_playbooks.py            # 플레이북 7대 필수 섹션 및 무결성 검증 CLI
```

---

## 3. 구현 세부 작업 목록 (Subtasks)

### [ ] TASK-010-1: 플레이북 정적 검증 도구(`tools/verify_playbooks.py`) 구현
- `playbook/README.md` 및 등록된 5종 대상 파일 존재 여부 검사.
- 각 파일별 7대 필수 섹션 헤딩(`## 1. ...` ~ `## 7. ...`) 누락 여부 정규식 검사.
- 인가되지 않은 타 체계 플레이북 파일(미등록 `.md`) 임의 생성 감지 시 실패 반환 가드레일 구현.
- CLI 인자 파싱 및 컬러/표준 출력 포맷팅.

### [ ] TASK-010-2: 표준 템플릿 명세 및 인덱스(`playbook/README.md`) 작성
- 플레이북 디렉토리 목적, 7대 필수 섹션 작성 규칙 명시.
- 5종 핵심 체계 바로가기 인덱스 링크 제공.
- 신규 플레이북 추가 시 준수해야 할 절차 기술.

### [ ] TASK-010-3: 인프라 도메인 매뉴얼(`playbook/0_infra/gps.md`) 작성
- GPS 비컨 컴퓨터 하드웨어 요구사항(컴퓨터, 무선 모뎀).
- 글로벌 GPS 채널 규격(`60001`~`60020`) 및 3D 좌표 설정법.
- 4개 이상 지상 분산 비컨 삼각측량 설치법 및 자가진단.

### [ ] TASK-010-4: 온보드 제어 도메인 매뉴얼(`playbook/1_control/vas.md`, `tca.md`) 작성
- **VAS**: Advanced Computer, 무선 모뎀, 자이로스코프, RCS 이온 추력기(Simulated) 배치 지침, 기체 Base 채널 동역학 링크, P/I/D 게인 튜닝.
- **TCA**: Advanced Computer, 유선/무선 모뎀, 메인 추력기 짐벌(Gimbal) 배치 지침, 기체 질량 중심(CoM) 편차 보정 및 오프셋 보정 실전 가이드.

### [ ] TASK-010-5: 유도 및 임무 도메인 매뉴얼(`playbook/2_guidance/fcp.md`, `playbook/3_planning/amm.md`) 작성
- **FCP**: Advanced Computer, 무선 모뎀, 센서 팩(CC:Avionics 4종), 센서 설치 방향(전방/상방), 외루프 PID 및 비행 모드 설정법.
- **AMM**: Advanced Computer(51x19 터미널), C2/웨이포인트 큐 영속화, 핫키 조작법(`[X]` E-STOP, `[H]` HOLD, `[W]` 웨이포인트 추가), GCS 연동 가이드.

### [ ] TASK-010-6: 프로젝트 규칙 반영, 컨텍스트 동기화 및 검증
- `.agent/rules/skill-workflows.md`에 플레이북 유지보수 원칙(코드/기능 변경 시 갱신 의무, 미인가 체계 작성 차단) 반영.
- `GEMINI.md` 및 `TASK.md`에 `playbook/` 경로 및 `tools/verify_playbooks.py` 표준 명령어 등록.
- `python tools/verify_playbooks.py` 및 기존 테스트 러너 회귀 확인.
