# ADVANCED_VTOL Gimbaled Vector Thruster Airframe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the new `ADVANCED_VTOL` airframe type featuring 2D gimbaled `vector_thruster` propulsion across TCA, VAS, FCP, Alignment, and Ground Infrastructure, enabling 6-DoF flight dynamics via pseudo-inverse thrust vector allocation without aerodynamic surfaces.

**Architecture:** 
1. **Actuator Layer (TCA)**: Wraps `vector_thruster` peripherals to accept 2D nozzle deflections (`vec.setVector(x, y)`) and scalar thrust (`vec.setPower(t)`), centering nozzles $(0, 0)$ on watchdog timeout/fail-safe, and reporting nozzle status and gimbal saturation via `MSG_ACTUATOR_STATUS`.
2. **Calibration Layer (Alignment)**: Sequencer executes multi-level throttle and 2D nozzle deflection pulses to construct an empirical Control Effectiveness Matrix $B$ ($6 \times 3N$) and its Moore-Penrose Pseudo-Inverse $B^\dagger = B^T (B B^T)^{-1}$, exported in the aircraft profile.
3. **Core Control Layer (VAS)**: Vehicle policy marks `ADVANCED_VTOL` as non-aerodynamic (`flapTarget = 0.0`, ASA bypassed); thrust mixer computes simultaneous thrust magnitudes and $(x, y)$ gimbal deflections using $B^\dagger$, transmitting clean polymorphic `outputs` in `MSG_THRUST_CMD` and applying directional anti-windup when gimbals saturate.
4. **Guidance Layer (FCP)**: Dedicated `advanced_vtol_driver.lua` outer-loop controller manages 3-axis decoupled horizontal/vertical kinematics, gimbal slew rate limits, and precision 2-stage touchdown without tilting vehicle attitude.
5. **Infrastructure Layer (GAC/GCS/Landing Pad/Installer)**: GAC v1.4.1 dedicated facility matching, Landing Pad approach authorization, and GCS fleet telemetry support `ADVANCED_VTOL`.

**Tech Stack:** CC:Tweaked Lua 5.2, Create Propulsion: Simulated (`vector_thruster`, `liquid_vector_thruster`, `creative_vector_thruster`), CraftOS-PC Unit Test Harness (`harness/unit/engine.py`), Multi-Node Simulation Harness (`harness/simulation/virtual_bus.lua`), Python verification CLI tools.

**Spec:**
- `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (v1.24.0 -> v1.25.0 Approved)
- `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (v2.10.1 -> v2.11.0 Approved)
- `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (v1.10.1 -> v1.11.0 Approved)
- `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (v1.17.0 -> v1.18.0 Approved)
- `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (v1.14.0 -> v1.15.0 Approved)
- `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (v2.5.2 -> v2.6.0 Approved)

## Global Constraints

- **Mod Ban & Allowlist**: Strictly ban all Valkyrien Skies (VS1/VS2) mods, APIs (`peripheral.find("ship")`), and namespaces (`valkyrien:`, `vs_clockwork:`, `kontraption:`). Exclusively allow `Create Propulsion: Simulated`'s `vector_thruster`, `liquid_vector_thruster`, `creative_vector_thruster`.
- **Zero-Tolerance Legacy Terminology (TASK-007)**: Absolutely zero occurrences of legacy abbreviations (`UAP`, `SAS`, `WAP`). Use `FCP`, `ASA`, `TCA`, `VAS` exclusively. Must pass `test_terminology_guard.py` and `verify_all_specs.py` Rule 8.
- **Zero-Fallback & Clean Polymorphism**: In `MSG_THRUST_CMD`, `outputs[groupId]` supports dual clean types: number for fixed thrusters (`outputs[g] = 12`) and table for vector thrusters (`outputs[g] = { thrust = 12, gimbalX = 0.2, gimbalY = -0.1 }`). Zero dual-key legacy fallbacks.
- **RF Spectrum Standard**: Preserve $Base = 10000 + (N-1) \times 40$ 40-channel standard. Zone 2 `Base+10` (`CH_THRUST_ACTUATION`), Zone 1 `Base+1` (`CH_GUIDANCE`), Zone 1 `Base+3` (`CH_TELEMETRY`), Zone 1 `Base+5` (GPS response).
- **20Hz Real-Time Budget**: All allocation math, matrix multiplications, and peripheral calls in VAS and TCA must execute within the 50ms tick budget.
- **Pure Thruster VTOL Rules**: `ADVANCED_VTOL` has zero aerodynamic control surfaces; `flapTarget` is strictly fixed to 0.0, `MSG_AERO_CMD` on `Base+11` is bypassed, and ASA communication is omitted.

