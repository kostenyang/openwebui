#!/usr/bin/env bash
# 部署 Open WebUI(+ mcpo,如果啟用)
set -euo pipefail
source "$(dirname "$0")/../config.env"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# mcpo config + cert
if [[ "${MCPO_ENABLED:-false}" == "true" ]]; then
  mkdir -p mcpo/certs
  if [[ -n "${UPSTREAM_MCP_CERT_FILE:-}" && -f "$UPSTREAM_MCP_CERT_FILE" ]]; then
    cp "$UPSTREAM_MCP_CERT_FILE" mcpo/certs/upstream.pem
    SSL_LINES=$(printf '      - SSL_CERT_FILE=/certs/upstream.pem\n      - REQUESTS_CA_BUNDLE=/certs/upstream.pem')
    CERT_VOL='      - ./mcpo/certs/upstream.pem:/certs/upstream.pem:ro'
  else
    SSL_LINES=""
    CERT_VOL=""
  fi

  HEADERS_JSON="{}"
  if [[ -n "${UPSTREAM_MCP_BEARER:-}" ]]; then
    HEADERS_JSON="{\"Authorization\": \"Bearer ${UPSTREAM_MCP_BEARER}\"}"
  fi
  cat > mcpo/config.json <<EOF
{
  "mcpServers": {
    "${UPSTREAM_MCP_NAME}": {
      "type": "${UPSTREAM_MCP_TYPE}",
      "url": "${UPSTREAM_MCP_URL}",
      "headers": ${HEADERS_JSON}
    }
  }
}
EOF
  chmod 600 mcpo/config.json
fi

# docker-compose.yml
{
cat <<EOF
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: always
    ports:
      - "${OPENWEBUI_PORT}:8080"
    volumes:
      - open-webui:/app/backend/data
    environment:
      - WEBUI_NAME=${WEBUI_NAME}
EOF

if [[ "${MCPO_ENABLED:-false}" == "true" ]]; then
cat <<EOF

  mcpo:
    image: ghcr.io/open-webui/mcpo:main
    container_name: mcpo
    restart: always
    ports:
      - "${MCPO_PORT}:8000"
    volumes:
      - ./mcpo/config.json:/app/config.json:ro
${CERT_VOL}
    environment:
${SSL_LINES}
    command:
      - "--host"
      - "0.0.0.0"
      - "--port"
      - "8000"
      - "--api-key"
      - "${MCPO_API_KEY}"
      - "--config"
      - "/app/config.json"
EOF
fi

cat <<EOF

volumes:
  open-webui:
EOF
} > docker-compose.yml

# 拉 image + 起
docker compose pull
docker compose up -d

# 等 open-webui healthy(最多 90 秒)
echo -n "  waiting for open-webui healthy"
for i in $(seq 1 45); do
  s=$(docker inspect -f '{{.State.Health.Status}}' open-webui 2>/dev/null || echo none)
  if [[ "$s" == "healthy" ]]; then echo " ✓"; break; fi
  echo -n "."; sleep 2
done

docker compose ps
