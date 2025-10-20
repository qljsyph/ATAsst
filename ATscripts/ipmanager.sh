#!/bin/bash
# =========================================
# 网络配置管理
# =========================================
#1.13.2
# 颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear

IFACE=$(ip -br link show | awk '{print $1}' | grep -v "lo" | head -n 1)
[ -z "$IFACE" ] && { echo -e "${RED}未找到网络接口，程序退出${NC}"; exit 1; }

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

# 全局 run_and_log 函数
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

if command -v nmcli >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager && nmcli device status | grep -qw "$IFACE"; then
    NET_MODE="nmcli"
elif grep -q "$IFACE" /etc/network/interfaces 2>/dev/null; then
    NET_MODE="interfaces"
elif grep -qr "$IFACE" /etc/netplan/*.yaml 2>/dev/null; then
    NET_MODE="netplan"
else
    NET_MODE="unknown"
fi

echo -e "${YELLOW}检测到网络接口: $IFACE${NC}"
log "检测到网络接口: $IFACE, 网络管理方式: $NET_MODE"

echo "当前检测到的网卡：$IFACE"
log "检测到网卡: $IFACE"
echo

if [ "$NET_MODE" = "interfaces" ]; then
    log "检测到 interfaces 管理模式"

    INTERFACE="$IFACE"

    log "检测到 Debian 系统，进入 Debian 网络管理逻辑"

    echo "=============================="
    echo "         网络配置工具"
    echo "=============================="
    echo -e "${YELLOW}检测到的网络接口是: $INTERFACE${NC}"

    while true; do
        echo "1）设置静态 IP"
        echo "2）切换为 DHCP 模式"
        echo "3）查看当前网络配置"
        echo "4）退出"
        read -p "请输入选项 [1-4]: " D_OPTION

        case "$D_OPTION" in
            1)
                read -rp "请输入静态 IP 地址: " IP_ADDRESS
                read -rp "请输入网关地址: " GATEWAY
                read -rp "请输入 DNS 服务器地址 (多个地址用空格分隔): " DNS_SERVERS
                log "用户选择设置静态 IP: IP=$IP_ADDRESS GATEWAY=$GATEWAY DNS=$DNS_SERVERS"

                INTERFACES_FILE="/etc/network/interfaces"
                RESOLV_CONF_FILE="/etc/resolv.conf"

                cat > $INTERFACES_FILE <<EOL
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug $INTERFACE
iface $INTERFACE inet static
    address $IP_ADDRESS
    netmask 255.255.255.0
    gateway $GATEWAY
EOL

                echo > $RESOLV_CONF_FILE
                for dns in $DNS_SERVERS; do
                    echo "nameserver $dns" >> $RESOLV_CONF_FILE
                done


                run_and_log "sudo systemctl restart networking"
                echo -e "${GREEN}静态 IP 地址和 DNS 配置完成！${NC}"
                ;;
            2)
                log "用户选择切换为 DHCP 模式"
                INTERFACES_FILE="/etc/network/interfaces"
                cat > $INTERFACES_FILE <<EOL
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug $INTERFACE
iface $INTERFACE inet dhcp
EOL
                run_and_log "sudo systemctl restart networking"
                echo -e "${GREEN}已切换为 DHCP 模式。${NC}"
                ;;
            3)
                log "用户查看当前网络配置"
                echo -e "${YELLOW}当前网络配置:${NC}"
                ip addr show "$INTERFACE" | grep "inet "
                echo
                echo -e "${YELLOW}默认网关:${NC}"
                ip route show default
                echo
                echo -e "${YELLOW}DNS 服务器:${NC}"
                grep 'nameserver' /etc/resolv.conf
                ;;
            4)
                log "用户退出 Debian 网络配置工具"
                echo "已退出。"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请输入 1~4。${NC}"
                ;;
        esac
    done

elif [ "$NET_MODE" = "netplan" ]; then
    log "检测到 Netplan 配置，使用 Netplan 模式"
    echo "=============================="
    echo "         网络配置工具"
    echo "=============================="
    CONFIG_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -n 1)
    if [ -z "$CONFIG_FILE" ]; then
        echo -e "${RED}未找到 Netplan 配置文件，程序退出。${NC}"
        log "未找到 Netplan 配置文件，退出"
        exit 1
    fi

    INTERFACE="$IFACE"
    echo -e "${YELLOW}检测到的网络接口是: $INTERFACE${NC}"

    backup_netplan() {
        BACKUP_FILE="${CONFIG_FILE}.bak-$(date +%Y%m%d-%H%M%S)"
        sudo cp "$CONFIG_FILE" "$BACKUP_FILE"
        log "Netplan配置已备份到 $BACKUP_FILE"
        echo "$BACKUP_FILE"
    }

    restore_netplan() {
        local backup="$1"
        if [ -f "$backup" ]; then
            sudo cp "$backup" "$CONFIG_FILE"
            log "恢复 Netplan 配置文件自备份 $backup"
            if run_and_log "sudo netplan apply"; then
                echo -e "${GREEN}已成功恢复并应用备份配置。${NC}"
                log "恢复并应用备份配置成功"
            else
                echo -e "${RED}恢复后应用配置失败，请手动检查。${NC}"
                log "恢复后应用配置失败"
            fi
        else
            echo -e "${RED}备份文件不存在，无法恢复。${NC}"
            log "备份文件不存在，恢复失败"
        fi
    }

    show_current_netplan_config() {
        echo -e "${YELLOW}当前网络配置:${NC}"
        ip addr show "$INTERFACE" | grep "inet "
        echo
        echo -e "${YELLOW}默认网关:${NC}"
        ip route show default
        echo
        echo -e "${YELLOW}DNS 服务器:${NC}"
        grep 'nameserver' /etc/resolv.conf || echo "无 DNS 服务器配置"
    }


    while true; do
        echo "1）设置静态 IP"
        echo "2）切换为 DHCP"
        echo "3）查看当前网络配置"
        echo "4）恢复最近备份"
        echo "5）退出"
        read -p "请输入选项 [1-5]: " N_OPTION

        case "$N_OPTION" in
            1)
                read -rp "请输入静态 IP 地址（带CIDR，例如 192.168.1.100/24）: " IP_CIDR
                read -rp "请输入网关地址: " GATEWAY
                read -rp "请输入 DNS 服务器地址 (多个用空格分隔): " DNS_SERVERS
                log "用户选择设置静态 IP: IP=$IP_CIDR GATEWAY=$GATEWAY DNS=$DNS_SERVERS"

                BACKUP_FILE=$(backup_netplan)

                # 生成 DNS 列表
                DNS_YAML=""
                for dns in $DNS_SERVERS; do
                    DNS_YAML+="      - $dns\n"
                done

                # 写入配置文件
                sudo tee "$CONFIG_FILE" > /dev/null <<EOL
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses:
        - $IP_CIDR
      gateway4: $GATEWAY
      nameservers:
        addresses:
$(echo -e "$DNS_YAML")
EOL

                if ! sudo netplan try --timeout 5; then
                    echo -e "${RED}配置验证失败，正在恢复备份...${NC}"
                    log "netplan try 验证失败，恢复备份"
                    restore_netplan "$BACKUP_FILE"
                    continue
                fi

                if run_and_log "sudo netplan apply"; then
                    echo -e "${GREEN}静态 IP 配置已应用！${NC}"
                else
                    echo -e "${RED}应用配置失败，正在恢复备份...${NC}"
                    log "netplan apply 失败，恢复备份"
                    restore_netplan "$BACKUP_FILE"
                fi
                ;;
            2)
                log "用户选择切换为 DHCP 模式"

                BACKUP_FILE=$(backup_netplan)

                sudo tee "$CONFIG_FILE" > /dev/null <<EOL
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: yes
EOL

                if run_and_log "sudo netplan apply"; then
                    echo -e "${GREEN}已切换为 DHCP 模式。${NC}"
                else
                    echo -e "${RED}应用配置失败，正在恢复备份...${NC}"
                    log "netplan apply 失败，恢复备份"
                    restore_netplan "$BACKUP_FILE"
                fi
                ;;
            3)
                log "用户查看当前网络配置"
                show_current_netplan_config
                ;;
            4)
                log "用户选择恢复最近备份"
                LATEST_BACKUP=$(ls -t ${CONFIG_FILE}.bak-* 2>/dev/null | head -n 1)
                if [ -z "$LATEST_BACKUP" ]; then
                    echo -e "${RED}未找到备份文件，无法恢复。${NC}"
                    log "未找到备份文件，恢复失败"
                else
                    echo "恢复备份文件：$LATEST_BACKUP ? [y/N]"
                    read -r confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        restore_netplan "$LATEST_BACKUP"
                    else
                        echo "取消恢复备份。"
                        log "用户取消恢复备份"
                    fi
                fi
                ;;
            5)
                log "用户退出 Netplan 网络配置工具"
                echo "已退出。"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请输入 1~5。${NC}"
                ;;
        esac
    done

elif [ "$NET_MODE" = "nmcli" ]; then

    log "检测到 NetworkManager 管理模式"

    NM_IFACE=$(nmcli -t -f DEVICE,STATE device | grep ":connected$" | cut -d':' -f1 | head -n1)
    if [ -n "$NM_IFACE" ] && ! nmcli device | awk '{print $1}' | grep -qw "$IFACE"; then
        echo "⚙️ 自动检测到 NetworkManager 实际使用接口：$NM_IFACE"
        log "修正接口名称: $IFACE → $NM_IFACE (由 NetworkManager 管理)"
        IFACE="$NM_IFACE"
    fi

    echo "=============================="
    echo "          网络配置工具"
    echo "=============================="
    CON_NAME=$(nmcli -t -f NAME,DEVICE con show --active | grep ":$IFACE$" | cut -d':' -f1)

    if [ -z "$CON_NAME" ]; then
        CON_NAME=$(nmcli -t -f NAME,DEVICE con show | grep ":$IFACE$" | cut -d':' -f1 | head -n1)
    fi

    if [ -z "$CON_NAME" ]; then
        NM_ACTIVE_DEV=$(nmcli -t -f DEVICE,STATE device | grep ":connected$" | cut -d':' -f1 | head -n1)
        if [ -n "$NM_ACTIVE_DEV" ]; then
            CON_NAME=$(nmcli -t -f NAME,DEVICE con show | grep ":$NM_ACTIVE_DEV$" | cut -d':' -f1 | head -n1)
            if [ -n "$CON_NAME" ]; then
                echo "⚙️ 自动检测到设备 $NM_ACTIVE_DEV 的连接：$CON_NAME"
                log "自动检测到设备 $NM_ACTIVE_DEV 的连接：$CON_NAME"
                IFACE="$NM_ACTIVE_DEV"
            fi
        fi
    fi

    if [ -z "$CON_NAME" ]; then
        echo "⚠️ 未自动检测到 $IFACE 的连接配置"
        echo "请从下面的列表中输入完整的连接名称（注意空格和大小写）："
        sudo nmcli --color yes con show | tee -a "$LOG_FILE"
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

else
    echo -e "${RED}无法确定网络管理方式，当前接口: $IFACE${NC}"
    log "无法确定网络管理方式，接口: $IFACE"
    exit 1
fi