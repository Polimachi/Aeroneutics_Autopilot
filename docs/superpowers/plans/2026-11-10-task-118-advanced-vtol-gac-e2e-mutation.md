# TASK-118: ADVANCED_VTOL & GAC Dedicated/Emergency E2E Simulation and Mutation Testing Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the multi-node E2E simulation suite (`tests/e2e/`) and mutation testing runner (`tools/run_mutation_tests.py`) to verify `ADVANCED_VTOL` 2D gimbaled vector propulsion (hangar gimbal pulse calibration, $B^\dagger$ profile sync, 6-DoF closed-loop guidance, nozzle fail-safe) and GAC dedicated facility isolation (`FACILITY_DEDICATED` rejection and last-resort `EMERGENCY` commandeering).

**Architecture:**
1. **TCA Gimbal Calibration Pulse Forwarding & Scenario 7 E2E (`TASK-118-1`)**: Fixes `tca_daemon.handle_calib_pulse` and `watchdog_sentinel.handle_pulse` to preserve 2D nozzle deflections (`gimbalX`, `gimbalY`) from `MSG_CALIB_PULSE`, and adds `tests/e2e/test_e2e_advanced_vtol_flight.lua` running `Alignment`, `FCP`, `VAS`, and `TCA` across `virtual_bus`.
2. **Scenario 6 Dedicated & Emergency Landing E2E Expansion (`TASK-118-2`)**: Extends `tests/e2e/test_e2e_facility_landing.lua` with a multi-pad sector (`PAD_PUB_01` public + `PAD_VIP_02` dedicated) verifying public-only beacon counts, public-first routing, `FACILITY_DEDICATED` rejection on Tier-1 handoff and Tier-2 check-in, and `isEmergency = true` last-resort dedicated pad commandeering.
3. **Mutation Testing Suite Expansion (`TASK-118-3`)**: Adds 5 deterministic mutants (`MUT-21` through `MUT-25`, expanding from 20 to 25 total mutants) targeting `VAS` pseudo-inverse matrix allocation, `TCA` fail-safe nozzle centering, `FCP` `advanced_vtol_driver` PID surge sign, and `GAC` `FACILITY_DEDICATED` / emergency commandeering guards.

**Tech Stack:** CC:Tweaked Lua 5.2 (Cobalt VM), CraftOS-PC Headless Runner (`tools/run_unit_tests.py`, `tools/run_e2e_tests.py`), Multi-Node Virtual RF Bus (`harness/simulation/virtual_bus.lua`, `harness/simulation/node_sandbox.lua`), Python 3.12 Mutation Runner (`tools/run_mutation_tests.py`).

**Spec:**
- [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md) (v1.25.0 `Implemented`)
- [ALIGNMENT_PROGRAM_SPECIFICATION.md](../../specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md) (v2.6.0 `Implemented`)
- [VAS_PROGRAM_SPECIFICATION.md](../../specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md) (v1.18.0 `Implemented`)
- [TCA_PROGRAM_SPECIFICATION.md](../../specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md) (v1.11.0 `Implemented`)
- [FCP_PROGRAM_SPECIFICATION.md](../../specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md) (v1.15.0 `Implemented`)
- [GAC_PROGRAM_SPECIFICATION_AND_ICD.md](../../specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md) (v1.4.1 `Implemented`)

## Global Constraints

- **Mod Ban & Peripheral Allowlist**: Zero Valkyrien Skies (`ship`, `vs2`, `kontraption:`) references. Vector propulsion exclusively uses `Create Propulsion: Simulated` `vector_thruster` peripheral API (`setPower`, `setVector`, `getVectorX`, `getVectorY`).
- **UAFS Envelope v1.9.5 & Zero-Fallback**: All RF packets use `ver = "1.9.5"`, `domainId`, `seq`, `type`, `time`, `payload` with canonical field names (`outputs[groupId] = { thrust, gimbalX, gimbalY }`, `appliedGimbal`, `gimbalSaturated`, `dedicatedCraftIds`, `dedicatedAirframeTypes`, `preferredFacilityId`, `isEmergency`, `reason`, `rejectReason`).
- **RF Spectrum & 40-Channel Allocation**: Craft $Base = 10000 + (N-1)\times 40$ (`10000` C2, `10001` Guidance, `10002` Telemetry, `10003` MFD, `10010` TCA, `10011` ASA); Hangar Bay 1 (`101` CMD, `102` TELEM, `104` TAP); GAC (`50003` Beacon, `50201` Check-in/Clearance, `50202` Facility Backbone, `50211`/`50212` Tactical Guidance).
- **Non-Aerodynamic `ADVANCED_VTOL` Invariant**: `flapTarget` is fixed at `0.0` across all flight phases, and VAS must emit zero `MSG_SURFACE_CMD` / `MSG_AERO_CMD` packets on `Base+11` (`10011`).
- **No Spec Status Churn**: All target specifications are already `Implemented` (`TASK-114`, `TASK-115`) and require zero schema or metadata changes.

## Review Focus

1. **TCA Calibration Pulse Dropping 2D Gimbal Deflections (`MSG_CALIB_PULSE`)**: When Alignment transmits a `GIMBAL_X` or `GIMBAL_Y` calibration pulse (`pulseLevel = 8, gimbalX = -0.5, gimbalY = 0.0`) on `CH 101`, `tca_daemon:handle_calib_pulse` and `watchdog_sentinel:handle_pulse` must forward the polymorphic `{ thrust, gimbalX, gimbalY }` table to `actuator_adapter.apply_thrust` so the physical `vector_thruster` deflects to `(-0.5, 0.0)` instead of remaining at `(0.0, 0.0)`.
2. **`ADVANCED_VTOL` Spurious Aerodynamic Actuation (`Base+11`)**: During `ADVANCED_VTOL` closed-loop flight, FCP must keep `flapTarget == 0.0` in `MSG_ATTITUDE_CMD` (`Base+1`), and VAS must emit polymorphic `{ thrust, gimbalX, gimbalY }` outputs on `Base+10` while transmitting zero packets on `Base+11`.
3. **TCA Vector Thruster `E_STOP` / Watchdog Non-Zero Nozzle Lock**: When `controlState = "E_STOP"` or watchdog expiration occurs while a `vector_thruster` holds non-zero gimbal deflection, TCA must cut power to `0` AND center nozzle gimbals to `(0.0, 0.0)` (`appliedGimbal = { x = 0.0, y = 0.0 }`, `gimbalSaturated = false`).
4. **GAC Sector Beacon Leaking Dedicated Pads & Unprivileged `preferredFacilityId` Bypass**: When a sector has 1 `FREE` public pad and 1 `FREE` dedicated pad (`dedicatedCraftIds = { "VIP_VTOL_01" }`), `MSG_FACILITY_BEACON` must advertise `totalLandingPads = 2` and `freeLandingPads = 1`; once the public pad is `OCCUPIED`, an unprivileged aircraft requesting check-in (even with `preferredFacilityId = "PAD_VIP_02"`) must be rejected with `status = "DENIED"`, `reason = "FACILITY_DEDICATED"`.
5. **Emergency Aircraft Prematurely Commandeering Dedicated Pad While Public Pad is `FREE`**: An aircraft with `isEmergency = true` checking in while both a public pad and a closer dedicated pad are `FREE` must be allocated the public pad first, commandeering the dedicated pad only when zero compatible public pads remain `FREE`.

---

## File Structure

