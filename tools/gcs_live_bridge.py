"""
Local RFC 6455 WebSocket Live Bridge Server for Create_Aeroneutics (TASK-404).

Relays real-time messages between in-game CC:Tweaked GCS (http.websocket) and
the offline host browser WebUI (tools/amm_mission_editor.html) on localhost:
  - WORLD_PRESET_SYNC     (GCS -> Bridge -> WebUI, cached for late joiners)
  - FLEET_TELEMETRY_SYNC  (GCS -> Bridge -> WebUI, cached for late joiners)
  - GPS_NODES_SYNC        (GCS -> Bridge -> WebUI, cached for late joiners)
  - MISSION_PUSH_CMD      (WebUI -> Bridge -> GCS)
  - MISSION_PUSH_ACK      (GCS -> Bridge -> WebUI)

Uses Python standard library only (zero external dependencies).
"""
from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import json
import socket
import struct
import sys
from typing import Any

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
OPCODE_CONT = 0x0
OPCODE_TEXT = 0x1
OPCODE_CLOSE = 0x8
OPCODE_PING = 0x9
OPCODE_PONG = 0xA


def compute_accept_key(sec_websocket_key: str) -> str:
    digest = hashlib.sha1((sec_websocket_key.strip() + WS_GUID).encode("ascii")).digest()
    return base64.b64encode(digest).decode("ascii")


def parse_http_headers(raw_header_bytes: bytes) -> dict[str, str]:
    text = raw_header_bytes.decode("iso-8859-1", errors="replace")
    lines = text.split("\r\n")
    headers: dict[str, str] = {}
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    return headers


