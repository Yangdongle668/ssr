#!/usr/bin/env bash
# 一键查询接入点信息
# 使用：bash info.sh
#
# 输出：
#   - SSR 节点详细参数
#   - SSR 链接（含终端二维码）
#   - Clash 配置文件路径 + SCP 下载命令
#   - 容器运行状态

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# ===== 颜色（用 ANSI-C 引用，cat 也能正确显示） =====
C_GRN=$'\e[0;32m'
C_CYN=$'\e[0;36m'
C_YLW=$'\e[0;33m'
C_RED=$'\e[0;31m'
C_BLU=$'\e[0;34m'
C_BLD=$'\e[1m'
C_DIM=$'\e[2m'
C_RST=$'\e[0m'

# ===== 辅助函数 =====
b64url() {
    printf '%s' "$1" | base64 -w 0 | tr '+/' '-_' | tr -d '='
}

generate_ssr_url() {
    local server="$1" port="$2" protocol="$3" method="$4" obfs="$5"
    local password="$6" obfs_param="${7:-}" proto_param="${8:-}"
    local remark="${9:-SSR}" group="${10:-ssr-docker}"

    local pass_b64 obfs_b64 proto_b64 remark_b64 group_b64
    pass_b64=$(b64url "${password}")
    obfs_b64=$(b64url "${obfs_param}")
    proto_b64=$(b64url "${proto_param}")
    remark_b64=$(b64url "${remark}")
    group_b64=$(b64url "${group}")

    local main_part="${server}:${port}:${protocol}:${method}:${obfs}:${pass_b64}"
    local query="/?obfsparam=${obfs_b64}&protoparam=${proto_b64}&remarks=${remark_b64}&group=${group_b64}"
    local full="${main_part}${query}"
    echo "ssr://$(b64url "${full}")"
}

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

container_status() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker 未安装"
        return
    fi
    if ! docker info >/dev/null 2>&1; then
        echo "Docker 服务未运行（或当前用户无权限）"
        return
    fi

    local cid status health
    cid=$(docker ps -a --filter "name=^ssr-server$" --format "{{.ID}}" 2>/dev/null | head -1)
    if [[ -z "${cid}" ]]; then
        echo "未运行 (容器不存在)"
        return
    fi
    status=$(docker inspect -f '{{.State.Status}}' "${cid}" 2>/dev/null || echo "unknown")
    health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "${cid}" 2>/dev/null || echo "n/a")
    echo "${status} (健康: ${health})"
}

bbr_status() {
    local cc avail
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    avail=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")
    echo "${cc} (可用: ${avail})"
}

print_section() {
    echo
    echo -e "${C_BLU}${C_BLD}═══════════ $1 ═══════════${C_RST}"
}

print_kv() {
    printf "  ${C_DIM}%-12s${C_RST} ${C_CYN}%s${C_RST}\n" "$1" "$2"
}

