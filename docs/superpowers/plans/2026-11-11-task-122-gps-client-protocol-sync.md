# GPS & Client Protocol Synchronization and Runtime Hardening (TASK-122) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate every wire-protocol mismatch, runtime crash, silent drop, stale sequence/spoof leak, and scheduling gap between the centralized GPS cluster (`src/0_infra/gps/`), GPS Client HAL (`client_core.lua`, `gps_client.lua`), Landing Pad controller (`src/0_infra/landing_pad/`), and FCP outer-loop navigation (`src/2_guidance/fcp/`), verified by isolated CraftOS-PC unit tests and a true closed-loop multi-node E2E simulation.

**Architecture:** All four isolated CC:Tweaked codebases remain self-contained (zero cross-bundle runtime imports, compliant with `installer/modules/manifest.lua` and `GEMINI.md` §4), communicating exclusively via standard `v1.9.5` wired/wireless packets over `CH 60001` (`CH_GPS_PING`), `CH 60002` (`CH_GPS_SERVICE`), `CH 60003` (`CH_GPS_NODE_IN`), and per-client reply channels (`Base+5` for aircraft, `Base_sec+5` for ground facilities). The central GPS scheduler emits explicit `FAIL_GEOMETRY` responses with a short 150ms tombstone (without raising high-watermarks) so 250ms client retries work, `server.lua` dispatches `CH 60002` status queries and normalizes `/gps_data/nodes.json`, `monitor_ui.lua` renders string client/node IDs safely, `gps_client` gains `isManaged` retry parity and status query APIs, `landing_pad` adopts `"FACILITY"`/`"FIX_OK"`/`"FIX_DEGRADED"` Zero-Fallback parsing with 1Hz/5Hz/STATIC scheduling, and `fcp` emits standard `time` envelopes while enforcing `targetClient`, monotonic `clientSeq`, elapsed kinematic gating, and barometer/altitude-sensor `pos.y` synchronization.

**Tech Stack:** CC:Tweaked 1.109+ Lua 5.2 (Cobalt VM), CraftOS-PC Headless Unit Test Runner (`tools/run_unit_tests.py`), Multi-Node E2E Simulation Harness (`tools/run_e2e_tests.py`), Mutation Test Runner (`tools/run_mutation_tests.py`), Python 3.10+ Specification & Context Verifiers (`tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/verify_manifest_sync.py`, `tools/verify_context_docs.py`).

**Spec:**
- Primary Specification: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v2.2.2 Implemented` -> `v2.3.0 Approved` in Task 1 -> `v2.3.0 Implemented` in Task 6)
- Master ICD: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.27.0 Approved` — Interface I-7 badge sync & stale `CH 10045` example comment fix)
- System Diagram: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.12.1 Approved` — GPS reference badge sync)
- Consumer Specs: `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md` (`v2.4.2 Implemented` — GPS reference badge sync), `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (`v1.16.0 Implemented` — GPS reference badge sync)
- Roadmap SSOT: `TASK.md` (`TASK-122`)

## Global Constraints

- **Lua 5.2 Cobalt Compatibility (`.agent/rules/cc-tweaked-runtime.md`)**: Zero Lua 5.3+ operators (`//`, `&`, `|`, `~`, `<<`, `>>`), zero `getfenv`/`setfenv`, zero blocking `os.pullEvent`/`sleep` inside `forbid_event_swallow` unit tests unless wrapped in `sdk.with_events_allowed`.
- **Valkyrien Skies Ban (`.agent/rules/domain-aeronautics.md`)**: Zero prohibited mod identifiers (`valkyrien`, `vs2`, `cc_vs`, `ship` peripheral, `kontraption:`).
- **Multi-Codebase Isolation (`GEMINI.md` §4 & `manifest.lua`)**: `src/0_infra/landing_pad/` and `src/2_guidance/fcp/` MUST NOT `require("gps_client")` from `src/0_infra/gps/`. Only `/lib/avionics_sensors.lua` is shared across bundles.
- **Zero-Fallback Wire Protocol (`skill-workflows.md`)**:
  - `landing_pad/modules/gps_client.lua` MUST reject legacy `"OK"` and `"SUCCESS"` fix statuses and accept strictly `"FIX_OK"` and `"FIX_DEGRADED"`.
  - `gps/server.lua` MUST read `/gps_data/nodes.json` via canonical `nodeId` and `position.{x,y,z}` and read heartbeat coordinates strictly from `msg.payload.pos` (no `msg.payload.position` alias).
  - `fcp/modules/network_manager.lua` MUST emit `time` on outbound envelopes rather than `timestamp`.
- **Mutation Test Target Line Preservation (`tools/run_mutation_tests.py`)**: Keep target lines untouched across `src/0_infra/gps/modules/{trilateration,radar_math}.lua`, `src/0_infra/landing_pad/modules/{pad_fsm,offset_transform}.lua`, and `src/2_guidance/fcp/modules/{channel_sentinel,flight_fsm,vectored_vtol_driver,advanced_vtol_driver}.lua`.
- **UI Surface Auditor Compliance (`harness/unit/guest/runner_lib.lua`)**: Every `mon:blit(text, fg, bg)` call in `monitor_ui.lua` must satisfy `#text == #fg == #bg == self.width` and pass numeric `setCursorPos` coordinates.
- **No Overclaims (`AGENTS.md` / `verify_context_docs.py` R2)**: Report only verified command outputs, exact test counts, and factual behavior boundaries.

## Review Focus

1. **250ms Client Retry Blocked by HWM or Long Tombstone on `FAIL_GEOMETRY`**: When 3+ collinear nodes fail `trilateration.solve` on expiration (`flushExpired`), the scheduler MUST emit a `MSG_GPS_RESPONSE` with `status = "FAIL_GEOMETRY"` and register only a **150ms** short tombstone (`nowMs + 150`) WITHOUT advancing `client_last_solved[targetClient]`. Updating HWM or using `tombstoneTtlMs` (`1000ms`) would block the client's 250ms same-`clientSeq` retry (verified in Tasks 2 & 6).
2. **`monitor_ui` `%d` Runtime Crash & Tab Residue on Attached Monitor**: `renderClientsTab` and `renderNodesTab` formatted string identifiers (`"AIRCRAFT_01"`, `"NODE_01"`) with `#%-4d`, raising a Lua error whenever a physical `monitor` peripheral is attached to the GPS server. String coercion (`tostring`), bounded column width (`%-10s`), clearing body rows `3..h-2`, and updating default channels from `854/855` to `60001/60002` prevent display crashes and stale tab rows (verified in Task 2).
3. **`isManaged` Retry Omission & Unbounded `pendingResponses` Growth**: `standaloneLocate()` retried once at 50% timeout with the same `clientSeq`, whereas `locate()` under `isManaged == true` slept until timeout without retrying. Adding identical 50%-timeout retry logic to `isManaged` and pruning unpolled `pendingResponses` after `5000ms` aligns both modes without leaking memory (verified in Task 3).
4. **Landing Pad Config Mismatch (`manifest.lua` vs `setup_wizard.lua`) & Channel `60001` Reply Fallback**: `manifest.lua` installs flat fields (`facilityId`, `sectorId`, `mobility`, `sectorGpsReplyChannel`), whereas runtime code read nested `channels` / `padId` / `mode`, `setup_wizard` emitted tables failing `config_store.validate_config`, and missing config fell back `replyChannel` to `60001` (`CH_GPS_PING`). Local config normalization in `config_store.lua`, complete schema generation in `setup_wizard.lua`, sector `Base_sec+5` (`50206`) derivation in `gps_client.lua`, and dual-rate 1Hz/5Hz/STATIC scheduling eliminate crosstalk and TX/RX mismatch (verified in Task 4).
5. **FCP Cross-Craft Spoof, Kinematic Gate False Drop & Altitude Drift**: Without `targetClient == ctx.domainId` filtering in `network_manager.verify_packet` and monotonic bounded `clientSeq` checking in `nav_engine.filter_gps`, multi-aircraft replies or replayed fixes could contaminate navigation. Computing kinematic gate `delta_t` from `(now_ms - lastGpsFixMs) / 1000.0` avoids dropping valid fixes across 10Hz/dropped-packet intervals, and syncing `state.pos.y` from telemetry `altitudeY` keeps `MSG_GPS_REQUEST.altitudeY` accurate for 2D trilateration projection (verified in Task 5).

---

## File Structure

- Modify: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` — Bump `v2.2.2` -> `v2.3.0` (`Approved` in Task 1 -> `Implemented` in Task 6); align §3.4/§7.1/§9 examples, §7.1 `FAIL_GEOMETRY` expiration + 150ms tombstone, and §8.1/§8.3 `requestStatus`/`pollStatus`/`queryStatus` + `isManaged` 50% retry + multi-codebase wire parity note.
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` — Update GPS reference badge (`v2.2.1` -> `v2.3.0`) and Interface I-7 stale `CH 10045` comment (`CH 10005`), preserving `Approved`.
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` — Update GPS reference badge (`v2.2.1` -> `v2.3.0`), preserving `Approved`.
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` — Update GPS reference badge (`v2.2.2` -> `v2.3.0`), preserving `Implemented`.
- Modify: `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md` — Update GPS reference badge (`v2.2.1` -> `v2.3.0`), preserving `Implemented`.
- Modify: `src/0_infra/gps/modules/session_scheduler.lua` — Return `session.replyChannel` as 3rd return value on `EARLY_SOLVED`; emit `FAIL_GEOMETRY` + 150ms short tombstone (without bumping HWM) on `flushExpired` when `count >= 3` solve fails; include `clientAltitudeY` and explicit `nodeCount`/`selectedNodes` on expiration responses.
- Modify: `src/0_infra/gps/server.lua` — Guard `main()` execution when required as a module and export testable functions; require `config_store`; normalize `/gps_data/nodes.json` (`nodeId`, `position`, `status`); transmit `EARLY_SOLVED` on returned `earlyReplyCh`; handle `CH_GPS_SERVICE` (`60002`) `MSG_GPS_STATUS_REQ`; fix `handleHeartbeat` (`msg.payload.pos` Zero-Fallback + `registry` sync); track `state.clients` / `state.clientCount` / `listenChan` / `dataChan`.
- Modify: `src/0_infra/gps/modules/monitor_ui.lua` — Replace `%d` ID formatting with `%-10s` `tostring` formatting; clear stale tab rows `3..h-2` on render; default overview channels to `60001`/`60002`.
- Modify: `src/0_infra/gps/node.lua` — Increment monotonic `state.reportSeq` per ping in `handlePingMessage`; guard `main(...)` for module/test imports and export handlers.
- Modify: `src/0_infra/gps/hal/wizard_cli.lua` — Replace non-existent `storage_hal.writeJson` with `storage_hal.writeJsonAtomic`.
- Modify: `src/0_infra/gps/modules/client_core.lua` — Add 5000ms TTL pruning on `pendingResponses`; add `nextStatusRequestPacket`, `MSG_GPS_STATUS_RESP` handling on `replyChannel` or `CH_GPS_SERVICE` (`60002`), and `pollStatus`.
- Modify: `src/0_infra/gps/hal/gps_client.lua` — Add 50%-timeout 1-time retry inside `isManaged` `locate()`; guard `os.epoch` in `standaloneLocate`; expose `requestStatus`, `pollStatus`, and `queryStatus`.
- Modify: `src/0_infra/landing_pad/modules/config_store.lua` — Add `normalize_config(raw)` to unify `manifest.lua` flat keys and runtime nested fields, and invoke during `load_config`.
- Modify: `src/0_infra/landing_pad/modules/setup_wizard.lua` — Emit full schema-valid config (`facilityId`, `sectorId`, `mobility`, `gacChannel`, `sectorFacilityChannel`, `sectorGpsReplyChannel`, `tacticalChannel`, `wirelessModemSide`, `slotDurationSec`) alongside existing fields from `assemble_config`.
- Modify: `src/0_infra/landing_pad/modules/gps_client.lua` — Switch `clientType` to `"FACILITY"`, derive `Base_sec+5` (`50206` default, zero `60001` fallback), enforce Zero-Fallback `ver`/`targetClient`/`clientSeq`/(`"FIX_OK"` | `"FIX_DEGRADED"`) validation, store `hasValidFix`/`lastStatus`/`lastAccuracy`/`lastHdop`, and add `has_valid_fix()` + `should_query_gps(fsmState, tickCount)`.
- Modify: `src/0_infra/landing_pad/main.lua` — Normalize config via `config_store.normalize_config(cfg)`, pass explicit `replyCh` (`reqPkt.payload.replyChannel`) into `send_packet`, and query GPS via `gpsClient:should_query_gps(currentState, tickCount)`.
- Modify: `src/2_guidance/fcp/modules/network_manager.lua` — Emit `time = now_epoch` in `encode_envelope` and reject `MSG_GPS_RESPONSE` packets when `payload.targetClient ~= ctx.domainId` in `verify_packet`.
- Modify: `src/2_guidance/fcp/modules/nav_engine.lua` — Add bounded monotonic `clientSeq` check (`lastGpsFixSeq`), compute elapsed `delta_t` for kinematic gating from `(now_ms - lastGpsFixMs) / 1000.0`, and synchronize `state.pos.y` from telemetry `altitudeY` in `integrate_dr`.
- Modify: `tests/0_infra/gps/test_gps_core.lua` — Add unit tests covering `session_scheduler`, `server`, `monitor_ui`, `node`, `wizard_cli` atomic save, `client_core` TTL/status, and `gps_client` `isManaged` retry + status query.
- Modify: `tests/0_infra/landing_pad/test_gps_client.lua`, `test_config_store.lua`, `test_setup_and_tui.lua` — Align tests to `"FACILITY"` / `"FIX_OK"` / `"FIX_DEGRADED"`, add negative Zero-Fallback & replay checks, verify dual-rate cadence, and test `normalize_config` + wizard validation.
- Modify: `tests/2_guidance/fcp/test_fcp_core.lua` — Add tests for `time` envelope field, `MSG_GPS_RESPONSE` `targetClient` rejection, `clientSeq` replay/future rejection, elapsed kinematic gate `delta_t`, and `integrate_dr` altitude sync.
- Modify: `tests/e2e/test_e2e_gps_triangulation.lua` — Upgrade Scenario 3 to exercise real `gps/server`, `gps/node`, `fcp_runtime`, `gps/hal/gps_client` (`CH 60002`), and `landing_pad/modules/gps_client` (`50206`), including `FAIL_GEOMETRY` + 250ms retry.
- Modify: `TASK.md`, `GEMINI.md`, `.agent/memory/workspace-root.md` — Sync `TASK-122` lifecycle state, test counts, and handover history.

