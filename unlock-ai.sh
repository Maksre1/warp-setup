#!/usr/bin/env bash

# ==============================================================================
# 🚀 VPS Auto-WARP & Optimization Configurator (v1.1 - Sing-box 1.13+ ready)
# Разблокировка нейросетей на вашем сервере (Gemini, ChatGPT, Claude)
# ==============================================================================

exec < /dev/tty

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear

echo -e "${BLUE}=========================================================${NC}"
echo -e "   🚀  ${GREEN}VPS Auto-WARP Configurator (v1.1)${NC}"
echo -e "   Разблокировка нейросетей (Gemini, ChatGPT, Claude)"
echo -e "${BLUE}=========================================================${NC}"
echo ""

read -p "Вы согласны продолжить настройку? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo -e "\n${YELLOW}Настройка отменена.${NC}\n"
    exit 0
fi

echo -e "\n---------------------------------------------------------"
echo -e "Укажите параметры подключения к вашему VPS-серверу:"
echo -e "---------------------------------------------------------"

read -p "[?] IP-адрес сервера: " VPS_IP
if [ -z "$VPS_IP" ]; then echo -e "${RED}Ошибка: IP пуст.${NC}"; exit 1; fi

read -p "[?] SSH-порт [22]: " VPS_PORT
VPS_PORT=${VPS_PORT:-22}

read -p "[?] Пользователь [root]: " VPS_USER
VPS_USER=${VPS_USER:-root}

read -p "[?] Пароль SSH: " VPS_PASS
echo ""

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
SSHPASS_BIN="$(command -v sshpass 2>/dev/null)"

if [ -z "$SSHPASS_BIN" ]; then
    if [[ "$(uname)" == "Darwin" ]]; then
        brew install hudochenkov/sshpass/sshpass 2>/dev/null
    elif [ -f /etc/debian_version ]; then
        sudo apt-get install -y sshpass >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y sshpass >/dev/null 2>&1
    fi
    SSHPASS_BIN="$(command -v sshpass 2>/dev/null)"
fi

if [ -z "$SSHPASS_BIN" ]; then
    echo -e "${RED}[✗] Не удалось найти sshpass. Установите вручную.${NC}"
    exit 1
fi

ssh-keygen -R "$VPS_IP" >/dev/null 2>&1 || true

conn_test=$(SSHPASS="$VPS_PASS" "$SSHPASS_BIN" -e ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p "$VPS_PORT" "$VPS_USER@$VPS_IP" "echo OK" 2>&1)
if [[ "$conn_test" != *"OK"* ]]; then
    echo -e "${RED}[✗] Ошибка подключения: $conn_test${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] Успешное подключение!${NC}"

