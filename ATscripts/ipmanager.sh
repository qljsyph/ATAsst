#!/bin/bash
# =========================================
# 网络配置管理
# =========================================
#1.13.5
# 颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
# ==============================
# 日志文件初始化与 log 函数
# ==============================
LOG_DIR="/var/log/ATAsst"
LOG_FILE="$LOG_DIR/ipmanager.log"
sudo mkdir -p "$LOG_DIR"
sudo touch "$LOG_FILE"
sudo chown root:root "$LOG_FILE"
sudo chmod 644 "$LOG_FILE"

# 定义 log 函数
log() {
    local msg="$*"
    echo "$(date '+%F %T') $msg" | sudo tee -a "$LOG_FILE" > /dev/null
}

log_separator() {
    echo "========================================================" | sudo tee -a "$LOG_FILE" > /dev/null
    echo "$(date '+%F %T') --- 新的操作开始 ---" | sudo tee -a "$LOG_FILE" > /dev/null
    echo "========================================================" | sudo tee -a "$LOG_FILE" > /dev/null
}

# ==============================
# 日志轮换
# ==============================
if ! command -v logrotate >/dev/null 2>&1; then
    echo "⚠️ logrotate 未安装，正在安装..."
    sudo apt update
    sudo apt install -y logrotate
fi

LOGROTATE_CONF="/etc/logrotate.d/ipmanager"
sudo tee "$LOGROTATE_CONF" > /dev/null <<EOL
$LOG_FILE {
    daily
    rotate 7
    missingok
    notifempty
    create 644 root root
}
EOL

log "logrotate 配置完成，文件: $LOGROTATE_CONF"

log_separator
log "网络管理器启动"

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

# 通用菜单循环函数
menu_loop() {
    local mode="$1"
    local fn_static="$2"
    local fn_dhcp="$3"
    local fn_show="$4"
    shift 4
    local extra_opts=("$@")

    while true; do
        echo "=============================="
        echo "         网络配置工具"
        echo "=============================="
        echo "1）设置静态 IP"
        echo "2）切换为 DHCP 模式"
        echo "3）查看当前网络配置"
        local opt_idx=4
        local opt_map=()
        for extra in "${extra_opts[@]}"; do
            local opt_label="${extra%%:*}"
            local opt_fn="${extra#*:}"
            echo "${opt_idx}）${opt_label}"
            opt_map[$opt_idx]="$opt_fn"
            ((opt_idx++))
        done
        echo "${opt_idx}）退出"
        read -rp "请输入选项 [1-${opt_idx}]: " MENU_OPTION
        case "$MENU_OPTION" in
            1)
                $fn_static
                ;;
            2)
                $fn_dhcp
                ;;
            3)
                $fn_show
                ;;
            *)  
                if [[ $MENU_OPTION -ge 4 && $MENU_OPTION -lt $opt_idx ]]; then
                    fn="${opt_map[$MENU_OPTION]}"
                    if [ -n "$fn" ]; then
                        $fn
                    else
                        echo "未知选项"
                    fi
                elif [[ $MENU_OPTION -eq $opt_idx ]]; then
                    echo "已退出。"
                    log "用户退出网络配置工具"
                    exit 0
                else
                    echo -e "${RED}无效选项，请输入 1~${opt_idx}。${NC}"
                fi
                ;;
        esac
    done
}
#查看配置函数
show_network_config() {
    local mode="$1"       # "netplan" 或 "nmcli"
    local iface="$2"
    local con_name="$3"   # NMCLI模式传递连接名，否则可空

    echo -e "${YELLOW}当前网络配置:${NC}"

    if [ "$mode" = "netplan" ]; then
        ip addr show "$iface" | grep "inet "
        echo
        echo -e "${YELLOW}默认网关:${NC}"
        ip route show default
        echo
        echo -e "${YELLOW}DNS 服务器:${NC}"
        grep 'nameserver' /etc/resolv.conf || echo "无 DNS 服务器配置"

    elif [ "$mode" = "nmcli" ]; then
        echo "连接名称：$con_name"
        echo "网卡名称：$iface"
        IPV4_METHOD=$(nmcli -g ipv4.method con show "$con_name" 2>/dev/null)
        case "$IPV4_METHOD" in
            manual) MODE_DESC="静态 IP";;
            auto)   MODE_DESC="DHCP（自动）";;
            disabled) MODE_DESC="IPv4 已禁用";;
            *)      MODE_DESC="$IPV4_METHOD";;
        esac
        echo "IP 模式：$MODE_DESC"
        nmcli dev show "$iface" | grep -E "IP4\.ADDRESS|IP4\.GATEWAY|IP4\.DNS" || true
    fi

    log "显示网络配置: $iface ($mode)"
}

