#!/usr/bin/env python3
"""
Create_Aeroneutics Host Offline Telemetry Analyzer & Profiler (TASK-120 / v0.3.0).

Merges multi-part JSONL logs recorded by the Ground FDR In-Flight Aligner,
evaluates closed-loop tracking, actuator/integrator saturation, and thrust
distribution, and emits bounded JSON configuration patch recommendations.
"""
from __future__ import annotations

import argparse
import csv
import glob
import json
import math
import statistics
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

DEFAULT_PID_BASELINE: Dict[str, Any] = {
    "attitude": {
        "pitch": {"kp": 3.2, "ki": 0.15, "kd": 0.45, "integralLimit": 4.0},
        "roll": {"kp": 3.5, "ki": 0.12, "kd": 0.48, "integralLimit": 4.0},
        "yaw": {"kp": 2.8, "ki": 0.08, "kd": 0.35, "integralLimit": 2.5},
    },
    "climb": {"kp": 2.0, "ki": 0.10, "kd": 0.00, "integralLimit": 3.0},
}

DEFAULT_SYSTEM_BASELINE: Dict[str, Any] = {
    "loopFrequencyHz": 20,
    "telemetryDiag": False,
}

DEFAULT_FCP_BASELINE: Dict[str, Any] = {
    "maxBankAngleDeg": 35.0,
    "maxPitchAngleDeg": 30.0,
    "maxClimbRate": 8.0,
}

GAIN_MULT_MIN = 0.70
GAIN_MULT_MAX = 1.35


def _wrap_angle_deg(deg: float) -> float:
    return (deg + 180.0) % 360.0 - 180.0


def _clamp(val: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, val))


def _percentile(sorted_vals: List[float], pct: float) -> float:
    if not sorted_vals:
        return 0.0
    idx = (len(sorted_vals) - 1) * _clamp(pct, 0.0, 1.0)
    lo = int(math.floor(idx))
    hi = int(math.ceil(idx))
    if lo == hi:
        return sorted_vals[lo]
    frac = idx - lo
    return sorted_vals[lo] * (1.0 - frac) + sorted_vals[hi] * frac


def resolve_inputs(inputs: Iterable[str]) -> List[Path]:
    """Expand files, globs, directories, and session manifests into sorted JSONL Paths."""
    collected: List[Path] = []
    seen = set()

    def add_path(p: Path) -> None:
        rp = p.resolve()
        if rp.is_file() and rp not in seen:
            seen.add(rp)
            collected.append(rp)

    for raw in inputs:
        matches = glob.glob(raw, recursive=True)
        candidates = [Path(m) for m in matches] if matches else [Path(raw)]
        for cand in candidates:
            if cand.is_dir():
                for jf in sorted(cand.rglob("*.jsonl")):
                    add_path(jf)
            elif cand.is_file() and cand.suffix.lower() == ".json":
                manifest = json.loads(cand.read_text(encoding="utf-8"))
                for part in manifest.get("parts", []):
                    fp = part.get("filePath")
                    if not fp:
                        continue
                    p_cand = Path(fp)
                    if not p_cand.is_file():
                        p_cand = cand.parent / Path(fp).name
                    if p_cand.is_file():
                        add_path(p_cand)
            elif cand.is_file():
                add_path(cand)

    return sorted(collected)


def parse_window(window_str: Optional[str]) -> Optional[Tuple[int, int]]:
    """Parse --window START_MS:END_MS argument."""
    if not window_str:
        return None
    parts = window_str.split(":", 1)
    if len(parts) != 2:
        raise ValueError(f"Invalid --window format (expected start:end): {window_str}")
    start_ms = int(parts[0]) if parts[0] else 0
    end_ms = int(parts[1]) if parts[1] else (1 << 62)
    return start_ms, end_ms


