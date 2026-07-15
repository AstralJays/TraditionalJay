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

install_from_checkout() {
  local root="$1"
  echo "==> Building from checkout: $root"
  apt-get install -y maven
  (cd "$root/app" && mvn -q -DskipTests package)
  cp "$root/app/target/traditional-jay-"*.jar "$APP_DIR/app.jar"
  rm -rf /root/.m2
  apt-get clean -y || true
}

install_from_source() {
  echo "==> Building from source (${REPO_URL}@${REPO_REF})"
  apt-get install -y git maven
  rm -rf /tmp/TraditionalJay-src
  git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" /tmp/TraditionalJay-src
  install_from_checkout /tmp/TraditionalJay-src
  rm -rf /tmp/TraditionalJay-src
}

# Prefer the repo that invoked us (cloud-init clones to /tmp/tj) so replace
# always ships the branch tip — not a stale GitHub Release JAR.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -d "${REPO_ROOT}/app/src" ]]; then
  install_from_checkout "$REPO_ROOT"
elif ! install_from_release; then
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
ExecStart=/usr/bin/java -Dcom.sun.jndi.ldap.object.trustURLCodebase=true org.springframework.boot.loader.JarLauncher --server.port=$LISTEN_PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now traditionaljay.service
echo "TraditionalJay listening on :$LISTEN_PORT"

# On-box Log4Shell attacker (LDAP + Exploit.class HTTP) so /security works with
# callback 127.0.0.1:1389 — no inbound ports needed on the operator laptop.
install_onbox_log4shell() {
  local tools_src="${REPO_ROOT}/tools"
  if [[ ! -f "${tools_src}/ldap-ref-server.py" ]]; then
    echo "==> tools/ missing — skipping on-box Log4Shell attacker"
    return 0
  fi
  echo "==> Installing on-box Log4Shell attacker (127.0.0.1:1389 + :8000)"
  apt-get install -y python3
  mkdir -p "$APP_DIR/tools/exploit"
  cp "$tools_src/ldap-ref-server.py" "$tools_src/run-log4shell-onbox.sh" "$APP_DIR/tools/"
  cp "$tools_src/exploit/Exploit.java" "$APP_DIR/tools/exploit/"
  chmod +x "$APP_DIR/tools/run-log4shell-onbox.sh" "$APP_DIR/tools/ldap-ref-server.py"
  javac -d "$APP_DIR/tools/exploit" "$APP_DIR/tools/exploit/Exploit.java"
  chown -R "$APP_USER:$APP_USER" "$APP_DIR/tools"

  cat >/etc/systemd/system/traditionaljay-log4shell.service <<EOF
[Unit]
Description=TraditionalJay on-box Log4Shell LDAP/HTTP attacker (workshop)
After=network.target traditionaljay.service

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$APP_DIR/tools
ExecStart=$APP_DIR/tools/run-log4shell-onbox.sh
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now traditionaljay-log4shell.service
  echo "==> On-box Log4Shell attacker listening on 127.0.0.1:1389"
}
install_onbox_log4shell

# Optional host sensor — skip if cloud-init already installed it.
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
