#!/usr/bin/env python3
"""
Create_Aeroneutics 3-Way Static Consistency Verifier.

Cross-validates:
1. Runtime source tree (src/ and root installer.lua)
2. Unified installer manifest (src/0_development/installer/modules/manifest.lua)
3. Google Drive deployment mapping SSOT (config/gdrive_mapping.json)
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent

ALLOWED_MODULE_CATEGORIES = {
    "development",
    "infra",
    "control",
    "guidance",
    "planning",
    "mission",
}

LAYER_TO_CATEGORY = {
    "0_development": "development",
    "0_infra": "infra",
    "1_control": "control",
    "2_guidance": "guidance",
    "3_planning": "planning",
    "4_mission": "mission",
}

ALLOWED_GDRIVE_CATEGORIES = {
    "installer",
    "bootstrap",
    "shared",
    "packages",
}

INSTALLER_ENTRY_EXEMPTIONS = {
    "src/0_development/installer/installer.lua",
    "src/0_development/installer/main.lua",
}

DEFERRED_SUBSYSTEM_DIRS = {
    "src/1_control/asa",
}

SIMULATION_NODE_PATTERN = re.compile(r"^node_[a-z0-9_]+\.lua$")
SHARED_SENSOR_REPO_PATH = "src/0_development/sensors/avionics_sensors.lua"
SHARED_SENSOR_DEST = "/lib/avionics_sensors.lua"


@dataclass
class VerificationReport:
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    checked_modules: int = 0
    checked_manifest_files: int = 0
    checked_src_files: int = 0
    checked_gdrive_entries: int = 0

    @property
    def ok(self) -> bool:
        return len(self.errors) == 0


def _skip_lua_non_code(text: str, idx: int) -> int:
    """Advances idx past a Lua string literal or comment starting at idx, or returns idx."""
    n = len(text)
    ch = text[idx]

    # Single-line or long comment
    if ch == "-" and idx + 1 < n and text[idx + 1] == "-":
        if idx + 3 < n and text[idx + 2 : idx + 4] == "[[":
            end = text.find("]]", idx + 4)
            return n if end == -1 else end + 2
        nl = text.find("\n", idx + 2)
        return n if nl == -1 else nl + 1

    # Quoted strings
    if ch in ('"', "'"):
        quote = ch
        i = idx + 1
        while i < n:
            if text[i] == "\\":
                i += 2
                continue
            if text[i] == quote:
                return i + 1
            i += 1
        return n

    # Long bracket string [[ ... ]] or [=[ ... ]=]
    if ch == "[" and idx + 1 < n:
        m = re.match(r"\[(=*)\[", text[idx:])
        if m:
            eq = m.group(1)
            close_pat = "]" + eq + "]"
            end = text.find(close_pat, idx + len(m.group(0)))
            return n if end == -1 else end + len(close_pat)

    return idx


def extract_balanced_braces(text: str, start_idx: int) -> str:
    """Finds the first '{' at or after start_idx and returns the balanced '{...}' slice."""
    n = len(text)
    open_idx = text.find("{", start_idx)
    if open_idx == -1:
        raise ValueError(f"Opening brace not found after index {start_idx}")

    depth = 0
    i = open_idx
    while i < n:
        next_i = _skip_lua_non_code(text, i)
        if next_i != i:
            i = next_i
            continue
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[open_idx : i + 1]
        i += 1

    raise ValueError(f"Unbalanced braces starting at index {open_idx}")


def _extract_named_table(lua_text: str, field_pattern: str) -> str:
    m = re.search(field_pattern, lua_text)
    if not m:
        raise ValueError(f"Table declaration matching {field_pattern!r} not found")
    return extract_balanced_braces(lua_text, m.end() - 1)


def _iter_top_level_entries(table_block: str) -> List[Tuple[Optional[str], str]]:
    """
    Iterates top-level elements inside a '{ ... }' Lua table block.
    Returns list of (key_or_none, raw_value_slice).
    """
    inner = table_block[1:-1]
    n = len(inner)
    i = 0
    entries: List[Tuple[Optional[str], str]] = []

    while i < n:
        # Skip whitespace and separators
        while i < n and inner[i] in " \t\r\n,;":
            i += 1
        if i >= n:
            break

        # Skip comments
        next_i = _skip_lua_non_code(inner, i)
        if next_i != i and inner[i] == "-":
            i = next_i
            continue

        # Check optional key = value at depth 0
        key: Optional[str] = None
        m_ident = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*", inner[i:])
        m_bracket = re.match(r'\[\s*"([^"]+)"\s*\]\s*=\s*', inner[i:])
        if m_ident:
            key = m_ident.group(1)
            i += m_ident.end()
        elif m_bracket:
            key = m_bracket.group(1)
            i += m_bracket.end()

        if i >= n:
            break

        val_start = i
        depth = 0
        while i < n:
            next_i = _skip_lua_non_code(inner, i)
            if next_i != i:
                i = next_i
                continue
            ch = inner[i]
            if ch in "{(":
                depth += 1
            elif ch in "})":
                depth = max(0, depth - 1)
            elif ch in ",;" and depth == 0:
                break
            i += 1

        raw_val = inner[val_start:i].strip()
        if raw_val:
            entries.append((key, raw_val))
        i += 1

    return entries


def _unquote_lua_string(raw: str) -> Optional[str]:
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in ('"', "'"):
        return raw[1:-1]
    return None


def _parse_kv_table(table_block: str) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for k, v in _iter_top_level_entries(table_block):
        if k is not None:
            result[k] = v
    return result


def parse_bootstrap_entries(lua_text: str) -> List[Dict[str, Optional[str]]]:
    """Parses BOOTSTRAP_FILES = { ... } entries from installer.lua or manifest.lua."""
    block = _extract_named_table(lua_text, r"BOOTSTRAP_FILES\s*=\s*\{")
    entries: List[Dict[str, Optional[str]]] = []
    for _, raw_item in _iter_top_level_entries(block):
        if not raw_item.startswith("{"):
            continue
        kv = _parse_kv_table(raw_item)
        repo_path = _unquote_lua_string(kv.get("repoPath", ""))
        cache_rel = _unquote_lua_string(kv.get("cacheRelPath", ""))
        raw_gid = kv.get("gdriveId", "nil")
        gid = None if raw_gid == "nil" else _unquote_lua_string(raw_gid)
        if repo_path is not None:
            entries.append(
                {
                    "repoPath": repo_path,
                    "cacheRelPath": cache_rel,
                    "gdriveId": gid,
                }
            )
    return entries


def parse_manifest(manifest_path: Path) -> Dict[str, Any]:
    """Structurally parses manifest.lua without executing Lua."""
    text = manifest_path.read_text(encoding="utf-8")

    bootstrap_files = parse_bootstrap_entries(text)

    shared_block = _extract_named_table(text, r"SHARED_LIBS\s*=\s*\{")
    shared_libs: Dict[str, Dict[str, Optional[str]]] = {}
    for lib_key, raw_lib in _iter_top_level_entries(shared_block):
        if lib_key and raw_lib.startswith("{"):
            kv = _parse_kv_table(raw_lib)
            raw_gid = kv.get("gdriveId", "nil")
            shared_libs[lib_key] = {
                "repoPath": _unquote_lua_string(kv.get("repoPath", "")),
                "dest": _unquote_lua_string(kv.get("dest", "")),
                "gdriveId": None if raw_gid == "nil" else _unquote_lua_string(raw_gid),
            }

    order_block = _extract_named_table(text, r"MODULE_ORDER\s*=\s*\{")
    module_order: List[str] = []
    for _, raw_id in _iter_top_level_entries(order_block):
        mod_id = _unquote_lua_string(raw_id)
        if mod_id is not None:
            module_order.append(mod_id)

    modules_block = _extract_named_table(text, r"MODULES\s*=\s*\{")
    modules: Dict[str, Dict[str, Any]] = {}
    for mod_key, raw_mod in _iter_top_level_entries(modules_block):
        if not mod_key or not raw_mod.startswith("{"):
            continue
        kv = _parse_kv_table(raw_mod)

        files_list: List[Dict[str, Optional[str]]] = []
        if "files" in kv and kv["files"].startswith("{"):
            for _, raw_file in _iter_top_level_entries(kv["files"]):
                if not raw_file.startswith("{"):
                    continue
                fkv = _parse_kv_table(raw_file)
                raw_gid = fkv.get("gdriveId", "nil")
                repo_p = _unquote_lua_string(fkv.get("repoPath", ""))
                dest_p = _unquote_lua_string(fkv.get("dest", ""))
                if repo_p is not None:
                    files_list.append(
                        {
                            "repoPath": repo_p,
                            "dest": dest_p,
                            "gdriveId": None if raw_gid == "nil" else _unquote_lua_string(raw_gid),
                        }
                    )

        config_dests: Set[str] = set()
        if "defaultConfigs" in kv and kv["defaultConfigs"].startswith("{"):
            for cfg_key, _ in _iter_top_level_entries(kv["defaultConfigs"]):
                if cfg_key:
                    config_dests.add(cfg_key)
        if "configTemplate" in kv and kv["configTemplate"].startswith("{"):
            ckv = _parse_kv_table(kv["configTemplate"])
            tpath = _unquote_lua_string(ckv.get("targetPath", ""))
            if tpath:
                config_dests.add(tpath)

        modules[mod_key] = {
            "id": _unquote_lua_string(kv.get("id", "")),
            "name": _unquote_lua_string(kv.get("name", "")),
            "category": _unquote_lua_string(kv.get("category", "")),
            "version": _unquote_lua_string(kv.get("version", "")),
            "installDir": _unquote_lua_string(kv.get("installDir", "")),
            "files": files_list,
            "configDests": config_dests,
        }

    return {
        "bootstrap_files": bootstrap_files,
        "shared_libs": shared_libs,
        "module_order": module_order,
        "modules": modules,
    }


def _is_under_deferred_dir(rel_path: str) -> bool:
    for d in DEFERRED_SUBSYSTEM_DIRS:
        prefix = d.rstrip("/") + "/"
        if rel_path.startswith(prefix):
            return True
    return False


def verify_workspace(
    workspace_root: Path,
    strict_gdrive_packages: bool = False,
) -> VerificationReport:
    """Runs 3-way consistency verification across src/, manifest.lua, and gdrive_mapping.json."""
    report = VerificationReport()

    root_installer = workspace_root / "installer.lua"
    src_installer = workspace_root / "src" / "0_development" / "installer" / "installer.lua"
    manifest_path = (
        workspace_root
        / "src"
        / "0_development"
        / "installer"
        / "modules"
        / "manifest.lua"
    )
    gdrive_map_path = workspace_root / "config" / "gdrive_mapping.json"
    src_root = workspace_root / "src"

    if not root_installer.is_file():
        report.errors.append(f"MISSING_DISK_FILE: installer.lua missing at {root_installer}")
    if not src_installer.is_file():
        report.errors.append(
            f"MISSING_DISK_FILE: mirror installer missing at {src_installer}"
        )
    if not manifest_path.is_file():
        report.errors.append(f"MISSING_DISK_FILE: manifest.lua missing at {manifest_path}")
        return report

    try:
        manifest_data = parse_manifest(manifest_path)
    except Exception as exc:
        report.errors.append(f"MANIFEST_PARSE_ERROR: {exc}")
        return report

    bootstrap_files: List[Dict[str, Optional[str]]] = manifest_data["bootstrap_files"]
    shared_libs: Dict[str, Dict[str, Optional[str]]] = manifest_data["shared_libs"]
    module_order: List[str] = manifest_data["module_order"]
    modules: Dict[str, Dict[str, Any]] = manifest_data["modules"]

    report.checked_modules = len(modules)

    # 1. Installer parity & bootstrap sync
    if root_installer.is_file() and src_installer.is_file():
        if root_installer.read_bytes() != src_installer.read_bytes():
            report.errors.append(
                "INSTALLER_BYTE_PARITY_MISMATCH: installer.lua differs from src/0_development/installer/installer.lua"
            )

    if root_installer.is_file():
        try:
            inst_bootstrap = parse_bootstrap_entries(
                root_installer.read_text(encoding="utf-8")
            )
            if inst_bootstrap != bootstrap_files:
                report.errors.append(
                    "INSTALLER_BOOTSTRAP_LIST_MISMATCH: installer.lua BOOTSTRAP_FILES differs from manifest.lua BOOTSTRAP_FILES"
                )
        except Exception as exc:
            report.errors.append(f"INSTALLER_PARSE_ERROR: {exc}")

    # 2. Manifest internal integrity & module categories
    order_set = set(module_order)
    mod_keys = set(modules.keys())
    if len(order_set) != len(module_order):
        seen: Set[str] = set()
        dups = [m for m in module_order if m in seen or seen.add(m)]  # type: ignore[func-returns-value]
        report.errors.append(
            f"MODULE_ORDER_MISMATCH: duplicate module IDs in MODULE_ORDER: {dups}"
        )
    missing_from_order = sorted(mod_keys - order_set)
    missing_from_modules = sorted(order_set - mod_keys)
    if missing_from_order:
        report.errors.append(
            f"MODULE_ORDER_MISMATCH: modules in MODULES missing from MODULE_ORDER: {missing_from_order}"
        )
    if missing_from_modules:
        report.errors.append(
            f"MODULE_ORDER_MISMATCH: modules in MODULE_ORDER missing from MODULES: {missing_from_modules}"
        )

    subsys_config_dests: Dict[str, Set[str]] = {}
    registered_repo_paths: Set[str] = set()

    for b in bootstrap_files:
        if b["repoPath"]:
            registered_repo_paths.add(b["repoPath"])

    for lib_info in shared_libs.values():
        if lib_info.get("repoPath"):
            registered_repo_paths.add(lib_info["repoPath"])  # type: ignore[arg-type]

    for mod_key, mod_info in modules.items():
        if mod_info["id"] != mod_key:
            report.errors.append(
                f"MODULE_ID_MISMATCH: MODULES['{mod_key}'].id is {mod_info['id']!r}"
            )

        category = mod_info.get("category")
        if category not in ALLOWED_MODULE_CATEGORIES:
            report.errors.append(
                f"INVALID_MODULE_CATEGORY: module '{mod_key}' has invalid category {category!r}"
            )

        has_shared_sensor = False
        mod_subsys_dirs: Set[str] = set()
        for fentry in mod_info["files"]:
            repo_p = fentry["repoPath"]
            dest_p = fentry["dest"]
            if not repo_p:
                continue
            registered_repo_paths.add(repo_p)

            if repo_p == SHARED_SENSOR_REPO_PATH and dest_p == SHARED_SENSOR_DEST:
                has_shared_sensor = True

            is_shared_injection = (
                mod_key != "sensors" and repo_p == SHARED_SENSOR_REPO_PATH
            )
            if not is_shared_injection:
                m_layer = re.match(r"^src/([^/]+)/([^/]+)/", repo_p)
                if m_layer:
                    layer_dir, subsys_name = m_layer.group(1), m_layer.group(2)
                    mod_subsys_dirs.add(f"src/{layer_dir}/{subsys_name}")
                    expected_cat = LAYER_TO_CATEGORY.get(layer_dir)
                    if expected_cat and category in ALLOWED_MODULE_CATEGORIES and category != expected_cat:
                        report.errors.append(
                            f"INVALID_MODULE_CATEGORY: module '{mod_key}' category {category!r} conflicts with source layer '{layer_dir}' (expected {expected_cat!r})"
                        )

        if not has_shared_sensor:
            report.errors.append(
                f"MISSING_SHARED_SENSOR_LIB: module '{mod_key}' does not bundle {SHARED_SENSOR_REPO_PATH} -> {SHARED_SENSOR_DEST}"
            )

        for sub_dir in mod_subsys_dirs:
            subsys_config_dests.setdefault(sub_dir, set()).update(
                mod_info["configDests"]
            )

    report.checked_manifest_files = len(registered_repo_paths)

    # 3. Manifest <-> src/ bidirectional parity
    for repo_p in sorted(registered_repo_paths):
        if not (workspace_root / repo_p).is_file():
            report.errors.append(f"MISSING_DISK_FILE: manifest references missing file '{repo_p}'")

    for deferred_dir in sorted(DEFERRED_SUBSYSTEM_DIRS):
        prefix = deferred_dir.rstrip("/") + "/"
        if any(p.startswith(prefix) for p in registered_repo_paths):
            report.errors.append(
                f"STALE_DEFERRED_EXEMPTION: '{deferred_dir}' is now registered in manifest.lua and must be removed from DEFERRED_SUBSYSTEM_DIRS"
            )

    if src_root.is_dir():
        for disk_file in sorted(src_root.rglob("*")):
            if not disk_file.is_file():
                continue
            rel_p = disk_file.relative_to(workspace_root).as_posix()
            name = disk_file.name
            if name.startswith(".") or name == "README.md":
                continue

            report.checked_src_files += 1

            if disk_file.suffix == ".lua":
                if rel_p in registered_repo_paths or rel_p in INSTALLER_ENTRY_EXEMPTIONS:
                    continue
                if _is_under_deferred_dir(rel_p):
                    continue
                if SIMULATION_NODE_PATTERN.match(name):
                    continue
                report.errors.append(
                    f"ORPHAN_SRC_FILE: '{rel_p}' is not registered in manifest.lua"
                )
            elif disk_file.suffix == ".json":
                if rel_p in registered_repo_paths or _is_under_deferred_dir(rel_p):
                    continue
                m_sub = re.match(r"^(src/[^/]+/[^/]+)/(.+)$", rel_p)
                if m_sub:
                    sub_dir = m_sub.group(1)
                    cfg_dest = "/" + m_sub.group(2)
                    if cfg_dest in subsys_config_dests.get(sub_dir, set()):
                        continue
                report.errors.append(
                    f"ORPHAN_SRC_CONFIG_FILE: '{rel_p}' is not registered in manifest.lua files or defaultConfigs"
                )

    # 4. config/gdrive_mapping.json 3-way parity
    if not gdrive_map_path.is_file():
        report.errors.append(
            f"MISSING_GDRIVE_MAPPING_FILE: missing {gdrive_map_path}"
        )
        return report

    try:
        gdrive_data = json.loads(gdrive_map_path.read_text(encoding="utf-8"))
    except Exception as exc:
        report.errors.append(f"GDRIVE_MAPPING_PARSE_ERROR: {exc}")
        return report

    gdrive_files = gdrive_data.get("files")
    bootstrap_map = gdrive_data.get("bootstrapMap")
    if not isinstance(gdrive_files, dict) or not isinstance(bootstrap_map, dict):
        report.errors.append(
            "INVALID_GDRIVE_METADATA: 'files' and 'bootstrapMap' must be JSON objects"
        )
        return report

    expected_category_by_path: Dict[str, str] = {"installer.lua": "installer"}
    for b in bootstrap_files:
        if b["repoPath"]:
            expected_category_by_path[b["repoPath"]] = "bootstrap"
    for lib_info in shared_libs.values():
        rp = lib_info.get("repoPath")
        if rp and rp not in expected_category_by_path:
            expected_category_by_path[rp] = "shared"
    for rp in registered_repo_paths:
        if rp not in expected_category_by_path:
            expected_category_by_path[rp] = "packages"

    required_core = (
        {"installer.lua"}
        | {b["repoPath"] for b in bootstrap_files if b["repoPath"]}
        | {s["repoPath"] for s in shared_libs.values() if s.get("repoPath")}
    )

    for req_p in sorted(required_core):
        fmeta = gdrive_files.get(req_p)
        b_id = bootstrap_map.get(req_p)
        if not isinstance(fmeta, dict) or not fmeta.get("id"):
            report.errors.append(
                f"MISSING_REQUIRED_GDRIVE_MAPPING: '{req_p}' missing from gdrive_mapping.json files"
            )
        if not isinstance(b_id, str) or not b_id:
            report.errors.append(
                f"MISSING_REQUIRED_GDRIVE_MAPPING: '{req_p}' missing from gdrive_mapping.json bootstrapMap"
            )

    for b in bootstrap_files:
        rp = b["repoPath"]
        gid = b["gdriveId"]
        if not rp:
            continue
        fmeta = gdrive_files.get(rp)
        fid = fmeta.get("id") if isinstance(fmeta, dict) else None
        bid = bootstrap_map.get(rp)
        if not gid or fid != gid or bid != gid:
            report.errors.append(
                f"BOOTSTRAP_GDRIVE_ID_MISMATCH: '{rp}' manifest gdriveId={gid!r}, files.id={fid!r}, bootstrapMap={bid!r}"
            )

    for repo_p, fmeta in sorted(gdrive_files.items()):
        report.checked_gdrive_entries += 1
        if not (workspace_root / repo_p).is_file() or repo_p not in expected_category_by_path:
            report.errors.append(
                f"ORPHAN_GDRIVE_MAPPING: '{repo_p}' in gdrive_mapping.json is missing on disk or unregistered in manifest"
            )
            continue

        if not isinstance(fmeta, dict):
            report.errors.append(
                f"INVALID_GDRIVE_METADATA: entry '{repo_p}' must be a JSON object"
            )
            continue

        if fmeta.get("repoPath") != repo_p:
            report.errors.append(
                f"GDRIVE_REPO_PATH_MISMATCH: key '{repo_p}' has repoPath={fmeta.get('repoPath')!r}"
            )

        gcat = fmeta.get("category")
        expected_gcat = expected_category_by_path[repo_p]
        if gcat not in ALLOWED_GDRIVE_CATEGORIES or gcat != expected_gcat:
            report.errors.append(
                f"INVALID_GDRIVE_CATEGORY: '{repo_p}' has category={gcat!r}, expected={expected_gcat!r}"
            )

        fid = fmeta.get("id")
        durl = fmeta.get("downloadUrl", "")
        if not isinstance(fid, str) or not fid or not isinstance(durl, str) or f"id={fid}" not in durl:
            report.errors.append(
                f"INVALID_GDRIVE_METADATA: '{repo_p}' missing valid id or matching downloadUrl"
            )

    for repo_p, bid in sorted(bootstrap_map.items()):
        fmeta = gdrive_files.get(repo_p)
        fid = fmeta.get("id") if isinstance(fmeta, dict) else None
        if not isinstance(fmeta, dict) or fid != bid:
            report.errors.append(
                f"BOOTSTRAP_GDRIVE_ID_MISMATCH: bootstrapMap['{repo_p}']={bid!r} does not match files['{repo_p}'].id={fid!r}"
            )

    if strict_gdrive_packages:
        for repo_p in sorted(expected_category_by_path.keys()):
            if repo_p not in gdrive_files:
                report.errors.append(
                    f"UNMAPPED_PACKAGE_FILE: '{repo_p}' is not present in gdrive_mapping.json files"
                )

    return report


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Verify 3-way consistency across src/, manifest.lua, and config/gdrive_mapping.json."
    )
    parser.add_argument(
        "--workspace-root",
        type=Path,
        default=WORKSPACE_ROOT,
        help="Repository root directory to verify",
    )
    parser.add_argument(
        "--strict-gdrive-packages",
        action="store_true",
        help="Require all package files (not only installer/bootstrap/shared) to be mapped in gdrive_mapping.json",
    )
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = build_arg_parser().parse_args(argv)
    report = verify_workspace(
        args.workspace_root.resolve(),
        strict_gdrive_packages=args.strict_gdrive_packages,
    )

    print("=== Create_Aeroneutics 3-Way Manifest Sync Verification ===")
    print(f"Modules checked       : {report.checked_modules}")
    print(f"Manifest paths checked: {report.checked_manifest_files}")
    print(f"Source files scanned  : {report.checked_src_files}")
    print(f"GDrive entries checked: {report.checked_gdrive_entries}")

    for warn in report.warnings:
        print(f"[WARN] {warn}")
    for err in report.errors:
        print(f"[ERROR] {err}")

    print(
        f"Manifest 3-way sync verification complete: {len(report.errors)} Errors, {len(report.warnings)} Warnings"
    )
    return 0 if report.ok else 1


if __name__ == "__main__":
    sys.exit(main())
