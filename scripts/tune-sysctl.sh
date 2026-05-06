#!/usr/bin/env bash
# 网络与系统参数调优（针对代理服务的高并发 + 大流量场景）
# 注意：仅在宿主机执行，容器内 sysctl 由 docker-compose 负责

set -euo pipefail

C_GRN='\033[0;32m'
C_YLW='\033[0;33m'
C_RST='\033[0m'

log_info() { echo -e "${C_GRN}[SYSCTL]${C_RST} $*"; }
log_warn() { echo -e "${C_YLW}[SYSCTL]${C_RST} $*"; }

CONF_FILE="/etc/sysctl.d/99-ssr-tune.conf"

apply_sysctl() {
    log_info "写入 ${CONF_FILE}"

    cat > "${CONF_FILE}" <<'EOF'
# === SSR Docker 部署：网络与系统调优 ===
# 由 ssr-docker-deploy 自动生成

# --- TCP 性能 ---
# TCP Fast Open：双向开启（客户端+服务端），降低首次握手延迟
net.ipv4.tcp_fastopen = 3

# 长连接空闲后不重新慢启动（适合长连接代理）
net.ipv4.tcp_slow_start_after_idle = 0

# MTU 探测：避免 GFW/中间设备造成的 MTU 黑洞
net.ipv4.tcp_mtu_probing = 1

# 降低尾部数据包延迟（Nagle 优化）
net.ipv4.tcp_notsent_lowat = 16384

# SACK + DSACK：丢包恢复更高效
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1

# 时间戳：精确 RTT，注意可能暴露 uptime（可按需关闭）
net.ipv4.tcp_timestamps = 1

# --- 缓冲区（64MB 上限，适合 1Gbps 长肥管道）---
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# --- 连接队列 ---
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_syncookies = 1

# --- 连接回收（防 TIME_WAIT 堆积）---
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 60000

# --- Keepalive ---
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# --- 端口范围（高并发短连接需要）---
net.ipv4.ip_local_port_range = 10000 65535

# --- 转发（容器/host 模式都需要）---
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# --- IPv6 ---
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0

# --- 文件句柄 ---
fs.file-max = 1048576
fs.nr_open = 1048576
EOF

    # 应用
    if sysctl -p "${CONF_FILE}" >/dev/null 2>&1; then
        log_info "✓ sysctl 参数已应用"
    else
        log_warn "部分 sysctl 参数应用失败（多数情况下是不可用项目，可忽略）"
        sysctl -p "${CONF_FILE}" 2>&1 | grep -E "error|cannot" || true
    fi
}

apply_limits() {
    log_info "调整文件句柄上限"
    local limits_conf="/etc/security/limits.d/99-ssr.conf"
    cat > "${limits_conf}" <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
* soft nproc  65535
* hard nproc  65535
root soft nofile 1048576
root hard nofile 1048576
EOF

    # systemd 服务的句柄上限
    if [[ -d /etc/systemd/system.conf.d ]] || mkdir -p /etc/systemd/system.conf.d 2>/dev/null; then
        cat > /etc/systemd/system.conf.d/99-ssr.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65535
EOF
    fi
}

main() {
    if [[ "${ENABLE_SYSCTL_TUNE:-true}" != "true" ]]; then
        log_warn "ENABLE_SYSCTL_TUNE=false，跳过调优"
        return 0
    fi

    apply_sysctl
    apply_limits
    log_info "✓ 网络调优完成"
}

main "$@"