---

### Task 1: Revise GPS Specification (`v2.3.0 Approved`) & Sync Reference Badges (`TASK-122-1`)

**Files:**
- Modify: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md:6-35,233-236,840-885,926-1005,1034,1073,1083-1089`
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md:46,1119,1123,1144`
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md:38`
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md:23`
- Modify: `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md:30`
- Modify: `TASK.md`

**Interfaces:**
- Consumes: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (Interface I-7), `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md` (§1.4.2, §2.1), `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (§8.5)
- Produces: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v2.3.0`, `Status: Approved`, `Date: 2026-11-11`), synchronized reference badges across 4 consumer specs (without changing consumer statuses), and `TASK.md` `[-]` state with `(현재 v2.3.0 Approved)`.

- [ ] **Step 1: Update `GPS_PROGRAM_SPECIFICATION_AND_ICD.md` metadata, Revision History, and protocol clarifications**

In `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`:
1. Update the metadata table (`lines 8-10`):
   - `문서 상태 (Status)`: `` `Approved` ``
   - `문서 버전 (Version)`: `` `v2.3.0` ``
   - `최종 수정일 (Date)`: `` `2026-11-11` ``
2. Prepend a row to `### Revision History` (`line 18`):
   ```markdown
   | `v2.3.0` | 2026-11-11 | `FAIL_GEOMETRY` 세션 만료 응답 및 150ms 단기 툼스톤(HWM 비갱신으로 250ms 재시도 허용), `CH 60002` 상태 조회 API(`requestStatus`/`pollStatus`/`queryStatus`), `isManaged` 50% 타임아웃 재시도 동등성, 멀티 코드베이스 독립 완결 클라이언트 와이어 호환 규칙 및 `/gps_data/node.json` 설정 경로 명시 (`Implemented` $\to$ `Approved`) | TASK-122 GPS ↔ 클라이언트 프로토콜 정합화 및 런타임 누락 보완 |
   ```
3. Sync reference badges at `lines 24-35`: set `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.27.0`), `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.12.1`), `FCP_PROGRAM_SPECIFICATION.md` (`v1.16.0`), `VAS_PROGRAM_SPECIFICATION.md` (`v1.18.0`), `TCA_PROGRAM_SPECIFICATION.md` (`v1.11.0`), `ALIGNMENT_PROGRAM_SPECIFICATION.md` (`v2.6.0`), `GAC_PROGRAM_SPECIFICATION_AND_ICD.md` (`v1.4.1`), `LANDING_PAD_SPECIFICATION_AND_ICD.md` (`v2.4.2`), `DOCKING_ARM_SPECIFICATION_AND_ICD.md` (`v1.11.1`), `RUNWAY_SPECIFICATION_AND_ICD.md` (`v1.10.6`).
4. Clean stale reply-channel example `10045` -> `10005` (`line 234`), `10065` -> `10005` (`line 848`), and `/gps_data/node_cfg.json` -> `/gps_data/node.json` (`lines 1034, 1073, 1083, 1084`).
5. Update `§7.1` expiration rules (`lines 877-880`):
   - Add explicit expiration branch when collected nodes `>= 3` and `trilateration.solve()` fails with `FAIL_GEOMETRY`: emit `MSG_GPS_RESPONSE` (`status = "FAIL_GEOMETRY"`, `nodeCount = count`, `selectedNodes = {}`), register a **150ms** short tombstone (`nowMs + 150`), and **do not update `client_last_solved[targetClient]`** so the client's 250ms retry with the same `clientSeq` can be re-evaluated.
   - Specify the same **150ms** short tombstone rule for `count < 3` (`FAIL_INSUFFICIENT`).
6. Update `§8.1` and `§8.3` (`lines 928-1001`):
   - Add `gpsClient.requestStatus([queryType], [replyChannel])`, `gpsClient.pollStatus()`, and `gpsClient.queryStatus([timeoutSec], [queryType])` for `CH 60002` (`MSG_GPS_STATUS_REQ` / `MSG_GPS_STATUS_RESP`), allowing `handleMessage` to dispatch `MSG_GPS_STATUS_RESP` on `replyChannel` or `CH_GPS_SERVICE` (`60002`).
   - Update `gpsClient.locate` `isManaged` pseudocode so managed polling also triggers the 1-time 50%-timeout retry (`timeoutSec * 0.5`) with the same `clientSeq`, matching `standaloneLocate`.
   - Document that multi-codebase isolated targets (`fcp`, `landing_pad`) implement this exact `v1.9.5` wire contract using their internal modules (`network_manager.lua` + `nav_engine.lua`, `landing_pad/modules/gps_client.lua`) without introducing cross-bundle imports of `/apis/gps_client.lua`.

- [ ] **Step 2: Synchronize GPS version badges in ICD, System Diagram, FCP, and Landing Pad specs + update `TASK.md`**

1. Update ONLY GPS version badge text (`-> v2.3.0`) without changing document versions or statuses in:
   - `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md:46` (`v2.2.1` -> `v2.3.0`), `line 1119` (`v2.0.0` -> `v2.3.0`), plus example comments on `lines 1123, 1144` (`10045` -> `10005` while noting `10045` `[DEPRECATED]`).
   - `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md:38` (`v2.2.1` -> `v2.3.0`).
   - `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md:23` (`v2.2.2` -> `v2.3.0`).
   - `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md:30` (`v2.2.1` -> `v2.3.0`).
2. Update `TASK.md`: mark `TASK-122` as `[-]` (and `TASK-122-1` `[x]` after verification), syncing the spec status label on `TASK-122` from `(현재 v2.2.2 Implemented)` to `(현재 v2.3.0 Approved)` so `verify_context_docs.py` R5 stays aligned throughout Tasks 2–5.

- [ ] **Step 3: Run specification & context static verifiers**

Run:
```powershell
python tools/verify_all_specs.py --check-readmes; if ($?) { python tools/verify_context_docs.py }
```
Expected: `SCAN RESULT: ALL 15 SPECS 100% CLEAN (0 Errors, 0 Warnings)`, `README audit complete: 0 error(s).`, and `[PASS] context docs: 0 findings`. (Note: `verify_spec_status.py` expects `GPS` `Implemented` and will pass in Task 6 after promotion back from `Approved`.)

