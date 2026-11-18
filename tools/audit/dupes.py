"""Cross-subsystem function clone & drift detector (L3)."""
from __future__ import annotations

import difflib
import hashlib
import re
from collections import defaultdict
from pathlib import Path
from typing import Any

from tools.audit.common import extract_lua_functions, iter_lua_files, subsystem_for_path

_TOKEN_PAT = re.compile(r"[a-zA-Z_][a-zA-Z0-9_]*|\d+(?:\.\d+)?|[^\s\w]")


def _normalize_tokens(stripped_body: str) -> list[str]:
    return _TOKEN_PAT.findall(stripped_body)


def analyze_dupes(
    root: Path,
    min_code_lines: int = 6,
    similarity_threshold: float = 0.80,
) -> dict[str, Any]:
    """Detect exact and diverged (near-duplicate) Lua functions across distinct subsystems."""
    root = root.resolve()
    candidates: list[dict[str, Any]] = []

    for lf in iter_lua_files(root):
        rel = lf.resolve().relative_to(root).as_posix()
        sub = subsystem_for_path(root, lf)
        txt = lf.read_text(encoding="utf-8", errors="replace")
        for fn in extract_lua_functions(txt, rel):
            if fn["code_lines"] < min_code_lines:
                continue
            tokens = _normalize_tokens(fn["stripped_body"])
            if len(tokens) < 20:
                continue
            # Strip function header name tokens (up to first '(') so renamed exports still match
            try:
                paren_idx = tokens.index("(")
                body_tokens = tokens[paren_idx:]
            except ValueError:
                body_tokens = tokens
            norm_str = " ".join(body_tokens)
            digest = hashlib.sha1(norm_str.encode("utf-8")).hexdigest()[:12]
            candidates.append({
                "file": rel,
                "subsystem": sub,
                "name": fn["name"],
                "start_line": fn["start_line"],
                "lines": fn["lines"],
                "code_lines": fn["code_lines"],
                "hash": digest,
                "tokens": body_tokens,
                "token_set": set(body_tokens),
            })

    # 1. Exact clusters across >= 2 distinct subsystems
    by_hash: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for c in candidates:
        by_hash[c["hash"]].append(c)

    exact_clusters: list[dict[str, Any]] = []
    clustered_keys: set[tuple[str, str, int]] = set()
    for digest, items in by_hash.items():
        subs = sorted({i["subsystem"] for i in items})
        if len(subs) >= 2:
            exact_clusters.append({
                "hash": digest,
                "subsystems": subs,
                "occurrences": [
                    {
                        "subsystem": i["subsystem"],
                        "file": i["file"],
                        "name": i["name"],
                        "start_line": i["start_line"],
                        "lines": i["lines"],
                    }
                    for i in items
                ],
                "extra_lines": sum(i["lines"] for i in items[1:]),
            })
            for i in items:
                clustered_keys.add((i["file"], i["name"], i["start_line"]))

    exact_clusters.sort(key=lambda cl: (-cl["extra_lines"], -len(cl["occurrences"])))

    # 2. Near-duplicate (drift) pairs across distinct subsystems (excluding exact clusters)
    near_pairs: list[dict[str, Any]] = []
    n = len(candidates)
    for i in range(n):
        a = candidates[i]
        for j in range(i + 1, n):
            b = candidates[j]
            if a["subsystem"] == b["subsystem"]:
                continue
            if a["hash"] == b["hash"]:
                continue
            # Fast length & Jaccard prefilter before SequenceMatcher
            la, lb = len(a["tokens"]), len(b["tokens"])
            if min(la, lb) / max(la, lb) < similarity_threshold:
                continue
            inter = len(a["token_set"] & b["token_set"])
            union = len(a["token_set"] | b["token_set"])
            if union == 0 or (inter / union) < (similarity_threshold * 0.85):
                continue
            ratio = difflib.SequenceMatcher(None, a["tokens"], b["tokens"]).ratio()
            if ratio >= similarity_threshold:
                near_pairs.append({
                    "similarity": round(ratio, 3),
                    "a": {
                        "subsystem": a["subsystem"],
                        "file": a["file"],
                        "name": a["name"],
                        "start_line": a["start_line"],
                        "lines": a["lines"],
                    },
                    "b": {
                        "subsystem": b["subsystem"],
                        "file": b["file"],
                        "name": b["name"],
                        "start_line": b["start_line"],
                        "lines": b["lines"],
                    },
                })

    near_pairs.sort(key=lambda p: (-p["similarity"], -p["a"]["lines"]))

    return {
        "analyzed_functions": len(candidates),
        "exact_cluster_count": len(exact_clusters),
        "near_pair_count": len(near_pairs),
        "total_duplicated_lines": sum(c["extra_lines"] for c in exact_clusters),
        "exact_clusters": exact_clusters,
        "near_duplicates": near_pairs,
    }
