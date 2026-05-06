#!/usr/bin/env bash
# SSR Docker 一键部署主脚本
# 使用：sudo ./deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# ===== 颜色 =====
C_RED='\033[0;31m'
C_GRN='\033[0;32m'
C_YLW='\033[0;33m'
C_BLU='\033[0;34m'
C_BLD='\033[1m'
C_RST='\033[0m'

log_step() { echo -e "\n${C_BLU}${C_BLD}[STEP]${C_RST} ${C_BLD}$*${C_RST}"; }
log_info() { echo -e "${C_GRN}[INFO]${C_RST} $*"; }
log_warn() { echo -e "${C_YLW}[WARN]${C_RST} $*"; }
log_err()  { echo -e "${C_RED}[ERR ]${C_RST} $*" >&2; }

# ===== 加载配置 =====
load_env() {
    if [[ ! -f .env ]]; then
        log_info "未找到 .env，从 .env.example 创建"
        cp .env.example .env
    fi
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
}

# ===== 前置检查 =====
check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        log_err "本脚本需要 root 权限运行（用于内核/sysctl/Docker 操作）"
        log_err "请用：sudo $0"
        exit 1
    fi
}

check_kernel_arch() {
    local arch
    arch=$(uname -m)
    if [[ "${arch}" != "x86_64" && "${arch}" != "aarch64" ]]; then
        log_warn "未测试的架构 ${arch}，可能部分功能不可用"
    fi
}

# ===== 安装 Docker =====
install_docker() {
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker 已安装：$(docker --version)"
    else
        log_info "正在安装 Docker（使用官方 get.docker.com 脚本）..."
        if ! curl -fsSL https://get.docker.com | sh; then
            log_err "Docker 安装失败"
            exit 1
        fi
    fi

    # 启动 Docker
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable docker >/dev/null 2>&1 || true
        systemctl start docker >/dev/null 2>&1 || true
    elif command -v service >/dev/null 2>&1; then
        service docker start >/dev/null 2>&1 || true
    fi

    # 验证 Docker 可用
    if ! docker info >/dev/null 2>&1; then
        log_err "Docker daemon 未运行"
        exit 1
    fi

    # 确认 docker compose 子命令可用
    if docker compose version >/dev/null 2>&1; then
        DC="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DC="docker-compose"
    else
        log_info "安装 docker compose 插件..."
        # shellcheck source=scripts/detect-os.sh
        source "${SCRIPT_DIR}/scripts/detect-os.sh"
        run_detection
        case "${OS_FAMILY}" in
            debian)
                apt-get update -qq
                apt-get install -y docker-compose-plugin || apt-get install -y docker-compose
                ;;
            rhel)
                ${PKG_MGR} install -y docker-compose-plugin || ${PKG_MGR} install -y docker-compose
                ;;
            arch)
                pacman -S --noconfirm docker-compose
                ;;
            alpine)
                apk add --no-cache docker-compose
                ;;
        esac
        if docker compose version >/dev/null 2>&1; then
            DC="docker compose"
        else
            DC="docker-compose"
        fi
    fi
    log_info "compose 命令: ${DC}"
    export DC
}

# ===== 安装通用依赖 =====
install_deps() {
    # shellcheck source=scripts/detect-os.sh
    source "${SCRIPT_DIR}/scripts/detect-os.sh"
    run_detection

    local pkgs=(curl ca-certificates)
    [[ "${ENABLE_QRCODE:-true}" == "true" ]] && pkgs+=(qrencode)

    log_info "安装依赖: ${pkgs[*]}"

    case "${OS_FAMILY}" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y "${pkgs[@]}"
            ;;
        rhel)
            ${PKG_MGR} install -y epel-release 2>/dev/null || true
            ${PKG_MGR} install -y "${pkgs[@]}"
            ;;
        arch)
            pacman -Sy --noconfirm "${pkgs[@]}"
            ;;
        alpine)
            apk add --no-cache "${pkgs[@]}"
            ;;
        suse)
            zypper install -y "${pkgs[@]}"
            ;;
        *)
            log_warn "未识别的发行版 ${OS_ID}，跳过依赖安装"
            log_warn "请手动确认已安装：${pkgs[*]}"
            ;;
    esac
}

# ===== 写 SSR 配置 =====
sync_config() {
    log_info "同步 SSR 配置（端口=${SSR_PORT} 协议=${SSR_PROTOCOL} 混淆=${SSR_OBFS}）"
    cat > config/config.json <<EOF
{
    "server": "0.0.0.0",
    "server_ipv6": "::",
    "server_port": ${SSR_PORT},
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "${SSR_PASSWORD}",
    "method": "${SSR_METHOD}",
    "protocol": "${SSR_PROTOCOL}",
    "protocol_param": "",
    "obfs": "${SSR_OBFS}",
    "obfs_param": "${SSR_OBFS_PARAM}",
    "speed_limit_per_con": 0,
    "speed_limit_per_user": 0,
    "additional_ports": {},
    "additional_ports_only": false,
    "timeout": 120,
    "udp_timeout": 60,
    "dns_ipv6": false,
    "connect_verbose_info": 0,
    "redirect": "",
    "fast_open": true,
    "workers": 1
}
EOF
}

