# TAP Unit Test Analysis & Universal Unit Test Framework Design

- **일자**: 2026-11-07
- **대상 워크스페이스**: `Create_Aeroneutics` (`src/<layer>/<program>/` 멀티 Lua 코드베이스)
- **참조 규칙**: `.agent/rules/cc-tweaked-runtime.md`, `.agent/rules/domain-aeronautics.md`, `src/README.md`

---

## 1. TAP 프로젝트 단위 테스트 구조 분석 요약

기존 `TAP` 프로젝트의 단위 테스트 체계(`Gate 2` + `harness_lib.lua` + `projects/tap/tests/test_*.lua` 11종 + `tests/test_harness_gates.py`)를 정밀 분석한 결과, 핵심 구성요소와 테스트 패턴은 다음과 같다.

### 1.1 실행 인프라 및 게스트 러너
1. **격리된 CraftOS-PC 헤드리스 세션 (`EphemeralCraftOSSession`)**:
   - `CraftOS-PC_console.exe`를 `--headless`(또는 `monitor`/`computer` 페리페럴 부착 시 `--raw`)와 `-d <session_dir>` 옵션으로 기동한다.
   - 호스트 프로젝트 파일을 임시 세션의 `computer/0/` 내부로 복사 스테이징하여 `fs.open`/`fs.delete` 테스트가 원본 워크스페이스를 변경하지 않도록 분리한다.
   - 게스트 종료 신호(`/_harness_out/done.flag`) 및 JSON 결과(`/_harness_out/result.json`) 폴링과 프로세스 트리 강제 종료(`taskkill /F /T /PID`) 이중 워치독을 사용한다.
2. **인게스트 테스트 DSL 및 프로파일러 (`_harness_lib.lua`)**:
   - 전역 BDD 구문: `describe(name, fn)`, `it(name, fn)`.
   - 기본 단언문 4종: `assert_eq`, `assert_true`, `assert_contains`, `assert_error`.
   - 명령어 예산 감시: `debug.sethook(count_hook, "", 100)`으로 `it()` 블록당 바이트코드 실행량을 계측해 `max_instructions_per_tick`(기본 `50000`) 초과 시 `YIELD_BUDGET_EXCEEDED` 오류를 발생시킨다.
   - 이벤트 삼킴(Event Swallowing) 감시: 단위 테스트 실행 중 `os.pullEvent`, `os.pullEventRaw`, `sleep`, `os.sleep` 호출 시 `EVENT_SWALLOW_VIOLATION` 오류를 발생시켜 순수 모듈 내부의 블로킹 호출을 탐지한다.
   - 화면 버퍼 감사: `term.blit(text, fg, bg)` 길이 불일치(`BLIT_LENGTH_MISMATCH`) 및 비수치 커서 좌표를 기록한다.
3. **정적 검사 게이트 (`NativeLuaCompiler` / `gate1_static.py`)**:
   - `lua52.dll`(`ctypes`)을 통한 Lua 5.2 문법 검증, 금지 모드(Valkyrien Skies / CC:VS) 식별자 스캔, 모듈 내 블로킹 슬립 검사를 수행한다.

### 1.2 TAP 단위 테스트(11개 파일)에서 확인된 테스트 패턴
- **순수 프로토콜·수학·할당 로직** (`test_packet_protocol.lua`, `test_group_allocator.lua`, `test_discovery_handler.lua`): 테이블 입력 주입 및 반환값·오차 범위(`math.abs(a - b) < 0.01`) 검증.
- **파일시스템 영속성** (`test_config_manager.lua`, `test_actuator_adapter.lua`): CraftOS 네이티브 `fs.open`/`fs.delete`를 이용한 설정 저장·로드·손상 JSON 복구 검증.
- **모뎀·액추에이터 대역 객체** (`test_tap_daemon.lua`, `test_channel_rebind_handler.lua`, `test_status_reporter.lua`): 파일별 인라인 `mockModem`(`open`, `close`, `isOpen`, `transmit` 송신 큐 기록) 및 `{ setSpeed = fn, setPower = fn }` 스텁 주입.
- **TUI 및 CLI 도구 검증** (`test_tui_dashboard.lua`, `test_tap_setup.lua`): `_G.__TAP_SETUP_IMPORTED_ONLY = true` 가드로 메인 루프 자동 진입을 억제한 뒤 키 핸들러·렌더 함수를 단위 호출.

