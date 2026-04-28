#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# mihomo + metacubexd Docker Setup Script
# Usage:
#   sudo ./mihomo-setup.sh <config-file-or-url> [--server-ip <ip>]
#
# Examples:
#   sudo ./mihomo-setup.sh ./my-config.yaml
#   sudo ./mihomo-setup.sh https://example.com/sub.yaml --server-ip 1.2.3.4
# ============================================================

# ---------- Defaults (override via env) ----------
INSTALL_DIR="${INSTALL_DIR:-/opt/mihomo}"
METACUBEXD_IMAGE="${METACUBEXD_IMAGE:-ghcr.io/metacubex/metacubexd}"
MIHOMO_IMAGE="${MIHOMO_IMAGE:-metacubex/mihomo}"
METACUBEXD_PORT="${METACUBEXD_PORT:-80}"
MIHOMO_API_PORT="${MIHOMO_API_PORT:-9090}"

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

usage() {
    cat <<EOF
Usage: $0 <config-file-or-url> [--server-ip <ip>]

Arguments:
  <config-file-or-url>   Required. Local path or http(s) URL to mihomo config.
                         Will be saved as config.yaml in ${INSTALL_DIR}.

Options:
  --server-ip <ip>       Optional. Sets DEFAULT_BACKEND_URL on metacubexd to
                         http://<ip>:${MIHOMO_API_PORT}.
  -h, --help             Show this help.
EOF
    exit "${1:-0}"
}

# ---------- Parse args ----------
CONFIG_SRC=""
SERVER_IP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --server-ip)
            [[ $# -ge 2 ]] || error "--server-ip requires a value"
            SERVER_IP="$2"
            shift 2
            ;;
        --server-ip=*)
            SERVER_IP="${1#*=}"
            shift
            ;;
        -h|--help)
            usage 0
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            [[ -z "$CONFIG_SRC" ]] || error "Only one config source allowed (got '$CONFIG_SRC' and '$1')"
            CONFIG_SRC="$1"
            shift
            ;;
    esac
done

[[ -n "$CONFIG_SRC" ]] || { warn "Missing required <config-file-or-url>"; usage 1; }

# ---------- Resolve local config to absolute path BEFORE any cd ----------
# Without this, a relative path like ./config.yaml breaks once the script cds into INSTALL_DIR below.
if [[ ! "$CONFIG_SRC" =~ ^https?:// ]]; then
    [[ -f "$CONFIG_SRC" ]] || error "Config file not found: $CONFIG_SRC (cwd: $PWD)"
    if command -v readlink >/dev/null && readlink -f / >/dev/null 2>&1; then
        CONFIG_SRC="$(readlink -f "$CONFIG_SRC")"
    else
        CONFIG_SRC="$(cd "$(dirname "$CONFIG_SRC")" && pwd)/$(basename "$CONFIG_SRC")"
    fi
fi

# ---------- Pre-flight ----------
[[ "$(id -u)" -eq 0 ]] || error "Run as root (or with sudo)."

command -v docker >/dev/null || error "Docker not installed. Install: curl -fsSL https://get.docker.com | bash"

if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    error "Docker Compose not available."
fi
info "Using compose command: ${COMPOSE_CMD}"

# ---------- Prepare install dir ----------
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# ---------- Fetch config ----------
CONFIG_DST="${INSTALL_DIR}/config.yaml"

if [[ "$CONFIG_SRC" =~ ^https?:// ]]; then
    info "Downloading config from ${CONFIG_SRC}..."
    if command -v curl >/dev/null; then
        curl -fsSL "$CONFIG_SRC" -o "$CONFIG_DST" || error "Download failed"
    elif command -v wget >/dev/null; then
        wget -qO "$CONFIG_DST" "$CONFIG_SRC" || error "Download failed"
    else
        error "Neither curl nor wget available."
    fi
else
    info "Copying ${CONFIG_SRC} -> ${CONFIG_DST}"
    cp "$CONFIG_SRC" "$CONFIG_DST"
fi

[[ -s "$CONFIG_DST" ]] || error "Config file is empty: $CONFIG_DST"

# ---------- Stop existing containers ----------
for name in metacubexd mihomo; do
    if docker ps -a --format '{{.Names}}' | grep -qw "$name"; then
        warn "Container '$name' exists. Removing..."
        docker rm -f "$name" >/dev/null 2>&1 || true
    fi
done

# ---------- Build env block for metacubexd ----------
if [[ -n "$SERVER_IP" ]]; then
    BACKEND_URL="http://${SERVER_IP}:${MIHOMO_API_PORT}"
    info "Setting DEFAULT_BACKEND_URL=${BACKEND_URL}"
    METACUBEXD_ENV="    environment:
      - DEFAULT_BACKEND_URL=${BACKEND_URL}"
else
    METACUBEXD_ENV=""
fi

# ---------- Write docker-compose.yml ----------
info "Writing docker-compose.yml to ${INSTALL_DIR}..."

cat > docker-compose.yml <<YAML
services:
  metacubexd:
    container_name: metacubexd
    image: ${METACUBEXD_IMAGE}
    restart: unless-stopped
    ports:
      - ${METACUBEXD_PORT}:80
${METACUBEXD_ENV}

  mihomo:
    container_name: mihomo
    image: ${MIHOMO_IMAGE}
    restart: unless-stopped
    network_mode: host
    cap_add:
      - ALL
    volumes:
      - ./config.yaml:/root/.config/mihomo/config.yaml:ro
YAML

# ---------- Pull & start ----------
info "Pulling images..."
${COMPOSE_CMD} pull

info "Starting containers..."
${COMPOSE_CMD} up -d

# ---------- Verify ----------
sleep 2
for name in metacubexd mihomo; do
    STATE=$(docker inspect --format='{{.State.Status}}' "$name" 2>/dev/null || echo "missing")
    if [[ "$STATE" != "running" ]]; then
        error "Container '$name' not running (state: $STATE). Check: docker logs $name"
    fi
done

info "Done."
info "  metacubexd UI: http://<host>:${METACUBEXD_PORT}"
info "  mihomo API:    http://<host>:${MIHOMO_API_PORT}"
[[ -n "$SERVER_IP" ]] && info "  Backend URL:   http://${SERVER_IP}:${MIHOMO_API_PORT}"
