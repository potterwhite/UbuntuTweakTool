#! /bin/bash

func_setup_env(){
	CURSOR_APPIMAGE_PATH="/opt/apps/develop_ide_cursor_ai/cursor-0.40.0-build-24082202sreugb2-x86_64.AppImage"
	CURSOR_DIR="$(dirname ${CURSOR_APPIMAGE_PATH})"
	CURSOR_TARBALL_PATH="${CURSOR_DIR}/cursor-0.40.0.tar.xz"
}

func_check_exist(){
	if [ -f ${CURSOR_APPIMAGE_PATH} ]; then
		ls -lha ${CURSOR_APPIMAGE_PATH}
		echo
		echo "exist, return 0"
		return 0
	else
		ls -lha ${CURSOR_APPIMAGE_PATH}
		echo
		echo "not exist, return 1"
		return 1
	fi
}

func_rebuild_cursor(){
	cd ${CURSOR_DIR}
	echo "start rebuild"
	tar axvf ${CURSOR_TARBALL_PATH}
	echo "you can press Alt+F2 then type in \"r\" and finally press enter to make it take effect."
	echo
}

main(){
	func_setup_env

	echo -e "\n##########################"
	echo -e "Start Fixing"

	func_check_exist

	local tmp_bool=$?
	if [ ${tmp_bool} -ne 0 ]; then
		# means does not exist
		func_rebuild_cursor
		func_check_exist
	else
		# means already exist
		echo -e "${CURSOR_APPIMAGE_PATH} exist, doing nothing!"
	fi

	echo -e "Completed!"
	echo -e "##########################\n"
}

main "$@"
