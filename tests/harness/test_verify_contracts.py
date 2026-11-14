"""
Unit tests for protocol contracts schema and loader validation.
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parents[2]
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

from tools.verify_contracts import load_contracts


class TestProtocolContractsSchema(unittest.TestCase):
    def test_load_contracts_contains_all_12_interfaces_and_envelope(self) -> None:
        contracts_path = WORKSPACE_ROOT / "config" / "protocol_contracts.json"
        contracts = load_contracts(contracts_path)

        self.assertIsInstance(contracts, dict)
        self.assertIn("schemaVersion", contracts)
        self.assertEqual(contracts["envelope"]["ver"], "1.9.5")
        self.assertEqual(
            contracts["envelope"]["requiredKeys"],
            ["ver", "domainId", "seq", "type", "time", "payload"],
        )

        # Interfaces I-1 through I-12
        ifaces = contracts.get("interfaces", [])
        self.assertEqual(len(ifaces), 12)
        ids = {iface["id"] for iface in ifaces}
        self.assertEqual(ids, {f"I-{i}" for i in range(1, 13)})

        # Each interface has required fields
        for iface in ifaces:
            self.assertIn("id", iface)
            self.assertIn("name", iface)
            self.assertIn("specs", iface)
            self.assertIsInstance(iface["specs"], list)
            self.assertIn("packets", iface)
            self.assertIsInstance(iface["packets"], (dict, list))

        # Channels configuration
        channels = contracts["channels"]
        self.assertIn("aircraft", channels)
        self.assertEqual(channels["aircraft"]["bandwidth"], 40)
        self.assertEqual(channels["aircraft"]["baseMin"], 10000)
        self.assertEqual(channels["aircraft"]["baseMax"], 49960)
        self.assertIn("hangar", channels)
        self.assertEqual(channels["hangar"]["baseMin"], 101)
        self.assertEqual(channels["hangar"]["bandwidth"], 10)
        self.assertIn("global", channels)
        self.assertIn(50000, channels["global"]["fixed"])

        # Mission Schema v2.0.0
        m_schema = contracts["missionSchema"]
        self.assertEqual(m_schema["version"], "2.0.0")

        # 36 ACT_*, 6 DEC_*, 3 MAC_*, 14 CONDITION_TYPES
        active_actions = m_schema["activeActions"]
        self.assertEqual(len(active_actions), 36)
        for act in active_actions:
            self.assertTrue(act.startswith("ACT_"), f"Expected ACT_ prefix for {act}")

        active_decorators = m_schema["activeDecorators"]
        self.assertEqual(len(active_decorators), 6)
        for dec in active_decorators:
            self.assertTrue(dec.startswith("DEC_"), f"Expected DEC_ prefix for {dec}")

        active_macros = m_schema["activeMacros"]
        self.assertEqual(len(active_macros), 3)
        for mac in active_macros:
            self.assertTrue(mac.startswith("MAC_"), f"Expected MAC_ prefix for {mac}")

        condition_types = m_schema["conditionTypes"]
        self.assertEqual(len(condition_types), 14)

        # Deferred subsystems
        self.assertIn("src/1_control/asa", contracts["deferredSubsystems"])

    def test_load_contracts_file_not_found(self) -> None:
        missing_path = WORKSPACE_ROOT / "config" / "does_not_exist.json"
        with self.assertRaises(FileNotFoundError):
            load_contracts(missing_path)

    def test_load_contracts_missing_top_level_keys(self) -> None:
        valid_minimal: dict[str, object] = {
            "schemaVersion": "1.0.0",
            "envelope": {
                "ver": "1.9.5",
                "requiredKeys": ["ver", "domainId", "seq", "type", "time", "payload"],
            },
            "channels": {
                "aircraft": {"baseMin": 10000, "baseMax": 49960, "bandwidth": 40},
                "hangar": {"baseMin": 101, "baseMax": 191, "bandwidth": 10},
                "global": {"fixed": [50000]},
            },
            "interfaces": [
                {"id": f"I-{i}", "name": f"Interface {i}", "specs": [], "packets": []}
                for i in range(1, 13)
            ],
            "missionSchema": {
                "version": "2.0.0",
                "activeActions": [f"ACT_{i}" for i in range(36)],
                "activeDecorators": [f"DEC_{i}" for i in range(6)],
                "activeMacros": [f"MAC_{i}" for i in range(3)],
                "conditionTypes": [f"COND_{i}" for i in range(14)],
            },
            "deferredSubsystems": ["src/1_control/asa"],
        }

        # Omitting each required top-level key must raise ValueError
        for required_key in [
            "schemaVersion",
            "envelope",
            "channels",
            "interfaces",
            "missionSchema",
            "deferredSubsystems",
        ]:
            bad_data = dict(valid_minimal)
            del bad_data[required_key]
            with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as tf:
                json.dump(bad_data, tf)
                tf_path = Path(tf.name)
            try:
                with self.assertRaises(ValueError):
                    load_contracts(tf_path)
            finally:
                tf_path.unlink(missing_ok=True)

    def test_load_contracts_malformed_envelope_or_interfaces(self) -> None:
        # Invalid envelope
        bad_envelope: dict[str, object] = {
            "schemaVersion": "1.0.0",
            "envelope": {"ver": "1.9.5"},  # missing requiredKeys
            "channels": {},
            "interfaces": [],
            "missionSchema": {},
            "deferredSubsystems": [],
        }
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as tf:
            json.dump(bad_envelope, tf)
            tf_path = Path(tf.name)
        try:
            with self.assertRaises(ValueError):
                load_contracts(tf_path)
        finally:
            tf_path.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
