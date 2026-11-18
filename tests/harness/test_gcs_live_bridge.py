"""
Unit and integration tests for tools/gcs_live_bridge.py (TASK-404).
Uses a minimal RFC 6455 masked client over stdlib asyncio sockets.
"""
from __future__ import annotations

import asyncio
import base64
import json
import os
import struct
import unittest

from tools import gcs_live_bridge
from tools.gcs_live_bridge import (
    GCSLiveBridgeServer,
    OPCODE_CLOSE,
    OPCODE_PING,
    OPCODE_PONG,
    OPCODE_TEXT,
    compute_accept_key,
    read_frame,
)


def encode_masked_frame(opcode: int, payload: bytes) -> bytes:
    header = bytearray([0x80 | (opcode & 0x0F)])
    length = len(payload)
    if length < 126:
        header.append(0x80 | length)
    elif length <= 0xFFFF:
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", length))
    mask = os.urandom(4)
    header.extend(mask)
    masked_payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return bytes(header) + masked_payload


async def ws_connect(host: str, port: int) -> tuple[asyncio.StreamReader, asyncio.StreamWriter, bytes]:
    reader, writer = await asyncio.open_connection(host, port)
    key_bytes = base64.b64encode(os.urandom(16))
    req = (
        f"GET / HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key_bytes.decode('ascii')}\r\n"
        f"Sec-WebSocket-Version: 13\r\n\r\n"
    ).encode("ascii")
    writer.write(req)
    await writer.drain()
    raw_resp = await reader.readuntil(b"\r\n\r\n")
    return reader, writer, raw_resp


