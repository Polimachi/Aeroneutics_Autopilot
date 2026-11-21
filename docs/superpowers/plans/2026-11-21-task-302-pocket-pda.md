# TASK-302: Pocket PDA Portable Remote C2, Ground Console Link & Emergency E_STOP Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the CC:Tweaked Pocket Computer (`26×20`) portable remote C2, HUD telemetry, wireless `E_STOP` + immediate `FDR` JSONL dump trigger, and remote `Alignment`/`FDR` session-binding terminal (`src/0_infra/pocket_pda/`) with full specification, wire-contract, installer manifest, GDrive mapping, playbook, and multi-node E2E integration (`TASK-302-1..4`).

**Architecture:** We follow a strict Spec-First sequence directly in-place at workspace root `c:\Users\sjmik\Desktop\Create_Aeroneutics` (executing `TASK-302` without creating a separate git worktree so existing uncommitted context files remain intact; keep `AGENTS.md` at `0 diff`). Task 1 authors `docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md` (`Draft` → `Approved`), updates peer specs (`ALIGNMENT`, `FDR`, `AMM`, `GCS`, Master ICD, Packet Diagram), and registers three new canonical wire packets (`MSG_ALIGN_REMOTE_CMD`, `MSG_ALIGN_REMOTE_STATUS` in `[I-4]`, and `MSG_FDR_REMOTE_CMD` in `[I-2]`) in `config/protocol_contracts.json`. Tasks 2–4 implement the `src/0_infra/pocket_pda/` codebase (networking, HUD/link-quality state, emergency C2, remote `Alignment`/`FDR` link controller, and `26×20` 3-tab TUI) alongside targeted peer hooks in `AMM` (`c2_arbiter.lua` `LAND_NEAREST`/`RTB`), `FDR` (`main.lua` receive-only `MSG_FDR_REMOTE_CMD`), and `Alignment` (`align_master.lua` + `main.lua` remote session binding/control). Tasks 5–6 wire `manifest.lua`, `config/gdrive_mapping.json`, `tools/run_boot_smoke.py`, `playbook/0_infra/pocket_pda.md`, multi-node E2E tests, and promote all modified specs to `Implemented` (`19` specs: `15 Implemented, 4 Approved`).

**Tech Stack:** CC:Tweaked Lua 5.2 (Cobalt VM, Pocket Computer `26×20` color terminal, Wireless/Ender Modem), `config/protocol_contracts.json` SSOT, CraftOS-PC headless unit & multi-node virtual-bus E2E runners (`tools/run_unit_tests.py`, `tools/run_e2e_tests.py`, `tools/run_boot_smoke.py`), Python 3.10+ static verifiers (`tools/verify_contracts.py`, `tools/verify_runtime_wiring.py`, `tools/verify_manifest_sync.py`, `tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/verify_playbooks.py`, `tools/verify_context_docs.py`, `python -m tools.audit guard`).

**Spec:**
- New Spec: `docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md` (`v1.0.0 Draft` → `Approved` → `Implemented`)
- Peer Specs Revised (`Implemented` → `Approved` in Task 1 → `Implemented` in Task 6):
  - `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (`v2.9.1` → `v2.10.0`)
  - `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md` (`v0.5.1` → `v0.6.0`)
  - `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v2.7.1` → `v2.8.0`)
  - `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v1.4.1` → `v1.5.0`)
- System Docs Synced (`Approved`):
  - `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.39.1` → `v1.40.0`)
  - `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.22.1` → `v2.23.0`)
- Backlog SSOT: `TASK.md` (`TASK-302-1`, `TASK-302-2`, `TASK-302-3`, `TASK-302-4`)

---

## Locked Rulings (Confirmed via /grill-me on 2026-11-21)

1. **`R1` (`FDR` Receive-Only `0 tx` Invariant + Dual-Target `Base+9` Routing):**
   - `FDR` (`src/0_development/fdr/main.lua`) maintains `0` `modem.transmit` calls under all paths.
   - `FDR` receives `MSG_FDR_REMOTE_CMD` (`BIND_AIRCRAFT`, `SET_MODE`, `DUMP_NOW`, `EXPORT_NOW`, `ROLLOVER_NOW`, `CLEAR_BUFFER`) on its currently bound `state.tap.baseChannel + 9` (`CH_EMERGENCY_CORE`) in all modes (`STANDBY`, `PAUSED`, `LOGGING`, `DISK_FULL`) by handling `MSG_FDR_REMOTE_CMD` at the top of `handle_modem_frame` **before** `if state.mode ~= "LOGGING" then return false end`.
   - `Pocket PDA` tracks `link_state.fdr.boundIndexN` (default `1`) and transmits `MSG_FDR_REMOTE_CMD` to `fdrBoundBase + 9` (and also to `net_ctx.baseChannel + 9` when `fdrBoundBase ~= net_ctx.baseChannel`), then updates its optimistic `link_state.fdr` display state (`boundIndexN`, `mode`, `lastAction`, `lastCmdMs`).
2. **`R2` (Global Single-Key `[X]` Immediate `E_STOP` + `FDR` `DUMP_NOW` Co-Transmission):**
   - Pressing `[X]` on `Pocket PDA` from any tab (`HUD`, `ALIGN`, `FDR`) immediately transmits two packets on `Base + 9` without confirmation delay:
     1. `MSG_EMERGENCY_OVERRIDE` (`{ action = "E_STOP", authKey = "ESTOP_CONFIRM_KEY", source = "POCKET_PDA", targetCraft = net_ctx.targetDomainId, reason = "PDA_OPERATOR_ESTOP" }`)
     2. `MSG_FDR_REMOTE_CMD` (`{ action = "DUMP_NOW", targetAircraftIndexN = net_ctx.aircraftIndexN, targetDomainId = net_ctx.targetDomainId, source = "POCKET_PDA", reason = "PDA_ESTOP_DUMP" }`, also sent to `fdrBoundBase + 9` if different)
   - In `FDR`, `DUMP_NOW` calls `trigger_manual_dump(state)` directly, so even if `FDR` is in `RING_BUFFER` mode, `PAUSED` mode, or already had `state.estopFlushed == true`, it immediately flushes/dumps JSONL to disk.
3. **`R3` (`LAND_NEAREST` Onboard `AMM` `c2_arbiter` Resolution + `EMERGENCY_LAND` Fallback):**
   - Pressing `[L]` on `Pocket PDA` transmits `MSG_OPERATOR_CMD` on `Base + 0` (`{ authority = "GCS_OVERRIDE", command = "LAND_NEAREST", targetCraft = net_ctx.targetDomainId, params = { source = "POCKET_PDA", facilityTypeFilter = "ANY" } }`).
   - In `src/3_planning/amm/modules/c2_arbiter.lua` (`handle_gcs_packet`, `require("facility_client")`), when `p.command == "LAND_NEAREST"`:
     - Resolve current aircraft position from `(self.engine and self.engine.lastMfd and self.engine.lastMfd.navigation and self.engine.lastMfd.navigation.currentPos) or (self.latest_mfd_payload and self.latest_mfd_payload.navigation and self.latest_mfd_payload.navigation.currentPos) or (self.latest_telem and self.latest_telem.navigation and self.latest_telem.navigation.currentPos) or (par.targetPos) or (self.engine and self.engine.homePos) or { x = 0, z = 0 }`.
     - Query `facility_client.find_nearest_free_landing_facility(self.engine and self.engine.fac, pos, par.facilityTypeFilter, par.maxRangeM)`.
     - If a free facility `best` is found: set `self.emergencyGoal` to `{ flightMode = "LANDING", arm = true, flightActive = true, facilityId = best.facilityId, designatedFacilityId = best.facilityId, targetPos = (best.position and best.position.x and best.position.z) and { x = best.position.x, z = best.position.z } or par.targetPos, targetAlt = (best.position and best.position.y) or par.targetAlt }`.
     - If no free facility is available: fall back immediately to `{ flightMode = "EMERGENCY_LAND", arm = true, flightActive = true, targetPos = par.targetPos, targetAlt = par.targetAlt }`.
     - Also support `p.command == "RTB"` as an alias for `"RTH"` (`flightMode = "FAILSAFE_RTH"`).
4. **`R4` (Full-Lifecycle `Alignment` Remote Session Control via `Base_hangar+0/+1`):**
   - Ground `Alignment` (`src/0_development/alignment/modules/align_master.lua` & `src/0_development/alignment/main.lua`) supports `align_master.handle_remote_cmd(master, pkt, cfg, modem, now_ms)` on `Base_hangar + 0` (`101..191`):
     - Consumes all required & optional keys of `MSG_ALIGN_REMOTE_CMD`: `action`, `stationId`, `bayId`, `aircraftIndexN`, `targetCraftDomain`, `baseHangarChannel`, `reason`, `saveProfile`, `source`.
     - Actions: `"BIND_SESSION"`, `"START_PULSE"`, `"PAUSE_SESSION"`, `"RETRY_STEP"`, `"APPROVE_SYNC"`, `"ABORT_SESSION"`, `"RELEASE_SESSION"`.
     - Preserve `align_master.release_channels(master)` closing `cmd_ch`, `telem_ch`, `tap_ch` so `tests/0_development/alignment/test_alignment_core.lua:140-167` passes unchanged; in `src/0_development/alignment/main.lua`, re-open `cmd_ch` after `PACKET` handling if `master.state == "STANDBY"` so the daemon remains reachable for future remote `BIND_SESSION` commands.
5. **`R5` (`26×20` 3-Tab Pocket TUI Layout & Dual Manual/Discovered Aircraft Selector):**
   - `SCREEN_W = 26`, `SCREEN_H = 20`; every rendered line is strictly 26 characters (`#line == 26`, 20 rows).
   - Rows 1–3: Global Header (Aircraft $N$, base channel, domainId, FSM state, RSSI tier `STRONG`/`GOOD`/`WEAK`/`LOST` & distance/`ENDER`, active tab `[1|2|3]`).
   - Rows 4–17: Switchable 3-tab body (`[1]HUD` flight telemetry & 4-node link matrix `AMM`/`VAS`/`GCS`/`ALN`/`FDR`; `[2]ALIGN` hangar bay $B$, target aircraft $N$, FSM state, active thruster, $R^2$/controllability, hotkeys; `[3]FDR` bound aircraft $N$, mode `LOGGING`/`STANDBY`/`PAUSED`, dump/export status, hotkeys).
   - Rows 18–20: Global Emergency & Navigation Footer (`[X]E-STOP+DUMP [H]HOLD`, `[R]RTB [L]LAND [< >]N [Q]X`, status banner).
   - Aircraft selection supports both `[<]`/`[>]` (`[`/`]` or `,`/`.` or Left/Right arrow keys for $N \pm 1$) and `[Tab]` (cycling discovered active aircraft from `CH 50000` `MSG_BLOCK_ASSIGN` and `Base+2/+3` telemetry).

