#!/bin/bash
# 备份和恢复 GitLab 和 Harbor 的脚本
# 使用方法：
# 备份：./backup.sh backup
# 恢复：./backup.sh restore

1_0_setup_env(){

	# --- 检查是否以 root 权限运行 ---
	if [ "$(id -u)" -ne 0 ]; then
	   echo "错误：此脚本需要以 root 权限运行。" >&2
	   echo "请尝试使用 'sudo $0 $*'" >&2 # 提示用户正确的运行方式
	   exit 1 # 退出脚本
	fi
	# --- 检查结束 ---

	BACKUP_DIR="/development/backup"
	HARBOR_DIR="/development/b-harbor/harbor2025/harbor"
	HARBOR_DATA="/development/b-harbor/harbor2025/data"
}

# 备份函数
backup() {
  echo "开始备份 GitLab..."
  gitlab-backup create
  # 使用 find 查找最新的 .tar 文件，避免通配符问题
  BACKUP_FILE=$(find /var/opt/gitlab/backups/ -maxdepth 1 -name "*.tar" -type f -printf "%T@ %p\n" | sort -nr | head -n 1 | cut -d' ' -f2)
  echo -e "\nBACKUPFILE=${BACKUP_FILE}\n"
  if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
      cp "$BACKUP_FILE" "$BACKUP_DIR/"
      cp /etc/gitlab/gitlab-secrets.json "$BACKUP_DIR/"
      cp /etc/gitlab/gitlab.rb "$BACKUP_DIR/"
      echo "GitLab 备份完成，存储在 $BACKUP_DIR"
  else
      echo "错误：未找到 GitLab 备份文件！"
      exit 1
  fi
#  cp /var/opt/gitlab/backups/*.tar "$BACKUP_DIR/"
#  cp /etc/gitlab/gitlab-secrets.json "$BACKUP_DIR/"
#  cp /etc/gitlab/gitlab.rb "$BACKUP_DIR/"
#  echo "GitLab 备份完成，存储在 $BACKUP_DIR"

  echo "开始备份 Harbor..."
  cd "$HARBOR_DIR" && docker-compose down
  tar -czf "$BACKUP_DIR/harbor_data_backup.tar.gz" "$HARBOR_DATA"
  tar -czf "$BACKUP_DIR/harbor_certs_backup.tar.gz" /etc/harbor/certs
  cp "$HARBOR_DIR/harbor.yml" "$BACKUP_DIR/"
  cd "$HARBOR_DIR" && docker-compose up -d
  echo "Harbor 备份完成，存储在 $BACKUP_DIR"
}

# 恢复函数
restore() {
  echo "开始恢复 GitLab..."
  rsync -av --progress "$BACKUP_DIR/gitlab_backup.tar" /var/opt/gitlab/backups/
  rsync -av --progress "$BACKUP_DIR/gitlab-secrets.json" /etc/gitlab/
  rsync -av --progress "$BACKUP_DIR/gitlab.rb" /etc/gitlab/
  gitlab-backup restore BACKUP="$BACKUP_DIR/gitlab_backup.tar"
  echo "GitLab 恢复完成"

#  echo "开始恢复 Harbor..."
#  cd "$HARBOR_DIR" && docker-compose down
#  tar -xzf "$BACKUP_DIR/harbor_data_backup.tar.gz" -C /
#  tar -xzf "$BACKUP_DIR/harbor_certs_backup.tar.gz" -C /etc/harbor/
#  cp "$BACKUP_DIR/harbor.yml" "$HARBOR_DIR/"
#  cd "$HARBOR_DIR" && docker-compose up -d
#  echo "Harbor 恢复完成"
}


main(){
	1_0_setup_env

	# 主逻辑
	case "$1" in
	  backup)
	    backup
	    ;;
	  restore)
	    restore
	    ;;
	  *)
	    echo "使用方法：$0 {backup|restore}"
	    exit 1
	    ;;
	esac

}

main "$@"
