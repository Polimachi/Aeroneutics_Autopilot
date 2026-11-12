# 착륙패드 시스템 및 통신 인터페이스 제어 규격서 (ICD)
> **Landing Pad System Specification & Interface Control Document (ICD)**  
> **프로젝트**: Universal Autonomous Flight Stack (AMM · FCP · VAS · Ground Infrastructure)  
> **대상 환경**: Minecraft CC:Tweaked (Ender Modem), Create: Aeronautics, Create: Avionics  

| 항목 | 내용 |
| :--- | :--- |
| **문서 상태 (Status)** | `Implemented` |
| **문서 버전 (Version)** | `v2.4.3` |
| **최종 수정일 (Date)** | `2026-11-12` |
| **구현 코드 (Source)** | `src/0_infra/landing_pad/` |
| **주관 도메인 (Domain)** | 지상 인프라 수직이착륙 착륙패드 비콘 (Landing Pad) |

### Revision History

| 버전 | 일자 | 개정 요약 | 개정 사유 |
| :--- | :--- | :--- | :--- |
| `v2.4.3` | 2026-11-12 | FCP-AMM 역할 분리(마스터 ICD v1.28.0)에 따른 기체 외부 교신·2차 테일러 외삽·300ms 복행 및 `landingPermitted`/`DANGEROUS` 호버 게이팅 주체 용어 정렬(`FCP (Node 04)` $\to$ `AMM (Node 03)`, `Base+4`로 `FCP`에 세트포인트 전달) 및 연관 규격서 버전 동기화 (`src/0_infra/landing_pad/` 런타임 무변경, `Implemented` 유지) | AMM 외부 게이트웨이·궤적 생성 전담 및 FCP 순수 외루프 제어기 역할 분리 정합화 |
| `v2.4.2` | 2026-11-08 | 구버전 명칭 전면 척결 및 표준 명칭(FCP/ASA) 동기화 | 용어 무결성 확보 |
| `v2.4.1` | 2026-11-08 | GAC v1.4.0 전용 시설물 아키텍처 연동 및 전용 패드 슬롯 배정 원칙 명시 | 상위 GAC 전용 시설물 규격 동기화 |
| `v2.4.0` | 2026-11-08 | GPS 모뎀 기반 수평 좌표 자동 획득, 컴퓨터 바디 기준(전후/좌우/상하) 상대 오프셋 보정, 동적 센서 미감지 강제 중단, 평시 1Hz GPS 측위·GAC 위치 보고 및 5단계 TUI 마법사 규격(Section 6) 증설 | 현장 설치 편의성 및 이동형 플랫폼 공간 인지 무결성 확립 |
| `v2.3.0` | 2026-11-08 | 초기 설치 시운전(상대 좌표 오프셋 보정) 및 동적 패드 인접 항법 센서 자동 바인딩 규격 추가 | 비콘 컴퓨터 설치 위치 오프셋 및 동적 텔레메트리 센서 연동 실체화 |
| `v2.2.5` | 2026-11-07 | 사양서 및 코드 디렉토리 `0_ground` → `0_infra` 통합 이동 및 경로 동기화 | 지상 인프라 체계 단일화 구조 개편 |
| `v2.2.4` | 2026-11-07 | 40채널 확장 및 표준 메타데이터 표 적용 | Phase 0 ICD 동기화 |


> **연관 규격서**: 
> - [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md) (마스터 ICD v1.28.0)
> - [GAC_PROGRAM_SPECIFICATION_AND_ICD.md](../gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md) (GAC 관제사 규격서 v1.4.2)
> - [SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md](../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 관계도 v2.13.0)
> - [GPS_PROGRAM_SPECIFICATION_AND_ICD.md](../gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md) (GPS 규격서 v2.3.1)
> - [AMM_PROGRAM_SPECIFICATION.md](../../3_planning/amm/AMM_PROGRAM_SPECIFICATION.md) (AMM 임무 관리자 및 조종석 단말 규격서 v1.3.0)
> - [FCP_PROGRAM_SPECIFICATION.md](../../2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md) (FCP 비행 제어 규격서 v2.0.0)
> - [VAS_PROGRAM_SPECIFICATION.md](../../1_control/vas/VAS_PROGRAM_SPECIFICATION.md) (비행 제어 코어 v1.19.0)
> - [RUNWAY_SPECIFICATION_AND_ICD.md](../runway/RUNWAY_SPECIFICATION_AND_ICD.md) (활주로 규격서 v1.10.7)
> - [DOCKING_ARM_SPECIFICATION_AND_ICD.md](../docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md) (도킹암 규격서 v1.11.2)

---

## 1. 개요 및 시스템 범위 (Overview & System Scope)

본 문서는 수직이착륙(VTOL) 기체의 안전한 지상 접근, 정밀 수직 하강 터치다운 및 공역 점유 관리를 관할하는 **착륙패드(Landing Pad) 노드**의 통신 프로토콜, 동역학 스트리밍, 상위 관제 백본 인터페이스, 상태 머신(FSM) 및 갑판 안정성 판정 알고리즘을 정의한 단독 완결형 세부 규격서입니다.

### 1.1 핵심 설계 원칙
1. **순수 가상 좌표 비콘화 및 광역 비콘 상위 위임 (Pure Virtual Coordinate & Aggregated Beacon)**:
   - 착륙패드는 복잡한 기계식 클램프, 갠트리, 피스톤 또는 바닥 물리 센서(압력판 등)를 일절 두지 않는 **순수 경량 항법 및 통신 노드**로 동작합니다.
   - CC:Tweaked 무선 모뎀 큐 과부하 및 채널 간섭을 방지하기 위해, 패드 노드는 `CH 50003` 광역 비콘을 직접 송출하지 않고 **상위 지상 구역 관제사(GAC)에게 섹터 집약 비콘(`MSG_FACILITY_BEACON`) 송출을 위임**합니다.
   - 모든 점유/진입 제어는 무선 모뎀 패킷 교신(`MSG_TOUCHDOWN_COMPLETE`, `MSG_ATC_SLOT_ASSIGN`)을 통해서만 소프트웨어적으로 관리됩니다.
2. **지상 구역 관제사(GAC) 관할 및 3-Tier 계층 제어 모델**:
   - 패드는 최상위 광역 관제탑(Tower ATC)과 직접 교신하지 않고, 직속 **지상 구역 관제사(GAC)**의 섹터 로컬 백본망(`CH_SECTOR_FACILITY` = $Base_{\text{sec}} + 1$)을 통해서만 슬롯 예약 및 상태 갱신을 수행합니다.
   - 패드는 1회 1기체 독점 점유(**FIFO 점유 모델**)로 운영되며, 착륙한 기체가 이륙할 때까지 무기한 `OCCUPIED`를 유지합니다. 후속 진입 기체는 GAC에 의해 공중 선회 대기(Loiter) 또는 관할 내 가용 타 패드로 자동 분산됩니다.
3. **유도 역할 분담 경계 (Guidance Responsibility Boundary)**:
   - **착륙패드 노드**: 터치다운 중심 좌표(`touchdownPoint`), 기본 물리 제원(`dimensions`, `maxWeight`), 접근 권장 헤딩(`approachHeading`), 최대 허용 하강률(`safeDescentRate`), 안전 반경(`clearanceZoneRadius`) 및 지상풍(`surfaceWind`) 등 환경 구속조건만을 브로드캐스트합니다.
   - **기체 AMM (Node 03) 및 FCP (Node 04)**: 패드가 제공한 구속조건을 바탕으로 `AMM`이 다단계 수직 강하 궤적(상공 진입 정렬 $\to$ 정속 수직 강하 $\to$ 지면효과 감속 플레어 $\to$ 접지) 및 동적 패드 20Hz 외삽 세트포인트를 연산해 `Base+4`(`CH_TRAJECTORY_CMD`)로 하달하고, `FCP`가 외루프 위치/속도/자세 추종 제어를 전담합니다.
4. **정적(Static) / 동적(Dynamic) 시설물 분리 모델링**:
   - **고정형 착륙패드 (Static Pad)**: 육상 기지 고정 패드. 좌표 불변이므로 속도/가속도 벡터 필드를 전송하지 않고 1Hz 하트비트만 유지하여 무선 트래픽을 최적화합니다.
   - **이동형 착륙패드 (Dynamic Pad)**: 해상 바지선, 기동 모선, 열차 상부 패드. 실시간 3D 위치, 속도 벡터($\vec{v}$), 가속도 벡터($\vec{a}$), 요동(Pitch/Roll)과 함께 **갑판 안정성 판정 플래그(`deckStatus`, `landingPermitted`)**를 20Hz로 스트리밍하여 기체의 랑데부 항법을 지원합니다.
