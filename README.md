# Open WebUI on home.lab

部署 Open WebUI 到 VCF lab 內網主機 `openwebui.home.lab` (10.0.0.64) 的完整流程紀錄。

| 項目 | 值 |
| --- | --- |
| Hostname | `openwebui.home.lab` |
| IP | `10.0.0.64/23` |
| Gateway / DNS | `10.0.0.1` |
| OS | Ubuntu 20.04.4 LTS |
| Docker | 28.1.1 |
| Compose | v2.35.1 |
| Open WebUI | `ghcr.io/open-webui/open-webui:main` |
| 對外 Port | `3000` → 容器 `8080` |
| 入口 | <http://10.0.0.64:3000/> |

---

## 1. 主機初始化(IP + Hostname)

機器原本是 DHCP 拿到 `10.0.0.3`,要改成靜態 `10.0.0.64`,並把 hostname 設成 `openwebui.home.lab`。

```bash
# 1. 設 hostname
hostnamectl set-hostname openwebui.home.lab

# 2. /etc/hosts
sed -i '/127\.0\.1\.1/d' /etc/hosts
echo '10.0.0.64 openwebui.home.lab openwebui' >> /etc/hosts

# 3. netplan 改靜態
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

# 4. 防 cloud-init 重開機後覆蓋網路設定
echo 'network: {config: disabled}' \
  > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

# 5. 套用(SSH session 會斷,要用新 IP 重連)
nohup bash -c 'sleep 3; netplan apply' >/tmp/np.out 2>&1 </dev/null & disown
```

驗證:

```bash
ssh root@10.0.0.64
hostnamectl                       # Static hostname: openwebui.home.lab
ip -4 addr show ens160            # 10.0.0.64/23
ping -c 2 10.0.0.1                # gateway 通
```

---

## 2. 安裝 Docker

Ubuntu 20.04(focal)已 EOL,官方 `get.docker.com` script 會試圖裝 `docker-model-plugin`(focal 沒這個包)而失敗。直接用 apt 裝必要的幾個包即可:

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  docker-ce docker-ce-cli containerd.io \
  docker-compose-plugin docker-buildx-plugin
systemctl enable --now docker
docker --version          # Docker version 28.1.1
docker compose version    # v2.35.1
```

> 註:get.docker.com 已會自動加 Docker 官方 apt repo,所以 `apt install` 直接找得到 `docker-ce`。

---

## 3. 部署 Open WebUI

`/opt/open-webui/docker-compose.yml`:

```yaml
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
```

啟動:

```bash
mkdir -p /opt/open-webui && cd /opt/open-webui
# (寫入上面的 docker-compose.yml)
docker compose pull
docker compose up -d
docker compose ps
```

---

## 4. 驗證

```bash
curl -sS -o /dev/null -w 'http=%{http_code}\n' http://10.0.0.64:3000/
# http=200
```

瀏覽器開 <http://10.0.0.64:3000/>,**第一個註冊的帳號自動是 admin**。

進去後常見設定:

- **Admin Panel → Settings → General**:關掉「Enable New Sign Ups」防止公開註冊
- **Admin Panel → Connections**:加 OpenAI / Anthropic / Ollama endpoint
- **Admin Panel → Models**:從 Ollama 拉模型(若有接)

---

## 5. 備份

所有資料(使用者、聊天、設定、向量庫)都在 docker volume `open-webui_open-webui`:

```bash
docker run --rm -v open-webui_open-webui:/data -v $PWD:/backup alpine \
  tar czf /backup/openwebui-$(date +%F).tgz -C /data .
```

---

## 6. 升級

```bash
cd /opt/open-webui
docker compose pull
docker compose up -d
docker image prune -f
```
