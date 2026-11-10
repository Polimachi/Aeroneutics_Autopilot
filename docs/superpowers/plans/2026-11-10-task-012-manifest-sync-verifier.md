# Installer Manifest, GDrive Mapping, and Source Tree 3-Way Sync Verifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a static 3-way consistency verifier (`tools/verify_manifest_sync.py`) that enforces bidirectional parity across the runtime source tree (`src/` and root `installer.lua`), the unified installer manifest (`src/0_development/installer/modules/manifest.lua`), and the Google Drive deployment mapping SSOT (`config/gdrive_mapping.json`), and integrate it into the standard verification pipeline.

**Architecture:** `tools/verify_manifest_sync.py` parses `manifest.lua` and `installer.lua` structurally without requiring a external Lua runtime, scans `src/` for all runtime `.lua` and `.json` files, and cross-validates them against `config/gdrive_mapping.json`. It exposes both a programmatic `run_verification(workspace_root, ...)` API returning a structured `VerificationReport` and a CLI entrypoint returning exit code `0` on `0 Errors` or `1` on any violation.

**Tech Stack:** Python 3.10+ standard library (`pathlib`, `re`, `json`, `argparse`, `dataclasses`, `unittest`).

**Spec:** `TASK.md` (`TASK-012`), `docs/guides/GDRIVE_DEPLOYMENT_GUIDE.md`, `src/0_development/installer/modules/manifest.lua`, `config/gdrive_mapping.json`.

## Global Constraints

- **Zero External Python Dependencies**: `tools/verify_manifest_sync.py` must use only the Python standard library so it runs in any local or CI environment.
- **No Broad Wildcard Ignore on `src/`**: Every `.lua` and `.json` file under `src/` must be accounted for by either (a) an explicit `repoPath` entry in `manifest.lua`, (b) a module `defaultConfigs`/`configTemplate` relative path for `.json` files, or (c) an explicit, narrowly-scoped exemption constant (`INSTALLER_ENTRY_EXEMPTIONS`, `SIMULATION_NODE_GLOB`, `DEFERRED_SUBSYSTEM_DIRS`).
- **Category Hygiene (TASK-009 & TASK-116 Alignment)**: Every module in `manifest.MODULES` must declare a valid `category` in `{"development", "infra", "control", "guidance", "planning", "mission"}` matching its `src/<layer>_<domain>/` directory, and every file entry in `config/gdrive_mapping.json` must declare a valid `category` in `{"installer", "bootstrap", "shared", "packages"}` matching its role in `manifest.lua`.
- **Bootstrap `gdriveId` & Byte-Parity Invariant**: `installer.lua` and `src/0_development/installer/installer.lua` must be byte-for-byte identical, and their `BOOTSTRAP_FILES` table must match `manifest.BOOTSTRAP_FILES` and `config/gdrive_mapping.json` (`files` and `bootstrapMap`) in both `repoPath` set and `gdriveId` values.
- **No Overclaim Output**: CLI summary output must report exact numeric counts (`0 Errors, 0 Warnings` or `<N> Errors, <M> Warnings`) and verified item totals.

## Review Focus

