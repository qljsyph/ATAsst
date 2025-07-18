#!/bin/bash

BASE_URL="https://ghfast.top/https://raw.githubusercontent.com/qljsyph/ATAsst/refs/heads/main/ATscripts"
SCRIPTS_DIR="/etc/mihomo/scripts"

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
)

function check_and_download_scripts() {
    echo "检查工具完整性"

    for key in "${!files[@]}"; do
        file="${files[$key]}"
        if [ ! -f "$SCRIPTS_DIR/$file" ]; then
            echo "依赖 $key 不存在，正在下载..."
            wget -O "$SCRIPTS_DIR/$file" "$BASE_URL/$file" > /dev/null 2>&1 || { echo "下载 $file 失败！"; exit 1; }
        fi
    done
}

sudo chmod -R 755 "$SCRIPTS_DIR"/* || { echo "设置脚本权限失败！"; exit 1; }


function show_menu() {
    echo "======================================================="
    echo "           欢迎使用 ATAsst工具   致谢MetaCubeX项目     "
    echo "               本工具为辅助虚空终端快捷使用     "
    echo "                  使用者请遵守当地法律法       "
    echo "            版本:1.12.2      工具作者:qljsyph       "
    echo "         Github:https://github.com/qljsyph/ATAsst"
    echo "======================================================="
    echo "1. 安装"
    echo "2. 卸载"
    echo "3. 首次运行"
    echo "4. 常用功能"
    echo "5. 配置文件工具"
    echo "6. 查看安装日志"
    echo "7. 更新ATAsst"
    echo "8. 退出"
}

# 主逻辑
check_and_download_scripts

while true; do
    show_menu
    read -r -p "请输入选项: " choice

    case $choice in
        1)
            echo "执行安装..."
            sudo bash "$SCRIPTS_DIR/install.sh"
            ;;
        2)
            echo "执行卸载..."
            sudo bash "$SCRIPTS_DIR/uninstall.sh"
            ;;
        3)
            echo "执行首次运行..."
            sudo bash "$SCRIPTS_DIR/run.sh"
            ;;
        4) 
            echo "常用功能..."
            sudo bash "$SCRIPTS_DIR/tools.sh"    
            ;;
        5)  echo "配置文件工具"
            sudo bash "$SCRIPTS_DIR/config.sh"
            ;;  
        6)
            echo "查看安装日志..."
            sudo bash "$SCRIPTS_DIR/catlog.sh"
            ;;
        7)
            echo "更新ATAsst..."
            sudo bash "$SCRIPTS_DIR/update_scripts.sh"
            ;;
        8)
            echo "退出程序"
            exit 0
            ;;
        *)
            echo "无效选项，请重新选择！"
            ;;
    esac
done