---

## Global Constraints

1. **CC:Tweaked Lua 5.2 & Pocket Computer (`26×20`) Compliance:** No Lua 5.3+ operators (`//`, `&`, `|`, `~`, `<<`, `>>`), no `arg`, no `getfenv`/`setfenv`, no `os.execute`/`os.remove`/`os.rename`/`os.exit`/`io.popen` (`.agent/rules/cc-tweaked-runtime.md`). All Pocket PDA TUI lines must be clamped/padded to exactly `26` columns across `20` rows (`26×20`) so rendering never wraps or scrolls vertically.
2. **Prohibited Mods & Zero-Fallback:** Zero Valkyrien Skies / `kontraption:` identifiers (`.agent/rules/domain-aeronautics.md`), zero dual-key legacy fallbacks (`verify_contracts.py`), and zero inline peer version badges outside `### Revision History` and Master ICD `§5.1` (`verify_all_specs.py` Rule 10).
3. **Multi-Codebase Isolation & Freeze Boundaries:** `src/0_infra/pocket_pda/` must not `require()` modules from other `src/<layer>/<subsystem>/` directories (only `/lib/avionics_sensors.lua` is bundled per `verify_manifest_sync.py`). Keep `src/1_control/asa/**`, `tests/1_control/asa/**`, `src/3_planning/amm/main.lua`, and `src/3_planning/amm/modules/mission_engine.lua` at `0 diff`.
4. **FDR Passive Receive-Only Invariant (`modem.transmit == 0`):** `src/0_development/fdr/` must remain strictly receive-only (`0` calls to `modem.transmit`). Remote commands from Pocket PDA (`MSG_FDR_REMOTE_CMD` on `Base + 9`) are processed passively by `FDR` without transmitting RF ACKs.
5. **40-Channel Spectrum & Envelope `ver = "1.9.5"`:** Aircraft $N \in [1, 1000]$ uses $Base = 10000 + (N - 1) \times 40$; Hangar Bay $B \in [1, 10]$ uses $Base_{\text{hangar}} = 101 + (B - 1) \times 10$. On aircraft block channels (`Base + 0`, `Base + 8`, `Base + 9`), Pocket PDA sets envelope `domainId` to the target aircraft's `domainId` (e.g., `"AIRCRAFT_01"`) and identifies itself via `payload.source = "POCKET_PDA"` (and `payload.authority = "GCS_OVERRIDE"` for `MSG_OPERATOR_CMD`).
6. **100% `requiredKeys` Consumption (`tools/audit/guard.py`):** Every key listed in `requiredKeys` for `MSG_ALIGN_REMOTE_CMD`, `MSG_ALIGN_REMOTE_STATUS`, and `MSG_FDR_REMOTE_CMD` must be explicitly read in `src/` so `python -m tools.audit guard` passes with `0 errors, 0 warnings`.
7. **No-Overclaim (`AGENTS.md` & `verify_context_docs.py` R2):** Never use banned superlatives or `guarantee(s)` across specs, playbooks, comments, or context docs.

---

## Review Focus

1. **Envelope `domainId` Routing on Aircraft Block Channels (`Base+0`, `Base+8`, `Base+9`):**
   - `VAS` `network_manager.verify_envelope(rawPacket, state.aircraftDomainId)` rejects packets on `Base+8`/`Base+9` if `pkt.domainId ~= state.aircraftDomainId`; `AMM` `channel_sentinel` counts packets on `Base+0..39` with foreign `domainId` (unless allowlisted) as channel intrusions; `FDR` `packet_tap` filters by `lockedDomainId`. Pocket PDA (`pda_network.lua`) must stamp packets sent to aircraft block channels (`Base+0`, `Base+8`, `Base+9`) with the selected aircraft's `targetDomainId` (`"AIRCRAFT_01"` by default, or auto-latched from `Base+2`/`Base+3` telemetry) while setting `payload.source = "POCKET_PDA"`. **Pinned in Task 2, Task 3, and Task 5 E2E tests.**
2. **`FDR` Receive-Only Invariant & `STANDBY`/`PAUSED` Command Reception (`src/0_development/fdr/main.lua`):**
   - `src/0_development/fdr/main.lua:147` currently starts `handle_modem_frame` with `if state.mode ~= "LOGGING" then return false end`. If `FDR` is in `STANDBY` or `PAUSED`, it would drop `MSG_FDR_REMOTE_CMD` unless `MSG_FDR_REMOTE_CMD` on `state.tap.baseChannel + 9` is handled **before** that early return. Also, `test_e2e_fdr_blackbox.lua:229` asserts that switching `FDR` from $N=1$ to $N=2$ closes `10009` and opens `10049`, and asserts `txSpy == 0`. `FDR` must never call `modem.transmit` when handling `MSG_FDR_REMOTE_CMD`, and Pocket PDA must transmit `MSG_FDR_REMOTE_CMD` to `fdrBoundBase + 9` (and `targetBase + 9` if different), updating `fdrBoundIndexN` on `"BIND_AIRCRAFT"`. **Pinned in Task 3 unit tests and Task 5 E2E tests.**
