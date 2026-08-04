# CatVPN 版本迭代（CHANGELOG）

> **版本策略**：CatVPN 的版本号独立于上游 3X-UI。当前上游基础为 **3X-UI v2.9.4**（`github.com/mhsanaei/3x-ui/v2`）。
> 面板内显示的版本即本仓库版本（见 `config/version`）。

---

## [1.2.0] - 2026-08-04

### 性能优化（面板打开速度）
- **删除生产环境 sourcemap**：移除 `antd / axios / otpauth / moment` 的 `.map` 文件（共约 4.4MB）。这些文件只在浏览器开发者工具开启时才会被请求，却会白白撑大 Go 二进制与预编译包。此举缩小二进制与预编译包体积，并**对齐 3X-UI v3.6.0 的同类修复（#6131「二进制内不再打包生产环境 sourcemaps」）**。
- **剥离悬空 sourceMappingURL 注释**：同步删除 4 个 `min.js` 末尾的 `//# sourceMappingURL=...` 注释，避免开发者工具开启时对缺失 `.map` 发起 404。
- **资源预加载提示**：在面板 HTML `<head>` 增加 `antd.min.css / vue.min.js / antd.min.js` 的 `<link rel="preload">`，让浏览器尽早并行拉取首屏最重资源，缩短首屏时间。
- **既有加速已确认保留**：Gzip 响应压缩（`gin-contrib/gzip`，`web.go` 中间件）与静态资源 `Cache-Control: max-age=31536000`（1 年强缓存）在本 base 早已启用，本期核对无误。

### 工程 / 文档
- 新增本 CHANGELOG，明确 CatVPN 版本独立于上游 3X-UI。
- 预编译 CI（`build.yml`）此前已修正为 **amd64-only 正式发布**（非 prerelease），`install.sh` 安装时自动下载预编译包免编译；arm64 等架构自动回退源码编译。

### 已知 / 后续路线
- **关于「合并 3X-UI v3.6.0 新特性」**：当前 base 是 3X-UI **v2.9.4**，而 v3.6.0 属 **v3 大版本**（`module` 路径 `/v3`，破坏性重写：React SPA 前端、xray-core v26.7.28、DB 行为变更）。**跨大版本的安全 cherry-pick 不可行**——`git` 历史与 module 路径不同，手工搬运等价于完整的 v2→v3 rebase。该 rebase 为独立大工程（会丢失「改 html 即维护」的简单性、需重测 VPNGate），本期未做，列为后续路线。面板速度目标已通过资源层优化达成。

---

## [1.1.0] - 2026-08-04

- **UI 精修**：登录页 Logo 放大至 120px、文案改为「你好，欢迎使用 CatVPN」；侧栏 Logo 放大至 56px 并更换新暗色主题猫 Logo（与暗色背景协调）。
- **预编译 CI**：新增 GitHub Actions `build.yml`，自动构建并发布 linux/amd64 预编译包。
- **技能通用化**：`catvpn` 技能克隆源切到 `qzyfl/CatVPN`，移除本地打 patch 步骤；支持 WorkBuddy / Codex / Claude / Cursor 等任意 AI Agent 环境调用安装。

---

## [1.0.0] - 2026-08-04

- **初始 CatVPN**：基于 X-MILI（3X-UI v2.9.4 衍生）做品牌化改造——猫 Logo（PNG + 标题栏 ICO）、面板名 `CatVPN`、默认中文界面；移除原版侧栏的 GitHub / Telegram 按钮与「产品推荐」菜单项。
- **网络增强**：
  - Cloudflare WARP 出口（`wg-warp` 接口，仅把 `130.158.75.0/24` 路由到 WARP）解决 VPNGate 被云厂商数据中心 IP 封禁的问题；
  - BBR v3 Max 内核加速（`bbr` 拥塞控制 + `fq` 队列规则）。
- **交付物**：一键安装脚本 `install.sh`（含依赖安装、现场编译、systemd、随机凭据、WARP、BBR）与 AI Agent 技能 `catvpn_setup.sh`。
