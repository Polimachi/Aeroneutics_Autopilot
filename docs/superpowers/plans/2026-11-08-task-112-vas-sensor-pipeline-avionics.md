# TASK-112: VAS 센서 파이프라인 CC:Avionics 표준 API 동기화 및 3축 속도/고도 정합화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the VAS (Node 01) sensor pipeline to synchronize with the universal `/lib/avionics_sensors.lua` standard library, ensuring full CC:Avionics official API conformity (`getHeight()`, multi-axis `getVelocity()` synthesis, gimbal Euler & rates) with 3D lever-arm compensation and updated unit tests.

**Architecture:** VAS relies on a 20Hz 3-Layer Sandwich pipeline where `sensor_pipeline.lua` is Layer 1. This refactoring binds `require("avionics_sensors")` for safe 0-tick peripheral sampling, normalizes raw sensor readings into standard physical quantities, executes 3D body lever-arm compensation ($\Delta h$ and $\mathbf{v} - \boldsymbol{\omega} \times \mathbf{r}$), and produces $SO(3)$ quaternion attitudes and multi-layer health maps for the FSM and flight controller.

**Tech Stack:** CC:Tweaked Lua 5.2 / Cobalt, CC:Avionics (`gimbal_sensor`, `altitude_sensor`, `velocity_sensor`), Create fluid tank / battery, CraftOS-PC unit test harness (`test_sdk.lua`).

**Spec:** `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (v1.14.0 -> v1.15.0)

## Global Constraints

- **Multi-Codebase Autonomy**: `src/1_control/vas/` remains self-contained; external shared libraries are accessed exclusively via `/lib/avionics_sensors.lua`.
- **Zero-Tick Non-Blocking**: All peripheral calls in 20Hz loop must remain protected by `pcall`/safe wrappers without yielding or stalling.
- **Zero-Fallback Single-Key**: Schema names must strictly follow standard property names without dual-key runtime fallbacks on reception.
- **Coordinate System**: Minecraft world coordinates ($+X$ East, $+Y$ Up, $+Z$ South) and body NED/FRD conventions are preserved without coordinate inversion.
- **Spec Status Protocol**: `VAS_PROGRAM_SPECIFICATION.md` retains its `Implemented` status upon completion, verified via `verify_spec_status.py` and `verify_all_specs.py`.

## Review Focus

1. **`altitude_sensor` official method resolution**: `getHeight()` and `getYCoordinate()` must take precedence over legacy `getAltitude()`, returning nil on invalid readings without crashing.
2. **1-axis `velocity_sensor` synthesis**: When only 1 or 2 velocity sensors are wired, missing axes must evaluate cleanly to `0.0` m/s rather than `nil`.
3. **`gimbal_sensor` angular rates mapping**: `getAngularRates()` array/table format must consistently map body rates (`wx` $\rightarrow$ pitch rate, `wy` $\rightarrow$ yaw rate, `wz` $\rightarrow$ roll rate).
4. **Lever-arm nil safety**: Empty or omitted `leverArmOffset` in sensor configuration must default to `{ dx = 0.0, dy = 0.0, dz = 0.0 }` without calculation drift.
5. **Standalone fallback robustness**: If `/lib/avionics_sensors.lua` is not found, `sensor_pipeline.lua` must fall back to basic direct peripheral queries rather than failing at load time.

---

### Task 1: VAS Specification Standardization (`VAS_PROGRAM_SPECIFICATION.md`)

**Files:**
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`
- Validate: `tools/verify_all_specs.py`, `tools/verify_spec_status.py`

**Interfaces:**
- Consumes: `/lib/avionics_sensors.lua` SSOT API definition from `src/0_development/sensors/avionics_sensors.lua`.
- Produces: Updated Sections 2.0, 2.1, 3.1-3.4, 5.2, and Revision History in `VAS_PROGRAM_SPECIFICATION.md`.

- [ ] **Step 1: Check current spec status and integrity**

Run: `python tools/verify_all_specs.py; python tools/verify_spec_status.py`
Expected: ALL 12 SPECS CLEAN, 7 Implemented, 5 Approved PASS.

