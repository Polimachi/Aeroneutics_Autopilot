# TASK-113: 온보드 제어기(VAS, TCA, ASA) `parallel` 비동기 디버그 TUI 분리 및 헤드리스 전환 옵션 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 온보드 비행 제어기(Node 01 VAS, Node 02 TCA, Node 06 ASA)의 메인 루프에서 기존 동기식 터미널 렌더링을 제거하고, 기본값 `debug: true` 하에서 ComputerCraft `parallel.waitForAny` 기반 비동기 코루틴으로 TUI 렌더러와 20Hz 제어 코어를 분리하여 실시간 제어 루프의 무결성을 보장하며, `debug: false` 설정 시 완전 헤드리스(Headless, 터미널 렌더링 0%)로 구동되도록 개편한다.

**Architecture:** 제어 코어 루프(20Hz 타이머/모뎀 이벤트 처리)와 터미널 렌더러(5Hz 저주기 UI 갱신 및 키 입력)를 물리적으로 완전 격리한다. 기본값(`debug: true`)에서는 CC `parallel.waitForAny` 코루틴 스케줄러를 통해 렌더러가 독립 5Hz 타이머로 동작하도록 하여 UI 렌더링 지연이 20Hz 비행 제어 타이밍에 전파되지 않도록 설계하고, `debug: false` 설정 시에는 터미널 초기화 및 화면 그리기 함수 호출을 완전히 우회하여 CPU 예산 소모를 0으로 만드는 순수 헤드리스 모드로 동작한다.

**Tech Stack:** CC:Tweaked Lua 5.2 / Cobalt, ComputerCraft `parallel` API, `os.startTimer`, `term.blit`, CraftOS-PC 단위 테스트 하네스 (`test_sdk.lua`).

**Spec:**
- `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (v1.15.0 -> v1.16.0)
- `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (v1.9.1 -> v1.10.0)
- `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (v1.4.0 -> v1.5.0)

## Global Constraints

- **Multi-Codebase Autonomy**: `src/1_control/vas/`, `src/1_control/tca/`, `src/1_control/asa/`는 공용 코드 없이 독립 완결성을 유지한다.
- **Default `debug = true` with Async Isolation**: 모든 제어기는 기본적으로 `debug = true`를 유지하되, 동기식 렌더링이 아닌 `parallel.waitForAny` 기반의 비동기 코루틴으로 TUI를 구동한다.
- **Pure Headless on `debug = false`**: `debug: false`가 명시되면 터미널 화면 조작(`term.clear()`, `term.blit()`, `write()`)을 일체 수행하지 않고 단일 상태 요약 라인만 출력한다.
- **Zero-Blocking Realtime Guarantee**: 20Hz 제어 루프(`os.pullEventRaw` / `os.pullEvent`) 내에서 렌더링 함수를 동기식으로 직접 호출하지 않는다.
- **Coroutine Fault Isolation**: `parallel.waitForAny` 디버그 구동 중 TUI 코루틴 내 렌더링 오류가 발생하더라도 제어 코어 루프가 강제 중단되지 않도록 보호한다.
- **Spec Status Protocol**: 사양 개정 착수 시 `Approved`로 전이하고, 검증 통과 후 `Implemented`로 자동 환원한다 (ASA는 TASK-105 연기에 따라 `Approved` 유지).

## Review Focus

1. **기본값 `debug = true` 시 비동기 격리**: 기본 설정 부재 또는 `debug` 미지정 시 기본값 `true`로 해석되어 `parallel.waitForAny`를 통해 20Hz 제어 루프의 지연 없이 5Hz 비동기 TUI가 구동되는가.
2. **`debug = false` 시 Headless 터미널 조작 완전 배제**: `debug: false` 시 `term.clear()`, `term.setCursorPos()` 등 화면 지우기나 프레임버퍼 그리기가 단 1회도 발생하지 않는가.
3. **`parallel` 코루틴 간 타이머 이벤트 충돌 방지**: 20Hz 제어 타이머(`state.timerId`)와 5Hz UI 타이머(`uiTimerId`)가 서로의 `os.pullEvent` 핸들러에서 오인 처리되지 않고 각자 격리되는가.
4. **디버그 TUI 종료 신호 전파**: TUI에서 `q` 또는 `t` 키를 누르거나 제어 코어가 셧다운될 때 `parallel.waitForAny`가 두 코루틴 모두를 깔끔하게 정상 종료하고 터미널을 복구하는가.
5. **CraftOS-PC 단위 테스트 하네스 호환성**: `parallel` API가 없는 목(Mock) 환경 또는 비GUI 헤드리스 테스트 환경에서도 syntax error나 nil 참조 없이 테스트가 통과하는가.

---

### Task 1: 제어기 사양서 규격 개정 (VAS, TCA, ASA)

**Files:**
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md`
- Validate: `tools/verify_all_specs.py`, `tools/verify_spec_status.py`

