# Unified Installer — 통합 코드베이스 설치 프로그램 및 배포 가이드 플레이북

> **대상 코드베이스**: `/installer.lua`, `src/0_development/installer/`, `tools/sync_gdrive.py`  
> **관련 사양서**: [INSTALLER_PROGRAM_SPECIFICATION.md](../../docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`Unified Installer`는 `Create_Aeroneutics`의 모든 모듈(15개 설치 타겟, 6개 카테고리)을 단일 진입점(`/installer.lua`)에서 설치·업데이트·제거하는 부트스트랩 및 패키지 관리자입니다.

- **단일 부트스트랩 SSOT (`/installer.lua`)**: 로컬 소스, 직접 업로드, 플로피 디스크, 원격 `wget run` 3가지 실행 환경을 자동 판별해 필요한 최소 부트스트랩 파일만 캐시한 뒤 본체(`installer_app.lua`)를 실행합니다.
- **원자적 스테이징 다운로드 & 설정 딥머지 마이그레이션**: 모든 파일을 임시 스테이징에 내려받은 뒤 검증에 성공해야만 라이브 루트를 갱신하며, 기존 JSON 설정의 사용자 커스텀 키는 보존한 채 신규 스키마 키만 병합(`migration_engine.lua`)합니다.
- **GitHub Raw / Google Drive 이중 소스 & 다중 부트 훅**: GitHub 접속 제한 시 Google Drive 공식 폴더(HTML 확인 페이지 자동 우회)로 전환할 수 있으며, 설치된 모듈별 `/startup/00_<id>.lua` 다중 부트 훅과 `/.version.json` 고아 파일 정리를 수행합니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 구분 | 품목 / 조건 | 필수 여부 | 비고 |
| :--- | :--- | :---: | :--- |
| 컴퓨터 | Computer 또는 Advanced Computer | 필수 | TUI 컬러 표시는 Advanced Computer 권장 (`51×19`) |
| 네트워크 | CC:Tweaked `http` API 활성화 | 필수 | 서버 `computercraft-server.toml`에서 `http.enabled = true` 필요 |
| 매체(선택) | Disk Drive + Floppy Disk | 선택 | 오프라인/반복 배포용 `/disk/installer.lua` 구성 시 |

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. 인스톨러 자체는 전용 물리 모뎀이나 센서를 요구하지 않으며, 설치 대상이 될 **각 컴퓨터의 터미널에서 직접 실행**합니다.
2. 여러 기체/지상 노드를 연속으로 셋업할 때는 Disk Drive를 작업대에 두고 `/disk/installer.lua`를 구운 Floppy Disk를 들고 다니며 각 컴퓨터 옆에 임시 부착해 실행하는 방식이 효율적입니다.
3. 설치 전 대상 컴퓨터 루트의 여유 디스크 용량이 충분한지 확인합니다(기본 CC 컴퓨터 `1MB`로 전 단일 모듈 설치에 충분).

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

`Unified Installer`는 RF 모뎀 채널을 사용하지 않고 CC:Tweaked `http` API를 통해 외부 원격 저장소에서 소스를 수신합니다.

- **GitHub 소스 기본 경로**: `https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/`
- **Google Drive 소스 기본 경로**: `https://drive.usercontent.google.com/download?id=<FILE_ID>&export=download&confirm=t`
- **Google Drive HTML 인터스티셜 자동 우회**: 대용량/반복 다운로드 시 Google Drive가 반환하는 확인 HTML 페이지에서 `confirm` 및 `uuid` 토큰을 파싱해 자동 재요청(1회)합니다.
- **설치 직후 채널 초기화**: 각 모듈 설치 시 `manifest.lua`의 `defaultConfigs`에 정의된 기본 채널 설정(`/config/system.json`, `/config.json`, `/gac/config.json`, `/config/fcp_config.json`, `/config/amm_config.json`, `/config/gcs_config.json` 등)이 자동 생성됩니다.

---

## 5. 소프트웨어 설치 방법 (Installation)

인게임 CC:Tweaked 컴퓨터에서 아래 3가지 경로 중 하나로 실행할 수 있습니다:

### 경로 1: 원격 다운로드 즉시 실행 (`wget run`)
```text
wget run https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/installer.lua
```

### 경로 2: 화면 직접 드래그 앤 드롭 업로드 (`/installer.lua`)
1. 호스트 저장소 루트의 `installer.lua` 파일을 열린 CC:Tweaked 컴퓨터 터미널 창으로 드래그 앤 드롭합니다.
2. 터미널에서 `installer.lua`를 실행합니다.

### 경로 3: 플로피 디스크 배포 (`/disk/installer.lua`)
1. 플로피 디스크 루트에 `installer.lua`를 복사합니다(`cp /installer.lua /disk/installer.lua`).
2. 대상 컴퓨터에 드라이브를 연결하고 `/disk/installer.lua`를 실행하면 대상 컴퓨터의 `/` 루트에 모듈이 설치됩니다.

### (호스트 개발자용) Google Drive 배포 동기화 CLI (`tools/sync_gdrive.py`)
```powershell
python tools/sync_gdrive.py stage
python tools/sync_gdrive.py sync --dry-run
python tools/sync_gdrive.py verify
```
- `config/gdrive_mapping.json`을 SSOT로 삼아 `dist_gdrive/`에 스테이징하고 `gdrive` CLI로 공식 폴더를 동기화합니다. 상세 절차는 [GDRIVE_DEPLOYMENT_GUIDE.md](../../docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md)를 참고하세요.

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

인스톨러는 별도 사용자 설정 파일 없이 아래 메타데이터와 매니페스트를 참조합니다:

| 파일 경로 | 위치 | 역할 |
| :--- | :--- | :--- |
| `/.version.json` | 대상 CC 컴퓨터 | 설치된 모듈 목록, 버전, 소유 파일 목록, 소스(`github`/`gdrive`) 기록 및 고아 파일 정리 기준 |
| `/startup/00_<moduleId>.lua` | 대상 CC 컴퓨터 | 다중 부트 호환 자동 시작 훅(`startup.enabled == true` 모듈 대상) |
| `/lib/avionics_sensors.lua` | 대상 CC 컴퓨터 | 온보드·인프라 모듈 설치 시 함께 주입되는 CC:Avionics 공용 센서 라이브러리 |
| `/lib/ota_agent.lua` | 대상 CC 컴퓨터 | `vas`, `tca`, `fcp`, `amm`, `ota` 설치 시 함께 주입되는 무선 OTA 슬레이브 에이전트 |

- **매니페스트 등록 모듈 ID (`manifest.MODULE_ORDER`, 15종)**:
  - `0_development`: `alignment`, `fdr`, `installer`*(부트스트랩 코어)*, `ota`, `sensors`
  - `0_infra`: `gps_server`, `gps_node`, `gps_client`, `gac`, `gcs`, `landing_pad`, `runway`
  - `1_control`: `vas`, `tca`
  - `2_guidance`: `fcp`
  - `3_planning`: `amm`

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### 대화형 51×19 TUI 단축키

| 화면 | 키 | 동작 |
| :--- | :---: | :--- |
| 공통 | `Up` / `Down` | 카테고리 또는 모듈 선택 커서 이동 |
| 공통 | `S` | 다운로드 소스 전환 (`GitHub` ↔ `Google Drive`) |
| 공통 | `Q` | 터미널 색상 복원 후 안전 종료 |
| 카테고리 메뉴 | `Enter` / `Right` | 선택한 도메인 폴더 진입 |
| 모듈 메뉴 | `Enter` | 선택한 모듈 설치 확인(`y`/`n`) 후 설치·업데이트 실행 |
| 모듈 메뉴 | `U` | 이미 설치된 모듈 제거 확인(`y`/`n`) 후 안전 삭제 |
| 모듈 메뉴 | `Backspace` / `Left` / `B` | 카테고리 메뉴로 복귀 |

### 비대화형 CLI 실행

```text
installer.lua install <moduleId> [--source github|gdrive]
installer.lua update <moduleId> [--source github|gdrive]
installer.lua uninstall <moduleId>
```

- Google Drive 부트스트랩 매핑 오버라이드가 필요한 경우 `--bootstrap-gdrive-map <path>` 옵션을 전달할 수 있습니다.

### 자주 발생하는 문제 및 해결법

- **`FS_DISABLED` 또는 `HTTP_DISABLED` / 다운로드 실패**
  - CC:Tweaked 서버 설정에서 HTTP API가 차단되었거나 도메인 화이트리스트에 `raw.githubusercontent.com` / `drive.usercontent.google.com`이 허용되지 않은 상태입니다. `S` 키로 소스를 전환하거나 서버 HTTP 허용 목록을 확인하세요.
- **`GDRIVE_HTML_INTERSTITIAL` 오류**
  - Google Drive 측 확인 페이지 토큰 추출이 차단된 경우입니다. GitHub 소스로 전환(`--source github`)하거나 잠시 후 재시도하세요.
- **업데이트 후 기존 설정값이 사라질까 우려될 때**
  - `migration_engine.lua`가 기존 JSON 파일의 키를 보존하고 신규 스키마 기본 키만 딥머지합니다. 단, `ota` 무선 배포에서 `--overwrite-config` 옵션을 켜면 덮어쓰기가 수행되므로 주의하세요.
