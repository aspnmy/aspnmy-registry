#!/bin/bash
# 生产模式下使用
# 挂载nginx作为前置用户名认证 反代
# 挂载redis作为负载均衡
# 挂载本地文件驱动或者S3桶驱动作为存储空间
# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 指定配置文件和目录
BASE_DIR="/etc/aspnmy_registry"

CURRENT_DIR=$(
    cd "$(dirname "$0")" || exit
    pwd
)

mkdir -p $BASE_DIR/{"redis","nginx","config"}
mkdir -p $BASE_DIR/nginx/{"certs","config","auth"}
mkdir -p $BASE_DIR/redis/{"certs","config"}
mkdir -p /opt/aspnmy_registry/registry_data


# nginx主目录
NGINX_DIR="$BASE_DIR/nginx"

# redis主目录
REDIS_DIR="$BASE_DIR/redis"

SSLOCK="$BASE_DIR/ssl_lock.json"
PROXY_CONFIG_FILE="$BASE_DIR/config/proxy-config-nginx.yml"
en_remoteurl="registry-1.docker.io"
cn_remoteurl="gateway.cf.earth-oline.org"
remoteurl=""
DOMAIN=$(jq -r '.domain' "$SSLOCK")
SET_REDIS_PASSWORD="root#1314"

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



# 生成随机用户名和密码的函数
random_username() {
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 8
}

random_password() {
    tr -dc 'A-Za-z0-9@#$%^&*()_+' </dev/urandom | head -c 16
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
    curl -sSL https://raw.githubusercontent.com/aspnmy/aspnmy-registry/refs/heads/docker-registry/autorun_upssl.sh -o autorun_upssl.sh  && bash autorun_upssl.sh
    if [ $? -ne 0 ]; then
        log "SSL证书更新失败"
        exit 1
    fi
    log "SSL证书更新成功"
}

# 设置nginx基本认证
set_nginx_htpasswd() {
    # 追加模式可以管理多用户
    local username
    local password
    username=$(random_username)
    password=$(random_password)
    local filedir=$NGINX_DIR/auth/htpasswd
    log "生成访问账户 ${username} 密码 ${password}"
    htpasswd -Bbn "${username}" "${password}" >> "$filedir"
}

set_docker_env() {


    # 检查配置文件是否存在
    if [ -f "$PROXY_CONFIG_FILE" ]; then
        log "配置文件已存在。"
        read -p "是否要覆盖现有的配置文件？(y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            log "操作已取消。"
            return 1
        fi
        log "警告:文件 $PROXY_CONFIG_FILE 将被覆盖。"
    fi

    # 显示选择菜单
    echo "请选择服务器所在的区域,国内请选(2),国外请选(1),其他自定义地址请自行输入:"
    select opt in "$en_remoteurl" "$cn_remoteurl" "输入其他"; do
        case $REPLY in
            1) remoteurl=$opt; break;;
            2) remoteurl=$opt; break;;
            3)
                # 循环直到用户输入一个非空值
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

    # 创建并写入内容到文件
    cat <<EOF > "$PROXY_CONFIG_FILE"
version: 0.1
log:
    fields:
        service: registry
    storage:
    cache:
        blobdescriptor: redis
        redis:
        addr: redis:6379
        db: 0
        password: $SET_REDIS_PASSWORD
    delete:
        enabled: true
    filesystem:
        rootdirectory: /var/lib/registry
        maxthreads: 100
http:
    addr: :5000
    headers:
        X-Content-Type-Options: [nosniff]
    proxy:
        remoteurl: https://$remoteurl
EOF

    log "文件 $PROXY_CONFIG_FILE 创建成功。"
    log "更新aspnmy-registry-cache初始参数完成"
}

