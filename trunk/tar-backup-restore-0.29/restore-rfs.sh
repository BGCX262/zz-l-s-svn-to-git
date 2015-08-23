#!/bin/bash
# /usr/mycode/restore-rfs
#
# **********************************************************************************************
#          This script comes with ABSOLUTELY NO WARRANTY, USE AT YOUR OWN RISK
# **********************************************************************************************
#
# Script to restore root partition that was backup by tar
# Backup by : backup-rfs (tar Linux system + MBR backup)
#
VERSION='0.29'
#
#
# Requirements :
# 1. a host system running Debian or Ubuntu (other distros may run correctly, but not tested)
# 2. A Target drive with or without partitions (this script can re-partition the Target drive)
# 
# Note :
#  Mount by device (e.g. /dev/sda1), UUID and Volumn Label are supported, but "Volumn Label" not fully tested
#
#
TEST_RUN=false			## for Debug Only. If true : do not actually write change to disk


# Limitations :
# 1. Due to Chroot Grub-install, 32 bit target requires 32 bit host, while 64 bit target requires 64 bit host
# 2. /boot should not be on a separated partation
# 3. Only Debian & Ubuntu have been tested and found stable. CentOS tested, but not so reliable
# 4. In case restoring CentOS target, CentOS host is required due to dm-mapper.
#

# Exit Codes
# 0 	- exit normally
# 1		- user exit
# 2		- no target drive found
# 3		- backup archive does not exist
# 4		- fstab or grub.cfg or menu.lst not found in the backup archive
# 5		- Host system does not support the FileSystem
# 6		- Target system does not support the FileSystem (not implemented yet)
# 7		- No target partition found
# 8		- Target partition is mounted
# 9		- Directories missing in the restored target
# 10	- unknown command line argument(s)


clear 
echo "#########################################################################################################"
echo "#                                                                                                       #"
echo "#                                        W A R N I N G                                                  #"
echo "#                                                                                                       #"
echo "#                  This script will re-partition and format the selected TARGET drive.                  #"
echo "#           Please make sure that you select the correct TARGET DRIVE during script running.            #"
echo "#                                        Version : $VERSION                                                 #"
echo "#########################################################################################################"


# User Options (Please use command line arguments instead of directly editing these variables )
# V=======================================================================================================V
BACKUP=''						## Full path name to the backup archive
FORCE_FILESYSTEM=''				## Override the File System (ext2, ext3, ext4 etc.) found from $BACKUP/etc/fstab, (default '')
INSTALL_MBR=true				## if restore to the same disk where the backup was taken from, no need. (default true)
FORCE_UUID=false				## Force the Target's menu.lst/grub.cfg and fstab to use UUID
FORCE_DD=false					## Force to use dd to install MBR (default false)
ROOTPW=''						## New root password

REPART=false					## Re-partitioning the Target Disk ? (default false)
THRESHOLD=9000					## How large a disk (MB) that will be parted into 2 partitions ? (default 9000)
PRIMARY1_SIZE=2048				## If re-partitioning, how large (MB) is the 1st Primary Partition ? (default 2048)
SW_SIZE=0						## Swap Partition Size (MB) (default 0)

# ^==================================== End Of User Options ===============================================^
									