def encode_frame(opcode: int, payload: bytes = b"") -> bytes:
    header = bytearray([0x80 | (opcode & 0x0F)])
    length = len(payload)
    if length < 126:
        header.append(length)
    elif length <= 0xFFFF:
        header.append(126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(127)
        header.extend(struct.pack("!Q", length))
    return bytes(header) + payload


async def read_frame(reader: asyncio.StreamReader) -> tuple[int, bytes] | None:
    chunks: list[bytes] = []
    frame_opcode: int | None = None
    while True:
        try:
            head = await reader.readexactly(2)
        except (asyncio.IncompleteReadError, ConnectionResetError, OSError):
            return None
        b1, b2 = head[0], head[1]
        fin = (b1 & 0x80) != 0
        opcode = b1 & 0x0F
        masked = (b2 & 0x80) != 0
        length = b2 & 0x7F
        if length == 126:
            length = struct.unpack("!H", await reader.readexactly(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", await reader.readexactly(8))[0]
        mask_key = await reader.readexactly(4) if masked else b""
        data = await reader.readexactly(length) if length > 0 else b""
        if masked:
            data = bytes(b ^ mask_key[i % 4] for i, b in enumerate(data))
        if opcode >= 0x8:
            return opcode, data
        if frame_opcode is None:
            frame_opcode = opcode
        chunks.append(data)
        if fin:
            return frame_opcode, b"".join(chunks)


class GCSLiveBridgeServer:
    def __init__(self, host: str = "127.0.0.1", port: int = 8765, dump_state: bool = False) -> None:
        self.host = host
        self.port = port
        self.bound_port: int = port
        self.dump_state = dump_state
        self.server: asyncio.AbstractServer | None = None
        self.clients: set[asyncio.StreamWriter] = set()
        self.latest_world: dict[str, Any] | None = None
        self.latest_fleet: dict[str, Any] | None = None
        self.latest_gps: dict[str, Any] | None = None

    async def start(self) -> None:
        self.server = await asyncio.start_server(self._handle_client, self.host, self.port)
        if self.server.sockets:
            self.bound_port = int(self.server.sockets[0].getsockname()[1])

    async def stop(self) -> None:
        for writer in list(self.clients):
            try:
                writer.write(encode_frame(OPCODE_CLOSE))
                await writer.drain()
            except OSError:
                pass
            writer.close()
        self.clients.clear()
        if self.server is not None:
            self.server.close()
            await self.server.wait_closed()
            self.server = None

    async def _send_json(self, writer: asyncio.StreamWriter, payload: dict[str, Any]) -> bool:
        frame = encode_frame(OPCODE_TEXT, json.dumps(payload, separators=(",", ":")).encode("utf-8"))
        try:
            writer.write(frame)
            await writer.drain()
            return True
        except OSError:
            return False

    async def _broadcast_other(self, sender: asyncio.StreamWriter, payload: dict[str, Any]) -> None:
        dead: list[asyncio.StreamWriter] = []
        for client in list(self.clients):
            if client is sender:
                continue
            ok = await self._send_json(client, payload)
            if not ok:
                dead.append(client)
        for client in dead:
            self.clients.discard(client)
            client.close()

    async def _send_cached_snapshots(self, writer: asyncio.StreamWriter) -> None:
        if self.latest_world is not None:
            await self._send_json(writer, self.latest_world)
        if self.latest_fleet is not None:
            await self._send_json(writer, self.latest_fleet)
        if self.latest_gps is not None:
            await self._send_json(writer, self.latest_gps)

    async def _process_text(self, writer: asyncio.StreamWriter, raw: bytes) -> None:
        try:
            msg = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return
        if not isinstance(msg, dict) or not isinstance(msg.get("type"), str):
            return
        mtype = msg["type"]
        if mtype == "WORLD_PRESET_SYNC":
            self.latest_world = msg
        elif mtype == "FLEET_TELEMETRY_SYNC":
            self.latest_fleet = msg
        elif mtype == "GPS_NODES_SYNC":
            self.latest_gps = msg
        if self.dump_state:
            print(f"[BRIDGE] {mtype}: {json.dumps(msg, ensure_ascii=False)}", flush=True)
        await self._broadcast_other(writer, msg)

    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            raw_headers = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=5.0)
        except Exception:
            writer.close()
            return
        headers = parse_http_headers(raw_headers)
        ws_key = headers.get("sec-websocket-key")
        if not ws_key:
            writer.write(b"HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
            await writer.drain()
            writer.close()
            return
        accept = compute_accept_key(ws_key)
        response = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        ).encode("ascii")
        writer.write(response)
        await writer.drain()

        self.clients.add(writer)
        try:
            await self._send_cached_snapshots(writer)
            while True:
                frame = await read_frame(reader)
                if frame is None:
                    break
                opcode, payload = frame
                if opcode == OPCODE_CLOSE:
                    try:
                        writer.write(encode_frame(OPCODE_CLOSE))
                        await writer.drain()
                    except OSError:
                        pass
                    break
                if opcode == OPCODE_PING:
                    writer.write(encode_frame(OPCODE_PONG, payload))
                    await writer.drain()
                elif opcode == OPCODE_TEXT:
                    await self._process_text(writer, payload)
        finally:
            self.clients.discard(writer)
            writer.close()


def detect_lan_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("10.255.255.255", 1))
            ip = sock.getsockname()[0]
            if ip and not ip.startswith("127."):
                return ip
    except OSError:
        pass
    try:
        ip = socket.gethostbyname(socket.gethostname())
        if ip and not ip.startswith("127."):
            return ip
    except OSError:
        pass
    return "<lan-ip>"


def resolve_bind_host(args: argparse.Namespace) -> str:
    if getattr(args, "lan", False) and args.host == "127.0.0.1":
        return "0.0.0.0"
    return str(args.host)


async def serve_forever(host: str, port: int, dump_state: bool) -> None:
    bridge = GCSLiveBridgeServer(host=host, port=port, dump_state=dump_state)
    await bridge.start()
    print(f"[GCS Live Bridge] Listening on ws://{host}:{bridge.bound_port}", flush=True)
    if host == "0.0.0.0":
        print(
            f"[GCS Live Bridge] LAN URL hint: ws://{detect_lan_ip()}:{bridge.bound_port} (or ws://<hostname>.local:{bridge.bound_port})",
            flush=True,
        )
    assert bridge.server is not None
    try:
        async with bridge.server:
            await bridge.server.serve_forever()
    except asyncio.CancelledError:
        pass
    finally:
        await bridge.stop()


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Create_Aeroneutics Localhost WebSocket Live Bridge")
    parser.add_argument("--host", default="127.0.0.1", help="Bind address (default: 127.0.0.1)")
    parser.add_argument("--lan", action="store_true", help="Bind to 0.0.0.0 for LAN WebUI access (alias for --host 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8765, help="WebSocket port (default: 8765)")
    parser.add_argument("--dump-state", action="store_true", help="Print relayed JSON frames to stdout")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    bind_host = resolve_bind_host(args)
    try:
        asyncio.run(serve_forever(bind_host, args.port, args.dump_state))
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
