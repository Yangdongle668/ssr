#!/usr/bin/env bash
# 生成 Clash YAML 配置文件（中国友好分流规则）
# 字段名遵循官方 Clash 标准（protocol-param / obfs-param 带连字符）
# 输出到 ./clash.yaml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

C_GRN='\033[0;32m'
C_YLW='\033[0;33m'
C_RST='\033[0m'

log_info() { echo -e "${C_GRN}[CLASH]${C_RST} $*"; }
log_warn() { echo -e "${C_YLW}[CLASH]${C_RST} $*"; }

# 探测公网 IP（多源容错）
detect_public_ip() {
    local ip=""
    local sources=(
        "https://api.ipify.org"
        "https://ifconfig.me/ip"
        "https://ipinfo.io/ip"
        "https://api.ip.sb/ip"
        "https://ipv4.icanhazip.com"
    )
    for src in "${sources[@]}"; do
        ip=$(curl -fsSL --connect-timeout 5 --max-time 10 "${src}" 2>/dev/null | tr -d '[:space:]' || true)
        if [[ "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "${ip}"
            return 0
        fi
    done
    return 1
}

generate_yaml() {
    local server="$1"
    local port="$2"
    local password="$3"
    local method="$4"
    local protocol="$5"
    local obfs="$6"
    local obfs_param="$7"
    local remark="$8"
    local out_file="$9"

    cat > "${out_file}" <<EOF
# ═══════════════════════════════════════════════════════════
#  Clash 配置文件 (由 ssr-docker-deploy 生成)
#  节点: ${remark}
#  生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# ═══════════════════════════════════════════════════════════

mixed-port: 7890
allow-lan: false
bind-address: '*'
mode: rule
log-level: info
ipv6: true
external-controller: 127.0.0.1:9090
secret: ''

# ───── DNS 配置 (国内 + 海外 fallback) ─────
dns:
  enable: true
  ipv6: false
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - 'localhost.ptlogin2.qq.com'
    - 'stun.*.*'
    - 'stun.*.*.*'
  default-nameserver:
    - 119.29.29.29
    - 223.5.5.5
  nameserver:
    - https://doh.pub/dns-query
    - https://dns.alidns.com/dns-query
    - 119.29.29.29
    - 223.5.5.5
  fallback:
    - https://1.1.1.1/dns-query
    - https://dns.google/dns-query
    - tls://1.0.0.1:853
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

# ───── 代理节点 ─────
proxies:
  - name: "${remark}"
    type: ssr
    server: ${server}
    port: ${port}
    cipher: ${method}
    password: "${password}"
    protocol: ${protocol}
    protocol-param: ""
    obfs: ${obfs}
    obfs-param: "${obfs_param}"
    udp: true

# ───── 策略组 ─────
proxy-groups:
  - name: 🚀 节点选择
    type: select
    proxies:
      - ♻️ 自动选择
      - "${remark}"
      - DIRECT

  - name: ♻️ 自动选择
    type: url-test
    proxies:
      - "${remark}"
    url: http://www.gstatic.com/generate_204
    interval: 300
    tolerance: 50

  - name: 🌍 国外媒体
    type: select
    proxies:
      - 🚀 节点选择
      - ♻️ 自动选择
      - "${remark}"
      - DIRECT

  - name: 📲 电报消息
    type: select
    proxies:
      - 🚀 节点选择
      - "${remark}"
      - DIRECT

  - name: 🍎 苹果服务
    type: select
    proxies:
      - DIRECT
      - 🚀 节点选择

  - name: 🛑 广告拦截
    type: select
    proxies:
      - REJECT
      - DIRECT

  - name: 🐟 漏网之鱼
    type: select
    proxies:
      - 🚀 节点选择
      - DIRECT
      - "${remark}"

# ───── 分流规则 ─────
rules:
  # 局域网与保留地址
  - DOMAIN-SUFFIX,local,DIRECT
  - DOMAIN-SUFFIX,localhost,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,100.64.0.0/10,DIRECT,no-resolve
  - IP-CIDR,17.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR6,::1/128,DIRECT,no-resolve
  - IP-CIDR6,fc00::/7,DIRECT,no-resolve
  - IP-CIDR6,fe80::/10,DIRECT,no-resolve

  # 广告拦截
  - DOMAIN-KEYWORD,admarvel,🛑 广告拦截
  - DOMAIN-KEYWORD,admaster,🛑 广告拦截
  - DOMAIN-KEYWORD,adsage,🛑 广告拦截
  - DOMAIN-KEYWORD,adsmogo,🛑 广告拦截
  - DOMAIN-KEYWORD,adsrvmedia,🛑 广告拦截
  - DOMAIN-KEYWORD,adwords,🛑 广告拦截
  - DOMAIN-KEYWORD,adservice,🛑 广告拦截
  - DOMAIN-SUFFIX,doubleclick.net,🛑 广告拦截

  # 苹果服务
  - DOMAIN-SUFFIX,apple.com,🍎 苹果服务
  - DOMAIN-SUFFIX,icloud.com,🍎 苹果服务
  - DOMAIN-SUFFIX,icloud-content.com,🍎 苹果服务
  - DOMAIN-SUFFIX,me.com,🍎 苹果服务
  - DOMAIN-SUFFIX,mzstatic.com,🍎 苹果服务

  # Telegram
  - DOMAIN-SUFFIX,t.me,📲 电报消息
  - DOMAIN-SUFFIX,tdesktop.com,📲 电报消息
  - DOMAIN-SUFFIX,telegra.ph,📲 电报消息
  - DOMAIN-SUFFIX,telegram.me,📲 电报消息
  - DOMAIN-SUFFIX,telegram.org,📲 电报消息
  - IP-CIDR,91.108.4.0/22,📲 电报消息,no-resolve
  - IP-CIDR,91.108.8.0/22,📲 电报消息,no-resolve
  - IP-CIDR,91.108.12.0/22,📲 电报消息,no-resolve
  - IP-CIDR,91.108.16.0/22,📲 电报消息,no-resolve
  - IP-CIDR,91.108.56.0/22,📲 电报消息,no-resolve
  - IP-CIDR,149.154.160.0/20,📲 电报消息,no-resolve

  # 国外媒体
  - DOMAIN-KEYWORD,youtube,🌍 国外媒体
  - DOMAIN-SUFFIX,googlevideo.com,🌍 国外媒体
  - DOMAIN-SUFFIX,ytimg.com,🌍 国外媒体
  - DOMAIN-SUFFIX,netflix.com,🌍 国外媒体
  - DOMAIN-SUFFIX,nflxvideo.net,🌍 国外媒体
  - DOMAIN-SUFFIX,nflxext.com,🌍 国外媒体
  - DOMAIN-SUFFIX,nflximg.com,🌍 国外媒体
  - DOMAIN-SUFFIX,nflximg.net,🌍 国外媒体
  - DOMAIN-SUFFIX,disney-plus.net,🌍 国外媒体
  - DOMAIN-SUFFIX,disneyplus.com,🌍 国外媒体
  - DOMAIN-SUFFIX,hbo.com,🌍 国外媒体
  - DOMAIN-SUFFIX,hbomax.com,🌍 国外媒体
  - DOMAIN-SUFFIX,spotify.com,🌍 国外媒体
  - DOMAIN-SUFFIX,scdn.co,🌍 国外媒体
  - DOMAIN-SUFFIX,twitch.tv,🌍 国外媒体
  - DOMAIN-SUFFIX,twitchcdn.net,🌍 国外媒体

  # 常见代理目标
  - DOMAIN-KEYWORD,google,🚀 节点选择
  - DOMAIN-KEYWORD,facebook,🚀 节点选择
  - DOMAIN-KEYWORD,twitter,🚀 节点选择
  - DOMAIN-KEYWORD,instagram,🚀 节点选择
  - DOMAIN-KEYWORD,github,🚀 节点选择
  - DOMAIN-SUFFIX,openai.com,🚀 节点选择
  - DOMAIN-SUFFIX,anthropic.com,🚀 节点选择
  - DOMAIN-SUFFIX,claude.ai,🚀 节点选择
  - DOMAIN-SUFFIX,wikipedia.org,🚀 节点选择

  # 国内常见域名直连
  - DOMAIN-SUFFIX,cn,DIRECT
  - DOMAIN-KEYWORD,baidu,DIRECT
  - DOMAIN-KEYWORD,taobao,DIRECT
  - DOMAIN-KEYWORD,alipay,DIRECT
  - DOMAIN-KEYWORD,jd,DIRECT
  - DOMAIN-KEYWORD,qq,DIRECT
  - DOMAIN-KEYWORD,wechat,DIRECT
  - DOMAIN-KEYWORD,weibo,DIRECT
  - DOMAIN-KEYWORD,bilibili,DIRECT
  - DOMAIN-KEYWORD,iqiyi,DIRECT
  - DOMAIN-KEYWORD,youku,DIRECT
  - DOMAIN-KEYWORD,xunlei,DIRECT
  - DOMAIN-KEYWORD,163,DIRECT
  - DOMAIN-KEYWORD,126,DIRECT
  - DOMAIN-SUFFIX,music.163.com,DIRECT

  # GEOIP 兜底
  - GEOIP,LAN,DIRECT,no-resolve
  - GEOIP,CN,DIRECT,no-resolve

  # 漏网之鱼
  - MATCH,🐟 漏网之鱼
EOF
}

main() {
    # 加载 .env
    if [[ -f "${PROJECT_DIR}/.env" ]]; then
        set -a
        # shellcheck disable=SC1091
        source "${PROJECT_DIR}/.env"
        set +a
    fi

    local server="${SSR_SERVER_IP:-}"
    if [[ -z "${server}" ]]; then
        log_info "正在检测公网 IP..."
        server=$(detect_public_ip) || {
            log_warn "无法自动获取公网 IP，请在 .env 中设置 SSR_SERVER_IP" >&2
            return 1
        }
    fi

    local port="${SSR_PORT:-17777}"
    local password="${SSR_PASSWORD:-gugugu}"
    local method="${SSR_METHOD:-chacha20-ietf}"
    local protocol="${SSR_PROTOCOL:-auth_chain_a}"
    local obfs="${SSR_OBFS:-tls1.2_ticket_auth}"
    local obfs_param="${SSR_OBFS_PARAM:-cloud.tencent.com}"
    local remark="${SSR_REMARK:-My-SSR-Node}"

    local out_file="${PROJECT_DIR}/clash.yaml"

    log_info "生成 Clash 配置文件..."
    generate_yaml "${server}" "${port}" "${password}" "${method}" \
                  "${protocol}" "${obfs}" "${obfs_param}" "${remark}" \
                  "${out_file}"

    chmod 600 "${out_file}"

    log_info "✓ 已生成: ${out_file}"
    log_info "  节点: ${remark} (${server}:${port})"
    log_info "  规则: 国内直连 / 国外走代理 / 广告拦截"
}

main "$@"
