# GCS (지상 관제소 및 채널 관리자) 상세 규격서
> **GCS: Ground Control Station & RF Channel Manager**  
> **프로젝트**: Universal Autonomous Flight Stack (UAFS Ecosystem)  
> **운영 환경**: Minecraft CC:Tweaked, Create: Aeronautics, Create: Avionics  

| 항목 | 내용 |
| :--- | :--- |
| **문서 상태 (Status)** | `Implemented` |
| **문서 버전 (Version)** | `v1.4.0` |
| **최종 수정일 (Date)** | `2026-11-18` |
| **구현 코드 (Source)** | `src/0_infra/gcs/` |
| **주관 도메인 (Domain)** | 지상 인프라 및 전역 무선 채널 관리 (GCS / Node 08) |

> **참조 문서**: 
> - [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md) (마스터 ICD v1.37.0)
> - [SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md](../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 구조도 v2.20.1)
> - [AMM_PROGRAM_SPECIFICATION.md](../../3_planning/amm/AMM_PROGRAM_SPECIFICATION.md) (임무 관리자 및 조종석 단말 v2.5.0)
> - [AMM_MISSION_EDITOR_SPECIFICATION.md](../../3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md) (외부 웹 GUI 미션 에디터 v0.6.0)
> - [FCP_PROGRAM_SPECIFICATION.md](../../2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md) (외루프 유도 v2.4.0)
> - [VAS_PROGRAM_SPECIFICATION.md](../../1_control/vas/VAS_PROGRAM_SPECIFICATION.md) (비행 제어 코어 v1.24.0)
> - [GEMINI.md](../../../../GEMINI.md) (전역 규칙 및 가이드라인)

### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v1.4.0` | `2026-11-18` | **`TASK-405` `--lan` 브리지 바인딩 및 `TASK-406` `CH 60003` GPS 하트비트·`gacNode` 무게중심·`60s` `OFFLINE` TTL 규격 추가 (`Implemented` $\to$ `Approved`)**: ① `channels.gpsHeartbeatChannel` (`60003`) 상시 청취로 `MSG_GPS_NODE_HEARTBEAT` 수신 및 WebSocket `GPS_NODES_SYNC` 중계, ② `WORLD_PRESET_SYNC`에 `gacNode` 요약(명시적 `position` 우선, 부재 시 `facilities[]` 무게중심 자동 산출) 첨부, ③ `60,000ms` 무신호 시 GPS/비행체 노드를 삭제 대신 `OFFLINE`/`STALE` 상태로 표기 및 `purge_offline_gps_nodes()` 제공, ④ 호스트 브리지 `tools/gcs_live_bridge.py`에 `--lan`(`0.0.0.0` 바인딩 및 LAN 접속 URL 안내) 옵션 추가 및 연관 배지(`AMM v2.5.0`, `FCP v2.4.0`, `VAS v1.24.0`, `ICD v1.36.0`, `Diagram v2.20.0`, `Editor v0.6.0`) 동기화 | `TASK-405` LAN 사설망 Live Bridge 접속 및 `TASK-406` 실시간 GPS/GAC 노드 관제·`60s` TTL 연동 |
| `v1.3.0` | `2026-11-16` | **`TASK-125` 40채널 블록 개편 및 채널 관리자 결함 해소 (`Implemented`)**: ① `OFFSET_ESTOP = 9` (`Base+9` `CH_EMERGENCY_CORE` `E_STOP` 직결 송출, `Base+1` 분리), ② `BW = 40` 고정 계약(`requestedBandwidth ~= 40` 시 `"DENIED"`), ③ `MSG_BLOCK_REQUEST` 선택 필드(`preferredBase`, `conflictBase`) 및 `MSG_BLOCK_ASSIGN.status` 표준 열거형(`"ASSIGNED"` \| `"REASSIGNED"` \| `"DENIED"` \| `"FAILED"`), 영속 리스 필드(`leaseState`, `reassignedFrom`, `reason`, `lastSeenMs`) 추가, ④ 4인자 블록 충돌 검사(`checkCollision(baseA, 40, baseB, 40)`) 정합 및 연관 배지(`ICD v1.35.0`, `Diagram v2.19.0`, `AMM v2.4.0`, `FCP v2.3.0`, `VAS v1.23.0`) 동기화 | `TASK-125` GCS 대역폭 검증·충돌 재할당·리스 영속화·E_STOP 채널 분리 반영 및 `TASK-404` 통합 |
| `v1.2.0` | `2026-11-16` | **`TASK-404` 다중 기체 동시 구독, 시설 비콘 수집(`CH 50003`/`50004`) 및 선택적 WebSocket Live Bridge (`modules/live_bridge_client.lua`) 규격 추가 (`Implemented` $	o$ `Approved`)**: ① 등록된 모든 편대 기체의 `Base+3`/`Base+0` 동시 개방 및 `CH 50003` (`MSG_FACILITY_BEACON`)·`CH 50004` (`MSG_MISSION_ACK`) 수신 통합, ② 로컬 브리지(`tools/gcs_live_bridge.py`, `ws://127.0.0.1:8765`)와 `WORLD_PRESET_SYNC`/`FLEET_TELEMETRY_SYNC`/`MISSION_PUSH_CMD`/`MISSION_PUSH_ACK` 양방향 중계 규격 신설, ③ `gcs_config.json` `liveBridge` 및 연관 문서(`ICD v1.34.0`, `Diagram v2.18.0`, `AMM v2.3.0`, `Editor v0.5.0`) 동기화 | `TASK-404` WebUI 미션 에디터 실시간 연동 및 원클릭 무선 미션 푸시·로드 지원 |
| `v1.1.0` | `2026-11-14` | Wave 1 전역 사양 동기화 (`Implemented` $	o$ `Approved`): `MSG_BLOCK_ASSIGN.status` 열거형(`"ASSIGNED" \| "REASSIGNED" \| "REJECTED" \| "DENIED"`) 정렬, `MSG_OPERATOR_CMD` 필드(`command` 열거형, `flightMode`, `emergencyAction`) 및 `MSG_EMERGENCY_OVERRIDE` `authKey` 마스터 ICD v1.30.0 동기화, 연관 문서 버전 갱신 | 마스터 ICD v1.30.0 및 다이어그램 v2.15.0 C2/부트스트랩 규격 일원화 |
| `v1.0.2` | 2026-11-12 | FCP-AMM 역할 분리(마스터 ICD v1.28.0) 동기화: `CH 50000` 부트스트랩(`MSG_BLOCK_REQUEST`)·`Base+0` C2(`MSG_OPERATOR_CMD`/`MSG_MISSION_CMD`)·평시 `Base+3` 5Hz 텔레메트리 송신 주체를 `AMM (Node 03)`으로 정렬(`MFD_ACRO` 시 `VAS` 직접 인계), `Base+1` `E_STOP`은 `AMM`·`FCP`를 모두 바이패스해 `VAS (Node 01)`에 직결 송출 명시, 연관 규격서 버전 동기화 (`src/0_infra/gcs/` 런타임 무변경, `Implemented` 유지) | AMM 외부 게이트웨이·C2 전담 및 FCP 순수 외루프 제어기 역할 분리 정합화 |
| `v1.0.1` | 2026-11-08 | 구버전 명칭 전면 척결 및 표준 명칭(FCP/ASA) 동기화 | 용어 무결성 확보 |
| `v1.0.0` | 2026-11-08 | GCS 채널 관리자(`CH 50000`) 및 지상 비행 지휘 콘솔 규격 제정 및 구현 완료 (`Draft` $\to$ `Implemented`) | TASK-107 GCS 구현 완료 및 25개 단위/E2E 테스트 통과 |

---

## 1. 프로그램 개요 및 시스템 위상 (Overview & Role)

**GCS (Ground Control Station & RF Channel Manager / Node 08)**는 UAFS 항공 생태계의 중앙 지상 관제 인프라로서, 기체들의 전역 40채널 블록($N = 1 \sim 1000$, 대역 $10000 \sim 49999$) 동적 배정 및 스티키 영속화를 총괄하는 **채널 관리자(Channel Manager)**와, 지상 관제사가 실시간 텔레메트리를 감시하고 비행 지휘 및 긴급 오버라이드를 수행하는 **비행 지휘 콘솔(C2 Console)**의 두 핵심 역할을 통합 수행합니다.

