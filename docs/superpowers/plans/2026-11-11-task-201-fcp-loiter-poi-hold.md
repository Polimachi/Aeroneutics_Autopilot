# FCP Outer-Loop Guidance Primitives (`LOITER` & `POI_HOLD`) Expansion (TASK-201) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the Flight Control Program (`src/2_guidance/fcp/`) with configurable circular orbit (`LOITER` radius/direction/speed) and Point-of-Interest hover/aiming (`POI_HOLD`) outer-loop guidance primitives, 3-mode yaw heading control (`AUTO`/`FACE_PATH`, `FIXED`, `POI`/`TARGET_LOCK`), and bumpless C2 mode-transition interlocks across `VECTORED_VTOL` and `ADVANCED_VTOL` airframes.

**Architecture:** `flight_fsm.lua` adds `POI_HOLD` to the active in-flight state set and transitions cleanly among `CRUISE`, `LOITER`, `POI_HOLD`, and `APPROACH_LAND` under C2 commands while preserving all fuel, telemetry, and GPS failsafes. `vectored_vtol_driver.lua` and `advanced_vtol_driver.lua` share a unified horizontal error resolver (point-to-point error in `CRUISE`/`POI_HOLD` vs radial-error + CW/CCW tangent velocity vector in `LOITER`) and a 3-mode yaw heading computer (`AUTO`, `FIXED`, `POI`) rate-limited at $30.0^\circ/\text{s}$ (`maxYawRateDegPerSec`). `operator_handler.lua`, `guidance_controller.lua`, and `fcp_runtime.lua` normalize incoming `Base+0` `MSG_OPERATOR_CMD` parameters (`loiterRadius`, `loiterDirection`, `poiTarget`, `headingMode`, `fixedHeading`), update `ctx.mission_target`, reset PID accumulators without losing gimbal/heading continuity, and apply a 2.0-second (`bumplessRampSec`) linear bumpless ramp across mode switches.

**Tech Stack:** CC:Tweaked 1.109+ Lua 5.2 (Cobalt VM), CraftOS-PC Headless Unit Test Runner (`tools/run_unit_tests.py`), Multi-Node E2E Simulation Harness (`tools/run_e2e_tests.py`), Mutation Test Runner (`tools/run_mutation_tests.py`), Python 3.10+ Specification & Context Verifiers (`tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/verify_manifest_sync.py`, `tools/verify_context_docs.py`).

**Spec:**
- Primary Specification: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (`v1.15.0 Implemented` $\to$ `v1.16.0 Approved` in Task 1 $\to$ `v1.16.0 Implemented` in Task 4)
- Master ICD: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.26.0 Approved` — Interface I-6 `MSG_OPERATOR_CMD` schema already includes `POI_HOLD`, `loiterRadius`, `loiterDirection`, `poiTarget`, `headingMode`, `fixedHeading`; sync FCP reference badge to `v1.16.0`)
- System Diagram: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.12.0 Approved` — sync FCP reference badge to `v1.16.0`)
- Upstream Consumer Spec: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v1.1.0 Approved` — sync FCP reference badge to `v1.16.0`)
- Roadmap SSOT: `TASK.md` (`TASK-201`)

## Global Constraints

- **Lua 5.2 Cobalt Compatibility (`.agent/rules/cc-tweaked-runtime.md`)**: Zero Lua 5.3+ operators (`//`, `&`, `|`, `~`, `<<`, `>>`), zero `getfenv`/`setfenv`, zero blocking `os.pullEvent` inside the 20Hz control step.
- **Valkyrien Skies Ban (`.agent/rules/domain-aeronautics.md`)**: Zero prohibited mod identifiers (`valkyrien`, `vs2`, `cc_vs`, `ship` peripheral, `kontraption:`).
- **Airframe Scope & Non-Aero Invariant (`FCP_PROGRAM_SPECIFICATION.md` §5.3)**:
  - Active airframes: `VECTORED_VTOL`, `ADVANCED_VTOL`.
  - Deferred airframes (`FIXED_WING`, `WINGED_VTOL`, `QUADROTOR`, `HEXAROTOR`) remain in `guidance_controller.DEFERRED_AIRFRAMES` returning `false, "UNSUPPORTED_AIRFRAME_DEFERRED"`.
  - `flapTarget` must remain strictly `0.0` in all flight modes (including `LOITER` and `POI_HOLD`) for `VECTORED_VTOL` and `ADVANCED_VTOL`.
- **Minecraft / NED Coordinate & Angle Conventions (`FCP_PROGRAM_SPECIFICATION.md` §3.1–3.2)**:
  - North = $-Z_{MC}$ ($\psi = 0.0^\circ$), East = $+X_{MC}$ ($\psi = 90.0^\circ$), South = $+Z_{MC}$ ($\psi = 180.0^\circ$), West = $-X_{MC}$ ($\psi = 270.0^\circ$), Altitude $h = +Y_{MC}$.
  - Bearing from $(x_1, z_1)$ to $(x_2, z_2)$: `math.deg(math.atan2(x2 - x1, -(z2 - z1))) % 360.0`.
  - Clockwise (`"CW"`) orbit at North of center ($x = x_c, z < z_c$) has tangent vector pointing East ($+X_{MC}$, $\psi = 90.0^\circ$); Counter-Clockwise (`"CCW"`) at North of center has tangent vector pointing West ($-X_{MC}$, $\psi = 270.0^\circ$).
- **Mutation Test Target Line Preservation (`tools/run_mutation_tests.py`)**:
  - `MUT-14` (`src/2_guidance/fcp/modules/flight_fsm.lua`): Preserve exact line `if gate.allowed then`.
  - `MUT-15` (`src/2_guidance/fcp/modules/vectored_vtol_driver.lua`): Preserve exact line `local skp, skd = g.surgeKp or 0.15, g.surgeKd or 0.08`.
  - `MUT-23` (`src/2_guidance/fcp/modules/advanced_vtol_driver.lua`): Preserve exact line `local raw_surge = clamp(skp * err_surge - skd * vel_surge + s_i, -1.0, 1.0)`.
- **Zero-Fallback & Spec-First Discipline (`skill-workflows.md`)**: Update `FCP_PROGRAM_SPECIFICATION.md` to `v1.16.0` (`Approved`) in Task 1 before modifying any `src/2_guidance/fcp/` code, and promote to `Implemented` in Task 4 after all verification gates pass.

## Review Focus

