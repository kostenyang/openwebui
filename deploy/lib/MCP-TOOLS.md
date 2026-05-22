# 在 Open WebUI 加 MCP / OpenAPI 工具

這份文件解釋 `05-mcp-tool.sh` 在做什麼、`config.env` 該怎麼填、以及兩種 MCP 接法的差別。看完你可以自己加第三、第四個 MCP 工具,不用每次找我。

## 0. 前提:Open WebUI 怎麼看「工具」

Open WebUI 不直接講 MCP 協定,它只認 **OpenAPI**。所以任何要被它呼叫的工具,**最終都得是一個 HTTP server 露出 `/openapi.json`**。

它怎麼知道有哪些工具?
- 看 admin 使用者 `settings.ui.toolServers` 這個 JSON 欄位。每一筆 entry 就是一個 OpenAPI server。
- 那筆 JSON 寫在容器內的 SQLite:`/app/backend/data/webui.db`,`user` 表的 `settings` 欄。
- 我們的腳本就是直接改那筆 JSON,**不走 Open WebUI 的 UI 也不走 REST**(reasons: REST 要 admin token,UI 不能自動化)。

## 1. 兩種 MCP 接法,在 config 上長得不一樣

### A. 「stdio / SSE 原生 MCP」→ 中央 mcpo 包一層

例:`vcf-lab` MCP server(在 10.0.0.65,FastMCP+SSE 對外)。它**只會講 MCP 協定**,不講 OpenAPI。

對策:在 Open WebUI 同一台機器跑 `mcpo`(我們的 docker compose 已經幫你裝了),`mcpo` 吃 MCP 吐 OpenAPI。Open WebUI 再去吃 `mcpo` 吐的 OpenAPI。

```
Open WebUI ─→ mcpo (本機:8000) ─SSE→ vcf-lab MCP (遠端:7000)
                ↑
            這層幫忙翻譯
```

config.env 對應的設定:
```bash
MCPO_ENABLED=true
MCPO_PORT=8000
MCPO_API_KEY="openwebui-mcpo-secret"      # 客戶端送 Bearer 給 mcpo 的 key
UPSTREAM_MCP_NAME="vcf-lab"                # mcpo 路徑會變 /vcf-lab/*
UPSTREAM_MCP_TYPE="sse"
UPSTREAM_MCP_URL="https://10.0.0.65:7000/sse"
UPSTREAM_MCP_BEARER="<vcf-mcp 的 token>"
UPSTREAM_MCP_CERT_FILE="/opt/open-webui/mcpo/certs/vcf-mcp.pem"
```

### B. 「成品 OpenAPI」MCP → 直接接,不走中央 mcpo

例:`mssql-mcp`(在 10.0.0.68)。它**容器內部已經跑了 mcpo**,對外直接是 OpenAPI:`http://10.0.0.68:8000/mssql/openapi.json`。它跟你本機的 mcpo 是**同一層**的東西,不是 upstream。

對策:Open WebUI 直接認它,跳過中央 mcpo。

```
Open WebUI ─→ mssql-mcp (遠端:8000/mssql)     ← 自己就是 OpenAPI
            ↘ (本機 mcpo 那條繼續為 vcf-lab 服務,不衝突)
```

config.env 對應的設定:
```bash
EXTRA_TOOL_SERVERS=(
  "mssql|http://10.0.0.68:8000/mssql|<mssql-mcp 的 MCPO_API_KEY>"
)
```

> **判斷標準**:對方 server 已經有 `/openapi.json`(curl 一下看得到 JSON schema)→ 走 B。對方只認 MCP 協定(`/sse` 走 SSE、或要 stdio 才能講話)→ 走 A,讓本機 mcpo 翻譯。

## 2. 完整 config.env 範例

開兩種 MCP 都接的情境(VCF lab 現在就長這樣):

