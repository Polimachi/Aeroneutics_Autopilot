"""
Universal multi-node E2E simulation test runner CLI for Create_Aeroneutics.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from pathlib import Path
from typing import Any

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

from harness.unit.config import resolve_craftos_paths
from harness.unit.session import EphemeralCraftOSSession, clean_workspace_orphans

GUEST_DIR = WORKSPACE_ROOT / "harness" / "unit" / "guest"
SIMULATION_DIR = WORKSPACE_ROOT / "harness" / "simulation"


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run multi-node end-to-end (E2E) packet sequence integration simulation."
    )
    parser.add_argument(
        "--filter",
        "-f",
        type=str,
        default=None,
        help="Substring filter applied to e2e test suite or case names.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output structured JSON results instead of human table.",
    )
    parser.add_argument(
        "--clean-orphans",
        action="store_true",
        help="Terminate lingering CraftOS-PC console processes before running.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=30.0,
        help="Global timeout in seconds for E2E simulation execution.",
    )
    return parser


def run_e2e_cli(
    argv: list[str] | None = None, workspace_root: Path | None = None
) -> tuple[int, dict[str, Any]]:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    root = (workspace_root or WORKSPACE_ROOT).resolve()
    sessions_root = root / ".runtime" / "e2e_sessions"

    if args.clean_orphans:
        clean_workspace_orphans(sessions_root)

    e2e_tests_dir = root / "tests" / "e2e"
    e2e_files: list[Path] = []
    if e2e_tests_dir.exists():
        e2e_files = sorted(e2e_tests_dir.glob("test_e2e_*.lua"))

    if args.filter:
        flt = args.filter.lower()
        e2e_files = [f for f in e2e_files if flt in f.name.lower()]

    if not e2e_files:
        payload = {
            "status": "PASS",
            "total_suites": 0,
            "total_passed": 0,
            "total_failed": 0,
            "suites": [],
            "logs": ["No tests/e2e/test_e2e_*.lua files found."],
        }
        if not args.json:
            print("=== Create_Aeroneutics Multi-Node E2E Simulation Runner ===")
            print("  [SKIP]  No matching tests/e2e/test_e2e_*.lua files found.")
            print("Overall Result: PASS (0 suites)")
        return 0, payload

    craftos_paths = resolve_craftos_paths()

    t0 = time.perf_counter()
    with EphemeralCraftOSSession(
        sessions_root=sessions_root,
        craftos_paths=craftos_paths,
        prefix="e2e_sim",
        abort_timeout_ms=10000,
        term_width=51,
        term_height=19,
    ) as session:
        c0 = session.computer_dir(0)

        # 1. Stage shared sensor SSOT library at /lib/
        shared_sensors = root / "src" / "0_development" / "sensors"
        if shared_sensors.is_dir():
            lib_dest = c0 / "lib"
            lib_dest.mkdir(parents=True, exist_ok=True)
            for lua_file in sorted(shared_sensors.glob("*.lua")):
                if lua_file.name != "main.lua":
                    shutil.copy2(lua_file, lib_dest / lua_file.name)

        # 2. Stage entire src/ tree at /src/
        session.stage_tree(root / "src", computer_id=0, dest_subdir="src")

        # 3. Stage harness simulation modules at /modules/
        session.stage_tree(root / "harness" / "simulation", computer_id=0, dest_subdir="modules")

        # 4. Stage harness unit guest SDK at /_harness/
        harness_dest = c0 / "_harness"
        harness_dest.mkdir(parents=True, exist_ok=True)
        shutil.copy2(GUEST_DIR / "runner_lib.lua", harness_dest / "runner_lib.lua")
        sdk_lua = GUEST_DIR / "test_sdk.lua"
        if sdk_lua.exists():
            shutil.copy2(sdk_lua, harness_dest / "test_sdk.lua")

        # 5. Stage E2E test suites at /_e2e/
        session.stage_tree(e2e_tests_dir, computer_id=0, dest_subdir="_e2e")

        # 6. Generate in-guest runner configuration and startup
        rel_test_files = [
            "/_e2e/" + f.name for f in e2e_files
        ]

        runner_cfg = {
            "test_files": rel_test_files,
            "filter_substr": "",
            "instruction_budget": 500000,
        }
        (harness_dest / "config.json").write_text(
            json.dumps(runner_cfg, indent=2), encoding="utf-8"
        )

        startup_script = """
