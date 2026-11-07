"""
Static guard verifying Lua 5.2 syntax, Lua 5.3+ prohibited operators, host OS API restrictions,
and Create: Aeronautics / Valkyrien Skies domain rules.
"""
from __future__ import annotations

import ctypes
import re
from dataclasses import dataclass
from pathlib import Path

from .config import CraftOSPaths, UnitTargetConfig


@dataclass
class StaticViolation:
    file_path: str
    line: int
    code: str
    message: str


class Lua52SyntaxChecker:
    def __init__(self, lua52_dll_path: Path | None) -> None:
        self.dll_path = lua52_dll_path
        self._dll: ctypes.CDLL | None = None
        if self.dll_path and self.dll_path.exists():
            try:
                self._dll = ctypes.CDLL(str(self.dll_path.resolve()))
                self._dll.luaL_newstate.restype = ctypes.c_void_p
                self._dll.luaL_newstate.argtypes = []
                self._dll.lua_close.restype = None
                self._dll.lua_close.argtypes = [ctypes.c_void_p]
                self._dll.lua_tolstring.restype = ctypes.c_char_p
                self._dll.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]

                if hasattr(self._dll, "luaL_loadbufferx"):
                    self._dll.luaL_loadbufferx.restype = ctypes.c_int
                    self._dll.luaL_loadbufferx.argtypes = [
                        ctypes.c_void_p,
                        ctypes.c_char_p,
                        ctypes.c_size_t,
                        ctypes.c_char_p,
                        ctypes.c_char_p,
                    ]
                elif hasattr(self._dll, "luaL_loadbuffer"):
                    self._dll.luaL_loadbuffer.restype = ctypes.c_int
                    self._dll.luaL_loadbuffer.argtypes = [
                        ctypes.c_void_p,
                        ctypes.c_char_p,
                        ctypes.c_size_t,
                        ctypes.c_char_p,
                    ]
            except Exception:
                self._dll = None

    def check_source(self, source: str, chunk_name: str) -> StaticViolation | None:
        if not self._dll:
            return None

        state = self._dll.luaL_newstate()
        if not state:
            return None

        try:
            src_bytes = source.encode("utf-8")
            name_bytes = chunk_name.encode("utf-8")
            if hasattr(self._dll, "luaL_loadbufferx"):
                status = self._dll.luaL_loadbufferx(
                    state, src_bytes, len(src_bytes), name_bytes, b"t"
                )
            else:
                status = self._dll.luaL_loadbuffer(
                    state, src_bytes, len(src_bytes), name_bytes
                )

            if status != 0:
                raw_err = self._dll.lua_tolstring(state, -1, None)
                err_str = raw_err.decode("utf-8", errors="replace") if raw_err else "Syntax error"
                line_no = 1
                m = re.search(r":(\d+):", err_str)
                if m:
                    line_no = int(m.group(1))
                return StaticViolation(
                    file_path=chunk_name,
                    line=line_no,
                    code="LUA52_SYNTAX_ERROR",
                    message=err_str,
                )
        finally:
            self._dll.lua_close(state)

        return None


