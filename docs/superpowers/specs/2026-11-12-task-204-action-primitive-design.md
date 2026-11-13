# 비행체 미션 자율 제어 아키텍처 및 확장형 표준 행동(Action Primitive) 종합 명세 보고서 (Minecraft / UAFS 정합판)

> **문서 성격**: `TASK-204` 착수 전 설계 청사진 (`Design Spec`) — 마인크래프트 인게임 모드 환경 및 현 UAFS 코드베이스/사양서 정합 개편본  
> **작성일**: `2026-11-12`  
> **대상 환경**: `Minecraft CC:Tweaked (Lua 5.2)`, `Create: Aeronautics`, `Create: Avionics`, `Create: Radars`, `Create Propulsion: Simulated`, `Advanced Peripherals`  
> **기준 사양서**: [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md) (`v1.28.0`), [AMM_PROGRAM_SPECIFICATION.md](../../specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md) (`v1.3.0`), [FCP_PROGRAM_SPECIFICATION.md](../../specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md) (`v2.0.0`), [VAS_PROGRAM_SPECIFICATION.md](../../specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md) (`v1.19.0`)  
> **연계 설계서 (`TASK-124`)**: [2026-11-13-task-204-chattering-prevention-design.md](./2026-11-13-task-204-chattering-prevention-design.md) (이산 틱·히스테리시스·단방향 래치·도착 안착 채터링 방지 규격)

---

## 0. 개편 목적 및 구현 등급 표기 규칙

본 문서는 범용 실세계 UAV 기준 초안을 **마인크래프트 인게임 물리·페리페럴 제약**과 **UAFS 4계층 아키텍처**에 맞게 재설계한 기준 명세입니다. `TASK-204` 수행 시 `AMM v1.3.0`의 기존 평면적 13종 액션 체계(`FLY_OVER`, `FLY_TO`, `ORBIT` 등)는 **완전 폐기(Zero-Fallback)**하고, 본 문서의 **`ACT_*` / `DEC_*` / `MAC_*` 3계층 체계**로 전면 대체합니다.

- **구현 등급 표기**:
  - **`[TASK-204 즉시]`**: 현행 UAFS 인프라(`GPS`, `GAC`, `LANDING_PAD`), 6대 기체, `AMM`/`FCP`/`VAS` 20Hz 폐루프로 즉시 구현 가능한 표준 행동
  - **`[로드맵 - <선행과제/센서>]`**: 인게임 모드 API/물리로 구현 가능하나 후속 태스크(`TASK-103`, `TASK-104`, `TASK-108`, `TASK-401`, `Zone 4`) 또는 선택적 탑재 센서가 필요한 확장 행동
  - **`TBD [TASK-401]`**: Zone 3 탑재체 통신 스키마 정의(`TASK-401`) 하위 항목으로 위임된 세부 페이로드 행동

---

## 1. 개요 및 시스템 아키텍처

UAFS(Universal Autonomous Flight Stack)의 자율 제어 시스템은 지상·공역 인프라와의 교신 및 임무 시퀀싱·항법·궤적 생성을 담당하는 **상위 임무·궤적 계층(`AMM`, Node 03)**, 순수 `SE(3)` 외루프 추종을 수행하는 **중위 유도 계층(`FCP`, Node 04)**, 그리고 `SO(3)` 내루프 자세·추력·조종면 믹싱을 담당하는 **하위 비행 제어 및 구동 계층(`VAS` Node 01 + `TCA`/`ASA` 클러스터)**으로 직교 분리됩니다.

마인크래프트 서버 틱과 `CC:Tweaked` 이벤트 루프 특성상 온보드 실시간 제어 주기는 **최대 20Hz (`50ms`)**를 상한으로 설계합니다.

### 1.1 UAFS 자율 제어 시스템의 4대 계층 구조

| 계층 구분 | 주요 서브 블록 (컴포넌트) | 핵심 역할 및 처리 기능 | 대표 HW / SW 스택 및 주기 |
| :--- | :--- | :--- | :--- |
| **지상 및 외부 인프라 계층**<br>(Ground & External) | • `GCS` 채널관리자 및 관제 콘솔 (`CH 50000`, `Base+0/+3`)<br>• `Tower ATC` (`CH 50001/50002`, `TASK-108`)<br>• `GAC` 섹터 관제사 (`CH 50003/50004`, $Base_{\text{sec}}+0/+1$)<br>• `Facility Swarm` (`Landing Pad`·`Runway`·`Docking Arm`)<br>• `GPS Swarm` (`CH 60001/60002`, `Base+5`)<br>• `Alignment` 격납고 콘솔 (`101~200`) / `Cockpit MFD` | • 40채널 블록 할당 및 원격 미션 제어(`MSG_MISSION_CMD`)<br>• 3-Tier 공역/시설물 접근·이착륙·도킹 전술 유도 벡터 송출<br>• 다중 기준국 2D 삼변측량 측위 응답 및 격납고 OLS 캘리브레이션<br>• 조종석 직결 급기동(`MFD_ACRO`) 및 하드 비상 차단(`E_STOP`) | • `CC:Tweaked` Computer / Monitor<br>• Wireless / Ender Modem (`[I-5]~[I-8]`)<br>• 주기: `1Hz`(비콘), `5~10Hz`(GPS), `20Hz`(동적 유도), 이벤트 |
| **상위 임무·외부 게이트웨이·궤적 계층**<br>(`AMM`, Node 03 — Layer 3) | • 3분할 미션 코어 (`mission_engine`, `condition_evaluator`, `hook_runner`) + `ACT_*`/`DEC_*`/`MAC_*` 레지스트리<br>• 외부 게이트웨이 (`facility_client`, `channel_sentinel`)<br>• 20Hz 항법 융합 (`nav_engine`: GPS+DR 상보 필터 $\alpha=0.35$)<br>• 20Hz 궤적 생성기 (`trajectory_generator` $\to$ `Base+4` `[I-12]`)<br>• C2 중재기 (`c2_arbiter`) 및 TUI/웹 에디터 연동 | • 행동 사전 진입 조건(`checkPrecondition`)·완료/중단 조건·0-tick 훅 실행<br>• 외부 RF 단일 종단(`top`+`back` 듀얼 모뎀, 단일 모뎀 폴백)<br>• 동적 갑판 2차 테일러 외삽·가상 ILS·`LOITER`/`POI_HOLD` 세트포인트 생성<br>• 평시 5Hz `Base+3` MFD 다운링크(`MFD_ACRO` 시 양보) 및 51x19 TUI/드래그앤드롭 수신 | • `CC:Tweaked` Advanced / Standard Computer (`Lua 5.2`)<br>• `parallel.waitForAny` 듀얼 코루틴<br>• Coroutine A: **20Hz (`50ms`)**<br>• Coroutine B (`headless=false`): **5Hz (`200ms`)** |
| **중위 외루프 유도 계층**<br>(`FCP`, Node 04 — Layer 2) | • 속도 상태 전파기 (`state_propagator`)<br>• `SE(3)` 외루프 제어기 (`outer_loop_controller`: $g = 11.0\text{ m/s}^2$)<br>• 6상태 외루프 FSM (`flight_fsm`: `PASSIVE_TRACKING`, `AMM_TIMEOUT_HOLD` `500ms` $\to$ `10s`) | • `AMM`이 `Base+4`로 하달한 3D 목표 궤적 추종 및 안티와인드업 적분<br>• 6대 기체 타입(`QUADROTOR`, `HEXAROTOR`, `VECTORED_VTOL`, `ADVANCED_VTOL`, `WINGED_VTOL`, `FIXED_WING`)별 `QUATERNION_RATE` 투영 (`Base+1`) | • `CC:Tweaked` Computer (`Lua 5.2`)<br>• 단일 `top` 모뎀 3채널 격리 (`Base+4/+2/+1`)<br>• 주기: **20Hz (`50ms`)** |
| **하위 내루프·센서·구동 계층**<br>(`VAS` Node 01 + `TCA`/`ASA`/`Zone 3` — Layer 1) | • `VAS (Node 01)`: `SO(3)` 단위 쿼터니언 내루프, $V^2$ 동압 스케줄링, 실속/플랩 가드, `Base+1` 선점 중재(`E_STOP > MFD_ACRO > FCP`, `1,500ms` 타임아웃)<br>• 분산 구동기: `TCA` 클러스터(`Base+10`), `ASA` 클러스터(`Base+11`, 공력 기종 전용), `Zone 3 Payload` (`Base+20~29`)<br>• 물리 센서: `CC:Avionics`(`/lib/avionics_sensors.lua`), `CC:Radars`, `Advanced Peripherals` | • 자세·각속도 폐루프 제어 및 6-DoF 추진기/공력면 믹싱 분배<br>• 추진기(`thruster`, `vector_thruster`, `ion_thruster` 등) 및 레드스톤/조종면 물리 인가<br>• `gimbal_sensor`, `velocity_sensor`, `laser_sensor`, `radar`, `plane_radar`, `geoScanner`, `playerDetector` 계측 및 20Hz `Base+2` 송출 | • `CC:Tweaked` Computer / Wired·Wireless Modem<br>• `Create: Aeronautics` / `Avionics` / `Radars` / `Propulsion: Simulated` / `Advanced Peripherals`<br>• 주기: **20Hz (`50ms`)** |

---

## 2. 상태 폭발(State Explosion) 방지를 위한 3단계 확장 아키텍처 및 진입 조건 체계

### 2.1 상태 폭발을 막는 3단계 모듈형 확장 아키텍처

`AMM v1.3.0`의 평면적 13종 액션 체계를 폐기하고, 행동 조합에 따른 상태 전이($N \times N$) 폭발을 막기 위해 행동을 다음 **3계층 조합 구조**로 설계합니다. `CC:Tweaked Lua` 환경에는 `.so`/`.dll` 동적 라이브러리가 없으므로, 모든 행동과 데코레이터는 `AMM` 코어(`mission_engine.lua`, `condition_evaluator.lua`, `hook_runner.lua`) 위에서 **Lua 모듈 레지스트리 테이블(`require` 기반 등록)**로 로드됩니다.

