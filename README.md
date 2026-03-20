# Quick Install Hub

One-line commands to quickly install useful packages and services.

## Proxy Server

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/DOCKERFILES/refs/heads/main/proxy-server/quick-start.sh | bash
```

## Docker (Ubuntu)

Install Docker CE with Docker Compose on Ubuntu:

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/quick-install-hub/refs/heads/main/ubuntu-docker-install-start.sh | bash
```

## Neko (Remote Browser)

Deploy [m1k1o/neko](https://github.com/m1k1o/neko) — a self-hosted virtual browser in Docker. Auto-detects CPU/RAM and allocates resources accordingly.

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/quick-install-hub/refs/heads/main/neko-setup.sh | bash
```

Custom browser and passwords:

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/quick-install-hub/refs/heads/main/neko-setup.sh \
  | NEKO_BROWSER=chromium NEKO_ADMIN_PASSWORD=secret NEKO_USER_PASSWORD=guest bash
```

## OpenClaw

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```