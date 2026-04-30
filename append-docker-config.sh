#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]:-}"

# Bootstrap when piped via `curl ... | bash` — no script file on disk and
# accelerating-docker-hub.json missing alongside it. Download both from the
# same source URL and re-exec the on-disk copy.
if [[ -z "$SCRIPT_PATH" || ! -f "$SCRIPT_PATH" ]]; then
    REPO_BASE="${REPO_BASE:-https://cdn.jsdelivr.net/gh/littlexia4-creator/quick-install-hub@main}"
    bootstrap_dir="$(mktemp -d)"
    curl -fsSL "${REPO_BASE}/append-docker-daemon-config.sh" -o "${bootstrap_dir}/append-docker-daemon-config.sh"
    curl -fsSL "${REPO_BASE}/accelerating-docker-hub.json" -o "${bootstrap_dir}/accelerating-docker-hub.json"
    chmod +x "${bootstrap_dir}/append-docker-daemon-config.sh"
    exec bash "${bootstrap_dir}/append-docker-daemon-config.sh" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CONFIG_SOURCE="${SCRIPT_DIR}/accelerating-docker-hub.json"
TARGET_PATH="${1:-}"

usage() {
    cat <<'EOF'
Usage:
  ./append-docker-daemon-config.sh [target-json]

Defaults:
  source-json: accelerating-docker-hub.json next to this script
  target-json:
    Linux: /etc/docker/daemon.json
    macOS: ~/.docker/config.json
EOF
}

detect_target_path() {
    case "$(uname -s)" in
        Linux)
            printf '%s\n' "/etc/docker/daemon.json"
            ;;
        Darwin)
            printf '%s\n' "${HOME}/.docker/config.json"
            ;;
        *)
            echo "Unsupported platform: $(uname -s)" >&2
            echo "Pass a target JSON path explicitly as the first argument." >&2
            exit 1
            ;;
    esac
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ -z "$TARGET_PATH" ]]; then
    TARGET_PATH="$(detect_target_path)"
fi

if [[ ! -f "$CONFIG_SOURCE" ]]; then
    REPO_BASE="${REPO_BASE:-https://cdn.jsdelivr.net/gh/littlexia4-creator/quick-install-hub@main}"
    echo "fetching from $REPO_BASE ..." >&2
    fetched_json="$(mktemp)"
    if ! curl -fsSL "${REPO_BASE}/accelerating-docker-hub.json" -o "$fetched_json"; then
        rm -f "$fetched_json"
        echo "Failed to download accelerating-docker-hub.json from $REPO_BASE" >&2
        exit 1
    fi
    CONFIG_SOURCE="$fetched_json"
fi

if [[ "$TARGET_PATH" == "/etc/"* && "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "This script must run as root to update $TARGET_PATH." >&2
    echo "Try: sudo $0" >&2
    exit 1
fi

target_dir="$(dirname "$TARGET_PATH")"
mkdir -p "$target_dir"

backup_path=""
if [[ -f "$TARGET_PATH" ]]; then
    backup_path="${TARGET_PATH}.bak.$(date +%Y%m%d%H%M%S)"
fi
tmp_path="$(mktemp)"

cleanup() {
    rm -f "$tmp_path"
    [[ -n "${fetched_json:-}" ]] && rm -f "$fetched_json"
}
trap cleanup EXIT

python3 - "$TARGET_PATH" "$CONFIG_SOURCE" "$tmp_path" <<'PY'
import json
import sys
from pathlib import Path

target_path = Path(sys.argv[1])
source_path = Path(sys.argv[2])
tmp_path = Path(sys.argv[3])


def load_json(path):
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8").strip()
    if not text:
        return {}
    return json.loads(text)


def merge_unique(existing, incoming):
    result = []
    seen = set()
    for value in [*existing, *incoming]:
        if value not in seen:
            result.append(value)
            seen.add(value)
    return result


target_config = load_json(target_path)
source_config = load_json(source_path)

if not isinstance(target_config, dict):
    raise SystemExit(f"{target_path} must contain a JSON object")
if not isinstance(source_config, dict):
    raise SystemExit(f"{source_path} must contain a JSON object")

for key, value in source_config.items():
    if key in {"registry-mirrors", "insecure-registries"}:
        if not isinstance(value, list):
            raise SystemExit(f"{source_path} field '{key}' must be a list")
        current = target_config.get(key, [])
        if not isinstance(current, list):
            raise SystemExit(f"{target_path} field '{key}' already exists but is not a list")
        target_config[key] = merge_unique(current, value)
    else:
        target_config[key] = value

with tmp_path.open("w", encoding="utf-8") as file:
    json.dump(target_config, file, indent=4)
    file.write("\n")
PY

if [[ -n "$backup_path" ]]; then
    cp "$TARGET_PATH" "$backup_path"
fi
install -m 0644 "$tmp_path" "$TARGET_PATH"

echo "Merged $CONFIG_SOURCE into $TARGET_PATH"
if [[ -n "$backup_path" ]]; then
    echo "Backup saved to $backup_path"
else
    echo "Created $TARGET_PATH"
fi

if [[ "${SKIP_RESTART:-0}" == "1" ]]; then
    echo "SKIP_RESTART=1 set; not restarting Docker."
    exit 0
fi

restart_docker_linux() {
    if command -v systemctl >/dev/null 2>&1; then
        echo "Restarting Docker via systemctl..."
        systemctl restart docker
        return 0
    fi
    if command -v service >/dev/null 2>&1; then
        echo "Restarting Docker via service..."
        service docker restart
        return 0
    fi
    echo "No systemctl or service found; restart Docker manually." >&2
    return 1
}

restart_docker_darwin() {
    if ! command -v osascript >/dev/null 2>&1; then
        echo "osascript not found; restart Docker Desktop manually." >&2
        return 1
    fi
    echo "Restarting Docker Desktop..."
    osascript -e 'quit app "Docker"' >/dev/null 2>&1 || true
    sleep 2
    open -a Docker
}

case "$(uname -s)" in
    Linux)
        restart_docker_linux
        ;;
    Darwin)
        restart_docker_darwin
        ;;
    *)
        echo "Unknown platform; restart Docker manually." >&2
        ;;
esac