- [ ] **Step 2: Update `VAS_PROGRAM_SPECIFICATION.md` Section 2, Section 3, Section 5.2, and Metadata Table**

Update metadata table:
- Version: `v1.15.0`
- Date: `2026-11-08`
- Status: `Implemented`

Update Section 2.1 table:
- Specify official peripheral types (`avionics:gimbal_sensor`, `avionics:altitude_sensor`, `avionics:velocity_sensor`) and `/lib/avionics_sensors.lua` module integration.
- Document `altitude_sensor.getHeight()` and multi-sensor `velocity_sensor.read_vector3()` synthesis.

Update Section 3.1 & 3.3:
- Document `sensors.gimbal.get_angular_rates()` replacing deprecated `getAngularVelocity()`.
- Add Revision History entry for `v1.15.0`.

- [ ] **Step 3: Run spec integrity verification**

Run: `python tools/verify_all_specs.py; python tools/verify_spec_status.py`
Expected: ALL 12 SPECS CLEAN, 7 Implemented, 5 Approved PASS.

- [ ] **Step 4: Commit spec update**

```bash
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(vas): synchronize specification Section 2-3 with CC:Avionics standard API"
```

---

### Task 2: Refactor `sensor_pipeline.lua` to Consume `avionics_sensors` (TDD Red-Green)

**Files:**
- Modify: `src/1_control/vas/modules/sensor_pipeline.lua`
- Test: `tests/1_control/vas/test_sensor_pipeline_refactor.lua` (temporary focused test or inline within test suite)

**Interfaces:**
- Consumes: `require("avionics_sensors")` (`sensors.gimbal`, `sensors.altitude`, `sensors.velocity`, `sensors.fuel`), `require("quat")`.
- Produces:
  - `sensor_pipeline.init(sensorsConfig) -> state`
  - `sensor_pipeline.sample_all(state) -> rawSamples`
  - `sensor_pipeline.evaluate_health(rawSamples, roles) -> healthMap, sensorOk`
  - `sensor_pipeline.compensate_lever_arm(rawSamples, lastCom, cfg, dt) -> comState`
  - `sensor_pipeline.process_kinematics(state, rawSamples, dt) -> comState, healthMap, sensorOk`
  - `sensor_pipeline.reconnect_faulty(state, healthMap) -> count`

- [ ] **Step 1: Write failing test verifying authentic CC:Avionics peripheral sampling in `sensor_pipeline`**

Add tests exercising:
1. `sensor_pipeline.sample_all` with `mock.cc_gimbal_sensor`, `mock.cc_altitude_sensor`, `mock.cc_velocity_sensor`.
2. Verify `raw.altitude.altitude` receives `getHeight()` value.
3. Verify `raw.velocity` combines 3D velocity using `read_vector3` or authentic velocity mocks.
4. Verify `raw.gimbal.pitchRate`, `rollRate`, `yawRate` correctly maps `wx, wz, wy`.
5. Verify `reconnect_faulty` restores failed devices using `avionics_sensors.find`.

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 1_control/vas`
Expected: FAIL due to legacy method mismatch or missing behavior.

- [ ] **Step 3: Implement refactored `sensor_pipeline.lua`**

1. Require `avionics_sensors` safely (`local okSensors, sensors = pcall(require, "avionics_sensors")`).
2. In `sample_device_role`:
   - If `sensors` is present:
     - Role `gimbal`: call `sensors.gimbal.get_angles(dev)` and `sensors.gimbal.get_angular_rates(dev)`.
     - Role `altitude`: call `sensors.altitude.get_height(dev)` (and `sensors.altitude.get_vertical_speed(dev)`).
     - Role `velocity`: call `sensors.velocity.read_vector3({ preferred_side = roleCfg.preferredSide })` or `sensors.velocity.get_velocity(dev)`.
     - Role `fuel`: call `sensors.fuel.get_fuel_level(dev)` or tank inspection.
   - If `sensors` not present: retain minimal direct peripheral method fallback (`getHeight`, `getAngles`, `getAngularRates`, `getVelocity`).
3. Ensure exact return schemas match downstream consumer expectations in `compensate_lever_arm` and `core_daemon`.
4. Keep 3D lever-arm transformation equations intact ($\Delta h$, $\boldsymbol{\omega} \times \mathbf{r}$).

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 1_control/vas`
Expected: PASS.

