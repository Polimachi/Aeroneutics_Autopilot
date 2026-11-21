# Pocket PDA — 휴대용 원격 관제·비상 E_STOP·지상 콘솔 링크 플레이북

> **대상 코드베이스**: `src/0_infra/pocket_pda/` (`main.lua`)  
> **관련 사양서**: [POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md](../../docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`Pocket PDA`는 조종사와 비행시험 정비사가 월드 내에서 직접 휴대하는 **CC:Tweaked Pocket Computer (`26×20`) 기반 휴대용 원격 관제·실시간 텔레메트리 HUD·지상 콘솔 통합 제어 단말**입니다. 고정형 `51×19` [GCS](gcs.md)와 별도로 현장 이동 중에도 즉시 기체 상태와 무선 링크 품질을 감시하고, 단일 키로 비상 정지 및 블랙박스 덤프를 실행하며, 격납고 [Alignment](../0_development/alignment.md)와 [FDR](../0_development/fdr.md)을 원격 조작하도록 설계되었습니다.

- **핵심 설계 결정 (`R1`–`R5`)**:
  - **`R1` (`FDR` 무송신 불변식 준수)**: `FDR`은 어떤 경로에서도 `modem.transmit`을 0회 호출합니다. Pocket PDA는 `Base + 9`로 `MSG_FDR_REMOTE_CMD`를 단방향 송출하고 내부 `fdr` 상태를 낙관적 갱신하며, `fdrBoundIndexN ~= N`일 때 `fdrBoundBase + 9`와 `Base + 9` 양쪽에 송신합니다.
  - **`R2` (글로벌 단일 키 `[X]` `E_STOP` + `DUMP_NOW`)**: 어느 탭에서도 확인 프롬프트 없이 `[X]` 입력 즉시 `Base + 9`로 `MSG_EMERGENCY_OVERRIDE`(`action = "E_STOP"`)와 `MSG_FDR_REMOTE_CMD`(`action = "DUMP_NOW"`)를 연쇄 송출합니다.
  - **`R3` (`[L]` `LAND_NEAREST` 온보드 중재)**: Pocket PDA는 패드 좌표를 직접 계산하지 않고 `Base + 0`으로 `LAND_NEAREST`를 송출하며, 온보드 [AMM](../3_planning/amm.md) `c2_arbiter`가 `facility_client` 비콘 인벤토리에서 최근접 `FREE` 착륙 시설을 선택합니다(빈 시설 부재 시 `EMERGENCY_LAND` 폴백).
  - **`R4` (`Alignment` 전 생명주기 원격 제어)**: $Base_{\text{hangar}} + 0 / +1$에서 `MSG_ALIGN_REMOTE_CMD` 및 `MSG_ALIGN_REMOTE_STATUS`를 교환해 세션 바인딩·펄스 개시·일시정지·단계 재시도·동기화 승인·중단·채널 해제를 원격 지휘합니다.
  - **`R5` (`26×20` 3-탭 무깜박 TUI)**: 모든 행을 26열 × 20행(`term.blit`)으로 고정해 `HUD` / `ALIGN` / `FDR` 3개 탭을 줄바꿈·스크롤 없이 표출합니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 구분 | 품목 / 조건 | 필수 여부 | 비고 |
| :--- | :--- | :---: | :--- |
| 단말 본체 | Wireless Pocket Computer 또는 Ender Pocket Computer (`26×20`) | 필수 | 기본 화면 크기 `26×20` (`term.blit` 컬러/모노 지원) |
| 통신 모뎀 | 내장 Wireless Modem 또는 Ender Modem (`modemSide: "back"` 기본) | 필수 | 차원 간 장거리·무제한 거리 운용 시 Ender Modem 권장 |
| 테스트/거치 환경 | 외부 무선 모뎀 자동 폴백 | 선택 | `"back"` 슬롯이 모뎀이 아닌 경우 `peripheral.find("modem")`으로 무선 모뎀 탐색 |

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. **제작 및 조합**: Pocket Computer(일반 또는 Advanced)와 Wireless Modem 또는 Ender Modem을 조합 테이블에서 결합해 Wireless/Ender Pocket Computer를 제작합니다(모뎀은 기본 슬롯 `"back"`에 장착됩니다).
2. **일반 무선 모뎀(`Wireless Modem`) vs `Ender Modem` 선택**:
   - **일반 Wireless Modem**: `modem_message`의 `senderDistance` 실측값을 수신하므로 `HUD`에 실제 거리(`38.0m` 등)와 `STRONG`/`GOOD`/`WEAK` 등급이 표시됩니다(고도/장애물에 따른 최대 송신 거리 제한 적용).
   - **Ender Modem**: 동일 차원 장거리·차원 간 전송 시 `senderDistance`가 `nil`로 전달될 수 있으며, 이때 링크 분류기는 `STRONG ENDER (100%)`로 표기합니다.
3. **안전 수칙**: Pocket PDA를 손에 쥐거나 인벤토리에 소지한 상태에서 기체 근처 이동 시 `[X]` 단일 키 `E_STOP` 오입력을 방지하려면 주 사용 탭 전환 후에도 키보드 입력 포커스를 확인하세요.

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

기체 인덱스 $N \in [1, 1000]$의 블록 기준 채널은 $\text{Base} = 10000 + (N - 1) \times 40$, 격납고 베이 번호 $B \in [1, 10]$의 기준 채널은 $Base_{\text{hangar}} = 101 + (B - 1) \times 10$입니다.

| 채널 | 기본값 (`N=1, B=1`) | 개방(`open`) | 방향 | 용도 및 주요 패킷 |
| :---: | :---: | :---: | :---: | :--- |
| `Base + 0` | `10000` | 상시 개방 | PDA ↔ AMM | `MSG_OPERATOR_CMD` (`HOLD`/`RTB`/`LAND_NEAREST`/`ARM`/`TAKEOFF`, `GCS_OVERRIDE`) 및 `MSG_MISSION_ACK` |
| `Base + 2` | `10002` | 상시 개방 | VAS → PDA | 20Hz `MSG_FLIGHT_TELEMETRY` (쿼터니언→오일러 변환) 및 `MSG_PBIT_REPORT` |
| `Base + 3` | `10003` | 상시 개방 | AMM/VAS → PDA | 5Hz `MSG_MFD_STATE` (비행 모드·FSM·고도·연료·액추에이터 상태) |
| `Base + 8` | `10008` | 상시 개방 | PDA ↔ VAS | `MSG_PBIT_REQ` 비행 전 자가진단 요청 및 `MSG_PBIT_REPORT` 수신 |
| `Base + 9` | `10009` | 상시 개방 | PDA ↔ VAS/FDR | `MSG_EMERGENCY_OVERRIDE` (`E_STOP`), `MSG_EMERGENCY_ALERT`, `MSG_FDR_REMOTE_CMD` (`0 tx` 단방향) |
| `Base_hangar + 0` | `101` | 송신 전용 | PDA → Alignment | `MSG_ALIGN_REMOTE_CMD` (격납고 베이 원격 세션 제어 명령) |
| `Base_hangar + 1` | `102` | 상시 개방 | Alignment/VAS → PDA | `MSG_ALIGN_REMOTE_STATUS`, `MSG_CALIBRATION_INIT_ACK`, `MSG_CALIB_ACK`, `MSG_CALIBRATION_CLOSE_ACK` |
| `50000` | `50000` | 상시 개방 | GCS → AMM 감청 | `MSG_BLOCK_ASSIGN` 패시브 스누핑으로 편대 기체 자동 발견 |
| `50004` | `50004` | 상시 개방 | AMM/GAC → GCS 감청 | `MSG_MISSION_ACK` 광역 미션 응답 감청 |

- `[` / `]` (또는 `Left` / `Right`) 및 `[Tab]`으로 기체 $N$을 전환하면 이전 블록 `oldBase + {0, 2, 3, 8, 9}`를 닫고 `newBase + {0, 2, 3, 8, 9}`를 즉시 개방합니다.
- `[2]ALIGN` 탭에서 `-` / `=`(`+`)로 베이 $B$를 전환하면 `oldHangarBase + 1`을 닫고 `newHangarBase + 1`을 개방합니다.

---

## 5. 소프트웨어 설치 방법 (Installation)

1. Pocket Computer 터미널에서 [Unified Installer](../0_development/installer.md) 부트스트랩을 실행합니다:
   ```text
   /installer.lua install pocket_pda
   ```
   (최초 설치 시 GitHub 또는 Google Drive 부트스트랩을 통해 `/installer.lua` 취득 후 `pocket_pda` 선택 설치 가능)
2. 배포 파일 경로:
   - `/main.lua` (`src/0_infra/pocket_pda/main.lua`)
   - `/config/pda_config.json` (`src/0_infra/pocket_pda/config/pda_config.json`)
   - `/modules/{pda_network,telemetry_hud_state,emergency_c2_controller,remote_link_controller,pocket_tui}.lua`
   - `/lib/avionics_sensors.lua`
   - `/startup/00_pocket_pda.lua` (부팅 시 `/main.lua` 자동 실행)

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

설정 파일 경로는 `/config/pda_config.json`이며, 누락된 키는 `main.load_config`가 아래 중첩 스키마 기본값으로 보완합니다.

```json
{
  "schemaVersion": "1.0.0",
  "system": {
    "id": "PDA_01",
    "domainId": "POCKET_PDA_01",
    "modemSide": "back",
    "loopFrequencyHz": 20,
    "uiRefreshRateHz": 5
  },
  "defaults": {
    "aircraftIndexN": 1,
    "targetDomainId": "AIRCRAFT_01",
    "hangarBayId": 1,
    "fdrBoundIndexN": 1
  },
  "channels": {
    "gcsBootstrapChannel": 50000,
    "missionAckChannel": 50004,
    "aircraftBaseMin": 10000,
    "aircraftBandwidth": 40,
    "maxAircraft": 1000,
    "hangarBaseMin": 101,
    "hangarBandwidth": 10,
    "maxHangarBays": 10
  },
  "linkQuality": {
    "telemetryTimeoutMs": 2000,
    "nodeStaleMs": 3000,
    "strongMaxDistM": 80.0,
    "goodMaxDistM": 200.0
  },
  "ui": {
    "screenWidth": 26,
    "screenHeight": 20
  }
}
```

| 키 경로 | 기본값 | 설명 |
| :--- | :---: | :--- |
| `system.modemSide` | `"back"` | 모뎀 장착 슬롯 (`"back"` 우선 확인 후 미탐지 시 무선 모뎀 폴백 탐색) |
| `system.uiRefreshRateHz` | `5` | `26×20` `term.blit` TUI 갱신 주기(Hz) |
| `defaults.aircraftIndexN` / `targetDomainId` | `1` / `"AIRCRAFT_01"` | 초기 감청 기체 번호 $N$ 및 도메인 ID |
| `defaults.hangarBayId` / `fdrBoundIndexN` | `1` / `1` | 초기 격납고 베이 번호 및 `FDR` 바인딩 기체 번호 |
| `linkQuality.telemetryTimeoutMs` | `2000` | 마지막 텔레메트리 수신 후 `LOST` 판정 임계 시간(ms) |
| `linkQuality.nodeStaleMs` | `3000` | 노드 온라인 배지(`AMM*`, `VAS*`, `GCS*`, `ALN*`, `FDR*`) 만료 시간(ms) |
| `linkQuality.strongMaxDistM` / `goodMaxDistM` | `80.0` / `200.0` | 거리 기반 링크 품질 분류 기준(`<= 80.0m`: `STRONG`, `<= 200.0m`: `GOOD`, `> 200.0m`: `WEAK`) |

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### `26×20` TUI 키바인딩 매트릭스

| 범위 / 탭 | 키 입력 | 동작 / 원격 명령 | 송신 패킷 및 채널 |
| :--- | :---: | :--- | :--- |
| **전역** | `1` / `2` / `3` | 탭 전환 (`[1]HUD` / `[2]ALN` / `[3]FDR`) | 로컬 UI 전환 |
| **전역** | `X` | **`E_STOP` + `DUMP_NOW`** (`R2`, 확인 없음) | `MSG_EMERGENCY_OVERRIDE` (`Base+9`) + `MSG_FDR_REMOTE_CMD` (`Base+9` / `fdrBoundBase+9`) |
| **전역** | `H` | 수평 정지 호버 (`HOLD` / `HOVER_HOLD`) | `MSG_OPERATOR_CMD` (`Base+0`) |
| **전역** | `R` | 홈 패드 귀환 (`RTB` → `RTH` / `FAILSAFE_RTH`) | `MSG_OPERATOR_CMD` (`Base+0`) |
| **전역** | `L` | 최근접 빈 시설 착륙 (`LAND_NEAREST`, `R3`) | `MSG_OPERATOR_CMD` (`Base+0`) |
| **전역** | `[` / `,` / `Left` | 이전 기체 ($N \leftarrow \max(1, N-1)$) | 기체 채널 재바인딩 |
| **전역** | `]` / `.` / `Right` | 다음 기체 ($N \leftarrow \min(1000, N+1)$) | 기체 채널 재바인딩 |
| **전역** | `Tab` | `CH 50000`으로 발견된 편대 기체 순환 | 기체 채널 재바인딩 |
| **전역** | `Q` | 개방 채널 닫기 및 안전 종료 | `modem.close()` |
| **`[1]HUD`** | `A` / `T` / `P` | `ARM` / `TAKEOFF` / `PBIT` 요청 | `MSG_OPERATOR_CMD` (`Base+0`) / `MSG_PBIT_REQ` (`Base+8`) |
| **`[2]ALIGN`** | `-` | 이전 격납고 베이 (`Bay - 1`, `1 ~ 10`) | `Base_hangar+1` 재바인딩 |
| **`[2]ALIGN`** | `=` / `+` | 다음 격납고 베이 (`Bay + 1`, `1 ~ 10`) | `Base_hangar+1` 재바인딩 |
| **`[2]ALIGN`** | `B` / `G` / `P` | `BIND_SESSION` / `START_PULSE` / `PAUSE_SESSION` | `MSG_ALIGN_REMOTE_CMD` ($Base_{\text{hangar}}+0$) |
| **`[2]ALIGN`** | `T` / `Y` | `RETRY_STEP` / `APPROVE_SYNC` | `MSG_ALIGN_REMOTE_CMD` ($Base_{\text{hangar}}+0$) |
| **`[2]ALIGN`** | `A` / `K` | `ABORT_SESSION` / `RELEASE_SESSION` | `MSG_ALIGN_REMOTE_CMD` ($Base_{\text{hangar}}+0$) |
| **`[3]FDR`** | `B` | `BIND_AIRCRAFT` (현재 PDA 기체 $N$에 `FDR` 재바인딩, `autoStartLogging=true`) | `MSG_FDR_REMOTE_CMD` (구 `fdrBoundBase+9` & 신 `Base+9`) |
| **`[3]FDR`** | `M` | `SET_MODE` (`LOGGING` ↔ `STANDBY` 토글) | `MSG_FDR_REMOTE_CMD` (`fdrBoundBase+9` / `Base+9`) |
| **`[3]FDR`** | `D` / `U` / `S` / `C` | `DUMP_NOW` / `EXPORT_NOW` / `ROLLOVER_NOW` / `CLEAR_BUFFER` | `MSG_FDR_REMOTE_CMD` (`fdrBoundBase+9` / `Base+9`) |

### 자주 발생하는 문제 및 해결법

- **`HUD` 링크 상태가 `LOST ---`로 고정되고 기체 원격 명령이 동작하지 않음**
  - 대상 기체 번호 `N`(`N:001` = `CH 10000`)과 실제 기체 [VAS](../1_control/vas.md)/[AMM](../3_planning/amm.md)의 `baseChannel`이 일치하는지 확인하세요. `]`/`[`로 인덱스를 맞추거나 `GCS` 부트스트랩(`50000`) 수신 후 `Tab`으로 발견 기체를 선택할 수 있습니다.
  - 거리가 Wireless Modem 송신 한계를 넘은 경우 `LOST`로 전환되므로 기체 쪽으로 접근하거나 Ender Pocket Computer를 사용하세요.
- **`[2]ALIGN`에서 `[B]ind`를 눌러도 `ALN` 응답이 오지 않음**
  - Pocket PDA의 `BAY:01` (`CH 101`/`102`)이 실제 격납고 [Alignment](../0_development/alignment.md) 콘솔의 `bayId`와 일치하는지 확인하고, 다르면 `=`/`+` 또는 `-` 키로 베이 번호를 맞추세요.
  - 기체가 `E_STOP` 상태이거나 기체 번호 $N$이 잘못된 경우 `Alignment` 또는 `VAS`가 세션을 거부(`REJECTED`)할 수 있습니다.
- **`[3]FDR`에서 `[D]ump`를 눌렀는데 `FDR*` 배지만 켜지고 RF 응답 패킷이 보이지 않음**
  - 정상 동작입니다. [FDR](../0_development/fdr.md)은 `modem.transmit == 0` 수신 전용 노드로 설계되어(`R1`), `MSG_FDR_REMOTE_CMD`를 수신·실행한 뒤 무선 응답을 송출하지 않습니다. 실제 파일 생성 여부는 `FDR` 본체 터미널의 `lastEventMsg` 또는 디스크(`/disk/fdr_logs/`·`/logs/`)에서 확인하세요.
- **기체가 `E_STOP`된 뒤 `[T]akeoff`를 눌러도 이륙하지 않음**
  - `[X]`에 의해 `VAS`가 하드 래치된 `E_STOP` 상태에서는 비행 중 복귀가 차단됩니다. 기체 안전 확인 후 `VAS` 컴퓨터를 재부팅(또는 격납고 재점검)한 뒤 `HUD`에서 `[P]BIT`을 먼저 수행하세요.
