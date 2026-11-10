# GAC Dedicated Facility & 2-Stage Multi-Attribute Allocation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete GAC (`src/0_infra/gac/`) support for dedicated facilities (`dedicatedCraftIds`, `dedicatedAirframeTypes`), including config schema validation, public-only free pad beacon summary counting, `FACILITY_DEDICATED` rejection and Tower ATC handoff filtering, and 3-Tab TUI `[DED: ...]`/`PUBLIC` display with dynamic facility/dedicated attribute management.

**Architecture:** Extends the existing modular GAC runtime in `src/0_infra/gac/modules/` without adding external dependencies. `config_loader.lua` validates dedicated fields; `facility_inventory.lua` isolates dedicated pads from public `freeLandingPads`/`freeRunways` beacon counts and exposes dedicated attribute mutators; `allocation_engine.lua` and `gac_fsm.lua` enforce `FACILITY_DEDICATED` rejection semantics across check-in and Tower ATC handoff; `tui_view.lua` and `main.lua` render Cyan-highlighted `[DED: ...]`/`PUBLIC` badges and persist operator facility edits.

**Tech Stack:** CC:Tweaked Lua 5.2 (Cobalt VM), Ender Modem RF (`CH 50001~50004`, $Base_{\text{sec}}+0$, $Base_{\text{sec}}+1$), Advanced Computer/Monitor API (`term`, `colors`), CraftOS-PC Headless Unit Test Runner (`tools/run_unit_tests.py`).

**Spec:** [GAC_PROGRAM_SPECIFICATION_AND_ICD.md](../../specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md) (v1.4.1 `Approved`)

## Global Constraints

- **Multi-Codebase Autonomy**: `src/0_infra/gac/` must remain 100% self-contained with zero cross-subsystem `require` calls.
- **Standard Envelope & Zero-Fallback**: All packets use `ver = "1.9.5"`, `domainId`, `seq`, `type`, `time`, `payload` with single-key standard field names (`dedicatedCraftIds`, `dedicatedAirframeTypes`, `preferredFacilityId`, `isEmergency`, `rejectReason`, `reason`).
- **Beacon Public-Only Free Count**: `facilitiesSummary.freeLandingPads` and `facilitiesSummary.freeRunways` must exclude dedicated facilities even when `status == "FREE"`, while `totalLandingPads` and `totalRunways` include both public and dedicated facilities.
- **Strict Rejection Reason Distinction**: `select_best_pad` and `handle_tower_handoff_req` must distinguish `"FACILITY_DEDICATED"`, `"OVERWEIGHT"`, `"SECTOR_ALL_OCCUPIED"`, and `"DECK_DANGEROUS"`.
- **TUI Dual-Display & 51x19 Resolution**: Tab 2 (`FACILITIES`) must fit within 51x19 characters, displaying `[DED: <id/type>]` or `PUBLIC` and highlighting unselected dedicated facilities in `colors.cyan`.

## Review Focus

1. **Malformed Dedicated Config Fields**: If a facility entry in `config.json` contains a numeric, boolean, or empty/non-string table element in `dedicatedCraftIds` or `dedicatedAirframeTypes`, `config_loader.validate_config` must reject it with `"INVALID_DEDICATED_CRAFT_IDS"` or `"INVALID_DEDICATED_AIRFRAME_TYPES"`.
2. **False Free-Pad Advertisement on Sector Beacon**: If a sector has 1 `FREE` public pad and 1 `FREE` dedicated pad, `inventory:get_summary()` must report `totalLandingPads = 2` and `freeLandingPads = 1` so unprivileged aircraft do not divert into a sector with zero public capacity.
3. **Emergency Commandeering Prematurely Seizing Dedicated Pad**: When an emergency aircraft (`isEmergency = true`) arrives while both a public pad and a dedicated pad are `FREE`, GAC must allocate the public pad first and only commandeer the dedicated pad when zero public pads are `FREE`.
4. **Unauthorized `preferredFacilityId` vs. No Public Fallback**: When an unprivileged craft requests a dedicated pad via `preferredFacilityId`, GAC must redirect it to an available public pad if one exists, or reject with `"FACILITY_DEDICATED"` (not `"OVERWEIGHT"`) when no public pad is available.
5. **Tower Handoff Accepting Unprivileged Craft into Dedicated-Only Sector**: `gac_fsm:handle_tower_handoff_req` must pass `payload` (`craftReq`) into allocation filtering so an unprivileged craft is rejected at Tier 1 handoff (`status = "REJECTED"`, `rejectReason = "FACILITY_DEDICATED"`) when only dedicated pads are `FREE`.

---

## File Structure