1. **원자적 기본 행동 (Atomic Action Primitive, `ACT_*`):**
   - 단일 제어 목표, 명시적 사전 진입 조건(`preconditions`), 완료/중단 조건(`completeWhen`/`abortWhen`)을 가지는 최소 실행 단위입니다.
   - 표준 Lua 생명주기 인터페이스 **`checkPrecondition(ctx)`**, **`onEnter(ctx)`**(0-tick 훅 포함), **`onTick(ctx, nowMs)`**(20Hz `trajectory_generator` 세트포인트 및 조건 평가), **`onExit(ctx)`**, **`onAbort(ctx)`**를 구현합니다.
2. **행동 수정자 / 데코레이터 (Action Decorator, `DEC_*`):**
   - 기존 기본 행동을 복제하지 않고 **제약 조건·파라미터·실행 래퍼(재시도/타임아웃/승인 대기/EMCON)**만 외부에서 덧씌우는 계층입니다.
   - 예: `DEC_EMCON`을 `ACT_NAV_GOTO_WP`에 결합하면 별도 은밀 이동 행동을 만들지 않고도 트랜스폰더 OFF(`avionics_controller.setTransponder(false)`), 외부 GPS 핑(`CH 60001`) 억제, `Base+2` DR 단독 항법이 자동 적용됩니다.
3. **복합 임무 매크로 (Composite Macro / Sub-tree, `MAC_*`):**
   - 반복 사용되는 `ACT_*` + `DEC_*` 시퀀스를 하나의 재사용 서브트리 템플릿으로 패키징한 단위이며, 미션 로더/에디터 단계에서 원자 체크포인트 시퀀스로 전개됩니다.

```
[상위 임무 JSON / GCS 원격 명령 / 웹 미션 에디터]
        │
        ▼
┌───────────────────────────────────────────────────────────┐
│ 3계층: 복합 임무 매크로 (MAC_*)                           │
│  예: MAC_SHIP_RECOVERY (동적 갑판 추종·동기화·정밀 착함)  │
└───────────────────────────┬───────────────────────────────┘
                            │ (체크포인트 서브트리 전개)
                            ▼
┌───────────────────────────────────────────────────────────┐
│ 2계층: 행동 수정자 / 데코레이터 (DEC_*)                   │
│  예: [DEC_RETRY_N(3)] + [DEC_SMOOTH_TRAJ]                 │
│  -> checkPrecondition / constraintProfile / 재시도 래핑   │
└───────────────────────────┬───────────────────────────────┘
                            │ (제약 조건 주입)
                            ▼
┌───────────────────────────────────────────────────────────┐
│ 1계층: 원자적 기본 행동 레지스트리 (ACT_*)                │
│  예: ACT_MOB_RV_TRACK -> ACT_MOB_DECK_SYNC -> ...         │
│  -> checkPrecondition / onEnter / onTick / onExit / onAbort│
└───────────────────────────────────────────────────────────┘
```

### 2.2 진입 조건(Pre-condition)의 4대 검증 분류 체계 (`TASK-204` 핵심 도입)

`mission_engine`은 특정 `ACT_*` 상태로 진입하기 직전 `checkPrecondition(ctx)`를 통해 아래 4대 범주의 논리곱(`AND`)을 평가하며, 미충족 시 `PRECONDITION_FAILED` 사유와 함께 안전 대기 또는 중단 정책으로 분기합니다.

1. **기체 및 비행 모드 상태 (`State Flag`):**
   - `VAS Base+2` `controlState`(`"DISARMED"`, `"IDLE_ARMED"`, `"NORMAL"`, `"FAILSAFE_HOLD"`, `"E_STOP"`), `activeSource`(`"FCP"`, `"MFD_ACRO"`, `"EMERGENCY_DIRECT"`).
   - `FCP Base+4` `MSG_OUTER_LOOP_STATUS.fsmState` 및 기체 타입(`QUADROTOR`, `HEXAROTOR`, `VECTORED_VTOL`, `ADVANCED_VTOL`, `WINGED_VTOL`, `FIXED_WING`) 적합성.
2. **항법 및 인지 센서 건전성 (`Sensor & Est`):**
   - `VAS Base+2` `sensorOk == true`, 세부 헬스 `sensorHealth { gimbal, altitude, velocity, fuel }`, 구동기 헬스 `actuatorHealth { tap, asa }`.
   - `nav_engine` 위치 유효성(`not gpsTimedOut` 또는 유효 DR 상태, `hdop`, `accuracy`) 및 선택적 탑재 센서(`laser_sensor`, `radar`/`plane_radar`, `geoScanner`, `playerDetector`) 장착 여부.
3. **에너지·통신 및 채널 자원 (`Resource`):**
   - `VAS Base+2` `fuel`($0.0 \sim 1.0$)이 해당 행동 및 귀환 요구 잔량 이상인지 여부.
   - `channel_sentinel` 블록 바인딩(`Base`) 완료, `Base+0` `MSG_CHANNEL_PROBE` 무충돌, `facility_client` `ATC`/`GAC` 인가 및 Zone 3(`Base+20~29`) 채널 가용성.
4. **공간 및 안전 제약 (`Spatial & Safety`):**
   - 마인크래프트 월드 3D 좌표 `(X, Y, Z)` 기준 지오펜스(수평 경계·Y고도 상하한) 내부 위치 여부, NFZ 비침범 여부, 목표 고도·속도의 기종별 물리 한계 이내 여부.

> **계층형 감독 원칙:** `AMM` Coroutine A는 매 50ms(20Hz) 틱마다 `Base+2` `E_STOP`/헬스 이상, `abortWhen`, 지오펜스 등 **비상 대응 계층(`ACT_FS_*`)** 조건을 최우선 평가하며, `FCP(500ms)` 및 `VAS(1,500ms)` 타임아웃 워치독이 독립 안전망으로 중첩 작동합니다.

---

## 3. 기본 8대 도메인 표준 행동 리스트 (총 45종 + `TASK-401 TBD`)

표준 비행 및 기본 임무 수행을 위한 8개 도메인 표준 행동 명세입니다.

### 3.1 시스템 초기화·지상 점검 및 시동 계층 (`ACT_SYS_*`, 6종)

| 행동 ID | 등급 | 행동 명칭 및 상세 설명 | 핵심 진입 조건 (Pre-conditions) | 완료 조건 및 UAFS 연동 |
| :--- | :---: | :--- | :--- | :--- |
| **`ACT_SYS_LOAD`** | `[즉시]` | **미션 프로파일 로드 및 정적 검증**<br>수신된 JSON 미션 테이블의 스키마, 6대 기체 호환성, 지오펜스/NFZ 충돌 여부를 검사해 메모리에 적재 | • `controlState`가 `"DISARMED"` 또는 비비행 대기 상태<br>• `validate_mission_table` 스키마 및 `ACT_*` 레지스트리 유효 | 검증 통과 시 `MISSION_READY` 상태 확정(실패 시 `SCHEMA_INVALID`) |
| **`ACT_SYS_PREFLIGHT`** | `[즉시]` | **비행 전 종합 자가 점검 (Pre-flight BIT)**<br>`VAS` 센서·구동기 헬스, `channel_sentinel` 블록 할당, `Base+0` 채널 충돌, 연료·GPS Fix 상태를 종합 점검 | • `MISSION_READY == true` 및 기체 지상 정지 상태<br>• `Base+2` 수신 정상(`sensorOk == true`, `actuatorHealth.tap == true`)<br>• `fuel`이 미션 최소 요구치 이상 | `channel_sentinel` `MSG_CHANNEL_PROBE` 무충돌 및 `PREFLIGHT_OK` 판정 |
| **`ACT_SYS_SET_HOME`** | `[즉시]` | **기지(Home) 및 가용 패드 캐시 등록**<br>`nav_engine` 현재 융합 `(X, Y, Z)` 좌표를 Home으로 고정하고 `facility_client`(`CH 50003`) 비상 패드 목록 동기화 | • `ACT_SYS_PREFLIGHT` 통과<br>• `nav_engine` 3D 위치 유효(GPS Fix 또는 수동 기준 좌표) | Home `(X, Y, Z)` 레지스터 기록 및 `CH 50003` 비콘 캐시 확인 |
| **`ACT_SYS_ARM`** | `[즉시]` | **추진계 2단계 시동 활성화 (Arming)**<br>`Base+0` 채널 프로브 검증 후 `Base+4` `[I-12]`로 `arm = true, flightActive = false` (`IDLE_ARMED`) 전이 | • `ACT_SYS_SET_HOME` 완료 및 `controlState == "DISARMED"`<br>• `Base+0` 채널 선점 충돌(`ARMING_LOCKED`) 없음 | `Base+2` `controlState == "IDLE_ARMED"` 및 `Base+4` Status 확인 |
| **`ACT_SYS_DISARM`** | `[즉시]` | **추진계 시동 해제 및 잠금 (Disarming)**<br>착륙 완료 후 `Base+4`로 `arm = false, flightActive = false` (`DISARMED`)를 하달하여 전 구동기 차단 | • 지상 접지 상태(`LANDED` 또는 `verticalSpeed <= 0.1 m/s`)<br>• 비상 강제 차단 상황이 아닌 정상 착륙 후 진입 | `Base+2` `controlState == "DISARMED"` 전환 및 로그 마감 |
| **`ACT_SYS_TERMINATE`** | `[즉시]` | **비행 강제 차단 (Hard E-Stop)**<br>치명적 결함·지오펜스 이탈·조종사 `[X]`/`Ctrl+X` 발동 시 `Base+1` 직결 `MSG_EMERGENCY_OVERRIDE`로 전 추진기 즉시 컷오프 | • `[X]`/`Ctrl+X` 또는 GCS `E_STOP` 명령 수신 **또는** 치명적 비행 불능 감지 | `Base+1` `E_STOP` (`authKey = "ESTOP_CONFIRM_KEY"`) 송출 및 `controlState == "E_STOP"` (`ASA` 300ms Safe Glide Trim) |

### 3.2 이륙·착륙 및 VTOL 천이 기동 계층 (`ACT_TKL_*`, 8종)

