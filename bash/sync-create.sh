#!/bin/bash

# ==============================================================================
# Syncthing Docker 自动化管理脚本
# 支持命令行参数静默执行，或无参数交互式执行
# ==============================================================================

# 颜色输出格式
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 默认参数变量 (可被用户输入覆盖)
ACTION=""
DATA_DIR=""
CONFIG_DIR="$HOME/.config/syncthing"
PUID=$(id -u)
PGID=$(id -g)
COMPOSE_WORK_DIR="$HOME/.syncthing-docker"

# 打印帮助信息
show_help() {
    echo -e "${CYAN}用法: $0 [选项]${NC}"
    echo "如果不提供任何选项，脚本将进入交互式向导模式。"
    echo ""
    echo "选项:"
    echo "  --action <install|remove|rebuild>   要执行的动作 (安装/卸载/重建)"
    echo "  --data-dir <path>                   需要同步的数据目录 (例如: /home/user/ObsidianVault)"
    echo "  --config-dir <path>                 Syncthing 配置文件存放目录 (默认: $HOME/.config/syncthing)"
    echo "  --puid <UID>                        运行容器的用户UID (默认: 当前用户 $PUID)"
    echo "  --pgid <GID>                        运行容器的用户组GID (默认: 当前用户 $PGID)"
    echo "  -h, --help                          显示此帮助信息"
    echo ""
    echo "示例 (静默一键安装):"
    echo "  $0 --action install --data-dir /home/ubuntu/ObsidianVault"
}

# 检查依赖
check_dependencies() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}错误: 未安装 Docker。请先安装 Docker。${NC}"
        exit 1
    fi
    # 兼容 docker-compose (V1) 或 docker compose (V2)
    if docker compose version &> /dev/null; then
        DOCKER_CMD="docker compose"
    elif docker-compose --version &> /dev/null; then
        DOCKER_CMD="docker-compose"
    else
        echo -e "${RED}错误: 未安装 Docker Compose。请先安装。${NC}"
        exit 1
    fi
}

# 解析命令行参数
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --action) ACTION="$2"; shift ;;
        --data-dir) DATA_DIR="$2"; shift ;;
        --config-dir) CONFIG_DIR="$2"; shift ;;
        --puid) PUID="$2"; shift ;;
        --pgid) PGID="$2"; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo -e "${RED}未知参数: $1${NC}"; show_help; exit 1 ;;
    esac
    shift
done

# 交互式向导 (如果命令行未提供关键参数)
interactive_mode() {
    echo -e "${CYAN}=== Syncthing Docker 配置向导 ===${NC}"
    
    # 获取动作
    if [[ -z "$ACTION" ]]; then
        echo "请选择你要执行的操作:"
        echo "  1) 安装/启动 (Install)"
        echo "  2) 卸载/停止 (Remove)"
        echo "  3) 重建/重启 (Rebuild)"
        read -p "请输入数字 [1/2/3]: " action_choice
        case $action_choice in
            1) ACTION="install" ;;
            2) ACTION="remove" ;;
            3) ACTION="rebuild" ;;
            *) echo -e "${RED}无效输入，退出。${NC}"; exit 1 ;;
        esac
    fi

    # 获取同步目录 (仅在安装或重建时需要)
    if [[ "$ACTION" != "remove" && -z "$DATA_DIR" ]]; then
        echo ""
        echo -e "${YELLOW}请输入你需要同步的文件夹绝对路径 (例如: $HOME/Sync):${NC}"
        read -p "数据目录: " DATA_DIR
        while [[ -z "$DATA_DIR" ]]; do
            echo -e "${RED}数据目录不能为空！${NC}"
            read -p "数据目录: " DATA_DIR
        done
    fi

    # 获取配置目录
    if [[ "$ACTION" != "remove" ]]; then
        read -p "请输入配置文件存放目录 [$CONFIG_DIR]: " input_config
        CONFIG_DIR=${input_config:-$CONFIG_DIR}
    fi
}

