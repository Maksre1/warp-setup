#!/usr/bin/env bash

# ==============================================================================
# 🚀 Universal AI Unlocker & Server Optimizer (Remote Installer)
# Запускается на вашем локальном ПК. Сам подключается к VPS и настраивает WARP 
# поверх любого существующего VPN-сервера (Amnezia, 3x-ui, Xray, OpenVPN).
# ==============================================================================

exec < /dev/tty

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear

echo -e "${BLUE}=========================================================${NC}"
echo -e "   🚀  ${GREEN}VPS Universal AI Unlocker (v2.0)${NC}"
echo -e "   Локальный установщик -> Настройка сервера"
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

echo -e "${GREEN}[✓] Успешное подключение к серверу!${NC}"

# ==============================================================================
# СЕРВЕРНАЯ ЧАСТЬ (выполняется на удаленном VPS)
# ==============================================================================
REMOTE_SCRIPT=$(cat << 'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive

status_update() { echo "PROGRESS:$1:$2"; }

status_update 10 "Оптимизация сетевого стека..."
cat > /etc/sysctl.d/99-ai-optimization.conf << SYSCTL_EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.core.rmem_max=67108864
net.core.wmem_max=67108864
SYSCTL_EOF
sysctl --system >/dev/null 2>&1 || true

status_update 30 "Установка sing-box и утилит..."
if [ -f /etc/debian_version ]; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl jq iptables iptables-persistent python3 >/dev/null 2>&1
fi
bash -c "$(curl -fsSL https://sing-box.app/deb-install.sh)" >/dev/null 2>&1

ARCH=$(uname -m); [ "$ARCH" == "x86_64" ] && WGCF_ARCH="amd64" || WGCF_ARCH="arm64"
curl -fsSL "https://github.com/ViRb3/wgcf/releases/download/v2.2.26/wgcf_2.2.26_linux_${WGCF_ARCH}" -o /usr/local/bin/wgcf
chmod +x /usr/local/bin/wgcf

status_update 50 "Настройка Cloudflare WARP..."
mkdir -p /etc/sing-box

if [ ! -f /etc/sing-box/warp.conf ]; then
    cd /tmp
    if ! wgcf register --accept-tos >/dev/null 2>&1; then
        echo "ERROR:WARP_BLOCKED"
        exit 1
    fi
    wgcf generate >/dev/null 2>&1
    
    CLIENT_ID=$(grep 'client_id' wgcf-account.toml 2>/dev/null | cut -d"'" -f2 | cut -d'"' -f2 || echo "")
    WARP_RESERVED=$(python3 -c "import base64,json; b=base64.b64decode('$CLIENT_ID'); print(json.dumps(list(b[:3])))" 2>/dev/null || echo "[0,0,0]")
    
    mv wgcf-profile.conf /etc/sing-box/warp.conf
    echo "$WARP_RESERVED" > /etc/sing-box/warp_reserved.txt
    cd /
else
    WARP_RESERVED=$(cat /etc/sing-box/warp_reserved.txt 2>/dev/null || echo "[0,0,0]")
fi

PRIVATE_KEY=$(grep 'PrivateKey' /etc/sing-box/warp.conf | awk '{print $3}')
WARP_IP4=$(grep 'Address' /etc/sing-box/warp.conf | grep -v ':' | awk '{print $3}' | head -n 1)
WARP_IP6=$(grep 'Address' /etc/sing-box/warp.conf | grep ':' | awk '{print $3}' | head -n 1)

status_update 70 "Настройка маршрутизации ИИ..."
cat << SB_EOF > /etc/sing-box/config.json
{
  "log": { "level": "warning" },
  "dns": {
    "servers": [
      { "tag": "dns-warp", "type": "https", "server": "1.1.1.1", "detour": "warp" },
      { "tag": "dns-direct", "type": "udp", "server": "8.8.8.8", "detour": "direct" }
    ],
    "rules": [
      { "domain_suffix": ["gemini.google.com", "openai.com", "chatgpt.com", "anthropic.com", "claude.ai", "google.ai"], "server": "dns-warp" }
    ],
    "final": "dns-direct"
  },
  "inbounds": [
    { "type": "redirect", "tag": "redirect-in", "listen": "0.0.0.0", "listen_port": 12345 }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    {
      "type": "wireguard",
      "tag": "warp",
      "server": "engage.cloudflareclient.com",
      "server_port": 2408,
      "local_address": ["$WARP_IP4", "$WARP_IP6"],
      "private_key": "$PRIVATE_KEY",
      "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "reserved": $WARP_RESERVED,
      "mtu": 1280
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
SB_EOF

status_update 90 "Настройка Iptables (прозрачный прокси)..."
iptables -t nat -D OUTPUT -p tcp -m owner --uid-owner sing-box -j RETURN 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345 2>/dev/null || true
iptables -t nat -D PREROUTING -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345 2>/dev/null || true

iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner sing-box -j RETURN
iptables -t nat -A OUTPUT -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345
iptables -t nat -A PREROUTING -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345

if [ -f /etc/debian_version ]; then
    netfilter-persistent save >/dev/null 2>&1 || iptables-save > /etc/iptables/rules.v4
fi

systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1
systemctl restart sing-box

status_update 100 "Завершение настройки"
EOF
)

TMP_SCRIPT="/tmp/warp_remote_script_$$"
FIFO_FILE="/tmp/warp_ssh_progress_$$"
mkfifo "$FIFO_FILE"
printf '%s\n' "$REMOTE_SCRIPT" > "$TMP_SCRIPT"

if [ "$VPS_USER" == "root" ]; then
    SSHPASS="$VPS_PASS" "$SSHPASS_BIN" -e ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p "$VPS_PORT" "$VPS_USER@$VPS_IP" "bash -s" < "$TMP_SCRIPT" > "$FIFO_FILE" 2>&1 &
    SSH_PID=$!
else
    # Для пользователей вроде ubuntu: загружаем скрипт, затем исполняем через sudo
    SSHPASS="$VPS_PASS" "$SSHPASS_BIN" -e ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p "$VPS_PORT" "$VPS_USER@$VPS_IP" "cat > /tmp/ai_setup_$$.sh" < "$TMP_SCRIPT"
    SSHPASS="$VPS_PASS" "$SSHPASS_BIN" -e ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p "$VPS_PORT" "$VPS_USER@$VPS_IP" "sudo -S bash /tmp/ai_setup_$$.sh; rm -f /tmp/ai_setup_$$.sh" <<< "$VPS_PASS" > "$FIFO_FILE" 2>&1 &
    SSH_PID=$!
fi

error_occurred=0

while IFS= read -r line; do
    if [[ "$line" == PROGRESS:* ]]; then
        printf "\r[i] Прогресс: %s" "$(echo "$line" | cut -d':' -f3)"
    elif [[ "$line" == ERROR:* ]]; then
        error_occurred=1
        err_msg=$(echo "$line" | cut -d':' -f2-)
        
        if [[ "$err_msg" == "WARP_BLOCKED" ]]; then
            printf "\n\n${RED}[✗] ОШИБКА: Cloudflare заблокировал авто-регистрацию WARP с IP вашего сервера (Ошибка 429).${NC}\n" >&2
            echo -e "${YELLOW}КАК РЕШИТЬ ПРОБЛЕМУ:${NC}" >&2
            echo -e "1. Скачайте 'wgcf' на этот локальный ПК." >&2
            echo -e "2. Выполните: wgcf register --accept-tos  затем  wgcf generate" >&2
            echo -e "3. Скопируйте содержимое файла wgcf-profile.conf." >&2
            echo -e "4. На сервере создайте файл: sudo nano /etc/sing-box/warp.conf и вставьте текст." >&2
            echo -e "5. Запустите этот скрипт снова.\n" >&2
        else
            printf "\n\n${RED}%s${NC}\n" "$err_msg" >&2
        fi
    fi
done < "$FIFO_FILE"

wait $SSH_PID 2>/dev/null
ssh_status=$?

rm -f "$FIFO_FILE" "$TMP_SCRIPT"
unset VPS_PASS

if [ "$ssh_status" -ne 0 ] || [ "$error_occurred" -ne 0 ]; then
    echo -e "\n\n${RED}[✗] Процесс прерван из-за ошибки!${NC}"
    exit 1
fi

printf "\n\n"
echo -e "${BLUE}=========================================================${NC}"
echo -e "   🎉  ${GREEN}УНИВЕРСАЛЬНАЯ РАЗБЛОКИРОВКА УСПЕШНО НАСТРОЕНА!${NC}"
echo -e "${BLUE}=========================================================${NC}"
echo ""
echo -e "Теперь ИИ-трафик маршрутизируется через WARP прозрачно."
echo -e "Ваш основной VPN работает как обычно."
echo -e "${GREEN}Приятного использования!${NC}"
