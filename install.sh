#!/usr/bin/env bash
# install.sh — CatVPN 一键安装脚本 (类似 X-MILI 的 install.sh, 但编译本仓库源码)
#
# 用法:
#   一键:  bash <(curl -sL https://raw.githubusercontent.com/qzyfl/CatVPN/main/install.sh)
#   本地:  git clone https://github.com/qzyfl/CatVPN && cd CatVPN && bash install.sh
#   重装:  FORCE=1 bash install.sh
#
# 功能:
#   1. 现场编译本仓库定制的 x-ui (猫 Logo / 中文 / 无 GitHub·Telegram·产品推荐 推广)
#   2. 安装 systemd 服务 (默认中文 zh_CN)
#   3. 注册 Cloudflare WARP, 建立专供 VPNGate(130.158.75.0/24) 的 wg-warp 出口
#      —— 解决云厂商数据中心 IP 被 VPNGate 封禁、抓不到节点的问题
#   4. 安装 BBR v3 Max 内核并启用 BBR 拥塞控制
#
# 幂等: 已安装的部分会自动跳过, 可安全重复运行 (FORCE=1 强制重编/重装)。
set -e

APP_NAME="CatVPN"
REPO="https://github.com/qzyfl/CatVPN"
INSTALL_DIR="/usr/local/x-ui"
DATA_DIR="/etc/x-ui"
LANG_DIR="/etc/x-mili"
LANG_FILE="$LANG_DIR/lang"
PANEL_PORT="${PANEL_PORT:-2053}"

red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; plain='\033[0m'
log()  { echo -e "${green}[CatVPN]${plain} $*"; }
warn() { echo -e "${yellow}[CatVPN]${plain} $*"; }
fail() { echo -e "${red}[CatVPN]${plain} $*" >&2; exit 1; }
step() { echo -e "${green}[CatVPN]${plain} ${yellow}[$1/$2]${plain} $3"; }

[[ $EUID -ne 0 ]] && fail "请使用 root 运行 / Please run as root"

# ---------- 语言 ----------
choose_language() {
    [[ -f "$LANG_FILE" ]] && X_LANG=$(cat "$LANG_FILE")
    if [[ -z "$X_LANG" ]]; then
        echo -e "${green}1.${plain} 简体中文"
        echo -e "${green}2.${plain} English"
        read -rp "请选择语言 / Please choose language [1-2]: " choice
        [[ "$choice" == "2" ]] && X_LANG="en_US" || X_LANG="zh_CN"
        mkdir -p "$LANG_DIR"; echo "$X_LANG" > "$LANG_FILE"
    fi
}
is_zh() { [[ "$X_LANG" == "zh_CN" ]]; }
choose_language
is_zh && log "开始安装/更新 ${APP_NAME}" || log "Installing/updating ${APP_NAME}"

command -v systemctl >/dev/null 2>&1 || fail "需要 systemd / systemd is required"

# ---------- 运行依赖 ----------
install_runtime_deps() {
    is_zh && log "安装运行依赖与编译工具..." || log "Installing runtime deps and build tools..."
    if command -v apt-get >/dev/null 2>&1; then
        is_zh && warn "若系统自动更新占用 apt 锁, 将等待释放。" || warn "Waiting for apt/dpkg lock if needed."
        apt-get -o DPkg::Lock::Timeout=1800 update -qq
        apt-get -o DPkg::Lock::Timeout=1800 install -y -qq ca-certificates curl tar gzip git wget jq \
            build-essential wireguard-tools
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y ca-certificates curl tar gzip git wget jq gcc make wireguard-tools
    elif command -v yum >/dev/null 2>&1; then
        yum install -y ca-certificates curl tar gzip git wget jq gcc make wireguard-tools
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache ca-certificates curl tar gzip git wget jq build-base wireguard-tools
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm ca-certificates curl tar gzip git wget jq base-devel wireguard-tools
    elif command -v zypper >/dev/null 2>&1; then
        zypper refresh; zypper -q install -y ca-certificates curl tar gzip git wget jq gcc make wireguard-tools
    else
        fail "不支持的包管理器 / Unsupported package manager"
    fi
}

