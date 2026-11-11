"""Static checker for Create_Aeroneutics root context documentation drift."""
from __future__ import annotations

from dataclasses import dataclass
import re

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
