#!/bin/bash

echo "Install Libsodium"

if [[ $(ls /usr/local/lib | grep -c 'libsodium') -gt 0 ]]; then
  echo "Libsodium already installed"
else
  wget https://download.libsodium.org/libsodium/releases/LATEST.tar.gz && \
    tar zxvf LATEST.tar.gz && \
    cd libsodium-stable && \
    ./configure && \
    make && make install && \
    ldconfig
fi

