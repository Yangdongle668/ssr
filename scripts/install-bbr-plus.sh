#!/usr/bin/env bash
# BBR/BBR Plus 内核安装脚本（支持 Debian/Ubuntu/CentOS/RHEL/Alma/Rocky）
# 内核来源：UJX6N/bbrplus-5.15（活跃维护，覆盖主流发行版 + 多架构）
# 容器/OpenVZ 自动跳过；老内核自动降级到原版 BBR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=detect-os.sh
source "${SCRIPT_DIR}/detect-os.sh"

# 颜色输出
C_RED='\033[0;31m'
C_GRN='\033[0;32m'
C_YLW='\033[0;33m'
C_RST='\033[0m'

log_info() { echo -e "${C_GRN}[BBR]${C_RST} $*"; }
log_warn() { echo -e "${C_YLW}[BBR]${C_RST} $*"; }
log_err()  { echo -e "${C_RED}[BBR]${C_RST} $*" >&2; }

# 启用原版 BBR（内核 >= 4.9）
enable_native_bbr() {
    log_info "启用原版 BBR（无需重启）..."

    # 持久化 sysctl
    local conf="/etc/sysctl.d/99-bbr.conf"
    cat > "${conf}" <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    sysctl -p "${conf}" >/dev/null 2>&1 || true

    # 验证
    local cc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    if [[ "${cc}" == "bbr" ]]; then
        log_info "✓ 原版 BBR 已启用"
        return 0
    else
        log_warn "BBR 切换失败，当前拥塞控制: ${cc}"
        return 1
    fi
}

# 启用 BBR Plus（需先安装内核）
enable_bbrplus() {
    local conf="/etc/sysctl.d/99-bbrplus.conf"
    cat > "${conf}" <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbrplus
EOF

    sysctl -p "${conf}" >/dev/null 2>&1 || true

    local cc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    if [[ "${cc}" == "bbrplus" ]]; then
        log_info "✓ BBR Plus 已启用"
        return 0
    else
        return 1
    fi
}

# 安装 BBR Plus 内核（Debian/Ubuntu）
install_bbrplus_deb() {
    local arch_suffix
    case "${ARCH}" in
        amd64) arch_suffix="x64" ;;
        arm64) arch_suffix="arm64" ;;
        *)
            log_err "BBR Plus 不支持架构: ${ARCH}"
            return 1
            ;;
    esac

    log_info "下载 UJX6N/bbrplus-5.15 内核包..."

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN

    # GitHub API 拿最新 release 资产列表，过滤 deb 包
    local api_url="https://api.github.com/repos/UJX6N/bbrplus-5.15/releases/latest"
    local assets
    assets=$(curl -fsSL --connect-timeout 10 "${api_url}" 2>/dev/null) || {
        log_err "无法访问 GitHub API（网络问题），将降级到原版 BBR"
        return 1
    }

    # 找到匹配架构的 deb 包（headers + image）
    local deb_urls
    deb_urls=$(echo "${assets}" \
        | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+\.deb"' \
        | grep -E "(${arch_suffix}|${ARCH})" \
        | grep -E "(headers|image)" \
        | sed 's/.*: *"//; s/"$//' || true)

    if [[ -z "${deb_urls}" ]]; then
        log_err "未找到 ${ARCH} 架构的 deb 包"
        return 1
    fi

    cd "${tmp_dir}"
    while IFS= read -r url; do
        log_info "下载: $(basename "${url}")"
        curl -fsSL -O "${url}" || {
            log_err "下载失败: ${url}"
            return 1
        }
    done <<< "${deb_urls}"

    log_info "安装内核包..."
    DEBIAN_FRONTEND=noninteractive dpkg -i ./*.deb || {
        log_err "dpkg 安装失败，尝试修复依赖..."
        apt-get install -f -y
        DEBIAN_FRONTEND=noninteractive dpkg -i ./*.deb || return 1
    }

    # 更新 grub 默认启动项
    update-grub 2>/dev/null || update-grub2 2>/dev/null || true

    return 0
}

# 安装 BBR Plus 内核（CentOS/RHEL/Alma/Rocky）
install_bbrplus_rpm() {
    if [[ "${ARCH}" != "amd64" ]]; then
        log_err "BBR Plus rpm 包目前仅支持 amd64"
        return 1
    fi

    log_info "下载 UJX6N/bbrplus-5.15 内核 rpm 包..."

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' RETURN

    local api_url="https://api.github.com/repos/UJX6N/bbrplus-5.15/releases/latest"
    local assets
    assets=$(curl -fsSL --connect-timeout 10 "${api_url}" 2>/dev/null) || {
        log_err "无法访问 GitHub API"
        return 1
    }

    # 根据 RHEL 大版本选择匹配的 rpm
    local rhel_major
    rhel_major=$(echo "${OS_VERSION}" | cut -d. -f1)

    local rpm_urls
    rpm_urls=$(echo "${assets}" \
        | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+\.rpm"' \
        | grep -E "(el${rhel_major}|rhel${rhel_major}|centos${rhel_major})" \
        | grep -E "x86_64" \
        | grep -vE "(devel|debug)" \
        | sed 's/.*: *"//; s/"$//' || true)

    if [[ -z "${rpm_urls}" ]]; then
        # 退而求其次：拿任意 el* rpm
        rpm_urls=$(echo "${assets}" \
            | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+\.rpm"' \
            | grep -E "x86_64" \
            | grep -vE "(devel|debug)" \
            | sed 's/.*: *"//; s/"$//' | head -3 || true)
    fi

    if [[ -z "${rpm_urls}" ]]; then
        log_err "未找到匹配的 rpm 包"
        return 1
    fi

    cd "${tmp_dir}"
    while IFS= read -r url; do
        log_info "下载: $(basename "${url}")"
        curl -fsSL -O "${url}" || return 1
    done <<< "${rpm_urls}"

    log_info "安装 rpm..."
    if [[ "${PKG_MGR}" == "dnf" ]]; then
        dnf install -y ./*.rpm || return 1
    else
        yum install -y ./*.rpm || return 1
    fi

    # 把新内核设为默认
    if command -v grub2-set-default >/dev/null 2>&1; then
        local new_kernel
        new_kernel=$(grep -E "^menuentry" /boot/grub2/grub.cfg 2>/dev/null \
            | grep -i bbrplus | head -1 \
            | sed -e 's/^menuentry [\x27"]\([^\x27"]*\)[\x27"].*/\1/' || true)
        if [[ -n "${new_kernel}" ]]; then
            grub2-set-default "${new_kernel}" || true
        fi
        grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
    fi

    return 0
}

