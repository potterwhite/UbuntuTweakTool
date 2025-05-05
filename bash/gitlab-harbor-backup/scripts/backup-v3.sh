#!/bin/bash
# 备份和恢复 GitLab 和 Harbor 的脚本
#
# 使用方法：
#   ./backup.sh {backup|restore} {gitlab|harbor|all} [gitlab|harbor]...
#
# 示例：
#   备份 GitLab 和 Harbor： ./backup.sh backup all
#   只备份 GitLab：         ./backup.sh backup gitlab
#   只备份 Harbor：         ./backup.sh backup harbor
#   同时备份 GitLab 和 Harbor：./backup.sh backup gitlab harbor
#
#   恢复 GitLab 和 Harbor： ./backup.sh restore all
#   只恢复 GitLab：         ./backup.sh restore gitlab
#   只恢复 Harbor：         ./backup.sh restore harbor
#   同时恢复 GitLab 和 Harbor：./backup.sh restore gitlab harbor

# 设置环境变量和路径
1_0_setup_env(){

	if [ "${V}" != "" ];then
		set -x
	fi

	# --- 检查是否以 root 权限运行 ---
	if [ "$(id -u)" -ne 0 ]; then
	   echo "错误：此脚本需要以 root 权限运行。" >&2
	   echo "请尝试使用 'sudo $0 $*'" >&2 # 提示用户正确的运行方式
	   exit 1 # 退出脚本
	fi
	# --- 检查结束 ---

	# 定义备份存储目录
	local BACKUP_DIR="/development/backup"
	GITLAB_BACKUP_DIR="${BACKUP_DIR}/part-i"
	HARBOR_BACKUP_DIR="${BACKUP_DIR}/part-ii"

	# 定义 Harbor 安装目录 (包含 docker-compose.yml)
	local HARBOR_base_dir="/development/b-harbor/harbor-v2"
	HARBOR_DIR="${HARBOR_base_dir}/harbor"
	# 定义 Harbor 数据存储目录 (对应 harbor.yml 中的 data_volume)
	#HARBOR_DATA="/development/b-harbor/harbor2025/data"
	HARBOR_DATA="${HARBOR_base_dir}/data"

	HARBOR_OFFLINE_PKG="harbor-offline-installer-v2.13.0.tgz"

	# 确保备份目录存在
	#mkdir -p "$BACKUP_DIR" || { echo "错误：无法创建备份目录 $BACKUP_DIR！" >&2; exit 1; }

	echo "环境变量设置完成。"
	echo "Gitlab备份目录：$GITLAB_BACKUP_DIR"
	echo "Harbor备份目录：$HARBOR_BACKUP_DIR"
	echo "Harbor 目录：$HARBOR_DIR"
	echo "Harbor 数据目录：$HARBOR_DATA"
	echo "" # 打印空行增加可读性
}

# 备份 GitLab 函数 (原逻辑未修改)
backup_gitlab() {
  echo "======== 开始备份 GitLab ========"

  gitlab-backup create
  # 使用 find 查找最新的 .tar 文件，避免通配符问题
  BACKUP_FILE=$(find /var/opt/gitlab/backups/ -maxdepth 1 -name "*_gitlab_backup.tar" -type f -printf "%T@ %p\n" | sort -nr | head -n 1 | cut -d' ' -f2)

  # 添加文件名检查
  if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
      echo "错误：未在 /var/opt/gitlab/backups/ 中找到最新的 GitLab 备份文件 (*_gitlab_backup.tar)！" >&2
      exit 1
  fi

  echo "找到最新的 GitLab 备份文件：$BACKUP_FILE"
  echo "复制备份文件和配置文件到 $GITLAB_BACKUP_DIR ..."

  # 复制备份文件
  cp "$BACKUP_FILE" "$GITLAB_BACKUP_DIR/" || { echo "错误：复制 GitLab 备份文件失败！" >&2; exit 1; }
  # 复制 secrets.json
  cp /etc/gitlab/gitlab-secrets.json "$GITLAB_BACKUP_DIR/" || { echo "警告：复制 gitlab-secrets.json 失败，可能需要手动备份！" >&2; }
  # 复制 gitlab.rb
  cp /etc/gitlab/gitlab.rb "$GITLAB_BACKUP_DIR/" || { echo "警告：复制 gitlab.rb 失败，可能需要手动备份！" >&2; }

  echo "======== GitLab 备份完成，存储在 $GITLAB_BACKUP_DIR ========"
  echo "" # 打印空行增加可读性
}

