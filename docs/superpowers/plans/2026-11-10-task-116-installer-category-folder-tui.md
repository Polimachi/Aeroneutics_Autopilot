# Unified Installer Category Folder TUI Refactoring (TASK-116) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the CC:Tweaked Unified Codebase Installer (`installer.lua` and `src/0_development/installer/`) from a flat 12-row module menu into a 2-level domain category folder navigation TUI (`CATEGORY_MENU` $\leftrightarrow$ `MODULE_MENU`) with viewport scrolling, backed by a formal program specification (`docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md`).

**Architecture:** `manifest.lua` defines canonical category metadata (`CATEGORY_ORDER`, `CATEGORIES`) and query helpers (`getCategory`, `listCategories`, `listModulesByCategory`) aligned with the 6 repository layers (`development`, `infra`, `control`, `guidance`, `planning`, `mission`) enforced by `tools/verify_manifest_sync.py`. `tui_view.lua` adds a viewport window calculator (`computeViewport`) and a root folder renderer (`renderCategoryMenu`) while upgrading `renderMenu` to clear ghost rows and scroll within the 12-row (`y = 4..15`) viewport on a `51x19` terminal. `installer_app.lua` transitions its interactive event loop to a 2-level state machine (`CATEGORY_MENU` $\to$ `MODULE_MENU` $\to$ `CONFIRM_INSTALL` / `CONFIRM_UNINSTALL`) while preserving non-interactive CLI commands (`install <id>`, `uninstall <id>`) unchanged.

**Tech Stack:** CC:Tweaked 1.109+ Lua 5.2 (Cobalt VM), ComputerCraft `term` / `fs` / `http` / `textutils` APIs, CraftOS-PC Headless Unit Test Runner (`tools/run_unit_tests.py`), Python 3.10+ verification suite (`tools/verify_manifest_sync.py`, `tools/verify_all_specs.py`, `tools/verify_spec_status.py`).

**Spec:**
- New Program Specification: `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` (`Draft` $\to$ `Approved` in Task 1 $\to$ `Implemented` in Task 4)
- Roadmap SSOT: `TASK.md` (`TASK-116`)
- Related Specs & Guides: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (§9), `docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md`
- Rules: `.agent/rules/cc-tweaked-runtime.md`, `.agent/rules/domain-aeronautics.md`, `.agent/rules/skill-workflows.md`

## Global Constraints

- **Lua 5.2 Cobalt Compatibility (`.agent/rules/cc-tweaked-runtime.md`)**: Zero Lua 5.3+ bitwise/integer division operators (`//`, `&`, `|`, `~`, `<<`, `>>`), zero `getfenv`/`setfenv`, zero host OS filesystem calls (`os.remove`, `os.rename`, `io.open`). Use `fs.*` exclusively.
- **Valkyrien Skies Ban (`.agent/rules/domain-aeronautics.md`)**: Zero prohibited mod strings (`valkyrien`, `vs2`, `cc_vs`, `ship` peripheral, `kontraption:`).
- **3-Way Manifest Sync Invariant (`tools/verify_manifest_sync.py`)**:
  - `installer.lua` (repository root) and `src/0_development/installer/installer.lua` must remain byte-for-byte identical.
  - Every module's `category` field in `manifest.MODULES` must remain in `{"development", "infra", "control", "guidance", "planning", "mission"}` matching its `src/<layer>/` directory.
  - `BOOTSTRAP_FILES` in `installer.lua` and `manifest.lua` must remain synchronized with `config/gdrive_mapping.json`.
- **51x19 Terminal & UI Auditor Discipline (`harness/unit/guest/runner_lib.lua`)**:
  - Never write outside `x = 1..51`, `y = 1..19`.
  - Menu viewport occupies `startY = 4` through `endY = h - 4` (`12` visible rows on `51x19`).
  - Never call `_G.printError`; render all status/error messages via `tui_view.renderMessage` on row `h` (`y = 19`).
- **Scope Boundary (`TASK-116`)**: Focus strictly on hierarchical category folder grouping and TUI navigation/scrolling; do NOT add multi-module composite bundle installation to a single computer (each CC:Tweaked computer mounts one standalone subsystem at `/`, except co-installed `gps_client` or `/lib/avionics_sensors.lua`).
- **Spec-First Lifecycle (`skill-workflows.md`)**: Author and approve `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` in Task 1 before modifying any `.lua` files in Tasks 2–3, then promote to `Implemented` in Task 4 after all verification gates pass.
- **Overclaim Ban (`AGENTS.md`)**: Report exact numeric test and verifier outputs only (`0 Errors, 0 Warnings`, `<N>/<N> PASS`).