# ===== 主流程 =====
main() {
    # 加载配置
    if [[ ! -f .env ]]; then
        if [[ -f .env.example ]]; then
            echo -e "${C_YLW}[!] 未找到 .env，从 .env.example 复制${C_RST}"
            cp .env.example .env
        else
            echo -e "${C_RED}[!] 未找到 .env 和 .env.example，无法读取配置${C_RST}" >&2
            exit 1
        fi
    fi

    set -a
    # shellcheck disable=SC1091
    source .env
    set +a

    # 解析 IP
    local server="${SSR_SERVER_IP:-}"
    if [[ -z "${server}" ]]; then
        echo -e "${C_DIM}正在检测公网 IP...${C_RST}"
        server=$(detect_public_ip) || {
            server="<未知>"
            echo -e "${C_YLW}[!] 公网 IP 检测失败，请在 .env 设置 SSR_SERVER_IP${C_RST}"
        }
    fi

    local port="${SSR_PORT:-17777}"
    local password="${SSR_PASSWORD:-gugugu}"
    local method="${SSR_METHOD:-chacha20-ietf}"
    local protocol="${SSR_PROTOCOL:-auth_chain_a}"
    local obfs="${SSR_OBFS:-tls1.2_ticket_auth}"
    local obfs_param="${SSR_OBFS_PARAM:-cloud.tencent.com}"
    local remark="${SSR_REMARK:-My-SSR-Node}"

    # ===== 标题 =====
    cat <<EOF

${C_GRN}${C_BLD}╔══════════════════════════════════════════════════════════╗
║              SSR 接入点信息查询                            ║
╚══════════════════════════════════════════════════════════╝${C_RST}
EOF

    # ===== 节点信息 =====
    print_section "节点参数"
    print_kv "服务器" "${server}"
    print_kv "端口" "${port}"
    print_kv "密码" "${password}"
    print_kv "加密方式" "${method}     ${C_DIM}(固定)${C_RST}"
    print_kv "协议" "${protocol}      ${C_DIM}(固定)${C_RST}"
    print_kv "混淆" "${obfs}  ${C_DIM}(固定)${C_RST}"
    print_kv "混淆参数" "${obfs_param}"
    print_kv "备注" "${remark}"

    # ===== SSR 链接 =====
    local ssr_url
    ssr_url=$(generate_ssr_url \
        "${server}" "${port}" "${protocol}" "${method}" "${obfs}" \
        "${password}" "${obfs_param}" "" "${remark}" "ssr-docker")

    print_section "SSR 链接（手机/桌面 SSR 客户端）"
    echo
    echo "  ${ssr_url}"
    echo

    if [[ "${ENABLE_QRCODE:-true}" == "true" ]] && command -v qrencode >/dev/null 2>&1; then
        echo -e "  ${C_DIM}扫描二维码导入：${C_RST}"
        qrencode -t ansiutf8 -o - "${ssr_url}" | sed 's/^/  /'
        # PNG 副本
        qrencode -t PNG -s 8 -o "./ssr-qrcode.png" "${ssr_url}" 2>/dev/null && \
            echo -e "  ${C_GRN}✓ 二维码 PNG: ./ssr-qrcode.png${C_RST}"
    fi

    # ===== Clash 配置文件 =====
    print_section "Clash 配置文件下载"
    if [[ -f clash.yaml ]]; then
        local size
        size=$(du -h clash.yaml | cut -f1)
        local abs_path
        abs_path=$(readlink -f clash.yaml)
        print_kv "本地路径" "${abs_path}"
        print_kv "文件大小" "${size}"

        echo
        echo -e "  ${C_BLD}从本机下载到客户端电脑（在客户端运行）：${C_RST}"
        echo
        echo -e "  ${C_GRN}# Linux / macOS：${C_RST}"
        echo "  scp root@${server}:${abs_path} ./clash.yaml"
        echo
        echo -e "  ${C_GRN}# Windows (PowerShell)：${C_RST}"
        echo "  scp root@${server}:${abs_path} clash.yaml"
        echo
        echo -e "  ${C_GRN}# 也可以直接 cat 复制内容：${C_RST}"
        echo "  cat ${abs_path}"
    else
        echo -e "  ${C_YLW}[!] clash.yaml 不存在，请先运行：${C_RST}"
        echo "      bash scripts/generate-clash.sh"
    fi

    # ===== 配置文件位置（其它）=====
    print_section "本地相关文件"
    [[ -f ssr-info.txt ]]    && print_kv "节点摘要"  "$(readlink -f ssr-info.txt)"
    [[ -f ssr-qrcode.png ]]  && print_kv "二维码 PNG" "$(readlink -f ssr-qrcode.png)"
    [[ -f clash.yaml ]]      && print_kv "Clash YAML" "$(readlink -f clash.yaml)"
    [[ -f .env ]]            && print_kv "环境配置"   "$(readlink -f .env)"

    # ===== 服务状态 =====
    print_section "运行状态"
    print_kv "SSR 容器" "$(container_status)"
    print_kv "BBR 状态" "$(bbr_status)"
    if command -v ss >/dev/null 2>&1; then
        if ss -lnt 2>/dev/null | grep -q ":${port} "; then
            print_kv "端口 ${port}" "${C_GRN}已监听${C_RST}"
        else
            print_kv "端口 ${port}" "${C_RED}未监听${C_RST}"
        fi
    fi

    # ===== 客户端使用提示 =====
    print_section "客户端导入"
    cat <<EOF

  ${C_BLD}SSR 客户端${C_RST} (Windows/macOS/Android/iOS):
    ${C_GRN}方式1：${C_RST} 复制上面的 ssr:// 链接，客户端选 "从剪贴板导入"
    ${C_GRN}方式2：${C_RST} 用客户端"扫描二维码"功能扫上面的终端二维码

  ${C_BLD}Clash 客户端${C_RST} (Clash for Windows/ClashX/Clash Verge/小猫咪):
    ${C_GRN}方式1：${C_RST} 用上面的 scp 命令把 clash.yaml 下载到本地
            然后在客户端 "Profiles/配置" 里 "导入文件"
    ${C_GRN}方式2：${C_RST} 在终端 \`cat clash.yaml\` 复制全部内容
            客户端选 "导入" → "从剪贴板"（部分客户端不支持）

  ${C_BLD}修改配置（端口/密码等）${C_RST}:
    ${C_GRN}sudo bash modify.sh${C_RST}              # 交互式修改
    ${C_GRN}sudo bash modify.sh --port 18888${C_RST} # 直接改端口
    ${C_GRN}sudo bash modify.sh --help${C_RST}       # 查看全部选项

EOF

    # 保存节点摘要到 ssr-info.txt（无颜色，可直接拷贝）
    {
        echo "═══════════ SSR 节点信息 ═══════════"
        echo "服务器:   ${server}"
        echo "端口:     ${port}"
        echo "密码:     ${password}"
        echo "加密方式: ${method}     (固定)"
        echo "协议:     ${protocol}      (固定)"
        echo "混淆:     ${obfs}  (固定)"
        echo "混淆参数: ${obfs_param}"
        echo "备注:     ${remark}"
        echo
        echo "═══════════ SSR 链接 ═══════════"
        echo "${ssr_url}"
        echo
        echo "═══════════ Clash 配置文件 ═══════════"
        if [[ -f clash.yaml ]]; then
            echo "本地路径: $(readlink -f clash.yaml)"
            echo "下载命令: scp root@${server}:$(readlink -f clash.yaml) ./clash.yaml"
        else
            echo "未生成（运行 bash scripts/generate-clash.sh）"
        fi
    } > ssr-info.txt
    chmod 600 ssr-info.txt 2>/dev/null || true
}

main "$@"
