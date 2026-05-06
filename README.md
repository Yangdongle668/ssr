# SSR Docker 一键部署

ShadowsocksR 服务端的 Docker 化一键部署方案，自动生成 SSR 链接 + Clash 配置文件，支持 BBR Plus 内核加速，全 Linux 发行版兼容。

## 特性

- ✅ **一键部署**：单条命令完成 Docker 安装 + 内核优化 + SSR 启动
- ✅ **双格式输出**：同时生成 SSR 链接（含二维码）+ Clash YAML 配置文件
- ✅ **隐蔽性强的协议组合**：`auth_chain_a` + `tls1.2_ticket_auth`（伪装域名 `cloud.tencent.com`）
- ✅ **BBR Plus 内核加速**：基于 `UJX6N/bbrplus-5.15`，自动适配 Debian/Ubuntu/CentOS/RHEL
- ✅ **配置可改**：单条命令修改端口、密码、伪装域名、备注
- ✅ **一键查询**：随时查看接入点信息、SSR 链接、Clash 文件下载命令
- ✅ **全 Linux VPS 兼容**：自动检测发行版与虚拟化类型，OpenVZ/LXC 自动降级
- ✅ **完整中国分流规则**：Clash 配置内置国内直连 + 国外代理 + 广告拦截

## 默认参数

| 项目 | 值 | 是否可改 |
|---|---|---|
| 端口 | `17777` | ✅ 可改 |
| 密码 | `gugugu` | ✅ 可改 |
| 加密方式 | `chacha20-ietf` | ❌ 锁定 |
| 协议 | `auth_chain_a` | ❌ 锁定 |
| 混淆 | `tls1.2_ticket_auth` | ❌ 锁定 |
| 混淆参数 | `cloud.tencent.com` | ✅ 可改 |
| 备注 | `My-SSR-Node` | ✅ 可改 |

> 加密 / 协议 / 混淆 三项是组合后整体生效的"流量伪装方案"，单独换其中一个会影响隐蔽性，所以锁定。

---

# 完整使用教程

## 第 1 步：准备 VPS

### 1.1 推荐配置
- **CPU**: 1 核以上
- **内存**: 512MB 以上（SSR 容器约 50MB）
- **系统**: Debian 11/12、Ubuntu 20.04/22.04/24.04、CentOS 7+、AlmaLinux/Rocky Linux 8/9
- **架构**: x86_64 或 ARM64
- **虚拟化**: KVM（推荐）、VMware、Xen-HVM
- **不推荐**：OpenVZ、LXC（无法换内核，BBR Plus 不可用，但 SSR 仍可运行）

### 1.2 网络要求
- 服务器在国外（一般是港日韩美新加坡）
- 端口 `17777` 在 VPS 商面板的"安全组/防火墙"里放行（TCP + UDP）

> 部署脚本会自动配置服务器系统层防火墙（iptables/ufw/firewalld），但 **VPS 商家的外部安全组规则必须由你手动配置**。

## 第 2 步：登录服务器并下载脚本

```bash
# 用 SSH 登录你的 VPS
ssh root@你的服务器IP

# 拉取本仓库
git clone <你的仓库地址> ssr
cd ssr
```

## 第 3 步：一键部署

```bash
sudo bash deploy.sh
```

部署脚本会依次执行：

```
[1/9] 加载配置（生成 .env）
[2/9] 安装系统依赖（curl / qrencode 等）
[3/9] 安装 / 启动 Docker
[4/9] 网络参数调优（TCP fastopen / 缓冲区 / MTU 探测）
[5/9] 配置 BBR / BBR Plus 加速
[6/9] 配置防火墙（自动放行 17777 端口）
[7/9] 同步 SSR 配置 + 启动 Docker 容器
[8/9] 生成 Clash YAML
[9/9] 输出接入点信息（SSR 链接 + 二维码 + Clash 下载命令）
```

**预计耗时**：3-5 分钟（不算 BBR Plus 内核安装；如装内核需 5-10 分钟，且需要重启）

### 部署完成的输出示例

