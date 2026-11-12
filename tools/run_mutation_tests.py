"""
Create_Aeroneutics Mutation Testing CLI Runner.
Systematically injects deterministic defects into production code (src/) to verify test effectiveness.
"""
from __future__ import annotations

import argparse
import sys
import subprocess
import time
from pathlib import Path
from typing import Dict, List, Any

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
TOOLS_DIR = WORKSPACE_ROOT / "tools"
RUN_UNIT_TESTS = TOOLS_DIR / "run_unit_tests.py"
RUN_E2E_TESTS = TOOLS_DIR / "run_e2e_tests.py"

# Definition of 25 core mutations across 11 domains
MUTATIONS: List[Dict[str, Any]] = [
    {
        "id": "MUT-01",
        "name": "VAS Domain Envelope Verification Check",
        "domain": "Network",
        "file": "src/1_control/vas/modules/network_manager.lua",
        "target": 'if expectedDomain and pkt.domainId ~= expectedDomain then return false, "ERR_DOMAIN_MISMATCH" end',
        "replacement": '-- if expectedDomain and pkt.domainId ~= expectedDomain then return false, "ERR_DOMAIN_MISMATCH" end',
        "runner": "unit",
        "target_arg": "1_control/vas",
    },
    {
        "id": "MUT-02",
        "name": "TCA Protocol Version Verification Check",
        "domain": "Network",
        "file": "src/1_control/tca/modules/packet_protocol.lua",
        "target": "if pkt.ver ~= packet_protocol.PROTO_VERSION then",
        "replacement": "if false and pkt.ver ~= packet_protocol.PROTO_VERSION then",
        "runner": "unit",
        "target_arg": "1_control/tca",
    },
    {
        "id": "MUT-03",
        "name": "AMM Channel Sentinel Candidate Base Validation",
        "domain": "Channel",
        "file": "src/3_planning/amm/modules/channel_sentinel.lua",
        "target": "if candidate and channel_sentinel.is_valid_base(candidate) then",
        "replacement": "if false and candidate and channel_sentinel.is_valid_base(candidate) then",
        "runner": "unit",
        "target_arg": "3_planning/amm",
    },
    {
        "id": "MUT-04",
        "name": "AMM Waypoint Queue 2D Arrival Distance Inversion",
        "domain": "Planning",
        "file": "src/3_planning/amm/modules/waypoint_queue.lua",
        "target": "if d2d <= rad then",
        "replacement": "if d2d > rad then",
        "runner": "unit",
        "target_arg": "3_planning/amm",
    },
    {
        "id": "MUT-05",
        "name": "AMM C2 Arbiter GCS Override Queue Suspension",
        "domain": "Planning",
        "file": "src/3_planning/amm/modules/c2_arbiter.lua",
        "target": 'self.queue.state = "SUSPENDED"',
        "replacement": '-- self.queue.state = "SUSPENDED"',
        "runner": "unit",
        "target_arg": "3_planning/amm",
    },
    {
        "id": "MUT-06",
        "name": "VAS Thrust Mixer Surge/Heave Sign Inversion",
        "domain": "Control",
        "file": "src/1_control/vas/modules/thrust_mixer.lua",
        "target": "raw = raw + (coeff[ax] or 0.0) * (demand[ax] or 0.0)",
        "replacement": "raw = raw - (coeff[ax] or 0.0) * (demand[ax] or 0.0)",
        "runner": "unit",
        "target_arg": "1_control/vas",
    },
    {
        "id": "MUT-07",
        "name": "VAS Emergency Override Dispatch Message Type",
        "domain": "Safety",
        "file": "src/1_control/vas/modules/network_manager.lua",
        "target": 'if msgType == "MSG_EMERGENCY_OVERRIDE" then',
        "replacement": 'if msgType == "MSG_DISABLED_OVERRIDE" then',
        "runner": "unit",
        "target_arg": "1_control/vas",
    },
    {
        "id": "MUT-08",
        "name": "TCA Watchdog Sentinel Expiration Callback",
        "domain": "Safety",
        "file": "src/1_control/tca/modules/watchdog_sentinel.lua",
        "target": "if wd.onTimeoutCb then pcall(wd.onTimeoutCb) end",
        "replacement": "-- if wd.onTimeoutCb then pcall(wd.onTimeoutCb) end",
        "runner": "unit",
        "target_arg": "1_control/tca",
    },
    {
        "id": "MUT-09",
        "name": "GPS Trilateration Fix Status Degradation",
        "domain": "Navigation",
        "file": "src/0_infra/gps/modules/trilateration.lua",
        "target": 'local status = "FIX_OK"',
        "replacement": 'local status = "FIX_CORRUPTED"',
        "runner": "unit",
        "target_arg": "0_infra/gps",
    },
    {
        "id": "MUT-10",
        "name": "GPS Radar Math Centroid Span Calculation",
        "domain": "Navigation",
        "file": "src/0_infra/gps/modules/radar_math.lua",
        "target": "centerX = (minX + maxX) / 2,",
        "replacement": "centerX = (minX - maxX) / 2,",
        "runner": "unit",
        "target_arg": "0_infra/gps",
    },
    {
        "id": "MUT-11",
        "name": "GAC Allocation Pad Candidate Weight Filtering",
        "domain": "Infra",
        "file": "src/0_infra/gac/modules/allocation_engine.lua",
        "target": "if maxW >= weight and maxR >= radius then",
        "replacement": "if maxW < weight and maxR >= radius then",
        "runner": "unit",
        "target_arg": "0_infra/gac",
    },
    {
        "id": "MUT-12",
        "name": "Landing Pad FSM Touchdown State Transition",
        "domain": "Infra",
        "file": "src/0_infra/landing_pad/modules/pad_fsm.lua",
        "target": 'state.currentState = "OCCUPIED"',
        "replacement": 'state.currentState = "FAIL_OCCUPIED"',
        "runner": "unit",
        "target_arg": "0_infra/landing_pad",
    },
    {
        "id": "MUT-13",
        "name": "Landing Pad Offset Transform Sine Yaw Sign",
        "domain": "Infra",
        "file": "src/0_infra/landing_pad/modules/offset_transform.lua",
        "target": "local sinYaw = math.sin(totalYawRad)",
        "replacement": "local sinYaw = -math.sin(totalYawRad)",
        "runner": "unit",
        "target_arg": "0_infra/landing_pad",
    },
    {
        "id": "MUT-14",
        "name": "FCP Flight FSM Takeoff Transition Guard",
        "domain": "Guidance",
        "file": "src/2_guidance/fcp/modules/flight_fsm.lua",
        "target": "if gate.allowed then",
        "replacement": "if false and gate.allowed then",
        "runner": "unit",
        "target_arg": "2_guidance/fcp",
    },
    {
        "id": "MUT-15",
        "name": "FCP Vectored VTOL PID Surge Gain Sign",
        "domain": "Guidance",
        "file": "src/2_guidance/fcp/modules/vectored_vtol_driver.lua",
        "target": "local skp, skd = g.surgeKp or 0.15, g.surgeKd or 0.08",
        "replacement": "local skp, skd = -(g.surgeKp or 0.15), g.surgeKd or 0.08",
        "runner": "unit",
        "target_arg": "2_guidance/fcp",
    },
    {
        "id": "MUT-16",
        "name": "GCS Fleet Tracker Telemetry Stale Flag",
        "domain": "Infra",
        "file": "src/0_infra/gcs/modules/fleet_tracker.lua",
        "target": "craft.isStale = true",
        "replacement": "craft.isStale = false",
        "runner": "unit",
        "target_arg": "0_infra/gcs",
    },
    {
        "id": "MUT-17",
        "name": "GCS Channel Manager Default Bandwidth Offset",
        "domain": "Channel",
        "file": "src/0_infra/gcs/modules/channel_manager.lua",
        "target": "local base = channel_manager.DEFAULT_BASE_MIN + (n - 1) * channel_manager.DEFAULT_BANDWIDTH",
        "replacement": "local base = channel_manager.DEFAULT_BASE_MIN + (n - 1) * 20",
        "runner": "unit",
        "target_arg": "0_infra/gcs",
    },
    {
        "id": "MUT-18",
        "name": "Alignment OLS Regression Dominant Slope Sign",
        "domain": "Calibration",
        "file": "src/0_development/alignment/modules/ols_regression_engine.lua",
        "target": "slope = k,",
        "replacement": "slope = -k,",
        "runner": "unit",
        "target_arg": "0_development/alignment",
    },
    {
        "id": "MUT-19",
        "name": "Sensors Avionics Canonical Type Support Guard",
        "domain": "Sensors",
        "file": "src/0_development/sensors/avionics_sensors.lua",
        "target": "return canon ~= nil",
        "replacement": "return false",
        "runner": "unit",
        "target_arg": "0_development/sensors",
    },
    {
        "id": "MUT-20",
        "name": "Installer Manifest Get Module Lookup",
        "domain": "Installer",
        "file": "src/0_development/installer/modules/manifest.lua",
        "target": "return manifest.MODULES[id]",
        "replacement": "return nil",
        "runner": "unit",
        "target_arg": "0_development/installer",
    },
    {
        "id": "MUT-21",
        "name": "VAS Vector VTOL Pseudo-Inverse Wrench Matrix Multiplication Sign Inversion",
        "domain": "Control",
        "file": "src/1_control/vas/modules/thrust_mixer.lua",
        "target": "sum = sum + (row[c] or 0.0) * (w[c] or 0.0)",
        "replacement": "sum = sum - (row[c] or 0.0) * (w[c] or 0.0)",
        "runner": "unit",
        "target_arg": "1_control/vas",
    },
    {
        "id": "MUT-22",
        "name": "TCA Vector Thruster Fail-Safe Nozzle Neutralization Bypass",
        "domain": "Safety",
        "file": "src/1_control/tca/modules/actuator_adapter.lua",
        "target": "pcall(item.wrapped.setVector, 0.0, 0.0)",
        "replacement": "-- pcall(item.wrapped.setVector, 0.0, 0.0)",
        "runner": "unit",
        "target_arg": "1_control/tca",
    },
    {
        "id": "MUT-23",
        "name": "FCP Advanced VTOL PID Surge Proportional Gain Sign Inversion",
        "domain": "Guidance",
        "file": "src/2_guidance/fcp/modules/advanced_vtol_driver.lua",
        "target": "local raw_surge = clamp(skp * err_surge - skd * vel_surge + s_i, -1.0, 1.0)",
        "replacement": "local raw_surge = clamp(-skp * err_surge - skd * vel_surge + s_i, -1.0, 1.0)",
        "runner": "unit",
        "target_arg": "2_guidance/fcp",
    },
    {
        "id": "MUT-24",
        "name": "GAC Dedicated Facility Rejection Classification Bypass",
        "domain": "Infra",
        "file": "src/0_infra/gac/modules/allocation_engine.lua",
        "target": "if hasDedicatedBlockingFree then",
        "replacement": "if false and hasDedicatedBlockingFree then",
        "runner": "unit",
        "target_arg": "0_infra/gac",
    },
    {
        "id": "MUT-25",
        "name": "GAC Emergency Dedicated Pad Commandeering Public-Free Guard Inversion",
        "domain": "Infra",
        "file": "src/0_infra/gac/modules/allocation_engine.lua",
        "target": "if not anyPublicFree then",
        "replacement": "if anyPublicFree then",
        "runner": "unit",
        "target_arg": "0_infra/gac",
    },
]


