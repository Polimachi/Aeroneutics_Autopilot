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


def check_gemini_spec_distribution(gemini_text: str, repo_root: Path) -> list[Finding]:
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


def run_all(repo_root: Path) -> list[Finding]:
    findings: list[Finding] = []

    readme_path = repo_root / "README.md"
    if readme_path.is_file():
        readme_text = readme_path.read_text(encoding="utf-8-sig")
        findings.extend(check_readme_counts(readme_text, "README.md"))
        findings.extend(check_overclaim(readme_text, "README.md"))

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
