#!/usr/bin/env bash
# 修改 SSR 配置（端口、密码、伪装域名、备注）
# 加密方式 / 协议 / 混淆 已锁定，不可修改
#
# 使用：
#   sudo bash modify.sh                            # 交互式
#   sudo bash modify.sh --port 18888               # 改端口
#   sudo bash modify.sh --password mynewpass       # 改密码
#   sudo bash modify.sh --obfs-param example.com   # 改伪装域名
#   sudo bash modify.sh --remark "我的节点"        # 改备注
#   sudo bash modify.sh -p 18888 -P pass --remark X  # 一次改多个
#   sudo bash modify.sh --reset                    # 恢复默认
#   sudo bash modify.sh --help                     # 帮助

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# ===== 颜色 =====
C_GRN=$'\e[0;32m'
C_CYN=$'\e[0;36m'
C_YLW=$'\e[0;33m'
C_RED=$'\e[0;31m'
C_BLU=$'\e[0;34m'
C_BLD=$'\e[1m'
C_RST=$'\e[0m'

log_info() { echo -e "${C_GRN}[INFO]${C_RST} $*"; }
log_warn() { echo -e "${C_YLW}[WARN]${C_RST} $*"; }
log_err()  { echo -e "${C_RED}[ERR ]${C_RST} $*" >&2; }
log_step() { echo -e "\n${C_BLU}${C_BLD}▶${C_RST} ${C_BLD}$*${C_RST}"; }

# ===== 默认值（与 .env.example 一致） =====
DEFAULT_PORT=17777
DEFAULT_PASSWORD=gugugu
DEFAULT_OBFS_PARAM=cloud.tencent.com
DEFAULT_REMARK="My-SSR-Node"

# 锁定字段（不允许修改）
LOCKED_METHOD=chacha20-ietf
LOCKED_PROTOCOL=auth_chain_a
LOCKED_OBFS=tls1.2_ticket_auth

# ===== 帮助 =====
usage() {
    cat <<EOF
${C_BLD}用法:${C_RST}  sudo bash modify.sh [选项]

${C_BLD}选项:${C_RST}
  -p, --port PORT             修改端口（1-65535）
  -P, --password PASS         修改密码（建议 8 字符以上）
      --obfs-param DOMAIN     修改混淆伪装域名
  -r, --remark NAME           修改节点备注
      --reset                 全部恢复默认
      --no-restart            修改后不重启容器（仅写文件）
  -h, --help                  显示本帮助

${C_BLD}固定不可修改:${C_RST}
  加密方式: ${LOCKED_METHOD}
  协议:     ${LOCKED_PROTOCOL}
  混淆:     ${LOCKED_OBFS}

${C_BLD}示例:${C_RST}
  sudo bash modify.sh                          # 交互式选项
  sudo bash modify.sh --port 18888 --password 8nB#Kp9!Xz
  sudo bash modify.sh -P new-strong-password
  sudo bash modify.sh --reset

修改后会自动：
  1. 更新 .env 文件
  2. 重新生成 config/config.json + clash.yaml + ssr-info.txt + 二维码
  3. 防火墙重新放行新端口（关闭旧端口）
  4. 重启 SSR 容器
  5. 显示新的接入点信息

EOF
}

# ===== 参数解析 =====
NEW_PORT=""
NEW_PASSWORD=""
NEW_OBFS_PARAM=""
NEW_REMARK=""
DO_RESET=false
DO_RESTART=true
INTERACTIVE=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port)         NEW_PORT="${2:?}";        INTERACTIVE=false; shift 2 ;;
        -P|--password)     NEW_PASSWORD="${2:?}";    INTERACTIVE=false; shift 2 ;;
        --obfs-param)      NEW_OBFS_PARAM="${2:?}";  INTERACTIVE=false; shift 2 ;;
        -r|--remark)       NEW_REMARK="${2:?}";      INTERACTIVE=false; shift 2 ;;
        --reset)           DO_RESET=true;            INTERACTIVE=false; shift ;;
        --no-restart)      DO_RESTART=false;         shift ;;
        -h|--help)         usage; exit 0 ;;
        *)                 log_err "未知参数: $1"; usage; exit 1 ;;
    esac
done

# ===== 前置检查 =====
if [[ ${EUID} -ne 0 ]]; then
    log_err "需要 root 权限（用于改防火墙、重启容器）"
    log_err "请用：sudo $0 $*"
    exit 1
fi

if [[ ! -f .env ]]; then
    log_warn ".env 不存在，从 .env.example 创建"
    cp .env.example .env
fi

# 加载当前配置
set -a
# shellcheck disable=SC1091
source .env
set +a