# ===== 防火墙 =====
configure_firewall() {
    if [[ "${ENABLE_FIREWALL:-true}" != "true" ]]; then
        log_warn "ENABLE_FIREWALL=false，跳过防火墙配置"
        return
    fi
    local port="${SSR_PORT:-17777}"
    log_info "开放防火墙端口 ${port}/tcp 与 ${port}/udp"

    # ufw
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow "${port}/tcp" >/dev/null || true
        ufw allow "${port}/udp" >/dev/null || true
        log_info "✓ ufw 规则已添加"
        return
    fi

    # firewalld
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null
        firewall-cmd --permanent --add-port="${port}/udp" >/dev/null
        firewall-cmd --reload >/dev/null
        log_info "✓ firewalld 规则已添加"
        return
    fi

    # iptables 直接
    if command -v iptables >/dev/null 2>&1; then
        iptables -C INPUT -p tcp --dport "${port}" -j ACCEPT 2>/dev/null \
            || iptables -I INPUT -p tcp --dport "${port}" -j ACCEPT
        iptables -C INPUT -p udp --dport "${port}" -j ACCEPT 2>/dev/null \
            || iptables -I INPUT -p udp --dport "${port}" -j ACCEPT

        # 持久化（debian: iptables-persistent；rhel: iptables-services）
        if command -v netfilter-persistent >/dev/null 2>&1; then
            netfilter-persistent save >/dev/null 2>&1 || true
        elif command -v iptables-save >/dev/null 2>&1 && [[ -d /etc/sysconfig ]]; then
            iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
        fi
        log_info "✓ iptables 规则已添加"
        return
    fi

    log_warn "未检测到防火墙工具，跳过"
}

# ===== fail2ban（可选）=====
install_fail2ban() {
    if [[ "${ENABLE_FAIL2BAN:-false}" != "true" ]]; then
        return
    fi

    if command -v fail2ban-client >/dev/null 2>&1; then
        log_info "fail2ban 已安装"
        return
    fi

    log_info "安装 fail2ban（保护 SSH）..."
    case "${OS_FAMILY}" in
        debian) apt-get install -y fail2ban ;;
        rhel) ${PKG_MGR} install -y fail2ban ;;
        arch) pacman -Sy --noconfirm fail2ban ;;
        alpine) apk add --no-cache fail2ban ;;
        *) log_warn "fail2ban 在 ${OS_ID} 上需手动安装"; return ;;
    esac

    cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
port    = ssh
maxretry = 5
findtime = 600
bantime  = 86400
EOF

    systemctl enable fail2ban >/dev/null 2>&1 || true
    systemctl restart fail2ban >/dev/null 2>&1 || true
    log_info "✓ fail2ban 已启用"
}

# ===== 启动容器 =====
start_container() {
    log_info "构建并启动 SSR 容器..."
    ${DC} build --pull
    ${DC} up -d

    # 等待健康检查
    log_info "等待容器启动..."
    local i=0
    while [[ ${i} -lt 30 ]]; do
        if ${DC} ps --format json 2>/dev/null | grep -q '"State":"running"' \
           || ${DC} ps 2>/dev/null | grep -qE "(Up|running)"; then
            break
        fi
        sleep 1
        i=$((i + 1))
    done

    # 验证端口
    local port="${SSR_PORT:-17777}"
    sleep 2
    if command -v ss >/dev/null 2>&1; then
        if ss -lnt | grep -q ":${port} "; then
            log_info "✓ 端口 ${port} 已监听"
        else
            log_warn "端口 ${port} 未监听，请检查日志：${DC} logs"
        fi
    fi
}

# ===== 显示部署信息 =====
show_info() {
    bash "${SCRIPT_DIR}/scripts/generate-qr.sh"

    if [[ -f /var/run/.ssr-bbrplus-need-reboot ]]; then
        echo
        echo -e "${C_YLW}${C_BLD}═════════════════════════════════════════════════════════${C_RST}"
        echo -e "${C_YLW}${C_BLD}  ⚠ BBR Plus 内核已安装，建议重启服务器以生效${C_RST}"
        echo -e "${C_YLW}${C_BLD}     重启命令：reboot${C_RST}"
        echo -e "${C_YLW}${C_BLD}═════════════════════════════════════════════════════════${C_RST}"
    fi
}

# ===== 主流程 =====
banner() {
    cat <<'EOF'

  ╔════════════════════════════════════════════════════╗
  ║   SSR Docker 一键部署                                ║
  ║   - 协议: auth_chain_a + tls1.2_ticket_auth          ║
  ║   - 加速: BBR Plus (UJX6N/bbrplus-5.15)              ║
  ║   - 网络: host 模式 + sysctl 调优                    ║
  ╚════════════════════════════════════════════════════╝

EOF
}

main() {
    banner
    check_root
    check_kernel_arch

    log_step "1/8 加载配置"
    load_env

    log_step "2/8 安装系统依赖"
    install_deps

    log_step "3/8 安装/启动 Docker"
    install_docker

    log_step "4/8 网络参数调优"
    bash "${SCRIPT_DIR}/scripts/tune-sysctl.sh" || log_warn "sysctl 调优失败，继续"

    log_step "5/8 配置 BBR/BBR Plus 加速"
    bash "${SCRIPT_DIR}/scripts/install-bbr-plus.sh" || log_warn "BBR 配置失败，继续"

    log_step "6/8 配置防火墙"
    configure_firewall

    log_step "7/8 同步 SSR 配置 + 启动容器"
    sync_config
    start_container

    log_step "8/8 附加项 + 输出信息"
    install_fail2ban
    show_info
}

main "$@"
