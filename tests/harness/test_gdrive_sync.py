"""
Unit tests for tools/sync_gdrive.py staging and GDrive synchronization CLI.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent.parent


class TestGDriveSyncCLI(unittest.TestCase):
    def setUp(self) -> None:
        self.cli_path = WORKSPACE_ROOT / "tools" / "sync_gdrive.py"

    def test_cli_exists(self) -> None:
        self.assertTrue(self.cli_path.is_file(), f"CLI missing at {self.cli_path}")

    def test_help_flag_returns_zero(self) -> None:
        result = subprocess.run(
            [sys.executable, str(self.cli_path), "--help"],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("stage", result.stdout)
        self.assertIn("sync", result.stdout)
        self.assertIn("status", result.stdout)
        self.assertIn("verify", result.stdout)

    def test_stage_collects_all_manifest_and_bootstrap_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_staging = Path(tmp_dir) / "dist_gdrive"
            result = subprocess.run(
                [
                    sys.executable,
                    str(self.cli_path),
                    "stage",
                    "--staging-dir",
                    str(tmp_staging),
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
            )
            self.assertEqual(result.returncode, 0, f"Stage failed: {result.stderr}")
            self.assertIn("Staging complete", result.stdout)

            # Check that root installer was staged
            installer_target = tmp_staging / "installer" / "installer.lua"
            self.assertTrue(installer_target.is_file(), f"Missing staged installer: {installer_target}")

            # Check bootstrap files were staged
            bootstrap_app = tmp_staging / "bootstrap" / "installer_app.lua"
            self.assertTrue(bootstrap_app.is_file(), f"Missing bootstrap app: {bootstrap_app}")

            # Check manifest was created
            manifest_json = tmp_staging / "manifest.json"
            self.assertTrue(manifest_json.is_file(), f"Missing manifest.json: {manifest_json}")
            data = json.loads(manifest_json.read_text(encoding="utf-8"))
            self.assertIn("files", data)
            self.assertGreaterEqual(len(data["files"]), 100)

    def test_sync_dry_run(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_staging = Path(tmp_dir) / "dist_gdrive"
            tmp_config = Path(tmp_dir) / "test_mapping.json"
            tmp_config.write_text("{}", encoding="utf-8")

            # Stage first
            subprocess.run(
                [
                    sys.executable,
                    str(self.cli_path),
                    "stage",
                    "--staging-dir",
                    str(tmp_staging),
                ],
                capture_output=True,
                check=True,
            )

            # Run dry-run sync
            result = subprocess.run(
                [
                    sys.executable,
                    str(self.cli_path),
                    "sync",
                    "--staging-dir",
                    str(tmp_staging),
                    "--mapping-file",
                    str(tmp_config),
                    "--dry-run",
                    "--category",
                    "bootstrap",
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
            )
            self.assertEqual(result.returncode, 0, f"Sync dry-run failed: {result.stderr}")
            self.assertIn("[DRY-RUN]", result.stdout)

    def test_verify_command_validates_mapping(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_config = Path(tmp_dir) / "valid_mapping.json"
            mapping = {
                "version": "1.0.0",
                "folderId": "1NgbGjm9YY7lpIlo4sLs32cNE2NwjVVy9",
                "bootstrapMap": {
                    "installer.lua": "ID_00",
                    "src/0_development/installer/installer_app.lua": "ID_01",
                    "src/0_development/installer/modules/manifest.lua": "ID_02",
                    "src/0_development/installer/modules/version_registry.lua": "ID_03",
                    "src/0_development/installer/modules/migration_engine.lua": "ID_04",
                    "src/0_development/installer/modules/startup_generator.lua": "ID_05",
                    "src/0_development/installer/modules/downloader.lua": "ID_06",
                    "src/0_development/installer/modules/tui_view.lua": "ID_07",
                },
                "files": {
                    "installer.lua": {"id": "ID_00"},
                    "src/0_development/installer/installer_app.lua": {"id": "ID_01"},
                    "src/0_development/installer/modules/manifest.lua": {"id": "ID_02"},
                    "src/0_development/installer/modules/version_registry.lua": {"id": "ID_03"},
                    "src/0_development/installer/modules/migration_engine.lua": {"id": "ID_04"},
                    "src/0_development/installer/modules/startup_generator.lua": {"id": "ID_05"},
                    "src/0_development/installer/modules/downloader.lua": {"id": "ID_06"},
                    "src/0_development/installer/modules/tui_view.lua": {"id": "ID_07"},
                }
            }
            tmp_config.write_text(json.dumps(mapping), encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(self.cli_path),
                    "verify",
                    "--mapping-file",
                    str(tmp_config),
                    "--category",
                    "bootstrap",
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
            )
            self.assertEqual(result.returncode, 0, f"Verify failed: {result.stderr}")
            self.assertIn("Verification PASS", result.stdout)


if __name__ == "__main__":
    unittest.main()
