#!/bin/bash
#Code optimized and tested on RHEL. Minor tweaks are necessary to port it for other flavours of UNIX.
VM_VERSION=`cat /etc/redhat-release | awk '{print$(NF-1)}' 2> /dev/null`
EXEC_PATH="/tmp/AutoRHL"
EXEC_MODE="auto"
LOG_FILE="$EXEC_PATH/AutoRHL.log"
CONFIG_PATH="$EXEC_PATH/etc"
DOWNLOAD_PATH="$EXEC_PATH/downloads"
LOG_TEXT=""
DATE_FORMAT=`date +%Y-%m-%d_%H:%M:%S`
# OS variables
H_NAME=$(/bin/hostname 2> /dev/null)
H_NAME_FQDN=$(/bin/hostname -f 2> /dev/null)
IP_ADDR=$(/bin/hostname -i 2> /dev/null)
# Config File paths
NTP_CONF="/etc/ntp.conf"
SUDO_FILE="/etc/sudoers"
PASS_FILE="/etc/passwd"
RESOLVE_CONF="/etc/resolv.conf"
HOSTS_FILE="/etc/hosts"
# Checking script directories and files
mkdir -p "$EXEC_PATH/etc" > /dev/null 2>&1
mkdir -p "$EXEC_PATH/dump" > /dev/null 2>&1
mkdir -p "$EXEC_PATH/downloads" > /dev/null 2>&1
if [ ! -f $LOG_FILE ]; then
	touch $LOG_FILE
fi
uwait(){
	echo -en '\E[1;30;44;97m'"Press any key to continue !"'\e[0m'
	read temp
}
update_log(){
	# Syntax update_log <color> <text|background> <text> <manual>
	COLOR_FORMAT=""
	COLOR_CODE="9m"
	# Checking 2nd argument
	if [ "$2" == "text" ];then
		# Setting color for text
		COLOR_FORMAT="\e[1;3"
	else
		# Setting color for background
		COLOR_FORMAT="\e[1;4"
	fi
	case $1 in
		"Blue")
			COLOR_CODE="4m";
		;;
		"Green")
			COLOR_CODE="2m";
		;;
		"Yellow")
			COLOR_CODE="3m";
		;;
		"Red")
			COLOR_CODE="1m";
		;;
		"Magenta")
			COLOR_CODE="5m";
		;;
	esac
	# Updating Log
	echo -e "$COLOR_FORMAT$COLOR_CODE"$3'\e[0m' >> $LOG_FILE
	# Interactive mode
	if [ "$EXEC_MODE" == "manual" ];then
		echo -e "$COLOR_FORMAT$COLOR_CODE"$3'\e[0m'
	fi
}
# Initial log entry and checking previous exit
EXIT_STATUS=$(cat $LOG_FILE | tail -1 | grep -c "Script exited")
update_log Blue background "#####################################################################################################"
update_log Blue text "$DATE_FORMAT - New execution of script !"
if [ $EXIT_STATUS -eq 0 ] && [ $(cat $LOG_FILE | wc -l) -gt 2 ];then
	update_log Yellow text "$DATE_FORMAT - The previous execution of the script did not end in a clean exit !"
fi
# Checking if root
if [ $(id | grep -ic root) -eq 0 ];then
	update_log Red text "$DATE_FORMAT - The script should be run as root !"
	update_log Blue text "$DATE_FORMAT - Script exited automatically !"
	exit 1
