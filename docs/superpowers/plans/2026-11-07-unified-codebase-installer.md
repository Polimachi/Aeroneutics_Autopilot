# 통합 코드베이스 설치 프로그램(Unified Codebase Installer) 구현 계획

> **에이전트 작업자 필수 지침:** 필수 서브 스킬로 `superpowers:subagent-driven-development`(권장) 또는 `superpowers:executing-plans`를 사용하여 태스크 단위로 본 계획을 구현하십시오. 각 단계의 진행 상황은 체크박스(`- [ ]`) 구문으로 추적합니다.

**목표 (Goal):** 저장소 내 전 도메인 코드베이스(VAS, TCA, FCP, Alignment, GPS Server/Node/Client)를 단일 진입점(`wget run .../installer.lua`)에서 TUI로 개별 선택 설치·업데이트·정리하고, 기존 개별 인스톨러(`gps/installer.lua` 등)를 Zero-Fallback 원칙에 따라 완전 통폐합 및 영구 폐기(Deprecate)한다.

**아키텍처 (Architecture):** 루트 `installer.lua`가 경량 부트스트래퍼로 동작하여 실행 시 GitHub Raw에서 필요한 코어 모듈을 임시 폴더(`/.installer_cache/`)에 동적 다운로드한 뒤 TUI 애플리케이션(`installer_app.lua`)을 기동한다. 설치 프로그램은 선언적 매니페스트(`manifest.lua`), HTTP 원자적 다운로더(`downloader.lua`), 설정 보존 마이그레이션 엔진(`migration_engine.lua`), 버전 추적 레지스트리(`version_registry.lua`), 멀티부트 후크 생성기(`startup_generator.lua`), 터미널 TUI(`tui_view.lua`)로 모듈화되며, 설치 완료 후 임시 캐시를 자동 정리한다.

**기술 스택 (Tech Stack):** CC:Tweaked Lua 5.2 (Cobalt 런타임 호환), CraftOS HTTP API (`http.get`), CraftOS Filesystem API (`fs`), CraftOS Term API (`term`), Python 3.12 단위 테스트 하네스 (`tools/run_unit_tests.py`).

**참조 사양서 (Spec):**
- 마스터 ICD: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`
- GPS 사양서: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`
- 런타임/도메인 규칙: `.agent/rules/cc-tweaked-runtime.md`, `.agent/rules/domain-aeronautics.md`

## 전역 제약사항 (Global Constraints)

- **런타임 호환성 (`.agent/rules/cc-tweaked-runtime.md`)**: Lua 5.3+ 전용 연산자(`//`, `&`, `|`, `~`, `<<`, `>>`), `getfenv`/`setfenv`, 호스트 OS 비활성 호출(`os.execute`, `io.popen`)을 일체 금지하며, CC:Tweaked 1.100+ Lua 5.2 Cobalt 환경과 100% 호환되도록 작성한다.
- **도메인 모드 차단 (`.agent/rules/domain-aeronautics.md`)**: Valkyrien Skies 및 CC:VS 계통 라이브러리/페리페럴을 사용하지 않는다.
- **Zero-Fallback 원칙 (`GEMINI.md`)**: 기존 `src/0_infra/gps/installer.lua` 및 `installer_core.lua`에 대한 듀얼키 폴백이나 영구 보존을 두지 않고 신규 통합 인스톨러로 완전 대체하며, 사양서 내 이전 경로는 `[DEPRECATED]` 배지로 명시한다.
- **원격 저장소 SSOT**: GitHub 기본 URL은 `https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/`을 사용하며, 브랜치/레포지토리 오버라이드 환경 변수 또는 전역 플래그를 지원한다.
- **안전한 데이터 보존**: 재설치나 업데이트 시 사용자의 기존 커스텀 설정(`config.json`, `node_cfg.json`, `nodes.json` 등)을 절대 유실하지 않고 깊은 병합(Deep Merge) 방식으로 결번 키만 보충한다.
- **품질 및 표현 규칙 (`AGENTS.md`)**: `no-overclaim` 원칙에 따라 검증되지 않은 수식어를 배제하고, 작성된 모듈은 `tests/installer/` 단위 테스트와 `tools/run_unit_tests.py`를 통해 100% 검증 통과를 입증한다.