```
═══════════ 节点参数 ═══════════
  服务器       1.2.3.4
  端口         17777
  密码         gugugu
  加密方式     chacha20-ietf  (固定)
  协议         auth_chain_a   (固定)
  混淆         tls1.2_ticket_auth  (固定)
  混淆参数     cloud.tencent.com
  备注         My-SSR-Node

═══════════ SSR 链接（手机/桌面 SSR 客户端）═══════════
  ssr://MS4yLjMuNDoxNzc3NzphdXRoX2NoYWluX2E6Y2hhY2hhMjAtaWV0Zjp...
  [终端二维码 ASCII 图案]
  ✓ 二维码 PNG: ./ssr-qrcode.png

═══════════ Clash 配置文件下载 ═══════════
  本地路径    /root/ssr/clash.yaml
  文件大小    7.2K

  从本机下载到客户端电脑（在客户端运行）：

  # Linux / macOS：
  scp root@1.2.3.4:/root/ssr/clash.yaml ./clash.yaml

  # Windows (PowerShell)：
  scp root@1.2.3.4:/root/ssr/clash.yaml clash.yaml
```

## 第 4 步：把配置导入到客户端

### 4.1 SSR 客户端（最简单）

**Windows / macOS / Android / iOS** 都有 SSR 客户端：

