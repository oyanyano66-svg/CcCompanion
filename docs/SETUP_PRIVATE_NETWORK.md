# 私有网络 (ZeroTier / Tailscale) 配置指南

> 给想用 VPN/SDN 把手机跟 cc 后端拉到同一虚拟局域网的用户。
> 适用于 ZeroTier、Tailscale、其他类似工具 (WireGuard 自建网等)。
>
> **使用前请先读 [DISCLAIMER.md](../DISCLAIMER.md) 跟 [SETUP_SERVER.md](SETUP_SERVER.md) (基础部署)。**

## 一句话总览

私网方案让手机跟 cc 后端在同一个虚拟局域网，绕过公网。
但默认 apns-server 只听 `127.0.0.1`，手机连进来会被拒。
需要改三件：**一 后端开门、二 系统防火墙放行、三 ccc app 填虚拟 IP**。

> 默认端口是 **8795**（见 `apns-server/config.example.toml`）。下文示例都用 8795，如果你改过 `port`，对应替换。

## 适用场景

- 不想在路由器配端口转发
- 不想用 Cloudflare Tunnel
- 公司 / 家里网络不允许公网入站
- 想让 cc 流量只走可信节点

## 一 安装跟连接私网

### ZeroTier

1. 装 ZeroTier 客户端 (zerotier.com/download)
2. my.zerotier.com 创建一个 Network，记下 Network ID
3. 电脑（跑 cc 的）加入该 Network：`sudo zerotier-cli join <NETWORK_ID>`
4. iPhone 装 ZeroTier app，加入同一 Network
5. my.zerotier.com 后台批准两个节点
6. 记下电脑被分配到的虚拟 IP（类似 `192.168.193.x` 或 `10.147.x.x`）

### Tailscale

1. 装 Tailscale 客户端 (tailscale.com/download)
2. 电脑跟 iPhone 用同一个 Tailscale 账号登录
3. 电脑被分配的虚拟 IP 在 tailscale.com admin console 或 `tailscale ip` 命令能看到（`100.x.x.x`）

## 二 改 apns-server 配置（核心一步）

apns-server 默认只听 `127.0.0.1`，虚拟网入站会被拒。

打开 cc 后端的 `config.toml`（一般在 `~/CcCompanion/apns-server/config.toml`），
在 `[server]` 区块改 `host` 跟 `allow_public_bind`：

```toml
[server]
host = "0.0.0.0"
port = 8795
allow_public_bind = true
```

**关于 host 选择**：

| 写法 | 暴露范围 | 推荐度 |
|------|----------|--------|
| `0.0.0.0` | 所有网卡含公网 | ⚠️ 简单，但公网 IP 的电脑等于对外暴露 |
| `<虚拟 IP>`（例 `192.168.193.5`） | 只对私网开门 | ✅ 最安全 |

如果电脑有公网 IP，**强烈建议**写虚拟 IP 而不是 `0.0.0.0`。

> **注意 P0-1 安全闸**：apns-server 默认拒绝绑定 `0.0.0.0`。如果你把 `host` 设成 `0.0.0.0` 但**没有**同时设 `allow_public_bind = true`，服务会拒绝启动并报错。这是 secure-by-default 设计，逼你显式确认对外暴露的风险。

### 进一步收紧：IP 白名单（可选但推荐）

`[server]` 还有一个 `allowed_ips` 选项，可以只放行私网网段，公网即使探到端口也连不进：

```toml
allowed_ips = ["127.0.0.1", "192.168.193.0/24"]   # ZeroTier 网段
# 或 Tailscale: allowed_ips = ["127.0.0.1", "100.64.0.0/10"]
```

空列表（默认）= 不限制。配上私网网段后，等于在后端层再加一道门。

改完**重启 apns-server**。

## 三 macOS 防火墙放行（macOS 用户必看）

macOS 系统自带防火墙可能拦截 Python 进程的入站连接，即使 backend 已经监听对外端口，系统层还是会丢包。

`系统设置 → 网络 → 防火墙 → 选项`，把 Python 加进允许入站列表。

或者临时关闭防火墙做验证（生产环境不推荐）。

Linux / Windows 用户检查对应防火墙工具（ufw / Windows Defender）。

## 四 ccc app 填私网 IP

ccc app onboarding wizard 或设置里的 backend URL，填成 cc 电脑被分配的 **虚拟 IP** + 端口：

```
错: http://127.0.0.1:8795       本机 loopback，手机连不到
错: http://192.168.1.100:8795   家里真实 LAN IP，手机不在同一 LAN 时连不到
对: http://100.64.1.5:8795      Tailscale 虚拟 IP
对: http://192.168.193.5:8795   ZeroTier 虚拟 IP
```

## 五 验证

手机 ZeroTier/Tailscale 客户端在线，然后：

1. 手机浏览器打开 `http://<虚拟IP>:8795/health` 应该返回 200
2. ccc app 测试连接按钮应该变绿
3. 测试发一条消息，后端 log 应该看到入站请求

## 常见报错

### 连不上 / 一直转圈

- 后端 log 完全没看到入站请求 → 防火墙拦了（检查第三步）或 `host` 还是 `127.0.0.1`
- 后端 log 看到 403 → token 不对，检查 `shared_secret`
- 后端 log 看到 connection reset → ZeroTier/Tailscale 网络抖动，先看私网双向 `ping` 是否通
- 后端启动直接报 `bind=0.0.0.0 but allow_public_bind=false` → 第二步漏了 `allow_public_bind = true`

### 电脑能上但 iPhone 不行

- iPhone 上的 ZeroTier/Tailscale 客户端是否在线（后台被系统杀）
- ATS：旧版本不允许明文 HTTP，更新到 1.0-221 或更高
- 如果配了 `allowed_ips`，确认 iPhone 拿到的虚拟 IP 在白名单网段里

### 今天能用明天不行

- 笔记本休眠 / 合盖会断 ZeroTier 连接 — 设置电源里改"合盖不休眠"
- 路由器 DHCP 重启可能让虚拟 IP 漂移 — Tailscale/ZeroTier 后台固定 IP

## 跟 Cloudflare Tunnel 对比

| 维度 | 私网（本文档） | Cloudflare Tunnel（[SETUP_CLOUDFLARED.md](SETUP_CLOUDFLARED.md)） |
|------|---------------|-------------------------------------------------------------------|
| 公网暴露 | 不暴露 | 通过 Cloudflare 暴露域名 |
| 配置复杂度 | 中 | 中 |
| 延迟 | 低（直连虚拟网） | 低（Cloudflare 边缘） |
| 多用户共享 | 难（每用户都要加入网络） | 易（公网域名给谁都能用） |
| 个人单用户 | ✅ 推荐 | ✅ 也可 |
| 公开 distribution | ❌ 不适合 | ✅ 推荐 |

---

*本指南覆盖私网部署。如要公网部署见 [SETUP_CLOUDFLARED.md](SETUP_CLOUDFLARED.md)。如要基础后端搭建见 [SETUP_SERVER.md](SETUP_SERVER.md)。*
