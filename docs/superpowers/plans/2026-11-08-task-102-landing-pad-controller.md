# Landing Pad Controller (TASK-102) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Tier 3 Landing Pad Controller (`src/0_infra/landing_pad/`) for VTOL ground/shipboard facility management, featuring virtual coordinate beaconing, computer body-frame 3D offset transform, dynamic 3-sensor auto-binding (`gimbal`, `altitude`, `velocity`), 5-step interactive TUI setup wizard, 3-second boot countdown FSM, GAC local backbone synchronization ($Base_{\text{sec}}+1$), and 20Hz tactical guidance streaming ($Base_{\text{sec}}+10+\text{Idx}$) with deck stability evaluation.

**Architecture:** A standalone, non-blocking ComputerCraft Lua application divided into modular components: configuration persistence (`config_store.lua`), 3D body-frame coordinate transformer (`offset_transform.lua`), CC:Avionics sensor adapter & deck stability analyzer (`sensor_adapter.lua`), GPS client & 20Hz dead-reckoning integrator (`gps_client.lua`), tactical guidance packet streamer (`tactical_streamer.lua`), pad FSM state machine (`pad_fsm.lua`), and an interactive 5-stage setup wizard & 51x19 terminal TUI (`setup_wizard.lua`, `tui_view.lua`) orchestrated by a 20Hz event loop (`main.lua`).

**Tech Stack:** CC:Tweaked Lua 5.2 (Cobalt VM), Ender Modem wireless networking (CH 60001, $Base_{\text{sec}}+0$, $Base_{\text{sec}}+1$, $Base_{\text{sec}}+5$, $Base_{\text{sec}}+10+\text{Idx}$), CC:Avionics sensor library (`avionics_sensors`), Advanced Color Computer & Monitor API (`term`, `colors`, `keys`), CraftOS-PC Headless Unit Test Framework (`tools/run_unit_tests.py`).

**Spec:** [LANDING_PAD_SPECIFICATION_AND_ICD.md](../../specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md) (v2.4.0)

## Global Constraints

- **Multi-Codebase Autonomy**: `src/0_infra/landing_pad/` must be 100% self-contained; no cross-layer `require` references to other subsystems (e.g. `gac`, `vas`, `fcp`), except the standard shared `/lib/avionics_sensors.lua`.
- **Channel Allocation Hierarchy**: Sector Base $Base_{\text{sec}} = 50001 + S \times 200$. Common GPS Ping `60001`. Sector Comm $+0$, Sector Local Backbone $+1$, Sector GPS Reply $+5$, Tactical channel $+10+Idx$.
- **Standard Envelope & Zero-Fallback**: Strict envelope (`ver="1.9.5"`, `domainId`, `seq`, `type`, `time`, `payload`) using exact single-key field names.
- **Sensor Standard Library**: Sensor bindings must use `require("avionics_sensors")` (`/lib/avionics_sensors.lua`).
- **51x19 Terminal TUI Layout**: 5-step setup wizard and 1-line compact daemon status bar must render safely within CC:Tweaked standard 51x19 terminal dimensions.
- **Lua 5.2 Compatibility**: No Lua 5.3+ bitwise operators (`//`, `&`, `|`, `~`), use `fs.*` exclusively.

## Review Focus

1. **Dynamic Sensor Absence / Disconnect during flight (`HALT_WITH_WARNING` & `MAINTENANCE`)**: In DYNAMIC mode, missing any of `gimbal_sensor`, `altitude_sensor`, or `velocity_sensor` at wizard time locks setup; at runtime, triggers immediate `MAINTENANCE` and broadcasts `MSG_ABORT_APPROACH` (`reason: SENSOR_FAULT`).
2. **Body Offset 3D Transformation with Mounting Yaw**: Ensures pad center position coordinates accurately rotate with `mountingYawOffset` and platform heading.
3. **GPS Latency & 20Hz Speed Integration Dead-Reckoning**: When GPS response arrives at 5Hz (or 1Hz), velocity integration ($v_x, v_y, v_z \times \Delta t$) updates position at 20Hz without cumulative drift spikes.
4. **Ghost Slot Timeout**: If an assigned aircraft fails to send `MSG_TOUCHDOWN_COMPLETE` within 120s, pad transitions to `GO_AROUND`, sends `MSG_ABORT_APPROACH` (`reason: TIMEOUT`), and reports to GAC to reset `FREE`.
5. **Atomic Config Serialization & Boot Hotkey**: `/landing_pad/config.json` must be written atomically via temp file; 3-second countdown accepts `[S]` to enter wizard or timeouts to autonomous daemon.

---

## File Structure

