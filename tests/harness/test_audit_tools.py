"""
Tests for tools.audit package (registry, static, dupes, specs, split, CLI).
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


class TestAuditTools(unittest.TestCase):
    def test_registry_captures_subsystems_docking_arm_spec_only_and_specs(self) -> None:
        from tools.audit.registry import build_registry

        reg = build_registry(REPO_ROOT)
        sub_map = {s["id"]: s for s in reg["subsystems"]}
        self.assertIn("1_control/vas", sub_map)
        self.assertTrue(sub_map["1_control/vas"]["code_present"])
        self.assertIn("0_infra/docking_arm", sub_map)
        self.assertFalse(sub_map["0_infra/docking_arm"]["code_present"])
        self.assertTrue(sub_map["0_infra/docking_arm"]["spec_only"])
        self.assertGreaterEqual(len(reg["modules"]), 139)
        self.assertEqual(len(reg["specs"]), 18)
        self.assertGreater(len(reg["packets"]), 0)

    def test_static_analysis_extracts_functions_and_field_consumption(self) -> None:
        from tools.audit.common import extract_lua_functions
        from tools.audit.static_analysis import analyze_static

        sample = (
            "local M = {}\n"
            "local function helper(x)\n"
            "    if x > 0 then\n"
            "        return x + 1\n"
            "    end\n"
            "    return 0\n"
            "end\n"
            "function M.run(p)\n"
            "    return helper(p.val)\n"
            "end\n"
            "return M\n"
        )
        fns = extract_lua_functions(sample, "sample.lua")
        names = [f["name"] for f in fns]
        self.assertEqual(names, ["helper", "M.run"])
        self.assertEqual(fns[0]["lines"], 6)

        res = analyze_static(REPO_ROOT)
        self.assertIn("module_sizes", res)
        self.assertIn("top_functions", res)
        self.assertIn("protocol_field_consumption", res)
        self.assertGreater(len(res["protocol_field_consumption"]), 0)

    def test_dupes_detects_cross_subsystem_clones_in_synthetic_repo(self) -> None:
        from tools.audit.dupes import analyze_dupes

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for sub in ("0_infra/alpha", "1_control/beta"):
                d = root / "src" / sub
                d.mkdir(parents=True)
                (d / "mod.lua").write_text(
                    "local M = {}\n"
                    "function M.compute_stuff(a, b, c)\n"
                    "    local x = a + b\n"
                    "    local y = b * c\n"
                    "    if x > y then\n"
                    "        return x - y\n"
                    "    end\n"
                    "    return y - x\n"
                    "end\n"
                    "return M\n",
                    encoding="utf-8",
                )
            res = analyze_dupes(root)
            self.assertGreaterEqual(res["exact_cluster_count"], 1)
            self.assertGreater(res["total_duplicated_lines"], 0)

    def test_specs_and_split_analysis_on_repo(self) -> None:
        from tools.audit.specs_analysis import analyze_specs
        from tools.audit.split_analysis import analyze_splits

        specs_res = analyze_specs(REPO_ROOT)
        self.assertEqual(len(specs_res["documents"]), 18)
        self.assertIn("pairwise_overlap", specs_res)
        self.assertIn("cochange", specs_res)

        split_res = analyze_splits(REPO_ROOT)
        lua_ids = {c["id"] for c in split_res["lua_candidates"]}
        spec_ids = {c["id"] for c in split_res["spec_candidates"]}
        self.assertIn("src/3_planning/amm/main.lua", lua_ids)
        self.assertIn("docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md", spec_ids)
        self.assertTrue(len(split_res["webui_candidates"]) >= 1)

    def test_cli_runs_subcommands_and_writes_json_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp) / "audit_out"
            proc = subprocess.run(
                [sys.executable, "-m", "tools.audit", "registry", "--out", str(out_dir), "--json"],
                capture_output=True,
                text=True,
                cwd=str(REPO_ROOT),
                timeout=30,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertTrue((out_dir / "registry.json").is_file())
            data = json.loads((out_dir / "registry.json").read_text(encoding="utf-8"))
            self.assertIn("subsystems", data)

    def test_guard_fails_on_installer_mirror_drift_and_warns_on_new_oversize_file(self) -> None:
        from tools.audit.guard import run_guard

        baseline_res = run_guard(REPO_ROOT)
        self.assertEqual(baseline_res["status"], "PASS", f"Guard errors: {baseline_res}")
        self.assertEqual(baseline_res["errors"], [])
        self.assertEqual(baseline_res["warnings"], [])

        baseline_cfg = json.loads((REPO_ROOT / "config" / "audit_baselines.json").read_text(encoding="utf-8"))
        self.assertEqual(
            baseline_cfg.get("unconsumed_required_keys_baseline"),
            [["MSG_SURFACE_DISCOVER_REQ", "targetPod"]],
        )

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "installer.lua").write_text("return 1\n", encoding="utf-8")
            sub = root / "src" / "0_development" / "installer"
            sub.mkdir(parents=True)
            (sub / "installer.lua").write_text("return 2\n", encoding="utf-8")
            oversize = root / "src" / "1_control" / "vas"
            oversize.mkdir(parents=True)
            (oversize / "big.lua").write_text("-- " + ("x" * 47000) + "\nreturn true\n", encoding="utf-8")
            (root / "config").mkdir(parents=True)
            (root / "config" / "audit_baselines.json").write_text(
                json.dumps({
                    "single_read_bytes": 46080,
                    "large_lua_exemptions": [],
                    "unconsumed_required_keys_baseline": [],
                    "installer_mirror_pair": ["installer.lua", "src/0_development/installer/installer.lua"],
                }),
                encoding="utf-8",
            )
            res = run_guard(root)
            self.assertEqual(res["status"], "FAIL")
            self.assertTrue(any("installer.lua" in e for e in res["errors"]))
            self.assertTrue(any("big.lua" in w for w in res["warnings"]))


if __name__ == "__main__":
    unittest.main()
