from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK_PATH = REPO_ROOT / ".agent" / "hooks" / "block_dangerous_git.py"


def _run_guard(cmd: str) -> dict:
    payload = json.dumps({"toolCall": {"name": "run_command", "args": {"CommandLine": cmd}}})
    proc = subprocess.run(
        [sys.executable, str(HOOK_PATH)],
        input=payload,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    )
    return json.loads(proc.stdout)


class TestGitGuardrailsHook(unittest.TestCase):
    def test_blocks_bare_dangerous_commands(self) -> None:
        cmds = [
            "git push",
            "git push --dry-run",
            "git push --force",
            "git reset --hard",
            "git clean -fd",
            "git branch -D feat",
            "git checkout .",
            "git checkout -- .",
            "git restore .",
            "git restore -- .",
        ]
        for cmd in cmds:
            with self.subTest(cmd=cmd):
                out = _run_guard(cmd)
                self.assertEqual(out["decision"], "deny")
                self.assertIn("BLOCKED by git-guardrails", out["reason"])

    def test_blocks_windows_git_exe_dangerous_commands(self) -> None:
        cmds = [
            '& "C:\\Program Files\\Git\\cmd\\git.exe" push --dry-run',
            '& "C:\\Program Files\\Git\\cmd\\git.exe" reset --hard',
            "& 'C:\\Program Files\\Git\\cmd\\git.exe' clean -fd",
            r"C:\Program Files\Git\cmd\git.exe branch -D feat",
            '& "C:\\Program Files\\Git\\cmd\\git.exe" checkout -- .',
            '& "C:\\Program Files\\Git\\cmd\\git.exe" restore .',
            '& "C:\\Program Files\\Git\\cmd\\GIT.EXE" push',
        ]
        for cmd in cmds:
            with self.subTest(cmd=cmd):
                out = _run_guard(cmd)
                self.assertEqual(out["decision"], "deny")
                self.assertIn("BLOCKED by git-guardrails", out["reason"])

    def test_allows_safe_git_and_non_git_commands(self) -> None:
        cmds = [
            '& "C:\\Program Files\\Git\\cmd\\git.exe" status -sb',
            '& "C:\\Program Files\\Git\\cmd\\git.exe" branch -d merged-branch',
            '& "C:\\Program Files\\Git\\cmd\\git.exe" checkout main',
            '& "C:\\Program Files\\Git\\cmd\\git.exe" restore README.md',
            "python tools/verify_context_docs.py",
        ]
        for cmd in cmds:
            with self.subTest(cmd=cmd):
                out = _run_guard(cmd)
                self.assertEqual(out["decision"], "ask")

    def test_handles_empty_or_invalid_stdin(self) -> None:
        for raw in ["", "{bad json"]:
            with self.subTest(raw=raw):
                proc = subprocess.run(
                    [sys.executable, str(HOOK_PATH)],
                    input=raw,
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    check=True,
                )
                self.assertEqual(json.loads(proc.stdout), {"decision": "ask"})


if __name__ == "__main__":
    unittest.main()
