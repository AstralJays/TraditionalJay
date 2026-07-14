#!/usr/bin/env bash
# Install Upwind host sensor on the VM (optional — skipped if creds unset).
set -euo pipefail

if [[ -z "${UPWIND_CLIENT_ID:-}" || -z "${UPWIND_CLIENT_SECRET:-}" ]]; then
  echo "==> UPWIND_CLIENT_ID / UPWIND_CLIENT_SECRET not set — skipping Upwind sensor"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl ca-certificates

EXTRA_CONFIG="${UPWIND_AGENT_EXTRA_CONFIG:-scanner-v2=true}"

echo "==> Installing Upwind sensor (extra config: ${EXTRA_CONFIG})"
curl -fsSL https://get.upwind.io/sensor.sh | \
  UPWIND_CLIENT_ID="$UPWIND_CLIENT_ID" \
  UPWIND_CLIENT_SECRET="$UPWIND_CLIENT_SECRET" \
  UPWIND_AGENT_EXTRA_CONFIG="$EXTRA_CONFIG" \
  bash -s

echo "==> Upwind sensor install finished"