- `src/0_infra/landing_pad/modules/config_store.lua` — Configuration parsing, schema validation, and atomic JSON persistence for `/landing_pad/config.json`.
- `src/0_infra/landing_pad/modules/offset_transform.lua` — 3D body-frame offset transformation and platform heading rotation.
- `src/0_infra/landing_pad/modules/sensor_adapter.lua` — Sensor peripheral discovery, background 1Hz auto-reconnection, and deck stability mathematical model ($\theta_{\text{tilt}} \le 10.0^\circ, |v_y| \le 2.5\text{ m/s}$).
- `src/0_infra/landing_pad/modules/gps_client.lua` — Dual-rate GPS request/response protocol (CH 60001 / $Base_{\text{sec}}+5$) and 20Hz velocity dead-reckoning integrator.
- `src/0_infra/landing_pad/modules/tactical_streamer.lua` — Packet builder for `MSG_FACILITY_STATIC_GUIDE`, `MSG_FACILITY_DYNAMIC_GUIDE`, `MSG_ABORT_APPROACH`, and `MSG_ATC_SLOT_ACK`.
- `src/0_infra/landing_pad/modules/pad_fsm.lua` — FSM state machine managing `INIT`, `IDLE`, `RESERVED`, `APPROACH_STATIC`, `APPROACH_DYNAMIC`, `OCCUPIED`, `GO_AROUND`, and `MAINTENANCE`.
- `src/0_infra/landing_pad/modules/tui_view.lua` — 51x19 terminal TUI rendering daemon status, live kinematics, and 1-line compact rolling audit log.
- `src/0_infra/landing_pad/modules/setup_wizard.lua` — 5-step interactive commissioning wizard and 3-second boot countdown FSM.
- `src/0_infra/landing_pad/config.lua` — Default configuration module.
- `src/0_infra/landing_pad/main.lua` — 20Hz non-blocking main daemon coordinating network, sensors, FSM, and TUI.
- `tests/0_infra/landing_pad/test_config_store.lua` — Unit tests for config persistence and schema validation.
- `tests/0_infra/landing_pad/test_offset_transform.lua` — Unit tests for 3D body offset coordinate translation.
- `tests/0_infra/landing_pad/test_sensor_adapter.lua` — Unit tests for sensor discovery, stability evaluation, and auto-reconnection.
- `tests/0_infra/landing_pad/test_gps_client.lua` — Unit tests for GPS ping/response and 20Hz dead reckoning.
- `tests/0_infra/landing_pad/test_tactical_streamer.lua` — Unit tests for tactical guidance envelope and payload generation.
- `tests/0_infra/landing_pad/test_pad_fsm.lua` — Unit tests for FSM lifecycle, abort triggers, and 120s slot timeout.
- `tests/0_infra/landing_pad/test_setup_and_tui.lua` — Unit tests for wizard validation, countdown, and 51x19 TUI output.
- `tests/0_infra/landing_pad/test_main_integration.lua` — Integration smoke test for the landing pad daemon.

---

### Task 1: Configuration Store & Body Offset 3D Coordinate Transform (`config_store.lua`, `offset_transform.lua`)

**Files:**
- Create: `src/0_infra/landing_pad/modules/config_store.lua`
- Create: `src/0_infra/landing_pad/modules/offset_transform.lua`
- Create: `tests/0_infra/landing_pad/test_config_store.lua`
- Create: `tests/0_infra/landing_pad/test_offset_transform.lua`

**Interfaces:**
- Consumes: `fs`, `textutils`, `math`
- Produces:
  - `config_store.get_default_config() -> table`
  - `config_store.validate_config(cfg: table) -> boolean, string | nil`
  - `config_store.load_config(path: string | nil) -> table, string | nil`
  - `config_store.save_config(path: string | nil, cfg: table) -> boolean, string | nil`
  - `offset_transform.calculate_pad_position(compPos: table, platformYaw: number, mountingYawOffset: number, bodyOffset: table) -> table`

- [ ] **Step 1: Write failing test**

```lua
-- tests/0_infra/landing_pad/test_config_store.lua
local config_store = require("config_store")

describe("Landing pad configuration store and persistence", function()
    it("returns default config matching v2.4.0 schema", function()
        local def = config_store.get_default_config()
        assert_eq(type(def), "table")
        assert_eq(def.version, "2.4.0")
        assert_eq(def.facilityId, "PAD_BRAVO_01")
        assert_eq(def.sectorId, 1)
        assert_eq(def.padIndex, 1)
        assert_eq(def.tacticalChannel, 50211)
        assert_eq(def.gacChannel, 50201)
        assert_eq(def.sectorFacilityChannel, 50202)
        assert_eq(def.sectorGpsReplyChannel, 50206)
        
        local ok, err = config_store.validate_config(def)
        assert_true(ok)
        assert_nil(err)
    end)

    it("rejects incomplete configuration", function()
        local bad = { facilityId = "PAD_01" }
        local ok, err = config_store.validate_config(bad)
        assert_false(ok)
        assert_not_nil(err)
    end)

    it("saves and loads configuration atomically", function()
        local path = sdk.temp_path("pad_config.json")
        local cfg = config_store.get_default_config()
        cfg.facilityId = "PAD_CUSTOM_99"
        
        local okSave, errSave = config_store.save_config(path, cfg)
        assert_true(okSave, errSave)
        
        local loaded, errLoad = config_store.load_config(path)
        assert_not_nil(loaded)
        assert_nil(errLoad)
        assert_eq(loaded.facilityId, "PAD_CUSTOM_99")
    end)
end)
```

