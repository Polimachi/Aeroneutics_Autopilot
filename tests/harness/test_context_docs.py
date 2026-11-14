from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOLS_DIR = REPO_ROOT / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import verify_context_docs as vcd


class TestSingleDocRules(unittest.TestCase):
    def test_readme_counts_flags_pass_ratio(self) -> None:
        f = vcd.check_readme_counts("x\n단위 `294/294 PASS`\n")
        self.assertEqual([(x.rule, x.line) for x in f], [("R1", 2)])

    def test_readme_counts_ignores_dates_and_paths(self) -> None:
        self.assertEqual(vcd.check_readme_counts("2026/11/10 a/b c 12/34"), [])

    def test_overclaim_reports_longest_term_once(self) -> None:
        f = vcd.check_overclaim("세계 최고 수준 달성\n", "TASK.md")
        self.assertEqual(len(f), 1)
        self.assertIn("세계 최고 수준", f[0].message)

    def test_overclaim_guarantee_case_insensitive(self) -> None:
        self.assertEqual(len(vcd.check_overclaim("We GUARANTEED it", "README.md")), 1)

    def test_gemini_structure_line_cap(self) -> None:
        body = "\n".join(vcd.GEMINI_SECTIONS) + "\n" + "x\n" * 80
        self.assertEqual([x.rule for x in vcd.check_gemini_structure(body)], ["R3"])

    def test_gemini_structure_section_mismatch(self) -> None:
        body = "## 1. Current Phase & Active Handover\n## 3. Standard Commands\n"
        self.assertEqual(len(vcd.check_gemini_structure(body)), 1)

    def test_markers_open_parent_with_done_child(self) -> None:
        t = "- [ ] **TASK-114: x**\n  - [x] **TASK-114-1**: a\n  - [ ] **TASK-114-2**: b\n"
        f = vcd.check_task_markers(t)
        self.assertEqual([(x.rule, x.line) for x in f], [("R6", 1)])

    def test_markers_closed_parent_with_open_child(self) -> None:
        t = "- [x] **TASK-009: x**\n    - [ ] **TASK-009-1**: a\n"
        self.assertEqual(len(vcd.check_task_markers(t)), 1)

    def test_markers_deferred_parent_and_in_progress_ok(self) -> None:
        t = "- [ ] **[연기] TASK-104: x**\n- [-] **TASK-201: y**\n  - [x] **TASK-201-1**: a\n"
        self.assertEqual(vcd.check_task_markers(t), [])

    def test_markers_crlf_input(self) -> None:
        t = "- [ ] **TASK-114: x**\r\n  - [x] **TASK-114-1**: a\r\n"
        self.assertEqual([x.line for x in vcd.check_task_markers(t)], [1])

    def test_archive_cap(self) -> None:
        items = "".join(f"- [x] **TASK-{i:03d}: t**\n" for i in range(11))
        t = "## ✅ 3. 완료\n" + items + "## 4. other\n- [x] **TASK-999: z**\n"
        self.assertEqual([x.rule for x in vcd.check_task_archive_cap(t)], ["R7"])
        self.assertEqual(len(vcd.archived_task_ids(t)), 11)


SPEC = "| **문서 상태 (Status)** | `Implemented` |\n| **문서 버전 (Version)** | `v1.15.0` |\n"