cleanup() {
    echo -e "\n${YELLOW}已中断，退出程序。${NC}"
    log "用户中断脚本"
    exit 130
}
trap cleanup INT TERM

mapfile -t RAW_IFACES < <(ip -br link show | awk '{print $1}' | grep -v "^lo")

declare -A DEV_PATHS
declare -A MACS
ALL_IFACES=()

for IF in "${RAW_IFACES[@]}"; do
    MAC=$(cat /sys/class/net/$IF/address 2>/dev/null | tr '[:upper:]' '[:lower:]')
    DEV_PATH=$(readlink -f /sys/class/net/$IF/device 2>/dev/null)

    if [[ -n "$MAC" && -n "${MACS[$MAC]}" ]]; then
        continue
    fi

    if [[ -n "$DEV_PATH" && -n "${DEV_PATHS[$DEV_PATH]}" ]]; then
        continue
    fi

    [[ -n "$MAC" ]] && MACS["$MAC"]=1
    [[ -n "$DEV_PATH" ]] && DEV_PATHS["$DEV_PATH"]=1
    ALL_IFACES+=("$IF")
done

#分类函数
get_iface_type() {
    local IF="$1"
    local TYPE_FILE="/sys/class/net/$IF/type"

    if [[ -d "/sys/class/net/$IF/wireless" ]]; then
        echo "Wi-Fi"
        return
    fi

    if [[ -f "$TYPE_FILE" ]]; then
        case "$(cat "$TYPE_FILE")" in
            1) echo "Ethernet" ;;
            772) echo "Virtual" ;;
            *) 
                if [[ "$IF" == *"tun"* || "$IF" == *"tap"* || "$IF" == *"docker"* ]]; then
                    echo "Virtual"
                else
                    echo "Unknown"
                fi
                ;;
        esac
    else
        echo "Unknown"
    fi
}

AUTO_SELECTED=false
IFACE=""

