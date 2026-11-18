"""Split necessity (N1-N5) and feasibility (F1-F6) raw metric extractor (Track S)."""
from __future__ import annotations

import re
from collections import defaultdict, deque
from pathlib import Path
from typing import Any

from tools.audit.common import (
    SINGLE_READ_BYTE_LIMIT,
    LUA_THRESHOLDS,
    SPEC_BYTE_THRESHOLD,
    SUBSYSTEM_BYTE_THRESHOLD,
    WEBUI_BYTE_THRESHOLD,
    extract_lua_functions,
    iter_lua_files,
    iter_spec_files,
    parse_spec_metadata,
    run_git_name_only_log,
    subsystem_for_path,
)
from tools.audit.specs_analysis import analyze_specs

_WORD_PAT = re.compile(r"\b[a-zA-Z_][a-zA-Z0-9_]*\b")


def _build_internal_call_graph(functions: list[dict[str, Any]]) -> dict[str, Any]:
    """Build undirected function adjacency within one Lua file to measure clusters & cross-edges."""
    short_names = [f["name"].split(".")[-1].split(":")[-1] for f in functions]
    idx_by_name: dict[str, int] = {}
    for idx, sn in enumerate(short_names):
        idx_by_name.setdefault(sn, idx)

    adj: dict[int, set[int]] = defaultdict(set)
    for idx, fn in enumerate(functions):
        words = set(_WORD_PAT.findall(fn["stripped_body"]))
        for w in words:
            target = idx_by_name.get(w)
            if target is not None and target != idx:
                adj[idx].add(target)
                adj[target].add(idx)

    visited: set[int] = set()
    components: list[list[int]] = []
    for i in range(len(functions)):
        if i in visited:
            continue
        comp: list[int] = []
        q = deque([i])
        visited.add(i)
        while q:
            u = q.popleft()
            comp.append(u)
            for v in adj[u]:
                if v not in visited:
                    visited.add(v)
                    q.append(v)
        components.append(comp)

    return {
        "function_count": len(functions),
        "connected_components": len(components),
        "edge_count": sum(len(vs) for vs in adj.values()) // 2,
    }


def _count_repo_refs(root: Path, needles: list[str], search_dirs: list[Path]) -> int:
    """Count files in search_dirs mentioning any needle."""
    hits = 0
    for d in search_dirs:
        if d.is_file():
            txt = d.read_text(encoding="utf-8", errors="replace")
            if any(n in txt for n in needles):
                hits += 1
        elif d.is_dir():
            for p in d.rglob("*"):
                if p.is_file() and p.suffix in (".lua", ".py", ".json", ".md"):
                    txt = p.read_text(encoding="utf-8", errors="replace")
                    if any(n in txt for n in needles):
                        hits += 1
    return hits


