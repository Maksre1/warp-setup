#!/usr/bin/env bash

# ==============================================================================
# 🚀 VPS Auto-WARP & Optimization Configurator (v1.0)
# Разблокировка нейросетей на вашем сервере (Gemini, ChatGPT, Claude)
# ==============================================================================

# Принудительно читаем stdin из реального терминала.
# Это обязательно при запуске через: bash -c "$(curl ...)"
# Без этой строки read получает пустой stdin и не показывает ввод.
exec < /dev/tty

# Цвета для красивого вывода в терминал
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

clear

# Приветственный экран
echo -e "${BLUE}=========================================================${NC}"
echo -e "   🚀  ${GREEN}VPS Auto-WARP Configurator (v1.0)${NC}"
echo -e "   Разблокировка нейросетей на вашем сервере"
echo -e "   (Gemini, ChatGPT, Claude)"
echo -e "${BLUE}=========================================================${NC}"
echo ""
echo -e "Этот скрипт нужен для тех, у кого Gemini (или другие ИИ) пишет"
echo -e "«недоступно в вашей стране», несмотря на зарубежный VPS."
echo -e "Он настроит маршрутизацию трафика нейросетей через сеть"
echo -e "Cloudflare WARP на сервере. Остальной трафик продолжит"
echo -e "работать напрямую через ваш основной IP."
echo ""
echo -e "• Совместимо с AmneziaVPN и 3x-ui (Xray)."
echo -e "• Скрипт выполняется на вашем компьютере и никуда не"
echo -e "  передает ваши данные. В целях безопасности вы можете"
echo -e "  сменить пароль от VPS в личном кабинете хостинга"
echo -e "  сразу после завершения настройки."
echo ""

# Запрос согласия
read -p "Вы согласны продолжить настройку? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo -e "\n${YELLOW}Настройка отменена.${NC}\n"
    exit 0
fi

echo -e "\n---------------------------------------------------------"
echo -e "Укажите параметры подключения к вашему VPS-серверу:"
echo -e "---------------------------------------------------------"

# Запрос данных для подключения
read -p "[?] IP-адрес сервера (например, 185.12.34.56): " VPS_IP
if [ -z "$VPS_IP" ]; then
    echo -e "${RED}Ошибка: IP-адрес не может быть пустым.${NC}"
    exit 1
fi

# Порт по умолчанию 22
read -p "[?] SSH-порт сервера [22]: " VPS_PORT
VPS_PORT=${VPS_PORT:-22}

# Пользователь по умолчанию root
read -p "[?] Имя пользователя SSH [root]: " VPS_USER
VPS_USER=${VPS_USER:-root}

# Запрос пароля (виден при вводе и вставке)
read -p "[?] Пароль SSH: " VPS_PASS
echo ""

# Принудительно добавляем brew-пути (macOS ARM и Intel) в PATH
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Проверка доступности sshpass
SSHPASS_BIN="$(command -v sshpass 2>/dev/null)"

if [ -z "$SSHPASS_BIN" ]; then
    echo -e "\n[i] Устанавливаем вспомогательный компонент (sshpass)..."
    if [[ "$(uname)" == "Darwin" ]]; then
        if command -v brew &>/dev/null; then
            brew install hudochenkov/sshpass/sshpass 2>&1 | grep -v '^==>'
            # После установки явно ищем бинарник по всем известным путям brew
            for brew_path in "/opt/homebrew/bin/sshpass" "/usr/local/bin/sshpass"; do
                if [ -x "$brew_path" ]; then
                    SSHPASS_BIN="$brew_path"
                    break
                fi
            done
        else
            echo -e "${RED}[✗] Homebrew не найден. Установите его с brew.sh и повторите.${NC}"
            exit 1
        fi
    elif [ -f /etc/debian_version ]; then
        sudo apt-get install -y sshpass >/dev/null 2>&1
        SSHPASS_BIN="$(command -v sshpass 2>/dev/null)"
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y sshpass >/dev/null 2>&1
        SSHPASS_BIN="$(command -v sshpass 2>/dev/null)"
    fi