```lua
-- tests/0_infra/landing_pad/test_offset_transform.lua
local offset_transform = require("offset_transform")

describe("Landing pad 3D body offset coordinate transform", function()
    it("transforms body offset (fwd, right, up) correctly when facing North (yaw=0)", function()
        local compPos = { x = 100.0, y = 64.0, z = 200.0 }
        local bodyOffset = { forward = 10.0, right = 5.0, up = 1.5 }
        -- Facing North (yaw 0): forward is -Z, right is +X, up is +Y
        local padPos = offset_transform.calculate_pad_position(compPos, 0.0, 0.0, bodyOffset)
        assert_near(padPos.x, 105.0, 1e-4)
        assert_near(padPos.y, 65.5, 1e-4)
        assert_near(padPos.z, 190.0, 1e-4)
    end)

    it("transforms body offset correctly with platform yaw 90 (East) and mounting yaw 0", function()
        local compPos = { x = 100.0, y = 64.0, z = 200.0 }
        local bodyOffset = { forward = 10.0, right = 0.0, up = 0.0 }
        -- Facing East (yaw 90): forward is +X, right is +Z
        local padPos = offset_transform.calculate_pad_position(compPos, 90.0, 0.0, bodyOffset)
        assert_near(padPos.x, 110.0, 1e-4)
        assert_near(padPos.y, 64.0, 1e-4)
        assert_near(padPos.z, 200.0, 1e-4)
    end)

    it("incorporates mountingYawOffset (+90 deg starboard mounting)", function()
        local compPos = { x = 0.0, y = 64.0, z = 0.0 }
        local bodyOffset = { forward = 10.0, right = 0.0, up = 0.0 }
        -- Platform yaw 0 (North), Computer mounted at +90 (facing East). Total yaw = 90
        local padPos = offset_transform.calculate_pad_position(compPos, 0.0, 90.0, bodyOffset)
        assert_near(padPos.x, 10.0, 1e-4)
        assert_near(padPos.z, 0.0, 1e-4)
    end)
end)
```

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 0_infra/landing_pad`
Expected: FAIL (`target has no unit tests` or `module not found`)

- [ ] **Step 3: Implement minimal code**

Implement `src/0_infra/landing_pad/modules/config_store.lua` and `src/0_infra/landing_pad/modules/offset_transform.lua`:
- `config_store`: default values matching ICD Section 6.4, atomic save using `.tmp` and `fs.move`.
- `offset_transform`:
  Total yaw $\psi = \text{math.rad}((\text{platformYaw} + \text{mountingYawOffset}) \pmod{360})$.
  $x_{pad} = x_{comp} + fwd \cdot \sin(\psi) + right \cdot \cos(\psi)$.
  $y_{pad} = y_{comp} + up$.
  $z_{pad} = z_{comp} - fwd \cdot \cos(\psi) + right \cdot \sin(\psi)$.

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 0_infra/landing_pad`
Expected: PASS (`6/6 PASS`)

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/landing_pad/modules/config_store.lua src/0_infra/landing_pad/modules/offset_transform.lua tests/0_infra/landing_pad/test_config_store.lua tests/0_infra/landing_pad/test_offset_transform.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(landing_pad): implement config store and 3D body offset transform"
```

---

### Task 2: Sensor Adapter & Deck Stability Evaluator (`sensor_adapter.lua`)

**Files:**
- Create: `src/0_infra/landing_pad/modules/sensor_adapter.lua`
- Create: `tests/0_infra/landing_pad/test_sensor_adapter.lua`

**Interfaces:**
- Consumes: `avionics_sensors`, `math`
- Produces:
  - `sensor_adapter.create(mode: string, preferredSide: string | nil) -> table`
  - `adapter:scan_peripherals() -> boolean, table`
  - `adapter:evaluate_deck_stability(pitch: number, roll: number, vy: number) -> string, boolean, number`
  - `adapter:read_kinematics() -> table, string | nil`
  - `adapter:check_auto_reconnect(nowSec: number) -> boolean`

- [ ] **Step 1: Write failing test**

```lua
-- tests/0_infra/landing_pad/test_sensor_adapter.lua
local sensor_adapter = require("sensor_adapter")

describe("Landing pad sensor adapter and deck stability evaluator", function()
    it("evaluates deck stability: STABLE when tilt <= 10 deg and |vy| <= 2.5 m/s", function()
        local adapter = sensor_adapter.create("DYNAMIC")
        local status, permitted, tilt = adapter:evaluate_deck_stability(1.2, -2.5, -0.15)
        assert_eq(status, "STABLE")
        assert_true(permitted)
        assert_near(tilt, 2.773, 1e-2)
    end)

    it("evaluates deck stability: DANGEROUS when tilt > 10 deg or |vy| > 2.5 m/s", function()
        local adapter = sensor_adapter.create("DYNAMIC")
        local status1, permitted1 = adapter:evaluate_deck_stability(8.0, 7.0, 0.5) -- tilt = sqrt(64+49) = 10.63 > 10.0
        assert_eq(status1, "DANGEROUS")
        assert_false(permitted1)

        local status2, permitted2 = adapter:evaluate_deck_stability(2.0, 2.0, 3.0) -- vy = 3.0 > 2.5
        assert_eq(status2, "DANGEROUS")
        assert_false(permitted2)
    end)

    it("scans peripherals and enforces 3 required sensors in DYNAMIC mode", function()
        local adapter = sensor_adapter.create("DYNAMIC")
        mock.peripheral_registry({
            top = { type = "modem", dev = mock.cc_modem({ isWireless = true }) }
        })
        local ok, scanReport = adapter:scan_peripherals()
        assert_false(ok)
        assert_false(scanReport.gimbal)
        assert_false(scanReport.altitude)
        assert_false(scanReport.velocity)
    end)

    it("passes peripheral scan in DYNAMIC mode when all 3 sensors are present", function()
        local adapter = sensor_adapter.create("DYNAMIC")
        mock.peripheral_registry({
            gimbal_0 = { type = "gimbal_sensor", dev = mock.cc_gimbal_sensor({ pitch = 0, roll = 0, yaw = 0 }) },
            altitude_0 = { type = "altitude_sensor", dev = mock.cc_altitude_sensor({ height = 64 }) },
            velocity_0 = { type = "velocity_sensor", dev = mock.cc_velocity_sensor({ velocity = 0, axis = "Y" }) }
        })
        local ok, scanReport = adapter:scan_peripherals()
        assert_true(ok)
        assert_true(scanReport.gimbal)
        assert_true(scanReport.altitude)
        assert_true(scanReport.velocity)
    end)
end)
```

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 0_infra/landing_pad`
Expected: FAIL (`module 'sensor_adapter' not found`)

