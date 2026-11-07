import tempfile
import unittest
from pathlib import Path

from harness.unit.config import UnitTargetConfig, resolve_craftos_paths
from harness.unit.engine import run_target_unit_tests


class TestRunnerIsolationAndProfiler(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.paths = resolve_craftos_paths()

    def _make_target(self, root: Path, src_files: dict[str, str], test_files: dict[str, str], budget: int = 50000) -> UnitTargetConfig:
        sdir = root / "src" / "1_control" / "demo"
        tdir = root / "tests" / "1_control" / "demo"
        sdir.mkdir(parents=True)
        tdir.mkdir(parents=True)
        for rel, body in src_files.items():
            p = sdir / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(body, encoding="utf-8")
        for rel, body in test_files.items():
            p = tdir / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(body, encoding="utf-8")
        return UnitTargetConfig(
            target_id="1_control/demo",
            source_dir=sdir,
            tests_dir=tdir,
            max_instructions_per_tick=budget,
        )

    def test_global_and_module_mutations_restore_even_after_test_crash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = self._make_target(
                root,
                {"modules/dep.lua": 'return { kind = "REAL" }\n'},
                {
                    "test_01_pollute.lua": (
                        'describe("polluter", function()\n'
                        '    it("mutates _G.term and package.loaded then crashes", function()\n'
                        '        _G.term = { broken = true }\n'
                        '        sdk.mock_module("dep", { kind = "STUB" })\n'
                        '        error("boom")\n'
                        '    end)\n'
                        'end)\n'
                    ),
                    "test_02_clean.lua": (
                        'describe("subsequent suite", function()\n'
                        '    it("sees restored _G.term and real dep module", function()\n'
                        '        assert_true(type(_G.term.getSize) == "function")\n'
                        '        assert_eq(_G.term.broken, nil)\n'
                        '        local dep = require("dep")\n'
                        '        assert_eq(dep.kind, "REAL")\n'
                        '    end)\n'
                        'end)\n'
                    ),
                },
            )
            rep = run_target_unit_tests(target, self.paths, root / "sessions")
            self.assertEqual(rep.passed_tests, 1)
            self.assertEqual(rep.failed_tests, 1)
            self.assertEqual(rep.tests[1].status, "PASS", rep.tests[1].error)

    def test_instruction_budget_and_event_swallow_guards(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = self._make_target(
                root,
                {"main.lua": "return true\n"},
                {
                    "test_guards.lua": (
                        'describe("guards", function()\n'
                        '    it("fails on excessive instruction loop", function()\n'
                        '        local s = 0\n'
                        '        for i = 1, 20000 do s = s + i end\n'
                        '    end)\n'
                        '    it("fails on unauthorized sleep", function()\n'
                        '        sleep(0.05)\n'
                        '    end)\n'
                        '    it("allows queued event pull inside sdk.with_events_allowed", function()\n'
                        '        sdk.with_events_allowed(function()\n'
                        '            os.queueEvent("custom_ping", 42)\n'
                        '            local ev, val = os.pullEvent("custom_ping")\n'
                        '            assert_eq(ev, "custom_ping")\n'
                        '            assert_eq(val, 42)\n'
                        '        end)\n'
                        '    end)\n'
                        'end)\n'
                    )
                },
                budget=5000,
            )
            rep = run_target_unit_tests(target, self.paths, root / "sessions")
            self.assertEqual(rep.tests[0].status, "FAIL")
            self.assertIn("YIELD_BUDGET_EXCEEDED", rep.tests[0].error)
            self.assertEqual(rep.tests[1].status, "FAIL")
            self.assertIn("EVENT_SWALLOW_VIOLATION", rep.tests[1].error)
            self.assertEqual(rep.tests[2].status, "PASS", rep.tests[2].error)

    def test_filter_executes_matching_cases_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = self._make_target(
                root,
                {"main.lua": "return true\n"},
                {
                    "test_filter.lua": (
                        'describe("math", function()\n'
                        '    it("alpha case", function() assert_eq(1, 1) end)\n'
                        '    it("beta case", function() error("should be skipped") end)\n'
                        'end)\n'
                    )
                },
            )
            rep = run_target_unit_tests(target, self.paths, root / "sessions", test_filter="alpha")
            self.assertEqual(rep.status, "PASS")
            self.assertEqual(rep.total_tests, 1)


if __name__ == "__main__":
    unittest.main()
