#!/usr/bin/env python3
"""Antigravity PreToolUse hook script to block destructive Git commands."""

import json
import re
import sys

_GIT = r"""\b[Gg][Ii][Tt](?:\.[Ee][Xx][Ee])?["']?\s+"""

DANGEROUS_PATTERNS = [
    (_GIT + r"push\b", "git push"),
    (r"\bpush\s+(?:--force|-f)\b", "git push --force"),
    (_GIT + r"reset\s+--hard\b", "git reset --hard"),
    (_GIT + r"clean\s+-[a-zA-Z]*f", "git clean -f/-fd"),
    (_GIT + r"branch\s+-D\b", "git branch -D"),
    (_GIT + r"checkout\s+(?:--\s+)?\.(?:\s|$)", "git checkout ."),
    (_GIT + r"restore\s+(?:--\s+)?\.(?:\s|$)", "git restore ."),
]


def main() -> int:
    raw = sys.stdin.read().strip()
    if not raw:
        print(json.dumps({"decision": "ask"}))
        return 0

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        print(json.dumps({"decision": "ask"}))
        return 0

    tool_call = payload.get("toolCall") or {}
    args = tool_call.get("args") or {}
    cmd = (
        args.get("CommandLine")
        or (payload.get("tool_input") or {}).get("command")
        or ""
    )

    for pattern, label in DANGEROUS_PATTERNS:
        if re.search(pattern, cmd):
            print(
                json.dumps(
                    {
                        "decision": "deny",
                        "reason": f"BLOCKED by git-guardrails: '{cmd}' matches restricted pattern '{label}'. Ask the user explicitly before running destructive git commands.",
                    }
                )
            )
            return 0

    print(json.dumps({"decision": "ask"}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
