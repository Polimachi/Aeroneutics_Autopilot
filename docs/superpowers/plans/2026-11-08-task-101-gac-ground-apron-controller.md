# GAC (Ground Apron Controller) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Tier 2 Ground Apron Controller (`src/0_infra/gac/`) for ground/flight-deck facility swarm management, featuring 1Hz aggregated sector beacons, 2-stage multi-attribute pad allocation, local go-around mediation, a dual-display (51x19 term + external monitor) 3-tab TUI console with operator override controls, and configuration persistence.

**Architecture:** A standalone, non-blocking ComputerCraft Lua application divided into modular components: configuration persistence (`config_loader.lua`), facility swarm registry (`facility_inventory.lua`), 2-stage mathematical optimization (`allocation_engine.lua`), aggregated beacon generator (`beacon_broadcaster.lua`), sector state machine (`gac_fsm.lua`), and a dual-target TUI renderer (`tui_view.lua`) orchestrated by a 20Hz event/timer main loop (`main.lua`).

**Tech Stack:** CC:Tweaked Lua 5.2 (Cobalt VM), Ender Modem wireless networking (CH 50001, 50002, 50003, 50004, $Base_{\text{sec}}+0$, $Base_{\text{sec}}+1$), Advanced Color Computer & Monitor API (`term`, `colors`), CraftOS-PC Headless Unit Test Framework (`tools/run_unit_tests.py`).

**Spec:** [GAC_PROGRAM_SPECIFICATION_AND_ICD.md](../../specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md) (v1.3.0)

## Global Constraints

- **Multi-Codebase Autonomy**: `src/0_infra/gac/` must be 100% self-contained; no cross-layer `require` references to other subsystems (e.g. `vas`, `fcp`, `landing_pad`).
- **Channel Allocation Hierarchy**: Sector Base $Base_{\text{sec}} = 50001 + S \times 200$. Common channels: Tower ATC `50001`, Wide-Area Backbone `50002`, Master Beacon `50003`, GAC Directory Dispatch `50004`. Sector channels: Sector Comm $+0$, Sector Local Backbone $+1$, Sector Beacon $+2$, Sector GPS reply $+5$, Tactical channels $+10 \sim +199$.
- **Standard Envelope & Zero-Fallback**: Strict standard envelope (`ver="1.9.5"`, `domainId`, `seq`, `type`, `time`, `payload`) using exact single-key field names.
- **Dual Display Target**: Default terminal 51x19 (`term`), auto-binding external advanced monitor (`peripheral.find("monitor")`) with touch event support.
- **TUI Non-blocking Operations**: TUI rendering and keyboard/touch event handling must run non-blocking in parallel with RF modem event polling.
- **Lua 5.2 Compatibility**: No Lua 5.3+ bitwise operators (`//`, `&`, `|`, `~`), no `getfenv`/`setfenv`, use `fs.*` exclusively.

## Review Focus

1. **Sector Over-capacity Denial**: When all valid facilities are occupied or exceed craft weight/radius limits, GAC must return `REJECTED` / `HOLD` with `"SECTOR_ALL_OCCUPIED"` or `"OVERWEIGHT"` without deadlocking.
2. **Local Go-Around Swarm Isolation**: When a pad reports `MSG_ABORT_APPROACH`, GAC must isolate that pad (`GO_AROUND`), and divert the aircraft to a secondary `FREE` pad on `MSG_ATC_ABORT_CLEAR` without prematurely releasing control to Tower ATC.
3. **Ghost Slot Expiration**: If an assigned aircraft fails to touch down within 120 seconds, GAC must trigger slot timeout, reset the pad to `FREE`, and log the cancellation.
4. **Emergency Lockdown Propagation**: Triggering `[E]` (Emergency Freeze) via TUI must broadcast `MSG_ABORT_APPROACH` to all approaching traffic, switch beacon status to `DECK_DANGEROUS`, and lock incoming handoffs.
5. **Config Serialization Integrity**: Dynamic registration or state edits via TUI must write back to `/gac/config.json` atomically without corrupting coordinates, channels, or existing facilities.

---

## File Structure

- `src/0_infra/gac/modules/config_loader.lua` — Configuration parsing, schema validation, and atomic JSON persistence.
- `src/0_infra/gac/modules/facility_inventory.lua` — In-memory facility registry, state transitions, dynamic telemetry cache, and emergency lockdown.
- `src/0_infra/gac/modules/allocation_engine.lua` — 2-stage multi-attribute pad selection algorithm (hard constraint filter + soft scoring function).
- `src/0_infra/gac/modules/beacon_broadcaster.lua` — 1Hz aggregated sector beacon (`CH 50003` / $Base_{\text{sec}}+2$) and directory dispatch (`CH 50004`) generator.
- `src/0_infra/gac/modules/gac_fsm.lua` — Sector FSM managing Tower ATC negotiation, aircraft check-in, pad slot assignment, go-around mediation, departure handoff, and timeouts.
- `src/0_infra/gac/modules/tui_view.lua` — Dual-display (51x19 terminal + monitor) 3-tab TUI renderer and interactive operator control dispatcher.
- `src/0_infra/gac/config.lua` — Default runtime configuration for GAC Sector Alpha.
- `src/0_infra/gac/main.lua` — Non-blocking 20Hz event loop coordinating network, FSM ticks, and TUI interactions.
- `tests/0_infra/gac/test_config_loader.lua` — Unit tests for config loading, validation, and atomic save.
- `tests/0_infra/gac/test_facility_inventory.lua` — Unit tests for facility registry, status updates, and emergency lockdown.
- `tests/0_infra/gac/test_allocation_engine.lua` — Unit tests for 2-stage multi-attribute selection and edge cases.
- `tests/0_infra/gac/test_beacon_broadcaster.lua` — Unit tests for 1Hz beacon and dispatch packet generation.
- `tests/0_infra/gac/test_gac_fsm.lua` — Unit tests for FSM lifecycle, handoffs, go-around, and slot timeouts.
- `tests/0_infra/gac/test_tui_view.lua` — Unit tests for 3-tab layout, keyboard shortcuts, and touch input.
- `tests/0_infra/gac/test_main_integration.lua` — Integration smoke test for peripheral binding, network listening, and tick execution.

