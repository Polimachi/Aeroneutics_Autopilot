# 범용 단위 테스트 프레임워크 구현 계획

> **에이전트 작업자 필수 지침:** 필수 서브 스킬로 `superpowers:subagent-driven-development`(권장) 또는 `superpowers:executing-plans`를 사용하여 태스크 단위로 본 계획을 구현하십시오. 각 단계의 진행 상황은 체크박스(`- [ ]`) 구문으로 추적합니다.

**목표 (Goal):** `src/<계층>/<프로젝트명>/` 산하 모든 독립 코드베이스에서 범용적으로 동작하는 격리형 CraftOS-PC 단위 테스트 러너 및 Create: Aeronautics 전용 Lua 5.2 단언문/Mock SDK를 구축하고, 활성 5개 프로그램 파일럿 테스트를 통해 동작을 검증한다.

**아키텍처 (Architecture):** Python 3.12 표준 라이브러리 기반 CLI(`tools/run_unit_tests.py`)가 `src/<layer>/<program>/` 하위의 자체 완결형 코드베이스를 자동 탐색하고, 사전 Lua 5.2 및 Create: Aeronautics 도메인 정적 검사(`lua52.dll` 문법 검사 + 금지 연산자/모드 스캔)를 수행한 뒤, 각 코드베이스별로 격리된 임시 CraftOS-PC 헤드리스 세션을 기동한다. 이때 `src/<layer>/<program>/`은 게스트 루트(`/`)에, `tests/<layer>/<program>/`은 `/_tests/`에 스테이징되며, 게스트 내부의 `runner_lib.lua` 및 `test_sdk.lua`가 테스트 케이스별 전역/모듈 캐시 자동 복원, `debug.sethook` 바이트코드 실행량 계측, 이벤트 삼킴 차단 및 `.`/`:` 호출 호환 Mock 환경에서 `describe`/`it` 스위트를 실행한다.

**기술 스택 (Tech Stack):** Python 3.12 (`unittest`, `ctypes`, `subprocess`, `argparse`, `json`), CraftOS-PC (`CraftOS-PC_console.exe`, `lua52.dll`, `periphemu`), CC:Tweaked Lua 5.2 (Cobalt 런타임 호환).

**참조 사양서 (Spec):** `docs/superpowers/specs/2026-11-07-universal-unit-test-design.md` (필수 준수 규칙: `.agent/rules/cc-tweaked-runtime.md`, `.agent/rules/domain-aeronautics.md`, `src/README.md`)

## 전역 제약사항 (Global Constraints)

- 레거시 하네스 격리 (`GEMINI.md`): `Antigravity_Workspace`의 구 하네스 스크립트나 바이너리를 참조·호출하지 않으며, `CraftOS-PC_console.exe`는 환경 변수 `CRAFTOS_PC_EXE`, 시스템 `PATH`, 또는 `C:\Program Files\CraftOS-PC\CraftOS-PC_console.exe`에서 자동 탐색한다.
- 호스트 Python 의존성: Python 3.12 표준 라이브러리만 사용한다 (`pytest` 미설치 환경이므로 호스트 테스트는 `python -m unittest` 사용).
- Git 바이너리 및 인덱스 격리: PowerShell `PATH`에 `git`이 없을 경우 `"C:\Program Files\Git\cmd\git.exe"`를 직접 호출하며, 작업 트리에 이미 존재하는 타 작업 수정분이 섞여 커밋되지 않도록 `git commit --only <task_files...> -m "..."` 또는 전용 Git Worktree 격리를 사용한다.
- Lua 5.2 런타임 제약 (`.agent/rules/cc-tweaked-runtime.md`): Lua 5.3+ 전용 연산자(`//`, `&`, `|`, 단항/XOR `~`, `<<`, `>>`), `getfenv`/`setfenv`, 가변 인자 `arg` 테이블, 비활성화된 호스트 OS 호출(`os.execute`, `io.popen`, `os.exit`, `os.remove`, `os.rename`)을 금지한다.
- 도메인 모드 차단 (`.agent/rules/domain-aeronautics.md`): Valkyrien Skies 및 CC:VS 계통 식별자(`valkyrien`, `valkyrienskies`, `vs2`, `cc_vs`, `vs_computers`, `valkyriencomputers`, `ship_api`, `extendedshipapi`, `ship_reader`, `vs_clockwork`, `eureka`, `trackwork`, `vs_tournament`, `vs_addition`, `create_interactive`, `vmod`, `drivebywire`, `kontraption:`, `peripheral.find("ship")`, `peripheral.wrap("ship")`, `ship.*` 물리 메서드)를 `src/` 및 `tests/`에서 차단한다 (단, Create Propulsion: Simulated의 단독 `ion_thruster` 페리페럴은 정상 허용).
- 프로덕션 디렉토리 순수성 (`src/README.md`): `src/<layer>/<program>/` 내부에는 테스트 파일이나 공용 런타임 라이브러리를 혼입하지 않으며, 모든 단위 테스트는 `tests/<layer>/<program>/test_*.lua`에 배치한다.
- 실행량 및 이벤트 규약: 기본값은 `max_instructions_per_tick = 50000`, `term_width = 51`, `term_height = 19`, `timeout_sec = 8.0`, `abort_timeout_ms = 4000`을 적용하며, `it()` 내부의 `os.pullEvent`, `os.pullEventRaw`, `sleep` 호출은 `sdk.with_events_allowed(...)` 블록으로 명시 감싸지 않는 한 차단한다.
- 문서 및 코드 표현 (`AGENTS.md` `no-overclaim`): 측정·검증되지 않은 우월성이나 완전성 표현을 문서, 주석, 코드에 작성하지 않는다.

## 집중 검토 항목 (Review Focus)

