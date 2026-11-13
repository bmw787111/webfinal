#!/usr/bin/env bash
# Sets up a "browser in a browser" (Ultraviolet proxy + tabbed UI) on port 1267.
#
#   ./setup.sh               install and run it as a background service (starts on boot)
#   ./setup.sh --foreground  install and run it in this terminal (Ctrl+C to stop)
#   ./setup.sh --uninstall   remove the service and the install folder
#
# Settings you can override:  PORT=8080 INSTALL_DIR=/opt/browser ./setup.sh
set -euo pipefail

PORT="${PORT:-1267}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/web-browser}"
SERVICE="web-browser"
UV_REPO="https://github.com/titaniumnetwork-dev/Ultraviolet-App"
UV_COMMIT="a1762248768730d06ffa5a652345aeef7126ab63"   # pinned so updates upstream can't break setup
NODE_MAJOR=24
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="service"

for arg in "$@"; do
  case "$arg" in
    --foreground) MODE="foreground" ;;
    --uninstall)  MODE="uninstall" ;;
    -h|--help)    sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mxx  %s\033[0m\n' "$*"; exit 1; }

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else
  command -v sudo >/dev/null || die "Run this as root or install sudo."
  SUDO="sudo"
fi
HAS_SYSTEMD=0; [ -d /run/systemd/system ] && command -v systemctl >/dev/null && HAS_SYSTEMD=1

# ---------- uninstall ----------
if [ "$MODE" = "uninstall" ]; then
  if [ "$HAS_SYSTEMD" = 1 ] && [ -f "/etc/systemd/system/$SERVICE.service" ]; then
    $SUDO systemctl disable --now "$SERVICE" || true
    $SUDO rm -f "/etc/systemd/system/$SERVICE.service"
    $SUDO systemctl daemon-reload
  fi
  rm -rf "$INSTALL_DIR"
  say "Uninstalled."
  exit 0
fi

[ -f "$SCRIPT_DIR/browser.html" ] || die "browser.html must be in the same folder as setup.sh."

# ---------- 1. system packages ----------
say "Installing git, curl and tar"
if   command -v apt-get >/dev/null; then $SUDO apt-get update -y && $SUDO apt-get install -y git curl ca-certificates tar xz-utils
elif command -v dnf     >/dev/null; then $SUDO dnf install -y git curl ca-certificates tar xz
elif command -v yum     >/dev/null; then $SUDO yum install -y git curl ca-certificates tar xz
elif command -v pacman  >/dev/null; then $SUDO pacman -Sy --needed --noconfirm git curl ca-certificates tar xz
elif command -v zypper  >/dev/null; then $SUDO zypper --non-interactive install git curl ca-certificates tar xz
elif command -v apk     >/dev/null; then $SUDO apk add git curl ca-certificates tar xz bash
else warn "Unknown package manager; make sure git, curl and tar are installed."; fi

# ---------- 2. Node.js ----------
node_major() { command -v node >/dev/null && node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0; }
if [ "$(node_major)" -lt 20 ]; then
  say "Installing Node.js $NODE_MAJOR"
  case "$(uname -m)" in
    x86_64|amd64)  ARCH=x64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    armv7l)        ARCH=armv7l ;;
    *) die "Unsupported CPU: $(uname -m). Install Node.js 20+ yourself, then rerun." ;;
  esac
  BASE="https://nodejs.org/dist/latest-v${NODE_MAJOR}.x"
  FILE="$(curl -fsSL "$BASE/SHASUMS256.txt" | grep -o "node-v[0-9.]*-linux-$ARCH.tar.xz" | head -n1)"
  [ -n "$FILE" ] || die "Could not find a Node.js download for linux-$ARCH."
  TMP="$(mktemp -d)"
  curl -fsSL "$BASE/$FILE" -o "$TMP/$FILE"
  (cd "$TMP" && curl -fsSL "$BASE/SHASUMS256.txt" | grep " $FILE\$" | sha256sum -c -) || die "Node.js download failed its checksum."
  $SUDO tar -xJf "$TMP/$FILE" -C /usr/local --strip-components=1 --exclude='*.md' --exclude=LICENSE
  rm -rf "$TMP"
  hash -r
fi
echo "Using Node $(node -v), npm $(npm -v)"

# ---------- 3. Ultraviolet ----------
say "Downloading the proxy into $INSTALL_DIR"
if [ ! -d "$INSTALL_DIR/.git" ]; then
  git clone "$UV_REPO" "$INSTALL_DIR"
fi
git -C "$INSTALL_DIR" fetch --quiet origin
git -C "$INSTALL_DIR" checkout --quiet --force "$UV_COMMIT"

say "Installing dependencies (this can take a minute)"
(cd "$INSTALL_DIR" && npm install --omit=dev --no-audit --no-fund --engine-strict=false)

say "Adding the tabbed browser UI"
cp "$SCRIPT_DIR/browser.html" "$INSTALL_DIR/public/index.html"

# ---------- 4. firewall ----------
if command -v ufw >/dev/null && $SUDO ufw status 2>/dev/null | grep -q "Status: active"; then
  say "Opening port $PORT in ufw"; $SUDO ufw allow "$PORT/tcp"
elif command -v firewall-cmd >/dev/null && $SUDO firewall-cmd --state >/dev/null 2>&1; then
  say "Opening port $PORT in firewalld"
  $SUDO firewall-cmd --permanent --add-port="$PORT/tcp" && $SUDO firewall-cmd --reload
fi

# ---------- 5. run ----------
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
finish() {
  echo
  echo "------------------------------------------------------------"
  echo " Open on this computer:   http://localhost:$PORT"
  [ -n "$IP" ] && echo " Other devices:           http://$IP:$PORT  (needs HTTPS, see README)"
  echo "------------------------------------------------------------"
}

if [ "$MODE" = "foreground" ] || [ "$HAS_SYSTEMD" = 0 ]; then
  [ "$HAS_SYSTEMD" = 0 ] && warn "systemd not found, running in this terminal instead."
  finish
  cd "$INSTALL_DIR"
  PORT="$PORT" exec node src/index.js
fi

say "Creating the $SERVICE service"
$SUDO tee "/etc/systemd/system/$SERVICE.service" >/dev/null <<UNIT
[Unit]
Description=Web Browser proxy (Ultraviolet) on port $PORT
After=network-online.target
Wants=network-online.target

[Service]
User=$(id -un)
WorkingDirectory=$INSTALL_DIR
Environment=PORT=$PORT
ExecStart=$(command -v node) src/index.js
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
$SUDO systemctl daemon-reload
$SUDO systemctl enable --now "$SERVICE"
$SUDO systemctl restart "$SERVICE"

for _ in $(seq 1 20); do
  curl -fsS -o /dev/null "http://localhost:$PORT/" && break; sleep 0.5
done
curl -fsS -o /dev/null "http://localhost:$PORT/" \
  || die "Server did not start. See: sudo journalctl -u $SERVICE -n 50"

finish
echo " Logs:    sudo journalctl -u $SERVICE -f"
echo " Stop:    sudo systemctl stop $SERVICE"
echo " Remove:  ./setup.sh --uninstall"