---

### Task 1: GAC Configuration Loader & Persistence (`config_loader.lua`)

**Files:**
- Create: `src/0_infra/gac/modules/config_loader.lua`
- Create: `tests/0_infra/gac/test_config_loader.lua`

**Interfaces:**
- Consumes: `fs`, `textutils`
- Produces:
  - `config_loader.get_default_config() -> table`
  - `config_loader.validate_config(cfg: table) -> boolean, string | nil`
  - `config_loader.load_config(path: string | nil) -> table, string | nil`
  - `config_loader.save_config(path: string | nil, cfg: table) -> boolean, string | nil`

- [ ] **Step 1: Write failing test**

```lua
-- tests/0_infra/gac/test_config_loader.lua
local config_loader = require("config_loader")

describe("GAC config loader and atomic persistence", function()
    it("returns valid default configuration with sector settings and facilities", function()
        local def = config_loader.get_default_config()
        assert_eq(type(def), "table")
        assert_eq(def.sectorId, "BASE_ALPHA_SECTOR_01")
        assert_eq(def.sectorIndex, 1)
        assert_eq(def.baseSecChannel, 50201)
        assert_eq(def.towerAtcChannel, 50001)
        assert_true(#def.facilities >= 1)
        
        local ok, err = config_loader.validate_config(def)
        assert_true(ok)
        assert_nil(err)
    end)

    it("rejects configuration missing mandatory sector fields", function()
        local bad = { sectorId = "TEST" }
        local ok, err = config_loader.validate_config(bad)
        assert_false(ok)
        assert_not_nil(err)
    end)

    it("performs atomic save and load round-trip", function()
        local path = sdk.temp_path("gac_config.json")
        local cfg = config_loader.get_default_config()
        cfg.sectorName = "Custom Test Sector"
        
        local okSave, errSave = config_loader.save_config(path, cfg)
        assert_true(okSave, errSave)
        
        local loaded, errLoad = config_loader.load_config(path)
        assert_not_nil(loaded)
        assert_nil(errLoad)
        assert_eq(loaded.sectorName, "Custom Test Sector")
        assert_eq(loaded.baseSecChannel, 50201)
    end)

    it("falls back to default config if file does not exist", function()
        local loaded, err = config_loader.load_config("/non_existent_gac_cfg.json")
        assert_not_nil(loaded)
        assert_nil(err)
        assert_eq(loaded.sectorId, "BASE_ALPHA_SECTOR_01")
    end)
end)
```

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: FAIL (`module 'config_loader' not found`)

- [ ] **Step 3: Implement minimal code**

Implement `src/0_infra/gac/modules/config_loader.lua`:
- `get_default_config()` providing `sectorId="BASE_ALPHA_SECTOR_01"`, `sectorName="Alpha Base Central Vertiport"`, `sectorType="VERTIPORT"`, `sectorIndex=1`, `baseSecChannel=50201`, `towerAtcChannel=50001`, `facilities` with default `PAD_01` and `PAD_02`.
- `validate_config(cfg)` checking required keys `sectorId`, `sectorIndex`, `baseSecChannel`, `towerAtcChannel`, and `facilities` array.
- `load_config(path)` reading file with `fs.open`, parsing with `textutils.unserializeJSON`, validating, and returning default if file missing.
- `save_config(path, cfg)` writing JSON atomically using temporary file `<path>.tmp` and `fs.move`.

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: PASS (`4/4 PASS`)

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/gac/modules/config_loader.lua tests/0_infra/gac/test_config_loader.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(gac): implement configuration loader and atomic persistence"
```

---

### Task 2: Facility Swarm Inventory Manager (`facility_inventory.lua`)

**Files:**
- Create: `src/0_infra/gac/modules/facility_inventory.lua`
- Create: `tests/0_infra/gac/test_facility_inventory.lua`

**Interfaces:**
- Consumes: `table`
- Produces:
  - `facility_inventory.create(initialFacilities: table | nil) -> table`
  - `inv:add_facility(fac: table) -> boolean, string | nil`
  - `inv:remove_facility(facilityId: string) -> boolean, string | nil`
  - `inv:get_facility(facilityId: string) -> table | nil`
  - `inv:get_all_facilities() -> table`
  - `inv:update_status(facilityId: string, status: string, craftId: string | nil, faultCode: string | nil) -> boolean, string | nil`
  - `inv:update_dynamic_telemetry(facilityId: string, pos: table, heading: number, vel: table) -> boolean, string | nil`
  - `inv:set_emergency_lockdown(active: boolean) -> void`
  - `inv:is_emergency_lockdown() -> boolean`
  - `inv:get_free_pads() -> table`
  - `inv:get_summary() -> table`

- [ ] **Step 1: Write failing test**

```lua
-- tests/0_infra/gac/test_facility_inventory.lua
local facility_inventory = require("facility_inventory")