---

## 2. `Create_Aeroneutics` 확장 시 식별된 5가지 구조적 한계

`TAP`은 단일 프로그램(`tap`) 전용 구조였기 때문에, 현재 `Create_Aeroneutics`의 다중 계층 코드베이스(`alignment`, `gps`, `tca`, `vas`, `sas` 및 향후 `gac`, `landing_pad`, `runway`, `docking_arm`, `asa` 등)에 그대로 적용할 경우 다음 문제가 발생한다.

1. **다중 코드베이스 간 모듈명·경로 충돌**:
   - `src/1_control/vas/modules/ui_renderer.lua`와 `src/2_guidance/sas/modules/ui_renderer.lua`, `network_manager.lua`, `protocol.lua` 등 서로 다른 프로그램이 동일 모듈명을 사용한다.
   - 각 코드베이스(`src/<layer>/<program>/`)는 인게임 컴퓨터 루트(`/`)에 배포되는 자체 완결형 구조를 가정하므로(`config/sas_config.json`, `modules/?.lua`, `hal/?.lua`, `tools/?.lua`), 코드베이스별 독립 CraftOS 세션 격리와 표준 `package.path` 자동 주입이 필요하다.
2. **테스트 간 전역(`_G`) 및 `package.loaded` 오염**:
   - `TAP`의 `test_tui_dashboard.lua`(`_G.term = ...`)와 `test_watchdog_sentinel.lua`(`package.loaded["actuator_adapter"] = ...`)는 변경한 전역 테이블과 모듈 캐시를 복원하지 않아 후속 테스트 파일 실행 순서에 따라 부작용이 전파된다.
3. **수치 연산·구조 비교 단언문 및 도메인 공용 Mock 부재**:
   - `vas`(`quat`, `vec3`, `flight_dynamics_core`, `sensor_pipeline`), `gps`(`trilateration`), `alignment`(`ols_regression_engine`, `align_master`)는 부동소수점 오차 검증(`assert_near`, `NaN`/`±inf` 거부 포함), 중첩 패킷 비교(`assert_deep_eq`), CC:Avionics 센서·Create Propulsion 액추에이터 스텁이 반복적으로 필요하다.
   - 특히 `alignment/modules/align_master.lua`와 `hud_renderer.lua`처럼 `m.transmit(...)`과 `m:transmit(...)`을 혼용·폴백하는 코드를 위해 `.` 호출과 `:` 호출을 모두 수용하는 Mock 규격이 필요하다.
4. **제한적 이벤트 루프 헬퍼 테스트 불가**:
   - 모든 `it()`에서 `os.pullEvent`를 일괄 차단하면 `os.queueEvent`로 유한 이벤트를 주입해 검증해야 하는 짧은 헬퍼(`flush_char_events` 등)를 단위 테스트할 수 없다. 기본값은 차단으로 유지하되 명시적 `sdk.with_events_allowed(fn)` 예외 블록이 필요하다.
