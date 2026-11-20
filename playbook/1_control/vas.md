# VAS — 20Hz 자세 안정화 코어 및 온보드 안전 감시 플레이북

> **대상 코드베이스**: `src/1_control/vas/` (`main.lua`)  
> **관련 사양서**: [VAS_PROGRAM_SPECIFICATION.md](../../docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`VAS (Vehicle Attitude Stabilizer / Node 01)`는 기체의 20Hz 내루프 자세 안정화(`QUATERNION_RATE`), 센서 융합 파이프라인, 3축 추력/모멘트 배분(`thrust_mixer`), 그리고 비행 안전 인터록을 담당하는 핵심 온보드 제어기입니다.

- **20Hz 헤드리스 코어 제어**: 기본값(`debug: false`)에서 50ms 루프 지연을 막기 위해 헤드리스로 동작하며, 필요 시 `debug: true` 설정으로 5Hz 비동기 TUI를 분리 구동합니다.
- **비행 전 5단계 PBIT & 조립 인터록 (`TASK-131`, `TASK-136`)**: 이륙 전 버스 RTT, 관성 토폴로지 해시(`> 5%` 질량 편차 시 `recalibrationRequired` 래치), 구동기 위글, 연료, 채널 충돌을 진단하고 공중 컨트랩션 해제(`DISASSEMBLED`) 시 즉시 `E_STOP`을 발령합니다.
- **공중 콜드부트 복구 & GPS DR 홀드오버 (`TASK-130`, `TASK-128`)**: 서버 재시작/청크 재로딩 시 `/.flight_state.json` 및 속도·고도를 판별해 `AIRBORNE_RECOVERY_HOLD`로 자동 수평 체공(10초 내 FCP/AMM 인계, 초과 시 `EMERGENCY_LAND`)하며, GPS 두절 시 1,500ms DR 홀드오버 및 10틱 청크 경계 블렌딩·`HOLD_LEVEL`을 수행합니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 구분 | 품목 / 페리페럴 | 필수 여부 | 비고 |
| :--- | :--- | :---: | :--- |
| 컴퓨터 | Advanced Computer | 필수 | 20Hz 쿼터니언 제어 루프 구동 |
| 통신 | Wireless Modem (또는 Ender Modem) | 필수 | 기체 내부 40채널 버스 및 `Alignment`/`OTA` 교신용 |
| 자세/각속도 | `gimbal_sensor` | 필수 | 동체 Pitch/Roll/Yaw 및 3축 각속도 측정 |
| 고도/승강 | `altitude_sensor` | 필수 | 월드 Y 고도 및 수직 속도(`m/s`) 측정 |
| 속도계 | `velocity_sensor` (전/상/측 3개 권장) | 필수 | 3축 선속도 측정 (`sensors.velocity.read_vector3`) |
| 기체 식별 | `physics_assembler` | 필수 | 조립 상태, 질량, CoM, 관성 텐서 조회 (`TASK-136`) |

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. **온보드 배치 및 공용 센서 결선**:
   - 기체 중앙부(가급적 `CoM` 근처)에 `VAS` 컴퓨터를 설치하고 무선 모뎀을 장착합니다.
   - `gimbal_sensor`, `altitude_sensor`, 3축 `velocity_sensor`, `physics_assembler`는 컴퓨터 인접 면 또는 **유선 모뎀 + 네트워킹 케이블**로 연결합니다(유선 모뎀 우클릭 빨간 테두리 활성화 필수 — [sensors.md](../0_development/sensors.md) 참고).
2. **기체 내부 4컴퓨터와의 관계**:
   - `VAS`는 물리 센서를 독점 판독하여 `Base+2`에 20Hz `MSG_FLIGHT_TELEMETRY`를 송출하므로, `FCP`와 `AMM`은 별도 물리 센서를 연결할 필요가 없습니다.
   - `VAS`가 판독한 추력/조종면 요구량은 `Base+10`으로 `TCA`에 전달됩니다.

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

기체 인덱스 $N$ (`1 ~ 1000`)에 따른 40채널 블록 공식은 다음과 같습니다:

$$\text{Base} = 10000 + (N - 1) \times 40$$

| 오프셋 | 기본값 ($N=1$) | 용도 | 송수신 방향 |
| :---: | :---: | :--- | :--- |
| `Base + 1` | `10001` | `guidance` — `FCP` 외루프 지령 및 `ACRO`(`MFD_ACRO`) 지령 수신 | `FCP`/`AMM` → `VAS` |
| `Base + 2` | `10002` | `telemetry` — 20Hz `MSG_FLIGHT_TELEMETRY` 송출 | `VAS` → `FCP`/`AMM`/`FDR` |
| `Base + 3` | `10003` | `mfd` — `AMM` 부재 시 5Hz 백업 `MSG_MFD_STATE` 송출 (AMM 활성 시 양보) | `VAS` → `GCS` |
| `Base + 5` | `10005` | `clientReply` — `GPS` 응답 수신 (필요 시) | `GPS` → `VAS` |
| `Base + 8` | `10008` | `calibration` — `Alignment` `MSG_CALIBRATION_INIT` 및 `AMM` `MSG_PBIT_REQ/REPORT` | `Alignment`/`AMM` ↔ `VAS` |
| `Base + 9` | `10009` | `emergency` — `CH_EMERGENCY_CORE` `E_STOP` 하드 래치 수신 | `AMM`/`GCS`/`FCP` → `VAS` |
| `Base + 10` | `10010` | `actuation` — `TCA` 추진기 클러스터 20Hz 추력 지령/상태 교환 | `VAS` ↔ `TCA` |
| `Base + 11` | `10011` | `asaActuation` — 공력 조종면 클러스터 지령/상태 교환 | `VAS` ↔ 조종면 |

- 격납고 무선 OTA를 위해 `/lib/ota_agent.lua`가 `Base_hangar + 4` (`105`) 채널도 대기합니다.

---

## 5. 소프트웨어 설치 방법 (Installation)

1. 기체 내부 `VAS` 컴퓨터에서 통합 인스톨러를 실행합니다:
   ```text
   /installer.lua install vas
   ```
2. 설치 구조:
   - 진입점: `/main.lua` (`startup/00_vas.lua` 자동 등록)
   - 모듈: `/modules/*.lua`, `/lib/avionics_sensors.lua`, `/lib/ota_agent.lua`
   - 기본 설정: `/config/system.json`

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

기본 설정 파일은 `/config/system.json`이며, 선택적으로 `/config/{sensors,pid,thrusters,surfaces,ota}.json` 및 교정 산출물 `/config/peripheral_manifest.json`을 로드합니다.

```json
{
  "aircraftIndexN": 1,
  "baseChannel": 10000,
  "bandwidth": 40,
  "channels": {
    "guidance": 1,
    "telemetry": 2,
    "mfd": 3,
    "trajectory": 4,
    "clientReply": 5,
    "calibration": 8,
    "emergency": 9,
    "actuation": 10,
    "asaActuation": 11
  },
  "timeouts": {
    "fcpCommandTimeoutMs": 1500,
    "sensorLossDebounceTicks": 1,
    "calibrationTimeoutSec": 120
  },
  "stallGuard": {
    "flapVfeLimit": 15.0
  },
  "debug": false
}
```

| 키 / 설정 파일 | 기본값 | 설명 |
| :--- | :--- | :--- |
| `aircraftIndexN` / `baseChannel` | `1` / `10000` | 기체 블록 번호 $N$ 및 기준 채널 (`AMM` 동적 재바인딩 시 자동 갱신) |
| `timeouts.fcpCommandTimeoutMs` | `1500` | 비행 중 `FCP` 지령 무응답 시 `FAILSAFE_HOLD` 전이 타임아웃(ms) |
| `debug` (또는 `system.debug`) | `false` | `false` 시 헤드리스, `true` 시 5Hz 비동기 컬러 TUI 대시보드 표시 |
| `telemetryDiag` | `false` | `true` 설정 시 적분기 포화 진단(`diag`)을 텔레메트리에 포함 (`FDR` 튜닝 시 활용) |
| `/config/pid.json` | 기본 내장 게인 | Pitch/Roll/Yaw/Climb `kp`, `ki`, `kd`, `integralLimit` 오버라이드 |
| `/config/thrusters.json` | `Alignment` 동기화 | `Alignment` 교정 완료 시 `MSG_PROFILE_SYNC`로 자동 저장됨 |

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### 실행 모드 및 TUI 단축키

- **기본 헤드리스 모드 (`debug: false`)**: 부팅 시 `[VAS] Core running in HEADLESS mode (Node 01, Base: 10000)` 출력 후 20Hz 루프에 집중합니다 (`Ctrl+T` 1초 길게 눌러 종료 가능).
- **디버그 TUI 모드 (`debug: true`)**: 51×19 HUD에 Pitch/Roll/Yaw 게이지, 고도/속도, `G A V F` 센서 상태, `TAP COMM`, 연료/동적 부하가 표시됩니다.
  - `Q` 또는 `T`: `VAS` 데몬 안전 종료

### 자주 발생하는 문제 및 해결법

- **시동(`ARM`)이 거부되고 `ERR_RECALIBRATION_REQUIRED`가 반환됨 (`TASK-136`)**
  - 기체 블록을 수정·재조립했거나 질량이 이전 교정값 대비 `> 5%` 변화해 재교정 래치가 걸린 상태입니다. [Alignment](../0_development/alignment.md) 베이에서 교정을 다시 실행하고 프로파일을 동기화(`Y`)하세요.
- **이륙 전 PBIT 검사에서 실패(`FAIL`)함 (`TASK-131`)**
  - 5대 진단 항목(`busRtt > 200ms`, `inertiaProfile` 미교정/분해, `actuatorWiggle` 실패, `energyFuel < 0.10`, `channelConflict`) 중 실패한 항목을 확인하세요. `TCA`가 `IDLE_ARMED` 또는 `DISARMED`에서 `Base+10`에 응답하는지 점검하세요.
- **기체가 `E_STOP` 상태에 갇혀 시동이 안 됨**
  - `E_STOP`은 안전을 위한 하드 래치 상태입니다. 기체 이상 원인을 해소한 뒤 `VAS` 컴퓨터를 재부팅(`reboot`)해 초기 상태로 복귀하세요.
- **부팅 직후 기체가 `AIRBORNE_RECOVERY_HOLD` 상태로 뜸 (`TASK-130`)**
  - 서버 재시작/청크 언로드 시 공중 상태(`/.flight_state.json` `AIRBORNE_ACTIVE` 또는 고도/속도 임계 초과)로 감지되어 자동 수평 호버링 보호에 들어간 것입니다. `FCP`/`AMM`이 10초 이내에 인계하면 자동으로 정상 비행(`NORMAL`)으로 복귀합니다.
