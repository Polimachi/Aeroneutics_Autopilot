"""
Unit test for tools/run_e2e_tests.py CLI runner.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.run_e2e_tests import build_arg_parser, run_e2e_cli


class TestE2ERunner(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = Path(__file__).resolve().parents[2]

    def test_e2e_arg_parser(self) -> None:
        parser = build_arg_parser()
        args = parser.parse_args(["--filter", "bootstrap", "--json", "--clean-orphans"])
        self.assertEqual(args.filter, "bootstrap")
        self.assertTrue(args.json)
        self.assertTrue(args.clean_orphans)

    def test_e2e_cli_runner_with_no_e2e_tests_yet(self) -> None:
        # Before e2e tests exist, run_e2e_cli should handle cleanly (SKIP or 0 tests)
        code, report = run_e2e_cli(["--json"], workspace_root=self.repo_root)
        self.assertEqual(code, 0)
        self.assertIn("suites", report)


if __name__ == "__main__":
    unittest.main()
