#!/bin/sh
TMPDATA=$(mktemp /tmp/data-XXXX.tmp)
TMPSIG=$(mktemp /tmp/sig-XXXX.tmp)
FIRMFILE=$1
FIRMFULLSIZE=`wc -c < $FIRMFILE`
FIRMDATASIZE=$(($FIRMFULLSIZE - 256))

#echo "full size: $FIRMFULLSIZE"
#echo "data size: $FIRMDATASIZE"

cp $FIRMFILE $TMPDATA
truncate -s $FIRMDATASIZE $TMPDATA
dd if=$FIRMFILE bs=1 skip=$FIRMDATASIZE  of=$TMPSIG 2>/dev/null

openssl dgst -sha1 -verify pubkey.pem -signature $TMPSIG $TMPDATA
rm $TMPSIG $TMPDATA