## Review Focus

1. **Ghost Rows Left Behind on Screen Transitions (`CATEGORY_MENU` $\leftrightarrow$ `MODULE_MENU`)**: When navigating from the 5-row category folder menu into a 1-module category folder (such as `2_guidance` containing only `fcp`), rows `5..15` would retain stale category text unless `renderCategoryMenu` and `renderMenu` explicitly blank all unoccupied viewport rows (`startY .. h - 4`) and row `h` on every frame (tested in Task 3 `test_installer_tui_and_app.lua`).
2. **Viewport Overflow When Module Count Exceeds 12 Rows (`y > h - 4`)**: If a category folder (or a synthetic module list) contains more than `12` items (e.g. `15` modules) and the user presses `Down` to index `15`, the cursor must stay visible via `computeViewport` scrolling (`firstIdx = 4, lastIdx = 15, scrollOffset = 3`) without ever calling `setCursorPos` on `y > 15` for list items (tested in Task 3 `test_installer_tui_and_app.lua`).
3. **Empty Category Folder Filtering (`4_mission` with `0` Active Modules)**: `manifest.CATEGORY_ORDER` includes all 6 architectural layers (`development`, `infra`, `control`, `guidance`, `planning`, `mission`), but `4_mission` currently has `0` registered modules; `manifest.listCategories()` (default `includeEmpty = false`) must omit empty categories so the TUI never opens a dead-end empty folder, while `manifest.listCategories(true)` returns all 6 categories for structural inspection (tested in Task 2 `test_manifest_and_registry.lua`).
4. **Parent Folder Cursor Preservation and Installed Counter Refresh (`[x/y inst]`)**: Opening category `#2` (`0_infra`), installing or uninstalling a module inside it, and pressing `Backspace` / `Left` / `B` to return to `CATEGORY_MENU` must preserve `categoryIndex == 2` and immediately reflect the updated `[installed/total inst]` counter on the folder row without restarting the installer (tested in Task 3 `test_installer_tui_and_app.lua`).
5. **Non-Interactive CLI Backward Compatibility**: Existing automated scripts and tests invoking `installer.lua install <moduleId> --source github` or `installer.lua uninstall <moduleId>` must bypass the 2-level TUI folder menu and execute directly by `moduleId` (tested in Task 3 `test_installer_tui_and_app.lua`).

---

## File Structure

- Create: `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` — Formal specification for the Unified Codebase Installer (`v1.1.0`), covering the 3-mode bootstrapper, dual sources, atomic staged download, deep-merge config migration, multi-boot startup hooks, `/.version.json` orphan safety, and the 2-level category folder TUI.
- Modify: `tools/verify_all_specs.py` — Register `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` in `SPEC_FILES` and `REVISION_HISTORY_SPECS` (14 $\to$ 15 active specs).
- Modify: `tools/verify_spec_status.py` — Register `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` in `TARGET_APPROVED` (Task 1) and promote to `TARGET_IMPLEMENTED` (Task 4).
- Modify: `src/0_development/installer/modules/manifest.lua` — Bump `manifest.VERSION = "1.1.0"`, add `manifest.CATEGORY_ORDER`, `manifest.CATEGORIES`, `manifest.getCategory(categoryId)`, `manifest.listCategories(includeEmpty)`, and `manifest.listModulesByCategory(categoryId)`.
- Modify: `src/0_development/installer/modules/tui_view.lua` — Add `tui_view.computeViewport(totalItems, selectedIndex, maxVisibleRows, currentScrollOffset)`, `tui_view.renderCategoryMenu(termObj, categories, selectedIndex, currentSource, installedMap, scrollOffset)`, and upgrade `tui_view.renderMenu(termObj, modules, selectedIndex, currentSource, installedMap, categoryInfo, scrollOffset)` with viewport scrolling, breadcrumb subtitle, and full viewport row clearing.
- Modify: `src/0_development/installer/installer_app.lua` — Upgrade `installer_app.run(opts)` interactive TUI state machine to 2-level folder navigation (`CATEGORY_MENU` $\leftrightarrow$ `MODULE_MENU` $\leftrightarrow$ `CONFIRM_INSTALL` / `CONFIRM_UNINSTALL`).
- Modify: `src/0_development/installer/installer.lua` & `installer.lua` — Bump `bootstrapper.VERSION = "1.1.0"` in both files maintaining byte-for-byte parity.
- Modify: `tests/0_development/installer/test_manifest_and_registry.lua` — Add unit tests for category metadata, `listCategories(false/true)`, and `listModulesByCategory`.
- Modify: `tests/0_development/installer/test_installer_tui_and_app.lua` — Add unit tests for `computeViewport`, `renderCategoryMenu`, ghost-row clearing on folder transition, $>12$ item viewport scrolling, and 2-level TUI key navigation (`CATEGORY_MENU` $\to$ `MODULE_MENU` $\to$ install/uninstall $\to$ `Backspace` back to folder list $\to$ `Quit`).
- Modify: `README.md`, `TASK.md`, `GEMINI.md`, `.agent/memory/workspace-root.md` — Sync documentation links, spec counts, unit test counts, and milestone handover.

