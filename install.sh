#!/usr/bin/env bash
# One-shot installer: Docker + Open WebUI on Ubuntu 20.04
# Run as root on a fresh box that already has correct IP/hostname.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "==> Adding Docker apt repo"
apt-get update -qq
apt-get install -y -qq ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

echo "==> Installing Docker"
apt-get update -qq
apt-get install -y -qq \
  docker-ce docker-ce-cli containerd.io \
  docker-compose-plugin docker-buildx-plugin
systemctl enable --now docker

echo "==> Deploying Open WebUI"
mkdir -p /opt/open-webui
cd /opt/open-webui
if [ ! -f docker-compose.yml ]; then
  cp "$(dirname "$0")/docker-compose.yml" .
fi
docker compose pull
docker compose up -d

echo "==> Done. Open WebUI is at http://$(hostname -I | awk '{print $1}'):3000/"