1. **`assert_near(actual, expected, eps)`에 `NaN` 또는 `±inf` 입력 전달**: 비유한 실수(`0/0`, `math.huge`, `-math.huge`)가 IEEE-754 비교를 통과하지 못하도록 명시적으로 `assert_near`에서 실패 처리해야 한다. (Task 4에서 검증)
2. **`_G.term`, `_G.peripheral`, 또는 `package.loaded[mod]` 변조 후 테스트 중도 에러 발생**: `it()` 블록 내부에서 전역이나 모듈 스텁을 변경한 직후 에러가 발생해도, 다음 `it()` 또는 후속 `test_*.lua` 실행 전에 이전 상태로 안전하게 복원되어야 한다. (Task 3에서 검증)
3. **페리페럴 메서드의 `.` 및 `:` 혼용 호출 (`m.transmit(...)` vs `m:transmit(...)`, `dev.write(...)` vs `dev:write(...)`)**: `mock.modem`, `mock.term`, `mock.actuator` 등 공용 Mock은 첫 번째 인자가 `self`인 경우 이를 정규화하여 두 호출 방식 모두 동일한 인자 큐를 기록해야 한다. (Task 4에서 검증)
4. **Lua 주석 및 문자열 리터럴 내부의 URL(`https://...`) 또는 비트 연산 기호 오탐 방지**: Lua 5.3+ 연산자 검사기는 줄 번호를 보존하면서 `--` 한 줄 주석, `--[[...]]` 블록 주석, 인용 부호 및 롱 스트링 리터럴을 빈칸으로 치환하여 URL의 `//`가 연산자로 오탐되지 않도록 해야 한다. (Task 2에서 검증)
5. **고아 프로세스 정리 시 사용자가 별도로 띄운 외부 `CraftOS-PC_console.exe` 보호**: `clean_workspace_orphans`는 프로세스의 `CommandLine`이 현재 워크스페이스의 `.runtime/sessions` 경로를 포함하는 경우에만 종료 대상으로 식별하고 타 CraftOS-PC 프로세스는 유지해야 한다. (Task 1에서 검증)

---

## 파일 구조 (File Structure)

- `harness/__init__.py` — 워크스페이스 검증 패키지 식별자.
- `harness/unit/__init__.py` — 단위 테스트 러너의 공용 데이터 클래스 및 진입점 노출.
- `harness/unit/config.py` — `CraftOS-PC_console.exe` 및 `lua52.dll` 경로 탐색, `src/<layer>/<program>/` 대상 자동 수집 및 선택적 `tests/<layer>/<program>/unit.json` 로드.
- `harness/unit/session.py` — 임시 `.runtime/sessions/` 디렉토리 관리, 코드베이스/테스트 파일 스테이징, 이중 워치독 실행 및 세션 한정 고아 프로세스 정리.
- `harness/unit/static_guard.py` — `lua52.dll`(`ctypes`) 기반 Lua 5.2 문법 검사 및 주석/문자열 제거 소스 대상 Lua 5.3+ 연산자, 호스트 OS API, 금지 모드 정적 검사.
- `harness/unit/guest/runner_lib.lua` — 게스트 내 BDD 테스트 러너(`describe`, `it`, `before_each`, `after_each`), 전역/모듈 캐시 스냅샷 복원, `debug.sethook` 실행량 계측, 이벤트 삼킴 가드, `term.blit` 감사 및 JSON 결과 출력.
- `harness/unit/guest/test_sdk.lua` — 게스트 내 확장 단언문(`assert_near`, `assert_deep_eq`, `assert_throws` 등) 및 Create: Aeronautics / CC:Tweaked Mock 팩토리(`mock.modem`, `mock.term`, `mock.redstone`, `mock.clock`, `mock.peripheral_registry`, `mock.avionics_*`, `mock.fuel_tank`, `mock.actuator`).
- `harness/unit/engine.py` — 정적 검사 및 임시 CraftOS-PC 세션 실행 파이프라인 조율, `TargetRunReport` 결과 취합.
- `tools/run_unit_tests.py` — CLI 실행 도구 (`--target`, `--filter`, `--json`, `--require-tests`, `--clean-orphans` 지원).
- `.luarc.json` — LuaLS 진단에서 단위 테스트 경로 및 전역 함수(`describe`, `it`, `mock`, `sdk`, `assert_*`) 인식 지원.
- `tests/harness/test_*.py` — Python `unittest` 기반 호스트 하네스 자체 검증 스위트.
- `tests/<layer>/<program>/test_<program>_core.lua` — 활성 5개 프로그램(`tca`, `vas`, `sas`, `gps`, `alignment`) 대상 파일럿 단위 테스트 스위트.

---

### Task 1: 대상 탐색, 설정 관리 및 임시 CraftOS-PC 세션 매니저

**파일 목록:**
- 생성: `harness/__init__.py`
- 생성: `harness/unit/__init__.py`
- 생성: `harness/unit/config.py`
- 생성: `harness/unit/session.py`
- 테스트: `tests/harness/test_session_and_config.py`

**인터페이스 명세:**
- 입력: 호스트 환경 정보 (`CRAFTOS_PC_EXE`, `CRAFTOS_PC_ROM_DIR`, `C:\Program Files\CraftOS-PC\CraftOS-PC_console.exe`).
- 출력:
  - `PeripheralAttachment(side: str | int, peripheral_type: str, args: list[Any] = field(default_factory=list))`
  - `CraftOSPaths(craftos_exe: Path, rom_dir: Path, lua52_dll: Path | None)`
  - `UnitTargetConfig(target_id: str, source_dir: Path, tests_dir: Path, timeout_sec: float = 8.0, abort_timeout_ms: int = 4000, term_width: int = 51, term_height: int = 19, max_instructions_per_tick: int = 50000, peripherals: list[PeripheralAttachment] = ...)`
  - `resolve_craftos_paths(env: Mapping[str, str] | None = None) -> CraftOSPaths`
  - `discover_codebase_targets(workspace_root: Path, target_query: str | None = None) -> list[UnitTargetConfig]`
  - `CraftOSSessionResult(session_id: str, exit_code: int, timed_out: bool, duration_ms: float, stdout_raw: str, stderr_raw: str, guest_result: dict[str, Any] | None)`
  - `EphemeralCraftOSSession(sessions_root: Path, craftos_paths: CraftOSPaths, prefix: str = "unit", abort_timeout_ms: int = 4000, term_width: int = 51, term_height: int = 19, keep_session: bool = False)` (메서드: `.computer_dir(...)`, `.stage_tree(...)`, `.run(...)`)
  - `clean_workspace_orphans(sessions_root: Path, max_age_sec: float = 0.0, process_enumerator: Callable[[], list[dict[str, Any]]] | None = None) -> dict[str, list[Any]]`