- Modify: `src/1_control/tca/modules/tca_daemon.lua:51-58` — Forward `{ thrust = p.pulseLevel, gimbalX = p.gimbalX, gimbalY = p.gimbalY }` in `handle_calib_pulse` when `gimbalX` or `gimbalY` is present in `MSG_CALIB_PULSE`.
- Modify: `src/1_control/tca/modules/watchdog_sentinel.lua:85-101` — Accept polymorphic `pulseLevel` (`number | { thrust, gimbalX, gimbalY }`) in `handle_pulse` and pass it to `actuator_adapter.apply_thrust`.
- Modify: `tests/1_control/tca/test_tca_vector_thruster.lua` — Pin unit test for `tca_daemon:handle_calib_pulse` applying 2D gimbal deflections during calibration pulses.
- Create: `tests/e2e/test_e2e_advanced_vtol_flight.lua` — Scenario 7 multi-node E2E test covering hangar vector calibration, $B^\dagger$ profile sync, FCP/VAS/TCA 6-DoF closed-loop flight, gimbal saturation anti-windup, and `E_STOP` nozzle centering.
- Modify: `tests/e2e/test_e2e_facility_landing.lua` — Expand Scenario 6 E2E test with dedicated pad beacon isolation, public-first allocation, `FACILITY_DEDICATED` rejection, and `EMERGENCY` dedicated pad commandeering.
- Modify: `tools/run_mutation_tests.py` — Add `MUT-21` through `MUT-25` covering `ADVANCED_VTOL` mixer/driver/actuator and `GAC` dedicated/emergency allocation logic.
- Modify: `README.md`, `GEMINI.md`, `TASK.md` — Sync E2E suite count (7 suites, 8 cases), unit test count (309), and mutation count (25/25 KILLED) upon completion.

---

### Task 1: TCA Gimbal Calibration Pulse Forwarding & Scenario 7 `ADVANCED_VTOL` E2E Simulation (`TASK-118-1`)

**Files:**
- Modify: `src/1_control/tca/modules/tca_daemon.lua:51-58`
- Modify: `src/1_control/tca/modules/watchdog_sentinel.lua:85-101`
- Modify: `tests/1_control/tca/test_tca_vector_thruster.lua:232-278`
- Create: `tests/e2e/test_e2e_advanced_vtol_flight.lua`

**Interfaces:**
- Consumes:
  - `multi_pulse_sequencer.new(domainId):start_vector_thruster(groupId)` / `build_pulse_packet(seq)` (`src/0_development/alignment/modules/multi_pulse_sequencer.lua`)
  - `ols_regression_engine.compute_vector_slopes(pulseResults)` (`src/0_development/alignment/modules/ols_regression_engine.lua`)
  - `profile_exporter.compute_pseudo_inverse(B)` / `build_sync_packet(domainId, seq, profile)` (`src/0_development/alignment/modules/profile_exporter.lua`)
  - `controllability_checker.evaluate(coeffs, airframeType, surfaces, opts, B_dagger, B)` (`src/0_development/alignment/modules/controllability_checker.lua`)
  - `guidance_controller.init(cfg)` / `compute(state, nav, target, fsm_ctx, dt)` (`src/2_guidance/fcp/modules/guidance_controller.lua`)
  - `actuator_adapter_tca.init(profile)` / `allocate(state, wrench)` / `reload_coefficients(state, profile, isFallback)` (`src/1_control/vas/modules/actuator_adapter_tca.lua`)
- Produces:
  - `watchdog_sentinel.handle_pulse(wd: table, pulseLevel: number | table, durationMs: number, adapterState: table) -> boolean`
  - `tca_daemon:handle_calib_pulse(pkt: table) -> boolean` (applies `{ thrust, gimbalX, gimbalY }` when `pkt.payload.gimbalX` or `pkt.payload.gimbalY` is present)
  - `tests/e2e/test_e2e_advanced_vtol_flight.lua` (Scenario 7 E2E suite)

- [ ] **Step 1: Write the failing unit test in `tests/1_control/tca/test_tca_vector_thruster.lua` and create `tests/e2e/test_e2e_advanced_vtol_flight.lua`**

Append to `tests/1_control/tca/test_tca_vector_thruster.lua` inside `describe("tca vector thruster discovery and status reporting", ...)`:

```lua
    it("applies 2D gimbal deflections during calibration pulse in tca_daemon", function()
        local mockDev = create_mock_vector_thruster()
        mock.peripheral_registry({
            left = { type = "vector_thruster", dev = mockDev }
        })

        local mockModem = mock.modem()
        local cfg = {
            groupId = "THR_VEC_1",
            aircraftDomainId = "AIRCRAFT_01",
            aircraftIndexN = 1,
            baseChannel = 10000,
            channels = { thrustActuation = 10010 },
            watchdogTimeoutMs = 300,
            nominalActuatorCount = 1,
            interactionMode = "API",
            ports = { modemSide = "top", redstoneSide = "bottom", apiSides = { "left" } }
        }

        local daemon = tca_daemon.init(cfg, mockModem)
        daemon.lastControlState = "CALIBRATION"

        local pulsePkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 14,
            type = "MSG_CALIB_PULSE",
            payload = {
                targetThrusterId = "THR_VEC_1",
                stepIndex = 4,
                phase = "GIMBAL_X",
                pulseLevel = 8,
                gimbalX = -0.5,
                gimbalY = 0.25,
                pulseDurationMs = 300
            }
        }

        local ok = daemon:handle_calib_pulse(pulsePkt)
        assert_true(ok)
        assert_eq(mockDev._power, 8)
        assert_near(mockDev._vectorX, -0.5, 1e-6)
        assert_near(mockDev._vectorY, 0.25, 1e-6)
    end)
```

Create `tests/e2e/test_e2e_advanced_vtol_flight.lua`:

