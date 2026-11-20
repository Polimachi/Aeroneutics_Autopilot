# Wireless OTA — 격납고 무선 OTA 배포 서버 및 롤백 워치독 플레이북

> **대상 코드베이스**: `src/0_development/ota/` (`main.lua`, `ota_agent.lua`)  
> **관련 사양서**: [OTA_PROGRAM_SPECIFICATION.md](../../docs/specs/0_development/ota/OTA_PROGRAM_SPECIFICATION.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`Wireless OTA`는 격납고에 주기된 기체 내부의 여러 컴퓨터(`VAS`, `TCA`, `FCP`, `AMM`)에 디스크를 일일이 뽑거나 재방문하지 않고 **무선 모뎀으로 일괄 업데이트를 배포**하는 격납고 배포 서버 및 슬레이브 에이전트 체계입니다.

- **독립 완결형 슬레이브 에이전트 (`/lib/ota_agent.lua`)**: 외부 모듈 `require` 없이 IEEE 802.3 CRC32 검증을 내장해 각 기체 제어기 루프 안에서 동작합니다.
- **비행 안전 게이트(`is_safe_for_ota`)**: 기체가 공중 부양(`isAirborne == true`) 중이거나 제어 상태가 `DISARMED` / `BOOT` / `IDLE_ARMED`가 아니면(`NOT_DISARMED`) 무선 업데이트 요청을 즉시 거부(`NACK`)합니다.
- **2단계 원자적 커밋 및 부트 워치독 롤백 (`TASK-117`)**: `/.ota_staging`에 청크를 모두 수신·CRC32 검증한 뒤 기존 파일을 `/.ota_backup`으로 백업하고 새 버전을 적용합니다. 재부팅 후 `bootConfirmTicks`(기본 `20`틱 = 1초) 내 정상 부팅 확인(`confirm_boot`)에 실패하면 다음 부팅 시 자동으로 `/.ota_backup`에서 이전 버전으로 롤백합니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 구분 | 품목 / 페리페럴 | 필수 여부 | 비고 |
| :--- | :--- | :---: | :--- |
| OTA 서버 | Advanced Computer | 필수 | 51×19 `term.blit` 대시보드 및 CLI 지원 |
| 통신 | Wireless Modem 또는 Ender Modem | 필수 | 격납고 베이 내 대상 기체 전체 커버리지 확보 |
| HTTP API | CC:Tweaked `http` 활성화 | 선택 | `[S]` 원격 패키지 동기화(`sync_remote`) 사용 시 필요 |
| 기체 노드 | `/lib/ota_agent.lua` 탑재 모듈 | 필수 | `vas`, `tca`, `fcp`, `amm` 설치 시 자동 포함됨 |

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. 격납고 베이(`Alignment` 스테이션 인접 구역 또는 정비 콘솔)에 OTA 서버용 Advanced Computer를 설치하고 무선/엔더 모뎀을 장착합니다.
2. 복수 격납고 베이에서 동시 업데이트 시 채널 혼선을 막기 위해 베이마다 고유 `bayId`(`1 ~ 10`)를 부여합니다.
3. 대상 기체의 `VAS`·`TCA`·`FCP`·`AMM` 전원이 모두 켜져 있고, 기체가 격납고 바닥에 착륙해 비무장(`DISARMED` 또는 `IDLE_ARMED`) 상태인지 확인합니다.

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

`OTA`는 격납고 베이 10채널 블록(`101 ~ 200`) 중 오프셋 `+4`와 `+5`를 사용합니다(`ota_agent.get_channels`).

$$\text{Base}_{\text{hangar}} = 101 + (\text{BayID} - 1) \times 10 \quad (1 \le \text{BayID} \le 10)$$

| 오프셋 | 채널 (기본 `BayID = 1`) | 용도 |
| :---: | :---: | :--- |
| `Base_hangar + 4` | `105` (`cmdCh`) | OTA 서버 → 기체 노드 (`DISCOVER`, `BEGIN`, `CHUNK`, `COMMIT`, `ABORT`) |
| `Base_hangar + 5` | `106` (`ackCh`) | 기체 노드 → OTA 서버 (`DISCOVER_ACK`, `ACK`, `NACK`, `COMMIT_ACK`) |

- 각 제어기(`VAS`, `FCP`, `AMM`, `TCA`)는 `ota_agent.new()` 초기화 시 설정된 `bayId`(또는 `bayIds` 목록)의 명령 채널을 자동으로 개방해 대기합니다.

---

## 5. 소프트웨어 설치 방법 (Installation)

1. 격납고 OTA 서버 컴퓨터에서 통합 인스톨러를 실행합니다:
   ```text
   /installer.lua install ota
   ```
2. 설치 구조:
   - 진입점: `/ota/main.lua` (`installDir = "/ota"`, 기본 `autorun = false`이므로 필요 시 `/ota/main.lua` 수동 실행)
   - 설정 파일: `/ota/config/ota_config.json`
   - 모듈: `/ota/modules/{ota_protocol,ota_server,ota_ui}.lua`, `/lib/ota_agent.lua`
3. 원격 패키지 캐시 채우기: 서버 실행 후 `[S]` 키 또는 CLI `sync` 명령을 실행하면 `manifest.lua` 기준으로 `vas`, `tca`, `fcp`, `amm` 최신 파일을 `/ota_packages/<moduleId>/`에 내려받습니다.

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

설정 파일 경로는 `/ota/config/ota_config.json`입니다.

```json
{
  "version": "0.1.0",
  "ota": {
    "bayId": 1,
    "chunkSize": 2048,
    "ackTimeoutSec": 1.5,
    "maxRetries": 3,
    "defaultSourceDir": "/ota_packages",
    "autoSyncOnBoot": false,
    "manifestUrl": "https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/src/0_development/installer/modules/manifest.lua",
    "githubRawBase": "https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/"
  },
  "network": {
    "domainId": "HANGAR-OTA-01"
  }
}
```

| 키 | 기본값 | 설명 |
| :--- | :--- | :--- |
| `ota.bayId` | `1` | 기본 작업 대상 격납고 베이 번호 (`1 ~ 10`) |
| `ota.chunkSize` | `2048` | 무선 청크 분할 크기(바이트) |
| `ota.ackTimeoutSec` | `1.5` | 청크 ACK 대기 타임아웃(초) |
| `ota.maxRetries` | `3` | 패킷 재전송 최대 횟수 |
| `ota.defaultSourceDir` | `"/ota_packages"` | 로컬/동기화 OTA 패키지 저장 디렉토리 |
| `ota.autoSyncOnBoot` | `false` | 서버 시작 시 원격 패키지 자동 동기화 여부 |

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### 51×19 대화형 TUI 단축키

| 키 | 동작 | 설명 |
| :---: | :--- | :--- |
| `D` | 노드 탐색 (`Discover`) | 현재 선택된 베이 채널로 브로드캐스트하여 응답 기체 노드 목록 갱신 |
| `S` | 원격 동기화 (`Sync`) | GitHub에서 최신 `manifest.lua` 및 패키지 파일을 `/ota_packages`로 동기화 |
| `U` | 선택 노드 배포 (`Update`) | 목록에서 선택한 노드로 청크 전송 및 적용 실행 |
| `B` | 베이 전환 (`Bay`) | 대상 베이 번호를 `1 → 2 → ... → 10` 순환 전환 |
| `O` | 설정 덮어쓰기 토글 | `overwriteConfig` (`ON`/`OFF`) 전환 (기본 `OFF`: 기존 `/config/*.json` 보존) |
| `R` | 자동 재부팅 토글 | `autoReboot` (`ON`/`OFF`) 전환 (적용 완료 후 원격 `os.reboot` 지시) |
| `Up` / `Down` | 커서 이동 | 발견된 노드 목록에서 대상 선택 |
| `Q` | 종료 | 열려 있던 `ackCh`를 닫고 종료 |

### CLI 실행 모드

```text
/ota/main.lua discover [--bay=1]
/ota/main.lua sync [moduleId]
/ota/main.lua deploy <moduleId> <domainId> [packageDir] [--bay=1] [--overwrite-config] [--reboot]
/ota/main.lua --headless
```

### 자주 발생하는 문제 및 해결법

- **`DEPLOY FAIL: NOT_DISARMED` (`[LOCK]` 배지 표시)**
  - 대상 기체가 비행 중(`isAirborne = true`)이거나 `NORMAL`/`FAILSAFE_HOLD`/`EMERGENCY_LAND`/`E_STOP` 상태입니다. 안전하게 착륙·비무장(`DISARMED` 또는 `IDLE_ARMED`)한 후 재시도하세요.
- **업데이트 후 기체가 재부팅되더니 구버전으로 되돌아감 (자동 롤백)**
  - 새 코드에 문법 오류나 초기화 크래시가 발생해 `PENDING_BOOT` 상태에서 `confirm_boot()`(`bootConfirmTicks = 20`)가 완료되지 않아 워치독이 `/.ota_backup`에서 복원한 정상 안전 동작입니다. 로컬 테스트로 오류를 수정한 뒤 재배포하세요.
- **노드 탐색(`D`) 시 기체가 뜨지 않음**
  - 기체 측 노드가 사용하는 `bayId`와 OTA 서버 상단 `BAY:NN (CH:105/106)` 채널이 일치하는지 확인하고, 무선 모뎀 거리를 점검하세요.