- [ ] **1단계: 실패하는 테스트 작성 (`tests/harness/test_session_and_config.py`)**

```python
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from harness.unit.config import discover_codebase_targets, resolve_craftos_paths
from harness.unit.session import EphemeralCraftOSSession, clean_workspace_orphans


class TestSessionAndConfig(unittest.TestCase):
    def test_discover_targets_and_short_name_query(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "src" / "1_control" / "tca").mkdir(parents=True)
            (root / "src" / "1_control" / "tca" / "main.lua").write_text("return true\n", encoding="utf-8")
            (root / "src" / "1_control" / "asa").mkdir(parents=True)
            (root / "src" / "1_control" / "asa" / "README.md").write_text("# ASA\n", encoding="utf-8")

            targets = discover_codebase_targets(root)
            self.assertEqual([t.target_id for t in targets], ["1_control/tca"])
            self.assertEqual(targets[0].peripherals[0].peripheral_type, "modem")

            by_short = discover_codebase_targets(root, target_query="tca")
            self.assertEqual(len(by_short), 1)
            self.assertEqual(by_short[0].target_id, "1_control/tca")

            with self.assertRaises(ValueError):
                discover_codebase_targets(root, target_query="nonexistent")

    def test_resolve_craftos_paths_rejects_invalid_override(self) -> None:
        with self.assertRaises(FileNotFoundError):
            resolve_craftos_paths({"CRAFTOS_PC_EXE": r"C:\missing\CraftOS-PC_console.exe"})

    def test_clean_orphans_ignores_external_craftos_processes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sessions_root = Path(tmp) / ".runtime" / "sessions"
            sessions_root.mkdir(parents=True)
            fake_procs = [
                {"ProcessId": 1111, "CommandLine": r'"C:\Program Files\CraftOS-PC\CraftOS-PC_console.exe"'},
                {"ProcessId": 2222, "CommandLine": f'CraftOS-PC_console.exe --headless -d "{sessions_root}\\unit_1"'},
            ]
            killed: list[int] = []
            with patch("harness.unit.session._kill_pid_tree", side_effect=lambda pid: killed.append(pid)):
                res = clean_workspace_orphans(sessions_root, process_enumerator=lambda: fake_procs)
            self.assertEqual(killed, [2222])
            self.assertEqual(res["killed_pids"], [2222])

    def test_ephemeral_session_executes_and_cleans_up(self) -> None:
        paths = resolve_craftos_paths()
        with tempfile.TemporaryDirectory() as tmp:
            sessions_root = Path(tmp) / "sessions"
            with EphemeralCraftOSSession(sessions_root, paths, prefix="smoke") as sess:
                c0 = sess.computer_dir(0)
                sdir = sess.session_dir
                (c0 / "startup.lua").write_text(
                    'fs.makeDir("/_harness_out")\n'
                    'local f = fs.open("/_harness_out/result.json", "w")\n'
                    'f.write(textutils.serializeJSON({ ok = true, sum = 2 + 3 }))\n'
                    'f.close()\n'
                    'local d = fs.open("/_harness_out/done.flag", "w")\n'
                    'd.write("OK")\n'
                    'd.close()\n'
                    'os.shutdown()\n',
                    encoding="utf-8",
                )
                result = sess.run(mode="headless", timeout_sec=5.0)
                self.assertTrue(sdir.exists())
            self.assertFalse(sdir.exists())
            self.assertFalse(result.timed_out)
            self.assertEqual(result.guest_result, {"ok": True, "sum": 5})
```

- [ ] **2단계: 테스트 실행 및 실패 확인**

실행 명령: `python -m unittest tests/harness/test_session_and_config.py -v`
예상 결과: `ModuleNotFoundError: No module named 'harness'` 오류로 실패

- [ ] **3단계: `harness/unit/config.py` 및 `harness/unit/session.py` 구현**

- `harness/unit/config.py`:
  - `resolve_craftos_paths(env)`: `CRAFTOS_PC_EXE`가 지정된 경우 해당 경로의 실존 여부를 검증하고, 미지정 시 시스템 경로와 공식 설치 경로(`C:\Program Files\CraftOS-PC\CraftOS-PC_console.exe`)를 차례로 탐색한다. `rom_dir` 및 `lua52_dll` 경로를 함께 구성한다.
  - `discover_codebase_targets(workspace_root, target_query)`: `src/<layer>/<program>` 구조에서 `*.lua` 파일이 존재하는 대상을 수집한다. `tests/<layer>/<program>/unit.json`이 존재하면 실행 타임아웃, 화면 크기, 부착 페리페럴 목록을 오버라이드한다. `target_query`를 지원하여 단축명(`tca`) 또는 전체 ID(`1_control/tca`)로 필터링한다.
- `harness/unit/session.py`:
  - 임시 세션 디렉토리에 `config/global.json`을 생성하고, `.stage_tree`를 통해 소스 및 테스트 트리를 복사 스테이징한다.
  - `.run`에서 CraftOS-PC 프로세스를 비동기 실행하고, `_harness_out/done.flag` 신호와 프로세스 종료 상태를 폴링하여 결과를 파싱한다.
  - `clean_workspace_orphans`는 `CommandLine`에 워크스페이스 세션 경로가 포함된 프로세스만 선별 종료한다.

- [ ] **4단계: 테스트 실행 및 통과 확인**

실행 명령: `python -m unittest tests/harness/test_session_and_config.py -v`
예상 결과: PASS (4개 테스트 통과)

- [ ] **5단계: 커밋**

```bash
git add harness/__init__.py harness/unit/__init__.py harness/unit/config.py harness/unit/session.py tests/harness/test_session_and_config.py
git commit --only harness/__init__.py harness/unit/__init__.py harness/unit/config.py harness/unit/session.py tests/harness/test_session_and_config.py -m "feat(harness): add multi-codebase target discovery and CraftOS session manager"
```

---

### Task 2: 사전 정적 검사 (Lua 5.2 및 Create: Aeronautics 도메인 가드)