```lua
-- tests/e2e/test_e2e_advanced_vtol_flight.lua
-- Scenario 7: Hangar 2D Gimbal Pulse Calibration -> FCP/VAS/TCA ADVANCED_VTOL 6-DoF Closed-Loop Flight
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

local B_6x12 = {
    -- T1, gx1, gy1,  T2, gx2, gy2,  T3, gx3, gy3,  T4, gx4, gy4
    { 0,   0,   8,    0,   0,   8,    0,   0,   8,    0,   0,   8 }, -- surge
    { 0,   8,   0,    0,   8,   0,    0,   8,   0,    0,   8,   0 }, -- sway
    { 1,   0,   0,    1,   0,   0,    1,   0,   0,    1,   0,   0 }, -- heave
    {-1,   0,   0,   -1,   0,   0,    1,   0,   0,    1,   0,   0 }, -- pitch
    { 1,   0,   0,   -1,   0,   0,    1,   0,   0,   -1,   0,   0 }, -- roll
    { 0,   2,  -2,    0,   2,   2,    0,  -2,  -2,    0,  -2,   2 }  -- yaw
}

describe("Scenario 7: ADVANCED_VTOL Gimbal Calibration & 6-DoF Closed-Loop Flight", function()
    it("completes gimbal X/Y pulse calibration, B_dagger profile sync, 6-DoF vector flight, saturation anti-windup, and E_STOP nozzle neutralization", function()
        local bus = virtual_bus.create_bus({ clock = 1000.0 })

        local align = node_sandbox.create_node(bus, "ALIGN", "src/0_development/alignment")
        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
        local tca = node_sandbox.create_node(bus, "TCA_VEC_1", "src/1_control/tca")

        -- 1. Attach mock vector_thruster peripheral to TCA_VEC_1 sandbox
        local vec_hw = {
            _power = 0,
            _vectorX = 0.5, -- non-zero pre-boot state to verify cold-boot centering
            _vectorY = -0.5,
        }
        function vec_hw.setPower(p) vec_hw._power = tonumber(p) or 0 end
        function vec_hw.setVector(x, y)
            vec_hw._vectorX = tonumber(x) or 0.0
            vec_hw._vectorY = tonumber(y) or 0.0
        end
        function vec_hw.getVectorX() return vec_hw._vectorX end
        function vec_hw.getVectorY() return vec_hw._vectorY end
        function vec_hw.getPower() return vec_hw._power end

        local orig_periph = tca.env.peripheral
        tca.env.peripheral = {
            getNames = function() return { "top", "left" } end,
            isPresent = function(s) return s == "top" or s == "left" end,
            getType = function(s)
                if s == "left" then return "vector_thruster" end
                return orig_periph.getType(s)
            end,
            wrap = function(s)
                if s == "left" then return vec_hw end
                return orig_periph.wrap(s)
            end,
            find = orig_periph.find,
            call = orig_periph.call,
        }

        local tca_daemon_mod = tca:require("tca_daemon")
        local tca_cfg = {
            groupId = "THR_VEC_1",
            aircraftDomainId = "AIRCRAFT_01",
            aircraftIndexN = 1,
            baseChannel = 10000,
            channels = { thrustActuation = 10010 },
            watchdogTimeoutMs = 300,
            nominalActuatorCount = 1,
            interactionMode = "API",
            ports = { modemSide = "top", redstoneSide = "bottom", apiSides = { "left" } }
        }
        local tca_inst = tca_daemon_mod.init(tca_cfg, tca.modem)
        tca.modem:open(10010)

        -- Cold-boot neutral centering check
        assert_true(tca_inst.adapterState.isVectorCapable)
        assert_near(vec_hw._vectorX, 0.0, 1e-6)
        assert_near(vec_hw._vectorY, 0.0, 1e-6)

        -- 2. Initialize VAS with network_manager, state_machine, vehicle_policy, and actuator_adapter_tca
        local vas_net = vas:require("network_manager")
        local vas_fsm_mod = vas:require("state_machine")
        local vas_policy_mod = vas:require("vehicle_policy")
        local vas_tca_mod = vas:require("actuator_adapter_tca")

        local vas_state = vas_net.init({
            aircraftDomainId = "AIRCRAFT_01",
            baseChannel = 10000,
        })
        vas_state.wirelessModem = vas.modem
        local vas_fsm = vas_fsm_mod.init({}, true)
        local vas_policy = vas_policy_mod.init({ vehicleType = "ADVANCED_VTOL" })
        local vas_tca = vas_tca_mod.init({
            airframeType = "ADVANCED_VTOL",
            isVectorVtol = true,
            vectorGroupOrder = { "THR_VEC_1", "THR_VEC_2", "THR_VEC_3", "THR_VEC_4" }
        })

        vas.modem:open(10000)
        vas.modem:open(10001)
        vas.modem:open(10010)
        align.modem:open(101)
        align.modem:open(102)
        align.modem:open(104)

        -- 3. Stage 1: Hangar Calibration Init & Bay Bind (Bay 1: 101/102/104)
        align.modem:transmit(10000, 102, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 1,
            type = "MSG_CALIBRATION_INIT",
            time = 1000,
            payload = {
                bayId = 1,
                stationId = "ALIGN_BAY_01",
                baseHangarChannel = 101,
                targetCraftDomain = "AIRCRAFT_01",
            }
        })
        bus:step(0.05)

        local vas_init_in = vas.modem:drain()
        assert_eq(#vas_init_in, 1)
        assert_true(vas_net.dispatch(vas_state, vas_fsm, nil, vas_tca, 10000, vas_init_in[1].replyChannel, vas_init_in[1].payload))
        assert_eq(vas_fsm.currentState, "CALIBRATION")
        bus:step(0.05)

        -- TCA processes MSG_CALIB_BAY_BIND (OPEN) on 10010
        local tca_bind_in = tca.modem:drain()
        assert_eq(#tca_bind_in, 1)
        assert_eq(tca_bind_in[1].payload.type, "MSG_CALIB_BAY_BIND")
        assert_true(tca_inst:dispatch_modem_message(10010, 10010, tca_bind_in[1].payload))
        assert_true(tca.modem:isOpen(101))
        assert_true(tca.modem:isOpen(104))

        -- 4. Stage 2: Vector Actuator Discovery on 104
        local discovery_client = align:require("discovery_client")
        local disc_client = discovery_client.new("AIRCRAFT_01")

        align.modem:drain() -- clear init ack
        align.modem:transmit(104, 104, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 2,
            type = "MSG_ACTUATOR_DISCOVER_REQ",
            time = 1010,
            payload = { targetGroup = "ALL" }
        })
        bus:step(0.05)

        local tca_disc_in = tca.modem:drain()
        assert_eq(#tca_disc_in, 1)
        assert_true(tca_inst:dispatch_modem_message(104, 104, tca_disc_in[1].payload))
        bus:step(0.05)

        local align_disc_in = align.modem:drain()
        assert_eq(#align_disc_in, 1)
        assert_eq(align_disc_in[1].payload.type, "MSG_ACTUATOR_DISCOVER_ACK")
        assert_true(disc_client:process_ack(align_disc_in[1].payload))
        assert_true(disc_client:is_vector_capable("THR_VEC_1"))

        -- 5. Stage 3: Multi-Pulse Gimbal Calibration (THROTTLE, GIMBAL_X, GIMBAL_Y) on 101
        local multi_pulse_sequencer = align:require("multi_pulse_sequencer")
        local ols_engine = align:require("ols_regression_engine")
        local profile_exporter = align:require("profile_exporter")
        local controllability_checker = align:require("controllability_checker")

        local seq = multi_pulse_sequencer.new("AIRCRAFT_01")
        seq:start_vector_thruster("THR_VEC_1")

        -- Step 1: THROTTLE (level 5, gx=0, gy=0)
        local p_thr = seq:build_pulse_packet(10)
        align.modem:transmit(101, 102, p_thr)
        bus:step(0.05)
        local tca_p1 = tca.modem:drain()
        assert_eq(#tca_p1, 1)
        assert_true(tca_inst:dispatch_modem_message(101, 102, tca_p1[1].payload))
        assert_eq(vec_hw._power, 5)
        assert_near(vec_hw._vectorX, 0.0, 1e-6)
        assert_near(vec_hw._vectorY, 0.0, 1e-6)

        -- Advance to Step 4: GIMBAL_X (level 8, gx=-0.5, gy=0)
        for _ = 1, 3 do seq:next_step() end
        local p_gx = seq:build_pulse_packet(11)
        assert_eq(p_gx.payload.phase, "GIMBAL_X")
        align.modem:transmit(101, 102, p_gx)
        bus:step(0.05)
        local tca_p4 = tca.modem:drain()
        assert_eq(#tca_p4, 1)
        assert_true(tca_inst:dispatch_modem_message(101, 102, tca_p4[1].payload))
        assert_eq(vec_hw._power, 8)
        assert_near(vec_hw._vectorX, -0.5, 1e-6)
        assert_near(vec_hw._vectorY, 0.0, 1e-6)

        -- Advance to Step 7: GIMBAL_Y (level 8, gx=0, gy=-0.5)
        for _ = 1, 3 do seq:next_step() end
        local p_gy = seq:build_pulse_packet(12)
        assert_eq(p_gy.payload.phase, "GIMBAL_Y")
        align.modem:transmit(101, 102, p_gy)
        bus:step(0.05)
        local tca_p7 = tca.modem:drain()
        assert_eq(#tca_p7, 1)
        assert_true(tca_inst:dispatch_modem_message(101, 102, tca_p7[1].payload))
        assert_eq(vec_hw._power, 8)
        assert_near(vec_hw._vectorX, 0.0, 1e-6)
        assert_near(vec_hw._vectorY, -0.5, 1e-6)

        -- 6. Stage 4: Compute OLS Vector Slopes, Moore-Penrose B_dagger & Sync Profile
        local slopes = ols_engine.compute_vector_slopes({
            throttle = {
                signals = { 5, 10, 15 },
                impulses = {
                    { surge = 0, sway = 0, heave = 5, pitch = -5, roll = 5, yaw = 0 },
                    { surge = 0, sway = 0, heave = 10, pitch = -10, roll = 10, yaw = 0 },
                    { surge = 0, sway = 0, heave = 15, pitch = -15, roll = 15, yaw = 0 },
                }
            },
            gimbalX = {
                signals = { -0.5, 0.5, 1.0 },
                impulses = {
                    { surge = 0, sway = -4, heave = 8, pitch = 0, roll = 0, yaw = -1 },
                    { surge = 0, sway = 4, heave = 8, pitch = 0, roll = 0, yaw = 1 },
                    { surge = 0, sway = 8, heave = 8, pitch = 0, roll = 0, yaw = 2 },
                }
            },
            gimbalY = {
                signals = { -0.5, 0.5, 1.0 },
                impulses = {
                    { surge = -4, sway = 0, heave = 8, pitch = 0, roll = 0, yaw = 1 },
                    { surge = 4, sway = 0, heave = 8, pitch = 0, roll = 0, yaw = -1 },
                    { surge = 8, sway = 0, heave = 8, pitch = 0, roll = 0, yaw = -2 },
                }
            }
        })
        assert_near(slopes.dThrust.heave, 1.0, 1e-4)
        assert_near(slopes.dGimbalX.sway, 8.0, 1e-4)
        assert_near(slopes.dGimbalY.surge, 8.0, 1e-4)

        local B_dagger = profile_exporter.compute_pseudo_inverse(B_6x12)
        assert_not_nil(B_dagger)
        local eval = controllability_checker.evaluate({}, "ADVANCED_VTOL", {}, nil, B_dagger, B_6x12)
        assert_eq(eval.status, "FULL_6DOF_PASS")

        local sync_pkt = profile_exporter.build_sync_packet("AIRCRAFT_01", 20, {
            profileId = "PROF_ADV_VTOL_01",
            airframeType = "ADVANCED_VTOL",
            isVectorVtol = true,
            controllabilityStatus = eval.status,
            controlEffectivenessMatrix = B_6x12,
            pseudoInverseMatrix = B_dagger,
            vectorGroupOrder = { "THR_VEC_1", "THR_VEC_2", "THR_VEC_3", "THR_VEC_4" },
        })

        vas.modem:drain() -- clear intermediate pulse packets on 101
        align.modem:transmit(101, 102, sync_pkt)
        bus:step(0.05)

        local vas_sync_in = vas.modem:drain()
        assert_eq(#vas_sync_in, 1)
        assert_true(vas_net.dispatch(vas_state, vas_fsm, nil, vas_tca, 101, vas_sync_in[1].replyChannel, vas_sync_in[1].payload))
        assert_eq(vas_fsm.currentState, "IDLE_ARMED")
        assert_not_nil(vas_tca.pseudoInverseMatrix)
        bus:step(0.05)

        local calib_acks = bus:find_packets({ type = "MSG_CALIB_ACK", channel = 102 })
        assert_eq(#calib_acks, 1)
        assert_eq(calib_acks[1].payload.payload.profileId, "PROF_ADV_VTOL_01")

        -- Close calibration session
        align.modem:transmit(101, 102, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 21,
            type = "MSG_CALIBRATION_CLOSE",
            time = 1060,
            payload = { bayId = 1, action = "CLOSE_SESSION", reason = "COMPLETE" }
        })
        bus:step(0.05)
        local vas_close_in = vas.modem:drain()
        assert_eq(#vas_close_in, 1)
        assert_true(vas_net.dispatch(vas_state, vas_fsm, nil, vas_tca, 101, vas_close_in[1].replyChannel, vas_close_in[1].payload))
        assert_false(vas.modem:isOpen(101))
        bus:step(0.05)

        local tca_close_in = tca.modem:drain()
        assert_eq(#tca_close_in, 1)
        assert_true(tca_inst:dispatch_modem_message(10010, 10010, tca_close_in[1].payload))
        assert_false(tca.modem:isOpen(101))
        assert_false(tca.modem:isOpen(104))

        -- 7. Stage 5: FCP -> VAS -> TCA Closed-Loop Flight (TAKEOFF -> CRUISE)
        local fcp_main = fcp:require("main")
        local fcp_cfg = fcp_main.load_config()
        fcp_cfg.system.airframeType = "ADVANCED_VTOL"
        fcp_cfg.system.domainId = "AIRCRAFT_01"

        local fcp_fsm_mod = fcp:require("flight_fsm")
        local guidance_controller = fcp:require("guidance_controller")
        local fcp_fsm = fcp_fsm_mod.init(fcp_cfg)
        local fcp_guid = guidance_controller.init(fcp_cfg)

        assert_true(fcp_fsm_mod.transition_to(fcp_fsm, "IDLE_ARMED"))
        assert_true(fcp_fsm_mod.transition_to(fcp_fsm, "TAKEOFF"))

        -- 7a. TAKEOFF below 15m clearance blocks horizontal surge/sway
        local nav_takeoff = {
            pos = { x = 0.0, y = 70.0, z = 0.0 },
            vel = { x = 0.0, y = 1.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        fcp_guid.driver_state.takeoff_origin_y = 64.0
        local target_wp = { x = 10.0, y = 85.0, z = -25.0 }
        local tk_cmd = guidance_controller.compute(fcp_guid, nav_takeoff, target_wp, {
            state = "TAKEOFF", flightActive = true, now_ms = 1100
        }, 0.05)
        assert_not_nil(tk_cmd)
        assert_eq(tk_cmd.mode, "ADVANCED_VTOL")
        assert_eq(tk_cmd.flapTarget, 0.0)
        assert_eq(tk_cmd.translationBias.surge, 0.0)
        assert_eq(tk_cmd.translationBias.sway, 0.0)
        assert_eq(tk_cmd.targetClimbRate, 2.5)

        -- 7b. CRUISE above clearance computes 3-axis translationBias with STRICT_LEVEL attitude
        assert_true(fcp_fsm_mod.transition_to(fcp_fsm, "CRUISE"))
        local nav_cruise = {
            pos = { x = 0.0, y = 80.0, z = 0.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = 0.0 },
            groundSpeed = 0.0,
        }
        local cr_cmd = guidance_controller.compute(fcp_guid, nav_cruise, target_wp, {
            state = "CRUISE", flightActive = true, now_ms = 1150
        }, 0.05)
        assert_not_nil(cr_cmd)
        assert_eq(cr_cmd.flapTarget, 0.0)
        assert_eq(cr_cmd.angleTargets.pitch, 0.0)
        assert_eq(cr_cmd.angleTargets.roll, 0.0)
        assert_true(cr_cmd.translationBias.surge > 0.0)
        assert_true(cr_cmd.translationBias.sway > 0.0)

        -- FCP transmits MSG_ATTITUDE_CMD on Base+1 (10001)
        fcp.modem:transmit(10001, 10001, {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 101,
            type = "MSG_ATTITUDE_CMD",
            time = 1150,
            payload = cr_cmd
        })
        bus:step(0.05)

        -- VAS receives MSG_ATTITUDE_CMD, verifies non-aero policy, and allocates 6-DoF vector thrust
        local vas_att_in = vas.modem:drain()
        assert_eq(#vas_att_in, 1)
        assert_true(vas_net.dispatch(vas_state, vas_fsm, nil, vas_tca, 10001, 10001, vas_att_in[1].payload))
        assert_eq(vas_fsm.currentState, "NORMAL")
        assert_eq(vas_policy_mod.resolve_flap_target(vas_policy, vas_state.latestCommand, 15.0, {}), 0.0)

        local wrench = {
            surge = 16.0,
            sway = 8.0,
            heave = 20.0,
            pitchTorque = 0.0,
            rollTorque = 0.0,
            yawTorque = 0.0
        }
        local vec_outputs, sat_status = vas_tca_mod.allocate(vas_tca, wrench)
        assert_not_nil(vec_outputs.THR_VEC_1)
        assert_eq(type(vec_outputs.THR_VEC_1), "table")
        assert_eq(vec_outputs.THR_VEC_1.thrust, 5)
        assert_near(vec_outputs.THR_VEC_1.gimbalX, 0.25, 1e-4)
        assert_near(vec_outputs.THR_VEC_1.gimbalY, 0.5, 1e-4)
        assert_false(sat_status.axisSaturatedPos.surge)

        -- VAS transmits MSG_THRUST_CMD on Base+10 (10010) and suppresses Base+11 (10011)
        vas_net.send_packet(vas_state, 10010, "MSG_THRUST_CMD", {
            watchdogSeq = 1,
            controlState = "NORMAL",
            outputs = vec_outputs
        })
        bus:step(0.05)

        local srf_pkts = bus:find_packets({ channel = 10011 })
        -- Only the earlier calibration bay bind packets (OPEN/CLOSE) may exist on 10011; zero MSG_SURFACE_CMD or MSG_AERO_CMD
        assert_eq(#bus:find_packets({ type = "MSG_SURFACE_CMD", channel = 10011 }), 0)
        assert_eq(#bus:find_packets({ type = "MSG_AERO_CMD", channel = 10011 }), 0)

        -- TCA processes MSG_THRUST_CMD and reports MSG_ACTUATOR_STATUS
        local tca_cmd_in = tca.modem:drain()
        assert_eq(#tca_cmd_in, 1)
        assert_true(tca_inst:dispatch_modem_message(10010, 10010, tca_cmd_in[1].payload))
        assert_eq(vec_hw._power, 5)
        assert_near(vec_hw._vectorX, 0.25, 1e-6)
        assert_near(vec_hw._vectorY, 0.5, 1e-6)
        bus:step(0.05)

        local vas_stat_in = vas.modem:drain()
        assert_eq(#vas_stat_in, 1)
        assert_eq(vas_stat_in[1].payload.type, "MSG_ACTUATOR_STATUS")
        assert_near(vas_stat_in[1].payload.payload.appliedGimbal.x, 0.25, 1e-6)
        assert_near(vas_stat_in[1].payload.payload.appliedGimbal.y, 0.5, 1e-6)
        assert_false(vas_stat_in[1].payload.payload.gimbalSaturated)
        assert_true(vas_net.dispatch(vas_state, vas_fsm, nil, vas_tca, 10010, 10010, vas_stat_in[1].payload))
        assert_false(vas_tca.hasGimbalSaturation)

        -- 8. Stage 6: Gimbal Saturation Anti-Windup & E_STOP Nozzle Neutralization
        local sat_outputs, sat_flags = vas_tca_mod.allocate(vas_tca, {
            surge = 40.0, sway = 0.0, heave = 20.0, pitchTorque = 0.0, rollTorque = 0.0, yawTorque = 0.0
        })
        assert_eq(sat_outputs.THR_VEC_1.gimbalY, 1.0)
        assert_true(sat_flags.axisSaturatedPos.surge)

        -- Force an out-of-range gimbal command into TCA to verify TCA clamping + gimbalSaturated feedback to VAS
        sat_outputs.THR_VEC_1.gimbalY = 1.4
        vas_net.send_packet(vas_state, 10010, "MSG_THRUST_CMD", {
            watchdogSeq = 2,
            controlState = "NORMAL",
            outputs = sat_outputs
        })
        bus:step(0.05)

        local tca_sat_in = tca.modem:drain()
        assert_eq(#tca_sat_in, 1)
        assert_true(tca_inst:dispatch_modem_message(10010, 10010, tca_sat_in[1].payload))
        assert_near(vec_hw._vectorY, 1.0, 1e-6)
        assert_true(tca_inst.adapterState.isGimbalSaturated)
        bus:step(0.05)

        local vas_sat_in = vas.modem:drain()
        assert_eq(#vas_sat_in, 1)
        assert_true(vas_sat_in[1].payload.payload.gimbalSaturated)
        assert_true(vas_net.dispatch(vas_state, vas_fsm, nil, vas_tca, 10010, 10010, vas_sat_in[1].payload))
        assert_true(vas_tca.hasGimbalSaturation)

        -- Hard E_STOP command cuts power to 0 and resets nozzle gimbals to (0.0, 0.0)
        vas_net.send_packet(vas_state, 10010, "MSG_THRUST_CMD", {
            watchdogSeq = 3,
            controlState = "E_STOP",
            outputs = { THR_VEC_1 = { thrust = 0, gimbalX = 0.8, gimbalY = -0.8 } }
        })
        bus:step(0.05)

        local tca_estop_in = tca.modem:drain()
        assert_eq(#tca_estop_in, 1)
        assert_true(tca_inst:dispatch_modem_message(10010, 10010, tca_estop_in[1].payload))
        assert_eq(vec_hw._power, 0)
        assert_near(vec_hw._vectorX, 0.0, 1e-6)
        assert_near(vec_hw._vectorY, 0.0, 1e-6)
    end)
end)
```

