# Sequential Implementation Plan: AMM v1.3.0 (TASK-207) → FCP v2.0.0 (TASK-208) → VAS v1.19.0 (TASK-209)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execute implementation in an isolated git worktree (`using-git-worktrees`) branched from `main`.

**Goal:** Execute **TASK-207** (`AMM v1.3.0`), **TASK-208** (`FCP v2.0.0`), and **TASK-209** (`VAS v1.19.0`) sequentially on a single cleanly partitioned architecture, migrating external RF, GPS+DR navigation fusion, 3-Tier ATC/facility docking, and 20Hz trajectory generation to AMM (`Base+4` `[I-12]`), reducing FCP to a single-modem 3-channel `SE(3)` outer-loop controller (`QUATERNION_RATE`), normalizing VAS to a Zero-Fallback inner-loop rate/quaternion controller with ACRO/failsafe alignment, and verifying closed-loop 3-node flight via unit, E2E, mutation, manifest, and spec gates.

**Architecture:** The aircraft control stack follows a strict 4-tier cascade: `AMM (Node 03)` owns dual-modem (`top` onboard / `back` infra with single-modem fallback) external RF (`CH 50000~50004`, `CH 60001/60002`, `Base_sec+*`, `Base+5`), `nav_engine` (GPS+DR $\alpha=0.35$, 5,000ms timeout), `facility_client` (2nd-order Taylor dynamic deck extrapolation, 300ms watchdog), `channel_sentinel` (4-layer `MSG_CHANNEL_REBIND`), and `trajectory_generator` (20Hz 11-mode setpoint generator on `Base+4` `[I-12]`, `Base+0` C2, and 5Hz `Base+3` MFD downlink with `MFD_ACRO` yield) via `parallel.waitForAny` (`20Hz`/`5Hz`). `FCP (Node 04)` operates headless by default on a single `top` modem and 3 channels (`Base+4/+2/+1`), propagating position via `state_propagator` (`dt <= 0.1s`, bounded `posEpoch` merge), managing 6 FSM states (`BOOT`, `IDLE_ARMED`, `ACTIVE_TRACKING`, `PASSIVE_TRACKING` with 2.0s bumpless ramp, `AMM_TIMEOUT_HOLD` `500ms -> 10s -> EMERGENCY_LAND`, `EMERGENCY_LAND`), and projecting unified `SE(3)` desired acceleration ($g = 11.0\text{ m/s}^2$) into `QUATERNION_RATE` for all 6 airframes. `VAS (Node 01)` consumes single-path `QUATERNION_RATE` / `RATE_COMMAND` on `Base+1` (Zero-Fallback, zero `ATTITUDE_ANGLE`, zero normal-flight `compute_climb_wrench` vertical PI), arbitrates `E_STOP (ESTOP_CONFIRM_KEY) > MFD_ACRO > FCP`, yields `Base+3` to AMM except during `MFD_ACRO` 20Hz `CORE_ACRO_TAKEOVER` HUD and 5Hz failsafe, and outputs `MSG_THRUST_CMD` (`Base+10`) and `[I-10]` `MSG_AERO_CMD` (`Base+11`).

**Tech Stack:** CC:Tweaked 1.109+ Lua 5.2 (Cobalt VM, `parallel.waitForAny`, `os.startTimer`, `textutils`, `fs`, `term.blit`), `/lib/avionics_sensors.lua`, CraftOS-PC Headless Unit Test Runner (`tools/run_unit_tests.py`), Multi-Node E2E Simulation Harness (`tools/run_e2e_tests.py`), Mutation Test Runner (`tools/run_mutation_tests.py`), Static Verifiers (`tools/validate_lua_syntax.py`, `tools/verify_manifest_sync.py`, `tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/verify_context_docs.py`, `tests/harness/`).

**Spec:**
- Master ICD & Diagram: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.28.0 Approved`), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.13.0 Approved`)
- Subsystem Specs: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v1.3.0 Approved` — stays `Approved` until `TASK-202-5` also finishes), `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (`v2.0.0 Approved -> Implemented` at TASK-208 completion), `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (`v1.19.0 Approved -> Implemented` at TASK-209 completion)
- Roadmap SSOT: `TASK.md` (`TASK-207`, `TASK-208`, `TASK-209`)

## Global Constraints

- **Execution Order & Phase Gates (Strict Sequential)**: Do NOT execute Phase 2 (`TASK-208`) until Phase 1 (`TASK-207`) passes all AMM unit tests, `verify_manifest_sync.py`, `validate_lua_syntax.py`, and `MUT-03`~`MUT-05`. Do NOT execute Phase 3 (`TASK-209`) until Phase 2 passes all FCP unit tests, `verify_manifest_sync.py`, `test_mutation_runner.py`, and `MUT-14`/`MUT-15`/`MUT-23`. Do NOT delete `src/2_guidance/fcp/` legacy modules until `MUT-03` has already been migrated to AMM (Phase 1) and `MUT-14`/`MUT-15`/`MUT-23` are retargeted alongside FCP replacement modules (Task 8).
- **Multi-Codebase Isolation (`GEMINI.md`)**: Modules in `src/<layer>/<name>/` must remain independently installable with zero cross-directory `require` calls outside `/lib/avionics_sensors.lua`. AMM `nav_engine.lua` implements GPS wire protocol compatibility (`ver = "1.9.5"`, `time`, `altitudeY`, `clientType = "AIRCRAFT"`, monotonic `clientSeq`, strict `targetClient` match on `CH 60001 -> Base+5`) natively inside `src/3_planning/amm/` without requiring `src/0_infra/gps/`.
- **Zero-Fallback Protocol (`AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` §1.3)**: No dual-key fallbacks in new/refactored interfaces. `FCP -> VAS` uses only `commandType = "QUATERNION_RATE"` (or `"RATE_COMMAND"` for ACRO) with `targetQuaternion`, `targetAngularRates`, `collectiveThrust`, optional `flapTarget`, and optional `translationBias { surge, sway }` — completely removing `ATTITUDE_ANGLE`, `angleTargets`, `rateTargets`, `targetClimbRate`, `targetThrottle`, and `translationBias.heave`. `VAS <-> ASA` uses only `[I-10]` `MSG_AERO_CMD`, `MSG_AERO_STATUS`, `MSG_SURFACE_DISCOVER_REQ/ACK`.
- **Lua 5.2 Cobalt & Non-Blocking 20Hz Rule (`.agent/rules/cc-tweaked-runtime.md`, `runner_lib.lua`)**: Zero Lua 5.3+ operators (`//`, `&`, `|`, `~`, `<<`, `>>`), zero prohibited OS APIs (`os.execute`, `os.exit`, `os.remove`, `os.rename`, `io.popen`, `getfenv`, `setfenv`), zero `sleep()`/`os.pullEvent()` calls inside tick or message handler modules, and every Lua function `<= 50` lines using dispatch tables and modular helpers.
- **Valkyrien Skies Ban (`.agent/rules/domain-aeronautics.md`)**: Zero prohibited mod tokens (`valkyrien`, `vs2`, `cc_vs`, `ship` peripheral/identifier, `kontraption:`, `eureka:`, `vs_clockwork:`, `trackwork:`) in any Lua, JSON, or doc file. `vector_thruster`, `ion_thruster`, `gimbal_sensor`, `altitude_sensor`, `velocity_sensor`, `create:clockwork_bearing` remain permitted.
- **Terminology Guard & 51x19 TUI Integrity (`tests/harness/test_terminology_guard.py`)**: Zero `uap`, `SAS`, `wap`, `VAS-Core`, `VAS-Align`, `VAC-Align`, `VAC-Core` anywhere in `src/`, `tests/`, or `docs/`. Every `term.blit` call in AMM/FCP/VAS TUI renderers must preserve exact `51` characters across `text`, `fg`, and `bg`.
- **Windows PowerShell & Git Guardrails**: Chain PowerShell commands with `; if ($?) { ... }` (never `&&`). Call Git via `& "C:\Program Files\Git\cmd\git.exe"`. Never run destructive git commands (`push --force`, `reset --hard`, `clean -fd`, `branch -D`, `checkout .`, `restore .`).

## Review Focus

1. **Modem Top/Back Arbitration & 4-Layer `MSG_CHANNEL_REBIND` Atomicity (`amm/network_manager.lua`, `amm/channel_sentinel.lua`, `fcp/network_manager.lua`, `vas/network_manager.lua`)**: AMM must open onboard channels (`Base+0..5`, `Base+20..29`) on `top` and infra channels (`50000..50004`, `Base_sec+*`, `60001/60002`) on `back` while degrading gracefully to single-modem union mode (`modemFallbackActive = true`) if only one wireless modem is present. A 4-layer rebind must keep both old and new channel sets open during `PREPARE`, enforce FCP 500ms ACK timeout `ROLLBACK` toward VAS/TCA/ASA without mutating `baseChannel`, and commit atomically (`config/*.json` + close old channels) only on `COMMIT` (pinned by Tasks 1, 4, 5, 10, 11).
2. **`nav_engine` Monotonic `clientSeq`, Elapsed Kinematic Gate & `posEpoch` Synchronization (`amm/nav_engine.lua`, `fcp/state_propagator.lua`)**: AMM must ignore foreign `targetClient` or replayed/future `clientSeq` GPS responses, preserve onboard `altitudeY` as authoritative `pos.y` (never overwritten by 2D GPS), degrade complementary gain to `degradedAlpha = 0.10` after `5,000ms` GPS loss, and increment `posEpoch` on every GPS fix so FCP `state_propagator` clamps `dt <= 0.1s` and bounds `posEpoch` step corrections to `posMergeMaxStepM = 2.0` without step discontinuities (pinned by Tasks 1, 5).
3. **Trajectory Mode Setpoints, 2nd-Order Taylor Deck Extrapolation & Docking Abort (`amm/trajectory_generator.lua`, `amm/facility_client.lua`)**: `facility_client` must clamp dynamic deck extrapolation to `dt <= 0.5s`, fall back to `HOVER_HOLD` / go-around if `MSG_FACILITY_DYNAMIC_GUIDE` exceeds `300ms`, and execute `15s x 10` ATC retry climbs (`+30m`). `trajectory_generator` must isolate `-0.8` docking abort reverse surge and `15.0m` safety radius, compute exact `LOITER` centripetal/tangential feedforward acceleration (`v^2/R`), enforce `POI_HOLD` `<= 30.0 deg/s` yaw slew, and populate complete `Base+4` `[I-12]` setpoints for all 11 modes (pinned by Tasks 2, 3, 4).
4. **SE(3) $g = 11.0\text{ m/s}^2$ Control Law, Sway-Loss Fallback & 2.0s Bumpless Ramp (`fcp/outer_loop_controller.lua`, `fcp/flight_fsm.lua`)**: FCP must use exact gravity feedforward $g = 11.0\text{ m/s}^2$, freeze outer-loop position integrators when `vasSat` reports inner-loop/tilt/thrust saturation (conditional anti-windup), drop from `STRICT_LEVEL` to `TILT_ASSISTED` tilt projection automatically if `actuatorHealth.tap == false` or `swayTotalLoss`, trigger `2.0s` bumpless ramp on mode changes or `PASSIVE_TRACKING`/`AMM_TIMEOUT_HOLD` exit while preserving `ADVANCED_VTOL` `prev_surge`/`prev_sway` continuity, and emit strictly `QUATERNION_RATE` packets with zero `ATTITUDE_ANGLE` fields (pinned by Tasks 6, 7).
5. **VAS Zero-Fallback Normal Path vs Isolated Failsafe Vertical PI & `MFD_ACRO` Preemption (`vas/vehicle_policy.lua`, `vas/flight_dynamics_core.lua`, `vas/state_machine.lua`, `vas/telemetry_feeder.lua`)**: Removing `compute_climb_wrench` from normal `flight_dynamics_core.compute()` must convert FCP `collectiveThrust` (`0.0..1.0`) directly into open-loop heave/surge thrust effort without vertical velocity PI fighting FCP's outer-loop SE(3) loop, while preserving vertical PI hold (`0.0 m/s` / `-1.5 m/s` / `-1.0 m/s`) strictly inside `FAILSAFE_HOLD`/`EMERGENCY_LAND`/`AIRBORNE_EMERGENCY`. `E_STOP` must verify `authKey == "ESTOP_CONFIRM_KEY"`, `Base+3` must stay completely silent during `activeSource == "FCP"` and transmit full `CORE_ACRO_TAKEOVER` payload at 20Hz during `MFD_ACRO` (pinned by Tasks 9, 10).
6. **Legacy Surface & Tooling Parity (`manifest.lua`, `run_mutation_tests.py`, `verify_spec_status.py`, `tests/e2e/`)**: Removing the 14 legacy FCP modules must stay 100% synchronized with `manifest.lua` (`verify_manifest_sync.py` 0 Errors/0 Warnings), all 25 mutation operators (`MUT-03` in AMM, `MUT-14`/`MUT-15`/`MUT-23` in FCP) must point to live code targets and achieve `25/25 KILLED`, all existing E2E scenarios must be migrated to `[I-12]` / `QUATERNION_RATE` / `MSG_AERO_CMD` without leaving stale mocks, and `tools/verify_spec_status.py` must advance `FCP` and `VAS` to `Implemented` (`9 Implemented, 6 Approved`) while keeping `AMM` at `Approved` until `TASK-202-5` finishes (pinned by Tasks 1, 8, 10, 11, 12).

---

## File Structure Overview

- **Phase 1 — AMM v1.3.0 (`TASK-207`)**:
  - Modify: `src/3_planning/amm/config/amm_config.json`, `src/0_development/installer/modules/manifest.lua` (`amm` v1.3.0 entry), `tools/run_mutation_tests.py` (`MUT-03`)
  - Create: `src/3_planning/amm/modules/channel_sentinel.lua`, `src/3_planning/amm/modules/nav_engine.lua`, `src/3_planning/amm/modules/facility_client.lua`, `src/3_planning/amm/modules/trajectory_generator.lua`
  - Modify: `src/3_planning/amm/modules/network_manager.lua`, `src/3_planning/amm/modules/c2_arbiter.lua`, `src/3_planning/amm/modules/mission_engine.lua`, `src/3_planning/amm/modules/ui_renderer.lua`, `src/3_planning/amm/main.lua`
  - Preserve unchanged for existing unit/mutation parity: `src/3_planning/amm/modules/waypoint_queue.lua` (`MUT-04`), `condition_evaluator.lua`, `hook_runner.lua`, `input_handler.lua`
  - Create/Modify Tests: `tests/3_planning/amm/test_channel_sentinel.lua`, `tests/3_planning/amm/test_nav_engine.lua`, `tests/3_planning/amm/test_facility_client.lua`, `tests/3_planning/amm/test_trajectory_generator.lua`, `tests/3_planning/amm/test_network_manager.lua`, `tests/3_planning/amm/test_c2_arbiter.lua`, `tests/3_planning/amm/test_main_loop.lua`