OLD_PORT="${SSR_PORT:-${DEFAULT_PORT}}"
OLD_PASSWORD="${SSR_PASSWORD:-${DEFAULT_PASSWORD}}"
OLD_OBFS_PARAM="${SSR_OBFS_PARAM:-${DEFAULT_OBFS_PARAM}}"
OLD_REMARK="${SSR_REMARK:-${DEFAULT_REMARK}}"

# ===== 重置模式 =====
if [[ "${DO_RESET}" == "true" ]]; then
    log_warn "─ 重置为默认值 ─"
    NEW_PORT="${DEFAULT_PORT}"
    NEW_PASSWORD="${DEFAULT_PASSWORD}"
    NEW_OBFS_PARAM="${DEFAULT_OBFS_PARAM}"
    NEW_REMARK="${DEFAULT_REMARK}"
    INTERACTIVE=false
fi

# ===== 交互式输入 =====
if [[ "${INTERACTIVE}" == "true" ]]; then
    cat <<EOF

${C_BLD}━━━━━━ 当前配置 ━━━━━━${C_RST}
  端口:     ${C_CYN}${OLD_PORT}${C_RST}
  密码:     ${C_CYN}${OLD_PASSWORD}${C_RST}
  伪装域名: ${C_CYN}${OLD_OBFS_PARAM}${C_RST}
  备注:     ${C_CYN}${OLD_REMARK}${C_RST}

${C_BLD}━━━━━━ 输入新值（直接回车 = 保持不变）━━━━━━${C_RST}
EOF

    read -r -p "新端口 [${OLD_PORT}]: " NEW_PORT
    read -r -p "新密码 [${OLD_PASSWORD}]: " NEW_PASSWORD
    read -r -p "新伪装域名 [${OLD_OBFS_PARAM}]: " NEW_OBFS_PARAM
    read -r -p "新备注 [${OLD_REMARK}]: " NEW_REMARK
fi

# 空值 = 保持原值
[[ -z "${NEW_PORT}" ]]        && NEW_PORT="${OLD_PORT}"
[[ -z "${NEW_PASSWORD}" ]]    && NEW_PASSWORD="${OLD_PASSWORD}"
[[ -z "${NEW_OBFS_PARAM}" ]]  && NEW_OBFS_PARAM="${OLD_OBFS_PARAM}"
[[ -z "${NEW_REMARK}" ]]      && NEW_REMARK="${OLD_REMARK}"

# ===== 验证 =====
validate_port() {
    local p="$1"
    if ! [[ "${p}" =~ ^[0-9]+$ ]] || (( p < 1 || p > 65535 )); then
        log_err "端口必须是 1-65535 的整数: ${p}"
        exit 1
    fi
    if (( p < 1024 )); then
        log_warn "端口 ${p} < 1024，可能与系统服务冲突"
    fi
    # 检查端口冲突（非自身占用）
    if [[ "${p}" != "${OLD_PORT}" ]] && command -v ss >/dev/null 2>&1; then
        if ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"; then
            log_warn "端口 ${p} 已被其它进程监听，请确认"
        fi
    fi
}

