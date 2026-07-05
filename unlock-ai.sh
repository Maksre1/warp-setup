#!/usr/bin/env bash

# ==============================================================================
# 🚀 Universal AI Unlocker & Server Optimizer
# Устанавливает WARP, Sing-box для ИИ-трафика и оптимизирует систему.
# Работает поверх любого существующего VPN-сервера (Amnezia, 3x-ui, Xray, OpenVPN).
# ==============================================================================

set -e
export DEBIAN_FRONTEND=noninteractive

if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен быть запущен с правами root"
   exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}>>> Оптимизация сетевого стека (BBR)...${NC}"
cat > /etc/sysctl.d/99-ai-optimization.conf << EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.core.rmem_max=67108864
net.core.wmem_max=67108864
EOF
sysctl --system >/dev/null 2>&1 || true

echo -e "${GREEN}>>> Установка sing-box и утилит...${NC}"
if [ -f /etc/debian_version ]; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl jq iptables iptables-persistent python3 >/dev/null 2>&1
fi
bash -c "$(curl -fsSL https://sing-box.app/deb-install.sh)" >/dev/null 2>&1

ARCH=$(uname -m); [ "$ARCH" == "x86_64" ] && WGCF_ARCH="amd64" || WGCF_ARCH="arm64"
curl -fsSL "https://github.com/ViRb3/wgcf/releases/download/v2.2.26/wgcf_2.2.26_linux_${WGCF_ARCH}" -o /usr/local/bin/wgcf
chmod +x /usr/local/bin/wgcf

echo -e "${GREEN}>>> Настройка WARP...${NC}"
mkdir -p /etc/sing-box

if [ ! -f /etc/sing-box/warp.conf ]; then
    cd /tmp
    echo -e "[i] Попытка регистрации бесплатного аккаунта WARP..."
    if ! wgcf register --accept-tos >/dev/null 2>&1; then
        echo -e "\n${RED}[✗] ОШИБКА: Cloudflare заблокировал автоматическую регистрацию с IP вашего сервера (Ошибка 429).${NC}"
        echo -e "${YELLOW}КАК РЕШИТЬ ПРОБЛЕМУ:${NC}"
        echo -e "1. Скачайте 'wgcf' на ваш домашний компьютер (Windows/Mac/Linux)."
        echo -e "2. Выполните на ПК: wgcf register --accept-tos  затем  wgcf generate"
        echo -e "3. Откройте полученный файл wgcf-profile.conf, скопируйте его содержимое."
        echo -e "4. На сервере создайте файл: nano /etc/sing-box/warp.conf"
        echo -e "5. Вставьте туда скопированный текст, сохраните и запустите этот скрипт снова.\n"
        exit 1
    fi
    wgcf generate >/dev/null 2>&1
    
    # Извлечение reserved байтов (улучшает соединение)
    CLIENT_ID=$(grep 'client_id' wgcf-account.toml 2>/dev/null | cut -d"'" -f2 | cut -d'"' -f2 || echo "")
    WARP_RESERVED=$(python3 -c "import base64,json; b=base64.b64decode('$CLIENT_ID'); print(json.dumps(list(b[:3])))" 2>/dev/null || echo "[0,0,0]")
    
    mv wgcf-profile.conf /etc/sing-box/warp.conf
    echo "$WARP_RESERVED" > /etc/sing-box/warp_reserved.txt
    cd /
else
    echo -e "${GREEN}[✓] Файл WARP (/etc/sing-box/warp.conf) уже существует, используем его.${NC}"
    WARP_RESERVED=$(cat /etc/sing-box/warp_reserved.txt 2>/dev/null || echo "[0,0,0]")
fi

# Извлечение данных из warp.conf
PRIVATE_KEY=$(grep 'PrivateKey' /etc/sing-box/warp.conf | awk '{print $3}')
WARP_IP4=$(grep 'Address' /etc/sing-box/warp.conf | grep -v ':' | awk '{print $3}' | head -n 1)
WARP_IP6=$(grep 'Address' /etc/sing-box/warp.conf | grep ':' | awk '{print $3}' | head -n 1)

echo -e "${GREEN}>>> Формирование конфига для перехвата ИИ...${NC}"
cat << EOF > /etc/sing-box/config.json
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
EOF

echo -e "${GREEN}>>> Настройка правил маршрутизации (iptables)...${NC}"
# Очищаем старые правила, если скрипт запускался ранее
iptables -t nat -D OUTPUT -p tcp -m owner --uid-owner sing-box -j RETURN 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345 2>/dev/null || true
iptables -t nat -D PREROUTING -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345 2>/dev/null || true

# Направляем локальный HTTP/HTTPS трафик в sing-box (кроме трафика самого sing-box)
iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner sing-box -j RETURN
iptables -t nat -A OUTPUT -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345
# Направляем трафик от других интерфейсов (например, от клиентов AmneziaVPN) в sing-box
iptables -t nat -A PREROUTING -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345

if [ -f /etc/debian_version ]; then
    netfilter-persistent save >/dev/null 2>&1 || iptables-save > /etc/iptables/rules.v4
fi

systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1
systemctl restart sing-box

echo -e "\n${BLUE}=========================================================${NC}"
echo -e "🎉 ${GREEN}Универсальная разблокировка успешно настроена!${NC}"
echo -e "${BLUE}=========================================================${NC}"
echo -e "Теперь трафик до ChatGPT, Gemini и Claude идет через WARP."
echo -e "Ваш основной VPN работает как обычно."