# ---------- 4G swap (小内存 VPS 编译防 OOM) ----------
ensure_swap() {
    MEM=$(free -m | sed -n "s/^Mem:[^0-9]*\([0-9]*\).*/\1/p")
    SWAP_TOTAL=$(free -m | awk "/^Swap:/{print \$2}")
    if [[ "$MEM" -lt 4096 ]] && [[ "$SWAP_TOTAL" -lt 4096 ]]; then
        is_zh && log "小内存(${MEM}M) 建 4G swap 防止编译 OOM..." || log "Low mem (${MEM}M): creating 4G swap to avoid build OOM..."
        swapoff /swapfile 2>/dev/null || true
        rm -f /swapfile
        fallocate -l 4G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=4096 status=none
        chmod 600 /swapfile; mkswap /swapfile >/dev/null; swapon /swapfile
    fi
}

# ---------- 安装 Go (若缺失) ----------
ensure_go() {
    if command -v /usr/local/go/bin/go >/dev/null 2>&1; then
        /usr/local/go/bin/go version
        return
    fi
    is_zh && log "安装 Go 工具链..." || log "Installing Go toolchain..."
    GOVER=$(curl -sL "https://go.dev/VERSION?m=text" | grep -oE "go[0-9]+\.[0-9]+(\.[0-9]+)?" | head -1)
    [[ -n "$GOVER" ]] || fail "无法获取 Go 版本 / Cannot fetch Go version"
    timeout 240 curl -sL "https://go.dev/dl/${GOVER}.linux-amd64.tar.gz" -o /tmp/go.tar.gz
    tar -C /usr/local -xzf /tmp/go.tar.gz && rm -f /tmp/go.tar.gz
    /usr/local/go/bin/go version
}

# ---------- 源码目录 (本地 clone 或 curl-clone) ----------
SRC_DIR=""
get_src_dir() {
    local here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$here/main.go" ]]; then
        SRC_DIR="$here"
        is_zh && log "使用本地仓库源码: $SRC_DIR" || log "Using local repo source: $SRC_DIR"
    else
        is_zh && log "克隆源码到 /tmp/catvpn-src ..." || log "Cloning source to /tmp/catvpn-src ..."
        rm -rf /tmp/catvpn-src
        git clone --depth 1 "$REPO" /tmp/catvpn-src
        SRC_DIR="/tmp/catvpn-src"
    fi
}

# ---------- 架构 ----------
detect_arch() {
    case "$(uname -m)" in
        x86_64 | amd64) echo "amd64" ;;
        aarch64 | arm64) echo "arm64" ;;
        i386 | i686) echo "i386" ;;
        *) echo "amd64" ;;
    esac
}

# ---------- 尝试下载预编译包 (对齐 X-MILI 模型) ----------
try_prebuilt() {
    local arch url pkg tmp_dir
    arch=$(detect_arch)
    local goarch="linux-${arch}"
    url="${REPO}/releases/latest/download/x-mili-${goarch}.tar.gz"
    tmp_dir=$(mktemp -d -t catvpn-prebuilt.XXXXXX)

    is_zh && log "尝试下载预编译包 (${goarch})..." || log "Trying prebuilt bundle (${goarch})..."
    if curl -fL --max-time 120 "$url" -o "$tmp_dir/pkg.tar.gz" 2>/dev/null; then
        if tar -xzf "$tmp_dir/pkg.tar.gz" -C "$tmp_dir" 2>/dev/null; then
            if [[ -x "$tmp_dir/x-ui" ]]; then
                mkdir -p "$INSTALL_DIR"
                cp "$tmp_dir/x-ui" "$INSTALL_DIR/x-ui"
                chmod +x "$INSTALL_DIR/x-ui"
                rm -rf "$tmp_dir"
                is_zh && log "已使用预编译包, 大小 $(stat -c%s "$INSTALL_DIR/x-ui") 字节" || log "Preinstalled, size $(stat -c%s "$INSTALL_DIR/x-ui") bytes"
                return 0
            fi
        fi
    fi
    rm -rf "$tmp_dir"
    return 1
}

