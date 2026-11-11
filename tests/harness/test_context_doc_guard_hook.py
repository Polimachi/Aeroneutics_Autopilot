from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOLS_DIR = REPO_ROOT / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import verify_context_docs as vcd

HOOK_PATH = REPO_ROOT / ".agent" / "hooks" / "context_doc_guard.py"


def _load_hook_module():
    spec = importlib.util.spec_from_file_location("context_doc_guard", HOOK_PATH)
    if spec is None or spec.loader is None:
        raise FileNotFoundError(f"Cannot load hook module from {HOOK_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


hook = _load_hook_module()
FINDING = vcd.Finding("R1", "README.md", 3, "count")


class FakeGit:
    def __init__(self, head: str | None, dirty: bool) -> None:
        self._head = head
        self._dirty = dirty

    def head(self) -> str | None:
        return self._head

    def is_dirty(self) -> bool:
        return self._dirty


def stop_payload(reason: str = "NO_TOOL_CALL", idle: bool = True) -> dict:
    return {"conversationId": "c1", "terminationReason": reason, "fullyIdle": idle}


class TestStopHook(unittest.TestCase):
    def test_allows_non_normal_termination(self) -> None:
        self.assertEqual(
            hook.handle_stop(
                stop_payload("USER_CANCELED"), {}, FakeGit("a", True), lambda: [FINDING]
            )["decision"],
            "allow",
        )

    def test_allows_when_background_busy(self) -> None:
        self.assertEqual(
            hook.handle_stop(
                stop_payload(idle=False), {}, FakeGit("a", True), lambda: [FINDING]
            )["decision"],
            "allow",
        )

    def test_skips_checks_when_repo_unchanged(self) -> None:
        state: dict = {}
        hook.handle_session_start({"conversationId": "c1"}, state, FakeGit("a", False))
        called: list[int] = []
        out = hook.handle_stop(
            stop_payload(),
            state,
            FakeGit("a", False),
            lambda: called.append(1) or [FINDING],
        )
        self.assertEqual((out["decision"], called), ("allow", []))

    def test_continues_on_dirty_tree_with_findings(self) -> None:
        out = hook.handle_stop(stop_payload(), {}, FakeGit("a", True), lambda: [FINDING])
        self.assertEqual(out["decision"], "continue")
        self.assertIn("[R1] README.md:L3", out["reason"])

    def test_stop_checks_when_head_moved_since_session_start(self) -> None:
        state: dict = {}
        hook.handle_session_start({"conversationId": "c1"}, state, FakeGit("a", False))
        self.assertEqual(
            hook.handle_stop(
                stop_payload(), state, FakeGit("b", False), lambda: [FINDING]
            )["decision"],
            "continue",
        )

    def test_clean_pass_records_head_and_skips_next_time(self) -> None:
        state: dict = {}
        hook.handle_session_start({"conversationId": "c1"}, state, FakeGit("a", False))
        hook.handle_stop(stop_payload(), state, FakeGit("b", False), lambda: [])
        called: list[int] = []
        hook.handle_stop(
            stop_payload(), state, FakeGit("b", False), lambda: called.append(1) or []
        )
        self.assertEqual(called, [])

    def test_stop_allows_after_two_continues_for_same_signature(self) -> None:
        state: dict = {}
        g = FakeGit("a", True)
        decisions = [
            hook.handle_stop(stop_payload(), state, g, lambda: [FINDING])["decision"]
            for _ in range(3)
        ]
        self.assertEqual(decisions, ["continue", "continue", "allow"])

    def test_stop_fails_open_when_checks_raise(self) -> None:
        def boom():
            raise RuntimeError("x")

        self.assertEqual(
            hook.handle_stop(stop_payload(), {}, FakeGit("a", True), boom)["decision"],
            "allow",
        )

    def test_main_fails_open_on_bad_stdin(self) -> None:
        r = subprocess.run(
            [sys.executable, str(HOOK_PATH), "stop"],
            input="not json",
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assertEqual((r.returncode, json.loads(r.stdout)), (0, {"decision": "allow"}))

    def test_state_roundtrip_and_corrupt_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "s.json"
            p.write_text("{bad", encoding="utf-8")
            self.assertEqual(hook.load_state(p), {})
            hook.save_state(p, {"c1": {"baseline": "a"}})
            self.assertEqual(hook.load_state(p)["c1"]["baseline"], "a")


if __name__ == "__main__":
    unittest.main()
