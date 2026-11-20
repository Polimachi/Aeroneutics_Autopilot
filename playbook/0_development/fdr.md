# FDR — 지상 블랙박스 로거 및 오프라인 비행 분석기 플레이북

> **대상 코드베이스**: `src/0_development/fdr/` (`main.lua`), `tools/analyze_flight_log.py`  
> **관련 사양서**: [FDR_PROGRAM_SPECIFICATION.md](../../docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`FDR (Ground In-Flight Aligner & Multi-Disk VFS Logger)`는 비행 중인 기체가 송출하는 RF 패킷을 송신 개입 없이(Receive-Only, `modem.transmit = 0`) 수신하여 다중 플로피 디스크 풀에 JSONL 포맷으로 기록하는 지상 블랙박스 로거입니다.

- **무간섭 패시브 스니핑**: 기체 RF 대역에 어떤 신호도 송신하지 않아 비행 제어 루프나 채널 중재에 영향을 주지 않습니다.
- **다중 디스크 VFS 자동 롤오버**: 연결된 모든 플로피 디스크 드라이브의 잔여 용량을 감시하고 `maxPartBytes`(`100,000 B`) 도달 또는 디스크 가득 참 시 다음 볼륨으로 자동 분할 전환(`storage_pool.lua`)합니다.
- **비상 자동 플러시 및 오프라인 튜닝**: `E_STOP` 패킷(`Base+9`) 감지 시 버퍼를 즉시 플러시하며, 저장된 JSONL 로그를 호스트 PC의 `tools/analyze_flight_log.py`로 분석해 `pid_tuned.json` 등 튜닝 패치를 산출할 수 있습니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 구분 | 품목 / 페리페럴 | 필수 여부 | 비고 |
| :--- | :--- | :---: | :--- |
| 컴퓨터 | Advanced Computer | 필수 | 51×19 `term.blit` 대시보드 표시 |
| 통신 | Wireless Modem 또는 Ender Modem | 필수 | 기체 비행 구역 전체 수신 가능 거리 확보 |
| 저장 장치 | Disk Drive × 1 이상 + Floppy Disk | 권장 | 다중 드라이브 유선 모뎀 연결 시 자동 풀 확장; 미연결 시 로컬 `/logs` 폴백 |

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. 지상 관제실 또는 시험 비행장 중앙에 Advanced Computer를 설치하고 상단(`modemSide: "top"` 기본) 또는 인접 면에 Ender Modem을 장착해 넓은 수신 반경을 확보합니다.
2. 장시간 시험 비행 로그를 분할 저장하려면 컴퓨터 옆에 Disk Drive 여러 대를 직접 붙이거나 유선 모뎀 + 케이블로 연결해 각각 Floppy Disk를 삽입합니다.
3. 인게임에서 디스크를 교체할 때는 컴퓨터를 끄지 않아도 `disk` / `disk_eject` 이벤트를 통해 가용 볼륨 풀을 즉시 재스캔합니다.

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

`FDR`은 대상 기체의 인덱스 $N$ (`1 ~ 1000`)에 따라 계산되는 기체 전용 40채널 블록 중 핵심 채널만 수신 전용(`modem.open`)으로 청취합니다.

$$\text{Base} = 10000 + (N - 1) \times 40$$

| 오프셋 | 채널 (기본 $N=1$) | 수집 패킷 타입 | 옵션 제어 |
| :---: | :---: | :--- | :--- |
| `Base + 1` | `10001` | `MSG_ATTITUDE_CMD` (`FCP → VAS` 자세/각속도 지령) | 상시 수신 |
| `Base + 2` | `10002` | `MSG_FLIGHT_TELEMETRY` (`VAS` 20Hz 상태·자세·고도·진단) | 상시 수신 |
| `Base + 4` | `10004` | `MSG_TRAJECTORY_SETPOINT`, `MSG_OUTER_LOOP_STATUS` | `tapOptions.trajectory` |
| `Base + 9` | `10009` | `MSG_EMERGENCY_OVERRIDE`, `MSG_EMERGENCY_ALERT` (자동 플러시 트리거) | 상시 수신 |
| `Base + 10` | `10010` | `MSG_THRUST_CMD`, `MSG_ACTUATOR_STATUS` | 상시 수신 |
| `Base + 11` | `10011` | `MSG_AERO_CMD`, `MSG_AERO_STATUS` | `tapOptions.aero` |

- `tapOptions.includeControlEvents: true` 설정 시 `MSG_CHANNEL_REBIND` / `MSG_CHANNEL_REBIND_ACK` 제어 이벤트도 함께 기록합니다.

---

## 5. 소프트웨어 설치 방법 (Installation)

1. 통합 인스톨러([installer.md](installer.md))를 통해 설치합니다:
   ```text
   /installer.lua install fdr
   ```
2. 설치 경로: `/main.lua`, `/modules/*.lua`, `/config/fdr_config.json`, 부팅 훅 `/startup/00_fdr.lua`.
3. 호스트 PC 오프라인 분석기(`tools/analyze_flight_log.py`)는 Python 3.10+ 표준 라이브러리만 사용하므로 추가 패키지 설치 없이 저장소 루트에서 실행합니다.

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

설정 파일 경로는 `/config/fdr_config.json`입니다.

```json
{
  "schemaVersion": "1.1.0",
  "aircraftIndexN": 1,
  "baseChannel": 10000,
  "domainId": "*",
  "modemSide": "top",
  "autoStartOnBoot": true,
  "recordMode": "STREAMING",
  "tapOptions": {
    "aero": true,
    "trajectory": true,
    "includeControlEvents": false
  },
  "streaming": {
    "flushIntervalFrames": 20,
    "flushIntervalSec": 1.0
  },
  "ringBuffer": { "capacity": 1500 },
  "storage": {
    "preferExternalDisk": true,
    "allowLocalFallback": true,
    "localDumpDir": "/logs",
    "diskSubDir": "fdr_logs",
    "maxPartBytes": 100000,
    "rollOverReserveBytes": 16384,
    "minFreeSpaceBytes": 16384,
    "autoPruneOldest": true,
    "maxTotalSessions": 10,
    "autoFlushOnEstop": true
  }
}
```

| 키 | 기본값 | 설명 |
| :--- | :--- | :--- |
| `aircraftIndexN` | `1` | 감시 대상 기체 번호 (`1~1000`) |
| `domainId` | `"*"` | 특정 기체 ID 필터 (`"*"`면 해당 채널의 모든 도메인 기록) |
| `recordMode` | `"STREAMING"` | 실시간 디스크 스트리밍 모드(링버퍼 백업 동시 유지) |
| `storage.maxPartBytes` | `100000` | JSONL 파트 파일 1개당 최대 크기(바이트) |
| `storage.autoFlushOnEstop` | `true` | `E_STOP` 패킷 수신 시 즉시 디스크 플러시 여부 |
| `export.mode` / `webhookUrl` | `"GDRIVE_WEBHOOK"` | `[U]` 키 입력 시 세션 로그를 HTTP 웹훅으로 업로드 |

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### 인게임 51×19 TUI 단축키

| 키 | 기능 | 설명 |
| :---: | :--- | :--- |
| `N` | 기체 인덱스 재바인딩 | 감시할 기체 번호 $N$을 동적으로 입력해 채널 전환(`switch_aircraft`) |
| `P` | 일시정지 / 재개 | `LOGGING` ↔ `PAUSED` 상태 전환 |
| `D` | 수동 플러시 / 덤프 | 스트림 즉시 플러시 또는 링버퍼 강제 저장 |
| `S` | 파트 수동 분할 | 현재 스트림을 닫고 다음 `partNNN` 파일로 즉시 롤오버 |
| `U` | 클라우드 반출 | `export` 설정을 사용해 최근 세션을 업로드 |
| `C` | 링버퍼·카운터 초기화 | 메모리 링버퍼 및 채널별 패킷 카운터 리셋 |
| `Q` | 안전 종료 | 열린 스트림 푸터 기록 후 채널을 닫고 종료 |

### 호스트 PC 오프라인 로그 분석기 사용법 (`tools/analyze_flight_log.py`)

인게임 월드 세이브의 컴퓨터/디스크 폴더에서 복사한 `.jsonl` 또는 세션 매니페스트 `.json`을 대상으로 실행합니다:

```bash
python tools/analyze_flight_log.py path/to/fdr_logs --csv out/flight.csv --emit-profile out/tuning
```

- `--window <start_ms:end_ms>`: 특정 비행 구간만 필터링 분석
- `--json <path>`: 자세 RMSE, 포화 비율(`saturationFreezeRatio`), 센서 이상 비율 전체 JSON 리포트 출력
- `--csv <path>`: 시계열 CSV(`rxMs`, `pitchDeg`, `rollDeg`, `yawDeg`, `altitudeY`, `verticalSpeed`, `saturationFreeze`) 생성
- `--emit-profile <dir>`: `pid_tuned.json`, `system_patch.json`, `fcp_patch.json`, `tuning_summary.json` 자동 생성 (`--min-samples` 기본 `100`)

### 자주 발생하는 문제 및 해결법

- **`STATE: DISK_FULL`로 전환되어 기록이 중단됨**
  - 모든 플로피 디스크 및 로컬 여유 공간이 `minFreeSpaceBytes(16,384 B)` 미만입니다. 새 빈 Floppy Disk를 삽입하면 볼륨 풀이 자동 갱신되며, 또는 오래된 로그를 정리한 뒤 `P` 또는 재실행으로 재개하세요.
- **패킷 카운터(`B+2 TELEM`)가 올라가지 않음**
  - 대상 기체의 `aircraftIndexN`($N$)과 `FDR`의 `N`이 일치하는지 확인하고(`N` 키로 변경 가능), `VAS` 컴퓨터에 무선 모뎀이 부착되어 있는지 점검하세요.
- **`analyze_flight_log.py`에서 `pid_tuned.json` 패치가 비어 있음**
  - `VAS` `/config/system.json`에서 `"telemetryDiag": true`를 켜고 비행해야 적분기 포화 진단 필드(`diag`)가 기록되며, 최소 샘플 수(`--min-samples`, 기본 100프레임) 이상의 비행 데이터가 필요합니다.