5. **소프트웨어 중심 접지 판정 및 지상 서비스 분리**:
   - 기체의 온보드 센서(고도계 하강 정지 $v_y \approx 0$ 또는 바퀴 센서)가 접지를 확인하고 `AMM (Node 03)`이 무선 패킷(`MSG_TOUCHDOWN_COMPLETE`)을 송출하면 즉시 패드 점유(`OCCUPIED`)로 전환하고 직속 GAC에 상태를 보고합니다.
   - 연료 급유 및 배터리 충전 등 지상 서비스(Ground Servicing)는 패드 노드의 기계 구동 인터록에서 분리되어, 착륙 후 독립된 외부 지상 요원/장비에 의해 선택적으로 수행됩니다.
6. **페일세이프 및 GAC 경유 국지 복행(Go-Around) 안전 인터록**:
   - 동적 패드 20Hz 구간에서 패킷 두절 발생 시 기체 `AMM (Node 03)`이 즉시 300ms 타임아웃을 감지하여 복행 궤적을 발령합니다. 패드는 요동 위험(`deckStatus == "DANGEROUS"`) 3초 지속, 명시적 `MSG_ABORT_APPROACH` 수신 또는 슬롯 타임아웃(120초) 시 `GO_AROUND` 상태로 전이합니다.
   - 패드는 복행 기체가 안전 복행 고도로 이탈하여 GAC가 패드 개방 명령(`MSG_ATC_FACILITY_UPDATE`, status: `FREE`)을 하달할 때까지 `GO_AROUND` 격리 상태를 유지하여 공역 경쟁 상태(Race Condition)를 차단합니다.
7. **GAC 연동 전용 착륙패드(Dedicated Pad) 운용 모델**:
   - 패드가 특정 기체 ID 또는 기종 전용으로 GAC 인벤토리에 등록된 경우, 패드는 상위 GAC로부터 해당 지정 기체 또는 비상 징발 인가된 기체의 슬롯 배정(`MSG_ATC_SLOT_ASSIGN`)만을 수신하여 1:1 전술 유도를 개시합니다.
   - 비인가 기체의 임의 전술 채널 접속 시도는 무인가 상태로 간주되며, 패드의 접근 슬롯은 GAC 백본 제어를 통해서만 배타적으로 활성화됩니다.

---

### 1.2 GPS 광역 항법 $\rightarrow$ 계층 관제 $\rightarrow$ 수직 착륙 전술 유도 연계 인터페이스 (Hierarchical Transition)
1. **광역 항법 단계 (GPS Waypoint Navigation)**:
   - 기체 `AMM (Node 03)`은 `CH_FACILITY_BEACON` (50003)에서 GAC가 집약 송출하는 섹터 대표 비콘을 수신하고, 중앙 GPS 체계(`CH_GPS_PING` 60001 / `Base+5`)를 이용하여 목적지 섹터 상공 50~100m 지점(Initial Approach Fix)까지 장거리 자율 비행 궤적을 생성해 `Base+4`로 `FCP (Node 04)`에 하달합니다.
2. **2단계 관제 인가 및 핸드오프 (Two-Stage Handoff)**:
   - 기체 `AMM (Node 03)`은 Tower ATC(`CH 50001`)로 진입을 요청하여 관할 GAC 섹터 채널($Base_{\text{sec}} + 0$)을 하달받습니다.
   - `AMM`은 섹터 채널로 주파수를 변경하여 GAC에 체크인(`MSG_GAC_CHECKIN_REQ`)하고, GAC는 다속성 분배를 통해 가용 착륙패드에 슬롯을 배정(`MSG_ATC_SLOT_ASSIGN` via $Base_{\text{sec}} + 1$)한 후 `AMM`에 패드 전술 채널(`CH_TACTICAL_GUIDANCE` = $Base_{\text{sec}} + 10 + \text{Idx}$)을 최종 하달합니다.
3. **전술 정밀 착륙 및 GPS 안전 백업**:
   - `AMM`은 전술 채널로 핸드오버하여 1Hz(정적 패드) 또는 20Hz(동적 패드)의 전술 가이드(`MSG_FACILITY_STATIC/DYNAMIC_GUIDE`)를 수신하고, 실시간 궤적 세트포인트를 `Base+4`로 `FCP`에 하달하여 수직 하강을 완수합니다.
   - **GPS 페일소프트 백업**: 정적 고정 패드의 경우 전술 무선 통신이 일시 두절되더라도 기체는 사전에 수신된 패드 정적 좌표와 중앙 GPS 수평 좌표($X, Z$), 온보드 고도계($Y$)를 결합하여 비상 복행 없이 안전 착륙을 완수합니다 (타임아웃 복행 면제 규격 준수).

---

### 1.3 코드 경량화 및 Deprecated 운영 정책 (Code Lightweighting & Deprecation Policy)
1. **사양서 명세 원칙 (Specification-First)**: 프로토콜 패킷 타입명 또는 페이로드 필드가 개정될 경우, 구버전 명칭은 사양서 내에 `[DEPRECATED]` 배지를 부여하고 대체 신규 필드명과 변경 이력을 명시하여 문서상에 보존합니다.
2. **코드베이스 경량화 원칙 (Zero-Fallback)**: CC:Tweaked Lua 분산 컴퓨터 환경의 자원 제약(메모리 절약, 20Hz 실시간 루프 성능 보장)을 준수하기 위해, 코드베이스는 사전 이중 호환(Fallback 래퍼, `payload.new or payload.old` 등)을 일체 작성하지 않고 **최신 표준 필드명/패킷명만을 단일 채택**합니다.
3. **런타임 오류 시 복구 원칙 (송신 노드 즉시 패치)**: 구버전 필드/패킷을 전송하는 미갱신 노드로 인해 수신 측에서 `nil` 인덱싱 등의 런타임 오류가 발생할 경우, 수신 측에 임시 폴백 코드를 추가하지 않고 **구버전 패킷을 송신한 발신 노드의 코드를 최신 사양으로 즉시 패치 및 재배포**하여 전역 일원화를 달성합니다.

---

### 1.4 초기 설치 시운전, 좌표계 변환 및 센서 바인딩 규격 (Commissioning, Kinematics & Sensor Binding)

착륙패드 비콘 컴퓨터는 물리적 현장 설치 시점에 컴퓨터 바디 프레임 상대 오프셋 보정, GPS 모뎀 기반 좌표 획득, 그리고 동적 패드 필수 항법 센서 3종 바인딩 절차를 필수적으로 완수해야 합니다.

#### 1.4.1 컴퓨터 바디 프레임 기준 착륙패드 중심 상대 좌표 오프셋 및 3D 기하 변환 (Body-Frame Offset & Kinematics)
1. **설치 물리 위치 분리 및 컴퓨터 바디 좌표계 (Computer Body Frame)**:
   - 비콘 컴퓨터 본체는 하강 기체의 다운워시(Downwash) 풍압, 물리 충돌 방지 및 작업자 시인성을 위해 착륙패드 정중앙이 아닌 **패드 가장자리(Control Box), 지하 기단부 또는 관제 단말 위치**에 설치됩니다.
   - 작업자는 컴퓨터 전면(화면)을 기준으로 착륙패드 정중앙까지의 **컴퓨터 바디 상대 변위 벡터 $\Deltaec{p}_{\text{comp}}$**를 실측 입력합니다:
     $$\Delta\vec{p}_{\text{comp}} = \begin{bmatrix} \Delta p_{\text{forward}} \\ \Delta p_{\text{right}} \\ \Delta p_{\text{up}} \end{bmatrix} \quad \begin{aligned} &\text{전방(+)/후방(-)} [\text{m}] \\ &\text{우측(+)/좌측(-)} [\text{m}] \\ &\text{상방(+)/하방(-)} [\text{m}] \end{aligned}$$
2. **정적 고정 패드 (Static Pad) 2D 수평 회전 변환**:
   - 정적 패드의 정면 방위각 $\psi_0 \in \{0^\circ, 90^\circ, 180^\circ, 270^\circ\}$ (또는 인접 장착된 짐벌 센서 실측 방위각)를 기준으로 마인크래프트 월드 좌표계($+X$: 동쪽, $+Y$: 상방, $+Z$: 남쪽) 상대 변위 $\Delta\vec{p}_{\text{world}}$를 산출합니다:
     $$\begin{cases} \Delta X_{\text{world}} = \Delta p_{\text{forward}} \sin\psi_0 + \Delta p_{\text{right}} \cos\psi_0 \\ \Delta Y_{\text{world}} = \Delta p_{\text{up}} \\ \Delta Z_{\text{world}} = -\Delta p_{\text{forward}} \cos\psi_0 + \Delta p_{\text{right}} \sin\psi_0 \end{cases}$$
   - 정밀 터치다운 중심 좌표: $\vec{p}_{\text{touchdown}} = \vec{p}_{\text{comp}} + \Delta\vec{p}_{\text{world}}$
