#!/bin/bash
#
MYDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. $MYDIR/set-env.sh
ERASESIZE=$((128 * 1024))
cd $MYDIR

# ---------------------------------------------------------------
# create directories in parent directory
# ---------------------------------------------------------------
for i in download firmware
do
    if [ -d "$DVAEMUPARENT/$i" ]
    then
	echo "-----> directory $DVAEMUPARENT/$i already exists"
    else
	echo "-----> creating dir: $DVAEMUPARENT/$i"
	mkdir $DVAEMUPARENT/$i
	if [ "$?" != "0" ]
	then
	    echo "-----> ERROR in mkdir, aborting"
	    exit 1
	fi
    fi
done

# ---------------------------------------------------------------
# check for wget sha1sum binwalk jefferson unzip
# ---------------------------------------------------------------
for i in wget sha1sum binwalk jefferson unzip dd
do which $i
   ret=$?
   if [ ! "$ret" = "0" ]
   then
       echo "-----> $i not present, aborting"
       echo "-----> please install it" 
       if [ "$i" = "jefferson" ]
       then
	   echo "-----> look at https://github.com/sviehb/jefferson"
       fi  
       exit 1
   else
       echo "-----> $i found"
   fi
done

# ---------------------------------------------------------------
# download buildroot, firmware and specific kernel file
# ---------------------------------------------------------------
DOWNFILE[0]="buildroot-2014.02.tar.gz"
DOWNURL[0]="https://buildroot.org/downloads/buildroot-2014.02.tar.gz"
DOWNCKSUM[0]="6f52bfcabc5ab967d16c99215b88bffa4b0ca7fa"

DOWNFILE[1]="DVA-5592_A1_WI_20180405.zip"
DOWNURL[1]="https://media.dlink.eu/ftp/products/dva/dva-5592/driver_software/DVA-5592_A1_WI_20180405.zip"
DOWNCKSUM[1]="59d65fbd94e1c313f40abb45c0e360d908ebd547"

DOWNFILE[2]="linux-3.4.11-rt19.tar.gz"
DOWNURL[2]="https://git.kernel.org/pub/scm/linux/kernel/git/rt/linux-stable-rt.git/snapshot/linux-stable-rt-3.4.11-rt19.tar.gz"
DOWNCKSUM[2]="fc1b1151a2c402001a0d197ba1ecb8e662ef2ce8"

for i in ${!DOWNFILE[*]}
do
    F=$DVAEMUPARENT/download/${DOWNFILE[$i]}
    FCK=""
    URLCK=${DOWNCKSUM[$i]}
    if [ -e $F ]
    then
	FCK=`sha1sum $F | awk '{print $1}'`
	echo "-----> `basename $F` exits with checksum $FCK"
    fi
    if [ "$FCK" == "$URLCK" ]
    then
	echo "-----> `basename $F` alread downloaded, not downloading"
    else
	echo "-----> Downloading ${DOWNURL[$i]} to $F"
	wget -O $F ${DOWNURL[$i]}
	if [ "$?" != "0" ]
	then
	   echo "-----> ERROR downloading ${DOWNURL[$i]}, aborting"
	   exit 1
	fi
	FCK=`sha1sum $F | awk '{print $1}'`
	if [ "$FCK" != "$URLCK" ]
	then
	    echo "-----> ERROR downloading ${DOWNURL[$i]}, bad checksum, aborting"
	    exit 1
	fi
    fi
done

# ---------------------------------------------------------------
# extract buildroot
# ---------------------------------------------------------------
BRDIR=`echo ${DOWNFILE[0]}|sed "s/.tar.gz//"`
if [ -d  "$DVAEMUPARENT/$BRDIR" ]
then
    echo "-----> $DVAEMUPARENT/$BRDIR"
    echo "----->       already exists, skip untarring. Remove it to force untarring ${DOWNFILE[0]}"
else
    echo "-----> untarring ${DOWNFILE[0]}"
    tar -C $DVAEMUPARENT/ -xvf $DVAEMUPARENT/download/${DOWNFILE[0]}
    if [ "$?" != "0" ]
    then
	echo "-----> ERROR untarring ${DOWNFILE[0]}, aborting"
	exit 1
    fi
    echo "-----> patching buildroot"
    pushd "$DVAEMUPARENT/$BRDIR"
    patch -N -p1 < $MYDIR/001-buildroot-2014-02-fix-bzip2url.patch
    popd