1. **Degenerate Zero-Distance Singularity at Orbit Center or POI Target (`d < 0.5m`)**: When the aircraft is directly over the `LOITER` center $(x_c, z_c)$ or directly over `poiTarget` $(x_p, z_p)$, `math.atan2(0, 0)` or division by `d_center == 0` must not produce `NaN` or snap yaw; `resolve_horizontal_error` must default the outward radial unit vector to North `(0.0, -1.0)` when `d_center <= 0.1`, and `compute_heading` must hold `prev_heading` when horizontal distance to target/POI is `< 0.5m` (tested in Task 2 `test_fcp_core.lua`).
2. **Invalid or Out-of-Range `MSG_OPERATOR_CMD` Parameters (`loiterRadius <= 0`, `fixedHeading < 0` or `>= 360`, unknown `loiterDirection`)**: A malformed C2 command sending `loiterRadius = -10`, `loiterDirection = "INVALID"`, or `fixedHeading = -45` must be sanitized by `operator_handler.process_c2` (`loiterRadius = math.max(5.0, tonumber(r) or 30.0)`, `loiterDirection = (dir == "CCW") and "CCW" or "CW"`, `fixedHeading = ((tonumber(h) % 360.0) + 360.0) % 360.0`) rather than inverting orbit geometry or producing out-of-range headings (tested in Task 3 `test_fcp_core.lua`).
3. **Spurious Bumpless Ramp on Initial Boot (`now_ms == 0` or `5000` Without Prior Mode Switch)**: Initializing `rampStartMs = 0` caused any `guidance_controller.compute` call with `now_ms < 2000` to scale `surge`/`sway` down toward `0.0` even when no hold recovery or mode transition occurred; `state.rampStartMs` must initialize to `-10000` (inactive) and only arm when `trigger_bumpless_transition(state, now_ms)` or `FAILSAFE_HOLD` exit occurs (tested in Task 3 `test_fcp_core.lua`).
4. **Strict Level Attitude Enforcement in `LOITER` and `POI_HOLD` Under `TILT_ASSISTED` Config**: Even when `envelopeMode == "TILT_ASSISTED"` and ground speed exceeds `15.0 m/s`, entering `LOITER` or `POI_HOLD` must slew `targetPitch` back to `0.0` and keep `targetRoll == 0.0` (`STRICT_LEVEL`), because pitch tilting is restricted exclusively to `CRUISE` (tested in Task 2 `test_fcp_core.lua` and `test_fcp_advanced_vtol.lua`).
5. **`PILOT_PRIMARY` Authority Protection Against Unforced GCS Mode Changes**: If `operator.authority == "PILOT_PRIMARY"`, a packet on `Base+0` with `authority = "GCS"` (without `GCS_OVERRIDE` or `forceOverride = true`) attempting to switch the aircraft into `LOITER` or `POI_HOLD` must be rejected with `reason = "PILOT_OVERRIDE_ACTIVE"` without mutating `ctx.mission_target` or triggering a mode transition (tested in Task 3 `test_fcp_core.lua`).

---

## File Structure

- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` — Bump to `v1.16.0` (`Approved` in Task 1 $\to$ `Implemented` in Task 4), document `POI_HOLD` state (15 $\to$ 16 outer-loop FSM states), `LOITER` CW/CCW radial+tangential control law, 3-mode yaw heading control (`AUTO`/`FACE_PATH`, `FIXED`, `POI`/`TARGET_LOCK`), `MSG_OPERATOR_CMD` extended parameters, and C2 mode-switch bumpless ramping interlock.
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` — Update FCP specification version reference badge (`v1.15.0` $\to$ `v1.16.0`).
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` — Update FCP specification version reference badge (`v1.13.0` $\to$ `v1.16.0`).
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` — Update FCP specification version reference badge (`v1.15.0` $\to$ `v1.16.0`).
- Modify: `src/2_guidance/fcp/config/fcp_config.json` — Add default `loiterRadialKp`, `orbitRadiusM`, `orbitSpeedMps` under `guidance.vectored_vtol` and `guidance.advanced_vtol`.
- Modify: `src/2_guidance/fcp/modules/flight_fsm.lua` — Add `POI_HOLD` to active in-flight/armed sets and support transitions between `CRUISE`, `LOITER`, `POI_HOLD`, and `APPROACH_LAND`.
- Modify: `src/2_guidance/fcp/modules/vectored_vtol_driver.lua` — Add `resolve_horizontal_error` (`LOITER` CW/CCW radial+tangent vector vs point target) and 3-mode `compute_heading` (`AUTO`/`FACE_PATH`, `FIXED`, `POI`/`TARGET_LOCK`/`ORBIT_POINT`).
- Modify: `src/2_guidance/fcp/modules/advanced_vtol_driver.lua` — Add `resolve_horizontal_error` (`LOITER` CW/CCW radial+tangent vector with 2.0/s gimbal slew limiter) and 3-mode `compute_heading` (`AUTO`/`FACE_PATH`, `FIXED`, `POI`/`TARGET_LOCK`/`ORBIT_POINT`).
- Modify: `src/2_guidance/fcp/modules/guidance_controller.lua` — Initialize `rampStartMs = -10000`, add `trigger_bumpless_transition(state, now_ms)`, detect active flight-mode transitions (`CRUISE` $\leftrightarrow$ `LOITER` $\leftrightarrow$ `POI_HOLD`), and apply bumpless ramping across `CRUISE`, `LOITER`, and `POI_HOLD`.
- Modify: `src/2_guidance/fcp/modules/operator_handler.lua` — Normalize `MSG_OPERATOR_CMD` extended `params` (`loiterRadius`, `loiterDirection`, `poiTarget`, `headingMode`, `fixedHeading`, `targetWaypoint`, `targetAlt`, `targetSpeed`, `designatedFacilityId`) and flag `bumplessTransition` on mode changes.
- Modify: `src/2_guidance/fcp/fcp_runtime.lua` — Wire `operator_handler.process_c2` output into `ctx.mission_target`, `ctx.pendingC2Cmd`, `flight_fsm`, and `guidance_controller.trigger_bumpless_transition`, and compute `navigation.distanceToWp` in `send_mfd_telemetry`.
- Modify: `tests/2_guidance/fcp/test_fcp_core.lua` — Add unit tests for `flight_fsm` `POI_HOLD`/`LOITER` transitions, `vectored_vtol_driver` `LOITER` (CW/CCW, radial convergence, center singularity) & `POI_HOLD` / 3-mode heading, `operator_handler` parameter normalization & authority rejection, `guidance_controller` bumpless transition ramping, and `fcp_runtime` closed-loop C2 dispatch.
- Modify: `tests/2_guidance/fcp/test_fcp_advanced_vtol.lua` — Add unit tests for `advanced_vtol_driver` `LOITER` (CW/CCW with gimbal slew limiting) and `POI_HOLD` (strict level hover + POI yaw tracking + `flapTarget == 0.0`).
- Modify: `tests/e2e/test_e2e_waypoint_guidance.lua` — Extend Scenario 2 E2E test to verify `MSG_OPERATOR_CMD` `LOITER` (`CW`, `loiterRadius = 40.0`) and `POI_HOLD` (`poiTarget`) commands processed through `fcp_runtime.step_tick` onto `Base+1` (`MSG_ATTITUDE_CMD`) and `Base+3` (`MSG_MFD_STATE`).
- Modify: `TASK.md`, `GEMINI.md`, `.agent/memory/workspace-root.md` — Sync task completion checkboxes, test counts, and handover context.

---

### Task 1: Revise FCP Specification to `v1.16.0 Approved` & Sync Cross-References (`TASK-201-1`)

**Files:**
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md:6-37,566-628,812-920,1286-1348,1518-1575`
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md:39`
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md:33`
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md:17`

**Interfaces:**
- Consumes:
  - `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (§Interface I-6 `MSG_OPERATOR_CMD` schema)
  - `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (§4.1 & §6.1 `ORBIT` $\to$ `LOITER` and `POI_HOLD` contract)
- Produces:
  - `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` at `Version: v1.16.0`, `Status: Approved`, `Date: 2026-11-11`
  - Synchronized FCP `v1.16.0` reference badges in `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`, `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`, and `AMM_PROGRAM_SPECIFICATION.md`

- [ ] **Step 1: Update `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` metadata, Revision History, and reference badges**