- Modify: `src/0_infra/gac/modules/config_loader.lua` — Validate optional `dedicatedCraftIds` and `dedicatedAirframeTypes` (string or array of non-empty strings) per facility entry.
- Modify: `src/0_infra/gac/modules/facility_inventory.lua` — Add `is_facility_dedicated(fac)`, `inv:is_dedicated(facilityId)`, `inv:update_dedicated(facilityId, dedicatedCraftIds, dedicatedAirframeTypes)`, and exclude dedicated facilities from `freeLandingPads` and `freeRunways` in `inv:get_summary()`.
- Modify: `src/0_infra/gac/modules/allocation_engine.lua` — Refine `select_best_pad` failure classification to return `"FACILITY_DEDICATED"` when an unauthorized `preferredFacilityId` or dedicated-only free pool blocks allocation, and prioritize public pads over dedicated pads during `isEmergency` when public pads are available.
- Modify: `src/0_infra/gac/modules/gac_fsm.lua` — Pass `payload` (`craftReq`) in `handle_tower_handoff_req` to `alloc.select_best_pad` and propagate `"FACILITY_DEDICATED"` / `"OVERWEIGHT"` / `"SECTOR_ALL_OCCUPIED"` / `"DECK_DANGEROUS"` in `MSG_ATC_SECTOR_HANDOFF_ACK`.
- Modify: `src/0_infra/gac/modules/tui_view.lua` — Add `tui_view.format_dedicated_badge(fac)`, render `[DED: ...]`/`PUBLIC` with `colors.cyan` highlight on Tab 2, add `[P]` (`EDIT_DEDICATED`) key binding, and provide `tui_view.apply_operator_action(...)` helper for testable facility add/delete/dedicated/state mutations.
- Modify: `src/0_infra/gac/main.lua` — Wire `ADD_FACILITY`, `DELETE_FACILITY`, `EDIT_DEDICATED`, and local backbone `MSG_ATC_FACILITY_UPDATE` synchronization into the event loop via `tui_view.apply_operator_action`.
- Modify: `tests/0_infra/gac/test_config_loader.lua` — Pin schema validation tests for `dedicatedCraftIds` and `dedicatedAirframeTypes`.
- Modify: `tests/0_infra/gac/test_facility_inventory.lua` — Pin dedicated detection, `update_dedicated`, and beacon summary public-only `freeLandingPads`/`freeRunways` counting.
- Modify: `tests/0_infra/gac/test_allocation_engine.lua` — Pin `dedicatedCraftIds` priority/fallback, `isEmergency` public-first vs. last-resort dedicated commandeering, and `"FACILITY_DEDICATED"` rejection cases.
- Modify: `tests/0_infra/gac/test_gac_fsm.lua` — Pin `handle_tower_handoff_req` and `handle_aircraft_checkin` with dedicated facilities and `"FACILITY_DEDICATED"` / `"OVERWEIGHT"` rejection reasons.
- Modify: `tests/0_infra/gac/test_tui_view.lua` — Pin `[DED: ...]` / `PUBLIC` formatting, `colors.cyan` row rendering, `[A]`/`[D]`/`[P]` key bindings, and operator facility management actions.
- Modify: `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md` — Promote Status from `Approved` to `Implemented` upon verification pass.

---

### Task 1: Dedicated Facility Config Validation & Inventory Summary Isolation (`TASK-114-2`)

**Files:**
- Modify: `src/0_infra/gac/modules/config_loader.lua:49-70`
- Modify: `src/0_infra/gac/modules/facility_inventory.lua:6-148`
- Test: `tests/0_infra/gac/test_config_loader.lua`
- Test: `tests/0_infra/gac/test_facility_inventory.lua`

**Interfaces:**
- Consumes: `fs`, `textutils`
- Produces:
  - `config_loader.validate_dedicated_field(val: any) -> boolean`
  - `config_loader.validate_config(cfg: table) -> boolean, string | nil`
  - `facility_inventory.is_facility_dedicated(fac: table) -> boolean`
  - `inv:is_dedicated(facilityId: string) -> boolean`
  - `inv:update_dedicated(facilityId: string, dedicatedCraftIds: string | table | nil, dedicatedAirframeTypes: string | table | nil) -> boolean, string | nil`
  - `inv:get_summary() -> table` (where `freeLandingPads` and `freeRunways` count only non-dedicated `FREE` facilities)

- [ ] **Step 1: Write failing tests in `tests/0_infra/gac/test_config_loader.lua` and `tests/0_infra/gac/test_facility_inventory.lua`**

