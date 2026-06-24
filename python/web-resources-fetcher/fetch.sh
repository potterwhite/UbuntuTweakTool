#!/usr/bin/env bash
# ============================================================
#  Web Resources Fetcher - 启动脚本
#  用法: ./fetch.sh <url> [options]
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/fetch.py"
VENV_DIR="${SCRIPT_DIR}/.venv"

# ─── 颜色 ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── 帮助信息 ───
show_help() {
    cat <<EOF
${CYAN}Web Resources Fetcher${NC}
从网页提取并下载所有资源（需要浏览器登录时自动弹出窗口）

${GREEN}用法:${NC}
  $(basename "$0") <url> [options]

${GREEN}参数:${NC}
  <url>                要抓取的网页 URL（必填）

${GREEN}选项:${NC}
  -o, --output <dir>   下载目录（默认: ./downloads）
  --headless            无头模式（不显示浏览器窗口）
  --no-login            跳过登录等待，直接抓取
  -h, --help            显示此帮助信息

${GREEN}示例:${NC}
  $(basename "$0") "https://developer.nvidia.com/embedded/downloads#?search=orin%20nx"
  $(basename "$0") "https://example.com/downloads" -o ~/my-downloads
  $(basename "$0") "https://example.com/files" --headless --no-login

${GREEN}首次使用:${NC}
  会自动创建 .venv 并安装依赖（playwright + chromium）
EOF
    exit 0
}

# ─── 打印函数 ───
log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── 参数校验 ───
validate_url() {
    local url="$1"
    if [[ -z "$url" ]]; then
        log_error "URL 参数不能为空"
        echo ""
        show_help
    fi
    if [[ ! "$url" =~ ^https?:// ]]; then
        log_error "URL 必须以 http:// 或 https:// 开头"
        log_error "收到: $url"
        exit 1
    fi
}

# ─── Python 环境检查 ───
check_python() {
    if ! command -v python3 &>/dev/null; then
        log_error "未找到 python3，请先安装 Python 3"
        exit 1
    fi
}

# ─── 虚拟环境管理 ───
setup_venv() {
    if [[ ! -d "$VENV_DIR" ]]; then
        log_info "创建虚拟环境..."
        python3 -m venv "$VENV_DIR"
        log_ok "虚拟环境已创建"
    fi

    source "${VENV_DIR}/bin/activate"

    # 检查 playwright 是否已安装
    if ! python3 -c "import playwright" 2>/dev/null; then
        log_info "安装依赖..."
        pip install -q -r "${SCRIPT_DIR}/requirements.txt"
        log_ok "依赖已安装"
    fi

    # 检查 chromium 浏览器是否已安装
    if [[ ! -d "${VENV_DIR}/lib/"*"/site-packages/playwright/driver/package/.local-browsers/chromium-"* ]]; then
        log_info "安装 Chromium 浏览器（首次需要）..."
        playwright install chromium
        log_ok "Chromium 已安装"
    fi
}

# ─── 参数解析 ───
parse_args() {
    local url=""
    local extra_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                ;;
            -o|--output)
                if [[ -z "${2:-}" ]]; then
                    log_error "--output 需要一个目录参数"
                    exit 1
                fi
                extra_args+=("--output" "$2")
                shift 2
                ;;
            --headless)
                extra_args+=("--headless")
                shift
                ;;
            --no-login)
                extra_args+=("--no-login")
                shift
                ;;
            -*)
                log_error "未知选项: $1"
                show_help
                ;;
            *)
                if [[ -z "$url" ]]; then
                    url="$1"
                else
                    log_error "多余的参数: $1"
                    show_help
                fi
                shift
                ;;
        esac
    done

    echo "$url"
    echo "${extra_args[@]+"${extra_args[@]}"}"
}

# ─── 主流程 ───
main() {
    # 无参数显示帮助
    if [[ $# -eq 0 ]]; then
        show_help
    fi

    # 解析参数
    local url=""
    local extra_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)      show_help ;;
            -o|--output)
                [[ -z "${2:-}" ]] && { log_error "--output 需要目录参数"; exit 1; }
                extra_args+=("--output" "$2"); shift 2 ;;
            --headless)     extra_args+=("--headless"); shift ;;
            --no-login)     extra_args+=("--no-login"); shift ;;
            -*)             log_error "未知选项: $1"; show_help ;;
            *)
                [[ -z "$url" ]] && { url="$1"; shift; continue; }
                log_error "多余的参数: $1"; show_help ;;
        esac
    done

    validate_url "$url"
    check_python
    setup_venv

    log_info "启动抓取: $url"
    python3 "$PYTHON_SCRIPT" "$url" "${extra_args[@]+"${extra_args[@]}"}"
}

main "$@"
