#!/usr/bin/env bash
# 生成 SSR 链接和二维码
# SSR URL 格式: ssr://base64(server:port:protocol:method:obfs:base64pass/?obfsparam=base64&protoparam=base64&remarks=base64&group=base64)

set -euo pipefail

C_GRN=$'\e[0;32m'
C_CYN=$'\e[0;36m'
C_YLW=$'\e[0;33m'
C_RST=$'\e[0m'

# Base64 URL-safe encode（SSR 规范）
# 标准 base64 → URL-safe: + → -, / → _, 去掉末尾的 =
b64url() {
    printf '%s' "$1" | base64 -w 0 | tr '+/' '-_' | tr -d '='
}

generate_ssr_url() {
    local server="$1"
    local port="$2"
    local protocol="$3"
    local method="$4"
    local obfs="$5"
    local password="$6"
    local obfs_param="${7:-}"
    local proto_param="${8:-}"
    local remark="${9:-SSR}"
    local group="${10:-default}"

    local pass_b64 obfs_b64 proto_b64 remark_b64 group_b64
    pass_b64=$(b64url "${password}")
    obfs_b64=$(b64url "${obfs_param}")
    proto_b64=$(b64url "${proto_param}")
    remark_b64=$(b64url "${remark}")
    group_b64=$(b64url "${group}")

    local main_part="${server}:${port}:${protocol}:${method}:${obfs}:${pass_b64}"
    local query="/?obfsparam=${obfs_b64}&protoparam=${proto_b64}&remarks=${remark_b64}&group=${group_b64}"
    local full_url="${main_part}${query}"

    local final
    final=$(b64url "${full_url}")
    echo "ssr://${final}"
}

# 自动获取公网 IP（多源容错）
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

print_qr() {
    local url="$1"
    if command -v qrencode >/dev/null 2>&1; then
        echo
        echo -e "${C_CYN}━━━━━━━━━━━━━━━━━ 二维码（手机扫描导入）━━━━━━━━━━━━━━━━━${C_RST}"
        qrencode -t ansiutf8 -o - "${url}"

        # 同时保存 PNG 文件
        local png_path="./ssr-qrcode.png"
        qrencode -t PNG -s 8 -o "${png_path}" "${url}" 2>/dev/null && \
            echo -e "${C_GRN}✓ PNG 已保存: ${png_path}${C_RST}"
    else
        echo -e "${C_YLW}⚠ 未安装 qrencode，跳过二维码生成${C_RST}"
        echo -e "${C_YLW}  请手动安装：apt install qrencode 或 yum install qrencode${C_RST}"
    fi
}

main() {
    # 加载 .env（如果存在）
    if [[ -f .env ]]; then
        set -a
        # shellcheck disable=SC1091
        source .env
        set +a
    fi

    local server="${SSR_SERVER_IP:-}"
    if [[ -z "${server}" ]]; then
        echo "正在检测公网 IP..."
        server=$(detect_public_ip) || {
            echo "无法自动获取公网 IP，请在 .env 中设置 SSR_SERVER_IP" >&2
            exit 1
        }
    fi

    local port="${SSR_PORT:-17777}"
    local password="${SSR_PASSWORD:-gugugu}"
    local method="${SSR_METHOD:-chacha20-ietf}"
    local protocol="${SSR_PROTOCOL:-auth_chain_a}"
    local obfs="${SSR_OBFS:-tls1.2_ticket_auth}"
    local obfs_param="${SSR_OBFS_PARAM:-cloud.tencent.com}"
    local remark="${SSR_REMARK:-My-SSR-Node}"

    local url
    url=$(generate_ssr_url \
        "${server}" "${port}" "${protocol}" "${method}" "${obfs}" \
        "${password}" "${obfs_param}" "" "${remark}" "ssr-docker")

    cat <<EOF

${C_GRN}╔══════════════════════════════════════════════════════════╗${C_RST}
${C_GRN}║              SSR 服务部署成功                              ║${C_RST}
${C_GRN}╚══════════════════════════════════════════════════════════╝${C_RST}

  服务器地址 :  ${C_CYN}${server}${C_RST}
  端口       :  ${C_CYN}${port}${C_RST}
  密码       :  ${C_CYN}${password}${C_RST}
  加密方式   :  ${C_CYN}${method}${C_RST}
  协议       :  ${C_CYN}${protocol}${C_RST}
  混淆       :  ${C_CYN}${obfs}${C_RST}
  混淆参数   :  ${C_CYN}${obfs_param}${C_RST}
  备注       :  ${C_CYN}${remark}${C_RST}

${C_CYN}━━━━━━━━━━━━━━━━━━━━━━━ SSR 链接 ━━━━━━━━━━━━━━━━━━━━━━━${C_RST}
${url}

EOF

    if [[ "${ENABLE_QRCODE:-true}" == "true" ]]; then
        print_qr "${url}"
    fi

    # 保存到文件供后续查看
    {
        echo "服务器: ${server}"
        echo "端口:   ${port}"
        echo "密码:   ${password}"
        echo "加密:   ${method}"
        echo "协议:   ${protocol}"
        echo "混淆:   ${obfs}"
        echo "混淆参数: ${obfs_param}"
        echo "备注:   ${remark}"
        echo ""
        echo "链接: ${url}"
    } > ./ssr-info.txt

    echo
    echo -e "${C_GRN}✓ 配置信息已保存: ./ssr-info.txt${C_RST}"
}

main "$@"
