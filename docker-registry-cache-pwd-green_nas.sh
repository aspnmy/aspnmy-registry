#!/bin/bash

# 适配绿联云模式

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'
# 指定配置文件和目录
BASE_DIR="/mnt/dm-2/.ugreen_nas/206739/docker/aspnmy_registry"
SSLOCK="$BASE_DIR/ssl_lock.json"

# 配置基本业务目录
mkdir -p $BASE_DIR && mkdir -p $BASE_DIR/{"certs","passwd","config","registry_data"}



# 从 JSON 文件中读取配置并进行校验
DOMAIN=$(jq -r '.domain' "$SSLOCK")
log "DOMAIN的值 : $DOMAIN"
if [ -z "$DOMAIN" ]; then
    log "配置错误：域名证书文件未生成。"
    exit 1
fi
# 生成随机用户名和密码的函数
random_username() {
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 8
}

random_password() {
    tr -dc 'A-Za-z0-9@#$%^&*()_+' </dev/urandom | head -c 16
}
CURRENT_DIR=$(
    cd "$(dirname "$0")" || exit
    pwd
)

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
    curl -sSL https://raw.githubusercontent.com/aspnmy/aspnmy-registry/refs/heads/docker-registry/autorun_upssl.sh -o autorun_upssl.sh  && bash autorun_upssl.sh
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
    local filedir=$BASE_DIR/${username}
    log "生成访问账户 ${username} 密码 ${password}"
    htpasswd -Bbn "${username}" "${password}" > $filedir
    cp -r $BASE_DIR/${username}  $BASE_DIR/passwd/htpasswd
}

update_docker_env(){

    curl -sSL https://raw.githubusercontent.com/aspnmy/aspnmy-registry/refs/heads/docker-registry/en/proxy-config-en.yml -o $BASE_DIR/config/proxy-config-en.yml
    log "更新aspnmy-registry-cache初始参数完成"
}

set_docker_compose_file(){

# 文件名
FILE_NAME="$BASE_DIR/config/docker-registry.yml"
rm -rf $FILE_NAME
# 创建并写入内容到文件
cat <<EOF > $FILE_NAME
name: aspnmy-registry-cache
services:
    registry:
        restart: always
        container_name: aspnmy-registry-cache
        volumes:
            - $BASE_DIR/passwd/htpasswd:/etc/docker/registry/htpasswd:ro
            # 配置缓存模式
            - $BASE_DIR/config/proxy-config-en.yml:/etc/docker/registry/config.yml:ro
            # 配置ssl证书此处为目录模式
            - /etc/letsencrypt/live/$DOMAIN/fullchain.pem:/certs/fullchain.pem
            - /etc/letsencrypt/live/$DOMAIN/privkey.pem:/certs/privkey.pem
            # 配置仓库实际挂载地址
            - $BASE_DIR/registry_data:/var/lib/registry
        environment:
            - REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io
            - REGISTRY_AUTH=htpasswd
            - REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm
            - REGISTRY_AUTH_HTPASSWD_PATH=/etc/docker/registry/htpasswd
            - REGISTRY_HTTP_TLS_CERTIFICATE=/certs/fullchain.pem
            - REGISTRY_HTTP_TLS_KEY=/certs/privkey.pem
        ports:
            - 5000:5000
        image: registry:2
EOF

log "文件 $FILE_NAME 创建成功。"


}

runAspnmyRegistryCache(){
    FILE_NAME="$BASE_DIR/config/docker-registry.yml"

    # 检查文件是否已存在
    if [ -f "$FILE_NAME" ]; then

        docker-compose -f $FILE_NAME up -d
        log "文件 $FILE_NAME 存在。拉取镜像成功，请等待1-5分钟"
    else
        log "文件 $FILE_NAME 不存在。拉取镜像失败"
        exit 1

    fi
}




# 主函数，执行所有设置
main() {
    local current_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    log "脚本开始执行，当前目录：$current_dir"
    # 安装依赖组件
    install_tools
    # 更新ssl证书文件
    update_ssl
    # 设置初始化用户密码
    set_htpasswd
    # 更新基础配置
    update_docker_env
    # 设置docker-compose配置脚本
    set_docker_compose_file
    # 拉起主服务镜像
    runAspnmyRegistryCache
    log "所有设置完成"
}

# 执行主函数
main



# $dockerDir=/mnt/dm-2/.ugreen_nas/206739/docker
# mkdir -p /mnt/dm-2/.ugreen_nas/206739/docker/aspnmy_registry/passwd
# mkdir -p /mnt/dm-2/.ugreen_nas/206739/docker/aspnmy_registry/config
# mkdir -p /mnt/dm-2/.ugreen_nas/206739/docker/aspnmy_registry/registry_data
# mkdir -p /mnt/dm-2/.ugreen_nas/206739/docker/aspnmy_registry/certs



name: aspnmy-registry-cache
services:
    aspnmy-registry-cache:
        restart: always
        container_name: aspnmy-registry-cache
        volumes:
            - /mnt/dm-2/.ugreen_nas/206739/docker/aspnmy_registry/passwd/htpasswd:/etc/docker/registry/htpasswd:ro
            # 配置缓存模式
            - /mnt/dm-2/.ugreen_nas/206739/docker/aspnmy_registry/config/proxy-config-en.yml:/etc/docker/registry/config.yml:ro
            # 配置ssl证书此处为目录模式
            #- /mnt/dm-2/.ugreen_nas/206739/docker/aspnmy_registry/certs/fullchain.pem:/certs/fullchain.pem
            #- /mnt/dm-2/.ugreen_nas/206739/docker/aspnmy_registry/certs/privkey.pem:/certs/privkey.pem
            # 配置仓库实际挂载地址
            - /mnt/dm-2/.ugreen_nas/206739/docker/aspnmy_registry/registry_data:/var/lib/registry
        environment:
            - REGISTRY_PROXY_REMOTEURL=https://docker.shdrr.org
            - REGISTRY_AUTH=htpasswd
            - REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm
            - REGISTRY_AUTH_HTPASSWD_PATH=/etc/docker/registry/htpasswd
            #- REGISTRY_HTTP_TLS_CERTIFICATE=/certs/fullchain.pem
            #- REGISTRY_HTTP_TLS_KEY=/certs/privkey.pem
        ports:
            - 5000:5000
        image: registry:2
        networks:
            - registry-speed-net
## UI
    registry-ui:
        container_name: registry-ui
        image: dqzboy/docker-registry-ui:latest
        environment:
        - DOCKER_REGISTRY_URL=http://aspnmy-registry-cache:5000
        # [必须]使用 openssl rand -hex 16 生成唯一值
        - SECRET_KEY_BASE=9f18244a1e2279fa5sd4a06a335d01b2
        # 启用Image TAG 的删除按钮
        - ENABLE_DELETE_IMAGES=true
        - NO_SSL_VERIFICATION=true
        restart: always
        ports:
        - 50000:8080
        networks:
        - registry-speed-net
networks:
    registry-speed-net: