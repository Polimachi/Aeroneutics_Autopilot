"""
Tests for tools/run_boot_smoke.py — CraftOS-PC boot smoke runner for active subsystems.
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent.parent
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

from harness.unit.config import CraftOSPaths
from harness.unit.session import CraftOSSessionResult
from tools.run_boot_smoke import (
    SmokeTarget,
    _stage_shared_sensors,
    build_smoke_targets,
    run_boot_smoke_cli,
    run_target_boot_smoke,
)


class TestBootSmokeRunner(unittest.TestCase):
    def test_build_smoke_targets_covers_13_active_subsystems_and_skips_deferred_asa(self) -> None:
        targets = build_smoke_targets(WORKSPACE_ROOT, include_deferred=False)
        self.assertEqual(len(targets), 13, f"Expected 13 active targets, got {len(targets)}")

        target_ids = [t.target_id for t in targets]
        self.assertNotIn("1_control/asa", target_ids)

        expected_ids = [
            "0_development/alignment",
            "0_development/fdr",
            "0_development/installer",
            "0_development/ota",
            "0_infra/gps",
            "0_infra/gac",
            "0_infra/gcs",
            "0_infra/landing_pad",
            "0_infra/runway",
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
            self.assertEqual(target.workspace_root, WORKSPACE_ROOT)

    def test_build_smoke_targets_includes_asa_when_include_deferred(self) -> None:
        targets = build_smoke_targets(WORKSPACE_ROOT, include_deferred=True)
        self.assertEqual(len(targets), 14, f"Expected 14 targets, got {len(targets)}")

        target_map = {t.target_id: t for t in targets}
        self.assertIn("1_control/asa", target_map)
        asa_target = target_map["1_control/asa"]
        self.assertTrue(asa_target.deferred)
        self.assertEqual(asa_target.expected_channels, [10011])
        self.assertEqual(asa_target.workspace_root, WORKSPACE_ROOT)

    def test_stage_shared_sensors_copies_file_and_raises_on_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            comp_dir = temp_path / "c0"
            comp_dir.mkdir()

            # 1. Successful copy from valid workspace root
            _stage_shared_sensors(comp_dir, WORKSPACE_ROOT)
            staged_file = comp_dir / "lib" / "avionics_sensors.lua"
            self.assertTrue(staged_file.is_file())
            self.assertGreater(staged_file.stat().st_size, 0)
            staged_ota = comp_dir / "lib" / "ota_agent.lua"
            self.assertTrue(staged_ota.is_file(), "Expected lib/ota_agent.lua to be staged")
            self.assertGreater(staged_ota.stat().st_size, 0)

            # 2. FileNotFoundError raised if missing
            empty_root = temp_path / "empty_ws"
            empty_root.mkdir()
            with self.assertRaises(FileNotFoundError) as ctx:
                _stage_shared_sensors(comp_dir, empty_root)
            self.assertIn("Required shared sensor library missing", str(ctx.exception))

    @patch("tools.run_boot_smoke.EphemeralCraftOSSession")
    def test_smoke_runner_reports_failure_on_lua_boot_error(self, mock_session_cls: MagicMock) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_comp = Path(temp_dir) / "dummy_comp"
            temp_comp.mkdir()

            mock_session = MagicMock()
            mock_session_cls.return_value.__enter__.return_value = mock_session
            mock_session.computer_dir.return_value = temp_comp

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
                workspace_root=WORKSPACE_ROOT,
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
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_comp = Path(temp_dir) / "dummy_comp"
            temp_comp.mkdir()

            mock_session = MagicMock()
            mock_session_cls.return_value.__enter__.return_value = mock_session
            mock_session.computer_dir.return_value = temp_comp

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
                workspace_root=WORKSPACE_ROOT,
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

    @patch("tools.run_boot_smoke.EphemeralCraftOSSession")
    def test_run_target_boot_smoke_stages_shared_sensors_and_configs(self, mock_session_cls: MagicMock) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            comp_dir = Path(temp_dir) / "comp0"
            comp_dir.mkdir()

            mock_session = MagicMock()
            mock_session_cls.return_value.__enter__.return_value = mock_session
            mock_session.computer_dir.return_value = comp_dir

            mock_session.run.return_value = CraftOSSessionResult(
                session_id="dummy_stage_test",
                exit_code=0,
                timed_out=False,
                duration_ms=50.0,
                stdout_raw="ok",
                stderr_raw="",
                guest_result={
                    "status": "PASS",
                    "error": None,
                    "opened_channels": [10001],
                },
            )

            target = SmokeTarget(
                target_id="1_control/vas",
                source_dir=WORKSPACE_ROOT / "src" / "1_control" / "vas",
                expected_channels=[10001],
                cli_args=[],
                deferred=False,
                workspace_root=None,
            )
            fake_paths = CraftOSPaths(
                craftos_exe=Path("fake_exe"),
                rom_dir=Path("fake_rom"),
                lua52_dll=None,
            )

            report = run_target_boot_smoke(
                target=target,
                craftos_paths=fake_paths,
                sessions_root=WORKSPACE_ROOT / ".runtime" / "test_sessions",
                timeout_sec=5.0,
                tick_window=0.1,
            )
            self.assertEqual(report["status"], "PASS")

            # Verify lib/avionics_sensors.lua staged
            staged_sensor = comp_dir / "lib" / "avionics_sensors.lua"
            self.assertTrue(staged_sensor.is_file(), "Expected lib/avionics_sensors.lua to be staged")
            self.assertGreater(staged_sensor.stat().st_size, 0)
            staged_ota = comp_dir / "lib" / "ota_agent.lua"
            self.assertTrue(staged_ota.is_file(), "Expected lib/ota_agent.lua to be staged")
            self.assertGreater(staged_ota.stat().st_size, 0)

            # Verify valid JSON configs staged
            expected_json_files = [
                comp_dir / "config.json",
                comp_dir / "config" / "gcs_config.json",
                comp_dir / "config" / "fcp_config.json",
                comp_dir / "config" / "amm_config.json",
                comp_dir / "config" / "sensors.json",
                comp_dir / "config" / "system.json",
                comp_dir / "config" / "ota_config.json",
            ]
            for cfg_path in expected_json_files:
                self.assertTrue(cfg_path.is_file(), f"Expected config file missing: {cfg_path}")
                content = cfg_path.read_text(encoding="utf-8")
                parsed = json.loads(content)
                self.assertIsInstance(parsed, dict, f"Expected JSON object in {cfg_path}")

    @patch("tools.run_boot_smoke.EphemeralCraftOSSession")
    def test_run_target_boot_smoke_stages_root_installer_for_installer_target(
        self, mock_session_cls: MagicMock
    ) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            comp_dir = Path(temp_dir) / "comp0"
            comp_dir.mkdir()

            mock_session = MagicMock()
            mock_session_cls.return_value.__enter__.return_value = mock_session
            mock_session.computer_dir.return_value = comp_dir
            mock_session.run.return_value = CraftOSSessionResult(
                session_id="dummy_installer_stage",
                exit_code=0,
                timed_out=False,
                duration_ms=25.0,
                stdout_raw="ok",
                stderr_raw="",
                guest_result={"status": "PASS", "error": None, "opened_channels": []},
            )

            target = SmokeTarget(
                target_id="0_development/installer",
                source_dir=WORKSPACE_ROOT / "src" / "0_development" / "installer",
                expected_channels=[],
                cli_args=[],
                deferred=False,
                workspace_root=WORKSPACE_ROOT,
            )
            fake_paths = CraftOSPaths(
                craftos_exe=Path("fake_exe"),
                rom_dir=Path("fake_rom"),
                lua52_dll=None,
            )
            report = run_target_boot_smoke(
                target=target,
                craftos_paths=fake_paths,
                sessions_root=WORKSPACE_ROOT / ".runtime" / "test_sessions",
                timeout_sec=5.0,
                tick_window=0.1,
            )
            self.assertEqual(report["status"], "PASS")
            staged_installer = comp_dir / "installer.lua"
            self.assertTrue(staged_installer.is_file(), "Expected root installer.lua to be staged")
            self.assertEqual(
                staged_installer.read_bytes(),
                (WORKSPACE_ROOT / "installer.lua").read_bytes(),
            )


if __name__ == "__main__":
    unittest.main()