REMOTE_SCRIPT=$(cat << 'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive

status_update() { echo "PROGRESS:$1:$2"; }

status_update 20 "Установка ПО"
if [ -f /etc/debian_version ]; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl jq iptables iptables-persistent >/dev/null 2>&1
fi
curl -fsSL https://sing-box.app/deb-install.sh | bash >/dev/null 2>&1

mkdir -p /etc/sing-box
status_update 40 "Настройка WARP"
ARCH=$(uname -m); [ "$ARCH" == "x86_64" ] && WGCF_ARCH="amd64" || WGCF_ARCH="arm64"
WGCF_URL="https://github.com/ViRb3/wgcf/releases/download/v2.2.26/wgcf_2.2.26_linux_${WGCF_ARCH}"
curl -fsSL "$WGCF_URL" -o /tmp/wgcf && chmod +x /tmp/wgcf
/tmp/wgcf register --accept-tos >/dev/null 2>&1
/tmp/wgcf generate >/dev/null 2>&1
private_key=$(awk '/^PrivateKey/{print $3}' /tmp/wgcf-profile.conf)
warp_ip4="$(awk '/^Address/{print $3}' /tmp/wgcf-profile.conf | grep -v ':' | head -1)"
warp_ip6="$(awk '/^Address/{print $3}' /tmp/wgcf-profile.conf | grep ':' | head -1)"
client_id=$(grep 'client_id' /tmp/wgcf-account.toml 2>/dev/null | awk -F'"' '{print $2}' || true)
warp_reserved=$(python3 -c "import base64,json; b=base64.b64decode('$client_id'); print(json.dumps(list(b[:3])))" 2>/dev/null || echo "[0,0,0]")

cat << SECONF > /etc/sing-box/config.json
{
  "log": { "level": "warning" },
  "dns": {
    "servers": [
      { "tag": "dns-remote", "type": "https", "server": "1.1.1.1", "path": "/dns-query", "detour": "warp" },
      { "tag": "dns-local", "type": "udp", "server": "8.8.8.8", "detour": "direct" }
    ],
    "rules": [
      { "domain_suffix": ["gemini.google.com", "openai.com", "chatgpt.com", "anthropic.com", "claude.ai", "google.ai"], "server": "dns-remote" }
    ],
    "final": "dns-local"
  },
  "inbounds": [
    { "type": "redirect", "tag": "redirect-in", "listen": "0.0.0.0", "listen_port": 12345 }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    {
      "type": "wireguard", "tag": "warp", "server": "engage.cloudflareclient.com", "server_port": 2408,
      "local_address": ["$warp_ip4", "$warp_ip6"], "private_key": "$private_key",
      "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=", "reserved": $warp_reserved, "mtu": 1280
    },
    { "type": "dns", "tag": "dns-out" }
  ],
  "route": {
    "rules": [
      { "type": "field", "inbound": "redirect-in", "sniff": ["http", "tls"], "sniff_override_destination": true },
      { "type": "field", "protocol": "dns", "outbound": "dns-out" },
      { "type": "field", "domain_suffix": ["gemini.google.com", "openai.com", "chatgpt.com", "anthropic.com", "claude.ai"], "outbound": "warp" },
      { "type": "field", "outbound": "direct" }
    ]
  }
}
SECONF

systemctl restart sing-box && systemctl enable sing-box >/dev/null 2>&1
status_update 80 "Настройка фаервола"
iptables -t nat -F
iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner sing-box -j RETURN
iptables -t nat -A OUTPUT -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345
iptables -t nat -A PREROUTING -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345
status_update 100 "Завершение"
EOF
)

TMP_SCRIPT="/tmp/warp_remote_script_$$"
FIFO_FILE="/tmp/warp_ssh_progress_$$"
mkfifo "$FIFO_FILE"
printf '%s\n' "$REMOTE_SCRIPT" > "$TMP_SCRIPT"

SSHPASS="$VPS_PASS" "$SSHPASS_BIN" -e ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p "$VPS_PORT" "$VPS_USER@$VPS_IP" "bash -s" < "$TMP_SCRIPT" > "$FIFO_FILE" 2>&1 &
SSH_PID=$!
error_occurred=0

while IFS= read -r line; do
    if [[ "$line" == PROGRESS:* ]]; then
        printf "\r[i] Прогресс: %s" "$(echo "$line" | cut -d':' -f3)"
    elif [[ "$line" == ERROR:* ]]; then
        error_occurred=1
        err_msg=$(echo "$line" | cut -d':' -f2-)
        printf "\n\n${RED}%s${NC}\n" "$err_msg" >&2
    fi
done < "$FIFO_FILE"

wait $SSH_PID 2>/dev/null
ssh_status=$?

rm -f "$FIFO_FILE" "$TMP_SCRIPT"
unset VPS_PASS

if [ "$ssh_status" -ne 0 ] || [ "$error_occurred" -ne 0 ]; then
    echo -e "\n\n${RED}[✗] Ошибка подключения или установки!${NC}"
    exit 1
fi

printf "\n\n"
echo -e "${BLUE}=========================================================${NC}"
echo -e "   🎉  ${GREEN}НАСТРОЙКА УСПЕШНО ЗАВЕРШЕНА!${NC}"
echo -e "${BLUE}=========================================================${NC}"
echo ""
echo -e "Все службы настроены и запущены."
echo -e "${GREEN}Приятного использования!${NC}"