```lua
-- Append inside describe(...) in tests/0_infra/gac/test_config_loader.lua
    it("accepts valid string or string-array dedicatedCraftIds and dedicatedAirframeTypes", function()
        local cfg = config_loader.get_default_config()
        cfg.facilities[1].dedicatedCraftIds = "VTOL_VIP_01"
        cfg.facilities[2].dedicatedCraftIds = { "VTOL_VIP_01", "DRONE_SCOUT_02" }
        cfg.facilities[2].dedicatedAirframeTypes = { "ADVANCED_VTOL", "VECTORED_VTOL" }

        local ok, err = config_loader.validate_config(cfg)
        assert_true(ok)
        assert_nil(err)
    end)

    it("rejects malformed dedicatedCraftIds or dedicatedAirframeTypes in facility config", function()
        local cfg1 = config_loader.get_default_config()
        cfg1.facilities[1].dedicatedCraftIds = 12345
        local ok1, err1 = config_loader.validate_config(cfg1)
        assert_false(ok1)
        assert_eq(err1, "INVALID_DEDICATED_CRAFT_IDS")

        local cfg2 = config_loader.get_default_config()
        cfg2.facilities[1].dedicatedAirframeTypes = { "VECTORED_VTOL", 99 }
        local ok2, err2 = config_loader.validate_config(cfg2)
        assert_false(ok2)
        assert_eq(err2, "INVALID_DEDICATED_AIRFRAME_TYPES")
    end)
```

```lua
-- Append inside describe(...) in tests/0_infra/gac/test_facility_inventory.lua
    it("excludes dedicated pads and runways from freeLandingPads and freeRunways in summary", function()
        local mixedFacilities = {
            {
                facilityId = "PAD_PUB_01",
                type = "LANDING_PAD",
                status = "FREE",
                maxSupportWeight = 30000.0,
                maxSupportRadius = 10.0
            },
            {
                facilityId = "PAD_DED_VIP",
                type = "LANDING_PAD",
                status = "FREE",
                maxSupportWeight = 50000.0,
                maxSupportRadius = 15.0,
                dedicatedCraftIds = { "VIP_CRAFT_01" }
            },
            {
                facilityId = "RWY_DED_01",
                type = "RUNWAY",
                status = "FREE",
                dedicatedAirframeTypes = "FIXED_WING"
            }
        }
        local inv = facility_inventory.create(mixedFacilities)
        assert_false(inv:is_dedicated("PAD_PUB_01"))
        assert_true(inv:is_dedicated("PAD_DED_VIP"))
        assert_true(inv:is_dedicated("RWY_DED_01"))

        local summary = inv:get_summary()
        assert_eq(summary.totalLandingPads, 2)
        assert_eq(summary.freeLandingPads, 1)
        assert_eq(summary.totalRunways, 1)
        assert_eq(summary.freeRunways, 0)
        assert_eq(summary.maxSupportWeight, 50000.0)
        assert_eq(summary.maxSupportRadius, 15.0)
    end)

    it("updates dedicated attributes dynamically on an existing facility", function()
        local inv = facility_inventory.create(samplePads)
        assert_false(inv:is_dedicated("PAD_02"))

        local ok, err = inv:update_dedicated("PAD_02", { "DRONE_01" }, "QUADROTOR")
        assert_true(ok)
        assert_nil(err)
        assert_true(inv:is_dedicated("PAD_02"))
        assert_eq(inv:get_summary().freeLandingPads, 1)

        local okClear = inv:update_dedicated("PAD_02", nil, nil)
        assert_true(okClear)
        assert_false(inv:is_dedicated("PAD_02"))
        assert_eq(inv:get_summary().freeLandingPads, 2)
    end)
```

- [ ] **Step 2: Run unit tests to verify failure**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: FAIL on the new config validation and inventory dedicated summary tests.

- [ ] **Step 3: Implement `validate_dedicated_field` in `src/0_infra/gac/modules/config_loader.lua` and `is_facility_dedicated` / `is_dedicated` / `update_dedicated` / `get_summary` filtering in `src/0_infra/gac/modules/facility_inventory.lua`**

In `src/0_infra/gac/modules/config_loader.lua`:
- `config_loader.validate_dedicated_field(val)` returns `true` if `val == nil`, if `type(val) == "string"`, or if `type(val) == "table"` where every indexed element `1..#val` has `type(v) == "string" and v ~= ""` (and no non-array keys exist).
- In `config_loader.validate_config(cfg)`, iterate `ipairs(cfg.facilities)`: verify `config_loader.validate_dedicated_field(fac.dedicatedCraftIds)` (else return `false, "INVALID_DEDICATED_CRAFT_IDS"`) and `config_loader.validate_dedicated_field(fac.dedicatedAirframeTypes)` (else return `false, "INVALID_DEDICATED_AIRFRAME_TYPES"`).

In `src/0_infra/gac/modules/facility_inventory.lua`:
- `facility_inventory.is_facility_dedicated(fac)` returns `true` if `fac.dedicatedCraftIds` or `fac.dedicatedAirframeTypes` is a non-empty string (`~= ""`) or a table with `#t > 0`.
- `inv:is_dedicated(facilityId)` returns `facility_inventory.is_facility_dedicated(state.facilities[facilityId])`.
- `inv:update_dedicated(facilityId, dedicatedCraftIds, dedicatedAirframeTypes)` updates `fac.dedicatedCraftIds` and `fac.dedicatedAirframeTypes` (deep-cloned) or returns `false, "FACILITY_NOT_FOUND"`.
- In `inv:get_summary()`, increment `freePads` and `freeRunways` only when `fac.status == "FREE" and not state.emergencyLockdown and not facility_inventory.is_facility_dedicated(fac)`.

