# FCP — 20Hz SE(3) 외루프 비행 제어 및 유도 컴퓨터 플레이북

> **대상 코드베이스**: `src/2_guidance/fcp/` (`main.lua`)  
> **관련 사양서**: [FCP_PROGRAM_SPECIFICATION.md](../../docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`FCP (Flight Control Program / Node 04)`는 상위 임무 관리자(`AMM`)가 보낸 3차원 궤적 지령(`Base+4`)과 `VAS`가 보낸 20Hz 기체 상태 텔레메트리(`Base+2`)를 비교하여, `SE(3)` 기하학적 외루프 유도 법칙으로 목표 자세 쿼터니언과 추력(`Base+1` `QUATERNION_RATE`)을 산출하는 순수 비행 유도 컴퓨터입니다.

- **5대 기종별 비행 드라이버**: `VECTORED_VTOL`, `ADVANCED_VTOL`, `MULTIROTOR`, `FIXED_WING`, `WINGED_VTOL` 기체의 비행 역학에 맞춰 추력 벡터 편향·뱅크 선회·천이(Transition) 제어를 수행합니다.
- **엄격한 3+1 내부 채널 격리**: 외부 `GPS`/`GCS`/`GAC` 채널을 직접 열지 않으며 오직 `Base+1`, `Base+2`, `Base+4`, `Base+9`만으로 기체 내부 제어 루프를 완결합니다.
- **무충격 핸드오프 & 안전 가드 (`TASK-130`, `TASK-128`, `TASK-018`)**: `AIRBORNE_RECOVERY_HOLD`에서 복귀 시 `bumplessRampSec`(`2.0초`) 동안 출력을 부드럽게 램프 인(Ramp-in)하고, GPS DR 열화 시 `HOLD_LEVEL` 수평 홀드를 지시하며, `VAS` 텔레메트리 타임아웃(`coreTelemetryTimeoutMs`) 시 적분기를 즉시 동결합니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 구분 | 품목 / 페리페럴 | 필수 여부 | 비고 |
| :--- | :--- | :---: | :--- |
| 컴퓨터 | Advanced Computer | 필수 | 20Hz `SE(3)` 외루프 계산 실행 |
| 통신 | Wireless Modem (`primaryModemSide: "top"` 기본) | 필수 | 기체 내부 `AMM`·`VAS` 간 40채널 버스 통신 |
| 물리 센서/구동기 | **연결 불필요** | 해당 없음 | 모든 센서 데이터는 `VAS` `Base+2`에서 수신함 |

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. 조종석(`AMM`) 또는 제어실(`VAS`) 인근에 `FCP` 전용 Advanced Computer를 배치하고 무선 모뎀을 부착합니다.
2. 기체 내 4대 컴퓨터(`AMM`, `FCP`, `VAS`, `TCA`)는 모두 동일한 기체 블록 인덱스 $N$ (`baseChannel = 10000 + (N - 1) * 40`) 및 동일한 `system.domainId`(`"AIRCRAFT_01"` 등)를 공유해야 합니다.
3. 기본 부팅 훅(`/startup/00_fcp.lua`)은 `--daemon` 플래그로 실행되어 20Hz 루프 지연 없이 백그라운드로 구동됩니다.

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

`FCP`는 기체 40채널 블록 내부의 Zone 1 채널 4개만 사용합니다 (`Base = 10000 + (N - 1) * 40`):

| 오프셋 | 기본값 ($N=1$) | 용도 | 송수신 방향 |
| :---: | :---: | :--- | :--- |
| `Base + 4` | `10004` | `trajectory` — `AMM` 20Hz `MSG_TRAJECTORY_CMD` 수신 및 `MSG_OUTER_LOOP_STATUS` 보고 | `AMM` ↔ `FCP` |
| `Base + 2` | `10002` | `telemetry` — `VAS` 20Hz `MSG_FLIGHT_TELEMETRY` 및 `MSG_NAV_QUALITY` 수신 | `VAS` → `FCP` |
| `Base + 1` | `10001` | `guidance` — `VAS`로 20Hz `MSG_ATTITUDE_CMD` (`QUATERNION_RATE`) 송출 | `FCP` → `VAS` |
| `Base + 9` | `10009` | `emergency` — `CH_EMERGENCY_CORE` `E_STOP` 비상 정지 수신 | `AMM`/`GCS` → `FCP` |

- 격납고 무선 OTA 업데이트 시 `/lib/ota_agent.lua`가 `Base_hangar + 4` (`105`) 채널을 추가로 개방합니다.

---

## 5. 소프트웨어 설치 방법 (Installation)

1. 온보드 `FCP` 컴퓨터에서 통합 인스톨러를 실행합니다:
   ```text
   /installer.lua install fcp
   ```
2. 설치 경로:
   - 진입점: `/main.lua` (`/startup/00_fcp.lua` → `/main.lua --daemon`)
   - 기본 설정: `/config/fcp_config.json`
   - 모듈: `/modules/*.lua`, `/lib/avionics_sensors.lua`, `/lib/ota_agent.lua`

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

설정 파일 경로는 `/config/fcp_config.json` (스키마 버전 `"2.1.0"`)입니다.

```json
{
  "version": "2.1.0",
  "system": {
    "domainId": "AIRCRAFT_01",
    "hardwareUuid": "FCP-NODE-04-UUID",
    "airframeType": "VECTORED_VTOL",
    "loopFrequencyHz": 20,
    "primaryModemSide": "top",
    "debug": false
  },
  "channels": {
    "baseChannel": 10000,
    "bandwidth": 40,
    "trajectoryOffset": 4,
    "telemetryOffset": 2,
    "guidanceOffset": 1,
    "emergencyOffset": 9
  },
  "outerLoop": {
    "gravityMps2": 11.0,
    "kpPos": { "x": 0.90, "y": 1.10, "z": 0.90 },
    "kdVel": { "x": 1.20, "y": 1.35, "z": 1.20 },
    "kiPos": { "x": 0.05, "y": 0.08, "z": 0.05 },
    "maxAccelMps2": 6.5,
    "maxIntegralAccel": 1.5,
    "hoverThrustNorm": 0.635,
    "maxYawRateDegPerSec": 30.0,
    "bumplessRampSec": 2.0
  },
  "safety": {
    "ammSetpointTimeoutMs": 500,
    "ammTimeoutHoldToEmgMs": 10000,
    "coreTelemetryTimeoutMs": 500,
    "navStaleTimeoutMs": 500,
    "rebindAckTimeoutMs": 500,
    "bumplessRampSec": 2.0,
    "emergencyDescentRateMps": -1.5,
    "fixedWingGlideDescentMps": -1.0
  }
}
```

### 주요 튜닝 파라미터

| 파라미터 | 기본값 | 조정 가이드 |
| :--- | :--- | :--- |
| `system.airframeType` | `"VECTORED_VTOL"` | 기체에 맞게 `VECTORED_VTOL`, `ADVANCED_VTOL`, `MULTIROTOR`, `FIXED_WING`, `WINGED_VTOL` 중 선택 |
| `outerLoop.hoverThrustNorm` | `0.635` | 기체가 제자리 호버링할 때 필요한 정규화 추력(`0.0~1.0`) — 기체가 이륙 후 가라앉으면 높이고 급상승하면 낮춤 |
| `outerLoop.kpPos` / `kdVel` | `0.90~1.10` / `1.20~1.35` | 목표 좌표 도달 시 오버슈트/진동이 크면 `kpPos`를 낮추거나 `kdVel`을 높임 |
| `outerLoop.fixed_wing.emergencyMaxBankDeg` | `75.0` | 고정익 비상 기동/비상 착륙 시 허용 최대 뱅크각(도) |
| `safety.ammSetpointTimeoutMs` | `500` | `AMM` 지령 두절 시 자동 호버링 진입 판정 시간(ms); `10000ms` 경과 시 `EMERGENCY_LAND` 전이 |

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### CLI 실행 플래그

```text
/main.lua --daemon                 # 기본 20Hz 헤드리스 데몬 모드
/main.lua --debug                  # 51x19 5Hz 진단 HUD 활성화 (아무 키나 누르면 종료)
/main.lua --base 10040 --daemon    # 특정 Base 채널 지정 실행
```

### 자주 발생하는 문제 및 해결법

- **`CONFIG_VERSION_MISMATCH` 경고가 뜸**
  - `/config/fcp_config.json`의 `"version"`이 `"2.1.0"`이 아닌 구버전 스키마입니다. 인스톨러로 업데이트하거나 `"version": "2.1.0"`으로 갱신하세요.
- **기체가 호버링 중 목표 고도보다 계속 낮거나 높게 떠 있음**
  - `outerLoop.hoverThrustNorm` 값이 실제 기체 중량 대비 낮거나 높기 때문입니다. `kiPos.y`가 보정하지만 응답이 느릴 경우 `hoverThrustNorm`을 기체 실측 호버 스로틀에 맞춰 조정하세요.
- **부팅 직후 `FCP`가 자세 지령을 보내지 않음 (`IDLE_ARMED` 유지)**
  - `VAS`가 공중 콜드부트 복구(`AIRBORNE_RECOVERY_HOLD`) 중이거나 `AMM`이 아직 궤적 셋포인트(`Base+4`)를 발행하지 않은 상태입니다. `VAS` 복구 종료 후 `AMM`에서 이륙/임무(`ACT_*`)를 시작하면 `2.0초` `bumplessRampSec`으로 부드럽게 제어권을 인계받습니다.
- **고속 기동 후 급정지할 때 기체가 좌우로 출렁임**
  - `outerLoop.maxAccelMps2`를 줄이거나 `kdVel.x`/`kdVel.z` 댐핑 게인을 소폭 증가시키세요.
