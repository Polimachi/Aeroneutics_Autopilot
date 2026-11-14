import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent.parent
TOOLS_DIR = WORKSPACE_ROOT / "tools"
SCRIPT_PATH = TOOLS_DIR / "analyze_flight_log.py"


def _euler_to_quat(pitch_deg: float, roll_deg: float, yaw_deg: float) -> dict:
    p = math.radians(pitch_deg) * 0.5
    r = math.radians(roll_deg) * 0.5
    y = math.radians(yaw_deg) * 0.5
    cp, sp = math.cos(p), math.sin(p)
    cr, sr = math.cos(r), math.sin(r)
    cy, sy = math.cos(y), math.sin(y)
    return {
        "w": cr * cp * cy + sr * sp * sy,
        "x": sr * cp * cy - cr * sp * sy,
        "y": cr * sp * cy + sr * cp * sy,
        "z": cr * cp * sy - sr * sp * cy,
    }


def _make_sample_records(
    count: int = 120,
    pitch_err_deg: float = 1.5,
    sat_ratio: float = 0.0,
    sensor_fault_ratio: float = 0.0,
    rate_command_only: bool = False,
    advanced_vtol: bool = False,
    oscillate: bool = False,
) -> list:
    records = [
        {
            "recordType": "META",
            "schemaVersion": "1.1.0",
            "sessionId": "CRAFT_01_1000",
            "partIndex": 1,
            "domainId": "CRAFT_01",
            "baseChannel": 10000,
            "startedAtMs": 1000,
        }
    ]
    seq = 1
    for i in range(count):
        rx = 1000 + i * 50
        cmd_type = "RATE_COMMAND" if rate_command_only else "QUATERNION_RATE"
        sign = 1.0 if (not oscillate or (i % 4) < 2) else -1.0
        target_pitch = 5.0
        meas_pitch = target_pitch - sign * pitch_err_deg

        records.append(
            {
                "recordType": "FRAME",
                "seqIdx": seq,
                "rxMs": rx,
                "txMs": rx - 5,
                "channel": 10001,
                "offset": 1,
                "msgType": "MSG_ATTITUDE_CMD",
                "payload": {
                    "commandType": cmd_type,
                    "targetQuaternion": _euler_to_quat(target_pitch, 0.0, 90.0),
                    "targetRates": {"p": 0.0, "q": 0.2, "r": 0.0},
                    "collectiveThrust": 0.6,
                },
            }
        )
        seq += 1

        is_sat = i < int(count * sat_ratio)
        is_fault = i < int(count * sensor_fault_ratio)
        records.append(
            {
                "recordType": "FRAME",
                "seqIdx": seq,
                "rxMs": rx + 10,
                "txMs": rx + 5,
                "channel": 10002,
                "offset": 2,
                "msgType": "MSG_FLIGHT_TELEMETRY",
                "payload": {
                    "attitude": _euler_to_quat(meas_pitch, 0.0, 90.0),
                    "angularRates": {"p": 0.0, "q": 0.05, "r": 0.0},
                    "dynamics": {
                        "altitudeY": 100.0 + i * 0.05,
                        "verticalSpeed": 0.2,
                        "velocity": {"vx": 1.0, "vy": 0.2, "vz": 0.0},
                    },
                    "controlState": "NORMAL",
                    "activeSource": "FCP",
                    "sensorOk": not is_fault,
                    "satFlags": {
                        "axisSaturatedPos": {"pitch": is_sat},
                        "axisSaturatedNeg": {},
                    },
                    "diag": {
                        "saturationFreeze": is_sat,
                        "integrators": {"pitch": 3.5 if is_sat else 0.5, "roll": 0.1, "yaw": 0.0, "climb": 0.2},
                        "integralLimits": {"pitch": 4.0, "roll": 4.0, "yaw": 2.5, "climb": 3.0},
                        "lastDemands": {"pitch": 1.0, "roll": 0.0, "yaw": 0.0},
                    },
                },
            }
        )
        seq += 1

        if advanced_vtol:
            outputs = {
                "grp_L": {"throttle": 0.995 if is_sat else 0.55, "gimbalPitch": 12.0, "gimbalYaw": 0.0},
                "grp_R": {"throttle": 0.50, "gimbalPitch": 12.0, "gimbalYaw": 0.0},
            }
        else:
            outputs = {"main_left": 0.995 if is_sat else 0.60, "main_right": 0.50}

        records.append(
            {
                "recordType": "FRAME",
                "seqIdx": seq,
                "rxMs": rx + 15,
                "txMs": rx + 10,
                "channel": 10010,
                "offset": 10,
                "msgType": "MSG_THRUST_CMD",
                "payload": {"watchdogSeq": i + 1, "controlState": "NORMAL", "outputs": outputs},
            }
        )
        seq += 1

    records.append(
        {
            "recordType": "FOOTER",
            "endedAtMs": 1000 + count * 50,
            "trigger": "SESSION_END",
            "frameCount": seq - 1,
        }
    )
    return records