1. **Unregistered Runtime `.lua` File Added to an Active Module (`ORPHAN_SRC_FILE`)**: If a developer creates `src/1_control/vas/modules/new_filter.lua` and forgets to register it in `manifest.MODULES.vas.files`, `verify_manifest_sync.py` must flag `ORPHAN_SRC_FILE` and exit non-zero.
2. **Renamed or Deleted File Left Behind in `manifest.lua` (`MISSING_DISK_FILE`)**: If a `repoPath` in `manifest.BOOTSTRAP_FILES`, `manifest.SHARED_LIBS`, or `manifest.MODULES[*].files` does not exist on disk, `verify_manifest_sync.py` must flag `MISSING_DISK_FILE`.
3. **Module Registered in `manifest.MODULES` But Omitted from `manifest.MODULE_ORDER` or Missing `category` (`MODULE_ORDER_MISMATCH` / `INVALID_MODULE_CATEGORY`)**: If a module table exists in `manifest.MODULES` without a corresponding entry in `manifest.MODULE_ORDER`, or has an empty/invalid `category` or a `category` that contradicts its `src/<layer>_<domain>/` path, `verify_manifest_sync.py` must flag it.
4. **Stale or Mismatched Entry in `config/gdrive_mapping.json` (`ORPHAN_GDRIVE_MAPPING` / `INVALID_GDRIVE_CATEGORY` / `BOOTSTRAP_GDRIVE_ID_MISMATCH`)**: If `config/gdrive_mapping.json` contains a file key not in `manifest.lua`/`installer.lua`, misses a required bootstrap/installer/shared entry, has an invalid/mismatched `category`, or has a `gdriveId` that disagrees with `manifest.lua` or `installer.lua`, `verify_manifest_sync.py` must flag it.
5. **Stale Deferred Subsystem Exemption (`STALE_DEFERRED_EXEMPTION`)**: Once a deferred subsystem in `DEFERRED_SUBSYSTEM_DIRS` (currently `src/1_control/asa`) is later added to `manifest.MODULES`, `verify_manifest_sync.py` must flag `STALE_DEFERRED_EXEMPTION` so the exemption list is kept clean.

---

## File Structure

- Create: `tools/verify_manifest_sync.py` — 3-way static consistency verifier CLI and library (`parse_manifest_lua`, `parse_bootstrap_lua`, `scan_src_tree`, `verify_manifest_sync`, `main`).
- Create: `tests/harness/test_manifest_sync_verifier.py` — Unit test suite exercising all 5 verification dimensions against both the live repository and synthetic fault-injected temporary workspaces.
- Modify: `tests/harness/test_tools_integrity.py` — Register `tools/verify_manifest_sync.py` in `expected_tools` and add `test_verify_manifest_sync_execution`.
- Modify: `TASK.md` — Track `TASK-012` execution and completion status.
- Modify: `GEMINI.md` — Add `python tools/verify_manifest_sync.py` to `## 2. Confirmed Architecture & Paths` and `## 3. Standard Commands`.

---

### Task 1: Implement 3-Way Manifest, GDrive Mapping, and Source Tree Verifier (`TASK-012-1`)

**Files:**
- Create: `tools/verify_manifest_sync.py`
- Create: `tests/harness/test_manifest_sync_verifier.py`

**Interfaces:**
- Consumes:
  - `installer.lua`
  - `src/0_development/installer/installer.lua`
  - `src/0_development/installer/modules/manifest.lua`
  - `config/gdrive_mapping.json`
  - `src/**/*`
- Produces:
  - `VerificationReport` dataclass in `tools/verify_manifest_sync.py`:
    - `errors: List[str]`
    - `warnings: List[str]`
    - `checked_modules: int`
    - `checked_manifest_files: int`
    - `checked_src_files: int`
    - `checked_gdrive_entries: int`
    - `ok: bool` (property: `len(self.errors) == 0`)
  - `verify_workspace(workspace_root: Path, strict_gdrive_packages: bool = False) -> VerificationReport`
  - CLI `python tools/verify_manifest_sync.py [--workspace-root <path>] [--strict-gdrive-packages]` printing summary ending with `Manifest 3-way sync verification complete: <E> Errors, <W> Warnings` and returning `0` if `E == 0` else `1`.

- [ ] **Step 1: Write the failing unit tests in `tests/harness/test_manifest_sync_verifier.py`**