# V---------------------------------- Functions -----------------------------------V
echoc(){
	echo -n -e $1
	if [ $# -lt 3 ]; then
		echo "$2"
	else
		echo "$2" "$3"
	fi
	echo -n -e '\E[37;40m'
}


# Check the system is Debian or not
chk_distro(){
	local ishost=$1
	local distros=(Ubuntu Debian CentOS)
	local str isok=false
	for dis in ${distros[@]}
	do
		if [ $ishost = true ]; then 
			str=`cat /etc/issue | grep "$dis"`
		else
			str=`cat $TMP_DIR/etc/issue | grep "$dis"`
		fi 
		if ([ ! -z "$str" ]); then
			isok=true
			[ $ishost = true ] && HO_DISTRO=${dis} || TG_DISTRO=${dis}
			break
		fi 
	done
	if [ $isok = false ]; then 
		echoc $red "*** WARNING *** "
		echoc $red "This script has been tested in ${distros[*]} only."
		echoc $red "The result is unexpected in other host systems."
		inquire "  Are you sure to continue ?"
		echo
	fi
	if [ $ishost = true ]; then
		if ([ $HO_DISTRO = 'Debian' ] || [ $TG_DISTRO = 'Ubuntu' ]); then
			if [ $(is_installed 'uuid-runtime') -eq 0 ]; then 
				echo "We need to use 'uuidgen', but you have not installed it."
				echo "We can 'apt-get install uuid-runtime' for you."
				inquire "  Shall we do it ?"
				echo
			fi
		fi
	fi 
}



cmp_distro(){
	local isok=false 
	if ([ $HO_DISTRO = $TG_DISTRO ]); then isok=true; fi
	if [ $isok = false ]; then 
		if ([ $HO_DISTRO = 'Debian' ] && [ $TG_DISTRO = 'Ubuntu' ]); then isok=true; fi
		if ([ $HO_DISTRO = 'Ubuntu' ] && [ $TG_DISTRO = 'Debian' ]); then isok=true; fi
	fi 
	if [ $isok = false ]; then
		echo "      Debian/Ubuntu targets can be restored by Debian/Ubuntu/CentOS hosts".
		echo "      CentOS targets can only be restored by CentOS host (restoring CentOS is still not reliable)".
		inquire "      Are you sure to continue ?"
		echo
	fi
}


chk_kernel_support(){
	local file=`uname -r`
	local line fchar ret=0
	local upper
	
	upper=`echo $1 | tr "[:lower:]" "[:upper:]"`
	upper="CONFIG_"$upper"_FS="
	
	file="/boot/config-$file"
	line=`cat $file | grep "$upper"`
	if [ ! -z $line ]; then 
		fchar=`echo $line | awk '{print $1}' | cut -b 1`  
		if [ ! $fchar = '#' ]; then 
			ret=1
		fi
	fi
	echo $(($ret))
}



chk_progs(){
	local fs prg i
	fss=(reiserfs xfs)
	for fs in ${fss[@]}
	do 
		if [ $1 = ${fs} ]; then 
			if [ $(is_installed "$fs"progs) -eq 0 ]; then 	
				echoc $blue "    To support $fs, '"$fs"progs' needed to be installed."
				echoc $blue "    You can run 'apt-get install "$fs"progs' to get $fs support."
				inquire "    Shall we do it for you now ?" "no_exit"
				if [ $PROCEED = "y" ]; then 
					apt-get -y install "$fs"progs
				fi 
				echo
			fi
			if [ $1 = 'reiserfs' ]; then 
				echoc $blue "    For unknown issue, this script is still unable to support $1."
				echoc $blue "    If you proceed, you may most probably end-up with a unbootable target."
				inquire "    Shall we proceed now ?"
			fi 
		fi 
	done
}


is_installed(){
	local pkg=$1
	pkg=`dpkg --get-selections "$1" | grep "$1" | awk '{print $2}'`
	if ([ -z $pkg ] || [ ! $pkg = 'install' ]); then
		echo $((0))
	else
		echo $((1))
	fi
}



fstab_rfs(){
	local fs fchar partition rfs
	fss=(ext2 ext3 ext4 reiserfs xfs)
	while read line   
	do   
		fchar=`echo $line | awk '{print $1}'`
		if [ ! $fchar = "#" ]; then 
			partition=`echo $line | awk '{print $2}'`
			if [ $partition = "/" ]; then
				for fs in ${fss[@]}
				do
					rfs=`echo $line | awk '{print $3}'`
					if [ $rfs = ${fs} ]; then
						FSTAB_FS=${fs}
						break
					fi
				done
			fi
		fi 
		if [ ! -z $FMT_FS ]; then break; fi
	done < $TMP_DIR/etc/fstab
}


# Ask to proceed or exit
inquire(){
	local reply prompt=$1
	local no_exit=$2

	PROCEED="n";
	echoc $cyan -n "$prompt (yes, no) y/[n]: "
    read reply
    if [ -z $reply ]; then reply="n"; fi
    if [ $reply = "y" ]; then
		PROCEED=y
    fi
	if [ -z "$no_exit" ]; then 
		if [ $PROCEED = "n" ]; then
			echo
			echo "***  User exit. ***"
			echo
			exit 1
		fi
	fi 
}


# Find Source Disk - the boot disk
findsrc(){
	SOURCE=`mount | grep ' / ' | cut -b 1-9`
}



get_target(){
	local drives selected i src
	local read reply size str
	local defa=
	local tmpfile=$TMP_DIR/fdisk.output
	fdisk -l | grep "Disk /dev/" > $tmpfile

	src=`echo $SOURCE | cut -b 6-8`
	declare -a drives 
	while read line   
	do 
		drv=`echo $line | cut -b 11-13`
		if [ ! $drv = ${src} ]; then 
			size=${#drives[*]}
			drives[$size]=${drv}
		fi 
	done < $tmpfile
	
	size=${#drives[*]}
	if [ $size -eq 0 ]; then
		echoc $red "     No target drive found, exiting !"
		echo
		exit 2
	fi 

	
	# Set the default choice $defa, by trying not to use Windows drive
	# Loop 1 - try to find drive with no partition
	# Loop 2 - try to find drive with Linux Partition
	for loop in 1 2
	do 
		for i in ${drives[@]}
		do 
			drv=/dev/${i}1
			if [ $loop -eq 1 ]; then
				str=`fdisk -l /dev/$i | grep $drv`
				if [ -z "$str" ]; then 		# no partition, use it
					defa=${i}
					break
				fi
			else
				str=`fdisk -l /dev/$i | grep $drv | grep Linux`
				if [ ! -z "$str" ]; then 		# no partition, use it
					defa=${i}
					break
				fi
			fi 
		done 
		if [ ! -z $defa ]; then break; fi 
	done 
	if [ -z $defa ]; then defa=${drives[0]}; fi 

	while [ -z $TARGET_DRV ]
	do 
		echo -n "     Please choose the Target Drive (${drives[*]}) "
		read -p "[$defa]:" selected
		if [ -z $selected ]; then selected=${defa}; fi 
		
		for i in ${drives[@]}
		do 
			if [ $i = ${selected} ]; then
				TARGET_DRV=/dev/${selected}
			fi 
		done 
	done
}




# Find target disk and partition
findtge(){
	local tdev drv fs
	local tmpfile=$TMP_DIR/fdisk.output
	fdisk -l $TARGET_DRV > $tmpfile

	drv=`echo $TARGET_DRV | cut -b 1-8`
	tdev=${drv}1
	if [ ! $tdev = ${SOURCE} ]; then 
		drv_exist=`cat $tmpfile | grep "^$tdev"`
		if [ ! -z "$drv_exist" ]; then
			# verify the file system is Linux
			fs=`fdisk -l ${drv} | grep $tdev | grep Linux`
			if [ ! -z "$fs" ]; then
				TARGET=${tdev}
			else
				echo "     ${src}${drv}1 is not a Linux Partition !"
				echo "     use -p if you're sure you selected the correct target drive."
			fi 
		fi
	fi 
}


# Check if the target drive/partition is mount or not
chk_mnt(){
	local str
	str=`mount | grep $1`
	if [ -z "$str" ]; then
		IS_MNT=false
	else
		IS_MNT=true
	fi
}


# Show the target drive information
show_target(){
	local drv
	drv=`echo $TARGET | cut -b 1-8`
	echo '------------------------------------------------------'
	#fdisk -l $drv
	sfdisk -l -uM $drv
	echo '------------------------------------------------------'
}


# Check if backup archive exists
chk_backup(){
	if [ ! -e $BACKUP ]; then
		echoc $red "$BACKUP is not found, exiting."
		echo
		exit 3
	fi
}


# Format the target partition 
fmt_target(){
	local drv boot_uuid=''
	local cmd
	# Swap Partition
	if [ $SW_SIZE -gt 0 ]; then 
		SWAP_UUID=`uuidgen -r`
		drv=$TARGET_DRV$SW_PARTNO
		cmd="mkswap -L "swap-$SW_PARTNO" -U "$SWAP_UUID" $drv"
		echo "      $cmd" 
		echo 
		if [ $TEST_RUN = false ]; then
			$cmd
		fi 
	fi 
	
	# Primary 1 - root partition 
	if ([ $HO_DISTRO = 'Debian' ] || [ $HO_DISTRO = 'Ubuntu' ]); then 
		boot_uuid=`uuidgen -r`
	fi 
	if [ $FMT_FS = 'xfs' ]; then 
		cmd="mkfs.$FMT_FS -f $TARGET"
		echo "      $cmd"
	else 
		[ -z $boot_uuid ] && cmd="mkfs.$FMT_FS $TARGET" || cmd="mkfs.$FMT_FS -U "$boot_uuid" -L "/" $TARGET"
		echo "      $cmd"
	fi 
	echo
	if [ $TEST_RUN = false ]; then
		$cmd
	fi
	echo
}


# mount command
mount_it(){
	mount -t $FMT_FS -o rw,defaults $TARGET /mnt
}


# Restore 
restore(){
	# Check if something is mounted to /mnt, unmount it if necessary
	chk_mnt '/mnt'
	if [ $IS_MNT = true ]; then
		umount /mnt
	else 
		mkdir -p /mnt
	fi 
	# mount the target drive/partition to /mnt
	mount_it

	if [ $TEST_RUN = false ]; then 
		# restore
		cd /mnt
		tar xvpfz $BACKUP -C /mnt

		# make directories, otherwise boot up will fail
		mkdir -p /mnt/proc
		mkdir -p /mnt/lost+found
		mkdir -p /mnt/mnt
		mkdir -p /mnt/sys
		mkdir -p /mnt/home
	else
		echo "    tar xvpfz $BACKUP -C /mnt"
		echo "    mkdir -p /mnt/proc"
		echo "    mkdir -p /mnt/lost+found"
		echo "    mkdir -p /mnt/mnt"
		echo "    mkdir -p /mnt/sys"
		echo "    mkdir -p /mnt/home"
	fi
	echo
}



install_grub(){
	echo "    grub-install --root-directory=/mnt --no-floppy --recheck $TARGET_DRV"
	if [ $TEST_RUN = false ]; then 
		#cp $GRUBCFG $TMP_DIR/grub.cfg
		grub-install --root-directory=/mnt --no-floppy --recheck $TARGET_DRV
		#cp $GRUBCFG $GRUBCFG.new
		#cp $TMP_DIR/grub.cfg $GRUBCFG 
	fi 
}





grub_chroot(){
	local rootfs="/mnt"
	local chr_script=/tmp/grub.sh
	local run=false
	echo -n '' > $chr_script

	if ([ $MBR_BY_DD = false ] && [ $INSTALL_MBR = true ]); then 
		echo "grub-install --recheck --no-floppy $TARGET_DRV > /tmp/grub.install.log" >> $chr_script
		# dpkg-reconfigure grub-pc
		# update-grub 
		if [ $TARGET_NOGRUB = true ]; then 
			#echo 'grub-mkconfig -o /boot/grub/grub.cfg "$@"' >> $chr_script
			if [ -f /boot/grub/grub.cfg ]; then 
				echo 'grub-mkconfig -o /boot/grub/grub.cfg' >> $chr_script
			else
				echo 'grub-mkconfig -o /boot/grub/menu.lst' >> $chr_script
			fi 
		fi 
		run=true
	fi 
	if [ ! -z "$ROOTPW" ]; then
		echo "echo -e \"$ROOTPW\n$ROOTPW\" | (passwd)" >> $chr_script
		#echo "echo \"root:$ROOTPW\" | chpasswd" >> $chr_script
		run=true
	fi 
	echo "exit" >> $chr_script
	chmod +x $chr_script 
	
	# Note for Ubuntu 
	# https://bugs.launchpad.net/ubuntu/+source/grub2/+bug/526045
	# http://savannah.gnu.org/bugs/?8539
	# /proc/devices: No entry for device-mapper found - harmless but noisy

	if [ $run = true ]; then 
		# Mount virtual Kernel file systems and chroot.
		mount --bind /dev $rootfs/dev
		mount --bind /tmp $rootfs/tmp
		mount -t proc proc $rootfs/proc
		mount -t sysfs sysfs $rootfs/sys
		mount -t devpts devpts $rootfs/dev/pts
		mount -t tmpfs shm $rootfs/dev/shm
		cp /etc/resolv.conf $rootfs/etc/resolv.conf
		
		echo "    Chrooting into $rootfs... "
		if [ $TEST_RUN = false ]; then
			chroot $rootfs /bin/bash $chr_script
		fi 
		echo 
		echo "    Existing from chroot ... "
		
		if [ -d $rootfs/proc ]; then umount $rootfs/proc; fi
		if [ -d $rootfs/sys ]; then umount $rootfs/sys; fi
		if [ -d $rootfs/tmp ]; then umount $rootfs/tmp; fi
		if [ -d $rootfs/dev/pts ]; then umount $rootfs/dev/pts; fi
		if [ -d $rootfs/dev/shm ]; then umount $rootfs/dev/shm; fi
		if [ -d $rootfs/dev ]; then umount $rootfs/dev; fi
	fi 
}




# Check if the directories exists
verify_dirs(){
	local folder
	for folder in ${VERIFY[@]}
	do
		if [ ! -d /mnt/$folder ]; then
			VERIFY_OK=false
			break
		fi
	done 
}



chk_uuid(){
	local str
	str=`cat $1 | grep $LBL_MATCH`
	echo
	if [ ! -z "$str" ]; then
		USE_UUID=1					## use Label
	else
		str=`cat $1 | grep $UUID_MATCH`
		if [ ! -z "$str" ]; then
			USE_UUID=2				## use UUID
		fi 
	fi
	case $USE_UUID in
	1)
		echo "    $1 uses Volume Label for booting."
		;;
	2)
		echo "    $1 uses UUID for booting."
		;;
	*)
		echo "    $1 does not use Volume Label or UUID for booting."
		;;
	esac
}