# 主入口
main() {
    run_detection

    log_info "OS=${OS_ID} ${OS_VERSION} (${OS_FAMILY}) | Arch=${ARCH} | Virt=${VIRT_TYPE} | Kernel=${KERNEL_VERSION}"
    log_info "当前拥塞控制=${CURRENT_CC} | HAS_BBR=${HAS_BBR} | HAS_BBRPLUS=${HAS_BBRPLUS}"

    local mode="${ACCEL_MODE:-auto}"

    if [[ "${mode}" == "skip" ]]; then
        log_warn "ACCEL_MODE=skip，跳过加速配置"
        return 0
    fi

    # 容器类虚拟化：内核共享，无法换；尝试启用现有 BBR
    if [[ "${CAN_CHANGE_KERNEL}" == "false" ]]; then
        log_warn "检测到容器化环境(${VIRT_TYPE})，无法替换内核"
        if [[ "${HAS_BBRPLUS}" == "true" ]]; then
            enable_bbrplus && return 0
        fi
        if [[ "${HAS_BBR}" == "true" ]]; then
            enable_native_bbr && return 0
        fi
        log_warn "宿主机未提供 BBR/BBR Plus 模块，使用默认拥塞控制(${CURRENT_CC})"
        log_warn "建议联系 VPS 商家升级宿主机内核，或换用 KVM 类型 VPS"
        return 0
    fi

    # 物理/KVM 环境：根据 mode 决定
    case "${mode}" in
        bbr)
            log_info "目标: 原版 BBR"
            local kmajor="${KERNEL_MAJOR:-0}"
            local kminor="${KERNEL_MINOR:-0}"
            if (( kmajor > 4 )) || { (( kmajor == 4 )) && (( kminor >= 9 )); }; then
                enable_native_bbr
            else
                log_warn "内核 ${KERNEL_VERSION} 太旧（< 4.9），无 BBR 模块"
                return 1
            fi
            ;;
        bbrplus|auto)
            if [[ "${HAS_BBRPLUS}" == "true" ]]; then
                log_info "✓ 内核已自带 BBR Plus 模块，直接启用"
                enable_bbrplus
                return 0
            fi

            if [[ "${mode}" == "auto" && "${HAS_BBR}" == "true" ]]; then
                # auto 模式且已有原版 BBR：询问还是直接装 BBR Plus？
                # 设计选择：auto 模式优先启用现有 BBR，避免必然重启
                log_info "auto 模式：内核已有原版 BBR，直接启用（如需 BBR Plus 请设 ACCEL_MODE=bbrplus）"
                enable_native_bbr
                return 0
            fi

            log_info "准备安装 BBR Plus 内核（${OS_FAMILY} / ${ARCH}）..."
            local install_ok="false"
            case "${OS_FAMILY}" in
                debian)
                    if install_bbrplus_deb; then
                        install_ok="true"
                    fi
                    ;;
                rhel)
                    if install_bbrplus_rpm; then
                        install_ok="true"
                    fi
                    ;;
                *)
                    log_warn "BBR Plus 暂不支持 ${OS_FAMILY}，降级到原版 BBR"
                    ;;
            esac

            if [[ "${install_ok}" == "true" ]]; then
                log_info "═══════════════════════════════════════════"
                log_info "  ✓ BBR Plus 内核安装完成"
                log_info "  ⚠ 需要重启服务器才能加载新内核"
                log_info "  重启后 BBR Plus 会自动启用"
                log_info "═══════════════════════════════════════════"
                # 标记需要重启
                touch /var/run/.ssr-bbrplus-need-reboot
                return 0
            fi

            # 安装失败：降级
            log_warn "BBR Plus 安装失败，降级到原版 BBR"
            if [[ "${HAS_BBR}" == "true" ]]; then
                enable_native_bbr
            else
                log_warn "原版 BBR 也不可用，跳过加速"
            fi
            ;;
        *)
            log_err "未知 ACCEL_MODE: ${mode}"
            return 1
            ;;
    esac
}

main "$@"