# ---------- 编译面板 (fallback) ----------
build_panel() {
    if [[ -x "$INSTALL_DIR/x-ui" ]] && [[ "${FORCE:-0}" != "1" ]]; then
        is_zh && log "已存在二进制, 跳过编译 (FORCE=1 可强制重编)" || log "Binary exists, skip build (FORCE=1 to rebuild)"
        return
    fi

    # [优先] 尝试预编译包 (GitHub Actions 构建, 快速免编译)
    if try_prebuilt; then
        return
    fi

    # [fallback] 预编译不可用, 现场源码编译
    is_zh && warn "预编译包不可用, 切换到源码编译模式..." || warn "Prebuilt unavailable, falling back to source build..."
    ensure_swap
    ensure_go
    is_zh && step 3 6 "编译 CatVPN 定制面板 (源码 fallback)" || step 3 6 "Building CatVPN panel (source fallback)"
    cd "$SRC_DIR"
    rm -f pow_alps.c
    export PATH="$PATH:/usr/local/go/bin"
    export GOPROXY="https://goproxy.cn,direct"
    export CGO_ENABLED=1
    export GOMAXPROCS=1
    mkdir -p "$INSTALL_DIR"
    timeout 1500 go build -o "$INSTALL_DIR/x-ui" . || fail "编译失败 / Build failed"
    is_zh && log "编译完成, 大小 $(stat -c%s "$INSTALL_DIR/x-ui" 2>/dev/null) 字节" || log "Build done, size $(stat -c%s "$INSTALL_DIR/x-ui" 2>/dev/null) bytes"
}

# ---------- 安装程序文件 + 默认中文 ----------
install_program_files() {
    is_zh && step 4 6 "安装程序文件 (默认中文)" || step 4 6 "Installing program files (default zh_CN)"
    mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$LANG_DIR"
    # 默认中文; 若用户选了英文则用英文
    echo "$X_LANG" > "$LANG_FILE"
}

# ---------- 初始化面板账号 ----------
gen_random_string() { tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "$1"; }

init_panel_settings() {
    is_zh && step 5 6 "配置面板账号/端口/安全后缀" || step 5 6 "Configuring panel login/port/secure suffix"
    local info; info=$("$INSTALL_DIR/x-ui" setting -show true 2>/dev/null || true)
    if echo "$info" | grep -q "hasDefaultCredential: true"; then
        local user pass port path
        user="${CATVPN_USERNAME:-$(gen_random_string 10)}"
        pass="${CATVPN_PASSWORD:-$(gen_random_string 18)}"
        port="${PANEL_PORT}"
        path="/$(gen_random_string 16)/"
        "$INSTALL_DIR/x-ui" setting -username "$user" -password "$pass" -port "$port" -resetTwoFactor true >/dev/null 2>&1 || true
        "$INSTALL_DIR/x-ui" setting -webBasePath "$path" >/dev/null 2>&1 || true
        PANEL_USER="$user"; PANEL_PASS="$pass"; PANEL_PATH="$path"
        panel_initialized=1
        is_zh && log "已生成随机账号/密码/端口/访问路径" || log "Generated random username/password/port/path"
    else
        is_zh && log "检测到已有非默认账号, 保留现有登录信息" || log "Existing non-default account detected, keeping it"
        panel_initialized=0
    fi
}

# ---------- systemd 服务 ----------
install_service() {
    is_zh && step 6 6 "安装并启动系统服务" || step 6 6 "Installing and starting system service"
    cat > /etc/systemd/system/x-ui.service <<EOF
[Unit]
Description=CatVPN (x-ui) Service
After=network.target
Wants=network.target

[Service]
Environment="XRAY_VMESS_AEAD_FORCED=false"
Type=simple
WorkingDirectory=${INSTALL_DIR}/
ExecStart=${INSTALL_DIR}/x-ui
ExecReload=kill -USR1 \$MAINPID
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl restart x-ui || systemctl start x-ui
    sleep 3
    systemctl is-active x-ui >/dev/null 2>&1 && log "x-ui active" || warn "x-ui 未 active, 请检查日志"
}