# 备份 Harbor 函数 (原逻辑未修改，仅独立出来)
backup_harbor() {
  echo "======== 开始备份 Harbor ========"

  # 检查 Harbor 目录是否存在
  if [ ! -d "$HARBOR_DIR" ]; then
      echo "错误：Harbor 目录 $HARBOR_DIR 不存在！无法备份 Harbor。" >&2
      exit 1
  fi
   if [ ! -d "$HARBOR_DATA" ]; then
      echo "错误：Harbor 数据目录 $HARBOR_DATA 不存在！请检查 HARBOR_DATA 变量。" >&2
      exit 1
  fi

  cd "$HARBOR_DIR" || { echo "错误：无法进入 Harbor 目录 $HARBOR_DIR！" >&2; exit 1; }

  echo "停止 Harbor 容器..."
  docker-compose down || { echo "警告：停止 Harbor 容器失败，可能需要手动处理！" >&2; }

  echo "备份 Harbor 数据目录 $HARBOR_DATA..."
  # 使用日期时间戳命名备份文件，以便区分和选择恢复点
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  local harbor_data_backup="$HARBOR_BACKUP_DIR/harbor_data_backup_$timestamp.tar.gz"
  local harbor_certs_backup="$HARBOR_BACKUP_DIR/harbor_certs_backup_$timestamp.tar.gz"

  tar -czf "$harbor_data_backup" "$HARBOR_DATA" || { echo "错误：备份 Harbor 数据失败！" >&2; exit 1; }
  echo "Harbor 数据备份到 $harbor_data_backup"

  echo "备份 Harbor 证书目录 /etc/harbor/certs ..."
  # 检查证书目录是否存在 (如果使用默认配置，通常会有)
  if [ -d "/etc/harbor/certs" ]; then
      tar -czf "$harbor_certs_backup" /etc/harbor/certs || { echo "错误：备份 Harbor 证书失败！" >&2; exit 1; }
       echo "Harbor 证书备份到 $harbor_certs_backup"
  else
      echo "警告：Harbor 证书目录 /etc/harbor/certs 不存在，跳过证书备份。" >&2
  fi


  echo "复制 harbor.yml 配置文件..."
  cp "$HARBOR_DIR/harbor.yml" "$HARBOR_BACKUP_DIR/harbor.yml_$timestamp" || { echo "警告：复制 harbor.yml 失败！" >&2; }
  echo "harbor.yml 备份到 $HARBOR_BACKUP_DIR/harbor.yml_$timestamp"


  echo "启动 Harbor 容器..."
  docker-compose up -d || { echo "警告：启动 Harbor 容器失败，可能需要手动处理！" >&2; }

  echo "======== Harbor 备份完成，存储在 $HARBOR_BACKUP_DIR ========"
  echo "" # 打印空行增加可读性
}

