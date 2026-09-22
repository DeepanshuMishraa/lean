#!/usr/bin/env python3
"""Capture a screenshot of a CEF page via the DevTools protocol.

Usage: cef_shot.py <out.png> [url-substring]
Connects to localhost:9222, picks the first page target whose URL contains
url-substring (or the first non-devtools page), captures PNG, writes it out.
No third-party dependencies: minimal raw-socket WebSocket client.
"""
import base64
import json
import os
import socket
import struct
import sys
import urllib.request


def recvn(s, n):
    data = b""
    while len(data) < n:
        chunk = s.recv(n - len(data))
        if not chunk:
            raise ConnectionError("socket closed")
        data += chunk
    return data


def ws_send(s, obj):
    payload = json.dumps(obj).encode()
    mask = os.urandom(4)
    if len(payload) < 126:
        frame = bytes([0x81, 0x80 | len(payload)]) + mask
    elif len(payload) < 65536:
        frame = bytes([0x81, 0x80 | 126]) + struct.pack(">H", len(payload)) + mask
    else:
        frame = bytes([0x81, 0x80 | 127]) + struct.pack(">Q", len(payload)) + mask
    frame += bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    s.sendall(frame)


def ws_recv(s):
    data = b""
    while True:
        h = recvn(s, 2)
        fin = h[0] & 0x80
        ln = h[1] & 0x7F
        if ln == 126:
            ln = struct.unpack(">H", recvn(s, 2))[0]
        elif ln == 127:
            ln = struct.unpack(">Q", recvn(s, 8))[0]
        if h[1] & 0x80:  # masked (server should not mask, but tolerate)
            recvn(s, 4)
        data += recvn(s, ln)
        if fin:
            break
    return json.loads(data)


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/cef_shot.png"
    # argv[2] is the CDP port (scripts/cef-shot.sh passes a unique port).
    # argv[3] is an optional URL substring filter; empty (default) captures
    # the first page target so redirects/canonicalization can't deselect it.
    port = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2].isdigit() else "9222"
    want = ""
    if len(sys.argv) > 3:
        want = sys.argv[3]
    elif len(sys.argv) > 2 and not sys.argv[2].isdigit():
        want = sys.argv[2]

    with urllib.request.urlopen(f"http://127.0.0.1:{port}/json", timeout=10) as r:
        targets = json.load(r)
    pages = [t for t in targets if t.get("type") == "page"]
    if want:
        pages = [t for t in pages if want in t.get("url", "")]
    if not pages:
        print("no matching page targets:", [t.get("url") for t in targets])
        sys.exit(1)
    ws_url = pages[0]["webSocketDebuggerUrl"]
    print("capturing:", pages[0].get("url"), "->", out_path)

    # ws://127.0.0.1:<port>/devtools/page/XXX
    assert ws_url.startswith("ws://")
    host_path = ws_url[5:]
    host_port, path = host_path.split("/", 1)
    # Trust the endpoint returned by our probed port; host/port come from it.
    host, ws_port = host_port.split(":")
    s = socket.create_connection((host, int(ws_port)), timeout=15)
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall(
        (
            f"GET /{path} HTTP/1.1\r\n"
            f"Host: {host}:{ws_port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        ).encode()
    )
    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += s.recv(4096)
    if b"101" not in resp.split(b"\r\n", 1)[0]:
        print("websocket upgrade failed:", resp[:200])
        sys.exit(1)

    ws_send(s, {"id": 1, "method": "Page.getLayoutMetrics"})
    ws_send(s, {"id": 2, "method": "Runtime.evaluate",
                "params": {"expression": "JSON.stringify({t: document.title, rs: document.readyState, w: window.innerWidth, h: window.innerHeight, url: location.href})"}})
    ws_send(s, {"id": 3, "method": "Network.enable"})
    pending = {1, 2, 3}
    got = {}
    net_events = []
    import time as _time
    deadline = _time.time() + 12
    s.settimeout(13)
    while pending and _time.time() < deadline:
        try:
            msg = ws_recv(s)
        except Exception as e:
            print("recv stopped:", e)
            break
        if msg.get("id") not in pending:
            if msg.get("method", "").startswith("Network."):
                net_events.append((msg.get("method"), str(msg.get("params", {}))[:160]))
            continue
        pending.discard(msg.get("id"))
        got[msg.get("id")] = msg.get("result", msg.get("error"))
    print("layout:", json.dumps(got.get(1))[:300])
    print("dom:", json.dumps(got.get(2))[:300])
    print("network events (%d):" % len(net_events))
    for m, p in net_events[:15]:
        print("  ", m, p)

    ws_send(s, {"id": 10, "method": "Page.captureScreenshot",
                "params": {"format": "png", "fromSurface": True}})
    pending = {10}
    while True:
        msg = ws_recv(s)
        if msg.get("id") not in pending:
            continue
        if "error" in msg:
            print("capture error:", json.dumps(msg["error"])[:300])
            if msg.get("id") == 10:
                # Fall back without fromSurface.
                ws_send(s, {"id": 11, "method": "Page.captureScreenshot",
                            "params": {"format": "png"}})
                pending.add(11)
            continue
        if "result" not in msg:
            continue
        img = base64.b64decode(msg["result"]["data"])
        with open(out_path, "wb") as f:
            f.write(img)
        print(f"wrote {len(img)} bytes")
        return


main()