change_uuid(){
	local OLD_UUID=''
	local NEW_UUID=
	local CFG_MENU=$1
	local name 
	
	if [ $USE_UUID -gt 0 ]; then 
		get_old_uuid $CFG_MENU
		echo "    $CFG_MENU's UUID is : $OLD_UUID"
		if [ $USE_UUID -eq 1 ]; then
			NEW_UUID=`tune2fs -l $TARGET | grep "Filesystem volume name:" | awk '{print $4}'`
			name="LABEL"
		else
			NEW_UUID=`tune2fs -l $TARGET | grep "Filesystem UUID:" | awk '{print $3}'`	
			name="UUID"
		fi 
		echo "    $TARGET's               $name is : $NEW_UUID"

		# if UUID is correct, just exit
		#if [ ! $NEW_UUID = ${OLD_UUID} ]; then
			echo "    We now change the $name of $TARGET ... "
			if [ $USE_UUID -eq 1 ]; then
				echo "    tune2fs $TARGET -L $OLD_UUID"
				if [ $TEST_RUN = false ]; then tune2fs $TARGET -L $OLD_UUID > /dev/null 2>&1; fi
			else
				echo "    tune2fs $TARGET -U $OLD_UUID"
				if [ $TEST_RUN = false ]; then tune2fs $TARGET -U $OLD_UUID > /dev/null 2>&1; fi
			fi 
		#fi
	fi
}