# 恢复 GitLab 函数 (原逻辑未修改，仅独立出来)
restore_gitlab() {
  echo "======== 开始恢复 GitLab ========"


  # 1. 在备份目录中找到最新的 GitLab 备份文件
  # 使用 find 查找最新的 *_gitlab_backup.tar 文件
  LATEST_GL_BACKUP=$(find "$GITLAB_BACKUP_DIR" -maxdepth 1 -name "*_gitlab_backup.tar" -type f -printf "%T@ %p\n" | sort -nr | head -n 1 | cut -d' ' -f2)

  if [ -z "$LATEST_GL_BACKUP" ] || [ ! -f "$LATEST_GL_BACKUP" ]; then
      echo "错误：在 $GITLAB_BACKUP_DIR 中未找到 GitLab 备份文件 (*_gitlab_backup.tar)！无法执行恢复。" >&2
      exit 1
  fi
  echo "找到最新的 GitLab 备份文件：$LATEST_GL_BACKUP"

  # 2. 将备份文件复制到 GitLab 默认的备份目录
  echo "复制备份文件到 /var/opt/gitlab/backups/..."
  # 使用 basename 获取文件名，防止路径问题
  GL_BACKUP_FILENAME=$(basename "$LATEST_GL_BACKUP")
  # 使用 rsync 带有进度显示，更适合大文件
  rsync -av --progress "$LATEST_GL_BACKUP" /var/opt/gitlab/backups/ || { echo "错误：复制 GitLab 备份文件失败！" >&2; exit 1; }
  echo "备份文件 $GL_BACKUP_FILENAME 已复制到 /var/opt/gitlab/backups/"

  # 3. 复制 gitlab-secrets.json 和 gitlab.rb
  echo "复制配置文件 gitlab-secrets.json 和 gitlab.rb..."
  if [ -f "$GITLAB_BACKUP_DIR/gitlab-secrets.json" ]; then
      cp "$GITLAB_BACKUP_DIR/gitlab-secrets.json" /etc/gitlab/ || { echo "警告：复制 gitlab-secrets.json 失败！" >&2; }
      echo "gitlab-secrets.json 复制完成。"
  else
      echo "警告：未在 $GITLAB_BACKUP_DIR 找到 gitlab-secrets.json，跳过复制。恢复后可能需要手动处理 secrets！" >&2
  fi

  if [ -f "$GITLAB_BACKUP_DIR/gitlab.rb" ]; then
      cp "$GITLAB_BACKUP_DIR/gitlab.rb" /etc/gitlab/ || { echo "警告：复制 gitlab.rb 失败！" >&2; }
      echo "gitlab.rb 复制完成。"
  else
      echo "警告：未在 $GITLAB_BACKUP_DIR 找到 gitlab.rb，跳过复制。恢复后请手动检查配置！" >&2
  fi

  # 4. 停止 GitLab 服务
  echo "停止 GitLab 服务 (puma, sidekiq, mailroom)..."
  gitlab-ctl stop puma sidekiq mailroom || { echo "警告：停止部分 GitLab 服务失败，尝试继续..." >&2; }
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
  # 注意：原脚本注释掉了 --force。保留原样，可能需要交互确认。
  gitlab-backup restore BACKUP="$BACKUP_TIMESTAMP"
  # 检查上一个命令的退出状态
  if [ $? -ne 0 ]; then
      echo "错误：GitLab 恢复命令执行失败！请手动检查！" >&2
      exit 1
  fi
  echo "GitLab 核心数据恢复完成。"

  # 7. 重新配置并启动 GitLab
  echo "重新配置 GitLab..."
  gitlab-ctl reconfigure || { echo "错误：GitLab 重新配置失败！请手动检查！" >&2; exit 1; }

  echo "启动 GitLab 服务..."
  gitlab-ctl start || { echo "错误：GitLab 服务启动失败！请手动检查！" >&2; exit 1; }

  echo "======== GitLab 恢复流程完成。建议手动运行 'sudo gitlab-rake gitlab:check SANITIZE=true' 进行全面检查。========"
  echo "" # 打印空行增加可读性
}

