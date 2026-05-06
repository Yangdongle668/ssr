FROM teddysun/shadowsocks-r:latest

LABEL maintainer="ssr-docker-deploy"
LABEL description="ShadowsocksR server with auth_chain_a + tls1.2_ticket_auth, optimized for restrictive networks"

RUN apk add --no-cache iproute2 net-tools curl bind-tools tzdata \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

COPY scripts/healthcheck.sh /healthcheck.sh
RUN chmod +x /healthcheck.sh

EXPOSE 17777/tcp 17777/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD /healthcheck.sh || exit 1
