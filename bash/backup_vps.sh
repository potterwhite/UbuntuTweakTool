#!/bin/bash

# ==========================================
# 默认配置 (如果没有通过参数传入，则使用以下默认值)
# ==========================================
REMOTE_USER="root"
REMOTE_PORT="22"
LOCAL_BASE_DIR="/tmp/test_backup"
KEEP_DAYS=30
SSH_KEY="$HOME/.ssh/id_rsa"
SETUP_CRON=0

# ==========================================
# 解析命令行参数
# ==========================================
# 帮助文档
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  --ip <IP>               (必填) 远程VPS的IP地址"
    echo "  --src-abs-dir <DIR>     (必填) 远程要备份的绝对路径"
    echo "  --user <USER>           远程用户名 (默认: root)"
    echo "  --port <PORT>           SSH端口号 (默认: 22)"
    echo "  --dest-dir <DIR>        本地存储备份的根目录 (默认: /tmp/test_backup)"
    echo "  --ssh-key <FILE>        SSH私钥绝对路径 (默认: ~/.ssh/id_rsa)"
    echo "  --keep-days <DAYS>      保留备份的天数 (默认: 30)"
    echo "  --setup-cron            不执行备份，而是将当前参数配置写入 Crontab 每天定时执行"
    echo "  -h, --help              显示此帮助信息"
    exit 1
}

# 循环解析参数
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ip) REMOTE_IP="$2"; shift ;;
        --src-abs-dir) SRC_DIR="$2"; shift ;;
        --user) REMOTE_USER="$2"; shift ;;
        --port) REMOTE_PORT="$2"; shift ;;
        --dest-dir) LOCAL_BASE_DIR="$2"; shift ;;
        --ssh-key) SSH_KEY="$2"; shift ;;
        --keep-days) KEEP_DAYS="$2"; shift ;;
        --setup-cron) SETUP_CRON=1 ;;
        -h|--help) show_help ;;
        *) echo "未知参数: $1"; show_help ;;
    esac
    shift
done

# 检查必填参数
if [ -z "$REMOTE_IP" ] || [ -z "$SRC_DIR" ]; then
    echo "❌ 错误：--ip 和 --src-abs-dir 是必填参数！"
    show_help
fi

# ==========================================
# 功能 1：一键配置 Crontab (定时任务)
# ==========================================
if [ "$SETUP_CRON" -eq 1 ]; then
    # 获取脚本的绝对路径
    SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0")
    
    # 确保本地备份目录存在，用于存放日志
    mkdir -p "${LOCAL_BASE_DIR}"
    
    # 拼接要写入 Cron 的完整命令 (不包含 --setup-cron)
    # 设定为每天凌晨 2:00 执行，并将日志输出到 backup_cron.log
    CRON_JOB="0 2 * * * ${SCRIPT_PATH} --ip ${REMOTE_IP} --src-abs-dir ${SRC_DIR} --user ${REMOTE_USER} --port ${REMOTE_PORT} --dest-dir ${LOCAL_BASE_DIR} --ssh-key ${SSH_KEY} --keep-days ${KEEP_DAYS} >> ${LOCAL_BASE_DIR}/backup_cron.log 2>&1"
    
    # 检查是否已经存在
    if crontab -l 2>/dev/null | grep -F "$SCRIPT_PATH" > /dev/null; then
        echo "⚠️ 警告：Crontab 中似乎已经包含此脚本的定时任务。请使用 'crontab -e' 手动检查。"
        exit 0
    fi
    
    # 写入 Crontab
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "✅ 成功！已将备份任务写入 Crontab。"
    echo "⏰ 每天凌晨 2:00 会自动执行备份。"
    echo "📝 备份日志将保存在: ${LOCAL_BASE_DIR}/backup_cron.log"
    exit 0
fi


# ==========================================
# 功能 2：执行核心备份流程 (带硬链接增量)
# ==========================================
DATETIME=$(date +%Y-%m-%d_%H-%M-%S)
TODAY_DIR="${LOCAL_BASE_DIR}/${DATETIME}"
LATEST_LINK="${LOCAL_BASE_DIR}/latest"

mkdir -p "${LOCAL_BASE_DIR}"

echo "----------------------------------------"
echo "开始时间: $(date)"
echo "从: ${REMOTE_USER}@${REMOTE_IP}:${SRC_DIR}"
echo "到: ${TODAY_DIR}"
echo "使用私钥: ${SSH_KEY}"
echo "----------------------------------------"

# 核心 rsync 命令
# 解析:
# -e "ssh -i ${SSH_KEY} -p ${REMOTE_PORT} -o StrictHostKeyChecking=no" 
#    -> 显式指定密钥！忽略 known_hosts 警告(防止定时任务时卡住)
rsync -avz --delete --numeric-ids \
      --rsync-path="sudo rsync" \
      -e "ssh -i ${SSH_KEY} -p ${REMOTE_PORT} -o StrictHostKeyChecking=no" \
      --link-dest="${LATEST_LINK}" \
      "${REMOTE_USER}@${REMOTE_IP}:${SRC_DIR}/" "${TODAY_DIR}/"

if [ $? -eq 0 ]; then
    echo "✅ 备份成功！文件存入: ${TODAY_DIR}"
    
    # 更新 latest 指针
    rm -f "${LATEST_LINK}"
    ln -s "${TODAY_DIR}" "${LATEST_LINK}"
    
    # 清理过期备份
    echo "🧹 清理超过 ${KEEP_DAYS} 天的旧备份..."
    find "${LOCAL_BASE_DIR}" -maxdepth 1 -type d -name "20*" -mtime +${KEEP_DAYS} -exec rm -rf {} \;
    echo "✅ 清理完成！"
    echo "结束时间: $(date)"
    echo "----------------------------------------"
else
    echo "❌ 备份失败！请检查上方报错信息。"
    rm -rf "${TODAY_DIR}"
    exit 1
fi