3. **이동형 동적 패드 (Dynamic Pad) 2단계 선체 프레임 변환 및 실시간 3D 회전 변환**:
   - **Step 1 (선체 바디 프레임 변환)**: 컴퓨터 정면이 선체 선수(Bow, 짐벌 센서 정면) 대비 장착된 방위 오프셋 $\Delta\psi_{\text{mount}} \in \{0^\circ \text{ (선수)}, +90^\circ \text{ (우현)}, 180^\circ \text{ (선미)}, -90^\circ \text{ (좌현)}\}$을 반영하여 선체 바디 변위($\Delta s_{\text{surge}}, \Delta s_{\text{sway}}, \Delta s_{\text{up}}$)로 1차 변환합니다:
     $$\begin{cases} \Delta s_{\text{surge}} = \Delta p_{\text{forward}} \cos\Delta\psi_{\text{mount}} - \Delta p_{\text{right}} \sin\Delta\psi_{\text{mount}} \\ \Delta s_{\text{sway}} = \Delta p_{\text{forward}} \sin\Delta\psi_{\text{mount}} + \Delta p_{\text{right}} \cos\Delta\psi_{\text{mount}} \\ \Delta s_{\text{up}} = \Delta p_{\text{up}} \end{cases}$$
   - **Step 2 (실시간 3D 오일러 회전 행렬 적용)**: 선체 짐벌 센서가 출력하는 3축 자세각(피치 $\theta$, 롤 $\phi$, 요 $\psi$)을 바탕으로 VAS Section 3.2 규격과 완전 일치하는 회전 행렬 $\mathbf{R}(\psi, \theta, \phi)$를 매 50ms(20Hz)마다 적용합니다:
     $$\begin{bmatrix} \Delta X_{\text{world}}(t) \\ \Delta Y_{\text{world}}(t) \\ \Delta Z_{\text{world}}(t) \end{bmatrix} = \Delta s_{\text{surge}} \begin{bmatrix} \cos\theta\sin\psi \\ \sin\theta \\ -\cos\theta\cos\psi \end{bmatrix} + \Delta s_{\text{sway}} \begin{bmatrix} \cos\phi\cos\psi + \sin\phi\sin\theta\sin\psi \\ -\sin\phi\cos\theta \\ \cos\phi\sin\psi - \sin\phi\sin\theta\cos\psi \end{bmatrix} + \Delta s_{\text{up}} \begin{bmatrix} \sin\phi\cos\psi - \cos\phi\sin\theta\sin\psi \\ \cos\phi\cos\theta \\ \sin\phi\sin\psi + \cos\phi\sin\theta\cos\psi \end{bmatrix}$$
   - **터치다운 위치 및 각속도 유도 속도 보정**:
     $$\vec{p}_{\text{touchdown}}(t) = \vec{p}_{\text{comp}}(t) + \Delta\vec{p}_{\text{world}}(t)$$
     $$\vec{v}_{\text{touchdown}}(t) = \vec{v}_{\text{comp}}(t) + \mathbf{R}(\psi, \theta, \phi) \cdot (\vec{\omega}_{\text{rad}} \times \Delta\vec{s}_{\text{body}})$$
     *(단, $\vec{\omega}_{\text{rad}} = [\text{math.rad}(p), \text{math.rad}(q), \text{math.rad}(r)]^T$ 단위 변환 엄수)*

#### 1.4.2 GPS 모뎀 기반 수평 좌표 자동 획득 및 상태별 이중 주기 운용 (GPS Acquisition & Dual-Rate Operation)
1. **자체 GPS 프로토콜 정합 및 전용 응답 채널 (`Base_sec + 5`)**:
   - 바닐라 CC `gps.locate()` API의 브로드캐스트 부하 및 동기 지연을 배제하고, 프로젝트 표준 자체 GPS 시스템([GPS_PROGRAM_SPECIFICATION_AND_ICD.md](../gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md))을 단일 채택합니다.
   - 요청 패킷(`MSG_GPS_REQUEST`)은 `CH_GPS_PING` (60001)으로 송출하며, 응답은 기체 전용 응답 채널($Base+5$)과 대칭되는 섹터 관할 시설물 전용 채널 **`CH_SECTOR_GPS_REPLY` ($Base_{\text{sec}} + 5$)**로 수신합니다.
   - 응답 패킷(`MSG_GPS_RESPONSE`) 수신 시 `payload.targetClient == facilityId` 조건을 검사하여 타 시설물과의 패킷 간섭을 원천 필터링합니다.
2. **정적 패드 (Static Pad) 하이브리드 수평·수직 좌표 획득**:
   - 수평 좌표 $(X, Z)$는 부팅 시 `CH 60001` GPS 질의 1회를 통해 자동 계측 및 메모리에 불변 저장합니다.
   - 수직 고도 $Y$ 및 방위각 $\psi_0$는 인접 장착된 `altitude_sensor` 및 `gimbal_sensor`가 존재할 경우 자동 리딩하고, 무선 모뎀 단독 장착 구성일 경우 초기 TUI 마법사에서 컴퓨터 블록 $Y$ 좌표와 4방위 정면(`N=0°`, `E=90°`, `S=180°`, `W=270°`)을 작업자가 입력합니다.
3. **동적 패드 (Dynamic Pad) 상태 의존형 이중 측위 주기**:
   - **비착륙 상태 전체 (`IDLE`, `OCCUPIED`, `GO_AROUND`, `DEPARTURE_PENDING`)**:
     - 무선 트래픽 절감을 위해 **1Hz** 비동기 GPS 질의(`CH 60001` $\to$ $Base_{\text{sec}}+5$)를 수행합니다.
     - 실측된 패드 중심 좌표 및 자세를 GAC 직속 로컬 백본($Base_{\text{sec}}+1$)의 `MSG_ATC_FACILITY_UPDATE` (`touchdownPoint`, `heading`, `velocity`)로 1Hz 송출하여 GAC의 섹터 종합 맵을 갱신합니다.
   - **착륙 진행 중 (`RESERVED`, `APPROACH_DYNAMIC`)**:
     - **5Hz(200ms)** 비동기 GPS 질의 + **20Hz(50ms)** 온보드 `velocity_sensor` 수치 적분(추측항법 보간) 융합으로 전술 유도 채널($Base_{\text{sec}}+10+\text{Idx}$)에 20Hz 고정밀 `MSG_FACILITY_DYNAMIC_GUIDE`를 실시간 스트리밍합니다.

#### 1.4.3 동적 패드 필수 센서 3종 바인딩 및 이원화 안전 인터록 (Sensor Binding & Dual-Stage Failsafe)
1. **필수 센서 3종 표준 네임스페이스 통일**:
   - Create: Avionics 및 VAS 코어 표준과 일치하도록 다음 3종 센서를 단일 허용합니다:
     - **3축 자세 및 각속도 센서**: `avionics:gimbal_sensor` (무접두 `gimbal_sensor` 지원)
     - **해발 고도 센서**: `avionics:altitude_sensor` (무접두 `altitude_sensor` 지원)
     - **3축 이동 속도 센서**: `avionics:velocity_sensor` (무접두 `velocity_sensor` 지원)
2. **이원화 결손 안전 정책 (Dual-Stage Failsafe Interlock)**:
   - **초기 TUI 셋업 마법사 진행 중 (Setup Stage)**:
     - 필수 센서 3종 중 1개라도 미감지 시 설정을 커밋할 수 없으며, **적색 경고 화면에서 동작을 즉시 강제 중단(`HALT_WITH_WARNING`)**합니다 (`[R]` 재스캔 또는 `[Q]` 종료만 허용).
   - **무인 가동 데몬 중 결손 발생 (Runtime Stage)**:
     - 접근 중인 기체가 존재할 경우 즉시 `MSG_ABORT_APPROACH` (`reason: "SENSOR_FAULT"`)를 전술 채널로 송출하여 즉각 복행을 지시합니다.
     - 직속 GAC에 `MSG_ATC_FACILITY_UPDATE` (`status: "MAINTENANCE"`, `faultCode: "SENSOR_UNAVAILABLE"`)를 송출하여 추가 기체 배정을 차단합니다.
     - 전술 채널 송출을 전면 차단하고, 콘솔에 적색 알람을 표출한 채 **1초(1Hz) 간격으로 백그라운드 센서 자동 재연결(`Auto-Reconnect`)**을 대기합니다. 센서 전원이 복구되면 즉시 `IDLE` (`status: FREE`)로 자율 복귀합니다.

---

## 2. 네트워크 채널 및 노드 토폴로지 (Network Channels & Topology)

착륙패드 시스템은 물리 구동 장치 없이 컴퓨터 본체와 무선 모뎀(Ender Modem)만으로 구성된 순수 무선(All-Wireless) 경량 네트워크를 사용하며, 직속 GAC가 관할하는 섹터 로컬 백본망에 귀속됩니다.

