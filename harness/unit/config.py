"""
Configuration and target discovery for Create_Aeroneutics unit test runner.
"""
from __future__ import annotations

import json
import os
import re
import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping


@dataclass
class PeripheralAttachment:
    side: str | int
    peripheral_type: str
    args: list[Any] = field(default_factory=list)


@dataclass
class CraftOSPaths:
    craftos_exe: Path
    rom_dir: Path
    lua52_dll: Path | None


@dataclass
class UnitTargetConfig:
    target_id: str
    source_dir: Path
    tests_dir: Path
    timeout_sec: float = 8.0
    abort_timeout_ms: int = 4000
    term_width: int = 51
    term_height: int = 19
    max_instructions_per_tick: int = 50000
    peripherals: list[PeripheralAttachment] = field(
        default_factory=lambda: [PeripheralAttachment(side="top", peripheral_type="modem")]
    )


def resolve_craftos_paths(env: Mapping[str, str] | None = None) -> CraftOSPaths:
    env_map = os.environ if env is None else env

    override_exe = env_map.get("CRAFTOS_PC_EXE")
    if override_exe:
        exe_path = Path(override_exe).resolve()
        if not exe_path.exists():
            raise FileNotFoundError(f"CRAFTOS_PC_EXE override not found: {exe_path}")
    else:
        which_exe = shutil.which("CraftOS-PC_console.exe")
        candidates = [
            Path(which_exe) if which_exe else None,
            Path(r"C:\Program Files\CraftOS-PC\CraftOS-PC_console.exe"),
            Path(r"C:\Program Files (x86)\CraftOS-PC\CraftOS-PC_console.exe"),
            Path(os.path.expandvars(r"%LOCALAPPDATA%\Programs\CraftOS-PC\CraftOS-PC_console.exe")),
            Path(os.path.expandvars(r"%LOCALAPPDATA%\CraftOS-PC\CraftOS-PC_console.exe")),
        ]
        exe_path = None
        for cand in candidates:
            if cand and cand.exists():
                exe_path = cand.resolve()
                break
        if not exe_path:
            raise FileNotFoundError(
                "CraftOS-PC_console.exe could not be located on the host. "
                "Ensure CraftOS-PC is installed or set CRAFTOS_PC_EXE."
            )

    override_rom = env_map.get("CRAFTOS_PC_ROM_DIR")
    if override_rom:
        rom_dir = Path(override_rom).resolve()
    else:
        rom_candidate = exe_path.parent / "rom"
        rom_dir = exe_path.parent if rom_candidate.exists() else exe_path.parent

    lua52_dll = exe_path.parent / "lua52.dll"
    if not lua52_dll.exists():
        lua52_dll = None

    return CraftOSPaths(craftos_exe=exe_path, rom_dir=rom_dir, lua52_dll=lua52_dll)


def discover_codebase_targets(
    workspace_root: Path, target_query: str | None = None
) -> list[UnitTargetConfig]:
    workspace_root = workspace_root.resolve()
    src_root = workspace_root / "src"
    tests_root = workspace_root / "tests"

    if not src_root.exists():
        return []

    targets: list[UnitTargetConfig] = []
    layer_pattern = re.compile(r"^\d+_")

    for layer_dir in sorted(src_root.iterdir()):
        if not layer_dir.is_dir() or not layer_pattern.match(layer_dir.name):
            continue
        for program_dir in sorted(layer_dir.iterdir()):
            if not program_dir.is_dir():
                continue

            target_id = f"{layer_dir.name}/{program_dir.name}"
            corresponding_tests = tests_root / layer_dir.name / program_dir.name

            has_src_lua = any(program_dir.rglob("*.lua"))
            has_test_lua = (
                any(corresponding_tests.rglob("test_*.lua"))
                if corresponding_tests.exists()
                else False
            )

            if not (has_src_lua or has_test_lua):
                continue

            unit_json = corresponding_tests / "unit.json"
            timeout_sec = 8.0
            abort_timeout_ms = 4000
            term_width = 51
            term_height = 19
            max_instructions = 50000
            peripherals = [PeripheralAttachment(side="top", peripheral_type="modem")]

            if unit_json.exists():
                try:
                    data = json.loads(unit_json.read_text(encoding="utf-8"))
                    timeout_sec = float(data.get("timeout_sec", timeout_sec))
                    abort_timeout_ms = int(data.get("abort_timeout_ms", abort_timeout_ms))
                    term_width = int(data.get("term_width", term_width))
                    term_height = int(data.get("term_height", term_height))
                    max_instructions = int(
                        data.get("max_instructions_per_tick", max_instructions)
                    )
                    if "peripherals" in data and isinstance(data["peripherals"], list):
                        peripherals = [
                            PeripheralAttachment(
                                side=p["side"],
                                peripheral_type=p["type"],
                                args=p.get("args", []),
                            )
                            for p in data["peripherals"]
                        ]
                except Exception:
                    pass

            targets.append(
                UnitTargetConfig(
                    target_id=target_id,
                    source_dir=program_dir,
                    tests_dir=corresponding_tests,
                    timeout_sec=timeout_sec,
                    abort_timeout_ms=abort_timeout_ms,
                    term_width=term_width,
                    term_height=term_height,
                    max_instructions_per_tick=max_instructions,
                    peripherals=peripherals,
                )
            )

    if target_query:
        query_norm = target_query.replace("\\", "/").strip().lower()
        matched = [
            t
            for t in targets
            if t.target_id.lower() == query_norm
            or t.target_id.split("/")[-1].lower() == query_norm
        ]
        if not matched:
            raise ValueError(f"No codebase target matched query: '{target_query}'")
        return matched

    return targets
