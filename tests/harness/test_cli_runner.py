import tempfile
import unittest
from pathlib import Path

from tools.run_unit_tests import run_cli


class TestCliRunner(unittest.TestCase):
    def test_cross_codebase_module_collision_isolation_and_exit_codes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            # Two separate codebases defining identically named modules/ui_renderer.lua
            for layer_prog, tag in (("1_control/vas", "VAS_UI"), ("2_guidance/sas", "SAS_UI")):
                sdir = root / "src" / layer_prog / "modules"
                tdir = root / "tests" / layer_prog
                sdir.mkdir(parents=True)
                tdir.mkdir(parents=True)
                (sdir / "ui_renderer.lua").write_text(f'return {{ id = "{tag}" }}\n', encoding="utf-8")
                (tdir / "test_ui.lua").write_text(
                    f'local ui = require("ui_renderer")\n'
                    f'describe("{layer_prog}", function()\n'
                    f'    it("loads isolated ui_renderer", function()\n'
                    f'        assert_eq(ui.id, "{tag}")\n'
                    f'    end)\n'
                    f'end)\n',
                    encoding="utf-8",
                )
            # Third codebase with source but no tests yet
            untested = root / "src" / "0_infra" / "gps"
            untested.mkdir(parents=True)
            (untested / "main.lua").write_text("return true\n", encoding="utf-8")

            code_ok, payload_ok = run_cli(["--json"], workspace_root=root)
            self.assertEqual(code_ok, 0)
            statuses = {r["target_id"]: r["status"] for r in payload_ok["targets"]}
            self.assertEqual(statuses, {
                "0_infra/gps": "SKIP",
                "1_control/vas": "PASS",
                "2_guidance/sas": "PASS",
            })

            code_strict, _ = run_cli(["--require-tests"], workspace_root=root)
            self.assertEqual(code_strict, 1)


if __name__ == "__main__":
    unittest.main()
