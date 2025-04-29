#!/bin/bash


main(){
        if [ "$#" != 1 ];then
                echo "wrong argc $#"
                return
        fi

	SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
	echo "${SCRIPT_PATH}"
	
	SCRIPT_DIR="$(dirname ${SCRIPT_PATH})"
	echo "${SCRIPT_DIR}"

	PWD_DIR="$(pwd -P)"
	echo "${PWD_DIR}"

        aria2c --max-concurrent-downloads=16 --split=16 --min-split-size=1M --max-connection-per-server=16 --continue=true "$1"

}

main "$@"

