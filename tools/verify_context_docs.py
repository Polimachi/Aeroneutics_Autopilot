"""Static checker for Create_Aeroneutics root context documentation drift."""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import re
import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
MAX_GEMINI_LINES = 80
ARCHIVE_CAP = 10
GEMINI_SECTIONS = (
    "## 1. Current Phase & Active Handover",
    "## 2. Confirmed Architecture & Paths",
    "## 3. Standard Commands",
    "## 4. Gotchas & Invariants",
)
BANNED_TERMS = (
    "세계 최고 수준",
    "최고 수준",
    "무결점",
    "완벽",
    "원천 차단",
    "무오염",
    "100% 보장",
    "world-class",
    "best-in-class",
    "flawless",
    "zero-defect",
    "bulletproof",
)
GUARANTEE_RE = re.compile(r"\bguarantee[sd]?\b", re.IGNORECASE)

_README_COUNT_RE = re.compile(r"\b\d+/\d+\s*(?:PASS|KILLED|passed)\b")
_SORTED_BANNED_TERMS = tuple(sorted(BANNED_TERMS, key=len, reverse=True))
_PARENT_TASK_RE = re.compile(r"^- \[( |-|x)\] \*\*(?:\[연기\] )?TASK-(\d+)\b")
_CHILD_TASK_RE = re.compile(r"^\s+- \[( |-|x)\] \*\*TASK-(\d+)-\d+")
_ARCHIVE_TASK_RE = re.compile(r"^- \[x\] \*\*(TASK-\d+)\b")

_STATUS_META_RE = re.compile(r"\|\s*\*\*문서 상태 \(Status\)\*\*\s*\|\s*`([^`]+)`\s*\|")
_VERSION_META_RE = re.compile(
    r"\|\s*\*\*문서 버전 \(Version\)\*\*\s*\|\s*`(v\d+\.\d+\.\d+)`\s*\|"
)
_GEMINI_DIST_RE = re.compile(r"(\d+)\s+Implemented,\s+(\d+)\s+Approved")
_TASK_SPEC_REF_RE = re.compile(
    r"`(docs/(?:specs|system)/[^`]+\.md)`\s*\(?(?:현재\s+)?(v\d+\.\d+\.\d+)(?:\s+(Draft|Approved|Implemented|Deprecated))?"
)
_MEMORY_HEADING_RE = re.compile(r"^## \d{4}-\d{2}-\d{2} — ")
_TASK_ID_RE = re.compile(r"\bTASK-\d+\b")

_TREE_LINE_RE = re.compile(r"^([│ ]*)(?:├──|└──)\s+(.*)$")
_BRACE_DIR_RE = re.compile(r"^([A-Za-z0-9_]+)/\{([^}]+)\}/?$")
_NESTED_DIR_RE = re.compile(r"^([A-Za-z0-9_]+)/([A-Za-z0-9_]+)/?$")
_PAREN_SUBDIRS_RE = re.compile(r"\(([a-z][a-z0-9_]*(?:\s*,\s*[a-z][a-z0-9_]*)*)\)")
_README_E2E_RE = re.compile(r"(\d+)개\s+통합\s+시뮬레이션\s+스위트\((\d+)개\s+케이스\)")
_README_SPEC_TOTAL_RE = re.compile(r"활성\s+사양서\s+(\d+)종")
_README_VERIFY_SPECS_RE = re.compile(r"(\d+)대\s+활성\s+사양서")
_README_VERIFY_SPECS_INLINE_RE = re.compile(r"verify_all_specs\.py.*?(\d+)대\s+사양서")
_E2E_IT_RE = re.compile(r"^\s*it\s*\(", re.MULTILINE)
_SPEC_FILES_BLOCK_RE = re.compile(r"SPEC_FILES\s*=\s*\[([^\]]+)\]")


@dataclass(frozen=True)
class Finding:
    rule: str
    path: str
    line: int
    message: str

    def format(self) -> str:
        return f"[{self.rule}] {self.path}:L{self.line}: {self.message}"


def check_readme_counts(text: str, path: str = "README.md") -> list[Finding]:
    findings: list[Finding] = []
    for idx, line in enumerate(text.splitlines(), 1):
        m = _README_COUNT_RE.search(line)
        if m:
            findings.append(
                Finding(
                    "R1",
                    path,
                    idx,
                    f"duplicate test count '{m.group(0)}' (SSOT is GEMINI.md)",
                )
            )
    return findings