```mermaid
flowchart TD
    ATC["Tier 1: 통합 관제탑 (Tower ATC)<br/>[CH 50001 대공 / CH 50002 광역 백본]"]
    GAC["Tier 2: 지상 구역 관제사 (GAC Node)<br/>[CH 50003 비콘 / Base_sec+0 관제 / Base_sec+1 백본]"]
    PAD["Tier 3: 착륙패드 노드 (Pad Node)<br/>[Base_sec+1 로컬 백본 / Base_sec+10+Idx 전술]<br/>* 순수 소프트웨어 비콘 노드 (무기계식)"]
    AMM["비행기체 게이트웨이 AMM (Node 03)<br/>[CH Base+5 / 50001 / Base_sec+0 / Base_sec+10+Idx]"]

    ATC <==>|"CH 50002 (광역 백본)<br/>MSG_ATC_SECTOR_HANDOFF_REQ / ACK"| GAC
    AMM <==>|"CH 50001 (대공 관제)<br/>광역 진입 요청 / GAC 채널 하달"| ATC
    GAC -.->|"CH 50003 (1Hz 대표 비콘)<br/>MSG_FACILITY_BEACON"| AMM
    AMM <==>|"CH Base_sec+0 (섹터 관제)<br/>체크인 / 패드 배정 인가"| GAC
    GAC <==>|"CH Base_sec+1 (섹터 로컬 백본)<br/>MSG_ATC_SLOT_ASSIGN / ACK<br/>MSG_ATC_FACILITY_UPDATE"| PAD
    PAD <==>|"CH Base_sec+10+Idx (1:1 전술 유도)<br/>STATIC(1Hz) / DYNAMIC(20Hz)"| AMM
    AMM -.->|"CH Base_sec+10+Idx / Base+5<br/>MSG_TOUCHDOWN_COMPLETE (접지 통보)"| PAD
    PAD -.->|"CH Base_sec+10+Idx 및 CH Base_sec+1<br/>MSG_ABORT_APPROACH (긴급 복행)"| AMM
```

### 2.1 채널 할당 표
| 채널 번호 | 채널 식별자 | 송신자 | 수신자 | 전송 주기 | 통신 목적 및 내용 |
| :---: | :---: | :---: | :---: | :---: | :--- |
| **`50001`** | `CH_ATC_COMM` | AMM / Tower ATC | Tower ATC / AMM | 이벤트 | 대공 광역 관제 및 관할 GAC 섹터 채널 이양 교신 |
| **`50002`** | `CH_ATC_FACILITY` | Tower ATC / GAC | GAC / Tower ATC | 1Hz / 이벤트 | 광역 관제탑과 GAC 간 섹터 핸드오프 교신 |
| **`50003`** | `CH_FACILITY_BEACON` | GAC Node (대표) | All (AMM, GCS) | 1Hz | **Sector 0 대표 집약 비콘**: 관할 구역 요약 정보 및 가용 현황 송출 (개별 패드는 직접 송출 중단) |
| **`60001`** | `CH_GPS_PING` | Pad Node | GPS 위성/서버 | 1회(정적) / 1Hz(비착륙) / 5Hz(착륙) | 자체 GPS 서버로 비콘 컴퓨터 물리 위치 질의 (`MSG_GPS_REQUEST`, clientType: "FACILITY") |
| **$Base_{\text{sec}} + 0$** | `CH_GAC_COMM` | AMM / GAC | GAC / AMM | 이벤트 | 기체 체크인(`MSG_GAC_CHECKIN_REQ`), 패드 배정 인가(`MSG_GAC_APPROACH_CLEARANCE`), 로컬 복행 ($Base_{\text{sec}} = 50001 + S \times 200$) |
| **$Base_{\text{sec}} + 1$** | `CH_SECTOR_FACILITY` | Pad Node / GAC | GAC / Pad Node | 1Hz / 이벤트 | **직속 섹터 로컬 백본**: GAC와 패드 간 슬롯 예약(`MSG_ATC_SLOT_ASSIGN/ACK`), 상태/위치 동기화(`MSG_ATC_FACILITY_UPDATE`), 복행 제어 |
| **$Base_{\text{sec}} + 5$** | `CH_SECTOR_GPS_REPLY` | GPS 위성/서버 | Pad Node | 1회 / 1Hz / 5Hz | **섹터 관할 시설물 전용 GPS 응답 수신**: `targetClient == facilityId` 필터링 기반 측위 수신 (`MSG_GPS_RESPONSE`) |
| **$Base_{\text{sec}} + 10 + \text{Idx}$** | `CH_TACTICAL_GUIDANCE` | Pad Node / AMM | AMM / Pad Node | 1Hz (정적)<br/>20Hz (동적) | **1:1 정밀 전술 유도 스트리밍** (`MSG_FACILITY_STATIC/DYNAMIC_GUIDE`), 접지 통보 (`MSG_TOUCHDOWN_COMPLETE`), 복행 지시 (`MSG_ABORT_APPROACH`) |
| **`Base + 5`** | `CH_EXTERNAL_COMM` | Pad Node | AMM (Node 03) | 이벤트 | 기체 전용 응답 채널 (점유 확인 통보) |

### 2.2 노드 하드웨어 구성 및 페리페럴 바인딩 (Node Hardware & Peripherals)

| 시설물 유형 | 필수 장비 구성 | 인터페이스/페리페럴 | 역할 및 기능 |
| :--- | :--- | :--- | :--- |
| **공통 (Common)** | CC:Tweaked 컴퓨터 본체 (Advanced Computer 권장) | `modem` (Ender Modem) | 로컬 백본($Base_{\text{sec}}+1$), GPS($60001, Base_{\text{sec}}+5$) 및 전술 채널($Base_{\text{sec}}+10+\text{Idx}$) 무선 송수신 |
| **정적 패드 (Static)** | 무선 모뎀 단독 장착 (센서 선택) | `altitude_sensor`, `gimbal_sensor` (옵션) | 사전 보정된 터치다운 중심 좌표 기반 1Hz 가이드 송출 (모뎀 단독 시 TUI 수동 Y/방위 입력) |
| **동적 패드 (Dynamic)** | 3축 자세 및 각속도 센서 | `avionics:gimbal_sensor` (무접두 지원) | 실시간 Pitch/Roll/Yaw 및 3축 각속도 계측 (선체 3D 회전 변환 및 $\theta_{tilt}$ 안정성 판정) |
| **동적 패드 (Dynamic)** | 해발 고도 센서 | `avionics:altitude_sensor` (무접두 지원) | 실시간 해발 고도($Y$) 및 수직 요동 계측 |
| **동적 패드 (Dynamic)** | 3차원 속도 센서 | `avionics:velocity_sensor` (무접두 지원) | 실시간 3차원 이동 속도 벡터($\vec{v}$) 계측 (20Hz 추측항법 적분 융합 및 Heave 속도 $v_y$ 감시) |

---

## 3. 통신 패킷 상세 규격 (Message Envelope & Payload Specification)

모든 통신은 표준 공통 Lua 테이블 엔벨로프(`ver`, `domainId`, `seq`, `type`, `time`, `payload`)를 필수 준수합니다.

### 3.1 광역 상태 비콘 (`MSG_FACILITY_BEACON`, CH 50003, 1Hz)
> [!NOTE]
> **GAC 집약 송출 원칙**: 본 패킷은 개별 패드가 독립 송출하지 않고, 상위 지상 구역 관제사(GAC)가 관할 구역 내 시설물 전체 현황을 수집하여 단일 대표 패킷으로 송출합니다. 패드 노드는 평시 CH 50003을 열지 않아 무선 모뎀 수신 큐를 절약합니다.
```lua
{
    ver = "1.9.5",
    domainId = "GAC_APRON_01",
    seq = 10021,
    type = "MSG_FACILITY_BEACON",
    time = 1729850000000,
    payload = {
        sectorId = 1,
        gacChannel = 50201,                  -- 해당 섹터 관제 채널 (Base_sec + 0)
        totalPads = 4,
        freePads = 3,
        maxSupportedWeight = 45000.0,
        maxClearanceRadius = 6.0,
        surfaceWind = { speed = 2.4, direction = 195.0 }
    }
}
```

---

### 3.2 고정 패드 정밀 유도 패킷 (`MSG_FACILITY_STATIC_GUIDE`, $Base_{\text{sec}}+10+\text{Idx}$, 1Hz)
좌표가 불변인 육상 고정 패드 전용 패킷입니다. 속도/가속도 필드가 제외되어 대역폭을 절감합니다.
```lua
{
    ver = "1.9.5",
    domainId = "PAD_BRAVO_01",
    seq = 10450,
    type = "MSG_FACILITY_STATIC_GUIDE",
    time = 1729850010000,
    payload = {
        facilityId = "PAD_BRAVO_01",
        targetAircraft = "AIRCRAFT_01",
        touchdownPoint = {                   -- 정밀 터치다운 중심 좌표 (Minecraft World Coordinates: X_MC, Y_MC, Z_MC)
            x = 1250.0,
            y = 65.0,
            z = -820.0
        },
        approachHeading = 180.0,             -- 권장 진입 헤딩 (deg, 진북 0°)
        safeDescentRate = 1.0,               -- 최대 허용 수직 하강률 (m/s)
        clearanceZoneRadius = 5.0,           -- 안전 반경 (m)
        surfaceWind = {                      -- 지상 국지풍 정보
            speed = 2.4,                     -- 풍속 (m/s)
            direction = 195.0                -- 풍향 (풍상 방위각, deg)
        },
        abortAlert = false                   -- 긴급 복행 요구 플래그 (true 시 즉시 Go-Around)
    }
}
```