fi

if [ -z "$SSHPASS_BIN" ] || [ ! -x "$SSHPASS_BIN" ]; then
    echo -e "${RED}[✗] Не удалось найти sshpass. Попробуйте установить его вручную.${NC}"
    exit 1
fi

echo -e "\n[i] Проверяем подключение к $VPS_IP..."

# Очищаем устаревший ключ хоста (если сервер переустанавливали)
ssh-keygen -R "$VPS_IP" >/dev/null 2>&1 || true
ssh-keygen -R "[$VPS_IP]:$VPS_PORT" >/dev/null 2>&1 || true

# Проверка подключения с явным указанием password-аутентификации
conn_test=$(SSHPASS="$VPS_PASS" "$SSHPASS_BIN" -e ssh \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=no \
    -o BatchMode=no \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -p "$VPS_PORT" \
    "$VPS_USER@$VPS_IP" \
    "echo OK" 2>&1)

if [[ "$conn_test" != *"OK"* ]]; then
    echo -e "${RED}[✗] Ошибка подключения!${NC}"
    if [[ "$conn_test" == *"Permission denied"* ]] || [[ "$conn_test" == *"Authentication failed"* ]]; then
        echo -e "    Неверный логин или пароль. Проверьте данные и повторите попытку."
    elif [[ "$conn_test" == *"Connection refused"* ]] || [[ "$conn_test" == *"timed out"* ]]; then
        echo -e "    Сервер $VPS_IP на порту $VPS_PORT недоступен."
        echo -e "    Убедитесь, что IP-адрес и порт введены верно."
    else
        echo -e "    ${YELLOW}$conn_test${NC}"
    fi
    echo ""
    exit 1
fi

echo -e "${GREEN}[✓] Успешное подключение к серверу $VPS_IP!${NC}"

# Подготовка скрипта для выполнения на стороне сервера
# Этот блок команд передается в удаленный shell
REMOTE_SCRIPT=$(cat << 'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive

# Перехват ошибок: отправляем в FIFO понятное сообщение
trap 'echo "ERROR:Ошибка на сервере (строка $LINENO): $BASH_COMMAND"' ERR

# Функция для обновления статуса на удаленной стороне
status_update() {
    echo "PROGRESS:$1:$2"
}

# Синхронизация времени сервера (критично для WireGuard/WARP handshakes)
timedatectl set-ntp true >/dev/null 2>&1 || true

# 1. Установка системных зависимостей
status_update 20 "Установка компонентов"
if [ -f /etc/debian_version ]; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl jq iptables iptables-persistent >/dev/null 2>&1
elif [ -f /etc/redhat-release ]; then
    yum install -y curl jq iptables iptables-services >/dev/null 2>&1
    if ! command -v jq &> /dev/null; then
        yum install -y epel-release >/dev/null 2>&1
        yum install -y jq >/dev/null 2>&1
    fi
else
    echo "ERROR: Неподдерживаемая ОС на сервере"
    exit 1
fi

# 2. Установка sing-box
status_update 30 "Установка sing-box"
if [ -f /etc/debian_version ]; then
    curl -fsSL https://sing-box.app/deb-install.sh | bash >/dev/null 2>&1
elif [ -f /etc/redhat-release ]; then
    curl -fsSL https://sing-box.app/rpm-install.sh | bash >/dev/null 2>&1
fi

# Создаем папку под конфиг, если нет
mkdir -p /etc/sing-box

# Регистрация WARP через wgcf (поддерживаемый CLI, всегда актуальный API)
status_update 40 "Настройка WARP"

# Определяем архитектуру сервера
ARCH=$(uname -m)
case $ARCH in
    x86_64)  WGCF_ARCH="amd64" ;;
    aarch64|arm64) WGCF_ARCH="arm64" ;;
    armv7l)  WGCF_ARCH="armv7" ;;
    *) echo "ERROR: Неподдерживаемая архитектура: $ARCH"; exit 1 ;;
