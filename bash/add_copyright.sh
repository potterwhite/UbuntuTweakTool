#!/bin/bash

# ==============================================================================
# Universal Copyright Header Automation Script (v3.1)
#
# Fixes in v3.1:
# - Auto-enables SPDX mode (-s) for licenses not natively supported (GPL, LGPL...)
# - Maps generic license names to valid SPDX IDs (e.g., lgpl -> LGPL-3.0-only)
# ==============================================================================

# Global Config
GO_VERSION="1.22.4"
DEFAULT_OWNER_NAME="ArcForge Team"
TIMEOUT_SEC=15

# Define Paths Explicitly
HOME_DIR="$HOME"
GO_INSTALL_DIR="$HOME_DIR/go"
GO_BIN_DIR="$GO_INSTALL_DIR/bin"
TOOL_BIN="$GO_BIN_DIR/addlicense"

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==============================================================================
# LEVEL 1: Foundation
# ==============================================================================

func_1_1_log_info() { echo -e "${CYAN}[INFO]${NC} $1" >&2; }
func_1_2_log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
func_1_3_log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
func_1_4_log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

func_1_5_check_command() { command -v "$1" >/dev/null 2>&1; }

func_1_6_detect_arch() {
    local raw_arch
    raw_arch=$(uname -m)
    case "$raw_arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        arm64)   echo "arm64" ;;
        *)       echo "amd64" ;;
    esac
}

# ==============================================================================
# LEVEL 2: Business Logic
# ==============================================================================

func_2_1_validate_and_preview() {
    local target="$1"
    
    if [ -z "$target" ]; then
        func_1_4_log_error "Missing argument.\nUsage: $0 <target_directory>"
        exit 1
    fi
    if [ ! -d "$target" ]; then
        func_1_4_log_error "Directory does not exist: $target"
        exit 1
    fi

    local abs_path
    abs_path=$(realpath "$target")
    
    echo "" >&2
    echo -e "${BLUE}--- Target Context Confirmation ---${NC}" >&2
    echo -e "You selected: ${CYAN}${abs_path}${NC}" >&2
    echo -e "Preview of contents:" >&2
    echo -e "${YELLOW}----------------------------------------${NC}" >&2
    ls -Fh "$target" | head -n 5 | sed 's/^/  - /' >&2
    echo -e "${YELLOW}----------------------------------------${NC}" >&2

    echo -n -e "Is this the correct directory? [y/N] " >&2
    read confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        func_1_3_log_warn "Aborted by user."
        exit 0
    fi
}

func_2_2_ensure_git_safe() {
    local target="$1"
    echo "" >&2
    
    if ! git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        func_1_3_log_warn "Target is NOT a git repository."
        echo -e "   ${RED}!!! ROLLBACK WARNING !!!${NC}" >&2
        echo -e "   We strongly recommend running this only on git-versioned folders." >&2
        echo -n -e "   Are you absolutely sure you want to continue? [y/N] " >&2
        read choice
        [[ "$choice" =~ ^[Yy]$ ]] || exit 1
    else
        if [ -n "$(git -C "$target" status --porcelain)" ]; then
            func_1_3_log_warn "Git repository has uncommitted changes."
            echo -e "   If the script fails, 'git checkout' will wipe your CURRENT work." >&2
            echo -n -e "   Proceed anyway (Risky)? [y/N] " >&2
            read choice
            [[ "$choice" =~ ^[Yy]$ ]] || exit 1
        fi
    fi
}

