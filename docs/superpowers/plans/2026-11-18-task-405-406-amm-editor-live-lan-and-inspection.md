# AMM Mission Editor LAN Live Bridge & Tactical Inspection Mode (`TASK-405` & `TASK-406`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Isolated HTML Skills:** When implementing or reviewing `tools/amm_mission_editor.html` and `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md`, apply `.agent/skills/frontend-design/SKILL.md` and `.agent/skills/web-design-guidelines/SKILL.md`.

**Goal:** Extend `tools/amm_mission_editor.html`, `tools/gcs_live_bridge.py`, `src/0_infra/gac/`, and `src/0_infra/gcs/` to support RFC 1918 LAN private IP / `.local` WebSocket Live Bridge connections with persistent URL input and `--lan` bridge bind option (`TASK-405`), wide-area zoom (`1%`..`400%`) with 10-step dynamic grid scaling, explicit `GAC` `position = { x, y, z }` broadcasting (with facility centroid fallback), live auto-registration and `60s` (`60000ms`) TTL `OFFLINE`/`STALE` semi-transparent marking + manual `Purge Offline` cleanup for `GPS`/`GAC`/subordinate facilities (`Landing Pad`, `Runway`, `Hangar`, `Docking Arm`), canvas/list target filtering, and a read-only `Inspection` mode allowing camera `Follow` and `Push to Aircraft` (`TASK-406`).

**Architecture:** We execute `TASK-405` and `TASK-406` as a single sequential pipeline so `AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.5.0` → `v0.6.0`), `GCS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v1.3.0` → `v1.4.0`), and `GAC_PROGRAM_SPECIFICATION_AND_ICD.md` (`v1.7.0 Approved`, explicit `GAC` `position`) transition cleanly (`Approved` → `Implemented` in Task 6). On the infrastructure side, `GAC` emits explicit `cfg.position` (or facility centroid fallback) in `MSG_FACILITY_BEACON.payload.position`, while `GCS` opens `CH 60003` (`MSG_GPS_NODE_HEARTBEAT`) alongside `CH 50003` (`MSG_FACILITY_BEACON`), emits `GPS_NODES_SYNC` and `WORLD_PRESET_SYNC` (with `gacNode` using explicit `position` or facility centroid), and marks silent live nodes `OFFLINE`/`STALE` at `60000ms` TTL across `GCS`, `tools/gcs_live_bridge.py` (`--lan` opt-in `0.0.0.0` bind), `LiveBridge`, and `WorldStore` without auto-deleting them until manual `Purge Offline`. On the WebUI side, `CanvasRenderer`, `Store`, and `InspectorUI` gain 10-tier grid scaling down to `zoom = 0.01`, craft/facility type filters, and a top-level `MISSION_EDIT` ↔ `INSPECTION` mode switch supporting camera `Follow` and `Push to Aircraft`.

**Tech Stack:** Single-file HTML5/CSS3/Vanilla ES2020 JS (`tools/amm_mission_editor.html`), Python 3.10+ `asyncio` RFC 6455 WebSocket server (`tools/gcs_live_bridge.py`), CC:Tweaked Lua 5.2 (`src/0_infra/gac/`, `src/0_infra/gcs/`), Python `unittest` + Node.js DOM/Canvas VM harness (`tests/3_planning/amm/test_amm_mission_editor.py`, `tests/harness/test_gcs_live_bridge.py`), CraftOS-PC headless Lua unit runner (`tools/run_unit_tests.py`).

**Spec:**
- `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.5.0 Implemented` → `v0.6.0 Approved` → `Implemented`)
- `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v1.3.0 Implemented` → `v1.4.0 Approved` → `Implemented`)
- `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md` (`v1.7.0 Approved` → `Implemented`)

## Global Constraints