def load_and_merge_jsonl(
    paths: Iterable[Path],
    strict: bool = False,
    window: Optional[Tuple[int, int]] = None,
) -> Dict[str, Any]:
    """Load multiple JSONL files, deduplicate FRAME records, and sort chronologically."""
    metas: List[Dict[str, Any]] = []
    footers: List[Dict[str, Any]] = []
    frames: List[Dict[str, Any]] = []
    dedup_keys = set()
    parse_errors = 0

    for path in paths:
        for line_no, raw_line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
            stripped = raw_line.strip()
            if not stripped:
                continue
            try:
                rec = json.loads(stripped)
            except json.JSONDecodeError as exc:
                if strict:
                    raise ValueError(f"Malformed JSON in {path}:{line_no}: {exc}") from exc
                parse_errors += 1
                continue

            if not isinstance(rec, dict):
                if strict:
                    raise ValueError(f"Non-object JSON record in {path}:{line_no}")
                parse_errors += 1
                continue

            rtype = rec.get("recordType", "FRAME")
            if rtype == "META":
                metas.append(rec)
                continue
            if rtype == "FOOTER":
                footers.append(rec)
                continue

            rx_ms = int(rec.get("rxMs", 0) or 0)
            if window and not (window[0] <= rx_ms <= window[1]):
                continue
            seq_idx = rec.get("seqIdx")
            dkey = (
                (rx_ms, int(seq_idx))
                if seq_idx is not None
                else (rx_ms, rec.get("channel"), rec.get("msgType"), rec.get("pktSeq"))
            )
            if dkey in dedup_keys:
                continue
            dedup_keys.add(dkey)
            frames.append(rec)

    frames.sort(key=lambda r: (int(r.get("rxMs", 0) or 0), int(r.get("seqIdx", 0) or 0)))
    return {
        "metas": metas,
        "footers": footers,
        "frames": frames,
        "parseErrors": parse_errors,
    }


def quat_to_euler_deg(q: Optional[Dict[str, Any]]) -> Dict[str, float]:
    """Convert quaternion {w,x,y,z} to Euler degrees matching src/1_control/vas/modules/quat.lua."""
    if not isinstance(q, dict):
        return {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}
    w = float(q.get("w", 1.0) or 0.0)
    x = float(q.get("x", 0.0) or 0.0)
    y = float(q.get("y", 0.0) or 0.0)
    z = float(q.get("z", 0.0) or 0.0)
    norm = math.sqrt(w * w + x * x + y * y + z * z)
    if norm > 1e-9:
        inv = 1.0 / norm
        w, x, y, z = w * inv, x * inv, y * inv, z * inv
    else:
        w, x, y, z = 1.0, 0.0, 0.0, 0.0

    sinp = 2.0 * (w * y - z * x)
    if abs(sinp) >= 1.0:
        pitch_rad = math.copysign(math.pi * 0.5, sinp)
    else:
        pitch_rad = math.asin(sinp)

    roll_rad = math.atan2(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y))
    yaw_rad = math.atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))
    yaw_deg = (math.degrees(yaw_rad) + 360.0) % 360.0
    return {
        "pitch": math.degrees(pitch_rad),
        "roll": math.degrees(roll_rad),
        "yaw": yaw_deg,
    }


def _find_nearest_within(
    candidates: List[Tuple[int, Dict[str, Any]]],
    idx_hint: int,
    target_rx: int,
    max_skew_ms: int,
) -> Tuple[Optional[Dict[str, Any]], int]:
    n = len(candidates)
    if n == 0:
        return None, 0
    i = min(idx_hint, n - 1)
    while i + 1 < n and abs(candidates[i + 1][0] - target_rx) <= abs(candidates[i][0] - target_rx):
        i += 1
    while i > 0 and abs(candidates[i - 1][0] - target_rx) < abs(candidates[i][0] - target_rx):
        i -= 1
    rx_cand, rec = candidates[i]
    if abs(rx_cand - target_rx) <= max_skew_ms:
        return rec, i
    return None, i