describe("GAC facility swarm inventory manager", function()
    local samplePads = {
        {
            facilityId = "PAD_01",
            type = "LANDING_PAD",
            tacticalChannel = 50211,
            maxSupportWeight = 40000.0,
            maxSupportRadius = 12.0,
            coordinates = { x = 1250.0, y = 65.0, z = -820.0 },
            status = "FREE",
            mobility = "STATIC"
        },
        {
            facilityId = "PAD_02",
            type = "LANDING_PAD",
            tacticalChannel = 50212,
            maxSupportWeight = 20000.0,
            maxSupportRadius = 6.0,
            coordinates = { x = 1300.0, y = 65.0, z = -800.0 },
            status = "FREE",
            mobility = "STATIC"
        }
    }

    it("initializes inventory and queries free pads and summary", function()
        local inv = facility_inventory.create(samplePads)
        assert_eq(#inv:get_all_facilities(), 2)
        local freePads = inv:get_free_pads()
        assert_eq(#freePads, 2)
        
        local summary = inv:get_summary()
        assert_eq(summary.totalLandingPads, 2)
        assert_eq(summary.freeLandingPads, 2)
        assert_eq(summary.maxSupportWeight, 40000.0)
        assert_eq(summary.maxSupportRadius, 12.0)
    end)

    it("updates status and reflects in free pads list", function()
        local inv = facility_inventory.create(samplePads)
        local ok, err = inv:update_status("PAD_01", "OCCUPIED", "CRAFT_01")
        assert_true(ok)
        assert_nil(err)
        
        local fac = inv:get_facility("PAD_01")
        assert_eq(fac.status, "OCCUPIED")
        assert_eq(fac.currentCraft, "CRAFT_01")
        
        local freePads = inv:get_free_pads()
        assert_eq(#freePads, 1)
        assert_eq(freePads[1].facilityId, "PAD_02")
    end)

    it("toggles emergency lockdown and overrides availability", function()
        local inv = facility_inventory.create(samplePads)
        assert_false(inv:is_emergency_lockdown())
        
        inv:set_emergency_lockdown(true)
        assert_true(inv:is_emergency_lockdown())
        assert_eq(#inv:get_free_pads(), 0)
        
        inv:set_emergency_lockdown(false)
        assert_false(inv:is_emergency_lockdown())
        assert_eq(#inv:get_free_pads(), 2)
    end)

    it("adds and removes facilities dynamically", function()
        local inv = facility_inventory.create(samplePads)
        local newFac = {
            facilityId = "PAD_03",
            type = "LANDING_PAD",
            tacticalChannel = 50213,
            maxSupportWeight = 15000.0,
            maxSupportRadius = 5.0,
            coordinates = { x = 1400.0, y = 65.0, z = -800.0 },
            status = "FREE"
        }
        local okAdd = inv:add_facility(newFac)
        assert_true(okAdd)
        assert_eq(#inv:get_all_facilities(), 3)
        
        local okRem = inv:remove_facility("PAD_03")
        assert_true(okRem)
        assert_eq(#inv:get_all_facilities(), 2)
    end)

    it("updates dynamic facility telemetry coordinates and velocity", function()
        local inv = facility_inventory.create(samplePads)
        local ok = inv:update_dynamic_telemetry("PAD_01", { x = 1260.0, y = 66.0, z = -815.0 }, 90.0, { vx = 1.0, vy = 0.0, vz = 0.0 })
        assert_true(ok)
        local fac = inv:get_facility("PAD_01")
        assert_eq(fac.coordinates.x, 1260.0)
        assert_eq(fac.heading, 90.0)
        assert_eq(fac.velocity.vx, 1.0)
    end)
end)
```

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: FAIL (`module 'facility_inventory' not found`)

- [ ] **Step 3: Implement minimal code**

Implement `src/0_infra/gac/modules/facility_inventory.lua`:
- Closure/object containing internal `facilities` table (keyed by `facilityId` and indexed array), `emergencyLockdown` boolean flag.
- Methods: `add_facility`, `remove_facility`, `get_facility`, `get_all_facilities`, `update_status`, `update_dynamic_telemetry`, `set_emergency_lockdown`, `is_emergency_lockdown`, `get_free_pads` (returns empty if emergency lockdown active, otherwise pads with `status == "FREE"`), `get_summary`.

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: PASS (`test_config_loader` + `test_facility_inventory` passing)

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/gac/modules/facility_inventory.lua tests/0_infra/gac/test_facility_inventory.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(gac): implement facility swarm inventory and status manager"
```

---

### Task 3: 2-Stage Multi-Attribute Allocation Engine (`allocation_engine.lua`)

**Files:**
- Create: `src/0_infra/gac/modules/allocation_engine.lua`
- Create: `tests/0_infra/gac/test_allocation_engine.lua`

**Interfaces:**
- Consumes: `math`
- Produces:
  - `allocation_engine.filter_candidates(facilities: table, craftWeight: number, craftRadius: number) -> table`
  - `allocation_engine.calculate_score(pad: table, craftPos: table, windDir: number, craftWeight: number, weights: table | nil, dNorm: number | nil) -> number`
  - `allocation_engine.select_best_pad(facilities: table, craftReq: table, surfaceWind: table, opts: table | nil) -> table | nil, string | nil`

- [ ] **Step 1: Write failing test**

```lua
-- tests/0_infra/gac/test_allocation_engine.lua
local allocation_engine = require("allocation_engine")

describe("GAC 2-stage multi-attribute pad allocation engine", function()
    local pads = {
        {
            facilityId = "PAD_SMALL",
            status = "FREE",
            maxSupportWeight = 10000.0,
            maxSupportRadius = 4.0,
            coordinates = { x = 100.0, y = 64.0, z = 0.0 },
            approachHeading = 180.0
        },
        {
            facilityId = "PAD_LARGE_NEAR",
            status = "FREE",
            maxSupportWeight = 50000.0,
            maxSupportRadius = 15.0,
            coordinates = { x = 200.0, y = 64.0, z = 0.0 },
            approachHeading = 180.0
        },
        {
            facilityId = "PAD_OCCUPIED",
            status = "OCCUPIED",
            maxSupportWeight = 50000.0,
            maxSupportRadius = 15.0,
            coordinates = { x = 50.0, y = 64.0, z = 0.0 },
            approachHeading = 180.0
        }
    }

    it("Stage 1: filters out occupied, overweight, or undersized pads", function()
        local valid = allocation_engine.filter_candidates(pads, 18500.0, 5.0)
        assert_eq(#valid, 1)
        assert_eq(valid[1].facilityId, "PAD_LARGE_NEAR")
    end)

    it("Short-circuits immediately if preferredFacilityId is valid and FREE", function()
        local craftReq = {
            aircraftId = "CRAFT_01",
            craftWeight = 8000.0,
            craftRadius = 3.0,
            currentPos = { x = 0.0, y = 100.0, z = 0.0 },
            preferredFacilityId = "PAD_SMALL"
        }
        local wind = { speed = 2.0, direction = 180.0 }
        local best, err = allocation_engine.select_best_pad(pads, craftReq, wind)
        assert_not_nil(best)
        assert_nil(err)
        assert_eq(best.facilityId, "PAD_SMALL")
    end)

    it("Stage 2: calculates score J(P_i) prioritizing headwind, distance, and weight margin", function()
        local craftReq = {
            aircraftId = "CRAFT_01",
            craftWeight = 8000.0,
            craftRadius = 3.0,
            currentPos = { x = 0.0, y = 64.0, z = 0.0 }
        }
        local wind = { speed = 3.0, direction = 180.0 }
        local best, err = allocation_engine.select_best_pad(pads, craftReq, wind)
        assert_not_nil(best)
        assert_nil(err)
        -- PAD_SMALL is at x=100 (closer than PAD_LARGE_NEAR at x=200), same heading
        assert_eq(best.facilityId, "PAD_SMALL")
    end)

    it("returns nil and SECTOR_ALL_OCCUPIED when no free pad exists", function()
        local occupiedOnly = {
            { facilityId = "P1", status = "OCCUPIED", maxSupportWeight = 50000, maxSupportRadius = 10, coordinates = {x=0,y=0,z=0} }
        }
        local craftReq = { aircraftId = "C1", craftWeight = 1000, craftRadius = 2, currentPos = {x=0,y=0,z=0} }
        local best, err = allocation_engine.select_best_pad(occupiedOnly, craftReq, { speed = 0, direction = 0 })
        assert_nil(best)
        assert_eq(err, "SECTOR_ALL_OCCUPIED")
    end)

    it("returns nil and OVERWEIGHT when all free pads exceed weight limit", function()
        local smallOnly = {
            { facilityId = "P1", status = "FREE", maxSupportWeight = 5000, maxSupportRadius = 10, coordinates = {x=0,y=0,z=0} }
        }
        local craftReq = { aircraftId = "C1", craftWeight = 20000, craftRadius = 2, currentPos = {x=0,y=0,z=0} }
        local best, err = allocation_engine.select_best_pad(smallOnly, craftReq, { speed = 0, direction = 0 })
        assert_nil(best)
        assert_eq(err, "OVERWEIGHT")
    end)
end)
```

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: FAIL (`module 'allocation_engine' not found`)

- [ ] **Step 3: Implement minimal code**

Implement `src/0_infra/gac/modules/allocation_engine.lua`:
- `filter_candidates(facilities, craftWeight, craftRadius)`: returns list of facilities matching `status == "FREE"`, `maxSupportWeight >= craftWeight`, `maxSupportRadius >= craftRadius`.
- `calculate_score(pad, craftPos, windDir, craftWeight, weights, dNorm)`: implements ICD formula:
  $J(P_i) = w_1 \cos(\psi_{wind} - \psi_{app}) - w_2 \frac{\|\vec{p}_{craft} - \vec{p}_{pad}\|}{D_{norm}} + w_3 \frac{W_{max} - W_{craft}}{W_{craft}}$ with default $w_1=0.50, w_2=0.35, w_3=0.15, D_{norm}=200.0$.
- `select_best_pad(facilities, craftReq, surfaceWind, opts)`: executes Stage 1 hard filter (handling `preferredFacilityId`), computes error code if empty (`OVERWEIGHT` if weight violated, otherwise `SECTOR_ALL_OCCUPIED`), and finds $\arg\max J(P_i)$.

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/gac/modules/allocation_engine.lua tests/0_infra/gac/test_allocation_engine.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(gac): implement 2-stage multi-attribute pad allocation engine"
```

---

### Task 4: Aggregated Beacon Broadcaster & Dispatcher (`beacon_broadcaster.lua`)

**Files:**
- Create: `src/0_infra/gac/modules/beacon_broadcaster.lua`
- Create: `tests/0_infra/gac/test_beacon_broadcaster.lua`

**Interfaces:**
- Consumes: `os.epoch`, `math`
- Produces:
  - `beacon_broadcaster.create(config: table) -> table`
  - `broadcaster:build_sector_beacon(inventory: table, surfaceWind: table, sectorStatus: string) -> table`
  - `broadcaster:build_dispatch_packet(activeSectors: table | nil) -> table`
  - `broadcaster:broadcast_1hz(modem: table, inventory: table, surfaceWind: table, sectorStatus: string, nowSec: number) -> boolean`

- [ ] **Step 1: Write failing test**

```lua
-- tests/0_infra/gac/test_beacon_broadcaster.lua
local beacon_broadcaster = require("beacon_broadcaster")

describe("GAC aggregated beacon broadcaster", function()
    local cfg = {
        sectorId = "BASE_ALPHA_SECTOR_01",
        sectorName = "Alpha Base Central Vertiport",
        sectorType = "VERTIPORT",
        baseSecChannel = 50201,
        towerAtcChannel = 50001,
        beaconChannel = 50003,
        dispatchChannel = 50004
    }

    local mockInventory = {
        get_summary = function()
            return {
                totalLandingPads = 4,
                freeLandingPads = 3,
                totalRunways = 0,
                freeRunways = 0,
                maxSupportWeight = 40000.0,
                maxSupportRadius = 12.0
            }
        end
    }

    it("formats standard MSG_FACILITY_BEACON envelope and payload", function()
        local bc = beacon_broadcaster.create(cfg)
        local wind = { speed = 2.4, direction = 195.0 }
        local pkt = bc:build_sector_beacon(mockInventory, wind, "OPERATIONAL")
        
        assert_eq(pkt.ver, "1.9.5")
        assert_eq(pkt.type, "MSG_FACILITY_BEACON")
        assert_eq(pkt.payload.sectorId, "BASE_ALPHA_SECTOR_01")
        assert_eq(pkt.payload.gacChannel, 50201)
        assert_eq(pkt.payload.towerAtcChannel, 50001)
        assert_eq(pkt.payload.facilitiesSummary.totalLandingPads, 4)
        assert_eq(pkt.payload.facilitiesSummary.freeLandingPads, 3)
        assert_eq(pkt.payload.surfaceWind.speed, 2.4)
        assert_eq(pkt.payload.status, "OPERATIONAL")
    end)

    it("formats standard MSG_GAC_DISPATCH packet for directory announcement", function()
        local bc = beacon_broadcaster.create(cfg)
        local pkt = bc:build_dispatch_packet()
        assert_eq(pkt.ver, "1.9.5")
        assert_eq(pkt.type, "MSG_GAC_DISPATCH")
        assert_eq(pkt.payload.activeSectors[1].sectorId, "BASE_ALPHA_SECTOR_01")
        assert_eq(pkt.payload.activeSectors[1].gacChannel, 50201)
    end)

    it("rate-limits broadcast to strict 1Hz", function()
        local sentChannels = {}
        local mockModem = {
            transmit = function(ch, replyCh, payload)
                table.insert(sentChannels, ch)
            end
        }
        local bc = beacon_broadcaster.create(cfg)
        local wind = { speed = 2.0, direction = 180.0 }
        
        -- First call at t=10.0: should transmit
        local ok1 = bc:broadcast_1hz(mockModem, mockInventory, wind, "OPERATIONAL", 10.0)
        assert_true(ok1)
        assert_eq(#sentChannels, 2) -- 50003 and 50004
        
        -- Second call at t=10.5: should be rate-limited (skipped)
        local ok2 = bc:broadcast_1hz(mockModem, mockInventory, wind, "OPERATIONAL", 10.5)
        assert_false(ok2)
        assert_eq(#sentChannels, 2)
        
        -- Third call at t=11.1: should transmit
        local ok3 = bc:broadcast_1hz(mockModem, mockInventory, wind, "OPERATIONAL", 11.1)
        assert_true(ok3)
        assert_eq(#sentChannels, 4)
    end)
end)
```

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: FAIL (`module 'beacon_broadcaster' not found`)

- [ ] **Step 3: Implement minimal code**

Implement `src/0_infra/gac/modules/beacon_broadcaster.lua`:
- Envelope construction with `ver = "1.9.5"`, monotonic `seq`, epoch millisecond timestamp.
- `build_sector_beacon` matching ICD Section 3.1 schema.
- `build_dispatch_packet` matching directory announcement on CH 50004.
- `broadcast_1hz(modem, inventory, surfaceWind, sectorStatus, nowSec)` with internal `lastBroadcastTime` guard.

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/gac/modules/beacon_broadcaster.lua tests/0_infra/gac/test_beacon_broadcaster.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(gac): implement 1Hz sector aggregated beacon and dispatch broadcaster"
```

---

### Task 5: GAC Sector FSM & Handoff Protocols (`gac_fsm.lua`)

**Files:**
- Create: `src/0_infra/gac/modules/gac_fsm.lua`
- Create: `tests/0_infra/gac/test_gac_fsm.lua`

**Interfaces:**
- Consumes: `allocation_engine`, `facility_inventory`
- Produces:
  - `gac_fsm.create(config: table, inventory: table, allocator: table) -> table`
  - `fsm:handle_tower_handoff_req(packet: table) -> table`
  - `fsm:handle_aircraft_checkin(packet: table) -> table | nil, table | nil` (assignMsg, clearanceMsg)
  - `fsm:handle_pad_slot_ack(packet: table) -> table | nil` (clearanceMsg)
  - `fsm:handle_facility_update(packet: table) -> table | nil` (sectorStatusMsg)
  - `fsm:handle_abort_approach(packet: table) -> table | nil`
  - `fsm:handle_abort_clear(packet: table) -> table | nil, table | nil`
  - `fsm:handle_departure_req(packet: table) -> table`
  - `fsm:handle_departure_complete(packet: table) -> table | nil`
  - `fsm:tick(nowSec: number) -> table` (list of timeout actions)

- [ ] **Step 1: Write failing test**

```lua
-- tests/0_infra/gac/test_gac_fsm.lua
local gac_fsm = require("gac_fsm")
local facility_inventory = require("facility_inventory")
local allocation_engine = require("allocation_engine")

describe("GAC sector FSM and multi-tier handoff protocols", function()
    local cfg = {
        sectorId = "BASE_ALPHA_SECTOR_01",
        baseSecChannel = 50201,
        towerAtcChannel = 50001
    }
    local samplePads = {
        {
            facilityId = "PAD_01",
            type = "LANDING_PAD",
            tacticalChannel = 50211,
            maxSupportWeight = 40000.0,
            maxSupportRadius = 12.0,
            coordinates = { x = 1250.0, y = 65.0, z = -820.0 },
            status = "FREE"
        },
        {
            facilityId = "PAD_02",
            type = "LANDING_PAD",
            tacticalChannel = 50212,
            maxSupportWeight = 40000.0,
            maxSupportRadius = 12.0,
            coordinates = { x = 1300.0, y = 65.0, z = -800.0 },
            status = "FREE"
        }
    }

    it("Tower ATC handoff negotiation: accepts if free pads exist", function()
        local inv = facility_inventory.create(samplePads)
        local fsm = gac_fsm.create(cfg, inv, allocation_engine)
        
        local req = {
            type = "MSG_ATC_SECTOR_HANDOFF_REQ",
            payload = {
                sectorId = "BASE_ALPHA_SECTOR_01",
                aircraftId = "AIRCRAFT_01",
                airframeType = "VECTORED_VTOL",
                craftWeight = 18500.0,
                craftRadius = 5.2
            }
        }
        local ack = fsm:handle_tower_handoff_req(req)
        assert_eq(ack.type, "MSG_ATC_SECTOR_HANDOFF_ACK")
        assert_eq(ack.payload.status, "ACCEPTED")
        assert_eq(ack.payload.assignedGacChannel, 50201)
    end)

    it("Full approach flow: Checkin -> Slot Assign -> Slot Ack -> Clearance", function()
        local inv = facility_inventory.create(samplePads)
        local fsm = gac_fsm.create(cfg, inv, allocation_engine)
        
        local checkin = {
            type = "MSG_GAC_CHECKIN_REQ",
            payload = {
                sectorId = "BASE_ALPHA_SECTOR_01",
                aircraftId = "AIRCRAFT_01",
                airframeType = "VECTORED_VTOL",
                craftWeight = 18500.0,
                craftRadius = 5.2,
                currentPos = { x = 1200.0, y = 100.0, z = -750.0 }
            }
        }
        local slotAssign, immediateClearance = fsm:handle_aircraft_checkin(checkin)
        assert_not_nil(slotAssign)
        assert_eq(slotAssign.type, "MSG_ATC_SLOT_ASSIGN")
        assert_eq(slotAssign.payload.aircraftId, "AIRCRAFT_01")
        assert_eq(slotAssign.payload.facilityId, "PAD_01")
        assert_nil(immediateClearance) -- Clearance is sent after slot ACK
        
        local slotAck = {
            type = "MSG_ATC_SLOT_ACK",
            payload = {
                facilityId = "PAD_01",
                aircraftId = "AIRCRAFT_01",
                status = "ACCEPTED",
                tacticalChannel = 50211
            }
        }
        local clearance = fsm:handle_pad_slot_ack(slotAck)
        assert_not_nil(clearance)
        assert_eq(clearance.type, "MSG_GAC_APPROACH_CLEARANCE")
        assert_eq(clearance.payload.status, "CLEARED")
        assert_eq(clearance.payload.assignedFacilityId, "PAD_01")
        assert_eq(clearance.payload.assignedTacticalChannel, 50211)
    end)

    it("Go-Around flow: Isolates failed pad and redirects to secondary pad on abort clear", function()
        local inv = facility_inventory.create(samplePads)
        local fsm = gac_fsm.create(cfg, inv, allocation_engine)
        
        -- Reserve PAD_01 for AIRCRAFT_01
        inv:update_status("PAD_01", "RESERVED", "AIRCRAFT_01")
        
        -- PAD_01 sends abort
        local abortMsg = {
            type = "MSG_ABORT_APPROACH",
            payload = {
                facilityId = "PAD_01",
                aircraftId = "AIRCRAFT_01",
                reason = "DECK_UNSTABLE"
            }
        }
        fsm:handle_abort_approach(abortMsg)
        assert_eq(inv:get_facility("PAD_01").status, "GO_AROUND")
        
        -- Aircraft reports safe altitude reached
        local abortClear = {
            type = "MSG_ATC_ABORT_CLEAR",
            payload = {
                sectorId = "BASE_ALPHA_SECTOR_01",
                facilityId = "PAD_01",
                aircraftId = "AIRCRAFT_01",
                currentAltitude = 100.0
            }
        }
        local newSlotAssign, divertClearance = fsm:handle_abort_clear(abortClear)
        assert_not_nil(newSlotAssign)
        assert_eq(newSlotAssign.payload.facilityId, "PAD_02") -- Redirected to PAD_02!
    end)

    it("Slot timeout triggers pad FREE reset after 120 seconds", function()
        local inv = facility_inventory.create(samplePads)
        local fsm = gac_fsm.create(cfg, inv, allocation_engine)
        inv:update_status("PAD_01", "RESERVED", "AIRCRAFT_01")
        fsm:record_slot_assignment("PAD_01", "AIRCRAFT_01", 100.0, 120)
        
        local actions1 = fsm:tick(150.0) -- 50s elapsed
        assert_eq(#actions1, 0)
        assert_eq(inv:get_facility("PAD_01").status, "RESERVED")
        
        local actions2 = fsm:tick(221.0) -- 121s elapsed (>120s)
        assert_eq(#actions2, 1)
        assert_eq(actions2[1].type, "SLOT_TIMEOUT")
        assert_eq(inv:get_facility("PAD_01").status, "FREE")
    end)
end)
```

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: FAIL (`module 'gac_fsm' not found`)

- [ ] **Step 3: Implement minimal code**

Implement `src/0_infra/gac/modules/gac_fsm.lua`:
- Active craft and slot tracking tables.
- Implements `handle_tower_handoff_req`: validates sector capacity, returns `MSG_ATC_SECTOR_HANDOFF_ACK`.
- Implements `handle_aircraft_checkin`: executes `allocation_engine.select_best_pad`, generates `MSG_ATC_SLOT_ASSIGN` for pad on $Base_{\text{sec}}+1$.
- Implements `handle_pad_slot_ack`: completes slot reservation, generates `MSG_GAC_APPROACH_CLEARANCE` for craft on $Base_{\text{sec}}+0$.
- Implements `handle_facility_update`: updates inventory status, generates `MSG_GAC_SECTOR_STATUS` for Tower ATC on `50002`.
- Implements `handle_abort_approach`: isolates pad to `GO_AROUND`.
- Implements `handle_abort_clear`: selects secondary free pad and initiates secondary slot assign.
- Implements `handle_departure_req`: approves clearance to Tower ATC `50001`.
- Implements `handle_departure_complete`: resets pad to `FREE`.
- Implements `tick(nowSec)`: checks for 60s checkin and 120s slot expiration, resetting abandoned pads.

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/gac/modules/gac_fsm.lua tests/0_infra/gac/test_gac_fsm.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(gac): implement sector FSM and multi-tier handoff protocol engine"
```

---

### Task 6: Terminal & Monitor TUI Dashboard & Operator Controls (`tui_view.lua`)

**Files:**
- Create: `src/0_infra/gac/modules/tui_view.lua`
- Create: `tests/0_infra/gac/test_tui_view.lua`

**Interfaces:**
- Consumes: `term`, `colors`, `keys`
- Produces:
  - `tui_view.create(termDev: table, monitorDev: table | nil) -> table`
  - `tui:set_active_tab(tabIndex: number) -> void`
  - `tui:add_log(entry: string) -> void`
  - `tui:render(state: table) -> void`
  - `tui:handle_key(key: number, char: string | nil, state: table) -> string | nil, any`
  - `tui:handle_touch(x: number, y: number, state: table) -> string | nil, any`

- [ ] **Step 1: Write failing test**

```lua
-- tests/0_infra/gac/test_tui_view.lua
local tui_view = require("tui_view")

describe("GAC 3-tab TUI view and operator controls", function()
    local mockTerm = {
        getSize = function() return 51, 19 end,
        clear = function() end,
        setCursorPos = function(x, y) end,
        setTextColor = function(c) end,
        setBackgroundColor = function(c) end,
        write = function(text) end
    }

    it("initializes with Tab 1 active and switches tabs via method or key", function()
        local tui = tui_view.create(mockTerm)
        assert_eq(tui.activeTab, 1)
        
        tui:handle_key(keys.two, "2", {})
        assert_eq(tui.activeTab, 2)
        
        tui:handle_key(keys.three, "3", {})
        assert_eq(tui.activeTab, 3)
    end)

    it("dispatches operator action events: Maint, Free, Emergency", function()
        local tui = tui_view.create(mockTerm)
        tui.activeTab = 2
        tui.selectedFacilityIndex = 1
        
        local actM, dataM = tui:handle_key(keys.m, "m", {})
        assert_eq(actM, "TOGGLE_MAINTENANCE")
        
        local actF, dataF = tui:handle_key(keys.f, "f", {})
        assert_eq(actF, "FORCE_FREE")
        
        local actE, dataE = tui:handle_key(keys.e, "e", {})
        assert_eq(actE, "TOGGLE_EMERGENCY")
    end)

    it("translates touch events on tab header to tab change", function()
        local tui = tui_view.create(mockTerm)
        -- Tab bar is at Y=2: [1: OVERVIEW] is at X=1~15, [2: FACILITIES] at X=18~32
        local act, data = tui:handle_touch(20, 2, {})
        assert_eq(tui.activeTab, 2)
    end)

    it("manages circular log buffer up to 50 items", function()
        local tui = tui_view.create(mockTerm)
        for i = 1, 60 do
            tui:add_log("Log message " .. i)
        end
        assert_eq(#tui.logs, 50)
        assert_eq(tui.logs[#tui.logs], "Log message 60")
    end)
end)
```

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: FAIL (`module 'tui_view' not found`)

- [ ] **Step 3: Implement minimal code**

Implement `src/0_infra/gac/modules/tui_view.lua`:
- Render 51x19 layout with Header (Y=1), Tab Bar (Y=2), Content Area (Y=3..18), and Shortcut Bar (Y=19).
- Support dual output: draw to `termDev` and mirror to `monitorDev` if present.
- Tab 1: Sector metrics, active traffic queue.
- Tab 2: Facility list with cursor selection (`↑`/`↓`), status color coding.
- Tab 3: 50-item rolling log buffer.
- Key bindings: `1-3` (tabs), `↑/↓` (cursor), `M` (`TOGGLE_MAINTENANCE`), `F` (`FORCE_FREE`), `W` (`WAVE_OFF`), `E` (`TOGGLE_EMERGENCY`), `A` (`ADD_FACILITY`), `D` (`DELETE_FACILITY`).

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/gac/modules/tui_view.lua tests/0_infra/gac/test_tui_view.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(gac): implement 3-tab dual-display TUI console and operator controls"
```

---

### Task 7: Independent Main Application & Config (`main.lua`, `config.lua`)

**Files:**
- Create: `src/0_infra/gac/config.lua`
- Create: `src/0_infra/gac/main.lua`
- Create: `tests/0_infra/gac/test_main_integration.lua`

**Interfaces:**
- Consumes: all GAC modules, `peripheral`, `os.pullEventRaw`
- Produces: Standalone entrypoint runnable directly or via startup script

- [ ] **Step 1: Write failing test**

```lua
-- tests/0_infra/gac/test_main_integration.lua
local config_loader = require("config_loader")
local facility_inventory = require("facility_inventory")
local allocation_engine = require("allocation_engine")
local beacon_broadcaster = require("beacon_broadcaster")
local gac_fsm = require("gac_fsm")

describe("GAC main application module integration smoke test", function()
    it("wires all modules and processes one complete event cycle synchronously", function()
        local cfg = config_loader.get_default_config()
        local inv = facility_inventory.create(cfg.facilities)
        local fsm = gac_fsm.create(cfg, inv, allocation_engine)
        local bc = beacon_broadcaster.create(cfg)
        
        -- Simulate checkin packet reception
        local checkinPkt = {
            ver = "1.9.5",
            type = "MSG_GAC_CHECKIN_REQ",
            time = 1000,
            payload = {
                sectorId = cfg.sectorId,
                aircraftId = "TEST_CRAFT",
                craftWeight = 10000,
                craftRadius = 4,
                currentPos = { x = 1200, y = 65, z = -800 }
            }
        }
        local slotAssign = fsm:handle_aircraft_checkin(checkinPkt)
        assert_not_nil(slotAssign)
        assert_eq(slotAssign.type, "MSG_ATC_SLOT_ASSIGN")
        
        -- Beacon generation
        local bPkt = bc:build_sector_beacon(inv, { speed = 2, direction = 180 }, "OPERATIONAL")
        assert_eq(bPkt.type, "MSG_FACILITY_BEACON")
        assert_eq(bPkt.payload.facilitiesSummary.freeLandingPads, 1) -- 1 free out of 2
    end)
end)
```

- [ ] **Step 2: Run test to confirm failure**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: FAIL (until modules are wired)

- [ ] **Step 3: Implement minimal code**

Implement `src/0_infra/gac/config.lua` and `src/0_infra/gac/main.lua`:
- `config.lua`: returns default configuration table.
- `main.lua`:
  - Discovers wireless modem and optional monitor.
  - Opens channels: `50002` (Tower ATC), `50004` (Dispatch), $Base_{\text{sec}}+0$ (Comm), $Base_{\text{sec}}+1$ (Local Backbone).
  - Initializes inventory, FSM, beacon broadcaster, and TUI view.
  - Runs 20Hz non-blocking event loop intercepting `modem_message`, `timer`, `key`, `char`, `monitor_touch`, `terminate`.
  - Safely handles operator overrides, saves config changes atomically, and cleans up open channels on exit.

- [ ] **Step 4: Run test to confirm pass**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: PASS (`7/7 PASS`)

- [ ] **Step 5: Commit**

```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/gac/config.lua src/0_infra/gac/main.lua tests/0_infra/gac/test_main_integration.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(gac): implement independent main application entry and non-blocking loop"
```

---

### Task 8: Unified Installer Manifest Registration & Full Suite Verification

**Files:**
- Modify: `src/0_development/installer/modules/manifest.lua`
- Modify: `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md`
- Modify: `TASK.md`

**Interfaces:**
- Consumes: `tools/run_unit_tests.py`, `tools/validate_lua_syntax.py`, `tools/verify_all_specs.py`, `tools/verify_spec_status.py`
- Produces: GAC registered in installer, spec promoted to `Implemented`, TASK.md updated

- [ ] **Step 1: Register GAC in Unified Installer manifest**

Edit `src/0_development/installer/modules/manifest.lua` to register `gac` module under `0_infra/gac` with all module files, main entrypoint, and startup hook generation.

- [ ] **Step 2: Run all unit tests**

Run: `python tools/run_unit_tests.py --require-tests --clean-orphans`
Expected: PASS on all targets (8+ targets, 90+ tests passing).

- [ ] **Step 3: Run harness regression tests**

Run: `python -m unittest discover -s tests/harness -p "test_*.py"`
Expected: PASS (`24/24 PASS`).

- [ ] **Step 4: Run Lua 5.2 syntax and spec verifiers**

Run: `python tools/validate_lua_syntax.py`
Expected: PASS across all Lua files.

Run: `python tools/verify_all_specs.py`
Expected: `SCAN RESULT: ALL 12 SPECS 100% CLEAN (0 Errors, 0 Warnings)`.

- [ ] **Step 5: Promote GAC Specification to `Implemented`**

Update `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md`:
- `문서 상태 (Status)`: `Approved` $\to$ `Implemented`
- `최종 수정일 (Date)`: `2026-11-08`

Run: `python tools/verify_spec_status.py`
Expected: Clean status check.

- [ ] **Step 6: Update TASK.md & Commit**

Update `TASK.md` marking `TASK-101` subtasks as complete (`[x]`).
Commit changes:
```bash
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/installer/modules/manifest.lua docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md TASK.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(gac): register 0_infra/gac in manifest and complete TASK-101"
```
