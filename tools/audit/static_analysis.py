"""Static code structure & protocol field consumption analysis (L2 & L3)."""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from harness.unit.static_guard import strip_lua_comments_and_strings
from tools.audit.common import extract_lua_functions, iter_lua_files, subsystem_for_path
from tools.verify_contracts import DEFAULT_CONTRACTS_PATH, load_contracts

_CFG_DEFAULT_ASSIGN = re.compile(r'([a-zA-Z_][a-zA-Z0-9_]*)\s*=')


def _find_unreferenced_functions(
    functions: list[dict[str, Any]],
    src_texts: dict[str, str],
    test_texts: dict[str, str],
) -> list[dict[str, Any]]:
    """Find functions whose short name appears only at its own definition in src/."""
    # Pre-strip comments/strings once per file for fast identifier lookup
    src_words_by_file: dict[str, dict[str, int]] = {}
    for path, text in src_texts.items():
        counts: dict[str, int] = {}
        stripped_txt, _ = strip_lua_comments_and_strings(text)
        for w in re.findall(r"\b[a-zA-Z_][a-zA-Z0-9_]*\b", stripped_txt):
            counts[w] = counts.get(w, 0) + 1
        src_words_by_file[path] = counts

    global_src_counts: dict[str, int] = {}
    for counts in src_words_by_file.values():
        for w, c in counts.items():
            global_src_counts[w] = global_src_counts.get(w, 0) + c

    global_test_counts: dict[str, int] = {}
    for text in test_texts.values():
        stripped_test, _ = strip_lua_comments_and_strings(text)
        for w in re.findall(r"\b[a-zA-Z_][a-zA-Z0-9_]*\b", stripped_test):
            global_test_counts[w] = global_test_counts.get(w, 0) + 1

    # Count how many functions share each short name
    def_counts: dict[str, int] = {}
    for fn in functions:
        short = fn["name"].split(".")[-1].split(":")[-1]
        def_counts[short] = def_counts.get(short, 0) + 1

    unreferenced: list[dict[str, Any]] = []
    for fn in functions:
        short = fn["name"].split(".")[-1].split(":")[-1]
        if short in ("init", "new", "create_app", "create_context", "step", "run", "main", "update"):
            continue
        if fn["is_local"]:
            file_count = src_words_by_file.get(fn["file"], {}).get(short, 0)
            if file_count <= 1:
                unreferenced.append({
                    "file": fn["file"],
                    "name": fn["name"],
                    "start_line": fn["start_line"],
                    "lines": fn["lines"],
                    "scope": "local",
                    "test_refs": global_test_counts.get(short, 0),
                })
        else:
            # Exported function: only flag if uniquely named and appears <= definition count in src
            if def_counts.get(short, 0) == 1 and global_src_counts.get(short, 0) <= 1:
                unreferenced.append({
                    "file": fn["file"],
                    "name": fn["name"],
                    "start_line": fn["start_line"],
                    "lines": fn["lines"],
                    "scope": "module",
                    "test_refs": global_test_counts.get(short, 0),
                })
    return unreferenced


def _analyze_protocol_fields(root: Path, src_texts: dict[str, str]) -> list[dict[str, Any]]:
    """Cross-check required/optional keys of every MSG_* packet against src/ references."""
    contracts_path = root / "config" / "protocol_contracts.json"
    if not contracts_path.is_file():
        contracts_path = DEFAULT_CONTRACTS_PATH
    if not contracts_path.is_file():
        return []

    contracts = load_contracts(contracts_path)
    # Build combined stripped+preserved text across all src lua files
    combined_src = "\n".join(src_texts.values())
    results: list[dict[str, Any]] = []

    for iface in contracts.get("interfaces", []):
        iface_id = iface.get("id")
        for ptype, pspec in iface.get("packets", {}).items():
            req_keys = list(pspec.get("requiredKeys", []))
            opt_keys = list(pspec.get("optionalKeys", []))
            all_keys = req_keys + opt_keys
            unreferenced_keys: list[str] = []
            key_counts: dict[str, int] = {}
            for k in all_keys:
                # Match .key, ["key"], ['key'], or key = (careful: count field read patterns too)
                read_pat = re.compile(
                    rf"(?:\.\s*{re.escape(k)}\b|\[\s*['\"]{re.escape(k)}['\"]\s*\])"
                )
                cnt = len(read_pat.findall(combined_src))
                key_counts[k] = cnt
                if cnt == 0:
                    unreferenced_keys.append(k)
            results.append({
                "packet": ptype,
                "interface": iface_id,
                "required_keys": len(req_keys),
                "optional_keys": len(opt_keys),
                "unreferenced_keys": unreferenced_keys,
                "key_read_counts": key_counts,
            })
    return results