init_harbor(){

	sudo mkdir -p /etc/harbor/certs
	sudo mkdir -p ${HARBOR_DIR}
	sudo mkdir -p ${HARBOR_DATA}

	# 更新系统包
	sudo apt update

	# 安装docker和docker-compose	
	sudo apt install -y docker.io docker-compose docker-compose-v2
	sudo apt install openssl

	# 启动docker服务并设置开机自启
	sudo systemctl start docker
	sudo systemctl enable docker

	#dirname for we will create the dir "harbor" manually, so enter parent dir
	tar axvf ${HARBOR_BACKUP_DIR}/${HARBOR_OFFLINE_PKG} -C $(dirname ${HARBOR_DIR})
	#tar axvf ${HARBOR_BACKUP_DIR}/${HARBOR_OFFLINE_PKG} -C ${HARBOR_DIR}


	sudo openssl req -x509 -newkey rsa:4096 -nodes -sha256 -days 36500 \
	  -keyout /etc/harbor/certs/harbor.key \
	  -out /etc/harbor/certs/harbor.crt \
	  -subj "/CN=192.168.3.67" \
	  -addext "subjectAltName=IP:192.168.3.67"
	sudo chmod 644 /etc/harbor/certs/harbor.crt
	sudo chmod 600 /etc/harbor/certs/harbor.key
	openssl x509 -in /etc/harbor/certs/harbor.crt -text -noout
	ls -lha /etc/harbor/certs/

	# 停止所有容器
	sudo docker stop nginx harbor-jobservice registryctl harbor-portal harbor-core harbor-db registry redis harbor-log

	# 删除所有容器	
	sudo docker rm -f nginx harbor-jobservice registryctl harbor-portal harbor-core harbor-db registry redis harbor-log

	# 删除网络
	sudo docker network rm harbor_harbor

	# 验证容器和网络删除
	sudo docker ps -a --filter "name=nginx|harbor-jobservice|registryctl|harbor-portal|harbor-core|harbor-db|registry|redis|harbor-log"
	sudo docker network ls --filter "name=harbor_harbor"

	# 可选：删除所有 goharbor/* 镜像（执行前确认是否需要）
	sudo docker images --filter "reference=goharbor/*" --format "{{.Repository}}:{{.Tag}}" | xargs -r sudo docker rmi -f

	# 可选：验证镜像删除
	sudo docker images --filter "reference=goharbor/*"

	# 可选：检查和删除数据卷（谨慎操作）
	sudo docker volume ls
	sudo docker volume rm $(sudo docker volume ls --filter "name=harbor" -q)

}