# 如果没有提供ACTION，则触发交互式模式
if [[ -z "$ACTION" || (-z "$DATA_DIR" && "$ACTION" != "remove") ]]; then
    interactive_mode
fi

# 确保路径是绝对路径 (Docker required)
if [[ -n "$DATA_DIR" ]]; then
    DATA_DIR=$(readlink -m "$DATA_DIR")
fi
CONFIG_DIR=$(readlink -m "$CONFIG_DIR")

# 生成 docker-compose.yml 文件
generate_compose_file() {
    mkdir -p "$COMPOSE_WORK_DIR"
    cat > "$COMPOSE_WORK_DIR/docker-compose.yml" <<EOF
version: "3.8"
services:
  syncthing:
    image: lscr.io/linuxserver/syncthing:latest
    container_name: syncthing
    environment:
      - PUID=$PUID
      - PGID=$PGID
      - TZ=Asia/Shanghai
    volumes:
      - $CONFIG_DIR:/config
      - $DATA_DIR:/data
    network_mode: host
    restart: unless-stopped
EOF
    echo -e "${GREEN}[OK] 已生成 Docker Compose 文件到 $COMPOSE_WORK_DIR${NC}"
}

# 执行: 安装
do_install() {
    echo -e "${CYAN}准备安装并启动 Syncthing...${NC}"
    mkdir -p "$DATA_DIR" "$CONFIG_DIR"
    generate_compose_file
    cd "$COMPOSE_WORK_DIR" || exit 1
    $DOCKER_CMD pull
    $DOCKER_CMD up -d
    echo -e "${GREEN}====================================================${NC}"
    echo -e "${GREEN}🎉 Syncthing 启动成功!${NC}"
    echo -e "Web 控制台: ${YELLOW}http://localhost:8384${NC}"
    echo -e "数据挂载点: ${YELLOW}$DATA_DIR${NC}"
    echo -e "配置文件点: ${YELLOW}$CONFIG_DIR${NC}"
    echo -e "${GREEN}====================================================${NC}"
}

# 执行: 卸载
do_remove() {
    echo -e "${YELLOW}准备停止并删除 Syncthing 容器...${NC}"
    if [[ -f "$COMPOSE_WORK_DIR/docker-compose.yml" ]]; then
        cd "$COMPOSE_WORK_DIR" || exit 1
        $DOCKER_CMD down
        echo -e "${GREEN}[OK] 容器已停止并删除。${NC}"
    else
        # 强制删除可能存在的同名容器
        docker rm -f syncthing &>/dev/null
        echo -e "${GREEN}[OK] 容器已强制清理。${NC}"
    fi

    # 提供清理选项 (安全起见，默认不删除用户数据)
    echo ""
    read -p "是否要删除 Syncthing 的【配置文件】? (仅配置，不影响你的同步文件) [y/N]: " clean_cfg
    if [[ "$clean_cfg" =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        echo -e "${GREEN}[OK] 配置文件已删除: $CONFIG_DIR${NC}"
    fi
    echo -e "${GREEN}卸载完成。你的数据目录 ($DATA_DIR) 完好无损。${NC}"
}

# 执行: 重建
do_rebuild() {
    echo -e "${CYAN}准备重建 Syncthing...${NC}"
    if [[ -f "$COMPOSE_WORK_DIR/docker-compose.yml" ]]; then
        cd "$COMPOSE_WORK_DIR" || exit 1
        $DOCKER_CMD down
    else
        docker rm -f syncthing &>/dev/null
    fi
    do_install
}

# ================= 核心执行逻辑 =================
check_dependencies

case "$ACTION" in
    install)
        do_install
        ;;
    remove)
        do_remove
        ;;
    rebuild)
        do_rebuild
        ;;
    *)
        echo -e "${RED}错误: 未知的动作 '$ACTION'${NC}"
        exit 1
        ;;
esac

exit 0
