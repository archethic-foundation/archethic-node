#!/bin/sh

FILENAME=`cat /sys/class/net/eno1/address`
echo Generating Keys - It may take a while...
./priv/c_dist/tpm_keygen > ~/$FILENAME 
echo Certified keys stored at ~/${FILENAME}