### 1.1 핵심 기능 요약
1. **RF 채널 부트스트랩 게이트웨이 (`CH 50000`)**:
   - 신규/재부팅 기체 `AMM (Node 03)`이 송출하는 `MSG_BLOCK_REQUEST` (`BW = 40` 고정 계약, 선택 `preferredBase`·`conflictBase`)를 수신.
   - `channel_registry.json`에 기반하여 기체 고유 식별자(`domainId`, `hardwareUuid`)에 고유 번호($N$), 영속 리스 상태(`leaseState`, `lastSeenMs`)를 매핑하고, 4인자 블록 충돌 검사(`checkCollision(baseA, 40, baseB, 40)`)를 수행.
   - 산출 공식 $Base = 10000 + (N - 1) \times 40$에 따른 40개 채널 블록을 `MSG_BLOCK_ASSIGN` (`"ASSIGNED"`/`"REASSIGNED"`/`"DENIED"`/`"FAILED"`)으로 회신 (`requestedBandwidth ~= 40` 시 `"DENIED"`).
2. **원격 비행 지휘 및 오버라이드 (Remote C2 Override)**:
   - 선택된 기체의 `Base + 0`(`CH_OPERATOR_C2`) 포트로 `GCS_OVERRIDE` 권한의 `MSG_OPERATOR_CMD`(`ARM`, `TAKEOFF`, `HOLD`, `RTH`, `LAND`, `WAYPOINT`) 및 `MSG_MISSION_CMD`를 기체 `AMM (Node 03)`에 인가.
   - 조종석 MFD(`PILOT_PRIMARY`)보다 상위 관제 우선권으로 중재.
3. **직결 하드 비상차단 (`E_STOP`, `OFFSET_ESTOP = 9`)**:
   - `AMM (Node 03)` 및 외루프 `FCP (Node 04)`를 경유하지 않고 온보드 비행 제어 코어 `VAS (Node 01)`의 **`Base + 9` (`CH_EMERGENCY_CORE`, `OFFSET_ESTOP = 9`)**로 `MSG_EMERGENCY_OVERRIDE`(`E_STOP`)를 직결 송출하여 추진기를 즉각 셧다운 (`Base + 1` 유도 채널과 분리).
4. **다중 기체 텔레메트리 모니터링 및 시설 비콘 수집**:
   - 등록된 모든 편대 기체의 `Base + 3`(`CH_MFD_STATE`, 구 `CH_MFD_INSTRUMENT` `[DEPRECATED]`) 및 `Base + 0`(`CH_OPERATOR_C2` / `MSG_MISSION_ACK`) 채널을 동시 개방하여(평시 `AMM (Node 03)` 5Hz 송출, `MFD_ACRO` 진입 시 `VAS (Node 01)` 20Hz 직결 인계) 자세 각도, Y고도, 대지속도, 승강률, 연료, FSM 상태를 실시간 캐싱.
   - `CH 50003` (`MSG_FACILITY_BEACON`), `CH 50004` (`MSG_MISSION_ACK`) 및 `CH 60003` (`MSG_GPS_NODE_HEARTBEAT`)을 상시 청취하여 섹터 시설·GAC·GPS 노드 스냅샷과 원격 미션 응답을 수집.
   - `[TAB]` 핫키를 통해 등록된 편대 기체 간 관제 타겟을 실시간 전환.
5. **51x19 분할 TUI 콘솔**:
   - CC:Tweaked Advanced Computer 표준 해상도(51x19)에 맞추어 좌측 25열 계기 HUD, 우측 26열 기체 목록 및 채널 현황, 하단 3행 명령 바 렌더링.
6. **선택적 WebSocket 실시간 브리지 (Optional Live Bridge, `TASK-404` / `405` / `406`)**:
   - `gcs_config.json`의 `liveBridge.enabled == true`일 때 `http.websocket`으로 로컬/LAN Python 브리지(`ws://127.0.0.1:8765`, `--lan` 시 `0.0.0.0` 바인딩)에 비블로킹 연결하여 `WORLD_PRESET_SYNC`(`gacNode` 포함), `GPS_NODES_SYNC`, `FLEET_TELEMETRY_SYNC`, `MISSION_PUSH_CMD` / `MISSION_PUSH_ACK` 양방향 중계를 수행 (`enabled == false` 또는 브리지 부재 시 헤드리스/TUI 단독 모드로 무중단 동작).

