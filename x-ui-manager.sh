#!/bin/bash
# 增强版 x-ui 一键管理脚本（带随机账号密码+SSL证书+域名绑定）
# 支持系统：CentOS 7+/Debian 9+/Ubuntu 18.04+
# 功能：安装(带随机账号/SSL/域名)/卸载/重启/查看状态/修改端口/重置密码

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 核心变量
XUI_DIR="/usr/local/x-ui"
XRAY_DIR="/usr/local/xray"
SERVICE_NAME="x-ui"
ACME_SH_URL="https://github.com/acmesh-official/acme.sh/raw/master/acme.sh"

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

# 生成随机高强度用户名和密码
generate_random_cred() {
    # 随机用户名（8-12位，字母+数字）
    USERNAME=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w $((8 + RANDOM % 5)) | head -n 1)
    # 随机密码（16位，字母+数字+特殊符号）
    PASSWORD=$(tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' < /dev/urandom | fold -w 16 | head -n 1)
    echo -e "${YELLOW}已生成随机账号密码：${NC}"
    echo -e "用户名：${GREEN}$USERNAME${NC}"
    echo -e "密码：${GREEN}$PASSWORD${NC}"
}

# 安装依赖（含acme.sh依赖）
install_dependencies() {
    echo -e "${YELLOW}正在安装系统依赖包...${NC}"
    if [[ $OS == *"CentOS"* ]]; then
        yum update -y
        yum install -y wget curl unzip tar socat cronie openssl-devel
    elif [[ $OS == *"Debian"* || $OS == *"Ubuntu"* ]]; then
        apt update -y
        apt install -y wget curl unzip tar socat cron openssl
    fi
}

# 安装acme.sh并申请SSL证书
install_ssl() {
    read -p "请输入要绑定的域名（如：xui.example.com）：" DOMAIN
    if [[ -z $DOMAIN ]]; then
        echo -e "${RED}域名不能为空！${NC}"
        exit 1
    fi

    # 检查域名解析是否生效
    echo -e "${YELLOW}检查域名解析状态...${NC}"
    SERVER_IP=$(curl -s ifconfig.me)
    DOMAIN_IP=$(nslookup $DOMAIN 2>/dev/null | grep 'Address:' | grep -v '127.0.0.1' | awk '{print $2}' | tail -n 1)
    
    if [[ -z $DOMAIN_IP || $DOMAIN_IP != $SERVER_IP ]]; then
        echo -e "${YELLOW}警告：域名解析IP($DOMAIN_IP)与服务器IP($SERVER_IP)不一致！${NC}"
        read -p "是否继续（解析生效后才能正常使用SSL）？(y/n)：" CONFIRM
        if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
            exit 1
        fi
    fi

    # 安装acme.sh
    echo -e "${YELLOW}安装acme.sh证书工具...${NC}"
    curl -sSL $ACME_SH_URL | sh -s email=my@example.com

    # 申请Let's Encrypt证书
    echo -e "${YELLOW}申请SSL证书（Let's Encrypt）...${NC}"
    ~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone -k ec-256 --force

    # 安装证书到指定目录
    SSL_DIR="/etc/x-ui/ssl"
    mkdir -p $SSL_DIR
    ~/.acme.sh/acme.sh --installcert -d $DOMAIN --fullchainpath $SSL_DIR/fullchain.cer --keypath $SSL_DIR/private.key --ecc

    # 设置证书自动续期
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --cron --renew-all

    echo -e "${GREEN}SSL证书安装完成！证书路径：$SSL_DIR${NC}"
    echo -e "${GREEN}域名 $DOMAIN 已绑定，证书将自动续期${NC}"
}

# 安装并配置x-ui（带SSL和随机账号）
install_xui() {
    check_root
    check_system
    install_dependencies

    # 生成随机账号密码
    generate_random_cred

    # 安装Xray核心
    echo -e "${YELLOW}正在安装Xray核心...${NC}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root

    # 安装x-ui面板
    echo -e "${YELLOW}正在安装x-ui面板...${NC}"
    wget -qO- https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh | bash -s -- install

    # 配置面板端口（默认443，HTTPS）
    read -p "请输入面板端口（默认443，HTTPS推荐）：" XUI_PORT
    XUI_PORT=${XUI_PORT:-443}

    # 设置账号密码
    echo -e "${YELLOW}配置面板账号密码...${NC}"
    $XUI_DIR/x-ui setting -username $USERNAME -password $PASSWORD
    $XUI_DIR/x-ui setting -port $XUI_PORT

    # 安装SSL证书并绑定域名
    install_ssl

    # 配置x-ui使用HTTPS
    echo -e "${YELLOW}配置HTTPS访问...${NC}"
    $XUI_DIR/x-ui setting -tls true -cert /etc/x-ui/ssl/fullchain.cer -key /etc/x-ui/ssl/private.key

    # 启动并设置开机自启
    systemctl enable $SERVICE_NAME
    systemctl restart $SERVICE_NAME

    # 输出最终配置信息
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}x-ui 面板安装配置完成！${NC}"
    echo -e "${GREEN}访问地址：https://$DOMAIN:$XUI_PORT${NC}"
    echo -e "${GREEN}用户名：$USERNAME${NC}"
    echo -e "${GREEN}密码：$PASSWORD${NC}"
    echo -e "${YELLOW}重要：请务必保存好账号密码，SSL证书已自动续期${NC}"
    echo -e "${GREEN}=====================================${NC}"
}

