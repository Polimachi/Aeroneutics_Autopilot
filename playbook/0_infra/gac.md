# GAC — 섹터 지상 계류장 관제기(Ground Apron Controller) 플레이북

> **대상 코드베이스**: `src/0_infra/gac/` (`main.lua`)  
> **관련 사양서**: [GAC_PROGRAM_SPECIFICATION_AND_ICD.md](../../docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`GAC (Ground Apron Controller)`는 공항·항모·전초기지 등 단일 섹터($S$)에 속한 모든 착륙패드(`Landing Pad`)와 활주로(`Runway`)의 인벤토리, 점유 상태, 착륙/이륙 슬롯 할당을 총괄하는 로컬 항공교통 관제 노드입니다.

- **시설 선택 및 전용 패드 매칭**: 기체 체크인(`MSG_GAC_CHECKIN_REQ`) 시 중량(`maxSupportWeight`), 반경(`maxSupportRadius`), 시설 타입뿐 아니라 **전용 기체/기종 지정(`dedicatedCraftIds`, `dedicatedAirframeTypes`)** 을 우선 매칭합니다.
- **비상 우선권 및 공용 패드 징발 (`EMERGENCY_REQUISITION`)**: 연료 부족(`BINGO_FUEL`)이나 비상 기체가 진입했는데 가용 패드가 없으면 타 일반 슬롯을 선점/징발해 착륙을 우선 허가합니다.
- **1Hz 섹터 비컨 송출 (`CH 50003` / `50004`)**: 기체 및 `GCS` Live Bridge가 섹터 내 시설 좌표·바람 정보·섹터 상태를 실시간으로 파악하도록 1Hz 브로드캐스트를 유지합니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 구분 | 품목 / 페리페럴 | 필수 여부 | 비고 |
| :--- | :--- | :---: | :--- |
| 컴퓨터 | Advanced Computer (`51×19`) | 필수 | 3탭 TUI 관제 콘솔 실행 |
| 통신 | Wireless Modem 또는 Ender Modem | 필수 | 섹터 백본·광역 ATC·접근 기체 동시 교신 |
| 외부 모니터 | Advanced Monitor (`51×19` 이상) | 선택 | 연결 시 터치(`monitor_touch`)로 탭 전환 및 시설 선택 지원 |

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. 공항 관제탑이나 항모 함교에 Advanced Computer를 배치하고 무선 모뎀을 부착합니다(함상/이동 기지에서도 운용 가능).
2. 관제실 전광판으로 쓰려면 컴퓨터 옆에 Advanced Monitor(폭 51×높이 19 이상)를 부착하거나 유선 모뎀으로 연결하세요. `peripheral` / `peripheral_detach` 이벤트를 감지해 모니터를 자동 인식합니다.
3. **섹터 인덱스 $S$ 분리 원칙**: 한 월드에 공항/항모가 여러 개라면 각 `GAC`의 `sectorIndex`($S = 1, 2, 3, \dots$)가 겹치지 않도록 다르게 설정해야 섹터 채널(`Base_sec`)이 충돌하지 않습니다.

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

섹터 인덱스 $S$ ($S \ge 1$)에 따른 섹터 기준 채널 공식은 다음과 같습니다:

$$\text{Base}_{\text{sec}} = 50001 + S \times 200$$

| 채널 | 기본값 ($S=1$) | 용도 | 송수신 대상 |
| :---: | :---: | :--- | :--- |
| `Base_sec + 0` | `50201` | 기체 체크인(`MSG_GAC_CHECKIN_REQ`), 착륙/이륙 허가(`CLEARANCE`), 이륙 요청(`DEPARTURE_REQ`) | 기체 `AMM` ↔ `GAC` |
| `Base_sec + 1` | `50202` | 섹터 로컬 백본 — 슬롯 할당(`SLOT_ASSIGN/ACK`), 상태 업데이트(`FACILITY_UPDATE`) | `GAC` ↔ `Landing Pad` / `Runway` |
| `50001` / `50002` | `50001` / `50002` | 광역 ATC 핸드오프 및 백본 상태 보고 | 광역 관제 ↔ `GAC` |
| `50003` | `50003` | 1Hz `MSG_FACILITY_BEACON` 송출 (시설 좌표, 풍향/풍속, 섹터 좌표 `position`) | `GAC` → `AMM` / `GCS` |
| `50004` | `50004` | 1Hz `MSG_DISPATCH_REPORT` 송출 | `GAC` → `AMM` / `GCS` |
| `50211+` | `50211+` | 각 시설 전술 채널(`tacticalChannel`) — `WAVE_OFF` / `EMERGENCY` 시 `MSG_ABORT_APPROACH` 직접 송신 | `GAC` → 접근 중 기체 |

---

## 5. 소프트웨어 설치 방법 (Installation)

1. 인게임 `GAC` 컴퓨터에서 통합 인스톨러를 실행합니다:
   ```text
   /installer.lua install gac
   ```
2. 설치 구조: `/main.lua`, `/config.lua`, `/modules/*.lua`, `/gac/config.json`, 부팅 훅 `/startup/00_gac.lua`.

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

설정 파일 경로는 `/gac/config.json`입니다.

```json
{
  "sectorId": "BASE_ALPHA_SECTOR_01",
  "sectorName": "Alpha Base Central Vertiport",
  "sectorType": "VERTIPORT",
  "sectorIndex": 1,
  "position": { "x": 1275.0, "y": 65.0, "z": -810.0 },
  "baseSecChannel": 50201,
  "towerAtcChannel": 50001,
  "beaconChannel": 50003,
  "dispatchChannel": 50004,
  "checkinTimeoutSec": 60,
  "slotDurationSec": 120,
  "surfaceWind": { "speed": 2.4, "direction": 195.0 },
  "facilities": [
    {
      "facilityId": "PAD_01",
      "type": "LANDING_PAD",
      "tacticalChannel": 50211,
      "maxSupportWeight": 40000.0,
      "maxSupportRadius": 12.0,
      "coordinates": { "x": 1250.0, "y": 65.0, "z": -820.0 },
      "status": "FREE",
      "mobility": "STATIC"
    }
  ]
}
```

- `position`: 섹터 중심 좌표 (`TASK-406` Live World Preset 지도상 GAC 아이콘 표시에 사용; 생략 시 `GCS`가 소속 시설 평균 Centroid를 산출).
- `facilities[]`: `type`으로 `"LANDING_PAD"` 또는 `"RUNWAY"`를 등록하며, 선택 키 `dedicatedCraftIds`(`["AIRCRAFT_01"]` 또는 CSV) 및 `dedicatedAirframeTypes`(`["VECTORED_VTOL"]`)로 전용 슬롯을 지정할 수 있습니다.
- `slotDurationSec`(`120`초): 할당된 착륙 슬롯이 시간 내에 완료되지 않으면 자동 만료되어 `FREE`로 복귀합니다.

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### 3-Tab TUI 단축키 및 터치 조작

| 키 | 동작 | 설명 |
| :---: | :--- | :--- |
| `1` / `2` / `3` | 탭 전환 | `[1: OVERVIEW]` / `[2: FACILITIES]` / `[3: LOGS & COMMS]` 전환 (외부 모니터 터치 가능) |
| `Up` / `Down` | 시설 선택 | `[2: FACILITIES]` 탭에서 관리할 시설 커서 이동 (또는 모니터 터치) |
| `A` | 시설 추가 | 하단 프롬프트 열기 — 형식: `ID,CH,X,Y,Z[,DED]` (예: `PAD_03,50213,1280,65,-810`) |
| `D` | 시설 삭제 | 선택된 시설 인벤토리에서 제거 |
| `P` | 전용 설정 편집 | 하단 프롬프트 열기 — 형식: `CraftID1,CraftID2|AirframeType1` (`Enter`로 저장, `Esc` 취소) |
| `M` | 정비 모드 토글 | 선택 시설 `FREE` ↔ `MAINTENANCE` 전환 및 백본 동기화 |
| `F` | 강제 해제 (`FORCE_FREE`) | 점유 고착된 시설을 강제로 `FREE` 상태로 리셋 |
| `W` | 복행 지령 (`WAVE_OFF`) | 선택 시설의 `tacticalChannel`로 `MSG_ABORT_APPROACH` 송출 및 `GO_AROUND` 전환 |
| `E` | 전 섹터 비상 폐쇄 | `EMERGENCY LOCKDOWN` 토글 — 활성 시 모든 시설에 `MSG_ABORT_APPROACH` 발령 및 섹터 상태 `DECK_DANGEROUS` 전환 |
| `S` | 설정 저장 | 현재 인벤토리 상태를 `/gac/config.json`에 즉시 저장 |
| `Q` | 안전 종료 | 열린 채널을 닫고 터미널 정리 후 종료 |

### 자주 발생하는 문제 및 해결법

- **예하 `Landing Pad`나 `Runway`가 등록되지 않거나 상태가 `FREE`로 안 바뀜**
  - `GAC`의 `baseSecChannel + 1`(예: `50202`)과 각 시설의 `sectorFacilityChannel`(`50202`), 그리고 `facilityId` 철자가 양쪽 `config.json`에서 정확히 일치하는지 확인하세요.
- **기체가 착륙 허가를 받지 못하고 `GO_AROUND` / 거부됨**
  - 전 섹터 비상 폐쇄(`E`)가 켜져 있거나, 기체 중량/반경이 모든 가용 시설의 `maxSupportWeight`/`maxSupportRadius`를 초과했거나, 모든 패드가 `dedicatedCraftIds` 전용으로 잠겨 있는지 `[2: FACILITIES]` 탭에서 확인하세요.
- **프롬프트 입력 중 문자가 입력되지 않거나 오작동할 때**
  - 프롬프트(`A` 또는 `P`) 활성 중에는 `Esc`로 취소하고 `Enter`로 확정합니다.
