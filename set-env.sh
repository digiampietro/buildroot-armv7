#!/bin/bash
export DVAEMUDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export DVAEMUPARENT="$( cd $DVAEMUDIR/.. && pwd )"
export BR2EXT="$DVAEMUDIR/ext-tree"
export BRDIR="$( cd $DVAEMUDIR/../buildroot-2* && pwd )"
export BRIMAGES=$BRDIR/output/images
export DVAFIRM=$DVAEMUPARENT/firmware
export DVAROOT=$DVAFIRM/root
export SYSROOT=$BRDIR/output/target
export TOOLBIN=$BRDIR/output/host/usr/bin

echo "DVAEMUDIR:        $DVAEMUDIR"
echo "DVAEMUPARENT:     $DVAEMUPARENT"
echo "BR2EXT:           $BR2EXT"
echo "BRDIR:            $BRDIR"
echo "BRIMAGES:         $BRIMAGES"
echo "DVAFIRM:          $DVAFIRM"
echo "DVAROOT:          $DVAROOT"
echo "SYSROOT:          $SYSROOT"
echo "TOOLBIN:          $TOOLBIN"


