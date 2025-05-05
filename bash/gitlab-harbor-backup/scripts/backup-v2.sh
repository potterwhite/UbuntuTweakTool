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

  # 1. 在备份目录中找到最新的 GitLab 备份文件
  # 使用 find 查找最新的 *_gitlab_backup.tar 文件
  LATEST_GL_BACKUP=$(find "$BACKUP_DIR" -maxdepth 1 -name "*_gitlab_backup.tar" -type f -printf "%T@ %p\n" | sort -nr | head -n 1 | cut -d' ' -f2)

  if [ -z "$LATEST_GL_BACKUP" ] || [ ! -f "$LATEST_GL_BACKUP" ]; then
      echo "错误：在 $BACKUP_DIR 中未找到 GitLab 备份文件 (*_gitlab_backup.tar)！"
      exit 1
  fi
  echo "找到最新的 GitLab 备份文件：$LATEST_GL_BACKUP"

  # 2. 将备份文件复制到 GitLab 默认的备份目录
  echo "复制备份文件到 /var/opt/gitlab/backups/..."
  # 使用 basename 获取文件名，防止路径问题
  GL_BACKUP_FILENAME=$(basename "$LATEST_GL_BACKUP")
  #cp "$LATEST_GL_BACKUP" /var/opt/gitlab/backups/
  rsync -av --progress "$LATEST_GL_BACKUP" /var/opt/gitlab/backups/
  if [ $? -ne 0 ]; then
      echo "错误：复制 GitLab 备份文件失败！"
      exit 1
  fi
  echo "备份文件 $GL_BACKUP_FILENAME 已复制到 /var/opt/gitlab/backups/"

  # 3. 复制 gitlab-secrets.json 和 gitlab.rb
  echo "复制配置文件 gitlab-secrets.json 和 gitlab.rb..."
  if [ -f "$BACKUP_DIR/gitlab-secrets.json" ]; then
      cp "$BACKUP_DIR/gitlab-secrets.json" /etc/gitlab/
      echo "gitlab-secrets.json 复制完成。"
  else
      echo "警告：未在 $BACKUP_DIR 找到 gitlab-secrets.json，跳过复制。"
  fi

  if [ -f "$BACKUP_DIR/gitlab.rb" ]; then
      cp "$BACKUP_DIR/gitlab.rb" /etc/gitlab/
      echo "gitlab.rb 复制完成。"
  else
      echo "警告：未在 $BACKUP_DIR 找到 gitlab.rb，跳过复制。"
  fi

  # 4. 停止 GitLab 服务
  echo "停止 GitLab 服务..."
  gitlab-ctl stop puma sidekiq mailroom
  # 给服务一些时间停止
  sleep 10

  # 5. 从文件名中提取备份时间戳
  # 文件名格式如：1746149566_2025_05_02_17.11.1_gitlab_backup.tar
  # 我们需要的是 1746149566_2025_05_02_17.11.1
  BACKUP_TIMESTAMP=${GL_BACKUP_FILENAME%_gitlab_backup.tar}
  echo "提取备份时间戳：$BACKUP_TIMESTAMP"

  # 6. 执行 GitLab 恢复命令
  echo "执行 GitLab 恢复命令..."
  # GitLab 恢复命令只需要备份文件的时间戳，并且期望备份文件在 /var/opt/gitlab/backups/ 目录下
  #gitlab-backup restore BACKUP="$BACKUP_TIMESTAMP" --force # 添加 --force 避免交互提示
  gitlab-backup restore BACKUP="$BACKUP_TIMESTAMP"
  # 检查上一个命令的退出状态
  if [ $? -ne 0 ]; then
      echo "错误：GitLab 恢复命令执行失败！请手动检查！"
      exit 1
  fi
  echo "GitLab 核心数据恢复完成。"

  # 7. 重新配置并启动 GitLab
  echo "重新配置 GitLab..."
  gitlab-ctl reconfigure
   if [ $? -ne 0 ]; then
      echo "错误：GitLab 重新配置失败！请手动检查！"
      exit 1
  fi

  echo "启动 GitLab 服务..."
  gitlab-ctl start
   if [ $? -ne 0 ]; then
      echo "错误：GitLab 服务启动失败！请手动检查！"
      exit 1
  fi

  echo "GitLab 恢复流程完成。建议手动运行 'sudo gitlab-rake gitlab:check SANITIZE=true' 进行全面检查。"

#  echo "开始恢复 Harbor..." # 这部分保持注释，直到你需要它
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
