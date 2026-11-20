# GPS Cluster — 3차원 삼각측량 측위 인프라 및 성상 품질 감시 플레이북

> **대상 코드베이스**: `src/0_infra/gps/` (`server.lua`, `node.lua`, `client_entry.lua`, `hal/gps_client.lua`)  
> **관련 사양서**: [GPS_PROGRAM_SPECIFICATION_AND_ICD.md](../../docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`GPS Cluster`는 마인크래프트 기본 CC `gps` 명령의 한계(동시 다중 클라이언트 충돌 및 비공면 GDOP 검증 부재)를 대체하여, 기체와 이동형 지상 시설(`Landing Pad`, `Runway`)에 20Hz 고속 3차원 측위와 성상 품질 등급(`MSG_NAV_QUALITY`)을 제공하는 지상 측위 인프라입니다.

- **중앙 솔버 서버 (`gps_server`)**: 스웜 노드가 보고한 거리 측정치를 세션 윈도우(`50ms`) 단위로 모아 3차원 구면 삼각측량을 수행하고, 성상 HDOP·생존 노드 수에 따라 `FIX_OK` / `FIX_DEGRADED` / `NO_FIX`를 응답합니다.
- **스웜 비컨 노드 (`gps_node`)**: 최소 4기 이상의 분산 컴퓨터가 측위 핑(`CH 60001`) 수신 거리와 자기 좌표를 서버로 보고하며, 10초마다 하트비트(`CH 60003`)를 송출해 서버 및 `GCS`에 노드의 생존 상태를 알립니다.
- **클라이언트 API (`gps_client`)**: 기체 `AMM`·지상 시설이 측위 핑을 보내고 응답과 `MSG_NAV_QUALITY`를 수신하도록 추상화합니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 노드 유형 | 품목 / 페리페럴 | 권장 수량 | 비고 |
| :--- | :--- | :---: | :--- |
| `gps_server` | Advanced Computer + Ender Modem | 1대 | 전역 비행 구역 전체와 노드 거리 보고 수신용 |
| `gps_server` (선택) | Advanced Monitor (해상도 `>= 80×30`) | 1면 | 4탭 시각 대시보드 및 2D 레이더 뷰 표시 (`textScale 0.5`) |
| `gps_node` | Computer + Wireless/Ender Modem | **최소 4대** | 공면(같은 평면) 배치를 피하고 높낮이와 수평을 분리 배치 |

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. **비공면(Non-Coplanar) 3D 위성군 배치 (핵심)**:
   - 4기 이상의 `gps_node`가 동일한 Y 높이나 한 직선 위에 놓이면 수직 방향 삼각측량 해가 발산합니다(GDOP 불량).
   - **권장 배치**: 기지 중심을 감싸는 사각형 또는 삼각뿔 형태로 X/Z 간격을 충분히(예: 100~300블록 이상) 벌리고, **최소 2개 이상의 서로 다른 고도(Y)**(예: 고층 타워 상단 `Y=140~200` 2기 + 다른 구역 중간/저고도 타워 `Y=75~95` 2기)에 분산 설치하세요.
2. **Ender Modem 사용 권장**:
   - 일반 Wireless Modem은 고도·거리 및 폭풍우 시 수신 반경이 급감하므로, 서버와 모든 노드에는 장거리 전천후 **Ender Modem** 부착을 권장합니다.
3. **모니터 연결 (`gps_server`)**:
   - 대형 모니터(`80×30` 이상)를 연결하고 텍스트 스케일 `0.5`로 설정되면 서버가 자동으로 4탭 터치 UI를 활성화합니다.

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

`GPS Cluster`는 글로벌 GPS 예약 대역(`60001 ~ 60020`) 중 4개 채널을 사용합니다.

| 채널 | 상수명 | 용도 | 송수신 방향 |
| :---: | :--- | :--- | :--- |
| `60001` | `CH_GPS_PING` | 클라이언트 측위 핑(`MSG_REQUEST`) 및 노드 간 교차 진단 핑(`MSG_DIAG_PING`) | Client/Server → Nodes |
| `60002` | `CH_GPS_SERVICE` | 상태 요청/응답(`MSG_STATUS_REQ/RESP`) 및 클라이언트 응답 발신 소스 | Client ↔ Server |
| `60003` | `CH_GPS_NODE_IN` | 노드 거리 보고(`MSG_NODE_REPORT`), 10초 하트비트(`MSG_NODE_HEARTBEAT`, `GCS`도 구독), 커미셔닝 요청 | Nodes → Server / `GCS` |
| `60004` | `CH_GPS_MGMT` | 노드 커미셔닝(`MSG_NODE_OFFER/VERIFY_RESP/REG_ACK`) 및 교차 진단 트리거(`MSG_DIAG_TRIGGER`) | Server ↔ Nodes |
| `Base + 5` / `Base_sec + 5` | `replyChannel` | 기체(`AMM`) 또는 스마트 시설(`Landing Pad`/`Runway`)이 요청 패킷에 명시하는 응답 수신 채널 | Server → Client |

---

## 5. 소프트웨어 설치 방법 (Installation)

1. **중앙 서버 컴퓨터**:
   ```text
   /installer.lua install gps_server
   ```
   - `/gps/server.lua`, `/gps_data/nodes.json`, 부팅 훅 `/startup/00_gps.lua` 생성.
2. **각 위성/지상 비컨 노드 컴퓨터 (4기 이상)**:
   ```text
   /installer.lua install gps_node
   ```
   - `/gps/node.lua`, 부팅 훅 `/startup/00_gps.lua` 생성.
3. **수동 실행 및 모드 지정 (`/gps/main.lua`)**:
   - `/gps/main.lua` 기본 인자는 `server`이며, `main.lua node [args...]` 또는 `main.lua client [args...]`로 실행할 수 있습니다.
   - CLI 인자만으로 노드 즉시 기동: `/gps/node.lua <nodeId> <x> <y> <z>` (예: `NODE_01 1200 160 -350`).

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

### 노드 설정 (`/gps_data/node.json`)

```json
{
  "version": "1.9.5",
  "nodeId": "NODE_01",
  "computerId": 12,
  "position": { "x": 1200, "y": 160, "z": -350 },
  "channels": {
    "ping": 60001,
    "service": 60002,
    "nodeIn": 60003,
    "mgmt": 60004
  },
  "modemSide": "top"
}
```

### 서버 노드 레지스트리 (`/gps_data/nodes.json`)

```json
{
  "version": "1.9.5",
  "nodes": {}
}
```

- **부팅 시 자동 커미셔닝**: `/gps_data/node.json`이 없거나 부팅 직후 **3초 카운트다운 중 `[S]` 키**를 누르면 4단계 Setup Wizard(`Hello → F3 좌표 "X Y Z" 입력 → 스웜 교차 잔차 검증 → 등록 저장`)가 실행됩니다.
- **노드 와치독 (`gps_server`)**: `10초` 초과 무응답 시 `STALE`, `35초` 초과 시 `OFFLINE`으로 전환합니다.

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### `gps_server` 대형 모니터 터치 조작

| 위치 | 버튼 / 탭 | 동작 |
| :--- | :--- | :--- |
| 상단 Y=1..2 | `[1: OVERVIEW]` / `[2: CLIENTS]` / `[3: NODES]` / `[4: RADAR]` | 시스템 요약 / 추적 중 기체 좌표 / 노드 상태 / 2D 레이더 뷰 전환 |
| 하단 | `[ REFRESH ]` / `[ REFIT ]` | 노드·클라이언트 경계 범위 및 중심 재계산 |
| 하단 | `[ CALIBRATE ]` | 첫 번째 노드 대상으로 교차 거리 진단(`MSG_DIAG_TRIGGER`) 트리거 |
| 하단 | `[ CLEAR ]` | 진단 상태 및 화면 초기화 |

### `gps_node` 조작

- **Setup Wizard 재실행**: 부팅 카운트다운(3초) 중 `S` 입력 (`wizard_cli.lua`로 F3 좌표 재입력).

### 자주 발생하는 문제 및 해결법

- **`FIX_DEGRADED` 또는 `NO_FIX`가 발생함**
  - 온라인 노드가 4개 미만(`activeNodes < 4`)이거나 노드들이 동일 평면(비슷한 Y 좌표)에 배치되어 삼각측량 행렬 조건수가 나쁜 경우입니다. 1개 이상의 노드 고도(Y)를 30블록 이상 높이거나 낮춰 3차원 분포를 만드세요.
- **기체가 `NAV_QUALITY_DEGRADED` / `HOLD_LEVEL` 상태에 진입함 (`TASK-128`)**
  - 청크 언로드 또는 모뎀 거리 이탈로 GPS 응답이 500ms~1,500ms 이상 지연되었을 때 `VAS`/`FCP`가 안전을 위해 수평 홀드로 보호하는 상태입니다. 비행 반경 내 Ender Modem 커버리지와 서버 청크 로딩 상태를 확인하세요.
- **노드 등록 시 `Swarm Max Residual` 경고가 큼**
  - F3 스크린샷에서 읽은 컴퓨터 블록 좌표(`X Y Z`)에 오타가 있거나 다른 노드와 동일 좌표가 중복 입력된 경우입니다. `[S]` 위저드로 정확한 블록 좌표를 다시 입력하세요.