**Interfaces:**
- Consumes: VICD-Spec 3-Layer Sandwich 아키텍처 및 40채널 전역 ICD 규약
- Produces: `debug: boolean (default: true)` 설정 스키마 및 `parallel.waitForAny` 비동기 디버그 뷰 / `debug: false` 헤드리스 전환 명세

- [ ] **Step 1: 현재 사양서 및 상태 무결성 확인**

Run: `python tools/verify_all_specs.py; python tools/verify_spec_status.py`  
Expected: ALL 12 SPECS CLEAN, 7 Implemented, 5 Approved PASS.

- [ ] **Step 2: `VAS_PROGRAM_SPECIFICATION.md` 규격 개정**

메타데이터 테이블 갱신:
- 문서 상태: `Approved`
- 문서 버전: `v1.16.0`
- 최종 수정일: `2026-11-08`

Section 1.1 및 Section 5.12 (`ui_renderer`), Section 6 명세 갱신:
- 디버그 TUI 기본 구동: `system.json` 내 `debug: true` (기본값)
- 비동기 코루틴 분리: CC `parallel.waitForAny` 기반 20Hz 제어 코어 + 5Hz 비동기 HUD 렌더러 분리 격리
- 헤드리스 옵션: `debug: false` 명시 시 터미널 렌더링 0% 헤드리스 모드로 직결 구동
- Revision History에 `v1.16.0` 행 추가.

- [ ] **Step 3: `TCA_PROGRAM_SPECIFICATION.md` 규격 개정**

메타데이터 테이블 갱신:
- 문서 상태: `Approved`
- 문서 버전: `v1.10.0`
- 최종 수정일: `2026-11-08`

Section 3 (설정 스키마) 및 Section 4.8 (`tui_dashboard`), Section 5 명세 갱신:
- 디버그 TUI 기본 구동: `config.json` 스키마 `debug: true` (기본값)
- 비동기 코루틴 분리: `debug == true` 시 `parallel.waitForAny` 기반 `run_daemon`과 `run_tui` 비동기 분리
- 헤드리스 옵션: `debug: false` 명시 시 터미널 렌더링 완전 배제
- Revision History에 `v1.10.0` 행 추가.

- [ ] **Step 4: `ASA_PROGRAM_SPECIFICATION.md` 규격 개정**

메타데이터 테이블 갱신:
- 문서 상태: `Approved` (유지)
- 문서 버전: `v1.5.0`
- 최종 수정일: `2026-11-08`

Section 1.2, Section 3 (설정 스키마) 및 Section 6.1 (메인 데몬) 명세 갱신:
- 디버그 TUI 기본 구동: `config.json` 스키마 `debug: true` (기본값)
- 비동기 코루틴 분리: `debug == true` 시 `parallel.waitForAny` 기반 비동기 진단 뷰 표출
- 헤드리스 옵션: `debug: false` 명시 시 헤드리스 직결 구동
- Revision History에 `v1.5.0` 행 추가.

- [ ] **Step 5: 정적 사양서 유효성 검사**

Run: `python tools/verify_all_specs.py; python tools/verify_spec_status.py`  
Expected: ALL 12 SPECS CLEAN, 5 Implemented, 7 Approved PASS.

- [ ] **Step 6: 커밋**

```bash
git add docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md
git commit -m "docs(specs): specify parallel async debug TUI default and headless option for VAS, TCA, ASA"
```

---

### Task 2: 설정 로더 스키마 표준화 (`debug: true` 기본값)

**Files:**
- Modify: `src/1_control/vas/modules/core_daemon.lua`
- Modify: `src/1_control/tca/modules/config_manager.lua`
- Create: `src/1_control/asa/modules/config_manager.lua`
- Test: `tests/1_control/vas/test_vas_core.lua`
- Test: `tests/1_control/tca/test_tca_core.lua`
- Test: `tests/1_control/asa/test_asa_core.lua`

