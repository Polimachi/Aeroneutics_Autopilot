"""
Ephemeral CraftOS-PC session lifecycle, mount/staging isolation, and process watchdog.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from .config import CraftOSPaths


@dataclass
class CraftOSSessionResult:
    session_id: str
    exit_code: int
    timed_out: bool
    duration_ms: float
    stdout_raw: str
    stderr_raw: str
    guest_result: dict[str, Any] | None = None


def _kill_pid_tree(pid: int) -> None:
    try:
        subprocess.run(
            ["taskkill", "/F", "/T", "/PID", str(pid)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
            check=False,
        )
    except Exception:
        pass


def _enumerate_windows_processes() -> list[dict[str, Any]]:
    ps_cmd = (
        "Get-CimInstance Win32_Process -Filter \"Name='CraftOS-PC_console.exe'\" | "
        "Select-Object ProcessId, CommandLine | ConvertTo-Json -Compress"
    )
    try:
        res = subprocess.run(
            ["powershell", "-NoProfile", "-Command", ps_cmd],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        out = res.stdout.strip()
        if not out:
            return []
        items = json.loads(out)
        if isinstance(items, dict):
            return [items]
        if isinstance(items, list):
            return items
    except Exception:
        pass
    return []


def clean_workspace_orphans(
    sessions_root: Path,
    max_age_sec: float = 0.0,
    process_enumerator: Callable[[], list[dict[str, Any]]] | None = None,
) -> dict[str, list[Any]]:
    sessions_root = sessions_root.resolve()
    killed_pids: list[int] = []
    removed_dirs: list[str] = []

    enumerator = process_enumerator or _enumerate_windows_processes
    procs = enumerator()
    sessions_root_str = str(sessions_root).lower().replace("\\", "/")

    for p in procs:
        cmdline = str(p.get("CommandLine") or "").lower().replace("\\", "/")
        if sessions_root_str in cmdline:
            pid = int(p.get("ProcessId") or 0)
            if pid > 0:
                _kill_pid_tree(pid)
                killed_pids.append(pid)

    if sessions_root.exists():
        now = time.time()
        for child in sessions_root.iterdir():
            if child.is_dir():
                try:
                    age = now - child.stat().st_mtime
                    if age >= max_age_sec:
                        shutil.rmtree(child, ignore_errors=True)
                        removed_dirs.append(child.name)
                except Exception:
                    pass

    return {
        "killed_pids": killed_pids,
        "removed_sessions": removed_dirs,
    }


def _build_global_config(abort_timeout_ms: int, term_width: int, term_height: int) -> dict[str, Any]:
    return {
        "abortTimeout": abort_timeout_ms,
        "checkUpdates": False,
        "cliControlKeyMode": 0,
        "clockSpeed": 20,
        "computerSpaceLimit": 20000000,
        "configReadOnly": False,
        "customCharScale": 0,
        "customFontPath": "",
        "customFontScale": 0,
        "defaultHeight": term_height,
        "defaultWidth": term_width,
        "default_computer_settings": "",
        "disable_lua51_features": False,
        "dropFilePath": False,
        "extendMargins": False,
        "http_blacklist": [],
        "http_enable": True,
        "http_max_download": 16777216,
        "http_max_requests": 16,
        "http_max_upload": 4194304,
        "http_max_websocket_message": 131072,
        "http_max_websockets": 4,
        "http_proxy_port": 0,
        "http_proxy_server": "",
        "http_timeout": 10000,
        "http_websocket_enabled": True,
        "http_whitelist": ["*"],
        "ignoreHotkeys": True,
        "initialComputer": 0,
        "keepOpenOnShutdown": False,
        "logErrors": True,
        "maxNotesPerTick": 8,
        "maxOpenPorts": 128,
        "maxRecordingTime": 15,
        "maximumFilesOpen": 128,
        "monitorsUseMouseEvents": False,
        "mount_mode": 1,
        "mounter_blacklist": [],
        "mounter_no_ask": ["*"],
        "mounter_whitelist": ["*"],
        "mouse_move_throttle": -1,
        "pluginData": {},
        "preferredHardwareDriver": "",
        "recordingFPS": 10,
        "romReadOnly": True,
        "serverMode": False,
        "showFPS": False,
        "showMountPrompt": False,
        "skipUpdate": "v2.8.3",
        "snapToSize": True,
        "snooperEnabled": False,
        "standardsMode": False,
        "useDFPWM": False,
        "useHardwareRenderer": False,
        "useVsync": False,
        "useWebP": False,
        "vanilla": False,
    }


class EphemeralCraftOSSession:
    def __init__(
        self,
        sessions_root: Path,
        craftos_paths: CraftOSPaths,
        prefix: str = "unit",
        abort_timeout_ms: int = 4000,
        term_width: int = 51,
        term_height: int = 19,
        keep_session: bool = False,
    ) -> None:
        self.sessions_root = sessions_root.resolve()
        self.craftos_paths = craftos_paths
        self.session_id = f"{prefix}_{int(time.time() * 1000)}_{uuid.uuid4().hex[:6]}"
        self.session_dir = self.sessions_root / self.session_id
        self.config_dir = self.session_dir / "config"
        self.computers_dir = self.session_dir / "computer"
        self.abort_timeout_ms = abort_timeout_ms
        self.term_width = term_width
        self.term_height = term_height
        self.keep_session = keep_session

    def __enter__(self) -> EphemeralCraftOSSession:
        self.config_dir.mkdir(parents=True, exist_ok=True)
        self.computers_dir.mkdir(parents=True, exist_ok=True)
        global_cfg = _build_global_config(
            abort_timeout_ms=self.abort_timeout_ms,
            term_width=self.term_width,
            term_height=self.term_height,
        )
        (self.config_dir / "global.json").write_text(
            json.dumps(global_cfg, indent=2), encoding="utf-8"
        )
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        if not self.keep_session and self.session_dir.exists():
            shutil.rmtree(self.session_dir, ignore_errors=True)

    def computer_dir(self, computer_id: int = 0) -> Path:
        cdir = self.computers_dir / str(computer_id)
        cdir.mkdir(parents=True, exist_ok=True)
        return cdir

    def stage_tree(
        self, src_dir: Path, computer_id: int = 0, dest_subdir: str = ""
    ) -> Path:
        target = self.computer_dir(computer_id)
        if dest_subdir:
            target = target / dest_subdir
            target.mkdir(parents=True, exist_ok=True)

        if src_dir.exists():
            for item in src_dir.rglob("*"):
                if item.is_file():
                    rel = item.relative_to(src_dir)
                    if any(
                        part.startswith(".runtime")
                        or part == "__pycache__"
                        or part.startswith(".git")
                        for part in rel.parts
                    ):
                        continue
                    out_file = target / rel
                    out_file.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(item, out_file)
        return target

    def run(self, mode: str = "headless", timeout_sec: float = 8.0) -> CraftOSSessionResult:
        exe = self.craftos_paths.craftos_exe
        if not exe.exists():
            raise FileNotFoundError(f"CraftOS-PC binary not found at {exe}")

        c0_out = self.computer_dir(0) / "_harness_out"
        c0_out.mkdir(parents=True, exist_ok=True)
        done_flag = c0_out / "done.flag"
        result_file = c0_out / "result.json"

        cmd = [
            str(exe),
            "--raw" if mode == "raw" else "--headless",
            "--rom",
            str(self.craftos_paths.rom_dir),
            "-d",
            str(self.session_dir),
        ]

        t0 = time.perf_counter()
        proc = subprocess.Popen(
            cmd,
            cwd=str(exe.parent),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )

        timed_out = False
        try:
            deadline = t0 + timeout_sec
            while time.perf_counter() < deadline:
                if done_flag.exists():
                    time.sleep(0.05)
                    break
                if proc.poll() is not None:
                    break
                time.sleep(0.025)
            else:
                timed_out = True
        finally:
            if proc.poll() is None:
                _kill_pid_tree(proc.pid)
            try:
                stdout_bytes, stderr_bytes = proc.communicate(timeout=1.5)
            except Exception:
                stdout_bytes, stderr_bytes = b"", b""

        duration_ms = (time.perf_counter() - t0) * 1000.0
        stdout_raw = stdout_bytes.decode("utf-8", errors="replace")
        stderr_raw = stderr_bytes.decode("utf-8", errors="replace")

        guest_result: dict[str, Any] | None = None
        if result_file.exists():
            try:
                guest_result = json.loads(result_file.read_text(encoding="utf-8", errors="replace"))
            except Exception as exc:
                guest_result = {
                    "parse_error": str(exc),
                    "raw": result_file.read_text(encoding="utf-8", errors="replace"),
                }

        return CraftOSSessionResult(
            session_id=self.session_id,
            exit_code=proc.returncode if proc.returncode is not None else -1,
            timed_out=timed_out,
            duration_ms=round(duration_ms, 2),
            stdout_raw=stdout_raw,
            stderr_raw=stderr_raw,
            guest_result=guest_result,
        )