def check_overclaim(text: str, path: str) -> list[Finding]:
    findings: list[Finding] = []
    for idx, line in enumerate(text.splitlines(), 1):
        lower_line = line.lower()
        matched_lower: list[str] = []
        for term in _SORTED_BANNED_TERMS:
            term_lower = term.lower()
            if term_lower in lower_line:
                if any(term_lower in prev for prev in matched_lower):
                    continue
                matched_lower.append(term_lower)
                findings.append(
                    Finding("R2", path, idx, f"banned overclaim term '{term}'")
                )
        m = GUARANTEE_RE.search(line)
        if m:
            findings.append(
                Finding("R2", path, idx, f"banned overclaim term '{m.group(0)}'")
            )
    return findings


def check_gemini_structure(text: str, path: str = "GEMINI.md") -> list[Finding]:
    findings: list[Finding] = []
    lines = text.splitlines()
    if len(lines) > MAX_GEMINI_LINES:
        findings.append(
            Finding(
                "R3",
                path,
                MAX_GEMINI_LINES + 1,
                f"line count {len(lines)} exceeds {MAX_GEMINI_LINES}",
            )
        )
    headings = [(idx, line) for idx, line in enumerate(lines, 1) if line.startswith("## ")]
    if tuple(h for _, h in headings) != GEMINI_SECTIONS:
        line_no = headings[0][0] if headings else 1
        findings.append(
            Finding(
                "R3",
                path,
                line_no,
                "section headings do not match the 4 required fixed sections",
            )
        )
    return findings


def check_task_markers(text: str, path: str = "TASK.md") -> list[Finding]:
    parents: list[tuple[int, str, str, list[str]]] = []
    for idx, line in enumerate(text.splitlines(), 1):
        pm = _PARENT_TASK_RE.match(line)
        if pm:
            parents.append((idx, pm.group(1), pm.group(2), []))
            continue
        cm = _CHILD_TASK_RE.match(line)
        if cm and parents:
            parents[-1][3].append(cm.group(1))

    findings: list[Finding] = []
    for line_no, state, task_num, child_states in parents:
        if state == " " and "x" in child_states:
            findings.append(
                Finding("R6", path, line_no, f"TASK-{task_num} parent should be [-]")
            )
        elif state == "x" and any(s in (" ", "-") for s in child_states):
            findings.append(
                Finding(
                    "R6", path, line_no, f"TASK-{task_num} parent closed with open child"
                )
            )
    return findings


def _archive_section_entries(text: str) -> list[tuple[int, str]]:
    in_archive = False
    entries: list[tuple[int, str]] = []
    for idx, line in enumerate(text.splitlines(), 1):
        if line.startswith("## ✅ 3."):
            in_archive = True
            continue
        if in_archive and line.startswith("## "):
            break
        if in_archive:
            m = _ARCHIVE_TASK_RE.match(line)
            if m:
                entries.append((idx, m.group(1)))
    return entries


def check_task_archive_cap(text: str, path: str = "TASK.md") -> list[Finding]:
    entries = _archive_section_entries(text)
    if len(entries) > ARCHIVE_CAP:
        overflow_line = entries[ARCHIVE_CAP][0]
        return [
            Finding(
                "R7",
                path,
                overflow_line,
                f"completed archive has {len(entries)} items (cap {ARCHIVE_CAP})",
            )
        ]
    return []


def archived_task_ids(text: str) -> list[str]:
    return [task_id for _, task_id in _archive_section_entries(text)]


def read_spec_meta(path: Path) -> tuple[str, str] | None:
    content = path.read_text(encoding="utf-8-sig")
    vm = _VERSION_META_RE.search(content)
    sm = _STATUS_META_RE.search(content)
    if not vm or not sm:
        return None
    return vm.group(1).strip(), sm.group(1).strip()


def iter_spec_files(repo_root: Path) -> list[Path]:
    paths: list[Path] = []
    sys_dir = repo_root / "docs" / "system"
    if sys_dir.is_dir():
        paths.extend(p for p in sys_dir.glob("*.md") if p.name != "README.md")
    specs_dir = repo_root / "docs" / "specs"
    if specs_dir.is_dir():
        paths.extend(p for p in specs_dir.rglob("*.md") if p.name != "README.md")
    return sorted(set(paths))


def _spec_status_counts(repo_root: Path) -> tuple[int, int]:
    actual_impl = 0
    actual_appr = 0
    for spec_path in iter_spec_files(repo_root):
        meta = read_spec_meta(spec_path)
        if not meta:
            continue
        _, status = meta
        if status == "Implemented":
            actual_impl += 1
        elif status == "Approved":
            actual_appr += 1
    return actual_impl, actual_appr


