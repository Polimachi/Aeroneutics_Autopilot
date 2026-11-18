"""CLI entry point for python -m tools.audit."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Callable

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.audit.dupes import analyze_dupes
from tools.audit.registry import build_registry
from tools.audit.specs_analysis import analyze_specs
from tools.audit.split_analysis import analyze_splits
from tools.audit.static_analysis import analyze_static

SUBCOMMANDS: dict[str, Callable[[Path], dict[str, Any]]] = {
    "registry": build_registry,
    "static": analyze_static,
    "dupes": analyze_dupes,
    "specs": analyze_specs,
    "split": analyze_splits,
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m tools.audit",
        description="Run Create_Aeroneutics architecture efficiency & utility audit collectors.",
    )
    parser.add_argument(
        "command",
        choices=[*SUBCOMMANDS.keys(), "all"],
        help="Audit collector subcommand to execute.",
    )
    parser.add_argument(
        "--root",
        type=str,
        default=None,
        help="Repository root override (default: repo root).",
    )
    parser.add_argument(
        "--out",
        type=str,
        default=None,
        help="Directory to write <command>.json outputs.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print JSON summary to stdout.",
    )
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else REPO_ROOT
    out_dir = Path(args.out).resolve() if args.out else None
    if out_dir is not None:
        out_dir.mkdir(parents=True, exist_ok=True)

    cmds = list(SUBCOMMANDS.keys()) if args.command == "all" else [args.command]
    results: dict[str, Any] = {}
    for cmd in cmds:
        data = SUBCOMMANDS[cmd](root)
        results[cmd] = data
        if out_dir is not None:
            (out_dir / f"{cmd}.json").write_text(
                json.dumps(data, indent=2, ensure_ascii=False),
                encoding="utf-8",
            )

    if args.json:
        payload = results if args.command == "all" else results[args.command]
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        for cmd, data in results.items():
            print(f"[audit:{cmd}] ok -> keys={list(data.keys())}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