## Review Focus

1. **Watchdog Timeout & Safe Fail-State**: When watchdog timer expires (300ms) or E-STOP occurs, TCA must cut thrust to 0 AND reset nozzle gimbals to neutral $(0, 0)$ to prevent physical craft flipping.
2. **Gimbal Saturation Anti-Windup**: When nozzle gimbal limits $[-1.0, 1.0]$ are reached, TCA reports `gimbalSaturated = true` in `MSG_ACTUATOR_STATUS`, and VAS freezes corresponding integral accumulators.
3. **Missing Pseudo-Inverse Fallback**: If an `ADVANCED_VTOL` profile lacks `pseudoInverseMatrix`, VAS gracefully falls back to decoupled linearized scalar mixing with a logged warning, preventing a crash.
4. **Single-Axis Gimbal Failure**: If a vector thruster loses pitch or yaw deflection response, TCA marks `healthStatus = "API_DEGRADED"`, allowing VAS to reallocate load to remaining actuators.
5. **Cold Boot & Neutral Initialization**: During initial peripheral scan in TCA, `vector_thruster` nozzles must be centered to $(0, 0)$ immediately.

---

### Task 0: Worktree Rebase & Baseline Environment Alignment

**Files:**
- Worktree: `.worktrees/task-advanced-vtol` (Branch: `task-advanced-vtol`)

**Interfaces:**
- Consumes: `main` branch HEAD (`f7eb99b` including TASK-007, TASK-111, TASK-114-1).
- Produces: Clean, rebased `task-advanced-vtol` worktree matching current baseline (248 unit tests, 6 E2E scenarios, 20 mutation kills, 33 harness tests).

- [ ] **Step 1: Inspect worktree status and commit divergence**
Run: `& "C:\Program Files\Git\cmd\git.exe" log -n 3 --oneline task-advanced-vtol`
Expected: Identify commits `b71a638` and `d8fd3c2` on `task-advanced-vtol`.

- [ ] **Step 2: Rebase worktree branch onto latest `main`**
Run:
```powershell
cd .worktrees/task-advanced-vtol
& "C:\Program Files\Git\cmd\git.exe" rebase main
cd ../..
```
Expected: Rebase succeeds cleanly without conflicts onto `main`.

- [ ] **Step 3: Run baseline verification inside worktree**
Run:
```powershell
cd .worktrees/task-advanced-vtol
python tools/verify_all_specs.py
python tools/run_unit_tests.py --require-tests --clean-orphans
python -m unittest discover -s tests/harness -p "test_*.py"
cd ../..
```
Expected: 14 specs 100% CLEAN, 248/248 unit tests PASS, 33/33 harness tests PASS.

---

### Task 1: Spec & ICD Updates for ADVANCED_VTOL

**Files:**
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (v1.24.0 -> v1.25.0)
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (v2.10.1 -> v2.11.0)
- Modify: `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (v1.10.1 -> v1.11.0, Implemented -> Approved)
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (v1.17.0 -> v1.18.0, Implemented -> Approved)
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (v1.14.0 -> v1.15.0, Implemented -> Approved)
- Modify: `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (v2.5.2 -> v2.6.0, Implemented -> Approved)

**Interfaces:**
- Consumes: Baseline specifications in `docs/system/` and `docs/specs/`.
- Produces:
  - ICD v1.25.0: `airframeType = "ADVANCED_VTOL"` definition, polymorphic `MSG_THRUST_CMD` schema (`outputs[groupId] = number | { thrust, gimbalX, gimbalY }`), extended `MSG_ACTUATOR_STATUS` with `appliedGimbal = { x, y }` and `gimbalSaturated`.
  - TCA v1.11.0: Vector thruster peripheral wrapping, gimbal deflection execution, neutral fail-safe.
  - VAS v1.18.0: Pseudo-inverse control allocation algorithm, Control Effectiveness Matrix representation, directional anti-windup.
  - FCP v1.15.0: `ADVANCED_VTOL` airframe support, `advanced_vtol_driver.lua` kinematics.
  - Alignment v2.6.0: Gimbal pulse calibration sequences and empirical $B$-matrix extraction.

