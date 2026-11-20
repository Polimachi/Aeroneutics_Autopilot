# Landing Pad — 고정형·이동형 함상 스마트 착륙패드 플레이북

> **대상 코드베이스**: `src/0_infra/landing_pad/` (`main.lua`)  
> **관련 사양서**: [LANDING_PAD_SPECIFICATION_AND_ICD.md](../../docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`Landing Pad`는 지상 수직 착륙장(`STATIC`) 또는 항해 중인 모선/항공모함 갑판(`DYNAMIC`)에 설치되어, 접근 중인 기체에 **실시간 패드 좌표·속도 벡터 및 갑판 안정성**을 무선 송출하는 스마트 착륙시설 제어기입니다.

- **20Hz 동적 정밀 유도 (`DYNAMIC`)**: 모선이 이동·회전·롤링하더라도 `CC:Avionics` 센서와 `offset_transform.lua`를 이용해 컴퓨터 위치로부터 실제 착륙 패드 중심의 3차원 위치와 속도(`vx, vy, vz`)를 계산하고 20Hz `MSG_PAD_DYNAMIC_GUIDE`를 송신합니다.
- **1Hz 정적 유도 (`STATIC`)**: 고정 지형 패드에서는 1Hz `MSG_PAD_STATIC_GUIDE`를 송출하고 GPS를 최초 1회(또는 주기 저빈도) 조회합니다.
- **갑판 동요 안전 감시**: 갑판 기울기($\sqrt{\text{pitch}^2 + \text{roll}^2} > 10.0^\circ$) 또는 상하 요동($|v_y| > 2.5\text{ m/s}$) 초과 시 즉시 `DANGEROUS` 판정과 함께 `MSG_ABORT_APPROACH`를 발행해 기체를 복행시킵니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 구분 | 품목 / 페리페럴 | `STATIC` | `DYNAMIC` | 비고 |
| :--- | :--- | :---: | :---: | :--- |
| 컴퓨터 | Advanced Computer (`51×19`) | 필수 | 필수 | 20Hz 데몬 및 TUI 실행 |
| 통신 | Wireless Modem 또는 Ender Modem | 필수 | 필수 | 기본 면 `"top"` |
| `gimbal_sensor` | CC:Avionics 짐벌 센서 | 선택 | **필수** | 갑판 Pitch/Roll/Yaw 및 각속도 측정 |
| `altitude_sensor` | CC:Avionics 고도 센서 | 선택 | **필수** | 해수면/월드 고도 Y 측정 |
| `velocity_sensor` | CC:Avionics 속도 센서 (3축 권장) | 선택 | **필수** | 모선 이동/상하 동요 속도 측정 |

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. **컴퓨터 및 패드 마킹 배치**:
   - 패드 바닥 중앙 또는 패드 가장자리 조종실에 컴퓨터를 배치합니다.
   - 컴퓨터 블록과 실제 기체 접지점(패드 중앙 표면)이 서로 떨어져 있을 경우, **착륙패드 방향 기준 오프셋 `bodyOffset` (`forward`, `right`, `up`)** 과 **모선 선수 대비 패드 회전 오프셋 `mountingYawOffset`** 을 설정에 기입해 오차를 보정할 수 있습니다.
2. **이동형 모선(`DYNAMIC`) 센서 부착**:
   - 모선 컨트랩션 내부에 `gimbal_sensor`, `altitude_sensor`, `velocity_sensor`를 인접 또는 유선 모뎀 네트워크로 연결합니다(유선 모뎀 우클릭 빨간 테두리 활성화 필수 — [sensors.md](../0_development/sensors.md) 참고).
3. **착륙 여유 반경 확보**:
   - 설정된 `clearanceZoneRadius`(기본 `5.0m`) 내에 구조물이나 장애물이 침범하지 않도록 패드 주변을 비워 두세요.

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

섹터 $S$의 기준 채널 $Base_{\text{sec}} = 50001 + S \times 200$ 및 패드 순번 `padIndex` ($1, 2, \dots$)를 기준으로 아래 채널을 개방합니다:

| 채널 | 기본값 (`S=1, Idx=1`) | 용도 | 송수신 방향 |
| :---: | :---: | :--- | :--- |
| `Base_sec + 1` | `50202` | `sectorFacilityChannel` — `GAC`와 `MSG_ATC_SLOT_ASSIGN/ACK`, 1Hz `FACILITY_UPDATE` 교환 | `Pad` ↔ `GAC` |
| `Base_sec + 5` | `50206` | `sectorGpsReplyChannel` — `GPS` 삼각측량 응답 수신 | `GPS` → `Pad` |
| `Base_sec + 10 + (Idx - 1)` | `50211` | `tacticalChannel` — 기체에 20Hz 동적/1Hz 정적 유도 및 `MSG_ABORT_APPROACH` 송출 | `Pad` ↔ 접근 기체 |
| `60001` | `60001` | `GPS_PING_CHANNEL` — `RESERVED`/`APPROACH_DYNAMIC` 중 5Hz, 평시 1Hz 측위 핑 송신 | `Pad` → `GPS` |

---

## 5. 소프트웨어 설치 방법 (Installation)

1. 패드 컴퓨터에서 통합 인스톨러를 실행합니다:
   ```text
   /installer.lua install landing_pad
   ```
2. 설치 경로: `/main.lua`, `/config.lua`, `/modules/*.lua`, `/landing_pad/config.json`, `/lib/avionics_sensors.lua`, 부팅 훅 `/startup/00_landing_pad.lua`.

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

설정 파일 경로는 `/landing_pad/config.json`입니다.

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
  "mountingYawOffset": 0.0,
  "bodyOffset": { "forward": 0.0, "right": 0.0, "up": 0.0 },
  "approachHeading": 180.0,
  "safeDescentRate": 1.0,
  "clearanceZoneRadius": 5.0,
  "maxSupportedWeight": 45000.0,
  "wirelessModemSide": "top",
  "slotDurationSec": 120
}
```

| 키 | 기본값 | 설명 |
| :--- | :--- | :--- |
| `facilityId` | `"PAD_BRAVO_01"` | `GAC` `/gac/config.json`에 등록된 시설 ID와 반드시 일치해야 함 |
| `sectorId` / `padIndex` | `1` / `1` | 섹터 번호 및 패드 인덱스(전술 채널 `Base_sec + 10 + (padIndex - 1)` 자동 계산) |
| `mobility` | `"DYNAMIC"` | `"STATIC"`(고정) 또는 `"DYNAMIC"`(모선·이동 함선 갑판) |
| `bodyOffset` | `{0, 0, 0}` | 컴퓨터 위치에서 실제 착륙패드 중심까지의 거리 오프셋(m) |
| `mountingYawOffset` | `0.0` | 모선 전방 대비 패드 회전 오프셋 각도(도) |
| `approachHeading` | `180.0` | 권장 최종 접근 방위각(도) |
| `maxSupportedWeight` | `45000.0` | 허용 최대 기체 중량(kg) |

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### TUI 단축키

| 키 | 동작 | 설명 |
| :---: | :--- | :--- |
| `F` | 강제 초기화 (`Force Free`) | 현재 패드 FSM을 `FREE`로 즉시 리셋하고 `GAC` 백본(`50202`)에 보고 |
| `Q` | 안전 종료 | 열린 채널을 닫고 터미널 정리 후 종료 |

### 자주 발생하는 문제 및 해결법

- **부팅 카운트다운 또는 `DYNAMIC` 모드에서 센서가 누락됨 (`HALT_WITH_WARNING`)**
  - `mobility == "DYNAMIC"`일 때는 `gimbal_sensor`, `altitude_sensor`, `velocity_sensor` 3종이 모두 인식되어야 정상 가동됩니다. 고정형 지상 패드라면 `/landing_pad/config.json`의 `"mobility"`를 `"STATIC"`으로 변경하세요.
- **기체가 접근 중에 갑자기 `MSG_ABORT_APPROACH`를 받고 복행함**
  - 모선이 급선회/급가속해 갑판 기울기 `> 10.0°` 또는 수직 요동 `> 2.5 m/s`를 넘어 `DANGEROUS` 판정이 발생했거나, `GAC`에서 `WAVE_OFF`/`EMERGENCY LOCKDOWN`이 발령된 상태입니다. 모선을 안정적으로 정지 또는 등속 직진 유지하세요.
- **착륙 위치가 패드 중심에서 수 블록 어긋남**
  - 컴퓨터 블록과 패드 중심 간 거리 차이입니다. `bodyOffset` (`forward`, `right`, `up`) 및 `mountingYawOffset`을 실제 블록 간격에 맞게 입력하세요.