---

## 2. 채널 부트스트랩 프로토콜 사양 (CH 50000, Interface I-8)

### 2.1 블록 배정 요청 (`MSG_BLOCK_REQUEST`)
```lua
{
    ver = "1.9.5",
    domainId = "AIRCRAFT_01",
    seq = 1,
    type = "MSG_BLOCK_REQUEST",
    time = 1729845000000,
    payload = {
        domainId = "AIRCRAFT_01",
        hardwareUuid = "BOX-CRAFT-4402",
        requestedBandwidth = 40,       -- 40 고정 계약 (~= 40 시 DENIED 반환)
        preferredBase = 10000,         -- 선택: AMM 로컬 channel_lease.json 캐시 재검증용
        conflictBase = nil             -- 선택: ARP 프로브 충돌 회피 요청 시 충돌 베이스 채널
    }
}
```

### 2.2 블록 배정 응답 (`MSG_BLOCK_ASSIGN`)
```lua
{
    ver = "1.9.5",
    domainId = "AIRCRAFT_01",
    seq = 1,
    type = "MSG_BLOCK_ASSIGN",
    time = 1729845000040,
    payload = {
        blockId = 1,
        baseChannel = 10000,
        bandwidth = 40,
        status = "ASSIGNED",           -- "ASSIGNED" | "REASSIGNED" | "DENIED" | "FAILED"
        channelRange = { start = 10000, end = 10039 },
        leaseState = "ACTIVE",         -- 선택: "ACTIVE" | "OFFLINE_CONFIRMED"
        reassignedFrom = nil,          -- 선택: "REASSIGNED" 시 직전 충돌/교체 베이스 채널
        reason = nil                   -- 선택: 재할당 또는 거부/실패 사유 코드
    }
}
```

---

## 3. 원격 C2 지휘 및 비상 직결 인터페이스 (Interface I-6, I-2)

### 3.1 원격 C2 오버라이드 (`MSG_OPERATOR_CMD`, Base + 0)
- **발신 채널**: 관제 대상 기체의 `Base + 0`
- **수신자**: 기체 온보드 `AMM` (Node 03, `c2_arbiter` 중재 후 `Base + 4`로 `FCP` 하달)
- **페이로드 구조**:
  - `targetCraft`: 대상 기체 `domainId` (선택)
  - `authority`: `"GCS_OVERRIDE"` 고정
  - `command`: `"ARM"` | `"DISARM"` | `"TAKEOFF"` | `"CRUISE"` | `"LOITER"` | `"POI_HOLD"` | `"LANDING"` | `"DOCKING"`
  - `flightMode`: 목표 비행 모드 문자열 (예: `"AUTO_NAV"`, `"CRUISE_HOLD"`)
  - `params`: 세부 매개변수 (목표 고도, 속도, 좌표 등)
  - `emergencyAction`: `"NONE"` | `"HOVER_HOLD"` | `"EMERGENCY_LAND"` | `"RTH"`

### 3.2 하드 비상차단 직결 지령 (`MSG_EMERGENCY_OVERRIDE`, Base + 9 / `OFFSET_ESTOP = 9`)
- **발신 채널**: 관제 대상 기체의 **`Base + 9` (`CH_EMERGENCY_CORE`, `OFFSET_ESTOP = 9`, 구 `Base + 1` `[DEPRECATED]`)**
- **수신자**: 기체 온보드 `VAS` (Node 01) 직결 (`AMM` 및 `FCP` 바이패스)
- **페이로드 구조**:
  - `source`: `"GCS"`
  - `action`: `"E_STOP"`
  - `reason`: 사유 문자열 (예: `"OPERATOR_HARD_STOP"`)
  - `authKey`: `"ESTOP_CONFIRM_KEY"` (인증 토큰)

---

## 4. 51x19 분할 TUI 콘솔 레이아웃