def analyze_splits(root: Path) -> dict[str, Any]:
    """Identify large Lua files, subsystems, specs, and WebUI candidates with N/F metrics."""
    root = root.resolve()
    commits = run_git_name_only_log(root, limit=100)
    churn_by_file: dict[str, int] = {}
    for files in commits:
        for f in files:
            churn_by_file[f] = churn_by_file.get(f, 0) + 1

    # 1. Subsystem byte totals
    sub_totals: dict[str, dict[str, Any]] = {}
    lua_files = iter_lua_files(root)
    for lf in lua_files:
        sid = subsystem_for_path(root, lf)
        if sid == "root":
            continue
        rec = sub_totals.setdefault(sid, {"id": sid, "bytes": 0, "lines": 0, "files": 0})
        txt = lf.read_text(encoding="utf-8", errors="replace")
        rec["bytes"] += lf.stat().st_size
        rec["lines"] += txt.count("\n") + (1 if txt and not txt.endswith("\n") else 0)
        rec["files"] += 1

    subsystem_candidates = sorted(
        [s for s in sub_totals.values() if s["bytes"] >= SUBSYSTEM_BYTE_THRESHOLD],
        key=lambda s: -s["bytes"],
    )

    # 2. Lua file candidates
    manifest_file = root / "src" / "0_development" / "installer" / "modules" / "manifest.lua"
    gdrive_file = root / "config" / "gdrive_mapping.json"
    contracts_file = root / "config" / "protocol_contracts.json"
    wiring_file = root / "tools" / "verify_runtime_wiring.py"
    tests_dir = root / "tests"

    lua_candidates: list[dict[str, Any]] = []
    for lf in lua_files:
        rel = lf.resolve().relative_to(root).as_posix()
        nbytes = lf.stat().st_size
        txt = lf.read_text(encoding="utf-8", errors="replace")
        nlines = txt.count("\n") + (1 if txt and not txt.endswith("\n") else 0)
        if nbytes < LUA_THRESHOLDS["bytes"] and nlines < LUA_THRESHOLDS["lines"]:
            continue

        fns = extract_lua_functions(txt, rel)
        cg = _build_internal_call_graph(fns)
        stem = lf.stem
        sid = subsystem_for_path(root, lf)
        sub_test_dir = tests_dir / sid if sid != "root" else tests_dir
        test_refs = _count_repo_refs(root, [stem, rel], [sub_test_dir])
        deploy_refs = _count_repo_refs(root, [rel, stem], [manifest_file, gdrive_file])
        gate_refs = _count_repo_refs(root, [rel, stem], [contracts_file, wiring_file])

        lua_candidates.append({
            "id": rel,
            "subsystem": sid,
            "bytes": nbytes,
            "lines": nlines,
            "read_chunks_needed": round(nbytes / SINGLE_READ_BYTE_LIMIT, 2),
            "recent_commits": churn_by_file.get(rel, 0),
            "call_graph": cg,
            "test_file_refs": test_refs,
            "deploy_refs": deploy_refs,
            "gate_refs": gate_refs,
            "is_data_heavy": rel.endswith("manifest.lua"),
            "single_file_constraint": rel == "installer.lua",
        })
    lua_candidates.sort(key=lambda c: -c["bytes"])

    # 3. Spec candidates
    specs_overview = analyze_specs(root)
    doc_map = {d["id"]: d for d in specs_overview["documents"]}
    spec_candidates: list[dict[str, Any]] = []
    for sf in iter_spec_files(root):
        meta = parse_spec_metadata(sf, root)
        if meta["bytes"] < SPEC_BYTE_THRESHOLD:
            continue
        did = meta["id"]
        dinfo = doc_map.get(did, {})
        # Compute section sizes
        text = sf.read_text(encoding="utf-8", errors="replace")
        sections = re.split(r"(?m)^(?=##\s+)", text)
        max_sec_bytes = max((len(s.encode("utf-8")) for s in sections), default=0)
        spec_candidates.append({
            "id": did,
            "status": meta["status"],
            "bytes": meta["bytes"],
            "lines": meta["lines"],
            "read_chunks_needed": round(meta["bytes"] / SINGLE_READ_BYTE_LIMIT, 2),
            "section_count": meta["section_count"],
            "max_section_bytes": max_sec_bytes,
            "recent_commits": churn_by_file.get(did, 0),
            "in_degree_links": dinfo.get("in_degree", 0),
            "out_degree_links": dinfo.get("out_degree", 0),
        })
    spec_candidates.sort(key=lambda c: -c["bytes"])

    # 4. WebUI candidates
    webui_candidates: list[dict[str, Any]] = []
    webui_path = root / "tools" / "amm_mission_editor.html"
    if webui_path.is_file() and webui_path.stat().st_size >= WEBUI_BYTE_THRESHOLD:
        wtxt = webui_path.read_text(encoding="utf-8", errors="replace")
        wbytes = webui_path.stat().st_size
        style_bytes = sum(len(m.group(0).encode("utf-8")) for m in re.finditer(r"<style[^>]*>.*?</style>", wtxt, re.S))
        script_bytes = sum(len(m.group(0).encode("utf-8")) for m in re.finditer(r"<script[^>]*>.*?</script>", wtxt, re.S))
        rel = "tools/amm_mission_editor.html"
        webui_candidates.append({
            "id": rel,
            "bytes": wbytes,
            "lines": wtxt.count("\n") + 1,
            "read_chunks_needed": round(wbytes / SINGLE_READ_BYTE_LIMIT, 2),
            "style_bytes": style_bytes,
            "script_bytes": script_bytes,
            "html_shell_bytes": max(0, wbytes - style_bytes - script_bytes),
            "recent_commits": churn_by_file.get(rel, 0),
            "single_file_constraint": True,
        })

    return {
        "thresholds": {
            "lua": LUA_THRESHOLDS,
            "subsystem_bytes": SUBSYSTEM_BYTE_THRESHOLD,
            "spec_bytes": SPEC_BYTE_THRESHOLD,
            "webui_bytes": WEBUI_BYTE_THRESHOLD,
            "single_read_bytes": SINGLE_READ_BYTE_LIMIT,
        },
        "subsystem_candidates": subsystem_candidates,
        "lua_candidates": lua_candidates,
        "spec_candidates": spec_candidates,
        "webui_candidates": webui_candidates,
    }
