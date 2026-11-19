"""
Tests for E2E simulation node/bus profiling (--profile) and non-interference.
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from harness.unit.config import UnitTargetConfig, resolve_craftos_paths
from harness.unit.engine import run_target_unit_tests
from tools.run_e2e_tests import build_arg_parser, run_e2e_cli


class TestAuditProfiler(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.paths = resolve_craftos_paths()
        cls.repo_root = REPO_ROOT

    def test_e2e_arg_parser_accepts_profile_option(self) -> None:
        parser = build_arg_parser()
        args = parser.parse_args(["--profile", "out/profile.json"])
        self.assertEqual(args.profile, "out/profile.json")

    def test_virtual_bus_and_node_sandbox_collect_profile_when_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            sdir = root / "src" / "0_development" / "prof_test"
            tdir = root / "tests" / "0_development" / "prof_test"
            sdir.mkdir(parents=True)
            tdir.mkdir(parents=True)
            (sdir / "main.lua").write_text("return true\n", encoding="utf-8")

            for sim_name in ("virtual_bus.lua", "node_sandbox.lua"):
                sim_src = self.repo_root / "harness" / "simulation" / sim_name
                (sdir / sim_name).write_text(sim_src.read_text(encoding="utf-8"), encoding="utf-8")

            (tdir / "test_profile.lua").write_text(
                'local virtual_bus = require("virtual_bus")\n'
                'local node_sandbox = require("node_sandbox")\n'
                'describe("audit profiler hooks", function()\n'
                '    it("records node require/call instructions and bus channel byte stats", function()\n'
                '        _G.__AUDIT_PROFILE = { enabled = true, nodes = {}, bus = { channels = {}, edges = {} }, stack = {} }\n'
                '        local bus = virtual_bus.create_bus()\n'
                '        local n1 = node_sandbox.create_node(bus, "NODE_A", "src/a", {\n'
                '            virtual_files = {\n'
                '                ["worker.lua"] = [[\n'
                'local M = {}\n'
                'function M.step(n)\n'
                '    local s = 0\n'
                '    for i = 1, (n or 100) do s = s + i end\n'
                '    return s\n'
                'end\n'
                'return M\n'
                ']],\n'
                '            }\n'
                '        })\n'
                '        local n2 = node_sandbox.create_node(bus, "NODE_B", "src/b", { virtual_files = {} })\n'
                '        n2.modem:open(10002)\n'
                '        local w = n1:require("worker")\n'
                '        local sum = w.step(500)\n'
                '        assert_eq(sum, 125250)\n'
                '        n1.modem:transmit(10002, 10002, { type = "MSG_PING", val = 1 })\n'
                '        n1.modem:transmit(10099, 10099, { type = "MSG_DROP" })\n'
                '        bus:step(0.05)\n'
                '        local prof = _G.__AUDIT_PROFILE\n'
                '        assert_not_nil(prof.nodes["NODE_A"])\n'
                '        assert_true(prof.nodes["NODE_A"].require_calls >= 1)\n'
                '        assert_true(prof.nodes["NODE_A"].calls >= 1)\n'
                '        assert_true(prof.nodes["NODE_A"].tick_calls >= 1)\n'
                '        assert_true(prof.nodes["NODE_A"].insns > 0)\n'
                '        assert_not_nil(prof.bus.channels["10002"])\n'
                '        assert_eq(prof.bus.channels["10002"].packets, 1)\n'
                '        assert_eq(prof.bus.channels["10002"].unreceived_packets, 0)\n'
                '        assert_true(prof.bus.channels["10002"].total_bytes > 0)\n'
                '        assert_eq(prof.bus.channels["10099"].unreceived_packets, 1)\n'
                '        _G.__AUDIT_PROFILE = nil\n'
                '    end)\n'
                'end)\n',
                encoding="utf-8",
            )

            cfg = UnitTargetConfig(
                target_id="0_development/prof_test",
                source_dir=sdir,
                tests_dir=tdir,
                timeout_sec=10.0,
            )
            rep = run_target_unit_tests(
                target=cfg,
                craftos_paths=self.paths,
                sessions_root=root / ".sessions",
                require_tests=True,
            )
            self.assertEqual(rep.status, "PASS", f"Errors: {rep.errors} | Tests: {rep.tests}")

    def test_run_e2e_cli_writes_profile_json_without_breaking_suites(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_path = Path(tmp) / "e2e_profile.json"
            code, report = run_e2e_cli(
                ["--filter", "bootstrap", "--json", "--profile", str(out_path)],
                workspace_root=self.repo_root,
            )
            self.assertEqual(code, 0, f"E2E failed: {report}")
            self.assertTrue(out_path.is_file(), "Profile JSON file was not written")
            prof = json.loads(out_path.read_text(encoding="utf-8"))
            self.assertIn("nodes", prof)
            self.assertIn("channels", prof)
            self.assertGreater(len(prof["nodes"]), 0)
            self.assertGreater(len(prof["channels"]), 0)

    def test_e2e_profile_mode_is_non_interfering_across_all_suites(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_path = Path(tmp) / "full_profile.json"
            code_base, rep_base = run_e2e_cli(["--json"], workspace_root=self.repo_root)
            code_prof, rep_prof = run_e2e_cli(
                ["--json", "--profile", str(out_path)],
                workspace_root=self.repo_root,
            )
            self.assertEqual(code_base, 0)
            self.assertEqual(code_prof, 0)
            self.assertEqual(rep_base["total_passed"], rep_prof["total_passed"])
            self.assertEqual(rep_base["total_failed"], 0)
            self.assertEqual(rep_prof["total_failed"], 0)
            self.assertEqual(rep_base["captured_packet_count"], rep_prof["captured_packet_count"])
            self.assertEqual(rep_base["contract_errors"], [])
            self.assertEqual(rep_prof["contract_errors"], [])

    def test_e2e_check_baseline_passes_with_warnings_only_on_regression(self) -> None:
        parser = build_arg_parser()
        args = parser.parse_args(["--check-baseline"])
        self.assertTrue(args.check_baseline)

        code, report = run_e2e_cli(
            ["--json", "--check-baseline"],
            workspace_root=self.repo_root,
        )
        self.assertEqual(code, 0, f"E2E check-baseline failed: {report}")
        self.assertEqual(report.get("baseline_warnings"), [])


if __name__ == "__main__":
    unittest.main()
