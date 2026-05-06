#!/usr/bin/env bash
# 检测发行版与虚拟化类型，导出全局变量供其他脚本使用
# 输出：OS_FAMILY OS_ID OS_VERSION OS_CODENAME ARCH PKG_MGR VIRT_TYPE KERNEL_VERSION

set -euo pipefail

detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_CODENAME="${VERSION_CODENAME:-}"
    elif [[ -f /etc/redhat-release ]]; then
        OS_ID="rhel"
        OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
        OS_CODENAME=""
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
        OS_CODENAME=""
    fi

    case "${OS_ID}" in
        debian|ubuntu|raspbian|kali|deepin)
            OS_FAMILY="debian"
            PKG_MGR="apt"
            ;;
        centos|rhel|fedora|almalinux|rocky|ol)
            OS_FAMILY="rhel"
            if command -v dnf >/dev/null 2>&1; then
                PKG_MGR="dnf"
            else
                PKG_MGR="yum"
            fi
            ;;
        arch|manjaro|endeavouros)
            OS_FAMILY="arch"
            PKG_MGR="pacman"
            ;;
        opensuse*|sles)
            OS_FAMILY="suse"
            PKG_MGR="zypper"
            ;;
        alpine)
            OS_FAMILY="alpine"
            PKG_MGR="apk"
            ;;
        *)
            OS_FAMILY="unknown"
            PKG_MGR="unknown"
            ;;
    esac
}

detect_arch() {
    local m
    m=$(uname -m)
    case "${m}" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l|armhf) ARCH="armhf" ;;
        *) ARCH="${m}" ;;
    esac
}

detect_virt() {
    # 优先用 systemd-detect-virt(最可靠)
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
    elif command -v virt-what >/dev/null 2>&1; then
        VIRT_TYPE=$(virt-what 2>/dev/null | head -1 || echo "none")
        [[ -z "${VIRT_TYPE}" ]] && VIRT_TYPE="none"
    else
        VIRT_TYPE="unknown"
        # 简单兜底检测
        if [[ -d /proc/vz ]] && [[ ! -d /proc/bc ]]; then
            VIRT_TYPE="openvz"
        elif grep -qa container=lxc /proc/1/environ 2>/dev/null; then
            VIRT_TYPE="lxc"
        elif [[ -f /.dockerenv ]]; then
            VIRT_TYPE="docker"
        elif [[ -r /sys/hypervisor/type ]]; then
            VIRT_TYPE=$(cat /sys/hypervisor/type)
        fi
    fi

    # 容器类虚拟化无法换内核
    case "${VIRT_TYPE}" in
        openvz|lxc|docker|podman|systemd-nspawn|wsl)
            CAN_CHANGE_KERNEL="false"
            ;;
        *)
            CAN_CHANGE_KERNEL="true"
            ;;
    esac
}

detect_kernel() {
    KERNEL_VERSION=$(uname -r)
    KERNEL_MAJOR=$(echo "${KERNEL_VERSION}" | cut -d. -f1)
    KERNEL_MINOR=$(echo "${KERNEL_VERSION}" | cut -d. -f2)
}

detect_bbr_status() {
    local cc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    CURRENT_CC="${cc}"

    local available
    available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")

    HAS_BBRPLUS="false"
    HAS_BBR="false"

    [[ "${available}" =~ bbrplus ]] && HAS_BBRPLUS="true"
    [[ "${available}" =~ (^|[[:space:]])bbr($|[[:space:]]) ]] && HAS_BBR="true"
}

run_detection() {
    detect_os
    detect_arch
    detect_virt
    detect_kernel
    detect_bbr_status
}

# 当作为脚本直接执行时输出结果
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_detection
    cat <<EOF
OS_FAMILY=${OS_FAMILY}
OS_ID=${OS_ID}
OS_VERSION=${OS_VERSION}
OS_CODENAME=${OS_CODENAME}
ARCH=${ARCH}
PKG_MGR=${PKG_MGR}
VIRT_TYPE=${VIRT_TYPE}
CAN_CHANGE_KERNEL=${CAN_CHANGE_KERNEL}
KERNEL_VERSION=${KERNEL_VERSION}
KERNEL_MAJOR=${KERNEL_MAJOR}
KERNEL_MINOR=${KERNEL_MINOR}
CURRENT_CC=${CURRENT_CC}
HAS_BBR=${HAS_BBR}
HAS_BBRPLUS=${HAS_BBRPLUS}
EOF
fi
