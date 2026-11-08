# TASK-111: 멀티노드 종단간(E2E) 패킷 시퀀스 통합 시뮬레이션 테스트 구축 계획서

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 분산 CC:Tweaked 노드(`GCS`, `AMM`, `FCP`, `VAS`, `TCA`, `ASA`, `GPS`, `Alignment`, `Landing Pad`)의 실제 소스 코드를 격리 샌드박스에서 구동하고 가상 RF 네트워크 버스(`VirtualBus`)를 통해 연결하여 마스터 ICD 및 시퀀스 다이어그램 규격의 6대 핵심 다중 틱 패킷 교환 시나리오를 통합 검증하는 완전 자동화 E2E 시뮬레이션 프레임워크를 구축한다.

**Architecture:**
1. **가상 RF 네트워크 버스 (`harness/simulation/virtual_bus.lua`)**: CC:Tweaked 유/무선 모뎀(`open`, `close`, `isOpen`, `transmit`) 물리 동작 및 전역 채널 매핑(`0~65535`)을 모사하고 모든 전송 패킷을 기록/추적하는 가상 통신 버스.
2. **멀티노드 게스트 샌드박스 (`harness/simulation/node_sandbox.lua`)**: 9개 대상 서브시스템의 프로덕션 코드(`src/`)를 전역 오염 없이 독립 실행할 수 있도록 `_ENV`, 격리 `package.loaded`, 노드별 가상 `fs`, 그리고 가상 모뎀을 주입하는 경량 샌드박스.
3. **E2E 시뮬레이션 실행기 CLI (`tools/run_e2e_tests.py`)**: CraftOS-PC 헤드리스 인스턴스에서 통합 시나리오 테스트 슈트(`tests/e2e/test_e2e_*.lua`)를 구동하고 JSON/콘솔 리포트를 생성하는 자동화 도구.
4. **6대 핵심 종단간 시나리오 슈트 (`tests/e2e/`)**: GCS 부트스트랩/텔레메트리, AMM-FCP-VAS-구동계 유도 폐루프, 고정밀 GPS 10Hz 측위 융합, 격납고 Alignment 다단 펄스/OLS 식별 세션, 원격 C2 오버라이드 및 하드 E-STOP 차단, GAC-착륙패드 3-Tier 전술 착륙을 단계별 검증.

**Tech Stack:** CC:Tweaked Lua 5.2 / Cobalt, CraftOS-PC Console (Headless), Python 3.12 unittest/subprocess, UAFS Envelope v1.9.5, ICD Master Channels ($BW=40$).