**Interfaces:**
- Consumes: JSON 설정 파일 또는 인라인 테이블
- Produces: `cfg.debug` (또는 `cfg.system.debug`) 불리언 플래그(`true` 기본값)가 보장된 정규화 설정 객체

- [ ] **Step 1: VAS/TCA/ASA 설정 로더에 `debug` 플래그 테스트 작성**

In `tests/1_control/vas/test_vas_core.lua`:
- `core_daemon.init()` 시 `system.debug`가 누락되었을 때 기본값 `true`로 주입되는지 검증하는 테스트 추가.
- `system.debug = false` 명시 시 `false`가 유지되는지 검증.

In `tests/1_control/tca/test_tca_core.lua`:
- `config_manager.load()` 시 `debug` 필드가 누락되었을 때 기본값 `true`로 주입되는지 검증하는 테스트 추가.
- `debug = false` 명시 시 `false`가 유지되는지 검증.

In `tests/1_control/asa/test_asa_core.lua`:
- `config_manager.load()` 및 `config_manager.default_config()`가 `debug = true`를 포함하여 정상 생성되는지 검증하는 테스트 추가.

- [ ] **Step 2: 테스트 실행 및 실패 확인**

Run: `python tools/run_unit_tests.py --require-tests`  
Expected: FAIL (ASA config_manager 모듈 미존재 또는 debug 기본값 assertion 불일치)

- [ ] **Step 3: `src/1_control/vas/modules/core_daemon.lua` 구현**

- `core_daemon.init` 내부에서 `cfg.system` 테이블을 점검하여:
  `if cfg.system.debug == nil then cfg.system.debug = true else cfg.system.debug = (cfg.system.debug == true) end`
- 만약 루트 디렉토리에 `config.json`이 있고 그 안에 `debug`가 정의되어 있다면 이를 `system.debug`에 안전하게 반영.

- [ ] **Step 4: `src/1_control/tca/modules/config_manager.lua` 구현**

- `default_cfg` 내 `debug = true` 추가.
- `config_manager.load()` 시:
  `if cfg.debug == nil then cfg.debug = true else cfg.debug = (cfg.debug == true) end`
- `config_manager.save()` 시 `debug` 필드 영속화 지원.

- [ ] **Step 5: `src/1_control/asa/modules/config_manager.lua` 구현**

- ASA 표준 설정 관리자 신규 작성:
  - `compute_base(aircraftIndexN)`: 40채널 공식 $10000 + (N-1) \times 40$ 준수.
  - `default_config()`: `debug = true`, `aircraftIndexN = 1`, `baseChannel = 10000`, `channels = { surfaceActuation = 10011 }`, `ports = { modemSide = "top", redstoneSide = "bottom" }`, `watchdogTimeoutMs = 300`, `aircraftDomainId = "AIRCRAFT_01"`.
  - `load(path)` & `save(path, cfg)`: JSON 파일 로드/저장 및 `debug` 기본값(`true`) 보장.

- [ ] **Step 6: 단위 테스트 실행 및 통과 확인**

Run: `python tools/run_unit_tests.py --require-tests`  
Expected: PASS

- [ ] **Step 7: 커밋**

```bash
git add src/1_control/vas/modules/core_daemon.lua src/1_control/tca/modules/config_manager.lua src/1_control/asa/modules/config_manager.lua tests/1_control/vas/test_vas_core.lua tests/1_control/tca/test_tca_core.lua tests/1_control/asa/test_asa_core.lua
git commit -m "feat(control): standardize debug flag with default true in config loaders for VAS, TCA, ASA"
```

---

### Task 3: VAS `parallel` 비동기 `ui_renderer` 분리 및 헤드리스 전환

**Files:**
- Modify: `src/1_control/vas/main.lua`
- Modify: `src/1_control/vas/modules/ui_renderer.lua`
- Test: `tests/1_control/vas/test_vas_core.lua`

**Interfaces:**
- Consumes: `core_daemon.handle_event`, `ui_renderer.render_dashboard`, `parallel.waitForAny`
- Produces: 제어 코어와 UI 렌더러가 비동기로 격리된 VAS 메인 엔트리포인트 (debug: true 비동기 TUI, debug: false 헤드리스)

