"""
Unit tests for tools/verify_manifest_sync.py 3-way static consistency verifier.
"""
from __future__ import annotations

import json
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
            "Live workspace failed 3-way manifest sync check:\n" + "\n".join(report.errors),
        )
        self.assertEqual(report.errors, [])
        self.assertGreaterEqual(report.checked_modules, 12)
        self.assertGreaterEqual(report.checked_manifest_files, 80)

    def test_detects_unregistered_orphan_src_lua_and_json_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _build_minimal_workspace(root)
            (root / "src" / "1_control" / "vas" / "modules" / "unregistered_new.lua").write_text(
                "return {}\n", encoding="utf-8"
            )
            (root / "src" / "1_control" / "vas" / "config").mkdir(parents=True)
            (root / "src" / "1_control" / "vas" / "config" / "unknown.json").write_text(
                "{}\n", encoding="utf-8"
            )

            report = verify_workspace(root)
            self.assertFalse(report.ok)
            self.assertTrue(
                any("ORPHAN_SRC_FILE" in e and "unregistered_new.lua" in e for e in report.errors),
                f"Expected ORPHAN_SRC_FILE error, got: {report.errors}",
            )
            self.assertTrue(
                any("ORPHAN_SRC_CONFIG_FILE" in e and "unknown.json" in e for e in report.errors),
                f"Expected ORPHAN_SRC_CONFIG_FILE error, got: {report.errors}",
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
            content = man_path.read_text(encoding="utf-8")
            content = content.replace('category = "control"', 'category = "invalid_cat"')
            content = content.replace('"vas",', '"vas",\n    "ghost_mod",')
            man_path.write_text(content, encoding="utf-8")

            report = verify_workspace(root)
            self.assertFalse(report.ok)
            self.assertTrue(
                any("INVALID_MODULE_CATEGORY" in e for e in report.errors),
                f"Expected INVALID_MODULE_CATEGORY error, got: {report.errors}",
            )
            self.assertTrue(
                any("MODULE_ORDER_MISMATCH" in e and "ghost_mod" in e for e in report.errors),
                f"Expected MODULE_ORDER_MISMATCH error, got: {report.errors}",
            )

    def test_detects_orphan_and_category_and_id_mismatch_in_gdrive_mapping(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _build_minimal_workspace(root)
            map_path = root / "config" / "gdrive_mapping.json"
            data = json.loads(map_path.read_text(encoding="utf-8"))
            # 1. Corrupt bootstrap ID
            data["files"]["src/0_development/installer/installer_app.lua"]["id"] = "WRONG_ID"
            # 2. Corrupt shared category
            data["files"]["src/0_development/sensors/avionics_sensors.lua"]["category"] = "packages"
            # 3. Add orphan file entry not in manifest
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
                any("INVALID_GDRIVE_CATEGORY" in e and "avionics_sensors.lua" in e for e in report.errors),
                f"Expected INVALID_GDRIVE_CATEGORY, got: {report.errors}",
            )
            self.assertTrue(
                any("ORPHAN_GDRIVE_MAPPING" in e and "ghost.lua" in e for e in report.errors),
                f"Expected ORPHAN_GDRIVE_MAPPING, got: {report.errors}",
            )

    def test_detects_stale_deferred_exemption_and_installer_parity_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _build_minimal_workspace(root)
            # Break installer parity
            (root / "installer.lua").write_text("-- modified\n", encoding="utf-8")
            # Register ASA inside manifest while src/1_control/asa is in DEFERRED_SUBSYSTEM_DIRS
            (root / "src" / "1_control" / "asa").mkdir(parents=True)
            (root / "src" / "1_control" / "asa" / "main.lua").write_text("return {}\n", encoding="utf-8")
            man_path = root / "src" / "0_development" / "installer" / "modules" / "manifest.lua"
            content = man_path.read_text(encoding="utf-8")
            content = content.replace('"vas",', '"vas",\n    "asa",')
            content = content.replace(
                "}\nreturn manifest",
                '''    asa = {
        id = "asa",
        name = "ASA",
        category = "control",
        version = "1.0.0",
        installDir = "/",
        files = {
            { repoPath = "src/1_control/asa/main.lua", dest = "/main.lua", gdriveId = nil },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil },
        },
    },
}
return manifest''',
            )
            man_path.write_text(content, encoding="utf-8")

            report = verify_workspace(root)
            self.assertFalse(report.ok)
            self.assertTrue(
                any("INSTALLER_BYTE_PARITY_MISMATCH" in e for e in report.errors),
                f"Expected INSTALLER_BYTE_PARITY_MISMATCH, got: {report.errors}",
            )
            self.assertTrue(
                any("STALE_DEFERRED_EXEMPTION" in e and "src/1_control/asa" in e for e in report.errors),
                f"Expected STALE_DEFERRED_EXEMPTION, got: {report.errors}",
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
