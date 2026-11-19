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
from unittest.mock import patch

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
            self.assertTrue(
                (tmp_staging / "bootstrap" / "modules" / "manifest.lua").is_file(),
                "Missing bootstrap manifest.lua",
            )

            # Check manifest was created
            manifest_json = tmp_staging / "manifest.json"
            self.assertTrue(manifest_json.is_file(), f"Missing manifest.json: {manifest_json}")
            data = json.loads(manifest_json.read_text(encoding="utf-8"))
            self.assertIn("files", data)
            self.assertEqual(data.get("categories", {}).get("bootstrap"), 7)
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

    def test_package_remote_names_are_collision_free(self) -> None:
        sys.path.insert(0, str(WORKSPACE_ROOT))
        from tools.sync_gdrive import discover_manifest_files  # noqa: E402

        entries = discover_manifest_files()
        pkg_entries = [e for e in entries if e["category"] == "packages"]
        self.assertGreaterEqual(len(pkg_entries), 100)
        remote_names = [e["remoteName"] for e in pkg_entries]
        self.assertEqual(len(remote_names), len(set(remote_names)), "Package remote names must not collide")
        self.assertIn("vas__main.lua", remote_names)
        self.assertIn("gcs__main.lua", remote_names)
        self.assertIn("runway__main.lua", remote_names)

    def test_discover_and_embed_use_root_installer_only(self) -> None:
        sys.path.insert(0, str(WORKSPACE_ROOT))
        import tools.sync_gdrive as sync_gdrive  # noqa: E402

        with tempfile.TemporaryDirectory() as tmp_dir:
            ws = Path(tmp_dir)
            (ws / "src" / "0_development" / "installer" / "modules").mkdir(parents=True)
            (ws / "installer.lua").write_text(
                'bootstrapper.BOOTSTRAP_FILES = {\n'
                '    { repoPath = "src/0_development/installer/installer_app.lua", cacheRelPath = "installer_app.lua", gdriveId = nil },\n'
                '}\n',
                encoding="utf-8",
            )
            (ws / "src" / "0_development" / "installer" / "modules" / "manifest.lua").write_text(
                'local manifest = {}\n'
                'manifest.MODULES = {\n'
                '    vas = {\n'
                '        files = {\n'
                '            { repoPath = "src/1_control/vas/main.lua", dest = "/main.lua", gdriveId = nil },\n'
                '        },\n'
                '    },\n'
                '}\n'
                'return manifest\n',
                encoding="utf-8",
            )

            with patch.object(sync_gdrive, "WORKSPACE_ROOT", ws):
                entries = sync_gdrive.discover_manifest_files()
                boot = [e for e in entries if e["category"] == "bootstrap"]
                self.assertEqual(len(boot), 1)
                self.assertEqual(boot[0]["repoPath"], "src/0_development/installer/installer_app.lua")

                modified = sync_gdrive.embed_bootstrap_ids({
                    "bootstrapMap": {
                        "src/0_development/installer/installer_app.lua": "GID_BOOT_1",
                    },
                    "files": {
                        "src/1_control/vas/main.lua": {"id": "GID_PKG_1"},
                    },
                })
                self.assertEqual(
                    modified,
                    ["installer.lua", "src/0_development/installer/modules/manifest.lua"],
                )
                self.assertIn('gdriveId = "GID_BOOT_1"', (ws / "installer.lua").read_text(encoding="utf-8"))
                self.assertIn(
                    'gdriveId = "GID_PKG_1"',
                    (ws / "src" / "0_development" / "installer" / "modules" / "manifest.lua").read_text(encoding="utf-8"),
                )
                self.assertFalse((ws / "src" / "0_development" / "installer" / "installer.lua").exists())


if __name__ == "__main__":
    unittest.main()