- [ ] **Step 2: Run unit and E2E tests to verify they fail**

Run:
```powershell
python tools/run_unit_tests.py --target 1_control/tca --clean-orphans
python tools/run_e2e_tests.py --filter advanced_vtol --clean-orphans
```
Expected: FAIL on `mockDev._vectorX` (`0.0` instead of `-0.5`) during `MSG_CALIB_PULSE` in both unit and E2E tests.

- [ ] **Step 3: Implement polymorphic calibration pulse forwarding in `src/1_control/tca/modules/tca_daemon.lua` and `src/1_control/tca/modules/watchdog_sentinel.lua`**

In `src/1_control/tca/modules/tca_daemon.lua` (`tca_daemon.handle_calib_pulse`):
```lua
function tca_daemon.handle_calib_pulse(inst, pkt)
    local p = pkt and pkt.payload
    if not p then return false end
    local tgt = p.targetThrusterId
    if tgt and tgt ~= inst.cfg.groupId and tgt ~= "ALL" then return false end
    if is_flight_state(inst.lastControlState) and inst.lastControlState ~= "CALIBRATION" then return false end
    local pulseSignal = (p.gimbalX ~= nil or p.gimbalY ~= nil)
        and { thrust = p.pulseLevel, gimbalX = p.gimbalX, gimbalY = p.gimbalY }
        or p.pulseLevel
    return inst.sentinel:handle_pulse(pulseSignal, p.pulseDurationMs, inst.adapterState)
end
```

