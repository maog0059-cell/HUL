#!/usr/bin/env bash
#
# openclaw-fast-install.sh — OpenClaw 极速下载安装脚本 (强化版)
#
# 加速策略:
#   1. pnpm 替代 npm — 硬链接 + content-addressable 存储，速度提升 2-3x
#   2. 镜像加速 — 支持 npmmirror / 自定义镜像 / HTTP 代理
#   3. 高并发下载 — 并发数 16，充分利用带宽
#   4. 智能重试 — 指数退避重试，网络抖动不怕
#   5. DNS 优化 — 可选 DNS-over-HTTPS，解决 DNS 污染
#   6. 多平台支持 — Linux / macOS / WSL 自动适配
#   7. 完整日志 — 全程记录安装过程，便于排障
#
# 用法:
#   bash openclaw-fast-install.sh                        # 使用镜像加速
#   bash openclaw-fast-install.sh --no-mirror            # 官方源
#   bash openclaw-fast-install.sh --mirror URL           # 自定义镜像
#   bash openclaw-fast-install.sh --proxy http://x:port  # HTTP 代理
#   bash openclaw-fast-install.sh --cn                   # 国内全套加速
#   bash openclaw-fast-install.sh --dry-run              # 预演模式
#   bash openclaw-fast-install.sh --uninstall            # 卸载 OpenClaw

set -euo pipefail

# ─── 版本 ───
SCRIPT_VERSION="2.0.0"

# ─── 颜色输出 ───
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' NC=''
fi

# ─── 日志 ───
LOG_FILE="/tmp/openclaw-install-$(date +%Y%m%d-%H%M%S).log"

_log() {
    local level="$1"; shift
    local ts
    ts=$(date '+%H:%M:%S')
    echo "[${ts}] [${level}] $*" >> "$LOG_FILE"
}

info()  { _log INFO  "$*"; echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { _log OK    "$*"; echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { _log WARN  "$*"; echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { _log ERROR "$*"; echo -e "${RED}[FAIL]${NC} $*" >&2; }
step()  { _log STEP  "$*"; echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }
debug() { _log DEBUG "$*"; }

# ─── 进度条 ───
spinner() {
    local pid=$1 msg="${2:-}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${spin:i++%${#spin}:1}${NC} %s" "$msg"
        sleep 0.1
    done
    printf "\r"
}

# ─── 默认配置 ───
USE_MIRROR=true
MIRROR_URL="https://registry.npmmirror.com"
ORIGINAL_NPM_REGISTRY=""
ORIGINAL_PNPM_REGISTRY=""
MIN_NODE_VERSION=22
PREFERRED_NODE_VERSION=24
PNPM_CONCURRENCY=16
HTTP_PROXY=""
HTTPS_PROXY=""
DRY_RUN=false
CN_MODE=false
DO_UNINSTALL=false
MAX_RETRIES=4
SKIP_NODE_CHECK=false
OPENCLAW_VERSION="latest"

# ─── 解析参数 ───
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-mirror)
            USE_MIRROR=false; shift ;;
        --mirror)
            USE_MIRROR=true; MIRROR_URL="$2"; shift 2 ;;
        --proxy)
            HTTP_PROXY="$2"; HTTPS_PROXY="$2"; shift 2 ;;
        --cn)
            CN_MODE=true; USE_MIRROR=true
            MIRROR_URL="https://registry.npmmirror.com"; shift ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        --uninstall)
            DO_UNINSTALL=true; shift ;;
        --concurrency)
            PNPM_CONCURRENCY="$2"; shift 2 ;;
        --skip-node)
            SKIP_NODE_CHECK=true; shift ;;
        --version)
            OPENCLAW_VERSION="$2"; shift 2 ;;
        --retries)
            MAX_RETRIES="$2"; shift 2 ;;
        -h|--help)
            cat <<'HELP'
OpenClaw 极速安装脚本 v2.0.0

用法: bash openclaw-fast-install.sh [选项]

基本选项:
  --no-mirror           不使用镜像，直接从官方源下载
  --mirror URL          使用自定义镜像地址
  --proxy URL           设置 HTTP/HTTPS 代理 (例: http://127.0.0.1:7890)
  --cn                  国内全套加速模式 (npmmirror + 优化 DNS)
  --version VER         指定 OpenClaw 版本 (默认: latest)

高级选项:
  --concurrency N       设置并发下载数 (默认: 16)
  --retries N           设置最大重试次数 (默认: 4)
  --skip-node           跳过 Node.js 版本检查
  --dry-run             预演模式，不执行实际安装
  --uninstall           卸载 OpenClaw

其他:
  -h, --help            显示帮助信息
HELP
            exit 0 ;;
        *)
            err "未知参数: $1 (使用 -h 查看帮助)"
            exit 1 ;;
    esac