class TestCrossRefRules(unittest.TestCase):
    def _repo(self, tmp: str) -> Path:
        root = Path(tmp)
        d = root / "docs/specs/2_guidance/fcp"
        d.mkdir(parents=True)
        (d / "FCP.md").write_text(SPEC, encoding="utf-8")
        (root / "docs/system").mkdir(parents=True)
        return root

    def test_spec_version_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = self._repo(tmp)
            t = "- **사양서 상태**: `docs/specs/2_guidance/fcp/FCP.md` (v1.16.0 Approved)\n"
            rules = [(x.rule, x.line) for x in vcd.check_task_spec_versions(t, root)]
            self.assertEqual(rules, [("R5", 1), ("R5", 1)])

    def test_spec_version_current_prefix_ok(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = self._repo(tmp)
            t = "`docs/specs/2_guidance/fcp/FCP.md` (현재 v1.15.0 Implemented → 목표 v1.16.0 Approved)\n"
            self.assertEqual(vcd.check_task_spec_versions(t, root), [])

    def test_spec_version_missing_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = self._repo(tmp)
            f = vcd.check_task_spec_versions("`docs/specs/x/NOPE.md` (v1.0.0)\n", root)
            self.assertEqual(len(f), 1)
            self.assertIn("missing spec file", f[0].message)

    def test_gemini_distribution(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = self._repo(tmp)
            self.assertEqual(
                vcd.check_gemini_spec_distribution("(1 Implemented, 0 Approved)", root),
                [],
            )
            self.assertEqual(
                len(vcd.check_gemini_spec_distribution("(2 Implemented, 0 Approved)", root)),
                1,
            )
            self.assertEqual(
                len(vcd.check_gemini_spec_distribution("no counts", root)),
                1,
            )

    def test_memory_coverage(self) -> None:
        t = "## ✅ 3. 완료\n- [x] **TASK-009: a**\n- [x] **TASK-116: b**\n"
        mem = {"workspace-root.md": "## 2026-11-10 — 인스톨러 개편 (TASK-116)\n본문 TASK-009\n"}
        f = vcd.check_memory_coverage(t, mem)
        self.assertEqual([x.rule for x in f], ["R8"])
        self.assertIn("TASK-009", f[0].message)

    def test_readme_sync_detects_tree_and_count_drift(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "docs/specs/0_development/alignment").mkdir(parents=True)
            (root / "docs/specs/0_development/fdr").mkdir(parents=True)
            (root / "src/0_development/alignment").mkdir(parents=True)
            (root / "src/0_development/fdr").mkdir(parents=True)
            (root / "tests/0_development/alignment").mkdir(parents=True)
            (root / "tests/e2e").mkdir(parents=True)
            (root / "tests/e2e/test_e2e_one.lua").write_text(
                'describe("x", function()\n  it("a", function() end)\n  it("b", function() end)\nend)\n',
                encoding="utf-8",
            )
            (root / "tools").mkdir(parents=True)
            (root / "tools/a.py").write_text("", encoding="utf-8")
            (root / "tools/b.py").write_text("", encoding="utf-8")
            (root / "tools/verify_all_specs.py").write_text(
                'SPEC_FILES = ["docs/specs/0_development/alignment/A.md"]\n',
                encoding="utf-8",
            )
            (root / "docs/specs/0_development/alignment/A.md").write_text(SPEC, encoding="utf-8")

            readme = (
                "```text\n"
                "Create_Aeroneutics/\n"
                "├── docs/\n"
                "│   └── specs/\n"
                "│       └── 0_development/ # desc (alignment)\n"
                "├── src/\n"
                "│   ├── 0_development/alignment/\n"
                "│   └── 0_infra/ghost/\n"
                "├── tests/\n"
                "│   ├── 0_development/alignment/\n"
                "│   └── e2e/\n"
                "└── tools/\n"
                "    ├── a.py\n"
                "    └── verify_all_specs.py # 2대 사양서\n"
                "```\n"
                "0개 통합 시뮬레이션 스위트(1개 케이스)\n"
                "활성 사양서 3종 (2 Implemented, 1 Approved)\n"
            )
            findings = vcd.check_readme_sync(readme, root)
            msgs = "\n".join(x.message for x in findings)
            self.assertTrue(all(x.rule == "R9" for x in findings))
            self.assertNotIn("0_development/alignment", msgs)
            self.assertIn("0_development/fdr", msgs)
            self.assertIn("0_infra/ghost", msgs)
            self.assertIn("b.py", msgs)
            self.assertIn("E2E", msgs)
            self.assertIn("2대", msgs)
            self.assertIn("3종", msgs)

    def test_readme_sync_passes_with_brace_and_paren_expansion(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for d in (
                "docs/specs/0_development/alignment",
                "docs/specs/0_development/fdr",
                "src/0_development/alignment",
                "src/0_development/fdr",
                "tests/0_infra/gac",
                "tests/0_infra/gps",
                "tests/e2e",
                "tools",
            ):
                (root / d).mkdir(parents=True)
            (root / "docs/specs/0_development/alignment/A.md").write_text(SPEC, encoding="utf-8")
            (root / "tests/e2e/test_e2e_one.lua").write_text(
                'it("a", function() end)\nit("b", function() end)\n', encoding="utf-8"
            )
            (root / "tools/verify_all_specs.py").write_text(
                'SPEC_FILES = ["docs/specs/0_development/alignment/A.md"]\n',
                encoding="utf-8",
            )
            readme = (
                "Phase 0: 12대 사양서 개편, TASK-013: 8대 사양서 승격\n"
                "```text\n"
                "Create_Aeroneutics/\n"
                "├── docs/\n"
                "│   └── specs/\n"
                "│       └── 0_development/ # 사양서 (alignment, fdr)\n"
                "├── src/\n"
                "│   └── 0_development/ # 코드 (alignment, fdr)\n"
                "├── tests/\n"
                "│   ├── 0_infra/{gac, gps}/\n"
                "│   └── e2e/\n"
                "└── tools/\n"
                "    └── verify_all_specs.py # 1대 사양서\n"
                "```\n"
                "1개 통합 시뮬레이션 스위트(2개 케이스)\n"
                "1대 활성 사양서 / 활성 사양서 1종 (1 Implemented, 0 Approved)\n"
            )
            self.assertEqual(vcd.check_readme_sync(readme, root), [])


class TestRepositoryBaseline(unittest.TestCase):
    def test_repository_has_no_context_drift(self) -> None:
        findings = vcd.run_all(REPO_ROOT)
        self.assertEqual(findings, [], "\n".join(x.format() for x in findings))

    def test_cli_json_exit_code(self) -> None:
        r = subprocess.run(
            [sys.executable, str(REPO_ROOT / "tools/verify_context_docs.py"), "--json"],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertEqual(json.loads(r.stdout), [])


if __name__ == "__main__":
    unittest.main()