---

### 3.3 동적 패드 실시간 동역학 스트리밍 (`MSG_FACILITY_DYNAMIC_GUIDE`, $Base_{\text{sec}}+10+\text{Idx}$, 20Hz)
바지선, 항공모함, 열차 등 이동 플랫폼 상의 패드 전용 패킷입니다. 실시간 3축 동역학과 함께 **갑판 안정성 판정 결과(`deckStatus`, `landingPermitted`)**를 포함하여 20Hz로 송출됩니다.
```lua
{
    ver = "1.9.5",
    domainId = "BARGE_PAD_02",
    seq = 45100,
    type = "MSG_FACILITY_DYNAMIC_GUIDE",
    time = 1729850020050,
    payload = {
        facilityId = "BARGE_PAD_02",
        targetAircraft = "AIRCRAFT_01",
        touchdownPoint = {                   -- 현재 시각 t에서의 패드 중심 3D 위치
            x = 840.25,
            y = 62.10,
            z = 1120.80
        },
        velocity = {                         -- 패드 3축 이동 속도 벡터 (m/s)
            vx = 6.20,
            vy = -0.15,                      -- 파도에 의한 상하 요동 (Heave)
            vz = 1.10
        },
        acceleration = {                     -- 패드 3축 이동 가속도 벡터 (m/s²)
            ax = 0.05,
            ay = 0.85,
            az = -0.02
        },
        attitude = {                         -- 패드 갑판 3축 자세각 (deg)
            pitch = 1.2,
            roll = -2.5,
            yaw = 85.0
        },
        angularRates = {                     -- 3축 각속도 (deg/s)
            pitchRate = 0.4,
            rollRate = -0.8,
            yawRate = 0.05
        },
        -- 갑판 요동 실시간 안전 판정 플래그 (Section 5.2 수식 연동)
        deckStatus = "STABLE",               -- "STABLE" (θ_tilt <= 10.0° and |vy| <= 2.5m/s) | "DANGEROUS"
        landingPermitted = true,             -- true: 최종 접지 허용, false: 호버 유지/접지 보류
        tiltAngleDeg = 2.77,                 -- 현재 합성 경사각 sqrt(pitch^2 + roll^2)
        heaveRateMps = -0.15,                -- 현재 수직 요동 속도 vy
        abortAlert = false                   -- 복행 발동 플래그
    }
}
```

---

### 3.4 접지 통보 인터페이스 (`MSG_TOUCHDOWN_COMPLETE`, $Base_{\text{sec}}+10+\text{Idx}$ / Base+5 $\rightarrow$ Pad / GAC)
기체의 온보드 제어기(수직 하강 정지 $v_y \approx 0$)가 물리 접지를 판정했을 때 송출하여 패드 상태를 즉시 `OCCUPIED`로 전이시키고 직속 GAC에 통보합니다.
```lua
{
    ver = "1.9.5",
    domainId = "AIRCRAFT_01",
    seq = 512,
    type = "MSG_TOUCHDOWN_COMPLETE",
    time = 1729850025000,
    payload = {
        facilityId = "PAD_BRAVO_01",
        touchdownTime = 1729850025000,
        craftState = "GROUND_IDLE"
    }
}
```

---

### 3.5 GAC 섹터 로컬 백본 통신 패킷 규격 ($Base_{\text{sec}} + 1$)

#### 1. GAC 슬롯 할당 (`MSG_ATC_SLOT_ASSIGN`, $Base_{\text{sec}}+1$, GAC $\rightarrow$ Pad)
직속 GAC가 기체에게 최종 접근 인가를 내리기 전 패드 노드에 슬롯을 배정합니다.
```lua
{
    ver = "1.9.5",
    domainId = "GAC_APRON_01",
    seq = 501,
    type = "MSG_ATC_SLOT_ASSIGN",
    time = 1729850005000,
    payload = {
        facilityId = "PAD_BRAVO_01",
        aircraftId = "AIRCRAFT_01",
        airframeType = "VECTORED_VTOL",
        slotDurationSec = 120,               -- 유효 슬롯 제한시간 (초)
        tacticalChannel = 50211              -- 전술 채널 (Base_sec + 10 + FacilityID)
    }
}
```

#### 2. 패드 슬롯 응답 (`MSG_ATC_SLOT_ACK`, $Base_{\text{sec}}+1$, Pad $\rightarrow$ GAC)
패드 노드가 직속 GAC의 슬롯 배정 요청을 승인 또는 거절합니다.
```lua
{
    ver = "1.9.5",
    domainId = "PAD_BRAVO_01",
    seq = 10451,
    type = "MSG_ATC_SLOT_ACK",
    time = 1729850005100,
    payload = {
        facilityId = "PAD_BRAVO_01",
        aircraftId = "AIRCRAFT_01",
        status = "ACCEPTED",                 -- "ACCEPTED" | "REJECTED"
        rejectReason = nil,                  -- "OCCUPIED", "MAINTENANCE", "OVERWEIGHT"
        tacticalChannel = 50211
    }
}
```

#### 3. 패드 상태 갱신 통보 (`MSG_ATC_FACILITY_UPDATE`, $Base_{\text{sec}}+1$, Pad $\leftrightarrow$ GAC 양방향)
공유 로컬 백본 상에서 시설물 간 충돌을 방지하기 위해 엄격한 `facilityId` 타겟팅 단일 스키마를 적용합니다. 동적 패드의 경우 1Hz 주기 위치 동기화 필드(`touchdownPoint`, `heading`, `velocity`)를 포함하여 송출합니다.
```lua
{
    ver = "1.9.5",
    domainId = "PAD_BRAVO_01",              -- 발신자에 따라 PAD_BRAVO_01 또는 GAC_APRON_01
    seq = 10452,
    type = "MSG_ATC_FACILITY_UPDATE",
    time = 1729850025100,
    payload = {
        facilityId = "PAD_BRAVO_01",
        status = "OCCUPIED",                 -- "FREE", "RESERVED", "OCCUPIED", "MAINTENANCE"
        currentCraft = "AIRCRAFT_01",        -- FREE 전환 시 nil
        faultCode = nil,                     -- MAINTENANCE 상태 시 오류 사유 ("SENSOR_UNAVAILABLE", "CALIBRATION_PENDING" 등)
        -- 동적 패드 1Hz 평시 측위 동기화 선택 필드
        touchdownPoint = {                   -- 현재 터치다운 중심 3D 좌표 (동적 패드 한정)
            x = 840.25,
            y = 62.10,
            z = 1120.80
        },
        heading = 85.0,                      -- 현재 선수/패드 방위각 (deg, 동적 패드 한정)
        velocity = {                         -- 현재 이동 속도 벡터 (m/s, 동적 패드 한정)
            vx = 6.20,
            vy = -0.15,
            vz = 1.10
        }
    }
}
```

#### 4. 긴급 복행 지시 (`MSG_ABORT_APPROACH`, $Base_{\text{sec}}+10+\text{Idx}$ 및 $Base_{\text{sec}}+1$)
패드 또는 GAC가 접근 중인 기체에 즉시 복행을 하달합니다.
```lua
{
    ver = "1.9.5",
    domainId = "PAD_BRAVO_01",              -- 패드 발신 시 PAD_BRAVO_01, GAC 발신 시 GAC_APRON_01
    seq = 10455,
    type = "MSG_ABORT_APPROACH",
    time = 1729850022000,
    payload = {
        facilityId = "PAD_BRAVO_01",
        aircraftId = "AIRCRAFT_01",
        reason = "DECK_UNSTABLE",            -- "DECK_UNSTABLE", "OBSTACLE_DETECTED", "GAC_ORDER", "TIMEOUT"
        recommendedClimbAltitude = 100.0     -- 안전 복행 권장 고도 (m)
    }
}
```

> [!NOTE]
> **무기계식 경량화 원칙**: 본 착륙패드는 순수 가상 좌표 비콘으로 운영되므로, 물리 클램프 체결(`MSG_PAD_CLAMP_STATUS`) 및 자동 급유/충전 스트리밍(`MSG_PAD_SERVICE_STATUS`) 패킷 시퀀스가 배제되었습니다. 급유 및 정비는 착륙 완료 후 별도의 외부 지상 지원 장비 또는 작업자에 의해 수동/선택적으로 처리됩니다.

---

