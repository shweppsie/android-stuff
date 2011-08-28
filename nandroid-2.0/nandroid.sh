#!/bin/bash

# nandroid v2.0 - an Android backup tool for the G1 by infernix and brainaid

# Requirements:

# - a modded android in recovery mode
# - busybox in recovery mode
# - 'adb shell' support running as root
# - dump_image-arm compiled and in current working dir
# - mkyaffs2image|mkyaffs2image-$ARCH in current working dir
# - root on a linux/mac (POSIX) machine for constructing system and data images

# Using JF RC30 v1.2 recovery image works, RC8 v1.2 doesnt because of adb shell missing.
# You can flash RC30 v1.2 recovery.img on an RC8 v1.2 phone until the RC8 v1.2 recovery mode is fixed.

# Reference data:

# dev:    size   erasesize  name
#mtd0: 00040000 00020000 "misc"
#mtd1: 00500000 00020000 "recovery"
#mtd2: 00280000 00020000 "boot"
#mtd3: 04380000 00020000 "system"
#mtd4: 04380000 00020000 "cache"
#mtd5: 04ac0000 00020000 "userdata"

# We don't dump misc or cache because they do not contain any useful data that we are aware of at this time.


# Logical steps (v2.0):
#
# 0.  test for a target dir and the various tools needed, if not found then exit with error.
# 1.  check "adb devices" for a device in recovery mode. set DEVICEID variable to the device ID. abort when not found.
# 2.  mount system and data partitions read-only, set up adb portforward and create destdir
# 3.  check free space on /cache, exit if less blocks than 20MB free
# 4.  push required tools to device in /cache
# 5   for partitions boot recovery misc:
# 5a  get md5sum for content of current partition *on the device* (no data transfered)
# 5b  while MD5sum comparison is incorrect (always is the first time):
# 5b1 dump current partition to a netcat session
# 5b2 start local netcat to dump image to current dir
# 5b3 compare md5sums of dumped data with dump in current dir. if correct, contine, else restart the loop (6b1)
# 6   for partitions system data:
# 6a  get md5sum for tar of content of current partition *on the device* (no data transfered)
# 6b  while MD5sum comparison is incorrect (always is the first time):
# 6b1 tar current partition to a netcat session
# 6b2 start local netcat to dump tar to current dir
# 6b3 compare md5sums of dumped data with dump in current dir. if correct, contine, else restart the loop (6b1)
# 6c  if i'm running as root:
# 6c1 create a temp dir using either tempdir command or the deviceid in /tmp
# 6c2 extract tar to tempdir
# 6c3 invoke mkyaffs2image to create the img
# 6c4 clean up
# 7.  remove tools from device /cache
# 8.  umount system and data on device
# 9.  print success.


DEVICEID=foo
TOOLS="dump_image-arm" 

echo "nandroid v2.0"
# 0
if [ "$1" == "" ]; then
	echo "Usage: $0 destdir"
	echo "destdir will be created if it does not exist"
	exit 0
fi
DESTDIR=$1
if [ ! -d $DESTDIR ]; then 
	mkdir -p $DESTDIR
	if [ ! -d $DESTDIR ]; then 
		echo "error: cannot create $DESTDIR"
		exit 1
	fi
else
	touch $DESTDIR/.nandroidwritable
	if [ ! -e $DESTDIR/.nandroidwritable ]; then
		echo "error: cannot write to $DESTDIR"
		exit 1
	fi
	rm $DESTDIR/.nandroidwritable
fi
adb=`which adb`
if [ "$adb" == "" ]; then
	echo "error: adb not found in path."
	exit 1
fi

md5sum=`which md5sum`
if [ "$md5sum" == "" ]; then
	echo "error: md5sum not found in path."
	exit 1
fi
tar==`which tar`
if [ "$tar" == "" ]; then
	echo "error: tar not found in path."
	exit 1
fi
nc=`which nc`
if [ "$nc" == "" ]; then
	nc=`which netcat`
	if [ "$nc" == "" ]; then
		echo "error: nc nor netcat found in path."
		exit 1
	else
		nc=`which netcat`
	fi
fi

if [ -e `pwd`/mkyaffs2image-`uname -m` ]; then
	mkyaffs2image=`pwd`/mkyaffs2image-`uname -m`
fi
if [ -e `pwd`/mkyaffs2image ]; then
	mkyaffs2image=`pwd`/mkyaffs2image
fi
if [ "$mkyaffs2image" == "" ]; then
	echo "error: `pwd`/mkyaffs2image or mkyaffs2image-`uname -m` missing"
	echo "either use the provided binary or compile it in tartools/yaffs2/utils"
	exit 1
fi


for tool in $TOOLS; do
	if [ ! -e ./$tool ]; then
		echo "error: $tool not found in current dir"
		echo "either use the provided binary or cross-compile it for arm in nandtools/android-imagetools"
		exit 1
	fi
done

# 1
DEVICEID="`adb devices | grep recovery | awk '{ print $1 }'`"