esac

# Скачиваем wgcf
WGCF_VER="2.2.26"
curl -fsSL "https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VER}/wgcf_${WGCF_VER}_linux_${WGCF_ARCH}" \
    -o /tmp/wgcf >/dev/null 2>&1
chmod +x /tmp/wgcf

# Регистрируем бесплатное устройство WARP
cd /tmp
/tmp/wgcf register --accept-tos >/dev/null 2>&1
/tmp/wgcf generate >/dev/null 2>&1

# Парсим WireGuard-профиль
private_key=$(awk '/^PrivateKey/{print $3}' /tmp/wgcf-profile.conf)
warp_ip4="$(awk '/^Address/{print $3}' /tmp/wgcf-profile.conf | grep -v ':' | head -1)"
warp_ip6="$(awk '/^Address/{print $3}' /tmp/wgcf-profile.conf | grep ':' | head -1)"

# Получаем reserved байты из account-файла (нужны для handshake с Cloudflare)
client_id=$(grep 'client_id' /tmp/wgcf-account.toml 2>/dev/null | awk -F'"' '{print $2}' || true)
if [ -n "$client_id" ]; then
    warp_reserved=$(python3 -c "import base64,json; b=base64.b64decode('$client_id'); print(json.dumps(list(b[:3])))" 2>/dev/null || echo "[0,0,0]")
else
    warp_reserved="[0,0,0]"
fi

# Убираем временные файлы wgcf
rm -f /tmp/wgcf /tmp/wgcf-account.toml /tmp/wgcf-profile.conf
cd /

# Запись конфига sing-box (с интеграцией DNS-over-HTTPS и TCP Fast Open)
cat << SECONF > /etc/sing-box/config.json
{
  "log": {
    "level": "warning"
  },
  "dns": {
    "servers": [
      {
        "tag": "dns-remote",
        "address": "https://1.1.1.1/dns-query",
        "detour": "warp"
      },
      {
        "tag": "dns-local",
        "address": "8.8.8.8",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "domain_suffix": [
          "gemini.google.com",
          "aistudio.google.com",
          "vertexai.google.com",
          "deepmind.google",
          "deepmind.com",
          "google.ai",
          "ai.google",
          "ai.google.com",
          "generativelanguage.googleapis.com",
          "makersuite.google.com",
          "openai.com",
          "chatgpt.com",
          "oaistatic.com",
          "oaiusercontent.com",
          "anthropic.com",
          "claude.ai",
          "challenges.cloudflare.com"
        ],
        "server": "dns-remote"
      }
    ],
    "final": "dns-local"
  },
  "inbounds": [
    {
      "type": "redirect",
      "tag": "redirect-in",
      "listen": "0.0.0.0",
      "listen_port": 12345,
      "sniff": true,
      "sniff_override_destination": true
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "tcp_fast_open": true
    },
    {
      "type": "wireguard",
      "tag": "warp",
      "server": "engage.cloudflareclient.com",
      "server_port": 2408,
      "local_address": [
        "$warp_ip4",
        "$warp_ip6"
      ],
      "private_key": "$private_key",
      "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "reserved": $warp_reserved,
      "mtu": 1280
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "domain_suffix": [
          "gemini.google.com",
          "aistudio.google.com",
          "vertexai.google.com",
          "deepmind.google",
          "deepmind.com",
          "google.ai",
          "ai.google",
          "ai.google.com",
          "generativelanguage.googleapis.com",
          "makersuite.google.com",
          "openai.com",
          "chatgpt.com",
          "oaistatic.com",
          "oaiusercontent.com",
          "anthropic.com",
          "claude.ai",
          "challenges.cloudflare.com"
        ],
        "outbound": "warp"
      },
      {
        "outbound": "direct"
      }
    ]
  }
}
SECONF