---

### Task 1: Author & Approve Unified Installer Program Specification (`TASK-116-1`)

**Files:**
- Create: `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md`
- Modify: `tools/verify_all_specs.py:16-49`
- Modify: `tools/verify_spec_status.py:16-35`
- Modify: `README.md:50-58`

**Interfaces:**
- Consumes:
  - `docs/specs/README.md` (5-row metadata table and lifecycle state rules)
  - `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (§9 installer integration reference)
  - `docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md`
- Produces:
  - `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` (`Status: Approved`, `Version: v1.1.0`, `Date: 2026-11-10`, `Source: src/0_development/installer/`)
  - Updated `SPEC_FILES` and `REVISION_HISTORY_SPECS` in `tools/verify_all_specs.py` (15 active specs)
  - Updated `TARGET_APPROVED` in `tools/verify_spec_status.py` (9 Implemented, 6 Approved during implementation)

- [ ] **Step 1: Create `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` with `Approved` metadata**

Write `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` containing:
1. Standard 5-field top metadata table:
   ```markdown
   | 항목 | 내용 |
   | :--- | :--- |
   | **문서 상태 (Status)** | `Approved` |
   | **문서 버전 (Version)** | `v1.1.0` |
   | **최종 수정일 (Date)** | `2026-11-10` |
   | **구현 코드 (Source)** | `src/0_development/installer/` |
   | **주관 도메인 (Domain)** | 통합 코드베이스 배포 및 계층형 패키지 매니저 (Unified Installer) |
   ```
2. Relative links to `../../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`, `../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`, `../../0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`, `../../../guides/GDRIVE_DEPLOYMENT_GUIDE.md`, and `../../../../GEMINI.md`.
3. `### Revision History` table with `v1.0.0` (`2026-11-08`, initial 3-mode unified installer & flat TUI) and `v1.1.0` (`2026-11-10`, 2-level category folder TUI navigation and 12-row viewport scrolling for `TASK-116`).
4. Sections covering:
   - §1 Overview & 3-Mode Execution Contexts (`direct_root`, `disk`, `remote_wget`)
   - §2 Dual Remote Sources (`github`, `gdrive`) & 7-File Bootstrap Architecture (`/.installer_cache`)
   - §3 Declarative Manifest & 6-Layer Category Folder Taxonomy (`0_development`, `0_infra`, `1_control`, `2_guidance`, `3_planning`, `4_mission`)
   - §4 51x19 2-Level Interactive TUI State Machine (`CATEGORY_MENU` $\leftrightarrow$ `MODULE_MENU` $\leftrightarrow$ `CONFIRM_INSTALL` / `CONFIRM_UNINSTALL`) & 12-Row Viewport Scrolling
   - §5 Atomic Staged Installation (`/.installer_stage`), Deep-Merge Config Migration, Multi-Boot Startup Hook (`/startup/00_<id>.lua`), and `/.version.json` Orphan Safety
   - §6 Static 3-Way Verification (`tools/verify_manifest_sync.py`) & Safety Fail-Safe Matrix (zero executable Lua runtime code blocks in spec per `skill-workflows.md`).