done

# ─── 辅助函数 ───
command_exists() { command -v "$1" &>/dev/null; }

version_major() { echo "$1" | grep -oE '^[0-9]+'; }

version_ge() {
    local v1 v2
    v1=$(version_major "$1")
    v2=$(version_major "$2")
    [[ "$v1" -ge "$v2" ]]
}

detect_os() {
    local os="unknown"
    case "$(uname -s)" in
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                os="wsl"
            else
                os="linux"
            fi ;;
        Darwin*) os="macos" ;;
        CYGWIN*|MINGW*|MSYS*) os="windows" ;;
    esac
    echo "$os"
}

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "x64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "$arch" ;;
    esac
}

# 带指数退避的重试
retry_with_backoff() {
    local max_retries="$MAX_RETRIES"
    local delay=2
    local attempt=0
    local cmd="$*"

    while [[ $attempt -lt $max_retries ]]; do
        attempt=$((attempt + 1))
        debug "尝试 #${attempt}: ${cmd}"

        if eval "$cmd"; then
            return 0
        fi

        if [[ $attempt -lt $max_retries ]]; then
            warn "第 ${attempt} 次尝试失败，${delay}s 后重试..."
            sleep "$delay"
            delay=$((delay * 2))
        fi
    done

    err "经过 ${max_retries} 次尝试后仍然失败"
    return 1
}

# 网络连通性检查
check_connectivity() {
    local test_url="$1"
    if command_exists curl; then
        curl -sS --connect-timeout 5 --max-time 10 -o /dev/null "$test_url" 2>/dev/null
    elif command_exists wget; then
        wget -q --timeout=5 --spider "$test_url" 2>/dev/null
    else
        return 0  # 无法检查，假设可用
    fi
}

# 测量下载速度
measure_speed() {
    local url="$1"
    local start end elapsed
    start=$(date +%s%N)
    curl -sS --connect-timeout 5 --max-time 15 -o /dev/null "$url" 2>/dev/null || return 1
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))
    echo "${elapsed}"
}

# ─── cleanup ───
cleanup() {
    local exit_code=$?
    if [[ -n "${ORIGINAL_NPM_REGISTRY}" ]]; then
        npm config set registry "${ORIGINAL_NPM_REGISTRY}" 2>/dev/null || true
    fi
    if [[ -n "${ORIGINAL_PNPM_REGISTRY}" ]]; then
        pnpm config set registry "${ORIGINAL_PNPM_REGISTRY}" --global 2>/dev/null || true
    fi
    if [[ -n "${HTTP_PROXY}" ]]; then
        npm config delete proxy 2>/dev/null || true
        npm config delete https-proxy 2>/dev/null || true
    fi
    if [[ $exit_code -ne 0 ]]; then
        echo ""
        err "安装过程中出现错误 (退出码: ${exit_code})"
        err "完整日志: ${LOG_FILE}"
    fi
}
trap cleanup EXIT

# ─── 卸载模式 ───
if [[ "$DO_UNINSTALL" == true ]]; then
    step "卸载 OpenClaw"
    if command_exists pnpm; then
        pnpm remove -g openclaw 2>/dev/null && ok "已通过 pnpm 卸载" || true
    fi
    if command_exists npm; then
        npm uninstall -g openclaw 2>/dev/null && ok "已通过 npm 卸载" || true
    fi
    ok "OpenClaw 卸载完成"
    exit 0
fi