**파일 목록:**
- 생성: `harness/unit/static_guard.py`
- 수정: `harness/unit/__init__.py`
- 테스트: `tests/harness/test_static_guard.py`

**인터페이스 명세:**
- 입력: `harness.unit.config`의 `CraftOSPaths`, `UnitTargetConfig`.
- 출력:
  - `StaticViolation(file_path: str, line: int, code: str, message: str)`
  - `Lua52SyntaxChecker(lua52_dll_path: Path | None)` (메서드: `.check_source(source: str, chunk_name: str) -> StaticViolation | None`)
  - `strip_lua_comments_and_strings(source: str) -> str`
  - `scan_lua_source(source: str, rel_path: str, syntax_checker: Lua52SyntaxChecker | None = None) -> list[StaticViolation]`
  - `scan_target_files(target: UnitTargetConfig, craftos_paths: CraftOSPaths) -> list[StaticViolation]`

- [ ] **1단계: 실패하는 테스트 작성 (`tests/harness/test_static_guard.py`)**

```python
import unittest

from harness.unit.config import resolve_craftos_paths
from harness.unit.static_guard import Lua52SyntaxChecker, scan_lua_source


class TestStaticGuard(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        paths = resolve_craftos_paths()
        cls.checker = Lua52SyntaxChecker(paths.lua52_dll)

    def test_lua52_dll_catches_syntax_error_with_line(self) -> None:
        v = scan_lua_source("local a = 1\nlocal b =\nreturn a\n", "modules/bad.lua", self.checker)
        self.assertTrue(any(item.code == "LUA52_SYNTAX_ERROR" and item.line >= 2 for item in v))

    def test_lua53_operators_rejected_but_urls_and_strings_ignored(self) -> None:
        safe_url_src = (
            '-- Docs: https://tweaked.cc/module/peripheral.html?a=1&b=2\n'
            'local url = "https://example.com/api//v1?x=1&y=2|z=3"\n'
            'local long_str = [[http://local//test << >> & |]]\n'
            'local ok = (1 ~= 2)\n'
            'return url, long_str, ok\n'
        )
        self.assertEqual(scan_lua_source(safe_url_src, "modules/safe.lua", self.checker), [])

        bad_ops = [
            "local q = 10 // 3\n",
            "local m = 6 & 3\n",
            "local n = 6 | 1\n",
            "local s = 1 << 4\n",
        ]
        for snippet in bad_ops:
            issues = scan_lua_source(snippet, "modules/op.lua", None)
            self.assertTrue(any(i.code == "LUA53_OPERATOR" for i in issues), snippet)

    def test_host_os_apis_rejected(self) -> None:
        issues = scan_lua_source('os.execute("dir")\nos.remove("a.txt")\n', "modules/os_bad.lua", self.checker)
        codes = [i.code for i in issues]
        self.assertEqual(codes.count("PROHIBITED_HOST_OS_API"), 2)

    def test_vs2_blocked_and_create_aeronautics_plus_ion_thruster_allowed(self) -> None:
        blocked_cases = [
            'local s = peripheral.find("ship")\n',
            'local q = ship.getQuaternion()\n',
            'local k = peripheral.find("kontraption:ion_thruster")\n',
            'local h = peripheral.wrap("eureka:ship_helm")\n',
            'local v = require("vs2.ship")\n',
        ]
        for code in blocked_cases:
            issues = scan_lua_source(code, "modules/flight.lua", self.checker)
            self.assertTrue(any(i.code == "PROHIBITED_MOD_VIOLATION" for i in issues), code)

        allowed_code = (
            'local ion = peripheral.find("ion_thruster")\n'
            'local vec = peripheral.find("vector_thruster")\n'
            'local gim = peripheral.find("gimbal_sensor")\n'
            'local brg = peripheral.find("create:clockwork_bearing")\n'
            'local ship_state = { ship_pos = { x = 0, y = 64, z = 0 }, ship_velocity = 12.0 }\n'
            'return ion, vec, gim, brg, ship_state\n'
        )
        self.assertEqual(scan_lua_source(allowed_code, "modules/aero.lua", self.checker), [])
```

- [ ] **2단계: 테스트 실행 및 실패 확인**

실행 명령: `python -m unittest tests/harness/test_static_guard.py -v`
예상 결과: `ModuleNotFoundError: No module named 'harness.unit.static_guard'` 오류로 실패

- [ ] **3단계: `harness/unit/static_guard.py` 구현**

- `ctypes`를 통해 `lua52.dll`의 `luaL_newstate`, `luaL_loadbufferx`, `lua_close`를 바인딩하여 네이티브 구문 검증기를 구성한다.
- `strip_lua_comments_and_strings`: 주석 및 문자열 리터럴을 빈칸으로 치환하여 원본 줄 번호를 유지하되, 문자열 내부의 URL 기호로 인한 Lua 5.3+ 연산자 오탐을 방지한다. 단, 금지 모드 식별자 스캔을 위한 문자열 리터럴 토큰 목록을 별도 추출해 검사한다.
- `.agent/rules/cc-tweaked-runtime.md` 및 `.agent/rules/domain-aeronautics.md` 규칙에 따른 금지 토큰 위반 사항을 검출한다.

- [ ] **4단계: 테스트 실행 및 통과 확인**

실행 명령: `python -m unittest tests/harness/test_static_guard.py -v`
예상 결과: PASS (4개 테스트 통과)

- [ ] **5단계: 커밋**

```bash
git add harness/unit/static_guard.py harness/unit/__init__.py tests/harness/test_static_guard.py
git commit --only harness/unit/static_guard.py harness/unit/__init__.py tests/harness/test_static_guard.py -m "feat(harness): add Lua 5.2 and Create Aeronautics static guard"
```

---

### Task 3: 인게스트 단위 테스트 러너 코어, 격리 복원 및 프로파일러

**파일 목록:**
- 생성: `harness/unit/guest/runner_lib.lua`
- 생성: `harness/unit/engine.py`
- 수정: `harness/unit/__init__.py`
- 수정: `.luarc.json`
- 테스트: `tests/harness/test_runner_isolation_and_profiler.py`