- **Phase 2 — FCP v2.0.0 (`TASK-208`)**:
  - Modify: `src/2_guidance/fcp/config/fcp_config.json`, `src/0_development/installer/modules/manifest.lua` (`fcp` v2.0.0 entry + `AIRFRAME_PRESETS`), `tools/run_mutation_tests.py` (`MUT-14`, `MUT-15`, `MUT-23`)
  - Replace/Rewrite: `src/2_guidance/fcp/modules/network_manager.lua`, `src/2_guidance/fcp/modules/flight_fsm.lua`, `src/2_guidance/fcp/modules/ui_renderer.lua`, `src/2_guidance/fcp/main.lua`
  - Create: `src/2_guidance/fcp/modules/state_propagator.lua`, `src/2_guidance/fcp/modules/outer_loop_controller.lua`
  - Delete (14 legacy/migrated files): `src/2_guidance/fcp/fcp_runtime.lua`, `src/2_guidance/fcp/modules/channel_sentinel.lua`, `src/2_guidance/fcp/modules/facility_client.lua`, `src/2_guidance/fcp/modules/nav_engine.lua`, `src/2_guidance/fcp/modules/operator_handler.lua`, `src/2_guidance/fcp/modules/thruster_profile.lua`, `src/2_guidance/fcp/modules/guidance_controller.lua`, `src/2_guidance/fcp/modules/vectored_vtol_driver.lua`, `src/2_guidance/fcp/modules/advanced_vtol_driver.lua`, `src/2_guidance/fcp/modules/drivers/drone_driver.lua`, `src/2_guidance/fcp/modules/drivers/fixed_wing_driver.lua`, `src/2_guidance/fcp/modules/drivers/helicopter_driver.lua`, `src/2_guidance/fcp/modules/aerodynamic_controller.lua`, `src/2_guidance/fcp/node_fcp_sim.lua`
  - Replace/Create Tests: `tests/2_guidance/fcp/test_fcp_network_and_rebind.lua`, `tests/2_guidance/fcp/test_state_propagator.lua`, `tests/2_guidance/fcp/test_flight_fsm_v2.lua`, `tests/2_guidance/fcp/test_outer_loop_se3.lua`, `tests/2_guidance/fcp/test_fcp_main_v2.lua` (retiring legacy `test_fcp_core.lua`, `test_fcp_advanced_vtol.lua`, `test_fcp_loiter_poi.lua`, etc.)
- **Phase 3 — VAS v1.19.0 (`TASK-209`)**:
  - Modify: `src/0_development/installer/modules/manifest.lua` (`vas` v1.19.0 `defaultConfigs["/config/system.json"]`), `src/1_control/vas/modules/vehicle_policy.lua`, `src/1_control/vas/modules/flight_dynamics_core.lua`, `src/1_control/vas/modules/state_machine.lua`, `src/1_control/vas/modules/network_manager.lua`, `src/1_control/vas/modules/telemetry_feeder.lua`, `src/1_control/vas/modules/core_daemon.lua`, `src/1_control/vas/modules/actuator_adapter_asa.lua`, `src/1_control/vas/main.lua`
  - Modify/Create Tests: `tests/1_control/vas/test_vas_core.lua`, `tests/1_control/vas/test_vas_advanced_vtol.lua`, `tests/1_control/vas/test_vas_quaternion_rate.lua`
- **Phase 4 — E2E Migration, Verification & Promotion**:
  - Modify: `tests/e2e/test_e2e_bootstrap_and_telemetry.lua`, `tests/e2e/test_e2e_waypoint_guidance.lua`, `tests/e2e/test_e2e_c2_and_estop.lua`, `tests/e2e/test_e2e_facility_landing.lua`, `tests/e2e/test_e2e_gps_triangulation.lua`, `tests/e2e/test_e2e_advanced_vtol_flight.lua`
  - Create: `tests/e2e/test_e2e_3node_se3_closed_loop.lua`
  - Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`, `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`, `tools/verify_spec_status.py`, `TASK.md`, `GEMINI.md`, `.agent/memory/workspace-root.md`

---

## Phase 1: TASK-207 — AMM v1.3.0 External Gateway, Nav Fusion & 20Hz Trajectory Generator

### Task 1: AMM v1.3.0 Config Schema, `manifest.lua`, `channel_sentinel.lua`, `nav_engine.lua` & `MUT-03` Migration

**Files:**
- Modify: `src/3_planning/amm/config/amm_config.json:1-8`
- Modify: `src/0_development/installer/modules/manifest.lua:517-556`
- Create: `src/3_planning/amm/modules/channel_sentinel.lua`
- Create: `src/3_planning/amm/modules/nav_engine.lua`
- Modify: `tools/run_mutation_tests.py:41-50`
- Create: `tests/3_planning/amm/test_channel_sentinel.lua`
- Create: `tests/3_planning/amm/test_nav_engine.lua`

**Interfaces:**
- Consumes:
  - CraftOS `os.epoch("utc")`, `fs`, `textutils`
  - FCP `v1.16.0` protocol baseline (`channel_sentinel.lua` & `nav_engine.lua`) + GPS v2.3.1 wire contract (`ver = "1.9.5"`, `CH_GPS_PING = 60001`, `CH_GPS_SERVICE = 60002`, `Base+5`, `targetClient`, `clientSeq`)
- Produces:
  - `channel_sentinel.init(config)` -> state (`baseChannel`, `bootstrapChannel = 50000`, `bandwidth = 40`, `channelProbeWaitMs = 200`, `gcsBootstrapTimeoutMs = 1000`)
  - `channel_sentinel.compute_base(n)`, `is_valid_base(baseCh)`, `start_bootstrap(state, now_ms)`, `on_block_assign(state, payload, now_ms)`, `probe_channel(state, candidate_base, now_ms)`, `on_probe_ack(state, packet)`, `negotiate_and_probe(state, now_ms, inbound)`
  - `channel_sentinel.initiate_rebind(state, newBaseChannel, now_ms)`, `on_rebind_ack(state, packet, now_ms)`, `step_rebind_transaction(state, now_ms)`
  - `nav_engine.init(config)`, `integrate_dr(state, telem, dt, now_ms)`, `should_query_gps(state, now_ms)`, `build_gps_request(state, now_ms)`, `filter_gps(state, payload, dt, now_ms, expectedSeq)`, `update_timeout(state, now_ms)` -> `state = { pos, vel, attitude, groundSpeed, posEpoch, navValid, gpsStale, degradedAlpha, lastGpsFixSeq, lastGpsFixMs }`

- [ ] **Step 1: Write failing unit tests in `tests/3_planning/amm/test_channel_sentinel.lua` and `tests/3_planning/amm/test_nav_engine.lua`**

Create `tests/3_planning/amm/test_channel_sentinel.lua`:
```lua
-- tests/3_planning/amm/test_channel_sentinel.lua
local channel_sentinel = require("channel_sentinel")

describe("AMM channel_sentinel 40-channel validation, bootstrap and 4-layer rebind", function()
    it("validates aligned base channels and normalizes invalid base to 10000", function()
        assert_true(channel_sentinel.is_valid_base(10000))
        assert_true(channel_sentinel.is_valid_base(10040))
        assert_true(channel_sentinel.is_valid_base(49960))
        assert_false(channel_sentinel.is_valid_base(10060))
        assert_false(channel_sentinel.is_valid_base(9960))
        assert_false(channel_sentinel.is_valid_base(50000))

        local st = channel_sentinel.init({ channels = { baseChannel = 10060 } })
        assert_eq(st.baseChannel, 10000)
        assert_eq(st.bootstrapChannel, 50000)
        assert_eq(st.bandwidth, 40)
    end)

    it("executes MUT-03 candidate base assignment on MSG_BLOCK_ASSIGN", function()
        local st = channel_sentinel.init({ channels = { baseChannel = 10000 } })
        local boot = channel_sentinel.start_bootstrap(st, 1000)
        assert_eq(boot.type, "MSG_BLOCK_REQUEST")
        assert_eq(boot.requestedBandwidth, 40)

        channel_sentinel.on_block_assign(st, { baseChannel = 10040 }, 1050)
        assert_eq(st.candidateBase, 10040)
        assert_eq(st.status, "START_PROBE")

        local probe = channel_sentinel.probe_channel(st, 10040, 1060)
        assert_eq(probe.type, "MSG_CHANNEL_PROBE")
        assert_eq(probe.candidateBaseChannel, 10040)

        local st2, _ = channel_sentinel.negotiate_and_probe(st, 1270, {})
        assert_eq(st2, "ACQUIRED")
        assert_eq(st.baseChannel, 10040)
    end)

    it("handles 2-phase rebind PREPARE -> COMMIT and 500ms timeout ROLLBACK", function()
        local st = channel_sentinel.init({ channels = { baseChannel = 10000 } })
        local prep = channel_sentinel.initiate_rebind(st, 10080, 1000)
        assert_eq(prep.type, "MSG_CHANNEL_REBIND")
        assert_eq(prep.payload.action, "PREPARE")
        assert_eq(prep.payload.oldBaseChannel, 10000)
        assert_eq(prep.payload.newBaseChannel, 10080)
        assert_eq(prep.payload.bandwidth, 40)

        assert_true(channel_sentinel.on_rebind_ack(st, {
            type = "MSG_CHANNEL_REBIND_ACK",
            payload = { transactionId = prep.payload.transactionId, status = "READY" },
        }, 1100))

        local commit, c_st = channel_sentinel.step_rebind_transaction(st, 1150)
        assert_eq(c_st, "COMMITTED")
        assert_eq(commit.payload.action, "COMMIT")
        assert_eq(st.baseChannel, 10080)
        assert_nil(st.rebindTx)

        -- Timeout path
        local prep2 = channel_sentinel.initiate_rebind(st, 10120, 2000)
        assert_not_nil(prep2)
        local rb, rb_st = channel_sentinel.step_rebind_transaction(st, 2550)
        assert_eq(rb_st, "ROLLED_BACK")
        assert_eq(rb.payload.action, "ROLLBACK")
        assert_eq(st.baseChannel, 10080)
        assert_nil(st.rebindTx)
    end)
end)
```

Create `tests/3_planning/amm/test_nav_engine.lua`:
```lua
-- tests/3_planning/amm/test_nav_engine.lua
local nav_engine = require("nav_engine")

describe("AMM nav_engine GPS+DR complementary filter, monotonic seq and epoch sync", function()
    it("synchronizes pos.y to onboard baro altitudeY and falls back to vy*dt when missing", function()
        local st = nav_engine.init({ navigation = { drComplementaryAlpha = 0.35, gpsTimeoutMs = 5000 } })
        nav_engine.integrate_dr(st, {
            dynamics = { altitudeY = 142.5, velocity = { vx = 10.0, vy = 0.0, vz = -5.0 } },
            attitude = { pitch = 1.0, roll = 0.0, heading = 90.0 },
        }, 0.05, 1000)
        assert_near(st.pos.y, 142.5, 1e-4)
        assert_near(st.pos.x, 0.5, 1e-4)
        assert_near(st.pos.z, -0.25, 1e-4)
        assert_true(st.navValid)

        nav_engine.integrate_dr(st, { velocity = { vx = 0.0, vy = 10.0, vz = 0.0 } }, 0.1, 1100)
        assert_near(st.pos.y, 143.5, 1e-4)
    end)

    it("builds TASK-122 compliant GPS request, enforces monotonic seq and increments posEpoch on FIX_OK", function()
        local st = nav_engine.init({
            system = { domainId = "AIRCRAFT_01" },
            channels = { baseChannel = 10000 },
            navigation = { drComplementaryAlpha = 0.35, kinematicGateLimitM = 8.0, gpsTimeoutMs = 5000 },
        })
        st.pos = { x = 10.0, y = 100.0, z = 20.0 }

        local ok, seq1, reqPkt = nav_engine.build_gps_request(st, 1000)
        assert_true(ok)
        assert_eq(seq1, 1)
        assert_eq(reqPkt.type, "MSG_GPS_REQUEST")
        assert_not_nil(reqPkt.time)
        assert_nil(reqPkt.timestamp)
        assert_eq(reqPkt.payload.replyChannel, 10005)
        assert_eq(reqPkt.payload.altitudeY, 100.0)
        assert_eq(reqPkt.payload.clientType, "AIRCRAFT")
        assert_eq(reqPkt.payload.clientSeq, 1)

        local epochBefore = st.posEpoch
        assert_true(nav_engine.filter_gps(st, {
            targetClient = "AIRCRAFT_01",
            clientSeq = 1,
            status = "FIX_OK",
            position = { x = 20.0, z = 30.0 },
            accuracy = 0.2,
            hdop = 1.0,
        }, 0.05, 1050))
        assert_eq(st.posEpoch, epochBefore + 1)
        assert_near(st.pos.x, 13.5, 1e-4) -- 0.65*10 + 0.35*20
        assert_near(st.pos.z, 23.5, 1e-4) -- 0.65*20 + 0.35*30
        assert_eq(st.pos.y, 100.0) -- Baro altitude preserved

        -- Replayed or future clientSeq rejected
        assert_false(nav_engine.filter_gps(st, {
            targetClient = "AIRCRAFT_01", clientSeq = 1, status = "FIX_OK", position = { x = 21, z = 31 }, hdop = 1.0,
        }, 0.05, 1100))
        assert_false(nav_engine.filter_gps(st, {
            targetClient = "AIRCRAFT_01", clientSeq = 99, status = "FIX_OK", position = { x = 21, z = 31 }, hdop = 1.0,
        }, 0.05, 1100))
    end)

    it("marks gpsStale after 5000ms and degrades alpha to 0.10, and accepts 3-streak snap", function()
        local st = nav_engine.init({
            system = { domainId = "AIRCRAFT_01" },
            navigation = { drComplementaryAlpha = 0.35, degradedAlpha = 0.10, gpsTimeoutMs = 5000, kinematicGateLimitM = 8.0 },
        })
        st.lastGpsFixMs = 1000
        assert_false(nav_engine.update_timeout(st, 5500))
        assert_true(nav_engine.update_timeout(st, 6100))
        assert_true(st.gpsStale)

        -- 3-streak outlier snap
        local _, s1 = nav_engine.should_query_gps(st, 6200)
        assert_false(nav_engine.filter_gps(st, { targetClient = "AIRCRAFT_01", clientSeq = s1, status = "FIX_OK", position = { x = 400, z = 0 }, hdop = 1.0 }, 0.05, 6200))
        local _, s2 = nav_engine.should_query_gps(st, 6300)
        assert_false(nav_engine.filter_gps(st, { targetClient = "AIRCRAFT_01", clientSeq = s2, status = "FIX_OK", position = { x = 401, z = 0 }, hdop = 1.0 }, 0.05, 6300))
        local _, s3 = nav_engine.should_query_gps(st, 6400)
        assert_true(nav_engine.filter_gps(st, { targetClient = "AIRCRAFT_01", clientSeq = s3, status = "FIX_OK", position = { x = 402, z = 0 }, hdop = 1.0 }, 0.05, 6400))
        assert_eq(st.lastGpsFixSeq, s3)
        assert_false(st.gpsStale)
    end)
end)
```

- [ ] **Step 2: Run unit tests to verify they fail**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --filter "channel_sentinel|nav_engine" --clean-orphans
```
Expected: FAIL (`module 'channel_sentinel' not found`, `module 'nav_engine' not found`).