- [ ] **Step 3: Implement minimal code**

Implement `src/0_infra/landing_pad/modules/sensor_adapter.lua`:
- Calls `sensors = require("avionics_sensors")`.
- `evaluate_deck_stability(pitch, roll, vy)`:
  $\theta_{\text{tilt}} = \sqrt{pitch^2 + roll^2}$.
  If $\theta_{\text{tilt}} \le 10.0$ and $|vy| \le 2.5$, returns `"STABLE"`, `true`, $\theta_{\text{tilt}}$.
  Else returns `"DANGEROUS"`, `false`, $\theta_{\text{tilt}}$.
- `scan_peripherals()`: checks `sensors.gimbal.find()`, `sensors.altitude.find()`, `sensors.velocity.find()`. In DYNAMIC mode, requires all 3. In STATIC mode, sensors are optional.
- `read_kinematics()`: retrieves pitch, roll, yaw, altitude, and 3D velocity using `sensors.velocity.get_velocity_3d()`.
- `check_auto_reconnect(nowSec)`: 1-second interval rescan if in faulted/missing state.

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 0_infra/landing_pad`
Expected: PASS (`10/10 PASS`)

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/landing_pad/modules/sensor_adapter.lua tests/0_infra/landing_pad/test_sensor_adapter.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(landing_pad): implement sensor adapter and deck stability evaluator"
```

---

### Task 3: GPS Client & 20Hz Dead-Reckoning Integrator (`gps_client.lua`)

**Files:**
- Create: `src/0_infra/landing_pad/modules/gps_client.lua`
- Create: `tests/0_infra/landing_pad/test_gps_client.lua`

**Interfaces:**
- Consumes: `os.epoch`, `math`
- Produces:
  - `gps_client.create(facilityId: string, replyChannel: number) -> table`
  - `client:build_request_packet() -> table`
  - `client:handle_response_packet(packet: table) -> boolean`
  - `client:update_dead_reckoning(vel: table, nowSec: number) -> table`
  - `client:get_current_position() -> table | nil`

- [ ] **Step 1: Write failing test**

```lua
-- tests/0_infra/landing_pad/test_gps_client.lua
local gps_client = require("gps_client")

describe("Landing pad GPS client and dead-reckoning integrator", function()
    it("generates standard MSG_GPS_REQUEST packet targeted to facilityId", function()
        local client = gps_client.create("PAD_BRAVO_01", 50206)
        local req = client:build_request_packet()
        assert_eq(req.type, "MSG_GPS_REQUEST")
        assert_eq(req.payload.clientType, "FACILITY")
        assert_eq(req.payload.targetClient, "PAD_BRAVO_01")
        assert_eq(req.payload.replyChannel, 50206)
    end)

    it("filters and processes MSG_GPS_RESPONSE matching targetClient", function()
        local client = gps_client.create("PAD_BRAVO_01", 50206)
        local otherResp = {
            type = "MSG_GPS_RESPONSE",
            payload = { targetClient = "OTHER_PAD", position = { x = 0, y = 0, z = 0 } }
        }
        assert_false(client:handle_response_packet(otherResp))
        assert_nil(client:get_current_position())

        local validResp = {
            type = "MSG_GPS_RESPONSE",
            payload = { targetClient = "PAD_BRAVO_01", position = { x = 840.25, y = 62.10, z = 1120.80 } }
        }
        assert_true(client:handle_response_packet(validResp))
        local pos = client:get_current_position()
        assert_eq(pos.x, 840.25)
        assert_eq(pos.y, 62.10)
    end)

    it("integrates velocity over dt at 20Hz without drift spikes", function()
        local client = gps_client.create("PAD_BRAVO_01", 50206)
        client:handle_response_packet({
            type = "MSG_GPS_RESPONSE",
            payload = { targetClient = "PAD_BRAVO_01", position = { x = 100.0, y = 60.0, z = 200.0 } }
        })
        client:set_last_update_time(10.0)

        -- dt = 0.05s (20Hz), vel = { vx = 10.0, vy = 0.0, vz = 0.0 }
        local pos = client:update_dead_reckoning({ vx = 10.0, vy = 0.0, vz = 0.0 }, 10.05)
        assert_near(pos.x, 100.5, 1e-4) -- 100.0 + 10.0 * 0.05
        assert_near(pos.z, 200.0, 1e-4)
    end)
end)
```

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 0_infra/landing_pad`
Expected: FAIL (`module 'gps_client' not found`)

- [ ] **Step 3: Implement minimal code**

Implement `src/0_infra/landing_pad/modules/gps_client.lua`:
- `build_request_packet`: builds standard `MSG_GPS_REQUEST` with `clientType="FACILITY"`, `targetClient=facilityId`, `replyChannel`.
- `handle_response_packet`: validates `payload.targetClient == facilityId`, updates internal anchor position and timestamp.
- `update_dead_reckoning(vel, nowSec)`: computes $\Delta t = nowSec - lastUpdateSec$, updates position: $x = x + v_x \Delta t, y = y + v_y \Delta t, z = z + v_z \Delta t$.

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 0_infra/landing_pad`
Expected: PASS (`13/13 PASS`)

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/landing_pad/modules/gps_client.lua tests/0_infra/landing_pad/test_gps_client.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(landing_pad): implement GPS client and 20Hz dead reckoning integrator"
```

---

### Task 4: Tactical Guidance Packet Builder & Broadcaster (`tactical_streamer.lua`)

**Files:**
- Create: `src/0_infra/landing_pad/modules/tactical_streamer.lua`
- Create: `tests/0_infra/landing_pad/test_tactical_streamer.lua`

**Interfaces:**
- Consumes: `os.epoch`
- Produces:
  - `tactical_streamer.create(config: table) -> table`
  - `streamer:build_static_guide(touchdownPoint: table, targetCraft: string, abortAlert: boolean) -> table`
  - `streamer:build_dynamic_guide(touchdownPoint: table, targetCraft: string, kinematics: table, stability: table, abortAlert: boolean) -> table`
  - `streamer:build_abort_approach(targetCraft: string, reason: string) -> table`
  - `streamer:build_slot_ack(craftId: string, accepted: boolean, rejectReason: string | nil) -> table`
  - `streamer:build_facility_update(status: string, craftId: string | nil, telemetry: table | nil) -> table`

- [ ] **Step 1: Write failing test**

```lua
-- tests/0_infra/landing_pad/test_tactical_streamer.lua
local tactical_streamer = require("tactical_streamer")

