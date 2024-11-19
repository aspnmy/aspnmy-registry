#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'
registry_user=$(random_username)
registry_pwd=$(random_password)

CURRENT_DIR=$(
    cd "$(dirname "$0")" || exit
    pwd
)

# 生成一个随机用户名
random_username() {
    # 使用 tr 和/dev/urandom 生成随机字符
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 8

}

# 生成一个随机密码
random_password() {
    # 使用 tr 和/dev/urandom 生成随机字符，并包含一些特殊字符
    tr -dc 'A-Za-z0-9@#$%^&*()_+' </dev/urandom | head -c 16
}


function log() {
    message="[Aspnmy Log]: $1 "
    case "$1" in
        *"失败"*|*"错误"*|*"请使用 root 或 sudo 权限运行此脚本"*)
            echo -e "${RED}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
        *"成功"*)
            echo -e "${GREEN}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
        *"忽略"*|*"跳过"*)
            echo -e "${YELLOW}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
        *)
            echo -e "${BLUE}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
    esac
}



function Install_tools(){

    apt install -y apache2 apache2-utils certbot python3-certbot-apache jq nslookup

}

function update_ssl(){

    # 证书文件：
    # /etc/letsencrypt/live/yourdomain.com/cert.pem
    # 私钥文件：
    # /etc/letsencrypt/live/yourdomain.com/privkey.pem
    # 证书链文件：
    # /etc/letsencrypt/live/yourdomain.com/chain.pem


    curl -sSL https://raw.githubusercontent.com/aspnmy/aspnmy-registry/refs/heads/docker-registry/autorun_upssl.sh  -o autorun_upssl.sh && chmod u+x autorun_upssl.sh && bash autorun_upssl.sh

}

function Set_htpasswd(){


    mkdir -p /etc/aspnmy_registry
    log "生成访问账户 ${registry_user} 密码 ${registry_pwd}"
    htpasswd -Bbn ${registry_user} ${registry_pwd} > /etc/aspnmy_registry/${registry_user}

}

# 安装私有库的缓存模式
function add_docker_registry_cache(){


    mkdir -p /etc/aspnmy_registry && touch /etc/aspnmy_registry/config.json && echo '{"domain": "registry.hk.earth-oline.org","cf_key": "mk2a1ukQx-OWV1qfQa76t5AnmfeXRKbJnyT4LS_j","zone_id": "34150e30f211ca717740d70bdf9a22cf","sub_domain": "registry.hk.earth-oline.org","email": "support@e2bank.cn"}' > /etc/aspnmy_registry/config.json
    log "生成访问账户 ${registry_user} 密码 ${registry_pwd}"
    htpasswd -Bbn ${registry_user} ${registry_pwd} > /etc/aspnmy_registry/${registry_user}

}