def _analyze_config_keys(root: Path, src_texts: dict[str, str]) -> list[dict[str, Any]]:
    """Inspect config.json / config/*.json files under src/ for unreferenced leaf keys."""
    findings: list[dict[str, Any]] = []
    src_dir = root / "src"
    if not src_dir.is_dir():
        return findings

    for cfg_path in sorted(src_dir.rglob("*.json")):
        rel = cfg_path.resolve().relative_to(root.resolve()).as_posix()
        sid = subsystem_for_path(root, cfg_path)
        sub_src = "\n".join(
            txt for p, txt in src_texts.items() if p.startswith(f"src/{sid}/")
        )
        try:
            data = json.loads(cfg_path.read_text(encoding="utf-8"))
        except Exception:
            continue

        unused: list[str] = []

        def _walk(obj: Any, prefix: str = "") -> None:
            if isinstance(obj, dict):
                for k, v in obj.items():
                    key_path = f"{prefix}.{k}" if prefix else str(k)
                    if not re.search(rf"\b{re.escape(str(k))}\b", sub_src):
                        unused.append(key_path)
                    if isinstance(v, dict):
                        _walk(v, key_path)

        _walk(data)
        findings.append({
            "file": rel,
            "subsystem": sid,
            "unused_keys": unused,
        })
    return findings


def analyze_static(root: Path) -> dict[str, Any]:
    """Run static L2/L3 code metrics across src/ and installer.lua."""
    root = root.resolve()
    lua_files = iter_lua_files(root)

    src_texts: dict[str, str] = {}
    module_sizes: list[dict[str, Any]] = []
    all_functions: list[dict[str, Any]] = []

    for lf in lua_files:
        rel = lf.resolve().relative_to(root).as_posix()
        txt = lf.read_text(encoding="utf-8", errors="replace")
        src_texts[rel] = txt
        nlines = txt.count("\n") + (1 if txt and not txt.endswith("\n") else 0)
        module_sizes.append({
            "file": rel,
            "subsystem": subsystem_for_path(root, lf),
            "bytes": lf.stat().st_size,
            "lines": nlines,
        })
        all_functions.extend(extract_lua_functions(txt, rel))

    test_texts: dict[str, str] = {}
    tests_dir = root / "tests"
    if tests_dir.is_dir():
        for tf in sorted(tests_dir.rglob("*.lua")):
            rel = tf.resolve().relative_to(root).as_posix()
            test_texts[rel] = tf.read_text(encoding="utf-8", errors="replace")

    module_sizes_sorted = sorted(module_sizes, key=lambda m: -m["bytes"])
    top_n_mod = max(1, len(module_sizes_sorted) // 10)

    fn_sizes = sorted(
        [
            {
                "file": f["file"],
                "name": f["name"],
                "start_line": f["start_line"],
                "lines": f["lines"],
                "code_lines": f["code_lines"],
            }
            for f in all_functions
        ],
        key=lambda f: -f["lines"],
    )
    top_n_fn = max(1, len(fn_sizes) // 10) if fn_sizes else 0

    unreferenced_fns = _find_unreferenced_functions(all_functions, src_texts, test_texts)
    proto_fields = _analyze_protocol_fields(root, src_texts)
    config_keys = _analyze_config_keys(root, src_texts)

    return {
        "total_lua_files": len(module_sizes),
        "total_lua_bytes": sum(m["bytes"] for m in module_sizes),
        "total_lua_lines": sum(m["lines"] for m in module_sizes),
        "total_functions": len(all_functions),
        "module_sizes": module_sizes_sorted,
        "top_10pct_modules": module_sizes_sorted[:top_n_mod],
        "top_functions": fn_sizes[: max(20, top_n_fn)],
        "unreferenced_functions": unreferenced_fns,
        "protocol_field_consumption": proto_fields,
        "config_key_usage": config_keys,
    }