validate_password() {
    local pw="$1"
    if [[ -z "${pw}" ]]; then
        log_err "密码不能为空"
        exit 1
    fi
    if [[ ${#pw} -lt 6 ]]; then
        log_warn "密码长度 ${#pw} < 6，强度太弱"
    fi
    if [[ "${pw}" =~ [\"\$\`\\] ]]; then
        log_err "密码不能包含 \" \$ \\\` \\\\ 字符（会破坏配置文件）"
        exit 1
    fi
}

validate_port "${NEW_PORT}"
validate_password "${NEW_PASSWORD}"

# ===== 摘要 =====
log_step "变更摘要"
diff_count=0
print_diff() {
    local key="$1" old="$2" new="$3"
    if [[ "${old}" != "${new}" ]]; then
        echo -e "  ${key}: ${C_RED}${old}${C_RST} → ${C_GRN}${new}${C_RST}"
        diff_count=$((diff_count + 1))
    else
        echo -e "  ${key}: ${C_CYN}${old}${C_RST} (unchanged)"
    fi
}
print_diff "端口    " "${OLD_PORT}"        "${NEW_PORT}"
print_diff "密码    " "${OLD_PASSWORD}"    "${NEW_PASSWORD}"
print_diff "伪装域名" "${OLD_OBFS_PARAM}"  "${NEW_OBFS_PARAM}"
print_diff "备注    " "${OLD_REMARK}"      "${NEW_REMARK}"

if (( diff_count == 0 )); then
    log_info "无变更，退出"
    exit 0
fi

if [[ "${INTERACTIVE}" == "true" ]]; then
    echo
    read -r -p "确认应用以上变更？[y/N]: " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        log_warn "已取消"
        exit 0
    fi
fi

# ===== 写入 .env =====
log_step "1/5 更新 .env"
update_env() {
    local key="$1" val="$2"
    # 转义 sed 特殊字符
    local safe_val
    safe_val=$(printf '%s' "${val}" | sed 's/[\/&]/\\&/g')
    if grep -qE "^${key}=" .env; then
        sed -i "s/^${key}=.*/${key}=${safe_val}/" .env
    else
        echo "${key}=${val}" >> .env
    fi
}
update_env "SSR_PORT"       "${NEW_PORT}"
update_env "SSR_PASSWORD"   "${NEW_PASSWORD}"
update_env "SSR_OBFS_PARAM" "${NEW_OBFS_PARAM}"
update_env "SSR_REMARK"     "${NEW_REMARK}"
log_info "✓ .env 已更新"

# ===== 重新生成 config.json =====
log_step "2/5 重新生成 config/config.json"
cat > config/config.json <<EOF
{
    "server": "0.0.0.0",
    "server_ipv6": "::",
    "server_port": ${NEW_PORT},
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "${NEW_PASSWORD}",
    "method": "${LOCKED_METHOD}",
    "protocol": "${LOCKED_PROTOCOL}",
    "protocol_param": "",
    "obfs": "${LOCKED_OBFS}",
    "obfs_param": "${NEW_OBFS_PARAM}",
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
log_info "✓ config.json 已更新"

# ===== 重新生成 clash.yaml =====
log_step "3/5 重新生成 clash.yaml"
bash scripts/generate-clash.sh || log_warn "生成 clash.yaml 失败，请稍后重试"

# ===== 防火墙：放新端口 + 关旧端口 =====
log_step "4/5 调整防火墙规则"
adjust_firewall() {
    local old="$1" new="$2"
    if [[ "${old}" == "${new}" ]]; then
        log_info "端口未变更，跳过防火墙"
        return
    fi

    if [[ "${ENABLE_FIREWALL:-true}" != "true" ]]; then
        log_warn "ENABLE_FIREWALL=false，跳过"
        return
    fi

    # ufw
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow "${new}/tcp"   >/dev/null 2>&1 || true
        ufw allow "${new}/udp"   >/dev/null 2>&1 || true
        ufw delete allow "${old}/tcp" >/dev/null 2>&1 || true
        ufw delete allow "${old}/udp" >/dev/null 2>&1 || true
        log_info "✓ ufw: 放行 ${new}, 移除 ${old}"
        return
    fi

    # firewalld
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${new}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port="${new}/udp" >/dev/null 2>&1 || true
        firewall-cmd --permanent --remove-port="${old}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --permanent --remove-port="${old}/udp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null
        log_info "✓ firewalld: 放行 ${new}, 移除 ${old}"
        return
    fi

    # iptables
    if command -v iptables >/dev/null 2>&1; then
        iptables -D INPUT -p tcp --dport "${old}" -j ACCEPT 2>/dev/null || true
        iptables -D INPUT -p udp --dport "${old}" -j ACCEPT 2>/dev/null || true
        iptables -C INPUT -p tcp --dport "${new}" -j ACCEPT 2>/dev/null \
            || iptables -I INPUT -p tcp --dport "${new}" -j ACCEPT
        iptables -C INPUT -p udp --dport "${new}" -j ACCEPT 2>/dev/null \
            || iptables -I INPUT -p udp --dport "${new}" -j ACCEPT
        # 持久化
        if command -v netfilter-persistent >/dev/null 2>&1; then
            netfilter-persistent save >/dev/null 2>&1 || true
        elif command -v iptables-save >/dev/null 2>&1 && [[ -d /etc/sysconfig ]]; then
            iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
        fi
        log_info "✓ iptables: 放行 ${new}, 移除 ${old}"
        return
    fi

    log_warn "未检测到防火墙工具，跳过"
}
adjust_firewall "${OLD_PORT}" "${NEW_PORT}"

# ===== 重启容器 =====
log_step "5/5 重启 SSR 容器"
if [[ "${DO_RESTART}" != "true" ]]; then
    log_warn "--no-restart 模式，跳过容器重启"
    log_warn "记得手动执行：docker compose restart"
else
    if docker compose version >/dev/null 2>&1; then
        DC="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DC="docker-compose"
    else
        log_warn "未找到 docker compose，跳过重启"
        DC=""
    fi

    if [[ -n "${DC}" ]]; then
        ${DC} restart ssr 2>&1 | grep -vE "^(time=|level=)" || true
        sleep 2
        log_info "✓ 容器已重启"
    fi
fi

# ===== 显示新信息 =====
log_step "应用完成 ✓"
echo
log_info "新的接入点信息："
echo
bash info.sh