| 행동 ID | 등급 | 행동 명칭 및 상세 설명 | 핵심 진입 조건 (Pre-conditions) | 완료 조건 및 UAFS 연동 |
| :--- | :---: | :--- | :--- | :--- |
| **`ACT_TKL_TAKEOFF_VERT`** | `[즉시]` | **수직 이륙 (Vertical Takeoff)**<br>현재 `(X, Z)`를 유지하며 `Base+4` `flightMode = "TAKEOFF"`로 지정된 안전 `Y` 고도까지 수직 상승 | • `controlState == "IDLE_ARMED"` 및 기종 `~= "FIXED_WING"`<br>• 상방 `laser_sensor`(장착 시) 클리어 및 `GAC` 이륙 인가(시설물 출발 시)<br>• `fuel >= minTakeoffFuel` | `altitudeY`가 목표 `Y` 허용 오차(`±1.5m`) 진입 시 완료 |
| **`ACT_TKL_TAKEOFF_RWY`** | `[로드맵: TASK-103]` | **활주로 고정익 이륙 (Runway Takeoff)**<br>`RUNWAY` 전술 유도($Base_{\text{sec}}+10+\text{Idx}$)를 추종하며 가속 후 `velocity_sensor` 대기속도 $1.3 V_s$ 이상에서 상승 | • `controlState == "IDLE_ARMED"` 및 `FIXED_WING` 또는 `WINGED_VTOL`<br>• `RUNWAY` 이륙 슬롯 인가(`GAC`/`Tower ATC`) 및 `velocity_sensor` 정상 | 안전 선회 `Y` 고도 및 실속 여유 속도 도달 |
| **`ACT_TKL_TRANS_MC2FW`** | `[즉시: WINGED_VTOL]` | **VTOL 순항 천이 (MC $\rightarrow$ FW)**<br>`WINGED_VTOL`이 호버링에서 전진 가속하여 양력·동압을 확보하고 공력 고정익 순항 모드로 전환 | • 비행 중(`NORMAL`), 기종 `== "WINGED_VTOL"`, `actuatorHealth.asa == true`<br>• 현재 고도가 최소 천이 안전 고도 이상 | `velocity_sensor.getAirspeed() > V_trans` 및 `FCP`/`VAS` 고정익 순항 루프 잠금 완료 |
| **`ACT_TKL_TRANS_FW2MC`** | `[즉시: WINGED_VTOL]` | **VTOL 호버링 역천이 (FW $\rightarrow$ MC)**<br>고정익 순항 중 감속과 동시에 수직 추력기 폐루프를 복원해 회전익 정밀 호버링으로 복귀 | • 비행 중(`NORMAL`), 기종 `== "WINGED_VTOL"`<br>• 전방 감속 거리 확보 및 `actuatorHealth.tap == true` | 대지속도 `<= 3.0 m/s` 감속 및 수직 호버링 제어 전환 완료 |
| **`ACT_TKL_LAND_NORM`** | `[즉시]` | **일반 수직 착륙 (Normal Landing)**<br>지정 `(X, Z)` 상공에서 `APPROACH_LAND` $\to$ `LANDING` 2단계 감속 하강으로 지면에 수직 착륙 | • 비행 중(`NORMAL`) 및 기종 `~= "FIXED_WING"`<br>• 목표 착륙 `(X, Z)` 수평 오차 `2.0m` 이내 정렬<br>• `altitudeY` / `laser_sensor`(장착 시) 정상 | 접지 감지(`verticalSpeed` 정지 및 고도 고정) 후 `ACT_SYS_DISARM` 연계 |
| **`ACT_TKL_LAND_PREC`** | `[즉시]` | **시설물 비콘 정밀 착륙 (Beacon Precision Land)**<br>`GAC`·`LANDING_PAD` 전술 유도 채널($Base_{\text{sec}}+10+\text{Idx}$ `STATIC`/`DYNAMIC_GUIDE`)을 추종해 패드 중앙에 정밀 착륙 | • `ACT_TKL_LAND_NORM` 조건 충족 및 `GAC` 슬롯 인가(`MSG_GAC_APPROACH_CLEARANCE`)<br>• `LANDING_PAD` 유도 패킷 워치독(`300ms`) 정상 | `Base+5` `MSG_TOUCHDOWN_COMPLETE` 및 `DISARMED` 확인 (이탈·이상 시 `ACT_TKL_ABORT_LAND`) |
| **`ACT_TKL_LAND_RWY`** | `[로드맵: TASK-103]` | **활주로 가상 ILS 착륙 (Runway ILS Land)**<br>`RUNWAY`의 로컬라이저 및 3° 글라이드슬로프 전술 유도 벡터($Base_{\text{sec}}+10+\text{Idx}$)를 추종해 활주로에 착륙 | • 비행 중(`NORMAL`), `FIXED_WING` 또는 `WINGED_VTOL`<br>• `GAC`/`RUNWAY` 착륙 슬롯 배정 및 가상 ILS 비콘 유효 | 활주로 접지(`MSG_TOUCHDOWN_COMPLETE`) 및 감속 정지 완료 |
| **`ACT_TKL_ABORT_LAND`** | `[즉시]` | **착륙 복행 (Go-Around)**<br>`MSG_ABORT_APPROACH` 수신, `300ms` 동적 유도 워치독 만료, 패드 요동 한계($10^\circ / 2.5\text{ m/s}$) 초과 또는 하방 장애물 감지 시 안전 고도로 재상승 | • 현재 행동이 `ACT_TKL_LAND_*` 상태<br>• 복행 트리거(시설물 Abort, 워치독 만료, `laser_sensor` 장애물) 발동 | 복행 안전 `Y` 고도 재도달 및 `GAC`에 `MSG_GAC_ABORT_CLEAR` 보고 |

### 3.3 기본 항법 및 경로 추종 계층 (`ACT_NAV_*`, 7종)

| 행동 ID | 등급 | 행동 명칭 및 상세 설명 | 핵심 진입 조건 (Pre-conditions) | 완료 조건 및 UAFS 연동 |
| :--- | :---: | :--- | :--- | :--- |
| **`ACT_NAV_GOTO_WP`** | `[즉시]` | **단일 3D 경유점 정밀 이동 (`FLY_TO`)**<br>현재 위치에서 목표 `(X, Y, Z)`까지 `CRUISE` 궤적으로 이동한 뒤 감속해 3D 반경 내 정밀 도달 | • 비행 중(`NORMAL`) 및 `nav_engine` 위치 유효<br>• 목표 `(X, Y, Z)`가 지오펜스 내부 및 귀환 연료 여유 충족 | 목표 좌표 3D(또는 2D+고도) `acceptanceRadius` 이내 정밀 진입 |
| **`ACT_NAV_SPLINE_WP`** | `[즉시]` | **무정지 스플라인 경유점 통과 (`FLY_OVER`)**<br>경유점에서 감속 정지하지 않고 다음 경유점(Look-ahead) 방향으로 부드럽게 궤적을 이어 통과 | • 비행 중(`NORMAL`) 및 `nav_engine` 위치 유효<br>• 다음 경유점 좌표가 미션 큐에 존재(권장) | 목표 수평 반경(`acceptanceRadius`) 진입 즉시 감속 없이 다음 스텝 전이 |
| **`ACT_NAV_CORRIDOR`** | `[즉시]` | **항공 회랑 정밀 유지 비행 (Corridor Follow)**<br>시작점~종점 3D 회랑 중심선을 이탈하지 않고 비행(`CROSS_TRACK_ERROR` 상시 감시) | • 비행 중(`NORMAL`) 및 `nav_engine` GPS+DR 유효<br>• 회랑 중심선 초기 오차가 최대 허용 편차 이내 | 회랑 종점 게이트 도달 완료(이탈 시 `CROSS_TRACK_ERROR` 중단 트리거) |
| **`ACT_NAV_CHANGE_ALT`** | `[즉시]` | **목표 Y 고도 변경 (Altitude Change)**<br>현재 수평 위치 또는 경로를 유지하며 `AMM trajectory_generator` 목표 `Y` 고도(`altitudeY`)까지 승강 | • 비행 중(`NORMAL`)<br>• 목표 `Y` 고도가 지오펜스 하한~상한 범위 이내 | `|targetAlt - telemetry.dynamics.altitudeY| <= toleranceM` 도달 |
| **`ACT_NAV_CHANGE_SPD`** | `[즉시]` | **순항 목표 속도 프로파일 변경 (Speed Change)**<br>이후 항법 행동에 적용될 `AMM trajectory_generator`의 목표 대지속도(`cruiseSpeed`)를 동적으로 갱신 | • 비행 중(`NORMAL`)<br>• 설정 속도가 기종 실속 속도(고정익) 초과 및 최대 허용 속도 미만 | `AMM` 궤적 프로파일 파라미터 갱신 즉시 완료 |
| **`ACT_NAV_CHANGE_YAW`** | `[즉시]` | **기수 방위각 정렬 제어 (Heading Align)**<br>회전익/VTOL 기체의 기수를 목표 방위각($0^\circ \sim 360^\circ$, MC `-Z` 북쪽 기준)으로 회전 정렬 | • 비행 중(`NORMAL`), 기종 `~= "FIXED_WING"`<br>• `Base+2` `sensorHealth.gimbal == true` | `|targetYaw - telemetry.attitude.yaw| <= 2.0°` 수렴 |
| **`ACT_NAV_TERRAIN_FLW`** | `[로드맵: laser_sensor]` | **하방 레이저 기반 지형 추종 비행**<br>DEM 대신 하방 장착 `CC:Avionics` `laser_sensor`의 실시간 지면 거리(`getDistance()`)를 일정하게 유지하며 이동 | • 비행 중(`NORMAL`), 하방 `laser_sensor` 장착 및 `hasTarget() == true`<br>• 목표 순항 속도가 레이저 센서 탐지 반응 한계 이내 | 목표 `(X, Z)` 도달까지 지면 이격 거리 허용 오차 유지 |

### 3.4 선회·체공 및 광역 탐색 패턴 계층 (`ACT_PAT_*`, 8종)

