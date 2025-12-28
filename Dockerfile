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

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# 设置工作目录
WORKDIR /srv

# 运行Caddy
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]

# 暴露常用端口
EXPOSE 80 443 1080 1443