func_2_3_ensure_environment() {
    local sys_arch
    sys_arch=$(func_1_6_detect_arch)
    
    if [ -d "$GO_INSTALL_DIR" ]; then
        if ! "$GO_BIN_DIR/go" version >/dev/null 2>&1; then
             func_1_1_log_info "Cleaning up broken Go installation..."
             chmod -R u+w "$GO_INSTALL_DIR" 2>/dev/null
             rm -rf "$GO_INSTALL_DIR"
        fi
    fi

    if [ ! -f "$GO_BIN_DIR/go" ]; then
        func_1_1_log_info "Installing Go ${GO_VERSION} for ${sys_arch}..."
        wget -q --show-progress "https://go.dev/dl/go${GO_VERSION}.linux-${sys_arch}.tar.gz" -O go_installer.tar.gz
        if [ $? -ne 0 ]; then
            func_1_4_log_error "Failed to download Go."
            exit 1
        fi
        tar -C "$HOME_DIR" -xzf go_installer.tar.gz
        rm go_installer.tar.gz
        func_1_2_log_success "Go installed."
    fi

    export PATH=$GO_BIN_DIR:$PATH
    
    if [ ! -f "$TOOL_BIN" ]; then
        func_1_1_log_info "Installing addlicense tool..."
        "$GO_BIN_DIR/go" install github.com/google/addlicense@latest >&2
        if [ ! -f "$TOOL_BIN" ]; then
             func_1_4_log_error "Installation failed."
             exit 1
        fi
        func_1_2_log_success "Tool installed."
    fi
}

func_2_4_ask_owner() {
    echo "" >&2
    echo -e "${BLUE}--- Configuration: Copyright Owner ---${NC}" >&2
    echo "Who holds the copyright?" >&2
    echo -n -e "Enter Name [${DEFAULT_OWNER_NAME}]: " >&2
    read user_owner
    if [ -z "$user_owner" ]; then
        echo "$DEFAULT_OWNER_NAME"
    else
        echo "$user_owner"
    fi
}