```bash
# ─── [3] 本機 mcpo + vcf-lab (路線 A) ─────────────────
MCPO_ENABLED=true
MCPO_PORT=8000
MCPO_API_KEY="openwebui-mcpo-secret"

UPSTREAM_MCP_NAME="vcf-lab"
UPSTREAM_MCP_TYPE="sse"
UPSTREAM_MCP_URL="https://10.0.0.65:7000/sse"
UPSTREAM_MCP_BEARER="ILnx5ohq04A92X01Sk9rw9Uvjk8f0Nbd02a8wuIFZbw"
UPSTREAM_MCP_CERT_FILE="/opt/open-webui/mcpo/certs/vcf-mcp.pem"

# ─── [3b] 額外的成品 OpenAPI (路線 B) ─────────────────
EXTRA_TOOL_SERVERS=(
  "mssql|http://10.0.0.68:8000/mssql|mssql-mcp-secret-99b12d9de4dbc58280d67669aaca2ec1"
)
```

## 3. 跑起來

第一次部署:`sudo bash install.sh`,腳本會跑到階段 [5/5] 自動註冊。

之後要單純加 / 改工具(機器已經跑著):
```bash
cd /root/deploy
vim config.env                            # 改 EXTRA_TOOL_SERVERS
sudo bash install.sh --skip-network --skip-docker --skip-openwebui --skip-llm
# 只跑階段 5,大概 3 秒結束
```

跑完看到:
```
[5/5] Register MCP Tool Server in Open WebUI
  → register local mcpo:
    replaced: vcf-lab -> http://10.0.0.64:8000/vcf-lab
  → register 1 extra tool server(s):
    added: mssql -> http://10.0.0.68:8000/mssql
```

> **idempotent**:同 URL 跑第二次只是 `replaced`,不會出現重複 entry。所以反覆跑沒副作用。

## 4. 怎麼驗證

```bash
# 開瀏覽器 → http://<openwebui-ip>:3000/
# 用 admin 登入(改 DB 後一定要重新整理 / 重登,settings 是 user-scoped 的)
# 新 chat → 輸入框旁邊 + Tools → 應該看到 mssql 跟 vcf-lab 並列
```

API 驗證(免進 UI):
```bash
docker exec open-webui python3 -c "
import json, sqlite3
db = sqlite3.connect('/app/backend/data/webui.db')
row = db.execute(\"SELECT settings FROM user WHERE role='admin'\").fetchone()
servers = json.loads(row[0])['ui']['toolServers']
for s in servers:
    print(f\"  {s['info']['name']:20s} -> {s['url']}\")
"
```

## 5. 常見坑

| 症狀 | 原因 | 解 |
| --- | --- | --- |
| 註冊跑完,UI 沒看到新 tool | admin user 沒重新整理 / 換瀏覽器 tab | F5 重新整理該 tab,或登出再登入 |
| `no admin user yet` | Open WebUI 剛裝、還沒有人註冊過 | 開瀏覽器先註冊第一個帳號(自動 admin),再重跑 `--skip-network --skip-docker --skip-openwebui --skip-llm` |
| 加進去了但 chat 用不到 | tool 的 URL 從 openwebui box 連不到 | `docker exec open-webui curl -s http://10.0.0.68:8000/mssql/openapi.json` 確認 |
| 401 Unauthorized | EXTRA_TOOL_SERVERS 的 bearer key 跟對方 server 不符 | 對方機器 `grep MCPO_API_KEY /opt/<service>/.env` 重抄 |
| 想多個 admin 也都看到 | 目前腳本只改第一個 `role='admin'` 的 user | 改 `LIMIT 1` 拿掉、改 `WHERE role='admin'` 全 loop |

## 6. 想再加一條怎麼辦

只要對方 server 自己已經是 OpenAPI(curl `/openapi.json` 回 JSON):

1. config.env 的 `EXTRA_TOOL_SERVERS` 陣列裡加一行:`"name|url|bearer"`
2. `sudo bash install.sh --skip-network --skip-docker --skip-openwebui --skip-llm`
3. 瀏覽器 F5

不需要動 mcpo / docker compose / cert 任何東西。