| 행동 ID | 등급 | 행동 명칭 및 상세 설명 | 핵심 진입 조건 (Pre-conditions) | 완료 조건 및 UAFS 연동 |
| :--- | :---: | :--- | :--- | :--- |
| **`ACT_PAT_HOLD_POS`** | `[즉시]` | **제자리 정밀 체공 대기 (`HOVER_HOLD`)**<br>현재 `(X, Y, Z)`와 기수각을 고정한 채 지정 시간 또는 외부 재개 명령 시까지 호버링 대기 | • 비행 중(`NORMAL`), 기종 `~= "FIXED_WING"`<br>• `nav_engine` 수평 위치 유효 | 대기 타이머 만료(`DURATION_SEC`) 또는 `resume`/`next` 수신 |
| **`ACT_PAT_POI_HOLD`** | `[즉시]` | **관심 지점 조준 체공 (`POI_HOLD`)**<br>지정 체공 위치 `(X, Y, Z)`를 유지하면서 기수(`<= 30.0°/s` 슬루)를 관심 좌표 `poiPos {x, y, z}`로 지속 지향 | • 비행 중(`NORMAL`), 기종 `~= "FIXED_WING"`<br>• `poiPos` 좌표 유효 및 `sensorHealth.gimbal == true` | `DURATION_SEC` 만료 또는 상위 해제 명령 수신 |
| **`ACT_PAT_LOITER_TIME`** | `[즉시]` | **목표 주변 일정 시간 원궤도 선회 (`LOITER`)**<br>중심 `(X, Z)` 기준 반경 $R \ge 5.0\text{ m}$ 원궤도를 `CW`/`CCW` 방향으로 지정 시간 선회(`Base+4` 방사+접선 벡터) | • 비행 중(`NORMAL`)<br>• 선회 반경 $R \ge 5.0\text{ m}$ 및 전체 궤도가 지오펜스 내부 | 누적 선회 시간(`DURATION_SEC`) 만료 |
| **`ACT_PAT_LOITER_TURNS`** | `[즉시]` | **목표 주변 지정 횟수($N$바퀴) 원궤도 선회**<br>선회 중심 기준 누적 방위각 변화량이 $N \times 360^\circ$에 도달할 때까지 원궤도 선회 | • `ACT_PAT_LOITER_TIME` 진입 조건과 동일<br>• 목표 회전 수 $N \ge 1$ 유효 | 누적 선회 각도 $\ge N \times 360^\circ$ 달성 |
| **`ACT_PAT_LOITER_ALT`** | `[즉시]` | **나선형 선회 상승/하강 (Helical Loiter)**<br>좁은 공역 내에서 원궤도 선회(`LOITER`)와 `Y` 고도 선형 변경을 동시에 수행해 안전하게 목표 고도에 도달 | • 비행 중(`NORMAL`)<br>• 선회 반경 내 지오펜스·고도 한계 충족 | 목표 `altitudeY` 허용 오차(`±1.5m`) 도달 |
| **`ACT_PAT_FIG_EIGHT`** | `[로드맵]` | **8자형 궤도 감시 선회 (Figure-8)**<br>두 초점 좌표를 잇는 8자 궤적을 `trajectory_generator` 20Hz 세트로 생성해 고정익/VTOL로 지속 감시 | • 비행 중(`NORMAL`)<br>• 두 로브 반경·중심 좌표가 지오펜스 내부 | 지정 시간 또는 왕복 사이클 완료 |
| **`ACT_PAT_GRID_SURVEY`** | `[로드맵: Radars/Geo]` | **레이더·스캐너 기반 격자 구역 스캔**<br>다각형 ROI 내부를 `plane_radar`/`radar` 또는 `geoScanner` 유효 반경(Swath) 간격으로 왕복 비행하며 탐색 | • 비행 중(`NORMAL`), 다각형 꼭짓점 $\ge 3$<br>• 탑재 `plane_radar`/`radar` 또는 `geoScanner` 정상 응답 | 모든 스캔 레그(Leg) 종점 통과 완료 |
| **`ACT_PAT_EXP_SPIRAL`** | `[로드맵: Radars/PD]` | **확장형 나선 수색 (Expanding Search)**<br>추정 기준점(Datum)에서 바깥으로 반경을 넓히며 비행하고, 레이더/`playerDetector` 포착 시 즉시 종료 | • 비행 중(`NORMAL`), 중심점 도달<br>• `radar`/`plane_radar` 또는 `playerDetector` 활성 | 최대 반경 도달 **또는** 표적 포착(`TARGET_FOUND`) 인터럽트 발생 |

### 3.5 환경 인지·동적 회피 및 표적 추적 계층 (`ACT_PER_*`, 4종)

*(비전 특징점 점검 `VIS_SERVO` 및 VIO/SLAM `VIO_NAV`는 마인크래프트 미지원으로 삭제 — GPS 두절 시 `nav_engine` DR 자동 전환으로 대체)*

| 행동 ID | 등급 | 행동 명칭 및 상세 설명 | 핵심 진입 조건 (Pre-conditions) | 완료 조건 및 UAFS 연동 |
| :--- | :---: | :--- | :--- | :--- |
| **`ACT_PER_LOCAL_AVOID`** | `[로드맵: Laser/Radar]` | **레이저·레이더 기반 근접 장애물 우회**<br>전방/측방 `laser_sensor` 지형 장애물 또는 `radar`/`plane_radar` 근접 트랙 감지 시 안전 오프셋 우회 경로 생성 | • 비행 중(`NORMAL`)<br>• `laser_sensor` 또는 `radar`/`plane_radar` 정상<br>• 안전 버퍼 내 장애물/접근 트랙 감지 | 장애물/트랙 통과 후 원래 목표 경로 복귀 완료 |
| **`ACT_PER_REPLAN_GLB`** | `[로드맵]` | **전역 경로 동적 재계획 (Global Re-planning)**<br>`GCS` 신규 NFZ 폴리곤 수신 또는 국소 회피 불가 차단 시 2D/3D A\* 알고리즘으로 경로 큐 재생성 | • `ACT_PER_LOCAL_AVOID` 시간 초과 **또는** `GCS` 신규 NFZ 수신 | 신규 안전 경유점 시퀀스 산출 및 큐 교체 완료 |
| **`ACT_PER_TRACK_TGT`** | `[로드맵: Radars/PD]` | **레이더·플레이어 실시간 표적 추격 및 거리 유지**<br>`CC:Radars` (`getTracks`/`getSelectedTrack`), `CC:Avionics` (`radar.getContact`), `playerDetector`가 반환한 `{x, y, z, velocity}`를 추종하며 이격 거리 유지 | • 비행 중(`NORMAL`)<br>• 표적 트랙 `id` 잠금(`TRACK_LOCKED == true`) 및 타임스탬프 유효 | 추적 종료 명령 수신(표적 소실 시 `ACT_PAT_EXP_SPIRAL` 등 분기) |
| **`ACT_PER_SENTRY_HOLD`** | `[로드맵: 착지 초계/자가충전]` | **착지 상태 감시 초계·저부하 대기 및 자가 충전 (Sentry Hold & Self-Recharge)**<br>지정 안전 평지/패드에 착륙해 `DISARM` 상태로 20Hz 궤적/제어 루프를 일시 중단(저부하 Standby Sleep)하고 `radar`/`playerDetector`·`modem_message`·`redstone`·타이머 감시를 유지하다 조건 충족 시 재이륙 연결.<br>*(구 `ACT_NRG_HIBERNATE`의 저부하 Standby Sleep 및 이벤트 웨이크업 방식을 본 행동으로 완전 통합)*<br>• **전기 기체 자가 충전(Self-Recharge) 메커니즘**:<br>기체 프로파일(`Profile`)이 전기 구동(`isElectric == true`)이고 태양광 패널 등 자가 충전 수단(`hasSelfCharging == true`)을 갖춘 경우, 에너지가 일정량 이하(`fuel <= lowEnergyThreshold`, 기본 `0.30`)로 저하되거나 초계 중 충전 필요 시 안전 지점에 착륙(`DISARM`)하여 일광 아래 자가 충전을 수행하며 대기. 목표 에너지(`targetFuel`, 기본 `0.85`) 보충 완료 시 `ACT_SYS_ARM` $\to$ 이륙하여 중단되었던 직전 행동(`Action`) 및 미션(`Mission`)을 자동 복귀하여 지속 수행. | • 지정 안전 지점 착지(`DISARMED`) 완료 또는 비행 중 저에너지 발생 시 안전 착륙 시퀀스 선행<br>• `radar`/`playerDetector`/모뎀/타이머/레드스톤 감시 리소스 중 최소 1종 유효<br>• 자가 충전 진입 시: 전기 프로파일(`isElectric == true`), 자가 충전 장비(`hasSelfCharging == true`), 천공 개방(태양광 차폐 없음) | • **초계/웨이크업**: 감시 표적 포착(`TARGET_LOCKED`), `Base+0` 명령 수신, 레드스톤 입력 감지, 대기 시간 만료 시 `ACT_SYS_ARM` $\to$ `TAKEOFF` 연계<br>• **자가 충전 완료**: `telemetry.fuel >= targetFuel` 충전 완료 시 자동 재시동(`ACT_SYS_ARM`) 후 직전 Action 및 미션 시퀀스 복귀 재개 |

### 3.6 임무 장비(Payload) 및 레드스톤 제어 계층 (`ACT_PAY_*`, 4종 + `TASK-401 TBD`)

*(실세계 짐벌 카메라 연속 촬영 `CAM_TRIG`, 장력 윈치 `WINCH_DLV`, 농약 살포 `SPRAY_CTRL` 삭제)*