- [ ] **Step 3: Implement AMM config schema, `channel_sentinel.lua`, `nav_engine.lua`, `manifest.lua` `amm` update, and `MUT-03` migration**

1. **Update `src/3_planning/amm/config/amm_config.json`**: Preserve top-level v1.2.0 keys (`domainId`, `baseChannel`, `defaultAlt`, `defaultSpeed`, `arrivalRadius`, `headless = false`) for backward compatibility with existing unit tests (`test_main_loop.lua`), bump `"version": "1.3.0"`, and add structured v1.3.0 blocks:
   - `"system"`: `{ "domainId": "AIRCRAFT_01", "airframeType": "VECTORED_VTOL", "loopFrequencyHz": 20, "uiFrequencyHz": 5, "primaryModemSide": "top", "infraModemSide": "back" }`
   - `"channels"`: `{ "bootstrapChannel": 50000, "baseChannel": 10000, "bandwidth": 40, "facilityBeaconChannel": 50003, "runwayDirectoryChannel": 50004, "atcCommChannel": 50001, "gpsPingChannel": 60001, "gpsServiceChannel": 60002 }`
   - `"navigation"`: `{ "gpsRequestRateHz": 10, "gpsTimeoutMs": 5000, "drComplementaryAlpha": 0.35, "degradedAlpha": 0.10, "maxAllowedHdop": 3.0, "kinematicGateLimitM": 8.0 }`
   - `"trajectory"`: `{ "takeoffClearanceAltitudeM": 15.0, "takeoffClimbRateMps": 2.5, "loiterRadiusM": 30.0, "loiterSpeedMps": 10.0, "loiterRadialKp": 1.0, "maxYawRateDegPerSec": 30.0, "approachDescentRateMps": -1.5, "touchdownDescentRateMps": -0.5, "landingAlignDistanceM": 0.5, "emergencyDescentRateMps": -2.0, "docking": { "creepSpeedMps": 0.4, "maxHorizToleranceM": 0.15, "maxVertToleranceM": 0.15, "maxHeadingToleranceDeg": 2.0, "abortThresholdM": 0.30, "abortHeadingThresholdDeg": 5.0, "abortSurgeBias": -0.8, "abortSafetyDistanceM": 15.0, "abortTimeoutMs": 300 } }`
   - `"safety"`: `{ "fcpStatusTimeoutMs": 500, "dynamicGuideTimeoutMs": 300, "channelProbeWaitMs": 200, "gcsBootstrapTimeoutMs": 1000, "maxApproachRetries": 3, "atcDeniedRetryIntervalSec": 15, "maxAtcDeniedRetries": 10, "deniedHoldingClimbM": 30.0, "lowFuelRthThreshold": 0.20, "emergencyLandFuelThreshold": 0.10, "goAroundTargetAltM": 100.0 }`

2. **Create `src/3_planning/amm/modules/channel_sentinel.lua`**: Migrate and refine FCP's `channel_sentinel.lua` preserving `if candidate and channel_sentinel.is_valid_base(candidate) then` (needed for `MUT-03`) and adding clean helper separation (`<= 50` lines/function):
   - Support both flat config (`cfg.baseChannel`) and nested config (`cfg.channels.baseChannel`, `cfg.system.domainId`).
   - Support `"READY"` and `"PREPARED"` ACK statuses in `on_rebind_ack` (`FCP` sends `READY` per ICD I-12).
   - Provide `is_valid_base`, `compute_base`, `start_bootstrap`, `on_block_assign`, `probe_channel`, `on_probe_ack`, `negotiate_and_probe`, `initiate_rebind`, `on_rebind_ack`, `step_rebind_transaction`.

3. **Create `src/3_planning/amm/modules/nav_engine.lua`**: Migrate FCP `nav_engine.lua` with full `TASK-122` protocol alignment (`<= 50` lines/function):
   - Track `pos`, `vel`, `attitude`, `groundSpeed`, `altitudeY`, `verticalSpeed`, `posEpoch` (`0` initial, incremented every accepted GPS fix), `navValid`, `gpsStale`, `degradedAlpha` (`0.10` fallback if `now_ms - lastGpsFixMs > 5000`).
   - `build_gps_request(state, now_ms)`: checks `should_query_gps(state, now_ms)` (`10Hz` default `100ms`), builds `ver = "1.9.5"`, `domainId = state.domainId`, `seq = reqSeq`, `type = "MSG_GPS_REQUEST"`, `time = now`, `payload = { replyChannel = baseChannel + 5, altitudeY = state.pos.y, clientType = "AIRCRAFT", clientSeq = reqSeq }`.
   - `filter_gps(state, payload, dt, now_ms)`: rejects `targetClient ~= state.domainId` (when `targetClient ~= nil`), rejects `clientSeq <= lastGpsFixSeq` or `clientSeq > lastReqSeq`, checks `hdop <= maxAllowedHdop`, applies elapsed-time kinematic outlier gate (`dt_clamped` clamped to `<= 5.0s`, 3-streak snap override), fuses 2D `x, z` with `alpha` (`drComplementaryAlpha = 0.35`, or `degradedAlpha = 0.10` after timeout / `FIX_DEGRADED`), preserves `pos.y`, clears `gpsStale = false`, increments `state.posEpoch = state.posEpoch + 1`.
   - Never call `sleep()` or `os.pullEvent()`.

4. **Update `src/0_development/installer/modules/manifest.lua` (`amm` entry)**:
   - Update `version = "1.3.0"`, register `channel_sentinel.lua` and `nav_engine.lua` (plus placeholder awareness — register `facility_client.lua` and `trajectory_generator.lua` only in Tasks 2–3 when those files exist on disk so `verify_manifest_sync.py` stays 0 Errors at every commit!).

5. **Update `tools/run_mutation_tests.py` (`MUT-03`)**:
   - Retarget `MUT-03` `"file"` to `"src/3_planning/amm/modules/channel_sentinel.lua"` and `"target_arg"` to `"3_planning/amm"`, leaving `MUT-04` and `MUT-05` untouched.

- [ ] **Step 4: Run tests, mutation check (`MUT-03`), manifest sync, and syntax check**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --clean-orphans; if ($?) { python tools/validate_lua_syntax.py }; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python -m unittest tests.harness.test_mutation_runner }
```
Expected: All `3_planning/amm` tests PASS, `0 Errors, 0 Warnings`, `test_mutation_runner` PASS. Run `python tools/run_mutation_tests.py --id MUT-03` (or full mutation run) and verify `MUT-03` KILLED.

- [ ] **Step 5: Commit Task 1**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/config/amm_config.json src/3_planning/amm/modules/channel_sentinel.lua src/3_planning/amm/modules/nav_engine.lua src/0_development/installer/modules/manifest.lua tools/run_mutation_tests.py tests/3_planning/amm/test_channel_sentinel.lua tests/3_planning/amm/test_nav_engine.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): migrate channel_sentinel and nav_engine with TASK-122 GPS protocol and MUT-03 target (TASK-207)"
```

---

### Task 2: AMM 3-Tier `facility_client.lua` & 2nd-Order Dynamic Deck Extrapolation

**Files:**
- Create: `src/3_planning/amm/modules/facility_client.lua`
- Modify: `src/0_development/installer/modules/manifest.lua` (`amm.files` += `facility_client.lua`)
- Create: `tests/3_planning/amm/test_facility_client.lua`

**Interfaces:**
- Consumes:
  - Beacon (`CH 50003` `MSG_FACILITY_BEACON`), Runway directory (`CH 50004` `MSG_RUNWAY_STATUS_RESP`), Tower ATC (`CH 50001`), GAC sector (`Base_sec+0` `MSG_GAC_CHECKIN_REQ`/`MSG_GAC_APPROACH_CLEARANCE`), Landing Pad / Runway / Docking Arm tactical streams (`Base_sec+10+Idx`: `MSG_FACILITY_STATIC_GUIDE`, `MSG_FACILITY_DYNAMIC_GUIDE`, `MSG_RUNWAY_ILS_BEACON`, `MSG_DOCKING_BEACON`, `MSG_DOCKING_STATUS`, `MSG_TOUCHDOWN_COMPLETE`), Docking Arm umbilical response (`Base+5`)
- Produces:
  - `facility_client.init(config)`
  - `facility_client.update_beacons(state, beaconPayload, now_ms)`
  - `facility_client.build_checkin_req(state, aircraftInfo, sectorId)`
  - `facility_client.on_atc_clearance(state, clrPayload, currentPos, now_ms)`
  - `facility_client.on_tactical_guide(state, pkt, now_ms)`
  - `facility_client.extrapolate_dynamic_deck(state, now_ms) -> pos, vel` (2nd-order Taylor $\mathbf{p}_{deck}(t+\Delta t) = \mathbf{p}_0 + \mathbf{v}_0 \Delta t + \frac{1}{2}\mathbf{a}_0 \Delta t^2$, $\Delta t \le 0.5\text{ s}$)
  - `facility_client.evaluate_guide_watchdog(state, now_ms) -> { triggerGoAround, retriesExhausted, holdAltClimbM, shouldRetryAtc, activeTarget }`
  - `facility_client.on_docking_status(state, payload, now_ms)` & `facility_client.build_touchdown_complete(state, craftState)`

- [ ] **Step 1: Write failing unit tests in `tests/3_planning/amm/test_facility_client.lua`**

Write tests verifying:
1. Beacon ingestion (`CH 50003`) & GAC check-in request build (`sectorId`, `aircraftId`, `craftWeight`, `craftRadius`, `airframeType`, `preferredFacilityId`, `isEmergency`).
2. `on_atc_clearance`: `CLEARED` binds `activePadId`, `padChannel`, `padMobility`; `DENIED` schedules `15s` retry up to `maxAtcDeniedRetries = 10`, raises `holdingTargetAlt` by `+30.0m` (`deniedHoldingClimbM`), and triggers `RTH` after 10 failures.
3. 2nd-order Taylor dynamic deck extrapolation (`pos = p0 + v0*dt + 0.5*a0*dt^2`), clamping `dt <= 0.5s`, plus `300ms` (`dynamicGuideTimeoutMs`) timeout triggering go-around (`retryCount + 1 <= maxApproachRetries = 3` -> `goAroundTargetAltM = 100.0`, else `FAILSAFE_RTH`).
4. Docking 4-stage lifecycle (`APPROACHING -> ALIGNED -> CAPTURED -> RETRIEVING -> HARD_LOCKED`) & `MSG_TOUCHDOWN_COMPLETE` build.

- [ ] **Step 2: Run test to verify failure**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --filter facility_client --clean-orphans
```
Expected: FAIL (`module 'facility_client' not found`).

- [ ] **Step 3: Implement `src/3_planning/amm/modules/facility_client.lua` and register in `manifest.lua`**

- Migrate baseline FCP `facility_client.lua` logic and expand strictly per `AMM_PROGRAM_SPECIFICATION.md` §3.5 & §10 (`<= 50` lines/function):
  - Store `dynamicGuide = { pos, vel, accel, lastUpdateMs, padVelocity, approachHeading }`, compute `extrapolate_dynamic_deck(state, now_ms)` clamping `dt = math.max(0.0, math.min(0.5, (now - g.lastUpdateMs) / 1000.0))`.
  - Enforce `dynamicGuideTimeoutMs = 300`: if `padMobility == "DYNAMIC"` and actively landing (`APPROACH_LAND`/`LANDING`/`DOCKING`) and elapsed `> 300`, increment `approachRetryCount` (up to `maxApproachRetries = 3`) and emit `triggerGoAround = true` (climb to `goAroundTargetAltM`), else `retriesExhausted = true` (`FAILSAFE_RTH` / `HOVER_HOLD`).
  - Handle `atcDenied`: wait `atcDeniedRetryIntervalSec = 15` (`15000ms`), up to `maxAtcDeniedRetries = 10`, returning `shouldRetryAtc = true` and `holdAltClimbM = 30.0`.
  - Handle docking status (`HARD_LOCKED` disarms / holds, `ABORTED` switches to `-0.8` abort trajectory).
- Add `{ repoPath = "src/3_planning/amm/modules/facility_client.lua", dest = "/modules/facility_client.lua", gdriveId = nil }` to `manifest.lua` `amm.files`.

- [ ] **Step 4: Run tests, manifest sync & Lua 5.2 syntax verification**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --clean-orphans; if ($?) { python tools/validate_lua_syntax.py }; if ($?) { python tools/verify_manifest_sync.py }
```
Expected: All `3_planning/amm` tests PASS, `0 Errors, 0 Warnings`.

