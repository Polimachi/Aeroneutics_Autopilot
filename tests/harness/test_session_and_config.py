import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from harness.unit.config import discover_codebase_targets, resolve_craftos_paths
from harness.unit.session import EphemeralCraftOSSession, clean_workspace_orphans


class TestSessionAndConfig(unittest.TestCase):
    def test_discover_targets_and_short_name_query(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "src" / "1_control" / "tca").mkdir(parents=True)
            (root / "src" / "1_control" / "tca" / "main.lua").write_text("return true\n", encoding="utf-8")
            (root / "src" / "1_control" / "asa").mkdir(parents=True)
            (root / "src" / "1_control" / "asa" / "README.md").write_text("# ASA\n", encoding="utf-8")

            targets = discover_codebase_targets(root)
            self.assertEqual([t.target_id for t in targets], ["1_control/tca"])
            self.assertEqual(targets[0].peripherals[0].peripheral_type, "modem")

            by_short = discover_codebase_targets(root, target_query="tca")
            self.assertEqual(len(by_short), 1)
            self.assertEqual(by_short[0].target_id, "1_control/tca")

            with self.assertRaises(ValueError):
                discover_codebase_targets(root, target_query="nonexistent")

    def test_resolve_craftos_paths_rejects_invalid_override(self) -> None:
        with self.assertRaises(FileNotFoundError):
            resolve_craftos_paths({"CRAFTOS_PC_EXE": r"C:\missing\CraftOS-PC_console.exe"})

    def test_clean_orphans_ignores_external_craftos_processes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sessions_root = Path(tmp) / ".runtime" / "sessions"
            sessions_root.mkdir(parents=True)
            fake_procs = [
                {"ProcessId": 1111, "CommandLine": r'"C:\Program Files\CraftOS-PC\CraftOS-PC_console.exe"'},
                {"ProcessId": 2222, "CommandLine": f'CraftOS-PC_console.exe --headless -d "{sessions_root}\\unit_1"'},
            ]
            killed: list[int] = []
            with patch("harness.unit.session._kill_pid_tree", side_effect=lambda pid: killed.append(pid)):
                res = clean_workspace_orphans(sessions_root, process_enumerator=lambda: fake_procs)
            self.assertEqual(killed, [2222])
            self.assertEqual(res["killed_pids"], [2222])

    def test_ephemeral_session_executes_and_cleans_up(self) -> None:
        paths = resolve_craftos_paths()
        with tempfile.TemporaryDirectory() as tmp:
            sessions_root = Path(tmp) / "sessions"
            with EphemeralCraftOSSession(sessions_root, paths, prefix="smoke") as sess:
                c0 = sess.computer_dir(0)
                sdir = sess.session_dir
                (c0 / "startup.lua").write_text(
                    'fs.makeDir("/_harness_out")\n'
                    'local f = fs.open("/_harness_out/result.json", "w")\n'
                    'f.write(textutils.serializeJSON({ ok = true, sum = 2 + 3 }))\n'
                    'f.close()\n'
                    'local d = fs.open("/_harness_out/done.flag", "w")\n'
                    'd.write("OK")\n'
                    'd.close()\n'
                    'os.shutdown()\n',
                    encoding="utf-8",
                )
                result = sess.run(mode="headless", timeout_sec=5.0)
                self.assertTrue(sdir.exists())
            self.assertFalse(sdir.exists())
            self.assertFalse(result.timed_out)
            self.assertEqual(result.guest_result, {"ok": True, "sum": 5})


if __name__ == "__main__":
    unittest.main()
