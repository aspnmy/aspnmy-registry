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
### docker私有库配置文件

```
name: docker-registry
services:
    registry:
        restart: always
        container_name: registry
        volumes:
            - /opt/aspnmy_registry/myregistry.htpasswd:/etc/docker/registry/htpasswd:ro
            # 配置缓存模式
            - /opt/aspnmy_registry/config.yml:/etc/docker/registry/config.yml:ro
        environment:
            - REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io
            - REGISTRY_AUTH=htpasswd
            - REGISTRY_AUTH_HTPASSWD_PATH=/etc/docker/registry/htpasswd
            - REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt
            - REGISTRY_HTTP_TLS_KEY=/certs/domain.key
        ports:
            - 5000:5000
        image: registry:2
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
