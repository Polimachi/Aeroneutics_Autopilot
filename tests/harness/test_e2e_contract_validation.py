"""
Unit tests for E2E captured wire packet protocol contracts validation.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parents[2]
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

from tools.verify_contracts import load_contracts, validate_captured_packets

CONTRACTS_PATH = WORKSPACE_ROOT / "config" / "protocol_contracts.json"


class TestE2EContractValidation(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = load_contracts(CONTRACTS_PATH)

    def test_valid_telemetry_and_rebind_packets_pass(self) -> None:
        valid_telemetry = {
            "suite": "test_e2e_telemetry.lua",
            "channel": 10002,
            "replyChannel": 10002,
            "from": "VAS",
            "time": 1000.0,
            "payload": {
                "ver": "1.9.5",
                "domainId": "AIRCRAFT_01",
                "seq": 1,
                "type": "MSG_FLIGHT_TELEMETRY",
                "time": 1000.0,
                "payload": {
                    "attitude": {"q0": 1.0, "q1": 0.0, "q2": 0.0, "q3": 0.0},
                    "angularRates": {"p": 0.0, "q": 0.0, "r": 0.0},
                    "dynamics": {"vx": 0.0, "vy": 0.0, "vz": 0.0},
                    "fuel": 0.85,
                    "dynamicLoad": 0.15,
                    "controlState": "NOMINAL",
                    "activeSource": "FCP",
                    "sensorOk": True,
                    "sensorHealth": {"imu": "OK"},
                    "actuatorHealth": {"tca": "NOMINAL"},
                },
            },
        }

        valid_rebind_ack = {
            "suite": "test_e2e_rebind.lua",
            "channel": 10000,
            "replyChannel": 10000,
            "from": "VAS",
            "time": 1001.0,
            "payload": {
                "ver": "1.9.5",
                "domainId": "AIRCRAFT_01",
                "seq": 2,
                "type": "MSG_CHANNEL_REBIND_ACK",
                "time": 1001.0,
                "payload": {
                    "transactionId": "TX-REBIND-001",
                    "action": "COMMIT",
                    "status": "COMMITTED",
                    "oldBaseChannel": 10000,
                    "newBaseChannel": 10040,
                },
            },
        }

        errors = validate_captured_packets([valid_telemetry, valid_rebind_ack], self.contracts)
        self.assertEqual(errors, [], f"Expected 0 errors for valid packets, got: {errors}")

    def test_missing_envelope_field_or_wrong_version_fails(self) -> None:
        # 1. Missing required envelope field 'seq'
        missing_seq = {
            "suite": "test_envelope.lua",
            "channel": 10002,
            "replyChannel": 10002,
            "from": "VAS",
            "time": 1000.0,
            "payload": {
                "ver": "1.9.5",
                "domainId": "AIRCRAFT_01",
                "type": "MSG_FLIGHT_TELEMETRY",
                "time": 1000.0,
                "payload": {},
            },
        }
        errs_missing = validate_captured_packets([missing_seq], self.contracts)
        self.assertTrue(len(errs_missing) >= 1)
        self.assertTrue(any("seq" in e for e in errs_missing))

        # 2. Incompatible envelope version
        bad_ver = {
            "suite": "test_envelope.lua",
            "channel": 50000,
            "replyChannel": 50000,
            "from": "ROGUE",
            "time": 1000.0,
            "payload": {
                "ver": "0.9.0",
                "domainId": "ROGUE",
                "seq": 1,
                "type": "MSG_BLOCK_REQUEST",
                "time": 1000.0,
                "payload": {"domainId": "ROGUE", "requestedBandwidth": 40},
            },
        }
        errs_ver = validate_captured_packets([bad_ver], self.contracts)
        self.assertTrue(len(errs_ver) >= 1)
        self.assertTrue(any("0.9.0" in e or "version" in e.lower() for e in errs_ver))

        # 3. Non-dictionary envelope payload
        non_dict = {
            "suite": "test_envelope.lua",
            "channel": 50000,
            "replyChannel": 50000,
            "from": "ROGUE",
            "time": 1000.0,
            "payload": "NOT_A_TABLE",
        }
        errs_nondict = validate_captured_packets([non_dict], self.contracts)
        self.assertTrue(len(errs_nondict) >= 1)
        self.assertTrue(any("dictionary" in e.lower() or "table" in e.lower() or "not" in e.lower() for e in errs_nondict))

    def test_deprecated_packet_type_or_payload_key_fails(self) -> None:
        # 1. Prohibited deprecated packet type MSG_REBIND_ACK
        deprecated_type_pkt = {
            "suite": "test_dep.lua",
            "channel": 10000,
            "replyChannel": 10000,
            "from": "VAS",
            "time": 1000.0,
            "payload": {
                "ver": "1.9.5",
                "domainId": "AIRCRAFT_01",
                "seq": 1,
                "type": "MSG_REBIND_ACK",
                "time": 1000.0,
                "payload": {"status": "READY"},
            },
        }
        errs_type = validate_captured_packets([deprecated_type_pkt], self.contracts)
        self.assertTrue(len(errs_type) >= 1)
        self.assertTrue(any("MSG_REBIND_ACK" in e for e in errs_type))

        # 2. Prohibited deprecated payload key oldBase
        deprecated_key_oldbase = {
            "suite": "test_dep.lua",
            "channel": 10000,
            "replyChannel": 10000,
            "from": "VAS",
            "time": 1000.0,
            "payload": {
                "ver": "1.9.5",
                "domainId": "AIRCRAFT_01",
                "seq": 2,
                "type": "MSG_CHANNEL_REBIND_ACK",
                "time": 1000.0,
                "payload": {
                    "transactionId": "TX-1",
                    "action": "COMMIT",
                    "status": "COMMITTED",
                    "oldBaseChannel": 10000,
                    "newBaseChannel": 10040,
                    "oldBase": 10000,  # Deprecated key
                },
            },
        }
        errs_oldbase = validate_captured_packets([deprecated_key_oldbase], self.contracts)
        self.assertTrue(len(errs_oldbase) >= 1)
        self.assertTrue(any("oldBase" in e for e in errs_oldbase))

        # 3. Prohibited deprecated payload key appliedDeg on MSG_AERO_STATUS
        deprecated_key_deg = {
            "suite": "test_dep.lua",
            "channel": 10011,
            "replyChannel": 10011,
            "from": "ASA",
            "time": 1000.0,
            "payload": {
                "ver": "1.9.5",
                "domainId": "AIRCRAFT_01",
                "seq": 3,
                "type": "MSG_AERO_STATUS",
                "time": 1000.0,
                "payload": {
                    "podId": "POD_1",
                    "surfaceId": "ELEV_L",
                    "interactionMode": "API",
                    "appliedDeflection": 0.5,
                    "healthStatus": "NOMINAL",
                    "appliedDeg": 15.0,  # Deprecated key
                },
            },
        }
        errs_deg = validate_captured_packets([deprecated_key_deg], self.contracts)
        self.assertTrue(len(errs_deg) >= 1)
        self.assertTrue(any("appliedDeg" in e for e in errs_deg))

        # 4. Prohibited deprecated/invalid token API_NOMINAL on MSG_AERO_STATUS
        deprecated_token_api_nom = {
            "suite": "test_dep.lua",
            "channel": 10011,
            "replyChannel": 10011,
            "from": "ASA",
            "time": 1000.0,
            "payload": {
                "ver": "1.9.5",
                "domainId": "AIRCRAFT_01",
                "seq": 4,
                "type": "MSG_AERO_STATUS",
                "time": 1000.0,
                "payload": {
                    "podId": "POD_1",
                    "surfaceId": "ELEV_L",
                    "interactionMode": "API",
                    "appliedDeflection": 0.5,
                    "healthStatus": "API_NOMINAL",  # Prohibited enum (must be NOMINAL)
                },
            },
        }
        errs_api_nom = validate_captured_packets([deprecated_token_api_nom], self.contracts)
        self.assertTrue(len(errs_api_nom) >= 1)
        self.assertTrue(any("API_NOMINAL" in e or "healthStatus" in e for e in errs_api_nom))

    def test_out_of_bounds_numeric_or_invalid_enum_fails(self) -> None:
        # 1. fuel = 1.5 exceeds bounds [0.0, 1.0]
        oob_fuel = {
            "suite": "test_bounds.lua",
            "channel": 10002,
            "replyChannel": 10002,
            "from": "VAS",
            "time": 1000.0,
            "payload": {
                "ver": "1.9.5",
                "domainId": "AIRCRAFT_01",
                "seq": 1,
                "type": "MSG_FLIGHT_TELEMETRY",
                "time": 1000.0,
                "payload": {
                    "attitude": {},
                    "angularRates": {},
                    "dynamics": {},
                    "fuel": 1.5,
                    "dynamicLoad": 0.2,
                    "controlState": "NOMINAL",
                    "activeSource": "FCP",
                    "sensorOk": True,
                    "sensorHealth": {},
                    "actuatorHealth": {},
                },
            },
        }
        errs_fuel = validate_captured_packets([oob_fuel], self.contracts)
        self.assertTrue(len(errs_fuel) >= 1)
        self.assertTrue(any("fuel" in e for e in errs_fuel))

        # 2. status = 'UNKNOWN_STATE' on MSG_CHANNEL_REBIND_ACK
        invalid_enum = {
            "suite": "test_bounds.lua",
            "channel": 10000,
            "replyChannel": 10000,
            "from": "VAS",
            "time": 1000.0,
            "payload": {
                "ver": "1.9.5",
                "domainId": "AIRCRAFT_01",
                "seq": 2,
                "type": "MSG_CHANNEL_REBIND_ACK",
                "time": 1000.0,
                "payload": {
                    "transactionId": "TX-1",
                    "action": "COMMIT",
                    "status": "UNKNOWN_STATE",
                    "oldBaseChannel": 10000,
                    "newBaseChannel": 10040,
                },
            },
        }
        errs_enum = validate_captured_packets([invalid_enum], self.contracts)
        self.assertTrue(len(errs_enum) >= 1)
        self.assertTrue(any("status" in e for e in errs_enum))

    def test_deprecated_channel_offset_fails(self) -> None:
        # Base+6 (10006) and Base+7 (10007)
        for bad_ch, expected_offset in ((10006, 6), (10007, 7)):
            dep_ch_pkt = {
                "suite": "test_ch.lua",
                "channel": bad_ch,
                "replyChannel": bad_ch,
                "from": "VAS",
                "time": 1000.0,
                "payload": {
                    "ver": "1.9.5",
                    "domainId": "AIRCRAFT_01",
                    "seq": 1,
                    "type": "MSG_THRUST_CMD",
                    "time": 1000.0,
                    "payload": {
                        "watchdogSeq": 1,
                        "controlState": "NOMINAL",
                        "outputs": {},
                    },
                },
            }
            errs = validate_captured_packets([dep_ch_pkt], self.contracts)
            self.assertTrue(len(errs) >= 1, f"Expected channel {bad_ch} to be flagged")
            self.assertTrue(
                any(str(bad_ch) in e or f"+{expected_offset}" in e for e in errs),
                f"Error should mention {bad_ch} or +{expected_offset}, got: {errs}",
            )


if __name__ == "__main__":
    unittest.main()