describe("Landing pad tactical guidance streamer", function()
    local cfg = {
        facilityId = "PAD_BRAVO_01",
        tacticalChannel = 50211,
        approachHeading = 180.0,
        safeDescentRate = 1.0,
        clearanceZoneRadius = 5.0
    }

    it("builds standard MSG_FACILITY_STATIC_GUIDE (1Hz)", function()
        local streamer = tactical_streamer.create(cfg)
        local pos = { x = 1250.0, y = 65.0, z = -820.0 }
        local pkt = streamer:build_static_guide(pos, "AIRCRAFT_01", false)
        assert_eq(pkt.ver, "1.9.5")
        assert_eq(pkt.type, "MSG_FACILITY_STATIC_GUIDE")
        assert_eq(pkt.payload.facilityId, "PAD_BRAVO_01")
        assert_eq(pkt.payload.targetAircraft, "AIRCRAFT_01")
        assert_eq(pkt.payload.touchdownPoint.x, 1250.0)
        assert_eq(pkt.payload.safeDescentRate, 1.0)
        assert_false(pkt.payload.abortAlert)
    end)

    it("builds standard MSG_FACILITY_DYNAMIC_GUIDE (20Hz)", function()
        local streamer = tactical_streamer.create(cfg)
        local pos = { x = 840.25, y = 62.10, z = 1120.80 }
        local kin = {
            velocity = { vx = 6.2, vy = -0.15, vz = 1.1 },
            acceleration = { ax = 0.05, ay = 0.85, az = -0.02 },
            attitude = { pitch = 1.2, roll = -2.5, yaw = 85.0 },
            angularRates = { pitchRate = 0.4, rollRate = -0.8, yawRate = 0.05 }
        }
        local stab = {
            deckStatus = "STABLE",
            landingPermitted = true,
            tiltAngleDeg = 2.77,
            heaveRateMps = -0.15
        }
        local pkt = streamer:build_dynamic_guide(pos, "AIRCRAFT_01", kin, stab, false)
        assert_eq(pkt.type, "MSG_FACILITY_DYNAMIC_GUIDE")
        assert_eq(pkt.payload.deckStatus, "STABLE")
        assert_true(pkt.payload.landingPermitted)
        assert_eq(pkt.payload.velocity.vx, 6.2)
    end)

    it("builds MSG_ABORT_APPROACH and MSG_ATC_FACILITY_UPDATE", function()
        local streamer = tactical_streamer.create(cfg)
        local abortPkt = streamer:build_abort_approach("AIRCRAFT_01", "DECK_UNSTABLE")
        assert_eq(abortPkt.type, "MSG_ABORT_APPROACH")
        assert_eq(abortPkt.payload.reason, "DECK_UNSTABLE")
        assert_eq(abortPkt.payload.recommendedClimbAltitude, 100.0)

        local updatePkt = streamer:build_facility_update("FREE", nil)
        assert_eq(updatePkt.type, "MSG_ATC_FACILITY_UPDATE")
        assert_eq(updatePkt.payload.status, "FREE")
    end)
end)
```

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 0_infra/landing_pad`
Expected: FAIL (`module 'tactical_streamer' not found`)

- [ ] **Step 3: Implement minimal code**

Implement `src/0_infra/landing_pad/modules/tactical_streamer.lua`:
- Message builders adhering to ICD Sections 3.2, 3.3, 3.5:
  - `build_static_guide`
  - `build_dynamic_guide`
  - `build_abort_approach`
  - `build_slot_ack`
  - `build_facility_update`

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 0_infra/landing_pad`
Expected: PASS (`16/16 PASS`)

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/landing_pad/modules/tactical_streamer.lua tests/0_infra/landing_pad/test_tactical_streamer.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(landing_pad): implement tactical guidance packet streamer"
```

---

### Task 5: Landing Pad FSM & Local Backbone Network Protocol (`pad_fsm.lua`)

**Files:**
- Create: `src/0_infra/landing_pad/modules/pad_fsm.lua`
- Create: `tests/0_infra/landing_pad/test_pad_fsm.lua`