- [ ] **Step 2: Register the new specification in `tools/verify_all_specs.py`, `tools/verify_spec_status.py`, and `README.md`**

In `tools/verify_all_specs.py`, add `'docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md'` to `SPEC_FILES` and `REVISION_HISTORY_SPECS`.
In `tools/verify_spec_status.py`, add `'docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md'` to `TARGET_APPROVED`.
In `README.md`, update the `docs/specs/0_development/` tree comment to include `installer`.

- [ ] **Step 3: Run specification integrity and status verifiers**

Run:
```powershell
python tools/verify_all_specs.py --check-readmes; if ($?) { python tools/verify_spec_status.py }
```
Expected:
- `verify_all_specs.py`: `SCAN RESULT: ALL 15 SPECS 100% CLEAN (0 Errors, 0 Warnings)` and `README audit complete: 0 error(s)`.
- `verify_spec_status.py`: `[PASS] All 15 specs have valid statuses (9 Implemented, 6 Approved)!`

- [ ] **Step 4: Commit Task 1**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md tools/verify_all_specs.py tools/verify_spec_status.py README.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(installer): add unified installer specification v1.1.0 Approved (TASK-116-1)"
```

---

### Task 2: Add Category Folder Registry & Grouping Helpers in `manifest.lua` (`TASK-116-2`)

**Files:**
- Modify: `src/0_development/installer/modules/manifest.lua:6-50,550-585`
- Modify: `src/0_development/installer/installer.lua:6`
- Modify: `installer.lua:6`
- Modify: `tests/0_development/installer/test_manifest_and_registry.lua:67-95`

**Interfaces:**
- Consumes: `manifest.MODULE_ORDER`, `manifest.MODULES`
- Produces:
  - `manifest.VERSION = "1.1.0"` (and `bootstrapper.VERSION = "1.1.0"` in `installer.lua` & `src/0_development/installer/installer.lua`)
  - `manifest.CATEGORY_ORDER = { "development", "infra", "control", "guidance", "planning", "mission" }`
  - `manifest.CATEGORIES`:
    - `development = { id = "development", code = "0_development", name = "Development & Calibration", shortName = "Dev & Align", description = "Hangar calibration, sensors library, and diagnostics" }`
    - `infra = { id = "infra", code = "0_infra", name = "Ground Infrastructure", shortName = "Ground Infra", description = "GPS cluster, GCS, GAC, landing pads, and runway" }`
    - `control = { id = "control", code = "1_control", name = "Flight Control", shortName = "Flight Control", description = "Onboard 20Hz attitude, thruster, and aero adapters" }`
    - `guidance = { id = "guidance", code = "2_guidance", name = "Guidance & Navigation", shortName = "Guidance (FCP)", description = "Outer-loop flight computer and airframe drivers" }`
    - `planning = { id = "planning", code = "3_planning", name = "Mission Planning & MFD", shortName = "Planning (AMM)", description = "Cockpit MFD terminal and waypoint mission manager" }`
    - `mission = { id = "mission", code = "4_mission", name = "Swarm & Payload Mission", shortName = "Swarm Mission", description = "Multi-craft formation and payload orchestration" }`
  - `manifest.getCategory(categoryId: string) -> table|nil`
  - `manifest.listModulesByCategory(categoryId: string) -> list<table>` (ordered by `manifest.MODULE_ORDER`)
  - `manifest.listCategories(includeEmpty: boolean|nil) -> list<table>` (each entry is a shallow copy of the category definition with `modules = listModulesByCategory(id)` and `moduleCount = #modules`; omits categories where `moduleCount == 0` unless `includeEmpty == true`)

- [ ] **Step 1: Write the failing unit tests in `tests/0_development/installer/test_manifest_and_registry.lua`**