3. **`Alignment` `release_channels` Backward Compatibility (`tests/0_development/alignment/test_alignment_core.lua:163`):**
   - Existing unit test `test_alignment_core.lua:140-167` calls `align_master.release_channels(master)` and asserts `mockModem.isOpen(101) == false`, `isOpen(102) == false`, `isOpen(104) == false`. Keep `align_master.release_channels(master)` closing `101, 102, 104` unchanged; in `align_master.handle_remote_cmd(master, pkt, cfg, modem, now_ms)`, transmit `MSG_ALIGN_REMOTE_STATUS` on `telem_ch` (`Base_hangar + 1`) **before** calling `release_channels`, and in `src/0_development/alignment/main.lua`'s daemon loop keep `cmd_ch` (`Base_hangar + 0`) open when waiting in `STANDBY` for remote `BIND_SESSION` packets. **Pinned in Task 3 unit tests.**
4. **`run_boot_smoke.py` Mock Peripheral Trap (`back` is `mock_monitor`) & `26×20` Screen Clamping:**
   - In `tools/run_boot_smoke.py:462-466`, `registry.back` is a `monitor` and `registry.top`/`bottom` are `modem`. If `pda_network.resolve_modem` blindly wraps `cfg.modemSide` (`"back"`) without checking `peripheral.getType(side) == "modem"`, it will wrap `mock_monitor` and fail to open any channels in boot smoke! `resolve_modem` must verify `peripheral.getType(side) == "modem"` before wrapping, falling back to `peripheral.find("modem")`. Also, every rendered TUI row must be exactly `26` chars (`#line == 26`, `20` rows). **Pinned in Task 2, Task 4, and Task 5.**
5. **Repository-Wide Count & Parity Guards Across Harness Tests:**
   - Adding `pocket_pda` changes repository counts asserted by existing tests:
     - `tests/0_development/installer/test_manifest_and_registry.lua`: total modules `15 → 16`, `infra` category `7 → 8`.
     - `tests/harness/test_boot_smoke_runner.py`: active targets `13 → 14`, with deferred `14 → 15`.
     - `tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tests/harness/test_verify_all_specs.py`, `tests/harness/test_audit_tools.py`: total active specs `18 → 19` (`15 Implemented, 4 Approved`).
     - `tools/verify_playbooks.py`, `playbook/README.md`, `tests/harness/test_verify_playbooks.py`: promote `playbook/0_infra/pocket_pda.md` from `RESERVED_EXPANSION_SLOTS` to `REQUIRED_PLAYBOOKS` (`15 → 16` playbooks).
     - `README.md`, `GEMINI.md`, `TASK.md`, `.agent/memory/workspace-root.md`: sync directory trees and counts for `verify_context_docs.py` R1–R9. **Pinned in Task 5 and Task 6.**

---

## File Structure

- **Task 1 (Spec-First Authoring & Wire Contracts SSOT):**
  - Create: `docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md`
  - Modify: `config/protocol_contracts.json`
  - Modify: `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md`
  - Modify: `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md`
  - Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`
  - Modify: `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md`
  - Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`
  - Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`
  - Modify: `tools/verify_all_specs.py`, `tools/verify_spec_status.py`
  - Test: `tests/harness/test_verify_all_specs.py`, `tests/harness/test_audit_tools.py`
- **Task 2 (`TASK-302-1` Part A — Pocket PDA Config, Network Router & Telemetry/RSSI HUD State):**
  - Create: `src/0_infra/pocket_pda/config/pda_config.json`
  - Create: `src/0_infra/pocket_pda/modules/pda_network.lua`
  - Create: `src/0_infra/pocket_pda/modules/telemetry_hud_state.lua`
  - Test: `tests/0_infra/pocket_pda/test_pda_network_and_hud.lua`
- **Task 3 (`TASK-302-2` & `TASK-302-3` — Emergency E_STOP+Dump, Tactical C2 & Remote `Alignment`/`FDR` Session Control):**
  - Create: `src/0_infra/pocket_pda/modules/emergency_c2_controller.lua`
  - Create: `src/0_infra/pocket_pda/modules/remote_link_controller.lua`
  - Modify: `src/3_planning/amm/modules/c2_arbiter.lua`
  - Modify: `src/0_development/fdr/main.lua`
  - Modify: `src/0_development/alignment/modules/align_master.lua`, `src/0_development/alignment/main.lua`
  - Test: `tests/0_infra/pocket_pda/test_pda_c2_and_remote_links.lua`, `tests/3_planning/amm/test_c2_arbiter.lua`, `tests/0_development/fdr/test_fdr_main.lua`, `tests/0_development/alignment/test_alignment_core.lua`
- **Task 4 (`TASK-302-1` Part B — `26×20` 3-Tab Lightweight TUI & `main.lua` Entrypoint):**
  - Create: `src/0_infra/pocket_pda/modules/pocket_tui.lua`
  - Create: `src/0_infra/pocket_pda/main.lua`
  - Test: `tests/0_infra/pocket_pda/test_pda_tui_and_main.lua`
- **Task 5 (`TASK-302-4` Part A — Installer Manifest, GDrive Mapping, Boot Smoke, Playbook & Multi-Node E2E):**
  - Modify: `src/0_development/installer/modules/manifest.lua`
  - Modify: `config/gdrive_mapping.json`
  - Modify: `tools/run_boot_smoke.py`
  - Create: `playbook/0_infra/pocket_pda.md`
  - Modify: `playbook/README.md`, `tools/verify_playbooks.py`
  - Create: `tests/e2e/test_e2e_pocket_pda_remote.lua`
  - Test: `tests/0_development/installer/test_manifest_and_registry.lua`, `tests/harness/test_boot_smoke_runner.py`, `tests/harness/test_verify_playbooks.py`
- **Task 6 (`TASK-302-4` Part B — Spec Promotion to `Implemented`, Context Sync & Full Gate Verification):**
  - Modify: `docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md`, `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md`, `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md`, `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`, `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md`, `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`, `tools/verify_spec_status.py`
  - Modify: `README.md`, `TASK.md`, `GEMINI.md`, `.agent/memory/workspace-root.md`

---

## Pre-Execution Setup (In-Place Execution)

- [x] **Step 1: Mark `TASK-302` in-progress (`[-]`) in `TASK.md` and run directly in-place at `c:\Users\sjmik\Desktop\Create_Aeroneutics`**

Do NOT create a separate git worktree (preserving uncommitted root context files; keep `AGENTS.md` untouched at `0 diff`). All Tasks 1–6 execute in-place inside `c:\Users\sjmik\Desktop\Create_Aeroneutics`.

---

### Task 1: Spec-First Authoring & Wire Contracts SSOT (`TASK-302-4`)

**Files:**
- Create: `docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md`
- Modify: `config/protocol_contracts.json`
- Modify: `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md`
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`
- Modify: `tools/verify_all_specs.py`
- Modify: `tools/verify_spec_status.py`
- Test: `tests/harness/test_verify_all_specs.py`
- Test: `tests/harness/test_audit_tools.py`

**Interfaces:**
- Produces in `config/protocol_contracts.json`:
  - Under `I-2` (`Outer Loop Guidance & Direct Pilot Commands`, channel override `aircraft_offset = 9`):
    - `MSG_FDR_REMOTE_CMD`:
      - `requiredKeys`: `["action", "targetAircraftIndexN", "source"]`
      - `optionalKeys`: `["targetDomainId", "recordMode", "autoStartLogging", "reason"]`
      - `enums`: `{ "action": ["BIND_AIRCRAFT", "SET_MODE", "DUMP_NOW", "EXPORT_NOW", "ROLLOVER_NOW", "CLEAR_BUFFER"] }`
      - `numericBounds`: `{ "targetAircraftIndexN": [1, 1000] }`
      - `specs`: `["docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md", "docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md"]`
    - Add `"docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md"` to `MSG_EMERGENCY_OVERRIDE.specs` (or `I-2.specs`).
  - Under `I-4` (`Aircraft Ground Calibration & Profile Sync`, `hangar_offset = 0` & `1`):
    - `MSG_ALIGN_REMOTE_CMD`:
      - `requiredKeys`: `["action", "stationId", "bayId", "aircraftIndexN"]`
      - `optionalKeys`: `["targetCraftDomain", "baseHangarChannel", "reason", "saveProfile", "source"]`
      - `enums`: `{ "action": ["BIND_SESSION", "START_PULSE", "PAUSE_SESSION", "RETRY_STEP", "APPROVE_SYNC", "ABORT_SESSION", "RELEASE_SESSION"] }`
      - `numericBounds`: `{ "bayId": [1, 10], "aircraftIndexN": [1, 1000] }`
      - `specs`: `["docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md", "docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md"]`
    - `MSG_ALIGN_REMOTE_STATUS`:
      - `requiredKeys`: `["stationId", "bayId", "aircraftIndexN", "fsmState", "status"]`
      - `optionalKeys`: `["targetCraftDomain", "baseHangarChannel", "craftBaseChannel", "activeThruster", "controllabilityStatus", "confidenceR2", "reason"]`
      - `enums`: `{ "status": ["SESSION_STARTED", "PULSE_STARTED", "PAUSED", "RETRYING", "SYNCING", "ABORTED", "RELEASED", "REJECTED"] }`
      - `specs`: `["docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md", "docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md"]`
    - Add `"docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md"` to `MSG_PBIT_REQ.specs` and `MSG_PBIT_REPORT.specs`.
  - Under `I-6` (`Operator C2 & Cockpit MFD Display`):
    - Add `"docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md"` to `MSG_OPERATOR_CMD.specs`, `MSG_MFD_STATE.specs`, and `MSG_MISSION_ACK.specs`.