fi
# Linux handlers
service_handler(){
	# Syntax service_handler <service name> <start|stop|restart|status>
	case $2 in
		"start")
			service $1 start > /dev/null 2>&1
			sleep 3s
			service $1 status > /dev/null 2>&1
		;;
		"stop")
			service $1 stop > /dev/null 2>&1
			sleep 3s
			service $1 status > /dev/null 2>&1
		;;
		"restart")
			service $1 restart > /dev/null 2>&1
			sleep 3s
			service $1 status > /dev/null 2>&1
		;;
		"status")
			service $1 status > /dev/null 2>&1
		;;
	esac
	if [ $? -eq 0 ];then
		return 0
	else
		return 1
	fi
}
do_sudolog(){
	# Enabling sudo log
	if [ $(cat $SUDO_FILE | grep -c "sudo.log") == 0 ];then
		# Taking backup
		/bin/cp $SUDO_FILE "$CONFIG_PATH/$(echo $SUDO_FILE | awk -F'/' '{print($NF)}')_`date +%Y_%m_%d_%H_%M_%S`" > /dev/null 2>&1
		update_log Yellow text "$DATE_FORMAT - Enabling sudo log !"
		echo "#Defaults sudo log" >> $SUDO_FILE
		echo "Defaults   logfile=\"/var/log/sudo.log\"" >> $SUDO_FILE
		update_log Green text "$DATE_FORMAT - Sudo log enabled !"
	else
		update_log Yellow text "$DATE_FORMAT - Sudo log was already enabled !"
	fi
	return 0
}
do_users(){
	# user variables
	USER_LIST="$DOWNLOAD_PATH/userlist.csv"
	# Creating Sudo Group
	groupadd -f sudogroup > /dev/null 2>&1
	if [ $(cat $SUDO_FILE | grep -cw "sudogroup") == 0 ];then
		# Taking backup
		/bin/cp $SUDO_FILE "$CONFIG_PATH/$(echo $SUDO_FILE | awk -F'/' '{print($NF)}')_`date +%Y_%m_%d_%H_%M_%S`" > /dev/null 2>&1
		echo "#Group with sudo access" >> $SUDO_FILE
		echo "%sudogroup        ALL=(ALL)       ALL" >> $SUDO_FILE
		update_log Green text "$DATE_FORMAT - Group named 'sudogroup' has been created with sudo access !"
	else
		update_log Yellow text "$DATE_FORMAT - Sudo group already exists !"
	fi
	# Getting user input file
	if [ $EXEC_MODE == "manual" ];then
		echo -en "\e[1;39mDo you want to use a custom input file ?(y/n): "
		read uinput
		if [ $uinput == "y" ];then
			echo -en "\e[1;39mEnter the file path: "
			read ufile
			USER_LIST=$ufile
		else
			# Downloading user file
			export_proxy
			update_log Yellow text "$DATE_FORMAT - Downloaing user file !"
			(timeout 3m wget --tries=3 -O $USER_LIST "https://raw.githubusercontent.com/leonerdo037/pHAutomation/master/userlist.csv") > /dev/null 2>&1
			if [ $? -eq 0 ];then
				update_log Green text "$DATE_FORMAT - Successfully downloaded user file !"
			else
				update_log Red text "$DATE_FORMAT - Unable to download user list !"
				return 1
			fi
		fi
	else
		# Downloading user file
		export_proxy
		(timeout 3m wget --tries=3 -O $USER_LIST "https://raw.githubusercontent.com/leonerdo037/pHAutomation/master/userlist.csv") > /dev/null 2>&1
		if [ $? -eq 0 ];then
			update_log Green text "$DATE_FORMAT - Successfully downloaded user file !"
		else
			update_log Red text "$DATE_FORMAT - Unable to download user list !"
			return 1
		fi
	fi
	IFS=$'\n'
	# Checking if input file exists
	if [ ! -f $USER_LIST ]; then
		update_log Red text "$DATE_FORMAT - The user input file: '$USER_LIST' was not found !"
		return 1
	fi
	# user creating
	RET_VALUE=0
	for line in $(cat $USER_LIST 2> /dev/null)
	do
		username=$(echo $line | awk -F',' '{print($1)}')
		comment=$(echo $line | awk -F',' '{print($2)}')
		group=$(echo $line | awk -F',' '{print($3)}')
		group2=$(echo $line | awk -F',' '{print($4)}')
		password=$(echo $line | awk -F',' '{print($5)}')
		issudouser=$(echo $line | awk -F',' '{print($6)}')
		#Checking input file syntax
		if [ -z "$username" ] || [ -z "$comment" ] || [ -z "$group" ] || [ -z "$group2" ] || [ -z "$password" ] || [ -z "$issudouser" ];then
			update_log Red text "$DATE_FORMAT - Error in line: $line"
			RET_VALUE=1
			continue
		fi
		# User creation and password setting
		if [ $(cat $PASS_FILE | grep -cw $username 2> /dev/null) == 0 ];then
			useradd -s /bin/bash -c $comment -g $group -G $group2 -d /home/$username $username > /dev/null 2>&1
			if [ $? -eq 0 ];then
				echo $password | passwd $username --stdin > /dev/null 2>&1
				update_log Green text "$DATE_FORMAT - User '$username' created !"
			else
				update_log Red text "$DATE_FORMAT - Unable to create the user: '$username' !"
				RET_VALUE=1
			fi
		else
			update_log Yellow text "$DATE_FORMAT - User '$username' already exists !"
		fi
		# Setting sudo access if needed
		if [ "$issudouser" == "y" ];then
			usermod -aG sudogroup $username > /dev/null 2>&1
			update_log Green text "$DATE_FORMAT - User '$username' was granted sudo access !"
		fi
	done
	IFS=$' '
	return $RET_VALUE
}
do_swap(){
	SERVER_TYPE=$(hostname -i | awk -F'.' '{print($3)}' 2> /dev/null)
	TOTAL_MEM=$(free -m | grep -i mem | awk '{print($2)}' 2> /dev/null)
	SWAP_MEM=$(free -m | grep -i swap | awk '{print($2)}' 2> /dev/null)
	# WaAgent file variables
	SWAP_ENABLED=$(cat $WAGENT_FILE | grep -v '^#' | grep -i EnableSwap | awk -F'=' '{print($2)}' 2> /dev/null)
	SWAP_MOUNT=$(cat $WAGENT_FILE | grep -v '^#' | grep -i MountPoint | awk -F'=' '{print($2)}' 2> /dev/null)
	SWAP_SIZE=$(cat $WAGENT_FILE | grep -v '^#' | grep -i SwapSizeMB | awk -F'=' '{print($2)}' 2> /dev/null)
	SWAP_LINE=$(cat $WAGENT_FILE | grep -v '^#' | grep -in SwapSizeMB | awk -F':' '{print($1)}' 2> /dev/null)
	# Calculating required memory
	case $SERVER_TYPE in
		103)
			REQ_MEM=$(bc -l <<< $TOTAL_MEM*1.5 | awk -F'.' '{print($1)}' 2> /dev/null)
		;;
		*)
			REQ_MEM=$(bc -l <<< $TOTAL_MEM*0.5 | awk -F'.' '{print($1)}' 2> /dev/null)
		;;
	esac
	# Validating the configuration
	if [ $(bc -l <<< $SWAP_MEM-100) -lt $REQ_MEM ] && [ $(bc -l <<< $SWAP_MEM+100) -gt $REQ_MEM ];then
		update_log Yellow text "$DATE_FORMAT - Swap is already configured as expected !"
		return 0
	fi
	# Taking backup
	/bin/cp $WAGENT_FILE "$CONFIG_PATH/$(echo $WAGENT_FILE | awk -F'/' '{print($NF)}')_`date +%Y_%m_%d_%H_%M_%S`" > /dev/null 2>&1
	# Checking if swap is enabled
	# Checking if variable is empty
	if [ -z "$SWAP_ENABLED" ];then
		SWAP_ENABLED="n"
	fi
	if [ $SWAP_ENABLED == 'n' ];then
		sed -i "s/ResourceDisk.EnableSwap=n/ResourceDisk.EnableSwap=y/g" $WAGENT_FILE 2> /dev/null
		service_handler waagent restart
		update_log Green text "$DATE_FORMAT - Swap enabled in the waagent configuration file !"
	fi
	# Checking if variable is empty
	if [ -z "$WAP_MOUNT" ];then
		SWAP_MOUNT="/mnt/"
	fi
	# Checking if mount point available
	if [ $SWAP_MOUNT != "/mnt/resource" ];then
		sed -i "s@ResourceDisk.MountPoint=$SWAP_MOUNT@ResourceDisk.MountPoint=/mnt/resource@g" $WAGENT_FILE  2> /dev/null
		service_handler waagent restart
		update_log Green text "$DATE_FORMAT - Mount Point Updated in the waagent configuration file !"
	fi	
	if [ "$SWAP_MEM" -lt "$REQ_MEM" ];then
		sed -i "s/ResourceDisk.SwapSizeMB=$SWAP_SIZE/ResourceDisk.SwapSizeMB=$REQ_MEM/g" $WAGENT_FILE 2> /dev/null
		#sed -i "s/ResourceDisk.SwapSizeMB=$SWAP_SIZE/ResourceDisk.SwapSizeMB=1024/g" $WAGENT_FILE 2> /dev/null
		service_handler waagent restart
		update_log Green text "$DATE_FORMAT - Swap changed from '$SWAP_MEM' to '$REQ_MEM' in the waagent configuration file !"
	fi
	# Validating the configuration
	SWAP_MEM_UPDATED=$(free -m | grep -i swap | awk '{print($2)}' 2> /dev/null)
	if [ $(bc -l <<< $SWAP_MEM_UPDATED-100) -lt $REQ_MEM ] && [ $(bc -l <<< $SWAP_MEM_UPDATED+100) -gt $REQ_MEM ];then
		update_log Green text "$DATE_FORMAT - Swap changes are reflected in the machine !"
		return 0
	else
		update_log Red text "$DATE_FORMAT - Swap changes are not reflected in the machine !"
		return 1
	fi
}
do_rootpass(){
	update_log Yellow text "$DATE_FORMAT - Attempting to change root password !"
	echo "5aG5WXb4*c" | passwd root --stdin > /dev/null 2>&1
	if [ $? -eq 0 ];then
		update_log Green text "$DATE_FORMAT - Root password changed successfully !"
	else
		update_log Red text "$DATE_FORMAT - Unable to change root password !"
		return 1
	fi
	return 0
}
auto_handler(){
	# Checking if execution mode is manual
	if [ "$EXEC_MODE" == "manual" ];then
		clear
	fi
	# Calling function
	update_log Magenta background "$2"
	TEMP_VAR=""
	for (( i=1;i<$(echo $2 | wc -c);i++))
	do
		TEMP_VAR+="-"
	done
	update_log Magenta text $TEMP_VAR
	$1
	if [ $? -eq 0 ];then
		update_log Green background "$DATE_FORMAT - $2 completed successfully !"
	else
		update_log Red background "$DATE_FORMAT - $2 completed with errors !"
	fi
	# Checking if execution mode is manual
	if [ "$EXEC_MODE" == "manual" ];then
		uwait
	fi
}
auto(){
	auto_handler "do_validation" "Download and run validation script"
	auto_handler "do_wagent" "WA Agent Validation"
	auto_handler "do_zone" "Setting TimeZone"
	auto_handler "do_ntp" "Configuring NTP service"
	auto_handler "do_swap" "Configuring SWAP"
	auto_handler "do_pass" "Configuring Password Policy"
	auto_handler "do_sudolog" "Enabling Sudo Log"
	auto_handler "do_users" "Creating Users"
	auto_handler "do_rootpass" "Changing root Password"
	auto_handler "do_domain" "Adding Server to Domain"
	update_log Blue text "$DATE_FORMAT - Script exited automatically !"
	exit 0
}
logo()
{
clear
	echo -e "\e[0;1m **************************************************************************************\e[0m"
	echo -e "\e[1;34m ___    _____  ___   _____              ___    _   _  _  _      ___    ___    ___   "
	echo -e "\e[1;34m(  _ \ (  _  )(  _ \(_   _)            (  _ \ ( ) ( )(_)( )    (  _ \ (  _ \ |  _ \ "
	echo -e "\e[1;34m| |_) )| ( ) || (_(_) | |     ______   | (_) )| | | || || |    | | ) || (_(_)| (_) )"
	echo -e "\e[1;34m| ,__/'| | | | \__ \  | |    (______)  |  _ <'| | | || || |  _ | | | )|  _)_ | ,  / "
	echo -e "\e[1;34m| |    | (_) |( )_) | | |              | (_) )| (_) || || |_( )| |_) || (_( )| |\ \ "
	echo -e "\e[1;34m(_)    (_____) \____) (_)              (____/ (_____)(_)(____/ (____/ (____/ (_) (_) \e[0m\n"
	echo -e "\e[1m **************************************************************************************\e[0m"
	echo -e "\e[1m Version 0.37 (BETA) \e[0m\n\n"
}
menu()
{
	logo # Calling Function
	echo -en '\E[1;30;44;97m' "MENU - (Navigate Using The Below Options)" '\e[0m\n\n'
	echo -en '\E[1;35m' "1.  VM INFORMATION" '\e[0m\n'
	echo -en '\E[1;35m' "2.  VALIDATE WA AGENT" '\e[0m\n'
	echo -en '\E[1;35m' "3.  SET TIMEZONE TO BST" '\e[0m\n'
	echo -en '\E[1;35m' "4.  CONFIGURE NTP SERVICE" '\e[0m\n'
	echo -en '\E[1;35m' "5.  CONFIGURE SWAP" '\e[0m\n'
	echo -en '\E[1;35m' "6.  SET PASSWORD POLICY(INPUT FILES NEEDED)" '\e[0m\n'
	echo -en '\E[1;35m' "7.  ENABLE SUDO LOG" '\e[0m\n'
	echo -en '\E[1;35m' "8.  CREATE USERS(INPUT FILES NEEDED)" '\e[0m\n'
	echo -en '\E[1;35m' "9.  CHANGE ROOT PASSWORD" '\e[0m\n'
	echo -en '\E[1;35m' "10. ADD SERVER TO DOMAIN" '\e[0m\n'
	echo -en '\E[1;35m' "11. DOWNLOAD & RUN VALIDATION SCRIPT" '\e[0m\n'
	echo -en '\E[1;31m' "0.  EXIT" '\e[0m\n\n'
	echo -en '\E[1;30;44;97m' Enter your Choice: '\e[0m'
	read menuChoice;
	case $menuChoice in
		0)
			clear
			update_log Blue text "$DATE_FORMAT - Script exited manually !"
			exit 0
		;;
		1)
			# Information
			logo
			echo -en '\E[1;30;44;97m' "MENU -> VM INFORMATION" '\e[0m\n\n'
			echo -en '\e[1;39m' "---------------------------------------\n"
			echo -en '\e[1;39m' "Hostname:        "$H_NAME_FQDN '\n'
			echo -en '\e[1;39m' "IP Address:      "$IP_ADDR '\n'
			echo -en '\E[1;39m' "RedHat Version:  "$VM_VERSION '\e[0m\n'
			echo -en '\E[1;39m' "WAagent Version: "$(waagent --version | head -1 | awk '{print($1)}'  2> /dev/null) '\e[0m\n'
			echo -en '\e[1;39m' "Uptime:          "$(/usr/bin/uptime | awk '{print($3,$4)}' 2> /dev/null) '\n'
			echo -en '\e[1;39m' "Last Reboot:     "$(/usr/bin/last reboot | head -1 | awk '{print($5,$6,$7,$8)}' 2> /dev/null) '\n'
			echo -en '\e[1;39m' "---------------------------------------\n\n"'\e[0m'
			uwait
			menu
		;;
		2)
			# WA AGENT
			auto_handler "do_wagent" "WA Agent Validation(Manual)"
			menu
		;;
		3)
			# TIMEZONE
			auto_handler "do_zone" "Setting TimeZone(Manual)"
			menu
		;;
		4)
			# NTP
			auto_handler "do_ntp" "Configuring NTP service(Manual)"
			menu
		;;
		5)
			# Swap
			auto_handler "do_swap" "Configuring SWAP(Manual)"
			menu
		;;
		6)
			# Password policy
			auto_handler "do_pass" "Configuring Password Policy(Manual)"
			menu
		;;
		7)
			# sudo log
			auto_handler "do_sudolog" "Enabling sudo log(Manual)"
			menu
		;;
		8)
			# User creation
			auto_handler "do_users" "Creating Users(Manual)"
			menu
		;;
		9)
			# Changing root password
			auto_handler "do_rootpass" "Changing root password(Manual)"
			menu
		;;
		10)
			# Adding server to Domain
			auto_handler "do_domain" "Adding Server to Domain(Manual)"
			menu
		;;
		11)
			# Validation script
			auto_handler "do_validation" "Download and run validation script(Manual)"
			menu
		;;
		*)
			menu
	esac
}
# Main
if [ "$1" = "auto" ]; then
	EXEC_MODE="auto"
	auto
elif [ "$1" = "manual" ]; then
	EXEC_MODE="manual"
	menu
elif [ "$#" == 0 ];then
	update_log Red text "$DATE_FORMAT - Script was called with 0 arguments. Execution failed !"
	exit 1
else
	update_log Red text "$DATE_FORMAT - The first argument should contain 'auto' or 'manual'. The value given was '$1'"
	exit 1
fi