Update the version assertion in `test_manifest_and_registry.lua` (`manifest.VERSION == "1.1.0"`) and add a new test block:
```lua
    it("groups modules into domain categories in deterministic layer order and filters empty folders by default", function()
        assert_eq(#manifest.CATEGORY_ORDER, 6)
        assert_eq(manifest.CATEGORY_ORDER[1], "development")
        assert_eq(manifest.CATEGORY_ORDER[2], "infra")
        assert_eq(manifest.CATEGORY_ORDER[3], "control")
        assert_eq(manifest.CATEGORY_ORDER[4], "guidance")
        assert_eq(manifest.CATEGORY_ORDER[5], "planning")
        assert_eq(manifest.CATEGORY_ORDER[6], "mission")

        local infraCat = manifest.getCategory("infra")
        assert_not_nil(infraCat)
        assert_eq(infraCat.code, "0_infra")
        assert_eq(infraCat.name, "Ground Infrastructure")

        -- Non-empty categories only (default includeEmpty = false)
        local activeCats = manifest.listCategories()
        assert_eq(#activeCats, 5)
        assert_eq(activeCats[1].id, "development")
        assert_eq(activeCats[1].moduleCount, 2)
        assert_eq(activeCats[1].modules[1].id, "alignment")
        assert_eq(activeCats[1].modules[2].id, "sensors")

        assert_eq(activeCats[2].id, "infra")
        assert_eq(activeCats[2].moduleCount, 6)
        assert_eq(activeCats[2].modules[1].id, "gps_server")
        assert_eq(activeCats[2].modules[6].id, "gcs")

        assert_eq(activeCats[3].id, "control")
        assert_eq(activeCats[3].moduleCount, 2)
        assert_eq(activeCats[3].modules[1].id, "vas")
        assert_eq(activeCats[3].modules[2].id, "tca")

        assert_eq(activeCats[4].id, "guidance")
        assert_eq(activeCats[4].moduleCount, 1)
        assert_eq(activeCats[4].modules[1].id, "fcp")

        assert_eq(activeCats[5].id, "planning")
        assert_eq(activeCats[5].moduleCount, 1)
        assert_eq(activeCats[5].modules[1].id, "amm")

        -- Including empty categories returns all 6 layers including 4_mission
        local allCats = manifest.listCategories(true)
        assert_eq(#allCats, 6)
        assert_eq(allCats[6].id, "mission")
        assert_eq(allCats[6].moduleCount, 0)
        assert_deep_eq(manifest.listModulesByCategory("mission"), {})
        assert_deep_eq(manifest.listModulesByCategory("nonexistent"), {})
    end)
```

- [ ] **Step 2: Run the installer unit tests to verify RED failure**

Run: `python tools/run_unit_tests.py --target installer`
Expected: FAIL (`attempt to index field 'CATEGORY_ORDER' (a nil value)`).

- [ ] **Step 3: Implement category metadata and query functions in `manifest.lua` and sync `installer.lua` version**

In `src/0_development/installer/modules/manifest.lua`:
- Set `manifest.VERSION = "1.1.0"`.
- Define `manifest.CATEGORY_ORDER` and `manifest.CATEGORIES`.
- Implement `manifest.getCategory(categoryId)`, `manifest.listModulesByCategory(categoryId)`, and `manifest.listCategories(includeEmpty)`.
In `src/0_development/installer/installer.lua` and root `installer.lua`:
- Set `bootstrapper.VERSION = "1.1.0"` identically in both files.

- [ ] **Step 4: Run unit tests and 3-way manifest verifier to verify GREEN**

Run:
```powershell
python tools/run_unit_tests.py --target installer; if ($?) { python tools/verify_manifest_sync.py }
```
Expected: `0_development/installer` PASS and `verify_manifest_sync.py` `0 Errors, 0 Warnings`.