- [ ] **Step 4: Commit Task 1**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md TASK.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(gps): revise GPS spec to v2.3.0 Approved and sync I-7 references (TASK-122-1)"
```

---

### Task 2: GPS Server, Scheduler, Node, Commissioning & Monitor UI Protocol Fixes (`TASK-122-2`)

**Files:**
- Modify: `src/0_infra/gps/modules/session_scheduler.lua:53-157`
- Modify: `src/0_infra/gps/server.lua:1-164`
- Modify: `src/0_infra/gps/node.lua:53-138`
- Modify: `src/0_infra/gps/modules/monitor_ui.lua:81-171`
- Modify: `src/0_infra/gps/hal/wizard_cli.lua:90-95`
- Modify: `tests/0_infra/gps/test_gps_core.lua:1-231`

**Interfaces:**
- Consumes: `src/0_infra/gps/modules/{protocol,config_store,trilateration}.lua`, `src/0_infra/gps/hal/storage_hal.lua`, `/gps_data/nodes.json` (`{ nodes = { [nodeId] = { nodeId, computerId, position, status } } }`)
- Produces:
  - `session_scheduler:ingestReport(...) -> action, payload|nil, replyChannelOrReason|nil` (when `action == "EARLY_SOLVED"`, 3rd return is numeric `session.replyChannel`)
  - `session_scheduler:flushExpired(...) -> { { replyChannel, clientAltitudeY, payload }, ... }` (emits `FAIL_GEOMETRY` + 150ms tombstone when `count >= 3` solve fails)
  - `server.lua` module export table when required, dispatching `CH 60002` `MSG_GPS_STATUS_REQ`, `CH 60003` `MSG_GPS_NODE_REPORT`/`MSG_GPS_NODE_HEARTBEAT` (`payload.pos`), tracking `state.clients` / `state.clientCount` / `listenChan` / `dataChan`
  - `monitor_ui` crash-free string ID table rendering and cleared tab bodies within `79x36` surface bounds
  - `node.lua` monotonically incrementing `reportSeq` and module export table
  - `wizard_cli.lua` `storage_hal.writeJsonAtomic`

- [ ] **Step 1: Write failing unit tests for `session_scheduler`, `server`, `monitor_ui`, `node`, and `wizard_cli`**

Append the following suites to `tests/0_infra/gps/test_gps_core.lua`:
```lua
describe("gps session_scheduler early solve and FAIL_GEOMETRY retry window", function()
    local session_scheduler = require("session_scheduler")

    it("returns replyChannel as 3rd return on EARLY_SOLVED", function()
        local sched = session_scheduler.new({ windowMs = 50, tombstoneTtlMs = 1000 })
        local registry = { nodes = {} }
        local nodes = {
            { id = "N1", x = 0, y = 80, z = 0 },
            { id = "N2", x = 500, y = 80, z = 0 },
            { id = "N3", x = 0, y = 80, z = 500 },
            { id = "N4", x = 500, y = 80, z = 500 },
        }
        local cx, cy, cz = 200, 100, 300
        local act, pl, replyCh
        for _, n in ipairs(nodes) do
            local d = math.sqrt((cx - n.x)^2 + (cy - n.y)^2 + (cz - n.z)^2)
            act, pl, replyCh = sched:ingestReport({
                targetClient = "AIRCRAFT_01",
                clientSeq = 7,
                nodeId = n.id,
                nodePos = { x = n.x, y = n.y, z = n.z },
                measuredDistance = d,
                clientAltitudeY = cy,
                replyChannel = 10005,
            }, registry, 1000)
        end
        assert_eq(act, "EARLY_SOLVED")
        assert_not_nil(pl)
        assert_eq(pl.status, "FIX_OK")
        assert_eq(replyCh, 10005)
    end)

    it("emits FAIL_GEOMETRY with 150ms tombstone on flushExpired without raising HWM", function()
        local sched = session_scheduler.new({ windowMs = 50, tombstoneTtlMs = 1000 })
        local registry = { nodes = {} }
        -- 3 strictly collinear nodes along Z=0
        local collinear = {
            { id = "C1", x = 0, y = 80, z = 0, d = 120 },
            { id = "C2", x = 100, y = 80, z = 0, d = 100 },
            { id = "C3", x = 200, y = 80, z = 0, d = 120 },
        }
        for _, n in ipairs(collinear) do
            local act = sched:ingestReport({
                targetClient = "AIRCRAFT_01",
                clientSeq = 1,
                nodeId = n.id,
                nodePos = { x = n.x, y = n.y, z = n.z },
                measuredDistance = n.d,
                clientAltitudeY = 80,
                replyChannel = 10005,
            }, registry, 1000)
            assert_eq(act, "BUFFERED")
        end

        local responses = sched:flushExpired(registry, 1060)
        assert_eq(#responses, 1)
        assert_eq(responses[1].replyChannel, 10005)
        assert_eq(responses[1].payload.status, "FAIL_GEOMETRY")
        assert_eq(responses[1].payload.targetClient, "AIRCRAFT_01")
        assert_eq(responses[1].payload.clientSeq, 1)
        assert_nil(sched.client_last_solved["AIRCRAFT_01"], "FAIL_GEOMETRY must not raise HWM")

        -- Late report inside 150ms tombstone window (1060 + 150 = 1210) must be dropped
        local lateAct, _, lateReason = sched:ingestReport({
            targetClient = "AIRCRAFT_01",
            clientSeq = 1,
            nodeId = "C4",
            nodePos = { x = 100, y = 80, z = 200 },
            measuredDistance = 200,
            clientAltitudeY = 80,
            replyChannel = 10005,
        }, registry, 1150)
        assert_eq(lateAct, "DROPPED")
        assert_eq(lateReason, "TOMBSTONE")

        -- Client 250ms retry (t=1250 > 1210) with same clientSeq must succeed when non-collinear node joins
        local retryNodes = {
            { id = "C1", x = 0, y = 80, z = 0 },
            { id = "C2", x = 500, y = 80, z = 0 },
            { id = "C3", x = 0, y = 80, z = 500 },
            { id = "C4", x = 500, y = 80, z = 500 },
        }
        local rAct, rPl, rCh
        for _, n in ipairs(retryNodes) do
            local d = math.sqrt((200 - n.x)^2 + (300 - n.z)^2)
            rAct, rPl, rCh = sched:ingestReport({
                targetClient = "AIRCRAFT_01",
                clientSeq = 1,
                nodeId = n.id,
                nodePos = { x = n.x, y = n.y, z = n.z },
                measuredDistance = d,
                clientAltitudeY = 80,
                replyChannel = 10005,
            }, registry, 1250)
        end
        assert_eq(rAct, "EARLY_SOLVED")
        assert_eq(rPl.status, "FIX_OK")
        assert_eq(rCh, 10005)
    end)
end)

describe("gps server handlers, CH 60002 status, nodes.json schema, and monitor_ui", function()
    local server = require("server")
    local monitor_ui = require("monitor_ui")
    local session_scheduler = require("session_scheduler")
    local node = require("node")
    local wizard_cli = require("wizard_cli")

    it("initializes registry from /gps_data/nodes.json nodeId/position schema", function()
        local nodesPath = "/gps_data/nodes.json"
        local hadNodes = fs.exists(nodesPath)
        local origRaw = nil
        if hadNodes then
            local f = fs.open(nodesPath, "r")
            origRaw = f and f.readAll()
            if f then f.close() end
        end
        storage_hal.writeJsonAtomic(nodesPath, {
            version = "1.9.5",
            nodes = {
                NODE_01 = { nodeId = "NODE_01", computerId = 1, position = { x = 10, y = 80, z = -20 }, status = "ONLINE" },
                NODE_02 = { nodeId = "NODE_02", computerId = 2, position = { x = 110, y = 80, z = -20 }, status = "OFFLINE" },
            }
        })
        local m = mock.modem({ wireless = true })
        sdk.patch(peripheral, "find", function(ptype)
            if ptype == "modem" then return m end
            return nil
        end)
        local okInit, _, _, _, state = pcall(server.initServer)
        if origRaw then
            local f = fs.open(nodesPath, "w")
            if f then f.write(origRaw); f.close() end
        elseif fs.exists(nodesPath) then
            fs.delete(nodesPath)
        end
        assert_true(okInit, tostring(state))
        assert_eq(#state.nodes, 2)
        assert_eq(state.nodes[1].id, "NODE_01")
        assert_eq(state.nodes[1].x, 10)
        assert_eq(state.nodes[1].z, -20)
        assert_eq(state.activeNodes, 1)
        assert_eq(state.listenChan, 60001)
        assert_eq(state.dataChan, 60002)
    end)

    it("handles EARLY_SOLVED TX, heartbeat payload.pos, and CH 60002 status requests", function()
        local m = mock.modem({ wireless = true })
        local sched = session_scheduler.new({ windowMs = 50, tombstoneTtlMs = 1000 })
        local registry = { nodes = {} }
        local state = {
            ticks = 400, solvedCount = 0, totalSolves = 0, seq = 1,
            activeNodes = 0, clientCount = 0, nodes = {}, clients = {}
        }

        -- Heartbeat with Zero-Fallback payload.pos
        local hbPkt = protocol.buildHeartbeat("NODE_09", 1, {
            nodeId = "NODE_09",
            computerId = 9,
            pos = { x = 123, y = 90, z = -456 },
            status = "ONLINE",
        }, 1000)
        server.handleModemMsg(sched, registry, m, state, { "modem_message", "top", protocol.CH_GPS_NODE_IN, protocol.CH_GPS_PING, hbPkt, 0 })
        assert_eq(#state.nodes, 1)
        assert_eq(state.nodes[1].id, "NODE_09")
        assert_eq(state.nodes[1].x, 123)
        assert_eq(state.nodes[1].z, -456)
        assert_eq(state.activeNodes, 1)

        -- 4-node EARLY_SOLVED must transmit on replyChannel 10005 without error and update clients
        local anchors = {
            { id = "N1", x = 0, y = 80, z = 0 },
            { id = "N2", x = 500, y = 80, z = 0 },
            { id = "N3", x = 0, y = 80, z = 500 },
            { id = "N4", x = 500, y = 80, z = 500 },
        }
        for idx, n in ipairs(anchors) do
            local d = math.sqrt((200 - n.x)^2 + (20 - 0)^2 + (300 - n.z)^2)
            local rep = protocol.buildNodeReport(n.id, idx, {
                targetClient = "AIRCRAFT_01",
                clientSeq = 12,
                nodeId = n.id,
                nodePos = { x = n.x, y = n.y, z = n.z },
                measuredDistance = d,
                clientAltitudeY = 100,
                replyChannel = 10005,
            }, 1010)
            server.handleModemMsg(sched, registry, m, state, { "modem_message", "top", protocol.CH_GPS_NODE_IN, protocol.CH_GPS_PING, rep, 0 })
        end
        assert_eq(state.solvedCount, 1)
        assert_eq(state.clientCount, 1)
        assert_eq(state.clients[1].id, "AIRCRAFT_01")
        assert_eq(m._transmitted[1].tx, 10005)
        assert_eq(m._transmitted[1].rx, protocol.CH_GPS_SERVICE)
        assert_eq(m._transmitted[1].pkt.type, protocol.MSG_RESPONSE)

        -- CH 60002 MSG_GPS_STATUS_REQ
        local stReq = protocol.buildStatusReq("GCS_01", 3, { queryType = "SUMMARY" }, 1020)
        server.handleModemMsg(sched, registry, m, state, { "modem_message", "top", protocol.CH_GPS_SERVICE, 50010, stReq, 0 })
        assert_eq(#m._transmitted, 2)
        assert_eq(m._transmitted[2].tx, 50010)
        assert_eq(m._transmitted[2].pkt.type, protocol.MSG_STATUS_RESP)
        assert_eq(m._transmitted[2].pkt.payload.activeNodes, 1)
        assert_eq(m._transmitted[2].pkt.payload.totalSolved, 1)
        assert_eq(m._transmitted[2].pkt.payload.uptime, 20)
    end)

    it("renders monitor_ui string IDs and 60001/60002 channels without format crash", function()
        local mon = mock.term(79, 36)
        local ui = monitor_ui.new({ width = 79, height = 36 })
        local st = {
            totalSolves = 5,
            activeNodes = 2,
            clientCount = 1,
            listenChan = 60001,
            dataChan = 60002,
            clients = { { id = "AIRCRAFT_01", x = 100.5, y = 80.0, z = -200.5, lastSeen = 0.2 } },
            nodes = { { id = "NODE_01", x = 0, y = 80, z = 0, status = "ONLINE", ping = 12 } },
        }
        ui:setTab(1); ui:render(mon, st)
        assert_true(mon:_contains("60001 (Listen) / 60002 (Data)"))
        ui:setTab(2); ui:render(mon, st)
        assert_true(mon:_contains("AIRCRAFT_01"), "Clients tab must render string IDs")
        assert_false(mon:_contains("Total Solved"), "Tab switch must clear previous tab rows")
        ui:setTab(3); ui:render(mon, st)
        assert_true(mon:_contains("NODE_01"), "Nodes tab must render string IDs")
    end)

    it("increments node report seq monotonically and wizard_cli saves atomically", function()
        local m = mock.modem({ wireless = true })
        local nCfg = { nodeId = "NODE_01", computerId = 5, position = { x = 0, y = 80, z = 0 } }
        local st = { reportsSent = 0, reportSeq = 0 }
        local req1 = protocol.buildRequest("AIRCRAFT_01", 1, { replyChannel = 10005, altitudeY = 80, clientType = "AIRCRAFT", clientSeq = 1 }, 1000)
        local req2 = protocol.buildRequest("AIRCRAFT_01", 2, { replyChannel = 10005, altitudeY = 80, clientType = "AIRCRAFT", clientSeq = 2 }, 1100)
        node.handlePingMessage(m, nCfg, protocol.CH_GPS_PING, req1, 50, st)
        node.handlePingMessage(m, nCfg, protocol.CH_GPS_PING, req2, 55, st)
        assert_eq(#m._transmitted, 2)
        assert_eq(m._transmitted[1].pkt.seq, 1)
        assert_eq(m._transmitted[2].pkt.seq, 2)

        local savePath = sdk.temp_path("wiz_node.json")
        sdk.patch(_G, "print", function() end)
        sdk.patch(_G, "write", function() end)
        sdk.patch(_G, "read", function() return "100 80 -200" end)
        local evIdx = 0
        local events = {
            { "modem_message", "top", protocol.CH_GPS_MGMT, protocol.CH_GPS_NODE_IN, { ver = "1.9.5", type = protocol.MSG_NODE_OFFER, payload = { suggestedNodeId = "NODE_07" } }, 0 },
            { "modem_message", "top", protocol.CH_GPS_MGMT, protocol.CH_GPS_NODE_IN, { ver = "1.9.5", type = protocol.MSG_NODE_VERIFY_RESP, payload = { passed = true, maxResidual = 0.1 } }, 0 },
            { "modem_message", "top", protocol.CH_GPS_MGMT, protocol.CH_GPS_NODE_IN, { ver = "1.9.5", type = protocol.MSG_NODE_REG_ACK, payload = { status = "COMMITTED" } }, 0 },
        }
        sdk.with_events_allowed(function()
            sdk.patch(os, "pullEvent", function()
                evIdx = evIdx + 1
                return table.unpack(events[evIdx])
            end)
            sdk.patch(os, "startTimer", function() return 1 end)
            sdk.patch(os, "epoch", function() return 1000 end)
            local commissioning = require("commissioning")
            local fsm = commissioning.newFSM({ hasConfig = false, computerId = 7 })
            local cfg = wizard_cli.runWizard(m, fsm, savePath)
            assert_eq(cfg.nodeId, "NODE_07")
            local saved = storage_hal.readJson(savePath)
            assert_not_nil(saved)
            assert_eq(saved.position.x, 100)
        end)
    end)
end)
```

- [ ] **Step 2: Run GPS unit tests to verify FAIL**

Run:
```powershell
python tools/run_unit_tests.py --target 0_infra/gps --clean-orphans
```
Expected: FAIL — `require("server")` blocks or returns `true`/errors before `EARLY_SOLVED`, `FAIL_GEOMETRY` is dropped, `monitor_ui` errors on `%d`, `node` blocks or keeps `seq=1`, and `wizard_cli` fails calling nil `storage_hal.writeJson`.

- [ ] **Step 3: Implement fixes in `session_scheduler.lua`, `server.lua`, `node.lua`, `monitor_ui.lua`, and `wizard_cli.lua`**

1. **`src/0_infra/gps/modules/session_scheduler.lua`** (`lines 53-157`):
   - In `tryEarlySolve(self, session, registry, nowMs)`: return `resp.payload, session.replyChannel` (`line 79`).
   - In `ingestReport`:
     ```lua
     local earlyPayload, earlyReplyCh = tryEarlySolve(self, session, registry, nowMs)
     if earlyPayload then return "EARLY_SOLVED", earlyPayload, earlyReplyCh end
     return "BUFFERED"
     ```
   - In `flushExpired`:
     ```lua
     if count >= 3 then
         local bbox = config_store.computeSwarmBBox(registry, session.reportsList)
         local sol, solErr = trilateration.solve(session.reportsList, session.clientAltitudeY, bbox)
         if sol then
             self:addTombstone(sKey, nowMs + self.tombstoneTtlMs)
             self.client_last_solved[session.targetClient] = math.max(
                 self.client_last_solved[session.targetClient] or 0,
                 session.clientSeq
             )
             self.client_last_solve_time[session.targetClient] = nowMs
             local resp = protocol.buildResponse("GPS_BASE_NET", 1, {
                 targetClient = session.targetClient,
                 clientSeq = session.clientSeq,
                 status = sol.status,
                 position = { x = sol.x, z = sol.z },
                 accuracy = sol.accuracy,
                 hdop = sol.hdop,
                 nodeCount = sol.nodeCount,
                 selectedNodes = sol.selectedNodes,
             }, nowMs)
             table.insert(responses, {
                 replyChannel = session.replyChannel,
                 clientAltitudeY = session.clientAltitudeY,
                 payload = resp.payload,
             })
         else
             self:addTombstone(sKey, nowMs + 150)
             local failGeom = protocol.buildResponse("GPS_BASE_NET", 1, {
                 targetClient = session.targetClient,
                 clientSeq = session.clientSeq,
                 status = solErr or "FAIL_GEOMETRY",
                 nodeCount = count,
                 selectedNodes = {},
             }, nowMs)
             table.insert(responses, {
                 replyChannel = session.replyChannel,
                 clientAltitudeY = session.clientAltitudeY,
                 payload = failGeom.payload,
             })
         end
     else
         self:addTombstone(sKey, nowMs + 150)
         local failResp = protocol.buildResponse("GPS_BASE_NET", 1, {
             targetClient = session.targetClient,
             clientSeq = session.clientSeq,
             status = "FAIL_INSUFFICIENT",
             nodeCount = count,
             selectedNodes = {},
         }, nowMs)
         table.insert(responses, {
             replyChannel = session.replyChannel,
             clientAltitudeY = session.clientAltitudeY,
             payload = failResp.payload,
         })
     end
     ```

2. **`src/0_infra/gps/server.lua`** (`lines 1-164`):
   - Add `local config_store = require("config_store")`.
   - Add local helpers `countOnlineNodes(nodes)` and `upsertClient(state, clientId, payload, altitudeY, nowMs)`:
     ```lua
     local function countOnlineNodes(nodes)
         local c = 0
         for _, n in ipairs(nodes or {}) do
             if n.status == "ONLINE" then c = c + 1 end
         end
         return c
     end

     local function upsertClient(state, clientId, payload, altitudeY, nowMs)
         if not payload or type(payload.position) ~= "table" or not clientId or clientId == "" then return end
         local cid = tostring(clientId)
         local altY = tonumber(altitudeY) or 0
         for _, c in ipairs(state.clients) do
             if c.id == cid then
                 c.x = tonumber(payload.position.x) or c.x
                 c.y = altY
                 c.z = tonumber(payload.position.z) or c.z
                 c.lastSeenMs = nowMs
                 c.lastSeen = 0
                 return
             end
         end
         table.insert(state.clients, {
             id = cid,
             x = tonumber(payload.position.x) or 0,
             y = altY,
             z = tonumber(payload.position.z) or 0,
             lastSeenMs = nowMs,
             lastSeen = 0,
         })
         state.clientCount = #state.clients
     end

     local function refreshClientAges(state, nowMs)
         for _, c in ipairs(state.clients or {}) do
             c.lastSeen = math.max(0, (nowMs - (c.lastSeenMs or nowMs)) / 1000.0)
         end
         state.clientCount = #(state.clients or {})
     end
     ```
   - Update `initServer()`: normalize `storage_hal.readJson("/gps_data/nodes.json")` via `config_store.normalizeServerRegistry(...)`, sort keys deterministically so UI order is stable, populate `state.nodes` strictly using `nd.nodeId`, `nd.position.{x,y,z}`, `nd.status or "ONLINE"`, set `state.activeNodes = countOnlineNodes(state.nodes)`, initialize `state.clientCount = 0`, `state.listenChan = protocol.CH_GPS_PING`, `state.dataChan = protocol.CH_GPS_SERVICE`.
   - Update `handleNodeReport`, `handleHeartbeat`, `handleStatusRequest`, `flushTimerExpired`, `handleModemMsg`, and bottom module guard (`main.lua` launches `shell.run("server.lua", "server")`, so do NOT guard on `args[1] == "server"`!):
     ```lua
     local function handleNodeReport(scheduler, registry, modem, state, msg)
         local ok = protocol.validatePacket(msg, protocol.MSG_NODE_REPORT)
         if not ok then return end
         local nowMs = os.epoch and os.epoch("utc") or 0
         local action, earlyPayload, earlyReplyCh = scheduler:ingestReport(msg.payload, registry, nowMs)
         if action == "EARLY_SOLVED" and earlyPayload then
             state.solvedCount = state.solvedCount + 1
             state.totalSolves = state.solvedCount
             state.lastSolvedStatus = earlyPayload.status
             upsertClient(state, earlyPayload.targetClient, earlyPayload, msg.payload.clientAltitudeY, nowMs)
             if harness_set_state then harness_set_state("last_solved_status", earlyPayload.status) end
             if modem and earlyReplyCh and earlyReplyCh > 0 then
                 state.seq = state.seq + 1
                 local pkt = protocol.buildResponse("GPS_BASE_NET", state.seq, earlyPayload, nowMs)
                 modem.transmit(earlyReplyCh, protocol.CH_GPS_SERVICE, pkt)
             end
         end
     end

     local function handleHeartbeat(state, msg, registry)
         local ok = protocol.validatePacket(msg, protocol.MSG_NODE_HEARTBEAT)
         if not ok or type(msg.payload) ~= "table" or not msg.payload.nodeId then return end
         local nid = tostring(msg.payload.nodeId)
         local pos = type(msg.payload.pos) == "table" and msg.payload.pos or nil
         local nextStatus = msg.payload.status or "ONLINE"
         if registry and type(registry.nodes) == "table" and registry.nodes[nid] then
             registry.nodes[nid].status = nextStatus
             registry.nodes[nid].lastHeartbeat = msg.time or (os.epoch and os.epoch("utc") or 0)
             if pos then
                 registry.nodes[nid].position = {
                     x = tonumber(pos.x) or (registry.nodes[nid].position and registry.nodes[nid].position.x) or 0,
                     y = tonumber(pos.y) or (registry.nodes[nid].position and registry.nodes[nid].position.y) or 0,
                     z = tonumber(pos.z) or (registry.nodes[nid].position and registry.nodes[nid].position.z) or 0,
                 }
             end
         end
         for _, n in ipairs(state.nodes) do
             if n.id == nid then
                 n.status = nextStatus
                 if pos then
                     n.x = tonumber(pos.x) or n.x
                     n.y = tonumber(pos.y) or n.y
                     n.z = tonumber(pos.z) or n.z
                 end
                 state.activeNodes = countOnlineNodes(state.nodes)
                 return
             end
         end
         table.insert(state.nodes, {
             id = nid,
             x = pos and (tonumber(pos.x) or 0) or 0,
             y = pos and (tonumber(pos.y) or 0) or 0,
             z = pos and (tonumber(pos.z) or 0) or 0,
             status = nextStatus,
             ping = 0,
         })
         state.activeNodes = countOnlineNodes(state.nodes)
     end

     local function handleStatusRequest(modem, state, evData)
         local msg = evData[5]
         local ok = protocol.validatePacket(msg, protocol.MSG_STATUS_REQ)
         if not ok or not modem then return end
         local replyCh = tonumber(evData[4])
         if not replyCh or replyCh < 1 or replyCh > 65535 then
             replyCh = protocol.CH_GPS_SERVICE
         end
         local nowMs = os.epoch and os.epoch("utc") or 0
         state.seq = state.seq + 1
         local pkt = protocol.buildStatusResp("GPS_BASE_NET", state.seq, {
             activeNodes = state.activeNodes or 0,
             uptime = math.floor((state.ticks or 0) / 20),
             totalSolved = state.solvedCount or 0,
             version = protocol.WIRE_VERSION,
         }, nowMs)
         modem.transmit(replyCh, protocol.CH_GPS_SERVICE, pkt)
     end

     local function flushTimerExpired(scheduler, registry, modem, state)
         local nowMs = os.epoch and os.epoch("utc") or 0
         local solved = scheduler:flushExpired(registry, nowMs)
         for _, item in ipairs(solved) do
             local st = item.payload and item.payload.status
             if st == "FIX_OK" or st == "FIX_DEGRADED" then
                 state.solvedCount = state.solvedCount + 1
                 state.totalSolves = state.solvedCount
             end
             state.lastSolvedStatus = st
             if item.payload and item.payload.position then
                 upsertClient(state, item.payload.targetClient, item.payload, item.clientAltitudeY, nowMs)
             end
             if harness_set_state then harness_set_state("last_solved_status", st) end
             if modem and item.replyChannel and item.replyChannel > 0 then
                 state.seq = state.seq + 1
                 local pkt = protocol.buildResponse("GPS_BASE_NET", state.seq, item.payload, nowMs)
                 modem.transmit(item.replyChannel, protocol.CH_GPS_SERVICE, pkt)
             end
         end
     end

     local function handleModemMsg(scheduler, registry, modem, state, evData)
         local channel, msg = evData[3], evData[5]
         if channel == protocol.CH_GPS_NODE_IN and type(msg) == "table" then
             if msg.type == protocol.MSG_NODE_REPORT then
                 handleNodeReport(scheduler, registry, modem, state, msg)
             elseif msg.type == protocol.MSG_NODE_HEARTBEAT then
                 handleHeartbeat(state, msg, registry)
             end
         elseif channel == protocol.CH_GPS_SERVICE and type(msg) == "table" then
             if msg.type == protocol.MSG_STATUS_REQ then
                 handleStatusRequest(modem, state, evData)
             end
         end
     end
     ```
   - Update `serverEventLoop`: call `refreshClientAges(state, os.epoch and os.epoch("utc") or 0)` right before `ui:render(mon, state)`.
   - Replace bottom `main()` with module/test guard and return export table:
     ```lua
     local args = { ... }
     local isRequired = (_G.describe ~= nil) or (type(args[2]) == "string" and args[2]:sub(-4) == ".lua")
     if not isRequired then
         main()
     end

     return {
         initServer = initServer,
         handleNodeReport = handleNodeReport,
         handleHeartbeat = handleHeartbeat,
         handleStatusRequest = handleStatusRequest,
         flushTimerExpired = flushTimerExpired,
         handleModemMsg = handleModemMsg,
         run = main,
     }
     ```

3. **`src/0_infra/gps/modules/monitor_ui.lua`** (`lines 81-171`):
   - In `renderOverviewTab`: `state.listenChan or 60001`, `state.dataChan or 60002`.
   - In `renderClientsTab` & `renderNodesTab` & `UI:render`:
     ```lua
     local function renderClientsTab(mon, state, w)
         local header, hf, hb = padLine("  ID         CLIENT POSITION (X, Y, Z)     LAST SEEN (s)", "d", "f", w)
         mon:setCursorPos(1, 4)
         mon:blit(header, hf, hb)
         local clients = state.clients or {}
         for i = 1, math.min(#clients, 25) do
             local c = clients[i]
             local idStr = string.sub(tostring(c.id or "?"), 1, 10)
             local row = string.format("  %-10s (%7.1f, %5.1f, %7.1f)  %5.1fs ago",
                 idStr, tonumber(c.x) or 0, tonumber(c.y) or 0, tonumber(c.z) or 0, tonumber(c.lastSeen) or 0)
             local t, f, b = padLine(row, "0", "f", w)
             mon:setCursorPos(1, 4 + i)
             mon:blit(t, f, b)
         end
     end

     local function renderNodesTab(mon, state, w)
         local header, hf, hb = padLine("  ID         NODE POSITION (X, Y, Z)       STATUS       PING", "b", "f", w)
         mon:setCursorPos(1, 4)
         mon:blit(header, hf, hb)
         local nodes = state.nodes or {}
         for i = 1, math.min(#nodes, 25) do
             local n = nodes[i]
             local idStr = string.sub(tostring(n.id or "?"), 1, 10)
             local row = string.format("  %-10s (%7.1f, %5.1f, %7.1f)  %-10s %dms",
                 idStr, tonumber(n.x) or 0, tonumber(n.y) or 0, tonumber(n.z) or 0, tostring(n.status or "OK"), tonumber(n.ping) or 0)
             local t, f, b = padLine(row, (n.status == "ONLINE" and "5" or "e"), "f", w)
             mon:setCursorPos(1, 4 + i)
             mon:blit(t, f, b)
         end
     end

     function UI:render(mon, state)
         local w = self.width
         local h = self.height
         renderHeader(mon, self.currentTab, w)
         local blankT, blankFg, blankBg = padLine("", "0", "f", w)
         for row = 3, h - 2 do
             mon:setCursorPos(1, row)
             mon:blit(blankT, blankFg, blankBg)
         end
         if self.currentTab == 1 then renderOverviewTab(mon, state, w)
         elseif self.currentTab == 2 then renderClientsTab(mon, state, w)
         elseif self.currentTab == 3 then renderNodesTab(mon, state, w)
         elseif self.currentTab == 4 then renderRadarTab(mon, state, w, h)
         end
         renderFooter(mon, w, h)
     end
     ```

4. **`src/0_infra/gps/node.lua`** (`lines 53-138`):
   - In `handlePingMessage`: increment `state.reportSeq = (state.reportSeq or 0) + 1` and pass `state.reportSeq` to `protocol.buildNodeReport(...)`.
   - Initialize `reportSeq = 0` inside `state` in `main(...)`.
   - Guard bottom `main(...)` with `local args = { ... }; local isRequired = (_G.describe ~= nil) or (type(args[2]) == "string" and args[2]:sub(-4) == ".lua"); if not isRequired then main(...) end` and return `{ loadOrCommissionNode = loadOrCommissionNode, handlePingMessage = handlePingMessage, sendHeartbeat = sendHeartbeat, run = main }`.

5. **`src/0_infra/gps/hal/wizard_cli.lua`** (`line 92`):
   - Change `storage_hal.writeJson(nodeCfgPath or "/gps_data/node.json", cfg)` to `storage_hal.writeJsonAtomic(nodeCfgPath or "/gps_data/node.json", cfg)`.

- [ ] **Step 4: Run GPS unit tests to verify PASS**

Run:
```powershell
python tools/run_unit_tests.py --target 0_infra/gps --clean-orphans
```
Expected: ALL `0_infra/gps` suites PASS with `ui_violation_count = 0` and `event_swallow_count = 0`.

- [ ] **Step 5: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/gps/modules/session_scheduler.lua src/0_infra/gps/server.lua src/0_infra/gps/node.lua src/0_infra/gps/modules/monitor_ui.lua src/0_infra/gps/hal/wizard_cli.lua tests/0_infra/gps/test_gps_core.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "fix(gps): repair early-solve replyChannel, FAIL_GEOMETRY response, CH 60002 status, and monitor_ui (TASK-122-2)"
```

---

### Task 3: GPS Client API Hardening, TTL Eviction & Status Query (`TASK-122-3`)

**Files:**
- Modify: `src/0_infra/gps/modules/client_core.lua:1-83`
- Modify: `src/0_infra/gps/hal/gps_client.lua:1-108`
- Modify: `tests/0_infra/gps/test_gps_core.lua`

**Interfaces:**
- Consumes: `src/0_infra/gps/modules/protocol.lua` (`CH_GPS_PING`, `CH_GPS_SERVICE`, `MSG_RESPONSE`, `MSG_STATUS_REQ`, `MSG_STATUS_RESP`)
- Produces:
  - `client_core:nextStatusRequestPacket(queryType, nowMs) -> seq, pkt`
  - `client_core:pollStatus() -> payload | nil`
  - `client_core` `5000ms` TTL eviction on `pendingResponses` (preserving `poll(seq) -> payload` return contract)
  - `gps_client.locate` `isManaged` 50%-timeout 1-time retry parity (`seq` reuse)
  - `gps_client.requestStatus(queryType, replyChannel) -> seq`, `gps_client.pollStatus() -> table|nil`, `gps_client.queryStatus(timeoutSec, queryType) -> table|nil, err`

- [ ] **Step 1: Write failing unit tests for `client_core` TTL & status query and `gps_client` `isManaged` retry**

Append the following suites to `tests/0_infra/gps/test_gps_core.lua`:
```lua
describe("gps client_core TTL pruning and CH 60002 status dispatch", function()
    it("prunes pendingResponses older than 5000ms while preserving active entries", function()
        local c = client_core.new()
        c:init("AIRCRAFT_01", "AIRCRAFT")
        local r1 = protocol.buildResponse("GPS_BASE_NET", 1, {
            targetClient = "AIRCRAFT_01", clientSeq = 1, status = "FIX_OK",
            position = { x = 10, z = 20 }, accuracy = 0.1, hdop = 1.0, nodeCount = 4
        }, 1000)
        local r2 = protocol.buildResponse("GPS_BASE_NET", 2, {
            targetClient = "AIRCRAFT_01", clientSeq = 2, status = "FIX_OK",
            position = { x = 30, z = 40 }, accuracy = 0.1, hdop = 1.0, nodeCount = 4
        }, 5500)
        assert_true(c:handleMessage(10005, r1, 1000))
        assert_true(c:handleMessage(10005, r2, 5500))
        -- Advance beyond 1000 + 5000 = 6000 on next request or message
        local _, _ = c:nextRequestPacket(80, 6200)
        assert_nil(c:poll(1), "Expired unpolled entry (>5000ms) must be pruned")
        local live = c:poll(2)
        assert_not_nil(live)
        assert_eq(live.position.x, 30)
    end)

    it("builds MSG_GPS_STATUS_REQ and consumes MSG_GPS_STATUS_RESP on CH 60002", function()
        local c = client_core.new()
        c:init("AIRCRAFT_01", "AIRCRAFT")
        local seq, reqPkt = c:nextStatusRequestPacket("SUMMARY", 1000)
        assert_eq(seq, 1)
        assert_true(protocol.validatePacket(reqPkt, protocol.MSG_STATUS_REQ))

        local stResp = protocol.buildStatusResp("GPS_BASE_NET", 5, {
            activeNodes = 4, uptime = 120, totalSolved = 42, version = "1.9.5"
        }, 1020)
        assert_false(c:handleMessage(99999, stResp, 1020))
        assert_true(c:handleMessage(protocol.CH_GPS_SERVICE, stResp, 1020))

        local polled = c:pollStatus()
        assert_not_nil(polled)
        assert_eq(polled.activeNodes, 4)
        assert_eq(polled.totalSolved, 42)
        assert_nil(c:pollStatus())
    end)
end)

describe("gps_client HAL managed retry parity and status query", function()
    local gps_client = require("gps_client")

    it("retries once at half-timeout with identical clientSeq when isManaged is true", function()
        local m = mock.modem({ wireless = true })
        sdk.patch(peripheral, "find", function(ptype)
            if ptype == "modem" then return m end
            return nil
        end)
        gps_client.init("AIRCRAFT_01", "AIRCRAFT", 10005)
        gps_client.setManaged(true)

        local nowMs = 1000
        local sleepCalls = 0
        sdk.with_events_allowed(function()
            sdk.patch(os, "epoch", function() return nowMs end)
            sdk.patch(_G, "sleep", function(sec)
                sleepCalls = sleepCalls + 1
                nowMs = nowMs + math.floor((tonumber(sec) or 0.05) * 1000)
                if sleepCalls == 6 and #m._transmitted >= 2 then
                    local secondSeq = m._transmitted[2].pkt.payload.clientSeq
                    local resp = protocol.buildResponse("GPS_BASE_NET", 1, {
                        targetClient = "AIRCRAFT_01",
                        clientSeq = secondSeq,
                        status = "FIX_OK",
                        position = { x = 250.0, z = -125.0 },
                        accuracy = 0.2,
                        hdop = 1.1,
                        nodeCount = 4,
                    }, nowMs)
                    gps_client.handleMessage("top", 10005, 60002, resp, 10)
                end
            end)
            local x, y, z, meta = gps_client.locate(120.0, 0.5)
            assert_near(x, 250.0, 1e-4)
            assert_eq(y, 120.0)
            assert_near(z, -125.0, 1e-4)
            assert_eq(meta.status, "FIX_OK")
        end)
        gps_client.setManaged(false)
        assert_eq(#m._transmitted, 2, "isManaged locate must emit initial + 1 half-timeout retry")
        assert_eq(m._transmitted[1].pkt.payload.clientSeq, m._transmitted[2].pkt.payload.clientSeq)
    end)

    it("exposes requestStatus and pollStatus over CH 60002", function()
        local m = mock.modem({ wireless = true })
        sdk.patch(peripheral, "find", function(ptype)
            if ptype == "modem" then return m end
            return nil
        end)
        gps_client.init("AIRCRAFT_01", "AIRCRAFT", 10005)
        local seq = gps_client.requestStatus("SUMMARY", protocol.CH_GPS_SERVICE)
        assert_true(seq >= 1)
        assert_eq(m._transmitted[1].tx, protocol.CH_GPS_SERVICE)
        assert_eq(m._transmitted[1].rx, protocol.CH_GPS_SERVICE)
        assert_eq(m._transmitted[1].pkt.type, protocol.MSG_STATUS_REQ)

        local resp = protocol.buildStatusResp("GPS_BASE_NET", 2, {
            activeNodes = 5, uptime = 60, totalSolved = 9, version = "1.9.5"
        }, 2000)
        assert_true(gps_client.handleMessage("top", protocol.CH_GPS_SERVICE, protocol.CH_GPS_SERVICE, resp, 0))
        local polled = gps_client.pollStatus()
        assert_not_nil(polled)
        assert_eq(polled.activeNodes, 5)
    end)
end)
```

- [ ] **Step 2: Run GPS unit tests to verify FAIL**

Run:
```powershell
python tools/run_unit_tests.py --target 0_infra/gps --clean-orphans
```
Expected: FAIL — `client_core` has no `nextStatusRequestPacket` / `pollStatus` / TTL eviction, and `gps_client` emits only 1 request under `isManaged == true` and lacks `requestStatus` / `pollStatus`.

- [ ] **Step 3: Implement TTL pruning, retry parity, and status query API**

1. **`src/0_infra/gps/modules/client_core.lua`**:
   - Track `self.latestStatus = nil` and `self.pendingTtlMs = 5000` inside `client_core.new()`.
   - Add local helper `pruneExpiredPending(self, nowMs)`:
     ```lua
     local function pruneExpiredPending(self, nowMs)
         local now = tonumber(nowMs)
         if not now then return end
         local ttl = self.pendingTtlMs or 5000
         for k, entry in pairs(self.pendingResponses) do
             if now - (entry.storedAt or 0) > ttl then
                 self.pendingResponses[k] = nil
             end
         end
     end
     ```
   - Call `pruneExpiredPending(self, nowMs)` at the top of `nextRequestPacket` and before storing in `handleMessage`.
   - Store `self.pendingResponses[cSeq] = { payload = pl, storedAt = tonumber(nowMs) or 0 }`.
   - In `poll(clientSeq)`: read `local entry = self.pendingResponses[cSeq]`; clear key and return `entry.payload`.
   - Add `nextStatusRequestPacket(self, queryType, nowMs)`:
     ```lua
     function client_core:nextStatusRequestPacket(queryType, nowMs)
         self.seq = self.seq + 1
         local pkt = protocol.buildStatusReq(self.domainId, self.seq, {
             queryType = tostring(queryType or "SUMMARY"),
         }, nowMs)
         return self.seq, pkt
     end
     ```
   - Update `handleMessage(self, channel, message, nowMs)`:
     ```lua
     function client_core:handleMessage(channel, message, nowMs)
         if type(message) ~= "table" then return false end
         local ch = tonumber(channel)
         if message.type == protocol.MSG_RESPONSE then
             if ch ~= self.replyChannel then return false end
             local ok = protocol.validatePacket(message, protocol.MSG_RESPONSE)
             if not ok then return false end
             local pl = message.payload
             if pl.targetClient ~= self.domainId then return false end
             local cSeq = tonumber(pl.clientSeq)
             if not cSeq then return false end
             pruneExpiredPending(self, nowMs)
             self.pendingResponses[cSeq] = { payload = pl, storedAt = tonumber(nowMs) or 0 }
             return true
         elseif message.type == protocol.MSG_STATUS_RESP then
             if ch ~= self.replyChannel and ch ~= protocol.CH_GPS_SERVICE then return false end
             local ok = protocol.validatePacket(message, protocol.MSG_STATUS_RESP)
             if not ok then return false end
             self.latestStatus = message.payload
             return true
         end
         return false
     end

     function client_core:pollStatus()
         local st = self.latestStatus
         self.latestStatus = nil
         return st
     end
     ```

2. **`src/0_infra/gps/hal/gps_client.lua`**:
   - Line 65 (`standaloneLocate`): replace `os.epoch("utc")` with `os.epoch and os.epoch("utc") or 0`.
   - Update `gps_client.locate(altitudeY, timeoutSec)` when `instance.isManaged == true`:
     ```lua
     function gps_client.locate(altitudeY, timeoutSec)
         if instance.isManaged then
             local modem = peripheral and peripheral.find and peripheral.find("modem")
             if not modem then return nil, nil, nil, { status = "NO_MODEM" } end
             local startMs = os.epoch and os.epoch("utc") or 0
             local seq, pkt = instance:nextRequestPacket(altitudeY, startMs)
             modem.transmit(protocol.CH_GPS_PING, instance.replyChannel, pkt)
             local totalMs = (tonumber(timeoutSec) or 0.5) * 1000
             local halfAtMs = startMs + totalMs * 0.5
             local deadline = startMs + totalMs
             local retried = false
             while true do
                 local fix = instance:poll(seq)
                 if fix then
                     if fix.position then return fix.position.x, altitudeY, fix.position.z, fix end
                     return nil, nil, nil, fix
                 end
                 local nowMs = os.epoch and os.epoch("utc") or 0
                 if nowMs >= deadline then break end
                 if not retried and nowMs >= halfAtMs then
                     retried = true
                     local _, retryPkt = instance:nextRequestPacket(altitudeY, nowMs, seq)
                     modem.transmit(protocol.CH_GPS_PING, instance.replyChannel, retryPkt)
                 end
                 sleep(0.05)
             end
             return nil, nil, nil, { status = "TIMEOUT" }
         else
             return standaloneLocate(altitudeY, timeoutSec)
         end
     end
     ```
   - Add status query helpers (`requestStatus`, `pollStatus`, `queryStatus`):
     ```lua
     function gps_client.requestStatus(queryType, replyChannel)
         local modem = peripheral and peripheral.find and peripheral.find("modem")
         if not modem then error("No modem attached for GPS client", 2) end
         local nowMs = os.epoch and os.epoch("utc") or 0
         local seq, pkt = instance:nextStatusRequestPacket(queryType, nowMs)
         modem.transmit(protocol.CH_GPS_SERVICE, tonumber(replyChannel) or protocol.CH_GPS_SERVICE, pkt)
         return seq
     end

     function gps_client.pollStatus()
         return instance:pollStatus()
     end

     function gps_client.queryStatus(timeoutSec, queryType)
         if instance.isManaged then
             gps_client.requestStatus(queryType, protocol.CH_GPS_SERVICE)
             local deadline = (os.epoch and os.epoch("utc") or 0) + (tonumber(timeoutSec) or 0.5) * 1000
             while (os.epoch and os.epoch("utc") or 0) < deadline do
                 local st = instance:pollStatus()
                 if st then return st, nil end
                 sleep(0.05)
             end
             return nil, "TIMEOUT"
         end
         local modem = peripheral and peripheral.find and peripheral.find("modem")
         if not modem then return nil, "NO_MODEM" end
         modem.open(protocol.CH_GPS_SERVICE)
         local nowMs = os.epoch and os.epoch("utc") or 0
         local _, pkt = instance:nextStatusRequestPacket(queryType, nowMs)
         modem.transmit(protocol.CH_GPS_SERVICE, protocol.CH_GPS_SERVICE, pkt)
         local tEnd = os.startTimer(tonumber(timeoutSec) or 0.5)
         while true do
             local evData = { os.pullEvent() }
             if evData[1] == "timer" and evData[2] == tEnd then
                 return nil, "TIMEOUT"
             elseif evData[1] == "modem_message" then
                 if instance:handleMessage(evData[3], evData[5], os.epoch and os.epoch("utc") or 0) then
                     local st = instance:pollStatus()
                     if st then return st, nil end
                 end
             end
         end
     end
     ```

- [ ] **Step 4: Run GPS unit tests to verify PASS**

Run:
```powershell
python tools/run_unit_tests.py --target 0_infra/gps --clean-orphans
```
Expected: ALL `0_infra/gps` tests PASS (`0` UI violations, `0` swallowed events).

- [ ] **Step 5: Commit Task 3**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/gps/modules/client_core.lua src/0_infra/gps/hal/gps_client.lua tests/0_infra/gps/test_gps_core.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(gps): add isManaged retry parity, response TTL pruning, and CH 60002 status query (TASK-122-3)"
```

---

### Task 4: Landing Pad GPS Client Zero-Fallback, Config Normalization & Dual-Rate Scheduling (`TASK-122-4`)

**Files:**
- Modify: `src/0_infra/landing_pad/modules/config_store.lua:1-138`
- Modify: `src/0_infra/landing_pad/modules/setup_wizard.lua:46-73`
- Modify: `src/0_infra/landing_pad/modules/gps_client.lua:1-158`
- Modify: `src/0_infra/landing_pad/main.lua:20-232`
- Modify: `tests/0_infra/landing_pad/test_gps_client.lua:1-87`
- Modify: `tests/0_infra/landing_pad/test_config_store.lua:1-42`
- Modify: `tests/0_infra/landing_pad/test_setup_and_tui.lua:1-90`

**Interfaces:**
- Consumes: `/landing_pad/config.json` (both `installer/modules/manifest.lua` `defaultConfigs` flat format and `setup_wizard` config), `modules/offset_transform.lua`
- Produces:
  - `config_store.normalize_config(raw)` returning unified canonical fields (`facilityId`, `padId`, `sectorId`, `sectorIndex`, `padIndex`, `mobility`, `mode`, `gacChannel`, `sectorFacilityChannel`, `sectorGpsReplyChannel`, `tacticalChannel`, `channels = { ... }`) passing `validate_config`
  - `setup_wizard:assemble_config(stepData)` passing `config_store.validate_config`
  - `gps_client` Zero-Fallback wire client: `clientType == "FACILITY"`, sector `Base_sec+5` (`50206` default, never `60001`), strict `ver == "1.9.5"` + `targetClient == facilityId` + `pendingSeq` sequence check + `"FIX_OK"` / `"FIX_DEGRADED"` acceptance only, `has_valid_fix()`, and `should_query_gps(fsmState, tickCount)` (`STATIC` once; `DYNAMIC` 5Hz in `RESERVED`/`APPROACH_DYNAMIC`, else 1Hz)
  - `landing_pad/main.lua` passing `reqPkt.payload.replyChannel` as CC `replyChannel` and honoring `should_query_gps`

- [ ] **Step 1: Write failing Landing Pad tests for `"FACILITY"`, Zero-Fallback status/seq validation, dual-rate cadence, and config normalization**

1. Replace the GPS-related tests in `tests/0_infra/landing_pad/test_gps_client.lua` with aligned `FACILITY`/`FIX_OK`/`FIX_DEGRADED`, negative Zero-Fallback, dual-rate cadence, and `STATIC` health tests:
   ```lua
   -- tests/0_infra/landing_pad/test_gps_client.lua
   local gps_client = require("gps_client")
   local offset_transform = require("offset_transform")

   describe("Landing pad GPS client and 20Hz dead reckoning", function()
       local dummyCfg = {
           facilityId = "PAD_ALPHA",
           sectorId = 1,
           mobility = "DYNAMIC",
           channels = {
               sectorGpsReplyChannel = 50206
           },
           position = { x = 100.0, y = 64.0, z = 200.0 },
           mountingYawOffset = 0.0,
           bodyOffset = { forward = 5.0, right = 0.0, up = 1.0 }
       }

       it("builds standard MSG_GPS_REQUEST packet with FACILITY type and derives 50206 default", function()
           local client = gps_client.create(dummyCfg, offset_transform)
           local pkt = client:build_request_packet(64.5, 12345678)
           assert_eq(pkt.ver, "1.9.5")
           assert_eq(pkt.type, "MSG_GPS_REQUEST")
           assert_eq(pkt.domainId, "PAD_ALPHA")
           assert_eq(pkt.payload.replyChannel, 50206)
           assert_eq(pkt.payload.altitudeY, 64.5)
           assert_eq(pkt.payload.clientType, "FACILITY")
           assert_eq(pkt.payload.clientSeq, 1)

           local flatDerived = gps_client.create({
               facilityId = "PAD_NO_CH",
               sectorId = 2,
               mobility = "STATIC",
               position = { x = 0, y = 64, z = 0 },
           }, offset_transform)
           local pkt2 = flatDerived:build_request_packet(64.0, 2000)
           assert_eq(pkt2.payload.replyChannel, 50406)
       end)

       it("handles FIX_OK and FIX_DEGRADED MSG_GPS_RESPONSE and rejects legacy/replayed/foreign packets", function()
           local client = gps_client.create(dummyCfg, offset_transform)
           assert_false(client:has_valid_fix())

           -- Unrequested response (pendingSeq == nil) must be rejected
           local unsolicited = {
               ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 1, time = 900,
               payload = { targetClient = "PAD_ALPHA", clientSeq = 1, status = "FIX_OK", position = { x = 10, z = 20 } }
           }
           assert_false(client:handle_response_packet(unsolicited, 9.0))

           local req = client:build_request_packet(64.0, 1000)
           local seq1 = req.payload.clientSeq

           -- Legacy OK / SUCCESS and non-1.9.5 / foreign target must be rejected
           assert_false(client:handle_response_packet({
               ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 2, time = 1010,
               payload = { targetClient = "PAD_ALPHA", clientSeq = seq1, status = "OK", position = { x = 10, z = 20 } }
           }, 10.0))
           assert_false(client:handle_response_packet({
               ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 3, time = 1010,
               payload = { targetClient = "PAD_ALPHA", clientSeq = seq1, status = "SUCCESS", position = { x = 10, z = 20 } }
           }, 10.0))
           assert_false(client:handle_response_packet({
               ver = "1.8.0", type = "MSG_GPS_RESPONSE", seq = 4, time = 1010,
               payload = { targetClient = "PAD_ALPHA", clientSeq = seq1, status = "FIX_OK", position = { x = 10, z = 20 } }
           }, 10.0))
           assert_false(client:handle_response_packet({
               ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 5, time = 1010,
               payload = { targetClient = "PAD_BETA", clientSeq = seq1, status = "FIX_OK", position = { x = 10, z = 20 } }
           }, 10.0))
           assert_false(client:handle_response_packet({
               ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 6, time = 1010,
               payload = { targetClient = "PAD_ALPHA", clientSeq = 999, status = "FIX_OK", position = { x = 10, z = 20 } }
           }, 10.0))

           local validResp = {
               ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 7, time = 1020,
               payload = {
                   targetClient = "PAD_ALPHA",
                   clientSeq = seq1,
                   status = "FIX_OK",
                   position = { x = 840.0, z = 1120.0 },
                   accuracy = 0.2,
                   hdop = 1.1
               }
           }
           assert_true(client:handle_response_packet(validResp, 10.0))
           assert_true(client:has_valid_fix())
           -- Replaying the already consumed clientSeq must be rejected
           assert_false(client:handle_response_packet(validResp, 10.1))

           local compPos = client:get_current_comp_pos()
           assert_near(compPos.x, 840.0, 1e-4)
           assert_near(compPos.z, 1120.0, 1e-4)
           local padPos = client:get_current_pad_pos()
           assert_near(padPos.x, 840.0, 1e-4)
           assert_near(padPos.y, 65.0, 1e-4)
           assert_near(padPos.z, 1115.0, 1e-4)

           -- FAIL_GEOMETRY consumes pendingSeq cleanly and rejects coordinate update
           local req2 = client:build_request_packet(64.0, 1100)
           assert_false(client:handle_response_packet({
               ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 8, time = 1120,
               payload = { targetClient = "PAD_ALPHA", clientSeq = req2.payload.clientSeq, status = "FAIL_GEOMETRY" }
           }, 11.2))
           assert_false(client:handle_response_packet({
               ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 9, time = 1130,
               payload = { targetClient = "PAD_ALPHA", clientSeq = req2.payload.clientSeq, status = "FIX_OK", position = { x = 0, z = 0 } }
           }, 11.3))

           -- FIX_DEGRADED is accepted for new request
           local req3 = client:build_request_packet(64.0, 1200)
           assert_true(client:handle_response_packet({
               ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 10, time = 1220,
               payload = { targetClient = "PAD_ALPHA", clientSeq = req3.payload.clientSeq, status = "FIX_DEGRADED", position = { x = 842.0, z = 1121.0 }, hdop = 6.2 }
           }, 12.2))
           assert_near(client:get_current_comp_pos().x, 842.0, 1e-4)
       end)

       it("enforces dual-rate (1Hz / 5Hz / STATIC-once) GPS query scheduling and STATIC health", function()
           local dynClient = gps_client.create(dummyCfg, offset_transform)
           assert_false(dynClient:should_query_gps("IDLE", 4))
           assert_true(dynClient:should_query_gps("IDLE", 20))
           assert_true(dynClient:should_query_gps("RESERVED", 4))
           assert_true(dynClient:should_query_gps("APPROACH_DYNAMIC", 8))
           assert_false(dynClient:should_query_gps("APPROACH_DYNAMIC", 9))

           local statClient = gps_client.create({
               facilityId = "PAD_STATIC_01",
               sectorId = 1,
               mobility = "STATIC",
               position = { x = 0, y = 64, z = 0 },
           }, offset_transform)
           assert_true(statClient:should_query_gps("IDLE", 20))
           local sReq = statClient:build_request_packet(64.0, 1000)
           assert_true(statClient:handle_response_packet({
               ver = "1.9.5", type = "MSG_GPS_RESPONSE", seq = 1, time = 1020,
               payload = { targetClient = "PAD_STATIC_01", clientSeq = sReq.payload.clientSeq, status = "FIX_OK", position = { x = 50.0, z = 60.0 } }
           }, 10.0))
           assert_false(statClient:should_query_gps("IDLE", 40))
           assert_true(statClient:check_gps_health(999.0))
           assert_false(statClient:is_degraded())
       end)

       it("integrates dead reckoning at 20Hz (dt = 0.05) using velocity", function()
           local client = gps_client.create(dummyCfg, offset_transform)
           client:set_comp_pos(100.0, 60.0, 200.0)
           client:update_dead_reckoning(0.05, {
               velocity = { vx = 10.0, vy = 2.0, vz = -5.0 },
               acceleration = { ax = 0.0, ay = 0.0, az = 0.0 },
               attitude = { pitch = 0.0, roll = 0.0, yaw = 90.0 }
           })
           assert_near(client:get_current_comp_pos().x, 100.5, 1e-4)
           assert_near(client:get_current_comp_pos().y, 60.1, 1e-4)
           assert_near(client:get_current_comp_pos().z, 199.75, 1e-4)
       end)

       it("flags degraded health when DYNAMIC GPS ping silent > 2.0s", function()
           local client = gps_client.create(dummyCfg, offset_transform)
           client:set_last_gps_time(10.0)
           assert_true(client:check_gps_health(11.5))
           assert_false(client:check_gps_health(12.5))
           assert_true(client:is_degraded())
       end)
   end)
   ```
2. Append to `tests/0_infra/landing_pad/test_config_store.lua`:
   ```lua
       it("normalizes flat manifest.lua schema into unified config table", function()
           local flat = {
               facilityId = "PAD_MANIFEST_02",
               sectorId = 2,
               padIndex = 3,
               mobility = "DYNAMIC",
               gacChannel = 50401,
               sectorFacilityChannel = 50402,
               sectorGpsReplyChannel = 50406,
               tacticalChannel = 50413,
           }
           local norm = config_store.normalize_config(flat)
           local ok, err = config_store.validate_config(norm)
           assert_true(ok, err)
           assert_eq(norm.padId, "PAD_MANIFEST_02")
           assert_eq(norm.mode, "DYNAMIC")
           assert_eq(norm.channels.sectorChannel, 50401)
           assert_eq(norm.channels.sectorGpsReplyChannel, 50406)
           assert_eq(norm.channels.tacticalChannel, 50413)
       end)
   ```
3. Append to `tests/0_infra/landing_pad/test_setup_and_tui.lua`:
   ```lua
       it("assembles schema-valid configuration passing config_store.validate_config", function()
           local config_store = require("config_store")
           local wizard = setup_wizard.create(offset_transform)
           local assembled = wizard:assemble_config({
               padId = "PAD_WIZ_01",
               sectorIndex = 2,
               padIndex = 4,
               mode = "DYNAMIC",
               x = 120, y = 70, z = -340,
           })
           local ok, err = config_store.validate_config(assembled)
           assert_true(ok, err)
           assert_eq(assembled.facilityId, "PAD_WIZ_01")
           assert_eq(assembled.sectorId, 2)
           assert_eq(assembled.gacChannel, 50401)
           assert_eq(assembled.sectorFacilityChannel, 50402)
           assert_eq(assembled.sectorGpsReplyChannel, 50406)
           assert_eq(assembled.tacticalChannel, 50414)
       end)
   ```

- [ ] **Step 2: Run Landing Pad unit tests to verify FAIL**

Run:
```powershell
python tools/run_unit_tests.py --target 0_infra/landing_pad --clean-orphans
```
Expected: FAIL — `clientType` is `"LANDING_PAD"`, `"OK"` still accepted / `"FIX_OK"` rejected, `normalize_config` missing, `should_query_gps` missing, wizard config fails `validate_config`.

- [ ] **Step 3: Implement `config_store`, `setup_wizard`, `gps_client`, and `main.lua` updates**

1. **`src/0_infra/landing_pad/modules/config_store.lua`**:
   - Add `config_store.normalize_config(raw)`:
     ```lua
     function config_store.normalize_config(raw)
         local cfg = {}
         if type(raw) == "table" then
             for k, v in pairs(raw) do cfg[k] = v end
         end
         local def = config_store.get_default_config()
         local fid = tostring(cfg.facilityId or cfg.padId or def.facilityId)
         local secId = tonumber(cfg.sectorId or cfg.sectorIndex) or def.sectorId
         local pIdx = tonumber(cfg.padIndex) or def.padIndex
         local mob = tostring(cfg.mobility or cfg.mode or def.mobility)
         local baseSec = 50001 + secId * 200
         local inCh = type(cfg.channels) == "table" and cfg.channels or {}

         local gacCh = tonumber(inCh.sectorChannel or cfg.gacChannel) or baseSec
         local facCh = tonumber(inCh.sectorFacilityChannel or cfg.sectorFacilityChannel) or (baseSec + 1)
         local gpsCh = tonumber(inCh.sectorGpsReplyChannel or cfg.sectorGpsReplyChannel) or (baseSec + 5)
         local tacCh = tonumber(inCh.tacticalChannel or cfg.tacticalChannel) or (baseSec + 10 + (pIdx - 1))

         cfg.version = tostring(cfg.version or cfg.ver or def.version)
         cfg.ver = tostring(cfg.ver or cfg.version)
         cfg.facilityId = fid
         cfg.padId = fid
         cfg.sectorId = secId
         cfg.sectorIndex = secId
         cfg.padIndex = pIdx
         cfg.mobility = mob
         cfg.mode = mob
         cfg.gacChannel = gacCh
         cfg.sectorFacilityChannel = facCh
         cfg.sectorGpsReplyChannel = gpsCh
         cfg.tacticalChannel = tacCh
         cfg.channels = {
             sectorChannel = gacCh,
             sectorFacilityChannel = facCh,
             sectorGpsReplyChannel = gpsCh,
             tacticalChannel = tacCh,
         }
         cfg.mountingYawOffset = tonumber(cfg.mountingYawOffset) or def.mountingYawOffset
         cfg.bodyOffset = type(cfg.bodyOffset) == "table" and cfg.bodyOffset or { forward = 0.0, right = 0.0, up = 0.0 }
         cfg.position = type(cfg.position) == "table" and cfg.position or { x = 0.0, y = 64.0, z = 0.0 }
         cfg.approachHeading = tonumber(cfg.approachHeading) or def.approachHeading
         cfg.safeDescentRate = tonumber(cfg.safeDescentRate) or def.safeDescentRate
         cfg.clearanceZoneRadius = tonumber(cfg.clearanceZoneRadius) or def.clearanceZoneRadius
         cfg.maxSupportedWeight = tonumber(cfg.maxSupportedWeight) or def.maxSupportedWeight
         cfg.wirelessModemSide = tostring(cfg.wirelessModemSide or def.wirelessModemSide)
         cfg.slotDurationSec = tonumber(cfg.slotDurationSec) or def.slotDurationSec
         return cfg
     end
     ```
   - In `load_config`: normalize `local normalized = config_store.normalize_config(data)`, validate `normalized`, and return `normalized, nil`.

2. **`src/0_infra/landing_pad/modules/setup_wizard.lua`** (`lines 46-73`):
   - In `wizard:assemble_config(stepData)`: populate `facilityId`, `padId`, `sectorId`, `sectorIndex`, `padIndex`, `mobility`, `mode`, `gacChannel = ch.sectorChannel`, `sectorFacilityChannel = ch.sectorFacilityChannel`, `sectorGpsReplyChannel = ch.sectorGpsReplyChannel`, `tacticalChannel = ch.tacticalChannel`, `channels = ch`, `wirelessModemSide`, `slotDurationSec`, `version = "2.4.0"`, `ver = "2.4.0"`.

3. **`src/0_infra/landing_pad/modules/gps_client.lua`** (`lines 1-158`):
   - Resolve `facilityId = tostring(config.facilityId or config.padId or "PAD")`, `mobility = tostring(config.mobility or config.mode or "STATIC")`, and `replyChannel = (config.channels and tonumber(config.channels.sectorGpsReplyChannel)) or tonumber(config.sectorGpsReplyChannel) or (50001 + (tonumber(config.sectorId or config.sectorIndex) or 1) * 200 + 5)`.
   - Track `hasValidFix = false`, `lastStatus = nil`, `lastAccuracy = nil`, `lastHdop = nil` inside `state`.
   - In `build_request_packet`: emit `domainId = state.facilityId`, `clientType = "FACILITY"`, `replyChannel = state.replyChannel`, `clientSeq = state.seq`.
   - In `handle_response_packet(msg, nowSec)`:
     ```lua
     function client:handle_response_packet(msg, nowSec)
         if type(msg) ~= "table" then return false end
         if msg.ver ~= WIRE_VERSION or msg.type ~= "MSG_GPS_RESPONSE" then return false end
         local payload = msg.payload
         if type(payload) ~= "table" then return false end
         if payload.targetClient ~= state.facilityId then return false end
         local cSeq = tonumber(payload.clientSeq)
         if state.pendingSeq == nil or not cSeq or cSeq ~= state.pendingSeq then return false end
         state.pendingSeq = nil
         state.lastStatus = payload.status

         if payload.status ~= "FIX_OK" and payload.status ~= "FIX_DEGRADED" then
             return false
         end
         if type(payload.position) ~= "table" or type(payload.position.x) ~= "number" or type(payload.position.z) ~= "number" then
             return false
         end

         state.compPos.x = payload.position.x
         state.compPos.z = payload.position.z
         state.lastAccuracy = tonumber(payload.accuracy)
         state.lastHdop = tonumber(payload.hdop)
         state.hasValidFix = true
         state.lastGpsTime = nowSec or (os.clock and os.clock() or 0)
         state.isDegraded = false
         recalculate_pad_pos()
         return true
     end
     ```
   - Update `check_gps_health(nowSec)` so `STATIC` pads with a valid initial fix stay healthy (`state.mobility == "STATIC" and state.hasValidFix` -> `state.isDegraded = false; return true`), and `update_dead_reckoning` checks `state.mobility == "DYNAMIC"`.
   - Add `client:has_valid_fix()` and `client:should_query_gps(fsmState, tickCount)`:
     ```lua
     function client:check_gps_health(nowSec)
         if state.mobility == "STATIC" and state.hasValidFix then
             state.isDegraded = false
             return true
         end
         local t = nowSec or (os.clock and os.clock() or 0)
         if (t - state.lastGpsTime) > GPS_TIMEOUT_SEC then
             state.isDegraded = true
             return false
         end
         state.isDegraded = false
         return true
     end

     function client:has_valid_fix()
         return state.hasValidFix == true
     end

     function client:should_query_gps(fsmState, tickCount)
         local tick = tonumber(tickCount) or 0
         if tick <= 0 then return false end
         if state.mobility == "STATIC" then
             return (not state.hasValidFix) and (tick % 20 == 0)
         end
         local interval = (fsmState == "RESERVED" or fsmState == "APPROACH_DYNAMIC") and 4 or 20
         return (tick % interval) == 0
     end
     ```

4. **`src/0_infra/landing_pad/main.lua`**:
   - Normalize `cfg = config_store.normalize_config(cfg)` after load (`lines 21-25`).
   - Update `send_packet(channel, pkt, replyCh)` to `modem.transmit(channel, replyCh or channel, pkt)`.
   - Extract GPS query OUTSIDE the `tickCount % 20 == 0` gate so 5Hz (`tickCount % 4 == 0`) runs during `RESERVED` / `APPROACH_DYNAMIC`, passing the GPS computer altitude `gpsClient:get_current_comp_pos().y` and `reqPkt.payload.replyChannel`:
     ```lua
     if gpsClient:should_query_gps(currentState, tickCount) then
         local compPos = gpsClient:get_current_comp_pos()
         local reqPkt = gpsClient:build_request_packet(compPos.y)
         send_packet(GPS_PING_CHANNEL, reqPkt, reqPkt.payload.replyChannel)
     end
     ```

- [ ] **Step 4: Run Landing Pad unit tests to verify PASS**

Run:
```powershell
python tools/run_unit_tests.py --target 0_infra/landing_pad --clean-orphans
```
Expected: ALL `0_infra/landing_pad` suites PASS.

- [ ] **Step 5: Commit Task 4**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_infra/landing_pad/modules/config_store.lua src/0_infra/landing_pad/modules/setup_wizard.lua src/0_infra/landing_pad/modules/gps_client.lua src/0_infra/landing_pad/main.lua tests/0_infra/landing_pad/test_gps_client.lua tests/0_infra/landing_pad/test_config_store.lua tests/0_infra/landing_pad/test_setup_and_tui.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "fix(landing_pad): enforce FACILITY FIX_OK/FIX_DEGRADED protocol, replyChannel, and dual-rate GPS cadence (TASK-122-4)"
```

---

### Task 5: FCP Envelope `time`, Target/Seq Guard, Kinematic Gate `delta_t` & Altitude Sync (`TASK-122-5`)

**Files:**
- Modify: `src/2_guidance/fcp/modules/network_manager.lua:99-134`
- Modify: `src/2_guidance/fcp/modules/nav_engine.lua:4-120`
- Modify: `tests/2_guidance/fcp/test_fcp_core.lua:167-230`

**Interfaces:**
- Consumes: `GPS` `MSG_GPS_RESPONSE` on `Base+5`, VAS `MSG_FLIGHT_TELEMETRY` (`dynamics.altitudeY`) on `Base+2`
- Produces:
  - `network_manager.encode_envelope` emitting `time` (zero `timestamp` header field)
  - `network_manager.verify_packet` accepting `MSG_GPS_RESPONSE` only when `type(pkt.payload) == "table" and pkt.payload.targetClient == ctx.domainId`
  - `nav_engine.filter_gps` enforcing bounded monotonic `clientSeq` and elapsed `(now_ms - lastGpsFixMs) / 1000.0` kinematic gating
  - `nav_engine.integrate_dr` syncing `state.pos.y` directly to `telemetry.dynamics.altitudeY` (fallback `vy * dt` when omitted)

- [ ] **Step 1: Write failing FCP unit tests**

Extend `tests/2_guidance/fcp/test_fcp_core.lua` inside `"network_manager and fcp_runtime 40-channel binding and Base+5 GPS link"`:
```lua
    it("encodes envelope with time field and filters foreign MSG_GPS_RESPONSE targetClient", function()
        local net = network_manager.init({ system = { domainId = "AIRCRAFT_01" } })
        local env = network_manager.encode_envelope(net, "MSG_GPS_REQUEST", {
            replyChannel = 10005, altitudeY = 80, clientType = "AIRCRAFT", clientSeq = 1
        })
        assert_not_nil(env.time)
        assert_nil(env.timestamp, "FCP envelope must emit time instead of legacy timestamp")

        local foreignResp = {
            ver = "1.9.5", domainId = "GPS_BASE_NET", seq = 2, type = "MSG_GPS_RESPONSE", time = 1100,
            payload = {
                targetClient = "AIRCRAFT_02", clientSeq = 1, status = "FIX_OK",
                position = { x = 999, z = 999 }, accuracy = 0.1, hdop = 1.0, nodeCount = 4
            }
        }
        assert_false(network_manager.ingest_modem_event(net, "back", 10005, 60002, foreignResp, 10, 1100))
        assert_nil(net.queues.gps)
    end)

    it("enforces monotonic bounded clientSeq, elapsed kinematic delta_t, and altitude sync in nav_engine", function()
        local nav_engine = require("nav_engine")
        local st = nav_engine.init({
            navigation = { drComplementaryAlpha = 0.5, kinematicGateLimitM = 8.0, gpsTimeoutMs = 5000 }
        })
        nav_engine.integrate_dr(st, {
            dynamics = { altitudeY = 142.5, velocity = { vx = 50.0, vy = 0.0, vz = 0.0 } }
        }, 0.05, 1000)
        assert_near(st.pos.y, 142.5, 1e-4, "integrate_dr must synchronize pos.y to dynamics.altitudeY")

        local ok1, reqSeq1 = nav_engine.should_query_gps(st, 1000)
        assert_true(ok1)
        assert_eq(reqSeq1, 1)
        assert_true(nav_engine.filter_gps(st, {
            clientSeq = 1, status = "FIX_OK", position = { x = 0.0, z = 0.0 }, accuracy = 0.5, hdop = 1.0
        }, 0.05, 1000))
        assert_eq(st.lastGpsFixSeq, 1)

        -- Duplicate / replayed clientSeq = 1 and future clientSeq = 99 must be rejected
        assert_false(nav_engine.filter_gps(st, {
            clientSeq = 1, status = "FIX_OK", position = { x = 1.0, z = 0.0 }, accuracy = 0.5, hdop = 1.0
        }, 0.05, 1100))
        assert_false(nav_engine.filter_gps(st, {
            clientSeq = 99, status = "FIX_OK", position = { x = 1.0, z = 0.0 }, accuracy = 0.5, hdop = 1.0
        }, 0.05, 1100))

        -- Craft moves at 50 m/s for 500ms -> 25m actual travel; elapsed delta_t=0.5 allows max_allowed ~39m
        local ok2, reqSeq2 = nav_engine.should_query_gps(st, 1500)
        assert_true(ok2)
        assert_eq(reqSeq2, 2)
        assert_true(nav_engine.filter_gps(st, {
            clientSeq = 2, status = "FIX_OK", position = { x = 25.0, z = 0.0 }, accuracy = 0.5, hdop = 1.0
        }, 0.05, 1500))
    end)
```

- [ ] **Step 2: Run FCP unit tests to verify FAIL**

Run:
```powershell
python tools/run_unit_tests.py --target 2_guidance/fcp --clean-orphans
```
Expected: FAIL — `env.time == nil`, foreign `MSG_GPS_RESPONSE` accepted, `pos.y` stays `64.0`, replay/future `clientSeq` accepted, and `25m` move fails kinematic gate with hardcoded `dt = 0.05` (`max_allowed = 8.0`).

- [ ] **Step 3: Implement `network_manager.lua` and `nav_engine.lua` updates**

1. **`src/2_guidance/fcp/modules/network_manager.lua`**:
   - In `encode_envelope` (`line 108`): replace `timestamp = now_epoch` with `time = now_epoch`.
   - In `verify_packet` (`lines 129-133`): add check before `return true`:
     ```lua
     if pkt.type == "MSG_GPS_RESPONSE" then
         if type(pkt.payload) ~= "table" or pkt.payload.targetClient ~= ctx.domainId then
             return false
         end
     end
     ```

2. **`src/2_guidance/fcp/modules/nav_engine.lua`**:
   - In `nav_engine.init` (`line 26`): add `lastGpsFixSeq = 0`.
   - In `nav_engine.integrate_dr` (`lines 49-53`):
     ```lua
     state.pos.x = state.pos.x + vx * dt
     local altY = dyn.altitudeY
     if altY == nil then altY = telemetry.altitudeY end
     if type(altY) == "number" then
         state.pos.y = altY
     else
         state.pos.y = state.pos.y + vy * dt
     end
     state.pos.z = state.pos.z + vz * dt
     ```
   - In `nav_engine.filter_gps` (`lines 85-119`):
     - Right after `status` guard, validate optional `clientSeq`:
       ```lua
       local cSeq = nil
       if fix_payload.clientSeq ~= nil then
           cSeq = tonumber(fix_payload.clientSeq)
           if not cSeq or cSeq <= (state.lastGpsFixSeq or 0) or (state.gpsReqSeq > 0 and cSeq > state.gpsReqSeq) then
               return false
           end
       end
       ```
     - Replace `local delta_t = dt or 0.05` with elapsed time window:
       ```lua
       local fallback_dt = dt or 0.05
       local delta_t = fallback_dt
       if (state.lastGpsFixMs or 0) > 0 and now_ms and now_ms > state.lastGpsFixMs then
           local elapsed = (now_ms - state.lastGpsFixMs) / 1000.0
           local maxSpanSec = (state.gpsTimeoutMs or 5000) / 1000.0
           delta_t = math.max(fallback_dt, math.min(elapsed, maxSpanSec))
       end
       ```
     - Record `if cSeq then state.lastGpsFixSeq = cSeq end` ONLY when accepting a fix (`if dist > max_allowed` -> 3-streak snap OR `apply_fix_fusion`).

- [ ] **Step 4: Run FCP unit tests to verify PASS**

Run:
```powershell
python tools/run_unit_tests.py --target 2_guidance/fcp --clean-orphans
```
Expected: ALL `2_guidance/fcp` tests PASS.

- [ ] **Step 5: Commit Task 5**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/2_guidance/fcp/modules/network_manager.lua src/2_guidance/fcp/modules/nav_engine.lua tests/2_guidance/fcp/test_fcp_core.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "fix(fcp): standardize time envelope, filter targetClient/clientSeq, sync altitudeY, and fix kinematic delta_t (TASK-122-5)"
```

---

### Task 6: Real Multi-Node E2E Verification, Spec Promotion & Full Regression (`TASK-122-6`)

**Files:**
- Modify: `tests/e2e/test_e2e_gps_triangulation.lua:1-159`
- Modify: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md:8-10`
- Modify: `TASK.md`, `GEMINI.md`, `.agent/memory/workspace-root.md`

**Interfaces:**
- Consumes: `src/0_infra/gps/{server,node,hal/gps_client,modules/session_scheduler,modules/protocol}`, `src/2_guidance/fcp/{fcp_runtime,modules/network_manager,modules/nav_engine}`, `src/0_infra/landing_pad/modules/{gps_client,offset_transform}`
- Produces: Real closed-loop E2E Scenario 3 coverage (`EARLY_SOLVED`, `FAIL_GEOMETRY` + 250ms retry, `CH 60002` status, `FACILITY` client on `50206`), `GPS_PROGRAM_SPECIFICATION_AND_ICD.md` promoted to `Implemented`, and synchronized root context documentation.

- [ ] **Step 1: Upgrade `tests/e2e/test_e2e_gps_triangulation.lua` to real closed-loop multi-node simulation**

Replace `tests/e2e/test_e2e_gps_triangulation.lua` with complete closed-loop multi-node wiring over `virtual_bus`:
```lua
-- tests/e2e/test_e2e_gps_triangulation.lua
-- Scenario 3: Closed-Loop Multi-Node GPS Triangulation, Fail-Geometry Retry, Status Query & Facility Client
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

describe("Scenario 3: GPS Closed-Loop Swarm Triangulation, Service Status & Multi-Client Integration", function()
    it("exercises FCP 4-node EARLY_SOLVED, collinear FAIL_GEOMETRY + 250ms retry, CH 60002 status, and Landing Pad FACILITY", function()
        local bus = virtual_bus.create_bus({ clock = 1.0 })
        sdk.patch(os, "epoch", function()
            return math.floor(bus.time * 1000 + 0.5)
        end)

        local handlerErrors = {}
        local function safeCall(tag, fn)
            local ok, err = pcall(fn)
            if not ok then
                table.insert(handlerErrors, tag .. ": " .. tostring(err))
            end
        end

        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
        local gps_srv = node_sandbox.create_node(bus, "GPS_SRV", "src/0_infra/gps")
        local gps_cli = node_sandbox.create_node(bus, "GPS_CLI", "src/0_infra/gps")
        local pad_node = node_sandbox.create_node(bus, "PAD_01", "src/0_infra/landing_pad")

        local anchorDefs = {
            { sb = node_sandbox.create_node(bus, "GPS_N1", "src/0_infra/gps"), cfg = { nodeId = "NODE_01", computerId = 1, position = { x = 0.0, y = 80.0, z = 0.0 } } },
            { sb = node_sandbox.create_node(bus, "GPS_N2", "src/0_infra/gps"), cfg = { nodeId = "NODE_02", computerId = 2, position = { x = 250.0, y = 80.0, z = 0.0 } } },
            { sb = node_sandbox.create_node(bus, "GPS_N3", "src/0_infra/gps"), cfg = { nodeId = "NODE_03", computerId = 3, position = { x = 500.0, y = 80.0, z = 0.0 } } },
            { sb = node_sandbox.create_node(bus, "GPS_N4", "src/0_infra/gps"), cfg = { nodeId = "NODE_04", computerId = 4, position = { x = 250.0, y = 80.0, z = 500.0 } } },
        }

        local truthByClient = {
            AIRCRAFT_01 = { x = 200.0, y = 100.0, z = 300.0 },
            AIRCRAFT_02 = { x = 200.0, y = 100.0, z = 300.0 },
            PAD_BRAVO_01 = { x = 340.0, y = 64.0, z = 420.0 },
        }

        local registry = { nodes = {} }
        local nodeEnabled = { true, true, true, true }
        local nodeMods, nodeStates = {}, {}
        for i, n in ipairs(anchorDefs) do
            registry.nodes[n.cfg.nodeId] = {
                nodeId = n.cfg.nodeId, computerId = n.cfg.computerId,
                position = n.cfg.position, status = "ONLINE"
            }
            nodeMods[i] = n.sb:require("node")
            nodeStates[i] = { reportsSent = 0, reportSeq = 0 }
            n.sb.modem:open(60001)
            n.sb.modem.on_message = function(ev)
                if not nodeEnabled[i] then return end
                local targetId = type(ev.payload) == "table" and ev.payload.domainId or nil
                local truth = truthByClient[targetId]
                if not truth then return end
                local dx = truth.x - n.cfg.position.x
                local dy = truth.y - n.cfg.position.y
                local dz = truth.z - n.cfg.position.z
                local dist3d = math.sqrt(dx * dx + dy * dy + dz * dz)
                safeCall(n.cfg.nodeId, function()
                    nodeMods[i].handlePingMessage(n.sb.modem, n.cfg, ev.channel, ev.payload, dist3d, nodeStates[i])
                end)
            end
        end

        local srv_mod = gps_srv:require("server")
        local sched_mod = gps_srv:require("session_scheduler")
        local sched = sched_mod.new({ windowMs = 50, tombstoneTtlMs = 1000 })
        local srv_state = {
            ticks = 400, solvedCount = 0, totalSolves = 0, seq = 1,
            activeNodes = 4, clientCount = 0,
            nodes = {
                { id = "NODE_01", x = 0, y = 80, z = 0, status = "ONLINE", ping = 0 },
                { id = "NODE_02", x = 250, y = 80, z = 0, status = "ONLINE", ping = 0 },
                { id = "NODE_03", x = 500, y = 80, z = 0, status = "ONLINE", ping = 0 },
                { id = "NODE_04", x = 250, y = 80, z = 500, status = "ONLINE", ping = 0 },
            },
            clients = {}
        }
        gps_srv.modem:open(60002)
        gps_srv.modem:open(60003)
        gps_srv.modem:open(60004)
        gps_srv.modem.on_message = function(ev)
            safeCall("GPS_SRV", function()
                srv_mod.handleModemMsg(sched, registry, gps_srv.modem, srv_state, {
                    "modem_message", ev.side, ev.channel, ev.replyChannel, ev.payload, ev.distance
                })
            end)
        end

        -- 1. FCP 4-node EARLY_SOLVED + foreign spoof filter + altitudeY sync
        local fcp_rt = fcp:require("fcp_runtime")
        local fcp_net = fcp:require("network_manager")
        local fcp_ctx = fcp_rt.create_context({
            system = { domainId = "AIRCRAFT_01" },
            channels = { baseChannel = 10000, bandwidth = 40 },
            navigation = { drComplementaryAlpha = 0.5, gpsTimeoutMs = 5000 }
        }, function() return fcp.modem end)
        fcp_ctx.nav.pos = { x = 195.0, y = 64.0, z = 295.0 }
        fcp.modem:open(10005)
        fcp.modem.on_message = function(ev)
            safeCall("FCP", function()
                fcp_net.ingest_modem_event(fcp_ctx.net, ev.side, ev.channel, ev.replyChannel, ev.payload, ev.distance, math.floor(bus.time * 1000 + 0.5))
            end)
        end

        fcp_net.ingest_modem_event(fcp_ctx.net, "top", 10002, 10002, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1, type = "MSG_FLIGHT_TELEMETRY", time = 1000,
            payload = { dynamics = { altitudeY = 100.0, velocity = { vx = 0, vy = 0, vz = 0 } }, controlState = "IDLE_ARMED" }
        }, 0, 1000)
        fcp_rt.step_tick(fcp_ctx, 0.05, 1000)
        assert_eq(fcp_ctx.nav.pos.y, 100.0)

        local reqPkts = bus:find_packets({ type = "MSG_GPS_REQUEST", channel = 60001 })
        assert_eq(#reqPkts, 1)
        assert_not_nil(reqPkts[1].payload.time)
        assert_nil(reqPkts[1].payload.timestamp)

        -- Inject foreign AIRCRAFT_02 spoof onto 10005 before delivering real GPS response
        gps_srv.modem:transmit(10005, 60002, {
            ver = "1.9.5", domainId = "GPS_BASE_NET", seq = 999, type = "MSG_GPS_RESPONSE", time = 1005,
            payload = { targetClient = "AIRCRAFT_02", clientSeq = 1, status = "FIX_OK", position = { x = -9999, z = -9999 }, nodeCount = 4, selectedNodes = {} }
        })
        bus:step(0.01) -- pings -> node reports
        bus:step(0.01) -- reports -> server EARLY_SOLVED response
        bus:step(0.03) -- response delivered to FCP

        fcp_rt.step_tick(fcp_ctx, 0.05, 1050)
        assert_near(fcp_ctx.nav.pos.x, 197.5, 0.5)
        assert_near(fcp_ctx.nav.pos.z, 297.5, 0.5)
        assert_eq(fcp_ctx.nav.pos.y, 100.0)
        assert_eq(fcp_ctx.nav.lastGpsFixSeq, 1)

        -- 2. Collinear 3-node FAIL_GEOMETRY + 250ms retry after 150ms tombstone
        nodeEnabled[4] = false
        bus.time = 2.000
        local cli_hal = gps_cli:require("gps_client")
        cli_hal.init("AIRCRAFT_02", "AIRCRAFT", 10045)
        cli_hal.setManaged(true)
        gps_cli.modem:open(10045)
        gps_cli.modem:open(60002)
        gps_cli.modem.on_message = function(ev)
            safeCall("GPS_CLI", function()
                cli_hal.handleMessage(ev.side, ev.channel, ev.replyChannel, ev.payload, ev.distance)
            end)
        end

        local retrySeq = cli_hal.request(100.0)
        bus:step(0.01) -- ping -> 3 collinear nodes
        bus:step(0.01) -- 3 reports buffered
        bus.time = 2.060
        srv_mod.flushTimerExpired(sched, registry, gps_srv.modem, srv_state)
        bus:step(0.01)
        local geomResp = cli_hal.poll(retrySeq)
        assert_not_nil(geomResp, "3 collinear nodes on expiration must return FAIL_GEOMETRY instead of hanging")
        assert_eq(geomResp.status, "FAIL_GEOMETRY")

        -- Re-enable 4th non-collinear node and retry at 250ms (> 150ms tombstone) with same clientSeq
        nodeEnabled[4] = true
        bus.time = 2.250
        gps_cli.modem:transmit(60001, 10045, {
            ver = "1.9.5", domainId = "AIRCRAFT_02", seq = retrySeq, type = "MSG_GPS_REQUEST", time = 2250,
            payload = { replyChannel = 10045, altitudeY = 100.0, clientType = "AIRCRAFT", clientSeq = retrySeq }
        })
        bus:step(0.01)
        bus:step(0.01)
        bus:step(0.01)
        local retryFix = cli_hal.poll(retrySeq)
        assert_not_nil(retryFix)
        assert_eq(retryFix.status, "FIX_OK")
        assert_near(retryFix.position.x, 200.0, 0.5)
        assert_near(retryFix.position.z, 300.0, 0.5)

        -- 3. CH 60002 server status query
        cli_hal.requestStatus("SUMMARY", 60002)
        bus:step(0.01)
        bus:step(0.01)
        local srvStatus = cli_hal.pollStatus()
        assert_not_nil(srvStatus)
        assert_eq(srvStatus.activeNodes, 4)
        assert_eq(srvStatus.totalSolved, 2)
        assert_eq(srvStatus.version, "1.9.5")

        -- 4. Landing Pad FACILITY (50206) closed loop & replay guard
        local pad_cfg_store = pad_node:require("config_store")
        local pad_offset = pad_node:require("offset_transform")
        local pad_gps_mod = pad_node:require("gps_client")
        local padCfg = pad_cfg_store.normalize_config({
            facilityId = "PAD_BRAVO_01", sectorId = 1, padIndex = 1, mobility = "DYNAMIC",
            gacChannel = 50201, sectorFacilityChannel = 50202, sectorGpsReplyChannel = 50206, tacticalChannel = 50211
        })
        local padGps = pad_gps_mod.create(padCfg, pad_offset)
        local lastPadEnvelope = nil
        local padReplayOk = nil
        pad_node.modem:open(50206)
        pad_node.modem.on_message = function(ev)
            lastPadEnvelope = ev.payload
            safeCall("PAD", function()
                local pad_gps_ok = padGps:handle_response_packet(ev.payload, bus.time)
                assert_true(pad_gps_ok)
            end)
        end
        assert_true(padGps:should_query_gps("RESERVED", 4))
        local padReq = padGps:build_request_packet(64.0, 2300)
        assert_eq(padReq.payload.clientType, "FACILITY")
        assert_eq(padReq.payload.replyChannel, 50206)
        pad_node.modem:transmit(60001, padReq.payload.replyChannel, padReq)
        bus:step(0.01)
        bus:step(0.01)
        bus:step(0.01)

        assert_true(padGps:has_valid_fix())
        assert_near(padGps:get_current_comp_pos().x, 340.0, 0.5)
        assert_near(padGps:get_current_comp_pos().z, 420.0, 0.5)
        assert_not_nil(lastPadEnvelope)
        padReplayOk = padGps:handle_response_packet(lastPadEnvelope, bus.time)
        assert_false(padReplayOk, "Landing Pad client must reject replayed clientSeq")

        assert_eq(#handlerErrors, 0, table.concat(handlerErrors, "; "))
    end)
end)
```

- [ ] **Step 2: Run E2E test and verify PASS (or iterate until green)**

Run:
```powershell
python tools/run_e2e_tests.py --scenario gps_triangulation --clean-orphans
```
Expected: `Scenario 3` PASS (4/4 E2E assertions inside Scenario 3).

- [ ] **Step 3: Promote `GPS_PROGRAM_SPECIFICATION_AND_ICD.md` to `Implemented`**

In `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`:
- Update `문서 상태 (Status)` (`line 8`) from `` `Approved` `` to `` `Implemented` `` and verify `최종 수정일 (Date)` is `` `2026-11-11` ``.

- [ ] **Step 4: Run complete multi-layer verification suite**

Run all repository gates verbatim and record exact numerical counts:
```powershell
python tools/run_unit_tests.py --require-tests --clean-orphans
python tools/run_e2e_tests.py --clean-orphans
python tools/run_mutation_tests.py
python -m unittest discover -s tests/harness -p "test_*.py"
python tools/validate_lua_syntax.py
python tools/verify_manifest_sync.py
python tools/verify_all_specs.py --check-readmes
python tools/verify_spec_status.py
```
Expected:
- `run_unit_tests.py`: 12/12 targets PASS (record exact total assertions/cases)
- `run_e2e_tests.py`: 7/7 scenarios 8/8 suites PASS
- `run_mutation_tests.py`: 25/25 KILLED (100.0%)
- `tests/harness`: 82/82 PASS
- `validate_lua_syntax.py`: all Lua files PASS (`0` syntax errors)
- `verify_manifest_sync.py`: `0 Errors, 0 Warnings`
- `verify_all_specs.py --check-readmes`: `SCAN RESULT: ALL 15 SPECS 100% CLEAN (0 Errors, 0 Warnings)`
- `verify_spec_status.py`: `[PASS] All 15 specs have valid statuses (9 Implemented, 6 Approved)!`

- [ ] **Step 5: Synchronize root context docs (`TASK.md`, `GEMINI.md`, `.agent/memory/workspace-root.md`) and commit**

1. Update `TASK.md`: mark `TASK-122` and `TASK-122-1..6` `[x]`, move `TASK-122` to top of `## ✅ 3. 완료된 작업 이력` (pruning oldest item if archive length exceeds `10` per rule R7), citing exact commit hashes and `GPS_PROGRAM_SPECIFICATION_AND_ICD.md (v2.3.0 Implemented)`.
2. Append `## 2026-11-11 — TASK-122 GPS ↔ 클라이언트 프로토콜 정합화 및 런타임 누락 보완 완료` entry in `.agent/memory/workspace-root.md` (satisfies R8).
3. Update `GEMINI.md` snapshot (`<= 80` lines strictly; record updated unit test count and `TASK-122` latest completion).
4. Run final context & status check:
   ```powershell
   python tools/verify_context_docs.py
   ```
   Expected: `[PASS] context docs: 0 findings`.
5. Commit:
   ```powershell
   & "C:\Program Files\Git\cmd\git.exe" add tests/e2e/test_e2e_gps_triangulation.lua docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md TASK.md GEMINI.md .agent/memory/workspace-root.md
   & "C:\Program Files\Git\cmd\git.exe" commit -m "test(e2e): upgrade GPS triangulation to closed-loop multi-node suite and promote spec (TASK-122-6)"
   ```
