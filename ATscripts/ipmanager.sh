#!/bin/bash
# =========================================
# Armbian 网络配置脚本（静态IP / DHCP / 查看配置，支持重启后保持IP）
# 修复版：处理连接名称中的空格和特殊字符
# =========================================

clear
echo "=============================="
echo "   Armbian 网络配置工具"
echo "=============================="

# 自动检测默认网卡
IFACE=$(ip route show default | awk '/default/ {print $5}' | head -n 1)

if [ -z "$IFACE" ]; then
    echo "⚠️ 未检测到默认网卡，请手动输入网卡名（如 eth0 / wlan0）:"
    read -p "网卡名: " IFACE
fi

echo "当前检测到的网卡：$IFACE"
echo

# 检查 NetworkManager 服务状态
if ! systemctl is-active --quiet NetworkManager; then
    echo "⚠️ NetworkManager 未运行，正在启动..."
    sudo systemctl start NetworkManager
    sleep 2
fi

# 列出所有可用的网络连接
echo ">>> 正在查找网络连接..."
echo "可用的网络连接列表："
sudo nmcli con show
echo

# 获取与当前网卡关联的连接（改进的检测方法）
CON_NAME=$(sudo nmcli -t -f NAME,DEVICE con show --active | grep ":$IFACE$" | cut -d':' -f1)

# 如果没找到活动连接，尝试查找所有连接
if [ -z "$CON_NAME" ]; then
    CON_NAME=$(sudo nmcli -t -f NAME,DEVICE con show | grep ":$IFACE$" | cut -d':' -f1 | head -n 1)
fi

# 如果还是没找到，让用户手动选择
if [ -z "$CON_NAME" ]; then
    echo "⚠️ 未自动检测到 $IFACE 的连接配置"
    echo "请从上面的列表中输入完整的连接名称（注意空格和大小写）："
    read -p "连接名称: " CON_NAME
    
    # 验证连接是否存在
    if ! sudo nmcli con show "$CON_NAME" &>/dev/null; then
        echo "❌ 连接 '$CON_NAME' 不存在，退出脚本"
        exit 1
    fi
fi

echo ">>> 将使用连接：$CON_NAME"
echo ">>> 关联网卡：$IFACE"
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

        echo
        echo ">>> 正在应用静态IP配置..."

        # 构建 DNS 参数
        if [ -n "$DNS2" ]; then
            DNS_PARAM="$DNS1 $DNS2"
        else
            DNS_PARAM="$DNS1"
        fi

        # 应用配置（使用引号包裹连接名称）
        if sudo nmcli con mod "$CON_NAME" \
            ipv4.method manual \
            ipv4.addresses "$IP_ADDR/$MASK" \
            ipv4.gateway "$GATEWAY" \
            ipv4.dns "$DNS_PARAM" \
            ipv4.ignore-auto-dns yes \
            connection.autoconnect yes; then
            
            echo ">>> 配置已应用，正在重启网络连接..."
            
            # 重启连接
            sudo nmcli con down "$CON_NAME" 2>/dev/null
            sleep 1
            sudo nmcli con up "$CON_NAME"
            
            echo
            echo "✅ 静态IP设置完成！当前网络信息："
            sleep 2
            nmcli dev show "$IFACE" | grep -E "IP4\.ADDRESS|IP4\.GATEWAY|IP4\.DNS"
        else
            echo "❌ 配置失败，请检查输入参数"
        fi
        ;;
    2)
        echo ">>> 正在切换为 DHCP 模式..."
        if sudo nmcli con mod "$CON_NAME" \
            ipv4.method auto \
            ipv4.dns "" \
            ipv4.ignore-auto-dns no \
            connection.autoconnect yes; then
            
            sudo nmcli con down "$CON_NAME" 2>/dev/null
            sleep 1
            sudo nmcli con up "$CON_NAME"

            echo
            echo "✅ 已切换为 DHCP 模式！当前网络信息："
            sleep 2
            nmcli dev show "$IFACE" | grep -E "IP4\.ADDRESS|IP4\.GATEWAY|IP4\.DNS"
        else
            echo "❌ 切换失败"
        fi
        echo
        ;;
    3)
        echo ">>> 当前网络配置如下："
        echo "连接名称：$CON_NAME"
        echo "网卡名称：$IFACE"
        echo

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

        nmcli con show "$CON_NAME" | grep -E "ipv4\.(method|addresses|gateway|dns)" || true
        echo
        echo "实际IP信息："
        nmcli dev show "$IFACE" | grep -E "IP4\.ADDRESS|IP4\.GATEWAY|IP4\.DNS" || true
        echo
        ;;
    4)
        echo ">>> 重新检测网络连接..."
        exec "$0"
        ;;
    5)
        echo "已退出。"
        exit 0
        ;;
    *)
        echo "❌ 无效选项，请输入 1~5。"
        ;;
    esac
done