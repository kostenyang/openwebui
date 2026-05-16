#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# Open WebUI 客戶端一鍵部署(Ubuntu 20.04/22.04/24.04)
# Usage:
#   cp config.env.example config.env  # 改填客戶環境
#   sudo bash install.sh               # 跑全部
#   sudo bash install.sh --skip-network  # 不動 IP/hostname
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${HERE}/config.env"
LIB="${HERE}/lib"

# ─── parse args ──────────────────────────────────────────────────────
SKIP_NETWORK=false
SKIP_DOCKER=false
SKIP_OPENWEBUI=false
SKIP_LLM=false
SKIP_MCP=false
for arg in "$@"; do
  case "$arg" in
    --skip-network)    SKIP_NETWORK=true ;;
    --skip-docker)     SKIP_DOCKER=true ;;
    --skip-openwebui)  SKIP_OPENWEBUI=true ;;
    --skip-llm)        SKIP_LLM=true ;;
    --skip-mcp)        SKIP_MCP=true ;;
    -h|--help)
      sed -n '2,9p' "$0"; exit 0 ;;
    *)
      echo "unknown arg: $arg"; exit 1 ;;
  esac
done

# ─── load config ─────────────────────────────────────────────────────
if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: $CONFIG not found. Copy config.env.example to config.env first."
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG"

# ─── must be root ────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo bash install.sh)"
  exit 1
fi

step() { echo; echo "════════════════════════════════════════"; echo "▶ $*"; echo "════════════════════════════════════════"; }

# ─── [1] network ─────────────────────────────────────────────────────
if ! $SKIP_NETWORK && [[ -n "${STATIC_IP:-}" ]]; then
  step "[1/5] Network: setting static IP $STATIC_IP, hostname $HOSTNAME"
  bash "$LIB/01-network.sh"
else
  echo "▷ Skip network"
fi

# ─── [2] docker ──────────────────────────────────────────────────────
if ! $SKIP_DOCKER; then
  step "[2/5] Docker install"
  bash "$LIB/02-docker.sh"
else
  echo "▷ Skip docker"
fi

# ─── [3] open-webui + mcpo compose ───────────────────────────────────
if ! $SKIP_OPENWEBUI; then
  step "[3/5] Deploy Open WebUI + mcpo"
  bash "$LIB/03-openwebui.sh"
else
  echo "▷ Skip openwebui deploy"
fi

# ─── [4] LLM providers (DB injection) ────────────────────────────────
if ! $SKIP_LLM; then
  step "[4/5] Inject LLM providers"
  bash "$LIB/04-llm.sh"
else
  echo "▷ Skip LLM providers"
fi

# ─── [5] MCP Tool Server registration ────────────────────────────────
if ! $SKIP_MCP && [[ "${MCPO_ENABLED:-false}" == "true" ]]; then
  step "[5/5] Register MCP Tool Server in Open WebUI"
  bash "$LIB/05-mcp-tool.sh"
else
  echo "▷ Skip MCP Tool registration"
fi

# ─── summary ─────────────────────────────────────────────────────────
IP_NOW="$(hostname -I | awk '{print $1}')"
echo
echo "════════════════════════════════════════"
echo "✓ Done."
echo "  Open WebUI : http://${IP_NOW}:${OPENWEBUI_PORT}/"
if [[ "${MCPO_ENABLED:-false}" == "true" ]]; then
  echo "  mcpo       : http://${IP_NOW}:${MCPO_PORT}/${UPSTREAM_MCP_NAME}/openapi.json"
fi
echo "════════════════════════════════════════"
echo "  → 第一個註冊的帳號自動成為 admin,記得搶。"
