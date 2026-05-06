# SSR Docker 一键部署

ShadowsocksR 服务端的 Docker 一键部署方案，预设隐蔽性更强的协议组合，自动配置 BBR Plus 内核加速，全 Linux 发行版兼容。

## 默认参数

| 项目 | 值 |
|---|---|
| 端口 | `17777` (TCP+UDP) |
| 密码 | `gugugu` |
| 加密方式 | `chacha20-ietf` |
| 协议 | `auth_chain_a` |
| 混淆 | `tls1.2_ticket_auth` |
| 混淆参数 | `cloud.tencent.com` |
| TCP 加速 | BBR Plus（自动降级到 BBR） |

> 所有参数都可以通过 `.env` 覆盖，无需改代码。

## 一键部署

```bash
git clone <this-repo> ssr && cd ssr
sudo bash deploy.sh
```

完成后会显示 SSR 链接 + 终端二维码（手机扫码导入），并保存 PNG 到 `./ssr-qrcode.png`，配置摘要保存到 `./ssr-info.txt`。

## 兼容性

### 发行版（依赖 Docker 即可）
- Debian 10/11/12
- Ubuntu 18.04/20.04/22.04/24.04
- CentOS 7/8、AlmaLinux 8/9、Rocky Linux 8/9
- Fedora、openSUSE、Arch、Alpine（基础功能）

### 架构
- `x86_64` (amd64) - 完整支持
- `aarch64` (arm64) - 完整支持（包括 BBR Plus 内核）
- 其他架构 - SSR 容器可用，BBR Plus 不可用，会自动降级

### 虚拟化
| 类型 | BBR Plus | 原版 BBR | 备注 |
|---|---|---|---|
| KVM / 物理机 | ✓ 可装 | ✓ | 推荐 |
| VMware / Xen HVM | ✓ 可装 | ✓ | |
| OpenVZ | ✗ | 取决于宿主机 | 共享内核，无法换 |
| LXC | ✗ | 取决于宿主机 | 共享内核 |

脚本会自动检测，无法换内核时降级到原版 BBR；都不行就用默认拥塞控制（容器仍可正常使用，只是没有加速）。

## 自定义配置

```bash
cp .env.example .env
vim .env       # 修改端口/密码/协议等
sudo bash deploy.sh
```

`.env` 主要选项：

```bash
SSR_PORT=17777                    # 端口
SSR_PASSWORD=gugugu               # 密码
SSR_PROTOCOL=auth_chain_a         # 协议
SSR_OBFS=tls1.2_ticket_auth       # 混淆
SSR_OBFS_PARAM=cloud.tencent.com  # 伪装域名

ACCEL_MODE=auto       # bbrplus / bbr / auto / skip
ENABLE_FIREWALL=true  # 自动放行端口
ENABLE_FAIL2BAN=false # SSH 防爆破（独立项，建议 VPS 都开）
ENABLE_QRCODE=true    # 生成二维码
```

## 常用运维

```bash
# 查看状态
docker compose ps

# 查看日志
docker compose logs -f ssr

# 重启
docker compose restart

# 修改配置后重启
vim config/config.json
docker compose restart ssr

# 完全重新部署
docker compose down
sudo bash deploy.sh

# 升级镜像
docker compose pull && docker compose up -d

# 查看 BBR 状态
sysctl net.ipv4.tcp_congestion_control
sysctl net.ipv4.tcp_available_congestion_control
```

## 客户端

- **Windows**: ShadowsocksR-Windows、ShadowsocksRR
- **macOS**: ShadowsocksX-NG-R8
- **Android**: ShadowsocksR、SsrrAndroid
- **iOS**: Potatso Lite、Shadowrocket（需要外区 Apple ID）
- **OpenWrt 路由器**: ShadowsocksR Plus+

直接用 `ssr-info.txt` 里的 `ssr://` 链接导入即可，或扫描 `ssr-qrcode.png` / 终端二维码。

## 安全建议

1. **VPS 安全**：部署后启用 `ENABLE_FAIL2BAN=true` 防 SSH 爆破
2. **不要使用默认密码**：把 `gugugu` 改成强随机串（16+ 字符）
3. **流量警告**：`auth_chain_a + tls1.2_ticket_auth` 隐蔽性较好，但**没有任何代理协议是 100% 安全的**。GFW 在持续升级主动探测，建议偶尔切换端口/密码
4. **重要**：若服务器在国内或受 GFW 严格管控的地区，请遵守当地法律法规

## 故障排查

### Docker 拉取失败
国内 VPS 可能无法直连 Docker Hub，可在 `/etc/docker/daemon.json` 加速：

```json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1panel.live"
  ]
}
```

然后 `systemctl restart docker`。

### BBR Plus 安装后未启用
内核安装需要重启：

```bash
reboot
# 重启后验证
uname -r          # 应显示 bbrplus 字样
sysctl net.ipv4.tcp_congestion_control   # 应为 bbrplus
```

### 客户端连不上
1. 检查防火墙：`iptables -L -n | grep 17777`
2. 检查容器：`docker compose ps`，应是 `running` 且 `healthy`
3. VPS 商面板的安全组规则也要放行 17777/tcp 和 17777/udp
4. 用 `nc -zv <服务器IP> 17777` 在客户端测试连通

### OpenVZ 无法启用 BBR
正常现象。换 KVM 的 VPS（推荐 BandwagonHost、Vultr、DigitalOcean、Linode 等）。

## 文件结构

```
.
├── deploy.sh                # 一键部署主脚本
├── docker-compose.yml       # 容器编排
├── Dockerfile               # 容器镜像
├── .env.example             # 配置模板
├── config/
│   └── config.json          # SSR 服务端配置
└── scripts/
    ├── detect-os.sh         # OS/虚拟化检测
    ├── install-bbr-plus.sh  # BBR Plus 内核安装
    ├── tune-sysctl.sh       # sysctl 网络调优
    ├── healthcheck.sh       # 容器健康检查
    └── generate-qr.sh       # SSR 链接 + 二维码生成
```

## 卸载

```bash
docker compose down -v
docker rmi ssr-server:latest
rm /etc/sysctl.d/99-ssr-tune.conf /etc/sysctl.d/99-bbr*.conf
sysctl --system
```