def check_gemini_spec_distribution(gemini_text: str, repo_root: Path) -> list[Finding]:
    actual_impl, actual_appr = _spec_status_counts(repo_root)

    findings: list[Finding] = []
    found_any = False
    for idx, line in enumerate(gemini_text.splitlines(), 1):
        for m in _GEMINI_DIST_RE.finditer(line):
            found_any = True
            listed_impl = int(m.group(1))
            listed_appr = int(m.group(2))
            if listed_impl != actual_impl or listed_appr != actual_appr:
                findings.append(
                    Finding(
                        "R4",
                        "GEMINI.md",
                        idx,
                        f"spec distribution mismatch: listed ({listed_impl} Implemented, {listed_appr} Approved), actual ({actual_impl} Implemented, {actual_appr} Approved)",
                    )
                )
    if not found_any:
        findings.append(
            Finding(
                "R4",
                "GEMINI.md",
                1,
                f"missing spec status counts (expected {actual_impl} Implemented, {actual_appr} Approved)",
            )
        )
    return findings


def check_task_spec_versions(
    task_text: str, repo_root: Path, path: str = "TASK.md"
) -> list[Finding]:
    findings: list[Finding] = []
    for idx, line in enumerate(task_text.splitlines(), 1):
        for m in _TASK_SPEC_REF_RE.finditer(line):
            rel_path, listed_ver, listed_status = m.group(1), m.group(2), m.group(3)
            spec_path = repo_root / rel_path
            if not spec_path.is_file():
                findings.append(Finding("R5", path, idx, f"missing spec file '{rel_path}'"))
                continue
            meta = read_spec_meta(spec_path)
            if meta is None:
                findings.append(
                    Finding("R5", path, idx, f"missing metadata table in '{rel_path}'")
                )
                continue
            actual_ver, actual_status = meta
            if listed_ver != actual_ver:
                findings.append(
                    Finding(
                        "R5",
                        path,
                        idx,
                        f"{rel_path} version mismatch: listed {listed_ver}, actual {actual_ver}",
                    )
                )
            if listed_status is not None and listed_status != actual_status:
                findings.append(
                    Finding(
                        "R5",
                        path,
                        idx,
                        f"{rel_path} status mismatch: listed {listed_status}, actual {actual_status}",
                    )
                )
    return findings


def memory_heading_task_ids(memory_texts: dict[str, str]) -> set[str]:
    covered: set[str] = set()
    for text in memory_texts.values():
        for line in text.splitlines():
            if _MEMORY_HEADING_RE.match(line):
                covered.update(_TASK_ID_RE.findall(line))
    return covered


def check_memory_coverage(
    task_text: str, memory_texts: dict[str, str], path: str = "TASK.md"
) -> list[Finding]:
    covered = memory_heading_task_ids(memory_texts)
    return [
        Finding(
            "R8",
            path,
            line_no,
            f"{task_id} archived in TASK.md but missing from .agent/memory/*.md headings",
        )
        for line_no, task_id in _archive_section_entries(task_text)
        if task_id not in covered
    ]


def _iter_domain_subsystems(root: Path, include_flat: bool = False) -> set[str]:
    if not root.is_dir():
        return set()
    items: set[str] = set()
    for top in sorted(root.iterdir()):
        if not top.is_dir() or top.name.startswith(".") or top.name == "__pycache__":
            continue
        subs = [
            s
            for s in top.iterdir()
            if s.is_dir() and not s.name.startswith(".") and s.name != "__pycache__"
        ]
        if subs:
            items.update(f"{top.name}/{sub.name}" for sub in subs)
        elif include_flat:
            items.add(top.name)
    return items


def _expand_tree_dir_entry(raw_path: str, comment: str, allow_flat: bool) -> list[str]:
    brace_m = _BRACE_DIR_RE.match(raw_path)
    if brace_m:
        layer, inner = brace_m.group(1), brace_m.group(2)
        return [f"{layer}/{tok.strip()}" for tok in inner.split(",") if tok.strip()]
    nested_m = _NESTED_DIR_RE.match(raw_path)
    if nested_m:
        return [f"{nested_m.group(1)}/{nested_m.group(2)}"]
    layer = raw_path.rstrip("/")
    if "/" in layer:
        return []
    paren_m = _PAREN_SUBDIRS_RE.search(comment)
    if paren_m:
        return [f"{layer}/{tok.strip()}" for tok in paren_m.group(1).split(",") if tok.strip()]
    return [layer] if allow_flat else []


