#! /usr/bin/env python3
"""Banner TCP listener for TraditionalJay reverse-shell / C2 demos.

  python3 tools/c2-listen.py --port 4444

Accepts connections and prints the first bytes (e.g. TraditionalJay-revshell).
Does not spawn an interactive operator shell — proves outbound dial-out from the VM.
"""
from __future__ import annotations

import argparse
import socket
from datetime import datetime, timezone


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=4444)
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((args.host, args.port))
    sock.listen(5)
    print(f"[*] C2 listen (banner) on {args.host}:{args.port}", flush=True)
    print("[*] Waiting for reverse-shell dial-outs…", flush=True)

    while True:
        conn, addr = sock.accept()
        ts = datetime.now(timezone.utc).strftime("%H:%M:%S")
        print(f"[{ts}] connection from {addr[0]}:{addr[1]}", flush=True)
        try:
            data = conn.recv(4096)
            if data:
                print(f"         first bytes ({len(data)}): {data[:120]!r}", flush=True)
            conn.sendall(b"TraditionalJay C2 ack\n")
        finally:
            conn.close()


if __name__ == "__main__":
    main()
