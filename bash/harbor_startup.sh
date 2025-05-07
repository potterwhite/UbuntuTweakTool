#!/bin/bash

# Harbor startup script

# Function to print colored messages
1_0_print_msg() {
    echo -e "${2:-$GREEN}$1${NC}"
}

1_1_load_env(){
	# Set Harbor directory path
	#HARBOR_PATH="/development/hdd1_4tb/harbor/harbor"
	#HARBOR_PATH="/development/b-harbor/harbor2025/harbor"
	HARBOR_PATH="/development/b-harbor/harbor-v2/harbor"

	# Color definitions
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'	
	NC='\033[0m'

	# Check if running as root
	if [ "$EUID" -ne 0 ]; then
	    1_0_print_msg "Please run as root" "${RED}"
	    exit 1
	fi

	# Check Harbor directory exists
	if [ ! -d "$HARBOR_PATH" ]; then
	    1_0_print_msg "Harbor directory not found: $HARBOR_PATH" "${RED}"
	    exit 1
	fi
}

1_2_helper_print(){
    local script_name
    script_name=$(basename "$0") # Gets the actual script name
    1_0_print_msg "Usage: ${script_name} [start|stop|restart]" "${YELLOW}"
    echo
    echo "Manages the Harbor service."
    echo "  start    - Starts the Harbor service."
    echo "  stop     - Stops the Harbor service."
    echo "  restart  - Restarts (stops and then starts) the Harbor service."
    echo
}

2_1_stop_harbor(){
	1_0_print_msg "Stopping Harbor..."
	docker compose down --remove-orphans
	1_0_print_msg "Harbor stopped."
}

2_2_start_harbor(){
	1_0_print_msg "Starting Harbor..."
	docker compose up -d
	# Check startup status
	sleep 10 # Give Harbor a moment to initialize
	# Be more specific with the grep if possible, e.g., using a known container name from your compose file
	#if docker ps --filter "status=running" | grep -q "harbor-nginx"; then # Adjusted grep target
	if docker ps --filter "status=running" | grep -q "goharbor/nginx-photon"; then # Adjusted grep target
		1_0_print_msg "Harbor started successfully!"
	else
		1_0_print_msg "Harbor may have failed to start. Check 'docker compose logs'." "${RED}"
		# Consider exiting with an error if start fails for start/restart actions
	        # exit 1
	fi
}

main(){
	1_1_load_env

	# Change to Harbor directory
	cd "$HARBOR_PATH" || { 1_0_print_msg "Error: Failed to change to Harbor directory: $HARBOR_PATH" "${RED}"; exit 1; }

	if [ "$#" -ne 1 ]; then
		1_2_helper_print
		exit 1
	fi

	ACTION="$1"

	case "$ACTION" in
		start)
			2_2_start_harbor
			;;
		stop)
			2_1_stop_harbor
			;;
		restart)
			2_1_stop_harbor
			# sleep 2 # Optional: a short pause between stop and start
			2_2_start_harbor
			;;
		*)
			1_0_print_msg "Error: Invalid command '$ACTION'." "${RED}"
			1_2_helper_print
			exit 1
			;;
	esac

}


main "$@"