def align_timeline(frames: List[Dict[str, Any]], max_skew_ms: int = 150) -> List[Dict[str, Any]]:
    """Pair each MSG_FLIGHT_TELEMETRY frame with nearby command/setpoint/actuator packets."""
    by_type: Dict[str, List[Tuple[int, Dict[str, Any]]]] = {
        "MSG_ATTITUDE_CMD": [],
        "MSG_TRAJECTORY_SETPOINT": [],
        "MSG_THRUST_CMD": [],
        "MSG_AERO_CMD": [],
        "MSG_OUTER_LOOP_STATUS": [],
    }
    telem_frames: List[Dict[str, Any]] = []
    for rec in frames:
        mtype = rec.get("msgType", "")
        rx_ms = int(rec.get("rxMs", 0) or 0)
        if mtype == "MSG_FLIGHT_TELEMETRY":
            telem_frames.append(rec)
        elif mtype in by_type:
            by_type[mtype].append((rx_ms, rec))

    hints = {k: 0 for k in by_type}
    aligned: List[Dict[str, Any]] = []
    for telem in telem_frames:
        rx_ms = int(telem.get("rxMs", 0) or 0)
        entry: Dict[str, Any] = {"rxMs": rx_ms, "telemetry": telem}
        for mtype, key_name in (
            ("MSG_ATTITUDE_CMD", "attitudeCmd"),
            ("MSG_TRAJECTORY_SETPOINT", "trajectorySetpoint"),
            ("MSG_THRUST_CMD", "thrustCmd"),
            ("MSG_AERO_CMD", "aeroCmd"),
            ("MSG_OUTER_LOOP_STATUS", "outerStatus"),
        ):
            match, next_hint = _find_nearest_within(by_type[mtype], hints[mtype], rx_ms, max_skew_ms)
            hints[mtype] = next_hint
            entry[key_name] = match
        aligned.append(entry)
    return aligned


def _count_zero_crossings(series: List[float], deadband: float = 0.25) -> int:
    crossings = 0
    prev_sign = 0
    for val in series:
        if abs(val) < deadband:
            continue
        cur_sign = 1 if val > 0 else -1
        if prev_sign != 0 and cur_sign != prev_sign:
            crossings += 1
        prev_sign = cur_sign
    return crossings


def _axis_summary(errors: List[float]) -> Dict[str, Any]:
    if not errors:
        return {"rmse": 0.0, "maxAbs": 0.0, "bias": 0.0, "oscillationCrossings": 0}
    rmse = math.sqrt(sum(e * e for e in errors) / len(errors))
    return {
        "rmse": round(rmse, 4),
        "maxAbs": round(max(abs(e) for e in errors), 4),
        "bias": round(statistics.mean(errors), 4),
        "oscillationCrossings": _count_zero_crossings(errors),
    }


