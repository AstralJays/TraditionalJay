#!/usr/bin/env python3
"""Minimal LDAP banner listener for Log4Shell workshop demos.

Probe-only: proves the vulnerable app dialed out. For full RCE in the sandbox
use tools/run-log4shell-ldap.sh instead.

  python3 tools/ldap-listen.py --port 1389
"""
from __future__ import annotations

import argparse
import socket
from datetime import datetime, timezone


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=1389)
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((args.host, args.port))
    sock.listen(5)
    print(f"[*] LDAP listen (banner only) on {args.host}:{args.port}", flush=True)
    print("[*] Waiting for Log4Shell JNDI callbacks…", flush=True)

    while True:
        conn, addr = sock.accept()
        ts = datetime.now(timezone.utc).strftime("%H:%M:%S")
        print(f"[{ts}] connection from {addr[0]}:{addr[1]}", flush=True)
        try:
            data = conn.recv(4096)
            if data:
                print(f"         first bytes ({len(data)}): {data[:64]!r}", flush=True)
        finally:
            conn.close()


if __name__ == "__main__":
    main()
