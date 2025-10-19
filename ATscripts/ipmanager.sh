#!/bin/bash
# =========================================
# Armbian 网络配置管理
# =========================================

clear
echo "=============================="
echo "   Armbian 网络配置工具"
echo "=============================="

# 日志配置
LOG_DIR="/var/log/ATAsst"
LOG_FILE="$LOG_DIR/ipmanager.log"
sudo mkdir -p "$LOG_DIR"
sudo touch "$LOG_FILE"
# 尝试把日志文件归当前用户（若无权限忽略）
sudo chown "$(whoami)" "$LOG_FILE" 2>/dev/null || true

log() {
    local msg="$*"
    echo "$(date '+%F %T') $msg" >> "$LOG_FILE"
}

run_and_log() {
    local cmd="$*"
    log "CMD: $cmd"
    if output=$(eval "$cmd" 2>&1); then
        if [ -n "$output" ]; then
            log "OK: $output"
        else
            log "OK"
        fi
        return 0
    else
        log "ERROR: $output"
        return 1
    fi
}

log "脚本启动"

IFACE=$(ip route show default | awk '/default/ {print $5}' | head -n 1)

if [ -z "$IFACE" ]; then
    echo "⚠️ 未检测到默认网卡，请手动输入网卡名（如 eth0 / wlan0）:"
    read -p "网卡名: " IFACE
fi

echo "当前检测到的网卡：$IFACE"
log "检测到网卡: $IFACE"
echo

if ! systemctl is-active --quiet NetworkManager; then
    echo "⚠️ NetworkManager 未运行，正在启动..."
    log "NetworkManager 未运行，尝试启动"
    run_and_log "sudo systemctl start NetworkManager"
    sleep 2
fi

echo ">>> 正在查找网络连接..."
echo "可用的网络连接列表："
sudo nmcli --color yes con show | tee -a "$LOG_FILE" 
echo

CON_NAME=$(sudo nmcli -t -f NAME,DEVICE con show --active | grep ":$IFACE$" | cut -d':' -f1)

if [ -z "$CON_NAME" ]; then
    CON_NAME=$(sudo nmcli -t -f NAME,DEVICE con show | grep ":$IFACE$" | cut -d':' -f1 | head -n 1)
fi

if [ -z "$CON_NAME" ]; then
    echo "⚠️ 未自动检测到 $IFACE 的连接配置"
    echo "请从上面的列表中输入完整的连接名称（注意空格和大小写）："
    read -p "连接名称: " CON_NAME

    if ! sudo nmcli con show "$CON_NAME" &>/dev/null; then
        echo "❌ 连接 '$CON_NAME' 不存在，退出脚本"
        log "用户输入连接 '$CON_NAME' 不存在，退出"
        exit 1
    fi
fi

echo ">>> 将使用连接：$CON_NAME"
log "将使用连接: $CON_NAME"
echo ">>> 关联网卡：$IFACE"
log "将操作网卡: $IFACE"
echo

