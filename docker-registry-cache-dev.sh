#!/bin/bash
# 注册表开发模式-单机测试版
# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 指定配置文件和目录
BASE_DIR="/etc/aspnmy_registry"
SSLOCK="$BASE_DIR/ssl_lock.json"
PROXY_CONFIG_FILE="$BASE_DIR/config/proxy-config.yml"
en_remoteurl="registry-1.docker.io"
cn_remoteurl="gateway.cf.earth-oline.org"
remoteurl=""
DOMAIN=$(jq -r '.domain' "$SSLOCK")
# 获取当前目录
CURRENT_DIR=$(cd "$(dirname "$0")" || exit; pwd)

# 日志记录函数
log() {
    local message="[Aspnmy Log]: $1"
    case "$1" in
        *"失败"*|*"错误"*|*"请使用 root 或 sudo 权限运行此脚本"*)
            echo -e "${RED}${message}${NC}" 2>&1 | tee -a "${BASE_DIR}/install.log"
            ;;
        *"成功"*)
            echo -e "${GREEN}${message}${NC}" 2>&1 | tee -a "${BASE_DIR}/install.log"
            ;;
        *"忽略"*|*"跳过"*)
            echo -e "${YELLOW}${message}${NC}" 2>&1 | tee -a "${BASE_DIR}/install.log"
            ;;
        *)
            echo -e "${BLUE}${message}${NC}" 2>&1 | tee -a "${BASE_DIR}/install.log"
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
    curl -sSL https://raw.githubusercontent.com/aspnmy/aspnmy-registry/refs/heads/docker-registry/autorun_upssl.sh -o autorun_upssl.sh && bash autorun_upssl.sh
    if [ $? -ne 0 ]; then
        log "SSL证书更新失败"
        exit 1
    fi
    log "SSL证书更新成功"
}

# 生成随机用户名和密码的函数
random_username() {
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 8
}

random_password() {
    tr -dc 'A-Za-z0-9@#$%^&*()_+' </dev/urandom | head -c 16
}

# 设置基本认证
set_htpasswd() {
    local username
    local password
    username=$(random_username)
    password=$(random_password)
    local filedir=$BASE_DIR/passwd/htpasswd

    log "生成访问账户 ${username} 密码 ${password}"
    htpasswd -Bbn "${username}" "${password}" > "$filedir"
}

# 设置docker-compose配置脚本
set_docker_compose_file() {
    local FILE_NAME="$BASE_DIR/config/docker-registry.yml"

    if [ -f "$FILE_NAME" ]; then
        log "警告:文件 $FILE_NAME 已存在，将被覆盖。"
    fi

    cat <<EOF > "$FILE_NAME"
name: aspnmy-registry-cache
services:
    registry:
        restart: always
        container_name: aspnmy-registry-cache
        volumes:
            - $BASE_DIR/passwd/htpasswd:/etc/docker/registry/auth/htpasswd:ro
            - $BASE_DIR/config/proxy-config.yml:/etc/docker/registry/config.yml:ro
            - /etc/letsencrypt/live/$DOMAIN:/certs
            - /opt/aspnmy_registry/registry_data:/var/lib/registry
        environment:
            - REGISTRY_AUTH=htpasswd
            - REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm
            - REGISTRY_AUTH_HTPASSWD_PATH=/etc/docker/registry/auth/htpasswd
            - REGISTRY_HTTP_TLS_CERTIFICATE=/certs/fullchain.pem
            - REGISTRY_HTTP_TLS_KEY=/certs/privkey.pem
        ports:
            - 443:443
        image: registry:2
EOF
    log "文件 $FILE_NAME 创建成功。"
}

# 设置基本配置
set_docker_env() {
    if [ -f "$PROXY_CONFIG_FILE" ]; then
        log "配置文件已存在。"
        read -p "是否要覆盖现有的配置文件？(y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            log "操作已取消。"
            return 1
        fi
        log "警告:文件 $PROXY_CONFIG_FILE 将被覆盖。"
    fi

    echo "请选择服务器所在的区域,国内请选(2),国外请选(1),其他自定义地址请自行输入:"
    select opt in "$en_remoteurl" "$cn_remoteurl" "输入其他"; do
        case $REPLY in
            1) remoteurl=$opt; break;;
            2) remoteurl=$opt; break;;
            3)
                while true; do
                    read -p "请输入远程镜像域名 (domain): " remoteurl
                    if [ -z "$remoteurl" ]; then
                        echo "远程镜像域名是必填项，请重新输入。"
                    else
                        break
                    fi
                done
                break;;
            *) echo "无效选项，请重新选择。";;
        esac
    done

    log "您选择的远程镜像域名是: $remoteurl"

    cat <<EOF > "$PROXY_CONFIG_FILE"
version: 0.1
log:
    fields:
        service: registry
storage:
    cache:
        blobdescriptor: inmemory
    delete:
        enabled: true
    filesystem:
        rootdirectory: /var/lib/registry
        maxthreads: 100
http:
    addr: :5000
    host: $DOMAIN
    tls:
        certificate: /certs/fullchain.pem
        key: /certs/privkey.pem

    headers:
        X-Content-Type-Options: [nosniff]
proxy:
    remoteurl: https://$remoteurl
EOF

    log "文件 $PROXY_CONFIG_FILE 创建成功。"
    log "更新aspnmy-registry-cache初始参数完成"
}

# 拉起主服务镜像
runAspnmyRegistryCache() {
    local FILE_NAME="$BASE_DIR/config/docker-registry.yml"

    if [ -f "$FILE_NAME" ]; then
        docker-compose -f "$FILE_NAME" up -d
        log "文件 $FILE_NAME 存在。拉取镜像成功，请等待1-5分钟"
    else
        log "文件 $FILE_NAME 不存在。拉取镜像失败"
        exit 1
    fi
}

# 主函数，执行所有设置
main() {
    log "脚本开始执行，当前目录:$CURRENT_DIR"

    install_tools
    update_ssl
    set_htpasswd
    set_docker_env
    set_docker_compose_file
    runAspnmyRegistryCache
    log "所有设置完成"
}

# 执行主函数
main