#!/bin/bash

# Certbot 自动化脚本
# 此脚本将自动获取 Let's Encrypt 证书，并配置 Apache

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 指定配置文件和目录
BASE_DIR="/etc/aspnmy_registry"
CONFIG_FILE="${BASE_DIR}/.config.json"

# 初始化变量 如果不存在数据默认空值
DOMAIN=$(jq -r '.domain // ""' "$CONFIG_FILE")
EMAIL=$(jq -r '.email // ""' "$CONFIG_FILE")
CF_API_KEY=$(jq -r '.cf_key // ""' "$CONFIG_FILE")
ZONE_ID=$(jq -r '.zone_id // ""' "$CONFIG_FILE")
SUB_DOMAIN=$(jq -r '.sub_domain // ""' "$CONFIG_FILE")

# 日志记录函数
log() {
    local message="[Aspnmy Log]: $1"
    case "$1" in
    *"失败"* | *"错误"* | *"请使用 root 或 sudo 权限运行此脚本"*)
        echo -e "${RED}${message}${NC}" 2>&1 | tee -a "${BASE_DIR}/install.log"
        ;;
    *"成功"*)
        echo -e "${GREEN}${message}${NC}" 2>&1 | tee -a "${BASE_DIR}/install.log"
        ;;
    *"忽略"* | *"跳过"*)
        echo -e "${YELLOW}${message}${NC}" 2>&1 | tee -a "${BASE_DIR}/install.log"
        ;;
    *)
        echo -e "${BLUE}${message}${NC}" 2>&1 | tee -a "${BASE_DIR}/install.log"
        ;;
    esac
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 获取外网 IP 地址
get_ip_address() {
    local ip_address
    if command_exists curl; then
        ip_address=$(curl -s https://api.ipify.org)
        if [ -z "$ip_address" ]; then
            log "错误:无法获取外网 IP 地址"
            exit 1
        else
            echo "$ip_address"
        fi
    else
        log "错误:curl 命令不存在"
        exit 1
    fi
}

# 安装指定的软件包-没有sudo权限的时候从远程下载安装sudo
install_packages() {
    local packages=("$@")
    for pkg in "${packages[@]}"; do
        if ! command_exists "$pkg"; then
            log "安装 $pkg..."
            if [[ -f /etc/os-release ]]; then
                . /etc/os-release
                case $ID in
                    "ubuntu" | "debian")
                        if command_exists apt-get; then
                            if [[ "$pkg" == "sudo" ]]; then
                                # 特殊处理 sudo 的安装，使用 curl 下载并安装
                                curl -sS https://deb.debian.org/debian/pool/main/s/sudo/sudo_1.8.31-1_amd64.deb -o sudo.deb && dpkg -i sudo.deb || { log "错误: sudo 安装失败"; exit 1; }
                                rm sudo.deb
                            else
                                sudo apt-get update && sudo apt-get install -y "$pkg"
                            fi
                        else
                            log "错误: apt-get 命令不存在，但需要它来安装 $pkg"
                            exit 1
                        fi
                        ;;
                    "centos" | "rhel" | "fedora" | "rocky")
                        if [[ "$pkg" == "sudo" ]]; then
                            # 特殊处理 sudo 的安装，使用 curl 下载并安装
                            curl -sS https://kojipkgs.fedoraproject.org//packages/sudo/1.9.5p2-1.fc35/x86_64/sudo-1.9.5p2-1.fc35.x86_64.rpm -o sudo.rpm && sudo rpm -ivh sudo.rpm || { log "错误: sudo 安装失败"; exit 1; }
                            rm sudo.rpm
                        elif command_exists yum; then
                            sudo yum install -y "$pkg"
                        elif command_exists dnf; then
                            sudo dnf install -y "$pkg"
                        else
                            log "错误: yum 或 dnf 命令不存在，但需要它们中的一个来安装 $pkg"
                            exit 1
                        fi
                        ;;
                    *)
                        log "错误: 您的操作系统 '$ID' 不受支持，或缺少安装 $pkg 的命令"
                        exit 1
                        ;;
                esac
            else
                log "错误: 无法检测操作系统发行版"
                exit 1
            fi
            if [ $? -ne 0 ]; then
                log "错误: $pkg 安装失败"
                exit 1
            fi
            log "$pkg 安装成功"
        fi
    done
}


# 判断项目必须组件是否存在不存在就安装
check_packages(){
    # 检查 sudo 和 curl 和 apache2 是否存在，不存在则安装
    install_packages "sudo" "curl" "apache2" "apache2-utils" "jq"

    # 检查 Certbot 是否存在，不存在则安装
    if ! command_exists certbot; then
        log "安装 Certbot..."
        install_packages "certbot" "python3-certbot-apache"
    fi
}


