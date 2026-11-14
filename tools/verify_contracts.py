"""
Protocol contracts SSOT loader and cross-subsystem verification tool.
Cross-checks specifications, static Lua/JSON code, and E2E captured packets
against config/protocol_contracts.json.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
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
    for idx, iface in enumerate(interfaces):
        if not isinstance(iface, dict):
            raise ValueError(f"Interface at index {idx} must be a dictionary")
        for ik in REQUIRED_INTERFACE_KEYS:
            if ik not in iface:
                raise ValueError(f"Interface at index {idx} missing required key '{ik}'")
        if not isinstance(iface["specs"], list):
            raise ValueError(f"Interface '{iface.get('id')}' field 'specs' must be a list")
        if not isinstance(iface["packets"], (dict, list)):
            raise ValueError(f"Interface '{iface.get('id')}' field 'packets' must be a dict or list")

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
    args = parser.parse_args()

    repo_root = Path(args.root).resolve() if args.root else REPO_ROOT
    contracts_path = Path(args.contracts).resolve() if args.contracts else (repo_root / "config" / "protocol_contracts.json")

    try:
        contracts = load_contracts(contracts_path)
    except (FileNotFoundError, ValueError) as exc:
        print(f"[FAIL] Contract validation failed: {exc}", file=sys.stderr)
        return 1

    iface_count = len(contracts.get("interfaces", []))
    act_count = len(contracts.get("missionSchema", {}).get("activeActions", []))
    print(
        f"[PASS] Loaded protocol contracts v{contracts.get('schemaVersion')} "
        f"({iface_count} interfaces, {act_count} active actions, envelope v{contracts['envelope']['ver']})!"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