## 4. 유한 상태 기계 및 동작 시퀀스 (FSM & Sequence)

### 4.1 착륙패드 FSM 상태 전이도

```mermaid
stateDiagram-v2
    [*] --> INIT : 부팅 핫키(3초) 또는 설정 로드
    INIT --> IDLE : 오프셋 보정 완료 및 센서 정상 (status: FREE)
    INIT --> MAINTENANCE : 셋업 중단(HALT_WITH_WARNING) 또는 부팅 시 필수 센서 미탐색
    
    IDLE --> RESERVED : GAC 슬롯 인가 수신 (MSG_ATC_SLOT_ASSIGN)
    note right of IDLE : 동적 패드: 1Hz GPS + GAC 백본 보고
    
    RESERVED --> APPROACH_STATIC : 정적 패드 (1Hz 가이드 스트리밍)
    RESERVED --> APPROACH_DYNAMIC : 동적 패드 (5Hz GPS + 20Hz 속도적분 -> 20Hz 스트리밍)
    RESERVED --> IDLE : 120초 슬롯 타임아웃 만료 (기체 미도착)
    
    APPROACH_STATIC --> OCCUPIED : 접지 통보 수신 (MSG_TOUCHDOWN_COMPLETE)
    APPROACH_DYNAMIC --> OCCUPIED : 접지 통보 수신 (MSG_TOUCHDOWN_COMPLETE)
    
    APPROACH_DYNAMIC --> GO_AROUND : deckStatus == DANGEROUS 3초 지속 OR MSG_ABORT_APPROACH OR 타임아웃
    APPROACH_STATIC --> GO_AROUND : MSG_ABORT_APPROACH 수신 OR 슬롯 타임아웃
    
    GO_AROUND --> IDLE : GAC 이탈 확인 및 패드 개방 명령 수신 (MSG_ATC_FACILITY_UPDATE, status: FREE)
    
    OCCUPIED --> DEPARTURE_PENDING : GAC 이륙 통보 수신
    DEPARTURE_PENDING --> IDLE : 기체 안전 이탈 확인 (GAC 명령: status: FREE)
    
    APPROACH_DYNAMIC --> MAINTENANCE : 런타임 센서 결손 (MSG_ABORT_APPROACH 송출)
    APPROACH_STATIC --> MAINTENANCE : 런타임 모뎀 결손
    MAINTENANCE --> IDLE : 1초(1Hz) 백그라운드 센서 자동 재연결(Auto-Reconnect) 복귀
```

### 4.2 착륙 및 이륙 3-Tier 관제 시퀀스 다이어그램

```mermaid
sequenceDiagram
    autonumber
    participant A as 기체 AMM (Node 03)
    participant ATC as 광역 관제탑 (Tower ATC)
    participant GAC as 지상 구역 관제사 (GAC Node)
    participant P as 착륙패드 노드 (Pad Node)

    Note over GAC: 1Hz 섹터 대표 비콘 송출 (CH 50003, freePads >= 1)
    Note over P: 로컬 백본 (CH 50202) 대기 중 (status: FREE)
    Note over A: 착륙 필요 판정 (RTH 또는 조종사 지시)
    
    Note over A,ATC: 1단계: 광역 진입 및 섹터 관제 채널 하달
    A->>ATC: MSG_ATC_APPROACH_REQ (CH 50001)<br/>[targetSector: 1, airframeType: VECTORED_VTOL]
    ATC->>GAC: MSG_ATC_SECTOR_HANDOFF_REQ (CH 50002)<br/>[aircraftId: AIRCRAFT_01, sectorId: 1]
    GAC-->>ATC: MSG_ATC_SECTOR_HANDOFF_ACK (CH 50002) [ACCEPTED, gacChannel: 50201]
    ATC->>A: MSG_ATC_HANDOFF_CLEARANCE (CH 50001)<br/>[sectorId: 1, gacChannel: 50201]

    Note over A,GAC: 2단계: 섹터 체크인 및 패드 배정
    A->>GAC: MSG_GAC_CHECKIN_REQ (CH 50201)<br/>[aircraftId: AIRCRAFT_01, weight: 12500.0, radius: 4.0]
    Note over GAC: 다속성 최적 패드 분배 알고리즘 J(P_i) 실행 -> PAD_BRAVO_01 낙점
    GAC->>P: MSG_ATC_SLOT_ASSIGN (CH 50202)<br/>[facilityId: PAD_BRAVO_01, aircraftId: AIRCRAFT_01, slotSec: 120]
    P-->>GAC: MSG_ATC_SLOT_ACK (CH 50202) [ACCEPTED, tacticalChannel: 50211]
    GAC->>A: MSG_GAC_APPROACH_CLEARANCE (CH 50201)<br/>[facilityId: PAD_BRAVO_01, tacticalChannel: 50211, mobility: DYNAMIC]

    Note over A,P: 3단계: 전술 채널 (CH 50211) 핸드오버 및 정밀 착륙
    alt 정적 패드 (STATIC)
        loop 1Hz 주기
            P->>A: MSG_FACILITY_STATIC_GUIDE (CH 50211)<br/>[touchdownPoint, approachHeading: 180°, wind]
        end
    else 동적 패드 (DYNAMIC)
        loop 20Hz 주기 (AMM 2차 테일러 외삽 -> Base+4 FCP 추종)
            P->>A: MSG_FACILITY_DYNAMIC_GUIDE (CH 50211)<br/>[touchdownPoint(t), vel, accel, attitude, deckStatus, landingPermitted]
        end
    end

    alt 정상 착륙 시나리오
        Note over A: landingPermitted == true 확인 후 최종 하강 궤적 하달/접지
        A->>P: MSG_TOUCHDOWN_COMPLETE (CH 50211)<br/>[facilityId: PAD_BRAVO_01, craftState: GROUND_IDLE]
        P->>GAC: MSG_ATC_FACILITY_UPDATE (CH 50202)<br/>[facilityId: PAD_BRAVO_01, status: OCCUPIED, currentCraft: AIRCRAFT_01]
        Note over P: 패드 점유(OCCUPIED) 확정 (외부 급유/정비 대기)
    else 요동 위험 / 국지 복행 시나리오 (Go-Around)
        Note over P: deckStatus == DANGEROUS 3초 지속 감지
        P->>A: MSG_ABORT_APPROACH (CH 50211) [reason: DECK_UNSTABLE]
        P->>GAC: MSG_ABORT_APPROACH (CH 50202) [reason: DECK_UNSTABLE]
        Note over P: FSM GO_AROUND 상태 전이 (패드 임의 배정 차단)
        Note over A: 급상승 복행 궤적 하달 (+30m 안전고도 도달)
        A->>GAC: MSG_GAC_ABORT_CLEAR (CH 50201) [craft: AIRCRAFT_01, alt: 100m]
        Note over GAC: 관할 내 다른 가용 패드(PAD_02) 즉시 탐색 및 재배정
        GAC->>P: MSG_ATC_FACILITY_UPDATE (CH 50202) [facilityId: PAD_BRAVO_01, status: FREE]
    end

    Note over A: 임무 완료 후 이륙 요청
    A->>GAC: MSG_GAC_DEPARTURE_REQ (CH 50201)
    GAC->>A: MSG_GAC_DEPARTURE_CLEARANCE (CH 50201) [climbAlt: 100.0, towerAtcChannel: 50001]
    
    Note over A: 수직 상승 이륙 개시 및 패드 영역 이탈
    A->>GAC: MSG_GAC_DEPARTURE_COMPLETE (CH 50201)
    GAC->>P: MSG_ATC_FACILITY_UPDATE (CH 50202) [facilityId: PAD_BRAVO_01, status: FREE]
    Note over P: 패드 개방 (IDLE, FREE 복귀)
    A->>ATC: MSG_ATC_DEPARTURE_COMPLETE (CH 50001) [광역 공역 복귀]
```

---

## 5. 수치해석 및 페일세이프 알고리즘 (Algorithms & Failsafe)

### 5.1 동적 패드 2차 추측항법 보간 (Dead Reckoning Extrapolation)
동적 패드 모드에서 기체 `AMM (Node 03)`의 `trajectory_generator`는 20Hz 루프에서 지연 시간 $\Delta t = (t_{current} - t_{packet})$ 동안 테일러 2차 확장을 적용하여 실시간 패드 예측 위치·속도 및 접근 궤적 세트포인트(`MSG_TRAJECTORY_SETPOINT`)를 산출한 뒤 `Base+4`(`CH_TRAJECTORY_CMD`)로 `FCP (Node 04)`에 전달합니다.

$$\vec{p}_{pad}(t) = \vec{p}_0 + \vec{v}_0 \Delta t + \frac{1}{2} \vec{a}_0 \Delta t^2$$

$$\vec{v}_{pad}(t) = \vec{v}_0 + \vec{a}_0 \Delta t$$

