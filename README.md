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

## TL;DR(已經有 IP/hostname 設好的情況)

```bash
git clone https://github.com/kostenyang/openwebui.git /opt/open-webui-setup
cd /opt/open-webui-setup
sudo bash install.sh
# 完成,瀏覽器開 http://<本機IP>:3000/
```

從零開始的完整版往下看。

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

## 7. 常見問題

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
├── docker-compose.yml                Open WebUI compose 定義
├── netplan/
│   └── 00-installer-config.yaml      靜態 IP 範本
└── .gitignore
```