- [ ] **Step 5: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/modules/facility_client.lua src/0_development/installer/modules/manifest.lua tests/3_planning/amm/test_facility_client.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): add facility_client with 2nd-order deck extrapolation and 300ms watchdog (TASK-207)"
```

---

### Task 3: AMM 20Hz `trajectory_generator.lua` (11 Modes, `LOITER`/`POI_HOLD`, Virtual ILS, `DOCKING` & `[I-12]` Setpoint Builder)

**Files:**
- Create: `src/3_planning/amm/modules/trajectory_generator.lua`
- Modify: `src/0_development/installer/modules/manifest.lua` (`amm.files` += `trajectory_generator.lua`)
- Create: `tests/3_planning/amm/test_trajectory_generator.lua`

**Interfaces:**
- Consumes:
  - `navState` (`{ pos, vel, attitude, groundSpeed, posEpoch }`), `facilityState`, active mission/C2 goal (`{ flightMode, targetPos, targetAlt, targetSpeed, loiterRadius, loiterDirection, poiPos, headingMode, fixedHeadingDeg, isAirborne }`), `dt`
- Produces:
  - `trajectory_generator.init(config)`
  - `trajectory_generator.MODES` (`IDLE`, `TAKEOFF`, `CRUISE`, `LOITER`, `POI_HOLD`, `APPROACH_LAND`, `LANDING`, `DOCKING`, `FAILSAFE_RTH`, `HOVER_HOLD`, `EMERGENCY_LAND`)
  - `trajectory_generator.compute(state, navState, facilityState, goal, dt, now_ms) -> setpoint` conforming strictly to ICD Interface I-12 `MSG_TRAJECTORY_SETPOINT.payload`:
    `{ flightMode, arm, flightActive, targetPos = {x,y,z}, targetVel = {vx,vy,vz}, targetAccelFF = {ax,ay,az}, targetHeadingDeg, headingMode, maxHorizSpeedMps, maxVertSpeedMps, maxTiltDeg, constraintProfile, flapHint, translationBiasHint = {surge, sway}, activeWpIndex, distanceToWp, posEpoch }`

- [ ] **Step 1: Write failing unit tests in `tests/3_planning/amm/test_trajectory_generator.lua`**

Write tests verifying all 11 modes and invariants:
1. `TAKEOFF`: anchors `takeoffOriginY`, commands vertical ascent (`vy = +2.5 m/s`, zero horizontal offset, `constraintProfile = "STRICT_LEVEL"`) until `nav.pos.y >= takeoffOriginY + 15.0`.
2. `CRUISE`: normalizes 3D direction to `targetSpeed`, computes `targetVel`, zero vertical feedforward once at `targetAlt`, `distanceToWp`, `flapHint`.
3. `LOITER`: enforces $R \ge 5.0\text{ m}$ (`math.max(5.0, r)`), handles singularity at $r < 10^{-3}$, computes CW/CCW tangential speed `v_t` + radial restoration `loiterRadialKp * (r - R)` AND centripetal feedforward `targetAccelFF` pointing inward ($\frac{v_t^2}{R}$).
4. `POI_HOLD`: holds `targetPos`, aims `targetHeadingDeg` at `poiPos` with `maxYawRateDegPerSec = 30.0` (`1.5 deg/tick`), freezes yaw inside $0.5\text{ m}$ singularity, forces `constraintProfile = "STRICT_LEVEL"`, `flapHint = 0.0`.
5. `APPROACH_LAND` & `LANDING`: 2-stage VTOL descent (`d_2D > 0.5 -> -1.5 m/s`, `d_2D <= 0.5 -> -0.5 m/s`) + uses `facility_client.extrapolate_dynamic_deck` when `padMobility == "DYNAMIC"` + virtual ILS glideslope for `FIXED_WING`/`WINGED_VTOL`.
6. `DOCKING`: 4-stage tolerances (`maxHorizToleranceM = 0.15`, `maxHeadingToleranceDeg = 2.0`, `creepSpeedMps = 0.4`), and aborts when alignment error exceeds `0.30m` or `5.0 deg`, emitting `translationBiasHint.surge = -0.8` until cleared `abortSafetyDistanceM = 15.0` (or `300ms` abort hold), resetting smoothly thereafter.
7. `EMERGENCY_LAND`: `targetVel = { vx = 0, vy = -2.0, vz = 0 }`, `constraintProfile = "STRICT_LEVEL"`, `flapHint = 1.0` (`FIXED_WING`/`WINGED_VTOL`).

- [ ] **Step 2: Run test to verify failure**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --filter trajectory_generator --clean-orphans
```
Expected: FAIL (`module 'trajectory_generator' not found`).

- [ ] **Step 3: Implement `src/3_planning/amm/modules/trajectory_generator.lua` and register in `manifest.lua`**

- Keep every function `<= 50` lines via `MODE_GENERATORS` dispatch table (`IDLE`, `TAKEOFF`, `CRUISE`, `LOITER`, `POI_HOLD`, `APPROACH_LAND`, `LANDING`, `DOCKING`, `FAILSAFE_RTH`, `HOVER_HOLD`, `EMERGENCY_LAND`).
- Reuse verified `TASK-201` math primitives adapted to setpoint coordinates:
  - Orbit tangent + centripetal feedforward: `ac = (v_t * v_t) / radius`, directed along unit radial inward vector `(-rx_u, 0, -rz_u)`.
  - Docking stage tracker + abort latch (`abortBias = -0.8` until `dist >= 15.0m`).
  - Reject/clamp non-finite inputs (`is_finite` guard on `NaN`/`Inf`).
  - Always attach `posEpoch = navState.posEpoch or 0`.
- Register `trajectory_generator.lua` in `src/0_development/installer/modules/manifest.lua` `amm.files`.

- [ ] **Step 4: Run tests, manifest sync & Lua 5.2 syntax verification**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --clean-orphans; if ($?) { python tools/validate_lua_syntax.py }; if ($?) { python tools/verify_manifest_sync.py }
```
Expected: All `3_planning/amm` tests PASS, `0 Errors, 0 Warnings`.

- [ ] **Step 5: Commit Task 3**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/modules/trajectory_generator.lua src/0_development/installer/modules/manifest.lua tests/3_planning/amm/test_trajectory_generator.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): implement 20Hz 11-mode trajectory_generator with LOITER/POI_HOLD/DOCKING (TASK-207)"
```

---

### Task 4: AMM Dual-Modem `network_manager.lua`, `c2_arbiter.lua`, `mission_engine.lua`, `ui_renderer.lua` & Dual-Coroutine `main.lua`

**Files:**
- Modify: `src/3_planning/amm/modules/network_manager.lua`
- Modify: `src/3_planning/amm/modules/c2_arbiter.lua`
- Modify: `src/3_planning/amm/modules/mission_engine.lua`
- Modify: `src/3_planning/amm/modules/ui_renderer.lua`
- Modify: `src/3_planning/amm/main.lua`
- Modify: `tests/3_planning/amm/test_network_manager.lua`
- Modify: `tests/3_planning/amm/test_c2_arbiter.lua`
- Modify: `tests/3_planning/amm/test_main_loop.lua`

**Interfaces:**
- Consumes:
  - `channel_sentinel` (Task 1), `nav_engine` (Task 1), `facility_client` (Task 2), `trajectory_generator` (Task 3)
  - `Base+2` `MSG_FLIGHT_TELEMETRY`, `Base+4` `MSG_OUTER_LOOP_STATUS` & `MSG_CHANNEL_REBIND_ACK`, `Base+1` `MSG_EMERGENCY_ALERT`
- Produces:
  - `network_manager`: dual modem (`onboardModem` / `infraModem` with single-modem fallback + `modemFallbackActive` flag), opens onboard `Base+0, +2, +3, +4, +5, +20..29` and infra `50000, 50001, 50003, 50004, 60002` + dynamic `Base_sec+*`, `send_trajectory_setpoint(payload)`, `send_rebind_command(action, txId, oldBase, newBase)`, `send_mfd_state(payload)` (suppressed when `activeSource == "MFD_ACRO"`), `send_emergency_override("E_STOP", reason, "ESTOP_CONFIRM_KEY", "AMM")`, `send_gps_request(pkt)`, `send_infra_packet(channel, pktType, payload)`
  - `c2_arbiter`: updates active goal (`flightMode`, `targetPos`, `targetAlt`, `targetSpeed`, `loiterRadius`, `loiterDirection`, `poiPos`, `headingMode`, `fixedHeadingDeg`) from `mission_engine` / `waypoint_queue` / `PILOT_ACTION_HANDLERS` instead of sending `MSG_OPERATOR_CMD` directly to FCP; monitors `Base+2` (`MSG_FLIGHT_TELEMETRY`), `Base+4` (`MSG_OUTER_LOOP_STATUS`, `500ms` timeout), fuel thresholds (`< 0.20` `FAILSAFE_RTH`, `< 0.10` `EMERGENCY_LAND`), and preserves `MUT-05` (`self.queue.state = "SUSPENDED"`)
  - `main.lua`: `step_20hz_tick(app, dt, now_ms)` & `step_5hz_downlink(app, now_ms)` inside Coroutine A (`0.05s` timer); `parallel.waitForAny(coroutine_a, coroutine_b)` when not `headless`, and single-loop Coroutine A when `headless = true` (continuing 5Hz `Base+3` downlink!).

- [ ] **Step 1: Write failing unit tests across `test_network_manager.lua`, `test_c2_arbiter.lua`, and `test_main_loop.lua`**

1. **`tests/3_planning/amm/test_network_manager.lua`**:
   - Update `send_emergency_override` expectation (or add dedicated test — wait: check if existing test sends `"CUTOFF"` or if v1.3.0 spec mandates `action = "E_STOP"`, `authKey = "ESTOP_CONFIRM_KEY"`, `source = "AMM"`; Zero-Fallback mandates `"E_STOP"` + `"ESTOP_CONFIRM_KEY"` + `"AMM"`, so update line 72-79 of `test_network_manager.lua` to match ICD v1.28.0 & AMM v1.3.0!).
   - Test dual modem binding (`top` onboard `10000/10002/10003/10004/10005` + `back` infra `50000/50001/50003/50004/60002`) vs single-modem fallback (`modemFallbackActive == true`).
   - Test `send_trajectory_setpoint` on `Base+4` (`10004` `MSG_TRAJECTORY_SETPOINT`), `send_rebind_command` on `Base+4` (`MSG_CHANNEL_REBIND`), and `send_mfd_state` suppression when `acroActive == true` (`activeSource == "MFD_ACRO"`).
2. **`tests/3_planning/amm/test_c2_arbiter.lua`**:
   - Test `ESTOP` pilot action emits `action = "E_STOP"`, `authKey = "ESTOP_CONFIRM_KEY"`, `source = "AMM"`.
   - Test `handle_outer_loop_status` & `check_timeouts`: `500ms` `Base+4` FCP loss raises alert banner & fallback goal (`HOVER_HOLD` / `FAILSAFE_RTH`), fuel `< 0.20` forces `FAILSAFE_RTH`, fuel `< 0.10` forces `EMERGENCY_LAND`.
   - Preserve `MUT-05` test (`GCS_OVERRIDE` sets `self.queue.state = "SUSPENDED"` + non-echo guarantee).
3. **`tests/3_planning/amm/test_main_loop.lua`**:
   - Test dual-coroutine orchestration (`parallel.waitForAny` receives 2 coroutines when `headless == false`, bypasses TUI and uses single 20Hz loop when `headless == true` while emitting `MSG_MFD_STATE` every 4 ticks = 5Hz unless `activeSource == "MFD_ACRO"`).
   - Test closed tick step: `Base+2` `MSG_FLIGHT_TELEMETRY` -> `nav_engine` DR -> GPS ping -> `trajectory_generator` -> `Base+4` `MSG_TRAJECTORY_SETPOINT` tx.

- [ ] **Step 2: Run tests to verify failure**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --clean-orphans
```
Expected: FAIL on new `[I-12]`, dual-modem, `"E_STOP"` / `"ESTOP_CONFIRM_KEY"`, and dual-coroutine assertions.

- [ ] **Step 3: Refactor AMM `network_manager.lua`, `c2_arbiter.lua`, `mission_engine.lua`, `ui_renderer.lua` & `main.lua`**

1. **`src/3_planning/amm/modules/network_manager.lua`**:
   - Add `bind_modems(top_modem, back_modem, base_ch)`: if both wireless modems exist (`top` != `back`), bind `onboardModem = top_modem` (`Base+0, +2, +3, +4, +5`, preserving Zone 3 `20..29` on `onboardModem`) and `infraModem = back_modem` (`50000, 50001, 50003, 50004, 60002`, plus dynamic `open_infra_channel`/`close_infra_channel` for `Base_sec+0`, `Base_sec+10+Idx`). If only one wireless modem is available, bind both `onboardModem` and `infraModem` to it, open union of channels, and set `self.modemFallbackActive = true` with a warning status. Preserve `bind_modem(m)` convenience method (`self.modem = m`, `self.onboardModem = m`, `self.infraModem = m`) for backward compatibility with unit tests.
   - Add `send_trajectory_setpoint(payload)` on `Base+4`, `send_rebind_command(action, txId, oldBase, newBase)` on `Base+4`, `send_mfd_state(payload, activeSource)` on `Base+3` (returns `false, "YIELDED_TO_MFD_ACRO"` without transmitting when `activeSource == "MFD_ACRO"`), `send_emergency_override(action, reason, authKey, source)` on `Base+1` with default `action = "E_STOP"`, `authKey = "ESTOP_CONFIRM_KEY"`, `source = "AMM"`.
   - Implement `apply_rebind(new_base)` closing old onboard `Base+0, +2, +3, +4, +5` and opening new ones without dropping active Zone 3 or infra channels.

2. **`src/3_planning/amm/modules/mission_engine.lua` & `src/3_planning/amm/modules/c2_arbiter.lua`**:
   - In `mission_engine.lua`: decouple `DISPATCHERS` from old FCP `Base+0` `MSG_OPERATOR_CMD` loop — instead emit structured `currentGoal` (`{ flightMode, targetPos, targetAlt, targetSpeed, loiterRadius, loiterDirection, poiPos, headingMode, arrivalRadius }`) stored on `self.currentGoal` / returned via `get_trajectory_goal()`, while preserving `hook_runner` Zone 3 (`PAYLOAD_ACTION`, `REDSTONE_ACTION`) and mission FSM transitions! (Note: keep `net:send_operator_cmd` only if GCS forwarding or legacy test stubs inspect it, OR better: `c2_arbiter` manages the active trajectory goal for `trajectory_generator` and external `Base+0` `MSG_OPERATOR_CMD` is inbound-only from GCS/external terminal onto AMM!). Verify every `tests/3_planning/amm/` test stays green (`mission_engine` + `c2_arbiter` + `condition_evaluator` + `hook_runner`).
   - In `c2_arbiter.lua`:
     - Handle inbound `Base+0` `MSG_OPERATOR_CMD` from GCS (`GCS_OVERRIDE` suspends `queue` via `self.queue.state = "SUSPENDED"` [`MUT-05`] and pauses `engine`, setting `authority = "GCS_OVERRIDE"` & updating `activeGoal` if GCS specifies `HOLD`/`RTH`/`LAND`; non-echo!).
     - Handle `handle_flight_telemetry(packet, now_ms)` (`Base+2`): record `latest_telem`, `lastTelemMs`, check `fuel < 0.10 -> EMERGENCY_LAND` / `fuel < 0.20 -> FAILSAFE_RTH`, feed `activeSource` (`"MFD_ACRO"` suspends AMM `Base+3` emission).
     - Handle `handle_outer_loop_status(packet, now_ms)` (`Base+4`): record `latest_outer_status`, `lastOuterStatusMs`, check `500ms` timeout (`fcpStatusTimeoutMs`).
     - `ESTOP` pilot action calls `self.net:send_emergency_override("E_STOP", "PILOT_ESTOP_HOTKEY", "ESTOP_CONFIRM_KEY", "AMM")`.
     - Add `get_effective_goal()` returning `{ flightMode, arm, flightActive, targetPos, targetAlt, targetSpeed, loiterRadius, loiterDirection, poiPos, headingMode, facilityId }` consumed by `trajectory_generator`.

3. **`src/3_planning/amm/modules/ui_renderer.lua` & `src/3_planning/amm/main.lua`**:
   - Minor left-pane update in `ui_renderer.lua`: show `NAV: GPS_OK|DR_STALE` / `FCP: TRACKING|PASSIVE|TIMEOUT` / `FAC: <padId>` cleanly inside existing unused rows `12..15` (all strictly padded to 24 chars inside col `2..25`, `51` chars total).
   - In `main.lua`:
     - Wire `channel_sentinel`, `nav_engine`, `facility_client`, `trajectory_generator` into `create_app(cfg, modems)`!
     - `step_20hz_tick(app, dt, now_ms)`: run DR prediction -> periodic 10Hz GPS request -> facility watchdog -> `channel_sentinel.step_rebind_transaction` -> `trajectory_generator.compute` -> `Base+4` `MSG_TRAJECTORY_SETPOINT` tx -> every 4th tick (`tickCount % 4 == 0`, 5Hz) aggregate `MSG_MFD_STATE` on `Base+3` unless `arbiter.activeSource == "MFD_ACRO"`.
     - Split `coroutine_a` (20Hz timer + `modem_message` + `mission_engine:tick`) and `coroutine_b` (5Hz UI render timer + immediate `key`/`char`/`paste`/`file_transfer` forwarding) via `parallel.waitForAny`, or single-loop `coroutine_a` in `headless` mode. Zero `sleep()` calls.

- [ ] **Step 4: Run full AMM suite, manifest sync, mutation check (`MUT-03`, `MUT-04`, `MUT-05`), and syntax check (Phase 1 Gate)**

Run:
```powershell
python tools/run_unit_tests.py --target 3_planning/amm --clean-orphans; if ($?) { python tools/validate_lua_syntax.py }; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python tools/run_mutation_tests.py --id MUT-03 }; if ($?) { python tools/run_mutation_tests.py --id MUT-04 }; if ($?) { python tools/run_mutation_tests.py --id MUT-05 }
```
Expected: All `3_planning/amm` tests PASS, `0 Errors, 0 Warnings`, `MUT-03`/`MUT-04`/`MUT-05` all KILLED.

- [ ] **Step 5: Commit Task 4 (Phase 1 Complete)**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/modules/network_manager.lua src/3_planning/amm/modules/c2_arbiter.lua src/3_planning/amm/modules/mission_engine.lua src/3_planning/amm/modules/ui_renderer.lua src/3_planning/amm/main.lua tests/3_planning/amm/test_network_manager.lua tests/3_planning/amm/test_c2_arbiter.lua tests/3_planning/amm/test_main_loop.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): wire dual-modem Base+4 [I-12], 5Hz MFD yield, and 20Hz/5Hz dual coroutines (TASK-207)"
```