def run_mutation(mut: Dict[str, Any], verbose: bool = False) -> bool:
    """
    Applies mutation, runs test runner, checks if test fails, restores file.
    Returns True if mutant was KILLED (test caught the failure), False if SURVIVED.
    """
    file_path = WORKSPACE_ROOT / mut["file"]
    if not file_path.exists():
        print(f"  [ERROR] Target file not found: {file_path}")
        return False

    original_bytes = file_path.read_bytes()
    original_content = original_bytes.decode("utf-8")
    if mut["target"] not in original_content:
        print(f"  [ERROR] Target text not found in {file_path.name}")
        return False

    mutated_content = original_content.replace(mut["target"], mut["replacement"], 1)
    file_path.write_text(mutated_content, encoding="utf-8", newline="")

    try:
        if mut["runner"] == "unit":
            cmd = [
                sys.executable,
                str(RUN_UNIT_TESTS),
                "--target",
                mut["target_arg"],
                "--clean-orphans",
            ]
        else:
            cmd = [
                sys.executable,
                str(RUN_E2E_TESTS),
                "--filter",
                mut["target_arg"],
                "--clean-orphans",
            ]

        proc = subprocess.run(cmd, capture_output=True, text=True, cwd=str(WORKSPACE_ROOT))
        
        # A test failure means the mutation was KILLED (desired outcome!)
        is_killed = (proc.returncode != 0) or ("FAIL" in proc.stdout) or ("failed" in proc.stdout.lower())
        
        if verbose and not is_killed:
            print(f"    [STDOUT] {proc.stdout[:200]}")
            print(f"    [STDERR] {proc.stderr[:200]}")

        return is_killed
    finally:
        # Atomic restore
        file_path.write_bytes(original_bytes)