- **Single-File Offline Integrity (`file://`)**: `tools/amm_mission_editor.html` remains a single self-contained `.html` file with zero external `<script src>`, `<link href>`, `fetch()`, `XMLHttpRequest`, `http://`, `https://`, or `wss://` calls.
- **Strict LAN / Loopback WebSocket Allowlist (`TASK-405`)**: `LiveBridge.isAllowedLocalUrl(url)` permits only `ws://` URLs targeting `localhost`, `127.0.0.0/8`, RFC 1918 private IPv4 (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` with each octet `0..255`), or mDNS `<host>.local` (`^[a-z0-9-]+(\.[a-z0-9-]+)*\.local$`), with optional port `1..65535`. Public IPv4 (`8.8.8.8`, `172.15.x.x`, `172.32.x.x`, `192.169.x.x`), `wss://`, and external domains are rejected with `NON_LOCAL_BRIDGE_URL`.
- **DOM XSS Safety & Dialog Ban**: Render all untrusted strings from JSON or WebSocket frames (`missionId`, `facilityId`, `nodeId`, `sectorName`, `domainId`, `notes`, `status`) exclusively via `document.createElement` + `textContent` / `.value`; never use `innerHTML`, `insertAdjacentHTML`, `window.alert`, `window.confirm`, or `window.prompt`.
- **Backward Compatibility with Existing Constants & Tests**: Keep `SchemaConstants.FACILITY_TYPE_FILTERS = ["ANY", "LANDING_PAD", "RUNWAY"]` unchanged for `ACT_TKL_LAND_NEAREST` validation; define `SchemaConstants.FACILITY_TYPES = ["LANDING_PAD", "RUNWAY", "HANGAR", "DOCKING_ARM", "GPS", "GAC", "WAYPOINT"]` and `SchemaConstants.MAP_FACILITY_FILTER_TYPES = ["ALL", "GAC", "GPS", "LANDING_PAD", "RUNWAY", "HANGAR", "DOCKING_ARM", "WAYPOINT"]` separately.
- **Null-Safe DOM Access**: Every new DOM element lookup in `InspectorUI` and `AppBootstrap` must guard with `if (el)` so partial DOM shims in `TestOperabilityRegressions` continue to pass without modification.
- **No-Overclaim & Prohibited Mods**: Zero banned overclaim terms (`AGENTS.md`) and zero Valkyrien Skies / `kontraption:` / deprecated action tokens (`.agent/rules/domain-aeronautics.md`).

## Review Focus

1. **RFC 1918 Boundary & Octet Overflow Bypass (`172.15.0.1`, `172.32.0.1`, `192.168.1.999`, `evil.local.com`)**:
   - A naive regex like `/^ws:\/\/(10\.|172\.|192\.168\.)/` would accept public `172.32.0.1` or invalid octets `192.168.1.999`. `isAllowedLocalUrl` must parse and validate each IPv4 octet (`0..255`), enforce `16 <= secondOctet <= 31` for `172.x`, validate port `1..65535`, and require `.local` to be the final TLD label. (Pinned in Task 2 tests.)
2. **Grid Line Explosion at Wide-Area Zoom (`zoom = 0.01`)**:
   - At `zoom = 0.01` on a `900px` canvas (`90,000m` world span), a fixed `stepWorld = 200` draws 450 grid lines and overlapping ruler numbers per frame. `CanvasRenderer.computeGridStep(zoom)` must select from `[10, 25, 50, 100, 200, 500, 1000, 2000, 5000, 10000]` so screen spacing stays `>= 55px` (`stepWorld = 10000` at `zoom = 0.01`). (Pinned in Task 3 tests.)
3. **Manual vs Live Auto-Registered Facility TTL Stale/Purge (`liveAuto` Isolation)**:
   - When `LiveBridge.markExpiredNodes(nowMs)` runs after `60000ms` of silence, it must **not** auto-delete expired live-auto nodes (`GPS`, `GAC`, `LANDING_PAD`, `RUNWAY`, `HANGAR`, `DOCKING_ARM`) or live crafts; it marks them `isStale: true, liveStatus: "OFFLINE"` for semi-transparent rendering (`globalAlpha = 0.38`) and `[OFFLINE]` badges. Only explicit `LiveBridge.purgeOfflineNodes()` (from the `Purge Offline` button) removes `OFFLINE`/`STALE` live-auto nodes (`liveAuto: true`) and stale crafts, while **never** deleting user-authored manual facilities (`!fac.liveAuto`) in `WorldStore`. Also, `WORLD_PRESET_SYNC` without `gacNode` must only upsert `msg.facilities` so existing `TestTask404LiveBridgeAndPush` (`facCount == 1`) remains intact. (Pinned in Task 4 tests.)
4. **Filter Desynchronization Between Canvas Rendering and Hit-Testing**:
   - If a craft airframe or facility type (`GPS`, `GAC`, `HANGAR`, etc.) is hidden via `ui.filters`, clicking its canvas coordinates must not select or assign the hidden pin/craft. Both `CanvasRenderer.render()` and `hitTestFacilityPin` / `hitTestInspectionTarget` must share `CanvasRenderer.isFacilityVisible(fac, ui)` and `CanvasRenderer.isCraftVisible(craft, ui)`. (Pinned in Task 5 tests.)
5. **Accidental Mission Mutation vs Allowed Follow/Push in `INSPECTION` Mode**:
   - While `ui.editorMode === "INSPECTION"`, dragging on the canvas or calling `Store.addCheckpoint` / `deleteCheckpoint` / `moveCheckpoint` / `duplicateCheckpoint` / `expandSelectedMacro` / `mutateMission` / `setMission` / `loadPreset` / `PICK_FACILITY` must not mutate `state.mission.checkpoints`; canvas pointer interaction must only pan, zoom, or select an entity (`ui.inspectedEntity`) to populate the read-only Inspection HUD, while camera `Follow` (`ui.followCraftId`) and `Push to Aircraft` (`LiveBridge.pushMission`) remain enabled. (Pinned in Task 5 tests.)

---

## File Structure

- **Modify:** `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` — Revise to `v0.6.0 Approved` (Task 1) and promote to `Implemented` (Task 6).
- **Modify:** `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` — Revise to `v1.4.0 Approved` (Task 1) and promote to `Implemented` (Task 6).
- **Modify:** `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md` — Already revised to `v1.7.0 Approved` (explicit `position`); promote to `Implemented` in Task 6.
- **Modify:** `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`, `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`, `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` — Sync cross-reference version badges (`Editor v0.6.0`, `GCS v1.4.0`, `GAC v1.7.0`).
- **Modify:** `tools/verify_spec_status.py`, `GEMINI.md`, `TASK.md` — Sync `Approved`/`Implemented` spec status distribution during Task 1 and Task 6.
- **Modify:** `src/0_infra/gac/modules/config_loader.lua`, `src/0_infra/gac/modules/beacon_broadcaster.lua`, `src/0_development/installer/modules/manifest.lua` — Support explicit `position = { x, y, z }` in GAC sector config and emit `payload.position` (explicit `cfg.position` first, centroid fallback) in `MSG_FACILITY_BEACON`.
- **Modify:** `src/0_infra/gcs/config/gcs_config.json`, `src/0_infra/gcs/modules/network_manager.lua`, `src/0_infra/gcs/modules/live_bridge_client.lua`, `src/0_infra/gcs/main.lua` — Add `gpsHeartbeatChannel: 60003` (`MSG_GPS_NODE_HEARTBEAT`), `GPS_NODES_SYNC` relay, `gacNode` metadata (`beacon_payload.position` or centroid fallback) in `WORLD_PRESET_SYNC`, and `60000ms` TTL `OFFLINE`/`STALE` + manual purge.
- **Modify:** `tools/gcs_live_bridge.py` — Add `--lan` flag (`0.0.0.0` bind + LAN IP guidance), cache and relay `GPS_NODES_SYNC`.
- **Modify:** `tools/amm_mission_editor.html` — Implement `TASK-405` (`isAllowedLocalUrl` RFC 1918/mDNS, `#liveBridgeUrlInput`, `localStorage` URL persistence) and `TASK-406` (`0.01..4.0` zoom, 10-step `computeGridStep`, `GPS_NODES_SYNC` + `gacNode` + `HANGAR` auto-registration, `60000ms` TTL `OFFLINE`/`STALE` + `Purge Offline`, target filter bar, and `MISSION_EDIT` ↔ `INSPECTION` mode with `Follow` & `Push to Aircraft`).
- **Modify:** `tests/3_planning/amm/test_amm_mission_editor.py`, `tests/harness/test_gcs_live_bridge.py`, `tests/0_infra/gcs/test_live_bridge_client.lua`, `tests/0_infra/gcs/test_main_loop.lua`, `tests/0_infra/gac/test_config_loader.lua`, `tests/0_infra/gac/test_beacon_broadcaster.lua` — Add unit and integration tests for `TASK-405` and `TASK-406`.
- **Modify:** `.agent/memory/workspace-root.md` — Append `TASK-405` and `TASK-406` completion log in Task 6.

---

### Task 1: Spec-First Revision (`AMM_MISSION_EDITOR_SPECIFICATION.md` `v0.6.0` & `GCS` `v1.4.0` `Approved`)

**Files:**
- Modify: `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md`
- Modify: `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md`
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`
- Modify: `tools/verify_spec_status.py`
- Modify: `GEMINI.md`
- Modify: `TASK.md`

**Interfaces:**
- Produces: `Approved` specifications (`AMM_MISSION_EDITOR_SPECIFICATION.md v0.6.0`, `GCS_PROGRAM_SPECIFICATION_AND_ICD.md v1.4.0`, alongside pre-revised `GAC_PROGRAM_SPECIFICATION_AND_ICD.md v1.7.0 Approved`) defining exact contracts for Tasks 2–5.

- [x] **Step 1: Revise `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` to `v0.6.0 Approved`**

Update metadata table (`Status: Approved`, `Version: v0.6.0`, `Date: 2026-11-18`), add `v0.6.0` row to `Revision History`, and update:
- §1.2 & §10.1: `LiveBridge.isAllowedLocalUrl(url)` RFC 1918 (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), `127.0.0.0/8`, `localhost`, and `*.local` `ws://` policy; `#liveBridgeUrlInput` persisted to `localStorage` (`uafs_amm_live_bridge_url_v1`).
- §3.3 & §4.1: Top bar `[Mission Edit | Inspection]` mode toggle (`ui.editorMode`), canvas filter bar (`ui.filters`), `Purge Offline` button (`#btnPurgeOffline`), and Inspection Mode read-only mission lock + entity telemetry HUD (`CRAFT` / `FACILITY` / `CHECKPOINT`) with camera `Follow` (`ui.followCraftId`) and `Push to Aircraft` support.
- §4.4 & §10.1: 7 facility types (`LANDING_PAD`, `RUNWAY`, `HANGAR`, `DOCKING_ARM`, `GPS`, `GAC`, `WAYPOINT`), `WORLD_PRESET_SYNC` (`gacNode` explicit `position` or facility centroid + subordinate facilities) & `GPS_NODES_SYNC` auto-registration (`liveAuto: true`, `lastSeenMs`), and `60000ms` (`1분 TTL`) `OFFLINE`/`STALE` semi-transparent transition (`markExpiredNodes(nowMs)`) + manual `purgeOfflineNodes()`.
- §8.1, §8.2 & §8.3: Zoom range `0.01 .. 4.0 px/m` (`1% .. 400%`), `fitView` lower bound `0.01`, and 10-step adaptive grid ladder `[10, 25, 50, 100, 200, 500, 1000, 2000, 5000, 10000]`.

- [x] **Step 2: Revise `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` to `v1.4.0 Approved` and sync reference badges**

Update metadata table (`Status: Approved`, `Version: v1.4.0`, `Date: 2026-11-18`), add `v1.4.0` row to `Revision History`, and document:
- `channels.gpsHeartbeatChannel = 60003` (`CH_GPS_NODE_IN`, `MSG_GPS_NODE_HEARTBEAT` passive listener).
- `WORLD_PRESET_SYNC` `gacNode` (explicit `position` or centroid of `facilities[]`) and `GPS_NODES_SYNC` WebSocket relay message (`{ type = "GPS_NODES_SYNC", nodes = [...] }`).
- `60000ms` (`60s`) `OFFLINE`/`STALE` status transition + manual `purge_offline_gps_nodes()`, and `tools/gcs_live_bridge.py --lan` (`127.0.0.1` default, `--lan` → `0.0.0.0` + LAN connection URL guidance).
Update reference badges in `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`, `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`, `AMM_PROGRAM_SPECIFICATION.md`, `GAC_PROGRAM_SPECIFICATION_AND_ICD.md` (already `v1.7.0 Approved` with explicit `position`), and mark `TASK-405` (`[-]`), `TASK-405-1` (`[x]`), `TASK-406` (`[-]`), `TASK-406-1` (`[x]`) in `TASK.md`. Temporarily move `GCS_PROGRAM_SPECIFICATION_AND_ICD.md` and `AMM_MISSION_EDITOR_SPECIFICATION.md` to `TARGET_APPROVED` alongside `GAC_PROGRAM_SPECIFICATION_AND_ICD.md` in `tools/verify_spec_status.py` (`11 Implemented, 7 Approved` in `GEMINI.md`).

- [x] **Step 3: Run specification & contract guardrails**

Run:
```powershell
python tools/verify_all_specs.py --check-readmes; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/verify_contracts.py --specs-only }; if ($?) { python tools/verify_context_docs.py }
```
Expected: `0 Errors, 0 Warnings` across all 4 verifiers.

---

### Task 2: `TASK-405` LAN Private IPv4 / `.local` Allowlist & Live Bridge URL Input UI

**Files:**
- Modify: `tools/amm_mission_editor.html`
- Modify: `tests/3_planning/amm/test_amm_mission_editor.py`

**Interfaces:**
- Produces:
  - `LiveBridge.URL_STORAGE_KEY = "uafs_amm_live_bridge_url_v1"`
  - `LiveBridge.isAllowedLocalUrl(url: string) -> boolean`
  - `LiveBridge.setUrl(url: string) -> { ok: boolean, url?: string, error?: string }`
  - `LiveBridge.getUrl() -> string`
  - Top header input `#liveBridgeUrlInput` bound to `LiveBridge.setUrl` and `#btnConnectLive`.

- [x] **Step 1: Write the failing test in `tests/3_planning/amm/test_amm_mission_editor.py`**

Add `TestTask405LanLiveBridgeUrl` in `tests/3_planning/amm/test_amm_mission_editor.py` and update `TestEditorBootstrap` `ws://` regex to allow loopback/RFC1918:
```python
class TestTask405LanLiveBridgeUrl(unittest.TestCase):
    def test_private_ipv4_mdns_allowlist_and_public_ip_rejection(self) -> None:
        res = run_editor_js(
            """
            const L = E.LiveBridge;
            const allowed = [
              "ws://127.0.0.1:8765",
              "ws://localhost:8765",
              "ws://10.0.0.1:8765",
              "ws://10.255.255.254:9000/live",
              "ws://172.16.0.5:8765",
              "ws://172.31.255.10:8765",
              "ws://192.168.0.10:8765",
              "ws://192.168.123.45:8765",
              "ws://gcs-server.local:8765",
              "ws://mc-node-01.lan.local:8765",
            ].map((u) => [u, L.isAllowedLocalUrl(u)]);
            const rejected = [
              "wss://192.168.0.10:8765",
              "http://192.168.0.10:8765",
              "ws://8.8.8.8:8765",
              "ws://172.15.255.1:8765",
              "ws://172.32.0.1:8765",
              "ws://192.169.1.1:8765",
              "ws://192.168.1.256:8765",
              "ws://192.168.1.1:70000",
              "ws://example.com:8765",
              "ws://evil.local.com:8765",
            ].map((u) => [u, L.isAllowedLocalUrl(u)]);
            const setBad = L.setUrl("ws://8.8.8.8:8765");
            const setOk = L.setUrl("ws://192.168.1.50:8765");
            const stored = localStorage.getItem(L.URL_STORAGE_KEY);
            return { allowed, rejected, setBad, setOk, stored, currentUrl: L.getUrl() };
            """
        )
        for url, ok in res["allowed"]:
            self.assertTrue(ok, f"Expected private/local URL to be allowed: {url}")
        for url, ok in res["rejected"]:
            self.assertFalse(ok, f"Expected public/invalid URL to be rejected: {url}")
        self.assertFalse(res["setBad"]["ok"])
        self.assertEqual(res["setBad"]["error"], "NON_LOCAL_BRIDGE_URL")
        self.assertTrue(res["setOk"]["ok"])
        self.assertEqual(res["stored"], "ws://192.168.1.50:8765")
        self.assertEqual(res["currentUrl"], "ws://192.168.1.50:8765")
```

- [x] **Step 2: Run test to verify it fails**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py -k TestTask405LanLiveBridgeUrl -v`
Expected: FAIL (`ws://10.0.0.1:8765` rejected by old `LOCAL_WS_RE` and `L.setUrl` undefined).

- [x] **Step 3: Implement RFC 1918 / `.local` validator, URL persistence, and `#liveBridgeUrlInput` in `tools/amm_mission_editor.html`**

In `tools/amm_mission_editor.html`:
- Add `<input id="liveBridgeUrlInput" type="text" class="mono" style="width:170px" value="ws://127.0.0.1:8765" placeholder="ws://127.0.0.1:8765" aria-label="Live Bridge WebSocket URL" spellcheck="false" autocomplete="off" translate="no">` in `header.top-header` immediately before `#btnConnectLive`.
- In `LiveBridge`:
  - Define `URL_STORAGE_KEY = "uafs_amm_live_bridge_url_v1"`.
  - Implement `isAllowedLocalUrl(url)` parsing `^ws:\/\/([^/:?#\s]+)(?::(\d{1,5}))?(\/[^\s]*)?$` (case-insensitive):
    - If port is present, require integer `1 <= port <= 65535`.
    - Accept host if `host === "localhost"` or `/^[a-z0-9-]+(\.[a-z0-9-]+)*\.local$/i.test(host)`.
    - If host matches `/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/`, parse octets `a, b, c, d`, verify each is `0..255`, and accept only `a === 127`, `a === 10`, `(a === 172 && b >= 16 && b <= 31)`, or `(a === 192 && b === 168)`.
  - Implement `setUrl(url)` and `loadInitialUrl()` reading/writing `localStorage.getItem(URL_STORAGE_KEY)`, and update `connect(url)` to default to `activeUrl` (and persist when a valid `url` argument is passed).
  - In `InspectorUI.renderLiveUi()` and `AppBootstrap.init()`, sync `#liveBridgeUrlInput` value with `LiveBridge.getUrl()` and pass `liveBridgeUrlInput.value` into `LiveBridge.connect(...)` on `#btnConnectLive` click.

- [x] **Step 4: Run test to verify it passes**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py -v`
Expected: PASS (all existing tests + `TestTask405LanLiveBridgeUrl` PASS).

---

### Task 3: `TASK-406-2` Wide-Area Zoom (`0.01..4.0`) & 10-Stage Adaptive Grid/Ruler Scaling

**Files:**
- Modify: `tools/amm_mission_editor.html`
- Modify: `tests/3_planning/amm/test_amm_mission_editor.py`

**Interfaces:**
- Produces:
  - `CanvasRenderer.MIN_ZOOM = 0.01`, `CanvasRenderer.MAX_ZOOM = 4.0`
  - `CanvasRenderer.GRID_STEPS = [10, 25, 50, 100, 200, 500, 1000, 2000, 5000, 10000]`
  - `CanvasRenderer.computeGridStep(zoom: number) -> number`

- [x] **Step 1: Write the failing test in `tests/3_planning/amm/test_amm_mission_editor.py`**

Add `test_wide_area_zoom_and_dynamic_grid_step_scaling` to `TestTask406WideZoomLiveTtlFiltersAndInspection` in `tests/3_planning/amm/test_amm_mission_editor.py`:
```python
class TestTask406WideZoomLiveTtlFiltersAndInspection(unittest.TestCase):
    def test_wide_area_zoom_and_dynamic_grid_step_scaling(self) -> None:
        res = run_editor_js(
            """
            const C = E.CanvasRenderer;
            const S = E.Store;
            S.resetToEmptyDraft({ clearUndo: true });
            S.addCheckpoint("ACT_NAV_SPLINE_WP", { targetPos: { x: -12000, z: -8000 } });
            S.addCheckpoint("ACT_NAV_SPLINE_WP", { targetPos: { x: 12000, z: 8000 } });
            C.fitView();
            const fitZoom = S.getState().ui.zoom;
            return {
              minZoom: C.MIN_ZOOM,
              maxZoom: C.MAX_ZOOM,
              stepAt001: C.computeGridStep(0.01),
              stepAt005: C.computeGridStep(0.05),
              stepAt020: C.computeGridStep(0.20),
              stepAt100: C.computeGridStep(1.0),
              stepAt300: C.computeGridStep(3.0),
              fitZoom,
            };
            """
        )
        self.assertEqual(res["minZoom"], 0.01)
        self.assertEqual(res["maxZoom"], 4.0)
        self.assertGreaterEqual(res["stepAt001"] * 0.01, 55.0)
        self.assertEqual(res["stepAt001"], 10000)
        self.assertEqual(res["stepAt005"], 2000)
        self.assertEqual(res["stepAt020"], 500)
        self.assertEqual(res["stepAt100"], 100)
        self.assertEqual(res["stepAt300"], 25)
        self.assertLess(res["fitZoom"], 0.1)
        self.assertGreaterEqual(res["fitZoom"], 0.01)
```

- [x] **Step 2: Run test to verify it fails**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py -k test_wide_area_zoom_and_dynamic_grid_step_scaling -v`
Expected: FAIL (`C.computeGridStep is not a function` / `fitZoom` clamped at `0.15`).

- [x] **Step 3: Implement `MIN_ZOOM = 0.01`, `computeGridStep(zoom)`, and wide-area `fitView()` in `tools/amm_mission_editor.html`**

In `CanvasRenderer` (`tools/amm_mission_editor.html`):
- Define `MIN_ZOOM = 0.01`, `MAX_ZOOM = 4.0`, and `GRID_STEPS = [10, 25, 50, 100, 200, 500, 1000, 2000, 5000, 10000]`.
- Implement `computeGridStep = (zoom) => { const z = Math.max(MIN_ZOOM, Number(zoom) || 1); for (const s of GRID_STEPS) { if (s * z >= 55) return s; } return 10000; };`.
- Use `computeGridStep(view.zoom)` in `render()` for Layer 1 grid and Layer 8 4-edge rulers.
- In `fitView()`, include live craft and visible world facility coordinates when `checkpoints` is empty (or in `INSPECTION` mode), and clamp zoom with `Math.max(MIN_ZOOM, Math.min(3.0, ...))`.
- In the `wheel` listener, clamp `nextZoom` with `Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, st.ui.zoom * factor))`.
- In `InspectorUI.renderTopBar` and `CanvasRenderer.render`, format zoom percentage as `view.zoom * 100 >= 10 ? Math.round(view.zoom * 100) : Number((view.zoom * 100).toFixed(1))` + `%`.

- [x] **Step 4: Run test to verify it passes**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py -v`
Expected: PASS.

---

### Task 4: `TASK-406-3` Live Node Auto-Registration (`GPS`, `GAC` Explicit Position/Centroid, Subordinate Facilities) & `60s` (`60000ms`) TTL `OFFLINE`/`STALE` + Manual `Purge Offline` Across `GAC`, `GCS`, `gcs_live_bridge.py`, and `LiveBridge`/`WorldStore`

**Files:**
- Modify: `src/0_infra/gac/modules/config_loader.lua`
- Modify: `src/0_infra/gac/modules/beacon_broadcaster.lua`
- Modify: `tests/0_infra/gac/test_config_loader.lua`
- Modify: `tests/0_infra/gac/test_beacon_broadcaster.lua`
- Modify: `src/0_infra/gcs/config/gcs_config.json`
- Modify: `src/0_development/installer/modules/manifest.lua`
- Modify: `src/0_infra/gcs/modules/network_manager.lua`
- Modify: `src/0_infra/gcs/modules/live_bridge_client.lua`
- Modify: `src/0_infra/gcs/main.lua`
- Modify: `tests/0_infra/gcs/test_live_bridge_client.lua`
- Modify: `tests/0_infra/gcs/test_main_loop.lua`
- Modify: `tools/gcs_live_bridge.py`
- Modify: `tests/harness/test_gcs_live_bridge.py`
- Modify: `tools/amm_mission_editor.html`
- Modify: `tests/3_planning/amm/test_amm_mission_editor.py`

**Interfaces:**
- Produces:
  - `GAC`: `config_loader` `position = { x, y, z }` default & validation; `beacon_broadcaster:build_sector_beacon` `payload.position` (explicit `cfg.position` first, centroid of `facilities[]` fallback).
  - `GCS`: `channels.gpsHeartbeatChannel = 60003` (`MSG_GPS_NODE_HEARTBEAT`), `live_bridge_client.send_gps_nodes(state, gps_nodes_map)`, `gacNode` metadata in `WORLD_PRESET_SYNC` (preferring `beacon_payload.position`, falling back to facility centroid), and `60000ms` TTL stale marking (`mark_expired_gps_nodes(now_ms)`) + `purge_offline_gps_nodes()`.
  - `tools/gcs_live_bridge.py`: `--lan` CLI option (`resolve_bind_host(args)` → `"0.0.0.0"` when `--lan` and `--host` default `"127.0.0.1"`, with LAN IP guidance output) + `latest_gps` caching and relay.
  - `tools/amm_mission_editor.html`: `SchemaConstants.FACILITY_TYPES = ["LANDING_PAD", "RUNWAY", "HANGAR", "DOCKING_ARM", "GPS", "GAC", "WAYPOINT"]`, `LiveBridge.NODE_TTL_MS = 60000`, `LiveBridge.handleMessage(rawOrObj, nowMs)`, `LiveBridge.markExpiredNodes(nowMs)`, `LiveBridge.purgeOfflineNodes()`, and `WorldStore` preservation of `liveAuto`, `lastSeenMs`, `isStale`, `liveStatus`, `status`, `sectorId`, `sectorName`, `gacChannel`, `tacticalChannel`, `surfaceWind`, `dedicated`, `currentCraft`, `reservedBy`, `computerId`, `uptime`, `reportsSent`.

- [x] **Step 1: Write failing tests in `tests/0_infra/gcs/`, `tests/harness/test_gcs_live_bridge.py`, and `tests/3_planning/amm/test_amm_mission_editor.py`**

1. In `tests/0_infra/gac/test_config_loader.lua` & `test_beacon_broadcaster.lua`: assert `cfg.position = { x, y, z }` validation (reject non-table/non-numeric `position` when provided) and `build_sector_beacon` emits `payload.position` from explicit `cfg.position` or falls back to the arithmetic centroid of `facilities[]` when `cfg.position` is omitted.
2. In `tests/0_infra/gcs/test_live_bridge_client.lua` & `test_main_loop.lua`: assert `CH 60003` is opened on startup, `MSG_GPS_NODE_HEARTBEAT` on `60003` sends `GPS_NODES_SYNC` over WebSocket, `MSG_FACILITY_BEACON` on `50003` forwards `beacon_payload.position` (or computes `gacNode` centroid) in `WORLD_PRESET_SYNC`, and silent GPS nodes older than `60000ms` are marked `isStale = true, status = "OFFLINE"` without auto-deletion until `purge_offline_gps_nodes()`.
3. In `tests/harness/test_gcs_live_bridge.py`: add `test_lan_flag_bind_host_and_gps_nodes_sync_caching` verifying `--lan` resolves bind host to `"0.0.0.0"` (while default remains `"127.0.0.1"`) and `GPS_NODES_SYNC` is cached for late-joining clients.
4. In `tests/3_planning/amm/test_amm_mission_editor.py`: add `test_live_node_autoregister_gac_centroid_gps_hangar_60s_stale_and_manual_purge` verifying:
   - Manual facility `MAN_PAD_01` is created in `LIVE_SECTOR_1`.
   - `WORLD_PRESET_SYNC` at `t = 1000` with `gacNode` (`GAC_01`, centroid `{x: 200, z: -50}`) and facilities (`PAD_01`, `RWY_01`, `HGR_01` of type `HANGAR`) + `GPS_NODES_SYNC` with `GPS_N1`, `GPS_N2` + `FLEET_TELEMETRY_SYNC` with `CRAFT_01` auto-registers all nodes in `WorldStore` and `LiveBridge`.
   - At `t = 30000` (`+29s`), `LiveBridge.markExpiredNodes(30000)` keeps all live nodes and crafts `ONLINE`.
   - At `t = 62000` (`+61s > 60000ms`), with `GPS_N1` and `CRAFT_01` refreshed at `t = 50000` while `GPS_N2`, `GAC_01`, `PAD_01`, `RWY_01`, `HGR_01` remain at `t = 1000`, `LiveBridge.markExpiredNodes(62000)` marks `GPS_N2`, `GAC_01`, `PAD_01`, `RWY_01`, `HGR_01` as `isStale: true, liveStatus: "OFFLINE"` **without deleting them**.
   - Calling `LiveBridge.purgeOfflineNodes()` removes `GPS_N2`, `GAC_01`, `PAD_01`, `RWY_01`, `HGR_01` while preserving `GPS_N1`, `CRAFT_01`, and manual `MAN_PAD_01`.

- [x] **Step 2: Run tests to verify they fail**

Run:
```powershell
python tools/run_unit_tests.py --target gac --clean-orphans; if ($?) { python tools/run_unit_tests.py --target gcs --clean-orphans }; python -m unittest tests/harness/test_gcs_live_bridge.py tests/3_planning/amm/test_amm_mission_editor.py -v
```
Expected: FAIL on the new GAC `position` / GPS heartbeat / `--lan` / `60s` TTL stale & purge tests.

- [x] **Step 3: Implement `GAC` `position`, `CH 60003` GPS heartbeat relay & `60s` TTL stale/purge in `src/0_infra/{gac,gcs}/` and `--lan` in `tools/gcs_live_bridge.py`**

1. In `src/0_infra/gac/modules/config_loader.lua`, `src/0_infra/gac/modules/beacon_broadcaster.lua`, and `src/0_development/installer/modules/manifest.lua` (`gac.defaultConfigs["/gac/config.json"]`):
   - Add default `position = { x = 1275.0, y = 65.0, z = -810.0 }` to GAC default config and validate optional `cfg.position` (`table` with numeric `x`, `y`, `z`) in `config_loader.validate_config(cfg)`.
   - In `beacon_broadcaster:build_sector_beacon`: compute `payload.position` using `cfg.position` when present, falling back to the arithmetic mean centroid of `facilities[]` positions when `cfg.position` is nil.
2. In `src/0_infra/gcs/config/gcs_config.json`, `src/0_development/installer/modules/manifest.lua`, `src/0_infra/gcs/main.lua`, and `src/0_infra/gcs/modules/network_manager.lua`:
   - Add `gpsHeartbeatChannel = 60003` to `channels` and open it in `network_manager.open_infra_channels(ctx)`.
   - In `live_bridge_client.lua`:
     - In `send_world_preset(state, beacon_payload, gac_domain_id)`: compute `gacNode` (`facilityId = gac_domain_id or ("GAC_" .. tostring(beacon_payload.sectorId or 0))`, `facilityType = "GAC"`, `status = beacon_payload.status or "OPERATIONAL"`, `gacChannel = beacon_payload.gacChannel`, `surfaceWind = beacon_payload.surfaceWind`, `position = beacon_payload.position` or centroid of `beacon_payload.facilities` if non-empty) and attach `gacNode` to `WORLD_PRESET_SYNC` (while keeping `facilities` array intact).
     - Add `send_gps_nodes(state, gps_nodes_map)` sending `{ type = "GPS_NODES_SYNC", nodes = list }`.
   - In `src/0_infra/gcs/main.lua`:
     - Handle `MSG_GPS_NODE_HEARTBEAT` on `gpsHeartbeatChannel` (`60003`), storing `{ nodeId, computerId, pos, status, uptime, reportsSent, lastSeenMs, isStale = false }` in `self.gps_nodes[nodeId]` and calling `live_bridge_client.send_gps_nodes(self.bridge, self.gps_nodes)`.
     - Add `mark_expired_gps_nodes(now_ms)` (`ttl_ms = 60000`) to mark silent GPS nodes (`now_ms - lastSeenMs > 60000`) as `isStale = true, status = "OFFLINE"`, and `purge_offline_gps_nodes()` to remove `isStale == true` GPS entries on operator request.
3. In `tools/gcs_live_bridge.py`:
   - Add `--lan` CLI flag (`action="store_true"`), `resolve_bind_host(args)` (returns `"0.0.0.0"` when `--lan` and `--host == "127.0.0.1"`), LAN IP hint printing on startup, and `self.latest_gps` caching/replay for `GPS_NODES_SYNC`.

- [x] **Step 4: Implement live node auto-registration & `60000ms` TTL `OFFLINE`/`STALE` + `Purge Offline` in `tools/amm_mission_editor.html`**

In `tools/amm_mission_editor.html`:
- Expand `SchemaConstants.FACILITY_TYPES` to `["LANDING_PAD", "RUNWAY", "HANGAR", "DOCKING_ARM", "GPS", "GAC", "WAYPOINT"]`.
- In `WorldStore.sanitizeFacility`: preserve optional live metadata fields (`liveAuto`, `lastSeenMs`, `isStale`, `liveStatus`, `status`, `sectorId`, `sectorName`, `gacChannel`, `tacticalChannel`, `surfaceWind`, `dedicated`, `currentCraft`, `reservedBy`, `computerId`, `uptime`, `reportsSent`), and add `WorldStore.markExpiredLiveFacilities(nowMs, ttlMs)` + `WorldStore.purgeOfflineLiveFacilities()` (removes only `f.liveAuto === true && (f.isStale === true || f.liveStatus === "OFFLINE")`).
- In `LiveBridge`:
  - Define `NODE_TTL_MS = 60000`.
  - Update `handleWorldSync(msg, nowMs)`: map `msg.facilities` with `liveAuto: true, lastSeenMs: nowMs, isStale: false, liveStatus: "ONLINE"`; if `msg.gacNode` has a valid `position`, also include the `GAC` facility entry (without duplicating if already in `msg.facilities`). Upsert into the live sector world while preserving existing manual facilities (`!f.liveAuto`) and `GPS` nodes in that world.
  - Add `handleGpsNodesSync(msg, nowMs)`: map `msg.nodes` into `FacilityEntry` items (`facilityId: n.nodeId, label: n.nodeId, type: "GPS", x: n.pos.x, z: n.pos.z, y: n.pos.y, status: n.status || "ONLINE", isStale: Boolean(n.isStale), liveStatus: n.isStale ? "OFFLINE" : (n.status || "ONLINE"), computerId: n.computerId, uptime: n.uptime, reportsSent: n.reportsSent, liveAuto: true, lastSeenMs: nowMs`) and upsert into the active live world (or `LIVE_SECTOR_0` if no `LIVE_SECTOR_*` world exists yet).
  - Update `handleFleetSync(msg, nowMs)`: merge incoming crafts (`lastSeenMs: nowMs, isStale: Boolean(raw.isStale), liveStatus: raw.isStale ? "STALE" : "ONLINE"`), retaining absent crafts so `markExpiredNodes` transitions them to `OFFLINE` at `60000ms`, and auto-center `Store.setUi({ viewOffset })` when `ui.followCraftId` matches an active craft.
  - Implement `markExpiredNodes(nowMs = Date.now())` and `purgeOfflineNodes()` (clearing stale crafts/trails and calling `WorldStore.purgeOfflineLiveFacilities()`), plus `#btnPurgeOffline` in UI and `5000ms` periodic `markExpiredNodes()` timer while connected.

- [x] **Step 5: Run GAC/GCS Lua unit tests, Python bridge tests, and AMM editor tests**

Run:
```powershell
python tools/run_unit_tests.py --target gac --clean-orphans; if ($?) { python tools/run_unit_tests.py --target gcs --clean-orphans }; if ($?) { python -m unittest tests/harness/test_gcs_live_bridge.py tests/3_planning/amm/test_amm_mission_editor.py -v }
```
Expected: PASS.

---

### Task 5: `TASK-406-4` & `TASK-406-5` Target Filtering UI/Renderer & Read-Only `Inspection` Mode

**Files:**
- Modify: `tools/amm_mission_editor.html`
- Modify: `tests/3_planning/amm/test_amm_mission_editor.py`

**Interfaces:**
- Produces:
  - `Store` `state.ui.editorMode = "MISSION_EDIT" | "INSPECTION"`, `state.ui.inspectedEntity = null | { kind: "CRAFT" | "FACILITY" | "CHECKPOINT", id: string }`, `state.ui.followCraftId = string | null`
  - `Store` `state.ui.filters = { showCrafts: true, craftAirframeFilter: "ALL", showFacilities: true, facilityTypeFilter: "ALL", facilityTypes: { GAC: true, GPS: true, LANDING_PAD: true, RUNWAY: true, HANGAR: true, DOCKING_ARM: true, WAYPOINT: true } }`
  - `Store.setEditorMode(mode)`, `Store.setFilter(patch)`, `Store.setFacilityTypeVisible(type, visible)`, `Store.selectInspectedEntity(entity)`, `Store.setFollowCraft(domainId)`
  - `CanvasRenderer.isCraftVisible(craft, ui)`, `CanvasRenderer.isFacilityVisible(fac, ui)`, `CanvasRenderer.hitTestInspectionTarget(sx, sy, view)`

- [x] **Step 1: Write failing tests in `tests/3_planning/amm/test_amm_mission_editor.py`**

Add `test_target_filtering_craft_and_facility_types` and `test_inspection_mode_locks_mutations_and_renders_entity_hud` to `TestTask406WideZoomLiveTtlFiltersAndInspection` in `tests/3_planning/amm/test_amm_mission_editor.py`:
```python
    def test_target_filtering_craft_and_facility_types(self) -> None:
        res = run_editor_js(
            """
            const S = E.Store, W = E.WorldStore, L = E.LiveBridge, C = E.CanvasRenderer;
            W.upsertFacility({ facilityId: "F_PAD", type: "LANDING_PAD", x: 10, z: 10 });
            W.upsertFacility({ facilityId: "F_GPS", type: "GPS", x: 50, z: 50 });
            W.upsertFacility({ facilityId: "F_GAC", type: "GAC", x: -50, z: -50 });
            W.upsertFacility({ facilityId: "F_HGR", type: "HANGAR", x: 80, z: -40 });
            L.handleMessage({
              type: "FLEET_TELEMETRY_SYNC",
              crafts: [
                { domainId: "VTOL_01", airframeType: "WINGED_VTOL", baseChannel: 10000, fsmState: "CRUISE", position: { x: 0, y: 120, z: 0 } },
                { domainId: "QUAD_02", airframeType: "MULTICOPTER", baseChannel: 10040, fsmState: "HOVER", position: { x: 30, y: 90, z: 30 } },
              ],
            }, 1000);
            S.setFilter({ craftAirframeFilter: "WINGED_VTOL", facilityTypeFilter: "GPS" });
            const st1 = S.getState();
            const vis1 = {
              vtol: C.isCraftVisible(L.getFleetCrafts()[0], st1.ui),
              quad: C.isCraftVisible(L.getFleetCrafts()[1], st1.ui),
              pad: C.isFacilityVisible(W.getFacility("F_PAD"), st1.ui),
              gps: C.isFacilityVisible(W.getFacility("F_GPS"), st1.ui),
            };
            S.setFilter({ craftAirframeFilter: "ALL", facilityTypeFilter: "ALL" });
            S.setFacilityTypeVisible("HANGAR", false);
            const st2 = S.getState();
            const vis2 = {
              hgr: C.isFacilityVisible(W.getFacility("F_HGR"), st2.ui),
              gac: C.isFacilityVisible(W.getFacility("F_GAC"), st2.ui),
            };
            return { vis1, vis2 };
            """
        )
        self.assertEqual(res["vis1"], {"vtol": True, "quad": False, "pad": False, "gps": True})
        self.assertEqual(res["vis2"], {"hgr": False, "gac": True})

    def test_inspection_mode_locks_mutations_and_renders_entity_hud(self) -> None:
        res = run_editor_js(
            """
            const S = E.Store, W = E.WorldStore, L = E.LiveBridge, C = E.CanvasRenderer;
            S.loadPreset("MSN_RECON_001");
            const countBefore = S.getState().mission.checkpoints.length;
            W.upsertFacility({ facilityId: "GPS_ALPHA", type: "GPS", x: 100, z: -100, y: 80, status: "ONLINE", uptime: 320, reportsSent: 44 });
            L.handleMessage({
              type: "FLEET_TELEMETRY_SYNC",
              crafts: [
                { domainId: "JET_99", airframeType: "WINGED_VTOL", baseChannel: 10080, fsmState: "LOITER", fuel: 0.64, groundSpeed: 19.5, attitude: { pitch: 2, roll: -5, yaw: 135 }, position: { x: 200, y: 160, z: -200 } },
              ],
            }, 2000);
            S.setEditorMode("INSPECTION");
            const blockedAdd = S.addCheckpoint("ACT_NAV_SPLINE_WP", { targetPos: { x: 0, z: 0 } });
            const blockedDel = S.deleteCheckpoint(0);
            const countAfter = S.getState().mission.checkpoints.length;
            const view = { offsetX: 0, offsetZ: 0, zoom: 1.0, width: 800, height: 600 };
            const craftScreen = C.worldToScreen(200, -200, view);
            const hitCraft = C.hitTestInspectionTarget(craftScreen.sx, craftScreen.sy, view);
            S.selectInspectedEntity(hitCraft);
            const inspected1 = S.getState().ui.inspectedEntity;
            S.setFollowCraft("JET_99");
            L.handleMessage({
              type: "FLEET_TELEMETRY_SYNC",
              crafts: [
                { domainId: "JET_99", airframeType: "WINGED_VTOL", baseChannel: 10080, fsmState: "LOITER", position: { x: 350, y: 160, z: -420 } },
              ],
            }, 2500);
            const followedOffset = { ...S.getState().ui.viewOffset };
            const gpsScreen = C.worldToScreen(100, -100, { offsetX: 0, offsetZ: 0, zoom: 1.0, width: 800, height: 600 });
            const hitGps = C.hitTestInspectionTarget(gpsScreen.sx, gpsScreen.sy, { offsetX: 0, offsetZ: 0, zoom: 1.0, width: 800, height: 600 });
            S.selectInspectedEntity(hitGps);
            const inspected2 = S.getState().ui.inspectedEntity;
            S.setFollowCraft(null);
            S.setEditorMode("MISSION_EDIT");
            return { countBefore, blockedAdd, blockedDel, countAfter, inspected1, followedOffset, inspected2 };
            """
        )
        self.assertEqual(res["blockedAdd"], -1)
        self.assertFalse(res["blockedDel"])
        self.assertEqual(res["countBefore"], res["countAfter"])
        self.assertEqual(res["inspected1"], {"kind": "CRAFT", "id": "JET_99"})
        self.assertEqual(res["followedOffset"], {"x": 350, "z": -420})
        self.assertEqual(res["inspected2"], {"kind": "FACILITY", "id": "GPS_ALPHA"})
```

- [x] **Step 2: Run test to verify it fails**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py -k TestTask406WideZoomLiveTtlFiltersAndInspection -v`
Expected: FAIL (`S.setFilter` / `S.setEditorMode` / `C.hitTestInspectionTarget` not defined).

- [x] **Step 3: Implement Target Filtering and `Inspection` Mode in `tools/amm_mission_editor.html`**

In `tools/amm_mission_editor.html`:
1. **Top Header & Canvas Overlay HTML**:
   - Add mode switch segmented group in `header.top-header`:
     `<div class="segmented" role="group" aria-label="Editor workspace mode"><button id="btnModeMissionEdit" type="button" aria-pressed="true">Mission Edit</button><button id="btnModeInspection" type="button" aria-pressed="false">Inspection</button></div>`
   - Add filter & purge controls in `.canvas-overlay-bar`:
     - `<button id="btnFilterCrafts" type="button" aria-pressed="true" title="Show/hide live aircraft on 2D map">Crafts</button>`
     - `<select id="filterCraftTypeSelect" aria-label="Filter aircraft by airframe type"><option value="ALL">All Crafts</option><option value="WINGED_VTOL">WINGED_VTOL</option><option value="MULTICOPTER">MULTICOPTER</option><option value="FIXED_WING">FIXED_WING</option><option value="ADVANCED_VTOL">ADVANCED_VTOL</option><option value="VECTORED_VTOL">VECTORED_VTOL</option></select>`
     - `<select id="filterFacilityTypeSelect" aria-label="Filter world facilities by type"><option value="ALL">All Facilities</option><option value="GAC">GAC</option><option value="GPS">GPS</option><option value="LANDING_PAD">LANDING_PAD</option><option value="RUNWAY">RUNWAY</option><option value="HANGAR">HANGAR</option><option value="DOCKING_ARM">DOCKING_ARM</option><option value="WAYPOINT">WAYPOINT</option></select>`
     - `<button id="btnPurgeOffline" type="button" title="Remove OFFLINE/STALE auto-registered live nodes">Purge Offline</button>`
2. **`Store` State & Guards**:
   - Initialize `editorMode: "MISSION_EDIT"`, `inspectedEntity: null`, `followCraftId: null`, and `filters` in `state.ui`.
   - Implement `setEditorMode(mode)`, `setFilter(patch)`, `setFacilityTypeVisible(type, visible)`, `selectInspectedEntity(entity)`, and `setFollowCraft(domainId)`.
   - Guard `addCheckpoint` (return `-1`), `deleteCheckpoint`, `moveCheckpoint`, `duplicateCheckpoint`, `expandSelectedMacro`, `mutateMission`, `setMission`, and `loadPreset` (return `false` when `state.ui.editorMode === "INSPECTION"`), while allowing camera `Follow` and `Push to Aircraft`.
3. **`CanvasRenderer` Filtering, Glyphs & Inspection Hit-Testing**:
   - Add distinct colors/glyphs for `HANGAR` (`#38bdf8` roofed box), `GPS` (`#22d3ee` satellite cross/diamond), and `GAC` (`#f43f5e` tower hexagon/beacon ring); draw `isStale || liveStatus === "OFFLINE"` entries semi-transparently (`globalAlpha = 0.38`) with `[OFFLINE]` tag.
   - Implement `isCraftVisible(craft, ui)` (checks `ui.showLiveCrafts !== false`, `filters.showCrafts !== false`, and `filters.craftAirframeFilter === "ALL" || craft.airframeType === filters.craftAirframeFilter`) and `isFacilityVisible(fac, ui)` (checks `ui.showWorldFacilities !== false`, `filters.showFacilities !== false`, `filters.facilityTypeFilter === "ALL" || fac.type === filters.facilityTypeFilter`, and `filters.facilityTypes[fac.type] !== false`).
   - Apply `isFacilityVisible` and `isCraftVisible` in `render()`, `hitTestFacilityPin()`, and `hitTestInspectionTarget(sx, sy, view)`.
   - In `bindMapEvents`: when `st.ui.editorMode === "INSPECTION"`, left-clicking hits `hitTestInspectionTarget(pt.sx, pt.sy, view)` and calls `Store.selectInspectedEntity(hit)` (or pans if no entity is hit), never initiating a checkpoint coordinate drag.
4. **`InspectorUI` Inspection Mode Rendering**:
   - When `st.ui.editorMode === "INSPECTION"`:
     - Hide `#btnOpenAddPicker` / `#btnOpenMacroPicker` while keeping `#btnPushAircraft` enabled, and render an interactive **Live Entities & Checkpoints** list in `#cpList` (grouped by visible Live Crafts, visible Facilities/`GAC`/`GPS`, and Checkpoints) so clicking any item selects `inspectedEntity` and centers the 2D canvas.
     - Render the read-only **Inspection HUD** in `#inspectorBody` showing detailed telemetry, attitude, speed, fuel, channel block, facility status/reservation/wind, GPS uptime/reports, `60s` TTL status (`ONLINE`/`OFFLINE`), plus a **`Follow Craft`** toggle button (`Store.setFollowCraft`).

- [x] **Step 4: Run test to verify it passes**

Run: `python -m unittest tests/3_planning/amm/test_amm_mission_editor.py -v`
Expected: PASS.

---

### Task 6: Full Verification Gate, Spec `Implemented` Promotion & Context Sync

**Files:**
- Modify: `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (`Approved` → `Implemented`)
- Modify: `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` (`Approved` → `Implemented`)
- Modify: `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md` (`Approved` → `Implemented`)
- Modify: `tools/verify_spec_status.py`
- Modify: `TASK.md`
- Modify: `GEMINI.md`
- Modify: `.agent/memory/workspace-root.md`

- [x] **Step 1: Promote `AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.6.0`), `GCS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v1.4.0`), and `GAC_PROGRAM_SPECIFICATION_AND_ICD.md` (`v1.7.0`) to `Implemented`**

Update `| **문서 상태 (Status)** | \`Implemented\` |` in all three specifications and restore all three paths to `TARGET_IMPLEMENTED` in `tools/verify_spec_status.py` (`14 Implemented, 4 Approved`).

- [x] **Step 2: Update `TASK.md`, `GEMINI.md`, and `.agent/memory/workspace-root.md`**

- In `TASK.md`: mark `TASK-405` (`TASK-405-1..3`) and `TASK-406` (`TASK-406-1..5`) as `[x]`, move both to the top of `## ✅ 3. 완료된 작업 이력`, and prune the oldest archived entries so `## ✅ 3. 완료된 작업 이력` retains at most `10` items (Rule R7).
- In `GEMINI.md` (strictly `<= 80` lines): update `## 1. Current Phase & Active Handover` (`직전 완료: TASK-406, TASK-405, ...`) and any updated test counts in `## 3. Standard Commands`.
- In `.agent/memory/workspace-root.md`: append a dated `2026-11-18` milestone entry referencing `TASK-405` and `TASK-406` (Rule R8).

- [x] **Step 3: Execute the full project verification suite**

Run:
```powershell
python tools/verify_contracts.py; if ($?) { python tools/verify_runtime_wiring.py }; if ($?) { python tools/run_boot_smoke.py --clean-orphans }; if ($?) { python tools/run_unit_tests.py --require-tests --clean-orphans }; if ($?) { python tools/run_e2e_tests.py --clean-orphans }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }; if ($?) { python -m unittest tests/3_planning/amm/test_amm_mission_editor.py -v }; if ($?) { python tools/verify_manifest_sync.py --strict-gdrive-packages }; if ($?) { python tools/verify_all_specs.py --check-readmes }; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/validate_lua_syntax.py }; if ($?) { python tools/verify_context_docs.py }
```
Expected: All commands exit `0` with `0 errors` / `0 findings`.