# 恢复 Harbor 函数 (根据原注释部分独立出来，并添加一些检查)
restore_harbor() {
  echo "======== 开始恢复 Harbor ========"

  init_harbor

   # 检查 Harbor 目录是否存在
  if [ ! -d "$HARBOR_DIR" ]; then
      echo "错误：Harbor 目录 $HARBOR_DIR 不存在！无法恢复 Harbor。" >&2
      exit 1
  fi
   if [ ! -d "$HARBOR_DATA" ]; then
      echo "警告：Harbor 数据目录 $HARBOR_DATA 不存在或不符合预期。请检查 HARBOR_DATA 变量和实际情况。" >&2
      # 不退出，让用户手动确认是否继续，或者脚本假定恢复会创建目录
  fi

  # --- 寻找最新的 Harbor 备份文件 ---
  echo "在 $HARBOR_BACKUP_DIR 中寻找最新的 Harbor 备份文件..."
  # 寻找最新的数据备份
  LATEST_HARBOR_DATA_BACKUP=$(find "$HARBOR_BACKUP_DIR" -maxdepth 1 -name "harbor_data_backup_*.tar.gz" -type f -printf "%T@ %p\n" | sort -nr | head -n 1 | cut -d' ' -f2)
  # 寻找最新的证书备份
  LATEST_HARBOR_CERTS_BACKUP=$(find "$HARBOR_BACKUP_DIR" -maxdepth 1 -name "harbor_certs_backup_*.tar.gz" -type f -printf "%T@ %p\n" | sort -nr | head -n 1 | cut -d' ' -f2)
  # 寻找最新的 harbor.yml 备份
  LATEST_HARBOR_YML_BACKUP=$(find "$HARBOR_BACKUP_DIR" -maxdepth 1 -name "harbor_*.yml" -type f -printf "%T@ %p\n" | sort -nr | head -n 1 | cut -d' ' -f2)


  if [ -z "$LATEST_HARBOR_DATA_BACKUP" ]; then
      echo "错误：在 $HARBOR_BACKUP_DIR 中未找到 Harbor 数据备份文件 (harbor_data_backup_*.tar.gz)！无法执行恢复。" >&2
      exit 1
  fi
   echo "找到最新的 Harbor 数据备份文件：$LATEST_HARBOR_DATA_BACKUP"

  if [ -z "$LATEST_HARBOR_CERTS_BACKUP" ]; then
      echo "警告：在 $HARBOR_BACKUP_DIR 中未找到 Harbor 证书备份文件 (harbor_certs_backup_*.tar.gz)。将跳过证书恢复。" >&2
      # 不退出，证书可能不常用或者有其他方式管理
  else
       echo "找到最新的 Harbor 证书备份文件：$LATEST_HARBOR_CERTS_BACKUP"
  fi

  if [ -z "$LATEST_HARBOR_YML_BACKUP" ]; then
      echo "警告：在 $HARBOR_BACKUP_DIR 中未找到 harbor.yml 备份文件 (harbor.yml_*)。将跳过配置文件恢复。" >&2
      # 不退出，配置文件可能手动修改或者有其他方式管理
  else
       echo "找到最新的 harbor.yml 备份文件：$LATEST_HARBOR_YML_BACKUP"
	sed -i "s@^[[:space:]]*#\?[[:space:]]*data_volume:.*@data_volume: ${HARBOR_DATA}@" ${LATEST_HARBOR_YML_BACKUP}
  fi
   echo "" # 打印空行增加可读性
  # --- 寻找结束 ---


  cd "$HARBOR_DIR" || { echo "错误：无法进入 Harbor 目录 $HARBOR_DIR！" >&2; exit 1; }

  echo "$(pwd -P)"
#  echo "停止 Harbor 容器..."
#  docker-compose down || { echo "警告：停止 Harbor 容器失败，尝试继续恢复。请手动检查 Harbor 状态！" >&2; }

  echo "恢复 Harbor 数据..."
  # 恢复数据，覆盖现有内容。-C / 表示解压到根目录，因为备份时打包的是绝对路径（/development/...）。
  # 请确保 HARBOR_DATA 变量和打包时的实际路径一致，否则恢复可能出错！
  #tar -axvf "$LATEST_HARBOR_DATA_BACKUP" -C / || { echo "错误：恢复 Harbor 数据失败！" >&2; exit 1; }
  tar -axvf "$LATEST_HARBOR_DATA_BACKUP" -C $(dirname ${HARBOR_DATA})  || { echo "错误：恢复 Harbor 数据失败！" >&2; exit 1; }
  echo "Harbor 数据恢复完成。"

  if [ -n "$LATEST_HARBOR_CERTS_BACKUP" ]; then
      echo "恢复 Harbor 证书..."
      # 恢复证书。备份时打包的是绝对路径（/etc/harbor/certs/...），-C / 表示解压到根目录。
      # 请确保实际的证书存储路径就是 /etc/harbor/certs！
      tar -axvf "$LATEST_HARBOR_CERTS_BACKUP" -C / || { echo "警告：恢复 Harbor 证书失败！请手动检查证书！" >&2; }
      echo "Harbor 证书恢复完成。"
  fi

  if [ -n "$LATEST_HARBOR_YML_BACKUP" ]; then
      echo "恢复 Harbor 配置文件..."
      # 复制配置文件
      cp "$LATEST_HARBOR_YML_BACKUP" "$HARBOR_DIR/harbor.yml" || { echo "警告：复制 harbor.yml 失败！请手动检查配置文件！" >&2; }
      echo "Harbor 配置文件恢复完成，已复制到 $HARBOR_DIR/harbor.yml"
  fi


  echo "启动 Harbor 容器..."
  sudo ./install.sh
  #docker-compose up -d || { echo "错误：启动 Harbor 容器失败！请手动检查 Harbor 状态！" >&2; exit 1; }

  echo "======== Harbor 恢复流程完成 ========"
  echo "" # 打印空行增加可读性
}