| 행동 ID | 등급 | 행동 명칭 및 상세 설명 | 핵심 진입 조건 (Pre-conditions) | 완료 조건 및 UAFS 연동 |
| :--- | :---: | :--- | :--- | :--- |
| **`ACT_PAY_BUS_CMD`** | `[즉시 / TASK-401 연계]` | **Zone 3 탑재체 버스 범용 명령 송출 (`PAYLOAD_ACTION`)**<br>`Base + 20 ~ 29` 채널을 동적 개방해 탑재체 노드에 `MSG_PAYLOAD_REQ`를 전송하고 응답(`MSG_PAYLOAD_ACK`)을 대기 | • `channelOffset`($20 \sim 29$) 유효 및 미션 스텝 활성<br>• 지정 Zone 3 탑재체 통신 가능 상태 | `waitForAck == false` 시 즉시 완료, 기본(`true`) 시 `PAYLOAD_RESP_MATCH` |
| **`ACT_PAY_REDSTONE`** | `[즉시]` | **로컬 레드스톤 및 16색 번들 케이블 제어 (`REDSTONE_ACTION`)**<br>컴퓨터 6면(`top`~`back`) 또는 번들 케이블로 비차단 디지털/아날로그 출력(`EMIT`) 또는 입력 신호 대기(`WAIT_INPUT`) 수행 | • `side`가 6면 중 하나이며, `mode`(`"EMIT"`/`"WAIT_INPUT"`) 유효 | `EMIT` 시 `durationMs` 만료, `WAIT_INPUT` 시 `REDSTONE_INPUT_HIGH` 충족 |
| **`ACT_PAY_SET_ROI`** | `[즉시]` | **기수 `POI` 및 Zone 3 터렛/포인터 조준 고정**<br>기수 `headingMode = "POI"` 또는 Zone 3(`Base+20/21`) `CC:Radars` 터렛(`auto_pitch`/`auto_yaw`)·`laser_pointer`를 특정 `(X, Y, Z)`에 지향 고정 | • ROI 좌표 `(X, Y, Z)` 유효<br>• 기수 지향(비고정익) 또는 Zone 3 조준 탑재체 응답 정상 | 기수/터렛 조준 정렬 및 `ROI_LOCK` 활성화 ACK 확인 |
| **`ACT_PAY_CLEAR_ROI`** | `[즉시]` | **관심 영역 지향 고정 해제 및 중립 복귀**<br>기수 `POI` 고정 및 `auto_pitch`/`auto_yaw`/`laser_pointer` 조준을 해제해 진행 방향(`AUTO`) 중립 상태로 복귀 | • 현재 모드가 `POI` 또는 `ROI_LOCK` 상태 | 중립 복귀(`AUTO`) 및 탑재체 해제 ACK 확인 |
| **`TBD [TASK-401]`** | `[로드맵: TASK-401]` | **세부 탑재체 전용 표준 행동군 (`CARGO_DROP`, `FIRE_CTRL`, `GEO_SCAN` 등)**<br>화물 투하구(Chute/Dispenser/Bomb Bay), `CC:Radars` `fire_controller`(`Base+21` `CH_WEAPON_BUS`), `geoScanner` 주기 스캔 등 세부 표준 액션은 **`TASK-401` (Zone 3 통신 스키마 정의) 하위 항목으로 위임하여 확정** | • `TASK-401` Discovery/Capability 및 인터록 스키마 확정 후 정의 | `TASK-401` 표준 `MSG_PAYLOAD_ACK` 상태 코드 연동 (`TBD`) |

### 3.7 통신·편대 협동 및 공역 통제 계층 (`ACT_COM_*`, 3종)

*(엔더 모뎀 무제한/비차폐 특성상 이기종 RF 절체 `LINK_SW` 및 전파 음영 중계 `RELAY_POS` 삭제)*

| 행동 ID | 등급 | 행동 명칭 및 상세 설명 | 핵심 진입 조건 (Pre-conditions) | 완료 조건 및 UAFS 연동 |
| :--- | :---: | :--- | :--- | :--- |
| **`ACT_COM_ATC_HOLD`** | `[즉시(GAC) / 로드맵(TASK-108)]` | **공역 및 섹터 관제 승인 대기 (`Tower ATC` / `GAC`)**<br>공항·섹터 진입 전 대기 지점에서 `LOITER`/`HOVER_HOLD`로 체공하며 `Tower ATC`(`CH 50001`) 핸드오프 또는 `GAC`($Base_{\text{sec}}+0$) 접근·슬롯 인가를 대기 | • 비행 중(`NORMAL`)<br>• `AMM` 외부 게이트웨이(`back` 모뎀) 활성 및 대상 관제 채널 오픈 | `MSG_ATC_HANDOFF_CLEARANCE` 또는 `MSG_GAC_APPROACH_CLEARANCE` 수신 시 전이 |
| **`ACT_COM_SWARM_FOLLOW`** | `[로드맵: Zone 4]` | **편대 합류 및 리더 상대 대형 유지**<br>`Zone 4` (`Base+30~39`) 채널로 리더 기체의 `(X, Y, Z)` 및 속도 벡터를 수신해 지정 3D 오프셋 $(\Delta X, \Delta Y, \Delta Z)$ 대형 유지 | • 비행 중(`NORMAL`)<br>• `Zone 4` 리더 브로드캐스트 수신 정상 및 초기 안전 분리 거리 확보 | 편대 해산(`SWARM_SPLIT`) 수신 또는 편대 구간 종점 도달 |
| **`ACT_COM_HANDOVER`** | `[로드맵: Zone 4]` | **교대 기체 간 임무 인계 (Mission Handover)**<br>장시간 초계 중 `fuel` 저하 시 고도 분리층으로 진입한 교대 기체에 `Zone 4`/`GCS` 경유로 활성 체크포인트·ROI 좌표를 인계하고 복귀 | • 현재 체공/초계 임무 중 및 교대 기체 `HANDOVER_READY` 수신 | 교대 기체 `HANDOVER_CONFIRMED` 수신 즉시 `ACT_FS_RTL_HOME` 전환 |

### 3.8 비상 대응 및 페일세이프 회복 계층 (`ACT_FS_*`, 5종)

*(고고도 강풍 탈출 `WIND_ESCAPE` 및 화약 낙하산 `PARACHUTE` 삭제 — 누락된 `ACT_FS_HOVER_HOLD` 신설)*

| 행동 ID | 등급 | 행동 명칭 및 상세 설명 | 핵심 진입 조건 (Pre-conditions / Interrupt Triggers) | 완료 조건 및 UAFS 연동 |
| :--- | :---: | :--- | :--- | :--- |
| **`ACT_FS_RTL_HOME`** | `[즉시]` | **기지 안전 고도 복귀 (Return to Launch)**<br>진행 중인 미션을 중단하고 안전 귀환 `Y` 고도로 상승해 `Home` 상공까지 `FAILSAFE_RTH` 궤적으로 복귀 | • 비행 중(`NORMAL` 또는 `FAILSAFE_HOLD`) 및 `HOME_VALID == true`<br>• **트리거:** 1차 저연료(`fuel <= 0.20`, `60 Ticks` 디바운스 래치), `[R]` 핫키, 또는 `fallbackPolicy == "RTH"` 발동 | `Home` 상공 수평 오차 `2.0m` 이내 도달 후 `ACT_TKL_LAND_PREC`/`LAND_NORM` 자동 연결 |
| **`ACT_FS_GOTO_RALLY`** | `[즉시]` | **최근접 가용 착륙패드 대피 (`Divert Nearest`)**<br>`Home` 복귀 `fuel`이 부족하거나 경로가 차단됐을 때 `facility_client`(`CH 50003` 비콘)의 최단거리 가용 패드로 이동 | • 비행 중 및 `CH 50003` 가용 시설물 목록 존재<br>• **트리거:** `Home` 귀환 소요 연료 초과 또는 `Home` 접근 불가 | 최단거리 패드 상공 도달 후 `ACT_TKL_LAND_PREC` 연결 |
| **`ACT_FS_FENCE_BRAKE`** | `[즉시]` | **지오펜스 경계 제동 및 안전 구역 복귀**<br>`nav_engine` `(X, Y, Z)`가 지오펜스 수평 경계 또는 `Y` 고도 상하한에 임박/침범 시 급제동 후 내부 안전 지점으로 후퇴 | • 비행 중<br>• **트리거:** 지오펜스 경계선 `5.0m` 이내(`2 Ticks` 디바운스) | `40 Ticks` 최소 유지 및 지오펜스 내부 `15.0m` 복귀 |
| **`ACT_FS_HOVER_HOLD`** | `[즉시]` | **현 위치 안전 정지·선회 대기 (`HOVER_HOLD` / `LOITER`)**<br>GPS `5,000ms` 초과 두절, `[H]` 핫키, 또는 `fallbackPolicy` 발동 시 현 위치에서 정지 체공(고정익은 `R=30m` 선회)하며 관제/복구를 대기 | • 비행 중<br>• **트리거:** `gpsTimedOut == true`, `[H]` 핫키, 또는 중단 정책 `"HOVER_HOLD"`/`"LOITER"` | 운용자 `resume`/`RTH` 명령 수신 또는 GPS 복구(`validStreak >= 3`) 후 재개 |
| **`ACT_FS_EMERG_LAND`** | `[즉시]` | **현 위치 즉시 비상 강하 착륙 (`EMERGENCY_LAND`)**<br>치명적 연료 고갈(`fuel <= 0.10`, `30 Ticks` 디바운스 래치), 측위 완전 상실, 또는 `[L]` 핫키/`10s` 타임아웃 만료 시 `-2.0 m/s` 정속 강하로 즉시 착륙 | • 비행 중<br>• **트리거:** 2차 위험 연료(`<= 0.10`), `[L]` 핫키, `AMM`/`FCP`/`VAS` 10초 홀드 만료 | 지면 접촉(`verticalSpeed == 0`) 감지 즉시 `ACT_SYS_DISARM` 강제 호출 |

---

## 4. 확장 3대 특수 도메인 표준 행동 리스트 (총 10종 — 9종 활성 + 1종 통합)

초기 명세의 7대 확장 도메인 중 인게임 물리·센서·모드에서 구현이 불가능한 **4개 도메인(구 `4.2 공중 매니퓰레이션 ACT_MAN_*`, 구 `4.4 전자전 ACT_EW_*`, 구 `4.6 극한 기상 ACT_ENV_*`, 구 `4.7 온보드 AI ACT_AI_*`)을 완전 삭제**하고, `Create: High Seas`/`Offroad` 및 UAFS 로드맵과 정합되는 **3개 도메인(10종: 9종 활성 + 1종 통합 이관)**만 남깁니다. *(구 `ACT_NRG_HIBERNATE`는 `ACT_PER_SENTRY_HOLD`로 통합)*

### 4.1 이동 플랫폼 및 해상·차량 연동 계층 (`ACT_MOB_*`, 5종)

*(갑판 테더 하푼 `TETHER_LAND`, 드로그 콘 `AIR_DOCK`, 슬링 진자 `SLING_DAMP` 삭제 $\rightarrow$ UAFS `DOCKING_ARM` `TASK-104`로 치환)*

