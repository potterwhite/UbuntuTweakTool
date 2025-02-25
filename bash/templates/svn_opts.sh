#!/bin/bash

func_load_env(){
	SCRIPT_PATH="$(readlink -f ${BASH_SOURCE[0]})"
	SCRIPT_DIR="$(dirname ${SCRIPT_PATH})"

	#echo "1=${SCRIPT_PATH}"
	#echo "2=${SCRIPT_DIR}"

	if [ "${V}" == "1" ]; then
		CURRENT_MODE="Debug"
	else
		CURRENT_MODE="Release"
	fi
}

func_echo_all_params(){
	if [ ${CURRENT_MODE,,} == "debug" ]; then
		echo "we have $# parameters:"
		local tmp_i=1
		for para in "$@";do
			echo "$tmp_i="$para""
			let tmp_i++
		done
	fi
}

func_if_subdir_exist(){
	if [ $1 == "" ]; then
		echo "empty string, pls give me a string of dir name"
		return 1
	fi

	local tmp_target="${1%/}"
	local tmp_i=1

	#---------------------------------------------------------------
	# 2nd stage: retrieve all dir names
	for subdir in */; do
		subdir=${subdir%/}
		
		echo "Round ${tmp_i}"
		let tmp_i++
		echo -e "\tsubdir=${subdir}"
		echo -e "\ttmp_target=${tmp_target}"

		if [ ${tmp_target,,} == "all" ];then
			return 0
		fi

		if [ -d ${subdir} ] && [ ${subdir} == ${tmp_target} ]; then
			echo "yes we found ${1}"
			return 0
		fi
	done
	return 1
}

#---------------------------------------------------------------
# 3rd stage: exec svn pull|push in each subdir

func_pull_single(){
	echo "single_pull: 1=$1"
	
	cd $1
	svn update
}

func_push_single(){
	echo "2"
}

func_push_or_pull_entrance(){
	local tmp_operation=${1,,}
	if [ ${tmp_operation} != "push" ] && [ ${tmp_operation} != "pull" ]; then
		echo "wrong operation: $1"
		echo -e "\tlegal operations: pull"
		echo -e "\tlegal operations: push"
		echo -e "you need to choose from them above...\n"
		return 1
	fi

	#-----------------------------------------------------
	local tmp_dirname=${2%/}
	if [ ${tmp_dirname} != "all" ]; then
		# push or pull single
		func_if_subdir_exist "${tmp_dirname}"
		local tmp_rtn_value=$?
		if [ ${CURRENT_MODE,,} == "debug" ]; then
			echo "return ${tmp_rtn_value}"
		fi

		if [ ${tmp_rtn_value} -eq 0 ]; then
			if [ ${CURRENT_MODE,,} == "debug" ]; then
				echo "wow true!!!!"
			fi

			if [ ${tmp_operation} == "push" ]; then
				func_push_single "${SCRIPT_DIR}/${tmp_dirname}"
			else
				func_pull_single "${SCRIPT_DIR}/${tmp_dirname}"
			fi
		else
			echo "could not find this dir \"${tmp_dirname}\", Check again..."
			return 1
		fi
	else
		# push or pull all
		for subdir in */; do		 
			if [ ${tmp_operation} == "push" ]; then
				func_push_single "${SCRIPT_DIR}/${subdir%/}"	
				echo
			else
				func_pull_single "${SCRIPT_DIR}/${subdir%/}"
				echo
			fi
		done

		echo "Done ${tmp_} all dirs"
		return 0
	fi
}

main() {
	func_load_env

	if [ $# -lt 2 ];then
		echo "wrong num of parameters: $#"
		exit 1
	else
		func_echo_all_params $@
	fi

	#-----------------------------------------------
	func_push_or_pull_entrance ${1} ${2}
	if [ $? -ne 0 ]; then
		exit 1
	fi
}

main $@
