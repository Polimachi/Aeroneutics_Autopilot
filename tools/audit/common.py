"""Shared parsing, Lua function extraction, and git churn helpers for tools.audit."""
from __future__ import annotations

import re
import subprocess
from pathlib import Path
from typing import Any

from harness.unit.static_guard import strip_lua_comments_and_strings

SINGLE_READ_BYTE_LIMIT = 46080

LUA_THRESHOLDS = {"bytes": 20000, "lines": 450}
SUBSYSTEM_BYTE_THRESHOLD = 90000
SPEC_BYTE_THRESHOLD = 80000
WEBUI_BYTE_THRESHOLD = 100000

_STATUS_PAT = re.compile(r"\|\s*\*\*문서 상태 \(Status\)\*\*\s*\|\s*`([^`]+)`\s*\|")
_VERSION_PAT = re.compile(r"\|\s*\*\*문서 버전 \(Version\)\*\*\s*\|\s*`([^`]+)`\s*\|")
_DATE_PAT = re.compile(r"\|\s*\*\*최종 수정일 \(Date\)\*\*\s*\|\s*`([^`]+)`\s*\|")
_HEADING_PAT = re.compile(r"^##\s+(.+)$", re.MULTILINE)

_FN_START_PAT = re.compile(
    r"^\s*(?:(local)\s+)?function\s+([a-zA-Z_][a-zA-Z0-9_.:]*)\s*\("
)
_FN_ASSIGN_PAT = re.compile(
    r"^\s*(?:(local)\s+)?([a-zA-Z_][a-zA-Z0-9_.]*)\s*=\s*function\s*\("
)
_WORD_PAT = re.compile(r"\b[a-zA-Z_][a-zA-Z0-9_]*\b")


def iter_lua_files(root: Path) -> list[Path]:
    """Return sorted list of Lua files in src/ and root installer.lua."""
    files: list[Path] = []
    src_dir = root / "src"
    if src_dir.is_dir():
        files.extend(sorted(src_dir.rglob("*.lua")))
    inst = root / "installer.lua"
    if inst.is_file():
        files.append(inst)
    return files


def iter_spec_files(root: Path) -> list[Path]:
    """Return sorted active/approved specification markdown files (excluding README.md)."""
    specs: list[Path] = []
    for base in (root / "docs" / "system", root / "docs" / "specs"):
        if base.is_dir():
            for p in sorted(base.rglob("*.md")):
                if p.name.lower() != "readme.md":
                    specs.append(p)
    return specs


def subsystem_for_path(root: Path, path: Path) -> str:
    """Return '<layer>/<subsystem>' for src files, or 'root' for root files."""
    rel = path.resolve().relative_to(root.resolve()).as_posix()
    parts = rel.split("/")
    if len(parts) >= 3 and parts[0] == "src":
        return f"{parts[1]}/{parts[2]}"
    return "root"


def parse_spec_metadata(md_path: Path, root: Path) -> dict[str, Any]:
    """Extract status, version, date, headings, and size from a spec markdown file."""
    text = md_path.read_text(encoding="utf-8", errors="replace")
    rel = md_path.resolve().relative_to(root.resolve()).as_posix()
    status_m = _STATUS_PAT.search(text)
    ver_m = _VERSION_PAT.search(text)
    date_m = _DATE_PAT.search(text)
    headings = [m.group(1).strip() for m in _HEADING_PAT.finditer(text)]
    return {
        "id": rel,
        "bytes": md_path.stat().st_size,
        "lines": text.count("\n") + (1 if text and not text.endswith("\n") else 0),
        "status": status_m.group(1).strip() if status_m else "UNKNOWN",
        "version": ver_m.group(1).strip() if ver_m else "UNKNOWN",
        "date": date_m.group(1).strip() if date_m else "UNKNOWN",
        "section_count": len(headings),
        "headings": headings,
    }


def extract_lua_functions(source: str, file_path: str = "") -> list[dict[str, Any]]:
    """
    Extract Lua function spans using comment/string-stripped lines for block depth tracking.
    """
    raw_lines = source.splitlines()
    stripped, _ = strip_lua_comments_and_strings(source)
    stripped_lines = stripped.splitlines()
    while len(stripped_lines) < len(raw_lines):
        stripped_lines.append("")

    functions: list[dict[str, Any]] = []
    stack: list[dict[str, Any]] = []
    block_depth = 0

    for idx, sline in enumerate(stripped_lines, start=1):
        m_start = _FN_START_PAT.match(sline)
        m_assign = _FN_ASSIGN_PAT.match(sline) if not m_start else None

        tokens = _WORD_PAT.findall(sline)
        opens = 0
        closes = 0
        for tok in tokens:
            if tok in ("function", "if", "do", "repeat"):
                opens += 1
            elif tok in ("end", "until"):
                closes += 1

        if m_start or m_assign:
            m = m_start or m_assign
            is_local = bool(m.group(1))
            name = m.group(2)
            # Only push function frame if 'end' does not close it on the same line
            fn_entry = {
                "file": file_path,
                "name": name,
                "is_local": is_local,
                "start_line": idx,
                "entry_depth": block_depth,
            }
            stack.append(fn_entry)

        block_depth += opens - closes
        if block_depth < 0:
            block_depth = 0

        while stack and block_depth <= stack[-1]["entry_depth"]:
            fn_entry = stack.pop()
            start_line = fn_entry["start_line"]
            end_line = idx
            body_raw = "\n".join(raw_lines[start_line - 1 : end_line])
            body_stripped = "\n".join(stripped_lines[start_line - 1 : end_line])
            non_empty = sum(1 for ln in stripped_lines[start_line - 1 : end_line] if ln.strip())
            functions.append({
                "file": file_path,
                "name": fn_entry["name"],
                "is_local": fn_entry["is_local"],
                "start_line": start_line,
                "end_line": end_line,
                "lines": end_line - start_line + 1,
                "code_lines": non_empty,
                "body": body_raw,
                "stripped_body": body_stripped,
            })

    return functions


def run_git_name_only_log(root: Path, limit: int = 100) -> list[list[str]]:
    """Return list of changed-file lists per recent commit (empty list if git unavailable)."""
    git_exe = "git"
    win_git = Path(r"C:\Program Files\Git\cmd\git.exe")
    if win_git.is_file():
        git_exe = str(win_git)
    try:
        proc = subprocess.run(
            [git_exe, "log", f"-n{limit}", "--name-only", "--pretty=format:---COMMIT---"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=str(root),
            timeout=15,
            check=False,
        )
        if proc.returncode != 0:
            return []
    except Exception:
        return []

    commits: list[list[str]] = []
    cur: list[str] | None = None
    for line in proc.stdout.splitlines():
        s = line.strip()
        if s == "---COMMIT---":
            if cur is not None:
                commits.append(cur)
            cur = []
        elif s and cur is not None:
            cur.append(s.replace("\\", "/"))
    if cur is not None:
        commits.append(cur)
    return commits
