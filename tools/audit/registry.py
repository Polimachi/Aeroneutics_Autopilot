"""Component registry builder for Create_Aeroneutics architecture audit."""
from __future__ import annotations

from pathlib import Path
from typing import Any

from tools.verify_contracts import DEFAULT_CONTRACTS_PATH, load_contracts
from tools.audit.common import (
    iter_lua_files,
    iter_spec_files,
    parse_spec_metadata,
    subsystem_for_path,
)


def build_registry(root: Path) -> dict[str, Any]:
    """Enumerate subsystems, Lua modules, channels, wire packets, and spec documents."""
    root = root.resolve()
    lua_files = iter_lua_files(root)
    spec_files = iter_spec_files(root)

    # Discover all subsystem directories under src/<layer>/<name>
    subsystems_map: dict[str, dict[str, Any]] = {}
    src_dir = root / "src"
    if src_dir.is_dir():
        for layer_dir in sorted(p for p in src_dir.iterdir() if p.is_dir()):
            for sub_dir in sorted(p for p in layer_dir.iterdir() if p.is_dir()):
                sid = f"{layer_dir.name}/{sub_dir.name}"
                subsystems_map[sid] = {
                    "id": sid,
                    "layer": layer_dir.name,
                    "name": sub_dir.name,
                    "path": f"src/{sid}",
                    "code_present": False,
                    "spec_only": False,
                    "file_count": 0,
                    "bytes": 0,
                    "lines": 0,
                }

    modules: list[dict[str, Any]] = []
    for lf in lua_files:
        rel = lf.resolve().relative_to(root).as_posix()
        sid = subsystem_for_path(root, lf)
        text = lf.read_text(encoding="utf-8", errors="replace")
        nbytes = lf.stat().st_size
        nlines = text.count("\n") + (1 if text and not text.endswith("\n") else 0)
        modules.append({
            "id": rel,
            "subsystem": sid,
            "bytes": nbytes,
            "lines": nlines,
        })
        if sid in subsystems_map:
            sub = subsystems_map[sid]
            sub["code_present"] = True
            sub["file_count"] += 1
            sub["bytes"] += nbytes
            sub["lines"] += nlines

    for sub in subsystems_map.values():
        if not sub["code_present"]:
            sub["spec_only"] = True

    contracts_path = root / "config" / "protocol_contracts.json"
    if not contracts_path.is_file():
        contracts_path = DEFAULT_CONTRACTS_PATH
    contracts = load_contracts(contracts_path)

    channels: list[dict[str, Any]] = []
    ac = contracts.get("channels", {}).get("aircraft", {})
    for zone_name, zdata in ac.get("zones", {}).items():
        for off in zdata.get("offsets", []):
            channels.append({
                "id": f"aircraft+{off}",
                "scope": "aircraft",
                "offset": off,
                "zone": zone_name,
            })
    hg = contracts.get("channels", {}).get("hangar", {})
    for cname, off in hg.get("offsets", {}).items():
        channels.append({
            "id": f"hangar+{off}",
            "scope": "hangar",
            "offset": off,
            "name": cname,
        })
    gl = contracts.get("channels", {}).get("global", {})
    descs = gl.get("descriptions", {})
    for ch in gl.get("fixed", []):
        channels.append({
            "id": f"global:{ch}",
            "scope": "global",
            "channel": ch,
            "description": descs.get(str(ch), ""),
        })

    packets: list[dict[str, Any]] = []
    for iface in contracts.get("interfaces", []):
        iface_id = iface.get("id")
        iface_specs = iface.get("specs", [])
        for ptype, pspec in iface.get("packets", {}).items():
            packets.append({
                "id": ptype,
                "interface": iface_id,
                "interface_name": iface.get("name"),
                "specs": iface_specs,
                "required_keys": list(pspec.get("requiredKeys", [])),
                "optional_keys": list(pspec.get("optionalKeys", [])),
                "deprecated": bool(pspec.get("deprecated", False)),
            })

    specs = [parse_spec_metadata(sf, root) for sf in spec_files]

    return {
        "subsystems": sorted(subsystems_map.values(), key=lambda s: s["id"]),
        "modules": modules,
        "channels": channels,
        "packets": packets,
        "specs": specs,
    }