```
+-------------------------+--------------------------+
| GCS CH50000 | CRAFTS: 3 | TARGET: AIRCRAFT_01      | Row 1
+-------------------------+--------------------------+
| [ACTIVE CRAFT HUD]      | [REGISTERED FLEET]       | Row 2
| Domain: AIRCRAFT_01     | #01 AIRCRAFT_01 [10000]  | Row 3
| FSM   : CRUISE          | #02 AIRCRAFT_02 [10040]  | Row 4
| Pitch :   +2.5 deg      | #03 DRONE_01    [10080]  | Row 5
| Roll  :   -0.0 deg      |                          | ...
| Yaw   :  180.0 deg      |                          |
| Alt Y :  125.4 m        |                          |
| VSpd  :   +0.0 m/s      |                          |
| GSpd  :   16.2 m/s      |                          |
| Fuel  : [||||||||--] 82%|                          |
| TCA/ASA: OK / OK        |                          | Row 16
+-------------------------+--------------------------+
| Status: ALL SYSTEMS NOMINAL                        | Row 17
| C2: [A]rm [T]akeoff [H]old [R]th [L]and [X]E-Stop  | Row 18
| Nav: [Tab]NextCraft [C]hannelReg [Q]uit            | Row 19
+----------------------------------------------------+
```

---

## 5. 설정 및 레지스트리 스키마

### 5.1 `gcs_config.json`
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

### 5.2 `channel_registry.json`
```json
{
  "version": "1.0.0",
  "updatedAt": "2026-11-08",
  "allocations": {
    "AIRCRAFT_01": {
      "blockId": 1,
      "baseChannel": 10000,
      "hardwareUuid": "BOX-CRAFT-4402",
      "bandwidth": 40,
      "leaseState": "ACTIVE",
      "lastSeenMs": 1729845000040,
      "assignedAt": 1729845000000
    }
  }
}
```

---

## 6. WebSocket 실시간 브리지 및 월드 프리셋 연동 (`TASK-404` / `405` / `406`, Optional)

- **브리지 토폴로지**: 인게임 `GCS` (`modules/live_bridge_client.lua`) $\leftrightarrow$ 호스트 PC Python RFC 6455 서버(`tools/gcs_live_bridge.py`, 기본 `127.0.0.1:8765`, LAN 원격 접속용 `--lan` 시 `0.0.0.0` 바인딩 및 LAN 안내 URL 출력) $\leftrightarrow$ 호스트 WebUI(`tools/amm_mission_editor.html`).
- **브리지 JSON 메시지 5종**:
  1. `WORLD_PRESET_SYNC` (`GCS` $\to$ 브리지 $\to$ WebUI): `CH 50003`에서 수신한 `MSG_FACILITY_BEACON`의 `sectorId`, `sectorName`, `facilities[]` 스냅샷과 `gacNode` 요약(비콘 명시 `position` 우선, 없으면 예하 `facilities[]` 좌표 무게중심) 전달.
  2. `GPS_NODES_SYNC` (`GCS` $\to$ 브리지 $\to$ WebUI): `CH 60003`에서 수신한 `MSG_GPS_NODE_HEARTBEAT` 기반 GPS 노드 목록(`nodes[]`: `nodeId`, `computerId`, `pos`, `status`, `uptime`, `reportsSent`, `lastSeenMs`, `isStale`) 송출. `60,000ms` 무신호 시 자동 삭제 없이 `isStale = true`, `status = "OFFLINE"`으로 표기하며 `purge_offline_gps_nodes()`로 수동 정리 가능.
  3. `FLEET_TELEMETRY_SYNC` (`GCS` $\to$ 브리지 $\to$ WebUI): 등록된 편대 전체 기체 목록(`crafts[]`: `domainId`, `baseChannel`, `airframeType`, `position`, `attitude`, `groundSpeed`, `fuel`, `fsmState`, `isStale`)을 주기적으로 송출.
  4. `MISSION_PUSH_CMD` (WebUI $\to$ 브리지 $\to$ `GCS`): `{ requestId, targetCraft, baseChannel, action: "LOAD" | "RUN", missionData, saveToDisk }`. `GCS`는 이를 대상 기체 `Base + 0` (`CH_OPERATOR_C2`) `MSG_MISSION_CMD` 패킷으로 변환 송출.
  5. `MISSION_PUSH_ACK` (`GCS` $\to$ 브리지 $\to$ WebUI): 대상 기체 `AMM`이 `Base + 0` 또는 `CH 50004`로 회신한 `MSG_MISSION_ACK`를 `{ requestId, targetCraft, action, status, reason, missionId, missionState }` 형태로 중계.
