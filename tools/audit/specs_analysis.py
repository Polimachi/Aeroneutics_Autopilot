"""Specification overlap, link graph, churn, and traceability analysis (L4)."""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from tools.audit.common import (
    iter_lua_files,
    iter_spec_files,
    parse_spec_metadata,
    run_git_name_only_log,
)
from tools.verify_contracts import DEFAULT_CONTRACTS_PATH, load_contracts

_LINK_PAT = re.compile(r"\[[^\]]+\]\(([^)#\s]+\.md)(?:#[^)]*)?\)")
_MSG_PAT = re.compile(r"\bMSG_[A-Z0-9_]+\b")
_IFACE_PAT = re.compile(r"\bI-\d+\b")


def _extract_meaningful_shingles(text: str) -> set[str]:
    """Extract normalized 5-word shingles from non-boilerplate markdown lines."""
    lines: list[str] = []
    in_rev = False
    for raw in text.splitlines():
        s = raw.strip()
        if s.startswith("### Revision History"):
            in_rev = True
            continue
        if in_rev and s.startswith("## "):
            in_rev = False
        if in_rev:
            continue
        if not s or s.startswith("#") or s.startswith("| :---") or s.startswith("---"):
            continue
        if s.startswith("> **연관 규격서**") or s.startswith("> - ["):
            continue
        norm = re.sub(r"[`*_>|]", " ", s.lower())
        norm = re.sub(r"\s+", " ", norm).strip()
        if len(norm) >= 25:
            lines.append(norm)

    words = " ".join(lines).split()
    if len(words) < 6:
        return set(lines)
    return {" ".join(words[i : i + 6]) for i in range(len(words) - 5)}


def analyze_specs(root: Path) -> dict[str, Any]:
    """Analyze spec sizes, cross-spec overlap, link graph, git co-change, and traceability."""
    root = root.resolve()
    spec_files = iter_spec_files(root)

    docs: list[dict[str, Any]] = []
    shingles_by_doc: dict[str, set[str]] = {}
    in_degree: dict[str, int] = {}
    out_edges: dict[str, list[str]] = {}
    msg_tokens_by_doc: dict[str, set[str]] = {}

    for sf in spec_files:
        meta = parse_spec_metadata(sf, root)
        doc_id = meta["id"]
        text = sf.read_text(encoding="utf-8", errors="replace")
        shingles_by_doc[doc_id] = _extract_meaningful_shingles(text)
        msg_tokens_by_doc[doc_id] = set(_MSG_PAT.findall(text))
        in_degree.setdefault(doc_id, 0)

        targets: list[str] = []
        for m in _LINK_PAT.finditer(text):
            rel_link = m.group(1)
            if rel_link.startswith(("http://", "https://")):
                continue
            resolved = (sf.parent / rel_link).resolve()
            if resolved.is_file():
                try:
                    t_id = resolved.relative_to(root).as_posix()
                    targets.append(t_id)
                    in_degree[t_id] = in_degree.get(t_id, 0) + 1
                except ValueError:
                    pass
        out_edges[doc_id] = sorted(set(targets))
        meta["msg_count"] = len(msg_tokens_by_doc[doc_id])
        meta["iface_refs"] = sorted(set(_IFACE_PAT.findall(text)))
        docs.append(meta)

    for d in docs:
        did = d["id"]
        d["in_degree"] = in_degree.get(did, 0)
        d["out_degree"] = len(out_edges.get(did, []))

    # Pairwise shingle overlap (containment = |A&B| / min(|A|,|B|), Jaccard = |A&B|/|A|B|)
    pairwise_overlap: list[dict[str, Any]] = []
    doc_ids = [d["id"] for d in docs]
    for i in range(len(doc_ids)):
        a_id = doc_ids[i]
        sa = shingles_by_doc[a_id]
        if not sa:
            continue
        for j in range(i + 1, len(doc_ids)):
            b_id = doc_ids[j]
            sb = shingles_by_doc[b_id]
            if not sb:
                continue
            inter = len(sa & sb)
            if inter == 0:
                continue
            containment = inter / min(len(sa), len(sb))
            jaccard = inter / len(sa | sb)
            if containment >= 0.05:
                pairwise_overlap.append({
                    "doc_a": a_id,
                    "doc_b": b_id,
                    "shared_shingles": inter,
                    "containment": round(containment, 4),
                    "jaccard": round(jaccard, 4),
                })
    pairwise_overlap.sort(key=lambda p: -p["containment"])

    # Git co-change churn across recent 100 commits
    commits = run_git_name_only_log(root, limit=100)
    spec_id_set = set(doc_ids)
    spec_commits = 0
    total_specs_per_commit = 0
    spec_touch_counts: dict[str, int] = {d: 0 for d in doc_ids}
    for files in commits:
        touched_specs = [f for f in files if f in spec_id_set]
        if touched_specs:
            spec_commits += 1
            total_specs_per_commit += len(touched_specs)
            for s in touched_specs:
                spec_touch_counts[s] += 1

    for d in docs:
        d["recent_commits"] = spec_touch_counts.get(d["id"], 0)

    # Traceability of MSG_* across specs, contracts, src/, tests/
    contracts_path = root / "config" / "protocol_contracts.json"
    if not contracts_path.is_file():
        contracts_path = DEFAULT_CONTRACTS_PATH
    contract_msgs: set[str] = set()
    if contracts_path.is_file():
        contracts = load_contracts(contracts_path)
        for iface in contracts.get("interfaces", []):
            contract_msgs.update(iface.get("packets", {}).keys())

    src_msgs: set[str] = set()
    for lf in iter_lua_files(root):
        src_msgs.update(_MSG_PAT.findall(lf.read_text(encoding="utf-8", errors="replace")))

    test_msgs: set[str] = set()
    tdir = root / "tests"
    if tdir.is_dir():
        for tf in tdir.rglob("*.lua"):
            test_msgs.update(_MSG_PAT.findall(tf.read_text(encoding="utf-8", errors="replace")))

    all_spec_msgs: set[str] = set().union(*msg_tokens_by_doc.values()) if msg_tokens_by_doc else set()
    traceability = {
        "spec_msg_total": len(all_spec_msgs),
        "in_contracts": len(all_spec_msgs & contract_msgs),
        "in_src": len(all_spec_msgs & src_msgs),
        "in_tests": len(all_spec_msgs & test_msgs),
        "spec_only_msgs": sorted(all_spec_msgs - src_msgs - contract_msgs),
    }

    return {
        "documents": sorted(docs, key=lambda d: -d["bytes"]),
        "pairwise_overlap": pairwise_overlap[:40],
        "cochange": {
            "commits_analyzed": len(commits),
            "spec_touching_commits": spec_commits,
            "avg_specs_per_spec_commit": (
                round(total_specs_per_commit / spec_commits, 2) if spec_commits > 0 else 0.0
            ),
        },
        "traceability": traceability,
    }