- [ ] **Step 1: Check existing spec status and baseline**
Run: `python tools/verify_all_specs.py`
Expected: ALL 14 SPECS 100% CLEAN.

- [ ] **Step 2: Update `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` to v1.25.0**
  - Add `ADVANCED_VTOL` to Supported Airframes table with description: "고기동 2D 짐벌 벡터 추진 VTOL (노즐 편향 및 차동 추력 6-DoF 통합 제어, 공력 조종면 불요)".
  - Update `MSG_THRUST_CMD` payload definition with polymorphic `outputs`:
    `outputs: { [groupId: string]: number | { thrust: number, gimbalX: number, gimbalY: number } }`.
  - Update `MSG_ACTUATOR_STATUS` payload with optional `appliedGimbal: { x: number, y: number }` and `gimbalSaturated: boolean`.
  - Increment version to `v1.25.0`, date `2026-11-09`, status `Approved`, add Revision History row.

- [ ] **Step 3: Update `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` to v2.11.0**
  - Add `ADVANCED_VTOL` architecture block and packet flow annotations.
  - Increment version to `v2.11.0`, date `2026-11-09`, status `Approved`, add Revision History row.

- [ ] **Step 4: Update Subsystem Specs (TCA v1.11.0, VAS v1.18.0, FCP v1.15.0, Alignment v2.6.0)**
  - Update `TCA_PROGRAM_SPECIFICATION.md` (v1.11.0 Approved): Vector thruster peripheral wrapping, `setVector` API, `isVectorCapable` discovery flag.
  - Update `VAS_PROGRAM_SPECIFICATION.md` (v1.18.0 Approved): Pseudo-inverse wrench mixer formulation, Control Effectiveness Matrix $B$, anti-windup.
  - Update `FCP_PROGRAM_SPECIFICATION.md` (v1.15.0 Approved): `advanced_vtol_driver.lua` outer loop kinematics, `ADVANCED_VTOL` mode transitions.
  - Update `ALIGNMENT_PROGRAM_SPECIFICATION.md` (v2.6.0 Approved): Gimbal X/Y pulse calibration protocol, regression engine slopes.

- [ ] **Step 5: Run spec validation tool to confirm 100% clean**
Run: `python tools/verify_all_specs.py`
Expected: ALL 14 SPECS 100% CLEAN (0 Errors, 0 Warnings, Rule 8 clean).

- [ ] **Step 6: Commit spec updates**
```bash
& "C:\Program Files\Git\cmd\git.exe" add docs/
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(spec): update ICD and specs for ADVANCED_VTOL gimbaled propulsion"
```

---

### Task 2: TCA Vector Thruster Peripheral Adapter & Daemon

**Files:**
- Modify: `src/1_control/tca/modules/actuator_adapter.lua`
- Modify: `src/1_control/tca/modules/discovery_handler.lua`
- Modify: `src/1_control/tca/modules/group_allocator.lua`
- Modify: `src/1_control/tca/modules/tca_daemon.lua`
- Modify: `src/1_control/tca/modules/status_reporter.lua`
- Test: `tests/1_control/tca/test_tca_vector_thruster.lua`
- Modify: `tests/1_control/tca/test_tca_core.lua`

**Interfaces:**
- Consumes: `vector_thruster` peripheral methods (`setVector(x, y)`, `setPower(t)`, `getVectorX()`, `getVectorY()`).
- Produces:
  - `actuator_adapter.apply_vector_thrust(state, rawOutput, activeCount, totalCount) -> string, number, table`: applies scalar power and 2D nozzle vector.
  - `actuator_adapter.cut_thrust(state)`: sets power to 0 AND centers vector to $(0, 0)$.
  - `discovery_handler.resolve_vector_capability(adapterState) -> boolean, table`: returns `isVectorCapable`, `gimbalLimits`.
  - `status_reporter:check_and_send(payload)`: propagates `appliedGimbal` and `gimbalSaturated`.