- [ ] **Step 5: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add installer.lua src/0_development/installer/installer.lua src/0_development/installer/modules/manifest.lua tests/0_development/installer/test_manifest_and_registry.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(installer): add domain category registry and grouping helpers in manifest (TASK-116-2)"
```

---

### Task 3: Implement 2-Level Category Folder TUI & Viewport Scrolling in `tui_view.lua` and `installer_app.lua` (`TASK-116-3`)

**Files:**
- Modify: `src/0_development/installer/modules/tui_view.lua:140-267`
- Modify: `src/0_development/installer/installer_app.lua:250-391`
- Modify: `tests/0_development/installer/test_installer_tui_and_app.lua:47-297`

**Interfaces:**
- Consumes:
  - `manifest.listCategories()`, `manifest.listModules()`
- Produces:
  - `tui_view.computeViewport(totalItems: number, selectedIndex: number, maxVisibleRows: number|nil, currentScrollOffset: number|nil) -> (number, number, number)`
    - Returns `(firstIdx, lastIdx, scrollOffset)` where `scrollOffset` is 0-based and `firstIdx .. lastIdx` is the 1-based inclusive visible slice of at most `maxVisibleRows` (default `12`) items containing `selectedIndex`.
  - `tui_view.renderCategoryMenu(termObj: table, categories: list<table>, selectedIndex: number, currentSource: string, installedMap: table|nil, scrollOffset: number|nil) -> number`
    - Renders header (`title = "Create: Aeronautics"`, `subtitle = "Select domain folder to browse"`, `contextLabel = "Folders"`).
    - Renders visible category rows on `y = 4 .. (h - 4)` formatted as `string.format("%s[DIR] %-13s %-16s [%d/%d inst]", prefix, catCode, catShort, instCount, totalCount)` and blanks remaining viewport rows up to `h - 4`.
    - Renders footer hints on `h - 2` (`" [Up/Down] Select   [Enter] Open Folder"`) and `h - 1` (`" [S] Toggle Source  [Q] Quit"`), blanks row `h`, and returns updated `scrollOffset`.
  - `tui_view.renderMenu(termObj: table, modules: list<table>, selectedIndex: number, currentSource: string, installedMap: table|nil, categoryInfo: table|nil, scrollOffset: number|nil) -> number`
    - When `categoryInfo` is provided, renders subtitle `"Folder: " .. tostring(categoryInfo.code or categoryInfo.id) .. " - " .. tostring(categoryInfo.name or "")` and `contextLabel = tostring(categoryInfo.code or categoryInfo.id)`.
    - Uses `computeViewport` to render visible modules onto `y = 4 .. (h - 4)`, blanks unoccupied rows in `4 .. (h - 4)`, displays scroll range on `h - 3` when `#modules > maxRows`, renders `[Bksp/B] Folders` hint on `h - 1` when `categoryInfo` is present, blanks row `h`, and returns updated `scrollOffset`.
  - `installer_app.run(opts)` interactive loop states:
    - Starts in `"CATEGORY_MENU"` (`categoryIndex = 1`, `categoryScroll = 0`).
    - In `"CATEGORY_MENU"`:
      - `Up` / `Down`: moves `categoryIndex` (`1 .. #categories`).
      - `Enter` (`28`, `156`, `keys.enter`, `keys.numPadEnter`) or `Right` (`205`, `keys.right`): enters `"MODULE_MENU"` for `categories[categoryIndex]` with `moduleIndex = 1`, `moduleScroll = 0`.
      - `S`: toggles source (`github` $\leftrightarrow$ `gdrive`).
      - `Q`: exits (`return true, nil`).
    - In `"MODULE_MENU"`:
      - `Up` / `Down`: moves `moduleIndex` (`1 .. #currentModules`).
      - `Enter`: transitions to `"CONFIRM_INSTALL"`.
      - `U`: transitions to `"CONFIRM_UNINSTALL"` if `installedMap[selectedMod.id]` exists, else sets warning `"Module is not installed"`.
      - `Backspace` (`14`, `keys.backspace`), `Left` (`203`, `keys.left`), or char `"b"`: returns to `"CATEGORY_MENU"` preserving `categoryIndex`.
      - `S`: toggles source (`github` $\leftrightarrow$ `gdrive`).
      - `Q`: exits (`return true, nil`).
    - In `"CONFIRM_INSTALL"` / `"CONFIRM_UNINSTALL"`:
      - Renders `"MODULE_MENU"` for the active category plus confirmation prompt on row `h`.
      - `Y`: executes install/uninstall, updates `installedMap`, returns to `"MODULE_MENU"`.
      - `N` / `Q` / `Backspace`: cancels and returns to `"MODULE_MENU"`.

- [ ] **Step 1: Write the failing unit tests in `tests/0_development/installer/test_installer_tui_and_app.lua`**

Update `tests/0_development/installer/test_installer_tui_and_app.lua` to test:
1. `"computes 12-row viewport window and scrolls smoothly when items exceed 12 rows"`:
   ```lua
   local f1, l1, s1 = tui_view.computeViewport(15, 1, 12, 0)
   assert_eq(f1, 1); assert_eq(l1, 12); assert_eq(s1, 0)

   local f2, l2, s2 = tui_view.computeViewport(15, 14, 12, s1)
   assert_eq(f2, 3); assert_eq(l2, 14); assert_eq(s2, 2)

   local f3, l3, s3 = tui_view.computeViewport(15, 15, 12, s2)
   assert_eq(f3, 4); assert_eq(l3, 15); assert_eq(s3, 3)

   local f4, l4, s4 = tui_view.computeViewport(15, 2, 12, s3)
   assert_eq(f4, 2); assert_eq(l4, 13); assert_eq(s4, 1)
   ```