FCP 외루프 요구 가속도 피드포워드 벡터(`AMM` 목표 궤적 추종):
$$\vec{a}_{cmd} = \vec{a}_{pad}(t) + K_p (\vec{p}_{pad}(t) - \vec{p}_{craft}) + K_d (\vec{v}_{pad}(t) - \vec{v}_{craft})$$

---

### 5.2 동적 패드 갑판 안정성(Deck Stability) 수학적 모델

동적 착륙패드는 20Hz 실행 루프에서 센서 텔레메트리(Pitch, Roll, 수직속도 $v_y$)를 기반으로 갑판 요동 안정성을 매 틱 평가합니다:

1. **합성 경사각 연산 (Combined Deck Tilt)**:
   $$\theta_{tilt} = \sqrt{\theta_{pitch}^2 + \theta_{roll}^2} \quad [\text{deg}]$$

2. **안정성 상태 평가 (Stability State Evaluation)**:
   $$\text{deckStatus} = \begin{cases} \text{"STABLE"}, & \text{if } \theta_{tilt} \le 10.0^\circ \text{ and } |v_{y,pad}| \le 2.5\text{ m/s} \\ \text{"DANGEROUS"}, & \text{otherwise} \end{cases}$$

3. **최종 접지 인가 플래그 (Landing Permitted Flag)**:
   $$\text{landingPermitted} = (\text{deckStatus} == \text{"STABLE"})$$

- 기체 `AMM (Node 03)`은 `landingPermitted == true`일 때만 최종 지면 접지 터치다운 강하 궤적을 하달하며, `deckStatus == "DANGEROUS"` 상태에서는 상공 3~5m 지점에서 호버 홀드(Hover Hold) 세트포인트를 유지해 `Base+4`로 `FCP`에 전달합니다. 만약 위험 상태가 3.0초 이상 지속되면 패드 노드가 `MSG_ABORT_APPROACH`를 송출하여 강제 복행을 발동합니다.

---

### 5.3 페일세이프 임계값 및 대응 매트릭스
| 이상 상황 | 감지 조건 | 적용 대상 | 페일세이프 조치 |
| :--- | :--- | :---: | :--- |
| **무선 하트비트 두절** | 최종 접근 중 $300\text{ms}$ 무수신 (기체 `AMM` 단독 감지) | 동적 패드 | 즉시 수직 상승 복행 궤적(`Base+4`) 하달, GAC 섹터 관제선 복귀 |
| **무선 하트비트 두절** | 무신호 지속 | 고정 패드 | **복행 면제**: 정적 좌표 기반 GPS/고도계로 착륙 강행 |
| **갑판 동역학 위험 요동** | $\theta_{tilt} > 10.0^\circ$ 또는 $\|v_{y,pad}\| > 2.5\text{ m/s}$ 3.0초 지속 | 동적 패드 | 패드가 `MSG_ABORT_APPROACH` 발신, 기체 급상승 복행 |
| **지상 장애물 감지** | 초음파/적외선/관제 센서 차폐 | 공통 | 패드 노드가 `MSG_ABORT_APPROACH` 즉시 송출, 기체 급상승 복행 |
| **접지 미확인 타임아웃** | 최저 강하 고도 도달 후 $10.0\text{초}$ 초과 | 공통 | 착륙 중단, 복행 고도로 상승 후 체공 선회 |
| **슬롯 만료 타임아웃** | 슬롯 인가 후 $120\text{초}$ 동안 접지 미보고 | 공통 | 패드 `GO_AROUND` 전이 후 GAC에 슬롯 만료 보고 및 `FREE` 리셋 |
| **동적 패드 센서 결손/두절** | 부팅 시 미탐색 또는 런타임 중 $300\text{ms}$ I/O 실패 | 동적 패드 | 즉시 `MAINTENANCE` 격리, 접근 기체에 `MSG_ABORT_APPROACH` (`reason: SENSOR_FAULT`) 발신 및 GAC 통보 |

---

## 6. 착륙패드 비콘 설치 셋업 마법사 및 TUI 운용 규격 (Commissioning Wizard & TUI)

현장 설치 작업자의 편의성 증진과 공간 인지 무결성 확보를 위해, 착륙패드 비콘 프로그램은 대화형 터미널 UI(TUI) 기반 5단계 셋업 마법사와 3초 핫키 부팅 시퀀스를 제공합니다.

### 6.1 부팅 카운트다운 및 핫키 FSM (`Boot Countdown & Hotkey FSM`)

```mermaid
stateDiagram-v2
    [*] --> BOOT_CHECK : 프로그램 구동 (main.lua)
    BOOT_CHECK --> SETUP_WIZARD : /landing_pad/config.json 부재 시
    BOOT_CHECK --> COUNTDOWN_3S : config.json 존재 시
    
    COUNTDOWN_3S --> SETUP_WIZARD : 3초 이내 [S] 키 입력
    COUNTDOWN_3S --> DAEMON_RUN : 3초 타임아웃 경과 (무인 자동 가동)
    
    SETUP_WIZARD --> CONFIG_COMMITTED : Step 1~5 완료 및 [Y] 확인
    SETUP_WIZARD --> BOOT_ABORT : [Q] 강제 취소 또는 동적 센서 미감지 탈출
    CONFIG_COMMITTED --> DAEMON_RUN : 신규 설정 저장 후 즉시 데몬 개시
```

1. **설정 파일 검사**: `/landing_pad/config.json` 존재 여부를 검사합니다.
2. **카운트다운 대기 (3초)**: 기존 설정이 존재할 경우 `3... 2... 1...` 카운트다운을 터미널에 표시하며, 3초 동안 키 입력을 논블로킹 대기합니다.
3. **핫키 분기**:
   - `[S]` 키 입력: 기존 설정을 덮어쓰기 위한 **5단계 대화형 셋업 마법사**로 진입합니다.
   - 타임아웃(3.0초) 경과: 즉시 무인 가동 모드(**`DAEMON_RUN`**)로 직행합니다.

### 6.2 5단계 대화형 TUI 마법사 워크플로우 (Interactive Wizard Workflow)

#### Step 1: 무선 모뎀 스캔 및 식별자/채널 설정
1. 무선 모뎀(`modem`, `isWireless() == true`)을 자동 스캔하여 바인딩합니다. 미장착 시 진행을 차단합니다.
2. 관할 섹터 번호 $S$ (기본값: `1`) 및 착륙패드 색인 $Idx$ (기본값: `1`)를 입력받습니다.
3. 고유 시설물 식별자 `facilityId` (예: `PAD_BRAVO_01`)를 입력받습니다.
4. 채널을 자동 산출합니다:
   - GAC 섹터 관제 채널: $Base_{\text{sec}} + 0 = 50001 + S \times 200$
   - 섹터 로컬 백본 채널: $Base_{\text{sec}} + 1$
   - 섹터 시설물 GPS 응답 채널: $Base_{\text{sec}} + 5$
   - 패드 전술 유도 채널: $Base_{\text{sec}} + 10 + Idx$

#### Step 2: 시설물 구동 모드 선택 (`STATIC` vs `DYNAMIC`)
- `[1] STATIC (육상 고정형 패드)`: 좌표 불변, 1Hz 하트비트 가이드 송출.
- `[2] DYNAMIC (선박/모선 이동형 패드)`: 실시간 3D 자세/속도 융합, 20Hz 고속 스트리밍.

#### Step 3: 센서 탐색, 방위 정렬 및 초기 GPS 측위
1. **정적 패드 (`STATIC`)**:
   - `altitude_sensor` 및 `gimbal_sensor` 연결 여부를 자동 스캔합니다.
   - 센서 존재 시: $Y$ 고도 및 정면 방위각 $\psi_0$ 자동 취득.
   - 센서 부재 시 (모뎀 단독): 컴퓨터 $Y$ 고도(정수/실수)와 정면 4방위(`N=0°`, `E=90°`, `S=180°`, `W=270°`)를 작업자가 입력합니다.
   - `CH 60001`로 `MSG_GPS_REQUEST`를 1회 송출하고, $Base_{\text{sec}} + 5$에서 `MSG_GPS_RESPONSE`를 수신하여 컴퓨터 물리 좌표 $(X_{\text{comp}}, Z_{\text{comp}})$를 자동 획득합니다.
2. **동적 패드 (`DYNAMIC`)**:
   - 필수 3종 센서(`avionics:gimbal_sensor`, `avionics:altitude_sensor`, `avionics:velocity_sensor`)를 전수 검사합니다.
   - **결손 시 즉시 중단 (`HALT_WITH_WARNING`)**: 1개라도 미감지 시 적색 경고 화면을 표출하고 마법사 진행 및 저장을 금지합니다 (`[R]` 재스캔 / `[Q]` 종료만 지원).
   - 정상 감지 시: 선체 대비 컴퓨터 장착 방위 오프셋 $\Delta\psi_{\text{mount}} \in \{0^\circ \text{ 선수}, +90^\circ \text{ 우현}, 180^\circ \text{ 선미}, -90^\circ \text{ 좌현}\}$을 작업자에게 선택받습니다.
   - `CH 60001` 및 $Base_{\text{sec}} + 5$를 통해 실시간 GPS 수평 좌표 획득 테스트를 수행하고 센서 라이브 계측치를 표출합니다.

