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

from tools.verify_contracts import (
    has_deprecation_marker,
    load_contracts,
    strip_lua_comments,
    strip_revision_history,
    verify_code_against_contracts,
    verify_specs_against_contracts,
)


class TestProtocolContractsSchema(unittest.TestCase):
    def test_load_contracts_contains_all_13_interfaces_and_envelope(self) -> None:
        contracts_path = WORKSPACE_ROOT / "config" / "protocol_contracts.json"
        contracts = load_contracts(contracts_path)

        self.assertIsInstance(contracts, dict)
        self.assertIn("schemaVersion", contracts)
        self.assertEqual(contracts["envelope"]["ver"], "1.9.5")
        self.assertEqual(
            contracts["envelope"]["requiredKeys"],
            ["ver", "domainId", "seq", "type", "time", "payload"],
        )

        # Interfaces I-1 through I-13
        ifaces = contracts.get("interfaces", [])
        self.assertEqual(len(ifaces), 13)
        ids = {iface["id"] for iface in ifaces}
        self.assertEqual(ids, {f"I-{i}" for i in range(1, 14)})

        # Each interface has required fields
        for iface in ifaces:
            self.assertIn("id", iface)
            self.assertIn("name", iface)
            self.assertIn("specs", iface)
            self.assertIsInstance(iface["specs"], list)
            self.assertIn("packets", iface)
            self.assertIsInstance(iface["packets"], dict)

        # Channels configuration
        channels = contracts["channels"]
        self.assertIn("aircraft", channels)
        self.assertEqual(channels["aircraft"]["bandwidth"], 40)
        self.assertEqual(channels["aircraft"]["baseMin"], 10000)
        self.assertEqual(channels["aircraft"]["baseMax"], 49960)
        self.assertIn("hangar", channels)
        self.assertEqual(channels["hangar"]["baseMin"], 101)
        self.assertEqual(channels["hangar"]["bandwidth"], 10)
        self.assertEqual(channels["hangar"]["offsets"]["otaCmd"], 4)
        self.assertEqual(channels["hangar"]["offsets"]["otaAck"], 5)
        self.assertIn("global", channels)
        self.assertIn(50000, channels["global"]["fixed"])

        # Mission Schema v2.0.0
        m_schema = contracts["missionSchema"]
        self.assertEqual(m_schema["version"], "2.0.0")

        # 37 ACT_*, 6 DEC_*, 3 MAC_*, 14 CONDITION_TYPES
        active_actions = m_schema["activeActions"]
        self.assertEqual(len(active_actions), 37)
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

    def test_load_contracts_rejects_non_dict_packets(self) -> None:
        contracts_path = WORKSPACE_ROOT / "config" / "protocol_contracts.json"
        data = json.loads(contracts_path.read_text(encoding="utf-8"))
        data["interfaces"][0]["packets"] = ["MSG_NOT_A_DICT"]
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as tf:
            json.dump(data, tf)
            tf_path = Path(tf.name)
        try:
            with self.assertRaises(ValueError) as ctx:
                load_contracts(tf_path)
            self.assertIn("must be a dict", str(ctx.exception))
        finally:
            tf_path.unlink(missing_ok=True)

    def test_load_contracts_rejects_duplicate_interface_ids(self) -> None:
        contracts_path = WORKSPACE_ROOT / "config" / "protocol_contracts.json"
        data = json.loads(contracts_path.read_text(encoding="utf-8"))
        data["interfaces"].append(dict(data["interfaces"][0]))
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as tf:
            json.dump(data, tf)
            tf_path = Path(tf.name)
        try:
            with self.assertRaises(ValueError) as ctx:
                load_contracts(tf_path)
            self.assertIn("Duplicate interface id", str(ctx.exception))
        finally:
            tf_path.unlink(missing_ok=True)