get_old_uuid(){
	local array 
	local element result
	local match 
	if [ $USE_UUID -eq 1 ]; then
		match=$LBL_MATCH
	else
		match=$UUID_MATCH
	fi 
	array=`cat $1 | grep $match`

	for element in ${array[@]}
	do
		result=`echo $element | grep $match`
		if [ ! -z "$result" ]; then
			if [ $USE_UUID -eq 1 ]; then
				OLD_UUID=`echo "$result" | cut -b 12-50`			## Volume Label
				OLD_UUID="$(echo $OLD_UUID | sed 's/\"//g')"		## remove "
			else
				OLD_UUID=`echo "$result" | cut -b 11-50`			## UUID
			fi 
			break
		fi 
	done
}



# some BIOS version do need a boot flag present on one partition
mkbootable(){
	local bootable drv
	echo "Checking boot flag of $TARGET ... "
	drv=`echo $TARGET | cut -b 1-8`
	bootable=`fdisk -l $drv | grep $drv | grep *`

	if [ -z "$bootable" ]; then
		echo -n "    Setting the boot flag of $TARGET ... "
		echo "a" > $TMP_DIR/fdisk.cmd
		echo "1" >> $TMP_DIR/fdisk.cmd
		echo "w" >> $TMP_DIR/fdisk.cmd
		echo "q" >> $TMP_DIR/fdisk.cmd
		if [ $TEST_RUN = false ]; then 
			fdisk $drv < $TMP_DIR/fdisk.cmd  > /dev/null 2>&1
			echo "done"
		else
			echo "bypassed"
			echo "    fdisk $drv < $TMP_DIR/fdisk.cmd  > /dev/null 2>&1"
		fi 
	fi
}


restore_mbr(){
	#local drv
	#drv=`echo $TARGET | cut -b 1-8`
	echo "    dd if=$TMP_DIR/tmp/mbr_backup/backup.mbr of=$TARGET_DRV count=1 bs=446  > /dev/null 2>&1"
	dd if=$TMP_DIR/tmp/mbr_backup/backup.mbr of=$TARGET_DRV bs=446 count=1 > /dev/null 2>&1
}


