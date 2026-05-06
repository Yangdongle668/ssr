#!/bin/sh
# 容器健康检查：进程在 + 端口在监听
set -e

PORT="${SSR_PORT:-17777}"

# 1. 进程检查
if ! pgrep -f "server.py" >/dev/null 2>&1; then
    echo "[health] ssr process not found"
    exit 1
fi

# 2. 端口监听检查（优先 ss，备选 netstat）
if command -v ss >/dev/null 2>&1; then
    if ! ss -lnt 2>/dev/null | grep -q ":${PORT} "; then
        echo "[health] port ${PORT} not listening"
        exit 1
    fi
elif command -v netstat >/dev/null 2>&1; then
    if ! netstat -lnt 2>/dev/null | grep -q ":${PORT} "; then
        echo "[health] port ${PORT} not listening"
        exit 1
    fi
fi

exit 0
