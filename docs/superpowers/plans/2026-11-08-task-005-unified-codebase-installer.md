# Unified Codebase Installer (TASK-005) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the self-contained CC:Tweaked Unified Codebase Installer (`installer.lua` + `src/0_development/installer/`) supporting 3 deployment modes (direct root upload `/installer.lua`, floppy disk `/disk/installer.lua`, remote `wget run`), GitHub Raw & Google Drive dual download sources, `/.version.json` orphan cleanup, config-preserving deep-merge migration, and Zero-Fallback removal of legacy `src/0_infra/gps/installer.lua`.

**Architecture:** The installer codebase resides in `src/0_development/installer/` (paired 1:1 with `tests/0_development/installer/` for `tools/run_unit_tests.py --target installer` discovery), while an identical standalone bootstrapper `installer.lua` sits at the repository root for single-file upload, floppy copy, or `wget run`. To satisfy `skill-workflows.md` Spec Lifecycle Guardrails without Mixed-Scope violation, Task 1 revises `GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v2.1.0` → `v2.2.0`, `Implemented` → `Approved`) before any `src/` edits; Tasks 2–7 implement the installer modules and remove legacy GPS installer files via TDD; Task 8 runs the full verification suite and promotes `GPS_PROGRAM_SPECIFICATION_AND_ICD.md` back to `Implemented`.

**Tech Stack:** CC:Tweaked 1.109+ Lua 5.2 (Cobalt VM), CraftOS APIs (`fs`, `http`, `term`, `textutils`, `colors`, `keys`, `cc.require`), CraftOS-PC headless unit test harness (`tools/run_unit_tests.py`), Python 3.12 `unittest`.

**Spec:**
- Roadmap SSOT: `TASK.md` (`TASK-005` / `TASK-005-1`..`TASK-005-7`)
- Master ICD: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`
- GPS Specification (Section 9): `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`
- Baseline Design Reference: `docs/superpowers/plans/2026-11-07-unified-codebase-installer.md` (superseded by this `2026-11-08` execution plan)
- Rules: `.agent/rules/cc-tweaked-runtime.md`, `.agent/rules/domain-aeronautics.md`, `.agent/rules/skill-workflows.md`

## Global Constraints

- **Lua 5.2 Cobalt Compatibility (`.agent/rules/cc-tweaked-runtime.md`)**: Zero Lua 5.3+ operators (`//`, `&`, `|`, `~` unary/binary bitwise, `<<`, `>>`), zero `getfenv`/`setfenv`, zero disabled host OS calls (`os.execute`, `os.remove`, `os.rename`, `os.exit`, `io.popen`). Use `fs.*` exclusively.
- **Valkyrien Skies Ban (`.agent/rules/domain-aeronautics.md`)**: Zero `valkyrien`, `vs2`, `cc_vs`, `ship` peripheral, or `kontraption:` identifiers in code, comments, or strings.
- **Harness UI & Log Compatibility (`harness/unit/guest/runner_lib.lua`)**: Never call `_G.printError` (the test runner hooks `printError` into fatal target errors); render all error banners via `term` methods. Every `term.blit(text, fg, bg)` must maintain `#text == #fg == #bg`, and `term.setCursorPos(x, y)` must pass numeric coordinates within `51x19`.
- **Harness Event-Swallow Discipline**: Interactive loops must accept injectable `opts.pullEvent` (defaulting to `os.pullEvent`), `opts.http` (`_G.http`), `opts.fs` (`_G.fs`), and `opts.term` (`_G.term`) so unit tests run synchronously under `forbid_event_swallow = true` and `< 50,000` instructions per `it(...)` block.
- **3 Deployment Contexts**: Direct root `/installer.lua`, floppy disk `/disk/installer.lua` (or `/disk2/...`), and ephemeral `wget run https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/installer.lua` must all install strictly to computer root `/` (`targetRoot`, default `"/"`).
- **Dual Download Sources**:
  - `github`: `"https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/" .. repoPath`
  - `gdrive`: `"https://drive.usercontent.google.com/download?id=" .. fileId .. "&export=download&confirm=t"` (with optional `/gdrive_ids.json` override map)
- **Version Metadata SSOT (`TASK.md`)**: Default metadata registry path is `"/.version.json"`.
- **Zero-Fallback & Spec Lifecycle (`GEMINI.md`, `skill-workflows.md`)**: Delete `src/0_infra/gps/installer.lua` and `src/0_infra/gps/modules/installer_core.lua` completely with no fallback shim; mark legacy GPS installer `[DEPRECATED]` in `GPS_PROGRAM_SPECIFICATION_AND_ICD.md`; transition `GPS` spec `Implemented` → `Approved` before `src/` edits and `Approved` → `Implemented` after verification passes.
- **Overclaim Ban (`AGENTS.md`)**: No unmeasured superlative claims in code comments, TUI strings, specs, or commit messages.
- **Windows Git Binary Path**: Use `& "C:\Program Files\Git\cmd\git.exe"` in PowerShell commands.

## Review Focus

1. **Floppy disk execution (`/disk/installer.lua` or `/disk2/installer.lua`) polluting `/disk` instead of computer root `/`**: Running from any `/disk*/` mount must write module files, configs, `/startup/00_<id>.lua`, and `/.version.json` strictly under `targetRoot` (`/`), never inside `/disk*/`, and must never delete `/disk*/installer.lua` (tested in Task 6 `test_bootstrapper.lua`).
2. **Generated `/startup/00_<id>.lua` hook failing on vanilla CraftOS `cc.require` when `main.lua` calls bare `require("<submod>")` or when `fcp` requires `--daemon`**: Startup hooks must construct a `cc.require.make` environment extending `package.path` with `modules/`, `modules/drivers/`, `hal/`, `tools/`, and `/apis/`, and forward module CLI arguments such as `{"--daemon"}` for `fcp` (tested in Task 3 `test_migration_and_startup.lua`).
3. **Google Drive HTTP 302/303 redirect chains with lowercase `location` headers, redirect loops, or unconfigured `gdriveId` (`nil`)**: `manifest.resolveUrl` must return `nil, "GDRIVE_ID_UNCONFIGURED"` cleanly when no ID is mapped, and `downloader.fetchString` must follow up to 5 redirects case-insensitively, close intermediate HTTP handles, and reject redirect loops `> 5` (tested in Task 2 `test_manifest_and_registry.lua` and Task 4 `test_downloader.lua`).
4. **Mid-batch network failure leaving `.tmp` remnants, corrupting working installations, or triggering premature orphan deletion**: `downloader.downloadBatch` must stage the entire batch into `<targetRoot>/.installer_stage` before committing to final destinations, and `installer_app.installModule` must abort before orphan removal or `/.version.json` save if any file fails (tested in Task 4 `test_downloader.lua` and Task 5 `test_installer_tui_and_app.lua`).
5. **Reinstall/upgrade overwriting nested user JSON settings (`channels`, `position`, `ports`) or deleting files owned by co-installed modules (e.g., `fcp` + `gps_client` or shared `/gps/modules/protocol.lua`)**: `migration_engine.deepMerge` must recursively preserve user leaf values at depth $\ge 3$ while backfilling missing keys, and `version_registry.getOrphanFiles` must exclude any path still owned by another module in `/.version.json` (tested in Task 2 `test_manifest_and_registry.lua` and Task 3 `test_migration_and_startup.lua`).