def strip_lua_comments_and_strings(
    source: str,
) -> tuple[str, list[tuple[int, str]]]:
    """
    Strips comments and string literals, replacing non-newline characters with spaces
    to preserve 1-to-1 line numbers for operator and keyword scanning.
    Also extracts string literals with their originating line number.
    """
    n = len(source)
    out: list[str] = []
    literals: list[tuple[int, str]] = []
    i = 0
    line = 1

    while i < n:
        c = source[i]
        c2 = source[i : i + 2]

        if c == "\n":
            line += 1
            out.append(c)
            i += 1
            continue

        # Single-line or multi-line comment: --
        if c2 == "--":
            start_line = line
            i += 2
            # Check long comment bracket: --[(=*)[
            long_match = re.match(r"^\[(=*)\[", source[i:])
            if long_match:
                eqs = long_match.group(1)
                closer = f"]{eqs}]"
                i += len(long_match.group(0))
                closer_idx = source.find(closer, i)
                if closer_idx == -1:
                    closer_idx = n
                else:
                    closer_idx += len(closer)
                comment_body = source[i - len(long_match.group(0)) - 2 : closer_idx]
                for ch in comment_body:
                    if ch == "\n":
                        line += 1
                        out.append("\n")
                    else:
                        out.append(" ")
                i = closer_idx
            else:
                out.extend([" ", " "])
                while i < n and source[i] != "\n":
                    out.append(" ")
                    i += 1
            continue

        # Long string literal: [(=*)[
        long_str_match = re.match(r"^\[(=*)\[", source[i:])
        if long_str_match:
            start_line = line
            eqs = long_str_match.group(1)
            closer = f"]{eqs}]"
            content_start = i + len(long_str_match.group(0))
            closer_idx = source.find(closer, content_start)
            if closer_idx == -1:
                content_end = n
                closer_idx = n
            else:
                content_end = closer_idx
                closer_idx += len(closer)

            extracted = source[content_start:content_end]
            literals.append((start_line, extracted))

            raw_span = source[i:closer_idx]
            for ch in raw_span:
                if ch == "\n":
                    line += 1
                    out.append("\n")
                else:
                    out.append(" ")
            i = closer_idx
            continue

        # Quoted string literal: ' or "
        if c in ("'", '"'):
            start_line = line
            delim = c
            out.append(" ")
            i += 1
            extracted_chars: list[str] = []
            while i < n:
                cur = source[i]
                if cur == "\n":
                    line += 1
                    out.append("\n")
                    i += 1
                    break
                if cur == "\\":
                    extracted_chars.append(cur)
                    out.append(" ")
                    i += 1
                    if i < n:
                        if source[i] == "\n":
                            line += 1
                            out.append("\n")
                        else:
                            extracted_chars.append(source[i])
                            out.append(" ")
                        i += 1
                    continue
                if cur == delim:
                    out.append(" ")
                    i += 1
                    break
                extracted_chars.append(cur)
                out.append(" ")
                i += 1
            literals.append((start_line, "".join(extracted_chars)))
            continue

        out.append(c)
        i += 1

    return "".join(out), literals


# Prohibited Valkyrien Skies identifiers per .agent/rules/domain-aeronautics.md
PROHIBITED_MOD_TOKENS = (
    "valkyrien",
    "valkyrienskies",
    "vs2",
    "cc_vs",
    "vs_computers",
    "valkyriencomputers",
    "ship_api",
    "extendedshipapi",
    "ship_reader",
    "vs_clockwork",
    "eureka",
    "trackwork",
    "vs_tournament",
    "vs_addition",
    "create_interactive",
    "vmod",
    "drivebywire",
    "kontraption:",
)

CC_VS_SHIP_METHODS = (
    "getWorldspacePosition",
    "getShipyardPosition",
    "getMomentOfInertiaTensor",
    "applyInvariantForce",
    "applyInvariantTorque",
    "applyRotDependentForce",
    "applyRotDependentTorque",
    "getQuaternion",
    "getOmega",
    "getSlug",
    "setSlug",
    "isStatic",
    "setStatic",
    "getScale",
    "getTransformationMatrix",
)