if [ "$DEVICEID" == "foo" ]; then
	echo "error: no phone found in recovery mode. power off phone. press and hold home button, then power up. keep home button pressed. then try again."
	exit 1
fi

# 2.
echo "mounting system and data read-only on device"
adb shell mount -o ro /system
adb shell mount -o ro /data

# 3.
echo "checking free space on cache"
FREEBLOCKS="`adb shell df -k /cache| grep cache | awk '{ print $4 }'`"
# we need abolt 5MB for the tools plus max 8MB for the recovery + boot, so 20MB should be fine
if [ $FREEBLOCKS -le 20000 ]; then
	echo "error: not enough free space available on cache partition, aborting."
	adb shell umount /system
	adb shell umount /data
	exit 1
fi

# 4.
echo "pushing tools to /cache: "
for tool in $TOOLS; do 
	echo -n "    $tool..."
	out=`adb push ./$tool /cache/$tool 2>&1`
	echo "done"
done

# 5.
for image in boot recovery misc; do
	# 5a
	echo -n "Getting md5sum on device for $image..."
	DEVICEMD5=`adb shell "/cache/dump_image-arm $image - | md5sum" | awk '{ print $1 }'`
	echo "done ($DEVICEMD5)"
	sleep 1s
	MD5RESULT=1
	# 5b
	while [ $MD5RESULT -eq 1 ]; do
		# EDITED by Nathan Overall
		echo -n "Dumping $image from device to sdcard..."
		adb shell "/cache/dump_image-arm $image /sdcard/$image.img"
		echo "done"
		echo -n "Copying image file from sdcard to $DESTDIR/$image.img..."
		out=`adb pull "/sdcard/$image.img" "$DESTDIR/$image.img" 2>&1`
		echo "done [$out]"
		echo -n "Deleting image file from sdcard..."
		adb shell "rm /sdcard/$image.img"
		echo "done"
		# 5b3
		echo -n "Comparing md5sum..."
		echo "${DEVICEMD5}  $DESTDIR/$image.img" | md5sum --check --status -
		if [ $? -eq 1 ]; then
			echo "error: md5sum mismatch, retrying"
		else
			echo "md5sum verified for $image.img"
			MD5RESULT=0
		fi
	done
done

# 6
for image in system data cache; do
	# 6a
	echo -n "Getting md5sum on device for tar for $image..."
	DEVICEMD5=`adb shell "tar c -f - /$image 2>/dev/null | md5sum" | awk '{ print $1 }'`
	echo "done ($DEVICEMD5)"
	sleep 1s
	MD5RESULT=1
	# 6b
	while [ $MD5RESULT -eq 1 ]; do
		# EDITED by Nathan Overall
		echo -n "Dumping tar file for $image to sdcard..."
		out=`adb shell "tar c -f /sdcard/$image.tar /$image"`
		echo "done"
		echo -n "Copying tar file from sdcard to $DESTDIR/$image.tar..."
		out=`adb pull "/sdcard/$image.tar" "$DESTDIR/$image.tar" 2>&1`
		echo "done [$out]"
		echo -n "Deleting tar file from sdcard..."
		adb shell "rm /sdcard/$image.tar"
		echo "done"
		# 6b3
		echo -n "Comparing md5sum..."
		echo "${DEVICEMD5}  $DESTDIR/$image.tar" | md5sum --check --status -
		if [ $? -eq 1 ]; then
			echo "error: md5sum mismatch, retrying"
		else
			echo "md5sum verified for $image.tar"
			MD5RESULT=0
		fi
		
	done
	# 6c
	if [  "`whoami`" == "root" ]; then
		#  6c1
		TMPDIR=$DESTDIR/$DEVICEID-$image-tmp
		mkdir $TMPDIR
		# 6c2
		echo -n "Extracting $image.tar to $TMPDIR..."
		out=`tar x -C $TMPDIR -f $DESTDIR/$image.tar 2>&1`
		echo "done"
		# 6c3
		echo -n "Creating $image.img with mkyaffs2image..."
		$mkyaffs2image $TMPDIR/$image $DESTDIR/$image.img
		echo "done"
		# 6c4
		rm -rf $DESTDIR/$image.tar $TMPDIR

	else
		# 6d
		echo "To convert $image.tar to $image.img, run the following commands as root:"
		echo ""
		echo "mkdir /tmp/$DEVICEID-$image-tmp"
		echo "tar x -C /tmp/$DEVICEID-$image-tmp -f $DESTDIR/$image.tar"
		echo "$mkyaffs2image /tmp/$DEVICEID-$image-tmp/$image $DESTDIR/$image.img"
		echo ""
		echo "Make sure that /tmp/$DEVICEID-$image-tmp doesn't exist befor you extract, or use different paths."
		echo "Remember to remove the tmp dirs when you are done."
	fi
done


# 7.
echo "removing tools from /cache: "
for tool in $TOOLS; do 
	echo -n "    $tool..."
	adb shell rm /cache/$tool
	echo "done"
done

# 8.
echo "unmounting system and data on device"
adb shell umount /system
adb shell umount /data

# 9.
echo "Backup successful."
