#!/usr/bin/env bash
# On-box C2 banner listener so reverse-shell demos succeed with 127.0.0.1:4444.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$DIR/c2-listen.py" --host 127.0.0.1 --port "${C2_PORT:-4444}"