- [ ] **Step 1: Update `tests/harness/test_verify_all_specs.py` and `tests/harness/test_audit_tools.py` for 19 active specs**

In `tests/harness/test_verify_all_specs.py`:
- Add `POCKET_PDA_SPEC_REL = "docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md"`.
- Update `test_spec_lists_contain_18_active_specs_including_editor` assertions from `18` to `19` and assert `self.assertIn(POCKET_PDA_SPEC_REL, vas.SPEC_FILES)` and `"ALL 19 SPECS 100% CLEAN (0 Errors, 0 Warnings)"`.
In `tests/harness/test_audit_tools.py`:
- Update `self.assertEqual(len(reg["specs"]), 18)` → `19` (`L30`) and `self.assertEqual(len(specs_res["documents"]), 18)` → `19` (`L91`).

- [ ] **Step 2: Run harness spec-list tests to verify they fail (Red)**

Run:
```powershell
python -m unittest tests/harness/test_verify_all_specs.py tests/harness/test_audit_tools.py
```
Expected: FAIL (`18 != 19`).

- [ ] **Step 3: Author `docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md` (`v1.0.0 Approved`) and update peer specs & `config/protocol_contracts.json`**

1. Create `docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md` with standard 5-row metadata table (`Status: Approved`, `Version: v1.0.0`, `Date: 2026-11-21`, `Source: src/0_infra/pocket_pda/`, `Domain: 휴대용 원격 관제·지상 콘솔 링크·비상 E_STOP 단말 (Pocket PDA)`), `### Revision History`, `연관 문서` links (without inline peer version badges per Rule 10), Mermaid architecture/sequence diagrams, 40-channel formula $\text{Base} = 10000 + (N - 1) \times 40$, hangar formula $Base_{\text{hangar}} = 101 + (B - 1) \times 10$, `26×20` 3-tab TUI specification (`[1]HUD/C2`, `[2]ALIGN`, `[3]FDR`), RSSI/distance classification from `modem_message` `senderDistance`, single-key `[X]` `E_STOP` + `FDR` dump protocol, `[H]`/`[R]`/`[L]` (`HOLD`/`RTB`/`LAND_NEAREST`) C2 commands, and all canonical packet names (`MSG_FLIGHT_TELEMETRY`, `MSG_MFD_STATE`, `MSG_OPERATOR_CMD`, `MSG_MISSION_ACK`, `MSG_EMERGENCY_OVERRIDE`, `MSG_EMERGENCY_ALERT`, `MSG_PBIT_REQ`, `MSG_PBIT_REPORT`, `MSG_BLOCK_ASSIGN`, `MSG_CALIBRATION_INIT_ACK`, `MSG_CALIB_ACK`, `MSG_CALIBRATION_CLOSE_ACK`, `MSG_ALIGN_REMOTE_CMD`, `MSG_ALIGN_REMOTE_STATUS`, `MSG_FDR_REMOTE_CMD`).
2. Update `config/protocol_contracts.json` with `MSG_FDR_REMOTE_CMD` (`I-2`, `packetChannelOverrides.MSG_FDR_REMOTE_CMD = { "kind": "aircraft_offset", "offset": 9 }`), `MSG_ALIGN_REMOTE_CMD` and `MSG_ALIGN_REMOTE_STATUS` (`I-4`), and `pocket_pda` spec references.
3. Revise peer specs to `Approved` (`2026-11-21`) with a `Revision History` row:
   - `ALIGNMENT_PROGRAM_SPECIFICATION.md` (`v2.10.0 Approved`): document `MSG_ALIGN_REMOTE_CMD` (`Base_hangar+0`) and `MSG_ALIGN_REMOTE_STATUS` (`Base_hangar+1`) remote session binding/control.
   - `FDR_PROGRAM_SPECIFICATION.md` (`v0.6.0 Approved`): document passive reception of `MSG_FDR_REMOTE_CMD` on `Base+9` (`BIND_AIRCRAFT`, `SET_MODE`, `DUMP_NOW`, `EXPORT_NOW`, `ROLLOVER_NOW`, `CLEAR_BUFFER`) preserving `0` `modem.transmit` calls.
   - `AMM_PROGRAM_SPECIFICATION.md` (`v2.8.0 Approved`): document `c2_arbiter` `MSG_OPERATOR_CMD` support for `command = "LAND_NEAREST"` (nearest free landing facility resolution with `EMERGENCY_LAND` fallback) and `"RTB"` alias from Pocket PDA / GCS.
   - `GCS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v1.5.0 Approved`): document coexistence with `Pocket PDA` passive fleet snoop on `CH 50000`/`CH 50004` and shared `GCS_OVERRIDE` C2 authority.
   - `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.40.0 Approved`) & `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.23.0 Approved`): add `Pocket PDA`, `MSG_FDR_REMOTE_CMD`, `MSG_ALIGN_REMOTE_CMD`, `MSG_ALIGN_REMOTE_STATUS`, and update `§5.1` table (`19` specs: `10 Implemented, 9 Approved` during implementation).
4. Register `docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md` in `tools/verify_all_specs.py` (`SPEC_FILES` and `REVISION_HISTORY_SPECS`, 19 specs) and `tools/verify_spec_status.py` (temporarily move `ALIGNMENT`, `FDR`, `AMM`, `GCS`, and new `POCKET_PDA` to `TARGET_APPROVED` during Tasks 1–5).

- [ ] **Step 4: Run spec & contract verification gates (Green)**

Run:
```powershell
python tools/verify_all_specs.py --check-readmes; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/verify_contracts.py --specs-only }; if ($?) { python -m unittest tests/harness/test_verify_all_specs.py tests/harness/test_audit_tools.py }
```
Expected: `ALL 19 SPECS 100% CLEAN (0 Errors, 0 Warnings)`, `verify_spec_status.py` `PASS`, `verify_contracts.py --specs-only` `0 errors`, and unit tests `OK`.