## 집중 검토 항목 (Review Focus)

1. **HTTP 비활성화 환경 또는 네트워크 일시 단절 (`http == nil` 또는 `http.get` 실패)**: CC:Tweaked 서버 설정에서 `http_enable = false`이거나 다운로드 중 패킷 유실 시, 프로그램이 에러로 크래시되지 않고 친절한 진단 메시지를 표출하며 안전 종료되어야 한다. (Task 3에서 검증)
2. **다운로드 중단 시 불완전 파일 잔존 방지 (원자적 쓰기)**: 파일을 다운로드할 때 대상 경로에 직접 쓰지 않고 임시 파일(`.tmp`)로 기록한 뒤 온전성 검증 후 `fs.move`로 원자적 치환해야 한다. (Task 3에서 검증)
3. **기존 사용자 startup.lua 보존 및 멀티부트 공존**: 사용자가 이미 작성한 `/startup.lua`나 타 프로그램의 startup 스크립트를 덮어쓰지 않고, CC:Tweaked 표준 멀티부트 디렉토리인 `/startup/` 산하에 독립 파일(`/startup/00_<mod>.lua`)로 등록해야 한다. (Task 2에서 검증)
4. **구버전 잔여 파일 고아화 방지 (Clean Upgrade)**: 모듈 업데이트 시 이전 버전에 존재했으나 새 버전에서 제거/이동된 파일이 남아있을 경우 `version_registry.lua`의 이전 설치 파일 목록과 대조하여 불필요한 고아 파일을 자동 정리해야 한다. (Task 1 & Task 4에서 검증)
5. **표준(흑백) 컴퓨터와 고급(컬러) 컴퓨터 TUI 적응**: `term.isColor()`를 판별하여 컬러 모니터에서는 강조 색상을 적용하고, 흑백 모니터에서는 반전(`colors.white`/`colors.black`) 및 텍스트 마커(`[*]`, `[ ]`)로 명확히 렌더링해야 한다. (Task 4에서 검증)

---

## 파일 구조 (File Structure)

- `installer.lua` — 루트에 위치한 경량 부트스트래퍼 (`wget run .../installer.lua` 진입점, GitHub Raw에서 `src/installer/` 모듈을 임시 폴더에 받아 실행 후 정리).
- `src/installer/installer_app.lua` — 통합 인스톨러 메인 애플리케이션 진입점 및 컨트롤러.
- `src/installer/modules/manifest.lua` — 7대 설치 모듈(VAS, TCA, FCP, Alignment, GPS Server, GPS Node, GPS Client)의 메타데이터, 파일 목록, startup 후크 경로, 기본 설정 선언부.
- `src/installer/modules/downloader.lua` — HTTP 비동기/동기 다운로드 유틸리티, 재시도, 원자적 쓰기(`.tmp` -> `fs.move`), 진행률 표시기.
- `src/installer/modules/migration_engine.lua` — 기존 JSON 설정 보존 및 신규 기본값 깊은 병합(Deep Merge) 엔진 (구 `installer_core.lua` 흡수 확장).
- `src/installer/modules/version_registry.lua` — `/.aeroneutics_version.json` 메타데이터 관리, 설치 이력 기록 및 잔여 파일 정리(Clean) 추적.
- `src/installer/modules/startup_generator.lua` — `/startup/` 디렉터리 기반 안전한 런타임 부트 후크 생성기.
- `src/installer/modules/tui_view.lua` — CC:Tweaked 터미널 TUI (메뉴 렌더링, 키 입력 처리, 진행률 바, 컬러/흑백 적응).
- `tests/installer/test_manifest_and_registry.lua` — 매니페스트 유효성 및 버전 레지스트리 단위 테스트.
- `tests/installer/test_migration_and_startup.lua` — 설정 마이그레이션 및 startup 후크 생성 단위 테스트.
- `tests/installer/test_downloader.lua` — Mock HTTP 기반 원자적 다운로드 및 에러 핸들링 단위 테스트.
- `tests/installer/test_tui_view.lua` — Mock Term 기반 TUI 렌더링 단위 테스트.
- `tests/installer/test_bootstrapper.lua` — 루트 부트스트래퍼 로직 단위 테스트.