| 행동 ID | 등급 | 행동 명칭 및 상세 설명 | 핵심 진입 조건 (Pre-conditions) | 완료 조건 및 UAFS 연동 |
| :--- | :---: | :--- | :--- | :--- |
| **`ACT_MOB_RV_TRACK`** | `[즉시: 동적 패드]` | **이동 플랫폼 랑데부 및 속도 동조**<br>주행 차량(`Create: Offroad`)·항해 선박(`Create: High Seas`) 탑재 동적 패드의 20Hz `MSG_FACILITY_DYNAMIC_GUIDE`($Base_{\text{sec}}+10+\text{Idx}$)를 수신하고 **2차 테일러 외삽**으로 접근·속도 일치 | • 비행 중(`NORMAL`)<br>• `MSG_FACILITY_DYNAMIC_GUIDE` 20Hz 수신 및 `300ms` 워치독 정상<br>• 플랫폼 속도가 기체 순항 한계(70%) 이하 | 갑판 상공 오프셋에서 상대 속도 `<= 0.3 m/s` 수렴 |
| **`ACT_MOB_DECK_SYNC`** | `[즉시: 동적 패드]` | **이동 갑판 요동 안전 인터록 및 동기화**<br>동적 `LANDING_PAD`(`v2.4.3`)가 송출하는 갑판 기울기/승강 속도를 감시해 안전 한계(**기울기 $10^\circ$, 승강 $2.5\text{ m/s}$**) 이내 착륙 윈도우를 포착·추종 | • `ACT_MOB_RV_TRACK` 완료 상태<br>• 동적 패드 3종 항법 센서 피드백 유효 | 갑판 요동 한계 이내 안정 윈도우 진입 및 `ACT_TKL_LAND_PREC` 전환 |
| **`ACT_MOB_MOVING_TKOFF`** | `[즉시: 동적 패드]` | **이동 차량·선박 갑판 동적 이륙**<br>이동 중인 플랫폼의 현재 지면 속도 벡터를 초기 궤적 피드포워드에 반영하여 충돌 없이 갑판을 이탈·이륙 | • `controlState == "IDLE_ARMED"` 및 기종 `~= "FIXED_WING"`<br>• 플랫폼 속도 벡터 수신 및 갑판 기울기 $\le 10^\circ$ | 상대 수직 속도 $\ge 3.0\text{ m/s}$로 플랫폼 안전 고도 이탈 완료 |
| **`ACT_MOB_ARM_DOCK`** | `[로드맵: TASK-104]` | **2축 도킹암 4단계 정밀 랑데부 및 포획 (`DOCK_ARM`)**<br>`trajectory_generator` 4단계 접근(최종 크립 $\le 0.4\text{ m/s}$, 공차 $|e_y|,|e_z|\le 0.15\text{ m}$, $|\Delta\psi|\le 2.0^\circ$)으로 도킹암에 결합하고, 이탈 시 `surge = -0.8` 비상 Abort 수행 | • 비행 중(`NORMAL`) 및 `GAC` 도킹 슬롯 인가<br>• `DOCKING_ARM` 20Hz 전술유도(`Base_sec+10+Idx`) 정상 | `Base+5` `MSG_DOCK_CAPTURE_STAGE` (`stage == "HARD_LOCKED"`) 및 `ARM_DOCKED` 확인 |
| **`ACT_MOB_ARM_UNDOCK`** | `[로드맵: TASK-104]` | **엄빌리컬 해제 및 도킹암 분리 이탈 (`UNDOCK_ARM`)**<br>보급 완료 후 엄빌리컬 연결을 해제하고 `DOCKING_ARM` 격납 위치에서 안전하게 분리·이탈 | • 도킹 결합(`HARD_LOCKED`) 완료 및 `ARMED` 준비 완료<br>• 엄빌리컬 보급 종료 확인 | `Base+5` `MSG_UMBILICAL_STATUS` 분리 및 `ARM_RELEASED` 확인 |

### 4.2 에너지 보급·재충전 및 저부하 대기 계층 (`ACT_NRG_*`, 1종 활성 + 1종 통합 — 구 4.3)

*(슈퍼커패시터 핫스왑 `BAT_SWAP`, 열상승기류 `THERM_SOAR`, 태양광 뱅크각 `SOLAR_OPT`, 수소 퍼지 `FUEL_PURGE` 삭제)*

| 행동 ID | 등급 | 행동 명칭 및 상세 설명 | 핵심 진입 조건 (Pre-conditions) | 완료 조건 및 UAFS 연동 |
| :--- | :---: | :--- | :--- | :--- |
| **`ACT_NRG_REFUEL_DOCK`** | `[로드맵: TASK-104/시설물]` | **도킹암·패드 유체/FE 자동 보급 및 충전 대기**<br>착륙패드(Portable Fluid/Energy Interface) 또는 `DOCKING_ARM` 엄빌리컬(`Base+5` `MSG_UMBILICAL_STATUS`) 체결 상태에서 연료(`mB`)와 에너지(`FE`) 보충을 완료할 때까지 대기 | • `DISARMED` 착륙 완료 또는 `HARD_LOCKED` 도킹 완료<br>• 보급 인터페이스/`MSG_UMBILICAL_STATUS` 활성 | `telemetry.fuel >= targetFuel` (예: `0.95`) 및 보급 완료 통보 확인 |
| **`ACT_NRG_HIBERNATE`** | `[통합: ACT_PER_SENTRY_HOLD]` | **저부하 이벤트 대기 전환 (Standby Sleep) [ACT_PER_SENTRY_HOLD로 통합]**<br>기존 착지 `DISARMED` 상태 저부하 궤적/제어 루프 일시 중단 및 이벤트(`modem_message`, `redstone`, 타이머) 웨이크업 대기 기능은 **`ACT_PER_SENTRY_HOLD`로 완전 통합**됨. (중복 대기 행동 제거 및 전기 기체 자가 충전 로직 일원화, Zero-Fallback 단일 경로 준수) | • `ACT_PER_SENTRY_HOLD` 참조 | `ACT_PER_SENTRY_HOLD`로 통합 이관 |

### 4.3 유무인 복합(MUM-T) 및 이기종(UGV·USV) 합동 계층 (`ACT_MUMT_*`, 3종 — 구 4.5)

*(3D SLAM 지도 정합 `MAP_MERGE`, PRF 레이저 지정 `LASER_DES`, 전파 음영 데이터 뮬 `DATA_MULE` 삭제)*

| 행동 ID | 등급 | 행동 명칭 및 상세 설명 | 핵심 진입 조건 (Pre-conditions) | 완료 조건 및 UAFS 연동 |
| :--- | :---: | :--- | :--- | :--- |
| **`ACT_MUMT_WINGMAN`** | `[로드맵: Zone 4]` | **선도 기체 윙맨(Loyal Wingman) 호위 기동**<br>플레이어 조종기 또는 리더 무인기가 `Zone 4`(`Base+30~39`)로 송출하는 `(X, Y, Z)`·속도·기수각을 수신해 전술 섹터 분리 거리 유지 | • 비행 중(`NORMAL`)<br>• `Zone 4` 전술 데이터링크 수신 정상 및 `radar` 안전 분리 확인 | `DETACH` 명령 또는 호위 해제 스텝 도달 |
| **`ACT_MUMT_UGV_SCOUT`** | `[로드맵: Zone 4]` | **지상 차량(`Offroad`)·함정(`High Seas`) 전방 정찰**<br>이동 중인 아군 지상/해상 대열보다 전방 $50 \sim 300\text{ m}$ 앞서 비행하며 `CC:Radars` / `playerDetector`로 적대 개체·함선을 탐지해 경보 중계 | • 비행 중(`NORMAL`), `Zone 4` 대열 위치·속도 수신<br>• `plane_radar`/`radar` 또는 `playerDetector` 활성 | 대열 목적지 도착 또는 전방 위험 트랙 경보 송출 |
| **`ACT_MUMT_CROSS_CUE`** | `[로드맵: Zone 4/Radars]` | **이기종 레이더 크로스큐잉(Cross-Cueing) 표적 재포착**<br>지상 `radar_monitor` 또는 타 기체가 브로드캐스트한 표적 좌표(`CUE_TARGET_MSG`)로 기동해 탑재 레이더·`POI_HOLD`로 재포착 및 식별 중계 | • `CUE_TARGET_MSG`(좌표, 유효 시한) 수신<br>• 탑재 `radar`/`plane_radar`/`playerDetector` 정상 | 불확실성 반경 내 표적 재포착(`TRACK_LOCKED`) 또는 부재 판정 보고 |

---

## 5. 조합형 확장을 위한 표준 데코레이터(`DEC_*`) 및 복합 매크로(`MAC_*`) 명세

### 5.1 표준 행동 수정자 / 데코레이터 (7종 `DEC_*`)

