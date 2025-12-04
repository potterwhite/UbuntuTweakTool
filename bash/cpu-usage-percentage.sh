#!/bin/sh

# 设置刷新间隔（秒）
INTERVAL=1

# 清除屏幕，准备实时显示
clear

# 读取初始的 CPU 时间数据
# 使用 awk 来处理，只关心以 "cpu" 后跟数字开头的行
PREV_STAT=$(awk '/^cpu[0-9]/ {print $1, $2, $3, $4, $5, $6, $7, $8}' /proc/stat)

# 进入无限循环，实时监控
while true; do
    # 等待指定的间隔时间
    sleep $INTERVAL

    # 读取当前的 CPU 时间数据
    CURR_STAT=$(awk '/^cpu[0-9]/ {print $1, $2, $3, $4, $5, $6, $7, $8}' /proc/stat)

    # 将上一次和这一次的数据合并，交给 awk 一次性处理
    # 使用 printf 可以安全地处理带有空格和换行的变量
    CPU_USAGE=$(printf "%s\n%s" "$PREV_STAT" "$CURR_STAT" | \
    awk '
        {
            # $1 是 CPU 的名字 (如 "cpu0")
            cpu_id = $1; 

            # 计算总时间：将所有时间片相加
            total_time = $2 + $3 + $4 + $5 + $6 + $7 + $8;

            # $5 是空闲时间
            idle_time = $5;

            # 如果我们已经存有这个CPU的上一次数据...
            if (cpu_id in prev_total) {
                # 计算总时间和空闲时间的差值
                total_delta = total_time - prev_total[cpu_id];
                idle_delta = idle_time - prev_idle[cpu_id];

                # 计算使用率
                # 防止除以零的错误
                if (total_delta > 0) {
                    usage = 100 * (total_delta - idle_delta) / total_delta;
                } else {
                    usage = 0;
                }

                # 格式化输出
                printf "%s: %5.2f%%\n", cpu_id, usage;
            }

            # 存储当前数据，作为下一次计算的"上一次数据"
            prev_total[cpu_id] = total_time;
            prev_idle[cpu_id] = idle_time;
        }
    ')
    
    # 将光标移动到左上角，准备重绘
    printf "\033[H"
    
    # 打印标题和计算出的使用率
    echo "--- CPU Usage (per core) ---"
    echo "$CPU_USAGE"
    echo "----------------------------"
    echo "(Press Ctrl+C to exit)"

    # 更新 PREV_STAT 以便下一次循环使用
    PREV_STAT="$CURR_STAT"
done