def _parse_readme_tree(
    readme_text: str,
) -> tuple[dict[str, int], dict[str, dict[str, int]]]:
    section_lines: dict[str, int] = {}
    entries: dict[str, dict[str, int]] = {k: {} for k in ("specs", "src", "tests", "tools")}
    in_tree = False
    in_docs = False
    section: str | None = None

    for idx, line in enumerate(readme_text.splitlines(), 1):
        stripped = line.strip()
        if not in_tree:
            if stripped == "```text":
                in_tree = True
            continue
        if stripped.startswith("```"):
            break
        m = _TREE_LINE_RE.match(line)
        if not m:
            continue
        indent = len(m.group(1))
        parts = m.group(2).split("#", 1)
        raw_path = parts[0].strip()
        comment = parts[1].strip() if len(parts) > 1 else ""

        if indent == 0:
            top = raw_path.rstrip("/")
            in_docs = top == "docs"
            section = top if top in ("src", "tests", "tools") else None
            if section:
                section_lines[section] = idx
            continue
        if in_docs and indent == 4:
            section = "specs" if raw_path.rstrip("/") == "specs" else None
            if section:
                section_lines[section] = idx
            continue
        if section in ("specs", "src", "tests"):
            expected_indent = 8 if section == "specs" else 4
            if indent == expected_indent:
                for item in _expand_tree_dir_entry(raw_path, comment, section == "tests"):
                    entries[section].setdefault(item, idx)
        elif section == "tools" and indent == 4 and not raw_path.endswith("/"):
            entries["tools"].setdefault(raw_path, idx)

    return section_lines, entries


def _check_readme_tree(
    readme_text: str, repo_root: Path, path: str
) -> list[Finding]:
    section_lines, tree_entries = _parse_readme_tree(readme_text)
    if not section_lines:
        return []

    actual_map: dict[str, tuple[Path, set[str]]] = {
        "specs": (
            repo_root / "docs" / "specs",
            _iter_domain_subsystems(repo_root / "docs" / "specs"),
        ),
        "src": (repo_root / "src", _iter_domain_subsystems(repo_root / "src")),
        "tests": (
            repo_root / "tests",
            _iter_domain_subsystems(repo_root / "tests", include_flat=True),
        ),
        "tools": (
            repo_root / "tools",
            {
                p.name
                for p in (repo_root / "tools").iterdir()
                if p.is_file() and not p.name.startswith(".") and not p.name.endswith(".pyc")
            }
            if (repo_root / "tools").is_dir()
            else set(),
        ),
    }

    findings: list[Finding] = []
    for sec, (sec_dir, actual) in actual_map.items():
        if sec not in section_lines or not sec_dir.is_dir():
            continue
        documented = tree_entries[sec]
        for missing in sorted(actual - set(documented)):
            findings.append(
                Finding(
                    "R9",
                    path,
                    section_lines[sec],
                    f"missing {sec}/ entry '{missing}' in README tree",
                )
            )
        for stale in sorted(set(documented) - actual):
            findings.append(
                Finding(
                    "R9",
                    path,
                    documented[stale],
                    f"stale {sec}/ entry '{stale}' not found on disk",
                )
            )
    return findings