| 데코레이터 ID | 등급 | 명칭 및 역할 | 결합 가능한 대상 행동 | 적용 시 변경되는 UAFS 내부 동작 메커니즘 |
| :--- | :---: | :--- | :--- | :--- |
| **`DEC_EMCON`** | `[즉시/로드맵]` | **전자침묵·DR 단독 항법 제약** *(구 `STEALTH` + `GNSS_DENIED` 통합)* | 모든 `ACT_NAV_*`, `ACT_PAT_*`, `ACT_MUMT_*` | `avionics_controller.setTransponder(false)` 적용, `CH 60001` GPS 핑·비필수 외부 RF 송출 억제, `nav_engine` DR(또는 탑재 `navigation_table`) 단독 항법 강제 |
| **`DEC_ENERGY_ECO`** | `[즉시]` | **최적 연료 절약 항속 제약** | `ACT_NAV_GOTO_WP`, `ACT_FS_RTL_HOME` | `trajectory_generator`의 순항 속도 및 가속도 상한을 연료 효율 최적 프로파일($V_{\text{ECO}}$)로 제한 |
| **`DEC_TIME_CRIT`** | `[로드맵]` | **목표 도착 시각(ETA) 준수 제약** | `ACT_NAV_*`, `ACT_MUMT_*` | 지정 ETA에 맞춰 `cruiseSpeed`를 기종 물리 허용 한계 내에서 실시간 증감 |
| **`DEC_SMOOTH_TRAJ`** | `[즉시]` | **무경사·저가속 정밀 안정화 제약** *(구 `SMOOTH_CINE` 치환)* | `ACT_NAV_*`, `ACT_PAT_*`, `ACT_PER_TRACK_TGT` | `FCP v2.0.0` `constraintProfile = "STRICT_LEVEL"` 강제 및 선회 각속도·가속도 상한 제한(레이더 스캔·화물 안정화용) |
| **`DEC_HUMAN_AUTH`** | `[즉시]` | **운용자 승인 대기 게이트** | `ACT_PAY_BUS_CMD`, `ACT_PAY_REDSTONE`, `ACT_TKL_LAND_PREC` | `checkPrecondition` 통과 후 실행 직전 `Base+0` GCS/로컬 TUI의 `CONFIRM` 입력 확인 |
| **`DEC_RETRY_N`** | `[즉시]` | **실패 시 자동 재시도 래퍼** | `ACT_TKL_LAND_PREC`, `ACT_MOB_ARM_DOCK` | 착륙 복행(`ABORT_LAND`) 또는 도킹 이탈(`surge = -0.8`) 시 안전 위치 복귀 후 최대 $N$회 재시도 |
| **`DEC_TIMEOUT_GUARD`** | `[즉시]` | **최대 실행 시간 강제 제한** | 모든 공중·대기 행동 | 스텝 경과 시간이 `maxDurationSec` 초과 시 즉시 `abortWhen`(`TIMEOUT_SEC`)으로 분기 |

### 5.2 복합 임무 매크로 (5종 `MAC_*`)

| 매크로 ID | 등급 | 매크로 명칭 | 내부 전개 시퀀스 (Sub-tree Expansion) | 주요 활용 시나리오 |
| :--- | :---: | :--- | :--- | :--- |
| **`MAC_RECON_ORBIT`** | `[즉시]` | **표적 이동-선회-복귀 정찰 매크로** | `ACT_NAV_GOTO_WP` $\to$ (`ACT_PAY_SET_ROI` $\parallel$ [`DEC_SMOOTH_TRAJ` + `ACT_PAT_LOITER_TIME`]) $\to$ `ACT_PAY_CLEAR_ROI` $\to$ [`DEC_ENERGY_ECO` + `ACT_FS_RTL_HOME`] $\to$ `ACT_TKL_LAND_PREC` | 지정 3D 좌표 정찰·기수/포인터 지향 선회 후 자동 귀환 |
| **`MAC_PATROL_RADAR`** | `[로드맵]` | **광역 레이더 수색·표적 추적 매크로** | `ACT_PAT_GRID_SURVEY` 수행 중 표적 포착 시 $\to$ `ACT_PER_TRACK_TGT` (또는 `ACT_PAT_POI_HOLD`) $\to$ 경보 보고 $\to$ 수색/복귀 | `CC:Radars` 기반 구역 초계 및 침입자 추적 |
| **`MAC_SHIP_RECOVERY`** | `[즉시: 동적 패드]` | **해상·차량 이동 갑판 자동 착함 매크로** | `ACT_MOB_RV_TRACK` $\to$ (`WINGED_VTOL` 시 `ACT_TKL_TRANS_FW2MC`) $\to$ `ACT_MOB_DECK_SYNC` $\to$ [`DEC_RETRY_N(3)` + `ACT_TKL_LAND_PREC`] $\to$ `ACT_SYS_DISARM` | `Create: High Seas` 항모 및 `Offroad` 이동 기지 착함 |
| **`MAC_ARM_RESUPPLY`** | `[로드맵: TASK-104]` | **도킹암 포획·엄빌리컬 보급 사이클** | `ACT_MOB_RV_TRACK` $\to$ [`DEC_RETRY_N(2)` + `ACT_MOB_ARM_DOCK`] $\to$ `ACT_NRG_REFUEL_DOCK` $\to$ `ACT_MOB_ARM_UNDOCK` | 무인기 장기 연속 작전을 위한 공중/지상 도킹 재보급 |
| **`MAC_CARGO_SORTIE`** | `[즉시 / TASK-401]` | **화물 투하·레드스톤 작동 왕복 출격** | `ACT_TKL_TAKEOFF_VERT` $\to$ `ACT_NAV_GOTO_WP` $\to$ [`DEC_HUMAN_AUTH` + `ACT_PAY_BUS_CMD`/`ACT_PAY_REDSTONE`] $\to$ `ACT_FS_RTL_HOME` $\to$ `ACT_TKL_LAND_PREC` | 구호품/폭장 투하 및 원격 레드스톤 시설 트리거 출격 |

---

## 6. 기준 미션 시나리오 적용 명세: '목표 이동 - 일정 시간 선회 - 복귀' (`MSN_RECON_001`)

`MAC_RECON_ORBIT` 기반으로 마인크래프트 3D 월드 좌표계와 UAFS `Base+4`/`Base+2`/`GAC` 프로토콜에 맞춰 구성한 기준 시나리오입니다.

### 6.1 시나리오 기준 파라미터

- **기지 좌표 (`Home` / `PAD_BRAVO_01`):** `(X = 0.0, Y = 64.0, Z = 0.0)`
- **목표 좌표 (`Target Waypoint`):** `(X = 450.0, Y = 140.0, Z = -1200.0)` *(기지로부터 수평 거리 약 $1,281.6\text{ m}$)*
- **비행 고도 및 속도:** 순항 고도 `Y = 140.0`, 이동 속도 `18.0 m/s`, 선회 접선 속도 `8.0 m/s`
- **선회 (`LOITER`) 조건:** 반경 `R = 40.0 m`, 방향 시계 방향(`CW`), 유지 시간 `180 s`, 기수/포인터는 중심 좌표 `(450.0, 64.0, -1200.0)` 고정(`headingMode = "POI"` + `ACT_PAY_SET_ROI`)
- **도달 판정 반경 (`acceptanceRadius`):** 수평 `5.0 m`, 수직 `2.0 m`

### 6.2 시나리오 실행 10단계 행동 시퀀스

| 순서 | 적용 표준 행동 ID (데코레이터) | 단계별 수행 역할 | 핵심 파라미터 설정값 | 완료 트리거 (Exit Trigger) | 예외 처리 (Fallback) |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **01** | `ACT_SYS_PREFLIGHT` | 비행 전 자가 점검 | `minFuel: 0.85`, `sensorOk: true`, `probe: true` | `Base+2` 헬스 및 `Base+0` 프로브 통과 | 점검 실패 시 `ABORTED` 및 배너 경보 |
| **02** | `ACT_SYS_ARM` | 2단계 시동 활성화 | `arm: true, flightActive: false`, 타임아웃: `5s` | `controlState == "IDLE_ARMED"` 확인 | `5s` 미완료 시 1회 재시도 후 중단 |
| **03** | `ACT_TKL_TAKEOFF_VERT` | 수직 이륙 | `targetAlt: 140.0`, `facilityId: "PAD_BRAVO_01"` | `|140.0 - altitudeY| <= 2.0m` 진입 | 상승 정체 시 즉시 `ACT_TKL_LAND_NORM` |
| **04** | `ACT_NAV_GOTO_WP` | 목표 접선 진입점 이동 | `targetPos: {450, 140, -1200}`, `speed: 18.0`, `tangentOffset: 40.0` | 접선 진입점 반경 `5.0m` 이내 도달 | GPS 5초 두절 시 `ACT_FS_HOVER_HOLD` |
| **05** | `ACT_PAY_SET_ROI` | 기수 `POI`·Zone 3 지향 고정 | `poiPos: {450, 64, -1200}`, `channelOffset: 20` | `ROI_LOCK` 정렬 및 Zone 3 ACK 확인 | Zone 3 미장착 시 기수 `POI` 단독 지향 |
| **06** | `ACT_PAT_LOITER_TIME`<br>+ `[DEC_SMOOTH_TRAJ]` | 목표 주변 정밀 선회 (`STRICT_LEVEL`) | `radius: 40.0 (CW)`, `durationSec: 180`, `speed: 8.0`, `profile: "STRICT_LEVEL"` | 궤도 진입 후 `180 s` 경과 | 저연료(`<= 0.20`) 시 즉시 `08`로 점프 |
| **07** | `ACT_PAY_CLEAR_ROI` | 지향 고정 해제 및 중립 복귀 | `headingMode: "AUTO"`, `channelOffset: 20` | 중립 복귀 및 Zone 3 해제 ACK 확인 | 응답 지연 시 타임아웃 후 복귀 강행 |
| **08** | `ACT_FS_RTL_HOME`<br>+ `[DEC_ENERGY_ECO]` | 기지 최적 연료 복귀 비행 | `home: {0, 140, 0}`, `ecoSpeed: 12.0` | `Home` 상공 수평 오차 `5.0m` 이내 도달 | 귀환 연료 부족 시 `ACT_FS_GOTO_RALLY` |
| **09** | `ACT_TKL_LAND_PREC`<br>+ `[DEC_RETRY_N(2)]` | `PAD_BRAVO_01` 비콘 정밀 착륙 | `facilityId: "PAD_BRAVO_01"`, `maxAttempts: 2` | `Base+5` 접지 통보 및 `verticalSpeed == 0` | 복행 조건 시 `ACT_TKL_ABORT_LAND` 후 재시도 |
| **10** | `ACT_SYS_DISARM` | 시동 해제 및 미션 종료 | `arm: false, flightActive: false` | `controlState == "DISARMED"` 및 `COMPLETED` | 해제 실패 시 `ACT_SYS_TERMINATE`(`E_STOP`) |

> **선회 궤도 접선 진입(Tangent Entry) 설계 노트:** `ACT_NAV_GOTO_WP`에서 `ACT_PAT_LOITER_TIME`으로 전환할 때 중심 좌표까지 직행한 후 반경 `R = 40.0 m` 원주로 밀려나면 오버슈트(Overshoot)가 발생합니다. 따라서 `trajectory_generator` 또는 경로 전처리기는 중심점으로부터 선회 반경만큼 앞선 **접선 진입점(Tangent Entry Point)**을 계산해 `ACT_NAV_GOTO_WP`의 종점으로 사용합니다.

