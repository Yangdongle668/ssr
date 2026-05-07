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
#
#  规则源: Loyalsoldier/clash-rules (社区维护，每周自动更新)
#  策略组: 13 组 (节点选择 / 自动选择 / 媒体 / 社交 / 服务 / AI 等)
# ═══════════════════════════════════════════════════════════

mixed-port: 7890
allow-lan: true
bind-address: '*'
mode: rule
log-level: info
ipv6: false
external-controller: 0.0.0.0:9090
secret: ''

# ───── DNS 配置 (国内 DoH + 海外 fallback) ─────
dns:
  enable: true
  ipv6: false
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - '+.pool.ntp.org'
    - 'localhost.ptlogin2.qq.com'
    - 'msftconnecttest.com'
    - 'msftncsi.com'
    - 'stun.*.*'
    - 'stun.*.*.*'
    - '+.stun.*.*'
    - '+.stun.*.*.*'
    - '+.stun.*.*.*.*'
    - '*.n.n.srv.nintendo.net'
    - '+.lan'
    - '+.srv.nintendo.net'
    - 'xbox.*.*.microsoft.com'
    - '*.*.xboxlive.com'
    - 'WORKGROUP'
  default-nameserver:
    - 119.29.29.29
    - 223.5.5.5
    - 114.114.114.114
  nameserver:
    - https://doh.pub/dns-query
    - https://dns.alidns.com/dns-query
    - 119.29.29.29
    - 223.5.5.5
  fallback:
    - https://1.1.1.1/dns-query
    - https://dns.google/dns-query
    - tls://1.0.0.1:853
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4
      - 0.0.0.0/32

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

# ───── 策略组 (13 组) ─────
proxy-groups:
  - name: 🔰 节点选择
    type: select
    proxies:
      - ♻️ 自动选择
      - 🎯 全球直连
      - "${remark}"

  - name: ♻️ 自动选择
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 300
    tolerance: 50
    proxies:
      - "${remark}"

  - name: 🎥 NETFLIX
    type: select
    proxies:
      - 🔰 节点选择
      - ♻️ 自动选择
      - "${remark}"
      - 🎯 全球直连

  - name: 🌍 国外媒体
    type: select
    proxies:
      - 🔰 节点选择
      - ♻️ 自动选择
      - "${remark}"
      - 🎯 全球直连

  - name: 🌏 国内媒体
    type: select
    proxies:
      - 🎯 全球直连
      - 🔰 节点选择

  - name: 📲 电报信息
    type: select
    proxies:
      - 🔰 节点选择
      - "${remark}"
      - 🎯 全球直连

  - name: 🤖 AI 服务
    type: select
    proxies:
      - 🔰 节点选择
      - ♻️ 自动选择
      - "${remark}"
      - 🎯 全球直连

  - name: 🍎 苹果服务
    type: select
    proxies:
      - 🎯 全球直连
      - 🔰 节点选择
      - "${remark}"

  - name: Ⓜ️ 微软服务
    type: select
    proxies:
      - 🎯 全球直连
      - 🔰 节点选择
      - "${remark}"

  - name: ⛔️ 广告拦截
    type: select
    proxies:
      - 🛑 全球拦截
      - 🎯 全球直连
      - 🔰 节点选择

  - name: 🎯 全球直连
    type: select
    proxies:
      - DIRECT
      - 🔰 节点选择

  - name: 🛑 全球拦截
    type: select
    proxies:
      - REJECT
      - DIRECT

  - name: 🐟 漏网之鱼
    type: select
    proxies:
      - 🔰 节点选择
      - 🎯 全球直连
      - ♻️ 自动选择
      - "${remark}"

# ───── 远程规则集 (Loyalsoldier/clash-rules，每天自动更新) ─────
rule-providers:
  reject:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/reject.txt"
    path: ./ruleset/reject.yaml
    interval: 86400

  icloud:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/icloud.txt"
    path: ./ruleset/icloud.yaml
    interval: 86400

  apple:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/apple.txt"
    path: ./ruleset/apple.yaml
    interval: 86400

  google:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/google.txt"
    path: ./ruleset/google.yaml
    interval: 86400

  proxy:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/proxy.txt"
    path: ./ruleset/proxy.yaml
    interval: 86400

  direct:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/direct.txt"
    path: ./ruleset/direct.yaml
    interval: 86400

  private:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/private.txt"
    path: ./ruleset/private.yaml
    interval: 86400

  gfw:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/gfw.txt"
    path: ./ruleset/gfw.yaml
    interval: 86400

  tld-not-cn:
    type: http
    behavior: domain
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/tld-not-cn.txt"
    path: ./ruleset/tld-not-cn.yaml
    interval: 86400

  telegramcidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/telegramcidr.txt"
    path: ./ruleset/telegramcidr.yaml
    interval: 86400

  cncidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/cncidr.txt"
    path: ./ruleset/cncidr.yaml
    interval: 86400

  lancidr:
    type: http
    behavior: ipcidr
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/lancidr.txt"
    path: ./ruleset/lancidr.yaml
    interval: 86400

  applications:
    type: http
    behavior: classical
    url: "https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/applications.txt"
    path: ./ruleset/applications.yaml
    interval: 86400