if [ ${#ALL_IFACES[@]} -eq 0 ]; then
    echo -e "${RED}未找到任何网络接口，程序退出${NC}"
    log "未找到任何网络接口，退出脚本"
    exit 1
elif [ ${#ALL_IFACES[@]} -eq 1 ]; then
    IFACE="${ALL_IFACES[0]}"
    TYPE=$(get_iface_type "$IFACE")
    echo -e "${YELLOW}检测到单一网络接口：$IFACE [$TYPE]${NC}"
    log "检测到单一网络接口: $IFACE [$TYPE]"
    AUTO_SELECTED=true

else
    echo "检测到多个网络接口（物理去重 + 保留虚拟接口）："

    # 接口角色判断函数
    get_iface_role() {
        local iface="$1"

        if [[ "$iface" == br* || "$iface" == docker* || "$iface" == tun* || "$iface" == tap* || "$iface" == Meta* ]]; then
            echo "Virtual"
            return
        fi

        if ip route show default 2>/dev/null | grep -qw "dev $iface"; then
            echo "WAN"
            return
        fi

        if ip -4 addr show "$iface" 2>/dev/null | grep -qE 'inet (192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01]))'; then
            echo "LAN"
            return
        fi

        echo "Other"
    }

    # 循环显示接口和角色
    i=1
    for iface in "${ALL_IFACES[@]}"; do
        type=$(get_iface_type "$iface")
        role=$(get_iface_role "$iface")
        printf "%d）%-12s [%s / %s]\n" "$i" "$iface" "$type" "$role"
        ((i++))
    done

    AUTO_IFACE=""
    for iface in "${ALL_IFACES[@]}"; do
        role=$(get_iface_role "$iface")
        if [[ "$role" == "WAN" ]]; then
            AUTO_IFACE="$iface"
            break
        fi
    done

    if [[ -z "$AUTO_IFACE" ]]; then
        for iface in "${ALL_IFACES[@]}"; do
            [[ "$(get_iface_type "$iface")" == "Ethernet" ]] && AUTO_IFACE="$iface" && break
        done
    fi

    if [[ -n "$AUTO_IFACE" ]]; then
        echo
        read -rp "检测到以太网接口 ${AUTO_IFACE}，是否自动选择？(Y/n): " yn
        case $yn in
            [Nn]*) ;;  # 用户拒绝，则继续手动选择
            *) 
                IFACE="$AUTO_IFACE"
                TYPE=$(get_iface_type "$IFACE")
                echo -e "${YELLOW}已自动选择网卡：$IFACE [$TYPE]${NC}"
                log "自动选择网卡: $IFACE [$TYPE]"
                AUTO_SELECTED=true
                ;;
        esac
    fi

    # 手动选择
    if ! $AUTO_SELECTED; then
        echo
        read -rp "请选择要配置的网卡编号 [1-${#ALL_IFACES[@]}]: " SELECTED
        IFACE="${ALL_IFACES[$((SELECTED-1))]}"
        TYPE=$(get_iface_type "$IFACE")
        echo -e "${YELLOW}已选择网卡：$IFACE [$TYPE]${NC}"
        log "用户选择网卡: $IFACE [$TYPE]"
    fi
fi
# 检测
NETPLAN_RENDERER=""
# 目标网卡的 Netplan
NETPLAN_FILES=$(grep -rl "$IFACE" /etc/netplan/*.yaml 2>/dev/null)
if [ -n "$NETPLAN_FILES" ] && grep -q "renderer:\s*NetworkManager" $NETPLAN_FILES 2>/dev/null; then
    NETPLAN_RENDERER="NetworkManager"
fi

if command -v nmcli >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager && nmcli device status | grep -qw "$IFACE"; then
    if [ "$NETPLAN_RENDERER" = "NetworkManager" ]; then
        NET_MODE="nmcli"
        log "Netplan+NetworkManager"
    else
        NET_MODE="nmcli"
        log "NetworkManager"
    fi
elif grep -q "$IFACE" /etc/network/interfaces 2>/dev/null; then
    NET_MODE="interfaces"
    log "interfaces"
elif grep -qr "$IFACE" /etc/netplan/*.yaml 2>/dev/null; then
    NET_MODE="netplan"
    log "Netplan"
else
    NET_MODE="unknown"
    log "无法确定网络管理方式"
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

    set_if_static() {
        read -rp "请输入静态 IP 地址: " IP_ADDRESS
        read -rp "请输入子网掩码（例如 255.255.255.0）: " NETMASK
        if ! [[ "$NETMASK" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            echo "❌ 子网掩码格式不正确，使用默认 255.255.255.0"
            NETMASK="255.255.255.0"
        fi
        read -rp "请输入网关地址: " GATEWAY
        read -rp "请输入 DNS 服务器地址 (多个地址用空格分隔): " DNS_SERVERS
        log "用户选择设置静态 IP: IP=$IP_ADDRESS NETMASK=$NETMASK GATEWAY=$GATEWAY DNS=$DNS_SERVERS"

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
    netmask $NETMASK
    gateway $GATEWAY
EOL

        if [[ -L /etc/resolv.conf ]]; then
            echo "⚠️ 检测到 systemd-resolved 管理 DNS，使用 resolvectl 设置"
            log "systemd-resolved 管理 DNS，使用 resolvectl 设置: ${DNS_SERVERS[*]}"
            for dns in $DNS_SERVERS; do
                run_and_log "sudo resolvectl dns $INTERFACE $dns"
            done
            run_and_log "sudo resolvectl reconfigure"
        else
            echo > $RESOLV_CONF_FILE
            for dns in $DNS_SERVERS; do
                echo "nameserver $dns" >> $RESOLV_CONF_FILE
                log "写入 DNS: $dns 到 $RESOLV_CONF_FILE"
            done
        fi

        run_and_log "sudo systemctl restart networking"
        echo -e "${GREEN}静态 IP 地址和 DNS 配置完成！${NC}"
    }

    set_if_dhcp() {
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
    }

    show_network_config_interfaces() {
        log "用户查看当前网络配置"
        echo -e "${YELLOW}当前网络配置:${NC}"
        ip addr show "$INTERFACE" | grep "inet "
        echo
        echo -e "${YELLOW}默认网关:${NC}"
        ip route show default
        echo
        echo -e "${YELLOW}DNS 服务器:${NC}"
        grep 'nameserver' /etc/resolv.conf
    }

    menu_loop "interfaces" set_if_static set_if_dhcp show_network_config_interfaces

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

    set_netplan_static() {
        read -rp "请输入静态 IP 地址（带CIDR，例如 192.168.1.100/24）: " IP_CIDR
        read -rp "请输入网关地址: " GATEWAY
        read -rp "请输入 DNS 服务器地址 (多个用空格分隔): " DNS_SERVERS
        log "用户选择设置静态 IP: IP=$IP_CIDR GATEWAY=$GATEWAY DNS=$DNS_SERVERS"

        BACKUP_FILE=$(backup_netplan)

        sudo tee "$CONFIG_FILE" > /dev/null <<EOL
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses:
        - $IP_CIDR
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses:
$(for dns in $DNS_SERVERS; do echo "          - $dns"; done)  
EOL

        if ! sudo netplan try --timeout 15; then
            echo -e "${RED}配置验证失败，正在恢复备份...${NC}"
            log "netplan try 验证失败，恢复备份"
            restore_netplan "$BACKUP_FILE"
            return
        fi

        if run_and_log "sudo netplan apply"; then
            echo -e "${GREEN}静态 IP 配置已应用！${NC}"
        else
            echo -e "${RED}应用配置失败，正在恢复备份...${NC}"
            log "netplan apply 失败，恢复备份"
            restore_netplan "$BACKUP_FILE"
        fi
    }

    set_netplan_dhcp() {
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
    }

    show_network_config_netplan() {
        log "用户查看当前网络配置"
        show_network_config "netplan" "$INTERFACE"
    }

    restore_latest_backup() {
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
    }

    menu_loop "netplan" set_netplan_static set_netplan_dhcp show_network_config_netplan "恢复最近备份:restore_latest_backup"

elif [ "$NET_MODE" = "nmcli" ]; then

    log "检测到 NetworkManager 管理模式"

    NM_IFACE=$(nmcli -t -f DEVICE,STATE device | grep ":connected$" | cut -d':' -f1 | head -n1)
    if [ -n "$NM_IFACE" ] && ! nmcli device | awk '{print $1}' | grep -qw "$IFACE"; then
        echo "⚙️ 自动检测到 NetworkManager 实际使用接口：$NM_IFACE"
        log "修正接口名称: $IFACE → $NM_IFACE (由 NetworkManager 管理)"
        IFACE="$NM_IFACE"
        # 更新接口角色
        ROLE=$(get_iface_role "$IFACE")
        echo -e "${YELLOW}已使用的网络接口: $IFACE [角色: $ROLE]${NC}"
        log "自动识别 NetworkManager 接口: $IFACE, 角色: $ROLE"
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
        read -rp "连接名称: " CON_NAME

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

    set_nmcli_static() {
        echo ">>> 设置静态 IP 模式"
        read -rp "请输入新的IP地址（例如 192.168.1.100）: " IP_ADDR
        read -rp "请输入子网掩码CIDR（例如 24 表示255.255.255.0）: " MASK
        read -rp "请输入网关地址（例如 192.168.1.1）: " GATEWAY
        read -rp "请输入主DNS（例如 223.5.5.5）: " DNS1
        read -rp "请输入备用DNS（可留空）: " DNS2

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
            show_network_config "nmcli" "$IFACE" "$CON_NAME"
            log "静态IP设置完成，显示当前网络信息"
        else
            echo "❌ 配置失败，请检查输入参数"
            log "静态IP配置失败"
        fi
    }

    set_nmcli_dhcp() {
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
            show_network_config "nmcli" "$IFACE" "$CON_NAME"
            log "切换为 DHCP 完成，显示当前网络信息"
        else
            echo "❌ 切换失败"
            log "切换为 DHCP 失败"
        fi
        echo
    }

    show_network_config_nmcli() {
        echo ">>> 当前网络配置如下："
        show_network_config "nmcli" "$IFACE" "$CON_NAME"
    }

    re_detect_nmcli() {
        echo ">>> 重新检测网络连接..."
        log "用户选择重新检测网络连接，重启脚本"
        exec "$0"
    }

    menu_loop "nmcli" set_nmcli_static set_nmcli_dhcp show_network_config_nmcli "重新检测网络连接:re_detect_nmcli"

else
    echo -e "${RED}无法确定网络管理方式，当前接口: $IFACE${NC}"
    log "无法确定网络管理方式，接口: $IFACE"
    exit 1
fi