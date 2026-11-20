# TCA — 20Hz 분산 추진기 클러스터 구동기 플레이북

> **대상 코드베이스**: `src/1_control/tca/` (`main.lua`, `tools/tca_setup.lua`)  
> **관련 사양서**: [TCA_PROGRAM_SPECIFICATION.md](../../docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`TCA (Thruster Cluster Adapter)`는 `VAS`로부터 수신한 20Hz 추력·짐벌 벡터 지령(`Base+10`)을 실제 물리 추진기(`Redstone` 출력 또는 `Create Propulsion: Simulated` API 페리페럴)에 인가하는 분산 구동 노드입니다.

- **이중 구동 모드 (`REDSTONE` / `API`)**: 일반 레드스톤 강도(`0~15`) 제어뿐 아니라 `API` 모드에서 `ion_thruster`, `vector_thruster`, `thruster` 등 페리페럴을 다수 묶어 제어하고 개체별 건전성(`NOMINAL`/`DEGRADED`/`TOTAL_LOSS`)을 `VAS`에 보고합니다.
- **300ms 페일세이프 워치독**: `VAS`로부터 `300ms` 이상 추력 지령이 끊기면 즉시 모든 추진기 출력을 `0`으로 차단해 폭주를 막습니다.
- **재조립 동적 리바인딩 & PBIT 위글 (`TASK-136`, `TASK-131`)**: 컨트랩션 재조립으로 유선 페리페럴 이름이 바뀌어도 `logicalBindingMap` 순번으로 자동 재매핑하며, 지상 대기(`DISARMED`/`IDLE_ARMED`) 중에만 `< 5%`(`pulseRatio <= 0.04`) PBIT 위글 응답을 수행합니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 구분 | 품목 / 페리페럴 | 필수 여부 | 비고 |
| :--- | :--- | :---: | :--- |
| 컴퓨터 | Computer 또는 Advanced Computer | 필수 | 클러스터 그룹(`THR_MAIN_L` 등)별 1대 이상 |
| 통신 | Wireless Modem (`modemSide: "top"` 기본) | 필수 | `VAS` `Base+10` 및 격납고 `Base_hangar+3` 수신 |
| 추진기 (`REDSTONE`) | 레드스톤 배선 또는 `redstoneIntegrator` | 선택 | `interactionMode == "REDSTONE"` 시 사용 (`redstoneSide`) |
| 추진기 (`API`) | `Create Propulsion: Simulated` 추진기 (`ion_thruster`, `vector_thruster`, `thruster` 등) | 선택 | `interactionMode == "API"` 시 인접 면(`apiSides`) 또는 유선 모뎀 연결 |

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. **추진기 그룹화 (`groupId`)**:
   - 기체의 좌/우/전/후 또는 상하향 추진기 위치에 따라 `THR_MAIN_L`, `THR_MAIN_R`, `THR_RCS_FWD` 등 그룹별로 `TCA` 컴퓨터를 두거나, 유선 모뎀 케이블로 동일 역할 추진기들을 한 `TCA`에 묶습니다.
2. **인접 면 및 유선 결선**:
   - `REDSTONE` 모드: 기본 출력 면은 `bottom`(`ports.redstoneSide`)입니다. 추진기 레드스톤 입력과 맞닿도록 배치하세요.
   - `API` 모드: 추진기 블록에 `Wired Modem`을 붙이고 **우클릭으로 빨간 테두리를 점등**시킨 뒤 `TCA` 컴퓨터와 케이블로 연결하거나, 컴퓨터의 `left`/`right`/`front`/`back` 면에 직접 인접시키세요.
3. **고도/무선 범위**:
   - 온보드 제어기 간 거리(`VAS ↔ TCA`)는 같은 기체 내부이므로 일반 Wireless Modem으로 충분합니다.

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

`TCA`는 기체 인덱스 $N$ 에 따라 40채널 블록 내 Zone 2의 `Base + 10` 채널을 사용합니다.

$$\text{ThrustChannel} = 10000 + (N - 1) \times 40 + 10$$

| 채널 | 기본값 ($N=1$) | 용도 | 송수신 방향 |
| :---: | :---: | :--- | :--- |
| `Base + 10` | `10010` | `MSG_THRUST_CMD` 20Hz 추력·짐벌 지령 수신 및 `MSG_ACTUATOR_STATUS` 상태 보고 | `VAS` ↔ `TCA` |
| `Base_hangar + 3` | `104` (Bay 1) | 격납고 교정 중 `MSG_ACTUATOR_DISCOVER_REQ/ACK` 및 `MSG_CALIB_PULSE` 응답 | `Alignment` ↔ `TCA` |
| `Base_hangar + 4/5` | `105` / `106` | 무선 OTA 에이전트(`/lib/ota_agent.lua`) 업데이트 채널 | `OTA` ↔ `TCA` |

- **동적 채널 재바인딩 (`Option A`)**: 비행 전 `AMM`/`GCS`가 기체 블록 번호 $N$ 을 재할당하면 `MSG_CHANNEL_REBIND` (`500ms` 롤백 워치독)를 수신해 `Base + 10`을 무중단 전환합니다.

---

## 5. 소프트웨어 설치 방법 (Installation)

1. 온보드 `TCA` 컴퓨터에서 통합 인스톨러를 실행합니다:
   ```text
   /installer.lua install tca
   ```
2. 설치 경로:
   - 진입점: `/main.lua` (`/startup/00_tca.lua` 자동 등록)
   - 설정 마법사: `/tools/tca_setup.lua`
   - 기본 설정: `/config.json`
   - 라이브러리: `/lib/avionics_sensors.lua`, `/lib/ota_agent.lua`

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

설정 파일 경로는 `/config.json`입니다.

```json
{
  "schemaVersion": "1.2.0",
  "groupId": "THR_MAIN_L",
  "interactionMode": "REDSTONE",
  "aircraftIndexN": 1,
  "baseChannel": 10000,
  "channels": {
    "thrustActuation": 10010
  },
  "watchdogTimeoutMs": 300,
  "nominalActuatorCount": 4,
  "aircraftDomainId": "AIRCRAFT_01",
  "ports": {
    "modemSide": "top",
    "redstoneSide": "bottom",
    "apiSides": ["left", "right", "front", "back"]
  },
  "deadband": 0,
  "debug": false
}
```

| 키 | 기본값 | 설명 |
| :--- | :--- | :--- |
| `groupId` | `"THR_MAIN_L"` | 추진기 그룹 식별자 (`Alignment` 탐색 및 `VAS` 추력 행렬 매칭 키) |
| `interactionMode` | `"REDSTONE"` | `"REDSTONE"` (0~15 신호) 또는 `"API"` (`ion_thruster` 등 직접 메서드 제어) |
| `aircraftIndexN` | `1` | 기체 인덱스 (`thrustActuation = 10000 + (N - 1) * 40 + 10`) |
| `watchdogTimeoutMs` | `300` | 지령 무응답 시 추력 0 컷오프 워치독 시간(ms) |
| `nominalActuatorCount` | `4` | 정상 동작해야 하는 기대 추진기 개수 (미달 시 `API_DEGRADED` 보고) |
| `debug` | `false` *(주의: `main.lua` 폴백은 `true`)* | 실비행 시 20Hz 루프 보호를 위해 `"debug": false` 헤드리스 유지 권장 |

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### 대화형 설정 마법사 (`/tools/tca_setup.lua`)

터미널에서 `/tools/tca_setup.lua`를 단독 실행하거나, 디버그 TUI 중 `[S]`를 눌러 설정을 바꿀 수 있습니다:

| 키 | 동작 | 설명 |
| :---: | :--- | :--- |
| `A` | `AirDomain` 변경 | 소속 기체 도메인 ID 입력 (예: `AIRCRAFT_01`) |
| `G` | `Group ID` 변경 | 추진기 그룹명 입력 (예: `THR_MAIN_L`, `THR_MAIN_R`) |
| `M` | `Mode` 전환 | `REDSTONE` ↔ `API` 토글 |
| `N` | `Aircraft Index N` 변경 | 기체 번호 $N$ (`1~1000`) 입력 시 `baseChannel`과 `Base+10` 자동 재계산 |
| `C` | `Nominal Count` 변경 | 기대 구동기 수량 입력 |
| `Enter` | 저장 및 복귀 | `/config.json` 저장 후 마법사 종료 |

### 데몬 디버그 TUI 단축키 (`debug != false` 시)

- `S`: 일시정지 후 `tca_setup.lua` 실행 및 변경된 설정 즉시 재적용
- `D`: `VAS`로 수동 진단 핑 송출
- `T` 또는 `Q`: 워치독 정지 및 추력 0 안전 종료

### 자주 발생하는 문제 및 해결법

- **PBIT 또는 비행 중 `API_DEGRADED` / `API_TOTAL_LOSS` 상태가 뜸**
  - `nominalActuatorCount` 수만큼 추진기가 연결되지 않았거나 유선 모뎀이 꺼져 있습니다. `tca_setup.lua` 상단 `[ATTACHED PERIPHERALS]` 목록에 추진기가 `#1 ~ #N`까지 모두 표시되는지 확인하세요.
- **`WATCHDOG: ERR` 표시와 함께 추진기가 반응하지 않음**
  - `VAS`가 꺼져 있거나 `aircraftIndexN`이 서로 달라 `Base+10` 채널이 불일치합니다. `[S]` → `[N]`으로 기체 번호를 맞추세요.
- **비행 중 `PBIT` 위글 테스트가 거부됨**
  - 정상 안전 동작입니다. `< 5%`(`pulseRatio <= 0.04`) 위글은 오직 `DISARMED` 또는 `IDLE_ARMED` 지상 상태에서만 허용됩니다.