---

## File Structure

- `installer.lua` — Repository-root standalone self-bootstrapping entrypoint (byte-identical to `src/0_development/installer/installer.lua`).
- `src/0_development/installer/main.lua` — Standard codebase entrypoint delegating to `require("installer").bootstrapAndRun`.
- `src/0_development/installer/installer.lua` — 3-mode context detector (`direct_root`, `disk`, `remote_wget`), local-core vs `/.installer_cache` remote bootstrapper.
- `src/0_development/installer/installer_app.lua` — Programmatic `installModule` / `uninstallModule` pipeline controller and interactive `51x19` TUI event loop.
- `src/0_development/installer/modules/manifest.lua` — Declarative registry of the 7 installable modules (`vas`, `tca`, `fcp`, `alignment`, `gps_server`, `gps_node`, `gps_client`), bootstrap file list, and GitHub/Google Drive URL resolver.
- `src/0_development/installer/modules/version_registry.lua` — Atomic `/.version.json` reader/writer and multi-module-safe orphan file calculator.
- `src/0_development/installer/modules/migration_engine.lua` — Arbitrary-depth non-destructive JSON config merger and atomic file migrator.
- `src/0_development/installer/modules/startup_generator.lua` — `/startup/00_<id>.lua` multi-boot hook generator with `cc.require` `package.path` injection.
- `src/0_development/installer/modules/downloader.lua` — HTTP adapter supporting GitHub Raw & Google Drive redirects, atomic `.tmp` writes, and staged batch commits.
- `src/0_development/installer/modules/tui_view.lua` — `51x19` CC:Tweaked terminal renderer (header, module menu, `[S]` source badge, progress bar, status banner; color & monochrome safe).
- `tests/0_development/installer/test_manifest_and_registry.lua` — Unit tests for `manifest` and `version_registry`.
- `tests/0_development/installer/test_migration_and_startup.lua` — Unit tests for `migration_engine` and `startup_generator`.
- `tests/0_development/installer/test_downloader.lua` — Unit tests for `downloader` (GitHub, GDrive 302 redirects, HTML interstitial rejection, staged rollback).
- `tests/0_development/installer/test_installer_tui_and_app.lua` — Unit tests for `tui_view` and `installer_app` end-to-end orchestration.
- `tests/0_development/installer/test_bootstrapper.lua` — Unit tests for `installer.lua` 3-mode detection, `/disk` isolation, and `/.installer_cache` cleanup.
- `tests/harness/test_installer_integrity.py` — Python regression test pinning root `installer.lua` byte parity, Lua 5.2 static guard compliance, manifest `repoPath` existence on disk, and legacy GPS installer absence.
- Modified/Deleted in existing targets & docs:
  - Modify: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`
  - Delete: `src/0_infra/gps/installer.lua`, `src/0_infra/gps/modules/installer_core.lua`
  - Modify: `src/0_infra/gps/main.lua`, `src/0_infra/gps/hal/gps_client.lua`, `tests/0_infra/gps/test_gps_core.lua`
  - Modify: `TASK.md`, `GEMINI.md`, `README.md`, `src/README.md`

---

### Task 1: Spec-First Revision of GPS Specification (`v2.1.0` → `v2.2.0`, `Implemented` → `Approved`)

**Files:**
- Modify: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`

**Interfaces:**
- Consumes: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v2.1.0`), `.agent/skills/specification-lifecycle-manager/SKILL.md`
- Produces: `Approved` GPS specification (`v2.2.0`) authorizing `src/0_infra/gps/installer.lua` & `installer_core.lua` removal and Unified Installer replacement

- [ ] **Step 1: Read `specification-lifecycle-manager` skill instructions and inspect GPS spec target lines**

Read `.agent/skills/specification-lifecycle-manager/SKILL.md` and inspect lines 1–35, 65–75, 145–155, and 1000–1105 of `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`. Do NOT touch any `.lua` file in this task.

- [ ] **Step 2: Update `GPS_PROGRAM_SPECIFICATION_AND_ICD.md` metadata, Revision History, and Section 9**

Apply the following exact specification updates in `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`:
1. Top Metadata Table:
   - `문서 상태 (Status)`: `` `Implemented` `` → `` `Approved` ``
   - `문서 버전 (Version)`: `` `v2.1.0` `` → `` `v2.2.0` ``
   - `최종 수정일 (Date)`: `` `2026-11-08` ``
2. `Revision History` table: prepend row for `` `v2.2.0` `` (`2026-11-08`) documenting `[DEPRECATED]` retirement of standalone `gps/installer.lua` & `installer_core.lua` and integration into the repository-wide Unified Codebase Installer (`installer.lua` / `src/0_development/installer/`) supporting direct upload, `/disk/installer.lua`, `wget run`, GitHub/Google Drive dual sources, and `/.version.json`.
3. Section 1.1 item 10 (line ~69) and Section 3.1 note (line ~148): replace active `gps/installer.lua` references with Unified Installer `installer.lua` (`gps_server`, `gps_node`, `gps_client` targets; mark `gps/installer.lua` `[DEPRECATED]`).
4. Section 9 (`## 9. 통합 코드베이스 인스톨러 배포 및 파일 패키징 규격`) & Section 11 row (line ~1102):
   - Remove `installer_core.lua` and `installer.lua` from the active `src/0_infra/gps/` tree diagram (noting `구 gps/installer.lua, gps/modules/installer_core.lua [DEPRECATED — Zero-Fallback 제거]`).
   - Document the 3 deployment paths (`/installer.lua`, `/disk/installer.lua`, `wget run .../installer.lua`), dual sources (`GitHub Raw` / `Google Drive` toggled via `[S]`), `/.version.json` metadata tracking, and the 3 GPS bundle roles (`gps_server` → `/gps/server.lua` + `/startup/00_gps.lua`, `gps_node` → `/gps/node.lua` + `/startup/00_gps.lua` preserving `/gps_data/node.json` & `/gps_data/node_cfg.json`, `gps_client` → `/apis/gps_client.lua` + `/gps/modules/{client_core,protocol}.lua`).
   - Do NOT include executable runtime implementation code blocks in Section 9 (declarative tables and directory/CLI layouts only, per `skill-workflows.md` and `no-overclaim`).