# Настройка системных лимитов файлов LimitNOFILE для службы sing-box
mkdir -p /etc/systemd/system/sing-box.service.d
cat << SYSTEMDOVER > /etc/systemd/system/sing-box.service.d/override.conf
[Service]
LimitNOFILE=1048576
SYSTEMDOVER

# Перезапуск sing-box
systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1
systemctl restart sing-box

# 3. Оптимизация системы (BBR + TCP + скрытие пинга)
status_update 60 "Оптимизация"

# Динамический расчет ресурсов RAM
total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
if [ "$total_mem_kb" -le 1500000 ]; then
    # RAM <= 1.5 GB
    tcp_rmem="4096 87380 4194304"
    tcp_wmem="4096 65536 4194304"
    somaxconn="2048"
    file_max="100000"
elif [ "$total_mem_kb" -le 4500000 ]; then
    # RAM 1.5 GB - 4.5 GB
    tcp_rmem="4096 87380 8388608"
    tcp_wmem="4096 65536 8388608"
    somaxconn="8192"
    file_max="300000"
else
    # RAM > 4.5 GB
    tcp_rmem="4096 87380 16777216"
    tcp_wmem="4096 65536 16777216"
    somaxconn="65535"
    file_max="1000000"
fi

# Проверяем поддержку BBR ядром и виртуализацией
bbr_supported=0
if sysctl net.ipv4.tcp_allowed_congestion_control 2>/dev/null | grep -q "bbr" || modprobe tcp_bbr 2>/dev/null; then
    bbr_supported=1
fi

# Пишем оптимизации в sysctl
cat << SYSCONF > /etc/sysctl.d/99-server-optimization.conf
# TCP Buffer sizes
net.ipv4.tcp_rmem=$tcp_rmem
net.ipv4.tcp_wmem=$tcp_wmem

# File descriptors and connections limits
fs.file-max=$file_max
net.core.somaxconn=$somaxconn
net.core.netdev_max_backlog=100000

# Security: Ignore all ping requests from bots
net.ipv4.icmp_echo_ignore_all=1

# TCP optimizations
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=15
net.ipv4.tcp_keepalive_probes=5
SYSCONF

if [ "$bbr_supported" -eq 1 ]; then
    cat << BBRCONF >> /etc/sysctl.d/99-server-optimization.conf
# BBR Congestion Control
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
BBRCONF
fi

# Применяем настройки sysctl (|| true защищает от сбоев на OpenVZ/LXC контейнерах)
sysctl --system >/dev/null 2>&1 || true

# 4. Настройка файрвола (iptables)
status_update 80 "Настройка файрвола"

# Очистим старые правила перехвата для sing-box (если переустановка)
iptables -t nat -D PREROUTING -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp -m owner --uid-owner sing-box -j RETURN 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345 2>/dev/null || true
iptables -D FORWARD -p udp --dport 443 -j REJECT 2>/dev/null || true
iptables -D OUTPUT -p udp --dport 443 -j REJECT 2>/dev/null || true

# Добавляем новые правила
# Перехват локального трафика на порты 80,443 (кроме самого sing-box)
iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner sing-box -j RETURN
iptables -t nat -A OUTPUT -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345
# Перехват входящего трафика от докеров (AmneziaVPN)
iptables -t nat -A PREROUTING -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports 12345

# Блокировка QUIC (чтобы форсировать падение на TCP)
iptables -A FORWARD -p udp --dport 443 -j REJECT
iptables -A OUTPUT -p udp --dport 443 -j REJECT

# Сохранение правил iptables для автозапуска
if [ -f /etc/debian_version ]; then
    netfilter-persistent save >/dev/null 2>&1 || iptables-save > /etc/iptables/rules.v4
elif [ -f /etc/redhat-release ]; then
    service iptables save >/dev/null 2>&1 || iptables-save > /etc/sysconfig/iptables
fi

status_update 100 "Завершение настройки"
EOF
)

