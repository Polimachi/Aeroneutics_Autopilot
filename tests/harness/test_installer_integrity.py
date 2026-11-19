"""
Integrity tests for Create_Aeroneutics Unified Installer root script and manifest.
"""
from __future__ import annotations

import re
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from harness.unit.config import UnitTargetConfig, resolve_craftos_paths
from harness.unit.engine import run_target_unit_tests
from harness.unit.session import CraftOSSessionResult
from harness.unit.static_guard import (
    Lua52SyntaxChecker,
    scan_lua_source,
    strip_lua_comments_and_strings,
)

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent.parent


class TestInstallerIntegrity(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        paths = resolve_craftos_paths()
        cls.checker = Lua52SyntaxChecker(paths.lua52_dll)

    def test_root_installer_is_single_source_and_no_duplicate_exists(self) -> None:
        root_installer = WORKSPACE_ROOT / "installer.lua"
        src_installer = WORKSPACE_ROOT / "src" / "0_development" / "installer" / "installer.lua"
        manifest_path = (
            WORKSPACE_ROOT / "src" / "0_development" / "installer" / "modules" / "manifest.lua"
        )

        self.assertTrue(root_installer.is_file(), f"Repo-root installer missing: {root_installer}")
        self.assertFalse(
            src_installer.exists(),
            f"Duplicate installer copy must not exist: {src_installer}",
        )
        self.assertTrue(manifest_path.is_file(), f"Manifest missing: {manifest_path}")
        manifest_code, _ = strip_lua_comments_and_strings(
            manifest_path.read_text(encoding="utf-8")
        )
        self.assertIsNone(
            re.search(r"\bBOOTSTRAP_FILES\s*=\s*\{", manifest_code),
            "manifest.lua must not define BOOTSTRAP_FILES (root /installer.lua is SSOT)",
        )

    @patch("harness.unit.engine.EphemeralCraftOSSession")
    def test_unit_engine_stages_root_installer_for_installer_target(
        self, mock_session_cls: MagicMock
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ws = Path(tmp)
            sentinel = "-- root installer SSOT sentinel\nreturn { BOOTSTRAP_FILES = {} }\n"
            (ws / "installer.lua").write_text(sentinel, encoding="utf-8")
            src_dir = ws / "src" / "0_development" / "installer"
            tests_dir = ws / "tests" / "0_development" / "installer"
            src_dir.mkdir(parents=True)
            tests_dir.mkdir(parents=True)
            (src_dir / "main.lua").write_text('return require("installer")\n', encoding="utf-8")
            (tests_dir / "test_stub.lua").write_text(
                'describe("stub", function() it("ok", function() assert_true(true) end) end)\n',
                encoding="utf-8",
            )

            comp_dir = ws / "comp0"
            comp_dir.mkdir()
            mock_session = MagicMock()
            mock_session_cls.return_value.__enter__.return_value = mock_session
            mock_session.computer_dir.return_value = comp_dir

            def _copy_tree(src_root: Path, computer_id: int = 0, dest_subdir: str = "") -> None:
                dest = comp_dir / dest_subdir if dest_subdir else comp_dir
                shutil.copytree(src_root, dest, dirs_exist_ok=True)

            mock_session.stage_tree.side_effect = _copy_tree
            mock_session.run.return_value = CraftOSSessionResult(
                session_id="unit_inst_stage",
                exit_code=0,
                timed_out=False,
                duration_ms=10.0,
                stdout_raw="",
                stderr_raw="",
                guest_result={"suites": [], "logs": [], "errors": []},
            )

            target = UnitTargetConfig(
                target_id="0_development/installer",
                source_dir=src_dir,
                tests_dir=tests_dir,
            )
            fake_paths = resolve_craftos_paths()
            run_target_unit_tests(target, fake_paths, ws / "sessions")

            staged_installer = comp_dir / "installer.lua"
            self.assertTrue(staged_installer.is_file(), "Root installer.lua was not staged into c0")
            self.assertEqual(staged_installer.read_text(encoding="utf-8"), sentinel)

    def test_repo_root_installer_passes_static_guard_and_lua52_syntax(self) -> None:
        root_installer = WORKSPACE_ROOT / "installer.lua"
        self.assertTrue(root_installer.exists(), f"Repo-root installer missing: {root_installer}")

        code = root_installer.read_text(encoding="utf-8")
        issues = scan_lua_source(code, "installer.lua", self.checker)
        self.assertEqual(
            issues,
            [],
            f"Static guard or Lua 5.2 syntax violations found in {root_installer}: {issues}",
        )

    def test_all_manifest_repo_paths_exist_on_disk(self) -> None:
        manifest_path = (
            WORKSPACE_ROOT
            / "src"
            / "0_development"
            / "installer"
            / "modules"
            / "manifest.lua"
        )
        self.assertTrue(manifest_path.exists(), f"Manifest missing: {manifest_path}")

        content = manifest_path.read_text(encoding="utf-8")
        pattern = re.compile(r'repoPath\s*=\s*["\']([^"\']+)["\']')
        repo_paths = pattern.findall(content)
        self.assertGreater(
            len(repo_paths),
            0,
            "Manifest must define at least one repoPath file",
        )

        missing_files = []
        for rel_path in repo_paths:
            full_path = WORKSPACE_ROOT / rel_path
            if not full_path.exists():
                missing_files.append(rel_path)

        self.assertEqual(
            missing_files,
            [],
            f"The following repoPath files in manifest.lua do not exist on disk: {missing_files}",
        )

    def test_legacy_gps_installer_removed(self) -> None:
        legacy_installer = WORKSPACE_ROOT / "src" / "0_infra" / "gps" / "installer.lua"
        legacy_installer_core = (
            WORKSPACE_ROOT / "src" / "0_infra" / "gps" / "modules" / "installer_core.lua"
        )
        self.assertFalse(
            legacy_installer.exists(),
            f"Legacy GPS installer must be deleted: {legacy_installer}",
        )
        self.assertFalse(
            legacy_installer_core.exists(),
            f"Legacy GPS installer_core must be deleted: {legacy_installer_core}",
        )


if __name__ == "__main__":
    unittest.main()