- [ ] **Step 5: Commit Task 1**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add config/protocol_contracts.json docs/specs/ docs/system/ tools/verify_all_specs.py tools/verify_spec_status.py tests/harness/test_verify_all_specs.py tests/harness/test_audit_tools.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(spec): add Pocket PDA spec and remote link contracts for TASK-302"
```

---

### Task 2: Pocket PDA Config, Network Router & Telemetry/RSSI HUD State (`TASK-302-1` Part A)

**Files:**
- Create: `src/0_infra/pocket_pda/config/pda_config.json`
- Create: `src/0_infra/pocket_pda/modules/pda_network.lua`
- Create: `src/0_infra/pocket_pda/modules/telemetry_hud_state.lua`
- Test: `tests/0_infra/pocket_pda/test_pda_network_and_hud.lua`

**Interfaces:**
- Produces in `pda_network.lua`:
  - `pda_network.compute_craft_base(aircraft_index_n) -> number|nil, string|nil` (`10000 + (n - 1) * 40` for integer $n \in [1, 1000]$)
  - `pda_network.compute_hangar_base(bay_id) -> number|nil, string|nil` (`101 + (bay_id - 1) * 10` for integer $bay\_id \in [1, 10]$)
  - `pda_network.default_domain_for_index(aircraft_index_n) -> string` (`string.format("AIRCRAFT_%02d", n)`)
  - `pda_network.init(cfg, modem_override) -> table` (resolves modem checking `peripheral.getType(side) == "modem"` before wrapping `side`, falling back to wireless `peripheral.find("modem")`)
  - `pda_network.open_channels(ctx) -> boolean, string|nil` (opens `base+{0,2,3,8,9}`, `baseHangar+1`, `50000`, `50004`)
  - `pda_network.close_channels(ctx) -> boolean`
  - `pda_network.rebind_aircraft(ctx, new_n, domain_override) -> boolean, string|nil` (closes old aircraft channels, opens new `base+{0,2,3,8,9}`, updates `ctx.aircraftIndexN`, `ctx.baseChannel`, `ctx.targetDomainId`)
  - `pda_network.rebind_hangar_bay(ctx, new_bay_id) -> boolean, string|nil` (closes old `baseHangar+1`, opens new `baseHangar+1`)
  - `pda_network.transmit_to_aircraft(ctx, offset, reply_offset_or_ch, pkt_type, payload, now_ms) -> boolean, table|nil` (uses `domainId = ctx.targetDomainId`, `ver = "1.9.5"`)
  - `pda_network.transmit_to_hangar(ctx, offset, reply_offset_or_ch, pkt_type, payload, now_ms) -> boolean, table|nil` (uses `domainId = ctx.targetDomainId`, `ver = "1.9.5"`)
  - `pda_network.parse_envelope(raw_msg) -> table|nil, string|nil`
- Produces in `telemetry_hud_state.lua`:
  - `telemetry_hud_state.init(cfg) -> table`
  - `telemetry_hud_state.classify_link_quality(distance_m, age_ms, cfg) -> table` (`{ tier = "STRONG"|"GOOD"|"WEAK"|"LOST", rssiPct = 0..100, distanceStr = "42.5m"|"ENDER"|"---" }`)
  - `telemetry_hud_state.quat_to_euler_deg(q) -> number, number, number` (`pitch, roll, yaw` in degrees, clamped `asin` input `[-1, 1]`, `yaw` in `[0, 360)`)
  - `telemetry_hud_state.ingest_packet(hud, net_ctx, channel, pkt, distance_m, now_ms) -> boolean`
  - `telemetry_hud_state.update_link_timeouts(hud, now_ms)`
  - `telemetry_hud_state.select_next_discovered(hud, current_n) -> number, string|nil`

- [ ] **Step 1: Write failing unit tests in `tests/0_infra/pocket_pda/test_pda_network_and_hud.lua`**

Test cases to include:
1. `compute_craft_base` ($N=1 \to 10000$, $N=2 \to 10040$, $N=1000 \to 49960$, $0$ and $1001 \to \text{nil}$) and `compute_hangar_base` ($B=1 \to 101$, $B=10 \to 191$, $0$ and $11 \to \text{nil}$).
2. `pda_network.init` skips non-modem peripheral on configured `modemSide = "back"` (e.g., when `"back"` is a `"monitor"` and `"top"` is a `"modem"`), opens `10000, 10002, 10003, 10008, 10009, 102, 50000, 50004`, and cleanly closes old aircraft channels when `rebind_aircraft(ctx, 3)` is called (`10080, 10082, 10083, 10088, 10089` opened; `10000..10009` closed).
3. `classify_link_quality` classifies `distance_m = 30.0, age_ms = 100` as `"STRONG"` (`"30.0m"`), `distance_m = 120.0, age_ms = 200` as `"GOOD"`, `distance_m = 300.0, age_ms = 200` as `"WEAK"`, `distance_m = nil, age_ms = 100` as `"STRONG"` (`"ENDER"`), and `age_ms = 3000` (`> telemetryTimeoutMs`) as `"LOST"` (`"---"`).
4. `ingest_packet` parses `MSG_MFD_STATE` on `Base+3` and `MSG_FLIGHT_TELEMETRY` on `Base+2` (including quaternion attitude conversion), auto-locks `net_ctx.targetDomainId` when `"*"` or default, records `AMM`/`VAS`/`GCS` online flags, and snoops `MSG_BLOCK_ASSIGN` on `50000` to populate `discoveredCrafts`.

- [ ] **Step 2: Run unit test to verify it fails (Red)**

Run:
```powershell
python tools/run_unit_tests.py --target 0_infra/pocket_pda --clean-orphans
```
Expected: FAIL (`module 'pda_network' not found`).

- [ ] **Step 3: Implement `pda_config.json`, `pda_network.lua`, and `telemetry_hud_state.lua`**

Implement the exact interfaces above in `src/0_infra/pocket_pda/config/pda_config.json`, `src/0_infra/pocket_pda/modules/pda_network.lua`, and `src/0_infra/pocket_pda/modules/telemetry_hud_state.lua`. Keep all functions `<= 50` lines and strictly Lua 5.2 compliant.

- [ ] **Step 4: Run unit test to verify it passes (Green)**

Run:
```powershell
python tools/run_unit_tests.py --target 0_infra/pocket_pda --clean-orphans
```
Expected: PASS (`4/4 PASS`).

- [ ] **Step 5: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/pocket_pda/ tests/0_infra/pocket_pda/test_pda_network_and_hud.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(pocket_pda): add network router, RSSI classifier, and HUD telemetry state (TASK-302-1)"
```

---

### Task 3: Emergency `E_STOP`+Dump, Tactical C2 & Remote `Alignment`/`FDR` Session Control (`TASK-302-2`, `TASK-302-3`)

**Files:**
- Create: `src/0_infra/pocket_pda/modules/emergency_c2_controller.lua`
- Create: `src/0_infra/pocket_pda/modules/remote_link_controller.lua`
- Modify: `src/3_planning/amm/modules/c2_arbiter.lua`
- Modify: `src/0_development/fdr/main.lua`
- Modify: `src/0_development/alignment/modules/align_master.lua`
- Modify: `src/0_development/alignment/main.lua`
- Test: `tests/0_infra/pocket_pda/test_pda_c2_and_remote_links.lua`
- Test: `tests/3_planning/amm/test_c2_arbiter.lua`
- Test: `tests/0_development/fdr/test_fdr_main.lua`
- Test: `tests/0_development/alignment/test_alignment_core.lua`

**Interfaces:**
- Produces in `emergency_c2_controller.lua`:
  - `emergency_c2_controller.trigger_estop_and_fdr_dump(net_ctx, hud_state, link_state, reason, now_ms) -> boolean`
    - Sends `MSG_EMERGENCY_OVERRIDE` on `Base + 9` (`{ action = "E_STOP", authKey = "ESTOP_CONFIRM_KEY", source = "POCKET_PDA", targetCraft = net_ctx.targetDomainId, reason = reason or "PDA_OPERATOR_ESTOP" }`).
    - Immediately sends `MSG_FDR_REMOTE_CMD` (`{ action = "DUMP_NOW", targetAircraftIndexN = net_ctx.aircraftIndexN, targetDomainId = net_ctx.targetDomainId, source = "POCKET_PDA", reason = "PDA_ESTOP_DUMP" }`) on `Base + 9` (and `fdrBoundBase + 9` if different).
  - `emergency_c2_controller.send_tactical_c2(net_ctx, hud_state, command, params, now_ms) -> boolean, string|nil`
    - Supports `"HOLD"` (`flightMode = "HOVER_HOLD"`), `"RTB"` / `"RTH"` (`command = "RTH"`, `flightMode = "FAILSAFE_RTH"`), `"LAND_NEAREST"` (`command = "LAND_NEAREST"`, `flightMode = "LANDING"`), `"LAND"` (`command = "LAND"`, `flightMode = "EMERGENCY_LAND"`), `"ARM"`, `"DISARM"`, `"TAKEOFF"`.
    - Transmits `MSG_OPERATOR_CMD` on `Base + 0` with `authority = "GCS_OVERRIDE"`, `targetCraft = net_ctx.targetDomainId`.
  - `emergency_c2_controller.send_pbit_request(net_ctx, run_wiggle, now_ms) -> boolean`
    - Transmits `MSG_PBIT_REQ` on `Base + 8` (`{ requestId = "PDA-PBIT-" .. tostring(net_ctx.seq + 1), source = "POCKET_PDA", runWiggle = (run_wiggle == true) }`).