func_2_5_select_license() {
    echo "" >&2
    echo -e "${BLUE}--- Configuration: License Type ---${NC}" >&2
    echo -e "${CYAN}Note: Licenses marked with (*) will use SPDX Short-Identifier headers.${NC}" >&2
    
    # Display Labels
    local labels=(
        "Apache 2.0" 
        "MIT" 
        "BSD" 
        "MPL 2.0" 
        "EPL 2.0" 
        "GPL 3.0 (*)" 
        "LGPL 3.0 (*)" 
        "AGPL 3.0 (*)" 
        "ISC (*)" 
        "Unlicense (*)"
    )
    
    # Internal Values (Mapped to addlicense generic names OR SPDX IDs)
    # For supported full-text: use generic name (apache, mit...)
    # For others: use Strict SPDX ID (GPL-3.0-only, etc.)
    local values=(
        "apache" 
        "mit" 
        "bsd" 
        "mpl" 
        "epl" 
        "GPL-3.0-only" 
        "LGPL-3.0-only" 
        "AGPL-3.0-only" 
        "ISC" 
        "Unlicense"
    )
    
    for i in "${!labels[@]}"; do
        echo "  [$i] ${labels[$i]}" >&2
    done
    
    echo -n -e "Select Index (Default: 1 [MIT]): " >&2
    read idx
    
    if [ -z "$idx" ]; then
        echo "mit"
        return
    fi
    
    if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -lt ${#values[@]} ]; then
        echo "${values[$idx]}"
    else
        func_1_3_log_warn "Invalid index. Defaulting to MIT."
        echo "mit"
    fi
}

func_2_6_scan_ignores() {
    local target="$1"
    local ignore_result=()
    local common_ignores=("third_party" "vendor" "node_modules" "build" "dist" "libs" "external")
    
    echo "" >&2
    echo -e "${BLUE}--- Configuration: Ignore List ---${NC}" >&2
    func_1_1_log_info "Scanning for sensitive directories..."
    
    ignore_result+=(".git")
    echo -e "  - .git          -> ${YELLOW}[Auto Ignored]${NC}" >&2

    for dir_name in "${common_ignores[@]}"; do
        if [ -d "${target}/${dir_name}" ]; then
            echo -n -e "  - Found candidate '${CYAN}${dir_name}${NC}'. Ignore it? [Y/n] " >&2
            read confirm
            confirm=${confirm:-y}
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                ignore_result+=("$dir_name")
                echo -e "    -> ${YELLOW}Added to ignore list${NC}" >&2
            else
                echo -e "    -> ${GREEN}Included${NC}" >&2
            fi
        fi
    done
    echo "${ignore_result[@]}"
}

func_2_7_execute_apply() {
    local target="$1"
    local owner="$2"
    local license="$3"
    local -a ignores=($4) 
    
    # -------------------------------------------------------------
    # Logic: Auto-detect if we need SPDX mode (-s)
    # The tool only supports full text for: apache, mit, bsd, mpl, epl
    # -------------------------------------------------------------
    local use_spdx="false"
    case "$license" in
        apache|mit|bsd|mpl|epl)
            use_spdx="false"
            ;;
        *)
            use_spdx="true"
            ;;
    esac

    local license_display=$(echo "$license" | tr 'a-z' 'A-Z')
    if [ "$use_spdx" == "true" ]; then
        license_display="${license_display} (SPDX Tag)"
    fi

    echo "" >&2
    echo -e "${BLUE}========================================${NC}" >&2
    echo -e "       FINAL EXECUTION SUMMARY          " >&2
    echo -e "${BLUE}========================================${NC}" >&2
    echo -e "Target:   ${CYAN}$(realpath "$target")${NC}" >&2
    echo -e "Owner:    ${CYAN}${owner}${NC}" >&2
    echo -e "License:  ${CYAN}${license_display}${NC}" >&2
    echo -e "Ignored:  ${YELLOW}${ignores[*]:-(None)}${NC}" >&2
    echo -e "----------------------------------------" >&2
    
    echo -n -e "Apply headers now? (Auto-start in ${TIMEOUT_SEC}s) [Y/n]: " >&2
    read -t $TIMEOUT_SEC confirm
    if [ $? -ne 0 ]; then echo "" >&2; confirm="y"; fi
    confirm=${confirm:-y}
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted." >&2
        exit 0
    fi

    func_1_1_log_info "Processing..."
    if [ ! -f "$TOOL_BIN" ]; then
        func_1_4_log_error "Tool binary missing at $TOOL_BIN"
        exit 1
    fi

    local find_args=("$target")
    if [ ${#ignores[@]} -gt 0 ]; then
        find_args+=("(")
        local first=true
        for ignore_dir in "${ignores[@]}"; do
            if [ "$first" = true ]; then first=false; else find_args+=("-o"); fi
            find_args+=("-name" "$ignore_dir")
        done
        find_args+=(")" "-prune" "-o")
    fi

    find_args+=("-type" "f" "(")
    find_args+=("-name" "*.cpp" "-o" "-name" "*.c" "-o" "-name" "*.cc" "-o" "-name" "*.h" "-o" "-name" "*.hpp")
    find_args+=("-o" "-name" "CMakeLists.txt" "-o" "-name" "*.go" "-o" "-name" "*.java" "-o" "-name" "*.py")
    find_args+=(")" "-print")

    # Construct the base command
    local cmd=("$TOOL_BIN" "-c" "$owner" "-l" "$license" "-v")
    
    # Dynamically append -s if needed
    if [ "$use_spdx" == "true" ]; then
        cmd+=("-s")
    fi

    # Run
    find "${find_args[@]}" | xargs -r "${cmd[@]}" >&2

    if [ $? -eq 0 ]; then
        func_1_2_log_success "Operation Complete."
    else
        func_1_4_log_error "Operation finished with some errors."
    fi
}

# ==============================================================================
# LEVEL 3: Main
# ==============================================================================

func_3_1_main() {
    local target_arg="${1:-.}"
    func_2_1_validate_and_preview "$target_arg"
    func_2_2_ensure_git_safe "$target_arg"
    func_2_3_ensure_environment
    local owner_val=$(func_2_4_ask_owner)
    local license_val=$(func_2_5_select_license)
    local ignore_val=$(func_2_6_scan_ignores "$target_arg")
    func_2_7_execute_apply "$target_arg" "$owner_val" "$license_val" "$ignore_val"
    echo "" >&2
    echo -e "${CYAN}--- Tips ---${NC}" >&2
    echo "1. Verify: 'git diff'" >&2
    echo "2. Undo:   'git checkout ${target_arg}'" >&2
}

func_3_1_main "$@"
