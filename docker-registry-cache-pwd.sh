#!/bin/bash

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 生成随机用户名和密码的函数
random_username() {
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 8
}

random_password() {
    tr -dc 'A-Za-z0-9@#$%^&*()_+' </dev/urandom | head -c 16
}

# 日志记录函数
log() {
    local message="[Aspnmy Log]: $1"
    case "$1" in
        *"失败"*|*"错误"*|*"请使用 root 或 sudo 权限运行此脚本"*)
            echo -e "${RED}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}/install.log"
            ;;
        *"成功"*)
            echo -e "${GREEN}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}/install.log"
            ;;
        *"忽略"*|*"跳过"*)
            echo -e "${YELLOW}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}/install.log"
            ;;
        *)
            echo -e "${BLUE}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}/install.log"
            ;;
    esac
}

# 安装必要的工具
install_tools() {
    log "正在安装必要的工具..."
    apt-get update && apt-get install -y apache2 apache2-utils certbot python3-certbot-apache jq
    if [ $? -ne 0 ]; then
        log "工具安装失败"
        exit 1
    fi
    log "工具安装成功"
}

# 更新SSL证书
update_ssl() {
    log "正在更新SSL证书..."
    curl -sSL https://raw.githubusercontent.com/aspnmy/aspnmy-registry/refs/heads/docker-registry/autorun_upssl.sh -o autorun_upssl.sh && chmod u+x autorun_upssl.sh && bash autorun_upssl.sh
    if [ $? -ne 0 ]; then
        log "SSL证书更新失败"
        exit 1
    fi
    log "SSL证书更新成功"
}

# 设置基本认证
set_htpasswd() {
    local username=$(random_username)
    local password=$(random_password)
    log "生成访问账户 ${username} 密码 ${password}"
    htpasswd -Bbn "${username}" "${password}" > /etc/aspnmy_registry/"${username}"
}

# 主函数，执行所有设置
main() {
    local current_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    log "脚本开始执行，当前目录：$current_dir"

    install_tools
    update_ssl
    set_htpasswd

    log "所有设置完成"
}

# 执行主函数
main