- Produces in `remote_link_controller.lua`:
  - `remote_link_controller.init(cfg) -> table`
  - `remote_link_controller.send_align_cmd(net_ctx, link_state, action, opts, now_ms) -> boolean, string|nil`
    - Actions: `"BIND_SESSION"`, `"START_PULSE"`, `"PAUSE_SESSION"`, `"RETRY_STEP"`, `"APPROVE_SYNC"`, `"ABORT_SESSION"`, `"RELEASE_SESSION"`.
    - Transmits `MSG_ALIGN_REMOTE_CMD` on `Base_hangar + 0` (`replyChannel = Base_hangar + 1`).
  - `remote_link_controller.ingest_align_packet(link_state, channel, pkt, now_ms) -> boolean`
    - Consumes `MSG_ALIGN_REMOTE_STATUS` (`stationId`, `bayId`, `aircraftIndexN`, `fsmState`, `status`, `targetCraftDomain`, `activeThruster`, `controllabilityStatus`, `confidenceR2`, `reason`), `MSG_CALIBRATION_INIT_ACK`, `MSG_CALIB_ACK`, `MSG_CALIBRATION_CLOSE_ACK`.
  - `remote_link_controller.send_fdr_cmd(net_ctx, link_state, action, opts, now_ms) -> boolean, string|nil`
    - Actions: `"BIND_AIRCRAFT"`, `"SET_MODE"`, `"DUMP_NOW"`, `"EXPORT_NOW"`, `"ROLLOVER_NOW"`, `"CLEAR_BUFFER"`.
    - Transmits `MSG_FDR_REMOTE_CMD` on `fdrBoundBase + 9` (and `net_ctx.baseChannel + 9` if different), updating `link_state.fdr.boundIndexN` and `link_state.fdr.mode`.
- Produces in peer modules:
  - `src/3_planning/amm/modules/c2_arbiter.lua`: in `handle_gcs_packet`, support `p.command == "RTB"` (maps to `"FAILSAFE_RTH"`) and `p.command == "LAND_NEAREST"` (queries `facility_client.find_nearest_free_landing_facility` on `self.engine and self.engine.fac` using current navigation position, setting `self.emergencyGoal` to `flightMode = "LANDING"` with `facilityId = best.facilityId`, `designatedFacilityId = best.facilityId`, `targetPos`, `targetAlt`, or falling back to `flightMode = "EMERGENCY_LAND"` if no free facility beacon exists).
  - `src/0_development/fdr/main.lua`: handle `MSG_FDR_REMOTE_CMD` on `state.tap.baseChannel + 9` at the top of `handle_modem_frame` (before `if state.mode ~= "LOGGING"`), reading `p.action`, `p.targetAircraftIndexN`, `p.source`, `p.targetDomainId`, `p.recordMode`, `p.autoStartLogging`, `p.reason`, executing `"BIND_AIRCRAFT"`, `"SET_MODE"` (`"LOGGING"`/`"STANDBY"`/`"PAUSED"`), `"DUMP_NOW"`, `"EXPORT_NOW"`, `"ROLLOVER_NOW"`, `"CLEAR_BUFFER"`, with `0` `modem.transmit` calls.
  - `src/0_development/alignment/modules/align_master.lua` & `src/0_development/alignment/main.lua`: add `align_master.handle_remote_cmd(self, pkt, cfg, modem, now_ms)` handling `MSG_ALIGN_REMOTE_CMD` (`"BIND_SESSION"`, `"START_PULSE"`, `"PAUSE_SESSION"`, `"RETRY_STEP"`, `"APPROVE_SYNC"`, `"ABORT_SESSION"`, `"RELEASE_SESSION"`) and emitting `MSG_ALIGN_REMOTE_STATUS` on `telem_ch` (`Base_hangar + 1`).

- [ ] **Step 1: Write failing unit tests in `tests/0_infra/pocket_pda/test_pda_c2_and_remote_links.lua`, `tests/3_planning/amm/test_c2_arbiter.lua`, `tests/0_development/fdr/test_fdr_main.lua`, and `tests/0_development/alignment/test_alignment_core.lua`**

Test cases:
1. `test_pda_c2_and_remote_links.lua`:
   - `trigger_estop_and_fdr_dump` emits both `MSG_EMERGENCY_OVERRIDE` (`Base+9`) and `MSG_FDR_REMOTE_CMD` (`action = "DUMP_NOW"`, `Base+9`).
   - `send_tactical_c2` emits `MSG_OPERATOR_CMD` on `Base+0` for `"HOLD"`, `"RTB"`, `"LAND_NEAREST"`.
   - `send_align_cmd` emits `MSG_ALIGN_REMOTE_CMD` on `Base_hangar+0` (`101` for Bay 1, `111` for Bay 2) and `ingest_align_packet` updates `link_state.alignment` from `MSG_ALIGN_REMOTE_STATUS`.
   - `send_fdr_cmd("BIND_AIRCRAFT", { targetAircraftIndexN = 4 })` sends `MSG_FDR_REMOTE_CMD` to old `fdrBoundBase + 9` (`10009`) and new `10129`, updating `link_state.fdr.boundIndexN = 4`.
2. `tests/3_planning/amm/test_c2_arbiter.lua`:
   - `handle_gcs_packet` with `command = "LAND_NEAREST"` resolves the nearest `FREE` landing pad from `engine.fac` (`PAD_02`) into `arbiter.emergencyGoal` (`flightMode = "LANDING"`, `designatedFacilityId = "PAD_02"`), and falls back to `flightMode = "EMERGENCY_LAND"` when no beacon is free.
3. `tests/0_development/fdr/test_fdr_main.lua`:
   - Receiving `MSG_FDR_REMOTE_CMD` on `Base+9` switches `STANDBY` ↔ `LOGGING`, rebinds aircraft $N=1 \to 2$ (`10049`), forces `DUMP_NOW` and `EXPORT_NOW`, all with `apis.modem._getTxCount() == 0`.
4. `tests/0_development/alignment/test_alignment_core.lua`:
   - `align_master.handle_remote_cmd` processes `BIND_SESSION` for $N=2$ (`10048`), `PAUSE_SESSION`, `RETRY_STEP`, `APPROVE_SYNC`, and `ABORT_SESSION`/`RELEASE_SESSION`, emitting `MSG_ALIGN_REMOTE_STATUS` on `102`.

- [ ] **Step 2: Run targeted unit tests to verify they fail (Red)**

Run:
```powershell
python tools/run_unit_tests.py --target 0_infra/pocket_pda --target 3_planning/amm --target 0_development/fdr --target 0_development/alignment --clean-orphans
```
Expected: FAIL on the new `TASK-302-2` and `TASK-302-3` assertions.

- [ ] **Step 3: Implement `emergency_c2_controller.lua`, `remote_link_controller.lua`, and peer hooks in `c2_arbiter.lua`, `fdr/main.lua`, `align_master.lua`, and `alignment/main.lua`**

Implement the functions above while keeping all existing unit tests in `amm`, `fdr`, and `alignment` passing and keeping `src/3_planning/amm/main.lua` and `src/3_planning/amm/modules/mission_engine.lua` untouched (`0 diff`).

- [ ] **Step 4: Run targeted unit tests to verify they pass (Green)**

Run:
```powershell
python tools/run_unit_tests.py --target 0_infra/pocket_pda --target 3_planning/amm --target 0_development/fdr --target 0_development/alignment --clean-orphans
```
Expected: All 4 targets PASS (`0` failures).