# ---------- WARP / VPNGate 出口 ----------
setup_warp() {
    if [[ -f /etc/wireguard/wg-warp.conf ]] && wg show wg-warp >/dev/null 2>&1; then
        is_zh && log "wg-warp 已存在且活跃, 跳过" || log "wg-warp already up, skip"
        return
    fi
    is_zh && log "配置 Cloudflare WARP (wg-warp 专供 VPNGate 130.158.75.0/24)..." || log "Setting up Cloudflare WARP (wg-warp for VPNGate 130.158.75.0/24)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq wireguard-tools 2>/dev/null || true
    modprobe wireguard || true
    if [[ ! -x /usr/local/bin/wgcf ]]; then
        curl -sL -o /usr/local/bin/wgcf "https://github.com/ViRb3/wgcf/releases/download/v2.2.32/wgcf_2.2.32_linux_amd64" && chmod +x /usr/local/bin/wgcf
    fi
    mkdir -p /etc/wireguard && cd /etc/wireguard
    [[ -f wgcf-account.toml ]] || wgcf register --accept-tos
    wgcf generate
    python3 - <<'PY'
import re, sys
try:
    src = open("wgcf-profile.conf").read()
    pk = re.search(r"PrivateKey = (\S+)", src).group(1)
    addr = re.search(r"Address = (\S+)", src).group(1).split(",")[0]
    peer = re.search(r"PublicKey = (\S+)", src).group(1)
    ep = re.search(r"Endpoint = (\S+)", src).group(1)
    src_ip = addr.split("/")[0]
except AttributeError as e:
    print("[ERROR] wgcf-profile.conf parse failed:", e, file=sys.stderr); sys.exit(1)
conf = """[Interface]
PrivateKey = %s
Address = %s
Table = off
PostUp = ip route add 130.158.75.0/24 dev %%i; iptables -t nat -A POSTROUTING -o %%i -j SNAT --to-source %s
PreDown = ip route del 130.158.75.0/24 dev %%i; iptables -t nat -D POSTROUTING -o %%i -j SNAT --to-source %s

[Peer]
PublicKey = %s
Endpoint = %s
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
""" % (pk, addr, src_ip, src_ip, peer, ep)
open("/etc/wireguard/wg-warp.conf", "w").write(conf)
print("wg-warp.conf written, src_ip=", src_ip)
PY
    wg-quick down wg-warp 2>/dev/null || true
    wg-quick up wg-warp
    systemctl enable wg-quick@wg-warp 2>/dev/null || true
    sleep 2
    ip route get 130.158.75.44 >/dev/null 2>&1 && log "VPNGate 路由经 wg-warp OK" || warn "VPNGate 路由未命中, 请检查"
}

# ---------- BBR v3 Max 内核 ----------
setup_bbr() {
    if uname -r | grep -q bbrv3-max; then
        is_zh && log "已是 BBR v3 Max 内核, 跳过" || log "Already BBR v3 Max kernel, skip"
        return
    fi
    is_zh && log "安装 BBR v3 Max 内核..." || log "Installing BBR v3 Max kernel..."
    ARCH=$(uname -m); AFILTER="x86_64"; [[ "$ARCH" == "aarch64" ]] && AFILTER="arm64"
    API="https://api.github.com/repos/byJoey/Actions-bbr-v3/releases"
    TAG=""
    for i in 1 2 3; do
        DATA=$(curl -s "${API}")
        TAG=$(echo "$DATA" | jq -r --arg f "$AFILTER" 'map(select(.tag_name|test("^"+$f+"-[0-9]";"i"))|select(.tag_name|endswith("-max")))|sort_by(.published_at)|.[-1].tag_name')
        [[ -n "$TAG" && "$TAG" != "null" ]] && break
        sleep 5
    done
    if [[ -z "$TAG" || "$TAG" == "null" ]]; then
        warn "无法获取 BBR 版本(API限流?), 跳过 BBR 安装"
        return
    fi
    is_zh && log "BBR max tag: $TAG" || log "BBR max tag: $TAG"
    ASSETS=$(echo "$DATA" | jq -r --arg t "$TAG" '.[]|select(.tag_name==$t)|.assets[].browser_download_url|select(test("(-dbg_|-dbgsym_)";"i")|not)')
    rm -f /tmp/linux-*.deb
    for U in $ASSETS; do wget -q "$U" -P /tmp/ || warn "下载失败: $U"; done
    if ! ls /tmp/linux-*.deb >/dev/null 2>&1; then warn "无可用 deb, 跳过 BBR"; return; fi
    dpkg -i /tmp/linux-*.deb && update-grub
    rm -f /tmp/linux-*.deb
    NEED_REBOOT=1
    is_zh && log "BBR 内核已装, 稍后重启生效" || log "BBR kernel installed, reboot to activate"
}

