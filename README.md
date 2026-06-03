# Quick Install Hub

One-line commands to quickly install useful packages and services.

## Proxy Server

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/DOCKERFILES/refs/heads/main/proxy-server/quick-start.sh | bash
```

## Docker (Ubuntu)

Install Docker CE with Docker Compose on Ubuntu:

```bash
curl -fsSL https://get.docker.com | bash
```

## Neko (Remote Browser)

Deploy [m1k1o/neko](https://github.com/m1k1o/neko) — a self-hosted virtual browser in Docker. Auto-detects CPU/RAM and allocates resources accordingly.

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/quick-install-hub/refs/heads/main/neko-setup.sh | bash
```

Custom ip:

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/quick-install-hub/refs/heads/main/neko-setup.sh \
  | SERVER_IP=38.165.43.231 bash
```

Custom browser and passwords:

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/quick-install-hub/refs/heads/main/neko-setup.sh \
  | NEKO_BROWSER=chromium NEKO_ADMIN_PASSWORD=secret NEKO_USER_PASSWORD=guest bash
```

Route the browser through a proxy (e.g. a [Mihomo](#mihomo-clash-compatible-proxy) mixed-port). The setting is stored in a host-mounted Firefox policies file, so it **survives container restart/recreate**, and a `neko-proxy` toggle command is installed:

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/quick-install-hub/refs/heads/main/neko-setup.sh \
  | NEKO_PROXY=11.160.226.174:7890 bash
```

Enable/disable at runtime:

```bash
sudo neko-proxy on       # route browser through the proxy
sudo neko-proxy off      # direct, no proxy
sudo neko-proxy status   # show current state
```

> Proxy auto-config currently supports `NEKO_BROWSER=firefox`. Customize the no-proxy list with `NEKO_PROXY_BYPASS` (default: `localhost, 127.0.0.1, <server-ip>`).

## Mihomo (Clash-compatible Proxy)

Deploy [mihomo](https://github.com/MetaCubeX/mihomo) + [metacubexd](https://github.com/MetaCubeX/metacubexd) dashboard via Docker. Pass a local config file or subscription URL; saved as `config.yaml`.

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/quick-install-hub/refs/heads/main/mihomo-setup.sh \
  | bash -s -- https://example.com/sub.yaml
```

With dashboard backend IP (sets `DEFAULT_BACKEND_URL` on metacubexd):

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/quick-install-hub/refs/heads/main/mihomo-setup.sh \
  | bash -s -- https://example.com/sub.yaml --server-ip 38.165.43.231
```

Local config file:

```bash
./mihomo-setup.sh ./my-config.yaml --server-ip 38.165.43.231
```

## Docker Registry Mirrors

Merge `accelerating-docker-hub.json` into the Docker daemon config to add registry mirrors. Auto-detects target path (`/etc/docker/daemon.json` on Linux, `~/.docker/config.json` on macOS), backs up existing config, merges `registry-mirrors` / `insecure-registries` lists without duplicates, then restarts Docker.

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/littlexia4-creator/quick-install-hub@main/append-docker-config.sh | sudo bash 
```

Download first then execute

```bash
wget https://cdn.jsdelivr.net/gh/littlexia4-creator/quick-install-hub@main/append-docker-config.sh
sudo sh ./append-docker-config.sh
```

Skip the auto-restart:

```bash
sudo SKIP_RESTART=1 ./append-docker-config.sh
```

## OpenClaw

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

## Install NATIVELINKE Based ON Python3 Image

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/DOCKERFILES/refs/heads/main/nativelink/nativelink-ubuntu/install.sh  | bash
```
```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/DOCKERFILES/refs/heads/main/nativelink/nativelink-python/install.sh  | bash
```
```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/DOCKERFILES/refs/heads/main/nativelink/nativelink-gcc/install.sh  | bash
```
```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/DOCKERFILES/refs/heads/main/nativelink/nativelink-osxcross-ubuntu/install.sh  | bash
```

## Deploy NATIVELINKE Server (CAS + Scheduler)
On the main Linux server:

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/nativelink-deploy/main/install.sh | bash -s -- server
```

## Deploy NATIVELINKE Worker
On any additional Linux server:

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/nativelink-deploy/main/install.sh | bash -s -- worker <SERVER_IP>
```

Replace <SERVER_IP> with the IP of the server running CAS + Scheduler.
