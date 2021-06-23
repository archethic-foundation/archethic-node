#!/bin/bash

echo "Install TPM Software Stack"

sudo apt -y update
sudo apt -y install \
  autoconf-archive \
  libcmocka0 \
  libcmocka-dev \
  procps \
  iproute2 \
  build-essential \
  git \
  pkg-config \
  gcc \
  libtool \
  automake \
  libssl-dev \
  uthash-dev \
  autoconf \
  doxygen \
  libjson-c-dev \
  libini-config-dev \
  libcurl4-openssl-dev \
  acl

git clone https://github.com/tpm2-software/tpm2-tss.git ~/tpm2-tss
cd ~/tpm2-tss
./bootstrap
./configure --with-udevrulesdir=/etc/udev/rules.d
make -j$(nproc)

sudo make install
sudo sed -i "s/tss/$(whoami)/gi" /etc/udev/rules.d/tpm-udev.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo ldconfig
sudo apt install tpm2-tools

cd ~
