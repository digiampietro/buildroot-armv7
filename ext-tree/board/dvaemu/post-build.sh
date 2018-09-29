#!/bin/bash
echo "parameters: $*" > /tmp/post-build.log
echo "DVAEMUDIR:        $DVAEMUDIR" >> /tmp/post-build.log
echo "BR2EXT:           $BR2EXT"    >> /tmp/post-build.log
echo "BRDIR:            $BRDIR"     >> /tmp/post-build.log
echo "BRIMAGES:         $BRIMAGES"  >> /tmp/post-build.log
echo "DVAROOT:          $DVAROOT"   >> /tmp/post-build.log
echo "DVAFIRM:          $DVAFIRM"   >> /tmp/post-build.log
ls $1 >> /tmp/post-build.log

DSTROOT="$1"
#--------------------------------------------------------------------
# configure eth0 up with dhcp #--------------------------------------------------------------------                                                                             
if grep eth0 $1/etc/network/interfaces >> /tmp/post-build.log
then
    echo "eth0 already configured" >> /tmp/post-build.log
else
    echo "configuring eth0 in interfaces" >> /tmp/post-build.log
    echo >> $DSTROOT/etc/network/interfaces
    echo "auto eth0" >> $1/etc/network/interfaces
    echo "iface eth0 inet dhcp" >> $1/etc/network/interfaces
    echo "  wait-delay 15" >> $1/etc/network/interfaces
fi
#--------------------------------------------------------------------
# copy DVA 5592 root file system
#--------------------------------------------------------------------
rsync -rav --delete $DVAROOT/ $DSTROOT/dva-root/
#--------------------------------------------------------------------
# copy DVA 5592 firmware files and scripts
#--------------------------------------------------------------------
mkdir $DSTROOT/dva-firm
cp $DVAFIRM/*.sig                      $DSTROOT/dva-firm/
cp $DVAFIRM/boot-fs.bin                $DSTROOT/dva-firm/
cp $DVAFIRM/root-fs.bin                $DSTROOT/dva-firm/
cp $DVAEMUDIR/qemu-run/set-nandsim.sh  $DSTROOT/dva-firm/