- [ ] **Step 1: VAS 비동기 `ui_renderer` 및 헤드리스 격리 단위 테스트 작성**

In `tests/1_control/vas/test_vas_core.lua`:
- `ui_renderer` 렌더링 검증: 목 터미널(`mock.terminal`)을 전달하여 `ui_renderer.render_dashboard`가 51x19 크기에 맞는 blit 문자열을 오류 없이 생성하는지 검증.
- 디버그 TUI 모드 검증: `state.cfg.system.debug ~= false`일 때 `parallel` 기반 비동기 코루틴 루프가 분리 가동되는지 검증.
- 헤드리스 모드 검증: `state.cfg.system.debug = false`일 때 터미널 clear/draw 함수가 호출되지 않는지 검증.

- [ ] **Step 2: 테스트 실행 및 실패 확인**

Run: `python tools/run_unit_tests.py --require-tests`  
Expected: FAIL (테스트 케이스 미구현 또는 main.lua 비동기 구조 미지원)

- [ ] **Step 3: `src/1_control/vas/modules/ui_renderer.lua` 정제**

- 화면 초기화(`clear_screen`) 및 복구 헬퍼 함수 추가.
- `render_dashboard` 진입 전 `surf` 유효성 검사 강화.

- [ ] **Step 4: `src/1_control/vas/main.lua` 리팩토링**

구조 개편:
```lua
local function run_daemon(state)
    while state.running do
        local event, p1, p2, p3, p4 = os.pullEventRaw()
        core_daemon.handle_event(state, event, p1, p2, p3, p4)
        if _G.__HARNESS_HIL_MODE and state.tickCount >= 10 then
            core_daemon.shutdown(state, "HIL_COMPLETE")
        end
    end
end

local function run_tui(state)
    if term and term.clear then
        term.setBackgroundColor(colors.black)
        term.clear()
    end
    ui_renderer.render_dashboard(term, state)

    local uiTimer = os.startTimer(0.2) -- 5Hz 비동기 UI 주기
    while state.running do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "timer" and p1 == uiTimer then
            ui_renderer.render_dashboard(term, state)
            uiTimer = os.startTimer(0.2)
        elseif event == "key" then
            if p1 == ((keys and keys.q) or 16) or p1 == ((keys and keys.t) or 20) then
                state.running = false
                break
            end
        end
    end
end
```
엔트리 분기:
- `state.cfg.system.debug ~= false` (기본값): `parallel.waitForAny(function() run_daemon(state) end, function() run_tui(state) end)`
- `state.cfg.system.debug == false`: 터미널 조작 없이 `[VAS] Core running in HEADLESS mode (Node 01, Base: %d)` 1줄 출력 후 `run_daemon(state)` 단독 직결 실행.
- 단위 테스트 환경(`_G.describe ~= nil`)에서는 자동 루프 진입을 방지하고 `main` / `run_daemon` / `run_tui` 모듈 인터페이스를 반환.

- [ ] **Step 5: 단위 테스트 실행 및 통과 확인**

Run: `python tools/run_unit_tests.py --require-tests`  
Expected: PASS (1_control/vas 전 케이스 통과)

- [ ] **Step 6: 커밋**

```bash
git add src/1_control/vas/main.lua src/1_control/vas/modules/ui_renderer.lua tests/1_control/vas/test_vas_core.lua
git commit -m "feat(vas): isolate ui_renderer with parallel async TUI by default and headless option"
```

---

### Task 4: TCA `parallel` 비동기 `tui_dashboard` 분리 및 헤드리스 전환

**Files:**
- Modify: `src/1_control/tca/main.lua`
- Modify: `src/1_control/tca/modules/tui_dashboard.lua`
- Test: `tests/1_control/tca/test_tca_core.lua`

**Interfaces:**
- Consumes: `tca_daemon`, `tui_dashboard.render_full_screen`, `parallel.waitForAny`
- Produces: 터미널 렌더링 부하가 20Hz 코어와 격리된 TCA 구동계 데몬 (debug: true 비동기 TUI, debug: false 헤드리스)

- [ ] **Step 1: TCA 비동기 `tui_dashboard` 및 헤드리스 격리 단위 테스트 작성**