# ----------- repartitioning disk drive -----------
delepart(){
	local str size no ptr=9
	local cmdfile tmpfile
	tmpfile=$TMP_DIR/fdisk.output
	cmdfile=$TMP_DIR/delepart.cmd
	echo -n '' > $cmdfile
	
	declare -a partnos 
	fdisk -l $TARGET_DRV | grep $TARGET_DRV > $tmpfile
	
	while [ $ptr -gt 0 ]
	do
		str=`cat $tmpfile | grep $TARGET_DRV$ptr`
		if [ ! -z "$str" ]; then 
			size=${#partnos[*]}
			partnos[$size]=$ptr 
		fi
		ptr=$((ptr-1))
	done 
	
	size=${#partnos[*]}
	if [ $size -gt 0 ]; then 
		for no in ${partnos[@]}
		do 
			echo "d" >> $cmdfile
			echo $no >> $cmdfile
		done
		echo "w" >> $cmdfile
		echo "       deleting partitions : fdisk $TARGET_DRV < $cmdfile > /dev/null 2>&1"
		if [ $TEST_RUN = false ]; then 
			#fdisk $TARGET_DRV < $cmdfile
			fdisk $TARGET_DRV < $cmdfile > /dev/null 2>&1
		fi 
	fi
}



addparts(){
	local cy_size cy_num dsk_size_b dsk_size_m primary2_size remains
	local cur_part=1
	local cmdfile=$TMP_DIR/createpart.cmd
	echo -n '' > $cmdfile

	# if [ $(is_installed 'bc') -eq 1 ]; then						## fdisk seems using 1000KB as 1MB
		# PRIMARY1_SIZE=$(floating_maths $PRIMARY1_SIZE*1.024) 
		# SW_SIZE=$(floating_maths $SW_SIZE*1.024) 
	# fi 
	
	cy_size=`fdisk -l $TARGET_DRV | grep "Units = " | awk '{print $9}'`
	cy_num=`fdisk -l $TARGET_DRV | grep "sectors/track, " | awk '{print $5}'`
	dsk_size_b=`expr $cy_size \* $cy_num`			## Disk Size in Byte
	dsk_size_m=`expr $dsk_size_b / 1048576`			## Disk Szie in MB
	#dsk_size_m=`expr $dsk_size_b / 1000000`			## Disk Szie in MB

	if [ $dsk_size_m -ge $THRESHOLD ]; then
		NUM_PART=2
	fi 
	if [ $SW_SIZE -gt 0 ]; then NUM_PART=$((NUM_PART+1)); fi

	if [ $NUM_PART -gt 2 ]; then								## P1 + P2 + SWAP, 3 partitions
		primary2_size=`expr $dsk_size_m - $PRIMARY1_SIZE - $SW_SIZE`
		if [ $primary2_size -le 0 ]; then NUM_PART=$((NUM_PART-1)); fi
	fi 

	if ([ $NUM_PART -eq 2 ] && [ $SW_SIZE -gt 0 ]); then 		## P1 + SWAP only, 
		PRIMARY1_SIZE=`expr $dsk_size_m - $SW_SIZE`
		SW_PARTNO=2
	fi 
	if ([ $NUM_PART -eq 3 ] && [ $SW_SIZE -gt 0 ]); then 
		SW_PARTNO=3
	fi
	
	while [ $cur_part -le ${NUM_PART} ]
	do 
		echo "n" >> $cmdfile
		echo "p" >> $cmdfile
		echo "$cur_part" >> $cmdfile
		echo "" >> $cmdfile
		if [ $cur_part -eq ${NUM_PART} ]; then 
			echo "" >> $cmdfile
		else
			if [ $cur_part -eq 1 ]; then
				echo -n "+$PRIMARY1_SIZE" >> $cmdfile
			else
				echo -n "+$primary2_size" >> $cmdfile
			fi 
			echo "M" >> $cmdfile
		fi 
		cur_part=$((cur_part+1))
	done 
	echo "w" >> $cmdfile
	echo "       creating partitions : fdisk $TARGET_DRV < $cmdfile > /dev/null 2>&1"
	if [ $TEST_RUN = false ]; then 
		#fdisk $TARGET_DRV < $cmdfile
		fdisk $TARGET_DRV < $cmdfile > /dev/null 2>&1
	fi
}



floating_maths(){
	local val ret
	var=`echo "scale=4; $1" | bc`
	ret=`echo $var|awk '{print int($1+0.5)}'`
	echo $(($ret))	
}


# ----------------------------
umnt_drv(){
	local drv_part=$1
	local device
	local tmpfile=$TMP_DIR/mount.output
	cd ~

	# Umount, wait max. 20 x 3 seconds
	for try in {1..20}
	do 
		mount -l | grep $drv_part > $tmpfile
		if [ ! -s $tmpfile ]; then break; fi 
		while read line   
		do   
			device=`echo $line | awk '{print $1}'`
			umount $device > /dev/null 2>&1
		done < $tmpfile
		sleep 3
	done 
}


# Update fstab if FORCE_FILESYSTEM is used
upt_fstab_grub(){
	local ffstab=$1
	local grubfile old new char device 
	local tmpfile=$TMP_DIR/new/tmp_fstab
	local tempgrub=$TMP_DIR/new/tmp_grub
	local tmpgrub1=$TMP_DIR/new/tmp_grub1
	local output str pos
	local firstchar mntpt 
	local tmppath=`dirname $tmpfile`
	local useuuid=0
	local prekey=''
	local boot_name=''
	local swap_name=''
	local BLKUUID=''			## vairable changed by blkid_uuid
	local GRUB_DEVICE=''		## variable changed by grub_device
	local ESC_STR
	mkdir -p $tmppath
	echo -n '' > $tmpfile
	
	if ([ $USE_UUID -eq 2 ] || [ $FORCE_UUID = true ]); then
		useuuid=2
		prekey='UUID='
	elif [ $USE_UUID -eq 1 ]; then 
		useuuid=1
		prekey='LABEL='
	fi 

	if [ $useuuid -gt 0 ]; then
		blkid_uuid $TARGET $useuuid
		boot_name=${BLKUUID}
		if ([ -z "$boot_name" ]); then
			[ $useuuid = 2 ] && tune2fs -U time $TARGET || tune2fs -L "/" $TARGET
			blkid_uuid $TARGET $useuuid
			boot_name=${BLKUUID}
		fi 
		if [ $SW_PARTNO -gt 0 ]; then 
			[ $useuuid -eq 2 ] && swap_name=${SWAP_UUID} || swap_name="swap-$SW_PARTNO"
		fi 
	fi 
	
	# process fstab
	while read line
	do 
		output=''
		firstchar=`echo "$line" | awk '{print $1}' | cut -b 1-1`
		mntpt=`echo "$line" | awk '{print $2}'`
		if ([ ! $firstchar = '#' ] && [ "$mntpt" = '/' ]); then
			device=`echo "$line" | awk '{print $1}'`			## the device name to be used in replacing grub.cfg/menu.lst
			echo "#$line" >> $tmpfile
			for pos in {1..20}
			do
				case $pos in
				1) 	if [ -z "$boot_name" ]; then
						str=`echo "$line" | awk '{print $'$pos'}'` 
					else
						str="$prekey$boot_name"
					fi
					;;
				3) str=${FMT_FS}
					;;
				4) str="defaults,errors=remount-ro"
					;;
				*) str=`echo "$line" | awk '{print $'$pos'}'`
					;;
				esac
				if [ -z "$str" ]; then break; fi
				
				if [ -z "$output" ]; then 
					output=${str}
				else
					output=`echo -n -e "$output\t$str"`
				fi
			done
		elif ([ ! $firstchar = '#' ] && [ `echo "$line" | awk '{print $3}'` = 'swap' ]); then
			output="#$line"
		else
			output=${line}
		fi
		echo "$output" >> $tmpfile
		if ([ ! $firstchar = '#' ] && [ "$mntpt" = '/' ]); then
			# Add the mount for swap 
			if ([ $SW_PARTNO -gt 0 ] && [ ! -z "$swap_name" ]); then 
				echo -e "$prekey$swap_name\ttmpfs\tswap\tsw\t0\t0" >> $tmpfile
			fi 
		fi 
	done < $ffstab
	if [ $TEST_RUN = false ]; then 
		cp $ffstab $ffstab.bak
		cp $tmpfile $ffstab
	fi 


	# Update Grub.cfg or Menu.lst to use UUID
	# If originally used UUID, there is no need to change grub.cfg/menu.lst
	if [ $USE_UUID -ne 2 ]; then
		if [ ! -z "$boot_name" ]; then 
			[ -e "$GRUBCFG" ] && grubfile=${GRUBCFG} || grubfile=${MENULST}
			if [ $TARGET_NOGRUB = false ]; then
				GRUB_DEVICE=${device}
			else 
				grub_device $grubfile
			fi 
#inquire "Pause"
			
			# old device/label/uuid
			escape4sed $GRUB_DEVICE
			old=${ESC_STR}
			
			sed 's/'"root='(hd1,1)'"'/'"root='(hd0,0)'"'/g' <$grubfile > $tmpgrub1
			
			# new device/label/uuid
			escape4sed "root=$prekey$boot_name"
			new=${ESC_STR}
			#sed 's/'root=$old'/'"$new"'/g' <$grubfile > $tempgrub
			sed 's/'root=$old'/'"$new"'/g' <$tmpgrub1 > $tempgrub
			if [ $TEST_RUN = false ]; then 
				cp $grubfile $grubfile.bak
				cp $tempgrub $grubfile
			fi 
		fi 
	fi
#inquire "Pause"
}



escape4sed(){
	local pos char
	ESC_STR=''
	for pos in {1..128}
	do 
		char=`echo "$1" | cut -b $pos`
		if [ -z $char ]; then break; fi 
		if [ $char = '/' ]; then char='\/'; fi
		ESC_STR=$ESC_STR$char
	done 
}



