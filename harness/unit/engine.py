"""
Execution engine running unit tests for a specific codebase target in an isolated CraftOS-PC session.
"""
from __future__ import annotations

import json
import shutil
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from .config import CraftOSPaths, UnitTargetConfig
from .session import EphemeralCraftOSSession
from .static_guard import StaticViolation, scan_target_files

GUEST_DIR = Path(__file__).resolve().parent / "guest"


@dataclass
class UnitCaseResult:
    suite: str
    name: str
    status: str
    duration_ms: float = 0.0
    instructions: int = 0
    error: str = ""


@dataclass
class TargetRunReport:
    target_id: str
    status: str  # "PASS", "FAIL", "SKIP"
    total_tests: int = 0
    passed_tests: int = 0
    failed_tests: int = 0
    max_insns_observed: int = 0
    event_swallow_count: int = 0
    ui_violation_count: int = 0
    duration_ms: float = 0.0
    timed_out: bool = False
    static_violations: list[StaticViolation] = field(default_factory=list)
    tests: list[UnitCaseResult] = field(default_factory=list)
    logs: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _needs_raw_mode(peripherals) -> bool:
    for p in peripherals:
        if getattr(p, "peripheral_type", None) in ("monitor", "computer"):
            return True
    return False


def run_target_unit_tests(
    target: UnitTargetConfig,
    craftos_paths: CraftOSPaths,
    sessions_root: Path,
    test_filter: str | None = None,
    require_tests: bool = False,
) -> TargetRunReport:
    t0 = time.perf_counter()

    # 1. Pre-flight static guard
    static_issues = scan_target_files(target, craftos_paths)
    if static_issues:
        dur = round((time.perf_counter() - t0) * 1000.0, 2)
        err_msgs = [f"[{i.code}] {i.file_path}:{i.line} {i.message}" for i in static_issues]
        return TargetRunReport(
            target_id=target.target_id,
            status="FAIL",
            duration_ms=dur,
            static_violations=static_issues,
            errors=err_msgs,
        )

    # 2. Check for test files
    test_files: list[Path] = []
    if target.tests_dir.exists():
        test_files = sorted(target.tests_dir.rglob("test_*.lua"))

    if not test_files:
        dur = round((time.perf_counter() - t0) * 1000.0, 2)
        if require_tests:
            return TargetRunReport(
                target_id=target.target_id,
                status="FAIL",
                duration_ms=dur,
                errors=[f"Target '{target.target_id}' has no unit tests in {target.tests_dir}"],
            )
        return TargetRunReport(
            target_id=target.target_id,
            status="SKIP",
            duration_ms=dur,
            logs=[f"No test_*.lua files found in {target.tests_dir}"],
        )

    # 3. Provision ephemeral session
    mode = "raw" if _needs_raw_mode(target.peripherals) else "headless"
    session_prefix = f"unit_{target.target_id.replace('/', '_')}"

    with EphemeralCraftOSSession(
        sessions_root=sessions_root,
        craftos_paths=craftos_paths,
        prefix=session_prefix,
        abort_timeout_ms=target.abort_timeout_ms,
        term_width=target.term_width,
        term_height=target.term_height,
    ) as session:
        c0 = session.computer_dir(0)

        # Stage shared sensor SSOT library at /lib/ across all targets
        shared_sensors_dir = target.source_dir.parent.parent / "0_development" / "sensors"
        if shared_sensors_dir.is_dir():
            lib_dest = c0 / "lib"
            lib_dest.mkdir(parents=True, exist_ok=True)
            for lua_file in sorted(shared_sensors_dir.glob("*.lua")):
                if lua_file.name != "main.lua":
                    shutil.copy2(lua_file, lib_dest / lua_file.name)

        # Stage source codebase at /
        session.stage_tree(target.source_dir, computer_id=0, dest_subdir="")

        # Stage test suite at /_tests/
        session.stage_tree(target.tests_dir, computer_id=0, dest_subdir="_tests")

        # Copy in-guest runner library & SDK
        harness_guest = c0 / "_harness"
        harness_guest.mkdir(parents=True, exist_ok=True)
        shutil.copy2(GUEST_DIR / "runner_lib.lua", harness_guest / "runner_lib.lua")
        sdk_lua = GUEST_DIR / "test_sdk.lua"
        has_sdk = sdk_lua.exists()
        if has_sdk:
            shutil.copy2(sdk_lua, harness_guest / "test_sdk.lua")

        rel_test_files = [
            "/_tests/" + str(f.relative_to(target.tests_dir)).replace("\\", "/")
            for f in test_files
        ]
        periph_dicts = [
            {"side": p.side, "type": p.peripheral_type, "args": p.args}
            for p in target.peripherals
        ]

        runner_cfg = {
            "test_files": rel_test_files,
            "filter_substr": test_filter or "",
            "instruction_budget": target.max_instructions_per_tick,
            "peripherals": periph_dicts,
            "has_sdk": has_sdk,
        }
        (harness_guest / "config.json").write_text(
            json.dumps(runner_cfg, indent=2), encoding="utf-8"
        )

        startup_script = """
local R = dofile("/_harness/runner_lib.lua")

local cf = fs.open("/_harness/config.json", "r")
local cfg = textutils.unserializeJSON(cf.readAll())
cf.close()

R.instruction_budget = tonumber(cfg.instruction_budget) or 50000
R.filter_substr = cfg.filter_substr
R.install_log_hooks()
R.install_dsl()

if cfg.has_sdk and fs.exists("/_harness/test_sdk.lua") then
    dofile("/_harness/test_sdk.lua")
end

if package then
    _G.package = package
    if package.path then
        package.path = "/?.lua;/?/init.lua;/modules/?.lua;/modules/?/init.lua;/hal/?.lua;/tools/?.lua;/lib/?.lua;" .. package.path
    end
end

local attached = R.setup_peripherals(cfg.peripherals)
if term and term.current then
    R.install_surface_auditor(term.current(), "term")
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
                    { name = "<top_level>", status = "FAIL", error = tostring(runtime_err) }
                }
            }
        elseif #R.suites == before_suites then
            R.suites[#R.suites + 1] = {
                name = tf,
                passed = 1,
                failed = 0,
                tests = {
                    { name = tf, status = "PASS", duration_ms = 0, instructions = 0 }
                }
            }
        end
    end
end

R.write_result({
    attached = attached,
    suites = R.suites,
    max_insns_observed = R.max_insns_observed,
    event_swallow_count = R.event_swallow_count,
    ui_violations = R.ui_violations,
    logs = R.logs,
    errors = R.errors,
})

os.shutdown()
"""
        (c0 / "startup.lua").write_text(startup_script, encoding="utf-8")
        run_res = session.run(mode=mode, timeout_sec=target.timeout_sec)

    dur = round((time.perf_counter() - t0) * 1000.0, 2)
    tests_out: list[UnitCaseResult] = []
    passed = 0
    failed = 0
    max_insns = 0
    event_swallows = 0
    ui_violations = 0
    logs: list[str] = []
    errors: list[str] = []

    if run_res.timed_out:
        errors.append(
            f"Execution timed out after {target.timeout_sec}s (infinite loop or blocking wait)."
        )

    if run_res.guest_result:
        gr = run_res.guest_result
        logs = gr.get("logs", [])
        errors.extend(gr.get("errors", []))
        max_insns = int(gr.get("max_insns_observed", 0))
        event_swallows = int(gr.get("event_swallow_count", 0))
        ui_violations = len(gr.get("ui_violations", []))
        for v in gr.get("ui_violations", []):
            errors.append(f"[{v.get('kind')}] {v.get('detail')}")

        for suite in gr.get("suites", []):
            sname = suite.get("name", "default")
            for t in suite.get("tests", []):
                st = t.get("status", "FAIL")
                if st == "PASS":
                    passed += 1
                else:
                    failed += 1
                tests_out.append(
                    UnitCaseResult(
                        suite=sname,
                        name=t.get("name", "unnamed"),
                        status=st,
                        duration_ms=float(t.get("duration_ms", 0.0)),
                        instructions=int(t.get("instructions", 0)),
                        error=t.get("error", ""),
                    )
                )
    else:
        if not run_res.timed_out:
            errors.append("CraftOS-PC exited without producing `/_harness_out/result.json`.")

    total = passed + failed
    status = "FAIL" if (failed > 0 or event_swallows > 0 or ui_violations > 0 or run_res.timed_out or errors) else "PASS"

    return TargetRunReport(
        target_id=target.target_id,
        status=status,
        total_tests=total,
        passed_tests=passed,
        failed_tests=failed,
        max_insns_observed=max_insns,
        event_swallow_count=event_swallows,
        ui_violation_count=ui_violations,
        duration_ms=dur,
        timed_out=run_res.timed_out,
        tests=tests_out,
        logs=logs,
        errors=errors,
    )
