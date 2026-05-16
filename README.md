# Open WebUI on home.lab

部署 Open WebUI 到內網主機 `openwebui.home.lab` (10.0.0.64) 的完整步驟與踩雷紀錄。
全程 root SSH 操作,Ubuntu 20.04,單張網卡,目標 5–10 分鐘搞定。

| 項目 | 值 |
| --- | --- |
| Hostname | `openwebui.home.lab` |
| IP | `10.0.0.64/23` |
| Gateway / DNS | `10.0.0.1` |
| OS | Ubuntu 20.04.4 LTS (focal) |
| Docker | 28.1.x |
| Compose | v2.35.x |
| Image | `ghcr.io/open-webui/open-webui:main` |
| 對外 Port | `3000` → 容器 `8080` |
| 入口 | <http://10.0.0.64:3000/> |

---

## TL;DR — 兩條路

### A. 客戶端 / 新環境 一鍵部署

連網路、Docker、Open WebUI、mcpo、LLM key、Tool Server 註冊全包,讀 `deploy/config.env`:

```bash
git clone https://github.com/kostenyang/openwebui.git
cd openwebui/deploy
cp config.env.example config.env && vim config.env
sudo bash install.sh
```

詳見 [`deploy/README.md`](deploy/README.md)。

### B. 已經有 box,只想裝 Open WebUI

```bash
git clone https://github.com/kostenyang/openwebui.git /opt/open-webui-setup
cd /opt/open-webui-setup
sudo bash install.sh
# 完成,瀏覽器開 http://<本機IP>:3000/
```

從零開始,**逐步理解每個動作做什麼**,往下看。

---

## 0. 前置檢查

開工前確認:

```bash
# OS 版本(這份步驟針對 Ubuntu 20.04)
. /etc/os-release && echo $PRETTY_NAME

# 網卡名稱(下面 netplan 會用到)
ip -br link

# 目標 IP 沒被別人用
ping -c 2 10.0.0.64       # 應該 100% packet loss
```

如果網卡不是 `ens160`,記得把後面 netplan 裡的網卡名換掉。

---

## 1. 改 IP 與 hostname

> ⚠️ 改 IP 會把當前 SSH session 踢掉,**用 `nohup` 把 `netplan apply` 丟背景**才不會卡住。改完用新 IP 重連。

```bash
# 1-1. hostname
hostnamectl set-hostname openwebui.home.lab

# 1-2. /etc/hosts 加自指項
sed -i '/127\.0\.1\.1/d' /etc/hosts
echo '10.0.0.64 openwebui.home.lab openwebui' >> /etc/hosts

# 1-3. netplan 改靜態
cat > /etc/netplan/00-installer-config.yaml <<'EOF'
network:
  version: 2
  ethernets:
    ens160:
      dhcp4: false
      addresses: [10.0.0.64/23]
      routes:
        - to: default
          via: 10.0.0.1
      nameservers:
        addresses: [10.0.0.1]
        search: [home.lab]
EOF
chmod 600 /etc/netplan/00-installer-config.yaml

# 1-4. 防 cloud-init 在重開機後把網路設定改回去
mkdir -p /etc/cloud/cloud.cfg.d
echo 'network: {config: disabled}' \
  > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

# 1-5. 套用(背景跑,本 SSH session 會在 ~3 秒後斷)
nohup bash -c 'sleep 3; netplan apply' >/tmp/np.out 2>&1 </dev/null & disown
```

開新 terminal,用新 IP 重連並驗證:

```bash
ssh root@10.0.0.64
hostnamectl                    # Static hostname: openwebui.home.lab
ip -4 addr show ens160         # inet 10.0.0.64/23
ping -c 2 10.0.0.1             # gateway 通
```

### 踩雷:`netplan apply` 卡死 SSH

直接在 SSH session 裡執行 `netplan apply`,IP 一變舊連線就死,指令永遠等不到回應、process 也清不掉。一定要 detach。

---

## 2. 安裝 Docker

> ⚠️ Ubuntu 20.04 已 EOL(2025/04 結束),官方 `get.docker.com` script 會嘗試裝 `docker-model-plugin`,但 focal repo 沒這個包,**整段 install 會中斷,docker 沒裝起來**。

正解:script 已經幫你加 apt repo,所以 script 失敗也沒關係,直接 `apt install` 必要的幾個包:

```bash
# 如果還沒跑過 get-docker.sh,先跑(只是為了它幫你寫好 apt 設定)
curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
sh /tmp/get-docker.sh || true   # 失敗在 docker-model-plugin,先忽略

# 直接裝該裝的
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  docker-ce docker-ce-cli containerd.io \
  docker-compose-plugin docker-buildx-plugin

systemctl enable --now docker

# 驗證
docker --version          # Docker version 28.1.1
docker compose version    # Docker Compose version v2.35.1
docker run --rm hello-world
```

---

## 3. 部署 Open WebUI

```bash
mkdir -p /opt/open-webui && cd /opt/open-webui

cat > docker-compose.yml <<'EOF'
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: always
    ports:
      - "3000:8080"
    volumes:
      - open-webui:/app/backend/data
    environment:
      - WEBUI_NAME=Open WebUI
      # 連外部 Ollama:
      # - OLLAMA_BASE_URL=http://<ollama-host>:11434
      # 連 OpenAI 相容 API:
      # - OPENAI_API_BASE_URL=https://api.openai.com/v1
      # - OPENAI_API_KEY=sk-...

volumes:
  open-webui:
EOF

docker compose pull
docker compose up -d
docker compose ps
```

第一次啟動 image 約 3.5 GB,健康檢查要 ~30 秒才會 healthy,中間 curl 可能會 connection reset,正常。

```bash
# 等到 ready 之後
curl -sS -o /dev/null -w 'http=%{http_code}\n' http://10.0.0.64:3000/
# http=200
```

---

## 4. 第一次登入

瀏覽器開 <http://10.0.0.64:3000/>:

1. 第一個註冊的帳號 **自動是 admin**,所以**第一個一定要是你**
2. 進去後立刻去 **Admin Panel → Settings → General** 把 *Enable New Sign Ups* **關掉**(防止外人註冊)
3. **Admin Panel → Connections** 加 Provider:
   - OpenAI / Anthropic / Groq 等 OpenAI-compatible:填 base URL + API key
   - Ollama:填 `http://<host>:11434`(或用 compose 的 env 直接設)
4. **Admin Panel → Models** 拉模型 / 設預設

---

## 5. 備份

所有資料(使用者、聊天、設定、文件向量庫)在 docker volume `open-webui_open-webui`:

```bash
docker run --rm \
  -v open-webui_open-webui:/data \
  -v $PWD:/backup alpine \
  tar czf /backup/openwebui-$(date +%F).tgz -C /data .
```

還原:

```bash
docker run --rm \
  -v open-webui_open-webui:/data \
  -v $PWD:/backup alpine \
  tar xzf /backup/openwebui-YYYY-MM-DD.tgz -C /data
```

---

## 6. 升級

```bash
cd /opt/open-webui
docker compose pull
docker compose up -d
docker image prune -f
```

升級不會碰 volume,設定/聊天保留。

---

## 7. (進階)接 MCP Server — 用 mcpo 當 OpenAPI 代理