fi


# ---------------------------------------------------------------
# extract firmware
# ---------------------------------------------------------------
FIRMFILE=`echo $DVAFIRM/${DOWNFILE[1]}|sed 's/.zip/.sig/'`
if [ -d $DVAFIRM/root ]
then
    echo "-----> firmware file already extracted"
    echo "-----> to force re-extraction remove $DVAFIRM/root and"
    echo "-----> remove $DVAFIRM/boot"
else
    echo "-----> extracting firmware, requires some time"
    unzip -o -d $DVAFIRM -e $DVAEMUPARENT/download/${DOWNFILE[1]}
    binwalk -e -C $DVAFIRM $FIRMFILE
    # ------ fix extracted root file system
    echo "-----> fix extracted root file system"
    CURRWD=`pwd`
    cd $DVAFIRM/_`basename ${FIRMFILE}`.extracted/jffs2-root/fs_3
    for i in `find . -maxdepth 1 -type l -print`;do mv $i ../fs_2/sbin/;done
    for i in `find . -maxdepth 1 -type f -print`;do mv $i ../fs_2/sbin/;done
    mv conf ../fs_2/www/
    mv sbin ../fs_2/usr/
    mv bin ../fs_2/usr/
    mv htdocs ../fs_2/www/
    mv lib ../fs_2/usr/
    mv nls ../fs_2/www/
    mv pages ../fs_2/www/
    mv share ../fs_2/usr/
    mv yapl ../fs_2/www/
    cd $DVAFIRM
    mv $DVAFIRM/_`basename ${FIRMFILE}`.extracted/jffs2-root/fs_2 root
    mv $DVAFIRM/_`basename ${FIRMFILE}`.extracted/jffs2-root/fs_1 boot
    rmdir $DVAFIRM/_`basename ${FIRMFILE}`.extracted/jffs2-root/fs_3
    rmdir $DVAFIRM/_`basename ${FIRMFILE}`.extracted/jffs2-root
    rm -rf $DVAFIRM/_`basename ${FIRMFILE}`.extracted
    cp -p $DVAFIRM/root/bin/busybox $DVAFIRM/root/sbin/init
    chmod 755 $DVAFIRM/root/sbin/init
    # ------ extract boot and root fs from firmware file
    echo "-----> extract boot and root fs from firmware file"
    dd if=${FIRMFILE} bs=256 skip=514 count=94720 of=$DVAFIRM/boot-root-fs.bin
    
    # ------ split boot and root partitions
    echo "-----> split boot and root partitions"
    PSPOS=`grep --byte-offset --only-matching --text YAPS-PartitionSplit $DVAFIRM/boot-root-fs.bin|awk -F: '{print $1}'`
    SPLITPOS=$(($PSPOS+256))
    BOOTROOTSIZE=`wc -c $DVAFIRM/boot-root-fs.bin|awk '{print $1}'`
    ROOTEND=$(($BOOTROOTSIZE - $ERASESIZE))
    ROOTLEN=$(($ROOTEND - $SPLITPOS))
    echo "         SPLITPOS:     $SPLITPOS"
    echo "         PSPOS:        $PSPOS"
    echo "         BOOTROOTSIZE: $BOOTROOTSIZE"
    echo "         ROOTEND:      $ROOTEND"
    echo "         ROOTLEN:      $ROOTLEN"
    
    # ------ extract boot partition image
    echo "-----> extract boot partition image"
    dd if=$DVAFIRM/boot-root-fs.bin of=$DVAFIRM/boot-fs.bin bs=256 count=$(($SPLITPOS / 256))
    
    # ------ extract root partition image, takes some time
    echo "-----> extract root partition image, takes some time"
    dd if=$DVAFIRM/boot-root-fs.bin of=$DVAFIRM/root-fs.bin bs=256 skip=$(($SPLITPOS / 256)) count=$(($ROOTLEN /256 ))
    
    # ------ extract end of file system marker
    echo "-----> extract end of file system marker"
    dd if=$DVAFIRM/boot-root-fs.bin of=$DVAFIRM/eofs.bin bs=256 skip=$(($ROOTEND / 256))
fi

cd $CURRWD