# ---------- 收尾验证 ----------
print_guide() {
    local info port web_path server_ip protocol
    info=$("$INSTALL_DIR/x-ui" setting -show true 2>/dev/null || true)
    port=$(echo "$info" | awk '/^port:/{print $2; exit}')
    web_path=$(echo "$info" | awk '/^webBasePath:/{print $2; exit}')
    port="${port:-$PANEL_PORT}"; web_path="${web_path:-/}"
    server_ip=$(curl -s --max-time 3 https://api.ipify.org || true); [[ -n "$server_ip" ]] || server_ip=$(curl -s --max-time 3 https://4.ident.me || true); [[ -n "$server_ip" ]] || server_ip="服务器IP"
    echo ""
    if is_zh; then
        echo -e "${green}============ ${APP_NAME} 安装完成 ============${plain}"
        echo -e "面板地址: ${green}http://${server_ip}:${port}${web_path}${plain}"
        [[ "$panel_initialized" == "1" ]] && { echo -e "登录账号: ${green}${PANEL_USER}${plain}"; echo -e "登录密码: ${green}${PANEL_PASS}${plain}"; echo -e "安全后缀: ${green}${web_path}${plain}"; } || echo -e "登录信息: ${yellow}已保留现有账号和密码${plain}"
        echo -e "WARP 出口: ${green}wg-warp (VPNGate 130.158.75.0/24)${plain}"
        echo -e "BBR: ${green}$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)${plain}"
        echo -e "${green}=============================================${plain}"
    else
        echo -e "${green}============ ${APP_NAME} Installed ============${plain}"
        echo -e "URL: ${green}http://${server_ip}:${port}${web_path}${plain}"
        [[ "$panel_initialized" == "1" ]] && { echo -e "Username: ${green}${PANEL_USER}${plain}"; echo -e "Password: ${green}${PANEL_PASS}${plain}"; echo -e "Secure suffix: ${green}${web_path}${plain}"; } || echo -e "Login: ${yellow}existing credentials preserved${plain}"
        echo -e "WARP egress: ${green}wg-warp (VPNGate 130.158.75.0/24)${plain}"
        echo -e "BBR: ${green}$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)${plain}"
        echo -e "${green}=============================================${plain}"
    fi
    echo ""
}

# ---------- 主流程 ----------
panel_initialized=0; NEED_REBOOT=0
is_zh && step 1 6 "安装运行依赖" || step 1 6 "Installing runtime deps"
install_runtime_deps
is_zh && step 2 6 "获取源码" || step 2 6 "Fetching source"
get_src_dir
build_panel
install_program_files
init_panel_settings
install_service
setup_warp
setup_bbr

# 重启前先写好 BBR sysctl (重启后自动生效)
cat > /etc/sysctl.d/99-catvpn.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system >/dev/null 2>&1 || true

print_guide

if [[ "$NEED_REBOOT" == "1" ]]; then
    is_zh && warn "已安装 BBR v3 Max 新内核, 即将重启以生效 (重启后 BBR 自动启用)。" || warn "New BBR v3 Max kernel installed, rebooting to activate."
    sleep 3
    reboot || true
fi
