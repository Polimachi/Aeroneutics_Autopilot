# AMM — 항공기 임무 관리자 및 조종석 MFD 단말 플레이북

> **대상 코드베이스**: `src/3_planning/amm/` (`main.lua`)  
> **관련 사양서**: [AMM_PROGRAM_SPECIFICATION.md](../../docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`AMM (Aircraft Mission Manager / Node 03)`는 조종석 `51×19` 컬러 MFD 터미널 위에서 동작하며, 다중 체크포인트 임무(`v2.0.0` `ACT_*`/`DEC_*`/`MAC_*`), 3단계 채널 중재, 외부 관제(`GCS`/`GAC`/`GPS`/시설) 교신, 그리고 안전 인터록을 전담하는 최상위 온보드 항법·임무 제어기입니다.

- **듀얼 모뎀 RF 분리 아키텍처**: 기체 내부 제어 버스(`Base + 0..39`)와 외부 지상 관제·GPS 인프라 망(`50000~60020`)을 물리 모뎀 2개로 분리해 내부 제어 지연을 줄입니다(단일 모뎀 폴백도 동작 가능).
- **3단계 채널 부트스트랩 & Option A 재바인딩**: 부팅 시 `Channel_Sentinel`로 기존 채널 점유 충돌을 프로브한 뒤 `GCS`(`CH 50000`)에서 비충돌 40채널 블록을 발급받고, 변경 시 `AMM → FCP → VAS → TCA` 4계층 동적 재바인딩을 중재합니다.
- **이륙 전 PBIT 인터록 & 공중 콜드부트 복구 (`TASK-131`, `TASK-130`)**: `ACT_TKL_TAKEOFF_*` 집행 전 `VAS`에 PBIT를 요청해 `overallStatus == "FAIL"` 또는 개별 체크 `FAIL` 시 `PBIT_TAKEOFF_INTERLOCK`으로 이륙을 차단하며, 공중 재부팅 시 `/.flight_state.json` 정책(`RESUME` 또는 `RTB`)에 따라 자동 복구합니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 구분 | 품목 / 페리페럴 | 필수 여부 | 비고 |
| :--- | :--- | :---: | :--- |
| 컴퓨터 | Advanced Computer (`51×19`) | 필수 | 조종석 51×19 MFD 및 명령어 CLI 실행 |
| 내부 모뎀 | Wireless Modem (`primaryModemSide: "top"` 기본) | 필수 | 기체 내부 `VAS`·`FCP`·Zone 3 탑재체 버스 교신 |
| 외부 모뎀 | Ender Modem (`infraModemSide: "back"` 기본) | 권장 | 광역 `GPS`(`60001`), `GCS`(`50000`), `GAC`/`Landing Pad`/`Runway` 교신용 |

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. 조종석에서 조종사가 바로 조작하고 화면을 읽을 수 있는 위치에 Advanced Computer를 설치합니다.
2. **듀얼 모뎀 방향 맞추기**:
   - 기본 설정 기준 **상단(`top`)** 면에 기체 내부용 Wireless Modem을, **후면(`back`)** 면에 원거리 지상 교신용 Ender Modem을 부착하세요. 다른 면에 장착했다면 `/config/amm_config.json`의 `system.primaryModemSide`와 `system.infraModemSide`를 수정합니다.
3. **미션 파일 주입 경로 (3가지)**:
   - ① CC:Tweaked 창으로 `.json` 미션 파일을 직접 드래그 앤 드롭 (`file_transfer` 이벤트 감지 후 `/missions/`에 검증 저장).
   - ② Floppy Disk(`/disk/*.json` 또는 `/disk/missions/*.json`).
   - ③ 기체 로컬 폴더(`/missions/*.json`).

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

### 내부 모뎀 (기체 40채널 블록: $\text{Base} = 10000 + (N - 1) \times 40$)

| 오프셋 | 기본값 ($N=1$) | 용도 |
| :---: | :---: | :--- |
| `Base + 0` | `10000` | `GCS` 원격 C2 / `MISSION_PUSH_CMD` 수신 및 채널 프로브 |
| `Base + 2` | `10002` | `VAS` 20Hz `MSG_FLIGHT_TELEMETRY` 수신 |
| `Base + 3` | `10003` | `GCS`로 5Hz `MSG_MFD_STATE` 다운링크 송출 (`VAS` 백업 송신 양보) |
| `Base + 4` | `10004` | `FCP`로 20Hz `MSG_TRAJECTORY_CMD` 송출 및 `MSG_OUTER_LOOP_STATUS` 수신 |
| `Base + 5` | `10005` | `GPS` 측위 응답 및 `MSG_NAV_QUALITY` 수신 |
| `Base + 8` | `10008` | `MSG_PBIT_REQ` 송신 및 `MSG_PBIT_REPORT` 수신 (`TASK-131`) |
| `Base + 9` | `10009` | `CH_EMERGENCY_CORE` `E_STOP` 비상 정지 송수신 |
| `Base + 20 ~ 39` | `10020~10039` | Zone 3 탑재체 버스 (`ACT_PAY_*` 동적 개방/통신) |

### 외부 모뎀 (인프라 및 관제 채널)

| 채널 | 용도 |
| :---: | :--- |
| `50000` | `GCS` 40채널 블록 부트스트랩 (`MSG_BLOCK_REQUEST/ASSIGN`) |
| `50001` | 광역 ATC 교신 채널 |
| `50003` / `50004` | `GAC` 시설 비컨(`MSG_FACILITY_BEACON`), 활주로 디렉토리, `MSG_MISSION_ACK` 보고 |
| `Base_sec + 0` / `50211+` | 섹터 `GAC` 체크인(`50201`) 및 배정된 `Landing Pad`/`Runway` 전술 유도 수신 |
| `60001` / `60002` | `GPS` 측위 핑 송신(`10Hz`) 및 서비스 조회 |

---

## 5. 소프트웨어 설치 방법 (Installation)

1. 조종석 `AMM` 컴퓨터에서 통합 인스톨러를 실행합니다:
   ```text
   /installer.lua install amm
   ```
2. 설치 경로: `/main.lua`, `/modules/*.lua`, `/config/amm_config.json`, `/lib/avionics_sensors.lua`, `/lib/ota_agent.lua`, 부팅 훅 `/startup/00_amm.lua`.

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

설정 파일 경로는 `/config/amm_config.json`입니다.

```json
{
  "version": "2.0.0",
  "domainId": "AIRCRAFT_01",
  "baseChannel": 10000,
  "defaultAlt": 150.0,
  "defaultSpeed": 18.0,
  "arrivalRadius": 15.0,
  "headless": false,
  "system": {
    "domainId": "AIRCRAFT_01",
    "airframeType": "VECTORED_VTOL",
    "loopFrequencyHz": 20,
    "uiFrequencyHz": 5,
    "primaryModemSide": "top",
    "infraModemSide": "back"
  },
  "navigation": {
    "gpsRequestRateHz": 10,
    "gpsTimeoutMs": 5000,
    "drComplementaryAlpha": 0.35,
    "degradedAlpha": 0.10,
    "maxAllowedHdop": 3.0,
    "kinematicGateLimitM": 8.0
  },
  "safety": {
    "lowFuelRthThreshold": 0.20,
    "emergencyLandFuelThreshold": 0.10,
    "goAroundTargetAltM": 100.0
  },
  "recovery": {
    "enabled": true,
    "stateFilePath": "/.flight_state.json",
    "coldBootPolicy": "RESUME",
    "syncTimeoutMs": 5000
  }
}
```

- `recovery.coldBootPolicy`: 공중 콜드부트 복구 시 `"RESUME"`(중단된 체크포인트로 임무 재개) 또는 `"RTB"`(홈 패드로 즉시 귀환) 선택.
- `autoRunDroppedFile`: `true` 설정 시 드래그 앤 드롭한 유효 미션을 대기 상태에서 즉시 자동 실행(기본 `false`).
- `safety.chattering`: 지오펜스/연료/VTOL 천이/갑판 동요/도달 판정의 디바운스 및 히스테리시스 임계값(`chattering_guard.lua`) 조정.

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### `NAV` 모드 핫키 (기본 대기 화면)

| 키 | 동작 | 설명 |
| :---: | :--- | :--- |
| `A` | `ARM` | 시동 준비 명령 |
| `T` | `TAKEOFF` | 이륙 지령 (`PBIT` 통과 시 수행) |
| `H` | `HOLD` | 현 위치 정지 체공 |
| `R` | `RTH` | 홈 패드/기지로 복귀 |
| `L` | `LAND` | 착륙 절차 시작 |
| `X` 또는 `Ctrl+X` | **`E_STOP`** | `Base+9` 즉시 비상 정지 송출 |
| `/` 또는 `Enter` | `CLI` 모드 전환 | 하단 명령어 입력 버퍼 진입 (`Esc`로 `NAV` 복귀) |

### `CLI` 모드 명령어 (`/` 또는 `Enter` 후 입력)

| 명령어 | 문법 예시 | 설명 |
| :--- | :--- | :--- |
| `pbit` | `pbit` | `VAS`에 5단계 비행 전 자가진단(`MSG_PBIT_REQ`) 수동 요청 |
| `run` / `mission run` | `run patrol single` / `run repeat` | 지정 미션 파일 또는 수동 웨이포인트 큐 실행 (`single` / `repeat`) |
| `load` / `save` / `files` | `load patrol` / `save my_wp` | `/missions/`·`/disk/` 미션 파일 조회·로드·저장 |
| `stop` / `pause` / `resume` / `next` | `pause` / `next` | 현재 미션 중단·일시정지·재개·다음 체크포인트 건너뛰기 |
| `confirm` | `confirm` | `ACT_SYS_WAIT_HUMAN_CONFIRM` 체크포인트 인가 승인 |
| `add` / `del` / `clear` / `goto` | `add 1200 -800 150 18 PAD_01` | 수동 큐에 `<x> <z> [alt] [speed] [facilityId]` 추가·삭제·이동 |
| `alt` / `spd` / `rad` | `alt 180` / `spd 22` / `rad 12` | 기본 순항 고도(m)·속도(m/s)·도달 반경(m) 변경 |
| `mission status` | `mission status` | 활성 미션 ID, 상태, 진행 체크포인트 번호(`idx/total`) 표시 |

### 자주 발생하는 문제 및 해결법

- **이륙 명령이 `PBIT_TAKEOFF_INTERLOCK`으로 차단됨 (`TASK-131`)**
  - `CLI`에서 `pbit`을 실행해 최신 진단 결과를 확인하세요. `VAS`에서 `inertiaProfile` (`RECALIBRATION_REQUIRED`), `actuatorWiggle`, `busRtt`, `energyFuel`, `channelConflict` 중 하나라도 `FAIL`이면 이륙이 거부됩니다(`WARN`은 경고와 함께 이륙 허용).
- **드래그 앤 드롭한 미션 파일이 `DROP FAIL`로 거부됨**
  - 파일명이 `.json`으로 끝나지 않거나 미션 스키마(`version == "2.0.0"`, 유효 `ACT_*` 등)를 위반했습니다. 호스트에서 [AMM Mission Editor](amm_mission_editor.md)의 프리플라이트 검증을 먼저 통과시킨 파일을 넣으세요.
- **기체가 `ACT_TKL_LAND_NEAREST` 등에서 시설을 찾지 못함**
  - `GAC`의 `CH 50003` 비컨을 수신하지 못한 상태입니다. 외부 모뎀(`infraModemSide`)이 장착되어 있고 `GAC`와 같은 월드 청크/모뎀 거리 내에 있는지 확인하세요.