2. `"renders category folder menu, clears ghost rows on folder transition, and scrolls >12 modules within 51x19 bounds"`:
   - Renders `tui_view.renderCategoryMenu(termColor, categories, 2, "github", { gps_server = { version = "2.2.0" }, gcs = { version = "1.0.0" } }, 0)`.
   - Verifies `[DIR] 0_infra`, `[2/6 inst]`, and `[Enter] Open Folder` appear on screen.
   - Renders `tui_view.renderMenu(termColor, categories[4].modules, 1, "github", {}, categories[4], 0)` (`2_guidance`, which has only 1 module `fcp`).
   - Asserts `termColor:_contains("FCP")` is `true` AND stale rows from the 5-row category screen (`"0_planning"`, `"3_planning"`, `"[2/6 inst]"`) are **no longer present** (`assert_false(termColor:_contains("3_planning"))`).
   - Creates a synthetic 15-module list (`MOD_01` .. `MOD_15`), calls `tui_view.renderMenu(termColor, syntheticMods, 15, "github", {}, { id = "infra", code = "0_infra", name = "Ground Infrastructure" }, 0)`, and asserts `MOD_15` is visible, `MOD_01` is scrolled off the top (`assert_false(termColor:_contains("MOD_01"))`), and `[4-15 of 15]` scroll indicator is shown.