# 卸载x-ui（含SSL证书清理）
uninstall_xui() {
    check_root
    echo -e "${YELLOW}正在卸载x-ui面板...${NC}"
    bash -c "$(curl -L https://github.com/vaxilu/x-ui/raw/master/install.sh)" @ uninstall

    # 清理SSL证书
    echo -e "${YELLOW}清理SSL证书相关文件...${NC}"
    rm -rf /etc/x-ui/ssl
    ~/.acme.sh/acme.sh --uninstall
    rm -rf ~/.acme.sh

    echo -e "${GREEN}x-ui面板及SSL证书已彻底卸载！${NC}"
}

# 重启x-ui服务
restart_xui() {
    check_root
    echo -e "${YELLOW}正在重启x-ui服务...${NC}"
    systemctl restart $SERVICE_NAME
    echo -e "${GREEN}x-ui服务已重启！${NC}"
}

# 查看x-ui状态（含HTTPS信息）
status_xui() {
    check_root
    echo -e "${YELLOW}x-ui服务状态：${NC}"
    systemctl status $SERVICE_NAME --no-pager
    
    echo -e "\n${YELLOW}面板配置信息：${NC}"
    $XUI_DIR/x-ui setting -show all
    
    echo -e "\n${YELLOW}访问地址检测：${NC}"
    TLS_STATUS=$($XUI_DIR/x-ui setting -show tls | grep -oE 'true|false')
    PORT=$($XUI_DIR/x-ui setting -show port)
    if [[ $TLS_STATUS == "true" ]]; then
        echo -e "HTTPS访问：https://$(curl -s ifconfig.me):$PORT"
    else
        echo -e "HTTP访问：http://$(curl -s ifconfig.me):$PORT"
    fi
}

# 重置随机密码
reset_password() {
    check_root
    echo -e "${YELLOW}生成新的随机密码...${NC}"
    NEW_PASSWORD=$(tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' < /dev/urandom | fold -w 16 | head -n 1)
    USERNAME=$($XUI_DIR/x-ui setting -show username | awk '{print $3}')
    $XUI_DIR/x-ui setting -password $NEW_PASSWORD
    
    echo -e "${GREEN}密码重置成功！${NC}"
    echo -e "用户名：${GREEN}$USERNAME${NC}"
    echo -e "新密码：${GREEN}$NEW_PASSWORD${NC}"
}

# 修改面板端口（支持HTTPS）
change_port() {
    check_root
    read -p "请输入新的面板端口（1000-65535）：" NEW_PORT
    if [[ $NEW_PORT =~ ^[0-9]+$ && $NEW_PORT -ge 1000 && $NEW_PORT -le 65535 ]]; then
        $XUI_DIR/x-ui setting -port $NEW_PORT
        restart_xui
        echo -e "${GREEN}面板端口已修改为 $NEW_PORT，服务已重启！${NC}"
    else
        echo -e "${RED}端口输入错误，请输入1000-65535之间的数字！${NC}"
    fi
}

# 主菜单
main_menu() {
    clear
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}  x-ui 增强版一键管理脚本 v2.0      ${NC}"
    echo -e "${GREEN}  含随机账号/SSL证书/域名绑定       ${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo -e "1. 安装x-ui（带SSL+域名+随机账号）"
    echo -e "2. 卸载x-ui（含SSL证书清理）"
    echo -e "3. 重启x-ui服务"
    echo -e "4. 查看x-ui状态（含HTTPS信息）"
    echo -e "5. 修改面板端口"
    echo -e "6. 重置随机密码"
    echo -e "0. 退出脚本"
    echo -e "${GREEN}=====================================${NC}"
    read -p "请输入操作编号：" OPTION

    case $OPTION in
        1) install_xui ;;
        2) uninstall_xui ;;
        3) restart_xui ;;
        4) status_xui ;;
        5) change_port ;;
        6) reset_password ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入错误，请选择0-6之间的数字！${NC}" && sleep 2 && main_menu ;;
    esac
}

# 启动主菜单
main_menu
