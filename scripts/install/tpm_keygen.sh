#!/bin/sh

FILENAME=`cat /sys/class/net/eno1/address`
echo "Generating Keys - It may take 3-4 minutes"
./priv/c_dist/tpm/keygen $FILENAME

