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
    local name="$1"
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker 未安装"
        return
    fi
    if ! docker info >/dev/null 2>&1; then
        echo "Docker 服务未运行（或当前用户无权限）"
        return
    fi

    local cid status health policy
    cid=$(docker ps -a --filter "name=^${name}$" --format "{{.ID}}" 2>/dev/null | head -1)
    if [[ -z "${cid}" ]]; then
        echo "未运行 (容器不存在)"
        return
    fi
    status=$(docker inspect -f '{{.State.Status}}' "${cid}" 2>/dev/null || echo "unknown")
    health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "${cid}" 2>/dev/null || echo "n/a")
    policy=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "${cid}" 2>/dev/null || echo "unknown")
    echo "${status} (健康: ${health}, 重启策略: ${policy})"
}

docker_autostart_status() {
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "n/a (非 systemd)"
        return
    fi
    if systemctl is-enabled docker >/dev/null 2>&1; then
        echo "已启用 (服务器重启后自动启动)"
    else
        echo "未启用 (服务器重启后需手动: systemctl start docker)"
    fi
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
    print_section "Clash 配置文件 - 下载方式"
    if [[ ! -f clash.yaml ]]; then
        echo -e "  ${C_YLW}[!] clash.yaml 不存在，请先运行：${C_RST}"
        echo "      bash scripts/generate-clash.sh"
    else
        local size abs_path
        size=$(du -h clash.yaml | cut -f1)
        abs_path=$(readlink -f clash.yaml)

        # ───── 方式 1: HTTP URL（推荐，配合 Clash 的 "Download from URL"）─────
        local clash_url=""
        if [[ "${ENABLE_CLASH_HTTP:-true}" == "true" ]] && [[ -n "${CLASH_HTTP_TOKEN:-}" ]]; then
            local http_port="${CLASH_HTTP_PORT:-18888}"
            clash_url="http://${server}:${http_port}/${CLASH_HTTP_TOKEN}/clash.yaml"

            echo
            echo -e "  ${C_BLD}${C_GRN}方式 1：URL 下载（推荐，对应 Clash 的 \"Download from URL\"）${C_RST}"
            echo
            echo -e "    ${C_CYN}${clash_url}${C_RST}"
            echo

            # URL 二维码（手机端方便）
            if [[ "${ENABLE_QRCODE:-true}" == "true" ]] && command -v qrencode >/dev/null 2>&1; then
                echo -e "    ${C_DIM}手机扫码（粘贴到 Clash for Android / 小猫咪）：${C_RST}"
                qrencode -t ansiutf8 -o - "${clash_url}" | sed 's/^/    /'
                qrencode -t PNG -s 6 -o "./clash-url-qrcode.png" "${clash_url}" 2>/dev/null && \
                    echo -e "    ${C_GRN}✓ URL 二维码 PNG: ./clash-url-qrcode.png${C_RST}"
            fi

            # 检测 nginx 容器是否在跑
            if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
                if docker ps --filter "name=^ssr-clash-http$" --format "{{.Names}}" 2>/dev/null | grep -q "ssr-clash-http"; then
                    echo -e "    ${C_GRN}✓ Clash HTTP 服务运行中${C_RST}"
                else
                    echo -e "    ${C_YLW}⚠ Clash HTTP 服务未运行，URL 不可访问${C_RST}"
                    echo -e "    ${C_YLW}  启动：docker compose --profile clash-http up -d${C_RST}"
                fi
            fi
        else
            echo
            echo -e "  ${C_YLW}方式 1：URL 下载 (已禁用)${C_RST}"
            echo -e "  ${C_DIM}  在 .env 设置 ENABLE_CLASH_HTTP=true 并重新部署${C_RST}"
        fi

        # ───── 方式 2: SCP 下载 ─────
        echo
        echo -e "  ${C_BLD}方式 2：SCP 下载到本地电脑${C_RST}"
        echo -e "    ${C_DIM}本地路径: ${abs_path} (${size})${C_RST}"
        echo
        echo -e "    ${C_GRN}# Linux / macOS / Windows PowerShell：${C_RST}"
        echo "    scp root@${server}:${abs_path} ./clash.yaml"

        # ───── 方式 3: 直接复制 ─────
        echo
        echo -e "  ${C_BLD}方式 3：在服务器终端 cat 复制全部内容${C_RST}"
        echo "    cat ${abs_path}"
    fi

    # ===== 配置文件位置（其它）=====
    print_section "本地相关文件"
    [[ -f ssr-info.txt ]]    && print_kv "节点摘要"  "$(readlink -f ssr-info.txt)"
    [[ -f ssr-qrcode.png ]]  && print_kv "二维码 PNG" "$(readlink -f ssr-qrcode.png)"
    [[ -f clash.yaml ]]      && print_kv "Clash YAML" "$(readlink -f clash.yaml)"
    [[ -f .env ]]            && print_kv "环境配置"   "$(readlink -f .env)"

    # ===== 服务状态 =====
    print_section "运行状态"
    print_kv "SSR 容器" "$(container_status ssr-server)"
    if [[ "${ENABLE_CLASH_HTTP:-true}" == "true" ]]; then
        print_kv "Clash HTTP" "$(container_status ssr-clash-http)"
    fi
    print_kv "Docker 自启" "$(docker_autostart_status)"
    print_kv "BBR 状态" "$(bbr_status)"
    if command -v ss >/dev/null 2>&1; then
        if ss -lnt 2>/dev/null | grep -q ":${port} "; then
            print_kv "SSR 端口 ${port}" "${C_GRN}已监听${C_RST}"
        else
            print_kv "SSR 端口 ${port}" "${C_RED}未监听${C_RST}"
        fi
        if [[ "${ENABLE_CLASH_HTTP:-true}" == "true" ]]; then
            local hp="${CLASH_HTTP_PORT:-18888}"
            if ss -lnt 2>/dev/null | grep -q ":${hp} "; then
                print_kv "HTTP 端口 ${hp}" "${C_GRN}已监听${C_RST}"
            else
                print_kv "HTTP 端口 ${hp}" "${C_RED}未监听${C_RST}"
            fi
        fi
    fi

    # ===== 客户端使用提示 =====
    print_section "客户端导入"
    cat <<EOF

  ${C_BLD}SSR 客户端${C_RST} (Windows/macOS/Android/iOS):
    ${C_GRN}方式1：${C_RST} 复制上面的 ssr:// 链接，客户端选 "从剪贴板导入"
    ${C_GRN}方式2：${C_RST} 用客户端"扫描二维码"功能扫上面的终端二维码

  ${C_BLD}Clash 客户端${C_RST} (Clash for Windows/ClashX/Clash Verge/小猫咪):
    ${C_GRN}方式1（推荐）：${C_RST} 复制上面的 URL，客户端 "Profiles/配置" → "Download"
            在 URL 输入框粘贴，确认即可（手机端用 URL 二维码扫码）
    ${C_GRN}方式2：${C_RST} 用 scp 把 clash.yaml 下载到本地，客户端 "导入文件"
    ${C_GRN}方式3：${C_RST} 在终端 \`cat clash.yaml\` 复制全部内容到客户端

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
            if [[ "${ENABLE_CLASH_HTTP:-true}" == "true" ]] && [[ -n "${CLASH_HTTP_TOKEN:-}" ]]; then
                local hp="${CLASH_HTTP_PORT:-18888}"
                echo "URL (推荐):  http://${server}:${hp}/${CLASH_HTTP_TOKEN}/clash.yaml"
            fi
            echo "本地路径:    $(readlink -f clash.yaml)"
            echo "SCP 下载:    scp root@${server}:$(readlink -f clash.yaml) ./clash.yaml"
        else
            echo "未生成（运行 bash scripts/generate-clash.sh）"
        fi
    } > ssr-info.txt
    chmod 600 ssr-info.txt 2>/dev/null || true
}

main "$@"