---

## Phase 2: TASK-208 — FCP v2.0.0 SE(3) Outer-Loop Controller Slimming

### Task 5: FCP 3-Channel Single-Modem `network_manager.lua` (`Base+4/+2/+1`) & `state_propagator.lua`

**Files:**
- Rewrite: `src/2_guidance/fcp/modules/network_manager.lua`
- Create: `src/2_guidance/fcp/modules/state_propagator.lua`
- Create: `tests/2_guidance/fcp/test_fcp_network_and_rebind.lua`
- Create: `tests/2_guidance/fcp/test_state_propagator.lua`

**Interfaces:**
- Consumes:
  - Inbound `Base+4` (`MSG_TRAJECTORY_SETPOINT`, `MSG_CHANNEL_REBIND`), `Base+2` (`MSG_FLIGHT_TELEMETRY`), `Base+1` (`MSG_CHANNEL_REBIND_ACK`)
- Produces:
  - `network_manager.init(cfg, modemResolver)`: binds single `top` wireless modem and opens ONLY 3 channels: `trajectory = Base+4`, `telemetry = Base+2`, `guidance = Base+1` (asserts NO `50000`, `60001`, `60002`, `Base+0`, `Base+3`, `Base+5` opened!).
  - `network_manager.ingest_modem_event(...)`, `send_attitude_cmd(net, payload)` (`Base+1`), `send_outer_loop_status(net, payload)` (`Base+4`), `step_rebind_watchdog(net, now_ms)` (`500ms` timeout relay rollback -> VAS `Base+1`, atomic config persist on `COMMIT` to `config/fcp_config.json`).
  - `state_propagator.init(cfg)`, `on_telemetry(state, telemPayload, now_ms)`, `on_setpoint_epoch(state, setpointPayload)`, `propagate(state, now_ms)` -> `{ pos, vel, attitude, angularRates, groundSpeed, airspeed, posEpoch, lastTelemMs, navStale, actuatorHealth }` (`dt` clamped to `<= 0.1s`, `posEpoch` step delta clamped to `posMergeMaxStepM = 2.0`, `navStale` at `> 500ms`).

- [ ] **Step 1: Write failing unit tests in `test_fcp_network_and_rebind.lua` and `test_state_propagator.lua`**

Verify:
1. FCP opens ONLY `10004`, `10002`, `10001` (never opens `50000`, `60001`, `60002`, `10000`, `10003`, `10005`).
2. `MSG_CHANNEL_REBIND` relay (`PREPARE` opens `newBase + 4, +2, +1` and forwards `PREPARE` on `oldBase+1`; receiving `MSG_CHANNEL_REBIND_ACK` relays `READY` to AMM `oldBase+4`; `COMMIT` closes old 3 channels, switches `baseChannel`, saves `config/fcp_config.json`; `500ms` ACK timeout sends `ROLLBACK` and closes pending `newBase` channels without mutating `baseChannel`).
3. `state_propagator`: integrates `vel * dt` (`dt` clamped to `0.1s`), limits `posEpoch` correction jump to `2.0m` per tick (`posMergeMaxStepM`), and raises `navStale = true` if telemetry age exceeds `500ms`.

- [ ] **Step 2: Run tests to verify failure**

Run:
```powershell
python tools/run_unit_tests.py --target 2_guidance/fcp --filter "test_fcp_network_and_rebind|test_state_propagator" --clean-orphans
```
Expected: FAIL.

- [ ] **Step 3: Implement `src/2_guidance/fcp/modules/network_manager.lua` and `src/2_guidance/fcp/modules/state_propagator.lua`**

- `network_manager.lua` (`<= 50` lines/function):
  - Reject packets with missing/non-table structure, `ver ~= "1.9.5"`, or mismatched `domainId`.
  - Dispatch strictly by channel/type (`Base+4` `[I-12]`, `Base+2` telemetry, `Base+1` rebind ACK).
  - Rebind transaction state machine: `PREPARE` -> forward on `oldBase+1` -> start `500ms` watchdog -> wait `MSG_CHANNEL_REBIND_ACK` from VAS -> emit `MSG_CHANNEL_REBIND_ACK` on `oldBase+4` -> handle `COMMIT`/`ROLLBACK` & atomic `fs.open(..., "w")` JSON write on `COMMIT`.
- `state_propagator.lua` (`<= 50` lines/function):
  - Store `pos`, `vel`, `attitude`, `angularRates`, `airspeed`, `groundSpeed`, `actuatorHealth`, `activeSource`, `posEpoch`, `lastTelemMs`, `lastPropagateMs`.
  - When `setpoint.posEpoch > state.lastSyncedEpoch` and `setpoint.targetRefPos` / `setpoint.craftPos` (per ICD I-12 `craftPos` / GPS epoch anchor) is present: compute correction vector `delta`, clamp magnitude to `posMergeMaxStepM = 2.0`, add clamped step to `pos`, and update `lastSyncedEpoch` (if `||delta|| <= 2.0`, converge completely).
  - Clamp `dt = math.max(0.0, math.min(0.1, (now_ms - lastPropagateMs) / 1000.0))` before Euler integration.

- [ ] **Step 4: Run tests & syntax check**

Run:
```powershell
python tools/run_unit_tests.py --target 2_guidance/fcp --filter "test_fcp_network_and_rebind|test_state_propagator" --clean-orphans; if ($?) { python tools/validate_lua_syntax.py }
```
Expected: PASS, 0 syntax errors.

- [ ] **Step 5: Commit Task 5**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/2_guidance/fcp/modules/network_manager.lua src/2_guidance/fcp/modules/state_propagator.lua tests/2_guidance/fcp/test_fcp_network_and_rebind.lua tests/2_guidance/fcp/test_state_propagator.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "refactor(fcp): slim network_manager to 3 channels and add state_propagator (TASK-208)"
```

---

### Task 6: FCP v2.0.0 6-State `flight_fsm.lua` & `fcp_config.json` Alignment

**Files:**
- Modify: `src/2_guidance/fcp/config/fcp_config.json`
- Rewrite: `src/2_guidance/fcp/modules/flight_fsm.lua`
- Create: `tests/2_guidance/fcp/test_flight_fsm_v2.lua`

**Interfaces:**
- Consumes:
  - `telemState` (`activeSource`, `controlState`, `altitudeY`), `setpoint` (`flightMode`, `arm`, `flightActive`, `lastRxMs`), `now_ms`
- Produces:
  - `flight_fsm.STATES = { BOOT = true, IDLE_ARMED = true, ACTIVE_TRACKING = true, PASSIVE_TRACKING = true, AMM_TIMEOUT_HOLD = true, EMERGENCY_LAND = true }`
  - `flight_fsm.step(state, ctx, now_ms) -> state, events` (`triggerBumpless = true` on `PASSIVE_TRACKING -> ACTIVE_TRACKING`, `AMM_TIMEOUT_HOLD -> ACTIVE_TRACKING`, and `flightMode` transitions; `500ms` AMM timeout -> `AMM_TIMEOUT_HOLD` -> `10s` -> `EMERGENCY_LAND`; explicit `EMERGENCY_LAND` setpoint -> `EMERGENCY_LAND`).
  - Helper guard function with exact target line `if flight_fsm.is_transition_allowed(curr, nextState) then` (designed to replace `MUT-14` cleanly in Task 8).

- [ ] **Step 1: Write failing unit tests in `tests/2_guidance/fcp/test_flight_fsm_v2.lua`**

Verify:
1. Only 6 valid states exist (`BOOT`, `IDLE_ARMED`, `ACTIVE_TRACKING`, `PASSIVE_TRACKING`, `AMM_TIMEOUT_HOLD`, `EMERGENCY_LAND`); invalid target state rejected cleanly (`is_transition_allowed` negative test — kills future `MUT-14`!).
2. `BOOT -> IDLE_ARMED` when fresh telemetry & valid `config/fcp_config.json` load; `IDLE_ARMED -> ACTIVE_TRACKING` on `flightActive == true`; `ACTIVE_TRACKING -> PASSIVE_TRACKING` when `activeSource == "MFD_ACRO"` (suppresses FCP `Base+1` tx); `PASSIVE_TRACKING -> ACTIVE_TRACKING` sets `bumplessTriggered = true` & `rampStartMs = now_ms`.
3. `ACTIVE_TRACKING` with `now_ms - lastSetpointMs > 500` transitions to `AMM_TIMEOUT_HOLD`; holding `> 10000ms` in `AMM_TIMEOUT_HOLD` transitions to `EMERGENCY_LAND`; fresh setpoint during `AMM_TIMEOUT_HOLD` recovers to `ACTIVE_TRACKING` with `bumplessTriggered = true`.

- [ ] **Step 2: Run test to verify failure**

Run:
```powershell
python tools/run_unit_tests.py --target 2_guidance/fcp --filter test_flight_fsm_v2 --clean-orphans
```
Expected: FAIL (legacy 16-state FSM fails 6-state checks).

- [ ] **Step 3: Update `src/2_guidance/fcp/config/fcp_config.json` & rewrite `src/2_guidance/fcp/modules/flight_fsm.lua`**

1. Update `src/2_guidance/fcp/config/fcp_config.json`: remove `bootstrapChannel`, `mfdInstrumentChannel`, `facilityBeaconChannel`, `atcCommChannel`, `gpsPingChannel`, `gpsServiceChannel`, `infraModemSide`, `navigation`, `docking`, `atcDenied*`; set `"version": "2.0.0"`, `system.debug = false`, `channels = { baseChannel = 10000, bandwidth = 40, trajectoryOffset = 4, telemetryOffset = 2, guidanceOffset = 1 }`, `propagation = { maxDtSec = 0.1, posMergeMaxStepM = 2.0, navStaleTimeoutMs = 500 }`, `se3 = { gravityMps2 = 11.0, kp = { x = 1.6, y = 2.2, z = 1.6 }, kd = { x = 1.4, y = 1.8, z = 1.4 }, ki = { x = 0.08, y = 0.12, z = 0.08 }, drag = { x = 0.02, y = 0.0, z = 0.02 }, integralLimit = { x = 3.0, y = 4.0, z = 3.0 }, maxThrustAccel = 22.0, minThrustAccel = 2.0, hoverThrustRatio = 0.635, tiltAssistedMaxPitchDeg = 10.0, tiltAssistedThresholdSpeedMps = 15.0, tiltSlewRateDegPerSec = 15.0, gimbalSlewRate = 2.0, multirotorMaxTiltDeg = 25.0, wingedVtolVLowMps = 8.0, wingedVtolVHighMps = 18.0, fixedWingRotationSpeedMps = 12.0, fixedWingStallSpeedMps = 10.0 }`, `safety = { ammSetpointTimeoutMs = 500, ammTimeoutHoldToEmgMs = 10000, rebindAckTimeoutMs = 500, bumplessRampSec = 2.0, emergencyDescentRateMps = -2.0 }`.
2. Implement 6-state `flight_fsm.lua` (`<= 50` lines/function) with `flight_fsm.is_transition_allowed(curr, nextState)` transition matrix and `step(state, ctx, now_ms)`.

- [ ] **Step 4: Run test & syntax check**

Run:
```powershell
python tools/run_unit_tests.py --target 2_guidance/fcp --filter test_flight_fsm_v2 --clean-orphans; if ($?) { python tools/validate_lua_syntax.py }
```
Expected: PASS, 0 syntax errors.

- [ ] **Step 5: Commit Task 6**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/2_guidance/fcp/config/fcp_config.json src/2_guidance/fcp/modules/flight_fsm.lua tests/2_guidance/fcp/test_flight_fsm_v2.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "refactor(fcp): implement v2.0.0 6-state flight_fsm and slim fcp_config.json (TASK-208)"
```

