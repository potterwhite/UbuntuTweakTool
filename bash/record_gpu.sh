#!/bin/bash

# --- 配置 ---
GPU_UTIL_FILE="/sys/devices/platform/fb000000.gpu/utilisation" # GPU利用率文件路径，请根据你的系统确认
LOG_FILE="gpu_peak_log.txt"  # 日志文件名，将在脚本当前目录下创建
CHECK_INTERVAL=1             # 检查间隔（秒）

# --- 全局变量 ---
current_peak=0               # 当前会话的峰值
peak_time=""                 # 峰值出现的时间
was_zero_last_time=1         # 标记上一次读取是否为0 (1=是, 0=否)，初始假设为0

# --- 函数定义 ---
1_0_load_env(){
    # set -e # 如果 cat 失败（例如文件不存在），这会导致脚本退出。如果希望更健壮，可以去掉它或添加检查。
    # set -x # 调试用，正常运行时可以注释掉
    echo "监控脚本启动..."
    echo "GPU 利用率文件: $GPU_UTIL_FILE"
    echo "日志文件: $(pwd)/$LOG_FILE"
    echo "检查间隔: $CHECK_INTERVAL 秒"
    # 检查 GPU 文件是否存在且可读
    if [ ! -r "$GPU_UTIL_FILE" ]; then
        echo "错误: 无法读取 GPU 利用率文件 '$GPU_UTIL_FILE'"
        echo "请检查路径是否正确以及是否有读取权限。"
        exit 1
    fi
    # 初始化/清空日志文件？ 如果想每次启动脚本都清空日志，取消下面这行的注释
    # > "$LOG_FILE"
}

record_peak_and_separate(){
    local peak_value=$1
    local time_of_peak=$2
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')

    if [ "$peak_value" -gt 0 ]; then # 只有当记录过峰值时才写入
        echo "会话结束. 本次峰值: ${peak_value}% 发生在 ${time_of_peak}" >> "$LOG_FILE"
        echo "---- 分隔线 (记录于: $current_time) ----" >> "$LOG_FILE"
        echo "会话结束. 本次峰值: ${peak_value}% 发生在 ${time_of_peak}" # 同时输出到控制台
    else
        # 如果整个“会话”利用率一直是0，则不记录峰值，只记录分隔线表示检测周期
        echo "---- 分隔线 (记录于: $current_time, 未检测到活动) ----" >> "$LOG_FILE"
    fi
}

monitor_gpu(){
    echo "开始监控 GPU 利用率... 按 Ctrl+C 停止。"
    # 确保持久化变量在子shell或函数作用域问题下可用 (对于简单脚本通常不是问题)
    export current_peak peak_time was_zero_last_time

    while true; do
        # 读取当前利用率
        if ! current_util=$(cat "$GPU_UTIL_FILE" 2>/dev/null); then
             echo "警告: 读取 $GPU_UTIL_FILE 失败，跳过本次检查。"
             sleep "$CHECK_INTERVAL"
             continue # 跳过这次循环
        fi

        # 尝试去除可能的非数字字符（例如某些驱动可能带单位%）
        current_util=$(echo "$current_util" | grep -oE '[0-9]+' | head -n 1)

        # 检查是否成功获取数字
        if ! [[ "$current_util" =~ ^[0-9]+$ ]]; then
            echo "警告: 从 $GPU_UTIL_FILE 读取到的值非预期数字: '$current_util'，跳过本次检查。"
             sleep "$CHECK_INTERVAL"
             continue # 跳过这次循环
        fi


        local current_timestamp=$(date '+%Y-%m-%d %H:%M:%S')

        # 在控制台显示当前值
        echo "当前 GPU 利用率: ${current_util}%  (检查时间: $current_timestamp)"

        # --- 核心逻辑 ---
        if [ "$current_util" -gt 0 ]; then
            # 当前利用率大于0
            if [ "$was_zero_last_time" -eq 1 ]; then
                # 从 0 变为非 0，新会话开始
                echo "新会话开始于 $current_timestamp"
                current_peak="$current_util" # 初始峰值就是当前值
                peak_time="$current_timestamp"
                was_zero_last_time=0 # 标记现在不是0了
            else
                # 会话持续中，检查是否是新的峰值
                if [ "$current_util" -gt "$current_peak" ]; then
                    current_peak="$current_util"
                    peak_time="$current_timestamp"
                    echo "新峰值记录: ${current_peak}% 发生在 ${peak_time}" # 可以选择性输出新峰值信息
                fi
            fi
        else
            # 当前利用率为 0
            if [ "$was_zero_last_time" -eq 0 ]; then
                # 刚从非 0 变为 0，会话结束
                record_peak_and_separate "$current_peak" "$peak_time"
                # 重置峰值记录
                current_peak=0
                peak_time=""
                was_zero_last_time=1 # 标记现在是0了
            else
                # 之前就是0，现在还是0，无需操作
                : # Bash no-op command
            fi
        fi

        # 等待下一个检查周期
        sleep "$CHECK_INTERVAL"

    done
}

# --- 主函数 ---
main(){
    1_0_load_env
    monitor_gpu
}

# --- 脚本入口 ---
# 添加 trap 以便在 Ctrl+C 退出时也能记录最后的峰值
trap 'echo "脚本被中断..."; record_peak_and_separate "$current_peak" "$peak_time"; echo "已记录最后峰值 (如果存在). 退出."; exit 0' SIGINT SIGTERM

main "$@"