- [ ] **Step 4: Run unit tests to verify pass**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: PASS for all tests in `test_config_loader.lua` and `test_facility_inventory.lua`.

- [ ] **Step 5: Commit Task 1**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/gac/modules/config_loader.lua src/0_infra/gac/modules/facility_inventory.lua tests/0_infra/gac/test_config_loader.lua tests/0_infra/gac/test_facility_inventory.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(gac): validate dedicated facility schema and isolate beacon free pad summary"
```

---

### Task 2: 2-Stage Allocation `FACILITY_DEDICATED` Rejection & Tower Handoff Filtering (`TASK-114-3`)

**Files:**
- Modify: `src/0_infra/gac/modules/allocation_engine.lua:59-235`
- Modify: `src/0_infra/gac/modules/gac_fsm.lua:43-74`
- Test: `tests/0_infra/gac/test_allocation_engine.lua`
- Test: `tests/0_infra/gac/test_gac_fsm.lua`

**Interfaces:**
- Consumes: `facility_inventory`
- Produces:
  - `allocation_engine.is_dedicated_facility(pad: table) -> boolean`
  - `allocation_engine.select_best_pad(facilities: table, craftReq: table, surfaceWind: table | nil, opts: table | nil) -> table | nil, string | nil` (error reasons: `"FACILITY_DEDICATED"`, `"OVERWEIGHT"`, `"SECTOR_ALL_OCCUPIED"`, `"INVALID_ARGUMENTS"`)
  - `fsm:handle_tower_handoff_req(packet: table) -> table` (evaluates `alloc.select_best_pad(inv:get_all_facilities(), payload, cfg.surfaceWind)` and sets `rejectReason` to `"DECK_DANGEROUS"`, `"FACILITY_DEDICATED"`, `"OVERWEIGHT"`, or `"SECTOR_ALL_OCCUPIED"`)

- [ ] **Step 1: Write failing tests in `tests/0_infra/gac/test_allocation_engine.lua` and `tests/0_infra/gac/test_gac_fsm.lua`**

```lua
-- Append inside describe(...) in tests/0_infra/gac/test_allocation_engine.lua
    it("allocates dedicatedCraftIds pad with first priority and falls back to public pad when occupied", function()
        local mixedPads = {
            {
                facilityId = "PAD_PUBLIC_NEAR",
                status = "FREE",
                maxSupportWeight = 30000.0,
                maxSupportRadius = 10.0,
                coordinates = { x = 10.0, y = 64.0, z = 0.0 },
                approachHeading = 180.0
            },
            {
                facilityId = "PAD_VIP_FAR",
                status = "FREE",
                maxSupportWeight = 30000.0,
                maxSupportRadius = 10.0,
                coordinates = { x = 180.0, y = 64.0, z = 0.0 },
                approachHeading = 180.0,
                dedicatedCraftIds = { "VIP_01", "VIP_02" }
            }
        }
        local vipReq = {
            aircraftId = "VIP_02",
            airframeType = "VECTORED_VTOL",
            craftWeight = 12000.0,
            craftRadius = 5.0,
            currentPos = { x = 0.0, y = 64.0, z = 0.0 }
        }
        local best1, err1 = allocation_engine.select_best_pad(mixedPads, vipReq, { speed = 2.0, direction = 180.0 })
        assert_not_nil(best1)
        assert_nil(err1)
        assert_eq(best1.facilityId, "PAD_VIP_FAR")

        -- When dedicated pad is OCCUPIED, VIP craft falls back to public pad
        mixedPads[2].status = "OCCUPIED"
        local best2, err2 = allocation_engine.select_best_pad(mixedPads, vipReq, { speed = 2.0, direction = 180.0 })
        assert_not_nil(best2)
        assert_nil(err2)
        assert_eq(best2.facilityId, "PAD_PUBLIC_NEAR")
    end)

    it("handles unauthorized preferredFacilityId: redirects to public pad if available, else returns FACILITY_DEDICATED", function()
        local padsWithPublic = {
            {
                facilityId = "PAD_DED_ONLY",
                status = "FREE",
                maxSupportWeight = 30000.0,
                maxSupportRadius = 10.0,
                coordinates = { x = 20.0, y = 64.0, z = 0.0 },
                dedicatedCraftIds = "VIP_01"
            },
            {
                facilityId = "PAD_PUB_01",
                status = "FREE",
                maxSupportWeight = 30000.0,
                maxSupportRadius = 10.0,
                coordinates = { x = 100.0, y = 64.0, z = 0.0 }
            }
        }
        local unauthReq = {
            aircraftId = "NORMAL_CRAFT",
            airframeType = "VECTORED_VTOL",
            craftWeight = 10000.0,
            craftRadius = 4.0,
            currentPos = { x = 0.0, y = 64.0, z = 0.0 },
            preferredFacilityId = "PAD_DED_ONLY"
        }
        local fallbackPad, errFallback = allocation_engine.select_best_pad(padsWithPublic, unauthReq, { speed = 0, direction = 0 })
        assert_not_nil(fallbackPad)
        assert_nil(errFallback)
        assert_eq(fallbackPad.facilityId, "PAD_PUB_01")

        -- When public pad is occupied, unauthorized preferredFacilityId must be rejected with FACILITY_DEDICATED
        padsWithPublic[2].status = "OCCUPIED"
        local deniedPad, errDenied = allocation_engine.select_best_pad(padsWithPublic, unauthReq, { speed = 0, direction = 0 })
        assert_nil(deniedPad)
        assert_eq(errDenied, "FACILITY_DEDICATED")
    end)

    it(" enforces emergency commandeering only when no public pad is FREE", function()
        local sectorPads = {
            {
                facilityId = "PAD_DED_CLOSER",
                status = "FREE",
                maxSupportWeight = 30000.0,
                maxSupportRadius = 10.0,
                coordinates = { x = 10.0, y = 64.0, z = 0.0 },
                dedicatedCraftIds = "VIP_01"
            },
            {
                facilityId = "PAD_PUB_FARTHER",
                status = "FREE",
                maxSupportWeight = 30000.0,
                maxSupportRadius = 10.0,
                coordinates = { x = 150.0, y = 64.0, z = 0.0 }
            }
        }
        local emgReq = {
            aircraftId = "EMG_CRAFT",
            airframeType = "VECTORED_VTOL",
            craftWeight = 10000.0,
            craftRadius = 4.0,
            currentPos = { x = 0.0, y = 64.0, z = 0.0 },
            isEmergency = true
        }
        -- Public pad is FREE -> must NOT commandeer dedicated pad even though dedicated pad is closer
        local bestPub, errPub = allocation_engine.select_best_pad(sectorPads, emgReq, { speed = 0, direction = 0 })
        assert_not_nil(bestPub)
        assert_nil(errPub)
        assert_eq(bestPub.facilityId, "PAD_PUB_FARTHER")

        -- Public pad becomes OCCUPIED -> emergency craft commandeers dedicated pad as last resort
        sectorPads[2].status = "OCCUPIED"
        local bestDed, errDed = allocation_engine.select_best_pad(sectorPads, emgReq, { speed = 0, direction = 0 })
        assert_not_nil(bestDed)
        assert_nil(errDed)
        assert_eq(bestDed.facilityId, "PAD_DED_CLOSER")
    end)