grub_device(){
	local grubfile=$1
	local line fchar fword pos str
	
	while read line
	do 
		fchar=`echo "$line" | awk '{print $1}' | cut -b 1-1`
		if ([ ! $fchar = '#' ]); then
			fword=`echo "$line" | awk '{print $1}'`
			if ([ $fword = 'kernel' ] || [ $fword = 'linux' ]); then
				#for pos in 2 3 4 5 6 7 8 9 10 11 12
				for pos in {2..12}
				do 
					str=`echo "$line" | awk '{print $'$pos'}'`
					if [ ! -z `echo "$str" | grep "^root=UUID="` ]; then
						GRUB_DEVICE=`echo "$str" | cut -b 11-128`
						if [ ! -z "$GRUB_DEVICE" ]; then break; fi 
					elif [ ! -z `echo "$str" | grep "^root=LABEL="` ]; then
						GRUB_DEVICE=`echo "$str" | cut -b 12-128`
						if [ ! -z "$GRUB_DEVICE" ]; then break; fi 
					elif [ ! -z `echo "$str" | grep "^root="` ]; then
						GRUB_DEVICE=`echo "$str" | cut -b 6-128`
						if [ ! -z "$GRUB_DEVICE" ]; then break; fi 
					fi
				done 
			fi 
		fi 
	done < $grubfile
#inquire "Pause"
}




blkid_uuid(){
	local str str1 pos 
	local useuuid=$2
	
	BLKUUID=''				## variable defined in the calling function
	for pos in 2 3 1 4 5 6
	do 
		str=`blkid "$1" | awk '{print $'$pos'}'`
		if [ $useuuid -eq 2 ]; then 
			str1=`echo "$str" | grep "^UUID="`
			if [ ! -z "$str1" ]; then
				BLKUUID=`echo "$str1" | cut -b 7-42`
				break
			fi
		else
			str1=`echo "$str" | grep "^LABEL="`
			if [ ! -z "$str1" ]; then
				BLKUUID=`echo "$str1" | cut -b 8-43`
				BLKUUID="$(echo $BLKUUID | sed 's/\"//g')"			## remove "
				break
			fi
		fi
	done
}




# Parse agruments
usage(){
	echoc $blue "This script can restore/install a Linux system backup by the script 'backup-rfs'."
	echo "Tested hosts   : Ubuntu, Debian, CentOS"
	echo "Tested targets : Ubuntu, Debian, CentOS(not fully passed)"
	echo
	echo
	echo "Usage : `basename $0` -b=backup-file.tgz [-f=filesystem] [-m] [-g] [-u] [-r=new-pw] [-p] [-t=threshold-size] [-o=p1size] [-s=swapsize]"
	echo
	echo "  Restore arguments:"
	echo "    -b        : full path name to the backup file"
	echo "    -f        : force to use filesystem in 1st primary partition (default backup's fs)"
	echo "    -m        : do NOT install MBR (default install MBR). Usually you should install MBR."
	echo "    -d        : force to use dd to install MBR instead of Grub (default false)"
	echo "    -u        : force to use UUID in /boot/grub and /etc/fstab (default backup's settings)"
	echo "    -r        : Reset the root password to a new password. -m & -d will be ignored if -r is used."
	echo
	echo "  Re-partition arguments:"
	echo "    -p        : re-partition the target drive (default not to part)"
	echo "    -t        : how large (MB) a drive start to create 2nd primary partition (default 9000)"
	echo "    -o        : size of 1st primary partition in MB (default 2048)"
	echo "    -s        : swap partition size in MB (default 0, not to create swap partition)"
	echo
	exit 10
}


is_digit(){
	local nonums="$(echo $1 | sed 's/[0-9]//g')"
	if [ -z "$nonums" ] ; then
		echo $((1))
	else
		echo $((0))
	fi
}


parse_args(){
	local arg val
	local opt_tos=false
	if [ $# -lt 1 ]; then
		usage
	fi
	
	arg=$1
	while [ ! -z $arg ]
	do
		case `echo $arg | cut -b 1-2` in
		-b) BACKUP=`echo $arg | cut -b 4-128`
			;;
		-f) FORCE_FILESYSTEM=`echo $arg | cut -b 4-50`
			;;
		-m) INSTALL_MBR=false
			;;
		-p) REPART=true
			;;
		-t) val=`echo $arg | cut -b 4-30`
			[ $(is_digit $val) -eq 1 ] && THRESHOLD=${val} || usage 
			opt_tos=true
			;;
		-o) val=`echo $arg | cut -b 4-30`
			[ $(is_digit $val) -eq 1 ] && PRIMARY1_SIZE=${val} || usage 
			opt_tos=true
			;;
		-s) val=`echo $arg | cut -b 4-30`
			[ $(is_digit $val) -eq 1 ] && SW_SIZE=${val} || usage 
			opt_tos=true
			;;
		-u) FORCE_UUID=true
			;;
		-d) FORCE_DD=true
			;;
		-r) val=`echo $arg | cut -b 4-128`
			ROOTPW=${val}
			;;
		*) 	usage
			;;
		esac
		shift 
		arg=$1
	done 
	if ([ $opt_tos = true ] && [ $REPART = false ]); then
		echoc $blue "Without -p, arguments -t=???, -o=??? and -s=??? have no effect !"
	fi
	# if [ ! -z "$ROOTPW" ]; then 
		# if ([ $INSTALL_MBR = false ] || [ $FORCE_DD = true ]); then 
			# echoc $blue "With -r, arguments -m and -d will be ignored !"
			# INSTALL_MBR=true
			# FORCE_DD=false
		# fi 
	# fi 
	if [ $FORCE_UUID = false ]; then
		echoc $blue "Argument -u, use UUID in fstab/grub is the safest way for booting in this script."
		inquire "Do you want the script to set -u for you ?" "no exit"
		if [ $PROCEED = "y" ]; then FORCE_UUID=true; fi 
	fi 
	echo 
}


