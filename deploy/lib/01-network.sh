#!/usr/bin/env bash
# 設靜態 IP + hostname。改完用 nohup detach netplan apply,SSH session 會斷。
set -euo pipefail
source "$(dirname "$0")/../config.env"

# 自動偵測網卡
NIC="${NIC:-}"
if [[ -z "$NIC" ]]; then
  NIC="$(ip -o -4 route show to default | awk '{print $5}' | head -1)"
  echo "  auto-detected NIC: $NIC"
fi

# hostname
if [[ -n "${HOSTNAME:-}" ]]; then
  hostnamectl set-hostname "$HOSTNAME"
  sed -i '/127\.0\.1\.1/d' /etc/hosts
  IP_NUM="${STATIC_IP%%/*}"
  SHORT="${HOSTNAME%%.*}"
  grep -q "$IP_NUM $HOSTNAME" /etc/hosts \
    || echo "$IP_NUM $HOSTNAME $SHORT" >> /etc/hosts
fi

# DNS list
DNS_LIST=""
if [[ -n "${DNS_SERVERS:-}" ]]; then
  IFS=',' read -ra arr <<< "$DNS_SERVERS"
  DNS_LIST="[$(IFS=,; echo "${arr[*]}")]"
fi

# netplan
NPFILE=/etc/netplan/00-installer-config.yaml
cat > "$NPFILE" <<EOF
network:
  version: 2
  ethernets:
    ${NIC}:
      dhcp4: false
      addresses: [${STATIC_IP}]
      routes:
        - to: default
          via: ${GATEWAY}
EOF
if [[ -n "$DNS_LIST" || -n "${DNS_SEARCH:-}" ]]; then
cat >> "$NPFILE" <<EOF
      nameservers:
EOF
  [[ -n "$DNS_LIST"   ]] && echo "        addresses: $DNS_LIST" >> "$NPFILE"
  [[ -n "${DNS_SEARCH:-}" ]] && echo "        search: [$DNS_SEARCH]" >> "$NPFILE"
fi
chmod 600 "$NPFILE"

# 防 cloud-init 重開機後覆蓋
mkdir -p /etc/cloud/cloud.cfg.d
echo 'network: {config: disabled}' \
  > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

echo "  netplan written:"
cat "$NPFILE" | sed 's/^/    /'

# detach apply,本 SSH session 會在 ~3 秒後斷,接著用新 IP 重連
echo "  applying in background — SSH may drop, reconnect to ${STATIC_IP%%/*}"
nohup bash -c 'sleep 3; netplan apply' >/tmp/netplan-apply.log 2>&1 </dev/null &
disown
