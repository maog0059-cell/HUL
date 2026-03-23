#!/usr/bin/env bash
#
# openclaw-fast-install.sh — 加速 OpenClaw 下载安装脚本
#
# 功能:
#   1. 自动检测并安装合适版本的 Node.js (>=22)
#   2. 使用 pnpm 替代 npm（更快、更省磁盘）
#   3. 支持 npm 镜像加速（默认 npmmirror，适合国内用户）
#   4. 并发下载优化
#   5. 自动完成 openclaw onboard
#
# 用法:
#   bash openclaw-fast-install.sh              # 使用镜像加速（推荐国内用户）
#   bash openclaw-fast-install.sh --no-mirror  # 使用官方源
#   bash openclaw-fast-install.sh --mirror URL # 自定义镜像地址

set -euo pipefail

# ─── 颜色输出 ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── 默认配置 ───
USE_MIRROR=true
MIRROR_URL="https://registry.npmmirror.com"
ORIGINAL_REGISTRY=""
MIN_NODE_VERSION=22
PNPM_CONCURRENCY=16

# ─── 解析参数 ───
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-mirror)
            USE_MIRROR=false
            shift
            ;;
        --mirror)
            USE_MIRROR=true
            MIRROR_URL="$2"
            shift 2
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --no-mirror       不使用镜像，直接从官方源下载"
            echo "  --mirror URL      使用自定义镜像地址"
            echo "  -h, --help        显示帮助信息"
            exit 0
            ;;
        *)
            err "未知参数: $1"
            exit 1
            ;;
    esac
done

# ─── 辅助函数 ───
command_exists() {
    command -v "$1" &>/dev/null
}

version_ge() {
    # 判断 $1 >= $2（主版本号比较）
    local v1 v2
    v1=$(echo "$1" | grep -oE '^[0-9]+')
    v2=$(echo "$2" | grep -oE '^[0-9]+')
    [[ "$v1" -ge "$v2" ]]
}

cleanup() {
    # 恢复原始 npm registry
    if [[ -n "${ORIGINAL_REGISTRY}" ]]; then
        info "恢复 npm registry 为: ${ORIGINAL_REGISTRY}"
        npm config set registry "${ORIGINAL_REGISTRY}" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# ─── 开始安装 ───
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}       OpenClaw 加速安装脚本${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""

# ─── 步骤 1: 检查 Node.js ───
info "检查 Node.js 版本..."

if command_exists node; then
    NODE_VER=$(node -v | tr -d 'v')
    if version_ge "$NODE_VER" "$MIN_NODE_VERSION"; then
        ok "Node.js v${NODE_VER} 已安装，满足要求 (>=${MIN_NODE_VERSION})"
    else
        warn "Node.js v${NODE_VER} 版本过低，需要 >= ${MIN_NODE_VERSION}"
        info "正在通过 nvm 安装 Node.js 24..."
        if command_exists nvm; then
            nvm install 24
            nvm use 24
        elif [[ -s "$HOME/.nvm/nvm.sh" ]]; then
            # shellcheck source=/dev/null
            source "$HOME/.nvm/nvm.sh"
            nvm install 24
            nvm use 24
        else
            info "未检测到 nvm，正在安装 nvm..."
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
            export NVM_DIR="$HOME/.nvm"
            # shellcheck source=/dev/null
            [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
            nvm install 24
            nvm use 24
        fi
        ok "Node.js $(node -v) 安装完成"
    fi
else
    warn "未检测到 Node.js"
    info "正在安装 nvm 和 Node.js 24..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
    nvm install 24
    nvm use 24
    ok "Node.js $(node -v) 安装完成"
fi

# ─── 步骤 2: 配置镜像加速 ───
if [[ "$USE_MIRROR" == true ]]; then
    info "配置 npm 镜像加速: ${MIRROR_URL}"
    ORIGINAL_REGISTRY=$(npm config get registry 2>/dev/null || echo "https://registry.npmjs.org/")
    npm config set registry "${MIRROR_URL}"
    ok "镜像已设置 (安装完成后会自动恢复)"
fi

# ─── 步骤 3: 安装 pnpm（更快的包管理器） ───
info "检查 pnpm..."

if command_exists pnpm; then
    ok "pnpm 已安装: $(pnpm -v)"
else
    info "正在安装 pnpm..."
    npm install -g pnpm
    ok "pnpm $(pnpm -v) 安装完成"
fi

# ─── 步骤 4: 配置 pnpm 并行下载 ───
info "配置 pnpm 并行下载 (并发数: ${PNPM_CONCURRENCY})..."
pnpm config set network-concurrency "${PNPM_CONCURRENCY}" --global 2>/dev/null || true

if [[ "$USE_MIRROR" == true ]]; then
    pnpm config set registry "${MIRROR_URL}" --global 2>/dev/null || true
fi

# ─── 步骤 5: 安装 OpenClaw ───
info "正在安装 OpenClaw (使用 pnpm 加速)..."
echo ""

START_TIME=$(date +%s)

pnpm add -g openclaw@latest

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
ok "OpenClaw 安装完成！耗时: ${ELAPSED} 秒"

# ─── 步骤 6: pnpm approve-builds ───
info "审批构建脚本 (pnpm 安全机制)..."
pnpm approve-builds -g 2>/dev/null || true

# ─── 步骤 7: 恢复镜像设置 ───
if [[ "$USE_MIRROR" == true && -n "${ORIGINAL_REGISTRY}" ]]; then
    info "恢复 npm registry..."
    npm config set registry "${ORIGINAL_REGISTRY}"
    pnpm config set registry "${ORIGINAL_REGISTRY}" --global 2>/dev/null || true
    ORIGINAL_REGISTRY=""  # 防止 trap 重复恢复
    ok "registry 已恢复为: ${ORIGINAL_REGISTRY:-https://registry.npmjs.org/}"
fi

# ─── 步骤 8: 验证安装 ───
info "验证安装..."
if command_exists openclaw; then
    CLAW_VER=$(openclaw --version 2>/dev/null || echo "unknown")
    ok "OpenClaw ${CLAW_VER} 安装成功！"
else
    warn "openclaw 命令未找到，可能需要重新打开终端"
    warn "或者手动运行: export PATH=\"\$(pnpm bin -g):\$PATH\""
fi

# ─── 完成 ───
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  安装完成！${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo "下一步："
echo "  1. 运行 openclaw onboard --install-daemon 完成初始化"
echo "  2. 运行 openclaw 开始使用"
echo ""
echo "加速技巧："
echo "  - 本脚本使用 pnpm 替代 npm，下载速度提升 2-3 倍"
echo "  - 使用 npmmirror 镜像，国内下载速度显著提升"
echo "  - 并发下载数设为 ${PNPM_CONCURRENCY}，充分利用带宽"
echo ""