**인터페이스 명세:**
- 입력: `UnitTargetConfig`, `CraftOSPaths`, `EphemeralCraftOSSession`, `StaticViolation`, `scan_target_files`.
- 출력:
  - `UnitCaseResult(suite: str, name: str, status: str, duration_ms: float = 0.0, instructions: int = 0, error: str = "")`
  - `TargetRunReport(target_id: str, status: str, total_tests: int = 0, passed_tests: int = 0, failed_tests: int = 0, max_insns_observed: int = 0, event_swallow_count: int = 0, ui_violation_count: int = 0, duration_ms: float = 0.0, timed_out: bool = False, static_violations: list[StaticViolation] = ..., tests: list[UnitCaseResult] = ..., logs: list[str] = ..., errors: list[str] = ...)`
  - `run_target_unit_tests(...) -> TargetRunReport`
  - 게스트 전역 함수: `describe`, `it`, `before_each`, `after_each`, `sdk.patch`, `sdk.mock_module`, `sdk.temp_path`, `sdk.with_events_allowed`, `sdk.profile_budget`, `assert_eq`, `assert_true`, `assert_contains`, `assert_error`.

- [ ] **1단계: 실패하는 테스트 작성 (`tests/harness/test_runner_isolation_and_profiler.py`)**

```python
import tempfile
import unittest
from pathlib import Path

from harness.unit.config import UnitTargetConfig, resolve_craftos_paths
from harness.unit.engine import run_target_unit_tests


class TestRunnerIsolationAndProfiler(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.paths = resolve_craftos_paths()

    def _make_target(self, root: Path, src_files: dict[str, str], test_files: dict[str, str], budget: int = 50000) -> UnitTargetConfig:
        sdir = root / "src" / "1_control" / "demo"
        tdir = root / "tests" / "1_control" / "demo"
        sdir.mkdir(parents=True)
        tdir.mkdir(parents=True)
        for rel, body in src_files.items():
            p = sdir / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(body, encoding="utf-8")
        for rel, body in test_files.items():
            p = tdir / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(body, encoding="utf-8")
        return UnitTargetConfig(
            target_id="1_control/demo",
            source_dir=sdir,
            tests_dir=tdir,
            max_instructions_per_tick=budget,
        )

    def test_global_and_module_mutations_restore_even_after_test_crash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = self._make_target(
                root,
                {"modules/dep.lua": 'return { kind = "REAL" }\n'},
                {
                    "test_01_pollute.lua": (
                        'describe("polluter", function()\n'
                        '    it("mutates _G.term and package.loaded then crashes", function()\n'
                        '        _G.term = { broken = true }\n'
                        '        sdk.mock_module("dep", { kind = "STUB" })\n'
                        '        error("boom")\n'
                        '    end)\n'
                        'end)\n'
                    ),
                    "test_02_clean.lua": (
                        'describe("subsequent suite", function()\n'
                        '    it("sees restored _G.term and real dep module", function()\n'
                        '        assert_true(type(_G.term.getSize) == "function")\n'
                        '        assert_eq(_G.term.broken, nil)\n'
                        '        local dep = require("dep")\n'
                        '        assert_eq(dep.kind, "REAL")\n'
                        '    end)\n'
                        'end)\n'
                    ),
                },
            )
            rep = run_target_unit_tests(target, self.paths, root / "sessions")
            self.assertEqual(rep.passed_tests, 1)
            self.assertEqual(rep.failed_tests, 1)
            self.assertEqual(rep.tests[1].status, "PASS", rep.tests[1].error)

    def test_instruction_budget_and_event_swallow_guards(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = self._make_target(
                root,
                {"main.lua": "return true\n"},
                {
                    "test_guards.lua": (
                        'describe("guards", function()\n'
                        '    it("fails on excessive instruction loop", function()\n'
                        '        local s = 0\n'
                        '        for i = 1, 20000 do s = s + i end\n'
                        '    end)\n'
                        '    it("fails on unauthorized sleep", function()\n'
                        '        sleep(0.05)\n'
                        '    end)\n'
                        '    it("allows queued event pull inside sdk.with_events_allowed", function()\n'
                        '        sdk.with_events_allowed(function()\n'
                        '            os.queueEvent("custom_ping", 42)\n'
                        '            local ev, val = os.pullEvent("custom_ping")\n'
                        '            assert_eq(ev, "custom_ping")\n'
                        '            assert_eq(val, 42)\n'
                        '        end)\n'
                        '    end)\n'
                        'end)\n'
                    )
                },
                budget=5000,
            )
            rep = run_target_unit_tests(target, self.paths, root / "sessions")
            self.assertEqual(rep.tests[0].status, "FAIL")
            self.assertIn("YIELD_BUDGET_EXCEEDED", rep.tests[0].error)
            self.assertEqual(rep.tests[1].status, "FAIL")
            self.assertIn("EVENT_SWALLOW_VIOLATION", rep.tests[1].error)
            self.assertEqual(rep.tests[2].status, "PASS", rep.tests[2].error)

    def test_filter_executes_matching_cases_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = self._make_target(
                root,
                {"main.lua": "return true\n"},
                {
                    "test_filter.lua": (
                        'describe("math", function()\n'
                        '    it("alpha case", function() assert_eq(1, 1) end)\n'
                        '    it("beta case", function() error("should be skipped") end)\n'
                        'end)\n'
                    )
                },
            )
            rep = run_target_unit_tests(target, self.paths, root / "sessions", test_filter="alpha")
            self.assertEqual(rep.status, "PASS")
            self.assertEqual(rep.total_tests, 1)
```

- [ ] **2단계: 테스트 실행 및 실패 확인**

실행 명령: `python -m unittest tests/harness/test_runner_isolation_and_profiler.py -v`
예상 결과: `ModuleNotFoundError: No module named 'harness.unit.engine'` 오류로 실패

- [ ] **3단계: `runner_lib.lua`, `engine.py` 구현 및 `.luarc.json` 갱신**

