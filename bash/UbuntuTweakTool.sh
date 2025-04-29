#!/bin/bash

get_user_confirmation() {
  while true; do
    read  -p "Please confirm (Y/n): " choice
    case $choice in
      [yY]|"")
        echo "true"
        return 0
        ;;
      [nN])
        echo "false"
        return 1
        ;;
      *)
        echo "Invalid input. Please enter y or n."
        ;;
    esac
  done
}

ctrl_c_handler() {
    echo -e "\nCtrl+C caught, cleaning up and exiting..."
    return 1
}

trap ctrl_c_handler SIGINT


echo "###############################################################################################"
echo "Require Administrator\`s Privillege"
echo "###############################################################################################"
sudo -v

echo "###############################################################################################"
echo "Replace APT source to china region"
echo "###############################################################################################"
if [[ ${1,,} == "all" ]] || get_user_confirmation; then


	tmp_backup_file=/opt/shell-scripts/batch_backup_system_origin_configs.sh
	if [[ -f "${tmp_backup_file}" ]];then
		sudo "${tmp_backup_file}"
	fi

	if [[ ! -f /etc/apt/sources.list.bak ]];then
		sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
	fi
	sudo tee /etc/apt/sources.list > /dev/null << EOF
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb-src https://mirrors.ustc.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb-src https://mirrors.ustc.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb-src https://mirrors.ustc.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
deb-src https://mirrors.ustc.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
deb https://mirrors.ustc.edu.cn/ubuntu/ jammy-proposed main restricted universe multiverse
deb-src https://mirrors.ustc.edu.cn/ubuntu/ jammy-proposed main restricted universe multiverse
EOF

	sudo apt-get update
	sudo apt-get upgrade -y

	# Essential tools for server
	sudo apt-get install -y \
		minicom \
		nfs-kernel-server \
		lm-sensors \
		python3-pip \
		openssh-server \
		nmap \
		curl \
		locate \
		net-tools \
		samba \
		smbclient \
		cifs-utils \
		pigz \
		git \
		vim

	# Optional GUI packages - only install if desktop environment detected
	if [[ -n $DISPLAY ]]; then
		echo "Desktop environment detected, installing GUI applications..."
		sudo apt-get install -y \
			vlc \
			screenfetch \
			fcitx5 \
			gnome-tweaks \
			dconf-editor
	else
		echo -e "\nNo desktop environment detected, skipping GUI applications."
	fi

else
  echo "User declined"
fi

echo "###############################################################################################"
echo "Shutdown Auto Upgrade"
echo "###############################################################################################"
if [[ ${1,,} == "all" ]] || get_user_confirmation; then
	sudo apt remove unattended-upgrades -y
else
  echo "User declined"
fi


