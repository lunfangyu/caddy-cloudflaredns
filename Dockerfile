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
# 使用 Caddy 在非 443 端口开启 HTTPS 原理：https://ssine.ink/posts/caddy-non-443-port-https/
# 配置全局端口
{
    http_port 800
    https_port 888
    auto_https disable_redirects
    email {env.CLOUDFLARE_EMAIL}

    log {
        # 1. 日志级别（优先级：DEBUG < INFO < WARN < ERROR < FATAL）
        level info  # 生产环境推荐 INFO/ERROR，调试用 DEBUG

        # 2. 全局日志格式（控制台/JSON，二选一，默认console）
        format console

        # 3. 日志输出目标（默认stdout，可改为文件/多个目标）
        output file /var/log/caddy/global.log {
            roll_size 100MB        # 单个日志文件大小阈值
            roll_keep 10           # 保留历史日志文件数
            roll_keep_for 168h     # 是将滚动的文件作为[持续时间字符串]保留多长时间。目前的实现支持日的分辨率；小数的值被四舍五入到下一个整日。例如，36h（1.5天）被四舍五入为48h（2天）。默认值: 2160h (90天)
            roll_local_time        # 将滚动设置为在文件名中使用本地时间戳。默认值：使用UTC时间。备注：此配置不知何原因，配置后不生效
        }
    }
}

# 1. 800端口：仅目标域名的HTTP请求跳转
example.com:800 *.example.com:800 {
    # 组合匹配器：仅 HTTP协议 + 目标域名 才触发跳转
    @need-redirect {
        protocol http
        host example.com www.example.com nas.example.com
    }
    # 直接跳转（无嵌套，匹配器写在redir前）
    redir @need-redirect https://{host}:888{uri} permanent
}

# 2. 888端口：处理HTTP重定向到HTTPS
# 此配置不生效，核心症结：Caddy 对「泛域名 + 非标准端口」的 HTTP 请求存在监听逻辑缺陷
#  Caddy社区高频反馈的场景：当配置 *.example.com:888 这种「泛域名 + 非标准端口（非 80/443）」时，Caddy 会默认将该端口标记为「HTTPS 专用」，导致 HTTP 请求无法被块内的 protocol http 匹配器捕获，直接触发 TLS 层的「HTTP→HTTPS 服务器」错误，并非规则优先级问题，而是 Caddy 对非标准端口的协议监听逻辑导致。
# :888 {
#    # 优先拦截所有HTTP请求，强制跳转HTTPS（优先级最高）
#    @http-request protocol http
#    redir @http-request https://{host}:888{uri} permanent
#}

# 3. 域名+端口监听，处理https请求
example.com:888 *.example.com:888 {
    # 假设你有example.com这个域名，所有服务都将通过这个域名及它的二级域名提供访问，那么如上
    # 二级/三级域名的证书不通用 如果需要为三级域名申请证书 也需要添加在上面
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
    
    # 创建一个名为@server-test的匹配器 他的匹配规则是请求标头的host字段（即访问的域名）为 nas.example.com
    @server-test host test.example.com
    # 处理符合@server-test匹配器规则的访问 提供反向代理
    handle @server-test {
        reverse_proxy 192.168.123.88:5666
    }
    
    # 静态页面。可以匹配多个条件 比如两个不同的host
    @static-website host example.com www.example.com
    handle @static-website {
        # 直接返回
        respond "Hello, world!"
    }
}

EOF

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# 设置工作目录
WORKDIR /srv

# 运行Caddy
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]

# 暴露常用端口
EXPOSE 80 443 800 888