- [ ] **Step 3: Verify specification integrity**

Run: `python scratch/verify_all_specs.py`
Expected: `SCAN RESULT: ALL 12 SPECS 100% CLEAN (0 Errors, 0 Warnings)` with `GPS_PROGRAM_SPECIFICATION_AND_ICD.md` showing `(Status: Approved, Version: v2.2.0, Date: 2026-11-08)`.

- [ ] **Step 4: Commit Spec-First update**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(gps): revise installer spec to unified installer v2.2.0 (Approved)"
```

---

### Task 2: Declarative Dual-Source Manifest & Version Registry (`TASK-005-1`)

**Files:**
- Create: `src/0_development/installer/modules/manifest.lua`
- Create: `src/0_development/installer/modules/version_registry.lua`
- Create: `tests/0_development/installer/test_manifest_and_registry.lua`

**Interfaces:**
- Consumes: CC:Tweaked `fs` and `textutils` APIs
- Produces:
  - `manifest.VERSION = "1.0.0"`
  - `manifest.SOURCES = { GITHUB = "github", GDRIVE = "gdrive" }`
  - `manifest.BASE_URLS = { github = "https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/", gdrive = "https://drive.usercontent.google.com/download?id=" }`
  - `manifest.BOOTSTRAP_FILES`: ordered list of 7 `{ repoPath, cacheRelPath, gdriveId }` entries (`installer_app.lua` + 6 files under `modules/`)
  - `manifest.MODULE_ORDER = { "vas", "tca", "fcp", "alignment", "gps_server", "gps_node", "gps_client" }`
  - `manifest.MODULES`: table keyed by module ID (`id`, `name`, `category`, `version`, `installDir`, `files`, `startup`, `defaultConfigs`)
  - `manifest.getModule(id) -> table|nil`
  - `manifest.listModules() -> list<table>`
  - `manifest.resolveUrl(sourceType, fileEntry, gdriveOverrides) -> (string|nil, string|nil)`
  - `version_registry.DEFAULT_META_PATH = "/.version.json"`
  - `version_registry.load(metaPath, fsApi) -> table`
  - `version_registry.save(metaPath, meta, fsApi) -> (boolean, string|nil)`
  - `version_registry.getOrphanFiles(meta, moduleId, newDestList) -> list<string>`
  - `version_registry.recordInstall(meta, moduleId, version, destList, sourceUsed, timestampMs) -> table`
  - `version_registry.removeModule(meta, moduleId) -> list<string>`

- [ ] **Step 1: Write the failing unit tests in `tests/0_development/installer/test_manifest_and_registry.lua`**

Create `tests/0_development/installer/test_manifest_and_registry.lua` covering:
```lua
local manifest = require("manifest")
local version_registry = require("version_registry")

