"""Regression guard checks for installer mirror parity, oversize Lua files, and dead requiredKeys."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from tools.audit.common import SINGLE_READ_BYTE_LIMIT, iter_lua_files
from tools.audit.static_analysis import _analyze_protocol_fields
from tools.verify_contracts import DEFAULT_CONTRACTS_PATH, load_contracts


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_guard(root: Path, baseline_path: Path | None = None) -> dict[str, Any]:
    """Run P5-approved architectural regression guards (Fail on installer drift, Warn on new bloat/dead keys)."""
    root = root.resolve()
    bpath = baseline_path or (root / "config" / "audit_baselines.json")
    baseline: dict[str, Any] = {}
    if bpath.is_file():
        baseline = json.loads(bpath.read_text(encoding="utf-8"))

    errors: list[str] = []
    warnings: list[str] = []

    # 1. Fail on installer.lua mirror divergence if both copies exist
    pair = baseline.get("installer_mirror_pair") or [
        "installer.lua",
        "src/0_development/installer/installer.lua",
    ]
    if len(pair) == 2:
        p1, p2 = root / pair[0], root / pair[1]
        if p1.is_file() and p2.is_file():
            h1, h2 = _sha256(p1), _sha256(p2)
            if h1 != h2:
                errors.append(
                    f"Mirror drift detected between '{pair[0]}' ({h1[:12]}) and '{pair[1]}' ({h2[:12]})."
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