In `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`:
1. Update the top metadata table to `문서 상태 (Status)`: `` `Approved` ``, `문서 버전 (Version)`: `` `v1.16.0` ``, `최종 수정일 (Date)`: `` `2026-11-11` ``.
2. Update the reference list badges at the top and bottom of the document (`AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` `v1.26.0`, `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` `v2.12.0`, `VAS_PROGRAM_SPECIFICATION.md` `v1.18.0`, `TCA_PROGRAM_SPECIFICATION.md` `v1.11.0`, `ASA_PROGRAM_SPECIFICATION.md` `v1.6.0`, `ALIGNMENT_PROGRAM_SPECIFICATION.md` `v2.6.0`, `GAC_PROGRAM_SPECIFICATION_AND_ICD.md` `v1.4.1`, `GPS_PROGRAM_SPECIFICATION_AND_ICD.md` `v2.2.2`, `LANDING_PAD_SPECIFICATION_AND_ICD.md` `v2.4.2`, `DOCKING_ARM_SPECIFICATION_AND_ICD.md` `v1.11.1`, `RUNWAY_SPECIFICATION_AND_ICD.md` `v1.10.6`, and add `[AMM_PROGRAM_SPECIFICATION.md](../../3_planning/amm/AMM_PROGRAM_SPECIFICATION.md) (조종석 통합 단말 및 미션 시퀀서 v1.1.0)`).
3. Prepend a new row to `### Revision History`:
   ```markdown
   | `v1.16.0` | 2026-11-11 | 외루프 유도 프리미티브(`LOITER` 반경/방향 선회 및 `POI_HOLD` 관심점 지속 조준 호버) 확장, 3종 통합 기수 지향 모드(`AUTO`/`FACE_PATH`, `FIXED`, `POI`/`TARGET_LOCK`) 및 `Base+0` `MSG_OPERATOR_CMD` 확장 파라미터(`loiterRadius`, `loiterDirection`, `poiTarget`, `headingMode`, `fixedHeading`) 수신·범프리스 전환 인터록 명세 반영 (`Implemented` $\to$ `Approved`) | TASK-201 FCP 외루프 유도 프리미티브 확장 및 AMM v1.1.0 연동 |
   ```

- [ ] **Step 2: Document `LOITER`, `POI_HOLD`, 3-mode heading, and bumpless C2 transition in `FCP_PROGRAM_SPECIFICATION.md` (§5.6, §5.7, §7.1–7.3, §7.7, §8.4.1, §9)**

Update the specification sections as follows:
1. **§5.6 (`VECTORED_VTOL`) & §5.7 (`ADVANCED_VTOL`)**:
   - Specify the **`LOITER` Circular Orbit Control Law**:
     - Outward radial unit vector from center $(X_c, Z_c)$ to craft $(X, Z)$: $\vec{u}_{out} = \frac{[X - X_c, \; Z - Z_c]^T}{d_c}$ (defaults to $[0, -1]^T$ when $d_c \le 0.1\text{ m}$).
     - Unit tangent vector for `direction` ($s = +1$ for `"CW"`, $s = -1$ for `"CCW"`): $\vec{u}_{tan} = [-s \cdot u_{out,z}, \; s \cdot u_{out,x}]^T$.
     - Effective horizontal guidance error fed to the 3-axis PID: $\vec{e}_{horiz} = (R_{loiter} - d_c)\vec{u}_{out} + v_{orbit}\vec{u}_{tan}$, where $R_{loiter} = \max(5.0, \text{loiterRadius})$ (default $30.0\text{ m}$) and $v_{orbit} = \max(1.0, \text{targetSpeed})$ (default $8.0\text{ m/s}$).
   - Specify the **`POI_HOLD` Hover & Continuous Aiming Control Law**:
     - Holds 3D position at $(X_{hold}, Y_{hold}, Z_{hold})$ under `STRICT_LEVEL` ($\theta_{cmd} = 0.0^\circ, \phi_{cmd} = 0.0^\circ$, `flapTarget = 0.0`) while locking nose heading $\psi_{cmd}$ onto `poiTarget` $(X_{poi}, Z_{poi})$ with yaw slew-rate limit $\le 30.0^\circ/\text{s}$.
   - Specify the **3-Mode Heading Dispatch (`headingMode`)**:
     - `"AUTO"` / `"FACE_PATH"`: Faces destination waypoint in `CRUISE` ($d \ge 1.5\text{ m}$) or tangent vector $\vec{u}_{tan}$ in `LOITER` (unless `poiTarget` is supplied).
     - `"FIXED"`: Locks heading to `fixedHeading` $\in [0^\circ, 360^\circ)$.
     - `"POI"` / `"TARGET_LOCK"` / `"ORBIT_POINT"` (and mandatory in `POI_HOLD`): Tracks bearing to `poiTarget` $(X_{poi}, Z_{poi})$ when $d_{poi} \ge 0.5\text{ m}$.
2. **§7.1–7.3 (`Outer-Loop FSM`) & §7.7 (`Bumpless Ramping`)**:
   - Add **`POI_HOLD`** (`관심점 조준 정밀 체공`) to the FSM state table, state diagram, and transition matrix (`CRUISE` $\leftrightarrow$ `LOITER` $\leftrightarrow$ `POI_HOLD`, plus transitions to `APPROACH_LAND`, `FAILSAFE_HOLD`, `FAILSAFE_RTH`, `EMERGENCY_LAND`, `PASSIVE_TRACKING`).
   - In §7.7, extend integrator reset (`reset_integrals`) and 2.0-second linear bumpless ramping (`bumplessRampSec = 2.0`) to C2 mode transitions between `CRUISE`, `LOITER`, and `POI_HOLD`.
3. **§8.2.1 (`MSG_ATTITUDE_CMD`) & §8.4.1 (`MSG_OPERATOR_CMD`)**:
   - Include `POI_HOLD` in `flightMode` enum and update the `MSG_OPERATOR_CMD` payload table/example to match `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` v1.26.0 (`command`, `flightMode`, `params.headingMode`, `params.fixedHeading`, `params.poiTarget`, `params.loiterRadius`, `params.loiterDirection`, `params.designatedFacilityId`).

- [ ] **Step 3: Sync FCP `v1.16.0` reference badges in `ICD`, `SYSTEM_DIAGRAM`, and `AMM` specs**

Update the FCP reference version text to `v1.16.0` in:
- `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md:39`
- `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md:33`
- `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md:17`

- [ ] **Step 4: Run `verify_all_specs.py` to verify specification integrity**

Run:
```powershell
python tools/verify_all_specs.py --check-readmes
```
Expected: `SCAN RESULT: ALL 15 SPECS 100% CLEAN (0 Errors, 0 Warnings)` and `README audit complete: 0 error(s)`.

