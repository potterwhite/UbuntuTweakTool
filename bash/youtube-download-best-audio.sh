#!/bin/bash

# YouTube Best Audio Downloader (Modular Version)
# Downloads best quality audio as MP3 with metadata and thumbnail.

load_environment() {
    # 1. Load environment variables
    if [ -f ~/.bashrc ]; then
        source ~/.bashrc
    fi
    # Add more if needed, e.g.:
    # [ -f ~/.profile ] && source ~/.profile
}

check_dependencies() {
    # 2. Check for required dependencies
    local deps=("yt-dlp" "ffmpeg" "aria2c" "deno")
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        echo "Error: Missing dependencies: ${missing[*]}"
        echo "Please install them, e.g.:"
        echo "  sudo apt install yt-dlp ffmpeg aria2   (Debian/Ubuntu)"
        echo "  sudo snap deno   (Debian/Ubuntu)"
        echo "  or"
        echo "  sudo dnf install yt-dlp ffmpeg aria2   (Fedora)"
        return 1
    fi
    return 0
}

validate_and_save_url() {
    # 3. Validate input URL and save to history
    if [ $# -ne 1 ]; then
        echo "Error: Exactly one URL is required."
        echo "Usage: $0 <URL>"
        return 1
    fi

    local url="$1"

    # Basic URL validation
    if ! [[ "$url" =~ ^https?://.+ ]]; then
        echo "Error: Invalid URL format. It must start with http:// or https://"
        return 1
    fi

    # Save to history file
    local HISTORY_FILE="$HOME/.yt_audio_history.txt"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $url" >> "$HISTORY_FILE"

    echo "$url"  # Return the validated URL via echo for main to capture
    return 0
}

download_audio() {
    # 4. Execute the yt-dlp download with optimized aria2c settings
    local url="$1"

    # Calculate parallel connections (cap at 16 CPUs)
    local ncpu=$(nproc)
    if [ "$ncpu" -gt 16 ]; then
        ncpu=16
    fi

    echo "Downloading best audio from: $url"
    echo "Using $ncpu parallel connections via aria2c"

    yt-dlp \
	--cookies-from-browser firefox \
        --no-playlist \
        -f bestaudio \
        --extract-audio \
        --audio-format mp3 \
        --audio-quality 0 \
        --embed-thumbnail \
        --embed-metadata \
        --add-metadata \
        --output "%(title)s [%(id)s].%(ext)s" \
        --ppa "ffmpeg:-metadata album='My Album'" \
        --downloader aria2c \
        --downloader-args "aria2c:-x $ncpu -s $ncpu -j $((ncpu/2 + 1))" \
	--remote-components ejs:github \
        "$url"

    if [ $? -eq 0 ]; then
        echo "Download completed successfully!"
        return 0
    else
        echo "Download failed."
        return 1
    fi
}

main() {
    load_environment

    if ! check_dependencies; then
        exit 1
    fi

    local url
    if ! url=$(validate_and_save_url "$@"); then
        exit 1
    fi

    if ! download_audio "$url"; then
        exit 1
    fi
}

# Start the script
main "$@"
