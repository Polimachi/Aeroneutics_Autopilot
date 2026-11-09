# TASK-009: Google Drive Deployment Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a structured Google Drive deployment staging directory layout (`dist_gdrive/`), build an automated staging and sync CLI (`tools/sync_gdrive.py`), enhance the installer mapping system (`config/gdrive_mapping.json`), upload release packages to Google Drive folder `1NgbGjm9YY7lpIlo4sLs32cNE2NwjVVy9`, and document operational guidelines.

**Architecture:** A 3-tier cloud distribution architecture. Local development sources (`src/`) are staged into a clean distribution layout (`dist_gdrive/`). A Python automation tool (`tools/sync_gdrive.py`) interfaces with the authenticated `gdrive` CLI to manage remote folder structures and in-place file updates, generating a versioned mapping SSOT (`config/gdrive_mapping.json`). The unified root bootstrapper (`installer.lua`) and declarative manifest (`manifest.lua`) consume this mapping to enable seamless in-game installation via Google Drive direct downloads.

**Tech Stack:** Python 3 (CLI, subprocess, json, unittest), CC:Tweaked Lua 5.2, Google Drive CLI (`gdrive`), GitHub Flavored Markdown.

**Spec:** `TASK.md` (TASK-009 specifications), `docs/specs/0_development/installer/`, and `installer.lua` ICD.

## Global Constraints

- **Folder SSOT**: Dedicated Google Drive target folder is `1NgbGjm9YY7lpIlo4sLs32cNE2NwjVVy9` (`Antigravity_Playground`).
- **Installer Byte Parity**: Root `installer.lua` and `src/0_development/installer/installer.lua` must remain 100% byte-for-byte identical.
- **Zero-Fallback in Production**: Direct file ID lookup with unambiguous errors (`GDRIVE_ID_UNCONFIGURED`).
- **Idempotent Sync**: `sync` must update existing files in-place (`gdrive mutate update`) to preserve remote file IDs where possible, uploading new files (`gdrive mutate upload`) only when absent.
- **Test Invariants**: Universal unit tests (293/293), E2E simulations (6/6), mutation tests (20/20), and harness suites must continue passing with zero regressions.

## Review Focus

1. **`installer.lua` mapping format compatibility**: ensure `--bootstrap-gdrive-map` parses both flat `{ "repoPath": "fileId" }` and structured `{ "files": { "repoPath": { "id": "..." } } }` formats.
2. **Byte parity enforcement**: any change to `installer.lua` must be mirrored to `src/0_development/installer/installer.lua`.
3. **Google Drive interstitial handling**: verify download URLs append `&export=download&confirm=t` and match `downloader.lua` expectations.
4. **Staging isolation**: ensure `dist_gdrive/` staging directory can be generated idempotently from `manifest.lua`.
5. **Tool integrity coverage**: register `tools/sync_gdrive.py` in `tests/harness/test_tools_integrity.py`.

---

### Task 1: Staging Directory Layout Architecture

**Files:**
- Create: `dist_gdrive/.gitkeep`
- Modify: `.gitignore:17-21`

**Interfaces:**
- Consumes: Repository directory layout.
- Produces: Git-tracked staging root `dist_gdrive/` with transient staging content ignored.

- [ ] **Step 1: Configure `.gitignore` for `dist_gdrive` staging outputs**

Add `dist_gdrive/*` to `.gitignore` while whitelisting `.gitkeep` and `gdrive_mapping.json`:
```gitignore
# Google Drive distribution staging
dist_gdrive/*
!dist_gdrive/.gitkeep
!dist_gdrive/gdrive_mapping.json
```

- [ ] **Step 2: Create `dist_gdrive/.gitkeep`**

Create empty file `dist_gdrive/.gitkeep`.

- [ ] **Step 3: Verify git status reflects intended tracking**

Run: `git status -sb`
Expected: `dist_gdrive/.gitkeep` is tracked or untracked candidate, no mass files ignored incorrectly.

- [ ] **Step 4: Commit staging directory structure**

```bash
git add .gitignore dist_gdrive/.gitkeep
git commit -m "chore(infra): initialize dist_gdrive staging directory layout"
```

---

### Task 2: GDrive Mapping SSOT Schema and Installer Loader Enhancement

**Files:**
- Create: `config/gdrive_mapping.json`
- Modify: `installer.lua:267-279`
- Modify: `src/0_development/installer/installer.lua:267-279`
- Modify: `tests/0_development/installer/test_bootstrapper.lua`

**Interfaces:**
- Consumes: Mapping JSON file path from `--bootstrap-gdrive-map`.
- Produces: Normalized `gdriveOverrides[repoPath] = fileId` mapping supporting both flat and nested schemas.

- [ ] **Step 1: Write failing unit test in `tests/0_development/installer/test_bootstrapper.lua`**

Test that `--bootstrap-gdrive-map` parses structured metadata format with nested `files` or `id` attributes:
```lua
    it("parses structured gdrive_mapping.json with nested file IDs", function()
        local pcRoot = sdk.temp_path("pc_root_structured_gdrive")
        fs.makeDir(pcRoot)

        local mapPath = pcRoot .. "/structured_map.json"
        local structuredMap = {
            version = "1.0.0",
            folderId = "1NgbGjm9YY7lpIlo4sLs32cNE2NwjVVy9",
            files = {
                ["src/0_development/installer/installer_app.lua"] = { id = "TEST_STRUCTURED_ID_01" },
            },
            bootstrapMap = {
                ["src/0_development/installer/modules/manifest.lua"] = "TEST_STRUCTURED_ID_02",
            }
        }
        writeFile(mapPath, textutils.serialiseJSON(structuredMap))

        local capturedOverrides = nil
        local mockHttp = createMockHttp(nil, "-- mock file")
        local ok, err = bootstrapper.bootstrapAndRun({
            runningProgram = "/installer.lua",
            targetRoot = pcRoot,
            cliArgs = { "--bootstrap-gdrive-map", mapPath },
            http = mockHttp,
            fs = fs,
            localCoreDir = false,
            appRunner = function(opts)
                capturedOverrides = opts.gdriveOverrides
                return true, nil
            end,
        })

        assert_true(ok)
        assert_not_nil(capturedOverrides)
        assert_eq(capturedOverrides["src/0_development/installer/installer_app.lua"], "TEST_STRUCTURED_ID_01")
        assert_eq(capturedOverrides["src/0_development/installer/modules/manifest.lua"], "TEST_STRUCTURED_ID_02")
    end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python tools/run_unit_tests.py -t 0_development/installer -f structured_gdrive`
Expected: FAIL (assertion error or nil override).

- [ ] **Step 3: Implement enhanced mapping loader in `installer.lua` and `src/0_development/installer/installer.lua`**

Update `installer.lua` lines 267-279:
```lua
            if textutils and textutils.unserialiseJSON then
                local map = textutils.unserialiseJSON(c)
                if type(map) == "table" then
                    gdriveOverrides = gdriveOverrides or {}
                    -- Support flat dictionary { [repoPath] = fileId }
                    for k, v in pairs(map) do
                        if type(v) == "string" then
                            gdriveOverrides[k] = v
                        elseif type(v) == "table" and type(v.id) == "string" then
                            gdriveOverrides[k] = v.id
                        end
                    end
                    -- Support structured dictionary { files = { [repoPath] = { id = "..." } }, bootstrapMap = { ... } }
                    if type(map.files) == "table" then
                        for k, v in pairs(map.files) do
                            if type(v) == "string" then
                                gdriveOverrides[k] = v
                            elseif type(v) == "table" and type(v.id) == "string" then
                                gdriveOverrides[k] = v.id
                            end
                        end
                    end
                    if type(map.bootstrapMap) == "table" then
                        for k, v in pairs(map.bootstrapMap) do
                            if type(v) == "string" then
                                gdriveOverrides[k] = v
                            end
                        end
                    end
                end
            end
```
Copy identical code to `src/0_development/installer/installer.lua`.

- [ ] **Step 4: Create initial `config/gdrive_mapping.json` template**