class TestContractsVerification(unittest.TestCase):
    def test_strip_revision_history_removes_table_lines(self) -> None:
        sample = (
            "# Spec Title\n\n"
            "### Revision History\n\n"
            "| Version | Date | Summary |\n"
            "| :---: | :---: | :--- |\n"
            "| `v1.0.0` | 2026-11-14 | `MSG_REBIND_ACK` deprecated |\n\n"
            "---\n\n"
            "## 1. Overview\n"
            "Active specification body line.\n"
        )
        stripped = strip_revision_history(sample)
        # Line count preserved
        self.assertEqual(len(stripped.splitlines()), len(sample.splitlines()))
        # Revision history contents replaced
        self.assertNotIn("MSG_REBIND_ACK", stripped)
        self.assertIn("Active specification body line.", stripped)

    def test_has_deprecation_marker_word_boundaries(self) -> None:
        # Non-deprecated sentences with Korean words ending in 구/기존 must NOT match
        self.assertFalse(has_deprecation_marker("복구 완료 MSG_REBIND_ACK"))
        self.assertFalse(has_deprecation_marker("요구 사항 MSG_REBIND_ACK"))
        self.assertFalse(has_deprecation_marker("도구 모음 MSG_REBIND_ACK"))
        self.assertFalse(has_deprecation_marker("연구 결과 MSG_REBIND_ACK"))

        # Valid deprecation markers must match
        self.assertTrue(has_deprecation_marker("구 Base+6 채널 대신 Base+10 사용"))
        self.assertTrue(has_deprecation_marker("(구 Base+6 [DEPRECATED])"))
        self.assertTrue(has_deprecation_marker("구형 20채널"))
        self.assertTrue(has_deprecation_marker("기존 oldBase + 11"))
        self.assertTrue(has_deprecation_marker("MSG_REBIND_ACK [DEPRECATED]"))

    def test_revision_history_and_deprecated_lines_do_not_trigger_false_positives(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            spec_rel = "docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md"
            spec_file = td_path / spec_rel
            spec_file.parent.mkdir(parents=True, exist_ok=True)

            spec_content = (
                "# VAS Specification\n\n"
                "### Revision History\n\n"
                "| Version | Date | Summary |\n"
                "| :---: | :---: | :--- |\n"
                "| `v1.30.0` | 2026-11-14 | `MSG_REBIND_ACK [DEPRECATED]` replaced with `MSG_CHANNEL_REBIND_ACK`, `oldBase` removed |\n\n"
                "---\n\n"
                "## 1. Overview\n"
                "System telemetries include `MSG_FLIGHT_TELEMETRY`.\n"
                "Here is an annotated deprecated packet: `MSG_REBIND_ACK` `[DEPRECATED]`.\n"
                "Here is a Korean annotated channel: 구 `Base+6` 대신 `Base+10` 사용 `[DEPRECATED]`.\n"
                "Here is a Korean annotated field: 구 `oldBase` 대신 `oldBaseChannel` 채택.\n"
            )
            spec_file.write_text(spec_content, encoding="utf-8")

            contracts = {
                "schemaVersion": "1.0.0",
                "envelope": {"ver": "1.9.5", "requiredKeys": ["ver", "domainId", "seq", "type", "time", "payload"]},
                "channels": {"aircraft": {"deprecatedOffsets": [6, 7]}, "hangar": {}, "global": {}},
                "interfaces": [
                    {
                        "id": "I-1",
                        "name": "Flight Telemetry",
                        "specs": [spec_rel],
                        "packets": {
                            "MSG_FLIGHT_TELEMETRY": {"requiredKeys": []}
                        },
                        "deprecatedPacketTypes": ["MSG_REBIND_ACK"],
                        "deprecatedPayloadKeys": ["oldBase"],
                    }
                ],
                "missionSchema": {"version": "2.0.0", "activeActions": [], "activeDecorators": [], "activeMacros": [], "conditionTypes": []},
                "deferredSubsystems": ["src/1_control/asa"],
            }

            # Should have 0 errors when deprecated tokens are annotated or in revision history
            errors = verify_specs_against_contracts(td_path, contracts, spec_paths=[spec_rel])
            self.assertEqual(errors, [])

            # Korean word ending in 구 (복구 완료) must NOT exempt MSG_REBIND_ACK from failing
            bogus_content = spec_content + "\n복구 완료 MSG_REBIND_ACK 수신.\n"
            spec_file.write_text(bogus_content, encoding="utf-8")
            errors_bogus = verify_specs_against_contracts(td_path, contracts, spec_paths=[spec_rel])
            self.assertEqual(len(errors_bogus), 1)
            self.assertIn("MSG_REBIND_ACK", errors_bogus[0])

            # Unannotated deprecated token in the body must fail
            unannotated_content = spec_content + "\nUnannotated usage of MSG_REBIND_ACK in body text.\n"
            spec_file.write_text(unannotated_content, encoding="utf-8")
            errors2 = verify_specs_against_contracts(td_path, contracts, spec_paths=[spec_rel])
            self.assertEqual(len(errors2), 1)
            self.assertIn("MSG_REBIND_ACK", errors2[0])

    def test_missing_canonical_packet_in_spec_fails(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            spec_rel = "docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md"
            spec_file = td_path / spec_rel
            spec_file.parent.mkdir(parents=True, exist_ok=True)

            # Spec does not mention MSG_CHANNEL_REBIND_ACK
            spec_content = (
                "# VAS Specification\n\n"
                "## 1. Overview\n"
                "System telemetries include `MSG_FLIGHT_TELEMETRY`.\n"
            )
            spec_file.write_text(spec_content, encoding="utf-8")

            contracts = {
                "schemaVersion": "1.0.0",
                "envelope": {"ver": "1.9.5", "requiredKeys": ["ver", "domainId", "seq", "type", "time", "payload"]},
                "channels": {"aircraft": {}, "hangar": {}, "global": {}},
                "interfaces": [
                    {
                        "id": "I-9",
                        "name": "Rebinding",
                        "specs": [spec_rel],
                        "packets": {
                            "MSG_CHANNEL_REBIND_ACK": {"requiredKeys": []}
                        },
                    }
                ],
                "missionSchema": {"version": "2.0.0", "activeActions": [], "activeDecorators": [], "activeMacros": [], "conditionTypes": []},
                "deferredSubsystems": [],
            }

            errors = verify_specs_against_contracts(td_path, contracts, spec_paths=[spec_rel])
            self.assertEqual(len(errors), 1)
            self.assertIn("MSG_CHANNEL_REBIND_ACK", errors[0])

    def test_static_code_detects_dual_key_fallback_and_deprecated_packet_literal(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            # Active subsystem with dot and bracket dual-key fallbacks and deprecated literal
            bad_lua = td_path / "src" / "0_infra" / "test_node" / "main.lua"
            bad_lua.parent.mkdir(parents=True, exist_ok=True)
            bad_lua.write_text(
                'local base = p.oldBase or p.newBaseChannel\n'
                'local p_type = "MSG_REBIND_ACK"\n'
                'local bracket_double = p["oldBase"] or p["newBaseChannel"]\n'
                'local bracket_single = p[\'oldBase\'] or p[\'newBaseChannel\']\n'
                '-- local commented = p["oldBase"] or p["newBaseChannel"]\n',
                encoding="utf-8",
            )

            # Clean single-key file
            clean_lua = td_path / "src" / "0_infra" / "clean_node" / "main.lua"
            clean_lua.parent.mkdir(parents=True, exist_ok=True)
            clean_lua.write_text(
                'local base = p.newBaseChannel\n'
                'local p_type = "MSG_CHANNEL_REBIND_ACK"\n'
                'local bracket_clean = p["newBaseChannel"]\n',
                encoding="utf-8",
            )

            # Deferred subsystem (asa)
            deferred_lua = td_path / "src" / "1_control" / "asa" / "main.lua"
            deferred_lua.parent.mkdir(parents=True, exist_ok=True)
            deferred_lua.write_text(
                'state.deflections.elevator = tonumber(s.ELEV or s.elevator) or 0\n',
                encoding="utf-8",
            )

            contracts = {
                "schemaVersion": "1.0.0",
                "envelope": {"ver": "1.9.5", "requiredKeys": []},
                "channels": {"aircraft": {}, "hangar": {}, "global": {}},
                "interfaces": [
                    {
                        "id": "I-9",
                        "name": "Rebind",
                        "specs": [],
                        "packets": {},
                        "deprecatedPacketTypes": ["MSG_REBIND_ACK"],
                        "deprecatedPayloadKeys": ["oldBase", "newBase"],
                    },
                    {
                        "id": "I-10",
                        "name": "Aero",
                        "specs": [],
                        "packets": {},
                        "deprecatedPayloadKeys": ["elevator"],
                    }
                ],
                "missionSchema": {"version": "2.0.0", "activeActions": [], "activeDecorators": [], "activeMacros": [], "conditionTypes": []},
                "deferredSubsystems": ["src/1_control/asa"],
            }

            # By default (include_deferred=False), deferredSubsystems (asa) are skipped
            errors = verify_code_against_contracts(td_path, contracts, include_deferred=False)
            self.assertEqual(len(errors), 4)
            # Dot dual-key fallback
            self.assertTrue(any("p.oldBase or p.newBaseChannel" in e for e in errors))
            # Deprecated literal
            self.assertTrue(any("MSG_REBIND_ACK" in e for e in errors))
            # Bracket double quote dual-key fallback
            self.assertTrue(any('p["oldBase"] or p["newBaseChannel"]' in e for e in errors))
            # Bracket single quote dual-key fallback
            self.assertTrue(any("p['oldBase'] or p['newBaseChannel']" in e for e in errors))
            # Verify clean_node had no errors
            self.assertFalse(any("clean_node" in e for e in errors))
            # Verify asa was skipped
            self.assertFalse(any("1_control/asa" in e.replace("\\", "/") for e in errors))

            # With include_deferred=True, asa is checked and flagged
            errors_deferred = verify_code_against_contracts(td_path, contracts, include_deferred=True)
            self.assertEqual(len(errors_deferred), 5)
            self.assertTrue(any("1_control/asa" in e.replace("\\", "/") for e in errors_deferred))

    def test_diagram_spec_verifies_all_canonical_packets_except_explicitly_excluded(self) -> None:
        contracts_path = WORKSPACE_ROOT / "config" / "protocol_contracts.json"
        contracts = load_contracts(contracts_path)

        diagram_rel = "docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md"
        diagram_errors = verify_specs_against_contracts(WORKSPACE_ROOT, contracts, spec_paths=[diagram_rel])
        self.assertEqual(diagram_errors, [], f"Live Diagram spec errors: {diagram_errors}")

        # Assert that if canonical packets are missing in a synthetic diagram, all required are flagged
        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            diag_file = td_path / diagram_rel
            diag_file.parent.mkdir(parents=True, exist_ok=True)
            diag_file.write_text("# Diagram\n\nEmpty diagram without canonical packets.\n", encoding="utf-8")

            errs = verify_specs_against_contracts(td_path, contracts, spec_paths=[diagram_rel])
            expected_diag_missing = sum(
                1 for i in contracts.get("interfaces", [])
                for p in i.get("packets", {}).values()
                if p.get("diagramRequired", True)
            )
            self.assertEqual(len(errs), expected_diag_missing)
            self.assertTrue(any("MSG_FLIGHT_TELEMETRY" in e for e in errs))
            self.assertFalse(any("MSG_ATC_APPROACH_CLEARANCE" in e for e in errs))

    def test_invalid_config_json_and_legacy_config_key_fails(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            cfg_dir = td_path / "src" / "2_guidance" / "fcp" / "config"
            cfg_dir.mkdir(parents=True, exist_ok=True)

            bad_json = cfg_dir / "bad_syntax.json"
            bad_json.write_text('{\n  "version": "1.0.0",\n}', encoding="utf-8")

            legacy_json = cfg_dir / "legacy_key.json"
            legacy_json.write_text('{\n  "version": "1.0.0",\n  "surfaceMix": 0.5\n}', encoding="utf-8")

            contracts = {
                "schemaVersion": "1.0.0",
                "envelope": {"ver": "1.9.5", "requiredKeys": []},
                "channels": {"aircraft": {}, "hangar": {}, "global": {}},
                "interfaces": [],
                "missionSchema": {"version": "2.0.0", "activeActions": [], "activeDecorators": [], "activeMacros": [], "conditionTypes": []},
                "deferredSubsystems": [],
            }

            errors = verify_code_against_contracts(td_path, contracts)
            self.assertEqual(len(errors), 2)
            self.assertTrue(any("bad_syntax.json" in e and "JSON" in e for e in errors))
            self.assertTrue(any("legacy_key.json" in e and "surfaceMix" in e for e in errors))

    def test_live_repo_specs_and_code_pass(self) -> None:
        contracts_path = WORKSPACE_ROOT / "config" / "protocol_contracts.json"
        contracts = load_contracts(contracts_path)

        spec_errors = verify_specs_against_contracts(WORKSPACE_ROOT, contracts)
        self.assertEqual(spec_errors, [], f"Live specs contract errors: {spec_errors}")

        code_errors = verify_code_against_contracts(WORKSPACE_ROOT, contracts, include_deferred=False)
        self.assertEqual(code_errors, [], f"Live code contract errors: {code_errors}")


if __name__ == "__main__":
    unittest.main()
