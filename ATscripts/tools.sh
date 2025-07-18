#!/bin/bash
SCRIPTS_DIR="/etc/mihomo/scripts"

show_menu() {
    clear
    echo "=== 常用功能菜单 ==="
    echo "1. 启动 mihomo 服务"   
    echo "2. 停止 mihomo 服务"
    echo "3. 查看 mihomo 服务状态"
    echo "4. 查看 mihomo 服务实时日志"
    echo "5. 启用 mihomo 服务自启动"
    echo "6. 关闭 mihomo 服务自启动"
    echo "7. 外网真实延迟测试"
    echo "8. 返回上层"
}

start_service() {
    echo "正在启动 mihomo 服务..."
    systemctl start mihomo
    echo "服务已启动。"
    read -r -p "按回车键返回菜单..."
}

stop_service() {
    echo "正在停止 mihomo 服务..."
    systemctl stop mihomo
    echo "服务已停止。"
    read -r -p "按回车键返回菜单..."
}

service_status() {
    echo "正在查看 mihomo 服务状态..."
    systemctl status mihomo
    read -r -p "按回车键返回菜单..."
}

view_logs() {
    echo "正在查看 mihomo 服务实时日志..."
    journalctl -u mihomo -o cat -f
    read -r -p "按回车键返回菜单..."
}

enable_service() {
    echo "正在启用 mihomo 服务自启动..."
    systemctl enable mihomo > /dev/null 2>&1
    echo "服务已启用自启动。"
    read -r -p "按回车键返回菜单..."
}

disable_service() {
    echo "正在关闭 mihomo 服务自启动..."
    systemctl disable mihomo > /dev/null 2>&1
    echo "服务已禁用自启动。"
    read -r -p "按回车键返回菜单..."
}

run_delaytest() {
    echo "外网真实延迟测试..."
    bash "$SCRIPTS_DIR/delaytest.sh"
}

while true; do
    show_menu
    read -r -p "请输入选择 (1-8): " choice
    case $choice in
        1) start_service ;;
        2) stop_service ;;
        3) service_status ;;
        4) view_logs ;;
        5) enable_service ;;
        6) disable_service ;;
        7) run_delaytest ;;
        8) break ;;
        *) echo "无效选择，请重新输入。" ;;
    esac
done