class TestGCSLiveBridge(unittest.TestCase):
    def test_compute_accept_key_rfc6455_vector(self) -> None:
        # Official RFC 6455 Section 4.2.2 example key
        self.assertEqual(
            compute_accept_key("dGhlIHNhbXBsZSBub25jZQ=="),
            "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
        )

    def test_handshake_caching_and_bidirectional_relay(self) -> None:
        async def scenario() -> None:
            server = GCSLiveBridgeServer(host="127.0.0.1", port=0)
            await server.start()
            try:
                port = server.bound_port
                gcs_r, gcs_w, gcs_resp = await ws_connect("127.0.0.1", port)
                self.assertIn(b"101 Switching Protocols", gcs_resp)

                world_msg = {
                    "type": "WORLD_PRESET_SYNC",
                    "sectorId": 1,
                    "sectorName": "Base Alpha",
                    "facilities": [
                        {"facilityId": "PAD_01", "facilityType": "LANDING_PAD", "status": "FREE", "position": {"x": 100, "y": 64, "z": -50}},
                    ],
                }
                fleet_msg = {
                    "type": "FLEET_TELEMETRY_SYNC",
                    "crafts": [
                        {"domainId": "AIRCRAFT_01", "baseChannel": 10000, "position": {"x": 120, "y": 140, "z": -30}, "fuel": 0.85, "fsmState": "CRUISE"},
                    ],
                }
                gcs_w.write(encode_masked_frame(OPCODE_TEXT, json.dumps(world_msg).encode("utf-8")))
                gcs_w.write(encode_masked_frame(OPCODE_TEXT, json.dumps(fleet_msg).encode("utf-8")))
                await gcs_w.drain()
                await asyncio.sleep(0.05)

                # Late-joining WebUI must receive both cached snapshots immediately
                ui_r, ui_w, ui_resp = await ws_connect("127.0.0.1", port)
                self.assertIn(b"101 Switching Protocols", ui_resp)

                op1, data1 = await asyncio.wait_for(read_frame(ui_r), timeout=2.0)  # type: ignore[misc]
                op2, data2 = await asyncio.wait_for(read_frame(ui_r), timeout=2.0)  # type: ignore[misc]
                self.assertEqual(op1, OPCODE_TEXT)
                self.assertEqual(op2, OPCODE_TEXT)
                got1 = json.loads(data1.decode("utf-8"))
                got2 = json.loads(data2.decode("utf-8"))
                self.assertEqual(got1["type"], "WORLD_PRESET_SYNC")
                self.assertEqual(got2["type"], "FLEET_TELEMETRY_SYNC")
                self.assertEqual(got1["facilities"][0]["facilityId"], "PAD_01")

                # Ping / Pong keepalive
                ui_w.write(encode_masked_frame(OPCODE_PING, b"hb"))
                await ui_w.drain()
                op_pong, pong_data = await asyncio.wait_for(read_frame(ui_r), timeout=2.0)  # type: ignore[misc]
                self.assertEqual(op_pong, OPCODE_PONG)
                self.assertEqual(pong_data, b"hb")

                # Bidirectional WebUI MISSION_PUSH_CMD -> GCS -> MISSION_PUSH_ACK -> WebUI
                push_cmd = {
                    "type": "MISSION_PUSH_CMD",
                    "requestId": "req-1",
                    "targetCraft": "AIRCRAFT_01",
                    "baseChannel": 10000,
                    "action": "LOAD",
                    "saveToDisk": True,
                    "missionData": {"version": "2.0.0", "missionId": "M_PUSH", "checkpoints": []},
                }
                ui_w.write(encode_masked_frame(OPCODE_TEXT, json.dumps(push_cmd).encode("utf-8")))
                await ui_w.drain()

                op_cmd, cmd_raw = await asyncio.wait_for(read_frame(gcs_r), timeout=2.0)  # type: ignore[misc]
                self.assertEqual(op_cmd, OPCODE_TEXT)
                cmd_decoded = json.loads(cmd_raw.decode("utf-8"))
                self.assertEqual(cmd_decoded["requestId"], "req-1")
                self.assertEqual(cmd_decoded["action"], "LOAD")

                push_ack = {
                    "type": "MISSION_PUSH_ACK",
                    "requestId": "req-1",
                    "targetCraft": "AIRCRAFT_01",
                    "action": "LOAD",
                    "status": "ACCEPTED",
                    "missionId": "M_PUSH",
                }
                gcs_w.write(encode_masked_frame(OPCODE_TEXT, json.dumps(push_ack).encode("utf-8")))
                await gcs_w.drain()

                op_ack, ack_raw = await asyncio.wait_for(read_frame(ui_r), timeout=2.0)  # type: ignore[misc]
                self.assertEqual(op_ack, OPCODE_TEXT)
                ack_decoded = json.loads(ack_raw.decode("utf-8"))
                self.assertEqual(ack_decoded["status"], "ACCEPTED")
                self.assertEqual(ack_decoded["missionId"], "M_PUSH")

                ui_w.write(encode_masked_frame(OPCODE_CLOSE, b""))
                await ui_w.drain()
                gcs_w.close()
                ui_w.close()
            finally:
                await server.stop()

        asyncio.run(scenario())

    def test_lan_flag_resolves_0_0_0_0_and_preserves_localhost_default(self) -> None:
        parser = gcs_live_bridge.build_arg_parser()
        default_args = parser.parse_args([])
        lan_args = parser.parse_args(["--lan"])
        explicit_args = parser.parse_args(["--lan", "--host", "192.168.1.10"])
        self.assertEqual(default_args.host, "127.0.0.1")
        self.assertFalse(default_args.lan)
        self.assertEqual(gcs_live_bridge.resolve_bind_host(default_args), "127.0.0.1")
        self.assertTrue(lan_args.lan)
        self.assertEqual(gcs_live_bridge.resolve_bind_host(lan_args), "0.0.0.0")
        self.assertEqual(gcs_live_bridge.resolve_bind_host(explicit_args), "192.168.1.10")

    def test_caches_and_replays_gps_nodes_sync_to_new_client(self) -> None:
        async def scenario() -> None:
            server = GCSLiveBridgeServer(host="127.0.0.1", port=0)
            await server.start()
            try:
                port = server.bound_port
                gcs_r, gcs_w, _ = await ws_connect("127.0.0.1", port)

                gps_msg = {
                    "type": "GPS_NODES_SYNC",
                    "nodes": [
                        {
                            "facilityId": "GPS_NODE_01",
                            "facilityType": "GPS",
                            "status": "ONLINE",
                            "position": {"x": 100.0, "y": 240.0, "z": -300.0},
                        }
                    ],
                }
                gcs_w.write(encode_masked_frame(OPCODE_TEXT, json.dumps(gps_msg).encode("utf-8")))
                await gcs_w.drain()
                await asyncio.sleep(0.05)

                self.assertIsNotNone(server.latest_gps)

                ui_r, ui_w, _ = await ws_connect("127.0.0.1", port)
                op1, raw1 = await asyncio.wait_for(read_frame(ui_r), timeout=2.0)  # type: ignore[misc]
                self.assertEqual(op1, OPCODE_TEXT)
                got1 = json.loads(raw1.decode("utf-8"))
                self.assertEqual(got1["type"], "GPS_NODES_SYNC")
                self.assertEqual(got1["nodes"][0]["facilityId"], "GPS_NODE_01")

                gcs_w.close()
                ui_w.close()
            finally:
                await server.stop()

        asyncio.run(scenario())


if __name__ == "__main__":
    unittest.main()