disp_result(){
	local cur_part size
	local tmpfile=$TMP_DIR/sfdisk.output
	local infofile=$TMP_DIR/restored.info
	sfdisk -l $TARGET_DRV -uM | grep $TARGET_DRV > $tmpfile
	echo -e "PartNo\tDevice\t\tFileSystem" > $infofile
	echo -e "P1:\t\t$TARGET\t\t$FMT_FS" >> $infofile
	
	cur_part=1
	while [ $cur_part -le $NUM_PART ]
	do 
		if [ $cur_part -eq 1 ]; then 
			size=`cat $tmpfile | grep $TARGET_DRV$cur_part | awk '{print $5'}`
			size=`echo $size | sed 's/\-//g'`
			echo " System restored to $TARGET_DRV$cur_part : $FMT_FS, $size"MB""
		else
			size=`cat $tmpfile | grep $TARGET_DRV$cur_part | awk '{print $4'}`
			size=`echo $size | sed 's/\-//g'`
			if [ $cur_part -eq 2 ]; then
				if ([ $SW_SIZE -gt 0 ] && [ $NUM_PART -eq 2 ]); then
					echo " Swap partition created $TARGET_DRV$cur_part : formatted as swap, $size"MB""
					echo -e "P$cur_part:\t\t$TARGET_DRV$cur_part\t\tswap" >> $infofile
				else
					echo " Partition created $TARGET_DRV$cur_part : not formatted, $size"MB""
					echo -e "P$cur_part:\t\t$TARGET_DRV$cur_part\t\tnone" >> $infofile
				fi
			else
				echo " Swap partition created $TARGET_DRV$cur_part : formatted as swap, $size"MB""
				echo -e "P$cur_part:\t\t$TARGET_DRV$cur_part\t\tswap" >> $infofile
			fi
		fi
		cur_part=$((cur_part+1))
	done 
	echo  " Information saved to $infofile"
}



disable_selinux(){
	local str
	local file=/mnt/etc/selinux/config
	mkdir -p $TMP_DIR/new
	if [ -f $file ]; then
		str=`cat $file | grep "SELINUX=enforcing" | grep -v "^#"`
		if [ ! -z "$str" ]; then 
			echo
			echo -n "    change 'enforcing' to 'permissive' ... "
			sed 's/'SELINUX=enforcing'/'SELINUX=permissive'/g' <$file > $TMP_DIR/new/selinux.conf
			if [ $TEST_RUN = false ]; then
				cp $file $file.bak
				cp $TMP_DIR/new/selinux.conf $file
			fi 
		fi
	fi
	echo "ok."
}


# ^---------------------------------End of functions ----------------------------------------^


# Public Variables
# V***********************************************V
SOURCE=''								## source drive/partition - the booting drive /dev/[sh]dx
TARGET_DRV=''							## The Target drive /dev/[sh]dx that repartitioning to be perform
TARGET=''								## target drive/partition - the drive/partition to be restored /dev/[sh]dx
FMT_FS=''								## format the target partition to what file system
FSTAB_FS=''								## Found file system from fstab (as a backup copy of FMT_FS)
IS_MNT=true								## is the target drive mounted
VERIFY_OK=true							## After restore, if the directories exist ?
PROCEED="n"								## Ask if proceed or not
MBR_BY_DD=false							## Restore MBR by dd, or grub-install
NUM_PART=1								## Number of partitions to be created in $TARGET_DRV
SW_PARTNO=0								## Swap partition number e.g. 3 for /dev/sda3
TARGET_NOGRUB=false						## if the target has no grub installed ?
SWAP_UUID=''							## Swap partition UUID
HO_DISTRO='unknown'						## The host distro
TG_DISTRO='unknown'						## The target distro

UUID_MATCH="root=UUID="					## The string matches for UUID in grub.cfg/menu.lst
LBL_MATCH="root=LABEL="					## The string matches for VOLUME LABEL in in grub.cfg/menu.lst
USE_UUID=0								## backup is using : 0 - boot by /dev/[sh]dx, 1 - by Volume Label, 2 - by UUID
GRUBCFG=/mnt/boot/grub/grub.cfg
MENULST=/mnt/boot/grub/menu.lst
TMP_DIR=/tmp/restore-rfs



VERIFY=(bin boot dev etc home lib lost+found opt proc root sbin sys usr var)		## some of the directories to be verified after restore
# ^***********************************************^


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

#parse arguments
parse_args $*

if [ $PRIMARY1_SIZE -gt $THRESHOLD ]; then PRIMARY1_SIZE=`expr $THRESHOLD`; fi

# Check the running system is Debian or not
chk_distro true

# Check if Back file exists
chk_backup


## Step 1. Extract some files from archives 
#-----------------------------------
# Extract /etc/fstab /boot/grub/grub.cfg /boot/grub/menu.lst to $TMP_DIR
echo -n "1. Checking $BACKUP, please wait ... "
rm -r $TMP_DIR > /dev/null 2>&1
mkdir -p $TMP_DIR
cd $TMP_DIR
# tar --extract --file=$BACKUP etc/fstab etc/issue etc/selinux/config \
							 # boot/grub/menu.lst boot/grub/grub.cfg boot/grub/grub.conf tmp/mbr_backup/backup.mbr \
							 # usr/mycode/mbr/backup.mbr > /dev/null 2>&1 
tar --extract --file=$BACKUP etc/fstab etc/issue \
							 boot/grub/menu.lst boot/grub/grub.cfg boot/grub/grub.conf tmp/mbr_backup/backup.mbr \
							 usr/mycode/mbr/backup.mbr > /dev/null 2>&1 
echo "ok."
if [ ! -e $TMP_DIR/etc/fstab ]; then
	echoc $red "    Backup archive has problem, missing fstab."
	 exit 4
fi 
if ([ ! -e "$TMP_DIR/boot/grub/menu.lst" ] && [ ! -e "$TMP_DIR/boot/grub/grub.cfg" ]); then
	TARGET_NOGRUB=true
	MBR_BY_DD=false 
	FORCE_UUID=true
	echoc $blue "    $BACKUP seems not to be containing a grub, "
	echoc $blue "    this script will installed it by 'grub-insall' and use UUID."
fi 
# if backup by old versions, backup.MBR location will be different, copy it to the new location
if ([ ! -e $TMP_DIR/tmp/mbr_backup/backup.mbr ] && [ -e $TMP_DIR/usr/mycode/mbr/backup.mbr ]); then
	mkdir -p $TMP_DIR/tmp/mbr_backup
	cp $TMP_DIR/usr/mycode/mbr/backup.mbr $TMP_DIR/tmp/mbr_backup/backup.mbr
fi 