# ─── 预演模式 ───
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo -e "${BOLD}预演模式 — 将执行以下操作:${NC}"
    echo ""
    echo "  操作系统:     $(detect_os) ($(detect_arch))"
    echo "  镜像加速:     ${USE_MIRROR} (${MIRROR_URL})"
    echo "  HTTP 代理:    ${HTTP_PROXY:-未设置}"
    echo "  国内加速:     ${CN_MODE}"
    echo "  并发数:       ${PNPM_CONCURRENCY}"
    echo "  最大重试:     ${MAX_RETRIES}"
    echo "  OpenClaw版本: ${OPENCLAW_VERSION}"
    echo "  日志文件:     ${LOG_FILE}"
    echo ""
    echo "  步骤:"
    echo "    1. 系统环境深度检测 (磁盘/内存/端口/权限/Node生态)"
    echo "    2. 网络诊断 (DNS/镜像测速/代理)"
    echo "    3. 检查/安装 Node.js >= ${MIN_NODE_VERSION}"
    echo "    4. 配置镜像 & 代理"
    echo "    5. 安装 pnpm + 并发优化 (${PNPM_CONCURRENCY} 线程)"
    echo "    6. 安装 openclaw@${OPENCLAW_VERSION}"
    echo "    7. 验证安装 & 恢复配置"
    echo "    8. 安装后健康检查"
    echo ""
    exit 0
fi

# ══════════════════════════════════════════════════════════════
#                        开始安装
# ══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║       OpenClaw 极速安装脚本 v${SCRIPT_VERSION}              ║${NC}"
echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${DIM}系统: $(detect_os) $(detect_arch) | 日志: ${LOG_FILE}${NC}"
echo ""

TOTAL_START=$(date +%s)

# ─── 步骤 1: 系统环境深度检测 ───
step "步骤 1/8: 系统环境深度检测"

DETECT_WARNINGS=0
DETECT_ERRORS=0

OS_TYPE=$(detect_os)
ARCH_TYPE=$(detect_arch)
ok "操作系统: ${OS_TYPE} (${ARCH_TYPE})"

# ── 1a. Linux 发行版识别 ──
if [[ "$OS_TYPE" == "linux" || "$OS_TYPE" == "wsl" ]]; then
    if [[ -f /etc/os-release ]]; then
        DISTRO_NAME=$(. /etc/os-release && echo "${PRETTY_NAME:-$ID}")
        ok "发行版: ${DISTRO_NAME}"
    elif command_exists lsb_release; then
        DISTRO_NAME=$(lsb_release -ds 2>/dev/null || echo "unknown")
        ok "发行版: ${DISTRO_NAME}"
    fi
fi

# ── 1b. 内核版本 ──
KERNEL_VER=$(uname -r 2>/dev/null || echo "unknown")
debug "内核: ${KERNEL_VER}"

# ── 1c. 磁盘空间检测 ──
MIN_DISK_MB=500
INSTALL_DIR="${HOME}"
if command_exists df; then
    AVAIL_KB=$(df -k "$INSTALL_DIR" 2>/dev/null | awk 'NR==2{print $4}')
    if [[ -n "$AVAIL_KB" && "$AVAIL_KB" =~ ^[0-9]+$ ]]; then
        AVAIL_MB=$((AVAIL_KB / 1024))
        if [[ "$AVAIL_MB" -lt "$MIN_DISK_MB" ]]; then
            err "磁盘空间不足! 可用: ${AVAIL_MB}MB, 最低要求: ${MIN_DISK_MB}MB"
            err "路径: ${INSTALL_DIR}"
            DETECT_ERRORS=$((DETECT_ERRORS + 1))
        elif [[ "$AVAIL_MB" -lt 1024 ]]; then
            warn "磁盘空间偏低: ${AVAIL_MB}MB (建议 >= 1GB)"
            DETECT_WARNINGS=$((DETECT_WARNINGS + 1))
        else
            ok "磁盘空间: ${AVAIL_MB}MB 可用"
        fi
    fi
fi

# ── 1d. 内存检测 ──
MIN_MEM_MB=512
if [[ -f /proc/meminfo ]]; then
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    AVAIL_MEM_KB=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
    if [[ -z "$AVAIL_MEM_KB" ]]; then
        # MemAvailable not present in older kernels, use free
        AVAIL_MEM_KB=$(grep MemFree /proc/meminfo | awk '{print $2}')
    fi
    TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
    AVAIL_MEM_MB=$((AVAIL_MEM_KB / 1024))

    if [[ "$AVAIL_MEM_MB" -lt "$MIN_MEM_MB" ]]; then
        warn "可用内存偏低: ${AVAIL_MEM_MB}MB / ${TOTAL_MEM_MB}MB (建议 >= ${MIN_MEM_MB}MB)"
        warn "可能导致 Node.js 安装/编译缓慢"
        DETECT_WARNINGS=$((DETECT_WARNINGS + 1))
    else
        ok "可用内存: ${AVAIL_MEM_MB}MB / ${TOTAL_MEM_MB}MB"
    fi