In `tests/1_control/tca/test_tca_core.lua`:
- `tui_dashboard.render_full_screen` 렌더링 무결성 검증 (정상 blit 출력 및 게이지 계산).
- `cfg.debug ~= false` (기본값) 시 비동기 UI 코루틴이 `isDirty` 또는 UI 타이머 기반으로 화면을 갱신하는지 검증.
- `cfg.debug = false` 시 화면 렌더링 호출 없이 이벤트 스텝이 정상 수행되는지 검증.

- [ ] **Step 2: 테스트 실행 및 실패 확인**

Run: `python tools/run_unit_tests.py --require-tests`  
Expected: FAIL

- [ ] **Step 3: `src/1_control/tca/main.lua` 리팩토링**

구조 개편:
```lua
local function run_daemon(daemon, activeCfg)
    while true do
        local ev, p1, p2, p3, p4 = os.pullEvent()
        if ev == "terminate" then
            daemon:pause()
            break
        else
            local ok, keepGoing = pcall(daemon.step_event, daemon, ev, p1, p2, p3, p4)
            if not ok then
                daemon:push_log("[ERR] " .. tostring(keepGoing):sub(1, 35))
            elseif keepGoing == false then
                break
            end
        end
    end
end

local function run_tui(daemon, activeCfg, modemDev)
    tui_dashboard.render_full_screen(activeCfg, daemon)
    local uiTimer = os.startTimer(0.2)
    while true do
        local ev, p1, p2 = os.pullEvent()
        if ev == "key" then
            local cont, nextCfg = handle_key_event(daemon, p1, activeCfg, modemDev)
            activeCfg = nextCfg
            if not cont then break end
        elseif ev == "timer" and p1 == uiTimer then
            if daemon.isDirty then
                tui_dashboard.render_full_screen(activeCfg, daemon)
                daemon.isDirty = false
            end
            uiTimer = os.startTimer(0.2)
        end
    end
end
```
엔트리 분기:
- `cfg.debug ~= false` (기본값): `parallel.waitForAny(function() run_daemon(daemon, cfg) end, function() run_tui(daemon, cfg, modem) end)`
- `cfg.debug == false`: 터미널 조작 없이 `[TCA] Actuator daemon running in HEADLESS mode (Group: %s, Base: %d)` 1줄 출력 후 `run_daemon(daemon, cfg)` 직결 실행.
- 테스트 환경(`_G.describe ~= nil`) 가드 적용.

- [ ] **Step 4: 단위 테스트 실행 및 통과 확인**

Run: `python tools/run_unit_tests.py --require-tests`  
Expected: PASS (1_control/tca 전 케이스 통과)

- [ ] **Step 5: 커밋**

```bash
git add src/1_control/tca/main.lua src/1_control/tca/modules/tui_dashboard.lua tests/1_control/tca/test_tca_core.lua
git commit -m "feat(tca): isolate tui_dashboard with parallel async TUI by default and headless option"
```

---

### Task 5: ASA 비동기 디버그 뷰, 메인 루프 및 단위 테스트 구축

**Files:**
- Create: `src/1_control/asa/modules/tui_dashboard.lua`
- Create: `src/1_control/asa/main.lua`
- Test: `tests/1_control/asa/test_asa_core.lua`

**Interfaces:**
- Consumes: `control_surface_mapper`, `config_manager`, `parallel.waitForAny`
- Produces: `debug: true` 기본값 비동기 51x19 진단 TUI 및 `debug: false` 헤드리스 옵션을 갖춘 ASA 엔트리포인트

- [ ] **Step 1: ASA 메인 루프 및 TUI 대시보드 단위 테스트 작성**

In `tests/1_control/asa/test_asa_core.lua`:
- `tui_dashboard` 렌더링 검증: 조종면 슬롯(elevator, leftAileron, rightAileron, rudder)의 타각/상태가 51x19 터미널에 정상 blit 출력되는지 검증.
- `main.lua` 기본 디버그 실행 검증: `cfg.debug ~= false` 시 비동기 TUI 코루틴과 데몬이 `parallel` 구조로 바인딩되는지 검증.
- `main.lua` 헤드리스 실행 검증: `cfg.debug = false` 시 터미널 조작 없이 이벤트 루프가 구동되는지 검증.

- [ ] **Step 2: 테스트 실행 및 실패 확인**

Run: `python tools/run_unit_tests.py --require-tests`  
Expected: FAIL (tui_dashboard 및 main 모듈 부재)

- [ ] **Step 3: `src/1_control/asa/modules/tui_dashboard.lua` 구현**