if [ $FORCE_DD = true ]; then MBR_BY_DD=true;fi 
if ([ ! -e $TMP_DIR/tmp/mbr_backup/backup.mbr ]); then
	if [ $MBR_BY_DD = true ]; then 
		echoc $blue "    $BACKUP does not contain the MBR backup of the source disk."
		echoc $blue "    As no MBR backup, this script will restore MRB by using 'grub-insall'."
		MBR_BY_DD=false
	fi 
fi 
echo 

# Check target distro
chk_distro false
## Step 2, Check Host & Target Distro
#------------------------------------
echo "2. Checking host and target distro ... "
echo "     Host   : $HO_DISTRO `getconf LONG_BIT` bits"
echo "     Target : $TG_DISTRO"
cmp_distro
echo 



## Step 3, Check root file system
#-----------------------------------
echo -n "3. Checking the root file system ... "
fstab_rfs
if [ -z $FSTAB_FS ]; then 
	echo "fail, assumimg ext3."
	FMT_FS=ext3
else
	FMT_FS=${FSTAB_FS}
	echo $FMT_FS
fi 
if ([ ! -z $FORCE_FILESYSTEM ] && [ ! $FMT_FS = ${FORCE_FILESYSTEM} ]) ; then
	echo "    user option : forced to use $FORCE_FILESYSTEM"
	FMT_FS=${FORCE_FILESYSTEM}
fi

# Check Host System's kernel support this file system or not
if [ $(chk_kernel_support $FMT_FS) -eq 0 ]; then
	echoc $red "    This Host System does not support $FMT_FS, it cannot proceed."
	echo
	exit 5
fi 
chk_progs $FMT_FS
echo



## Step 4. Find the booting device 
#-----------------------------------
findsrc
echo "4. Find Booting device : $SOURCE !"
echo



## Step 5. Find target drive/partition
#-----------------------------------
echo "5. Looking for a target drive ... "
get_target
if [ $REPART = true ]; then
	inquire "     Repartitioning it ($TARGET_DRV) ? All data will be destroyed !"
	umnt_drv $TARGET_DRV
	delepart
	addparts
fi
echo


## Step 6. Find target partition
#-----------------------------------
echo "6. Trying to find the target partition ... "
findtge
if [ -z $TARGET ]; then
	echoc $red "     No target partition found, exiting !"
	echo
	exit 7
else
	echo "     Found target partition $TARGET !"
	echo
fi


## Step 6. Check if mounted
#-----------------------------------
echo -n "7. Double check if $TARGET is mounted ... "
chk_mnt $TARGET
if [ $IS_MNT = true ]; then
	echoc $red "yes, exiting."
	echo
	exit 8
else
	echo "no."
fi 	
echo


## Step 8. Show Target information and ask for comfirm
#-----------------------------------
echo "8. The target disk information is as below :"
show_target
inquire "   Is this the target drive you want to restore ?"
echo


## Step 9. Format the $TARGET
#-----------------------------------
echo "9. Format $TARGET to $FMT_FS file system ... "
fmt_target


## Step 10. Mount and Restore
#-----------------------------------
# check if /mnt is mounted by other devices
echo "10. Mount $TARGET to /mnt and restore ... "
restore
echo


# Step 11. Verify if the directories exists
#-----------------------------------
echo -n "11. Checking if the expected directories exist in the TARGET drive ... "
chk_mnt '/mnt'
if [ $IS_MNT = false ]; then
	mount_it
fi 
verify_dirs
if [ $VERIFY_OK = true ]; then
	echo "seems good."
else
	echoc $red "directory missing !"
	exit 9
fi
echo 



## Step 12. Install grub
#-----------------------------------
if ([ $INSTALL_MBR = true ]); then 
	if [ $MBR_BY_DD = true ]; then
		echo "11. Restoring MBR by dd ... "
		restore_mbr
	else 
		rm /tmp/grub.install.log > /dev/null 2>&1
		echo "12. Install GRUB to Target Drive ... "
		if ([ $TARGET_NOGRUB = true ]); then 
			install_grub
		fi 
		grub_chroot
		if ([ -f /tmp/grub.install.log ] && [ -z "`cat /tmp/grub.install.log | grep "No error"`" ]); then 
			echo
			echo "    chroot grub-install may be failed, try grub-install without chroot ..."
			install_grub
		else  
			if [ $TG_DISTRO = 'CentOS' ]; then
				if ([ $INSTALL_MBR = true ] && [ $MBR_BY_DD = false ]); then 
					install_grub
				fi 
			fi 
		fi 
	fi 
else
	echo "12. Install GRUB to Target Drive ... bypassed."
	if [ ! -z "$ROOTPW" ]; then grub_chroot; fi 
fi
echo


## Step 13. Disable SELINUX if necessary
echo -n "13. Checking SELinux policy ... "
disable_selinux
echo 


# Step 14. Change the UUID of the TARGET partition if necessary
#-----------------------------------
echo -n "14. Checking the UUID / Volume Label ... "
if [ $TARGET_NOGRUB = true ]; then
	echo "bypassed."
else 
	if [ -e "$GRUBCFG" ]; then 
		chk_uuid "$GRUBCFG"
		change_uuid "$GRUBCFG"
	else
		chk_uuid "$MENULST"
		change_uuid "$MENULST"
	fi
fi 
echo



# Step 15. Update Target /etc/fstab and /boot/grub/grub.cfg or menu.lst
#-----------------------------------
if [ -e $GRUBCFG ]; then 
	echo -n "15. Updating /mnt/etc/fstab and /mnt/boot/grub/grub.cfg ... "
else
	echo -n "15. Updating /mnt/etc/fstab and /mnt/boot/grub/menu.lst ... "
fi
upt_fstab_grub '/mnt/etc/fstab'
echo "ok."
echo




# Step 16. Umount /mnt
#-----------------------------------
echo -n "16. Waiting for $TARGET umounted ... "
umnt_drv $TARGET
chk_mnt $TARGET
if [ $IS_MNT = false ]; then 
	echo "ok".
else
	echo "fail."
fi 
echo
sleep 3


# Step 17. Check and set the boot flag of the target drive
#-----------------------------------
echo -n "17. "
mkbootable 
echo

echoc $blue "The Target drive is restored as $FMT_FS file system."
echoc $blue "Please review its /etc/fstab now."
echo
echo 
echo "Restore completed :" 
disp_result
echo

exit 0