- [ ] **Step 5: Commit Task 3**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/pocket_pda/ src/3_planning/amm/modules/c2_arbiter.lua src/0_development/fdr/main.lua src/0_development/alignment/ tests/0_infra/pocket_pda/ tests/3_planning/amm/test_c2_arbiter.lua tests/0_development/fdr/test_fdr_main.lua tests/0_development/alignment/test_alignment_core.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(pocket_pda,amm,fdr,alignment): implement remote E-STOP+dump, LAND_NEAREST, and Alignment/FDR session control (TASK-302-2,3)"
```

---

### Task 4: Pocket Computer `26×20` 3-Tab TUI & `main.lua` Entrypoint (`TASK-302-1` Part B)

**Files:**
- Create: `src/0_infra/pocket_pda/modules/pocket_tui.lua`
- Create: `src/0_infra/pocket_pda/main.lua`
- Test: `tests/0_infra/pocket_pda/test_pda_tui_and_main.lua`

**Interfaces:**
- Produces in `pocket_tui.lua`:
  - `pocket_tui.SCREEN_W = 26`, `pocket_tui.SCREEN_H = 20`
  - `pocket_tui.create_buffer(w, h) -> table` (defaults to `26, 20`)
  - `pocket_tui.format_line(text, width) -> string` (clamps/pads to `26` characters)
  - `pocket_tui.render_screen(buf, view_model) -> table` (populates 20 lines of 26 chars + fg/bg blit strings for active tab `"HUD" | "ALIGN" | "FDR"`)
  - `pocket_tui.flush_buffer(buf, term_obj) -> boolean`
- Produces in `src/0_infra/pocket_pda/main.lua`:
  - `main.load_config(path, fs_api) -> table`
  - `main.create_app(cfg, modem_override, fs_api) -> table`
  - `main:process_modem_message(channel, reply_channel, raw_msg, distance_m, now_ms) -> boolean`
  - `main:process_key(key_code, char_str, now_ms) -> boolean`
    - Global hotkeys (active on all tabs):
      - `1` / `2` / `3`: switch active tab (`"HUD"`, `"ALIGN"`, `"FDR"`)
      - `x`: immediate `E_STOP` + `FDR` JSONL dump (`trigger_estop_and_fdr_dump`)
      - `h`: `HOLD` (`HOVER_HOLD`)
      - `r`: `RTB` (`RTH` / `FAILSAFE_RTH`)
      - `l`: `LAND_NEAREST`
      - `[` or `,` or `keys.left`: decrement aircraft $N$ ($\max(1, N - 1)$) and rebind
      - `]` or `.` or `keys.right`: increment aircraft $N$ ($\min(1000, N + 1)$) and rebind
      - `tab`: cycle next discovered aircraft in fleet
      - `q`: clean shutdown (`self.running = false`, close channels)
    - Tab-specific hotkeys:
      - Tab 1 (`HUD`): `a` = `ARM`, `t` = `TAKEOFF`, `p` = `MSG_PBIT_REQ`
      - Tab 2 (`ALIGN`): `-`/`=` = Hangar Bay $B \pm 1$ ($1 \dots 10$), `b` = `BIND_SESSION`, `g` = `START_PULSE`, `p` = `PAUSE_SESSION`, `y` = `APPROVE_SYNC`, `a` = `ABORT_SESSION`, `k` = `RELEASE_SESSION`
      - Tab 3 (`FDR`): `b` = `BIND_AIRCRAFT` (to current selected $N$), `m` = toggle `LOGGING`/`STANDBY`, `d` = `DUMP_NOW`, `u` = `EXPORT_NOW`, `s` = `ROLLOVER_NOW`, `c` = `CLEAR_BUFFER`
  - `main:select_aircraft(new_n, domain_override) -> boolean, string|nil`
  - `main:render(term_obj, now_ms) -> boolean`
  - `main.main_loop(config_path)`

- [ ] **Step 1: Write failing unit tests in `tests/0_infra/pocket_pda/test_pda_tui_and_main.lua`**

Test cases:
1. `pocket_tui.render_screen` renders all 3 tabs (`"HUD"`, `"ALIGN"`, `"FDR"`) into a `26×20` buffer where every single row `1..20` has `#text == 26`, `#fg == 26`, `#bg == 26`, and `flush_buffer` calls `term.blit` 20 times without error on a `26×20` mock terminal.
2. `HUD` tab displays `N:001`, `10000`, altitude, vertical speed, ground speed, attitude (`P/R/Y`), fuel percentage bar, link quality (`STRONG`/`ENDER`/`LOST`), and node indicators (`AMM`, `VAS`, `GCS`, `ALN`, `FDR`).
3. `main.create_app` + `process_key` dispatches `[X]` (`E_STOP` + `FDR` `DUMP_NOW`), `[H]` (`HOLD`), `[R]` (`RTB`), `[L]` (`LAND_NEAREST`), `[[]`/`[]]` aircraft $N$ stepping, tab switching `[1]`/`[2]`/`[3]`, `ALIGN` tab session commands (`[B]`, `[G]`, `[P]`, `[Y]`, `[A]`, `[K]`), and `FDR` tab commands (`[B]`, `[M]`, `[D]`, `[U]`, `[S]`, `[C]`), then shuts down cleanly on `[Q]`.

- [ ] **Step 2: Run unit test to verify it fails (Red)**

Run:
```powershell
python tools/run_unit_tests.py --target 0_infra/pocket_pda --clean-orphans
```
Expected: FAIL (`module 'pocket_tui' not found`).

- [ ] **Step 3: Implement `pocket_tui.lua` and `src/0_infra/pocket_pda/main.lua`**

Implement `src/0_infra/pocket_pda/modules/pocket_tui.lua` and `src/0_infra/pocket_pda/main.lua` with all functions `<= 50` lines and zero unused imports.

- [ ] **Step 4: Run unit tests and runtime wiring check (Green)**

Run:
```powershell
python tools/run_unit_tests.py --target 0_infra/pocket_pda --clean-orphans; if ($?) { python tools/verify_runtime_wiring.py }
```
Expected: All `0_infra/pocket_pda` unit tests PASS and `verify_runtime_wiring.py` reports `14 subsystems (0 violations, 4 exemptions)`.