**Interfaces:**
- Consumes: `tactical_streamer`, `sensor_adapter`, `gps_client`
- Produces:
  - `pad_fsm.create(config: table, streamer: table) -> table`
  - `fsm:handle_slot_assign(packet: table) -> table` (slot_ack)
  - `fsm:handle_touchdown_complete(packet: table) -> table | nil` (facility_update to GAC)
  - `fsm:handle_gac_facility_update(packet: table) -> void`
  - `fsm:trigger_abort(reason: string) -> table, table` (abort_to_craft, update_to_gac)
  - `fsm:tick(nowSec: number, stability: table | nil) -> table` (list of outgoing messages)

- [ ] **Step 1: Write failing test**

```lua
-- tests/0_infra/landing_pad/test_pad_fsm.lua
local pad_fsm = require("pad_fsm")
local tactical_streamer = require("tactical_streamer")

describe("Landing pad FSM and local backbone protocols", function()
    local cfg = {
        facilityId = "PAD_BRAVO_01",
        mobility = "DYNAMIC",
        tacticalChannel = 50211,
        slotDurationSec = 120
    }

    it("handles MSG_ATC_SLOT_ASSIGN: transitions from IDLE to APPROACH and responds ACCEPTED", function()
        local streamer = tactical_streamer.create(cfg)
        local fsm = pad_fsm.create(cfg, streamer)
        assert_eq(fsm.status, "IDLE")

        local assignPkt = {
            type = "MSG_ATC_SLOT_ASSIGN",
            payload = { facilityId = "PAD_BRAVO_01", aircraftId = "AIRCRAFT_01", slotDurationSec = 120, tacticalChannel = 50211 }
        }
        local ack = fsm:handle_slot_assign(assignPkt)
        assert_eq(ack.type, "MSG_ATC_SLOT_ACK")
        assert_eq(ack.payload.status, "ACCEPTED")
        assert_eq(fsm.status, "APPROACH_DYNAMIC")
        assert_eq(fsm.targetCraft, "AIRCRAFT_01")
    end)

    it("handles MSG_TOUCHDOWN_COMPLETE: transitions to OCCUPIED and notifies GAC", function()
        local streamer = tactical_streamer.create(cfg)
        local fsm = pad_fsm.create(cfg, streamer)
        fsm:handle_slot_assign({ payload = { facilityId = "PAD_BRAVO_01", aircraftId = "AIRCRAFT_01" } })

        local tdPkt = {
            type = "MSG_TOUCHDOWN_COMPLETE",
            payload = { facilityId = "PAD_BRAVO_01", craftState = "GROUND_IDLE" }
        }
        local update = fsm:handle_touchdown_complete(tdPkt)
        assert_eq(fsm.status, "OCCUPIED")
        assert_not_nil(update)
        assert_eq(update.payload.status, "OCCUPIED")
    end)

    it("triggers GO_AROUND on 3.0s continuous DANGEROUS deck stability", function()
        local streamer = tactical_streamer.create(cfg)
        local fsm = pad_fsm.create(cfg, streamer)
        fsm:handle_slot_assign({ payload = { facilityId = "PAD_BRAVO_01", aircraftId = "AIRCRAFT_01" } })

        -- 1 second dangerous: no abort yet
        fsm:tick(10.0, { deckStatus = "DANGEROUS" })
        fsm:tick(11.0, { deckStatus = "DANGEROUS" })
        assert_eq(fsm.status, "APPROACH_DYNAMIC")

        -- 3.1 seconds dangerous: triggers GO_AROUND
        local msgs = fsm:tick(13.1, { deckStatus = "DANGEROUS" })
        assert_eq(fsm.status, "GO_AROUND")
        assert_true(#msgs >= 1)
        assert_eq(msgs[1].type, "MSG_ABORT_APPROACH")
    end)

    it("expires slot and resets to IDLE after 120s timeout", function()
        local streamer = tactical_streamer.create(cfg)
        local fsm = pad_fsm.create(cfg, streamer)
        fsm:handle_slot_assign({ payload = { facilityId = "PAD_BRAVO_01", aircraftId = "AIRCRAFT_01", slotDurationSec = 120 } })
        fsm.slotStartTime = 100.0

        local msgs = fsm:tick(221.0, { deckStatus = "STABLE" }) -- 121s elapsed
        assert_eq(fsm.status, "GO_AROUND")
        assert_eq(msgs[1].type, "MSG_ABORT_APPROACH")
    end)
end)
```

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 0_infra/landing_pad`
Expected: FAIL (`module 'pad_fsm' not found`)

- [ ] **Step 3: Implement minimal code**

Implement `src/0_infra/landing_pad/modules/pad_fsm.lua`:
- States: `INIT`, `IDLE`, `RESERVED`, `APPROACH_STATIC`, `APPROACH_DYNAMIC`, `OCCUPIED`, `GO_AROUND`, `MAINTENANCE`.
- Tracking: `targetCraft`, `slotStartTime`, `slotDurationSec`, `dangerousStartTime`.
- `tick(nowSec, stability)` checks:
  1. If `APPROACH_DYNAMIC` and `deckStatus == "DANGEROUS"`, increments dangerous timer; if $\ge 3.0\text{s}$, fires abort.
  2. If slot active and `nowSec - slotStartTime > slotDurationSec`, fires slot timeout abort.
  3. GAC `FREE` release via `handle_gac_facility_update`.

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 0_infra/landing_pad`
Expected: PASS (`20/20 PASS`)

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/landing_pad/modules/pad_fsm.lua tests/0_infra/landing_pad/test_pad_fsm.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(landing_pad): implement pad FSM and local backbone protocols"
```

---

### Task 6: 5-Stage Commissioning Wizard & 51x19 TUI View (`setup_wizard.lua`, `tui_view.lua`)

**Files:**
- Create: `src/0_infra/landing_pad/modules/setup_wizard.lua`
- Create: `src/0_infra/landing_pad/modules/tui_view.lua`
- Create: `tests/0_infra/landing_pad/test_setup_and_tui.lua`

**Interfaces:**
- Consumes: `term`, `colors`, `keys`, `config_store`, `sensor_adapter`, `offset_transform`
- Produces:
  - `setup_wizard.run_wizard(opts: table) -> table | nil`
  - `tui_view.create(termDev: table) -> table`
  - `tui:render_countdown(seconds: number, facilityId: string, mode: string) -> void`
  - `tui:render_daemon(state: table) -> void`
  - `tui:set_bottom_log(logMsg: string) -> void`

- [ ] **Step 1: Write failing test**

```lua
-- tests/0_infra/landing_pad/test_setup_and_tui.lua
local tui_view = require("tui_view")
local setup_wizard = require("setup_wizard")