- `harness/unit/guest/runner_lib.lua`:
  - `describe`/`it` 실행 전후 전역 환경(`_G.term`, `_G.peripheral`, `_G.rednet` 등)과 `package.loaded`를 스냅샷 및 복원하는 언두(undo) 체계를 구현한다.
  - `debug.sethook` 기반 바이트코드 실행량 계측 및 초과 시 `YIELD_BUDGET_EXCEEDED`를 발생시킨다.
  - 기본 상태에서 `os.pullEvent` 및 `sleep`을 차단하고, 유한 이벤트 테스트가 필요한 경우 `sdk.with_events_allowed` 블록을 통해서만 허용한다.
  - `term.blit` 호출 시 텍스트/전경색/배경색 문자열 길이 일치 여부를 감사한다.
- `harness/unit/engine.py`:
  - 정적 가드를 통과한 대상에 대해 임시 세션을 구축하고, `package.path`에 `"/?.lua;/?/init.lua;/modules/?.lua;/modules/?/init.lua;/hal/?.lua;/tools/?.lua;/lib/?.lua;"`를 주입한 뒤 CraftOS-PC를 실행하여 결과를 수집한다.
- `.luarc.json`:
  - 테스트 러너 전역 심볼(`describe`, `it`, `mock`, `sdk`, `assert_*` 등)을 진단 예외 목록에 등록한다.

- [ ] **4단계: 테스트 실행 및 통과 확인**

실행 명령: `python -m unittest discover -s tests/harness -v`
예상 결과: PASS (Task 1~3 호스트 테스트 모두 통과)

- [ ] **5단계: 커밋**

```bash
git add harness/unit/guest/runner_lib.lua harness/unit/engine.py harness/unit/__init__.py .luarc.json tests/harness/test_runner_isolation_and_profiler.py
git commit --only harness/unit/guest/runner_lib.lua harness/unit/engine.py harness/unit/__init__.py .luarc.json tests/harness/test_runner_isolation_and_profiler.py -m "feat(harness): add in-guest unit runner with state teardown and profiler"
```

---

### Task 4: 범용 CC:Tweaked & Create: Aeronautics 단언문 및 Mock SDK

**파일 목록:**
- 생성: `harness/unit/guest/test_sdk.lua`
- 수정: `harness/unit/engine.py`
- 테스트: `tests/harness/test_guest_sdk.py`

**인터페이스 명세:**
- 입력: `runner_lib.lua` (`_G.sdk`, `sdk.patch`).
- 출력:
  - 전역 단언문: `assert_ne`, `assert_false`, `assert_nil`, `assert_not_nil`, `assert_near`, `assert_deep_eq`, `assert_throws` (기존 `assert_error`와 병행 지원).
  - 전역 `_G.mock` 팩토리 (`.` 및 `:` 호출 모두 지원):
    - `mock.modem(opts)` -> 송수신 기록 및 채널 개폐 Mock
    - `mock.term(w, h)` -> 2D 가상 프레임버퍼 및 커서 제어 Mock
    - `mock.redstone()` -> 방향별 아날로그/디지털 신호 입출력 Mock
    - `mock.clock(start_ms)` -> 가상 시계 제어 Mock
    - `mock.peripheral_registry(side_map)` -> `peripheral` API 모킹 및 자동 복원
    - `mock.avionics_gimbal`, `mock.avionics_altitude`, `mock.avionics_velocity`, `mock.fuel_tank`, `mock.actuator`

- [ ] **1단계: 실패하는 테스트 작성 (`tests/harness/test_guest_sdk.py`)**

```python
import tempfile
import unittest
from pathlib import Path

from harness.unit.config import UnitTargetConfig, resolve_craftos_paths
from harness.unit.engine import run_target_unit_tests


class TestGuestSdk(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.paths = resolve_craftos_paths()

    def test_assertions_nan_inf_deep_eq_and_dual_call_mocks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            sdir = root / "src" / "1_control" / "sdk_check"
            tdir = root / "tests" / "1_control" / "sdk_check"
            sdir.mkdir(parents=True)
            tdir.mkdir(parents=True)
            (sdir / "main.lua").write_text("return true\n", encoding="utf-8")
            (tdir / "test_sdk_features.lua").write_text(
                'describe("extended assertions", function()\n'
                '    it("rejects NaN and inf in assert_near while passing finite tolerance", function()\n'
                '        assert_near(0.3000001, 0.3, 1e-5)\n'
                '        assert_throws(function() assert_near(0 / 0, 1.0, 0.1) end, "non-finite")\n'
                '        assert_throws(function() assert_near(math.huge, math.huge, 0.1) end, "non-finite")\n'
                '    end)\n'
                '    it("compares nested and cyclic tables in assert_deep_eq", function()\n'
                '        assert_deep_eq({ a = 1, b = { x = "ok" } }, { a = 1, b = { x = "ok" } })\n'
                '        assert_throws(function()\n'
                '            assert_deep_eq({ payload = { sig = 8 } }, { payload = { sig = 9 } })\n'
                '        end, "payload.sig")\n'
                '        local c1, c2 = {}, {}\n'
                '        c1.self = c1\n'
                '        c2.self = c2\n'
                '        assert_deep_eq(c1, c2)\n'
                '    end)\n'
                'end)\n'
                'describe("dual dot/colon mocks and avionics registry", function()\n'
                '    it("normalizes dot and colon calls on mock.modem, mock.term, and mock.actuator", function()\n'
                '        local m = mock.modem()\n'
                '        m.open(101)\n'
                '        m:open(102)\n'
                '        m.transmit(101, 102, { cmd = "A" })\n'
                '        m:transmit(103, 104, { cmd = "B" })\n'
                '        assert_true(m.isOpen(101) and m:isOpen(102))\n'
                '        assert_eq(m._transmitted[1].tx, 101)\n'
                '        assert_eq(m._transmitted[2].tx, 103)\n'
                '        local scr = mock.term(20, 5)\n'
                '        scr.setCursorPos(1, 1)\n'
                '        scr:write("HELLO")\n'
                '        assert_true(scr:_contains("HELLO"))\n'
                '        local act = mock.actuator("bearing")\n'
                '        act.setSpeed(128)\n'
                '        assert_eq(act._lastSpeed, 128)\n'
                '        act:setSpeed(-64)\n'
                '        assert_eq(act._lastSpeed, -64)\n'
                '    end)\n'
                '    it("registers CC:Avionics sensors in mock.peripheral_registry", function()\n'
                '        mock.peripheral_registry({\n'
                '            left = { type = "gimbal_sensor", dev = mock.avionics_gimbal({ pitch = 2.5, roll = -1.0 }) },\n'
                '            right = { type = "altitude_sensor", dev = mock.avionics_altitude({ altitude = 120.5, verticalSpeed = 1.2 }) },\n'
                '        })\n'
                '        local g = peripheral.find("gimbal_sensor")\n'
                '        local a = peripheral.wrap("right")\n'
                '        assert_near(g.getAngles().pitch, 2.5, 1e-6)\n'
                '        assert_near(a.getAltitude(), 120.5, 1e-6)\n'
                '    end)\n'
                'end)\n',
                encoding="utf-8",
            )
            target = UnitTargetConfig(target_id="1_control/sdk_check", source_dir=sdir, tests_dir=tdir)
            rep = run_target_unit_tests(target, self.paths, root / "sessions")
            self.assertEqual(rep.status, "PASS", rep.errors or [t.error for t in rep.tests])
            self.assertEqual(rep.passed_tests, 4)
```