- [ ] **Step 1: Write failing unit test for TCA vector thruster actuation**
Create `tests/1_control/tca/test_tca_vector_thruster.lua` asserting:
1. `actuator_adapter.scan_api_peripherals` detects mock `vector_thruster` with `setVector` and `setPower`.
2. `actuator_adapter.apply_thrust` with `{ thrust = 12, gimbalX = 0.5, gimbalY = -0.3 }` calls `setPower(12)` and `setVector(0.5, -0.3)`.
3. `actuator_adapter.cut_thrust` sets `setPower(0)` and `setVector(0, 0)`.
4. Clamping: inputs $gimbalX = 1.5, gimbalY = -2.0$ clamp to $1.0, -1.0$ and trigger saturation flag.
5. Backward compatibility: scalar number input `10` sets `setPower(10)` and `setVector(0, 0)`.

- [ ] **Step 2: Run test to verify it fails**
Run: `python tools/run_unit_tests.py --test-file tests/1_control/tca/test_tca_vector_thruster.lua`
Expected: FAIL (vector handling missing).

- [ ] **Step 3: Implement vector thruster handling in `actuator_adapter.lua`**
  - Add `"vector_thruster"`, `"liquid_vector_thruster"`, `"creative_vector_thruster"` detection and methods `setVector`, `setVectorX`, `setVectorY` to wrapper.
  - Extend `apply_thrust` to inspect `type(rawSignal) == "table"`:
    - Extract `thrust` (or default 0) and apply via `dispatch_val`.
    - Extract `gimbalX` and `gimbalY` clamped to $[-1.0, 1.0]$ and apply via `pcall(item.wrapped.setVector, gx, gy)`.
    - Record `lastGimbal = { x = gx, y = gy }` and `isGimbalSaturated = (math.abs(rawGx) >= 1.0 or math.abs(rawGy) >= 1.0)`.
  - In `cut_thrust`, call `setVector(0, 0)` for all vector-capable peripherals.

- [ ] **Step 4: Update `discovery_handler.lua` & `status_reporter.lua` & `tca_daemon.lua`**
  - In `discovery_handler.handle_discover_req`: include `isVectorCapable` and `gimbalLimits = { minX = -1.0, maxX = 1.0, minY = -1.0, maxY = 1.0 }` in ACK.
  - In `group_allocator.extract_group_output`: return table `{ thrust = t, gimbalX = gx, gimbalY = gy }` if entry is table, else scalar number.
  - In `tca_daemon.handle_thrust_cmd`: pass `appliedGimbal` and `gimbalSaturated` into `status_reporter:check_and_send`.
  - In `status_reporter.lua`: include `appliedGimbal` and `gimbalSaturated` in `MSG_ACTUATOR_STATUS`.

- [ ] **Step 5: Run unit tests to verify they pass**
Run: `python tools/run_unit_tests.py --test-file tests/1_control/tca/test_tca_vector_thruster.lua`
Expected: PASS.
Run: `python tools/run_unit_tests.py --test-target tca`
Expected: ALL TCA tests PASS.

- [ ] **Step 6: Commit TCA changes**
```bash
& "C:\Program Files\Git\cmd\git.exe" add src/1_control/tca/ tests/1_control/tca/
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(tca): add vector_thruster peripheral support and polymorphic thrust/gimbal actuation"
```

---

### Task 3: Alignment Gimbal Calibration & Pseudo-Inverse Matrix Engine

**Files:**
- Modify: `src/0_development/alignment/modules/discovery_client.lua`
- Modify: `src/0_development/alignment/modules/multi_pulse_sequencer.lua`
- Modify: `src/0_development/alignment/modules/ols_regression_engine.lua`
- Modify: `src/0_development/alignment/modules/profile_exporter.lua`
- Modify: `src/0_development/alignment/modules/controllability_checker.lua`
- Test: `tests/0_development/alignment/test_alignment_vector.lua`
- Modify: `tests/0_development/alignment/test_alignment_core.lua`

**Interfaces:**
- Consumes: TCA `MSG_ACTUATOR_DISCOVER_ACK` (`isVectorCapable`), IMU sensor readings.
- Produces:
  - `multi_pulse_sequencer.generate_vector_sequence(groupId) -> table`: pulse sequence for throttle, gimbalX, and gimbalY.
  - `ols_regression_engine.compute_vector_slopes(results) -> table`: $\frac{\partial \vec{W}}{\partial T}$, $\frac{\partial \vec{W}}{\partial g_x}$, $\frac{\partial \vec{W}}{\partial g_y}$.
  - `profile_exporter.compute_pseudo_inverse(B_matrix) -> table`: computes Moore-Penrose Pseudo-Inverse $B^\dagger = B^T (B B^T)^{-1}$ via Gauss-Jordan elimination with partial pivoting for $6 \times M$ matrix.
  - Profile output with `isVectorVtol = true`, `controlEffectivenessMatrix`, and `pseudoInverseMatrix`.