- [ ] **Step 5: Commit Task 1**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(fcp): revise FCP spec to v1.16.0 Approved with LOITER and POI_HOLD primitives (TASK-201-1)"
```

---

### Task 2: Implement `POI_HOLD` FSM State & `LOITER`/`POI_HOLD` Control Loops in Active VTOL Drivers (`TASK-201-2`)

**Files:**
- Modify: `src/2_guidance/fcp/config/fcp_config.json:51-130`
- Modify: `src/2_guidance/fcp/modules/flight_fsm.lua:24-35,117-136,172-190`
- Modify: `src/2_guidance/fcp/modules/vectored_vtol_driver.lua:25-48,101-189`
- Modify: `src/2_guidance/fcp/modules/advanced_vtol_driver.lua:26-49,116-237`
- Test: `tests/2_guidance/fcp/test_fcp_core.lua`
- Test: `tests/2_guidance/fcp/test_fcp_advanced_vtol.lua`

**Interfaces:**
- Consumes:
  - `nav`: `{ pos = { x, y, z }, vel = { x, y, z }, attitude = { pitch, roll, heading }, groundSpeed }`
  - `target`: `{ x, y, z, targetSpeed, headingMode, fixedHeading, poiTarget = { x, y, z }, loiterRadius, loiterDirection }`
  - `fsm_state`: `"TAKEOFF" | "CRUISE" | "LOITER" | "POI_HOLD" | "APPROACH_LAND" | "TOUCHDOWN" | "FAILSAFE_HOLD" | "FAILSAFE_RTH" | "EMERGENCY_LAND"`
- Produces:
  - `flight_fsm.transition_to`, `flight_fsm.evaluate`, `flight_fsm.is_flight_active`, `flight_fsm.is_armed` supporting `"POI_HOLD"`
  - `vectored_vtol_driver.resolve_horizontal_error(pos, target, fsm_state, g, cfg) -> err_x, err_z, tangent_heading`
  - `vectored_vtol_driver.compute_heading(cfg, nav, target, dt, prev_heading, fsm_state, tangent_heading) -> heading_deg`
  - `advanced_vtol_driver.resolve_horizontal_error(pos, target, fsm_state, g, cfg) -> err_x, err_z, tangent_heading`
  - `advanced_vtol_driver.compute_heading(cfg, nav, target, dt, prev_heading, fsm_state, tangent_heading) -> heading_deg`

- [ ] **Step 1: Write the failing unit tests in `tests/2_guidance/fcp/test_fcp_core.lua` and `tests/2_guidance/fcp/test_fcp_advanced_vtol.lua`**

Append to `tests/2_guidance/fcp/test_fcp_core.lua`:
```lua
describe("flight_fsm POI_HOLD and LOITER mode transitions", function()
    it("transitions cleanly among CRUISE, LOITER, POI_HOLD, and APPROACH_LAND while keeping inFlight active", function()
        local fsm = flight_fsm.init({ system = { airframeType = "VECTORED_VTOL" } })
        flight_fsm.transition_to(fsm, "CRUISE")
        assert_true(flight_fsm.is_flight_active(fsm))
        assert_true(flight_fsm.is_armed(fsm))

        flight_fsm.evaluate(fsm, { cmd = "POI_HOLD" }, 1000)
        assert_eq(fsm.current_state, "POI_HOLD")
        assert_true( fsm.inFlight )
        assert_true(flight_fsm.is_flight_active(fsm))
        assert_true(flight_fsm.is_armed(fsm))

        flight_fsm.evaluate(fsm, { cmd = "LOITER" }, 1050)
        assert_eq(fsm.current_state, "LOITER")

        flight_fsm.evaluate(fsm, { cmd = "POI_HOLD" }, 1100)
        assert_eq(fsm.current_state, "POI_HOLD")

        flight_fsm.evaluate(fsm, { cmd = "CRUISE" }, 1150)
        assert_eq(fsm.current_state, "CRUISE")

        flight_fsm.transition_to(fsm, "POI_HOLD")
        flight_fsm.evaluate(fsm, { atcStatus = "CLEARED" }, 1200)
        assert_eq(fsm.current_state, "APPROACH_LAND")
    end)
end)