set_Nignx_Config() {
    # 文件名
    FILE_NAME="$NGINX_DIR/config/nginx.conf"
    if [ -f "$FILE_NAME" ]; then
        log "警告:文件 $FILE_NAME 已存在，将被覆盖。"
    fi

    # 创建并写入内容到文件
    cat <<EOF > "$FILE_NAME"
events {
    worker_connections  1024;
}

http {

    upstream docker-registry {
        server registry-cache:5000;
    }

    ## Set a variable to help us decide if we need to add the
    ## 'Docker-Distribution-Api-Version' header.
    ## The registry always sets this header.
    ## In the case of nginx performing auth, the header is unset
    ## since nginx is auth-ing before proxying.
    map $upstream_http_docker_distribution_api_version $docker_distribution_api_version {
        '' 'registry/2.0';
    }

    server {
        listen 443 ssl;
        server_name $DOMAIN;

        # SSL
        ssl_certificate /etc/nginx/conf.d/fullchain.pem;
        ssl_certificate_key /etc/nginx/conf.d/privkey.pem;

        # Recommendations from https://raymii.org/s/tutorials/Strong_SSL_Security_On_nginx.html
        ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
        ssl_ciphers 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
        ssl_prefer_server_ciphers on;
        ssl_session_cache shared:SSL:10m;

        # disable any limits to avoid HTTP 413 for large image uploads
        client_max_body_size 0;

        # required to avoid HTTP 411: see Issue #1486 (https://github.com/moby/moby/issues/1486)
        chunked_transfer_encoding on;

        location /v2/ {
        # Do not allow connections from docker 1.5 and earlier
        # docker pre-1.6.0 did not properly set the user agent on ping, catch "Go *" user agents
        if ($http_user_agent ~ "^(docker\/1\.(3|4|5(?!\.[0-9]-dev))|Go ).*$" ) {
            return 404;
        }

        # To add basic authentication to v2 use auth_basic setting.
        auth_basic "Registry realm";
        auth_basic_user_file /etc/nginx/conf.d/htpasswd;

        ## If $docker_distribution_api_version is empty, the header is not added.
        ## See the map directive above where this variable is defined.
        add_header 'Docker-Distribution-Api-Version' $docker_distribution_api_version always;

        proxy_pass                          http://docker-registry;
        proxy_set_header  Host              $http_host;   # required for docker client's sake
        proxy_set_header  X-Real-IP         $remote_addr; # pass on real client's IP
        proxy_set_header  X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header  X-Forwarded-Proto $scheme;
        proxy_read_timeout                  900;
        }
    }
    }
EOF
}

set_docker_compose_Nignx_file() {
    # 配置以Nginx为用户名验证代理的注册表
    # 确保必要的变量被设置
    if [ -z "$SSLOCK" ] || [ -z "$BASE_DIR" ]; then
        log "错误:SSLOCK 或 BASE_DIR 变量未设置。"
        return 1
    fi


    if [ -z "$DOMAIN" ]; then
        log "配置错误:域名未设置。先生成域名证书。"
        update_ssl
        # 重新读取 DOMAIN，因为可能在 update_ssl 中设置
        DOMAIN=$(jq -r '.domain' "$SSLOCK")
        if [ -z "$DOMAIN" ]; then
            log "配置错误:域名证书文件未生成。"
            return 1
        fi
    fi

    # 文件名
    FILE_NAME="$BASE_DIR/config/docker-registry-nginx.yml"
    if [ -f "$FILE_NAME" ]; then
        log "警告:文件 $FILE_NAME 已存在，将被覆盖。"
    fi

    # 创建并写入内容到文件
    cat <<EOF > "$FILE_NAME"
name: aspnmy-nginx-registry-cache
services:
    registry-redis:
        image: redis:alpine
        environment:
            - REDIS_PASSWORD=$SET_REDIS_PASSWORD
            command: redis-server --save 60 1 --loglevel warning --requirepass ${REDIS_PASSWORD}
        networks:
            - registry-network
    registry-nginx:
        # Note : Only nginx:alpine supports bcrypt.
        # If you don't need to use bcrypt, you can use a different tag.
        # Ref. https://github.com/nginxinc/docker-nginx/issues/29
        image: "nginx:alpine"
        ports:
            - 5043:443
        depends_on:
            - registry-cache
        volumes:

            - $NGINX_DIR/auth:/etc/nginx/conf.d
            - $NGINX_DIR/config/nginx.conf:/etc/nginx/nginx.conf:ro
            - $NGINX_DIR/config/certs/fullchain.pem:/etc/nginx/conf.d/fullchain.pem
            - $NGINX_DIR/config/certs/privkey.pem:/etc/nginx/conf.d/privkey.pem
            # auth_basic_user_file /etc/nginx/conf.d/htpasswd
            - $NGINX_DIR/auth/htpasswd:/etc/nginx/conf.d/htpasswd
        networks:
            - registry-network


    registry-cache:
        image: registry:2
        volumes:
            # 配置仓库实际挂载地址
            - /opt/aspnmy_registry/registry_data:/var/lib/registry
            # 配置缓存模式
            - $PROXY_CONFIG_FILE:/etc/docker/registry/config.yml:ro
        depends_on:
            - registry-redis
        networks:
            - registry-network
networks:
    registry-network:

EOF
    log "文件 $FILE_NAME 创建成功。"
}




runAspnmyRegistryCacheNginx(){
    FILE_NAME="$BASE_DIR/config/docker-registry-nginx.yml"

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
    log "脚本开始执行，当前目录:$current_dir"

    # 安装依赖组件
    install_tools
    # 更新ssl证书文件
    update_ssl
    # 设置初始化用户密码
    set_htpasswd
    # 更新基础配置
    set_docker_env
    # 设置docker-compose配置脚本
    set_docker_compose_file
    # 拉起主服务镜像
    runAspnmyRegistryCache
    log "所有设置完成"
}

# 执行主函数
main