- 51x19 터미널 진단 뷰 구현:
  - Header: `ASA Surface Cluster | Node 06 | Airframe: <domainId> | Base: <baseChannel>`
  - Body: 엘리베이터, 좌/우 에일러론, 러더, 플랩의 할당 모드(`API`/`REDSTONE`), 현재 타각(`deg` 또는 `RS 0~15`), 포화 경고(`SAT`) 게이지 표출.
  - Footer: FSM 상태(`ARMED_NORMAL`, `SAFE_GLIDE`), 워치독 상태, 단말 조작 단축키 안내.

- [ ] **Step 4: `src/1_control/asa/main.lua` 구현**

- `config_manager.load("config.json")`로 설정 로드 (부재 시 `debug = true` 기본값 생성).
- `control_surface_mapper.scan(peripheral)`을 통한 조종면 자동 탐색 바인딩.
- `run_daemon`과 `run_tui` 분리:
  - `debug ~= false` (기본값): `parallel.waitForAny(run_daemon, run_tui)`로 비동기 진단 대시보드 구동.
  - `debug == false`: `[ASA] Surface daemon running in HEADLESS mode (Base: %d, Mode: %s)` 1줄 출력 후 데몬 루프 직결.
- 테스트 환경(`_G.describe ~= nil`) 가드 적용.

- [ ] **Step 5: 단위 테스트 실행 및 통과 확인**

Run: `python tools/run_unit_tests.py --require-tests`  
Expected: PASS (1_control/asa 전 케이스 통과)

- [ ] **Step 6: 커밋**

```bash
git add src/1_control/asa/main.lua src/1_control/asa/modules/tui_dashboard.lua tests/1_control/asa/test_asa_core.lua
git commit -m "feat(asa): implement parallel async tui_dashboard by default with headless option"
```

---

### Task 6: 전역 회귀 검증, 사양서 `Implemented` 환원 및 마일스톤 인계

**Files:**
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md`
- Modify: `TASK.md`
- Modify: `GEMINI.md`
- Validate: `tools/run_unit_tests.py`, `tools/verify_all_specs.py`, `tools/validate_lua_syntax.py`, `tools/verify_spec_status.py`

**Interfaces:**
- Consumes: 전역 단위 테스트 및 사양서 무결성 검사기
- Produces: 146+개 테스트 PASS 증거, 사양서 `Implemented` 상태 갱신, 동기화된 태스크 SSOT

- [ ] **Step 1: 전체 단위 테스트 및 문법 정적 검증**

Run:
```bash
python tools/validate_lua_syntax.py
python tools/run_unit_tests.py --require-tests --clean-orphans
python -m unittest discover -s tests/harness -p "test_*.py"
```
Expected: All Lua files syntax OK, all unit test targets PASS, 24/24 harness tests PASS.

- [ ] **Step 2: 사양서 상태 환원 (`Implemented`) 및 정적 무결성 검증**

- `VAS_PROGRAM_SPECIFICATION.md`: `문서 상태`를 `Implemented`로 환원, 최종 수정일 `2026-11-08` 유지.
- `TCA_PROGRAM_SPECIFICATION.md`: `문서 상태`를 `Implemented`로 환원, 최종 수정일 `2026-11-08` 유지.
- `ASA_PROGRAM_SPECIFICATION.md`: TASK-105 연기에 따라 `Approved` 상태 유지.
- Run: `python tools/verify_all_specs.py; python tools/verify_spec_status.py`  
Expected: ALL 12 SPECS CLEAN (7 Implemented, 5 Approved PASS).

- [ ] **Step 3: `TASK.md` 및 `GEMINI.md` 갱신**

- `TASK.md`:
  - `TASK-113` 및 하위 작업 113-1 ~ 113-5를 `[x]` (완료)로 전이하고 완료 이력 상단에 기록.
  - 다음 우선 과제 활성화 (TASK-200 AMM 또는 TASK-110 FCP VTOL).
- `GEMINI.md`:
  - 80줄 상한 준수 하에 직전 완료 작업을 `TASK-113`으로 갱신하고 최신 스냅샷 동기화.

- [ ] **Step 4: 마일스톤 최종 커밋**

```bash
git add docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md TASK.md GEMINI.md
git commit -m "chore(task): complete TASK-113 parallel async debug TUI and headless refactor for onboard controllers"
```