#### Step 4: 컴퓨터 바디 프레임 오프셋 및 운용 제원 입력
1. 컴퓨터 본체 정면 기준 착륙패드 정중앙까지의 상대 변위 입력:
   - `Forward Offset (m)`: 전방 $(+)$ / 후방 $(-)$
   - `Right Offset (m)`: 우측 $(+)$ / 좌측 $(-)$
   - `Up Offset (m)`: 상방 $(+)$ / 하방 $(-)$
2. 운용 한계 제원 입력 (기본값 제공):
   - 권장 진입 방위각 `approachHeading` (deg, 기본: `180.0`)
   - 최대 허용 강하율 `safeDescentRate` (m/s, 기본: `1.0`)
   - 안전 구역 반경 `clearanceZoneRadius` (m, 기본: `5.0`)
   - 최대 지지 하중 `maxSupportedWeight` (kg, 기본: `45000.0`)
3. **실시간 좌표 프리뷰**: 현재 입력된 오프셋이 적용된 참 월드 좌표 $\vec{p}_{\text{touchdown}}$을 계산하여 화면에 표시하고 작업자의 시각적 검증을 거칩니다.

#### Step 5: 설정 확인, 원자적 저장 및 자동 가동
1. 구성된 전체 설정 요약 화면을 표출하고 `[Y/N]` 최종 승인을 요청합니다.
2. 승인 시 `/landing_pad/config.json`에 원자적(Atomic) 직렬화 저장을 수행합니다.
3. 2초 후 무인 가동 모드(`DAEMON_RUN`)로 자동 진입합니다.

---

### 6.3 51×19 표준 터미널 UI 와이어프레임 (ASCII Wireframes)

CC:Tweaked Advanced Computer의 표준 해상도인 **51×19 텍스트 터미널** 기준 UI 레이아웃 규격입니다.

#### 1) 부팅 카운트다운 화면 (`COUNTDOWN_3S`)
```text
+-------------------------------------------------+
|   CREATE: AERONAUTICS LANDING PAD CONTROLLER    |
|   Facility ID: PAD_BRAVO_01  |  Mode: DYNAMIC   |
+-------------------------------------------------+
|                                                 |
|   Existing configuration detected.              |
|                                                 |
|   Starting autonomous daemon in:                |
|                                                 |
|                    [ 2 ]                        |
|                                                 |
|   Press [S] to enter Setup Wizard               |
|   Press [D] to start Daemon immediately         |
|                                                 |
|   Sector Base: 50201 | Tactical Ch: 50211       |
+-------------------------------------------------+
| Status: BOOT_COUNTDOWN           [CraftOS 1.10] |
+-------------------------------------------------+
```

#### 2) Step 4 오프셋 파라미터 입력 및 좌표 프리뷰 화면
```text
+-------------------------------------------------+
|   LANDING PAD COMMISSIONING WIZARD (Step 4/5)   |
|   Computer Body-Frame Offset Calibration        |
+-------------------------------------------------+
| Enter relative distance from computer front:    |
|   Forward (+)/Back(-) [m] : 12.0                |
|   Right  (+)/Left(-) [m] : -4.5                 |
|   Up     (+)/Down(-) [m] : 1.2                  |
|                                                 |
| Mounting Yaw Offset : +90 deg (Starboard)       |
|                                                 |
| [LIVE KINEMATICS PREVIEW]                       |
|   Comp Pos  : X=1240.0, Y=64.0, Z=-824.5        |
|   Pad Center: X=1252.0, Y=65.2, Z=-820.0        |
|                                                 |
| Press [ENTER] to confirm values                 |
+-------------------------------------------------+
| [B] Back           [R] Recalculate     [Q] Quit |
+-------------------------------------------------+
```

#### 3) Step 3 동적 패드 필수 센서 미감지 강제 중단 화면 (`HALT_WITH_WARNING`)
```text
+-------------------------------------------------+
|   LANDING PAD COMMISSIONING WIZARD (Step 3/5)   |
|   * CRITICAL HARDWARE ERROR: SENSOR MISSING *   |
+-------------------------------------------------+
| Dynamic pad mode requires 3 physical sensors.   |
| Current peripheral scan results:                |
|                                                 |
|   [FAIL] avionics:gimbal_sensor   : NOT FOUND   |
|   [ OK ] avionics:altitude_sensor : CONNECTED   |
|   [FAIL] avionics:velocity_sensor : NOT FOUND   |
|                                                 |
| * CANNOT PROCEED WITH CURRENT HARDWARE SETUP *  |
| Configuration commit is locked to prevent crash |
| Check wired modem cables and sensor power.      |
|                                                 |
| Press [R] to Rescan      Press [Q] to Abort     |
+-------------------------------------------------+
| Status: HALT_WITH_WARNING        [CANNOT SAVE]  |
+-------------------------------------------------+
```

#### 4) Step 3 동적 패드 센서 정상 라이브 검증 화면
```text
+-------------------------------------------------+
|   LANDING PAD COMMISSIONING WIZARD (Step 3/5)   |
|   Dynamic Sensor Validation & Mounting Setup    |
+-------------------------------------------------+
| Hardware scan: ALL 3 SENSORS DETECTED           |
|                                                 |
| Select computer mounting orientation:           |
|   [1] 0 deg   (Facing Bow / Ship Forward)       |
| > [2] +90 deg (Facing Starboard / Ship Right)   |
|   [3] 180 deg (Facing Stern / Ship Aft)         |
|   [4] -90 deg (Facing Port / Ship Left)         |
|                                                 |
| [LIVE TELEMETRY STREAM]                         |
|   Pitch: +1.2 deg   Roll: -0.8 deg   Yaw: 85.0  |
|   Alt  : 62.1 m     Vy  : +0.02 m/s (STABLE)    |
|   GPS  : X=840.2, Y=62.1, Z=1120.8 (LOCK 5Hz)   |
+-------------------------------------------------+
| [Enter] Select     [R] Rescan          [B] Back |
+-------------------------------------------------+
```

#### 5) 무인 운용 데몬 모드 화면 (`DAEMON_RUN`)
```text
+-------------------------------------------------+
| PAD_BRAVO_01 [DYNAMIC] | SEC: 1 | TACT: 50211   |
| Status: APPROACH_DYNAMIC | Target: AIRCRAFT_01  |
+-------------------------------------------------+
| [TACTICAL GUIDANCE STREAM - 20Hz]               |
| Touchdown: X=840.25  Y=62.10  Z=1120.80         |
| Velocity : Vx=+6.20  Vy=-0.15 Vz=+1.10  (m/s)   |
| Deck Tilt: 2.77 deg (Limit: 10.0 deg)           |
| Heave    : -0.15 m/s (Limit: 2.50 m/s)          |
| Deck Cond: [ STABLE ]  Landing: [ PERMITTED ]   |
|                                                 |
| [LOCAL BACKBONE TRAFFIC]                        |
| Last GAC Sync: 1729850025.1 (0.2s ago)          |
| Active Slot  : 45s remaining / 120s             |
+-------------------------------------------------+
| 13:45:12 [TX] DYN_GUIDE seq=45120 -> AIRCRAFT_01|
+-------------------------------------------------+
```

---

### 6.4 컴팩트 1줄 로깅 데몬 모드 및 JSON 스키마 규격

1. **컴팩트 1줄 순환 로그 (Compact 1-Line Log)**:
   - 터미널 최하단 라인(19행)에는 가장 최근 발생한 중요 이벤트/패킷 송수신 내역을 1줄로 축약 표출합니다:
     ```text
     [HH:MM:SS] [TX/RX/ERR] <TYPE> seq=<N> <summary>
     ```
   - 무의미한 20Hz 스트리밍 텍스트 스크롤로 인한 터미널 렌더링 병목을 방지합니다.
2. **설정 파일 (`/landing_pad/config.json`) 표준 스키마**:
   ```json
   {
     "version": "2.4.0",
     "facilityId": "PAD_BRAVO_01",
     "sectorId": 1,
     "padIndex": 1,
     "mobility": "DYNAMIC",
     "gacChannel": 50201,
     "sectorFacilityChannel": 50202,
     "sectorGpsReplyChannel": 50206,
     "tacticalChannel": 50211,
     "mountingYawOffset": 90.0,
     "bodyOffset": {
       "forward": 12.0,
       "right": -4.5,
       "up": 1.2
     },
     "staticPosition": null,
     "approachHeading": 180.0,
     "safeDescentRate": 1.0,
     "clearanceZoneRadius": 5.0,
     "maxSupportedWeight": 45000.0,
     "wirelessModemSide": "top"
   }
   ```
