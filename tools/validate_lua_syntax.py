"""
Lua 5.2 syntax validation tool using CraftOS-PC lua52.dll.
Scans Lua source files and compiles each chunk with luaL_loadfilex.
"""
from __future__ import annotations

import ctypes
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


def find_lua52_dll() -> Path | None:
    # 1. Try importing harness.unit.config.resolve_craftos_paths
    try:
        from harness.unit.config import resolve_craftos_paths
        paths = resolve_craftos_paths()
        if paths.lua52_dll and paths.lua52_dll.exists():
            return paths.lua52_dll.resolve()
    except Exception:
        pass

    # 2. Check environment variable LUA52_DLL
    env_dll = os.environ.get("LUA52_DLL")
    if env_dll:
        p = Path(env_dll).resolve()
        if p.exists():
            return p

    # 3. Check fallback paths
    candidates = [
        Path(r"c:\Users\sjmik\Desktop\Antigravity_Workspace\Lua_Harness\bin\lua52.dll"),
        Path(r"C:\Program Files\CraftOS-PC\lua52.dll"),
        Path(r"C:\Program Files (x86)\CraftOS-PC\lua52.dll"),
        Path(os.path.expandvars(r"%LOCALAPPDATA%\Programs\CraftOS-PC\lua52.dll")),
        Path(os.path.expandvars(r"%LOCALAPPDATA%\CraftOS-PC\lua52.dll")),
    ]
    for cand in candidates:
        if cand and cand.exists():
            return cand.resolve()

    return None


def main() -> int:
    dll_path = find_lua52_dll()
    if dll_path is None:
        print("[ERROR] lua52.dll could not be located on the host.", file=sys.stderr)
        print("Please ensure CraftOS-PC is installed or set LUA52_DLL environment variable.", file=sys.stderr)
        return 2

    try:
        lua = ctypes.CDLL(str(dll_path))
    except Exception as e:
        print(f"[ERROR] Failed to load DLL from {dll_path}: {e}", file=sys.stderr)
        return 2

    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    lua.luaL_loadfilex.restype = ctypes.c_int
    if hasattr(lua, "lua_settop"):
        lua.lua_settop.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lua.lua_settop.restype = None
    if hasattr(lua, "lua_tolstring"):
        lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        lua.lua_tolstring.restype = ctypes.c_char_p
    lua.lua_close.argtypes = [ctypes.c_void_p]

    L = lua.luaL_newstate()
    if not L:
        print("[ERROR] Failed to initialize Lua state via luaL_newstate()", file=sys.stderr)
        return 2

    # Discover target files
    if len(sys.argv) > 1:
        target_files = [Path(p).resolve() for p in sys.argv[1:]]
    else:
        src_files = sorted(REPO_ROOT.glob("src/**/*.lua"))
        installer_file = [REPO_ROOT / "installer.lua"] if (REPO_ROOT / "installer.lua").exists() else []
        target_files = src_files + installer_file

    print("=== Lua 5.2 Syntax Validation ===")
    print(f"Loaded DLL: {dll_path}")
    print(f"Validating {len(target_files)} target file(s)...")

    failed_files: list[tuple[Path, str]] = []

    for fpath in target_files:
        if not fpath.exists():
            print(f"FAIL [Not found]: {fpath}")
            failed_files.append((fpath, "File not found"))
            continue

        ret = lua.luaL_loadfilex(L, str(fpath).encode("utf-8"), None)
        rel_label = fpath.relative_to(REPO_ROOT) if fpath.is_relative_to(REPO_ROOT) else fpath
        if ret == 0:
            print(f"PASS [Syntax OK]: {rel_label}")
        else:
            err_msg = ""
            if hasattr(lua, "lua_tolstring"):
                raw_err = lua.lua_tolstring(L, -1, None)
                if raw_err:
                    err_msg = raw_err.decode("utf-8", errors="replace")
            print(f"FAIL [Syntax Error code {ret}]: {rel_label} - {err_msg}")
            failed_files.append((fpath, err_msg or f"Error code {ret}"))

        if hasattr(lua, "lua_settop"):
            lua.lua_settop(L, 0)

    lua.lua_close(L)

    print("=" * 40)
    if not failed_files:
        print(f"All {len(target_files)} Lua files passed Lua 5.2 compilation successfully!")
        return 0
    else:
        print(f"Validation FAILED: {len(failed_files)} file(s) failed syntax check.")
        for fp, err in failed_files:
            print(f"  - {fp}: {err}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
