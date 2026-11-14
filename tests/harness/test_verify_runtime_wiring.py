"""
Unit tests for tools/verify_runtime_wiring.py.
Verifies static reachability, orphan modules, broken requires,
package path safety, and dead import detection.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parents[2]
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

from tools.verify_runtime_wiring import (
    WiringViolation,
    analyze_subsystem_wiring,
    verify_all_wiring,
    KNOWN_EXEMPTIONS,
)


class TestVerifyRuntimeWiring(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = Path(tempfile.mkdtemp(prefix="test_wiring_"))

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_detects_broken_require_target(self) -> None:
        sub_dir = self.temp_dir / "src" / "1_control" / "sub_test"
        sub_dir.mkdir(parents=True)
        main_lua = sub_dir / "main.lua"
        main_lua.write_text(
            'local missing = require("nonexistent_mod")\nprint(missing)\n',
            encoding="utf-8",
        )

        violations = analyze_subsystem_wiring(sub_dir, self.temp_dir)
        broken = [v for v in violations if v.code == "BROKEN_REQUIRE"]
        self.assertGreaterEqual(len(broken), 1)
        self.assertEqual(broken[0].code, "BROKEN_REQUIRE")
        self.assertIn("nonexistent_mod", broken[0].message)

    def test_detects_orphan_module_not_reachable_from_main(self) -> None:
        sub_dir = self.temp_dir / "src" / "1_control" / "sub_test"
        modules_dir = sub_dir / "modules"
        modules_dir.mkdir(parents=True)

        main_lua = sub_dir / "main.lua"
        main_lua.write_text(
            'local reachable = require("modules.reachable")\nprint(reachable)\n',
            encoding="utf-8",
        )

        reachable_lua = modules_dir / "reachable.lua"
        reachable_lua.write_text('return { name = "reachable" }\n', encoding="utf-8")

        orphan_lua = modules_dir / "dead_helper.lua"
        orphan_lua.write_text('return { name = "orphan" }\n', encoding="utf-8")

        node_lua = sub_dir / "node_simulation.lua"
        node_lua.write_text('return { name = "node_sim" }\n', encoding="utf-8")

        violations = analyze_subsystem_wiring(sub_dir, self.temp_dir)
        orphans = [v for v in violations if v.code == "ORPHAN_MODULE"]

        self.assertEqual(len(orphans), 1)
        self.assertIn("dead_helper.lua", orphans[0].file_path.replace("\\", "/"))

        # Verify node_*.lua is ignored
        node_violations = [v for v in violations if "node_simulation" in v.file_path]
        self.assertEqual(node_violations, [])

    def test_detects_unused_require_binding_in_main(self) -> None:
        sub_dir = self.temp_dir / "src" / "1_control" / "sub_test"
        modules_dir = sub_dir / "modules"
        modules_dir.mkdir(parents=True)

        main_lua = sub_dir / "main.lua"
        main_lua.write_text(
            'local used_mod = require("modules.used_mod")\n'
            'local dead_mod = require("modules.dead_mod")\n'
            'local _ = require("modules.side_effect")\n'
            'used_mod.do_action()\n',
            encoding="utf-8",
        )

        (modules_dir / "used_mod.lua").write_text("return { do_action = function() end }\n", encoding="utf-8")
        (modules_dir / "dead_mod.lua").write_text("return {}\n", encoding="utf-8")
        (modules_dir / "side_effect.lua").write_text("return {}\n", encoding="utf-8")

        violations = analyze_subsystem_wiring(sub_dir, self.temp_dir)
        dead = [v for v in violations if v.code == "DEAD_IMPORT"]

        self.assertEqual(len(dead), 1)
        self.assertEqual(dead[0].line, 2)
        self.assertIn("dead_mod", dead[0].message)

    def test_missing_package_path_when_startup_injection_disabled(self) -> None:
        sub_dir = self.temp_dir / "src" / "1_control" / "sub_test"
        modules_dir = sub_dir / "modules"
        modules_dir.mkdir(parents=True)

        # Bare require without package.path modification in main.lua
        main_lua = sub_dir / "main.lua"
        main_lua.write_text(
            'local helper = require("helper")\nhelper.run()\n',
            encoding="utf-8",
        )
        (modules_dir / "helper.lua").write_text("return { run = function() end }\n", encoding="utf-8")

        # When startup_injects_modules=False and main lacks package.path -> MISSING_PACKAGE_PATH
        violations_no_startup = analyze_subsystem_wiring(
            sub_dir, self.temp_dir, startup_injects_modules=False
        )
        missing_pkg = [v for v in violations_no_startup if v.code == "MISSING_PACKAGE_PATH"]
        self.assertGreaterEqual(len(missing_pkg), 1)

        # When startup_injects_modules=True -> no violation because startup hook injects modules/?.lua
        violations_startup = analyze_subsystem_wiring(
            sub_dir, self.temp_dir, startup_injects_modules=True
        )
        missing_pkg_startup = [v for v in violations_startup if v.code == "MISSING_PACKAGE_PATH"]
        self.assertEqual(missing_pkg_startup, [])

    def test_deferred_asa_skipped_by_default_and_scanned_with_include_deferred(self) -> None:
        # Default scan: deferred subsystems are excluded
        violations_default = verify_all_wiring(WORKSPACE_ROOT, include_deferred=False)
        asa_default = [v for v in violations_default if "1_control/asa" in v.file_path.replace("\\", "/")]
        self.assertEqual(asa_default, [])

        # Scanned with include_deferred=True
        violations_deferred = verify_all_wiring(WORKSPACE_ROOT, include_deferred=True)
        # Verify asa is scanned without crashing; assert no broken requires in asa
        asa_broken = [
            v for v in violations_deferred
            if "1_control/asa" in v.file_path.replace("\\", "/") and v.code == "BROKEN_REQUIRE"
        ]
        self.assertEqual(asa_broken, [])

    def test_live_repo_runtime_wiring_passes(self) -> None:
        violations = verify_all_wiring(WORKSPACE_ROOT, include_deferred=False)

        # 1. Zero broken requires across all active subsystems
        broken = [v for v in violations if v.code == "BROKEN_REQUIRE"]
        self.assertEqual(broken, [], f"Live repo has broken requires: {broken}")

        # 2. Zero missing package path violations across all active subsystems
        missing_pkg = [v for v in violations if v.code == "MISSING_PACKAGE_PATH"]
        self.assertEqual(missing_pkg, [], f"Live repo has missing package paths: {missing_pkg}")

        # 3. Overall violations must be 0 (known exemptions are tracked with documented rationale)
        self.assertEqual(violations, [], f"Live repo wiring violations: {violations}")

    def test_strict_wiring_verification_flags_all_known_exemptions(self) -> None:
        violations = verify_all_wiring(WORKSPACE_ROOT, strict=True)
        self.assertEqual(
            len(violations),
            4,
            f"Expected exactly 4 strict violations matching KNOWN_EXEMPTIONS, got {len(violations)}: {violations}",
        )

        violation_keys = {
            (Path(v.file_path).resolve().relative_to(WORKSPACE_ROOT.resolve()).as_posix(), v.code)
            for v in violations
        }
        self.assertEqual(violation_keys, set(KNOWN_EXEMPTIONS.keys()))

        # Verify each of the 4 specific documented exemptions
        self.assertIn(("src/1_control/vas/modules/vec3.lua", "ORPHAN_MODULE"), violation_keys)
        self.assertIn(("src/0_infra/gac/config.lua", "ORPHAN_MODULE"), violation_keys)
        self.assertIn(("src/0_infra/landing_pad/config.lua", "ORPHAN_MODULE"), violation_keys)
        self.assertIn(("src/0_infra/landing_pad/main.lua", "DEAD_IMPORT"), violation_keys)

        # Ensure the landing_pad main.lua DEAD_IMPORT specifically refers to setup_wizard
        dead_imports = [v for v in violations if v.code == "DEAD_IMPORT"]
        self.assertEqual(len(dead_imports), 1)
        self.assertIn("setup_wizard", dead_imports[0].message)

    def test_cli_execution_and_json_output(self) -> None:
        cli_path = WORKSPACE_ROOT / "tools" / "verify_runtime_wiring.py"
        res = subprocess.run(
            [sys.executable, str(cli_path), "--json"],
            cwd=str(WORKSPACE_ROOT),
            capture_output=True,
            text=True,
        )
        self.assertEqual(res.returncode, 0, f"CLI stderr: {res.stderr}")
        data = json.loads(res.stdout)
        self.assertIn("violations", data)
        self.assertIn("summary", data)


if __name__ == "__main__":
    unittest.main()