- [ ] **2단계: 테스트 실행 및 실패 확인**

실행 명령: `python -m unittest tests/harness/test_guest_sdk.py -v`
예상 결과: `attempt to call global 'assert_near' (a nil value)` 오류로 실패

- [ ] **3단계: `harness/unit/guest/test_sdk.lua` 구현 및 `engine.py` 연동**

- `assert_near`: `is_finite_number` 검사기를 통해 `NaN`, `math.huge`, `-math.huge` 입력 시 `"non-finite"` 메시지를 포함한 에러를 발생시킨다.
- `assert_deep_eq`: 테이블 순환 참조 방지 및 차이가 발생한 필드 경로(예: `root.payload.sig`)를 정확히 보고한다.
- 모든 Mock 메서드에 `strip_self` 정규화 래퍼를 적용하여 `obj.fn(...)` 및 `obj:fn(...)` 호출이 동일하게 동작하도록 한다.
- `mock.peripheral_registry`: 전달받은 가상 장치 맵으로 `_G.peripheral`을 교체하고 테스트 종료 시 자동 원복한다.

- [ ] **4단계: 테스트 실행 및 통과 확인**

실행 명령: `python -m unittest tests/harness/test_guest_sdk.py -v`
예상 결과: PASS (4개 게스트 케이스 통과)

- [ ] **5단계: 커밋**

```bash
git add harness/unit/guest/test_sdk.lua harness/unit/engine.py tests/harness/test_guest_sdk.py
git commit --only harness/unit/guest/test_sdk.lua harness/unit/engine.py tests/harness/test_guest_sdk.py -m "feat(harness): add Lua 5.2 assertion and Create Aeronautics mock SDK"
```

---

### Task 5: 멀티 코드베이스 CLI 러너 (`tools/run_unit_tests.py`)

**파일 목록:**
- 생성: `tools/run_unit_tests.py`
- 테스트: `tests/harness/test_cli_runner.py`

**인터페이스 명세:**
- 입력: `config.py`의 `discover_codebase_targets`, `resolve_craftos_paths`, `session.py`의 `clean_workspace_orphans`, `engine.py`의 `run_target_unit_tests`.
- 출력:
  - `build_arg_parser() -> argparse.ArgumentParser`
  - `run_cli(argv: list[str] | None = None, workspace_root: Path | None = None) -> tuple[int, dict[str, Any]]`
  - `main(argv: list[str] | None = None) -> int`
  - CLI 플래그: `--target <id_or_short_name>`, `--filter <substr>`, `--json`, `--require-tests`, `--clean-orphans`.

- [ ] **1단계: 실패하는 테스트 작성 (`tests/harness/test_cli_runner.py`)**

```python
import tempfile
import unittest
from pathlib import Path

from tools.run_unit_tests import run_cli


class TestCliRunner(unittest.TestCase):
    def test_cross_codebase_module_collision_isolation_and_exit_codes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            # 서로 다른 두 코드베이스가 동일한 이름의 modules/ui_renderer.lua를 가짐
            for layer_prog, tag in (("1_control/vas", "VAS_UI"), ("2_guidance/sas", "SAS_UI")):
                sdir = root / "src" / layer_prog / "modules"
                tdir = root / "tests" / layer_prog
                sdir.mkdir(parents=True)
                tdir.mkdir(parents=True)
                (sdir / "ui_renderer.lua").write_text(f'return {{ id = "{tag}" }}\n', encoding="utf-8")
                (tdir / "test_ui.lua").write_text(
                    f'local ui = require("ui_renderer")\n'
                    f'describe("{layer_prog}", function()\n'
                    f'    it("loads isolated ui_renderer", function()\n'
                    f'        assert_eq(ui.id, "{tag}")\n'
                    f'    end)\n'
                    f'end)\n',
                    encoding="utf-8",
                )
            # 소스는 있으나 테스트는 아직 없는 코드베이스
            untested = root / "src" / "0_infra" / "gps"
            untested.mkdir(parents=True)
            (untested / "main.lua").write_text("return true\n", encoding="utf-8")

            code_ok, payload_ok = run_cli(["--json"], workspace_root=root)
            self.assertEqual(code_ok, 0)
            statuses = {r["target_id"]: r["status"] for r in payload_ok["targets"]}
            self.assertEqual(statuses, {
                "0_infra/gps": "SKIP",
                "1_control/vas": "PASS",
                "2_guidance/sas": "PASS",
            })

            code_strict, _ = run_cli(["--require-tests"], workspace_root=root)
            self.assertEqual(code_strict, 1)
```

- [ ] **2단계: 테스트 실행 및 실패 확인**

실행 명령: `python -m unittest tests/harness/test_cli_runner.py -v`
예상 결과: `ModuleNotFoundError: No module named 'tools'` 오류로 실패

- [ ] **3단계: `tools/run_unit_tests.py` 구현**