- [ ] **Step 1: Write failing unit test for Alignment gimbal calibration & pseudo-inverse**
Create `tests/0_development/alignment/test_alignment_vector.lua` asserting:
1. `discovery_client` marks node with `isVectorCapable = true`.
2. `multi_pulse_sequencer` schedules Gimbal X and Gimbal Y calibration pulses for vector nodes.
3. `ols_regression_engine` estimates linear gains for gimbal deflection across pitch/roll/yaw/surge/sway.
4. `profile_exporter.compute_pseudo_inverse` accurately computes $B^\dagger$ such that $B \cdot B^\dagger \approx I_6$ for a controllable 6-DoF vector thruster matrix.

- [ ] **Step 2: Run test to verify it fails**
Run: `python tools/run_unit_tests.py --test-file tests/0_development/alignment/test_alignment_vector.lua`
Expected: FAIL.

- [ ] **Step 3: Implement gimbal pulse sequence in `multi_pulse_sequencer.lua`**
  - Add sub-phases for vector nodes:
    - Phase 1: Throttle pulse (neutral gimbal $gx=0, gy=0$) at levels 5, 10, 15.
    - Phase 2: Gimbal X pulse (base throttle 8) at $gx \in \{-0.5, 0.5, 1.0\}$.
    - Phase 3: Gimbal Y pulse (base throttle 8) at $gy \in \{-0.5, 0.5, 1.0\}$.

- [ ] **Step 4: Implement OLS slopes & Pseudo-Inverse in `ols_regression_engine.lua` & `profile_exporter.lua`**
  - In `ols_regression_engine.lua`: compute 6-axis derivative vectors for $T$, $g_x$, $g_y$.
  - In `profile_exporter.lua`: assemble Control Effectiveness Matrix $B$ ($6 \times 3N$).
  - Implement $6 \times 6$ matrix inversion $(B B^T)^{-1}$ using Gauss-Jordan elimination with partial pivoting.
  - Compute $B^\dagger = B^T (B B^T)^{-1}$.
  - Export profile with `airframeType = "ADVANCED_VTOL"`, `isVectorVtol = true`, `pseudoInverseMatrix = B_dagger`.

- [ ] **Step 5: Run unit tests to verify they pass**
Run: `python tools/run_unit_tests.py --test-file tests/0_development/alignment/test_alignment_vector.lua`
Expected: PASS.
Run: `python tools/run_unit_tests.py --test-target alignment`
Expected: ALL Alignment tests PASS.

- [ ] **Step 6: Commit Alignment changes**
```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/alignment/ tests/0_development/alignment/
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(alignment): add vector thruster gimbal calibration and pseudo-inverse matrix generation"
```

---

### Task 4: VAS Policy & Pseudo-Inverse Vector Mixer

**Files:**
- Modify: `src/1_control/vas/modules/vehicle_policy.lua`
- Modify: `src/1_control/vas/modules/thrust_mixer.lua`
- Modify: `src/1_control/vas/modules/actuator_adapter_tca.lua`
- Modify: `src/1_control/vas/modules/core_daemon.lua`
- Test: `tests/1_control/vas/test_vas_advanced_vtol.lua`
- Modify: `tests/1_control/vas/test_vas_core.lua`

**Interfaces:**
- Consumes: 6-DoF wrench demand from flight dynamics, aircraft profile containing `pseudoInverseMatrix` and `controlEffectivenessMatrix`.
- Produces:
  - `thrust_mixer.allocate_vector_vtol(state, wrenchDemand) -> table`: maps 6-DoF wrench $\vec{w}$ to $\{ [groupId] = \{ thrust = T, gimbalX = gx, gimbalY = gy \} \}$ via $B^\dagger$.
  - `actuator_adapter_tca.allocate`: emits polymorphic `outputs` table in `MSG_THRUST_CMD`.
  - `vehicle_policy`: classifies `ADVANCED_VTOL` as non-aerodynamic, bypassing ASA and `MSG_AERO_CMD`.

