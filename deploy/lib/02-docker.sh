#!/usr/bin/env bash
# 裝 Docker CE + compose plugin。Ubuntu 20/22/24 都通。
# Focal (20.04) EOL,要繞過 get-docker.sh 失敗的 docker-model-plugin。
set -euo pipefail

if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
  echo "  docker already installed: $(docker --version)"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive

# Docker apt repo
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq \
  docker-ce docker-ce-cli containerd.io \
  docker-compose-plugin docker-buildx-plugin

systemctl enable --now docker
echo "  installed: $(docker --version) | $(docker compose version)"
