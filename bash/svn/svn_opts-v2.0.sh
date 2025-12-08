#!/bin/bash

# ==============================================================================
# SVN Bulk Management Script
# ==============================================================================
# Refactored Version
# Features:
#   - Bulk Pull/Push
#   - Interactive Mode to add Repositories
#   - Layered Architecture (Level 1 to Level 4)
# ==============================================================================

# ==============================================================================
# LEVEL 1: Primitives & Environment & Logging
# (最底层的工具函数，不涉及具体业务逻辑)
# ==============================================================================

func_1_0_load_env() {
    SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
    SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"

    # Default to Release unless V=1 is passed
    if [ "${V}" == "1" ]; then
        CURRENT_MODE="Debug"
    else
        CURRENT_MODE="Release"
    fi
}

func_1_1_log() {
    # $1: Level (INFO, DEBUG, ERROR)
    # $2: Message
    local level=$1
    local msg=$2

    if [ "${level}" == "DEBUG" ] && [ "${CURRENT_MODE}" != "Debug" ]; then
        return
    fi

    # Color codes
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[1;33m'
    local NC='\033[0m' # No Color

    case "${level}" in
        "ERROR") echo -e "${RED}[ERROR] ${msg}${NC}" ;;
        "INFO")  echo -e "${GREEN}[INFO]  ${msg}${NC}" ;;
        "WARN")  echo -e "${YELLOW}[WARN]  ${msg}${NC}" ;;
        "DEBUG") echo -e "[DEBUG] ${msg}" ;;
        *)       echo -e "${msg}" ;;
    esac
}

# ==============================================================================
# LEVEL 2: Atomic SVN Operations
# (针对单个目录的原子操作，不关心遍历逻辑)
# ==============================================================================

func_2_0_svn_checkout() {
    # $1: SVN URL
    # $2: Local Directory Name
    # $3: Username (Optional)
    local url="$1"
    local dir="$2"
    local user="$3"

    func_1_1_log "INFO" "Starting Checkout: ${url} -> ${dir}"
    
    if [ -n "$user" ]; then
        svn checkout "${url}" "${dir}" --username "${user}"
    else
        svn checkout "${url}" "${dir}"
    fi

    if [ $? -eq 0 ]; then
        func_1_1_log "INFO" "Checkout successful."
    else
        func_1_1_log "ERROR" "Checkout failed."
    fi
}

func_2_1_svn_pull_single() {
    # $1: Absolute Path to Directory
    local target_dir="$1"

    func_1_1_log "INFO" ">>> Pulling: $(basename "${target_dir}")"
    
    # Check if it is a directory
    if [ ! -d "${target_dir}" ]; then
        func_1_1_log "ERROR" "Directory not found: ${target_dir}"
        return 1
    fi

    # Subshell to avoid changing global CWD
    (
        cd "${target_dir}" || return 1
        svn update
    )
}

func_2_2_svn_push_single() {
    # $1: Absolute Path to Directory
    local target_dir="$1"

    func_1_1_log "INFO" ">>> Pushing: $(basename "${target_dir}")"

    if [ ! -d "${target_dir}" ]; then
        func_1_1_log "ERROR" "Directory not found: ${target_dir}"
        return 1
    fi

    (
        cd "${target_dir}" || return 1

        # --- Original Logic Preservation Start ---
        # 检查SVN状态
        local has_missing_files=$(svn status | grep '^!' | wc -l)
        local has_conflicts=$(svn status | grep '^C' | wc -l)
        local scheduled_but_missing=$(svn status | grep "is scheduled for addition, but is missing" | wc -l)
        
        # 只有在有问题时才执行revert
        if [ "$has_missing_files" -gt 0 ] || [ "$has_conflicts" -gt 0 ] || [ "$scheduled_but_missing" -gt 0 ]; then
            func_1_1_log "WARN" "SVN status abnormal in $(basename "${target_dir}"), executing revert/repair..."
            svn revert --depth infinity .
            # 删除 missing 的文件引用
            svn status | grep '^!' | awk '{print $2}' | xargs -r svn rm --force
        fi

        svn add * --force > /dev/null 2>&1
        svn diff
        svn commit -m "$(date +%b%d.%Y_%H:%M:%S)" -m "Default Commit Message"
        # --- Original Logic Preservation End ---
    )
}

# ==============================================================================
# LEVEL 3: Orchestration & Logic
# (业务逻辑层：处理批量循环、交互流程)
# ==============================================================================

