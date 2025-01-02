# 关于私有库引擎

### podman-registry 分支

- 使用podman或者buildah作为构建引擎的,推荐使用 podman-registry 分支

### docker-registry 分支
- 使用docker作为构建引擎的,推荐使用 docker-registry 分支

### 私有库访问密钥
- 使用htpasswd 作为访问密钥加密程序,用以下命令生成
```
htpasswd -Bbn myuser mypassword > /myregistry/myregistry.htpasswd
```
### 快速部署脚本
- 使用下面命令进行脚本快速部署，拉起私有缓存镜像库
- 第一个用户名及访问密码 使用下面的命令查看日志文件
```
cat $pwd/install.log
```

```
curl -sSL https://raw.githubusercontent.com/aspnmy/aspnmy-registry/refs/heads/docker-registry/docker-registry-cache-dev.sh -o docker-registry-cache-dev.sh && bash docker-registry-cache-dev.sh
```

### docker私有库配置文件

```
name: docker-registry
services:
    registry:
        restart: always
        container_name: registry
        volumes:
            - /opt/aspnmy_registry/passwd/aspnmy_registry.htpasswd:/etc/docker/registry/htpasswd:ro
            # 配置缓存模式
            # - /opt/aspnmy_registry/config/proxy-config-en.yml:/etc/docker/registry/config.yml:ro
            # 配置ssl证书
            - /opt/aspnmy_registry/certs/registry.ny.earth-oline.org-fullchain.pem:/certs/registry.ny.earth-oline.org-fullchain.pem
            - /opt/aspnmy_registry/certs/registry.ny.earth-oline.org-privkey.pem:/certs/registry.ny.earth-oline.org-privkey.pem
            - /opt/aspnmy_registry/registry_data:/var/lib/registry
        environment:
            - REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io
            - REGISTRY_AUTH=htpasswd
            - REGISTRY_AUTH_HTPASSWD_REALM: Registry Realm
            - REGISTRY_AUTH_HTPASSWD_PATH=/etc/docker/registry/htpasswd
            - REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.ny.earth-oline.org-fullchain.pem
            - REGISTRY_HTTP_TLS_KEY=/certs/registry.ny.earth-oline.org-privkey.pem
            #- REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY: /var/lib/registry
        ports:
            - 5000:5000
        image: registry:latest
```

### podman私有库配置文件

```
podman run --name podman-registry \
    -p 5000:5000 \
    -v /opt/aspnmy_registry/data:/var/lib/registry:z \
    # 配置缓存模式
    -v /opt/aspnmy_registry/config.yml:/etc/docker/registry/config.yml:ro
    -v /opt/aspnmy_registry/auth:/auth:z \
    -e "REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io"
    -e "REGISTRY_AUTH=htpasswd" \
    -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    -v /opt/aspnmy_registry/certs:/certs:z \
    -e "REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt" \
    -e "REGISTRY_HTTP_TLS_KEY=/certs/domain.key" \
    -e REGISTRY_COMPATIBILITY_SCHEMA1_ENABLED=true \
    -e REGISTRY_STORAGE_DELETE_ENABLED=true \
    -d \
    docker.io/library/registry:latest

```

### Dockerfile 构建文件
本私有库是用官方仓库文件直接构建的,访问密钥及证书,自动换证书脚本直接封装在容器内,只需运行无需关注其他

### 基础镜像 registry:2

### 缓存模式分支
- 如需使用缓存模式代理上级仓库请按照下面内容进行配置(请确保上级仓库能够访问到-国内需要访问代理地址;国外直接访问原始地址即可)

- 现在,当你尝试拉取一个镜像时,如果它在你的私有 Registry 中不存在,Registry 将会从上游 Registry 拉取并缓存它:

- proxy-config-en.yml
    国外节点请使用这个配置文件(国外节点pull与push均可)
- proxy-config-cn.yml
    国内节点请使用这个配置文件(使用这个配置文件只能执行pull业务无法push)