Create `config/gdrive_mapping.json`:
```json
{
  "version": "1.0.0",
  "folderId": "1NgbGjm9YY7lpIlo4sLs32cNE2NwjVVy9",
  "folderUrl": "https://drive.google.com/drive/folders/1NgbGjm9YY7lpIlo4sLs32cNE2NwjVVy9",
  "lastSync": null,
  "files": {},
  "bootstrapMap": {}
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `python tools/run_unit_tests.py -t 0_development/installer`
Expected: PASS (30/30 passed).

Run: `python -m unittest tests/harness/test_installer_integrity.py`
Expected: PASS (byte-for-byte parity confirmed).

- [ ] **Step 6: Commit installer mapping support**

```bash
git add installer.lua src/0_development/installer/installer.lua tests/0_development/installer/test_bootstrapper.lua config/gdrive_mapping.json
git commit -m "feat(installer): support structured gdrive_mapping.json and metadata schemas"
```

---

### Task 3: Automated Staging & GDrive Sync CLI Tool (`tools/sync_gdrive.py`)

**Files:**
- Create: `tools/sync_gdrive.py`
- Create: `tests/harness/test_gdrive_sync.py`
- Modify: `tests/harness/test_tools_integrity.py:16-25`

**Interfaces:**
- Consumes: `src/0_development/installer/modules/manifest.lua`, `gdrive` CLI (`readonly ls`, `mutate upload`, `mutate update`, `mutate mkdir`).
- Produces: `dist_gdrive/` file hierarchy, updated `config/gdrive_mapping.json`, CLI exit codes (0 on success).

- [ ] **Step 1: Write unit tests in `tests/harness/test_gdrive_sync.py`**

Test:
- CLI argument parsing (`stage`, `status`, `sync`, `verify`).
- `stage` command collects all files from `manifest.BOOTSTRAP_FILES`, `SHARED_LIBS`, and `MODULES`.
- `config/gdrive_mapping.json` updater and serializer.
- `verify` checks remote ID resolution format.

- [ ] **Step 2: Run test to verify it fails (Red)**

Run: `python -m unittest tests/harness/test_gdrive_sync.py`
Expected: FAIL (module `tools.sync_gdrive` not found).

- [ ] **Step 3: Implement `tools/sync_gdrive.py`**

Implement CLI with commands:
1. `stage`: Copies root `installer.lua` to `dist_gdrive/installer/installer.lua`, bootstrap files to `dist_gdrive/bootstrap/`, and package modules to `dist_gdrive/packages/<module>/`.
2. `sync --folder-id <id>`:
   - Queries `gdrive readonly ls <folderId> --json` to list remote files.
   - For each staged file, if already present in remote folder, runs `gdrive mutate update <fileId> <localPath>`. If absent, runs `gdrive mutate upload <localPath> --parent <folderId>`.
   - Records file IDs in `config/gdrive_mapping.json` (under both `files[repoPath]` and `bootstrapMap[repoPath]`).
3. `status`: Displays local staged file count, mapped file count, and remote file count.
4. `verify`: Validates all required bootstrap and package files have non-null IDs in `config/gdrive_mapping.json`.

- [ ] **Step 4: Update `tests/harness/test_tools_integrity.py`**

Add `WORKSPACE_ROOT / "tools" / "sync_gdrive.py"` to `expected_tools`.

- [ ] **Step 5: Run tests to verify they pass (Green)**

Run: `python -m unittest tests/harness/test_gdrive_sync.py`
Expected: PASS.

Run: `python -m unittest tests/harness/test_tools_integrity.py`
Expected: PASS.

- [ ] **Step 6: Commit tool implementation**

```bash
git add tools/sync_gdrive.py tests/harness/test_gdrive_sync.py tests/harness/test_tools_integrity.py
git commit -m "feat(tools): add automated staging and GDrive synchronization CLI"
```

---

### Task 4: Staging Execution, Google Drive Upload & Manifest ID Population

**Files:**
- Modify: `config/gdrive_mapping.json`
- Modify: `installer.lua:10-18`
- Modify: `src/0_development/installer/installer.lua:10-18`
- Modify: `src/0_development/installer/modules/manifest.lua:18-26`

**Interfaces:**
- Consumes: Target Google Drive folder `1NgbGjm9YY7lpIlo4sLs32cNE2NwjVVy9`.
- Produces: Live uploaded files on Google Drive, populated `gdrive_mapping.json`, and bootstrap `gdriveId` presets.

- [ ] **Step 1: Execute staging command**

Run: `python tools/sync_gdrive.py stage`
Expected: Output indicates all bootstrap files, packages, and installer successfully staged to `dist_gdrive/`.

- [ ] **Step 2: Execute sync command against target Google Drive folder**

Run: `python tools/sync_gdrive.py sync --folder-id 1NgbGjm9YY7lpIlo4sLs32cNE2NwjVVy9`
Expected: Bootstrap files and core release artifacts uploaded to Google Drive folder, returning file IDs and writing to `config/gdrive_mapping.json`.

- [ ] **Step 3: Verify remote folder contents via `gdrive` CLI**

Run: `gdrive readonly ls 1NgbGjm9YY7lpIlo4sLs32cNE2NwjVVy9 --max 50`
Expected: Remote files listed with IDs matching `config/gdrive_mapping.json`.

- [ ] **Step 4: Populate bootstrap file IDs in `installer.lua`, `src/0_development/installer/installer.lua`, and `manifest.lua`**

Populate the `gdriveId` fields for the 7 bootstrap files from `config/gdrive_mapping.json` so that out-of-the-box GDrive source downloads work without arguments.
Verify byte parity between root `installer.lua` and `src/0_development/installer/installer.lua`.

- [ ] **Step 5: Run integrity and installer tests**

Run: `python -m unittest tests/harness/test_installer_integrity.py`
Expected: PASS.

Run: `python tools/run_unit_tests.py -t 0_development/installer`
Expected: PASS.

- [ ] **Step 6: Commit uploaded mapping and manifest presets**

```bash
git add config/gdrive_mapping.json installer.lua src/0_development/installer/installer.lua src/0_development/installer/modules/manifest.lua
git commit -m "feat(deploy): synchronize release artifacts to Google Drive and populate bootstrap IDs"
```

---

### Task 5: Operational Guidelines Documentation and Milestone Completion

**Files:**
- Create: `docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md`
- Modify: `TASK.md`
- Modify: `GEMINI.md`

**Interfaces:**
- Consumes: Verification commands output.
- Produces: Complete operational guide and updated roadmap marking TASK-009 as complete `[x]`.

- [ ] **Step 1: Write `docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md`**

Document:
- Directory layout (`dist_gdrive/` staging and `config/gdrive_mapping.json`).
- `tools/sync_gdrive.py` CLI command usage.
- In-game ComputerCraft terminal commands:
  - Direct root: `installer.lua --bootstrap-gdrive-map config/gdrive_mapping.json`
  - Wget remote bootstrap: `wget run <gdrive_download_url>`
- Google Drive permission settings and account management.

- [ ] **Step 2: Run full system regression gate**

Run:
1. `python -m unittest discover -s tests/harness -p "test_*.py"` (Harness PASS)
2. `python tools/run_unit_tests.py --require-tests --clean-orphans` (293+ unit tests PASS)
3. `python tools/run_e2e_tests.py --clean-orphans` (6/6 E2E PASS)
4. `python tools/run_mutation_tests.py` (20/20 KILLED, 100.0%)
5. `python tools/verify_all_specs.py` (14/14 specs 100% CLEAN)
6. `python tools/validate_lua_syntax.py` (126/126 files PASS)
7. `python tools/verify_spec_status.py` (8 Implemented, 6 Approved)

- [ ] **Step 3: Update `TASK.md` and `GEMINI.md`**

- Move `TASK-009` to `## 3. 완료된 작업 이력` in `TASK.md`, maintain top 10 limit.
- Update `GEMINI.md` Phase 1 & 2 active handover section.

- [ ] **Step 4: Commit documentation and task completion**

```bash
git add docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md TASK.md GEMINI.md
git commit -m "docs: publish Google Drive deployment guide and mark TASK-009 complete"
```