**Spec:**
- [docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md) (v1.23.0)
- [docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md](../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (v2.10.0)
- [docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md](../specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md) (v1.0.0)
- [docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md](../specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md) (v1.0.0)
- [docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md](../specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md) (v1.13.0)
- [docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md](../specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md) (v1.16.0)
- [docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md](../specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md) (v1.10.0)
- [docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md](../specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md) (v1.5.0)
- [docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md](../specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md) (v2.2.1)
- [docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md](../specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md) (v2.5.1)
- [docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md](../specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md) (v2.4.0)

## Global Constraints

- 모든 통신 패킷은 UAFS Envelope v1.9.5 표준 스키마(`ver = "1.9.5"`, `domainId`, `seq`, `type`, `time`, `payload`)를 준수한다.
- 비행체 채널 할당은 40채널 블록($BW=40$, $Base = 10000 + (N-1)\times 40$) 및 4대 기능 Zone(Zone 1: 코어, Zone 2: 구동계, Zone 3: 탑재체, Zone 4: 편대)을 준수한다.
- CC 컴퓨터 루트 마운트 격리 원칙에 따라 `src/<layer>/<name>/` 간 공용 모듈 직접 상호 참조는 일체 금지되며 오직 모뎀 RF 패킷 교환으로만 통신한다.
- 런타임 코드 내 Zero-Fallback 원칙을 엄수하며 `[DEPRECATED]` 구버전 필드(구 Base+6, Base+7 등)는 송수신단 모두 배제한다.
- 테스트 러너와 E2E 시뮬레이션은 결정론적(Deterministic) 다중 틱 방식으로 구동되어 비동기 슬립 레이스 컨디션 없이 즉각 검증된다.

## Review Focus

1. **노드 간 환경 격리 실패 (Namespace Leak)**: `AMM`, `GCS`, `FCP`, `VAS`가 모두 `modules/network_manager.lua`를 가질 때 `package.loaded` 오염으로 잘못된 모듈을 호출하는 현상 방지.
2. **RF 채널 개폐 타이밍 위반**: 발신 노드가 패킷을 송신할 때 수신 노드가 해당 채널을 `modem.open()`하지 않아 패킷이 유실되는 현상 방지 (부트스트랩/교정 핸드셰이크 순서 엄수).
3. **GCS C2 오버라이드 시 AMM 반향 방지**: GCS가 `Base+0`으로 `GCS_OVERRIDE` 명령 송출 시 온보드 AMM이 이를 감청하여 큐를 안전 정지하되 자체 재송신 루프를 돌리지 않는지 확인.
4. **하드 비상차단(E-STOP) 직결 인터록**: GCS/조종사가 `Base+1`로 `MSG_EMERGENCY_OVERRIDE` 송신 시 FCP 경유 없이 VAS가 즉시 0-틱 차단하여 TCA/ASA 출력을 0으로 동결하는지 확인.
5. **GPS 조기 연산 타임아웃 및 융합**: 10Hz 주기적 핑 송출 시 4개 이상 스웜 거리 보고 수신 후 서버가 50ms 내 조기 연산 응답을 `Base+5`로 회신하고 FCP가 좌표를 수용하는지 확인.

---

### Task 1: 가상 RF 네트워크 버스 및 패킷 트레이서 (`virtual_bus.lua`)

**Files:**
- Create: `harness/simulation/virtual_bus.lua`
- Test: `tests/harness/test_virtual_bus.lua`

**Interfaces:**
- Consumes: CC:Tweaked standard peripheral model
- Produces: `virtual_bus.create_bus() -> bus`, `bus:create_modem(node_id) -> modem`, `bus:step()`, `bus:transmit()`, `bus.packet_log`, `bus:find_packets(filter)`

- [ ] **Step 1: Write the failing test**

```lua
-- tests/harness/test_virtual_bus.lua
local virtual_bus = require("virtual_bus")

describe("virtual_bus RF modem router", function()
    it("routes packets between nodes listening on open channels", function()
        local bus = virtual_bus.create_bus()
        local m1 = bus:create_modem("NODE_A")
        local m2 = bus:create_modem("NODE_B")

        m2:open(50000)
        assert_true(m2:isOpen(50000))
        assert_false(m1:isOpen(50000))

        m1:transmit(50000, 10000, { ver = "1.9.5", type = "TEST_PING" })
        bus:step()

        assert_eq(#bus.packet_log, 1)
        assert_eq(bus.packet_log[1].from, "NODE_A")
        assert_eq(bus.packet_log[1].channel, 50000)
        assert_eq(bus.packet_log[1].replyChannel, 10000)
        assert_eq(#m2.inbox, 1)
        assert_eq(m2.inbox[1].payload.type, "TEST_PING")
    end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python tools/run_unit_tests.py --target 0_development/sensors` (or verify virtual_bus not yet implemented)
Expected: FAIL / Module not found

- [ ] **Step 3: Implement `virtual_bus.create_bus()` in `harness/simulation/virtual_bus.lua`**

Implement bus router supporting:
- `open(channel)`, `close(channel)`, `isOpen(channel)` per modem instance.
- `transmit(channel, replyChannel, payload)` pushing to bus pending queue.
- `step()` delivering pending messages to all registered modems having `channel` open, storing into `modem.inbox` and `bus.packet_log`.
- `find_packets(filter)` searching `bus.packet_log` by `type`, `channel`, `from`.

- [ ] **Step 4: Run test to verify it passes**

Run: `python tests/harness/test_cli_runner.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add harness/simulation/virtual_bus.lua tests/harness/test_virtual_bus.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(sim): implement virtual RF network bus and packet tracer"
```

---

### Task 2: 멀티노드 격리 게스트 샌드박스 (`node_sandbox.lua`)

**Files:**
- Create: `harness/simulation/node_sandbox.lua`
- Test: `tests/harness/test_node_sandbox.lua`

**Interfaces:**
- Consumes: `virtual_bus.create_bus()`, target source directories in `src/`
- Produces: `node_sandbox.create_node(bus, node_id, src_dir, opts) -> node_instance`
  - `node:require(module_name) -> module`
  - `node:call(func_name, ...) -> ...`
  - `node:drain_inbox() -> count`

- [ ] **Step 1: Write the failing test**

```lua
-- tests/harness/test_node_sandbox.lua
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("node_sandbox environment isolation", function()
    it("isolates package.loaded and global namespaces between two nodes", function()
        local bus = virtual_bus.create_bus()
        local node_gcs = node_sandbox.create_node(bus, "GCS", "src/0_infra/gcs")
        local node_amm = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")

        local gcs_net = node_gcs:require("network_manager")
        local amm_net = node_amm:require("network_manager")

        assert_not_nil(gcs_net)
        assert_not_nil(amm_net)
        assert_ne(gcs_net, amm_net, "network_manager must be independently loaded")
    end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: Check failure of `node_sandbox` require.
Expected: FAIL with module not found

- [ ] **Step 3: Implement `node_sandbox.lua`**

Implement:
- Sandbox table `env` with custom `_G = env`, private `package.loaded = {}`, custom `package.path` pointing to node's root and `modules/`.
- Custom `peripheral` table hooking `wrap("top")` / `find("modem")` to `bus:create_modem(node_id)`.
- Custom `fs` wrapper resolving relative configuration paths (`config/*.json`) to the node's directory.
- `node:step(dt)` method to dispatch inbound modem messages from `inbox` to `os.queueEvent("modem_message", ...)`.

- [ ] **Step 4: Run test to verify it passes**

Run: Unit verification of node sandbox.
Expected: PASS

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add harness/simulation/node_sandbox.lua tests/harness/test_node_sandbox.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(sim): implement multi-node isolated guest sandbox"
```

---

### Task 3: E2E 시뮬레이션 CLI 러너 및 하네스 연동 (`run_e2e_tests.py`)

**Files:**
- Create: `tools/run_e2e_tests.py`
- Create: `tests/harness/test_e2e_runner.py`
- Modify: `tests/harness/test_tools_integrity.py`

**Interfaces:**
- Consumes: `harness/unit/session.py`, `CraftOSPaths`
- Produces: CLI `python tools/run_e2e_tests.py [--filter <substr>] [--json] [--clean-orphans]` returning exit code 0 on PASS, 1 on FAIL.

- [ ] **Step 1: Write the failing test**

```python
# tests/harness/test_e2e_runner.py
import unittest
from tools.run_e2e_tests import run_e2e_cli

class TestE2ERunner(unittest.TestCase):
    def test_e2e_cli_invocation_structure(self):
        code, results = run_e2e_cli(["--help"])
        self.assertEqual(code, 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m unittest tests/harness/test_e2e_runner.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'tools.run_e2e_tests'`

- [ ] **Step 3: Implement `tools/run_e2e_tests.py`**

Implement CLI engine:
- Resolve CraftOS-PC paths via `resolve_craftos_paths()`.
- Provision `EphemeralCraftOSSession` staging `src/`, `harness/simulation/`, and `tests/e2e/`.
- Execute test runner guest script executing all discovered `tests/e2e/test_e2e_*.lua` suites.
- Parse `result.json` and print tabular report or structured JSON.

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m unittest tests/harness/test_e2e_runner.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add tools/run_e2e_tests.py tests/harness/test_e2e_runner.py tests/harness/test_tools_integrity.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(tools): implement run_e2e_tests.py simulation runner CLI"
```

---

### Task 4: 시나리오 1 — GCS 부트스트랩, 40채널 동적 배정 및 텔레메트리 캐시 검증

**Files:**
- Create: `tests/e2e/test_e2e_bootstrap_and_telemetry.lua`

**Interfaces:**
- Consumes: `src/0_infra/gcs/`, `src/2_guidance/fcp/`, `src/1_control/vas/`
- Validates:
  - FCP `MSG_BLOCK_REQUEST` on `CH 50000` (`requestedBandwidth = 40`)
  - GCS `MSG_BLOCK_ASSIGN` on `CH 50000` (`baseChannel = 10000`, `blockId = 1`)
  - VAS `MSG_FLIGHT_TELEMETRY` on `Base+2` (10002)
  - FCP downlink `MSG_MFD_STATE` on `Base+3` (10003)
  - GCS multi-craft telemetry cache and fleet tracking

- [ ] **Step 1: Write the failing E2E test**

```lua
-- tests/e2e/test_e2e_bootstrap_and_telemetry.lua
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 1: GCS Bootstrap & Telemetry Downlink", function()
    it("completes full bootstrap handshake and fleet telemetry caching", function()
        local bus = virtual_bus.create_bus()
        local gcs = node_sandbox.create_node(bus, "GCS", "src/0_infra/gcs")
        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")

        -- 1. GCS opens CH 50000
        gcs:call("init_channel_manager")
        assert_true(gcs.modem:isOpen(50000))

        -- 2. FCP starts bootstrap request
        fcp:call("start_bootstrap_request", "HW-UUID-001", 40)
        bus:step()

        -- Assert GCS processed MSG_BLOCK_REQUEST and issued MSG_BLOCK_ASSIGN
        local assign_pkts = bus:find_packets({ type = "MSG_BLOCK_ASSIGN", channel = 50000 })
        assert_eq(#assign_pkts, 1)
        assert_eq(assign_pkts[1].payload.payload.baseChannel, 10000)

        -- 3. FCP commits Base=10000, opens Base+0, Base+1, Base+2, Base+3
        fcp:call("on_bootstrap_assigned", assign_pkts[1].payload)
        assert_true(fcp.modem:isOpen(10002))

        -- 4. VAS streams telemetry on Base+2 (10002)
        vas:call("transmit_telemetry", 10002, { pitch = 1.5, roll = 0.0, altY = 120.0 })
        bus:step()

        -- 5. FCP receives telem and outputs MSG_MFD_STATE on Base+3 (10003)
        fcp:call("step_tick", 0.05)
        bus:step()
        local mfd_pkts = bus:find_packets({ type = "MSG_MFD_STATE", channel = 10003 })
        assert_eq(#mfd_pkts, 1)

        -- 6. GCS monitors Base+3 and caches active telemetry
        gcs:call("process_telemetry_packet", 10003, mfd_pkts[1].payload)
        local active = gcs:call("get_active_craft")
        assert_not_nil(active)
        assert_eq(active.baseChannel, 10000)
    end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python tools/run_e2e_tests.py --filter bootstrap`
Expected: FAIL

- [ ] **Step 3: Implement scenario test logic and node adaptors in test suite**

Implement test execution harness verifying authentic envelope format, channel alignment, and state caching.

- [ ] **Step 4: Run test to verify it passes**

Run: `python tools/run_e2e_tests.py --filter bootstrap`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add tests/e2e/test_e2e_bootstrap_and_telemetry.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "test(e2e): implement scenario 1 GCS bootstrap and telemetry downlink"
```

---

### Task 5: 시나리오 2 — AMM 웨이포인트 큐, 이륙 지령 및 FCP/VAS/TCA/ASA 폐루프 유도 검증

**Files:**
- Create: `tests/e2e/test_e2e_waypoint_guidance.lua`

**Interfaces:**
- Consumes: `src/3_planning/amm/`, `src/2_guidance/fcp/`, `src/1_control/vas/`, `src/1_control/tca/`, `src/1_control/asa/`
- Validates:
  - Pilot `ARM` & `TAKEOFF` (`MSG_OPERATOR_CMD` on `Base+0` 10000)
  - FCP FSM: `DISARMED` → `IDLE_ARMED` → `TAKEOFF` → `CRUISE`
  - FCP `MSG_ATTITUDE_CMD` on `Base+1` (10001) with climb rate
  - VAS SO(3) inner loop `MSG_THRUST_CMD` on `Base+10` (10010) & `MSG_SURFACE_CMD` on `Base+11` (10011)
  - TCA & ASA status reports (`MSG_ACTUATOR_STATUS`, `MSG_SURFACE_STATUS`)
  - AMM waypoint progression upon reaching target altitude and coordinates

- [ ] **Step 1: Write the failing test**

```lua
-- tests/e2e/test_e2e_waypoint_guidance.lua
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 2: AMM Waypoint & FCP/VAS/TCA/ASA Closed Loop", function()
    it("drives full sequence from pilot takeoff to cruise waypoint advance", function()
        local bus = virtual_bus.create_bus()
        local amm = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")
        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
        local tca = node_sandbox.create_node(bus, "TCA", "src/1_control/tca")
        local asa = node_sandbox.create_node(bus, "ASA", "src/1_control/asa")

        -- AMM queues WP1(100, 100, 150) and pilot commands TAKEOFF
        amm:call("add_waypoint", 100, 100, 150, 18)
        amm:call("pilot_action", "ARM")
        amm:call("pilot_action", "TAKEOFF", { targetAlt = 150 })
        bus:step()

        local cmd_pkts = bus:find_packets({ type = "MSG_OPERATOR_CMD", channel = 10000 })
        assert_eq(#cmd_pkts, 2)

        -- FCP processes C2 cmd and issues guidance on Base+1 (10001)
        fcp:call("step_tick", 0.05)
        bus:step()
        local att_pkts = bus:find_packets({ type = "MSG_ATTITUDE_CMD", channel = 10001 })
        assert_eq(#att_pkts, 1)

        -- VAS receives attitude cmd, mixes outputs to TCA (Base+10) & ASA (Base+11)
        vas:call("step_tick", 0.05)
        bus:step()
        local thr_pkts = bus:find_packets({ type = "MSG_THRUST_CMD", channel = 10010 })
        local srf_pkts = bus:find_packets({ type = "MSG_SURFACE_CMD", channel = 10011 })
        assert_true(#thr_pkts >= 1)
        assert_true(#srf_pkts >= 1)
    end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python tools/run_e2e_tests.py --filter waypoint_guidance`
Expected: FAIL

- [ ] **Step 3: Implement multi-node guidance closure test logic**

Implement multi-tick loop verifying TCA and ASA feedback back to VAS, and VAS telemetry back to FCP.

- [ ] **Step 4: Run test to verify it passes**

Run: `python tools/run_e2e_tests.py --filter waypoint_guidance`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add tests/e2e/test_e2e_waypoint_guidance.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "test(e2e): implement scenario 2 AMM waypoint guidance closed loop"
```

---

### Task 6: 시나리오 3 — 고정밀 GPS 10Hz 측위 핑, 스웜 보고 및 FCP 항법 융합 검증

**Files:**
- Create: `tests/e2e/test_e2e_gps_triangulation.lua`

**Interfaces:**
- Consumes: `src/2_guidance/fcp/`, `src/0_infra/gps/`
- Validates:
  - FCP periodic `MSG_GPS_REQUEST` on `CH 60001` (`replyChannel = 10005`, `altitudeY = 125.4`)
  - GPS swarm nodes Euclidean distance measurement & `MSG_GPS_NODE_REPORT` on `CH 60003`
  - GPS Central Server early-solve WLS trilateration ($\le 50\text{ms}$)
  - GPS Server `MSG_GPS_RESPONSE` on `CH 10005` (`Base+5`, `FIX_OK`, `position = {x, z}`)
  - FCP position reception, Kalman filter update, and MFD state propagation

- [ ] **Step 1: Write the failing test**

```lua
-- tests/e2e/test_e2e_gps_triangulation.lua
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 3: GPS 10Hz Swarm Triangulation & Navigation Fusion", function()
    it("executes full ping -> node report -> early-solve -> response cycle", function()
        local bus = virtual_bus.create_bus()
        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
        local gps_srv = node_sandbox.create_node(bus, "GPS_SRV", "src/0_infra/gps")
        local gps_n1 = node_sandbox.create_node(bus, "GPS_N1", "src/0_infra/gps")
        local gps_n2 = node_sandbox.create_node(bus, "GPS_N2", "src/0_infra/gps")
        local gps_n3 = node_sandbox.create_node(bus, "GPS_N3", "src/0_infra/gps")
        local gps_n4 = node_sandbox.create_node(bus, "GPS_N4", "src/0_infra/gps")

        -- Configure swarm node coordinates
        gps_n1:call("set_node_position", 0, 100, 0)
        gps_n2:call("set_node_position", 500, 100, 0)
        gps_n3:call("set_node_position", 0, 100, 500)
        gps_n4:call("set_node_position", 500, 100, 500)

        -- FCP issues GPS ping on 60001
        fcp:call("send_gps_ping", 10005, 120.0)
        bus:step()

        local ping_pkts = bus:find_packets({ type = "MSG_GPS_REQUEST", channel = 60001 })
        assert_eq(#ping_pkts, 1)

        -- Swarm nodes report distances to GPS Server on 60003
        bus:step()
        local report_pkts = bus:find_packets({ type = "MSG_GPS_NODE_REPORT", channel = 60003 })
        assert_true(#report_pkts >= 4)

        -- GPS Server solves position and replies on 10005
        gps_srv:call("solve_and_reply")
        bus:step()
        local resp_pkts = bus:find_packets({ type = "MSG_GPS_RESPONSE", channel = 10005 })
        assert_eq(#resp_pkts, 1)
        assert_eq(resp_pkts[1].payload.payload.status, "FIX_OK")
    end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python tools/run_e2e_tests.py --filter gps_triangulation`
Expected: FAIL

- [ ] **Step 3: Implement GPS 10Hz triangulation closed-loop test**

Connect FCP `nav_engine` to GPS client reply handler and assert position fix.

- [ ] **Step 4: Run test to verify it passes**

Run: `python tools/run_e2e_tests.py --filter gps_triangulation`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add tests/e2e/test_e2e_gps_triangulation.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "test(e2e): implement scenario 3 GPS 10Hz swarm triangulation and navigation fusion"
```

---

### Task 7: 시나리오 4 — 격납고 Alignment 상주 콘솔, 직결 바인딩 및 OLS 프로파일 동기화 검증

**Files:**
- Create: `tests/e2e/test_e2e_hangar_alignment.lua`

**Interfaces:**
- Consumes: `src/0_development/alignment/`, `src/1_control/vas/`, `src/1_control/tca/`, `src/1_control/asa/`
- Validates:
  - Alignment Console in Bay 1 ($Base_{\text{hangar}} = 101$) sends `MSG_CALIBRATION_INIT` to craft `Base+0` (10000)
  - VAS enters `CALIBRATION`, opens Bay 1 channels (101, 102, 104), propagates `MSG_CALIB_BAY_BIND` to TCA & ASA
  - Alignment discover query `MSG_ACTUATOR_DISCOVER_REQ` on `104`, TCA replies `MSG_ACTUATOR_DISCOVER_ACK`
  - Alignment multi-level pulse sequence `MSG_CALIB_PULSE` on `101`, VAS streams `MSG_FLIGHT_TELEMETRY` on `102`
  - OLS regression calculation, `MSG_PROFILE_SYNC` on `101`, VAS replies `MSG_CALIB_ACK`
  - `MSG_CALIBRATION_CLOSE` session teardown, VAS & TCA close Bay 1 channels and restore `IDLE_ARMED`

- [ ] **Step 1: Write the failing test**

```lua
-- tests/e2e/test_e2e_hangar_alignment.lua
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 4: Hangar Alignment Calibration Session", function()
    it("completes full 5-stage calibration session and OLS profile sync", function()
        local bus = virtual_bus.create_bus()
        local align = node_sandbox.create_node(bus, "ALIGN", "src/0_development/alignment")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
        local tca = node_sandbox.create_node(bus, "TCA", "src/1_control/tca")
        local asa = node_sandbox.create_node(bus, "ASA", "src/1_control/asa")

        -- Alignment sends INIT on craft Base+0 (10000)
        align:call("start_calibration_init", 1, 10000) -- bayId 1, craftBase 10000
        bus:step()

        local init_pkts = bus:find_packets({ type = "MSG_CALIBRATION_INIT", channel = 10000 })
        assert_eq(#init_pkts, 1)

        -- VAS accepts and replies ACK on Bay Telem (102 = 101+1)
        vas:call("step_tick", 0.05)
        bus:step()
        local ack_pkts = bus:find_packets({ type = "MSG_CALIBRATION_INIT_ACK", channel = 102 })
        assert_eq(#ack_pkts, 1)
        assert_true(vas.modem:isOpen(101))
        assert_true(vas.modem:isOpen(102))

        -- Pulse test sequence on 101
        align:call("trigger_pulse_step", 1, 8, 300)
        bus:step()
        assert_true(#bus:find_packets({ type = "MSG_CALIB_PULSE", channel = 101 }) >= 1)

        -- Profile sync on 101
        align:call("sync_profile", "PROF-TEST-01", { k = 1.25, deadband = 0.05 })
        bus:step()
        local prof_pkts = bus:find_packets({ type = "MSG_PROFILE_SYNC", channel = 101 })
        assert_eq(#prof_pkts, 1)

        -- Session close
        align:call("close_session")
        bus:step()
        assert_false(vas.modem:isOpen(101))
    end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python tools/run_e2e_tests.py --filter hangar_alignment`
Expected: FAIL

- [ ] **Step 3: Implement alignment session verification logic**

Assert complete OLS evaluation, channel bind/unbind cascade, and return to normal armed state.

- [ ] **Step 4: Run test to verify it passes**

Run: `python tools/run_e2e_tests.py --filter hangar_alignment`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add tests/e2e/test_e2e_hangar_alignment.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "test(e2e): implement scenario 4 hangar alignment calibration session"
```

---

### Task 8: 시나리오 5 — GCS C2 오버라이드, AMM 무반향 감청 및 하드 `E_STOP` 직결 차단 검증

**Files:**
- Create: `tests/e2e/test_e2e_c2_and_estop.lua`

**Interfaces:**
- Consumes: `src/0_infra/gcs/`, `src/3_planning/amm/`, `src/2_guidance/fcp/`, `src/1_control/vas/`, `src/1_control/tca/`
- Validates:
  - GCS remote command `HOLD` on `Base+0` (10000) with `authority = "GCS_OVERRIDE"`
  - AMM detects `GCS_OVERRIDE`, transitions state to `SUSPENDED`, zero retransmissions
  - FCP transitions FSM to `HOVER_HOLD`
  - GCS or AMM pilot issues `E_STOP` on `Base+1` (10001) with `action = "E_STOP"`
  - VAS directly intercepts `Base+1`, bypasses FCP, transitions to `E_STOP` FSM state
  - VAS issues `MSG_THRUST_CMD` on `Base+10` (10010) with all thruster outputs = 0 and `controlState = "E_STOP"`
  - VAS broadcasts `MSG_EMERGENCY_ALERT` on `Base+1` to notify FCP

- [ ] **Step 1: Write the failing test**

```lua
-- tests/e2e/test_e2e_c2_and_estop.lua
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 5: GCS C2 Override & Hard E-STOP Cutoff", function()
    it("handles remote override without AMM echo and cuts thrusters on Base+1 E-STOP", function()
        local bus = virtual_bus.create_bus()
        local gcs = node_sandbox.create_node(bus, "GCS", "src/0_infra/gcs")
        local amm = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")
        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
        local tca = node_sandbox.create_node(bus, "TCA", "src/1_control/tca")

        -- 1. In-flight normal operation
        vas:call("set_state", "NORMAL")

        -- 2. GCS issues remote HOLD on Base+0 (10000)
        gcs:call("send_c2_command", 10000, "HOLD", "HOVER_HOLD")
        bus:step()

        -- AMM must suspend queue without emitting new packets
        local before_cnt = #bus.packet_log
        amm:call("step_tick", 0.05)
        bus:step()
        assert_eq(#bus.packet_log, before_cnt, "AMM must not echo or retransmit during GCS override")

        -- 3. GCS issues hard E_STOP on Base+1 (10001)
        gcs:call("send_estop_override", 10001)
        bus:step()

        local estop_pkts = bus:find_packets({ type = "MSG_EMERGENCY_OVERRIDE", channel = 10001 })
        assert_eq(#estop_pkts, 1)

        -- VAS intercepts Base+1 and immediately cuts TCA thrust to 0
        vas:call("step_tick", 0.05)
        bus:step()

        local kill_pkts = bus:find_packets({ type = "MSG_THRUST_CMD", channel = 10010 })
        assert_true(#kill_pkts >= 1)
        local last_kill = kill_pkts[#kill_pkts]
        assert_eq(last_kill.payload.payload.controlState, "E_STOP")
        for _, out_val in pairs(last_kill.payload.payload.outputs or {}) do
            assert_eq(out_val, 0)
        end
    end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python tools/run_e2e_tests.py --filter c2_and_estop`
Expected: FAIL

- [ ] **Step 3: Implement override and cutoff verification logic**

Verify non-echo behavior and immediate zero-thrust shutoff.

- [ ] **Step 4: Run test to verify it passes**

Run: `python tools/run_e2e_tests.py --filter c2_and_estop`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add tests/e2e/test_e2e_c2_and_estop.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "test(e2e): implement scenario 5 GCS C2 override and hard E-STOP cutoff"
```

---

### Task 9: 시나리오 6 — GAC & 착륙패드 3-Tier 스마트 전술 착륙 시퀀스 검증

**Files:**
- Create: `tests/e2e/test_e2e_facility_landing.lua`

**Interfaces:**
- Consumes: `src/0_infra/gac/`, `src/0_infra/landing_pad/`, `src/2_guidance/fcp/`, `src/3_planning/amm/`
- Validates:
  - GAC 1Hz broadcast `MSG_FACILITY_BEACON` on `CH 50003`
  - FCP check-in request `MSG_GAC_CHECKIN_REQ` on $Base_{\text{sec}}+0$ (50201)
  - GAC allocates Pad, issues `MSG_ATC_SLOT_ASSIGN` on $Base_{\text{sec}}+1$ (50202)
  - Landing Pad accepts `MSG_ATC_SLOT_ACK`, GAC issues `MSG_GAC_APPROACH_CLEARANCE` to FCP
  - Landing Pad transmits tactical guidance `MSG_FACILITY_STATIC_GUIDE` / `DYNAMIC_GUIDE` on $Base_{\text{sec}}+10+1$ (50211)
  - FCP guides craft to touchdown, transmits `MSG_TOUCHDOWN_COMPLETE` on 50211
  - Landing Pad notifies GAC `MSG_ATC_FACILITY_UPDATE` (`status = "OCCUPIED"`)

- [ ] **Step 1: Write the failing test**

```lua
-- tests/e2e/test_e2e_facility_landing.lua
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 6: 3-Tier Facility Tactical Landing", function()
    it("completes beacon -> checkin -> slot assign -> tactical guide -> touchdown flow", function()
        local bus = virtual_bus.create_bus()
        local gac = node_sandbox.create_node(bus, "GAC", "src/0_infra/gac")
        local pad = node_sandbox.create_node(bus, "PAD", "src/0_infra/landing_pad")
        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")

        -- 1. GAC broadcasts beacon on 50003
        gac:call("broadcast_beacon")
        bus:step()
        assert_true(#bus:find_packets({ type = "MSG_FACILITY_BEACON", channel = 50003 }) >= 1)

        -- 2. FCP checks in on 50201
        fcp:call("request_checkin", 50201, "AIRCRAFT_01", 12500)
        bus:step()
        local req_pkts = bus:find_packets({ type = "MSG_GAC_CHECKIN_REQ", channel = 50201 })
        assert_eq(#req_pkts, 1)

        -- 3. GAC assigns slot on 50202 and grants clearance
        gac:call("step_tick", 0.05)
        bus:step()
        pad:call("step_tick", 0.05)
        bus:step()
        gac:call("step_tick", 0.05)
        bus:step()
        local clr_pkts = bus:find_packets({ type = "MSG_GAC_APPROACH_CLEARANCE", channel = 50201 })
        assert_eq(#clr_pkts, 1)

        -- 4. Pad streams tactical guidance on 50211
        pad:call("stream_guidance", 50211)
        bus:step()
        local guide_pkts = bus:find_packets({ channel = 50211 })
        assert_true(#guide_pkts >= 1)

        -- 5. FCP touches down and transmits MSG_TOUCHDOWN_COMPLETE
        fcp:call("report_touchdown", 50211, "PAD_01")
        bus:step()
        local td_pkts = bus:find_packets({ type = "MSG_TOUCHDOWN_COMPLETE", channel = 50211 })
        assert_eq(#td_pkts, 1)

        -- 6. Pad reports OCCUPIED to GAC on 50202
        pad:call("step_tick", 0.05)
        bus:step()
        local upd_pkts = bus:find_packets({ type = "MSG_ATC_FACILITY_UPDATE", channel = 50202 })
        assert_eq(#upd_pkts, 1)
        assert_eq(upd_pkts[1].payload.payload.status, "OCCUPIED")
    end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python tools/run_e2e_tests.py --filter facility_landing`
Expected: FAIL

- [ ] **Step 3: Implement facility landing integration test**

Verify complete 3-Tier coordination sequence.

- [ ] **Step 4: Run test to verify it passes**

Run: `python tools/run_e2e_tests.py --filter facility_landing`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add tests/e2e/test_e2e_facility_landing.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "test(e2e): implement scenario 6 3-tier facility tactical landing"
```

---

### Task 10: 전체 회귀 검증, 마일스톤 동기화 및 작업 완결

**Files:**
- Modify: `TASK.md`
- Modify: `GEMINI.md`

**Interfaces:**
- Consumes: All tests passing across unit and E2E simulation suites
- Produces: Updated project memory and task tracker

- [ ] **Step 1: Execute all test suites**

Run:
1. `python tools/run_unit_tests.py --require-tests --clean-orphans` (12 targets, 241/241 PASS)
2. `python tools/run_e2e_tests.py --clean-orphans` (All 6 scenarios PASS)
3. `python -m unittest discover -s tests/harness -p "test_*.py"` (All PASS)
4. `python tools/verify_all_specs.py` (14 specs 100% clean)
5. `python tools/validate_lua_syntax.py` (All Lua clean)
6. `python tools/verify_spec_status.py` (9 Implemented, 5 Approved)

- [ ] **Step 2: Update `TASK.md`**

Mark `TASK-111` as `[x]` in Completed Tasks Archive, derive follow-up items (`TASK-301` next).

- [ ] **Step 3: Update `GEMINI.md` snapshot**

Sync active handover, verified test counts, and commands in `GEMINI.md` (strictly $\le 80$ lines).

- [ ] **Step 4: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add TASK.md GEMINI.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "chore(task): complete TASK-111 multi-node E2E packet simulation framework"
```