describe("Landing pad 51x19 TUI and setup wizard", function()
    local mockTerm = {
        getSize = function() return 51, 19 end,
        clear = function() end,
        setCursorPos = function(x, y) end,
        setTextColor = function(c) end,
        setBackgroundColor = function(c) end,
        write = function(text) end
    }

    it("renders countdown screen within 51x19 terminal", function()
        local tui = tui_view.create(mockTerm)
        tui:render_countdown(2, "PAD_BRAVO_01", "DYNAMIC")
        -- Verified no boundary crashes or printError calls
    end)

    it("renders autonomous daemon screen with 1-line compact rolling log on Y=19", function()
        local tui = tui_view.create(mockTerm)
        tui:set_bottom_log("13:45:12 [TX] DYN_GUIDE seq=45120 -> AIRCRAFT_01")
        tui:render_daemon({
            facilityId = "PAD_BRAVO_01",
            mode = "DYNAMIC",
            sectorId = 1,
            tacticalChannel = 50211,
            status = "APPROACH_DYNAMIC",
            targetCraft = "AIRCRAFT_01",
            touchdownPoint = { x = 840.25, y = 62.10, z = 1120.80 },
            velocity = { vx = 6.2, vy = -0.15, vz = 1.1 },
            stability = { deckStatus = "STABLE", landingPermitted = true, tiltAngleDeg = 2.77, heaveRateMps = -0.15 }
        })
        assert_eq(tui.bottomLog, "13:45:12 [TX] DYN_GUIDE seq=45120 -> AIRCRAFT_01")
    end)

    it("setup wizard rejects DYNAMIC mode when sensors are missing (HALT_WITH_WARNING)", function()
        mock.peripheral_registry({
            top = { type = "modem", dev = mock.cc_modem({ isWireless = true }) }
        })
        local ok, err = setup_wizard.check_dynamic_prerequisites()
        assert_false(ok)
        assert_eq(err, "HALT_WITH_WARNING")
    end)
end)
```

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 0_infra/landing_pad`
Expected: FAIL (`module 'setup_wizard' not found`)

- [ ] **Step 3: Implement minimal code**

Implement `src/0_infra/landing_pad/modules/setup_wizard.lua` and `src/0_infra/landing_pad/modules/tui_view.lua`:
- `tui_view`:
  - `render_countdown`: 51x19 layout matching ASCII Wireframe 1).
  - `render_daemon`: 51x19 layout matching ASCII Wireframe 5). Line 19 contains `bottomLog`.
  - Color palette: `colors.blue`, `colors.cyan`, `colors.green`, `colors.yellow`, `colors.red`.
- `setup_wizard`:
  - Step 1: Modem validation, sector $S$, pad $Idx$, $facilityId$.
  - Step 2: Mode selection (`STATIC` vs `DYNAMIC`).
  - Step 3: Sensor check (`HALT_WITH_WARNING` if DYNAMIC lacks sensors).
  - Step 4: Body offset (`fwd`, `right`, `up`) and live preview.
  - Step 5: Summary, `[Y/N]` confirmation, atomic save to `/landing_pad/config.json`.

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 0_infra/landing_pad`
Expected: PASS (`23/23 PASS`)

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/landing_pad/modules/setup_wizard.lua src/0_infra/landing_pad/modules/tui_view.lua tests/0_infra/landing_pad/test_setup_and_tui.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(landing_pad): implement commissioning wizard and 51x19 TUI view"
```

---

### Task 7: Main Daemon Entrypoint & 20Hz Non-blocking Loop (`main.lua`, `config.lua`)

**Files:**
- Create: `src/0_infra/landing_pad/config.lua`
- Create: `src/0_infra/landing_pad/main.lua`
- Create: `tests/0_infra/landing_pad/test_main_integration.lua`

**Interfaces:**
- Consumes: all landing pad modules, `peripheral`, `os.pullEventRaw`
- Produces: Standalone CC:Tweaked executable with boot countdown and daemon

- [ ] **Step 1: Write failing test**