> **背景**:Open WebUI 的 Tools 只吃 OpenAPI(REST),不直接講 MCP 協定。
> 解法是 [`mcpo`](https://github.com/open-webui/mcpo) — 把任何 MCP server 包成 OpenAPI HTTP server,Open WebUI 像呼叫一般工具一樣呼叫它。
>
> ```
> [Open WebUI] ──HTTP/OpenAPI──▶ [mcpo] ──MCP/SSE──▶ [VCF MCP Server]
>     :3000                       :8000              10.0.0.65:7000
> ```

### 7.1 上游 MCP server 資訊(本 lab)

| | |
| --- | --- |
| Host | `10.0.0.65` (mcp-server) |
| Endpoint | `https://10.0.0.65:7000/sse` |
| Transport | SSE (Server-Sent Events) |
| TLS | 自簽憑證(CN=10.0.0.65,2036 過期) |
| 認證 | `Authorization: Bearer <token>`,token 在 `/opt/vcf-mcp/keys.json` |
| systemd unit | `vcf-mcp.service` |

> ⚠️ **安全提醒**:本 lab 的 MCP server 持有 vCenter / SDDC Manager / ESXi root 密碼。MCP API token 等於對全 lab 的高權限,**只應在內網流通**。本 README 雖然 commit 了 token,但前提是這個 lab 不對外暴露 — 若你 fork 此設定到 production,務必把 token 改用 env var / Docker secret,不要塞進 git。

### 7.2 上游 cert 要有 SAN(踩雷預警)

> ⚠️ Python ≥ 3.10 / httpx 已經**完全不認 CN-only 的 cert**,只看 `subjectAltName`。
> 上游 vcf-mcp 預設產的 cert 如果只有 `CN=10.0.0.65`,mcpo 會吐:
> `[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: IP address mismatch`
>
> 處理:在 10.0.0.65 重生有 SAN 的 cert。

```bash
ssh root@10.0.0.65 'bash -s' <<'REMOTE'
cd /opt/vcf-mcp
cp cert.pem cert.pem.bak.$(date +%s)
cp key.pem  key.pem.bak.$(date +%s)
cat > /tmp/san.cnf <<EOF
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[dn]
CN = 10.0.0.65
O  = VCF-Lab
[v3]
basicConstraints = critical, CA:FALSE
keyUsage         = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName   = @san
[san]
IP.1  = 10.0.0.65
IP.2  = 127.0.0.1
DNS.1 = mcp-server
DNS.2 = localhost
EOF
openssl req -x509 -nodes -newkey rsa:4096 -days 3650 \
  -keyout key.pem -out cert.pem -config /tmp/san.cnf -extensions v3
chmod 600 key.pem; chmod 644 cert.pem
systemctl restart vcf-mcp
REMOTE
```

### 7.3 在 10.0.0.64 加上 mcpo

把上游的自簽 cert 拉下來放到 mcpo 容器讀得到的位置:

```bash
mkdir -p /opt/open-webui/mcpo/certs
scp root@10.0.0.65:/opt/vcf-mcp/cert.pem /opt/open-webui/mcpo/certs/vcf-mcp.pem
```

寫 mcpo 設定 `/opt/open-webui/mcpo/config.json`:

```json
{
  "mcpServers": {
    "vcf-lab": {
      "type": "sse",
      "url": "https://10.0.0.65:7000/sse",
      "headers": {
        "Authorization": "Bearer ILnx5ohq04A92X01Sk9rw9Uvjk8f0Nbd02a8wuIFZbw"
      }
    }
  }
}
```

```bash
chmod 600 /opt/open-webui/mcpo/config.json
```

把 mcpo 加進 `/opt/open-webui/docker-compose.yml`:

```yaml
services:
  open-webui:
    # ... (同 §3)

  mcpo:
    image: ghcr.io/open-webui/mcpo:main
    container_name: mcpo
    restart: always
    ports:
      - "8000:8000"
    volumes:
      - ./mcpo/config.json:/app/config.json:ro
      - ./mcpo/certs/vcf-mcp.pem:/certs/vcf-mcp.pem:ro
    environment:
      # 讓 httpx 信任自簽 cert
      - SSL_CERT_FILE=/certs/vcf-mcp.pem
      - REQUESTS_CA_BUNDLE=/certs/vcf-mcp.pem
    command:
      - "--host"
      - "0.0.0.0"
      - "--port"
      - "8000"
      - "--api-key"
      - "openwebui-mcpo-secret"   # Open WebUI 端要送這個 Bearer
      - "--config"
      - "/app/config.json"
```

啟動:

```bash
cd /opt/open-webui
docker compose pull mcpo
docker compose up -d
docker logs mcpo --tail 20
```

成功 log 應該長這樣(沒看到 `Failed to connect`):

```
INFO - Successfully connected to MCP server: vcf-lab
INFO - Application startup complete.
INFO - Uvicorn running on http://0.0.0.0:8000
```

### 7.4 驗證 mcpo

```bash
# Tool 列表(應該是滿的)
curl -s -H 'Authorization: Bearer openwebui-mcpo-secret' \
  http://10.0.0.64:8000/vcf-lab/openapi.json | jq '.paths | keys'

# 直接呼叫一個 tool(等同 MCP 的 tools/call)
curl -s -X POST -H 'Authorization: Bearer openwebui-mcpo-secret' \
  -H 'Content-Type: application/json' \
  -d '{"host":"10.0.0.65","count":2}' \
  http://10.0.0.64:8000/vcf-lab/ping_host
```

### 7.5 在 Open WebUI 介面加 Tool

1. 登入 <http://10.0.0.64:3000/> 用 admin
2. 右上頭像 → **Settings** → **Tools**(或 **Admin Panel → Settings → Tools**)
3. 點 **+** 新增:
   - **URL**: `http://10.0.0.64:8000/vcf-lab`
   - **API Key Type**: `Bearer`
   - **API Key**: `openwebui-mcpo-secret`
4. 儲存後,Open WebUI 會自動 fetch `openapi.json`,把每個 MCP tool 變成可用工具
5. 開新 chat → 在輸入框旁邊的 **+ Tool** 按鈕勾選 `vcf-lab` → 開問

### 7.6 常見坑

| 症狀 | 原因 | 解法 |
| --- | --- | --- |
| mcpo log: `ConnectTimeout` | 上游 MCP 沒回 TLS handshake | 檢查 `vcf-mcp` service 是否在跑、SSE 連線有沒有累積太多 |
| mcpo log: `IP address mismatch, certificate is not valid for ...` | 上游 cert 只有 CN 沒 SAN | 跑 §7.2 重生 cert |
| mcpo log: `SSL certificate verify failed` | 沒掛 cert / SSL_CERT_FILE 沒設 | 檢查 §7.3 的 volume 跟 env |
| `/openapi.json` paths 是 `{}` | mcpo 啟動時 upstream 失敗,沒拉到 tool schema | `docker compose restart mcpo` 重抓 |
| Open WebUI 加 Tool 401 | API Key 沒填或填錯 | 跟 mcpo `--api-key` 對齊 |
| 上游 MCP 接了一陣子變慢 | SSE 連線累積(FastMCP 已知問題) | `systemctl restart vcf-mcp` 清掉 |

---

## 8. 接 LLM Provider:OpenAI / Gemini / Claude

| Provider | 接法 | 哪裡填 |
| --- | --- | --- |
| **OpenAI** | 原生 OpenAI-compatible | Admin Panel → Settings → **Connections** |
| **Google Gemini** | Google 的 OpenAI-compatible 端點 | Admin Panel → Settings → **Connections** |
| **Anthropic Claude** | 走 Function/Pipe(API 格式不同) | Admin Panel → **Functions** |

### 8.1 OpenAI

1. 拿 key:<https://platform.openai.com/api-keys>
2. **Admin Panel → Settings → Connections → OpenAI API**
3. 點 **+ Add Connection**:
   - **URL**: `https://api.openai.com/v1`
   - **Key**: `sk-proj-...`
   - **Prefix ID**(可選): `openai`
4. 按 **🔄** 拉模型列表,選你要露出來的(`gpt-4o`、`gpt-5` 等)
5. Save。新 chat 的 model 下拉就會出現

### 8.2 Google Gemini

> Google 有官方 OpenAI-compatible 端點,Open WebUI 當成另一個 OpenAI 接就好,**不用 Function**。

1. 拿 key:<https://aistudio.google.com/apikey>
2. **Admin Panel → Settings → Connections → OpenAI API → + Add Connection**:
   - **URL**: `https://generativelanguage.googleapis.com/v1beta/openai`
   - **Key**: `AIza...`
   - **Prefix ID**: `gemini`
3. **🔄** 拉模型,會看到 `gemini-2.5-pro`、`gemini-2.5-flash` 等

> ⚠️ 若拉不到模型列表,在連線設定打開 **Model IDs** 手動填:`gemini-2.5-pro,gemini-2.5-flash,gemini-2.0-flash`

### 8.3 Anthropic Claude

Claude 的 `/v1/messages` 跟 OpenAI 的 `/v1/chat/completions` 格式差很多(尤其 system message、streaming SSE 結構),所以走 Function。

#### A. UI 安裝(一般做法)

1. 拿 key:<https://console.anthropic.com/settings/keys>
2. **Admin Panel → Functions → + Create new function**(右上角加號)
3. **Function ID**: `anthropic`,**Name**: `Anthropic`
4. 把 [`functions/anthropic_pipe.py`](functions/anthropic_pipe.py) **整份內容**貼進去 → **Save**
5. 列表回到 Functions,**Anthropic** 那一列:
   - 右邊小齒輪 ⚙ → 把 `ANTHROPIC_API_KEY` 填進去 → **Save**
   - 旁邊的開關打開(enabled)
6. 開新 chat,model 下拉會多三個:
   - `anthropic.claude-opus-4-7`
   - `anthropic.claude-sonnet-4-6`
   - `anthropic.claude-haiku-4-5`

要加更多 model id?改 `pipes()` 那個 list,Save 就好。

#### B. 進階:直接灌進 DB(自動化或 CI 用)

跳過 UI,直接把 Function row 寫進 SQLite,然後 restart container:

```bash
# 1. 把 functions/anthropic_pipe.py 複製進容器
docker cp functions/anthropic_pipe.py open-webui:/tmp/anthropic_pipe.py

# 2. 跑 install script(把 KEY 換成你的)
docker exec -e API_KEY="sk-ant-api03-xxxx" open-webui python3 <<'EOF'
import sqlite3, json, time, os
USER_ID = '<admin-user-id>'   # SELECT id FROM user WHERE role='admin'
API_KEY = os.environ['API_KEY']
content = open('/tmp/anthropic_pipe.py', encoding='utf-8').read()
valves = json.dumps({
    'ANTHROPIC_API_KEY': API_KEY,
    'ANTHROPIC_API_BASE': 'https://api.anthropic.com/v1',
    'MAX_TOKENS': 8192,
})
meta = json.dumps({'description': 'Anthropic Claude provider', 'manifest': {}})
now = int(time.time())
db = sqlite3.connect('/app/backend/data/webui.db')
db.execute('DELETE FROM function WHERE id=?', ('anthropic',))
db.execute(
    'INSERT INTO function (id, user_id, name, type, content, meta, '
    'created_at, updated_at, valves, is_active, is_global) '
    'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
    ('anthropic', USER_ID, 'Anthropic', 'pipe', content, meta, now, now, valves, 1, 1)
)
db.commit()
EOF

# 3. 重啟才會載入新 Function
docker restart open-webui
```

> Admin user_id 怎麼找:
> ```bash
> docker exec open-webui python3 -c "import sqlite3; \
>   print([r for r in sqlite3.connect('/app/backend/data/webui.db').execute(\"SELECT id, email, role FROM user WHERE role='admin'\")])"
> ```

### 8.4 模型管理小撇步

| 想做的事 | 怎麼做 |
| --- | --- |
| 把某些模型藏起來不要露給一般使用者 | Admin Panel → **Models** → 該 model → 設 **Hide** |
| 設預設模型 | Admin Panel → Settings → **General → Default Models** |
| 替模型自訂顯示名 / 描述 / 預設 system prompt | Admin Panel → **Models** → **Edit** |
| 不同使用者看到不同的 model | Admin Panel → **Models** → 給該 model 設 **Visibility**(public/private/groups) |

### 8.5 API Keys 的存放

填進去的 key 都加密存在 docker volume `open-webui_open-webui` 的 SQLite DB(`webui.db`)裡,**不會出現在 docker-compose.yml 或 env**。要備份就照 §5。

---

## 9. 常見問題

| 症狀 | 原因 | 解法 |
| --- | --- | --- |
| `netplan apply` 後 SSH 永遠連不上 | 子網寫錯,封包出不去 | console 進機器手動改回 |
| `docker-model-plugin` 裝不起來 | Ubuntu 20.04 EOL | 改用 §2 的 `apt install` |
| 開 3000 port 連線 reset | 健康檢查還沒過(starting) | 等 30–60 秒 |
| 第一個帳號不是自己 | 別人比你先註冊 → admin 是別人 | `docker compose down -v` 砍 volume 重來 |
| 重開機後 IP 變回 DHCP | cloud-init 把 netplan 蓋掉 | 確認 §1-4 的 `99-disable-network-config.cfg` 存在 |

---

## 檔案結構

```
.
├── README.md                         本檔
├── install.sh                        裝 Docker + 起 Open WebUI 的一鍵腳本
├── docker-compose.yml                Open WebUI + mcpo compose 定義
├── deploy/                           客戶端一鍵部署包(scp 整包過去用)
│   ├── README.md                       └ deploy 詳細說明
│   ├── config.env.example              └ 範本(scp 後拷成 config.env)
│   ├── install.sh                      └ 主入口
│   └── lib/                            └ 階段 scripts
├── functions/
│   └── anthropic_pipe.py             Open WebUI Function:Claude provider(§8.3)
├── mcpo/
│   ├── config.json                   mcpo upstream MCP servers 設定(目前 lab 用)
│   └── certs/                        放上游自簽 cert(本機 scp 過來)
├── netplan/
│   └── 00-installer-config.yaml      靜態 IP 範本
└── .gitignore
```
