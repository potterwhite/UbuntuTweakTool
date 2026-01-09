#!/bin/bash

func_1_load_env(){
	set -e

	if [[ "$#" != "3" ]] && [[ "$#" != "4" ]] ; then
		echo "parameters is illegal, only have $# parameter(s)..."
		func_1_1_help
		exit 1
	fi

	if [ "$#" == "3" ]; then		
		OLD_UUID=""
	else
		OLD_UUID="$1"
		shift
	fi
	OLD_NAME="$1"

	NEW_UUID="$2"
	NEW_NAME="$3"

	TARGET_MD_FOLDER="./Obsidian_Import_Test"
	
	echo "OLD_UUID=${OLD_UUID}"
	echo "OLD_NAME=${OLD_NAME}"
	echo "NEW_UUID=${NEW_UUID}"
	echo "NEW_NAME=${NEW_NAME}"
}

func_1_1_help(){
	echo -e " "
	echo -e "1st parameter: old uuid "
	echo -e "2nd parameter: old task_name "
	echo -e "3rd parameter: new uuid "
	echo -e "4th parameter: new task_name "

	echo -e " "
	echo -e "example:"
	echo -e " \${script_name} \"5938c1bd-8c1f-404b-88fc-aa5735ea4b63\" \"task_关于pkb的理论研究\" \"a01a1a38-586e-4f8d-8f66-b3fbd8bc9eb0\" \"task_harborpilot_早期v1.0.0发布之前的所有工作\""
	echo -e " "
}

func_2_process(){
	#sed -i 's/(task_uuid:: ) (task_name:: 学习, Obsidian与NAS连接)/(task_uuid:: 67108fc8-682b-482c-b336-43f0cdd9a0cf) (task_name:: [[task_解决obsidian无法同步到个人存储空间的问题（使用syncthing解决）]])/g' "${TARGET_MD_FOLDER}/*.md"

#---------------v2	
#	sed -i "s/(task_uuid:: ${OLD_UUID}) (task_name:: ${OLD_NAME})/(task_uuid:: ${NEW_UUID}) (task_name:: [[${NEW_NAME}]])/g" "${TARGET_MD_FOLDER}/*.md"

#---------------v3
grep -l "(task_uuid:: ${OLD_UUID}) (task_name:: ${OLD_NAME})" "${TARGET_MD_FOLDER}"/*.md | while read -r file; do
    echo "正在修改: $file"
#    sed -i 's/(task_uuid:: ) (task_name:: 学习, Obsidian与NAS连接)/(task_uuid:: 67108fc8-682b-482c-b336-43f0cdd9a0cf) (task_name:: [[task_解决obsidian无法同步到个人存储空间的问题（使用syncthing解决）]])/g' "$file"
#    sed -i "s/(task_uuid:: ${OLD_UUID}) (task_name:: ${OLD_NAME})/(task_uuid:: ${NEW_UUID}) (task_name:: [[${NEW_NAME}]])/g" "$file"
    sed -i "s#(task_uuid:: ${OLD_UUID}) (task_name:: ${OLD_NAME})#(task_uuid:: ${NEW_UUID}) (task_name:: [[${NEW_NAME}]])#g" "$file"
done


}

main(){
	func_1_load_env "$@" || exit 1
	func_2_process || exit 1
}

main "$@"