def compute_tracking_metrics(aligned: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Compute quaternion attitude tracking and optional outer-loop trajectory errors."""
    pitch_errs: List[float] = []
    roll_errs: List[float] = []
    yaw_errs: List[float] = []
    alt_errs: List[float] = []
    rate_cmd_skipped = 0

    for item in aligned:
        telem_p = (item.get("telemetry") or {}).get("payload") or {}
        att_cmd = item.get("attitudeCmd")
        if att_cmd:
            cmd_p = att_cmd.get("payload") or {}
            ctype = cmd_p.get("commandType", "")
            if ctype == "RATE_COMMAND":
                rate_cmd_skipped += 1
            elif ctype == "QUATERNION_RATE" and isinstance(cmd_p.get("targetQuaternion"), dict):
                meas_e = quat_to_euler_deg(telem_p.get("attitude"))
                tgt_e = quat_to_euler_deg(cmd_p.get("targetQuaternion"))
                pitch_errs.append(tgt_e["pitch"] - meas_e["pitch"])
                roll_errs.append(tgt_e["roll"] - meas_e["roll"])
                yaw_errs.append(_wrap_angle_deg(tgt_e["yaw"] - meas_e["yaw"]))

        traj_cmd = item.get("trajectorySetpoint")
        if traj_cmd:
            tp = traj_cmd.get("payload") or {}
            dyn = telem_p.get("dynamics") or {}
            tgt_alt = tp.get("targetAltitudeY") or (tp.get("targetPosition") or {}).get("y")
            if tgt_alt is not None and dyn.get("altitudeY") is not None:
                alt_errs.append(float(tgt_alt) - float(dyn["altitudeY"]))

    p_sum = _axis_summary(pitch_errs)
    r_sum = _axis_summary(roll_errs)
    y_sum = _axis_summary(yaw_errs)
    a_sum = _axis_summary(alt_errs)
    return {
        "attitude": {
            "quatSampleCount": len(pitch_errs),
            "rateCommandSkippedCount": rate_cmd_skipped,
            "pitchRmseDeg": p_sum["rmse"],
            "rollRmseDeg": r_sum["rmse"],
            "yawRmseDeg": y_sum["rmse"],
            "axes": {"pitch": p_sum, "roll": r_sum, "yaw": y_sum},
        },
        "altitude": {"sampleCount": len(alt_errs), **a_sum},
    }


def _output_is_saturated(outputs: Any, threshold: float = 0.99) -> bool:
    if not isinstance(outputs, dict):
        return False
    for val in outputs.values():
        if isinstance(val, (int, float)) and abs(float(val)) >= threshold:
            return True
        if isinstance(val, dict):
            thr = val.get("throttle", val.get("power"))
            if isinstance(thr, (int, float)) and abs(float(thr)) >= threshold:
                return True
    return False


def compute_saturation_metrics(aligned: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Compute VAS diag/satFlags stats with passive actuator saturation fallback."""
    total = len(aligned)
    if total == 0:
        return {
            "sampleCount": 0,
            "diagSampleCount": 0,
            "saturationFreezeRatio": 0.0,
            "actuatorSaturationRatio": 0.0,
            "sensorFaultRatio": 0.0,
            "axisSaturationCounts": {"pitch": 0, "roll": 0, "yaw": 0, "surge": 0},
            "maxIntegratorUsageRatio": {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "climb": 0.0},
        }

    diag_samples = 0
    freeze_count = 0
    actuator_sat_count = 0
    sensor_faults = 0
    axis_counts = {"pitch": 0, "roll": 0, "yaw": 0, "surge": 0}
    max_int_ratio = {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "climb": 0.0}

    for item in aligned:
        tp = (item.get("telemetry") or {}).get("payload") or {}
        if tp.get("sensorOk") is False:
            sensor_faults += 1

        sat_flags = tp.get("satFlags")
        diag = tp.get("diag")
        if isinstance(diag, dict) or isinstance(sat_flags, dict):
            diag_samples += 1
            if isinstance(diag, dict) and diag.get("saturationFreeze") is True:
                freeze_count += 1
            if isinstance(sat_flags, dict):
                pos = sat_flags.get("axisSaturatedPos") or {}
                neg = sat_flags.get("axisSaturatedNeg") or {}
                for ax in axis_counts:
                    if pos.get(ax) is True or neg.get(ax) is True:
                        axis_counts[ax] += 1
            if isinstance(diag, dict):
                ints = diag.get("integrators") or {}
                lims = diag.get("integralLimits") or {}
                for ax in max_int_ratio:
                    lim = float(lims.get(ax, 0.0) or 0.0)
                    if lim > 1e-6 and ax in ints:
                        ratio = abs(float(ints[ax])) / lim
                        if ratio > max_int_ratio[ax]:
                            max_int_ratio[ax] = round(ratio, 4)

        thrust_p = ((item.get("thrustCmd") or {}).get("payload") or {}).get("outputs")
        aero_p = ((item.get("aeroCmd") or {}).get("payload") or {}).get("surfaces")
        if _output_is_saturated(thrust_p) or _output_is_saturated(aero_p):
            actuator_sat_count += 1

    freeze_denom = diag_samples if diag_samples > 0 else total
    return {
        "sampleCount": total,
        "diagSampleCount": diag_samples,
        "saturationFreezeRatio": round(freeze_count / freeze_denom, 4),
        "actuatorSaturationRatio": round(actuator_sat_count / total, 4),
        "sensorFaultRatio": round(sensor_faults / total, 4),
        "axisSaturationCounts": axis_counts,
        "maxIntegratorUsageRatio": max_int_ratio,
    }


def compute_thrust_distribution(aligned: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Compute scalar and ADVANCED_VTOL per-channel thrust distribution statistics."""
    samples_by_ch: Dict[str, List[float]] = {}
    gimbal_pitch_by_ch: Dict[str, List[float]] = {}

    for item in aligned:
        outputs = ((item.get("thrustCmd") or {}).get("payload") or {}).get("outputs")
        if not isinstance(outputs, dict):
            continue
        for ch_name, val in outputs.items():
            if isinstance(val, (int, float)):
                samples_by_ch.setdefault(ch_name, []).append(float(val))
            elif isinstance(val, dict):
                thr = val.get("throttle", val.get("power"))
                if isinstance(thr, (int, float)):
                    samples_by_ch.setdefault(ch_name, []).append(float(thr))
                gp = val.get("gimbalPitch")
                if isinstance(gp, (int, float)):
                    gimbal_pitch_by_ch.setdefault(ch_name, []).append(float(gp))

    channels: Dict[str, Any] = {}
    means: List[float] = []
    for ch_name in sorted(samples_by_ch):
        vals = sorted(samples_by_ch[ch_name])
        mean_val = statistics.mean(vals)
        means.append(mean_val)
        entry: Dict[str, Any] = {
            "samples": len(vals),
            "min": round(vals[0], 4),
            "mean": round(mean_val, 4),
            "p95": round(_percentile(vals, 0.95), 4),
            "max": round(vals[-1], 4),
        }
        if ch_name in gimbal_pitch_by_ch:
            gp_vals = gimbal_pitch_by_ch[ch_name]
            entry["gimbalPitchMaxAbsDeg"] = round(max(abs(v) for v in gp_vals), 3)
        channels[ch_name] = entry

    imbalance = (max(means) - min(means)) if len(means) >= 2 else 0.0
    return {
        "channelCount": len(channels),
        "meanImbalance": round(imbalance, 4),
        "channels": channels,
    }


def _tune_axis_gains(
    base_gains: Dict[str, float],
    axis_metrics: Dict[str, Any],
    is_saturated: bool,
    sample_count: int,
) -> Tuple[Dict[str, float], str]:
    kp = float(base_gains.get("kp", 3.0))
    ki = float(base_gains.get("ki", 0.1))
    kd = float(base_gains.get("kd", 0.4))
    ilim = float(base_gains.get("integralLimit", 4.0))

    rmse = float(axis_metrics.get("rmse", 0.0))
    crossings = int(axis_metrics.get("oscillationCrossings", 0))
    osc_rate = crossings / max(1, sample_count)
    kp_mult, ki_mult, kd_mult = 1.0, 1.0, 1.0
    notes: List[str] = []

    if osc_rate >= 0.08:
        kp_mult = 0.85
        kd_mult = 1.25
        notes.append("oscillation_damping")
    elif rmse >= 5.0:
        kp_mult = 1.20
        kd_mult = 1.10
        notes.append("high_tracking_error_boost")
    elif rmse >= 2.0:
        kp_mult = 1.10
        notes.append("moderate_tracking_error_boost")

    if is_saturated:
        ki_mult = 0.85
        notes.append("saturation_ki_freeze_trim")
    elif abs(float(axis_metrics.get("bias", 0.0))) >= 1.5 and osc_rate < 0.05:
        ki_mult = 1.15
        notes.append("steady_bias_ki_boost")

    kp_mult = _clamp(kp_mult, GAIN_MULT_MIN, GAIN_MULT_MAX)
    ki_mult = _clamp(ki_mult, GAIN_MULT_MIN, 1.0 if is_saturated else GAIN_MULT_MAX)
    kd_mult = _clamp(kd_mult, GAIN_MULT_MIN, GAIN_MULT_MAX)

    tuned = {
        "kp": round(kp * kp_mult, 4),
        "ki": round(ki * ki_mult, 4),
        "kd": round(kd * kd_mult, 4),
        "integralLimit": ilim,
    }
    return tuned, (", ".join(notes) if notes else "nominal")


def generate_tuning_profile(
    report: Dict[str, Any],
    baseline_pid: Optional[Dict[str, Any]] = None,
    baseline_system: Optional[Dict[str, Any]] = None,
    baseline_fcp: Optional[Dict[str, Any]] = None,
    min_samples: int = 100,
) -> Dict[str, Any]:
    """Generate bounded [0.70x, 1.35x] tuning patches with sensor/sample/saturation guards."""
    pid_base = json.loads(json.dumps(baseline_pid or DEFAULT_PID_BASELINE))
    sys_base = json.loads(json.dumps(baseline_system or DEFAULT_SYSTEM_BASELINE))
    fcp_base = json.loads(json.dumps(baseline_fcp or DEFAULT_FCP_BASELINE))

    sat = report.get("saturation") or {}
    tracking = report.get("tracking") or {}
    att = tracking.get("attitude") or {}
    att_axes = att.get("axes") or {}
    n_samples = int(report.get("telemetryCount", 0) or 0)
    fault_ratio = float(sat.get("sensorFaultRatio", 0.0) or 0.0)

    if fault_ratio > 0.20:
        return {
            "eligible": False,
            "blockedReason": "SENSOR_FAULT_RATE_EXCEEDED",
            "sensorFaultRatio": fault_ratio,
            "telemetryCount": n_samples,
            "pidPatch": pid_base,
            "systemPatch": sys_base,
            "fcpPatch": fcp_base,
        }
    if n_samples < min_samples:
        return {
            "eligible": False,
            "blockedReason": "INSUFFICIENT_SAMPLES",
            "sensorFaultRatio": fault_ratio,
            "telemetryCount": n_samples,
            "minSamplesRequired": min_samples,
            "pidPatch": pid_base,
            "systemPatch": sys_base,
            "fcpPatch": fcp_base,
        }

    is_saturated = (
        float(sat.get("saturationFreezeRatio", 0.0) or 0.0) >= 0.15
        or float(sat.get("actuatorSaturationRatio", 0.0) or 0.0) >= 0.15
    )

    pid_att = pid_base.setdefault("attitude", {})
    rationale: Dict[str, str] = {}
    for axis_name in ("pitch", "roll", "yaw"):
        if axis_name not in pid_att:
            pid_att[axis_name] = dict(DEFAULT_PID_BASELINE["attitude"][axis_name])
        tuned_axis, note = _tune_axis_gains(
            pid_att[axis_name],
            att_axes.get(axis_name, {}),
            is_saturated=is_saturated,
            sample_count=n_samples,
        )
        pid_att[axis_name] = tuned_axis
        rationale[axis_name] = note

    if is_saturated and "maxBankAngleDeg" in fcp_base:
        fcp_base["maxBankAngleDeg"] = round(float(fcp_base["maxBankAngleDeg"]) * 0.85, 2)
        rationale["fcp"] = "reduced_max_bank_due_to_saturation"
    else:
        rationale["fcp"] = "nominal"

    return {
        "eligible": True,
        "blockedReason": None,
        "clampBounds": [GAIN_MULT_MIN, GAIN_MULT_MAX],
        "isSaturated": is_saturated,
        "telemetryCount": n_samples,
        "sensorFaultRatio": fault_ratio,
        "rationale": rationale,
        "pidPatch": pid_base,
        "systemPatch": sys_base,
        "fcpPatch": fcp_base,
    }


def build_report(
    merged: Dict[str, Any],
    aligned: List[Dict[str, Any]],
    top_n: int = 5,
) -> Dict[str, Any]:
    """Assemble structured telemetry analysis summary from merged JSONL and aligned frames."""
    frames = merged["frames"]
    rx_times = [int(f.get("rxMs", 0) or 0) for f in frames]
    duration_sec = ((rx_times[-1] - rx_times[0]) / 1000.0) if len(rx_times) >= 2 else 0.0
    tracking = compute_tracking_metrics(aligned)
    saturation = compute_saturation_metrics(aligned)
    distribution = compute_thrust_distribution(aligned)

    top_channels = sorted(
        distribution["channels"].items(),
        key=lambda kv: kv[1]["max"],
        reverse=True,
    )[: max(1, top_n)]

    return {
        "sessionCount": len(merged["metas"]),
        "totalFrames": len(frames),
        "telemetryCount": len(aligned),
        "parseErrors": merged["parseErrors"],
        "durationSec": round(duration_sec, 3),
        "tracking": tracking,
        "saturation": saturation,
        "thrustDistribution": distribution,
        "topChannels": [{"channel": k, **v} for k, v in top_channels],
    }


def export_csv(aligned: List[Dict[str, Any]], csv_path: Path) -> None:
    """Write flattened per-telemetry-frame time-series CSV for host plotting."""
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "rxMs",
        "controlState",
        "sensorOk",
        "pitchDeg",
        "rollDeg",
        "yawDeg",
        "altitudeY",
        "verticalSpeed",
        "saturationFreeze",
    ]
    with csv_path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        for item in aligned:
            tp = (item.get("telemetry") or {}).get("payload") or {}
            euler = quat_to_euler_deg(tp.get("attitude"))
            dyn = tp.get("dynamics") or {}
            diag = tp.get("diag") or {}
            writer.writerow(
                {
                    "rxMs": item.get("rxMs", 0),
                    "controlState": tp.get("controlState", ""),
                    "sensorOk": tp.get("sensorOk", ""),
                    "pitchDeg": round(euler["pitch"], 4),
                    "rollDeg": round(euler["roll"], 4),
                    "yawDeg": round(euler["yaw"], 4),
                    "altitudeY": dyn.get("altitudeY", ""),
                    "verticalSpeed": dyn.get("verticalSpeed", ""),
                    "saturationFreeze": diag.get("saturationFreeze", ""),
                }
            )


def _load_optional_json(path_str: Optional[str]) -> Optional[Dict[str, Any]]:
    if not path_str:
        return None
    return json.loads(Path(path_str).read_text(encoding="utf-8"))


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Analyze FDR JSONL telemetry logs and emit tuning patches.")
    parser.add_argument("inputs", nargs="+", help="JSONL log files, directories, globs, or session_manifest.json")
    parser.add_argument("--json", dest="json_out", help="Write full JSON analysis report to path")
    parser.add_argument("--csv", dest="csv_out", help="Write flattened CSV time-series to path")
    parser.add_argument("--emit-profile", dest="profile_dir", help="Directory for pid/system/fcp patch JSON files")
    parser.add_argument("--baseline-pid", help="Baseline pid.json path")
    parser.add_argument("--baseline-system", help="Baseline system.json path")
    parser.add_argument("--baseline-fcp", help="Baseline fcp.json path")
    parser.add_argument("--window", help="Time filter window start_ms:end_ms")
    parser.add_argument("--top", type=int, default=5, help="Top N thruster channels to highlight")
    parser.add_argument("--min-samples", type=int, default=100, help="Minimum samples before emitting active tuning")
    parser.add_argument("--strict", action="store_true", help="Fail immediately on malformed JSONL lines")
    args = parser.parse_args(argv)

    paths = resolve_inputs(args.inputs)
    if not paths:
        print("[ERROR] No matching JSONL files found.", file=sys.stderr)
        return 1

    try:
        window = parse_window(args.window)
        merged = load_and_merge_jsonl(paths, strict=args.strict, window=window)
    except ValueError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    aligned = align_timeline(merged["frames"])
    report = build_report(merged, aligned, top_n=args.top)

    if args.json_out:
        out_p = Path(args.json_out)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        out_p.write_text(json.dumps(report, indent=2), encoding="utf-8")

    if args.csv_out:
        export_csv(aligned, Path(args.csv_out))

    if args.profile_dir:
        prof = generate_tuning_profile(
            report,
            baseline_pid=_load_optional_json(args.baseline_pid),
            baseline_system=_load_optional_json(args.baseline_system),
            baseline_fcp=_load_optional_json(args.baseline_fcp),
            min_samples=args.min_samples,
        )
        pdir = Path(args.profile_dir)
        pdir.mkdir(parents=True, exist_ok=True)
        (pdir / "pid_tuned.json").write_text(json.dumps(prof["pidPatch"], indent=2), encoding="utf-8")
        (pdir / "system_patch.json").write_text(json.dumps(prof["systemPatch"], indent=2), encoding="utf-8")
        (pdir / "fcp_patch.json").write_text(json.dumps(prof["fcpPatch"], indent=2), encoding="utf-8")
        summary = {k: v for k, v in prof.items() if k not in ("pidPatch", "systemPatch", "fcpPatch")}
        (pdir / "tuning_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    att = report["tracking"]["attitude"]
    sat = report["saturation"]
    print(
        f"FDR Analysis | files={len(paths)} frames={report['totalFrames']} telem={report['telemetryCount']} "
        f"pitchRMSE={att['pitchRmseDeg']}deg rollRMSE={att['rollRmseDeg']}deg "
        f"satFreeze={sat['saturationFreezeRatio']*100:.1f}% sensorFault={sat['sensorFaultRatio']*100:.1f}%"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
