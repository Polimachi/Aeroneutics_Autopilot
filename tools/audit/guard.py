"""Regression guard checks for root installer SSOT, duplicate copies, oversize Lua files, and dead requiredKeys."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from tools.audit.common import SINGLE_READ_BYTE_LIMIT, iter_lua_files
from tools.audit.static_analysis import _analyze_protocol_fields
from tools.verify_contracts import DEFAULT_CONTRACTS_PATH, load_contracts


def run_guard(root: Path, baseline_path: Path | None = None) -> dict[str, Any]:
    """Run P5-approved architectural regression guards (Fail on missing/duplicate installer, Warn on new bloat/dead keys)."""
    root = root.resolve()
    bpath = baseline_path or (root / "config" / "audit_baselines.json")
    baseline: dict[str, Any] = {}
    if bpath.is_file():
        baseline = json.loads(bpath.read_text(encoding="utf-8"))

    errors: list[str] = []
    warnings: list[str] = []

    # 1. Fail if root installer.lua is missing or any forbidden duplicate copy exists
    root_installer = root / "installer.lua"
    if not root_installer.is_file():
        errors.append("Missing root SSOT installer 'installer.lua'.")

    forbidden_duplicates = baseline.get("installer_forbidden_duplicates")
    if forbidden_duplicates is None:
        forbidden_duplicates = ["src/0_development/installer/installer.lua"]
    for rel_dup in forbidden_duplicates:
        dup_path = root / rel_dup
        if dup_path.exists():
            errors.append(
                f"Forbidden duplicate installer copy detected at '{rel_dup}' (root 'installer.lua' is SSOT)."
            )

    # 2. Warn on new Lua files exceeding single-read limit (46,080 B)
    max_bytes = int(baseline.get("single_read_bytes") or SINGLE_READ_BYTE_LIMIT)
    exempt_lua = set(baseline.get("large_lua_exemptions") or [])
    src_texts: dict[str, str] = {}
    for lf in iter_lua_files(root):
        rel = lf.resolve().relative_to(root).as_posix()
        src_texts[rel] = lf.read_text(encoding="utf-8", errors="replace")
        nbytes = lf.stat().st_size
        if nbytes > max_bytes and rel not in exempt_lua:
            warnings.append(
                f"Oversize Lua module '{rel}' ({nbytes} B > {max_bytes} B single-read limit)."
            )

    # 3. Warn on newly introduced unconsumed requiredKeys (when contracts exist in root)
    contracts_path = root / "config" / "protocol_contracts.json"
    if contracts_path.is_file() or (baseline_path is None and DEFAULT_CONTRACTS_PATH.is_file() and (root / "src").is_dir()):
        known_dead_req = {
            tuple(item) for item in (baseline.get("unconsumed_required_keys_baseline") or [])
        }
        if contracts_path.is_file():
            contracts = load_contracts(contracts_path)
            req_map: dict[str, set[str]] = {}
            for iface in contracts.get("interfaces", []):
                for ptype, pspec in iface.get("packets", {}).items():
                    req_map[ptype] = set(pspec.get("requiredKeys", []))
            for entry in _analyze_protocol_fields(root, src_texts):
                ptype = entry["packet"]
                reqs = req_map.get(ptype, set())
                for k in entry["unreferenced_keys"]:
                    if k in reqs and (ptype, k) not in known_dead_req:
                        warnings.append(
                            f"Unconsumed requiredKey '{ptype}.{k}' has 0 reads in src/."
                        )

    return {
        "status": "FAIL" if errors else "PASS",
        "errors": errors,
        "warnings": warnings,
    }