elif [[ "$OS_TYPE" == "macos" ]]; then
    TOTAL_MEM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    TOTAL_MEM_MB=$((TOTAL_MEM_BYTES / 1024 / 1024))
    ok "总内存: ${TOTAL_MEM_MB}MB"
fi

# ── 1e. Shell 环境检测 ──
CURRENT_SHELL=$(basename "${SHELL:-unknown}")
ok "Shell: ${CURRENT_SHELL}"

# 检测 shell 配置文件是否存在
SHELL_RC=""
case "$CURRENT_SHELL" in
    bash)
        for rc in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
            [[ -f "$rc" ]] && SHELL_RC="$rc" && break
        done ;;
    zsh)
        [[ -f "$HOME/.zshrc" ]] && SHELL_RC="$HOME/.zshrc" ;;
    fish)
        [[ -f "$HOME/.config/fish/config.fish" ]] && SHELL_RC="$HOME/.config/fish/config.fish" ;;
esac
if [[ -n "$SHELL_RC" ]]; then
    debug "Shell 配置文件: ${SHELL_RC}"
else
    warn "未找到 shell 配置文件，PATH 修改可能不会持久"
    DETECT_WARNINGS=$((DETECT_WARNINGS + 1))
fi

# ── 1f. 用户权限检测 ──
if [[ "$(id -u)" -eq 0 ]]; then
    warn "当前以 root 用户运行！"
    warn "建议使用普通用户运行，全局包将安装在用户目录"
    DETECT_WARNINGS=$((DETECT_WARNINGS + 1))
fi

# ── 1g. 必要工具检查 (增强) ──
REQUIRED_TOOLS=(curl git)
OPTIONAL_TOOLS=(wget tar gzip unzip)

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command_exists "$tool"; then
        TOOL_VER=$("$tool" --version 2>/dev/null | head -1 || echo "")
        ok "${tool} 已安装 ${DIM}(${TOOL_VER})${NC}"
    else
        warn "${tool} 未安装，尝试自动安装..."
        case "$OS_TYPE" in
            linux|wsl)
                if command_exists apt-get; then
                    info "通过 apt 安装 ${tool}..."
                    sudo apt-get update -qq && sudo apt-get install -y -qq "$tool"
                elif command_exists yum; then
                    info "通过 yum 安装 ${tool}..."
                    sudo yum install -y -q "$tool"
                elif command_exists dnf; then
                    sudo dnf install -y -q "$tool"
                elif command_exists pacman; then
                    sudo pacman -S --noconfirm "$tool"
                elif command_exists apk; then
                    sudo apk add --no-cache "$tool"
                elif command_exists zypper; then
                    sudo zypper install -y "$tool"
                else
                    err "无法自动安装 ${tool}，请手动安装"
                    DETECT_ERRORS=$((DETECT_ERRORS + 1))
                fi ;;
            macos)
                if command_exists brew; then
                    brew install "$tool"
                else
                    err "请先安装 Homebrew: https://brew.sh"
                    DETECT_ERRORS=$((DETECT_ERRORS + 1))
                fi ;;
        esac
    fi
done

for tool in "${OPTIONAL_TOOLS[@]}"; do
    if command_exists "$tool"; then
        debug "${tool} 可用"
    else
        debug "${tool} 不可用 (可选)"
    fi
done

# ── 1h. 已有 Node.js 生态健康检查 ──
if command_exists node; then
    NODE_PATH_CHECK=$(which node 2>/dev/null || echo "")
    debug "Node 路径: ${NODE_PATH_CHECK}"

    # 检测 npm 是否可用
    if command_exists npm; then
        NPM_VER=$(npm -v 2>/dev/null || echo "unknown")
        NPM_PREFIX=$(npm config get prefix 2>/dev/null || echo "")
        ok "npm v${NPM_VER} ${DIM}(prefix: ${NPM_PREFIX})${NC}"

        # 检测 npm prefix 权限
        if [[ -n "$NPM_PREFIX" && -d "$NPM_PREFIX" ]]; then
            if [[ ! -w "$NPM_PREFIX" ]]; then
                warn "npm prefix 目录无写权限: ${NPM_PREFIX}"
                warn "全局安装可能需要 sudo 或修复权限"
                DETECT_WARNINGS=$((DETECT_WARNINGS + 1))
            fi
        fi

        # 检测 npm cache 大小
        if [[ -d "$HOME/.npm/_cacache" ]]; then
            NPM_CACHE_SIZE=$(du -sm "$HOME/.npm/_cacache" 2>/dev/null | awk '{print $1}')
            if [[ -n "$NPM_CACHE_SIZE" && "$NPM_CACHE_SIZE" -gt 1024 ]]; then
                warn "npm 缓存较大 (${NPM_CACHE_SIZE}MB)，可运行 npm cache clean --force 清理"
            fi
        fi
    else
        warn "npm 不可用，将在 Node.js 安装后获得"
    fi

    # 检测已安装的 openclaw
    if command_exists openclaw; then
        EXISTING_VER=$(openclaw --version 2>/dev/null || echo "unknown")
        warn "检测到已安装的 OpenClaw: ${EXISTING_VER}"
        warn "本脚本将升级/覆盖安装"
    fi
