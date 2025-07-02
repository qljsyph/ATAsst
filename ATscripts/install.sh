#!/bin/bash


if [ "$EUID" -ne 0 ]; then
    echo "请使用 sudo 运行此脚本。"
    exit 1
fi

LOG_FILE="/var/log/mihomo_install.log"


true > "$LOG_FILE"
chmod 666 "$LOG_FILE"

function log_message() {
    echo "$1" | tee -a "$LOG_FILE"
}

log_message "===== 开始安装 ====="


if [ -f "/usr/local/bin/mihomo" ]; then
    log_message "/usr/local/bin/mihomo 已存在，是否删除？（y/n）"
    read -r choice
    if [ "$choice" == "y" ]; then
        log_message "正在删除现有的 /usr/local/bin/mihomo ..."
        if ! rm -f /usr/local/bin/mihomo; then
            log_message "删除失败！"
            exit 1
        fi
        log_message "现有文件已成功删除"
    else
        log_message "用户选择不删除文件，退出安装"
        exit 0
    fi
fi


function get_github_versions() {
    local url=$1
    local version_type=$2
    log_message "尝试获取 $version_type 版本信息..."
    if ! response=$(curl -s "$url"); then
        log_message "获取 GitHub 版本信息时网络请求失败，请检查网络连接。"
        return 1
    fi
    log_message "成功获取 $version_type 版本信息"
    if [ "$version_type" == "Alpha" ]; then
        echo "$response" | jq -r 'if type=="array" then
             .[] | .tag_name as $tag | .assets[] | select(.name | test("linux.*alpha.*\\.gz$")) | [.name, $tag] | @tsv
           else
             .tag_name as $tag | .assets[] | select(.name | test("linux.*alpha.*\\.gz$")) | [.name, $tag] | @tsv
           end'
    else
        echo "$response" | jq -r 'if type=="array" then
             .[] | .tag_name as $tag | .assets[] | select(.name | test("^mihomo-linux.*\\.gz$")) | [.name, $tag] | @tsv
           else
             .tag_name as $tag | .assets[] | select(.name | test("^mihomo-linux.*\\.gz$")) | [.name, $tag] | @tsv
           end'
    fi
}


function install_to_bin() {
    local file_name=$1
    local temp_dir=$2

    if [ ! -f "$temp_dir/$file_name" ]; then
        log_message "文件 $temp_dir/$file_name 不存在或下载失败，请检查网络连接或 GitHub 链接是否有效。"
        return 1
    fi

    log_message "正在解压 $file_name..."
    if ! gunzip "$temp_dir/$file_name"; then
        log_message "解压文件 $file_name 失败，请检查文件是否损坏。"
        return 1
    fi
    log_message "文件 $file_name 解压成功"

    extracted_file="${file_name%.gz}"

    # smart 内核解压后文件名为 smart，需重命名为 mihomo
    if [[ "$extracted_file" == "smart"* ]]; then
        log_message "检测到 smart 内核，重命名为 mihomo"
        mv "$temp_dir/$extracted_file" "$temp_dir/mihomo"
        extracted_file="mihomo"
    fi

    if [ -f "$temp_dir/$extracted_file" ]; then
        log_message "正在将文件移动到 /usr/local/bin 并重命名为 mihomo..."
        if ! mv "$temp_dir/$extracted_file" /usr/local/bin/mihomo; then
            log_message "移动文件到 /usr/local/bin 失败，请检查权限。"
            return 1
        fi
        log_message "文件已成功移动到 /usr/local/bin 并重命名为 mihomo"

        if ! chmod 755 /usr/local/bin/mihomo; then
            log_message "设置文件权限失败，请检查权限。"
            return 1
        fi
        log_message "已成功为 /usr/local/bin/mihomo 设置 755 权限"

        log_message "正在创建 /etc/systemd/system/mihomo.service 文件..."
        if ! cat <<EOF > /etc/systemd/system/mihomo.service
[Unit]
Description=mihomo Daemon, Another Clash Kernel.
After=network.target NetworkManager.service systemd-networkd.service iwd.service

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
Restart=always
ExecStartPre=/usr/bin/sleep 1s
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
        then
            log_message "创建 mihomo.service 文件失败，请检查权限。"
            return 1
        fi

        
        if [ ! -f "/etc/systemd/system/mihomo.service" ]; then
            log_message "创建 mihomo.service 文件失败，请检查权限。"
            return 1
        fi
        log_message "成功创建 /etc/systemd/system/mihomo.service 文件"

        log_message "正在重新加载 systemd 服务，启用 mihomo 服务..."
        if ! systemctl daemon-reload; then
            log_message "重新加载 systemd 服务失败，请检查配置。"
            return 1
        fi
        log_message "systemd 服务重新加载成功"

        if ! systemctl enable mihomo.service; then
            log_message "启用 mihomo 服务失败，请检查配置。"
            return 1
        fi
        log_message "mihomo 服务已成功设置为开机自启"
    else
        log_message "解压后未找到文件，安装失败。"
        return 1
    fi
}


