#!/bin/bash

BASE_URL="https://ghfast.top/https://raw.githubusercontent.com/qljsyph/ATAsst/refs/heads/main/ATscripts"
SCRIPTS_DIR="/etc/mihomo/scripts"
LOG_DIR="/var/log/ATAsst"
LOG_FILE="$LOG_DIR/AT_update.log"
TEMP_DIR="/tmp/mihomo_update_temp"
clear
# 最大重试次数
MAX_RETRIES=3

# 用于输出日志
function log_message() {
    echo "$1" | tee -a "$LOG_FILE" > /dev/null
}

function curl_with_retry() {
    local url="$1"
    local retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        result=$(curl -s "$url")
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            echo "$result"
            return 0
        fi
        log_message "curl 下载 $url 失败，正在进行第 $((retries + 1)) 次重试..."
        retries=$((retries + 1))
        sleep 2
    done
    log_message "curl 下载 $url 失败，达到最大重试次数。"
    return 1
}

function wget_with_retry() {
    local url="$1"
    local output="$2"
    local retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        if wget -O "$output" "$url" > /dev/null 2>&1; then
            return 0
        fi
        log_message "wget 下载 $url 失败，正在进行第 $((retries + 1)) 次重试..."
        retries=$((retries + 1))
        sleep 2
    done
    log_message "wget 下载 $url 失败，达到最大重试次数。"
    return 1
}

# 清空旧的日志文件
true > "$LOG_FILE"

log_message "===== 开始更新工具 ====="


if [ ! -d "$SCRIPTS_DIR" ]; then
    log_message "工具目录不存在，正在创建目录..."
    sudo mkdir -p "$SCRIPTS_DIR" || { log_message "创建目录失败！"; exit 1; }
fi


if [ -f "$SCRIPTS_DIR/menu.sh" ]; then
    # 优先解析 LOCAL_VERSION="x.y.z"
    local_current_version=$(grep -oP 'LOCAL_VERSION\s*=\s*"[0-9.]+"' "$SCRIPTS_DIR/menu.sh" 2>/dev/null | sed -E 's/.*"([0-9.]+)".*/\1/' || true)
    # 回退到解析输出的“版本:1.2.3”
    if [ -z "$local_current_version" ]; then
        local_current_version=$(grep -oP '(?<=版本:)[0-9.]+' "$SCRIPTS_DIR/menu.sh" | head -n1 || true)
    fi
    if [ -z "$local_current_version" ]; then
        log_message "未找到本地 menu.sh 中的版本信息，假设当前版本为 0.0.0"
        local_current_version="0.0.0"
    else
        log_message "当前本地版本：$local_current_version"
    fi
else
    log_message "未找到本地 menu.sh，假设当前版本为 0.0.0"
    local_current_version="0.0.0"
fi


log_message "获取远程版本信息..."
remote_menu=$(curl_with_retry "$BASE_URL/menu.sh") || { log_message "获取远程 menu.sh 失败，退出。"; exit 1; }

# 优先解析远端定义的 LOCAL_VERSION="x.y.z"
remote_version=$(echo "$remote_menu" | grep -oP 'LOCAL_VERSION\s*=\s*"[0-9.]+"' | sed -E 's/.*"([0-9.]+)".*/\1/' || true)

# 回退到解析页面显示的“版本:x.y.z”
if [ -z "$remote_version" ]; then
    remote_version=$(echo "$remote_menu" | grep -oP '(?<=版本:)[0-9.]+' | head -n1 || true)
fi

if [ -z "$remote_version" ]; then
    log_message "获取远程版本信息失败或解析不到版本，退出。"
    exit 1
fi

log_message "远程版本：$remote_version"


if [ "$local_current_version" != "$remote_version" ]; then
    log_message "当前版本：$local_current_version"
    log_message "远程版本：$remote_version"
    read -r -p "发现新版本，是否更新？(y/n): " update_choice

    if [ "$update_choice" != "y" ]; then
        log_message "用户选择不更新，返回主菜单。"
        echo "用户选择不更新，返回主菜单。"
        exec bash "$SCRIPTS_DIR/menu.sh"
    fi
else
    log_message "当前已是最新版本，无需更新。"
    echo "当前已是最新版本，无需更新。"
    exec bash "$SCRIPTS_DIR/menu.sh"
fi


log_message "删除旧版..."
for file in "$SCRIPTS_DIR"/*; do
    if [ -f "$file" ]; then
        log_message "正在删除旧文件: $file ..."
        if ! sudo rm -f "$file" > /dev/null 2>&1; then
            log_message "删除文件 $file 失败！"
            exit 1
        else
            log_message "成功删除旧文件: $file"
        fi
    fi
done


cd "$SCRIPTS_DIR" || { log_message "无法进入目录！"; exit 1; }


log_message "下载更新文件..."
declare -A files=(
    ["依赖1"]="menu.sh"
    ["依赖2"]="install.sh"
    ["依赖3"]="uninstall.sh"
    ["依赖4"]="run.sh"
    ["依赖5"]="tools.sh"
    ["依赖6"]="catlog.sh"
    ["依赖7"]="update_scripts.sh"
    ["依赖8"]="reset.sh"
    ["依赖9"]="config.sh"
    ["依赖10"]="delaytest.sh"
    ["依赖11"]="ipmanager.sh"
)

for key in "${!files[@]}"; do
    file="${files[$key]}"
    log_message "正在下载 $file ..."
    if wget_with_retry "$BASE_URL/$file" "$SCRIPTS_DIR/$file"; then
        log_message "成功下载 $file"
    else
        log_message "下载 $file 失败，退出！"
        exit 1
    fi
done


log_message "设置工具文件权限为 755 ..."
sudo chmod -R 755 "$SCRIPTS_DIR"/* > /dev/null 2>&1 || { log_message "设置权限失败！"; exit 1; }


if [ -d "$TEMP_DIR" ]; then
    log_message "清除临时目录 $TEMP_DIR ..."
    sudo rm -rf "$TEMP_DIR" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log_message "成功清除临时目录 $TEMP_DIR"
    else
        log_message "清除临时目录 $TEMP_DIR 失败！"
        exit 1
    fi
fi

log_message "===== 工具更新完成 ====="


echo "工具更新完成！"

log_message "重新加载"
exec bash "$SCRIPTS_DIR/menu.sh" && exit