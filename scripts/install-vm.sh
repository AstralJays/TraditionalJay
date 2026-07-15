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
  rm -rf /tmp/TraditionalJay-src /root/.m2
  apt-get clean -y || true
}

if ! install_from_release; then
  echo "==> No usable GitHub Release JAR; falling back to Maven build"
  install_from_source
fi

# Explode the Spring Boot fat JAR onto disk so host / agentless SCA can see
# nested deps as real files (esp. log4j-core-2.14.1.jar → CVE-2021-44228).
# Running only `java -jar app.jar` leaves Log4j inside BOOT-INF/lib inside a
# zip, which some scanners miss even when they catch sibling nested jars.
explode_fat_jar() {
  echo "==> Exploding app.jar for SCA-visible BOOT-INF/lib (Log4Shell workshop)"
  rm -rf "$APP_DIR/BOOT-INF" "$APP_DIR/META-INF" "$APP_DIR/org"
  (cd "$APP_DIR" && jar xf app.jar)
  # Keep app.jar for rebuilds / fallback; runtime uses exploded JarLauncher.
  test -f "$APP_DIR/BOOT-INF/lib/log4j-core-2.14.1.jar"
  test -f "$APP_DIR/org/springframework/boot/loader/JarLauncher.class"
}
explode_fat_jar

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
ExecStart=/usr/bin/java org.springframework.boot.loader.JarLauncher --server.port=$LISTEN_PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now traditionaljay.service
echo "TraditionalJay listening on :$LISTEN_PORT"

# Optional host sensor — skip if cloud-init already installed it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f /etc/upwind/agent.yaml ]]; then
  if [[ -x "${SCRIPT_DIR}/install-upwind-sensor.sh" ]]; then
    bash "${SCRIPT_DIR}/install-upwind-sensor.sh"
  elif [[ -x /tmp/install-upwind-sensor.sh ]]; then
    bash /tmp/install-upwind-sensor.sh
  elif [[ -n "${REPO_URL:-}" && -n "${REPO_REF:-}" ]]; then
    curl -fsSL "${REPO_URL}/raw/${REPO_REF}/scripts/install-upwind-sensor.sh" \
      -o /tmp/install-upwind-sensor.sh || true
    if [[ -s /tmp/install-upwind-sensor.sh ]]; then
      chmod +x /tmp/install-upwind-sensor.sh
      bash /tmp/install-upwind-sensor.sh
    fi
  fi
else
  echo "==> Upwind sensor already installed — skipping"
fi
