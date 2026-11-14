"""
Tests for tools/run_boot_smoke.py — CraftOS-PC boot smoke runner for active subsystems.
"""
from __future__ import annotations

import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from harness.unit.config import CraftOSPaths
from harness.unit.session import CraftOSSessionResult
from tools.run_boot_smoke import (
    SmokeTarget,
    build_smoke_targets,
    run_boot_smoke_cli,
    run_target_boot_smoke,
)

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent.parent


class TestBootSmokeRunner(unittest.TestCase):
    def test_build_smoke_targets_covers_10_active_subsystems_and_skips_deferred_asa(self) -> None:
        targets = build_smoke_targets(WORKSPACE_ROOT, include_deferred=False)
        self.assertEqual(len(targets), 10, f"Expected 10 active targets, got {len(targets)}")

        target_ids = [t.target_id for t in targets]
        self.assertNotIn("1_control/asa", target_ids)

        expected_ids = [
            "0_development/alignment",
            "0_development/installer",
            "0_infra/gps",
            "0_infra/gac",
            "0_infra/gcs",
            "0_infra/landing_pad",
            "1_control/tca",
            "1_control/vas",
            "2_guidance/fcp",
            "3_planning/amm",
        ]
        for exp_id in expected_ids:
            self.assertIn(exp_id, target_ids)

        for target in targets:
            self.assertTrue(target.source_dir.is_dir(), f"Source dir missing: {target.source_dir}")
            self.assertTrue(
                (target.source_dir / "main.lua").is_file(),
                f"main.lua missing in {target.source_dir}",
            )
            self.assertFalse(target.deferred)

    def test_build_smoke_targets_includes_asa_when_include_deferred(self) -> None:
        targets = build_smoke_targets(WORKSPACE_ROOT, include_deferred=True)
        self.assertEqual(len(targets), 11, f"Expected 11 targets, got {len(targets)}")

        target_map = {t.target_id: t for t in targets}
        self.assertIn("1_control/asa", target_map)
        asa_target = target_map["1_control/asa"]
        self.assertTrue(asa_target.deferred)
        self.assertEqual(asa_target.expected_channels, [10011])

    @patch("tools.run_boot_smoke.EphemeralCraftOSSession")
    def test_smoke_runner_reports_failure_on_lua_boot_error(self, mock_session_cls: MagicMock) -> None:
        mock_session = MagicMock()
        mock_session_cls.return_value.__enter__.return_value = mock_session
        mock_session.computer_dir.return_value = WORKSPACE_ROOT / ".runtime" / "dummy_comp"

        mock_session.run.return_value = CraftOSSessionResult(
            session_id="dummy_session",
            exit_code=0,
            timed_out=False,
            duration_ms=120.0,
            stdout_raw="error",
            stderr_raw="",
            guest_result={
                "status": "FAIL",
                "error": "attempt to call a nil value (global 'missing_fn')",
                "opened_channels": [],
            },
        )

        dummy_target = SmokeTarget(
            target_id="test/dummy",
            source_dir=WORKSPACE_ROOT / "src" / "0_development" / "installer",
            expected_channels=[],
            cli_args=[],
            deferred=False,
        )
        fake_paths = CraftOSPaths(
            craftos_exe=Path("fake_exe"),
            rom_dir=Path("fake_rom"),
            lua52_dll=None,
        )

        report = run_target_boot_smoke(
            target=dummy_target,
            craftos_paths=fake_paths,
            sessions_root=WORKSPACE_ROOT / ".runtime" / "test_sessions",
            timeout_sec=5.0,
            tick_window=0.1,
        )

        self.assertEqual(report["status"], "FAIL")
        self.assertIn("missing_fn", report["error"])

    @patch("tools.run_boot_smoke.EphemeralCraftOSSession")
    def test_smoke_runner_reports_failure_on_missing_expected_channel(self, mock_session_cls: MagicMock) -> None:
        mock_session = MagicMock()
        mock_session_cls.return_value.__enter__.return_value = mock_session
        mock_session.computer_dir.return_value = WORKSPACE_ROOT / ".runtime" / "dummy_comp"

        mock_session.run.return_value = CraftOSSessionResult(
            session_id="dummy_session",
            exit_code=0,
            timed_out=False,
            duration_ms=150.0,
            stdout_raw="ok",
            stderr_raw="",
            guest_result={
                "status": "PASS",
                "error": None,
                "opened_channels": [10001, 10002],
            },
        )

        dummy_target = SmokeTarget(
            target_id="test/dummy",
            source_dir=WORKSPACE_ROOT / "src" / "2_guidance" / "fcp",
            expected_channels=[10001, 10002, 10004],
            cli_args=[],
            deferred=False,
        )
        fake_paths = CraftOSPaths(
            craftos_exe=Path("fake_exe"),
            rom_dir=Path("fake_rom"),
            lua52_dll=None,
        )

        report = run_target_boot_smoke(
            target=dummy_target,
            craftos_paths=fake_paths,
            sessions_root=WORKSPACE_ROOT / ".runtime" / "test_sessions",
            timeout_sec=5.0,
            tick_window=0.1,
        )

        self.assertEqual(report["status"], "FAIL")
        self.assertTrue(report["missing_channels"])
        self.assertIn(10004, report["missing_channels"])


if __name__ == "__main__":
    unittest.main()
