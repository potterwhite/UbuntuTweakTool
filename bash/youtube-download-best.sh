#!/bin/bash

main(){
    if [ "$#" -lt 1 ];then # 允许至少一个参数 (URL)，也可以有其他 yt-dlp 参数
        echo "Usage: $0 <YOUTUBE_URL> [other yt-dlp options]"
        echo "Example: $0 \"https://www.youtube.com/watch?v=VIDEO_ID\""
        echo "Example: $0 \"https://www.youtube.com/watch?v=VIDEO_ID\" -o \"My Video.mp4\""
        return 1
    fi

    # SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
    # echo "Script path: ${SCRIPT_PATH}"
    #
    # SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
    # echo "Script directory: ${SCRIPT_DIR}"
    #
    # PWD_DIR="$(pwd -P)"
    # echo "Current working directory: ${PWD_DIR}"

    # 使用 yt-dlp (可能是 yt-dlp)
    # -f "bestvideo+bestaudio/best" 选择最佳视频和音频流
    # --merge-output-format mp4 合并为 mp4 格式
    # --embed-thumbnail 嵌入视频的缩略图作为封面
    # "$@" 将所有传递给脚本的参数都传递给 yt-dlp
    #   这样你就可以在命令行直接使用其他 yt-dlp 的选项，比如 -o 来指定输出文件名

    echo "Attempting to download and embed thumbnail for: $1"
    yt-dlp \
	--cookies-from-browser firefox \
        -f "bestvideo+bestaudio/best" \
        --merge-output-format mp4 \
        --embed-thumbnail \
        "$@" # 传递所有参数给下载工具

    if [ $? -eq 0 ]; then
        echo "Download and thumbnail embedding (if available) likely successful."
    else
        echo "An error occurred during download or processing."
    fi
}

main "$@"
