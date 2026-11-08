# TASK-200: AMM (Aircraft Mission Manager & Cockpit MFD) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the AMM (Aircraft Mission Manager, Node 03) subsystem integrating Cockpit MFD (51x19 dual-pane TUI), sequential waypoint queue management, persistent JSON storage, GCS C2 snooping, and emergency hotkey/CLI dispatch into FCP (`Base+0`) and VAS (`Base+1`).

**Architecture:** AMM operates as the Layer 3 planning and cockpit terminal running on an Advanced Computer (51x19 terminal). It maintains a 4-state queue FSM (`IDLE`, `EN_ROUTE`, `SUSPENDED`, `COMPLETED`), listens to 5Hz `MSG_MFD_STATE` on `Base+3` for HUD rendering and 2D arrival detection ($d_{2D} \le 15\text{ m}$), dispatches sequential waypoints to FCP on `Base+0` (`MSG_OPERATOR_CMD`), snoops `Base+0` for non-loopback GCS overrides, and fires instant `E_STOP` cutoffs to VAS on `Base+1` (`MSG_EMERGENCY_OVERRIDE`). Input is modal (`NAV/HOTKEY` vs `CLI EDIT`) to prevent key collisions.

**Tech Stack:** CC:Tweaked Lua 5.2 / Cobalt, ComputerCraft `term.blit` / `os.pullEventRaw`, CraftOS-PC headless test harness (`tools/run_unit_tests.py`).

**Spec:** `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (v1.0.0 `Draft` $\to$ `Approved`)

---

## Global Constraints

- **Single Function Length**: Every individual Lua function must strictly remain $\le 50$ lines of code (enforcing modular decomposition).
- **Multi-Codebase Autonomy**: `src/3_planning/amm/` must remain completely self-contained with no cross-package direct requires outside standard CC APIs and local modules.
- **Zero-Tick Non-Blocking**: Event polling uses `os.pullEventRaw` with deterministic timer-driven rendering (5Hz) and 20Hz non-blocking event handling; no `os.sleep()` inside core dispatchers.
- **Zero-Fallback Single-Key**: Packet schemas must strictly conform to UAFS Network Envelope v1.9.5 without runtime dual-key fallbacks.
- **RF Spectrum Standard**: Base channel follows $Base = 10000 + (N-1) \times 40$. AMM utilizes `Base+0` (C2 TX & GCS RX), `Base+1` (E-STOP TX), `Base+3` (MFD HUD RX).
- **Terminal Resolution**: Fixed 51x19 characters standard CC Advanced Computer resolution. Left 25 cols for HUD, right 26 cols for Mission Queue, rows 17-19 for status, hotkeys, and CLI.

---

## Review Focus

1. **Modal Input Collision Guard**: Typing commands like `add`, `alt`, or `clear` in `CLI EDIT MODE` must never trigger single-key hotkeys like `[A]` (ARM toggle) or `[L]` (LAND), while emergency `Ctrl+X` E-STOP must fire regardless of mode.
2. **GCS C2 Non-Loopback Snooping**: GCS `MSG_OPERATOR_CMD` packets received on `Base+0` must transition the queue to `SUSPENDED` and update the display without re-transmitting onto `Base+0` (preventing broadcast echo and FCP duplicate execution).
3. **Ground-to-Air Handover Interlock**: Pressing `[T]` (TAKEOFF) must command FCP takeoff but withhold $WP_1$ dispatch until FCP's `MSG_MFD_STATE` confirms `fsmState == "CRUISE"` (clearance altitude reached).
4. **Queue Lifecycle under Manual Overrides**: Triggering `[H]` (HOVER_HOLD), `[R]` (RTH), or `[L]` (EMERGENCY_LAND) must suspend 2D arrival evaluations so AMM does not advance waypoints during emergency hover/descent.
5. **Corrupted/Missing Mission JSON Safety**: Attempting to load an invalid or nonexistent JSON route must cleanly display a status warning banner on row 17 without throwing an unhandled runtime error.

---

## File Structure & Responsibilities

```
src/3_planning/amm/
├── main.lua                # Main daemon entry point, 20Hz event loop & 5Hz UI timer
├── config/
│   └── amm_config.json     # Configuration file: defaultAlt, defaultSpeed, arrivalRadius, channels
└── modules/
    ├── waypoint_queue.lua  # Waypoint FIFO queue, 2D arrival distance check, JSON load/save
    ├── network_manager.lua # ICD v1.9.5 envelope encode/decode, Base+0/1/3 modem packet dispatch
    ├── c2_arbiter.lua      # PILOT vs GCS authority arbitration, queue FSM & FCP/VAS command synthesis
    ├── ui_renderer.lua     # 51x19 dual-pane term.blit buffer renderer (HUD + Mission Queue)
    └── input_handler.lua   # Modal input parser: NAV/HOTKEY mode vs CLI EDIT buffer mode