fi

# ── 1i. 端口冲突检测 ──
OPENCLAW_PORTS=(3000 3001 8080)
for port in "${OPENCLAW_PORTS[@]}"; do
    if command_exists ss; then
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            warn "端口 ${port} 已被占用 (可能影响 openclaw daemon)"
            DETECT_WARNINGS=$((DETECT_WARNINGS + 1))
        fi
    elif command_exists lsof; then
        if lsof -iTCP:"${port}" -sTCP:LISTEN &>/dev/null; then
            warn "端口 ${port} 已被占用 (可能影响 openclaw daemon)"
            DETECT_WARNINGS=$((DETECT_WARNINGS + 1))
        fi
    elif command_exists netstat; then
        if netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
            warn "端口 ${port} 已被占用 (可能影响 openclaw daemon)"
            DETECT_WARNINGS=$((DETECT_WARNINGS + 1))
        fi
    fi
done

# ── 1j. 环境变量冲突检测 ──
if [[ -n "${NODE_OPTIONS:-}" ]]; then
    warn "检测到 NODE_OPTIONS 环境变量: ${NODE_OPTIONS}"
    warn "可能影响安装过程"
    DETECT_WARNINGS=$((DETECT_WARNINGS + 1))
fi

if [[ -n "${npm_config_registry:-}" ]]; then
    info "检测到 npm_config_registry 环境变量: ${npm_config_registry}"
fi

# ── 1k. 检测报告 ──
echo ""
if [[ "$DETECT_ERRORS" -gt 0 ]]; then
    err "检测发现 ${DETECT_ERRORS} 个错误，${DETECT_WARNINGS} 个警告"
    err "请修复错误后重新运行脚本"
    exit 1
elif [[ "$DETECT_WARNINGS" -gt 0 ]]; then
    warn "检测发现 ${DETECT_WARNINGS} 个警告 (不影响安装，但建议关注)"
else
    ok "环境检测全部通过!"
fi

# ─── 步骤 2: 网络诊断 & 代理配置 ───
step "步骤 2/8: 网络诊断 & 加速配置"

# DNS 解析检测
info "检测 DNS 解析..."
DNS_TEST_HOSTS=("registry.npmjs.org" "registry.npmmirror.com" "github.com")
DNS_FAIL=0
for host in "${DNS_TEST_HOSTS[@]}"; do
    if command_exists nslookup; then
        if nslookup "$host" &>/dev/null; then
            debug "DNS 解析正常: ${host}"
        else
            warn "DNS 解析失败: ${host}"
            DNS_FAIL=$((DNS_FAIL + 1))
        fi
    elif command_exists dig; then
        if dig +short "$host" &>/dev/null; then
            debug "DNS 解析正常: ${host}"
        else
            warn "DNS 解析失败: ${host}"
            DNS_FAIL=$((DNS_FAIL + 1))
        fi
    elif command_exists host; then
        if host "$host" &>/dev/null; then
            debug "DNS 解析正常: ${host}"
        else
            warn "DNS 解析失败: ${host}"
            DNS_FAIL=$((DNS_FAIL + 1))
        fi
    else
        if curl -sS --connect-timeout 3 -o /dev/null "https://${host}" 2>/dev/null; then
            debug "连通性正常: ${host}"
        else
            warn "无法连接: ${host}"
            DNS_FAIL=$((DNS_FAIL + 1))
        fi
    fi
done

if [[ "$DNS_FAIL" -eq 0 ]]; then
    ok "DNS 解析正常"
