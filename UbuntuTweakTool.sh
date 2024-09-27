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


echo "###############################################################################################"
echo "Require Administrator\`s Privillege"
echo "###############################################################################################"
sudo -v

echo "###############################################################################################"
echo "Replace APT source to china region"
echo "###############################################################################################"
/opt/shell-scripts/batch_backup_system_origin_configs.sh
if [[ ! -f /etc/apt/sources.list.bak ]];then
	sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
fi
sudo bash -c "cat << EOF > /etc/apt/sources.list && apt update 
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
EOF"
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y minicom nfs-kernel-server lm-sensors vlc screenfetch python3-pip openssh-server \
			nmap fcitx5 curl gnome-tweaks dconf-editor locate net-tools samba smbclient cifs-utils pigz git vim
						

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
  sudo pro attach C12YhjAox3RvhjHUuWdmNXBQzNtAxb
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

	if ! sudo grep -q "UUID=iac6976e1-0d3c-4ac7-b738-ea3685e5f985" /etc/fstab; then
		echo -e "\tthe file is clean, writing process started"
		
		FSTAB_CONTENT='
										#localhost:/home/vmgithub/Development                         /mnt/baytto_tencent_cloud_ssh          nfs     port=3049,noatime,nofail,_netdev            0      0 
										#kingston 256G /dev/nvme1n1p1 
										UUID=iac6976e1-0d3c-4ac7-b738-ea3685e5f985        /mnt/256gb_kingston_nvmessd            ext4    defaults,noatime,nofail            0       2 
										# /mnt/Apps_D was on /dev/sda1 during installation
										UUID=3E8241198240D755                            /mnt/2tb_wd_purpleSurveillance_hdd     ntfs    defaults,noatime,nofail            0       2
										UUID=BAA076B4A076772B                            /mnt/2tb_wd_passport_hdd               ntfs    defaults,noatime,nofail            0       2'
		
		sudo bash -c "echo -e '${FSTAB_CONTENT}' | sed 's/^\t*//' >> /etc/fstab"
	else
		echo -e "\tthe file is corrupted, writing process aborted."
	fi

else
  echo "User declined"
fi

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
											# Date: Nov29.2023
											# Author: MrJamesLZA
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



echo "###############################################################################################"
echo "Samba Setup"
echo "###############################################################################################"
if [[ ${1,,} == "all" ]] || get_user_confirmation; then
  echo "User confirmed"
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
	sudo mkdir -p /mnt/sambashare_main_entry/sambashare
	sudo chmod 2775 /mnt/sambashare_main_entry/sambashare
	sudo chown sambashare: /mnt/sambashare_main_entry/sambashare
	sudo smbpasswd -a sambashare
	sudo smbpasswd -e sambashare
	
	sudo groupadd sambaadmin
	sudo useradd -M -d /mnt/sambashare_main_entry/sambaadmin -s /usr/sbin/nologin -g sambaadmin sambaadmin
	sudo usermod -aG sambaadmin james
	sudo smbpasswd -a sambaadmin
	sudo mkdir -p /mnt/sambashare_main_entry/sambaadmin
	sudo chown sambaadmin:sambaadmin /mnt/sambashare_main_entry/sambaadmin
	sudo chmod 2770 /mnt/sambashare_main_entry/sambaadmin
		
	SMB_CONTENT='[samba priviledge] 
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
	
	if ! sudo grep -q "[samba priviledge]" /etc/fstab; then
		echo -e "\tthe file is clean, writing process started"
		sudo bash -c "echo -e '${SMB_CONTENT}' >> /etc/samba/smb.conf"
	else
		echo -e "\tthe file is corrupted, writing process aborted."
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