```

```lua
-- Append inside describe(...) in tests/0_infra/gac/test_gac_fsm.lua
    it("Tower ATC handoff & Checkin reject unauthorized craft with FACILITY_DEDICATED when only dedicated pads are free", function()
        local dedOnlyPads = {
            {
                facilityId = "PAD_VIP_ONLY",
                type = "LANDING_PAD",
                tacticalChannel = 50211,
                maxSupportWeight = 40000.0,
                maxSupportRadius = 12.0,
                coordinates = { x = 1250.0, y = 65.0, z = -820.0 },
                status = "FREE",
                dedicatedCraftIds = { "VIP_CRAFT_01" }
            }
        }
        local inv = facility_inventory.create(dedOnlyPads)
        local fsm = gac_fsm.create(cfg, inv, allocation_engine)

        local handoffReq = {
            type = "MSG_ATC_SECTOR_HANDOFF_REQ",
            payload = {
                sectorId = "BASE_ALPHA_SECTOR_01",
                aircraftId = "REGULAR_CRAFT",
                airframeType = "VECTORED_VTOL",
                craftWeight = 15000.0,
                craftRadius = 5.0,
                isEmergency = false
            }
        }
        local handoffAck = fsm:handle_tower_handoff_req(handoffReq)
        assert_eq(handoffAck.payload.status, "REJECTED")
        assert_eq(handoffAck.payload.rejectReason, "FACILITY_DEDICATED")
        assert_nil(handoffAck.payload.assignedGacChannel)

        local checkinReq = {
            type = "MSG_GAC_CHECKIN_REQ",
            payload = {
                sectorId = "BASE_ALPHA_SECTOR_01",
                aircraftId = "REGULAR_CRAFT",
                airframeType = "VECTORED_VTOL",
                craftWeight = 15000.0,
                craftRadius = 5.0,
                currentPos = { x = 1200.0, y = 100.0, z = -750.0 },
                preferredFacilityId = "PAD_VIP_ONLY",
                isEmergency = false
            }
        }
        local slotAssign, clearance = fsm:handle_aircraft_checkin(checkinReq)
        assert_nil(slotAssign)
        assert_not_nil(clearance)
        assert_eq(clearance.payload.status, "DENIED")
        assert_eq(clearance.payload.reason, "FACILITY_DEDICATED")
    end)