def main() -> int:
    parser = argparse.ArgumentParser(description="Create_Aeroneutics Mutation Testing Runner")
    parser.add_argument("--filter", "-f", type=str, default=None, help="Filter mutations by ID or domain")
    parser.add_argument("--verbose", "-v", action="store_true", help="Print verbose test logs on survived mutants")
    args = parser.parse_args()

    mutations = MUTATIONS
    if args.filter:
        flt = args.filter.lower()
        mutations = [m for m in mutations if flt in m["id"].lower() or flt in m["domain"].lower()]

    print(f"=== Create_Aeroneutics Mutation Testing ({len(mutations)} mutants) ===")
    start_time = time.time()
    killed_count = 0
    survived_count = 0

    for mut in mutations:
        is_killed = run_mutation(mut, verbose=args.verbose)
        if is_killed:
            killed_count += 1
            print(f"  [KILLED]   {mut['id']} ({mut['domain']}) - {mut['name']}")
        else:
            survived_count += 1
            print(f"  [SURVIVED] {mut['id']} ({mut['domain']}) - {mut['name']}")

    total = len(mutations)
    kill_rate = (killed_count / total * 100.0) if total > 0 else 0.0
    elapsed = time.time() - start_time

    print("\n=== Mutation Test Summary ===")
    print(f"  Total Mutants:   {total}")
    print(f"  Killed (Caught): {killed_count}")
    print(f"  Survived (Miss): {survived_count}")
    print(f"  Kill Rate:       {kill_rate:.1f}%")
    print(f"  Elapsed Time:    {elapsed:.2f}s")

    if kill_rate >= 90.0:
        print(f"\nResult: PASS (Kill Rate {kill_rate:.1f}% >= 90.0% threshold)")
        return 0
    else:
        print(f"\nResult: FAIL (Kill Rate {kill_rate:.1f}% < 90.0% threshold)")
        return 1


if __name__ == "__main__":
    sys.exit(main())
