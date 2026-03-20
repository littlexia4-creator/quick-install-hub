#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# m1k1o/neko Docker Setup Script for Ubuntu
# Quick one-liner:
#   curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/quick-install-hub/refs/heads/main/neko-setup.sh | bash
# ============================================================

# ---------- Default configuration (override via env vars) ----------
NEKO_IMAGE="${NEKO_IMAGE:-m1k1o/neko:latest}"
NEKO_BROWSER="${NEKO_BROWSER:-firefox}"
NEKO_CONTAINER_NAME="${NEKO_CONTAINER_NAME:-neko-${NEKO_BROWSER}}"
NEKO_HTTP_PORT="${NEKO_HTTP_PORT:-8080}"  
NEKO_UDP_RANGE="${NEKO_UDP_RANGE:-52000-52100}"  # Changed from 52000-52100 to 52000-52100
NEKO_UDP_RANGE="${NEKO_UDP_RANGE:-52000-52100}"
NEKO_ADMIN_PASSWORD="${NEKO_ADMIN_PASSWORD:-admin}"
NEKO_USER_PASSWORD="${NEKO_USER_PASSWORD:-user}"
NEKO_SCREEN="${NEKO_SCREEN:-1920*1080@60}"
INSTALL_DIR="${INSTALL_DIR:-/opt/neko}"

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------- Auto-detect hardware resources ----------
TOTAL_MEM_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
TOTAL_CPUS=$(nproc)

# Memory: allocate 50% of total RAM to the container (min 2g, max 16g)
if [[ -z "${NEKO_MEM_LIMIT:-}" ]]; then
    HALF_MEM=$((TOTAL_MEM_MB / 2))
    if   (( HALF_MEM < 2048 )); then NEKO_MEM_LIMIT="2g"
    elif (( HALF_MEM > 16384 )); then NEKO_MEM_LIMIT="16g"
    else NEKO_MEM_LIMIT="$((HALF_MEM / 1024))g"
    fi
fi

# Shared memory: 50% of container memory (min 1g, max 4g)
if [[ -z "${NEKO_SHM_SIZE:-}" ]]; then
    MEM_NUM=${NEKO_MEM_LIMIT%g}
    SHM=$((MEM_NUM / 2))
    (( SHM < 1 )) && SHM=1
    (( SHM > 4 )) && SHM=4
    NEKO_SHM_SIZE="${SHM}g"
fi

# CPUs: allocate 50% of total cores (min 1, max 8)
if [[ -z "${NEKO_CPUS:-}" ]]; then
    HALF_CPUS=$((TOTAL_CPUS / 2))
    (( HALF_CPUS < 1 )) && HALF_CPUS=1
    (( HALF_CPUS > 8 )) && HALF_CPUS=8
    NEKO_CPUS="${HALF_CPUS}.0"
fi

info "Detected: ${TOTAL_CPUS} CPUs, ${TOTAL_MEM_MB}MB RAM"
info "Allocating: cpus=${NEKO_CPUS}, mem=${NEKO_MEM_LIMIT}, shm=${NEKO_SHM_SIZE}"

# ---------- Pre-flight checks ----------
[[ "$(id -u)" -eq 0 ]] || error "This script must be run as root (or with sudo)."

if ! command -v docker &>/dev/null; then
    error "Docker is not installed. Install it first:\n  curl -fsSL https://get.docker.com | bash"
fi

if ! docker compose version &>/dev/null && ! command -v docker-compose &>/dev/null; then
    error "Docker Compose is not available. Install Docker Compose first."
fi

# Determine compose command
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

info "Using compose command: ${COMPOSE_CMD}"

# ---------- Create install directory ----------
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# ---------- Stop existing container if running ----------
if docker ps -a --format '{{.Names}}' | grep -qw "${NEKO_CONTAINER_NAME}"; then
    warn "Container '${NEKO_CONTAINER_NAME}' already exists. Stopping and removing..."
    ${COMPOSE_CMD} down 2>/dev/null || docker rm -f "${NEKO_CONTAINER_NAME}" 2>/dev/null || true
fi

# ---------- Write docker-compose.yml ----------
info "Writing docker-compose.yml to ${INSTALL_DIR}..."

cat > docker-compose.yml <<YAML
services:
  neko:
    image: ${NEKO_IMAGE}
    restart: unless-stopped
    container_name: ${NEKO_CONTAINER_NAME}
    shm_size: '${NEKO_SHM_SIZE}'
    cpus: ${NEKO_CPUS}
    mem_limit: ${NEKO_MEM_LIMIT}
    oom_kill_disable: false

    ports:
      - "${NEKO_HTTP_PORT}:8080"
      - "${NEKO_UDP_RANGE}:${NEKO_UDP_RANGE}/udp"

    environment:
      - NEKO_BROWSER=${NEKO_BROWSER}
      - NEKO_ADMIN_PASSWORD=${NEKO_ADMIN_PASSWORD}
      - NEKO_USER_PASSWORD=${NEKO_USER_PASSWORD}
      - NEKO_ROOM_NAME=${NEKO_BROWSER}Room
      - NEKO_SCREEN=${NEKO_SCREEN}
      - NEKO_EPR=${NEKO_UDP_RANGE}

    volumes:
      - neko-data:/home/neko/.mozilla
      - neko-recordings:/var/lib/neko/recordings

volumes:
  neko-data:
  neko-recordings:
YAML

# ---------- Pull image & start ----------
info "Pulling image ${NEKO_IMAGE}..."
docker pull "${NEKO_IMAGE}"

info "Starting neko container..."
${COMPOSE_CMD} up -d

# ---------- Wait for healthy ----------
info "Waiting for container to become healthy..."
for i in $(seq 1 10); do
    STATE=$(docker inspect --format='{{.State.Status}}' "${NEKO_CONTAINER_NAME}" 2>/dev/null || echo "missing")
    if [[ "${STATE}" == "running" ]]; then
        break
    fi
    sleep 1
done

if [[ "${STATE}" != "running" ]]; then
    error "Container failed to start. Check logs: docker logs ${NEKO_CONTAINER_NAME}"
fi

# # ---------- Open firewall ports if ufw is active ----------
# if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
#     info "Opening firewall ports (ufw)..."
#     ufw allow "${NEKO_HTTP_PORT}/tcp" >/dev/null
#     ufw allow "${NEKO_UDP_RANGE}/udp" >/dev/null
# fi

# ---------- Done ----------
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
info "====================================="
info "  m1k1o/neko is running!"
info "====================================="
info "  URL:            http://${SERVER_IP}:${NEKO_HTTP_PORT}"
info "  Admin password: ${NEKO_ADMIN_PASSWORD}"
info "  User password:  ${NEKO_USER_PASSWORD}"
info "  Install dir:    ${INSTALL_DIR}"
info "====================================="
echo ""