tests/3_planning/amm/
├── test_waypoint_queue.lua # Unit tests for queue operations, persistence, and arrival logic
├── test_network_manager.lua# Unit tests for packet encoding/decoding and channel routing
├── test_c2_arbiter.lua     # Unit tests for authority switching, takeoff handshake, and queue FSM
├── test_input_handler.lua  # Unit tests for modal key handling and CLI command parsing
├── test_ui_renderer.lua    # Unit tests for 51x19 screen buffer text/color rendering
└── test_amm_integration.lua# Closed-loop integration test (FCP/VAS simulated packet cycle)
```

---

### Task 1: Scaffolding, Configuration & Harness Setup

**Files:**
- Create: `src/3_planning/amm/config/amm_config.json`
- Create: `tests/3_planning/amm/test_harness_setup.lua`
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (Promote Status: `Approved`)

**Steps:**
- [ ] **Step 1.1**: Promote `AMM_PROGRAM_SPECIFICATION.md` status to `Approved` with current date and verify specs with `python tools/verify_all_specs.py`.
- [ ] **Step 1.2**: Write failing test `tests/3_planning/amm/test_harness_setup.lua` verifying configuration loading defaults (`domainId`, `baseChannel`, `defaultAlt`, `defaultSpeed`, `arrivalRadius`).
- [ ] **Step 1.3**: Create `src/3_planning/amm/config/amm_config.json` with standard defaults (`defaultAlt = 150.0`, `defaultSpeed = 18.0`, `arrivalRadius = 15.0`).
- [ ] **Step 1.4**: Run tests via `python tools/run_unit_tests.py` to confirm PASS.

---

### Task 2: Waypoint Queue & JSON Persistence (`waypoint_queue.lua`)

**Files:**
- Create: `src/3_planning/amm/modules/waypoint_queue.lua`
- Create: `tests/3_planning/amm/test_waypoint_queue.lua`

**Steps:**
- [ ] **Step 2.1**: Write failing unit tests in `test_waypoint_queue.lua`:
  - `add(x, z, alt, speed, facilityId)`: pushes to queue, returns item with 1-based index.
  - `del(index)`: removes item, re-indexes remaining items.
  - `clear()`: resets queue to empty, returns queue to `IDLE`.
  - `get_active()`: returns current target waypoint.
  - `check_arrival(craft_pos, default_radius)`: returns `true` when 2D Euclidean distance $\le R_{arrival}$, advancing target index.
  - `save(filename)` and `load(filename)`: atomic JSON serialization to `missions/<name>.json` with error handling for malformed/missing files.
- [ ] **Step 2.2**: Implement `src/3_planning/amm/modules/waypoint_queue.lua` keeping all functions $\le 50$ lines.
- [ ] **Step 2.3**: Run `python tools/run_unit_tests.py` and `python tools/validate_lua_syntax.py` to verify PASS and syntax compliance.

---

### Task 3: Network Manager & ICD v1.9.5 Protocol (`network_manager.lua`)

**Files:**
- Create: `src/3_planning/amm/modules/network_manager.lua`
- Create: `tests/3_planning/amm/test_network_manager.lua`

**Steps:**
- [ ] **Step 3.1**: Write failing unit tests in `test_network_manager.lua`:
  - `encode_envelope(type, payload)`: attaches standard v1.9.5 envelope (`ver = "1.9.5"`, `domainId`, `seq`, `time`).
  - `decode_envelope(raw_packet)`: validates envelope schema, returns nil on corrupted payload.
  - `send_operator_cmd(modem, base_chan, payload)`: transmits onto `Base + 0`.
  - `send_emergency_override(modem, base_chan, action, reason)`: transmits `MSG_EMERGENCY_OVERRIDE` onto `Base + 1`.
  - `open_channels(modem, base_chan)`: opens `Base + 0` and `Base + 3`.
- [ ] **Step 3.2**: Implement `src/3_planning/amm/modules/network_manager.lua` with protected modem calls (`pcall`).
- [ ] **Step 3.3**: Run unit tests to confirm PASS.

---

### Task 4: C2 Arbiter & Queue FSM (`c2_arbiter.lua`)

**Files:**
- Create: `src/3_planning/amm/modules/c2_arbiter.lua`
- Create: `tests/3_planning/amm/test_c2_arbiter.lua`

**Steps:**
- [ ] **Step 4.1**: Write failing unit tests in `test_c2_arbiter.lua`:
  - Queue FSM transitions: `IDLE` $\to$ `EN_ROUTE` $\to$ `SUSPENDED` $\to$ `COMPLETED`.
  - `handle_gcs_packet(packet)`: when `authority == "GCS_OVERRIDE"`, transitions queue to `SUSPENDED`, updates active flightMode, does NOT re-transmit.
  - `handle_pilot_action(action, params)`: switches authority to `PILOT_PRIMARY`, builds `MSG_OPERATOR_CMD` for FCP on `Base+0`.
  - Ground-to-air handover: `on_fsm_state_change(new_state)`: dispatches $WP_1$ with `command = "CRUISE"` only when FCP enters `"CRUISE"`.
  - Final waypoint completion: when queue finishes, dispatches `APPROACH_LAND` if `facilityId` present, else `LOITER`.
- [ ] **Step 4.2**: Implement `src/3_planning/amm/modules/c2_arbiter.lua`.
- [ ] **Step 4.3**: Run unit tests to confirm PASS.

---

### Task 5: Modal Input Handler (`input_handler.lua`)

**Files:**
- Create: `src/3_planning/amm/modules/input_handler.lua`
- Create: `tests/3_planning/amm/test_input_handler.lua`

**Steps:**
- [ ] **Step 5.1**: Write failing unit tests in `test_input_handler.lua`:
  - In `NAV/HOTKEY` mode: single keys `x` $\to$ E-STOP, `h` $\to$ HOLD, `r` $\to$ RTH, `l` $\to$ LAND, `a` $\to$ ARM toggle, `t` $\to$ TAKEOFF.
  - In `NAV/HOTKEY` mode: pressing `Enter` or `/` enters `CLI EDIT` mode.
  - In `CLI EDIT` mode: typing characters `add 500 -1200` appends to buffer without triggering hotkeys; pressing `Enter` parses CLI command (`add`, `del`, `goto`, `clear`, `pause`, `resume`, `save`, `load`, `alt`, `spd`, `rad`).
  - Emergency override: `Ctrl+X` (key code with modifier or explicit mapping) triggers E-STOP even in `CLI EDIT` mode.
- [ ] **Step 5.2**: Implement `src/3_planning/amm/modules/input_handler.lua`.
- [ ] **Step 5.3**: Run unit tests to confirm PASS.

---

### Task 6: 51x19 Dual-Pane TUI Renderer (`ui_renderer.lua`)

**Files:**
- Create: `src/3_planning/amm/modules/ui_renderer.lua`
- Create: `tests/3_planning/amm/test_ui_renderer.lua`

**Steps:**
- [ ] **Step 6.1**: Write failing unit tests in `test_ui_renderer.lua`:
  - `create_buffer(w, h)`: initializes 51x19 character, text color, and background color matrices.
  - `render_hud(buffer, mfd_state)`: formats left pane (pitch, roll, heading, Y-alt, vertical speed, ground speed, fuel bar, health).
  - `render_queue(buffer, queue_state, current_wp_idx)`: formats right pane (waypoint list with markers `*`, `OK`, target altitude, distance).
  - `render_footer(buffer, banner_msg, input_mode, input_buffer)`: formats rows 17-19 (status message, hotkey guide, CLI prompt).
  - `flush_buffer(term_obj)`: outputs buffer using `term.blit` for 0-flicker rendering.
- [ ] **Step 6.2**: Implement `src/3_planning/amm/modules/ui_renderer.lua`.
- [ ] **Step 6.3**: Run unit tests to confirm PASS.

---

### Task 7: Main Daemon Dispatcher & CraftOS Integration (`main.lua`)

**Files:**
- Create: `src/3_planning/amm/main.lua`
- Create: `tests/3_planning/amm/test_main_loop.lua`

**Steps:**
- [ ] **Step 7.1**: Write unit test in `test_main_loop.lua` simulating the main event pump:
  - Dispatches `modem_message` to network manager and arbiter.
  - Dispatches `timer` (5Hz 200ms) to UI renderer and arrival distance check.
  - Dispatches `key` / `char` to modal input handler.
  - Clean shutdown on `terminate` / `q` key.
- [ ] **Step 7.2**: Implement `src/3_planning/amm/main.lua` with protected `xpcall` error reporting.
- [ ] **Step 7.3**: Run unit tests to confirm PASS.

---

### Task 8: End-to-End Simulation, Installer Manifest & Verification

**Files:**
- Create: `tests/3_planning/amm/test_amm_integration.lua`
- Modify: `src/0_development/installer/modules/manifest.lua`
- Validate: `tools/run_unit_tests.py`, `tools/validate_lua_syntax.py`, `tools/verify_all_specs.py`

**Steps:**
- [ ] **Step 8.1**: Write `test_amm_integration.lua` running a multi-tick closed loop:
  1. AMM boots, loads route with 3 waypoints.
  2. Pilot presses `[A]` (ARM) $\to$ FCP receives ARM.
  3. Pilot presses `[T]` (TAKEOFF) $\to$ FCP receives TAKEOFF.
  4. FCP enters `CRUISE` $\to$ AMM dispatches $WP_1$.
  5. FCP reports arrival at $WP_1$ $\to$ AMM automatically advances and dispatches $WP_2$.
  6. GCS sends `HOVER_HOLD` on `Base+0` $\to$ AMM queue suspends without re-transmitting.
  7. Pilot enters `resume` $\to$ AMM resumes sequencing to $WP_3$.
  8. Final WP reaches destination $\to$ FCP transitions to `LOITER` or `APPROACH_LAND`.
- [ ] **Step 8.2**: Register `amm` package in `src/0_development/installer/modules/manifest.lua` (Node 03 Cockpit Mission & Flight Terminal, target directory `/amm`).
- [ ] **Step 8.3**: Run full test suites:
  - `python tools/validate_lua_syntax.py` (0 errors)
  - `python tools/run_unit_tests.py --require-tests --clean-orphans` (all PASS)
  - `python -m unittest discover -s tests/harness -p "test_*.py"` (all PASS)
  - `python tools/verify_all_specs.py` & `tools/verify_spec_status.py`
