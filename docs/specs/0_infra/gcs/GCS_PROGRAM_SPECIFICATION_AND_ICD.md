# GCS (지상 관제소 및 채널 관리자) 상세 규격서
> **GCS: Ground Control Station & RF Channel Manager**  
> **프로젝트**: Universal Autonomous Flight Stack (UAFS Ecosystem)  
> **운영 환경**: Minecraft CC:Tweaked, Create: Aeronautics, Create: Avionics  

| 항목 | 내용 |
| :--- | :--- |
| **문서 상태 (Status)** | `Implemented` |
| **문서 버전 (Version)** | `v1.0.2` |
| **최종 수정일 (Date)** | `2026-11-12` |
| **구현 코드 (Source)** | `src/0_infra/gcs/` |
| **주관 도메인 (Domain)** | 지상 인프라 및 전역 무선 채널 관리 (GCS / Node 08) |

> **참조 문서**: 
> - [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md) (마스터 ICD v1.28.0)
> - [SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md](../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 구조도 v2.13.0)
> - [AMM_PROGRAM_SPECIFICATION.md](../../3_planning/amm/AMM_PROGRAM_SPECIFICATION.md) (임무 관리자 및 조종석 단말 v1.3.0)
> - [FCP_PROGRAM_SPECIFICATION.md](../../2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md) (외루프 유도 v2.0.0)
> - [VAS_PROGRAM_SPECIFICATION.md](../../1_control/vas/VAS_PROGRAM_SPECIFICATION.md) (비행 제어 코어 v1.19.0)
> - [GEMINI.md](../../../../GEMINI.md) (전역 규칙 및 가이드라인)

### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v1.0.2` | 2026-11-12 | FCP-AMM 역할 분리(마스터 ICD v1.28.0) 동기화: `CH 50000` 부트스트랩(`MSG_BLOCK_REQUEST`)·`Base+0` C2(`MSG_OPERATOR_CMD`/`MSG_MISSION_CMD`)·평시 `Base+3` 5Hz 텔레메트리 송신 주체를 `AMM (Node 03)`으로 정렬(`MFD_ACRO` 시 `VAS` 직접 인계), `Base+1` `E_STOP`은 `AMM`·`FCP`를 모두 바이패스해 `VAS (Node 01)`에 직결 송출 명시, 연관 규격서 버전 동기화 (`src/0_infra/gcs/` 런타임 무변경, `Implemented` 유지) | AMM 외부 게이트웨이·C2 전담 및 FCP 순수 외루프 제어기 역할 분리 정합화 |
| `v1.0.1` | 2026-11-08 | 구버전 명칭 전면 척결 및 표준 명칭(FCP/ASA) 동기화 | 용어 무결성 확보 |
| `v1.0.0` | 2026-11-08 | GCS 채널 관리자(`CH 50000`) 및 지상 비행 지휘 콘솔 규격 제정 및 구현 완료 (`Draft` $\to$ `Implemented`) | TASK-107 GCS 구현 완료 및 25개 단위/E2E 테스트 통과 |

---

## 1. 프로그램 개요 및 시스템 위상 (Overview & Role)

**GCS (Ground Control Station & RF Channel Manager / Node 08)**는 UAFS 항공 생태계의 중앙 지상 관제 인프라로서, 기체들의 전역 40채널 블록($N = 1 \sim 1000$, 대역 $10000 \sim 49999$) 동적 배정 및 스티키 영속화를 총괄하는 **채널 관리자(Channel Manager)**와, 지상 관제사가 실시간 텔레메트리를 감시하고 비행 지휘 및 긴급 오버라이드를 수행하는 **비행 지휘 콘솔(C2 Console)**의 두 핵심 역할을 통합 수행합니다.

### 1.1 핵심 기능 요약
1. **RF 채널 부트스트랩 게이트웨이 (`CH 50000`)**:
   - 신규 기체 `AMM (Node 03)`이 부팅 시 송출하는 `MSG_BLOCK_REQUEST`를 수신.
   - `channel_registry.json`에 기반하여 기체 고유 식별자(`domainId`, `hardwareUuid`)에 고유 번호($N$)를 스티키(Sticky) 매핑.
   - 산출 공식 $Base = 10000 + (N - 1) \times 40$에 따른 40개 채널 블록을 `MSG_BLOCK_ASSIGN`으로 회신.
