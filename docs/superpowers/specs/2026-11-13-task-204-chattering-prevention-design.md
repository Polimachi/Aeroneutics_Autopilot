# 자율 비행체 미션 관리 시스템(AMM) 채터링(Chattering) 방지 규칙 및 설계 명세

> **문서 성격**: `TASK-124` 설계 명세 (`Design Spec` — `TASK-204` 선행 채터링 방지 가드 정합화)  
> **작성일**: `2026-11-13`  
> **대상 환경**: `Minecraft CC:Tweaked (Lua 5.2)`, `Create: Aeronautics`, `Create: Avionics`, `Create: Radars`, `Create Propulsion: Simulated`, `Advanced Peripherals`  
> **기준 문서 및 코드**: [2026-11-12-task-204-action-primitive-design.md](./2026-11-12-task-204-action-primitive-design.md), [AMM_PROGRAM_SPECIFICATION.md](../../specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md) (`v1.3.0`), [amm_config.json](../../../src/3_planning/amm/config/amm_config.json), [fcp_config.json](../../../src/2_guidance/fcp/config/fcp_config.json), [nav_engine.lua](../../../src/3_planning/amm/modules/nav_engine.lua), [facility_client.lua](../../../src/3_planning/amm/modules/facility_client.lua)

---

## 1. 목적, 적용 경계 및 비목표

### 1.1 목적 및 배경
자율 비행체 미션 관리 계층(`AMM`, Node 03)에서 센서 측정값·속력·연료·좌표가 상태 전이 임계값 경계에서 진동할 때 두 행동(`ACT_*`)이나 조건 판정이 짧은 주기로 제어권을 번갈아 선점하는 **채터링(Chattering / State Oscillation)**을 억제하기 위한 설계 명세입니다.

본 문서는 범용 실세계 UAV 기준 초안을 **마인크래프트 인게임 제약**과 **현행 UAFS 코드베이스 경계**에 맞게 재정립하며, [2026-11-12-task-204-action-primitive-design.md](./2026-11-12-task-204-action-primitive-design.md) 및 `TASK-204`의 `[즉시]` 36종 액션 체계와 1:1 정합됩니다.

### 1.2 적용 범위 분리 (`[즉시]` vs `[로드맵]`)
- **본 규격 (`[즉시]` — `TASK-124` / `TASK-204` 구현 대상)**:
  - `ACT_FS_FENCE_BRAKE` (지오펜스 경계 제동), `ACT_FS_RTL_HOME` / `ACT_FS_EMERG_LAND` (저연료 래치), `ACT_FS_HOVER_HOLD` (GPS 두절·복구), `ACT_TKL_TRANS_MC2FW` $\leftrightarrow$ `ACT_TKL_TRANS_FW2MC` (VTOL 천이), `ACT_MOB_DECK_SYNC` / `ACT_TKL_ABORT_LAND` (동적 갑판 요동·복행), `ACT_NAV_*` / `ACT_PAT_HOLD_POS` / `ACT_TKL_TAKEOFF_VERT` (목표 도착 안착 불감대).
- **격리 규격 (`[로드맵]` — 7장 분리 수록)**:
  - `ACT_PER_LOCAL_AVOID`, `ACT_PER_REPLAN_GLB`, 3차원 복셀 시공간 클리어런스(Swept Volume LOS Clearance), 경로 교체 비용 마진, 기계식 베어링/서브컨트랩션 변형 시 임계값 동결 규칙(`항목 E`).

### 1.3 비목표 및 금지 사항 (Non-Goals & Anti-Goals)
- **VAS/FCP ICD 미확장 원칙**: `VAS Base+2` (`MSG_FLIGHT_TELEMETRY`) 또는 `FCP Base+4` 패킷 스키마를 확장하여 기체 외접 반경($R_{\text{bound}}$), 최대 감속도($a_{\text{max}}$), 응답 시상수($\tau_{\text{mech}}$), 실시간 연료 소비율($P_{\text{consume}}$)이나 Create 회전력(`SU`)·보일러 열량을 신규 송출하지 않습니다.
- **미지원 인게임 API 비의존**: CC:Tweaked가 직접 제공하지 않는 3D 복셀 점유 볼륨 레이캐스트나 미로딩 청크(Unloaded Chunk) 직접 질의에 의존하지 않습니다.
- **실시간 루프 비블로킹**: 모든 디바운스·유지 카운터는 `Coroutine A` (`step_20hz_tick`) 내부에서 비차단 상태로 평가하며 `sleep()`을 호출하지 않습니다.