3. `"drives 2-level interactive TUI folder navigation (Category -> Open Folder -> Install -> Backspace to Category -> Quit)"`:
   - Feeds synthetic events:
     - `{ "char", "s" }` (toggle to GDrive)
     - `{ "char", "s" }` (toggle back to GitHub)
     - `{ "key", 208 }` (Down to category #2 `0_infra`)
     - `{ "key", 208 }` (Down to category #3 `1_control`)
     - `{ "key", 28 }` (Enter `1_control` folder: modules are `[1] vas`, `[2] tca`)
     - `{ "key", 208 }` (Down to module #2 `tca`)
     - `{ "key", 28 }` (Enter to install `tca`)
     - `{ "char", "y" }` (Confirm install `tca`)
     - `{ "key", 14 }` (Backspace back to `CATEGORY_MENU`)
     - `{ "char", "q" }` (Quit from `CATEGORY_MENU`)
   - Asserts `ok == true`, `tca` is installed (`/main.lua`, `/startup/00_tca.lua`, `/.version.json`), and final rendered screen is back on `CATEGORY_MENU` showing `[1/2 inst]` for `1_control`!
4. `"supports uninstalling an installed module inside a category folder and navigating back via [B] key"`:
   - Pre-installs `gcs` in category #2 (`0_infra`), enters category #2 (`Down`, `Enter`), navigates down to `gcs` (index 6 in `0_infra`), presses `"u"`, confirms `"y"`, presses `"b"` to return to `CATEGORY_MENU`, and presses `"q"` to quit; asserts `meta.modules.gcs == nil`.

- [ ] **Step 2: Run installer unit tests to verify RED failure**

Run: `python tools/run_unit_tests.py --target installer`
Expected: FAIL (`attempt to call field 'computeViewport' (a nil value)`).

- [ ] **Step 3: Implement `computeViewport`, `renderCategoryMenu`, and updated `renderMenu` in `tui_view.lua` and 2-level state machine in `installer_app.lua`**

In `src/0_development/installer/modules/tui_view.lua`:
- Implement `tui_view.computeViewport(totalItems, selectedIndex, maxVisibleRows, currentScrollOffset)`.
- Implement `tui_view.renderCategoryMenu(termObj, categories, selectedIndex, currentSource, installedMap, scrollOffset)`.
- Update `tui_view.renderMenu(termObj, modules, selectedIndex, currentSource, installedMap, categoryInfo, scrollOffset)` to blank all unoccupied rows in `startY .. (h - 4)` and row `h`, render scroll range on `h - 3` when `#mods > maxRows`, and show `[Bksp/B] Folders` when `categoryInfo` is provided.
In `src/0_development/installer/installer_app.lua`:
- Update `installer_app.run(opts)` interactive TUI section to use `manifestMod.listCategories()` (falling back to a single synthetic category wrapping `manifestMod.listModules()` only if a custom test stub omits `listCategories`), starting in `"CATEGORY_MENU"` and handling transitions between `"CATEGORY_MENU"`, `"MODULE_MENU"`, `"CONFIRM_INSTALL"`, and `"CONFIRM_UNINSTALL"`.

- [ ] **Step 4: Run installer unit tests to verify GREEN**

Run: `python tools/run_unit_tests.py --target installer`
Expected: `[PASS]  0_development/installer` (all suites passed with zero UI auditor or instruction budget errors).

- [ ] **Step 5: Commit Task 3**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/installer/modules/tui_view.lua src/0_development/installer/installer_app.lua tests/0_development/installer/test_installer_tui_and_app.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(installer): implement 2-level category folder TUI and viewport scrolling (TASK-116-3)"
```

---

### Task 4: Full Pipeline Verification, Spec Promotion (`Approved` $\to$ `Implemented`), and Context Sync (`TASK-116-4`)

**Files:**
- Modify: `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md:8`
- Modify: `tools/verify_spec_status.py:16-35`
- Modify: `TASK.md:1-60,125-145`
- Modify: `GEMINI.md:1-50`
- Modify: `.agent/memory/workspace-root.md`

**Interfaces:**
- Consumes: All modified files from Tasks 1–3
- Produces:
  - `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` promoted to `Implemented` (`10 Implemented, 5 Approved` across 15 active specs)
  - Updated `TASK.md`, `GEMINI.md` ($\le 80$ lines), and `.agent/memory/workspace-root.md`

- [ ] **Step 1: Promote `INSTALLER_PROGRAM_SPECIFICATION.md` to `Implemented` and update `tools/verify_spec_status.py`**

In `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md`:
- Change `| **문서 상태 (Status)** | \`Approved\` |` to `| **문서 상태 (Status)** | \`Implemented\` |`.
In `tools/verify_spec_status.py`:
- Move `'docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md'` from `TARGET_APPROVED` to `TARGET_IMPLEMENTED` (10 Implemented, 5 Approved).

- [ ] **Step 2: Run the complete project verification suite**

Run:
```powershell
python tools/run_unit_tests.py --require-tests --clean-orphans; if ($?) { python tools/run_e2e_tests.py --clean-orphans }; if ($?) { python tools/run_mutation_tests.py }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }; if ($?) { python tools/verify_manifest_sync.py }; if ($?) { python tools/verify_all_specs.py --check-readmes }; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/validate_lua_syntax.py }
```
Expected:
- `run_unit_tests.py`: 12/12 targets PASS
- `run_e2e_tests.py`: 6/6 scenarios PASS
- `run_mutation_tests.py`: 20/20 KILLED (100.0%)
- `unittest`: 49/49 PASS
- `verify_manifest_sync.py`: `0 Errors, 0 Warnings`
- `verify_all_specs.py --check-readmes`: `ALL 15 SPECS 100% CLEAN (0 Errors, 0 Warnings)`
- `verify_spec_status.py`: `All 15 specs have valid statuses (10 Implemented, 5 Approved)`
- `validate_lua_syntax.py`: `126 files passed Lua 5.2 compilation`

- [ ] **Step 3: Sync `TASK.md`, `GEMINI.md`, and `.agent/memory/workspace-root.md`**

In `TASK.md`:
- Mark `TASK-116` (`TASK-116-1` .. `TASK-116-4`) as `[x]` and move to the top of `## ✅ 3. 완료된 작업 이력` (pruning the 11th oldest entry to keep 10 items).
In `GEMINI.md` (strictly $\le 80$ lines):
- Update `직전 완료` to `TASK-116`, update unit test count and spec count (`15대 사양서`, `10 Implemented, 5 Approved`).
In `.agent/memory/workspace-root.md`:
- Append the `TASK-116` milestone handover log with exact command outputs.

- [ ] **Step 4: Commit Task 4**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md tools/verify_spec_status.py TASK.md GEMINI.md .agent/memory/workspace-root.md docs/superpowers/plans/2026-11-10-task-116-installer-category-folder-tui.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "chore(installer): promote installer spec to Implemented and close TASK-116"
```