# Функция для вывода прогресс-бара
draw_progress_bar() {
    local percent=$1
    local text=$2
    local bar_length=20
    local filled_length=$(( percent * bar_length / 100 ))
    local unfilled_length=$(( bar_length - filled_length ))
    
    local bar=""
    for ((i=0; i<filled_length; i++)); do bar="${bar}█"; done
    for ((i=0; i<unfilled_length; i++)); do bar="${bar}░"; done
    
    # Очистка строки и вывод нового прогресс-бара
    printf "\r[i] Выполняется настройка и оптимизация сервера...\n"
    printf "\r[${bar}] ${percent}%% (${text})"
    # Возвращаемся на строку выше для красивого обновления
    printf "\033[A"
}

# Запуск SSH соединения и выполнение команд с отслеживанием прогресса
error_occurred=0
ssh_connected=1  # уже проверено выше

# Временный именованный канал для сбора прогресса
FIFO_FILE="/tmp/warp_ssh_progress_$$"
mkfifo "$FIFO_FILE"

# Временный файл со скриптом для передачи через stdin
TMP_SCRIPT="/tmp/warp_remote_script_$$"
echo "$REMOTE_SCRIPT" > "$TMP_SCRIPT"

# Запускаем SSH через sshpass в фоновом режиме, перенаправляя вывод в FIFO
SSHPASS="$VPS_PASS" "$SSHPASS_BIN" -e ssh \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=no \
    -o BatchMode=no \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -p "$VPS_PORT" \
    "$VPS_USER@$VPS_IP" \
    "bash -s" < "$TMP_SCRIPT" > "$FIFO_FILE" 2>&1 &

SSH_PID=$!

echo ""

# Читаем FIFO и выводим прогресс-бар
while IFS= read -r line; do
    if [[ "$line" == PROGRESS:* ]]; then
        percent=$(echo "$line" | cut -d':' -f2)
        text=$(echo "$line" | cut -d':' -f3)
        draw_progress_bar "$percent" "$text"
    elif [[ "$line" == ERROR:* ]]; then
        error_occurred=1
        err_msg=$(echo "$line" | cut -d':' -f2-)
        # Сразу выводим ошибку сервера в терминал
        printf "\n\n${RED}%s${NC}\n" "$err_msg" >&2
    fi
done < "$FIFO_FILE"

# Ждем завершения фонового процесса SSH
wait $SSH_PID 2>/dev/null
ssh_status=$?

rm -f "$FIFO_FILE" "$TMP_SCRIPT"

# Очищаем пароль из памяти
unset VPS_PASS

# Обработка результатов установки
if [ "$ssh_status" -ne 0 ] || [ "$error_occurred" -ne 0 ]; then
    echo -e "\n\n${RED}[✗] Ошибка подключения или установки!${NC}"
    if [ -n "$err_msg" ]; then
        echo -e "    Детали: ${YELLOW}$err_msg${NC}"
    else
        echo -e "    Убедитесь, что IP-адрес, порт, имя пользователя и пароль введены верно."
    fi
    echo ""
    exit 1
fi

# Сдвигаемся вниз после прогресс-бара
printf "\n\n"

# Финальный баннер
echo -e "${BLUE}=========================================================${NC}"
echo -e "   🎉  ${GREEN}НАСТРОЙКА УСПЕШНО ЗАВЕРШЕНА!${NC}"
echo -e "${BLUE}=========================================================${NC}"
echo ""
echo -e "Все службы настроены и запущены."
echo -e "${GREEN}Приятного использования!${NC}"
echo ""
echo -e "${YELLOW}💡 РЕКОМЕНДАЦИЯ ПО БЕЗОПАСНОСТИ:${NC}"
echo -e "   Поскольку настройка завершена, мы рекомендуем зайти"
echo -e "   в личный кабинет вашего VPS-хостинга и сменить пароль"
echo -e "   от сервера."
echo ""
echo -e "${BLUE}=========================================================${NC}"
read -n 1 -s -r -p "Для выхода нажмите любую клавишу..."
echo ""
exit 0