```python
"""
Unit tests for tools/verify_manifest_sync.py 3-way static consistency verifier.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(WORKSPACE_ROOT))

from tools.verify_manifest_sync import verify_workspace  # noqa: E402


def _build_minimal_workspace(root: Path) -> None:
    """Creates a minimal valid 3-way synced workspace inside root for fault-injection tests."""
    (root / "src" / "0_development" / "installer" / "modules").mkdir(parents=True)
    (root / "src" / "0_development" / "sensors").mkdir(parents=True)
    (root / "src" / "1_control" / "vas" / "modules").mkdir(parents=True)
    (root / "config").mkdir(parents=True)

    bootstrap_block = '''bootstrapper.BOOTSTRAP_FILES = {
    { repoPath = "src/0_development/installer/installer_app.lua", cacheRelPath = "installer_app.lua", gdriveId = "ID_APP" },
    { repoPath = "src/0_development/installer/modules/manifest.lua", cacheRelPath = "modules/manifest.lua", gdriveId = "ID_MAN" },
}
'''
    (root / "installer.lua").write_text(bootstrap_block, encoding="utf-8")
    (root / "src" / "0_development" / "installer" / "installer.lua").write_text(
        bootstrap_block, encoding="utf-8"
    )
    (root / "src" / "0_development" / "installer" / "main.lua").write_text(
        'return require("installer")\n', encoding="utf-8"
    )
    (root / "src" / "0_development" / "installer" / "installer_app.lua").write_text(
        "return {}\n", encoding="utf-8"
    )
    (root / "src" / "0_development" / "sensors" / "avionics_sensors.lua").write_text(
        "return {}\n", encoding="utf-8"
    )
    (root / "src" / "1_control" / "vas" / "main.lua").write_text(
        "return {}\n", encoding="utf-8"
    )
    (root / "src" / "1_control" / "vas" / "modules" / "core_daemon.lua").write_text(
        "return {}\n", encoding="utf-8"
    )

    manifest_lua = '''local manifest = {}
manifest.BOOTSTRAP_FILES = {
    { repoPath = "src/0_development/installer/installer_app.lua", cacheRelPath = "installer_app.lua", gdriveId = "ID_APP" },
    { repoPath = "src/0_development/installer/modules/manifest.lua", cacheRelPath = "modules/manifest.lua", gdriveId = "ID_MAN" },
}
manifest.SHARED_LIBS = {
    avionics_sensors = {
        repoPath = "src/0_development/sensors/avionics_sensors.lua",
        dest = "/lib/avionics_sensors.lua",
        gdriveId = nil,
    },
}
manifest.MODULE_ORDER = {
    "vas",
}
manifest.MODULES = {
    vas = {
        id = "vas",
        name = "VAS",
        category = "control",
        version = "1.15.0",
        installDir = "/",
        defaultConfigs = {
            ["/config/system.json"] = { baseChannel = 10000 },
        },
        files = {
            { repoPath = "src/1_control/vas/main.lua", dest = "/main.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/core_daemon.lua", dest = "/modules/core_daemon.lua", gdriveId = nil },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil },
        },
    },
}
return manifest
'''
    (root / "src" / "0_development" / "installer" / "modules" / "manifest.lua").write_text(
        manifest_lua, encoding="utf-8"
    )

    gdrive_map = {
        "version": "1.0.0",
        "folderId": "FOLDER_123",
        "folderUrl": "https://drive.google.com/drive/folders/FOLDER_123",
        "lastSync": "2026-11-10T00:00:00Z",
        "files": {
            "installer.lua": {
                "id": "ID_INST",
                "name": "installer.lua",
                "repoPath": "installer.lua",
                "category": "installer",
                "sizeBytes": 100,
                "sha256": "a" * 64,
                "downloadUrl": "https://drive.usercontent.google.com/download?id=ID_INST&export=download&confirm=t",
            },
            "src/0_development/installer/installer_app.lua": {
                "id": "ID_APP",
                "name": "installer_app.lua",
                "repoPath": "src/0_development/installer/installer_app.lua",
                "category": "bootstrap",
                "sizeBytes": 10,
                "sha256": "b" * 64,
                "downloadUrl": "https://drive.usercontent.google.com/download?id=ID_APP&export=download&confirm=t",
            },
            "src/0_development/installer/modules/manifest.lua": {
                "id": "ID_MAN",
                "name": "manifest.lua",
                "repoPath": "src/0_development/installer/modules/manifest.lua",
                "category": "bootstrap",
                "sizeBytes": 200,
                "sha256": "c" * 64,
                "downloadUrl": "https://drive.usercontent.google.com/download?id=ID_MAN&export=download&confirm=t",
            },
            "src/0_development/sensors/avionics_sensors.lua": {
                "id": "ID_SENS",
                "name": "avionics_sensors.lua",
                "repoPath": "src/0_development/sensors/avionics_sensors.lua",
                "category": "shared",
                "sizeBytes": 10,
                "sha256": "d" * 64,
                "downloadUrl": "https://drive.usercontent.google.com/download?id=ID_SENS&export=download&confirm=t",
            },
        },
        "bootstrapMap": {
            "installer.lua": "ID_INST",
            "src/0_development/installer/installer_app.lua": "ID_APP",
            "src/0_development/installer/modules/manifest.lua": "ID_MAN",
            "src/0_development/sensors/avionics_sensors.lua": "ID_SENS",
        },
    }
    (root / "config" / "gdrive_mapping.json").write_text(
        json.dumps(gdrive_map, indent=2), encoding="utf-8"
    )


class TestManifestSyncVerifier(unittest.TestCase):
    def test_live_workspace_passes_with_zero_errors(self) -> None:
        report = verify_workspace(WORKSPACE_ROOT)
        self.assertTrue(
            report.ok,
            f"Live workspace failed 3-way manifest sync check:\n" + "\n".join(report.errors),
        )
        self.assertEqual(report.errors, [])
        self.assertGreaterEqual(report.checked_modules, 12)
        self.assertGreaterEqual(report.checked_manifest_files, 80)

    def test_detects_unregistered_orphan_src_lua_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _build_minimal_workspace(root)
            orphan = root / "src" / "1_control" / "vas" / "modules" / "unregistered_new.lua"
            orphan.write_text("return {}\n", encoding="utf-8")

            report = verify_workspace(root)
            self.assertFalse(report.ok)
            self.assertTrue(
                any("ORPHAN_SRC_FILE" in e and "unregistered_new.lua" in e for e in report.errors),
                f"Expected ORPHAN_SRC_FILE error, got: {report.errors}",
            )

    def test_detects_missing_disk_file_referenced_in_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _build_minimal_workspace(root)
            (root / "src" / "1_control" / "vas" / "modules" / "core_daemon.lua").unlink()

            report = verify_workspace(root)
            self.assertFalse(report.ok)
            self.assertTrue(
                any("MISSING_DISK_FILE" in e and "core_daemon.lua" in e for e in report.errors),
                f"Expected MISSING_DISK_FILE error, got: {report.errors}",
            )

    def test_detects_module_order_mismatch_and_invalid_category(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _build_minimal_workspace(root)
            man_path = root / "src" / "0_development" / "installer" / "modules" / "manifest.lua"
            content = man_path.read_text(encoding="utf-8").replace(
                'category = "control"', 'category = "invalid_cat"'
            )
            man_path.write_text(content, encoding="utf-8")

            report = verify_workspace(root)
            self.assertFalse(report.ok)
            self.assertTrue(
                any("INVALID_MODULE_CATEGORY" in e for e in report.errors),
                f"Expected INVALID_MODULE_CATEGORY error, got: {report.errors}",
            )

    def test_detects_orphan_and_category_and_id_mismatch_in_gdrive_mapping(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _build_minimal_workspace(root)
            map_path = root / "config" / "gdrive_mapping.json"
            data = json.loads(map_path.read_text(encoding="utf-8"))
            # 1. Corrupt bootstrap ID
            data["files"]["src/0_development/installer/installer_app.lua"]["id"] = "WRONG_ID"
            # 2. Add orphan file entry not in manifest
            data["files"]["src/1_control/vas/ghost.lua"] = {
                "id": "ID_GHOST",
                "name": "ghost.lua",
                "repoPath": "src/1_control/vas/ghost.lua",
                "category": "packages",
                "sizeBytes": 10,
                "sha256": "e" * 64,
                "downloadUrl": "https://drive.usercontent.google.com/download?id=ID_GHOST&export=download&confirm=t",
            }
            map_path.write_text(json.dumps(data, indent=2), encoding="utf-8")

            report = verify_workspace(root)
            self.assertFalse(report.ok)
            self.assertTrue(
                any("BOOTSTRAP_GDRIVE_ID_MISMATCH" in e for e in report.errors),
                f"Expected BOOTSTRAP_GDRIVE_ID_MISMATCH, got: {report.errors}",
            )
            self.assertTrue(
                any("ORPHAN_GDRIVE_MAPPING" in e and "ghost.lua" in e for e in report.errors),
                f"Expected ORPHAN_GDRIVE_MAPPING, got: {report.errors}",
            )

    def test_cli_returns_zero_on_live_workspace(self) -> None:
        cli_path = WORKSPACE_ROOT / "tools" / "verify_manifest_sync.py"
        res = subprocess.run(
            [sys.executable, str(cli_path)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            cwd=str(WORKSPACE_ROOT),
        )
        self.assertEqual(res.returncode, 0, f"CLI failed:\n{res.stdout}\n{res.stderr}")
        self.assertIn("0 Errors, 0 Warnings", res.stdout)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the unit test to verify it fails**

Run: `python -m unittest tests/harness/test_manifest_sync_verifier.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'tools.verify_manifest_sync'`

- [ ] **Step 3: Implement `tools/verify_manifest_sync.py`**

Implement `tools/verify_manifest_sync.py` with the following exact constants, parsers, and checks:
- **Constants**:
  - `ALLOWED_MODULE_CATEGORIES = {"development", "infra", "control", "guidance", "planning", "mission"}`
  - `LAYER_TO_CATEGORY = {"0_development": "development", "0_infra": "infra", "1_control": "control", "2_guidance": "guidance", "3_planning": "planning", "4_mission": "mission"}`
  - `ALLOWED_GDRIVE_CATEGORIES = {"installer", "bootstrap", "shared", "packages"}`
  - `INSTALLER_ENTRY_EXEMPTIONS = {"src/0_development/installer/installer.lua", "src/0_development/installer/main.lua"}`
  - `DEFERRED_SUBSYSTEM_DIRS = {"src/1_control/asa"}`
- **Lua Table Block Parser Helpers**:
  - `extract_balanced_braces(text: str, start_idx: int) -> str`: scans from opening `{` at or after `start_idx` and returns the balanced `{ ... }` substring (ignoring braces inside quoted strings or `--` single-line comments).
  - `parse_bootstrap_entries(lua_text: str) -> List[Dict[str, Optional[str]]]`: extracts `{ repoPath = "...", cacheRelPath = "...", gdriveId = ... }` entries from `BOOTSTRAP_FILES = { ... }`.
  - `parse_manifest(manifest_path: Path) -> Dict[str, Any]`:
    - Extracts `bootstrap_files` (`BOOTSTRAP_FILES`), `shared_libs` (`SHARED_LIBS`), `module_order` (`MODULE_ORDER`), and `modules` (`MODULES`).
    - For each top-level key `<mod_key> = { ... }` inside `manifest.MODULES = { ... }`:
      - Parses `id`, `name`, `category`, `version`, `installDir`.
      - Parses `files` list (`{ repoPath = "...", dest = "...", gdriveId = ... }`).
      - Parses `defaultConfigs` keys (`["/path/to/cfg.json"]`) and `configTemplate` `targetPath` if present.
- **Verification Checks in `verify_workspace(workspace_root: Path, strict_gdrive_packages: bool = False) -> VerificationReport`**:
  1. **Installer Root & Mirror Parity**:
     - Verify `installer.lua` and `src/0_development/installer/installer.lua` exist and are byte-for-byte identical (`INSTALLER_BYTE_PARITY_MISMATCH`).
     - Verify `installer.lua` `BOOTSTRAP_FILES` matches `manifest.lua` `BOOTSTRAP_FILES` in order, `repoPath`, `cacheRelPath`, and `gdriveId` (`INSTALLER_BOOTSTRAP_LIST_MISMATCH`).
  2. **Manifest Internal & Category Integrity**:
     - Compare `module_order` against `modules.keys()`: flag `MODULE_ORDER_MISMATCH` if any module is in `MODULE_ORDER` but not `MODULES`, in `MODULES` but not `MODULE_ORDER`, or duplicated in `MODULE_ORDER`.
     - For each module `mod_key, mod_info`:
       - Verify `mod_info["id"] == mod_key` (`MODULE_ID_MISMATCH`).
       - Verify `mod_info["category"] in ALLOWED_MODULE_CATEGORIES` (`INVALID_MODULE_CATEGORY`).
       - Verify every module includes `src/0_development/sensors/avionics_sensors.lua` (`dest = "/lib/avionics_sensors.lua"`) in `mod_info["files"]` (`MISSING_SHARED_SENSOR_LIB`).
       - For primary module files (excluding `src/0_development/sensors/avionics_sensors.lua`), verify the `src/<layer>/` prefix maps via `LAYER_TO_CATEGORY` to `mod_info["category"]` (`INVALID_MODULE_CATEGORY`).
  3. **Manifest $\leftrightarrow$ `src/` Bidirectional File Parity**:
     - Collect all `repoPath` strings across `bootstrap_files`, `shared_libs`, and `modules[*].files`.
     - For each `repoPath`, verify `(workspace_root / repoPath).is_file()`; if missing, append `MISSING_DISK_FILE: <repoPath>`.
     - If any directory in `DEFERRED_SUBSYSTEM_DIRS` now has files registered in `manifest.lua`, append `STALE_DEFERRED_EXEMPTION: <dir>`.
     - Walk `(workspace_root / "src").rglob("*")` for files:
       - Ignore `.gitkeep` and `README.md`.
       - For `.lua` files:
         - Skip if in `registered_repo_paths` or `INSTALLER_ENTRY_EXEMPTIONS`.
         - Skip if under any directory in `DEFERRED_SUBSYSTEM_DIRS`.
         - Skip if file name matches `^node_[a-z0-9_]+\.lua$` (multi-node simulation harness fixture scripts).
         - Otherwise append `ORPHAN_SRC_FILE: <rel_path> is not registered in manifest.lua`.
       - For `.json` files:
         - Skip if in `registered_repo_paths` or under `DEFERRED_SUBSYSTEM_DIRS`.
         - Check if `<rel_path>` matches `src/<layer>/<subsys>/<rest_rel>` where `/" + <rest_rel>` is registered in `defaultConfigs` or `configTemplate` of a module belonging to `<subsys>`.
         - Otherwise append `ORPHAN_SRC_CONFIG_FILE: <rel_path> is not registered in manifest.lua files or defaultConfigs`.
  4. **`config/gdrive_mapping.json` 3-Way Parity**:
     - Load `config/gdrive_mapping.json` (flag `MISSING_GDRIVE_MAPPING_FILE` if absent).
     - Build expected role category map for all distributable files:
       - `"installer.lua"` $\to$ `"installer"`
       - `bootstrap_files` $\to$ `"bootstrap"`
       - `shared_libs` $\to$ `"shared"`
       - remaining `modules[*].files` $\to$ `"packages"`
     - Verify required core files (`"installer.lua"`, all `bootstrap_files`, all `shared_libs`) exist in both `mapping["files"]` and `mapping["bootstrapMap"]` with non-empty `id` (`MISSING_REQUIRED_GDRIVE_MAPPING`).
     - For each `b_entry` in `manifest.bootstrap_files`:
       - Verify `b_entry["gdriveId"]` equals `mapping["files"][repo_p]["id"]` and `mapping["bootstrapMap"][repo_p]` (`BOOTSTRAP_GDRIVE_ID_MISMATCH`).
     - For each `repo_p, file_meta` in `mapping["files"].items()`:
       - Verify `(workspace_root / repo_p).is_file()` and `repo_p in expected_category_by_path` (`ORPHAN_GDRIVE_MAPPING`).
       - Verify `file_meta.get("repoPath") == repo_p` (`GDRIVE_REPO_PATH_MISMATCH`).
       - Verify `file_meta.get("category") in ALLOWED_GDRIVE_CATEGORIES` and `file_meta.get("category") == expected_category_by_path.get(repo_p)` (`INVALID_GDRIVE_CATEGORY`).
       - Verify `file_meta.get("id")` is a non-empty string and `f"id={file_meta.get('id')}"` is in `file_meta.get("downloadUrl", "")` (`INVALID_GDRIVE_METADATA`).
     - For each `repo_p, bid` in `mapping["bootstrapMap"].items()`:
       - Verify `repo_p in mapping["files"]` and `mapping["files"][repo_p].get("id") == bid` (`BOOTSTRAP_GDRIVE_ID_MISMATCH`).
     - If `strict_gdrive_packages` is `True`, verify every `repoPath` in `expected_category_by_path` is present in `mapping["files"]` (`UNMAPPED_PACKAGE_FILE`).

- [ ] **Step 4: Run the unit tests and CLI to verify pass**

Run:
```powershell
python -m unittest tests/harness/test_manifest_sync_verifier.py -v; if ($?) { python tools/verify_manifest_sync.py }
```
Expected: `6/6 PASS` in `test_manifest_sync_verifier.py` and `0 Errors, 0 Warnings` from `python tools/verify_manifest_sync.py`.

- [ ] **Step 5: Commit Task 1**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tools/verify_manifest_sync.py tests/harness/test_manifest_sync_verifier.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(tools): implement 3-way manifest, GDrive map, and src tree verifier (TASK-012-1)"
```

---

### Task 2: Integrate into Standard Verification Pipeline & Sync Living Context (`TASK-012-2`)

**Files:**
- Modify: `tests/harness/test_tools_integrity.py:15-115`
- Modify: `TASK.md:44-50`
- Modify: `GEMINI.md:1-50`

**Interfaces:**
- Consumes: `tools/verify_manifest_sync.py`
- Produces:
  - `TestToolsIntegrity.test_verify_manifest_sync_execution` in `tests/harness/test_tools_integrity.py`
  - Updated standard verification one-liner in `GEMINI.md` and completed `TASK-012` entry in `TASK.md`.

- [ ] **Step 1: Write the failing test in `tests/harness/test_tools_integrity.py`**

Add `WORKSPACE_ROOT / "tools" / "verify_manifest_sync.py"` to `expected_tools` in `test_tools_exist_and_scratch_is_clean` and append:
```python
    def test_verify_manifest_sync_execution(self) -> None:
        script = WORKSPACE_ROOT / "tools" / "verify_manifest_sync.py"
        result = subprocess.run(
            [sys.executable, str(script)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=str(WORKSPACE_ROOT),
            timeout=30,
        )
        self.assertEqual(
            result.returncode,
            0,
            f"tools/verify_manifest_sync.py exited with non-zero code {result.returncode}.\nOutput:\n{result.stdout}\nError:\n{result.stderr}",
        )
        self.assertIn("0 Errors, 0 Warnings", result.stdout)
```

- [ ] **Step 2: Run the full harness test discovery to verify pass**

Run: `python -m unittest discover -s tests/harness -p "test_*.py"`
Expected: `48/48 PASS` (41 existing + 6 in `test_manifest_sync_verifier.py` + 1 in `test_tools_integrity.py`).

- [ ] **Step 3: Update `TASK.md`, `GEMINI.md`, and `.agent/memory/workspace-root.md`**

In `TASK.md`:
- Mark `TASK-012`, `TASK-012-1`, and `TASK-012-2` as `[x]` and move `TASK-012` to the top of `## ✅ 3. 완료된 작업 이력` (pruning the 11th oldest entry to maintain the 10-item cap).

In `GEMINI.md` (strictly $\le 80$ lines):
- Update `직전 완료` to `TASK-012`.
- Add `tools/verify_manifest_sync.py` to `## 2. Confirmed Architecture & Paths` and `## 3. Standard Commands`, and update the harness regression count (`48/48 PASS`).

In `.agent/memory/workspace-root.md`:
- Append the `TASK-012` completion entry with verification metrics.

- [ ] **Step 4: Run full project static and regression verification pipeline**

Run:
```powershell
python tools/verify_manifest_sync.py; if ($?) { python tools/verify_all_specs.py }; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/validate_lua_syntax.py }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }
```
Expected:
- `verify_manifest_sync.py`: `0 Errors, 0 Warnings`
- `verify_all_specs.py`: `0 Errors, 0 Warnings`
- `verify_spec_status.py`: `9 Implemented, 5 Approved`
- `validate_lua_syntax.py`: `126 files passed Lua 5.2 compilation`
- `unittest`: `48/48 PASS`

- [ ] **Step 5: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tests/harness/test_tools_integrity.py TASK.md GEMINI.md .agent/memory/workspace-root.md docs/superpowers/plans/2026-11-10-task-012-manifest-sync-verifier.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "chore(ci): integrate verify_manifest_sync.py into harness pipeline and close TASK-012"
```
