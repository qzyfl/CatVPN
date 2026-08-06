#!/usr/bin/env bash
#
# update.sh — CatVPN 在线更新脚本
#
# 修复 High 级供应链 / 降级缺陷:
#   旧版 update.sh 会从上游 Aimilibot/X-MILI 拉取并安装, 把已装的 CatVPN 降级/替换成
#   未定制的 X-MILI (丢失猫 Logo / 中文 / WARP·VPNGate 集成 / 去推广区块等全部定制),
#   且安装到 /usr/bin/ml、产物命名 .x-mili-commit, 与 install.sh 完全不一致, arm64 直接 fail。
#
# 修复方案 (方案 A):
#   直接复用官方 install.sh 的已验证安装/更新逻辑 —— 从 qzyfl/CatVPN 下载 install.sh,
#   以 FORCE=1 执行, 保证安装路径 (/usr/local/x-ui)、二进制名 (/usr/local/bin/x-ui)、
#   配置目录与 install.sh 严格一致, 杜绝“更新后变回 X-MILI”的降级问题。
#
set -euo pipefail

APP_NAME="CatVPN"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/qzyfl/CatVPN/main}"
INSTALLER_URL="${REPO_RAW}/install.sh"
INSTALL_DIR="/usr/local/x-ui"

red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; plain='\033[0m'
log()  { echo -e "${green}[${APP_NAME}]${plain} $*"; }
warn() { echo -e "${yellow}[${APP_NAME}]${plain} $*"; }
fail() { echo -e "${red}[${APP_NAME}]${plain} $*" >&2; exit 1; }

# ---------- 前置检查 ----------
[[ $EUID -ne 0 ]] && fail "请使用 root 运行 / Please run as root"
command -v systemctl >/dev/null 2>&1 || fail "需要 systemd / systemd is required"
[[ -d "$INSTALL_DIR" ]] || fail "未找到安装目录 ${INSTALL_DIR}，请先安装 CatVPN"

command -v curl >/dev/null 2>&1 || fail "缺少 curl / curl is required"

# ---------- 下载官方安装脚本 ----------
log "从 ${REPO_RAW} 下载官方安装脚本以执行更新..."
tmp_install="$(mktemp -t catvpn-install.XXXXXX.sh)"
trap 'rm -f "$tmp_install"' EXIT

if ! curl -fsSL "$INSTALLER_URL" -o "$tmp_install"; then
    fail "下载安装脚本失败 / Failed to download installer: ${INSTALLER_URL}"
fi
[[ -s "$tmp_install" ]] || fail "下载的安装脚本为空 / Downloaded installer is empty: ${INSTALLER_URL}"

# 供应链防护: 确认下载到的脚本确实来自 qzyfl/CatVPN, 拒绝非预期来源, 防止再次被降级
if ! grep -q 'qzyfl/CatVPN' "$tmp_install"; then
    fail "安装脚本来源异常 (非 qzyfl/CatVPN)，已中止更新以防供应链攻击 / Unexpected installer source, aborted."
fi

# ---------- 复用官方安装逻辑完成更新 (保证与 install.sh 路径/命名一致) ----------
log "复用官方安装逻辑 (FORCE=1) 重新安装 CatVPN，保证与 install.sh 一致..."
FORCE=1 bash "$tmp_install"

log "CatVPN 更新完成 / CatVPN update complete."
