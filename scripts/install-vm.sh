#!/usr/bin/env bash
# Install TraditionalJay on a fresh Ubuntu VM (cloud-init / manual).
set -euo pipefail

APP_USER="${APP_USER:-traditionaljay}"
APP_DIR="${APP_DIR:-/opt/traditionaljay}"
REPO_URL="${REPO_URL:-https://github.com/AstralJays/TraditionalJay.git}"
REPO_REF="${REPO_REF:-main}"
LISTEN_PORT="${LISTEN_PORT:-8080}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y openjdk-11-jdk maven git curl

id -u "$APP_USER" >/dev/null 2>&1 || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
mkdir -p "$APP_DIR"
cd /tmp
rm -rf TraditionalJay-src
git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" TraditionalJay-src
cd TraditionalJay-src/app
mvn -q -DskipTests package
cp target/traditional-jay-*.jar "$APP_DIR/app.jar"
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
