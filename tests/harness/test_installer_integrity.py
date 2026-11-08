"""
Integrity tests for Create_Aeroneutics Unified Installer root script and manifest.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

from harness.unit.config import resolve_craftos_paths
from harness.unit.static_guard import Lua52SyntaxChecker, scan_lua_source

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent.parent


class TestInstallerIntegrity(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        paths = resolve_craftos_paths()
        cls.checker = Lua52SyntaxChecker(paths.lua52_dll)

    def test_installer_byte_parity_between_root_and_src(self) -> None:
        root_installer = WORKSPACE_ROOT / "installer.lua"
        src_installer = WORKSPACE_ROOT / "src" / "0_development" / "installer" / "installer.lua"

        self.assertTrue(root_installer.exists(), f"Repo-root installer missing: {root_installer}")
        self.assertTrue(src_installer.exists(), f"Source installer missing: {src_installer}")

        root_bytes = root_installer.read_bytes()
        src_bytes = src_installer.read_bytes()
        self.assertEqual(
            root_bytes,
            src_bytes,
            "installer.lua at repository root must be 100% byte-for-byte identical to src/0_development/installer/installer.lua",
        )

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