- [ ] **Step 1: Write failing unit test for VAS ADVANCED_VTOL allocation**
Create `tests/1_control/vas/test_vas_advanced_vtol.lua` asserting:
1. `vehicle_policy` recognizes `ADVANCED_VTOL`: `flapTarget = 0.0`, no aerodynamic surfaces required.
2. `thrust_mixer` loads `pseudoInverseMatrix` from profile and computes $(T_i, gx_i, gy_i)$ given surge/sway/heave/pitch/roll/yaw demand.
3. Clamping & Anti-Windup: when surge demand pushes $gimbalY$ to $+1.0$, `saturationStatus.axisSaturatedPos.surge` becomes true.
4. `core_daemon` transmits `MSG_THRUST_CMD` on `Base+10` with polymorphic `{ thrust = ..., gimbalX = ..., gimbalY = ... }` outputs.
5. `MSG_AERO_CMD` on `Base+11` is NOT transmitted for `ADVANCED_VTOL`.

- [ ] **Step 2: Run test to verify it fails**
Run: `python tools/run_unit_tests.py --test-file tests/1_control/vas/test_vas_advanced_vtol.lua`
Expected: FAIL.

- [ ] **Step 3: Update `vehicle_policy.lua`**
  - Add `ADVANCED_VTOL` to non-aerodynamic types (matching `VECTORED_VTOL`, `QUADROTOR`, `HEXAROTOR`):
    - `transitionAlpha = 0.0`
    - `resolve_flap_target = 0.0`
    - Stall guard bypassed (non-wing).
    - Decoupled horizontal movement enabled.

- [ ] **Step 4: Implement Pseudo-Inverse Wrench Mixer in `thrust_mixer.lua` & `actuator_adapter_tca.lua`**
  - In `thrust_mixer.init`: parse `pseudoInverseMatrix` and `isVectorVtol`.
  - In `thrust_mixer.mix`:
    - If `state.isVectorVtol` and `state.pseudoInverseMatrix`:
      - Form vector $\vec{w} = [surge, sway, heave, rollTorque, pitchTorque, yawTorque]^T$.
      - Compute $\vec{u} = B^\dagger \cdot \vec{w}$.
      - For each vector group $i$: map $u_{3i-2} \to thrust$ ($0 \sim 15$), $u_{3i-1} \to gimbalX$ ($[-1.0, 1.0]$), $u_{3i} \to gimbalY$ ($[-1.0, 1.0]$).
      - Check saturation for thrust and gimbals.
      - Return `outputs[groupId] = { thrust = T, gimbalX = gx, gimbalY = gy }`.
    - Else fallback to linear scalar mixer.
  - In `actuator_adapter_tca.lua`: preserve polymorphic table structure for `outputs`.
  - In `core_daemon.lua`: integrate `gimbalSaturated` feedback into directional anti-windup accumulator.

- [ ] **Step 5: Run unit tests to verify they pass**
Run: `python tools/run_unit_tests.py --test-file tests/1_control/vas/test_vas_advanced_vtol.lua`
Expected: PASS.
Run: `python tools/run_unit_tests.py --test-target vas`
Expected: ALL VAS tests PASS.

- [ ] **Step 6: Commit VAS changes**
```bash
& "C:\Program Files\Git\cmd\git.exe" add src/1_control/vas/ tests/1_control/vas/
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(vas): implement pseudo-inverse thrust vector mixer and policy for ADVANCED_VTOL"
```

---

### Task 5: FCP Outer-Loop `advanced_vtol_driver.lua` & Guidance Integration

**Files:**
- Create: `src/2_guidance/fcp/modules/advanced_vtol_driver.lua`
- Modify: `src/2_guidance/fcp/modules/guidance_controller.lua`
- Modify: `src/2_guidance/fcp/modules/flight_fsm.lua`
- Modify: `src/2_guidance/fcp/modules/ui_renderer.lua`
- Modify: `src/2_guidance/fcp/config/fcp_config.json`
- Test: `tests/2_guidance/fcp/test_fcp_advanced_vtol.lua`
- Modify: `tests/2_guidance/fcp/test_fcp_core.lua`

**Interfaces:**
- Consumes: Navigation state (pos, vel, attitude), target waypoint, FSM flight state (`TAKEOFF`, `CRUISE`, `APPROACH`, `TOUCHDOWN`, `HOLD`).
- Produces:
  - `advanced_vtol_driver.compute(cfg, nav, target, fsm_state, dt, driver_state) -> table`: outputs `targetPitch`, `targetRoll`, `targetHeading`, `targetThrottle`, `targetClimbRate`, `translationBias = { surge, sway, heave }`.
  - `guidance_controller.is_airframe_supported("ADVANCED_VTOL") -> true`.
  - FCP TUI indicator displaying `ADVANCED_VTOL` mode.

