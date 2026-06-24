#!/usr/bin/env bash
# ============================================================
#  Web Resources Fetcher - Launcher
#  Usage: ./fetch.sh <url> [options]
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/fetch.py"
VENV_DIR="${SCRIPT_DIR}/.venv"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Help ---
show_help() {
    local cmd
    cmd="$(basename "$0")"
    echo -e "${CYAN}Web Resources Fetcher${NC}"
    echo "Extract and download all resources from a web page."
    echo "Opens a browser for login if the site requires authentication."
    echo ""
    echo -e "${GREEN}Usage:${NC}"
    echo "  $cmd <url> [options]"
    echo ""
    echo -e "${GREEN}Arguments:${NC}"
    echo "  <url>                Target web page URL (required)"
    echo ""
    echo -e "${GREEN}Options:${NC}"
    echo "  -o, --output <dir>   Download directory (default: ./downloads)"
    echo "  --headless           Run browser in headless mode (no window)"
    echo "  --no-login           Skip login detection, scrape directly"
    echo "  -h, --help           Show this help message"
    echo ""
    echo -e "${GREEN}Examples:${NC}"
    echo "  $cmd \"https://example.com/downloads\""
    echo "  $cmd \"https://example.com/files\" -o ~/my-downloads"
    echo "  $cmd \"https://example.com/files\" --headless --no-login"
    echo ""
    echo -e "${GREEN}First run:${NC}"
    echo "  Automatically creates .venv and installs dependencies (playwright + chromium)"
    exit 0
}

# --- Logging ---
log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- URL validation ---
validate_url() {
    local url="$1"
    if [[ -z "$url" ]]; then
        log_error "URL argument is required"
        echo ""
        show_help
    fi
    if [[ ! "$url" =~ ^https?:// ]]; then
        log_error "URL must start with http:// or https://"
        log_error "Got: $url"
        exit 1
    fi
}

# --- Python check ---
check_python() {
    if ! command -v python3 &>/dev/null; then
        log_error "python3 not found. Please install Python 3 first."
        exit 1
    fi
}

# --- Virtual environment setup ---
setup_venv() {
    if [[ ! -d "$VENV_DIR" ]]; then
        log_info "Creating virtual environment..."
        python3 -m venv "$VENV_DIR"
        log_ok "Virtual environment created"
    fi

    source "${VENV_DIR}/bin/activate"

    # Install playwright if missing
    if ! python3 -c "import playwright" 2>/dev/null; then
        log_info "Installing dependencies..."
        pip install -q -r "${SCRIPT_DIR}/requirements.txt"
        log_ok "Dependencies installed"
    fi

    # Install chromium browser if missing
    if [[ ! -d "${VENV_DIR}/lib/"*"/site-packages/playwright/driver/package/.local-browsers/chromium-"* ]]; then
        log_info "Installing Chromium browser (first-time setup)..."
        playwright install chromium
        log_ok "Chromium installed"
    fi
}

# --- Main ---
main() {
    if [[ $# -eq 0 ]]; then
        show_help
    fi

    local url=""
    local extra_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)      show_help ;;
            -o|--output)
                [[ -z "${2:-}" ]] && { log_error "--output requires a directory argument"; exit 1; }
                extra_args+=("--output" "$2"); shift 2 ;;
            --headless)     extra_args+=("--headless"); shift ;;
            --no-login)     extra_args+=("--no-login"); shift ;;
            -*)             log_error "Unknown option: $1"; show_help ;;
            *)
                [[ -z "$url" ]] && { url="$1"; shift; continue; }
                log_error "Unexpected argument: $1"; show_help ;;
        esac
    done

    validate_url "$url"
    check_python
    setup_venv

    log_info "Fetching: $url"
    python3 "$PYTHON_SCRIPT" "$url" "${extra_args[@]+"${extra_args[@]}"}"
}

main "$@"