---

### Task 7: FCP v2.0.0 Unified `SE(3)` `outer_loop_controller.lua` (6 Airframes, `QUATERNION_RATE`, Anti-Windup & Bumpless Ramp)

**Files:**
- Create: `src/2_guidance/fcp/modules/outer_loop_controller.lua`
- Create: `tests/2_guidance/fcp/test_outer_loop_se3.lua`

**Interfaces:**
- Consumes:
  - `navState` (from `state_propagator`), `setpoint` (from `Base+4`), `fsmCtx` (`{ currentState, bumplessActive, rampAlpha, vasSat, actuatorHealth }`), `dt`
- Produces:
  - `outer_loop_controller.init(cfg)`
  - `outer_loop_controller.is_airframe_supported(airframeType)` (exactly 6: `FIXED_WING`, `WINGED_VTOL`, `VECTORED_VTOL`, `ADVANCED_VTOL`, `QUADROTOR`, `HEXAROTOR`)
  - `outer_loop_controller.compute_desired_accel(state, nav, setpoint, dt, satFlags)` -> `a_des = { ax, ay, az }` with exact gravity compensation $g = 11.0\text{ m/s}^2$ (`ay = ffY + kpY*ey + kdY*evy + intY - dY*vy + 11.0`) and conditional anti-windup
  - `outer_loop_controller.compute(state, nav, setpoint, fsmCtx, dt)` -> Zero-Fallback `MSG_ATTITUDE_CMD.payload`:
    `{ source = "FCP", arm = true, flightActive = true, flightMode = ..., mode = airframeType, commandType = "QUATERNION_RATE", targetQuaternion = { w, x, y, z }, targetAngularRates = { pitchRate, rollRate, yawRate }, collectiveThrust, flapTarget, translationBias = ... }` (ZERO `angleTargets`, ZERO `targetThrottle`, ZERO `targetClimbRate`, ZERO `translationBias.heave`).

- [ ] **Step 1: Write failing unit tests in `tests/2_guidance/fcp/test_outer_loop_se3.lua`**

Verify all FCP v2.0.0 §5–§6 requirements across all 6 airframes:
1. Hovering equilibrium ($\mathbf{e}_p = \mathbf{e}_v = 0, \mathbf{a}_{ff} = 0$) yields `a_des.y == 11.0` ($g = 11.0\text{ m/s}^2$) and `collectiveThrust ~ hoverThrustRatio (0.635)`.
2. Conditional anti-windup: when `vasSat.axisSaturatedPos.surge == true` or `tiltClamped == true`, positive error does not increase the integrator on that axis, whereas negative error unwinds it (`reset_integrators` resets all axes).
3. Zero-Fallback Wire Purity: returned command MUST have `commandType == "QUATERNION_RATE"`, `targetQuaternion = {w,x,y,z}`, `targetAngularRates = {pitchRate,rollRate,yawRate}`, numeric `collectiveThrust in [0, 1]`, AND strictly `nil` for `angleTargets`, `rateTargets`, `targetThrottle`, `targetClimbRate`, and `translationBias.heave`.
4. All 6 Airframe Projections:
   - `QUADROTOR` / `HEXAROTOR`: tilts thrust vector toward `a_des` clamped to `25.0 deg`, `translationBias == nil`, `flapTarget == 0.0`.
   - `VECTORED_VTOL` & `ADVANCED_VTOL`:
     - `STRICT_LEVEL` keeps level pitch/roll (`0.0 deg`), drives horizontal `translationBias = { surge, sway }` (`ADVANCED_VTOL` applies `gimbalSlewRate = 2.0/s`!).
     - `TILT_ASSISTED` slews pitch up to `+-10 deg` at `15 deg/s` above `15 m/s` except in `LOITER`/`POI_HOLD`.
     - **Sway-Loss Tilt Fallback**: when `actuatorHealth.tap == false` or `swayLoss == true`, falls back automatically from `STRICT_LEVEL` to tilt projection using pitch/roll!
   - `FIXED_WING`: Bank-to-Turn roll projection toward lateral acceleration (`translationBias == nil`), respects `rotationSpeed >= 12 m/s` and `stallSpeed >= 10 m/s`.
   - `WINGED_VTOL`: blends `[8, 18] m/s` horizontally (`translationBias` scales by `(1 - alpha)`), `flapTarget` clamped to `1.0`.
5. `PASSIVE_TRACKING -> ACTIVE_TRACKING` & `AMM_TIMEOUT_HOLD -> ACTIVE_TRACKING`: applies smooth `2.0s` bumpless ramp while preserving `ADVANCED_VTOL` `prev_surge`/`prev_sway` continuity!
6. `AMM_TIMEOUT_HOLD` self-generates level hover (`targetVel = 0`, `a_des.y ~ 11.0`); `EMERGENCY_LAND` commands `-2.0 m/s` descent with level attitude.

- [ ] **Step 2: Run test to verify failure**

Run:
```powershell
python tools/run_unit_tests.py --target 2_guidance/fcp --filter test_outer_loop_se3 --clean-orphans
```
Expected: FAIL (`module 'outer_loop_controller' not found`).

- [ ] **Step 3: Implement `src/2_guidance/fcp/modules/outer_loop_controller.lua`**

- Structure into clean `<= 50`-line functions using `AIRFRAME_PROJECTORS` dispatch table (`FIXED_WING`, `WINGED_VTOL`, `VECTORED_VTOL`, `ADVANCED_VTOL`, `QUADROTOR`, `HEXAROTOR`).
- Quaternion & Euler helper (`euler_deg_to_quat(pitchDeg, rollDeg, yawDeg)` consistent with VAS `quat.lua` convention) and attitude rate feedforward helper (`compute_yaw_rate_ff(setpoint, nav)` bounded by `maxYawRateDegPerSec`).
- Keep integrator anti-windup guard explicitly checkable (supports `MUT-15` gain sign & `MUT-23` sway-loss fallback guard cleanly).
- Zero legacy fields emitted on output table.

- [ ] **Step 4: Run test & syntax check**

Run:
```powershell
python tools/run_unit_tests.py --target 2_guidance/fcp --filter test_outer_loop_se3 --clean-orphans; if ($?) { python tools/validate_lua_syntax.py }
```
Expected: PASS, 0 syntax errors.

- [ ] **Step 5: Commit Task 7**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/2_guidance/fcp/modules/outer_loop_controller.lua tests/2_guidance/fcp/test_outer_loop_se3.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(fcp): implement unified SE(3) outer_loop_controller for 6 airframes (TASK-208)"
```

---

### Task 8: FCP `main.lua` Headless-Default Runtime, Legacy 14-File Removal, `manifest.lua` (`v2.0.0`), `MUT-14/15/23` & Phase 2 Gate

**Files:**
- Rewrite: `src/2_guidance/fcp/main.lua`
- Modify: `src/2_guidance/fcp/modules/ui_renderer.lua` (slim optional `debug: true` 51x19 HUD)
- Delete (14 files): `src/2_guidance/fcp/fcp_runtime.lua`, `src/2_guidance/fcp/modules/channel_sentinel.lua`, `src/2_guidance/fcp/modules/facility_client.lua`, `src/2_guidance/fcp/modules/nav_engine.lua`, `src/2_guidance/fcp/modules/operator_handler.lua`, `src/2_guidance/fcp/modules/thruster_profile.lua`, `src/2_guidance/fcp/modules/guidance_controller.lua`, `src/2_guidance/fcp/modules/vectored_vtol_driver.lua`, `src/2_guidance/fcp/modules/advanced_vtol_driver.lua`, `src/2_guidance/fcp/modules/drivers/drone_driver.lua`, `src/2_guidance/fcp/modules/drivers/fixed_wing_driver.lua`, `src/2_guidance/fcp/modules/drivers/helicopter_driver.lua`, `src/2_guidance/fcp/modules/aerodynamic_controller.lua`, `src/2_guidance/fcp/node_fcp_sim.lua`
- Delete obsolete FCP v1.x unit tests that directly required deleted files (check all files in `tests/2_guidance/fcp/` first, replacing coverage inside `test_fcp_main_v2.lua`): inspect & clean old `tests/2_guidance/fcp/` files
- Create: `tests/2_guidance/fcp/test_fcp_main_v2.lua`
- Modify: `src/0_development/installer/modules/manifest.lua` (`fcp` v2.0.0 entry + `AIRFRAME_PRESETS`)
- Modify: `tools/run_mutation_tests.py` (`MUT-14`, `MUT-15`, `MUT-23`)

**Interfaces:**
- Consumes:
  - `network_manager`, `state_propagator`, `flight_fsm`, `outer_loop_controller`, optional `ui_renderer`
- Produces:
  - `main.load_config(path)`, `main.create_context(cfg, modemResolver)`, `main.step_tick(ctx, dt, now_ms)`, `main.run(args)` (`debug: false` default headless 20Hz loop; `debug: true` launches `parallel.waitForAny` daemon + 5Hz `ui_renderer`)

- [ ] **Step 1: Write failing unit tests in `tests/2_guidance/fcp/test_fcp_main_v2.lua` (and audit `tests/0_development/installer/`)**

Verify:
1. `load_config` reads `config/fcp_config.json` with `debug == false` default and 3 channels (`baseChannel = 10000`, offsets `4/2/1`).
2. `step_tick`: propagates state -> steps FSM -> skips `Base+1` tx during `PASSIVE_TRACKING` (`activeSource == "MFD_ACRO"`) -> emits `MSG_OUTER_LOOP_STATUS` on `Base+4` -> emits `MSG_ATTITUDE_CMD` (`QUATERNION_RATE`) on `Base+1` during `ACTIVE_TRACKING`/`AMM_TIMEOUT_HOLD`/`EMERGENCY_LAND`.
3. Headless execution (`debug: false`) skips `parallel.waitForAny` and `term.clear`/`term.blit`; `debug: true` invokes `parallel.waitForAny` with 2 coroutines and renders exact `51x19` rows in `ui_renderer`.
4. Ensure `test_fcp_network_and_rebind.lua`, `test_state_propagator.lua`, `test_flight_fsm_v2.lua`, `test_outer_loop_se3.lua`, `test_fcp_main_v2.lua` kill `MUT-14`, `MUT-15`, `MUT-23`.

- [ ] **Step 2: Run test to verify failure**

Run:
```powershell
python tools/run_unit_tests.py --target 2_guidance/fcp --filter test_fcp_main_v2 --clean-orphans
```
Expected: FAIL.

- [ ] **Step 3: Implement `main.lua` & `ui_renderer.lua`, delete 14 legacy files & obsolete tests, update `manifest.lua` & `tools/run_mutation_tests.py`**

1. Rewrite `src/2_guidance/fcp/main.lua` (`<= 50` lines/function, Zero-Sleep `os.startTimer(0.05)` loop, optional `parallel.waitForAny` when `debug == true`).
2. Update `src/2_guidance/fcp/modules/ui_renderer.lua` to display v2.0.0 telemetry (`Base+4/+2/+1`, `FSM`, `SE(3)` `a_des`, `pos`, `epoch`, `bumpless`) in exact 51x19 `term.blit`.
3. Remove the 14 deprecated/migrated files from `src/2_guidance/fcp/` (check `tests/2_guidance/fcp/` and remove obsolete v1.x test files so `--require-tests` sees clean v2.0.0 FCP suite).
4. Update `src/0_development/installer/modules/manifest.lua`:
   - `fcp`: `version = "2.0.0"`, `startup.args` updated if needed (keep `target = "/main.lua"`), `defaultConfigs["/config/fcp_config.json"]` aligned with slim v2.0.0 schema, `files` list updated strictly to:
     `main.lua`, `config/fcp_config.json`, `modules/network_manager.lua`, `modules/state_propagator.lua`, `modules/outer_loop_controller.lua`, `modules/flight_fsm.lua`, `modules/ui_renderer.lua`, plus `/lib/avionics_sensors.lua`.
   - Clean up `manifest.AIRFRAME_PRESETS` (`remove obsolete infraModemSide / gpsPingChannel / facilityBeaconChannel` from FCP template, checking `tests/0_development/installer/` expectations).
5. Update `tools/run_mutation_tests.py`:
   - `MUT-14` -> `src/2_guidance/fcp/modules/flight_fsm.lua` (`if not flight_fsm.is_transition_allowed(curr, nextState) then` -> flip condition), `target_arg = "2_guidance/fcp"`.
   - `MUT-15` -> `src/2_guidance/fcp/modules/outer_loop_controller.lua` (gravity constant `11.0` or vertical acceleration sign in `compute_desired_accel`), `target_arg = "2_guidance/fcp"`.
   - `MUT-23` -> `src/2_guidance/fcp/modules/outer_loop_controller.lua` (sway-loss tilt fallback condition or bumpless blend weight), `target_arg = "2_guidance/fcp"`.

- [ ] **Step 4: Run FCP + Installer tests, manifest sync, `MUT-14/15/23`, harness & syntax check (Phase 2 Gate)**

Run:
```powershell
python tools/run_unit_tests.py --target 2_guidance/fcp --clean-orphans; if ($?) { python tools/run_unit_tests.py --target 0_development/installer --clean-orphans }; if ($?) { python tools/validate_lua_syntax.py }; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python -m unittest tests.harness.test_mutation_runner tests.harness.test_installer_integrity }; if ($?) { python tools/run_mutation_tests.py --id MUT-14 }; if ($?) { python tools/run_mutation_tests.py --id MUT-15 }; if ($?) { python tools/run_mutation_tests.py --id MUT-23 }
```
Expected: All PASS, `0 Errors, 0 Warnings`, `MUT-14`/`MUT-15`/`MUT-23` all KILLED.

- [ ] **Step 5: Commit Task 8 (Phase 2 Complete)**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add -A src/2_guidance/fcp tests/2_guidance/fcp src/0_development/installer/modules/manifest.lua tools/run_mutation_tests.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "refactor(fcp): complete v2.0.0 SE(3) outer-loop slimming and manifest/mutation sync (TASK-208)"
```

---

## Phase 3: TASK-209 — VAS v1.19.0 `QUATERNION_RATE` Normalization & ACRO/Failsafe Alignment

### Task 9: VAS Zero-Fallback `QUATERNION_RATE`/`RATE_COMMAND` & Normal-Flight `compute_climb_wrench` Removal