```

- [ ] **Step 2: Run unit tests to verify failure**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: FAIL on `"FACILITY_DEDICATED"` rejection reason and `handle_tower_handoff_req` dedicated filtering.

- [ ] **Step 3: Implement `FACILITY_DEDICATED` rejection classification in `src/0_infra/gac/modules/allocation_engine.lua` and `craftReq` filtering in `src/0_infra/gac/modules/gac_fsm.lua`**

In `src/0_infra/gac/modules/allocation_engine.lua`:
- Extract helper `allocation_engine.is_dedicated_facility(pad)` returning `true` when `pad.dedicatedCraftIds` or `pad.dedicatedAirframeTypes` is a non-empty string or non-empty table.
- In `select_best_pad`, when `#validCandidates == 0`:
  1. Check if `craftReq.preferredFacilityId` matches a facility `prefFac` in `facilities` where `allocation_engine.is_dedicated_facility(prefFac)` and `not allocation_engine.isEligible(prefFac, craftReq, facilities)` -> return `nil, "FACILITY_DEDICATED"`.
  2. Scan `facilities` for `fac.status == "FREE"`: track `hasFreePad = true`, and if `(fac.maxSupportWeight or 0) >= craftWeight and (fac.maxSupportRadius or 0) >= craftRadius` and `allocation_engine.is_facility_compatible(fac.facilityType or fac.type or "LANDING_PAD", craftReq.airframeType)` and `allocation_engine.is_dedicated_facility(fac)` -> return `nil, "FACILITY_DEDICATED"`.
  3. If `hasFreePad` -> return `nil, "OVERWEIGHT"`, else -> return `nil, "SECTOR_ALL_OCCUPIED"`.

In `src/0_infra/gac/modules/gac_fsm.lua`:
- In `fsm:handle_tower_handoff_req(packet)`:
  - If `inv:is_emergency_lockdown()` is true, set `accepted = false`, `rejectReason = "DECK_DANGEROUS"`.
  - Otherwise, call `local bestPad, errReason = alloc.select_best_pad(inv:get_all_facilities(), payload, cfg.surfaceWind)`. Set `accepted = (bestPad ~= nil)` and `rejectReason = errReason`.

- [ ] **Step 4: Run unit tests to verify pass**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: PASS for all tests in `test_allocation_engine.lua`, `test_gac_advanced_vtol.lua`, and `test_gac_fsm.lua`.

