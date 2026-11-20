# AMM Mission Editor — WebUI 비주얼 미션 에디터 및 Live Bridge 플레이북

> **대상 도구**: `tools/amm_mission_editor.html`, `tools/gcs_live_bridge.py`  
> **관련 사양서**: [AMM_MISSION_EDITOR_SPECIFICATION.md](../../docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`AMM Mission Editor`는 호스트 PC 브라우저에서 별도 설치 없이 단일 HTML 파일로 실행되어 `AMM` `v2.0.0` 다중 체크포인트 미션을 시각적으로 설계·검증하고, 필요 시 `GCS Live Bridge`를 통해 인게임 기체와 실시간 양방향 연동하는 컴패니언 웹 애플리케이션입니다.

- **무설치 단일 파일 & 로컬/LAN 보안 정책**: `tools/amm_mission_editor.html`을 브라우저로 여는 것만으로 즉시 동작하며, 외부 인터넷/CDN 요청 없이 오직 사용자가 `'Connect Live'`를 누른 루프백(`127.0.0.1`/`localhost`), RFC 1918 사설 IPv4(`10.*`/`172.16-31.*`/`192.168.*`), `*.local`의 `ws://` 브리지에만 연결합니다(`TASK-404`/`405`).
- **3계층 미션 및 정적 프리플라이트 검증**: 37종 활성 `ACT_*`(및 19종 예약/로드맵 `ACT_*`), 7종 `DEC_*` 데코레이터, 5종 `MAC_*` 매크로 전개, 19종 `preconditions`, 14종 종료/중단 조건(`settleTicks`), 4종 라이프사이클 훅을 인게임 Lua 검증기와 동일한 규칙으로 실시간 검증(`validateMission()`)합니다.
- **멀티-월드 프리셋 · 광역 줌 · Live `Inspection` (`TASK-403`, `TASK-406`)**: `0.01 ~ 4.0 px/m` (`1% ~ 400%`) 광역 줌과 10단계 동적 그리드 위에서 `GAC`/`Landing Pad`/`Runway`/`GPS` 시설 자동 등록(60초 TTL `OFFLINE` 표시), 기체·시설 타입 필터링, 읽기 전용 `Inspection` 관전 및 원클릭 `Push to Aircraft`를 제공합니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 환경 | 요구 사항 | 필수 여부 | 비고 |
| :--- | :--- | :---: | :--- |
| 호스트 브라우저 | Chrome / Edge / Firefox 최신 데스크톱 브라우저 | 필수 | `file://` 직접 열기 지원, 별도 웹서버·npm 불필요 |
| Live Bridge (선택) | Python 3.10+ (`tools/gcs_live_bridge.py`) | 선택 | 외부 의존성 없는 표준 라이브러리 단독 실행 |
| 인게임 연동 (선택) | `GCS` 컴퓨터 (`liveBridge.enabled: true`) | 선택 | CC:Tweaked HTTP/WebSocket 로컬/LAN 접속 허용 필요 ([gcs.md](../0_infra/gcs.md)) |

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. **오프라인 파일 워크플로우 (기본)**:
   - 인게임 시설 배치가 끝나면 호스트에서 에디터를 열어 `World` 프리셋에 주요 착륙패드·활주로(`facilityId`, `X/Z/Y`, `headingDeg`)를 등록하거나 World JSON을 불러와 미션을 작성합니다.
   - 완성된 미션을 `Export .json`으로 내려받아 인게임 `AMM` 컴퓨터 창에 드래그 앤 드롭하거나 `/disk/missions/`에 넣습니다.
2. **실시간 Live Mode 배치 (`TASK-404` / `405` / `406`)**:
   - 인게임에서 `GPS Cluster` + `GAC` + `Landing Pad`/`Runway` + `GCS`를 모두 가동하면, `GCS`가 `CH 50003`(`MSG_FACILITY_BEACON`)과 `CH 60003`(`MSG_GPS_NODE_HEARTBEAT`)을 수집해 브리지로 자동 송출하므로 좌표를 손으로 베껴 적을 필요 없이 WebUI 지도에 시설과 기체가 실시간 배치됩니다.

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

`AMM Mission Editor` 자체는 호스트 PC 브라우저에서 실행되므로 RF 채널을 직접 점유하지 않으며, WebSocket 브리지를 통해 인게임 `GCS`와 5종의 JSON 메시지를 교환합니다:

| 방향 | 메시지 타입 | 역할 |
| :--- | :--- | :--- |
| `GCS → Bridge → WebUI` | `WORLD_PRESET_SYNC` | `GAC` 본체 좌표(또는 시설 무게중심) 및 소속 패드·활주로 자동 등록 |
| `GCS → Bridge → WebUI` | `GPS_NODES_SYNC` | `GPS` 비컨 위치·상태 동기화 (60초 무응답 시 `OFFLINE`/`STALE` 반투명 표시) |
| `GCS → Bridge → WebUI` | `FLEET_TELEMETRY_SYNC` | 등록된 모든 기체의 실시간 `(X, Y, Z)` 위치·기수각·궤적 폴리라인(`Trail`) |
| `WebUI → Bridge → GCS` | `MISSION_PUSH_CMD` | 선택 기체(`Base+0`)로 `LOAD` 또는 `RUN` 미션 JSON 및 `saveToDisk` 무선 전송 |
| `GCS → Bridge → WebUI` | `MISSION_PUSH_ACK` | 기체 `AMM`이 `CH 50004`로 회신한 수락/거부 결과를 WebUI 토스트로 표시 |

- **브리지 URL 보안 허용 규칙 (`LiveBridge.isAllowedLocalUrl`)**: `ws://127.0.0.1:<port>`, `ws://localhost:<port>`, `ws://10.x.x.x:<port>`, `ws://172.16-31.x.x:<port>`, `ws://192.168.x.x:<port>`, `ws://*.local:<port>`만 허용하며 공인 IP 및 `wss://`는 차단합니다.

---

## 5. 소프트웨어 설치 방법 (Installation)

1. **WebUI 에디터 실행**:
   - 저장소의 `tools/amm_mission_editor.html` 파일을 더블클릭하거나 브라우저 주소창으로 열어 바로 사용합니다.
2. **Live Bridge 서버 시작 (실시간 모드 사용 시)**:
   ```powershell
   # 로컬 단일 PC 환경
   python tools/gcs_live_bridge.py --port 8765

   # LAN 분리 호스트 환경 (예: 별도 마인크래프트 서버 호스트)
   python tools/gcs_live_bridge.py --port 8765 --lan
   ```
3. WebUI 상단의 Live URL 입력란(`ws://127.0.0.1:8765` 또는 `ws://<LAN_IP>:8765`)을 확인하고 **`Connect Live`** 버튼을 클릭합니다.

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

에디터는 브라우저 `localStorage`를 이용해 작업 중 상태와 프리셋을 자동 보관합니다:

| 항목 | 저장 위치 / 설명 |
| :--- | :--- |
| 브리지 접속 URL | `localStorage`에 마지막 입력한 로컬/LAN `ws://` URL 자동 기억 |
| 월드 시설 프리셋 (`WorldStore`) | 멀티-월드별 `{ facilityId, label, type, x, z, y, headingDeg, notes }` 영속화 및 JSON Export/Import 지원 |
| 미션 기본값 기준선 | `defaultAlt = 150.0`m, `defaultSpeed = 18.0`m/s, `acceptanceRadius = 15.0`m (`amm_config.json` 기준) |
| 기체 40채널 프리뷰 | `Mission Settings`에서 기체 인덱스 $N$ (`1~1000`) 지정 시 `baseChannel`과 `Zone 3` (`Base + 20..39`) 오프셋 미리보기 제공 |
| 출력 미션 스키마 | `version: "2.0.0"`, `executionMode: "SINGLE" | "REPEAT"`, `checkpoints[]` (Zero-Fallback 단일 스키마) |

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### 5영역 워크스페이스 및 핵심 작업 흐름

1. **상단 바 (`Top Header`)**: `Mission ID`, `Execution Mode`(`SINGLE`/`REPEAT`), `Undo`/`Redo`, `Presets`, `Import`/`Export .json`, `Raw JSON` 드로어, `World` 선택기, `Mission Edit` ↔ `Inspection` 모드 전환, `Connect Live`, `Push to Aircraft`.
2. **좌측 레일 (`300px`)**: `+ Add` (`ACT_*` 팔레트 팝오버), `+ Macro` (`MAC_*` 매크로 삽입 및 `Expand Now`), 체크포인트 순서 드래그/재정렬, Live 대상 필터(기체/시설 타입 `GAC`, `GPS`, `LANDING_PAD`, `RUNWAY`, `HANGAR`, `DOCKING_ARM`, `WAYPOINT` 토글 및 `Purge Offline`).
3. **중앙 2D `(X, Z)` 전술 캔버스**:
   - 마우스 휠로 `1% ~ 400%`(`0.01 ~ 4.0 px/m`) 광역 줌, 드래그 패닝, `Fit All` 전체 보기.
   - `Alt` 키 미세 드래그로 웨이포인트/접선 진입점/POI 조준점/고도 미니 프로필(`5m` 스냅) 조정.
   - **`Inspection` 모드**: 미션 편집 잠금, 기체 클릭 시 카메라 자동 추적(`Follow`), 텔레메트리/시설/GPS 상세 HUD 열람 및 `Push to Aircraft` 가능.
4. **우측 인스펙터 (`420px`)**: `[Checkpoint | Mission Settings]` 2모드 및 `Params | Guards | Conditions | Hooks` 4탭 편집. `facilityId`가 월드 프리셋에 없으면 `UNREGISTERED_FACILITY_ID` 경고와 함께 원클릭 등록 버튼 제공.
5. **하단 프리플라이트 검증 바**: `[All | Errors | Warnings]` 필터 — 오류 항목 클릭 시 해당 체크포인트와 입력 필드 탭으로 자동 포커스.

### 자주 발생하는 문제 및 해결법

- **`Connect Live` 시 `Disallowed non-local WebSocket URL` 오류가 발생함**
  - 입력한 주소가 공인 IP이거나 `wss://` 프로토콜입니다. `ws://127.0.0.1:8765` 또는 `ws://192.168.x.x:8765` 같은 사설 LAN `ws://` 주소만 사용하세요.
- **오래된 GPS 노드가 지도에 계속 흐리게 남아 있음**
  - `GCS`가 60초(`60000ms`) 이상 하트비트를 받지 못한 노드는 실수로 지워지지 않도록 반투명 `[OFFLINE]`으로 보존됩니다. 실제로 제거된 노드라면 필터 패널의 `Purge Offline`을 눌러 정리하세요.
- **`Push to Aircraft` 후 `UNKNOWN_TARGET_CRAFT` 오류가 반환됨**
  - `GCS`의 `/config/channel_registry.json`에 해당 `targetCraft`(`AIRCRAFT_01` 등)가 등록되어 있지 않은 상태입니다. 기체 `AMM`을 먼저 켜 `GCS`(`CH 50000`)와 부트스트랩 등록을 완료한 뒤 다시 푸시하세요.
- **`Export .json` 전 `DEFERRED_ACTION_UNSUPPORTED` 경고가 뜸**
  - 아직 온보드에 구현되지 않은 로드맵 `[로드맵]` 액션(예: `ACT_PAY_CARGO_DROP` 등)을 선택한 상태입니다. 현재 활성 비행이 목적이라면 `[즉시]` 실행 가능한 37종 활성 `ACT_*` 프리미티브로 교체하세요.
