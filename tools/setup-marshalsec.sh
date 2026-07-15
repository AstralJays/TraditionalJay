#!/usr/bin/env bash
# Download marshalsec for full Log4Shell RCE demos (sandbox only).
# Upstream has no GitHub Release artifacts — pull a known built all-jar.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAR="${DIR}/marshalsec-0.0.3-SNAPSHOT-all.jar"
# kozmer/log4j-shell-poc vendors a built marshalsec all-jar (mbechler has no releases).
URL="https://raw.githubusercontent.com/kozmer/log4j-shell-poc/main/target/marshalsec-0.0.3-SNAPSHOT-all.jar"

if [[ -f "$JAR" && -s "$JAR" ]]; then
  echo "==> marshalsec already present: $JAR"
  exit 0
fi

echo "==> Downloading marshalsec (~40MB LDAP reference server)…"
curl -fL --progress-bar "$URL" -o "${JAR}.partial"
mv "${JAR}.partial" "$JAR"
echo "==> Saved $JAR ($(du -h "$JAR" | awk '{print $1}'))"
