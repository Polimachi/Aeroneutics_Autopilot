# Avionics Sensors — CC:Avionics 4종 공용 센서 라이브러리 및 결선 플레이북

> **대상 코드베이스**: `src/0_development/sensors/avionics_sensors.lua` (`/lib/avionics_sensors.lua`)  
> **관련 사양서**: [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`avionics_sensors`는 `Create: Avionics` 모드의 4대 핵심 센서 페리페럴을 일관된 인터페이스로 탐색·검증·판독하는 전역 공용 Lua 라이브러리(`/lib/avionics_sensors.lua`)입니다.

- **지원 센서 4종 SSOT**: `velocity_sensor`, `altitude_sensor`, `gimbal_sensor`, `physics_assembler` (`avionics:` / `create_avionics:` 네임스페이스 접두사 자동 정규화).
- **이중 토폴로지 투명 지원**: 컴퓨터 6면에 직접 인접한 센서뿐 아니라 **유선 모뎀(Wired Modem) + 케이블 네트워크**에 연결된 원격 센서도 동일한 `find()` / `wrap()` API로 탐색합니다.
- **3축 속도 벡터 합성 & 1틱 병렬 어셈블러 조회**: 1축 전용 `velocity_sensor` 3개를 자동 분류·합성(`read_vector3`)하고, `mainThread` yield가 6회 누적되는 `physics_assembler` 쿼리를 `parallel.waitForAll`로 **1틱(0.05초)** 내에 일괄 판독(`assembler.read`)합니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 센서 페리페럴 ID | 측정 항목 및 특성 | 온보드(`VAS`) 필수 | 이동형 패드/활주로(`DYNAMIC`) |
| :--- | :--- | :---: | :---: |
| `gimbal_sensor` | Pitch/Roll 오일러 각, 3축 각속도, 중력 벡터, 고유 가속도 | 필수 | 필수 |
| `altitude_sensor` | 월드 절대 Y 고도(`m`), 대기압 비율(`0.0~1.5`), 수직 속도(`m/s`) | 필수 | 필수 |
| `velocity_sensor` | 장착 축(`x`/`y`/`z`) 1축 선속도(`m/s`, `0.05 m/s` 데드밴드) | 필수(3축 권장) | 필수 |
| `physics_assembler` | 조립 여부, 총 질량(`kg`), 무게중심(`CoM`), 3×3 관성 텐서 | 필수(`TASK-136`) | 선택 |

- **유선 모뎀 네트워크 결선 시 필수 부품**: CC:Tweaked `Wired Modem` (컴퓨터 측 1개 + 각 센서 측 1개씩) 및 `Networking Cable`.

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. **직접 인접 vs 유선 모뎀 연결**:
   - 센서 블록을 컴퓨터의 6면(`top`, `bottom`, `left`, `right`, `front`, `back`)에 직접 맞대면 `preferred_side`로 바로 래핑할 수 있습니다.
   - 기체 무게중심(CoM) 부근이나 선체 각 축에 센서를 분산 배치해야 할 때는 **유선 모뎀 + 케이블**로 컴퓨터와 연결하세요.
2. **유선 모뎀 활성화 (가장 흔한 실수 방지)**:
   - 센서에 부착된 유선 모뎀을 반드시 **우클릭하여 빨간 테두리가 점등**되도록 활성화해야 네트워크에 `"velocity_sensor_0"`, `"gimbal_sensor_0"` 등의 주변기기 이름이 등록됩니다.
3. **3축 속도계 (`velocity_sensor` × 3) 배치 요령**:
   - `velocity_sensor`는 1축 방향만 측정하므로 선체 전진(`forward`), 수직(`vertical`), 횡(`lateral`) 3방향으로 각각 1개씩 총 3개를 부착합니다.
   - 각 센서의 `getAxis()` 반환값(`"x"`, `"y"`, `"z"`) 또는 네트워크 이름(`ship_velocity_sensor_forward_0` 등)을 기준으로 `sensors.velocity.read_vector3()`가 3축 벡터 `{ vx, vy, vz, speed, horizontal_speed }`를 자동 합성합니다.
4. **센서 오프셋 최소화**:
   - `gimbal_sensor`는 가급적 기체 무게중심(`CoM`)에 가깝게 배치해 회전 기동 시 레버암 원심 가속도 오차를 줄입니다.

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

`avionics_sensors`는 무선 RF 채널을 사용하지 않고 로컬 컴퓨터 인접 면 및 CC:Tweaked 유선 페리페럴 버스(`peripheral`)에서 동작합니다.

- 무선 모뎀으로 텔레메트리나 위치 정보를 송출하는 역할은 각 상위 제어기(`VAS` `Base+2`, `Landing Pad`/`Runway` 전술 채널)가 담당합니다.
- 유선 네트워크에 다수 센서가 물려 있을 경우 `sensors.find_all("velocity_sensor")`로 전체 목록을 확인해 특정 이름(`wrap`)으로 고정할 수 있습니다.

---

## 5. 소프트웨어 설치 방법 (Installation)

1. 온보드 제어기(`vas`, `fcp`, `amm`, `tca`) 또는 지상 시설(`gps_*`, `gac`, `landing_pad`, `runway`)을 설치하면 통합 인스톨러가 `/lib/avionics_sensors.lua`를 자동 배치합니다.
2. 단독으로 센서 라이브러리만 설치·테스트하려면 다음을 실행합니다:
   ```text
   /installer.lua install sensors
   ```
3. Lua 코드에서 로드:
   ```lua
   package.path = "/lib/?.lua;" .. package.path
   local sensors = require("avionics_sensors")
   ```

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

라이브러리 자체는 별도 JSON 설정 파일을 갖지 않으며, 호출 시 옵션 테이블(`opts`)로 우선 탐색 면과 병렬 여부를 제어합니다.

| API 호출 예시 | 옵션 키 | 설명 |
| :--- | :--- | :--- |
| `sensors.gimbal.find({ preferred_side = "bottom" })` | `preferred_side` | 특정 인접 면 또는 유선 주변기기 이름을 최우선 탐색 |
| `sensors.find_all("velocity_sensor", { filter = fn })` | `filter` | 조건 함수로 특정 방향/모뎀 이름의 센서만 필터링 |
| `sensors.velocity.read_vector3()` | (배열/키맵/옵션) | 3축 속도 센서 자동 탐색·평균·합성 (`{ vx, vy, vz, speed }`) |
| `sensors.assembler.read(dev, { parallel = true })` | `parallel` | 기본값 `true` — 6개 어셈블러 메서드를 `parallel.waitForAll`로 1틱 일괄 호출 |

- `VAS`에서 센서 역할별 우선 면을 지정하려면 `/config/sensors.json`의 `roles.<role>.preferredSide`를 설정합니다.

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### Lua 프롬프트(`lua`) 빠른 하드웨어 자가진단 예시

인게임 컴퓨터에서 `lua` 명령으로 인터프리터를 열어 센서가 정상 인식되는지 즉시 점검할 수 있습니다:

```lua
local s = require("avionics_sensors")
local g = s.gimbal.find()
local a = s.altitude.find()
local v, verr = s.velocity.read_vector3()
local p = s.assembler.find()
print("GIMBAL:", g ~= nil, "ALT:", a ~= nil, "VEL:", v and v.speed or verr, "ASM:", p ~= nil)
```

### 자주 발생하는 문제 및 해결법

- **`PERIPHERAL_NOT_FOUND` 또는 `NO_VELOCITY_SENSORS_FOUND` 오류**
  - 유선 모뎀을 사용 중인 경우 센서 블록 쪽 유선 모뎀과 컴퓨터 쪽 유선 모뎀 양쪽을 **우클릭해 빨간 테두리가 켜졌는지** 확인하세요.
- **`PERIPHERAL_TYPE_MISMATCH` 오류**
  - `preferred_side`로 지정한 면에 다른 종류의 블록(모뎀, 모니터 등)이 붙어 있습니다. 면 이름을 수정하거나 옵션을 생략해 자동 탐색(`find()`)을 사용하세요.
- **`physics_assembler` 호출 시 루프 주기가 느려짐 (6틱 지연)**
  - `getMass()`, `getCenterOfMass()` 등을 순차 호출하면 각 메서드의 `mainThread` yield로 6틱(0.3초)이 소모됩니다. 반드시 `sensors.assembler.read(dev)`를 사용해 1틱 병렬 일괄 조회를 유지하세요.
- **기체 회전 시 `velocity_sensor` 값이 계속 미세하게 흔들림**
  - 기체 자체 데드밴드는 `0.05 m/s`이지만 무게중심에서 멀리 떨어진 끝단에 속도 센서를 붙이면 각속도에 의한 접선 속도가 함께 측정됩니다. 가급적 CoM 주변에 부착하거나 `VAS` 레버암 보정 구성을 점검하세요.
