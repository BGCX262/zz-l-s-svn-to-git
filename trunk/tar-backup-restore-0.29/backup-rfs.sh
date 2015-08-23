#!/bin/bash
# /usr/mycode/backup-rfs
# Ref : http://ubuntuforums.org/showthread.php?t=35087
# Array Ref : http://www.linuxtopia.org/online_books/advanced_bash_scripting_guide/arrays.html
# Script Ref : http://www.comptechdoc.org/os/linux/programming/script/linux_pgscriptvariables.html
#
# Version 0.2 - added backup of MBR
#
# To be restored by : restore-rfs
#
#
VERSION=0.28
TEST=0		# for Debug only, $TEST=1 means testing only, no actualy backup

# CentOS : sestatus
#SELinux status:                 enabled
#SELinuxfs mount:                /selinux
#Current mode:                   permissive
#Mode from config file:          disabled
#Policy version:                 21
#Policy from config file:        targeted

## User Options
# -------------------------------------------------------------------------------------------------------------
BACKUP_FILE=/rfs_backup/backup.tgz			# root_fs backup file
EXCLUDES=(/var/lib/mysql/ib_logfile* /var/lib/mysql/ibdata* /home)

# After restore :
# For Debian rebuild mysql db : /usr/bin/mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql 
#
# -------------------------------------------------------------------------------------------------------------

# Array storing the running process
declare -a RUNNING	


