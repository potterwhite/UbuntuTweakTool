#!/bin/bash

################################################################################
# Script Name: temperature_monitor.sh
# Description: Advanced hardware temperature monitoring script
# Author: MrJamesLZAZ
# Created: 2024-12-17
# Modified: 2025-01-15
# Version: 1.1
################################################################################

########################################################################
# 1st. Load environment variables
func_load_env() {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
}

########################################################################
# 2nd. Print functions
func_print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

func_print_error() {
    echo -e "${RED}Error: $1${NC}"
}

func_print_warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

func_print_success() {
    echo -e "${GREEN}$1${NC}"
}

########################################################################
# 3rd. Check root privileges
func_check_root() {
    if [ "$EUID" -ne 0 ]; then
        func_print_error "Please run as root (sudo)"
        exit 1
    fi
}

########################################################################
# 4th. Package management functions
func_get_package_manager() {
    if command -v apt &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

func_install_packages() {
    local pkg_manager=$(func_get_package_manager)
    local packages=("$@")

    case $pkg_manager in
        "apt")
            func_print_warning "Installing required packages..."
            apt update
            apt install -y "${packages[@]}"
            ;;
        "dnf"|"yum")
            func_print_warning "Installing required packages..."
            $pkg_manager install -y "${packages[@]}"
            ;;
        "pacman")
            func_print_warning "Installing required packages..."
            pacman -Sy --noconfirm "${packages[@]}"
            ;;
        *)
            func_print_error "Unsupported package manager. Please install packages manually."
            exit 1
            ;;
    esac
}

# 检查并安装依赖
func_check_requirements() {
    local missing_packages=()
    declare -A pkg_names=(
        ["sensors"]="lm-sensors"
        ["smartctl"]="smartmontools"
        ["nvme"]="nvme-cli"
        ["ipmitool"]="ipmitool"
    )

    for cmd in "${!pkg_names[@]}"; do
        if ! command -v $cmd &>/dev/null; then
            missing_packages+=("${pkg_names[$cmd]}")
        fi
    done

    if [ ${#missing_packages[@]} -ne 0 ]; then
        func_print_warning "Missing required packages: ${missing_packages[*]}"
        read -p "Would you like to install them now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            func_install_packages "${missing_packages[@]}"
        else
            func_print_error "Required packages must be installed to continue."
            exit 1
        fi
    fi
}

########################################################################
# 5th. CPU detection and monitoring
func_get_cpu_vendor() {
    grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}'
}

func_get_cpu_model() {
    grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//'
}

func_monitor_intel_cpu() {
    func_print_header "Intel CPU Temperatures"

    if ! lsmod | grep -q "coretemp"; then
        func_print_warning "Loading coretemp module..."
        modprobe coretemp 2>/dev/null
    fi

    if sensors 2>/dev/null | grep -q "Package id 0:"; then
        sensors 2>/dev/null | grep -E "Package id 0:|Core [0-9]+:"
    else
        func_print_warning "Cannot read Intel CPU temperatures"
    fi
}

func_monitor_amd_cpu() {
    func_print_header "AMD CPU Temperatures"

    if ! lsmod | grep -q "k10temp"; then
        func_print_warning "Loading k10temp module..."
        modprobe k10temp 2>/dev/null
    fi

    if sensors 2>/dev/null | grep -q "Tctl"; then
        sensors 2>/dev/null | grep -E "Tctl|Tdie|Core[[:space:]]"
    elif sensors 2>/dev/null | grep -q "k10temp"; then
        sensors 2>/dev/null | grep "temp1"
    else
        func_print_warning "Cannot read AMD CPU temperatures"
    fi
}

########################################################################
# 6th. Storage temperatures
func_monitor_storage_temperatures() {
    func_print_header "Storage Temperatures"

    # NVME drives
    if ls /dev/nvme? 1>/dev/null 2>&1; then
        echo "NVME Drives:"
        for nvme in /dev/nvme?; do
            local drive_name=$(basename $nvme)
            local temp=$(nvme smart-log $nvme 2>/dev/null | grep "temperature" | awk '{print $3}')
            echo -e "${drive_name}: \t\t\t ${temp}°C"
        done
    else
        func_print_warning "No NVME drives found"
    fi

    # SATA drives
    if ls /dev/sd? 1>/dev/null 2>&1; then
        echo -e "\nSATA Drives:"
        for drive in /dev/sd?; do
            local drive_name=$(basename $drive)
            local temp=$(smartctl -A $drive 2>/dev/null | awk '/Temperature_Celsius/ {print $10}')
            if [ ! -z "$temp" ]; then
                echo -e "${drive_name}: \t\t\t ${temp}°C"
            fi
        done
    else
        func_print_warning "No SATA drives found"
    fi
}

########################################################################
# 7th. GPU temperatures
func_monitor_gpu_temperatures() {
    func_print_header "GPU Temperatures"

    if command -v nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader
    else
        # Try AMD GPU temperature
        if [ -d "/sys/class/drm/card0/device/hwmon" ]; then
            for hwmon in /sys/class/drm/card0/device/hwmon/hwmon*/temp1_input; do
                if [ -f "$hwmon" ]; then
                    temp=$(cat "$hwmon" 2>/dev/null)
                    echo "AMD GPU: $((temp/1000))°C"
                fi
            done
        else
            func_print_warning "No GPU temperature sensors found"
        fi
    fi
}

########################################################################
# 8th. Fan speeds
func_monitor_fan_speeds() {
    func_print_header "Fan Speeds"
    sensors 2>/dev/null | grep -E "fan[0-9]+:"
}

########################################################################
# 9th. IPMI monitoring
func_monitor_ipmi() {
    # 首先检查是否存在IPMI设备
    if [ -e "/dev/ipmi0" ] || [ -e "/dev/ipmi/0" ] || [ -e "/dev/ipmidev/0" ]; then
        func_print_header "IPMI Monitoring"
        ipmitool sdr list
    else
        # 如果不是服务器硬件，就跳过这部分
        return 0
    fi
}

########################################################################
# 99th. Main function
main() {
    # 初始化颜色
    func_load_env

    # 显示标题
    echo -e "${GREEN}=================== Hardware Temperature Monitor ===================${NC}"

    # 检查root权限
    func_check_root

    # 检查并安装依赖
    func_check_requirements

    # 初始化传感器
    if ! sensors-detect --auto &>/dev/null; then
        func_print_warning "Failed to auto-detect sensors. Some readings may be unavailable."
    fi

    # 获取并显示系统信息
    local cpu_vendor=$(func_get_cpu_vendor)
    local cpu_model=$(func_get_cpu_model)

    func_print_header "System Information"
    echo "CPU Vendor: $cpu_vendor"
    echo "CPU Model: $cpu_model"

    # 监控CPU温度
    case "$cpu_vendor" in
        "GenuineIntel")
            func_monitor_intel_cpu
            ;;
        "AuthenticAMD")
            func_monitor_amd_cpu
            ;;
        *)
            func_print_warning "Unknown CPU vendor: $cpu_vendor"
            sensors 2>/dev/null | grep -E "Core|Package|temp1"
            ;;
    esac

    # 监控存储设备温度
    func_monitor_storage_temperatures

    # 监控GPU温度
    func_monitor_gpu_temperatures

    # 监控风扇速度
    func_monitor_fan_speeds

    # IPMI监控
    func_monitor_ipmi

    echo -e "\n${GREEN}======================= End of Report =======================${NC}"
}

# 执行主函数
main "$@"
