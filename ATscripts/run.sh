#!/bin/bash

LOG_FILE="/var/log/mihomo_install.log"

function check_config_file() {
    if [ ! -f "/etc/mihomo/config.yaml" ]; then
        echo "错误：/etc/mihomo/config.yaml 文件不存在，请上传 config.yaml 文件！" 
        return 1
    fi
    return 0
}

function enable_mihomo_watch_service() {
    SERVICE_FILE="/etc/systemd/system/mihomo-watch.service"
    WATCH_SCRIPT="/etc/mihomo/scripts/watch-mihomo.sh"

    echo "正在启用 config.yaml 监控服务..." >> "$LOG_FILE"

    if [ ! -f "$SERVICE_FILE" ]; then
        echo "监控服务文件 $SERVICE_FILE 不存在，跳过启用。" >> "$LOG_FILE"
        return 0
    fi

    if [ ! -f "$WATCH_SCRIPT" ]; then
        echo "监控脚本 $WATCH_SCRIPT 不存在，跳过启用。" >> "$LOG_FILE"
        return 0
    fi

    echo "重新加载 systemd..." >> "$LOG_FILE"
    sudo systemctl daemon-reload

    echo "启用并启动 mihomo-watch.service ..." >> "$LOG_FILE"
    sudo systemctl enable --now mihomo-watch.service

    if systemctl is-active --quiet mihomo-watch.service; then
        echo "mihomo-watch.service 已成功运行。" >> "$LOG_FILE"
    else
        echo "mihomo-watch.service 启动失败，请检查 systemctl status。" >> "$LOG_FILE"
    fi
}

function check_and_run() {
   
    echo "正在重新加载 systemd 配置..." >> "$LOG_FILE"
    sudo systemctl daemon-reload

    echo "正在启用自启动服务..." >> "$LOG_FILE"
    sudo systemctl enable mihomo

    echo "正在启动mihomo服务" >> "$LOG_FILE"
    sudo systemctl start mihomo

    echo "正在查看 mihomo 服务状态..."
    service_status=$(systemctl status mihomo) 

    echo "$service_status"

    if echo "$service_status" | grep -q "Active: failed"; then
        echo "mihomo 服务启动失败，状态为 failed。" >> "$LOG_FILE"
        echo "$service_status"
        echo "返回主菜单..."
        return 1
    fi

    if echo "$service_status" | grep -q "Active: active (running)"; then
        echo "mihomo 服务已成功启动，状态为 active (running)。" >> "$LOG_FILE"

        
        echo "正在启用 IPv4 和 IPv6 转发..."
        sudo sed -i '/net.ipv4.ip_forward/s/^#//;/net.ipv6.conf.all.forwarding/s/^#//' /etc/sysctl.conf
        sudo sysctl -p

       
        sudo chmod +x /etc/mihomo/scripts/reset.sh
        echo "正在重启网络..." >> "$LOG_FILE"
        restart_output=$(sudo /etc/mihomo/scripts/reset.sh 2>&1) ; echo "$restart_output" >> "$LOG_FILE"

        if echo "$restart_output" | grep -q "successfully"; then
            echo "网络服务已重启，配置已更新。" >> "$LOG_FILE"
        elif echo "$restart_output" | grep -q "No known network management service found"; then
            echo "未检测到有效的服务，请检查日志或重启系统。" >> "$LOG_FILE"
            return 1
        else
            echo "未知错误，请检查日志。" 
            return 1
        fi

        # 成功后启用 mihomo-watch.service
        enable_mihomo_watch_service
    fi
}

echo "正在初始/重启..."

check_config_file
if [ $? -ne 0 ]; then
    echo "返回主菜单..."
    exit 1
fi

check_and_run

echo "执行完毕，返回主菜单..."