class TestAnalyzeFlightLog(unittest.TestCase):
    def setUp(self):
        if str(TOOLS_DIR) not in sys.path:
            sys.path.insert(0, str(TOOLS_DIR))
        import analyze_flight_log as afl  # noqa: WPS433

        self.afl = afl

    def test_resolve_and_merge_dedup_and_strict_truncation(self):
        recs = _make_sample_records(count=10)
        part1 = recs[:15]
        part2 = [recs[14]] + recs[15:]  # overlap frame 14 for dedup check

        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            d1 = root / "disk1" / "fdr_logs"
            d2 = root / "disk2" / "fdr_logs"
            d1.mkdir(parents=True)
            d2.mkdir(parents=True)
            p1 = d1 / "CRAFT_01_1000_part001.jsonl"
            p2 = d2 / "CRAFT_01_1000_part002.jsonl"
            p1.write_text("\n".join(json.dumps(r) for r in part1) + "\n", encoding="utf-8")
            p2.write_text(
                "\n".join(json.dumps(r) for r in part2) + "\n{truncated_json_line",
                encoding="utf-8",
            )

            resolved = self.afl.resolve_inputs([str(root)])
            self.assertEqual(len(resolved), 2)

            merged = self.afl.load_and_merge_jsonl(resolved, strict=False)
            self.assertEqual(merged["parseErrors"], 1)
            expected_frames = sum(1 for r in recs if r["recordType"] == "FRAME")
            self.assertEqual(len(merged["frames"]), expected_frames)

            with self.assertRaises(ValueError):
                self.afl.load_and_merge_jsonl(resolved, strict=True)

    def test_quat_to_euler_and_rate_command_tracking_skip(self):
        q = _euler_to_quat(12.5, -6.25, 210.0)
        e = self.afl.quat_to_euler_deg(q)
        self.assertAlmostEqual(e["pitch"], 12.5, places=3)
        self.assertAlmostEqual(e["roll"], -6.25, places=3)
        self.assertAlmostEqual(e["yaw"], 210.0, places=3)

        rate_frames = [r for r in _make_sample_records(count=15, pitch_err_deg=25.0, rate_command_only=True) if r["recordType"] == "FRAME"]
        aligned = self.afl.align_timeline(rate_frames, max_skew_ms=150)
        tracking = self.afl.compute_tracking_metrics(aligned)
        self.assertEqual(tracking["attitude"]["quatSampleCount"], 0)
        self.assertEqual(tracking["attitude"]["pitchRmseDeg"], 0.0)

    def test_saturation_distribution_and_tuning_safety_guards(self):
        # 1) High saturation (>= 15%) freezes Ki increase and clamps multipliers to [0.70, 1.35]
        recs = _make_sample_records(count=120, pitch_err_deg=8.0, sat_ratio=0.30, advanced_vtol=True, oscillate=True)
        frames = [r for r in recs if r["recordType"] == "FRAME"]
        aligned = self.afl.align_timeline(frames)
        sat = self.afl.compute_saturation_metrics(aligned)
        dist = self.afl.compute_thrust_distribution(aligned)
        tracking = self.afl.compute_tracking_metrics(aligned)

        self.assertGreater(sat["saturationFreezeRatio"], 0.25)
        self.assertIn("grp_L", dist["channels"])
        self.assertGreater(dist["channels"]["grp_L"]["max"], 0.99)

        baseline_pid = {
            "attitude": {
                "pitch": {"kp": 3.0, "ki": 0.2, "kd": 0.4, "integralLimit": 4.0},
                "roll": {"kp": 3.0, "ki": 0.2, "kd": 0.4, "integralLimit": 4.0},
                "yaw": {"kp": 2.5, "ki": 0.1, "kd": 0.3, "integralLimit": 2.5},
            }
        }
        report = {
            "telemetryCount": len(aligned),
            "tracking": tracking,
            "saturation": sat,
            "thrustDistribution": dist,
        }
        profile = self.afl.generate_tuning_profile(report, baseline_pid=baseline_pid, min_samples=100)
        self.assertTrue(profile["eligible"])
        tuned_pitch = profile["pidPatch"]["attitude"]["pitch"]
        self.assertLessEqual(tuned_pitch["ki"], baseline_pid["attitude"]["pitch"]["ki"])
        self.assertLessEqual(tuned_pitch["kp"], baseline_pid["attitude"]["pitch"]["kp"] * 1.35 + 1e-9)
        self.assertGreaterEqual(tuned_pitch["kp"], baseline_pid["attitude"]["pitch"]["kp"] * 0.70 - 1e-9)

        # 2) Sensor fault ratio > 20% blocks tuning
        faulty_frames = [r for r in _make_sample_records(count=120, sensor_fault_ratio=0.25) if r["recordType"] == "FRAME"]
        faulty_sat = self.afl.compute_saturation_metrics(self.afl.align_timeline(faulty_frames))
        blocked_sensor = self.afl.generate_tuning_profile(
            {"telemetryCount": 120, "tracking": tracking, "saturation": faulty_sat, "thrustDistribution": dist},
            baseline_pid=baseline_pid,
            min_samples=100,
        )
        self.assertFalse(blocked_sensor["eligible"])
        self.assertEqual(blocked_sensor["blockedReason"], "SENSOR_FAULT_RATE_EXCEEDED")

        # 3) Insufficient samples (< 100) blocks tuning
        blocked_samples = self.afl.generate_tuning_profile(
            {"telemetryCount": 50, "tracking": tracking, "saturation": sat, "thrustDistribution": dist},
            baseline_pid=baseline_pid,
            min_samples=100,
        )
        self.assertFalse(blocked_samples["eligible"])
        self.assertEqual(blocked_samples["blockedReason"], "INSUFFICIENT_SAMPLES")

    def test_cli_json_csv_and_emit_profile(self):
        recs = _make_sample_records(count=110, pitch_err_deg=3.0)
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            log_path = root / "flight.jsonl"
            log_path.write_text("\n".join(json.dumps(r) for r in recs) + "\n", encoding="utf-8")
            base_pid_path = root / "pid.json"
            base_pid_path.write_text(
                json.dumps({"attitude": {"pitch": {"kp": 3.0, "ki": 0.15, "kd": 0.45, "integralLimit": 4.0}}}),
                encoding="utf-8",
            )
            out_json = root / "report.json"
            out_csv = root / "frames.csv"
            emit_dir = root / "out_profile"

            proc = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    str(log_path),
                    "--json",
                    str(out_json),
                    "--csv",
                    str(out_csv),
                    "--emit-profile",
                    str(emit_dir),
                    "--baseline-pid",
                    str(base_pid_path),
                    "--top",
                    "3",
                    "--strict",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertTrue(out_json.exists())
            self.assertTrue(out_csv.exists())
            for fname in ("pid_tuned.json", "system_patch.json", "fcp_patch.json", "tuning_summary.json"):
                self.assertTrue((emit_dir / fname).exists(), f"missing {fname}")

    def test_craftospc_fdr_to_python_analyzer_roundtrip(self):
        exe = os.environ.get("CRAFTOS_PC_EXE") or shutil.which("CraftOS-PC_console") or r"C:\Program Files\CraftOS-PC\CraftOS-PC_console.exe"
        if not Path(exe).is_file():
            self.skipTest("CraftOS-PC_console executable not available")

        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            data_dir = root / "cc_data"
            comp_dir = data_dir / "computer" / "0"
            fdr_src = WORKSPACE_ROOT / "src" / "0_development" / "fdr"
            shutil.copytree(fdr_src / "modules", comp_dir / "modules")
            (comp_dir / "main.lua").write_text((fdr_src / "main.lua").read_text(encoding="utf-8"), encoding="utf-8")
            (comp_dir / "disk" / "fdr_logs").mkdir(parents=True)

            startup_lua = """
local ok, err = pcall(function()
    package.path = "/modules/?.lua;" .. package.path
    local fdr_main = require("main")
    local st = fdr_main.init({
        schemaVersion = "1.1.0",
        aircraftIndexN = 1,
        domainId = "*",
        autoStartOnBoot = true,
        recordMode = "STREAMING",
        tapOptions = { aero = true, trajectory = true, includeControlEvents = false },
        streaming = { flushIntervalFrames = 20, flushIntervalSec = 1.0 },
        storage = {
            preferExternalDisk = false,
            allowLocalFallback = true,
            localDumpDir = "/disk/fdr_logs",
            maxPartBytes = 12000,
            rollOverReserveBytes = 1024,
            minFreeSpaceBytes = 1024,
            autoPruneOldest = false,
            autoFlushOnEstop = true,
        },
        export = { mode = "NONE" },
    }, {
        modem = { open = function() end, close = function() end, isOpen = function() return true end, isWireless = function() return true end },
        epoch = function() return 5000 end,
    })
    for i = 1, 105 do
        local ts = 5000 + i * 50
        st.apis.epoch = function() return ts end
        fdr_main.handle_event(st, "modem_message", "top", 10001, 10001, {
            ver = "1.9.5", domainId = "CRAFT_CC", seq = i, time = ts,
            type = "MSG_ATTITUDE_CMD",
            payload = { commandType = "QUATERNION_RATE", targetQuaternion = { w = 1, x = 0, y = 0, z = 0 }, collectiveThrust = 0.6 },
        })
        fdr_main.handle_event(st, "modem_message", "top", 10002, 10002, {
            ver = "1.9.5", domainId = "CRAFT_CC", seq = i, time = ts + 10,
            type = "MSG_FLIGHT_TELEMETRY",
            payload = {
                attitude = { w = 0.996, x = 0.0, y = 0.087, z = 0.0 },
                angularRates = { p = 0, q = 0.01, r = 0 },
                dynamics = { altitudeY = 80.0, verticalSpeed = 0.0, velocity = { vx = 0, vy = 0, vz = 0 } },
                controlState = "NORMAL", activeSource = "FCP", sensorOk = true,
                satFlags = { axisSaturatedPos = {}, axisSaturatedNeg = {} },
                diag = { saturationFreeze = false, integrators = { pitch = 0.2, roll = 0, yaw = 0, climb = 0 }, integralLimits = { pitch = 4, roll = 4, yaw = 2.5, climb = 3 } },
            },
        })
        fdr_main.handle_event(st, "modem_message", "top", 10010, 10010, {
            ver = "1.9.5", domainId = "CRAFT_CC", seq = i, time = ts + 15,
            type = "MSG_THRUST_CMD",
            payload = { watchdogSeq = i, controlState = "NORMAL", outputs = { thr1 = 0.55, thr2 = 0.50 } },
        })
    end
    fdr_main.shutdown(st, "ROUNDTRIP_OK")
end)
if not ok then
    local f = fs.open("/roundtrip_err.txt", "w")
    f.write(tostring(err))
    f.close()
end
os.shutdown()
"""
            # Prevent auto-running main.run() when main is required by startup.lua
            main_txt = (comp_dir / "main.lua").read_text(encoding="utf-8")
            (comp_dir / "main.lua").write_text(" _G.__HARNESS_HIL_MODE = true\n" + main_txt, encoding="utf-8")
            (comp_dir / "startup.lua").write_text(startup_lua, encoding="utf-8")

            cc_proc = subprocess.run(
                [exe, "--headless", "--directory", str(data_dir)],
                capture_output=True,
                text=True,
                timeout=15,
            )
            self.assertEqual(cc_proc.returncode, 0, cc_proc.stderr)
            err_file = comp_dir / "roundtrip_err.txt"
            self.assertFalse(err_file.exists(), err_file.read_text(encoding="utf-8") if err_file.exists() else "")

            jsonl_files = sorted((comp_dir / "disk" / "fdr_logs").rglob("*.jsonl"))
            self.assertGreaterEqual(len(jsonl_files), 2)

            out_json = root / "cc_report.json"
            emit_dir = root / "cc_profile"
            az_proc = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    str(comp_dir / "disk" / "fdr_logs"),
                    "--json",
                    str(out_json),
                    "--emit-profile",
                    str(emit_dir),
                    "--strict",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(az_proc.returncode, 0, az_proc.stderr)
            rep = json.loads(out_json.read_text(encoding="utf-8"))
            self.assertEqual(rep["parseErrors"], 0)
            self.assertGreaterEqual(rep["telemetryCount"], 100)
            summary = json.loads((emit_dir / "tuning_summary.json").read_text(encoding="utf-8"))
            self.assertTrue(summary["eligible"])


if __name__ == "__main__":
    unittest.main()