- [ ] **Step 5: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/gac/modules/allocation_engine.lua src/0_infra/gac/modules/gac_fsm.lua tests/0_infra/gac/test_allocation_engine.lua tests/0_infra/gac/test_gac_fsm.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(gac): implement FACILITY_DEDICATED rejection and tower handoff craftReq filtering"
```

---

### Task 3: 3-Tab TUI Console `DED`/`PUBLIC` Display & Facility Management Wiring (`TASK-114-4`)

**Files:**
- Modify: `src/0_infra/gac/modules/tui_view.lua:94-205`
- Modify: `src/0_infra/gac/main.lua:174-238`
- Test: `tests/0_infra/gac/test_tui_view.lua`
- Test: `tests/0_infra/gac/test_main_integration.lua`

**Interfaces:**
- Consumes: `facility_inventory`, `config_loader`, `term`, `colors`, `keys`
- Produces:
  - `tui_view.format_dedicated_badge(fac: table) -> string, boolean` (returns badge text such as `"[DED: VTOL_01]"` or `"PUBLIC"`, and boolean `isDedicated`)
  - `tui_view.apply_operator_action(action: string, indexOrData: any, ctx: table) -> boolean, string | nil`
  - `view:handle_key(key: number | nil, char: string | nil, state: table) -> string | nil, any` (supports `[A]` `ADD_FACILITY`, `[D]` `DELETE_FACILITY`, `[P]` `EDIT_DEDICATED`)

- [ ] **Step 1: Write failing tests in `tests/0_infra/gac/test_tui_view.lua` and `tests/0_infra/gac/test_main_integration.lua`**

```lua
-- Append inside describe(...) in tests/0_infra/gac/test_tui_view.lua
    it("formats DED/PUBLIC badges and renders Tab 2 with Cyan highlight for dedicated facilities", function()
        local badge1, isDed1 = tui_view.format_dedicated_badge({ facilityId = "P1", dedicatedCraftIds = { "VTOL_01" } })
        assert_eq(badge1, "[DED: VTOL_01]")
        assert_true(isDed1)

        local badge2, isDed2 = tui_view.format_dedicated_badge({ facilityId = "P2", dedicatedAirframeTypes = "DRONE" })
        assert_eq(badge2, "[DED: DRONE]")
        assert_true(isDed2)

        local badge3, isDed3 = tui_view.format_dedicated_badge({ facilityId = "P3" })
        assert_eq(badge3, "PUBLIC")
        assert_false(isDed3)

        local writtenLines = {}
        local usedColors = {}
        local captureTerm = {
            getSize = function() return 51, 19 end,
            clear = function() end,
            setCursorPos = function(x, y) end,
            setTextColor = function(c) table.insert(usedColors, c) end,
            setBackgroundColor = function(c) end,
            write = function(text) table.insert(writtenLines, tostring(text)) end
        }
        local tui = tui_view.create(captureTerm)
        tui:set_active_tab(2)
        tui.selectedFacilityIndex = 1 -- Select row 1 so row 2 is unselected dedicated
        tui:render({
            config = { sectorId = "ALPHA", baseSecChannel = 50201 },
            facilities = {
                { facilityId = "PAD_01", type = "LANDING_PAD", status = "FREE", tacticalChannel = 50211 },
                { facilityId = "PAD_02", type = "LANDING_PAD", status = "FREE", tacticalChannel = 50212, dedicatedCraftIds = "VTOL_01" }
            }
        })

        local joined = table.concat(writtenLines, "\n")
        assert_true(string.find(joined, "PUBLIC", 1, true) ~= nil)
        assert_true(string.find(joined, "[DED: VTOL_01]", 1, true) ~= nil)

        local hasCyan = false
        for _, col in ipairs(usedColors) do
            if col == colors.cyan then hasCyan = true break end
        end
        assert_true(hasCyan)
    end)

    it("dispatches ADD_FACILITY, DELETE_FACILITY, and EDIT_DEDICATED keys and applies operator mutations", function()
        local tui = tui_view.create(mockTerm)
        tui.activeTab = 2
        tui.selectedFacilityIndex = 2

        local actA = tui:handle_key(keys.a, "a", {})
        assert_eq(actA, "ADD_FACILITY")

        local actD, idxD = tui:handle_key(keys.d, "d", {})
        assert_eq(actD, "DELETE_FACILITY")
        assert_eq(idxD, 2)

        local actP, idxP = tui:handle_key(keys.p, "p", {})
        assert_eq(actP, "EDIT_DEDICATED")
        assert_eq(idxP, 2)
    end)