---

### Task 1: 선언적 매니페스트 및 버전 레지스트리 모듈 구축

**파일 목록:**
- 생성: `src/installer/modules/manifest.lua`
- 생성: `src/installer/modules/version_registry.lua`
- 생성: `tests/installer/test_manifest_and_registry.lua`

**인터페이스 명세:**
- `manifest.lua`:
  - `manifest.BASE_URL`: 기본 원격 Git 저장소 Raw URL (`https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/`)
  - `manifest.MODULES`: 모듈 딕셔너리
    - `id`: `"vas"`, `"tca"`, `"fcp"`, `"alignment"`, `"gps_server"`, `"gps_node"`, `"gps_client"`
    - `name`: 화면 표출용 명칭
    - `category`: `"FLIGHT_CONTROL"`, `"GUIDANCE"`, `"INFRA"` 등
    - `installDir`: 설치 대상 로컬 디렉터리 (예: `"/vas"`, `"/tca"`, `"/gps"`, `"/apis"`)
    - `files`: 상대 소스 경로 및 로컬 저장 경로 매핑 배열
    - `startup`: `{ enabled = true, path = "/startup/00_vas.lua", target = "/vas/main.lua", name = "VAS" }` (클라이언트는 disabled)
    - `defaultConfigs`: 보존 대상 기본 설정 파일 및 기본 템플릿 테이블
  - `manifest.getModule(id)`: 모듈 정의 반환
  - `manifest.listModules()`: 전체 모듈 목록 반환
- `version_registry.lua`:
  - `version_registry.load(metaPath)`: `/.aeroneutics_version.json` 로드 (없으면 기본 빈 테이블)
  - `version_registry.save(metaPath, meta)`: 원자적 JSON 저장
  - `version_registry.recordInstall(meta, moduleId, version, fileList)`: 특정 모듈 설치 기록 추가/갱신
  - `version_registry.getOrphanFiles(meta, moduleId, newFileList)`: 이전 설치 파일 중 새 파일 목록에 없는 고아 파일 목록 반환
  - `version_registry.removeModule(meta, moduleId)`: 모듈 제거 기록

**실행 단계:**
- [ ] 1.1 `tests/installer/test_manifest_and_registry.lua` 실패 테스트 작성 (매니페스트 7개 모듈 무결성 검증, 버전 레지스트리 저장/로드/고아 파일 계산 검증).
- [ ] 1.2 `src/installer/modules/manifest.lua` 구현 (모듈별 파일 목록, 대상 디렉터리, startup 정보 선언).
- [ ] 1.3 `src/installer/modules/version_registry.lua` 구현 (메타데이터 JSON I/O 및 고아 파일 추출 알고리즘).
- [ ] 1.4 `python tools/run_unit_tests.py --target installer` 실행 및 PASS 확인.

---

### Task 2: 설정 보존 마이그레이션 엔진 및 멀티부트 생성기 구축

**파일 목록:**
- 생성: `src/installer/modules/migration_engine.lua`
- 생성: `src/installer/modules/startup_generator.lua`
- 생성: `tests/installer/test_migration_and_startup.lua`

**인터페이스 명세:**
- `migration_engine.lua`:
  - `migration_engine.deepMerge(existingConfig, defaultConfig)`: 기존 사용자 커스텀 값을 그대로 유지하면서, 새 버전에 추가된 기본값 필드만 안전하게 보충.
  - `migration_engine.migrateFile(filePath, defaultConfig)`: 파일이 존재하면 읽어서 deepMerge 후 저장, 파일이 없으면 defaultConfig를 원자적으로 기록.
- `startup_generator.lua`:
  - `startup_generator.generateHookContent(moduleName, targetScriptPath)`: `/startup/`에 배치할 안전한 실행 후크 스크립트 문자열 반환 (`fs.exists` 검사 및 `shell.run` 감싸기).
  - `startup_generator.installHook(hookPath, moduleName, targetScriptPath)`: `/startup` 디렉터리를 생성하고 후크 파일을 원자적으로 기록.
  - `startup_generator.removeHook(hookPath)`: 모듈 제거 시 후크 파일 삭제.

