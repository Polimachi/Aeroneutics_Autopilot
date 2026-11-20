# Runway — 고정익·VTOL 스마트 활주로 및 유선 등화 제어기 플레이북

> **대상 코드베이스**: `src/0_infra/runway/` (`main.lua`)  
> **관련 사양서**: [RUNWAY_SPECIFICATION_AND_ICD.md](../../docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`Runway`는 고정익 항공기와 날개 달린 VTOL 기체의 활주 이착륙을 안내하기 위해 활주로 시단 접지점(`touchdownOffset`)과 종단점(`endOffset`), 글라이드슬로프(`glideSlopeAngle`)를 실시간 산출하고, 유선 레드스톤 등화·어레스팅 클러치·풍향 전광판을 연동 제어하는 활주로 관제 프로그램(`TASK-103`)입니다.

- **2점 활주로 벡터 유도**: `offset_transform.lua`로 접지 구역 시작점과 활주로 끝점의 3차원 월드 좌표를 계산해 `APPROACH_DYNAMIC` / `APPROACH_STATIC` 비컨을 송출합니다.
- **터치다운 및 활주로 이탈 핸드셰이크**: 기체 `AMM`이 송출하는 `MSG_RUNWAY_TOUCHDOWN`과 `MSG_RUNWAY_VACATED`를 수신해 `ROLLOUT` → `VACATING` → `FREE` 상태 전이와 `GAC` 백본 보고를 수행합니다.
- **유선 하드웨어 연동 (`lighting_controller.lua`)**: `redstoneIntegrator`를 통한 상태별 ALS/PAPI 등화 점멸, `carrier_arresting_clutch` 아날로그 레드스톤 제어(`ROLLOUT`/`OCCUPIED` 시 강도 `15`), `wind_display_link` 상태·풍속 출력(미연결 시에도 안전 저하 동작)을 지원합니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 구분 | 품목 / 페리페럴 | 필수 여부 | 비고 |
| :--- | :--- | :---: | :--- |
| 컴퓨터 | Advanced Computer (`51×19`) | 필수 | 20Hz 데몬 및 51×19 상태 화면 |
| 통신 | Wireless Modem 또는 Ender Modem | 필수 | 기본 면 `"top"` |
| `redstone_integrator` | Advanced Peripherals Redstone Integrator (`redstone_integrator_0`) | 선택 | 유선 모뎀 연결 시 활주로 상태별 6면 등화/웨이브오프 경광등 제어 |
| 어레스팅 클러치 | 유선 주변기기명 `carrier_arresting_clutch` | 선택 | 착륙 활주(`ROLLOUT`/`OCCUPIED`) 중 제동 클러치 작동(강도 15) |
| 풍향 전광판 | `wind_display_link` 또는 `display_link` | 선택 | 활주로 상태(`RWY: ...`) 및 풍향/풍속 출력 |
| 동적 센서 (`DYNAMIC` 시) | `gimbal_sensor`, `altitude_sensor`, `velocity_sensor` | 조건부 필수 | 항공모함 등 이동형 활주로 운용 시 필수 |

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. **활주로 기준 좌표 및 2점 오프셋 설계**:
   - 활주로 관제실 컴퓨터 위치를 기준으로 **접지 시단(`touchdownOffset`)** 과 **활주로 끝단(`endOffset`)** 까지의 상대 오프셋(`forward`, `right`, `up`)을 측정합니다. 기본값은 `endOffset.forward = 200.0`m입니다.
   - `touchdownZoneLength`(기본 `80.0`m)와 `glideSlopeAngle`(기본 `3.0°`)이 진입로 장애물과 간섭하지 않도록 활주로 연장선 앞뒤 장애물을 정리하세요.
2. **유선 등화·어레스팅 결선 (`lighting_controller.lua`)**:
   - 유선 모뎀으로 `redstone_integrator_0`을 연결하면 각 방위 면 출력이 상태에 따라 자동 제어됩니다:
     - `FREE`/`IDLE`: `north` 점등
     - `RESERVED`/`APPROACH_*`: `top`, `bottom`, `north`, `east` 점등 (진입등/글라이드등)
     - `ROLLOUT`/`OCCUPIED`: `south` 전환 점등 및 `carrier_arresting_clutch` 출력 `15`
     - `WAVE_OFF`/`MAINTENANCE`: `top`·`south` 2Hz 교차 점멸 경광등

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

섹터 $S$ 기준 채널 $Base_{\text{sec}} = 50001 + S \times 200$ 및 `runwayIndex` 기반 채널 구성입니다:

| 채널 | 기본값 (`S=1, Idx=1`) | 용도 | 송수신 방향 |
| :---: | :---: | :--- | :--- |
| `Base_sec + 1` | `50202` | `sectorFacilityChannel` — `GAC` 슬롯 할당·1Hz 시설 상태 보고 | `Runway` ↔ `GAC` |
| `Base_sec + 5` | `50206` | `sectorGpsReplyChannel` — `GPS` 측위 응답 수신 | `GPS` → `Runway` |
| `Base_sec + 10 + (Idx - 1)` | `50211` | `tacticalChannel` — 활주로 유도 송출 및 `MSG_RUNWAY_TOUCHDOWN`/`VACATED` 수신 | `Runway` ↔ 기체 `AMM` |
| `60001` | `60001` | `GPS_PING_CHANNEL` — `DYNAMIC` 항모 모드 측위 핑 | `Runway` → `GPS` |

- `GAC`와 같은 섹터에 `Landing Pad`와 `Runway`를 함께 둘 때는 `tacticalChannel` 번호(`50211`, `50212`, ...)가 서로 중복되지 않도록 `runwayIndex`와 `padIndex`를 조정하세요.

---

## 5. 소프트웨어 설치 방법 (Installation)

1. 활주로 컴퓨터에서 통합 인스톨러를 실행합니다:
   ```text
   /installer.lua install runway
   ```
2. 설치 경로: `/main.lua`, `/modules/*.lua`, `/runway/config.json`, `/lib/avionics_sensors.lua`, 부팅 훅 `/startup/00_runway.lua`.

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

설정 파일 경로는 `/runway/config.json`입니다.

```json
{
  "version": "1.12.0",
  "facilityId": "RWY_ALPHA_09L",
  "sectorId": 1,
  "runwayIndex": 1,
  "mobility": "DYNAMIC",
  "gacChannel": 50201,
  "sectorFacilityChannel": 50202,
  "sectorGpsReplyChannel": 50206,
  "tacticalChannel": 50211,
  "mountingYawOffset": 0.0,
  "position": { "x": 0.0, "y": 64.0, "z": 0.0 },
  "touchdownOffset": { "forward": 0.0, "right": 0.0, "up": 0.0 },
  "endOffset": { "forward": 200.0, "right": 0.0, "up": 0.0 },
  "approachHeading": 90.0,
  "approachDirection": "FRONT",
  "glideSlopeAngle": 3.0,
  "touchdownZoneLength": 80.0,
  "wirelessModemSide": "top",
  "slotDurationSec": 120
}
```

| 키 | 기본값 | 설명 |
| :--- | :--- | :--- |
| `facilityId` | `"RWY_ALPHA_09L"` | `GAC` 인벤토리에 등록한 활주로 ID와 일치해야 함 |
| `touchdownOffset` / `endOffset` | `{0,0,0}` / `{200,0,0}` | 접지 시작점 및 활주로 종단점의 로컬 오프셋(m) |
| `approachHeading` | `90.0` | 활주로 착륙 진입 방위각(도, `09L = 090°`) |
| `glideSlopeAngle` | `3.0` | 표준 강하 진입각(도) |
| `touchdownZoneLength` | `80.0` | 유효 접지 구역 길이(m) |

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### 51×19 TUI 단축키

| 키 | 동작 | 설명 |
| :---: | :--- | :--- |
| `S` | Wizard 설정 재저장 | `setup_wizard`로 현재 설정 재조합 후 `/runway/config.json` 저장 |
| `F` | 강제 해제 (`Force Free`) | 활주로 FSM을 `FREE`로 복구하고 `GAC` 백본(`50202`)에 즉시 보고 |
| `L` | 등화 테스트 토글 | 유선 등화 상태를 `WAVE_OFF` 경광등 테스트 모드로 전환/복귀 |
| `Q` | 안전 종료 | 열린 채널을 닫고 종료 |

### 자주 발생하는 문제 및 해결법

- **화면에 `Wired HW : redstone_integrator_0 missing` 경고가 표시됨**
  - 유선 레드스톤 인티그레이터(`redstone_integrator`)가 연결되지 않았거나 유선 모뎀이 비활성(빨간 테두리 꺼짐) 상태입니다. 등화 제어가 불필요하다면 경고 상태 그대로 무선 유도만 정상 작동합니다.
- **기체가 착륙 후에도 활주로가 `OCCUPIED` / `ROLLOUT` 상태로 남아 있음**
  - 기체 `AMM`이 활주로 이탈(`MSG_RUNWAY_VACATED`) 보고 전에 정지했거나 수동 개입으로 종료된 경우입니다. `[F]` 키로 `Force Free`를 실행하거나 `GAC`에서 `[F]`로 슬롯을 해제하세요.
- **고정 지형 활주로인데 `position`과 `Threshold` 좌표가 0으로 표시됨**
  - `mobility`가 `"STATIC"`인 경우 `/runway/config.json`의 `position`에 실제 활주로 기준 블록 좌표를 정확히 기입하거나, GPS 클러스터가 온라인인지 확인하세요.
