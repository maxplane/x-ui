#!/bin/bash
# 类似 x-ui 的 Xray 面板一键管理脚本
# 支持系统：CentOS 7+/Debian 9+/Ubuntu 18.04+
# 功能：安装/卸载/重启/查看状态/修改端口

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 定义核心变量
XUI_VERSION="1.7.0"
XUI_PORT="54321"
XUI_DIR="/usr/local/x-ui"
XRAY_DIR="/usr/local/xray"
SERVICE_NAME="x-ui"

# 检查是否为 root 用户
check_root() {
    if [ $EUID -ne 0 ]; then
        echo -e "${RED}错误：必须以 root 用户运行此脚本！${NC}"
        exit 1
    fi
}

# 检查系统版本
check_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        echo -e "${RED}无法识别系统版本，脚本仅支持 CentOS/Debian/Ubuntu！${NC}"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}正在安装依赖包...${NC}"
    if [[ $OS == *"CentOS"* ]]; then
        yum update -y
        yum install -y wget curl unzip tar socat
    elif [[ $OS == *"Debian"* || $OS == *"Ubuntu"* ]]; then
        apt update -y
        apt install -y wget curl unzip tar socat
    fi
}

# 安装 Xray 核心
install_xray() {
    echo -e "${YELLOW}正在安装 Xray 核心...${NC}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
}

# 安装 x-ui 面板
install_xui() {
    check_root
    check_system
    install_dependencies
    install_xray

    echo -e "${YELLOW}正在下载并安装 x-ui 面板...${NC}"
    wget -qO- https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh | bash -s -- install

    # 配置面板端口
    $XUI_DIR/x-ui setting -port $XUI_PORT

    # 启动服务
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME

    # 获取服务器 IP
    SERVER_IP=$(curl -s ifconfig.me)

    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}x-ui 面板安装成功！${NC}"
    echo -e "${GREEN}面板访问地址：http://$SERVER_IP:$XUI_PORT${NC}"
    echo -e "${GREEN}初始账号：admin${NC}"
    echo -e "${GREEN}初始密码：admin${NC}"
    echo -e "${YELLOW}注意：请立即登录面板修改密码！${NC}"
    echo -e "${GREEN}=====================================${NC}"
}

# 卸载 x-ui
uninstall_xui() {
    check_root
    echo -e "${YELLOW}正在卸载 x-ui 面板...${NC}"
    bash -c "$(curl -L https://github.com/vaxilu/x-ui/raw/master/install.sh)" @ uninstall
    echo -e "${GREEN}x-ui 面板已成功卸载！${NC}"
}

# 重启 x-ui
restart_xui() {
    check_root
    echo -e "${YELLOW}正在重启 x-ui 服务...${NC}"
    systemctl restart $SERVICE_NAME
    echo -e "${GREEN}x-ui 服务已重启！${NC}"
}

# 查看状态
status_xui() {
    check_root
    echo -e "${YELLOW}x-ui 服务状态：${NC}"
    systemctl status $SERVICE_NAME --no-pager
    echo -e "\n${YELLOW}面板访问地址：${NC}"
    echo -e "http://$(curl -s ifconfig.me):$($XUI_DIR/x-ui setting -show port)"
}

# 修改面板端口
change_port() {
    check_root
    read -p "请输入新的面板端口（建议 1000-65535）：" NEW_PORT
    if [[ $NEW_PORT =~ ^[0-9]+$ && $NEW_PORT -ge 1000 && $NEW_PORT -le 65535 ]]; then
        $XUI_DIR/x-ui setting -port $NEW_PORT
        restart_xui
        echo -e "${GREEN}面板端口已修改为 $NEW_PORT，已重启服务！${NC}"
    else
        echo -e "${RED}端口输入错误，请输入 1000-65535 之间的数字！${NC}"
    fi
}

# 主菜单
main_menu() {
    clear
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}      x-ui 一键管理脚本 v1.0        ${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo -e "1. 安装 x-ui 面板"
    echo -e "2. 卸载 x-ui 面板"
    echo -e "3. 重启 x-ui 服务"
    echo -e "4. 查看 x-ui 状态"
    echo -e "5. 修改面板端口"
    echo -e "0. 退出脚本"
    echo -e "${GREEN}=====================================${NC}"
    read -p "请输入操作编号：" OPTION

    case $OPTION in
        1) install_xui ;;
        2) uninstall_xui ;;
        3) restart_xui ;;
        4) status_xui ;;
        5) change_port ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入错误，请选择 0-5 之间的数字！${NC}" && sleep 2 && main_menu ;;
    esac
}

# 启动主菜单
main_menu