describe("manifest dual-source module definitions", function()
    it("registers all 7 modules in deterministic order with valid production file mappings", function()
        local list = manifest.listModules()
        assert_eq(#list, 7)
        assert_eq(list[1].id, "vas")
        assert_eq(list[2].id, "tca")
        assert_eq(list[3].id, "fcp")
        assert_eq(list[4].id, "alignment")
        assert_eq(list[5].id, "gps_server")
        assert_eq(list[6].id, "gps_node")
        assert_eq(list[7].id, "gps_client")

        local fcp = manifest.getModule("fcp")
        assert_eq(fcp.installDir, "/")
        assert_true(fcp.startup.enabled)
        assert_eq(fcp.startup.path, "/startup/00_fcp.lua")
        assert_eq(fcp.startup.args[1], "--daemon")

        local gpsClient = manifest.getModule("gps_client")
        assert_false(gpsClient.startup.enabled)
    end)

    it("resolves GitHub raw URLs and handles configured vs unconfigured Google Drive IDs", function()
        local entry = { repoPath = "src/1_control/vas/main.lua", dest = "/main.lua", gdriveId = nil }
        local ghUrl, ghErr = manifest.resolveUrl("github", entry)
        assert_nil(ghErr)
        assert_eq(ghUrl, "https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/src/1_control/vas/main.lua")

        local gdNil, gdErr = manifest.resolveUrl("gdrive", entry)
        assert_nil(gdNil)
        assert_eq(gdErr, "GDRIVE_ID_UNCONFIGURED")

        local gdOk, gdOkErr = manifest.resolveUrl("gdrive", entry, { ["src/1_control/vas/main.lua"] = "1AbCdEfGhIjKlMnOp" })
        assert_nil(gdOkErr)
        assert_eq(gdOk, "https://drive.usercontent.google.com/download?id=1AbCdEfGhIjKlMnOp&export=download&confirm=t")
    end)
end)

describe("version_registry /.version.json persistence and multi-module orphan safety", function()
    it("saves atomically, detects single-module orphans, and protects files shared with co-installed modules", function()
        local metaPath = sdk.temp_path(".version.json")
        local meta = version_registry.load(metaPath)
        assert_deep_eq(meta.modules, {})

        version_registry.recordInstall(meta, "gps_server", "2.2.0", {
            "/gps/server.lua",
            "/gps/modules/protocol.lua",
            "/gps/modules/old_legacy.lua",
        }, "github", 1000)
        version_registry.recordInstall(meta, "gps_client", "2.2.0", {
            "/apis/gps_client.lua",
            "/gps/modules/protocol.lua",
        }, "github", 1005)

        local okSave = version_registry.save(metaPath, meta)
        assert_true(okSave)

        local reloaded = version_registry.load(metaPath)
        -- Upgrading gps_server drops protocol.lua and old_legacy.lua from gps_server's list,
        -- but protocol.lua is still owned by gps_client so ONLY old_legacy.lua may be orphaned!
        local orphans = version_registry.getOrphanFiles(reloaded, "gps_server", { "/gps/server.lua" })
        assert_deep_eq(orphans, { "/gps/modules/old_legacy.lua" })
    end)

    it("isolates per-module file lists in /.version.json when co-installing gps_client alongside fcp", function()
        local meta = version_registry.load("/_nonexistent_version.json")
        version_registry.recordInstall(meta, "fcp", "1.11.0", { "/main.lua", "/fcp_runtime.lua" }, "github", 2000)
        local clientOrphans = version_registry.getOrphanFiles(meta, "gps_client", { "/apis/gps_client.lua" })
        assert_deep_eq(clientOrphans, {})
        local removable = version_registry.removeModule(meta, "fcp")
        assert_deep_eq(removable, { "/fcp_runtime.lua", "/main.lua" })
    end)
end)
```

- [ ] **Step 2: Run unit test runner to verify RED failure**

Run: `python tools/run_unit_tests.py --target installer`
Expected: FAIL (`module 'manifest' not found`).

- [ ] **Step 3: Implement `src/0_development/installer/modules/manifest.lua` and `version_registry.lua`**

Implement `manifest.lua` and `version_registry.lua` matching the exact `Interfaces` block above:
- Map the exact production files (excluding simulation-only `node_*_sim.lua` / mock `node_*.lua` files and excluding deprecated `gps/installer.lua` & `gps/modules/installer_core.lua`):
  - `vas` (`installDir = "/"`): `main.lua` + all 15 files in `src/1_control/vas/modules/*.lua`; `startup = { enabled = true, path = "/startup/00_vas.lua", target = "/main.lua", name = "VAS" }`; `defaultConfigs` for `/config/system.json` (`aircraftIndexN = 1`, `baseChannel = 10000`, `bandwidth = 40`).
  - `tca` (`installDir = "/"`): `main.lua`, `tools/tca_setup.lua`, + all 10 files in `src/1_control/tca/modules/*.lua`; `startup = { enabled = true, path = "/startup/00_tca.lua", target = "/main.lua", name = "TCA" }`; `defaultConfigs` for `/config.json` (`schemaVersion = "1.2.0"`, `groupId = "THR_MAIN_L"`, `interactionMode = "REDSTONE"`, `aircraftIndexN = 1`, `baseChannel = 10000`, `channels = { thrustActuation = 10010 }`, `watchdogTimeoutMs = 300`, `nominalActuatorCount = 4`, `aircraftDomainId = "AIRCRAFT_01"`, `ports = { modemSide = "top", redstoneSide = "bottom", apiSides = { "left", "right", "front", "back" } }`, `deadband = 0`).
  - `fcp` (`installDir = "/"`): `main.lua`, `fcp_runtime.lua`, all 11 files in `src/2_guidance/fcp/modules/*.lua`, and all 3 files in `src/2_guidance/fcp/modules/drivers/*.lua`; `startup = { enabled = true, path = "/startup/00_fcp.lua", target = "/main.lua", args = { "--daemon" }, name = "FCP" }`; `defaultConfigs` for `/config/fcp_config.json` (`system = { domainId = "AIRCRAFT_01", hardwareUuid = "FCP-04", airframeType = "VECTORED_VTOL", loopFrequencyHz = 20, primaryModemSide = "top", infraModemSide = "back" }`, `channels = { bootstrapChannel = 50000, baseChannel = 10000, bandwidth = 40, mfdInstrumentChannel = 10003, facilityBeaconChannel = 50003, atcCommChannel = 50001, gpsPingChannel = 60001, gpsServiceChannel = 60002 }`).
  - `alignment` (`installDir = "/"`): `main.lua` + all 10 files in `src/0_development/alignment/modules/*.lua`; `startup = { enabled = true, path = "/startup/00_alignment.lua", target = "/main.lua", name = "Alignment" }`; `defaultConfigs` for `/config.json` (`station` Bay 1 `101..104` + `safety`).
  - `gps_server` (`installDir = "/gps"`): `main.lua`, `server.lua`, `hal/storage_hal.lua`, `modules/{config_store,monitor_ui,protocol,radar_math,session_scheduler,trilateration}.lua` mapped under `/gps/...`; `startup = { enabled = true, path = "/startup/00_gps.lua", target = "/gps/server.lua", name = "GPS Server" }`; `defaultConfigs` for `/gps_data/nodes.json` (`{ version = "1.9.5", nodes = {} }`).
  - `gps_node` (`installDir = "/gps"`): `main.lua`, `node.lua`, `hal/{storage_hal,wizard_cli}.lua`, `modules/{commissioning,config_store,protocol}.lua` mapped under `/gps/...`; `startup = { enabled = true, path = "/startup/00_gps.lua", target = "/gps/node.lua", name = "GPS Node" }`; `defaultConfigs` for `/gps_data/node_cfg.json` (`role = "NODE"`, `channels = { ping = 60001, service = 60002, nodeIn = 60003, mgmt = 60004 }`, `networkKey = "GPS_BASE_NET"`, `heartbeatSec = 10`, `position = { x = 0, y = 0, z = 0 }`).
  - `gps_client` (`installDir = "/gps"`): `/apis/gps_client.lua` (`src/0_infra/gps/hal/gps_client.lua`), `/gps/client_entry.lua` (`src/0_infra/gps/client_entry.lua`), `/gps/modules/client_core.lua`, `/gps/modules/protocol.lua`; `startup = { enabled = false }`; `defaultConfigs = {}`.
- `BOOTSTRAP_FILES`: lists `src/0_development/installer/installer_app.lua` and the 6 files in `src/0_development/installer/modules/*.lua`.
- Sort returned file lists deterministically (`table.sort`) in `getOrphanFiles` and `removeModule`.

- [ ] **Step 4: Run unit test runner to verify GREEN**

Run: `python tools/run_unit_tests.py --target installer`
Expected: `[PASS]  0_development/installer` (4/4 passed).

- [ ] **Step 5: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/installer/modules/manifest.lua src/0_development/installer/modules/version_registry.lua tests/0_development/installer/test_manifest_and_registry.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(installer): add dual-source manifest and /.version.json registry"
```

---

### Task 3: Config Deep-Merge Migration Engine & Multi-Boot Startup Hook Generator (`TASK-005-2`)

**Files:**
- Create: `src/0_development/installer/modules/migration_engine.lua`
- Create: `src/0_development/installer/modules/startup_generator.lua`
- Create: `tests/0_development/installer/test_migration_and_startup.lua`

**Interfaces:**
- Consumes: CC:Tweaked `fs`, `textutils`, `cc.require`
- Produces:
  - `migration_engine.deepMerge(existingConfig, defaultConfig) -> table`
  - `migration_engine.migrateFile(filePath, defaultConfig, fsApi) -> (boolean, table|nil, string|nil)`
  - `startup_generator.resolveTargetPath(targetRoot, relOrAbsPath) -> string`
  - `startup_generator.generateHookContent(spec) -> string`
  - `startup_generator.installHook(spec, targetRoot, fsApi) -> (boolean, string|nil)`
  - `startup_generator.removeHook(hookPath, targetRoot, fsApi) -> boolean`

- [ ] **Step 1: Write the failing unit tests in `tests/0_development/installer/test_migration_and_startup.lua`**

Create `tests/0_development/installer/test_migration_and_startup.lua` testing:
1. `"recursively preserves nested user overrides at depth >= 3 while backfilling missing keys"`: merges existing `{ channels = { baseChannel = 10040 }, ports = { apiSides = { "front" } } }` with defaults `{ channels = { baseChannel = 10000, bandwidth = 40, gpsPingChannel = 60001 }, ports = { modemSide = "top", apiSides = { "left", "right" } } }`; asserts `baseChannel == 10040`, `bandwidth == 40`, `gpsPingChannel == 60001`, `modemSide == "top"`, `apiSides` equals `{ "front" }` (arrays are not corrupted by index merging), and neither input table was mutated.
2. `"migrates missing and existing JSON config files atomically"`: tests `migrateFile` creating a new JSON file and preserving customized keys on second run without leaving `.tmp` files.
3. `"executes generated startup hook with bare submodule require and forwards daemon args"`: stages a miniature target root `/_tmp/boot_root` containing `/_tmp/boot_root/modules/sub_helper.lua` (`return { tag = "OK_SUB" }`) and `/_tmp/boot_root/main.lua` (`local h = require("sub_helper"); local a = {...}; _G.__BOOT_TEST_OUT = h.tag .. ":" .. tostring(a[1])`), calls `startup_generator.installHook({ path = "/startup/00_fcp.lua", name = "FCP", target = "/_tmp/boot_root/main.lua", installDir = "/_tmp/boot_root", args = { "--daemon" } }, "/_tmp/boot_root")`, verifies `/_tmp/boot_root/startup/00_fcp.lua` exists while sibling `/_tmp/boot_root/startup.lua` is untouched, runs `dofile("/_tmp/boot_root/startup/00_fcp.lua")`, and asserts `_G.__BOOT_TEST_OUT == "OK_SUB:--daemon"`.

- [ ] **Step 2: Run unit tests to verify RED failure**

Run: `python tools/run_unit_tests.py --target installer`
Expected: FAIL (`module 'migration_engine' not found`).

- [ ] **Step 3: Implement `migration_engine.lua` and `startup_generator.lua`**

Implement both modules:
- `isArray(t)`: returns `true` when `type(t) == "table"` and `#t > 0` with all keys integer `1..#t`, so user array overrides (e.g. `apiSides`) replace default arrays cleanly instead of leaving trailing default elements.
- `generateHookContent(spec)`: emits pure Lua 5.2 code using `pcall(require, "cc.require")` + `cc_req.make(env, installDir)` (falling back to `_ENV` `package`/`require`) and prepending `<installDir>/?.lua;<installDir>/?/init.lua;<installDir>/modules/?.lua;<installDir>/modules/drivers/?.lua;<installDir>/hal/?.lua;<installDir>/tools/?.lua;/apis/?.lua;` to `env.package.path`, then calling `loadfile(target, nil, env)` with serialized `args` (`"--daemon"`, etc.). Do NOT emit `printError(...)` inside the hook.

- [ ] **Step 4: Run unit tests to verify GREEN**

Run: `python tools/run_unit_tests.py --target installer`
Expected: `[PASS]  0_development/installer` (all suites passed).

- [ ] **Step 5: Commit Task 3**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/installer/modules/migration_engine.lua src/0_development/installer/modules/startup_generator.lua tests/0_development/installer/test_migration_and_startup.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(installer): add deep-merge config migrator and multi-boot hook generator"
```

---

### Task 4: Atomic HTTP Downloader with Dual-Source & Staged Batch Rollback (`TASK-005-3`)

**Files:**
- Create: `src/0_development/installer/modules/downloader.lua`
- Create: `tests/0_development/installer/test_downloader.lua`

**Interfaces:**
- Consumes: `manifest.resolveUrl`, CC:Tweaked `http` & `fs` APIs
- Produces:
  - `downloader.MAX_REDIRECTS = 5`
  - `downloader.checkHttpAvailable(httpApi) -> (boolean, string|nil)`
  - `downloader.fetchString(url, opts) -> (string|nil, string|nil)`
  - `downloader.downloadFileAtomic(url, destPath, opts) -> (boolean, string|nil)`
  - `downloader.downloadBatch(sourceType, fileEntries, opts) -> (boolean, list<string>|nil, string|nil)`

- [ ] **Step 1: Write the failing unit tests in `tests/0_development/installer/test_downloader.lua`**

Create `tests/0_development/installer/test_downloader.lua` testing:
1. `"reports HTTP_DISABLED gracefully when http API is nil"`: `checkHttpAvailable(nil)` returns `false, "HTTP_DISABLED"`.
2. `"follows 302 lowercase location redirects, closes intermediate handles, and rejects redirect loops"`: mock `http.get` returning 302 with `{ location = "https://doc-01.googleusercontent.com/final" }` -> 200 `"return { ok = true }"`, asserting intermediate `close()` was called and body matches; plus cyclic 302 loop returning `nil, "TOO_MANY_REDIRECTS"` after 5 hops; plus Google Drive HTML quota/sign-in interstitial (`"<!DOCTYPE html><html><title>Google Drive - Quota exceeded</title></html>"`) returning `nil, "GDRIVE_HTML_INTERSTITIAL"`.
3. `"cleans up .tmp file and preserves existing destination file on mid-download failure"`: pre-populates `dest` with `"OLD_WORKING"`, simulates HTTP 500 failure, asserts `dest` still contains `"OLD_WORKING"` and `dest .. ".tmp"` does not exist.
4. `"stages batch in /.installer_stage and rolls back entire batch if final file fails"`: 3-file batch where file #3 fails HTTP 404; asserts files #1 and #2 at target root retain their pre-upgrade content, `/.installer_stage` is deleted, and `onProgress` received `(1, 3, ...)` and `(2, 3, ...)`.

- [ ] **Step 2: Run unit tests to verify RED failure**

Run: `python tools/run_unit_tests.py --target installer`
Expected: FAIL (`module 'downloader' not found`).

- [ ] **Step 3: Implement `src/0_development/installer/modules/downloader.lua`**

Implement `downloader.lua`:
- `fetchString(url, opts)`: tracks `hops = 0 .. maxRedirects`, checks `resp.getResponseCode()` if present (`301/302/303/307/308` -> look up `headers["Location"] or headers["location"]`, close `resp`, repeat), closes `resp` before returning body, rejects Google Drive HTML interstitials (`url:find("drive%.")` or `url:find("googleusercontent")` when trimmed body starts with `<!DOCTYPE html` or `<html` — if `uuid=` & `confirm=` can be extracted once and retried, retry once; otherwise return `nil, "GDRIVE_HTML_INTERSTITIAL"`).
- `downloadBatch(sourceType, fileEntries, opts)`:
  1. Resolve all URLs upfront via `(opts.manifest or require("manifest")).resolveUrl(sourceType, entry, opts.gdriveOverrides)`; fail immediately with `false, nil, err` before touching disk if any URL fails resolution.
  2. Download every file via `downloadFileAtomic` into `<targetRoot>/.installer_stage<entry.dest>`, invoking `opts.onProgress(idx, #fileEntries, entry.dest)`.
  3. On any download error, `fs.delete("<targetRoot>/.installer_stage")` and return `false, nil, err`.
  4. Once all files are staged, atomically replace each `<targetRoot><entry.dest>` from its staged file, delete `<targetRoot>/.installer_stage`, and return `true, installedDestList, nil`.

- [ ] **Step 4: Run unit tests to verify GREEN**

Run: `python tools/run_unit_tests.py --target installer`
Expected: `[PASS]  0_development/installer` (all suites passed).

- [ ] **Step 5: Commit Task 4**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/installer/modules/downloader.lua tests/0_development/installer/test_downloader.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(installer): add dual-source atomic HTTP downloader with staged batch commit"
```

---

### Task 5: `51x19` Terminal TUI View & Main Installer Application Controller (`TASK-005-4`)

**Files:**
- Create: `src/0_development/installer/modules/tui_view.lua`
- Create: `src/0_development/installer/installer_app.lua`
- Create: `tests/0_development/installer/test_installer_tui_and_app.lua`

**Interfaces:**
- Consumes: `manifest`, `version_registry`, `migration_engine`, `startup_generator`, `downloader`
- Produces:
  - `tui_view.toggleSource(currentSource) -> string`
  - `tui_view.renderHeader(termObj, title, subtitle, currentSource, contextLabel)`
  - `tui_view.renderMenu(termObj, modules, selectedIndex, currentSource, installedMap)`
  - `tui_view.renderProgress(termObj, cur, total, currentPath, currentSource)`
  - `tui_view.renderMessage(termObj, level, message)`
  - `installer_app.installModule(moduleId, opts) -> (boolean, table|nil, string|nil)`
  - `installer_app.uninstallModule(moduleId, opts) -> (boolean, string|nil)`
  - `installer_app.run(opts) -> (boolean, string|nil)`

- [ ] **Step 1: Write the failing unit tests in `tests/0_development/installer/test_installer_tui_and_app.lua`**

Create `tests/0_development/installer/test_installer_tui_and_app.lua` testing:
1. `"renders header, 7-module menu, progress bar, and source toggle within 51x19 bounds"`: uses `mock.term(51, 19)` (both color `isColor() == true` and monochrome `isColor() == false`), verifies `toggleSource("github") == "gdrive"` and `toggleSource("gdrive") == "github"`, verifies rendered screen contains `[GitHub]` / `[GDrive]` and all 7 module names with zero UI auditor violations.
2. `"installs module end-to-end, preserves user config, writes startup hook, cleans orphans, and updates /.version.json"`: runs `installer_app.installModule("tca", { targetRoot = "/_tmp/app_root", source = "github", http = mockHttp })` with pre-existing `/_tmp/app_root/config.json` (`groupId = "THR_CUSTOM_R"`), pre-existing `/_tmp/app_root/.version.json` listing orphan `"/modules/legacy_old.lua"`, and pre-existing `"/modules/legacy_old.lua"` on disk; verifies all TCA files downloaded, `groupId == "THR_CUSTOM_R"` preserved while `channels.thrustActuation == 10010` backfilled, `/startup/00_tca.lua` created, `legacy_old.lua` deleted, and `/.version.json` updated.
3. `"aborts before orphan cleanup or registry update when downloadBatch fails"`: simulates HTTP error during upgrade; verifies pre-existing `legacy_old.lua` and `/.version.json` remain untouched.
4. `"drives interactive TUI key sequence ([S] toggle -> [S] toggle -> select -> Enter -> [Q] quit)"`: feeds synthetic events via `opts.pullEvent` (`{ "char", "s" }`, `{ "char", "s" }`, `{ "key", 208 }`, `{ "key", 28 }`, `{ "char", "y" }`, `{ "char", "q" }`) and verifies clean exit without event-swallow errors.

- [ ] **Step 2: Run unit tests to verify RED failure**

Run: `python tools/run_unit_tests.py --target installer`
Expected: FAIL (`module 'tui_view' not found`).

- [ ] **Step 3: Implement `tui_view.lua` and `installer_app.lua`**

Implement `tui_view.lua` and `installer_app.lua`:
- Truncate/pad every rendered line to `w` (`termObj.getSize()`, default `51x19`) using `termObj.setCursorPos(1, y)` + `termObj.write(...)`; never exceed `y = h` (`19`), never call `printError`.
- Support non-interactive CLI mode inside `installer_app.run(opts)`: if `opts.cliArgs` provides `{"install", "<moduleId>", ["--source", "gdrive"]}` or `{"uninstall", "<moduleId>"}`, execute directly and return `(ok, err)` without blocking for keyboard input; otherwise run the interactive TUI loop.

- [ ] **Step 4: Run unit tests to verify GREEN**

Run: `python tools/run_unit_tests.py --target installer`
Expected: `[PASS]  0_development/installer` (all suites passed).

- [ ] **Step 5: Commit Task 5**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/installer/modules/tui_view.lua src/0_development/installer/installer_app.lua tests/0_development/installer/test_installer_tui_and_app.lua
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(installer): add 51x19 TUI view and module installation controller"
```

---

### Task 6: 3-Mode Root Bootstrapper (`installer.lua`) & Integrity Guard (`TASK-005-5`)

**Files:**
- Create: `src/0_development/installer/installer.lua`
- Create: `src/0_development/installer/main.lua`
- Create: `installer.lua` (repository root, byte-identical to `src/0_development/installer/installer.lua`)
- Create: `tests/0_development/installer/test_bootstrapper.lua`
- Create: `tests/harness/test_installer_integrity.py`

**Interfaces:**
- Consumes: `manifest.BOOTSTRAP_FILES`, `installer_app.run`, CC:Tweaked `shell`, `fs`, `http`, `package`
- Produces:
  - `bootstrapper.detectContext(runningProgram, fsApi) -> { mode: string, runningPath: string, scriptDir: string, targetRoot: string, preserveSelf: boolean }`
  - `bootstrapper.resolveLocalCoreDir(ctx, fsApi) -> string|nil`
  - `bootstrapper.bootstrapAndRun(opts) -> (boolean, string|nil)`

- [ ] **Step 1: Write the failing unit tests in `tests/0_development/installer/test_bootstrapper.lua` and `tests/harness/test_installer_integrity.py`**

1. In `tests/0_development/installer/test_bootstrapper.lua`, test:
   - `"detects direct_root, disk (/disk & /disk2), and remote_wget contexts accurately"`:
     - `"/installer.lua"` -> `mode == "direct_root"`, `targetRoot == "/"`, `preserveSelf == true`
     - `"/disk/installer.lua"` and `"disk2/installer.lua"` -> `mode == "disk"`, `targetRoot == "/"`, `preserveSelf == true`
     - `"/rom/programs/http/wget.lua"` or `"/_tmp_wget_run.lua"` -> `mode == "remote_wget"`, `targetRoot == "/"`, `preserveSelf == false`
   - `"targets computer root / and preserves disk files when launched from /disk/installer.lua"`: mounts mock `/_tmp/disk_sim` & `/_tmp/pc_root`, runs `bootstrapAndRun` in disk mode without local core so it HTTP-bootstraps into `/_tmp/pc_root/.installer_cache`, runs mock `appRunner`, cleans `/_tmp/pc_root/.installer_cache`, preserves `/disk/installer.lua` untouched, and passes `targetRoot = "/_tmp/pc_root"`.
   - `"cleans /.installer_cache even if installer_app.run raises an error"` (`pcall` + cleanup guarantee).
   - `"preserves /installer.lua on computer root after direct_root execution completes"`.
2. In `tests/harness/test_installer_integrity.py`, write `unittest.TestCase` checking:
   - `installer.lua` (repo root) exists and equals `src/0_development/installer/installer.lua` byte-for-byte.
   - `scan_lua_source` (with `Lua52SyntaxChecker` from `resolve_craftos_paths()`) returns `[]` on repo-root `installer.lua`.
   - Every `repoPath = "..."` entry parsed from `src/0_development/installer/modules/manifest.lua` exists on disk under `WORKSPACE_ROOT`.

- [ ] **Step 2: Run Lua and Python tests to verify RED failure**

Run:
- `python tools/run_unit_tests.py --target installer`
- `python -m unittest tests/harness/test_installer_integrity.py -v`
Expected: Both FAIL (`installer.lua` missing).

- [ ] **Step 3: Implement `src/0_development/installer/installer.lua`, `src/0_development/installer/main.lua`, and sync root `installer.lua`**

Implement the self-contained bootstrapper:
- Embed the minimal 7-file bootstrap list directly inside `installer.lua` (so `installer.lua` has zero external dependencies before `/.installer_cache` is fetched when dropped alone onto a fresh CC computer or invoked via `wget run`!).
- Support `--source gdrive --bootstrap-gdrive-map /gdrive_ids.json` as well as default GitHub Raw bootstrap URL `"https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/"`.
- Guard top-level auto-execution with:
  ```lua
  local _boot_args = { ... }
  local _is_module_require = (_boot_args[1] == "installer" and select("#", ...) >= 1)
  if not _G.__INSTALLER_LIB_MODE and not _is_module_require then
      bootstrapper.bootstrapAndRun({ cliArgs = _boot_args })
  end
  return bootstrapper
  ```
  (In Lua 5.2 / CC `cc.require`, `require("installer")` passes `"installer"` and the resolved file path as `...`, whereas CLI execution `installer` passes user CLI args where `_boot_args[1] ~= "installer"`, and tests can also set `_G.__INSTALLER_LIB_MODE = true`.)
- Copy `src/0_development/installer/installer.lua` verbatim to repo-root `installer.lua`, and create `src/0_development/installer/main.lua` delegating to `require("installer").bootstrapAndRun({ cliArgs = { ... } })`.

- [ ] **Step 4: Run Lua and Python tests to verify GREEN**

Run:
- `python tools/run_unit_tests.py --target installer`
- `python -m unittest discover -s tests/harness -p "test_*.py" -v`
Expected: Both PASS (`0_development/installer` PASS; all harness + integrity tests OK).

- [ ] **Step 5: Commit Task 6**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add installer.lua src/0_development/installer/installer.lua src/0_development/installer/main.lua tests/0_development/installer/test_bootstrapper.lua tests/harness/test_installer_integrity.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(installer): add 3-mode root bootstrapper and manifest parity checks"
```

---

### Task 7: Legacy GPS Installer Zero-Fallback Removal (`TASK-005-6`)

**Files:**
- Delete: `src/0_infra/gps/installer.lua`
- Delete: `src/0_infra/gps/modules/installer_core.lua`
- Modify: `src/0_infra/gps/main.lua`
- Modify: `src/0_infra/gps/hal/gps_client.lua`
- Modify: `tests/0_infra/gps/test_gps_core.lua`
- Modify: `tests/harness/test_installer_integrity.py`

**Interfaces:**
- Consumes: Approved `GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v2.2.0`), `src/0_infra/gps/modules/config_store.lua`
- Produces: Clean `0_infra/gps` codebase with zero legacy installer files and self-resolving `/apis/gps_client.lua`

- [ ] **Step 1: Add failing Zero-Fallback & `gps_client` path assertions**

1. In `tests/harness/test_installer_integrity.py`, add `test_legacy_gps_installer_removed` asserting neither `src/0_infra/gps/installer.lua` nor `src/0_infra/gps/modules/installer_core.lua` exists.
2. In `tests/0_infra/gps/test_gps_core.lua`, replace lines 180–198 (`describe("gps installer node configuration", ...)` which called `require("installer")`) with `describe("gps config_store 4-channel node configuration and standalone gps_client load", ...)` asserting:
   - `config_store.normalizeNodeConfig({}, 7)` produces `channels = { ping = 60001, service = 60002, nodeIn = 60003, mgmt = 60004 }` with `cfg.channel == nil`.
   - `pcall(require, "installer")` returns `false` (proving legacy `gps/installer.lua` is absent from `0_infra/gps`).

- [ ] **Step 2: Run tests to verify RED failure**

Run:
- `python -m unittest tests/harness/test_installer_integrity.py -v`
- `python tools/run_unit_tests.py --target 0_infra/gps`
Expected: FAIL (`src/0_infra/gps/installer.lua` still exists).

- [ ] **Step 3: Delete legacy GPS installer files and clean `gps/main.lua` & `gps_client.lua`**

1. Delete `src/0_infra/gps/installer.lua` and `src/0_infra/gps/modules/installer_core.lua`.
2. In `src/0_infra/gps/main.lua`, remove lines 13–14 (`elseif mode == "installer" then shell.run("installer.lua")`).
3. At top of `src/0_infra/gps/hal/gps_client.lua` (before `require("client_core")`), add a pure Lua 5.2 `package.path` guard appending `;/gps/modules/?.lua` when `package and package.path` does not already contain `/gps/modules/?.lua`, so scripts loading `/apis/gps_client.lua` on external computers resolve `client_core` and `protocol` automatically.

- [ ] **Step 4: Run GPS unit tests and Python integrity tests to verify GREEN**

Run:
- `python tools/run_unit_tests.py --target 0_infra/gps`
- `python tools/run_unit_tests.py --target installer`
- `python -m unittest discover -s tests/harness -p "test_*.py" -v`
Expected: All PASS.

- [ ] **Step 5: Commit Task 7**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add -A src/0_infra/gps tests/0_infra/gps/test_gps_core.lua tests/harness/test_installer_integrity.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "refactor(gps): remove legacy gps installer under zero-fallback policy"
```

---

### Task 8: Full Regression Verification, Spec Promotion (`Approved` → `Implemented`), & Context Sync (`TASK-005-7`)

**Files:**
- Modify: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (status promotion `Approved` → `Implemented`)
- Modify: `README.md`
- Modify: `src/README.md`
- Modify: `TASK.md`
- Modify: `GEMINI.md`

**Interfaces:**
- Consumes: Completed Tasks 1–7, `.agent/skills/verification-before-completion/SKILL.md`, `.agent/skills/md-management/SKILL.md`
- Produces: All 7 unit-test targets passing, 12/12 specs clean (`5 Implemented, 7 Approved`), synchronized roadmap and context snapshot ($\le 80$ lines)

- [ ] **Step 1: Run full code & harness verification battery (`verification-before-completion`)**

Run:
1. `python tools/run_unit_tests.py --require-tests --clean-orphans`
2. `python -m unittest discover -s tests/harness -p "test_*.py" -v`
3. `python scratch/validate_lua_syntax.py`
Expected:
- Unit test runner: `7 targets` (`0_development/alignment`, `0_development/installer`, `0_infra/gps`, `1_control/asa`, `1_control/tca`, `1_control/vas`, `2_guidance/fcp`) — `Overall Result: PASS`.
- Harness Python tests: all tests `OK`.
- Lua 5.2 syntax check: `PASS`.

- [ ] **Step 2: Promote `GPS_PROGRAM_SPECIFICATION_AND_ICD.md` from `Approved` to `Implemented` and run spec scanners**

Per `skill-workflows.md` Section 3 lightweight completion transition:
1. Update `문서 상태 (Status)` in `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` from `` `Approved` `` to `` `Implemented` `` (`Date: 2026-11-08`).
2. Run:
   - `python scratch/verify_all_specs.py`
   - `python scratch/verify_spec_status.py`
Expected:
- `SCAN RESULT: ALL 12 SPECS 100% CLEAN (0 Errors, 0 Warnings)`
- `[PASS] All 12 specs have valid statuses (5 Implemented, 7 Approved)!`

- [ ] **Step 3: Synchronize `README.md`, `src/README.md`, `TASK.md`, and `GEMINI.md`**

1. `src/README.md` & `README.md`: register `0_development/installer/` (and root `installer.lua`) in the directory layout and update unit test target count (`7` targets).
2. `TASK.md`: mark `TASK-005` and `TASK-005-1`..`TASK-005-7` `[x]` with completion date `2026-11-08`, plan path `docs/superpowers/plans/2026-11-08-task-005-unified-codebase-installer.md`, and verification summary; add completed entry to `## ✅ 3. 완료된 작업 이력` (keeping $\le 30$ entries).
3. `GEMINI.md` (read `.agent/skills/md-management/SKILL.md` first): update Section 1 (`TASK-005` complete, next active candidate `TASK-006`), Section 2 (`installer.lua` + `0_development/installer`), and Section 3 (`7개 타겟`), keeping total length strictly $\le 80$ lines. Verify line count via `(Get-Content GEMINI.md).Count`.

- [ ] **Step 4: Commit documentation & status promotion**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md README.md src/README.md TASK.md GEMINI.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(installer): promote GPS v2.2.0 to Implemented and complete TASK-005"
```
