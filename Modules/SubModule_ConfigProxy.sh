


echo "###############################################################################################"
echo "Set File Use Proxy"
echo "###############################################################################################"

# Define a function to handle the wgetrc file
process_file() {
  local file_path=$1
  local target_string=$2
  local BOOL_SET_STRING=A_CASE

  if [[ ! -f $file_path ]]; then
    echo "File not exists at $file_path"
    BOOL_SET_STRING=B_CASE
  else
    echo "File already exists at $file_path"
    if ! sudo grep -q "$target_string" $file_path; then
      echo "File already exists but no $target_string at $file_path"
      BOOL_SET_STRING=B_CASE
    else
      echo "File already has $target_string at $file_path"
      if ! sudo grep -q "$target_string = on" $file_path; then
        echo "File already has $target_string but not on at $file_path"
        BOOL_SET_STRING=C_CASE
      fi
    fi
  fi

  if [[ ${BOOL_SET_STRING} == B_CASE ]]; then
    sudo bash -c "echo '$target_string = on' >> $file_path"
    echo "File option $target_string been set to on at $file_path"
  elif [[ ${BOOL_SET_STRING} == C_CASE ]]; then
    sudo sed -i "s/$target_string*/$target_string = on/" $file_path
    echo "File option $target_string been replaced to on at $file_path"
  fi
}


# List of files and target strings to process
files_to_process=(
  "/usr/local/etc/wgetrc use_proxy = on"
  "/home/james/.gitconfig [http]
    proxy = http://127.0.0.1:7890"
  "/root/.curlrc proxy="http://127.0.0.1:7890""
  "/etc/apt/apt.conf.d/01proxy 	Acquire::http::Proxy "http://127.0.0.1:7890/";
	Acquire::https::Proxy "http://127.0.0.1:7890/";
"
)

SubModule_ConfigProxy() {
  # Process each file
  for file_and_string in "${files_to_process[@]}"; do
    process_file $file_and_string
  done
}

# BOOL_SET_WGETRC=A_CASE

# if [[ ! -f /usr/local/etc/wgetrc ]]; then
# 	echo "Wgetrc not exists"
# 	BOOL_SET_WGETRC=B_CASE
# else
# 	echo "Wgetrc already exists"
# 	if ! sudo grep -q "use_proxy" /usr/local/etc/wgetrc; then
# 		echo "Wgetrc already exists but no use_proxy"

# 		BOOL_SET_WGETRC=B_CASE
# 	else
# 		echo "Wgetrc already has use_proxy"
# 		if ! sudo grep -q "use_proxy = on" /usr/local/etc/wgetrc; then
# 			echo "Wgetrc already has use_proxy but not on"

# 			BOOL_SET_WGETRC=C_CASE
# 		fi
# 	fi
# fi

# if [[ ${BOOL_SET_WGETRC} == B_CASE ]]; then
# 	sudo bash -c "echo 'use_proxy = on' >> /usr/local/etc/wgetrc"
# 	echo "Wgetrc option use_proxy been set to on"
# elif [[ ${BOOL_SET_WGETRC} == C_CASE ]]; then
# 	sudo sed -i 's/use_proxy*/use_proxy = on/' /usr/local/etc/wgetrc
# 	echo "Wgetrc option use_proxy been replaced to on"
# fi
