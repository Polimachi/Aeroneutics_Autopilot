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

DEPRECATION_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"\[DEPRECATED\]", re.IGNORECASE),
    re.compile(r"\bDEPRECATED\b", re.IGNORECASE),
    re.compile(r"(?:^|[\s`(\[<*~])구(?:형)?\s+"),
    re.compile(r"(?:^|[\s`(\[<*~])기존\s+"),
)


def has_deprecation_marker(line: str) -> bool:
    """Check if a line contains a valid deprecation annotation with proper word boundaries."""
    return any(pat.search(line) for pat in DEPRECATION_PATTERNS)

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


def strip_lua_comments(source: str) -> str:
    """
    Strips single-line (--) and multi-line (--[[ ]]) comments from Lua source,
    replacing comment characters with spaces to preserve line numbers and columns.
    String literals ('...', "...", and [=[...]=]) are preserved intact so that
    bracket indexing expressions like t["keyA"] or t['keyB'] can be statically analyzed.
    """
    n = len(source)
    out: list[str] = []
    i = 0

    while i < n:
        c = source[i]
        c2 = source[i : i + 2]

        if c == "\n":
            out.append(c)
            i += 1
            continue

        # Single-line or multi-line comment: --
        if c2 == "--":
            i += 2
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
            eqs = long_str_match.group(1)
            closer = f"]{eqs}]"
            content_start = i + len(long_str_match.group(0))
            closer_idx = source.find(closer, content_start)
            if closer_idx == -1:
                closer_idx = n
            else:
                closer_idx += len(closer)
            out.append(source[i:closer_idx])
            i = closer_idx
            continue

        # Quoted string literal: ' or "
        if c in ("'", '"'):
            delim = c
            out.append(delim)
            i += 1
            while i < n:
                cur = source[i]
                if cur == "\n":
                    out.append("\n")
                    i += 1
                    break
                if cur == "\\":
                    out.append(cur)
                    i += 1
                    if i < n:
                        out.append(source[i])
                        i += 1
                    continue
                out.append(cur)
                i += 1
                if cur == delim:
                    break
            continue

        out.append(c)
        i += 1

    return "".join(out)


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
            has_marker = has_deprecation_marker(line)

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
                diagram_req = pkt_data.get("diagramRequired", True) if isinstance(pkt_data, dict) else True

                should_check = False
                if is_master_icd:
                    should_check = True
                elif is_diagram:
                    # Diagram covers all canonical packets across all 12 interfaces
                    # unless explicitly excluded via diagramRequired: false
                    should_check = diagram_req
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
        comments_stripped = strip_lua_comments(source)

        # 1. Check prohibited string literals
        for line_no, lit in literals:
            if lit in deprecated_packet_literals:
                errors.append(
                    f"{rel}:{line_no}: Prohibited deprecated packet or mode literal '{lit}' detected"
                )

        # 2. Check dual-key fallback on comments-stripped code (preserves string keys in brackets)
        for line_idx, line in enumerate(comments_stripped.splitlines(), 1):
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