5. **호스트 환경 독립성 제약**:
   - `GEMINI.md` 불변 규칙에 따라 `Antigravity_Workspace`의 레거시 하네스나 바이너리를 참조하지 않고, 호스트 Python 3.12 표준 라이브러리(`unittest`, `ctypes`, `subprocess`)와 시스템에 설치된 `CraftOS-PC_console.exe`(`C:\Program Files\CraftOS-PC\`)를 자동 탐색해 동작해야 한다.

---

## 3. 범용 단위 테스트 프레임워크 목표 아키텍처

### 3.1 디렉토리 및 설정 규약
- **프로덕션 코드**: `src/<layer>/<program>/` (테스트 파일 혼입 없음)
- **단위 테스트 스위트**: `tests/<layer>/<program>/test_*.lua` (`src/<layer>/<program>/`과 1:1 대칭)
- **선택적 타깃 오버라이드**: `tests/<layer>/<program>/unit.json` (생략 시 기본값 적용: `top` 모뎀 부착, `51x19` 터미널, `max_instructions_per_tick = 50000`, `timeout_sec = 8.0`, `abort_timeout_ms = 4000`)
- **호스트 러너 및 게스트 코어**:
  - `harness/unit/config.py`: 타깃 코드베이스 자동 탐색(`src/<layer>/<program>`), 단축명 해석(`tca` -> `1_control/tca`), CraftOS-PC 실행 파일·`lua52.dll` 경로 해석.
  - `harness/unit/session.py`: 코드베이스별 임시 세션(`.runtime/sessions/unit_<slug>_<ts>_<id>/`) 생성, `src/<layer>/<program>/` → `computer/0/`, `tests/<layer>/<program>/` → `computer/0/_tests/` 스테이징, 이중 워치독 실행 및 세션 경로 한정 고아 프로세스 정리.
  - `harness/unit/static_guard.py`: 실행 전 `src/` 및 `tests/` 대상 Lua 5.2 문법(`lua52.dll` `luaL_loadbufferx`), 주석·문자열 제거 후 Lua 5.3+ 연산자(`//`, `&`, `|`, `<<`, `>>`), 금지 호스트 OS API, 금지 Valkyrien Skies 식별자 정적 검사.
  - `harness/unit/guest/runner_lib.lua`: `describe`, `it`, `before_each`, `after_each`, 테스트 케이스 단위 전역/모듈 캐시 스냅샷·복원, `debug.sethook` 명령어 예산 계측, 이벤트 삼킴 차단 및 `sdk.with_events_allowed` 예외 허용, `term.blit` 감사, JSON 결과 직렬화.
  - `harness/unit/guest/test_sdk.lua`: 확장 단언문(`assert_eq`, `assert_ne`, `assert_true`, `assert_false`, `assert_nil`, `assert_not_nil`, `assert_near`, `assert_deep_eq`, `assert_contains`, `assert_error`) 및 범용 Mock 팩토리(`mock.modem`, `mock.term`, `mock.redstone`, `mock.clock`, `mock.peripheral_registry`, `mock.avionics_gimbal`, `mock.avionics_altitude`, `mock.avionics_velocity`, `mock.fuel_tank`, `mock.actuator`).
  - `harness/unit/engine.py`: 정적 가드 → CraftOS 세션 실행 → `TargetRunReport` 집계 파이프라인.
  - `tools/run_unit_tests.py`: 단일/전체 코드베이스 실행 CLI (`--target`, `--filter`, `--json`, `--require-tests`, `--clean-orphans`).
  - `tests/harness/test_*.py`: 호스트 러너 자체 검증 스위트 (`python -m unittest discover -s tests/harness -v`).

### 3.2 게스트 패키지 경로 계약
코드베이스 `src/<layer>/<program>/`이 `computer/0/` 루트(`/`)로 복사된 상태에서 게스트 부트스트랩은 아래 `package.path`를 선두에 주입한다:
```lua
"/?.lua;/?/init.lua;/modules/?.lua;/modules/?/init.lua;/hal/?.lua;/tools/?.lua;/lib/?.lua;"
```
이를 통해 `alignment`, `gps`, `tca`, `vas`, `sas` 및 향후 신규 계층 코드베이스가 별도 경로 수정 없이 인게임과 동일한 `require("<module>")` 및 상대 설정 경로(`"config.json"`, `"config/sas_config.json"`)를 그대로 사용한다.

### 3.3 CLI 종료 코드 및 리포트 계약
- 종료 코드 `0`: 실행된 모든 타깃의 정적 위반 `0`건, 실패 테스트 `0`건, 이벤트 삼킴 위반 `0`건, UI `blit` 위반 `0`건, 타임아웃 `False` (테스트 파일이 없는 코드베이스는 기본 `SKIP`, `--require-tests` 지정 시 `FAIL` 처리).
- 종료 코드 `1`: 위 조건 중 하나라도 위반되거나 CraftOS-PC 실행 파일 미발견 시 반환.
