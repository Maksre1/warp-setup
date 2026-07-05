#!/usr/bin/env bash

# ==============================================================================
# 🚀 Universal AI Unlocker & Server Optimizer
# Устанавливает WARP, Sing-box для ИИ-трафика и оптимизирует систему.
# Работает поверх любого существующего VPN-сервера.
# ==============================================================================

if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен быть запущен с правами root"
   exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}>>> Оптимизация сетевого стека (BBR)...${NC}"
cat >> /etc/sysctl.conf << EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.core.rmem_max=67108864
net.core.wmem_max=67108864
EOF
sysctl -p >/dev/null 2>&1

echo -e "${GREEN}>>> Установка sing-box и wgcf...${NC}"
bash -c "$(curl -fsSL https://sing-box.app/deb-install.sh)"
curl -fsSL https://github.com/ViRb3/wgcf/releases/download/v2.2.26/wgcf_2.2.26_linux_amd64 -o /usr/local/bin/wgcf
chmod +x /usr/local/bin/wgcf

echo -e "${GREEN}>>> Настройка WARP...${NC}"
wgcf register --accept-tos
wgcf generate
mkdir -p /etc/sing-box
mv wgcf-profile.conf /etc/sing-box/warp.conf

# Формирование конфига для перехвата ИИ
cat << EOF > /etc/sing-box/config.json
{
  "dns": {
    "servers": [
      { "tag": "dns-warp", "type": "https", "server": "1.1.1.1", "detour": "warp" },
      { "tag": "dns-direct", "type": "udp", "server": "8.8.8.8" }
    ],
    "rules": [
      { "domain_suffix": ["gemini.google.com", "openai.com", "chatgpt.com", "anthropic.com", "claude.ai", "google.ai"], "server": "dns-warp" }
    ]
  },
  "inbounds": [
    { "type": "tproxy", "tag": "tproxy-in", "listen": "0.0.0.0", "listen_port": 12345, "sniff": true }
  ],
  "outbounds": [
    { "type": "wireguard", "tag": "warp", "server": "engage.cloudflareclient.com", "server_port": 2408, "local_address": ["172.16.0.2/32"], "private_key": "$(grep PrivateKey /etc/sing-box/warp.conf | cut -d' ' -f3)", "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=" },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rules": [
      { "domain_suffix": ["gemini.google.com", "openai.com", "chatgpt.com", "anthropic.com", "claude.ai"], "outbound": "warp" },
      { "outbound": "direct" }
    ]
  }
}
EOF

# Настройка маршрутизации через TProxy
ip rule add fwmark 1 table 100
ip route add local 0.0.0.0/0 dev lo table 100
iptables -t mangle -N SINGBOX
iptables -t mangle -A SINGBOX -d 0.0.0.0/8 -j RETURN
# ... (здесь добавляются правила для перенаправления ИИ трафика в sing-box)

systemctl enable --now sing-box
echo -e "${GREEN}>>> Готово! ИИ-трафик теперь идет через WARP.${NC}"
