#!/usr/bin/env python3
"""Antigravity SessionStart/Stop hook guarding against context document drift."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Callable, Protocol

REPO_ROOT = Path(__file__).resolve().parents[2]
STATE_PATH = REPO_ROOT / ".runtime" / "context_doc_guard_state.json"
MAX_CONTINUES = 2
MAX_LISTED = 10
_FALLBACK_GIT = Path(r"C:\Program Files\Git\cmd\git.exe")


class GitProbe(Protocol):
    def head(self) -> str | None: ...
    def is_dirty(self) -> bool: ...


class SubprocessGit:
    def __init__(self, repo_root: Path) -> None:
        self._repo_root = repo_root
        git_cmd = shutil.which("git")
        if not git_cmd and _FALLBACK_GIT.is_file():
            git_cmd = str(_FALLBACK_GIT)
        self._git_cmd = git_cmd

    def _run(self, *args: str) -> str | None:
        if not self._git_cmd:
            return None
        try:
            proc = subprocess.run(
                [self._git_cmd, *args],
                cwd=str(self._repo_root),
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=5,
            )
            if proc.returncode != 0:
                return None
            return proc.stdout
        except Exception:
            return None

    def head(self) -> str | None:
        out = self._run("rev-parse", "HEAD")
        if out is None:
            return None
        stripped = out.strip()
        return stripped or None

    def is_dirty(self) -> bool:
        out = self._run("status", "--porcelain")
        return bool(out and out.strip())


def load_state(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def handle_session_start(payload: dict, state: dict, git: GitProbe) -> dict:
    conv_id = str(payload.get("conversationId") or "default")
    state[conv_id] = {
        "baseline": git.head(),
        "lastCleanHead": None,
        "continues": {},
    }
    return {}


def handle_stop(
    payload: dict,
    state: dict,
    git: GitProbe,
    run_checks: Callable[[], list],
) -> dict:
    if payload.get("terminationReason") != "NO_TOOL_CALL" or payload.get("fullyIdle") is False:
        return {"decision": "allow"}

    conv_id = str(payload.get("conversationId") or "default")
    entry = state.get(conv_id)
    if not isinstance(entry, dict):
        entry = {"baseline": None, "lastCleanHead": None, "continues": {}}
        state[conv_id] = entry
    continues = entry.get("continues")
    if not isinstance(continues, dict):
        continues = {}
        entry["continues"] = continues

    dirty = git.is_dirty()
    head = git.head()
    baseline = entry.get("baseline")
    last_clean = entry.get("lastCleanHead")
    head_moved = (
        baseline is not None
        and head is not None
        and head != baseline
        and head != last_clean
    )
    if not (dirty or head_moved):
        return {"decision": "allow"}

    try:
        findings = run_checks()
    except Exception:
        return {"decision": "allow"}

    if not findings:
        if not dirty and head is not None:
            entry["lastCleanHead"] = head
        return {"decision": "allow"}

    formatted = [f.format() for f in findings]
    sig = hashlib.sha1("\n".join(sorted(formatted)).encode("utf-8")).hexdigest()
    count = int(continues.get(sig, 0))
    if count >= MAX_CONTINUES:
        return {"decision": "allow"}

    continues[sig] = count + 1
    listed = formatted[:MAX_LISTED]
    extra = len(formatted) - len(listed)
    if extra > 0:
        listed.append(f"... 외 {extra}건")

    lines_block = "\n".join(listed)
    reason = (
        f"[context-doc-guard] 컨텍스트 문서 정합성 위반 {len(formatted)}건.\n"
        "- 이번 작업에서 생긴 위반이면 지금 수정하고 `python tools/verify_context_docs.py` 결과 0 findings를 확인한 뒤 종료하세요.\n"
        "- 이번 작업과 무관한 기존 위반이거나 현재 단계(계획·브레인스토밍·Q&A)에서 수정할 수 없으면, 사용자에게 한 줄로 보고하고 종료하세요.\n"
        f"{lines_block}"
    )
    return {"decision": "continue", "reason": reason}


def _default_run_checks() -> list:
    tools_dir = str(REPO_ROOT / "tools")
    if tools_dir not in sys.path:
        sys.path.insert(0, tools_dir)
    import verify_context_docs

    return verify_context_docs.run_all(REPO_ROOT)


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    args = sys.argv[1:] if argv is None else argv
    mode = args[0] if args else "stop"
    fallback = {} if mode == "session-start" else {"decision": "allow"}

    try:
        payload = json.loads(sys.stdin.read())
        if not isinstance(payload, dict):
            print(json.dumps(fallback, ensure_ascii=False))
            return 0

        state = load_state(STATE_PATH)
        git = SubprocessGit(REPO_ROOT)
        if mode == "session-start":
            result = handle_session_start(payload, state, git)
        elif mode == "stop":
            result = handle_stop(payload, state, git, _default_run_checks)
        else:
            result = fallback
        save_state(STATE_PATH, state)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except Exception:
        print(json.dumps(fallback, ensure_ascii=False))
        return 0


if __name__ == "__main__":
    sys.exit(main())
