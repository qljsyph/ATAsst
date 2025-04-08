#!/bin/bash
#v1.11.1
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 用户运行此脚本。"
    exit 1
fi
LOG_FILE="/var/log/AT_install.log"

function log_message() {
    echo "$1" | tee -a "$LOG_FILE"
}

true > "$LOG_FILE"

log_message "===== 开始安装脚本 ====="

if ! command -v sudo &> /dev/null; then
    log_message "未检测到 sudo，正在安装..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get update && sudo apt-get install -y sudo || { log_message "安装 sudo 失败！"; exit 1; }
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y sudo || { log_message "安装 sudo 失败！"; exit 1; }
    else
        log_message "无法通过 apt-get 或 yum 安装 sudo，请手动安装！"
        exit 1
    fi
else
    log_message "已安装 sudo"
fi

if ! command -v tar &> /dev/null; then
    log_message "未检测到 tar，正在安装..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get install -y tar || { log_message "安装 tar 失败！"; exit 1; }
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y tar || { log_message "安装 tar 失败！"; exit 1; }
    else
        log_message "无法通过 apt-get 或 yum 安装 tar，请手动安装！"
        exit 1
    fi
else
    log_message "已安装 tar"
fi

if ! command -v gzip &> /dev/null; then
    log_message "未检测到 gzip，正在安装..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get install -y gzip || { log_message "安装 gzip 失败！"; exit 1; }
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y gzip || { log_message "安装 gzip 失败！"; exit 1; }
    else
        log_message "无法通过 apt-get 或 yum 安装 gzip，请手动安装！"
        exit 1
    fi
else
    log_message "已安装 gzip"
fi

if ! command -v wget &> /dev/null; then
    log_message "未检测到 wget，正在安装..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get install -y wget || { log_message "安装 wget 失败！"; exit 1; }
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y wget || { log_message "安装 wget 失败！"; exit 1; }
    else
        log_message "无法通过 apt-get 或 yum 安装 wget，请手动安装！"
        exit 1
    fi
else
    log_message "已安装 wget"
fi

if ! command -v curl &> /dev/null; then
    log_message "未检测到 curl，正在安装..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get install -y curl || { log_message "安装 curl 失败！"; exit 1; }
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y curl || { log_message "安装 curl 失败！"; exit 1; }
    else
        log_message "无法通过 apt-get 或 yum 安装 curl，请手动安装！"
        exit 1
    fi
else
    log_message "已安装 curl"
fi

if ! command -v jq &> /dev/null; then
    log_message "未检测到 jq，正在安装..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get install -y jq || { log_message "安装 jq 失败！"; exit 1; }
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y jq || { log_message "安装 jq 失败！"; exit 1; }
    else
        log_message "无法通过 apt-get 或 yum 安装 jq，请手动安装！"
        exit 1
    fi
else
    log_message "已安装 jq"
fi

SCRIPTS_DIR="/etc/mihomo/scripts"
if [ ! -d "$SCRIPTS_DIR" ]; then
    log_message "脚本目录不存在，正在创建目录..."
    sudo mkdir -p "$SCRIPTS_DIR" || { log_message "创建脚本目录失败！"; exit 1; }
fi

log_message "设置脚本目录权限为 755 ..."
sudo chmod -R 755 "$SCRIPTS_DIR" || { log_message "设置脚本目录权限失败！"; exit 1; }

log_message "下载安装..."
wget -O "$SCRIPTS_DIR/menu.sh" "https://ghfast.top/https://raw.githubusercontent.com/qljsyph/ATAsst/refs/heads/watch/ATscripts/menu.sh" > /dev/null 2>&1 || { log_message "下载 menu.sh 失败！"; exit 1; }

log_message "开始集成 config.yaml 监控服务（mihomo-watch）..."

# 安装 inotify-tools（用于监控文件变化）
if ! command -v inotifywait &> /dev/null; then
    log_message "未检测到 inotify-tools，正在安装..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get install -y inotify-tools || { log_message "安装 inotify-tools 失败！"; exit 1; }
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y inotify-tools || { log_message "安装 inotify-tools 失败！"; exit 1; }
    else
        log_message "无法通过 apt-get 或 yum 安装 inotify-tools，请手动安装！"
        exit 1
    fi
else
    log_message "已安装 inotify-tools"
fi

# 创建 watch-mihomo.sh 脚本
WATCH_SCRIPT="$SCRIPTS_DIR/watch-mihomo.sh"
log_message "生成监控脚本 $WATCH_SCRIPT ..."
cat << 'EOF' | sudo tee "$WATCH_SCRIPT" > /dev/null
#!/bin/bash
WATCH_DIR="/etc/mihomo"
WATCH_FILE="config.yaml"

echo "开始监控 $WATCH_DIR/$WATCH_FILE ..."

while true; do
    change=$(inotifywait -e modify,create,delete,move "$WATCH_DIR" --format '%f' --quiet)
    if [ "$change" = "$WATCH_FILE" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 检测到 $WATCH_FILE 被修改，重启 mihomo.service"
        systemctl stop mihomo
        systemctl start mihomo
    fi
done
EOF

sudo chmod +x "$WATCH_SCRIPT" || { log_message "设置监控脚本权限失败！"; exit 1; }

# 创建 systemd 服务文件
SERVICE_FILE="/etc/systemd/system/mihomo-watch.service"
log_message "创建 systemd 服务文件 $SERVICE_FILE ..."
cat << EOF | sudo tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=Watch config.yaml and reload mihomo on change
After=network.target
Wants=mihomo.service

[Service]
ExecStart=$WATCH_SCRIPT
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

log_message "创建快捷方式..."
echo "#!/bin/bash" | sudo tee /usr/local/bin/AT > /dev/null
echo "bash /etc/mihomo/scripts/menu.sh" | sudo tee -a /usr/local/bin/AT > /dev/null
sudo chmod +x /usr/local/bin/AT || { log_message "创建快捷方式失败！"; exit 1; }

log_message "===== 安装完成 ====="

echo "安装完成！现在你可以在终端中输入 'AT' 来运行程序。"