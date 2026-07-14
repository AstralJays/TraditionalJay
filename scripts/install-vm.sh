#!/usr/bin/env bash
# Install TraditionalJay on a fresh Ubuntu VM (cloud-init / manual).
set -euo pipefail

APP_USER="${APP_USER:-traditionaljay}"
APP_DIR="${APP_DIR:-/opt/traditionaljay}"
REPO_URL="${REPO_URL:-https://github.com/AstralJays/TraditionalJay.git}"
REPO_REF="${REPO_REF:-main}"
REPO_SLUG="${REPO_SLUG:-AstralJays/TraditionalJay}"
RELEASE_TAG="${RELEASE_TAG:-}"   # e.g. v0.1.0 — empty = latest release, else build from source
LISTEN_PORT="${LISTEN_PORT:-8080}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y openjdk-11-jdk curl ca-certificates

id -u "$APP_USER" >/dev/null 2>&1 || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
mkdir -p "$APP_DIR"

install_from_release() {
  local api asset url
  if [[ -n "$RELEASE_TAG" ]]; then
    api="https://api.github.com/repos/${REPO_SLUG}/releases/tags/${RELEASE_TAG}"
  else
    api="https://api.github.com/repos/${REPO_SLUG}/releases/latest"
  fi
  asset=$(curl -fsSL "$api" | python3 -c '
import json,sys
rel=json.load(sys.stdin)
for a in rel.get("assets", []):
  if a["name"].endswith(".jar") and "traditional-jay" in a["name"]:
    print(a["browser_download_url"]); break
' 2>/dev/null || true)
  [[ -n "$asset" ]] || return 1
  echo "==> Downloading release JAR: $asset"
  curl -fsSL "$asset" -o "$APP_DIR/app.jar"
}

install_from_source() {
  echo "==> Building from source (${REPO_URL}@${REPO_REF})"
  apt-get install -y git maven
  rm -rf /tmp/TraditionalJay-src
  git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" /tmp/TraditionalJay-src
  (cd /tmp/TraditionalJay-src/app && mvn -q -DskipTests package)
  cp /tmp/TraditionalJay-src/app/target/traditional-jay-*.jar "$APP_DIR/app.jar"
}

if ! install_from_release; then
  echo "==> No usable GitHub Release JAR; falling back to Maven build"
  install_from_source
fi

chown -R "$APP_USER:$APP_USER" "$APP_DIR"

cat >/etc/systemd/system/traditionaljay.service <<EOF
[Unit]
Description=TraditionalJay (Log4Shell workshop app)
After=network.target

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$APP_DIR
Environment=SERVER_PORT=$LISTEN_PORT
ExecStart=/usr/bin/java -jar $APP_DIR/app.jar --server.port=$LISTEN_PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now traditionaljay.service
echo "TraditionalJay listening on :$LISTEN_PORT"