```lua
-- tests/0_infra/landing_pad/test_main_integration.lua
local config_store = require("config_store")
local offset_transform = require("offset_transform")
local tactical_streamer = require("tactical_streamer")
local pad_fsm = require("pad_fsm")

describe("Landing pad main daemon integration smoke test", function()
    it("wires modules and computes pad coordinates and guidance packets cleanly", function()
        local cfg = config_store.get_default_config()
        local streamer = tactical_streamer.create(cfg)
        local fsm = pad_fsm.create(cfg, streamer)

        -- Coordinate transform check
        local compPos = { x = 840.0, y = 62.0, z = 1120.0 }
        local padPos = offset_transform.calculate_pad_position(compPos, 85.0, cfg.mountingYawOffset, cfg.bodyOffset)
        assert_not_nil(padPos.x)
        assert_not_nil(padPos.y)

        -- Approach & guidance packet flow
        fsm:handle_slot_assign({ payload = { facilityId = cfg.facilityId, aircraftId = "AIRCRAFT_01" } })
        assert_eq(fsm.status, "APPROACH_DYNAMIC")

        local pkt = streamer:build_static_guide(padPos, "AIRCRAFT_01", false)
        assert_eq(pkt.type, "MSG_FACILITY_STATIC_GUIDE")
    end)

    it("verifies config.lua exports default configuration", function()
        local cfg = require("config")
        assert_eq(type(cfg), "table")
        assert_eq(cfg.version, "2.4.0")
        assert_eq(cfg.facilityId, "PAD_BRAVO_01")
    end)
end)
```

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 0_infra/landing_pad`
Expected: FAIL (`module 'config' not found`)

- [ ] **Step 3: Implement minimal code**

Implement `src/0_infra/landing_pad/config.lua` and `src/0_infra/landing_pad/main.lua`:
- `config.lua`: returns `config_store.get_default_config()`.
- `main.lua`:
  1. Boot check: `/landing_pad/config.json`. If missing, runs `setup_wizard.run_wizard()`.
  2. If config exists, runs 3-second countdown (`render_countdown`). If `[S]` pressed, enters wizard; if `[D]` or 3s timeout, starts daemon.
  3. Opens channels: $Base_{\text{sec}}+1$ (Backbone), $Base_{\text{sec}}+5$ (GPS Reply), $Base_{\text{sec}}+10+Idx$ (Tactical).
  4. 20Hz non-blocking event loop intercepting `timer`, `modem_message`, `key`, `terminate`.
  5. Broadcasts 1Hz static guide or 20Hz dynamic guide with live telemetry.
  6. Updates 1-line log on line 19 and renders daemon TUI.
  7. On exit: closes modem channels and clears terminal.

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 0_infra/landing_pad`
Expected: PASS (`25/25 PASS`)

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/landing_pad/config.lua src/0_infra/landing_pad/main.lua tests/0_infra/landing_pad/test_main_integration.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(landing_pad): implement main daemon entrypoint and non-blocking loop"
```

---

### Task 8: Unified Installer Manifest Registration & Full Suite Verification

**Files:**
- Modify: `src/0_development/installer/modules/manifest.lua`
- Modify: `tests/0_development/installer/test_manifest_and_registry.lua`
- Modify: `tests/0_development/installer/test_installer_tui_and_app.lua`
- Modify: `tools/verify_spec_status.py`
- Modify: `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md`
- Modify: `TASK.md`
- Modify: `GEMINI.md`

**Interfaces:**
- Consumes: `tools/run_unit_tests.py`, `tools/validate_lua_syntax.py`, `tools/verify_all_specs.py`, `tools/verify_spec_status.py`
- Produces: Landing pad registered in installer, spec promoted to `Implemented`, TASK.md and GEMINI.md updated

- [ ] **Step 1: Register landing_pad in Unified Installer manifest**

Add `landing_pad` to `manifest.MODULE_ORDER` and `manifest.MODULES`:
- id: `"landing_pad"`, name: `"Landing Pad"`, category: `"infra"`, version: `"2.4.0"`
- files: `main.lua`, `config.lua`, `modules/config_store.lua`, `modules/offset_transform.lua`, `modules/sensor_adapter.lua`, `modules/gps_client.lua`, `modules/tactical_streamer.lua`, `modules/pad_fsm.lua`, `modules/tui_view.lua`, `modules/setup_wizard.lua`, `/lib/avionics_sensors.lua`.
- Update `test_manifest_and_registry.lua` and `test_installer_tui_and_app.lua` module counts (10 modules).

- [ ] **Step 2: Run all unit tests**

Run: `python tools/run_unit_tests.py --require-tests --clean-orphans`
Expected: PASS on all 10 targets (~135+ tests passing).

- [ ] **Step 3: Run harness regression tests**

Run: `python -m unittest discover -s tests/harness -p "test_*.py"`
Expected: PASS (`24/24 PASS`).

- [ ] **Step 4: Promote Landing Pad Specification to `Implemented`**

Update `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md`:
- `문서 상태 (Status)`: `Approved` $\to$ `Implemented`
- `최종 수정일 (Date)`: `2026-11-08`

Update `tools/verify_spec_status.py`:
- Move `LANDING_PAD_SPECIFICATION_AND_ICD.md` from `TARGET_APPROVED` to `TARGET_IMPLEMENTED` (7 Implemented, 5 Approved).

Run: `python tools/validate_lua_syntax.py`  
Run: `python tools/verify_all_specs.py`  
Run: `python tools/verify_spec_status.py`  
Expected: All 100% CLEAN.

- [ ] **Step 5: Update TASK.md, GEMINI.md & Commit**

Update `TASK.md`:
- Mark `TASK-102` as complete `[x]`, move to `## 3. 완료된 작업 이력`.
- Set next active immediate task to `TASK-112: VAS/FCP 센서 표준 라이브러리(avionics_sensors) 연동 및 잔재 정리`.
Update `GEMINI.md`:
- Current Phase handover notes.

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/installer/modules/manifest.lua tests/0_development/installer/ docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md tools/verify_spec_status.py TASK.md GEMINI.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(landing_pad): register landing_pad in manifest, promote spec to Implemented, and complete TASK-102"
```