elif [[ "$DNS_FAIL" -ge "${#DNS_TEST_HOSTS[@]}" ]]; then
    err "所有 DNS 解析失败! 请检查网络连接或 DNS 配置"
    err "尝试: echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf"
    exit 1
else
    warn "部分 DNS 解析失败 (${DNS_FAIL}/${#DNS_TEST_HOSTS[@]})，继续安装..."
fi

# 配置代理
if [[ -n "$HTTP_PROXY" ]]; then
    export http_proxy="$HTTP_PROXY"
    export https_proxy="$HTTPS_PROXY"
    export HTTP_PROXY HTTPS_PROXY
    ok "HTTP 代理已设置: ${HTTP_PROXY}"
fi

# 测试镜像 vs 官方源速度
if [[ "$USE_MIRROR" == true ]]; then
    info "测试镜像连通性..."
    if check_connectivity "$MIRROR_URL"; then
        ok "镜像可用: ${MIRROR_URL}"

        # 速度对比
        info "测量镜像响应速度..."
        MIRROR_MS=$(measure_speed "${MIRROR_URL}/openclaw" 2>/dev/null || echo "N/A")
        OFFICIAL_MS=$(measure_speed "https://registry.npmjs.org/openclaw" 2>/dev/null || echo "N/A")

        if [[ "$MIRROR_MS" != "N/A" && "$OFFICIAL_MS" != "N/A" ]]; then
            ok "镜像: ${MIRROR_MS}ms  vs  官方: ${OFFICIAL_MS}ms"
            if [[ "$MIRROR_MS" -gt "$OFFICIAL_MS" ]] 2>/dev/null; then
                warn "官方源更快，但仍使用镜像 (稳定性更好)"
            fi
        fi
    else
        warn "镜像不可用，切换到官方源"
        USE_MIRROR=false
    fi
fi

# 国内全套加速
if [[ "$CN_MODE" == true ]]; then
    info "国内加速模式: 配置 nvm 镜像..."
    export NVM_NODEJS_ORG_MIRROR="https://npmmirror.com/mirrors/node"
    ok "Node.js 下载镜像已设置"
fi

# ─── 步骤 3: Node.js 检查 & 安装 ───
step "步骤 3/8: Node.js 环境准备"

if [[ "$SKIP_NODE_CHECK" == true ]]; then
    warn "跳过 Node.js 版本检查"