In `src/1_control/tca/modules/watchdog_sentinel.lua` (`watchdog_sentinel.handle_pulse`):
```lua
function watchdog_sentinel.handle_pulse(wd, pulseLevel, durationMs, adapterState)
    if not wd or not adapterState then return false end
    local ok_aa, mod_aa = pcall(require, "actuator_adapter")
    local aa = ok_aa and mod_aa or package.loaded["actuator_adapter"]
    local pLvl = (type(pulseLevel) == "table" and tonumber(pulseLevel.thrust)) or tonumber(pulseLevel) or 0
    local dMs = tonumber(durationMs) or 0
    if pLvl <= 0 or dMs <= 0 then
        wd:cancel_pulse()
        if aa and aa.cut_thrust then aa.cut_thrust(adapterState) end
        return true
    end
    local signalArg = (type(pulseLevel) == "table") and pulseLevel or pLvl
    if aa and aa.apply_thrust then aa.apply_thrust(adapterState, signalArg, 1, 1) end
    wd:schedule_pulse(dMs, function()
        if aa and aa.cut_thrust then aa.cut_thrust(adapterState) end
    end)
    return true
end
```

- [ ] **Step 4: Run unit and E2E tests to verify they pass**

Run:
```powershell
python tools/run_unit_tests.py --target 1_control/tca --clean-orphans
python tools/run_e2e_tests.py --filter advanced_vtol --clean-orphans
```
Expected: PASS (`test_tca_vector_thruster.lua` and `test_e2e_advanced_vtol_flight.lua` 1/1 passed).