echo "###############################################################################################"
echo "Grub Config"
echo "###############################################################################################"
if [[ ${1,,} == "all" ]] || get_user_confirmation; then
  echo "User confirmed"
  sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*quiet splash[^"]*"/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub
	sudo update-grub
else
  echo "User declined"
fi


echo "###############################################################################################"
echo "Ubuntu Pro Installation"
echo "###############################################################################################"
if [[ ${1,,} == "all" ]] || get_user_confirmation; then
  echo "User confirmed"
  echo "Please enter your Ubuntu Pro token (you can ctrl+c to jump over this step):"

  read -r tmp_token
  # check if the user press ctrl+c
  if [[ $? == 1 ]];then
	echo "User cancelled"
  else
		sudo pro attach ${tmp_token}
  fi

else
  echo "User declined"
fi


echo "###############################################################################################"
echo "tweak app installation"
echo "###############################################################################################"
if [[ ${1,,} == "all" ]] || get_user_confirmation; then
  echo "User confirmed"
  sudo apt-get install gnome-tweaks
else
  echo "User declined"
fi


echo "###############################################################################################"
echo "Chromium Browser Installation"
echo "###############################################################################################"
if [[ ${1,,} == "all" ]] || get_user_confirmation; then
  echo "User confirmed"
  sudo apt install chromium-browser
else
  echo "User declined"
fi

echo "###############################################################################################"
echo "Set Timezone (default to Asia/Hong_Kong)"
echo "###############################################################################################"
if [[ ${1,,} == "all" ]] || get_user_confirmation; then
  echo "User confirmed"
  echo "Now it is going to set timezone to Asia/Hong_Kong.(Y/n)"
  read -r tmp_bool
  if [[ ${tmp_bool,,} == "y" ]] || [[ ${tmp_bool,,} == "yes" ]] || [[ -z ${tmp_bool} ]]; then
    echo "Now setting timezone to Asia/Hong_Kong..."
    sudo timedatectl set-timezone Asia/Hong_Kong
	timedatectl status | grep "Time zone"
    echo "Done"
  else
    echo "You chose No"
	echo "And you can check all legal timezone by: timedatectl list-timezones"
	echo "Then use this command to set your desired timezone:"
	echo "sudo timedatectl set-timezone <your-timezone>"
  fi

else
  echo "User declined"
fi

echo "###############################################################################################"
echo "Ubuntu RTC Config to 1"
echo "###############################################################################################"
if [[ ${1,,} == "all" ]] || get_user_confirmation; then
  echo "User confirmed"
  sudo timedatectl set-local-rtc 1
	echo "Done"
else
  echo "User declined"
fi

echo "###############################################################################################"
echo "fstab disk auto mount script"
echo "###############################################################################################"
if [[ ${1,,} == "all" ]] || get_user_confirmation; then
	echo "User confirmed"
  sudo mkdir -p /mnt/256gb_kingston_nvmessd
	sudo mkdir -p /mnt/2tb_wd_purpleSurveillance_hdd
	sudo mkdir -p /mnt/2tb_wd_passport_hdd

	echo "Available UUIDs on your system:"
	echo "-------------------------------"
	# 列出所有UUID并添加序号
	mapfile -t uuid_list < <(ls -lha /dev/disk/by-uuid/)
	for i in "${!uuid_list[@]}"; do
		if [[ $i -eq 0 ]]; then continue; fi  # 跳过第一行(total行)
		echo "$i) ${uuid_list[$i]}"
	done
	echo "-------------------------------"

	# 询问Kingston NVMe SSD
	echo -e "\nWhich one is your Kingston NVMe SSD? (Enter the number, or press Enter to skip):"
	read -r nvme_choice
	if [[ -n "$nvme_choice" ]] && [[ "$nvme_choice" -gt 0 ]] && [[ "$nvme_choice" -lt ${#uuid_list[@]} ]]; then
		NVME_UUID=$(echo "${uuid_list[$nvme_choice]}" | awk '{print $9}')
		echo "Selected UUID: $NVME_UUID"
	fi

	# 询问WD Purple HDD
	echo -e "\nWhich one is your WD Purple Surveillance HDD? (Enter the number, or press Enter to skip):"
	read -r purple_choice
	if [[ -n "$purple_choice" ]] && [[ "$purple_choice" -gt 0 ]] && [[ "$purple_choice" -lt ${#uuid_list[@]} ]]; then
		PURPLE_UUID=$(echo "${uuid_list[$purple_choice]}" | awk '{print $9}')
		echo "Selected UUID: $PURPLE_UUID"
	fi

	# 询问WD Passport HDD
	echo -e "\nWhich one is your WD Passport HDD? (Enter the number, or press Enter to skip):"
	read -r passport_choice
	if [[ -n "$passport_choice" ]] && [[ "$passport_choice" -gt 0 ]] && [[ "$passport_choice" -lt ${#uuid_list[@]} ]]; then
		PASSPORT_UUID=$(echo "${uuid_list[$passport_choice]}" | awk '{print $9}')
		echo "Selected UUID: $PASSPORT_UUID"
	fi

	FSTAB_CONTENT='
										#localhost:/home/vmgithub/Development                         /mnt/baytto_tencent_cloud_ssh          nfs     port=3049,noatime,nofail,_netdev            0      0'

	# 只有当用户选择了UUID时才添加相应的挂载配置
	if [[ -n "${NVME_UUID}" ]]; then
		FSTAB_CONTENT+="
										UUID=${NVME_UUID}        /mnt/256gb_kingston_nvmessd            ext4    defaults,noatime,nofail            0       2"
	fi
	if [[ -n "${PURPLE_UUID}" ]]; then
		FSTAB_CONTENT+="
										UUID=${PURPLE_UUID}      /mnt/2tb_wd_purpleSurveillance_hdd     ntfs    defaults,noatime,nofail            0       2"
	fi
	if [[ -n "${PASSPORT_UUID}" ]]; then
		FSTAB_CONTENT+="
										UUID=${PASSPORT_UUID}    /mnt/2tb_wd_passport_hdd               ntfs    defaults,noatime,nofail            0       2"
	fi

	if ! sudo grep -q "UUID=" /etc/fstab; then
		echo -e "\tthe file is clean, writing process started"
		sudo bash -c "echo -e '${FSTAB_CONTENT}' | sed 's/^\t*//' >> /etc/fstab"
		echo "fstab has been updated successfully"
	else
		echo -e "\tWarning: UUIDs already exist in fstab. Please check /etc/fstab manually."
	fi

else
  echo "User declined"
fi


if [[ -n ${DISPLAY} ]];then
	echo "###############################################################################################"
	echo "fcitx5 chinese type method Installation "
	echo "###############################################################################################"
	if [[ ${1,,} == "all" ]] || get_user_confirmation; then
		echo "User confirmed"
		sudo apt install -y \
							fcitx5-chinese-addons \
							fcitx5-frontend-gtk4 \
							fcitx5-frontend-gtk3 \
							fcitx5-frontend-gtk2 \
							fcitx5-frontend-qt5
		wget https://github.com/felixonmars/fcitx5-pinyin-zhwiki/releases/download/0.2.4/zhwiki-20240426.dict
		mkdir -p ~/.local/share/fcitx5/pinyin/dictionaries/
		mv ./zhwiki-*.dict ~/.local/share/fcitx5/pinyin/dictionaries/

		if ! sudo grep -q "These vars are for fcitx chinese input" /etc/profile; then
			echo -e "\tthe file is clean, writing process started"
			PROFILE_CONTENT='
												##############################################################
												# These vars are for fcitx chinese input
												# Auto-generated by Ubuntu Tweak Tool
												##############################################################
												export XMODIFIERS=@im=fcitx
												export GTK_IM_MODULE=fcitx
												export QT_IM_MODULE=fcitx'

			sudo bash -c "echo -e ${PROFILE_CONTENT} | sed 's/^\t*//' >> /etc/profile"
		else
			echo -e "\tthe file is corrupted, writing process aborted."
		fi

		im-config
		sudo apt install -y gnome-tweaks
		fcitx5-configtool

		git clone https://github.com/catppuccin/fcitx5.git
		mkdir -p ~/.local/share/fcitx5/themes/
		cp -rfav ./fcitx5/src/* ~/.local/share/fcitx5/themes
		rm -rf ./fcitx5
		fcitx5-configtool
	else
		echo "User declined"
	fi
fi # end of if [[ -n ${DISPLAY} ]];then


echo "###############################################################################################"
echo "Samba Setup"
echo "###############################################################################################"
if [[ ${1,,} == "all" ]] || get_user_confirmation; then
  echo "User confirmed"

  # 获取当前用户名
  CURRENT_USER=$(whoami)
  echo "Current username is: ${CURRENT_USER}"
  echo "Do you want to use '${CURRENT_USER}' as the Samba admin user? (Y/n)"
  read -r use_current_user

  if [[ ${use_current_user,,} == "n" ]] || [[ ${use_current_user,,} == "no" ]]; then
    echo "Please enter the username you want to use:"
    read -r SAMBA_USER
  else
    SAMBA_USER=${CURRENT_USER}
  fi

  echo "Using '${SAMBA_USER}' as Samba admin user"

  # 原有的 Samba 安装和配置代码
  sudo apt update
  sudo apt install samba
  sudo systemctl restart smbd.service
  sudo systemctl enable smbd.service
  sudo systemctl status smbd.service

  sudo ufw allow samba comment "without this rule allowing, samba will take no response from server to clients"
  sudo ufw enable
  sudo ufw status

  sudo mkdir -p /mnt/sambashare_main_entry/
  sudo chgrp sambashare /mnt/sambashare_main_entry/
  sudo useradd -M -d /mnt/sambashare_main_entry/sambashare -s /usr/sbin/nologin -g sambashare sambashare
  sudo usermod -aG sambashare ${SAMBA_USER}
  sudo mkdir -p /mnt/sambashare_main_entry/sambashare
  sudo chmod 2775 /mnt/sambashare_main_entry/sambashare
  sudo chown sambashare: /mnt/sambashare_main_entry/sambashare
  sudo smbpasswd -a sambashare
  sudo smbpasswd -e sambashare

  sudo groupadd sambaadmin
  sudo useradd -M -d /mnt/sambashare_main_entry/sambaadmin -s /usr/sbin/nologin -g sambaadmin sambaadmin
  sudo usermod -aG sambaadmin ${SAMBA_USER}
  sudo usermod -aG sambashare sambaadmin
  sudo mkdir -p /mnt/sambashare_main_entry/sambaadmin
  sudo chown sambaadmin:sambaadmin /mnt/sambashare_main_entry/sambaadmin
  sudo chmod 2770 /mnt/sambashare_main_entry/sambaadmin
  sudo smbpasswd -a sambaadmin
  sudo smbpasswd -e sambaadmin

  SMB_CONTENT='[sambaadmin]
	path = /mnt/sambashare_main_entry/sambaadmin
	browseable = yes
	read only = no
	force create mode = 660
	force directory mode = 770
	valid users = @sambaadmin

[sambashare]
	comment = Samba on Ubuntu
	path = /mnt/sambashare_main_entry/sambashare
	read only = yes
	browsable = yes
	guest ok = yes
	create mask = 0660
	#create mask = 0775
	#create mask = 0600
	directory mask = 2770
	valid users = @sambaadmin @sambashare
	read list = guest nobody
	write list = @sambaadmin @sambashare

#   [samba priviledge] and [sambashare] - The names of the shares to use when logging in.
#    path - The path to the share.
#    browseable -  If the share is to be listed in the list of the available shares. By setting to no, other users won''t be able to see the share.
#    read only - If the users specified in the valid users list can write to this share.
#    force create mode - Sets the permissions for the files which are newly created.
#    force directory mode - Sets the permissions for the newly created directories in this share.
#    valid users - A list of users and groups that are allowed to access the share.'
  SMB_FILE="/etc/samba/smb.conf"

  if ! sudo grep -q "\[sambaadmin\]" ${SMB_FILE}; then
    echo -e "\tthe file is clean, writing process started"
    # sudo bash -c "echo -e '${SMB_CONTENT}' | sed 's/^\t*//' >> /etc/samba/smb.conf"
	echo -e "${SMB_CONTENT}" | sed 's/^\t*//' | sudo tee -a "${SMB_FILE}" > /dev/null
    # sudo echo -e '${FSTAB_CONTENT}' | sudo sed 's/^\t*//' >> ${SMB_FILE}

  else
    echo -e "\tthe file ${SMB_FILE} is corrupted, writing process aborted."
  fi

  sudo systemctl restart smbd
  sudo systemctl restart nmbd
  sudo systemctl status smbd
else
  echo "User declined"
fi


echo "###############################################################################################"
echo "Cursor AI Initialization"
echo "###############################################################################################"
if [[ ${1,,} == "all" ]] || [[ ${1,,} == "cursorai" ]] || get_user_confirmation; then
  echo "User confirmed"
  sudo apt install libfuse2
else
  echo "User declined"
fi

echo "###############################################################################################"
echo "The end of processing"
echo "###############################################################################################"

