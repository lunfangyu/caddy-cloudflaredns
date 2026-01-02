# syntax=docker/dockerfile:1

ARG TAG

FROM --platform=$BUILDPLATFORM caddy:$TAG-builder-alpine AS builder

ARG TARGETOS TARGETARCH

RUN GOOS=$TARGETOS GOARCH=$TARGETARCH \
    xcaddy build \
    --with github.com/caddy-dns/cloudflare \
    --with github.com/WeidiDeng/caddy-cloudflare-ip \
    --with github.com/mholt/caddy-dynamicdns \
    --with github.com/mholt/caddy-webdav

FROM caddy:$TAG-alpine

# ========== 新增：声明 Cloudflare 环境变量（带默认值占位符） ==========
# Cloudflare 账号邮箱（可在运行容器时通过 -e 覆盖）
ENV CLOUDFLARE_EMAIL=""
# Cloudflare API 令牌（建议运行时通过 -e 传入，不要硬编码）
ENV CLOUDFLARE_API_TOKEN=""

# 设置时区为北京时间
ENV TZ=Asia/Shanghai
# 安装时区数据并设置
RUN apk add --no-cache tzdata && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    # 清理缓存以减小镜像大小
    rm -rf /var/cache/apk/*

# 验证时区设置
RUN echo "Container timezone set to:" && date && echo "Timezone file:" && cat /etc/timezone

# ========== 新增：添加默认Caddyfile到镜像 ==========
# 直接在Dockerfile中通过HERE DOC创建Caddyfile，无需外部文件
COPY <<EOF /etc/caddy/Caddyfile
# 配置全局端口（也可以改为其他端口）
{
    http_port 80
    https_port 443
    email {env.CLOUDFLARE_EMAIL}
}

example.com *.example.com {

    # 一级/二级/三级域名的证书不通用 如果需要为三级域名申请证书 也需要添加在上面
    tls {  
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
    
    # 创建一个名为server-1的匹配器 匹配nas.example.com
    @server-1 host nas.example.com
    # 反向代理到内网服务
    handle @server-1 {
        reverse_proxy 192.168.123.88:5666
    }
    
    # 第二个域名反代理配置
    @server-2 host s2.example.com
    handle @server-2 {
        reverse_proxy 192.168.123.88:8080
    }
    
    # 静态页面（匹配example.com/www.example.com）
    @static-website host example.com www.example.com
    handle @static-website {
        # 直接返回文本（可替换为静态文件服务）
        respond "Hello, world!"

        # 如需静态网页，取消以下注释并挂载目录
        # root * /srv/www
        # file_server
    }
    
    # 兜底规则：未匹配的请求返回404
    handle {
        respond 404
    }
}
EOF

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# 设置工作目录
WORKDIR /srv

# 运行Caddy
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]

# 暴露常用端口
EXPOSE 80 443 1080 1443