```

```lua
-- Append inside describe(...) in tests/0_infra/gac/test_main_integration.lua
    it("executes operator facility add, dedicated attribute update, and delete with config persistence", function()
        local tui_view = require("tui_view")
        local path = sdk.temp_path("gac_op_test.json")
        local cfg = config_loader.get_default_config()
        local inv = facility_inventory.create(cfg.facilities)
        local tui = tui_view.create()

        local ctx = {
            inventory = inv,
            config = cfg,
            configPath = path,
            configLoader = config_loader,
            tui = tui
        }

        -- 1. Add facility with dedicatedAirframeTypes
        local okAdd = tui_view.apply_operator_action("ADD_FACILITY", {
            facilityId = "PAD_DED_03",
            type = "LANDING_PAD",
            tacticalChannel = 50213,
            maxSupportWeight = 30000.0,
            maxSupportRadius = 10.0,
            coordinates = { x = 1350.0, y = 65.0, z = -810.0 },
            status = "FREE",
            dedicatedAirframeTypes = { "ADVANCED_VTOL" }
        }, ctx)
        assert_true(okAdd)
        assert_true(inv:is_dedicated("PAD_DED_03"))

        -- 2. Edit dedicated attributes on index 1 (PAD_01)
        local okEdit = tui_view.apply_operator_action("EDIT_DEDICATED", 1, ctx, {
            dedicatedCraftIds = { "VIP_CRAFT_99" },
            dedicatedAirframeTypes = nil
        })
        assert_true(okEdit)
        assert_true(inv:is_dedicated("PAD_01"))

        -- 3. Delete facility at index 3 (PAD_DED_03)
        local okDel = tui_view.apply_operator_action("DELETE_FACILITY", 3, ctx)
        assert_true(okDel)
        assert_nil(inv:get_facility("PAD_DED_03"))

        -- Verify persisted config reflects changes
        local reloaded = config_loader.load_config(path)
        assert_eq(#reloaded.facilities, 2)
        assert_eq(reloaded.facilities[1].dedicatedCraftIds[1], "VIP_CRAFT_99")
    end)
```

- [ ] **Step 2: Run unit tests to verify failure**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: FAIL with `format_dedicated_badge` / `apply_operator_action` / `EDIT_DEDICATED` undefined.

- [ ] **Step 3: Implement `format_dedicated_badge`, Tab 2 `DEDICATED` column + Cyan highlight, `[P]` binding, and `apply_operator_action` in `src/0_infra/gac/modules/tui_view.lua` and `src/0_infra/gac/main.lua`**

In `src/0_infra/gac/modules/tui_view.lua`:
- Implement `tui_view.format_dedicated_badge(fac)`:
  - Extract first string from `fac.dedicatedCraftIds` (string or table `[1]`); if non-empty, return `"[DED: " .. id .. "]"`, `true`.
  - Else extract first string from `fac.dedicatedAirframeTypes` (string or table `[1]`); if non-empty, return `"[DED: " .. af .. "]"`, `true`.
  - Else return `"PUBLIC"`, `false`.
- In `render_to_device` Tab 2 (`view.activeTab == 2`):
  - Update header at `Y=4`: `"ID     TYPE  STATUS    DEDICATED      CRAFT   CH"`
  - For each facility row, compute `local dedBadge, isDedicated = tui_view.format_dedicated_badge(fac)`.
  - Set row foreground `local fg = isSelected and colors.black or (isDedicated and colors.cyan or colors.white)`.
  - Format row including `dedBadge` so both `"PUBLIC"` and `"[DED: ...]"` render cleanly within 51 chars.
- In `view:handle_key(key, char, state)`:
  - Add `elseif key == keys.p or char == "p" or char == "P" then return "EDIT_DEDICATED", self.selectedFacilityIndex`.
- Implement `tui_view.apply_operator_action(action, data, ctx, extraPayload)`:
  - Supports `"ADD_FACILITY"`, `"DELETE_FACILITY"`, `"EDIT_DEDICATED"`, `"TOGGLE_MAINTENANCE"`, `"FORCE_FREE"`, `"WAVE_OFF"`, `"TOGGLE_EMERGENCY"`, updating `ctx.inventory`, persisting via `ctx.configLoader.save_config(ctx.configPath, ctx.config)`, and transmitting `MSG_ATC_FACILITY_UPDATE` on `(ctx.config.baseSecChannel or 50201) + 1` when `ctx.modem` is present.
- In `src/0_infra/gac/main.lua`:
  - Delegate keyboard operator actions to `tui_view.apply_operator_action(action, data, { inventory = inventory, config = cfg, configPath = CONFIG_FILE, configLoader = config_loader, tui = tui, modem = modem })`.

- [ ] **Step 4: Run unit tests to verify pass**

Run: `python tools/run_unit_tests.py --target 0_infra/gac`
Expected: PASS for all tests in `test_tui_view.lua` and `test_main_integration.lua`.

- [ ] **Step 5: Commit Task 3**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/gac/modules/tui_view.lua src/0_infra/gac/main.lua tests/0_infra/gac/test_tui_view.lua tests/0_infra/gac/test_main_integration.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(gac): add TUI DED/PUBLIC badges and operator facility management"
```

---

### Task 4: Full Verification Suite & Spec Status Promotion (`TASK-114-5`)

**Files:**
- Modify: `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md:6-13`
- Modify: `TASK.md:35-42`
- Modify: `GEMINI.md:1-20`

**Interfaces:**
- Consumes: `tools/run_unit_tests.py`, `tools/run_e2e_tests.py`, `tools/run_mutation_tests.py`, `tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/validate_lua_syntax.py`
- Produces: Verified GAC v1.4.1 implementation and updated `Implemented` spec status.

- [ ] **Step 1: Run full unit, E2E, mutation, and harness test suites**

Run:
```powershell
python tools/run_unit_tests.py --require-tests --clean-orphans; if ($?) { python tools/run_e2e_tests.py --clean-orphans }; if ($?) { python tools/run_mutation_tests.py }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }
```
Expected: All 12 unit test targets PASS, 6/6 E2E scenarios PASS, 20/20 mutations KILLED (100.0%), 41/41 harness tests PASS.

- [ ] **Step 2: Promote `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md` Status to `Implemented` and sync `TASK.md` / `GEMINI.md`**

In `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md`:
- Update `| **문서 상태 (Status)** | \`Approved\` |` $\to$ `| **문서 상태 (Status)** | \`Implemented\` |`
- Update `| **최종 수정일 (Date)** | \`2026-11-08\` |` $\to$ `| **최종 수정일 (Date)** | \`2026-11-10\` |`

In `TASK.md` and `GEMINI.md`:
- Move `TASK-114` to `## ✅ 3. 완료된 작업 이력` (pruning oldest entry beyond 10 items) and update `GEMINI.md` Current Phase & Standard Commands counts.

- [ ] **Step 3: Run static spec and syntax validators**

Run:
```powershell
python tools/verify_all_specs.py; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/validate_lua_syntax.py }
```
Expected: `0 Errors, 0 Warnings`, `9 Implemented, 5 Approved`, and `0 syntax errors`.

- [ ] **Step 4: Commit Task 4**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md TASK.md GEMINI.md .agent/memory/workspace-root.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(gac): promote GAC spec v1.4.1 to Implemented and close TASK-114"
```