def _check_readme_spec_and_e2e_counts(
    readme_text: str, repo_root: Path, path: str
) -> list[Finding]:
    findings: list[Finding] = []
    e2e_dir = repo_root / "tests" / "e2e"
    e2e_files = sorted(e2e_dir.glob("test_e2e_*.lua")) if e2e_dir.is_dir() else []
    actual_suites = len(e2e_files)
    actual_cases = sum(
        len(_E2E_IT_RE.findall(p.read_text(encoding="utf-8-sig"))) for p in e2e_files
    )

    verify_specs_path = repo_root / "tools" / "verify_all_specs.py"
    actual_verified_specs: int | None = None
    if verify_specs_path.is_file():
        m_block = _SPEC_FILES_BLOCK_RE.search(verify_specs_path.read_text(encoding="utf-8-sig"))
        if m_block:
            actual_verified_specs = len(re.findall(r"['\"][^'\"]+\.md['\"]", m_block.group(1)))

    actual_impl, actual_appr = _spec_status_counts(repo_root)
    actual_total_specs = actual_impl + actual_appr

    for idx, line in enumerate(readme_text.splitlines(), 1):
        if e2e_files:
            em = _README_E2E_RE.search(line)
            if em and (int(em.group(1)) != actual_suites or int(em.group(2)) != actual_cases):
                findings.append(
                    Finding(
                        "R9",
                        path,
                        idx,
                        f"E2E count mismatch: listed {em.group(1)} suites ({em.group(2)} cases), actual {actual_suites} suites ({actual_cases} cases)",
                    )
                )
        if actual_verified_specs is not None:
            for pat in (_README_VERIFY_SPECS_RE, _README_VERIFY_SPECS_INLINE_RE):
                vm = pat.search(line)
                if vm and int(vm.group(1)) != actual_verified_specs:
                    findings.append(
                        Finding(
                            "R9",
                            path,
                            idx,
                            f"verify_all_specs count mismatch: listed {vm.group(1)}대, actual {actual_verified_specs}대",
                        )
                    )
        if actual_total_specs > 0:
            tm = _README_SPEC_TOTAL_RE.search(line)
            if tm and int(tm.group(1)) != actual_total_specs:
                findings.append(
                    Finding(
                        "R9",
                        path,
                        idx,
                        f"active spec total mismatch: listed {tm.group(1)}종, actual {actual_total_specs}종",
                    )
                )
            dm = _GEMINI_DIST_RE.search(line)
            if dm and (int(dm.group(1)) != actual_impl or int(dm.group(2)) != actual_appr):
                findings.append(
                    Finding(
                        "R9",
                        path,
                        idx,
                        f"spec distribution mismatch: listed ({dm.group(1)} Implemented, {dm.group(2)} Approved), actual ({actual_impl} Implemented, {actual_appr} Approved)",
                    )
                )
    return findings


def check_readme_sync(
    readme_text: str, repo_root: Path, path: str = "README.md"
) -> list[Finding]:
    """Verify README.md directory tree and E2E/spec counts match the filesystem (R9)."""
    return _check_readme_tree(readme_text, repo_root, path) + _check_readme_spec_and_e2e_counts(
        readme_text, repo_root, path
    )


def run_all(repo_root: Path) -> list[Finding]:
    findings: list[Finding] = []

    readme_path = repo_root / "README.md"
    if readme_path.is_file():
        readme_text = readme_path.read_text(encoding="utf-8-sig")
        findings.extend(check_readme_counts(readme_text, "README.md"))
        findings.extend(check_overclaim(readme_text, "README.md"))
        findings.extend(check_readme_sync(readme_text, repo_root, "README.md"))

    gemini_path = repo_root / "GEMINI.md"
    if gemini_path.is_file():
        gemini_text = gemini_path.read_text(encoding="utf-8-sig")
        findings.extend(check_overclaim(gemini_text, "GEMINI.md"))
        findings.extend(check_gemini_structure(gemini_text, "GEMINI.md"))
        findings.extend(check_gemini_spec_distribution(gemini_text, repo_root))

    memory_texts: dict[str, str] = {}
    memory_dir = repo_root / ".agent" / "memory"
    if memory_dir.is_dir():
        for mem_path in sorted(memory_dir.glob("*.md")):
            rel = mem_path.relative_to(repo_root).as_posix()
            text = mem_path.read_text(encoding="utf-8-sig")
            memory_texts[rel] = text
            findings.extend(check_overclaim(text, rel))

    task_path = repo_root / "TASK.md"
    if task_path.is_file():
        task_text = task_path.read_text(encoding="utf-8-sig")
        findings.extend(check_overclaim(task_text, "TASK.md"))
        findings.extend(check_task_spec_versions(task_text, repo_root, "TASK.md"))
        findings.extend(check_task_markers(task_text, "TASK.md"))
        findings.extend(check_task_archive_cap(task_text, "TASK.md"))
        findings.extend(check_memory_coverage(task_text, memory_texts, "TASK.md"))

    return findings


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(description="Verify root context docs consistency.")
    parser.add_argument("--json", action="store_true", help="Emit findings as JSON array.")
    args = parser.parse_args(argv)

    findings = run_all(REPO_ROOT)
    if args.json:
        print(json.dumps([asdict(f) for f in findings], ensure_ascii=False))
        return 1 if findings else 0

    if not findings:
        print("[PASS] context docs: 0 findings")
        return 0

    print(f"[FAIL] context docs: {len(findings)} findings")
    for finding in findings:
        print(finding.format())
    return 1


if __name__ == "__main__":
    sys.exit(main())
