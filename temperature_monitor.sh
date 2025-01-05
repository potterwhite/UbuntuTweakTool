#!/bin/bash

################################################################################
# Script Name: temperature_monitor.sh
# Description: Advanced hardware temperature monitoring script
# Author: MrJamesLZAZ
# Created: 2024-12-17
# Version: 1.1
################################################################################

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function definitions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_error() {
    echo -e "${RED}Error: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

# Check root privileges
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (sudo)"
    exit 1
fi

# Package management functions
get_package_manager() {
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

install_packages() {
    local pkg_manager=$(get_package_manager)
    local packages=("$@")
    
    case $pkg_manager in
        "apt")
            print_warning "Installing required packages..."
            apt update
            apt install -y "${packages[@]}"
            ;;
        "dnf"|"yum")
            print_warning "Installing required packages..."
            $pkg_manager install -y "${packages[@]}"
            ;;
        "pacman")
            print_warning "Installing required packages..."
            pacman -Sy --noconfirm "${packages[@]}"
            ;;
        *)
            print_error "Unsupported package manager. Please install packages manually."
            exit 1
            ;;
    esac
}

# Check and install required packages
check_and_install_requirements() {
    local missing_packages=()
    
    # Define required packages for different package managers
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
        print_warning "Missing required packages: ${missing_packages[*]}"
        read -p "Would you like to install them now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_packages "${missing_packages[@]}"
        else
            print_error "Required packages must be installed to continue."
            exit 1
        fi
    fi
}

# CPU detection and monitoring
get_cpu_vendor() {
    grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}'
}

get_cpu_model() {
    grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//'
}

monitor_intel_cpu() {
    print_header "Intel CPU Temperatures"
    
    if ! lsmod | grep -q "coretemp"; then
        print_warning "Loading coretemp module..."
        modprobe coretemp 2>/dev/null
    fi
    
    if sensors 2>/dev/null | grep -q "Package id 0:"; then
        sensors 2>/dev/null | grep -E "Package id 0:|Core [0-9]+:"
    else
        print_warning "Cannot read Intel CPU temperatures"
    fi
}

monitor_amd_cpu() {
    print_header "AMD CPU Temperatures"
    
    if ! lsmod | grep -q "k10temp"; then
        print_warning "Loading k10temp module..."
        modprobe k10temp 2>/dev/null
    fi
    
    if sensors 2>/dev/null | grep -q "Tctl"; then
        sensors 2>/dev/null | grep -E "Tctl|Tdie|Core[[:space:]]"
    elif sensors 2>/dev/null | grep -q "k10temp"; then
        sensors 2>/dev/null | grep "temp1"
    else
        print_warning "Cannot read AMD CPU temperatures"
    fi
}

monitor_storage_temperatures() {
    print_header "Storage Temperatures"
    
    # NVME drives
    if ls /dev/nvme? 1>/dev/null 2>&1; then
        echo "NVME Drives:"
        for nvme in /dev/nvme?; do
            echo "$(basename $nvme):"
            nvme smart-log $nvme 2>/dev/null | grep "temperature"
        done
    else
        print_warning "No NVME drives found"
    fi
    
    # SATA drives
    if ls /dev/sd? 1>/dev/null 2>&1; then
        echo -e "\nSATA Drives:"
        for drive in /dev/sd?; do
            echo "$(basename $drive):"
            smartctl -A $drive 2>/dev/null | awk '/Temperature_Celsius/ {print $10"°C"}'
        done
    else
        print_warning "No SATA drives found"
    fi
}

monitor_gpu_temperatures() {
    print_header "GPU Temperatures"
    
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
            print_warning "No GPU temperature sensors found"
        fi
    fi
}

# Main execution
echo -e "${GREEN}=================== Hardware Temperature Monitor ===================${NC}"

# Check and install requirements
check_and_install_requirements

# Initialize sensors
if ! sensors-detect --auto &>/dev/null; then
    print_warning "Failed to auto-detect sensors. Some readings may be unavailable."
fi

# CPU monitoring
cpu_vendor=$(get_cpu_vendor)
cpu_model=$(get_cpu_model)

print_header "System Information"
echo "CPU Vendor: $cpu_vendor"
echo "CPU Model: $cpu_model"

case "$cpu_vendor" in
    "GenuineIntel")
        monitor_intel_cpu
        ;;
    "AuthenticAMD")
        monitor_amd_cpu
        ;;
    *)
        print_warning "Unknown CPU vendor: $cpu_vendor"
        sensors 2>/dev/null | grep -E "Core|Package|temp1"
        ;;
esac

# Storage monitoring
monitor_storage_temperatures

# GPU monitoring
monitor_gpu_temperatures

# Fan speeds
print_header "Fan Speeds"
if ls /sys/class/hwmon/hwmon*/fan* &>/dev/null; then
    find /sys/class/hwmon/hwmon*/fan* -type f -name "input" 2>/dev/null | while read fan; do
        if [ -f "$fan" ]; then
            fan_name=$(basename $(dirname $fan))
            speed=$(cat $fan 2>/dev/null)
            [ ! -z "$speed" ] && echo "$fan_name: $speed RPM"
        fi
    done
else
    print_warning "No fan sensors found"
fi

# IPMI monitoring (if available)
if command -v ipmitool &>/dev/null; then
    print_header "IPMI Sensors"
    ipmitool sensor 2>/dev/null || print_warning "Unable to read IPMI sensors"
fi

echo -e "\n${GREEN}======================= End of Report =======================${NC}"
