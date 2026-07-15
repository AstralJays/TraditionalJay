#!/usr/bin/env bash
# Download marshalsec for full Log4Shell RCE demos (sandbox only).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAR="${DIR}/marshalsec-0.0.3-SNAPSHOT-all.jar"
URL="https://github.com/mbechler/marshalsec/releases/download/v0.0.3/marshalsec-0.0.3-SNAPSHOT-all.jar"

if [[ -f "$JAR" ]]; then
  echo "==> marshalsec already present: $JAR"
  exit 0
fi

echo "==> Downloading marshalsec (LDAP reference server)…"
curl -fsSL "$URL" -o "$JAR"
echo "==> Saved $JAR"