def validate_captured_packets(
    packets: list[dict[str, Any]],
    contracts: dict[str, Any],
) -> list[str]:
    """
    Validates captured E2E wire packets against protocol_contracts.json SSOT.
    Verifies channel allocation, envelope integrity, packet deprecations,
    required payload keys, enums, and numeric bounds.
    """
    errors: list[str] = []

    envelope_spec = contracts.get("envelope", {})
    expected_ver = envelope_spec.get("ver", "1.9.5")
    required_envelope_keys = envelope_spec.get(
        "requiredKeys", ["ver", "domainId", "seq", "type", "time", "payload"]
    )
    envelope_types = envelope_spec.get("types", {})

    channels_cfg = contracts.get("channels", {})
    ac_cfg = channels_cfg.get("aircraft", {})
    ac_base_min = ac_cfg.get("baseMin", 10000)
    ac_bandwidth = ac_cfg.get("bandwidth", 40)
    ac_max_craft = ac_cfg.get("maxAircraft", 1000)
    ac_dep_offsets = set(ac_cfg.get("deprecatedOffsets", [6, 7]))

    hg_cfg = channels_cfg.get("hangar", {})
    hg_dep_offsets = set(hg_cfg.get("deprecatedOffsets", [1001, 1002]))

    # Deprecated packet types and global payload keys
    deprecated_packet_types: set[str] = set()
    global_dep_payload_keys: set[str] = {"oldBase", "newBase", "appliedDeg", "API_NOMINAL", "switchTimeoutMs"}
    packet_defs: dict[str, tuple[dict[str, Any], dict[str, Any]]] = {}

    for iface in contracts.get("interfaces", []):
        for dpt in iface.get("deprecatedPacketTypes", []):
            deprecated_packet_types.add(dpt)
        for pkt_name, pkt_spec in iface.get("packets", {}).items():
            packet_defs[pkt_name] = (iface, pkt_spec)

    for idx, pkt in enumerate(packets):
        if not isinstance(pkt, dict):
            errors.append(f"Packet #{idx}: entry must be a dictionary, got {type(pkt).__name__}")
            continue

        suite = pkt.get("suite") or "<unknown_suite>"
        channel = pkt.get("channel")
        raw_payload = pkt.get("payload")

        # Channel check
        if isinstance(channel, (int, float)):
            ch_num = int(channel)
            # Aircraft channel check: baseMin..baseMax
            if ac_base_min <= ch_num < (ac_base_min + ac_max_craft * ac_bandwidth):
                offset = (ch_num - ac_base_min) % ac_bandwidth
                if offset in ac_dep_offsets:
                    errors.append(
                        f"[{suite}] Packet #{idx} on channel {ch_num}: Prohibited deprecated aircraft channel offset +{offset} used"
                    )
            elif ch_num < 40 and ch_num in ac_dep_offsets:
                errors.append(
                    f"[{suite}] Packet #{idx} on channel {ch_num}: Prohibited deprecated aircraft channel offset +{ch_num} used"
                )

            # Hangar channel check
            if ch_num in hg_dep_offsets:
                errors.append(
                    f"[{suite}] Packet #{idx} on channel {ch_num}: Prohibited deprecated hangar channel {ch_num} used"
                )

        # Envelope payload check
        if not isinstance(raw_payload, dict):
            errors.append(
                f"[{suite}] Packet #{idx} on channel {channel}: Payload is not a dictionary/object (got {type(raw_payload).__name__})"
            )
            continue

        # Check required envelope keys
        for ek in required_envelope_keys:
            if ek not in raw_payload:
                errors.append(
                    f"[{suite}] Packet #{idx} on channel {channel}: Missing required envelope key '{ek}'"
                )

        # Check envelope version
        if "ver" in raw_payload and raw_payload["ver"] != expected_ver:
            errors.append(
                f"[{suite}] Packet #{idx} on channel {channel}: Envelope version mismatch: expected '{expected_ver}', got '{raw_payload['ver']}'"
            )

        # Check envelope key types
        for k, exp_type in envelope_types.items():
            if k in raw_payload:
                val = raw_payload[k]
                if exp_type == "string" and not isinstance(val, str):
                    errors.append(
                        f"[{suite}] Packet #{idx} on channel {channel}: Envelope key '{k}' must be string, got {type(val).__name__}"
                    )
                elif exp_type == "number" and (not isinstance(val, (int, float)) or isinstance(val, bool)):
                    errors.append(
                        f"[{suite}] Packet #{idx} on channel {channel}: Envelope key '{k}' must be number, got {type(val).__name__}"
                    )
                elif exp_type == "object" and not isinstance(val, dict):
                    errors.append(
                        f"[{suite}] Packet #{idx} on channel {channel}: Envelope key '{k}' must be object/dict, got {type(val).__name__}"
                    )

        pkt_type = raw_payload.get("type")
        if pkt_type in deprecated_packet_types:
            errors.append(
                f"[{suite}] Packet #{idx} on channel {channel}: Prohibited deprecated packet type '{pkt_type}' transmitted"
            )

        inner_payload = raw_payload.get("payload")
        if isinstance(inner_payload, dict):
            iface_match, pkt_spec_match = packet_defs.get(pkt_type, (None, None))
            iface_dep_keys = set(iface_match.get("deprecatedPayloadKeys", [])) if iface_match else set()
            active_dep_keys = global_dep_payload_keys | iface_dep_keys

            # Check for deprecated payload keys at top level and nested levels
            def _check_dep_keys(d: dict[str, Any], path: str = "payload") -> None:
                for k, v in d.items():
                    if k in active_dep_keys:
                        errors.append(
                            f"[{suite}] Packet #{idx} on channel {channel} ({pkt_type}): Prohibited deprecated payload key '{k}' detected at '{path}'"
                        )
                    if isinstance(v, dict):
                        _check_dep_keys(v, f"{path}.{k}")

            _check_dep_keys(inner_payload)

            # If packet type is canonical, validate against its packet specification
            if pkt_spec_match:
                # Check required keys
                for rk in pkt_spec_match.get("requiredKeys", []):
                    if rk not in inner_payload:
                        errors.append(
                            f"[{suite}] Packet #{idx} on channel {channel} ({pkt_type}): Missing required payload key '{rk}'"
                        )

                # Check enums
                for ek, allowed_vals in pkt_spec_match.get("enums", {}).items():
                    if ek in inner_payload:
                        val = inner_payload[ek]
                        if val not in allowed_vals:
                            errors.append(
                                f"[{suite}] Packet #{idx} on channel {channel} ({pkt_type}): Field '{ek}' has invalid enum value '{val}' (allowed: {allowed_vals})"
                            )

                # Check numeric bounds
                for nk, bounds in pkt_spec_match.get("numericBounds", {}).items():
                    if nk in inner_payload:
                        val = inner_payload[nk]
                        if not isinstance(val, (int, float)) or isinstance(val, bool):
                            errors.append(
                                f"[{suite}] Packet #{idx} on channel {channel} ({pkt_type}): Field '{nk}' expected number, got {type(val).__name__}"
                            )
                        elif val < bounds[0] or val > bounds[1]:
                            errors.append(
                                f"[{suite}] Packet #{idx} on channel {channel} ({pkt_type}): Field '{nk}' value {val} out of bounds [{bounds[0]}, {bounds[1]}]"
                            )

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
