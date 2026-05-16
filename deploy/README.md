# Open WebUI 客戶端部署包

一個資料夾、一個 script、一個 config 檔。SCP 過去客戶機器,改 `config.env`,跑 `install.sh` 完事。

## 快速使用

```bash
# 1. 把整個 deploy/ scp 到客戶機器
scp -r deploy/ root@<customer-host>:/root/

# 2. 在客戶機器上
ssh root@<customer-host>
cd /root/deploy
cp config.env.example config.env
vim config.env                # 改填客戶環境(見下方)

# 3. 一鍵跑
sudo bash install.sh

# 跑完看到:
# ✓ Done.
#   Open WebUI : http://<ip>:3000/
#   mcpo       : http://<ip>:8000/<mcp-name>/openapi.json
```

## 階段控制(可分段跑)

```bash
sudo bash install.sh --skip-network    # 不動 IP/hostname
sudo bash install.sh --skip-docker     # Docker 已裝
sudo bash install.sh --skip-openwebui  # 只灌 LLM key / 註冊 tool
sudo bash install.sh --skip-llm        # 不灌 LLM provider
sudo bash install.sh --skip-mcp        # 不註冊 Tool Server
```

階段:

| 階段 | 做什麼 | Skip 條件 |
| --- | --- | --- |
| **1. network** | 設靜態 IP、hostname、netplan、防 cloud-init 重設 | `--skip-network` 或 `STATIC_IP=""` |
| **2. docker** | 裝 Docker CE + compose plugin | `--skip-docker` 或已裝 |
| **3. openwebui** | 起 Open WebUI(+ mcpo 若啟用)docker compose | `--skip-openwebui` |
| **4. llm** | 把 OpenAI/Gemini key 寫進 config DB,Anthropic 灌 Function | `--skip-llm` 或所有 key 都空 |
| **5. mcp-tool** | 把 mcpo 註冊成 admin 的 Tool Server | `--skip-mcp` 或 `MCPO_ENABLED=false` |

> ⚠️ 階段 4 / 5 需要 admin user 存在。**第一次部署順序**:
> 1. 跑 `install.sh --skip-llm --skip-mcp`(階段 1-3,Open WebUI 起來)
> 2. 開瀏覽器 `http://<ip>:3000/` **註冊一個 admin 帳號**
> 3. 再跑 `install.sh --skip-network --skip-docker --skip-openwebui`(階段 4-5)

或一次跑完(階段 4/5 會說「no admin user yet」自動跳過),註冊完再跑一次階段 4/5。

## config.env 範例

最常見的兩種情境:

### 情境 A:純 Open WebUI + Gemini(無 MCP)

```bash
STATIC_IP="10.20.30.40/24"
GATEWAY="10.20.30.1"
DNS_SERVERS="10.20.30.1,8.8.8.8"
HOSTNAME="openwebui.customer.local"

MCPO_ENABLED=false

GEMINI_API_KEY="AIza..."
```

### 情境 B:Open WebUI + mcpo 接客戶的 MCP server

```bash
STATIC_IP="10.20.30.40/24"
GATEWAY="10.20.30.1"
HOSTNAME="openwebui.customer.local"

MCPO_ENABLED=true
MCPO_API_KEY="$(openssl rand -hex 16)"
UPSTREAM_MCP_NAME="customer-mcp"
UPSTREAM_MCP_TYPE="sse"
UPSTREAM_MCP_URL="https://10.20.30.50:7000/sse"
UPSTREAM_MCP_BEARER="<上游 MCP 的 token>"
UPSTREAM_MCP_CERT_FILE="/root/customer-mcp.pem"   # 自簽 cert

OPENAI_API_KEY="sk-..."
```

## 注意事項 / 踩雷

| 情境 | 處理 |
| --- | --- |
| `STATIC_IP` 改了之後 SSH 斷線 | 正常,script 用 `nohup` detach `netplan apply`,你開新 SSH 連新 IP 接著跑 |
| Ubuntu 20.04 上 `get-docker.sh` 失敗 | script 已改用 `apt install`,繞過 `docker-model-plugin` 套件問題 |
| 客戶 MCP 是自簽 cert | 把 cert.pem 放在客戶機器上,`UPSTREAM_MCP_CERT_FILE` 指到絕對路徑 |
| 客戶 MCP cert CN-only 沒 SAN | 重生有 SAN 的 cert(參考主 README §7.2) |
| 重跑 script 想刷掉 LLM key | 安全:`04-llm.sh` 會 `DELETE FROM function WHERE id='anthropic'` 再 INSERT,並 overwrite `config.openai.*` |

## 部署完的對外資訊

| 服務 | URL |
| --- | --- |
| Open WebUI 入口 | `http://<host>:3000/` |
| mcpo OpenAPI 列表 | `http://<host>:8000/<mcp-name>/openapi.json` |

## 移除

```bash
cd /opt/open-webui
docker compose down -v       # -v 連 volume(資料庫)一起砍
rm -rf /opt/open-webui
```

設定的 IP/hostname/netplan 不會自動回復,要手動改 `/etc/netplan/00-installer-config.yaml`。
