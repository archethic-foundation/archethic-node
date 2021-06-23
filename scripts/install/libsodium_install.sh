#!/bin/bash

echo "Install Libsodium"

if [[ $(ls /usr/local/lib | grep -c 'libsodium') -gt 0 ]]; then
  echo "Libsodium already installed"
else
 wget -O ~/libsodium-stable.tar.gz https://download.libsodium.org/libsodium/releases/LATEST.tar.gz
 tar zxvf ~/libsodium-stable.tar.gz -C ~/
 cd ~/libsodium-stable
 ./configure
 make
 sudo make install
 sudo ldconfig
 cd ~
fi