# 主菜单
while true; do
    echo "请选择操作："
    echo "1）设置静态 IP"
    echo "2）切换为 DHCP（自动获取IP）"
    echo "3）查看当前网络配置"
    echo "4）重新检测网络连接"
    echo "5）退出"
    read -p "请输入选项 [1-5]: " OPTION
    echo

    case "$OPTION" in
    1)
        echo ">>> 设置静态 IP 模式"
        read -p "请输入新的IP地址（例如 192.168.1.100）: " IP_ADDR
        read -p "请输入子网掩码CIDR（例如 24 表示255.255.255.0）: " MASK
        read -p "请输入网关地址（例如 192.168.1.1）: " GATEWAY
        read -p "请输入主DNS（例如 223.5.5.5）: " DNS1
        read -p "请输入备用DNS（可留空）: " DNS2

        log "设置静态IP: IP=$IP_ADDR/$MASK GATEWAY=$GATEWAY DNS1=$DNS1 DNS2=$DNS2"

        echo
        echo ">>> 正在应用静态IP配置..."

        if [ -n "$DNS2" ]; then
            DNS_PARAM="$DNS1 $DNS2"
        else
            DNS_PARAM="$DNS1"
        fi

        if run_and_log "sudo nmcli con mod \"${CON_NAME}\" \
            ipv4.method manual \
            ipv4.addresses \"${IP_ADDR}/${MASK}\" \
            ipv4.gateway \"${GATEWAY}\" \
            ipv4.dns \"${DNS_PARAM}\" \
            ipv4.ignore-auto-dns yes \
            connection.autoconnect yes"; then

            echo ">>> 配置已应用，正在重启网络连接..."
            log "已修改连接配置，尝试下线再上线连接: $CON_NAME"
            run_and_log "sudo nmcli con down \"${CON_NAME}\""
            sleep 1
            run_and_log "sudo nmcli con up \"${CON_NAME}\""

            echo
            echo "✅ 静态IP设置完成！当前网络信息："
            sleep 2
            nmcli dev show "$IFACE" | tee -a "$LOG_FILE" | grep -E "IP4\.ADDRESS|IP4\.GATEWAY|IP4\.DNS"
            log "静态IP设置完成，显示当前网络信息"
        else
            echo "❌ 配置失败，请检查输入参数"
            log "静态IP配置失败"
        fi
        ;;
    2)
        echo ">>> 正在切换为 DHCP 模式..."
        log "切换为 DHCP 模式"
        if run_and_log "sudo nmcli con mod \"${CON_NAME}\" \
            ipv4.method auto \
            ipv4.gateway \"\" \
            ipv4.dns \"\" \
            ipv4.ignore-auto-dns no \
            connection.autoconnect yes"; then

            run_and_log "sudo nmcli con down \"${CON_NAME}\""
            sleep 1
            run_and_log "sudo nmcli con up \"${CON_NAME}\""

            echo
            echo "✅ 已切换为 DHCP 模式！当前网络信息："
            sleep 2
            nmcli dev show "$IFACE" | tee -a "$LOG_FILE" | grep -E "IP4\.ADDRESS|IP4\.GATEWAY|IP4\.DNS"
            log "切换为 DHCP 完成，显示当前网络信息"
        else
            echo "❌ 切换失败"
            log "切换为 DHCP 失败"
        fi
        echo
        ;;
    3)
        echo ">>> 当前网络配置如下："
        echo "连接名称：$CON_NAME"
        echo "网卡名称：$IFACE"
        echo

        log "查看当前网络配置: $CON_NAME on $IFACE"
        # 获取并显示 ipv4.method（判断是静态还是 DHCP）
        IPV4_METHOD=$(nmcli -g ipv4.method con show "$CON_NAME" 2>/dev/null)
        if [ -z "$IPV4_METHOD" ]; then
            IPV4_METHOD="未知"
        fi

        case "$IPV4_METHOD" in
            manual) MODE_DESC="静态 IP";;
            auto)   MODE_DESC="DHCP（自动）";;
            disabled) MODE_DESC="IPv4 已禁用";;
            *)      MODE_DESC="$IPV4_METHOD";;
        esac

        echo "IP 模式：$MODE_DESC"
        echo

        nmcli con show "$CON_NAME" | tee -a "$LOG_FILE" | grep -E "ipv4\.(method|addresses|gateway|dns)" || true
        echo
        echo "实际IP信息："
        nmcli dev show "$IFACE" | tee -a "$LOG_FILE" | grep -E "IP4\.ADDRESS|IP4\.GATEWAY|IP4\.DNS" || true
        echo
        log "显示完当前网络配置"
        ;;
    4)
        echo ">>> 重新检测网络连接..."
        log "用户选择重新检测网络连接，重启脚本"
        exec "$0"
        ;;
    5)
        echo "已退出。"
        log "脚本退出"
        exit 0
        ;;
    *)
        echo "❌ 无效选项，请输入 1~5。"
        ;;
    esac
done