- [ ] **Step 5: Commit `sensor_pipeline.lua`**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/1_control/vas/modules/sensor_pipeline.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(vas): integrate avionics_sensors standard API into sensor_pipeline"
```

---

### Task 3: Align VAS Core Test Suite with Authentic CC:Avionics Mocks

**Files:**
- Modify: `tests/1_control/vas/test_vas_core.lua`

**Interfaces:**
- Consumes: `mock.cc_gimbal_sensor`, `mock.cc_altitude_sensor`, `mock.cc_velocity_sensor`, `mock.fuel_tank` from `harness/unit/guest/test_sdk.lua`.
- Produces: 10/10 PASS on `0_control/vas` unit tests.

- [ ] **Step 1: Write test cases in `test_vas_core.lua` testing authentic mocks**

Update `test_vas_core.lua` lines 50-92 to use:
- `mock.cc_gimbal_sensor({ pitch = 5.0, roll = -2.0, wx = 0.1, wy = 0.0, wz = 0.0 })`
- `mock.cc_altitude_sensor({ height = 150.0, verticalSpeed = 0.5 })`
- `mock.cc_velocity_sensor({ velocity = 10.0, axis = "x" })` (or multi-axis velocity mock registry)
- `mock.fuel_tank(800, 1000)`

Verify backward compatibility with legacy `mock.avionics_gimbal`, `mock.avionics_altitude`, and `mock.avionics_velocity`.

- [ ] **Step 2: Run test suite to verify tests pass**

Run: `python tools/run_unit_tests.py --target 1_control/vas`
Expected: 10/10 tests PASS.

- [ ] **Step 3: Commit updated test suite**

```bash
& "C:\Program Files\Git\cmd\git.exe" add tests/1_control/vas/test_vas_core.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "test(vas): align test_vas_core with authentic CC:Avionics sensor mocks"
```

---

### Task 4: Full System Verification, Installer Manifest Check, and Project Handover

**Files:**
- Modify: `TASK.md`
- Modify: `GEMINI.md`
- Check: `src/0_development/installer/modules/manifest.lua`

- [ ] **Step 1: Verify installer bundle includes `/lib/avionics_sensors.lua` for VAS**

Verify that `src/0_development/installer/modules/manifest.lua` contains `{ repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua" }` for `vas` module.
Run installer tests: `python tools/run_unit_tests.py --target 0_development/installer`
Expected: 28/28 PASS.

- [ ] **Step 2: Run complete 5-stage verification suite**

1. `python tools/run_unit_tests.py --require-tests --clean-orphans` (Assert 144/144 PASS across 10 targets)
2. `python -m unittest discover -s tests/harness -p "test_*.py"` (Assert 24/24 PASS)
3. `python tools/validate_lua_syntax.py` (Assert 109/109 PASS)
4. `python tools/verify_all_specs.py` (Assert 12/12 PASS, 0 errors, 0 warnings)
5. `python tools/verify_spec_status.py` (Assert 7 Implemented, 5 Approved PASS)

- [ ] **Step 3: Update `TASK.md` and `GEMINI.md`**

1. In `TASK.md`: Mark `TASK-112` as completed (`[x]`) with all subtasks (`TASK-112-1` ~ `TASK-112-4`), move to Section 3 Completed Tasks archive.
2. In `GEMINI.md`: Update Section 1 Active Handover with completed `TASK-112` and nominate next task candidates (`TASK-106`, `TASK-110`). Keep strictly $\le 80$ lines.

- [ ] **Step 4: Commit task completion**

```bash
& "C:\Program Files\Git\cmd\git.exe" add TASK.md GEMINI.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "chore(task): complete TASK-112 VAS avionics sensor standardization and update living context"
```
