"""
Unit test for tools/run_mutation_tests.py runner integrity.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.run_mutation_tests import MUTATIONS, run_mutation


class TestMutationRunnerIntegrity(unittest.TestCase):
    def test_mutation_definitions_validity(self):
        """Ensure all 20 mutations point to existing files and have valid targets."""
        self.assertGreaterEqual(len(MUTATIONS), 20, "Must define at least 20 mutation operators")
        for mut in MUTATIONS:
            file_path = REPO_ROOT / mut["file"]
            self.assertTrue(file_path.exists(), f"Target file must exist: {mut['file']}")
            content = file_path.read_text(encoding="utf-8")
            self.assertIn(
                mut["target"],
                content,
                f"Target string for {mut['id']} must exist in {mut['file']}",
            )


if __name__ == "__main__":
    unittest.main()