---

## 2. 마인크래프트 인게임 및 UAFS 런타임 전제 조건

1. **이원화 시간 기준 (Dual-Timebase Specification):**
   - **물리·제어 전이 가드 (`step_20hz_tick` 정수 틱, $N \in \mathbb{Z}^+$):** 상태 전이 디바운스($N_{\text{debounce}}$), 최소 유지 시간($N_{\text{dwell}}$), 도착 안착 유지($N_{\text{settle}}$)는 `src/3_planning/amm/main.lua`의 `step_20hz_tick` 호출마다 `1`씩 증가하는 정수 틱 카운터(`tickCount`)로 측정합니다. 공칭 1틱은 마인크래프트 $20\text{ TPS}$ 기준 $\Delta t_{\text{tick}} = 0.05\text{ s}$이며, 서버 TPS 저하 시 물리 틱 속도에 자연 동기화되어 현실 시간 기준 조기 오작동을 방지합니다.
   - **통신·링크 워치독 (`now_ms` 유지):** 패킷 수신 두절 감시(`nav_engine.gpsTimeoutMs = 5000`, `nav_engine.coreTimeoutMs = 500`, `facility_client.dynamicGuideTimeoutMs = 300`, `fcp_config.ammSetpointTimeoutMs = 500`)는 현행 코드베이스의 `now_ms`(`os.epoch("utc")`) 기준을 그대로 유지합니다.
2. **공간 복셀 양자화 및 구동계 출력 양자화:**
   - 월드 지형과 좌표는 $1\text{ Block} = 1.0\text{ m}$ 격자로 구성되며, 하위 `TCA`([node_tca.lua](../../../src/1_control/vas/node_tca.lua))는 추진기를 레드스톤 **$0 \sim 15$ 정수 단계**로 구동할 수 있습니다. 이 이산 출력 양자화와 $0.05\text{ s}$ 틱 지연은 목표 좌표/고도 경계 부근에서 $1 \sim 2\text{ Blocks}$ 왕복 진동(Limit Cycle)을 유발할 수 있으므로 도착 안착 유지(`N_settle`)와 이탈 불감대를 적용합니다.
3. **고정 파라미터 직접 지정 원칙:**
   - 런타임 Lua 코드는 $R_{\text{bound}}, a_{\text{max}}, \tau_{\text{mech}}$ 기반 동적 수식을 실시간 계산하지 않고, [amm_config.json](../../../src/3_planning/amm/config/amm_config.json)에 명시된 고정 수치(`safety.chattering.*`)를 직접 읽습니다. 기체 체급별 정규화 수식은 운영자가 설정값을 튜닝하기 위한 참고 이론치(부록 A)로만 활용합니다.
