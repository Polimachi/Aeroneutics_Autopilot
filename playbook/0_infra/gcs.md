# GCS & Live Bridge — 중앙 지상 관제소 및 WebUI 실시간 중계 플레이북

> **대상 코드베이스**: `src/0_infra/gcs/` (`main.lua`), `tools/gcs_live_bridge.py`  
> **관련 사양서**: [GCS_PROGRAM_SPECIFICATION_AND_ICD.md](../../docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`GCS (Ground Control Station / Node 08)`는 전역 비행체들의 40채널 블록을 충돌 없이 할당·관리하고, 다중 기체 텔레메트리를 실시간 추적하며, 원격 C2/비상 `E_STOP` 및 호스트 WebUI(`amm_mission_editor.html`) 연동을 중계하는 중앙 지상 관제소입니다.

- **동적 40채널 부트스트랩 할당 (`CH 50000`)**: 기체 `AMM`의 `MSG_BLOCK_REQUEST`를 수신해 `10000 ~ 49960` 구간(최대 1,000대, 대역폭 `40`) 내 비충돌 블록을 영속 리스(`/config/channel_registry.json`)로 발급·재할당(`ASSIGNED` / `REASSIGNED`)합니다.
- **원격 C2 및 비상 정지 (`E_STOP`)**: 선택된 기체의 `Base+0`으로 `ARM`/`TAKEOFF`/`HOLD`/`RTH`/`LAND`를 지령하고, `Base+9`로 즉시 비상 정지(`MSG_EMERGENCY_OVERRIDE`)를 송출합니다.
- **실시간 WebSocket Live Bridge (`TASK-404` / `405` / `406`)**: `GAC`의 시설 비컨(`CH 50003`), `GPS` 노드의 하트비트(`CH 60003`, 60초 TTL `OFFLINE` 관리), 기체 텔레메트리(`Base+3`)를 `tools/gcs_live_bridge.py`를 통해 호스트 브라우저 WebUI로 스트리밍하고, WebUI의 원클릭 `Push to Aircraft` 미션을 기체(`Base+0`)로 무선 전송합니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 구분 | 품목 / 조건 | 필수 여부 | 비고 |
| :--- | :--- | :---: | :--- |
| 컴퓨터 | Advanced Computer (`51×19`) | 필수 | 다중 기체 상태 컬러 TUI 렌더링 |
| 통신 | Ender Modem (`modemSide: "top"` 기본) | 필수 | 전역 공역의 모든 기체 및 시설 수신 필요 |
| 네트워크 (Live 사용 시) | CC:Tweaked HTTP/WebSocket 허용 | 선택 | `127.0.0.1` 또는 사설 LAN IP WebSocket 접속 허용 필요 |

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. 중앙 사령부/관제탑 내부에 Advanced Computer를 설치하고, 상단(`"top"`) 등 설정된 면에 Ender Modem을 장착합니다.
2. 기지가 광범위할 경우 `GCS` 청크가 언로드되지 않도록 스폰 청크 또는 청크 로더 구역 내에 배치하세요.
3. **WebUI Live Bridge를 사용할 때의 CC:Tweaked 서버 설정**:
   - 싱글플레이어/사설 서버의 `computercraft-server.toml`에서 로컬 루프백(`127.0.0.1`) 또는 브리지 호스트의 사설 IP(`192.168.*` 등)가 HTTP 차단 대역(`private_ip` 등)에 막혀 있지 않은지 확인하세요.

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

`GCS`는 부트스트랩/인프라 공용 채널과 등록된 각 기체의 40채널 블록 내 C2/다운링크 채널을 함께 엽니다.

| 채널 | 방향 | 용도 |
| :---: | :---: | :--- |
| `50000` | 양방향 | `MSG_BLOCK_REQUEST` 수신 및 `MSG_BLOCK_ASSIGN` 응답 (채널 부트스트랩) |
| `50003` | 수신 | `GAC` 1Hz `MSG_FACILITY_BEACON` 수신 → WebUI `WORLD_PRESET_SYNC` 전달 |
| `50004` | 수신 | 기체 `MSG_MISSION_ACK` 수신 → WebUI `MISSION_PUSH_ACK` 전달 |
| `60003` | 수신 | `GPS` 노드 10초 `MSG_GPS_NODE_HEARTBEAT` 수신 (60초 무신호 시 `OFFLINE`/`STALE`) |
| `Base + 0` | 송신 | 선택 기체로 원격 C2 명령 및 무선 `MISSION_PUSH_CMD` 송출 |
| `Base + 3` | 수신 | 기체 20Hz/5Hz `MSG_MFD_STATE` 텔레메트리 수신 |
| `Base + 9` | 송신 | `MSG_EMERGENCY_OVERRIDE` (`E_STOP`) 비상 코어 강제 정지 송출 |

---

## 5. 소프트웨어 설치 방법 (Installation)

1. 인게임 `GCS` 컴퓨터에서 통합 인스톨러를 실행합니다:
   ```text
   /installer.lua install gcs
   ```
   - `/main.lua`, `/modules/*.lua`, `/config/gcs_config.json`, `/config/channel_registry.json`, 부팅 훅 `/startup/00_gcs.lua` 설치.
2. **(선택) 호스트 PC Live Bridge 서버 실행**:
   ```powershell
   # 동일 PC에서 실행 시 (기본 127.0.0.1:8765)
   python tools/gcs_live_bridge.py --port 8765

   # 마인크래프트 서버와 WebUI 브라우저가 LAN 내 다른 PC에 있을 때
   python tools/gcs_live_bridge.py --port 8765 --lan
   ```
   - `--lan` 플래그 지정 시 `0.0.0.0`에 바인딩하며 터미널에 LAN 사설 IP 접속 URL(`ws://<LAN_IP>:8765`)을 안내합니다.

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

설정 파일 경로는 `/config/gcs_config.json`입니다.

```json
{
  "system": {
    "id": "GCS_01",
    "name": "Ground Control Station",
    "domainId": "GCS_01",
    "loopFrequencyHz": 20,
    "uiRefreshRateHz": 5,
    "modemSide": "top"
  },
  "channels": {
    "bootstrapChannel": 50000,
    "facilityBeaconChannel": 50003,
    "missionAckChannel": 50004,
    "gpsHeartbeatChannel": 60003,
    "bandwidth": 40,
    "baseChannelMin": 10000,
    "baseChannelMax": 49960,
    "maxCraftBlocks": 1000
  },
  "liveBridge": {
    "enabled": false,
    "url": "ws://127.0.0.1:8765",
    "telemetrySyncHz": 5
  },
  "ui": {
    "screenWidth": 51,
    "screenHeight": 19,
    "telemetryTimeoutSec": 5.0
  }
}
```

- Live Mode 사용 시 `liveBridge.enabled`를 `true`로 바꾸고 `liveBridge.url`을 브리지 주소(`ws://127.0.0.1:8765` 또는 `ws://<LAN_IP>:8765`)로 맞춘 뒤 `GCS`를 재시작하세요.
- `/config/channel_registry.json`에는 발급된 기체별 `domainId`, `hardwareUuid`, `baseChannel`, `blockId`가 저장됩니다.

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### 인게임 51×19 TUI 단축키

| 키 | 동작 | 대상 |
| :---: | :--- | :--- |
| `Tab` / `Space` | 다음 기체 선택 | 등록된 기체 순환 전환 |
| `A` | `ARM` | 활성 기체 시동 준비 지령 |
| `T` | `TAKEOFF` | 활성 기체 이륙 지령 (`altitude: 80.0m`) |
| `H` | `HOLD` | 활성 기체 현 위치 체공 |
| `R` | `RTH` | 활성 기체 홈 패드 귀환 |
| `L` | `LAND` | 활성 기체 착륙 |
| `X` | **`E_STOP`** | 활성 기체 `Base+9` 비상 정지 송출 |
| `C` | 레지스트리 저장 | `/config/channel_registry.json` 수동 저장 |
| `Q` | 안전 종료 | Live Bridge WebSocket 정리 후 종료 |

### 자주 발생하는 문제 및 해결법

- **`GCS`가 호스트 `gcs_live_bridge.py`에 연결되지 않음 (`HTTP_WS_UNAVAILABLE` / 연결 실패)**
  - `gcs_config.json`의 `liveBridge.enabled`가 `true`인지 확인하고, CC:Tweaked 서버 설정(`computercraft-server.toml`)에서 사설 대역 HTTP/WebSocket 차단이 해제되어 있는지 점검하세요. LAN 환경에서는 브리지 실행 시 `--lan` 옵션을 붙여야 합니다.
- **기체와 `GCS` 간 채널 블록이 꼬여 충돌함**
  - `GCS`를 켠 상태에서 기체 `AMM`을 부팅하면 `CH 50000` 부트스트랩을 통해 자동 재할당(`REASSIGNED`)됩니다. 수동 초기화가 필요하면 `/config/channel_registry.json`을 점검하거나 `[C]`로 현재 할당을 저장한 뒤 기체를 재부팅하세요.
- **WebUI에서 GPS 노드가 `[OFFLINE]`으로 어둡게 표시됨**
  - `GCS`가 `CH 60003`에서 60초(`60000ms`) 이상 하트비트를 받지 못한 상태입니다. 해당 GPS 노드의 전원 및 청크 로딩을 확인하거나, 실제로 철거된 노드라면 WebUI에서 `Purge Offline`으로 정리하세요.
