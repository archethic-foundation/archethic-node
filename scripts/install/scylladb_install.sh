#!/bin/bash

echo "Install ScyllaDB"

sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 5e08fbd8b5d6ec9c

sudo curl -L --output /etc/apt/sources.list.d/scylla.list http://downloads.scylladb.com/deb/ubuntu/scylla-4.3-$(lsb_release -s -c).list

sudo apt-get update
sudo apt-get install -y scylla

sudo apt-get update
sudo apt-get install -y openjdk-8-jre-headless
sudo update-java-alternatives --jre-headless -s java-1.8.0-openjdk-amd64

cat <<EOF
disks:
  - mountpoint: /
      read_iops: 145539
      read_bandwidth: 2460177920
      write_iops: 84298
      write_bandwidth: 500473280
>> 

scylla_setup --no-raid-setup --no-kernel-check --no-verify-package --no-io-setup --no-memory-setup


