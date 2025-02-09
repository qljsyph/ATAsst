#!/bin/bash

show_menu() {
    clear
    echo "=== 常用工具菜单 ==="
    echo "1. 停止 mihomo 服务"
    echo "2. 查看 mihomo 服务状态"
    echo "3. 查看 mihomo 服务实时日志"
    echo "4. 启用 mihomo 服务自启动"
    echo "5. 关闭 mihomo 服务自启动"
    echo "6. 返回上层"
}

stop_service() {
    echo "正在停止 mihomo 服务..."
    systemctl stop mihomo
    echo "服务已停止。"
    read -p "按回车键返回菜单..."
}

service_status() {
    echo "正在查看 mihomo 服务状态..."
    systemctl status mihomo
    read -p "按回车键返回菜单..."
}

view_logs() {
    echo "正在查看 mihomo 服务实时日志..."
    journalctl -u mihomo -o cat -f
    read -p "按回车键返回菜单..."
}

enable_service() {
    echo "正在启用 mihomo 服务自启动..."
    systemctl enable mihomo
    echo "服务已启用自启动。"
    read -p "按回车键返回菜单..."
}

disable_service() {
    echo "正在关闭 mihomo 服务自启动..."
    systemctl disable mihomo
    echo "服务已禁用自启动。"
    read -p "按回车键返回菜单..."
}

while true; do
    show_menu
    read -p "请输入选择 (1-6): " choice
    case $choice in
        1) stop_service ;;
        2) service_status ;;
        3) view_logs ;;
        4) enable_service ;;
        5) disable_service ;;
        6) break ;;  # 选择返回上层，退出循环
        *) echo "无效选择，请重新输入。" ;;
    esac
done