# 验证 Apache 是否正在运行
check_apache() {
    if command_exists systemctl; then
        if ! systemctl is-active --quiet apache2; then
            log "Apache 服务未运行启动 Apache..."
            sudo systemctl start apache2
            if [ $? -ne 0 ]; then
                log "错误:Apache 服务启动失败"
                exit 1
            fi
            log "Apache 服务启动成功"
        fi
    else
        log "错误:systemctl 命令不存在"
        exit 1
    fi
}

# 判断 cloudflare 参数不为空的情况下才执行set_cloudflare_dns函数
check_cloudflare_dns(){
    if [[ -n "$CF_API_KEY" && -n "$ZONE_ID" && -n "$SUB_DOMAIN" ]]; then
        set_cloudflare_dns
    fi
}
# 设置 Cloudflare DNS 记录
set_cloudflare_dns() {
    log "配置 Cloudflare DNS 记录"
    local Response
    local IP_ADDRESS
    IP_ADDRESS=$(get_ip_address)
    if command_exists curl; then
        Response=$(curl --request POST \
            --url "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            --header 'Content-Type: application/json' \
            --header "Authorization: Bearer $CF_API_KEY" \
            --data "{
                \"comment\": \"Domain verification record\",
                \"name\": \"$SUB_DOMAIN\",
                \"proxied\": true,
                \"settings\": {},
                \"tags\": [],
                \"ttl\": 120,
                \"content\": \"$IP_ADDRESS\",
                \"type\": \"A\"
                }")
        if [ $? -ne 0 ]; then
            log "错误:设置 Cloudflare DNS 记录失败,原始值是:$Response"
            exit 1
        fi
        log "Cloudflare DNS 记录设置成功,原始值是:$Response"
    else
        log "错误:curl 命令不存在"
        exit 1
    fi
}

# 获取 SSL 证书
get_SSL() {
    # 使用 Certbot 获取证书
    log "获取证书..."
    sudo certbot --apache -d "$DOMAIN" --agree-tos --email "$EMAIL" --non-interactive --redirect

    # 检查证书是否成功获取
    if [ $? -eq 0 ]; then
        log "证书成功获取并配置"
        cat <<EOF >"$BASE_DIR/ssl_lock.json"
{"domain": "$DOMAIN"}
EOF
    else
        log "证书获取失败"
        exit 1
    fi
}

# 重启 Apache 以应用新证书（可选）
restart_web() {
    # 重启 Apache 以应用新证书
    log "重启 Apache 服务以应用新证书..."
    sudo systemctl restart apache2
    if [ $? -ne 0 ]; then
        log "错误:Apache 服务重启失败"
        exit 1
    fi
    log "Apache 服务重启成功"
}

# 初始化配置文件
Config_init() {
    # 检查配置文件是否存在
    if [ -f "$CONFIG_FILE" ]; then
        echo "配置文件已存在"
        read -p "是否要覆盖现有的配置文件？(y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            echo "操作已取消"
            return 1 # 退出函数
        fi
    fi
    # 初始化变量
    key1=""
    key2=""

    # 循环直到必填参数被正确填写
    while true; do
        echo "请输入配置信息:"

        # 读取用户输入的必选值
        read -p "请输入域名 (domain): " key1
        if [ -z "$key1" ]; then
            echo "域名是必填项，请重新输入"
        else
            break # 跳出循环，继续执行
        fi
    done

    while true; do
        read -p "请输入邮箱 (email): " key2
        if [ -z "$key2" ]; then
            echo "邮箱是必填项，请重新输入"
        else
            break # 跳出循环，继续执行
        fi
    done

    # 读取用户输入的可选值
    read -p "请输入Cloudflare API密钥 (cf_key) [如需自动化使用Cloudflare-Dns配置需要配置这个参数/可选/按回车使用默认值]:" key3
    read -p "请输入Cloudflare Zone ID (zone_id) [如需自动化使用Cloudflare-Dns配置需要配置这个参数/可选/按回车使用默认值]:" key4
    read -p "请输入子域名 (sub_domain) [如需自动化使用Cloudflare-Dns配置需要配置这个参数/可选/按回车使用默认值]:" key5
    # 如果 $key5 为空，则设置其值与 $key1 相同
    if [ -z "$key5" ]; then
        key5="$key1"
    fi
    # 将用户输入的值写入配置文件
    cat <<EOF >"$CONFIG_FILE"
{"domain": "$key1","email": "$key2","cf_key": "$key3","zone_id": "$key4","sub_domain": "$key5"}
EOF
    echo "配置文件已生成:$CONFIG_FILE"
}
main() {
    # 检查网络连接
    ip_address=$(get_ip_address)
    # 检测并安装必须组件
    check_packages
    # 初始化配置文件
    Config_init

    # 安装 Certbot
    if ! command -v certbot &>/dev/null; then
        install_certbot
    fi

    # 验证 Apache 是否正在运行
    check_apache

    # 设置 Cloudflare DNS 记录
    check_cloudflare_dns

    # 获取 SSL 证书
    get_SSL

    # 重启 Apache 以应用新证书
    restart_web

    log "自动化脚本执行完毕"
}

main
