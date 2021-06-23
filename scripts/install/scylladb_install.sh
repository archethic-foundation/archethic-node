#!/bin/bash

echo "Install ScyllaDB"

sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 5e08fbd8b5d6ec9c

sudo curl -L --output /etc/apt/sources.list.d/scylla.list http://downloads.scylladb.com/deb/ubuntu/scylla-4.3-$(lsb_release -s -c).list

sudo apt-get update
sudo apt-get install -y scylla

sudo apt-get update
sudo apt-get install -y openjdk-8-jre-headless
sudo update-java-alternatives --jre-headless -s java-1.8.0-openjdk-amd64

sudo scylla_setup --no-raid-setup --no-ec2-check --no-kernel-check --no-verify-package --no-sysconfig-setup --io-setup=1 --no-version-check --no-cpuscaling-setup --no-fstrim-setup --no-memory-setup --no-swap-setup

sudo scylla_memory_setup --memory=8G
sudo scylla_cpuset_setup --cpuset 2

sudo systemctl start scylla-server
nodetool status




