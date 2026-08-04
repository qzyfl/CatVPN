# CatVPN

> 基于 [X-MILI](https://github.com/Aimilibot/X-MILI)（3X-UI 衍生）改造的定制 Xray 代理面板：猫 Logo、默认中文、去除了原版的 GitHub / Telegram / 产品推荐推广区块；并强化了 **Cloudflare WARP 出口（解决 VPNGate 被云厂商 IP 封禁）** 与 **BBR v3 Max 内核加速**。

[![GitHub](https://img.shields.io/badge/GitHub-CatVPN-black?style=for-the-badge&logo=github)](https://github.com/qzyfl/CatVPN)
[![一键安装](https://img.shields.io/badge/一键安装-Linux_VPS-brightgreen?style=for-the-badge)](#一键安装)
[![License](https://img.shields.io/badge/License-GPLv3-blue?style=for-the-badge)](#开源协议)

## 项目介绍

CatVPN 在 X-MILI 基础上做了品牌化与网络增强：

- **品牌定制**：猫 Logo（PNG + 标题栏 ICO）、面板名 `CatVPN`、默认中文界面；移除原版侧栏的 GitHub / Telegram 按钮与「产品推荐」菜单项。
- **VPNGate 出口修复**：云厂商数据中心 IP（腾讯云 / 阿里云等）常被 VPNGate 的 CSV API（`vpngate.net` → `130.158.75.0/24`）封禁，导致抓不到节点。CatVPN 安装时会注册 Cloudflare WARP，并建立独立的 `wg-warp` WireGuard 接口，**仅把 `130.158.75.0/24` 路由到 WARP 出口**（不劫持服务器默认路由），让面板透明地经 WARP 拉取 VPNGate 节点。
- **BBR v3 Max 内核**：一键安装 byJoey 的 BBR v3 Max 内核并启用 `bbr` 拥塞控制 + `fq` 队列规则，提升吞吐与延迟。
- 基于 Xray，保留入站 / 出站 / 路由 / DNS / 证书 / 日志等常用面板管理能力。

## 一键安装

在 **root** 权限的 Linux VPS（Debian / Ubuntu 系推荐）上执行：

```bash
bash <(curl -sL https://raw.githubusercontent.com/qzyfl/CatVPN/main/install.sh)
```

脚本会自动完成：安装依赖 → 现场编译本仓库定制的 x-ui（小内存 VPS 自动补 4G swap 防 OOM）→ 安装 systemd 服务（默认中文）→ 初始化随机面板账号 → 配置 WARP/wg-warp 出口 → 安装 BBR v3 Max 内核（若需新内核则自动重启）。

> 也可先克隆再本地安装：
> ```bash
> git clone https://github.com/qzyfl/CatVPN && cd CatVPN && bash install.sh
> ```
> 重装 / 强制重新编译：`FORCE=1 bash install.sh`

安装完成后终端会打印面板地址、登录账号与密码。默认端口 `2053`，访问路径带随机安全后缀。

## 致敬开源

CatVPN 是 [X-MILI](https://github.com/Aimilibot/X-MILI) 的衍生修改版，而 X-MILI 本身基于 [3X-UI](https://github.com/MHSanaei/3x-ui)（[Xray](https://github.com/xtls/xray-core) 内核）。本仓库沿用 GPLv3 协议，保留原作者权益。

| 上游 | 说明 |
| --- | --- |
| [X-MILI](https://github.com/Aimilibot/X-MILI) | 本仓库直接衍生的面板（含 VPNGate 出站逻辑） |
| [3X-UI](https://github.com/MHSanaei/3x-ui) | 面板基础 |
| [Xray-core](https://github.com/xtls/xray-core) | 代理内核 |
| [VPNGate](https://www.vpngate.net/cn/) | 公益节点来源 |
| [byJoey/Actions-bbr-v3](https://github.com/byJoey/Actions-bbr-v3) | BBR v3 Max 内核 |

## 备注

- WARP 出口仅接管 `130.158.75.0/24`，不影响服务器其他出网流量。
- 面板初始账号密码为随机生成，请登录后及时修改。
- 编译需要 Go 与 `CGO_ENABLED=1`（sqlite），小内存机器由脚本自动处理 swap。

## 开源协议

本项目基于 GPLv3。详见 [LICENSE](./LICENSE)。CatVPN 的全部修改均在 X-MILI 的 GPLv3 授权范围内进行。