describe("vectored_vtol_driver LOITER CW/CCW orbit and POI_HOLD aiming primitives", function()
    local vectored_vtol_driver = require("vectored_vtol_driver")
    local main = require("main")

    it("drives tangential East (+X) velocity in CW LOITER and West (-X) velocity in CCW LOITER when North of center", function()
        local cfg = main.load_config()
        cfg.guidance.vectored_vtol.envelopeMode = "TILT_ASSISTED"
        -- Craft is at (0, 100, -30), which is exactly 30m North of center (0, 100, 0), facing North (heading = 0)
        local nav = {
            pos = { x = 0.0, y = 100.0, z = -30.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 18.0,
        }
        local target_cw = {
            x = 0.0, y = 100.0, z = 0.0,
            loiterRadius = 30.0,
            loiterDirection = "CW",
            targetSpeed = 8.0,
            headingMode = "AUTO",
        }
        local ds_cw = { prev_heading = 0.0, current_pitch = 0.0 }
        local out_cw = vectored_vtol_driver.compute(cfg, nav, target_cw, "LOITER", 0.05, ds_cw)
        -- Facing North (0 deg), Eastward (+X) tangent demand projects to positive sway (+right)
        assert_true(out_cw.sway > 0.0, "CW loiter at North of center must command positive sway (East), got " .. tostring(out_cw.sway))
        assert_eq(out_cw.targetPitch, 0.0, "LOITER must enforce STRICT_LEVEL pitch 0.0 even when TILT_ASSISTED is configured")
        assert_eq(out_cw.targetRoll, 0.0, "LOITER must enforce STRICT_LEVEL roll 0.0")
        assert_true(out_cw.targetHeading > 0.0 and out_cw.targetHeading <= 1.51, "Heading must slew toward 90 deg East tangent")

        local target_ccw = {
            x = 0.0, y = 100.0, z = 0.0,
            loiterRadius = 30.0,
            loiterDirection = "CCW",
            targetSpeed = 8.0,
            headingMode = "AUTO",
        }
        local ds_ccw = { prev_heading = 0.0, current_pitch = 0.0 }
        local out_ccw = vectored_vtol_driver.compute(cfg, nav, target_ccw, "LOITER", 0.05, ds_ccw)
        -- Facing North (0 deg), Westward (-X) tangent demand projects to negative sway (-left)
        assert_true(out_ccw.sway < 0.0, "CCW loiter at North of center must command negative sway (West), got " .. tostring(out_ccw.sway))
        assert_true(out_ccw.targetHeading >= 358.49 and out_ccw.targetHeading < 360.0, "Heading must slew toward 270 deg West tangent")
    end)

    it("pulls craft inward when outside loiterRadius and handles zero-distance center singularity", function()
        local cfg = main.load_config()
        -- Craft is 50m North of center (0, 100, -50), facing North (0 deg); loiterRadius = 30m -> r_err = -20m (Southward / backward)
        local nav = {
            pos = { x = 0.0, y = 100.0, z = -50.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local target = { x = 0.0, y = 100.0, z = 0.0, loiterRadius = 30.0, loiterDirection = "CW", targetSpeed = 8.0 }
        local out = vectored_vtol_driver.compute(cfg, nav, target, "LOITER", 0.05, {})
        assert_true(out.surge < 0.0, "Outside orbit radius while facing North (away from center) must command negative surge toward center")

        -- Singularity check: craft exactly at center (0, 100, 0)
        nav.pos = { x = 0.0, y = 100.0, z = 0.0 }
        local out_center = vectored_vtol_driver.compute(cfg, nav, target, "LOITER", 0.05, { prev_heading = 45.0 })
        assert_true(out_center.surge == out_center.surge and out_center.sway == out_center.sway, "Must not produce NaN at d_center == 0")
        assert_true(out_center.targetHeading == out_center.targetHeading, "targetHeading must not be NaN at d_center == 0")
    end)

    it("holds position and slews heading toward poiTarget in POI_HOLD and FIXED heading modes", function()
        local cfg = main.load_config()
        local nav = {
            pos = { x = 10.0, y = 100.0, z = 10.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        -- Hold at (10, 100, 10), aim at POI (110, 64, 10) which is due East (+X -> 90 deg)
        local poi_target = {
            x = 10.0, y = 100.0, z = 10.0,
            poiTarget = { x = 110.0, y = 64.0, z = 10.0 },
        }
        local ds = { prev_heading = 0.0 }
        local out_poi = vectored_vtol_driver.compute(cfg, nav, poi_target, "POI_HOLD", 0.05, ds)
        assert_eq(out_poi.surge, 0.0, "Zero position error in POI_HOLD must yield 0.0 surge")
        assert_eq(out_poi.sway, 0.0, "Zero position error in POI_HOLD must yield 0.0 sway")
        assert_eq(out_poi.targetPitch, 0.0, "POI_HOLD must maintain 0.0 pitch")
        assert_eq(out_poi.targetRoll, 0.0, "POI_HOLD must maintain 0.0 roll")
        -- 30 deg/s * 0.05s = 1.5 deg step toward 90 deg
        assert_true(math.abs(out_poi.targetHeading - 1.5) < 0.01, "Heading must slew by +1.5 deg toward East POI")

        -- FIXED heading mode in CRUISE aiming at 270 deg
        local fixed_target = {
            x = 10.0, y = 100.0, z = -50.0,
            headingMode = "FIXED",
            fixedHeading = 270.0,
        }
        local out_fixed = vectored_vtol_driver.compute(cfg, nav, fixed_target, "CRUISE", 0.05, { prev_heading = 0.0 })
        assert_true(math.abs(out_fixed.targetHeading - 358.5) < 0.01, "FIXED 270 deg from 0 deg must slew -1.5 deg to 358.5 deg")
    end)
end)
```

Append to `tests/2_guidance/fcp/test_fcp_advanced_vtol.lua`:
```lua
describe("advanced_vtol_driver LOITER and POI_HOLD primitives with gimbal slew limiting", function()
    local advanced_vtol_driver = require("advanced_vtol_driver")
    local main = require("main")

    it("executes CW and CCW LOITER with 2.0/s gimbal slew rate limiting and STRICT_LEVEL attitude", function()
        local cfg = main.load_config()
        cfg.guidance.advanced_vtol.envelopeMode = "TILT_ASSISTED"
        local nav = {
            pos = { x = 0.0, y = 100.0, z = -30.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 20.0,
        }
        local target_cw = {
            x = 0.0, y = 100.0, z = 0.0,
            loiterRadius = 30.0,
            loiterDirection = "CW",
            targetSpeed = 10.0,
            poiTarget = { x = 0.0, y = 64.0, z = 0.0 },
            headingMode = "POI",
        }
        local ds = { prev_surge = 0.0, prev_sway = 0.0, prev_heading = 0.0 }
        local out = advanced_vtol_driver.compute(cfg, nav, target_cw, "LOITER", 0.05, ds)
        assert_true(out.sway > 0.0 and out.sway <= 0.1001, "Gimbal slew limiter must cap sway step to <= 0.10 per tick")
        assert_eq(out.targetPitch, 0.0, "LOITER must enforce STRICT_LEVEL pitch 0.0")
        assert_eq(out.targetRoll, 0.0, "LOITER must enforce STRICT_LEVEL roll 0.0")
        assert_eq(out.flapTarget, 0.0, "flapTarget must remain 0.0")
    end)

    it("holds 3D hover and aims at poiTarget in POI_HOLD mode", function()
        local cfg = main.load_config()
        local nav = {
            pos = { x = 0.0, y = 100.0, z = 0.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 90.0 },
            groundSpeed = 0.0,
        }
        -- Hold at (0, 100, 0), aim South (+Z -> 180 deg)
        local target = {
            x = 0.0, y = 100.0, z = 0.0,
            poiTarget = { x = 0.0, y = 64.0, z = 50.0 },
        }
        local ds = { prev_surge = 0.0, prev_sway = 0.0, prev_heading = 90.0 }
        local out = advanced_vtol_driver.compute(cfg, nav, target, "POI_HOLD", 0.05, ds)
        assert_eq(out.surge, 0.0)
        assert_eq(out.sway, 0.0)
        assert_eq(out.targetPitch, 0.0)
        assert_eq(out.targetRoll, 0.0)
        assert_eq(out.flapTarget, 0.0)
        assert_true(math.abs(out.targetHeading - 91.5) < 0.01, "Heading must slew from 90.0 toward 180.0 by +1.5 deg")
    end)
end)
```

- [ ] **Step 2: Run the FCP unit tests to confirm they fail**

Run:
```powershell
python tools/run_unit_tests.py --target 2_guidance/fcp --clean-orphans
```
Expected: FAIL on `POI_HOLD` transition and `LOITER`/`POI_HOLD` driver assertions.

- [ ] **Step 3: Implement `POI_HOLD` in `flight_fsm.lua` and `LOITER`/`POI_HOLD` + 3-mode heading in `vectored_vtol_driver.lua`, `advanced_vtol_driver.lua`, and `fcp_config.json`**

1. **`src/2_guidance/fcp/config/fcp_config.json`**:
   - Add `"loiterRadialKp": 1.0` to `guidance.vectored_vtol` and `"orbitRadiusM": 25.0`, `"orbitSpeedMps": 8.0`, `"loiterRadialKp": 1.0` to `guidance.advanced_vtol`.
2. **`src/2_guidance/fcp/modules/flight_fsm.lua`**:
   - Add `POI_HOLD = true` to `inflight_set` in `transition_to`, `active_set` in `is_flight_active`, and `armed_set` in `is_armed`.
   - In `flight_fsm.evaluate(state, ctx, now_ms)`:
     - Allow transitions among `CRUISE`, `LOITER`, and `POI_HOLD` when `c.cmd == "CRUISE"`, `c.cmd == "LOITER"`, or `c.cmd == "POI_HOLD"`.
     - Allow `(s == "CRUISE" or s == "LOITER" or s == "POI_HOLD") and (c.atcStatus == "CLEARED" or c.cmd == "LANDING")` $\to$ `APPROACH_LAND`.
   - Keep `if gate.allowed then` untouched (`MUT-14`).
3. **`src/2_guidance/fcp/modules/vectored_vtol_driver.lua` & `src/2_guidance/fcp/modules/advanced_vtol_driver.lua`**:
   - Add `resolve_horizontal_error(pos, target, fsm_state, g, cfg)`:
     ```lua
     function driver.resolve_horizontal_error(pos, target, fsm_state, g, cfg)
         local tgt_x = target and target.x or pos.x
         local tgt_z = target and target.z or pos.z
         if fsm_state ~= "LOITER" then
             return tgt_x - pos.x, tgt_z - pos.z, nil
         end
         local rx, rz = tgt_x - pos.x, tgt_z - pos.z
         local d_center = math.sqrt(rx * rx + rz * rz)
         local ux_out, uz_out = 0.0, -1.0
         if d_center > 0.1 then
             ux_out, uz_out = -rx / d_center, -rz / d_center
         end
         local dir = (target and target.loiterDirection == "CCW") and -1.0 or 1.0
         local tx_unit, tz_unit = -dir * uz_out, dir * ux_out
         local radius = math.max(5.0, tonumber(target and target.loiterRadius) or g.orbitRadiusM or (cfg and cfg.navigation and cfg.navigation.loiterRadiusM) or 30.0)
         local v_orbit = math.max(1.0, tonumber(target and target.targetSpeed) or g.orbitSpeedMps or 8.0)
         local k_rad = g.loiterRadialKp or 1.0
         local r_err = (radius - d_center) * k_rad
         local err_x = ux_out * r_err + tx_unit * v_orbit
         local err_z = uz_out * r_err + tz_unit * v_orbit
         local tan_hdg = (math.deg(math.atan2(tx_unit, -tz_unit)) + 360.0) % 360.0
         return err_x, err_z, tan_hdg
     end
     ```
   - Update `compute_heading(cfg, nav, target, dt, prev_heading, fsm_state, tangent_heading)` to support:
     - `mode == "FIXED"` with `target.fixedHeading`
     - `mode == "POI" or mode == "TARGET_LOCK" or mode == "ORBIT_POINT" or fsm_state == "POI_HOLD"` aiming at `poi = (target and target.poiTarget) or g.targetPoint or target` when `dist >= 0.5`
     - `mode == "AUTO" or mode == "FACE_PATH"`: in `LOITER`, aim at `target.poiTarget` if provided else `tangent_heading`; in other states, aim at `(target.x, target.z)` when `dist >= 1.5`.
   - Call `resolve_horizontal_error` and pass `fsm_state, tan_hdg` to `compute_heading` inside `compute()`, preserving the exact `MUT-15` and `MUT-23` lines.

- [ ] **Step 4: Run the FCP unit tests to verify they pass**

Run:
```powershell
python tools/run_unit_tests.py --target 2_guidance/fcp --clean-orphans
```
Expected: PASS on all `test_fcp_core.lua` and `test_fcp_advanced_vtol.lua` suites.

- [ ] **Step 5: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/2_guidance/fcp/config/fcp_config.json src/2_guidance/fcp/modules/flight_fsm.lua src/2_guidance/fcp/modules/vectored_vtol_driver.lua src/2_guidance/fcp/modules/advanced_vtol_driver.lua tests/2_guidance/fcp/test_fcp_core.lua tests/2_guidance/fcp/test_fcp_advanced_vtol.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(fcp): implement LOITER and POI_HOLD control loops for active VTOL drivers (TASK-201-2)"
```

---

### Task 3: Implement `MSG_OPERATOR_CMD` Parameter Normalization, Bumpless Ramping & Runtime C2 Dispatch (`TASK-201-3`)

**Files:**
- Modify: `src/2_guidance/fcp/modules/operator_handler.lua:4-56`
- Modify: `src/2_guidance/fcp/modules/guidance_controller.lua:24-160`
- Modify: `src/2_guidance/fcp/fcp_runtime.lua:46-174`
- Test: `tests/2_guidance/fcp/test_fcp_core.lua`

**Interfaces:**
- Consumes:
  - `MSG_OPERATOR_CMD` packet on `Base+0` (`payload = { authority, command, flightMode, params, emergencyAction, forceOverride }`)
- Produces:
  - `operator_handler.normalize_params(raw_params, flight_mode) -> table`
  - `operator_handler.process_c2(state, packet, now_ms) -> { accepted, command, flightMode, params, bumplessTransition, action, emergencyAction, reason }`
  - `guidance_controller.trigger_bumpless_transition(state, now_ms)`

- [ ] **Step 1: Write the failing unit tests in `tests/2_guidance/fcp/test_fcp_core.lua`**

Append to `tests/2_guidance/fcp/test_fcp_core.lua`:
```lua
describe("operator_handler MSG_OPERATOR_CMD normalization, authority guard, and bumpless transition", function()
    local operator_handler = require("operator_handler")
    local guidance_controller = require("guidance_controller")
    local fcp_runtime = require("fcp_runtime")
    local main = require("main")

    it("normalizes LOITER and POI_HOLD parameters and sanitizes out-of-range inputs", function()
        local op = operator_handler.init({})
        local pkt_loiter = {
            type = "MSG_OPERATOR_CMD",
            payload = {
                authority = "PILOT_PRIMARY",
                command = "LOITER",
                flightMode = "LOITER",
                params = {
                    targetWaypoint = { x = 200.0, z = -300.0 },
                    targetAlt = 140.0,
                    targetSpeed = 12.0,
                    loiterRadius = -15.0,       -- invalid negative -> clamp to >= 5.0
                    loiterDirection = "INVALID", -- invalid -> default "CW"
                    headingMode = "FIXED",
                    fixedHeading = -45.0,       -- normalize to 315.0
                },
                emergencyAction = "NONE",
            },
        }
        local res = operator_handler.process_c2(op, pkt_loiter, 1000)
        assert_true(res.accepted)
        assert_eq(res.flightMode, "LOITER")
        assert_eq(res.params.loiterRadius, 5.0, "Negative loiterRadius must be clamped to minimum 5.0m")
        assert_eq(res.params.loiterDirection, "CW", "Invalid loiterDirection must default to CW")
        assert_eq(res.params.headingMode, "FIXED")
        assert_eq(res.params.fixedHeading, 315.0, "-45 deg fixedHeading must normalize to 315.0 deg")

        -- Transition from LOITER to POI_HOLD triggers bumplessTransition
        local pkt_poi = {
            type = "MSG_OPERATOR_CMD",
            payload = {
                authority = "PILOT_PRIMARY",
                command = "POI_HOLD",
                flightMode = "POI_HOLD",
                params = {
                    targetWaypoint = { x = 210.0, z = -310.0 },
                    targetAlt = 135.0,
                    poiTarget = { x = 250.0, y = 64.0, z = -350.0 },
                },
            },
        }
        local res_poi = operator_handler.process_c2(op, pkt_poi, 2000)
        assert_true(res_poi.accepted)
        assert_eq(res_poi.flightMode, "POI_HOLD")
        assert_eq(res_poi.params.headingMode, "POI", "POI_HOLD must default headingMode to POI")
        assert_not_nil(res_poi.params.poiTarget)
        assert_eq(res_poi.params.poiTarget.x, 250.0)
        assert_true(res_poi.bumplessTransition, "Switching LOITER -> POI_HOLD must flag bumplessTransition")

        -- Unforced GCS packet while PILOT_PRIMARY is active must be rejected
        local pkt_unforced_gcs = {
            type = "MSG_OPERATOR_CMD",
            payload = {
                authority = "GCS",
                command = "CRUISE",
                flightMode = "CRUISE",
                params = { targetWaypoint = { x = 0.0, z = 0.0 } },
            },
        }
        local res_rej = operator_handler.process_c2(op, pkt_unforced_gcs, 2500)
        assert_false(res_rej.accepted)
        assert_eq(res_rej.reason, "PILOT_OVERRIDE_ACTIVE")
    end)

    it("applies 2.0s bumpless linear ramp on mode transition without zeroing initial boot output", function()
        local cfg = main.load_config()
        local g_state = guidance_controller.init(cfg)
        local nav = {
            pos = { x = 0.0, y = 100.0, z = -30.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local target = { x = 0.0, y = 100.0, z = 0.0, loiterRadius = 30.0, loiterDirection = "CW", targetSpeed = 8.0 }

        -- At now_ms = 500 on fresh boot (no prior mode switch), output must NOT be zeroed by ramp
        local cmd_boot, _ = guidance_controller.compute(g_state, nav, target, { state = "CRUISE", flightActive = true, now_ms = 500 }, 0.05)
        assert_true(math.abs(cmd_boot.surge) > 0.1, "Fresh boot at now_ms=500 must not be attenuated by un-triggered ramp")

        -- Switching CRUISE -> LOITER at now_ms = 1000 triggers bumpless ramp (elapsed = 500ms at now_ms = 1500 -> lambda = 0.25)
        guidance_controller.trigger_bumpless_transition(g_state, 1000)
        local cmd_mid, _ = guidance_controller.compute(g_state, nav, target, { state = "LOITER", flightActive = true, now_ms = 1500 }, 0.05)
        local cmd_full, _ = guidance_controller.compute(g_state, nav, target, { state = "LOITER", flightActive = true, now_ms = 3500 }, 0.05)
        assert_true(math.abs(cmd_mid.sway) < math.abs(cmd_full.sway), "Bumpless ramp at 500ms elapsed must attenuate sway compared to full 2.5s elapsed")
        assert_eq(cmd_mid.translationBias.sway, cmd_mid.sway, "translationBias.sway must match ramped sway")
    end)

    it("wires Base+0 MSG_OPERATOR_CMD through fcp_runtime.step_tick into FSM, mission_target, and Base+1/Base+3", function()
        local transmitted = {}
        local mock_modem = {
            open = function() end,
            close = function() end,
            isOpen = function() return true end,
            transmit = function(ch, reply_ch, payload)
                table.insert(transmitted, { channel = ch, replyChannel = reply_ch, payload = payload })
            end,
            isWireless = function() return true end,
        }
        local cfg = main.load_config()
        local ctx = fcp_runtime.create_context(cfg, function() return mock_modem end)
        flight_fsm.transition_to(ctx.fsm, "CRUISE")
        ctx.nav.pos = { x = 0.0, y = 100.0, z = -40.0 }
        ctx.nav.coreAlive = true

        local network_manager = require("network_manager")
        network_manager.ingest_modem_event(ctx.net, "top", 10000, 10000, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            senderId = "AMM-03",
            type = "MSG_OPERATOR_CMD",
            seq = 10,
            timestamp = 2000,
            payload = {
                authority = "PILOT_PRIMARY",
                command = "LOITER",
                flightMode = "LOITER",
                params = {
                    targetWaypoint = { x = 0.0, z = 0.0 },
                    targetAlt = 120.0,
                    targetSpeed = 10.0,
                    loiterRadius = 40.0,
                    loiterDirection = "CCW",
                },
                emergencyAction = "NONE",
            },
        }, 1, 2000)

        -- Advance 4 ticks so both Base+1 MSG_ATTITUDE_CMD and Base+3 MSG_MFD_STATE are emitted
        for i = 1, 4 do
            fcp_runtime.step_tick(ctx, 0.05, 2000 + i * 50)
        end

        assert_eq(ctx.fsm.current_state, "LOITER")
        assert_eq(ctx.mission_target.y, 120.0)
        assert_eq(ctx.mission_target.loiterRadius, 40.0)
        assert_eq(ctx.mission_target.loiterDirection, "CCW")

        local att_tx, mfd_tx = nil, nil
        for _, tx in ipairs(transmitted) do
            if tx.channel == 10001 and tx.payload.type == "MSG_ATTITUDE_CMD" then att_tx = tx end
            if tx.channel == 10003 and tx.payload.type == "MSG_MFD_STATE" then mfd_tx = tx end
        end
        assert_not_nil(att_tx, "MSG_ATTITUDE_CMD must be transmitted on Base+1")
        assert_eq(att_tx.payload.payload.flightMode, "LOITER")
        assert_not_nil(mfd_tx, "MSG_MFD_STATE must be transmitted on Base+3")
        assert_eq(mfd_tx.payload.payload.fsmState, "LOITER")
        assert_eq(mfd_tx.payload.payload.navigation.distanceToWp, 40.0)
    end)
end)
```

- [ ] **Step 2: Run the FCP unit tests to verify the new tests fail**

Run:
```powershell
python tools/run_unit_tests.py --target 2_guidance/fcp --clean-orphans
```
Expected: FAIL on `operator_handler` normalization, `guidance_controller.trigger_bumpless_transition`, and `fcp_runtime` C2 dispatch.

- [ ] **Step 3: Implement C2 normalization in `operator_handler.lua`, bumpless transition in `guidance_controller.lua`, and C2 wiring in `fcp_runtime.lua`**

1. **`src/2_guidance/fcp/modules/operator_handler.lua`**:
   - Add `lastFlightMode = nil` in `operator_handler.init(config)`.
   - Implement `operator_handler.normalize_params(raw_params, flight_mode)`:
     - Sanitize `loiterRadius = math.max(5.0, tonumber(p.loiterRadius) or 30.0)`.
     - Sanitize `loiterDirection = (p.loiterDirection == "CCW") and "CCW" or "CW"`.
     - Sanitize `headingMode`: default to `"POI"` when `flight_mode == "POI_HOLD"` and `p.headingMode == nil`; validate against `AUTO`, `FIXED`, `POI`, `FACE_PATH`, `TARGET_LOCK`, `ORBIT_POINT` (default `"AUTO"`).
     - Sanitize `fixedHeading`: if `p.fixedHeading ~= nil` and `tonumber(p.fixedHeading)` then `((tonumber(p.fixedHeading) % 360.0) + 360.0) % 360.0`.
     - Preserve `targetWaypoint`, `targetAlt`, `targetSpeed`, `designatedFacilityId`, `poiTarget`.
   - In `operator_handler.process_c2(state, packet, now_ms)`:
     - Resolve `mode = payload.flightMode or payload.command`.
     - Compute `bumpless = (state.lastFlightMode ~= nil and mode ~= nil and state.lastFlightMode ~= mode)` for active flight modes (`CRUISE`, `LOITER`, `POI_HOLD`, `APPROACH_LAND`, `LANDING`).
     - Update `state.lastFlightMode = mode`.
     - Return `{ accepted = true, command = payload.command or mode, flightMode = mode, params = normalized_params, bumplessTransition = bumpless }`.
2. **`src/2_guidance/fcp/modules/guidance_controller.lua`**:
   - Initialize `rampStartMs = -10000` and `lastFsmState = nil` in `guidance_controller.init(config)`.
   - Add `guidance_controller.trigger_bumpless_transition(state, now_ms)`:
     - Calls `driver.reset_integrals(state.driver_state)` (preserving `prev_heading`, `prev_surge`, `prev_sway`) and sets `state.rampStartMs = now_ms or 0`.
   - In `apply_ramping(state, raw_cmd, now_ms)`:
     - Scale `raw_cmd.surge` and `raw_cmd.sway` (and `raw_cmd.translationBias.surge`/`sway` if present) by `lambda`.
   - In `guidance_controller.compute(state, nav, mission_target, fsm_ctx, dt)`:
     - Detect mode transitions between `CRUISE`, `LOITER`, and `POI_HOLD` via `state.lastFsmState` (or `fsm_ctx.bumpless == true`) and invoke `guidance_controller.trigger_bumpless_transition(state, now)`.
     - Apply `apply_ramping` when `(now - state.rampStartMs) >= 0 and (now - state.rampStartMs) < (state.bumplessRampSec * 1000.0)` and `fsm_state` is in `{ CRUISE = true, LOITER = true, POI_HOLD = true }`.
3. **`src/2_guidance/fcp/fcp_runtime.lua`**:
   - In `process_inbox(ctx, polled, now_ms)` when `polled.c2` is accepted:
     - Handle `c2_res.action` (`EMERGENCY_LAND` $\to$ `flight_fsm.transition_to(ctx.fsm, "EMERGENCY_LAND", "C2_EMERGENCY_LAND")`, `HOVER_HOLD` $\to$ `flight_fsm.transition_to(ctx.fsm, "FAILSAFE_HOLD", "C2_HOVER_HOLD")`, `RTH` $\to$ `flight_fsm.transition_to(ctx.fsm, "FAILSAFE_RTH", "C2_RTH")`).
     - Store `ctx.pendingC2Cmd = c2_res.flightMode or c2_res.command`.
     - Merge `c2_res.params` into `ctx.mission_target` (`x`, `z` from `targetWaypoint`, `y` from `targetAlt`, `targetSpeed`, `headingMode`, `fixedHeading`, `poiTarget`, `loiterRadius`, `loiterDirection`, `designatedFacilityId`).
     - If `c2_res.bumplessTransition`, call `guidance_controller.trigger_bumpless_transition(ctx.guidance, now_ms)`.
   - Pass `cmd = ctx.pendingC2Cmd` in `build_fsm_context(ctx, nav_summary)` and clear `ctx.pendingC2Cmd = nil` after `flight_fsm.evaluate`.
   - In `send_mfd_telemetry(ctx, nav_summary)`, compute `distanceToWp = math.sqrt(dx * dx + dz * dz)`.

- [ ] **Step 4: Run the FCP unit tests to verify they pass**

Run:
```powershell
python tools/run_unit_tests.py --target 2_guidance/fcp --clean-orphans
```
Expected: PASS on all `2_guidance/fcp` unit tests.

- [ ] **Step 5: Commit Task 3**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/2_guidance/fcp/modules/operator_handler.lua src/2_guidance/fcp/modules/guidance_controller.lua src/2_guidance/fcp/fcp_runtime.lua tests/2_guidance/fcp/test_fcp_core.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(fcp): add MSG_OPERATOR_CMD parameter normalization and bumpless C2 transition interlock (TASK-201-3)"
```

---

### Task 4: E2E Simulation Verification, Full Regression Suite & Specification Promotion (`TASK-201-4`)

**Files:**
- Modify: `tests/e2e/test_e2e_waypoint_guidance.lua:230-250`
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md:8-10,2125-2150`
- Modify: `TASK.md:5,32,64-73,111-125`
- Modify: `GEMINI.md:5-12,42-50`
- Modify: `.agent/memory/workspace-root.md`

**Interfaces:**
- Consumes:
  - `fcp_runtime.create_context`, `fcp_runtime.step_tick`, `network_manager.ingest_modem_event` in `tests/e2e/test_e2e_waypoint_guidance.lua`
- Produces:
  - Multi-node E2E verification of `LOITER` and `POI_HOLD` C2 commands through `FCP` onto `Base+1` and `Base+3`
  - `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` promoted to `Status: Implemented` (`v1.16.0`, `2026-11-11`)
  - Synchronized `TASK.md`, `GEMINI.md`, and `.agent/memory/workspace-root.md` (`0 findings` on `verify_context_docs.py`)

- [ ] **Step 1: Extend `tests/e2e/test_e2e_waypoint_guidance.lua` with `LOITER` and `POI_HOLD` closed-loop assertions**

In `tests/e2e/test_e2e_waypoint_guidance.lua`, after step 8 (`wp1_pkts` verification), add step 9 exercising `fcp_runtime` on the `FCP` sandbox node:
- Feed a `MSG_OPERATOR_CMD` (`flightMode = "LOITER"`, `loiterRadius = 40.0`, `loiterDirection = "CW"`, `targetWaypoint = { x = 100, z = 100 }`, `targetAlt = 150.0`) on `Base+0` (`10000`) into `fcp_runtime.step_tick`, and assert `MSG_ATTITUDE_CMD` (`flightMode == "LOITER"`) is emitted on `Base+1` (`10001`).
- Feed a `MSG_OPERATOR_CMD` (`flightMode = "POI_HOLD"`, `targetWaypoint = { x = 100, z = 100 }`, `targetAlt = 150.0`, `poiTarget = { x = 200, y = 64, z = 100 }`) on `Base+0` (`10000`) into `fcp_runtime.step_tick`, and assert `MSG_ATTITUDE_CMD` (`flightMode == "POI_HOLD"`, `flapTarget == 0.0`) is emitted on `Base+1` (`10001`) and `MSG_MFD_STATE` (`fsmState == "POI_HOLD"`) is emitted on `Base+3` (`10003`).

- [ ] **Step 2: Run the E2E simulation suite to verify it passes**

Run:
```powershell
python tools/run_e2e_tests.py --clean-orphans
```
Expected: `8/8 passed, 0 failed` across 7 E2E scenarios.

- [ ] **Step 3: Promote `FCP_PROGRAM_SPECIFICATION.md` to `Implemented` and run all verification gates**

Update `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` top metadata table:
- `문서 상태 (Status)`: `` `Implemented` ``
- `최종 수정일 (Date)`: `` `2026-11-11` ``

Run the full verification suite:
```powershell
python tools/run_unit_tests.py --require-tests --clean-orphans; if ($?) { python tools/run_e2e_tests.py --clean-orphans }; if ($?) { python tools/run_mutation_tests.py }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python tools/verify_all_specs.py --check-readmes }; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/validate_lua_syntax.py }
```
Expected:
- Unit tests: 12 targets PASS (`0 failed`)
- E2E tests: 7 scenarios `8/8 PASS`
- Mutation tests: `25/25 KILLED (100.0%)`
- Harness tests: `82/82 PASS`
- `verify_manifest_sync.py`: `0 Errors, 0 Warnings`
- `verify_all_specs.py --check-readmes`: `15 specs 0 Errors, 0 Warnings`
- `verify_spec_status.py`: `15 specs (9 Implemented, 6 Approved) PASS`
- `validate_lua_syntax.py`: `126/126 PASS`

- [ ] **Step 4: Sync `TASK.md`, `GEMINI.md`, and `.agent/memory/workspace-root.md` and run `verify_context_docs.py`**

1. Move `TASK-201` (`[x]`) to the top of `## 3. 완료된 작업 이력` in `TASK.md` (pruning the 11th oldest entry to maintain the 10-entry cap) and update the header summary.
2. Update `GEMINI.md` (`직전 완료`, `다음 액션`, and unit test total count in `Standard Commands`, keeping `<= 80` lines).
3. Append a `2026-11-11 — TASK-201` entry to `.agent/memory/workspace-root.md`.
4. Run:
   ```powershell
   python tools/verify_context_docs.py
   ```
   Expected: `[PASS] Context document verification passed (0 findings across R1-R8).`

- [ ] **Step 5: Commit Task 4**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tests/e2e/test_e2e_waypoint_guidance.lua docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md TASK.md GEMINI.md .agent/memory/workspace-root.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(fcp): verify LOITER/POI_HOLD E2E and promote FCP v1.16.0 to Implemented (TASK-201-4)"
```
