"""
Protocol contracts SSOT loader and cross-subsystem verification tool.
Cross-checks specifications, static Lua/JSON code, and E2E captured packets
against config/protocol_contracts.json.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from harness.unit.static_guard import strip_lua_comments_and_strings
from tools.verify_spec_status import TARGET_APPROVED, TARGET_IMPLEMENTED

DEFAULT_CONTRACTS_PATH = REPO_ROOT / "config" / "protocol_contracts.json"

REQUIRED_TOP_LEVEL_KEYS: tuple[str, ...] = (
    "schemaVersion",
    "envelope",
    "channels",
    "interfaces",
    "missionSchema",
    "deferredSubsystems",
)

REQUIRED_ENVELOPE_KEYS: tuple[str, ...] = (
    "ver",
    "requiredKeys",
)

REQUIRED_CHANNEL_SECTIONS: tuple[str, ...] = (
    "aircraft",
    "hangar",
    "global",
)

REQUIRED_INTERFACE_KEYS: tuple[str, ...] = (
    "id",
    "name",
    "specs",
    "packets",
)

REQUIRED_MISSION_SCHEMA_KEYS: tuple[str, ...] = (
    "version",
    "activeActions",
    "activeDecorators",
    "activeMacros",
    "conditionTypes",
)

DEPRECATION_MARKERS: tuple[str, ...] = (
    "[DEPRECATED]",
    "DEPRECATED",
    "deprecated",
    "구 ",
    "구형",
    "기존 ",
)

LEGACY_SURFACE_KEYS: tuple[str, ...] = (
    "elevator",
    "leftAileron",
    "rightAileron",
    "rudder",
)

LEGACY_CONFIG_KEYS: tuple[str, ...] = (
    "surfaceMix",
    "aeroEnvelope",
    "navStaleEpochMs",
)

DUAL_KEY_FALLBACK_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"\b([a-zA-Z_][a-zA-Z0-9_]*)\s*\.\s*([a-zA-Z_][a-zA-Z0-9_]*)\s+or\s+\1\s*\.\s*([a-zA-Z_][a-zA-Z0-9_]*)\b"),
    re.compile(r"\b([a-zA-Z_][a-zA-Z0-9_]*)\[['\"]([a-zA-Z0-9_]+)['\"]\]\s+or\s+\1\[['\"]([a-zA-Z0-9_]+)['\"]\]"),
)


def load_contracts(contracts_path: Path) -> dict[str, Any]:
    """
    Load and structurally validate the protocol contracts SSOT JSON file.

    Raises:
        FileNotFoundError: If contracts_path does not exist.
        ValueError: If the file is not valid JSON or lacks required schema keys.
    """
    contracts_file = Path(contracts_path).resolve()
    if not contracts_file.is_file():
        raise FileNotFoundError(f"Contracts file not found: {contracts_file}")

    try:
        data = json.loads(contracts_file.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"Malformed JSON in {contracts_file}: {exc}") from exc

    if not isinstance(data, dict):
        raise ValueError(f"Top-level contracts object must be a dictionary, got {type(data).__name__}")

    # Top-level required keys
    for key in REQUIRED_TOP_LEVEL_KEYS:
        if key not in data:
            raise ValueError(f"Missing required top-level key '{key}' in {contracts_file}")

    # Envelope validation
    envelope = data.get("envelope")
    if not isinstance(envelope, dict):
        raise ValueError("Field 'envelope' must be a dictionary")
    for ek in REQUIRED_ENVELOPE_KEYS:
        if ek not in envelope:
            raise ValueError(f"Missing required envelope field '{ek}' in contracts")
    if not isinstance(envelope.get("requiredKeys"), list):
        raise ValueError("Field 'envelope.requiredKeys' must be a list")

    # Channels validation
    channels = data.get("channels")
    if not isinstance(channels, dict):
        raise ValueError("Field 'channels' must be a dictionary")
    for ck in REQUIRED_CHANNEL_SECTIONS:
        if ck not in channels or not isinstance(channels[ck], dict):
            raise ValueError(f"Missing or invalid channels section '{ck}' in contracts")

    # Interfaces validation
    interfaces = data.get("interfaces")
    if not isinstance(interfaces, list) or len(interfaces) == 0:
        raise ValueError("Field 'interfaces' must be a non-empty list")

    seen_interface_ids: set[str] = set()
    for idx, iface in enumerate(interfaces):
        if not isinstance(iface, dict):
            raise ValueError(f"Interface at index {idx} must be a dictionary")
        for ik in REQUIRED_INTERFACE_KEYS:
            if ik not in iface:
                raise ValueError(f"Interface at index {idx} missing required key '{ik}'")
        iface_id = iface["id"]
        if iface_id in seen_interface_ids:
            raise ValueError(f"Duplicate interface id '{iface_id}' at index {idx}")
        seen_interface_ids.add(iface_id)

        if not isinstance(iface["specs"], list):
            raise ValueError(f"Interface '{iface_id}' field 'specs' must be a list")
        if not isinstance(iface["packets"], dict):
            raise ValueError(f"Interface '{iface_id}' field 'packets' must be a dict")

    # Mission schema validation
    m_schema = data.get("missionSchema")
    if not isinstance(m_schema, dict):
        raise ValueError("Field 'missionSchema' must be a dictionary")
    for mk in REQUIRED_MISSION_SCHEMA_KEYS:
        if mk not in m_schema:
            raise ValueError(f"Missing required missionSchema key '{mk}' in contracts")
    for list_key in ("activeActions", "activeDecorators", "activeMacros", "conditionTypes"):
        if not isinstance(m_schema.get(list_key), list):
            raise ValueError(f"Field 'missionSchema.{list_key}' must be a list")

    # Deferred subsystems validation
    deferred = data.get("deferredSubsystems")
    if not isinstance(deferred, list):
        raise ValueError("Field 'deferredSubsystems' must be a list")

    return data


def strip_revision_history(markdown: str) -> str:
    """
    Replace lines inside '### Revision History' section with empty lines
    to preserve 1-to-1 line numbers while ignoring past change logs.
    Section ends at the next line starting with '---' or '## ' or end of file.
    """
    lines = markdown.splitlines()
    out: list[str] = []
    in_rev = False
    for line in lines:
        stripped_l = line.strip()
        if stripped_l.lower().startswith("### revision history"):
            in_rev = True
            out.append("")
            continue
        if in_rev:
            if (
                stripped_l.startswith("---")
                or stripped_l.startswith("## ")
                or (stripped_l.startswith("### ") and not stripped_l.lower().startswith("### revision history"))
            ):
                in_rev = False
                out.append(line)
            else:
                out.append("")
        else:
            out.append(line)
    return "\n".join(out)


def _collect_deprecated_spec_tokens(contracts: dict[str, Any]) -> set[str]:
    """Collect unambiguous deprecated token names that must not appear in specs without annotation."""
    tokens: set[str] = set()
    for iface in contracts.get("interfaces", []):
        tokens.update(iface.get("deprecatedPacketTypes", []))
        tokens.update(iface.get("deprecatedModes", []))
        # Add unambiguous deprecated payload keys (excluding generic English words like 'mode', 'phase', 'heave')
        for k in iface.get("deprecatedPayloadKeys", []):
            if k not in ("mode", "phase", "heave", "newBase", "API_NOMINAL", "API_TOTAL_LOSS"):
                tokens.add(k)
    # Channel offsets
    tokens.update({"Base+6", "Base+7", "base+6", "base+7"})
    return tokens


def verify_specs_against_contracts(
    repo_root: Path,
    contracts: dict[str, Any],
    spec_paths: list[str] | None = None,
) -> list[str]:
    """
    Cross-checks active specifications against protocol_contracts.json SSOT:
    1. Verifies no unannotated deprecated tokens appear in active spec bodies.
    2. Verifies all canonical packet types required for each spec are present.
    3. Verifies Master ICD and Diagram cover all interfaces.
    """
    root = Path(repo_root).resolve()
    if spec_paths is None:
        target_specs = list(TARGET_IMPLEMENTED) + list(TARGET_APPROVED)
    else:
        target_specs = list(spec_paths)

    errors: list[str] = []
    deprecated_tokens = _collect_deprecated_spec_tokens(contracts)
    master_icd_rel = "docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md"
    diagram_rel = "docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md"

    for rel_path in target_specs:
        spec_file = root / rel_path
        if not spec_file.is_file():
            errors.append(f"{rel_path}: Active specification file not found")
            continue

        raw_content = spec_file.read_text(encoding="utf-8")
        stripped_content = strip_revision_history(raw_content)
        lines = stripped_content.splitlines()

        # 1. Deprecated tokens check outside Revision History
        in_deprecated_comment_block = False
        for line_idx, line in enumerate(lines, 1):
            stripped_line = line.strip()
            if not stripped_line:
                in_deprecated_comment_block = False
                continue

            is_comment = stripped_line.startswith("--") or stripped_line.startswith("//")
            has_marker = any(marker in line for marker in DEPRECATION_MARKERS)

            if is_comment and has_marker:
                in_deprecated_comment_block = True
                continue
            elif is_comment and in_deprecated_comment_block:
                continue
            else:
                in_deprecated_comment_block = False

            if has_marker:
                continue
            for tok in deprecated_tokens:
                pattern = r"\b" + re.escape(tok) + r"\b"
                if re.search(pattern, line):
                    errors.append(
                        f"{rel_path}:{line_idx}: Deprecated token '{tok}' found without [DEPRECATED] annotation"
                    )

        # 2. Canonical packets check
        is_master_icd = rel_path.replace("\\", "/") == master_icd_rel
        is_diagram = rel_path.replace("\\", "/") == diagram_rel

        for iface in contracts.get("interfaces", []):
            iface_id = iface.get("id", "UNKNOWN")
            iface_specs = [s.replace("\\", "/") for s in iface.get("specs", [])]
            norm_rel = rel_path.replace("\\", "/")

            for pkt_name, pkt_data in iface.get("packets", {}).items():
                pkt_specs = pkt_data.get("specs") if isinstance(pkt_data, dict) else None

                should_check = False
                if is_master_icd:
                    should_check = True
                elif is_diagram:
                    # Diagram covers all canonical packets unless explicitly scoped to a different file
                    if pkt_specs is not None:
                        should_check = diagram_rel in [s.replace("\\", "/") for s in pkt_specs]
                    else:
                        should_check = True
                elif pkt_specs is not None:
                    should_check = norm_rel in [s.replace("\\", "/") for s in pkt_specs]
                elif norm_rel in iface_specs:
                    should_check = True

                if should_check and pkt_name not in raw_content:
                    errors.append(
                        f"{rel_path}: Missing canonical packet '{pkt_name}' from interface {iface_id}"
                    )

    return errors


def _collect_code_legacy_keys(contracts: dict[str, Any]) -> set[str]:
    """Collect legacy and deprecated keys for static Lua code dual-key fallback detection."""
    keys: set[str] = set()
    for iface in contracts.get("interfaces", []):
        keys.update(iface.get("deprecatedPayloadKeys", []))
    keys.update(LEGACY_SURFACE_KEYS)
    keys.update(LEGACY_CONFIG_KEYS)
    keys.update({"oldBase", "newBase", "switchTimeoutMs", "elevator", "leftAileron", "rightAileron", "rudder"})
    return keys


def verify_code_against_contracts(
    repo_root: Path,
    contracts: dict[str, Any],
    include_deferred: bool = False,
) -> list[str]:
    """
    Statically scans Lua source files and JSON configs under src/:
    1. Prohibits string literals matching deprecated packet types or deprecated modes.
    2. Prohibits dual-key fallbacks (e.g. ident.keyA or ident.keyB) where a key matches legacy/deprecated keys.
    3. Validates JSON syntax and prohibits legacy configuration keys in src/**/config/*.json.
    """
    root = Path(repo_root).resolve()
    errors: list[str] = []

    deferred_paths = [
        Path(p).as_posix().strip("/")
        for p in contracts.get("deferredSubsystems", [])
    ]

    deprecated_packet_literals: set[str] = set()
    for iface in contracts.get("interfaces", []):
        deprecated_packet_literals.update(iface.get("deprecatedPacketTypes", []))
        deprecated_packet_literals.update(iface.get("deprecatedModes", []))

    legacy_keys = _collect_code_legacy_keys(contracts)

    src_dir = root / "src"
    if not src_dir.is_dir():
        return errors

    # Collect Lua files
    lua_files = sorted(src_dir.rglob("*.lua"))
    root_installer = root / "installer.lua"
    if root_installer.is_file():
        lua_files.append(root_installer)

    for lua_path in lua_files:
        try:
            rel = lua_path.relative_to(root).as_posix()
        except ValueError:
            rel = str(lua_path)

        if not include_deferred:
            if any(rel.startswith(dp) or f"/{dp}/" in f"/{rel}/" for dp in deferred_paths):
                continue

        source = lua_path.read_text(encoding="utf-8", errors="replace")
        stripped_code, literals = strip_lua_comments_and_strings(source)

        # 1. Check prohibited string literals
        for line_no, lit in literals:
            if lit in deprecated_packet_literals:
                errors.append(
                    f"{rel}:{line_no}: Prohibited deprecated packet or mode literal '{lit}' detected"
                )

        # 2. Check dual-key fallback on stripped code
        for line_idx, line in enumerate(stripped_code.splitlines(), 1):
            for pat in DUAL_KEY_FALLBACK_PATTERNS:
                for match in pat.finditer(line):
                    k1, k2 = match.group(2), match.group(3)
                    if k1 != k2 and (k1 in legacy_keys or k2 in legacy_keys):
                        errors.append(
                            f"{rel}:{line_idx}: Prohibited dual-key fallback '{match.group(0)}' detected (Zero-Fallback violation)"
                        )

    # Collect JSON files under src/
    json_files = sorted(src_dir.rglob("*.json"))
    for json_path in json_files:
        try:
            rel = json_path.relative_to(root).as_posix()
        except ValueError:
            rel = str(json_path)

        if not include_deferred:
            if any(rel.startswith(dp) or f"/{dp}/" in f"/{rel}/" for dp in deferred_paths):
                continue

        content = json_path.read_text(encoding="utf-8", errors="replace")
        try:
            parsed = json.loads(content)
        except Exception as exc:
            errors.append(f"{rel}: Invalid JSON syntax: {exc}")
            continue

        def _check_legacy_config_keys(obj: Any) -> None:
            if isinstance(obj, dict):
                for k, v in obj.items():
                    if k in LEGACY_CONFIG_KEYS:
                        errors.append(
                            f"{rel}: Prohibited legacy configuration key '{k}' detected (Zero-Fallback violation)"
                        )
                    _check_legacy_config_keys(v)
            elif isinstance(obj, list):
                for item in obj:
                    _check_legacy_config_keys(item)

        _check_legacy_config_keys(parsed)

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Protocol contracts SSOT schema loader and verification tool."
    )
    parser.add_argument(
        "--contracts",
        type=str,
        default=None,
        help="Path to protocol_contracts.json (default: config/protocol_contracts.json)",
    )
    parser.add_argument(
        "--root",
        type=str,
        default=None,
        help="Repository root override",
    )
    parser.add_argument(
        "--specs-only",
        action="store_true",
        default=False,
        help="Run specification SSOT verification only",
    )
    parser.add_argument(
        "--code-only",
        action="store_true",
        default=False,
        help="Run static Lua and JSON code verification only",
    )
    parser.add_argument(
        "--include-deferred",
        action="store_true",
        default=False,
        help="Include deferred subsystems (e.g. src/1_control/asa) in static code check",
    )
    args = parser.parse_args()

    repo_root = Path(args.root).resolve() if args.root else REPO_ROOT
    contracts_path = Path(args.contracts).resolve() if args.contracts else (repo_root / "config" / "protocol_contracts.json")

    try:
        contracts = load_contracts(contracts_path)
    except (FileNotFoundError, ValueError) as exc:
        print(f"[FAIL] Contract validation failed: {exc}", file=sys.stderr)
        return 1

    check_specs = not args.code_only
    check_code = not args.specs_only

    all_errors: list[str] = []
    specs_checked = 0
    code_checked = 0

    if check_specs:
        spec_errors = verify_specs_against_contracts(repo_root, contracts)
        specs_checked = len(TARGET_IMPLEMENTED) + len(TARGET_APPROVED)
        all_errors.extend(spec_errors)

    if check_code:
        code_errors = verify_code_against_contracts(
            repo_root, contracts, include_deferred=args.include_deferred
        )
        code_checked = len(list((repo_root / "src").rglob("*.lua"))) + len(list((repo_root / "src").rglob("*.json")))
        all_errors.extend(code_errors)

    if all_errors:
        print(f"[FAIL] {len(all_errors)} protocol contract violation(s) found:", file=sys.stderr)
        for err in all_errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    status_parts = []
    if check_specs:
        status_parts.append(f"{specs_checked} active specs verified")
    if check_code:
        status_parts.append(f"{code_checked} code/config files verified")
    summary = ", ".join(status_parts)

    print(f"[PASS] Protocol contracts verification passed ({summary}, 0 errors)!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
