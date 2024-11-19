#!/bin/bash

# Certbot 自动化脚本
# 此脚本将自动获取 Let's Encrypt 证书，并配置 Apache

# 指定配置文件
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BASE_DIR="/etc/aspnmy_registry"
CONFIG_FILE="${BASE_DIR}/config.json"

function log() {
    message="[Aspnmy Log]: $1 "
    case "$1" in
        *"失败"*|*"错误"*|*"请使用 root 或 sudo 权限运行此脚本"*)
            log -e "${RED}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
        *"成功"*)
            log -e "${GREEN}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
        *"忽略"*|*"跳过"*)
            log -e "${YELLOW}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
        *)
            log -e "${BLUE}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
    esac
}


# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    log "错误：配置文件 '$CONFIG_FILE' 不存在。"
    exit 1
fi

# 从 JSON 文件中读取配置
DOMAIN=$(jq -r '.domain' $CONFIG_FILE)
EMAIL=$(jq -r '.email' $CONFIG_FILE)
CF_APK=$(jq -r '.cf_key' $CONFIG_FILE)
ZONE_ID=$(jq -r '.zone_id' $CONFIG_FILE)
SUBDOMAIN=$(jq -r '.sub_domain' $CONFIG_FILE)
ip_address=$(get_ip)



# 检查是否成功读取域名和电子邮件
if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    log "配置错误：域名或电子邮件地址未设置。"
    exit 1
fi

# 安装 Certbot 和 Apache 插件（如果尚未安装）
if ! command -v certbot &> /dev/null; then
    log "安装 Certbot..."
    sudo apt-get update
    sudo apt-get install -y certbot python3-certbot-apache
fi

# 验证 Apache 是否正在运行
if ! systemctl is-active --quiet apache2; then
    log "Apache 服务未运行。启动 Apache..."
    sudo systemctl start apache2
fi

get_ip(){
# 获取外网 IP 地址的 shell 脚本
# 使用 curl 获取 IP 地址
# 使用 ipify.org API
IP=$(curl -s https://api.ipify.org)
echo $IP

}

function Set_CF_DNS(){
    # 获取证书前先确认设置dns数据
    log "配置cloudflare-dns记录"
    curl --request POST \
    --url https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $CF_APK" \
    --data '{
    "comment": "Domain verification record",
    "name": "$SUBDOMAIN",
    "proxied": true,
    "settings": {},
    "tags": [],
    "ttl": 120,
    "content": "$ip_address",
    "type": "A"
    }'
}

log "设置DNS记录"
Set_CF_DNS

# 使用 Certbot 获取证书
log "获取证书..."
sudo certbot --apache -d $DOMAIN  --agree-tos --email $EMAIL --non-interactive --redirect

# 检查证书是否成功获取
if [ $? -eq 0 ]; then
    log "证书成功获取并配置。"
else
    log "证书获取失败。"
    exit 1
fi

# 重启 Apache 以应用新证书（可选）
log "重启 Apache 服务以应用新证书..."
sudo systemctl restart apache2

log "自动化脚本执行完毕。"