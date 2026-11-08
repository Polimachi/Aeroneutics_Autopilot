"""
Integrity and regression tests for Create_Aeroneutics developer tools and scratch directory.
"""
from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent.parent


class TestToolsIntegrity(unittest.TestCase):
    def test_tools_exist_and_scratch_is_clean(self) -> None:
        expected_tools = [
            WORKSPACE_ROOT / "tools" / "verify_all_specs.py",
            WORKSPACE_ROOT / "tools" / "validate_lua_syntax.py",
            WORKSPACE_ROOT / "tools" / "verify_spec_status.py",
            WORKSPACE_ROOT / "tools" / "run_unit_tests.py",
        ]
        for tool_path in expected_tools:
            self.assertTrue(
                tool_path.is_file(),
                f"Required tool file missing: {tool_path}",
            )

        scratch_dir = WORKSPACE_ROOT / "scratch"
        self.assertTrue(scratch_dir.is_dir(), f"scratch/ directory missing: {scratch_dir}")
        remaining_items = [
            p.name for p in scratch_dir.iterdir()
            if p.name != "__pycache__"
        ]
        self.assertEqual(
            remaining_items,
            ["README.md"],
            f"scratch/ contains unexpected files (only README.md permitted): {remaining_items}",
        )

    def test_verify_all_specs_execution(self) -> None:
        script = WORKSPACE_ROOT / "tools" / "verify_all_specs.py"
        result = subprocess.run(
            [sys.executable, str(script)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=str(WORKSPACE_ROOT),
            timeout=60,
        )
        self.assertEqual(
            result.returncode,
            0,
            f"tools/verify_all_specs.py exited with non-zero code {result.returncode}.\nOutput:\n{result.stdout}\nError:\n{result.stderr}",
        )
        self.assertIn("0 Errors, 0 Warnings", result.stdout)

    def test_verify_spec_status_execution(self) -> None:
        script = WORKSPACE_ROOT / "tools" / "verify_spec_status.py"
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
            f"tools/verify_spec_status.py exited with non-zero code {result.returncode}.\nOutput:\n{result.stdout}\nError:\n{result.stderr}",
        )
        self.assertIn("specs have valid statuses", result.stdout)

    def test_validate_lua_syntax_execution(self) -> None:
        script = WORKSPACE_ROOT / "tools" / "validate_lua_syntax.py"
        result = subprocess.run(
            [sys.executable, str(script)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=str(WORKSPACE_ROOT),
            timeout=60,
        )
        self.assertEqual(
            result.returncode,
            0,
            f"tools/validate_lua_syntax.py exited with non-zero code {result.returncode}.\nOutput:\n{result.stdout}\nError:\n{result.stderr}",
        )
        self.assertIn("passed Lua 5.2 compilation", result.stdout)

    def test_all_subsystem_readmes_have_valid_relative_links(self) -> None:
        script = WORKSPACE_ROOT / "tools" / "verify_all_specs.py"
        result = subprocess.run(
            [sys.executable, str(script), "--check-readmes"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=str(WORKSPACE_ROOT),
            timeout=60,
        )
        self.assertEqual(
            result.returncode,
            0,
            f"tools/verify_all_specs.py --check-readmes exited with non-zero code {result.returncode}.\nOutput:\n{result.stdout}\nError:\n{result.stderr}",
        )
        self.assertIn("README audit complete: 0 error(s)", result.stdout)


if __name__ == "__main__":
    unittest.main()