func_3_0_process_batch() {
    # $1: Operation (push/pull)
    # $2: Target Name (all / specific_dir_name)
    # $3: Root Path (Where the svn repos are)
    
    local op=${1,,}  # to lowercase
    local target_name=${2%/} # remove trailing slash
    local root_path="$3"

    func_1_1_log "DEBUG" "Operation: $op, Target: $target_name, Root: $root_path"

    # Fix for your error: Ensure the root path exists
    if [ ! -d "${root_path}" ]; then
        func_1_1_log "ERROR" "Root path does not exist: ${root_path}"
        return 1
    fi

    # Go to root path to safely look for directories
    cd "${root_path}" || return 1

    # Logic Branch: Single Dir vs All Dirs
    if [ "${target_name}" != "all" ]; then
        # === Single Directory Mode ===
        local full_path="${root_path}/${target_name}"
        
        if [ "${op}" == "push" ]; then
            func_2_2_svn_push_single "${full_path}"
        else
            func_2_1_svn_pull_single "${full_path}"
        fi
    else
        # === Batch "All" Mode ===
        
        # Enable nullglob: if no matches, returns empty string instead of literal '*'
        shopt -s nullglob
        local subdirs=( */ )
        shopt -u nullglob

        # Fix for "Not a directory" bug: Check if array is empty
        if [ ${#subdirs[@]} -eq 0 ]; then
            func_1_1_log "WARN" "No subdirectories found in ${root_path}."
            return 0
        fi

        for subdir in "${subdirs[@]}"; do
            local clean_subdir="${subdir%/}" # Remove trailing slash
            local full_path="${root_path}/${clean_subdir}"

            # Ensure it's actually a dir (double check)
            if [ -d "${full_path}" ]; then
                 if [ "${op}" == "push" ]; then
                    func_2_2_svn_push_single "${full_path}"
                else
                    func_2_1_svn_pull_single "${full_path}"
                fi
                echo "" # Empty line for readability
            fi
        done
        func_1_1_log "INFO" "Done processing all directories."
    fi
}

func_3_1_interactive_mode() {
    # New Feature: Interactive Mode to add SVN
    local root_path="$1"
    
    echo "=========================================="
    echo "      SVN Interactive Management"
    echo "=========================================="
    echo "Current Location: ${root_path}"
    echo ""
    
    read -p "Enter SVN Repository URL: " repo_url
    if [ -z "$repo_url" ]; then
        func_1_1_log "ERROR" "URL cannot be empty."
        return 1
    fi

    # Extract default folder name from URL (simple heuristic)
    local default_name
    default_name=$(basename "${repo_url}")
    
    read -p "Enter Directory Name [${default_name}]: " dir_name
    dir_name=${dir_name:-$default_name} # Use default if empty

    read -p "Enter Username (Press Enter to skip): " svn_user

    echo ""
    echo "Summary:"
    echo "  URL:  $repo_url"
    echo "  DIR:  $root_path/$dir_name"
    echo "  USER: ${svn_user:-<system default>}"
    echo ""
    read -p "Proceed with checkout? (y/n): " confirm

    if [ "${confirm,,}" == "y" ]; then
        # Switch to root path before checkout
        cd "${root_path}" || return 1
        func_2_0_svn_checkout "${repo_url}" "${dir_name}" "${svn_user}"
    else
        echo "Cancelled."
    fi
}

# ==============================================================================
# LEVEL 4: Entry Point & Argument Parsing
# (Main 函数：参数解析与分发)
# ==============================================================================

main() {
    # Initialize Environment
    func_1_0_load_env

    # Check for arguments
    if [ $# -lt 1 ]; then
        echo "Usage:"
        echo "  1. Standard Mode: $0 [push|pull] [all|dir_name] [root_path]"
        echo "  2. Interactive:   $0 interactive [root_path]"
        echo ""
        echo "Example:"
        echo "  $0 pull all /mnt/data/svn-repos/"
        echo "  $0 interactive /mnt/data/svn-repos/"
        exit 1
    fi

    local action="$1"

    # === Dispatcher ===
    if [ "${action}" == "interactive" ] || [ "${action}" == "-i" ]; then
        # Interactive Mode
        local target_path
        if [ -n "$2" ]; then
             target_path="$(readlink -f "$2")"
        else
             # target_path="${SCRIPT_DIR}" # Default to current dir if not provided
             target_path="${PWD}"
        fi
        
        func_3_1_interactive_mode "${target_path}"
        
    else
        # Standard Push/Pull Mode
        if [ $# -lt 3 ]; then
             func_1_1_log "ERROR" "Missing arguments for push/pull mode."
             echo "Format: $0 [push|pull] [all|dir_name] [root_path]"
             exit 1
        fi

        local scope="$2"
        local raw_path="$3"
        local target_path="$(readlink -f "${raw_path}")"

        func_3_0_process_batch "${action}" "${scope}" "${target_path}"
    fi

    if [ $? -ne 0 ]; then
        exit 1
    fi
}

# Call Main
main "$@"