# ───── 分流规则 (优先级从上到下) ─────
rules:
  # ─── AI 服务（最高优先级，避免被其它规则匹配走错组）───
  - DOMAIN-SUFFIX,openai.com,🤖 AI 服务
  - DOMAIN-SUFFIX,oaistatic.com,🤖 AI 服务
  - DOMAIN-SUFFIX,oaiusercontent.com,🤖 AI 服务
  - DOMAIN-SUFFIX,chatgpt.com,🤖 AI 服务
  - DOMAIN-SUFFIX,anthropic.com,🤖 AI 服务
  - DOMAIN-SUFFIX,claude.ai,🤖 AI 服务
  - DOMAIN-SUFFIX,anthropicusercontent.com,🤖 AI 服务
  - DOMAIN-SUFFIX,gemini.google.com,🤖 AI 服务
  - DOMAIN-SUFFIX,bard.google.com,🤖 AI 服务
  - DOMAIN-SUFFIX,perplexity.ai,🤖 AI 服务
  - DOMAIN-SUFFIX,midjourney.com,🤖 AI 服务
  - DOMAIN-SUFFIX,poe.com,🤖 AI 服务
  - DOMAIN-SUFFIX,character.ai,🤖 AI 服务
  - DOMAIN-KEYWORD,openai,🤖 AI 服务
  - DOMAIN-KEYWORD,anthropic,🤖 AI 服务

  # ─── Netflix 专组 ───
  - DOMAIN-SUFFIX,netflix.com,🎥 NETFLIX
  - DOMAIN-SUFFIX,netflix.net,🎥 NETFLIX
  - DOMAIN-SUFFIX,nflxext.com,🎥 NETFLIX
  - DOMAIN-SUFFIX,nflximg.com,🎥 NETFLIX
  - DOMAIN-SUFFIX,nflximg.net,🎥 NETFLIX
  - DOMAIN-SUFFIX,nflxso.net,🎥 NETFLIX
  - DOMAIN-SUFFIX,nflxvideo.net,🎥 NETFLIX
  - DOMAIN-KEYWORD,netflix,🎥 NETFLIX

  # ─── 应用进程直连 (BT/迅雷/网盘客户端) ───
  - RULE-SET,applications,🎯 全球直连

  # ─── 局域网 / 私有网络 ───
  - DOMAIN,clash.razord.top,🎯 全球直连
  - DOMAIN,yacd.haishan.me,🎯 全球直连
  - DOMAIN,yacd.metacubex.one,🎯 全球直连
  - DOMAIN,d.metacubex.one,🎯 全球直连
  - RULE-SET,private,🎯 全球直连
  - RULE-SET,lancidr,🎯 全球直连,no-resolve

  # ─── 广告拦截 / 隐私追踪 / 挖矿 (规则集，30000+ 条) ───
  - RULE-SET,reject,⛔️ 广告拦截

  # ─── Apple 服务 (国内 CDN 直连更快) ───
  - RULE-SET,icloud,🍎 苹果服务
  - RULE-SET,apple,🍎 苹果服务

  # ─── 微软服务 ───
  - DOMAIN-SUFFIX,office.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,office.net,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,office365.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,microsoft.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,microsoftonline.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,onedrive.live.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,sharepoint.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,sharepointonline.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,outlook.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,live.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,bing.com,Ⓜ️ 微软服务
  - DOMAIN-SUFFIX,msftconnecttest.com,Ⓜ️ 微软服务

  # ─── Google 服务 ───
  - RULE-SET,google,🔰 节点选择

  # ─── Telegram (域名 + IP 段) ───
  - DOMAIN-SUFFIX,t.me,📲 电报信息
  - DOMAIN-SUFFIX,tdesktop.com,📲 电报信息
  - DOMAIN-SUFFIX,telegra.ph,📲 电报信息
  - DOMAIN-SUFFIX,telegram.me,📲 电报信息
  - DOMAIN-SUFFIX,telegram.org,📲 电报信息
  - DOMAIN-SUFFIX,telesco.pe,📲 电报信息
  - RULE-SET,telegramcidr,📲 电报信息,no-resolve

  # ─── 国内常用媒体 (B站/爱奇艺/优酷等) ───
  - DOMAIN-SUFFIX,bilibili.com,🌏 国内媒体
  - DOMAIN-SUFFIX,bilivideo.com,🌏 国内媒体
  - DOMAIN-SUFFIX,hdslb.com,🌏 国内媒体
  - DOMAIN-SUFFIX,iqiyi.com,🌏 国内媒体
  - DOMAIN-SUFFIX,iqiyipic.com,🌏 国内媒体
  - DOMAIN-SUFFIX,qy.net,🌏 国内媒体
  - DOMAIN-SUFFIX,youku.com,🌏 国内媒体
  - DOMAIN-SUFFIX,mgtv.com,🌏 国内媒体
  - DOMAIN-SUFFIX,tudou.com,🌏 国内媒体
  - DOMAIN-SUFFIX,le.com,🌏 国内媒体
  - DOMAIN-SUFFIX,ku6.com,🌏 国内媒体
  - DOMAIN-SUFFIX,music.163.com,🌏 国内媒体
  - DOMAIN-SUFFIX,kuwo.cn,🌏 国内媒体
  - DOMAIN-SUFFIX,kugou.com,🌏 国内媒体
  - DOMAIN-SUFFIX,xiami.com,🌏 国内媒体

  # ─── 国外媒体 (YouTube/Twitch/Spotify/HBO等) ───
  - DOMAIN-SUFFIX,youtube.com,🌍 国外媒体
  - DOMAIN-SUFFIX,googlevideo.com,🌍 国外媒体
  - DOMAIN-SUFFIX,ytimg.com,🌍 国外媒体
  - DOMAIN-SUFFIX,youtu.be,🌍 国外媒体
  - DOMAIN-SUFFIX,disneyplus.com,🌍 国外媒体
  - DOMAIN-SUFFIX,disney-plus.net,🌍 国外媒体
  - DOMAIN-SUFFIX,disney.io,🌍 国外媒体
  - DOMAIN-SUFFIX,bamgrid.com,🌍 国外媒体
  - DOMAIN-SUFFIX,hbo.com,🌍 国外媒体
  - DOMAIN-SUFFIX,hbomax.com,🌍 国外媒体
  - DOMAIN-SUFFIX,hbomaxcdn.com,🌍 国外媒体
  - DOMAIN-SUFFIX,hbogo.com,🌍 国外媒体
  - DOMAIN-SUFFIX,spotify.com,🌍 国外媒体
  - DOMAIN-SUFFIX,scdn.co,🌍 国外媒体
  - DOMAIN-SUFFIX,twitch.tv,🌍 国外媒体
  - DOMAIN-SUFFIX,twitchcdn.net,🌍 国外媒体
  - DOMAIN-SUFFIX,jtvnw.net,🌍 国外媒体
  - DOMAIN-SUFFIX,ttvnw.net,🌍 国外媒体
  - DOMAIN-SUFFIX,primevideo.com,🌍 国外媒体
  - DOMAIN-SUFFIX,amazonvideo.com,🌍 国外媒体
  - DOMAIN-SUFFIX,bbc.com,🌍 国外媒体
  - DOMAIN-SUFFIX,bbc.co.uk,🌍 国外媒体
  - DOMAIN-SUFFIX,bbci.co.uk,🌍 国外媒体
  - DOMAIN-SUFFIX,abema.tv,🌍 国外媒体
  - DOMAIN-SUFFIX,bahamut.com.tw,🌍 国外媒体
  - DOMAIN-SUFFIX,gamer.com.tw,🌍 国外媒体
  - DOMAIN-SUFFIX,niconico.jp,🌍 国外媒体
  - DOMAIN-SUFFIX,nicovideo.jp,🌍 国外媒体

  # ─── 代理域名 (GFW列表 + 常见需翻墙的) ───
  - RULE-SET,proxy,🔰 节点选择
  - RULE-SET,gfw,🔰 节点选择
  - RULE-SET,tld-not-cn,🔰 节点选择

  # ─── 国内域名 ───
  - RULE-SET,direct,🎯 全球直连

  # ─── GeoIP 兜底 ───
  - RULE-SET,cncidr,🎯 全球直连,no-resolve
  - GEOIP,LAN,🎯 全球直连,no-resolve
  - GEOIP,CN,🎯 全球直连,no-resolve

  # ─── 漏网之鱼 ───
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

    # 同步到 HTTP 下载目录（nginx 容器读这里）
    if [[ "${ENABLE_CLASH_HTTP:-true}" == "true" ]] && [[ -n "${CLASH_HTTP_TOKEN:-}" ]]; then
        local share_dir="${PROJECT_DIR}/share/${CLASH_HTTP_TOKEN}"
        mkdir -p "${share_dir}"
        cp "${out_file}" "${share_dir}/clash.yaml"
        chmod 644 "${share_dir}/clash.yaml"   # nginx 容器内 nobody 用户要能读
        chmod 755 "${share_dir}"
        chmod 755 "${PROJECT_DIR}/share"
        log_info "✓ 已同步到下载目录: share/${CLASH_HTTP_TOKEN}/clash.yaml"
    fi
}

main "$@"