**Files:**
- Modify: `src/1_control/vas/modules/vehicle_policy.lua`
- Modify: `src/1_control/vas/modules/flight_dynamics_core.lua`
- Modify: `src/1_control/vas/modules/state_machine.lua`
- Create: `tests/1_control/vas/test_vas_quaternion_rate.lua`
- Modify: `tests/1_control/vas/test_vas_core.lua`
- Modify: `tests/1_control/vas/test_vas_advanced_vtol.lua`

**Interfaces:**
- Consumes:
  - `MSG_ATTITUDE_CMD` (`commandType = "QUATERNION_RATE"` or `"RATE_COMMAND"` with `targetQuaternion`, `targetAngularRates`, `collectiveThrust` in `[0, 1]`, optional `flapTarget`, optional `translationBias { surge, sway }`)
  - `MSG_EMERGENCY_OVERRIDE` (`action = "E_STOP"`, `authKey = "ESTOP_CONFIRM_KEY"`, `source = "AMM"|"MFD"|"GCS"`)
- Produces:
  - `vehicle_policy.resolve_guidance_targets(cmd)`: Zero-Fallback strict `cmd.targetQuaternion` (ignores/rejects legacy `targetOrientation` / `angleTargets` / `targetClimbRate` / `targetThrottle` / `translationBias.heave`); `vFe = 15.0` default (`flapVfeLimit`).
  - `flight_dynamics_core.compute(state, telem, guidance, dt, satStatus)`: computes `attWrench` (attitude error against `targetQuaternion` + `targetAngularRates` angular-rate damping/feedforward, or pure rate PI-D when `commandType == "RATE_COMMAND"`) + open-loop `heave`/`surge` effort directly from `guidance.collectiveThrust * (state.thrustScale or 15.0)` — **ZERO** normal-flight `compute_climb_wrench` vertical velocity PI loop!
  - `state_machine.lua`: isolates vertical velocity PI hold (`0.0 m/s` in `FAILSAFE_HOLD`, `-1.5 m/s` in `EMERGENCY_LAND`, `-1.0 m/s` in `AIRBORNE_EMERGENCY`) inside `get_effective_command(state, comState)` producing normalized `QUATERNION_RATE` (`targetQuaternion`, `targetAngularRates = {0,0,0}`, `collectiveThrust in [0, 1]`, `translationBias = {surge=0, sway=0}`); `arbitrate_c2` verifies `authKey == "ESTOP_CONFIRM_KEY"` for `E_STOP` and prioritizes `E_STOP > MFD_ACRO > FCP`.

- [ ] **Step 1: Write failing unit tests in `tests/1_control/vas/test_vas_quaternion_rate.lua` & update `test_vas_advanced_vtol.lua`**

Verify:
1. `vehicle_policy` parses `QUATERNION_RATE` (`targetQuaternion`, `targetAngularRates`, `collectiveThrust`) cleanly, drops any `translationBias.heave`, ignores legacy `angleTargets`/`targetOrientation`/`targetClimbRate`/`targetThrottle`, and clamps flaps at `vFe = 15.0`.
2. `flight_dynamics_core.compute()` during normal `QUATERNION_RATE` flight produces `heave` solely from `collectiveThrust` + `targetQuaternion` (changing `telem.verticalSpeed` while keeping `collectiveThrust = 0.635` constant must NOT change `heave` or `integrators.climb` — proving vertical PI is completely absent from normal flight!).
3. `flight_dynamics_core.compute()` with `commandType = "RATE_COMMAND"` bypasses quaternion angle P-error and tracks `targetAngularRates` directly for `MFD_ACRO`.
4. `state_machine.get_effective_command()` during `FAILSAFE_HOLD` and `EMERGENCY_LAND` outputs `commandType = "QUATERNION_RATE"` with closed-loop vertical speed compensation reflected directly inside normalized `collectiveThrust in [0.0, 1.0]`.
5. `state_machine.arbitrate_c2`: rejects `E_STOP` missing `"ESTOP_CONFIRM_KEY"`, accepts `E_STOP` with `authKey == "ESTOP_CONFIRM_KEY"`, preempts `MFD_ACRO` over `FCP`, and returns to `FCP` when `acroActive == false`.
6. Update legacy `cmd = { targetThrottle = 0.2, targetOrientation = ... }` fixture in `test_vas_advanced_vtol.lua:47-51` to `QUATERNION_RATE` (`collectiveThrust = 0.2`, `targetQuaternion = ...`).

- [ ] **Step 2: Run VAS unit tests to verify failure**

Run:
```powershell
python tools/run_unit_tests.py --target 1_control/vas --clean-orphans
```
Expected: FAIL (`collectiveThrust` ignored / `compute_climb_wrench` mutating `heave` on `verticalSpeed` change / legacy `angleTargets` active).

- [ ] **Step 3: Refactor `vehicle_policy.lua`, `flight_dynamics_core.lua`, and `state_machine.lua`**

1. **`src/1_control/vas/modules/vehicle_policy.lua`** (`<= 50` lines/function):
   - Update `vFe = (stall.flapVfeLimit) or cfg.vFe or 15.0`.
   - Zero-Fallback `resolve_guidance_targets(cmd)`: read ONLY `cmd.targetQuaternion` (normalize if table with `w`, else `quat.identity()`).
   - `pre_process_guidance`: populate `{ commandType = rawCmd.commandType or "QUATERNION_RATE", targetQuaternion, targetAngularRates = rawCmd.targetAngularRates or { pitchRate = 0, rollRate = 0, yawRate = 0 }, collectiveThrust = clamp01(rawCmd.collectiveThrust), flapTarget, transitionAlpha, translationBias = { surge = ..., sway = ... } }` (never emit `heave` inside `translationBias`, never copy `targetThrottle`/`targetClimbRate`).
   - Update `apply_stall_guard` to enforce `minStallThrust = clamp01(policy.minStallThrottle)` on `conditionedCmd.collectiveThrust` and nose-down `conditionedCmd.targetQuaternion`.
2. **`src/1_control/vas/modules/flight_dynamics_core.lua`** (`<= 50` lines/function):
   - Remove `compute_climb_wrench` from `flight_dynamics_core.compute()`!
   - Update `compute_attitude_wrench`: support `targetAngularRates` reference (`eRate = refRate - measRate`, computing derivative/rate damping against `refRate` instead of assuming zero angular rate!). When `guidance.commandType == "RATE_COMMAND"`, track `eRate` directly without outer quaternion angle error.
   - Compute open-loop `thrustEffort = math.max(0.0, math.min(15.0, (tonumber(guidance.collectiveThrust) or 0.0) * (state.thrustScale or 15.0)))`; map `alpha = guidance.transitionAlpha or 0.0`: for pure rotary/VTOL (`alpha == 0`), `heave = thrustEffort`, `surge = bias.surge`; for winged/fixed-wing (`alpha > 0`), blend forward `surge` (`bias.surge * (1 - alpha) + thrustEffort * alpha`) and `heave = thrustEffort * (1 - alpha)`.
3. **`src/1_control/vas/modules/state_machine.lua`** (`<= 50` lines/function):
   - Isolate emergency vertical hold PI inside `compute_emergency_collective(state, targetVy, measVy)`: returns normalized `collectiveThrust in [0.0, 1.0]` around `hoverBaseNormalized = 0.635` (or derived from `(hoverBaseThrottle or 9.525) / 15.0`) for `FAILSAFE_HOLD` (`0.0 m/s`), `EMERGENCY_LAND` (`-1.5 m/s`), and `AIRBORNE_EMERGENCY` (`-1.0 m/s`).
   - Emit pure `QUATERNION_RATE` command tables (`targetQuaternion = quat.from_euler(0, 0, yaw)`, `targetAngularRates = { pitchRate = 0, rollRate = 0, yawRate = 0 }`, `collectiveThrust`, `flapTarget`, `translationBias = { surge = 0, sway = 0 }`).
   - Update `arbitrate_c2`: require `cmd.authKey == "ESTOP_CONFIRM_KEY"` for `E_STOP` (`action == "E_STOP"` or `emergencyAction == "E_STOP"`), handle `MFD_DIRECT`/`MFD_ACRO`/`acroActive == true` (`state.activeSource = "MFD_ACRO"`), else `FCP`.

- [ ] **Step 4: Run VAS unit tests & syntax check**

Run:
```powershell
python tools/run_unit_tests.py --target 1_control/vas --clean-orphans; if ($?) { python tools/validate_lua_syntax.py }
```
Expected: All `1_control/vas` tests PASS, 0 syntax errors.

- [ ] **Step 5: Commit Task 9**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/1_control/vas/modules/vehicle_policy.lua src/1_control/vas/modules/flight_dynamics_core.lua src/1_control/vas/modules/state_machine.lua tests/1_control/vas/test_vas_quaternion_rate.lua tests/1_control/vas/test_vas_core.lua tests/1_control/vas/test_vas_advanced_vtol.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "refactor(vas): enforce Zero-Fallback QUATERNION_RATE and remove normal-flight vertical PI (TASK-209)"
```

---

### Task 10: VAS `system.json` Defaults (`manifest.lua`), `[I-10]` `MSG_AERO_*`, `Base+3` ACRO HUD & Identifier Cleanup

**Files:**
- Modify: `src/0_development/installer/modules/manifest.lua` (`vas` `version = "1.19.0"`, `defaultConfigs["/config/system.json"]`)
- Modify: `src/1_control/vas/modules/network_manager.lua`
- Modify: `src/1_control/vas/modules/telemetry_feeder.lua`
- Modify: `src/1_control/vas/modules/core_daemon.lua`
- Modify: `src/1_control/vas/modules/actuator_adapter_asa.lua`
- Modify: `src/1_control/vas/main.lua`
- Modify: `tests/1_control/vas/test_vas_core.lua`

**Interfaces:**
- Consumes:
  - `manifest.lua` `defaultConfigs["/config/system.json"]` (`channels: { trajectory = 4, actuation = 10, asaActuation = 11 }`, `timeouts.fcpCommandTimeoutMs = 1500`, `stallGuard.flapVfeLimit = 15.0`)
- Produces:
  - `network_manager.ZONE_OFFSETS` (`trajectory = 4`, `actuation = 10`, `aero = 11`, `asaActuation = 11`), `broadcast_discovery` sending BOTH `MSG_ACTUATOR_DISCOVER_REQ` on `Base+10` and `MSG_SURFACE_DISCOVER_REQ` on `Base+11` (when aero or universal), handling `MSG_SURFACE_DISCOVER_ACK`, `MSG_AERO_STATUS`, rejecting stale `MSG_ATTITUDE_CMD` missing `QUATERNION_RATE`/`RATE_COMMAND`.
  - `telemetry_feeder`: `Base+3` emits VAS §8.7 `CORE_ACRO_TAKEOVER` payload (`source = "CORE_ACRO_TAKEOVER"`, `fsmState`, `flightMode = "ACRO"`, `acroActive = true`, `attitude`, `angularRates`, `dynamics`, `fuel`, `dynamicLoad`, `sensorHealth`, `actuatorHealth`) at 20Hz during `activeSource == "MFD_ACRO"`, emits failsafe MFD summary at 5Hz (`tickCounter % 4 == 0`), and keeps `Base+3` strictly silent during `FCP`.
  - Normalized identifiers (`satAsa`, `satTca`, `fcpCmd`) across `core_daemon.lua`, `actuator_adapter_asa.lua`, and `network_manager.lua`.

- [ ] **Step 1: Write/extend failing unit tests in `tests/1_control/vas/test_vas_core.lua`**

Add assertions verifying:
1. `telemetry_feeder` `Base+3` payload during `activeSource == "MFD_ACRO"` carries `source == "CORE_ACRO_TAKEOVER"`, `flightMode == "ACRO"`, `acroActive == true`, nested `attitude`, `angularRates`, `dynamics`, `actuatorHealth`.
2. `network_manager` supports `asaActuation = 11`, dispatches `MSG_SURFACE_DISCOVER_ACK` on `Base+11` (`adapterAsa:register_surface_node`), sends `MSG_SURFACE_DISCOVER_REQ` on `Base+11` for aerodynamic airframes, and keeps `MUT-01` (`ERR_DOMAIN_MISMATCH`) & `MUT-07` (`MSG_EMERGENCY_OVERRIDE`) intact.
3. `core_daemon` uses normalized `satAsa`/`satTca`/`fcpCmd` and reads `stallGuard.flapVfeLimit = 15.0` cleanly.
4. `vas/main.lua` does NOT force `state.fsm.currentState = "NORMAL"` unconditionally outside `_G.harness_set_state` mocks (safe boot in `DISARMED`/`IDLE_ARMED`).

- [ ] **Step 2: Run VAS tests to verify failure**

Run:
```powershell
python tools/run_unit_tests.py --target 1_control/vas --clean-orphans
```
Expected: FAIL on new `CORE_ACRO_TAKEOVER` payload / `[I-10]` discovery / safe boot state assertions.

- [ ] **Step 3: Apply VAS network, telemetry feeder, daemon, `main.lua` & `manifest.lua` updates**

1. **`src/0_development/installer/modules/manifest.lua`**: Set `vas.version = "1.19.0"` and update `vas.defaultConfigs["/config/system.json"]` to include explicit `channels = { c2 = 0, guidance = 1, telemetry = 2, mfd = 3, trajectory = 4, clientReply = 5, actuation = 10, asaActuation = 11 }`, `timeouts = { fcpCommandTimeoutMs = 1500, sensorLossDebounceTicks = 1, calibrationTimeoutSec = 120 }`, `stallGuard = { flapVfeLimit = 15.0 }`, `debug = false`.
2. **`src/1_control/vas/modules/telemetry_feeder.lua`**: Update `build_mfd_payload` to emit VAS §8.7 `CORE_ACRO_TAKEOVER` schema (keeping `fsmState`, `attitude`, `angularRates`, `dynamics`, `fuel`, `dynamicLoad`, `sensorHealth`, `actuatorHealth`, `source = isAcro and "CORE_ACRO_TAKEOVER" or "CORE_FAILSAFE"`, `flightMode = isAcro and "ACRO" or fsmState.currentState`, `acroActive = isAcro`). Keep `Base+2` `MSG_FLIGHT_TELEMETRY` carrying `activeSource`, `actuatorHealth`, `controlState`, `dynamics.altitudeY`, `dynamics.velocity`.
3. **`src/1_control/vas/modules/network_manager.lua`**, **`actuator_adapter_asa.lua`**, **`core_daemon.lua`**:
   - Support `subchannels.asaActuation` alias mapped to `channels.aero` (`Base+11`), preserve `navSensor` alias (`Base+4`) ONLY if `trajectory` unset? No — Zero-Fallback: replace `navSensor` with `trajectory = 4` (update `test_vas_core.lua:207` `assert_eq(net.channels.trajectory, 10004)`!).
   - In `broadcast_discovery(state)`: send `MSG_ACTUATOR_DISCOVER_REQ` on `Base+10` and `MSG_SURFACE_DISCOVER_REQ` on `Base+11` (for aerodynamic airframes or unconditionally when `channels.aero` exists); handle `MSG_SURFACE_DISCOVER_ACK` via `state.adapterAsa.register_surface_node` (add `register_surface_node` on `actuator_adapter_asa.lua`).
   - Normalize `fcpCmd`, `satTca`, `satAsa` local identifiers across `core_daemon.lua`.
4. **`src/1_control/vas/main.lua`**: Replace unconditional `state.fsm.currentState = "NORMAL"` with `if _G.harness_set_state then state.fsm.currentState = "NORMAL" end`.

- [ ] **Step 4: Run VAS tests, installer tests, manifest sync, `MUT-01`/`MUT-06`/`MUT-07`, and syntax check (Phase 3 Gate)**

Run:
```powershell
python tools/run_unit_tests.py --target 1_control/vas --clean-orphans; if ($?) { python tools/run_unit_tests.py --target 0_development/installer --clean-orphans }; if ($?) { python tools/validate_lua_syntax.py }; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python tools/run_mutation_tests.py --id MUT-01 }; if ($?) { python tools/run_mutation_tests.py --id MUT-06 }; if ($?) { python tools/run_mutation_tests.py --id MUT-07 }
```
Expected: All PASS, `0 Errors, 0 Warnings`, `MUT-01`/`MUT-06`/`MUT-07` all KILLED.

- [ ] **Step 5: Commit Task 10 (Phase 3 Complete)**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/installer/modules/manifest.lua src/1_control/vas tests/1_control/vas
& "C:\Program Files\Git\cmd\git.exe" commit -m "refactor(vas): align system.json defaults, [I-10] discovery, CORE_ACRO_TAKEOVER HUD, and identifiers (TASK-209)"
```