**실행 단계:**
- [ ] 2.1 `tests/installer/test_migration_and_startup.lua` 실패 테스트 작성 (중첩 테이블 deepMerge 불변성 검증, 결번 키 보충 검증, startup 후크 생성/삭제 검증).
- [ ] 2.2 `src/installer/modules/migration_engine.lua` 구현 (`src/0_infra/gps/modules/installer_core.lua`의 마이그레이션 로직을 일반화하여 이식).
- [ ] 2.3 `src/installer/modules/startup_generator.lua` 구현 (표준 `/startup/` 멀티부트 규칙 준수).
- [ ] 2.4 `python tools/run_unit_tests.py --target installer` 실행 및 PASS 확인.

---

### Task 3: HTTP 원자적 다운로더 및 파일 시스템 유틸리티 구축

**파일 목록:**
- 생성: `src/installer/modules/downloader.lua`
- 생성: `tests/installer/test_downloader.lua`

**인터페이스 명세:**
- `downloader.lua`:
  - `downloader.checkHttpAvailable()`: `http` API 존재 및 활성화 여부 점검 (`boolean, errString`).
  - `downloader.fetchString(url, timeoutSec)`: HTTP GET을 통해 원격 텍스트 내용 가져오기 (`string, errString`).
  - `downloader.downloadFileAtomic(url, destPath, onProgress)`:
    - 원격 URL에서 내용 수신
    - 목적지 상위 디렉터리 자동 생성 (`fs.makeDir`)
    - 임시 파일(`destPath .. ".tmp"`)에 원자적 기록
    - 완료 시 `fs.delete(destPath)` 및 `fs.move(tmpPath, destPath)` 수행
    - 실패 시 임시 파일 정리 및 명확한 오류 반환
  - `downloader.downloadBatch(baseUrl, fileMap, onProgress)`: 파일 맵(`{ remoteRel = localDest }`) 순차 다운로드 및 진행 콜백 호출 (`cur, total, path`).

**실행 단계:**
- [ ] 3.1 `tests/installer/test_downloader.lua` 실패 테스트 작성 (`mock.http`를 활용한 성공 다운로드, 원자적 치환 검증, 404/네트워크 실패 시 롤백 및 임시 파일 정리 검증).
- [ ] 3.2 `src/installer/modules/downloader.lua` 구현 (재시도 로직, `.tmp` 원자적 쓰기, 에러 격리).
- [ ] 3.3 `python tools/run_unit_tests.py --target installer` 실행 및 PASS 확인.

---

### Task 4: 터미널 TUI 뷰 및 메인 인스톨러 컨트롤러 구축

**파일 목록:**
- 생성: `src/installer/modules/tui_view.lua`
- 생성: `src/installer/installer_app.lua`
- 생성: `tests/installer/test_tui_view.lua`

**인터페이스 명세:**
- `tui_view.lua`:
  - `tui_view.renderHeader(title, subtitle)`: 상단 배너 출력 (`term.isColor()` 분기 처리).
  - `tui_view.renderMenu(items, selectedIndex)`: 단일 모듈 목록 표출 및 화살표/숫자 키 선택 렌더링.
  - `tui_view.renderProgress(cur, total, currentFile)`: 진행률 바(`[=====>    ] 50%`) 표출.
  - `tui_view.renderMessage(level, msg)`: `INFO`, `SUCCESS`, `WARN`, `ERROR` 메시지 박스 표출.
  - `tui_view.promptConfirm(promptText)`: `(y/n)` 확인 입력 수신.
- `installer_app.lua`:
  - `installer_app.run(options)`:
    - 매니페스트 및 설치 메타데이터 로드
    - TUI 메인 루프 기동
    - 사용자의 모듈 선택(1~7) 처리
    - 대상 모듈 다운로드, 설정 마이그레이션, startup 후크 등록, 버전 메타 기록
    - 구버전 고아 파일 자동 정리(Clean) 수행
    - 설치 결과 안내 및 재부팅 권고

