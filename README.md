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

## OpenClaw

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

## Install NATIVELINKE Based ON Python3 Image

```bash
curl -fsSL https://raw.githubusercontent.com/littlexia4-creator/DOCKERFILES/refs/heads/main/nativelink-ubuntu/install.sh | bash
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