- [ ] **Step 5: Commit Task 4**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/pocket_pda/ tests/0_infra/pocket_pda/test_pda_tui_and_main.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(pocket_pda): implement 26x20 3-tab TUI renderer and main daemon loop (TASK-302-1)"
```

---

### Task 5: Installer Manifest, GDrive Mapping, Boot Smoke, Playbook & Multi-Node E2E (`TASK-302-4` Part A)

**Files:**
- Modify: `src/0_development/installer/modules/manifest.lua`
- Modify: `config/gdrive_mapping.json`
- Modify: `tools/run_boot_smoke.py`
- Create: `playbook/0_infra/pocket_pda.md`
- Modify: `playbook/README.md`
- Modify: `tools/verify_playbooks.py`
- Create: `tests/e2e/test_e2e_pocket_pda_remote.lua`
- Modify: `tests/0_development/installer/test_manifest_and_registry.lua`
- Modify: `tests/harness/test_boot_smoke_runner.py`
- Modify: `tests/harness/test_verify_playbooks.py`

**Interfaces:**
- `manifest.lua`:
  - Add `"pocket_pda"` to `manifest.MODULE_ORDER` (16th entry).
  - Add `manifest.MODULES.pocket_pda` (`id = "pocket_pda"`, `name = "Pocket PDA"`, `category = "infra"`, `version = "1.0.0"`, `installDir = "/"`, `startup = { enabled = true, path = "/startup/00_pocket_pda.lua", target = "/main.lua", name = "Pocket PDA" }`) bundling the 7 files in `src/0_infra/pocket_pda/` (`main.lua`, `config/pda_config.json`, `modules/pda_network.lua`, `modules/telemetry_hud_state.lua`, `modules/emergency_c2_controller.lua`, `modules/remote_link_controller.lua`, `modules/pocket_tui.lua`) plus `{ repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" }`.
- `config/gdrive_mapping.json`:
  - Register the 7 `src/0_infra/pocket_pda/**` package entries (`135 → 142` total mapped files) with matching `gdriveId`, `sha256`, `sizeBytes`, `category = "packages"`, `name = "pocket_pda__..."`, `downloadUrl`, and `bootstrapMap` entries (and run `sync_gdrive.py` when remote credentials are active).
- `tools/run_boot_smoke.py`:
  - Add `SmokeTarget(target_id="0_infra/pocket_pda", source_dir=src / "0_infra" / "pocket_pda", expected_channels=[102, 10000, 10002, 10003, 10008, 10009, 50000, 50004], cli_args=[], deferred=False, workspace_root=root)` (`13 → 14` active targets) and stage `config/pda_config.json` in `_stage_minimal_configs`.
- `playbook/0_infra/pocket_pda.md` & `tools/verify_playbooks.py`:
  - Author the 7-section operational playbook `playbook/0_infra/pocket_pda.md`, link it in `playbook/README.md`, and promote `"playbook/0_infra/pocket_pda.md"` from `RESERVED_EXPANSION_SLOTS` to `REQUIRED_PLAYBOOKS` (`15 → 16` required playbooks).

- [ ] **Step 1: Update `test_manifest_and_registry.lua`, `test_boot_smoke_runner.py`, `test_verify_playbooks.py`, and create `tests/e2e/test_e2e_pocket_pda_remote.lua`**

In `tests/e2e/test_e2e_pocket_pda_remote.lua`, write 2 multi-node E2E scenarios:
1. `Scenario 11a: Pocket PDA Remote C2 (HOLD/RTB/LAND_NEAREST), Single-Key E_STOP & Immediate FDR JSONL Dump`:
   - Nodes: `PDA` (`src/0_infra/pocket_pda`), `AMM` (`src/3_planning/amm`), `VAS` (`src/1_control/vas`), `TCA` (`src/1_control/tca`), `FDR` (`src/0_development/fdr`).
   - Verify `PDA` ingests `VAS`/`AMM` telemetry on `10002`/`10003` with `senderDistance = 38.0` (`STRONG`), issues `LAND_NEAREST` (`Base+0`) resolving a free pad in `AMM` `c2_arbiter`, and then triggers single-key `[X]` `E_STOP` (`Base+9`) causing `VAS` to latch `E_STOP`, `TCA` to cut thrust to `0`, and `FDR` to flush its JSONL session immediately with `0` `FDR` `modem.transmit` calls.
2. `Scenario 11b: Pocket PDA Remote Alignment Hangar Session & FDR Dynamic Aircraft [N] Rebinding`:
   - Nodes: `PDA` (`src/0_infra/pocket_pda`), `ALIGN` (`src/0_development/alignment`), `VAS` (`src/1_control/vas`), `FDR` (`src/0_development/fdr`).
   - Verify `PDA` switches to $N=2$ (`Base = 10040`), remotely binds `FDR` to $N=2$ (`10049`) and triggers `DUMP_NOW`, and remotely binds `Alignment` Bay 1 (`101/102`) to $N=2$ (`AIRCRAFT_02`, `10048`), receiving `MSG_ALIGN_REMOTE_STATUS` (`SESSION_STARTED`) and `MSG_CALIBRATION_INIT_ACK` before cleanly releasing the session (`RELEASE_SESSION`).

- [ ] **Step 2: Register `pocket_pda` in `manifest.lua`, `config/gdrive_mapping.json`, `tools/run_boot_smoke.py`, `playbook/0_infra/pocket_pda.md`, `playbook/README.md`, and `tools/verify_playbooks.py`**

- [ ] **Step 3: Run manifest sync, playbook verifier, boot smoke, unit tests, and E2E suite (Green)**

Run:
```powershell
python tools/verify_manifest_sync.py --strict-gdrive-packages; if ($?) { python tools/verify_playbooks.py }; if ($?) { python tools/run_boot_smoke.py --clean-orphans }; if ($?) { python tools/run_unit_tests.py --require-tests --clean-orphans }; if ($?) { python tools/run_e2e_tests.py --clean-orphans }
```
Expected:
- `verify_manifest_sync.py`: `16 modules, 0 Errors, 0 Warnings`
- `verify_playbooks.py`: `ALL 16 PLAYBOOKS & README CLEAN (0 Errors, 0 Warnings)`
- `run_boot_smoke.py`: `14/14 PASS`
- `run_unit_tests.py`: `16 targets PASS`
- `run_e2e_tests.py`: `11 suites / 25/25 PASS (0 contract violations)`

- [ ] **Step 4: Commit Task 5**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/installer/modules/manifest.lua config/gdrive_mapping.json tools/run_boot_smoke.py playbook/ tools/verify_playbooks.py tests/e2e/test_e2e_pocket_pda_remote.lua tests/0_development/installer/test_manifest_and_registry.lua tests/harness/test_boot_smoke_runner.py tests/harness/test_verify_playbooks.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(pocket_pda,installer,e2e,playbook): integrate manifest, boot smoke, playbook, and E2E suite (TASK-302-4)"
```

---

### Task 6: Spec Promotion to `Implemented`, Context Sync & Full Gate Verification (`TASK-302-4` Part B)

**Files:**
- Modify: `docs/specs/0_infra/pocket_pda/POCKET_PDA_PROGRAM_SPECIFICATION_AND_ICD.md`
- Modify: `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md`
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`
- Modify: `tools/verify_spec_status.py`
- Modify: `config/audit_baselines.json` (if new `PDA` E2E node instruction baseline is recorded)
- Modify: `README.md`
- Modify: `TASK.md`
- Modify: `GEMINI.md`
- Modify: `.agent/memory/workspace-root.md`

**Interfaces:**
- Final spec distribution: `19` specs (`15 Implemented, 4 Approved`).

- [ ] **Step 1: Promote `POCKET_PDA`, `ALIGNMENT`, `FDR`, `AMM`, and `GCS` specifications from `Approved` to `Implemented` (`2026-11-21`) and sync Master ICD `§5.1` and `tools/verify_spec_status.py`**

- [ ] **Step 2: Sync `README.md`, `TASK.md`, `GEMINI.md`, and `.agent/memory/workspace-root.md` per `md-management` & `verify_context_docs.py` R1–R9**

1. `README.md`: update `0_infra` directory listings (`docs/specs/0_infra/`, `src/0_infra/`, `tests/0_infra/`, `playbook/0_infra/`) to include `pocket_pda`, update active spec count to `19` (`15 Implemented, 4 Approved`), E2E suite count to `11개 통합 시뮬레이션 스위트(25개 케이스)`, and playbook count to `16종`.
2. `TASK.md`: mark `TASK-302` and `TASK-302-1..4` `[x]`, move `TASK-302` to the top of `## 3. 완료된 작업 이력`, and prune the 11th oldest entry (`TASK-405`) so `## 3.` retains exactly `10` entries (`R7`).
3. `.agent/memory/workspace-root.md`: prepend `## 2026-11-21 — Pocket PDA 휴대용 원격 관제·지상 콘솔 링크·비상 E_STOP 단말 구축 (TASK-302)` entry (`R8`).
4. `GEMINI.md`: update `§1` (`직전 완료: TASK-302`, `다음 액션: 1순위 TASK-140`), `§2` (`0_infra/{gps,gac,gcs,landing_pad,pocket_pda,runway}`, `playbook/` 16종, GDrive 142파일), `§3` (exact verification metrics), keeping total lines `<= 80` (`R3`).

- [ ] **Step 3: Run full verification gate suite (`verification-before-completion`)**

Run:
```powershell
python tools/validate_lua_syntax.py; if ($?) { python tools/verify_all_specs.py --check-readmes }; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/verify_contracts.py }; if ($?) { python tools/verify_runtime_wiring.py }; if ($?) { python tools/verify_manifest_sync.py --strict-gdrive-packages }; if ($?) { python tools/verify_playbooks.py }; if ($?) { python -m tools.audit guard }; if ($?) { python tools/run_boot_smoke.py --clean-orphans }; if ($?) { python tools/run_unit_tests.py --require-tests --clean-orphans }; if ($?) { python tools/run_e2e_tests.py --clean-orphans --check-baseline }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }; if ($?) { python tools/verify_context_docs.py }
```
Expected: `0` errors and `0` warnings across all commands, and `git diff -- src/1_control/asa tests/1_control/asa src/3_planning/amm/main.lua src/3_planning/amm/modules/mission_engine.lua` is empty (`0 diff`).

- [ ] **Step 4: Commit Task 6**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/ tools/verify_spec_status.py config/audit_baselines.json README.md TASK.md GEMINI.md .agent/memory/workspace-root.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(task-302): promote specs to Implemented and sync context docs"
```
