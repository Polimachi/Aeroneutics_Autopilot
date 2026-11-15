"""
Runtime wiring verifier for Create_Aeroneutics.
Verifies static reachability, orphan modules, broken requires,
package path safety, and dead imports across subsystem main.lua trees.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from harness.unit.static_guard import strip_lua_comments_and_strings

# SSOT for known architectural exemptions with traceable justification:
# Format: (relative_posix_path, violation_code): rationale
KNOWN_EXEMPTIONS: dict[tuple[str, str], str] = {
    (
        "src/1_control/vas/modules/vec3.lua",
        "ORPHAN_MODULE",
    ): (
        "Audit Report 1 Q7 decision: vec3.lua retained as standalone 3D vector math utility "
        "for future VAS expansions; verified by tests/1_control/vas/test_vec3.lua."
    ),
    (
        "src/0_infra/gac/config.lua",
        "ORPHAN_MODULE",
    ): (
        "Deployed directly to /config.lua root per installer manifest.lua; "
        "serves as standalone default configuration specification script."
    ),
    (
        "src/0_infra/landing_pad/config.lua",
        "ORPHAN_MODULE",
    ): (
        "Deployed directly to /config.lua root per installer manifest.lua; "
        "serves as standalone default configuration specification script."
    ),
    (
        "src/0_infra/landing_pad/main.lua",
        "DEAD_IMPORT",
    ): (
        "setup_wizard imported in landing_pad main daemon for commissioning setup wizard; "
        "verified by tests/0_infra/landing_pad/test_setup_and_tui.lua."
    ),
}

# Standard ComputerCraft & environment modules that do not reside in subsystem
IGNORED_REQUIRE_TARGETS: frozenset[str] = frozenset({
    "avionics_sensors",
    "/lib/avionics_sensors",
    "/lib/avionics_sensors.lua",
    "ota_agent",
    "/lib/ota_agent",
    "/lib/ota_agent.lua",
    "cc.require",
    "cc.expect",
    "cc.strings",
    "cc.pretty",
    "cc.image",
    "cc.completion",
})

# Patterns matching target references
REQUIRE_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r'\brequire\s*\(\s*["\']([^"\']+)["\']\s*\)'),
    re.compile(r'\brequire\s+["\']([^"\']+)["\']'),
    re.compile(r'\bpcall\s*\(\s*require\s*,\s*["\']([^"\']+)["\']'),
    re.compile(r'\bdofile\s*\(\s*["\']([^"\']+)["\']\s*\)'),
    re.compile(r'\bloadfile\s*\(\s*["\']([^"\']+)["\']'),
    re.compile(r'\bshell\.run\s*\(\s*["\']([^"\']+)["\']'),
)

LOCAL_REQUIRE_BINDING_PATTERN: re.Pattern[str] = re.compile(
    r'^\s*local\s+([a-zA-Z0-9_]+)\s*=\s*(?:pcall\s*\(\s*)?require\b'
)


@dataclass
class WiringViolation:
    file_path: str
    line: int
    code: str
    message: str
    subsystem: str


def strip_lua_comments_preserving_strings(source: str) -> str:
    """
    Replaces comments with spaces to preserve line numbers and character alignment,
    while leaving string literals intact for target extraction.
    """
    n = len(source)
    out: list[str] = []
    i = 0
    in_single = False
    in_double = False

    while i < n:
        c = source[i]
        c2 = source[i : i + 2] if i + 1 < n else ""

        if c == '"' and not in_single:
            in_double = not in_double
            out.append(c)
            i += 1
            continue

        if c == "'" and not in_double:
            in_single = not in_single
            out.append(c)
            i += 1
            continue

        if c == "\\" and (in_single or in_double):
            out.append(c)
            i += 1
            if i < n:
                out.append(source[i])
                i += 1
            continue

        if not in_single and not in_double and c2 == "--":
            i += 2
            out.extend([" ", " "])
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
                    out.append("\n" if ch == "\n" else " ")
                i = closer_idx
            else:
                while i < n and source[i] != "\n":
                    out.append(" ")
                    i += 1
            continue

        out.append(c)
        i += 1

    return "".join(out)


def resolve_require_target(
    subsystem_dir: Path,
    from_file: Path,
    target: str,
    repo_root: Path,
) -> Path | None:
    """
    Resolves a require target relative to subsystem roots (root, modules/, hal/, tools/).
    Returns resolved Path if found within the subsystem or repo, else None.
    """
    if target in IGNORED_REQUIRE_TARGETS or target.startswith("/rom/") or target.startswith("rom/"):
        return Path("/lib/avionics_sensors.lua")

    clean = target[:-4] if target.endswith(".lua") else target
    path_var = clean.replace(".", "/")

    candidates: list[Path] = [
        subsystem_dir / f"{path_var}.lua",
        subsystem_dir / f"{clean}.lua",
        subsystem_dir / "modules" / f"{path_var}.lua",
        subsystem_dir / "modules" / f"{clean}.lua",
        subsystem_dir / "hal" / f"{path_var}.lua",
        subsystem_dir / "hal" / f"{clean}.lua",
        subsystem_dir / "tools" / f"{path_var}.lua",
        subsystem_dir / "tools" / f"{clean}.lua",
        from_file.parent / f"{path_var}.lua",
        from_file.parent / f"{clean}.lua",
    ]

    if target.endswith(".lua"):
        candidates.extend([
            subsystem_dir / target,
            from_file.parent / target,
            subsystem_dir / "modules" / target,
            subsystem_dir / "hal" / target,
            subsystem_dir / "tools" / target,
        ])

    if target.startswith("src/"):
        candidates.append(repo_root / target)
        candidates.append(repo_root / f"{target}.lua")

    for candidate in candidates:
        if candidate.exists() and candidate.is_file():
            return candidate.resolve()

    return None


def extract_targets_from_file(file_path: Path) -> list[tuple[int, str, str]]:
    """
    Extracts require, dofile, loadfile, and shell.run targets with their line numbers.
    Returns list of (line_no, target_string, raw_line).
    """
    try:
        raw = file_path.read_text(encoding="utf-8")
    except Exception:
        return []

    stripped = strip_lua_comments_preserving_strings(raw)
    results: list[tuple[int, str, str]] = []

    for line_idx, line in enumerate(stripped.splitlines(), 1):
        # Ignore calls guarded by explicit runtime existence checks
        if "fs.exists" in line or "fsObj.exists" in line:
            continue

        for pattern in REQUIRE_PATTERNS:
            for match in pattern.finditer(line):
                results.append((line_idx, match.group(1), line.strip()))

    return results


def check_dead_imports_in_main(main_file: Path, subsystem_name: str) -> list[WiringViolation]:
    """
    Checks for `local <var> = require(...)` bindings in main.lua that are never
    referenced anywhere else in main.lua outside comments and strings.
    """
    try:
        raw = main_file.read_text(encoding="utf-8")
    except Exception:
        return []

    stripped_code, _ = strip_lua_comments_and_strings(raw)
    code_lines = stripped_code.splitlines()
    raw_lines = raw.splitlines()
    violations: list[WiringViolation] = []

    for line_idx, raw_line in enumerate(raw_lines, 1):
        m = LOCAL_REQUIRE_BINDING_PATTERN.match(raw_line)
        if not m:
            continue

        var_name = m.group(1)
        if var_name == "_":
            continue

        usage_rx = re.compile(r"\b" + re.escape(var_name) + r"\b")
        used = False

        for other_idx, code_line in enumerate(code_lines, 1):
            if other_idx == line_idx:
                continue
            if usage_rx.search(code_line):
                used = True
                break

        if not used:
            violations.append(
                WiringViolation(
                    file_path=str(main_file),
                    line=line_idx,
                    code="DEAD_IMPORT",
                    message=f"Variable '{var_name}' is imported via require() but never used in {main_file.name}",
                    subsystem=subsystem_name,
                )
            )

    return violations


def analyze_subsystem_wiring(
    subsystem_dir: Path,
    repo_root: Path,
    startup_injects_modules: bool = True,
    strict: bool = False,
) -> list[WiringViolation]:
    """
    Performs BFS reachability, broken require detection, orphan module detection,
    package.path safety checks, and dead import analysis for a single subsystem.
    """
    main_file = subsystem_dir / "main.lua"
    if not main_file.exists():
        return []

    try:
        subsystem_name = subsystem_dir.relative_to(repo_root / "src").as_posix()
    except ValueError:
        subsystem_name = subsystem_dir.name

    violations: list[WiringViolation] = []
    main_raw = main_file.read_text(encoding="utf-8")
    main_modifies_package_path = bool(
        re.search(r"package\.path\s*=\s*.*modules", main_raw, re.IGNORECASE)
    )

    all_subsystem_lua: set[Path] = set()
    for lua_path in subsystem_dir.rglob("*.lua"):
        # Exclude node simulation harnesses and tests
        if lua_path.name.startswith("node_"):
            continue
        if "tests" in lua_path.parts:
            continue
        all_subsystem_lua.add(lua_path.resolve())

    # BFS reachability
    visited: set[Path] = {main_file.resolve()}
    queue: list[Path] = [main_file.resolve()]

    while queue:
        cur_file = queue.pop(0)
        targets = extract_targets_from_file(cur_file)

        for line_no, target_str, raw_line in targets:
            resolved = resolve_require_target(subsystem_dir, cur_file, target_str, repo_root)

            if resolved is None:
                violations.append(
                    WiringViolation(
                        file_path=str(cur_file),
                        line=line_no,
                        code="BROKEN_REQUIRE",
                        message=f"Target module '{target_str}' could not be resolved to any file in {subsystem_name}",
                        subsystem=subsystem_name,
                    )
                )
            else:
                # Check package.path safety on bare requires in main.lua
                if (
                    cur_file == main_file.resolve()
                    and not startup_injects_modules
                    and not main_modifies_package_path
                ):
                    is_bare = "." not in target_str and "/" not in target_str
                    in_modules = (subsystem_dir / "modules" / f"{target_str}.lua").resolve() == resolved
                    at_root = (subsystem_dir / f"{target_str}.lua").resolve() == resolved
                    if is_bare and in_modules and not at_root:
                        violations.append(
                            WiringViolation(
                                file_path=str(cur_file),
                                line=line_no,
                                code="MISSING_PACKAGE_PATH",
                                message=(
                                    f"Bare require('{target_str}') resolves inside modules/ but "
                                    f"main.lua does not configure package.path and startup injection is disabled"
                                ),
                                subsystem=subsystem_name,
                            )
                        )

                if resolved in all_subsystem_lua and resolved not in visited:
                    visited.add(resolved)
                    queue.append(resolved)

        # Installer BOOTSTRAP_FILES reachability
        if "installer" in subsystem_name:
            cur_raw = cur_file.read_text(encoding="utf-8")
            for bf in re.findall(r'repoPath\s*=\s*["\']([^"\']+)["\']', cur_raw):
                resolved_bf = (repo_root / bf).resolve()
                if resolved_bf.exists() and resolved_bf in all_subsystem_lua and resolved_bf not in visited:
                    visited.add(resolved_bf)
                    queue.append(resolved_bf)

    # Orphan module detection
    unreachable = all_subsystem_lua - visited
    for orphan in sorted(unreachable):
        violations.append(
            WiringViolation(
                file_path=str(orphan),
                line=1,
                code="ORPHAN_MODULE",
                message=f"Module '{orphan.name}' is unreachable from {main_file.name}",
                subsystem=subsystem_name,
            )
        )

    # Dead import detection in main.lua
    dead_import_violations = check_dead_imports_in_main(main_file, subsystem_name)
    violations.extend(dead_import_violations)

    # Exemption filtering
    filtered_violations: list[WiringViolation] = []
    for v in violations:
        try:
            rel_path = Path(v.file_path).resolve().relative_to(repo_root.resolve()).as_posix()
        except ValueError:
            rel_path = Path(v.file_path).as_posix()

        exemption_key = (rel_path, v.code)
        if not strict and exemption_key in KNOWN_EXEMPTIONS:
            continue
        filtered_violations.append(v)

    return filtered_violations


def load_deferred_subsystems(repo_root: Path) -> list[str]:
    """Loads deferred subsystems from config/protocol_contracts.json if available."""
    contracts_path = repo_root / "config" / "protocol_contracts.json"
    if contracts_path.exists():
        try:
            data = json.loads(contracts_path.read_text(encoding="utf-8"))
            deferred = data.get("deferredSubsystems")
            if isinstance(deferred, list):
                return [str(p) for p in deferred]
        except Exception:
            pass
    return ["src/1_control/asa"]


def verify_all_wiring(
    repo_root: Path,
    include_deferred: bool = False,
    strict: bool = False,
) -> list[WiringViolation]:
    """
    Scans all subsystems under src/ with main.lua and aggregates wiring violations.
    Excludes deferred subsystems (e.g. src/1_control/asa) unless include_deferred=True.
    """
    src_dir = repo_root / "src"
    if not src_dir.is_dir():
        return []

    deferred_paths = load_deferred_subsystems(repo_root)
    all_violations: list[WiringViolation] = []

    for main_path in sorted(src_dir.rglob("main.lua")):
        sub_dir = main_path.parent
        rel_sub = sub_dir.relative_to(repo_root).as_posix()

        is_deferred = any(
            rel_sub == dp or rel_sub.startswith(f"{dp}/") or f"/{dp}/" in f"/{rel_sub}/"
            for dp in deferred_paths
        )

        if is_deferred and not include_deferred:
            continue

        violations = analyze_subsystem_wiring(
            subsystem_dir=sub_dir,
            repo_root=repo_root,
            startup_injects_modules=True,
            strict=strict,
        )
        all_violations.extend(violations)

    return all_violations


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify static runtime wiring, broken requires, orphan modules, and dead imports."
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=REPO_ROOT,
        help="Path to repository root",
    )
    parser.add_argument(
        "--include-deferred",
        action="store_true",
        help="Include deferred subsystems (e.g. src/1_control/asa)",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Do not filter known exemptions; treat all as errors",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output violations and summary in JSON format",
    )

    args = parser.parse_args()
    root = args.repo_root.resolve()

    violations = verify_all_wiring(
        repo_root=root,
        include_deferred=args.include_deferred,
        strict=args.strict,
    )

    # Collect acknowledged exemptions
    exemptions_output: list[dict[str, str]] = []
    if not args.strict:
        for (rel_path, code), rationale in sorted(KNOWN_EXEMPTIONS.items()):
            full_path = root / rel_path
            if full_path.exists():
                exemptions_output.append({
                    "file_path": rel_path,
                    "code": code,
                    "rationale": rationale,
                })

    subsystems_scanned = len(list((root / "src").rglob("main.lua")))
    if not args.include_deferred:
        deferred_paths = load_deferred_subsystems(root)
        subsystems_scanned -= sum(
            1 for p in (root / "src").rglob("main.lua")
            if any(dp in p.as_posix() for dp in deferred_paths)
        )

    if args.json:
        output_data = {
            "violations": [asdict(v) for v in violations],
            "exemptions": exemptions_output,
            "summary": {
                "total_violations": len(violations),
                "total_exemptions": len(exemptions_output),
                "subsystems_scanned": subsystems_scanned,
            },
        }
        print(json.dumps(output_data, indent=2))
    else:
        if exemptions_output:
            print(f"=== Acknowledged Known Exemptions ({len(exemptions_output)}) ===")
            for ex in exemptions_output:
                print(f"  [EXEMPTION] {ex['file_path']}: {ex['code']}")
                print(f"    Rationale: {ex['rationale']}")
            print()

        if violations:
            print(f"=== Wiring Violations Found ({len(violations)}) ===")
            for v in violations:
                print(f"  {v.file_path}:{v.line}: [{v.subsystem}] {v.code}: {v.message}")
            print(f"\nResult: FAILED ({len(violations)} violations across {subsystems_scanned} subsystems)")
        else:
            print(f"Runtime Wiring Verification: PASS (0 violations, {len(exemptions_output)} known exemptions acknowledged across {subsystems_scanned} subsystems)")

    return 0 if len(violations) == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