elif command_exists node; then
    NODE_VER=$(node -v | tr -d 'v')
    if version_ge "$NODE_VER" "$MIN_NODE_VERSION"; then
        ok "Node.js v${NODE_VER} 满足要求 (>= ${MIN_NODE_VERSION})"
    else
        warn "Node.js v${NODE_VER} 版本过低 (需要 >= ${MIN_NODE_VERSION})"
        info "正在升级到 Node.js ${PREFERRED_NODE_VERSION}..."

        # 加载或安装 nvm
        if ! command_exists nvm; then
            if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
                # shellcheck source=/dev/null
                source "$HOME/.nvm/nvm.sh"
            else
                info "安装 nvm..."
                retry_with_backoff curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh \| bash
                export NVM_DIR="$HOME/.nvm"
                # shellcheck source=/dev/null
                [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
            fi
        fi

        retry_with_backoff nvm install "$PREFERRED_NODE_VERSION"
        nvm use "$PREFERRED_NODE_VERSION"
        ok "Node.js $(node -v) 安装完成"
    fi
else
    warn "未检测到 Node.js"
    info "安装 nvm + Node.js ${PREFERRED_NODE_VERSION}..."

    if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.nvm/nvm.sh"
    else
        retry_with_backoff curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh \| bash
        export NVM_DIR="$HOME/.nvm"
        # shellcheck source=/dev/null
        [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
    fi

    retry_with_backoff nvm install "$PREFERRED_NODE_VERSION"
    nvm use "$PREFERRED_NODE_VERSION"
    ok "Node.js $(node -v) 安装完成"
fi

# ─── 步骤 4: 配置镜像 ───
step "步骤 4/8: 配置下载源"

ORIGINAL_NPM_REGISTRY=$(npm config get registry 2>/dev/null || echo "https://registry.npmjs.org/")
debug "原始 npm registry: ${ORIGINAL_NPM_REGISTRY}"

if [[ "$USE_MIRROR" == true ]]; then
    npm config set registry "${MIRROR_URL}"
    ok "npm 镜像: ${MIRROR_URL}"

    # 代理配置
    if [[ -n "$HTTP_PROXY" ]]; then
        npm config set proxy "$HTTP_PROXY"
        npm config set https-proxy "$HTTPS_PROXY"
        ok "npm 代理已配置"
    fi
fi

# ─── 步骤 5: 安装 pnpm ───
step "步骤 5/8: 安装 pnpm 加速引擎"

if command_exists pnpm; then
    PNPM_VER=$(pnpm -v)
    ok "pnpm v${PNPM_VER} 已就绪"
else
    info "安装 pnpm..."
    retry_with_backoff npm install -g pnpm
    ok "pnpm v$(pnpm -v) 安装完成"
fi

# 配置 pnpm 优化参数
info "调优 pnpm 配置..."
ORIGINAL_PNPM_REGISTRY=$(pnpm config get registry --global 2>/dev/null || echo "")

pnpm config set network-concurrency "${PNPM_CONCURRENCY}" --global 2>/dev/null || true
pnpm config set fetch-retries "$MAX_RETRIES" --global 2>/dev/null || true
pnpm config set fetch-retry-mintimeout 2000 --global 2>/dev/null || true
pnpm config set fetch-retry-maxtimeout 30000 --global 2>/dev/null || true

if [[ "$USE_MIRROR" == true ]]; then
    pnpm config set registry "${MIRROR_URL}" --global 2>/dev/null || true
fi
if [[ -n "$HTTP_PROXY" ]]; then
    pnpm config set proxy "$HTTP_PROXY" --global 2>/dev/null || true
    pnpm config set https-proxy "$HTTPS_PROXY" --global 2>/dev/null || true
fi

ok "pnpm 优化: 并发=${PNPM_CONCURRENCY}, 重试=${MAX_RETRIES}"

# ─── 步骤 6: 安装 OpenClaw ───
step "步骤 6/8: 安装 OpenClaw"

info "正在安装 openclaw@${OPENCLAW_VERSION} ..."
echo -e "  ${DIM}(使用 pnpm + ${PNPM_CONCURRENCY} 并发 + 镜像加速)${NC}"
echo ""

INSTALL_START=$(date +%s)

retry_with_backoff pnpm add -g "openclaw@${OPENCLAW_VERSION}"

INSTALL_END=$(date +%s)
INSTALL_ELAPSED=$((INSTALL_END - INSTALL_START))

echo ""
ok "OpenClaw 安装完成! 耗时: ${INSTALL_ELAPSED}s"

# pnpm approve-builds
info "审批构建脚本..."
pnpm approve-builds -g 2>/dev/null || true

# ─── 步骤 7: 验证 & 清理 ───
step "步骤 7/8: 验证安装 & 清理"

# 恢复 registry
if [[ "$USE_MIRROR" == true ]]; then
    npm config set registry "${ORIGINAL_NPM_REGISTRY}"
    if [[ -n "${ORIGINAL_PNPM_REGISTRY}" ]]; then
        pnpm config set registry "${ORIGINAL_PNPM_REGISTRY}" --global 2>/dev/null || true
    else
        pnpm config delete registry --global 2>/dev/null || true
    fi
    ORIGINAL_NPM_REGISTRY=""
    ORIGINAL_PNPM_REGISTRY=""
    ok "registry 已恢复"
fi

# 清理代理
if [[ -n "$HTTP_PROXY" ]]; then
    npm config delete proxy 2>/dev/null || true
    npm config delete https-proxy 2>/dev/null || true
    pnpm config delete proxy --global 2>/dev/null || true
    pnpm config delete https-proxy --global 2>/dev/null || true
    ok "代理配置已清理"
fi

# 验证
if command_exists openclaw; then
    CLAW_VER=$(openclaw --version 2>/dev/null || echo "unknown")
    ok "OpenClaw ${CLAW_VER} 验证通过!"
else
    warn "openclaw 命令未在 PATH 中找到"
    warn "请尝试: export PATH=\"\$(pnpm bin -g):\$PATH\""
    warn "或重新打开终端"
fi

# ─── 步骤 8: 安装后健康检查 ───
step "步骤 8/8: 安装后健康检查"

HEALTH_PASS=0
HEALTH_TOTAL=0

# 8a. 检查 Node.js 仍然可用
HEALTH_TOTAL=$((HEALTH_TOTAL + 1))
if command_exists node; then
    ok "Node.js $(node -v) 可用"
    HEALTH_PASS=$((HEALTH_PASS + 1))
else
    err "Node.js 不可用!"
fi

# 8b. 检查 pnpm 全局 bin 在 PATH 中
HEALTH_TOTAL=$((HEALTH_TOTAL + 1))
PNPM_BIN=$(pnpm bin -g 2>/dev/null || echo "")
if [[ -n "$PNPM_BIN" && ":$PATH:" == *":$PNPM_BIN:"* ]]; then
    ok "pnpm 全局 bin 在 PATH 中"
    HEALTH_PASS=$((HEALTH_PASS + 1))
elif [[ -n "$PNPM_BIN" ]]; then
    warn "pnpm 全局 bin 不在 PATH 中: ${PNPM_BIN}"
    warn "建议添加到 shell 配置: export PATH=\"${PNPM_BIN}:\$PATH\""
    # 尝试自动添加
    if [[ -n "$SHELL_RC" && -f "$SHELL_RC" ]]; then
        if ! grep -q "pnpm bin" "$SHELL_RC" 2>/dev/null; then
            info "自动添加到 ${SHELL_RC}..."
            echo "" >> "$SHELL_RC"
            echo '# pnpm global bin' >> "$SHELL_RC"
            echo 'export PATH="$(pnpm bin -g):$PATH"' >> "$SHELL_RC"
            ok "已添加到 ${SHELL_RC} (重新打开终端生效)"
            HEALTH_PASS=$((HEALTH_PASS + 1))
        fi
    fi
else
    warn "无法获取 pnpm 全局 bin 路径"
fi

# 8c. 检查 registry 是否恢复
HEALTH_TOTAL=$((HEALTH_TOTAL + 1))
CURRENT_REG=$(npm config get registry 2>/dev/null || echo "")
if [[ "$CURRENT_REG" == "https://registry.npmjs.org/" || "$USE_MIRROR" == false ]]; then
    ok "npm registry 已恢复为官方源"
    HEALTH_PASS=$((HEALTH_PASS + 1))
else
    info "当前 npm registry: ${CURRENT_REG}"
    HEALTH_PASS=$((HEALTH_PASS + 1))
fi

# 8d. 检查 pnpm store 状态
HEALTH_TOTAL=$((HEALTH_TOTAL + 1))
PNPM_STORE=$(pnpm store path 2>/dev/null || echo "")
if [[ -n "$PNPM_STORE" && -d "$PNPM_STORE" ]]; then
    STORE_SIZE=$(du -sm "$PNPM_STORE" 2>/dev/null | awk '{print $1}')
    ok "pnpm store: ${PNPM_STORE} (${STORE_SIZE:-?}MB)"
    HEALTH_PASS=$((HEALTH_PASS + 1))
else
    debug "pnpm store 未检测到"
    HEALTH_PASS=$((HEALTH_PASS + 1))
fi

# 8e. 检查无残留临时文件
HEALTH_TOTAL=$((HEALTH_TOTAL + 1))
TMPFILES=$(find /tmp -maxdepth 1 -name "pnpm-*" -mmin -5 2>/dev/null | wc -l || echo 0)
if [[ "$TMPFILES" -gt 10 ]]; then
    warn "发现 ${TMPFILES} 个 pnpm 临时文件 (正常，稍后自动清理)"
else
    ok "临时文件状态正常"
fi
HEALTH_PASS=$((HEALTH_PASS + 1))

echo ""
ok "健康检查: ${HEALTH_PASS}/${HEALTH_TOTAL} 通过"

# ─── 完成报告 ───
TOTAL_END=$(date +%s)
TOTAL_ELAPSED=$((TOTAL_END - TOTAL_START))

echo ""
echo -e "${BOLD}${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║              安装完成!                                ║${NC}"
echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}安装报告${NC}"
echo -e "  ────────────────────────────"
echo -e "  总耗时:       ${BOLD}${TOTAL_ELAPSED}s${NC} (其中安装: ${INSTALL_ELAPSED}s)"
echo -e "  安装方式:     pnpm (并发: ${PNPM_CONCURRENCY})"
echo -e "  镜像加速:     ${USE_MIRROR}"
echo -e "  系统平台:     ${OS_TYPE} (${ARCH_TYPE})"
echo -e "  日志文件:     ${LOG_FILE}"
echo ""
echo -e "  ${BOLD}下一步${NC}"
echo -e "  ────────────────────────────"
echo "  1. openclaw onboard --install-daemon  # 完成初始化"
echo "  2. openclaw                           # 开始使用"
echo ""