- [ ] **Step 5: Commit Task 1**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/1_control/tca/modules/tca_daemon.lua src/1_control/tca/modules/watchdog_sentinel.lua tests/1_control/tca/test_tca_vector_thruster.lua tests/e2e/test_e2e_advanced_vtol_flight.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "test(e2e): add scenario 7 ADVANCED_VTOL gimbal calibration and 6-DoF flight simulation"
```

---

### Task 2: GAC Dedicated Pad Rejection (`FACILITY_DEDICATED`) & `EMERGENCY` Commandeering E2E Simulation (`TASK-118-2`)

**Files:**
- Modify: `tests/e2e/test_e2e_facility_landing.lua:250-259`

**Interfaces:**
- Consumes:
  - `facility_inventory.create(facilities)` / `get_summary()` (`src/0_infra/gac/modules/facility_inventory.lua`)
  - `allocation_engine.select_best_pad(facilities, craftReq, surfaceWind, opts)` (`src/0_infra/gac/modules/allocation_engine.lua`)
  - `gac_fsm.create(cfg, inv, alloc)` / `handle_tower_handoff_req(pkt)` / `handle_aircraft_checkin(pkt, wind)` / `handle_pad_slot_ack(pkt)` / `handle_facility_update(pkt)` (`src/0_infra/gac/modules/gac_fsm.lua`)
  - `beacon_broadcaster.create(cfg):build_sector_beacon(inv, wind, status)` (`src/0_infra/gac/modules/beacon_broadcaster.lua`)
  - `pad_fsm.create(cfg, streamer, isRegistered)` (`src/0_infra/landing_pad/modules/pad_fsm.lua`)
  - `facility_client.init(cfg)` / `update_beacons(fc, payload, now)` / `on_atc_clearance(fc, clr, pos, now)` (`src/2_guidance/fcp/modules/facility_client.lua`)
- Produces:
  - Second `it(...)` test case in `tests/e2e/test_e2e_facility_landing.lua` exercising dedicated pad beacon exclusion, public-first emergency allocation, `FACILITY_DEDICATED` rejection on Tier-1 handoff and Tier-2 check-in, and last-resort `EMERGENCY` dedicated pad commandeering through touchdown.

- [ ] **Step 1: Add the dedicated facility & emergency commandeering E2E test case to `tests/e2e/test_e2e_facility_landing.lua`**

Append inside `describe("Scenario 6: 3-Tier Facility Tactical Landing", ...)` in `tests/e2e/test_e2e_facility_landing.lua`:

```lua
    it("enforces dedicated pad beacon isolation, FACILITY_DEDICATED rejection, and last-resort EMERGENCY commandeering", function()
        local bus = virtual_bus.create_bus({ clock = 2000.0 })

        local gac = node_sandbox.create_node(bus, "GAC", "src/0_infra/gac")
        local pad_pub = node_sandbox.create_node(bus, "PAD_PUB_01", "src/0_infra/landing_pad")
        local pad_vip = node_sandbox.create_node(bus, "PAD_VIP_02", "src/0_infra/landing_pad")
        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")

        local config_loader = gac:require("config_loader")
        local facility_inventory = gac:require("facility_inventory")
        local allocation_engine = gac:require("allocation_engine")
        local beacon_broadcaster = gac:require("beacon_broadcaster")
        local gac_fsm = gac:require("gac_fsm")

        local gac_cfg = config_loader.get_default_config()
        gac_cfg.facilities = {
            {
                facilityId = "PAD_PUB_01",
                type = "LANDING_PAD",
                tacticalChannel = 50211,
                maxSupportWeight = 40000.0,
                maxSupportRadius = 12.0,
                coordinates = { x = 1400.0, y = 65.0, z = -820.0 },
                status = "FREE",
                mobility = "STATIC"
            },
            {
                facilityId = "PAD_VIP_02",
                type = "LANDING_PAD",
                tacticalChannel = 50212,
                maxSupportWeight = 40000.0,
                maxSupportRadius = 12.0,
                coordinates = { x = 1210.0, y = 65.0, z = -805.0 },
                status = "FREE",
                mobility = "STATIC",
                dedicatedCraftIds = { "VIP_VTOL_01" },
                dedicatedAirframeTypes = { "ADVANCED_VTOL" }
            }
        }
        assert_true(config_loader.validate_config(gac_cfg))

        local inv = facility_inventory.create(gac_cfg.facilities)
        local fsm = gac_fsm.create(gac_cfg, inv, allocation_engine)
        local bc = beacon_broadcaster.create(gac_cfg)

        gac.modem:open(50201)
        gac.modem:open(50202)

        -- Setup PAD_PUB_01 and PAD_VIP_02 nodes
        local pub_streamer = pad_pub:require("tactical_streamer").create({
            padId = "PAD_PUB_01", facilityId = "PAD_PUB_01", mode = "STATIC",
            approachHeading = 180.0, safeDescentRate = 1.0, clearanceZoneRadius = 5.0,
            channels = { sectorFacilityChannel = 50202, tacticalChannel = 50211 }
        })
        local pub_fsm = pad_pub:require("pad_fsm").create({
            padId = "PAD_PUB_01", facilityId = "PAD_PUB_01", mode = "STATIC",
            channels = { sectorFacilityChannel = 50202, tacticalChannel = 50211 }
        }, pub_streamer, true)
        pad_pub.modem:open(50202)
        pad_pub.modem:open(50211)

        local vip_streamer = pad_vip:require("tactical_streamer").create({
            padId = "PAD_VIP_02", facilityId = "PAD_VIP_02", mode = "STATIC",
            approachHeading = 180.0, safeDescentRate = 1.0, clearanceZoneRadius = 5.0,
            channels = { sectorFacilityChannel = 50202, tacticalChannel = 50212 }
        })
        local vip_fsm = pad_vip:require("pad_fsm").create({
            padId = "PAD_VIP_02", facilityId = "PAD_VIP_02", mode = "STATIC",
            channels = { sectorFacilityChannel = 50202, tacticalChannel = 50212 }
        }, vip_streamer, true)
        pad_vip.modem:open(50202)
        pad_vip.modem:open(50212)

        local facility_client = fcp:require("facility_client")
        local fcp_fc = facility_client.init({ safety = { maxApproachRetries = 3 } })
        fcp.modem:open(50003)
        fcp.modem:open(50201)
        fcp.modem:open(50212)

        -- 1. Beacon public-only free pad advertisement check (total=2, free=1)
        local beacon_pkt = bc:build_sector_beacon(inv, gac_cfg.surfaceWind, "OPERATIONAL")
        assert_eq(beacon_pkt.payload.facilitiesSummary.totalLandingPads, 2)
        assert_eq(beacon_pkt.payload.facilitiesSummary.freeLandingPads, 1)

        -- 2. Review Focus Check: Emergency craft arriving while PAD_PUB_01 is FREE must select PAD_PUB_01 (not PAD_VIP_02)
        local early_emg_pad, early_emg_err = allocation_engine.select_best_pad(inv:get_all_facilities(), {
            aircraftId = "EMG_EARLY_01",
            airframeType = "VECTORED_VTOL",
            craftWeight = 12000,
            craftRadius = 4.5,
            currentPos = { x = 1200, y = 80, z = -800 },
            isEmergency = true
        }, gac_cfg.surfaceWind)
        assert_nil(early_emg_err)
        assert_not_nil(early_emg_pad)
        assert_eq(early_emg_pad.facilityId, "PAD_PUB_01")

        -- 3. Unprivileged craft requesting preferredFacilityId = "PAD_VIP_02" while PAD_PUB_01 is FREE is redirected to PAD_PUB_01
        local reg1_assign, reg1_err = fsm:handle_aircraft_checkin({
            ver = "1.9.5",
            domainId = "REGULAR_VTOL_01",
            seq = 1,
            type = "MSG_GAC_CHECKIN_REQ",
            time = 2010,
            payload = {
                sectorId = gac_cfg.sectorId,
                aircraftId = "REGULAR_VTOL_01",
                craftWeight = 12000,
                craftRadius = 4.5,
                currentPos = { x = 1200, y = 80, z = -800 },
                airframeType = "VECTORED_VTOL",
                preferredFacilityId = "PAD_VIP_02",
                isEmergency = false
            }
        }, gac_cfg.surfaceWind)
        assert_nil(reg1_err)
        assert_not_nil(reg1_assign)
        assert_eq(reg1_assign.payload.facilityId, "PAD_PUB_01")

        -- Mark PAD_PUB_01 as OCCUPIED after REGULAR_VTOL_01 lands
        fsm:handle_facility_update({
            ver = "1.9.5",
            domainId = "PAD_PUB_01",
            seq = 2,
            type = "MSG_ATC_FACILITY_UPDATE",
            time = 2050,
            payload = {
                facilityId = "PAD_PUB_01",
                status = "OCCUPIED",
                currentCraft = "REGULAR_VTOL_01"
            }
        })
        assert_eq(inv:get_summary().freeLandingPads, 0)
        assert_eq(inv:get_facility("PAD_VIP_02").status, "FREE")

        -- 4. Unprivileged craftREGULAR_VTOL_02 rejected with FACILITY_DEDICATED at both Tier-1 Handoff and Tier-2 Check-In
        local handoff_ack = fsm:handle_tower_handoff_req({
            ver = "1.9.5",
            domainId = "TOWER_SECTOR_00",
            seq = 10,
            type = "MSG_ATC_SECTOR_HANDOFF_REQ",
            time = 2060,
            payload = {
                sectorId = gac_cfg.sectorId,
                aircraftId = "REGULAR_VTOL_02",
                airframeType = "VECTORED_VTOL",
                craftWeight = 12000,
                craftRadius = 4.5,
                isEmergency = false
            }
        })
        assert_eq(handoff_ack.payload.status, "REJECTED")
        assert_eq(handoff_ack.payload.rejectReason, "FACILITY_DEDICATED")

        fcp.modem:transmit(50201, 50201, {
            ver = "1.9.5",
            domainId = "REGULAR_VTOL_02",
            seq = 11,
            type = "MSG_GAC_CHECKIN_REQ",
            time = 2070,
            payload = {
                sectorId = gac_cfg.sectorId,
                aircraftId = "REGULAR_VTOL_02",
                craftWeight = 12000,
                craftRadius = 4.5,
                currentPos = { x = 1200, y = 80, z = -800 },
                airframeType = "VECTORED_VTOL",
                preferredFacilityId = "PAD_VIP_02",
                isEmergency = false
            }
        })
        bus:step(0.05)

        local gac_deny_in = gac.modem:drain()
        assert_eq(#gac_deny_in, 1)
        local deny_assign, deny_clr = fsm:handle_aircraft_checkin(gac_deny_in[1].payload, gac_cfg.surfaceWind)
        assert_nil(deny_assign)
        assert_not_nil(deny_clr)
        assert_eq(deny_clr.payload.status, "DENIED")
        assert_eq(deny_clr.payload.reason, "FACILITY_DEDICATED")

        gac.modem:transmit(50201, 50201, deny_clr)
        bus:step(0.05)

        local fcp_deny_in = fcp.modem:drain()
        assert_eq(#fcp_deny_in, 1)
        facility_client.on_atc_clearance(fcp_fc, {
            status = fcp_deny_in[1].payload.payload.status,
            reason = fcp_deny_in[1].payload.payload.reason
        }, { x = 1200, y = 80, z = -800 }, 2075)
        assert_eq(fcp_fc.atcStatus, "DENIED")

        -- 5. Emergency aircraft MAYDAY_VTOL_99 commandeers dedicated PAD_VIP_02 when all public pads are OCCUPIED
        fcp.modem:transmit(50201, 50201, {
            ver = "1.9.5",
            domainId = "MAYDAY_VTOL_99",
            seq = 20,
            type = "MSG_GAC_CHECKIN_REQ",
            time = 2100,
            payload = {
                sectorId = gac_cfg.sectorId,
                aircraftId = "MAYDAY_VTOL_99",
                craftWeight = 14000,
                craftRadius = 5.0,
                currentPos = { x = 1205, y = 78, z = -802 },
                airframeType = "VECTORED_VTOL",
                isEmergency = true
            }
        })
        bus:step(0.05)

        local gac_emg_in = gac.modem:drain()
        assert_eq(#gac_emg_in, 1)
        local emg_assign, emg_err = fsm:handle_aircraft_checkin(gac_emg_in[1].payload, gac_cfg.surfaceWind)
        assert_nil(emg_err)
        assert_not_nil(emg_assign)
        assert_eq(emg_assign.payload.facilityId, "PAD_VIP_02")
        assert_eq(emg_assign.payload.aircraftId, "MAYDAY_VTOL_99")
        assert_eq(emg_assign.payload.tacticalChannel, 50212)

        gac.modem:transmit(50202, 50202, emg_assign)
        bus:step(0.05)

        -- PAD_VIP_02 processes slot assignment and replies MSG_ATC_SLOT_ACK
        pad_pub.modem:drain()
        local vip_assign_in = pad_vip.modem:drain()
        assert_eq(#vip_assign_in, 1)
        local vip_acks = vip_fsm:handle_backbone_message(vip_assign_in[1].payload, 2105)
        assert_eq(#vip_acks, 1)
        assert_eq(vip_acks[1].type, "MSG_ATC_SLOT_ACK")
        assert_eq(vip_acks[1].payload.status, "ACCEPTED")
        assert_eq(vip_fsm:get_state(), "APPROACH_STATIC")

        pad_vip.modem:transmit(50202, 50202, vip_acks[1])
        bus:step(0.05)

        -- GAC grants approach clearance on 50201 for commandeered PAD_VIP_02
        local gac_vip_ack = gac.modem:drain()
        assert_eq(#gac_vip_ack, 1)
        local emg_clr = fsm:handle_pad_slot_ack(gac_vip_ack[1].payload)
        assert_not_nil(emg_clr)
        assert_eq(emg_clr.payload.status, "CLEARED")
        assert_eq(emg_clr.payload.assignedFacilityId, "PAD_VIP_02")
        assert_eq(emg_clr.payload.assignedTacticalChannel, 50212)

        gac.modem:transmit(50201, 50201, emg_clr)
        bus:step(0.05)

        local fcp_emg_clr = fcp.modem:drain()
        assert_eq(#fcp_emg_clr, 1)
        local emg_p = fcp_emg_clr[1].payload.payload
        facility_client.on_atc_clearance(fcp_fc, {
            status = emg_p.status,
            padId = emg_p.assignedFacilityId,
            padChannel = emg_p.assignedTacticalChannel,
            padMobility = "STATIC",
        }, { x = 1205, y = 78, z = -802 }, 2110)
        assert_eq(fcp_fc.atcStatus, "CLEARED")
        assert_eq(fcp_fc.activePadId, "PAD_VIP_02")
        assert_eq(fcp_fc.padChannel, 50212)

        -- Touchdown on PAD_VIP_02 transitions pad and GAC inventory to OCCUPIED
        fcp.modem:transmit(50212, 50212, {
            ver = "1.9.5",
            domainId = "MAYDAY_VTOL_99",
            seq = 21,
            type = "MSG_TOUCHDOWN_COMPLETE",
            time = 2150,
            payload = { facilityId = "PAD_VIP_02", craftState = "GROUND_IDLE" }
        })
        bus:step(0.05)

        local vip_td_in = pad_vip.modem:drain()
        assert_eq(#vip_td_in, 1)
        local vip_upds = vip_fsm:handle_tactical_message(vip_td_in[1].payload, 2155)
        assert_eq(#vip_upds, 1)
        assert_eq(vip_fsm:get_state(), "OCCUPIED")

        pad_vip.modem:transmit(50202, 50202, vip_upds[1])
        bus:step(0.05)

        local gac_vip_upd = gac.modem:drain()
        assert_eq(#gac_vip_upd, 1)
        local sec_status = fsm:handle_facility_update(gac_vip_upd[1].payload)
        assert_not_nil(sec_status)
        assert_eq(inv:get_facility("PAD_VIP_02").status, "OCCUPIED")
        assert_eq(inv:get_facility("PAD_VIP_02").currentCraft, "MAYDAY_VTOL_99")
    end)
```

- [ ] **Step 2: Run E2E test runner on `facility_landing` to verify both test cases pass**

Run: `python tools/run_e2e_tests.py --filter facility_landing --clean-orphans`
Expected: PASS (`test_e2e_facility_landing` 2/2 passed).

- [ ] **Step 3: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tests/e2e/test_e2e_facility_landing.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "test(e2e): expand scenario 6 with dedicated pad rejection and emergency commandeering"
```

---

### Task 3: Mutation Testing Suite Expansion (`MUT-21` ~ `MUT-25`) & Context Sync (`TASK-118-3`)

**Files:**
- Modify: `tools/run_mutation_tests.py:19-221`
- Modify: `README.md`
- Modify: `GEMINI.md`
- Modify: `TASK.md`

**Interfaces:**
- Consumes:
  - `src/1_control/vas/modules/thrust_mixer.lua`
  - `src/1_control/tca/modules/actuator_adapter.lua`
  - `src/2_guidance/fcp/modules/advanced_vtol_driver.lua`
  - `src/0_infra/gac/modules/allocation_engine.lua`
- Produces:
  - `MUTATIONS` list in `tools/run_mutation_tests.py` expanded from 20 to 25 deterministic mutants (`MUT-01` .. `MUT-25`), achieving 25/25 KILLED (100.0%).

- [ ] **Step 1: Add `MUT-21` through `MUT-25` to `tools/run_mutation_tests.py`**

Append to `MUTATIONS` in `tools/run_mutation_tests.py`:

```python
    {
        "id": "MUT-21",
        "name": "VAS Vector VTOL Pseudo-Inverse Wrench Matrix Multiplication Sign Inversion",
        "domain": "Control",
        "file": "src/1_control/vas/modules/thrust_mixer.lua",
        "target": "sum = sum + (row[c] or 0.0) * (w[c] or 0.0)",
        "replacement": "sum = sum - (row[c] or 0.0) * (w[c] or 0.0)",
        "runner": "unit",
        "target_arg": "1_control/vas",
    },
    {
        "id": "MUT-22",
        "name": "TCA Vector Thruster Fail-Safe Nozzle Neutralization Bypass",
        "domain": "Safety",
        "file": "src/1_control/tca/modules/actuator_adapter.lua",
        "target": "pcall(item.wrapped.setVector, 0.0, 0.0)",
        "replacement": "-- pcall(item.wrapped.setVector, 0.0, 0.0)",
        "runner": "unit",
        "target_arg": "1_control/tca",
    },
    {
        "id": "MUT-23",
        "name": "FCP Advanced VTOL PID Surge Proportional Gain Sign Inversion",
        "domain": "Guidance",
        "file": "src/2_guidance/fcp/modules/advanced_vtol_driver.lua",
        "target": "local raw_surge = clamp(skp * err_surge - skd * vel_surge + s_i, -1.0, 1.0)",
        "replacement": "local raw_surge = clamp(-skp * err_surge - skd * vel_surge + s_i, -1.0, 1.0)",
        "runner": "unit",
        "target_arg": "2_guidance/fcp",
    },
    {
        "id": "MUT-24",
        "name": "GAC Dedicated Facility Rejection Classification Bypass",
        "domain": "Infra",
        "file": "src/0_infra/gac/modules/allocation_engine.lua",
        "target": "if hasDedicatedBlockingFree then",
        "replacement": "if false and hasDedicatedBlockingFree then",
        "runner": "unit",
        "target_arg": "0_infra/gac",
    },
    {
        "id": "MUT-25",
        "name": "GAC Emergency Dedicated Pad Commandeering Public-Free Guard Inversion",
        "domain": "Infra",
        "file": "src/0_infra/gac/modules/allocation_engine.lua",
        "target": "if not anyPublicFree then",
        "replacement": "if anyPublicFree then",
        "runner": "unit",
        "target_arg": "0_infra/gac",
    },
```

- [ ] **Step 2: Run the new mutants (`MUT-21` ~ `MUT-25`) and full mutation suite to verify 25/25 KILLED**

Run:
```powershell
python tools/run_mutation_tests.py
```
Expected: `25/25 KILLED` (`100.0%` kill rate, `>= 90.0%` threshold).

- [ ] **Step 3: Run full verification pipeline (`validate_lua_syntax`, `verify_manifest_sync`, `verify_all_specs`, `verify_spec_status`, unit, E2E, harness)**

Run:
```powershell
python tools/validate_lua_syntax.py; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python tools/verify_all_specs.py }; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/run_unit_tests.py --require-tests --clean-orphans }; if ($?) { python tools/run_e2e_tests.py --clean-orphans }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }
```
Expected:
- `validate_lua_syntax.py`: 127 Lua files PASS
- `verify_manifest_sync.py`: `0 Errors, 0 Warnings`
- `verify_all_specs.py`: `0 Errors, 0 Warnings`
- `verify_spec_status.py`: `9 Implemented, 5 Approved`
- `run_unit_tests.py`: `309/309 PASS` across 12 targets
- `run_e2e_tests.py`: `7 suites (8/8 passed)`
- `unittest`: `49/49 PASS`

- [ ] **Step 4: Sync `TASK.md`, `GEMINI.md`, `.agent/memory/workspace-root.md`, and `README.md` with updated test metrics and mark `TASK-118` complete**

Update:
- `TASK.md`: Move `TASK-118` (`TASK-118-1`, `TASK-118-2`, `TASK-118-3`) to `## ✅ 3. 완료된 작업 이력` (pruning oldest entry beyond 10).
- `GEMINI.md` & `README.md`: Update standard command test counts (`309/309 PASS`, `7개 시나리오 8/8 PASS`, `25/25 KILLED`).
- `.agent/memory/workspace-root.md`: Append `TASK-118` completion record.

- [ ] **Step 5: Commit Task 3**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tools/run_mutation_tests.py TASK.md GEMINI.md README.md .agent/memory/workspace-root.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "test(mutation): add ADVANCED_VTOL and GAC dedicated/emergency mutation targets (25/25 KILLED)"
```
