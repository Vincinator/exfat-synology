#!/bin/sh

#usage 
#/bin/usbsync.sh [mountdevice] [mountpoint]
#/bin/usbsync.sh /dev/sdu1 /volume1/usbexfat/usbshare1


function CleanUpLog() {
	sed -i '/\ '"$t"'\ /d' $SysLog
}

function CheckRunning() {
	n=1
	c=0
	while ((n<=$(cat $SysLog | wc -l)))
	do
		PidInfo=$(cat $SysLog | sed -n "${n} p")
		SameDev=$(echo $PidInfo | grep "$MountDevice $MountPoint")
		SamePid=$(echo $PidInfo | grep "\[PID$PID\]")
		OldPid=$(echo $PidInfo | awk '{ print $1 }' | sed 's/\[PID//g' | sed 's/\]//g')
		t1=$(echo $PidInfo | awk '{ print $2 }')
		if [ -n "$SameDev" ]&&[ -z "$SamePid" ]&&[ -n "$OldPid" ]; then
			#usbsync already running
			if [ $(($t1-$t)) -lt 10 ]&&[ $(($PID-$OldPid)) -gt 0 ]; then
				CleanUpLog
				exit 0
			fi
		fi
		((n+=1))
	done
}
function CheckDisk() {
	echo "Disk"${DiskInfo#*"$DiskName"} > /tmp/usb.hash"$PID"
	DevInfo=$(fdisk -l | grep "$DevName")
	echo "Device "${DevInfo#*"$DevName"} >> /tmp/usb.hash"$PID"
	echo "USB Disk: $DiskName" > $DestDir/usbhash.log
	echo "Device: $DevName" >> $DestDir/usbhash.log
	UUID=$(md5sum /tmp/usb.hash"$PID" | awk '{ print $1 }')
	echo "USBHash: $UUID" >> $DestDir/usbhash.log
	rm -f /tmp/usb.hash"$PID"
}

function UmountDisk() {
	#auto unmount
	AutoUnmount=$(cat "$Settings" | grep 'AutoUnmount')
	AutoUnmount=${AutoUnmount#*:}
	if [ "$AutoUnmount" == "true" ]; then
		sleep 5
		/usr/syno/bin/synocheckshare.bin --vol-unmounting USB "$DevName" "$MountPoint"
		/bin/umount -l -k "$MountPoint"
		echo "Unmounted" "$MountPoint" >> $RsyncLog
		/sbin/eject -F "$DevName"
		echo "Ejected" "$DevName" >> $RsyncLog
		sleep 2
		ISEXFAT=$(echo "$MountPoint" | grep 'usbexfat')
		if [ -n "$ISEXFAT" ]; then
			rm -R "$MountPoint"
		fi
	fi
	echo >> $RsyncLog
	echo >> $RsyncLog
	echo >> $RsyncLog
	cat $RsyncLog >> $DestDir/import_history.log

	EXIFNAME="$DestDir/exifname.sh"
	if [ -f "$EXIFNAME" ]; then
		"$EXIFNAME" &
	fi
}

function DoRepl() {

	CheckDisk
	AutoSync=$(cat "$Settings" | grep 'AutoSync')
	AutoSync=${AutoSync#*:}
	if [ "$AutoSync" != "true" ]; then
		CleanUpLog
		return 0
	fi
	USBHash=$(cat "$Settings" | grep 'USBHash' | grep "$UUID")
	#if [ -z "$USBHash" ]; then
	#	CleanUpLog
	#	 exit 0
	#fi	

	RsyncLog=$DestDir/import_latest.log
	rm -f $RsyncLog
	FileExtension=$(cat "$Settings" | grep 'FileExtension')
	if [ -n "$FileExtension" ]; then
		FileExtension=${FileExtension#*:}
		FileExtension=($(echo "$FileExtension" | sed 's/*/\\*/g' | sed 's/;/ /g'))
		for s in ${FileExtension[@]}
		do
			if [ "$s" == "\*" ]||[ "$s" == "\*.\*" ]; then
				FileExtension=""
				break
			fi
		done
	else
		FileExtension=""
	fi

	#load history record
	OldFiles=$DestDir/\@eaDir/copied.log
	if [ ! -f "$OldFiles" ]; then
		touch "$OldFiles"
	fi
	AllFiles=/tmp/all.files"$PID".list
	NewFiles=/tmp/new.files"$PID".list
	SyncList=/tmp/sync.files"$PID".list
	if [ ! -d "$SrcDir" ]; then
		echo `date` > $RsyncLog
		echo "USBHash: $UUID" >> $RsyncLog
		echo "Found 0 New File(s) in" $SrcDir >> $RsyncLog
		UmountDisk
		sleep 5
		CleanUpLog
		return 0
	fi
	#save file list to AllFiles
	if [ -z "$FileExtension" ]; then
		#echo "find all"
		find $SrcDir -type f -name "*.*" | sed 's/ /\\ /g' | xargs ls -go --full-time | cut -c 14- > $AllFiles
	else
		rm -f $AllFiles
		for s in ${FileExtension[@]}
		do
			#echo "find $s"
			find $SrcDir -type f -name "*.*" | grep -i "\.$s$" | sed 's/ /\\ /g' | xargs ls -go --full-time | cut -c 14- >> $AllFiles
		done
	fi
	#cat $AllFiles
	#exit 0
	n=1
	c=0
	while ((n<=$(cat $AllFiles | wc -l)))
	do
		FileInfo=$(cat $AllFiles | sed -n "${n} p")
		if [ -n "$FileInfo" ]; then
			MainInfo=${FileInfo%%/*}`basename ${FileInfo#*/}`
			IsOldFile=`cat $OldFiles | grep "$(echo $MainInfo | sed 's/ /\\ /g')"`
			if [ -z "$IsOldFile" ]; then
				echo $MainInfo >> $NewFiles
				echo ${FileInfo#*$SrcDir/} >> $SyncList
				((c+=1))
			fi
		fi
		((n+=1))
	done
	#
	echo `date` > $RsyncLog
	echo "USBHash: $UUID" >> $RsyncLog
	echo "Found" $c "New File(s) in" $SrcDir >> $RsyncLog
	#sync new files
	if [ -f "$SyncList" ]; then
		rsync -av --files-from=$SyncList $SrcDir $DestDir >> $RsyncLog
		rm -f $SyncList
	fi
	#save list to OldFiles
	if [ -f "$NewFiles" ]; then
		cat $NewFiles >> $OldFiles
		rm -f $NewFiles
	fi
} 


#require settingss
DefaultDir=/volume1/PhotoImported
Settings=$DefaultDir/usbsync.cfg
if [ ! -f "$Settings" ]; then
	exit 0
fi	
MountDevice="$1"
MountPoint="$2"
PID="$$"
t=$(date +%s)
SysLog=/tmp/usbsync.running
echo "[PID$PID] $t $MountDevice $MountPoint" >> $SysLog

sleep 2


CheckRunning
ls -r "$MountPoint"
DevName=$(/bin/mount.bin | grep "$(dirname $MountPoint)/$(basename $MountPoint)" | awk '{ print $1 }')
DiskName=$(echo "$DevName" | sed 's/[0-9]//g')
#load settings


# 1) Photo Import


SourceDirPhoto=$(cat "$Settings" | grep 'SourceDirPhoto')
if [ -n "$SourceDirPhoto" ]; then
	SrcDir=$MountPoint/${SourceDirPhoto#*:}
else
	SrcDir=$MountPoint/
fi
ImportDirPhoto=$(cat "$Settings" | grep 'ImportDirPhoto')
if [ -n "$ImportDirPhoto" ]; then
	DestDir=${ImportDirPhoto#*:}
else
	DestDir=$DefaultDir
fi
if [ ! -d "$DestDir" ]; then
	mkdir -p "$DestDir"
fi


DoRepl

rm -f $AllFiles

# 2) Video Import
SourceDirVideo=$(cat "$Settings" | grep 'SourceDirVideo')
if [ -n "$SourceDirVideo" ]; then
	SrcDir=$MountPoint/${SourceDirVideo#*:}
else
	echo "Import Photo Dir is not set" >> $RsyncLog
	return 0
fi

ImportDirVideo=$(cat "$Settings" | grep 'ImportDirVideo')
if [ -n "$ImportDirVideo" ]; then
	DestDir=${ImportDirVideo#*:}
else 
	echo "Import Video Dir is not set" >> $RsyncLog
	return 0
fi
if [ ! -d "$DestDir" ]; then
	mkdir -p "$DestDir"
fi


DoRepl

# 3) Cleanup ...

rm -f $AllFiles
UmountDisk
sleep 10
CleanUpLog