2. **원격 비행 지휘 및 오버라이드 (Remote C2 Override)**:
   - 선택된 기체의 `Base + 0`(`CH_OPERATOR_C2`) 포트로 `GCS_OVERRIDE` 권한의 `MSG_OPERATOR_CMD`(`ARM`, `TAKEOFF`, `HOLD`, `RTH`, `LAND`, `WAYPOINT`) 및 `MSG_MISSION_CMD`를 기체 `AMM (Node 03)`에 인가.
   - 조종석 MFD(`PILOT_PRIMARY`)보다 상위 관제 우선권으로 중재.
3. **직결 하드 비상차단 (`E_STOP`)**:
   - `AMM (Node 03)` 및 외루프 `FCP (Node 04)`를 경유하지 않고 온보드 비행 제어 코어 `VAS (Node 01)`의 `Base + 1`(`CH_FLIGHT_GUIDANCE`)로 `MSG_EMERGENCY_OVERRIDE`(`E_STOP`)를 직결 송출하여 추진기를 즉각 셧다운.
4. **다중 기체 텔레메트리 모니터링**:
   - 활성 기체의 `Base + 3`(`CH_MFD_STATE`, 구 `CH_MFD_INSTRUMENT` `[DEPRECATED]`) 텔레메트리를 수신(평시 `AMM (Node 03)` 5Hz 송출, `MFD_ACRO` 진입 시 `VAS (Node 01)` 20Hz 직결 인계)하여 자세 각도, Y고도, 대지속도, 승강률, 연료, FSM 상태 표출.
   - `[TAB]` 핫키를 통해 등록된 편대 기체 간 관제 타겟을 실시간 전환.
5. **51x19 분할 TUI 콘솔**:
   - CC:Tweaked Advanced Computer 표준 해상도(51x19)에 맞추어 좌측 25열 계기 HUD, 우측 26열 기체 목록 및 채널 현황, 하단 3행 명령 바 렌더링.

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
        requestedBandwidth = 40
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
        status = "ASSIGNED", -- "ASSIGNED" | "DENIED"
        channelRange = { start = 10000, end = 10039 }
    }
}
```

---

## 3. 원격 C2 지휘 및 비상 직결 인터페이스 (Interface I-6, I-2)

### 3.1 원격 C2 오버라이드 (`MSG_OPERATOR_CMD`, Base + 0)
- **발신 채널**: 관제 대상 기체의 `Base + 0`
- **수신자**: 기체 온보드 `AMM` (Node 03, `c2_arbiter` 중재 후 `Base + 4`로 `FCP` 하달)
- **페이로드 구조**:
  - `targetCraft`: 대상 기체 `domainId`
  - `authority`: `"GCS_OVERRIDE"` 고정
  - `command`: `"ARM"` | `"DISARM"` | `"TAKEOFF"` | `"CRUISE"` | `"HOLD"` | `"RTH"` | `"LAND"` | `"WAYPOINT"`
  - `params`: 세부 매개변수 (목표 고도, 속도, 좌표 등)

### 3.2 하드 비상차단 직결 지령 (`MSG_EMERGENCY_OVERRIDE`, Base + 1)
- **발신 채널**: 관제 대상 기체의 `Base + 1`
- **수신자**: 기체 온보드 `VAS` (Node 01) 직결 (`AMM` 및 `FCP` 바이패스)
- **페이로드 구조**:
  - `source`: `"GCS"`
  - `action`: `"E_STOP"`
  - `reason`: 사유 문자열 (예: `"OPERATOR_HARD_STOP"`)

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
    "bandwidth": 40,
    "baseChannelMin": 10000,
    "baseChannelMax": 49960,
    "maxCraftBlocks": 1000
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
      "assignedAt": 1729845000000
    }
  }
}
```