- [ ] **Step 1: Write failing unit test for `advanced_vtol_driver`**
Create `tests/2_guidance/fcp/test_fcp_advanced_vtol.lua` asserting:
1. `guidance_controller.is_airframe_supported("ADVANCED_VTOL")` returns `true`.
2. `advanced_vtol_driver.compute` calculates 3-axis translation bias with anti-windup.
3. Airframe maintains level attitude (`targetPitch = 0, targetRoll = 0`) during translation when in `STRICT_LEVEL` mode, or applies controlled pitch in `TILT_ASSISTED` mode.
4. Vertical takeoff and precision landing sequences operate correctly.
5. `flapTarget` is strictly 0.0.

- [ ] **Step 2: Run test to verify it fails**
Run: `python tools/run_unit_tests.py --test-file tests/2_guidance/fcp/test_fcp_advanced_vtol.lua`
Expected: FAIL.

- [ ] **Step 3: Implement `src/2_guidance/fcp/modules/advanced_vtol_driver.lua`**
  - Implement 3-axis PID translation controller:
    - $surge = K_p \cdot e_{surge} + K_i \int e_{surge} + K_d \dot{e}_{surge}$
    - $sway = K_p \cdot e_{sway} + K_i \int e_{sway} + K_d \dot{e}_{sway}$
    - $heave = K_p \cdot e_{heave} + K_i \int e_{heave} + K_d \dot{e}_{heave}$
  - Gimbal slew rate limiter: limits rate of change of translation bias to match vector thruster physical deflection speed.
  - Heading management: supports `FACE_PATH` and `TARGET_LOCK`.
  - FSM transitions: `TAKEOFF` (vertical climb), `CRUISE` (high speed horizontal transit), `APPROACH` (2-stage deceleration), `TOUCHDOWN` (0.5m/s soft landing), `EMERGENCY_LAND`.

- [ ] **Step 4: Integrate into FCP runtime & configuration**
  - In `guidance_controller.lua`: add `ADVANCED_VTOL = true` to `SUPPORTED_AIRFRAMES`, dispatch to `advanced_vtol_driver`.
  - In `flight_fsm.lua`: recognize `ADVANCED_VTOL` as VTOL class.
  - In `fcp_config.json`: add `guidance.advanced_vtol` configuration block with PID gains, slew rates, and speed limits.
  - In `ui_renderer.lua`: render `ADVANCED_VTOL` header in TUI.

- [ ] **Step 5: Run unit tests to verify they pass**
Run: `python tools/run_unit_tests.py --test-file tests/2_guidance/fcp/test_fcp_advanced_vtol.lua`
Expected: PASS.
Run: `python tools/run_unit_tests.py --test-target fcp`
Expected: ALL FCP tests PASS.

- [ ] **Step 6: Commit FCP changes**
```bash
& "C:\Program Files\Git\cmd\git.exe" add src/2_guidance/fcp/ tests/2_guidance/fcp/
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(fcp): add dedicated advanced_vtol_driver and guidance controller support"
```

---

### Task 6: Ground Infrastructure & Mission System Airframe Compatibility

**Files:**
- Modify: `src/0_infra/gac/modules/allocation_engine.lua`
- Modify: `src/0_infra/landing_pad/modules/pad_fsm.lua`
- Modify: `src/0_infra/gcs/modules/fleet_tracker.lua`
- Modify: `src/3_planning/amm/modules/mission_controller.lua`
- Modify: `src/0_development/installer/modules/manifest.lua`
- Test: `tests/0_infra/gac/test_gac_advanced_vtol.lua`

**Interfaces:**
- Consumes: `airframeType = "ADVANCED_VTOL"` in C2, GAC, and telemetry packets.
- Produces:
  - GAC v1.4.1 recognizes `ADVANCED_VTOL` for Landing Pad and Docking Arm slot assignment, including `dedicatedAirframeTypes`.
  - Landing Pad accepts `ADVANCED_VTOL` in approach authorization.
  - GCS correctly renders and tracks `ADVANCED_VTOL` telemetry.
  - Installer includes `ADVANCED_VTOL` template config.