---

## 7. 시스템 구현용 행동 트리(Behavior Tree) 및 JSON 데이터 규격

### 7.1 행동 트리 (Behavior Tree) 논리 구조 (데코레이터 결합형)

```
[Root: ReactiveFallback (AMM 20Hz 미션 안전 감독기)]
 ├── [Condition] 정상 비행 가능 상태인가? (fuel > 0.20 AND sensorOk AND controlState ~= "E_STOP")
 │    └── (True일 때 실행) [Sequence: 주 미션 시퀀스 (MAC_RECON_ORBIT 기반)]
 │         ├── [Action] ACT_SYS_PREFLIGHT (Base+2 헬스 & Base+0 프로브 점검)
 │         ├── [Action] ACT_SYS_ARM (Base+4 IDLE_ARMED 전이)
 │         ├── [Action] ACT_TKL_TAKEOFF_VERT (Y=140.0 수직 이륙)
 │         ├── [Action] ACT_NAV_GOTO_WP (목표 {450, 140, -1200} 접선 진입점 이동)
 │         ├── [Parallel: 선회 및 표적 지향 동시 수행]
 │         │    ├── [Action] ACT_PAY_SET_ROI (중심 {450, 64, -1200} POI/Zone 3 고정)
 │         │    └── [Decorator: DEC_SMOOTH_TRAJ (constraintProfile="STRICT_LEVEL")]
 │         │         └── [Action] ACT_PAT_LOITER_TIME (반경 40m, 180초 CW 원궤도 선회)
 │         ├── [Action] ACT_PAY_CLEAR_ROI (지향 해제 및 AUTO 복귀)
 │         ├── [Decorator: DEC_ENERGY_ECO (최적 연비 순항 속도 제한)]
 │         │    └── [Action] ACT_FS_RTL_HOME (Home {0, 140, 0} 복귀 비행)
 │         ├── [Decorator: DEC_RETRY_N (maxAttempts=2, 실패 시 ACT_TKL_ABORT_LAND)]
 │         │    └── [Action] ACT_TKL_LAND_PREC (GAC/PAD_BRAVO_01 비콘 정밀 착륙)
 │         └── [Action] ACT_SYS_DISARM (시동 해제 및 미션 완료)
 │
 └── (False일 때 즉시 전환) [Sequence: 비상 대응 시퀀스]
      ├── [Action] ACT_PAY_CLEAR_ROI (탑재체·지향 즉시 해제)
      ├── [Fallback: UAFS 4단 비상 회복]
      │    ├── [Action] ACT_FS_RTL_HOME (1차 저연료 fuel <= 0.20 시 Home 복귀)
      │    ├── [Action] ACT_FS_GOTO_RALLY (Home 복귀 불가 시 CH 50003 최단 가용 패드 대피)
      │    ├── [Action] ACT_FS_HOVER_HOLD (GPS 5,000ms 두절 등 일시 정지/선회 대기)
      │    └── [Action] ACT_FS_EMERG_LAND (2차 위험 fuel <= 0.10 시 -2.0m/s 즉시 착륙)
      └── [Action] ACT_SYS_DISARM (치명적 제어 불능 시 ACT_SYS_TERMINATE Base+1 E_STOP)
```

### 7.2 미션 관리 시스템 입력용 표준 JSON 페이로드 (`v2.0.0` 초안 — UAFS `camelCase` 정합)

기존 `AMM v1.3.0`의 `checkpoints`·`completeWhen`·`abortWhen`·`onEnter`/`onExit`/`onAbort` 구조와 `ICD v1.9.5`의 `camelCase` 명명 규칙을 계승하면서, 신규 **`action` (`ACT_*`)**, **`decorators` (`DEC_*`)**, **`preconditions` (진입 조건)**를 통합한 표준 JSON 스키마입니다(`mav_cmd`·위경도 전면 제거).

```json
{
  "missionId": "MSN_RECON_001",
  "version": "2.0.0",
  "vehicleType": "VECTORED_VTOL",
  "executionMode": "SINGLE",
  "homePosition": {
    "x": 0.0,
    "y": 64.0,
    "z": 0.0,
    "facilityId": "PAD_BRAVO_01"
  },
  "defaults": {
    "cruiseSpeed": 18.0,
    "targetAlt": 140.0,
    "acceptanceRadius": 5.0,
    "headingMode": "AUTO"
  },
  "failsafePolicy": {
    "lowFuelRtlThreshold": 0.20,
    "criticalFuelLandThreshold": 0.10,
    "gpsTimeoutSec": 5.0,
    "linkLossAction": "ACT_FS_RTL_HOME",
    "rallyFallbackAction": "ACT_FS_GOTO_RALLY"
  },
  "checkpoints": [
    {
      "checkpointId": "CP_01_TAKEOFF",
      "action": "ACT_TKL_TAKEOFF_VERT",
      "decorators": [],
      "params": {
        "targetAlt": 140.0,
        "facilityId": "PAD_BRAVO_01"
      },
      "preconditions": {
        "controlState": "IDLE_ARMED",
        "sensorOk": true,
        "minFuel": 0.85,
        "disallowedAirframes": ["FIXED_WING"]
      },
      "completeWhen": {
        "logic": "ALL",
        "conditions": [
          { "type": "ALTITUDE_REACHED", "toleranceM": 2.0 }
        ]
      },
      "abortWhen": {
        "logic": "ANY",
        "conditions": [
          { "type": "TIMEOUT_SEC", "timeout": 60 }
        ]
      }
    },
    {
      "checkpointId": "CP_02_GOTO_ORBIT_ENTRY",
      "action": "ACT_NAV_GOTO_WP",
      "decorators": [],
      "params": {
        "targetPos": { "x": 450.0, "z": -1200.0 },
        "targetAlt": 140.0,
        "cruiseSpeed": 18.0,
        "tangentEntryOffsetM": 40.0
      },
      "preconditions": {
        "controlState": "NORMAL",
        "gpsValid": true,
        "sensorOk": true,
        "minFuel": 0.40
      },
      "completeWhen": {
        "logic": "ALL",
        "conditions": [
          { "type": "PROXIMITY_3D", "toleranceM": 5.0 }
        ]
      }
    },
    {
      "checkpointId": "CP_03_SET_ROI",
      "action": "ACT_PAY_SET_ROI",
      "decorators": [],
      "params": {
        "poiPos": { "x": 450.0, "y": 64.0, "z": -1200.0 },
        "channelOffset": 20,
        "command": "POI_LOCK"
      },
      "preconditions": {
        "controlState": "NORMAL",
        "sensorOk": true
      },
      "onEnter": [
        { "type": "NOTIFY_OPERATOR", "level": "INFO", "message": "ROI LOCK ENGAGED" }
      ],
      "completeWhen": {
        "logic": "ANY",
        "conditions": [
          { "type": "PAYLOAD_RESP_MATCH", "expectedStatus": "OK" }
        ]
      }
    },
    {
      "checkpointId": "CP_04_LOITER_RECON",
      "action": "ACT_PAT_LOITER_TIME",
      "decorators": [
        {
          "decoratorId": "DEC_SMOOTH_TRAJ",
          "overrideParams": {
            "constraintProfile": "STRICT_LEVEL",
            "maxYawRateDegS": 20.0
          }
        }
      ],
      "params": {
        "targetPos": { "x": 450.0, "z": -1200.0 },
        "targetAlt": 140.0,
        "radius": 40.0,
        "direction": "CW",
        "cruiseSpeed": 8.0,
        "headingMode": "POI",
        "poiPos": { "x": 450.0, "y": 64.0, "z": -1200.0 },
        "durationSec": 180.0
      },
      "preconditions": {
        "controlState": "NORMAL",
        "gpsValid": true,
        "minFuel": 0.25
      },
      "completeWhen": {
        "logic": "ALL",
        "conditions": [
          { "type": "DURATION_SEC", "durationSec": 180.0 }
        ]
      },
      "abortWhen": {
        "logic": "ANY",
        "conditions": [
          { "type": "FUEL_LEVEL_BELOW", "threshold": 0.20 }
        ]
      }
    },
    {
      "checkpointId": "CP_05_CLEAR_ROI",
      "action": "ACT_PAY_CLEAR_ROI",
      "decorators": [],
      "params": {
        "channelOffset": 20,
        "command": "POI_RELEASE"
      },
      "preconditions": {
        "controlState": "NORMAL"
      },
      "completeWhen": {
        "logic": "ANY",
        "conditions": [
          { "type": "PAYLOAD_RESP_MATCH", "expectedStatus": "OK" }
        ]
      }
    },
    {
      "checkpointId": "CP_06_RTL_HOME",
      "action": "ACT_FS_RTL_HOME",
      "decorators": [
        {
          "decoratorId": "DEC_ENERGY_ECO",
          "overrideParams": { "ecoCruiseSpeed": 12.0 }
        }
      ],
      "params": {
        "targetPos": { "x": 0.0, "z": 0.0 },
        "targetAlt": 140.0,
        "acceptanceRadius": 5.0
      },
      "preconditions": {
        "controlState": "NORMAL",
        "minFuel": 0.12
      },
      "completeWhen": {
        "logic": "ALL",
        "conditions": [
          { "type": "PROXIMITY_2D", "toleranceM": 5.0 }
        ]
      }
    },
    {
      "checkpointId": "CP_07_LAND_PREC",
      "action": "ACT_TKL_LAND_PREC",
      "decorators": [
        {
          "decoratorId": "DEC_RETRY_N",
          "overrideParams": {
            "maxAttempts": 2,
            "recoveryAction": "ACT_TKL_ABORT_LAND"
          }
        }
      ],
      "params": {
        "facilityId": "PAD_BRAVO_01",
        "targetPos": { "x": 0.0, "z": 0.0 }
      },
      "preconditions": {
        "controlState": "NORMAL",
        "gpsValid": true,
        "disallowedAirframes": ["FIXED_WING"]
      },
      "completeWhen": {
        "logic": "ALL",
        "conditions": [
          { "type": "FACILITY_TOUCHDOWN", "facilityId": "PAD_BRAVO_01" }
        ]
      }
    }
  ]
}
```
