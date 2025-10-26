#!/bin/bash
LOG_DIR="/var/log/ATAsst"
function remove_mihomo_bin() {
    if [ -f "/usr/local/bin/mihomo" ]; then
        echo "正在删除核心"
        sudo rm -f /usr/local/bin/mihomo
        echo "核心已删除"
    else
        echo "核心不存在，跳过删除"
    fi
}

function remove_mihomo_service() {
    if [ -f "/etc/systemd/system/mihomo.service" ]; then
        echo "正在删除服务"
        sudo rm -f /etc/systemd/system/mihomo.service
        echo "服务文件已删除"
        # 重新加载 systemd
        sudo systemctl daemon-reload
    else
        echo "服务文件不存在，跳过删除"
    fi
}

function remove_mihomo_config() {
    if [ -d "/etc/mihomo" ]; then
        echo "正在删除配置文件"
        sudo rm -rf /etc/mihomo
        echo "配置已删除"
    else
        echo "配置不存在，跳过删除"
     fi
}

function remove_AT_install_log() {
    if [ -f "$LOG_DIR/AT_install.log" ]; then
        echo "正在删除脚本安装日志"
        sudo rm -f $LOG_DIR/AT_install.log
        echo "日志已删除"
    else
        echo "日志不存在，跳过删除"
    fi
}

function remove_AT_update_log() {
    if [ -f "$LOG_DIR/AT_update.log" ]; then
        echo "正在删除 更新日志"
        sudo rm -f $LOG_DIR/AT_update.log
        echo "日志已删除"
    else
        echo "日志不存在，跳过删除"
    fi
}

function remove_mihomo_install_log() {
    if [ -f "$LOG_DIR/mihomo_install.log" ]; then
        echo "正在删除 安装日志"
        sudo rm -f $LOG_DIR/mihomo_install.log
        echo "日志已删除"
    else
        echo "日志不存在，跳过删除"
    fi
}
function remove_ipmanager_log() {
    if [ -f "$LOG_DIR/ipmanager.log" ]; then
        echo "正在删除 网络管理器日志"
        sudo rm -f $LOG_DIR/ipmanager.log
        echo "日志已删除"
    else
        echo "日志不存在，跳过删除"
    fi
}

function uninstall() {
    echo "正在卸载 mihomo..."

    remove_mihomo_bin
    remove_mihomo_service
    remove_mihomo_config
    remove_AT_install_log
    remove_AT_update_log
    remove_mihomo_install_log
    remove_ipmanager_log

    echo "卸载完成，返回主菜单..."
}

uninstall