def scan_lua_source(
    source: str, rel_path: str, syntax_checker: Lua52SyntaxChecker | None = None
) -> list[StaticViolation]:
    violations: list[StaticViolation] = []

    # 1. Native Lua 5.2 DLL syntax check
    if syntax_checker:
        syntax_err = syntax_checker.check_source(source, rel_path)
        if syntax_err:
            violations.append(syntax_err)

    stripped_code, literals = strip_lua_comments_and_strings(source)
    lines = stripped_code.split("\n")

    # 2. Lua 5.3+ operators (scanned on stripped code)
    for idx, l in enumerate(lines, 1):
        # Integer division //
        if "//" in l:
            violations.append(
                StaticViolation(
                    file_path=rel_path,
                    line=idx,
                    code="LUA53_OPERATOR",
                    message="Lua 5.3+ integer division operator '//' is forbidden in CC:Tweaked Lua 5.2",
                )
            )
        # Bitwise shift << or >>
        if "<<" in l or ">>" in l:
            violations.append(
                StaticViolation(
                    file_path=rel_path,
                    line=idx,
                    code="LUA53_OPERATOR",
                    message="Lua 5.3+ bitwise shift operator ('<<' or '>>') is forbidden in Lua 5.2; use bit32",
                )
            )
        # Bitwise &
        if "&" in l:
            violations.append(
                StaticViolation(
                    file_path=rel_path,
                    line=idx,
                    code="LUA53_OPERATOR",
                    message="Lua 5.3+ bitwise operator '&' is forbidden in Lua 5.2; use bit32.band",
                )
            )
        # Bitwise |
        if "|" in l:
            violations.append(
                StaticViolation(
                    file_path=rel_path,
                    line=idx,
                    code="LUA53_OPERATOR",
                    message="Lua 5.3+ bitwise operator '|' is forbidden in Lua 5.2; use bit32.bor",
                )
            )
        # Bitwise ~ (excluding ~= inequality)
        tilde_matches = re.finditer(r"~(?!=)", l)
        for _ in tilde_matches:
            violations.append(
                StaticViolation(
                    file_path=rel_path,
                    line=idx,
                    code="LUA53_OPERATOR",
                    message="Lua 5.3+ bitwise operator '~' is forbidden in Lua 5.2; use bit32.bxor/bnot",
                )
            )

        # 3. Host OS API checks
        if re.search(r"\bos\s*\.\s*(?:execute|remove|rename|exit)\b", l):
            violations.append(
                StaticViolation(
                    file_path=rel_path,
                    line=idx,
                    code="PROHIBITED_HOST_OS_API",
                    message="Host OS API (os.execute/remove/rename/exit) is disabled in CraftOS; use fs.*",
                )
            )
        if re.search(r"\bio\s*\.\s*popen\b", l):
            violations.append(
                StaticViolation(
                    file_path=rel_path,
                    line=idx,
                    code="PROHIBITED_HOST_OS_API",
                    message="Host OS API io.popen is disabled in CraftOS",
                )
            )
        if re.search(r"\b(?:getfenv|setfenv)\b", l):
            violations.append(
                StaticViolation(
                    file_path=rel_path,
                    line=idx,
                    code="PROHIBITED_LUA51_ENV_API",
                    message="getfenv/setfenv is deprecated/disabled in Lua 5.2; use _ENV",
                )
            )

        # 4. CC:VS ship methods on stripped code
        method_pattern = r"\bship\s*\.\s*(" + "|".join(CC_VS_SHIP_METHODS) + r")\b"
        m_ship = re.search(method_pattern, l)
        if m_ship:
            violations.append(
                StaticViolation(
                    file_path=rel_path,
                    line=idx,
                    code="PROHIBITED_MOD_VIOLATION",
                    message=f"Valkyrien Skies CC:VS ship physics method 'ship.{m_ship.group(1)}()' is prohibited",
                )
            )

        # Prohibited token in stripped code identifiers (e.g. require("vs2.ship"))
        for tok in PROHIBITED_MOD_TOKENS:
            if tok in l.lower():
                violations.append(
                    StaticViolation(
                        file_path=rel_path,
                        line=idx,
                        code="PROHIBITED_MOD_VIOLATION",
                        message=f"Valkyrien Skies prohibited mod token '{tok}' detected",
                    )
                )

    # 5. String literal inspection for prohibited peripheral / mod names
    for line_no, lit in literals:
        lit_lower = lit.lower()
        # peripheral.find("ship") / peripheral.wrap("ship")
        if lit_lower.strip() == "ship":
            violations.append(
                StaticViolation(
                    file_path=rel_path,
                    line=line_no,
                    code="PROHIBITED_MOD_VIOLATION",
                    message="Valkyrien Skies peripheral identifier 'ship' is prohibited",
                )
            )
        for tok in PROHIBITED_MOD_TOKENS:
            if tok in lit_lower:
                violations.append(
                    StaticViolation(
                        file_path=rel_path,
                        line=line_no,
                        code="PROHIBITED_MOD_VIOLATION",
                        message=f"Valkyrien Skies prohibited mod identifier '{tok}' detected in literal",
                    )
                )

    # Deduplicate violations by (file_path, line, code)
    dedup: dict[tuple[str, int, str], StaticViolation] = {}
    for v in violations:
        key = (v.file_path, v.line, v.code)
        if key not in dedup:
            dedup[key] = v

    return sorted(dedup.values(), key=lambda v: (v.line, v.code))


def scan_target_files(
    target: UnitTargetConfig, craftos_paths: CraftOSPaths
) -> list[StaticViolation]:
    checker = Lua52SyntaxChecker(craftos_paths.lua52_dll)
    all_violations: list[StaticViolation] = []

    scan_dirs = [target.source_dir]
    if target.tests_dir.exists():
        scan_dirs.append(target.tests_dir)

    for base_dir in scan_dirs:
        for f in sorted(base_dir.rglob("*.lua")):
            try:
                rel = str(f.relative_to(target.source_dir.parent.parent.parent))
            except Exception:
                rel = str(f)
            src = f.read_text(encoding="utf-8", errors="replace")
            violations = scan_lua_source(src, rel, checker)
            all_violations.extend(violations)

    return all_violations