# 主逻辑函数
main(){
	# 调用环境变量设置函数
	1_0_setup_env

	# 获取操作类型 (backup 或 restore)
	local action="$1"
	# 移除第一个参数，剩下的参数是组件列表
	shift

	# 获取组件列表 (gitlab, harbor, all)
	local components=("$@")

	# 用于标记是否需要执行 GitLab 或 Harbor 的操作
	local do_gitlab=false
	local do_harbor=false

	# --- 参数校验 ---
	if [ -z "$action" ]; then
		echo "错误：未指定操作 (backup 或 restore)。" >&2
		echo "使用方法：$0 {backup|restore} {gitlab|harbor|all} [gitlab|harbor]..."
		exit 1
	fi

	# 检查操作类型是否有效
	case "$action" in
		backup|restore)
			;; # 有效的操作类型
		*)
			echo "错误：无效的操作 '$action'。必须是 'backup' 或 'restore'。" >&2
			echo "使用方法：$0 {backup|restore} {gitlab|harbor|all} [gitlab|harbor]..."
			exit 1
			;;
	esac

	if [ ${#components[@]} -eq 0 ]; then
		echo "错误：未指定要操作的组件 (gitlab, harbor, 或 all)。" >&2
		echo "使用方法：$0 {backup|restore} {gitlab|harbor|all} [gitlab|harbor]..."
		exit 1
	fi
	# --- 参数校验结束 ---


	# --- 解析组件参数 ---
	local all_specified=false
	for component in "${components[@]}"; do
		case "$component" in
			gitlab)
				do_gitlab=true
				;;
			harbor)
				do_harbor=true
				;;
			all)
				all_specified=true
				do_gitlab=true # 如果指定了 all，则同时处理 gitlab 和 harbor
				do_harbor=true
				break # 如果指定了 all，则忽略后续的组件参数
				;;
			*)
				echo "错误：无效的组件 '$component'。必须是 'gitlab', 'harbor', 或 'all'。" >&2
				echo "使用方法：$0 {backup|restore} {gitlab|harbor|all} [gitlab|harbor]..."
				exit 1
				;;
		esac
	done
	# --- 解析组件参数结束 ---


	# --- 执行指定的操作和组件 ---
	echo "执行操作: $action"
	echo "目标组件:"
	[ "$do_gitlab" = true ] && echo "- GitLab"
	[ "$do_harbor" = true ] && echo "- Harbor"
    echo "" # 打印空行增加可读性

    # 如果指定了 'all'，按照原脚本备份的顺序执行 (GitLab -> Harbor)
    # 如果是恢复 'all'，考虑到 Harbor 数据恢复可能需要先于 GitLab (如果 GitLab 依赖 Harbor 镜像)，
    # 但原脚本的恢复部分只写了 GitLab，且 GitLab 恢复包含了停止/启动自身服务。
    # 为了保持独立性并遵循原脚本逻辑（GitLab先），我们按 GitLab -> Harbor 的顺序执行。
    # 请注意：实际生产环境中恢复顺序可能需要根据服务间的依赖关系仔细设计！
	if [ "$do_gitlab" = true ]; then
		if [ "$action" = "backup" ]; then
			backup_gitlab
		else # action is restore
			restore_gitlab
		fi
	fi

	if [ "$do_harbor" = true ]; then
		if [ "$action" = "backup" ]; then
			backup_harbor
		else # action is restore
			restore_harbor
		fi
	fi

    # 检查是否有任何操作被执行
    if [ "$do_gitlab" = false ] && [ "$do_harbor" = false ]; then
        echo "警告：没有指定任何有效的组件进行操作。请检查您的参数。" >&2
        echo "使用方法：$0 {backup|restore} {gitlab|harbor|all} [gitlab|harbor]..."
        exit 1
    fi
	# --- 执行结束 ---

	echo "所有指定操作已尝试完成。"
}

# 调用主函数，传递所有命令行参数
main "$@"
