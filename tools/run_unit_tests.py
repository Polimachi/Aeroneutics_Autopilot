"""
Universal unit test runner CLI for Create_Aeroneutics multi-codebase repositories.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

from harness.unit.config import discover_codebase_targets, resolve_craftos_paths
from harness.unit.engine import run_target_unit_tests
from harness.unit.session import clean_workspace_orphans


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run isolated CC:Tweaked unit tests across Create_Aeroneutics codebases."
    )
    parser.add_argument(
        "--target",
        "-t",
        type=str,
        default=None,
        help="Target codebase to test (e.g. '1_control/tca' or short name 'tca'). Default runs all.",
    )
    parser.add_argument(
        "--test-target",
        dest="test_target",
        type=str,
        default=None,
        help="Alias for --target.",
    )
    parser.add_argument(
        "--test-file",
        dest="test_file",
        type=str,
        default=None,
        help="Path to specific test file to target.",
    )
    parser.add_argument(
        "--filter",
        "-f",
        type=str,
        default=None,
        help="Substring filter applied to suite/case names.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output structured JSON results instead of human table.",
    )
    parser.add_argument(
        "--require-tests",
        action="store_true",
        help="Fail if any discovered target has no test_*.lua files.",
    )
    parser.add_argument(
        "--clean-orphans",
        action="store_true",
        help="Terminate any lingering CraftOS-PC console processes for this workspace before running.",
    )
    return parser


def run_cli(
    argv: list[str] | None = None, workspace_root: Path | None = None
) -> tuple[int, dict[str, Any]]:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    root = (workspace_root or WORKSPACE_ROOT).resolve()
    sessions_root = root / ".runtime" / "sessions"

    cleaned_summary = None
    if args.clean_orphans:
        cleaned_summary = clean_workspace_orphans(sessions_root)

    try:
        craftos_paths = resolve_craftos_paths()
    except FileNotFoundError as exc:
        err_payload = {
            "overall_status": "FAIL",
            "error": str(exc),
            "cleaned_orphans": cleaned_summary,
            "targets": [],
        }
        if args.json:
            print(json.dumps(err_payload, indent=2))
        else:
            print(f"[FAIL] {exc}")
        return 1, err_payload

    target_query = args.target or getattr(args, "test_target", None)
    test_filter = args.filter
    if getattr(args, "test_file", None):
        tf = Path(args.test_file).as_posix()
        parts = [p for p in tf.split("/") if p and p != "tests"]
        if len(parts) >= 2:
            target_query = target_query or f"{parts[0]}/{parts[1]}"
        elif len(parts) == 1:
            target_query = target_query or parts[0]
        stem = Path(tf).stem
        if stem.startswith("test_"):
            stem = stem[5:]
        for prefix in ("alignment_", "tca_", "vas_", "fcp_", "gac_", "gcs_", "gps_"):
            if stem.startswith(prefix):
                stem = stem[len(prefix):]
        if not test_filter:
            test_filter = stem

    try:
        targets = discover_codebase_targets(root, target_query=target_query)
    except ValueError as exc:
        err_payload = {
            "overall_status": "FAIL",
            "error": str(exc),
            "cleaned_orphans": cleaned_summary,
            "targets": [],
        }
        if args.json:
            print(json.dumps(err_payload, indent=2))
        else:
            print(f"[FAIL] {exc}")
        return 1, err_payload

    if not targets:
        empty_payload = {
            "overall_status": "SKIP",
            "message": "No codebase targets discovered in src/.",
            "cleaned_orphans": cleaned_summary,
            "targets": [],
        }
        if args.json:
            print(json.dumps(empty_payload, indent=2))
        else:
            print("[SKIP] No codebase targets discovered in src/.")
        return 0, empty_payload

    target_reports: list[dict[str, Any]] = []
    has_failure = False

    if not args.json:
        print(f"=== Create_Aeroneutics Unit Test Runner ({len(targets)} targets) ===")

    for tgt in targets:
        rep = run_target_unit_tests(
            target=tgt,
            craftos_paths=craftos_paths,
            sessions_root=sessions_root,
            test_filter=test_filter,
            require_tests=args.require_tests,
        )
        rep_dict = rep.to_dict()
        target_reports.append(rep_dict)

        if rep.status == "FAIL":
            has_failure = True

        if not args.json:
            tag = f"[{rep.status}]"
            details = f"({rep.passed_tests}/{rep.total_tests} passed, {rep.duration_ms:.1f}ms)"
            if rep.status == "SKIP":
                details = f"({rep.logs[0] if rep.logs else 'skipped'})"
            print(f"  {tag:<7} {tgt.target_id:<32} {details}")
            if rep.errors:
                for err in rep.errors:
                    print(f"          ! {err}")

    overall_status = "FAIL" if has_failure else "PASS"
    summary = {
        "overall_status": overall_status,
        "cleaned_orphans": cleaned_summary,
        "targets": target_reports,
    }

    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print(f"\nOverall Result: {overall_status}")

    return (0 if overall_status == "PASS" else 1), summary


def main(argv: list[str] | None = None) -> int:
    code, _ = run_cli(argv)
    return code


if __name__ == "__main__":
    sys.exit(main())
