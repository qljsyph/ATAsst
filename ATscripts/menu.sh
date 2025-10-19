#!/bin/bash

BASE_URL="https://ghfast.top/https://raw.githubusercontent.com/qljsyph/ATAsst/refs/heads/main/ATscripts"
SCRIPTS_DIR="/etc/mihomo/scripts"
LOCAL_VERSION="1.13.0"
版本:1.30.0 #兼顾版本检测
# 清空并定义关联数组
unset files
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

function get_remote_version() {
    local url="$BASE_URL/menu.sh"
    local remote=""
    if command -v curl >/dev/null 2>&1; then
        remote=$(curl -fsSL "$url" 2>/dev/null | grep -m1 '版本:' | sed -E 's/.*版本:([0-9.]+).*/\1/' || true)
    elif command -v wget >/dev/null 2>&1; then
        remote=$(wget -qO- "$url" 2>/dev/null | grep -m1 '版本:' | sed -E 's/.*版本:([0-9.]+).*/\1/' || true)
    fi
    echo "$remote"
}

function check_and_download_scripts() {
    echo "检查工具完整性"
    mkdir -p "$SCRIPTS_DIR"

    for key in "${!files[@]}"; do
        file="${files[$key]}"
        dest="$SCRIPTS_DIR/$file"
        url="$BASE_URL/$file"

        if [ -f "$dest" ]; then
            continue
        fi

        echo "依赖 $key ($file) 不存在，正在下载..."

        downloader=""
        if command -v wget >/dev/null 2>&1; then
            downloader="wget -q -O"
        elif command -v curl >/dev/null 2>&1; then
            downloader="curl -fsSL -o"
        else
            echo "未检测到 wget 或 curl，尝试自动安装..."
            if command -v apt >/dev/null 2>&1; then
                sudo apt update -y && sudo apt install -y wget curl
            elif command -v pacman >/dev/null 2>&1; then
                sudo pacman -Sy --noconfirm wget curl
            else
                echo "❌ 未检测到支持的包管理器，请手动安装 wget 或 curl。"
                exit 1
            fi

            # 再次检测
            if command -v wget >/dev/null 2>&1; then
                downloader="wget -q -O"
            elif command -v curl >/dev/null 2>&1; then
                downloader="curl -fsSL -o"
            else
                echo "❌ 自动安装失败，请手动安装 wget 或 curl。"
                exit 1
            fi
        fi
        for attempt in 1 2 3; do
            if $downloader "$dest" "$url"; then
                chmod 755 "$dest"
                echo "✅ $file 下载成功"
                break
            else
                echo "⚠️  第 $attempt 次下载 $file 失败，重试中..."
                sleep 1
            fi
        done
        if [ ! -f "$dest" ]; then
            echo "❌ 无法下载 $file，请检查网络或 URL 是否有效：$url"
            exit 1
        fi
    done
}

sudo chmod -R 755 "$SCRIPTS_DIR"/* || { echo "设置脚本权限失败！"; exit 1; }

REMOTE_VERSION="$(get_remote_version)"
NEW_VERSION_AVAILABLE=0
if [ -z "$REMOTE_VERSION" ]; then
    echo "⚠️ 无法获取远程版本信息，请检查网络连接。"
elif [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    NEW_VERSION_AVAILABLE=1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

function show_menu() {
    echo "======================================================="
    echo "           欢迎使用 ATAsst工具   致谢MetaCubeX项目     "
    echo "               本工具为辅助虚空终端快捷使用     "
    echo "                  使用者请遵守当地法律法       "
    echo "                    工具作者:qljsyph       "
    if [ "$NEW_VERSION_AVAILABLE" -eq 1 ]; then
        echo -e "            版本: ${GREEN}${LOCAL_VERSION}${NC}   (${YELLOW}检测到新版本: ${REMOTE_VERSION}${NC})"
    else
        echo "            版本: ${LOCAL_VERSION}"
    fi
    echo "         Github:https://github.com/qljsyph/ATAsst"
    echo "======================================================="
    echo "1. 安装"
    echo "2. 卸载"
    echo "3. 首次运行"
    echo "4. 常用功能"
    echo "5. 配置文件工具"
    echo "6. 查看安装日志"
    echo "7. 更新ATAsst"
    echo "8. Armbian网络管理"
    echo "9. 退出"
}

# 子脚本执行函数，先检查文件是否存在
function run_script() {
    local script_name="$1"
    local script_path="$SCRIPTS_DIR/$script_name"
    if [ ! -f "$script_path" ]; then
        echo -e "${RED}错误：脚本 $script_name 不存在，请检查是否完整安装。${NC}"
        return 1
    fi
    sudo bash "$script_path"
}

# 主逻辑
check_and_download_scripts

while true; do
    show_menu
    read -r -p "请输入选项: " choice

    case $choice in
        1)
            echo "执行安装..."
            run_script "install.sh"
            ;;
        2)
            echo "执行卸载..."
            run_script "uninstall.sh"
            ;;
        3)
            echo "执行首次运行..."
            run_script "run.sh"
            ;;
        4) 
            echo "常用功能..."
            run_script "tools.sh"    
            ;;
        5)  
            echo "配置文件工具"
            run_script "config.sh"
            ;;  
        6)
            echo "查看安装日志..."
            run_script "catlog.sh"
            ;;
        7)
            echo "更新ATAsst..."
            run_script "update_scripts.sh"
            ;;
        8)
            echo "网络管理..."
            run_script "ipmanager.sh"
            ;;
        9)
            echo "退出程序"
            exit 0
            ;;
        *)
            echo "无效选项，请重新选择！"
            ;;
    esac
done