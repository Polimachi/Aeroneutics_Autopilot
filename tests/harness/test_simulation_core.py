"""
Unit test for simulation harness: virtual_bus and node_sandbox running in CraftOS-PC.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from harness.unit.config import UnitTargetConfig, resolve_craftos_paths
from harness.unit.engine import run_target_unit_tests


class TestSimulationCore(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.paths = resolve_craftos_paths()
        cls.repo_root = Path(__file__).resolve().parents[2]

    def test_virtual_bus_routing_and_packet_log(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            sdir = root / "src" / "0_development" / "sim_test"
            tdir = root / "tests" / "0_development" / "sim_test"
            sdir.mkdir(parents=True)
            tdir.mkdir(parents=True)
            (sdir / "main.lua").write_text("return true\n", encoding="utf-8")

            # Copy virtual_bus.lua if exists into sdir
            sim_src = self.repo_root / "harness" / "simulation" / "virtual_bus.lua"
            if sim_src.exists():
                (sdir / "virtual_bus.lua").write_text(sim_src.read_text(encoding="utf-8"), encoding="utf-8")

            (tdir / "test_bus.lua").write_text(
                'local virtual_bus = require("virtual_bus")\n'
                'describe("virtual_bus RF router", function()\n'
                '    it("routes packets between nodes listening on open channels", function()\n'
                '        local bus = virtual_bus.create_bus()\n'
                '        local m1 = bus:create_modem("NODE_A")\n'
                '        local m2 = bus:create_modem("NODE_B")\n'
                '        m2:open(50000)\n'
                '        assert_true(m2:isOpen(50000))\n'
                '        assert_false(m1:isOpen(50000))\n'
                '        m1:transmit(50000, 10000, { ver = "1.9.5", type = "TEST_PING" })\n'
                '        bus:step(0.05)\n'
                '        assert_eq(#bus.packet_log, 1)\n'
                '        assert_eq(bus.packet_log[1].from, "NODE_A")\n'
                '        assert_eq(bus.packet_log[1].channel, 50000)\n'
                '        assert_eq(bus.packet_log[1].replyChannel, 10000)\n'
                '        assert_eq(#m2.inbox, 1)\n'
                '        assert_eq(m2.inbox[1].payload.type, "TEST_PING")\n'
                '        local found = bus:find_packets({ type = "TEST_PING", channel = 50000 })\n'
                '        assert_eq(#found, 1)\n'
                '    end)\n'
                'end)\n',
                encoding="utf-8",
            )

            cfg = UnitTargetConfig(
                target_id="0_development/sim_test",
                source_dir=sdir,
                tests_dir=tdir,
                timeout_sec=10.0,
            )
            report = run_target_unit_tests(
                target=cfg,
                craftos_paths=self.paths,
                sessions_root=root / ".sessions",
                require_tests=True,
            )
            self.assertEqual(report.status, "PASS", f"Errors: {report.errors}")
            self.assertEqual(report.passed_tests, 1)

    def test_node_sandbox_isolation_and_execution(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            sdir = root / "src" / "0_development" / "sim_sandbox_test"
            tdir = root / "tests" / "0_development" / "sim_sandbox_test"
            sdir.mkdir(parents=True)
            tdir.mkdir(parents=True)
            (sdir / "main.lua").write_text("return true\n", encoding="utf-8")

            # Copy simulation modules into sdir
            vbus = self.repo_root / "harness" / "simulation" / "virtual_bus.lua"
            if vbus.exists():
                (sdir / "virtual_bus.lua").write_text(vbus.read_text(encoding="utf-8"), encoding="utf-8")
            nsandbox = self.repo_root / "harness" / "simulation" / "node_sandbox.lua"
            if nsandbox.exists():
                (sdir / "node_sandbox.lua").write_text(nsandbox.read_text(encoding="utf-8"), encoding="utf-8")

            (tdir / "test_sandbox.lua").write_text(
                'local virtual_bus = require("virtual_bus")\n'
                'local node_sandbox = require("node_sandbox")\n'
                'describe("node_sandbox environment isolation", function()\n'
                '    it("creates isolated sandboxes with distinct package.loaded", function()\n'
                '        local bus = virtual_bus.create_bus()\n'
                '        local n1 = node_sandbox.create_node(bus, "NODE_1", "src/mock1", {\n'
                '            virtual_files = {\n'
                '                ["test_mod.lua"] = "return { id = \'MOD_1\', counter = 0 }",\n'
                '            }\n'
                '        })\n'
                '        local n2 = node_sandbox.create_node(bus, "NODE_2", "src/mock2", {\n'
                '            virtual_files = {\n'
                '                ["test_mod.lua"] = "return { id = \'MOD_2\', counter = 100 }",\n'
                '            }\n'
                '        })\n'
                '        local m1 = n1:require("test_mod")\n'
                '        local m2 = n2:require("test_mod")\n'
                '        assert_eq(m1.id, "MOD_1")\n'
                '        assert_eq(m2.id, "MOD_2")\n'
                '        m1.counter = 42\n'
                '        assert_eq(m1.counter, 42)\n'
                '        assert_eq(m2.counter, 100)\n'
                '        -- verify modem integration\n'
                '        assert_not_nil(n1.modem)\n'
                '        assert_not_nil(n2.modem)\n'
                '        n2.modem:open(10000)\n'
                '        n1.modem:transmit(10000, 10001, { type = "PING" })\n'
                '        bus:step(0.05)\n'
                '        assert_eq(#n2.modem.inbox, 1)\n'
                '    end)\n'
                'end)\n',
                encoding="utf-8",
            )

            cfg = UnitTargetConfig(
                target_id="0_development/sim_sandbox_test",
                source_dir=sdir,
                tests_dir=tdir,
                timeout_sec=10.0,
            )
            report = run_target_unit_tests(
                target=cfg,
                craftos_paths=self.paths,
                sessions_root=root / ".sessions",
                require_tests=True,
            )
            self.assertEqual(report.status, "PASS", f"Errors: {report.errors}")
            self.assertEqual(report.passed_tests, 1)


if __name__ == "__main__":
    unittest.main()
