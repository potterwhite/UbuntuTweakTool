#!/bin/bash

# ==========================================
# 脚本配置区
# ==========================================
TARGET_CODEC="h264"
OUTPUT_SUFFIX="_H264"
# iPad Pro 2016 (A9X) 完美硬解参数: High Profile, yuv420p
#FFMPEG_OPTS="-c:v libx264 -preset medium -crf 23 -pix_fmt yuv420p -fps_mode passthrough"
# 解释：
# -c:v h264_nvenc : 使用显卡编码
# -preset p7      : 显卡编码质量设为“最慢/最好”（对于显卡来说依然很快）
# -cq 19          : 恒定质量 19（视觉无损的黄金点，接近原画）
# -b:v 0          : 必须设为0，让显卡完全由 -cq 参数控制码率，不要人为限制上限
FFMPEG_OPTS="-c:v h264_nvenc -preset p7 -cq 19 -b:v 0 -pix_fmt yuv420p -fps_mode passthrough"
# 音频转为 AAC 以确保最大兼容性 (Jellyfin Direct Play)
AUDIO_OPTS="-c:a aac -b:a 192k -ac 2"

# ==========================================
# 功能函数定义
# ==========================================

# [底层功能] 获取视频编码格式
# 返回值: 编码名称 (如 av1, h264, hevc)
func_1_3_get_video_codec() {
    local file_path="$1"
    local codec_name
    
    codec_name=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file_path")
    
    echo "$codec_name"
}

# [核心功能] 执行转码
# 输入: 源文件路径, 输出文件路径
func_1_4_exec_transcode() {
    local input="$1"
    local output="$2"
    
    echo "   >>> 正在启动 FFmpeg 转换..."
    echo "   >>> 目标: $output"
    
    # < /dev/null 防止 ffmpeg 吞掉 while 循环的标准输入
    # -map 0:v:0 选择第一个视频流
    # -map 0:a? 选择所有音频流(如果有)
    # -sn 暂时丢弃字幕(防止字幕格式不兼容导致容器封装失败，如ASS进MP4)，如需保留可尝试去掉-sn
    ffmpeg -n -v error -stats -i "$input" \
        -map 0:v:0 -map 0:a? \
        $FFMPEG_OPTS \
        $AUDIO_OPTS \
        -sn \
        "$output" < /dev/null
        
    return $?
}

# [逻辑控制] 处理单个文件
# 负责判断是否需要转换，计算文件名
func_1_2_process_single_file() {
    local file="$1"
    local codec
    
    # 1. 获取编码
    codec=$(func_1_3_get_video_codec "$file")
    
    # 如果获取不到编码（可能不是视频），直接返回
    if [ -z "$codec" ]; then
        return
    fi

    echo "[-] 扫描文件: $file (当前编码: $codec)"

    # 2. 判断是否已经是 H264
    if [ "$codec" == "$TARGET_CODEC" ]; then
        echo "   [!] 已是 H.264 格式，跳过。"
        return
    fi

    # 3. 分解文件名与后缀
    local filename=$(basename -- "$file")
    local dirname=$(dirname -- "$file")
    local extension="${filename##*.}"
    local name_no_ext="${filename%.*}"
    
    # 4. 构造输出文件名: 原名_H264.原后缀
    local output_file="${dirname}/${name_no_ext}${OUTPUT_SUFFIX}.${extension}"

    # 5. 调用转码函数
    func_1_4_exec_transcode "$file" "$output_file"
    
    if [ $? -eq 0 ]; then
        echo "   [√] 转换成功!"
    else
        echo "   [x] 转换失败或目标文件已存在。"
    fi
}

# [流程控制] 遍历目录
# 递归查找所有视频文件
func_1_1_traverse_directory() {
    local target_dir="$1"
    
    echo "正在扫描目录: $target_dir ..."
    
    # 查找常见视频后缀，排除以 _H264 结尾的文件防止重复处理
    find "$target_dir" -type f \
        \( -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" -o -name "*.webm" -o -name "*.mov" -o -name "*.flv" -o -name "*.wmv" \) \
        ! -name "*${OUTPUT_SUFFIX}.*" \
        -print0 | while IFS= read -r -d $'\0' file; do
            
            func_1_2_process_single_file "$file"
            
    done
}

# [入口] 主函数
main() {
    # 检查依赖
    if ! command -v ffmpeg &> /dev/null; then
        echo "错误: 未找到 ffmpeg，请先安装。"
        exit 1
    fi

    # 获取输入参数，默认为当前目录
    local work_dir="${1:-.}"
    
    if [ ! -d "$work_dir" ]; then
        echo "错误: 目录 '$work_dir' 不存在。"
        exit 1
    fi

    echo "=========================================="
    echo "开始批量转换任务 (目标: H.264 / iPad Pro 2016)"
    echo "工作目录: $work_dir"
    echo "=========================================="
    
    func_1_1_traverse_directory "$work_dir"
    
    echo "=========================================="
    echo "所有任务处理完成。"
    echo "=========================================="
}

# ==========================================
# 启动脚本
# ==========================================
main "$@"
