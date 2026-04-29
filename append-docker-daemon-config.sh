#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    echo "Config source not found: $CONFIG_SOURCE" >&2
    exit 1
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
    with path.open("r", encoding="utf-8") as file:
        return json.load(file)


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