function install_version() {
    local url=$1
    local version_type=$2

    log_message "正在获取 $version_type 版版本信息..."
    versions=$(get_github_versions "$url" "$version_type")

    if [ -z "$versions" ]; then
        log_message "未找到 $version_type 版的 Linux 系统 .gz 压缩包，返回上层..."
        return
    fi

    log_message "请选择要安装的 $version_type 版本架构："
    IFS=$'\n'
    select version in $versions; do
        if [ -n "$version" ]; then
            file_name=$(echo "$version" | awk -F $'\t' '{print $1}')
            tag=$(echo "$version" | awk -F $'\t' '{print $2}')

            temp_dir=$(mktemp -d)
            log_message "临时目录创建成功：$temp_dir"

            trap 'log_message "删除临时目录：$temp_dir"; rm -rf "$temp_dir"' EXIT

            log_message "正在下载 $version_type 版本: $file_name"
            # 根据版本类型选择不同的下载地址
            if [ "$version_type" == "Smart" ]; then
                download_url="https://ghfast.top/https://github.com/vernesong/mihomo/releases/download/$tag/$file_name"
            else
                download_url="https://ghfast.top/https://github.com/MetaCubeX/mihomo/releases/download/$tag/$file_name"
            fi
            log_message "下载地址: $download_url"

            http_code=$(curl -L -s -w "%{http_code}" "$download_url" -o "$temp_dir/$file_name")
            if [ "$http_code" == "200" ]; then
                log_message "$file_name 下载完成"
                if ! install_to_bin "$file_name" "$temp_dir"; then
                    log_message "安装 $file_name 失败"
                    return 1
                fi
                log_message "安装 $file_name 成功"
                break
            else
                log_message "下载失败，错误码：$http_code，请检查网络连接或 GitHub 链接是否有效。"
                return 1
            fi
        else
            log_message "无效选择，请重新选择."
        fi
    done
    unset IFS
}

function install_alpha() {
    log_message "开始尝试安装 Alpha 版本"
    if ! install_version "https://api.github.com/repos/MetaCubeX/mihomo/releases?per_page=5" "Alpha"; then
        log_message "安装 Alpha 版本失败"
        return 1
    fi
    log_message "Alpha 版本安装成功"
}

function install_stable() {
    log_message "开始尝试安装发行版"
    if ! install_version "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" "发行"; then
        log_message "安装发行版失败"
        return 1
    fi
    log_message "发行版安装成功"
}

function install_smart() {
    log_message "开始尝试安装 Smart 版本"
    if ! install_version "https://api.github.com/repos/vernesong/mihomo/releases?per_page=5" "Smart"; then
        log_message "安装 Smart 版本失败"
        return 1
    fi
    log_message "Smart 版本安装成功"

    ai_model_url="https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model.bin"
    ai_model_path="/etc/mihomo/Model.bin"

    log_message "开始准备 AI 模型存放目录..."
    if [ ! -d "/etc/mihomo" ]; then
        mkdir -p /etc/mihomo
        log_message "已创建目录 /etc/mihomo"
    fi

    log_message "开始下载 AI 模型..."
    if curl -L -o "$ai_model_path" "$ai_model_url"; then
        log_message "AI 模型下载完成，已保存到 $ai_model_path"
        chmod 644 "$ai_model_path"
    else
        log_message "AI 模型下载失败，请检查网络或手动下载。"
    fi
}

function show_menu() {
    clear
    echo "==============================="
    echo "       安装核心程序           "
    echo "==============================="
    echo "1) 安装 Alpha 版"
    echo "2) 安装发行版"
    echo "3) 安装 Smart 版"
    echo "4) 返回上层"
    echo -n "请输入你的选择 [1-4]: "
}

# 主控制逻辑
while true; do
    show_menu
    read -r -p "请输入选项: " choice
    case $choice in
        1) 
            if ! install_alpha; then
                log_message "安装过程中出现问题，请查看日志进行排查"
            fi
            ;;
        2) 
            if ! install_stable; then
                log_message "安装过程中出现问题，请查看日志进行排查"
            fi
            ;;
        3)
            if ! install_smart; then
                log_message "安装过程中出现问题，请查看日志进行排查"
            fi
            ;;
        4) 
            echo "返回上层..."
            break
            ;;
        *) 
            echo "无效选项，请重新选择."
            sleep 2
            ;;
    esac
done