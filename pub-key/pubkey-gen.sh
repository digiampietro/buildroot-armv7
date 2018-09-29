#!/bin/bash
#
# Generate a pem file based on the following inputs
#   1. asn1 definition file
#   2. binary file with Multi Precision Integer modulus
#   3. binary file with Multi Precision Integer exponent
# Output files:
#   pubkey.der  (in DER format)
#   pubkey.pem  (in PEM format)
#
ASN=$1
MOD=$2
EXP=$3

if [ "$ASN" == "" ]
then
    echo "Missing argument files"
    exit 1
fi


if [ ! -e $ASN ]
then
    echo "$ASN not found"
    exit 1
fi

if [ ! -e $MOD ]
then
    echo "$MOD not found"
    exit 1
fi

if [ ! -e $MOD ]
then
    echo "$MOD not found"
    exit 1
fi

MODSIZE=`wc -c < $MOD`
EXPSIZE=`wc -c < $EXP`
echo modsize: $MODSIZE
echo expsize: $EXPSIZE

# generate ASN file

cat $ASN | sed  "s/%%MODULUS%%/$(xxd -ps -c $MODSIZE $MOD)/" \
         | sed  "s/%%EXPONENT%%/$(xxd -ps -c $EXPSIZE  $EXP)/"  \
       > $ASN.out

openssl asn1parse -genconf $ASN.out -out pubkey.der -noout
openssl rsa -in pubkey.der -inform der -pubin -out pubkey.pem