- `sys.path`에 워크스페이스 루트를 자동 등록하여 루트에서 직접 실행할 수 있도록 한다.
- `run_cli` 구현:
  - `--clean-orphans` 처리 지원.
  - `discover_codebase_targets`를 통한 대상 선정 및 순차 실행.
  - `--json` 시 정형화된 JSON 출력, 기본 시 간결한 테이블 및 실패 진단 정보 출력.
  - 모든 대상이 정적 위반 0건, 실패 0건, 타임아웃 False인 경우 종료 코드 0, 그 외 1 반환 (`--require-tests` 지정 시 테스트 미보유 대상은 실패 처리).

- [ ] **4단계: 테스트 실행 및 통과 확인**

실행 명령: `python -m unittest discover -s tests/harness -v`
예상 결과: PASS (호스트 하네스 전체 단위 테스트 통과)

- [ ] **5단계: 커밋**

```bash
git add tools/run_unit_tests.py tests/harness/test_cli_runner.py
git commit --only tools/run_unit_tests.py tests/harness/test_cli_runner.py -m "feat(harness): add multi-codebase run_unit_tests CLI"
```

---

### Task 6: 활성 5개 코드베이스 대상 파일럿 단위 테스트 스위트 구축

**파일 목록:**
- 생성: `tests/1_control/tca/test_tca_core.lua`
- 생성: `tests/1_control/vas/test_vas_core.lua`
- 생성: `tests/2_guidance/sas/test_sas_core.lua`
- 생성: `tests/0_infra/gps/test_gps_core.lua`
- 생성: `tests/0_development/alignment/test_alignment_core.lua`

**인터페이스 명세:**
- 입력: `tools/run_unit_tests.py`, 게스트 `runner_lib.lua` + `test_sdk.lua`, `src/{0_development/alignment,0_infra/gps,1_control/tca,1_control/vas,2_guidance/sas}/`의 프로덕션 모듈 (읽기 전용 참조).
- 출력: `Create_Aeroneutics`의 모든 활성 도메인 패턴을 검증하는 실행 가능한 단위 테스트 스위트.

- [ ] **1단계: 테스트 미보유 상태에서 `--require-tests` 실패 확인**

실행 명령: `python tools/run_unit_tests.py --require-tests`
예상 결과: 5개 활성 코드베이스의 테스트 파일 부재로 종료 코드 `1` 및 실패 반환.

- [ ] **2단계: 5개 파일럿 단위 테스트 파일 작성**

각 코드베이스의 실제 모듈 계약과 런타임 특성을 검증하는 테스트 스위트를 작성한다:
- `tests/1_control/tca/test_tca_core.lua`:
  - `config_manager.load`/`save` 왕복 검증 (`aircraftIndexN = 2` -> `baseChannel = 10020`, `thrustActuation = 10026`).
  - `group_allocator.calculate_api_boosted_signal(8, 3, 4)` -> `s = 11`, `assert_near(r, 4.0 / 3.0, 0.01)`.
  - `tca_daemon`의 `DISARMED` 안전 절단(`appliedSignal == 0`) 및 `E_STOP` 쿠션 유지 로직 검증.
  - `_G.__TCA_SETUP_IMPORTED_ONLY = true`를 이용한 `tca_setup` 키 입력 모드 토글(`REDSTONE` <-> `API`) 및 UI 렌더링 검증.
- `tests/1_control/vas/test_vas_core.lua`:
  - `quat.normalize`, `quat.multiply`, `quat.error_quaternion`의 불변성 검증 (`assert_near(..., 1e-6)`).
  - `flight_dynamics_core.init` 및 적분기 리셋 검증.
  - `mock.peripheral_registry`를 이용한 `sensor_pipeline`의 `gimbal`, `altitude`, `velocity`, `fuel` 샘플링 및 건강성 판정 검증.
- `tests/2_guidance/sas/test_sas_core.lua`:
  - 스테이징된 `config/sas_config.json`의 정상 로드 검증 (하위 디렉토리 보존 확인).
  - `flight_fsm`의 지상 상태 전이(`BOOT_INIT` -> `DISARMED` -> `ARMING` -> `IDLE_ARMED` -> `TAKEOFF`) 및 비행 중 연료 부족 긴급 착륙(`EMERGENCY_LAND`) 전이 검증.
- `tests/0_infra/gps/test_gps_core.lua`:
  - `storage_hal.writeJsonAtomic` 및 `storage_hal.readJson`의 임시 CraftOS 파일시스템 원자적 저장/로드 검증.
  - `trilateration.projectHorizontal`, `selectOptimalNodes`, `solveLinearWLS`를 통한 기준 좌표 `(x = 30.0, z = -20.0)` 복원 정밀도 검증 (`assert_near(..., 1e-2)`).
- `tests/0_development/alignment/test_alignment_core.lua`:
  - `ols_regression_engine.identify_dominant_axis` 및 `calculate_regression`의 `dominantAxis == "surge"`, $R^2 \approx 1.0$ 검증.
  - `align_master.init_bay_session`의 격납고 채널 자동 개방 및 `hud_renderer` 인공수평선 렌더링 시 `BLIT_LENGTH_MISMATCH` 무결성 검증.

- [ ] **3단계: 전체 단위 테스트 및 호스트 하네스 검증 실행**

실행 명령: `python -m unittest discover -s tests/harness -v; python tools/run_unit_tests.py --require-tests`
예상 결과: 종료 코드 `0`으로 통과. 5개 대상(`0_development/alignment`, `0_infra/gps`, `1_control/tca`, `1_control/vas`, `2_guidance/sas`) 모두 정적 위반 0건, 실패 0건, 이벤트 삼킴 0건, UI 위반 0건으로 `[PASS]` 보고.

- [ ] **4단계: 커밋**

```bash
git add tests/1_control/tca/test_tca_core.lua tests/1_control/vas/test_vas_core.lua tests/2_guidance/sas/test_sas_core.lua tests/0_infra/gps/test_gps_core.lua tests/0_development/alignment/test_alignment_core.lua
git commit --only tests/1_control/tca/test_tca_core.lua tests/1_control/vas/test_vas_core.lua tests/2_guidance/sas/test_sas_core.lua tests/0_infra/gps/test_gps_core.lua tests/0_development/alignment/test_alignment_core.lua -m "test: add universal pilot unit test suites across all 5 active codebases"
```