4. **UAFS 가용 실측 데이터 계약 (`Zero-Fallback`):**
   - 연료는 `VAS Base+2`의 단일 정규화 비율 **`telemetry.fuel` ($0.0 \sim 1.0$)**만을 사용합니다 (`sensor_pipeline.lua`의 유체 탱크 `mB` 및 `FE` 통합 비율).
   - VTOL 천이 속력 기준은 `FCP` [fcp_config.json](../../../src/2_guidance/fcp/config/fcp_config.json#L59-L60)의 `wingedVtolVLowMps` (`8.0 m/s`) 및 `wingedVtolVHighMps` (`18.0 m/s`)와 정합합니다.
   - GPS 복구 판정은 [nav_engine.lua](../../../src/3_planning/amm/modules/nav_engine.lua#L238)의 기존 구현(`gpsRecovered = (state.validStreak >= 3)`)을 단일 경로로 사용합니다.

---

## 3. 채터링 가드 모듈화 아키텍처 (Approaches & Selected Design)

### 3.1 구현 아키텍처 대안 비교

| 비교 항목 | 방안 A: 중앙 전이 가드(`chattering_guard.lua`) + `condition_evaluator` 안착 틱 통합 (채택) | 방안 B: 개별 모듈·액션 핸들러 분산 구현 |
| :--- | :--- | :--- |
| **상태 관리 위치** | 신규 경량 모듈 `chattering_guard.lua`가 히스테리시스·`debounce` 연속 카운터·`dwell` 잠금 틱·단방향 `latch` 상태를 단일 레지스트리 테이블로 관리하고, `condition_evaluator.lua`가 `settleTicks`를 평가 | `mission_engine`(연료 래치), 각 `ACT_*` 핸들러(지오펜스·천이), `facility_client`(갑판 요동), `condition_evaluator`(도착)에 카운터·래치 분산 |
| **우선순위 선점 및 초기화** | 상위 선점 예외(`E_STOP > ACT_FS_* > ABORT_LAND > 일반`) 적용 시 하위 가드 카운터를 일괄 정리하고, `DISARMED`/`engine:stop()` 시 모든 래치를 단일 호출(`guard:reset()`)로 초기화 | 각 모듈에 리셋 훅을 개별 연결해야 하며, 선점 전환 시 잔여 카운터 리셋 누락 위험 존재 |
| **함수 복잡도 및 테스트성** | `chattering_guard.lua` 단독 단위/돌연변이 테스트 가능, 36종 `ACT_*` 핸들러를 50줄 이하로 유지 가능 | 각 `ACT_*` 핸들러 내부에 상태 추적 분기가 중첩되어 코드량 증가 |
| **평가 결과** | **최종 채택** (`TASK-124` / `TASK-204` 표준 가드 모듈로 확정) | 기각 (상태 분산 및 초기화 누락 위험) |

### 3.2 UAFS 우선순위 선점 위계 및 상향 선점 예외 원칙

구형 범용 우선순위 라벨(`P0~P4`)을 폐기하고, UAFS 실제 제어 위계를 기준으로 **상향 선점 예외(Upward Preemption Exception)**를 적용합니다.

```text
[1] Base+1 Hard E-Stop          (ACT_SYS_TERMINATE / VAS controlState == "E_STOP")
[2] 치명적 비상 착륙            (ACT_FS_EMERG_LAND: fuel <= 0.10 래치, 10s 홀드 만료, [L])
[3] 지오펜스 경계 제동          (ACT_FS_FENCE_BRAKE: 수평/고도 경계 침범·임박)
[4] 안전 귀환 / 대피 / 체공     (ACT_FS_GOTO_RALLY, ACT_FS_RTL_HOME: fuel <= 0.20 래치, ACT_FS_HOVER_HOLD: GPS 두절)
[5] 착륙 복행                   (ACT_TKL_ABORT_LAND: 동적 갑판 요동/300ms 워치독 초과)
[6] 일반 비행·임무 행동         (ACT_TKL_TRANS_*, ACT_NAV_*, ACT_PAT_*, ACT_MOB_*, ACT_PAY_*, ACT_COM_*)
```

- **상향 선점 원칙:** `N_dwell` 잠금은 현재 행동보다 **낮은(또는 동일한) 우선순위**로 복귀할 때만 해제 전환을 잠급니다. 유지 틱이 남아 있더라도 더 높은 우선순위(`[1]~[5]`) 조건이 확정되면 `N_dwell`을 즉시 무시하고 상위 행동으로 선점합니다.

---

## 4. `[즉시]` 적용 5대 채터링 방지 규칙 상세

### 4.1 이중 임계값 히스테리시스 (Dual-Threshold Hysteresis)

특정 조건으로 진입할 때의 임계값($\theta_{\text{enter}}$)과 해제하고 복귀할 때의 임계값($\theta_{\text{exit}}$)을 분리해 불감대($\Delta H = |\theta_{\text{exit}} - \theta_{\text{enter}}|$)를 형성합니다.

1. **지오펜스 경계 여유 거리 (`ACT_FS_FENCE_BRAKE`):**
   - 경계까지의 여유 거리가 **`fenceBrakeMarginM` (`5.0 m`) 이하**로 진입(또는 외곽 이탈)하면 제동·후퇴를 발동하고, 지오펜스 내부 **`fenceReleaseMarginM` (`15.0 m`) 이상**으로 복귀해야 해제합니다 ($\Delta H = 10.0\text{ m}$).
2. **`WINGED_VTOL` 천이 속력 (`ACT_TKL_TRANS_MC2FW` $\leftrightarrow$ `ACT_TKL_TRANS_FW2MC`):**
   - `fcp_config.json`의 천이 대역(`8.0 ~ 18.0 m/s`)과 정합하여, 순항 천이(`MC2FW`) 완료 및 고정익 유지 상한 기준 **`vtolCruiseEnterMps = 18.0 m/s`**, 역천이(`FW2MC`) 강제 안전 하한 기준 **`vtolHoverReturnMps = 8.0 m/s`**로 분리해 $\Delta H_v = 10.0\text{ m/s}$ 불감대를 형성합니다.
3. **동적 갑판 요동 안전 윈도우 (`ACT_MOB_DECK_SYNC` $\leftrightarrow$ `ACT_TKL_ABORT_LAND`):**
   - 착륙 진행 중 **Abort 진입(비상 이탈)**: 갑판 기울기(Pitch/Roll) **`> 10.0°`** 또는 수직 승강 속력 **`> 2.5 m/s`** (`LANDING_PAD v2.4.3` 규격 상한).
   - 복행 후 **재동기화 진입 허용**: 갑판 기울기 **`<= 7.0°`** 및 수직 승강 속력 **`<= 1.8 m/s`** ($\Delta H_{\text{tilt}} = 3.0^\circ$, $\Delta H_{\text{heave}} = 0.7\text{ m/s}$).
4. **체공·유지 이탈 재보정 경계 (`ACT_PAT_HOLD_POS` / `ACT_NAV_GOTO_WP` 후속 안착):**
   - 도달 판정 반경(`acceptanceRadius`, 기본 `5.0 m`) 이내로 안착한 상태에서 외부 외란이나 레드스톤 양자화 드리프트로 반경 경계를 스치더라도 즉시 재접근 모드로 튀지 않도록 **`reengageMarginM = 2.0 m`**를 더한 `acceptanceRadius + 2.0 m` 초과 시에만 재추종합니다.

### 4.2 진입 디바운스 (Entry Debounce Ticks, $N_{\text{debounce}}$)

측정값이 $\theta_{\text{enter}}$를 위반한 뒤 **연속된 $N_{\text{debounce}}$ 틱(`step_20hz_tick`) 동안 매 틱 참(True)**으로 유지될 때만 상태 전이를 확정합니다. 1틱이라도 거짓이 되면 연속 카운터(`streak`)를 `0`으로 초기화합니다.

| 적용 대상 (`[즉시]`) | 전이 방향 / 트리거 조건 | 권장 디바운스 ($N_{\text{debounce}}$) | 공칭 시간 ($20\text{ TPS}$) | 비고 |
| :--- | :--- | :---: | :---: | :--- |
| **`ACT_FS_FENCE_BRAKE`** | 지오펜스 여유 $\le 5.0\text{ m}$ | **`2 Ticks`** | `0.10 s` | 빠른 경계 방어 우선 |
| **`ACT_TKL_ABORT_LAND`** | 동적 갑판 요동 $> 10.0^\circ$ 또는 $> 2.5\text{ m/s}$ | **`2 Ticks`** | `0.10 s` | 단일 패킷 순간 노이즈만 배제하고 신속 복행 |
| **`ACT_MOB_DECK_SYNC`** | 갑판 요동 $\le 7.0^\circ$ & $\le 1.8\text{ m/s}$ 안정화 | **`10 Ticks`** | `0.50 s` | 안전 비대칭: 착륙 허가는 보수적 확인 |
| **`ACT_TKL_TRANS_*`** | `MC2FW` ($\ge 18\text{ m/s}$) / `FW2MC` ($\le 8\text{ m/s}$) | **`10 Ticks`** | `0.50 s` | 순간 돌풍/가감속 피크에 의한 반복 천이 억제 |
| **`ACT_FS_RTL_HOME`** | `telemetry.fuel <= 0.20` (`lowFuelRthThreshold`) | **`60 Ticks`** | `3.00 s` | 순간 센서 튐 방지 후 `RTL_LATCH` 진입 |
| **`ACT_FS_EMERG_LAND`** | `telemetry.fuel <= 0.10` (`emergencyLandFuelThreshold`) | **`30 Ticks`** | `1.50 s` | 위험 고갈 확정 후 `EMERG_LAND_LATCH` 진입 |
| **`ACT_FS_HOVER_HOLD`** 해제 | GPS 두절 복귀 | **`validStreak >= 3` fixes** | (`nav_engine` 기구현) | `nav_engine.gpsRecovered` 단일 경로 재사용 |

### 4.3 최소 유지 시간 (Minimum Dwell Ticks, $N_{\text{dwell}}$)

상태 전환 발생 틱 $k_{\text{switch}}$ 이후 해제 임계값($\theta_{\text{exit}}$)을 만족하더라도 **$k - k_{\text{switch}} \ge N_{\text{dwell}}$**을 충족하기 전까지는 하위 우선순위 행동으로의 복귀를 잠급니다.

| 적용 대상 (`[즉시]`) | 최소 유지 틱 ($N_{\text{dwell}}$) | 공칭 시간 ($20\text{ TPS}$) | 해제 잠금 목적 |
| :--- | :---: | :---: | :--- |
| **`ACT_FS_FENCE_BRAKE`** | **`40 Ticks`** | `2.00 s` | 경계선 급제동 및 내부 복귀 기동 안정화 |
| **`ACT_TKL_ABORT_LAND`** | **`60 Ticks`** | `3.00 s` | 복행 상승 고도 확보 후 `DEC_RETRY_N` 재접근 허용 |
| **`ACT_TKL_TRANS_MC2FW` / `FW2MC`** | **`100 Ticks`** | `5.00 s` | 천이 직후 역천이 재진입 진동 방지 |

### 4.4 단방향 비가역 래치 (One-Way Irreversible Latch)

물리적으로 비행 중 자연 회복되지 않는 자원 고갈(`telemetry.fuel`) 페일세이프에는 해제 임계값을 두지 않고 **단방향 래치**를 적용합니다.

1. **`RTL_LATCH` (`ACT_FS_RTL_HOME`):**
   - `telemetry.fuel <= 0.20` (`amm_config.safety.lowFuelRthThreshold`) 상태가 `60 Ticks` 연속 유지되면 `latches.rtl = true`로 고정합니다.
   - 이후 감속·하강으로 일시적으로 연료 비율 변동이 없거나 스쳐도 임무 시퀀스로 복귀하지 않으며, 오직 `EMERG_LAND_LATCH` 또는 `E_STOP`으로만 단방향 승격됩니다.
2. **`EMERG_LAND_LATCH` (`ACT_FS_EMERG_LAND`):**
   - `telemetry.fuel <= 0.10` (`amm_config.safety.emergencyLandFuelThreshold`) 상태가 `30 Ticks` 연속 유지되면 `latches.emergLand = true`로 고정하고, 착륙 접지 완료까지 상승·순항 복귀를 차단합니다.
3. **래치 해제 경계 (Reset Boundary):**
   - 래치는 비행 중 자동 해제되지 않으며, ① `VAS Base+2 controlState == "DISARMED"` 착지 완료 후 `mission_engine:stop()` / `COMPLETE` 처리되거나, ② 지상 보급 후 `fuel > 0.25` (`0.20 + 0.05` 마진) 상태에서 `engine:start()`가 호출될 때만 `guard:reset()`으로 일괄 해제됩니다.

### 4.5 목표 도착 안착 유지 및 불감대 (`N_settle` — 항목 D)

하위 `TCA`의 레드스톤 `0~15` 정수 양자화 추력과 $0.05\text{ s}$ 틱 이산화로 인해 기체가 목표 좌표·고도 경계($\pm\text{tolerance}$)에 1틱만 스쳤다가 튕겨 나가는 Limit Cycle 및 오완료 판정을 방지하기 위해 `condition_evaluator.lua`에 **안착 유지 틱(`settleTicks`)**을 도입합니다.

- **대상 조건**: `PROXIMITY_2D`, `PROXIMITY_3D`, `ALTITUDE_REACHED`
- **평가 규칙**:
  - 기체가 허용 반경/고도 오차 이내에 진입한 상태로 **연속 `settleTicks` 틱 동안 이탈하지 않을 때만** 조건을 `true`로 확정합니다.
  - 안착 카운팅 도중 허용 오차를 벗어나면 카운터를 `0`으로 리셋합니다 (`PROXIMITY_*` 재진입은 히스테리시스 없이 설정 `toleranceM` 기준, 완료 후 체공 유지는 4.1절의 `reengageMarginM` 적용).
- **기본값 구분 (행동 성격별 차등)**:
  - **정지·안착형 (`ACT_NAV_GOTO_WP`, `ACT_NAV_CHANGE_ALT`, `ACT_TKL_TAKEOFF_VERT`, `ACT_PAT_LOITER_ALT`):** 기본 `settleTicks = 4` (`0.20 s` 공칭)
  - **무정지 통과형 (`ACT_NAV_SPLINE_WP`):** 기본 `settleTicks = 0` (반경 진입 즉시 감속 없이 다음 스텝 전이)

---

## 5. `amm_config.json` 규격 및 `chattering_guard.lua` API 계약

### 5.1 `amm_config.json` 추가 설정 블록 (`safety.chattering`)

기존 `safety.lowFuelRthThreshold` (`0.20`) 및 `safety.emergencyLandFuelThreshold` (`0.10`)를 유지한 채 아래 `chattering` 하위 블록을 추가합니다.

```json
{
  "safety": {
    "lowFuelRthThreshold": 0.20,
    "emergencyLandFuelThreshold": 0.10,
    "chattering": {
      "fenceBrakeMarginM": 5.0,
      "fenceReleaseMarginM": 15.0,
      "fenceDebounceTicks": 2,
      "fenceDwellTicks": 40,
      "lowFuelDebounceTicks": 60,
      "emergFuelDebounceTicks": 30,
      "fuelLatchResetMargin": 0.05,
      "vtolCruiseEnterMps": 18.0,
      "vtolHoverReturnMps": 8.0,
      "vtolTransDebounceTicks": 10,
      "vtolTransDwellTicks": 100,
      "deckAbortTiltDeg": 10.0,
      "deckSafeTiltDeg": 7.0,
      "deckAbortHeaveMps": 2.5,
      "deckSafeHeaveMps": 1.8,
      "deckAbortDebounceTicks": 2,
      "deckSyncDebounceTicks": 10,
      "goAroundDwellTicks": 60,
      "arrivalSettleTicks": 4,
      "arrivalReengageMarginM": 2.0
    }
  }
}
```

### 5.2 `chattering_guard.lua` 모듈 인터페이스 (`TASK-124` / `TASK-204` 구현 계약)

`src/3_planning/amm/modules/chattering_guard.lua`는 순수 Lua 테이블 기반(외부 CC API 비의존)으로 다음 계약을 제공합니다.

- `chattering_guard.init(config)` $\to$ `state`: 설정 로드 및 `debounce`, `dwell`, `latches`(`lowFuelLatched`, `emergFuelLatched`) 테이블 초기화.
- `chattering_guard.reset(state)` $\to$ `nil`: `engine:stop()` 또는 `DISARMED` 이후 재기동 시 모든 `debounce`, `dwell`, `latches` 초기화.
- `chattering_guard.eval_hysteresis(prevActive, value, enterTh, exitTh, mode)` $\to$ `boolean`: `"LOW_ACTIVE"` (`<= enterTh` 진입 / `>= exitTh` 해제) 또는 `"HIGH_ACTIVE"` (`>= enterTh` 진입 / `<= exitTh` 해제) 평가.
- `chattering_guard.eval_debounce(state, key, condition, requiredTicks)` $\to$ `boolean`: `condition == true` 연속 틱 누적; `requiredTicks` 도달 시 `true` 반환, `false` 시 즉시 `0` 리셋.
- `chattering_guard.start_dwell(state, key, nowTick, dwellTicks)` / `chattering_guard.is_dwell_locked(state, key, nowTick, currentPrio, candidatePrio)` $\to$ `boolean`: `candidatePrio < currentPrio` (상위 우선순위 선점, 숫자가 작을수록 상위)이면 잠금 즉시 무시(`false`), 그 외에는 `nowTick < dwell[key]` 동안 `true` 반환.
- `chattering_guard.update_fuel_latches(state, fuel, cfg, isDisarmed)`: `fuel <= 0.20` (`60 Ticks`) 시 `latches.lowFuelLatched = true`, `fuel <= 0.10` (`30 Ticks`) 시 `latches.emergFuelLatched = true` 설정. `isDisarmed` 및 `fuel > 0.20 + fuelLatchResetMargin` 충족 시에만 수동/재기동 리셋 허용.

---

## 6. 검증 기준 (`TASK-124` / `TASK-204` 단위·E2E 테스트 시나리오)

구현 완료 시 아래 채터링 시나리오가 단위 테스트 및 E2E 회귀 테스트에서 검증되어야 합니다.

1. **지오펜스 경계 진동 억제:** 경계 `4.8m` $\leftrightarrow$ `6.0m`를 1틱 주기로 왕복할 때 `2 Ticks` 디바운스·`40 Ticks` 유지 및 `15.0m` 복귀 전까지 `ACT_FS_FENCE_BRAKE`가 해제되지 않음.
2. **연료 단방향 래치 및 승격:** `fuel = 0.20` 60틱 유지로 `RTL_LATCH` 진입 후 `fuel = 0.22`로 순간 회복되어도 미션 복귀 불가, `fuel = 0.10` 30틱 유지 시 `EMERG_LAND_LATCH`로만 승격, `DISARMED` + `fuel = 0.90` + `start()` 시 정상 초기화.
3. **상향 선점 예외:** `ACT_FS_FENCE_BRAKE` 40틱 유지 잠금 중(`tick = 10`) `EMERG_LAND_LATCH` 또는 `E_STOP` 발생 시 `N_dwell`을 무시하고 즉시 선점.
4. **VTOL 천이 히스테리시스:** `18.0 m/s`와 `8.0 m/s` 사이의 중간 속력(`12.0 ~ 17.5 m/s`)에서 반복 왕복 시 `100 Ticks` 유지 + 히스테리시스로 천이 재발 없음.
5. **레드스톤 양자화 도착 Limit Cycle 방어:** 목표 반경 경계(`5.0m`)에 1틱 진입 후 다음 틱에 `5.4m`로 튕기는 조건에서 `settleTicks = 4` 동안 조기 완료되지 않고, 4틱 연속 유지 시에만 완료(`ACT_NAV_SPLINE_WP`는 `0 Ticks` 즉시 통과).
6. **TPS 저하 비동기성 불변 검증:** `step_20hz_tick`을 가상 `now_ms` 간격 `100ms`(`10 TPS` 모사)로 호출해도 `N_debounce`/`N_dwell`은 틱 수 기준으로 정확히 동작하고, 통신 워치독(`5000ms`/`300ms`)은 `now_ms` 기준으로 동작함.

---

## 7. `[로드맵]` 보류 규칙 (후속 확장 영역)

본 장의 규칙은 `TASK-124` 및 `TASK-204` 본 구현 범위에서 제외되며, 전방 장애물 회피(`ACT_PER_LOCAL_AVOID`)·전역 경로 재계획(`ACT_PER_REPLAN_GLB`) 및 서브컨트랩션 연동 태스크 착수 시 적용합니다.

### 7.1 시공간 클리어런스 및 경로 교체 마진 (`ACT_PER_LOCAL_AVOID`, `ACT_PER_REPLAN_GLB`)
- **가시선 클리어런스:** `laser_sensor` 또는 `CC:Radars` / `geoScanner` 기반으로 원래 경로 합류 방향에 안전 여유 반경(`R_bound + max(2.0, 0.2 * R_bound)`) 및 전방 정지 거리(`R_bound + v^2/(2*a_max) + v`) 내 점유 장애물이 `0개`이고, 속도 벡터 교각이 `25°` 이내일 때만 전역 경로로 복귀합니다.
- **경로 교체 비용 히스테리시스:** 신규 산출 경로 비용 $J_{\text{new}}$가 현재 잔여 경로 비용 $J_{\text{current}}$ 대비 $20\%$ 이상 우수할 때만($J_{\text{new}} \le 0.80 \cdot J_{\text{current}}$) 경로를 교체하며, 재계획 최소 주기는 $N_{\text{replan}} \ge 20\text{ Ticks}$로 제한합니다.

### 7.2 서브컨트랩션 변형 시 임계값 원자적 동결 (`항목 E`)
- 기체에 부착된 Create 기계식 베어링(`Mechanical Bearing`)·피스톤 등 서브컨트랩션이 구동되어 기체 외형 반경($R_{\text{bound}}$) 및 질량 중심(CoM)이 실시간으로 변하는 구간 동안에는 장애물 회피 임계값($\theta_{\text{enter}}, \theta_{\text{exit}}$) 갱신을 일시 동결하고, 구동 완료 후 최소 안정화 유지 시간(`Atomic Dwell`) 경과 뒤 새 기체 반경을 반영합니다.

---

## 부록 A. 기체 체급별 `amm_config.json` 튜닝 참고표 (이론 기준치)

> [!NOTE]
> 아래 수식과 표는 **런타임 코드에서 직접 계산하지 않는 오프라인 운영자 튜닝 참고치**입니다. 운영자는 자신의 기체 크기($R_{\text{bound}}$), 최대 순항 속력($v$), 최대 제동 감속도($a_{\text{max}}$)를 바탕으로 아래 기준치를 계산한 뒤 [amm_config.json](../../../src/3_planning/amm/config/amm_config.json)의 `safety.chattering` 고정 필드에 반영할 수 있습니다.

- **기체 고유 참고 변수:** $R_{\text{bound}}$ (CoM~외곽 최대 반경, Blocks), $v$ (속력, Blocks/s), $a_{\text{max}}$ (최대 감속도, Blocks/s²), $d_{\text{stop}} = \frac{v^2}{2 a_{\text{max}}}$, $\tau_{\text{mech}} \approx 4 + 1.5 R_{\text{bound}}$ (Ticks)

| 구분 항목 | 오프라인 산출 참고식 | 소형 고속 기체<br>($R_{\text{bound}}=2$, $v=25$, $a_{\text{max}}=15$) | 중형 표준 기체<br>($R_{\text{bound}}=8$, $v=12$, $a_{\text{max}}=6$) | 대형 고관성 함선<br>($R_{\text{bound}}=30$, $v=5$, $a_{\text{max}}=1.5$) |
| :--- | :--- | :---: | :---: | :---: |
| **틱당 이동량 ($\Delta d_{\text{tick}}$)** | $0.05 v$ | `1.25 B/tick` | `0.60 B/tick` | `0.25 B/tick` |
| **최소 제동 거리 ($d_{\text{stop}}$)** | $\frac{v^2}{2 a_{\text{max}}}$ | `20.8 B` | `12.0 B` | `8.3 B` |
| **지오펜스 진입/해제 여유** | $d_{\text{stop}} + 0.1v + 1 \to +\max(5, 0.5 R_{\text{bound}})$ | `24.3 B → 29.3 B`<br>(`2 Ticks`) | `14.2 B → 19.2 B`<br>(`2 Ticks`) | `9.8 B → 24.8 B`<br>(`2~3 Ticks`) |
| **지오펜스 최소 유지 ($N_{\text{dwell}}$)** | $\left\lceil \frac{v}{0.05 a_{\text{max}}} \right\rceil + 40$ | `74 Ticks` | `80 Ticks` | `107 Ticks` |
| **`[로드맵]` 장애물 진입/해제** | $R_{\text{bound}}+d_{\text{stop}}+0.15v+2 \to +\max(3, 0.3 R_{\text{bound}}+0.5v)$ | `28.6 B → 41.7 B` | `23.8 B → 32.2 B` | `41.1 B → 52.6 B` |
| **`[로드맵]` 장애물 최소 유지** | $\max(40, \lceil 3.0 \cdot \tau_{\text{mech}} \rceil)$ | `40 Ticks` | `80 Ticks` | `200 Ticks` |