| 平台 | 推荐客户端 |
|---|---|
| Windows | [ShadowsocksR-Windows](https://github.com/HMBSbige/ShadowsocksR-Windows)、ShadowsocksRR |
| macOS | ShadowsocksX-NG-R8 |
| Android | [SsrrAndroid](https://github.com/HMBSbige/ShadowsocksR-Android) |
| iOS | Potatso Lite、Shadowrocket（需要外区 Apple ID）|
| 路由器 | OpenWrt + ShadowsocksR Plus+ |

**两种导入方式**：
- **扫码导入**：用客户端"扫描二维码"功能扫部署完成时的终端二维码（或扫 `./ssr-qrcode.png`）
- **粘贴链接**：复制 `ssr://...` 链接，客户端选"从剪贴板导入"

### 4.2 Clash 客户端（功能更强）

Clash 支持精细分流（国内直连 / 国外代理 / 广告拦截）。

| 平台 | 推荐客户端 |
|---|---|
| Windows | [Clash Verge](https://github.com/clash-verge-rev/clash-verge-rev)、Clash for Windows |
| macOS | [ClashX Pro](https://install.appcenter.ms/users/clashx/apps/clashx-pro/distribution_groups/public)、Clash Verge |
| Android | [Clash for Android](https://github.com/Kr328/ClashForAndroid)、小猫咪 |
| iOS | Stash、Shadowrocket（外区 Apple ID）|
| Linux | Clash Verge |

**步骤**：

#### Step 1：从服务器把 `clash.yaml` 下载到本地

在你的**电脑（不是服务器）**上打开终端（Windows 用 PowerShell），运行部署完成时显示的 `scp` 命令：

```bash
# 把 1.2.3.4 换成你的服务器 IP
scp root@1.2.3.4:/root/ssr/clash.yaml ./clash.yaml
```

输入 SSH 密码后，会下载 `clash.yaml` 到当前目录。

> Windows 用户如果没有 `scp`，可以用 [WinSCP](https://winscp.net/) 图形界面拖拽，或在 PowerShell 里直接用（Win10+ 自带）

#### Step 2：在 Clash 客户端导入

以 **Clash Verge** 为例：
1. 打开 Clash Verge
2. 左侧"配置/Profiles"
3. 点"+"号 → "本地文件"
4. 选刚下载的 `clash.yaml`
5. 点新出现的配置卡片"使用"
6. 顶部开关打开"系统代理 / TUN 模式"

以 **Clash for Windows** 为例：
1. 打开 CFW
2. "Profiles" 标签
3. 点"+"号 → 选 `clash.yaml` → "Open"
4. 点配置使其变蓝
5. "General" 标签 → 打开"System Proxy"

**导入后**：
- 默认走"🚀 节点选择"组（节点选择 → 自动选择 → 你的 SSR 节点）
- 国内域名 / IP 自动直连
- 国外域名走代理
- 广告域名被拦截

---

# 修改配置（端口 / 密码 / 备注）

> ⚠️ **加密方式 / 协议 / 混淆方式不可修改**（设计上固定，保证流量伪装方案完整）

## 方式 A：交互式（推荐新手）

```bash
sudo bash modify.sh
```

会显示当前配置 + 引导你输入新值，直接回车 = 保持不变：

```
━━━━━━ 当前配置 ━━━━━━
  端口:     17777
  密码:     gugugu
  伪装域名: cloud.tencent.com
  备注:     My-SSR-Node

━━━━━━ 输入新值（直接回车 = 保持不变）━━━━━━
新端口 [17777]: 18888
新密码 [gugugu]: 我的强密码123
新伪装域名 [cloud.tencent.com]:
新备注 [My-SSR-Node]: 美国节点-1

▶ 变更摘要
  端口    : 17777 → 18888
  密码    : gugugu → 我的强密码123
  伪装域名: cloud.tencent.com (unchanged)
  备注    : My-SSR-Node → 美国节点-1

确认应用以上变更？[y/N]: y
```

## 方式 B：命令行参数（适合脚本化）

```bash
# 改端口
sudo bash modify.sh --port 18888

# 改密码
sudo bash modify.sh --password 'My$tr0ng-P@ss'

# 改伪装域名（建议用大流量国内站点域名）
sudo bash modify.sh --obfs-param www.bing.com

# 改备注
sudo bash modify.sh --remark "香港节点"

# 一次改多个
sudo bash modify.sh -p 18888 -P newpass --remark "JP-Tokyo"

# 短选项
sudo bash modify.sh -p 18888 -P newpass

# 重置为默认值
sudo bash modify.sh --reset

# 修改但不重启容器（高级用法）
sudo bash modify.sh -p 18888 --no-restart

# 查看帮助
sudo bash modify.sh --help
```

## 修改后会自动做什么？

```
1. 写入新值到 .env
2. 重新生成 config/config.json
3. 重新生成 clash.yaml
4. 防火墙放行新端口、移除旧端口
5. 重启 SSR 容器
6. 显示新的接入点信息
```

**修改端口后**：客户端需要重新导入新的链接 / 配置文件，因为端口变了。

**修改密码后**：客户端需要更新密码，或重新导入。

> 💡 推荐每隔 1-3 个月轮换一次端口和密码，降低被识别和封锁的概率。

---

# 一键查询接入点信息

任何时候想查看当前的接入点信息：

```bash
bash info.sh
```

输出包括：
- 节点完整参数
- SSR 链接 + 二维码（终端 ASCII + PNG 文件）
- Clash 配置文件路径 + SCP 下载命令
- 容器运行状态
- BBR 加速状态
- 客户端导入提示

不需要 root 权限（只读 .env 和本地文件）。

---

# 常用运维命令

## 查看状态

```bash
# 容器状态
docker compose ps

# 实时日志
docker compose logs -f ssr

# 最近 100 行日志
docker compose logs --tail 100 ssr

# 端口监听检查
ss -lntu | grep 17777

# BBR 状态
sysctl net.ipv4.tcp_congestion_control
```

## 重启 / 停止 / 启动

```bash
# 重启
docker compose restart

# 停止
docker compose stop

# 启动（停止后）
docker compose start

# 完全停止（删除容器，保留配置）
docker compose down

# 重新启动（基于已有配置）
docker compose up -d
```

## 升级

```bash
# 拉最新基础镜像并重启
docker compose pull
docker compose up -d --build
```

## 完全重置（保留 .env 配置）

```bash
docker compose down
sudo bash deploy.sh
```

## 完全卸载

```bash
# 停止并删除容器
docker compose down -v

# 删除镜像
docker rmi ssr-server:latest teddysun/shadowsocks-r:latest

# 删除 sysctl 调优
sudo rm -f /etc/sysctl.d/99-ssr-tune.conf /etc/sysctl.d/99-bbr*.conf
sudo sysctl --system

# 删除部署目录
cd .. && rm -rf ssr
```

> 卸载不会删除已安装的 BBR Plus 内核，如要回退原内核需要在 GRUB 启动时手动选择，或卸载对应的 kernel 包。

---

# 兼容性说明

## 系统兼容矩阵

| 发行版 | 自动安装 Docker | BBR Plus 内核 | 防火墙 |
|---|---|---|---|
| Debian 10/11/12 | ✅ | ✅ | iptables/ufw |
| Ubuntu 18.04+/20.04+/22.04+/24.04 | ✅ | ✅ | iptables/ufw |
| CentOS 7/8 | ✅ | ✅ | firewalld |
| AlmaLinux 8/9 | ✅ | ✅ | firewalld |
| Rocky Linux 8/9 | ✅ | ✅ | firewalld |
| Fedora 35+ | ✅ | ⚠️ 内核版本不兼容 → 降级 BBR | firewalld |
| openSUSE | ✅ | ⚠️ 降级到原版 BBR | firewalld |
| Arch Linux | ✅ | ⚠️ 降级到原版 BBR | iptables |
| Alpine | ⚠️ 仅 SSR 容器 | ⚠️ 视情况 | iptables |

## 虚拟化兼容矩阵

| 类型 | BBR Plus | 原版 BBR | 备注 |
|---|---|---|---|
| KVM / 物理机 | ✅ 可装 | ✅ | 推荐 |
| VMware / Xen-HVM | ✅ 可装 | ✅ | |
| OpenVZ | ❌ | ⚠️ 取决于宿主机 | 共享内核，部分 OpenVZ 7+ 支持 |
| LXC | ❌ | ⚠️ 取决于宿主机 | |
| Docker-in-Docker | ❌ | ⚠️ | 不推荐 |

脚本会自动检测，无法换内核时降级到原版 BBR；都不行就用默认 cubic（容器仍可正常使用，只是没加速）。

## 架构兼容矩阵

| 架构 | SSR 容器 | BBR Plus 内核 |
|---|---|---|
| x86_64 (amd64) | ✅ | ✅ deb + rpm 都有 |
| ARM64 (aarch64) | ✅ | ✅ deb 有，rpm 暂无 |
| ARMv7 / 其它 | ✅ | ❌ 自动降级 |

---

# 故障排查

## 客户端连不上

按这个顺序排查：

```bash
# 1. 容器在跑吗？
docker compose ps
# 如果不是 "running"，看日志：
docker compose logs --tail 50 ssr

# 2. 端口在监听吗？
ss -lntu | grep 17777
# 应该看到 17777 端口在 LISTEN 状态

# 3. 系统防火墙放行了吗？
# Debian/Ubuntu:
iptables -L -n | grep 17777
ufw status | grep 17777
# CentOS/RHEL:
firewall-cmd --list-ports | grep 17777

# 4. VPS 商家的外部安全组放行了吗？
# 这一步必须在 VPS 商家面板配置：腾讯云"安全组"、阿里云"安全组"、
# 谷歌云"防火墙规则"、AWS"安全组"、BandwagonHost / Vultr 没有外部安全组

# 5. 在客户端测试网络连通：
nc -zv 你的服务器IP 17777
# 或：
telnet 你的服务器IP 17777
```

## 速度慢 / 不稳定

```bash
# 查看 BBR 是否启用
sysctl net.ipv4.tcp_congestion_control
# 应该是 bbr 或 bbrplus

# 如果显示 cubic 且服务器是 KVM/物理机，重新跑 BBR 安装
sudo bash scripts/install-bbr-plus.sh

# 如果安装后提示需重启，重启服务器
sudo reboot

# 重启后再次确认
sysctl net.ipv4.tcp_congestion_control
```

## Docker 拉镜像失败（国内 VPS）

国内 VPS 可能无法访问 Docker Hub，编辑 `/etc/docker/daemon.json` 加镜像加速：

```json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1panel.live",
    "https://hub.rat.dev"
  ]
}
```

然后：

```bash
sudo systemctl restart docker
```

## BBR Plus 安装后没生效

```bash
# 查看当前内核
uname -r
# 应该显示包含 bbrplus 字样

# 如果没有，说明新内核没被设为默认，重启选择新内核：
sudo reboot

# 重启后查看内核启动菜单：
ls /boot/vmlinuz-*

# 强制设置 GRUB 默认内核（Debian/Ubuntu）：
sudo grub-set-default 0  # 0 = 第一个内核（通常是新内核）
sudo update-grub
sudo reboot
```

## OpenVZ VPS BBR 不可用

OpenVZ 共享宿主机内核，无法换内核。两个选择：

1. **联系 VPS 商家**：让他们升级宿主机内核到支持 BBR 的版本
2. **换 VPS**：选 KVM 类型的 VPS，市场上常见的有：
   - 国外：BandwagonHost、Vultr、DigitalOcean、Linode、Hetzner、RackNerd
   - 国内出海：腾讯云海外、阿里云海外（节点选香港 / 东京 / 新加坡）

## 修改 .env 后没生效

修改 `.env` 后**必须重新部署或修改**才能生效：

```bash
# 推荐：用 modify.sh 修改（自动重启）
sudo bash modify.sh

# 或：直接改完 .env 后重启
docker compose restart
bash scripts/generate-clash.sh  # 重新生成 clash.yaml
```

---

# 安全建议

1. **修改默认密码**：`gugugu` 是公开的，部署后立即修改
   ```bash
   sudo bash modify.sh -P "$(openssl rand -base64 16)"
   ```

2. **保护 SSH**：建议启用 fail2ban 防 SSH 爆破
   ```bash
   # 编辑 .env
   ENABLE_FAIL2BAN=true
   # 重新跑 deploy
   sudo bash deploy.sh
   ```

3. **定期换端口**：把 17777 换成你自己选的高位端口，每 1-3 个月换一次
   ```bash
   sudo bash modify.sh --port $((10000 + RANDOM % 50000))
   ```

4. **保密 clash.yaml**：里面包含完整密码和服务器信息，传输 / 存储要走加密通道（SCP / 加密硬盘）

5. **流量提醒**：`auth_chain_a + tls1.2_ticket_auth` 隐蔽性好，但 GFW 在持续升级主动探测，**没有协议是 100% 安全的**。如果连续被封，及时换端口和伪装域名

6. **法律提醒**：请遵守服务器所在地和你所在地的法律法规

---

# 文件结构

```
ssr/
├── deploy.sh                # 一键部署主入口（root 执行）
├── info.sh                  # 一键查询接入点信息
├── modify.sh                # 修改端口 / 密码 / 伪装域名 / 备注
├── docker-compose.yml       # Docker 编排
├── Dockerfile               # 自定义镜像（基于 teddysun/shadowsocks-r）
├── .env                     # 实际配置（git 忽略）
├── .env.example             # 配置模板
├── .gitignore
├── README.md                # 本文档
├── config/
│   └── config.json          # SSR 服务端配置（自动生成）
├── scripts/
│   ├── detect-os.sh         # OS / 虚拟化 / 内核检测
│   ├── install-bbr-plus.sh  # BBR Plus 内核安装
│   ├── tune-sysctl.sh       # sysctl 网络调优
│   ├── generate-clash.sh    # 生成 Clash YAML
│   └── healthcheck.sh       # Docker 健康检查
├── clash.yaml               # Clash 配置（生成产物，git 忽略）
├── ssr-info.txt             # 节点摘要（生成产物，git 忽略）
└── ssr-qrcode.png           # SSR 二维码（生成产物，git 忽略）
```

---

# 命令速查表

| 命令 | 用途 |
|---|---|
| `sudo bash deploy.sh` | 首次部署（或重新部署） |
| `bash info.sh` | 查看接入点信息（不需要 root） |
| `sudo bash modify.sh` | 交互式修改配置 |
| `sudo bash modify.sh --port 18888` | 直接改端口 |
| `sudo bash modify.sh --password 'xxx'` | 直接改密码 |
| `sudo bash modify.sh --reset` | 重置默认值 |
| `sudo bash modify.sh --help` | 修改命令的完整帮助 |
| `docker compose ps` | 查看容器状态 |
| `docker compose logs -f ssr` | 实时日志 |
| `docker compose restart` | 重启容器 |
| `bash scripts/generate-clash.sh` | 仅重新生成 clash.yaml |
| `sysctl net.ipv4.tcp_congestion_control` | 查 BBR 状态 |

---

# License

MIT

# 致谢

- [teddysun/shadowsocks-r](https://hub.docker.com/r/teddysun/shadowsocks-r) - Docker 镜像
- [UJX6N/bbrplus-5.15](https://github.com/UJX6N/bbrplus-5.15) - BBR Plus 内核
- [yaofeng2688/v2ray2clash](https://github.com/yaofeng2688/v2ray2clash) - Clash 转换格式参考