---

## Phase 4: 3-Node Closed-Loop E2E Integration, Full Verification & Spec/Context Promotion

### Task 11: E2E Migration to `AMM -> Base+4 -> FCP -> Base+1 (QUATERNION_RATE) -> VAS -> Base+10/11` & Scenario 8

**Files:**
- Modify: `tests/e2e/test_e2e_bootstrap_and_telemetry.lua`
- Modify: `tests/e2e/test_e2e_waypoint_guidance.lua`
- Modify: `tests/e2e/test_e2e_c2_and_estop.lua`
- Modify: `tests/e2e/test_e2e_facility_landing.lua`
- Modify: `tests/e2e/test_e2e_gps_triangulation.lua`
- Modify: `tests/e2e/test_e2e_advanced_vtol_flight.lua`
- Create: `tests/e2e/test_e2e_3node_se3_closed_loop.lua`

**Interfaces:**
- Consumes:
  - Production sandboxes `src/3_planning/amm`, `src/2_guidance/fcp`, `src/1_control/vas`, `src/1_control/tca`, `src/1_control/asa`, `src/0_infra/{gps,gac,gcs,landing_pad}`, `src/0_development/alignment`
- Produces:
  - Updated E2E scenarios matching ICD `v1.28.0` / Architecture `v2.13.0` (`AMM` owns `CH 50000`, `CH 60001/60002 -> Base+5`, `CH 50003/50201/50211`, `Base+3` MFD; `FCP` bridges `Base+4 <-> Base+1` `QUATERNION_RATE`; `VAS -> ASA` uses `MSG_AERO_CMD` / `MSG_AERO_STATUS`)
  - Scenario 8 (`test_e2e_3node_se3_closed_loop.lua`):
    1. Live `AMM -> FCP -> VAS -> TCA` closed loop across `TAKEOFF -> CRUISE -> LOITER -> POI_HOLD -> LANDING`.
    2. `MFD_ACRO` takeover (`VAS Base+2 activeSource="MFD_ACRO"`, `AMM` yields `Base+3`, `VAS` broadcasts `CORE_ACRO_TAKEOVER` on `Base+3`, `FCP` enters `PASSIVE_TRACKING`) followed by `FCP` release (`ACTIVE_TRACKING` with `2.0s` bumpless ramp and zero surge discontinuity).
    3. 4-layer live `MSG_CHANNEL_REBIND` cascade (`AMM Base+4 -> FCP Base+1 -> VAS Base+10/11 -> TCA -> ACKs up to AMM -> COMMIT`).
    4. 3-tier failsafe cascade (`AMM` `Base+4` drop -> `FCP` `500ms` `AMM_TIMEOUT_HOLD` -> `10s` `EMERGENCY_LAND`; and `FCP` `Base+1` drop -> `VAS` `1500ms` `FAILSAFE_HOLD` -> `EMERGENCY_LAND`).

- [ ] **Step 1: Write Scenario 8 and update Scenarios 1, 2, 3, 5, 6, 7 for the refactored topology**

Key updates per existing E2E file:
- `test_e2e_bootstrap_and_telemetry.lua`: change `channel_sentinel` node from `FCP` to `AMM`; verify `AMM` opens `Base+0..5` and receives `VAS Base+2`, then downlinks `MSG_MFD_STATE` on `Base+3` to `GCS`.
- `test_e2e_waypoint_guidance.lua`: drive real `AMM` (`Base+4`) -> `FCP` (`outer_loop_controller`) -> `Base+1` (`QUATERNION_RATE`) -> `VAS` (`MSG_AERO_CMD` on `Base+11` instead of deprecated `MSG_SURFACE_CMD`/`MSG_SURFACE_STATUS`).
- `test_e2e_c2_and_estop.lua`: include `authKey = "ESTOP_CONFIRM_KEY"` & verify `AMM` + `GCS` `E_STOP` preemption on `Base+1`.
- `test_e2e_facility_landing.lua`: move `facility_client` from `FCP` sandbox to `AMM` sandbox.
- `test_e2e_gps_triangulation.lua`: move `FCP` `nav_engine` client to `AMM` sandbox (`Base+2` `altitudeY` injection -> `CH 60001` -> `10005` reply -> `posEpoch` increment).
- `test_e2e_advanced_vtol_flight.lua`: drive `FCP v2.0.0` `outer_loop_controller` (`QUATERNION_RATE`, `STRICT_LEVEL`, `translationBias {surge, sway}`, `flapTarget = 0.0`) -> `VAS` (`pre_process_guidance` + `flight_dynamics_core` + `actuator_adapter_tca`) -> `TCA`.
- Add `tests/e2e/test_e2e_3node_se3_closed_loop.lua` covering Scenario 8.

- [ ] **Step 2: Run E2E runner to isolate any integration mismatches & fix inline**

Run:
```powershell
python tools/run_e2e_tests.py --clean-orphans
```
Fix any minor wire/schema edge cases exposed between live AMM, FCP, VAS, TCA, GCS, GAC, GPS sandboxes until all 8 scenarios (9/9+ specs) PASS cleanly.

- [ ] **Step 3: Commit Task 11**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tests/e2e
& "C:\Program Files\Git\cmd\git.exe" commit -m "test(e2e): migrate E2E suite to 4-tier [I-12]/QUATERNION_RATE architecture and add 3-node closed-loop Scenario 8 (TASK-207/208/209)"
```

---

### Task 12: Full Regression Verification, Spec Status Promotion (`FCP` & `VAS`), and Context Sync

**Files:**
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (header metadata: `문서 상태 (Status)` -> `Implemented`, `최종 수정일` -> completion date)
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (header metadata: `문서 상태 (Status)` -> `Implemented`, `최종 수정일` -> completion date)
- Keep `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` at `Approved` (with Revision/note that `TASK-207` is implemented and `TASK-202-5` web editor remains before `AMM` promotion to `Implemented`).
- Modify: `tools/verify_spec_status.py` (move `FCP` and `VAS` to `TARGET_IMPLEMENTED` -> `9 Implemented, 6 Approved`)
- Modify: `TASK.md` (mark `TASK-207`, `TASK-208`, `TASK-209` `[x]`, move to `## 3. 완료된 작업 이력` respecting the 10-entry prune cap!)
- Modify: `GEMINI.md` (update Phase 1 & 2 handover snapshot `<= 80` lines)
- Modify: `.agent/memory/workspace-root.md` (append `TASK-207`, `TASK-208`, `TASK-209` completion entries per `verify_context_docs.py` R8)

- [ ] **Step 1: Promote `FCP` and `VAS` specifications to `Implemented` and update `tools/verify_spec_status.py`**

Per `.agent/rules/skill-workflows.md` (completion exception without Mixed-Scope interruption): update `문서 상태 (Status)` to `` `Implemented` `` and `최종 수정일` in `FCP_PROGRAM_SPECIFICATION.md` and `VAS_PROGRAM_SPECIFICATION.md`, move those two paths from `TARGET_APPROVED` to `TARGET_IMPLEMENTED` in `tools/verify_spec_status.py` (`9 Implemented, 6 Approved`).

- [ ] **Step 2: Run ALL full verification suites cleanly (zero shortcuts)**

Run sequentially:
```powershell
python tools/run_unit_tests.py --require-tests --clean-orphans; if ($?) { python tools/run_e2e_tests.py --clean-orphans }; if ($?) { python tools/run_mutation_tests.py }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }; if ($?) { python tools/verify_all_specs.py --check-readmes }; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/validate_lua_syntax.py }; if ($?) { python tools/verify_manifest_sync.py }
```
Expected:
- `run_unit_tests.py`: 12/12 targets PASS
- `run_e2e_tests.py`: all scenarios PASS
- `run_mutation_tests.py`: 25/25 KILLED (100.0%, >= 90.0%)
- `tests/harness`: all PASS (`test_mutation_runner`, `test_terminology_guard`, `test_static_guard`, `test_tools_integrity`, etc.)
- `verify_all_specs.py --check-readmes`: `0 Errors, 0 Warnings`
- `verify_spec_status.py`: `9 Implemented, 6 Approved PASS`
- `validate_lua_syntax.py` & `verify_manifest_sync.py`: `0 Errors, 0 Warnings`

- [ ] **Step 3: Sync `TASK.md`, `GEMINI.md`, and `.agent/memory/workspace-root.md`, then verify context docs**

Update `TASK.md` (pruning `## 3` archive to max 10 items), `GEMINI.md` (`<= 80` lines), and `.agent/memory/workspace-root.md` with exact verified counts/hashes from Step 2, then run:
```powershell
python tools/verify_context_docs.py
```
Expected: `0 findings` (Exit code 0).

- [ ] **Step 4: Final Commit & Readiness Check**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md tools/verify_spec_status.py TASK.md GEMINI.md .agent/memory/workspace-root.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "chore(docs): promote FCP v2.0.0 and VAS v1.19.0 specs and sync context after TASK-207/208/209"
```

---

## Self-Review Check (Inline Verification)
1. **Spec Coverage**:
   - `AMM v1.3.0`: dual modem (`top`+`back` w/ fallback), `20Hz`/`5Hz` dual coroutines + `headless` bypass, `channel_sentinel` (`CH 50000`, `200ms` probe, 4-layer rebind), `nav_engine` (`TASK-122` GPS+DR $\alpha=0.35$, `degradedAlpha=0.10`, `5000ms` timeout, `posEpoch`), `facility_client` (Beacon/Runway/ATC/GAC/Pad/Docking, 2nd-order Taylor $\le 0.5\text{ s}$, `300ms` watchdog, `15s x 10` ATC retry), `trajectory_generator` (11 modes, `LOITER` ffAccel, `POI_HOLD` $\le 30^\circ/\text{s}$, `-0.8` docking abort, ILS, 2-stage touchdown, `-2.0` emergency), `[I-12]` `Base+4`, `Base+3` 5Hz downlink w/ `MFD_ACRO` yield, `E_STOP` `authKey`. All mapped in Phase 1 (Tasks 1–4).
   - `FCP v2.0.0`: single `top` modem 3 channels (`Base+4/+2/+1`), `state_propagator` (`dt <= 0.1s`, `posMergeMaxStepM = 2.0`, `500ms` navStale), 6-state `flight_fsm` (`BOOT`, `IDLE_ARMED`, `ACTIVE_TRACKING`, `PASSIVE_TRACKING` 2.0s ramp, `AMM_TIMEOUT_HOLD` `500ms -> 10s -> EMERGENCY_LAND`), unified `SE(3)` ($g = 11.0\text{ m/s}^2$, conditional anti-windup, 6-airframe `QUATERNION_RATE`, `STRICT_LEVEL`/`TILT_ASSISTED` + sway-loss fallback, `25 deg` multirotor, `[8,18] m/s` winged VTOL, BTT+TECS fixed wing), 14 legacy files removed, `debug: false` headless default. All mapped in Phase 2 (Tasks 5–8).
   - `VAS v1.19.0`: Zero-Fallback `QUATERNION_RATE`/`RATE_COMMAND`, normal-flight `compute_climb_wrench` removed (failsafe vertical PI isolated in `state_machine.lua`), `E_STOP (ESTOP_CONFIRM_KEY) > MFD_ACRO > FCP`, `Base+3` `CORE_ACRO_TAKEOVER` 20Hz HUD & silence guard, `[I-10]` `MSG_AERO_*`/`MSG_SURFACE_DISCOVER_*`, `manifest.lua` `system.json` (`trajectory: 4`, `asaActuation: 11`, `fcpCommandTimeoutMs: 1500`, `flapVfeLimit: 15.0`), `satAsa`/`satTca`/`fcpCmd`. All mapped in Phase 3 (Tasks 9–10).
2. **Placeholder Scan**: Zero `TBD`/`TODO` placeholders; every step specifies exact files, invariants, PowerShell commands, and expected assertions.
3. **Type & Tooling Parity**: `MUT-03`/`04`/`05` and `MUT-14`/`15`/`23` explicitly scheduled with `test_mutation_runner.py` checks; `verify_manifest_sync.py` kept at 0 Errors at every phase boundary; `verify_spec_status.py` aligned at Task 12 (`AMM` stays `Approved` until `TASK-202-5`, `FCP` & `VAS` -> `Implemented`).
4. **Global Constraint Parity**: PowerShell `; if ($?) { ... }` syntax, `& "C:\Program Files\Git\cmd\git.exe"`, Zero-Sleep 20Hz, `<= 50`-line functions, Lua 5.2 Cobalt, VS ban clean.