#----------------------------------- Functions --------------------------------------------
##
echoc(){
	echo -n -e $1
	if [ $# -lt 3 ]; then
		echo "$2"
	else
		echo "$2" "$3"
	fi
	echo -n -e '\E[37;40m'
}

# Ask to proceed or exit
inquire(){
	local reply skip=$1;
    if [ -z $skip ]; then skip="y"; fi

	PROCEED="exit";
    if [ $skip = "n" ]; then
		echo -n "   Shall we do it? (yes, quit) [y]/q: "
	else 
		echo -n "   Shall we do it? (yes, skip, quit) [y]/s/q: "
	fi 
    read reply
    if [ -z $reply ]; then reply="y"; fi
    if [ $reply = "y" ]; then
		PROCEED=y
    fi
    if [ $skip = "y" ]; then
	    if [ $reply = "s" ]; then
			PROCEED=n
	    fi
	fi 
    if [ $PROCEED = "exit" ]; then
		echo
		echo "   User exit."
		exit 0
    fi
}


check_root(){
	# check if the script is run by root, the backup process should be run by root
	echo -n "1. Checking if you are root ... "
	if [[ $UID -ne 0 ]]; then
		echo "$0 must be run as root, now exit."
		exit 1
	else
		echo "yes"
	fi
}



check_old(){
	# Check if old backup file exist or not
	echo 
	echo -n "2. Checking if $BACKUP_FILE exist ... "
	if [ -f $BACKUP_FILE ]; then
		echo "yes"
		echo "   This script will remove your old backup file ... "
		inquire "n"
	else
		echo "no"
	fi
}


stop_process(){
	## Process to be check
	#  procname - `ps aux` listed process name
	#  start_st - /etc/init.d/xxx file name, which we can used to start/stop the process 
	local ptr pid size process
	local procname start_st

	procname=(lighttpd amuled transmission-daemon cron pure-ftpd smbd exim4 webmin rsyslogd)
	start_st=(lighttpd amule-daemon transmission-daemon cron pure-ftpd samba exim4 webmin rsyslogd)

	# Check for running process and suggest to stop them
	ptr=0
	for process in ${procname[@]}
	do
		pid=`ps aux | grep "$process" | grep -v grep`
		if ! test -z "$pid"; then
			size=${#RUNNING[*]}
			RUNNING[$size]=${start_st[$ptr]} 
		fi
		ptr=$((ptr+1))
	done
	echo 
	echo "3. These processes are running, which are suggested to stop before running backup :"
	echo "   ${RUNNING[*]}"
	echo

	# Help to stop process
	size=${#RUNNING[*]}
	if [ $size -gt 0 ]; then
		echo "   This script can stop the processes for you ... "
		inquire
		echo 
		if [ $PROCEED = "y" ]; then
			for process in ${RUNNING[@]}
			do
				echo -n "   Trying to stop $process ... "
				if [ $TEST -eq 0 ]; then
					/etc/init.d/$process stop > /dev/null 2>&1
				fi 
				echo "ok."
			done

			echo
			echo "   This script can restart the processes after the backup ... "
			inquire
			RESTART=${PROCEED}
		fi
	fi 
}


backup(){
	###
	# Actually run backup now 
	local additional=''
	local add
	for add in ${EXCLUDES[@]}
	do
		additional="$additional --exclude=$add"
	done
	
	echo 
	echo "4. We are above to start the Tar Backup process by the command : "
	echo "      tar cvpzf $BACKUP_FILE --exclude=/proc --exclude=/lost+found \\"
	echo "                             --exclude=/etc/udev/rules.d/*-net.rules \\"
	echo "                             --exclude=$BACKUP_FILE --exclude=/mnt --exclude=/sys \\"
	if [ ! -z "$additional" ]; then 
		echo "                            $additional \\"
	fi 
	echo "                             --exclude=$BACKUP_PATH /"
	echo
	inquire
	echo 
	if [ $PROCEED = "y" ]; then
		if [ $TEST -eq 0 ]; then
			# backup the MBR
			bu_mbr
			if [ -f $BACKUP_FILE ]; then
				rm $BACKUP_FILE 
				echo "   $BACKUP_FILE removed."
			fi 
			cd /
			tar cvpzf $BACKUP_FILE --exclude=/proc --exclude=/lost+found \
				--exclude=/etc/udev/rules.d/*-net.rules \
				--exclude=$BACKUP_FILE --exclude=/mnt --exclude=/sys \
				$additional --exclude=$BACKUP_PATH /		
		fi 
		# Restore command : tar xvpfz $BACKUP_PATH/backup.tgz -C /
		#  then, if necessary :
		#  	mkdir proc
		#	mkdir lost+found
		#	mkdir mnt
		#	mkdir sys
		#	etc...


		# Also backup the directory tree structure of $BACKUP_PATH
		# Restore command : tar xvpfz $BACKUP_PATH/backup_dir.tgz -C /
		if [ $TEST -eq 0 ]; then
			tar cvpfz /tmp/backup_dir.tgz --no-recursion --files-from <( find $BACKUP_PATH -type d)
			cp /tmp/backup_dir.tgz $BACKUP_PATH/backup_dir.tgz
			rm /tmp/backup_dir.tgz
			for add in ${EXCLUDES[@]}
			do
				if [ -d "$add" ]; then 
					tar cvpfz /tmp/$add.tgz --no-recursion --files-from <( find $add -type d)
					cp /tmp/$add.tgz $BACKUP_PATH/$add.tgz
					rm /tmp/$add.tgz
				fi
			done
		fi 

		echo
		echo "Backup completed, files :"
		ls -l $BACKUP_PATH/*.tgz
	fi
}



restart_process(){
	# Restart the stopped processes if necessary
	local process
	if [ $RESTART = "y" ]; then
		echo
		echo "5. Restart the stopped processes ... "
		echo 
		for process in ${RUNNING[@]}
		do
			echo -n "   Trying to restart $process ... "
			if [ $TEST -eq 0 ]; then
				/etc/init.d/$process restart > /dev/null 2>&1
			fi 
			echo "ok."
		done
	fi 
}


bu_mbr(){
	local drv
	mkdir -p "$MBR_PATH/mbr"
	drv=`mount | grep ' / ' | cut -b 1-8`
	dd if=$drv of=$MBR_PATH/backup.mbr bs=512 count=1 > /dev/null 2>&1 
	echo "backup-rfs Version:$VERSION" > $MBR_PATH/version.txt
}


# ----------------------------------End of functions -----------------------------------------


clear
echo "#########################################################################################################"
echo "# Tar backup root filesystem script                                                                     #"
echo "#  Version $VERSION                                                                                         #"
echo "#########################################################################################################"


BACKUP_PATH=`dirname $BACKUP_FILE`

# This path should be fixed, otherwise the restore-rfs script cannot find it
MBR_PATH=/tmp/mbr_backup		# If you change this path, you have to change the path in the script restore-rfs also.
RESTART=n					# restart stopped process after backup ?


# Colour for echoc()
black='\E[30;40m'
red='\E[31;40m'
yellow='\E[33;40m'
blue='\E[34;40m'
magenta='\E[35;40m'
cyan='\E[36;40m'
white='\E[37;40m'

echoc $red "         This script is a FREEWARE comes with ABSOLUTELY NO WARRANTY, USE AT YOUR OWN RISK"
echo


mkdir -p "$BACKUP_PATH"

check_root
check_old
stop_process
backup
restart_process

exit 0