**실행 단계:**
- [ ] 4.1 `tests/installer/test_tui_view.lua` 실패 테스트 작성 (터미널 렌더링 줄 수, 색상 분기, 진행률 출력 검증).
- [ ] 4.2 `src/installer/modules/tui_view.lua` 구현.
- [ ] 4.3 `src/installer/installer_app.lua` 구현 (모듈 설치/업데이트/정리 파이프라인 조율).
- [ ] 4.4 `python tools/run_unit_tests.py --target installer` 실행 및 PASS 확인.

---

### Task 5: 루트 동적 부트스트래퍼 (`installer.lua`) 구축

**파일 목록:**
- 생성: `installer.lua` (저장소 루트)
- 생성: `tests/installer/test_bootstrapper.lua`

**인터페이스 명세:**
- `installer.lua`:
  - `wget run https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/installer.lua`로 실행되는 단일 진입점.
  - 동작 순서:
    1. `http` API 활성화 여부 사전 점검 (미활성화 시 에러 표출 후 중단).
    2. 로컬 개발 환경 여부 감지 (이미 `src/installer/installer_app.lua`가 존재하면 로컬 모듈 직접 로드).
    3. 원격 환경인 경우:
       - 임시 캐시 디렉터리 `/.installer_cache/` 생성.
       - 필수 부트스트랩 모듈(`manifest.lua`, `downloader.lua`, `migration_engine.lua`, `version_registry.lua`, `startup_generator.lua`, `tui_view.lua`, `installer_app.lua`)을 GitHub Raw에서 임시 캐시로 다운로드.
       - `package.path`에 임시 캐시 경로 등록 후 `installer_app.run()` 실행.
       - 인스톨러 종료 시 임시 캐시 `/.installer_cache/` 완전 삭제 (잔여물 무오염 보장).

**실행 단계:**
- [ ] 5.1 `tests/installer/test_bootstrapper.lua` 실패 테스트 작성 (부트스트랩 캐시 생성, 모듈 로드, 임시 캐시 안전 삭제 검증).
- [ ] 5.2 `installer.lua` 루트 스크립트 작성.
- [ ] 5.3 `python tools/run_unit_tests.py --target installer` 실행 및 PASS 확인.

---

### Task 6: 구버전 개별 인스톨러 완전 폐기(Zero-Fallback) 및 사양서 동기화

**파일 목록:**
- 삭제: `src/0_infra/gps/installer.lua`
- 삭제: `src/0_infra/gps/modules/installer_core.lua`
- 수정: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (제9절 인스톨러 규격을 통합 `installer.lua`로 개정 및 레거시 파일 [DEPRECATED] 처리)

**실행 단계:**
- [ ] 6.1 `src/0_infra/gps/installer.lua` 및 `src/0_infra/gps/modules/installer_core.lua` 파일 삭제 (Zero-Fallback 원칙 준수).
- [ ] 6.2 `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`의 제9절 인스톨러 규정 개정:
  - 구버전 플로피 디스크 배포 방식은 `[DEPRECATED]` 배지 부여.
  - 통합 원격 인스톨러(`wget run .../installer.lua`) 규격을 공식 설치 절차로 등록.
- [ ] 6.3 `python scratch/verify_all_specs.py` 실행하여 사양서 무결성 스캔(0 Errors, 0 Warnings) 확인.

---

### Task 7: 단위 테스트 하네스 전수 실행 및 회귀 검증

**파일 목록:**
- 검증 대상: `tests/installer/`, `tests/0_infra/gps/`, `tests/1_control/vas/`, `tests/1_control/tca/`, `tests/2_guidance/fcp/`, `tests/0_development/alignment/`

**실행 단계:**
- [ ] 7.1 `python tools/run_unit_tests.py --clean-orphans --require-tests` 전체 실행.
- [ ] 7.2 활성 6개 전 코드베이스(`alignment`, `gps`, `tca`, `vas`, `fcp`, `installer`) 테스트 100% PASS 확인.
- [ ] 7.3 `TASK.md`에 신규 완료 과제 반영 및 후속 마일스톤 업데이트.