local R = dofile("/_harness/runner_lib.lua")

local cf = fs.open("/_harness/config.json", "r")
local cfg = textutils.unserializeJSON(cf.readAll())
cf.close()

R.instruction_budget = tonumber(cfg.instruction_budget) or 500000
R.filter_substr = cfg.filter_substr
R.install_log_hooks()
R.install_dsl()

if fs.exists("/_harness/test_sdk.lua") then
    dofile("/_harness/test_sdk.lua")
end

if package then
    _G.package = package
    if package.path then
        package.path = "/?.lua;/?/init.lua;/modules/?.lua;/modules/?/init.lua;/lib/?.lua;" .. package.path
    end
end

for _, tf in ipairs(cfg.test_files) do
    local fn, load_err = loadfile(tf, nil, _ENV)
    if not fn then
        R.suites[#R.suites + 1] = {
            name = tf,
            passed = 0,
            failed = 1,
            tests = {
                { name = "<loadfile>", status = "FAIL", error = tostring(load_err) }
            }
        }
    else
        local before_suites = #R.suites
        local ok, runtime_err = xpcall(fn, debug.traceback)
        if not ok then
            R.suites[#R.suites + 1] = {
                name = tf,
                passed = 0,
                failed = 1,
                tests = {
                    { name = "<runtime>", status = "FAIL", error = tostring(runtime_err) }
                }
            }
        elseif #R.suites == before_suites then
            R.suites[#R.suites + 1] = {
                name = tf,
                passed = 0,
                failed = 0,
                tests = {}
            }
        end
    end
end

R.write_result({
    suites = R.suites,
    logs = R.logs or {},
    errors = R.errors or {},
})

os.shutdown()
"""
        (c0 / "startup.lua").write_text(startup_script, encoding="utf-8")

        session_res = session.run(mode="headless", timeout_sec=args.timeout)

    total_dur_ms = round((time.perf_counter() - t0) * 1000.0, 2)
    guest_data = session_res.guest_result or {}
    suites = guest_data.get("suites", [])

    total_passed = sum(s.get("passed", 0) for s in suites)
    total_failed = sum(s.get("failed", 0) for s in suites)

    all_pass = (total_failed == 0 and session_res.exit_code == 0 and not session_res.timed_out)
    final_status = "PASS" if all_pass else "FAIL"

    report_payload: dict[str, Any] = {
        "status": final_status,
        "duration_ms": total_dur_ms,
        "total_suites": len(suites),
        "total_passed": total_passed,
        "total_failed": total_failed,
        "timed_out": session_res.timed_out,
        "exit_code": session_res.exit_code,
        "suites": suites,
        "logs": guest_data.get("logs", []),
    }

    if not args.json:
        print(f"=== Create_Aeroneutics Multi-Node E2E Simulation Runner ({len(suites)} suites) ===")
        for s in suites:
            s_name = Path(s.get("name", "")).stem
            passed = s.get("passed", 0)
            failed = s.get("failed", 0)
            status_tag = "[PASS]" if failed == 0 else "[FAIL]"
            print(f"  {status_tag:<8} {s_name:<36} ({passed}/{passed + failed} passed)")
            if failed > 0:
                for t in s.get("tests", []):
                    if t.get("status") == "FAIL":
                        print(f"           - {t.get('name')}: {t.get('error')}")
        print(f"\nOverall Result: {final_status} ({total_passed}/{total_passed + total_failed} passed, {total_dur_ms}ms)")

    exit_code = 0 if all_pass else 1
    return exit_code, report_payload


if __name__ == "__main__":
    code, _ = run_e2e_cli()
    sys.exit(code)
