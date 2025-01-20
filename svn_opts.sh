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
	local tmp_location="${1}"
	echo "tmp_location=${tmp_location}"
	cd ${tmp_location}

    # 首先检查SVN状态
    local has_missing_files=$(svn status | grep '^!' | wc -l)
    local has_conflicts=$(svn status | grep '^C' | wc -l)
    local scheduled_but_missing=$(svn status | grep "is scheduled for addition, but is missing" | wc -l)
    
    # 只有在有问题时才执行revert
    if [ $has_missing_files -gt 0 ] || [ $has_conflicts -gt 0 ] || [ $scheduled_but_missing -gt 0 ]; then
        echo "检测到SVN状态异常，执行修复..."
        svn revert --depth infinity .
        svn status | grep '^!' | awk '{print $2}' | xargs -r svn rm --force
    fi

	svn add * --force
	svn diff
	svn commit -m "$(date +%b%d.%Y_%H:%M:%S)" -m "Default Commit Message"
}

func_push_or_pull_entrance(){
	echo "1=${1}"
	echo "2=${2}"
	echo "3=${3}"

	#-----------------------------------------------------
	local tmp_operation=${1,,}
	if [ ${tmp_operation} != "push" ] && [ ${tmp_operation} != "pull" ]; then
		echo "wrong operation: $1"
		echo -e "\tlegal operations: pull"
		echo -e "\tlegal operations: push"
		echo -e "you need to choose from them above...\n"
		return 1
	fi

	#-----------------------------------------------------
	local tmp_choices=${2%/}
	local tmp_dirname=${3%/}
	if [ ${tmp_choices} != "all" ]; then
		# push or pull single
		func_if_subdir_exist "${tmp_choices}"
		local tmp_rtn_value=$?
		if [ ${CURRENT_MODE,,} == "debug" ]; then
			echo "return ${tmp_rtn_value}"
		fi

		if [ ${tmp_rtn_value} -eq 0 ]; then
			if [ ${CURRENT_MODE,,} == "debug" ]; then
				echo "wow true!!!!"
			fi

			if [ ${tmp_operation} == "push" ]; then
				#func_push_single "${SCRIPT_DIR}/${tmp_dirname}"
				func_push_single "${tmp_dirname}/${tmp_choices}"
			else
				#func_pull_single "${SCRIPT_DIR}/${tmp_dirname}"
				func_pull_single "${tmp_dirname}/${tmp_choices}"
			fi
		else
			echo "could not find this dir \"${tmp_dirname}\", Check again..."
			return 1
		fi
	else
		# push or pull all
		for subdir in */; do		 
			if [ ${tmp_operation} == "push" ]; then
				#func_push_single "${SCRIPT_DIR}/${subdir%/}"	
				func_push_single "${tmp_dirname}/${subdir%/}"
				echo
			else
				#func_pull_single "${SCRIPT_DIR}/${subdir%/}"
				func_pull_single "${tmp_dirname}/${subdir%/}"
				echo
			fi
		done

		echo "Done ${tmp_} all dirs"
		return 0
	fi
}

main() {
	func_load_env

	if [ $# -lt 3 ];then
		echo "wrong num of parameters: $#"
		echo "for example:"
		echo "$0 push all /home/david/svn/"
		echo 
		exit 1
	else
		func_echo_all_params $@
	fi

	#-----------------------------------------------
	local tmp_location="$(readlink -f "${3}")"
	func_push_or_pull_entrance ${1} ${2} ${tmp_location}

	if [ $? -ne 0 ]; then
		exit 1
	fi
}

main $@