- [ ] **Step 1: Write unit test for GAC & Landing Pad handling of ADVANCED_VTOL**
Create `tests/0_infra/gac/test_gac_advanced_vtol.lua` asserting:
1. `allocation_engine.is_facility_compatible` matches `ADVANCED_VTOL` with `LANDING_PAD` and `DOCKING_ARM`.
2. Dedicated facility matching permits `dedicatedAirframeTypes = {"ADVANCED_VTOL"}`.

- [ ] **Step 2: Run test to verify it fails**
Run: `python tools/run_unit_tests.py --test-file tests/0_infra/gac/test_gac_advanced_vtol.lua`
Expected: FAIL.

- [ ] **Step 3: Update infrastructure & mission modules**
  - In `src/0_infra/gac/modules/allocation_engine.lua`: allow `ADVANCED_VTOL` for pad and arm allocation, including dedicated slot check.
  - In `src/0_infra/landing_pad/modules/pad_fsm.lua`: accept `ADVANCED_VTOL` in approach requests.
  - In `src/0_infra/gcs/modules/fleet_tracker.lua`: add `ADVANCED_VTOL` icon/label in HUD.
  - In `src/0_development/installer/modules/manifest.lua`: register `ADVANCED_VTOL` airframe preset.

- [ ] **Step 4: Run unit tests to verify they pass**
Run: `python tools/run_unit_tests.py --test-file tests/0_infra/gac/test_gac_advanced_vtol.lua`
Expected: PASS.
Run: `python tools/run_unit_tests.py --test-target gac`
Expected: ALL GAC tests PASS.

- [ ] **Step 5: Commit infrastructure updates**
```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/ src/0_development/installer/ tests/0_infra/
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(infra): add ADVANCED_VTOL airframe compatibility across GAC, Landing Pad, GCS, and Installer"
```

---

### Task 7: Full System Verification, Spec Lifecycle Promotion & Regression Sweep

**Files:**
- Modify (Status promotion):
  - `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (Approved -> Implemented)
  - `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (Approved -> Implemented)
  - `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (Approved -> Implemented)
  - `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (Approved -> Implemented)
  - `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (Approved -> Implemented)
  - `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (Approved -> Implemented)
- Verify: All modified files across repository.

- [ ] **Step 1: Run comprehensive Lua 5.2 syntax validation**
Run: `python tools/validate_lua_syntax.py`
Expected: All Lua files PASS with zero syntax errors.

- [ ] **Step 2: Run all unit test targets**
Run: `python tools/run_unit_tests.py --require-tests --clean-orphans`
Expected: 100% PASS across all targets (including alignment, tca, vas, fcp, gac, landing_pad). All existing 248 tests + new vector tests pass.

- [ ] **Step 3: Run multi-node E2E simulation tests**
Run: `python tools/run_e2e_tests.py --clean-orphans`
Expected: 6/6 E2E scenarios PASS (verifying backward compatibility with fixed thruster airframes).

- [ ] **Step 4: Run mutation testing suite**
Run: `python tools/run_mutation_tests.py`
Expected: 100% kill rate (20/20 mutants killed).

- [ ] **Step 5: Run harness regression and terminology tests**
Run: `python -m unittest discover -s tests/harness -p "test_*.py"`
Expected: ALL 33 tests PASS (including `test_terminology_guard.py` 4/4 PASS).

- [ ] **Step 6: Promote specification statuses to `Implemented`**
  - Update top metadata table `문서 상태` to `Implemented` and `최종 수정일` to `2026-11-09` for:
    - ICD (v1.25.0)
    - System Diagram (v2.11.0)
    - TCA (v1.11.0)
    - VAS (v1.18.0)
    - FCP (v1.15.0)
    - Alignment (v2.6.0)

- [ ] **Step 7: Run full specification integrity and link verification**
Run: `python tools/verify_all_specs.py`
Expected: ALL 14 SPECS 100% CLEAN (0 Errors, 0 Warnings).

- [ ] **Step 8: Final commit and branch review**
```bash
& "C:\Program Files\Git\cmd\git.exe" add docs/
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(spec): promote ADVANCED_VTOL specs to Implemented post-verification"
& "C:\Program Files\Git\cmd\git.exe" status -sb
```
Confirm clean git working tree on `task-advanced-vtol`.
